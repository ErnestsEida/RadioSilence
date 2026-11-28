extends RefCounted
## Authoritative game simulation. Runs on the host (or locally for Solo / Co-op).
## Clients only ever see snapshot() output.
##
## Match flow per team, at any of the 4 bunkers:
##   steal KEYS off enemy-team players (exactly one key exists per player)
##   -> each stolen key unlocks one puzzle room of a bunker (for your team only)
##   -> solve both rooms of that bunker -> its vault opens for your team
##   -> carry loot back to your tank / base camp to bank points. Most points wins.

const Defs = preload("res://scripts/defs.gd")
const MapData = preload("res://scripts/map_data.gd")

const PLAYER_R := 0.25
const TANK_R := 0.6
const TANK_HP := 500.0
const GATE_HP := 300.0
const TANK_RESPAWN := 25.0
const WAR_RESPAWN := 60.0     # WAR: vehicles and planes come back, but much slower
const PLAYER_RESPAWN := 7.0
const WEAPON_DROP_LIFE := PLAYER_RESPAWN * 1.5   # dropped guns stay this long
const ARMOR_RESPAWN := 40.0
const ARMOR_ABSORB := 0.6                        # share of each hit the vest soaks up
const CANNON_CD := 2.2
const BASE_SPEED := 3.3
const SPRINT_MULT := 1.5
const GRAVITY := 9.0
const KEY_RETURN_TIME := 60.0

const I_MX := 0
const I_MY := 1
const I_YAW := 2
const I_FIRE := 3
const I_ALT := 4
const I_USE := 5
const I_USEC := 6
const I_SEATC := 7
const I_WREQ := 8
const I_WSEQ := 9
const I_RELC := 10
const I_EPOCH := 11
const I_SPRINT := 12
const I_CROUCH := 13
const I_JUMPC := 14
const I_THROWC := 15
const I_PRI := 16
const I_SEC := 17
const I_EQ := 18
const I_PITCH := 19
const I_AUTO := 20     # vertical aim assist (gamepad / shared keyboard)
const I_AIMX := 21     # mortar aim point (world coordinates)
const I_AIMY := 22
const INPUT_SIZE := 23
const JUMP_V := 3.0
# gun traverse relative to the hull (min, max); the moto sidecar MG and the jeep's rear MG can't swing through the crew
const TRAVERSE := [Vector2(-PI, PI), Vector2(-PI, PI), Vector2(-0.45, 1.7), Vector2(-2.6, 2.6), Vector2(-PI, PI),
	Vector2(-PI, PI), Vector2(-PI, PI), Vector2(-PI, PI)]
const MAX_PITCH := 0.95
const FALL_SAFE := 2.3

const AIM_SD := [0.15, 0.085, 0.045]
const REACT := [1.0, 0.6, 0.3]
const PZ_SPEED := [0.85, 0.55, 0.35]
const CODE_LENGTHS := [4, 5, 6]
const TUNE_TOL := [0.08, 0.06, 0.045]


class Player:
	var ttype := 1
	var id := 0
	var slot := 0
	var name := ""
	var team := 0
	var pos := Vector2.ZERO
	var yaw := 0.0
	var hp := 100.0
	var alive := true
	var respawn := 0.0
	var tank = null
	var seat := -1
	var weapon := 3
	var primary := 3
	var secondary := 1
	var equip := 0
	var eqn := 2
	var want := [3, 1, 0]
	var mags := {}
	var res := {}
	var cool := 0.0
	var reload := 0.0
	var inp: Array = []
	var use_count := 0
	var seat_count := 0
	var reload_count := 0
	var weapon_seq := 0
	var jump_count := 0
	var throw_count := 0
	var epoch := 0
	var progress := 0.0
	var hint := 0
	var hurt := 0.0
	var shots := 0
	var seat_edge := false   # [seat] pressed this frame (on foot: board a vehicle as gunner)
	var spawn_t := -99.0
	var spawn_shots := 0
	var kills := 0
	var moving := false
	var fire_t := 0.0
	var fire_prev := false
	var stamina := 1.0
	var exhausted := false
	var sprint := false
	var crouch := false
	var ads := false
	var z := 0.0
	var vz := 0.0
	var peak := 0.0
	var air := false
	var pitch := 0.0
	var carried := 0
	var keys: Array = []
	var puzzle := -1
	var pz_bunker := -1
	var pz_prev := -1
	var ammo_cd := 0.0
	var burst_left := 0   # rounds still to come in the current burst (burst rifle)
	var heal_id := -1     # teammate a medkit would heal right now (H_HEAL hint)
	var armor := 0.0      # 0..100, soaks ARMOR_ABSORB of incoming damage
	var hw := -1          # weapon id of a dropped gun in reach (H_WEAPON hint)
	var bot = null


class Bot:
	var seat_t := 0.0     # cooldown between seat swaps (alone in a vehicle: drive OR shoot)
	var use_c := 0
	var seat_c := 0
	var wseq := 0
	var wreq := 1
	var wcd := 0.0
	var jump_c := 0
	var throw_c := 0
	var throw_cd := 0.0
	var target = null
	var see_t := 0.0
	var react_t := 0.0
	var err := 0.0
	var err_t := 0.0
	var path: Array = []
	var path_t := 0.0
	var path_goal := Vector2i(-99, -99)
	var stuck_t := 0.0
	var stuck_pos := Vector2.ZERO
	var reverse_t := 0.0
	var use_cd := 0.0
	var strafe := 1.0
	var strafe_t := 0.0
	var pause_t := 0.0     # plants its feet for a moment to aim
	var retreat_t := 0.0   # hurt: falls back for a moment
	var flank := 1.0       # approach from this side of the enemy (re-rolled now and then)
	var flank_t := 0.0
	var tvel := Vector2.ZERO   # target velocity estimate (for leading shots)
	var tlast := Vector2.ZERO
	var tlast_id := -1
	var tick := 0
	var pz_t := 0.0
	var pz_release := false
	var travel := Vector2.INF
	var taxi_stuck := 0.0
	var taxi_cd := 0.0


class Tank:
	var ttype := 2
	var vtype := 0
	var slot := 0
	var gun_pitch := 0.0
	var id := 0
	var team := 0
	var pos := Vector2.ZERO
	var hull := 0.0
	var turret := 0.0
	var hp := 500.0
	var alive := true
	var driver = null
	var gunner = null
	var drive := 0.0
	var steer := 0.0
	var cannon_cd := 0.0
	var mg_cd := 0.0
	var respawn := 0.0
	var spawn := Vector3.ZERO
	var moving := false
	var fire_t := 0.0
	# planes only
	var z := 0.0          # altitude
	var speed := 0.0      # forward speed
	var ppitch := 0.0     # nose pitch (rad, + = climbing)
	var pcmd := 0.0       # pilot's pitch command (mouse Y)
	var bank := 0.0
	var bombs := 0
	var bomb_cd := 0.0


class Enemy:
	var ttype := 0
	var id := 0
	var kind := 1
	var bunker := -1
	var pos := Vector2.ZERO
	var home := Vector2.ZERO
	var yaw := 0.0
	var hp := 70.0
	var max_hp := 70.0
	var dead := false
	var dead_t := 0.0
	var alerted := false
	var target = null
	var last_known := Vector2.ZERO
	var has_lk := false
	var cd := 0.0
	var burst := 0
	var path: Array = []
	var path_t := 0.0
	var path_goal := Vector2i(-1, -1)
	var see_t := 0.0
	var firing_t := 0.0
	var moving := false
	var wander_t := 0.0
	var wander := Vector2.ZERO


class Shell:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var team := 0
	var owner = null
	var life := 2.0
	var dmg := 150.0
	var splash := 1.8
	var z := 0.6
	var slope := 0.0
	var vz := 0.0        # bombs: vertical speed (with grav > 0 the slope follows it)
	var grav := 0.0


class Bullet:
	var id := 0
	var pos := Vector2.ZERO
	var z := 0.6
	var slope := 0.0
	var dir := Vector2.RIGHT
	var speed := 60.0
	var left := 30.0
	var dmg := 10.0
	var team := 0
	var owner = null


class Grenade:
	var id := 0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var z := 0.4
	var vz := 2.4
	var team := 0
	var owner = null
	var fuse := 2.0
	var smoke := false


var TEAM_BUNKER: Array = [0, 1, 3, 2]   # team -> the bunker it owns (set from the map layout)
var R := 2   # puzzle rooms per bunker (2 or 4, = players per team)
var V := 2   # index of the vault door in doors[] / acc[] (= R)
const RECLAIM_TIME := 60.0

var bstate: Array = []   # per bunker: {owner, acc[R+1], sol[R], pz[R], hold, first}
var map
var astar := AStarGrid2D.new()
var tank_astar := AStarGrid2D.new()
var team_astar := {}
var team_pass := {}
var teams := {}
var keys := {}        # key id -> {"team", "owner", "holder" (pid or -1), "item" (item id or -1)}
var difficulty := 1
var players := {}
var tanks: Array = []
var enemies: Array = []
var shells: Array = []
var bullets: Array = []
var grenades: Array = []
var smokes: Array = []
var items: Array = []
var gates: Array = []
var events := PackedFloat32Array()
var messages: Array = []
var alerts := [false, false, false, false]
var reinforce_t := [10.0, 10.0, 10.0, 10.0]
var loot_t := 8.0
var idol_t := [0.0, 0.0, 0.0, 0.0]
var vault_first := [-1, -1, -1, -1]
var team_target := {}
var target_t := 0.0
var elapsed := 0.0
var time_limit := 900.0
var score_limit := 2500
var winner := -1
var over := false
var rng := RandomNumberGenerator.new()
var next_id := 100
var _ents := PackedFloat32Array()
# random events: one at a time, roughly every 2-2.5 minutes (at least 3-4 in a 10 minute match)
var evt := {}
var evt_next := 90.0
var evt_last := -1
var evt_count := 0
var evt_log: Array = []
# game mode (Defs.MODE_*): heist = keys/puzzles/vault loot, ctf = flags, tdm = kills
var mode := 0
var flags := {}   # ctf: team -> {"home": Vector2, "pos": Vector2, "z", "st" (0 home, 1 carried, 2 dropped), "car" (pid or -1), "t" (return timer)}


func _init(p_map, roster: Array, seed_val: int, p_difficulty := 1, p_time := 900.0, p_score := 2500, p_mode := 0) -> void:
	map = p_map
	mode = clampi(p_mode, 0, Defs.MODE_NAMES.size() - 1)
	difficulty = clampi(p_difficulty, 0, 2)
	time_limit = p_time
	score_limit = p_score
	rng.seed = seed_val + 99
	for g in [astar, tank_astar]:
		g.region = Rect2i(0, 0, map.W, map.H)
		g.cell_size = Vector2(1, 1)
		g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		g.update()
	for y in map.H:
		for x in map.W:
			if map.get_wall(x, y) != 0 or map.obst[y * map.W + x] != 0:
				astar.set_point_solid(Vector2i(x, y), true)
			if not map.tank_cell_ok(x, y):
				tank_astar.set_point_solid(Vector2i(x, y), true)
	for g in map.gates:
		gates.append({"cells": g.cells, "approach": g.approach, "center": g.center, "bunker": g.bunker, "hp": GATE_HP, "open": false})
	for p in map.soldier_spawns:
		_spawn_enemy(Defs.E_SOLDIER, p, false)
	for p in map.turret_spawns:
		_spawn_enemy(Defs.E_TURRET, p, false)
	var team_set := {}
	var members := {}
	for r in roster:
		team_set[int(r.team)] = true
		members[int(r.team)] = int(members.get(int(r.team), 0)) + 1
	R = map.rooms
	V = R
	TEAM_BUNKER = map.team_bunker.duplicate()
	for t in team_set.keys():
		var ti := int(t)
		# one 2-seat vehicle per pair of players: 2 per team in 4-player teams
		var nveh := maxi(1, (int(members[ti]) + 1) / 2)
		if mode == Defs.MODE_WAR:
			nveh = clampi(int(members[ti]) + 2, 4, 10)   # WAR: big fleet up front, vehicles never respawn
		for k in nveh:
			var tk := Tank.new()
			tk.id = 1000 + ti + k * 100
			tk.team = ti
			tk.slot = k
			var s: Vector3 = map.team_spawns[ti]
			# vehicles park side by side, alternating left/right of the first one
			var side := float((k + 1) / 2) * (1.0 if k % 2 == 1 else -1.0)
			var off := Vector2.from_angle(s.z + PI * 0.5) * 3.0 * side
			var sp := Vector2(s.x + off.x, s.y + off.y)
			if map.circle_blocked(sp, 0.7):
				# parking spot blocked (tower, mortar pit...): take the nearest free one
				for rr in range(1, 8):
					var found := false
					for a in 12:
						var c := sp + Vector2.from_angle(a * TAU / 12.0) * float(rr)
						if not map.circle_blocked(c, 0.7):
							sp = c
							found = true
							break
					if found:
						break
			tk.spawn = Vector3(sp.x, sp.y, s.z)
			tk.vtype = rng.randi() % Defs.GROUND_VEHICLES
			var idx := 0
			for r in roster:
				if int(r.team) != ti:
					continue
				if idx / 2 == k and r.has("vehicle"):
					tk.vtype = clampi(int(r.vehicle), 0, Defs.GROUND_VEHICLES - 1)
					break
				idx += 1
			_reset_tank(tk)
			tanks.append(tk)
		if mode == Defs.MODE_WAR:
			_park_planes(ti, maxi(2, int(members[ti]) / 4), nveh)
		teams[ti] = {"score": 0}
		team_pass[ti] = {}
		team_astar[ti] = astar
	for b in map.bunkers.size():
		var owner := -1
		for t in team_set.keys():
			if TEAM_BUNKER[int(t)] == b:
				owner = int(t)
		var acc: Array = []
		acc.resize(R + 1)
		acc.fill(false)
		var sol: Array = []
		sol.resize(R)
		sol.fill(false)
		bstate.append({"owner": owner, "acc": acc, "sol": sol, "pz": _room_puzzles(), "hold": 0.0, "first": -1})
	var slots := {}
	for r in roster:
		var p := Player.new()
		p.id = int(r.pid)
		p.name = str(r.name)
		p.team = int(r.team)
		p.slot = int(slots.get(p.team, 0))
		slots[p.team] = p.slot + 1
		if r.get("bot", false):
			p.bot = Bot.new()
			p.want = [Defs.PRIMARIES[rng.randi() % Defs.PRIMARIES.size()], Defs.SECONDARIES[rng.randi() % Defs.SECONDARIES.size()], rng.randi() % 4]
		elif r.has("loadout"):
			p.want = r.loadout.duplicate()
		players[p.id] = p
		if mode == Defs.MODE_HEIST:
			keys[p.id] = {"team": p.team, "owner": p.id, "bunker": TEAM_BUNKER[p.team], "holder": -1, "item": -1, "used": false}
		_respawn(p)   # everyone starts on foot at their camp; the team vehicles wait next to them
	# bunkers nobody owns: their keys (one per room) are carried by that bunker's guards
	var nk := -1
	for b in map.bunkers.size():
		if int(bstate[b].owner) < 0 and mode == Defs.MODE_HEIST:
			for k in R:
				keys[nk] = {"team": -1, "owner": nk, "bunker": b, "holder": -1, "item": -1, "used": false}
				nk -= 1
	for b in map.bunkers.size():
		if mode != Defs.MODE_HEIST:
			break
		for i in 6:
			_spawn_vault_loot(b, false)
		items.append(_loot_item(4, map.bunkers[b].vault_center, b))
	_pick_team_targets()
	_place_armor()
	evt_next = rng.randf_range(70.0, 110.0)
	if mode == Defs.MODE_CTF:
		for t in teams:
			var fh := _flag_home(int(t))
			flags[int(t)] = {"home": fh, "pos": fh, "z": 0.0, "st": 0, "car": -1, "t": 0.0}
		_msg("CAPTURE THE FLAG: steal an enemy flag and bring it to YOUR flag at your camp. Carriers can't use vehicles!")
	elif mode == Defs.MODE_TDM:
		_msg("TEAM DEATHMATCH: every enemy kill scores (vehicles count double). First to %d kills wins!" % score_limit)
	elif mode == Defs.MODE_WAR:
		_place_points()
		_msg("WAR: capture and hold points A, B and C. Every held point scores. Lost vehicles take a whole minute to come back!")
	else:
		_msg("Each team owns a bunker. Kill enemies for their KEYS - their keys open THEIR bunker. Defend yours!")


func _nid() -> int:
	next_id += 1
	return next_id


# ---------------------------------------------------------------- public

func set_input(pid: int, inp: Array) -> void:
	if players.has(pid) and inp.size() >= INPUT_SIZE:
		players[pid].inp = inp


func remove_player(pid: int) -> void:
	if not players.has(pid):
		return
	var p = players[pid]
	if p.tank != null:
		_exit_tank(p)
	_flag_drop(p)
	_drop_keys(p)
	keys.erase(pid)
	for it in items:
		if it.k == 0 and int(it.key) == pid:
			it.life = 0.0
	_msg("%s left the game" % p.name)
	players.erase(pid)


func step(dt: float) -> void:
	if over:
		return
	elapsed += dt
	target_t -= dt
	if target_t <= 0.0:
		target_t = 8.0
		_pick_team_targets()
	for p in players.values():
		if p.bot != null:
			p.inp = _bot_think(p, dt)
		_update_player(p, dt)
	for t in tanks:
		_update_tank(t, dt)
	_update_shells(dt)
	_update_mortars(dt)
	_update_bullets(dt)
	_update_grenades(dt)
	for e in enemies:
		_update_enemy(e, dt)
	if mode == Defs.MODE_CTF:
		_update_flags(dt)
	elif mode == Defs.MODE_WAR:
		_update_points(dt)
	_update_world(dt)
	_update_events(dt)
	if int(elapsed) % 5 == 0 and int(elapsed - dt) % 5 != 0:
		enemies = enemies.filter(func(e): return not e.dead or elapsed - e.dead_t < 45.0)


func team_keys(team: int) -> int:
	var n := 0
	for p in players.values():
		if p.team == team:
			for k in p.keys:
				if int(keys[k].team) != team:
					n += 1
	return n


func snapshot() -> Dictionary:
	_ents = PackedFloat32Array()
	for en in enemies:
		var fl := 0
		if en.firing_t > 0.0: fl |= 1
		if en.moving: fl |= 2
		if en.dead: fl |= 4
		_pack(en.kind, en.pos, en.yaw, _guard_owner(en), fl, en.hp / en.max_hp, 0.0, en.id)
	for t in tanks:
		var fl := 0
		if t.fire_t > 0.0: fl |= 1
		if t.moving: fl |= 2
		fl |= t.vtype << 8
		fl |= clampi(int(round((t.gun_pitch + 1.0) * 127.5)), 0, 255) << 12
		if _is_plane(t):
			# planes: aux = altitude, bits 20-27 = bank
			fl |= clampi(int(round((clampf(t.bank, -1.0, 1.0) + 1.0) * 127.5)), 0, 255) << 20
			_pack(Defs.E_TANK if t.alive else Defs.E_WRECK, t.pos, t.hull, t.team, fl, t.hp / float(_vs(t).hp), t.z, t.id)
			continue
		_pack(Defs.E_TANK if t.alive else Defs.E_WRECK, t.pos, t.hull, t.team, fl, t.hp / float(_vs(t).hp), t.turret, t.id)
	for p in players.values():
		if p.alive and p.tank == null:
			var fl := 0
			if p.fire_t > 0.0: fl |= 1
			if p.moving: fl |= 2
			if p.crouch: fl |= 16
			if p.air: fl |= 128
			if p.carried > 0: fl |= 32
			if p.keys.size() > 1: fl |= 64
			_pack(Defs.E_PLAYER, p.pos, p.yaw, p.team, fl, p.hp / 100.0, p.z, p.id)
	for s in shells:
		_pack(Defs.E_SHELL, s.pos, s.vel.angle(), s.team, 0, 1.0, s.z, 0)
	for bl in bullets:
		_pack(Defs.E_BULLET, bl.pos, bl.dir.angle(), bl.team, 0, bl.z, bl.speed, bl.id)
	for g in grenades:
		_pack(Defs.E_GRENADE, g.pos, 0.0, g.team, 1 if g.smoke else 0, 1.0, g.z, g.id)
	for s in smokes:
		_pack(Defs.E_SMOKE, s.pos, 0.0, -1, 0, s.life / 12.0, s.r, s.id)
	for it in items:
		if it.k == 2:
			_pack(Defs.E_DROP, it.pos, 0.0, -1, 0, 1.0, 0.0, it.id)
		elif it.k == 3:
			_pack(Defs.E_ARMOR, it.pos, 0.0, -1, 0, 1.0, float(it.get("z", 0.0)), it.id)
		elif it.k == 4:
			_pack(Defs.E_WEAPON, it.pos, 0.0, -1, int(it.wpn), clampf(float(it.life) / WEAPON_DROP_LIFE, 0.0, 1.0), float(it.get("z", 0.0)), it.id)
		elif it.k == 0:
			_pack(Defs.E_KEY, it.pos, 0.0, int(keys[it.key].team) if keys.has(it.key) else -1, 0, 1.0, float(it.get("z", 0.0)), it.id)
		else:
			_pack(Defs.E_LOOT, it.pos, 0.0, -1, 0, float(it.get("z", 0.0)), float(it.kind), it.id)
	for b in map.bunkers.size():
		for r in R:
			_pack(Defs.E_TERMINAL, map.bunkers[b].terminals[r], 0.0, -1, 0, 1.0, float(b * 4 + r), 0)
		_pack(Defs.E_AMMO, map.bunkers[b].ammo, 0.0, -1, 0, 1.0, 0.0, 0)
	for t in teams:
		if int(t) < map.camp_ammo.size():
			_pack(Defs.E_AMMO, map.camp_ammo[int(t)], 0.0, int(t), 0, 1.0, 0.0, 0)
	var fls: Array = []
	for i in cpoints.size():
		var cpd: Dictionary = cpoints[i]
		_pack(Defs.E_POINT, cpd.pos, 0.0, int(cpd.owner), int(cpd.cap) + 1, float(cpd.prog), float(i), 0)
	for ft in flags:
		var f: Dictionary = flags[ft]
		_pack(Defs.E_FLAG, f.pos, 0.0, int(ft), int(f.st), 1.0, float(f.z), 0)
		fls.append([int(ft), f.pos.x, f.pos.y, int(f.st), int(f.car), float(f.t)])
	var pl: Array = []
	for p in players.values():
		var role := _role(p)
		var vpos: Vector2 = p.pos
		var vyaw: float = p.yaw
		var teid := -1
		var thp := 0.0
		var ccd := 0.0
		if p.tank != null:
			var t = p.tank
			vpos = t.pos
			vyaw = t.hull if role == Defs.ROLE_DRIVER else t.turret
			teid = t.id
			thp = t.hp / float(_vs(t).hp)
			ccd = clampf(t.cannon_cd / maxf(0.1, float(_vs(t).main_cd)), 0.0, 1.0)
		if p.bot != null:
			# bots only need what OTHER players' screens use (name tags, scoreboard, fog of war): keeps 16 v 16 light
			pl.append({"id": p.id, "tm": p.team, "role": role, "x": vpos.x, "y": vpos.y, "yaw": vyaw, "hp": p.hp,
				"name": p.name, "kills": p.kills, "bot": true, "z": p.z, "tank": teid, "rsp": p.respawn, "cr": p.crouch})
			continue
		var pz = null
		if p.puzzle >= 0:
			pz = bstate[p.pz_bunker].pz[p.puzzle].duplicate(true)
			pz.r = p.puzzle
			pz.b = p.pz_bunker
		var stolen := 0
		for k in p.keys:
			if int(keys[k].team) != p.team:
				stolen += 1
		pl.append({"id": p.id, "tm": p.team, "role": role, "x": vpos.x, "y": vpos.y, "yaw": vyaw, "hp": p.hp,
			"w": p.weapon, "mag": int(p.mags.get(p.weapon, 0)), "res": int(p.res.get(p.weapon, 0)), "rel": p.reload > 0.0,
			"ep": p.epoch, "prog": p.progress, "hint": p.hint, "rsp": p.respawn, "hurt": p.hurt, "tank": teid,
			"thp": thp, "ccd": ccd, "name": p.name, "kills": p.kills, "shots": p.shots, "mv": p.moving,
			"bot": p.bot != null, "st": p.stamina, "ex": p.exhausted, "cr": p.crouch, "z": p.z, "air": p.air, "sp": p.sprint,
			"loot": p.carried, "eqt": p.equip, "eqn": p.eqn, "pri": p.primary, "sec": p.secondary, "pz": pz,
			"ads": p.ads, "own_key": p.keys.has(p.id), "stolen": stolen})
		(pl.back() as Dictionary)["mortar"] = _mortar_user(p)
		(pl.back() as Dictionary)["hid"] = p.heal_id
		(pl.back() as Dictionary)["ar"] = p.armor
		if p.tank != null and _is_plane(p.tank):
			var pt = p.tank
			(pl.back() as Dictionary)["pl"] = [pt.z, pt.speed, pt.ppitch, pt.bombs, float(_vs(pt).speed), float(_vs(pt).takeoff)]
		(pl.back() as Dictionary)["hw"] = p.hw if p.alive and p.tank == null else -1
	var dyn := PackedInt32Array()
	for g in gates:
		for c in g.cells:
			dyn.append(c.x)
			dyn.append(c.y)
			dyn.append(map.get_wall(c.x, c.y))
	for b in map.bunkers.size():
		for c in map.bunkers[b].doors:
			dyn.append(c.x)
			dyn.append(c.y)
			dyn.append(map.get_wall(c.x, c.y))
	var ts := {}
	for t in teams:
		ts[t] = {"score": teams[t].score, "keys": team_keys(int(t)), "kl": _team_key_list(int(t)) if mode == Defs.MODE_HEIST else []}
	var bs: Array = []
	for b in bstate.size():
		var st: Dictionary = bstate[b]
		var left := 0
		for kid in keys:
			if int(keys[kid].bunker) == b and not keys[kid].used:
				left += 1
		bs.append({"owner": st.owner, "acc": st.acc.duplicate(), "sol": st.sol.duplicate(), "hold": st.hold, "keys": left})
	var ev := events
	events = PackedFloat32Array()
	return {"t": elapsed, "e": _ents, "p": pl, "dyn": dyn, "ev": ev, "msg": messages.duplicate(),
		"alert": alerts.duplicate(), "teams": ts, "bunkers": bs, "tl": maxf(0.0, time_limit - elapsed), "lim": score_limit,
		"win": winner, "over": over, "nkeys": keys.size(), "evt": evt.duplicate(), "mortar": _mortar_snap(), "mode": mode, "flags": fls,
		"cp": _points_snap(), "hold3": hold_all}


# ---------------------------------------------------------------- helpers

func _pack(typ: int, pos: Vector2, ang: float, team: int, fl: int, hp: float, aux: float, id: int) -> void:
	_ents.append(typ)
	_ents.append(pos.x)
	_ents.append(pos.y)
	_ents.append(ang)
	_ents.append(team)
	_ents.append(fl)
	_ents.append(hp)
	_ents.append(aux)
	_ents.append(id)


func _ev(t: int, pos: Vector2, pos2 := Vector2.ZERO) -> void:
	events.append(t)
	events.append(pos.x)
	events.append(pos.y)
	events.append(pos2.x)
	events.append(pos2.y)


func _msg(text: String) -> void:
	messages.append([text, elapsed])
	if messages.size() > 6:
		messages.pop_front()


func _team_tank(team: int):
	for t in tanks:
		if t.team == team:
			return t
	return null


## The vehicle this player crews (players 0-1 of a team share vehicle 0, players 2-3 vehicle 1).
func _slot_tank(p):
	if mode == Defs.MODE_WAR and p.bot != null:
		# the last 4 bots of each team are aircrews: two planes, pilot + bomber each
		var n := 0
		for q in players.values():
			if q.team == p.team:
				n += 1
		if n >= 8 and p.slot >= n - 4:
			var mine: Array = []
			for t in tanks:
				if t.team == p.team and _is_plane(t):
					mine.append(t)
			var idx: int = (p.slot - (n - 4)) / 2
			if idx < mine.size() and mine[idx].alive:
				return mine[idx]
	var best = null
	for t in tanks:
		if t.team == p.team:
			if t.slot == p.slot / 2:
				return t
			if best == null:
				best = t
	return best


func _role(p) -> int:
	if not p.alive:
		return Defs.ROLE_DEAD
	if p.tank == null:
		return Defs.ROLE_FOOT
	# a crew member is EITHER the driver OR the gunner - even alone (switch seats with F)
	return Defs.ROLE_DRIVER if p.seat == 0 else Defs.ROLE_GUNNER


func _radius(t) -> float:
	if t.ttype == 0:
		return 0.3 if t.kind == Defs.E_SOLDIER else 0.45
	if t.ttype == 2:
		return float(Defs.VEHICLES[t.vtype].r)
	return 0.22 if t.crouch else 0.3


## The team whose bunker this guard/turret defends (-1 = neutral bunker, hostile to everyone).
func _guard_owner(e) -> int:
	if e.bunker < 0 or e.bunker >= bstate.size():
		return -1
	return int(bstate[e.bunker].owner)


func _pass(team: int) -> Dictionary:
	return team_pass.get(team, {})


func _hostiles(team: int) -> Array:
	var out: Array = []
	if team >= 0:
		for e in enemies:
			if not e.dead and _guard_owner(e) != team:
				out.append(e)
	for p in players.values():
		if p.alive and p.tank == null and p.team != team:
			out.append(p)
	for t in tanks:
		if t.alive and t.team != team:
			out.append(t)
	return out


func _smoke_blocks(a: Vector2, b: Vector2) -> bool:
	for s in smokes:
		var ab := b - a
		var L2 := ab.length_squared()
		var tt := 0.0 if L2 < 0.0001 else clampf((s.pos - a).dot(ab) / L2, 0.0, 1.0)
		if (a + ab * tt).distance_to(s.pos) < s.r * 0.85:
			return true
	return false


## Vertical extent of things: feet height and body height.
func _base_z(t) -> float:
	return t.z if t.ttype == 1 or t.ttype == 2 else 0.0


func _tall(t) -> float:
	if t.ttype == 1:
		return 0.55 if t.crouch else 0.95
	if t.ttype == 2:
		return [1.1, 1.0, 0.85, 0.95, 1.1, 0.75, 0.9, 0.8][t.vtype]
	return 0.95 if t.kind == Defs.E_SOLDIER else 0.85


func _eye_z(t) -> float:
	if t.ttype == 1 and t.tank != null:
		return 0.75
	return _base_z(t) + _tall(t) * 0.66


func _chest_z(t) -> float:
	return _base_z(t) + _tall(t) * 0.55


## Where bots aim vertically: low enough on soldiers that standing AND crouching bodies get hit
## (crouch-spamming no longer makes them miss), centre mass on everything else.
func _aim_z(t) -> float:
	if t.ttype == 1 and t.tank == null:
		return _base_z(t) + 0.4
	return _chest_z(t)


func _head_z(t) -> float:
	return _base_z(t) + _tall(t) * 0.9


func _see(a: Vector2, b: Vector2, pass_cells := {}) -> bool:
	return map.los3(a, 0.62, b, 0.55, pass_cells) and not _smoke_blocks(a, b)


## 3D visibility between two entities: 0 = hidden, 1 = only the head shows over cover, 2 = clearly visible.
func _vis(a, b, pass_cells := {}) -> int:
	if _smoke_blocks(a.pos, b.pos):
		return 0
	var ez := _eye_z(a)
	if map.los3(a.pos, ez, b.pos, _chest_z(b), pass_cells):
		return 2
	if map.los3(a.pos, ez, b.pos, _head_z(b), pass_cells):
		return 1
	return 0


func _ray_circle(o: Vector2, d: Vector2, c: Vector2, r: float) -> float:
	var oc := c - o
	var tp := oc.dot(d)
	if tp < 0.0:
		return -1.0
	var d2 := oc.length_squared() - tp * tp
	if d2 > r * r:
		return -1.0
	return maxf(0.0, tp - sqrt(r * r - d2))


func _spawn_enemy(kind: int, pos: Vector2, alerted: bool):
	var e := Enemy.new()
	e.id = _nid()
	e.kind = kind
	e.pos = pos
	e.home = pos
	e.wander = pos
	e.bunker = map.bunker_at(pos)
	if e.bunker < 0:
		var bd := 1e9
		for i in map.bunkers.size():
			var d: float = pos.distance_to(map.bunkers[i].center)
			if d < bd:
				bd = d
				e.bunker = i
	e.yaw = rng.randf() * TAU
	if kind == Defs.E_TURRET:
		e.hp = 350.0
		e.max_hp = 350.0
	e.alerted = alerted
	e.see_t = rng.randf() * 0.3
	e.wander_t = rng.randf_range(1.0, 4.0)
	enemies.append(e)
	return e


func _set_solid_all(c: Vector2i, solid: bool) -> void:
	astar.set_point_solid(c, solid)
	for t in team_astar:
		if not (team_pass[t].has(c) and not solid):
			team_astar[t].set_point_solid(c, solid)


func _near_bunker(p: Vector2) -> int:
	var best := -1
	var bd := 22.0
	for i in map.bunkers.size():
		var d: float = p.distance_to(map.bunkers[i].center)
		if d < bd:
			bd = d
			best = i
	return best


# ---------------------------------------------------------------- keys

func _loot_item(kind: int, pos: Vector2, bunker: int) -> Dictionary:
	return {"id": _nid(), "k": 1, "kind": kind, "pos": pos, "value": Defs.LOOT_VALUES[kind], "life": 1e9, "vault": bunker}


func _give_key(p, kid: int) -> void:
	var k: Dictionary = keys[kid]
	k.holder = p.id
	k.item = -1
	if not p.keys.has(kid):
		p.keys.append(kid)


## A loose key goes back to its owner if they are alive, otherwise it waits until they respawn.
func _return_key(kid: int) -> void:
	if not keys.has(kid):
		return
	var k: Dictionary = keys[kid]
	if k.holder >= 0 and players.has(k.holder):
		players[k.holder].keys.erase(kid)
	k.holder = -1
	k.item = -1
	if not k.used and players.has(kid) and players[kid].alive:
		_give_key(players[kid], kid)


## Using a key on a door consumes it for good (until the owners reclaim their bunker).
func _consume_key(kid: int) -> void:
	var k: Dictionary = keys[kid]
	if k.holder >= 0 and players.has(k.holder):
		players[k.holder].keys.erase(kid)
	k.holder = -1
	k.item = -1
	k.used = true


func _drop_keys(p) -> void:
	var i := 0
	var n: int = p.keys.size()
	for kid in p.keys:
		var off := Vector2.from_angle(TAU * float(i) / maxf(1.0, float(n))) * 0.35
		var it := {"id": _nid(), "k": 0, "key": kid, "pos": p.pos + off, "life": KEY_RETURN_TIME, "z": p.z}
		items.append(it)
		keys[kid].holder = -1
		keys[kid].item = it.id
		i += 1
	p.keys.clear()


# ---------------------------------------------------------------- players

func _respawn(p) -> void:
	var s: Vector3 = map.team_spawns[p.team]
	var base := Vector2(s.x, s.y)
	var fp := _war_spawn_point(p.team)
	if fp != Vector2.INF:
		base = fp
	p.pos = base
	# every team member gets their own spot on a ring around the camp (no stacking on one point),
	# on the side away from the map edge; skip spots that are blocked or already taken
	var placed := false
	# 3 rings of 8 around the camp; WAR (16 per team) adds 2 more rings of 12
	for ring in [2.6, 3.6, 1.8, 4.8, 6.0]:
		var nk: int = 8 if float(ring) < 4.0 else 12
		for k in nk:
			var a: float = s.z + (float((p.slot + k) % nk) - (float(nk) - 1.0) * 0.5) * (0.42 if nk == 8 else 0.3)
			var c: Vector2 = base + Vector2.from_angle(a) * float(ring)
			if map.circle_blocked(c, PLAYER_R, {}, 0.0):
				continue
			var taken := false
			for q in players.values():
				if q != p and q.alive and q.tank == null and q.pos.distance_to(c) < 0.9:
					taken = true
			for t in tanks:
				if t.alive and t.pos.distance_to(c) < float(_vs(t).r) + 0.5:
					taken = true
			if not taken:
				p.pos = c
				placed = true
				break
		if placed:
			break
	p.alive = true
	p.hp = 100.0
	p.spawn_t = elapsed
	p.spawn_shots = p.shots
	p.primary = int(p.want[0]) if Defs.PRIMARIES.has(int(p.want[0])) else Defs.W_RIFLE
	p.secondary = int(p.want[1]) if Defs.SECONDARIES.has(int(p.want[1])) else Defs.W_PISTOL
	p.equip = clampi(int(p.want[2]), 0, 3)
	_refill(p)
	p.weapon = p.primary
	p.reload = 0.0
	p.cool = 0.0
	p.yaw = s.z
	p.epoch += 1
	p.progress = 0.0
	p.hurt = 0.0
	p.stamina = 1.0
	p.exhausted = false
	p.z = 0.0
	p.vz = 0.0
	p.puzzle = -1
	p.carried = 0
	if keys.has(p.id) and keys[p.id].holder < 0 and keys[p.id].item < 0 and not keys[p.id].used:
		_give_key(p, p.id)


func _refill(p) -> void:
	var mult := 1.6 if p.equip == Defs.EQ_AMMO else 1.0
	for w in [p.primary, p.secondary]:
		var wd: Dictionary = Defs.WPN[w]
		p.mags[w] = int(wd.mag)
		p.res[w] = -1 if int(wd.reserve) < 0 else int(int(wd.reserve) * mult)
	p.eqn = Defs.EQUIP_COUNT[p.equip]


func _update_player(p, dt: float) -> void:
	p.hurt = maxf(0.0, p.hurt - dt * 1.5)
	p.fire_t -= dt
	p.ammo_cd -= dt
	if not p.alive:
		p.respawn -= dt
		if p.inp.size() >= INPUT_SIZE:
			p.want = [int(p.inp[I_PRI]), int(p.inp[I_SEC]), int(p.inp[I_EQ])]
		if p.respawn <= 0.0 and not over:
			_respawn(p)
		return
	if p.tank != null:
		p.pos = p.tank.pos
	if p.inp.size() < INPUT_SIZE:
		return
	var inp: Array = p.inp
	var nw: Array = [int(inp[I_PRI]), int(inp[I_SEC]), int(inp[I_EQ])]
	if nw != p.want and p.tank == null and elapsed - p.spawn_t < 6.0 and p.shots == p.spawn_shots:
		# still at the spawn and hasn't fired: a new loadout applies right away (fixes the first spawn of a
		# match ignoring the picked loadout, and lets you fix your kit right after respawning)
		p.want = nw
		p.primary = int(nw[0]) if Defs.PRIMARIES.has(int(nw[0])) else p.primary
		p.secondary = int(nw[1]) if Defs.SECONDARIES.has(int(nw[1])) else p.secondary
		p.equip = clampi(int(nw[2]), 0, 3)
		_refill(p)
		p.weapon = p.primary
		p.reload = 0.0
	p.want = nw
	var epoch_ok: bool = int(inp[I_EPOCH]) == p.epoch
	var use_pressed: bool = int(inp[I_USEC]) != p.use_count
	p.use_count = int(inp[I_USEC])
	var seat_pressed: bool = int(inp[I_SEATC]) != p.seat_count
	p.seat_count = int(inp[I_SEATC])
	p.seat_edge = seat_pressed
	var reload_pressed: bool = int(inp[I_RELC]) != p.reload_count
	p.reload_count = int(inp[I_RELC])
	var jump_pressed: bool = int(inp[I_JUMPC]) != p.jump_count
	p.jump_count = int(inp[I_JUMPC])
	var throw_pressed: bool = int(inp[I_THROWC]) != p.throw_count
	p.throw_count = int(inp[I_THROWC])
	var wreq := -1
	if int(inp[I_WSEQ]) != p.weapon_seq:
		p.weapon_seq = int(inp[I_WSEQ])
		wreq = int(inp[I_WREQ])
	var fire: bool = bool(inp[I_FIRE])
	var fire_edge: bool = fire and not p.fire_prev
	p.fire_prev = fire
	if p.tank != null:
		_player_in_tank(p, inp, use_pressed, seat_pressed, epoch_ok)
		return
	if _mortar_user(p):
		_player_at_mortar(p, inp, use_pressed, fire, dt)
		return
	if epoch_ok:
		p.yaw = float(inp[I_YAW])
	p.pitch = clampf(float(inp[I_PITCH]), -MAX_PITCH, MAX_PITCH)
	if p.puzzle >= 0:
		p.moving = false
		p.sprint = false
		p.ads = false
		_regen_stamina(p, dt)
		_update_puzzle(p, inp, use_pressed, fire_edge, dt)
		return
	var pass_cells := _pass(p.team)
	var gnd: float = map.ground_at(p.pos, PLAYER_R, p.z, pass_cells)
	var on_ground: bool = p.z <= gnd + 0.01 and p.vz <= 0.0
	p.crouch = bool(inp[I_CROUCH]) and on_ground
	p.ads = bool(inp[I_ALT])
	var my := float(inp[I_MY])
	# stamina: running it dry locks sprinting until it has fully recovered
	p.sprint = bool(inp[I_SPRINT]) and my > 0.3 and not p.exhausted and not p.crouch and not p.ads
	if p.sprint:
		p.stamina = maxf(0.0, p.stamina - dt * 0.2)
		p.cool = maxf(p.cool, 0.15)
		if p.stamina <= 0.0:
			p.exhausted = true
			p.sprint = false
	else:
		_regen_stamina(p, dt)
	if jump_pressed and on_ground and not p.crouch and p.stamina > 0.1:
		p.vz = JUMP_V
		p.peak = p.z
		p.stamina = maxf(0.0, p.stamina - 0.08)
	var fwd := Vector2.from_angle(p.yaw)
	var right := Vector2(-fwd.y, fwd.x)
	var mv: Vector2 = fwd * my + right * float(inp[I_MX])
	if mv.length() > 1.0:
		mv = mv.normalized()
	var speed: float = BASE_SPEED * float(Defs.WPN[p.weapon].speed)
	if p.crouch:
		speed *= 0.5
	elif p.sprint:
		speed *= SPRINT_MULT
	elif p.exhausted:
		speed *= 0.85
	if p.ads:
		speed *= 0.6
	if p.carried > 0:
		speed *= 0.9
	if on_ground and p.z < 0.05 and map.floor_at(p.pos) == MapData.F_WATER:
		speed *= 0.7
	var np: Vector2 = map.move_circle(p.pos, mv * speed * dt, PLAYER_R, pass_cells, p.z)
	np = _push_from_tanks(np, p.team)
	p.moving = np.distance_squared_to(p.pos) > 0.000001
	p.pos = np
	_vertical(p, dt, pass_cells)
	if wreq >= 1 and wreq <= 3:
		var w: int = [p.primary, p.secondary, Defs.W_KNIFE][wreq - 1]
		if w != p.weapon:
			p.weapon = w
			p.reload = 0.0
			p.cool = 0.35
	p.cool -= dt
	if p.reload > 0.0:
		p.reload -= dt
		if p.reload <= 0.0:
			_finish_reload(p)
	if reload_pressed:
		_start_reload(p)
	var wd: Dictionary = Defs.WPN[p.weapon]
	var trigger: bool = fire if bool(wd.auto) else fire_edge
	var burst: int = int(wd.get("burst", 0))
	if p.burst_left > 0 and (burst <= 0 or p.reload > 0.0 or p.sprint):
		p.burst_left = 0
	if p.burst_left > 0:
		if p.cool <= 0.0:
			p.burst_left -= 1
			_fire_weapon(p)
	elif trigger and p.cool <= 0.0 and p.reload <= 0.0 and not p.sprint:
		p.burst_left = maxi(0, burst - 1)
		_fire_weapon(p)
	if throw_pressed:
		_use_equipment(p)
	_pickups(p)
	_interact(p, use_pressed)
	_heal_hint(p)


## Gravity, stepping up/down stairs and ledges, ceilings and fall damage.
func _vertical(p, dt: float, pass_cells: Dictionary) -> void:
	var gnd: float = map.ground_at(p.pos, PLAYER_R, p.z, pass_cells)
	if p.vz > 0.0 or p.z > gnd + MapData.STEP or (p.air and p.z > gnd + 0.001):
		if not p.air:
			p.peak = p.z
		p.air = true
		p.z += p.vz * dt
		p.vz -= GRAVITY * dt
		p.peak = maxf(p.peak, p.z)
		var head: float = 0.62 if p.crouch else MapData.HEAD
		var ceil_h: float = map.ceiling_at(p.pos, PLAYER_R, p.z)
		if p.z + head > ceil_h:
			p.z = maxf(gnd, ceil_h - head)
			p.vz = minf(p.vz, 0.0)
		if p.z <= gnd:
			var drop: float = p.peak - gnd
			p.z = gnd
			p.vz = 0.0
			p.air = false
			if drop > FALL_SAFE:
				_damage(p, (drop - FALL_SAFE) * 55.0, null, false)
				_ev(Defs.EV_HIT, p.pos)
	else:
		p.z = gnd   # walk up / down a step
		p.vz = 0.0
		p.air = false


func _regen_stamina(p, dt: float) -> void:
	p.stamina = minf(1.0, p.stamina + dt * (0.09 if p.exhausted else 0.12))
	if p.exhausted and p.stamina >= 1.0:
		p.exhausted = false


func _push_from_tanks(pos: Vector2, team: int) -> Vector2:
	for t in tanks:
		var d: Vector2 = pos - t.pos
		var L := d.length()
		var minr := _radius(t) + PLAYER_R
		if L < minr:
			var n := d / L if L > 0.001 else Vector2.RIGHT
			var cand: Vector2 = t.pos + n * minr
			if not map.circle_blocked(cand, PLAYER_R, _pass(team)):
				pos = cand
	return pos


func _start_reload(p) -> void:
	if p.weapon == Defs.W_KNIFE or p.reload > 0.0:
		return
	var wd: Dictionary = Defs.WPN[p.weapon]
	if int(p.mags.get(p.weapon, 0)) >= int(wd.mag):
		return
	if int(p.res.get(p.weapon, 0)) == 0:
		return
	p.reload = float(wd.reload)


func _finish_reload(p) -> void:
	p.reload = 0.0
	var wd: Dictionary = Defs.WPN[p.weapon]
	var need: int = int(wd.mag) - int(p.mags.get(p.weapon, 0))
	var r: int = int(p.res.get(p.weapon, 0))
	if r < 0:
		p.mags[p.weapon] = int(wd.mag)
		return
	var take := mini(need, r)
	p.mags[p.weapon] = int(p.mags.get(p.weapon, 0)) + take
	p.res[p.weapon] = r - take


func _fire_weapon(p) -> void:
	var wd: Dictionary = Defs.WPN[p.weapon]
	if p.weapon == Defs.W_KNIFE:
		p.cool = float(wd.cd)
		p.shots += 1
		_ev(Defs.EV_KNIFE, p.pos)
		_melee(p)
		return
	if int(p.mags.get(p.weapon, 0)) <= 0:
		p.burst_left = 0
		_start_reload(p)
		return
	p.mags[p.weapon] = int(p.mags[p.weapon]) - 1
	p.cool = float(wd.burst_cd) if p.burst_left > 0 else float(wd.cd)
	p.shots += 1
	p.fire_t = 0.08
	var spread: float = float(wd.spread)
	if p.weapon == Defs.W_SNIPER and not p.ads:
		spread = 0.07
	elif wd.has("hip") and not p.ads:
		spread = float(wd.hip)
	if p.moving:
		spread *= 1.6
	if p.crouch:
		spread *= 0.6
	if p.ads:
		spread *= 0.4
	if p.air:
		spread *= 2.5
	var ez := _eye_z(p) - 0.04
	var pitch: float = p.pitch
	if p.inp.size() > I_AUTO and bool(p.inp[I_AUTO]):
		pitch = _auto_pitch(p, pitch, ez, float(wd.reach))
	if wd.has("rocket"):
		_fire_rocket(p, wd, spread, ez, pitch)
		return
	for i in int(wd.pellets):
		var sl := tan(clampf(pitch + rng.randfn(0.0, spread * 0.5), -1.3, 1.3))
		_spawn_bullet(p.pos, p.yaw + rng.randfn(0.0, spread * 0.6), float(wd.vel), float(wd.reach), float(wd.dmg), p.team, p, ez, sl)
	_ev(Defs.EV_SHOT, p.pos, Vector2(p.weapon, 0))
	if int(p.mags[p.weapon]) <= 0:
		_start_reload(p)


## Rocket launcher: a slow explosive projectile on the vehicle-shell path (_update_shells/_explode),
## full damage to vehicles and gates.
func _fire_rocket(p, wd: Dictionary, spread: float, ez: float, pitch: float) -> void:
	var d := Vector2.from_angle(p.yaw + rng.randfn(0.0, spread * 0.6))
	var s := Shell.new()
	s.pos = p.pos + d * 0.3
	s.vel = d * float(wd.vel)
	s.team = p.team
	s.owner = p
	s.dmg = float(wd.dmg)
	s.splash = float(wd.rocket)
	s.life = float(wd.reach) / float(wd.vel)
	s.z = ez
	s.slope = tan(clampf(pitch + rng.randfn(0.0, spread * 0.5), -1.2, 1.2))
	shells.append(s)
	_ev(Defs.EV_SHOT, p.pos, Vector2(p.weapon, 0))
	if int(p.mags[p.weapon]) <= 0:
		_start_reload(p)


func _spawn_bullet(pos: Vector2, ang: float, speed: float, reach: float, dmg: float, team: int, owner, z := 0.6, slope := 0.0) -> void:
	var b := Bullet.new()
	b.id = _nid()
	b.dir = Vector2.from_angle(ang)
	b.pos = pos
	b.z = z
	b.slope = slope
	b.speed = speed
	b.left = reach
	b.dmg = dmg
	b.team = team
	b.owner = owner
	bullets.append(b)


## Vertical aim assist (gamepads / shared keyboard): snap the shot's pitch onto a target in the crosshair column.
func _auto_pitch(p, pitch: float, ez: float, reach: float) -> float:
	var best := pitch
	var bd := reach
	var f := Vector2.from_angle(p.yaw)
	for t in _hostiles(p.team):
		var to: Vector2 = t.pos - p.pos
		var d := to.length()
		if d < 0.5 or d > bd:
			continue
		var lat := absf(to.dot(Vector2(-f.y, f.x)))
		if to.dot(f) <= 0.0 or lat > _radius(t) + 0.15:
			continue
		var want := atan2(_chest_z(t) - ez, d)
		if absf(want - pitch) < 0.45 and map.los3(p.pos, ez, t.pos, _chest_z(t), _pass(p.team)):
			best = want
			bd = d
	return best


## Bullets are real projectiles flying through the 3D height field: they travel at the weapon's muzzle
## speed (a sniper shot at range can be dodged), fly over low cover, and hit high or low on a body.
func _update_bullets(dt: float) -> void:
	var keep: Array = []
	for b in bullets:
		var stp: float = minf(b.speed * dt, b.left)
		var wr: Dictionary = map.ray3(b.pos, b.z, b.dir, b.slope, stp, _pass(b.team))
		var best_t: float = float(wr.dist) if wr.hit else stp
		var best = null
		var best_z := 0.0
		for t in _hostiles(b.team):
			var h := _ray_circle(b.pos, b.dir, t.pos, _radius(t))
			if h < 0.0 or h > best_t:
				continue
			var tc := maxf(h, (t.pos - b.pos).dot(b.dir))
			var z0: float = b.z + b.slope * h
			var z1: float = b.z + b.slope * tc
			var lo := _base_z(t) - 0.05
			var hi := _base_z(t) + _tall(t)
			var zh := z0 if (z0 >= lo and z0 <= hi) else z1
			if zh >= lo and zh <= hi:
				best_t = h
				best = t
				best_z = zh
		var hp: Vector2 = b.pos + b.dir * best_t
		if best != null:
			var dmg: float = b.dmg
			var head: bool = best.ttype != 2 and not (best.ttype == 0 and best.kind == Defs.E_TURRET) and best_z > _base_z(best) + _tall(best) * 0.8
			if head:
				dmg *= 1.8
			_damage(best, dmg, b.owner, false)
			_ev(Defs.EV_HIT if best.ttype != 2 else Defs.EV_IMPACT, hp, Vector2(1.0 if head else 0.0, best_z))
			continue
		if wr.hit:
			_ev(Defs.EV_IMPACT, b.pos + b.dir * maxf(0.0, best_t - 0.05), Vector2(float(wr.z), 0.0))
			if wr.wall:
				_damage_cell(wr.cell, b.dmg * 0.6)
			continue
		b.pos = hp
		b.z += b.slope * stp
		b.left -= stp
		if b.left > 0.01:
			keep.append(b)
	bullets = keep


func _use_equipment(p) -> void:
	if p.eqn <= 0:
		return
	if p.equip == Defs.EQ_MEDKIT:
		var mate = _heal_target(p)
		if mate != null:
			mate.hp = minf(100.0, mate.hp + 50.0)
			p.eqn -= 1
			p.cool = maxf(p.cool, 0.4)
			_ev(Defs.EV_HEAL, mate.pos, Vector2(1.0, 0.0))
			_msg("%s healed %s" % [p.name, mate.name])
			return
		if p.hp >= 100.0:
			return
		p.hp = minf(100.0, p.hp + 50.0)
		p.eqn -= 1
		_ev(Defs.EV_HEAL, p.pos)
		return
	if p.equip != Defs.EQ_FRAG and p.equip != Defs.EQ_SMOKE:
		return
	p.eqn -= 1
	var g := Grenade.new()
	g.id = _nid()
	var d := Vector2.from_angle(p.yaw)
	var sp := 9.5 if not p.crouch else 6.5
	var pa := clampf(p.pitch, -0.6, 0.9)
	g.pos = p.pos + d * 0.2
	g.z = _eye_z(p) - 0.1
	g.vel = d * sp * cos(pa)
	g.vz = 2.0 + sp * sin(pa)
	g.team = p.team
	g.owner = p
	g.smoke = p.equip == Defs.EQ_SMOKE
	g.fuse = 1.6 if g.smoke else 2.1
	grenades.append(g)
	p.cool = maxf(p.cool, 0.4)
	_ev(Defs.EV_THROW, p.pos)


const HEAL_REACH := 2.2

## The hurt teammate on foot a medkit would heal: within HEAL_REACH, roughly in the crosshair, in sight.
func _heal_target(p):
	var best = null
	var bd := HEAL_REACH + PLAYER_R
	var f := Vector2.from_angle(p.yaw)
	for q in players.values():
		if q == p or q.team != p.team or not q.alive or q.tank != null or q.hp >= 100.0:
			continue
		var to: Vector2 = q.pos - p.pos
		var d := to.length()
		if d > bd or absf(q.z - p.z) > 1.0:
			continue
		var lat := absf(to.dot(Vector2(-f.y, f.x)))
		if (d > 0.3 and to.dot(f) <= 0.0) or lat > PLAYER_R + 0.35:
			continue
		if not map.los3(p.pos, _eye_z(p), q.pos, _chest_z(q), _pass(p.team)):
			continue
		best = q
		bd = d
	return best


func _heal_hint(p) -> void:
	p.heal_id = -1
	if p.equip != Defs.EQ_MEDKIT or p.eqn <= 0:
		return
	var mate = _heal_target(p)
	if mate != null:
		p.heal_id = mate.id
		if p.hint == 0:
			p.hint = Defs.H_HEAL


func _melee(p) -> void:
	var best = null
	var bd := 99.0
	var f := Vector2.from_angle(p.yaw)
	for t in _hostiles(p.team):
		var to: Vector2 = t.pos - p.pos
		var d := to.length()
		if d < float(Defs.WPN[0].reach) + _radius(t) and d < bd and absf(_base_z(t) - p.z) < 0.9:
			if (d < 0.3 or f.dot(to / d) > 0.5) and map.los3(p.pos, _eye_z(p), t.pos, _chest_z(t), _pass(p.team)):
				best = t
				bd = d
	if best != null:
		_damage(best, float(Defs.WPN[0].dmg), p, false)
		_ev(Defs.EV_HIT, best.pos)


func _damage(t, dmg: float, attacker, explosive: bool) -> void:
	if t.ttype == 0:
		if t.dead:
			return
		var d := dmg if (t.kind == Defs.E_SOLDIER or explosive) else dmg * 0.2
		t.hp -= d
		t.alerted = true
		if attacker != null:
			t.last_known = attacker.pos
			t.has_lk = true
		if t.bunker >= 0:
			alerts[t.bunker] = true
		if t.hp <= 0.0:
			_kill_enemy(t, attacker)
	elif t.ttype == 1:
		if not t.alive:
			return
		if t.armor > 0.0:
			var soak: float = minf(t.armor, dmg * ARMOR_ABSORB)
			t.armor -= soak
			dmg -= soak
		t.hp -= dmg
		t.hurt = 1.0
		if t.hp <= 0.0:
			_kill_player(t, attacker)
	else:
		if not t.alive:
			return
		t.hp -= dmg if explosive else dmg * float(_vs(t).armor)
		for o in [t.driver, t.gunner]:
			if o != null:
				o.hurt = maxf(o.hurt, 0.5)
		if t.hp <= 0.0:
			_destroy_tank(t, attacker)


func _kill_enemy(e, killer) -> void:
	if e.dead:
		return
	e.dead = true
	e.dead_t = elapsed
	e.hp = 0.0
	e.moving = false
	if e.kind == Defs.E_SOLDIER:
		_drop_weapon(Defs.W_RIFLE, int(Defs.WPN[Defs.W_RIFLE].mag), 60, e.pos, 0.0)
	if killer != null and killer.ttype == 1:
		killer.kills += 1
		if e.kind == Defs.E_SOLDIER and rng.randf() < 0.35:
			for kid in keys:
				var k: Dictionary = keys[kid]
				if int(k.team) < 0 and int(k.bunker) == e.bunker and k.holder < 0 and k.item < 0 and not k.used:
					var it := {"id": _nid(), "k": 0, "key": kid, "pos": e.pos, "life": KEY_RETURN_TIME}
					items.append(it)
					k.item = it.id
					break


func _kill_player(p, killer) -> void:
	_flag_drop(p)
	p.alive = false
	p.hp = 0.0
	p.respawn = PLAYER_RESPAWN
	p.progress = 0.0
	p.moving = false
	p.puzzle = -1
	if p.primary != Defs.W_KNIFE:
		_drop_weapon(p.primary, int(p.mags.get(p.primary, 0)), int(p.res.get(p.primary, 0)), p.pos + Vector2(-0.3, 0.2), p.z)
	p.armor = 0.0
	p.z = 0.0
	var dropped: int = p.keys.size()
	_drop_keys(p)
	if p.carried > 0:
		items.append({"id": _nid(), "k": 1, "kind": 5, "pos": p.pos + Vector2(0.3, 0.0), "value": p.carried, "life": 90.0, "vault": -1, "z": p.z})
		p.carried = 0
	var kmsg := ""
	if dropped > 0:
		kmsg = " - %d key%s dropped!" % [dropped, "" if dropped == 1 else "s"]
	if killer != null and killer.ttype == 1 and killer != p:
		killer.kills += 1
		if mode == Defs.MODE_TDM and killer.team != p.team and teams.has(killer.team):
			teams[killer.team].score += 1
		if evt_active(Defs.EVT_BOUNTY) and p.team == int(evt.team) and killer.team != p.team and mode != Defs.MODE_CTF:
			var bv: int = Defs.BOUNTY_VALUE if mode == Defs.MODE_HEIST else 1
			teams[killer.team].score += bv
			_ev(Defs.EV_DEPOSIT, killer.pos, Vector2(bv, killer.team))
			_msg("BOUNTY collected by %s: +%d for %s" % [killer.name, bv, Defs.TEAM_NAMES[killer.team]])
		_msg("%s [%s] killed %s [%s]%s" % [killer.name, Defs.TEAM_NAMES[killer.team], p.name, Defs.TEAM_NAMES[p.team], kmsg])
	else:
		_msg("%s [%s] was killed%s" % [p.name, Defs.TEAM_NAMES[p.team], kmsg])


func _pickups(p) -> void:
	var keep: Array = []
	for it in items:
		if p.pos.distance_to(it.pos) > 0.7 or absf(p.z - float(it.get("z", 0.0))) > 0.9:
			keep.append(it)
			continue
		if it.k == 0:
			var kid: int = it.key
			if not keys.has(kid):
				continue
			var kt: int = keys[kid].team
			if kt == p.team:
				_return_key(kid)
				if kid != p.id:
					_msg("%s recovered a %s key" % [p.name, Defs.TEAM_NAMES[p.team]])
			else:
				_give_key(p, kid)
				_msg("%s [%s] grabbed a %s key" % [p.name, Defs.TEAM_NAMES[p.team], "guard's" if kt < 0 else Defs.TEAM_NAMES[kt]])
			_ev(Defs.EV_PICKUP, it.pos, Vector2(0, 0))
		elif it.k == 3:
			# armor vest: only taken when it helps
			if p.armor >= 99.0:
				keep.append(it)
				continue
			p.armor = 100.0
			var si: int = int(it.get("spot", -1))
			if si >= 0 and si < armor_spots.size():
				armor_spots[si].t = ARMOR_RESPAWN
			_ev(Defs.EV_PICKUP, it.pos, Vector2(0, 0))
		elif it.k == 4:
			keep.append(it)   # guns are picked up with [use] (see _weapon_pickup)
			continue
		elif it.k == 2:
			# supply crate: loot to bank + full refit
			p.carried += int(it.value)
			p.hp = 100.0
			_refill(p)
			_ev(Defs.EV_PICKUP, it.pos, Vector2(1, 0))
			_msg("%s [%s] grabbed the SUPPLY CRATE (+%d loot)" % [p.name, Defs.TEAM_NAMES[p.team], int(it.value)])
		else:
			if int(it.vault) >= 0 and int(bstate[int(it.vault)].owner) == p.team:
				keep.append(it)   # you can't rob your own vault
				continue
			p.carried += int(it.value)
			_ev(Defs.EV_PICKUP, it.pos, Vector2(1, 0))
			if int(it.kind) == 4 and int(it.vault) >= 0:
				idol_t[int(it.vault)] = 60.0
	items = keep


## A key this player holds that opens bunker b (or any bunker if b < 0); -99999 if none.
func _stolen_key(p, b := -1) -> int:
	for k in p.keys:
		var kd: Dictionary = keys[k]
		if int(kd.team) != p.team and (b < 0 or int(kd.bunker) == b):
			return int(k)
	return -99999


## Like _stolen_key, but also any key a living teammate carries: keys are shared by the whole team.
func _team_key(p, b := -1) -> int:
	var kid := _stolen_key(p, b)
	if kid != -99999:
		return kid
	for q in players.values():
		if q != p and q.team == p.team and q.alive:
			kid = _stolen_key(q, b)
			if kid != -99999:
				return kid
	return -99999


## The team's stolen keys for the HUD: [key team, bunker, holder id] each.
func _team_key_list(team: int) -> Array:
	var out: Array = []
	for q in players.values():
		if q.team == team:
			for k in q.keys:
				var kd: Dictionary = keys[k]
				if int(kd.team) != team:
					out.append([int(kd.team), int(kd.bunker), int(q.id)])
	return out


# ---------------------------------------------------------------- armor & dropped weapons

var armor_spots: Array = []   # {pos, z, t}: t > 0 = respawn countdown, item back when it runs out


## Scatter armor vests over open ground (host only - clients just see the items in the snapshot).
func _place_armor() -> void:
	armor_spots.clear()
	var want: int = 10 if map.W <= 160 else 12
	var tries := 0
	while armor_spots.size() < want and tries < 4000:
		tries += 1
		var c := Vector2(rng.randf_range(6.0, map.W - 6.0), rng.randf_range(6.0, map.H - 6.0))
		var cx := floori(c.x)
		var cy := floori(c.y)
		if map.circle_blocked(c, 0.5, {}, 0.0) or map.has_roof(cx, cy) or map.bunker_at(c) >= 0:
			continue
		var ok := true
		for s in map.team_spawns:
			if c.distance_to(Vector2(s.x, s.y)) < 14.0:
				ok = false
		for a in armor_spots:
			if c.distance_to(a.pos) < 18.0:
				ok = false
		if ok:
			armor_spots.append({"pos": Vector2(cx + 0.5, cy + 0.5), "z": 0.0, "t": 0.0})
	for i in armor_spots.size():
		_spawn_armor(i)


func _spawn_armor(i: int) -> void:
	var a: Dictionary = armor_spots[i]
	items.append({"id": _nid(), "k": 3, "pos": a.pos, "life": 1e9, "z": float(a.z), "spot": i})


func _update_armor(dt: float) -> void:
	for i in armor_spots.size():
		var a: Dictionary = armor_spots[i]
		if float(a.t) > 0.0:
			a.t = float(a.t) - dt
			if float(a.t) <= 0.0:
				_spawn_armor(i)


func _drop_weapon(w: int, mag: int, res: int, pos: Vector2, z: float) -> void:
	if w <= Defs.W_KNIFE or w >= Defs.WPN.size():
		return
	items.append({"id": _nid(), "k": 4, "wpn": w, "mag": mag, "res": res, "pos": pos, "life": WEAPON_DROP_LIFE, "z": z})


## [use] next to a dropped gun: it replaces your primary (or sidearm), your old one drops in its place.
func _weapon_pickup(p, pressed: bool) -> bool:
	p.hw = -1
	var best = null
	var bd := 1.1
	for it in items:
		if it.k == 4 and absf(p.z - float(it.get("z", 0.0))) < 0.9:
			var d: float = p.pos.distance_to(it.pos)
			if d < bd:
				bd = d
				best = it
	if best == null:
		return false
	var w: int = int(best.wpn)
	p.hw = w
	p.hint = Defs.H_WEAPON
	if not pressed:
		return true
	items.erase(best)
	var side: bool = Defs.SECONDARIES.has(w)
	var old: int = p.secondary if side else p.primary
	if old == w:
		# same gun: just take the ammo
		p.res[w] = -1 if int(p.res.get(w, 0)) < 0 else int(p.res.get(w, 0)) + int(best.mag) + maxi(0, int(best.res))
	else:
		_drop_weapon(old, int(p.mags.get(old, 0)), int(p.res.get(old, 0)), best.pos, float(best.get("z", 0.0)))
		if side:
			p.secondary = w
		else:
			p.primary = w
		p.mags[w] = int(best.mag)
		p.res[w] = int(best.res)
		p.weapon = w
		p.reload = 0.0
		p.cool = 0.3
	_ev(Defs.EV_PICKUP, best.pos, Vector2(0, 0))
	return true


func _interact(p, pressed: bool) -> void:
	p.hint = 0
	p.progress = 0.0
	if _weapon_pickup(p, pressed):
		return
	var ts: Dictionary = teams[p.team]
	for t in tanks:
		if t.alive and t.team == p.team and p.pos.distance_to(t.pos) < _radius(t) + 0.9 and (t.driver == null or t.gunner == null):
			if _flag_of(p) >= 0:
				p.hint = Defs.H_FLAG_NOVEH
				continue
			p.hint = Defs.H_ENTER
			if pressed:
				_enter_tank(p, t, 0)
				return
			if p.seat_edge:
				_enter_tank(p, t, 1)
				return
	if p.carried > 0:
		var s: Vector3 = map.team_spawns[p.team]
		var at_tank := false
		for tk in tanks:
			if tk.team == p.team and tk.alive and p.pos.distance_to(tk.pos) < 2.4:
				at_tank = true
		if at_tank or p.pos.distance_to(Vector2(s.x, s.y)) < 5.0:
			_deposit(p)
	if _mortar_interact(p, pressed):
		return
	# the resupply crate at your own base camp (every mode)
	if int(p.team) < map.camp_ammo.size() and p.pos.distance_to(map.camp_ammo[p.team]) < 1.4:
		p.hint = Defs.H_AMMO
		if pressed and p.ammo_cd <= 0.0:
			_refill(p)
			p.ammo_cd = 20.0
			_ev(Defs.EV_PICKUP, map.camp_ammo[p.team], Vector2(2, 0))
	var b := _near_bunker(p.pos)
	if b < 0:
		return
	var bk: Dictionary = map.bunkers[b]
	var st: Dictionary = bstate[b]
	var acc: Array = st.acc
	var sol: Array = st.sol
	var mine: bool = int(st.owner) == p.team
	var heist: bool = mode == Defs.MODE_HEIST   # bunker rooms and vaults only matter in a heist
	for r in (R + 1 if heist else 0):
		var dc: Vector2i = bk.doors[r]
		if p.pos.distance_to(Vector2(dc.x + 0.5, dc.y + 0.5)) < 1.5 and not acc[r] and not mine:
			if r == V:
				p.hint = Defs.H_VAULT
			else:
				var kid := _team_key(p, b)
				if kid != -99999:
					p.hint = Defs.H_UNLOCK
					if pressed:
						var kh: int = int(keys[kid].holder)
						_consume_key(kid)
						if kh != p.id and players.has(kh):
							_msg("%s used %s's key" % [p.name, players[kh].name])
						_grant(b, r)
						_ev(Defs.EV_UNLOCK, Vector2(dc.x + 0.5, dc.y + 0.5))
						var whose: String = "neutral" if int(st.owner) < 0 else Defs.TEAM_NAMES[int(st.owner)]
						_msg("%s TEAM used a key on the %s bunker (%s) - %s room open" % [Defs.TEAM_NAMES[p.team], map.bunker_names[b], whose, _room_name(b, r)])
						return
				else:
					p.hint = Defs.H_KEYDOOR
	for r in (R if heist else 0):
		if p.pos.distance_to(bk.terminals[r]) < 1.3 and acc[r] and not mine:
			if sol[r]:
				p.hint = Defs.H_SOLVED
			else:
				p.hint = Defs.H_TERMINAL
				if pressed:
					p.puzzle = r
					p.pz_bunker = b
					p.pz_prev = 0
					return
	if p.pos.distance_to(bk.ammo) < 1.4:
		p.hint = Defs.H_AMMO
		if pressed and p.ammo_cd <= 0.0:
			_refill(p)
			p.ammo_cd = 20.0
			_ev(Defs.EV_PICKUP, bk.ammo, Vector2(2, 0))


func _deposit(p) -> void:
	var pts: int = p.carried * (2 if evt_active(Defs.EVT_GOLD) else 1)
	teams[p.team].score += pts
	_ev(Defs.EV_DEPOSIT, p.pos, Vector2(pts, p.team))
	_msg("%s banked %d points for %s%s" % [p.name, pts, Defs.TEAM_NAMES[p.team], " (GOLD RUSH x2!)" if pts > p.carried else ""])
	p.carried = 0


## Open door r of bunker b (0..R-1 puzzle rooms, R = vault) for everybody.
func _grant(b: int, r: int) -> void:
	bstate[b].acc[r] = true
	var c: Vector2i = map.bunkers[b].doors[r]
	map.set_wall(c.x, c.y, 0)
	astar.set_point_solid(c, false)


## Owners held their bunker: re-lock every door, reset the puzzles, hand both keys back.
func _reclaim(b: int) -> void:
	var st: Dictionary = bstate[b]
	var bk: Dictionary = map.bunkers[b]
	for r in R + 1:
		var c: Vector2i = bk.doors[r]
		map.set_wall(c.x, c.y, MapData.DOOR if r == V else MapData.KEYDOOR)
		astar.set_point_solid(c, true)
		for q in players.values():
			if q.alive and q.tank == null and floori(q.pos.x) == c.x and floori(q.pos.y) == c.y:
				q.pos = bk.door_outside[r]
		st.acc[r] = false
	for r in R:
		st.sol[r] = false
	st.pz = _room_puzzles()
	st.hold = 0.0
	for q in players.values():
		if q.puzzle >= 0 and q.pz_bunker == b:
			q.puzzle = -1
	for kid in keys:
		var k: Dictionary = keys[kid]
		if int(k.bunker) == b and k.used:
			k.used = false
			_return_key(kid)
	var who: String = Defs.TEAM_NAMES[int(st.owner)] if int(st.owner) >= 0 else "The garrison"
	_msg("%s held the %s bunker for a minute - it is SEALED again and their keys are back!" % [who, map.bunker_names[b]])
	_ev(Defs.EV_DOOR, bk.center)


# ---------------------------------------------------------------- puzzles

func _room_name(b: int, r: int) -> String:
	if r >= V:
		return "VAULT"
	return str(Defs.PUZZLES[int(bstate[b].pz[r].ty)].name)


func _all_solved(b: int) -> bool:
	for r in R:
		if not bstate[b].sol[r]:
			return false
	return true

## Every bunker draws its rooms as DIFFERENT puzzle types from a fresh shuffle of all types (not the match
## seed: puzzles are host-only), avoiding the exact set the previous bunker got.
var last_pz_set: Array = []
func _room_puzzles() -> Array:
	var pool: Array = range(Defs.PUZZLES.size())
	var pick: Array = []
	for tries in 4:
		pool.shuffle()
		pick = pool.slice(0, mini(R, pool.size()))
		var sorted_pick := pick.duplicate()
		sorted_pick.sort()
		if sorted_pick != last_pz_set:
			last_pz_set = sorted_pick
			break
	var out: Array = []
	for k in R:
		out.append(_new_puzzle(int(pick[k % pick.size()]), 0))
	return out


func _new_code(stage: int) -> Dictionary:
	return _new_puzzle(Defs.PZ_CODE, stage)


func _new_tune() -> Dictionary:
	return _new_puzzle(Defs.PZ_TUNER, 0)


func _new_puzzle(ty: int, stage: int) -> Dictionary:
	var pz := {"ty": ty, "stage": stage, "stages": int(Defs.PUZZLES[ty].stages), "err": 0.0}
	match ty:
		Defs.PZ_CODE:
			var seq: Array = []
			for i in [4, 5][mini(stage, 1)]:
				seq.append(randi() % 4)
			pz.seq = seq
			pz.pos = 0
		Defs.PZ_TUNER:
			pz.v = 0.5
			pz.t = 0.5
			pz.hold = 0.0
			pz.need = 2.5
			pz.tol = [0.12, 0.1][mini(stage, 1)]
			pz.phase = randf() * TAU
		Defs.PZ_DIAL:
			var combo: Array = []
			for i in [2, 3][mini(stage, 1)]:
				combo.append(randi() % 40)
			pz.combo = combo
			pz.idx = 0
			pz.v = 0.0
			pz.lastdir = 0
		Defs.PZ_TIMING:
			pz.m = 0.0          # sweeping marker 0..1
			pz.d = 1.0
			pz.zc = randf_range(0.2, 0.8)
			pz.zw = [0.11, 0.095, 0.08][mini(stage, 2)]
			pz.spd = [0.6, 0.75, 0.9][mini(stage, 2)]
			pz.hits = 0
			pz.need = 3
			pz.miss = 0.0
		Defs.PZ_VALVES:
			pz.g = [randf_range(0.2, 0.35), randf_range(0.65, 0.8), randf_range(0.3, 0.7)]
			pz.vel = [0.0, 0.0, 0.0]
			pz.sel = 0
			pz.hold = 0.0
			pz.need = 3.0
			pz.band = [0.13, 0.11][mini(stage, 1)]
		Defs.PZ_STEADY:
			pz.cx = 0.0
			pz.cy = 0.0
			pz.vx = 0.0
			pz.vy = 0.0
			pz.tx = 0.0
			pz.ty2 = 0.0
			pz.tr = [0.3, 0.24][mini(stage, 1)]
			pz.ph = randf() * TAU
			pz.hold = 0.0
			pz.need = 3.0
		Defs.PZ_PUMP:
			pz.g = 0.15
			pz.last = 0
			pz.hold = 0.0
			pz.need = 1.6
			pz.lo = 0.75
			pz.leak = [0.22, 0.3][mini(stage, 1)]
	return pz


## Advance one stage of a puzzle; returns true when the whole puzzle is solved.
func _pz_stage_done(p, b: int, r: int, pz: Dictionary) -> void:
	_ev(Defs.EV_PZ_OK, p.pos)
	var st: int = int(pz.stage) + 1
	if st >= int(pz.stages):
		_solve(p, b, r)
	else:
		bstate[b].pz[r] = _new_puzzle(int(pz.ty), st)


func _pz_fail(p, b: int, r: int, pz: Dictionary) -> void:
	_ev(Defs.EV_PZ_BAD, p.pos)
	var np := _new_puzzle(int(pz.ty), int(pz.stage))
	np.err = 0.6
	bstate[b].pz[r] = np


func _update_puzzle(p, inp: Array, use_pressed: bool, fire_edge: bool, dt: float) -> void:
	var r: int = p.puzzle
	var b: int = p.pz_bunker
	var bst: Dictionary = bstate[b]
	if use_pressed or bst.sol[r]:
		p.puzzle = -1
		return
	var mx := float(inp[I_MX])
	var my := float(inp[I_MY])
	var dir := -1
	if my > 0.5:
		dir = 0
	elif mx > 0.5:
		dir = 1
	elif my < -0.5:
		dir = 2
	elif mx < -0.5:
		dir = 3
	var pressed: bool = dir >= 0 and dir != p.pz_prev
	p.pz_prev = dir
	var pz: Dictionary = bst.pz[r]
	pz.err = maxf(0.0, float(pz.err) - dt)
	var stages := float(pz.stages)
	var part := 0.0
	match int(pz.ty):
		Defs.PZ_CODE:
			if pressed:
				if dir == int(pz.seq[pz.pos]):
					pz.pos += 1
					_ev(Defs.EV_BEEP, p.pos)
					if pz.pos >= pz.seq.size():
						_pz_stage_done(p, b, r, pz)
						return
				else:
					_pz_fail(p, b, r, pz)
					return
			part = float(pz.pos) / float(pz.seq.size())
		Defs.PZ_TUNER:
			var stg: int = pz.stage
			pz.t = 0.5 + 0.3 * sin(elapsed * (0.3 + 0.1 * stg) + pz.phase) * (0.7 + 0.3 * sin(elapsed * (0.6 + 0.15 * stg)))
			pz.v = clampf(pz.v + mx * dt * 0.7, 0.0, 1.0)
			if absf(pz.v - pz.t) < float(pz.tol):
				pz.hold += dt
				if pz.hold >= float(pz.need):
					_pz_stage_done(p, b, r, pz)
					return
			else:
				pz.hold = maxf(0.0, pz.hold - dt * 0.5)
			part = pz.hold / float(pz.need)
		Defs.PZ_DIAL:
			if absf(mx) > 0.15:
				pz.v = fposmod(pz.v + mx * dt * 12.0, 40.0)
				pz.lastdir = 1 if mx > 0.0 else -1
			if fire_edge:
				var n: int = pz.combo[pz.idx]
				var need := 1 if int(pz.idx) % 2 == 0 else -1
				var off := absf(fposmod(pz.v - n + 20.0, 40.0) - 20.0)
				if off < 1.2 and int(pz.lastdir) == need:
					pz.idx += 1
					_ev(Defs.EV_BEEP, p.pos)
					if pz.idx >= pz.combo.size():
						_pz_stage_done(p, b, r, pz)
						return
				else:
					_pz_fail(p, b, r, pz)
					return
			part = float(pz.idx) / float(pz.combo.size())
		Defs.PZ_TIMING:
			pz.miss = maxf(0.0, float(pz.miss) - dt)
			var m: float = float(pz.m) + float(pz.d) * float(pz.spd) * dt
			if m > 1.0 or m < 0.0:
				pz.d = -float(pz.d)
				m = clampf(m, 0.0, 1.0)
			pz.m = m
			if fire_edge:
				if absf(m - float(pz.zc)) <= float(pz.zw):
					pz.hits = int(pz.hits) + 1
					_ev(Defs.EV_BEEP, p.pos)
					if int(pz.hits) >= int(pz.need):
						_pz_stage_done(p, b, r, pz)
						return
					# the zone jumps somewhere else, away from the marker
					var nz: float = randf_range(0.15, 0.85)
					if absf(nz - m) < 0.25:
						nz = fposmod(nz + 0.5, 0.7) + 0.15
					pz.zc = nz
				else:
					pz.hits = maxi(0, int(pz.hits) - 1)   # a miss costs one hit, not the stage
					pz.miss = 0.4
					_ev(Defs.EV_PZ_BAD, p.pos)
			part = float(pz.hits) / float(pz.need)
		Defs.PZ_VALVES:
			var stg: int = pz.stage
			var band: float = pz.band
			if pressed and (dir == 1 or dir == 3):
				pz.sel = (int(pz.sel) + (1 if dir == 1 else 2)) % 3
			var all_in := true
			for i in 3:
				var v: float = float(pz.vel[i]) * (1.0 - dt * 0.8) + randfn(0.0, 1.0) * dt * (0.25 + 0.15 * stg)
				v = clampf(v, -0.06 - 0.03 * stg, 0.06 + 0.03 * stg)
				var g: float = pz.g[i] + v * dt
				if i == int(pz.sel):
					g += my * dt * 0.55
				if g < 0.0 or g > 1.0:
					v = -v
				pz.vel[i] = v
				pz.g[i] = clampf(g, 0.0, 1.0)
				if absf(float(pz.g[i]) - 0.5) > band:
					all_in = false
			if all_in:
				pz.hold += dt
				if pz.hold >= float(pz.need):
					_pz_stage_done(p, b, r, pz)
					return
			else:
				pz.hold = maxf(0.0, pz.hold - dt * 0.5)
			part = pz.hold / float(pz.need)
		Defs.PZ_STEADY:
			var stg: int = pz.stage
			# the ring wanders slowly, the cursor is shoved around by a random drift
			var tt: float = elapsed + float(pz.ph)
			pz.tx = 0.5 * sin(tt * (0.33 + 0.08 * stg)) * cos(tt * 0.21)
			pz.ty2 = 0.45 * sin(tt * (0.47 + 0.1 * stg) + 1.3)
			var jit: float = 1.5 + 0.6 * stg
			var vx: float = float(pz.vx) * (1.0 - dt * 1.2) + randfn(0.0, 1.0) * dt * jit
			var vy: float = float(pz.vy) * (1.0 - dt * 1.2) + randfn(0.0, 1.0) * dt * jit
			vx = clampf(vx, -0.6, 0.6)
			vy = clampf(vy, -0.6, 0.6)
			pz.vx = vx
			pz.vy = vy
			pz.cx = clampf(float(pz.cx) + (vx + mx * 0.9) * dt, -1.0, 1.0)
			pz.cy = clampf(float(pz.cy) + (vy + my * 0.9) * dt, -1.0, 1.0)
			var dd := Vector2(float(pz.cx) - float(pz.tx), float(pz.cy) - float(pz.ty2)).length()
			if dd <= float(pz.tr):
				pz.hold += dt
				if pz.hold >= float(pz.need):
					_pz_stage_done(p, b, r, pz)
					return
			else:
				pz.hold = maxf(0.0, pz.hold - dt * 0.6)
			part = pz.hold / float(pz.need)
		Defs.PZ_PUMP:
			if pressed and (dir == 1 or dir == 3):
				var side := 1 if dir == 1 else -1
				if side != int(pz.last):
					pz.g = minf(1.0, float(pz.g) + 0.065)
					pz.last = side
			pz.g = maxf(0.0, float(pz.g) - float(pz.leak) * dt)
			if float(pz.g) >= float(pz.lo):
				pz.hold += dt
				if pz.hold >= float(pz.need):
					_pz_stage_done(p, b, r, pz)
					return
			else:
				pz.hold = maxf(0.0, pz.hold - dt * 0.8)
			part = pz.hold / float(pz.need)
	var cur: Dictionary = bst.pz[r]
	p.progress = (float(cur.stage) + part) / stages


func _solve(p, b: int, r: int) -> void:
	var ts: Dictionary = teams[p.team]
	var bst: Dictionary = bstate[b]
	bst.sol[r] = true
	p.puzzle = -1
	_msg("%s TEAM solved the %s %s!" % [Defs.TEAM_NAMES[p.team], map.bunker_names[b], _room_name(b, r)])
	if _all_solved(b):
		_grant(b, V)
		var dc: Vector2i = map.bunkers[b].doors[V]
		_ev(Defs.EV_DOOR, Vector2(dc.x + 0.5, dc.y + 0.5))
		if vault_first[b] < 0:
			vault_first[b] = p.team
			ts.score += 100
			_msg("%s VAULT open for %s TEAM (+100 first-in bonus). Its garrison rushes in!" % [map.bunker_names[b], Defs.TEAM_NAMES[p.team]])
			for g in map.bunkers[b].guards:
				_spawn_enemy(Defs.E_SOLDIER, g, true)
		else:
			_msg("%s VAULT open for %s TEAM" % [map.bunker_names[b], Defs.TEAM_NAMES[p.team]])


# ---------------------------------------------------------------- tanks

func _reset_tank(t) -> void:
	t.alive = true
	t.hp = float(_vs(t).hp)
	t.pos = Vector2(t.spawn.x, t.spawn.y)
	t.hull = t.spawn.z
	t.turret = t.spawn.z
	t.cannon_cd = 0.0
	t.mg_cd = 0.0
	t.drive = 0.0
	t.steer = 0.0
	t.z = 0.0
	t.speed = 0.0
	t.ppitch = 0.0
	t.pcmd = 0.0
	t.bank = 0.0
	t.bombs = int(_vs(t).get("bombs", 0))


## want: 0 = driver seat first, 1 = gunner seat first (the other one if that is taken).
func _enter_tank(p, t, want := 0) -> bool:
	if _flag_of(p) >= 0:
		return false   # flag carriers stay on foot
	if _is_plane(t) and t.z > 0.3:
		return false   # can't board a flying plane
	if want == 1 and t.gunner == null:
		t.gunner = p
		p.seat = 1
	elif t.driver == null:
		t.driver = p
		p.seat = 0
	elif t.gunner == null:
		t.gunner = p
		p.seat = 1
	else:
		return false
	p.tank = t
	p.pos = t.pos
	p.progress = 0.0
	p.puzzle = -1
	p.hp = maxf(p.hp, 100.0)
	p.reload = 0.0
	p.moving = false
	p.crouch = false
	p.sprint = false
	p.z = 0.0
	if p.carried > 0 and teams.has(p.team):
		_deposit(p)
	_resync_tank(t)
	return true


func _resync_tank(t) -> void:
	for o in [t.driver, t.gunner]:
		if o != null:
			o.yaw = t.turret
			o.epoch += 1


func _exit_tank(p) -> void:
	var t = p.tank
	if t == null:
		return
	if t.driver == p:
		t.driver = null
	if t.gunner == p:
		t.gunner = null
	p.tank = null
	p.seat = -1
	if _is_plane(t) and t.z > 1.0 and p.alive:
		# no parachutes
		p.pos = t.pos
		_msg("%s jumped out of a flying plane" % p.name)
		_kill_player(p, null)
		_resync_tank(t)
		return
	var fwd := Vector2.from_angle(t.hull)
	var side := Vector2(-fwd.y, fwd.x)
	var base: Vector2 = t.pos
	p.pos = base
	for s in [base - fwd * 1.0, base + side * 1.0, base - side * 1.0, base + fwd * 1.0, base - fwd * 1.4, base + side * 1.4, base - side * 1.4]:
		if not map.circle_blocked(s, PLAYER_R):
			p.pos = s
			break
	p.yaw = t.turret
	p.epoch += 1
	_resync_tank(t)


func _switch_seat(p) -> void:
	var t = p.tank
	if p.seat == 0 and t.gunner == null:
		t.driver = null
		t.gunner = p
		p.seat = 1
	elif p.seat == 1 and t.driver == null:
		t.gunner = null
		t.driver = p
		p.seat = 0
	_resync_tank(t)


func _player_in_tank(p, inp: Array, use_pressed: bool, seat_pressed: bool, epoch_ok: bool) -> void:
	var t = p.tank
	p.moving = false
	_regen_stamina(p, 1.0 / 60.0)
	if over:
		return
	p.hint = 0
	if use_pressed:
		_exit_tank(p)
		return
	# no seat swapping inside: get out and climb back in ([use] = drive, [seat] = gun)
	var role := _role(p)
	if _is_plane(t):
		_player_in_plane(p, t, role, inp, epoch_ok)
		return
	p.pitch = clampf(float(inp[I_PITCH]), -0.45, 0.6)
	if role == Defs.ROLE_SOLO or role == Defs.ROLE_GUNNER:
		t.gun_pitch = p.pitch
	if role == Defs.ROLE_SOLO or role == Defs.ROLE_DRIVER:
		t.drive = clampf(float(inp[I_MY]), -1.0, 1.0)
		t.steer = clampf(float(inp[I_MX]), -1.0, 1.0)
	if role == Defs.ROLE_SOLO or role == Defs.ROLE_GUNNER:
		if epoch_ok:
			t.turret = float(inp[I_YAW])
			var lim: Vector2 = TRAVERSE[t.vtype]
			if lim.x > -PI:
				t.turret = t.hull + clampf(angle_difference(t.hull, t.turret), lim.x, lim.y)
			p.yaw = t.turret
		var vs := _vs(t)
		if bool(inp[I_FIRE]):
			if str(vs.main) != "none":
				_tank_cannon(t, p)
			else:
				_tank_mg(t, p, t.turret)
		if bool(inp[I_ALT]) and float(vs.mg_cd) > 0.0:
			_tank_mg(t, p, t.turret)
	else:
		p.yaw = t.hull   # the driver only drives (no hull MG: driver OR shooter, never both)


func _vs(t) -> Dictionary:
	return Defs.VEHICLES[t.vtype]


func _update_tank(t, dt: float) -> void:
	var vs := _vs(t)
	if not t.alive:
		t.respawn -= dt
		if t.respawn <= 0.0:
			_reset_tank(t)
			_msg("%s %s redeployed at base camp" % [Defs.TEAM_NAMES[t.team], vs.name])
		return
	t.cannon_cd -= dt
	t.mg_cd -= dt
	t.fire_t -= dt
	if t.driver == null or over:
		# nobody at the wheel: no leftover throttle/steering from whoever just left the seat
		t.drive = 0.0
		t.steer = 0.0
		t.pcmd = 0.0
	if _is_plane(t):
		_update_plane(t, dt)
		return
	var r: float = vs.r
	# no turning on the spot: steering needs throttle, and reversing steers like a car
	var roll: float = clampf(absf(t.drive) * 1.6, 0.0, 1.0) * (1.0 if t.drive >= 0.0 else -1.0)
	t.hull = wrapf(t.hull + t.steer * float(vs.turn) * roll * dt, -PI, PI)
	var spd: float = float(vs.speed) if t.drive > 0.0 else float(vs.rev)
	var delta: Vector2 = Vector2.from_angle(t.hull) * t.drive * spd * dt
	var np: Vector2 = map.move_circle(t.pos, delta, r)
	for o in tanks:
		if o != t and o.z < 1.0 and np.distance_to(o.pos) < r + _radius(o) and np.distance_to(o.pos) < t.pos.distance_to(o.pos):
			np = t.pos
	t.moving = np.distance_squared_to(t.pos) > 0.000001
	t.pos = np
	if t.moving and absf(t.drive) > 0.5:
		var crusher = t.driver if t.driver != null else t.gunner
		for e in enemies:
			if not e.dead and e.kind == Defs.E_SOLDIER and _guard_owner(e) != t.team and e.pos.distance_to(t.pos) < r + 0.2:
				_kill_enemy(e, crusher)
				_ev(Defs.EV_HIT, e.pos)
	for o in [t.driver, t.gunner]:
		if o != null:
			o.pos = t.pos


# ---------------------------------------------------------------- planes (WAR)

const PLANE_CEIL := 14.0
const BOMB_GRAV := 6.0


func _is_plane(t) -> bool:
	return t.vtype >= Defs.PLANE_FIRST


## Planes line up beside the camp, noses towards the map centre, on the most open ground nearby.
func _park_planes(ti: int, n: int, first_slot: int) -> void:
	var s: Vector3 = map.team_spawns[ti]
	var base := Vector2(s.x, s.y)
	var to_c := (Vector2(map.W * 0.5, map.H * 0.5) - base).normalized()
	var side := Vector2(-to_c.y, to_c.x)
	for k in n:
		var tk := Tank.new()
		tk.id = 5000 + ti + k * 100
		tk.team = ti
		tk.slot = first_slot + k
		tk.vtype = Defs.PLANE_FIRST + k % 3
		var want: Vector2 = base + to_c * 9.0 + side * (float(k) - float(n - 1) * 0.5) * 3.2
		var sp := _open_spot(want)
		tk.spawn = Vector3(sp.x, sp.y, to_c.angle())
		_reset_tank(tk)
		tanks.append(tk)


func _player_in_plane(p, t, role: int, inp: Array, epoch_ok: bool) -> void:
	if role == Defs.ROLE_DRIVER:
		# pilot: W/S throttle, A/D turn, mouse up/down = climb/dive. Flies only.
		t.drive = clampf(float(inp[I_MY]), -1.0, 1.0)
		t.steer = clampf(float(inp[I_MX]), -1.0, 1.0)
		t.pcmd = clampf(float(inp[I_PITCH]), -0.7, 0.7)
		p.pitch = t.pcmd
		p.yaw = t.hull
	else:
		# bomber: free look (mostly down), FIRE releases a bomb
		p.pitch = clampf(float(inp[I_PITCH]), -1.3, 0.3)
		if epoch_ok:
			p.yaw = float(inp[I_YAW])
		if bool(inp[I_FIRE]) and t.bombs > 0 and t.bomb_cd <= 0.0 and t.z > 0.5:
			_drop_bomb(t, p)


## AI aircrew. Pilot: wait for the bomber, take off, fly at ~8 towards the points the team doesn't hold and circle
## them. Bomber: release when the predicted impact is near an enemy-held point or enemy troops.
func _bot_plane(p, b, t, role: int, dt: float, o: Dictionary) -> void:
	var vs := _vs(t)
	if role == Defs.ROLE_DRIVER:
		if t.z <= 0.0 and t.gunner == null and b.taxi_stuck < 12.0:
			b.taxi_stuck += dt   # wait a bit for the bomber to climb in
			o.my = 0.0
			o.pitch = 0.0
			return
		var goal := Vector2(map.W * 0.5, map.H * 0.5)
		var bd := 1e9
		for cp in cpoints:
			if int(cp.owner) != p.team:
				var d: float = t.pos.distance_to(cp.pos)
				if d < bd:
					bd = d
					goal = cp.pos
		var desired: float = (goal - t.pos).angle()
		var steer: float = clampf(angle_difference(t.hull, desired) * 2.0, -1.0, 1.0)
		if t.pos.distance_to(goal) < 7.0:
			steer = 0.8   # circle over the target
		o.my = 1.0
		if t.z <= 0.0:
			# take-off run: straight ahead, pull up once fast enough
			o.mx = 0.0
			o.pitch = 0.5 if t.speed >= float(vs.takeoff) else 0.0
			if t.speed < 0.3:
				b.seat_t += dt
				if b.seat_t > 3.0:
					o.mx = 1.0   # stuck against something: turn away
		else:
			b.seat_t = 0.0
			o.mx = steer
			o.pitch = clampf((8.0 - t.z) * 0.15, -0.35, 0.5)
		return
	# bomber
	o.pitch = -1.0
	if t.z < 2.0 or t.bombs <= 0 or t.bomb_cd > 0.0:
		return
	var vh: float = t.speed * cos(t.ppitch)
	var vz0: float = t.speed * sin(t.ppitch)
	var z0: float = t.z - 0.35
	var tt: float = (vz0 + sqrt(maxf(0.0, vz0 * vz0 + 2.0 * BOMB_GRAV * z0))) / BOMB_GRAV
	var hit: Vector2 = t.pos + Vector2.from_angle(t.hull) * vh * tt
	var good := false
	for cp in cpoints:
		if int(cp.owner) != p.team and hit.distance_to(cp.pos) < 3.5:
			good = true
	if not good:
		for q in _hostiles(p.team):
			if q.ttype != 0 and q.pos.distance_to(hit) < 2.5 and _base_z(q) < 1.0:
				good = true
				break
	if good:
		o.fire = true


func _drop_bomb(t, p) -> void:
	var vs := _vs(t)
	t.bombs -= 1
	t.bomb_cd = 0.4
	var d := Vector2.from_angle(t.hull)
	var s := Shell.new()
	s.pos = t.pos - d * 0.2
	s.vel = d * t.speed * cos(t.ppitch)
	s.vz = sin(t.ppitch) * t.speed
	s.grav = BOMB_GRAV
	s.team = t.team
	s.owner = p
	s.dmg = float(vs.bomb_dmg)
	s.splash = float(vs.bomb_splash)
	s.life = 12.0
	s.z = t.z - 0.35
	shells.append(s)
	_ev(Defs.EV_CANNON, t.pos, Vector2(t.vtype, 0))
	p.shots += 1


func _update_plane(t, dt: float) -> void:
	var vs := _vs(t)
	t.bomb_cd -= dt
	var vmax: float = vs.speed
	var vto: float = vs.takeoff
	var acc: float = vs.accel
	t.speed = clampf(t.speed + t.drive * acc * dt - (0.15 * dt if t.drive <= 0.0 else 0.0), 0.0, vmax)
	var r: float = vs.r
	if t.z <= 0.0:
		# rolling on the ground: taxi, take off when fast enough and the pilot pulls up
		t.z = 0.0
		t.bank = move_toward(t.bank, 0.0, dt * 2.0)
		t.hull = wrapf(t.hull + t.steer * 1.2 * clampf(t.speed / vto, 0.15, 1.0) * dt, -PI, PI)
		var d: Vector2 = Vector2.from_angle(t.hull) * t.speed * dt
		var np: Vector2 = map.move_circle(t.pos, d, r * 0.5)
		if d.length() > 0.0001 and np.distance_squared_to(t.pos) < d.length_squared() * 0.25:
			if t.speed > vto * 0.6:
				_crash(t)
				return
			t.speed = 0.0
		t.pos = np
		t.ppitch = move_toward(t.ppitch, 0.0, dt)
		if t.speed >= vto and t.pcmd > 0.08:
			t.z = 0.05
			t.ppitch = 0.15
	else:
		# flying
		var stall: bool = t.speed < vto * 0.8
		var want_p: float = -0.5 if stall else t.pcmd * 0.9
		t.ppitch = move_toward(t.ppitch, want_p, dt * (0.6 if stall else 1.1))
		t.bank = lerpf(t.bank, t.steer * 0.65, minf(1.0, dt * 3.0))
		t.hull = wrapf(t.hull + t.steer * float(vs.turn) * dt, -PI, PI)
		# diving speeds you up, climbing slows you down
		t.speed = clampf(t.speed - sin(t.ppitch) * 2.0 * dt, 0.0, vmax * 1.25)
		t.z += sin(t.ppitch) * t.speed * dt
		if t.z > PLANE_CEIL:
			t.z = PLANE_CEIL
			t.ppitch = minf(t.ppitch, 0.0)
		var np2: Vector2 = t.pos + Vector2.from_angle(t.hull) * cos(t.ppitch) * t.speed * dt
		# keep inside the map: the plane banks back towards the centre near the edges
		var m := 6.0
		if np2.x < m or np2.y < m or np2.x > map.W - m or np2.y > map.H - m:
			var to_c := (Vector2(map.W * 0.5, map.H * 0.5) - np2).angle()
			t.hull = rotate_toward(t.hull, to_c, float(vs.turn) * 1.6 * dt)
			np2 = Vector2(clampf(np2.x, 2.0, map.W - 2.0), clampf(np2.y, 2.0, map.H - 2.0))
		t.pos = np2
		if t.z > 0.05 and map.circle_blocked(t.pos, 0.35, {}, t.z):
			_crash(t)   # flew into a building / hill
			return
		if t.z <= 0.0:
			# touchdown: slow and level enough = landing, otherwise a crash
			if t.speed < vto * 1.35 and t.ppitch > -0.3:
				t.z = 0.0
				t.ppitch = 0.0
			else:
				_crash(t)
				return
	t.moving = t.speed > 0.1
	t.gun_pitch = t.ppitch
	for o in [t.driver, t.gunner]:
		if o != null:
			o.pos = t.pos
			o.z = t.z


func _crash(t) -> void:
	var crew: Array = [t.driver, t.gunner]
	_explode(t.pos, -1, null, 2.4, 120.0, 120.0, 0.3)
	_destroy_tank(t, null)
	for o in crew:
		if o != null and o.alive:
			_kill_player(o, null)
	_msg("%s %s CRASHED" % [Defs.TEAM_NAMES[t.team], _vs(t).name])


func _tank_cannon(t, p) -> void:
	var vs := _vs(t)
	if t.cannon_cd > 0.0:
		return
	t.cannon_cd = float(vs.main_cd)
	t.fire_t = 0.15
	var spread := 0.025 if str(vs.main) == "autocannon" else (0.04 if str(vs.main) == "rockets" else 0.0)
	var d := Vector2.from_angle(t.turret + rng.randf_range(-spread, spread))
	var s := Shell.new()
	s.pos = t.pos + d * (float(vs.r) + 0.1)
	s.vel = d * float(vs.shell_speed)
	s.team = t.team
	s.owner = p
	s.dmg = float(vs.main_dmg)
	s.splash = float(vs.splash)
	s.life = 40.0 / float(vs.shell_speed)
	s.z = 0.7
	s.slope = tan(clampf(t.gun_pitch, -0.35, 0.5))
	shells.append(s)
	_ev(Defs.EV_CANNON, t.pos, Vector2(t.vtype, 0))
	p.shots += 1


func _tank_mg(t, p, ang: float) -> void:
	var vs := _vs(t)
	if t.mg_cd > 0.0 or float(vs.mg_cd) <= 0.0:
		return
	t.mg_cd = float(vs.mg_cd)
	t.fire_t = 0.06
	# the driver's hull MG fires level, the gunner's MG follows the gun elevation
	var sl := rng.randf_range(-0.015, 0.015) + (tan(t.gun_pitch) if p != t.driver or t.gunner == null else 0.0)
	_spawn_bullet(t.pos + Vector2.from_angle(ang) * (float(vs.r) + 0.05), ang + rng.randf_range(-0.03, 0.03), 80.0, 30.0, float(vs.mg_dmg), t.team, p, 0.78, sl)
	_ev(Defs.EV_MG, t.pos)
	p.shots += 1


func _destroy_tank(t, killer) -> void:
	t.alive = false
	t.respawn = WAR_RESPAWN if mode == Defs.MODE_WAR else TANK_RESPAWN
	_ev(Defs.EV_EXPLOSION, t.pos)
	_msg("%s %s DESTROYED" % [Defs.TEAM_NAMES[t.team], _vs(t).name])
	if mode == Defs.MODE_TDM and killer != null and killer.ttype == 1 and killer.team != t.team and teams.has(killer.team) and (t.driver != null or t.gunner != null):
		teams[killer.team].score += 2   # a crewed vehicle kill counts double
	for o in [t.driver, t.gunner]:
		if o != null:
			_exit_tank(o)
			_damage(o, 35.0, killer, true)
	if _is_plane(t):
		t.z = 0.0   # the wreck falls to the ground
		t.speed = 0.0


func _update_shells(dt: float) -> void:
	var keep: Array = []
	for s in shells:
		var exploded := false
		for i in 4:
			if s.grav > 0.0:
				s.vz -= s.grav * dt / 4.0
				s.slope = s.vz / maxf(0.01, s.vel.length())
			var stp: Vector2 = s.vel * (dt / 4.0)
			var L := stp.length()
			var wr: Dictionary = map.ray3(s.pos, s.z, stp / maxf(L, 1e-6), s.slope, L)
			if wr.hit:
				var hp: Vector2 = s.pos + stp / maxf(L, 1e-6) * maxf(0.0, float(wr.dist) - 0.05)
				_explode(hp, s.team, s.owner, s.splash, s.dmg, s.dmg, float(wr.z))
				exploded = true
				break
			s.pos += stp
			s.z += s.slope * L
			for t in _hostiles(s.team):
				if t.pos.distance_to(s.pos) < _radius(t) + 0.15 and s.z > _base_z(t) - 0.1 and s.z < _base_z(t) + _tall(t) + 0.1:
					exploded = true
					break
			if exploded:
				_explode(s.pos, s.team, s.owner, s.splash, s.dmg, s.dmg, s.z)
				break
		s.life -= dt
		if not exploded and s.life <= 0.0:
			_explode(s.pos, s.team, s.owner, s.splash, s.dmg, s.dmg, s.z)
			exploded = true
		if not exploded:
			keep.append(s)
	shells = keep


func _update_grenades(dt: float) -> void:
	var keep: Array = []
	for g in grenades:
		var pass_cells := _pass(g.team)
		for i in 3:
			var h := dt / 3.0
			var np: Vector2 = g.pos + g.vel * h
			if map.sphere_blocked(np, 0.08, g.z, pass_cells):
				if map.sphere_blocked(Vector2(np.x, g.pos.y), 0.08, g.z, pass_cells):
					g.vel.x = -g.vel.x * 0.5
				if map.sphere_blocked(Vector2(g.pos.x, np.y), 0.08, g.z, pass_cells):
					g.vel.y = -g.vel.y * 0.5
				if g.vel.length() > 1.0:
					_ev(Defs.EV_BOUNCE, g.pos)
			else:
				g.pos = np
			g.z += g.vz * h
			g.vz -= GRAVITY * h
			var gnd: float = map.ground_at(g.pos, 0.1, g.z, pass_cells)
			if map.has_roof(floori(g.pos.x), floori(g.pos.y)) and g.z > MapData.CEIL - 0.08 and g.z < MapData.CEIL + 0.2 and g.vz > 0.0:
				g.z = MapData.CEIL - 0.08
				g.vz = -g.vz * 0.3
			if g.z <= gnd:
				g.z = gnd
				if absf(g.vz) > 1.0:
					_ev(Defs.EV_BOUNCE, g.pos)
				g.vz = -g.vz * 0.35
				g.vel *= 0.55
		g.fuse -= dt
		if g.fuse <= 0.0:
			if g.smoke:
				smokes.append({"id": _nid(), "pos": g.pos, "r": 2.8, "life": 12.0})
				_ev(Defs.EV_SMOKE, g.pos)
			else:
				_explode(g.pos, g.team, g.owner, 2.6, 135.0, 60.0, g.z + 0.1)
		else:
			keep.append(g)
	grenades = keep
	for s in smokes:
		s.life -= dt
	smokes = smokes.filter(func(s): return s.life > 0.0)


func _explode(pos: Vector2, team: int, owner, R: float, dmg: float, gate_dmg: float, ez := 0.3) -> void:
	_ev(Defs.EV_EXPLOSION, pos, Vector2(ez, 0.0))
	for t in _hostiles(team):
		var dz: float = clampf(ez, _base_z(t), _base_z(t) + _tall(t)) - ez
		var d: float = sqrt(t.pos.distance_squared_to(pos) + dz * dz)
		if d < R + _radius(t) and map.los3(pos, ez + 0.05, t.pos, _chest_z(t), _pass(team)):
			_damage(t, dmg * (1.0 - clampf(d / (R + 0.5), 0.0, 1.0) * 0.6), owner, true)
	for g in gates:
		if g.open:
			continue
		for c in g.cells:
			if Vector2(c.x + 0.5, c.y + 0.5).distance_to(pos) < 1.6:
				g.hp -= gate_dmg
				_gate_check(g)
				break


func _damage_cell(cell: Vector2i, dmg: float) -> void:
	for g in gates:
		if not g.open and g.cells.has(cell):
			g.hp -= dmg
			_gate_check(g)
			return


func _gate_check(g: Dictionary) -> void:
	if g.open or g.hp > 0.0:
		return
	g.open = true
	for c in g.cells:
		map.set_wall(c.x, c.y, 0)
		_set_solid_all(c, false)
	for c in g.cells:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var q := Vector2i(c.x + dx, c.y + dy)
				if tank_astar.is_in_boundsv(q):
					tank_astar.set_point_solid(q, not map.tank_cell_ok(q.x, q.y))
	_ev(Defs.EV_GATE, g.center)
	_ev(Defs.EV_EXPLOSION, g.center)
	_msg("A gate of the %s bunker has been breached!" % map.bunker_names[int(g.bunker)])
	alerts[int(g.bunker)] = true


# ---------------------------------------------------------------- base mortars
# Each base camp has a mortar pit (map.mortars[team]). One member of that team at a time can man it:
# the client shows a top-down view, the aim point arrives in the input (I_AIMX/I_AIMY) and shells
# fly a ballistic arc (simulated as a timed flight) and land with range-dependent scatter.

const MORTAR_MIN := 8.0
const MORTAR_RELOAD := 4.0
const MORTAR_SPLASH := 2.6
const MORTAR_DMG := 110.0
const MORTAR_GATE_DMG := 90.0
const MORTAR_USE := 1.6       # how close to the tube you must stand to man it
const MORTAR_KNOCK := 30.0    # taking this much damage in quick succession knocks the crew off it
const MORTAR_WHISTLE := 1.25  # the incoming whistle starts this long before impact
const MORTAR_BOT_ERR := [3.2, 2.2, 1.3]
const MORTAR_SPECIAL_CD := 30.0   # rapid-fire barrage special
const MORTAR_BURST := 6
const MORTAR_BURST_GAP := 0.35

var mortars := {}         # team -> {"pos", "user" (pid or -1), "cd", "hp", bot bookkeeping}
var mshells: Array = []   # {"team", "owner", "from", "aim", "to", "t", "T", "warned"}
var mortar_bot_t := {}    # bot pid -> seconds until it considers crewing the mortar again
var mortar_bots := true   # may bots crew the base mortars at all


func mortar_range() -> float:
	return 0.5 * float(map.W)


## Flight time grows with range: ~2.9 s at minimum range, 4.2 s at maximum.
func mortar_flight(d: float) -> float:
	return 2.8 + 1.4 * clampf(d / mortar_range(), 0.0, 1.0)


## Standard deviation of the landing point (per axis) at distance d.
func mortar_scatter(d: float) -> float:
	return 0.3 + 0.022 * d


func _mortars_ready() -> void:
	if not mortars.is_empty():
		return
	for t in teams:
		var ti := int(t)
		if ti < map.mortars.size():
			mortars[ti] = {"pos": map.mortars[ti], "user": -1, "cd": 0.0, "hp": 100.0, "bot_t": 0.0, "bot_idle": 0.0,
				"bot_walk": 0.0, "bot_scan": 0.0, "bot_tgt": Vector2.INF}


## Where a crew member stands to work the mortar: just inside the pit, on the camp side.
func mortar_stand(team: int) -> Vector2:
	_mortars_ready()
	if not mortars.has(team):
		return Vector2.ZERO
	var mp: Vector2 = mortars[team].pos
	var s: Vector3 = map.team_spawns[team]
	var d := Vector2(s.x, s.y) - mp
	return mp + (d.normalized() if d.length() > 0.1 else Vector2.LEFT)


func _mortar_user(p) -> bool:
	return mortars.has(p.team) and int(mortars[p.team].user) == p.id


func _mortar_clamp(from: Vector2, aim: Vector2) -> Vector2:
	var v := aim - from
	var L := v.length()
	if L < 0.01:
		v = Vector2.RIGHT
		L = 1.0
	var out := from + v / L * clampf(L, MORTAR_MIN, mortar_range())
	return out.clamp(Vector2(1.0, 1.0), Vector2(float(map.W) - 1.0, float(map.H) - 1.0))


func _mortar_man(p) -> bool:
	_mortars_ready()
	if not mortars.has(p.team) or not p.alive or p.tank != null:
		return false
	var m: Dictionary = mortars[p.team]
	if int(m.user) >= 0 and int(m.user) != p.id:
		return false
	m.user = p.id
	m.hp = p.hp
	m.bot_t = 0.0
	m.bot_idle = 0.0
	p.puzzle = -1
	p.reload = 0.0
	p.progress = 0.0
	p.moving = false
	return true


func _mortar_leave(team: int) -> void:
	if not mortars.has(team):
		return
	var m: Dictionary = mortars[team]
	var uid := int(m.user)
	m.user = -1
	if players.has(uid):
		var p = players[uid]
		p.crouch = false
		p.epoch += 1   # the client re-syncs its view direction


func _player_at_mortar(p, inp: Array, use_pressed: bool, fire: bool, dt: float) -> void:
	p.moving = false
	p.sprint = false
	p.ads = false
	p.crouch = true   # ducked behind the sandbags
	p.hint = 0
	p.progress = 0.0
	_regen_stamina(p, dt)
	if use_pressed or over:
		_mortar_leave(p.team)
		return
	var aim := Vector2(float(inp[I_AIMX]), float(inp[I_AIMY]))
	var m: Dictionary = mortars[p.team]
	m.aim = aim
	# special: rapid-fire barrage (RMB / alt fire), once every MORTAR_SPECIAL_CD seconds
	if bool(inp[I_ALT]) and float(m.get("sp", 0.0)) <= 0.0 and int(m.get("burst", 0)) <= 0:
		m.burst = MORTAR_BURST
		m.burst_t = 0.0
		m.sp = MORTAR_SPECIAL_CD
		_msg("%s [%s] calls a MORTAR BARRAGE!" % [p.name, Defs.TEAM_NAMES[p.team]])
	if fire and int(m.get("burst", 0)) <= 0:
		_mortar_fire(p, aim)


func _mortar_fire(p, aim: Vector2, barrage := false) -> bool:
	if not mortars.has(p.team):
		return false
	var m: Dictionary = mortars[p.team]
	if float(m.cd) > 0.0 and not barrage:
		return false
	var from: Vector2 = m.pos
	var to := _mortar_clamp(from, aim)
	var d := from.distance_to(to)
	var sd := mortar_scatter(d) * (1.8 if barrage else 1.0) + (1.2 if barrage else 0.0)
	var off := Vector2(clampf(rng.randfn(0.0, sd), -2.5 * sd, 2.5 * sd), clampf(rng.randfn(0.0, sd), -2.5 * sd, 2.5 * sd))
	var hit := (to + off).clamp(Vector2(1.0, 1.0), Vector2(float(map.W) - 1.0, float(map.H) - 1.0))
	mshells.append({"team": p.team, "owner": p, "from": from, "aim": to, "to": hit, "t": 0.0, "T": mortar_flight(d), "warned": false})
	if not barrage:
		m.cd = MORTAR_RELOAD
	_ev(Defs.EV_MORTAR, from, Vector2(float(p.team), d))
	return true


func _mortar_impact(team: int, owner, pos: Vector2) -> void:
	var gz: float = map.ground_at(pos, 0.1, 9.0)
	_explode(pos, team, owner, MORTAR_SPLASH, MORTAR_DMG, MORTAR_GATE_DMG, gz + 0.15)


func _update_mortars(dt: float) -> void:
	_mortars_ready()
	for t in mortars:
		var m: Dictionary = mortars[t]
		m.cd = maxf(0.0, float(m.cd) - dt)
		m.sp = maxf(0.0, float(m.get("sp", 0.0)) - dt)
		if int(m.get("burst", 0)) > 0:
			# barrage in progress: one shell every MORTAR_BURST_GAP seconds at the current aim point
			m.burst_t = float(m.burst_t) - dt
			var bu = players.get(int(m.user))
			if bu == null or not _mortar_user(bu):
				m.burst = 0
			elif float(m.burst_t) <= 0.0:
				m.burst_t = MORTAR_BURST_GAP
				m.burst = int(m.burst) - 1
				var baim: Vector2 = m.get("aim", m.pos)
				_mortar_fire(bu, baim, true)
				if int(m.burst) <= 0:
					m.cd = MORTAR_RELOAD
		var uid := int(m.user)
		if uid < 0:
			continue
		var u = players.get(uid)
		if u == null or not u.alive or u.tank != null or over or u.pos.distance_to(m.pos) > MORTAR_USE + 0.8:
			_mortar_leave(int(t))
		elif float(m.hp) - float(u.hp) >= MORTAR_KNOCK:
			_mortar_leave(int(t))
		else:
			# recent damage adds up for ~0.75 s: a burst of hits knocks you off, a graze doesn't
			m.hp = float(u.hp) if float(u.hp) > float(m.hp) else move_toward(float(m.hp), float(u.hp), dt * 40.0)
	var keep: Array = []
	for s in mshells:
		s.t = float(s.t) + dt
		var left: float = float(s.T) - float(s.t)
		if not bool(s.warned) and left <= MORTAR_WHISTLE:
			s.warned = true
			_ev(Defs.EV_MORTAR_IN, s.to, Vector2(float(s.team), left))
		if left <= 0.0:
			_mortar_impact(int(s.team), s.owner, s.to)
		else:
			keep.append(s)
	mshells = keep


func _mortar_interact(p, pressed: bool) -> bool:
	_mortars_ready()
	if not mortars.has(p.team) or absf(float(p.z)) > 0.6:
		return false
	var m: Dictionary = mortars[p.team]
	var mp: Vector2 = m.pos
	if p.pos.distance_to(mp) > MORTAR_USE:
		return false
	if int(m.user) >= 0 and int(m.user) != p.id:
		p.hint = Defs.H_MORTAR_BUSY
		return false
	p.hint = Defs.H_MORTAR
	return pressed and _mortar_man(p)


func _mortar_snap() -> Dictionary:
	_mortars_ready()
	var ms := {}
	for t in mortars:
		var m: Dictionary = mortars[t]
		var mp: Vector2 = m.pos
		ms[t] = {"x": mp.x, "y": mp.y, "u": int(m.user), "cd": float(m.cd), "sp": float(m.get("sp", 0.0)), "burst": int(m.get("burst", 0))}
	var sh: Array = []
	for s in mshells:
		var a: Vector2 = s.aim
		var f: Vector2 = s.from
		var hp: Vector2 = s.to
		sh.append([int(s.team), f.x, f.y, a.x, a.y, float(s.T) - float(s.t), float(s.T), hp.x, hp.y])
	return {"m": ms, "s": sh, "rng": mortar_range(), "min": MORTAR_MIN, "rel": MORTAR_RELOAD, "spl": MORTAR_SPLASH,
		"spmax": MORTAR_SPECIAL_CD}


## Now and then one bot (4-player teams, or teams without humans) crews its base mortar and shells
## enemies its team can see; it leaves after a while, when there is nothing to hit or when threatened.
func _bot_mortar(p, b, dt: float, o: Dictionary) -> bool:
	if not mortars.has(p.team):
		return false
	var m: Dictionary = mortars[p.team]
	var mp: Vector2 = m.pos
	if _mortar_user(p):
		m.bot_t = float(m.bot_t) + dt
		var tgt := _mortar_bot_target(p.team, m, dt)
		m.bot_idle = 0.0 if tgt != Vector2.INF else float(m.bot_idle) + dt
		var threat: bool = b.target != null and b.target.pos.distance_to(p.pos) < 12.0
		if threat or float(m.bot_t) > 40.0 or float(m.bot_idle) > 9.0 or p.hp < 50.0:
			if b.use_cd <= 0.0:
				b.use_c += 1
				b.use_cd = 1.0
				mortar_bot_t[p.id] = rng.randf_range(70.0, 130.0)
			return true
		if tgt != Vector2.INF:
			var err: float = MORTAR_BOT_ERR[difficulty]
			var aim := tgt + Vector2(rng.randfn(0.0, err), rng.randfn(0.0, err))
			o.ax = aim.x
			o.ay = aim.y
			o.fire = float(m.cd) <= 0.0 and b.react_t <= 0.0
		return true
	# not on the mortar: should this bot go and crew it?
	var wait: float = float(mortar_bot_t.get(p.id, rng.randf_range(30.0, 80.0))) - dt
	mortar_bot_t[p.id] = wait
	if wait > 0.0 or not _mortar_bot_eligible(p, b, m):
		return false
	if _mortar_bot_target(p.team, m, dt) == Vector2.INF:
		mortar_bot_t[p.id] = 3.0
		return false
	m.bot_walk = float(m.bot_walk) + dt
	if float(m.bot_walk) > 20.0:
		m.bot_walk = 0.0
		mortar_bot_t[p.id] = 60.0
		return false
	_bot_walk(p, b, mortar_stand(p.team), dt, o)
	if p.pos.distance_to(mp) < MORTAR_USE - 0.1 and b.use_cd <= 0.0:
		b.use_c += 1
		b.use_cd = 1.0
		m.bot_walk = 0.0
	return true


func _mortar_bot_eligible(p, b, m: Dictionary) -> bool:
	if not mortar_bots or p.carried > 0 or _stolen_key(p) != -99999 or b.target != null or p.puzzle >= 0 or int(m.user) >= 0:
		return false
	var mp: Vector2 = m.pos
	if p.pos.distance_to(mp) > 30.0:
		return false
	var n := 0
	var humans := 0
	var top := -1
	for q in players.values():
		if q.team == p.team:
			n += 1
			if q.bot == null:
				humans += 1
			elif int(q.id) > top:
				top = int(q.id)
	return top == int(p.id) and (n >= 4 or humans == 0)


## Best target for the team's mortar: an enemy the team can see, in range and not under a roof,
## preferring groups. Rescanned every 0.6 s; Vector2.INF if there is none.
func _mortar_bot_target(team: int, m: Dictionary, dt: float) -> Vector2:
	m.bot_scan = float(m.bot_scan) - dt
	if float(m.bot_scan) > 0.0:
		var cached: Vector2 = m.bot_tgt
		return cached
	m.bot_scan = 0.6
	var mp: Vector2 = m.pos
	var eyes: Array = []
	for q in players.values():
		if q.team == team and q.alive:
			eyes.append(q.pos)
	var cands: Array = []
	var tb: int = int(team_target.get(team, -1))
	for h in _hostiles(team):
		if h.ttype == 2 and h.driver == null and h.gunner == null:
			continue
		var hp: Vector2 = h.pos
		var d := mp.distance_to(hp)
		if d < MORTAR_MIN + 1.0 or d > mortar_range() - 1.0 or map.has_roof(floori(hp.x), floori(hp.y)):
			continue
		if h.ttype == 0 and int(h.bunker) == tb:
			cands.append(h)   # the garrison of the bunker we're attacking: we know where they are
			continue
		for e in eyes:
			var ep: Vector2 = e
			if ep.distance_to(hp) < 22.0 * _vis_mult() and _see(ep, hp):
				cands.append(h)
				break
	var best := Vector2.INF
	var bs := 0.0
	for h in cands:
		var sc := 1.0 + (0.5 if h.ttype != 0 else 0.0)
		for h2 in cands:
			if h2 != h and h2.pos.distance_to(h.pos) < 3.5:
				sc += 1.0
		if sc > bs:
			bs = sc
			best = h.pos
	m.bot_tgt = best
	return best


func _bot_walk(p, b, goal: Vector2, dt: float, o: Dictionary) -> void:
	var ta: AStarGrid2D = team_astar[p.team]
	var gcell := Vector2i(floori(goal.x), floori(goal.y))
	if b.path_t <= 0.0 or gcell != b.path_goal:
		b.path_t = 1.0
		b.path_goal = gcell
		b.path = []
		var sc := Vector2i(floori(p.pos.x), floori(p.pos.y))
		if ta.is_in_boundsv(sc) and ta.is_in_boundsv(gcell) and not ta.is_point_solid(sc) and not ta.is_point_solid(gcell):
			b.path = ta.get_id_path(sc, gcell)
	var tgt := goal
	while b.path.size() > 0:
		var c: Vector2i = b.path[0]
		var cc := Vector2(c.x + 0.5, c.y + 0.5)
		if p.pos.distance_to(cc) < 0.35 and b.path.size() > 1:
			b.path.pop_front()
			continue
		tgt = cc
		break
	var mv: Vector2 = tgt - p.pos
	mv = mv.normalized() if mv.length() > 0.1 else Vector2.ZERO
	if p.pos.distance_to(goal) < 0.25:
		mv = Vector2.ZERO
	var yaw: float = p.yaw
	if mv != Vector2.ZERO:
		yaw = rotate_toward(yaw, mv.angle(), 8.0 * dt)
	o.yaw = yaw
	var fwd := Vector2.from_angle(yaw)
	o.my = mv.dot(fwd)
	o.mx = mv.dot(Vector2(-fwd.y, fwd.x))


# ---------------------------------------------------------------- base defenders

# ---------------------------------------------------------------- random events

func evt_active(k: int) -> bool:
	return not evt.is_empty() and int(evt.k) == k and float(evt.get("warn", 0.0)) <= 0.0


## Vision range multiplier for AI (storms hide everything).
func _vis_mult() -> float:
	return 0.5 if evt_active(Defs.EVT_STORM) else 1.0


func _update_events(dt: float) -> void:
	if evt.is_empty():
		if elapsed >= evt_next and time_limit - elapsed > 40.0:
			var k := _pick_event()
			if k >= 0:
				start_event(k)
			else:
				evt_next = elapsed + 10.0
		return
	evt.t -= dt
	var k: int = evt.k
	if float(evt.get("warn", 0.0)) > 0.0:
		evt.warn -= dt
		if evt.warn <= 0.0:
			_ev(Defs.EV_EVENT, Vector2(evt.x, evt.y), Vector2(k, 1))
		return
	if k == Defs.EVT_SUPPLY:
		if not evt.landed:
			evt.z = maxf(0.0, float(evt.z) - dt * 0.6)
			if evt.z <= 0.0:
				evt.landed = true
				evt.t = 90.0
				var it := {"id": _nid(), "k": 2, "pos": Vector2(evt.x, evt.y), "value": Defs.SUPPLY_VALUE, "life": 90.0, "vault": -1, "z": 0.0}
				items.append(it)
				evt.item = it.id
				_ev(Defs.EV_EVENT, it.pos, Vector2(k, 3))
				_msg("The supply crate has landed!")
		else:
			var still := false
			for it in items:
				if int(it.id) == int(evt.item):
					still = true
			if not still:
				evt.t = 0.0
	elif k == Defs.EVT_ARTY:
		_update_airstrike(dt)
	if evt.t <= 0.0:
		end_event()


func _pick_event() -> int:
	var opts: Array = []
	for k in Defs.EVENT_NAMES.size():
		if k == evt_last:
			continue
		if k == Defs.EVT_BOUNTY and (teams.size() < 2 or mode == Defs.MODE_CTF):
			continue
		if (k == Defs.EVT_SUPPLY or k == Defs.EVT_GOLD) and mode != Defs.MODE_HEIST:
			continue   # loot events only make sense in a heist
		opts.append(k)
		if k == Defs.EVT_SUPPLY or k == Defs.EVT_ARTY:
			opts.append(k)   # the action events come up a bit more often
	if opts.is_empty():
		return -1
	return int(opts[rng.randi() % opts.size()])


func start_event(k: int) -> void:
	evt = {"k": k, "t": 60.0, "warn": 0.0, "x": 0.0, "y": 0.0, "r": 0.0, "z": 0.0, "team": -1, "landed": false, "item": -1, "cd": 0.0}
	evt_last = k
	evt_count += 1
	evt_log.append([k, elapsed])
	evt_next = elapsed + rng.randf_range(130.0, 165.0)
	var text: String = Defs.EVENT_INFO[k]
	match k:
		Defs.EVT_SUPPLY:
			var c := _drop_spot()
			evt.x = c.x
			evt.y = c.y
			evt.z = 7.0
			evt.t = 120.0
		Defs.EVT_ARTY:
			_plan_airstrike()
		Defs.EVT_STORM:
			evt.t = 60.0
		Defs.EVT_JAM:
			evt.t = 45.0
		Defs.EVT_GOLD:
			evt.t = 60.0
		Defs.EVT_BOUNTY:
			evt.t = 75.0
			var best := -1
			var bs := -1
			for t in teams:
				var sc: int = teams[t].score + rng.randi_range(0, 3)
				if sc > bs:
					bs = sc
					best = int(t)
			evt.team = best
			text = "Bounty on team %s: +%d pts for every kill!" % [Defs.TEAM_NAMES[best], Defs.BOUNTY_VALUE]
			if mode == Defs.MODE_TDM:
				text = "Bounty on team %s: every kill on them counts DOUBLE!" % Defs.TEAM_NAMES[best]
	var nm: String = Defs.STORM_NAMES[map.theme] if k == Defs.EVT_STORM else Defs.EVENT_NAMES[k]
	_msg("EVENT - %s: %s" % [nm, text])
	_ev(Defs.EV_EVENT, Vector2(evt.x, evt.y), Vector2(k, 0))


func end_event() -> void:
	var k: int = evt.k
	_ev(Defs.EV_EVENT, Vector2(evt.x, evt.y), Vector2(k, 2))
	if k == Defs.EVT_SUPPLY and int(evt.item) >= 0:
		items = items.filter(func(it): return int(it.id) != int(evt.item))
	var nm: String = Defs.STORM_NAMES[map.theme] if k == Defs.EVT_STORM else Defs.EVENT_NAMES[k]
	_msg("%s is over." % nm)
	evt = {}
	evt_next = maxf(evt_next, elapsed + 45.0)


## An open spot out in the field, away from bunkers and camps, reachable on foot.
func _drop_spot() -> Vector2:
	for tries in 200:
		var x := rng.randi_range(int(map.W * 0.2), int(map.W * 0.8))
		var y := rng.randi_range(int(map.H * 0.2), int(map.H * 0.8))
		var c := Vector2i(x, y)
		if map.cell_h(x, y) > 0.0 or map.obst[y * map.W + x] != 0 or map.has_roof(x, y) or map.flo[y * map.W + x] == MapData.F_WATER:
			continue
		if map.bunker_at(Vector2(x, y)) >= 0 or astar.is_point_solid(c):
			continue
		return Vector2(x + 0.5, y + 0.5)
	return Vector2(map.W * 0.5 + 0.5, map.H * 0.5 + 0.5)


## Artillery lands near a random living soldier or vehicle (so it matters), never inside a bunker.
func _arty_spot() -> Vector2:
	var cands: Array = []
	for p in players.values():
		if p.alive and map.bunker_at(p.pos) < 0:
			var near_camp := false
			for s in map.team_spawns:
				if p.pos.distance_to(Vector2(s.x, s.y)) < 14.0:
					near_camp = true
			if not near_camp:
				cands.append(p.pos)
	if cands.is_empty():
		return _drop_spot()
	var base: Vector2 = cands[rng.randi() % cands.size()]
	return base + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 4.0)


## AIR STRIKE: after a siren, bomber waves fly straight across the whole map in random directions,
## carpet-bombing a strip under their track, while artillery shells rain down all over the map.
## Bomb/shell impacts are scheduled ahead of time (evt.bombs = [x, y, time]) so clients can warn players.
const AIR_WARN := 6.0
const AIR_TIME := 30.0
const PLANE_SPEED := 16.0
const BOMB_GAP := 3.6
const BOMB_DELAY := 1.2


func _plan_airstrike() -> void:
	evt.warn = AIR_WARN
	evt.t = AIR_WARN + AIR_TIME
	evt.x = map.W * 0.5
	evt.y = map.H * 0.5
	evt.r = 0.0
	evt.runs = []
	evt.bombs = []
	evt.cd = 1.0
	var start := elapsed + AIR_WARN
	var offsets := [0.0, 3.5, 7.0, 11.0, 15.5, 20.0]
	for i in offsets.size():
		var ang := rng.randf() * TAU
		var dir := Vector2.from_angle(ang)
		var mid := Vector2(rng.randf_range(0.15, 0.85) * map.W, rng.randf_range(0.15, 0.85) * map.H)
		var half := float(map.W) * 0.75
		evt.runs.append({"ax": mid.x - dir.x * half, "ay": mid.y - dir.y * half, "bx": mid.x + dir.x * half, "by": mid.y + dir.y * half,
			"t0": start + float(offsets[i]), "on": false})


func _near_spawn(c: Vector2, r := 12.0) -> bool:
	for s in map.team_spawns:
		if c.distance_to(Vector2(s.x, s.y)) < r:
			return true
	return false


func _update_airstrike(dt: float) -> void:
	var now := elapsed
	var bombs: Array = evt.bombs
	for run in evt.runs:
		if run.on or now < float(run.t0):
			continue
		run.on = true
		var a := Vector2(run.ax, run.ay)
		var b := Vector2(run.bx, run.by)
		var L := a.distance_to(b)
		var dir := (b - a) / L
		_ev(Defs.EV_EVENT, a.lerp(b, 0.5), Vector2(Defs.EVT_ARTY, 4))
		var d := rng.randf_range(0.0, BOMB_GAP)
		while d < L:
			var c := a + dir * d + Vector2(-dir.y, dir.x) * rng.randf_range(-1.2, 1.2)
			if c.x > 1.5 and c.y > 1.5 and c.x < map.W - 1.5 and c.y < map.H - 1.5 and not _near_spawn(c):
				bombs.append([c.x, c.y, float(run.t0) + d / PLANE_SPEED + BOMB_DELAY])
			d += BOMB_GAP
	# artillery scattered over the whole map in between the bomber waves
	if now < evt_end_time() - 2.0:
		evt.cd -= dt
		if evt.cd <= 0.0:
			evt.cd = rng.randf_range(0.35, 0.7)
			for tries in 10:
				var c := Vector2(rng.randf_range(3.0, map.W - 3.0), rng.randf_range(3.0, map.H - 3.0))
				if not _near_spawn(c):
					bombs.append([c.x, c.y, now + 1.6])
					break
	var keep: Array = []
	for bm in bombs:
		if float(bm[2]) <= now:
			var c := Vector2(bm[0], bm[1])
			var gz: float = map.ground_at(c, 0.1, 9.0)
			_explode(c, -1, null, 2.3, 90.0, 45.0, gz + 0.15)
		else:
			keep.append(bm)
	evt.bombs = keep


func evt_end_time() -> float:
	return elapsed + float(evt.get("t", 0.0))


## Is this spot about to be hit (a bomb or shell lands within `margin` in the next few seconds)?
func _in_arty(pos: Vector2, margin := 3.0) -> bool:
	return _arty_danger(pos, margin) != Vector2.INF


func _arty_danger(pos: Vector2, margin := 3.0) -> Vector2:
	if evt.is_empty() or int(evt.k) != Defs.EVT_ARTY:
		return Vector2.INF
	var best := Vector2.INF
	var bd := margin
	for bm in evt.get("bombs", []):
		var c := Vector2(bm[0], bm[1])
		var d := c.distance_to(pos)
		if d < bd and float(bm[2]) - elapsed < 3.5:
			bd = d
			best = c
	return best


func _valid_target(t) -> bool:
	if t.ttype == 1:
		return t.alive and t.tank == null
	if t.ttype == 2:
		return t.alive
	return false


func _find_target(e):
	var reach := (15.0 if e.kind == Defs.E_SOLDIER else 20.0) * _vis_mult()
	var best = null
	var bd := reach
	var f := Vector2.from_angle(e.yaw)
	var owner := _guard_owner(e)
	for c in _hostiles(-1):
		if c.ttype == 2 and c.driver == null and c.gunner == null:
			continue
		if owner >= 0 and c.team == owner:
			continue   # a bunker's garrison never shoots the team that owns it
		var to: Vector2 = c.pos - e.pos
		var d := to.length()
		if c.ttype == 1 and c.crouch:
			d *= 1.4
		if d >= bd:
			continue
		var aware: bool = e.alerted or e.kind == Defs.E_TURRET or d < 4.0 or (d > 0.01 and f.dot(to / to.length()) > 0.35)
		if not aware:
			continue
		if _vis(e, c) == 0:
			continue
		best = c
		bd = d
	return best


func _update_enemy(e, dt: float) -> void:
	if e.dead:
		return
	e.cd -= dt
	e.firing_t -= dt
	e.see_t -= dt
	e.path_t -= dt
	e.moving = false
	if e.see_t <= 0.0:
		e.see_t = 0.2 + rng.randf() * 0.15
		e.target = _find_target(e)
	if e.target != null and not _valid_target(e.target):
		e.target = null
	if over:
		return
	if e.kind == Defs.E_TURRET:
		_turret_ai(e, dt)
		return
	if e.target != null:
		var tp: Vector2 = e.target.pos
		var to: Vector2 = tp - e.pos
		var dist := to.length()
		e.alerted = true
		e.last_known = tp
		e.has_lk = true
		if e.bunker >= 0:
			alerts[e.bunker] = true
		var a := to.angle()
		e.yaw = rotate_toward(e.yaw, a, dt * 6.0)
		if dist > 7.0 and e.home.distance_to(tp) < 26.0:
			_follow(e, tp, dt, 1.7)
		if e.cd <= 0.0 and absf(angle_difference(e.yaw, a)) < 0.25:
			e.cd = rng.randf_range(0.8, 1.4)
			e.firing_t = 0.12
			_ev(Defs.EV_ENEMY_SHOT, e.pos)
			var chance := clampf(0.8 - dist * 0.032, 0.15, 0.8)
			if e.target.ttype == 1:
				if e.target.moving:
					chance *= 0.65
				if e.target.crouch:
					chance *= 0.7
				if e.target.sprint:
					chance *= 0.8
			var vis := _vis(e, e.target)
			if vis == 1:
				chance *= 0.35   # only the head shows over cover
			elif vis == 0:
				chance = 0.0
			var hit := rng.randf() < chance
			_enemy_tracer(e, tp, hit)
			if hit:
				_damage(e.target, 10.0, null, false)
	elif e.has_lk and e.home.distance_to(e.last_known) < 26.0:
		_follow(e, e.last_known, dt, 2.0)
		if e.pos.distance_to(e.last_known) < 0.7:
			e.has_lk = false
	else:
		e.has_lk = false
		e.wander_t -= dt
		if e.wander_t <= 0.0:
			e.wander_t = rng.randf_range(2.5, 6.0)
			var w: Vector2 = e.home + Vector2(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
			e.wander = w if map.los(e.pos, w) and not map.circle_blocked(w, 0.25) else e.pos
		if e.pos.distance_to(e.home) > 6.0:
			_follow(e, e.home, dt, 1.2)
		elif e.pos.distance_to(e.wander) > 0.3:
			_step_toward(e, e.wander, dt, 0.8)


func _turret_ai(e, dt: float) -> void:
	if e.target == null:
		e.yaw = wrapf(e.yaw + dt * 0.4, -PI, PI)
		e.burst = 0
		return
	var to: Vector2 = e.target.pos - e.pos
	var dist := to.length()
	var a := to.angle()
	e.yaw = rotate_toward(e.yaw, a, dt * 1.3)
	if e.bunker >= 0:
		alerts[e.bunker] = true
	if absf(angle_difference(e.yaw, a)) < 0.12 and e.cd <= 0.0:
		if e.burst <= 0:
			e.burst = 5
		e.burst -= 1
		e.cd = 0.14 if e.burst > 0 else 1.8
		e.firing_t = 0.1
		_ev(Defs.EV_ENEMY_SHOT, e.pos)
		var vis := _vis(e, e.target)
		var hit := rng.randf() < clampf(0.55 - dist * 0.015, 0.15, 0.55) * (1.0 if vis == 2 else (0.35 if vis == 1 else 0.0))
		_enemy_tracer(e, e.target.pos, hit)
		if hit:
			_damage(e.target, 6.0, null, e.target.ttype == 2)


func _enemy_tracer(e, tp: Vector2, hit: bool) -> void:
	var to: Vector2 = tp - e.pos
	var L := to.length()
	if L < 0.1:
		return
	var d := to / L
	var end := tp
	if not hit:
		end = tp + Vector2(-d.y, d.x) * rng.randf_range(-0.8, 0.8) + d * 1.5
		var wr: Dictionary = map.ray_wall(e.pos, (end - e.pos).normalized(), e.pos.distance_to(end))
		if wr.hit:
			end = e.pos + (end - e.pos).normalized() * (float(wr.dist) - 0.05)
			_ev(Defs.EV_IMPACT, end)
	_ev(Defs.EV_TRACER, e.pos + d * 0.4, end)


func _follow(e, goal: Vector2, dt: float, speed: float) -> void:
	var gc := Vector2i(floori(goal.x), floori(goal.y))
	if e.path_t <= 0.0 or gc != e.path_goal:
		e.path_t = 0.8
		e.path_goal = gc
		var sc := Vector2i(floori(e.pos.x), floori(e.pos.y))
		e.path = []
		if astar.is_in_boundsv(sc) and astar.is_in_boundsv(gc) and not astar.is_point_solid(gc) and not astar.is_point_solid(sc):
			e.path = astar.get_id_path(sc, gc)
		if e.path.size() > 0:
			e.path.pop_front()
	var tgt := goal
	while e.path.size() > 0:
		var c: Vector2i = e.path[0]
		var cc := Vector2(c.x + 0.5, c.y + 0.5)
		if e.pos.distance_to(cc) < 0.35:
			e.path.pop_front()
			continue
		tgt = cc
		break
	_step_toward(e, tgt, dt, speed)


func _step_toward(e, tgt: Vector2, dt: float, speed: float) -> void:
	var d: Vector2 = tgt - e.pos
	var L := d.length()
	if L < 0.01:
		return
	var np: Vector2 = map.move_circle(e.pos, d / L * minf(speed * dt, L), 0.25)
	e.moving = np.distance_squared_to(e.pos) > 0.0000001
	e.pos = np
	if e.target == null:
		e.yaw = rotate_toward(e.yaw, d.angle(), dt * 5.0)


# ---------------------------------------------------------------- world tick

func _vault_loot_count(b: int) -> int:
	var n := 0
	for it in items:
		if it.k == 1 and int(it.vault) == b:
			n += 1
	return n


func _spawn_vault_loot(b: int, announce: bool) -> void:
	var bk: Dictionary = map.bunkers[b]
	for tries in 10:
		var c: Vector2 = bk.vault_cells[rng.randi() % bk.vault_cells.size()]
		var free := c.distance_to(bk.vault_center) > 0.8
		for it in items:
			if it.pos.distance_to(c) < 0.8:
				free = false
		if not free:
			continue
		var roll := rng.randf()
		var kind := 0 if roll < 0.35 else (3 if roll < 0.55 else (2 if roll < 0.8 else 1))
		items.append(_loot_item(kind, c + Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2)), b))
		if announce:
			_ev(Defs.EV_BEEP, c)
		return


func _update_world(dt: float) -> void:
	_update_armor(dt)
	for it in items:
		it.life -= dt
		if it.life <= 0.0 and it.k == 0 and keys.has(int(it.key)):
			_return_key(int(it.key))
	items = items.filter(func(it): return it.life > 0.0)
	loot_t -= dt
	if loot_t <= 0.0 and mode == Defs.MODE_HEIST:
		loot_t = 6.0
		for b in map.bunkers.size():
			if _vault_loot_count(b) < 8:
				_spawn_vault_loot(b, true)
	for b in map.bunkers.size():
		var st: Dictionary = bstate[b]
		if st.acc.has(true):
			# owners hold their breached bunker (owners inside, no enemy players inside) for 60s -> sealed again
			var owners_in := false
			var enemies_in := false
			for q in players.values():
				if q.alive and q.tank == null and map.bunker_at(q.pos) == b:
					if q.team == int(st.owner):
						owners_in = true
					else:
						enemies_in = true
			var holding: bool = (owners_in or int(st.owner) < 0) and not enemies_in
			if holding:
				var before: float = st.hold
				st.hold += dt
				if int(before / 15.0) != int(st.hold / 15.0) and st.hold < RECLAIM_TIME and int(st.owner) >= 0:
					_msg("%s is reclaiming the %s bunker: %d s left" % [Defs.TEAM_NAMES[int(st.owner)], map.bunker_names[b], int(RECLAIM_TIME - st.hold)])
				if st.hold >= RECLAIM_TIME:
					_reclaim(b)
			else:
				st.hold = 0.0
		if idol_t[b] > 0.0:
			idol_t[b] -= dt
			if idol_t[b] <= 0.0:
				items.append(_loot_item(4, map.bunkers[b].vault_center, b))
		if alerts[b]:
			reinforce_t[b] -= dt
			if reinforce_t[b] <= 0.0:
				reinforce_t[b] = 12.0
				var alive_s := 0
				for e in enemies:
					if not e.dead and e.kind == Defs.E_SOLDIER and e.bunker == b:
						alive_s += 1
				if alive_s < 14:
					var pos: Vector2 = map.bunkers[b].reinforce + Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))
					var e = _spawn_enemy(Defs.E_SOLDIER, pos, true)
					e.bunker = b
	var top := -1
	var top_score := -1
	for t in teams:
		if int(teams[t].score) > top_score:
			top_score = int(teams[t].score)
			top = int(t)
	if top_score >= score_limit or elapsed >= time_limit:
		over = true
		winner = top
		_ev(Defs.EV_WIN, Vector2.ZERO)
		_msg("MATCH OVER - %s TEAM WINS with %d %s" % [Defs.TEAM_NAMES[top], top_score, ["points", "captures", "kills", "points"][mode]])


# ---------------------------------------------------------------- WAR: capture points

const POINT_R := 4.5
const CAP_NEUTRAL := 15.0     # seconds to take a neutral point alone
const CAP_ENEMY := 20.0       # seconds to flip an enemy point (it first drains to neutral)
const POINT_TICK := 5.0       # every held point scores +1 this often
const HOLD_ALL_WIN := 60.0    # holding all three this long wins outright
var cpoints: Array = []       # {pos, owner, cap (team capturing or -1), prog 0..1}
var point_t := 0.0
var hold_all := 0.0
var hold_team := -1


## Three points across the middle of the map, perpendicular to the line between the first two camps.
func _place_points() -> void:
	cpoints.clear()
	var c := Vector2(map.W * 0.5, map.H * 0.5)
	var s0: Vector3 = map.team_spawns[0]
	var s1: Vector3 = map.team_spawns[1]
	var axis := (Vector2(s1.x, s1.y) - Vector2(s0.x, s0.y)).normalized()
	var perp := Vector2(-axis.y, axis.x)
	for k in 3:
		var want: Vector2 = c + perp * float(k - 1) * map.W * 0.28
		cpoints.append({"pos": _open_spot(want), "owner": -1, "cap": -1, "prog": 0.0})


func _open_spot(want: Vector2) -> Vector2:
	for rr in range(0, 14):
		for a in maxi(1, rr * 6):
			var c: Vector2 = want + Vector2.from_angle(TAU * float(a) / float(maxi(1, rr * 6))) * float(rr)
			var ci := Vector2i(floori(c.x), floori(c.y))
			if ci.x < 3 or ci.y < 3 or ci.x >= map.W - 3 or ci.y >= map.H - 3:
				continue
			if not map.circle_blocked(c, 1.2, {}, 0.0) and not map.has_roof(ci.x, ci.y):
				return Vector2(ci.x + 0.5, ci.y + 0.5)
	return want


func _update_points(dt: float) -> void:
	for cp in cpoints:
		var counts := {}
		for q in players.values():
			if q.alive and q.pos.distance_to(cp.pos) <= POINT_R:
				counts[q.team] = int(counts.get(q.team, 0)) + 1
		if counts.size() != 1:
			continue   # empty or contested: frozen
		var t: int = int(counts.keys()[0])
		var n: int = int(counts[t])
		var rate: float = (1.0 + 0.25 * float(mini(n, 4) - 1)) * dt   # more people capture a bit faster
		if int(cp.owner) == t:
			cp.prog = minf(1.0, float(cp.prog) + rate / CAP_NEUTRAL)   # heal a damaged hold
			cp.cap = -1
			continue
		if int(cp.owner) >= 0:
			# drain the enemy's hold first
			cp.cap = t
			cp.prog = float(cp.prog) - rate / (CAP_ENEMY * 0.5)
			if float(cp.prog) <= 0.0:
				_msg("%s TEAM neutralised point %s" % [Defs.TEAM_NAMES[t], Defs.POINT_NAMES[cpoints.find(cp)]])
				cp.owner = -1
				cp.prog = 0.0
			continue
		if int(cp.cap) != t:
			cp.cap = t
			cp.prog = 0.0
		cp.prog = float(cp.prog) + rate / CAP_NEUTRAL
		if float(cp.prog) >= 1.0:
			cp.owner = t
			cp.prog = 1.0
			cp.cap = -1
			_ev(Defs.EV_PICKUP, cp.pos, Vector2(1, 0))
			_msg("%s TEAM captured point %s!" % [Defs.TEAM_NAMES[t], Defs.POINT_NAMES[cpoints.find(cp)]])
	# scoring
	point_t += dt
	if point_t >= POINT_TICK:
		point_t -= POINT_TICK
		for cp in cpoints:
			if int(cp.owner) >= 0 and teams.has(int(cp.owner)):
				teams[int(cp.owner)].score += 1
	# one team holding everything wins after a minute
	var o0: int = int(cpoints[0].owner) if cpoints.size() > 0 else -1
	var all_same: bool = o0 >= 0
	for cp in cpoints:
		if int(cp.owner) != o0:
			all_same = false
	if all_same:
		if hold_team != o0:
			hold_team = o0
			hold_all = 0.0
			_msg("%s TEAM holds ALL points - %d s to total victory!" % [Defs.TEAM_NAMES[o0], int(HOLD_ALL_WIN)])
		hold_all += dt
		if hold_all >= HOLD_ALL_WIN and teams.has(o0):
			teams[o0].score = maxi(int(teams[o0].score), score_limit)
	else:
		hold_team = -1
		hold_all = 0.0


func _points_snap() -> Array:
	var out: Array = []
	for cp in cpoints:
		out.append([cp.pos.x, cp.pos.y, int(cp.owner), int(cp.cap), float(cp.prog)])
	return out


## WAR respawn: the owned point closest to the action (nearest to a point we don't own); INF = camp.
func _war_spawn_point(team: int) -> Vector2:
	if mode != Defs.MODE_WAR:
		return Vector2.INF
	var best := Vector2.INF
	var bd := 1e9
	for cp in cpoints:
		if int(cp.owner) != team or int(cp.cap) >= 0:
			continue   # only safe (uncontested) points
		var d := 1e9
		for o in cpoints:
			if int(o.owner) != team:
				d = minf(d, cp.pos.distance_to(o.pos))
		if d < bd:
			bd = d
			best = cp.pos
	return best


func _bot_war_goal(p) -> Dictionary:
	# most bots push the nearest point we don't own; every third bot guards a threatened own point
	var guard: bool = p.slot % 3 == 2
	var best = null
	var bd := 1e9
	for cp in cpoints:
		var own: bool = int(cp.owner) == p.team
		var threatened: bool = own and int(cp.cap) >= 0
		var d: float = p.pos.distance_to(cp.pos)
		if guard and threatened:
			d -= 1000.0
		elif own:
			d += 500.0
		if d < bd:
			bd = d
			best = cp
	if best == null:
		return {"goal": Vector2(map.W * 0.5, map.H * 0.5), "arrive": 2.0}
	var off := Vector2.from_angle(float(p.id) * 2.39996) * 2.2
	return {"goal": best.pos + off, "arrive": 1.5}


# ---------------------------------------------------------------- game modes (capture the flag / team deathmatch)

## Where a team's flag stands: just behind its camp's vehicle spawn, on open walkable ground.
func _flag_home(team: int) -> Vector2:
	var s: Vector3 = map.team_spawns[team]
	var base := Vector2(s.x, s.y)
	var back := -Vector2.from_angle(s.z)
	var side := Vector2(-back.y, back.x)
	for d in [2.5, 3.5, 1.5, 4.5]:
		for k in [0.0, 1.0, -1.0, 2.0, -2.0]:
			var c: Vector2 = base + back * float(d) + side * float(k)
			var ci := Vector2i(floori(c.x), floori(c.y))
			if astar.is_in_boundsv(ci) and not astar.is_point_solid(ci) and map.cell_h(ci.x, ci.y) <= 0.0 \
					and not map.circle_blocked(Vector2(ci.x + 0.5, ci.y + 0.5), 0.4):
				return Vector2(ci.x + 0.5, ci.y + 0.5)
	return base


## The team whose flag this player carries (-1 = none).
func _flag_of(p) -> int:
	for ft in flags:
		if int(flags[ft].st) == 1 and int(flags[ft].car) == p.id:
			return int(ft)
	return -1


func _flag_drop(p) -> void:
	var ft := _flag_of(p)
	if ft < 0:
		return
	var f: Dictionary = flags[ft]
	f.st = 2
	f.car = -1
	f.t = Defs.FLAG_RETURN
	f.pos = p.pos
	f.z = p.z
	_ev(Defs.EV_PICKUP, p.pos, Vector2(0, 0))
	_msg("%s dropped the %s flag!" % [p.name, Defs.TEAM_NAMES[ft]])


func _flag_return(ft: int) -> void:
	var f: Dictionary = flags[ft]
	f.st = 0
	f.car = -1
	f.t = 0.0
	f.pos = f.home
	f.z = 0.0
	_ev(Defs.EV_UNLOCK, f.home)


func _update_flags(dt: float) -> void:
	for ft in flags:
		var t := int(ft)
		var f: Dictionary = flags[ft]
		if int(f.st) == 1:
			var c = players.get(int(f.car))
			if c == null or not c.alive or c.tank != null:
				if c != null:
					_flag_drop(c)
				else:
					f.st = 2
					f.car = -1
					f.t = Defs.FLAG_RETURN
				continue
			f.pos = c.pos
			f.z = c.z
			var own: Dictionary = flags.get(c.team, {})
			if not own.is_empty() and int(own.st) == 0 and c.pos.distance_to(own.home) < 1.6 and absf(c.z) < 0.9:
				teams[c.team].score += 1
				_ev(Defs.EV_DEPOSIT, c.pos, Vector2(1, c.team))
				_msg("%s [%s] CAPTURED the %s flag!  (%d/%d)" % [c.name, Defs.TEAM_NAMES[c.team], Defs.TEAM_NAMES[t], int(teams[c.team].score), score_limit])
				_flag_return(t)
			continue
		if int(f.st) == 2:
			f.t = float(f.t) - dt
			if float(f.t) <= 0.0:
				_flag_return(t)
				_msg("The %s flag returned to its base" % Defs.TEAM_NAMES[t])
				continue
		for p in players.values():
			if not p.alive or p.tank != null or p.pos.distance_to(f.pos) > 0.8 or absf(p.z - float(f.z)) > 0.9:
				continue
			if p.team == t:
				if int(f.st) == 2:
					_flag_return(t)
					_msg("%s returned the %s flag" % [p.name, Defs.TEAM_NAMES[t]])
					break
			elif _flag_of(p) < 0:
				f.st = 1
				f.car = p.id
				f.t = 0.0
				_ev(Defs.EV_PICKUP, f.pos, Vector2(0, 0))
				_msg("%s [%s] TOOK the %s flag!" % [p.name, Defs.TEAM_NAMES[p.team], Defs.TEAM_NAMES[t]])
				break


## Where a bot wants to go in CTF / TDM: {"goal": Vector2, "arrive": float}.
func _bot_mode_goal(p) -> Dictionary:
	var s: Vector3 = map.team_spawns[p.team]
	var home := Vector2(s.x, s.y)
	if mode == Defs.MODE_WAR:
		return _bot_war_goal(p)
	if mode == Defs.MODE_TDM:
		# hunt the nearest enemy soldier or crewed vehicle
		var bd := 1e9
		var goal := Vector2(map.W * 0.5, map.H * 0.5)
		for q in _hostiles(p.team):
			if q.ttype == 0 or (q.ttype == 2 and q.driver == null and q.gunner == null):
				continue
			var d: float = p.pos.distance_to(q.pos)
			if d < bd:
				bd = d
				goal = q.pos
		# don't run straight at them: swing out to this bot's flank side while closing in
		var away: Vector2 = goal - p.pos
		if away.length() > 7.0 and p.bot != null:
			var fg: Vector2 = goal + Vector2(-away.y, away.x).normalized() * float(p.bot.flank) * minf(7.0, away.length() * 0.35)
			if fg.x > 2.0 and fg.y > 2.0 and fg.x < map.W - 2.0 and fg.y < map.H - 2.0 and not map.circle_blocked(fg, 0.3):
				goal = fg
		return {"goal": goal, "arrive": 2.0}
	var mine: Dictionary = flags.get(p.team, {})
	var defender: bool = p.slot % 2 == 1
	if _flag_of(p) >= 0:
		# carrier: run home to our flag
		return {"goal": mine.home if not mine.is_empty() else home, "arrive": 0.1}
	if not mine.is_empty():
		if int(mine.st) == 2 and (defender or p.pos.distance_to(mine.pos) < 35.0):
			return {"goal": mine.pos, "arrive": 0.05}
		if int(mine.st) == 1:
			var c = players.get(int(mine.car))
			if c != null and (defender or p.pos.distance_to(c.pos) < 25.0):
				return {"goal": c.pos, "arrive": 1.0}
		if defender:
			var a := float(p.id % 6) * TAU / 6.0
			var gp: Vector2 = mine.home + Vector2.from_angle(a) * 3.0
			if astar.is_in_boundsv(Vector2i(floori(gp.x), floori(gp.y))) and astar.is_point_solid(Vector2i(floori(gp.x), floori(gp.y))):
				gp = mine.home
			return {"goal": gp, "arrive": 1.5}
	# attacker: escort a nearby teammate carrying a flag, else raid the closest enemy base
	var bd := 1e9
	var goal := home
	for ft in flags:
		if int(ft) == p.team:
			continue
		var f: Dictionary = flags[ft]
		if int(f.st) == 1:
			var c = players.get(int(f.car))
			if c != null and c.team == p.team:
				if p.pos.distance_to(c.pos) < 25.0:
					return {"goal": c.pos + Vector2.from_angle(float(p.id)) * 2.0, "arrive": 1.5}
				continue
		var d: float = home.distance_to(f.home) + p.pos.distance_to(f.pos) * 0.5
		if d < bd:
			bd = d
			goal = f.pos
	return {"goal": goal, "arrive": 0.05}


# ---------------------------------------------------------------- AI teams

## Each AI team focuses one bunker: the one it has made most progress in, otherwise the nearest.
func _pick_team_targets() -> void:
	for t in teams:
		var s: Vector3 = map.team_spawns[int(t)]
		var best := 0
		var bscore := -1e9
		for b in map.bunkers.size():
			var st: Dictionary = bstate[b]
			if int(st.owner) == int(t):
				continue
			var prog := 0
			for r in R + 1:
				if st.acc[r]:
					prog += 2
			for r in R:
				if st.sol[r]:
					prog += 3
			# keys the team already holds for this bunker matter most
			for q in players.values():
				if q.team == int(t):
					for kid in q.keys:
						if int(keys[kid].bunker) == b and int(keys[kid].team) != int(t):
							prog += 4
			var sc: float = prog * 100.0 - Vector2(s.x, s.y).distance_to(map.bunkers[b].center) + float((int(t) * 37 + b * 11) % 7)
			if sc > bscore:
				bscore = sc
				best = b
		team_target[int(t)] = best


func _human_in(t) -> bool:
	return (t.driver != null and t.driver.bot == null) or (t.gunner != null and t.gunner.bot == null)


func _alive_target(t) -> bool:
	if t.ttype == 0:
		return not t.dead
	if t.ttype == 1:
		return t.alive and t.tank == null
	return t.alive


func _bot_find_target(p):
	var reach := (24.0 if p.tank != null else 17.0) * _vis_mult()
	var best = null
	var bd := reach
	for c in _hostiles(p.team):
		var d: float = c.pos.distance_to(p.pos)
		if d < bd and _vis(p, c, _pass(p.team)) > 0:
			best = c
			bd = d
	return best


func _team_gate(team: int, from: Vector2):
	var b: int = team_target.get(team, 0)
	var best = null
	var bd := 1e9
	for g in gates:
		if int(g.bunker) != b:
			continue
		var d: float = from.distance_to(g.approach) * (0.5 if g.open else 1.0)
		if d < bd:
			bd = d
			best = g
	return best


func _bunker_open(b: int) -> bool:
	for g in gates:
		if int(g.bunker) == b and g.open:
			return true
	return false


func _bot_think(p, dt: float) -> Array:
	var b = p.bot
	var o := {"mx": 0.0, "my": 0.0, "yaw": p.yaw, "fire": false, "alt": false, "hold": false, "sprint": false, "crouch": false}
	b.tick += 1
	b.use_cd -= dt
	b.seat_t -= dt
	b.see_t -= dt
	b.react_t -= dt
	b.err_t -= dt
	b.path_t -= dt
	b.strafe_t -= dt
	b.pause_t -= dt
	b.retreat_t -= dt
	b.flank_t -= dt
	if b.flank_t <= 0.0:
		b.flank_t = rng.randf_range(5.0, 11.0)
		b.flank = rng.randf_range(-1.0, 1.0)
	# track the target's real velocity (strafing players don't move where they look)
	if b.target != null and b.target.id == b.tlast_id:
		var v: Vector2 = (b.target.pos - b.tlast) / maxf(dt, 0.001)
		if v.length() < 15.0:
			b.tvel = b.tvel.lerp(v, minf(1.0, dt * 8.0))
	else:
		b.tvel = Vector2.ZERO
	if b.target != null:
		b.tlast = b.target.pos
		b.tlast_id = b.target.id
	else:
		b.tlast_id = -1
	b.wcd -= dt
	b.throw_cd -= dt
	if b.err_t <= 0.0:
		b.err_t = 0.6
		b.err = rng.randfn(0.0, AIM_SD[difficulty])
	if p.alive and not over:
		if b.see_t <= 0.0:
			b.see_t = 0.25
			var nt = _bot_find_target(p)
			if nt != b.target:
				b.react_t = REACT[difficulty]
			b.target = nt
		if b.target != null and not _alive_target(b.target):
			b.target = null
		if p.tank != null:
			_bot_tank(p, b, dt, o)
		elif not _bot_mortar(p, b, dt, o):
			_bot_foot(p, b, dt, o)
	# aim up/down at the target's chest (with the bot's aiming error)
	var pitch := 0.0
	if o.has("pitch"):
		pitch = float(o.pitch)   # plane crews steer their own pitch
	elif b.target != null and p.alive:
		var d := maxf(0.5, p.pos.distance_to(b.target.pos))
		pitch = atan2(_aim_z(b.target) - (_eye_z(p) - 0.04), d) + b.err * 0.4
	return [o.mx, o.my, o.yaw, o.fire, o.alt, o.hold, b.use_c, b.seat_c, b.wreq, b.wseq, 0, p.epoch,
		o.sprint, o.crouch, b.jump_c, b.throw_c, p.want[0], p.want[1], p.want[2], pitch, false, o.get("ax", 0.0), o.get("ay", 0.0)]


func _bot_tank(p, b, dt: float, o: Dictionary) -> void:
	var t = p.tank
	var role := _role(p)
	if _is_plane(t):
		_bot_plane(p, b, t, role, dt, o)
		return
	if mode != Defs.MODE_HEIST and b.travel == Vector2.INF and not _human_in(t):
		# CTF / TDM: vehicles are taxis to wherever the bot wants to fight
		var mg: Dictionary = _bot_mode_goal(p)
		b.travel = mg.goal
	if b.travel != Vector2.INF and not _human_in(t):
		# taxi ride: drive to where we wanted to go on foot, then hop out
		b.taxi_stuck = b.taxi_stuck + dt if (not t.moving and role != Defs.ROLE_GUNNER) else 0.0
		if t.pos.distance_to(b.travel) < 6.0 or t.hp < 60.0 or b.taxi_stuck > 3.0:
			b.travel = Vector2.INF
			b.taxi_stuck = 0.0
			b.taxi_cd = 20.0
			if b.use_cd <= 0.0:
				b.use_c += 1
				b.use_cd = 3.0
			return
		if role == Defs.ROLE_SOLO or role == Defs.ROLE_DRIVER:
			_bot_drive(b, t, b.travel, dt, o)
		if role != Defs.ROLE_DRIVER and b.target != null:
			var desired: float = (b.target.pos - t.pos).angle() + b.err * 0.5
			o.yaw = rotate_toward(t.turret, desired, 2.2 * dt)
			o.alt = absf(angle_difference(o.yaw, desired)) < 0.1 and b.react_t <= 0.0
		return
	var g = _team_gate(p.team, t.pos)
	if g == null:
		return
	var appr: Vector2 = g.approach
	var gc: Vector2 = g.center
	var human_in := _human_in(t)
	var at_gate: bool = t.pos.distance_to(appr) < 3.0
	if not human_in and b.use_cd <= 0.0 and ((g.open and at_gate) or t.hp < 90.0):
		b.use_c += 1
		b.use_cd = 3.0
		return
	# alone in the vehicle a bot can't drive and shoot at once: drive to the gate, then move to the gun (and back)
	var alone: bool = t.driver == null or t.gunner == null
	if alone and b.seat_t <= 0.0:
		var want_gun: bool = at_gate or (b.target != null and not t.moving and t.pos.distance_to(b.target.pos) < 9.0)
		if (role == Defs.ROLE_DRIVER and want_gun) or (role == Defs.ROLE_GUNNER and not want_gun):
			_switch_seat(p)
			b.seat_t = 1.5
			return
	if role == Defs.ROLE_SOLO or role == Defs.ROLE_DRIVER:
		if not at_gate:
			_bot_drive(b, t, appr, dt, o)
		else:
			var diff := angle_difference(t.hull, (gc - t.pos).angle())
			o.mx = clampf(diff * 3.0, -1.0, 1.0)
			o.my = 0.35 if absf(diff) > 0.08 else 0.0   # creep to swing the nose (no pivoting on the spot)
	if role == Defs.ROLE_SOLO or role == Defs.ROLE_GUNNER:
		var aim_pt = null
		var cannon := false
		if b.target != null:
			aim_pt = b.target.pos
			cannon = str(_vs(t).main) == "none" or b.target.ttype == 2 or (b.target.ttype == 0 and b.target.kind == Defs.E_TURRET) or t.pos.distance_to(aim_pt) > 7.0 or str(_vs(t).main) == "autocannon"
		elif not g.open and t.pos.distance_to(gc) < 13.0:
			aim_pt = gc
			cannon = true
		var cur: float = t.turret
		if aim_pt != null:
			var desired: float = (aim_pt - t.pos).angle() + b.err * 0.5
			var ny := rotate_toward(cur, desired, 2.2 * dt)
			o.yaw = ny
			if absf(angle_difference(ny, desired)) < 0.07 and b.react_t <= 0.0:
				o.fire = cannon
				o.alt = b.target != null
		else:
			o.yaw = rotate_toward(cur, t.hull, 1.5 * dt)
	elif role == Defs.ROLE_DRIVER and b.target != null:
		var a: float = (b.target.pos - t.pos).angle()
		o.fire = absf(angle_difference(t.hull, a)) < 0.12 and b.react_t <= 0.0


func _tank_path(from: Vector2i, to: Vector2i) -> Array:
	var s := from
	if not tank_astar.is_in_boundsv(s) or tank_astar.is_point_solid(s):
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
			var q: Vector2i = from + d
			if tank_astar.is_in_boundsv(q) and not tank_astar.is_point_solid(q):
				s = q
				break
	if not tank_astar.is_in_boundsv(s) or not tank_astar.is_in_boundsv(to) or tank_astar.is_point_solid(s) or tank_astar.is_point_solid(to):
		return []
	return tank_astar.get_id_path(s, to)


func _bot_drive(b, t, goal: Vector2, dt: float, o: Dictionary) -> void:
	var gcell := Vector2i(floori(goal.x), floori(goal.y))
	if b.path_t <= 0.0 or gcell != b.path_goal:
		b.path_t = 2.0
		b.path_goal = gcell
		b.path = _tank_path(Vector2i(floori(t.pos.x), floori(t.pos.y)), gcell)
	var tgt := goal
	while b.path.size() > 0:
		var c: Vector2i = b.path[0]
		var cc := Vector2(c.x + 0.5, c.y + 0.5)
		if t.pos.distance_to(cc) < 1.3 and b.path.size() > 1:
			b.path.pop_front()
			continue
		tgt = cc
		break
	var diff := angle_difference(t.hull, (tgt - t.pos).angle())
	# vehicles can't pivot on the spot: turn while rolling, three-point turn when the goal is behind
	o.mx = clampf(diff * 2.5, -1.0, 1.0)
	o.my = 1.0 if absf(diff) < 0.45 else 0.6
	if absf(diff) > 2.2 and t.pos.distance_to(tgt) < 6.0:
		o.my = -0.7
		o.mx = -1.0 if diff > 0.0 else 1.0
	b.stuck_t += dt
	if b.stuck_t > 1.2:
		if t.pos.distance_to(b.stuck_pos) < 0.4 and b.reverse_t <= 0.0:
			b.reverse_t = 0.9
			b.path_t = 0.0
		b.stuck_t = 0.0
		b.stuck_pos = t.pos
	if b.reverse_t > 0.0:
		b.reverse_t -= dt
		o.my = -1.0
		o.mx = -1.0 if diff > 0.0 else 1.0   # reversing steers the other way round


func _stolen_key_any(q, b: int) -> bool:
	for k in q.keys:
		if int(keys[k].bunker) == b:
			return true
	return false


func _team_solver(team: int, bunker: int, room: int):
	for q in players.values():
		if q.team == team and q.alive and q.puzzle == room and q.pz_bunker == bunker:
			return q
	return null


func _bot_puzzle(p, b, dt: float, o: Dictionary) -> void:
	if b.target != null and b.target.pos.distance_to(p.pos) < 6.0 and b.react_t <= 0.0 and b.use_cd <= 0.0:
		b.use_c += 1
		b.use_cd = 2.0
		return
	var pz: Dictionary = bstate[p.pz_bunker].pz[p.puzzle]
	b.pz_t -= dt
	var ty: int = pz.ty
	# continuous-control puzzles
	if ty == Defs.PZ_TUNER:
		var err: float = float(pz.t) - float(pz.v) + rng.randfn(0.0, 0.02 * (3 - difficulty))
		o.mx = clampf(err * 9.0, -1.0, 1.0)
		return
	if ty == Defs.PZ_STEADY:
		var nz: float = 0.08 * (3 - difficulty)
		o.mx = clampf((float(pz.tx) - float(pz.cx)) * 5.0 - float(pz.vx) * 1.2 + rng.randfn(0.0, nz), -1.0, 1.0)
		o.my = clampf((float(pz.ty2) - float(pz.cy)) * 5.0 - float(pz.vy) * 1.2 + rng.randfn(0.0, nz), -1.0, 1.0)
		return
	if ty == Defs.PZ_PUMP:
		# alternate left/right at a human cadence (faster on higher difficulty)
		if b.pz_t <= 0.0:
			b.pz_release = not b.pz_release
			b.pz_t = PZ_SPEED[difficulty] * rng.randf_range(0.2, 0.3)
		o.mx = 1.0 if b.pz_release else -1.0
		return
	if ty == Defs.PZ_TIMING:
		if b.pz_release:
			if b.pz_t <= 0.0:
				b.pz_release = false
			return
		var off: float = absf(float(pz.m) - float(pz.zc))
		# reaction error: sometimes presses a bit early / late
		var slack: float = float(pz.zw) * [1.4, 1.0, 0.7][difficulty]
		if off < slack and b.pz_t <= 0.0:
			o.fire = true
			b.pz_release = true
			b.pz_t = PZ_SPEED[difficulty] * rng.randf_range(0.5, 1.0)
		return
	if ty == Defs.PZ_VALVES:
		var worst := 0
		var we := -1.0
		for i in 3:
			var e: float = absf(float(pz.g[i]) - 0.5)
			if e > we:
				we = e
				worst = i
		if b.pz_release:
			if b.pz_t <= 0.0:
				b.pz_release = false
			return
		var cur_e: float = absf(float(pz.g[pz.sel]) - 0.5)
		if worst != int(pz.sel) and we > 0.05 and cur_e < 0.03 and b.pz_t <= 0.0:
			o.mx = 1.0
			b.pz_release = true
			b.pz_t = 0.12 + PZ_SPEED[difficulty] * 0.4
			return
		o.my = clampf((0.5 - float(pz.g[pz.sel])) * 10.0, -1.0, 1.0)
		return
	if ty == Defs.PZ_DIAL:
		var n: int = pz.combo[pz.idx]
		var need := 1 if int(pz.idx) % 2 == 0 else -1
		var dist := fposmod((n - float(pz.v)) * need, 40.0)
		if int(pz.lastdir) != need and dist < 1.0:
			dist += 40.0   # approach from the required side
		if b.pz_release:
			if b.pz_t <= 0.0:
				b.pz_release = false
			return
		if dist > 0.35 and dist < 39.5:
			o.mx = need * clampf(dist / 5.0, 0.25, 1.0)
		elif b.pz_t <= 0.0:
			o.fire = true
			b.pz_release = true
			b.pz_t = PZ_SPEED[difficulty] * rng.randf_range(0.7, 1.3)
		return
	# tap-input puzzles: alternate a press frame with a release pause
	if b.pz_release:
		if b.pz_t <= 0.0:
			b.pz_release = false
			b.pz_t = PZ_SPEED[difficulty] * rng.randf_range(0.6, 1.2)
		return
	if b.pz_t > 0.0:
		return
	var dir := -1
	if ty == Defs.PZ_CODE:
		dir = int(pz.seq[pz.pos])
		if rng.randf() < 0.05:
			dir = (dir + 1) % 4
	if dir >= 0:
		o.my = 1.0 if dir == 0 else (-1.0 if dir == 2 else 0.0)
		o.mx = 1.0 if dir == 1 else (-1.0 if dir == 3 else 0.0)
	b.pz_release = true
	b.pz_t = 0.1


func _bot_foot(p, b, dt: float, o: Dictionary) -> void:
	if p.puzzle >= 0:
		_bot_puzzle(p, b, dt, o)
		return
	var t = _slot_tank(p)
	if t != null and (not t.alive or (t.driver != null and t.gunner != null and t.driver != p and t.gunner != p)):
		# own vehicle wrecked or full: use the team's other one
		for o2 in tanks:
			if o2.team == p.team and o2.alive and not _is_plane(o2) and (o2.driver == null or o2.gunner == null):
				t = o2
	var tb: int = team_target.get(p.team, 0)
	var held := _stolen_key(p)
	if held != -99999:
		tb = int(keys[held].bunker)   # carrying a key: go use it
	# outside HEIST the map has no bunkers at all
	var heist: bool = mode == Defs.MODE_HEIST and tb < map.bunkers.size()
	var bk: Dictionary = map.bunkers[tb] if heist else {}
	var acc: Array = bstate[tb].acc if heist else []
	var sol: Array = bstate[tb].sol if heist else []
	var own_b: int = TEAM_BUNKER[p.team]
	var own_st: Dictionary = bstate[own_b] if heist and own_b < bstate.size() else {"acc": []}
	var defend := false
	if own_st.acc.has(true):
		# the lowest-id living bot of the team holds the home bunker to reclaim it
		defend = true
		for q in players.values():
			if q.team == p.team and q.bot != null and q.alive and q.id < p.id:
				defend = false
	var goal: Vector2 = p.pos
	var shoot_at = null
	var arrive := 0.9
	var press_near := Vector2.INF
	var tank_ok: bool = t != null and t.alive and (t.driver == null or t.gunner == null)
	var open: bool = _bunker_open(tb) or map.bunker_at(p.pos) == tb
	var s: Vector3 = map.team_spawns[p.team]
	var home := Vector2(s.x, s.y)
	var own_key_item = null
	for it in items:
		if it.k == 0 and keys.has(int(it.key)) and int(keys[it.key].team) == p.team and p.pos.distance_to(it.pos) < 18.0:
			own_key_item = it
	var crate = null
	if evt_active(Defs.EVT_SUPPLY) and evt.landed and not defend:
		for it in items:
			if int(it.id) == int(evt.item) and p.pos.distance_to(it.pos) < 32.0:
				crate = it
	var danger := _arty_danger(p.pos)
	if danger != Vector2.INF:
		# a bomb is about to land here: run away from it
		var away: Vector2 = p.pos - danger
		goal = danger + (away.normalized() if away.length() > 0.1 else Vector2.RIGHT) * 4.5
		arrive = 0.5
	elif mode == Defs.MODE_WAR and t != null and _is_plane(t) and t.alive and t.z <= 0.0 and (t.driver == null or t.gunner == null):
		# aircrew: go and board our plane
		goal = t.pos
		press_near = t.pos
		arrive = 0.2
	elif mode != Defs.MODE_HEIST:
		var mg: Dictionary = _bot_mode_goal(p)
		goal = mg.goal
		arrive = mg.arrive
	elif crate != null and p.carried < 150:
		goal = crate.pos
		arrive = 0.2
	elif tank_ok and (_human_in(t) or (not open and p.pos.distance_to(t.pos) < 16.0)):
		goal = t.pos
		press_near = t.pos
	elif p.carried >= 150 or (p.carried > 0 and (_vault_loot_count(tb) == 0 or not acc[V])):
		goal = home
		if t != null and t.alive and p.pos.distance_to(t.pos) < p.pos.distance_to(home):
			goal = t.pos
	elif own_key_item != null:
		goal = own_key_item.pos
		arrive = 0.2
	elif defend:
		var obk: Dictionary = map.bunkers[own_b]
		goal = obk.center + Vector2(float(p.id % 5) - 2.0, float(p.id % 3) * 2.0 - 2.0)
		if map.bunker_at(p.pos) == own_b and p.pos.distance_to(goal) < 6.0:
			arrive = 6.0
		elif not _bunker_open(own_b):
			var og = null
			var od := 1e9
			for g in gates:
				if int(g.bunker) == own_b and p.pos.distance_to(g.approach) < od:
					od = p.pos.distance_to(g.approach)
					og = g
			if og != null:
				goal = og.approach
				if p.pos.distance_to(goal) < 3.0:
					shoot_at = og.center
	elif not open:
		var g = _team_gate(p.team, p.pos)
		if g != null:
			goal = g.approach
			if p.pos.distance_to(goal) < 3.0:
				shoot_at = g.center
	elif acc[V]:
		var best := 1e9
		goal = bk.vault_center
		for it in items:
			if it.k == 1 and int(it.vault) == tb and p.pos.distance_to(it.pos) < best:
				best = p.pos.distance_to(it.pos)
				goal = it.pos
		arrive = 0.2
	else:
		# an open, unsolved room nobody of ours is working -> solve it; otherwise guard a teammate's room
		var room := -1
		var guard_room := -1
		for r in R:
			if acc[r] and not sol[r]:
				if guard_room < 0:
					guard_room = r
				if room < 0 and _team_solver(p.team, tb, r) == null:
					room = r
		var need := -1
		for r in R:
			if not acc[r]:
				need = r
				break
		if need >= 0 and _team_key(p, tb) != -99999:
			var dc: Vector2i = bk.doors[need]
			goal = bk.door_outside[need]
			press_near = Vector2(dc.x + 0.5, dc.y + 0.5)
		elif room >= 0:
			goal = bk.terminals[room]
			press_near = bk.terminals[room]
		elif guard_room >= 0:
			goal = bk.door_outside[guard_room]
		else:
			# hunt this bunker's keys: loose ones first, then whoever carries one (its owners or a rival)
			var best := 1e9
			goal = bk.center
			for it in items:
				if it.k == 0 and keys.has(int(it.key)) and int(keys[it.key].team) != p.team and not keys[it.key].used and p.pos.distance_to(it.pos) < best * (0.6 if int(keys[it.key].bunker) == tb else 1.0):
					best = p.pos.distance_to(it.pos)
					goal = it.pos
			if best > 1e8:
				for q in players.values():
					if q.team != p.team and q.alive and q.keys.size() > 0 and p.pos.distance_to(q.pos) < best:
						best = p.pos.distance_to(q.pos)
						goal = q.pos
			arrive = 0.3
	# long trip ahead and a free team vehicle nearby: drive there instead of walking
	b.travel = Vector2.INF
	b.taxi_cd -= dt
	if press_near == Vector2.INF and b.taxi_cd <= 0.0 and not _in_arty(p.pos) and p.pos.distance_to(goal) > 30.0 and _flag_of(p) < 0:
		for tv in tanks:
			if tv.team == p.team and tv.alive and not _is_plane(tv) and (tv.driver == null or tv.gunner == null) and not _human_in(tv) \
					and p.pos.distance_to(tv.pos) < 16.0 and tv.pos.distance_to(goal) < p.pos.distance_to(goal) + 8.0:
				b.travel = goal
				goal = tv.pos
				press_near = tv.pos
				break
	if press_near != Vector2.INF:
		arrive = 0.2
	if press_near != Vector2.INF and p.pos.distance_to(press_near) < 1.25 and b.use_cd <= 0.0:
		b.use_c += 1
		b.use_cd = 1.5
	var ta: AStarGrid2D = team_astar[p.team]
	var gcell := Vector2i(floori(goal.x), floori(goal.y))
	if b.path_t <= 0.0 or gcell != b.path_goal:
		b.path_t = 1.0
		b.path_goal = gcell
		b.path = []
		var sc := Vector2i(floori(p.pos.x), floori(p.pos.y))
		if ta.is_in_boundsv(sc) and ta.is_in_boundsv(gcell) and not ta.is_point_solid(sc) and not ta.is_point_solid(gcell):
			b.path = ta.get_id_path(sc, gcell)
	var tgt := goal
	while b.path.size() > 0:
		var c: Vector2i = b.path[0]
		var cc := Vector2(c.x + 0.5, c.y + 0.5)
		if p.pos.distance_to(cc) < 0.35 and b.path.size() > 1:
			b.path.pop_front()
			continue
		tgt = cc
		break
	var mv: Vector2 = tgt - p.pos
	mv = mv.normalized() if mv.length() > 0.15 else Vector2.ZERO
	if mode != Defs.MODE_HEIST and mv != Vector2.ZERO and p.pos.distance_to(goal) > 3.0:
		# weave a little instead of running a perfectly straight, predictable line
		var sw: float = sin(elapsed * 1.9 + float(p.id) * 1.7) * 0.45 + sin(elapsed * 0.7 + float(p.id)) * 0.25
		mv = (mv + Vector2(-mv.y, mv.x) * sw).normalized()
	if p.pos.distance_to(goal) < arrive:
		mv = Vector2.ZERO
	var want_w := 1
	if int(p.mags.get(p.primary, 0)) <= 0 and int(p.res.get(p.primary, 0)) == 0:
		want_w = 2
	var aim_pt = shoot_at
	var fighting := false
	if b.target != null:
		var td: float = b.target.pos.distance_to(p.pos)
		fighting = true
		aim_pt = b.target.pos
		if td < 1.3:
			want_w = 3
		var to: Vector2 = (b.target.pos - p.pos).normalized()
		var side: Vector2 = Vector2(-to.y, to.x) * b.strafe
		# full duel footwork only where fighting IS the objective; carriers of flags / loot / keys keep running
		var duel: bool = (mode == Defs.MODE_TDM or mode == Defs.MODE_WAR) and _flag_of(p) < 0
		var carrying: bool = _flag_of(p) >= 0 or p.carried > 0 or _stolen_key(p) != -99999
		if not duel and not carrying and td < 9.0:
			if b.strafe_t <= 0.0:
				b.strafe_t = rng.randf_range(0.4, 1.2)
				b.strafe = -b.strafe
			mv = (mv * 0.45 + side * 0.75).limit_length(1.0)
		elif duel and td < 16.0:
			# duel movement: irregular left/right strafes, short stops to aim, the odd jump,
			# keep a fighting distance (back off when too close, push when far)
			if b.strafe_t <= 0.0:
				b.strafe_t = rng.randf_range(0.25, 1.1)
				if rng.randf() < 0.75:
					b.strafe = -b.strafe
				b.pause_t = rng.randf_range(0.25, 0.7) if rng.randf() < 0.2 else 0.0
				if rng.randf() < 0.1 and td > 3.0 and difficulty > 0:
					b.jump_c += 1
			var radial := 0.0
			if td < 4.5:
				radial = -0.6
			elif td > 11.0:
				radial = 0.45
			var push: float = 0.6 if mode == Defs.MODE_WAR else 0.25   # WAR: keep advancing on the objective
			if b.pause_t > 0.0:
				mv = Vector2.ZERO if mode != Defs.MODE_WAR else mv * 0.3
			else:
				mv = (mv * push + side * 0.85 + to * radial).limit_length(1.0)
		elif td > 12.0 and rng.randf() < 0.02:
			o.crouch = true
		if p.hp < 35.0 and b.retreat_t <= -4.0 and rng.randf() < 0.03:
			b.retreat_t = rng.randf_range(1.2, 2.5)
		if b.retreat_t > 0.0 and duel:
			mv = (-to * 0.85 + side * 0.5).limit_length(1.0)
		if p.eqn > 0 and b.throw_cd <= 0.0 and td > 4.0 and td < 11.0 and p.equip == Defs.EQ_FRAG and rng.randf() < 0.01:
			b.throw_c += 1
			b.throw_cd = 6.0
		if p.hp < 45.0 and p.equip == Defs.EQ_MEDKIT and p.eqn > 0 and b.throw_cd <= 0.0:
			b.throw_c += 1
			b.throw_cd = 3.0
	if aim_pt != null:
		var lead := Vector2.ZERO
		if b.target != null:
			# lead by the target's measured velocity (bullet travel time)
			var bv: float = maxf(20.0, float(Defs.WPN[p.weapon].vel))
			lead = b.tvel * (b.target.pos.distance_to(p.pos) / bv) * [0.5, 0.75, 0.95][difficulty]
		var desired: float = (aim_pt + lead - p.pos).angle() + b.err
		o.yaw = rotate_toward(p.yaw, desired, 7.0 * dt)
		if absf(angle_difference(o.yaw, desired)) < 0.1 and b.react_t <= 0.0:
			var wd: Dictionary = Defs.WPN[p.weapon]
			o.fire = bool(wd.auto) or b.tick % 6 < 3
			o.alt = fighting and p.weapon == Defs.W_SNIPER
	elif mv != Vector2.ZERO:
		o.yaw = rotate_toward(p.yaw, mv.angle(), 8.0 * dt)
		o.sprint = p.pos.distance_to(goal) > 10.0 and not p.exhausted and p.stamina > 0.25
	var fwd := Vector2.from_angle(o.yaw)
	o.my = mv.dot(fwd)
	o.mx = mv.dot(Vector2(-fwd.y, fwd.x))
	# rockets are for vehicles and gates: against infantry a bot switches to its sidearm
	if want_w == 1 and p.primary == Defs.W_RPG and b.target != null and b.target.ttype != 2:
		want_w = 2
	var want_id: int = [p.primary, p.secondary, Defs.W_KNIFE][want_w - 1]
	if p.weapon != want_id and b.wcd <= 0.0:
		b.wreq = want_w
		b.wseq += 1
		b.wcd = 0.6
