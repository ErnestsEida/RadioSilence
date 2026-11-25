extends SceneTree
## Bakes the vehicle atlas and renders preview images. Run windowed (not headless):
##   Godot_console.exe --path <project> -s tools/vehicle_preview.gd [-- --no-cockpit] [--no-atlas]
## Output in tools/preview_out/: vehicle_atlas.png, vehicle_sheet.png, cockpit_<vtype>_<role>.png

const VM := preload("res://scripts/vehicle_models.gd")
const VB := preload("res://scripts/vehicle_bake.gd")
const VV := preload("res://scripts/vehicle_view.gd")
const TEAM := Color(0.25, 0.45, 0.9)
const ANGLES := [0, 2, 4, 6, 8]

var out_dir := ""


func _initialize() -> void:
	_run()


func _tint(c: Color) -> Color:
	if c.a8 == VB.PAINT_ALPHA:
		var l := c.r * 1.3
		return Color(minf(1.0, l * TEAM.r + 0.04), minf(1.0, l * TEAM.g + 0.04), minf(1.0, l * TEAM.b + 0.04), 1.0)
	return c


func _blit(dst: Image, src: Image, sr: Rect2i, at: Vector2i, scale: int) -> void:
	for y in sr.size.y:
		for x in sr.size.x:
			var c := src.get_pixel(sr.position.x + x, sr.position.y + y)
			if c.a8 == 0:
				continue
			var t := _tint(c)
			for sy in scale:
				for sx in scale:
					var px := at.x + x * scale + sx
					var py := at.y + y * scale + sy
					if px >= 0 and py >= 0 and px < dst.get_width() and py < dst.get_height():
						dst.set_pixel(px, py, t)


func _run() -> void:
	out_dir = ProjectSettings.globalize_path("res://tools/preview_out")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var args := OS.get_cmdline_user_args()
	await process_frame
	if args.has("--cache"):
		var vc: Node = VB.new()
		root.add_child(vc)
		var tc := Time.get_ticks_msec()
		var cimg: Image = await vc.call("bake")
		print("CACHED_BAKE_MS ", Time.get_ticks_msec() - tc, " size ", cimg.get_size(), " format ", cimg.get_format())
		vc.queue_free()
	if not args.has("--no-atlas"):
		var vb: Node = VB.new()
		vb.set("debug_timing", true)
		root.add_child(vb)
		var t0 := Time.get_ticks_msec()
		var atlas: Image = await vb.call("bake", false)
		var ms := Time.get_ticks_msec() - t0
		print("BAKE_MS ", ms, " (inner ", vb.get("last_bake_ms"), ")  size ", atlas.get_size())
		atlas.save_png(out_dir + "/vehicle_atlas.png")
		# alpha histogram sanity check
		var hist := {}
		var data := atlas.get_data()
		var i := 3
		while i < data.size():
			var a := data[i]
			hist[a] = int(hist.get(a, 0)) + 1
			i += 4 * 7
		print("ALPHA_VALUES ", hist)
		_sheet(atlas)
		_atlas_view(atlas)
		vb.queue_free()
	if not args.has("--no-cockpit"):
		await _cockpits()
	quit()


func _atlas_view(atlas: Image) -> void:
	var w := atlas.get_width()
	var h := atlas.get_height()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.42, 0.43, 0.4))
	for y in range(0, h, 128):
		img.fill_rect(Rect2i(0, y + 121, w, 1), Color(0.3, 0.3, 0.28))
	for x in range(0, w, 128):
		img.fill_rect(Rect2i(x, 0, 1, h), Color(0.35, 0.35, 0.33))
	_blit(img, atlas, Rect2i(0, 0, w, h), Vector2i.ZERO, 1)
	for v in VM.NUM_TYPES:
		var crop := img.get_region(Rect2i(0, v * 512, w, 512))
		crop.save_png(out_dir + "/atlas_view_%d.png" % v)


func _sheet(atlas: Image) -> void:
	var F := VB.F
	var S := 2
	var cell := F * S
	var cols := ANGLES.size()
	var rows := VM.NUM_TYPES * 2
	var img := Image.create(cell * cols, cell * rows, false, Image.FORMAT_RGBA8)
	for r in rows:
		for c in cols:
			var shade := 0.4 if (r + c) % 2 == 0 else 0.44
			img.fill_rect(Rect2i(c * cell, r * cell, cell, cell), Color(shade, shade + 0.01, shade - 0.02))
			img.fill_rect(Rect2i(c * cell, r * cell + (F - 1 - VB.GROUND_PX) * S, cell, 1), Color(0.3, 0.3, 0.28))
	for v in VM.NUM_TYPES:
		for w in 2:
			var r := v * 2 + w
			for ci in cols:
				var a: int = ANGLES[ci]
				var hull_row := v * 4 + w * 2
				var tur_row := hull_row + 1
				var off := VB.pivot_px(VM.TURRET_PIVOT[v], float(a) * VB.ANGLE_STEP)
				var at := Vector2i(ci * cell, r * cell)
				var tat := at + Vector2i(roundi(off.x) * S, roundi(off.y) * S)
				var turret_behind := off.y < -0.5
				if turret_behind:
					_blit(img, atlas, Rect2i(a * F, tur_row * F, F, F), tat, S)
				_blit(img, atlas, Rect2i(a * F, hull_row * F, F, F), at, S)
				if not turret_behind:
					_blit(img, atlas, Rect2i(a * F, tur_row * F, F, F), tat, S)
	img.save_png(out_dir + "/vehicle_sheet.png")
	# close-up: every vehicle at two angles, 4x
	var Z := 4
	var zc := F * Z
	var zoom := Image.create(zc * VM.NUM_TYPES, zc * 2, false, Image.FORMAT_RGBA8)
	zoom.fill(Color(0.42, 0.43, 0.4))
	for v in VM.NUM_TYPES:
		for k in 2:
			var a: int = [3, 13][k]
			var off := VB.pivot_px(VM.TURRET_PIVOT[v], float(a) * VB.ANGLE_STEP)
			var at := Vector2i(v * zc, k * zc)
			var tat := at + Vector2i(roundi(off.x) * Z, roundi(off.y) * Z)
			var behind := off.y < -0.5
			if behind:
				_blit(zoom, atlas, Rect2i(a * F, (v * 4 + 1) * F, F, F), tat, Z)
			_blit(zoom, atlas, Rect2i(a * F, (v * 4) * F, F, F), at, Z)
			if not behind:
				_blit(zoom, atlas, Rect2i(a * F, (v * 4 + 1) * F, F, F), tat, Z)
	zoom.save_png(out_dir + "/vehicle_zoom.png")


func _bg(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var c: Color
		if y < h / 2:
			c = Color(0.45, 0.58, 0.72).lerp(Color(0.72, 0.76, 0.78), float(y) / float(h / 2))
		else:
			c = Color(0.42, 0.4, 0.33).lerp(Color(0.3, 0.27, 0.2), float(y - h / 2) / float(h / 2))
		img.fill_rect(Rect2i(0, y, w, 1), c)
	# a few posts on the ground plane to judge alignment (1 unit tall at 3 / 6 cells)
	return img


func _cockpits() -> void:
	var sz := Vector2i(1920, 1080)
	var sheet := Image.create(640 * 3, 360 * VM.NUM_TYPES, false, Image.FORMAT_RGBA8)
	for v in VM.NUM_TYPES:
		var vv: SubViewport = VV.new()
		vv.size = sz
		root.add_child(vv)
		vv.call("setup", v, TEAM)
		for role in [1, 2, 3]:
			var seats: Array = VM.SEAT[v]
			var seat: Vector3 = seats[0 if role == 2 else 1]
			var st := {"turret_rel": 0.35 if role == 1 else 0.0, "hfov": 80.0, "time": 1.0, "speed": 0.0,
				"steer": 0.4 if role == 2 else 0.0, "kick": 0.0, "eye": seat.y}
			for i in 3:
				vv.call("update_pose", role, st)
				await process_frame
			await RenderingServer.frame_post_draw
			var shot := vv.get_texture().get_image()
			shot.convert(Image.FORMAT_RGBA8)
			var img := _bg(sz.x, sz.y)
			img.blend_rect(shot, Rect2i(Vector2i.ZERO, sz), Vector2i.ZERO)
			img.fill_rect(Rect2i(sz.x / 2 - 6, sz.y / 2, 13, 1), Color(0.1, 1.0, 0.2))
			img.fill_rect(Rect2i(sz.x / 2, sz.y / 2 - 6, 1, 13), Color(0.1, 1.0, 0.2))
			img.save_png(out_dir + "/cockpit_%d_%d.png" % [v, role])
			var small := img.duplicate() as Image
			small.resize(640, 360, Image.INTERPOLATE_BILINEAR)
			sheet.blit_rect(small, Rect2i(0, 0, 640, 360), Vector2i((int(role) - 1) * 640, v * 360))
			print("cockpit ", v, " ", role)
		# stress pose: firing, turret turned left, full speed, hard steer
		var seats2: Array = VM.SEAT[v]
		var seat2: Vector3 = seats2[1]
		var st2 := {"turret_rel": -0.9, "hfov": 80.0, "time": 2.3, "speed": 1.0, "steer": -1.0, "kick": 1.0, "eye": seat2.y}
		for i in 3:
			vv.call("update_pose", 3, st2)
			await process_frame
		await RenderingServer.frame_post_draw
		var shot2 := vv.get_texture().get_image()
		shot2.convert(Image.FORMAT_RGBA8)
		var img2 := _bg(sz.x, sz.y)
		img2.blend_rect(shot2, Rect2i(Vector2i.ZERO, sz), Vector2i.ZERO)
		img2.resize(960, 540, Image.INTERPOLATE_BILINEAR)
		img2.save_png(out_dir + "/cockpit_%d_stress.png" % v)
		vv.queue_free()
		await process_frame
	sheet.save_png(out_dir + "/cockpit_sheet.png")
