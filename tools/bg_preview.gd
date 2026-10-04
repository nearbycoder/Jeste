extends SceneTree
## godot --headless --path . --script res://tools/bg_preview.gd -- <chapter> <out.png>
const Bg = preload("res://tools/art_bg.gd")

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var d: Dictionary = Bg.build(int(a[0]))
	var out := Image.create(320, 180, false, Image.FORMAT_RGBA8)
	out.blit_rect(d.sky, Rect2i(0, 0, 320, 180), Vector2i.ZERO)
	for k in ["far", "mid", "near"]:
		out.blend_rect(d[k], Rect2i(int(a[2]) if a.size() > 2 else 0, 0, 320, 180), Vector2i.ZERO)
	out.resize(960, 540, Image.INTERPOLATE_NEAREST)
	out.save_png(a[1])
	quit()
