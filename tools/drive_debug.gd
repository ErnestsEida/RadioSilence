extends SceneTree
## Diagnostics: are AI crews actually driving their vehicles in a solo match?
const MapData = preload("res://scripts/map_data.gd")
const World = preload("res://scripts/world.gd")

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var map_i := int(args[0]) if args.size() > 0 else 0
	var size := int(args[1]) if args.size() > 1 else 2
	var m = MapData.new()
	m.generate(map_i, 20261119, size)
	var roster: Array = [{"pid": 1, "peer": 1, "name": "Human", "team": 0}]
	var pid := 100
	for t in 4:
		for k in (size - 1 if t == 0 else size):
			roster.append({"pid": pid, "peer": 0, "name": "AI%d" % pid, "team": t, "bot": true})
			pid += 1
	var w = World.new(m, roster, 20261119)
	var start := {}
	for t in w.tanks:
		start[t.id] = t.pos
	for i in 60 * 300:
		w.step(1.0 / 60.0)
		if i % (60 * 30) == 0:
			var line := "t=%3ds " % int(w.elapsed)
			for t in w.tanks:
				var d := "-" if t.driver == null else ("H" if t.driver.bot == null else "B")
				var g := "-" if t.gunner == null else ("H" if t.gunner.bot == null else "B")
				line += "| T%d.%d %s %s%s moved %.0f hp %.0f " % [t.team, t.slot, ["TNK", "BRV", "MOT", "JEP", "RKT"][t.vtype], d, g, t.pos.distance_to(start[t.id]), t.hp]
			print(line)
	quit()
