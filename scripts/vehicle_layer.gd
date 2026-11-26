extends SubViewport
## Real 3D vehicles composited into the raycast view (shaders/raycast.gdshader, veh3d_*).
##
##   var vl = preload("res://scripts/vehicle_layer.gd").new()
##   raycast_subviewport.add_child(vl)      # as a child it is rendered before the raycast pass
##   mat.set_shader_parameter("veh3d_col", vl.get_texture())
##   mat.set_shader_parameter("veh3d_depth", vl.depth_texture())
##   every frame: vl.begin(); vl.push(...) for each visible vehicle;
##                mat.set_shader_parameter("veh3d_on", vl.finish(size, cam_pos, yaw, plen, bob, look, eye, time, dt))
##
## This viewport renders the lit colour (layer 1); a second SubViewport sharing the same World3D renders
## every mesh again (depth twins on layer 2) with a shader that writes the linear forward distance
## (along the camera axis, world units) as 16-bit fixed point in RG, B = 1 solid / 0.5 ground shadow.
## World mapping: map (x, y, height z) -> Vector3(x, z, y). The model frame (+X nose, +Z right, +Y up)
## then maps without mirroring: hull angle a -> rotation.y = -a.
## The raycaster's look is a y-shear, so the camera stays level and uses an off-centre frustum.

const VM := preload("res://scripts/vehicle_models.gd")
const Defs := preload("res://scripts/defs.gd")

const DEPTH_RANGE := 64.0
const NEAR := 0.05
const FAR := 90.0
const L_COL := 1
const L_DEPTH := 2
## elevation trunnion in the Gun node's local frame, per vtype
const ELEV_PIVOT := [Vector3.ZERO, Vector3.ZERO, Vector3(0.18, 0.555, 0.0), Vector3(0.0, 0.645, 0.0), Vector3.ZERO]
const ELEV_MIN := [-0.17, -0.17, -0.3, -0.3, -0.05]
const ELEV_MAX := [0.35, 0.35, 0.7, 0.9, 0.8]
const RECOIL := [0.08, 0.05, 0.015, 0.015, 0.0]
const FLASH_SIZE := [1.6, 1.25, 0.6, 0.75, 0.0]

const DEPTH_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, shadows_disabled, ambient_light_disabled, fog_disabled, specular_disabled;
uniform float depth_range = 64.0;
uniform float flag = 1.0;
uniform bool ellipse = false;
varying float vdist;
void vertex() {
	vdist = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}
void fragment() {
	if (ellipse && length(UV * 2.0 - 1.0) > 0.8) discard;
	// The Compatibility pipeline passes mid/high 8-bit values through ~exactly (+-1) but crushes values
	// below ~50 (measured by readback), so every channel carries a base-54 digit stored as 96 + 3 * n.
	// R, G: coarse digits (54 * 54 steps); B: 27 fine steps + 27 if solid (0 = ground shadow).
	float x = clamp(vdist / depth_range, 0.0, 0.999999) * 2916.0;
	float a = floor(x / 54.0);
	float b = floor(x - a * 54.0);
	float c = floor(fract(x) * 27.0) + (flag > 0.75 ? 27.0 : 0.0);
	ALBEDO = (vec3(a, b, c) * 3.0 + 96.0) / 255.0;
}
"""

const SHADOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float strength = 0.55;
void fragment() {
	float r = length(UV * 2.0 - 1.0);
	ALBEDO = vec3(0.0);
	ALPHA = strength * (1.0 - smoothstep(0.3, 0.8, r));
}
"""


class Parts:
	var body: ArrayMesh
	var body_xf: Transform3D
	var tur: ArrayMesh
	var tur_xf: Transform3D       # turret mesh frame relative to the yaw pivot node
	var gun: ArrayMesh
	var gun_xf: Transform3D       # Gun node relative to the turret node
	var muzzle: Vector3           # in the Gun node frame
	var extent: AABB              # body bounds (shadow size)
	var paint: Material


class VInst:
	var root: Node3D
	var chassis: Node3D
	var yaw_n: Node3D
	var gun_n: Node3D
	var gun_mi: MeshInstance3D
	var gun_rest: Transform3D
	var gun_pivot: Vector3
	var flash: Node3D
	var meshes: Array[MeshInstance3D] = []
	var vt := 0
	var wreck := false
	var team := -99
	var pos := Vector2.ZERO
	var hull := 0.0
	var tur := 0.0
	var pitch := 0.0
	var kick := 0.0
	var moving := false
	var firing := false
	var heads: Node3D               # headlight glow (shown at dusk / night / bad weather)
	var fresh := true
	var seen := false
	var last_seen := 0.0
	var phase := 0.0


static var _parts: Dictionary = {}

var _dvp: SubViewport
var _world: World3D
var _cam: Camera3D
var _dcam: Camera3D
var _scene: Node3D
var _depth_mat: ShaderMaterial
var _depth_shadow_mat: ShaderMaterial
var _shadow_mat: ShaderMaterial
var _flash_mat: StandardMaterial3D
var _team_mats: Dictionary = {}
var _insts: Dictionary = {}       # entity id -> VInst
var _count := 0
var _time := 0.0
var _dt := 0.016
var _flash_mesh: SphereMesh
var _shadow_mesh: PlaneMesh
var _env: Environment
var _key: DirectionalLight3D
var _fill: DirectionalLight3D
var _head_mat: StandardMaterial3D
var _heads_on := false


func _init() -> void:
	transparent_bg = true
	own_world_3d = false
	msaa_3d = Viewport.MSAA_DISABLED
	screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	use_taa = false
	positional_shadow_atlas_size = 0
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	size = Vector2i(320, 180)
	_world = World3D.new()
	world_3d = _world

	_dvp = SubViewport.new()
	_dvp.transparent_bg = true
	_dvp.own_world_3d = false
	_dvp.world_3d = _world
	_dvp.msaa_3d = Viewport.MSAA_DISABLED
	_dvp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_dvp.use_taa = false
	_dvp.positional_shadow_atlas_size = 0
	_dvp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_dvp.size = size
	add_child(_dvp)

	_scene = Node3D.new()
	_scene.name = "VehicleLayerWorld"
	add_child(_scene)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.56, 0.58, 0.64)
	env.ambient_light_energy = 0.62
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_env = env
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_FRUSTUM
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.cull_mask = L_COL
	_cam.environment = env
	_cam.current = true
	add_child(_cam)
	var denv := Environment.new()
	denv.background_mode = Environment.BG_CLEAR_COLOR
	denv.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	denv.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	denv.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_dcam = Camera3D.new()
	_dcam.projection = Camera3D.PROJECTION_FRUSTUM
	_dcam.keep_aspect = Camera3D.KEEP_WIDTH
	_dcam.cull_mask = L_DEPTH
	_dcam.environment = denv
	_dcam.current = true
	_dvp.add_child(_dcam)

	# sun roughly matching the raycaster's four-way light (+x faces brightest, then +y) and the sky's sun
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.93, 0.8)
	key.light_energy = 1.2
	key.shadow_enabled = false
	key.layers = L_COL
	key.transform = Transform3D(Basis.looking_at(Vector3(-0.62, -0.75, -0.42).normalized(), Vector3.UP), Vector3.ZERO)
	_scene.add_child(key)
	_key = key
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.7, 0.8, 1.0)
	fill.light_energy = 0.3
	fill.shadow_enabled = false
	fill.layers = L_COL
	fill.transform = Transform3D(Basis.looking_at(Vector3(0.6, -0.25, 0.7).normalized(), Vector3.UP), Vector3.ZERO)
	_scene.add_child(fill)
	_fill = fill
	_head_mat = StandardMaterial3D.new()
	_head_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_head_mat.albedo_color = Color(1.0, 0.97, 0.82)

	var dsh := Shader.new()
	dsh.code = DEPTH_SHADER
	_depth_mat = ShaderMaterial.new()
	_depth_mat.shader = dsh
	_depth_mat.set_shader_parameter("depth_range", DEPTH_RANGE)
	_depth_mat.set_shader_parameter("flag", 1.0)
	_depth_shadow_mat = ShaderMaterial.new()
	_depth_shadow_mat.shader = dsh
	_depth_shadow_mat.set_shader_parameter("depth_range", DEPTH_RANGE)
	_depth_shadow_mat.set_shader_parameter("flag", 0.5)
	_depth_shadow_mat.set_shader_parameter("ellipse", true)
	var ssh := Shader.new()
	ssh.code = SHADOW_SHADER
	_shadow_mat = ShaderMaterial.new()
	_shadow_mat.shader = ssh
	_shadow_mat.render_priority = -1
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.albedo_color = Color(1.0, 0.78, 0.35)
	_flash_mesh = SphereMesh.new()
	_flash_mesh.radius = 0.05
	_flash_mesh.height = 0.1
	_flash_mesh.radial_segments = 8
	_flash_mesh.rings = 4
	_shadow_mesh = PlaneMesh.new()
	_shadow_mesh.size = Vector2(1.0, 1.0)


func depth_texture() -> ViewportTexture:
	return _dvp.get_texture()


## Time of day / weather (atmos.gd look()): dims the sun, fill and ambient, switches the headlight glow.
func set_atmos(lk: Dictionary) -> void:
	var a: Vector3 = lk.get("ambient", Vector3.ONE)
	var lum := maxf(0.05, a.x * 0.3 + a.y * 0.59 + a.z * 0.11)
	var hue := Color(a.x / lum, a.y / lum, a.z / lum)
	_env.ambient_light_color = Color(0.56 * hue.r, 0.58 * hue.g, 0.64 * hue.b)
	_env.ambient_light_energy = 0.62 * lum
	_key.light_color = Color(minf(1.0, 1.0 * hue.r), minf(1.0, 0.93 * hue.g), minf(1.0, 0.8 * hue.b))
	_key.light_energy = 1.2 * lum
	_fill.light_energy = 0.3 * lum
	_heads_on = bool(lk.get("heads", false))
	for k in _insts.keys():
		var vi: VInst = _insts[k]
		if vi.heads != null:
			vi.heads.visible = _heads_on


# ------------------------------------------------------------------ meshes ----

static func _parts_for(vt: int, wreck: bool) -> Parts:
	var key := vt * 2 + (1 if wreck else 0)
	if _parts.has(key):
		var cached: Parts = _parts[key]
		return cached
	var p := Parts.new()
	p.paint = VM.paint_material()
	var root: Node3D = VM.build(vt, "all", wreck)
	var body := root.get_node("Body") as Node3D
	var tur := root.get_node("Turret") as Node3D
	var gun := tur.find_child("Gun", true, false) as Node3D
	p.body_xf = body.transform
	p.body = _flatten(body, null)
	p.extent = p.body.get_aabb()
	var pv: Vector2 = VM.TURRET_PIVOT[vt]
	p.tur_xf = Transform3D(tur.transform.basis, tur.transform.origin - Vector3(pv.x, 0.0, pv.y))
	p.tur = _flatten(tur, gun)
	if gun != null:
		var gx := gun.transform
		var n := gun.get_parent() as Node3D
		while n != null and n != tur:
			gx = n.transform * gx
			n = n.get_parent() as Node3D
		p.gun_xf = gx
		p.gun = _flatten(gun, null)
		var bb := p.gun.get_aabb()
		p.muzzle = Vector3(bb.end.x, bb.get_center().y, bb.get_center().z)
		if vt == VM.TANK or vt == VM.BRONEVIKS:
			p.muzzle.y = 0.0
			p.muzzle.z = 0.0
	root.free()
	_parts[key] = p
	return p


## Merges every visible MeshInstance3D below `top` (in top's local frame, skipping `skip`'s subtree)
## into one ArrayMesh with one surface per material.
static func _flatten(top: Node3D, skip: Node) -> ArrayMesh:
	var groups := {}
	for c in top.get_children():
		_gather(c, Transform3D.IDENTITY, groups, skip)
	var out := ArrayMesh.new()
	for mat: Material in groups.keys():
		var g: Array = groups[mat]
		var verts: PackedVector3Array = g[0]
		if verts.size() == 0:
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g[0]
		arrays[Mesh.ARRAY_NORMAL] = g[1]
		arrays[Mesh.ARRAY_INDEX] = g[2]
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, mat)
	return out


static func _gather(n: Node, xf: Transform3D, groups: Dictionary, skip: Node) -> void:
	if n == skip:
		return
	var t := xf
	if n is Node3D:
		var n3 := n as Node3D
		if not n3.visible:
			return
		t = xf * n3.transform
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mat: Material = mi.material_override
		if mi.mesh != null and mat != null:
			if not groups.has(mat):
				groups[mat] = [PackedVector3Array(), PackedVector3Array(), PackedInt32Array()]
			var g: Array = groups[mat]
			var verts: PackedVector3Array = g[0]
			var norms: PackedVector3Array = g[1]
			var idx: PackedInt32Array = g[2]
			var nb := Transform3D(t.basis.inverse().transposed(), Vector3.ZERO)
			for s in mi.mesh.get_surface_count():
				var arr: Array = mi.mesh.surface_get_arrays(s)
				var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				var base := verts.size()
				verts.append_array(t * v)
				if nr.size() == v.size():
					var tn: PackedVector3Array = nb * nr
					for i in tn.size():
						tn[i] = tn[i].normalized()
					norms.append_array(tn)
				else:
					var up := PackedVector3Array()
					up.resize(v.size())
					up.fill(Vector3.UP)
					norms.append_array(up)
				var ii: Variant = arr[Mesh.ARRAY_INDEX]
				if ii is PackedInt32Array and (ii as PackedInt32Array).size() > 0:
					var src: PackedInt32Array = ii
					var off := idx.size()
					idx.resize(off + src.size())
					for i in src.size():
						idx[off + i] = src[i] + base
				else:
					var off2 := idx.size()
					idx.resize(off2 + v.size())
					for i in v.size():
						idx[off2 + i] = base + i
			g[0] = verts
			g[1] = norms
			g[2] = idx
	for c in n.get_children():
		_gather(c, t, groups, skip)


func _team_mat(team: int) -> Material:
	if _team_mats.has(team):
		var m0: Material = _team_mats[team]
		return m0
	var c := Color(0.45, 0.47, 0.4)
	if team >= 0 and team < Defs.TEAM_COLORS.size():
		c = Defs.TEAM_COLORS[team]
	var m := StandardMaterial3D.new()
	m.albedo_color = c.lerp(Color(0.5, 0.5, 0.45), 0.12)
	m.roughness = 0.8
	m.metallic_specular = 0.3
	_team_mats[team] = m
	return m


## A colour MeshInstance3D plus its depth twin (child, same transform).
func _mesh(parent: Node3D, mesh: Mesh, xf: Transform3D, vi: VInst, dmat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	mi.layers = L_COL
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var d := MeshInstance3D.new()
	d.mesh = mesh
	d.layers = L_DEPTH
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	d.material_override = dmat if dmat != null else _depth_mat
	mi.add_child(d)
	vi.meshes.append(mi)
	return mi


func _paint(vi: VInst, p: Parts) -> void:
	var tm := _team_mat(vi.team)
	for mi in vi.meshes:
		var am := mi.mesh as ArrayMesh
		if am == null:
			continue
		for s in am.get_surface_count():
			if am.surface_get_material(s) == p.paint:
				mi.set_surface_override_material(s, tm)


func _build(vt: int, wreck: bool, team: int) -> VInst:
	var p := _parts_for(vt, wreck)
	var vi := VInst.new()
	vi.vt = vt
	vi.wreck = wreck
	vi.team = team
	vi.phase = randf() * TAU
	vi.root = Node3D.new()
	_scene.add_child(vi.root)
	# soft blob shadow on the ground (darkens the raycast floor in the composite)
	var ex := p.extent
	var sh := MeshInstance3D.new()
	sh.mesh = _shadow_mesh
	sh.material_override = _shadow_mat
	sh.layers = L_COL
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sh.transform = Transform3D(Basis.from_scale(Vector3(ex.size.x * 1.2, 1.0, ex.size.z * 1.25)), Vector3(ex.get_center().x, 0.012, ex.get_center().z))
	vi.root.add_child(sh)
	var shd := MeshInstance3D.new()
	shd.mesh = _shadow_mesh
	shd.material_override = _depth_shadow_mat
	shd.layers = L_DEPTH
	shd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sh.add_child(shd)

	vi.chassis = Node3D.new()
	vi.root.add_child(vi.chassis)
	_mesh(vi.chassis, p.body, p.body_xf, vi)
	var pv: Vector2 = VM.TURRET_PIVOT[vt]
	vi.yaw_n = Node3D.new()
	vi.yaw_n.position = Vector3(pv.x, 0.0, pv.y)
	vi.chassis.add_child(vi.yaw_n)
	var tmi := _mesh(vi.yaw_n, p.tur, p.tur_xf, vi)
	if p.gun != null:
		var piv: Vector3 = ELEV_PIVOT[vt]
		vi.gun_pivot = piv
		vi.gun_n = Node3D.new()
		vi.gun_rest = p.gun_xf * Transform3D(Basis.IDENTITY, piv)
		vi.gun_n.transform = vi.gun_rest
		tmi.add_child(vi.gun_n)
		vi.gun_mi = _mesh(vi.gun_n, p.gun, Transform3D(Basis.IDENTITY, -piv), vi)
		var fs: float = FLASH_SIZE[vt]
		if not wreck and fs > 0.0:
			vi.flash = Node3D.new()
			vi.flash.position = p.muzzle - piv + Vector3(0.06 * fs, 0.0, 0.0)
			vi.gun_n.add_child(vi.flash)
			var fm := MeshInstance3D.new()
			fm.mesh = _flash_mesh
			fm.material_override = _flash_mat
			fm.layers = L_COL
			fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fm.scale = Vector3(2.2, 1.0, 1.0) * fs
			vi.flash.add_child(fm)
			var fd := MeshInstance3D.new()
			fd.mesh = _flash_mesh
			fd.material_override = _depth_mat
			fd.layers = L_DEPTH
			fd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fm.add_child(fd)
			vi.flash.visible = false
	if not wreck:
		# two headlamps on the nose (colour layer + depth twins so they count as solid)
		vi.heads = Node3D.new()
		vi.chassis.add_child(vi.heads)
		for sgn in [-1.0, 1.0]:
			var hm := MeshInstance3D.new()
			hm.mesh = _flash_mesh
			hm.material_override = _head_mat
			hm.layers = L_COL
			hm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			hm.position = Vector3(ex.end.x + 0.01, ex.position.y + ex.size.y * 0.42, ex.get_center().z + float(sgn) * ex.size.z * 0.3)
			hm.scale = Vector3(0.5, 0.9, 0.9)
			vi.heads.add_child(hm)
			var hd := MeshInstance3D.new()
			hd.mesh = _flash_mesh
			hd.material_override = _depth_mat
			hd.layers = L_DEPTH
			hd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			hm.add_child(hd)
		vi.heads.visible = _heads_on
	_paint(vi, p)
	return vi


# --------------------------------------------------------------- per frame ----

func begin() -> void:
	_count = 0
	for k in _insts.keys():
		var vi: VInst = _insts[k]
		vi.seen = false


## One visible vehicle from the snapshot. fl: bit0 firing, bit1 moving, bits 8-11 vtype, bits 12-19 gun pitch.
func push(id: int, wreck: bool, vtype: int, pos: Vector2, hull: float, turret: float, team: int, fl: int) -> void:
	var vt := clampi(vtype, 0, VM.NUM_TYPES - 1)
	var key := id
	var vi: VInst = null
	if _insts.has(key):
		vi = _insts[key]
		if vi.vt != vt or vi.wreck != wreck:
			vi.root.queue_free()
			_insts.erase(key)
			vi = null
	if vi == null:
		vi = _build(vt, wreck, team)
		_insts[key] = vi
	elif vi.team != team and not wreck:
		vi.team = team
		_paint(vi, _parts_for(vt, wreck))
	var pb := (fl >> 12) & 255
	var pitch := 0.0 if pb == 0 or wreck else float(pb) / 127.5 - 1.0
	pitch = clampf(pitch, float(ELEV_MIN[vt]), float(ELEV_MAX[vt]))
	var rel := 0.0 if wreck else angle_difference(hull, turret)
	var firing := (fl & 1) != 0 and not wreck
	if firing and not vi.firing:
		vi.kick = 1.0
	vi.firing = firing
	vi.moving = (fl & 2) != 0 and not wreck
	vi.seen = true
	vi.last_seen = _time
	vi.root.visible = true
	if vi.fresh or vi.pos.distance_squared_to(pos) > 4.0:
		vi.fresh = false
		vi.pos = pos
		vi.hull = hull
		vi.tur = rel
		vi.pitch = pitch
	else:
		# snapshots arrive at 60 Hz: ease towards them so faster displays do not see steps
		var k := 1.0 - exp(-_dt * 35.0)
		vi.pos = vi.pos.lerp(pos, k)
		vi.hull = lerp_angle(vi.hull, hull, k)
		vi.tur = lerp_angle(vi.tur, rel, k)
		vi.pitch = lerpf(vi.pitch, pitch, k)
	_count += 1


## Updates the cameras and poses; returns whether anything is drawn (feed it to veh3d_on).
func finish(sz: Vector2i, cpos: Vector2, yaw: float, plen: float, bob: float, look: float, eye: float, t: float, dt: float) -> bool:
	_time = t
	_dt = dt
	var dead: Array = []
	for k in _insts.keys():
		var vi: VInst = _insts[k]
		if not vi.seen:
			vi.root.visible = false
			vi.fresh = true
			if _time - vi.last_seen > 8.0:
				dead.append(k)
			continue
		_pose(vi, dt)
	for k in dead:
		var vi: VInst = _insts[k]
		vi.root.queue_free()
		_insts.erase(k)
	if _count == 0:
		render_target_update_mode = SubViewport.UPDATE_DISABLED
		_dvp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return false
	var s := Vector2i(maxi(1, sz.x), maxi(1, sz.y))
	if size != s:
		size = s
		_dvp.size = s
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_dvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var aspect := float(s.x) / float(s.y)
	var fwd := Vector3(cos(yaw), 0.0, sin(yaw))
	var right := Vector3(-sin(yaw), 0.0, cos(yaw))
	var xf := Transform3D(Basis(right, Vector3.UP, -fwd), Vector3(cpos.x, eye, cpos.y))
	# screen x: sx = lat / (dz * plen); screen y: horizon shifted by (bob + look) of the height (y-shear)
	var w := 2.0 * NEAR * plen
	var off := Vector2(0.0, 2.0 * (bob + look) * NEAR * plen / aspect)
	for c: Camera3D in [_cam, _dcam]:
		c.transform = xf
		c.set_frustum(w, off, NEAR, FAR)
	return true


func _pose(vi: VInst, dt: float) -> void:
	vi.root.transform = Transform3D(Basis(Vector3.UP, -vi.hull), Vector3(vi.pos.x, 0.0, vi.pos.y))
	if vi.moving:
		var ph := _time + vi.phase
		vi.chassis.position = Vector3(0.0, absf(sin(ph * 11.0)) * 0.008 + sin(ph * 37.0) * 0.002, 0.0)
		vi.chassis.rotation = Vector3(sin(ph * 6.3) * 0.006, 0.0, sin(ph * 4.1) * 0.01)
	elif not vi.wreck:
		vi.chassis.position = Vector3(0.0, sin((_time + vi.phase) * 41.0) * 0.0012, 0.0)
		vi.chassis.rotation = Vector3.ZERO
	vi.yaw_n.rotation = Vector3(0.0, -vi.tur, 0.0)
	vi.kick = maxf(0.0, vi.kick - dt * 5.0)
	if vi.gun_n != null and not vi.wreck:
		vi.gun_n.transform = vi.gun_rest * Transform3D(Basis(Vector3(0, 0, 1), vi.pitch), Vector3.ZERO)
		var back: float = RECOIL[vi.vt]
		var jit := 0.0
		if vi.firing and (vi.vt == VM.MOTO or vi.vt == VM.JEEP):
			jit = sin(_time * 90.0) * 0.004
		vi.gun_mi.position = -vi.gun_pivot + Vector3(-back * vi.kick + jit, 0.0, 0.0)
	if vi.flash != null:
		var on := vi.firing and fmod(_time * 24.0 + vi.phase, 1.0) < 0.55
		vi.flash.visible = on
		if on:
			var r := 0.8 + 0.4 * fmod(_time * 37.0 + vi.phase * 3.0, 1.0)
			vi.flash.scale = Vector3(r, r * 0.9, r * 0.9)
			vi.flash.rotation = Vector3(fmod(_time * 13.0, TAU), 0.0, 0.0)
