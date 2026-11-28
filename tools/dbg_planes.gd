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
			r.append({"pid": 100 + r.size(), "peer": 0, "name": "B%d" % r.size(), "team": t, "bot": true})
	var w = World.new(m, r, 20261119, 1, 900.0, 150, Defs.MODE_WAR)
	w.evt_next = 1e9
	for i in 60 * 70:
		w.step(1.0 / 60.0)
		if i % 300 == 0:
			for t in w.tanks:
				if w._is_plane(t) and t.team == 0:
					print("t=%d plane %d alive=%s z=%.1f spd=%.1f drv=%s gun=%s drive=%.1f pcmd=%.2f pos=%s" % [i / 60, t.id, t.alive, t.z, t.speed, t.driver != null, t.gunner != null, t.drive, t.pcmd, str(t.pos.round())])
	quit()
