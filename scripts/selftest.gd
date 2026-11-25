extends RefCounted
## Headless checks:  _engine\Godot_v4.4.1-stable_win64_console.exe --headless --path . -- --selftest

const MapData = preload("res://scripts/map_data.gd")
const World = preload("res://scripts/world.gd")
const Defs = preload("res://scripts/defs.gd")
const SEED := 20261119
const DT := 1.0 / 60.0

static var fails := 0


static func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		fails += 1


static func _cell(v: Vector2) -> Vector2i:
	return Vector2i(floori(v.x), floori(v.y))


static func _bfs(m, start: Vector2i, open_doors: bool) -> Dictionary:
	var seen := {start: true}
	var q: Array = [start]
	while q.size() > 0:
		var c: Vector2i = q.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n) or n.x < 0 or n.y < 0 or n.x >= m.W or n.y >= m.H:
				continue
			var w: int = m.get_wall(n.x, n.y)
			var ok: bool = (w == 0 and m.obst[n.y * m.W + n.x] == 0) or w == MapData.GATE or (open_doors and (w == MapData.DOOR or w == MapData.KEYDOOR))
			if ok:
				seen[n] = true
				q.append(n)
	return seen


static func _inp(p, o := {}) -> Array:
	return [o.get("mx", 0.0), o.get("my", 0.0), o.get("yaw", p.yaw), o.get("fire", false), o.get("alt", false), o.get("use", false),
		o.get("usec", p.use_count), 0, o.get("wreq", 1), o.get("wseq", p.weapon_seq), 0, p.epoch,
		o.get("sprint", false), o.get("crouch", false), o.get("jumpc", p.jump_count), o.get("throwc", p.throw_count), p.want[0], p.want[1], p.want[2],
		o.get("pitch", 0.0), false, o.get("ax", 0.0), o.get("ay", 0.0)]


static func _steps(w, n: int, pid: int, o := {}) -> void:
	for i in n:
		w.set_input(pid, _inp(w.players[pid], o))
		w.step(DT)


static func _press_use(w, pid: int) -> void:
	var p = w.players[pid]
	_steps(w, 2, pid, {"usec": p.use_count + 1})
	_steps(w, 2, pid)


static func _bots(teams: int, per := 2) -> Array:
	var r: Array = []
	for t in teams:
		for k in per:
			r.append({"pid": 100 + r.size(), "peer": 0, "name": "AI%d" % r.size(), "team": t, "bot": true})
	return r


static func _quiet(w) -> void:
	w.evt_next = 1e9   # no random events during scripted tests
	for e in w.enemies:
		e.dead = true
	for g in w.gates:
		g.hp = 0.0
		w._gate_check(g)


static func _grab_key_of(w, pid: int, kid: int) -> void:
	for it in w.items:
		if it.k == 0 and int(it.key) == kid:
			w.players[pid].pos = it.pos
	_steps(w, 2, pid)


## An open, roofless ground cell near `p` (for scripted targets).
static func _open_spot(m, p: Vector2) -> Vector2:
	for r in 12:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := floori(p.x) + dx
				var y := floori(p.y) + dy
				var ok := true
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						var i: int = (y + oy) * m.W + x + ox
						if m.get_wall(x + ox, y + oy) != 0 or m.roof[i] != 0 or m.obst[i] != 0:
							ok = false
				if ok:
					return Vector2(x + 0.5, y + 0.5)
	return p


static func _test_mortars() -> void:
	print("== mortars")
	var m = MapData.new()
	m.generate(0, SEED)
	_check(m.mortars.size() == 4, "every base camp has a mortar pit")
	var bags := 0
	var mp0: Vector2 = m.mortars[0]
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if m.get_wall(floori(mp0.x) + dx, floori(mp0.y) + dy) == MapData.SANDBAG:
				bags += 1
	_check(bags == 13, "the pit is a ring of sandbags with a way in (%d bags)" % bags)
	var w = World.new(m, [{"pid": 1, "peer": 1, "name": "A", "team": 0}, {"pid": 2, "peer": 1, "name": "A2", "team": 0},
		{"pid": 3, "peer": 1, "name": "B", "team": 1}], SEED)
	_quiet(w)
	for q in w.players.values():
		w._exit_tank(q)
	var a = w.players[1]
	var a2 = w.players[2]
	var b = w.players[3]
	var stand: Vector2 = w.mortar_stand(0)
	var s0: Vector3 = m.team_spawns[0]
	# walk from the camp into the pit
	a.pos = Vector2(s0.x, s0.y)
	for i in 300:
		_steps(w, 1, 1, {"my": 1.0, "yaw": (stand - a.pos).angle()})
		if a.pos.distance_to(stand) < 0.3:
			break
	_check(a.pos.distance_to(mp0) < w.MORTAR_USE, "walked from the camp into the pit (%.1f from the tube)" % a.pos.distance_to(mp0))
	_steps(w, 2, 1)
	_check(a.hint == Defs.H_MORTAR, "standing at the mortar shows the 'man mortar' hint")
	_press_use(w, 1)
	_check(w._mortar_user(a), "USE mans the mortar")
	var sn: Dictionary = w.snapshot()
	var rec_ok := false
	for r in sn.p:
		if int(r.id) == 1:
			rec_ok = bool(r.mortar)
	_check(rec_ok and sn.has("mortar") and int(sn.mortar.m[0].u) == 1, "snapshot: player record has mortar=true, team mortar lists its user")
	# a second team member: 'mortar in use'
	a2.pos = mp0 + Vector2(0, 1.0)
	_steps(w, 2, 2)
	_check(a2.hint == Defs.H_MORTAR_BUSY, "a teammate gets the 'mortar in use' hint")
	_press_use(w, 2)
	_check(w._mortar_user(a) and not w._mortar_user(a2), "only one crew member at a time")
	# another team can't use it
	b.pos = mp0 + Vector2(0, -1.0)
	_press_use(w, 3)
	_check(not w._mortar_user(b) and int(w.mortars[0].user) == 1 and b.hint != Defs.H_MORTAR, "an enemy can't use another team's mortar")
	a2.pos = Vector2(s0.x, s0.y)
	# range limits
	var far: Vector2 = w._mortar_clamp(mp0, mp0 + Vector2(300, 300))
	var near: Vector2 = w._mortar_clamp(mp0, mp0 + Vector2(1.0, 0.5))
	_check(absf(mp0.distance_to(far) - w.mortar_range()) < 0.01 and w.mortar_range() >= 0.45 * m.W, "aim beyond max range is clamped to %.0f" % w.mortar_range())
	_check(absf(mp0.distance_to(near) - w.MORTAR_MIN) < 0.01, "aim inside the minimum range is pushed out to %.0f" % w.MORTAR_MIN)
	# shell flight and damage on an enemy soldier
	var tp := _open_spot(m, mp0 + Vector2(10.0, 9.0))
	b.pos = tp
	b.hp = 100.0
	_steps(w, 1, 1, {"fire": true, "ax": tp.x, "ay": tp.y})
	_check(w.mshells.size() == 1, "LMB fires a shell (%.1f from the mortar)" % mp0.distance_to(tp))
	_steps(w, 30, 1, {"fire": true, "ax": tp.x, "ay": tp.y})
	_check(w.mshells.size() == 1 and float(w.mortars[0].cd) > 3.0, "reloading: holding fire doesn't fire again")
	var flight := 0.5
	var hp2 := -1.0
	while w.mshells.size() > 0 and flight < 8.0:
		_steps(w, 1, 1, {"ax": tp.x, "ay": tp.y})
		flight += DT
		if flight >= 2.0 and hp2 < 0.0:
			hp2 = b.hp
	_check(flight > 2.0 and flight < 5.0 and hp2 == 100.0, "the shell takes %.1f s to land (target untouched at 2 s)" % flight)
	_check(b.hp < 100.0 or not b.alive, "the shell hurts the soldier at the target (%.0f hp left)" % b.hp)
	_steps(w, 60 * 4, 1)
	_check(float(w.mortars[0].cd) <= 0.0, "reloaded after %.0f s" % w.MORTAR_RELOAD)
	# a shell damages gates
	var g: Dictionary = w.gates[0]
	g.open = false
	g.hp = w.GATE_HP
	w._mortar_impact(0, a, g.center)
	_check(float(g.hp) < w.GATE_HP, "a mortar hit damages a gate (%.0f -> %.0f)" % [w.GATE_HP, float(g.hp)])
	g.open = true
	# leaving: USE, getting hit hard, dying
	_press_use(w, 1)
	_check(not w._mortar_user(a) and int(w.mortars[0].user) == -1, "USE again leaves the mortar")
	_press_use(w, 1)
	_check(w._mortar_user(a), "manned again")
	a.hp = 100.0
	w._damage(a, 35.0, b, false)
	_steps(w, 2, 1)
	_check(not w._mortar_user(a) and a.alive, "getting hit hard knocks the crew off the mortar")
	_press_use(w, 1)
	w._damage(a, 500.0, b, false)
	_steps(w, 2, 1)
	_check(not a.alive and int(w.mortars[0].user) == -1, "dying frees the mortar")
	# a bot crews the mortar of an all-bot team and shells a visible enemy
	var mbt = MapData.new()
	mbt.generate(0, SEED)
	var wb = World.new(mbt, [{"pid": 100, "peer": 0, "name": "AI1", "team": 0, "bot": true}, {"pid": 101, "peer": 0, "name": "AI2", "team": 0, "bot": true},
		{"pid": 3, "peer": 1, "name": "B", "team": 1}], SEED)
	_quiet(wb)
	var bot = wb.players[101]
	var mate = wb.players[100]
	for q in wb.players.values():
		wb._exit_tank(q)
	var mpb: Vector2 = mbt.mortars[0]
	var enemy = wb.players[3]
	# out of the bot's rifle reach (17) but inside its view (22) from the pit
	var bstand: Vector2 = wb.mortar_stand(0)
	enemy.pos = _open_spot(mbt, mpb + Vector2(14.0, 12.0))
	for k in 48:
		var cand := _open_spot(mbt, mpb + Vector2.from_angle(TAU * k / 48.0) * 19.5)
		var dd := bstand.distance_to(cand)
		if dd > 18.0 and dd < 21.5 and wb._see(bstand, cand):
			enemy.pos = cand
			break
	mate.alive = false
	mate.respawn = 999.0
	bot.pos = Vector2(s0.x, s0.y).lerp(wb.mortar_stand(0), 0.6)
	wb.mortar_bot_t[101] = 0.0
	var manned := false
	var fired := 0
	for i in 60 * 30:
		wb.set_input(3, _inp(enemy))
		enemy.hp = 100.0
		var before: int = wb.mshells.size()
		wb.step(DT)
		manned = manned or wb._mortar_user(bot)
		if wb.mshells.size() > before:
			fired += 1
		if fired >= 2:
			break
	_check(manned and fired >= 1, "an AI crews its mortar and shells a spotted enemy (%d shells)" % fired)


static func run() -> int:
	fails = 0
	if OS.get_cmdline_user_args().has("--mortars"):
		_test_mortars()
		print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
		return 0 if fails == 0 else 1
	for mi in MapData.MAPS.size():
		var t0 := Time.get_ticks_msec()
		var m = MapData.new()
		m.generate(mi, SEED)
		print("== map %d: %s  %dx%d, %d bunkers, %d gates, %d props (%d ms)" % [mi, MapData.MAPS[mi].name, m.W, m.H, m.bunkers.size(), m.gates.size(), m.decor.size(), Time.get_ticks_msec() - t0])
		var s0: Vector3 = m.team_spawns[0]
		var reach := _bfs(m, Vector2i(int(s0.x), int(s0.y)), false)
		var spawns := true
		for s in m.team_spawns:
			spawns = spawns and reach.has(Vector2i(int(s.x), int(s.y)))
		_check(spawns, "all 4 team camps connected on foot")
		var sealed := true
		var doors := true
		for bk in m.bunkers:
			sealed = sealed and not reach.has(_cell(bk.terminals[0])) and not reach.has(_cell(bk.terminals[1])) and not reach.has(_cell(bk.vault_center))
			for d in bk.door_outside:
				doors = doors and reach.has(_cell(d))
		_check(m.bunkers.size() == 4 and sealed, "4 bunkers, rooms and vaults sealed by key doors")
		_check(doors, "every key door is reachable from outside")
		var tank_ok := true
		for t in 4:
			var s: Vector3 = m.team_spawns[t]
			var tr: Dictionary = m.tank_reach(Vector2i(int(s.x), int(s.y)))
			for bi in 4:
				var any := false
				for g in m.gates:
					if int(g.bunker) == bi and tr.has(_cell(g.approach)):
						any = true
				tank_ok = tank_ok and any
		_check(tank_ok, "every team tank can reach a gate of every bunker")

	print("== 4 players per team: 16 players, 16 keys, 16 puzzle rooms")
	var maps_ok := true
	for mi in MapData.MAPS.size():
		var m16 = MapData.new()
		m16.generate(mi, SEED, 4)
		var s16: Vector3 = m16.team_spawns[0]
		var r16 := _bfs(m16, Vector2i(int(s16.x), int(s16.y)), false)
		for bk in m16.bunkers:
			maps_ok = maps_ok and bk.terminals.size() == 4 and bk.doors.size() == 5 and not r16.has(_cell(bk.vault_center))
			for tp in bk.terminals:
				maps_ok = maps_ok and not r16.has(_cell(tp))
			for d in bk.door_outside:
				maps_ok = maps_ok and r16.has(_cell(d))
			maps_ok = maps_ok and r16.has(_cell(bk.ammo))
	_check(maps_ok, "every map: 4 sealed puzzle rooms per bunker, all key doors and ammo reachable")
	var mq = MapData.new()
	mq.generate(0, SEED, 4)
	var wq = World.new(mq, _bots(4, 4), SEED)
	_quiet(wq)
	var crewed := 0
	for t in wq.tanks:
		if t.driver != null and t.gunner != null:
			crewed += 1
	_check(wq.players.size() == 16 and wq.keys.size() == 16, "16 players and exactly 16 keys")
	_check(wq.tanks.size() == 8 and crewed == 8, "2 crewed vehicles per team (%d vehicles, %d crewed)" % [wq.tanks.size(), crewed])
	var nrooms := 0
	var distinct := true
	for st in wq.bstate:
		nrooms += st.pz.size()
		var tys := {}
		for pz in st.pz:
			tys[int(pz.ty)] = true
		distinct = distinct and tys.size() == 4
	_check(nrooms == 16 and distinct, "16 puzzle rooms, 4 different puzzle types in every bunker")
	var qb := 1
	for r in 4:
		wq._grant(qb, r)
	var qp = wq.players[100]
	for r in 3:
		wq._solve(qp, qb, r)
	_check(not wq.bstate[qb].acc[4], "vault stays shut with 3 of 4 rooms solved")
	wq._solve(qp, qb, 3)
	_check(wq.bstate[qb].acc[4], "solving the 4th room opens the vault")
	wq._reclaim(qb)
	_check(not wq.bstate[qb].acc.has(true) and not wq.bstate[qb].sol.has(true), "reclaim re-locks all 4 rooms and the vault")

	print("== keys, rooms, puzzles, vault, banking, reclaim")
	var m3 = MapData.new()
	m3.generate(0, SEED)
	var w = World.new(m3, [{"pid": 1, "peer": 1, "name": "A", "team": 0},
		{"pid": 2, "peer": 1, "name": "B1", "team": 1}, {"pid": 3, "peer": 1, "name": "B2", "team": 1}], SEED)
	_quiet(w)
	_check(w.keys.size() == 3 + 4, "one key per player (3) + 2 guard keys for each of the 2 unowned bunkers")
	var a = w.players[1]
	var b1 = w.players[2]
	var b2 = w.players[3]
	for q in [a, b1, b2]:
		w._exit_tank(q)
	_check(a.keys == [1] and b1.keys == [2], "players start carrying their own key")
	var sb: int = w.TEAM_BUNKER[1]
	var bk: Dictionary = m3.bunkers[sb]
	# A kills B1 and takes B1's key
	b1.pos = a.pos + Vector2(1.5, 0)
	b1.hp = 1.0
	_steps(w, 30, 1, {"yaw": (b1.pos - a.pos).angle(), "fire": true})
	_check(not b1.alive and b1.keys.is_empty(), "B1 killed and dropped their key")
	_grab_key_of(w, 1, 2)
	_check(a.keys.has(2), "A carries B's key")
	# A dies carrying both keys -> both dropped; then A respawns and grabs B's key back
	a.hp = 1.0
	w._damage(a, 50.0, null, false)
	var dropped := 0
	for it in w.items:
		if it.k == 0:
			dropped += 1
	_check(not a.alive and dropped == 2, "dying drops ALL carried keys (own + stolen)")
	w._respawn(a)
	_check(not a.keys.has(1), "A's own key stays on the ground until recovered")
	_grab_key_of(w, 1, 1)
	_grab_key_of(w, 1, 2)
	_check(a.keys.has(1) and a.keys.has(2), "A recovered own key and re-took B's key")
	# unlock B's code room -> key consumed
	a.pos = bk.door_outside[0]
	_press_use(w, 1)
	_check(w.bstate[sb].acc[0] and w.keys[2].used and not a.keys.has(2), "key used on B's bunker is gone (consumed)")
	w._respawn(b1)
	_check(not b1.keys.has(2), "a used key does not come back on respawn")
	# second key from B2
	b2.pos = a.pos + Vector2(1.2, 0)
	b2.hp = 1.0
	_steps(w, 30, 1, {"yaw": (b2.pos - a.pos).angle(), "fire": true})
	_grab_key_of(w, 1, 3)
	a.pos = bk.door_outside[1]
	_press_use(w, 1)
	_check(w.bstate[sb].acc[1] and w.keys[3].used, "second key opens the second room")
	var left := 0
	for kid in w.keys:
		if int(w.keys[kid].bunker) == sb and not w.keys[kid].used:
			left += 1
	_check(left == 0, "B's bunker has no keys left")
	# puzzles (force a known pair of types for the scripted solve)
	w.bstate[sb].pz = [w._new_puzzle(Defs.PZ_CODE, 0), w._new_puzzle(Defs.PZ_TUNER, 0)]
	a.pos = bk.terminals[0]
	_press_use(w, 1)
	var guard := 0
	while not w.bstate[sb].sol[0] and guard < 900:
		guard += 1
		var pz: Dictionary = w.bstate[sb].pz[0]
		var d: int = int(pz.seq[pz.pos])
		_steps(w, 2, 1, {"mx": 1.0 if d == 1 else (-1.0 if d == 3 else 0.0), "my": 1.0 if d == 0 else (-1.0 if d == 2 else 0.0)})
		_steps(w, 2, 1)
	_check(w.bstate[sb].sol[0], "4-stage code lock solved (incl. hidden-code stages)")
	a.pos = bk.terminals[1]
	_press_use(w, 1)
	for i in 6000:
		if w.bstate[sb].sol[1]:
			break
		var pz: Dictionary = w.bstate[sb].pz[1]
		_steps(w, 1, 1, {"mx": clampf((float(pz.t) - float(pz.v)) * 10.0, -1.0, 1.0)})
	_check(w.bstate[sb].sol[1] and w.bstate[sb].acc[2], "signal tuner solved -> B's vault is open")
	for e in w.enemies:
		e.dead = true
	var loot := 0
	for it in w.items:
		if it.k == 1 and int(it.vault) == sb:
			a.pos = it.pos
			_steps(w, 1, 1)
			loot = a.carried
			break
	_check(loot > 0, "A picked up loot in B's vault (%d)" % loot)
	var s0b: Vector3 = m3.team_spawns[0]
	a.pos = Vector2(s0b.x, s0b.y) + Vector2(1, 0)
	_steps(w, 2, 1)
	_check(a.carried == 0 and w.teams[0].score == 100 + loot, "loot banked (score %d incl. +100 first-in)" % w.teams[0].score)
	# B holds its bunker for 60 s -> sealed again, keys back
	w._respawn(b1)
	w._respawn(b2)
	b1.pos = bk.center
	b2.pos = bk.center + Vector2(0.6, 0)
	for i in 3700:
		w.set_input(1, _inp(a))
		w.set_input(2, _inp(b1))
		w.set_input(3, _inp(b2))
		w.step(DT)
		if not w.bstate[sb].acc[0]:
			break
	_check(not w.bstate[sb].acc[0] and not w.bstate[sb].acc[2] and not w.keys[2].used, "owners held 60 s: bunker sealed and keys restored")
	_check(b1.keys.has(2) and b2.keys.has(3) and m3.get_wall(bk.doors[0].x, bk.doors[0].y) == MapData.KEYDOOR, "keys back in the owners' hands, doors locked")

	print("== AI solves every puzzle type")
	for ty in 5:
		var mp = MapData.new()
		mp.generate(0, SEED)
		var wp = World.new(mp, [{"pid": 1, "peer": 1, "name": "A", "team": 0}, {"pid": 100, "peer": 0, "name": "B", "team": 1, "bot": true}], SEED)
		_quiet(wp)
		var bot = wp.players[100]
		wp._exit_tank(bot)
		var tb: int = wp.TEAM_BUNKER[0]
		wp._grant(tb, 0)
		wp.bstate[tb].pz[0] = wp._new_puzzle(ty, 0)
		bot.pos = mp.bunkers[tb].terminals[0]
		bot.puzzle = 0
		bot.pz_bunker = tb
		var secs := 0.0
		for i in 60 * 400:
			wp.players[1].alive = false
			wp.players[1].respawn = 99.0
			bot.puzzle = 0 if not wp.bstate[tb].sol[0] else -1
			wp.step(DT)
			secs += DT
			if wp.bstate[tb].sol[0]:
				break
		_check(wp.bstate[tb].sol[0], "AI solved %s in %.0f s" % [Defs.PUZZLES[ty].name, secs])

	print("== movement and bullets")
	var m4 = MapData.new()
	m4.generate(0, SEED)
	var w4 = World.new(m4, [{"pid": 1, "peer": 1, "name": "A", "team": 0, "loadout": [Defs.W_SNIPER, Defs.W_REVOLVER, Defs.EQ_FRAG]}], SEED)
	_quiet(w4)
	var p = w4.players[1]
	w4._exit_tank(p)
	p.pos = Vector2(12.5, 12.5)
	var runs := 0
	for i in 900:
		_steps(w4, 1, 1, {"my": 1.0, "sprint": true, "yaw": 0.0})
		if p.sprint:
			runs += 1
		if i % 120 == 0:
			p.pos = Vector2(12.5, 12.5)
		if p.exhausted:
			break
	_check(p.exhausted and runs > 200 and runs < 360, "sprinting drains stamina to EXHAUSTED (%.1f s of sprint)" % (runs * DT))
	_steps(w4, 120, 1, {"my": 1.0, "sprint": true, "yaw": 0.0})
	_check(not p.sprint and p.exhausted, "cannot sprint while exhausted, even after it starts refilling")
	_steps(w4, 900, 1)
	_check(not p.exhausted and p.stamina >= 1.0, "sprint unlocks only once stamina is full again")
	# along the north-south road, between the north bunker and the map centre (clear line of fire)
	var down := PI * 0.5
	p.pos = Vector2(m4.W / 2 + 0.5, 40.5)
	p.yaw = down
	p.epoch += 1
	var tgt = w4._spawn_enemy(Defs.E_SOLDIER, p.pos + Vector2(0, 28), false)
	tgt.hp = 500.0
	tgt.max_hp = 500.0
	tgt.bunker = -1
	p.cool = 0.0
	p.reload = 0.0
	p.mags[p.weapon] = 5
	_steps(w4, 1, 1, {"fire": true, "alt": true, "yaw": down})
	_check(tgt.hp == 500.0 and w4.bullets.size() == 1, "sniper fires a travelling bullet (no instant hit)")
	_steps(w4, 30, 1, {"alt": true, "yaw": down})
	_check(tgt.hp == 500.0, "after 0.5 s the bullet is still on its way (28 tiles away)")
	_steps(w4, 40, 1, {"alt": true, "yaw": down})
	_check(tgt.hp < 500.0, "bullet arrives after ~0.8 s and hits")
	_check(500.0 - tgt.hp < 100.0, "sniper hit no longer one-shots a full-health soldier (%d dmg)" % int(500.0 - tgt.hp))
	tgt.hp = 500.0
	tgt.pos = p.pos + Vector2(0, 28)
	_steps(w4, 120, 1, {"yaw": down})
	p.cool = 0.0
	p.reload = 0.0
	p.mags[p.weapon] = 5
	_steps(w4, 1, 1, {"fire": true, "alt": true, "yaw": down})
	tgt.pos += Vector2(2.0, 0)   # dodge sideways while the bullet flies
	_steps(w4, 90, 1, {"alt": true, "yaw": down})
	_check(tgt.hp == 500.0, "target that sidesteps during flight is missed")

	print("== heights: cover, stairs, aiming up and down")
	var wpn_rifle := {"alt": true}
	var c0 := Vector2i(m4.W / 2, 64)
	p.pos = Vector2(c0.x + 0.5, c0.y + 0.5)
	p.z = 0.0
	p.yaw = down
	p.epoch += 1
	for dx in range(-1, 2):
		m4._blk(c0.x + dx, c0.y + 1, MapData.SANDBAG, 0.55)
	tgt.pos = p.pos + Vector2(0, 5)
	tgt.hp = 500.0
	w4.bullets.clear()
	_steps(w4, 40, 1, wpn_rifle)
	p.cool = 0.0
	p.reload = 0.0
	p.mags[p.weapon] = 5
	_steps(w4, 1, 1, {"fire": true, "alt": true, "yaw": down})
	_steps(w4, 30, 1, {"alt": true, "yaw": down})
	_check(tgt.hp < 500.0, "a standing shot flies over low sandbags (%d dmg)" % int(500.0 - tgt.hp))
	tgt.hp = 500.0
	_steps(w4, 40, 1, {"alt": true, "crouch": true, "yaw": down})
	p.cool = 0.0
	p.reload = 0.0
	p.mags[p.weapon] = 5
	_steps(w4, 1, 1, {"fire": true, "alt": true, "crouch": true, "yaw": down})
	_steps(w4, 30, 1, {"alt": true, "crouch": true, "yaw": down})
	_check(tgt.hp == 500.0, "crouched behind sandbags the shot hits the cover")
	_check(w4._vis(tgt, p) == 0, "a crouched player behind sandbags is hidden from a guard")
	_steps(w4, 30, 1, {"alt": true, "yaw": down})
	_check(w4._vis(tgt, p) > 0, "standing up exposes them again")
	# camp watchtower: walk up the stairs onto the platform
	p.pos = Vector2(11.5, 2.5)
	p.z = 0.0
	p.yaw = PI
	p.epoch += 1
	_steps(w4, 240, 1, {"my": 1.0, "yaw": PI})
	_check(absf(p.z - 1.8) < 0.05 and p.pos.x < 4.5, "walked up the stairs onto the watchtower (z %.2f, x %.1f)" % [p.z, p.pos.x])
	p.pos = Vector2(3.5, 2.5)
	tgt.pos = Vector2(14.5, 2.5)
	tgt.hp = 500.0
	var east := 0.0
	var ez: float = w4._eye_z(p) - 0.04
	var pdown := atan2(w4._chest_z(tgt) - ez, 11.0)
	_steps(w4, 40, 1, {"alt": true, "yaw": east})
	p.cool = 0.0
	p.reload = 0.0
	p.mags[p.weapon] = 5
	_steps(w4, 1, 1, {"fire": true, "alt": true, "yaw": east, "pitch": 0.0})
	_steps(w4, 30, 1, {"alt": true, "yaw": east})
	_check(tgt.hp == 500.0, "a level shot from the tower flies over a target below")
	_steps(w4, 40, 1, {"alt": true, "yaw": east, "pitch": pdown})
	p.cool = 0.0
	p.reload = 0.0
	p.mags[p.weapon] = 5
	_steps(w4, 1, 1, {"fire": true, "alt": true, "yaw": east, "pitch": pdown})
	_steps(w4, 30, 1, {"alt": true, "yaw": east, "pitch": pdown})
	_check(tgt.hp < 500.0, "aiming down from the tower hits it (%d dmg)" % int(500.0 - tgt.hp))
	tgt.dead = true
	var hp0: float = p.hp
	p.pos = Vector2(2.5, 3.5)
	_steps(w4, 150, 1, {"my": 1.0, "yaw": down})
	_check(p.z < 0.01 and p.hp == hp0, "stepping off the tower drops you to the ground unhurt (z %.2f, hp %.0f -> %.0f, alive %s)" % [p.z, hp0, p.hp, str(p.alive)])
	tgt.dead = true

	print("== random events")
	var w5 = World.new(m4, [{"pid": 1, "peer": 1, "name": "A", "team": 0}, {"pid": 2, "peer": 1, "name": "B", "team": 1}], SEED)
	_quiet(w5)
	var pa = w5.players[1]
	var pb = w5.players[2]
	w5._exit_tank(pa)
	w5._exit_tank(pb)
	for e in w5.enemies:
		e.dead = true
	# supply drop: falls, lands, and the crate gives loot + refit
	w5.start_event(Defs.EVT_SUPPLY)
	var drop := Vector2(w5.evt.x, w5.evt.y)
	_steps(w5, 60 * 14, 1)
	_check(bool(w5.evt.landed), "supply crate parachutes down and lands")
	pa.hp = 40.0
	pa.pos = drop
	_steps(w5, 2, 1)
	_check(pa.carried == Defs.SUPPLY_VALUE and pa.hp == 100.0, "grabbing the crate gives %d loot and full health" % Defs.SUPPLY_VALUE)
	_steps(w5, 2, 1)
	_check(w5.evt.is_empty(), "supply event ends once the crate is taken")
	# gold rush doubles banking
	w5.start_event(Defs.EVT_GOLD)
	var sc0: int = w5.teams[0].score
	w5._deposit(pa)
	_check(w5.teams[0].score - sc0 == Defs.SUPPLY_VALUE * 2, "gold rush: banked loot counts double (+%d)" % (w5.teams[0].score - sc0))
	w5.end_event()
	# artillery hurts whoever stays in the zone, after a warning
	pb.pos = drop + Vector2(0, 3)
	pb.hp = 100.0
	w5.start_event(Defs.EVT_ARTY)
	_steps(w5, 60 * 5, 1)
	_check(pb.hp == 100.0 and w5.evt.bombs.is_empty(), "air strike: siren warning before anything drops")
	# one bomb scheduled right on top of B, the rest of the strike is map-wide
	w5.evt.bombs.append([pb.pos.x, pb.pos.y, w5.elapsed + 3.0])
	var hits := 0
	var quads := {}
	var booms := 0
	for i in 60 * 34:
		pb.hp = maxf(pb.hp, 50.0)
		pb.alive = true
		var before: float = pb.hp
		var nb: int = w5.evt.get("bombs", []).size() if not w5.evt.is_empty() else 0
		for bm in w5.evt.get("bombs", []) if not w5.evt.is_empty() else []:
			quads[int(float(bm[0]) * 2.0 / m4.W) * 2 + int(float(bm[1]) * 2.0 / m4.H)] = true
		w5.set_input(1, _inp(pa))
		w5.step(DT)
		if not w5.evt.is_empty() and w5.evt.get("bombs", []).size() < nb:
			booms += 1
		if pb.hp < before:
			hits += 1
	_check(hits > 0, "a bomb landing on a soldier hurts him (%d hits)" % hits)
	_check(quads.size() == 4 and w5.evt.is_empty(), "air strike covers all 4 quarters of the map, then ends (%d impacts)" % booms)
	# bounty: killing a player of the marked team pays out
	pb.alive = true
	pb.hp = 100.0
	w5.start_event(Defs.EVT_BOUNTY)
	w5.evt.team = 1
	var sc1: int = w5.teams[0].score
	w5._damage(pb, 500.0, pa, false)
	_check(w5.teams[0].score - sc1 == Defs.BOUNTY_VALUE, "bounty kill pays +%d" % Defs.BOUNTY_VALUE)
	w5.end_event()
	w5.start_event(Defs.EVT_STORM)
	_check(w5._vis_mult() < 1.0, "storm cuts AI vision range")
	w5.end_event()

	_test_mortars()

	for run_cfg in [[0, 2], [1, 2], [2, 2], [3, 2], [0, 4]]:
		var mi: int = run_cfg[0]
		var per: int = run_cfg[1]
		print("== 4 AI teams of %d on %s (max 12 sim minutes)" % [per, MapData.MAPS[mi].name])
		var mb = MapData.new()
		mb.generate(mi, SEED, per)
		var wb = World.new(mb, _bots(4, per), SEED, 1, 720.0, 999999)
		var t0 := Time.get_ticks_msec()
		var first := {"key": -1.0, "room": -1.0, "solve": -1.0, "vault": -1.0, "bank": -1.0, "reclaim": -1.0}
		var steps := 0
		var max_keys := 0
		for i in 43200:
			wb.step(DT)
			if i % 2 == 0:
				wb.snapshot()
			steps += 1
			var live_keys := 0
			for kid in wb.keys:
				if not wb.keys[kid].used:
					live_keys += 1
			max_keys = maxi(max_keys, live_keys)
			for tm in wb.teams:
				if first.key < 0.0 and wb.team_keys(int(tm)) > 0: first.key = wb.elapsed
				if first.bank < 0.0 and wb.teams[tm].score > 100: first.bank = wb.elapsed
			for b in wb.bstate.size():
				var st: Dictionary = wb.bstate[b]
				if first.room < 0.0 and (st.acc[0] or st.acc[1]): first.room = wb.elapsed
				if first.solve < 0.0 and (st.sol[0] or st.sol[1]): first.solve = wb.elapsed
				if first.vault < 0.0 and st.acc[wb.V]: first.vault = wb.elapsed
				if first.reclaim < 0.0 and first.room >= 0.0 and float(st.hold) > 59.0: first.reclaim = wb.elapsed
			if wb.over:
				break
		var ms := Time.get_ticks_msec() - t0
		var scores := ""
		for tm in wb.teams:
			scores += "%s %d  " % [Defs.TEAM_NAMES[tm], wb.teams[tm].score]
		print("  %.0fs sim, %.2f ms/step | key %.0fs room %.0fs puzzle %.0fs vault %.0fs bank %.0fs reclaim %.0fs" % [
			wb.elapsed, float(ms) / steps, first.key, first.room, first.solve, first.vault, first.bank, first.reclaim])
		print("  scores: %s" % scores)
		_check(max_keys <= per * 4 and wb.keys.size() == per * 4, "never more than %d keys in play (%d)" % [per * 4, max_keys])
		_check(first.key >= 0.0 and first.room >= 0.0, "AI steals keys and opens rooms")
		_check(first.vault >= 0.0 and first.bank >= 0.0, "AI opens a vault and banks loot")
		var in10 := 0
		var names := ""
		for e in wb.evt_log:
			if float(e[1]) <= 600.0:
				in10 += 1
			names += "%s@%ds " % [Defs.EVENT_NAMES[int(e[0])], int(e[1])]
		print("  events: %s" % names)
		_check(in10 >= 3, "at least 3 random events in the first 10 minutes (%d)" % in10)

	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	return 0 if fails == 0 else 1
