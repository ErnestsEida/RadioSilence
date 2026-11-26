extends SubViewport
## First-person weapon view models, built procedurally from primitive meshes.
##
## Usage:
##   var vm = preload("res://scripts/viewmodel.gd").new()
##   add_child(vm); vm.setup(team_color)
##   every frame: vm.size = low_res_size; vm.update_pose(weapon_id, state_dict)
##   draw vm.get_texture() full-screen over the game view.
##
## Weapon local space: +X right, +Y up, -Z forward (muzzle direction).
## Every gun is modelled so that its sight line lies on local y = 0, x = 0,
## so aiming simply means "identity rotation, origin on the camera axis".

const KNIFE := 0
const PISTOL := 1
const REVOLVER := 2
const RIFLE := 3
const SMG := 4
const SHOTGUN := 5
const SNIPER := 6
const LMG := 7
const BURST := 8
const DMR := 9
const MPISTOL := 10
const DBARREL := 11
const RPG := 12
const NUM_WEAPONS := 13

const BASE_FOV := 46.0
const WIND := 1.0 # flip to -1.0 if triangle winding is ever inverted


class Rig:
	var root: Node3D
	var hip_pos: Vector3 = Vector3(0.12, -0.1, -0.3)
	var hip_rot: Vector3 = Vector3.ZERO # degrees: pitch, yaw, roll
	var ads_pos: Vector3 = Vector3(0.0, 0.0, -0.2)
	var ads_fov: float = 50.0
	var can_ads: bool = true
	var pivot: Vector3 = Vector3(0.0, -0.1, 0.0)
	var muzzle: Vector3 = Vector3.ZERO
	var flash_scale: float = 1.0
	var kick_back: float = 0.04
	var kick_rot: float = 6.0
	var mag: Node3D = null
	var mag_rest: Vector3 = Vector3.ZERO
	var mag_grab: Vector3 = Vector3.ZERO # left hand position (weapon space) when holding the mag
	var left_arm: Node3D = null
	var left_hand: Vector3 = Vector3.ZERO # rest position of the left hand frame
	var right_arm: Node3D = null
	var anim: Node3D = null # slide / pump / bolt / cylinder / feed cover
	var anim2: Node3D = null
	var anim_rest: Transform3D = Transform3D.IDENTITY
	var anim2_rest: Transform3D = Transform3D.IDENTITY
	var hip_only: Array[Node3D] = [] # hidden when fully aimed (scope lenses)
	var ads_only: Array[Node3D] = [] # shown only when fully aimed (scope reticle)
	var extra: Node3D = null # e.g. shotgun shell in hand
	var icon_keep: Node3D = null # part of an arm that stays in the side-view icon (the knife)


var _ready_done := false
var _world: Node3D
var _cam: Camera3D
var _rigs: Array[Rig] = []
var _flash: Node3D
var _flash_light: OmniLight3D
var _throw_arm: Node3D
var _throw_nade: Node3D
var _fly_nade: Node3D
var _cur := -1

# materials
var m_gun: StandardMaterial3D
var m_gun2: StandardMaterial3D
var m_poly: StandardMaterial3D
var m_poly2: StandardMaterial3D
var m_dark: StandardMaterial3D
var m_steel: StandardMaterial3D
var m_stainless: StandardMaterial3D
var m_blade: StandardMaterial3D
var m_wood: StandardMaterial3D
var m_wood_dark: StandardMaterial3D
var m_brass: StandardMaterial3D
var m_tan: StandardMaterial3D
var m_od: StandardMaterial3D
var m_glove: StandardMaterial3D
var m_glove2: StandardMaterial3D
var m_sleeve: StandardMaterial3D
var m_cuff: StandardMaterial3D
var m_glass: StandardMaterial3D
var m_tint: StandardMaterial3D
var m_fiber: StandardMaterial3D
var m_reddot: StandardMaterial3D
var m_black: StandardMaterial3D
var m_shell: StandardMaterial3D
var m_nade: StandardMaterial3D
var m_flash: StandardMaterial3D
var m_scope_in: StandardMaterial3D


func _init() -> void:
	transparent_bg = true
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	msaa_3d = Viewport.MSAA_4X
	if size.x <= 0 or size.y <= 0:
		size = Vector2i(533, 300)


# ---------------------------------------------------------------- setup ----

func setup(team_color: Color) -> void:
	if _ready_done:
		return
	_ready_done = true
	transparent_bg = true
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_make_materials(team_color)

	_world = Node3D.new()
	_world.name = "ViewModelWorld"
	add_child(_world)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.46, 0.48, 0.55)
	env.ambient_light_energy = 0.55
	var sky := Sky.new()
	var psky := ProceduralSkyMaterial.new()
	psky.sky_top_color = Color(0.42, 0.47, 0.56)
	psky.sky_horizon_color = Color(0.62, 0.62, 0.62)
	psky.ground_bottom_color = Color(0.12, 0.11, 0.1)
	psky.ground_horizon_color = Color(0.4, 0.38, 0.36)
	sky.sky_material = psky
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 4.0
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)

	_cam = Camera3D.new()
	_cam.fov = BASE_FOV
	_cam.near = 0.01
	_cam.far = 20.0
	_cam.current = true
	_world.add_child(_cam)

	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.96, 0.9)
	key.light_energy = 1.35
	key.shadow_enabled = true
	key.shadow_bias = 0.02
	key.shadow_normal_bias = 1.0
	key.directional_shadow_max_distance = 3.0
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.transform = Transform3D(Basis.looking_at(Vector3(0.5, -0.75, -0.45).normalized(), Vector3.UP), Vector3.ZERO)
	_world.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.75, 0.82, 1.0)
	fill.light_energy = 0.35
	fill.transform = Transform3D(Basis.looking_at(Vector3(-0.6, 0.35, -0.7).normalized(), Vector3.UP), Vector3.ZERO)
	_world.add_child(fill)

	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.7, 0.82, 1.0)
	rim.light_energy = 0.9
	rim.transform = Transform3D(Basis.looking_at(Vector3(-0.55, -0.35, 0.75).normalized(), Vector3.UP), Vector3.ZERO)
	_world.add_child(rim)

	for i in NUM_WEAPONS:
		var r := Rig.new()
		r.root = Node3D.new()
		r.root.name = "W%d" % i
		r.root.visible = false
		_world.add_child(r.root)
		_rigs.append(r)
	_build_knife(_rigs[KNIFE])
	_build_pistol(_rigs[PISTOL])
	_build_revolver(_rigs[REVOLVER])
	_build_rifle(_rigs[RIFLE])
	_build_smg(_rigs[SMG])
	_build_shotgun(_rigs[SHOTGUN])
	_build_sniper(_rigs[SNIPER])
	_build_lmg(_rigs[LMG])
	_build_burst(_rigs[BURST])
	_build_dmr(_rigs[DMR])
	_build_mpistol(_rigs[MPISTOL])
	_build_dbarrel(_rigs[DBARREL])
	_build_rpg(_rigs[RPG])
	for r in _rigs:
		if r.mag != null:
			r.mag_rest = r.mag.position
		if r.anim != null:
			r.anim_rest = r.anim.transform
		if r.anim2 != null:
			r.anim2_rest = r.anim2.transform
	_build_flash()
	_build_throw_arm()


func _make_materials(team: Color) -> void:
	m_gun = _mat(Color(0.17, 0.175, 0.19), 0.42, 0.55)
	m_gun2 = _mat(Color(0.25, 0.255, 0.27), 0.45, 0.5)
	m_poly = _mat(Color(0.075, 0.075, 0.08), 0.68, 0.0)
	m_poly2 = _mat(Color(0.11, 0.11, 0.115), 0.62, 0.0)
	m_dark = _mat(Color(0.03, 0.03, 0.032), 0.8, 0.0)
	m_steel = _mat(Color(0.36, 0.37, 0.39), 0.32, 0.8)
	m_stainless = _mat(Color(0.62, 0.63, 0.65), 0.28, 0.85)
	m_blade = _mat(Color(0.72, 0.73, 0.75), 0.2, 0.9)
	m_wood = _mat(Color(0.34, 0.19, 0.1), 0.6, 0.0)
	m_wood_dark = _mat(Color(0.16, 0.08, 0.04), 0.7, 0.0)
	m_brass = _mat(Color(0.82, 0.6, 0.25), 0.3, 0.85)
	m_tan = _mat(Color(0.5, 0.42, 0.3), 0.8, 0.0)
	m_od = _mat(Color(0.24, 0.27, 0.17), 0.85, 0.0)
	m_glove = _mat(Color(0.33, 0.27, 0.19), 0.9, 0.0)
	m_glove2 = _mat(Color(0.1, 0.095, 0.09), 0.8, 0.0)
	var sl := team.lerp(Color(0.4, 0.4, 0.4), 0.35).darkened(0.45)
	m_sleeve = _mat(sl, 0.95, 0.0)
	m_sleeve.metallic_specular = 0.2
	m_cuff = _mat(sl.darkened(0.3), 0.95, 0.0)
	m_cuff.metallic_specular = 0.2
	m_glass = _mat(Color(0.08, 0.12, 0.2), 0.08, 0.6)
	m_glass.emission_enabled = true
	m_glass.emission = Color(0.05, 0.12, 0.2)
	m_tint = StandardMaterial3D.new()
	m_tint.albedo_color = Color(0.4, 0.7, 0.9, 0.18)
	m_tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_tint.roughness = 0.05
	m_tint.metallic = 0.5
	m_tint.cull_mode = BaseMaterial3D.CULL_DISABLED
	m_fiber = _mat(Color(1.0, 0.45, 0.05), 0.4, 0.0)
	m_fiber.emission_enabled = true
	m_fiber.emission = Color(1.0, 0.4, 0.05)
	m_fiber.emission_energy_multiplier = 1.5
	m_reddot = StandardMaterial3D.new()
	m_reddot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m_reddot.albedo_color = Color(1.0, 0.1, 0.08)
	m_black = StandardMaterial3D.new()
	m_black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m_black.albedo_color = Color(0.0, 0.0, 0.0)
	m_black.cull_mode = BaseMaterial3D.CULL_DISABLED
	m_shell = _mat(Color(0.7, 0.08, 0.06), 0.5, 0.0)
	m_nade = _mat(Color(0.26, 0.3, 0.18), 0.6, 0.15)
	m_scope_in = _mat(Color(0.12, 0.12, 0.13), 0.5, 0.3)
	m_scope_in.cull_mode = BaseMaterial3D.CULL_DISABLED
	m_flash = StandardMaterial3D.new()
	m_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m_flash.vertex_color_use_as_albedo = true
	m_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m_flash.cull_mode = BaseMaterial3D.CULL_DISABLED
	m_flash.no_depth_test = false


func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


# ------------------------------------------------------- mesh helpers ----

## weapon-space point from (forward, up, right)
func _P(f: float, u: float, x: float = 0.0) -> Vector3:
	return Vector3(x, u, -f)


func _p3(p: Vector2, x: float) -> Vector3:
	return Vector3(x, p.y, -p.x)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, hint: Vector3) -> void:
	var g := (b - a).cross(c - a)
	if g.length_squared() < 1e-16:
		return
	var bb := b
	var cc := c
	if g.dot(hint) * WIND > 0.0:
		bb = c
		cc = b
	var nrm := g.normalized()
	if nrm.dot(hint) < 0.0:
		nrm = -nrm
	st.set_normal(nrm)
	st.add_vertex(a)
	st.set_normal(nrm)
	st.add_vertex(bb)
	st.set_normal(nrm)
	st.add_vertex(cc)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, hint: Vector3) -> void:
	_tri(st, a, b, c, hint)
	_tri(st, a, c, d, hint)


## Extrudes a side profile (points are Vector2(forward, up)) across X with chamfered edges.
func _extrude(poly_in: PackedVector2Array, width: float, bevel: float) -> ArrayMesh:
	var poly := PackedVector2Array(poly_in)
	var n := poly.size()
	var area := 0.0
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	if area < 0.0:
		poly.reverse()
	var hw := width * 0.5
	var bv := clampf(bevel, 0.0, hw * 0.9)
	var xo := hw - bv
	var inset := PackedVector2Array()
	if bv > 0.0:
		for i in n:
			var p0: Vector2 = poly[(i - 1 + n) % n]
			var p1: Vector2 = poly[i]
			var p2: Vector2 = poly[(i + 1) % n]
			var e0 := (p1 - p0).normalized()
			var e1 := (p2 - p1).normalized()
			var n0 := Vector2(e0.y, -e0.x)
			var n1 := Vector2(e1.y, -e1.x)
			var bis := n0 + n1
			if bis.length() < 0.0001:
				bis = n0
			bis = bis.normalized()
			var d := maxf(bis.dot(n0), 0.35)
			inset.append(p1 - bis * (bv / d))
	else:
		inset = poly
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var e := (b - a).normalized()
		var nn := Vector3(0.0, -e.x, -e.y)
		_quad(st, _p3(a, -xo), _p3(b, -xo), _p3(b, xo), _p3(a, xo), nn)
		if bv > 0.0:
			var ia: Vector2 = inset[i]
			var ib: Vector2 = inset[(i + 1) % n]
			_quad(st, _p3(a, xo), _p3(b, xo), _p3(ib, hw), _p3(ia, hw), (nn + Vector3.RIGHT).normalized())
			_quad(st, _p3(a, -xo), _p3(b, -xo), _p3(ib, -hw), _p3(ia, -hw), (nn + Vector3.LEFT).normalized())
	var cap := inset
	var tris := Geometry2D.triangulate_polygon(cap)
	if tris.is_empty():
		cap = poly
		tris = Geometry2D.triangulate_polygon(cap)
	var t := 0
	while t + 2 < tris.size():
		var a: Vector2 = cap[tris[t]]
		var b: Vector2 = cap[tris[t + 1]]
		var c: Vector2 = cap[tris[t + 2]]
		_tri(st, _p3(a, hw), _p3(b, hw), _p3(c, hw), Vector3.RIGHT)
		_tri(st, _p3(a, -hw), _p3(b, -hw), _p3(c, -hw), Vector3.LEFT)
		t += 3
	return st.commit()


func _pv(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var i := 0
	while i + 1 < flat.size():
		var x: float = flat[i]
		var y: float = flat[i + 1]
		out.append(Vector2(x, y))
		i += 2
	return out


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot_deg
	parent.add_child(m)
	return m


## chamfered box; size is (width x, height y, depth z)
func _box(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO, bev: float = 0.0) -> MeshInstance3D:
	var mesh: Mesh
	if bev <= 0.0:
		var bm := BoxMesh.new()
		bm.size = sz
		mesh = bm
	else:
		var hz := sz.z * 0.5
		var hy := sz.y * 0.5
		var b := minf(bev, minf(hz, hy) * 0.9)
		var poly := PackedVector2Array([
			Vector2(-hz + b, -hy), Vector2(hz - b, -hy), Vector2(hz, -hy + b), Vector2(hz, hy - b),
			Vector2(hz - b, hy), Vector2(-hz + b, hy), Vector2(-hz, hy - b), Vector2(-hz, -hy + b)])
		mesh = _extrude(poly, sz.x, minf(b, sz.x * 0.45))
	return _mi(parent, mesh, mat, pos, rot_deg)


## side profile extruded across X, centred at x
func _prof(parent: Node3D, flat: Array, width: float, x: float, mat: Material, bev: float = 0.003) -> MeshInstance3D:
	return _mi(parent, _extrude(_pv(flat), width, bev), mat, Vector3(x, 0.0, 0.0))


func _cyl_mesh(r_top: float, r_bot: float, h: float, seg: int, caps: bool) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	c.cap_top = caps
	c.cap_bottom = caps
	return c


## cylinder along the forward axis from f0 to f1 (r1 = radius at the front end, <0 = same)
func _cyl(parent: Node3D, r: float, f0: float, f1: float, up: float, x: float, mat: Material, seg: int = 14, r1: float = -1.0, caps: bool = true) -> MeshInstance3D:
	var rf := r if r1 < 0.0 else r1
	var m := _cyl_mesh(rf, r, absf(f1 - f0), seg, caps)
	return _mi(parent, m, mat, _P((f0 + f1) * 0.5, up, x), Vector3(-90.0, 0.0, 0.0))


## cylinder between two arbitrary points (r0 at a, r1 at b)
func _limb(parent: Node3D, a: Vector3, b: Vector3, r0: float, r1: float, mat: Material, seg: int = 12) -> MeshInstance3D:
	var d := b - a
	var ln := d.length()
	var y := d / maxf(ln, 0.0001)
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	var m := MeshInstance3D.new()
	m.mesh = _cyl_mesh(r1, r0, ln, seg, true)
	m.material_override = mat
	m.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	parent.add_child(m)
	return m


func _ring(parent: Node3D, r_in: float, r_out: float, pos: Vector3, mat: Material, seg: int = 16) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = r_in
	t.outer_radius = r_out
	t.rings = seg
	t.ring_segments = 6
	return _mi(parent, t, mat, pos, Vector3(90.0, 0.0, 0.0))


func _sphere(parent: Node3D, r: float, pos: Vector3, mat: Material, seg: int = 10) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = maxi(seg / 2, 3)
	return _mi(parent, s, mat, pos)


## flat annulus in the XY plane (facing +Z) with per-edge colours
func _annulus(r_in: float, r_out: float, c_in: Color, c_out: Color, seg: int = 48) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var d0 := Vector3(cos(a0), sin(a0), 0.0)
		var d1 := Vector3(cos(a1), sin(a1), 0.0)
		st.set_color(c_in)
		st.add_vertex(d0 * r_in)
		st.set_color(c_out)
		st.add_vertex(d0 * r_out)
		st.set_color(c_out)
		st.add_vertex(d1 * r_out)
		st.set_color(c_in)
		st.add_vertex(d0 * r_in)
		st.set_color(c_out)
		st.add_vertex(d1 * r_out)
		st.set_color(c_in)
		st.add_vertex(d1 * r_in)
	return st.commit()


func _node(parent: Node3D, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees = rot_deg
	parent.add_child(n)
	return n


# --------------------------------------------------------------- hands ----

## Gloved hand wrapped around a grip. Frame: +Y along the grip (up), -Z = front strap,
## +X = outer side (for s = 1, right hand). Returns wrist point in frame space.
func _grip_hand(f: Node3D, gw: float, gd: float, s: float, trigger: bool) -> Vector3:
	var g := m_glove
	var top := 0.026 if trigger else 0.04
	var bot := -0.05
	var fh := top - bot
	var fy := (top + bot) * 0.5
	# back of the hand on the outer side
	_box(f, Vector3(0.026, 0.09, gd * 2.0 + 0.026), Vector3(s * (gw + 0.012), -0.004, 0.006), g, Vector3.ZERO, 0.01)
	_box(f, Vector3(0.008, 0.062, 0.032), Vector3(s * (gw + 0.026), -0.002, -0.006), m_glove2, Vector3.ZERO, 0.003)
	# fingers wrapped across the front strap, as one mass with grooves
	_box(f, Vector3(gw * 2.0 + 0.04, fh, 0.026), Vector3(s * 0.004, fy, -gd - 0.011), g, Vector3.ZERO, 0.009)
	var nf := 3 if trigger else 4
	for j in range(1, nf):
		var y: float = top - fh * float(j) / float(nf)
		_box(f, Vector3(gw * 2.0 + 0.042, 0.0035, 0.024), Vector3(s * 0.004, y, -gd - 0.0125), m_dark)
	# finger tips on the inner side
	_box(f, Vector3(0.02, fh - 0.004, 0.034), Vector3(-s * (gw + 0.009), fy, -gd + 0.006), g, Vector3.ZERO, 0.008)
	# heel of the hand round the back strap
	_box(f, Vector3(gw * 2.0 + 0.03, 0.072, 0.032), Vector3(s * 0.004, -0.012, gd + 0.011), g, Vector3.ZERO, 0.011)
	# thumb high on the inner side, pointing forward
	_box(f, Vector3(0.021, 0.023, 0.066), Vector3(-s * (gw + 0.01), 0.044, -0.006), g, Vector3(-6.0, 0.0, 0.0), 0.009)
	if trigger:
		_box(f, Vector3(0.019, 0.02, 0.046), Vector3(s * (gw + 0.004), 0.04, -gd - 0.016), g, Vector3(6.0, 0.0, 0.0), 0.008)
		_box(f, Vector3(0.018, 0.022, 0.018), Vector3(s * 0.005, 0.032, -gd - 0.036), g, Vector3.ZERO, 0.007)
	return Vector3(s * 0.008, -0.032, gd + 0.035)


## Support hand cupping a handguard of half-size hs. Frame: -Z along the barrel.
## Palm underneath, thumb along the left side, fingers curled up the right side.
func _cup_hand(f: Node3D, hs: float) -> Vector3:
	var g := m_glove
	_box(f, Vector3(hs * 2.0 + 0.014, 0.026, 0.088), Vector3(0.0, -hs - 0.013, 0.004), g, Vector3.ZERO, 0.01)
	_box(f, Vector3(0.028, hs * 1.4, 0.084), Vector3(-hs - 0.013, -hs * 0.45, 0.006), g, Vector3(0.0, 0.0, -12.0), 0.01)
	_box(f, Vector3(0.008, hs * 1.0, 0.05), Vector3(-hs - 0.029, -hs * 0.5, 0.008), m_glove2, Vector3(0.0, 0.0, -12.0), 0.003)
	# fingers up the right side + tips over the top
	_box(f, Vector3(0.022, hs * 1.7, 0.084), Vector3(hs + 0.01, -hs * 0.3, -0.0), g, Vector3(0.0, 0.0, 6.0), 0.009)
	_box(f, Vector3(0.02, 0.02, 0.08), Vector3(hs * 0.5, hs * 0.74, 0.0), g, Vector3(0.0, 0.0, -38.0), 0.008)
	for j in range(1, 4):
		var z: float = -0.042 + float(j) * 0.021
		_box(f, Vector3(0.024, hs * 1.6, 0.0035), Vector3(hs + 0.0105, -hs * 0.3, z), m_dark, Vector3(0.0, 0.0, 6.0))
	# thumb along the left side pointing forward
	_box(f, Vector3(0.021, 0.022, 0.068), Vector3(-hs - 0.009, hs * 0.15, -0.034), g, Vector3(0.0, -4.0, 0.0), 0.009)
	return Vector3(-hs * 0.6, -hs - 0.032, 0.05)

func _forearm(parent: Node3D, wrist: Vector3, elbow: Vector3) -> void:
	var dir := (elbow - wrist).normalized()
	_limb(parent, wrist - dir * 0.012, wrist + dir * 0.05, 0.03, 0.033, m_glove)
	_limb(parent, wrist + dir * 0.035, wrist + dir * 0.075, 0.043, 0.045, m_cuff)
	_limb(parent, wrist + dir * 0.06, wrist + dir * 0.2, 0.04, 0.047, m_sleeve)
	_limb(parent, wrist + dir * 0.19, wrist + dir * 0.215, 0.049, 0.049, m_cuff)
	_limb(parent, wrist + dir * 0.205, elbow, 0.047, 0.058, m_sleeve)


func _right_arm(r: Rig, grip_pos: Vector3, grip_rot: Vector3, gw: float, gd: float, elbow: Vector3, trigger: bool = true) -> Node3D:
	var arm := _node(r.root)
	var hf := _node(arm, grip_pos, grip_rot)
	var w := hf.transform * _grip_hand(hf, gw, gd, 1.0, trigger)
	_forearm(arm, w, elbow)
	r.right_arm = arm
	return arm


func _left_cup_arm(r: Rig, parent: Node3D, pos: Vector3, hs: float, elbow: Vector3, rot: Vector3 = Vector3.ZERO) -> Node3D:
	var arm := _node(parent)
	var hf := _node(arm, pos, rot)
	var w := hf.transform * _cup_hand(hf, hs)
	_forearm(arm, w, elbow)
	r.left_arm = arm
	r.left_hand = pos
	return arm


# ------------------------------------------------------------- weapons ----

func _build_knife(r: Rig) -> void:
	r.can_ads = false
	r.hip_pos = Vector3(0.16, -0.14, -0.36)
	r.hip_rot = Vector3(0.0, 8.0, -6.0)
	r.pivot = Vector3(0.0, 0.0, 0.0)
	r.flash_scale = 0.0
	# hand frame: knife handle runs along frame +Y, tilted forward
	var arm := _node(r.root)
	var hf0 := _node(arm, Vector3.ZERO, Vector3(-58.0, 18.0, 0.0))
	var hf := _node(hf0, Vector3.ZERO, Vector3(0.0, 40.0, 0.0))
	var w := hf0.transform * hf.transform * _grip_hand(hf, 0.012, 0.016, 1.0, false)
	_forearm(arm, w, w + Vector3(0.14, -0.3, 0.2))
	r.right_arm = arm
	# knife in the same frame. blade edge faces -Z, spine +Z
	var k := _node(hf)
	k.scale = Vector3(1.15, 1.2, 1.15)
	_box(k, Vector3(0.022, 0.11, 0.03), Vector3(0.0, -0.005, 0.0), m_poly, Vector3.ZERO, 0.008)
	for j in 3:
		_box(k, Vector3(0.024, 0.004, 0.032), Vector3(0.0, -0.045 + float(j) * 0.03, 0.0), m_poly2, Vector3.ZERO, 0.0)
	_box(k, Vector3(0.026, 0.016, 0.034), Vector3(0.0, -0.066, 0.0), m_gun, Vector3.ZERO, 0.005) # pommel
	_box(k, Vector3(0.028, 0.008, 0.062), Vector3(0.0, 0.054, -0.004), m_gun, Vector3.ZERO, 0.003) # guard
	# blade profile in (forward=-Z, up=+Y) of the knife frame, extruded thin along X
	var blade := _prof(k, [-0.013, 0.058, 0.015, 0.058, 0.017, 0.15, 0.012, 0.2, 0.0, 0.235, -0.006, 0.222, -0.002, 0.2, -0.013, 0.19], 0.0055, 0.0, m_blade, 0.0024)
	blade.position = Vector3.ZERO
	_box(k, Vector3(0.0058, 0.11, 0.004), Vector3(0.0, 0.12, 0.004), m_steel, Vector3.ZERO, 0.0) # fuller
	_prof(k, [-0.013, 0.058, -0.004, 0.058, -0.006, 0.17, -0.013, 0.186], 0.006, 0.0, m_gun, 0.0) # serrated spine
	r.icon_keep = k


func _build_pistol(r: Rig) -> void:
	r.hip_pos = Vector3(0.135, -0.033, -0.39)
	r.hip_rot = Vector3(2.0, 20.0, -12.0)
	r.ads_pos = Vector3(0.0, 0.0, -0.32 - 0.0)
	r.ads_fov = 50.0
	r.pivot = _P(0.0, -0.09)
	r.muzzle = _P(0.165, -0.022)
	r.flash_scale = 0.65
	r.kick_back = 0.035
	r.kick_rot = 9.0
	var R := r.root
	# slide
	var sl := _node(R)
	_prof(sl, [-0.032, -0.036, 0.157, -0.036, 0.16, -0.013, 0.152, -0.006, -0.026, -0.006, -0.032, -0.012], 0.026, 0.0, m_gun, 0.003)
	for j in 5:
		_box(sl, Vector3(0.0275, 0.018, 0.0025), _P(-0.024 + float(j) * 0.0055, -0.02), m_dark)
	_box(sl, Vector3(0.012, 0.002, 0.032), _P(0.05, -0.0058, 0.002), m_dark)
	_box(sl, Vector3(0.011, 0.003, 0.03), _P(0.05, -0.0075, 0.002), m_steel)
	# sights: top of rear ears and front post on y = 0
	_box(sl, Vector3(0.022, 0.004, 0.009), _P(-0.02, -0.006), m_gun)
	_box(sl, Vector3(0.007, 0.007, 0.009), _P(-0.02, -0.0035, 0.0068), m_gun, Vector3.ZERO, 0.0015)
	_box(sl, Vector3(0.007, 0.007, 0.009), _P(-0.02, -0.0035, -0.0068), m_gun, Vector3.ZERO, 0.0015)
	_box(sl, Vector3(0.0038, 0.0068, 0.007), _P(0.145, -0.0034), m_fiber)
	r.anim = sl
	# frame
	_prof(R, [-0.034, -0.036, 0.15, -0.036, 0.152, -0.053, 0.062, -0.053, 0.05, -0.058, -0.004, -0.058, -0.03, -0.05], 0.0235, 0.0, m_poly, 0.003)
	_box(R, Vector3(0.026, 0.008, 0.06), _P(0.115, -0.056), m_poly2, Vector3.ZERO, 0.002)
	# grip
	_prof(R, [-0.036, -0.05, 0.008, -0.052, 0.004, -0.072, -0.012, -0.158, -0.052, -0.158, -0.05, -0.11, -0.053, -0.062, -0.05, -0.045], 0.03, 0.0, m_poly, 0.005)
	# trigger guard and trigger
	_box(R, Vector3(0.009, 0.0065, 0.05), _P(0.033, -0.082), m_poly, Vector3.ZERO, 0.002)
	_box(R, Vector3(0.009, 0.03, 0.0065), _P(0.058, -0.068), m_poly, Vector3(-18.0, 0.0, 0.0), 0.002)
	_box(R, Vector3(0.006, 0.018, 0.006), _P(0.022, -0.067), m_dark, Vector3(-10.0, 0.0, 0.0))
	# magazine (base plate visible, body hidden in the grip)
	var mg := _node(R, _P(-0.03, -0.1))
	_box(mg, Vector3(0.021, 0.1, 0.03), Vector3(0.0, -0.005, -0.002), m_gun, Vector3(-12.0, 0.0, 0.0), 0.003)
	_box(mg, Vector3(0.032, 0.009, 0.046), Vector3(0.0, -0.061, 0.006), m_poly2, Vector3(-12.0, 0.0, 0.0), 0.003)
	r.mag = mg
	r.mag_grab = _P(-0.035, -0.2, -0.02)
	# hands: right on the grip, left wrapped over it (mirrored)
	var gp := _P(-0.024, -0.108)
	var grot := Vector3(-16.0, 0.0, 0.0)
	_right_arm(r, gp, grot, 0.0155, 0.024, _P(-0.26, -0.3, 0.24))
	var la := _node(R)
	var hf := _node(la, gp + Vector3(-0.012, -0.016, -0.006), grot + Vector3(0.0, -10.0, 0.0))
	hf.scale = Vector3(1.06, 1.06, 1.06)
	var w := hf.transform * _grip_hand(hf, 0.017, 0.026, -1.0, false)
	_forearm(la, w, _P(-0.24, -0.32, -0.26))
	r.left_arm = la
	r.left_hand = Vector3.ZERO


func _build_revolver(r: Rig) -> void:
	r.hip_pos = Vector3(0.135, -0.035, -0.41)
	r.hip_rot = Vector3(2.0, 20.0, -12.0)
	r.ads_pos = Vector3(0.0, 0.0, -0.33)
	r.ads_fov = 50.0
	r.pivot = _P(0.0, -0.09)
	r.muzzle = _P(0.255, -0.035)
	r.flash_scale = 1.0
	r.kick_back = 0.045
	r.kick_rot = 14.0
	var R := r.root
	# frame
	_prof(R, [-0.048, -0.008, 0.058, -0.008, 0.062, -0.058, 0.03, -0.066, -0.004, -0.07, -0.036, -0.064, -0.052, -0.034], 0.024, 0.0, m_stainless, 0.003)
	# barrel with full under-lug and top rib
	_prof(R, [0.056, -0.012, 0.25, -0.012, 0.25, -0.064, 0.13, -0.064, 0.062, -0.06], 0.022, 0.0, m_stainless, 0.004)
	_box(R, Vector3(0.012, 0.005, 0.19), _P(0.155, -0.0085), m_steel, Vector3.ZERO, 0.0015)
	_prof(R, [0.215, -0.006, 0.244, -0.006, 0.244, 0.0, 0.233, 0.0], 0.0045, 0.0, m_fiber, 0.0)
	_box(R, Vector3(0.0225, 0.003, 0.11), _P(0.17, -0.05), m_steel) # lug flat line
	# rear notch on the top strap
	_box(R, Vector3(0.006, 0.008, 0.012), _P(-0.032, -0.004, 0.0058), m_steel, Vector3.ZERO, 0.0015)
	_box(R, Vector3(0.006, 0.008, 0.012), _P(-0.032, -0.004, -0.0058), m_steel, Vector3.ZERO, 0.0015)
	# hammer
	_prof(R, [-0.052, -0.022, -0.036, -0.022, -0.042, -0.006, -0.068, -0.004, -0.066, -0.011, -0.054, -0.014], 0.008, 0.0, m_steel, 0.002)
	# cylinder: crane pivot below-left, spin node at the bore axis
	var crane := _node(R, _P(0.0, -0.058, -0.011))
	var spin := _node(crane, Vector3(0.011, 0.023, 0.0))
	var cyl := _cyl(spin, 0.0225, -0.0005, 0.047, 0.0, 0.0, m_stainless, 18)
	cyl.position = _P(0.0235, 0.0)
	for j in 6:
		var a := TAU * float(j) / 6.0 + PI / 6.0
		var fl := _cyl(spin, 0.0045, 0.008, 0.04, 0.0, 0.0, m_dark, 6)
		fl.position = _P(0.024, sin(a) * 0.021, cos(a) * 0.021)
	_cyl(spin, 0.006, 0.047, 0.06, 0.0, 0.0, m_steel, 8)
	r.anim = crane
	r.anim2 = spin
	_cyl(R, 0.0045, 0.06, 0.13, -0.052, 0.0, m_steel, 8) # ejector rod
	# grip (wood) with metal back strap
	_prof(R, [-0.048, -0.055, -0.006, -0.066, -0.014, -0.11, -0.026, -0.168, -0.078, -0.168, -0.074, -0.11, -0.066, -0.058], 0.034, 0.0, m_wood, 0.006)
	_prof(R, [-0.066, -0.05, -0.052, -0.035, -0.07, -0.11, -0.077, -0.168, -0.083, -0.168, -0.08, -0.11], 0.016, 0.0, m_stainless, 0.002)
	_box(R, Vector3(0.0355, 0.012, 0.018), _P(-0.045, -0.13, 0.0), m_wood_dark, Vector3(-14.0, 0.0, 0.0), 0.003)
	# trigger guard and trigger
	_box(R, Vector3(0.009, 0.0065, 0.052), _P(0.026, -0.088), m_stainless, Vector3.ZERO, 0.002)
	_box(R, Vector3(0.009, 0.028, 0.0065), _P(0.052, -0.076), m_stainless, Vector3(-15.0, 0.0, 0.0), 0.002)
	_box(R, Vector3(0.006, 0.02, 0.007), _P(0.014, -0.074), m_steel, Vector3(-12.0, 0.0, 0.0))
	var gp := _P(-0.042, -0.112)
	var grot := Vector3(-20.0, 0.0, 0.0)
	_right_arm(r, gp, grot, 0.0165, 0.026, _P(-0.26, -0.31, 0.24))
	var la := _node(R)
	var hf := _node(la, gp + Vector3(-0.013, -0.016, -0.006), grot + Vector3(0.0, -10.0, 0.0))
	hf.scale = Vector3(1.06, 1.06, 1.06)
	var w := hf.transform * _grip_hand(hf, 0.018, 0.028, -1.0, false)
	_forearm(la, w, _P(-0.24, -0.33, -0.26))
	r.left_arm = la
	r.left_hand = Vector3.ZERO
	r.mag_grab = _P(0.03, -0.06, -0.06)
	# speed-loader rounds held by the left hand during reload
	var sp := _node(la, _P(0.0, -0.06, -0.05))
	for j in 6:
		var a := TAU * float(j) / 6.0
		_cyl(sp, 0.0042, 0.0, 0.014, sin(a) * 0.012, cos(a) * 0.012, m_brass, 8)
	_cyl(sp, 0.016, -0.012, 0.0, 0.0, 0.0, m_poly, 12)
	sp.visible = false
	r.extra = sp


func _build_rifle(r: Rig) -> void:
	r.hip_pos = Vector3(0.165, -0.062, -0.47)
	r.hip_rot = Vector3(2.0, 5.0, -12.0)
	r.ads_pos = Vector3(0.0, 0.0, -0.26)
	r.ads_fov = 46.0
	r.pivot = _P(0.0, -0.1)
	r.muzzle = _P(0.6, -0.065)
	r.flash_scale = 1.0
	r.kick_back = 0.03
	r.kick_rot = 3.5
	var R := r.root
	var bore := -0.065
	# upper receiver + rail
	_box(R, Vector3(0.034, 0.05, 0.27), _P(0.04, -0.06), m_gun, Vector3.ZERO, 0.005)
	_box(R, Vector3(0.023, 0.009, 0.25), _P(0.045, -0.0315), m_gun, Vector3.ZERO, 0.002)
	for j in 11:
		_box(R, Vector3(0.025, 0.004, 0.009), _P(-0.065 + float(j) * 0.023, -0.026), m_gun2)
	_box(R, Vector3(0.05, 0.009, 0.014), _P(-0.092, -0.04), m_poly2, Vector3.ZERO, 0.003) # charging handle
	_cyl(R, 0.0085, -0.085, -0.045, -0.05, 0.02, m_gun2, 10) # forward assist
	_box(R, Vector3(0.002, 0.016, 0.06), _P(0.03, -0.065, 0.0175), m_dark) # ejection port
	_box(R, Vector3(0.004, 0.009, 0.018), _P(0.0, -0.093, -0.017), m_gun2) # bolt catch
	# lower receiver, mag well
	_prof(R, [-0.085, -0.085, 0.125, -0.085, 0.125, -0.128, 0.058, -0.128, 0.05, -0.115, -0.03, -0.115, -0.085, -0.1], 0.032, 0.0, m_gun, 0.004)
	_box(R, Vector3(0.0325, 0.012, 0.02), _P(0.04, -0.11, 0.0), m_gun2, Vector3.ZERO, 0.002) # mag release area
	# pistol grip
	_prof(R, [-0.038, -0.108, 0.002, -0.108, -0.022, -0.205, -0.068, -0.21, -0.064, -0.19, -0.048, -0.13], 0.03, 0.0, m_poly, 0.006)
	# trigger guard + trigger
	_box(R, Vector3(0.008, 0.006, 0.07), _P(0.018, -0.136), m_gun, Vector3.ZERO, 0.002)
	_box(R, Vector3(0.006, 0.018, 0.006), _P(0.012, -0.124), m_dark, Vector3(-12.0, 0.0, 0.0))
	# magazine (tan polymer, curved)
	var mg := _node(R, _P(0.09, -0.125))
	_prof(mg, [-0.025, 0.0, 0.025, 0.0, 0.038, -0.09, 0.052, -0.175, 0.0, -0.184, -0.012, -0.095], 0.025, 0.0, m_tan, 0.004)
	_box(mg, Vector3(0.028, 0.012, 0.058), Vector3(0.0, -0.183, -0.026), m_tan, Vector3(-10.0, 0.0, 0.0), 0.004)
	for j in 3:
		_box(mg, Vector3(0.026, 0.003, 0.03), Vector3(0.0, -0.03 - float(j) * 0.035, -0.002 - float(j) * 0.009), m_dark)
	r.mag = mg
	r.mag_grab = _P(0.11, -0.25, 0.0)
	# buffer tube + stock
	_cyl(R, 0.015, -0.3, -0.085, -0.062, 0.0, m_gun, 12)
	_prof(R, [-0.19, -0.042, -0.335, -0.044, -0.34, -0.155, -0.305, -0.155, -0.235, -0.088, -0.19, -0.086], 0.04, 0.0, m_poly, 0.006)
	# rear BUIS: aperture ring centred on the sight line
	_box(R, Vector3(0.024, 0.014, 0.03), _P(-0.06, -0.02), m_poly2, Vector3.ZERO, 0.002)
	_box(R, Vector3(0.006, 0.02, 0.016), _P(-0.06, -0.008, 0.0105), m_poly2, Vector3.ZERO, 0.0015)
	_box(R, Vector3(0.006, 0.02, 0.016), _P(-0.06, -0.008, -0.0105), m_poly2, Vector3.ZERO, 0.0015)
	_ring(R, 0.0042, 0.0078, _P(-0.06, 0.0), m_poly2, 14)
	# handguard
	_box(R, Vector3(0.052, 0.052, 0.2), _P(0.27, bore), m_poly, Vector3.ZERO, 0.014)
	_box(R, Vector3(0.022, 0.008, 0.2), _P(0.27, bore + 0.03), m_poly2, Vector3.ZERO, 0.002)
	for j in 4:
		_box(R, Vector3(0.054, 0.012, 0.022), _P(0.205 + float(j) * 0.04, bore - 0.004), m_dark, Vector3.ZERO, 0.003)
	_cyl(R, 0.031, 0.16, 0.172, bore, 0.0, m_gun, 16) # delta ring
	# barrel, front sight base, flash hider
	_cyl(R, 0.0085, 0.37, 0.545, bore, 0.0, m_gun, 12)
	_prof(R, [0.375, -0.077, 0.412, -0.077, 0.407, -0.052, 0.398, -0.014, 0.386, -0.014, 0.379, -0.052], 0.02, 0.0, m_gun, 0.003)
	_box(R, Vector3(0.0035, 0.016, 0.014), _P(0.392, -0.007, 0.0085), m_gun)
	_box(R, Vector3(0.0035, 0.016, 0.014), _P(0.392, -0.007, -0.0085), m_gun)
	_box(R, Vector3(0.0035, 0.014, 0.0035), _P(0.392, -0.007), m_gun2) # post, top at y = 0
	_cyl(R, 0.011, 0.53, 0.595, bore, 0.0, m_gun2, 8)
	for j in 4:
		var a := TAU * float(j) / 4.0 + PI / 4.0
		_box(R, Vector3(0.003, 0.003, 0.04), _P(0.575, bore + sin(a) * 0.0105, cos(a) * 0.0105), m_dark)
	# hands
	_right_arm(r, _P(-0.044, -0.158), Vector3(-20.0, 0.0, 0.0), 0.015, 0.023, _P(-0.4, -0.3, 0.14))
	_left_cup_arm(r, R, _P(0.27, bore), 0.026, _P(0.02, -0.42, -0.24), Vector3(0.0, 0.0, 0.0))


func _build_smg(r: Rig) -> void:
	r.hip_pos = Vector3(0.16, -0.068, -0.46)
	r.hip_rot = Vector3(2.0, 5.0, -12.0)
	r.ads_pos = Vector3(0.0, 0.0, -0.16 - 0.0325)
	r.ads_fov = 46.0
	r.pivot = _P(0.0, -0.1)
	r.muzzle = _P(0.39, -0.058)
	r.flash_scale = 0.75
	r.kick_back = 0.025
	r.kick_rot = 2.5
	var R := r.root
	var bore := -0.058
	# receiver (stamped steel)
	_box(R, Vector3(0.034, 0.05, 0.25), _P(0.035, bore), m_gun, Vector3.ZERO, 0.013)
	_cyl(R, 0.0095, 0.15, 0.335, -0.037, 0.0, m_gun, 12) # cocking tube
	_box(R, Vector3(0.006, 0.008, 0.03), _P(0.25, -0.034, -0.012), m_poly2, Vector3(0.0, 0.0, 0.0), 0.002) # cocking handle
	_box(R, Vector3(0.002, 0.014, 0.05), _P(0.03, bore - 0.002, 0.0172), m_dark)
	# lower / trigger group + grip (polymer)
	_prof(R, [-0.085, -0.078, 0.052, -0.078, 0.052, -0.098, 0.0, -0.104, -0.068, -0.1], 0.031, 0.0, m_poly, 0.004)
	_prof(R, [-0.048, -0.094, -0.01, -0.094, -0.03, -0.185, -0.072, -0.19, -0.068, -0.165], 0.03, 0.0, m_poly, 0.006)
	_box(R, Vector3(0.008, 0.006, 0.055), _P(0.02, -0.115), m_poly, Vector3.ZERO, 0.002)
	_box(R, Vector3(0.006, 0.016, 0.006), _P(0.012, -0.105), m_dark, Vector3(-12.0, 0.0, 0.0))
	# handguard (slim, slightly bulbous)
	_prof(R, [0.16, -0.036, 0.325, -0.04, 0.335, -0.06, 0.325, -0.088, 0.17, -0.09, 0.16, -0.075], 0.046, 0.0, m_poly, 0.012)
	for j in 5:
		_box(R, Vector3(0.047, 0.004, 0.012), _P(0.19 + float(j) * 0.027, -0.083), m_dark)
	# front sight hood + barrel
	_box(R, Vector3(0.016, 0.02, 0.016), _P(0.345, -0.034), m_gun, Vector3.ZERO, 0.003)
	_ring(R, 0.009, 0.013, _P(0.345, -0.017), m_gun, 14)
	_cyl(R, 0.0095, 0.33, 0.395, bore, 0.0, m_gun2, 12)
	_cyl(R, 0.0125, 0.33, 0.348, bore, 0.0, m_gun, 12)
	# rear drum sight
	_box(R, Vector3(0.026, 0.016, 0.02), _P(-0.07, -0.03), m_gun, Vector3.ZERO, 0.004)
	# magazine (steel, strongly curved)
	var mg := _node(R, _P(0.078, -0.082))
	_prof(mg, [-0.017, 0.0, 0.017, 0.0, 0.042, -0.08, 0.075, -0.16, 0.045, -0.172, 0.015, -0.09], 0.02, 0.0, m_gun2, 0.003)
	_box(mg, Vector3(0.024, 0.01, 0.036), Vector3(0.0, -0.168, -0.06), m_gun, Vector3(-25.0, 0.0, 0.0), 0.003)
	r.mag = mg
	r.mag_grab = _P(0.13, -0.2, 0.0)
	# collapsing stock
	_cyl(R, 0.006, -0.3, -0.09, -0.048, 0.014, m_gun, 8)
	_cyl(R, 0.006, -0.3, -0.09, -0.048, -0.014, m_gun, 8)
	_box(R, Vector3(0.042, 0.085, 0.016), _P(-0.305, -0.08), m_poly, Vector3.ZERO, 0.006)
	_box(R, Vector3(0.036, 0.012, 0.03), _P(-0.09, -0.048), m_gun, Vector3.ZERO, 0.003)
	# top rail mount + red dot sight
	_box(R, Vector3(0.022, 0.012, 0.14), _P(0.0, -0.028), m_gun, Vector3.ZERO, 0.002)
	_box(R, Vector3(0.024, 0.014, 0.036), _P(-0.01, -0.017), m_poly, Vector3.ZERO, 0.003)
	_cyl(R, 0.0175, -0.0325, 0.0125, 0.0, 0.0, m_scope_in, 16, -1.0, false)
	_ring(R, 0.0148, 0.0195, _P(-0.0325, 0.0), m_poly, 18)
	_ring(R, 0.0148, 0.0195, _P(0.0125, 0.0), m_poly, 18)
	_box(R, Vector3(0.008, 0.008, 0.012), _P(-0.01, 0.019), m_poly, Vector3.ZERO, 0.002) # turret
	_box(R, Vector3(0.008, 0.008, 0.012), _P(-0.01, 0.0, 0.019), m_poly, Vector3.ZERO, 0.002)
	var lens := _cyl(R, 0.0152, 0.0095, 0.0105, 0.0, 0.0, m_tint, 18)
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dot := _sphere(R, 0.0009, _P(0.009, 0.0), m_reddot, 8)
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# hands
	_right_arm(r, _P(-0.04, -0.14), Vector3(-18.0, 0.0, 0.0), 0.015, 0.022, _P(-0.4, -0.29, 0.14))
	_left_cup_arm(r, R, _P(0.25, -0.064), 0.024, _P(0.02, -0.42, -0.22))


func _build_shotgun(r: Rig) -> void:
	r.hip_pos = Vector3(0.17, -0.065, -0.48)
	r.hip_rot = Vector3(2.0, 5.0, -12.0)
	r.ads_pos = Vector3(0.0, 0.0, -0.25)
	r.ads_fov = 50.0
	r.pivot = _P(-0.05, -0.08)
	r.muzzle = _P(0.65, -0.026)
	r.flash_scale = 1.45
	r.kick_back = 0.06
	r.kick_rot = 9.0
	var R := r.root
	# receiver
	_prof(R, [-0.088, -0.014, 0.12, -0.014, 0.12, -0.072, 0.03, -0.078, -0.088, -0.074], 0.034, 0.0, m_gun, 0.004)
	_box(R, Vector3(0.002, 0.022, 0.06), _P(0.04, -0.04, 0.0172), m_dark) # ejection port
	_box(R, Vector3(0.002, 0.012, 0.08), _P(0.02, -0.06, -0.0172), m_gun2) # left side relief line
	# barrel, vent rib, magazine tube
	_cyl(R, 0.0115, 0.12, 0.645, -0.026, 0.0, m_gun, 14)
	_box(R, Vector3(0.008, 0.005, 0.52), _P(0.385, -0.0125), m_gun2)
	_cyl(R, 0.0112, 0.12, 0.56, -0.052, 0.0, m_gun, 12)
	_cyl(R, 0.0125, 0.56, 0.585, -0.052, 0.0, m_gun2, 12)
	_box(R, Vector3(0.016, 0.042, 0.016), _P(0.548, -0.04), m_gun2, Vector3.ZERO, 0.003) # barrel clamp
	_sphere(R, 0.0028, _P(0.632, -0.0018), m_brass, 8) # bead
	# ghost ring rear sight
	_box(R, Vector3(0.026, 0.008, 0.03), _P(-0.06, -0.011), m_gun, Vector3.ZERO, 0.002)
	_box(R, Vector3(0.005, 0.016, 0.014), _P(-0.06, -0.002, 0.0115), m_gun, Vector3.ZERO, 0.0015)
	_box(R, Vector3(0.005, 0.016, 0.014), _P(-0.06, -0.002, -0.0115), m_gun, Vector3.ZERO, 0.0015)
	_ring(R, 0.0048, 0.0078, _P(-0.06, 0.0), m_gun, 14)
	# stock (wood), butt pad
	_prof(R, [-0.088, -0.018, -0.088, -0.074, -0.12, -0.092, -0.15, -0.125, -0.385, -0.155, -0.4, -0.15, -0.4, -0.052, -0.37, -0.048, -0.16, -0.066, -0.115, -0.042], 0.036, 0.0, m_wood, 0.008)
	_prof(R, [-0.4, -0.152, -0.416, -0.153, -0.416, -0.05, -0.4, -0.05], 0.038, 0.0, m_poly, 0.004)
	# trigger guard and trigger
	_box(R, Vector3(0.009, 0.007, 0.07), _P(-0.04, -0.098), m_gun, Vector3.ZERO, 0.002)
	_box(R, Vector3(0.009, 0.025, 0.007), _P(-0.006, -0.087), m_gun, Vector3(-10.0, 0.0, 0.0), 0.002)
	_box(R, Vector3(0.006, 0.02, 0.006), _P(-0.042, -0.085), m_dark, Vector3(-12.0, 0.0, 0.0))
	# pump (wood with grooves) + action bars; left hand rides on it
	var pump := _node(R)
	_box(pump, Vector3(0.05, 0.044, 0.17), _P(0.3, -0.05), m_wood, Vector3.ZERO, 0.014)
	for j in 6:
		_box(pump, Vector3(0.0515, 0.0455, 0.0045), _P(0.235 + float(j) * 0.026, -0.05), m_wood_dark, Vector3.ZERO, 0.013)
	_box(pump, Vector3(0.004, 0.006, 0.17), _P(0.13, -0.056, 0.0145), m_steel)
	_box(pump, Vector3(0.004, 0.006, 0.17), _P(0.13, -0.056, -0.0145), m_steel)
	r.anim = pump
	_right_arm(r, _P(-0.128, -0.085), Vector3(-50.0, 0.0, 0.0), 0.015, 0.022, _P(-0.42, -0.28, 0.12), true)
	_left_cup_arm(r, pump, _P(0.3, -0.05), 0.025, _P(0.04, -0.42, -0.24))
	r.mag_grab = _P(0.06, -0.11, -0.01)
	# a shell for the left hand during reload
	var sh := _node(r.left_arm, _P(0.3, -0.085, 0.0))
	_cyl(sh, 0.0095, -0.03, 0.035, 0.0, 0.0, m_shell, 10)
	_cyl(sh, 0.0102, -0.045, -0.03, 0.0, 0.0, m_brass, 10)
	sh.visible = false
	r.extra = sh


func _build_sniper(r: Rig) -> void:
	r.hip_pos = Vector3(0.17, -0.072, -0.5)
	r.hip_rot = Vector3(2.0, 5.0, -12.0)
	r.ads_pos = Vector3(0.0, 0.0, -0.075 - 0.14)
	r.ads_fov = 30.0
	r.pivot = _P(0.0, -0.1)
	r.muzzle = _P(0.74, -0.055)
	r.flash_scale = 1.35
	r.kick_back = 0.07
	r.kick_rot = 10.0
	var R := r.root
	var bore := -0.055
	# receiver + barrel + muzzle brake
	_cyl(R, 0.0165, -0.07, 0.15, bore, 0.0, m_gun, 16)
	_box(R, Vector3(0.003, 0.012, 0.055), _P(0.04, bore + 0.002, 0.0165), m_dark) # ejection port
	_cyl(R, 0.0125, 0.15, 0.7, bore, 0.0, m_gun, 14, 0.0095)
	_box(R, Vector3(0.026, 0.024, 0.05), _P(0.72, bore), m_gun2, Vector3.ZERO, 0.004)
	for j in 3:
		_box(R, Vector3(0.0265, 0.012, 0.006), _P(0.705 + float(j) * 0.013, bore), m_dark)
	# stock / chassis (OD green) with grip and cheek riser
	_prof(R, [0.37, -0.06, 0.37, -0.086, 0.1, -0.09, 0.045, -0.1, 0.035, -0.112, -0.018, -0.112, -0.028, -0.172, -0.072, -0.178, -0.068, -0.12, -0.12, -0.096, -0.36, -0.124, -0.372, -0.11, -0.372, -0.034, -0.335, -0.03, -0.16, -0.05, -0.075, -0.05, -0.06, -0.062], 0.04, 0.0, m_od, 0.007)
	_prof(R, [-0.33, -0.028, -0.18, -0.03, -0.18, -0.018, -0.32, -0.014], 0.03, 0.0, m_od, 0.004)
	_prof(R, [-0.372, -0.126, -0.39, -0.128, -0.39, -0.032, -0.372, -0.032], 0.042, 0.0, m_poly, 0.004)
	_box(R, Vector3(0.0405, 0.008, 0.2), _P(0.22, -0.075), m_od.duplicate() as Material, Vector3.ZERO, 0.0)
	_box(R, Vector3(0.042, 0.004, 0.18), _P(0.22, -0.07), m_dark)
	# trigger guard, trigger, magazine
	_box(R, Vector3(0.009, 0.007, 0.06), _P(0.01, -0.118), m_gun, Vector3.ZERO, 0.002)
	_box(R, Vector3(0.006, 0.018, 0.006), _P(0.005, -0.104), m_steel, Vector3(-12.0, 0.0, 0.0))
	var mg := _node(R, _P(0.07, -0.09))
	_box(mg, Vector3(0.026, 0.05, 0.075), Vector3(0.0, -0.022, 0.0), m_poly, Vector3.ZERO, 0.004)
	r.mag = mg
	r.mag_grab = _P(0.09, -0.16, 0.0)
	# bolt (handle on the right side)
	var bolt := _node(R, _P(-0.07, bore))
	_cyl(bolt, 0.0125, -0.045, 0.01, 0.0, 0.0, m_steel, 12)
	_limb(bolt, Vector3(0.008, 0.0, 0.025), Vector3(0.045, -0.024, 0.03), 0.0045, 0.0045, m_steel, 8)
	_sphere(bolt, 0.0105, Vector3(0.048, -0.026, 0.031), m_poly, 10)
	r.anim = bolt
	# scope (sight line = tube axis = y 0)
	var tube := _cyl(R, 0.0128, -0.075, 0.17, 0.0, 0.0, m_poly, 16, -1.0, false)
	tube.name = "tube"
	_cyl(R, 0.019, -0.125, -0.075, 0.0, 0.0, m_poly, 18, 0.0128, false)
	_cyl(R, 0.0195, -0.145, -0.125, 0.0, 0.0, m_poly, 18, -1.0, false)
	_ring(R, 0.016, 0.0205, _P(-0.145, 0.0), m_poly2, 20)
	_cyl(R, 0.0128, 0.17, 0.23, 0.0, 0.0, m_poly, 18, 0.0245, false)
	_cyl(R, 0.025, 0.23, 0.275, 0.0, 0.0, m_poly, 20, -1.0, false)
	_ring(R, 0.0215, 0.026, _P(0.275, 0.0), m_poly2, 20)
	_cyl(R, 0.0105, 0.035, 0.06, 0.0, 0.0, m_poly2, 12) # power ring band
	var t1 := _mi(R, _cyl_mesh(0.0095, 0.0095, 0.02, 12, true), m_poly, _P(0.06, 0.02), Vector3.ZERO)
	t1.name = "turret_top"
	_mi(R, _cyl_mesh(0.0095, 0.0095, 0.02, 12, true), m_poly, _P(0.06, 0.0, 0.02), Vector3(0.0, 0.0, 90.0))
	_mi(R, _cyl_mesh(0.0085, 0.0085, 0.016, 12, true), m_poly, _P(0.06, 0.0, -0.019), Vector3(0.0, 0.0, 90.0))
	_box(R, Vector3(0.03, 0.038, 0.016), _P(-0.03, -0.03), m_gun, Vector3.ZERO, 0.004) # rings
	_box(R, Vector3(0.03, 0.038, 0.016), _P(0.125, -0.03), m_gun, Vector3.ZERO, 0.004)
	_box(R, Vector3(0.018, 0.01, 0.22), _P(0.05, -0.044), m_gun, Vector3.ZERO, 0.002) # base rail
	# lenses (hip view only)
	var eye_lens := _mi(R, _cyl_mesh(0.0175, 0.0175, 0.002, 18, true), m_glass, _P(-0.14, 0.0), Vector3(-90.0, 0.0, 0.0))
	var obj_lens := _mi(R, _cyl_mesh(0.023, 0.023, 0.002, 18, true), m_glass, _P(0.265, 0.0), Vector3(-90.0, 0.0, 0.0))
	r.hip_only.append(eye_lens)
	r.hip_only.append(obj_lens)
	# scoped view: black mask with a round window, soft edge vignette and duplex reticle
	var sc := _node(R, _P(-0.147, 0.0))
	var mask := _mi(sc, _annulus(0.0172, 0.8, Color.BLACK, Color.BLACK), m_black.duplicate() as Material, Vector3.ZERO)
	(mask.material_override as StandardMaterial3D).vertex_color_use_as_albedo = true
	var vg_mat := StandardMaterial3D.new()
	vg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vg_mat.vertex_color_use_as_albedo = true
	vg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vg_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mi(sc, _annulus(0.0135, 0.0173, Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.7)), vg_mat, Vector3(0.0, 0.0, 0.0002))
	var tint := StandardMaterial3D.new()
	tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tint.albedo_color = Color(0.55, 0.75, 0.85, 0.07)
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var disc := CylinderMesh.new()
	disc.top_radius = 0.0175
	disc.bottom_radius = 0.0175
	disc.height = 0.0001
	disc.radial_segments = 32
	_mi(sc, disc, tint, Vector3(0.0, 0.0, -0.0005), Vector3(90.0, 0.0, 0.0))
	var lw := 0.00026
	_box(sc, Vector3(0.035, lw, 0.0001), Vector3(0.0, 0.0, 0.0004), m_black)
	_box(sc, Vector3(lw, 0.035, 0.0001), Vector3(0.0, 0.0, 0.0004), m_black)
	var tw := 0.0009
	_box(sc, Vector3(0.012, tw, 0.0001), Vector3(0.0115, 0.0, 0.0004), m_black)
	_box(sc, Vector3(0.012, tw, 0.0001), Vector3(-0.0115, 0.0, 0.0004), m_black)
	_box(sc, Vector3(tw, 0.012, 0.0001), Vector3(0.0, -0.0115, 0.0004), m_black)
	_box(sc, Vector3(tw, 0.012, 0.0001), Vector3(0.0, 0.0115, 0.0004), m_black)
	_box(sc, Vector3(0.0005, 0.0005, 0.0001), Vector3(0.0, 0.0, 0.0005), m_reddot)
	for c in sc.get_children():
		var gi := c as GeometryInstance3D
		if gi != null:
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.ads_only.append(sc)
	# folded bipod
	_box(R, Vector3(0.03, 0.014, 0.02), _P(0.56, -0.07), m_gun, Vector3.ZERO, 0.003)
	_cyl(R, 0.0045, 0.38, 0.555, -0.082, 0.011, m_gun2, 8)
	_cyl(R, 0.0045, 0.38, 0.555, -0.082, -0.011, m_gun2, 8)
	# hands
	_right_arm(r, _P(-0.046, -0.14), Vector3(-14.0, 0.0, 0.0), 0.016, 0.023, _P(-0.4, -0.29, 0.14))
	_left_cup_arm(r, R, _P(0.25, -0.074), 0.023, _P(0.02, -0.42, -0.24))


func _build_lmg(r: Rig) -> void:
	r.hip_pos = Vector3(0.18, -0.07, -0.5)
	r.hip_rot = Vector3(2.0, 5.0, -12.0)
	r.ads_pos = Vector3(0.0, 0.0, -0.24)
	r.ads_fov = 48.0
	r.pivot = _P(0.0, -0.11)
	r.muzzle = _P(0.785, -0.07)
	r.flash_scale = 1.15
	r.kick_back = 0.03
	r.kick_rot = 3.0
	var R := r.root
	var bore := -0.07
	# receiver
	_box(R, Vector3(0.05, 0.074, 0.3), _P(0.04, -0.085), m_gun, Vector3.ZERO, 0.008)
	_box(R, Vector3(0.002, 0.018, 0.06), _P(0.04, -0.095, 0.0255), m_dark)
	_box(R, Vector3(0.052, 0.008, 0.22), _P(0.05, -0.105), m_gun2, Vector3.ZERO, 0.002)
	# feed cover (hinged at the rear) with rear sight
	var cover := _node(R, _P(-0.065, -0.048))
	_prof(cover, [0.0, 0.0, 0.185, 0.0, 0.175, 0.02, 0.025, 0.026, 0.0, 0.018], 0.054, 0.0, m_gun2, 0.005)
	_box(cover, Vector3(0.024, 0.012, 0.028), _P(0.035, 0.028), m_gun, Vector3.ZERO, 0.002)
	_box(cover, Vector3(0.005, 0.02, 0.014), _P(0.035, 0.04, 0.0105), m_gun, Vector3.ZERO, 0.0015)
	_box(cover, Vector3(0.005, 0.02, 0.014), _P(0.035, 0.04, -0.0105), m_gun, Vector3.ZERO, 0.0015)
	_ring(cover, 0.0042, 0.0078, _P(0.035, 0.048), m_gun, 14)
	r.anim = cover
	# pistol grip, trigger guard
	_prof(R, [-0.04, -0.118, 0.0, -0.118, -0.022, -0.21, -0.066, -0.215, -0.062, -0.195, -0.048, -0.14], 0.03, 0.0, m_poly, 0.006)
	_box(R, Vector3(0.009, 0.007, 0.072), _P(0.016, -0.146), m_gun, Vector3.ZERO, 0.002)
	_box(R, Vector3(0.006, 0.018, 0.006), _P(0.01, -0.133), m_dark, Vector3(-12.0, 0.0, 0.0))
	_prof(R, [-0.07, -0.118, 0.07, -0.118, 0.07, -0.13, -0.05, -0.13], 0.034, 0.0, m_gun, 0.003)
	# stock
	_prof(R, [-0.11, -0.055, -0.38, -0.07, -0.385, -0.17, -0.35, -0.175, -0.26, -0.13, -0.11, -0.122], 0.038, 0.0, m_poly, 0.007)
	_box(R, Vector3(0.0385, 0.025, 0.13), _P(-0.21, -0.094), m_dark)
	# handguard
	_prof(R, [0.19, -0.058, 0.35, -0.066, 0.35, -0.106, 0.19, -0.118], 0.056, 0.0, m_poly, 0.01)
	for j in 4:
		_box(R, Vector3(0.0575, 0.006, 0.014), _P(0.215 + float(j) * 0.033, -0.096), m_dark)
	# barrel, heat shield, gas tube, front sight, flash hider
	_cyl(R, 0.0118, 0.19, 0.73, bore, 0.0, m_gun, 14)
	_box(R, Vector3(0.034, 0.012, 0.29), _P(0.5, bore + 0.014), m_gun2, Vector3.ZERO, 0.005)
	for j in 9:
		_box(R, Vector3(0.022, 0.002, 0.014), _P(0.375 + float(j) * 0.031, bore + 0.02), m_dark)
		_box(R, Vector3(0.035, 0.006, 0.01), _P(0.375 + float(j) * 0.031, bore + 0.012), m_dark)
	_cyl(R, 0.0085, 0.35, 0.56, -0.093, 0.0, m_gun, 10)
	_prof(R, [0.538, -0.1, 0.578, -0.1, 0.573, -0.062, 0.564, -0.016, 0.552, -0.016, 0.543, -0.062], 0.02, 0.0, m_gun, 0.003)
	_box(R, Vector3(0.0035, 0.018, 0.0035), _P(0.558, -0.008), m_gun2)
	_cyl(R, 0.0135, 0.72, 0.79, bore, 0.0, m_gun2, 8)
	# carrying handle on the left
	_box(R, Vector3(0.01, 0.012, 0.11), _P(0.3, -0.04, -0.038), m_poly, Vector3.ZERO, 0.003)
	_box(R, Vector3(0.024, 0.008, 0.01), _P(0.26, -0.05, -0.027), m_gun)
	_box(R, Vector3(0.024, 0.008, 0.01), _P(0.34, -0.05, -0.027), m_gun)
	# folded bipod
	_box(R, Vector3(0.032, 0.016, 0.022), _P(0.6, -0.09), m_gun, Vector3.ZERO, 0.003)
	_cyl(R, 0.005, 0.4, 0.6, -0.1, 0.012, m_gun2, 8)
	_cyl(R, 0.005, 0.4, 0.6, -0.1, -0.012, m_gun2, 8)
	_box(R, Vector3(0.012, 0.01, 0.02), _P(0.4, -0.103, 0.012), m_poly)
	_box(R, Vector3(0.012, 0.01, 0.02), _P(0.4, -0.103, -0.012), m_poly)
	# box magazine (tan) hanging under the left side, with a belt feeding in
	var mg := _node(R, _P(0.05, -0.125, -0.02))
	_box(mg, Vector3(0.075, 0.1, 0.115), Vector3(-0.012, -0.05, 0.0), m_tan, Vector3.ZERO, 0.009)
	_box(mg, Vector3(0.077, 0.012, 0.117), Vector3(-0.012, -0.03, 0.0), m_tan.duplicate() as Material, Vector3.ZERO, 0.004)
	_box(mg, Vector3(0.003, 0.05, 0.07), Vector3(-0.05, -0.055, 0.0), m_dark)
	r.mag = mg
	r.mag_grab = _P(0.05, -0.2, -0.05)
	for j in 4:
		var t := float(j) / 3.0
		var p := Vector3(-0.04 + t * 0.016, -0.105 + t * 0.05, -0.005)
		var rd := _cyl(R, 0.0048, 0.025, 0.075, 0.0, 0.0, m_brass, 8)
		rd.position = p + Vector3(0.0, 0.0, -0.05)
		var lk := _box(R, Vector3(0.012, 0.004, 0.012), p + Vector3(0.003, 0.0, -0.03), m_gun)
		lk.rotation_degrees = Vector3(0.0, 0.0, 70.0)
	# hands
	_right_arm(r, _P(-0.046, -0.168), Vector3(-20.0, 0.0, 0.0), 0.015, 0.023, _P(-0.4, -0.31, 0.14))
	_left_cup_arm(r, R, _P(0.28, -0.084), 0.028, _P(0.04, -0.43, -0.25))


## Bullpup burst rifle: polymer shell, magazine behind the grip, enclosed trigger guard, tube red dot.
func _build_burst(r: Rig) -> void:
	r.hip_pos = Vector3(0.165, -0.066, -0.43)
	r.hip_rot = Vector3(2.0, 5.0, -12.0)
	r.ads_pos = Vector3(0.0, 0.0, -0.21)
	r.ads_fov = 42.0
	r.pivot = _P(0.06, -0.1)
	r.muzzle = _P(0.62, -0.06)
	r.flash_scale = 0.95
	r.kick_back = 0.028
	r.kick_rot = 3.0
	var R := r.root
	var bore := -0.06
	# stock shell (OD polymer) from the butt to the front of the action
	_prof(R, [-0.36, -0.04, 0.17, -0.04, 0.17, -0.092, 0.125, -0.1, 0.02, -0.1, -0.05, -0.112, -0.22, -0.118, -0.29, -0.15, -0.36, -0.152], 0.046, 0.0, m_od, 0.012)
	_prof(R, [-0.36, -0.04, -0.376, -0.042, -0.376, -0.152, -0.36, -0.152], 0.048, 0.0, m_poly, 0.004) # butt pad
	_prof(R, [-0.34, -0.04, -0.22, -0.04, -0.23, -0.031, -0.33, -0.033], 0.036, 0.0, m_poly2, 0.005) # cheek rest
	_box(R, Vector3(0.002, 0.018, 0.07), _P(-0.2, -0.07, 0.0232), m_dark) # ejection port
	_box(R, Vector3(0.0465, 0.004, 0.36), _P(-0.08, -0.098), m_poly2) # parting line
	# steel receiver top + rail behind the sight
	_box(R, Vector3(0.032, 0.014, 0.26), _P(0.01, -0.036), m_gun, Vector3.ZERO, 0.003)
	_box(R, Vector3(0.022, 0.008, 0.11), _P(-0.035, -0.027), m_gun, Vector3.ZERO, 0.002)
	for j in 4:
		_box(R, Vector3(0.024, 0.004, 0.009), _P(-0.08 + float(j) * 0.024, -0.022), m_gun2)
	_cyl(R, 0.006, 0.1, 0.16, -0.05, -0.026, m_gun2, 8) # charging handle
	# pistol grip + big enclosed trigger guard
	_prof(R, [0.035, -0.098, 0.088, -0.098, 0.072, -0.198, 0.028, -0.202, 0.03, -0.18, 0.034, -0.13], 0.03, 0.0, m_od, 0.006)
	_box(R, Vector3(0.012, 0.009, 0.1), _P(0.14, -0.192), m_od, Vector3.ZERO, 0.003)
	_box(R, Vector3(0.012, 0.1, 0.014), _P(0.19, -0.143), m_od, Vector3.ZERO, 0.003)
	_box(R, Vector3(0.006, 0.02, 0.006), _P(0.1, -0.112), m_dark, Vector3(-12.0, 0.0, 0.0)) # trigger
	_box(R, Vector3(0.05, 0.006, 0.01), _P(0.03, -0.075), m_gun2) # burst selector
	# handguard, barrel, gas block, flash hider
	_box(R, Vector3(0.05, 0.05, 0.17), _P(0.255, bore - 0.004), m_poly, Vector3.ZERO, 0.014)
	for j in 4:
		_box(R, Vector3(0.052, 0.01, 0.02), _P(0.205 + float(j) * 0.034, bore - 0.008), m_dark, Vector3.ZERO, 0.003)
	_cyl(R, 0.0092, 0.34, 0.57, bore, 0.0, m_gun, 12)
	_box(R, Vector3(0.022, 0.03, 0.026), _P(0.38, bore + 0.006), m_gun2, Vector3.ZERO, 0.004)
	_cyl(R, 0.012, 0.555, 0.625, bore, 0.0, m_gun2, 10)
	for j in 3:
		var a := TAU * float(j) / 3.0
		_box(R, Vector3(0.0025, 0.0025, 0.045), _P(0.6, bore + sin(a) * 0.0115, cos(a) * 0.0115), m_dark)
	# compact tube red dot on a riser
	_box(R, Vector3(0.022, 0.02, 0.05), _P(0.045, -0.022), m_gun, Vector3.ZERO, 0.003)
	_cyl(R, 0.0132, 0.02, 0.07, 0.0, 0.0, m_scope_in, 16, -1.0, false)
	_cyl(R, 0.015, 0.02, 0.07, 0.0, 0.0, m_od, 18, -1.0, false)
	_ring(R, 0.0122, 0.0158, _P(0.02, 0.0), m_poly, 18)
	_ring(R, 0.0122, 0.0158, _P(0.07, 0.0), m_poly, 18)
	_box(R, Vector3(0.008, 0.007, 0.012), _P(0.045, 0.016), m_poly, Vector3.ZERO, 0.002)
	_box(R, Vector3(0.007, 0.008, 0.012), _P(0.045, 0.0, 0.016), m_poly, Vector3.ZERO, 0.002)
	var lens := _cyl(R, 0.0125, 0.064, 0.065, 0.0, 0.0, m_tint, 18)
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dot := _sphere(R, 0.0008, _P(0.063, 0.0), m_reddot, 8)
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# magazine behind the grip (smoked polymer, curved)
	var mg := _node(R, _P(-0.1, -0.11))
	_prof(mg, [-0.024, 0.0, 0.024, 0.0, 0.034, -0.085, 0.047, -0.165, -0.002, -0.174, -0.012, -0.09], 0.024, 0.0, m_poly2, 0.004)
	_box(mg, Vector3(0.027, 0.011, 0.054), Vector3(0.0, -0.172, -0.024), m_poly, Vector3(-10.0, 0.0, 0.0), 0.004)
	for j in 3:
		_box(mg, Vector3(0.025, 0.003, 0.028), Vector3(0.0, -0.03 - float(j) * 0.035, -0.002 - float(j) * 0.009), m_dark)
	r.mag = mg
	r.mag_grab = _P(-0.08, -0.24, 0.0)
	# hands
	_right_arm(r, _P(0.054, -0.152), Vector3(-18.0, 0.0, 0.0), 0.015, 0.023, _P(-0.3, -0.3, 0.14))
	_left_cup_arm(r, R, _P(0.26, bore - 0.004), 0.026, _P(0.06, -0.42, -0.24))


## Scoped-view overlay for a magnified optic: black mask with a round window of radius win at
## the eyepiece (forward f), soft vignette and a reticle. chevron: SVD-style ^ with stadia lines.
func _scope_view(R: Node3D, f: float, win: float, chevron: bool) -> Node3D:
	var sc := _node(R, _P(f, 0.0))
	var mask := _mi(sc, _annulus(win, 0.8, Color.BLACK, Color.BLACK), m_black.duplicate() as Material, Vector3.ZERO)
	(mask.material_override as StandardMaterial3D).vertex_color_use_as_albedo = true
	var vg_mat := StandardMaterial3D.new()
	vg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vg_mat.vertex_color_use_as_albedo = true
	vg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vg_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mi(sc, _annulus(win * 0.8, win + 0.0001, Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.7)), vg_mat, Vector3(0.0, 0.0, 0.0002))
	var lw := 0.00024
	if chevron:
		var red := m_reddot
		for s: float in [-1.0, 1.0]:
			_box(sc, Vector3(0.0032, lw * 1.6, 0.0001), Vector3(s * 0.00105, -0.001, 0.0004), red, Vector3(0.0, 0.0, -s * 52.0))
		_box(sc, Vector3(win * 0.7, lw, 0.0001), Vector3(-win * 0.5, 0.0, 0.0004), m_black)
		_box(sc, Vector3(win * 0.7, lw, 0.0001), Vector3(win * 0.5, 0.0, 0.0004), m_black)
		for j in 4:
			var y := -0.0035 - float(j) * 0.0022
			_box(sc, Vector3(0.0022 - float(j) * 0.0003, lw, 0.0001), Vector3(0.0, y, 0.0004), m_black)
		_box(sc, Vector3(lw, 0.0095, 0.0001), Vector3(0.0, -0.0075, 0.0004), m_black)
	else:
		_box(sc, Vector3(win * 2.0, lw, 0.0001), Vector3(0.0, 0.0, 0.0004), m_black)
		_box(sc, Vector3(lw, win * 2.0, 0.0001), Vector3(0.0, 0.0, 0.0004), m_black)
	for c in sc.get_children():
		var gi := c as GeometryInstance3D
		if gi != null:
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return sc


## Semi-auto marksman rifle: wooden handguard and skeleton stock, 10-round mag, medium scope.
func _build_dmr(r: Rig) -> void:
	r.hip_pos = Vector3(0.17, -0.07, -0.49)
	r.hip_rot = Vector3(2.0, 5.0, -12.0)
	r.ads_pos = Vector3(0.0, 0.0, -0.2)
	r.ads_fov = 34.0
	r.pivot = _P(0.0, -0.1)
	r.muzzle = _P(0.78, -0.058)
	r.flash_scale = 1.2
	r.kick_back = 0.05
	r.kick_rot = 6.5
	var R := r.root
	var bore := -0.058
	# receiver + dust cover
	_box(R, Vector3(0.032, 0.046, 0.25), _P(0.02, -0.068), m_gun, Vector3.ZERO, 0.006)
	_prof(R, [-0.105, -0.044, 0.135, -0.044, 0.128, -0.034, -0.07, -0.03, -0.105, -0.036], 0.03, 0.0, m_gun2, 0.004)
	_box(R, Vector3(0.002, 0.016, 0.06), _P(0.05, -0.062, 0.0165), m_dark)
	var ch := _node(R, _P(0.09, -0.056, 0.016))
	_box(ch, Vector3(0.018, 0.01, 0.016), Vector3(0.009, 0.0, 0.0), m_steel, Vector3.ZERO, 0.002)
	r.anim = ch
	# trigger group, guard, trigger
	_prof(R, [-0.075, -0.09, 0.05, -0.09, 0.05, -0.102, -0.06, -0.102], 0.028, 0.0, m_gun, 0.003)
	_box(R, Vector3(0.009, 0.007, 0.07), _P(0.0, -0.13), m_gun, Vector3.ZERO, 0.002)
	_box(R, Vector3(0.009, 0.03, 0.007), _P(0.034, -0.115), m_gun, Vector3(-12.0, 0.0, 0.0), 0.002)
	_box(R, Vector3(0.006, 0.018, 0.006), _P(-0.004, -0.114), m_steel, Vector3(-12.0, 0.0, 0.0))
	# wooden handguard, gas tube cover
	_box(R, Vector3(0.046, 0.042, 0.22), _P(0.255, bore - 0.006), m_wood, Vector3.ZERO, 0.014)
	for j in 3:
		_box(R, Vector3(0.0475, 0.006, 0.03), _P(0.2 + float(j) * 0.05, bore - 0.012), m_wood_dark, Vector3.ZERO, 0.002)
	_box(R, Vector3(0.03, 0.018, 0.2), _P(0.255, bore + 0.022), m_wood_dark, Vector3.ZERO, 0.006)
	_cyl(R, 0.012, 0.145, 0.155, bore, 0.0, m_gun2, 14)
	# barrel, front sight block, slotted flash hider
	_cyl(R, 0.0095, 0.365, 0.72, bore, 0.0, m_gun, 12)
	_cyl(R, 0.0122, 0.365, 0.395, bore, 0.0, m_gun2, 12)
	_box(R, Vector3(0.018, 0.034, 0.024), _P(0.5, bore + 0.01), m_gun, Vector3.ZERO, 0.003)
	_cyl(R, 0.0125, 0.71, 0.785, bore, 0.0, m_gun2, 10)
	for j in 4:
		var a := TAU * float(j) / 4.0 + PI / 4.0
		_box(R, Vector3(0.003, 0.003, 0.05), _P(0.758, bore + sin(a) * 0.012, cos(a) * 0.012), m_dark)
	# skeleton wooden stock: pistol grip, lower bar, comb, butt
	_prof(R, [-0.06, -0.096, -0.022, -0.1, -0.048, -0.19, -0.094, -0.196, -0.09, -0.152, -0.086, -0.11], 0.032, 0.0, m_wood, 0.007)
	_prof(R, [-0.09, -0.168, -0.36, -0.15, -0.36, -0.126, -0.1, -0.146], 0.03, 0.0, m_wood, 0.006)
	_prof(R, [-0.1, -0.044, -0.36, -0.05, -0.36, -0.088, -0.25, -0.082, -0.13, -0.076, -0.1, -0.09], 0.034, 0.0, m_wood, 0.006)
	_prof(R, [-0.32, -0.085, -0.36, -0.085, -0.36, -0.13, -0.32, -0.13], 0.03, 0.0, m_wood, 0.004)
	_prof(R, [-0.36, -0.044, -0.376, -0.044, -0.376, -0.155, -0.36, -0.155], 0.036, 0.0, m_poly, 0.004)
	_prof(R, [-0.31, -0.049, -0.16, -0.046, -0.16, -0.036, -0.3, -0.036], 0.026, 0.0, m_wood_dark, 0.004)
	# 10-round magazine (steel)
	var mg := _node(R, _P(0.09, -0.096))
	_prof(mg, [-0.03, 0.0, 0.03, 0.0, 0.04, -0.06, 0.044, -0.104, -0.014, -0.11, -0.022, -0.06], 0.026, 0.0, m_gun2, 0.004)
	for j in 2:
		_box(mg, Vector3(0.0265, 0.004, 0.04), Vector3(0.0, -0.035 - float(j) * 0.03, -0.004 - float(j) * 0.004), m_dark)
	r.mag = mg
	r.mag_grab = _P(0.1, -0.2, 0.0)
	# scope on a side-rail bracket
	_box(R, Vector3(0.018, 0.008, 0.2), _P(0.04, -0.03), m_gun, Vector3.ZERO, 0.002)
	_box(R, Vector3(0.026, 0.03, 0.014), _P(-0.02, -0.016), m_gun, Vector3.ZERO, 0.004)
	_box(R, Vector3(0.026, 0.03, 0.014), _P(0.1, -0.016), m_gun, Vector3.ZERO, 0.004)
	_cyl(R, 0.0118, -0.07, 0.13, 0.0, 0.0, m_poly, 16, -1.0, false)
	_cyl(R, 0.0168, -0.11, -0.07, 0.0, 0.0, m_poly, 18, 0.0118, false)
	_cyl(R, 0.0172, -0.128, -0.11, 0.0, 0.0, m_poly, 18, -1.0, false)
	_ring(R, 0.0142, 0.0182, _P(-0.128, 0.0), m_poly2, 20)
	_cyl(R, 0.0118, 0.13, 0.17, 0.0, 0.0, m_poly, 18, 0.0195, false)
	_cyl(R, 0.0198, 0.17, 0.205, 0.0, 0.0, m_poly, 20, -1.0, false)
	_ring(R, 0.0168, 0.0205, _P(0.205, 0.0), m_poly2, 20)
	_cyl(R, 0.0125, 0.03, 0.05, 0.0, 0.0, m_poly2, 12)
	_mi(R, _cyl_mesh(0.0085, 0.0085, 0.016, 12, true), m_poly, _P(0.04, 0.018), Vector3.ZERO)
	_mi(R, _cyl_mesh(0.0085, 0.0085, 0.016, 12, true), m_poly, _P(0.04, 0.0, 0.018), Vector3(0.0, 0.0, 90.0))
	var eye_lens := _mi(R, _cyl_mesh(0.0152, 0.0152, 0.002, 18, true), m_glass, _P(-0.124, 0.0), Vector3(-90.0, 0.0, 0.0))
	var obj_lens := _mi(R, _cyl_mesh(0.018, 0.018, 0.002, 18, true), m_glass, _P(0.198, 0.0), Vector3(-90.0, 0.0, 0.0))
	r.hip_only.append(eye_lens)
	r.hip_only.append(obj_lens)
	r.ads_only.append(_scope_view(R, -0.13, 0.0172, true))
	# hands
	_right_arm(r, _P(-0.062, -0.148), Vector3(-18.0, 0.0, 0.0), 0.016, 0.023, _P(-0.4, -0.29, 0.14))
	_left_cup_arm(r, R, _P(0.25, bore - 0.006), 0.025, _P(0.02, -0.42, -0.24))


## Machine pistol: two-tone pistol with a compensator, fire selector and a long 20-round mag.
func _build_mpistol(r: Rig) -> void:
	r.hip_pos = Vector3(0.135, -0.03, -0.39)
	r.hip_rot = Vector3(2.0, 20.0, -12.0)
	r.ads_pos = Vector3(0.0, 0.0, -0.32)
	r.ads_fov = 50.0
	r.pivot = _P(0.0, -0.09)
	r.muzzle = _P(0.205, -0.022)
	r.flash_scale = 0.6
	r.kick_back = 0.022
	r.kick_rot = 4.0
	var R := r.root
	# slide (black) with forward serrations
	var sl := _node(R)
	_prof(sl, [-0.032, -0.036, 0.162, -0.036, 0.165, -0.013, 0.157, -0.006, -0.026, -0.006, -0.032, -0.012], 0.026, 0.0, m_stainless, 0.003)
	for j in 5:
		_box(sl, Vector3(0.0275, 0.018, 0.0025), _P(-0.024 + float(j) * 0.0055, -0.02), m_dark)
	for j in 3:
		_box(sl, Vector3(0.0275, 0.016, 0.0025), _P(0.12 + float(j) * 0.0055, -0.021), m_dark)
	_box(sl, Vector3(0.012, 0.002, 0.032), _P(0.05, -0.0058, 0.002), m_dark)
	_box(sl, Vector3(0.022, 0.004, 0.009), _P(-0.02, -0.006), m_gun)
	_box(sl, Vector3(0.007, 0.007, 0.009), _P(-0.02, -0.0035, 0.0068), m_gun, Vector3.ZERO, 0.0015)
	_box(sl, Vector3(0.007, 0.007, 0.009), _P(-0.02, -0.0035, -0.0068), m_gun, Vector3.ZERO, 0.0015)
	_box(sl, Vector3(0.0038, 0.0068, 0.007), _P(0.15, -0.0034), m_fiber)
	r.anim = sl
	# compensator on the frame (doesn't move with the slide), ports on top
	_box(R, Vector3(0.027, 0.03, 0.038), _P(0.185, -0.022), m_gun2, Vector3.ZERO, 0.004)
	for j in 3:
		_box(R, Vector3(0.012, 0.004, 0.006), _P(0.174 + float(j) * 0.01, -0.0065), m_dark)
	# frame (polymer)
	_prof(R, [-0.034, -0.036, 0.166, -0.036, 0.168, -0.053, 0.062, -0.053, 0.05, -0.058, -0.004, -0.058, -0.03, -0.05], 0.0235, 0.0, m_poly, 0.003)
	_box(R, Vector3(0.026, 0.008, 0.07), _P(0.12, -0.056), m_poly, Vector3.ZERO, 0.002)
	_box(R, Vector3(0.004, 0.01, 0.012), _P(-0.018, -0.042, 0.0135), m_steel, Vector3(0.0, 0.0, 0.0), 0.0015) # selector
	_prof(R, [-0.036, -0.05, 0.008, -0.052, 0.004, -0.072, -0.012, -0.158, -0.052, -0.158, -0.05, -0.11, -0.053, -0.062, -0.05, -0.045], 0.03, 0.0, m_poly, 0.005)
	for j in 4:
		_box(R, Vector3(0.031, 0.004, 0.034), _P(-0.03 + float(j) * 0.0035, -0.09 - float(j) * 0.016), m_poly2, Vector3(-14.0, 0.0, 0.0))
	_box(R, Vector3(0.009, 0.0065, 0.05), _P(0.033, -0.082), m_poly, Vector3.ZERO, 0.002)
	_box(R, Vector3(0.009, 0.03, 0.0065), _P(0.058, -0.068), m_poly, Vector3(-18.0, 0.0, 0.0), 0.002)
	_box(R, Vector3(0.006, 0.018, 0.006), _P(0.022, -0.067), m_dark, Vector3(-10.0, 0.0, 0.0))
	# extended magazine sticking out well below the grip
	var mg := _node(R, _P(-0.03, -0.1))
	_box(mg, Vector3(0.021, 0.19, 0.03), Vector3(0.0, -0.05, -0.002), m_gun, Vector3(-12.0, 0.0, 0.0), 0.003)
	_box(mg, Vector3(0.022, 0.004, 0.026), Vector3(0.0, -0.085, -0.012), m_dark, Vector3(-12.0, 0.0, 0.0))
	_box(mg, Vector3(0.03, 0.01, 0.042), Vector3(0.0, -0.143, -0.025), m_poly2, Vector3(-12.0, 0.0, 0.0), 0.003)
	r.mag = mg
	r.mag_grab = _P(-0.035, -0.26, -0.02)
	# hands like the pistol
	var gp := _P(-0.024, -0.108)
	var grot := Vector3(-16.0, 0.0, 0.0)
	_right_arm(r, gp, grot, 0.0155, 0.024, _P(-0.26, -0.3, 0.24))
	var la := _node(R)
	var hf := _node(la, gp + Vector3(-0.012, -0.016, -0.006), grot + Vector3(0.0, -10.0, 0.0))
	hf.scale = Vector3(1.06, 1.06, 1.06)
	var w := hf.transform * _grip_hand(hf, 0.017, 0.026, -1.0, false)
	_forearm(la, w, _P(-0.24, -0.32, -0.26))
	r.left_arm = la
	r.left_hand = Vector3.ZERO


## Side-by-side double-barrel: break action (anim = barrels + forend on the hinge), two triggers.
func _build_dbarrel(r: Rig) -> void:
	r.hip_pos = Vector3(0.17, -0.06, -0.47)
	r.hip_rot = Vector3(2.0, 5.0, -12.0)
	r.ads_pos = Vector3(0.0, 0.0, -0.3)
	r.ads_fov = 50.0
	r.pivot = _P(-0.05, -0.08)
	r.muzzle = _P(0.62, -0.02)
	r.flash_scale = 1.6
	r.kick_back = 0.075
	r.kick_rot = 12.0
	var R := r.root
	# action (polished steel) with the top lever
	_prof(R, [-0.082, -0.013, 0.05, -0.013, 0.05, -0.064, -0.012, -0.07, -0.082, -0.062], 0.046, 0.0, m_steel, 0.005)
	_box(R, Vector3(0.047, 0.004, 0.05), _P(0.0, -0.045), m_stainless) # engraving band
	_box(R, Vector3(0.012, 0.006, 0.034), _P(-0.07, -0.006, 0.006), m_steel, Vector3(0.0, -18.0, 0.0), 0.002)
	# barrels + forend on the hinge (front-bottom of the action)
	var hb := 0.05
	var hu := -0.052
	var hinge := _node(R, _P(hb, hu))
	for s: float in [-1.0, 1.0]:
		_cyl(hinge, 0.0118, 0.0, 0.57, -0.02 - hu, s * 0.0122, m_gun, 14)
		_cyl(hinge, 0.0085, 0.566, 0.572, -0.02 - hu, s * 0.0122, m_dark, 10)
		_cyl(hinge, 0.0121, -0.002, 0.004, -0.02 - hu, s * 0.0122, m_brass, 12) # shell rims
	_box(hinge, Vector3(0.008, 0.006, 0.55), _P(0.285, -0.007 - hu), m_gun2)
	_box(hinge, Vector3(0.012, 0.01, 0.5), _P(0.3, -0.032 - hu), m_gun)
	_sphere(hinge, 0.0028, _P(0.556, -0.0018 - hu), m_brass, 8)
	_box(hinge, Vector3(0.05, 0.012, 0.035), _P(0.02, -0.036 - hu), m_steel, Vector3.ZERO, 0.003) # lump
	_box(hinge, Vector3(0.044, 0.03, 0.17), _P(0.13, -0.046 - hu), m_wood, Vector3.ZERO, 0.012)
	for j in 5:
		_box(hinge, Vector3(0.0455, 0.0315, 0.004), _P(0.08 + float(j) * 0.025, -0.046 - hu), m_wood_dark, Vector3.ZERO, 0.011)
	r.anim = hinge
	# straight-grip stock, butt pad
	_prof(R, [-0.082, -0.016, -0.082, -0.062, -0.11, -0.078, -0.15, -0.108, -0.39, -0.148, -0.4, -0.143, -0.4, -0.052, -0.37, -0.048, -0.16, -0.064, -0.11, -0.046], 0.036, 0.0, m_wood, 0.008)
	_prof(R, [-0.4, -0.145, -0.416, -0.146, -0.416, -0.05, -0.4, -0.05], 0.038, 0.0, m_poly, 0.004)
	# trigger guard, two triggers
	_box(R, Vector3(0.009, 0.007, 0.075), _P(-0.032, -0.098), m_steel, Vector3.ZERO, 0.002)
	_box(R, Vector3(0.009, 0.03, 0.007), _P(0.004, -0.084), m_steel, Vector3(-12.0, 0.0, 0.0), 0.002)
	_box(R, Vector3(0.006, 0.02, 0.006), _P(-0.016, -0.08), m_steel, Vector3(-12.0, 0.0, 0.0))
	_box(R, Vector3(0.006, 0.02, 0.006), _P(-0.038, -0.08), m_steel, Vector3(-18.0, 0.0, 0.0))
	# hands: right on the wrist, left on the forend (rides with the barrels)
	_right_arm(r, _P(-0.128, -0.085), Vector3(-50.0, 0.0, 0.0), 0.015, 0.022, _P(-0.42, -0.28, 0.12), true)
	_left_cup_arm(r, hinge, _P(0.13, -0.046 - hu), 0.024, _P(0.04 - hb, -0.42 - hu, -0.24))
	r.mag_grab = _P(-0.04, 0.03, 0.0) # breech, hinge space
	var sh := _node(r.left_arm, _P(0.13, -0.08 - hu, 0.0))
	for s: float in [-1.0, 1.0]:
		_cyl(sh, 0.0095, -0.03, 0.035, 0.0, s * 0.011, m_shell, 10)
		_cyl(sh, 0.0102, -0.045, -0.03, 0.0, s * 0.011, m_brass, 10)
	sh.visible = false
	r.extra = sh


## RPG-style rocket launcher on the shoulder; the warhead (= mag) is loaded from the front.
func _build_rpg(r: Rig) -> void:
	r.hip_pos = Vector3(0.15, -0.05, -0.36)
	r.hip_rot = Vector3(1.0, 4.0, -6.0)
	r.ads_pos = Vector3(0.0, 0.0, -0.2)
	r.ads_fov = 44.0
	r.pivot = _P(0.0, -0.1)
	r.muzzle = _P(0.36, -0.065)
	r.flash_scale = 1.4
	r.kick_back = 0.05
	r.kick_rot = 5.0
	var R := r.root
	var bore := -0.065
	# launch tube (olive), wooden heat guard, rear blast cone
	_cyl(R, 0.021, -0.42, 0.345, bore, 0.0, m_od, 18)
	_cyl(R, 0.0245, -0.07, 0.16, bore, 0.0, m_wood, 18)
	_cyl(R, 0.0255, -0.078, -0.066, bore, 0.0, m_gun, 18)
	_cyl(R, 0.0255, 0.156, 0.168, bore, 0.0, m_gun, 18)
	_cyl(R, 0.024, 0.322, 0.348, bore, 0.0, m_gun, 18)
	_cyl(R, 0.04, -0.56, -0.43, bore, 0.0, m_gun, 18, 0.022, false)
	_cyl(R, 0.0405, -0.565, -0.555, bore, 0.0, m_gun2, 18)
	_cyl(R, 0.034, -0.52, -0.515, bore, 0.0, m_dark, 16)
	_cyl(R, 0.0225, -0.44, -0.415, bore, 0.0, m_gun2, 16)
	# trigger housing, pistol grip, guard, forward grip
	_box(R, Vector3(0.026, 0.026, 0.16), _P(0.06, bore - 0.03), m_gun, Vector3.ZERO, 0.004)
	_prof(R, [0.0, -0.105, 0.036, -0.105, 0.02, -0.195, -0.022, -0.198, -0.02, -0.175, -0.012, -0.12], 0.03, 0.0, m_wood, 0.006)
	_box(R, Vector3(0.008, 0.006, 0.065), _P(0.062, -0.136), m_gun, Vector3.ZERO, 0.002)
	_box(R, Vector3(0.008, 0.032, 0.006), _P(0.094, -0.12), m_gun, Vector3.ZERO, 0.002)
	_box(R, Vector3(0.006, 0.02, 0.006), _P(0.05, -0.115), m_dark, Vector3(-12.0, 0.0, 0.0))
	_prof(R, [0.1, -0.102, 0.135, -0.102, 0.128, -0.185, 0.094, -0.186, 0.098, -0.13], 0.03, 0.0, m_wood, 0.006)
	# folding iron sights: rear aperture, front post (top on y = 0)
	_box(R, Vector3(0.03, 0.012, 0.02), _P(-0.04, bore + 0.024), m_gun, Vector3.ZERO, 0.002)
	_box(R, Vector3(0.005, 0.04, 0.01), _P(-0.04, -0.022, 0.012), m_gun, Vector3.ZERO, 0.0015)
	_box(R, Vector3(0.005, 0.04, 0.01), _P(-0.04, -0.022, -0.012), m_gun, Vector3.ZERO, 0.0015)
	_ring(R, 0.0045, 0.0085, _P(-0.04, 0.0), m_gun, 14)
	_box(R, Vector3(0.034, 0.012, 0.02), _P(0.26, bore + 0.024), m_gun, Vector3.ZERO, 0.002)
	_box(R, Vector3(0.004, 0.05, 0.006), _P(0.26, -0.018, 0.014), m_gun, Vector3.ZERO, 0.0015)
	_box(R, Vector3(0.004, 0.05, 0.006), _P(0.26, -0.018, -0.014), m_gun, Vector3.ZERO, 0.0015)
	_box(R, Vector3(0.032, 0.004, 0.006), _P(0.26, 0.007), m_gun)
	_box(R, Vector3(0.0035, 0.038, 0.004), _P(0.26, -0.019), m_gun2)
	# warhead (loaded from the front)
	var rk := _node(R, _P(0.345, bore))
	_cyl(rk, 0.0195, -0.02, 0.012, 0.0, 0.0, m_gun2, 14)
	_cyl(rk, 0.02, 0.012, 0.045, 0.0, 0.0, m_od, 18, 0.042)
	_cyl(rk, 0.042, 0.045, 0.11, 0.0, 0.0, m_od, 18)
	_cyl(rk, 0.0425, 0.07, 0.078, 0.0, 0.0, m_tan, 18)
	_cyl(rk, 0.042, 0.11, 0.2, 0.0, 0.0, m_od, 18, 0.012)
	_cyl(rk, 0.009, 0.2, 0.235, 0.0, 0.0, m_steel, 10, 0.004)
	r.mag = rk
	r.mag_grab = _P(0.42, -0.12, -0.03)
	# hands: right on the pistol grip, left on the forward grip
	_right_arm(r, _P(0.006, -0.15), Vector3(-14.0, 0.0, 0.0), 0.015, 0.023, _P(-0.36, -0.3, 0.14))
	var lp := _P(0.115, -0.145)
	var la := _node(R)
	var hf := _node(la, lp, Vector3(-8.0, 0.0, 0.0))
	var w := hf.transform * _grip_hand(hf, 0.015, 0.016, -1.0, false)
	_forearm(la, w, _P(0.0, -0.42, -0.24))
	r.left_arm = la
	r.left_hand = lp


# --------------------------------------------------------- flash/throw ----

func _build_flash() -> void:
	_flash = Node3D.new()
	_flash.visible = false
	_world.add_child(_flash)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var core := Color(1.0, 0.97, 0.8, 1.0)
	var mid := Color(1.0, 0.72, 0.25, 0.85)
	var tip := Color(1.0, 0.45, 0.08, 0.0)
	# front-facing star (XY plane)
	var pts := 10
	for i in pts:
		var a0 := TAU * float(i) / float(pts)
		var a1 := TAU * float(i + 1) / float(pts)
		var am := (a0 + a1) * 0.5
		var r_tip := 0.13 if i % 2 == 0 else 0.085
		st.set_color(core)
		st.add_vertex(Vector3.ZERO)
		st.set_color(mid)
		st.add_vertex(Vector3(cos(a0), sin(a0), 0.0) * 0.032)
		st.set_color(tip)
		st.add_vertex(Vector3(cos(am), sin(am), 0.0) * r_tip)
		st.set_color(core)
		st.add_vertex(Vector3.ZERO)
		st.set_color(tip)
		st.add_vertex(Vector3(cos(am), sin(am), 0.0) * r_tip)
		st.set_color(mid)
		st.add_vertex(Vector3(cos(a1), sin(a1), 0.0) * 0.032)
	# side petals along the barrel axis (forward = -Z)
	for k in 4:
		var a := TAU * float(k) / 4.0 + PI / 4.0
		var side := Vector3(cos(a), sin(a), 0.0)
		var w := 0.03
		var c0 := Vector3.ZERO
		var c1 := side * w + Vector3(0.0, 0.0, -0.03)
		var c2 := Vector3(0.0, 0.0, -0.24)
		var c3 := side * -w * 0.2 + Vector3(0.0, 0.0, -0.03)
		var perp := Vector3(-side.y, side.x, 0.0)
		c1 = side * 0.0 + perp * w + Vector3(0.0, 0.0, -0.03)
		c3 = perp * -w + Vector3(0.0, 0.0, -0.03)
		st.set_color(core)
		st.add_vertex(c0)
		st.set_color(mid)
		st.add_vertex(c1)
		st.set_color(tip)
		st.add_vertex(c2)
		st.set_color(core)
		st.add_vertex(c0)
		st.set_color(tip)
		st.add_vertex(c2)
		st.set_color(mid)
		st.add_vertex(c3)
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	m.material_override = m_flash
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.name = "star"
	_flash.add_child(m)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.7, 0.35)
	_flash_light.light_energy = 0.0
	_flash_light.omni_range = 1.4
	_flash_light.visible = false
	_world.add_child(_flash_light)


func _build_throw_arm() -> void:
	_throw_arm = Node3D.new()
	_throw_arm.visible = false
	_world.add_child(_throw_arm)
	var hf := _node(_throw_arm, Vector3.ZERO, Vector3(-10.0, 0.0, 0.0))
	var w := hf.transform * _grip_hand(hf, 0.02, 0.026, -1.0, false)
	_forearm(_throw_arm, w, w + Vector3(-0.06, -0.33, 0.24))
	_throw_nade = _node(hf)
	_make_grenade(_throw_nade)
	_fly_nade = Node3D.new()
	_fly_nade.visible = false
	_world.add_child(_fly_nade)
	_make_grenade(_fly_nade)


func _make_grenade(n: Node3D) -> void:
	var body := _sphere(n, 0.031, Vector3(0.0, 0.0, 0.0), m_nade, 14)
	body.scale = Vector3(1.0, 1.12, 1.0)
	for j in 3:
		var rg := _ring(n, 0.0295, 0.0335, Vector3(0.0, -0.016 + float(j) * 0.016, 0.0), m_nade, 16)
		rg.rotation_degrees = Vector3.ZERO
	_mi(n, _cyl_mesh(0.011, 0.012, 0.016, 10, true), m_gun, Vector3(0.0, 0.039, 0.0))
	_box(n, Vector3(0.01, 0.006, 0.05), Vector3(0.0, 0.041, 0.018), m_gun2, Vector3(-20.0, 0.0, 0.0))
	var pin := _ring(n, 0.006, 0.0085, Vector3(-0.014, 0.042, -0.006), m_steel, 10)
	pin.rotation_degrees = Vector3(0.0, 0.0, 90.0)


# ----------------------------------------------------------- animation ----

func _f(st: Dictionary, key: String) -> float:
	var v: Variant = st.get(key, 0.0)
	if v is float or v is int:
		return float(v)
	if v is bool:
		return 1.0 if bool(v) else 0.0
	return 0.0


func _kf(p: float, times: PackedFloat32Array, vals: PackedVector3Array) -> Vector3:
	if p <= times[0]:
		return vals[0]
	for i in range(1, times.size()):
		if p <= times[i]:
			var u: float = (p - times[i - 1]) / maxf(times[i] - times[i - 1], 0.0001)
			u = u * u * (3.0 - 2.0 * u)
			return vals[i - 1].lerp(vals[i], u)
	return vals[vals.size() - 1]


func _hump(x: float, a: float, b: float, c: float, d: float) -> float:
	## 0 before a, rises to 1 at b, holds, falls to 0 at d
	return smoothstep(a, b, x) * (1.0 - smoothstep(c, d, x))


## Optional helper for the caller: suggested world-view FOV multiplier while aiming.
func get_ads_zoom(weapon: int, ads: float) -> float:
	var z := 1.0
	if weapon == SNIPER:
		z = 0.3
	elif weapon == DMR:
		z = 0.42
	elif weapon == RIFLE or weapon == LMG or weapon == SMG or weapon == BURST or weapon == RPG:
		z = 0.8
	elif weapon != KNIFE:
		z = 0.88
	return lerpf(1.0, z, clampf(ads, 0.0, 1.0))


func update_pose(weapon: int, st: Dictionary) -> void:
	if not _ready_done:
		return
	var w := clampi(weapon, 0, NUM_WEAPONS - 1)
	if w != _cur:
		for i in _rigs.size():
			_rigs[i].root.visible = (i == w)
		_cur = w
	var r: Rig = _rigs[w]

	var t := _f(st, "time")
	var bob_x := _f(st, "bob_x")
	var bob_y := _f(st, "bob_y")
	var sway := clampf(_f(st, "sway"), -1.0, 1.0)
	var kick := clampf(_f(st, "kick"), 0.0, 1.0)
	var reload := clampf(_f(st, "reload"), 0.0, 1.0)
	var swch := clampf(_f(st, "switch"), 0.0, 1.0)
	var sprint := clampf(_f(st, "sprint"), 0.0, 1.0)
	var ads := clampf(_f(st, "ads"), 0.0, 1.0)
	var throw := clampf(_f(st, "throw"), 0.0, 1.0)
	var crouch := clampf(_f(st, "crouch"), 0.0, 1.0)
	var flash := _f(st, "flash") > 0.5
	if not r.can_ads:
		ads = 0.0
	if throw > 0.0:
		ads = 0.0
	var ae := ads * ads * (3.0 - 2.0 * ads)
	var sp := sprint * (1.0 - ae)
	var free := 1.0 - ae

	# ---- framing for the current aspect ratio
	var vs := size
	var aspect := float(maxi(vs.x, 1)) / float(maxi(vs.y, 1))
	var base_fov := BASE_FOV
	var xs := 1.0
	if aspect < 1.6:
		var k := clampf((1.6 - aspect) / 0.75, 0.0, 1.0)
		base_fov = BASE_FOV + 12.0 * k
		xs = lerpf(1.0, 0.6, k)
	_cam.fov = lerpf(base_fov, r.ads_fov, ae)

	var hp := r.hip_pos
	var hr := r.hip_rot
	if st.has("_hip_pos"): # debug/tuning override
		hp = st["_hip_pos"]
	if st.has("_hip_rot"):
		hr = st["_hip_rot"]
	var pos := Vector3(hp.x * xs, hp.y, hp.z)
	if aspect < 1.6:
		pos.y -= 0.01 * clampf((1.6 - aspect) / 0.75, 0.0, 1.0)
	pos = pos.lerp(r.ads_pos, ae)
	var rot := hr * (1.0 - ae)

	# ---- idle breathing, walk bob, turn sway
	pos.y += sin(t * 1.7) * 0.0028 * free
	pos.x += sin(t * 0.85) * 0.0012 * free
	rot.x += sin(t * 1.7 + 0.6) * 0.35 * free
	rot.z += sin(t * 0.9) * 0.3 * free
	var bob_k := 1.0 - 0.85 * ae
	var bob_amp := 1.0 + sp * 1.2
	pos.x += bob_x * 0.011 * bob_k * bob_amp
	pos.y += bob_y * 0.009 * bob_k * bob_amp
	rot.z += bob_x * 1.6 * bob_k * bob_amp
	rot.y += bob_x * 0.8 * bob_k
	var sway_k := 1.0 - 0.7 * ae
	pos.x -= sway * 0.014 * sway_k
	rot.y += sway * 3.5 * sway_k
	rot.z += sway * 3.0 * sway_k

	# ---- sprint
	if w == PISTOL or w == REVOLVER or w == MPISTOL:
		pos += Vector3(-0.03, -0.07, 0.04) * sp
		rot += Vector3(-28.0, 18.0, 10.0) * sp
	elif w == KNIFE:
		pos += Vector3(-0.02, -0.04, 0.03) * sp
		rot += Vector3(-15.0, 10.0, 6.0) * sp
	else:
		pos += Vector3(-0.045, -0.055, 0.05) * sp
		rot += Vector3(-14.0, 28.0, 20.0) * sp

	pos.y -= 0.012 * crouch * free

	# ---- recoil (knife: slash)
	var spring := sin((1.0 - kick) * PI * 2.2) * kick * 0.25
	if w == KNIFE:
		if kick > 0.0:
			var p := 1.0 - kick
			var times := PackedFloat32Array([0.0, 0.14, 0.36, 0.62, 1.0])
			var dpos := _kf(p, times, PackedVector3Array([Vector3.ZERO, Vector3(0.05, 0.07, 0.02), Vector3(-0.13, -0.05, -0.08), Vector3(-0.1, -0.08, -0.04), Vector3.ZERO]))
			var drot := _kf(p, times, PackedVector3Array([Vector3.ZERO, Vector3(15.0, -20.0, -30.0), Vector3(-20.0, 28.0, 45.0), Vector3(-15.0, 22.0, 32.0), Vector3.ZERO]))
			pos += dpos
			rot += drot
	else:
		var kc := kick * kick * (3.0 - 2.0 * kick)
		pos.z += (kc + spring) * r.kick_back * (1.0 - 0.4 * ae)
		pos.y += kc * r.kick_back * 0.12
		rot.x += (kc + spring * 0.6) * r.kick_rot * (1.0 - 0.35 * ae)
		rot.z += kc * r.kick_rot * 0.15 * sin(t * 37.0)

	# ---- reload: tilt + dip
	var rl := 0.0
	if reload > 0.0 and reload < 1.0:
		rl = _hump(reload, 0.0, 0.16, 0.84, 1.0)
	if rl > 0.0:
		var depth := 1.0 - 0.5 * ae
		match w:
			REVOLVER:
				rot += Vector3(8.0, -6.0, 20.0) * rl * depth
				pos += Vector3(0.0, -0.02, 0.01) * rl
			SHOTGUN:
				rot += Vector3(4.0, -10.0, -30.0) * rl * depth
				pos += Vector3(0.0, -0.01, 0.0) * rl
			DBARREL:
				rot += Vector3(14.0, -12.0, -12.0) * rl * depth
				pos += Vector3(-0.02, -0.01, 0.03) * rl
			RPG:
				rot += Vector3(-6.0, -6.0, -8.0) * rl * depth
				pos += Vector3(0.0, -0.03, 0.0) * rl
			KNIFE:
				rot += Vector3(10.0, -20.0, -25.0) * rl
			_:
				rot += Vector3(5.0, -10.0, -20.0) * rl * depth
				pos += Vector3(0.0, -0.012, 0.0) * rl

	# ---- switch / throw lowering
	if swch > 0.0:
		var se := swch * swch * (3.0 - 2.0 * swch)
		pos += Vector3(0.03, -0.32, 0.06) * se
		rot += Vector3(-35.0, 10.0, -10.0) * se
	var tw_low := 0.0
	if throw > 0.0 and throw < 1.0:
		tw_low = _hump(throw, 0.0, 0.14, 0.84, 1.0)
		pos += Vector3(0.05, -0.2, 0.05) * tw_low
		rot += Vector3(-28.0, -8.0, -12.0) * tw_low

	# ---- compose transform (rotation about the grip pivot)
	var b := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	r.root.transform = Transform3D(b, pos + r.pivot - b * r.pivot)

	# ---- per-weapon moving parts
	_animate_parts(r, w, kick, reload, _f(st, "empty") > 0.5)
	if r.left_arm != null:
		r.left_arm.visible = tw_low < 0.25

	# ---- scope / lens visibility
	var scoped := ads > 0.93 and not r.ads_only.is_empty()
	if not r.ads_only.is_empty():
		for c in r.root.get_children():
			var n3 := c as Node3D
			if n3 != null:
				n3.visible = (n3 in r.ads_only) == scoped
		if not scoped:
			for n in r.hip_only:
				n.visible = true

	# ---- muzzle flash
	if flash and r.flash_scale > 0.0 and swch < 0.5:
		_flash.visible = true
		var spin := fmod(t * 97.0, TAU)
		var fs := r.flash_scale * (0.85 + 0.3 * absf(sin(t * 53.0)))
		var ft := Transform3D(Basis(Vector3(0.0, 0.0, 1.0), spin).scaled(Vector3(fs, fs, fs)), r.muzzle)
		_flash.transform = r.root.transform * ft
		_flash_light.visible = true
		_flash_light.light_energy = 2.5 * r.flash_scale
		_flash_light.position = r.root.transform * (r.muzzle + Vector3(0.0, 0.03, 0.05))
		if scoped:
			_flash.visible = false
	else:
		_flash.visible = false
		_flash_light.visible = false
		_flash_light.light_energy = 0.0

	_animate_throw(throw)


func _animate_parts(r: Rig, w: int, kick: float, reload: float, empty: bool = false) -> void:
	var rel := reload > 0.0 and reload < 1.0
	# magazine swap + left hand
	var lhand := Vector3.ZERO
	var lrot := Vector3.ZERO
	if r.mag != null and w == RPG:
		# the spent rocket is gone; a new one slides in from the front, carried by the left hand
		var off := Vector3.ZERO
		var vis := not empty
		if rel:
			vis = reload > 0.36
			var u := smoothstep(0.36, 0.7, reload)
			off = _P(0.16, -0.14, -0.04).lerp(Vector3.ZERO, u)
			var grab := r.mag_grab - r.left_hand
			var below := grab + _P(0.0, -0.18, -0.02)
			var tt := PackedFloat32Array([0.0, 0.1, 0.24, 0.36, 0.7, 0.84, 1.0])
			lhand = _kf(reload, tt, PackedVector3Array([Vector3.ZERO, Vector3.ZERO, below, grab + off, grab, Vector3.ZERO, Vector3.ZERO]))
			if reload > 0.36 and reload < 0.7:
				lhand = grab + off
			lrot = Vector3(-30.0, 0.0, 70.0) * _hump(reload, 0.12, 0.3, 0.7, 0.84)
		r.mag.position = r.mag_rest + off
		r.mag.visible = vis
	elif r.mag != null:
		var mag_off := Vector3.ZERO
		var mag_vis := true
		if rel and w != REVOLVER and w != SHOTGUN:
			var p := reload
			if p > 0.12 and p < 0.32:
				var u := (p - 0.12) / 0.2
				mag_off = Vector3(0.0, -0.32 * u * u, 0.02 * u)
			elif p >= 0.32 and p < 0.5:
				mag_vis = false
			elif p >= 0.5 and p < 0.74:
				var u2 := smoothstep(0.5, 0.74, p)
				mag_off = Vector3(-0.01, -0.2, 0.0).lerp(Vector3.ZERO, u2)
			if r.left_arm != null and w != PISTOL and w != MPISTOL:
				var grab := r.mag_grab - r.left_hand
				var below := grab + Vector3(-0.04, -0.25, 0.05)
				var tt := PackedFloat32Array([0.0, 0.1, 0.2, 0.34, 0.5, 0.6, 0.74, 0.88, 1.0])
				lhand = _kf(p, tt, PackedVector3Array([Vector3.ZERO, Vector3.ZERO, grab, below, below, grab + Vector3(-0.01, -0.2, 0.0) * 0.6, grab, Vector3.ZERO, Vector3.ZERO]))
				lrot = Vector3(0.0, 0.0, 12.0) * _hump(p, 0.1, 0.2, 0.74, 0.88)
			elif r.left_arm != null:
				var below_p := Vector3(-0.05, -0.22, 0.06)
				var tt2 := PackedFloat32Array([0.0, 0.25, 0.4, 0.5, 0.74, 0.85])
				lhand = _kf(p, tt2, PackedVector3Array([Vector3.ZERO, Vector3.ZERO, below_p, below_p, mag_off + Vector3(-0.01, -0.03, 0.0), Vector3.ZERO]))
		r.mag.position = r.mag_rest + mag_off
		r.mag.visible = mag_vis
	match w:
		PISTOL, MPISTOL:
			var back := 0.03 * smoothstep(0.45, 0.8, kick)
			if rel:
				back = maxf(back, 0.03 * _hump(reload, 0.06, 0.12, 0.82, 0.88))
			r.anim.transform = r.anim_rest.translated(Vector3(0.0, 0.0, back))
		REVOLVER:
			var sw := 0.0
			var spin := 0.0
			if rel:
				sw = _hump(reload, 0.08, 0.22, 0.78, 0.9)
				spin = smoothstep(0.22, 0.4, reload) * TAU * 1.5 + smoothstep(0.78, 0.92, reload) * TAU
			var cyl_rot := Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(78.0) * sw)
			r.anim.transform = Transform3D(cyl_rot, r.anim_rest.origin)
			var kspin := (1.0 - kick) * TAU / 6.0 if kick > 0.0 else 0.0
			r.anim2.transform = Transform3D(Basis(Vector3(0.0, 0.0, 1.0), spin + kspin), r.anim2_rest.origin)
			if r.extra != null:
				r.extra.visible = rel and reload > 0.28 and reload < 0.7
			if rel and r.left_arm != null:
				var tgt := r.mag_grab
				var tt3 := PackedFloat32Array([0.0, 0.2, 0.32, 0.45, 0.62, 0.74, 0.86])
				lhand = _kf(reload, tt3, PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3(-0.06, -0.2, 0.08), tgt, tgt + Vector3(0.0, 0.0, -0.01), Vector3(-0.06, -0.2, 0.08), Vector3.ZERO]))
		SHOTGUN:
			var pump := 0.0
			if kick > 0.0:
				pump = sin(PI * clampf((0.88 - kick) / 0.6, 0.0, 1.0)) * 0.075
			r.anim.transform = r.anim_rest.translated(Vector3(0.0, 0.0, pump))
			var show := false
			if rel:
				var cyc := clampf((reload - 0.14) / 0.72, 0.0, 1.0) * 3.0
				var ph := fmod(cyc, 1.0)
				if reload > 0.14 and reload < 0.86:
					var port := r.mag_grab - r.left_hand
					var fetch := port + Vector3(-0.05, -0.2, 0.06)
					var tt4 := PackedFloat32Array([0.0, 0.3, 0.6, 0.8, 1.0])
					lhand = _kf(ph, tt4, PackedVector3Array([fetch, port + Vector3(0.0, -0.02, 0.02), port, port, fetch]))
					lrot = Vector3(0.0, 0.0, 18.0)
					show = ph < 0.75
				else:
					var e := smoothstep(0.0, 0.14, reload) * (1.0 - smoothstep(0.86, 1.0, reload))
					lhand = (r.mag_grab - r.left_hand + Vector3(-0.05, -0.2, 0.06)) * e
			if r.extra != null:
				r.extra.visible = show
		SNIPER:
			var lift := 0.0
			var pull := 0.0
			if kick > 0.0:
				var p := 1.0 - kick
				lift = _hump(p, 0.2, 0.32, 0.62, 0.74)
				pull = _hump(p, 0.32, 0.44, 0.5, 0.62)
			if rel:
				lift = maxf(lift, _hump(reload, 0.06, 0.14, 0.82, 0.92))
				pull = maxf(pull, _hump(reload, 0.14, 0.22, 0.74, 0.82))
			var bb := Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(65.0) * lift)
			r.anim.transform = Transform3D(bb, r.anim_rest.origin + Vector3(0.0, 0.0, 0.07 * pull))
		LMG:
			var op := 0.0
			if rel:
				op = _hump(reload, 0.08, 0.2, 0.76, 0.88)
			r.anim.transform = Transform3D(Basis(Vector3(1.0, 0.0, 0.0), deg_to_rad(55.0) * op), r.anim_rest.origin)
		DMR:
			var back2 := 0.045 * smoothstep(0.5, 0.85, kick)
			if rel:
				back2 = maxf(back2, 0.06 * _hump(reload, 0.72, 0.8, 0.84, 0.9))
			r.anim.transform = r.anim_rest.translated(Vector3(0.0, 0.0, back2))
		DBARREL:
			var open := 0.0
			var show := false
			if rel:
				open = _hump(reload, 0.04, 0.16, 0.82, 0.92)
				var breech := r.mag_grab - r.left_hand
				var fetch := breech + Vector3(-0.06, -0.24, 0.08)
				var tt5 := PackedFloat32Array([0.0, 0.16, 0.3, 0.42, 0.55, 0.66, 0.8, 1.0])
				lhand = _kf(reload, tt5, PackedVector3Array([Vector3.ZERO, Vector3.ZERO, fetch, fetch, breech, breech, Vector3.ZERO, Vector3.ZERO]))
				lrot = Vector3(0.0, 0.0, 20.0) * _hump(reload, 0.16, 0.3, 0.66, 0.8)
				show = reload > 0.36 and reload < 0.6
			r.anim.transform = Transform3D(Basis(Vector3(1.0, 0.0, 0.0), -deg_to_rad(34.0) * open), r.anim_rest.origin)
			if r.extra != null:
				r.extra.visible = show
	if r.left_arm != null:
		var lb := Basis.from_euler(lrot * (PI / 180.0))
		r.left_arm.transform = Transform3D(lb, lhand + r.left_hand - lb * r.left_hand)


# ------------------------------------------------------------- icons ----

var _icon_light: DirectionalLight3D = null


## Side-view icon rendering (weapon_icons.gd, on its own instance): shows rig w alone at rest,
## without arms, flash or scope overlay, seen from its right side by an orthographic camera
## fitted to the gun (muzzle to the right of the image).
func icon_pose(w: int) -> void:
	if not _ready_done or w < 0 or w >= _rigs.size():
		return
	var r: Rig = _rigs[w]
	for i in _rigs.size():
		_rigs[i].root.visible = (i == w)
	_cur = -1
	r.root.transform = Transform3D.IDENTITY
	_animate_parts(r, w, 0.0, 0.0)
	if r.icon_keep != null and r.icon_keep.get_parent() != r.root:
		r.icon_keep.reparent(r.root, false)
		r.icon_keep.transform = Transform3D(Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0)) * Basis.from_scale(Vector3(1.15, 1.2, 1.15)), Vector3.ZERO)
	for n: Node3D in [r.right_arm, r.left_arm, r.extra]:
		if n != null:
			n.visible = false
	for n in r.ads_only:
		n.visible = false
	for n in r.hip_only:
		n.visible = true
	_flash.visible = false
	_flash_light.visible = false
	_throw_arm.visible = false
	_fly_nade.visible = false
	# fit the camera to the visible meshes
	var box := AABB()
	var first := true
	var stack: Array[Node] = [r.root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var n3 := n as Node3D
		if n3 != null and not n3.visible:
			continue
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			var bb: AABB = mi.global_transform * mi.get_aabb()
			box = bb if first else box.merge(bb)
			first = false
		stack.append_array(n.get_children())
	var c := box.get_center()
	var aspect := float(maxi(size.x, 1)) / float(maxi(size.y, 1))
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.size = maxf(box.size.y, box.size.z / aspect) * 1.04
	_cam.near = 0.01
	_cam.far = 10.0
	_cam.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(box.end.x + 1.0, c.y, c.z))
	if _icon_light == null:
		# brighter than in-game so the dark metal reads on dark UI backgrounds
		for c2 in _world.get_children():
			var we := c2 as WorldEnvironment
			if we != null:
				we.environment.ambient_light_energy = 1.25
				we.environment.ambient_light_color = Color(0.62, 0.64, 0.7)
		_icon_light = DirectionalLight3D.new()
		_icon_light.light_color = Color(1.0, 0.97, 0.92)
		_icon_light.light_energy = 1.7
		_icon_light.transform = Transform3D(Basis.looking_at(Vector3(-0.75, -0.55, -0.35).normalized(), Vector3.UP), Vector3.ZERO)
		_world.add_child(_icon_light)


func _animate_throw(throw: float) -> void:
	if throw <= 0.0 or throw >= 1.0:
		_throw_arm.visible = false
		_fly_nade.visible = false
		return
	_throw_arm.visible = true
	var tt := PackedFloat32Array([0.0, 0.22, 0.42, 0.56, 0.66, 0.82, 1.0])
	var ppos := PackedVector3Array([
		Vector3(-0.2, -0.6, -0.5), Vector3(-0.17, -0.15, -0.5), Vector3(-0.1, -0.03, -0.38),
		Vector3(-0.11, -0.01, -0.45), Vector3(-0.07, -0.05, -0.7), Vector3(-0.03, -0.35, -0.6), Vector3(-0.05, -0.7, -0.5)])
	var prot := PackedVector3Array([
		Vector3(-20.0, 20.0, 0.0), Vector3(5.0, 15.0, -10.0), Vector3(35.0, 10.0, -20.0),
		Vector3(25.0, 5.0, -10.0), Vector3(-35.0, 0.0, 0.0), Vector3(-50.0, 0.0, 0.0), Vector3(-60.0, 0.0, 0.0)])
	_throw_arm.position = _kf(throw, tt, ppos)
	var rr := _kf(throw, tt, prot)
	_throw_arm.rotation_degrees = rr
	var released := throw > 0.6
	_throw_nade.visible = not released
	if released and throw < 0.9:
		_fly_nade.visible = true
		var u := (throw - 0.6) / 0.3
		var start := _kf(0.6, tt, ppos) + Vector3(0.0, 0.03, -0.02)
		_fly_nade.position = start + Vector3(0.03 * u, 0.12 * u - 0.05 * u * u, -1.6 * u)
		_fly_nade.rotation = Vector3(u * 9.0, u * 3.0, 0.0)
	else:
		_fly_nade.visible = false
