extends Node
## Renders the trailer's caption plates with the game's own pixel font and UI
## colours, as transparent PNGs scaled 6x (one game pixel = 6 video pixels):
##
##   godot --path . --rendering-method mobile --resolution 320x180 \
##         res://tools/trailer/plates.tscn -- <plates.json> <out_dir>
##
## plates.json: [{"id", "kicker", "title", "line"} | {"id", "big": "TEXT"}]
## Writes <id>_body.png and <id>_kick.png (or <id>_big.png) plus plates_meta.json
## with each image's size, which make_trailer.py animates with ffmpeg overlays.

const SCALE := 6
const PAD_X := 9
var vp: SubViewport
var canvas: Node2D
var cur: Dictionary
var part := ""
var jobs: Array = []     # [plate, part] still to render
var out := ""
var meta := {}
var step := 0


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var plates: Array = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var out_dir: String = a[1]
	vp = SubViewport.new()
	vp.size = Vector2i(320, 64)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(vp)
	canvas = Node2D.new()
	canvas.draw.connect(_draw_plate)
	vp.add_child(canvas)
	for p in plates:
		for which in (["big"] if p.has("big") else ["body", "kick"]):
			jobs.append([p, which])
	out = out_dir


## One part per few frames: draw, let the SubViewport render, read it back.
## force_draw keeps frames coming even when the compositor hides the window.
func _process(_d: float) -> void:
	RenderingServer.force_draw(false)
	step += 1
	if step % 3 == 1:
		if jobs.is_empty():
			var f := FileAccess.open(out + "/plates_meta.json", FileAccess.WRITE)
			f.store_string(JSON.stringify(meta, "\t"))
			f.close()
			get_tree().quit()
			return
		cur = jobs[0][0]
		part = jobs[0][1]
		canvas.queue_redraw()
	elif step % 3 == 0:
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		var used := img.get_used_rect()
		img = img.get_region(used)
		img.resize(img.get_width() * SCALE, img.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
		img.save_png("%s/%s_%s.png" % [out, cur.id, part])
		meta["%s_%s" % [cur.id, part]] = {"w": img.get_width(), "h": img.get_height(),
			"x": used.position.x * SCALE, "y": used.position.y * SCALE}
		jobs.pop_front()


## All parts are drawn in one 320x64 layout so their relative offsets match:
## the kicker tab sits on the body's top edge.
func _draw_plate() -> void:
	var ci := canvas
	if part == "big":
		var text: String = cur.big
		# 2x pixel text, outlined in ink, with a crimson underline
		var w := PixelText.width(text) * 2
		var x := roundf(160 - w / 2.0)
		ci.draw_set_transform(Vector2(x, 20), 0, Vector2(2, 2))
		for d in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1), Vector2(1, 1)]:
			PixelText.draw(ci, d, text, UIKit.INK)
		PixelText.draw(ci, Vector2.ZERO, text, UIKit.GOLD)
		ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		ci.draw_rect(Rect2(x + w / 2.0 - 14, 41, 28, 2), UIKit.INK)
		ci.draw_rect(Rect2(x + w / 2.0 - 13, 41, 26, 1), UIKit.CRIMSON)
		return
	var title: String = cur.get("title", "")
	var line: String = cur.get("line", "")
	var bw := maxf(PixelText.width(title), PixelText.width(line)) + PAD_X * 2 + 6
	var body := Rect2(4, 22, bw, 27)
	if part == "body":
		ci.draw_rect(Rect2(body.position + Vector2(2, 2), body.size), Color(0, 0, 0, 0.4))
		var top := Color(0.13, 0.08, 0.19, 0.93)
		var bot := Color(0.05, 0.03, 0.08, 0.93)
		ci.draw_polygon(PackedVector2Array([body.position, Vector2(body.end.x, body.position.y), body.end, Vector2(body.position.x, body.end.y)]),
			PackedColorArray([top, top, bot, bot]))
		UIKit.frame(ci, body.grow(1), UIKit.INK)
		ci.draw_rect(Rect2(body.position.x, body.position.y, body.size.x, 1), UIKit.GOLD)
		ci.draw_rect(Rect2(body.position.x, body.end.y - 1, body.size.x, 1), Color(UIKit.GOLD, 0.8))
		ci.draw_rect(Rect2(body.position.x, body.position.y + 1, 2, body.size.y - 2), UIKit.CRIMSON)
		UIKit.diamond(ci, Vector2(body.position.x + 8, body.position.y + 8), 2.0, UIKit.CRIMSON.lightened(0.15))
		PixelText.draw(ci, Vector2(body.position.x + PAD_X + 4, body.position.y + 4), title, UIKit.GOLD, Color(UIKit.INK, 0.9))
		PixelText.draw(ci, Vector2(body.position.x + PAD_X + 4, body.position.y + 15), line, UIKit.CREAM, Color(UIKit.INK, 0.9))
	elif part == "kick":
		var kicker: String = cur.get("kicker", "")
		if kicker == "":
			return
		var kw := PixelText.width(kicker) + 12
		var tr := Rect2(body.position.x + 4, body.position.y - 11, kw, 11)
		ci.draw_rect(Rect2(tr.position + Vector2(2, 2), tr.size), Color(0, 0, 0, 0.4))
		ci.draw_rect(tr.grow(1), UIKit.INK)
		ci.draw_rect(tr, UIKit.CRIMSON.darkened(0.25))
		ci.draw_rect(Rect2(tr.position.x, tr.position.y, tr.size.x, 1), UIKit.CRIMSON.lightened(0.3))
		PixelText.draw(ci, Vector2(tr.position.x + 6, tr.position.y + 2), kicker, UIKit.CREAM, Color(UIKit.INK, 0.8))
