extends Node
## LAN / Hamachi server discovery over UDP port 7778.
##
## Host side: every second a small JSON beacon is broadcast out of EVERY local IPv4 adapter
## (directed broadcast per adapter + 255.255.255.255 + loopback), and unicast "discover"
## queries are answered immediately to the query's source address/port.
## Client side: listen on 7778 (or an ephemeral port when 7778 is taken, e.g. a second game
## instance on the same PC), send discover queries periodically out of every adapter, keep a
## list of servers, measure ping from query -> reply and drop servers after ~4 s of silence.

signal servers_changed

const PORT := 7778
const GAME_ID := "RADIO_SILENCE"
const VERSION := 1
const BEACON_INTERVAL := 1.0
const QUERY_INTERVAL := 1.5
const TIMEOUT_MS := 4000
const ADAPTER_REFRESH := 5.0
const MAX_PACKET := 1400

## Host side: returns the beacon fields {name, port, map, players, max, size, in_game}.
var info_provider: Callable = Callable()
var hosting := false
var browsing := false
## Port the shared listening socket is bound to (PORT, or an ephemeral fallback; 0 = closed).
var listen_port := 0

var _listen: PacketPeerUDP = null
var _senders: Array[PacketPeerUDP] = []
var _sender_targets: Array[PackedStringArray] = []
var _adapters: PackedStringArray = PackedStringArray()
var _beacon_t := 0.0
var _query_t := 0.0
var _adapter_t := 0.0
var _emit_t := 0.0
var _servers: Dictionary = {}   # key -> server Dictionary
var _dirty := false
var _instance_id := ""
var _answered: Dictionary = {}   # query keys answered since the last beacon


func _init() -> void:
	_instance_id = "%08x%08x" % [randi(), Time.get_ticks_usec() & 0x7fffffff]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(hosting or browsing)   # start_*() may run before _ready()


func _exit_tree() -> void:
	_close_all()


# ---------------------------------------------------------------- public API

func start_host() -> void:
	hosting = true
	_open()
	_beacon_t = 0.0


func stop_host() -> void:
	hosting = false
	_maybe_close()


func start_browse() -> void:
	browsing = true
	_servers.clear()
	_open()
	_query_t = 0.0
	_dirty = true


func stop_browse() -> void:
	browsing = false
	_servers.clear()
	_maybe_close()


## Ask a specific address directly (e.g. a typed-in Hamachi IP) in addition to broadcasts.
func query_address(ip: String) -> void:
	if _listen == null or ip == "":
		return
	_send_to(_listen, ip, PORT, _query_packet())


## Known servers, sorted by name. Each: {key, id, name, ip, port, map, players, max, size,
## in_game, ping (ms, -1 unknown), seen (ticks ms)}.
func get_servers() -> Array:
	var out: Array = []
	for k: String in _servers:
		var s: Dictionary = _servers[k]
		out.append(s.duplicate())
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("name", "")) < str(b.get("name", "")))
	return out


func get_server(key: String) -> Dictionary:
	var s: Dictionary = _servers.get(key, {})
	return s.duplicate()


## Usable local IPv4 addresses (no loopback / link-local).
static func local_ipv4() -> PackedStringArray:
	var out := PackedStringArray()
	for a: String in IP.get_local_addresses():
		if a.count(".") != 3 or a.begins_with("127.") or a.begins_with("169.254.") or a == "0.0.0.0":
			continue
		if not out.has(a):
			out.append(a)
	return out


static func address_label(a: String) -> String:
	var p := a.split(".")
	if p.size() != 4:
		return "?"
	var o0 := int(p[0])
	var o1 := int(p[1])
	if o0 == 25 or o0 == 26:
		return "Hamachi"
	if o0 == 10 or (o0 == 192 and o1 == 168) or (o0 == 172 and o1 >= 16 and o1 <= 31):
		return "LAN"
	if o0 == 100 and o1 >= 64 and o1 <= 127:
		return "VPN"
	return "Network"


## "192.168.1.5 (LAN), 25.12.34.56 (Hamachi)" - Hamachi addresses listed first.
static func describe_addresses() -> String:
	var parts := PackedStringArray()
	var rest := PackedStringArray()
	for a: String in local_ipv4():
		var lab := address_label(a)
		if lab == "Hamachi":
			parts.append("%s (%s)" % [a, lab])
		else:
			rest.append("%s (%s)" % [a, lab])
	parts.append_array(rest)
	return ", ".join(parts) if parts.size() > 0 else "no network adapters found"


## Directed broadcast addresses to try for one adapter (Godot gives no netmask, so guess).
static func broadcast_targets(a: String) -> PackedStringArray:
	var out := PackedStringArray()
	var p := a.split(".")
	if p.size() != 4:
		return out
	var o0 := int(p[0])
	if o0 == 25 or o0 == 26:
		out.append("%d.255.255.255" % o0)          # Hamachi is a /8
	elif o0 == 10:
		out.append("10.255.255.255")
		out.append("%s.%s.%s.255" % [p[0], p[1], p[2]])
	else:
		out.append("%s.%s.%s.255" % [p[0], p[1], p[2]])
	out.append("255.255.255.255")
	return out


# ---------------------------------------------------------------- sockets

func _open() -> void:
	if _listen == null:
		_listen = PacketPeerUDP.new()
		_listen.set_broadcast_enabled(true)
		var err := _listen.bind(PORT, "0.0.0.0")
		if err != OK:
			err = _listen.bind(PORT, "*")
		if err != OK:
			# 7778 is taken (another instance on this PC) - an ephemeral port still gets
			# unicast replies to our queries.
			_listen.close()
			err = _listen.bind(0, "0.0.0.0")
		if err != OK:
			push_warning("Discovery: could not open a UDP socket (error %d)" % err)
			_listen = null
			listen_port = 0
		else:
			listen_port = _listen.get_local_port()
		_adapters = PackedStringArray()
		_adapter_t = 0.0
	_refresh_adapters()
	set_process(true)


func _refresh_adapters() -> void:
	var now := local_ipv4()
	if now == _adapters:
		return
	_adapters = now
	for s: PacketPeerUDP in _senders:
		s.close()
	_senders.clear()
	_sender_targets.clear()
	for a: String in _adapters:
		var s := PacketPeerUDP.new()
		s.set_broadcast_enabled(true)
		if s.bind(0, a) != OK:
			continue
		_senders.append(s)
		_sender_targets.append(broadcast_targets(a))


func _maybe_close() -> void:
	if not hosting and not browsing:
		_close_all()


func _close_all() -> void:
	if _listen != null:
		_listen.close()
		_listen = null
	listen_port = 0
	for s: PacketPeerUDP in _senders:
		s.close()
	_senders.clear()
	_sender_targets.clear()
	_adapters = PackedStringArray()
	set_process(false)


func _send_to(sock: PacketPeerUDP, ip: String, port: int, pkt: PackedByteArray) -> void:
	if sock.set_dest_address(ip, port) == OK:
		sock.put_packet(pkt)


## Send out of every adapter (directed + limited broadcast), the default route and loopback.
func _broadcast(pkt: PackedByteArray) -> void:
	for i in _senders.size():
		var s: PacketPeerUDP = _senders[i]
		for t: String in _sender_targets[i]:
			_send_to(s, t, PORT, pkt)
	if _listen != null:
		_send_to(_listen, "255.255.255.255", PORT, pkt)
		if listen_port != PORT:
			_send_to(_listen, "127.0.0.1", PORT, pkt)    # a same-PC instance holds 7778


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	_adapter_t -= delta
	if _adapter_t <= 0.0:
		_adapter_t = ADAPTER_REFRESH
		_refresh_adapters()
	if _listen != null:
		_poll(_listen)
	for s: PacketPeerUDP in _senders:
		_poll(s)
	if hosting:
		_beacon_t -= delta
		if _beacon_t <= 0.0:
			_beacon_t = BEACON_INTERVAL
			_answered.clear()
			_broadcast(_beacon_packet(-1))
	if browsing:
		_query_t -= delta
		if _query_t <= 0.0:
			_query_t = QUERY_INTERVAL
			_broadcast(_query_packet())
		_prune()
		_emit_t -= delta
		if _dirty or _emit_t <= 0.0:
			_dirty = false
			_emit_t = 1.0
			servers_changed.emit()


func _query_packet() -> PackedByteArray:
	var q := {"game": GAME_ID, "v": VERSION, "q": "discover", "t": Time.get_ticks_msec(), "id": _instance_id}
	return JSON.stringify(q).to_utf8_buffer()


func _beacon_packet(echo_t: int) -> PackedByteArray:
	var info: Dictionary = {}
	if info_provider.is_valid():
		var r: Variant = info_provider.call()
		if typeof(r) == TYPE_DICTIONARY:
			info = r
	var b := {
		"game": GAME_ID, "v": VERSION, "id": _instance_id,
		"name": str(info.get("name", "Host")).substr(0, 24),
		"port": int(info.get("port", 7777)),
		"map": int(info.get("map", 0)),
		"players": int(info.get("players", 1)),
		"max": int(info.get("max", 8)),
		"size": int(info.get("size", 2)),
		"in_game": bool(info.get("in_game", false)),
	}
	if echo_t >= 0:
		b["t"] = echo_t
		b["reply"] = true
	return JSON.stringify(b).to_utf8_buffer()


func _poll(sock: PacketPeerUDP) -> void:
	var guard := 0
	while sock.get_available_packet_count() > 0 and guard < 64:
		guard += 1
		var pkt := sock.get_packet()
		var ip := sock.get_packet_ip()
		var port := sock.get_packet_port()
		if pkt.size() == 0 or pkt.size() > MAX_PACKET:
			continue
		if OS.has_environment("RS_DISCOVERY_DEBUG"):
			print("discovery[%s h=%s b=%s] got %d bytes from %s:%d: %s" % [_instance_id, hosting, browsing, pkt.size(), ip, port, pkt.get_string_from_utf8()])
		var parsed: Variant = JSON.parse_string(pkt.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = parsed
		if str(d.get("game", "")) != GAME_ID or int(d.get("v", 0)) != VERSION:
			continue
		if d.has("q"):
			if hosting and str(d.get("q", "")) == "discover" and ip != "" and port > 0:
				var t := int(d.get("t", -1))
				# one query arrives via several broadcast paths: answer each source once
				var rk := "%s:%d:%d:%s" % [ip, port, t, str(d.get("id", ""))]
				if not _answered.has(rk):
					_answered[rk] = true
					_send_to(sock, ip, port, _beacon_packet(t))
		elif browsing:
			_on_beacon(d, ip)


func _on_beacon(d: Dictionary, ip: String) -> void:
	if ip == "":
		return
	if ip.begins_with("::ffff:"):
		ip = ip.substr(7)
	var now := Time.get_ticks_msec()
	var port := int(d.get("port", 7777))
	var id := str(d.get("id", ""))
	if id == "":
		id = ip
	var key := "%s:%d" % [id, port]
	var s: Dictionary = _servers.get(key, {})
	var is_new := s.is_empty()
	if is_new:
		s = {"key": key, "id": id, "ping": -1, "addrs": {}}
	var addrs: Dictionary = s["addrs"]
	addrs[ip] = now
	s["seen"] = now
	s["port"] = port
	s["name"] = str(d.get("name", "Host")).substr(0, 24)
	s["map"] = int(d.get("map", 0))
	s["players"] = int(d.get("players", 1))
	s["max"] = int(d.get("max", 8))
	s["size"] = int(d.get("size", 2))
	s["in_game"] = bool(d.get("in_game", false))
	if bool(d.get("reply", false)) and d.has("t"):
		var rtt: int = maxi(0, now - int(d.get("t", now)))
		var old: int = int(s.get("ping", -1))
		s["ping"] = rtt if old < 0 else int(round(old * 0.5 + rtt * 0.5))
	var before := str(s.get("ip", ""))
	s["ip"] = _best_addr(addrs, now)
	_servers[key] = s
	if is_new or before != str(s["ip"]):
		_dirty = true


## Prefer an address on one of our own subnets, then anything non-loopback, then loopback.
func _best_addr(addrs: Dictionary, now: int) -> String:
	var best := ""
	var best_score := -1
	for a: String in addrs:
		if now - int(addrs[a]) > TIMEOUT_MS:
			continue
		var score := 1
		if a.begins_with("127."):
			score = 0
		elif _on_local_subnet(a):
			score = 2
		if score > best_score:
			best_score = score
			best = a
	return best


func _on_local_subnet(a: String) -> bool:
	var p := a.split(".")
	if p.size() != 4:
		return false
	for mine: String in _adapters:
		var m := mine.split(".")
		if m.size() != 4:
			continue
		if a == mine:
			return true
		var slash8 := m[0] == "25" or m[0] == "26" or m[0] == "10"
		if slash8 and p[0] == m[0]:
			return true
		if p[0] == m[0] and p[1] == m[1] and p[2] == m[2]:
			return true
	return false


func _prune() -> void:
	var now := Time.get_ticks_msec()
	for k: String in _servers.keys():
		var s: Dictionary = _servers[k]
		if now - int(s.get("seen", 0)) > TIMEOUT_MS:
			_servers.erase(k)
			_dirty = true
		else:
			var addrs: Dictionary = s["addrs"]
			for a: String in addrs.keys():
				if now - int(addrs[a]) > TIMEOUT_MS:
					addrs.erase(a)
			var ip := _best_addr(addrs, now)
			if ip != str(s.get("ip", "")):
				s["ip"] = ip
				_dirty = true
