extends ColorRect
## Live raycast fly-through of the selected map, used behind the main menu.

const MapData = preload("res://scripts/map_data.gd")
const Defs = preload("res://scripts/defs.gd")
const MAX_SPRITES := 160
const SWAY := [Defs.FR_TREE, Defs.FR_PINE, Defs.FR_BUSH, Defs.FR_GRASS, Defs.FR_SNOWBUSH, Defs.FR_DRYBUSH, Defs.FR_REEDS, Defs.FR_FLOWERS, Defs.FR_DEADTREE]

var mapdata = null
var mat: ShaderMaterial
var res: Dictionary
var t := 0.0
var map_i := -1
var spr_img: Image
var spr_tex: ImageTexture
var spr_buf := PackedFloat32Array()
var mini_tex: ImageTexture


func setup(p_res: Dictionary) -> void:
	res = p_res
	mat = ShaderMaterial.new()
	mat.shader = res.shader
	material = mat
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	spr_buf.resize(MAX_SPRITES * 8)
	spr_img = Image.create_from_data(MAX_SPRITES, 2, false, Image.FORMAT_RGBAF, spr_buf.to_byte_array())
	spr_tex = ImageTexture.create_from_image(spr_img)
	mat.set_shader_parameter("wall_tex", res.wall_tex)
	mat.set_shader_parameter("sprite_tex", res.sprite_tex)
	mat.set_shader_parameter("spr_data", spr_tex)


func set_map(i: int) -> void:
	if i == map_i:
		return
	map_i = i
	mapdata = MapData.new()
	mapdata.generate(i, 20261119)
	mat.set_shader_parameter("map_tex", ImageTexture.create_from_image(mapdata.pack_image()))
	mapdata.apply_shader(mat)
	var th: Array = MapData.THEMES[mapdata.palette]
	# minimap preview for the menu
	var img := Image.create(mapdata.W, mapdata.H, false, Image.FORMAT_RGBA8)
	for y in mapdata.H:
		for x in mapdata.W:
			var k: int = y * mapdata.W + x
			var w: int = mapdata.wall[k]
			var c: Color = th[0].darkened(0.25)
			if w == 1 or w == 2:
				c = Color(0.42, 0.38, 0.33)
			elif w > 0:
				c = Color(0.75, 0.72, 0.65)
			elif mapdata.flo[k] == 1:
				c = th[2]
			elif mapdata.flo[k] >= 2:
				c = Color(0.32, 0.32, 0.32)
			elif mapdata.obst[k] != 0:
				c = th[0].darkened(0.5)
			img.set_pixel(x, y, c)
	mini_tex = ImageTexture.create_from_image(img)


func _process(dt: float) -> void:
	if mapdata == null or not is_visible_in_tree():
		return
	t += dt
	# glide up and down the north-south road through the map centre, looking around
	var W: float = mapdata.W
	var H: float = mapdata.H
	var span := H - 100.0
	var ph := fmod(t * 1.4, span * 2.0)
	var y := 50.0 + (ph if ph < span else span * 2.0 - ph)
	var forward := PI * 0.5 if ph < span else -PI * 0.5
	var cam := Vector2(W * 0.5 + 0.5 + sin(t * 0.21) * 1.2, y)
	var yaw := forward + sin(t * 0.13) * 1.1
	var aspect := size.x / maxf(1.0, size.y)
	var plen := tan(deg_to_rad(80.0) * 0.5)
	mat.set_shader_parameter("cam_pos", cam)
	mat.set_shader_parameter("cam_angle", yaw)
	mat.set_shader_parameter("plen", plen)
	mat.set_shader_parameter("vscale", aspect * 0.5 / plen)
	# a slow crane shot: rises above the cover, tilts down to show the terrain
	var vs := aspect * 0.5 / plen
	mat.set_shader_parameter("eye", 1.5 + sin(t * 0.17) * 0.9)
	mat.set_shader_parameter("look", tan(-0.12 + sin(t * 0.23) * 0.1) * vs)
	mat.set_shader_parameter("time", t)
	mat.set_shader_parameter("bob", 0.0)
	mat.set_shader_parameter("indoor", 0.0)
	mat.set_shader_parameter("hurt", 0.0)
	mat.set_shader_parameter("desat", 0.0)
	# props as sprites
	var dir := Vector2.from_angle(yaw)
	var cosmax := cos(atan(plen) + 0.1)
	var list: Array = []
	for d in mapdata.decor:
		var p := Vector2(d[0], d[1])
		var rel := p - cam
		var dist := rel.length()
		if dist > 34.0 or (dist > 1.5 and rel.dot(dir) / dist < cosmax - 1.0 / dist):
			continue
		var fr: int = d[2]
		if fr >= Defs.FR_FLAG and fr < Defs.FR_FLAG + 10:
			fr += int(t * 5.0 + p.x) % 2
		list.append([dist, p.x, p.y, fr, d[3], d[4], 2.0 if fr in SWAY else 0.0])
	list.sort_custom(func(a, b): return a[0] > b[0])
	if list.size() > MAX_SPRITES:
		list = list.slice(list.size() - MAX_SPRITES)
	var row := MAX_SPRITES * 4
	for i in list.size():
		var s: Array = list[i]
		spr_buf[i * 4] = s[1]
		spr_buf[i * 4 + 1] = s[2]
		spr_buf[i * 4 + 2] = s[3]
		spr_buf[i * 4 + 3] = s[4]
		spr_buf[row + i * 4] = s[5]
		spr_buf[row + i * 4 + 1] = s[6]
		spr_buf[row + i * 4 + 2] = 0.0
		spr_buf[row + i * 4 + 3] = 0.0
	spr_img.set_data(MAX_SPRITES, 2, false, Image.FORMAT_RGBAF, spr_buf.to_byte_array())
	spr_tex.update(spr_img)
	mat.set_shader_parameter("sprite_count", list.size())
