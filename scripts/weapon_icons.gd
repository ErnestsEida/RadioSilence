extends Node
## Weapon icons: clean side views rendered from the first-person view models (viewmodel.gd,
## icon_pose) plus simple procedural equipment icons. Rendered once and cached in user://
## (bump CACHE_VERSION whenever a view model changes). Headless: no weapon icons (getters
## return null), equipment icons are still drawn (pure Image code).
##
##   var wi: Node = WeaponIcons.new(); add_child(wi); await wi.bake(); wi.queue_free()
##   WeaponIcons.weapon(id) (IW x IH), weapon_small(id) (SW x SH), equip(id), equip_small(id)

const VM := preload("res://scripts/viewmodel.gd")
const Defs := preload("res://scripts/defs.gd")

const CACHE_VERSION := 1
const IW := 192
const IH := 64
const SW := 84
const SH := 28
const SS := 2   # supersampling of the 3D render

static var _big: Array[Texture2D] = []
static var _small: Array[Texture2D] = []
static var _eq_big: Array[Texture2D] = []
static var _eq_small: Array[Texture2D] = []


static func weapon(id: int) -> Texture2D:
	return _big[id] if id >= 0 and id < _big.size() else null


static func weapon_small(id: int) -> Texture2D:
	return _small[id] if id >= 0 and id < _small.size() else null


static func equip(id: int) -> Texture2D:
	return _eq_big[id] if id >= 0 and id < _eq_big.size() else null


static func equip_small(id: int) -> Texture2D:
	return _eq_small[id] if id >= 0 and id < _eq_small.size() else null


static func cache_path() -> String:
	return "user://weapon_icons_v%d_%d.png" % [CACHE_VERSION, Defs.WPN.size()]


func bake(use_cache: bool = true) -> void:
	_make_equipment()
	if DisplayServer.get_name() == "headless":
		return
	var n: int = Defs.WPN.size()
	var atlas: Image = null
	var path := cache_path()
	if use_cache and FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and img.get_width() == IW and img.get_height() == IH * n:
			atlas = img
			if atlas.get_format() != Image.FORMAT_RGBA8:
				atlas.convert(Image.FORMAT_RGBA8)
	if atlas == null:
		atlas = await _render(n)
		if atlas == null:
			return
		atlas.save_png(path)
	_big.clear()
	_small.clear()
	for i in n:
		var im := atlas.get_region(Rect2i(0, i * IH, IW, IH))
		_big.append(ImageTexture.create_from_image(im))
		_small.append(ImageTexture.create_from_image(_shrink(im)))


func _render(n: int) -> Image:
	var vm: SubViewport = VM.new()
	vm.size = Vector2i(IW * SS, IH * SS)
	add_child(vm)
	vm.call("setup", Color(0.3, 0.35, 0.4))
	var atlas := Image.create(IW, IH * n, false, Image.FORMAT_RGBA8)
	for w in n:
		vm.call("icon_pose", w)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var shot := vm.get_texture().get_image()
		if shot == null or shot.is_empty():
			vm.queue_free()
			return null
		shot.convert(Image.FORMAT_RGBA8)
		atlas.blit_rect(_finish(shot), Rect2i(0, 0, IW, IH), Vector2i(0, w * IH))
	vm.queue_free()
	return atlas


## Crop to the visible pixels, fit into IW x IH (3 px margin), add a soft light outline.
func _finish(src: Image) -> Image:
	var used := src.get_used_rect()
	var out := Image.create(IW, IH, false, Image.FORMAT_RGBA8)
	if used.size.x <= 0 or used.size.y <= 0:
		return out
	var crop := src.get_region(used)
	var k := minf(float(IW - 6) / float(used.size.x), float(IH - 6) / float(used.size.y))
	var w := maxi(1, int(round(used.size.x * k)))
	var h := maxi(1, int(round(used.size.y * k)))
	crop.resize(w, h, Image.INTERPOLATE_LANCZOS)
	out.blit_rect(crop, Rect2i(0, 0, w, h), Vector2i((IW - w) / 2, (IH - h) / 2))
	return _outline(out, 0.55)


static func _outline(img: Image, strength: float) -> Image:
	var W := img.get_width()
	var H := img.get_height()
	var res := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for y in H:
		for x in W:
			var a := 0.0
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
				var px := x + d.x
				var py := y + d.y
				if px >= 0 and py >= 0 and px < W and py < H:
					a = maxf(a, img.get_pixel(px, py).a)
			var c := img.get_pixel(x, y)
			var o := Color(0.92, 0.9, 0.82, a * strength)
			res.set_pixel(x, y, o.blend(c))
	return res


## Small version: the visible part, scaled to fit SW x SH (1 px margin) and centred.
static func _shrink(im: Image) -> Image:
	var out := Image.create(SW, SH, false, Image.FORMAT_RGBA8)
	var used := im.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return out
	var crop := im.get_region(used)
	var k := minf(float(SW - 2) / float(used.size.x), float(SH - 2) / float(used.size.y))
	var w := maxi(1, int(round(used.size.x * k)))
	var h := maxi(1, int(round(used.size.y * k)))
	crop.resize(w, h, Image.INTERPOLATE_LANCZOS)
	out.blit_rect(crop, Rect2i(0, 0, w, h), Vector2i((SW - w) / 2, (SH - h) / 2))
	return out


# ------------------------------------------------------------ equipment ----

func _make_equipment() -> void:
	if not _eq_big.is_empty():
		return
	for e in Defs.EQUIP_NAMES.size():
		var img := Image.create(IW, IH, false, Image.FORMAT_RGBA8)
		match e:
			Defs.EQ_FRAG:
				_draw_frag(img)
			Defs.EQ_SMOKE:
				_draw_smoke(img)
			Defs.EQ_MEDKIT:
				_draw_medkit(img)
			_:
				_draw_ammo(img)
		var fin := _outline(img, 0.55)
		_eq_big.append(ImageTexture.create_from_image(fin))
		_eq_small.append(ImageTexture.create_from_image(_shrink(fin)))


## Shaded fill: light from the upper left.
static func _shade(c: Color, u: float, v: float) -> Color:
	return c.lightened(clampf(0.35 - 0.5 * u - 0.3 * v, 0.0, 0.5)) if u + v < 0.7 else c.darkened(clampf((u + v - 0.7) * 0.5, 0.0, 0.45))


static func _ellipse(img: Image, c: Vector2, rx: float, ry: float, col: Color) -> void:
	for y in range(int(c.y - ry) - 1, int(c.y + ry) + 2):
		for x in range(int(c.x - rx) - 1, int(c.x + rx) + 2):
			var dx := (float(x) + 0.5 - c.x) / rx
			var dy := (float(y) + 0.5 - c.y) / ry
			var d := dx * dx + dy * dy
			if d <= 1.0 and x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, _shade(col, (dx + 1.0) * 0.5, (dy + 1.0) * 0.5))


static func _rect(img: Image, r: Rect2, col: Color, shaded: bool = true, rad: float = 0.0) -> void:
	for y in range(int(r.position.y), int(r.end.y)):
		for x in range(int(r.position.x), int(r.end.x)):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			if rad > 0.0:
				var qx := clampf(float(x) + 0.5, r.position.x + rad, r.end.x - rad)
				var qy := clampf(float(y) + 0.5, r.position.y + rad, r.end.y - rad)
				if Vector2(float(x) + 0.5 - qx, float(y) + 0.5 - qy).length() > rad:
					continue
			var u := (float(x) - r.position.x) / maxf(r.size.x, 1.0)
			var v := (float(y) - r.position.y) / maxf(r.size.y, 1.0)
			img.set_pixel(x, y, _shade(col, u, v) if shaded else col)


static func _ring(img: Image, c: Vector2, r0: float, r1: float, col: Color) -> void:
	for y in range(int(c.y - r1) - 1, int(c.y + r1) + 2):
		for x in range(int(c.x - r1) - 1, int(c.x + r1) + 2):
			var d := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(c)
			if d >= r0 and d <= r1 and x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, col)


func _draw_frag(img: Image) -> void:
	var body := Color(0.3, 0.36, 0.2)
	_ellipse(img, Vector2(96, 38), 17, 21, body)
	for k in 3:
		_rect(img, Rect2(80, 27 + k * 9, 33, 2), body.darkened(0.45), false)
	for k in 3:
		_rect(img, Rect2(88 + k * 7, 18, 1, 40), body.darkened(0.35), false)
	_rect(img, Rect2(89, 11, 14, 8), Color(0.45, 0.46, 0.48), true, 1.5)
	_rect(img, Rect2(100, 12, 6, 30), Color(0.55, 0.56, 0.58), true, 1.5)   # spoon
	_ring(img, Vector2(85, 13), 3.5, 5.5, Color(0.7, 0.7, 0.72))           # pin ring


func _draw_smoke(img: Image) -> void:
	var can := Color(0.42, 0.45, 0.42)
	_rect(img, Rect2(82, 16, 28, 42), can, true, 3.0)
	_rect(img, Rect2(82, 28, 28, 6), Color(0.9, 0.9, 0.88), false)
	_rect(img, Rect2(82, 16, 28, 5), can.darkened(0.3), false)
	_rect(img, Rect2(88, 9, 16, 8), Color(0.45, 0.46, 0.48), true, 1.5)
	_rect(img, Rect2(101, 10, 6, 28), Color(0.55, 0.56, 0.58), true, 1.5)
	_ring(img, Vector2(85, 11), 3.5, 5.5, Color(0.7, 0.7, 0.72))
	for k in 3:
		_ellipse(img, Vector2(122 + k * 9, 20 - k * 4), 6 + k * 2, 5 + k, Color(0.75, 0.76, 0.78, 0.85))


func _draw_medkit(img: Image) -> void:
	_rect(img, Rect2(84, 8, 24, 8), Color(0.25, 0.25, 0.27), true, 3.0)
	_rect(img, Rect2(90, 11, 12, 6), Color(0, 0, 0, 0), false)
	_rect(img, Rect2(66, 15, 60, 42), Color(0.88, 0.88, 0.85), true, 5.0)
	_rect(img, Rect2(66, 30, 60, 3), Color(0.6, 0.6, 0.58), false)
	_rect(img, Rect2(91, 21, 10, 30), Color(0.85, 0.12, 0.1), false)
	_rect(img, Rect2(81, 31, 30, 10), Color(0.85, 0.12, 0.1), false)


func _draw_ammo(img: Image) -> void:
	for k in 4:
		var x := 78 + k * 10
		_rect(img, Rect2(x, 8, 6, 14), Color(0.82, 0.6, 0.25), true, 2.0)
		_rect(img, Rect2(x + 1, 4, 4, 6), Color(0.7, 0.45, 0.2), true, 2.0)
	var bag := Color(0.36, 0.38, 0.24)
	_rect(img, Rect2(64, 18, 64, 40), bag, true, 6.0)
	_rect(img, Rect2(64, 18, 64, 14), bag.darkened(0.2), true, 6.0)
	_rect(img, Rect2(92, 28, 8, 8), Color(0.15, 0.15, 0.15), false)
	for k in 2:
		_rect(img, Rect2(70 + k * 46, 40, 6, 12), bag.darkened(0.35), false)
