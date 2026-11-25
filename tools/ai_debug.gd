extends SceneTree
## AI diagnostics: _engine\Godot_v4.4.1-stable_win64_console.exe --headless --path . --script res://tools/ai_debug.gd

const MapData = preload("res://scripts/map_data.gd")
const World = preload("res://scripts/world.gd")
const Defs = preload("res://scripts/defs.gd")


func _init() -> void:
	var m = MapData.new()
	m.generate(0, 20261119)
	var roster: Array = []
	for t in 4:
		for k in 2:
			roster.append({"pid": 100 + roster.size(), "peer": 0, "name": "AI%d" % roster.size(), "team": t, "bot": true})
	var w = World.new(m, roster, 20261119, 1, 900.0, 999999)
	var deaths := {}
	for i in 60 * 300:
		w.step(1.0 / 60.0)
		for p in w.players.values():
			if not p.alive and p.respawn > 6.95:
				deaths[p.id] = int(deaths.get(p.id, 0)) + 1
		if i % (60 * 20) == 0:
			print("--- t=%ds" % int(w.elapsed))
			for p in w.players.values():
				var tb: int = w.team_target.get(p.team, 0)
				var held := w._stolen_key(p)
				var where := "tank" if p.tank != null else ("dead" if not p.alive else "B%d" % m.bunker_at(p.pos))
				print("  %s t%d tgt%d keys%s held%s at %s d=%.0f deaths=%d hp=%d" % [p.name, p.team, tb, str(p.keys), "-" if held == -99999 else str(held),
					where, p.pos.distance_to(m.bunkers[tb].center), int(deaths.get(p.id, 0)), int(p.hp)])
			var gopen := ""
			for g in w.gates:
				gopen += "1" if g.open else "0"
			print("  gates %s  bstate acc %s" % [gopen, str(w.bstate.map(func(s): return s.acc))])
	quit()
