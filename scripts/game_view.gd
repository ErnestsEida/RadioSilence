extends Control
## One player's screen: low-res raycast view + weapon/cockpit overlay + crisp HUD with fog-of-war minimap.

const Defs = preload("res://scripts/defs.gd")
const Gfx = preload("res://scripts/gfx.gd")
const MapData = preload("res://scripts/map_data.gd")
const ViewModel = preload("res://scripts/viewmodel.gd")
const WeaponIcons = preload("res://scripts/weapon_icons.gd")
const VehicleView = preload("res://scripts/vehicle_view.gd")
const VModels = preload("res://scripts/vehicle_models.gd")
const MortarView = preload("res://scripts/mortar_view.gd")
const VehicleLayer = preload("res://scripts/vehicle_layer.gd")
const Atmos = preload("res://scripts/atmos.gd")
const VEH_SCALE := 2.4
const VEH_ZOFF := -0.1125   # the baked frames put the ground 6 px above the bottom edge
const MAX_SPRITES := 200
const SPRITE_RANGE := 34.0
const VISION := 22.0
const REVEAL := 10
const ARROWS := ["^", ">", "v", "<"]

var res: Dictionary
var lp
var mapdata
var svc: SubViewportContainer
var sv: SubViewport
var rect: ColorRect
var mat: ShaderMaterial
var wlayer: Control
var hud: Control
var me: Dictionary = {}
var snap: Dictionary = {}
var cam_pos := Vector2.ZERO
var cam_yaw := 0.0
var walk_t := 0.0
var time := 0.0
var font: Font
var spr_img: Image
var spr_tex: ImageTexture
var spr_buf := PackedFloat32Array()

var dead_since := {}
var hp_prev := {}
var flash_until := {}
var yaw_prev := 0.0
var sway := 0.0
var reload_t := 0.0
var switch_t := 0.0
var last_weapon := -1
var dead_t := 0.0
var last_hurt := 0.0
var step_phase := 0.0
var my_tank_moving := false
var my_vtype := 0
var spread := 0.0
var ads_t := 0.0
var sprint_t := 0.0
var eye := 0.6
var cam_pitch := 0.0
var last_vscale := 1.0
var bold: FontVariation
# camera of the last rendered frame, for projecting world points (name tags) onto the HUD
var pj_yaw := 0.0
var pj_plen := 1.0
var pj_vscale := 1.0
var pj_horizon := 0.5
var pj_eye := 0.6
var vv = null
var vv_type := -1
var vv_team := -1
var my_hull := 0.0
var hull_prev := 0.0
var steer_s := 0.0
var frame_dt := 0.016
var indoor_k := 0.0
var vm = null
var vlayer = null   # vehicle_layer.gd: real 3D vehicles composited by depth (null = baked sprite fallback)
# ambient life: birds circling overhead, smoke and flames from emitters
const SWAY := [Defs.FR_TREE, Defs.FR_PINE, Defs.FR_BUSH, Defs.FR_GRASS, Defs.FR_SNOWBUSH, Defs.FR_DRYBUSH, Defs.FR_REEDS, Defs.FR_FLOWERS, Defs.FR_DEADTREE]
var birds: Array = []      # {c: Vector2 centre, r, w (speed), ph, z}
var puffs: Array = []      # {p: Vector2, z, t, life, k}
var emit_t := 0.0
var trees: Array = []
var storm_k := 0.0
var lightning := 0.0
var thunder_t := 3.0
var flare_t := 0.0
var whistle_cd := 0.0

var fog_data := PackedByteArray()
var fog_tex: ImageTexture
var fog_t := 0.0
var spotted := {}
var spot_t := 0.0
var mview = null   # top-down mortar view (mortar_view.gd), shown instead of the raycaster while manning
var atm: Dictionary = {}          # weather x time-of-day look (atmos.gd)
var dyn_lights: Array = []        # this frame's lights: [dist2, Vector4(x, y, z, radius), Vector4(r, g, b, spot cos), Vector2 dir]
var ground_marks: Array = []      # Vector4(x, y, radius, intensity) set by set_ground_marks()
var own_marks: Array = []         # from the air strike event (bombs about to land)
var flash_seed := 0.0
var thunder_snd := -1.0
var lamp_k := 0.0                 # lamp posts lit (dusk / night / bad weather)
var fx_test := ""                 # debug screenshots: --fxtest=marks / --fxtest=lightning


func setup(p_res: Dictionary, p_lp, p_map, shrink: int) -> void:
	res = p_res
	lp = p_lp
	mapdata = p_map
	font = ThemeDB.fallback_font
	bold = FontVariation.new()
	bold.base_font = font
	bold.variation_embolden = 0.9
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc = SubViewportContainer.new()
	svc.stretch = true
	svc.stretch_shrink = shrink
	svc.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(svc)
	sv = SubViewport.new()
	sv.disable_3d = true
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	svc.add_child(sv)
	rect = ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mat = ShaderMaterial.new()
	mat.shader = res.shader
	rect.material = mat
	sv.add_child(rect)
	if DisplayServer.get_name() != "headless" and not OS.get_cmdline_user_args().has("--veh-sprites"):
		vlayer = VehicleLayer.new()
		sv.add_child(vlayer)   # a child viewport is rendered before the raycast pass that samples it
		mat.set_shader_parameter("veh3d_col", vlayer.get_texture())
		mat.set_shader_parameter("veh3d_depth", vlayer.depth_texture())
		mat.set_shader_parameter("veh3d_range", VehicleLayer.DEPTH_RANGE)
	wlayer = Control.new()
	wlayer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wlayer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sv.add_child(wlayer)
	wlayer.draw.connect(_draw_weapon)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	hud.draw.connect(_draw_hud)

	spr_buf.resize(MAX_SPRITES * 2 * 4)
	spr_img = Image.create_from_data(MAX_SPRITES, 2, false, Image.FORMAT_RGBAF, spr_buf.to_byte_array())
	spr_tex = ImageTexture.create_from_image(spr_img)
	mat.set_shader_parameter("map_tex", res.map_tex)
	mat.set_shader_parameter("wall_tex", res.wall_tex)
	mat.set_shader_parameter("sprite_tex", res.sprite_tex)
	mat.set_shader_parameter("spr_data", spr_tex)
	mapdata.apply_shader(mat)
	atm = Atmos.look(int(mapdata.weather), int(mapdata.tod), MapData.THEMES[mapdata.palette], mapdata.theme)
	Atmos.apply(mat, atm)
	lamp_k = 1.0 if bool(atm.heads) else 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fxtest="):
			fx_test = a.substr(9)
	if vlayer != null:
		vlayer.set_atmos(atm)
	if res.get("veh_tex") != null:
		mat.set_shader_parameter("veh_tex", res.veh_tex)
	var tcs := PackedVector3Array()
	for c in Defs.TEAM_COLORS:
		tcs.append(Vector3(c.r, c.g, c.b))
	mat.set_shader_parameter("team_cols", tcs)
	_init_birds()

	var n: int = mapdata.W * mapdata.H
	fog_data.resize(n * 2)
	for i in n:
		fog_data[i * 2] = 8
		fog_data[i * 2 + 1] = 235
	fog_tex = ImageTexture.create_from_image(Image.create_from_data(mapdata.W, mapdata.H, false, Image.FORMAT_LA8, fog_data))
	mview = MortarView.new()
	add_child(mview)
	mview.setup(self)


func _role() -> int:
	return int(me.get("role", Defs.ROLE_FOOT))


# ---------------------------------------------------------------- per frame

func render(p_snap: Dictionary, rec: Dictionary, effects: Array, dt: float) -> void:
	snap = p_snap
	me = rec
	time += dt
	frame_dt = dt
	svc.stretch_shrink = Settings.pixel
	if me.is_empty():
		wlayer.queue_redraw()
		hud.queue_redraw()
		return
	if MortarView.manning(me):
		cam_pos = Vector2(me.x, me.y)
		_update_fog(dt)
		mview.show_view(snap, me, effects, dt)
		return
	mview.hide_view()
	var role := _role()
	cam_pos = Vector2(me.x, me.y)
	if role == Defs.ROLE_FOOT or role == Defs.ROLE_SOLO or role == Defs.ROLE_GUNNER:
		cam_yaw = lp.yaw
	elif role == Defs.ROLE_DRIVER:
		cam_yaw = float(me.yaw) + float(lp.drv_look)   # free look while driving
	else:
		cam_yaw = me.yaw
	var yaw_vel := angle_difference(yaw_prev, cam_yaw) / maxf(dt, 0.001)
	yaw_prev = cam_yaw
	sway = lerpf(sway, clampf(-yaw_vel * 0.08, -1.0, 1.0), minf(1.0, dt * 8.0))
	var moving: bool = me.mv
	var sprinting: bool = me.sp
	var foot := role == Defs.ROLE_FOOT and me.pz == null
	if moving and role == Defs.ROLE_FOOT:
		walk_t += dt * (1.45 if sprinting else (0.6 if me.cr else 1.0))
		var ph := fmod(walk_t * 4.6 / PI, 1.0)
		if ph < step_phase and lp.view_index == 0 and not bool(me.get("air", false)):
			Sfx.play("step", -14.0 if sprinting else -17.0, randf_range(0.85, 1.15))
		step_phase = ph
	var weapon: int = me.w
	if last_weapon != weapon and role == Defs.ROLE_FOOT:
		if last_weapon >= 0:
			switch_t = 0.3
			Sfx.play("switch", -8.0)
		last_weapon = weapon
	switch_t = maxf(0.0, switch_t - dt)
	reload_t = reload_t + dt if me.rel else 0.0
	ads_t = move_toward(ads_t, 1.0 if (lp.ads and foot and not sprinting) else 0.0, dt * 6.0)
	sprint_t = move_toward(sprint_t, 1.0 if sprinting else 0.0, dt * 5.0)
	spread = lerpf(spread, (1.0 if moving else 0.0) + lp.kick + sprint_t * 2.0 - ads_t * 0.8, minf(1.0, dt * 10.0))
	var hurt: float = me.hurt
	if hurt > last_hurt + 0.2:
		lp.shake = maxf(lp.shake, 0.5)
	last_hurt = hurt
	lp.shake = maxf(0.0, lp.shake - dt * 2.5)
	dead_t = dead_t + dt if role == Defs.ROLE_DEAD else 0.0

	var foot_z := float(me.z)
	var target_eye := foot_z + (0.38 if me.cr else 0.62)
	if role == Defs.ROLE_SOLO or role == Defs.ROLE_DRIVER or role == Defs.ROLE_GUNNER:
		target_eye = [0.78, 0.72, 0.66, 0.74, 0.8][my_vtype]
	elif role == Defs.ROLE_DEAD:
		target_eye = lerpf(foot_z + 0.6, foot_z + 0.1, minf(dead_t / 0.6, 1.0))
	if absf(eye - target_eye) < 0.5:
		eye = lerpf(eye, target_eye, minf(1.0, dt * (9.0 if me.cr or absf(eye - target_eye) > 0.15 else 18.0)))
	else:
		eye = target_eye
	var pitch: float = lp.pitch if role != Defs.ROLE_DEAD and me.pz == null else 0.0
	cam_pitch = lerpf(cam_pitch, pitch, minf(1.0, dt * 30.0))

	var bob := 0.0
	if role == Defs.ROLE_FOOT and Settings.bob and not bool(me.get("air", false)):
		bob = sin(walk_t * 9.2) * (0.014 if sprinting else 0.009)
	elif my_tank_moving:
		bob = sin(time * 38.0) * 0.003
	var shake: float = lp.shake
	var yaw := cam_yaw + sin(time * 47.0) * shake * 0.02
	bob += cos(time * 53.0) * shake * 0.012

	var sz := Vector2(sv.size)
	var aspect := sz.x / maxf(1.0, sz.y)
	var zoom := lerpf(1.0, float(Defs.WPN[weapon].zoom), ads_t) if foot else 1.0
	var plen := tan(deg_to_rad(Settings.fov + sprint_t * 6.0) * 0.5) / zoom
	var vscale := aspect * 0.5 / plen
	last_vscale = vscale
	mat.set_shader_parameter("cam_pos", cam_pos)
	mat.set_shader_parameter("cam_angle", yaw)
	mat.set_shader_parameter("plen", plen)
	mat.set_shader_parameter("vscale", vscale)
	mat.set_shader_parameter("bob", bob)
	mat.set_shader_parameter("look", tan(cam_pitch) * vscale)
	pj_yaw = yaw
	pj_plen = plen
	pj_vscale = vscale
	pj_horizon = 0.5 + bob + tan(cam_pitch) * vscale
	pj_eye = eye
	mat.set_shader_parameter("time", time)
	mat.set_shader_parameter("eye", eye)
	mat.set_shader_parameter("hurt", hurt * 0.6)
	mat.set_shader_parameter("desat", minf(dead_t * 1.5, 0.8))
	var under_roof: bool = mapdata.has_roof(floori(cam_pos.x), floori(cam_pos.y)) and eye < MapData.CEIL
	indoor_k = move_toward(indoor_k, 1.0 if under_roof else 0.0, dt * 3.0)
	mat.set_shader_parameter("indoor", indoor_k)
	_update_ambient(dt)
	_event_fx(dt)
	if vlayer != null:
		vlayer.begin()
	_build_sprites(effects, plen)
	_upload_lights()
	if vlayer != null:
		mat.set_shader_parameter("veh3d_on", vlayer.finish(sv.size, cam_pos, yaw, plen, bob, tan(cam_pitch) * vscale, eye, time, dt))
	_update_fog(dt)
	wlayer.queue_redraw()
	hud.queue_redraw()


## Atlas column for a part pointing along `ang`, seen from the camera (0 = nose towards us, +90 deg = nose to the left).
func _veh_angle(pos: Vector2, ang: float) -> int:
	var rel := wrapf(ang - (cam_pos - pos).angle(), 0.0, TAU)
	return int(round(rel / (TAU / 16.0))) % 16


## Baked 3D vehicle: a hull sprite plus a separately rotating turret sprite at its pivot.
func _add_vehicle(list: Array, wreck: bool, vt: int, pos: Vector2, hull: float, turret: float, team: int, id: int, firing: bool) -> void:
	vt = clampi(vt, 0, 4)
	var row: int = vt * 4 + (2 if wreck else 0)
	var flash := 0.0
	if id > 0 and float(flash_until.get(id, 0.0)) > time:
		flash = 0.5
	if firing:
		flash = maxf(flash, 0.3)
	var flags := 8.0 + (0.0 if wreck else float(team + 1) * 16.0)
	var d2 := cam_pos.distance_squared_to(pos)
	list.append([d2, pos.x, pos.y, float(row * 16 + _veh_angle(pos, hull)), VEH_SCALE, VEH_ZOFF, flags, flash, 0.0])
	var pv: Vector2 = VModels.TURRET_PIVOT[vt]
	var pp: Vector2 = pos + Vector2.from_angle(hull) * pv.x + Vector2.from_angle(hull + PI * 0.5) * pv.y
	var td := cam_pos.distance_squared_to(pp)
	# a turret sitting over the hull centre is drawn after the hull; one behind it is drawn first
	td = minf(td, d2 - 0.001) if td <= d2 + 0.05 else td
	list.append([td, pp.x, pp.y, float((row + 1) * 16 + _veh_angle(pp, hull if wreck else turret)), VEH_SCALE, VEH_ZOFF, flags, flash, 0.0])


func _evt() -> Dictionary:
	var ev = snap.get("evt", {})
	return ev if ev is Dictionary else {}


func _evt_on(k: int) -> bool:
	var ev := _evt()
	return not ev.is_empty() and int(ev.k) == k and float(ev.get("warn", 0.0)) <= 0.0


## Storm visibility, rain/blizzard intensity and lightning; smoke flare over a supply drop.
func _event_fx(dt: float) -> void:
	storm_k = move_toward(storm_k, 1.0 if _evt_on(Defs.EVT_STORM) else 0.0, dt * 0.35)
	var th: Array = MapData.THEMES[mapdata.palette]
	# match weather / time of day (atmos.gd) with the storm event layered on top
	var fc: Color = atm.fog_col
	if mapdata.theme != 1:
		fc = fc.darkened(0.4 * storm_k)
	mat.set_shader_parameter("fog_col", Vector3(fc.r, fc.g, fc.b))
	mat.set_shader_parameter("fog_dist", float(th[9]) * float(atm.fog_k) * lerpf(1.0, 0.45 if float(atm.fog_k) < 0.6 else 0.32, storm_k))
	var wt: int = atm.particles
	if storm_k > 0.3 and (wt == 0 or (wt == -1 and mapdata.theme == 0)):
		wt = 4   # rain
	elif storm_k > 0.3 and wt == -1:
		wt = mapdata.theme
	mat.set_shader_parameter("weather", wt)
	mat.set_shader_parameter("weather_amt", maxf(float(atm.particle_amt), 1.0 + storm_k * 3.5))
	lightning = maxf(0.0, lightning - dt * 2.6)
	var stormy: bool = bool(atm.lightning) or (storm_k > 0.6 and (mapdata.theme == 0 or mapdata.theme == 3))
	if stormy:
		thunder_t -= dt
		if thunder_t <= 0.0:
			thunder_t = randf_range(4.0, 13.0)
			lightning = 1.0
			flash_seed = randf() * 100.0
			thunder_snd = randf_range(0.15, 1.6)   # thunder follows the flash
		if flash_seed > 0.0 and lightning < 0.55 and lightning > 0.5 and randf() < 0.5:
			lightning = 0.9   # a second stroke
			flash_seed = -1.0
	if thunder_snd > 0.0:
		thunder_snd -= dt
		if thunder_snd <= 0.0 and lp.view_index == 0:
			Sfx.play("thunder", -4.0, randf_range(0.6, 1.0))
	if fx_test == "lightning":
		lightning = 0.8
	var flick := 0.55 + 0.45 * sin(time * 47.0 + absf(flash_seed)) * sin(time * 23.0)
	if fx_test == "lightning":
		flick = 1.0
	# the first-person weapon / cockpit layer takes the scene light too
	var am: Vector3 = atm.ambient
	var wl := Color(am.x, am.y, am.z).lerp(Color.WHITE, lerpf(0.3, 1.0, indoor_k)) + Color(0.6, 0.6, 0.7) * lightning * flick
	if lp.kick > 0.8:
		wl = wl.lerp(Color.WHITE, 0.5)
	wlayer.modulate = Color(minf(wl.r, 1.0), minf(wl.g, 1.0), minf(wl.b, 1.0), 1.0)
	mat.set_shader_parameter("lightning", lightning * flick)
	var ev := _evt()
	if not ev.is_empty() and int(ev.k) == Defs.EVT_SUPPLY and puffs.size() < 240:
		flare_t -= dt
		if flare_t <= 0.0:
			flare_t = 0.15
			var fp := Vector2(ev.x, ev.y)
			if fp.distance_squared_to(cam_pos) < 1600.0:
				puffs.append({"p": fp + Vector2(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1)), "z": 0.1, "t": 0.0, "life": randf_range(3.0, 4.5), "k": 0})


## Ground warning marks for the raycast view (red pulsing ring + fill on floors and block tops).
## marks: Array of Vector4(x, y, radius, intensity 0..1), at most 16 (shared with the air strike marks).
## Kept until replaced: call it every frame while impacts are incoming, pass [] to clear.
func set_ground_marks(marks: Array) -> void:
	ground_marks = marks.duplicate()


func _flicker(seed_v: float) -> float:
	return 0.78 + 0.14 * sin(time * 13.0 + seed_v * 1.7) + 0.08 * sin(time * 31.0 + seed_v * 5.3)


func _add_light(p: Vector2, z: float, radius: float, c: Color, energy: float, spot_cos := 0.0, sdir := Vector2.ZERO) -> void:
	var d2 := cam_pos.distance_squared_to(p)
	var reach := radius + float(atm.get("fog_k", 1.0)) * 34.0
	if d2 > reach * reach:
		return
	dyn_lights.append([d2, Vector4(p.x, p.y, z, radius), Vector4(c.r * energy, c.g * energy, c.b * energy, spot_cos), sdir])


## Headlight cone in front of a vehicle plus a small glow on its nose.
func _add_headlights(pos: Vector2, hull: float, vt: int) -> void:
	var f := Vector2.from_angle(hull)
	var nose := pos + f * (1.15 if (vt == 0 or vt == 4) else 1.0)
	_add_light(nose, 0.55, 14.0, Color(1.0, 0.93, 0.76), 2.6, 0.87, f)
	_add_light(nose + f * 0.4, 0.5, 2.2, Color(1.0, 0.93, 0.76), 0.9)


## Fires, lamp posts and the air strike warning marks; uploads all dynamic lights to the shader.
func _upload_lights() -> void:
	for em in mapdata.emitters:
		if int(em[3]) == 1:
			var ep := Vector2(em[0], em[1])
			_add_light(ep, float(em[2]) + 0.35, 5.5, Color(1.0, 0.55, 0.2), 1.7 * _flicker(ep.x + ep.y * 3.0))
	if lamp_k > 0.0:
		var storm: bool = bool(atm.lightning) or storm_k > 0.6
		for l in mapdata.lamps:
			var lpos := Vector2(l[0], l[1])
			var e := 1.5
			if storm:
				# storm-battered lamps: flicker and the odd drop-out
				var ph := lpos.x * 0.37 + lpos.y * 0.71
				e *= 0.75 + 0.25 * sin(time * 19.0 + ph)
				if sin(time * 1.3 + ph * 4.0) > 0.93:
					e *= 0.15
			_add_light(lpos, float(l[2]), 8.5, Color(1.0, 0.86, 0.6), e)
	if lp.kick > 0.8 and _role() == Defs.ROLE_FOOT and int(me.w) != Defs.W_KNIFE:
		_add_light(cam_pos + Vector2.from_angle(cam_yaw) * 0.6, eye, 4.5, Color(1.0, 0.75, 0.4), 1.4)
	dyn_lights.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var n := mini(dyn_lights.size(), Atmos.MAX_LIGHTS)
	var lpos4 := PackedVector4Array()
	var lcol4 := PackedVector4Array()
	var ldir := PackedVector2Array()
	lpos4.resize(Atmos.MAX_LIGHTS)
	lcol4.resize(Atmos.MAX_LIGHTS)
	ldir.resize(Atmos.MAX_LIGHTS)
	for i in n:
		var L: Array = dyn_lights[i]
		lpos4[i] = L[1]
		lcol4[i] = L[2]
		ldir[i] = L[3]
	mat.set_shader_parameter("light_count", n)
	mat.set_shader_parameter("lights", lpos4)
	mat.set_shader_parameter("light_cols", lcol4)
	mat.set_shader_parameter("light_dirs", ldir)
	# warning marks: the lead dev's set_ground_marks() + air strike bombs landing within 0.5 s
	own_marks.clear()
	if fx_test == "marks":
		var mp := cam_pos + Vector2.from_angle(cam_yaw) * 6.0
		own_marks.append(Vector4(mp.x, mp.y, 2.5, 1.0))
	var ev := _evt()
	if not ev.is_empty():
		var now: float = snap.get("t", 0.0)
		for bm in ev.get("bombs", []):
			var left: float = float(bm[2]) - now
			if left < 0.5 and left > -0.05:
				own_marks.append(Vector4(float(bm[0]), float(bm[1]), 2.5, clampf(1.0 - left, 0.5, 1.0)))
	# mortar shells: their exact impact spot glows red 0.5 s before they land (everyone sees it)
	var msnap: Dictionary = snap.get("mortar", {})
	for sh in msnap.get("s", []):
		var sa: Array = sh
		if sa.size() > 8 and float(sa[5]) < 0.5:
			own_marks.append(Vector4(float(sa[7]), float(sa[8]), float(msnap.get("spl", 2.6)), clampf(1.0 - float(sa[5]), 0.5, 1.0)))
	var mk := PackedVector4Array()
	mk.resize(Atmos.MAX_MARKS)
	var m := 0
	for src in [ground_marks, own_marks]:
		for v in src:
			if m < Atmos.MAX_MARKS and v is Vector4:
				mk[m] = v
				m += 1
	mat.set_shader_parameter("mark_count", m)
	mat.set_shader_parameter("marks", mk)


func _init_birds() -> void:
	birds.clear()
	var r := RandomNumberGenerator.new()
	r.seed = 4242 + mapdata.map_index
	for i in (10 if mapdata.theme != 3 else 6):
		var c := Vector2(r.randf_range(12.0, mapdata.W - 12.0), r.randf_range(12.0, mapdata.H - 12.0))
		var w := r.randf_range(0.12, 0.25) * (1.0 if r.randf() < 0.5 else -1.0)
		var rad := r.randf_range(4.0, 9.0)
		var z := r.randf_range(4.0, 5.8)
		var ph := r.randf() * TAU
		for k in r.randi_range(2, 5):
			birds.append({"c": c, "r": rad + r.randf_range(-0.8, 0.8), "w": w, "ph": ph + k * 0.12, "z": z + r.randf_range(-0.4, 0.4)})
	trees.clear()
	for d in mapdata.decor:
		if int(d[2]) == Defs.FR_TREE:
			trees.append(Vector2(d[0], d[1]))


## Smoke columns from chimneys and burning wrecks, sparks over fires, leaves drifting down from trees.
func _update_ambient(dt: float) -> void:
	var wind := Vector2(0.35, 0.12)
	var keep: Array = []
	for pf in puffs:
		pf.t += dt
		if float(pf.t) >= float(pf.life):
			continue
		var k: int = pf.k
		if k == 0:
			pf.z += dt * 0.55
			pf.p += wind * dt * (0.5 + float(pf.t) * 0.3)
		elif k == 1:
			pf.z += dt * 1.3
			pf.p += Vector2(sin(float(pf.t) * 7.0 + float(pf.life) * 13.0), cos(float(pf.t) * 5.0)) * dt * 0.3
		else:
			pf.z = maxf(0.02, float(pf.z) - dt * 0.35)
			pf.p += Vector2(sin(float(pf.t) * 2.2 + float(pf.life) * 9.0) * 0.5, 0.15) * dt
		keep.append(pf)
	puffs = keep
	emit_t -= dt
	if emit_t > 0.0 or puffs.size() > 240:
		return
	emit_t = 0.12
	for e in mapdata.emitters:
		var ep := Vector2(e[0], e[1])
		if ep.distance_squared_to(cam_pos) > 900.0:
			continue
		if int(e[3]) == 0:
			if randf() < 0.45:
				puffs.append({"p": ep + Vector2(randf_range(-0.12, 0.12), randf_range(-0.12, 0.12)), "z": float(e[2]), "t": 0.0, "life": randf_range(2.5, 4.0), "k": 0})
		else:
			puffs.append({"p": ep + Vector2(randf_range(-0.15, 0.15), randf_range(-0.15, 0.15)), "z": float(e[2]) + 0.1, "t": 0.0, "life": randf_range(0.5, 0.9), "k": 1})
			if randf() < 0.3:
				puffs.append({"p": ep, "z": float(e[2]) + 0.25, "t": 0.0, "life": randf_range(2.0, 3.0), "k": 0})
	if trees.size() > 0 and randf() < 0.6:
		var tp: Vector2 = trees[randi() % trees.size()]
		for i in 6:
			if tp.distance_squared_to(cam_pos) < 196.0:
				break
			tp = trees[randi() % trees.size()]
		if tp.distance_squared_to(cam_pos) < 196.0:
			puffs.append({"p": tp + Vector2(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5)), "z": randf_range(0.9, 1.4), "t": 0.0, "life": 4.0, "k": 2})


func _facing(ang: float, pos: Vector2, right: Vector2) -> Vector2i:
	var to_cam := (cam_pos - pos).angle()
	var d := absf(angle_difference(ang, to_cam))
	if d < PI * 0.25:
		return Vector2i(0, 0)
	if d > PI * 0.75:
		return Vector2i(2, 0)
	return Vector2i(1, 0 if Vector2.from_angle(ang).dot(right) > 0.0 else 1)


func _visible(pos: Vector2, dir: Vector2, cosmax: float, margin: float) -> bool:
	var rel := pos - cam_pos
	var d := rel.length()
	if d > SPRITE_RANGE:
		return false
	if d < margin + 0.5:
		return true
	return rel.dot(dir) / d > cosmax - margin / d


func _team_state(team: int) -> Dictionary:
	var ts: Dictionary = snap.get("teams", {})
	return ts.get(team, {})


## Game mode of the match (Defs.MODE_*).
func _gmode() -> int:
	return clampi(int(snap.get("mode", 0)), 0, Defs.MODE_NAMES.size() - 1)


## CTF flag of a team from the snapshot: [team, x, y, state, carrier pid, return timer] (empty if none).
func _flag_info(team: int) -> Array:
	for f in snap.get("flags", []):
		if int(f[0]) == team:
			return f
	return []


func _flag_carrier(team: int) -> int:
	var f := _flag_info(team)
	return int(f[4]) if f.size() > 4 and int(f[3]) == 1 else -1


## Game log (kill feed + messages): small lines on a dark strip, the local player's name in bold yellow.
func _draw_log(s: Vector2, fs: int) -> void:
	var t: float = snap.get("t", 0.0)
	var lfs := int(clampf(float(fs) * 0.62 * Settings.log_size, 9.0, 40.0))
	var my_name: String = str(me.get("name", ""))
	var y := s.y * 0.23
	for m in snap.get("msg", []):
		var age: float = t - float(m[1])
		if age >= 6.0:
			continue
		var a := clampf(6.0 - age, 0.0, 1.0)
		var text := str(m[0])
		# split into [segment, is_me] pieces
		var segs: Array = []
		var rest := text
		if my_name.length() >= 2:
			var i := rest.find(my_name)
			while i >= 0:
				if i > 0:
					segs.append([rest.substr(0, i), false])
				segs.append([my_name, true])
				rest = rest.substr(i + my_name.length())
				i = rest.find(my_name)
		if rest != "":
			segs.append([rest, false])
		var w := 0.0
		for sg in segs:
			w += (bold if sg[1] else font).get_string_size(str(sg[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
		var x := (s.x - w) * 0.5
		var mine: bool = segs.size() > 1 or (segs.size() == 1 and bool(segs[0][1]))
		hud.draw_rect(Rect2(x - 8, y - lfs - 1, w + 16, lfs + 7), Color(0.1, 0.08, 0.0, 0.55 * a) if mine else Color(0, 0, 0, 0.42 * a))
		for sg in segs:
			var f: Font = bold if sg[1] else font
			var col := Color(1.0, 0.86, 0.3, a) if sg[1] else Color(0.92, 0.92, 0.88, a)
			hud.draw_string(f, Vector2(x + 1, y + 1), str(sg[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, Color(0, 0, 0, a * 0.8))
			hud.draw_string(f, Vector2(x, y), str(sg[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, col)
			x += f.get_string_size(str(sg[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
		y += lfs + 8


## World point -> HUD pixel (z = height in world units). Returns (-1e9, ...) when behind the camera.
func _project(pos: Vector2, z: float, s: Vector2) -> Vector3:
	var dir := Vector2.from_angle(pj_yaw)
	var rightv := Vector2(-dir.y, dir.x)
	var rel := pos - cam_pos
	var dz := rel.dot(dir)
	if dz < 0.3:
		return Vector3(-1e9, -1e9, dz)
	var sx := rel.dot(rightv) / (pj_plen * dz)
	var sy := pj_horizon + (pj_eye - z) * pj_vscale / dz
	return Vector3((sx + 1.0) * 0.5 * s.x, sy * s.y, dz)


## Name + health bar above every living teammate on foot (seen through walls, fades with distance).
func _draw_nametags(s: Vector2, fs: int) -> void:
	var my_id: int = int(me.get("id", -1))
	var team: int = int(me.get("tm", -1))
	var tfs := int(clampf(float(fs) * 0.6, 9.0, 30.0))
	for row in snap.get("p", []):
		if int(row.id) == my_id or int(row.tm) != team or float(row.hp) <= 0.0 or float(row.get("rsp", 0.0)) > 0.0:
			continue
		var in_veh: bool = int(row.get("tank", -1)) >= 0
		var pos := Vector2(float(row.x), float(row.y))
		var d := cam_pos.distance_to(pos)
		if d > 70.0:
			continue
		var top: float = float(row.get("z", 0.0)) + (1.6 if in_veh else (0.62 if bool(row.get("cr", false)) else 0.9))
		var sp := _project(pos, top, s)
		if sp.x < -50.0 or sp.x > s.x + 50.0 or sp.y < -20.0 or sp.y > s.y:
			continue
		var a := clampf(1.4 - d / 60.0, 0.35, 1.0)
		var nm := str(row.name)
		var tw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
		var bw := clampf(tw, 40.0, 140.0)
		var tc: Color = Defs.TEAM_COLORS[team].lightened(0.45)
		var by := sp.y - 6.0
		hud.draw_string(font, Vector2(sp.x - tw * 0.5 + 1, by - 5), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(0, 0, 0, a * 0.85))
		hud.draw_string(font, Vector2(sp.x - tw * 0.5, by - 6), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(tc.r, tc.g, tc.b, a))
		var hp := clampf(float(row.hp) / 100.0, 0.0, 1.0)
		var br := Rect2(sp.x - bw * 0.5, by, bw, maxf(4.0, tfs * 0.32))
		hud.draw_rect(br.grow(1.0), Color(0, 0, 0, 0.7 * a))
		var hc := Color(0.3, 0.95, 0.35) if hp > 0.6 else (Color(1.0, 0.8, 0.2) if hp > 0.3 else Color(1.0, 0.25, 0.2))
		hud.draw_rect(Rect2(br.position, Vector2(bw * hp, br.size.y)), Color(hc.r, hc.g, hc.b, a))


## HEIST: one chip per stolen key the team holds (whose key it is + who carries it). Any teammate can use them.
func _draw_team_keys(pad: float, oy: float, fs: int, line: float, ts: Dictionary) -> float:
	var kl: Array = ts.get("kl", [])
	var kfs := fs - 5
	var own_txt := "own key: %s" % ("carried" if me.own_key else "lost / used")
	_txt(Vector2(pad, oy), "TEAM KEYS %d  -  shared  -  %s" % [kl.size(), own_txt], kfs, Color(1, 0.85, 0.4))
	oy += line - 4
	if kl.is_empty():
		return oy + 2
	var x := pad
	for k in kl:
		var kt: int = int(k[0])
		var holder: String = "you" if int(k[2]) == int(me.id) else _pname(int(k[2]))
		var bname: String = str(mapdata.bunker_names[int(k[1])]) if int(k[1]) >= 0 and int(k[1]) < mapdata.bunker_names.size() else "?"
		var label := "%s (%s)" % [bname, holder]
		var kc: Color = Defs.TEAM_COLORS[kt] if kt >= 0 and kt < Defs.TEAM_COLORS.size() else Color(0.8, 0.8, 0.75)
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, kfs - 1).x
		var r := Rect2(x, oy - kfs + 2, tw + kfs + 14, kfs + 6)
		hud.draw_rect(r, Color(0, 0, 0, 0.5))
		hud.draw_rect(r, kc, false, 2.0)
		# little key glyph
		var kc2 := kc.lightened(0.3)
		var cy := r.position.y + r.size.y * 0.5
		hud.draw_arc(Vector2(r.position.x + 7, cy), kfs * 0.22, 0, TAU, 12, kc2, 2.0)
		hud.draw_line(Vector2(r.position.x + 7 + kfs * 0.22, cy), Vector2(r.position.x + kfs + 4, cy), kc2, 2.0)
		_txt(Vector2(r.position.x + kfs + 8, oy + 1), label, kfs - 1, Color(1, 1, 1, 0.95))
		x += r.size.x + 6
	return oy + line


func _pname(pid: int) -> String:
	for row in snap.get("p", []):
		if int(row.id) == pid:
			return str(row.name)
	return "?"


func _build_sprites(effects: Array, plen: float) -> void:
	var list: Array = []
	var dir := Vector2.from_angle(cam_yaw)
	var cosmax := cos(atan(plen) + 0.05)
	var e: PackedFloat32Array = snap.get("e", PackedFloat32Array())
	var my_id: int = me.id
	var my_tank: int = me.tank
	var my_team: int = me.tm
	var right := Vector2.from_angle(cam_yaw + PI * 0.5)
	var anim := int(time * 6.0) % 2
	var bobz := 0.08 + sin(time * 3.0) * 0.05
	my_tank_moving = false
	dyn_lights.clear()
	var heads: bool = bool(atm.get("heads", false))
	for i in e.size() / 9:
		var o := i * 9
		var typ := int(e[o])
		var pos := Vector2(e[o + 1], e[o + 2])
		var ang: float = e[o + 3]
		var team := int(e[o + 4])
		var fl := int(e[o + 5])
		var hp: float = e[o + 6]
		var aux: float = e[o + 7]
		var id := int(e[o + 8])
		if typ == Defs.E_TANK and id == my_tank:
			my_tank_moving = (fl & 2) != 0
			my_vtype = (fl >> 8) & 15
			my_hull = ang
			if heads:
				_add_headlights(pos, ang, my_vtype)
			if fl & 1:
				_add_light(pos + Vector2.from_angle(cam_yaw) * 2.0, 0.8, 7.0, Color(1.0, 0.7, 0.35), 2.2)
			continue
		if typ == Defs.E_TANK:
			if heads:
				_add_headlights(pos, ang, (fl >> 8) & 15)
			if fl & 1:
				_add_light(pos + Vector2.from_angle(aux) * 2.0, 0.8, 7.0, Color(1.0, 0.7, 0.35), 2.0)
		elif (typ == Defs.E_SOLDIER or typ == Defs.E_PLAYER or typ == Defs.E_TURRET) and (fl & 1) and not (fl & 4) and id != my_id:
			_add_light(pos + Vector2.from_angle(ang) * 0.5, 0.65, 4.0, Color(1.0, 0.75, 0.4), 1.3 * randf_range(0.7, 1.0))
		elif typ == Defs.E_WRECK:
			_add_light(pos, 0.7, 4.5, Color(1.0, 0.5, 0.2), 0.8 * _flicker(float(id)))
		if (typ == Defs.E_TANK or typ == Defs.E_WRECK) and vlayer != null:
			if _visible(pos, dir, cosmax, 2.5):
				vlayer.push(id, typ == Defs.E_WRECK, (fl >> 8) & 15, pos, ang, aux, team, fl)
			continue
		if (typ == Defs.E_TANK or typ == Defs.E_WRECK) and res.get("veh_tex") != null:
			if _visible(pos, dir, cosmax, 1.8):
				_add_vehicle(list, typ == Defs.E_WRECK, (fl >> 8) & 15, pos, ang, aux, team, id, (fl & 1) != 0)
			continue
		if typ == Defs.E_SMOKE:
			continue
		if not _visible(pos, dir, cosmax, 1.5):
			continue
		var frame := -1
		var scale := 1.0
		var zoff := 0.0
		var mirror := 0.0
		var flash := 0.0
		if id > 0 and hp_prev.has(id) and hp < float(hp_prev[id]) - 0.001:
			flash_until[id] = time + 0.08
		if id > 0:
			hp_prev[id] = hp
		if id > 0 and float(flash_until.get(id, 0.0)) > time:
			flash = 0.6
		if typ == Defs.E_SOLDIER or typ == Defs.E_PLAYER:
			if typ == Defs.E_PLAYER and id == my_id:
				continue
			var base := (0 if typ == Defs.E_SOLDIER else team + 1) * 16
			scale = 0.9
			if typ == Defs.E_PLAYER:
				zoff = aux
			if fl & 4:
				if not dead_since.has(id):
					dead_since[id] = time
				frame = base + (Defs.SO_DYING if time - float(dead_since[id]) < 0.35 else Defs.SO_DEAD)
				flash = 0.0
			else:
				dead_since.erase(id)
				var f := _facing(ang, pos, right)
				mirror = float(f.y)
				if fl & 128 and not (fl & 16):
					frame = base + Defs.SO_JUMP
				elif fl & 16:
					frame = base + Defs.SO_CROUCH
				elif fl & 1:
					frame = base + (Defs.SO_SHOOT if f.x != 1 else Defs.SO_SHOOT_SIDE)
				else:
					var stp := 0
					if fl & 2:
						stp = 1 + int(fmod(time * 4.0 + id * 0.37, 2.0))
					frame = base + [Defs.SO_FRONT, Defs.SO_SIDE, Defs.SO_BACK][f.x] + stp
		elif typ == Defs.E_TANK:
			var f := _facing(ang, pos, right)
			var vt := (fl >> 8) & 15
			var fi: int = [0, 1 + (anim if fl & 2 else 0), 3][f.x]
			frame = (Defs.FR_TANK + team * 4 + fi) if vt == 0 else (Defs.FR_VEH + (vt - 1) * 16 + team * 4 + fi)
			mirror = float(f.y)
			scale = [1.3, 1.2, 0.95, 1.1, 1.3][vt]
			if fl & 1:
				flash = 0.4
		elif typ == Defs.E_WRECK:
			frame = Defs.FR_WRECK
			scale = 1.3
		elif typ == Defs.E_TURRET:
			frame = Defs.FR_TURRET_DEAD if fl & 4 else Defs.FR_TURRET
			scale = 1.05
			if fl & 1:
				flash = 0.5
		elif typ == Defs.E_SHELL:
			frame = Defs.FR_SHELL
			scale = 0.35
			zoff = aux - 0.17
		elif typ == Defs.E_KEY:
			frame = Defs.FR_KEY + team + 1
			scale = 0.55
			zoff = aux + bobz
			flash = 0.25 + 0.2 * sin(time * 6.0)
		elif typ == Defs.E_LOOT:
			frame = Defs.FR_LOOT + int(aux)
			scale = 0.75 if int(aux) == 4 else 0.5
			zoff = hp + (0.0 if int(aux) == 4 else bobz * 0.5)
		elif typ == Defs.E_GRENADE:
			frame = Defs.FR_SMOKE_GREN if fl & 1 else Defs.FR_GRENADE
			scale = 0.22
			zoff = aux
		elif typ == Defs.E_TERMINAL:
			var bi := int(aux) / 4
			var r := int(aux) % 4
			var bl: Array = snap.get("bunkers", [])
			var solved: bool = bi < bl.size() and bool(bl[bi].sol[r])
			frame = Defs.FR_TERMINAL + (2 if solved else r)
			scale = 0.9
		elif typ == Defs.E_BULLET:
			frame = Defs.FR_TRACER
			scale = 0.16 if aux < 50.0 else 0.11
			zoff = hp - scale * 0.5
			flash = 0.5
		elif typ == Defs.E_AMMO:
			frame = Defs.FR_AMMO
			scale = 0.75
		elif typ == Defs.E_DROP:
			frame = Defs.FR_DROP
			scale = 0.85
			flash = 0.15 + 0.15 * sin(time * 5.0)
		elif typ == Defs.E_FLAG:
			if fl == 1 and _flag_carrier(team) == int(me.get("id", -1)):
				continue   # the flag on my own back
			frame = Defs.FR_FLAG + clampi(team, 0, 4) * 2 + int(time * 5.0 + pos.x * 0.37) % 2
			scale = 0.8 if fl == 1 else 1.0
			zoff = aux + (0.45 if fl == 1 else 0.0)
			flash = 0.2 + 0.15 * sin(time * 6.0) if fl == 2 else 0.0
		if frame < 0:
			continue
		list.append([cam_pos.distance_squared_to(pos), pos.x, pos.y, frame, scale, zoff, mirror, flash, 0.0])
	for d in mapdata.decor:
		var p := Vector2(d[0], d[1])
		if _visible(p, dir, cosmax, 1.0):
			var fr: int = d[2]
			var fl := 0.0
			if fr in SWAY:
				fl = 2.0
			elif fr >= Defs.FR_FLAG and fr < Defs.FR_FLAG + 10:
				fr += int(time * 5.0 + p.x * 0.37) % 2
			elif fr == Defs.FR_FIRE:
				fr += int(time * 9.0 + p.y) % 2
				fl = 4.0
			elif fr == Atmos.FR_LAMP and lamp_k > 0.0:
				fl = 32.0
			list.append([cam_pos.distance_squared_to(p), p.x, p.y, fr, d[3], d[4], fl, 0.0, 0.0])
	var ev := _evt()
	if not ev.is_empty() and int(ev.k) == Defs.EVT_SUPPLY and not bool(ev.landed):
		# crate swinging under its parachute on the way down
		var cp := Vector2(ev.x, ev.y) + Vector2(sin(time * 1.3), cos(time * 1.1)) * 0.25 * clampf(float(ev.z), 0.0, 1.0)
		if _visible(cp, dir, cosmax, 2.0):
			var cz: float = ev.z
			list.append([cam_pos.distance_squared_to(cp), cp.x, cp.y, Defs.FR_DROP, 0.85, cz, 0.0, 0.0, 0.0])
			list.append([cam_pos.distance_squared_to(cp) - 0.01, cp.x, cp.y, Defs.FR_CHUTE, 2.2, cz + 0.6, 0.0, 0.0, 0.0])
	if not ev.is_empty() and int(ev.k) == Defs.EVT_ARTY:
		var now: float = snap.get("t", 0.0)
		for run in ev.get("runs", []):
			var ra := Vector2(run.ax, run.ay)
			var rb := Vector2(run.bx, run.by)
			var L := ra.distance_to(rb)
			var f: float = (now - float(run.t0)) * 16.0 / L
			if f < 0.0 or f > 1.0:
				continue
			# three bombers in a loose V formation
			var fdir := (rb - ra) / L
			var side := Vector2(-fdir.y, fdir.x)
			for w in 3:
				var pp: Vector2 = ra.lerp(rb, f) + side * float(w - 1) * 3.0 - fdir * absf(float(w - 1)) * 2.5
				if cam_pos.distance_squared_to(pp) < 3600.0:
					list.append([cam_pos.distance_squared_to(pp), pp.x, pp.y, Defs.FR_PLANE, 3.4, 5.2 + float(w) * 0.3, 0.0, 0.0, 0.0])
		# whistle for impacts landing close by
		whistle_cd -= frame_dt
		if lp.view_index == 0 and whistle_cd <= 0.0:
			for bm in ev.get("bombs", []):
				var left: float = float(bm[2]) - now
				if left > 0.9 and left < 1.05 and cam_pos.distance_to(Vector2(bm[0], bm[1])) < 16.0:
					Sfx.play("whistle", -4.0 - cam_pos.distance_to(Vector2(bm[0], bm[1])) * 0.5, randf_range(0.9, 1.15))
					whistle_cd = 0.3
					break
	for bd in birds:
		var a: float = time * float(bd.w) + float(bd.ph)
		var bp: Vector2 = bd.c + Vector2(cos(a), sin(a)) * float(bd.r)
		if _visible(bp, dir, cosmax, 1.0):
			var bz: float = float(bd.z) + sin(time * 0.7 + float(bd.ph)) * 0.4
			list.append([cam_pos.distance_squared_to(bp), bp.x, bp.y, Defs.FR_BIRD + int(time * 7.0 + float(bd.ph) * 3.0) % 2, 0.35, bz, 0.0, 0.0, 0.0])
	for pf in puffs:
		var pp: Vector2 = pf.p
		if not _visible(pp, dir, cosmax, 1.5):
			continue
		var f: float = float(pf.t) / float(pf.life)
		if int(pf.k) == 0:
			list.append([cam_pos.distance_squared_to(pp), pp.x, pp.y, Defs.FR_SMOKE, lerpf(0.5, 1.6, f), float(pf.z) - 0.3, 0.0, 0.0, 0.55 * (1.0 - f)])
		else:
			list.append([cam_pos.distance_squared_to(pp), pp.x, pp.y, Defs.FR_LEAF if int(pf.k) == 2 else Defs.FR_PUFF, 0.12 if int(pf.k) == 2 else 0.2, float(pf.z), 4.0, 0.0, 0.0 if int(pf.k) == 2 else 0.8 * (1.0 - f)])
	for fx in effects:
		var age: float = fx.t
		var f: float = age / float(fx.life)
		var p: Vector2 = fx.p
		var k: int = fx.k
		if (k == 1 or k == 2) and p.distance_to(cam_pos) < 0.8:
			continue
		var frame := Defs.FR_PUFF
		var scale := 0.35
		var zoff := 0.3
		var alpha := 0.0
		var fz: float = float(fx.get("z", -1.0))
		if k == 0:
			frame = Defs.FR_EXPL + mini(2, int(age / 0.15))
			scale = 1.7
			zoff = -0.2 if fz < 0.0 else fz - 0.5
		elif k == 1:
			alpha = 0.9 * (1.0 - f)
			if fz >= 0.0:
				zoff = fz - 0.17
		elif k == 2:
			frame = Defs.FR_BLOOD
			scale = 0.3
			if fz >= 0.0:
				zoff = fz - 0.15
		elif k == 3:
			p = p.lerp(fx.p2, f)
			frame = Defs.FR_TRACER
			scale = 0.13
			zoff = 0.42
		elif k == 4:
			frame = Defs.FR_SMOKE
			scale = lerpf(0.7, 1.7, f)
			zoff = lerpf(-0.1, 0.8, f)
			alpha = 0.75 * (1.0 - f)
		elif k == 5:
			frame = Defs.FR_DUST
			scale = lerpf(0.5, 1.0, f)
			zoff = -0.1
			alpha = 0.55 * (1.0 - f)
		elif k == 6:
			frame = Defs.FR_SMOKE
			scale = lerpf(1.6, 2.4, f)
			zoff = lerpf(-0.6, -0.2, f)
			alpha = 0.92 * minf(1.0, (1.0 - f) * 3.0)
		if k == 0 and age < 0.5:
			_add_light(p, 0.8, 9.0, Color(1.0, 0.62, 0.3), 3.2 * (1.0 - age / 0.5))
		if not _visible(p, dir, cosmax, 1.5):
			continue
		list.append([cam_pos.distance_squared_to(p), p.x, p.y, frame, scale, zoff, 4.0 if k == 0 else 0.0, 0.0, alpha])
	list.sort_custom(func(a, b): return a[0] > b[0])
	if list.size() > MAX_SPRITES:
		list = list.slice(list.size() - MAX_SPRITES)
	var cnt := list.size()
	var row := MAX_SPRITES * 4
	for i in cnt:
		var s: Array = list[i]
		var o := i * 4
		spr_buf[o] = s[1]
		spr_buf[o + 1] = s[2]
		spr_buf[o + 2] = s[3]
		spr_buf[o + 3] = s[4]
		spr_buf[row + o] = s[5]
		spr_buf[row + o + 1] = s[6]
		spr_buf[row + o + 2] = s[7]
		spr_buf[row + o + 3] = s[8]
	spr_img.set_data(MAX_SPRITES, 2, false, Image.FORMAT_RGBAF, spr_buf.to_byte_array())
	spr_tex.update(spr_img)
	mat.set_shader_parameter("sprite_count", cnt)


# ---------------------------------------------------------------- fog of war

func _team_eyes() -> Array:
	var eyes: Array = [cam_pos]
	for r in snap.get("p", []):
		if int(r.tm) == int(me.tm) and int(r.id) != int(me.id) and int(r.role) != Defs.ROLE_DEAD:
			eyes.append(Vector2(r.x, r.y))
	return eyes


func _update_fog(dt: float) -> void:
	fog_t -= dt
	spot_t -= dt
	var eyes := _team_eyes()
	if fog_t <= 0.0:
		fog_t = 0.2
		var changed := false
		var W: int = mapdata.W
		for eyep in eyes:
			var cx := int(eyep.x)
			var cy := int(eyep.y)
			for y in range(maxi(0, cy - REVEAL), mini(mapdata.H, cy + REVEAL + 1)):
				for x in range(maxi(0, cx - REVEAL), mini(W, cx + REVEAL + 1)):
					var i := (y * W + x) * 2 + 1
					if fog_data[i] != 0 and (x - cx) * (x - cx) + (y - cy) * (y - cy) <= REVEAL * REVEAL:
						fog_data[i] = 0
						changed = true
		if changed:
			fog_tex.update(Image.create_from_data(mapdata.W, mapdata.H, false, Image.FORMAT_LA8, fog_data))
	if spot_t <= 0.0:
		spot_t = 0.2
		spotted.clear()
		var team: int = me.tm
		var e: PackedFloat32Array = snap.get("e", PackedFloat32Array())
		for i in e.size() / 9:
			var o := i * 9
			var typ := int(e[o])
			if typ != Defs.E_SOLDIER and typ != Defs.E_TURRET and typ != Defs.E_PLAYER and typ != Defs.E_TANK and typ != Defs.E_KEY:
				continue
			if typ != Defs.E_KEY and (int(e[o + 4]) == team or (int(e[o + 5]) & 4)):
				continue
			var pos := Vector2(e[o + 1], e[o + 2])
			for eyep in eyes:
				if eyep.distance_to(pos) < VISION and mapdata.los(eyep, pos):
					spotted[int(e[o + 8])] = true
					break


# ---------------------------------------------------------------- low-res overlay (weapon / cockpit)

func _draw_weapon() -> void:
	if me.is_empty():
		return
	var role := _role()
	var s := wlayer.size
	if role == Defs.ROLE_FOOT:
		if vv != null:
			vv.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if me.pz != null:
			return
		_draw_vm(s)
	elif role != Defs.ROLE_DEAD:
		if vv != null:
			vv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_draw_cockpit(s, role)


## 3D first-person weapon (scripts/viewmodel.gd) rendered in its own SubViewport and drawn over the view.
func _draw_vm(s: Vector2) -> void:
	if vm == null:
		vm = ViewModel.new()
		add_child(vm)
		vm.setup(Defs.TEAM_COLORS[int(me.tm)])
	vm.size = Vector2i(maxi(16, int(s.x)), maxi(16, int(s.y)))
	var weapon: int = me.w
	var dur: float = maxf(0.1, float(Defs.WPN[weapon].reload))
	vm.update_pose(weapon, {
		"time": time,
		"bob_x": sin(walk_t * 4.6) * (1.0 if Settings.bob else 0.3),
		"bob_y": absf(cos(walk_t * 4.6)) * (1.0 if Settings.bob else 0.3),
		"sway": sway,
		"kick": float(lp.kick),
		"reload": clampf(reload_t / dur, 0.0, 1.0) if reload_t > 0.0 else 0.0,
		"switch": switch_t / 0.3,
		"sprint": sprint_t,
		"ads": ads_t,
		"throw": (1.0 - float(lp.throw_t) / 0.5) if lp.throw_t > 0.0 else 0.0,
		"flash": float(lp.kick) > 0.8 and weapon != Defs.W_KNIFE,
		"crouch": 1.0 if me.cr else 0.0,
		"empty": int(me.mag) <= 0,
	})
	wlayer.draw_texture_rect(vm.get_texture(), Rect2(Vector2.ZERO, s), false)


func _draw_gun(s: Vector2) -> void:
	var weapon: int = me.w
	var vm: Dictionary = res.vm[weapon]
	var tex: Texture2D = vm.tex
	var muzzle: Vector2 = vm.muzzle
	var h := s.y * 0.6
	var sc := h / 160.0
	var u := s.y / 100.0
	var rest := Vector2(s.x * 0.56, s.y * 0.58)
	if weapon == Defs.W_PISTOL or weapon == Defs.W_REVOLVER:
		rest = Vector2(s.x * 0.56, s.y * 0.66)
	elif weapon == Defs.W_KNIFE:
		rest = Vector2(s.x * 0.62, s.y * 0.66)
	var aim := Vector2(s.x * 0.5, s.y * 0.53)
	var mpos := rest.lerp(aim, ads_t * 0.85)
	var k: float = lp.kick
	var amt := (1.0 if Settings.bob else 0.3) * (1.0 - ads_t * 0.8)
	var off := Vector2(sin(walk_t * 4.6) * 5.0 * u * amt, absf(cos(walk_t * 4.6)) * 4.0 * u * amt)
	off.y += sin(time * 1.7) * 0.8 * u * (1.0 - ads_t)
	off.x += sway * 12.0 * u
	off.y += absf(sway) * 3.0 * u
	var ang := sway * 0.04
	if weapon == Defs.W_KNIFE:
		off += Vector2(-k * 26.0 * u, -k * 14.0 * u)
		ang -= k * 0.7
	else:
		off.y += k * (9.0 if weapon == Defs.W_SHOTGUN or weapon == Defs.W_SNIPER else 5.0) * u
		ang -= k * 0.05
	if reload_t > 0.0:
		var dur: float = Defs.WPN[weapon].reload
		var r := sin(PI * clampf(reload_t / maxf(dur, 0.1), 0.0, 1.0))
		ang += 0.6 * r
		off.y += h * 0.32 * r
	off.y += h * 0.9 * (switch_t / 0.3)
	off += Vector2(h * 0.12, h * 0.22) * sprint_t
	ang += 0.5 * sprint_t
	if lp.throw_t > 0.0:
		off.y += h * 0.6 * sin(PI * clampf(lp.throw_t / 0.5, 0.0, 1.0))
	var pivot_local := Vector2(150, 160)
	var base := Vector2(mpos.x - muzzle.x * sc, s.y + h * 0.02 - h + (mpos.y - rest.y)) + off
	var pivot := base + pivot_local * sc
	wlayer.draw_set_transform(pivot, ang, Vector2(sc, sc))
	var team: int = me.tm
	var sleeve: Color = Defs.TEAM_COLORS[team].darkened(0.35)
	for sl in vm.sleeves:
		var pts := PackedVector2Array()
		for q in sl:
			var qq: Vector2 = q
			if qq.y >= 159.0:
				qq.y += 140.0   # sleeves continue off the bottom of the screen
			pts.append(qq - pivot_local)
		wlayer.draw_colored_polygon(pts, sleeve)
		wlayer.draw_polyline(pts, sleeve.darkened(0.5), 1.5)
	wlayer.draw_texture(tex, -pivot_local)
	if k > 0.55 and weapon != Defs.W_KNIFE and reload_t <= 0.0:
		var m: Vector2 = muzzle - pivot_local
		var r := 11.0 if weapon != Defs.W_SHOTGUN else 16.0
		var pts := PackedVector2Array()
		for i in 12:
			var a := float(i) / 12.0 * TAU + time * 9.0
			pts.append(m + Vector2(cos(a), sin(a) * 0.8) * (r if i % 2 == 0 else r * 0.4))
		wlayer.draw_colored_polygon(pts, Color(1.0, 0.75, 0.2))
		wlayer.draw_circle(m, r * 0.35, Color(1, 1, 0.85))
	wlayer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_throw(s: Vector2) -> void:
	var f := clampf(1.0 - lp.throw_t / 0.5, 0.0, 1.0)
	var p := Vector2(s.x * 0.78, s.y * 1.05).lerp(Vector2(s.x * 0.58, s.y * 0.62), sin(PI * f * 0.5))
	var r := s.y * 0.045
	var team: int = me.tm
	wlayer.draw_colored_polygon(PackedVector2Array([p + Vector2(r * 0.8, r), p + Vector2(r * 2.4, s.y), p + Vector2(-r * 1.0, s.y), p + Vector2(-r * 0.8, r)]), Defs.TEAM_COLORS[team].darkened(0.35))
	wlayer.draw_circle(p, r * 1.2, Color(0.86, 0.67, 0.52))
	if f < 0.8:
		wlayer.draw_circle(p + Vector2(0, -r * 0.9), r * 0.8, Color(0.45, 0.47, 0.5) if int(me.eqt) == Defs.EQ_SMOKE else Color(0.3, 0.36, 0.22))


func _poly(pts: Array, c: Color) -> void:
	wlayer.draw_colored_polygon(PackedVector2Array(pts), c)


func _draw_cockpit(s: Vector2, role: int) -> void:
	# 3D first-person vehicle (scripts/vehicle_view.gd), same models as the world sprites
	if vv == null or vv_type != my_vtype or vv_team != int(me.tm):
		if vv != null:
			vv.queue_free()
		vv = VehicleView.new()
		add_child(vv)
		vv.setup(my_vtype, Defs.TEAM_COLORS[int(me.tm)])
		vv_type = my_vtype
		vv_team = int(me.tm)
	vv.size = Vector2i(maxi(16, int(s.x)), maxi(16, int(s.y)))
	var rel := 0.0 if role == Defs.ROLE_DRIVER else angle_difference(my_hull, cam_yaw)
	var hull_rate := angle_difference(hull_prev, my_hull) / maxf(0.001, frame_dt)
	hull_prev = my_hull
	steer_s = lerpf(steer_s, clampf(hull_rate / 2.0, -1.0, 1.0), 0.15)
	var ccd: float = me.ccd
	vv.update_pose(role, {
		"turret_rel": rel,
		"hfov": float(Settings.fov),
		"time": time,
		"speed": 1.0 if my_tank_moving else 0.0,
		"steer": steer_s,
		"kick": maxf(float(lp.kick), clampf((ccd - 0.85) * 6.0, 0.0, 1.0) if role != Defs.ROLE_DRIVER else 0.0),
		"eye": eye,
		"look": float(lp.drv_look) if role == Defs.ROLE_DRIVER else 0.0,
		"pitch": cam_pitch,
	})
	# the world view is y-sheared by the pitch, so shift the cockpit the same way
	var shear: float = tan(cam_pitch) * last_vscale * s.y
	wlayer.draw_texture_rect(vv.get_texture(), Rect2(Vector2(0.0, shear), s), false)


func _draw_cockpit_2d(s: Vector2, role: int) -> void:
	var shake := Vector2.ZERO
	var ccd: float = me.ccd
	if ccd > 0.88 and role != Defs.ROLE_DRIVER:
		shake = Vector2(randf_range(-3, 3), randf_range(-3, 3))
	if my_tank_moving:
		shake.y += sin(time * 40.0) * 1.0
	var hullc := Color(0.15, 0.17, 0.13)
	var edge := Color(0.07, 0.08, 0.06)
	var tc: Color = Defs.TEAM_COLORS[int(me.tm)].darkened(0.5)
	if my_vtype == Defs.V_MOTO or my_vtype == Defs.V_JEEP:
		_draw_open_top(s, role, shake, tc)
		return
	_poly([Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, s.y * 0.1), Vector2(s.x * 0.85, s.y * 0.13), Vector2(s.x * 0.15, s.y * 0.13), Vector2(0, s.y * 0.1)], hullc)
	wlayer.draw_line(Vector2(s.x * 0.15, s.y * 0.13), Vector2(s.x * 0.85, s.y * 0.13), edge, 2)
	_poly([Vector2(0, 0), Vector2(s.x * 0.04, s.y * 0.1), Vector2(s.x * 0.04, s.y * 0.85), Vector2(0, s.y)], hullc)
	_poly([Vector2(s.x, 0), Vector2(s.x * 0.96, s.y * 0.1), Vector2(s.x * 0.96, s.y * 0.85), Vector2(s.x, s.y)], hullc)
	if role == Defs.ROLE_DRIVER:
		_poly([Vector2(0, s.y), Vector2(0, s.y * 0.8), Vector2(s.x * 0.22, s.y * 0.73) + shake, Vector2(s.x * 0.78, s.y * 0.73) + shake, Vector2(s.x, s.y * 0.8), Vector2(s.x, s.y)], tc)
		wlayer.draw_line(Vector2(s.x * 0.22, s.y * 0.73) + shake, Vector2(s.x * 0.78, s.y * 0.73) + shake, tc.lightened(0.3), 2)
		_poly([Vector2(0, s.y), Vector2(0, s.y * 0.86), Vector2(s.x, s.y * 0.86), Vector2(s.x, s.y)], hullc)
	else:
		var bw := s.x * 0.04
		_poly([Vector2(s.x * 0.5 - bw * 1.5, s.y) + shake, Vector2(s.x * 0.5 + bw * 1.5, s.y) + shake,
			Vector2(s.x * 0.5 + bw * 0.7, s.y * 0.78) + shake, Vector2(s.x * 0.5 - bw * 0.7, s.y * 0.78) + shake], Color(0.13, 0.14, 0.12))
		_poly([Vector2(0, s.y), Vector2(0, s.y * 0.9), Vector2(s.x, s.y * 0.9), Vector2(s.x, s.y)], hullc)
	for i in 14:
		wlayer.draw_rect(Rect2(s.x * (0.06 + i * 0.065), s.y * 0.04, 2, 2), Color(0.35, 0.38, 0.3))


## Motorcycle / jeep: no armour around you - handlebars or windshield, and a mounted MG for the gunner.
func _draw_open_top(s: Vector2, role: int, shake: Vector2, tc: Color) -> void:
	var metal := Color(0.16, 0.16, 0.17)
	var glove := Color(0.55, 0.45, 0.3)
	if role == Defs.ROLE_GUNNER or role == Defs.ROLE_SOLO:
		# pintle-mounted machine gun pointing into the screen
		var c := Vector2(s.x * 0.5, s.y) + shake
		_poly([c + Vector2(-s.x * 0.07, 0), c + Vector2(s.x * 0.07, 0), c + Vector2(s.x * 0.025, -s.y * 0.3), c + Vector2(-s.x * 0.025, -s.y * 0.3)], metal)
		_poly([c + Vector2(-s.x * 0.012, -s.y * 0.3), c + Vector2(s.x * 0.012, -s.y * 0.3), c + Vector2(s.x * 0.009, -s.y * 0.42), c + Vector2(-s.x * 0.009, -s.y * 0.42)], Color(0.1, 0.1, 0.1))
		_poly([c + Vector2(-s.x * 0.06, -s.y * 0.2), c + Vector2(-s.x * 0.035, -s.y * 0.2), c + Vector2(-s.x * 0.05, -s.y * 0.26), c + Vector2(-s.x * 0.065, -s.y * 0.26)], Color(0.6, 0.5, 0.15))
		wlayer.draw_circle(c + Vector2(-s.x * 0.12, -s.y * 0.04), s.y * 0.05, glove)
		wlayer.draw_circle(c + Vector2(s.x * 0.12, -s.y * 0.04), s.y * 0.05, glove)
		_poly([c + Vector2(-s.x * 0.25, s.y * 0.05), c + Vector2(-s.x * 0.15, -s.y * 0.06), c + Vector2(-s.x * 0.09, -s.y * 0.02), c + Vector2(-s.x * 0.17, s.y * 0.05)], tc)
		_poly([c + Vector2(s.x * 0.25, s.y * 0.05), c + Vector2(s.x * 0.15, -s.y * 0.06), c + Vector2(s.x * 0.09, -s.y * 0.02), c + Vector2(s.x * 0.17, s.y * 0.05)], tc)
		return
	if my_vtype == Defs.V_MOTO:
		var hb := s.y * 0.8 + shake.y
		_poly([Vector2(s.x * 0.44, s.y), Vector2(s.x * 0.56, s.y), Vector2(s.x * 0.53, hb), Vector2(s.x * 0.47, hb)], tc)
		wlayer.draw_circle(Vector2(s.x * 0.5, hb + s.y * 0.02), s.y * 0.035, Color(0.1, 0.1, 0.1))
		wlayer.draw_circle(Vector2(s.x * 0.5, hb + s.y * 0.02), s.y * 0.02, Color(0.75, 0.9, 1.0))
		wlayer.draw_line(Vector2(s.x * 0.22, hb - s.y * 0.04), Vector2(s.x * 0.78, hb - s.y * 0.04), metal, s.y * 0.02)
		wlayer.draw_circle(Vector2(s.x * 0.22, hb - s.y * 0.04), s.y * 0.045, glove)
		wlayer.draw_circle(Vector2(s.x * 0.78, hb - s.y * 0.04), s.y * 0.045, glove)
		_poly([Vector2(s.x * 0.05, s.y), Vector2(s.x * 0.18, hb), Vector2(s.x * 0.26, hb), Vector2(s.x * 0.2, s.y)], tc.darkened(0.2))
		_poly([Vector2(s.x * 0.95, s.y), Vector2(s.x * 0.82, hb), Vector2(s.x * 0.74, hb), Vector2(s.x * 0.8, s.y)], tc.darkened(0.2))
	else:
		var hood := s.y * 0.82 + shake.y
		_poly([Vector2(0, s.y), Vector2(0, hood), Vector2(s.x, hood), Vector2(s.x, s.y)], tc)
		wlayer.draw_line(Vector2(0, hood), Vector2(s.x, hood), tc.lightened(0.3), 2)
		wlayer.draw_rect(Rect2(s.x * 0.06, s.y * 0.2, s.x * 0.88, s.y * 0.04), metal)
		wlayer.draw_line(Vector2(s.x * 0.08, s.y * 0.24), Vector2(s.x * 0.08, hood), metal, s.x * 0.015)
		wlayer.draw_line(Vector2(s.x * 0.92, s.y * 0.24), Vector2(s.x * 0.92, hood), metal, s.x * 0.015)
		wlayer.draw_arc(Vector2(s.x * 0.5, s.y * 1.05), s.y * 0.18, PI, TAU, 24, Color(0.1, 0.1, 0.1), s.y * 0.03)


# ---------------------------------------------------------------- crisp HUD

func _txt(pos: Vector2, t: String, fs: int, col := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	hud.draw_string(font, pos + Vector2(2, 2), t, align, width, fs, Color(0, 0, 0, col.a * 0.8))
	hud.draw_string(font, pos, t, align, width, fs, col)


func _bar(r: Rect2, frac: float, col: Color, label: String, fs: int) -> void:
	hud.draw_rect(r, Color(0, 0, 0, 0.55))
	hud.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)
	hud.draw_rect(r, Color(1, 1, 1, 0.4), false, 1.0)
	if label != "":
		_txt(r.position + Vector2(6, r.size.y - 4), label, fs)


func _key(action: String) -> String:
	var m := {"kbm": {"use": "E", "seat": "F", "gear": "G", "fire": "LMB"}, "kb2": {"use": "Num Enter", "seat": "Num +", "gear": "Num 8", "fire": "Num 0"}, "pad": {"use": "X", "seat": "Y", "gear": "LB", "fire": "RT"}}
	return m.get(lp.device, m.pad)[action]


func _arrow(c: Vector2, d: int, size: float, col: Color) -> void:
	var angles := [-PI * 0.5, 0.0, PI * 0.5, PI]
	var f := Vector2.from_angle(float(angles[d]))
	var r := Vector2(-f.y, f.x)
	hud.draw_colored_polygon(PackedVector2Array([c + f * size, c - f * size * 0.6 + r * size * 0.8, c - f * size * 0.6 - r * size * 0.8]), col)


func _draw_hud() -> void:
	var s := hud.size
	var fs := int(clampf(s.y / 42.0, 12.0, 36.0) * Settings.ui_scale)
	if me.is_empty():
		_txt(Vector2(0, s.y * 0.5), "Waiting for host...", fs + 6, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, s.x)
		return
	var role := _role()
	var team: int = me.tm
	var tc: Color = Defs.TEAM_COLORS[team]
	var c := s * 0.5
	var pad := 14.0
	var line := float(fs) + 10.0

	# sniper scope
	if false:
		var r := s.y * 0.42
		var pts := PackedVector2Array()
		for i in 64:
			pts.append(c + Vector2.from_angle(TAU * i / 64.0) * r)
		hud.draw_rect(Rect2(0, 0, c.x - r, s.y), Color.BLACK)
		hud.draw_rect(Rect2(c.x + r, 0, s.x - c.x - r, s.y), Color.BLACK)
		hud.draw_arc(c, r + s.y, 0, TAU, 64, Color.BLACK, s.y * 2.0)
		hud.draw_arc(c, r, 0, TAU, 64, Color(0.05, 0.05, 0.05), 6)
		hud.draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), Color(0, 0, 0, 0.9), 2)
		hud.draw_line(c + Vector2(0, -r), c + Vector2(0, r), Color(0, 0, 0, 0.9), 2)
		hud.draw_circle(c, 2.5, Color(1, 0.2, 0.2))

	# crosshair
	if role == Defs.ROLE_FOOT and me.pz == null and not ((int(me.w) == Defs.W_SNIPER or int(me.w) == Defs.W_DMR) and ads_t > 0.85):
		var w := Color(1, 1, 1, 0.85 * (1.0 - ads_t * 0.7))
		var gap := 4.0 + spread * 10.0
		hud.draw_line(c + Vector2(-gap - 8, 0), c + Vector2(-gap, 0), w, 2)
		hud.draw_line(c + Vector2(gap, 0), c + Vector2(gap + 8, 0), w, 2)
		hud.draw_line(c + Vector2(0, -gap - 8), c + Vector2(0, -gap), w, 2)
		hud.draw_line(c + Vector2(0, gap), c + Vector2(0, gap + 8), w, 2)
	elif role == Defs.ROLE_SOLO or role == Defs.ROLE_GUNNER:
		var g := Color(0.4, 1.0, 0.4, 0.9)
		hud.draw_arc(c, 26, 0, TAU, 40, g, 2)
		hud.draw_line(c + Vector2(-60, 0), c + Vector2(-30, 0), g, 2)
		hud.draw_line(c + Vector2(30, 0), c + Vector2(60, 0), g, 2)
		hud.draw_line(c + Vector2(0, 30), c + Vector2(0, 60), g, 2)
		hud.draw_circle(c, 2, g)
		_txt(Vector2(0, c.y - 40), "%03d" % int(wrapf(rad_to_deg(cam_yaw) + 90.0, 0.0, 360.0)), fs - 4, g, HORIZONTAL_ALIGNMENT_CENTER, s.x)
	elif role == Defs.ROLE_DRIVER:
		var g := Color(1, 0.85, 0.3, 0.8)
		hud.draw_line(c + Vector2(-14, 10), c + Vector2(0, -4), g, 2)
		hud.draw_line(c + Vector2(14, 10), c + Vector2(0, -4), g, 2)

	# status bottom-left
	var y := s.y - pad - 22.0
	if role != Defs.ROLE_DEAD:
		_bar(Rect2(pad, y, 240, 22), float(me.hp) / 100.0, Color(0.8, 0.15, 0.15), "HP %d" % int(me.hp), fs - 4)
		y -= 14.0
		hud.draw_rect(Rect2(pad, y, 240, 8), Color(0, 0, 0, 0.5))
		hud.draw_rect(Rect2(pad, y, 240 * float(me.st), 8), Color(0.95, 0.2, 0.15) if me.ex else Color(0.9, 0.85, 0.3))
		if me.ex:
			_txt(Vector2(pad + 250, y + 9), "EXHAUSTED", fs - 8, Color(1, 0.4, 0.3))
		y -= 28.0
	if role == Defs.ROLE_SOLO or role == Defs.ROLE_DRIVER or role == Defs.ROLE_GUNNER:
		_bar(Rect2(pad, y, 240, 22), float(me.thp), Color(0.35, 0.65, 0.3), "HULL %d%%" % int(float(me.thp) * 100.0), fs - 4)
		y -= 28.0
		if role != Defs.ROLE_DRIVER:
			var ccd: float = me.ccd
			_bar(Rect2(pad, y, 240, 22), 1.0 - ccd, Color(0.85, 0.65, 0.2), "CANNON READY" if ccd <= 0.0 else "LOADING", fs - 4)
			y -= 28.0
	var stance := ""
	if role == Defs.ROLE_FOOT:
		stance = "  SPRINT" if me.sp else ("  CROUCH" if me.cr else "")
	_txt(Vector2(pad, y), "%s%s  -  %s TEAM" % [Defs.ROLE_NAMES[role], stance, Defs.TEAM_NAMES[team]], fs - 2, tc.lightened(0.3))

	# weapon & gear bottom-right
	var wtxt := ""
	if role == Defs.ROLE_FOOT:
		var wd: Dictionary = Defs.WPN[int(me.w)]
		if int(me.w) == Defs.W_KNIFE:
			wtxt = "KNIFE"
		else:
			wtxt = "%s   %d / %s" % [wd.name, int(me.mag), "--" if int(me.res) < 0 else str(int(me.res))]
		if me.rel:
			wtxt += "   RELOADING"
		var eq: int = me.eqt
		var gear := "%s  x%d  [%s]" % [Defs.EQUIP_SHORT[eq], int(me.eqn), _key("gear")] if eq != Defs.EQ_AMMO else "AMMO BAG (passive)"
		_txt(Vector2(0, s.y - pad - 6 - line), gear, fs - 4, Color(0.85, 0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_RIGHT, s.x - pad)
	elif role == Defs.ROLE_SOLO or role == Defs.ROLE_GUNNER:
		var vsd: Dictionary = Defs.VEHICLES[my_vtype]
		wtxt = ("%s  %s [fire]%s" % [vsd.name, str(vsd.main).to_upper(), "   MG [alt fire]" if float(vsd.mg_cd) > 0.0 else ""]) if str(vsd.main) != "none" else "%s  MG [fire]" % vsd.name
		_txt(Vector2(0, s.y - pad - 6 - line), "[%s] exit vehicle   [%s] switch seat" % [_key("use"), _key("seat")], fs - 4, Color(0.85, 0.85, 0.85, 0.8), HORIZONTAL_ALIGNMENT_RIGHT, s.x - pad)
	elif role == Defs.ROLE_DRIVER:
		wtxt = ("%s  HULL MG [fire]" % Defs.VEHICLES[my_vtype].name) if bool(Defs.VEHICLES[my_vtype].driver_mg) else "%s  DRIVING" % Defs.VEHICLES[my_vtype].name
		_txt(Vector2(0, s.y - pad - 6 - line), "[%s] exit vehicle   [%s] switch seat" % [_key("use"), _key("seat")], fs - 4, Color(0.85, 0.85, 0.85, 0.8), HORIZONTAL_ALIGNMENT_RIGHT, s.x - pad)
	if wtxt != "":
		_txt(Vector2(0, s.y - pad - 6), wtxt, fs + 2, Color(1, 0.9, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, s.x - pad)
		var wicon: Texture2D = WeaponIcons.weapon(int(me.w)) if role == Defs.ROLE_FOOT else null
		if wicon != null:
			# side view of the current weapon, left of its name
			var ih := float(fs) * 2.2
			var iw := ih * float(wicon.get_width()) / float(wicon.get_height())
			var tw := font.get_string_size(wtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 2).x
			hud.draw_texture_rect(wicon, Rect2(s.x - pad - tw - iw - 10.0, s.y - pad - 6.0 - ih * 0.72, iw, ih), false, Color(1, 1, 1, 0.95))

	if Settings.nametags and not MortarView.manning(me):
		_draw_nametags(s, fs)
	_draw_objectives(s, fs, pad, line)
	_draw_teams(s, fs)
	_draw_minimap(s, pad)
	_draw_event_banner(s, fs)

	_draw_log(s, fs)

	if me.pz != null:
		_draw_puzzle(s, fs, me.pz)
	else:
		var hint: int = me.hint
		var hints := {
			Defs.H_ENTER: "[%s] Enter tank" % _key("use"),
			Defs.H_KEYDOOR: "Locked - you need one of THIS bunker's keys (kill its owners and take theirs)",
			Defs.H_UNLOCK: "[%s] Unlock with a key" % _key("use"),
			Defs.H_TERMINAL: "[%s] Work the puzzle terminal - your teammate should cover you!" % _key("use"),
			Defs.H_VAULT: "Vault sealed - open and solve BOTH puzzle rooms of this bunker",
			Defs.H_AMMO: "[%s] Resupply ammo & gear" % _key("use"),
			Defs.H_SOLVED: "Puzzle solved",
			Defs.H_MORTAR: "[%s] Man the base mortar" % _key("use"),
			Defs.H_MORTAR_BUSY: "Mortar in use",
			Defs.H_FLAG_NOVEH: "Flag carriers can't use vehicles - run it home!",
		}
		var htxt: String = hints.get(hint, "")
		if hint == Defs.H_HEAL:
			for q in snap.get("p", []):
				if int(q.id) == int(me.get("hid", -1)):
					htxt = "[%s] Heal %s" % [_key("gear"), str(q.name)]
		if htxt != "":
			_txt(Vector2(0, s.y * 0.68), htxt, fs, Color(1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, s.x)
		if int(me.loot) > 0:
			_txt(Vector2(0, s.y * 0.68 + line), "CARRYING %d PTS - bring it to your tank or base" % int(me.loot), fs - 2, Color(1, 0.85, 0.3), HORIZONTAL_ALIGNMENT_CENTER, s.x)

	if role == Defs.ROLE_DEAD:
		_txt(Vector2(0, s.y * 0.42), "KILLED IN ACTION", fs * 2, Color(1, 0.3, 0.3), HORIZONTAL_ALIGNMENT_CENTER, s.x)
		_txt(Vector2(0, s.y * 0.42 + fs * 2), ("Redeploying in %d...  (your key was dropped)" if _gmode() == Defs.MODE_HEIST else "Redeploying in %d...") % int(ceilf(float(me.rsp))), fs + 2, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, s.x)
		_txt(Vector2(0, s.y * 0.42 + fs * 4), "Next loadout: %s / %s / %s   (change it in the pause menu)" % [Defs.WPN[lp.loadout[0]].name, Defs.WPN[lp.loadout[1]].name, Defs.EQUIP_SHORT[lp.loadout[2]]], fs - 2, Color(0.85, 0.85, 0.85), HORIZONTAL_ALIGNMENT_CENTER, s.x)

	if lp.show_scores or bool(snap.get("over", false)):
		_draw_scores(s, fs)
	if Settings.show_fps and lp.view_index == 0:
		_txt(Vector2(s.x * 0.5 - 30, s.y - 10), "%d FPS" % Engine.get_frames_per_second(), fs - 6, Color(0.7, 1, 0.7))


func _draw_objectives(s: Vector2, fs: int, pad: float, line: float) -> void:
	var team: int = me.tm
	var ts := _team_state(team)
	var bl: Array = snap.get("bunkers", [])
	if ts.is_empty() or bl.is_empty():
		return
	if _gmode() != Defs.MODE_HEIST:
		_draw_mode_objectives(fs, pad, line)
		return
	var oy := pad + fs
	_txt(Vector2(pad, oy), "%s TEAM   %d PTS" % [Defs.TEAM_NAMES[team], int(ts.score)], fs, Defs.TEAM_COLORS[team].lightened(0.3))
	oy += line
	oy = _draw_team_keys(pad, oy, fs, line, ts)
	# one line per bunker: owner, keys left, rooms, vault, reclaim timer
	for b in bl.size():
		var bs: Dictionary = bl[b]
		var owner: int = bs.owner
		var mine: bool = owner == team
		var rooms := ""
		for r in mapdata.rooms:
			rooms += ("[#]" if bs.sol[r] else ("[o]" if bs.acc[r] else "[ ]"))
		var vault := "VAULT OPEN" if bs.acc[mapdata.rooms] else "sealed"
		var who: String = "YOURS" if mine else (Defs.TEAM_NAMES[owner] if owner >= 0 else "neutral")
		var txt := "%s (%s)  keys %d  %s  %s" % [mapdata.bunker_names[b], who, int(bs["keys"]), rooms, vault]
		var col: Color = Defs.TEAM_COLORS[owner].lightened(0.35) if owner >= 0 else Color(0.8, 0.8, 0.75)
		if mine and (bs.acc as Array).has(true):
			txt += "  BREACHED! hold it: %ds" % int(60.0 - float(bs.hold))
			col = Color(1, 0.35, 0.3) if fmod(time, 1.0) < 0.6 else Color(1, 0.8, 0.4)
		elif not mine and float(bs.hold) > 1.0:
			txt += "  (owners reclaiming %ds)" % int(60.0 - float(bs.hold))
		_txt(Vector2(pad, oy), txt, fs - 6, col)
		oy += line - 6
	var al: Array = snap.get("alert", [])
	for b in al.size():
		if al[b] and fmod(time, 1.0) < 0.65 and mapdata.bunker_at(cam_pos) == b:
			_txt(Vector2(pad, oy + 4), "THIS BUNKER IS ON ALERT", fs - 4, Color(1, 0.25, 0.2))


## CTF: one line per flag (home / taken by X / dropped, returns in N s).  TDM: the kill race.
func _draw_mode_objectives(fs: int, pad: float, line: float) -> void:
	var team: int = me.tm
	var gm := _gmode()
	var ts: Dictionary = snap.get("teams", {})
	var lim := int(snap.get("lim", 0))
	var oy := pad + fs
	var my_score := int(_team_state(team).get("score", 0))
	var lim_txt := "" if lim > 99999 else " / %d" % lim
	_txt(Vector2(pad, oy), "%s  -  %s TEAM   %d%s %s" % [Defs.MODE_NAMES[gm], Defs.TEAM_NAMES[team], my_score, lim_txt, Defs.MODE_UNITS[gm].to_upper()], fs, Defs.TEAM_COLORS[team].lightened(0.3))
	oy += line
	if gm == Defs.MODE_CTF:
		var carrying := -1
		for f in snap.get("flags", []):
			if int(f[3]) == 1 and int(f[4]) == int(me.id):
				carrying = int(f[0])
		var own := _flag_info(team)
		if carrying >= 0:
			var at_home: bool = own.size() > 3 and int(own[3]) == 0
			var txt := "YOU HAVE THE %s FLAG - bring it to your flag at your camp!" % Defs.TEAM_NAMES[carrying]
			if not at_home:
				txt = "YOU HAVE THE %s FLAG - your own flag must be home to score!" % Defs.TEAM_NAMES[carrying]
			_txt(Vector2(pad, oy), txt, fs - 4, Color(1, 0.9, 0.3) if fmod(time, 1.0) < 0.7 else Color(1, 1, 1))
			oy += line
		var keys: Array = ts.keys()
		keys.sort()
		for t in keys:
			var f := _flag_info(int(t))
			if f.is_empty():
				continue
			var st := int(f[3])
			var who: String = "YOUR flag" if int(t) == team else "%s flag" % Defs.TEAM_NAMES[int(t)]
			var state := "at home"
			if st == 1:
				var cp := int(f[4])
				state = "TAKEN by %s" % ("YOU" if cp == int(me.id) else _pname(cp))
			elif st == 2:
				state = "DROPPED - returns in %ds" % int(ceilf(float(f[5])))
			var col: Color = Defs.TEAM_COLORS[int(t)].lightened(0.35)
			if int(t) == team and st != 0:
				col = Color(1, 0.35, 0.3) if fmod(time, 1.0) < 0.6 else Color(1, 0.8, 0.4)
			_txt(Vector2(pad, oy), "%s: %s   (%d caps)" % [who, state, int(ts[t].score)], fs - 6, col)
			oy += line - 6
	else:
		var rows: Array = []
		for t in ts:
			rows.append([int(ts[t].score), int(t)])
		rows.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
		for r in rows:
			var tt: int = r[1]
			var mark := "  <" if tt == team else ""
			_txt(Vector2(pad, oy), "%s  %d kills%s" % [Defs.TEAM_NAMES[tt], int(r[0]), mark], fs - 6, Defs.TEAM_COLORS[tt].lightened(0.35))
			oy += line - 6
		_txt(Vector2(pad, oy), "enemy kill +1, crewed vehicle +2", fs - 8, Color(0.85, 0.85, 0.8, 0.8))


const PZ_ACCENT := [Color(0.35, 1.0, 0.45), Color(0.35, 0.85, 1.0), Color(1.0, 0.75, 0.3), Color(0.95, 0.45, 1.0), Color(1.0, 0.55, 0.25),
	Color(0.4, 1.0, 0.85), Color(1.0, 0.4, 0.4)]


## CRT terminal: bezel, glowing screen, scanlines, stage pips, then the puzzle-specific display.
func _draw_puzzle(s: Vector2, fs: int, pz: Dictionary) -> void:
	var ty: int = pz.ty
	var info: Dictionary = Defs.PUZZLES[ty]
	var acc: Color = PZ_ACCENT[ty]
	var w := minf(700.0, s.x * 0.9)
	var h := minf(430.0, s.y * 0.7)
	var r := Rect2(s.x * 0.5 - w * 0.5, s.y * 0.5 - h * 0.5, w, h)
	# bezel
	hud.draw_rect(r.grow(18), Color(0.1, 0.1, 0.09))
	hud.draw_rect(r.grow(18), Color(0.32, 0.31, 0.28), false, 3.0)
	hud.draw_rect(r.grow(8), Color(0.03, 0.03, 0.03))
	for i in 4:
		hud.draw_circle(r.position + Vector2(-10, -10) + Vector2((w + 20) * (i % 2), (h + 20) * (i / 2)), 3.5, Color(0.45, 0.44, 0.4))
	# screen with radial-ish falloff
	var base := acc.darkened(0.88)
	for i in 16:
		var f := absf(float(i) - 7.5) / 7.5
		hud.draw_rect(Rect2(r.position.x, r.position.y + h * i / 16.0, w, h / 16.0 + 1.0), base.lerp(Color(0.0, 0.0, 0.0), f * 0.6))
	# header
	var stage: int = int(pz.stage)
	var stages: int = int(pz.stages)
	_glow_txt(Vector2(r.position.x + 20, r.position.y + fs + 12), info.name, fs + 4, acc)
	var bname: String = mapdata.bunker_names[int(pz.b)] if pz.has("b") else ""
	_txt(Vector2(r.position.x, r.position.y + fs + 10), "%s BUNKER  //  STAGE %d OF %d" % [bname, mini(stage + 1, stages), stages], fs - 6, acc.darkened(0.2), HORIZONTAL_ALIGNMENT_RIGHT, w - 20)
	for i in stages:
		var pc := Vector2(r.position.x + 26 + i * 22, r.position.y + fs + 30)
		hud.draw_circle(pc, 7, acc.darkened(0.7))
		if i < stage:
			hud.draw_circle(pc, 5, acc)
		elif i == stage:
			hud.draw_arc(pc, 6, 0, TAU, 16, acc, 2.0)
	hud.draw_line(Vector2(r.position.x + 14, r.position.y + fs + 44), Vector2(r.end.x - 14, r.position.y + fs + 44), acc.darkened(0.5), 1.0)
	var inner := Rect2(r.position.x + 24, r.position.y + fs + 54, w - 48, h - fs - 120)
	match ty:
		Defs.PZ_CODE: _pz_code(inner, fs, pz, acc)
		Defs.PZ_TUNER: _pz_tuner(inner, fs, pz, acc)
		Defs.PZ_DIAL: _pz_dial(inner, fs, pz, acc)
		Defs.PZ_TIMING: _pz_timing(inner, fs, pz, acc)
		Defs.PZ_VALVES: _pz_valves(inner, fs, pz, acc)
		Defs.PZ_STEADY: _pz_steady(inner, fs, pz, acc)
		Defs.PZ_PUMP: _pz_pump(inner, fs, pz, acc)
	# footer
	_txt(Vector2(r.position.x, r.end.y - 34), info.help, fs - 6, acc.lightened(0.4), HORIZONTAL_ALIGNMENT_CENTER, w)
	_txt(Vector2(r.position.x, r.end.y - 12), "[%s] leave terminal   -   you cannot shoot while working!" % _key("use"), fs - 7, Color(1, 0.55, 0.45), HORIZONTAL_ALIGNMENT_CENTER, w)
	# mistake flash, scanlines, flicker
	var err: float = pz.get("err", 0.0)
	if err > 0.0:
		hud.draw_rect(r, Color(1, 0.1, 0.05, err * 0.5))
		_glow_txt(Vector2(r.position.x, r.get_center().y), "ACCESS DENIED - RESET", fs + 8, Color(1, 0.3, 0.25), HORIZONTAL_ALIGNMENT_CENTER, w)
	var yy := r.position.y
	while yy < r.end.y:
		hud.draw_line(Vector2(r.position.x, yy), Vector2(r.end.x, yy), Color(0, 0, 0, 0.18), 1.0)
		yy += 3.0
	var roll := fmod(time * 60.0, h)
	hud.draw_rect(Rect2(r.position.x, r.position.y + roll, w, 24), Color(acc.r, acc.g, acc.b, 0.035))


func _glow_txt(pos: Vector2, t: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	for o in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
		hud.draw_string(font, pos + o, t, align, width, size, Color(col.r, col.g, col.b, 0.18))
	hud.draw_string(font, pos, t, align, width, size, col)


func _cell(rect: Rect2, fill: Color, edge: Color, lw := 2.0) -> void:
	hud.draw_rect(rect, fill)
	hud.draw_rect(rect, edge, false, lw)


func _pz_code(inner: Rect2, fs: int, pz: Dictionary, acc: Color) -> void:
	var seq: Array = pz.seq
	var pos: int = pz.pos
	var cell := minf(72.0, (inner.size.x - 20.0) / seq.size())
	var x0 := inner.position.x + (inner.size.x - cell * seq.size()) * 0.5
	var y0 := inner.position.y + inner.size.y * 0.25
	for i in seq.size():
		var cr := Rect2(x0 + i * cell + 5, y0, cell - 10, cell - 10)
		var done := i < pos
		var cur := i == pos
		var pulse := 0.5 + 0.5 * sin(time * 8.0)
		_cell(cr, acc.darkened(0.55) if done else (acc.darkened(0.8).lerp(acc.darkened(0.6), pulse) if cur else Color(0.02, 0.04, 0.02)), acc if cur else acc.darkened(0.5))
		_arrow(cr.get_center(), int(seq[i]), cell * 0.26, acc.lightened(0.5) if done else (Color(1, 1, 0.6) if cur else acc))
	_txt(Vector2(inner.position.x, y0 + cell + 30), "%d / %d" % [pos, seq.size()], fs - 2, acc, HORIZONTAL_ALIGNMENT_CENTER, inner.size.x)


func _pz_tuner(inner: Rect2, fs: int, pz: Dictionary, acc: Color) -> void:
	var tol: float = pz.get("tol", 0.1)
	var bar := Rect2(inner.position.x + 10, inner.position.y + inner.size.y * 0.18, inner.size.x - 20, inner.size.y * 0.42)
	_cell(bar, Color(0.0, 0.05, 0.08), acc.darkened(0.3))
	for i in 11:
		var gx := bar.position.x + bar.size.x * i / 10.0
		hud.draw_line(Vector2(gx, bar.position.y), Vector2(gx, bar.end.y), acc.darkened(0.75), 1.0)
		_txt(Vector2(gx - 14, bar.end.y + 16), "%d" % (88 + i * 2), fs - 9, acc.darkened(0.3))
	var tx: float = bar.position.x + float(pz.t) * bar.size.x
	hud.draw_rect(Rect2(tx - tol * bar.size.x, bar.position.y, tol * 2.0 * bar.size.x, bar.size.y), Color(0.2, 0.9, 0.4, 0.28))
	var pts := PackedVector2Array()
	for i in 120:
		var f := float(i) / 119.0
		var amp := exp(-pow((f - float(pz.t)) / 0.08, 2.0)) * bar.size.y * 0.42 + 2.0
		pts.append(Vector2(bar.position.x + f * bar.size.x, bar.get_center().y + sin(time * 12.0 + f * 90.0) * amp))
	hud.draw_polyline(pts, acc, 2.0)
	var vx: float = bar.position.x + float(pz.v) * bar.size.x
	hud.draw_rect(Rect2(vx - 2, bar.position.y - 10, 4, bar.size.y + 20), Color(1, 0.9, 0.3))
	hud.draw_colored_polygon(PackedVector2Array([Vector2(vx - 8, bar.position.y - 14), Vector2(vx + 8, bar.position.y - 14), Vector2(vx, bar.position.y - 4)]), Color(1, 0.9, 0.3))
	var lock := float(pz.hold) / 3.5
	_txt(Vector2(inner.position.x, bar.end.y + 44), "SIGNAL LOCK", fs - 6, acc)
	_bar(Rect2(inner.position.x + 120, bar.end.y + 32, inner.size.x - 130, 14), lock, acc, "", fs - 6)


func _pz_dial(inner: Rect2, fs: int, pz: Dictionary, acc: Color) -> void:
	var c := Vector2(inner.position.x + inner.size.x * 0.32, inner.get_center().y)
	var rad := minf(inner.size.y * 0.46, inner.size.x * 0.28)
	hud.draw_circle(c, rad + 8, Color(0.12, 0.12, 0.12))
	hud.draw_circle(c, rad, Color(0.2, 0.19, 0.17))
	hud.draw_arc(c, rad, 0, TAU, 64, acc.darkened(0.2), 2.0)
	var rot := -float(pz.v) / 40.0 * TAU
	for i in 40:
		var a := rot + TAU * i / 40.0 - PI * 0.5
		var long := i % 5 == 0
		hud.draw_line(c + Vector2.from_angle(a) * (rad - (14.0 if long else 7.0)), c + Vector2.from_angle(a) * (rad - 2.0), acc if long else acc.darkened(0.4), 2.0 if long else 1.0)
		if long:
			var tp := c + Vector2.from_angle(a) * (rad - 28.0)
			_txt(tp - Vector2(8, -6), str(i), fs - 6, acc.lightened(0.3))
	hud.draw_circle(c, rad * 0.32, Color(0.32, 0.3, 0.27))
	hud.draw_circle(c, rad * 0.26, Color(0.16, 0.15, 0.13))
	hud.draw_line(c, c + Vector2.from_angle(rot - PI * 0.5) * rad * 0.3, acc, 3.0)
	hud.draw_colored_polygon(PackedVector2Array([c + Vector2(-9, -rad - 18), c + Vector2(9, -rad - 18), c + Vector2(0, -rad - 4)]), Color(1, 0.3, 0.25))
	_glow_txt(c + Vector2(-15, rad * 0.62), "%02d" % (int(round(float(pz.v))) % 40), fs + 4, Color(1, 0.9, 0.5))
	# combination list
	var combo: Array = pz.combo
	var idx: int = pz.idx
	var lx := inner.position.x + inner.size.x * 0.62
	var ly := inner.position.y + 10
	_txt(Vector2(lx, ly + fs), "COMBINATION", fs - 4, acc)
	for i in combo.size():
		var y := ly + fs * 2 + 12 + i * (fs + 14)
		var col := acc.lightened(0.4) if i < idx else (Color(1, 1, 0.6) if i == idx else acc.darkened(0.4))
		var dir_txt := "RIGHT >" if i % 2 == 0 else "< LEFT"
		var num := "%02d" % int(combo[i]) if i <= idx else "--"
		_cell(Rect2(lx, y - fs - 2, inner.size.x * 0.34, fs + 10), Color(0, 0, 0, 0.3), col.darkened(0.3), 1.0)
		_txt(Vector2(lx + 10, y), "%s  %s" % [num, dir_txt], fs - 2, col)
		if i < idx:
			_txt(Vector2(lx + inner.size.x * 0.27, y), "OK", fs - 4, acc)
	var ld: int = pz.lastdir
	_txt(Vector2(lx, inner.end.y - 4), "turning: %s" % ("RIGHT" if ld > 0 else ("LEFT" if ld < 0 else "-")), fs - 6, acc.darkened(0.2))


func _pz_valves(inner: Rect2, fs: int, pz: Dictionary, acc: Color) -> void:
	var band: float = pz.get("band", 0.12)
	var gw := inner.size.x * 0.16
	var gh := inner.size.y * 0.78
	for i in 3:
		var gx := inner.position.x + inner.size.x * (0.12 + i * 0.27)
		var gr := Rect2(gx, inner.position.y + 6, gw, gh)
		var sel := i == int(pz.sel)
		_cell(gr, Color(0.06, 0.03, 0.01), Color(1, 1, 0.6) if sel else acc.darkened(0.4), 3.0 if sel else 1.5)
		var by := gr.end.y - (0.5 + band) * gh
		hud.draw_rect(Rect2(gx + 2, by, gw - 4, band * 2.0 * gh), Color(0.2, 0.85, 0.35, 0.35))
		var g: float = pz.g[i]
		var ok := absf(g - 0.5) <= band
		var lvl := gr.end.y - g * gh
		hud.draw_rect(Rect2(gx + 6, lvl, gw - 12, gr.end.y - lvl - 3), (Color(0.3, 0.9, 0.4) if ok else Color(1, 0.4, 0.2)).darkened(0.25))
		hud.draw_line(Vector2(gx - 6, lvl), Vector2(gx + gw + 6, lvl), Color(1, 0.95, 0.7), 2.0)
		for k in 9:
			var ty2 := gr.position.y + gh * (k + 1) / 10.0
			hud.draw_line(Vector2(gx, ty2), Vector2(gx + 8, ty2), acc.darkened(0.3), 1.0)
		_txt(Vector2(gx, gr.end.y + fs + 2), "VALVE %d" % (i + 1), fs - 6, Color(1, 1, 0.6) if sel else acc)
	_txt(Vector2(inner.position.x, inner.end.y + 10), "STABLE", fs - 6, acc)
	_bar(Rect2(inner.position.x + 80, inner.end.y, inner.size.x - 90, 12), float(pz.hold) / float(pz.get("need", 3.0)), acc, "", fs - 6)


## TIMING LOCK: marker sweeping a horizontal track, green zone, hit lamps.
func _pz_timing(inner: Rect2, fs: int, pz: Dictionary, acc: Color) -> void:
	var track := Rect2(inner.position.x + 20, inner.position.y + inner.size.y * 0.3, inner.size.x - 40, inner.size.y * 0.24)
	var miss: float = pz.get("miss", 0.0)
	_cell(track, Color(0.05, 0.0, 0.06), Color(1, 0.3, 0.25) if miss > 0.0 else acc.darkened(0.3), 2.0)
	for i in 21:
		var gx := track.position.x + track.size.x * i / 20.0
		hud.draw_line(Vector2(gx, track.end.y - (10.0 if i % 5 == 0 else 5.0)), Vector2(gx, track.end.y), acc.darkened(0.5), 1.0)
	var zc: float = pz.zc
	var zw: float = pz.zw
	var zr := Rect2(track.position.x + (zc - zw) * track.size.x, track.position.y + 3, zw * 2.0 * track.size.x, track.size.y - 6)
	var m: float = pz.m
	var inside := absf(m - zc) <= zw
	hud.draw_rect(zr, Color(0.25, 0.95, 0.4, 0.55 if inside else 0.32))
	hud.draw_rect(zr, Color(0.4, 1.0, 0.55), false, 2.0)
	var mx := track.position.x + m * track.size.x
	hud.draw_rect(Rect2(mx - 3, track.position.y - 12, 6, track.size.y + 24), Color(1, 1, 0.75) if inside else Color(1, 0.85, 0.3))
	hud.draw_circle(Vector2(mx, track.position.y - 14), 6, Color(1, 0.9, 0.4))
	# hit lamps
	var need: int = pz.get("need", 3)
	var hits: int = pz.get("hits", 0)
	var ly := track.end.y + fs + 28
	for i in need:
		var c := Vector2(inner.get_center().x + (i - (need - 1) * 0.5) * 46.0, ly)
		hud.draw_circle(c, 15, acc.darkened(0.75))
		hud.draw_circle(c, 11, Color(0.35, 1.0, 0.5) if i < hits else Color(0.06, 0.08, 0.06))
		hud.draw_arc(c, 15, 0, TAU, 20, acc.darkened(0.3), 2.0)
	if miss > 0.0:
		_glow_txt(Vector2(inner.position.x, track.position.y - 22), "MISS!", fs, Color(1, 0.35, 0.3), HORIZONTAL_ALIGNMENT_CENTER, inner.size.x)
	else:
		_txt(Vector2(inner.position.x, track.position.y - 22), "[%s] when the marker is in the green" % _key("fire"), fs - 6, acc, HORIZONTAL_ALIGNMENT_CENTER, inner.size.x)


## STEADY HAND: square field, wandering ring, jittery cursor with a short trail.
func _pz_steady(inner: Rect2, fs: int, pz: Dictionary, acc: Color) -> void:
	var side := minf(inner.size.y - 26.0, inner.size.x * 0.6)
	var f := Rect2(inner.get_center().x - side * 0.5, inner.position.y, side, side)
	_cell(f, Color(0.0, 0.06, 0.05), acc.darkened(0.35), 2.0)
	for i in 1:
		hud.draw_line(Vector2(f.get_center().x, f.position.y), Vector2(f.get_center().x, f.end.y), acc.darkened(0.75), 1.0)
		hud.draw_line(Vector2(f.position.x, f.get_center().y), Vector2(f.end.x, f.get_center().y), acc.darkened(0.75), 1.0)
	var to_px := func(x: float, y: float) -> Vector2:
		return f.get_center() + Vector2(x, -y) * side * 0.5
	var tc: Vector2 = to_px.call(float(pz.tx), float(pz.ty2))
	var tr: float = float(pz.tr) * side * 0.5
	var cc: Vector2 = to_px.call(float(pz.cx), float(pz.cy))
	var inside := cc.distance_to(tc) <= tr
	hud.draw_circle(tc, tr, Color(0.3, 1.0, 0.6, 0.18 if inside else 0.08))
	hud.draw_arc(tc, tr, 0, TAU, 48, Color(0.4, 1.0, 0.65) if inside else acc, 3.0)
	var shake := Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
	var col := Color(1, 1, 0.7) if inside else Color(1, 0.45, 0.3)
	hud.draw_line(cc + shake + Vector2(-12, 0), cc + shake + Vector2(12, 0), col, 2.0)
	hud.draw_line(cc + shake + Vector2(0, -12), cc + shake + Vector2(0, 12), col, 2.0)
	hud.draw_circle(cc + shake, 4.0, col)
	_bar(Rect2(f.position.x, f.end.y + 8, side, 10), float(pz.hold) / float(pz.get("need", 3.0)), acc, "", fs - 6)


## PRESSURE PUMP: tall gauge with the green top band, piston arrows that flash on the side to press next.
func _pz_pump(inner: Rect2, fs: int, pz: Dictionary, acc: Color) -> void:
	var gw := inner.size.x * 0.14
	var gh := inner.size.y * 0.85
	var gr := Rect2(inner.get_center().x - gw * 0.5, inner.position.y + 4, gw, gh)
	_cell(gr, Color(0.07, 0.01, 0.01), acc.darkened(0.3), 2.0)
	var lo: float = pz.get("lo", 0.75)
	var band := Rect2(gr.position.x + 2, gr.position.y + 2, gw - 4, (1.0 - lo) * gh - 2)
	hud.draw_rect(band, Color(0.25, 0.9, 0.4, 0.3))
	var g: float = pz.g
	var ok := g >= lo
	var lvl := gr.end.y - g * gh
	hud.draw_rect(Rect2(gr.position.x + 6, lvl, gw - 12, gr.end.y - lvl - 3), (Color(0.3, 0.95, 0.45) if ok else Color(1.0, 0.35, 0.25)).darkened(0.2))
	hud.draw_line(Vector2(gr.position.x - 8, lvl), Vector2(gr.end.x + 8, lvl), Color(1, 0.95, 0.7), 2.0)
	for k in 9:
		var ty2 := gr.position.y + gh * (k + 1) / 10.0
		hud.draw_line(Vector2(gr.position.x, ty2), Vector2(gr.position.x + 8, ty2), acc.darkened(0.3), 1.0)
	var last: int = pz.get("last", 0)
	var asz := fs * 1.4
	var lc := Vector2(gr.position.x - inner.size.x * 0.2, gr.get_center().y)
	var rc := Vector2(gr.end.x + inner.size.x * 0.2, gr.get_center().y)
	var pulse := 0.6 + 0.4 * sin(time * 14.0)
	_arrow(lc, 3, asz, Color(1, 1, 0.6, pulse) if last != -1 else acc.darkened(0.55))
	_arrow(rc, 1, asz, Color(1, 1, 0.6, pulse) if last != 1 else acc.darkened(0.55))
	_txt(Vector2(lc.x - 60, lc.y + asz + fs), "LEFT", fs - 6, acc, HORIZONTAL_ALIGNMENT_CENTER, 120)
	_txt(Vector2(rc.x - 60, rc.y + asz + fs), "RIGHT", fs - 6, acc, HORIZONTAL_ALIGNMENT_CENTER, 120)
	_bar(Rect2(inner.position.x + 40, inner.end.y + 4, inner.size.x - 80, 12), float(pz.hold) / float(pz.get("need", 1.6)), acc, "", fs - 6)


## Score chips across the top with the match timer.
## Banner under the scoreboard while a random event runs.
func _draw_event_banner(s: Vector2, fs: int) -> void:
	var ev := _evt()
	if ev.is_empty():
		return
	var k: int = ev.k
	var nm: String = Defs.STORM_NAMES[mapdata.theme] if k == Defs.EVT_STORM else Defs.EVENT_NAMES[k]
	var info: String = Defs.EVENT_INFO[k]
	var col := [Color(0.3, 1.0, 0.4), Color(1.0, 0.3, 0.2), Color(0.6, 0.75, 1.0), Color(1.0, 0.6, 0.2), Color(1.0, 0.85, 0.2), Color(1.0, 0.4, 0.8)][k] as Color
	var warn: float = ev.get("warn", 0.0)
	var left: float = ev.t
	var head := "EVENT: %s" % nm
	if k == Defs.EVT_ARTY and warn > 0.0:
		head = "AIR RAID SIREN - bombers in %d s" % int(ceil(warn))
		info = "Bomber tracks show as red lines on the map. Get under a roof or away from the lines!"
	elif k == Defs.EVT_SUPPLY and not bool(ev.landed):
		head = "SUPPLY DROP incoming"
		info = "Watch the green marker and the smoke - the crate is coming down."
	elif k == Defs.EVT_BOUNTY:
		var bt: int = ev.team
		info = ("YOUR team has a bounty on its head - stay alive!" if bt == int(me.tm) else ("Kill %s soldiers: +%d pts each." % [Defs.TEAM_NAMES[bt], Defs.BOUNTY_VALUE] if _gmode() == Defs.MODE_HEIST else "Kills on %s count DOUBLE." % Defs.TEAM_NAMES[bt])) if bt >= 0 else info
		col = Defs.TEAM_COLORS[bt] if bt >= 0 else col
	if k != Defs.EVT_SUPPLY or bool(ev.landed):
		head += "   %d s" % int(ceil(left))
	var w := minf(s.x * 0.62, 760.0)
	var y := 30.0 + fs + 22.0 if s.x >= 1100.0 else s.y * 0.13
	var r := Rect2((s.x - w) * 0.5, y, w, fs * 2.6 + 10)
	var pulse := 0.5 + 0.5 * sin(time * 4.0)
	hud.draw_rect(r, Color(0.05, 0.05, 0.06, 0.72))
	hud.draw_rect(r, Color(col.r, col.g, col.b, 0.6 + 0.4 * pulse), false, 2.0)
	_txt(Vector2(r.position.x, y + fs + 4), head, fs, col, HORIZONTAL_ALIGNMENT_CENTER, w)
	_txt(Vector2(r.position.x, y + fs * 2.2 + 6), info, fs - 6, Color(0.92, 0.92, 0.9), HORIZONTAL_ALIGNMENT_CENTER, w)


func _draw_teams(s: Vector2, fs: int) -> void:
	var ts: Dictionary = snap.get("teams", {})
	var keys: Array = ts.keys()
	keys.sort()
	var w := 130.0
	var narrow := s.x < 1100.0
	var x := s.x * 0.5 - keys.size() * (w + 6) * 0.5
	var y := 30.0
	if narrow:
		var ms := clampf(minf(s.x, s.y) * 0.28, 120.0, 240.0)
		x = s.x - 14.0 - w
		y = 14.0 + 34.0 + ms + 10.0
	var tl: float = snap.get("tl", 0.0)
	var gm := _gmode()
	var timer := "%d:%02d   first to %d" % [int(tl) / 60, int(tl) % 60, int(snap.get("lim", 0))]
	if gm != Defs.MODE_HEIST:
		timer = "%s   %d:%02d   first to %d %s" % [Defs.MODE_NAMES[gm], int(tl) / 60, int(tl) % 60, int(snap.get("lim", 0)), Defs.MODE_UNITS[gm]]
	if narrow:
		_txt(Vector2(x, y - 6), timer, fs - 6, Color(1, 1, 1, 0.9))
		y += 6
	else:
		_txt(Vector2(0, 22), timer, fs - 4, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, s.x)
	for t in keys:
		var col: Color = Defs.TEAM_COLORS[int(t)]
		var info: Dictionary = ts[t]
		var r := Rect2(x, y, w, fs + 10)
		hud.draw_rect(r, Color(col.r, col.g, col.b, 0.6 if int(t) == int(me.tm) else 0.3))
		hud.draw_rect(r, col, false, 2.0)
		var extra := "  K%d" % int(info["keys"])
		if gm == Defs.MODE_TDM:
			extra = " kills"
		elif gm == Defs.MODE_CTF:
			var fi := _flag_info(int(t))
			extra = "  " + (["FLAG", "TAKEN", "DROP"][clampi(int(fi[3]), 0, 2)] if fi.size() > 3 else "")
		_txt(Vector2(x + 6, y + fs + 2), "%s %d%s" % [Defs.TEAM_NAMES[int(t)].substr(0, 3), int(info.score), extra], fs - 6)
		if narrow:
			y += fs + 14
		else:
			x += w + 6


func _draw_scores(s: Vector2, fs: int) -> void:
	var rows: Array = snap.get("p", []).duplicate()
	rows.sort_custom(func(a, b): return int(a.tm) < int(b.tm) or (int(a.tm) == int(b.tm) and int(a.kills) > int(b.kills)))
	var h := (rows.size() + 4) * (fs + 8) + 20.0
	var r := Rect2(s.x * 0.15, s.y * 0.16, s.x * 0.7, h)
	hud.draw_rect(r, Color(0, 0, 0, 0.8))
	var yy := r.position.y + fs + 12
	if bool(snap.get("over", false)):
		var win: int = snap.get("win", -1)
		_txt(Vector2(r.position.x, yy), "MATCH OVER - %s TEAM WINS   (ENTER: menu)" % Defs.TEAM_NAMES[maxi(win, 0)], fs + 2, Defs.TEAM_COLORS[maxi(win, 0)].lightened(0.3), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		yy += fs + 14
	var ts: Dictionary = snap.get("teams", {})
	var gm := _gmode()
	var line := "%s:     " % Defs.MODE_NAMES[gm]
	for t in ts:
		line += "%s %d %s     " % [Defs.TEAM_NAMES[int(t)], int(ts[t].score), Defs.MODE_UNITS[gm]]
	_txt(Vector2(r.position.x, yy), line, fs - 2, Color(1, 0.9, 0.6), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	yy += fs + 12
	_txt(Vector2(r.position.x + 16, yy), "PLAYER", fs - 2, Color(1, 0.85, 0.4))
	_txt(Vector2(r.position.x, yy), "KILLS     STATUS", fs - 2, Color(1, 0.85, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 16)
	for row in rows:
		yy += fs + 8
		var col: Color = Defs.TEAM_COLORS[int(row.tm)]
		_txt(Vector2(r.position.x + 16, yy), "%s%s" % [row.name, "  (AI)" if row.bot else ""], fs - 2, col.lightened(0.3))
		_txt(Vector2(r.position.x, yy), "%d     %s" % [int(row.kills), Defs.ROLE_NAMES[int(row.role)]], fs - 2, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 16)


func _draw_minimap(s: Vector2, pad: float) -> void:
	var ms := clampf(minf(s.x, s.y) * 0.28, 120.0, 240.0)
	var o := Vector2(s.x - pad - ms, pad + 34)
	var k: float = ms / float(mapdata.W)
	hud.draw_rect(Rect2(o - Vector2(3, 3), Vector2(ms + 6, ms + 6)), Color(0, 0, 0, 0.7))
	hud.draw_texture_rect(res.mini_tex, Rect2(o, Vector2(ms, ms)), false, Color(1, 1, 1, 0.9))
	hud.draw_texture_rect(fog_tex, Rect2(o, Vector2(ms, ms)), false)
	if _evt_on(Defs.EVT_JAM):
		# radio jammed: nothing but static
		hud.draw_rect(Rect2(o, Vector2(ms, ms)), Color(0.05, 0.06, 0.05, 0.92))
		var cell := ms / 24.0
		var seed_i := int(time * 20.0)
		for yy in 24:
			for xx in 24:
				var n := float((xx * 7919 + yy * 104729 + seed_i * 31337) % 1000) / 1000.0
				if n > 0.55:
					hud.draw_rect(Rect2(o + Vector2(xx, yy) * cell, Vector2(cell, cell)), Color(0.6, 0.7, 0.6, (n - 0.55) * 0.9))
		_txt(o + Vector2(0, ms * 0.5 - 10), "NO SIGNAL", 18, Color(1, 0.35, 0.3, 0.6 + 0.4 * sin(time * 6.0)), HORIZONTAL_ALIGNMENT_CENTER, ms)
		return
	var ev := _evt()
	if not ev.is_empty():
		var ep := o + Vector2(ev.x, ev.y) * k
		if int(ev.k) == Defs.EVT_ARTY:
			# bomber tracks (dashed red while incoming, solid while flying) and impacts about to land
			var now: float = snap.get("t", 0.0)
			var a := 0.5 + 0.5 * sin(time * 10.0)
			hud.draw_rect(Rect2(o, Vector2(ms, ms)), Color(1, 0.1, 0.05, 0.06 + 0.06 * a))
			for run in ev.get("runs", []):
				var ra: Vector2 = o + Vector2(run.ax, run.ay) * k
				var rb: Vector2 = o + Vector2(run.bx, run.by) * k
				var t0: float = run.t0
				var L := Vector2(run.ax, run.ay).distance_to(Vector2(run.bx, run.by))
				if now > t0 + L / 16.0 + 1.5 or now < t0 - 5.0:
					continue
				if now < t0:
					hud.draw_dashed_line(ra, rb, Color(1, 0.3, 0.2, 0.5 + 0.4 * a), 1.5, 6.0)
				else:
					hud.draw_line(ra, rb, Color(1, 0.2, 0.1, 0.55), 2.0)
					var f := clampf((now - t0) * 16.0 / L, 0.0, 1.0)
					hud.draw_circle(ra.lerp(rb, f), 3.5, Color(1, 1, 1))
			for bm in ev.get("bombs", []):
				var left: float = float(bm[2]) - now
				if left < 3.0:
					hud.draw_circle(o + Vector2(bm[0], bm[1]) * k, 1.5 + (3.0 - left), Color(1, 0.15, 0.05, 0.85))
		elif int(ev.k) == Defs.EVT_SUPPLY:
			var a := 0.6 + 0.4 * sin(time * 5.0)
			hud.draw_rect(Rect2(ep - Vector2(5, 5), Vector2(10, 10)), Color(0.3, 1.0, 0.4, a))
			hud.draw_rect(Rect2(ep - Vector2(5, 5), Vector2(10, 10)), Color.BLACK, false, 1.0)
			hud.draw_arc(ep, 9.0 + 3.0 * a, 0, TAU, 20, Color(0.3, 1.0, 0.4, 0.7), 1.5)
	var team: int = me.tm
	var bl: Array = snap.get("bunkers", [])
	for b in mini(bl.size(), mapdata.bunkers.size()):
		var bk: Dictionary = mapdata.bunkers[b]
		var bs: Dictionary = bl[b]
		var owner: int = bs.owner
		var rr := Rect2(o + Vector2(bk.bx, bk.by) * k, Vector2(24, 24) * k)
		hud.draw_rect(rr, Defs.TEAM_COLORS[owner] if owner >= 0 else Color(0.8, 0.8, 0.8), false, 2.0)
		for r in (mapdata.rooms + 1 if _gmode() == Defs.MODE_HEIST else 0):
			var dc: Vector2i = bk.doors[r]
			var p := o + Vector2(dc.x + 0.5, dc.y + 0.5) * k
			hud.draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), Color(0.3, 1, 0.4) if bs.acc[r] else Color(1, 0.8, 0.2))
	var e: PackedFloat32Array = snap.get("e", PackedFloat32Array())
	for i in e.size() / 9:
		var b := i * 9
		var typ := int(e[b])
		var et := int(e[b + 4])
		var id := int(e[b + 8])
		var p := o + Vector2(e[b + 1], e[b + 2]) * k
		if typ == Defs.E_TANK or typ == Defs.E_WRECK:
			if et == team:
				hud.draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), Defs.TEAM_COLORS[team] if typ == Defs.E_TANK else Color(0.3, 0.3, 0.3))
			elif typ == Defs.E_TANK and spotted.has(id):
				hud.draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), Defs.TEAM_COLORS[et])
				hud.draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), Color.BLACK, false, 1.0)
		elif typ == Defs.E_PLAYER:
			if et == team and id != int(me.id):
				hud.draw_circle(p, 3, Defs.TEAM_COLORS[team].lightened(0.3))
			elif et != team and spotted.has(id):
				hud.draw_circle(p, 3.5, Defs.TEAM_COLORS[et])
		elif typ == Defs.E_KEY and spotted.has(id):
			hud.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color(0.95, 0.85, 0.2))
			hud.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color.BLACK, false, 1.0)
		elif (typ == Defs.E_SOLDIER or typ == Defs.E_TURRET) and spotted.has(id):
			hud.draw_circle(p, 2.5 if typ == Defs.E_SOLDIER else 3.5, Color(1, 0.15, 0.1))
	# CTF flags (always shown - carriers too, for everyone)
	for f in snap.get("flags", []):
		var ft: int = int(f[0])
		var fp: Vector2 = o + Vector2(float(f[1]), float(f[2])) * k
		var fst: int = int(f[3])
		var fc: Color = Defs.TEAM_COLORS[clampi(ft, 0, 3)]
		if fst == 1:
			var blink := 0.5 + 0.5 * sin(time * 8.0)
			hud.draw_arc(fp, 6.0 + 2.0 * blink, 0, TAU, 16, Color(1, 1, 1, 0.5 + 0.5 * blink), 1.5)
		hud.draw_line(fp + Vector2(-3, 5), fp + Vector2(-3, -7), Color.BLACK, 2.0)
		hud.draw_colored_polygon(PackedVector2Array([fp + Vector2(-3, -7), fp + Vector2(5, -4), fp + Vector2(-3, -1)]), fc.lightened(0.2) if fst != 2 or fmod(time, 0.8) < 0.5 else Color(1, 1, 1))
	if mview != null:
		mview.minimap_marks(hud, o, k, snap, team)
	var mp := o + cam_pos * k
	var f := Vector2.from_angle(cam_yaw)
	hud.draw_colored_polygon(PackedVector2Array([mp + f * 7, mp + f.rotated(2.5) * 5, mp + f.rotated(-2.5) * 5]), Color.WHITE)
