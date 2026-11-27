extends SceneTree
const MapData = preload("res://scripts/map_data.gd")
const World = preload("res://scripts/world.gd")
const Defs = preload("res://scripts/defs.gd")
func _init() -> void:
	var m = MapData.new()
	m.generate(0, 1234)
	var w = World.new(m, [{"pid": 1, "peer": 1, "name": "A", "team": 0}], 1234)
	w._drop_weapon(Defs.W_SNIPER, 5, 10, w.armor_spots[0].pos, 0.0)
	var s: Dictionary = w.snapshot()
	var e: PackedFloat32Array = s.e
	var c := {}
	for i in e.size() / 9:
		var t := int(e[i * 9])
		c[t] = int(c.get(t, 0)) + 1
		if t == 32:
			print("weapon ent: ", e.slice(i * 9, i * 9 + 9))
	print(c)
	quit()
