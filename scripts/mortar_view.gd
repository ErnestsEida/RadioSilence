extends Control
## Top-down tactical view shown instead of the raycaster while a player mans the base mortar:
## aerial terrain (shaders/mortar_map.gdshader over the packed map), trees and props, the team's
## units, enemies the team has spotted, the range rings, the reticle, shells in flight and impacts.
## Owned by one GameView (gv); main.gd feeds it mouse / stick aim and reads the aim point back.

const Defs = preload("res://scripts/defs.gd")
const MapData = preload("res://scripts/map_data.gd")
const SPAN := 54.0          # world units across the shorter side of the view
const AIM_SPEED := 24.0     # keyboard / stick reticle speed (world units per second)
const VISION := 22.0
const HAZE := Color(0.02, 0.03, 0.02, 0.55)

var gv = null
var on := false
var aim := Vector2.ZERO
var cam := Vector2.ZERO
var ppu := 20.0
var mpos := Vector2.ZERO
var r_max := 80.0
var r_min := 8.0
var splash := 2.6
var reload := 4.0
var cd := 0.0
var team := 0
var time := 0.0
var snap: Dictionary = {}
var me: Dictionary = {}
var fx: Array = []
var seen := {}
var seen_t := 0.0
var scorch: Array = []     # [pos, time]
var terrain: ColorRect
var tmat: ShaderMaterial
var overlay: Control
var font: Font
var fired_t := 9.0
var last_cd := 0.0


func setup(p_gv) -> void:
	gv = p_gv
	font = ThemeDB.fallback_font
	visible = false
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	terrain = ColorRect.new()
	terrain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	terrain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tmat = ShaderMaterial.new()
	tmat.shader = load("res://shaders/mortar_map.gdshader")
	terrain.material = tmat
	add_child(terrain)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	var th: Array = MapData.THEMES[int(gv.mapdata.palette)]
	tmat.set_shader_parameter("map_tex", gv.res.map_tex)
	tmat.set_shader_parameter("fog_tex", gv.fog_tex)
	tmat.set_shader_parameter("map_size", Vector2(float(gv.mapdata.W), float(gv.mapdata.H)))
	var names := ["ground_a", "ground_b", "dirt_a", "dirt_b"]
	for k in 4:
		var c: Color = th[k]
		tmat.set_shader_parameter(names[k], Vector3(c.r, c.g, c.b))
	var rt: Color = th[8]
	tmat.set_shader_parameter("rock_tint", Vector3(rt.r, rt.g, rt.b))
	tmat.set_shader_parameter("snow", 1.0 if int(gv.mapdata.theme) == 2 else 0.0)


static func manning(rec: Dictionary) -> bool:
	return bool(rec.get("mortar", false)) and int(rec.get("role", Defs.ROLE_FOOT)) == Defs.ROLE_FOOT


# ---------------------------------------------------------------- per frame

func show_view(p_snap: Dictionary, p_me: Dictionary, effects: Array, dt: float) -> void:
	snap = p_snap
	me = p_me
	fx = effects
	time += dt
	team = int(me.tm)
	var md: Dictionary = snap.get("mortar", {})
	var mm: Dictionary = md.get("m", {})
	if mm.has(team):
		var m: Dictionary = mm[team]
		mpos = Vector2(float(m.x), float(m.y))
		cd = float(m.cd)
	r_max = float(md.get("rng", 80.0))
	r_min = float(md.get("min", 8.0))
	reload = float(md.get("rel", 4.0))
	splash = float(md.get("spl", 2.6))
	if not on:
		on = true
		var c := Vector2(float(gv.mapdata.W), float(gv.mapdata.H)) * 0.5
		aim = mpos + (c - mpos).normalized() * minf(32.0, r_max)
		_clamp_aim()
		cam = aim
		fired_t = 9.0
		last_cd = cd
		visible = true
		gv.svc.visible = false
		gv.hud.visible = false
	if cd > last_cd + 0.5:
		fired_t = 0.0
	last_cd = cd
	fired_t += dt
	ppu = minf(size.x, size.y) / SPAN
	cam = cam.lerp(aim, 1.0 - exp(-dt * 4.5))
	tmat.set_shader_parameter("view_origin", cam - size * 0.5 / ppu)
	tmat.set_shader_parameter("ppu", ppu)
	tmat.set_shader_parameter("rect_size", size)
	tmat.set_shader_parameter("time", time)
	tmat.set_shader_parameter("mortar_pos", mpos)
	tmat.set_shader_parameter("r_max", r_max)
	tmat.set_shader_parameter("r_min", r_min)
	_update_seen(dt)
	_track_impacts()
	overlay.queue_redraw()


func hide_view() -> void:
	if not on:
		return
	on = false
	visible = false
	gv.svc.visible = true
	gv.hud.visible = true


## The team's fog-of-war spotting, plus what the crew sees over the sandbags (3D line of sight).
func _update_seen(dt: float) -> void:
	seen_t -= dt
	if seen_t > 0.0:
		return
	seen_t = 0.2
	seen = {} if gv._evt_on(Defs.EVT_JAM) else gv.spotted.duplicate()
	var my := Vector2(float(me.x), float(me.y))
	var e: PackedFloat32Array = snap.get("e", PackedFloat32Array())
	for i in e.size() / 9:
		var o := i * 9
		var typ := int(e[o])
		if typ != Defs.E_SOLDIER and typ != Defs.E_TURRET and typ != Defs.E_PLAYER and typ != Defs.E_TANK:
			continue
		if int(e[o + 4]) == team or (int(e[o + 5]) & 4) != 0:
			continue
		var pos := Vector2(e[o + 1], e[o + 2])
		if my.distance_to(pos) < VISION and gv.mapdata.los3(my, 0.75, pos, 0.6):
			seen[int(e[o + 8])] = true


## Leave a scorch mark wherever something blew up.
func _track_impacts() -> void:
	for f in fx:
		if int(f.k) == 0 and not f.has("mv_seen"):
			f["mv_seen"] = true
			scorch.append([f.p, time])
	while scorch.size() > 40 or (scorch.size() > 0 and time - float(scorch[0][1]) > 40.0):
		scorch.pop_front()


# ---------------------------------------------------------------- aiming (called from main.gd)

func _clamp_aim() -> void:
	var v := aim - mpos
	var L := v.length()
	if L < 0.01:
		v = Vector2.RIGHT
		L = 1.0
	aim = mpos + v / L * clampf(L, r_min, r_max)
	aim = aim.clamp(Vector2(1.0, 1.0), Vector2(float(gv.mapdata.W) - 1.0, float(gv.mapdata.H) - 1.0))


func mouse_move(rel: Vector2) -> void:
	aim += rel / maxf(ppu, 1.0) * Settings.sens
	_clamp_aim()


static func _k(key: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(key) else 0.0


static func _dz(v: float) -> float:
	return 0.0 if absf(v) < 0.2 else v


## Moves the reticle with the movement input (+ arrows / right stick) and returns the aim point.
func update_aim(lp, mv: Vector2, fast: bool, dt: float) -> Vector2:
	if not on:
		return Vector2.ZERO
	var v := mv
	if lp.device == "kbm":
		v += Vector2(_k(KEY_RIGHT) - _k(KEY_LEFT), _k(KEY_UP) - _k(KEY_DOWN))
	elif lp.device == "kb2":
		v = Vector2(_k(KEY_RIGHT) - _k(KEY_LEFT), _k(KEY_UP) - _k(KEY_DOWN))
	else:
		v += Vector2(_dz(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)), -_dz(Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)))
	v = v.limit_length(1.0)
	aim += Vector2(v.x, -v.y) * AIM_SPEED * (2.0 if fast else 1.0) * dt
	_clamp_aim()
	return aim


# ---------------------------------------------------------------- numbers (keep in sync with world.gd)

func flight_time(d: float) -> float:
	return 2.8 + 1.4 * clampf(d / maxf(1.0, r_max), 0.0, 1.0)


func scatter(d: float) -> float:
	return 0.3 + 0.022 * d


# ---------------------------------------------------------------- drawing

func _ws(p: Vector2) -> Vector2:
	return size * 0.5 + (p - cam) * ppu


func _txt(pos: Vector2, t: String, fs: int, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	overlay.draw_string(font, pos + Vector2(2, 2), t, align, width, fs, Color(0, 0, 0, col.a * 0.85))
	overlay.draw_string(font, pos, t, align, width, fs, col)


func _panel(r: Rect2, accent: Color) -> void:
	overlay.draw_rect(r, Color(0.04, 0.06, 0.05, 0.72))
	overlay.draw_rect(r, Color(accent.r, accent.g, accent.b, 0.55), false, 1.5)
	overlay.draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color(accent.r, accent.g, accent.b, 0.85))


func _dashed_circle(c: Vector2, r: float, col: Color, w: float, n: int) -> void:
	for i in n:
		var a0 := TAU * float(i) / float(n)
		overlay.draw_arc(c, r, a0, a0 + TAU / float(n) * 0.55, 6, col, w)


func _dashed_line(a: Vector2, b: Vector2, col: Color, w: float, dash: float) -> void:
	var L := a.distance_to(b)
	if L < 1.0:
		return
	var d := (b - a) / L
	var t := fmod(time * 30.0, dash * 2.0)
	while t < L:
		overlay.draw_line(a + d * t, a + d * minf(L, t + dash), col, w)
		t += dash * 2.0


func _draw_overlay() -> void:
	if not on:
		return
	var s := overlay.size
	var fs := int(clampf(s.y / 40.0, 12.0, 24.0))
	for sc in scorch:
		var sp := _ws(sc[0])
		var age: float = time - float(sc[1])
		overlay.draw_circle(sp, 1.3 * ppu, Color(0.05, 0.04, 0.03, 0.32 * clampf(1.0 - age / 40.0, 0.0, 1.0)))
	_draw_decor(s)
	_draw_pit()
	_draw_units(s)
	_draw_shells()
	_draw_blasts()
	_draw_reticle(fs)
	_draw_hud(s, fs)


func _visible_pt(sp: Vector2, s: Vector2, margin: float) -> bool:
	return sp.x > -margin and sp.y > -margin and sp.x < s.x + margin and sp.y < s.y + margin


func _star(c: Vector2, r: float, n: int, inner: float, rot: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in n * 2:
		var rr := r if i % 2 == 0 else r * inner
		pts.append(c + Vector2.from_angle(rot + PI * float(i) / float(n)) * rr)
	overlay.draw_colored_polygon(pts, col)


func _draw_decor(s: Vector2) -> void:
	var snowy: bool = int(gv.mapdata.theme) == 2
	var shadow := Vector2(0.32, 0.26) * ppu
	for d in gv.mapdata.decor:
		var p := Vector2(float(d[0]), float(d[1]))
		var sp := _ws(p)
		if not _visible_pt(sp, s, ppu * 2.0):
			continue
		var fr := int(d[2])
		var sc := float(d[3])
		var h := fmod(p.x * 12.9898 + p.y * 78.233, 1.0)
		if fr == Defs.FR_TREE:
			var r := 0.5 * sc * ppu
			overlay.draw_circle(sp + shadow * 1.4, r, Color(0, 0, 0, 0.3))
			overlay.draw_circle(sp, r, Color(0.12, 0.24, 0.08))
			overlay.draw_circle(sp + Vector2(-0.18, -0.2) * r, r * 0.72, Color(0.19, 0.34, 0.12))
			overlay.draw_circle(sp + Vector2(-0.32, -0.36) * r, r * 0.36, Color(0.3, 0.46, 0.2))
		elif fr == Defs.FR_PINE:
			var r := 0.42 * sc * ppu
			_star(sp + shadow * 1.5, r, 7, 0.55, h * TAU, Color(0, 0, 0, 0.3))
			_star(sp, r, 7, 0.55, h * TAU, Color(0.09, 0.2, 0.12))
			_star(sp + Vector2(-0.12, -0.14) * r, r * 0.62, 7, 0.55, h * TAU + 0.3, Color(0.8, 0.84, 0.9) if snowy else Color(0.15, 0.3, 0.17))
		elif fr == Defs.FR_DEADTREE:
			var r := 0.45 * sc * ppu
			for k in 5:
				var a := h * TAU + TAU * float(k) / 5.0
				overlay.draw_line(sp, sp + Vector2.from_angle(a) * r, Color(0.28, 0.2, 0.13), maxf(1.0, ppu * 0.08))
		elif fr == Defs.FR_BUSH or fr == Defs.FR_SNOWBUSH or fr == Defs.FR_DRYBUSH:
			var r := 0.42 * sc * ppu
			var c := Color(0.17, 0.3, 0.11)
			if fr == Defs.FR_SNOWBUSH:
				c = Color(0.78, 0.8, 0.86)
			elif fr == Defs.FR_DRYBUSH:
				c = Color(0.45, 0.38, 0.2)
			overlay.draw_circle(sp + shadow * 0.6, r, Color(0, 0, 0, 0.22))
			overlay.draw_circle(sp, r, c)
			overlay.draw_circle(sp + Vector2(-0.25, -0.25) * r, r * 0.5, c.lightened(0.18))
		elif fr == Defs.FR_CACTUS:
			var r := 0.28 * sc * ppu
			overlay.draw_circle(sp + shadow, r, Color(0, 0, 0, 0.25))
			overlay.draw_circle(sp, r, Color(0.22, 0.42, 0.2))
			overlay.draw_circle(sp, r * 0.45, Color(0.35, 0.58, 0.3))
		elif fr == Defs.FR_CRATE:
			var r := 0.36 * sc * ppu
			overlay.draw_rect(Rect2(sp - Vector2(r, r) + shadow * 0.5, Vector2(r, r) * 2.0), Color(0, 0, 0, 0.3))
			overlay.draw_rect(Rect2(sp - Vector2(r, r), Vector2(r, r) * 2.0), Color(0.55, 0.4, 0.22))
			overlay.draw_rect(Rect2(sp - Vector2(r, r), Vector2(r, r) * 2.0), Color(0.3, 0.2, 0.1), false, 1.5)
			overlay.draw_line(sp - Vector2(r, r), sp + Vector2(r, r), Color(0.35, 0.24, 0.12), 1.5)
		elif fr == Defs.FR_BARREL:
			var r := 0.28 * sc * ppu
			overlay.draw_circle(sp + shadow * 0.5, r, Color(0, 0, 0, 0.3))
			overlay.draw_circle(sp, r, Color(0.45, 0.16, 0.1))
			overlay.draw_arc(sp, r * 0.7, 0, TAU, 16, Color(0.25, 0.1, 0.07), 1.5)
		elif fr == Defs.FR_FIRE:
			var r := (0.3 + 0.08 * sin(time * 17.0 + h * 9.0)) * ppu
			overlay.draw_circle(sp, r * 2.2, Color(1.0, 0.5, 0.1, 0.12))
			overlay.draw_circle(sp, r, Color(1.0, 0.55, 0.15, 0.9))
			overlay.draw_circle(sp, r * 0.5, Color(1.0, 0.9, 0.5))
		elif fr == Defs.FR_CARWRECK:
			var a := h * TAU
			var f := Vector2.from_angle(a) * 0.75 * sc * ppu
			var rgt := Vector2.from_angle(a + PI * 0.5) * 0.38 * sc * ppu
			var pts := PackedVector2Array([sp - f - rgt, sp + f - rgt, sp + f + rgt, sp - f + rgt])
			var shp := PackedVector2Array()
			for q in pts:
				shp.append(q + shadow)
			overlay.draw_colored_polygon(shp, Color(0, 0, 0, 0.3))
			overlay.draw_colored_polygon(pts, Color(0.32, 0.2, 0.13))
			overlay.draw_line(sp - f * 0.2 - rgt, sp - f * 0.2 + rgt, Color(0.15, 0.1, 0.08), 2.0)
		elif fr == Defs.FR_RUBBLE:
			for k in 3:
				var o := Vector2.from_angle(h * TAU + k * 2.1) * 0.25 * ppu
				overlay.draw_rect(Rect2(sp + o - Vector2(2, 2), Vector2(4, 4) * (1.0 + k * 0.3)), Color(0.42, 0.4, 0.37))
		elif fr == Defs.FR_SANDBAG:
			overlay.draw_rect(Rect2(sp - Vector2(0.35, 0.18) * ppu, Vector2(0.7, 0.36) * ppu), Color(0.6, 0.53, 0.36))
		elif fr >= Defs.FR_FLAG and fr < Defs.FR_FLAG + 10:
			var ft := (fr - Defs.FR_FLAG) / 2
			var fc: Color = Defs.TEAM_COLORS[ft] if ft < 4 else Color(0.85, 0.82, 0.75)
			var wave := sin(time * 4.0 + h * 6.0) * 0.08
			overlay.draw_line(sp, sp + Vector2(0, -0.2) * ppu, Color(0.2, 0.2, 0.2), 2.0)
			overlay.draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -0.2) * ppu, sp + Vector2(0.75, -0.05 + wave) * ppu, sp + Vector2(0, 0.25) * ppu]), fc)


func _draw_pit() -> void:
	var sp := _ws(mpos)
	var tc: Color = Defs.TEAM_COLORS[team]
	var dirv := (aim - mpos).normalized()
	overlay.draw_circle(sp + Vector2(0.15, 0.12) * ppu, 0.42 * ppu, Color(0, 0, 0, 0.35))
	overlay.draw_circle(sp, 0.42 * ppu, Color(0.22, 0.24, 0.2))
	overlay.draw_arc(sp, 0.42 * ppu, 0, TAU, 24, tc, 2.0)
	var tip := sp + dirv * 0.75 * ppu
	overlay.draw_line(sp - dirv * 0.15 * ppu, tip, Color(0.12, 0.13, 0.11), maxf(3.0, 0.24 * ppu))
	overlay.draw_line(sp - dirv * 0.1 * ppu, tip, Color(0.34, 0.37, 0.3), maxf(1.5, 0.1 * ppu))
	if fired_t < 0.18:
		var k := fired_t / 0.18
		overlay.draw_circle(tip, (0.3 + k * 0.6) * ppu, Color(1.0, 0.85, 0.45, 0.9 * (1.0 - k)))
	if fired_t < 1.6:
		var k2 := fired_t / 1.6
		for j in 3:
			var o := Vector2.from_angle(float(j) * 2.1 + time * 0.3) * (0.3 + k2 * 0.9) * ppu
			overlay.draw_circle(tip + o + dirv * k2 * ppu * 0.6, (0.35 + k2 * 0.7) * ppu, Color(0.75, 0.73, 0.68, 0.45 * (1.0 - k2)))


func _unit(sp: Vector2, yaw: float, col: Color, r: float, ring: Color) -> void:
	overlay.draw_circle(sp + Vector2(2, 2), r, Color(0, 0, 0, 0.4))
	overlay.draw_circle(sp, r, col)
	overlay.draw_arc(sp, r, 0, TAU, 20, ring, 2.0)
	var f := Vector2.from_angle(yaw)
	overlay.draw_colored_polygon(PackedVector2Array([sp + f * r * 1.9, sp + f.rotated(0.7) * r * 0.9, sp + f.rotated(-0.7) * r * 0.9]), ring)


func _vehicle(sp: Vector2, hull: float, turret: float, vt: int, col: Color, ring: Color, wreck: bool) -> void:
	var vr: float = float(Defs.VEHICLES[clampi(vt, 0, 4)].r)
	var f := Vector2.from_angle(hull) * vr * 1.25 * ppu
	var rg := Vector2.from_angle(hull + PI * 0.5) * vr * 0.85 * ppu
	var pts := PackedVector2Array([sp - f - rg, sp + f - rg, sp + f + rg, sp - f + rg])
	var shp := PackedVector2Array()
	for q in pts:
		shp.append(q + Vector2(0.25, 0.2) * ppu)
	overlay.draw_colored_polygon(shp, Color(0, 0, 0, 0.35))
	overlay.draw_colored_polygon(pts, Color(0.18, 0.17, 0.16) if wreck else col.darkened(0.15))
	pts.append(pts[0])
	overlay.draw_polyline(pts, ring, 2.0)
	if not wreck:
		overlay.draw_circle(sp, vr * 0.5 * ppu, col.lightened(0.15))
		overlay.draw_line(sp, sp + Vector2.from_angle(turret) * vr * 1.8 * ppu, col.darkened(0.5), maxf(2.0, 0.12 * ppu))


func _draw_units(s: Vector2) -> void:
	var e: PackedFloat32Array = snap.get("e", PackedFloat32Array())
	var pulse := 0.6 + 0.4 * sin(time * 7.0)
	var my_id := int(me.id)
	for i in e.size() / 9:
		var o := i * 9
		var typ := int(e[o])
		var pos := Vector2(e[o + 1], e[o + 2])
		var sp := _ws(pos)
		if not _visible_pt(sp, s, 40.0):
			continue
		var ang: float = e[o + 3]
		var et := int(e[o + 4])
		var fl := int(e[o + 5])
		var aux: float = e[o + 7]
		var id := int(e[o + 8])
		var friendly := et == team
		if typ == Defs.E_PLAYER:
			var r := maxf(6.0, 0.38 * ppu)
			if friendly:
				var tc: Color = Defs.TEAM_COLORS[team]
				_unit(sp, ang, tc.lightened(0.15), r, Color.WHITE if id == my_id else Color(0.05, 0.05, 0.05))
			elif seen.has(id):
				var ec: Color = Defs.TEAM_COLORS[clampi(et, 0, 3)]
				overlay.draw_arc(sp, r * 1.9, 0, TAU, 24, Color(1, 0.2, 0.15, 0.5 * pulse), 2.0)
				_unit(sp, ang, ec, r, Color(1, 0.15, 0.1))
		elif typ == Defs.E_TANK or typ == Defs.E_WRECK:
			var vt := (fl >> 8) & 15
			var wreck := typ == Defs.E_WRECK
			if friendly:
				_vehicle(sp, ang, aux, vt, Defs.TEAM_COLORS[team], Color(0.05, 0.05, 0.05), wreck)
			elif seen.has(id) or (wreck and float(gv.fog_data[(clampi(int(pos.y), 0, int(gv.mapdata.H) - 1) * int(gv.mapdata.W) + clampi(int(pos.x), 0, int(gv.mapdata.W) - 1)) * 2 + 1]) == 0.0):
				_vehicle(sp, ang, aux, vt, Defs.TEAM_COLORS[clampi(et, 0, 3)], Color(1, 0.15, 0.1), wreck)
				if not wreck:
					overlay.draw_arc(sp, 1.6 * ppu, 0, TAU, 28, Color(1, 0.2, 0.15, 0.5 * pulse), 2.0)
		elif typ == Defs.E_SOLDIER or typ == Defs.E_TURRET:
			if (fl & 4) != 0:
				continue
			if friendly:
				overlay.draw_circle(sp, maxf(3.0, 0.22 * ppu), Defs.TEAM_COLORS[team].darkened(0.2))
			elif seen.has(id):
				var r2 := maxf(4.0, (0.26 if typ == Defs.E_SOLDIER else 0.42) * ppu)
				overlay.draw_circle(sp + Vector2(2, 2), r2, Color(0, 0, 0, 0.4))
				if typ == Defs.E_TURRET:
					overlay.draw_rect(Rect2(sp - Vector2(r2, r2), Vector2(r2, r2) * 2.0), Color(0.75, 0.12, 0.08))
					overlay.draw_line(sp, sp + Vector2.from_angle(ang) * r2 * 1.8, Color(0.2, 0.05, 0.03), 3.0)
				else:
					overlay.draw_circle(sp, r2, Color(0.85, 0.12, 0.08))
					overlay.draw_arc(sp, r2, 0, TAU, 16, Color(0.25, 0.03, 0.02), 1.5)
		elif typ == Defs.E_SHELL:
			overlay.draw_circle(sp, 3.0, Color(1.0, 0.85, 0.4))
		elif typ == Defs.E_DROP:
			overlay.draw_rect(Rect2(sp - Vector2(0.4, 0.4) * ppu, Vector2(0.8, 0.8) * ppu), Color(0.3, 0.38, 0.22))
			overlay.draw_rect(Rect2(sp - Vector2(0.4, 0.4) * ppu, Vector2(0.8, 0.8) * ppu), Color(0.3, 1.0, 0.4, pulse), false, 2.0)


func _draw_shells() -> void:
	var md: Dictionary = snap.get("mortar", {})
	var tc: Color = Defs.TEAM_COLORS[team]
	for sh in md.get("s", []):
		var st := int(sh[0])
		var from := Vector2(float(sh[1]), float(sh[2]))
		var a := Vector2(float(sh[3]), float(sh[4]))
		var left: float = float(sh[5])
		var T: float = maxf(0.1, float(sh[6]))
		var sp := _ws(a)
		if st == team:
			var k := clampf(1.0 - left / T, 0.0, 1.0)
			overlay.draw_circle(sp, splash * ppu, Color(1.0, 0.75, 0.25, 0.08 + 0.1 * k))
			overlay.draw_arc(sp, splash * ppu, 0, TAU, 40, Color(1.0, 0.8, 0.3, 0.85), 2.0)
			overlay.draw_arc(sp, splash * ppu * (1.0 - k), 0, TAU, 32, Color(1.0, 0.9, 0.5, 0.6), 1.5)
			_txt(sp + Vector2(-20, -splash * ppu - 6), "%.1f" % left, 15, Color(1, 0.9, 0.55))
			# the shell itself: ground track + an oblique lift for its height on the arc
			var apex := 9.0 * T * T / 8.0
			for j in range(7, -1, -1):
				var kj := clampf(k - float(j) * 0.02, 0.0, 1.0)
				var gp := from.lerp(a, kj)
				var lift := 4.0 * apex * kj * (1.0 - kj) * 0.22
				var pj := _ws(gp) + Vector2(0.0, -lift * ppu)
				if j == 0:
					overlay.draw_circle(_ws(gp), maxf(3.0, 0.2 * ppu), Color(0, 0, 0, 0.4))
					overlay.draw_circle(pj, maxf(7.0, 0.5 * ppu), Color(1.0, 0.9, 0.6, 0.25))
					overlay.draw_circle(pj, maxf(4.0, 0.26 * ppu), Color(0.95, 0.92, 0.8))
					overlay.draw_circle(pj, maxf(2.0, 0.13 * ppu), tc.darkened(0.2))
				else:
					overlay.draw_circle(pj, maxf(2.0, 0.17 * ppu) * (1.0 - j * 0.1), Color(0.9, 0.88, 0.82, 0.5 - j * 0.06))
		elif left < 2.2:
			var pulse := 0.5 + 0.5 * sin(time * 16.0)
			overlay.draw_circle(sp, splash * ppu, Color(1, 0.1, 0.05, 0.12 + 0.15 * pulse))
			overlay.draw_arc(sp, splash * ppu, 0, TAU, 40, Color(1, 0.2, 0.1, 0.9), 2.5)
			_txt(sp + Vector2(-40, splash * ppu + 18), "INCOMING", 15, Color(1, 0.35, 0.3, 0.6 + 0.4 * pulse))


func _draw_blasts() -> void:
	for f in fx:
		var k := int(f.k)
		if k != 0 and k != 4 and k != 6:
			continue
		var p: Vector2 = f.p
		var sp := _ws(p)
		var age: float = float(f.t)
		var q: float = age / maxf(0.01, float(f.life))
		if k == 0:
			overlay.draw_circle(sp, lerpf(0.6, 3.0, sqrt(q)) * ppu, Color(1.0, 0.55, 0.15, 0.5 * (1.0 - q)))
			overlay.draw_circle(sp, lerpf(0.5, 1.6, q) * ppu, Color(1.0, 0.9, 0.6, 0.85 * (1.0 - q)))
			overlay.draw_arc(sp, lerpf(0.5, 4.5, q) * ppu, 0, TAU, 32, Color(1, 1, 0.9, 0.6 * (1.0 - q)), 2.0)
		else:
			var r := lerpf(0.5, 1.4, q) * ppu
			overlay.draw_circle(sp + Vector2(q * 0.6, -q * 0.3) * ppu, r, Color(0.55, 0.53, 0.5, 0.35 * (1.0 - q)))


func _draw_reticle(fs: int) -> void:
	var sp := _ws(aim)
	var ms := _ws(mpos)
	var ready := cd <= 0.0
	var c := Color(0.45, 1.0, 0.55) if ready else Color(1.0, 0.72, 0.28)
	var d := mpos.distance_to(aim)
	_dashed_line(ms, sp, Color(1, 1, 1, 0.3), 1.5, 9.0)
	var R := splash * ppu
	overlay.draw_arc(sp, R, 0, TAU, 48, Color(0, 0, 0, 0.5), 4.0)
	overlay.draw_arc(sp, R, 0, TAU, 48, c, 2.0)
	_dashed_circle(sp, scatter(d) * 2.0 * ppu + R * 0.15, Color(c.r, c.g, c.b, 0.55), 1.5, 24)
	for k in 4:
		var dv := Vector2.from_angle(PI * 0.5 * float(k) + PI * 0.25 * 0.0)
		overlay.draw_line(sp + dv * R * 0.35, sp + dv * R * 0.8, c, 2.0)
		overlay.draw_line(sp + dv * R * 1.15, sp + dv * R * 1.5, c, 2.0)
	overlay.draw_circle(sp, 2.5, c)
	var tsec := flight_time(d)
	_txt(sp + Vector2(R * 1.6, -6), "%d m" % int(round(d)), fs - 3, c)
	_txt(sp + Vector2(R * 1.6, fs - 4), "%.1f s   +/-%.1f" % [tsec, scatter(d)], fs - 7, Color(c.r, c.g, c.b, 0.85))


func _hint_keys() -> Array:
	var dev: String = gv.lp.device
	if dev == "kbm":
		return ["MOUSE / WASD", "LMB", "E", "SHIFT"]
	if dev == "kb2":
		return ["ARROWS", "Num0", "Num Enter", "Num9"]
	return ["STICKS", "RT", "X", "L3"]


func _draw_hud(s: Vector2, fs: int) -> void:
	var tc: Color = Defs.TEAM_COLORS[team]
	var pad := 14.0
	# title
	var tr := Rect2(pad, pad, 330, fs * 2.6 + 10)
	_panel(tr, tc)
	_txt(tr.position + Vector2(12, fs + 10), "MORTAR", fs + 6, Color(1, 0.95, 0.8))
	_txt(tr.position + Vector2(12, fs * 2 + 14), "%s BASE   range %d-%d m" % [Defs.TEAM_NAMES[team], int(r_min), int(r_max)], fs - 6, tc.lightened(0.4))
	# status: reload + shells in flight
	var bw := minf(440.0, s.x * 0.5)
	var br := Rect2(s.x * 0.5 - bw * 0.5, s.y - pad - fs * 3.6, bw, fs * 3.6)
	_panel(br, tc)
	var keys := _hint_keys()
	var frac := 1.0 - clampf(cd / maxf(0.1, reload), 0.0, 1.0)
	var bar := Rect2(br.position + Vector2(12, 12), Vector2(bw - 24, fs * 1.1))
	overlay.draw_rect(bar, Color(0, 0, 0, 0.6))
	overlay.draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color(0.35, 0.85, 0.4) if cd <= 0.0 else Color(0.9, 0.6, 0.2))
	var st := "READY  -  [%s] FIRE" % keys[1] if cd <= 0.0 else "RELOADING  %.1f s" % cd
	_txt(bar.position + Vector2(0, bar.size.y - 4), st, fs - 4, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, bar.size.x)
	var mine := 0
	var nxt := 99.0
	var md: Dictionary = snap.get("mortar", {})
	for sh in md.get("s", []):
		if int(sh[0]) == team:
			mine += 1
			nxt = minf(nxt, float(sh[5]))
	var fl_txt := "SHELLS IN FLIGHT: %d" % mine
	if mine > 0:
		fl_txt += "    next impact %.1f s" % nxt
	_txt(Vector2(br.position.x, br.position.y + fs * 3.0), fl_txt, fs - 5, Color(1, 0.88, 0.55) if mine > 0 else Color(0.8, 0.8, 0.78), HORIZONTAL_ALIGNMENT_CENTER, bw)
	# health + controls
	var hp := float(me.hp)
	var hr := Rect2(pad, s.y - pad - 22, 220, 22)
	overlay.draw_rect(hr, Color(0, 0, 0, 0.6))
	overlay.draw_rect(Rect2(hr.position, Vector2(hr.size.x * clampf(hp / 100.0, 0.0, 1.0), hr.size.y)), Color(0.8, 0.15, 0.15))
	overlay.draw_rect(hr, Color(1, 1, 1, 0.4), false, 1.0)
	_txt(hr.position + Vector2(6, 17), "HP %d" % int(hp), fs - 6)
	_txt(Vector2(pad, s.y - pad - 34), "[%s] leave mortar" % keys[2], fs - 5, Color(0.9, 0.9, 0.85, 0.9))
	_txt(Vector2(0, s.y - pad - 6), "%s aim   %s fast   %s fire" % [keys[0], keys[3], keys[1]], fs - 6, Color(0.85, 0.85, 0.8, 0.8), HORIZONTAL_ALIGNMENT_RIGHT, s.x - pad)
	_draw_inset(s, pad, fs)
	# kill feed / messages
	var t: float = float(snap.get("t", 0.0))
	var my := s.y * 0.16
	for m in snap.get("msg", []):
		var age: float = t - float(m[1])
		if age < 5.0:
			_txt(Vector2(0, my), str(m[0]), fs - 4, Color(1, 1, 1, clampf(5.0 - age, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER, s.x)
			my += fs + 4
	# taking fire
	var hurt := float(me.get("hurt", 0.0))
	if hurt > 0.05:
		var a := clampf(hurt, 0.0, 1.0) * 0.45
		var bwid := s.y * 0.08
		overlay.draw_rect(Rect2(0, 0, s.x, bwid), Color(0.8, 0.05, 0.02, a))
		overlay.draw_rect(Rect2(0, s.y - bwid, s.x, bwid), Color(0.8, 0.05, 0.02, a))
		overlay.draw_rect(Rect2(0, 0, bwid, s.y), Color(0.8, 0.05, 0.02, a))
		overlay.draw_rect(Rect2(s.x - bwid, 0, bwid, s.y), Color(0.8, 0.05, 0.02, a))
		_txt(Vector2(0, s.y * 0.3), "UNDER FIRE!", fs + 4, Color(1, 0.35, 0.3, 0.5 + 0.5 * sin(time * 10.0)), HORIZONTAL_ALIGNMENT_CENTER, s.x)


## Whole-map overview: explored terrain, range circle, current view box, reticle.
func _draw_inset(s: Vector2, pad: float, fs: int) -> void:
	var ms := clampf(minf(s.x, s.y) * 0.26, 110.0, 230.0)
	var o := Vector2(s.x - pad - ms, pad)
	var W := float(gv.mapdata.W)
	var k := ms / W
	overlay.draw_rect(Rect2(o - Vector2(3, 3), Vector2(ms + 6, ms + 6)), Color(0, 0, 0, 0.75))
	overlay.draw_texture_rect(gv.res.mini_tex, Rect2(o, Vector2(ms, ms)), false, Color(1, 1, 1, 0.9))
	overlay.draw_texture_rect(gv.fog_tex, Rect2(o, Vector2(ms, ms)), false, Color(1, 1, 1, 0.6))
	var tc: Color = Defs.TEAM_COLORS[team]
	var mp := o + mpos * k
	var box := Rect2(o, Vector2(ms, ms))
	var prev := mp + Vector2(r_max * k, 0.0)
	for i in range(1, 97):
		var q := mp + Vector2.from_angle(TAU * float(i) / 96.0) * r_max * k
		if box.has_point(q) and box.has_point(prev):
			overlay.draw_line(prev, q, Color(1, 0.82, 0.35, 0.8), 1.5)
		prev = q
	var vr := Rect2(o + (cam - size * 0.5 / ppu) * k, size / ppu * k).intersection(Rect2(o, Vector2(ms, ms)))
	overlay.draw_rect(vr, Color(1, 1, 1, 0.7), false, 1.0)
	overlay.draw_circle(mp, 3.5, tc)
	var md: Dictionary = snap.get("mortar", {})
	for sh in md.get("s", []):
		if int(sh[0]) == team:
			overlay.draw_circle(o + Vector2(float(sh[3]), float(sh[4])) * k, 2.5, Color(1, 0.85, 0.3))
	var ap := o + aim * k
	overlay.draw_line(ap - Vector2(5, 0), ap + Vector2(5, 0), Color(0.45, 1, 0.55), 2.0)
	overlay.draw_line(ap - Vector2(0, 5), ap + Vector2(0, 5), Color(0.45, 1, 0.55), 2.0)
	_txt(o + Vector2(ms - 16, fs - 2), "N", fs - 4, Color(1, 1, 1, 0.8))
	overlay.draw_colored_polygon(PackedVector2Array([o + Vector2(ms - 11, fs + 2), o + Vector2(ms - 15, fs + 12), o + Vector2(ms - 7, fs + 12)]), Color(1, 1, 1, 0.8))


## Mortar markers on the normal HUD minimap: own shells' targets, and a red warning where enemy
## shells are about to land.
func minimap_marks(hud: Control, o: Vector2, k: float, p_snap: Dictionary, my_team: int) -> void:
	var md: Dictionary = p_snap.get("mortar", {})
	var mm: Dictionary = md.get("m", {})
	if mm.has(my_team):
		var m: Dictionary = mm[my_team]
		var mp := o + Vector2(float(m.x), float(m.y)) * k
		hud.draw_arc(mp, 4.0, 0, TAU, 12, Defs.TEAM_COLORS[my_team].lightened(0.3), 1.5)
		hud.draw_circle(mp, 1.5, Color.WHITE)
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.016)
	for sh in md.get("s", []):
		var p := o + Vector2(float(sh[3]), float(sh[4])) * k
		var left: float = float(sh[5])
		if int(sh[0]) == my_team:
			hud.draw_line(p - Vector2(3, 3), p + Vector2(3, 3), Color(1, 0.85, 0.3), 1.5)
			hud.draw_line(p - Vector2(3, -3), p + Vector2(3, -3), Color(1, 0.85, 0.3), 1.5)
		elif left < 2.2:
			hud.draw_circle(p, maxf(4.0, float(md.get("spl", 2.6)) * k * 1.5), Color(1, 0.1, 0.05, 0.25 + 0.35 * pulse))
			hud.draw_arc(p, maxf(4.0, float(md.get("spl", 2.6)) * k * 1.5), 0, TAU, 16, Color(1, 0.2, 0.1), 1.5)
