extends SceneTree
## Renders the SERVER BROWSER with two fake hosts beaconing on this PC and saves a PNG.
##   godot --path . -s res://tools/browser_shot.gd -- out.png

const Discovery = preload("res://scripts/discovery.gd")

var main_node: Node = null
var t := 0.0
var opened := false
var out := "user://browser_shot.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var scene: PackedScene = load("res://scenes/main.tscn")
	main_node = scene.instantiate()
	root.add_child(main_node)
	var infos: Array = [
		{"name": "Sarge", "port": 7777, "map": 0, "players": 3, "max": 8, "size": 2, "in_game": false},
		{"name": "Hamachi Henk", "port": 7777, "map": 1, "players": 9, "max": 16, "size": 4, "in_game": true},
	]
	for info: Dictionary in infos:
		var d := Discovery.new()
		d.info_provider = func() -> Dictionary: return info
		root.add_child(d)
		d.start_host()


func _process(delta: float) -> bool:
	t += delta
	if not opened and t > 4.0 and main_node.get("browser_root") != null:
		opened = true
		main_node.call("_open_browser")
	if opened and t > 8.0:
		var img := root.get_texture().get_image()
		img.save_png(out)
		print("saved ", out)
		return true
	return t > 20.0
