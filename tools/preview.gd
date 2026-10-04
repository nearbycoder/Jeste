extends SceneTree
## Builds a scaled contact sheet of images: --script res://tools/preview.gd -- out.png scale img1 img2 ...
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var sc := int(args[1])
	var imgs: Array[Image] = []
	var w := 0
	var h := 0
	for i in range(2, args.size()):
		var img := Image.load_from_file(ProjectSettings.globalize_path(args[i]))
		img.convert(Image.FORMAT_RGBA8)
		img.resize(img.get_width() * sc, img.get_height() * sc, Image.INTERPOLATE_NEAREST)
		imgs.append(img)
		w = maxi(w, img.get_width())
		h += img.get_height() + 4
	var sheet := Image.create(w, h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.25, 0.25, 0.3))
	var y := 0
	for img in imgs:
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(0, y))
		y += img.get_height() + 4
	sheet.save_png(out)
	quit()
