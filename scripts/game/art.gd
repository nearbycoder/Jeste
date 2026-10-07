class_name Art
extends RefCounted
## Central access to generated textures (see tools/gen_art.gd).

const CHAPTER_TILESETS := ["meadow", "town", "dream", "carnival", "ridge", "cathedral", "undertow", "summit", "village"]

static var _index: Dictionary = {}
static var _tex: Dictionary = {}
static var _img: Dictionary = {}


static func clear_cache() -> void:
	_tex.clear()
	_img.clear()


static func index() -> Dictionary:
	if _index.is_empty():
		var f := FileAccess.open("res://assets/art_index.json", FileAccess.READ)
		if f:
			_index = JSON.parse_string(f.get_as_text())
	return _index


static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		var t: Texture2D = null
		if ResourceLoader.exists(path):
			t = load(path)
		if t == null:
			var img := Image.load_from_file(path)
			if img:
				t = ImageTexture.create_from_image(img)
		_tex[path] = t
	return _tex[path]


static func image(path: String) -> Image:
	if not _img.has(path):
		var t := tex(path)
		var img: Image = t.get_image() if t else Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.convert(Image.FORMAT_RGBA8)
		_img[path] = img
	return _img[path]


static func tileset_image(name: String) -> Image:
	return image("res://assets/tiles/%s.png" % name)


static func objects() -> Texture2D:
	return tex("res://assets/sprites/objects.png")


## The objects sheet as pale shapes with a dark rim, for the Route Ghost's
## own berries, bells, keys, gems and balloons: drawn in her tint they read
## as hers, unlike the player's full-colour items and slate found-berry
## outlines.
static func objects_ghost() -> Texture2D:
	const KEY := "objects_ghost"
	if not _tex.has(KEY):
		var src := image("res://assets/sprites/objects.png")
		var w := src.get_width()
		var h := src.get_height()
		var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var c := src.get_pixel(x, y)
				if c.a > 0.0:
					var v := 0.4 + 0.6 * c.get_luminance()
					out.set_pixel(x, y, Color(v, v, v, c.a))
					continue
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = Vector2i(x, y) + d
					# only within the same 16x16 cell
					if n.x / 16 == x / 16 and n.y / 16 == y / 16 and n.x >= 0 and n.y >= 0 and n.x < w and n.y < h and src.get_pixel(n.x, n.y).a > 0.0:
						out.set_pixel(x, y, Color(0.1, 0.12, 0.25, 1.0))
						break
		_tex[KEY] = ImageTexture.create_from_image(out)
	return _tex[KEY]


static func obj_rect(name: String) -> Rect2:
	var i: int = int(index().get("objects", {}).get(name, 0))
	return Rect2((i % 16) * 16, (i / 16) * 16, 16, 16)


static func player() -> Texture2D:
	return tex("res://assets/sprites/player.png")


static func player_menu() -> Texture2D:
	return tex("res://assets/sprites/player_menu.png")


static func grin() -> Texture2D:
	return tex("res://assets/sprites/grin.png")


static func frame_index(name: String) -> int:
	var frames: Array = index().get("mira_frames", [])
	return maxi(frames.find(name), 0)


static func portraits() -> Texture2D:
	return tex("res://assets/sprites/portraits.png")


## variant: 0 base, 1 blink, 2 talking, 3 blink + talking
static func portrait_rect(character: String, expr: String, variant: int = 0) -> Rect2:
	var p: Dictionary = index().get("portraits", {}).get(character, {})
	var cr: Array = p.get(expr, p.get("normal", [0, 0]))
	return Rect2((int(cr[0]) + variant) * 32, int(cr[1]) * 32, 32, 32)


static func has_portrait(character: String) -> bool:
	return index().get("portraits", {}).has(character)


static func bg(chapter: int, layer: String) -> Texture2D:
	return tex("res://assets/bg/ch%d_%s.png" % [chapter, layer])


static func font() -> Texture2D:
	return tex("res://assets/font.png")


static func font_widths() -> Array:
	return index().get("font_widths", [])
