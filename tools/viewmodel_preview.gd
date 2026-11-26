extends SceneTree
## Renders the view models over a fake raycaster background and saves PNGs.
## Run windowed (not headless):
##   Godot_console.exe --path <project> --script res://tools/viewmodel_preview.gd -- --out=<dir> [--only=3] [--states=idle,ads]

const VM := preload("res://scripts/viewmodel.gd")
const NAMES := ["knife", "pistol", "revolver", "rifle", "smg", "shotgun", "sniper", "lmg", "burst", "dmr", "mpistol", "dbarrel", "rpg"]

var out_dir := "res://tools/preview_out"
var only := -1
var state_filter: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--only="):
			only = int(a.substr(7))
		elif a.begins_with("--states="):
			state_filter = a.substr(9).split(",")
	_run()


func _bg(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var c: Color
		if y < h / 2:
			var u := float(y) / float(h / 2)
			c = Color(0.22, 0.23, 0.26).lerp(Color(0.12, 0.12, 0.14), u)
		else:
			var v := float(y - h / 2) / float(h / 2)
			c = Color(0.16, 0.14, 0.11).lerp(Color(0.32, 0.28, 0.22), v)
		for x in w:
			img.set_pixel(x, y, c)
	# a wall slab to judge contrast
	for y in range(h / 2 - h / 5, h / 2 + h / 5):
		for x in range(int(w * 0.55), int(w * 0.8)):
			img.set_pixel(x, y, Color(0.38, 0.36, 0.33))
	return img


func _cross(img: Image) -> void:
	var cx := img.get_width() / 2
	var cy := img.get_height() / 2
	for d in range(3, 7):
		img.set_pixel(cx + d, cy, Color(0.2, 1.0, 0.3))
		img.set_pixel(cx - d, cy, Color(0.2, 1.0, 0.3))
		img.set_pixel(cx, cy + d, Color(0.2, 1.0, 0.3))
		img.set_pixel(cx, cy - d, Color(0.2, 1.0, 0.3))


func _run() -> void:
	var abs_out := out_dir
	if abs_out.begins_with("res://"):
		abs_out = ProjectSettings.globalize_path(abs_out)
	DirAccess.make_dir_recursive_absolute(abs_out)
	await process_frame
	var vm: SubViewport = VM.new()
	vm.size = Vector2i(533, 300)
	root.add_child(vm)
	vm.call("setup", Color(0.25, 0.45, 0.9))
	var tune_path := ProjectSettings.globalize_path("res://tools/tune.json")
	if "--tune" in OS.get_cmdline_user_args() and FileAccess.file_exists(tune_path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(tune_path))
		var arr: Array = data
		var tiles2: Array[Image] = []
		for e: Dictionary in arr:
			var pa: Array = e.get("pos", [])
			var ra: Array = e.get("rot", [])
			var st2: Dictionary = {"time": 1.0}
			for k: String in e.keys():
				if k != "pos" and k != "rot" and k != "w":
					st2[k] = e[k]
			if pa.size() == 3:
				st2["_hip_pos"] = Vector3(float(pa[0]), float(pa[1]), float(pa[2]))
			if ra.size() == 3:
				st2["_hip_rot"] = Vector3(float(ra[0]), float(ra[1]), float(ra[2]))
			vm.size = Vector2i(533, 300)
			for i in 4:
				vm.call("update_pose", int(e.get("w", 3)), st2)
				await process_frame
			await RenderingServer.frame_post_draw
			var shot2 := vm.get_texture().get_image()
			shot2.convert(Image.FORMAT_RGBA8)
			var img2 := _bg(533, 300)
			img2.blend_rect(shot2, Rect2i(0, 0, 533, 300), Vector2i.ZERO)
			_cross(img2)
			tiles2.append(img2)
		var cols2 := 3 if tiles2.size() > 4 else 2
		var rows2 := int(ceil(float(tiles2.size()) / float(cols2)))
		var sheet2 := Image.create(533 * cols2, 300 * rows2, false, Image.FORMAT_RGBA8)
		for i in tiles2.size():
			sheet2.blit_rect(tiles2[i], Rect2i(0, 0, 533, 300), Vector2i((i % cols2) * 533, (i / cols2) * 300))
		sheet2.save_png(abs_out + "/tune.png")
		print("tune sheet saved")
		quit()
		return
	var states := {
		"idle": {"time": 1.0},
		"ads": {"time": 1.0, "ads": 1.0},
		"sprint": {"time": 1.0, "sprint": 1.0},
		"reload": {"time": 1.0, "reload": 0.5},
		"reload25": {"time": 1.0, "reload": 0.25},
		"kick": {"time": 1.3, "kick": 1.0, "flash": true},
		"kick6": {"time": 1.3, "kick": 0.6},
		"throw": {"time": 1.0, "throw": 0.45},
		"walk": {"time": 1.0, "bob_x": 1.0, "bob_y": -1.0, "sway": 0.6},
		"narrow": {"time": 1.0},
		"narrow_ads": {"time": 1.0, "ads": 1.0},
	}
	for w in NAMES.size():
		if only >= 0 and w != only:
			continue
		var tiles: Array[Image] = []
		for sname: String in states.keys():
			if not state_filter.is_empty() and not state_filter.has(sname):
				continue
			var st: Dictionary = states[sname]
			var sz := Vector2i(533, 300)
			if sname.begins_with("narrow"):
				sz = Vector2i(266, 300)
			vm.size = sz
			for i in 4:
				vm.call("update_pose", w, st)
				await process_frame
			await RenderingServer.frame_post_draw
			var shot := vm.get_texture().get_image()
			shot.convert(Image.FORMAT_RGBA8)
			var img := _bg(sz.x, sz.y)
			img.blend_rect(shot, Rect2i(Vector2i.ZERO, sz), Vector2i.ZERO)
			_cross(img)
			var base := "%s/%d_%s_%s" % [abs_out, w, NAMES[w], sname]
			img.save_png(base + ".png")
			var big := img.duplicate() as Image
			big.resize(sz.x * 3, sz.y * 3, Image.INTERPOLATE_NEAREST)
			big.save_png(base + "_x3.png")
			if not sname.begins_with("narrow"):
				tiles.append(img)
		# contact sheet: 3 columns
		if tiles.size() > 0:
			var cols := 3
			var rows := int(ceil(float(tiles.size()) / float(cols)))
			var sheet := Image.create(533 * cols, 300 * rows, false, Image.FORMAT_RGBA8)
			for i in tiles.size():
				sheet.blit_rect(tiles[i], Rect2i(0, 0, 533, 300), Vector2i((i % cols) * 533, (i / cols) * 300))
			sheet.save_png("%s/%d_%s_sheet.png" % [abs_out, w, NAMES[w]])
		print("rendered ", NAMES[w])
	quit()
