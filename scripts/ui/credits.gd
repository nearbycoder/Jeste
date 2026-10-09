extends Node2D
## End credits: the logo and cast roll scroll over the epilogue sky, while
## the whole troupe gathers on a grassy ledge for a curtain call.

var time := 0.0
var backdrop: Backdrop
var scroll := 0.0
var ledge_tex: Texture2D
var ended := false
var end_t := 0.0
var confetti: Array = []

const SPEED := 13.0
const LINE_H := 13.0
var lines := [
	["", "logo"], ["", ""], ["", ""], ["", ""],
	["a mountain that laughs back", "sub"],
	["", ""], ["", ""],
	["Starring", "head"],
	["Mira Vale", ""], ["the Grin", ""], ["Old Bellamy", ""], ["Tobi Harrow", ""],
	["Ringmaster Oddo", ""], ["a very patient Magpie", ""],
	["", ""],
	["and", "head"],
	["Nana Odile, who taught Mira", ""], ["that a dropped ball is", ""], ["just the start of a better joke", ""],
	["", ""], ["", ""],
	["Made with", "head"],
	["Godot Engine", ""], ["hand-placed pixels", ""], ["a small synthesizer", ""], ["and an automated climber", ""],
	["that proved every berry", ""], ["could be reached", ""],
	["", ""], ["", ""],
	["Thank you", "head"],
	["for climbing.", ""],
	["", ""],
	["It's okay to take the mask off.", "sub"],
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
	Game.web_status({"screen": "credits"})
	backdrop.setup(8)
	ledge_tex = _make_ledge()
	Sfx.play_music("credits")
	Sfx.play_ambience("")


func _make_ledge() -> Texture2D:
	var d := RoomDef.new()
	d.id = "credits_ledge"
	d.w = 42
	d.h = 4
	var rows := PackedStringArray([
		"..........................................",
		"##########################################",
		"##########################################",
		"##########################################",
	])
	d.rows = rows
	d.cells.resize(d.w * d.h)
	for y in d.h:
		for x in d.w:
			d.cells[y * d.w + x] = RoomDef.SOLID if rows[y][x] == "#" else RoomDef.EMPTY
	var art := TerrainArt.render(d, "village")
	var img: Image = art.fg
	img.blend_rect(art.deco, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i.ZERO)
	return ImageTexture.create_from_image(img)


func _total() -> float:
	return lines.size() * LINE_H + 205.0


func _process(delta: float) -> void:
	time += delta
	backdrop.cam_pos.x = time * 6.0
	if not ended:
		scroll += delta * SPEED
		if scroll > _total():
			ended = true
			Sfx.play("complete")
			for i in 80:
				confetti.append({"p": Vector2(randf_range(40, 280), randf_range(-60, -4)), "v": Vector2(randf_range(-10, 10), randf_range(10, 30)), "c": [Color("ff5a6e"), Color("ffd25a"), Color("5ad2ff"), Color("8aff6e"), Color("ff8ae0")][i % 5], "ph": randf() * TAU})
	else:
		end_t += delta
		if end_t > 9.0:
			Game.goto_title()
	for c in confetti:
		c.p += c.v * delta
		c.p.x += sin(time * 3.0 + c.ph) * 10.0 * delta
	queue_redraw()


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouse:
		# a click reads as Confirm (right click as Back); the wheel scrolls
		var d := UIKit.wheel_step(ev)
		if d != 0 and not ended:
			scroll = maxf(scroll + 40.0 * d, 0.0)
		ev = UIKit.click_action(ev)
		if ev == null:
			return
	if ev.is_action_pressed("back") or ev.is_action_pressed("pause"):
		Game.goto_title()
	elif ev.is_action_pressed("confirm"):
		if ended and end_t > 1.0:
			Game.goto_title()
		else:
			scroll += 40


func _draw_logo(y: float) -> void:
	var letters := UIKit.logo_letters()
	var x := roundf(160.0 - UIKit.logo_width() / 2.0)
	for i in letters.size():
		var L: Dictionary = letters[i]
		var bob := roundf(sin(time * 1.6 + i * 0.8))
		draw_texture(L.tex, Vector2(x - int(L.m), y + bob - int(L.m)))
		x += int(L.w) + 2


func _draw() -> void:
	# soft central column of shade keeps the text readable on the bright sky
	var c0 := Color(0.03, 0.02, 0.06, 0.0)
	var c1 := Color(0.03, 0.02, 0.06, 0.28)
	draw_polygon(PackedVector2Array([Vector2(40, 0), Vector2(160, 0), Vector2(160, 180), Vector2(40, 180)]), PackedColorArray([c0, c1, c1, c0]))
	draw_polygon(PackedVector2Array([Vector2(160, 0), Vector2(280, 0), Vector2(280, 180), Vector2(160, 180)]), PackedColorArray([c1, c0, c0, c1]))
	for i in lines.size():
		var y := 186.0 + i * LINE_H - scroll
		if y < -40 or y > 182:
			continue
		var txt: String = lines[i][0]
		match lines[i][1]:
			"logo":
				_draw_logo(y)
			"head":
				var w := PixelText.width(txt)
				PixelText.draw_centered_outlined(self, 160, y, txt, UIKit.GOLD, UIKit.INK)
				for sx in [-1, 1]:
					var dx: float = 160 + sx * (w / 2.0 + 9)
					draw_rect(Rect2(dx - (12 if sx < 0 else 0) + (0 if sx < 0 else 4), y + 4, 8, 1), Color(UIKit.GOLD, 0.7))
					UIKit.diamond(self, Vector2(dx, y + 4), 2.0, UIKit.CRIMSON)
			"sub":
				PixelText.draw_centered_outlined(self, 160, y, txt, Color("ffc8e0"), UIKit.INK)
			_:
				PixelText.draw_centered_outlined(self, 160, y, txt, UIKit.CREAM, UIKit.INK)
	# the troupe on the ledge
	draw_texture(ledge_tex, Vector2(-8, 156))
	var ground := 164.0
	_npc("res://assets/sprites/npc_bellamy.png", Vector2(92, ground), false, 0.0)
	_npc("res://assets/sprites/npc_tobi.png", Vector2(228, ground), true, 1.3)
	_npc("res://assets/sprites/npc_oddo.png", Vector2(258, ground - 3 + sin(time * 1.5) * 2.0), true, 2.1, Color(1, 1, 1, 0.8))
	var base := Vector2(160 if ended else 40, ground)
	if ended:
		base.x = lerpf(40.0, 160.0, ease(clampf(end_t / 1.5, 0.0, 1.0), -2.0))
	draw_texture_rect_region(Art.player_menu(), Rect2(base.x - 12, base.y - 24, 24, 24), Rect2(Art.frame_index("talk%d" % (int(time * 4.4) % 2)) * 24, 0, 24, 24))
	for i in 3:
		var t := time * 2.2 + i * TAU / 3.0
		var p := base + Vector2(cos(t) * 7.0, -18.0 - absf(sin(t)) * 14.0)
		var names := ["ball_r", "ball_y", "ball_u"]
		draw_texture_rect_region(Art.objects(), Rect2((p - Vector2(8, 8)).round(), Vector2(16, 16)), Art.obj_rect(names[i]))
	if ended:
		var a := clampf((end_t - 1.0) * 1.5, 0.0, 1.0)
		var sc := 2.0
		var txt := "The End"
		var w := PixelText.width(txt) * sc
		draw_set_transform(Vector2(roundf(160 - w / 2.0), 70), 0, Vector2(sc, sc))
		for d in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			PixelText.draw(self, d * 0.5, txt, Color(UIKit.INK, a))
		PixelText.draw(self, Vector2.ZERO, txt, Color(UIKit.GOLD, a))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		for c in confetti:
			var spin := sin(time * 12.0 + c.ph)
			draw_rect(Rect2((c.p as Vector2).round(), Vector2(2 if absf(spin) > 0.4 else 1, 1)), c.c if spin > 0 else (c.c as Color).darkened(0.3))
		if end_t > 2.0:
			var pairs := [[Game.key_label("jump"), "Title"]]
			UIKit.hints(self, Vector2(roundf(160 - UIKit.hints_width(pairs) / 2.0), 100), pairs, 0.8)


func _npc(path: String, feet: Vector2, face_left: bool, phase: float, mod: Color = Color.WHITE) -> void:
	var frames: Array = Art.index().get("npc_frames", ["idle0"])
	var fname := "idle%d" % [0, 0, 1, 2, 3, 3, 3, 2, 1, 0, 4, 0][int((time + phase) * 5.0) % 12]
	if ended:
		fname = "talk%d" % (int(time * 5.0 + phase) % 2)
	var fi := maxi(frames.find(fname), 0)
	var tex := Art.tex(path)
	if face_left:
		draw_set_transform(Vector2(feet.x * 2.0, 0), 0, Vector2(-1, 1))
	draw_texture_rect_region(tex, Rect2((feet - Vector2(12, 24)).round(), Vector2(24, 24)), Rect2(fi * 24, 0, 24, 24), mod)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
