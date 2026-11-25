extends SceneTree
## LAN discovery test. Run:
##   godot --headless --path . -s res://tools/discovery_test.gd -- both|host|client [seconds]
## "both" runs a host beacon and a browser in one process (the second socket cannot get
## 7778, so this also exercises the ephemeral-port fallback). Exit code 0 = a server was found.

const Discovery = preload("res://scripts/discovery.gd")

var mode := "both"
var secs := 8.0
var host_d: Discovery = null
var cli_d: Discovery = null
var t := 0.0
var print_t := 0.0
var found := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]
	if args.size() > 1:
		secs = float(args[1])
	var main_script: GDScript = load("res://scripts/main.gd")
	print("main.gd loaded: ", main_script != null and main_script.can_instantiate())
	print("local adapters: ", Discovery.describe_addresses())
	for a: String in Discovery.local_ipv4():
		print("  ", a, " -> ", Discovery.broadcast_targets(a))
	if mode == "host" or mode == "both":
		host_d = Discovery.new()
		host_d.info_provider = func() -> Dictionary:
			return {"name": "TestHost-%d" % OS.get_process_id(), "port": 7777, "map": 1, "players": 3, "max": 8, "size": 2, "in_game": false}
		root.add_child(host_d)
		host_d.start_host()
		print("host: listen port ", host_d.listen_port)
	if mode == "client" or mode == "both":
		cli_d = Discovery.new()
		root.add_child(cli_d)
		cli_d.start_browse()
		print("client: listen port ", cli_d.listen_port)


func _process(delta: float) -> bool:
	t += delta
	print_t += delta
	if cli_d != null and print_t >= 1.0:
		print_t = 0.0
		var list: Array = cli_d.get_servers()
		print("[%.1fs] %d server(s)" % [t, list.size()])
		for s: Dictionary in list:
			found = true
			print("   %s  ip=%s port=%d map=%d players=%d/%d size=%d in_game=%s ping=%d addrs=%s" % [
				str(s.get("name", "")), str(s.get("ip", "")), int(s.get("port", 0)), int(s.get("map", 0)),
				int(s.get("players", 0)), int(s.get("max", 0)), int(s.get("size", 0)),
				str(s.get("in_game", false)), int(s.get("ping", -1)), str(s.get("addrs", {}))])
	if t >= secs:
		if cli_d != null:
			print("RESULT: ", "FOUND" if found else "NOTHING FOUND")
		return true
	return false


func _finalize() -> void:
	if host_d != null:
		host_d.stop_host()
	if cli_d != null:
		cli_d.stop_browse()
