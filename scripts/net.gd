extends Node
## LAN networking (ENet). The host runs the World; clients send inputs and receive snapshots.

signal lobby_changed
signal game_started(cfg: Dictionary)
signal snapshot_received(snap: Dictionary)
signal input_received(pid: int, inp: Array)
signal connection_lost(reason: String)
signal peer_left(peer: int)

const Discovery = preload("res://scripts/discovery.gd")

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 16

var players := {}    # peer_id -> {"name": String, "team": int}
var lobby_cfg := {"map": 0, "fill": true, "size": 2}
var pid_owner := {}  # pid -> peer_id (host only)
var online := false
var in_game := false
var my_name := "Player"
var my_vehicle := 0
var host_port := DEFAULT_PORT
## LAN / Hamachi server discovery (beacons while hosting, server list while browsing).
var discovery: Discovery = null


func _ready() -> void:
	discovery = Discovery.new()
	discovery.name = "Discovery"
	discovery.info_provider = beacon_info
	add_child(discovery)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)


func host(port: int, pname: String) -> int:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	in_game = false
	my_name = pname
	host_port = port
	players = {1: {"name": pname, "team": 0, "vehicle": my_vehicle}}
	if discovery != null:
		discovery.start_host()
	lobby_changed.emit()
	return OK


func join(ip: String, port: int, pname: String) -> int:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	in_game = false
	my_name = pname
	players = {}
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	online = false
	in_game = false
	players = {}
	pid_owner = {}
	if discovery != null:
		discovery.stop_host()


## Fields for the discovery beacon (host side).
func beacon_info() -> Dictionary:
	var ts := team_size()
	return {"name": my_name, "port": host_port, "map": int(lobby_cfg.get("map", 0)), "players": players.size(),
		"max": ts * 4, "size": ts, "in_game": in_game}


func team_size() -> int:
	return 4 if int(lobby_cfg.get("size", 2)) == 4 else 2


func is_host() -> bool:
	return online and multiplayer.is_server()


func _on_connected() -> void:
	register.rpc_id(1, my_name, my_vehicle)


func _on_failed() -> void:
	leave()
	connection_lost.emit("Could not connect to host.")


func _on_server_gone() -> void:
	leave()
	connection_lost.emit("Host left the game.")


func _on_peer_disconnected(id: int) -> void:
	if online and multiplayer.is_server():
		players.erase(id)
		sync_lobby.rpc(players, lobby_cfg)
		peer_left.emit(id)


func set_vehicle(peer: int, vehicle: int) -> void:
	if in_game or not players.has(peer):
		return
	players[peer].vehicle = clampi(vehicle, 0, 4)
	sync_lobby.rpc(players, lobby_cfg)


@rpc("any_peer", "reliable")
func request_vehicle(vehicle: int) -> void:
	if multiplayer.is_server():
		set_vehicle(multiplayer.get_remote_sender_id(), vehicle)


func set_team(peer: int, team: int) -> void:
	if in_game or not players.has(peer) or team < 0 or team > 3:
		return
	var count := 0
	for id in players:
		if id != peer and players[id].team == team:
			count += 1
	if count < team_size():
		players[peer].team = team
		sync_lobby.rpc(players, lobby_cfg)


@rpc("any_peer", "reliable")
func register(pname: String, vehicle := 0) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if in_game or players.size() >= team_size() * 4:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	var counts := [0, 0, 0, 0]
	for p in players.values():
		counts[p.team] += 1
	var team := 0
	for t in 4:
		if counts[t] < team_size():
			team = t
			break
	players[id] = {"name": pname.substr(0, 16), "team": team, "vehicle": clampi(vehicle, 0, 4)}
	sync_lobby.rpc(players, lobby_cfg)


@rpc("any_peer", "reliable")
func request_team(team: int) -> void:
	if multiplayer.is_server():
		set_team(multiplayer.get_remote_sender_id(), team)


@rpc("authority", "call_local", "reliable")
func sync_lobby(p: Dictionary, cfg: Dictionary) -> void:
	players = p
	lobby_cfg = cfg
	lobby_changed.emit()


@rpc("authority", "call_local", "reliable")
func start_game(cfg: Dictionary) -> void:
	in_game = true
	game_started.emit(cfg)


@rpc("any_peer", "unreliable_ordered")
func client_input(pid: int, inp: Array) -> void:
	if not multiplayer.is_server():
		return
	if int(pid_owner.get(pid, -1)) == multiplayer.get_remote_sender_id():
		input_received.emit(pid, inp)


@rpc("authority", "unreliable_ordered")
func snapshot(snap: Dictionary) -> void:
	snapshot_received.emit(snap)
