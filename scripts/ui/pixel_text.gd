class_name PixelText
extends RefCounted
## Draws text with the generated bitmap font onto any CanvasItem.

const CELL_W := 6
const CELL_H := 9
const LINE_H := 10


static func char_width(c: String) -> int:
	var code := c.unicode_at(0)
	if code < 32 or code > 127:
		code = 63
	var widths := Art.font_widths()
	if widths.is_empty():
		return 5
	return int(widths[code - 32])


static func width(text: String) -> int:
	var w := 0
	for i in text.length():
		w += char_width(text[i]) + 1
	return maxi(w - 1, 0)


static func draw(ci: CanvasItem, pos: Vector2, text: String, color: Color = Color.WHITE, shadow: Color = Color(0, 0, 0, 0), max_chars: int = -1) -> void:
	var tex := Art.font()
	if tex == null:
		return
	var x := int(pos.x)
	var y := int(pos.y)
	var n := text.length() if max_chars < 0 else mini(max_chars, text.length())
	for i in n:
		var c := text[i]
		var code := c.unicode_at(0)
		if code < 32 or code > 127:
			code = 63
		var gi := code - 32
		var src := Rect2((gi % 16) * CELL_W, (gi / 16) * CELL_H, CELL_W, CELL_H)
		if shadow.a > 0.0:
			ci.draw_texture_rect_region(tex, Rect2(x + 1, y + 1, CELL_W, CELL_H), src, shadow)
		ci.draw_texture_rect_region(tex, Rect2(x, y, CELL_W, CELL_H), src, color)
		x += char_width(c) + 1


static func draw_centered(ci: CanvasItem, center_x: float, y: float, text: String, color: Color = Color.WHITE, shadow: Color = Color(0, 0, 0, 0)) -> void:
	draw(ci, Vector2(roundi(center_x - width(text) / 2.0), y), text, color, shadow)


## Greedy word wrap to a pixel width.
static func wrap(text: String, max_w: int) -> PackedStringArray:
	var out := PackedStringArray()
	for para in text.split("\n"):
		var line := ""
		for word in para.split(" ", false):
			var cand := word if line == "" else line + " " + word
			if width(cand) > max_w and line != "":
				out.append(line)
				line = word
			else:
				line = cand
		out.append(line)
	return out
