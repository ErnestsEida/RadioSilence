extends SceneTree
## 16-player sanity check: 1v1 (8 per team) and 1v1v1v1 (4 per team) on every map, all modes.
const MapData = preload("res://scripts/map_data.gd")
const World = preload("res://scripts/world.gd")

func _init() -> void:
	for mi in MapData.MAPS.size():
		for teams in [2, 4]:
			var per: int = 16 / teams
			for mode in [0, 1, 2]:
				var m = MapData.new()
				m.generate(mi, 20261119, per, mode == 0)
				var roster: Array = []
				for t in teams:
					for k in per:
						roster.append({"pid": 100 + roster.size(), "peer": 0, "name": "AI", "team": t, "bot": true})
				var w = World.new(m, roster, 20261119, 1, 600.0, 999999, mode)
				var bad := 0
				for t in w.tanks:
					if m.circle_blocked(t.pos, 0.6):
						bad += 1
				var stacked := 0
				for p in w.players.values():
					for q in w.players.values():
						if p.id < q.id and p.pos.distance_to(q.pos) < 0.5:
							stacked += 1
				for i in 600:
					w.step(1.0 / 60.0)
				print("map %d teams %d x%d mode %d: players %d keys %d vehicles %d blocked %d stacked %d" % [mi, teams, per, mode, w.players.size(), w.keys.size(), w.tanks.size(), bad, stacked])
	quit()
