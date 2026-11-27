extends RefCounted
## Procedural pixel art: wall atlas, sprite atlas (16x16 frames of 64 px) and first-person weapon art.

const Defs = preload("res://scripts/defs.gd")

const T := 64
# muzzle point of each weapon image (knife, pistol, rifle)
const VM := 160  # first-person weapon canvas size

const SKIN := Color(0.86, 0.67, 0.52)
const BOOT := Color(0.12, 0.1, 0.08)
const GEAR := Color(0.27, 0.24, 0.16)
const GUN := Color(0.15, 0.15, 0.16)
const WOOD := Color(0.42, 0.27, 0.14)


static func _h(x: int, y: int, s: int) -> float:
	var n := (x * 374761393 + y * 668265263 + s * 1442695041) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	n = n ^ (n >> 16)
	return float(n & 0xffff) / 65535.0


# ---------------------------------------------------------------- walls

static func make_walls() -> ImageTexture:
	var n := 16
	var img := Image.create(T * n, T, false, Image.FORMAT_RGBA8)
	for id in range(1, n + 1):
		var ox := (id - 1) * T
		for y in T:
			for x in T:
				img.set_pixel(ox + x, y, _wall_px(id, x, y))
	return ImageTexture.create_from_image(img)


static func _wall_px(id: int, x: int, y: int) -> Color:
	var n := _h(x, y, id)
	var n2 := _h(x / 4, y / 4, id + 10)
	match id:
		8:
			return _keydoor_px(x, y, n)
		1:
			var base := Color(0.42, 0.38, 0.33)
			var v := 0.7 + 0.25 * n2 + 0.1 * n
			if _h(x / 8, y / 8, 3) > 0.75 and (x % 8 == 0 or y % 8 == 0):
				v *= 0.6
			v *= 0.85 + 0.15 * float(64 - y) / 64.0
			return Color(base.r * v, base.g * v, base.b * v)
		2:
			var row := y / 8
			var off := (row % 2) * 8
			var bx := (x + off) % 16
			var by := y % 8
			if _h(x / 6, y / 6, 9) > 0.86:
				return Color(0.14, 0.1, 0.08)
			if bx == 0 or by == 0:
				return Color(0.55, 0.52, 0.48) * (0.9 + 0.1 * n)
			var b := 0.8 + 0.2 * _h((x + off) / 16, row, 5)
			if by == 1:
				b *= 1.12
			return Color(0.56 * b, 0.26 * b, 0.18 * b) * (0.9 + 0.1 * n)
		3:
			if y >= 52 and y < 60:
				return Color(0.85, 0.7, 0.1) if ((x + y) / 6) % 2 == 0 else Color(0.1, 0.1, 0.1)
			if y < 3:
				return Color(0.7, 0.7, 0.68)
			var row := y / 16
			var off := (row % 2) * 16
			var bx := (x + off) % 32
			var by := y % 16
			if bx == 0 or by == 0:
				return Color(0.3, 0.3, 0.3)
			var v := (0.86 + 0.12 * n2) * (0.95 + 0.05 * n) * (0.8 + 0.2 * float(y) / 64.0)
			if _h(x / 3, y / 8, 21) > 0.9:
				v *= 0.75
			return Color(0.58 * v, 0.58 * v, 0.55 * v)
		4:
			var px := x % 32
			var py := y % 32
			if y >= 29 and y <= 32 and x % 8 < 6:
				return Color(0.3, 0.8, 0.9)
			if px < 2 or py < 2:
				return Color(0.12, 0.14, 0.18)
			for r in [Vector2i(5, 5), Vector2i(26, 5), Vector2i(5, 26), Vector2i(26, 26)]:
				if absi(px - r.x) <= 1 and absi(py - r.y) <= 1:
					return Color(0.55, 0.6, 0.65)
			return Color(0.28, 0.32, 0.38) * (0.92 + 0.08 * n)
		5:
			if x < 4 or x > 59 or y < 4:
				return Color(0.85, 0.7, 0.1) if ((x + y) / 5) % 2 == 0 else Color(0.08, 0.08, 0.08)
			if Vector2(x, y).distance_to(Vector2(32, 12)) < 4.5:
				return Color(1.0, 0.15, 0.1)
			if x == 31 or x == 32:
				return Color(0.08, 0.08, 0.1)
			var rib := 0.8 if y % 10 < 2 else 1.0
			return Color(0.38, 0.39, 0.43) * rib * (0.93 + 0.07 * n)
		6:
			if x < 4 or x > 59 or y < 4 or y > 59:
				return Color(0.4, 0.42, 0.45) * (0.9 + 0.1 * n)
			if x % 16 < 3:
				return Color(0.22, 0.23, 0.25)
			return Color(0.88, 0.72, 0.12) * (0.9 + 0.1 * n) if ((x + y) / 8) % 2 == 0 else Color(0.1, 0.1, 0.1)
		7:
			if x >= 20 and x < 44 and y >= 18 and y < 32:
				if x < 22 or x > 41 or y < 20 or y > 29 or x == 31:
					return Color(0.3, 0.3, 0.3)
				return Color(0.05, 0.08, 0.12) + Color(0.1, 0.12, 0.15) * float(y - 20) / 10.0
			if y > 52 and y % 3 == 0 and x > 8 and x < 56:
				return Color(0.35, 0.34, 0.32)
			var v := (0.88 + 0.1 * n2) * (0.95 + 0.05 * n)
			return Color(0.62 * v, 0.6 * v, 0.55 * v)
		9:
			# sandbags: staggered rows of stuffed bags
			var row := y / 16
			var off := (row % 2) * 12
			var bx := (x + off) % 24
			var by := y % 16
			var dx := (bx - 12.0) / 12.0
			var dy := (by - 8.0) / 8.0
			var r := dx * dx * 0.6 + dy * dy
			if r > 1.0:
				return Color(0.22, 0.19, 0.13)
			var lit := 1.05 - dy * 0.25 - r * 0.2
			var weave := 0.94 if (x + y) % 3 == 0 else 1.0
			return Color(0.62, 0.55, 0.38) * lit * weave * (0.92 + 0.08 * n)
		10:
			# wooden crate
			if x < 4 or x > 59 or y < 4 or y > 59:
				return Color(0.36, 0.24, 0.12) * (0.9 + 0.1 * n)
			if absi(x - y) < 3 or absi(x - (63 - y)) < 3:
				return Color(0.45, 0.31, 0.16) * (0.9 + 0.1 * n)
			var plank := 0.88 if y % 12 == 0 else 1.0
			return Color(0.6, 0.44, 0.24) * plank * (0.85 + 0.12 * n2 + 0.05 * n)
		11:
			# shipping container: corrugated steel, rusty
			var rib := 0.78 if x % 8 < 2 else (1.08 if x % 8 < 4 else 1.0)
			var rust := _h(x / 5, y / 5, 33) > 0.82
			var base := Color(0.55, 0.18, 0.12) if rust else Color(0.18, 0.38, 0.5)
			if y < 3 or y > 60:
				return Color(0.2, 0.2, 0.22)
			if x > 40 and x < 44 and y > 20 and y < 44:
				return Color(0.75, 0.75, 0.7)
			return base * rib * (0.9 + 0.1 * n)
		12:
			# poured concrete blocks
			var v := (0.82 + 0.12 * n2) * (0.94 + 0.06 * n)
			if y % 32 == 0 or x % 32 == 0:
				v *= 0.75
			if _h(x / 2, y / 2, 44) > 0.97:
				v *= 0.6
			return Color(0.6 * v, 0.6 * v, 0.58 * v)
		13:
			# wooden planks (fences, towers, cabins)
			var p := x / 10
			var v := 0.8 + 0.2 * _h(p, 0, 55)
			if x % 10 == 0:
				return Color(0.2, 0.13, 0.07)
			if _h(x / 2, y / 6, 56) > 0.93:
				v *= 0.7
			if (y == 10 or y == 50) and x % 10 == 5:
				return Color(0.25, 0.25, 0.25)
			return Color(0.55, 0.38, 0.22) * v * (0.94 + 0.06 * n)
		14:
			# steel stair plates with a hazard edge
			if y < 6:
				return Color(0.9, 0.72, 0.1) if ((x + y) / 4) % 2 == 0 else Color(0.1, 0.1, 0.1)
			var tread := 0.8 if (x / 4 + y / 4) % 2 == 0 else 1.0
			return Color(0.42, 0.44, 0.47) * tread * (0.9 + 0.1 * n)
		15:
			# hedge
			var g := Color(0.16, 0.32, 0.12)
			var leaf := _h(x / 3, y / 3, 66)
			var v := 0.7 + 0.45 * leaf + 0.15 * n
			if y < 6:
				v *= 1.1
			return Color(g.r * v, g.g * v, g.b * v)
		16:
			# plaster / adobe with cracks and exposed bricks
			var v := (0.86 + 0.1 * n2) * (0.96 + 0.04 * n)
			if _h(x / 12, y / 8, 71) > 0.84:
				var row := y / 6
				var bx := (x + (row % 2) * 6) % 12
				if bx == 0 or y % 6 == 0:
					return Color(0.4, 0.36, 0.3)
				return Color(0.55, 0.3, 0.2) * (0.9 + 0.1 * n)
			if absi((x * 7 + y * 3) % 61 - 30) < 1 and _h(x / 16, y / 16, 72) > 0.6:
				v *= 0.6
			return Color(0.74 * v, 0.66 * v, 0.52 * v)
	return Color.MAGENTA


# ---------------------------------------------------------------- drawing primitives

static func _new(w := T, h := T) -> Image:
	return Image.create(w, h, false, Image.FORMAT_RGBA8)


static func _r(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	var rr := Rect2i(x, y, w, h).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if rr.size.x > 0 and rr.size.y > 0:
		img.fill_rect(rr, c)


static func _circ(img: Image, cx: float, cy: float, r: float, c: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in range(int(cy - r) - 1, int(cy + r) + 2):
		if y < 0 or y >= h:
			continue
		for x in range(int(cx - r) - 1, int(cx + r) + 2):
			if x < 0 or x >= w:
				continue
			if (x + 0.5 - cx) * (x + 0.5 - cx) + (y + 0.5 - cy) * (y + 0.5 - cy) <= r * r:
				img.set_pixel(x, y, c)


static func _line(img: Image, a: Vector2, b: Vector2, w: float, c: Color) -> void:
	var L := a.distance_to(b)
	var steps := maxi(1, int(L * 2.0))
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		_circ(img, p.x, p.y, w * 0.5, c)


## Scanline polygon fill, lit from the top.
static func _poly(img: Image, pts: Array, c: Color, grad := 0.18) -> void:
	var miny := 1e9
	var maxy := -1e9
	for p in pts:
		miny = minf(miny, p.y)
		maxy = maxf(maxy, p.y)
	var h := maxf(1.0, maxy - miny)
	for y in range(maxi(0, int(miny)), mini(img.get_height(), int(maxy) + 1)):
		var sy := y + 0.5
		var xs: Array = []
		for i in pts.size():
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			if (a.y <= sy and b.y > sy) or (b.y <= sy and a.y > sy):
				xs.append(a.x + (sy - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		var t := (sy - miny) / h
		var col := c.lightened(grad * (1.0 - t)) if t < 0.5 else c.darkened(grad * (t - 0.5))
		for k in range(0, xs.size() - 1, 2):
			var x0 := maxi(0, int(round(xs[k])))
			var x1 := mini(img.get_width(), int(round(xs[k + 1])))
			if x1 > x0:
				img.fill_rect(Rect2i(x0, y, x1 - x0, 1), col)


## Noise + dark outline pass.
static func _finish(img: Image, outline: bool, seed_v: int) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var src := img.get_data()
	var out := src.duplicate()
	for y in h:
		for x in w:
			var i := (y * w + x) * 4
			if src[i + 3] > 127:
				var v := 0.93 + 0.1 * _h(x, y, seed_v)
				out[i] = clampi(int(src[i] * v), 0, 255)
				out[i + 1] = clampi(int(src[i + 1] * v), 0, 255)
				out[i + 2] = clampi(int(src[i + 2] * v), 0, 255)
			elif outline:
				var near := false
				if x > 0 and src[i - 4 + 3] > 127: near = true
				elif x < w - 1 and src[i + 4 + 3] > 127: near = true
				elif y > 0 and src[i - w * 4 + 3] > 127: near = true
				elif y < h - 1 and src[i + w * 4 + 3] > 127: near = true
				if near:
					out[i] = 14
					out[i + 1] = 13
					out[i + 2] = 12
					out[i + 3] = 255
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out)


static func _put(atlas: Image, idx: int, fr: Image, outline := true, process := true) -> void:
	var img := _finish(fr, outline, 77 + idx) if process else fr
	atlas.blit_rect(img, Rect2i(0, 0, T, T), Vector2i((idx % 16) * T, (idx / 16) * T))


# ---------------------------------------------------------------- sprite atlas

static func make_sprites() -> ImageTexture:
	var atlas := Image.create(T * 16, T * 16, false, Image.FORMAT_RGBA8)
	for pal in 5:
		var uni: Color
		var helm: Color
		var band: Color
		if pal == 0:
			uni = Color(0.38, 0.40, 0.31)
			helm = Color(0.27, 0.29, 0.22)
			band = Color(0.85, 0.1, 0.1)
		else:
			var tc: Color = Defs.TEAM_COLORS[pal - 1]
			uni = tc.darkened(0.3)
			helm = tc.darkened(0.55)
			band = tc.lightened(0.45)
		var base := pal * 16
		var phases := [0, 1, -1]
		for ph in 3:
			var phase: int = phases[ph]
			_put(atlas, base + Defs.SO_FRONT + ph, _soldier(0, phase, uni, helm, band, 0))
			_put(atlas, base + Defs.SO_SIDE + ph, _soldier(1, phase, uni, helm, band, 0))
			_put(atlas, base + Defs.SO_BACK + ph, _soldier(2, phase, uni, helm, band, 0))
		_put(atlas, base + Defs.SO_SHOOT, _soldier(0, 0, uni, helm, band, 1))
		_put(atlas, base + Defs.SO_SHOOT_SIDE, _soldier(1, 0, uni, helm, band, 1))
		_put(atlas, base + Defs.SO_DYING, _soldier(0, 0, uni, helm, band, 2))
		_put(atlas, base + Defs.SO_DEAD, _soldier(0, 0, uni, helm, band, 3))
		_put(atlas, base + Defs.SO_CROUCH, _soldier(0, 0, uni, helm, band, 4))
		_put(atlas, base + Defs.SO_JUMP, _soldier(0, 0, uni, helm, band, 5))
	for t in 4:
		var tc: Color = Defs.TEAM_COLORS[t]
		_put(atlas, Defs.FR_TANK + t * 4 + 0, _tank_front(tc, false))
		_put(atlas, Defs.FR_TANK + t * 4 + 1, _tank_side(tc, 0))
		_put(atlas, Defs.FR_TANK + t * 4 + 2, _tank_side(tc, 1))
		_put(atlas, Defs.FR_TANK + t * 4 + 3, _tank_front(tc, true))
	_put(atlas, Defs.FR_WRECK, _wreck())
	_put(atlas, Defs.FR_TURRET, _turret(false))
	_put(atlas, Defs.FR_TURRET_DEAD, _turret(true))
	_put(atlas, Defs.FR_SHELL, _shell(), false)
	for k in 3:
		_put(atlas, Defs.FR_EXPL + k, _explosion(k), false)
	_put(atlas, Defs.FR_PUFF, _soft(Color(0.7, 0.68, 0.62), 12.0, 1.0), false, false)
	_put(atlas, Defs.FR_BLOOD, _splat(Color(0.65, 0.04, 0.04), 9.0), false)
	_put(atlas, Defs.FR_SMOKE, _soft(Color(0.32, 0.31, 0.3), 28.0, 0.9), false, false)
	_put(atlas, Defs.FR_DUST, _soft(Color(0.6, 0.52, 0.4), 24.0, 0.8), false, false)
	_put(atlas, Defs.FR_TRACER, _tracer(), false, false)
	_put(atlas, Defs.FR_TREE, _tree())
	_put(atlas, Defs.FR_PINE, _pine())
	_put(atlas, Defs.FR_DEADTREE, _deadtree())
	_put(atlas, Defs.FR_BUSH, _bush(Color(0.2, 0.36, 0.14)))
	_put(atlas, Defs.FR_CACTUS, _cactus())
	_put(atlas, Defs.FR_CRATE, _crate())
	_put(atlas, Defs.FR_BARREL, _barrel())
	_put(atlas, Defs.FR_CARWRECK, _carwreck())
	_put(atlas, Defs.FR_RUBBLE, _rubble())
	_put(atlas, Defs.FR_GRASS, _grass(), false)
	_put(atlas, Defs.FR_SNOWBUSH, _bush(Color(0.85, 0.87, 0.92)))
	_put(atlas, Defs.FR_SANDBAG, _sandbag())
	_put(atlas, Defs.FR_DRYBUSH, _drybush(), false)
	for k in 5:
		_put(atlas, Defs.FR_KEY + k, _key(Color(0.95, 0.8, 0.2) if k == 0 else Defs.TEAM_COLORS[k - 1]))
	for k in 6:
		_put(atlas, Defs.FR_LOOT + k, _loot(k))
	_put(atlas, Defs.FR_GRENADE, _grenade(false))
	_put(atlas, Defs.FR_SMOKE_GREN, _grenade(true))
	for k in 3:
		_put(atlas, Defs.FR_TERMINAL + k, _terminal(k))
	_put(atlas, Defs.FR_AMMO, _ammo_crate())
	_put(atlas, Defs.FR_ARMOR, _armor_vest())
	for vt in range(1, 5):
		for t in 4:
			var tc: Color = Defs.TEAM_COLORS[t]
			for k in 4:
				_put(atlas, Defs.FR_VEH + (vt - 1) * 16 + t * 4 + k, _vehicle(vt, k, tc))
	for t in 5:
		var fc: Color = Defs.TEAM_COLORS[t] if t < 4 else Color(0.8, 0.78, 0.72)
		for k in 2:
			_put(atlas, Defs.FR_FLAG + t * 2 + k, _flag(fc, k))
	for k in 2:
		_put(atlas, Defs.FR_BIRD + k, _bird(k))
		_put(atlas, Defs.FR_FIRE + k, _fire(k))
	_put(atlas, Defs.FR_REEDS, _reeds(), false)
	_put(atlas, Defs.FR_FLOWERS, _flowers(), false)
	_put(atlas, Defs.FR_LEAF, _soft(Color(0.55, 0.5, 0.2), 4.0, 1.0), false, false)
	_put(atlas, Defs.FR_CHUTE, _chute())
	_put(atlas, Defs.FR_DROP, _supply_crate())
	_put(atlas, Defs.FR_MORTAR, _mortar())
	_put(atlas, Defs.FR_PLANE, _plane())
	return ImageTexture.create_from_image(atlas)


## Twin-engine bomber seen from below/behind: wings, fuselage, engines with spinning props.
static func _plane() -> Image:
	var img := _new()
	var body := Color(0.28, 0.3, 0.24)
	var under := Color(0.42, 0.45, 0.4)
	_poly(img, [Vector2(2, 30), Vector2(62, 30), Vector2(60, 36), Vector2(4, 36)], body, 0.25)       # wing
	_r(img, 4, 34, 56, 2, under)
	_poly(img, [Vector2(28, 18), Vector2(36, 18), Vector2(37, 46), Vector2(27, 46)], body.lightened(0.05), 0.3)  # fuselage
	_poly(img, [Vector2(20, 46), Vector2(44, 46), Vector2(42, 50), Vector2(22, 50)], body, 0.2)      # tailplane
	_r(img, 31, 40, 2, 9, body.darkened(0.3))                                                          # fin
	for ex in [16.0, 48.0]:
		_circ(img, ex, 33.0, 4.0, body.darkened(0.2))
		_r(img, int(ex) - 6, 27, 12, 2, Color(0.55, 0.55, 0.52, 1.0))                                   # prop blur
	_circ(img, 32, 20, 2.5, Color(0.6, 0.75, 0.85))                                                    # nose glass
	_r(img, 12, 31, 3, 3, Color(0.85, 0.15, 0.1))
	_r(img, 49, 31, 3, 3, Color(0.85, 0.15, 0.1))
	return img


static func _chute() -> Image:
	var img := _new()
	var a := Color(0.92, 0.9, 0.85)
	var b := Color(0.85, 0.3, 0.15)
	for x in range(4, 60):
		var t := (x - 32.0) / 28.0
		var top := 6.0 + t * t * 14.0
		var bottom := 20.0 + t * t * 6.0 + sin(x * 0.75) * 1.5
		for y in range(int(top), int(bottom)):
			var c: Color = a if (x / 9) % 2 == 0 else b
			img.set_pixel(x, y, c.darkened(0.25 * float(y - top) / maxf(1.0, bottom - top)))
	for sx in [6, 18, 32, 46, 58]:
		_line(img, Vector2(sx, 22), Vector2(32, 62), 1.0, Color(0.25, 0.22, 0.2))
	return img


## Base mortar: tube on a baseplate with a bipod, a crate of shells beside it.
static func _mortar() -> Image:
	var img := _new()
	var steel := Color(0.24, 0.27, 0.2)
	var dark := Color(0.12, 0.13, 0.11)
	_poly(img, [Vector2(10, 55), Vector2(24, 50), Vector2(40, 53), Vector2(30, 61), Vector2(14, 61)], Color(0.3, 0.3, 0.28), 0.25)
	_line(img, Vector2(36, 30), Vector2(46, 59), 2.5, dark)
	_line(img, Vector2(36, 30), Vector2(31, 60), 2.5, dark)
	_line(img, Vector2(40, 46), Vector2(34, 46), 2.0, dark)
	_line(img, Vector2(24, 55), Vector2(40, 13), 8.0, steel.darkened(0.3))
	_line(img, Vector2(24, 54), Vector2(39, 14), 5.0, steel)
	_line(img, Vector2(22, 53), Vector2(37, 14), 1.5, steel.lightened(0.35))
	_circ(img, 40.5, 12.5, 4.6, dark)
	_circ(img, 40.5, 12.5, 2.6, Color(0.03, 0.03, 0.03))
	_r(img, 33, 29, 8, 5, Color(0.2, 0.2, 0.18))
	_circ(img, 41.5, 31.5, 2.2, Color(0.5, 0.48, 0.4))
	# shell crate
	_poly(img, [Vector2(44, 47), Vector2(61, 47), Vector2(61, 62), Vector2(44, 62)], Color(0.34, 0.36, 0.2), 0.2)
	_r(img, 44, 47, 17, 2, Color(0.22, 0.24, 0.13))
	for k in 3:
		_circ(img, 47.5 + k * 5.0, 51.5, 2.0, Color(0.78, 0.62, 0.25))
		_circ(img, 47.5 + k * 5.0, 51.0, 0.9, Color(0.95, 0.85, 0.5))
	return img


static func _supply_crate() -> Image:
	var img := _new()
	var w := Color(0.3, 0.38, 0.22)
	_poly(img, [Vector2(8, 24), Vector2(56, 24), Vector2(56, 64), Vector2(8, 64)], w, 0.2)
	_r(img, 8, 24, 48, 3, w.darkened(0.35))
	_r(img, 8, 40, 48, 3, w.darkened(0.35))
	_r(img, 8, 24, 3, 40, w.darkened(0.3))
	_r(img, 53, 24, 3, 40, w.darkened(0.3))
	_r(img, 22, 45, 20, 12, Color(0.92, 0.9, 0.82))
	_r(img, 30, 46, 4, 10, Color(0.8, 0.12, 0.1))
	_r(img, 27, 49, 10, 4, Color(0.8, 0.12, 0.1))
	_circ(img, 32, 19, 4.0, Color(1.0, 0.25, 0.15))
	_r(img, 31, 21, 2, 4, Color(0.2, 0.2, 0.2))
	return img


static func _flag(c: Color, k: int) -> Image:
	var img := _new()
	_r(img, 9, 2, 3, 62, Color(0.35, 0.33, 0.3))
	_circ(img, 10.5, 2.5, 2.0, Color(0.8, 0.7, 0.3))
	for x in range(12, 56):
		var t := float(x - 12) / 44.0
		var wave := sin(t * 6.0 + k * PI) * 3.0 * t
		var top := 5.0 + wave
		for y in range(int(top), int(top + 22.0 - t * 3.0)):
			var shade := 0.85 + 0.2 * sin(t * 6.0 + k * PI + 1.2)
			var col := c * shade
			if y > top + 8.0 and y < top + 12.0:
				col = col.lightened(0.35)
			img.set_pixel(x, clampi(y, 0, 63), Color(col.r, col.g, col.b, 1.0))
	return img


static func _bird(k: int) -> Image:
	var img := _new()
	var c := Color(0.1, 0.1, 0.12)
	var tip := 22.0 if k == 0 else 40.0
	_line(img, Vector2(14, tip), Vector2(32, 32), 3, c)
	_line(img, Vector2(50, tip), Vector2(32, 32), 3, c)
	_circ(img, 32, 33, 3, c)
	return img


static func _fire(k: int) -> Image:
	var img := _barrel()
	for i in 26:
		var x := 20.0 + _h(i, k + 1, 91) * 24.0
		var y := 18.0 - _h(i, k + 5, 91) * 16.0
		var r := 3.0 + _h(i, k + 9, 91) * 4.0
		var c := Color(1.0, 0.45, 0.08) if i % 3 else Color(1.0, 0.85, 0.3)
		_circ(img, x, y + 4.0, r, c)
	return img


static func _reeds() -> Image:
	var img := _new()
	for i in 12:
		var x := 14.0 + _h(i, 1, 93) * 36.0
		var top := 14.0 + _h(i, 2, 93) * 22.0
		var bend := (_h(i, 3, 93) - 0.5) * 10.0
		_line(img, Vector2(x, 64), Vector2(x + bend, top), 1.6, Color(0.42, 0.48, 0.2).darkened(_h(i, 4, 93) * 0.3))
		if i % 3 == 0:
			_r(img, int(x + bend) - 1, int(top), 3, 7, Color(0.36, 0.22, 0.12))
	return img


static func _flowers() -> Image:
	var img := _new()
	var cols := [Color(0.95, 0.85, 0.2), Color(0.9, 0.3, 0.3), Color(0.95, 0.95, 0.95), Color(0.6, 0.45, 0.9)]
	for i in 10:
		var x := 12.0 + _h(i, 1, 95) * 40.0
		var top := 40.0 + _h(i, 2, 95) * 16.0
		_line(img, Vector2(x, 64), Vector2(x, top), 1.4, Color(0.25, 0.45, 0.16))
		_circ(img, x, top, 2.5, cols[i % 4])
	return img


static func _helmet(img: Image, cx: float, top: float, helm: Color) -> void:
	_poly(img, [Vector2(cx - 9, top + 10), Vector2(cx - 7, top + 3), Vector2(cx, top), Vector2(cx + 7, top + 3),
		Vector2(cx + 9, top + 10), Vector2(cx + 10, top + 12), Vector2(cx - 10, top + 12)], helm, 0.3)
	_r(img, int(cx - 10), int(top + 11), 20, 2, helm.darkened(0.3))


static func _soldier(view: int, phase: int, uni: Color, helm: Color, band: Color, mode: int) -> Image:
	var img := _new()
	var pants := uni.darkened(0.3)
	var uni_d := uni.darkened(0.25)
	var skin_d := SKIN.darkened(0.25)
	if mode == 4:
		# kneeling: thighs spread wide, body low (head ~14 px lower than standing)
		_r(img, 14, 51, 16, 7, pants)
		_r(img, 34, 51, 16, 7, pants.darkened(0.1))
		_r(img, 12, 57, 10, 6, BOOT)
		_r(img, 42, 57, 10, 6, BOOT)
		_poly(img, [Vector2(21, 36), Vector2(43, 36), Vector2(42, 54), Vector2(22, 54)], uni)
		_r(img, 22, 51, 20, 3, GEAR)
		_r(img, 29, 33, 6, 4, skin_d)
		_circ(img, 32, 28, 6, SKIN)
		_r(img, 29, 28, 2, 2, Color(0.08, 0.08, 0.08))
		_r(img, 34, 28, 2, 2, Color(0.08, 0.08, 0.08))
		_helmet(img, 32, 17, helm)
		_line(img, Vector2(19, 39), Vector2(22, 49), 5, uni_d)
		_line(img, Vector2(45, 39), Vector2(41, 45), 5, uni_d)
		_line(img, Vector2(13, 53), Vector2(51, 42), 4, GUN)
		_circ(img, 22, 49, 3, SKIN)
		_circ(img, 41, 45, 3, SKIN)
		return img
	if mode == 5:
		# mid-jump: knees pulled up, arms out, gun raised
		_line(img, Vector2(27, 42), Vector2(19, 49), 7, pants)
		_line(img, Vector2(37, 42), Vector2(45, 49), 7, pants.darkened(0.1))
		_line(img, Vector2(19, 49), Vector2(24, 56), 6, pants)
		_line(img, Vector2(45, 49), Vector2(40, 56), 6, pants.darkened(0.1))
		_r(img, 19, 55, 9, 6, BOOT)
		_r(img, 36, 55, 9, 6, BOOT)
		_poly(img, [Vector2(21, 20), Vector2(43, 20), Vector2(42, 42), Vector2(22, 42)], uni)
		_r(img, 22, 39, 20, 3, GEAR)
		_r(img, 29, 17, 6, 4, skin_d)
		_circ(img, 32, 12, 6, SKIN)
		_r(img, 29, 12, 2, 2, Color(0.08, 0.08, 0.08))
		_r(img, 34, 12, 2, 2, Color(0.08, 0.08, 0.08))
		_helmet(img, 32, 1, helm)
		_line(img, Vector2(21, 23), Vector2(12, 30), 5, uni_d)
		_line(img, Vector2(43, 23), Vector2(50, 27), 5, uni_d)
		_line(img, Vector2(8, 33), Vector2(56, 22), 4, GUN)
		_circ(img, 12, 31, 3, SKIN)
		_circ(img, 50, 26, 3, SKIN)
		return img
	if mode == 3:
		_r(img, 4, 59, 56, 5, Color(0.42, 0.03, 0.03))
		_poly(img, [Vector2(14, 51), Vector2(44, 51), Vector2(46, 60), Vector2(14, 60)], uni)
		_line(img, Vector2(44, 56), Vector2(60, 58), 6, pants)
		_r(img, 58, 54, 5, 7, BOOT)
		_circ(img, 9, 55, 5.5, SKIN)
		_r(img, 2, 49, 11, 5, helm)
		_line(img, Vector2(18, 48), Vector2(42, 50), 3, GUN)
		_line(img, Vector2(26, 53), Vector2(30, 60), 2, GEAR)
		return img
	if mode == 2:
		_line(img, Vector2(28, 60), Vector2(33, 46), 6, pants)
		_line(img, Vector2(36, 60), Vector2(35, 46), 6, pants)
		_line(img, Vector2(34, 46), Vector2(46, 30), 12, uni)
		_circ(img, 49, 24, 6, SKIN)
		_r(img, 42, 15, 13, 7, helm)
		_line(img, Vector2(40, 34), Vector2(54, 40), 4, uni_d)
		_line(img, Vector2(44, 30), Vector2(30, 22), 4, uni_d)
		_line(img, Vector2(14, 20), Vector2(26, 30), 3, GUN)
		for i in 6:
			_circ(img, 48 + _h(i, 1, 3) * 12, 26 + _h(i, 2, 3) * 14, 1.5, Color(0.7, 0.05, 0.05))
		return img
	var b := 1 if phase != 0 else 0
	if view == 1:
		var hip := Vector2(31, 43)
		var f := float(phase) * 7.0
		_line(img, hip, Vector2(31 - f, 57), 6, pants.darkened(0.15))
		_r(img, int(28 - f), 56, 8, 6, BOOT)
		_poly(img, [Vector2(18, 23 + b), Vector2(26, 23 + b), Vector2(26, 40 + b), Vector2(18, 39 + b)], uni_d)
		_poly(img, [Vector2(25, 22 + b), Vector2(38, 22 + b), Vector2(38, 44), Vector2(26, 44)], uni)
		_line(img, hip, Vector2(31 + f, 57), 6, pants)
		_r(img, int(28 + f), 56, 9, 6, BOOT)
		_r(img, 26, 40, 12, 3, GEAR)
		_r(img, 31, 19 + b, 5, 4, skin_d)
		_circ(img, 33, 14 + b, 6, SKIN)
		_r(img, 38, 14 + b, 2, 3, SKIN)
		_r(img, 35, 13 + b, 2, 2, Color(0.08, 0.08, 0.08))
		_helmet(img, 32, 3 + b, helm)
		_line(img, Vector2(31, 25 + b), Vector2(39, 32 + b), 5, uni_d)
		_line(img, Vector2(27, 27 + b), Vector2(28, 30 + b), 4, band)
		_line(img, Vector2(22, 34 + b), Vector2(60, 30 + b), 3, GUN)
		_r(img, 36, 32 + b, 4, 6, GUN)
		_r(img, 20, 33 + b, 7, 3, WOOD)
		_circ(img, 40, 32 + b, 2.5, SKIN)
		_circ(img, 48, 31 + b, 2.5, SKIN)
		if mode == 1:
			_circ(img, 61, 30, 6, Color(1, 0.75, 0.2))
			_circ(img, 61, 30, 3, Color(1, 1, 0.85))
		return img
	# front / back
	var lift_l := 3 if phase > 0 else 0
	var lift_r := 3 if phase < 0 else 0
	_r(img, 24, 42, 7, 15 - lift_l, pants)
	_r(img, 33, 42, 7, 15 - lift_r, pants.darkened(0.1))
	_r(img, 23, 56 - lift_l, 9, 7, BOOT)
	_r(img, 32, 56 - lift_r, 9, 7, BOOT)
	_poly(img, [Vector2(21, 22 + b), Vector2(43, 22 + b), Vector2(42, 43), Vector2(22, 43)], uni)
	_r(img, 22, 40, 20, 3, GEAR)
	_r(img, 29, 19 + b, 6, 4, skin_d)
	if view == 2:
		_poly(img, [Vector2(24, 23 + b), Vector2(40, 23 + b), Vector2(40, 39 + b), Vector2(24, 39 + b)], uni_d, 0.25)
		_r(img, 24, 21 + b, 16, 4, Color(0.35, 0.33, 0.22))
		_line(img, Vector2(18, 24 + b), Vector2(18, 38 + b), 5, uni_d)
		_line(img, Vector2(46, 24 + b), Vector2(46, 38 + b), 5, uni_d)
		_circ(img, 32, 14 + b, 6, skin_d)
		_helmet(img, 32, 3 + b, helm)
		_r(img, 23, 12 + b, 18, 4, helm)
		_line(img, Vector2(41, 6 + b), Vector2(44, 30 + b), 3, GUN)
		return img
	_line(img, Vector2(25, 23 + b), Vector2(30, 41), 2, GEAR)
	_line(img, Vector2(39, 23 + b), Vector2(34, 41), 2, GEAR)
	_r(img, 24, 35, 5, 4, GEAR.darkened(0.2))
	_r(img, 35, 35, 5, 4, GEAR.darkened(0.2))
	_circ(img, 32, 14 + b, 6, SKIN)
	_r(img, 29, 14 + b, 2, 2, Color(0.08, 0.08, 0.08))
	_r(img, 34, 14 + b, 2, 2, Color(0.08, 0.08, 0.08))
	_r(img, 30, 18 + b, 4, 1, Color(0.5, 0.28, 0.22))
	_helmet(img, 32, 3 + b, helm)
	if mode == 1:
		_line(img, Vector2(19, 25), Vector2(27, 31), 5, uni_d)
		_line(img, Vector2(45, 25), Vector2(37, 31), 5, uni_d)
		_r(img, 27, 26, 10, 9, GUN)
		_circ(img, 32, 29, 9, Color(1, 0.75, 0.2))
		_circ(img, 32, 29, 5, Color(1, 1, 0.85))
	else:
		_line(img, Vector2(19, 25 + b), Vector2(21, 37), 5, uni_d)
		_line(img, Vector2(45, 25 + b), Vector2(42, 32), 5, uni_d)
		_line(img, Vector2(18, 26 + b), Vector2(19, 29 + b), 5, band)
		_line(img, Vector2(13, 41), Vector2(51, 29), 4, GUN)
		_line(img, Vector2(13, 41), Vector2(20, 39), 4, WOOD)
		_circ(img, 22, 37, 3, SKIN)
		_circ(img, 41, 33, 3, SKIN)
	return img


static func _camo(img: Image, x0: int, y0: int, w: int, h: int, col: Color, seed_v: int) -> void:
	for i in 7:
		var cx := x0 + _h(i, 1, seed_v) * w
		var cy := y0 + _h(i, 2, seed_v) * h
		var r := 2.0 + _h(i, 3, seed_v) * 3.0
		for y in range(int(cy - r), int(cy + r) + 1):
			for x in range(int(cx - r), int(cx + r) + 1):
				if x >= x0 and x < x0 + w and y >= y0 and y < y0 + h and Vector2(x, y).distance_to(Vector2(cx, cy)) <= r:
					if img.get_pixel(x, y).a > 0.5:
						img.set_pixel(x, y, col)


static func _tank_side(col: Color, ph: int) -> Image:
	var img := _new()
	var dark := col.darkened(0.45)
	var tr := Color(0.13, 0.13, 0.12)
	_poly(img, [Vector2(1, 46), Vector2(6, 42), Vector2(58, 42), Vector2(63, 46), Vector2(60, 61), Vector2(4, 61)], tr, 0.1)
	for i in 16:
		var x := (i * 4 + ph * 2) % 64
		_r(img, x, 43, 2, 2, Color(0.3, 0.3, 0.28))
		_r(img, x, 59, 2, 2, Color(0.3, 0.3, 0.28))
	for i in 6:
		var cx := 8.0 + i * 9.6
		_circ(img, cx, 52, 5, Color(0.33, 0.33, 0.31))
		_circ(img, cx, 52, 2, tr)
		var a := float(ph) * 0.8 + i
		_line(img, Vector2(cx, 52) + Vector2.from_angle(a) * 4.0, Vector2(cx, 52) - Vector2.from_angle(a) * 4.0, 1, Color(0.2, 0.2, 0.2))
	_poly(img, [Vector2(3, 32), Vector2(56, 32), Vector2(62, 36), Vector2(60, 43), Vector2(3, 43)], col)
	_r(img, 3, 32, 54, 2, col.lightened(0.25))
	_camo(img, 3, 33, 58, 10, col.darkened(0.25), 11)
	_poly(img, [Vector2(16, 20), Vector2(40, 20), Vector2(44, 26), Vector2(42, 32), Vector2(14, 32)], dark, 0.3)
	_camo(img, 14, 20, 30, 12, dark.darkened(0.25), 12)
	_r(img, 44, 23, 20, 4, Color(0.2, 0.2, 0.21))
	_r(img, 42, 22, 5, 6, Color(0.25, 0.25, 0.26))
	_r(img, 22, 16, 9, 4, tr)
	_line(img, Vector2(18, 20), Vector2(14, 4), 1, Color(0.2, 0.2, 0.2))
	_r(img, 6, 36, 6, 4, Color(0.3, 0.28, 0.2))
	return img


static func _tank_front(col: Color, back: bool) -> Image:
	var img := _new()
	var dark := col.darkened(0.45)
	var tr := Color(0.13, 0.13, 0.12)
	_r(img, 3, 36, 13, 26, tr)
	_r(img, 48, 36, 13, 26, tr)
	for i in 7:
		_r(img, 3, 38 + i * 3, 13, 1, Color(0.3, 0.3, 0.28))
		_r(img, 48, 38 + i * 3, 13, 1, Color(0.3, 0.3, 0.28))
	_poly(img, [Vector2(10, 30), Vector2(54, 30), Vector2(50, 58), Vector2(14, 58)], col)
	_camo(img, 10, 30, 44, 28, col.darkened(0.25), 21)
	_poly(img, [Vector2(19, 15), Vector2(45, 15), Vector2(47, 30), Vector2(17, 30)], dark, 0.3)
	_camo(img, 17, 15, 30, 15, dark.darkened(0.25), 22)
	_r(img, 22, 11, 10, 4, tr)
	_line(img, Vector2(43, 15), Vector2(48, 0), 1, Color(0.2, 0.2, 0.2))
	if not back:
		_r(img, 26, 19, 12, 11, Color(0.22, 0.22, 0.23))
		_circ(img, 32, 24, 5, Color(0.12, 0.12, 0.12))
		_circ(img, 32, 24, 2.5, Color(0.0, 0.0, 0.0))
		_r(img, 14, 36, 5, 4, Color(1, 0.92, 0.6))
		_r(img, 45, 36, 5, 4, Color(1, 0.92, 0.6))
		_r(img, 20, 48, 24, 2, col.darkened(0.4))
	else:
		_r(img, 18, 40, 10, 6, Color(0.12, 0.12, 0.12))
		_r(img, 36, 40, 10, 6, Color(0.12, 0.12, 0.12))
		for i in 3:
			_r(img, 18, 41 + i * 2, 10, 1, Color(0.25, 0.25, 0.25))
			_r(img, 36, 41 + i * 2, 10, 1, Color(0.25, 0.25, 0.25))
		_r(img, 22, 50, 20, 5, Color(0.3, 0.28, 0.2))
		_r(img, 15, 37, 3, 2, Color(0.8, 0.1, 0.1))
		_r(img, 46, 37, 3, 2, Color(0.8, 0.1, 0.1))
	return img


static func _wreck() -> Image:
	var img := _tank_side(Color(0.17, 0.16, 0.15), 0)
	for i in 16:
		var x := 6.0 + _h(i, 1, 5) * 50.0
		var y := 18.0 + _h(i, 2, 5) * 26.0
		_circ(img, x, y, 1.5 + _h(i, 3, 5) * 2.5, Color(1.0, 0.4 + _h(i, 4, 5) * 0.45, 0.05) if i % 2 == 0 else Color(0.06, 0.06, 0.06))
	return img


static func _sandbag_row(img: Image, y: int, n: int, x0: int) -> void:
	for i in n:
		_poly(img, [Vector2(x0 + i * 10, y + 2), Vector2(x0 + i * 10 + 10, y), Vector2(x0 + i * 10 + 11, y + 6), Vector2(x0 + i * 10 + 1, y + 7)], Color(0.6, 0.52, 0.36), 0.25)


static func _turret(dead: bool) -> Image:
	var img := _new()
	_sandbag_row(img, 56, 6, 2)
	_sandbag_row(img, 50, 6, 4)
	_sandbag_row(img, 44, 5, 8)
	if dead:
		_poly(img, [Vector2(18, 34), Vector2(44, 30), Vector2(46, 44), Vector2(16, 44)], Color(0.12, 0.12, 0.11))
		_line(img, Vector2(30, 36), Vector2(50, 26), 3, Color(0.1, 0.1, 0.1))
		_circ(img, 26, 34, 3, Color(1.0, 0.5, 0.1))
		return img
	_r(img, 28, 38, 8, 7, Color(0.2, 0.2, 0.2))
	_poly(img, [Vector2(15, 20), Vector2(49, 20), Vector2(47, 40), Vector2(17, 40)], Color(0.3, 0.35, 0.26), 0.3)
	_r(img, 21, 25, 6, 2, Color(0.1, 0.1, 0.1))
	_r(img, 37, 25, 6, 2, Color(0.1, 0.1, 0.1))
	_circ(img, 32, 31, 5, Color(0.13, 0.13, 0.13))
	_circ(img, 32, 31, 2, Color(0, 0, 0))
	return img


static func _alarm(k: int) -> Image:
	var img := _new()
	_r(img, 22, 60, 20, 4, Color(0.3, 0.3, 0.32))
	_r(img, 29, 28, 6, 33, Color(0.45, 0.46, 0.5))
	_poly(img, [Vector2(16, 12), Vector2(48, 12), Vector2(48, 34), Vector2(16, 34)], Color(0.26, 0.26, 0.29), 0.3)
	for i in 4:
		_r(img, 20, 22 + i * 3, 24, 1, Color(0.1, 0.1, 0.1))
	var dome := Color(1, 0.12, 0.08)
	if k == 1:
		dome = Color(0.5, 0.04, 0.04)
	elif k == 2:
		dome = Color(0.15, 0.7, 0.25)
	_circ(img, 32, 11, 8, dome)
	if k != 1:
		_circ(img, 29.5, 8.5, 3, dome.lightened(0.5))
	_r(img, 18, 32, 28, 2, Color(0.9, 0.75, 0.1) if k != 2 else Color(0.3, 0.3, 0.3))
	return img


static func _server(k: int) -> Image:
	var img := _new()
	_poly(img, [Vector2(12, 2), Vector2(52, 2), Vector2(52, 64), Vector2(12, 64)], Color(0.15, 0.17, 0.23), 0.2)
	_r(img, 12, 2, 2, 62, Color(0.3, 0.33, 0.4))
	_r(img, 50, 2, 2, 62, Color(0.3, 0.33, 0.4))
	for row in 8:
		var y := 7 + row * 7
		_r(img, 16, y, 32, 5, Color(0.24, 0.27, 0.33))
		_r(img, 18, y + 2, 14, 1, Color(0.1, 0.1, 0.12))
		if k == 2:
			continue
		for l in 4:
			var on := _h(row, l, k + 3) > 0.4
			var c := Color(0.2, 1.0, 0.35) if (row + l) % 3 != 0 else Color(0.3, 0.7, 1.0)
			_r(img, 36 + l * 3, y + 1, 2, 2, c if on else Color(0.08, 0.12, 0.1))
	if k == 2:
		for i in 18:
			var x := 14.0 + _h(i, 1, 9) * 36.0
			var y := 4.0 + _h(i, 2, 9) * 56.0
			_circ(img, x, y, 1.5 + _h(i, 3, 9) * 3.0, Color(0.05, 0.05, 0.05) if i % 3 else Color(1, 0.5, 0.1))
	return img


static func _shell() -> Image:
	var img := _new()
	_circ(img, 32, 32, 12, Color(1.0, 0.45, 0.1))
	_circ(img, 32, 32, 7, Color(1.0, 0.95, 0.6))
	return img


static func _explosion(k: int) -> Image:
	var img := _new()
	var radii := [16.0, 24.0, 29.0]
	var r: float = radii[k]
	for y in T:
		for x in T:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(32, 32))
			var n := _h(x / 3, y / 3, 40 + k)
			if d > r * (0.75 + 0.25 * n):
				continue
			var t := d / r
			var c: Color
			if k == 2:
				if n > 0.6:
					continue
				c = Color(0.35, 0.33, 0.3).lerp(Color(0.8, 0.4, 0.1), (1.0 - t) * 0.5)
			elif t < 0.35:
				c = Color(1, 1, 0.8)
			elif t < 0.65:
				c = Color(1, 0.75, 0.2)
			else:
				c = Color(0.9, 0.3, 0.05)
			img.set_pixel(x, y, c)
	return img


## Soft round sprite with alpha falloff (smoke, dust, puff).
static func _soft(c: Color, r: float, density: float) -> Image:
	var img := _new()
	for y in T:
		for x in T:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(32, 34))
			var n := _h(x / 3, y / 3, 61)
			var a := clampf(1.0 - d / (r * (0.8 + 0.3 * n)), 0.0, 1.0)
			if a <= 0.0:
				continue
			var shade := 1.0 + 0.25 * (34.0 - y) / r
			img.set_pixel(x, y, Color(c.r * shade, c.g * shade, c.b * shade, minf(1.0, a * 1.6) * density))
	return img


static func _splat(c: Color, r: float) -> Image:
	var img := _new()
	for y in T:
		for x in T:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(32, 32))
			if d < r and _h(x / 2, y / 2, 91) > 0.3:
				img.set_pixel(x, y, c)
	return img


static func _tracer() -> Image:
	var img := _new()
	for y in T:
		for x in T:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(32, 32))
			if d < 10.0:
				var a := 1.0 - d / 10.0
				img.set_pixel(x, y, Color(1.0, 0.9, 0.5 + a * 0.5, 1.0 if d < 5.0 else a))
	return img


# ---------------------------------------------------------------- props

static func _tree() -> Image:
	var img := _new()
	var bark := Color(0.32, 0.22, 0.14)
	_poly(img, [Vector2(28, 36), Vector2(36, 36), Vector2(38, 64), Vector2(26, 64)], bark, 0.1)
	_line(img, Vector2(32, 44), Vector2(22, 34), 3, bark)
	_line(img, Vector2(33, 42), Vector2(44, 32), 3, bark)
	var g := Color(0.17, 0.32, 0.12)
	for c in [Vector3(32, 24, 17), Vector3(19, 30, 12), Vector3(45, 30, 12), Vector3(32, 11, 11), Vector3(24, 16, 9), Vector3(41, 16, 9)]:
		_circ(img, c.x, c.y, c.z, g.darkened(0.25))
	for c in [Vector3(30, 22, 14), Vector3(18, 28, 9), Vector3(43, 28, 9), Vector3(30, 10, 8)]:
		_circ(img, c.x, c.y, c.z, g)
	for i in 30:
		var x := 8.0 + _h(i, 1, 13) * 46.0
		var y := 4.0 + _h(i, 2, 13) * 36.0
		if img.get_pixel(int(x), int(y)).a > 0.5:
			_circ(img, x, y, 1.6, g.lightened(0.25) if y < 26 else g.darkened(0.35))
	return img


static func _pine() -> Image:
	var img := _new()
	_r(img, 29, 52, 6, 12, Color(0.3, 0.2, 0.12))
	var g := Color(0.1, 0.24, 0.16)
	for k in 4:
		var top := 4.0 + k * 11.0
		var half := 9.0 + k * 5.0
		_poly(img, [Vector2(32, top), Vector2(32 + half, top + 16), Vector2(32 - half, top + 16)], g, 0.25)
		_poly(img, [Vector2(32, top), Vector2(32 + half * 0.5, top + 7), Vector2(32 - half * 0.5, top + 7)], Color(0.9, 0.92, 0.96), 0.0)
		_r(img, int(32 - half), int(top + 14), int(half * 2), 2, Color(0.88, 0.9, 0.95))
	return img


static func _deadtree() -> Image:
	var img := _new()
	var c := Color(0.35, 0.3, 0.26)
	_line(img, Vector2(32, 64), Vector2(32, 18), 5, c)
	_line(img, Vector2(32, 40), Vector2(18, 26), 3, c)
	_line(img, Vector2(32, 34), Vector2(46, 20), 3, c)
	_line(img, Vector2(32, 22), Vector2(24, 8), 2, c)
	_line(img, Vector2(46, 20), Vector2(52, 10), 2, c)
	return img


static func _bush(g: Color) -> Image:
	var img := _new()
	for c in [Vector3(22, 52, 11), Vector3(40, 50, 13), Vector3(31, 44, 11)]:
		_circ(img, c.x, c.y, c.z, g.darkened(0.2))
	for c in [Vector3(21, 50, 8), Vector3(39, 48, 10), Vector3(30, 42, 8)]:
		_circ(img, c.x, c.y, c.z, g)
	for i in 12:
		_circ(img, 14.0 + _h(i, 1, 17) * 36.0, 38.0 + _h(i, 2, 17) * 20.0, 1.5, g.lightened(0.25))
	for y in range(60, 64):
		for x in T:
			img.set_pixel(x, y, Color(0, 0, 0, 0))
	return img


static func _cactus() -> Image:
	var img := _new()
	var g := Color(0.3, 0.5, 0.25)
	_poly(img, [Vector2(27, 6), Vector2(37, 6), Vector2(38, 64), Vector2(26, 64)], g, 0.25)
	_line(img, Vector2(27, 36), Vector2(16, 36), 7, g)
	_line(img, Vector2(16, 37), Vector2(16, 20), 7, g)
	_line(img, Vector2(37, 30), Vector2(48, 30), 7, g)
	_line(img, Vector2(48, 31), Vector2(48, 14), 7, g)
	for y in range(8, 62, 4):
		_r(img, 31, y, 1, 2, g.darkened(0.35))
	return img


static func _crate() -> Image:
	var img := _new()
	var w := Color(0.55, 0.4, 0.22)
	_poly(img, [Vector2(10, 22), Vector2(54, 22), Vector2(54, 64), Vector2(10, 64)], w, 0.2)
	for y in [22, 36, 50]:
		_r(img, 10, y, 44, 2, w.darkened(0.35))
	_r(img, 10, 22, 3, 42, w.darkened(0.3))
	_r(img, 51, 22, 3, 42, w.darkened(0.3))
	_line(img, Vector2(13, 24), Vector2(51, 62), 3, w.darkened(0.2))
	_r(img, 24, 40, 16, 6, Color(0.15, 0.15, 0.15))
	return img


static func _barrel() -> Image:
	var img := _new()
	var c := Color(0.45, 0.12, 0.08)
	_poly(img, [Vector2(18, 20), Vector2(46, 20), Vector2(48, 42), Vector2(46, 64), Vector2(18, 64), Vector2(16, 42)], c, 0.2)
	for y in [24, 42, 60]:
		_r(img, 16, y, 32, 2, c.darkened(0.4))
	_r(img, 22, 30, 6, 30, c.lightened(0.2))
	_r(img, 26, 46, 12, 6, Color(0.9, 0.75, 0.1))
	return img


static func _carwreck() -> Image:
	var img := _new()
	var rust := Color(0.4, 0.25, 0.16)
	_poly(img, [Vector2(2, 42), Vector2(14, 40), Vector2(20, 28), Vector2(44, 28), Vector2(52, 40), Vector2(62, 42), Vector2(62, 56), Vector2(2, 56)], rust, 0.2)
	_poly(img, [Vector2(23, 31), Vector2(32, 31), Vector2(32, 40), Vector2(18, 40)], Color(0.05, 0.05, 0.06), 0.0)
	_poly(img, [Vector2(35, 31), Vector2(42, 31), Vector2(48, 40), Vector2(35, 40)], Color(0.05, 0.05, 0.06), 0.0)
	_circ(img, 15, 56, 7, Color(0.08, 0.08, 0.08))
	_circ(img, 49, 56, 7, Color(0.08, 0.08, 0.08))
	for i in 14:
		_circ(img, 4.0 + _h(i, 1, 23) * 56.0, 30.0 + _h(i, 2, 23) * 24.0, 2.0, Color(0.12, 0.1, 0.09) if i % 2 else rust.lightened(0.2))
	return img


static func _rubble() -> Image:
	var img := _new()
	for i in 16:
		var x := 8.0 + _h(i, 1, 31) * 48.0
		var y := 46.0 + _h(i, 2, 31) * 14.0
		var c := Color(0.5, 0.45, 0.4) if i % 3 else Color(0.5, 0.25, 0.18)
		_poly(img, [Vector2(x - 5, y + 4), Vector2(x - 2, y - 3), Vector2(x + 4, y - 2), Vector2(x + 6, y + 4)], c.darkened(_h(i, 3, 31) * 0.3), 0.3)
	return img


static func _grass() -> Image:
	var img := _new()
	for i in 14:
		var x := 18.0 + _h(i, 1, 41) * 28.0
		_line(img, Vector2(x, 64), Vector2(x + (_h(i, 2, 41) - 0.5) * 14.0, 44.0 + _h(i, 3, 41) * 10.0), 1.5, Color(0.25, 0.42, 0.16).lightened(_h(i, 4, 41) * 0.2))
	return img


static func _drybush() -> Image:
	var img := _new()
	for i in 22:
		var a := Vector2(32 + (_h(i, 1, 51) - 0.5) * 20.0, 60)
		var b := a + Vector2((_h(i, 2, 51) - 0.5) * 34.0, -8.0 - _h(i, 3, 51) * 20.0)
		_line(img, a, b, 1.5, Color(0.55, 0.45, 0.3).darkened(_h(i, 4, 51) * 0.3))
	return img


static func _sandbag() -> Image:
	var img := _new()
	_sandbag_row(img, 56, 6, 2)
	_sandbag_row(img, 49, 5, 7)
	return img




# ---------------------------------------------------------------- objective props

static func _keydoor_px(x: int, y: int, n: float) -> Color:
	if x < 4 or x > 59 or y < 3:
		return Color(0.3, 0.3, 0.33) * (0.9 + 0.1 * n)
	if x >= 44 and x <= 54 and y >= 26 and y <= 40:
		if x == 44 or x == 54 or y == 26 or y == 40:
			return Color(0.1, 0.1, 0.1)
		if (x - 46) % 3 == 0 and (y - 29) % 3 == 0 and y < 38:
			return Color(0.2, 0.9, 0.4)
		return Color(0.15, 0.17, 0.2)
	if Vector2(x, y).distance_to(Vector2(49, 17)) < 4.0:
		return Color(0.95, 0.8, 0.15)
	var stripe := 0.85 if (y / 8) % 2 == 0 else 1.0
	if x >= 7 and x <= 40 and y >= 6 and y <= 58:
		if x == 7 or x == 40 or y == 6 or y == 58:
			return Color(0.2, 0.2, 0.2)
		return Color(0.5, 0.45, 0.28) * stripe * (0.92 + 0.08 * n)
	return Color(0.32, 0.33, 0.36) * (0.92 + 0.08 * n)


static func _key(c: Color) -> Image:
	var img := _new()
	_circ(img, 20, 44, 11, c)
	_circ(img, 20, 44, 5, Color(0, 0, 0, 0))
	_r(img, 29, 41, 27, 7, c)
	_r(img, 47, 48, 5, 8, c)
	_r(img, 38, 48, 4, 6, c)
	_r(img, 29, 41, 27, 2, c.lightened(0.45))
	_circ(img, 16, 38, 2.5, c.lightened(0.6))
	return img


static func _loot(k: int) -> Image:
	var img := _new()
	match k:
		0:
			for i in 4:
				_poly(img, [Vector2(12, 50 - i * 5), Vector2(52, 50 - i * 5), Vector2(54, 56 - i * 5), Vector2(10, 56 - i * 5)], Color(0.35, 0.6, 0.3), 0.2)
			_r(img, 28, 36, 8, 20, Color(0.9, 0.85, 0.6))
			_r(img, 18, 41, 4, 4, Color(0.2, 0.4, 0.2))
		1:
			_poly(img, [Vector2(16, 44), Vector2(48, 44), Vector2(56, 58), Vector2(8, 58)], Color(0.95, 0.75, 0.15), 0.4)
			_poly(img, [Vector2(20, 36), Vector2(44, 36), Vector2(48, 44), Vector2(16, 44)], Color(1.0, 0.85, 0.3), 0.3)
			_r(img, 22, 46, 20, 2, Color(1, 0.95, 0.7))
		2:
			_poly(img, [Vector2(12, 40), Vector2(52, 40), Vector2(52, 60), Vector2(12, 60)], Color(0.42, 0.22, 0.12), 0.2)
			_poly(img, [Vector2(10, 32), Vector2(54, 32), Vector2(52, 40), Vector2(12, 40)], Color(0.5, 0.28, 0.15), 0.2)
			_r(img, 12, 46, 40, 2, Color(0.85, 0.7, 0.2))
			_circ(img, 22, 31, 4, Color(0.9, 0.1, 0.2))
			_circ(img, 32, 29, 5, Color(0.2, 0.6, 1.0))
			_circ(img, 42, 31, 4, Color(0.2, 0.9, 0.4))
			_circ(img, 31, 27, 1.5, Color(1, 1, 1))
		3:
			_poly(img, [Vector2(14, 34), Vector2(50, 34), Vector2(52, 60), Vector2(12, 60)], Color(0.82, 0.72, 0.5), 0.2)
			_r(img, 12, 44, 40, 6, Color(0.8, 0.12, 0.1))
			_r(img, 16, 38, 16, 2, Color(0.3, 0.25, 0.2))
			_r(img, 16, 53, 24, 2, Color(0.3, 0.25, 0.2))
		4:
			var g := Color(1.0, 0.8, 0.2)
			_poly(img, [Vector2(18, 54), Vector2(46, 54), Vector2(48, 62), Vector2(16, 62)], Color(0.35, 0.3, 0.25), 0.2)
			_poly(img, [Vector2(24, 28), Vector2(40, 28), Vector2(44, 54), Vector2(20, 54)], g, 0.4)
			_circ(img, 32, 20, 8, g)
			_r(img, 28, 18, 2, 2, Color(0.9, 0.1, 0.1))
			_r(img, 34, 18, 2, 2, Color(0.9, 0.1, 0.1))
			_line(img, Vector2(24, 32), Vector2(16, 22), 4, g)
			_line(img, Vector2(40, 32), Vector2(48, 22), 4, g)
			_circ(img, 29, 16, 2, Color(1, 1, 0.8))
		5:
			_poly(img, [Vector2(20, 30), Vector2(44, 30), Vector2(52, 50), Vector2(46, 62), Vector2(18, 62), Vector2(12, 50)], Color(0.55, 0.42, 0.26), 0.3)
			_r(img, 26, 26, 12, 6, Color(0.4, 0.3, 0.18))
			_r(img, 30, 38, 4, 18, Color(0.95, 0.85, 0.3))
			_r(img, 26, 40, 12, 3, Color(0.95, 0.85, 0.3))
			_r(img, 26, 50, 12, 3, Color(0.95, 0.85, 0.3))
	return img


static func _grenade(smoke: bool) -> Image:
	var img := _new()
	if smoke:
		_poly(img, [Vector2(24, 34), Vector2(40, 34), Vector2(40, 60), Vector2(24, 60)], Color(0.45, 0.47, 0.5), 0.4)
		_r(img, 24, 40, 16, 4, Color(0.9, 0.9, 0.9))
		_r(img, 28, 28, 8, 6, Color(0.3, 0.3, 0.3))
	else:
		_circ(img, 32, 48, 12, Color(0.3, 0.36, 0.22))
		for i in 3:
			_r(img, 21, 42 + i * 5, 22, 1, Color(0.18, 0.22, 0.13))
		_r(img, 28, 32, 8, 6, Color(0.35, 0.35, 0.37))
		_line(img, Vector2(36, 34), Vector2(42, 44), 2, Color(0.35, 0.35, 0.37))
	return img


static func _terminal(k: int) -> Image:
	var img := _new()
	_poly(img, [Vector2(14, 30), Vector2(50, 30), Vector2(54, 64), Vector2(10, 64)], Color(0.28, 0.3, 0.34), 0.3)
	_poly(img, [Vector2(16, 6), Vector2(48, 6), Vector2(48, 32), Vector2(16, 32)], Color(0.18, 0.19, 0.22), 0.2)
	var scrs := [Color(0.05, 0.2, 0.08), Color(0.03, 0.12, 0.2), Color(0.05, 0.3, 0.1)]
	var scr: Color = scrs[k]
	_r(img, 19, 9, 26, 20, scr)
	if k == 0:
		var g := Color(0.3, 1.0, 0.4)
		for i in 3:
			var x := 22 + i * 8
			_poly(img, [Vector2(x + 3, 13), Vector2(x + 6, 18), Vector2(x, 18)], g, 0.0)
		_r(img, 21, 23, 22, 2, g)
	elif k == 1:
		for x in range(20, 44):
			var y := 19.0 + sin(float(x) * 0.6) * 5.0
			_r(img, x, int(y), 1, 2, Color(0.3, 0.85, 1.0))
	else:
		_line(img, Vector2(24, 19), Vector2(30, 25), 2, Color(0.4, 1.0, 0.5))
		_line(img, Vector2(30, 25), Vector2(41, 12), 2, Color(0.4, 1.0, 0.5))
	for i in 4:
		_r(img, 16 + i * 9, 40, 6, 4, [Color(0.9, 0.2, 0.2), Color(0.9, 0.8, 0.2), Color(0.2, 0.8, 0.3), Color(0.3, 0.5, 0.9)][i])
	return img


## Plate carrier vest: dark kevlar body, shoulder straps, neck cut, two magazine pouches, a lighter armour plate.
static func _armor_vest() -> Image:
	var img := _new()
	var k := Color(0.2, 0.25, 0.3)
	var kd := k.darkened(0.35)
	# body (front panel with a neck cut-out)
	_poly(img, [Vector2(14, 22), Vector2(24, 22), Vector2(32, 30), Vector2(40, 22), Vector2(50, 22), Vector2(52, 60), Vector2(12, 60)], k, 0.2)
	# shoulder straps
	_r(img, 14, 14, 9, 10, kd)
	_r(img, 41, 14, 9, 10, kd)
	# armour plate
	_poly(img, [Vector2(20, 32), Vector2(44, 32), Vector2(43, 47), Vector2(21, 47)], Color(0.38, 0.45, 0.52), 0.15)
	_r(img, 22, 34, 20, 2, Color(0.55, 0.62, 0.7))
	# pouches with mags
	for i in 3:
		_r(img, 15 + i * 12, 49, 10, 9, Color(0.27, 0.31, 0.24))
		_r(img, 17 + i * 12, 46, 6, 4, GUN)
		_r(img, 15 + i * 12, 49, 10, 2, Color(0.34, 0.38, 0.3))
	# side straps + buckles
	_r(img, 12, 40, 3, 12, kd)
	_r(img, 49, 40, 3, 12, kd)
	_r(img, 12, 44, 3, 3, Color(0.6, 0.6, 0.55))
	_r(img, 49, 44, 3, 3, Color(0.6, 0.6, 0.55))
	# shield badge
	_poly(img, [Vector2(28, 37), Vector2(36, 37), Vector2(36, 41), Vector2(32, 45), Vector2(28, 41)], Color(0.35, 0.75, 1.0))
	return img


static func _ammo_crate() -> Image:
	var img := _new()
	var o := Color(0.33, 0.37, 0.22)
	_poly(img, [Vector2(6, 34), Vector2(58, 34), Vector2(58, 64), Vector2(6, 64)], o, 0.25)
	_poly(img, [Vector2(4, 28), Vector2(60, 28), Vector2(58, 34), Vector2(6, 34)], o.lightened(0.15), 0.1)
	_r(img, 18, 44, 28, 10, Color(0.9, 0.78, 0.2))
	for i in 5:
		_r(img, 21 + i * 5, 46, 3, 6, Color(0.55, 0.4, 0.15))
		_r(img, 21 + i * 5, 44, 3, 2, Color(0.75, 0.55, 0.2))
	_r(img, 6, 40, 4, 8, Color(0.15, 0.15, 0.15))
	_r(img, 54, 40, 4, 8, Color(0.15, 0.15, 0.15))
	return img


# ---------------------------------------------------------------- first-person weapons (perspective view models)

static func _vseg(img: Image, B: Vector2, M: Vector2, t0: float, t1: float, w0: float, w1: float, c: Color, off := 0.0, grad := 0.3) -> void:
	var d := (M - B).normalized()
	var nn := Vector2(-d.y, d.x)
	var a := B.lerp(M, t0) + nn * off
	var b := B.lerp(M, t1) + nn * off
	_poly(img, [a - nn * w0, b - nn * w1, b + nn * w1, a + nn * w0], c, grad)


static func _blob(img: Image, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts: Array = []
	for i in 16:
		var a := TAU * float(i) / 16.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	_poly(img, pts, col, 0.25)


static func _hand(img: Image, c: Vector2, rx: float, ry: float) -> void:
	_blob(img, c, rx, ry, SKIN)
	for k in 3:
		var y := -ry * 0.35 + k * ry * 0.35
		_line(img, c + Vector2(-rx * 0.65, y), c + Vector2(rx * 0.45, y + ry * 0.1), 1.2, SKIN.darkened(0.25))


## Returns one entry per weapon id: {"tex", "sleeves" (polys in texture space), "muzzle"}.
## The weapon sits low-right and its barrel points INTO the screen toward the crosshair.
static func make_weapons() -> Array:
	var out: Array = []
	var metal := Color(0.17, 0.18, 0.2)
	var dark := Color(0.09, 0.09, 0.1)
	var wood := Color(0.42, 0.27, 0.14)
	var poly := Color(0.25, 0.27, 0.23)
	for w in 8:
		var img := _new(VM, VM)
		var sleeves: Array = []
		var B := Vector2(100, 178)
		var M := Vector2(72, 34)
		var lh := 0.58
		var long_gun := w >= Defs.W_RIFLE
		if w == Defs.W_KNIFE:
			B = Vector2(126, 176)
			M = Vector2(92, 46)
			var hc := B.lerp(M, 0.17)
			sleeves.append([hc + Vector2(-12, 10), hc + Vector2(16, 2), Vector2(160, 138), Vector2(160, 160), Vector2(112, 160)])
			_vseg(img, B, M, 0.1, 0.36, 7, 6, Color(0.3, 0.2, 0.12))
			_vseg(img, B, M, 0.35, 0.39, 15, 15, Color(0.22, 0.22, 0.24))
			_vseg(img, B, M, 0.39, 1.0, 7, 0.6, Color(0.72, 0.75, 0.8), 0.0, 0.45)
			_vseg(img, B, M, 0.4, 0.97, 1.6, 0.3, Color(0.96, 0.97, 1.0), -3.8, 0.0)
			_hand(img, hc, 16, 13)
		elif w == Defs.W_PISTOL or w == Defs.W_REVOLVER:
			B = Vector2(84, 178)
			M = Vector2(84, 74) if w == Defs.W_PISTOL else Vector2(84, 66)
			sleeves.append([Vector2(10, 160), Vector2(56, 160), Vector2(72, 132), Vector2(58, 122)])
			sleeves.append([Vector2(112, 160), Vector2(158, 160), Vector2(112, 122), Vector2(98, 132)])
			if w == Defs.W_PISTOL:
				_vseg(img, B, M, 0.42, 1.0, 16, 13, Color(0.24, 0.24, 0.26), 0.0, 0.35)
				_vseg(img, B, M, 0.44, 1.0, 5, 4, Color(0.44, 0.44, 0.47), 0.0, 0.1)
				for k in 4:
					_vseg(img, B, M, 0.46 + k * 0.03, 0.475 + k * 0.03, 15, 15, Color(0.15, 0.15, 0.16), 0.0, 0.0)
				_vseg(img, B, M, 0.5, 0.56, 3, 3, dark, -9.0)
				_vseg(img, B, M, 0.5, 0.56, 3, 3, dark, 9.0)
				_vseg(img, B, M, 0.94, 1.0, 2.5, 2.5, dark)
			else:
				_vseg(img, B, M, 0.36, 0.44, 4, 4, dark)
				_vseg(img, B, M, 0.42, 0.62, 20, 18, Color(0.2, 0.2, 0.22), 0.0, 0.35)
				for k in 3:
					_vseg(img, B, M, 0.44, 0.6, 1.2, 1.2, Color(0.1, 0.1, 0.1), -10.0 + k * 10.0, 0.0)
				_vseg(img, B, M, 0.6, 1.0, 7, 6, metal, 0.0, 0.3)
				_vseg(img, B, M, 0.6, 1.0, 2, 2, Color(0.42, 0.42, 0.45), 0.0, 0.0)
				_vseg(img, B, M, 0.95, 1.0, 2.5, 2.5, dark)
			_hand(img, Vector2(68, 136), 20, 18)
			_hand(img, Vector2(100, 136), 20, 18)
			_line(img, Vector2(72, 122), Vector2(82, 112), 7, SKIN)
			_line(img, Vector2(96, 122), Vector2(86, 112), 7, SKIN.darkened(0.08))
		else:
			B = Vector2(128, 184)
			if w == Defs.W_SMG:
				M = Vector2(80, 58)
				lh = -1.0
			elif w == Defs.W_SHOTGUN:
				M = Vector2(74, 38)
				lh = 0.55
			elif w == Defs.W_SNIPER:
				M = Vector2(74, 26)
				lh = 0.52
			elif w == Defs.W_LMG:
				M = Vector2(70, 44)
				lh = 0.5
			var d := (M - B).normalized()
			var nn := Vector2(-d.y, d.x)
			var P := func(t: float) -> Vector2: return B.lerp(M, t)
			# magazines go under everything
			if w == Defs.W_RIFLE:
				_poly(img, [P.call(0.17) - nn * 15, P.call(0.3) - nn * 14, P.call(0.28) - nn * 28 + Vector2(0, 30), P.call(0.15) - nn * 31 + Vector2(0, 30)], Color(0.14, 0.14, 0.15), 0.3)
			elif w == Defs.W_SMG:
				var c0: Vector2 = P.call(0.42)
				_poly(img, [c0 + Vector2(-6, 6), c0 + Vector2(6, 6), c0 + Vector2(4, 52), c0 + Vector2(-8, 52)], Color(0.12, 0.12, 0.13), 0.3)
			elif w == Defs.W_LMG:
				_poly(img, [P.call(0.12) - nn * 18, P.call(0.34) - nn * 16, P.call(0.32) - nn * 42 + Vector2(0, 26), P.call(0.1) - nn * 46 + Vector2(0, 26)], Color(0.3, 0.33, 0.22), 0.3)
				_line(img, P.call(0.2) - nn * 16, P.call(0.22) - nn * 4, 3, Color(0.8, 0.65, 0.25))
			elif w == Defs.W_SNIPER:
				_vseg(img, B, M, 0.36, 0.62, 13, 10, wood, 0.0, 0.3)
			# body
			var rec_end: float = {Defs.W_RIFLE: 0.42, Defs.W_SMG: 0.6, Defs.W_SHOTGUN: 0.34, Defs.W_SNIPER: 0.38, Defs.W_LMG: 0.45}[w]
			var rec_w: float = {Defs.W_RIFLE: 28.0, Defs.W_SMG: 26.0, Defs.W_SHOTGUN: 27.0, Defs.W_SNIPER: 24.0, Defs.W_LMG: 34.0}[w]
			var rec_c := metal if w != Defs.W_SNIPER else Color(0.26, 0.29, 0.21)
			_vseg(img, B, M, 0.0, rec_end, rec_w * 1.15, rec_w * 0.8, rec_c, 0.0, 0.35)
			_vseg(img, B, M, 0.03, rec_end, rec_w * 0.22, rec_w * 0.16, rec_c.lightened(0.14), 0.0, 0.1)
			if w == Defs.W_RIFLE:
				_vseg(img, B, M, 0.36, 0.42, 9, 8, dark)
				_vseg(img, B, M, 0.42, 0.74, 17, 12, poly, 0.0, 0.3)
				for k in 4:
					_vseg(img, B, M, 0.46 + k * 0.065, 0.48 + k * 0.065, 11, 8, poly.darkened(0.4), 0.0, 0.0)
				_vseg(img, B, M, 0.74, 0.97, 4, 3.2, dark)
				var fs: Vector2 = P.call(0.9)
				_poly(img, [fs + Vector2(-2, 0), fs + Vector2(2, 0), fs + Vector2(2, -9), fs + Vector2(-2, -9)], dark, 0.0)
				_vseg(img, B, M, 0.95, 1.0, 5, 5, dark)
			elif w == Defs.W_SMG:
				_vseg(img, B, M, 0.6, 0.86, 9, 7, Color(0.16, 0.16, 0.17), 0.0, 0.3)
				for k in 3:
					var hp: Vector2 = P.call(0.64 + k * 0.07)
					_circ(img, hp.x, hp.y, 2, Color(0.05, 0.05, 0.05))
				_vseg(img, B, M, 0.86, 1.0, 3.5, 3, dark)
			elif w == Defs.W_SHOTGUN:
				_vseg(img, B, M, 0.34, 0.97, 6, 5, dark, 4.0)
				_vseg(img, B, M, 0.34, 1.0, 6, 5, metal, -4.0, 0.3)
				_vseg(img, B, M, 0.42, 0.66, 19, 15, wood, 0.0, 0.3)
				for k in 5:
					_vseg(img, B, M, 0.44 + k * 0.045, 0.455 + k * 0.045, 18, 15, wood.darkened(0.35), 0.0, 0.0)
				var bead: Vector2 = P.call(0.99) - nn * 4
				_circ(img, bead.x, bead.y, 2, Color(1, 0.85, 0.3))
			elif w == Defs.W_SNIPER:
				_vseg(img, B, M, 0.38, 1.0, 5, 3.5, dark)
				_vseg(img, B, M, 0.05, 0.42, 12, 10, Color(0.08, 0.08, 0.09), 0.0, 0.3)
				for t in [0.13, 0.33]:
					_vseg(img, B, M, t, t + 0.03, 15, 14, dark)
				var lens: Vector2 = P.call(0.05)
				_circ(img, lens.x, lens.y, 12, Color(0.06, 0.06, 0.07))
				_circ(img, lens.x, lens.y, 8, Color(0.1, 0.22, 0.38))
				_circ(img, lens.x - 3, lens.y - 3, 2.5, Color(0.6, 0.8, 1.0))
				var bolt: Vector2 = P.call(0.16) + nn * 16
				_line(img, bolt, bolt + nn * 12, 4, metal)
				_circ(img, (bolt + nn * 13).x, (bolt + nn * 13).y, 4, dark)
			elif w == Defs.W_LMG:
				_vseg(img, B, M, 0.08, 0.38, 14, 11, Color(0.3, 0.31, 0.3), 0.0, 0.2)
				_vseg(img, B, M, 0.45, 0.86, 9, 7, Color(0.17, 0.17, 0.17), 0.0, 0.3)
				for k in 5:
					var hp: Vector2 = P.call(0.5 + k * 0.07)
					_circ(img, hp.x, hp.y, 1.8, Color(0.05, 0.05, 0.05))
				_vseg(img, B, M, 0.86, 1.0, 4, 3.5, dark)
				var bp: Vector2 = P.call(0.82)
				_line(img, bp, bp + Vector2(-9, 12), 2, dark)
				_line(img, bp, bp + Vector2(9, 12), 2, dark)
			# hands
			var rh: Vector2 = P.call(0.25) + nn * 17
			sleeves.append([rh + Vector2(-12, 6), rh + Vector2(10, -6), Vector2(160, rh.y + 4), Vector2(160, 160), Vector2(rh.x - 18, 160)])
			var lhp: Vector2
			if lh < 0.0:
				lhp = P.call(0.42) + Vector2(-3, 20)
			else:
				lhp = P.call(lh) - nn * 10 + Vector2(-2, 9)
			sleeves.append([lhp + Vector2(-13, 6), lhp + Vector2(10, 12), Vector2(58, 160), Vector2(0, 160), Vector2(0, 148)])
			_hand(img, lhp, 12, 9)
			_hand(img, rh, 15, 13)
		var fin := _finish(img, true, 900 + w)
		var sl: Array = []
		for s in sleeves:
			sl.append(PackedVector2Array(s))
		out.append({"tex": ImageTexture.create_from_image(fin), "sleeves": sl, "muzzle": M, "long": long_gun})
	return out


# ---------------------------------------------------------------- vehicle sprites (front, side a, side b, back)

static func _wheel(img: Image, cx: float, cy: float, r: float, ph: int) -> void:
	_circ(img, cx, cy, r, Color(0.1, 0.1, 0.1))
	_circ(img, cx, cy, r * 0.55, Color(0.38, 0.38, 0.36))
	var a := float(ph) * 0.8
	_line(img, Vector2(cx, cy) + Vector2.from_angle(a) * r * 0.5, Vector2(cx, cy) - Vector2.from_angle(a) * r * 0.5, 1, Color(0.15, 0.15, 0.15))
	_line(img, Vector2(cx, cy) + Vector2.from_angle(a + 1.57) * r * 0.5, Vector2(cx, cy) - Vector2.from_angle(a + 1.57) * r * 0.5, 1, Color(0.15, 0.15, 0.15))


static func _rider(img: Image, x: float, y: float, col: Color) -> void:
	_poly(img, [Vector2(x - 4, y), Vector2(x + 4, y), Vector2(x + 5, y + 12), Vector2(x - 5, y + 12)], col.darkened(0.3))
	_circ(img, x, y - 4, 4, SKIN)
	_r(img, int(x - 5), int(y - 9), 10, 4, col.darkened(0.55))


static func _vehicle(vt: int, k: int, col: Color) -> Image:
	var img := _new()
	var dark := col.darkened(0.45)
	var ph := 1 if k == 2 else 0
	var side := k == 1 or k == 2
	match vt:
		1:  # BRONEVIKS - armoured car
			if side:
				_poly(img, [Vector2(4, 50), Vector2(8, 32), Vector2(48, 32), Vector2(60, 40), Vector2(60, 50)], col, 0.25)
				_camo(img, 4, 32, 56, 18, col.darkened(0.25), 31)
				_r(img, 14, 36, 8, 2, Color(0.08, 0.08, 0.08))
				_poly(img, [Vector2(20, 22), Vector2(38, 22), Vector2(40, 32), Vector2(18, 32)], dark, 0.3)
				_r(img, 38, 25, 22, 3, Color(0.15, 0.15, 0.16))
				for wx in [13.0, 31.0, 50.0]:
					_wheel(img, wx, 53, 8, ph)
			elif k == 0:
				_poly(img, [Vector2(10, 28), Vector2(54, 28), Vector2(56, 52), Vector2(8, 52)], col, 0.25)
				_poly(img, [Vector2(14, 22), Vector2(50, 22), Vector2(54, 28), Vector2(10, 28)], col.lightened(0.15), 0.1)
				_r(img, 18, 33, 28, 3, Color(0.06, 0.06, 0.06))
				_poly(img, [Vector2(22, 12), Vector2(42, 12), Vector2(44, 22), Vector2(20, 22)], dark, 0.3)
				_circ(img, 32, 17, 3, Color(0.05, 0.05, 0.05))
				_r(img, 5, 46, 9, 16, Color(0.1, 0.1, 0.1))
				_r(img, 50, 46, 9, 16, Color(0.1, 0.1, 0.1))
				_r(img, 12, 41, 5, 3, Color(1, 0.9, 0.6))
				_r(img, 47, 41, 5, 3, Color(1, 0.9, 0.6))
			else:
				_poly(img, [Vector2(10, 26), Vector2(54, 26), Vector2(56, 52), Vector2(8, 52)], col, 0.25)
				_poly(img, [Vector2(22, 12), Vector2(42, 12), Vector2(44, 26), Vector2(20, 26)], dark, 0.3)
				_circ(img, 32, 38, 8, Color(0.1, 0.1, 0.1))
				_circ(img, 32, 38, 4, Color(0.35, 0.35, 0.35))
				_r(img, 5, 46, 9, 16, Color(0.1, 0.1, 0.1))
				_r(img, 50, 46, 9, 16, Color(0.1, 0.1, 0.1))
		2:  # MOTORCYCLE with sidecar
			if side:
				_wheel(img, 14, 54, 8, ph)
				_wheel(img, 48, 54, 8, ph)
				_line(img, Vector2(14, 54), Vector2(30, 42), 3, Color(0.2, 0.2, 0.22))
				_line(img, Vector2(30, 42), Vector2(48, 54), 3, Color(0.2, 0.2, 0.22))
				_poly(img, [Vector2(22, 38), Vector2(42, 38), Vector2(44, 46), Vector2(20, 46)], col, 0.3)
				_line(img, Vector2(44, 40), Vector2(50, 30), 2, Color(0.25, 0.25, 0.25))
				_rider(img, 32, 22, col)
				_line(img, Vector2(36, 26), Vector2(48, 31), 3, col.darkened(0.3))
			else:
				_wheel(img, 22, 54, 7, 0)
				_r(img, 19, 40, 6, 14, Color(0.2, 0.2, 0.22))
				_r(img, 10, 34, 24, 3, Color(0.25, 0.25, 0.25))
				_rider(img, 22, 22, col)
				_poly(img, [Vector2(34, 42), Vector2(58, 42), Vector2(56, 56), Vector2(36, 56)], col, 0.3)
				_wheel(img, 46, 58, 5, 0)
				_rider(img, 46, 30, col)
				if k == 0:
					_r(img, 42, 24, 8, 3, Color(0.12, 0.12, 0.12))
					_circ(img, 22, 44, 2.5, Color(1, 0.9, 0.6))
		3:  # JEEP
			if side:
				_poly(img, [Vector2(4, 50), Vector2(6, 36), Vector2(58, 36), Vector2(60, 50)], col, 0.25)
				_camo(img, 4, 36, 56, 14, col.darkened(0.25), 41)
				_line(img, Vector2(42, 36), Vector2(38, 24), 2, Color(0.15, 0.15, 0.15))
				_r(img, 30, 23, 9, 2, Color(0.15, 0.15, 0.15))
				_rider(img, 32, 25, col)
				_line(img, Vector2(14, 36), Vector2(14, 22), 2, Color(0.2, 0.2, 0.2))
				_r(img, 8, 18, 18, 4, Color(0.12, 0.12, 0.12))
				_rider(img, 16, 24, col)
				_wheel(img, 14, 52, 8, ph)
				_wheel(img, 50, 52, 8, ph)
			else:
				_poly(img, [Vector2(8, 34), Vector2(56, 34), Vector2(56, 52), Vector2(8, 52)], col, 0.25)
				_r(img, 6, 46, 9, 14, Color(0.1, 0.1, 0.1))
				_r(img, 49, 46, 9, 14, Color(0.1, 0.1, 0.1))
				_rider(img, 24, 18, col)
				_rider(img, 40, 18, col)
				_r(img, 26, 8, 12, 3, Color(0.12, 0.12, 0.12))
				_line(img, Vector2(32, 10), Vector2(32, 34), 2, Color(0.2, 0.2, 0.2))
				if k == 0:
					_r(img, 12, 26, 40, 2, Color(0.2, 0.25, 0.3))
					for gx in range(22, 42, 4):
						_r(img, gx, 38, 2, 10, Color(0.08, 0.08, 0.08))
					_circ(img, 15, 40, 3, Color(1, 0.9, 0.6))
					_circ(img, 49, 40, 3, Color(1, 0.9, 0.6))
				else:
					_circ(img, 32, 42, 6, Color(0.1, 0.1, 0.1))
		4:  # ROCKET TRUCK
			if side:
				_poly(img, [Vector2(42, 26), Vector2(56, 26), Vector2(62, 36), Vector2(62, 50), Vector2(42, 50)], col, 0.25)
				_r(img, 46, 29, 9, 7, Color(0.2, 0.28, 0.35))
				_r(img, 2, 40, 42, 10, dark)
				for i in 4:
					_line(img, Vector2(6, 38 - i * 4), Vector2(38, 26 - i * 4), 3, Color(0.25, 0.27, 0.22))
					_circ(img, 39, 26 - i * 4, 1.5, Color(0.8, 0.3, 0.1))
				for wx in [10.0, 26.0, 52.0]:
					_wheel(img, wx, 53, 7, ph)
			elif k == 0:
				_poly(img, [Vector2(12, 22), Vector2(52, 22), Vector2(54, 52), Vector2(10, 52)], col, 0.25)
				_r(img, 16, 26, 32, 10, Color(0.2, 0.28, 0.35))
				for gx in range(18, 46, 4):
					_r(img, gx, 40, 2, 8, Color(0.08, 0.08, 0.08))
				_circ(img, 15, 44, 3, Color(1, 0.9, 0.6))
				_circ(img, 49, 44, 3, Color(1, 0.9, 0.6))
				_r(img, 6, 48, 9, 14, Color(0.1, 0.1, 0.1))
				_r(img, 49, 48, 9, 14, Color(0.1, 0.1, 0.1))
				for i in 4:
					_r(img, 14 + i * 9, 8, 7, 7, Color(0.25, 0.27, 0.22))
			else:
				_r(img, 8, 36, 48, 16, dark)
				for gy in 3:
					for gx in 4:
						_circ(img, 15 + gx * 11, 14 + gy * 9, 4, Color(0.25, 0.27, 0.22))
						_circ(img, 15 + gx * 11, 14 + gy * 9, 2, Color(0.05, 0.05, 0.05))
				_r(img, 6, 48, 9, 14, Color(0.1, 0.1, 0.1))
				_r(img, 49, 48, 9, 14, Color(0.1, 0.1, 0.1))
				_r(img, 10, 52, 4, 3, Color(0.8, 0.1, 0.1))
				_r(img, 50, 52, 4, 3, Color(0.8, 0.1, 0.1))
	return img
