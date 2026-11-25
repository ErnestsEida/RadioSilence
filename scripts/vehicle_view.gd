extends SubViewport
## First-person 3D vehicle overlay (analogous to viewmodel.gd).
##
##   var vv = preload("res://scripts/vehicle_view.gd").new()
##   add_child(vv); vv.setup(vtype, team_color)
##   every frame: vv.size = low_res_size; vv.update_pose(role, st)
##   draw vv.get_texture() full-screen over the raycast view.
##
## role: 1 = commander (drives and aims, camera follows the turret), 2 = driver (camera fixed to
## the hull), 3 = gunner (camera follows the turret).
## st: "turret_rel" (rad, + = turret turned right), "hfov" (deg), "time", "speed" (-1..1),
##     "steer" (-1..1), "kick" (0..1), "eye" (camera height).

const VM := preload("res://scripts/vehicle_models.gd")

const ROLE_SOLO := 1
const ROLE_DRIVER := 2
const ROLE_GUNNER := 3

var _vtype := -1
var _ready_done := false
var _world: Node3D
var _cam: Camera3D
var _model: Node3D
var _body: Node3D
var _turret: Node3D
var _gun: Node3D
var _gun_rest := Transform3D.IDENTITY
var _steer: Node3D
var _steer_rest := Transform3D.IDENTITY
var _wheel: Node3D
var _wheel_rest := Transform3D.IDENTITY
var _dress: Node3D          # camera-space frame plates
var _plates: Array = []     # [MeshInstance3D, Rect2 (ndc x0, y0, x1, y1)]
var _tdress: Node3D         # turret-space interior parts (breech)
var _breech: Node3D
var _breech_rest := Transform3D.IDENTITY
var _sleeve: Node3D
var _role := -1
var m_team: StandardMaterial3D
var m_glass: StandardMaterial3D
var m_frame: StandardMaterial3D
var m_frame2: StandardMaterial3D
var m_rim: StandardMaterial3D
var m_bolt: StandardMaterial3D


func _init() -> void:
	transparent_bg = true
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	msaa_3d = Viewport.MSAA_4X
	if size.x <= 0 or size.y <= 0:
		size = Vector2i(533, 300)


func setup(vtype: int, team_color: Color) -> void:
	if _ready_done:
		return
	_ready_done = true
	_vtype = clampi(vtype, 0, VM.NUM_TYPES - 1)
	transparent_bg = true
	own_world_3d = true

	m_team = StandardMaterial3D.new()
	m_team.albedo_color = team_color.lerp(Color(0.36, 0.38, 0.3), 0.45).darkened(0.3)
	m_team.roughness = 0.8
	m_team.metallic_specular = 0.3
	m_glass = StandardMaterial3D.new()
	m_glass.albedo_color = Color(0.55, 0.7, 0.8, 0.07)
	m_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_glass.roughness = 0.05
	m_glass.metallic = 0.4
	m_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	m_frame = StandardMaterial3D.new()
	m_frame.albedo_color = Color(0.2, 0.215, 0.18)
	m_frame.roughness = 0.85
	m_frame2 = StandardMaterial3D.new()
	m_frame2.albedo_color = Color(0.1, 0.105, 0.1)
	m_frame2.roughness = 0.9
	m_rim = StandardMaterial3D.new()
	m_rim.albedo_color = Color(0.2, 0.21, 0.19)
	m_rim.roughness = 0.6
	m_rim.metallic = 0.4
	m_bolt = StandardMaterial3D.new()
	m_bolt.albedo_color = Color(0.32, 0.33, 0.3)
	m_bolt.roughness = 0.5
	m_bolt.metallic = 0.5

	_world = Node3D.new()
	_world.name = "VehicleViewWorld"
	add_child(_world)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.58)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 4.0
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)

	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.95, 0.85)
	key.light_energy = 1.0
	key.shadow_enabled = true
	key.shadow_bias = 0.03
	key.shadow_normal_bias = 1.0
	key.directional_shadow_max_distance = 4.0
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.transform = Transform3D(Basis.looking_at(Vector3(0.45, -0.8, 0.4).normalized(), Vector3.UP), Vector3.ZERO)
	_world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.75, 0.82, 1.0)
	fill.light_energy = 0.4
	fill.transform = Transform3D(Basis.looking_at(Vector3(0.6, 0.3, -0.7).normalized(), Vector3.UP), Vector3.ZERO)
	_world.add_child(fill)

	_model = VM.build(_vtype, "all", false)
	_world.add_child(_model)
	_retint(_model)
	_body = _model.get_node("Body") as Node3D
	_turret = _model.get_node("Turret") as Node3D
	_gun = _turret.find_child("Gun", true, false) as Node3D
	if _gun != null:
		_gun_rest = _gun.transform
	_steer = _body.find_child("Steer", true, false) as Node3D
	if _steer != null:
		_steer_rest = _steer.transform
	_wheel = _body.find_child("SteerWheel", true, false) as Node3D
	if _wheel != null:
		_wheel_rest = _wheel.transform

	_cam = Camera3D.new()
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.fov = 80.0
	_cam.near = 0.012
	_cam.far = 30.0
	_cam.current = true
	_world.add_child(_cam)
	_dress = Node3D.new()
	_dress.name = "Dress"
	_cam.add_child(_dress)
	_tdress = Node3D.new()
	_tdress.name = "TurretDress"
	_turret.add_child(_tdress)


func _retint(n: Node) -> void:
	var paint: Material = VM.paint_material()
	var glass: Material = VM.materials(false)["glass"]
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if mi.material_override == paint:
			mi.material_override = m_team
		elif mi.material_override == glass:
			mi.material_override = m_glass
	for c in n.get_children():
		_retint(c)


func _hide(path: String, hidden: bool) -> void:
	var n := _model.find_child(path, true, false) as Node3D
	if n != null:
		n.visible = not hidden


func _hide_path(base: Node3D, path: String, hidden: bool) -> void:
	if base == null:
		return
	var n := base.get_node_or_null(path) as Node3D
	if n != null:
		n.visible = not hidden


# -------------------------------------------------------------- dressing ----

func _plate(r: Rect2, mat: Material, depth: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	mi.mesh = bm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("depth", depth)
	_dress.add_child(mi)
	_plates.append([mi, r])
	return mi


## Armour frame around the view: top band ft, side bands fs, bottom band fb (fractions of the half
## screen, measured from the edge in NDC units 0..2). Inner edges get a lighter rim and bolts.
func _frame(ft: float, fs: float, fb: float, slant: float) -> void:
	if ft > 0.0:
		_plate(Rect2(-1.3, 1.0 - ft, 2.6, ft + 0.3), m_frame)
		_plate(Rect2(-1.3, 1.0 - ft - 0.02, 2.6, 0.03), m_rim, 0.0004)
		for i in 9:
			var x := -0.88 + 0.22 * float(i)
			_plate(Rect2(x - 0.01, 1.0 - ft * 0.45 - 0.018, 0.02, 0.036), m_bolt, 0.0004)
	if fs > 0.0:
		for s: float in [-1.0, 1.0]:
			var x0 := 1.0 - fs if s > 0.0 else -1.3
			_plate(Rect2(x0, -1.3, fs + 0.3, 2.6), m_frame)
			var xr := 1.0 - fs - 0.015 if s > 0.0 else -1.0 + fs - 0.015
			_plate(Rect2(xr, -1.3, 0.03, 2.6), m_rim, 0.0004)
			if slant > 0.0:
				# angled corner gusset where the roof edge meets the side
				var g := _plate(Rect2(x0 - slant * 0.5 if s > 0.0 else x0, 1.0 - ft - slant * 0.4, fs + 0.3 + slant * 0.5, slant), m_frame, 0.0002)
				g.set_meta("gusset", s)
	if fb > 0.0:
		_plate(Rect2(-1.3, -1.3, 2.6, fb + 0.3), m_frame2)
		_plate(Rect2(-1.3, -1.0 + fb - 0.005, 2.6, 0.03), m_rim, 0.001)


func _layout_plates() -> void:
	var hf := deg_to_rad(_cam.fov) * 0.5
	var d := 0.03
	var hw := d * tan(hf)
	var hh := hw * float(size.y) / maxf(1.0, float(size.x))
	for e: Array in _plates:
		var mi: MeshInstance3D = e[0]
		var r: Rect2 = e[1]
		var dep: float = mi.get_meta("depth", 0.0)
		var x0 := r.position.x * hw
		var x1 := r.end.x * hw
		var y0 := r.position.y * hh
		var y1 := r.end.y * hh
		var t := Transform3D(Basis.from_scale(Vector3(x1 - x0, y1 - y0, 0.0003)), Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, -d + dep))
		if mi.has_meta("gusset"):
			var s: float = mi.get_meta("gusset")
			t = Transform3D(Basis(Vector3(0, 0, 1), s * 0.5) * Basis.from_scale(Vector3(x1 - x0, y1 - y0, 0.0003)), t.origin)
		mi.transform = t


func _clear_dress() -> void:
	for c in _dress.get_children():
		c.queue_free()
	_plates.clear()
	for c in _tdress.get_children():
		c.queue_free()
	_breech = null
	if _sleeve != null:
		_sleeve.queue_free()
		_sleeve = null


func _box(p: Node3D, c: Vector3, s: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.material_override = mat
	mi.position = c
	p.add_child(mi)
	return mi


func _cylx(p: Node3D, x0: float, x1: float, y: float, z: float, r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = absf(x1 - x0)
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = mat
	mi.position = Vector3((x0 + x1) * 0.5, y, z)
	mi.rotation = Vector3(0, 0, -PI * 0.5)
	p.add_child(mi)
	return mi


func _configure(role: int) -> void:
	_role = role
	_clear_dress()
	# reset everything that a previous role may have hidden
	_turret.visible = true
	for nm: String in ["Roof", "Ring", "Rail", "Mantlet", "Driver", "Gunner", "Cab", "CabShell", "Windshield"]:
		_hide(nm, false)
	for rv in _model.find_children("Rivets*", "", true, false):
		(rv as Node3D).visible = true
	for base: Node3D in [_body, _turret]:
		for p: String in ["Driver/Head", "Driver/Torso", "Gunner/Head", "Gunner/Torso"]:
			_hide_path(base, p, false)
	var gunner_view := role != ROLE_DRIVER
	match _vtype:
		VM.TANK, VM.BRONEVIKS:
			# looking out through the vision blocks: roof fittings and the mantlet would intrude
			_hide("Roof", true)
			_hide("Ring", true)
			_hide("Rail", true)
			for rv in _model.find_children("Rivets*", "", true, false):
				(rv as Node3D).visible = false
			_hide("Mantlet", true)
			if gunner_view:
				_frame(0.15, 0.06, 0.0, 0.0)
				# recoil sleeve / breech running from the lower right corner into the barrel
				if _gun != null:
					var gm: Material = VM.materials(false)["gun"]
					var seats: Array = VM.SEAT[_vtype]
					var gseat: Vector3 = seats[1]
					var pv: Vector2 = VM.TURRET_PIVOT[_vtype]
					var cam_local_x := gseat.x - pv.x
					var x0 := minf(cam_local_x + 0.04 - _gun_rest.origin.x, -0.05)
					var r := 0.03 if _vtype == VM.TANK else 0.024
					_sleeve = Node3D.new()
					_gun.add_child(_sleeve)
					_cylx(_sleeve, x0, 0.0, 0.0, 0.0, r, gm)
					_cylx(_sleeve, x0, x0 + 0.05, 0.0, 0.0, r * 1.35, m_rim)
					_cylx(_sleeve, x0 * 0.45, x0 * 0.45 + 0.03, 0.0, 0.0, r * 1.2, m_rim)
					_box(_sleeve, Vector3(x0 * 0.6, -r * 1.1, 0.0), Vector3(-x0 * 0.7, r * 0.5, r * 1.6), m_rim)
			else:
				# driver: the turret is behind / around the head, show only the hull through the slit
				_turret.visible = false
				_frame(0.2, 0.07, 0.0, 0.0)
		VM.MOTO:
			if role == ROLE_DRIVER:
				_hide_path(_body, "Driver/Head", true)
				_hide_path(_body, "Driver/Torso", true)
			else:
				_hide_path(_turret, "Gunner/Head", true)
				_hide_path(_turret, "Gunner/Torso", true)
		VM.JEEP:
			if role == ROLE_DRIVER:
				_hide_path(_body, "Driver/Head", true)
				_hide_path(_body, "Driver/Torso", true)
				# the rear MG would sweep right past the driver's head
				_turret.visible = false
			else:
				_hide_path(_turret, "Gunner/Head", true)
				_hide_path(_turret, "Gunner/Torso", true)
		VM.ROCKET:
			if role == ROLE_DRIVER:
				# door pillars at the screen edges, the rest is the modelled cab interior
				_frame(0.0, 0.04, 0.0, 0.0)
			else:
				# the cab roof is above the gunner's eye: leave it out so it does not block the aim
				_hide("CabShell", true)
				_hide("Cab", true)
	_layout_plates()


# ------------------------------------------------------------------ pose ----

func update_pose(role: int, st: Dictionary) -> void:
	if not _ready_done:
		return
	var r := role
	if r != ROLE_SOLO and r != ROLE_DRIVER and r != ROLE_GUNNER:
		r = ROLE_GUNNER
	var hfov: float = st.get("hfov", 80.0)
	var t: float = st.get("time", 0.0)
	var speed: float = st.get("speed", 0.0)
	var steer: float = st.get("steer", 0.0)
	var kick: float = st.get("kick", 0.0)
	var trel: float = st.get("turret_rel", 0.0)
	var look: float = st.get("look", 0.0)      # driver head turn (rad, + = right)
	var gpitch: float = st.get("pitch", 0.0)   # gun elevation (rad, + = up)
	var seat_i := 0 if r == ROLE_DRIVER else 1
	var seats: Array = VM.SEAT[_vtype]
	var seat: Vector3 = seats[seat_i]
	var eye: float = st.get("eye", seat.y)
	_cam.fov = clampf(hfov, 30.0, 140.0)
	if r != _role:
		_configure(r)
	else:
		_layout_plates()

	_turret.rotation.y = -trel
	var pv: Vector2 = VM.TURRET_PIVOT[_vtype]
	var piv := Vector3(pv.x, 0.0, pv.y)
	var cpos: Vector3
	var yaw := -PI * 0.5
	if r == ROLE_DRIVER:
		cpos = seat
		yaw -= look
	else:
		cpos = piv + (seat - piv).rotated(Vector3.UP, -trel)
		yaw -= trel
	cpos.y = seat.y + clampf(eye - seat.y, -0.2, 0.2)

	# engine vibration, suspension bounce, body roll with steering
	var spd := clampf(absf(speed), 0.0, 1.0)
	var open_top := _vtype == VM.MOTO or _vtype == VM.JEEP
	var amp := (0.0012 + 0.0035 * spd) * (1.6 if open_top else 1.0)
	var vib := Vector3(sin(t * 31.0) * amp * 0.4, sin(t * 43.0) * amp + sin(t * 7.3) * amp * 1.5 * spd, cos(t * 37.0) * amp * 0.4)
	_model.position = vib
	var roll := -steer * spd * (0.05 if _vtype == VM.MOTO else 0.015)
	_model.rotation = Vector3(roll, 0.0, sin(t * 5.1) * 0.004 * spd)

	_cam.transform = Transform3D(Basis(Vector3.UP, yaw), cpos)

	# steering
	if _steer != null:
		_steer.transform = _steer_rest * Transform3D(Basis(Vector3(-0.2, 1.0, 0.0).normalized(), -steer * 0.35), Vector3.ZERO)
	if _wheel != null:
		_wheel.transform = _wheel_rest * Transform3D(Basis(Vector3.UP, -steer * 1.6), Vector3.ZERO)

	# recoil
	var k := clampf(kick, 0.0, 1.0)
	var back := 0.0
	match _vtype:
		VM.TANK:
			back = 0.09
		VM.BRONEVIKS:
			back = 0.05
		VM.MOTO, VM.JEEP:
			back = 0.018
		_:
			back = 0.0
	if _gun != null:
		var jit := 0.0
		if _vtype == VM.MOTO or _vtype == VM.JEEP:
			jit = sin(t * 90.0) * 0.012 * k
		var elev := gpitch if r != ROLE_DRIVER else 0.0
		_gun.transform = _gun_rest.rotated_local(Vector3(0, 0, 1), elev).translated_local(Vector3(-back * k, 0.0, 0.0)).rotated_local(Vector3(0, 0, 1), jit)
		if _vtype == VM.ROCKET:
			_gun.transform = _gun_rest.rotated_local(Vector3(0, 0, 1), elev - 0.02 * k)
	if _breech != null:
		_breech.transform = _breech_rest.translated(Vector3(-back * k, 0.0, 0.0))
