extends SceneTree
const Doll = preload("res://tools/art_doll.gd")
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var who := args[0] if args.size() > 0 else "mira"
	var ch
	match who:
		"bellamy": ch = Doll.bellamy()
		"tobi": ch = Doll.tobi()
		"oddo": ch = Doll.oddo()
		_: ch = Doll.mira()
	var P := Doll.poses()
	var order: Array = Doll.FRAME_ORDER
	var cols := 9
	var rows := int(ceil(order.size() / float(cols)))
	var sheet := Image.create(cols * 24, rows * 24, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.35, 0.33, 0.42))
	for i in order.size():
		var r: Dictionary = Doll.render(ch, P[order[i]])
		sheet.blend_rect(r.image, Rect2i(0, 0, 24, 24), Vector2i((i % cols) * 24, (i / cols) * 24))
	sheet.resize(sheet.get_width() * 6, sheet.get_height() * 6, Image.INTERPOLATE_NEAREST)
	sheet.save_png("/tmp/doll_%s.png" % who)
	quit()
