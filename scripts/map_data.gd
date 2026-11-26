extends RefCounted
## The grid map: walls, floors, roofs, props, 4 guarded bunkers and team spawns. Generated deterministically.
##
## Layout: team base camps sit in the 4 corners; one bunker sits on each side of the map, so every
## team has two bunkers at equal distance. Each bunker = walled compound with 4 gates, 2 key-locked
## puzzle huts, an armory hut, a barracks hut and the vault building.

const Defs = preload("res://scripts/defs.gd")
const Atmos = preload("res://scripts/atmos.gd")
const FR_LAMP := Atmos.FR_LAMP

const ROCK := 1
const BRICK := 2
const COMPOUND := 3
const TECH := 4
const DOOR := 5
const GATE := 6
const HUT := 7
const KEYDOOR := 8
const SANDBAG := 9
const CRATE := 10
const CONTAINER := 11
const CONCRETE := 12
const PLANKS := 13
const STEEL := 14
const HEDGE := 15
const PLASTER := 16
const WALL_TYPES := 16
# default block height of each wall type (1 unit = 1 cell; a standing soldier is 0.95 tall)
const DEF_H := [0.0, 1.4, 1.8, 2.0, 1.9, 1.9, 2.0, 1.45, 1.45, 0.55, 0.75, 1.25, 1.0, 0.6, 0.3, 0.85, 2.0]

const F_GROUND := 0
const F_DIRT := 1
const F_CONCRETE := 2
const F_METAL := 3
const F_WATER := 4
const F_COBBLE := 5

# vertical movement rules
const STEP := 0.36     # highest ledge you can walk up without jumping
const HEAD := 0.9      # head clearance needed
const CEIL := 1.0      # interior ceiling height
const HSCALE := 40.0   # height -> texture byte

# theme = weather class (0 temperate: pollen / thunderstorm, 1 arid: dust / sandstorm, 2 snow, 3 urban: embers / ash storm)
# palette = colour set in THEMES; layout = where the 4 camps and 4 bunkers sit (see _layout)
const MAPS := [
	{"name": "Green Valley", "size": 160, "theme": 0, "palette": 0, "layout": "cross", "style": "valley", "desc": "Rolling grassland, woods and old ruins. Bunkers on the four sides."},
	{"name": "Dust Fortress", "size": 160, "theme": 1, "palette": 1, "layout": "pinwheel", "style": "desert", "desc": "Open desert with mesas and wrecks. Long sightlines, staggered bunkers."},
	{"name": "Frost Ridge", "size": 176, "theme": 2, "palette": 2, "layout": "diamond", "style": "snow", "desc": "Snowy ridges and pine forest. Bunkers in the corners, camps between them."},
	{"name": "Ruined Town", "size": 160, "theme": 3, "palette": 3, "layout": "inner", "style": "town", "desc": "Four bunkers locked together in the town centre. Street fighting."},
	{"name": "Red Canyon", "size": 176, "theme": 1, "palette": 4, "layout": "diamond", "style": "canyon", "desc": "Towering red rock walls and narrow passes. Pick your route."},
	{"name": "Harbor Yard", "size": 160, "theme": 0, "palette": 5, "layout": "inner", "style": "harbor", "desc": "Container stacks, warehouses and canals around a central fortress block."},
	{"name": "Marshlands", "size": 160, "theme": 0, "palette": 6, "layout": "pinwheel", "style": "marsh", "desc": "Foggy swamp: wade through ponds and reeds between hedgerows."},
	{"name": "Coastline", "size": 176, "theme": 0, "palette": 7, "layout": "cross", "style": "coast", "desc": "Beaches, dunes and surf along two shores. Wide open flanks."},
]
const LAYOUT_NAMES := {
	"cross": ["NORTH", "SOUTH", "WEST", "EAST"],
	"pinwheel": ["NORTH", "SOUTH", "WEST", "EAST"],
	"diamond": ["NORTH-WEST", "NORTH-EAST", "SOUTH-EAST", "SOUTH-WEST"],
	"inner": ["NORTH-WEST", "NORTH-EAST", "SOUTH-EAST", "SOUTH-WEST"],
}

# ground_a, ground_b, dirt_a, dirt_b, sky_top, sky_hor, fog, mountain, rock tint, fog distance
const THEMES := [
	[Color(0.19, 0.29, 0.12), Color(0.27, 0.37, 0.16), Color(0.33, 0.27, 0.19), Color(0.41, 0.34, 0.24),
		Color(0.30, 0.42, 0.58), Color(0.72, 0.64, 0.52), Color(0.62, 0.62, 0.58), Color(0.30, 0.31, 0.37), Color(1, 1, 1), 34.0],
	[Color(0.62, 0.50, 0.32), Color(0.70, 0.58, 0.38), Color(0.50, 0.38, 0.25), Color(0.56, 0.44, 0.30),
		Color(0.32, 0.50, 0.72), Color(0.92, 0.76, 0.55), Color(0.86, 0.74, 0.58), Color(0.62, 0.42, 0.30), Color(1.25, 1.05, 0.8), 40.0],
	[Color(0.80, 0.82, 0.87), Color(0.92, 0.93, 0.96), Color(0.52, 0.52, 0.56), Color(0.60, 0.60, 0.64),
		Color(0.52, 0.58, 0.66), Color(0.80, 0.82, 0.86), Color(0.80, 0.82, 0.86), Color(0.55, 0.58, 0.66), Color(0.95, 1.0, 1.1), 22.0],
	[Color(0.30, 0.28, 0.24), Color(0.36, 0.33, 0.28), Color(0.25, 0.23, 0.21), Color(0.31, 0.29, 0.26),
		Color(0.22, 0.20, 0.30), Color(0.78, 0.45, 0.30), Color(0.46, 0.38, 0.35), Color(0.20, 0.18, 0.24), Color(0.9, 0.85, 0.85), 26.0],
	# 4 red canyon
	[Color(0.58, 0.36, 0.24), Color(0.66, 0.42, 0.28), Color(0.48, 0.30, 0.20), Color(0.55, 0.35, 0.24),
		Color(0.36, 0.52, 0.74), Color(0.95, 0.74, 0.55), Color(0.85, 0.62, 0.48), Color(0.55, 0.28, 0.20), Color(1.35, 0.85, 0.65), 42.0],
	# 5 harbor (overcast)
	[Color(0.33, 0.34, 0.33), Color(0.39, 0.40, 0.39), Color(0.30, 0.28, 0.25), Color(0.36, 0.33, 0.29),
		Color(0.38, 0.45, 0.55), Color(0.68, 0.70, 0.72), Color(0.60, 0.63, 0.66), Color(0.32, 0.36, 0.42), Color(0.9, 0.95, 1.05), 28.0],
	# 6 marsh (misty)
	[Color(0.20, 0.25, 0.12), Color(0.26, 0.30, 0.15), Color(0.27, 0.24, 0.16), Color(0.32, 0.28, 0.19),
		Color(0.40, 0.47, 0.45), Color(0.66, 0.68, 0.58), Color(0.55, 0.60, 0.52), Color(0.28, 0.33, 0.30), Color(0.9, 1.0, 0.9), 24.0],
	# 7 coast (sunny, sandy dirt)
	[Color(0.30, 0.45, 0.18), Color(0.38, 0.52, 0.22), Color(0.84, 0.76, 0.55), Color(0.90, 0.82, 0.62),
		Color(0.25, 0.50, 0.85), Color(0.80, 0.86, 0.92), Color(0.75, 0.82, 0.88), Color(0.40, 0.50, 0.62), Color(1.05, 1.0, 0.95), 44.0],
]

# Vault building (12x12) at bunker (+6, +6). '#' wall, '.' floor, 'g' guard, 'R' vault centre, 'M' vault door
const BUILDING := [
	"############",
	"#g...#....g#",
	"#.##.#.##..#",
	"#.#..#..#..#",
	"#.#.####.#.#",
	"#...#R.#...#",
	"#.#.#..#.#.#",
	"#.#.##.#.#.#",
	"#.#......#.#",
	"#.####.###.#",
	"#g....g....#",
	"#####M######",
]

var W := 160
var H := 160
var theme := 0                   # weather class
var palette := 0                 # colour set (THEMES index)
var layout := "cross"
var bunker_names: Array = ["NORTH", "SOUTH", "WEST", "EAST"]
var team_bunker: Array = [0, 1, 3, 2]   # team -> the bunker it owns
var map_index := 0
var rooms := 2                   # puzzle rooms per bunker (= players per team: 2 or 4)
var with_bunkers := true         # HEIST only
var camp_ammo: Array = []        # per team: Vector2 of the base camp's resupply crate
var wall := PackedByteArray()
var flo := PackedByteArray()
var roof := PackedByteArray()
var obst := PackedByteArray()
var hgt := PackedFloat32Array()   # block height of wall cells
var rtop := PackedFloat32Array()  # roof slab top of roofed cells (slab spans CEIL .. rtop)
var decor: Array = []           # [x, y, frame, scale, z]
var emitters: Array = []        # [x, y, z, kind]  0 = smoke column, 1 = fire
var lamps: Array = []           # [x, y, z] light of a lamp post / floodlight (decor frame Atmos.FR_LAMP)
var weather := 0                # match weather + time of day from the match cfg (scripts/atmos.gd)
var tod := 1
var team_spawns: Array = []     # Vector3(x, y, yaw)
var mortars: Array = []         # per team: Vector2 centre of the base camp's mortar pit
var soldier_spawns: Array = []
var turret_spawns: Array = []
var bunkers: Array = []         # see _build_bunker
var gates: Array = []           # flat list: {cells, approach, center, bunker}
var rng := RandomNumberGenerator.new()
var _zones: Array = []          # Rect2i no-terrain zones (bunkers + margins)


func get_wall(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= W or y >= H:
		return ROCK
	return wall[y * W + x]


func set_wall(x: int, y: int, v: int) -> void:
	if x < 0 or y < 0 or x >= W or y >= H:
		return
	wall[y * W + x] = v


func has_roof(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= W or y >= H:
		return false
	return roof[y * W + x] != 0


func is_solid_at(p: Vector2) -> bool:
	return get_wall(floori(p.x), floori(p.y)) != 0


## Height of the block in a cell (0 for open ground), out of map = very tall.
func cell_h(x: int, y: int) -> float:
	if x < 0 or y < 0 or x >= W or y >= H:
		return 9.0
	var i := y * W + x
	return hgt[i] if wall[i] != 0 else 0.0


func floor_at(p: Vector2) -> int:
	var x := floori(p.x)
	var y := floori(p.y)
	if x < 0 or y < 0 or x >= W or y >= H:
		return F_GROUND
	return flo[y * W + x]


static func _cdist2(p: Vector2, x: int, y: int) -> float:
	var cx := clampf(p.x, x, x + 1.0)
	var cy := clampf(p.y, y, y + 1.0)
	return (p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy)


## `pass_cells` lists door cells this mover may walk through (its team has access).
## `foot` < 0: every block is solid (vehicles, guards). `foot` >= 0: a walker with its feet at that
## height - low blocks it can step onto are not solid, and it needs head room under roofs and lintels.
func circle_blocked(p: Vector2, r: float, pass_cells := {}, foot := -1.0) -> bool:
	for y in range(floori(p.y - r), floori(p.y + r) + 1):
		for x in range(floori(p.x - r), floori(p.x + r) + 1):
			var inside := x >= 0 and y >= 0 and x < W and y < H
			var i := y * W + x
			if not inside or (wall[i] != 0 and not (pass_cells.size() > 0 and pass_cells.has(Vector2i(x, y)))):
				if foot < 0.0 or not inside or hgt[i] > foot + STEP:
					if _cdist2(p, x, y) < r * r:
						return true
			elif obst[i] != 0 and foot < 1.0:
				var dx := p.x - (x + 0.5)
				var dy := p.y - (y + 0.5)
				if dx * dx + dy * dy < (r + 0.28) * (r + 0.28):
					return true
			if foot >= 0.0 and inside and roof[i] != 0 and foot + HEAD > CEIL + 0.02 and foot < rtop[i] - STEP:
				if _cdist2(p, x, y) < r * r:
					return true
	return false


## Small flying object (grenade) at height z: does it touch a block, a tree, a roof slab or a lintel?
func sphere_blocked(p: Vector2, r: float, z: float, pass_cells := {}) -> bool:
	for y in range(floori(p.y - r), floori(p.y + r) + 1):
		for x in range(floori(p.x - r), floori(p.x + r) + 1):
			if _cdist2(p, x, y) >= r * r:
				continue
			if x < 0 or y < 0 or x >= W or y >= H:
				return true
			var i := y * W + x
			if wall[i] != 0 and hgt[i] > z and not (pass_cells.size() > 0 and pass_cells.has(Vector2i(x, y))):
				return true
			if roof[i] != 0 and z > CEIL - 0.02 and z < rtop[i]:
				return true
			if obst[i] != 0 and z < 1.2:
				var dx := p.x - (x + 0.5)
				var dy := p.y - (y + 0.5)
				if dx * dx + dy * dy < (r + 0.25) * (r + 0.25):
					return true
	return false


## Highest surface a walker with feet at `foot` stands on (block tops and roofs it can reach).
func ground_at(p: Vector2, r: float, foot: float, pass_cells := {}) -> float:
	var g := 0.0
	var rr := r * 0.7
	for y in range(floori(p.y - rr), floori(p.y + rr) + 1):
		for x in range(floori(p.x - rr), floori(p.x + rr) + 1):
			if x < 0 or y < 0 or x >= W or y >= H or _cdist2(p, x, y) >= rr * rr:
				continue
			var i := y * W + x
			if wall[i] != 0 and not (pass_cells.size() > 0 and pass_cells.has(Vector2i(x, y))):
				if hgt[i] <= foot + STEP:
					g = maxf(g, hgt[i])
			if roof[i] != 0 and foot >= rtop[i] - STEP:
				g = maxf(g, rtop[i])
	return g


## Is there a ceiling right above this walker (it can't jump higher than this)?
func ceiling_at(p: Vector2, r: float, foot: float) -> float:
	var c := 99.0
	for y in range(floori(p.y - r), floori(p.y + r) + 1):
		for x in range(floori(p.x - r), floori(p.x + r) + 1):
			if x < 0 or y < 0 or x >= W or y >= H or _cdist2(p, x, y) >= r * r:
				continue
			var i := y * W + x
			if roof[i] != 0 and foot < CEIL:
				c = minf(c, CEIL)
	return c


func move_circle(p: Vector2, delta: Vector2, r: float, pass_cells := {}, foot := -1.0) -> Vector2:
	var np := p
	var tx := Vector2(p.x + delta.x, p.y)
	if not circle_blocked(tx, r, pass_cells, foot):
		np = tx
	var ty := Vector2(np.x, np.y + delta.y)
	if not circle_blocked(ty, r, pass_cells, foot):
		np = ty
	return np


## 3D ray through the height field: from (o, oz) along horizontal unit vector `d`, rising `slope`
## per unit. Hits block faces/tops, the ground, roof slabs and ceilings. Returns {hit, dist, cell, wall, z}.
func ray3(o: Vector2, oz: float, d: Vector2, slope: float, maxd: float, pass_cells := {}) -> Dictionary:
	var mx := floori(o.x)
	var my := floori(o.y)
	var ddx := 1e30 if absf(d.x) < 1e-9 else absf(1.0 / d.x)
	var ddy := 1e30 if absf(d.y) < 1e-9 else absf(1.0 / d.y)
	var sx := 1
	var sy := 1
	var sdx := 0.0
	var sdy := 0.0
	if d.x < 0.0:
		sx = -1
		sdx = (o.x - mx) * ddx
	else:
		sdx = (mx + 1.0 - o.x) * ddx
	if d.y < 0.0:
		sy = -1
		sdy = (o.y - my) * ddy
	else:
		sdy = (my + 1.0 - o.y) * ddy
	var t_in := 0.0
	for it in 512:
		var t_out := minf(minf(sdx, sdy), maxd)
		var z_in := oz + slope * t_in
		var z_out := oz + slope * t_out
		var hit_t := -1.0
		var is_wall := false
		if mx < 0 or my < 0 or mx >= W or my >= H:
			hit_t = t_in
			is_wall = true
		else:
			var i := my * W + mx
			var solid := wall[i] != 0 and not (pass_cells.size() > 0 and pass_cells.has(Vector2i(mx, my)))
			var h := hgt[i] if solid else 0.0
			if solid and t_in > 0.0 and z_in < h:
				hit_t = t_in
				is_wall = true
			elif z_out < h:
				hit_t = (h - oz) / slope if slope < -1e-6 else t_in
				is_wall = solid
			elif roof[i] != 0:
				var rt := rtop[i]
				if t_in > 0.0 and z_in > CEIL and z_in < rt:
					hit_t = t_in
				elif z_in >= rt and z_out < rt:
					hit_t = (rt - oz) / slope
				elif z_in <= CEIL and z_out > CEIL:
					hit_t = (CEIL - oz) / slope
		if hit_t >= 0.0:
			return {"hit": true, "dist": hit_t, "cell": Vector2i(mx, my), "wall": is_wall, "z": oz + slope * hit_t}
		if t_out >= maxd:
			break
		if sdx < sdy:
			t_in = sdx
			sdx += ddx
			mx += sx
		else:
			t_in = sdy
			sdy += ddy
			my += sy
	return {"hit": false, "dist": maxd, "cell": Vector2i(-1, -1), "wall": false, "z": oz + slope * maxd}


## Line of sight between two points at given heights (sees over low cover, through windows).
func los3(a: Vector2, za: float, b: Vector2, zb: float, pass_cells := {}) -> bool:
	var dv := b - a
	var L := dv.length()
	if L < 0.01:
		return true
	return not ray3(a, za, dv / L, (zb - za) / L, L, pass_cells).hit


## Grid DDA. Returns {hit, dist, cell}.
func ray_wall(o: Vector2, d: Vector2, maxd: float, pass_cells := {}) -> Dictionary:
	var mx := floori(o.x)
	var my := floori(o.y)
	var ddx := 1e30 if absf(d.x) < 1e-9 else absf(1.0 / d.x)
	var ddy := 1e30 if absf(d.y) < 1e-9 else absf(1.0 / d.y)
	var sx := 1
	var sy := 1
	var sdx := 0.0
	var sdy := 0.0
	if d.x < 0.0:
		sx = -1
		sdx = (o.x - mx) * ddx
	else:
		sdx = (mx + 1.0 - o.x) * ddx
	if d.y < 0.0:
		sy = -1
		sdy = (o.y - my) * ddy
	else:
		sdy = (my + 1.0 - o.y) * ddy
	var dist := 0.0
	while dist < maxd:
		if sdx < sdy:
			dist = sdx
			sdx += ddx
			mx += sx
		else:
			dist = sdy
			sdy += ddy
			my += sy
		if dist > maxd:
			break
		if get_wall(mx, my) != 0 and not (pass_cells.size() > 0 and pass_cells.has(Vector2i(mx, my))):
			return {"hit": true, "dist": dist, "cell": Vector2i(mx, my)}
	return {"hit": false, "dist": maxd, "cell": Vector2i(-1, -1)}


func los(a: Vector2, b: Vector2, pass_cells := {}) -> bool:
	var d := b - a
	var L := d.length()
	if L < 0.01:
		return true
	return not ray_wall(a, d / L, L, pass_cells).hit


func bunker_at(p: Vector2) -> int:
	for i in bunkers.size():
		var b: Dictionary = bunkers[i]
		if p.x >= b.bx - 1 and p.x <= b.bx + 25 and p.y >= b.by - 1 and p.y <= b.by + 25:
			return i
	return -1


# ---------------------------------------------------------------- textures

const TILE_H := [1.0, 1.0, 0.9, 1.0, 0.95, 1.9, 2.0, 1.45, 1.45, 0.55, 0.75, 1.25, 1.0, 0.6, 0.3, 0.85, 1.0]
const SHADER_COLORS := ["ground_a", "ground_b", "dirt_a", "dirt_b", "sky_top", "sky_hor", "fog_col", "mount_col", "rock_tint"]


## Sets every map-dependent raycast shader parameter (except the map texture itself).
func apply_shader(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("map_size", Vector2(W, H))
	var th: Array = THEMES[palette]
	for k in SHADER_COLORS.size():
		var c: Color = th[k]
		mat.set_shader_parameter(SHADER_COLORS[k], Vector3(c.r, c.g, c.b))
	mat.set_shader_parameter("fog_dist", th[9])
	mat.set_shader_parameter("tile_h", PackedFloat32Array(TILE_H))
	mat.set_shader_parameter("wall_tiles", float(WALL_TYPES))
	mat.set_shader_parameter("weather", theme)
	mat.set_shader_parameter("snow_tops", 1.0 if theme == 2 else 0.0)


## Packs the map for the shader: r = wall id, g = roof top (0 = open), b = floor, a = block height.
func pack_image() -> Image:
	var n := W * H
	var data := PackedByteArray()
	data.resize(n * 4)
	for i in n:
		data[i * 4] = wall[i]
		data[i * 4 + 1] = clampi(int(round(rtop[i] * HSCALE)), 1, 255) if roof[i] != 0 else 0
		data[i * 4 + 2] = flo[i]
		data[i * 4 + 3] = clampi(int(round(hgt[i] * HSCALE)), 0, 255) if wall[i] != 0 else 0
	return Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, data)


# ---------------------------------------------------------------- generation

## p_bunkers: only HEIST uses the bunkers (keys, puzzle rooms, vaults); other modes get open terrain there.
func generate(p_map: int, seed_val: int, p_rooms := 2, p_bunkers := true) -> void:
	map_index = clampi(p_map, 0, MAPS.size() - 1)
	rooms = 4 if p_rooms >= 4 else 2
	with_bunkers = p_bunkers
	camp_ammo.clear()
	var info: Dictionary = MAPS[map_index]
	W = int(info.size)
	H = W
	theme = int(info.theme)
	palette = int(info.get("palette", theme))
	layout = str(info.get("layout", "cross"))
	bunker_names = LAYOUT_NAMES[layout]
	var n := W * H
	wall.resize(n)
	wall.fill(0)
	flo.resize(n)
	flo.fill(F_GROUND)
	roof.resize(n)
	roof.fill(0)
	obst.resize(n)
	obst.fill(0)
	hgt.resize(n)
	hgt.fill(0.0)
	rtop.resize(n)
	rtop.fill(0.0)
	decor.clear()
	emitters.clear()
	lamps.clear()
	soldier_spawns.clear()
	turret_spawns.clear()
	bunkers.clear()
	gates.clear()
	_zones.clear()
	rng.seed = seed_val + map_index * 7919

	var cx := W / 2
	var cy := H / 2
	# roads: a ring road linking the four bunkers and the camps, plus the two main crossings
	for i in range(W):
		for k in range(-1, 2):
			flo[(cy + k) * W + i] = F_DIRT
			flo[i * W + (cx + k)] = F_DIRT
	for i in range(W):
		_blk(i, 0, ROCK, 3.5)
		_blk(i, H - 1, ROCK, 3.5)
		_blk(0, i, ROCK, 3.5)
		_blk(W - 1, i, ROCK, 3.5)

	var origins: Array = _layout(cx, cy)
	for ti in 4:
		var s: Vector3 = team_spawns[ti]
		for y in range(int(s.y) - 4, int(s.y) + 5):
			for x in range(int(s.x) - 4, int(s.x) + 5):
				flo[y * W + x] = F_CONCRETE
		camp_ammo.append(Vector2(s.x + 3.5, s.y - 3.5))   # resupply crate (drawn as an ammo crate entity)
		_add_decor(Vector2(s.x - 3.5, s.y + 3.5), Defs.FR_BARREL, 0.65, false)
		_add_lamp(Vector2(s.x - 4.3, s.y - 4.3))
		_add_lamp(Vector2(s.x + 4.3, s.y + 4.3))
		_camp_tower(ti)

	if with_bunkers:
		for i in 4:
			var o: Vector2i = origins[i]
			_zones.append(Rect2i(o.x - 7, o.y - 7, 38, 38))
			_build_bunker(o.x, o.y, i)
	for s in team_spawns:
		_zones.append(Rect2i(int(s.x) - 9, int(s.y) - 9, 19, 19))

	var area_k: float = float(W * H) / (96.0 * 96.0)
	var rock_mult := 1.0
	match str(info.style):
		"valley":
			for i in int(3 * area_k):
				_pond()
			_scatter_rocks(int(110 * area_k), 3, 0.75)
			for i in int(6 * area_k):
				_hedge_line()
			for i in int(2 * area_k):
				_ruin()
			for i in int(2 * area_k):
				_field_tower()
			for i in int(4 * area_k):
				_nest()
			for i in int(3 * area_k):
				_crate_pile()
			for i in int(3 * area_k):
				_fence_line()
			_scatter_decor(Defs.FR_TREE, int(150 * area_k), true, 1.6)
			_scatter_decor(Defs.FR_BUSH, int(150 * area_k), false, 0.7)
			_scatter_decor(Defs.FR_GRASS, int(220 * area_k), false, 0.4)
			_scatter_decor(Defs.FR_FLOWERS, int(90 * area_k), false, 0.35)
			_scatter_decor(Defs.FR_DEADTREE, int(20 * area_k), true, 1.5)
		"desert":
			rock_mult = 1.2
			for i in int(4 * area_k):
				_mesa()
			_scatter_rocks(int(55 * area_k), 5, 1.0)
			for i in int(3 * area_k):
				_adobe()
			for i in int(3 * area_k):
				_container_yard()
			for i in int(2 * area_k):
				_field_tower()
			for i in int(5 * area_k):
				_nest()
			_scatter_decor(Defs.FR_CACTUS, int(70 * area_k), true, 1.1)
			_scatter_decor(Defs.FR_DRYBUSH, int(110 * area_k), false, 0.6)
			_scatter_decor(Defs.FR_CARWRECK, int(18 * area_k), true, 1.2)
			_scatter_decor(Defs.FR_BARREL, int(30 * area_k), true, 0.65)
			_scatter_decor(Defs.FR_FIRE, int(8 * area_k), true, 0.55)
		"snow":
			rock_mult = 1.1
			_ridges(int(38 * area_k))
			for i in int(3 * area_k):
				_cabin()
			for i in int(2 * area_k):
				_field_tower()
			for i in int(4 * area_k):
				_nest()
			for i in int(3 * area_k):
				_fence_line()
			for i in int(2 * area_k):
				_pond()
			_scatter_decor(Defs.FR_PINE, int(270 * area_k), true, 1.8)
			_scatter_decor(Defs.FR_SNOWBUSH, int(100 * area_k), false, 0.6)
			_scatter_decor(Defs.FR_FIRE, int(5 * area_k), true, 0.55)
		"town":
			_town()
			for i in int(3 * area_k):
				_barricade()
			for i in int(2 * area_k):
				_container_yard()
			_scatter_decor(Defs.FR_RUBBLE, int(110 * area_k), false, 0.6)
			_scatter_decor(Defs.FR_CARWRECK, int(26 * area_k), true, 1.2)
			_scatter_decor(Defs.FR_BARREL, int(40 * area_k), true, 0.65)
			_scatter_decor(Defs.FR_CRATE, int(30 * area_k), true, 0.7)
			_scatter_decor(Defs.FR_FIRE, int(14 * area_k), true, 0.55)
		"canyon":
			rock_mult = 1.35
			for i in int(5 * area_k):
				_canyon_wall()
			for i in int(3 * area_k):
				_mesa()
			_scatter_rocks(int(40 * area_k), 3, 1.0)
			for i in int(2 * area_k):
				_adobe()
			for i in int(2 * area_k):
				_field_tower()
			for i in int(4 * area_k):
				_nest()
			_scatter_decor(Defs.FR_CACTUS, int(35 * area_k), true, 1.1)
			_scatter_decor(Defs.FR_DRYBUSH, int(120 * area_k), false, 0.6)
			_scatter_decor(Defs.FR_DEADTREE, int(15 * area_k), true, 1.4)
			_scatter_decor(Defs.FR_CARWRECK, int(10 * area_k), true, 1.2)
			_scatter_decor(Defs.FR_FIRE, int(6 * area_k), true, 0.55)
		"harbor":
			_harbor_canals()
			for i in int(6 * area_k):
				_container_yard()
			for i in int(4 * area_k):
				_warehouse()
			for i in int(5 * area_k):
				_crane()
			for i in int(3 * area_k):
				_crate_pile()
			for i in int(3 * area_k):
				_barricade()
			for y in range(H):
				for x in range(W):
					if flo[y * W + x] == F_GROUND and _rh(x / 5, y / 5, 31) < 0.8:
						flo[y * W + x] = F_CONCRETE
			_scatter_decor(Defs.FR_BARREL, int(45 * area_k), true, 0.65)
			_scatter_decor(Defs.FR_CRATE, int(40 * area_k), true, 0.7)
			_scatter_decor(Defs.FR_CARWRECK, int(10 * area_k), true, 1.2)
			_scatter_decor(Defs.FR_FIRE, int(8 * area_k), true, 0.55)
		"marsh":
			for i in int(9 * area_k):
				_pond(3.5, 7.0)
			for i in int(8 * area_k):
				_hedge_line()
			for i in int(4 * area_k):
				_fence_line()
			for i in int(3 * area_k):
				_cabin()
			for i in int(2 * area_k):
				_ruin()
			for i in int(2 * area_k):
				_field_tower()
			for i in int(3 * area_k):
				_nest()
			_scatter_rocks(int(30 * area_k), 2, 0.6)
			_scatter_decor(Defs.FR_DEADTREE, int(60 * area_k), true, 1.5)
			_scatter_decor(Defs.FR_TREE, int(50 * area_k), true, 1.5)
			_scatter_decor(Defs.FR_REEDS, int(200 * area_k), false, 0.6)
			_scatter_decor(Defs.FR_BUSH, int(120 * area_k), false, 0.7)
			_scatter_decor(Defs.FR_GRASS, int(160 * area_k), false, 0.45)
		"coast":
			_shoreline()
			for i in int(3 * area_k):
				_dune_ridge()
			_scatter_rocks(int(45 * area_k), 3, 0.85)
			for i in int(3 * area_k):
				_adobe()
			for i in int(3 * area_k):
				_field_tower()
			for i in int(6 * area_k):
				_nest()
			for i in int(3 * area_k):
				_fence_line()
			_scatter_decor(Defs.FR_TREE, int(50 * area_k), true, 1.6)
			_scatter_decor(Defs.FR_BUSH, int(90 * area_k), false, 0.7)
			_scatter_decor(Defs.FR_GRASS, int(160 * area_k), false, 0.45)
			_scatter_decor(Defs.FR_DRYBUSH, int(60 * area_k), false, 0.6)
			_scatter_decor(Defs.FR_CARWRECK, int(8 * area_k), true, 1.2)
			_scatter_decor(Defs.FR_FIRE, int(8 * area_k), true, 0.55)
	_finalize_heights(rock_mult)
	_ensure_paths()
	_mortar_pits()
	# props that make the map feel alive: burning wrecks, fires
	for d in decor:
		if int(d[2]) == Defs.FR_FIRE:
			emitters.append([d[0], d[1], 0.5, 1])
		elif int(d[2]) == Defs.FR_CARWRECK and _rh(floori(d[0]), floori(d[1]), 77) < 0.45:
			emitters.append([d[0], d[1], 0.55, 0])


func _blk(x: int, y: int, id: int, h: float) -> void:
	if x < 0 or y < 0 or x >= W or y >= H:
		return
	wall[y * W + x] = id
	hgt[y * W + x] = h


func _set_roof(x: int, y: int, top: float) -> void:
	if x < 0 or y < 0 or x >= W or y >= H:
		return
	roof[y * W + x] = 1
	rtop[y * W + x] = top


func _rh(x: int, y: int, s: int) -> float:
	var v := (x * 374761393 + y * 668265263 + s * 1442695041 + map_index * 97) & 0x7fffffff
	v = ((v ^ (v >> 13)) * 1274126177) & 0x7fffffff
	v = v ^ (v >> 16)
	return float(v & 0xffff) / 65535.0


func _finalize_heights(rock_mult: float) -> void:
	for y in H:
		for x in W:
			var i := y * W + x
			if wall[i] != 0 and hgt[i] <= 0.0:
				if wall[i] == ROCK:
					var c := 0
					for dy in range(-2, 3):
						for dx in range(-2, 3):
							if get_wall(x + dx, y + dy) == ROCK:
								c += 1
					hgt[i] = minf(3.4, (0.55 + c * 0.1 + _rh(x, y, 5) * 0.55) * rock_mult)
				else:
					hgt[i] = DEF_H[wall[i]]
			if roof[i] != 0 and rtop[i] <= 0.0:
				rtop[i] = 1.3


func _build_bunker(bx: int, by: int, idx: int) -> void:
	var o := Vector2(bx, by)
	for y in range(by, by + 24):
		for x in range(bx, bx + 24):
			flo[y * W + x] = F_CONCRETE
			if x == bx or x == bx + 23 or y == by or y == by + 23:
				var corner := (x == bx or x == bx + 23) and (y == by or y == by + 23)
				_blk(x, y, COMPOUND, 2.5 if corner else 2.0)
	var gate_cells := [[], [], [], []]
	for k in range(10, 13):
		gate_cells[0].append(Vector2i(bx + k, by))
		gate_cells[1].append(Vector2i(bx + k, by + 23))
		gate_cells[2].append(Vector2i(bx, by + k))
		gate_cells[3].append(Vector2i(bx + 23, by + k))
	var approach := [o + Vector2(11.5, -4.5), o + Vector2(11.5, 27.5), o + Vector2(-4.5, 11.5), o + Vector2(27.5, 11.5)]
	var center := [o + Vector2(11.5, 0.5), o + Vector2(11.5, 23.5), o + Vector2(0.5, 11.5), o + Vector2(23.5, 11.5)]
	for g in 4:
		var ap: Vector2 = approach[g]
		if ap.x < 3 or ap.y < 3 or ap.x > W - 4 or ap.y > H - 4:
			continue   # gate would face the map edge
		for c in gate_cells[g]:
			_blk(c.x, c.y, GATE, 2.0)
		# gate posts stand taller than the wall
		var c0: Vector2i = gate_cells[g][0]
		var c2: Vector2i = gate_cells[g][2]
		var dv: Vector2i = c2 - c0
		var st := Vector2i(signi(dv.x), signi(dv.y))
		_blk(c0.x - st.x, c0.y - st.y, COMPOUND, 2.6)
		_blk(c2.x + st.x, c2.y + st.y, COMPOUND, 2.6)
		gates.append({"cells": gate_cells[g], "approach": ap, "center": center[g], "bunker": idx})
		# a short apron in front of every gate
		for y in range(int(ap.y) - 2, int(ap.y) + 3):
			for x in range(int(ap.x) - 2, int(ap.x) + 3):
				if x > 0 and y > 0 and x < W - 1 and y < H - 1:
					flo[y * W + x] = F_DIRT

	_hut(bx + 1, by + 1, Vector2i(bx + 5, by + 3))
	_hut(bx + 18, by + 1, Vector2i(bx + 18, by + 3))
	_hut(bx + 18, by + 18, Vector2i(bx + 18, by + 20))
	_hut(bx + 1, by + 18, Vector2i(bx + 5, by + 20))
	# puzzle rooms: corner huts behind key doors (2 per bunker, or all 4 in 4-per-team matches)
	var room_doors := [Vector2i(bx + 5, by + 3), Vector2i(bx + 18, by + 20), Vector2i(bx + 18, by + 3), Vector2i(bx + 5, by + 20)]
	var room_terms := [o + Vector2(2.5, 3.5), o + Vector2(21.5, 20.5), o + Vector2(21.5, 3.5), o + Vector2(2.5, 20.5)]
	var room_out := [o + Vector2(6.5, 3.5), o + Vector2(17.5, 20.5), o + Vector2(17.5, 3.5), o + Vector2(6.5, 20.5)]
	for r in rooms:
		var dc: Vector2i = room_doors[r]
		_blk(dc.x, dc.y, KEYDOOR, 1.45)
	var b := {"idx": idx, "bx": bx, "by": by,
		"terminals": room_terms.slice(0, rooms),
		"ammo": o + Vector2(21.5, 3.5) if rooms <= 2 else o + Vector2(13.5, 2.5),
		"reinforce": o + Vector2(3.5, 20.5) if rooms <= 2 else o + Vector2(11.5, 21.5),
		"vault_center": Vector2.ZERO, "vault_cells": [], "guards": [],
		"center": o + Vector2(12.0, 12.0)}
	for p in [Vector2(3.5, 2.5), Vector2(20.5, 21.5), Vector2(2.5, 19.5), Vector2(3.5, 8.5), Vector2(20.5, 15.5), Vector2(8.5, 20.5), Vector2(15.5, 3.5)]:
		soldier_spawns.append(o + p)
	# the two outer turrets cover the approaches from the map centre
	var toward_s := by + 12 < H / 2
	var toward_e := bx + 12 < W / 2
	turret_spawns.append(o + (Vector2(7.5, 27.5) if toward_s else Vector2(7.5, -3.5)))
	turret_spawns.append(o + (Vector2(27.5, 16.5) if toward_e else Vector2(-3.5, 16.5)))
	for t in turret_spawns.slice(turret_spawns.size() - 2):
		for dx in range(-1, 2):
			_add_decor(Vector2(t.x + dx * 0.7, t.y + 0.9), Defs.FR_SANDBAG, 0.6, false)
	# low sandbag cover inside the yard
	for p in [Vector2i(8, 4), Vector2i(15, 19)]:
		for k in 3:
			_blk(bx + p.x + k, by + p.y, SANDBAG, 0.55)
	# owner's flag over the vault
	var flag_team: int = maxi(0, team_bunker.find(idx))
	var door_cell := Vector2i.ZERO
	for r in range(12):
		var line: String = BUILDING[r]
		for c in range(12):
			var x := bx + 6 + c
			var y := by + 6 + r
			var ch := line[c]
			flo[y * W + x] = F_METAL
			if ch == "#" and (r == 0 or r == 11) and (c == 0 or c == 11):
				# notched corners: the yard around the vault is one connected ring, so every gate
				# reaches every key door and the vault door (the corner huts touch these corners)
				flo[y * W + x] = F_CONCRETE
				continue
			if ch == "#":
				var outer := r == 0 or r == 11 or c == 0 or c == 11
				_blk(x, y, TECH, 2.2 if outer else 1.9)
				continue
			_set_roof(x, y, 1.9)
			if ch != "M":
				b.vault_cells.append(Vector2(x + 0.5, y + 0.5))
			if ch == "g":
				soldier_spawns.append(Vector2(x + 0.5, y + 0.5))
				b.guards.append(Vector2(x + 0.5, y + 0.5))
			elif ch == "R":
				b.vault_center = Vector2(x + 0.5, y + 0.5)
			elif ch == "M":
				door_cell = Vector2i(x, y)
				_blk(x, y, DOOR, 1.9)
				_set_roof(x, y, 2.2)
	decor.append([bx + 12.0, by + 12.0, Defs.FR_FLAG + flag_team * 2, 1.0, 1.9])
	emitters.append([bx + 7.5, by + 7.5, 2.2, 0])
	# lamps beside the four gates, lighting the approach
	for lp in [Vector2(14.3, -1.5), Vector2(9.7, 25.5), Vector2(-1.5, 9.7), Vector2(25.5, 14.3)]:
		var q: Vector2 = o + lp
		if q.x > 3.0 and q.y > 3.0 and q.x < W - 4.0 and q.y < H - 4.0 and wall[floori(q.y) * W + floori(q.x)] == 0:
			_add_lamp(q)
	# doors[0 .. rooms-1] = puzzle rooms, doors[rooms] = the vault
	b["doors"] = room_doors.slice(0, rooms) + [door_cell]
	b["door_outside"] = room_out.slice(0, rooms) + [Vector2(door_cell.x + 0.5, door_cell.y + 1.5)]
	bunkers.append(b)


func _hut(x0: int, y0: int, door: Vector2i) -> void:
	for y in range(y0, y0 + 5):
		for x in range(x0, x0 + 5):
			flo[y * W + x] = F_METAL
			if x == x0 or y == y0 or x == x0 + 4 or y == y0 + 4:
				_blk(x, y, HUT, 1.45)
			else:
				_set_roof(x, y, 1.3)
	set_wall(door.x, door.y, 0)
	_set_roof(door.x, door.y, 1.45)


## A wooden watchtower: 4x4 platform at 1.8 with corner posts and a staircase.
func _tower_at(px: int, py: int, sdir: Vector2i, flag: int) -> void:
	for y in range(py, py + 4):
		for x in range(px, px + 4):
			var corner := (x == px or x == px + 3) and (y == py or y == py + 3)
			_blk(x, y, PLANKS, 2.4 if corner else 1.8)
	var start := Vector2i(px + 4, py + 1) if sdir.x > 0 else (Vector2i(px - 1, py + 1) if sdir.x < 0 else (Vector2i(px + 1, py + 4) if sdir.y > 0 else Vector2i(px + 1, py - 1)))
	for k in 5:
		var c := start + sdir * k
		_blk(c.x, c.y, STEEL, 1.5 - 0.3 * k)
	if flag >= 0:
		decor.append([px + 2.0, py + 2.0, Defs.FR_FLAG + flag * 2, 1.0, 1.8])


## Where the 4 base camps (team_spawns, team order 0..3) and the 4 bunkers (returned origins) sit,
## and which bunker each team owns. Every layout keeps all four sides of the fight symmetrical.
func _layout(cx: int, cy: int) -> Array:
	var m := 8.5
	var corners := [Vector3(m, m, PI * 0.25), Vector3(W - m, H - m, -PI * 0.75), Vector3(W - m, m, PI * 0.75), Vector3(m, H - m, -PI * 0.25)]
	var e := 12
	match layout:
		"diamond":
			# camps in the middle of each side, bunkers in the corners; each team owns the bunker clockwise of it
			team_spawns = [Vector3(cx + 0.5, m, PI * 0.5), Vector3(cx + 0.5, H - m, -PI * 0.5), Vector3(W - m, cy + 0.5, PI), Vector3(m, cy + 0.5, 0.0)]
			e = 15
			team_bunker = [1, 3, 2, 0]
			return [Vector2i(e, e), Vector2i(W - e - 24, e), Vector2i(W - e - 24, H - e - 24), Vector2i(e, H - e - 24)]
		"inner":
			# camps in the corners, the four bunkers packed around the central crossroads
			team_spawns = corners
			var d := 22
			team_bunker = [0, 2, 1, 3]
			return [Vector2i(cx - 12 - d, cy - 12 - d), Vector2i(cx - 12 + d, cy - 12 - d), Vector2i(cx - 12 + d, cy - 12 + d), Vector2i(cx - 12 - d, cy - 12 + d)]
		"pinwheel":
			# bunkers on the sides but slid along them, each one close to "its" camp
			team_spawns = corners
			var sh := 22
			team_bunker = [2, 3, 0, 1]
			return [Vector2i(cx - 12 + sh, e), Vector2i(cx - 12 - sh, H - e - 24), Vector2i(e, cy - 12 - sh), Vector2i(W - e - 24, cy - 12 + sh)]
	team_spawns = corners
	team_bunker = [0, 1, 3, 2]
	return [Vector2i(cx - 12, e), Vector2i(cx - 12, H - e - 24), Vector2i(e, cy - 12), Vector2i(W - e - 24, cy - 12)]


func _camp_tower(ti: int) -> void:
	var s: Vector3 = team_spawns[ti]
	var left := s.x < W * 0.5
	var top := s.y < H * 0.5
	var corner := (s.x < W * 0.25 or s.x > W * 0.75) and (s.y < H * 0.25 or s.y > H * 0.75)
	if corner:
		_tower_at(1 if left else W - 5, 1 if top else H - 5, Vector2i(1 if left else -1, 0), ti)
	elif s.y < H * 0.25 or s.y > H * 0.75:
		# camp in the middle of the top/bottom edge: tower beside it against the edge, stairs towards the camp
		_tower_at(int(s.x) + 6, 1 if top else H - 5, Vector2i(-1, 0), ti)
	else:
		_tower_at(1 if left else W - 5, int(s.y) + 6, Vector2i(0, -1), ti)


## Every base camp gets a mortar pit beside it: a 5x5 ring of sandbags, open towards the camp,
## with the mortar in the middle (only that team can use it - see world.gd).
func _mortar_pits() -> void:
	mortars.clear()
	for ti in team_spawns.size():
		var s: Vector3 = team_spawns[ti]
		var dv := Vector2.from_angle(s.z - PI * 0.25)
		var d := Vector2i(roundi(dv.x), roundi(dv.y))
		var c := Vector2i(floori(s.x + d.x * 6.5), floori(s.y + d.y * 6.5))
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var x := c.x + dx
				var y := c.y + dy
				if x < 1 or y < 1 or x >= W - 1 or y >= H - 1:
					continue
				var i := y * W + x
				flo[i] = F_DIRT
				roof[i] = 0
				obst[i] = 0
				wall[i] = 0
				hgt[i] = 0.0
				if maxi(absi(dx), absi(dy)) != 2:
					continue
				var along := -(dx * d.x + dy * d.y)
				var side := absi(dx * d.y - dy * d.x)
				if along == 2 and side <= 1:
					continue   # the way in, facing the camp
				_blk(x, y, SANDBAG, 0.55)
		var keep: Array = []
		for dd in decor:
			if absf(float(dd[0]) - (c.x + 0.5)) < 3.0 and absf(float(dd[1]) - (c.y + 0.5)) < 3.0:
				continue
			keep.append(dd)
		decor = keep
		var mp := Vector2(c.x + 0.5, c.y + 0.5)
		_add_decor(mp, Defs.FR_MORTAR, 0.8, true)
		mortars.append(mp)


func _rect_free(x0: int, y0: int, w: int, h: int) -> bool:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			if not _free(x, y):
				return false
	return true


func _field_tower() -> void:
	for tries in 40:
		var px := rng.randi_range(6, W - 10)
		var py := rng.randi_range(6, H - 10)
		var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		var sdir: Vector2i = dirs[rng.randi() % 4]
		var x0 := px - 1 + mini(0, sdir.x * 6)
		var y0 := py - 1 + mini(0, sdir.y * 6)
		var w := 6 + absi(sdir.x) * 6
		var h := 6 + absi(sdir.y) * 6
		if _rect_free(x0, y0, w, h):
			_tower_at(px, py, sdir, 4)
			return


func _nest() -> void:
	for tries in 30:
		var cx := rng.randi_range(4, W - 5)
		var cy := rng.randi_range(4, H - 5)
		if not _rect_free(cx - 3, cy - 3, 7, 7):
			continue
		var open := rng.randi() % 4
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if maxi(absi(dx), absi(dy)) != 2:
					continue
				var side := 0 if dy == -2 else (1 if dx == 2 else (2 if dy == 2 else 3))
				if side == open and absi(dx) < 2 or side == open and absi(dy) < 2:
					continue
				_blk(cx + dx, cy + dy, SANDBAG, 0.55)
		_add_decor(Vector2(cx + 0.5, cy + 0.5), Defs.FR_CRATE if rng.randf() < 0.5 else Defs.FR_BARREL, 0.6, false)
		return


func _crate_pile() -> void:
	for tries in 30:
		var cx := rng.randi_range(4, W - 5)
		var cy := rng.randi_range(4, H - 5)
		if not _rect_free(cx - 2, cy - 2, 5, 4):
			continue
		for k in rng.randi_range(3, 5):
			var x := cx + rng.randi_range(-1, 1)
			var y := cy + rng.randi_range(-1, 0)
			_blk(x, y, CRATE, 1.5 if rng.randf() < 0.3 else 0.75)
		return


func _container_yard() -> void:
	for tries in 40:
		var cx := rng.randi_range(6, W - 12)
		var cy := rng.randi_range(6, H - 12)
		if not _rect_free(cx - 1, cy - 1, 10, 9):
			continue
		for k in 3:
			var horiz := rng.randf() < 0.5
			var x0 := cx + (0 if horiz else k * 3)
			var y0 := cy + (k * 3 if horiz else 0)
			var w := 5 if horiz else 2
			var h := 2 if horiz else 5
			var tall := 2.5 if rng.randf() < 0.3 else 1.25
			for y in range(y0, y0 + h):
				for x in range(x0, x0 + w):
					if x < cx + 8 and y < cy + 7:
						_blk(x, y, CONTAINER, tall)
			# a crate to climb up onto it
			var step := Vector2i(x0 + w, y0) if horiz else Vector2i(x0, y0 + h)
			if step.x < cx + 8 and step.y < cy + 7 and tall < 2.0:
				_blk(step.x, step.y, CRATE, 0.75)
		return


func _hedge_line() -> void:
	for tries in 20:
		var x := rng.randi_range(4, W - 5)
		var y := rng.randi_range(4, H - 5)
		var d := Vector2i(1, 0) if rng.randf() < 0.5 else Vector2i(0, 1)
		var L := rng.randi_range(5, 11)
		var ok := true
		for k in L:
			if not _free(x + d.x * k, y + d.y * k):
				ok = false
				break
		if not ok:
			continue
		for k in L:
			if k % 6 != 3:
				_blk(x + d.x * k, y + d.y * k, HEDGE, 0.85)
		return


func _fence_line() -> void:
	for tries in 20:
		var x := rng.randi_range(4, W - 5)
		var y := rng.randi_range(4, H - 5)
		var d := Vector2i(1, 0) if rng.randf() < 0.5 else Vector2i(0, 1)
		var L := rng.randi_range(6, 14)
		var ok := true
		for k in L:
			if not _free(x + d.x * k, y + d.y * k):
				ok = false
				break
		if not ok:
			continue
		for k in L:
			if k % 5 != 2:
				_blk(x + d.x * k, y + d.y * k, PLANKS, 0.6)
		return


func _pond(rmin := 2.2, rmax := 4.2) -> void:
	for tries in 20:
		var cx := rng.randi_range(8, W - 9)
		var cy := rng.randi_range(8, H - 9)
		var r := rng.randf_range(rmin, rmax)
		if not _field_ok(cx, cy):
			continue
		var ext := int(ceil(r)) + 2
		for y in range(cy - ext, cy + ext + 1):
			for x in range(cx - ext, cx + ext + 1):
				var d := Vector2(x - cx, y - cy).length() + _rh(x, y, 11) * 1.2
				if d < r and _free(x, y):
					flo[y * W + x] = F_WATER
				elif d < r + 1.2 and _free(x, y) and rng.randf() < 0.35:
					_add_decor(Vector2(x + rng.randf(), y + rng.randf()), Defs.FR_REEDS, 0.55, false)
		return


## Red Canyon: a long, tall, meandering rock wall with a couple of passes through it.
func _canyon_wall() -> void:
	var p := Vector2(rng.randi_range(10, W - 11), rng.randi_range(10, H - 11))
	var dir := Vector2.from_angle(rng.randf() * TAU)
	var length := rng.randi_range(25, 50)
	var gap_at := [rng.randi_range(6, length / 2), rng.randi_range(length / 2 + 3, length - 4)]
	for k in length:
		var pass_here := false
		for g in gap_at:
			if absi(k - int(g)) <= 1:
				pass_here = true
		if not pass_here:
			var thick := 1 + int(_rh(k, length, 41) * 2.0)
			for wy in range(-thick, thick + 1):
				for wx in range(-thick, thick + 1):
					var c := Vector2i(floori(p.x) + wx, floori(p.y) + wy)
					if _free(c.x, c.y):
						_blk(c.x, c.y, ROCK, snappedf(2.2 + _rh(c.x, c.y, 43) * 1.2 - absf(wx + wy) * 0.15, 0.2))
		p += dir
		dir = dir.rotated(rng.randf_range(-0.25, 0.25))
		if p.x < 6 or p.y < 6 or p.x > W - 7 or p.y > H - 7:
			break


## Harbor: two canals across the map (wade-able water) with quay walls and bridges.
func _harbor_canals() -> void:
	for k in 2:
		var horiz := k == 0
		var at := int((W if horiz else H) * (0.3 if rng.randf() < 0.5 else 0.7))
		for i in range(2, (W if horiz else H) - 2):
			var bridge := (i / 14) % 3 == 1 and i % 14 < 5
			for w in range(-2, 3):
				var x := i if horiz else at + w
				var y := at + w if horiz else i
				if not _field_ok(x, y) or get_wall(x, y) != 0:
					continue
				if absi(w) == 2:
					if not bridge and rng.randf() < 0.85:
						_blk(x, y, CONCRETE, 0.35)   # low quay edge
				elif not bridge:
					flo[y * W + x] = F_WATER
				else:
					flo[y * W + x] = F_METAL


## Harbor warehouse: a big flat-roofed shed with roller doors.
func _warehouse() -> void:
	for tries in 30:
		var w := rng.randi_range(8, 12)
		var h := rng.randi_range(6, 9)
		var x0 := rng.randi_range(4, W - w - 5)
		var y0 := rng.randi_range(4, H - h - 5)
		if not _rect_free(x0 - 1, y0 - 1, w + 2, h + 2):
			continue
		_house(x0, y0, w, h, CONTAINER if rng.randf() < 0.5 else PLASTER, snappedf(rng.randf_range(2.0, 2.6), 0.1), false)
		return


## Harbor crane: a tall 2x2 concrete pylon with a crate stack beside it.
func _crane() -> void:
	for tries in 30:
		var x := rng.randi_range(6, W - 8)
		var y := rng.randi_range(6, H - 8)
		if not _rect_free(x - 1, y - 1, 5, 4):
			continue
		for dy in 2:
			for dx in 2:
				_blk(x + dx, y + dy, CONCRETE, 3.4)
		_blk(x + 2, y, CRATE, 0.75)
		_blk(x + 2, y + 1, CRATE, 1.5)
		emitters.append([x + 1.0, y + 1.0, 3.4, 0])
		return


## Coastline: the sea along the east and south edges, with a sandy beach between sea and grass.
func _shoreline() -> void:
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			var dist := minf(float(W - 1 - x), float(H - 1 - y))
			dist += sin(float(x) * 0.11) * 2.5 + sin(float(y) * 0.13 + 1.0) * 2.5 + _rh(x / 3, y / 3, 61) * 2.0
			if not _field_ok(x, y) or get_wall(x, y) != 0:
				continue
			if dist < 9.0:
				flo[y * W + x] = F_WATER
			elif dist < 17.0:
				flo[y * W + x] = F_DIRT   # sand (the coast palette's dirt is sand)
				if rng.randf() < 0.015:
					_add_decor(Vector2(x + 0.5, y + 0.5), Defs.FR_DRYBUSH, 0.5, false)


## Coastline: a low grassy dune ridge you can climb onto and fight over.
func _dune_ridge() -> void:
	for tries in 20:
		var p := Vector2(rng.randi_range(10, W - 11), rng.randi_range(10, H - 11))
		if not _field_ok(int(p.x), int(p.y)):
			continue
		var dir := Vector2.from_angle(rng.randf() * TAU)
		for k in rng.randi_range(10, 18):
			for w in range(-1, 2):
				var c := Vector2i(floori(p.x + dir.y * w), floori(p.y - dir.x * w))
				if _free(c.x, c.y) and k % 6 != 3:
					_blk(c.x, c.y, ROCK, 0.6 if w != 0 else 0.9)
			p += dir
			dir = dir.rotated(rng.randf_range(-0.2, 0.2))
		return


func _mesa() -> void:
	for tries in 20:
		var cx := rng.randi_range(8, W - 9)
		var cy := rng.randi_range(8, H - 9)
		var r := rng.randf_range(3.0, 5.5)
		if not _field_ok(cx, cy):
			continue
		for y in range(cy - 7, cy + 8):
			for x in range(cx - 7, cx + 8):
				var d := Vector2(x - cx, y - cy).length() + _rh(x, y, 13) * 1.5
				if d < r and _field_ok(x, y):
					var k := 1.0 - d / r
					var terr := floorf((1.4 + 2.2 * k) * 3.0) / 3.0
					_blk(x, y, ROCK, terr)
		return


## Broken brick walls of uneven height - climbable rubble and cover.
func _ruin() -> void:
	for tries in 30:
		var w := rng.randi_range(5, 8)
		var h := rng.randi_range(5, 8)
		var x0 := rng.randi_range(4, W - w - 5)
		var y0 := rng.randi_range(4, H - h - 5)
		if not _rect_free(x0 - 1, y0 - 1, w + 2, h + 2):
			continue
		for y in range(y0, y0 + h):
			for x in range(x0, x0 + w):
				var e := x == x0 or y == y0 or x == x0 + w - 1 or y == y0 + h - 1
				if e and rng.randf() < 0.75:
					_blk(x, y, BRICK, snappedf(rng.randf_range(0.3, 1.9), 0.15))
				elif not e:
					flo[y * W + x] = F_CONCRETE
					if rng.randf() < 0.15:
						_add_decor(Vector2(x + 0.5, y + 0.5), Defs.FR_RUBBLE, 0.6, false)
		return


func _adobe() -> void:
	for tries in 30:
		var w := rng.randi_range(5, 7)
		var h := rng.randi_range(5, 7)
		var x0 := rng.randi_range(4, W - w - 5)
		var y0 := rng.randi_range(4, H - h - 5)
		if not _rect_free(x0 - 1, y0 - 1, w + 2, h + 2):
			continue
		_house(x0, y0, w, h, PLASTER, snappedf(rng.randf_range(1.5, 1.9), 0.1), rng.randf() < 0.35)
		return


func _cabin() -> void:
	for tries in 30:
		var w := rng.randi_range(5, 7)
		var h := rng.randi_range(4, 6)
		var x0 := rng.randi_range(4, W - w - 5)
		var y0 := rng.randi_range(4, H - h - 5)
		if not _rect_free(x0 - 1, y0 - 1, w + 2, h + 2):
			continue
		_house(x0, y0, w, h, PLANKS, 1.6, false)
		return


func _barricade() -> void:
	for tries in 40:
		var x := rng.randi_range(4, W - 5)
		var y := rng.randi_range(4, H - 5)
		var d := Vector2i(1, 0) if rng.randf() < 0.5 else Vector2i(0, 1)
		var L := rng.randi_range(4, 7)
		var ok := true
		for k in L:
			if not _free(x + d.x * k, y + d.y * k):
				ok = false
				break
		if not ok:
			continue
		for k in L:
			if k == L / 2:
				continue
			_blk(x + d.x * k, y + d.y * k, SANDBAG if rng.randf() < 0.6 else CRATE, 0.55 if rng.randf() < 0.6 else 0.75)
		return


## A building: perimeter walls with windows, doors with lintels, a walkable flat roof with a parapet,
## optional inner staircase up to the roof and a smoking chimney. Ruined houses have broken walls and no roof.
func _house(x0: int, y0: int, w: int, h: int, mat: int, wall_h: float, ruined: bool) -> void:
	var rt := wall_h - 0.3
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			var e := x == x0 or y == y0 or x == x0 + w - 1 or y == y0 + h - 1
			var corner := (x == x0 or x == x0 + w - 1) and (y == y0 or y == y0 + h - 1)
			if e:
				if ruined:
					if rng.randf() < 0.7:
						_blk(x, y, mat, snappedf(rng.randf_range(0.3, wall_h), 0.15))
				elif not corner and (x + y) % 3 == 1 and rng.randf() < 0.6:
					_blk(x, y, mat, 0.45)          # window: low sill + lintel above
					_set_roof(x, y, wall_h)
				else:
					_blk(x, y, mat, wall_h)
			else:
				flo[y * W + x] = F_CONCRETE
				if not ruined:
					_set_roof(x, y, rt)
				elif rng.randf() < 0.12:
					_add_decor(Vector2(x + 0.5, y + 0.5), Defs.FR_RUBBLE, 0.6, false)
	var dx := x0 + w / 2
	var dy := y0 + h / 2
	var doors := [Vector2i(dx, y0), Vector2i(dx, y0 + h - 1), Vector2i(x0, dy)]
	var right_door := rng.randf() < 0.5
	if right_door:
		doors.append(Vector2i(x0 + w - 1, dy))
	for c in doors:
		set_wall(c.x, c.y, 0)
		hgt[c.y * W + c.x] = 0.0
		if not ruined:
			_set_roof(c.x, c.y, wall_h)
	if ruined:
		return
	# inner staircase along the right wall, up through a hole in the roof
	var steps := int(ceil(rt / 0.32)) - 1
	if not right_door and steps <= h - 3:
		var sx := x0 + w - 2
		for k in steps:
			var y := y0 + h - 2 - k
			var i := y * W + sx
			roof[i] = 0
			rtop[i] = 0.0
			_blk(sx, y, STEEL, rt * float(k + 1) / float(steps + 1))
	# chimney on a corner, with smoke
	if rng.randf() < 0.6:
		var cxx := x0 if rng.randf() < 0.5 else x0 + w - 1
		var cyy := y0 if rng.randf() < 0.5 else y0 + h - 1
		_blk(cxx, cyy, BRICK, wall_h + 0.6)
		emitters.append([cxx + 0.5, cyy + 0.5, wall_h + 0.6, 0])


func _field_ok(x: int, y: int) -> bool:
	if x < 2 or y < 2 or x > W - 3 or y > H - 3:
		return false
	for z in _zones:
		if z.has_point(Vector2i(x, y)):
			return false
	if absi(x - W / 2) <= 3 or absi(y - H / 2) <= 3:
		return false
	return true


func _free(x: int, y: int) -> bool:
	return _field_ok(x, y) and get_wall(x, y) == 0 and obst[y * W + x] == 0 and flo[y * W + x] != F_WATER


func _add_decor(p: Vector2, frame: int, scale: float, solid: bool) -> void:
	decor.append([p.x, p.y, frame, scale, 0.0])
	if solid:
		obst[floori(p.y) * W + floori(p.x)] = 1


## Lamp post (sprite 2.2 tall, not solid) and its light near the top.
func _add_lamp(p: Vector2) -> void:
	decor.append([p.x, p.y, FR_LAMP, 2.2, 0.0])
	lamps.append([p.x + 0.25, p.y, 2.0])


func _scatter_decor(frame: int, count: int, solid: bool, scale: float) -> void:
	for i in count:
		for tries in 20:
			var x := rng.randi_range(2, W - 3)
			var y := rng.randi_range(2, H - 3)
			if not _free(x, y):
				continue
			var j := 0.0 if solid else 0.35
			_add_decor(Vector2(x + 0.5 + rng.randf_range(-j, j), y + 0.5 + rng.randf_range(-j, j)), frame, scale * rng.randf_range(0.85, 1.15), solid)
			break


func _scatter_rocks(count: int, max_size: int, rock_share: float) -> void:
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 40:
		tries += 1
		var cx := rng.randi_range(2, W - 3)
		var cy := rng.randi_range(2, H - 3)
		if not _free(cx, cy):
			continue
		placed += 1
		if rng.randf() < rock_share:
			var size := rng.randi_range(1, max_size)
			for dy in range(-size + 1, size):
				for dx in range(-size + 1, size):
					if absi(dx) + absi(dy) < size and rng.randf() < 0.85 and _free(cx + dx, cy + dy):
						set_wall(cx + dx, cy + dy, ROCK)
		else:
			var bh := snappedf(rng.randf_range(0.6, 1.8), 0.15)
			for i in range(rng.randi_range(2, 5)):
				if _free(cx + i, cy):
					_blk(cx + i, cy, BRICK, bh)
			for i in range(rng.randi_range(1, 4)):
				if _free(cx, cy + i):
					_blk(cx, cy + i, BRICK, bh)


func _ridges(count: int) -> void:
	for i in count:
		var p := Vector2(rng.randi_range(4, W - 5), rng.randi_range(4, H - 5))
		var dir := Vector2.from_angle(rng.randf() * TAU)
		var length := rng.randi_range(8, 20)
		for k in length:
			if k % 7 != 3:
				for w in [Vector2i(0, 0), Vector2i(1, 0)]:
					var c := Vector2i(floori(p.x) + w.x, floori(p.y) + w.y)
					if _free(c.x, c.y):
						set_wall(c.x, c.y, ROCK)
			p += dir
			dir = dir.rotated(rng.randf_range(-0.35, 0.35))


func _town() -> void:
	for gy in range(3, H - 10, 11):
		for gx in range(3, W - 10, 11):
			if rng.randf() < 0.2:
				continue
			var w := rng.randi_range(5, 8)
			var h := rng.randi_range(5, 8)
			var x0 := gx + rng.randi_range(0, 2)
			var y0 := gy + rng.randi_range(0, 2)
			var ok := true
			for y in range(y0 - 1, y0 + h + 1):
				for x in range(x0 - 1, x0 + w + 1):
					if not _field_ok(x, y):
						ok = false
			if not ok:
				continue
			var mat := BRICK if rng.randf() < 0.6 else PLASTER
			_house(x0, y0, w, h, mat, snappedf(rng.randf_range(1.6, 2.6), 0.1), rng.randf() < 0.35)
	for y in range(H):
		for x in range(W):
			if flo[y * W + x] == F_GROUND and (x % 11 <= 1 or y % 11 <= 1):
				flo[y * W + x] = F_COBBLE if (x / 11 + y / 11) % 3 == 0 else F_CONCRETE
	# a couple of plazas with a fountain
	for k in 3:
		for tries in 20:
			var cx := rng.randi_range(8, W - 9)
			var cy := rng.randi_range(8, H - 9)
			if not _rect_free(cx - 3, cy - 3, 7, 7):
				continue
			for y in range(cy - 3, cy + 4):
				for x in range(cx - 3, cx + 4):
					flo[y * W + x] = F_COBBLE
			for y in range(cy - 1, cy + 2):
				for x in range(cx - 1, cx + 2):
					if x == cx and y == cy:
						_blk(x, y, CONCRETE, 0.9)
					else:
						flo[y * W + x] = F_WATER
			for y in range(cy - 2, cy + 3):
				for x in range(cx - 2, cx + 3):
					if maxi(absi(x - cx), absi(y - cy)) == 2 and (x + y) % 4 != 0:
						_blk(x, y, CONCRETE, 0.35)
			break


## Every team's tank must reach at least one gate of every bunker; carve corridors if needed.
func _ensure_paths() -> void:
	for t in 4:
		var s: Vector3 = team_spawns[t]
		var start := Vector2i(int(s.x), int(s.y))
		var reach := tank_reach(start)
		for bi in bunkers.size():
			var best: Dictionary = {}
			var bd := 1e9
			var ok := false
			for g in gates:
				if int(g.bunker) != bi:
					continue
				var ap: Vector2 = g.approach
				if reach.has(Vector2i(floori(ap.x), floori(ap.y))):
					ok = true
				var d := ap.distance_to(Vector2(s.x, s.y))
				if d < bd:
					bd = d
					best = g
			if ok or best.is_empty():
				continue
			var goal := Vector2i(floori(best.approach.x), floori(best.approach.y))
			_carve(start, goal)
			reach = tank_reach(start)


func _carve(a: Vector2i, b: Vector2i) -> void:
	var c := a
	var cells: Array = []
	while c.x != b.x:
		cells.append(c)
		c.x += signi(b.x - c.x)
	while c.y != b.y:
		cells.append(c)
		c.y += signi(b.y - c.y)
	cells.append(b)
	var carved := {}
	for p in cells:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var x: int = p.x + dx
				var y: int = p.y + dy
				if x < 1 or y < 1 or x > W - 2 or y > H - 2:
					continue
				if bunker_at(Vector2(x, y)) >= 0:
					continue
				carved[y * W + x] = true
				set_wall(x, y, 0)
				roof[y * W + x] = 0
				obst[y * W + x] = 0
	var keep: Array = []
	for d in decor:
		var i := floori(d[1]) * W + floori(d[0])
		if carved.has(i):
			continue
		keep.append(d)
	decor = keep


func tank_cell_ok(x: int, y: int) -> bool:
	return not circle_blocked(Vector2(x + 0.5, y + 0.5), 0.62)


func tank_reach(start: Vector2i) -> Dictionary:
	var seen := {start: true}
	var q: Array = [start]
	while q.size() > 0:
		var c: Vector2i = q.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n) or n.x < 1 or n.y < 1 or n.x >= W - 1 or n.y >= H - 1:
				continue
			if tank_cell_ok(n.x, n.y):
				seen[n] = true
				q.append(n)
	return seen
