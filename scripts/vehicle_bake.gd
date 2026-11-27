extends Node
## Bakes the 3D vehicle models (vehicle_models.gd) into one rotated sprite atlas.
##
##   var vb: Node = preload("res://scripts/vehicle_bake.gd").new()
##   add_child(vb)
##   var atlas: Image = await vb.bake()
##
## Layout: F x F frames (F = 128), 16 columns x 20 rows (2048 x 2560, RGBA8).
##   column a (0..15): view angle rel = a * 22.5 deg; rel 0 = nose towards the viewer,
##                     rel +90 = nose pointing to the image's left, 180 = seen from behind.
##   row = vtype * 4 + k, k: 0 hull, 1 turret, 2 wreck hull, 3 wreck turret.
## Each frame: orthographic, looking down PITCH_DEG, VIEW world units wide/high; the part's origin
## (ground point under its pivot) lies at x = F/2, y = F - 1 - GROUND_PX. Turret frames are centred
## on the turret pivot (turret alone at its true height).
## Alpha: 0 = empty, 255 = fixed colour, PAINT_ALPHA (153) = team paint: rgb holds the lit
## grayscale luminance of a light-grey paint (multiply by the team colour when drawing).

const VM := preload("res://scripts/vehicle_models.gd")

const CACHE_VERSION := 1
const F := 128
const COLS := 16
const ROWS := 20
const PARTS_PER_TYPE := 4
const VIEW := 2.4
const PITCH_DEG := 8.0
const GROUND_PX := 6
const PAINT_ALPHA := 153
const ANGLE_STEP := 22.5

const COMBINE_SHADER := """
shader_type canvas_item;
render_mode blend_disabled, unshaded;
uniform sampler2D col_tex : filter_nearest;
uniform sampler2D mask_tex : filter_nearest;
uniform float paint_alpha = 0.6;
void fragment() {
	ivec2 sz = textureSize(col_tex, 0);
	ivec2 p = clamp(ivec2(floor(UV * vec2(sz))), ivec2(0), sz - ivec2(1));
	vec4 c = texelFetch(col_tex, p, 0);
	vec4 m = texelFetch(mask_tex, p, 0);
	if (c.a < 0.5) {
		COLOR = vec4(0.0);
	} else if (m.r > 0.5) {
		float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		COLOR = vec4(vec3(l), paint_alpha);
	} else {
		COLOR = vec4(c.rgb, 1.0);
	}
}
"""

var last_bake_ms := 0
var debug_timing := false


static func cache_path() -> String:
	return "user://vehicles_v%d.png" % CACHE_VERSION


## Pixel offset (dx right, dy down) at which a point at hull-frame offset (fwd, right) appears in a
## frame drawn at view angle rel_deg, relative to the hull origin's pixel. Useful to place turret
## frames over hull frames: offset(TURRET_PIVOT[vtype], a * 22.5).
static func pivot_px(off: Vector2, rel_deg: float) -> Vector2:
	var th := -deg_to_rad(rel_deg + 90.0)
	var w := Vector3(off.x, 0.0, off.y).rotated(Vector3.UP, th)
	var up := Vector3(0.0, cos(deg_to_rad(PITCH_DEG)), -sin(deg_to_rad(PITCH_DEG)))
	var u := VIEW / float(F)
	return Vector2(w.x / u, -w.dot(up) / u)


func bake(use_cache: bool = true) -> Image:
	if DisplayServer.get_name() == "headless":
		return Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var path := cache_path()
	if use_cache and FileAccess.file_exists(path):
		var cached := Image.load_from_file(path)
		if cached != null and cached.get_width() == F * COLS and cached.get_height() == F * ROWS:
			if cached.get_format() != Image.FORMAT_RGBA8:
				cached.convert(Image.FORMAT_RGBA8)
			return cached
	var t0 := Time.get_ticks_msec()
	var img: Image = await _render()
	last_bake_ms = Time.get_ticks_msec() - t0
	if img.get_width() == F * COLS:
		img.save_png(path)
	return img


func _render() -> Image:
	var W := F * COLS
	var H := F * ROWS
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	vp.positional_shadow_atlas_size = 0
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)

	var world := Node3D.new()
	vp.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.56, 0.58, 0.64)
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.92, 0.78)
	key.light_energy = 1.25
	key.shadow_enabled = false
	key.transform = Transform3D(Basis.looking_at(Vector3(0.55, -0.7, -0.45).normalized(), Vector3.UP), Vector3.ZERO)
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.7, 0.8, 1.0)
	fill.light_energy = 0.3
	fill.shadow_enabled = false
	fill.transform = Transform3D(Basis.looking_at(Vector3(-0.7, -0.2, 0.5).normalized(), Vector3.UP), Vector3.ZERO)
	world.add_child(fill)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = VIEW * float(ROWS)
	cam.near = 0.5
	cam.far = 200.0
	var cb := Basis(Vector3(1, 0, 0), -deg_to_rad(PITCH_DEG))
	cam.transform = Transform3D(cb, cb.z * 80.0)
	cam.current = true
	world.add_child(cam)
	var right := cb.x
	var up := cb.y
	var u := VIEW / float(F)

	# instances: one per frame; each part is flattened into one multi-surface mesh (one surface per
	# material) so the whole atlas is a few thousand draw calls
	var paint: Material = VM.paint_material()
	var insts: Array[MeshInstance3D] = []
	var t_build := Time.get_ticks_msec()
	for v in 5:   # ground vehicles only (planes always use the real 3D layer)
		for k in PARTS_PER_TYPE:
			var part := "hull" if k % 2 == 0 else "turret"
			var wreck := k >= 2
			var tmpl: Node3D = VM.build(v, part, wreck)
			var mesh := _flatten(tmpl)
			tmpl.free()
			var row := v * PARTS_PER_TYPE + k
			for a in COLS:
				var inst := MeshInstance3D.new()
				inst.mesh = mesh
				inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var px := float(a * F) + float(F) * 0.5 - float(W) * 0.5
				var py := float(row * F) + float(F - 1 - GROUND_PX) + 0.5 - float(H) * 0.5
				inst.position = right * (px * u) - up * (py * u)
				inst.rotation = Vector3(0.0, -deg_to_rad(float(a) * ANGLE_STEP + 90.0), 0.0)
				world.add_child(inst)
				insts.append(inst)
	if debug_timing:
		print("vehicle_bake: build ", Time.get_ticks_msec() - t_build, " ms")

	# pass 1: lit colour
	var t_r := Time.get_ticks_msec()
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var col := vp.get_texture().get_image()
	if col == null:
		vp.queue_free()
		return Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var col_tex := ImageTexture.create_from_image(col)

	# pass 2: paint mask (paint = white, everything else black, unshaded)
	var m_white := StandardMaterial3D.new()
	m_white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m_white.albedo_color = Color.WHITE
	var m_black := StandardMaterial3D.new()
	m_black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m_black.albedo_color = Color.BLACK
	for inst in insts:
		var am := inst.mesh as ArrayMesh
		for s in am.get_surface_count():
			inst.set_surface_override_material(s, m_white if am.surface_get_material(s) == paint else m_black)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if debug_timing:
		print("vehicle_bake: colour+mask ", Time.get_ticks_msec() - t_r, " ms")

	# pass 3: combine on the GPU
	var vp2 := SubViewport.new()
	vp2.size = Vector2i(W, H)
	vp2.transparent_bg = true
	vp2.disable_3d = true
	vp2.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp2)
	var rect := ColorRect.new()
	rect.position = Vector2.ZERO
	rect.size = Vector2(W, H)
	var sh := Shader.new()
	sh.code = COMBINE_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("col_tex", col_tex)
	sm.set_shader_parameter("mask_tex", vp.get_texture())
	sm.set_shader_parameter("paint_alpha", float(PAINT_ALPHA) / 255.0)
	rect.material = sm
	vp2.add_child(rect)
	vp2.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var out := vp2.get_texture().get_image()
	vp2.queue_free()
	vp.queue_free()
	if out == null:
		return Image.create(16, 16, false, Image.FORMAT_RGBA8)
	if out.get_format() != Image.FORMAT_RGBA8:
		out.convert(Image.FORMAT_RGBA8)
	return out


## Merges every MeshInstance3D below root into one ArrayMesh with one surface per material.
func _flatten(root: Node3D) -> ArrayMesh:
	var groups := {}
	_gather(root, Transform3D.IDENTITY, groups)
	var out := ArrayMesh.new()
	for mat: Material in groups.keys():
		var g: Array = groups[mat]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g[0]
		arrays[Mesh.ARRAY_NORMAL] = g[1]
		arrays[Mesh.ARRAY_INDEX] = g[2]
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, mat)
	return out


## groups: Material -> [PackedVector3Array verts, PackedVector3Array normals, PackedInt32Array index]
func _gather(n: Node, xf: Transform3D, groups: Dictionary) -> void:
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
		_gather(c, t, groups)
