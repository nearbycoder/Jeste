extends "res://scripts/ui/title.gd"
## Trailer title / end card: the title screen's backdrop, logo, campfire and
## juggling Mira, without the menu. `mode = "end"` adds the repository link,
## `mode = "poster"` a play button for the README.

var mode := "title"
const DY := 22.0
const URL := "github.com/nearbycoder/Jeste"


func _ready() -> void:
	super()
	logo_node.position.y = DY


func _build_items() -> void:
	items = []
	row_k = []


func _input(_ev: InputEvent) -> void:
	pass


func _unhandled_input(_ev: InputEvent) -> void:
	pass


func _draw() -> void:
	draw_texture(ledge_tex, Vector2(212, 142))
	UIKit.campfire(self, FIRE, time)
	for e in embers:
		var a := clampf(e.life, 0.0, 1.0)
		draw_rect(Rect2((e.p as Vector2).round(), Vector2.ONE), Color(1.0, 0.75, 0.3, a))
	var frame := Art.frame_index("talk%d" % (int(juggle_t * 4.4) % 2))
	draw_set_transform(MIRA, 0, Vector2(1, 1))
	draw_texture_rect_region(Art.player_menu(), Rect2(-12, -24, 24, 24), Rect2(frame * 24, 0, 24, 24), Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	for i in 3:
		var t := juggle_t * 2.2 + i * TAU / 3.0
		var p := MIRA + Vector2(cos(t) * 7.0, -18.0 - absf(sin(t)) * 14.0)
		var names := ["ball_r", "ball_y", "ball_u"]
		draw_texture_rect_region(Art.objects(), Rect2((p - Vector2(8, 8)).round(), Vector2(16, 16)), Art.obj_rect(names[i]))
	# tagline
	var tk := _intro(1.15, 0.5)
	if tk > 0.0:
		var tag := "a mountain that laughs back"
		var ty := LOGO_Y + DY + 40.0
		var tw := PixelText.width(tag)
		draw_rect(Rect2(160 - tw / 2.0 - 18, ty + 4, 12 * tk, 1), Color(UIKit.GOLD, 0.7 * tk))
		draw_rect(Rect2(160 + tw / 2.0 + 18 - 12 * tk, ty + 4, 12 * tk, 1), Color(UIKit.GOLD, 0.7 * tk))
		PixelText.draw_centered_outlined(self, 160, ty, tag, Color(UIKit.CREAM, tk), Color(UIKit.INK, 0.9 * tk))
	if mode == "end":
		var k := _intro(1.7, 0.45)
		if k > 0.0:
			var e := ease(k, 0.3)
			var line2 := "Made with Godot 4.7"
			var w := maxf(PixelText.width(URL), PixelText.width(line2)) + 24.0
			# keep clear of Mira's juggling balls on the right
			var cx := minf(160.0, 228.0 - w / 2.0)
			var r := Rect2(roundf(cx - w / 2.0), 104 + (1.0 - e) * 8.0, w, 30)
			UIKit.panel(self, r, e)
			PixelText.draw_centered_outlined(self, r.get_center().x, r.position.y + 7, URL, Color(UIKit.GOLD, e), Color(UIKit.INK, e))
			PixelText.draw_centered(self, r.get_center().x, r.position.y + 18, line2, Color(UIKit.MUTED, e), Color(UIKit.INK, 0.8 * e))
	if mode == "poster":
		# README poster frame: a pixel play button under the tagline
		var c := Vector2(160, 118)
		draw_circle(c + Vector2(1, 2), 17, Color(0, 0, 0, 0.35))
		draw_circle(c, 17, UIKit.INK)
		draw_circle(c, 16, UIKit.GOLD)
		draw_circle(c, 14, Color(0.13, 0.08, 0.19))
		draw_colored_polygon(PackedVector2Array([c + Vector2(-5, -8), c + Vector2(9, 0), c + Vector2(-5, 8)]), UIKit.CREAM)
		PixelText.draw_centered_outlined(self, 160, 140, "Watch the trailer", UIKit.GOLD, UIKit.INK)
	UIKit.wipe(self, wipe, -1.0)
