extends SceneTree
## Generates every PNG used by the game from code + ASCII art.
## Run:  godot --headless --path . --script res://tools/gen_art.gd

const Tiles = preload("res://tools/art_tiles.gd")
const Sprites = preload("res://tools/art_sprites.gd")
const Bg = preload("res://tools/art_bg.gd")
const FontGen = preload("res://tools/art_font.gd")


func _save(img: Image, path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var err := img.save_png(abs_path)
	if err != OK:
		push_error("failed to save " + path)


func _sheet(frames: Array, fw: int, fh: int, pal: Dictionary = {}) -> Image:
	var img := Image.create(fw * frames.size(), fh, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in frames.size():
		Sprites.blit_ascii(img, frames[i], i * fw, 0, pal)
	return img


func _init() -> void:
	var index := {}
	# Tilesets
	for name in Tiles.SETS.keys():
		_save(Tiles.build(name), "res://assets/tiles/%s.png" % name)

	# Player + the Grin (palette swap)
	var mira := Sprites.mira_frames()
	_save(_sheet(mira, 16, 16), "res://assets/sprites/player.png")
	var grin_pal := {"s": "e8e4f0", "d": "b8b0c8", "h": "1a1026", "c": "3a1f5a", "C": "24133a",
		"y": "d8344f", "w": "2a1a3a", "W": "1a1026", "t": "5a2a7a", "T": "3a1a52", "p": "d8344f",
		"P": "8f1f35", "l": "120a1a", "b": "2a1a3a", "m": "ff3a5a", "e": "ff3a5a"}
	_save(_sheet(mira, 16, 16, grin_pal), "res://assets/sprites/grin.png")
	index["mira_frames"] = Sprites.MIRA_FRAMES

	# NPCs
	_save(_sheet(Sprites.BELLAMY, 16, 24), "res://assets/sprites/npc_bellamy.png")
	_save(_sheet(Sprites.TOBI, 16, 16), "res://assets/sprites/npc_tobi.png")
	_save(_sheet(Sprites.ODDO, 16, 24), "res://assets/sprites/npc_oddo.png")
	_save(_sheet(Sprites.MAGPIE, 8, 8), "res://assets/sprites/magpie.png")

	# Objects (+ palette variants)
	var objs: Array = []
	var names: Array = []
	for n in Sprites.OBJECT_ORDER:
		objs.append([Sprites.OBJECTS[n], {}])
		names.append(n)
	var gold := {"o": "ffe066", "O": "fff6c0", "R": "c9a227", "g": "f2c14e", "G": "b8862a"}
	objs.append([Sprites.OBJECTS["berry0"], gold]); names.append("gold0")
	objs.append([Sprites.OBJECTS["berry1"], gold]); names.append("gold1")
	var ghost := {"o": "7a8ab8", "O": "a8b8e0", "R": "4a5a8a", "g": "6a7aa8", "G": "4a5a88"}
	objs.append([Sprites.OBJECTS["berry0"], ghost]); names.append("ghost0")
	objs.append([Sprites.OBJECTS["berry1"], ghost]); names.append("ghost1")
	var twin := {"g": "ff7ab8", "G": "b83a7a"}
	objs.append([Sprites.OBJECTS["gem0"], twin]); names.append("twin0")
	objs.append([Sprites.OBJECTS["gem1"], twin]); names.append("twin1")
	var gem_out := {"g": "2a4a3a", "G": "1a2a24", "z": "3a5a4a"}
	objs.append([Sprites.OBJECTS["gem0"], gem_out]); names.append("gem_empty")
	var ghost_bell := {"y": "7a8ab8", "Y": "4a5a8a", "z": "a8b8e0", "x": "8a9ac8"}
	objs.append([Sprites.OBJECTS["bell0"], ghost_bell]); names.append("bell_ghost")
	var cols := 16
	var rows := int(ceil(objs.size() / float(cols)))
	var oimg := Image.create(cols * 16, rows * 16, false, Image.FORMAT_RGBA8)
	oimg.fill(Color(0, 0, 0, 0))
	var oindex := {}
	for i in objs.size():
		Sprites.blit_ascii(oimg, objs[i][0], (i % cols) * 16, (i / cols) * 16, objs[i][1])
		oindex[names[i]] = i
	_save(oimg, "res://assets/sprites/objects.png")
	index["objects"] = oindex

	# Portraits
	var chars := ["mira", "grin", "bellamy", "tobi", "oddo"]
	var maxc := 0
	for ch in chars:
		maxc = maxi(maxc, Sprites.PORTRAIT_SETS[ch].size())
	var pimg := Image.create(maxc * 32, chars.size() * 32, false, Image.FORMAT_RGBA8)
	pimg.fill(Color(0, 0, 0, 0))
	var pindex := {}
	for r in chars.size():
		var ch: String = chars[r]
		var set: Array = Sprites.PORTRAIT_SETS[ch]
		pindex[ch] = {}
		for col in set.size():
			var e: Array = set[col]
			var p := Sprites.portrait(ch, e[1], e[2])
			pimg.blit_rect(p, Rect2i(0, 0, 32, 32), Vector2i(col * 32, r * 32))
			pindex[ch][e[0]] = [col, r]
	_save(pimg, "res://assets/sprites/portraits.png")
	index["portraits"] = pindex

	# Font
	var f := FontGen.build()
	_save(f.image, "res://assets/font.png")
	index["font_widths"] = Array(f.widths)

	# Backgrounds
	for ch in 9:
		var b := Bg.build(ch)
		_save(b.sky, "res://assets/bg/ch%d_sky.png" % ch)
		_save(b.far, "res://assets/bg/ch%d_far.png" % ch)
		_save(b.near, "res://assets/bg/ch%d_near.png" % ch)

	# Icon: Mira's happy portrait scaled 2x
	var icon := Sprites.portrait("mira", "happy", "smile")
	var bgc := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	bgc.fill(Color.html("#2b1d4a"))
	bgc.blend_rect(icon, Rect2i(0, 0, 32, 32), Vector2i.ZERO)
	# recolour cap key to gold for the icon
	for y in 32:
		for x in 32:
			var px := bgc.get_pixel(x, y)
			if px.is_equal_approx(Color.html("#ff00ff")):
				bgc.set_pixel(x, y, Color.html("#f2c14e"))
			elif px.is_equal_approx(Color.html("#c000c0")):
				bgc.set_pixel(x, y, Color.html("#b8862a"))
	bgc.resize(128, 128, Image.INTERPOLATE_NEAREST)
	_save(bgc, "res://assets/icon.png")

	var fa := FileAccess.open("res://assets/art_index.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify(index, "\t"))
	fa.close()
	print("art generated")
	quit()
