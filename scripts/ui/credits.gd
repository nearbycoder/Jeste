extends Node2D
## End credits: scrolling text over the epilogue sky while Mira juggles.

var time := 0.0
var backdrop: Backdrop
var scroll := 0.0
var lines := [
	["JESTE", "title"],
	["", ""],
	["a mountain that laughs back", "sub"],
	["", ""], ["", ""],
	["~ Starring ~", "head"],
	["Mira Vale", ""], ["the Grin", ""], ["Old Bellamy", ""], ["Tobi Harrow", ""],
	["Ringmaster Oddo", ""], ["a very patient Magpie", ""],
	["", ""],
	["~ and ~", "head"],
	["Nana Odile, who taught Mira", ""], ["that a dropped ball is", ""], ["just the start of a better joke", ""],
	["", ""], ["", ""],
	["~ Made with ~", "head"],
	["Godot Engine", ""], ["hand-placed pixels", ""], ["and an automated climber", ""],
	["that proved every berry", ""], ["could be reached", ""],
	["", ""], ["", ""],
	["~ Thank you ~", "head"],
	["for climbing.", ""],
	["", ""],
	["It's okay to take the mask off.", "sub"],
	["", ""], ["", ""], ["", ""],
]


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -10
	add_child(layer)
	backdrop = Backdrop.new()
	layer.add_child(backdrop)
	var post := PostFX.new()
	add_child(post)
	post.setup(8)
	backdrop.setup(8)
	Sfx.play_music("credits")


func _process(delta: float) -> void:
	time += delta
	scroll += delta * 14.0
	backdrop.cam_pos.x = time * 6.0
	if scroll > lines.size() * 14 + 200:
		Game.goto_title()
	queue_redraw()


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("back") or ev.is_action_pressed("pause"):
		Game.goto_title()
	elif ev.is_action_pressed("confirm"):
		scroll += 40


func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(0, 0, 0, 0.35))
	for i in lines.size():
		var y := 190.0 + i * 14.0 - scroll
		if y < -12 or y > 182:
			continue
		var txt: String = lines[i][0]
		match lines[i][1]:
			"title":
				draw_set_transform(Vector2(160 - PixelText.width(txt), y - 6), 0, Vector2(2, 2))
				PixelText.draw(self, Vector2.ZERO, txt, Color("f2c14e"), Color(0, 0, 0, 0.8))
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			"head":
				PixelText.draw_centered(self, 160, y, txt, Color("f2c14e"), Color(0, 0, 0, 0.8))
			"sub":
				PixelText.draw_centered(self, 160, y, txt, Color("ffb8d8"), Color(0, 0, 0, 0.8))
			_:
				PixelText.draw_centered(self, 160, y, txt, Color.WHITE, Color(0, 0, 0, 0.8))
	# Mira juggling
	var base := Vector2(40, 170)
	draw_texture_rect_region(Art.player_menu(), Rect2(base.x - 12, base.y - 24, 24, 24), Rect2(Art.frame_index("talk%d" % (int(time * 4.4) % 2)) * 24, 0, 24, 24))
	for i in 3:
		var t := time * 2.2 + i * TAU / 3.0
		var p := base + Vector2(cos(t) * 7.0, -18.0 - absf(sin(t)) * 14.0)
		var names := ["ball_r", "ball_y", "ball_u"]
		draw_texture_rect_region(Art.objects(), Rect2(p.x - 8, p.y - 8, 16, 16), Art.obj_rect(names[i]))
