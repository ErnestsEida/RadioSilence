extends SceneTree
## Dumps the soldier row of team 1 (frames 16..31) to tools/preview_out/soldiers.png
const Gfx = preload("res://scripts/gfx.gd")
func _init() -> void:
	var tex = Gfx.make_sprites()
	var img: Image = tex.get_image() if tex is Texture2D else tex
	var out := img.get_region(Rect2i(0, 64, 1024, 64))
	out.resize(2048, 128, Image.INTERPOLATE_NEAREST)
	out.save_png("res://tools/preview_out/soldiers.png")
	quit()
