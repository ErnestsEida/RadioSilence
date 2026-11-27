extends RefCounted
## Procedural low-poly 3D vehicle models (tank, broneviks, motorcycle, jeep, rocket truck).
##
##   var VM := preload("res://scripts/vehicle_models.gd")
##   var n: Node3D = VM.build(vtype, "all", false)
##
## Model frame: origin = ground point under the vehicle's pivot centre, +X = forward (nose),
## +Y = up, +Z = the vehicle's right side. 1 unit = 1 map cell (a soldier is 0.95 tall).
##
## part:
##   "hull"   - everything that does not rotate with the gunner's aim
##   "turret" - only the rotating part; its root origin is the turret pivot on the ground
##              (geometry at its true height), i.e. the pivot sits at TURRET_PIVOT in the hull frame
##   "all"    - hull plus a child Node3D named "Turret" placed at TURRET_PIVOT
## The rotating part is always a child Node3D named "Turret" of the returned root.
##
## Every MeshInstance3D uses material_override taken from materials(wreck); the team paint
## material is materials(false)["paint"] (identify paint surfaces by comparing against it).
## Each MeshInstance3D also carries meta "mk" = material key.
## Named helper nodes (used by vehicle_view.gd): "Body", "Turret", "Gun", "Roof", "Mantlet",
## "Driver", "Gunner" (each with "Head", "Torso", "Arms"), "Steer", "SteerWheel", "Glass".

const TANK := 0
const BRONEVIKS := 1
const MOTO := 2
const JEEP := 3
const ROCKET := 4
const FIGHTER := 5
const HEAVY := 6
const DIVE := 7
const NUM_TYPES := 8
## planes: height of the propeller axis (the "turret" part spins around +X there); 0 = no spinning prop part
const PROP_Y := [0.0, 0.0, 0.0, 0.0, 0.0, 0.55, 0.0, 0.6]
const PAINT := "paint"
const WIND := 1.0

## turret pivot offset from the vehicle origin, Vector2(forward, right), hull frame
const TURRET_PIVOT := [Vector2(0.06, 0.0), Vector2(-0.22, 0.0), Vector2(-0.02, 0.17), Vector2(-0.25, 0.0), Vector2(-0.32, 0.0),
	Vector2(1.27, 0.0), Vector2(1.95, 0.0), Vector2(1.37, 0.0)]
## first-person camera positions (hull frame, turret at rest): [driver, gunner] per vtype
const SEAT := [
	[Vector3(-0.14, 0.78, -0.2), Vector3(-0.18, 0.78, -0.12)],
	[Vector3(0.06, 0.72, -0.12), Vector3(-0.34, 0.72, -0.12)],
	[Vector3(-0.06, 0.66, -0.17), Vector3(-0.12, 0.66, 0.17)],
	[Vector3(-0.08, 0.74, -0.16), Vector3(-0.61, 0.74, 0.0)],
	[Vector3(0.18, 0.8, -0.18), Vector3(-0.8, 0.8, -0.4)],
	[Vector3(0.1, 0.8, 0.0), Vector3(-0.2, 0.8, 0.0)],
	[Vector3(1.2, 0.95, 0.0), Vector3(1.7, 0.7, 0.0)],
	[Vector3(0.25, 0.85, 0.0), Vector3(-0.15, 0.85, 0.0)],
]

static var _M: Dictionary = {}
static var _W: bool = false
static var _cache: Dictionary = {}


# ------------------------------------------------------------ materials ----

static func _mat(c: Color, rough: float = 0.85, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = 0.3
	return m


static func materials(wreck: bool) -> Dictionary:
	if _cache.has(wreck):
		var cached: Dictionary = _cache[wreck]
		return cached
	var d: Dictionary = {}
	if not wreck:
		d["paint"] = _mat(Color(0.66, 0.66, 0.64), 0.8)
		d["olive"] = _mat(Color(0.25, 0.27, 0.19), 0.85)
		d["olive2"] = _mat(Color(0.33, 0.33, 0.25), 0.85)
		d["dark"] = _mat(Color(0.085, 0.085, 0.085), 0.9)
		d["track"] = _mat(Color(0.14, 0.13, 0.12), 0.95)
		d["tyre"] = _mat(Color(0.075, 0.075, 0.075), 0.95)
		d["hub"] = _mat(Color(0.28, 0.29, 0.25), 0.8, 0.2)
		d["gun"] = _mat(Color(0.15, 0.16, 0.17), 0.45, 0.5)
		d["steel"] = _mat(Color(0.45, 0.46, 0.47), 0.4, 0.6)
		d["rust"] = _mat(Color(0.36, 0.2, 0.11), 0.9)
		d["glass"] = _mat(Color(0.2, 0.27, 0.32), 0.15, 0.3)
		d["wood"] = _mat(Color(0.42, 0.3, 0.17), 0.9)
		d["canvas"] = _mat(Color(0.4, 0.37, 0.27), 0.95)
		d["leather"] = _mat(Color(0.27, 0.16, 0.08), 0.8)
		d["glove"] = _mat(Color(0.17, 0.14, 0.11), 0.85)
		d["uniform"] = _mat(Color(0.3, 0.31, 0.22), 0.95)
		d["skin"] = _mat(Color(0.78, 0.58, 0.44), 0.8)
		d["helmet"] = _mat(Color(0.22, 0.25, 0.17), 0.7)
		d["brass"] = _mat(Color(0.75, 0.58, 0.25), 0.4, 0.7)
		d["warhead"] = _mat(Color(0.36, 0.37, 0.34), 0.6, 0.3)
		d["white"] = _mat(Color(0.85, 0.85, 0.8), 0.8)
		var lt := _mat(Color(1.0, 0.92, 0.7), 0.3)
		lt.emission_enabled = true
		lt.emission = Color(1.0, 0.9, 0.6)
		lt.emission_energy_multiplier = 0.6
		d["light"] = lt
		var rd := _mat(Color(0.75, 0.08, 0.05), 0.4)
		rd.emission_enabled = true
		rd.emission = Color(0.6, 0.05, 0.02)
		rd.emission_energy_multiplier = 0.5
		d["red"] = rd
	else:
		var char_c := Color(0.12, 0.105, 0.09)
		d["paint"] = _mat(char_c, 0.95)
		d["olive"] = _mat(Color(0.09, 0.085, 0.075), 0.95)
		d["olive2"] = _mat(Color(0.16, 0.12, 0.09), 0.95)
		d["dark"] = _mat(Color(0.045, 0.042, 0.04), 0.95)
		d["track"] = _mat(Color(0.1, 0.075, 0.06), 0.95)
		d["tyre"] = _mat(Color(0.04, 0.04, 0.04), 0.95)
		d["hub"] = _mat(Color(0.22, 0.12, 0.06), 0.95)
		d["gun"] = _mat(Color(0.07, 0.065, 0.06), 0.8)
		d["steel"] = _mat(Color(0.14, 0.12, 0.1), 0.9)
		d["rust"] = _mat(Color(0.26, 0.12, 0.05), 0.95)
		d["glass"] = _mat(Color(0.02, 0.02, 0.02), 0.95)
		d["wood"] = _mat(Color(0.06, 0.045, 0.035), 0.95)
		d["canvas"] = _mat(Color(0.07, 0.06, 0.05), 0.95)
		d["leather"] = _mat(Color(0.06, 0.04, 0.03), 0.95)
		d["glove"] = _mat(Color(0.06, 0.05, 0.04), 0.95)
		d["uniform"] = _mat(Color(0.07, 0.06, 0.05), 0.95)
		d["skin"] = _mat(Color(0.07, 0.06, 0.05), 0.95)
		d["helmet"] = _mat(Color(0.07, 0.06, 0.05), 0.95)
		d["brass"] = _mat(Color(0.2, 0.13, 0.06), 0.9)
		d["warhead"] = _mat(Color(0.15, 0.1, 0.07), 0.95)
		d["white"] = _mat(Color(0.2, 0.18, 0.16), 0.95)
		d["light"] = _mat(Color(0.03, 0.03, 0.03), 0.9)
		d["red"] = _mat(Color(0.05, 0.03, 0.03), 0.9)
	_cache[wreck] = d
	return d


static func paint_material() -> StandardMaterial3D:
	var m: StandardMaterial3D = materials(false)[PAINT]
	return m


# --------------------------------------------------------------- public ----

static func build(vtype: int, part: String, wreck: bool) -> Node3D:
	_W = wreck
	_M = materials(wreck)
	var root := Node3D.new()
	root.name = "Vehicle%d_%s%s" % [vtype, part, "_wreck" if wreck else ""]
	var pv: Vector2 = TURRET_PIVOT[clampi(vtype, 0, NUM_TYPES - 1)]
	if part == "hull" or part == "all":
		var body := _node(root, "Body")
		match vtype:
			TANK:
				_tank_hull(body)
			BRONEVIKS:
				_brone_hull(body)
			MOTO:
				_moto_hull(body)
			JEEP:
				_jeep_hull(body)
			FIGHTER:
				_fighter_hull(body)
			HEAVY:
				_heavy_hull(body)
			DIVE:
				_dive_hull(body)
			_:
				_truck_hull(body)
		if wreck:
			body.position.y = -0.025
			body.rotation_degrees = Vector3(3.5, 0.0, -2.0)
	if part == "turret" or part == "all":
		var t := _node(root, "Turret")
		if part == "all":
			t.position = Vector3(pv.x, 0.0, pv.y)
		# geometry is authored relative to the pivot
		match vtype:
			TANK:
				_tank_turret(t)
			BRONEVIKS:
				_brone_turret(t)
			MOTO:
				_moto_turret(t)
			JEEP:
				_jeep_turret(t)
			FIGHTER, DIVE:
				_prop(t, 0.78 if vtype == FIGHTER else 0.86)
			HEAVY:
				_heavy_nose(t)
			_:
				_truck_turret(t)
		if wreck:
			var inner := t
			inner.position.y += -0.02
			inner.rotation_degrees = Vector3(4.0, 7.0, -2.5)
	return root


# ------------------------------------------------------------ mesh helpers ----

static func _node(p: Node3D, nm: String = "", pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	if nm != "":
		n.name = nm
	n.position = pos
	n.rotation_degrees = rot_deg
	p.add_child(n)
	return n


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, hint: Vector3) -> void:
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


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, hint: Vector3) -> void:
	_tri(st, a, b, c, hint)
	_tri(st, a, c, d, hint)


static func _p3(p: Vector2, z: float) -> Vector3:
	return Vector3(p.x, p.y, z)


## Extrudes a side profile (Vector2(x, y)) across Z (centred on z = 0) with chamfered edges.
static func _extrude(poly_in: PackedVector2Array, width: float, bevel: float) -> ArrayMesh:
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
	var zo := hw - bv
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
			var dd := maxf(bis.dot(n0), 0.35)
			inset.append(p1 - bis * (bv / dd))
	else:
		inset = poly
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var e := (b - a).normalized()
		var nn := Vector3(e.y, -e.x, 0.0)
		_quad(st, _p3(a, -zo), _p3(b, -zo), _p3(b, zo), _p3(a, zo), nn)
		if bv > 0.0:
			var ia: Vector2 = inset[i]
			var ib: Vector2 = inset[(i + 1) % n]
			_quad(st, _p3(a, zo), _p3(b, zo), _p3(ib, hw), _p3(ia, hw), (nn + Vector3(0.0, 0.0, 1.0)).normalized())
			_quad(st, _p3(a, -zo), _p3(b, -zo), _p3(ib, -hw), _p3(ia, -hw), (nn + Vector3(0.0, 0.0, -1.0)).normalized())
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
		_tri(st, _p3(a, hw), _p3(b, hw), _p3(c, hw), Vector3(0.0, 0.0, 1.0))
		_tri(st, _p3(a, -hw), _p3(b, -hw), _p3(c, -hw), Vector3(0.0, 0.0, -1.0))
		t += 3
	return st.commit()


static func _pv(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var i := 0
	while i + 1 < flat.size():
		var x: float = flat[i]
		var y: float = flat[i + 1]
		out.append(Vector2(x, y))
		i += 2
	return out


static func _mi(p: Node3D, mesh: Mesh, key: String, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	var mat: Material = _M[key]
	m.material_override = mat
	m.set_meta("mk", key)
	m.position = pos
	m.rotation_degrees = rot_deg
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(m)
	return m


## chamfered box; c = centre, s = (length x, height y, width z)
static func _box(p: Node3D, c: Vector3, s: Vector3, key: String, bev: float = 0.0, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh: Mesh
	if bev <= 0.0:
		var bm := BoxMesh.new()
		bm.size = s
		mesh = bm
	else:
		var hx := s.x * 0.5
		var hy := s.y * 0.5
		var b := minf(bev, minf(hx, hy) * 0.9)
		var poly := PackedVector2Array([
			Vector2(-hx + b, -hy), Vector2(hx - b, -hy), Vector2(hx, -hy + b), Vector2(hx, hy - b),
			Vector2(hx - b, hy), Vector2(-hx + b, hy), Vector2(-hx, hy - b), Vector2(-hx, -hy + b)])
		mesh = _extrude(poly, s.z, minf(b, s.z * 0.45))
	return _mi(p, mesh, key, c, rot_deg)


## side profile [x0, y0, x1, y1, ...] extruded across Z, centred at z
static func _prof(p: Node3D, flat: Array, w: float, z: float, key: String, bev: float = 0.01) -> MeshInstance3D:
	return _mi(p, _extrude(_pv(flat), w, bev), key, Vector3(0.0, 0.0, z))


## top-view profile [x0, z0, x1, z1, ...] extruded vertically from y0 to y0 + h
static func _top(p: Node3D, flat: Array, h: float, y0: float, key: String, bev: float = 0.01) -> MeshInstance3D:
	return _mi(p, _extrude(_pv(flat), h, bev), key, Vector3(0.0, y0 + h * 0.5, 0.0), Vector3(90.0, 0.0, 0.0))


static func _basis_y(axis: Vector3) -> Basis:
	var y := axis.normalized()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.9 else Vector3(1.0, 0.0, 0.0)
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## cylinder from a (radius r0) to b (radius r1)
static func _cyl(p: Node3D, a: Vector3, b: Vector3, r0: float, r1: float, key: String, seg: int = 10) -> MeshInstance3D:
	var d := b - a
	var ln := d.length()
	var c := CylinderMesh.new()
	c.top_radius = r1
	c.bottom_radius = r0
	c.height = maxf(ln, 0.0005)
	c.radial_segments = seg
	c.rings = 1
	var m := _mi(p, c, key, Vector3.ZERO)
	m.transform = Transform3D(_basis_y(d), (a + b) * 0.5)
	return m


## box whose local Y runs from a to b; s = (thickness along x, -, width along z)
static func _obox(p: Node3D, a: Vector3, b: Vector3, thick: float, width: float, key: String, bev: float = 0.0) -> MeshInstance3D:
	var d := b - a
	var y := d.normalized()
	var zr := Vector3(0.0, 0.0, 1.0)
	if absf(y.dot(zr)) > 0.9:
		zr = Vector3(1.0, 0.0, 0.0)
	var x := y.cross(zr).normalized()
	var z := x.cross(y).normalized()
	var m := _box(p, Vector3.ZERO, Vector3(thick, d.length(), width), key, bev)
	m.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	return m


static func _sphere(p: Node3D, c: Vector3, r: float, key: String, seg: int = 10, hemi: bool = false) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r if hemi else r * 2.0
	s.is_hemisphere = hemi
	s.radial_segments = seg
	s.rings = maxi(seg / 2, 3)
	return _mi(p, s, key, c)


static func _torus(p: Node3D, c: Vector3, axis: Vector3, r: float, tube: float, key: String) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = r - tube
	t.outer_radius = r + tube
	t.rings = 20
	t.ring_segments = 6
	var m := _mi(p, t, key, Vector3.ZERO)
	m.transform = Transform3D(_basis_y(axis), c)
	return m


## arc-shaped mudguard profile around a wheel centre (x, y), extruded across z
static func _fender(p: Node3D, cx: float, cy: float, r_in: float, r_out: float, a0: float, a1: float, w: float, z: float, key: String) -> MeshInstance3D:
	var pts: Array = []
	var seg := 8
	for i in seg + 1:
		var a := deg_to_rad(lerpf(a0, a1, float(i) / float(seg)))
		pts.append(cx + cos(a) * r_out)
		pts.append(cy + sin(a) * r_out)
	for i in seg + 1:
		var a := deg_to_rad(lerpf(a1, a0, float(i) / float(seg)))
		pts.append(cx + cos(a) * r_in)
		pts.append(cy + sin(a) * r_in)
	return _prof(p, pts, w, z, key, 0.006)


## many tiny cubes merged into one mesh (rivets / bolts)
static func _rivets(p: Node3D, pts: PackedVector3Array, r: float, key: String) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in pts:
		var v: Array[Vector3] = []
		for i in 8:
			v.append(c + Vector3(r if (i & 1) != 0 else -r, r if (i & 2) != 0 else -r, r if (i & 4) != 0 else -r))
		_quad(st, v[0], v[1], v[3], v[2], Vector3(0, 0, -1))
		_quad(st, v[4], v[5], v[7], v[6], Vector3(0, 0, 1))
		_quad(st, v[0], v[1], v[5], v[4], Vector3(0, -1, 0))
		_quad(st, v[2], v[3], v[7], v[6], Vector3(0, 1, 0))
		_quad(st, v[0], v[2], v[6], v[4], Vector3(-1, 0, 0))
		_quad(st, v[1], v[3], v[7], v[5], Vector3(1, 0, 0))
	var m := _mi(p, st.commit(), key, Vector3.ZERO)
	m.name = "Rivets"
	return m


static func _rivet_line(a: Vector3, b: Vector3, n: int, out: PackedVector3Array) -> void:
	for i in n:
		out.append(a.lerp(b, (float(i) + 0.5) / float(n)))


## road wheel with tyre, rims and hub cap; axis along Z
static func _wheel(p: Node3D, c: Vector3, r: float, w: float, seg: int = 14, hub_key: String = "hub") -> Node3D:
	var n := _node(p, "Wheel", c)
	var rr := r * (0.9 if _W else 1.0)
	if _W:
		n.position.y -= r - rr
	_cyl(n, Vector3(0, 0, -w * 0.5), Vector3(0, 0, w * 0.5), rr, rr, "tyre", seg)
	for s: float in [-1.0, 1.0]:
		_cyl(n, Vector3(0, 0, s * w * 0.5), Vector3(0, 0, s * (w * 0.5 + 0.006)), r * 0.6, r * 0.6, hub_key, seg)
		_cyl(n, Vector3(0, 0, s * (w * 0.5 + 0.006)), Vector3(0, 0, s * (w * 0.5 + 0.02)), r * 0.24, r * 0.18, "dark", 8)
	return n


# ----------------------------------------------------------------- crew ----

## Low-poly soldier. hip/shoulder are centre points; z spread is along the model Z axis.
## Children: Head, Torso, Arms (for hiding in first person).
static func _crew(p: Node3D, nm: String, hip: Vector3, shoulder: Vector3, knee_fwd: float, foot: Vector3, hand_l: Vector3, hand_r: Vector3) -> Node3D:
	var n := _node(p, nm)
	var torso := _node(n, "Torso")
	var arms := _node(n, "Arms")
	var head := _node(n, "Head")
	var up := (shoulder - hip).normalized()
	# legs: thigh forward from hip, shin down to the foot
	for s: float in [-1.0, 1.0]:
		var h := hip + Vector3(0, 0, s * 0.05)
		var k := h + Vector3(knee_fwd, 0.02, s * 0.01)
		var f := Vector3(foot.x, foot.y, foot.z + s * 0.055)
		_cyl(torso, h, k, 0.038, 0.032, "uniform", 6)
		_cyl(torso, k, f, 0.03, 0.026, "uniform", 6)
		_box(torso, f + Vector3(0.02, 0.012, 0), Vector3(0.07, 0.03, 0.04), "leather", 0.008)
	# torso (slightly tapered greatcoat block) + belt
	_obox(torso, hip - up * 0.02, shoulder, 0.1, 0.15, "uniform", 0.03)
	_obox(torso, hip + up * 0.04, hip + up * 0.065, 0.105, 0.155, "leather")
	# arms
	for s: float in [-1.0, 1.0]:
		var sh := shoulder + Vector3(0, -0.015, s * 0.085)
		var hand: Vector3 = hand_r if s > 0.0 else hand_l
		var mid := (sh + hand) * 0.5 + Vector3(-0.02, -0.045, s * 0.03)
		_cyl(arms, sh, mid, 0.03, 0.026, "uniform", 6)
		_cyl(arms, mid, hand, 0.026, 0.022, "uniform", 6)
		_box(arms, hand, Vector3(0.05, 0.035, 0.035), "glove", 0.01)
	# head + helmet
	var hc := shoulder + up * 0.075 + Vector3(0.0, 0.0, 0.0)
	_cyl(head, shoulder - up * 0.01, hc, 0.025, 0.025, "skin", 6)
	_sphere(head, hc, 0.046, "skin", 8)
	_sphere(head, hc + Vector3(-0.004, 0.008, 0), 0.056, "helmet", 10, true)
	_cyl(head, hc + Vector3(-0.004, 0.006, 0), hc + Vector3(-0.004, 0.012, 0), 0.064, 0.058, "helmet", 10)
	return n


# ----------------------------------------------------------------- TANK ----

static func _tank_hull(b: Node3D) -> void:
	var track := [-0.6, 0.0, 0.6, 0.0, 0.7, 0.04, 0.765, 0.13, 0.75, 0.23, 0.67, 0.3, -0.66, 0.3, -0.745, 0.245, -0.775, 0.15, -0.71, 0.045]
	var riv := PackedVector3Array()
	for s: float in [-1.0, 1.0]:
		_prof(b, track, 0.22, s * 0.39, "track", 0.02)
		# track links: grousers on the outer face along the bottom run
		for i in 16:
			var x := -0.62 + 0.08 * float(i)
			_box(b, Vector3(x, 0.012, s * 0.5), Vector3(0.025, 0.024, 0.012), "dark")
		for i in 5:
			var x := -0.5 + 0.25 * float(i)
			_cyl(b, Vector3(x, 0.125, s * 0.49), Vector3(x, 0.125, s * 0.512), 0.108, 0.108, "olive", 14)
			_cyl(b, Vector3(x, 0.125, s * 0.512), Vector3(x, 0.125, s * 0.518), 0.07, 0.07, "olive2", 12)
			_cyl(b, Vector3(x, 0.125, s * 0.518), Vector3(x, 0.125, s * 0.53), 0.035, 0.028, "dark", 8)
		# drive sprocket (rear) and idler (front)
		_cyl(b, Vector3(-0.68, 0.165, s * 0.48), Vector3(-0.68, 0.165, s * 0.515), 0.085, 0.085, "dark", 12)
		_cyl(b, Vector3(-0.68, 0.165, s * 0.515), Vector3(-0.68, 0.165, s * 0.53), 0.04, 0.03, "olive", 8)
		_cyl(b, Vector3(0.67, 0.16, s * 0.48), Vector3(0.67, 0.16, s * 0.515), 0.075, 0.075, "olive", 12)
		# fenders over the tracks
		if not (_W and s > 0.0):
			_box(b, Vector3(0.0, 0.33, s * 0.4), Vector3(1.5, 0.025, 0.21), "olive", 0.008)
			_box(b, Vector3(0.79, 0.315, s * 0.4), Vector3(0.1, 0.02, 0.21), "olive", 0.006, Vector3(0, 0, -25))
		# toolbox + external fuel tank on the fenders
		_box(b, Vector3(-0.08, 0.375, s * 0.44), Vector3(0.3, 0.07, 0.08), "olive", 0.012)
		_cyl(b, Vector3(-0.66, 0.4, s * 0.43), Vector3(-0.36, 0.4, s * 0.43), 0.048, 0.048, "olive", 10)
		_cyl(b, Vector3(-0.505, 0.4, s * 0.43), Vector3(-0.495, 0.4, s * 0.43), 0.052, 0.052, "dark", 10)
		# headlights
		_cyl(b, Vector3(0.66, 0.4, s * 0.36), Vector3(0.72, 0.4, s * 0.36), 0.032, 0.032, "dark", 10)
		_cyl(b, Vector3(0.72, 0.4, s * 0.36), Vector3(0.725, 0.4, s * 0.36), 0.025, 0.025, "light", 10)
		# exhausts out of the rear plate
		_cyl(b, Vector3(-0.7, 0.42, s * 0.2), Vector3(-0.8, 0.42, s * 0.2), 0.034, 0.034, "rust", 8)
		_cyl(b, Vector3(-0.795, 0.42, s * 0.2), Vector3(-0.805, 0.42, s * 0.2), 0.025, 0.025, "dark", 8)
		# rivets along the hull side top edge
		_rivet_line(Vector3(-0.62, 0.53, s * 0.455), Vector3(0.45, 0.53, s * 0.455), 12, riv)
		# tow hooks
		_box(b, Vector3(0.82, 0.36, s * 0.24), Vector3(0.04, 0.04, 0.03), "dark")
		# tail light
		_box(b, Vector3(-0.755, 0.5, s * 0.36), Vector3(0.01, 0.025, 0.04), "red")
	# lower hull between the tracks
	_box(b, Vector3(0.0, 0.2, 0.0), Vector3(1.36, 0.24, 0.56), "dark")
	# upper hull with sloped glacis and rear plate
	_prof(b, [-0.72, 0.31, 0.6, 0.31, 0.8, 0.355, 0.83, 0.4, 0.52, 0.56, -0.64, 0.56, -0.745, 0.49], 0.92, 0.0, PAINT, 0.025)
	# rear deck engine grille
	_box(b, Vector3(-0.44, 0.563, 0.0), Vector3(0.3, 0.012, 0.52), "dark")
	for i in 6:
		_box(b, Vector3(-0.565 + 0.05 * float(i), 0.567, 0.0), Vector3(0.018, 0.012, 0.5), "olive")
	# glacis: driver's hatch, hull MG ball, spare track links
	var gl := Vector3(0, 0, -27.0)
	var nrm := Vector3(0.45, 0.89, 0.0)
	_box(b, Vector3(0.66, 0.475, -0.2) + nrm * 0.012, Vector3(0.16, 0.025, 0.17), "olive", 0.008, gl)
	_box(b, Vector3(0.7, 0.455, -0.2) + nrm * 0.026, Vector3(0.012, 0.012, 0.11), "dark", 0.0, gl)
	_sphere(b, Vector3(0.69, 0.465, 0.22), 0.042, "olive", 10)
	_cyl(b, Vector3(0.71, 0.465, 0.22), Vector3(0.86, 0.465, 0.22), 0.012, 0.011, "gun", 6)
	for i in 3:
		_box(b, Vector3(0.785 - 0.035 * float(i), 0.41 + 0.018 * float(i), 0.02 + 0.0 * float(i)) + nrm * 0.012, Vector3(0.03, 0.02, 0.22), "track", 0.004, gl)
	# rivets on the glacis edge
	_rivet_line(Vector3(0.6, 0.52, -0.42), Vector3(0.6, 0.52, 0.42), 10, riv)
	_rivets(b, riv, 0.008, "olive2")
	# tow cable along the left side
	_cyl(b, Vector3(-0.5, 0.49, -0.462), Vector3(0.35, 0.49, -0.462), 0.01, 0.01, "steel", 5)


static func _tank_turret(t: Node3D) -> void:
	var roof := _node(t, "Roof")
	_cyl(_node(t, "Ring"), Vector3(0, 0.555, 0), Vector3(0, 0.6, 0), 0.31, 0.3, "dark", 16)
	# hexagonal cast turret, the bevel gives the sloped top edge
	_top(t, [0.33, -0.18, 0.33, 0.18, 0.1, 0.31, -0.32, 0.29, -0.44, 0.17, -0.44, -0.17, -0.32, -0.29, 0.1, -0.31], 0.27, 0.585, PAINT, 0.065)
	# rear bustle stowage box
	_box(roof, Vector3(-0.48, 0.7, 0.0), Vector3(0.09, 0.11, 0.38), "olive", 0.015)
	# grab rails on the sides
	for s: float in [-1.0, 1.0]:
		_cyl(roof, Vector3(-0.25, 0.77, s * 0.305), Vector3(0.05, 0.77, s * 0.315), 0.008, 0.008, "olive2", 5)
		_box(roof, Vector3(-0.05, 0.69, s * 0.305), Vector3(0.11, 0.022, 0.012), "dark", 0.0, Vector3(0, s * -14.0, 0))
	# mantlet + gun
	var mant := _node(t, "Mantlet")
	_cyl(mant, Vector3(0.355, 0.705, -0.16), Vector3(0.355, 0.705, 0.16), 0.085, 0.085, "olive", 12)
	_box(mant, Vector3(0.41, 0.705, 0.0), Vector3(0.08, 0.13, 0.2), "olive", 0.025)
	var gun := _node(t, "Gun", Vector3(0.42, 0.705, 0.0))
	_cyl(gun, Vector3(0.0, 0, 0), Vector3(0.18, 0, 0), 0.046, 0.04, "gun", 12)
	_cyl(gun, Vector3(0.18, 0, 0), Vector3(0.55, 0, 0), 0.03, 0.028, "gun", 10)
	_cyl(gun, Vector3(0.54, 0, 0), Vector3(0.62, 0, 0), 0.042, 0.042, "gun", 10)
	_cyl(gun, Vector3(0.6205, 0, 0), Vector3(0.6215, 0, 0), 0.02, 0.02, "dark", 8)
	_cyl(gun, Vector3(-0.02, -0.02, 0.1), Vector3(0.09, -0.02, 0.1), 0.012, 0.011, "gun", 6)
	if _W:
		gun.rotation_degrees = Vector3(0, 0, -8.0)
	# commander's cupola with vision blocks and hatch
	_cyl(roof, Vector3(-0.16, 0.84, -0.13), Vector3(-0.16, 0.925, -0.13), 0.1, 0.095, PAINT, 12)
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.3
		_box(roof, Vector3(-0.16 + cos(a) * 0.096, 0.89, -0.13 + sin(a) * 0.096), Vector3(0.02, 0.022, 0.035), "dark", 0.0, Vector3(0, -rad_to_deg(a), 0))
	if _W:
		_cyl(roof, Vector3(-0.27, 0.93, -0.13), Vector3(-0.27, 1.0, -0.13), 0.085, 0.085, "olive", 12).rotation_degrees = Vector3(0, 0, 70)
	else:
		_cyl(roof, Vector3(-0.16, 0.925, -0.13), Vector3(-0.16, 0.945, -0.13), 0.09, 0.075, "olive", 12)
		_box(roof, Vector3(-0.16, 0.95, -0.13), Vector3(0.06, 0.012, 0.012), "dark")
	# loader's hatch + periscopes
	_box(roof, Vector3(-0.12, 0.857, 0.13), Vector3(0.15, 0.02, 0.13), "olive", 0.006)
	_box(roof, Vector3(0.17, 0.865, -0.14), Vector3(0.05, 0.035, 0.04), "dark", 0.006)
	_box(roof, Vector3(0.17, 0.865, 0.12), Vector3(0.05, 0.035, 0.04), "dark", 0.006)
	# pintle AA machine gun
	_cyl(roof, Vector3(-0.05, 0.85, 0.16), Vector3(-0.05, 0.95, 0.16), 0.012, 0.012, "gun", 6)
	_box(roof, Vector3(-0.02, 0.965, 0.16), Vector3(0.15, 0.035, 0.03), "gun", 0.006)
	_cyl(roof, Vector3(0.05, 0.968, 0.16), Vector3(0.2, 0.968, 0.16), 0.008, 0.008, "gun", 6)
	_box(roof, Vector3(-0.02, 0.94, 0.19), Vector3(0.06, 0.04, 0.035), "olive2", 0.005)
	# antenna
	_cyl(roof, Vector3(-0.36, 0.84, 0.2), Vector3(-0.36, 0.88, 0.2), 0.018, 0.015, "dark", 6)
	if not _W:
		_cyl(roof, Vector3(-0.36, 0.88, 0.2), Vector3(-0.4, 1.2, 0.2), 0.008, 0.006, "dark", 4)
	else:
		_cyl(roof, Vector3(-0.36, 0.88, 0.2), Vector3(-0.38, 0.96, 0.2), 0.008, 0.006, "dark", 4)


# ------------------------------------------------------------ BRONEVIKS ----

static func _brone_hull(b: Node3D) -> void:
	var riv := PackedVector3Array()
	var rail := _node(b, "Rail")
	# chassis
	_box(b, Vector3(0.0, 0.2, 0.0), Vector3(1.3, 0.08, 0.46), "dark")
	# fighting compartment and armoured engine hood
	_prof(b, [-0.7, 0.24, 0.3, 0.24, 0.34, 0.5, 0.16, 0.66, -0.6, 0.66, -0.71, 0.56], 0.66, 0.0, PAINT, 0.018)
	_prof(b, [0.28, 0.25, 0.72, 0.25, 0.745, 0.43, 0.68, 0.5, 0.34, 0.52], 0.54, 0.0, PAINT, 0.025)
	# radiator louvres
	_box(b, Vector3(0.742, 0.34, 0.0), Vector3(0.02, 0.16, 0.4), "dark")
	for i in 5:
		_box(b, Vector3(0.75, 0.28 + 0.03 * float(i), 0.0), Vector3(0.02, 0.012, 0.4), "olive", 0.0, Vector3(0, 0, -30))
	# hood hatches (louvred top)
	for s: float in [-1.0, 1.0]:
		_box(b, Vector3(0.52, 0.515, s * 0.12), Vector3(0.3, 0.012, 0.16), "olive", 0.004, Vector3(0, 0, -4))
	# driver vision hatch and hull MG on the front plate
	var pr := Vector3(0, 0, -41.6)
	var nrm := Vector3(0.66, 0.75, 0.0)
	_box(b, Vector3(0.25, 0.58, -0.14) + nrm * 0.01, Vector3(0.14, 0.02, 0.18), "olive", 0.006, pr)
	_box(b, Vector3(0.25, 0.58, -0.14) + nrm * 0.022, Vector3(0.012, 0.01, 0.12), "dark", 0.0, pr)
	_sphere(b, Vector3(0.27, 0.56, 0.16), 0.038, "olive", 8)
	_cyl(b, Vector3(0.29, 0.56, 0.16), Vector3(0.42, 0.555, 0.16), 0.011, 0.01, "gun", 6)
	var wheels := [0.42, -0.22, -0.52]
	for s: float in [-1.0, 1.0]:
		for x: float in wheels:
			_wheel(b, Vector3(x, 0.15, s * 0.37), 0.15, 0.1, 14)
		# front mudguard arc + rear fender plate over the bogie
		if not (_W and s < 0.0):
			_fender(b, 0.42, 0.15, 0.175, 0.19, 0.0, 180.0, 0.13, s * 0.37, "olive")
		_box(b, Vector3(-0.37, 0.33, s * 0.37), Vector3(0.68, 0.022, 0.13), "olive", 0.006)
		_box(b, Vector3(-0.725, 0.3, s * 0.37), Vector3(0.06, 0.02, 0.13), "olive", 0.004, Vector3(0, 0, 50))
		# spare wheel carried on the hull side between the axles (free-rotating, BA-10 style)
		_wheel(b, Vector3(0.12, 0.31, s * 0.375), 0.135, 0.08, 12)
		# headlights in armoured covers
		_cyl(b, Vector3(0.63, 0.45, s * 0.24), Vector3(0.7, 0.45, s * 0.24), 0.034, 0.03, "olive", 10)
		_cyl(b, Vector3(0.7, 0.45, s * 0.24), Vector3(0.705, 0.45, s * 0.24), 0.024, 0.024, "light", 10)
		# side vision slits + access door
		_box(b, Vector3(0.12, 0.6, s * 0.332), Vector3(0.1, 0.012, 0.01), "dark")
		_box(b, Vector3(-0.35, 0.6, s * 0.332), Vector3(0.1, 0.012, 0.01), "dark")
		_box(b, Vector3(-0.08, 0.44, s * 0.333), Vector3(0.2, 0.24, 0.008), "olive2", 0.004)
		_box(b, Vector3(0.01, 0.4, s * 0.34), Vector3(0.012, 0.03, 0.01), "steel")
		# riveted panel seams
		_rivet_line(Vector3(-0.68, 0.64, s * 0.33), Vector3(0.17, 0.64, s * 0.33), 14, riv)
		_rivet_line(Vector3(-0.68, 0.27, s * 0.33), Vector3(0.28, 0.27, s * 0.33), 14, riv)
		_rivet_line(Vector3(0.36, 0.495, s * 0.27), Vector3(0.68, 0.48, s * 0.27), 6, riv)
		_rivet_line(Vector3(0.36, 0.28, s * 0.27), Vector3(0.7, 0.28, s * 0.27), 6, riv)
		# frame antenna (handrail) around the roof
		if not _W:
			for x: float in [-0.56, -0.22, 0.08]:
				_cyl(rail, Vector3(x, 0.66, s * 0.3), Vector3(x, 0.72, s * 0.3), 0.007, 0.007, "dark", 4)
			_cyl(rail, Vector3(-0.56, 0.72, s * 0.3), Vector3(0.08, 0.72, s * 0.3), 0.007, 0.007, "dark", 4)
		# exhaust muffler under the side
		_cyl(b, Vector3(-0.1, 0.19, s * 0.28), Vector3(-0.6, 0.19, s * 0.28), 0.025, 0.025, "rust", 6)
		_box(b, Vector3(-0.712, 0.5, s * 0.26), Vector3(0.01, 0.025, 0.04), "red")
	if not _W:
		_cyl(rail, Vector3(-0.56, 0.72, -0.3), Vector3(-0.56, 0.72, 0.3), 0.007, 0.007, "dark", 4)
	_rivet_line(Vector3(0.17, 0.655, -0.32), Vector3(0.17, 0.655, 0.32), 10, riv)
	_rivet_line(Vector3(-0.6, 0.655, -0.32), Vector3(-0.6, 0.655, 0.32), 10, riv)
	_rivets(b, riv, 0.007, "olive2")
	# rear stowage box + tow hook
	_box(b, Vector3(-0.73, 0.4, 0.0), Vector3(0.06, 0.1, 0.3), "olive", 0.01)
	_box(b, Vector3(0.76, 0.22, 0.0), Vector3(0.04, 0.04, 0.5), "dark")


static func _brone_turret(t: Node3D) -> void:
	var roof := _node(t, "Roof")
	_cyl(_node(t, "Ring"), Vector3(0, 0.64, 0), Vector3(0, 0.67, 0), 0.215, 0.215, "dark", 14)
	_cyl(t, Vector3(0, 0.665, 0), Vector3(0, 0.83, 0), 0.225, 0.2, PAINT, 12)
	_cyl(roof, Vector3(0, 0.83, 0), Vector3(0, 0.875, 0), 0.2, 0.12, PAINT, 12)
	var riv := PackedVector3Array()
	for i in 16:
		var a := TAU * float(i) / 16.0
		riv.append(Vector3(cos(a) * 0.222, 0.69, sin(a) * 0.222))
		riv.append(Vector3(cos(a) * 0.204, 0.815, sin(a) * 0.204))
	_rivets(roof, riv, 0.007, "olive2")
	# vision slits
	for s: float in [-1.0, 1.0]:
		_box(roof, Vector3(0.02, 0.77, s * 0.21), Vector3(0.08, 0.012, 0.012), "dark", 0.0, Vector3(0, s * -8.0, 0))
	# hatch + periscope + whip antenna
	if _W:
		_cyl(roof, Vector3(-0.12, 0.88, 0.0), Vector3(-0.12, 0.9, 0.0), 0.085, 0.085, "olive", 12).rotation_degrees = Vector3(0, 0, 75)
	else:
		_cyl(roof, Vector3(-0.03, 0.873, 0.0), Vector3(-0.03, 0.895, 0.0), 0.09, 0.08, "olive", 12)
	_box(roof, Vector3(0.1, 0.86, -0.09), Vector3(0.05, 0.05, 0.035), "dark", 0.006)
	if not _W:
		_cyl(roof, Vector3(-0.18, 0.8, 0.1), Vector3(-0.2, 1.12, 0.1), 0.007, 0.005, "dark", 4)
	# mantlet + 45 mm gun + coax MG
	var mant := _node(t, "Mantlet")
	_box(mant, Vector3(0.215, 0.725, 0.0), Vector3(0.08, 0.13, 0.17), "olive", 0.025)
	var gun := _node(t, "Gun", Vector3(0.24, 0.705, 0.0))
	_cyl(gun, Vector3(0.0, 0, 0), Vector3(0.08, 0, 0), 0.034, 0.03, "gun", 10)
	_cyl(gun, Vector3(0.08, 0, 0), Vector3(0.42, 0, 0), 0.022, 0.02, "gun", 10)
	_cyl(gun, Vector3(0.4, 0, 0), Vector3(0.44, 0, 0), 0.028, 0.028, "gun", 10)
	_cyl(gun, Vector3(-0.01, -0.015, 0.06), Vector3(0.07, -0.015, 0.06), 0.01, 0.009, "gun", 6)
	if _W:
		gun.rotation_degrees = Vector3(0, 0, -10.0)


# ----------------------------------------------------------- MOTORCYCLE ----

const BZ := -0.17
const SZ := 0.17


static func _moto_hull(b: Node3D) -> void:
	var z := BZ
	# wheels + mudguards
	_wheel(b, Vector3(-0.3, 0.13, z), 0.13, 0.05, 14)
	_fender(b, -0.3, 0.13, 0.145, 0.16, 20.0, 175.0, 0.065, z, PAINT)
	# steering assembly: fork, front wheel, guard, headlight, handlebars
	var steer := _node(b, "Steer", Vector3(0.25, 0.46, z))
	steer.rotation_degrees = Vector3.ZERO
	var fw := Vector3(0.32, 0.13, z) - steer.position
	_wheel(steer, fw, 0.13, 0.05, 14)
	_fender(steer, fw.x, fw.y, 0.145, 0.16, 5.0, 150.0, 0.065, 0.0, PAINT)
	for s: float in [-1.0, 1.0]:
		_cyl(steer, fw + Vector3(0, 0, s * 0.035), Vector3(-0.005, -0.02, s * 0.035), 0.012, 0.014, "steel", 6)
	_cyl(steer, Vector3(0.0, -0.03, -0.045), Vector3(0.0, -0.03, 0.045), 0.02, 0.02, "dark", 6)
	_cyl(steer, Vector3(0.0, -0.015, 0), Vector3(0.065, -0.015, 0), 0.036, 0.034, "dark", 10)
	_cyl(steer, Vector3(0.065, -0.015, 0), Vector3(0.07, -0.015, 0), 0.028, 0.028, "light", 10)
	# handlebars high and wide
	for s: float in [-1.0, 1.0]:
		_cyl(steer, Vector3(-0.005, 0.0, s * 0.03), Vector3(-0.03, 0.085, s * 0.07), 0.009, 0.009, "steel", 5)
		_cyl(steer, Vector3(-0.03, 0.085, s * 0.07), Vector3(-0.045, 0.09, s * 0.14), 0.009, 0.009, "steel", 5)
		_cyl(steer, Vector3(-0.045, 0.09, s * 0.12), Vector3(-0.05, 0.09, s * 0.165), 0.015, 0.015, "tyre", 6)
	_cyl(steer, Vector3(-0.03, 0.085, -0.07), Vector3(-0.03, 0.085, 0.07), 0.009, 0.009, "steel", 5)
	# mirror on the left grip
	_cyl(steer, Vector3(-0.04, 0.09, -0.12), Vector3(-0.035, 0.15, -0.13), 0.004, 0.004, "steel", 4)
	_cyl(steer, Vector3(-0.04, 0.155, -0.13), Vector3(-0.03, 0.155, -0.13), 0.02, 0.02, "steel", 8)
	# frame
	_cyl(b, Vector3(0.24, 0.43, z), Vector3(-0.12, 0.35, z), 0.017, 0.015, "dark", 6)
	_cyl(b, Vector3(0.24, 0.43, z), Vector3(0.07, 0.12, z), 0.017, 0.015, "dark", 6)
	_cyl(b, Vector3(-0.12, 0.35, z), Vector3(-0.3, 0.14, z), 0.014, 0.014, "dark", 6)
	_cyl(b, Vector3(0.07, 0.12, z), Vector3(-0.3, 0.13, z), 0.014, 0.014, "dark", 6)
	# fuel tank with paint, knee pads
	_box(b, Vector3(0.1, 0.415, z), Vector3(0.22, 0.085, 0.1), PAINT, 0.035, Vector3(0, 0, -8))
	_box(b, Vector3(0.08, 0.42, z), Vector3(0.05, 0.03, 0.105), "dark", 0.008, Vector3(0, 0, -8))
	# boxer engine: cylinders stick out on both sides
	_box(b, Vector3(0.03, 0.2, z), Vector3(0.18, 0.13, 0.11), "dark", 0.025)
	_box(b, Vector3(-0.09, 0.22, z), Vector3(0.1, 0.1, 0.09), "olive", 0.02)
	_cyl(b, Vector3(0.07, 0.2, z - 0.16), Vector3(0.07, 0.2, z + 0.16), 0.034, 0.034, "steel", 8)
	for s: float in [-1.0, 1.0]:
		_box(b, Vector3(0.07, 0.2, z + s * 0.16), Vector3(0.08, 0.08, 0.03), "dark", 0.012)
		_cyl(b, Vector3(0.07, 0.17, z + s * 0.15), Vector3(-0.15, 0.1, z + s * 0.1), 0.012, 0.012, "rust", 5)
	_cyl(b, Vector3(-0.15, 0.1, z - 0.1), Vector3(-0.42, 0.12, z - 0.08), 0.022, 0.02, "rust", 8)
	# saddle, pillion pad, panniers, tail light
	_box(b, Vector3(-0.1, 0.36, z), Vector3(0.15, 0.035, 0.11), "leather", 0.014)
	_box(b, Vector3(-0.3, 0.295, z), Vector3(0.13, 0.028, 0.09), "leather", 0.01)
	for s: float in [-1.0, 1.0]:
		_box(b, Vector3(-0.31, 0.22, z + s * 0.07), Vector3(0.12, 0.1, 0.045), "leather", 0.012)
	_box(b, Vector3(-0.415, 0.27, z), Vector3(0.01, 0.025, 0.035), "red")
	# sidecar: boat-shaped tub, chassis struts, wheel, spare wheel
	_prof(b, [-0.3, 0.13, 0.12, 0.13, 0.3, 0.2, 0.33, 0.26, 0.25, 0.32, -0.2, 0.335, -0.31, 0.28], 0.25, SZ, PAINT, 0.05)
	_box(b, Vector3(-0.07, 0.334, SZ), Vector3(0.28, 0.012, 0.18), "leather", 0.004)
	_box(b, Vector3(-0.07, 0.341, SZ), Vector3(0.24, 0.006, 0.14), "dark")
	_box(b, Vector3(0.05, 0.25, SZ + 0.126), Vector3(0.16, 0.012, 0.004), "white")
	_wheel(b, Vector3(-0.04, 0.11, SZ + 0.155), 0.11, 0.045, 12)
	_fender(b, -0.04, 0.11, 0.125, 0.14, 10.0, 170.0, 0.055, SZ + 0.155, PAINT)
	for x: float in [0.12, -0.2]:
		_cyl(b, Vector3(x, 0.13, z), Vector3(x, 0.14, SZ + 0.16), 0.012, 0.012, "dark", 5)
	if not _W:
		_wheel(b, Vector3(-0.33, 0.24, SZ), 0.09, 0.04, 12).rotation_degrees = Vector3(0, 90, 0)
	# rider
	if not _W:
		_crew(b, "Driver", Vector3(-0.1, 0.4, z), Vector3(-0.05, 0.6, z), 0.17, Vector3(0.06, 0.13, z),
			Vector3(0.2, 0.55, z - 0.14), Vector3(0.2, 0.55, z + 0.14))
		# goggles on the helmet
		var head: Node3D = b.get_node("Driver/Head")
		_box(head, Vector3(-0.005, 0.69, z), Vector3(0.02, 0.018, 0.09), "dark")


static func _moto_turret(t: Node3D) -> void:
	# sidecar MG34 on a pedestal + gunner; local origin = pivot (in the sidecar)
	var mg := _node(t, "Gun", Vector3(0.0, 0.0, 0.0))
	_cyl(t, Vector3(0.17, 0.33, 0), Vector3(0.17, 0.53, 0), 0.012, 0.012, "dark", 6)
	_box(mg, Vector3(0.19, 0.555, 0), Vector3(0.17, 0.04, 0.03), "gun", 0.006)
	_cyl(mg, Vector3(0.27, 0.56, 0), Vector3(0.42, 0.56, 0), 0.016, 0.016, "gun", 8)
	_cyl(mg, Vector3(0.42, 0.56, 0), Vector3(0.46, 0.56, 0), 0.01, 0.014, "gun", 6)
	var riv := PackedVector3Array()
	_rivet_line(Vector3(0.28, 0.576, 0), Vector3(0.41, 0.576, 0), 5, riv)
	_rivets(mg, riv, 0.004, "dark")
	_obox(mg, Vector3(0.11, 0.55, 0), Vector3(0.0, 0.53, 0), 0.03, 0.022, "wood", 0.006)
	_cyl(mg, Vector3(0.18, 0.54, -0.035), Vector3(0.18, 0.54, -0.015), 0.04, 0.04, "gun", 10)
	_box(mg, Vector3(0.13, 0.52, 0), Vector3(0.02, 0.05, 0.015), "dark")
	_box(mg, Vector3(0.14, 0.585, 0), Vector3(0.01, 0.02, 0.01), "dark")
	_box(mg, Vector3(0.44, 0.58, 0), Vector3(0.008, 0.02, 0.006), "dark")
	if _W:
		mg.rotation_degrees = Vector3(0, 0, -12)
		return
	_crew(t, "Gunner", Vector3(-0.12, 0.24, 0.0), Vector3(-0.08, 0.53, 0.0), 0.2, Vector3(0.14, 0.15, 0.0),
		Vector3(0.18, 0.565, -0.06), Vector3(0.12, 0.51, 0.03))


# ----------------------------------------------------------------- JEEP ----

static func _jeep_hull(b: Node3D) -> void:
	_box(b, Vector3(0.02, 0.2, 0.0), Vector3(1.16, 0.06, 0.5), "dark")
	for s: float in [-1.0, 1.0]:
		for x: float in [0.4, -0.4]:
			_wheel(b, Vector3(x, 0.15, s * 0.33), 0.15, 0.1, 14)
		# flat front fenders
		if not (_W and s > 0.0):
			_box(b, Vector3(0.43, 0.37, s * 0.335), Vector3(0.36, 0.022, 0.15), PAINT, 0.006)
			_box(b, Vector3(0.645, 0.33, s * 0.335), Vector3(0.1, 0.02, 0.15), PAINT, 0.006, Vector3(0, 0, -40))
		_box(b, Vector3(0.43, 0.32, s * 0.262), Vector3(0.34, 0.1, 0.01), "dark")
		# headlights + blackout light in the grille
		_cyl(b, Vector3(0.625, 0.405, s * 0.16), Vector3(0.645, 0.405, s * 0.16), 0.034, 0.034, "dark", 10)
		_cyl(b, Vector3(0.645, 0.405, s * 0.16), Vector3(0.65, 0.405, s * 0.16), 0.027, 0.027, "light", 10)
		# rear wheel arches inside the tub
		_box(b, Vector3(-0.4, 0.3, s * 0.255), Vector3(0.32, 0.1, 0.06), "dark")
		# bumperettes + tail lights
		_box(b, Vector3(-0.63, 0.25, s * 0.26), Vector3(0.05, 0.05, 0.08), "dark")
		_box(b, Vector3(-0.605, 0.42, s * 0.27), Vector3(0.012, 0.03, 0.035), "red")
		# grab handles on the sides
		_box(b, Vector3(-0.2, 0.43, s * 0.318), Vector3(0.08, 0.015, 0.01), "dark")
	# bumper, grille, hood
	_box(b, Vector3(0.68, 0.23, 0.0), Vector3(0.05, 0.05, 0.76), PAINT, 0.01)
	_box(b, Vector3(0.62, 0.36, 0.0), Vector3(0.03, 0.22, 0.44), PAINT, 0.008)
	for i in 9:
		_box(b, Vector3(0.633, 0.36, -0.08 + 0.02 * float(i)), Vector3(0.012, 0.15, 0.008), "dark")
	_prof(b, [0.3, 0.27, 0.64, 0.27, 0.64, 0.47, 0.3, 0.5], 0.5, 0.0, PAINT, 0.02)
	# white ID star on the hood
	_cyl(b, Vector3(0.47, 0.485, 0), Vector3(0.47, 0.492, 0), 0.07, 0.07, "white", 5).rotation_degrees = Vector3(0, 0, -5.0)
	# tub: floor, sides, rear panel, cowl
	_box(b, Vector3(-0.15, 0.25, 0.0), Vector3(0.9, 0.04, 0.62), PAINT)
	for s: float in [-1.0, 1.0]:
		_box(b, Vector3(-0.15, 0.36, s * 0.3), Vector3(0.9, 0.22, 0.03), PAINT, 0.01)
	_box(b, Vector3(-0.59, 0.36, 0.0), Vector3(0.03, 0.22, 0.62), PAINT, 0.01)
	_box(b, Vector3(0.3, 0.39, 0.0), Vector3(0.06, 0.24, 0.62), PAINT, 0.012)
	# seats
	for s: float in [-1.0, 1.0]:
		_box(b, Vector3(0.0, 0.32, s * 0.16), Vector3(0.17, 0.06, 0.19), "canvas", 0.015)
		_box(b, Vector3(-0.09, 0.42, s * 0.16), Vector3(0.04, 0.18, 0.19), "canvas", 0.015, Vector3(0, 0, 8))
	_box(b, Vector3(-0.5, 0.34, 0.0), Vector3(0.14, 0.05, 0.5), "canvas", 0.015)
	# windshield (slightly raked)
	var ws := _node(b, "Windshield", Vector3(0.33, 0.5, 0.0), Vector3(0, 0, 9))
	if not _W:
		_box(ws, Vector3(0, 0.015, 0), Vector3(0.03, 0.03, 0.62), PAINT, 0.006)
		_box(ws, Vector3(0, 0.37, 0), Vector3(0.022, 0.022, 0.62), PAINT, 0.005)
		for s: float in [-1.0, 1.0]:
			_box(ws, Vector3(0, 0.19, s * 0.3), Vector3(0.022, 0.36, 0.022), PAINT, 0.005)
		_box(ws, Vector3(0, 0.19, 0.0), Vector3(0.016, 0.34, 0.01), "olive")
		var gl := _node(ws, "Glass")
		for s: float in [-1.0, 1.0]:
			_box(gl, Vector3(0, 0.19, s * 0.147), Vector3(0.008, 0.335, 0.28), "glass")
	else:
		_box(ws, Vector3(0, 0.015, 0), Vector3(0.03, 0.03, 0.62), PAINT, 0.006)
		_box(ws, Vector3(0, 0.1, -0.295), Vector3(0.03, 0.17, 0.03), PAINT, 0.006, Vector3(25, 0, 0))
	# steering column + wheel
	_cyl(b, Vector3(0.3, 0.44, -0.16), Vector3(0.13, 0.58, -0.16), 0.012, 0.012, "dark", 6)
	var sw := _node(b, "SteerWheel", Vector3(0.12, 0.59, -0.16))
	sw.basis = _basis_y(Vector3(-0.6, 1.0, 0.0))
	_torus(sw, Vector3.ZERO, Vector3.UP, 0.07, 0.008, "dark")
	for i in 3:
		var a := TAU * float(i) / 3.0 + PI * 0.5
		_cyl(sw, Vector3.ZERO, Vector3(cos(a) * 0.066, 0.0, sin(a) * 0.066), 0.005, 0.005, "dark", 4)
	_cyl(sw, Vector3(0, -0.01, 0), Vector3(0, 0.01, 0), 0.016, 0.016, "dark", 8)
	# dashboard gauges
	for s: float in [-0.08, 0.0]:
		_cyl(b, Vector3(0.265, 0.47, s - 0.12), Vector3(0.27, 0.47, s - 0.12), 0.02, 0.02, "dark", 8)
	# spare wheel + jerrycan on the back, shovel and axe on the side
	_wheel(b, Vector3(-0.66, 0.37, 0.15), 0.14, 0.08, 14).rotation_degrees = Vector3(0, 90, 0)
	_box(b, Vector3(-0.63, 0.35, -0.2), Vector3(0.06, 0.16, 0.11), "olive", 0.012)
	_box(b, Vector3(-0.15, 0.37, -0.318), Vector3(0.36, 0.018, 0.01), "wood")
	_box(b, Vector3(0.05, 0.37, -0.318), Vector3(0.06, 0.04, 0.01), "steel")
	# pintle post for the MG (static part)
	_cyl(b, Vector3(-0.25, 0.27, 0.0), Vector3(-0.25, 0.53, 0.0), 0.022, 0.018, "gun", 8)
	_box(b, Vector3(-0.25, 0.28, 0.0), Vector3(0.1, 0.02, 0.1), "dark")
	# driver
	if not _W:
		_crew(b, "Driver", Vector3(-0.1, 0.39, -0.16), Vector3(-0.08, 0.66, -0.16), 0.2, Vector3(0.2, 0.27, -0.16),
			Vector3(0.09, 0.63, -0.21), Vector3(0.1, 0.62, -0.1))


static func _jeep_turret(t: Node3D) -> void:
	# pintle head + heavy MG + ammo can + gunner; local origin = pivot (top of the post)
	var mg := _node(t, "Gun", Vector3(0.0, -0.03, 0.0))
	_cyl(t, Vector3(0, 0.52, 0), Vector3(0, 0.57, 0), 0.016, 0.016, "gun", 6)
	_box(t, Vector3(0.0, 0.57, 0), Vector3(0.06, 0.03, 0.08), "gun", 0.006)
	_box(mg, Vector3(-0.01, 0.65, 0), Vector3(0.22, 0.07, 0.065), "gun", 0.01)
	_box(mg, Vector3(-0.02, 0.69, 0), Vector3(0.16, 0.012, 0.06), "gun")
	_cyl(mg, Vector3(0.1, 0.645, 0), Vector3(0.3, 0.645, 0), 0.024, 0.024, "gun", 10)
	var riv := PackedVector3Array()
	for i in 6:
		riv.append(Vector3(0.12 + 0.03 * float(i), 0.668, 0))
		riv.append(Vector3(0.12 + 0.03 * float(i), 0.645, 0.024))
		riv.append(Vector3(0.12 + 0.03 * float(i), 0.645, -0.024))
	_rivets(mg, riv, 0.005, "dark")
	_cyl(mg, Vector3(0.3, 0.645, 0), Vector3(0.47, 0.645, 0), 0.014, 0.014, "gun", 8)
	_cyl(mg, Vector3(0.45, 0.645, 0), Vector3(0.5, 0.645, 0), 0.02, 0.018, "gun", 8)
	_box(mg, Vector3(0.48, 0.672, 0), Vector3(0.012, 0.03, 0.006), "dark")
	_box(mg, Vector3(-0.05, 0.705, 0), Vector3(0.012, 0.03, 0.03), "dark")
	# spade grips
	for s: float in [-1.0, 1.0]:
		_cyl(mg, Vector3(-0.125, 0.66, s * 0.03), Vector3(-0.15, 0.6, s * 0.03), 0.011, 0.011, "wood", 6)
	_box(mg, Vector3(-0.125, 0.645, 0), Vector3(0.02, 0.05, 0.05), "gun")
	# ammo can + belt
	_box(mg, Vector3(-0.01, 0.62, -0.085), Vector3(0.12, 0.08, 0.06), "olive", 0.01)
	_box(mg, Vector3(0.0, 0.665, -0.05), Vector3(0.04, 0.008, 0.04), "brass")
	if _W:
		mg.rotation_degrees = Vector3(0, 0, -14)
		return
	_crew(t, "Gunner", Vector3(-0.38, 0.42, 0.0), Vector3(-0.37, 0.68, 0.0), 0.12, Vector3(-0.24, 0.27, 0.0),
		Vector3(-0.15, 0.6, -0.035), Vector3(-0.15, 0.6, 0.035))


# --------------------------------------------------------- ROCKET TRUCK ----

# ------------------------------------------------------------ planes ----

## Roundel (team paint ring with a white centre) on a wing top / fuselage side.
static func _roundel(b: Node3D, c: Vector3, axis: Vector3, r: float) -> void:
	_cyl(b, c, c + axis * 0.006, r, r, PAINT, 12)
	_cyl(b, c + axis * 0.006, c + axis * 0.012, r * 0.62, r * 0.62, "white", 12)
	_cyl(b, c + axis * 0.012, c + axis * 0.016, r * 0.28, r * 0.28, "red", 10)


static func _gear(b: Node3D, x: float, z: float, top: float, r: float) -> void:
	_box(b, Vector3(x, (top + r) * 0.5, z), Vector3(0.035, top - r, 0.035), "dark")
	_cyl(b, Vector3(x, r, z - 0.035), Vector3(x, r, z + 0.035), r, r, "tyre", 12)


## Single-engine fighter-bomber: ~2.4 long, 3.0 wingspan.
static func _fighter_hull(b: Node3D) -> void:
	var y := 0.55
	_cyl(b, Vector3(-1.15, y + 0.08, 0), Vector3(-0.2, y, 0), 0.07, 0.19, PAINT, 12)
	_cyl(b, Vector3(-0.2, y, 0), Vector3(1.05, y, 0), 0.19, 0.2, PAINT, 12)
	_cyl(b, Vector3(1.05, y, 0), Vector3(1.24, y, 0), 0.2, 0.15, "dark", 12)
	for s: float in [-1.0, 1.0]:
		_cyl(b, Vector3(0.9, y + 0.12, s * 0.15), Vector3(0.6, y + 0.1, s * 0.17), 0.025, 0.025, "steel", 6)   # exhausts
	# wings (slight dihedral) + tips
	for s: float in [-1.0, 1.0]:
		_box(b, Vector3(0.3, y - 0.1 + 0.04, s * 0.78), Vector3(0.62, 0.05, 1.4), PAINT, 0.01, Vector3(s * -3.0, 0, 0))
		_box(b, Vector3(0.24, y - 0.04 + 0.05, s * 1.5), Vector3(0.42, 0.04, 0.12), PAINT, 0.01, Vector3(s * -3.0, 0, 0))
		_roundel(b, Vector3(0.28, y - 0.03, s * 1.15), Vector3.UP, 0.15)
		_gear(b, 0.42, s * 0.48, y - 0.1, 0.1)
		# light bombs under the wings
		_cyl(b, Vector3(0.12, y - 0.24, s * 0.85), Vector3(0.55, y - 0.24, s * 0.85), 0.05, 0.05, "olive", 8)
		_box(b, Vector3(0.1, y - 0.24, s * 0.85), Vector3(0.06, 0.12, 0.012), "olive")
	# canopy + tail
	_sphere(b, Vector3(0.12, y + 0.17, 0), 0.15, "glass", 10, true)
	_box(b, Vector3(-0.15, y + 0.17, 0), Vector3(0.36, 0.1, 0.22), PAINT, 0.03)
	_box(b, Vector3(-1.02, y + 0.1, 0), Vector3(0.3, 0.03, 0.95), PAINT, 0.01)
	_box(b, Vector3(-1.06, y + 0.3, 0), Vector3(0.28, 0.38, 0.03), PAINT, 0.01, Vector3(0, 0, 12))
	_box(b, Vector3(-1.08, y + 0.4, 0), Vector3(0.14, 0.12, 0.035), "white")
	_gear(b, -1.05, 0.0, y, 0.05)
	_roundel(b, Vector3(-0.55, y + 0.02, 0.19), Vector3(0, 0, 1), 0.11)
	_roundel(b, Vector3(-0.55, y + 0.02, -0.19), Vector3(0, 0, -1), 0.11)


## Spinning propeller (authored around the axis at the origin, +X forward).
static func _prop(t: Node3D, span: float) -> void:
	_cyl(t, Vector3(-0.03, 0, 0), Vector3(0.1, 0, 0), 0.07, 0.025, "steel", 10)
	_box(t, Vector3(0.02, 0, 0), Vector3(0.02, span, 0.07), "dark", 0.0, Vector3(25, 0, 0))
	_box(t, Vector3(0.02, 0, 0), Vector3(0.02, 0.07, span), "dark", 0.0, Vector3(25, 0, 0))
	_box(t, Vector3(0.02, span * 0.47, 0), Vector3(0.025, 0.05, 0.075), "brass")
	_box(t, Vector3(0.02, -span * 0.47, 0), Vector3(0.025, 0.05, 0.075), "brass")


## Twin-engine heavy bomber: ~3.6 long, 4.6 wingspan, glazed nose, prop discs on both engines.
static func _heavy_hull(b: Node3D) -> void:
	var y := 0.75
	_cyl(b, Vector3(-1.75, y + 0.12, 0), Vector3(-0.6, y, 0), 0.1, 0.3, PAINT, 14)
	_cyl(b, Vector3(-0.6, y, 0), Vector3(1.5, y, 0), 0.3, 0.3, PAINT, 14)
	_cyl(b, Vector3(1.5, y, 0), Vector3(1.85, y - 0.03, 0), 0.3, 0.2, PAINT, 14)
	_box(b, Vector3(1.0, y + 0.3, 0), Vector3(0.4, 0.12, 0.3), "glass", 0.04)
	for s: float in [-1.0, 1.0]:
		_box(b, Vector3(0.3, y - 0.05, s * 1.25), Vector3(0.8, 0.07, 2.1), PAINT, 0.015)
		_box(b, Vector3(0.22, y - 0.04, s * 2.35), Vector3(0.5, 0.05, 0.2), PAINT, 0.01)
		_roundel(b, Vector3(0.3, y, s * 1.7), Vector3.UP, 0.22)
		# engine nacelle + prop disc (blur) + exhausts
		var ez := s * 0.95
		_cyl(b, Vector3(-0.2, y - 0.06, ez), Vector3(0.9, y - 0.06, ez), 0.12, 0.17, PAINT, 12)
		_cyl(b, Vector3(0.9, y - 0.06, ez), Vector3(1.02, y - 0.06, ez), 0.17, 0.12, "dark", 12)
		_cyl(b, Vector3(1.05, y - 0.06, ez), Vector3(1.06, y - 0.06, ez), 0.55, 0.55, "glass", 18)
		_cyl(b, Vector3(1.02, y - 0.06, ez), Vector3(1.1, y - 0.06, ez), 0.05, 0.02, "steel", 8)
		_gear(b, 0.45, ez, y - 0.2, 0.16)
	# bomb bay doors, tail with twin fins
	_box(b, Vector3(0.0, y - 0.29, 0), Vector3(1.0, 0.03, 0.34), "dark")
	_box(b, Vector3(-1.6, y + 0.14, 0), Vector3(0.4, 0.04, 1.5), PAINT, 0.01)
	for s: float in [-1.0, 1.0]:
		_box(b, Vector3(-1.66, y + 0.38, s * 0.72), Vector3(0.32, 0.5, 0.035), PAINT, 0.01, Vector3(0, 0, 10))
	_sphere(b, Vector3(-1.7, y + 0.2, 0), 0.1, "glass", 8)   # tail gunner
	_gear(b, -1.6, 0.0, y, 0.07)
	_roundel(b, Vector3(-0.8, y + 0.05, 0.3), Vector3(0, 0, 1), 0.15)
	_roundel(b, Vector3(-0.8, y + 0.05, -0.3), Vector3(0, 0, -1), 0.15)


## Heavy bomber "turret": glazed nose with a gun (static).
static func _heavy_nose(t: Node3D) -> void:
	_sphere(t, Vector3(-0.08, 0.72, 0), 0.2, "glass", 12)
	_cyl(t, Vector3(0.0, 0.7, 0), Vector3(0.3, 0.7, 0), 0.02, 0.02, "gun", 6)


## Dive bomber: inverted-gull wings, long two-seat canopy, spatted fixed gear, one big bomb under the belly.
static func _dive_hull(b: Node3D) -> void:
	var y := 0.6
	_cyl(b, Vector3(-1.3, y + 0.1, 0), Vector3(-0.2, y, 0), 0.07, 0.21, PAINT, 12)
	_cyl(b, Vector3(-0.2, y, 0), Vector3(1.15, y, 0), 0.21, 0.21, PAINT, 12)
	_cyl(b, Vector3(1.15, y, 0), Vector3(1.34, y, 0), 0.21, 0.16, "dark", 12)
	_box(b, Vector3(0.05, y + 0.18, 0), Vector3(0.9, 0.14, 0.2), "glass", 0.04)
	for s: float in [-1.0, 1.0]:
		# gull wing: inner panel angled down, outer panel up
		_box(b, Vector3(0.35, y - 0.18, s * 0.42), Vector3(0.62, 0.05, 0.6), PAINT, 0.01, Vector3(s * 18.0, 0, 0))
		_box(b, Vector3(0.3, y - 0.12, s * 1.2), Vector3(0.55, 0.05, 1.05), PAINT, 0.01, Vector3(s * -7.0, 0, 0))
		_roundel(b, Vector3(0.3, y - 0.08, s * 1.3), Vector3.UP, 0.15)
		# spatted gear at the wing bend
		_box(b, Vector3(0.38, y - 0.4, s * 0.68), Vector3(0.06, 0.35, 0.06), PAINT)
		_cyl(b, Vector3(0.28, 0.12, s * 0.68), Vector3(0.55, 0.12, s * 0.68), 0.06, 0.1, PAINT, 10)
		_cyl(b, Vector3(0.38, 0.11, s * 0.68 - 0.035), Vector3(0.38, 0.11, s * 0.68 + 0.035), 0.1, 0.1, "tyre", 10)
		# dive brakes under the wings
		_box(b, Vector3(0.1, y - 0.3, s * 1.1), Vector3(0.04, 0.1, 0.6), "dark")
	_cyl(b, Vector3(-0.1, y - 0.36, 0), Vector3(0.6, y - 0.36, 0), 0.09, 0.09, "olive", 10)
	_box(b, Vector3(-0.12, y - 0.36, 0), Vector3(0.08, 0.2, 0.02), "olive")
	_box(b, Vector3(-1.2, y + 0.12, 0), Vector3(0.3, 0.035, 1.0), PAINT, 0.01)
	_box(b, Vector3(-1.24, y + 0.34, 0), Vector3(0.3, 0.42, 0.035), PAINT, 0.01, Vector3(0, 0, 8))
	_gear(b, -1.2, 0.0, y, 0.05)
	_roundel(b, Vector3(-0.6, y + 0.02, 0.21), Vector3(0, 0, 1), 0.12)
	_roundel(b, Vector3(-0.6, y + 0.02, -0.21), Vector3(0, 0, -1), 0.12)


static func _truck_hull(b: Node3D) -> void:
	_box(b, Vector3(-0.03, 0.27, 0.0), Vector3(1.56, 0.07, 0.44), "dark")
	_box(b, Vector3(0.83, 0.26, 0.0), Vector3(0.04, 0.05, 0.74), "dark", 0.008)
	var shell := _node(b, "CabShell")
	for s: float in [-1.0, 1.0]:
		for x: float in [0.5, -0.28, -0.56]:
			_wheel(b, Vector3(x, 0.17, s * 0.355), 0.17, 0.11, 14)
		# curved front fenders + running boards
		if not (_W and s < 0.0):
			_fender(b, 0.5, 0.17, 0.195, 0.215, 0.0, 180.0, 0.15, s * 0.335, PAINT)
		_box(b, Vector3(0.21, 0.33, s * 0.35), Vector3(0.2, 0.02, 0.12), "dark", 0.004)
		# headlights on the fenders
		_cyl(b, Vector3(0.6, 0.42, s * 0.28), Vector3(0.68, 0.42, s * 0.28), 0.036, 0.04, "dark", 10)
		_cyl(b, Vector3(0.68, 0.42, s * 0.28), Vector3(0.685, 0.42, s * 0.28), 0.032, 0.032, "light", 10)
		_cyl(b, Vector3(0.62, 0.38, s * 0.28), Vector3(0.62, 0.42, s * 0.28), 0.01, 0.01, "dark", 4)
		# side windows, door seam + handle, mirrors
		_box(shell, Vector3(0.32, 0.79, s * 0.392), Vector3(0.22, 0.17, 0.012), "glass")
		_box(shell, Vector3(0.32, 0.5, s * 0.391), Vector3(0.3, 0.008, 0.01), "olive")
		_box(shell, Vector3(0.22, 0.6, s * 0.395), Vector3(0.04, 0.012, 0.012), "steel")
		_cyl(shell, Vector3(0.48, 0.8, s * 0.39), Vector3(0.5, 0.82, s * 0.47), 0.005, 0.005, "dark", 4)
		_box(shell, Vector3(0.5, 0.84, s * 0.47), Vector3(0.01, 0.05, 0.03), "dark")
		# stabiliser jacks at the rear
		_cyl(b, Vector3(-0.72, 0.3, s * 0.3), Vector3(-0.74, 0.04, s * 0.33), 0.016, 0.016, "dark", 6)
		_box(b, Vector3(-0.74, 0.03, s * 0.33), Vector3(0.07, 0.015, 0.07), "dark")
		# bed side boards, mud flaps, tail lights, fuel tank
		_box(b, Vector3(-0.31, 0.41, s * 0.43), Vector3(0.88, 0.06, 0.025), PAINT, 0.006)
		_box(b, Vector3(-0.73, 0.22, s * 0.355), Vector3(0.012, 0.12, 0.1), "tyre")
		_box(b, Vector3(-0.755, 0.38, s * 0.38), Vector3(0.012, 0.03, 0.04), "red")
	_cyl(b, Vector3(-0.05, 0.3, -0.33), Vector3(0.12, 0.3, -0.33), 0.06, 0.06, "olive", 10)
	# hood + radiator grille
	_prof(b, [0.48, 0.3, 0.8, 0.3, 0.805, 0.56, 0.77, 0.6, 0.48, 0.62], 0.42, 0.0, PAINT, 0.03)
	_box(b, Vector3(0.808, 0.44, 0.0), Vector3(0.015, 0.24, 0.3), "dark")
	for i in 7:
		_box(b, Vector3(0.815, 0.44, -0.12 + 0.04 * float(i)), Vector3(0.01, 0.22, 0.012), "olive2")
	for s: float in [-1.0, 1.0]:
		for i in 4:
			_box(b, Vector3(0.6 + 0.04 * float(i), 0.5, s * 0.212), Vector3(0.012, 0.07, 0.006), "dark")
	# cab
	_prof(shell, [0.12, 0.3, 0.5, 0.3, 0.5, 0.71, 0.47, 0.92, 0.14, 0.94], 0.78, 0.0, PAINT, 0.03)
	var gl := _node(shell, "Glass")
	for s: float in [-1.0, 1.0]:
		_box(gl, Vector3(0.485, 0.815, s * 0.17), Vector3(0.01, 0.19, 0.31), "glass", 0.0, Vector3(0, 0, 8.5))
	_box(shell, Vector3(0.485, 0.815, 0.0), Vector3(0.016, 0.21, 0.018), "olive", 0.0, Vector3(0, 0, 8.5))
	# cab interior (visible from the driver's seat): dashboard, pillars, header, steering wheel
	var cab := _node(b, "Cab")
	_box(cab, Vector3(0.425, 0.665, 0.0), Vector3(0.11, 0.1, 0.72), "olive", 0.012)
	_box(cab, Vector3(0.375, 0.665, -0.18), Vector3(0.012, 0.06, 0.2), "dark")
	for s: float in [-1.0, 1.0]:
		_box(cab, Vector3(0.47, 0.815, s * 0.36), Vector3(0.04, 0.24, 0.05), "olive", 0.008, Vector3(0, 0, 8.5))
	_box(cab, Vector3(0.44, 0.905, 0.0), Vector3(0.06, 0.035, 0.76), "olive", 0.008)
	for s: float in [-0.25, -0.11]:
		_cyl(cab, Vector3(0.366, 0.67, s), Vector3(0.37, 0.67, s), 0.02, 0.02, "dark", 10)
		_cyl(cab, Vector3(0.364, 0.67, s), Vector3(0.366, 0.67, s), 0.016, 0.016, "white", 10)
	_cyl(cab, Vector3(0.42, 0.6, -0.18), Vector3(0.33, 0.7, -0.18), 0.012, 0.012, "dark", 6)
	var sw := _node(cab, "SteerWheel", Vector3(0.325, 0.705, -0.18))
	sw.basis = _basis_y(Vector3(-1.0, 1.6, 0.0))
	_torus(sw, Vector3.ZERO, Vector3.UP, 0.075, 0.008, "dark")
	for i in 3:
		var a := TAU * float(i) / 3.0 + PI * 0.5
		_cyl(sw, Vector3.ZERO, Vector3(cos(a) * 0.07, 0.0, sin(a) * 0.07), 0.005, 0.005, "dark", 4)
	# cab roof: spotlight + whip antenna
	_cyl(shell, Vector3(0.36, 0.955, 0.28), Vector3(0.36, 0.99, 0.28), 0.008, 0.008, "dark", 4)
	_cyl(shell, Vector3(0.34, 1.0, 0.28), Vector3(0.4, 1.0, 0.28), 0.03, 0.03, "dark", 8)
	if not _W:
		_cyl(shell, Vector3(0.16, 0.95, -0.36), Vector3(0.1, 1.28, -0.38), 0.007, 0.005, "dark", 4)
	# flat bed + stowage boxes behind the cab
	_box(b, Vector3(-0.31, 0.36, 0.0), Vector3(0.88, 0.04, 0.86), "wood", 0.006)
	for i in 6:
		_box(b, Vector3(-0.31, 0.382, -0.36 + 0.144 * float(i)), Vector3(0.86, 0.004, 0.01), "dark")
	_box(b, Vector3(-0.755, 0.41, 0.0), Vector3(0.025, 0.06, 0.86), PAINT, 0.006)
	for s: float in [-1.0, 1.0]:
		_box(b, Vector3(0.06, 0.45, s * 0.3), Vector3(0.09, 0.14, 0.2), "olive", 0.012)


static func _truck_turret(t: Node3D) -> void:
	_cyl(t, Vector3(0, 0.38, 0), Vector3(0, 0.44, 0), 0.24, 0.24, "dark", 16)
	_box(t, Vector3(0.0, 0.47, 0.0), Vector3(0.5, 0.06, 0.4), PAINT, 0.01)
	for s: float in [-1.0, 1.0]:
		_prof(t, [-0.24, 0.47, 0.18, 0.47, -0.03, 0.66], 0.025, s * 0.19, PAINT, 0.004)
	# gun-layer's sight box on the left
	_box(t, Vector3(-0.12, 0.58, -0.225), Vector3(0.08, 0.06, 0.04), "dark", 0.008)
	var rack := _node(t, "Gun", Vector3(-0.04, 0.63, 0.0), Vector3(0, 0, 9.0 if not _W else 2.0))
	_cyl(rack, Vector3(0, 0, -0.2), Vector3(0, 0, 0.2), 0.022, 0.022, "dark", 8)
	var x0 := -0.33
	var x1 := 0.43
	for row in 2:
		var y := 0.05 + 0.085 * float(row)
		for col in 4:
			var z := -0.135 + 0.09 * float(col)
			_cyl(rack, Vector3(x0, y, z), Vector3(x1, y, z), 0.04, 0.04, "olive", 8)
			_cyl(rack, Vector3(x1, y, z), Vector3(x1 + 0.003, y, z), 0.032, 0.032, "dark", 8)
			if not _W:
				_cyl(rack, Vector3(x1 - 0.02, y, z), Vector3(x1 + 0.05, y, z), 0.03, 0.012, "warhead", 8)
				_cyl(rack, Vector3(x1 + 0.005, y, z), Vector3(x1 + 0.015, y, z), 0.031, 0.029, "red", 8)
	for x: float in [-0.22, 0.05, 0.32]:
		_box(rack, Vector3(x, 0.092, 0.0), Vector3(0.035, 0.21, 0.38), PAINT, 0.008)
	for s: float in [-1.0, 1.0]:
		_box(rack, Vector3(0.05, 0.0, s * 0.19), Vector3(0.78, 0.03, 0.02), PAINT, 0.004)
