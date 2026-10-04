extends RefCounted
## Procedural parallax backgrounds, one set per chapter:
##   sky  (320x180, opaque)   - gradient, stars, sun/moon
##   far  (640x180, alpha)    - distant silhouettes (tileable horizontally)
##   near (640x180, alpha)    - closer silhouettes (tileable horizontally)

const W := 640
const H := 180


static func c(hex: String) -> Color:
	return Color.html("#" + hex)


static func _hash(x: int, y: int, s: int) -> int:
	var h := x * 374761393 + y * 668265263 + s * 1442695041
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return absi(h)


static func gradient(img: Image, stops: Array) -> void:
	# stops: [[t, Color], ...] t in 0..1 top->bottom, dithered between bands
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		var t := float(y) / float(h - 1)
		var a: Array = stops[0]
		var b: Array = stops[stops.size() - 1]
		for i in stops.size() - 1:
			if t >= stops[i][0] and t <= stops[i + 1][0]:
				a = stops[i]
				b = stops[i + 1]
				break
		var span: float = maxf(b[0] - a[0], 0.0001)
		var lt: float = (t - a[0]) / span
		for x in w:
			# ordered dither in 4 steps
			var bayer: int = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5][(y % 4) * 4 + (x % 4)]
			var q := floorf(lt * 6.0 + bayer / 16.0) / 6.0
			img.set_pixel(x, y, (a[1] as Color).lerp(b[1], clampf(q, 0.0, 1.0)))


static func stars(img: Image, count: int, seed: int, col: Color, max_y: int) -> void:
	for i in count:
		var x := _hash(i, 1, seed) % img.get_width()
		var y := _hash(i, 2, seed) % max_y
		var br := 0.4 + float(_hash(i, 3, seed) % 60) / 100.0
		img.set_pixel(x, y, Color(col.r, col.g, col.b, 1.0).lerp(img.get_pixel(x, y), 1.0 - br))
		if _hash(i, 4, seed) % 9 == 0 and x > 0 and y > 0 and x < img.get_width() - 1 and y < max_y - 1:
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				img.set_pixel(x + d.x, y + d.y, col.lerp(img.get_pixel(x + d.x, y + d.y), 0.6))


static func disc(img: Image, cx: int, cy: int, r: int, col: Color, glow: Color = Color(0, 0, 0, 0)) -> void:
	if glow.a > 0.0:
		for y in range(cy - r * 3, cy + r * 3 + 1):
			for x in range(cx - r * 3, cx + r * 3 + 1):
				if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
					continue
				var d := Vector2(x - cx, y - cy).length()
				if d < r * 3:
					var a := (1.0 - d / (r * 3.0)) * glow.a
					if (x + y) % 2 == 0 or a > 0.3:
						img.set_pixel(x, y, img.get_pixel(x, y).lerp(Color(glow.r, glow.g, glow.b), a))
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r:
				img.set_pixel(x, y, col)


## Tileable height function built from integer-frequency sines.
static func height_fn(x: float, base: float, amps: Array, seed: int) -> float:
	var hgt := base
	for i in amps.size():
		var k := i + 1
		var ph := float(_hash(i, 7, seed) % 1000) / 1000.0 * TAU
		hgt += amps[i] * sin(TAU * k * x / W + ph)
	return hgt


static func mountains(img: Image, base: float, amps: Array, seed: int, col: Color, snow_line: float = -1.0, snow: Color = Color.WHITE, shade: Color = Color(0, 0, 0, 0)) -> void:
	var w := img.get_width()
	for x in w:
		var top := int(height_fn(x, base, amps, seed))
		var prev := int(height_fn(x - 1, base, amps, seed))
		for y in range(maxi(top, 0), H):
			var cc := col
			if snow_line >= 0.0 and y < snow_line and y < top + 3 + (_hash(x, y, seed) % 3):
				cc = snow
			elif shade.a > 0.0 and top > prev and y < top + 10:
				cc = col.lerp(shade, 0.5)
			img.set_pixel(x, y, cc)


static func trees(img: Image, base_y: int, count: int, seed: int, col: Color, min_h: int, max_h: int) -> void:
	for i in count:
		var x := _hash(i, 11, seed) % W
		var hgt := min_h + _hash(i, 12, seed) % maxi(max_h - min_h, 1)
		var by := base_y + _hash(i, 13, seed) % 8
		for row in hgt:
			var half := int(float(row) / hgt * (hgt / 2.5)) + 1
			var y := by - hgt + row
			for dx in range(-half, half + 1):
				var px := (x + dx + W) % W
				if y >= 0 and y < H:
					img.set_pixel(px, y, col)
		for y in range(by, H):
			for dx in range(-1, 2):
				img.set_pixel((x + dx + W) % W, y, col)


static func rect(img: Image, x0: int, y0: int, w: int, h: int, col: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			var px := (x + W) % img.get_width()
			if y >= 0 and y < img.get_height():
				img.set_pixel(px, y, col)


static func tri(img: Image, cx: int, top: int, half: int, h: int, col: Color) -> void:
	for row in h:
		var hw := int(float(row) / h * half)
		for dx in range(-hw, hw + 1):
			var px := (cx + dx + W) % img.get_width()
			var y := top + row
			if y >= 0 and y < img.get_height():
				img.set_pixel(px, y, col)


static func houses(img: Image, ground: int, seed: int, col: Color, window: Color) -> void:
	var x := 0
	var i := 0
	while x < W:
		var w := 24 + _hash(i, 21, seed) % 30
		var h := 18 + _hash(i, 22, seed) % 30
		rect(img, x, ground - h, w, H - ground + h, col)
		tri(img, x + w / 2, ground - h - w / 2, w / 2 + 2, w / 2, col)
		if _hash(i, 25, seed) % 3 == 0:
			rect(img, x + w / 2 + 4, ground - h - w / 2 - 4, 4, 10, col)
		for wy in range(ground - h + 5, ground - 4, 9):
			for wx in range(x + 4, x + w - 5, 8):
				if _hash(wx, wy, seed) % 5 < 2:
					rect(img, wx, wy, 3, 4, window)
		x += w + _hash(i, 23, seed) % 14
		i += 1
	rect(img, 0, ground, W, H - ground, col)


static func clouds(img: Image, count: int, seed: int, col: Color, y0: int, y1: int, size: int) -> void:
	var iw := img.get_width()
	for i in count:
		var cx := _hash(i, 31, seed) % iw
		var cy := y0 + _hash(i, 32, seed) % maxi(y1 - y0, 1)
		var n := 4 + _hash(i, 33, seed) % 5
		for j in n:
			var ox := (j - n / 2) * size
			var r := size + _hash(i * 10 + j, 34, seed) % size
			for y in range(-r, r / 2):
				for x in range(-r, r + 1):
					if x * x + y * y * 2 <= r * r:
						var px := (cx + ox + x + iw) % iw
						var py := cy + y
						if py >= 0 and py < H:
							img.set_pixel(px, py, col)


static func lights(img: Image, y0: int, sag: int, seed: int) -> void:
	var cols := [c("ff5a6e"), c("ffd25a"), c("5ad2ff"), c("8aff6e"), c("ff8ae0")]
	var seg := 80
	for s in W / seg:
		var x0 := s * seg
		for i in seg:
			var t := float(i) / seg
			var y := y0 + int(sin(t * PI) * sag)
			img.set_pixel(x0 + i, y, c("1a1020"))
			if i % 8 == 4:
				var col: Color = cols[(_hash(s, i, seed)) % cols.size()]
				img.set_pixel(x0 + i, y + 1, col)
				img.set_pixel(x0 + i, y + 2, col)


static func arches(img: Image, seed: int, col: Color, glass: Array) -> void:
	for i in 5:
		var cx := i * 128 + 64
		var w := 40
		var top := 30
		# window
		for y in range(top, 150):
			for x in range(-w / 2, w / 2 + 1):
				var inside := y > top + w / 2 or (x * x + (y - top - w / 2) * (y - top - w / 2) <= (w / 2) * (w / 2))
				if inside:
					var gc: Color = glass[(_hash((cx + x) / 6, y / 8, seed)) % glass.size()]
					if (x + w / 2) % 10 == 0 or y % 16 == 0:
						gc = col
					img.set_pixel((cx + x + W) % W, y, gc)
		# pillar
		rect(img, cx + 54, 0, 20, H, col)
	rect(img, 0, 150, W, 30, col)


static func stalactites(img: Image, seed: int, col: Color, from_top: bool) -> void:
	for i in 40:
		var x := _hash(i, 41, seed) % W
		var hgt := 10 + _hash(i, 42, seed) % 50
		var half := 3 + _hash(i, 43, seed) % 8
		for row in hgt:
			var hw := int(float(hgt - row) / hgt * half)
			for dx in range(-hw, hw + 1):
				var y := row if from_top else H - 1 - row
				img.set_pixel((x + dx + W) % W, y, col)


static func tents(img: Image, ground: int, seed: int, col: Color, stripe: Color) -> void:
	for i in 4:
		var cx := i * 160 + 50 + _hash(i, 51, seed) % 40
		var hgt := 50 + _hash(i, 52, seed) % 30
		var half := 40 + _hash(i, 53, seed) % 20
		for row in hgt:
			var hw := int(pow(float(row) / hgt, 0.7) * half)
			for dx in range(-hw, hw + 1):
				var y := ground - hgt + row
				var cc := col if ((dx + 200) / 8) % 2 == 0 else stripe
				img.set_pixel((cx + dx + W) % W, y, cc)
		rect(img, cx, ground - hgt - 10, 1, 10, col)
		rect(img, cx + 1, ground - hgt - 10, 6, 4, stripe)
	# ferris wheel
	var fx := 400
	var fy := 70
	var r := 50
	for a in 360:
		var rad := deg_to_rad(a)
		img.set_pixel((fx + int(cos(rad) * r) + W) % W, fy + int(sin(rad) * r), col)
		if a % 30 == 0:
			for t in r:
				img.set_pixel((fx + int(cos(rad) * t) + W) % W, fy + int(sin(rad) * t), col)
			rect(img, fx + int(cos(rad) * r) - 3, fy + int(sin(rad) * r), 7, 6, col)
	for t in 90:
		img.set_pixel(fx - t / 3, fy + t, col)
		img.set_pixel(fx + t / 3, fy + t, col)
	rect(img, 0, ground, W, H - ground, col)


static func build(chapter: int) -> Dictionary:
	var sky := Image.create(320, 180, false, Image.FORMAT_RGBA8)
	var far := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var near := Image.create(W, H, false, Image.FORMAT_RGBA8)
	far.fill(Color(0, 0, 0, 0))
	near.fill(Color(0, 0, 0, 0))
	match chapter:
		0:
			gradient(sky, [[0.0, c("2b1d4a")], [0.45, c("8a3f6b")], [0.8, c("e07a5f")], [1.0, c("f2cc8f")]])
			stars(sky, 40, 1, c("fff2d0"), 60)
			disc(sky, 230, 140, 14, c("ffe3a0"), Color(1, 0.8, 0.5, 0.5))
			# Mount Jeste: twin-peaked like a jester cap
			mountains(far, 110, [6, 4, 3], 3, c("4a2f5e"))
			for x in W:
				var d1 := absf(x - 200.0)
				var d2 := absf(x - 268.0)
				var peak := mini(int(40 + d1 * 0.9), int(48 + d2 * 0.95))
				for y in range(maxi(peak, 0), H):
					var snowy := y < peak + 6 and y < 70
					far.set_pixel(x, y, c("efe6f2") if snowy else c("3a2550"))
			mountains(near, 140, [8, 5, 3, 2], 5, c("1f2a2a"))
			trees(near, 150, 70, 7, c("152020"), 14, 30)
		1:
			gradient(sky, [[0.0, c("070b22")], [0.6, c("1a2050")], [1.0, c("3a3f7a")]])
			stars(sky, 140, 11, c("ffffff"), 140)
			disc(sky, 70, 40, 10, c("f4f1d0"), Color(0.8, 0.85, 1.0, 0.25))
			mountains(far, 90, [14, 9, 6], 13, c("26305e"), 100, c("8a97c8"))
			houses(near, 150, 17, c("10142a"), c("ffcf6a"))
		2:
			gradient(sky, [[0.0, c("12061f")], [0.5, c("3d1450")], [1.0, c("8a2d6e")]])
			stars(sky, 160, 21, c("ffd6ff"), 180)
			for i in 12:
				var mx := (i * 53) % 640
				var my := 30 + (i * 37) % 100
				disc(far, mx, my, 7, c("5a2a7a"))
				far.set_pixel(posmod(mx - 3, W), my - 1, c("12061f")); far.set_pixel(posmod(mx + 3, W), my - 1, c("12061f"))
				for dx in range(-3, 4):
					far.set_pixel(posmod(mx + dx, W), my + 3 - (1 if absi(dx) < 2 else 0) * (1 if i % 2 == 0 else -1), c("12061f"))
			mountains(near, 150, [6, 4, 2], 23, c("2a0d3a"))
			for x in W:
				var drop := int(18 + 10 * sin(x * 0.07) + 6 * sin(x * 0.19))
				for y in drop:
					near.set_pixel(x, y, c("6a0f2c") if (x / 4) % 2 == 0 else c("4a0a20"))
		3:
			gradient(sky, [[0.0, c("0e0716")], [0.6, c("2a1030")], [1.0, c("5a1f3a")]])
			stars(sky, 90, 31, c("fff0d0"), 120)
			tents(far, 150, 33, c("1f0d22"), c("33122e"))
			lights(near, 20, 18, 35)
			lights(near, 44, 10, 36)
		4:
			gradient(sky, [[0.0, c("3f86d0")], [0.6, c("8cc8ee")], [1.0, c("d9f0fa")]])
			clouds(sky, 6, 41, c("f4fbff"), 30, 110, 7)
			mountains(far, 100, [18, 10, 6, 3], 43, c("7aa0c8"), 95, c("eef6ff"), c("5a80a8"))
			clouds(far, 10, 44, c("ffffff"), 120, 160, 6)
			mountains(near, 140, [14, 8, 4, 2], 45, c("4f7a4a"), -1, Color.WHITE, c("3a5c38"))
		5:
			gradient(sky, [[0.0, c("050e12")], [1.0, c("17343a")]])
			arches(far, 51, c("0b1d21"), [c("2f6f8a"), c("8a2f5a"), c("c9a23a"), c("3a8a5a"), c("5a3a9a")])
			for i in 8:
				rect(near, i * 80 + 30, 0, 14, H, c("061114"))
				rect(near, i * 80 + 26, 0, 22, 8, c("061114"))
				rect(near, i * 80 + 26, 170, 22, 10, c("061114"))
		6:
			gradient(sky, [[0.0, c("01050c")], [0.7, c("082036")], [1.0, c("0d3550")]])
			stars(sky, 70, 61, c("3fc9a8"), 180)
			stalactites(far, 63, c("0a1a2c"), true)
			stalactites(far, 64, c("0a1a2c"), false)
			stalactites(near, 65, c("040b14"), true)
			for i in 50:
				var x := _hash(i, 66, 6) % W
				var y := _hash(i, 67, 6) % H
				near.set_pixel(x, y, c("5ff0d0"))
		7:
			gradient(sky, [[0.0, c("1b2a5a")], [0.35, c("6a4a8a")], [0.65, c("f08a7a")], [1.0, c("ffd38a")]])
			stars(sky, 50, 71, c("ffffff"), 50)
			disc(sky, 160, 175, 22, c("fff2c0"), Color(1, 0.85, 0.6, 0.45))
			mountains(far, 130, [10, 6, 3], 73, c("b8a0c8"), 140, c("fff4ff"))
			clouds(far, 14, 74, c("ffe8e0"), 140, 175, 8)
			mountains(near, 158, [8, 5, 3, 2], 75, c("e8eef8"), -1, Color.WHITE, c("b8c4dc"))
		8:
			gradient(sky, [[0.0, c("6fb8e0")], [0.7, c("cfe8f0")], [1.0, c("ffe0a8")]])
			clouds(sky, 5, 81, c("ffffff"), 20, 80, 6)
			mountains(far, 110, [10, 6, 3], 83, c("8aa070"), -1)
			for x in W:
				var d1 := absf(x - 420.0)
				var d2 := absf(x - 470.0)
				var peak := mini(int(30 + d1 * 0.9), int(36 + d2 * 0.95))
				for y in range(maxi(peak, 0), 110):
					far.set_pixel(x, y, c("efe6f2") if y < peak + 5 else c("9a8ab0"))
			mountains(near, 150, [5, 3, 2], 85, c("4f8a3f"))
			# bell tower
			rect(near, 120, 70, 24, 90, c("6b4a3a"))
			tri(near, 132, 50, 16, 20, c("8a3a2a"))
			rect(near, 126, 80, 12, 12, c("2a1a14"))
			disc(near, 132, 88, 4, c("e8b84a"))
	return {"sky": sky, "far": far, "near": near}
