extends RefCounted
## Procedural tileset generator. Each tileset atlas is 16 x 8 tiles of 8x8 px:
##   row 0-1  solid ground, 16 autotile variants (mask: 1 up, 2 right, 4 down, 8 left
##            = neighbour is solid), two texture variations
##   row 2-3  alternate solid material ('%'), same layout
##   row 4    background wall, 16 variants
##   row 5    misc: 0-3 jump-thru (L, M, R, single), 4-7 crumble (L, M, R, single),
##            8 door, 9 cracked, 10 mask A solid, 11 mask A ghost, 12 mask B solid,
##            13 mask B ghost, 14 curtain, 15 curtain highlight
##   row 6    spikes: 0 up, 1 down, 2 left, 3 right

const SETS := {
	"meadow": {"style": "dirt", "base": "5a3d2b", "light": "7d5638", "dark": "3d291f", "outline": "1d1218",
		"top": "4f9a3a", "top_light": "8bd35a", "top_dark": "2f6b2a",
		"alt_style": "brick", "alt_base": "6e6a78", "alt_light": "8e8a99", "alt_dark": "4b4856",
		"bg": "2a1f22", "metal": "c9ced9"},
	"town": {"style": "brick", "base": "4a4f6a", "light": "6a7192", "dark": "30344a", "outline": "14141d",
		"top": "dfe8f5", "top_light": "ffffff", "top_dark": "9fb0d0",
		"alt_style": "plank", "alt_base": "6b4a35", "alt_light": "8f6545", "alt_dark": "4a3123",
		"bg": "1d2030", "metal": "d4d9e6"},
	"dream": {"style": "crystal", "base": "4b2f6b", "light": "7a52a3", "dark": "2f1d47", "outline": "110a1d",
		"top": "c58cff", "top_light": "f0d6ff", "top_dark": "8a56c4",
		"alt_style": "brick", "alt_base": "2f3a6b", "alt_light": "4a5a99", "alt_dark": "1f2747",
		"bg": "1c1230", "metal": "e8d8ff"},
	"carnival": {"style": "plank", "base": "7a3b2e", "light": "a5543f", "dark": "50251c", "outline": "1c0e0d",
		"top": "e8b84a", "top_light": "fff0a0", "top_dark": "a8782a",
		"alt_style": "stripe", "alt_base": "c8324a", "alt_light": "f2eee9", "alt_dark": "8a2033",
		"bg": "2a1418", "metal": "f2d27a"},
	"ridge": {"style": "rock", "base": "8a6f52", "light": "b3946f", "dark": "5c4836", "outline": "221913",
		"top": "7fb84a", "top_light": "b6e374", "top_dark": "4f8a35",
		"alt_style": "plank", "alt_base": "6b5240", "alt_light": "8f7055", "alt_dark": "48362a",
		"bg": "3a2e26", "metal": "dfe4ea"},
	"cathedral": {"style": "marble", "base": "2f5f66", "light": "52909a", "dark": "1d3d43", "outline": "0a1618",
		"top": "cfe6e6", "top_light": "ffffff", "top_dark": "8fb3b5",
		"alt_style": "brick", "alt_base": "5c5470", "alt_light": "7f7699", "alt_dark": "3c364b",
		"bg": "142a2f", "metal": "e6f2f2"},
	"undertow": {"style": "rock", "base": "1f3554", "light": "30527d", "dark": "132238", "outline": "060c17",
		"top": "3fc9a8", "top_light": "9ff5dc", "top_dark": "1f8a73",
		"alt_style": "crystal", "alt_base": "2a2050", "alt_light": "4a3a8a", "alt_dark": "1a1433",
		"bg": "0d1726", "metal": "bfe9ff"},
	"summit": {"style": "ice", "base": "8fa8cc", "light": "c9dcf2", "dark": "61789e", "outline": "222c45",
		"top": "ffffff", "top_light": "ffffff", "top_dark": "d0deef",
		"alt_style": "rock", "alt_base": "5a5f73", "alt_light": "7d8399", "alt_dark": "3c3f4f",
		"bg": "3a4766", "metal": "ffffff"},
	"village": {"style": "brick", "base": "8f5a3c", "light": "b8774f", "dark": "5f3a27", "outline": "21130d",
		"top": "6fae45", "top_light": "a8dc6c", "top_dark": "457a2c",
		"alt_style": "plank", "alt_base": "7a5a3a", "alt_light": "a07850", "alt_dark": "52391f",
		"bg": "3a2a22", "metal": "e0e0e0"},
}


static func _c(hex: String) -> Color:
	return Color.html("#" + hex)


static func _hash(x: int, y: int, s: int) -> int:
	var h := x * 374761393 + y * 668265263 + s * 2147483647
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return absi(h)


## Texture fill colour for material `style` at tile-local pixel (px,py).
static func _fill(style: String, px: int, py: int, variant: int, base: Color, light: Color, dark: Color) -> Color:
	var r := _hash(px, py, variant * 31 + 7) % 100
	match style:
		"dirt":
			if r < 8: return dark
			if r < 13: return light
			if (px + py * 3 + variant) % 11 == 0: return dark
			return base
		"brick":
			var row := py / 4
			var off := 4 if (row + variant) % 2 == 1 else 0
			if py % 4 == 3: return dark
			if (px + off) % 8 == 7: return dark
			if py % 4 == 0 and (px + off) % 8 < 6: return light
			if r < 6: return dark
			return base
		"plank":
			if py % 4 == 3: return dark
			if (px == 2 or px == 6) and py % 4 == 1 and (variant + py / 4) % 2 == 0: return dark
			if py % 4 == 0: return light
			if r < 5: return dark
			return base
		"stripe":
			if (px + py + variant * 4) % 8 < 4: return base
			return light
		"crystal":
			var d := (px + py + variant * 3) % 8
			if d == 0: return light
			if (px - py + 16 + variant) % 8 == 0: return dark
			if r < 6: return light
			return base
		"rock":
			var n := (_hash(px / 3, py / 3, variant) % 100)
			if n < 22: return dark
			if n > 88: return light
			if r < 6: return dark
			return base
		"marble":
			var v := int(abs(sin((px + variant * 5) * 0.9 + py * 0.7) * 10.0))
			if v == 0: return light
			if (px * 2 + py) % 13 == 0: return dark
			return base
		"ice":
			if (px + py * 2 + variant * 3) % 9 == 0: return light
			if (px * 3 - py + 24 + variant) % 11 == 0: return dark
			if r < 10: return light
			return base
	return base


static func _draw_solid(img: Image, ox: int, oy: int, mask: int, variant: int, style: String, pal: Dictionary, has_top: bool, prefix: String) -> void:
	var base := _c(pal[prefix + "base"])
	var light := _c(pal[prefix + "light"])
	var dark := _c(pal[prefix + "dark"])
	var outline := _c(pal.outline)
	var top := _c(pal.top)
	var top_light := _c(pal.top_light)
	var top_dark := _c(pal.top_dark)
	var up_open := mask & 1 == 0
	var right_open := mask & 2 == 0
	var down_open := mask & 4 == 0
	var left_open := mask & 8 == 0
	for py in 8:
		for px in 8:
			var col := _fill(style, px, py, variant, base, light, dark)
			# Edge shading
			if left_open and px == 1: col = col.darkened(0.25)
			if right_open and px == 6: col = col.darkened(0.25)
			if down_open and py == 6: col = col.darkened(0.3)
			if up_open and py == 1: col = col.lightened(0.12)
			# Outlines
			if (left_open and px == 0) or (right_open and px == 7) or (down_open and py == 7) or (up_open and py == 0):
				col = outline
			# Top cap (grass / snow)
			if up_open and has_top:
				var hang := 2 + (_hash(px, 0, variant + 3) % 2)
				if py == 0:
					col = top_light
				elif py == 1:
					col = top
				elif py < hang + 1:
					col = top_dark if (px + variant) % 3 != 0 else top
			# Rounded corners
			var corner := false
			if up_open and left_open and px == 0 and py == 0: corner = true
			if up_open and right_open and px == 7 and py == 0: corner = true
			if down_open and left_open and px == 0 and py == 7: corner = true
			if down_open and right_open and px == 7 and py == 7: corner = true
			if corner:
				col = Color(0, 0, 0, 0)
			img.set_pixel(ox + px, oy + py, col)


static func _draw_bg(img: Image, ox: int, oy: int, mask: int, style: String, pal: Dictionary) -> void:
	var bg := _c(pal.bg)
	var light := bg.lightened(0.12)
	var dark := bg.darkened(0.3)
	for py in 8:
		for px in 8:
			var col := _fill(style, px, py, 0, bg, light, dark)
			if mask & 1 == 0 and py == 0: col = dark
			if mask & 4 == 0 and py == 7: col = dark
			if mask & 8 == 0 and px == 0: col = dark
			if mask & 2 == 0 and px == 7: col = dark
			img.set_pixel(ox + px, oy + py, col)


static func _draw_spike_up(img: Image, ox: int, oy: int, pal: Dictionary) -> void:
	var metal := _c(pal.metal)
	var shade := metal.darkened(0.45)
	var outline := _c(pal.outline)
	var rows := [
		"........",
		"........",
		"........",
		".ab..ab.",
		".ab..ab.",
		"aabbaabb",
		"aabbaabb",
		"kkkkkkkk",
	]
	for y in 8:
		var line: String = rows[y]
		for x in 8:
			var ch := line[x]
			if ch == "a":
				img.set_pixel(ox + x, oy + y, metal)
			elif ch == "b":
				img.set_pixel(ox + x, oy + y, shade)
			elif ch == "k":
				img.set_pixel(ox + x, oy + y, outline)


static func _rotate_tile(img: Image, sx: int, sy: int, dx: int, dy: int, times: int) -> void:
	var tmp := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	tmp.blit_rect(img, Rect2i(sx, sy, 8, 8), Vector2i.ZERO)
	for t in times:
		var r := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		for y in 8:
			for x in 8:
				r.set_pixel(7 - y, x, tmp.get_pixel(x, y))
		tmp = r
	img.blit_rect(tmp, Rect2i(0, 0, 8, 8), Vector2i(dx, dy))


static func build(name: String) -> Image:
	var pal: Dictionary = SETS[name]
	var img := Image.create(128, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for v in 2:
		for m in 16:
			_draw_solid(img, m * 8, v * 8, m, v, pal.style, pal, true, "")
			_draw_solid(img, m * 8, 16 + v * 8, m, v, pal.alt_style, pal, false, "alt_")
	for m in 16:
		_draw_bg(img, m * 8, 32, m, pal.style, pal)
	var outline := _c(pal.outline)
	var metal := _c(pal.metal)
	# Jump-thru planks (row 5, cols 0-3)
	var wood := _c("8a5a3a")
	var wood_l := _c("b07a50")
	var wood_d := _c("5a3a24")
	for i in 4:
		var ox := i * 8
		for px in 8:
			img.set_pixel(ox + px, 40, wood_l)
			img.set_pixel(ox + px, 41, wood)
			img.set_pixel(ox + px, 42, wood_d)
			img.set_pixel(ox + px, 43, outline)
		var left := i == 0 or i == 3
		var right := i == 2 or i == 3
		if left:
			for py in range(40, 44):
				img.set_pixel(ox, py, outline)
			for py in range(44, 47):
				img.set_pixel(ox + 1, py, wood_d)
		if right:
			for py in range(40, 44):
				img.set_pixel(ox + 7, py, outline)
			for py in range(44, 47):
				img.set_pixel(ox + 6, py, wood_d)
	# Crumble (cols 4-7): cracked, shaded boards
	var cr_ramp := [_c("2a1a10"), _c("5a3a22"), _c("7a5232"), _c("9a6c44"), _c("c08c5a")]
	for i in 4:
		var ox := 32 + i * 8
		for py in 8:
			for px in 8:
				var k := 3
				if py == 0: k = 4
				elif py >= 6: k = 1
				elif py == 5: k = 2
				if (px + i * 3) % 7 == 0 and py > 0 and py < 6: k = 2
				img.set_pixel(ox + px, 40 + py, cr_ramp[k])
		img.set_pixel(ox + 2 + (i % 3), 41, cr_ramp[0])
		img.set_pixel(ox + 3 + (i % 3), 42, cr_ramp[0])
		img.set_pixel(ox + 3 + (i % 3), 43, cr_ramp[0])
		img.set_pixel(ox + 5, 44, cr_ramp[0])
		for px in 8:
			img.set_pixel(ox + px, 47, cr_ramp[0])
		if i == 0 or i == 3:
			for py in 8:
				img.set_pixel(ox, 40 + py, cr_ramp[0])
			img.set_pixel(ox + 1, 40, cr_ramp[3])
		if i == 2 or i == 3:
			for py in 8:
				img.set_pixel(ox + 7, 40 + py, cr_ramp[0])
		# nail heads
		img.set_pixel(ox + 1, 41, _c("d8dce8"))
		img.set_pixel(ox + 6, 41, _c("d8dce8"))
	# Door (col 8): riveted iron bars with a gold padlock
	var iron := [_c("101220"), _c("2a2f44"), _c("454c68"), _c("6a7390"), _c("9aa3c0")]
	for py in 8:
		for px in 8:
			var k := 1
			var bar := px % 4
			if bar == 1: k = 3
			elif bar == 2: k = 2
			if py == 0 or py == 7: k = 2
			if bar == 1 and py % 4 == 1: k = 4
			if px == 0 or px == 7: k = 0
			img.set_pixel(64 + px, 40 + py, iron[k])
	var gold := _c("f2c14e")
	var gold_d := _c("a8782a")
	for p in [Vector2i(3, 3), Vector2i(4, 3), Vector2i(3, 4), Vector2i(4, 4), Vector2i(3, 5), Vector2i(4, 5)]:
		img.set_pixel(64 + p.x, 40 + p.y, gold)
	img.set_pixel(67, 42, gold_d); img.set_pixel(68, 42, gold_d)
	img.set_pixel(68, 44, _c("1c1424"))
	img.set_pixel(67, 45, gold_d)
	# Cracked wall (col 9): chapter rock with fracture lines and chips
	for py in 8:
		for px in 8:
			var col := _fill(pal.style, px, py, 1, _c(pal.base), _c(pal.light), _c(pal.dark))
			img.set_pixel(72 + px, 40 + py, col)
	for p in [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 3), Vector2i(4, 3), Vector2i(4, 4), Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 6), Vector2i(3, 4), Vector2i(2, 5), Vector2i(2, 6), Vector2i(5, 1), Vector2i(6, 0)]:
		img.set_pixel(72 + p.x, 40 + p.y, outline)
	for p in [Vector2i(1, 1), Vector2i(3, 2), Vector2i(5, 4), Vector2i(1, 5)]:
		img.set_pixel(72 + p.x, 40 + p.y, _c(pal.light).lightened(0.2))
	# Mask blocks (cols 10-13): porcelain theatre masks
	_draw_mask_block(img, 80, 40, false, true)
	_draw_mask_block(img, 88, 40, false, false)
	_draw_mask_block(img, 96, 40, true, true)
	_draw_mask_block(img, 104, 40, true, false)
	# Curtain (col 14, 15)
	var vel := _c("8a1430")
	var vel_l := _c("c0284a")
	var vel_d := _c("4a0a1c")
	for py in 8:
		for px in 8:
			var f := px % 4
			var col := vel
			if f == 0: col = vel_d
			elif f == 2: col = vel_l
			img.set_pixel(112 + px, 40 + py, col)
			img.set_pixel(120 + px, 40 + py, col.lightened(0.25))
	# Spikes (row 6)
	_draw_spike_up(img, 0, 48, pal)
	_rotate_tile(img, 0, 48, 8, 48, 2)    # down
	_rotate_tile(img, 0, 48, 16, 48, 3)   # left-pointing (mounted on a wall to the right)
	_rotate_tile(img, 0, 48, 24, 48, 1)   # right-pointing
	return img


static func _draw_mask_block(img: Image, ox: int, oy: int, tragedy: bool, solid: bool) -> void:
	# comedy = warm red porcelain with a smile; tragedy = cool blue with a frown
	var ramp := [_c("2a0a14"), _c("8a1f33"), _c("c8344a"), _c("ec5a6e"), _c("ffb0b8")]
	if tragedy:
		ramp = [_c("0a1230"), _c("1f3a8a"), _c("3a64c8"), _c("5a8af0"), _c("b8d0ff")]
	var gold := _c("f2c14e")
	if not solid:
		for py in 8:
			for px in 8:
				var edge := px == 0 or py == 0 or px == 7 or py == 7
				if edge and (px + py) % 3 != 0:
					var cc: Color = ramp[3]
					img.set_pixel(ox + px, oy + py, Color(cc.r, cc.g, cc.b, 0.75))
		img.set_pixel(ox + 2, oy + 3, Color(ramp[3], 0.5))
		img.set_pixel(ox + 5, oy + 3, Color(ramp[3], 0.5))
		return
	for py in 8:
		for px in 8:
			var k := 2
			if py <= 1 or px == 1: k = 3
			if py == 1 and px <= 2: k = 4
			if py >= 6 or px == 6: k = 1
			var c: Color = ramp[k]
			if px == 0 or py == 0 or px == 7 or py == 7:
				c = gold if (px + py) % 2 == 0 and not (px == 0 and py == 0) else _c("a8782a")
			img.set_pixel(ox + px, oy + py, c)
	# eyes
	img.set_pixel(ox + 2, oy + 3, ramp[0]); img.set_pixel(ox + 5, oy + 3, ramp[0])
	if tragedy:
		img.set_pixel(ox + 2, oy + 2, ramp[1]); img.set_pixel(ox + 5, oy + 2, ramp[1])
		img.set_pixel(ox + 2, oy + 6, ramp[0]); img.set_pixel(ox + 3, oy + 5, ramp[0])
		img.set_pixel(ox + 4, oy + 5, ramp[0]); img.set_pixel(ox + 5, oy + 6, ramp[0])
		img.set_pixel(ox + 2, oy + 4, ramp[4])   # tear
	else:
		img.set_pixel(ox + 2, oy + 5, ramp[0]); img.set_pixel(ox + 3, oy + 6, ramp[0])
		img.set_pixel(ox + 4, oy + 6, ramp[0]); img.set_pixel(ox + 5, oy + 5, ramp[0])
		img.set_pixel(ox + 1, oy + 4, ramp[4]); img.set_pixel(ox + 6, oy + 4, ramp[4])  # blush
