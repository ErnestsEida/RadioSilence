extends SceneTree
const MapData = preload("res://scripts/map_data.gd")
const World = preload("res://scripts/world.gd")
const Defs = preload("res://scripts/defs.gd")
func _init() -> void:
	var m = MapData.new()
	m.generate(0, 20261119, 16, false)
	var r: Array = []
	for t in 2:
		for k in 16:
			r.append({"pid": 100 + r.size(), "peer": 0, "name": "Bot%d" % r.size(), "team": t, "bot": true})
	var w = World.new(m, r, 20261119, 1, 900.0, 150, Defs.MODE_WAR)
	for i in 3600:
		w.step(1.0 / 60.0)
	var s: Dictionary = w.snapshot()
	for k in s:
		print(k, ": ", var_to_bytes(s[k]).size())
	print("one player rec: ", var_to_bytes(s.p[0]).size(), " keys ", s.p[0].keys().size(), "  ents ", s.e.size() / 9)
	quit()
