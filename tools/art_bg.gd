extends RefCounted
## Painted parallax backgrounds, one art-directed set per chapter.
## Layers (all tile horizontally at W except the static sky):
##   sky   320x180  gradient (ordered-dither smooth), sun/moon, stars, glow
##   far   640x180  distant range, heavy atmospheric haze toward the horizon
##   mid   640x180  closer range / skyline with lighting from the sun side
##   near  640x180  dark foreground silhouettes (trees, roofs, tents...)
## The game also adds runtime clouds, fog bands and light shafts.

const W := 640
const H := 180

const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]


static func c(hex: String) -> Color:
	return Color.html("#" + hex)


static func _h(x: int, y: int, s: int) -> int:
	var h := (x * 374761393 + y * 668265263 + s * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return h ^ (h >> 16)


## Smooth periodic value noise in [0,1], period W (tileable).
static func noise1(x: float, freq: int, seed: int) -> float:
	var fx := x / W * freq
	var i := int(floor(fx))
	var t := fx - i
	var a := float(_h(posmod(i, freq), 0, seed) % 1000) / 1000.0
	var b := float(_h(posmod(i + 1, freq), 0, seed) % 1000) / 1000.0
	t = t * t * (3.0 - 2.0 * t)
	return lerpf(a, b, t)


static func fbm(x: float, base_freq: int, octaves: int, seed: int) -> float:
	var v := 0.0
	var amp := 1.0
	var tot := 0.0
	var f := base_freq
	for o in octaves:
		v += noise1(x, f, seed + o * 17) * amp
		tot += amp
		amp *= 0.5
		f *= 2
	return v / tot


## Ridged fbm gives sharp mountain crests.
static func ridged(x: float, base_freq: int, octaves: int, seed: int) -> float:
	var v := 0.0
	var amp := 1.0
	var tot := 0.0
	var f := base_freq
	for o in octaves:
		var n := 1.0 - absf(noise1(x, f, seed + o * 31) * 2.0 - 1.0)
		v += n * n * amp
		tot += amp
		amp *= 0.5
		f *= 2
	return v / tot


static func dither_mix(a: Color, b: Color, t: float, x: int, y: int, steps: int = 8) -> Color:
	var q: float = t * steps + (BAYER[(y % 4) * 4 + (x % 4)] / 16.0) - 0.5
	return a.lerp(b, clampf(floorf(q + 0.5) / steps, 0.0, 1.0))


static func gradient(img: Image, stops: Array) -> void:
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
		var lt: float = (t - a[0]) / maxf(b[0] - a[0], 0.0001)
		for x in w:
			img.set_pixel(x, y, dither_mix(a[1], b[1], lt, x, y, 10))


static func glow(img: Image, cx: int, cy: int, r: float, col: Color, strength: float) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in range(maxi(0, int(cy - r)), mini(h, int(cy + r) + 1)):
		for x in range(maxi(0, int(cx - r)), mini(w, int(cx + r) + 1)):
			var d := Vector2(x - cx, y - cy).length() / r
			if d >= 1.0:
				continue
			var k := pow(1.0 - d, 2.0) * strength
			img.set_pixel(x, y, dither_mix(img.get_pixel(x, y), col, k, x, y, 8))


static func disc(img: Image, cx: int, cy: int, r: int, col: Color, shade: Color, crater := false) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var dx := x - cx
			var dy := y - cy
			if dx * dx + dy * dy > r * r:
				continue
			var k := clampf((dx + dy) / float(r * 2) + 0.5, 0.0, 1.0)
			var col2 := dither_mix(col, shade, k * 0.6, x, y, 4)
			if crater and _h(x / 3, y / 3, 5) % 9 == 0:
				col2 = col2.darkened(0.08)
			img.set_pixel(x, y, col2)


static func stars(img: Image, count: int, seed: int, max_y: int) -> void:
	for i in count:
		var x := _h(i, 1, seed) % img.get_width()
		var y := _h(i, 2, seed) % max_y
		var fade := 1.0 - float(y) / max_y
		var b := (0.35 + float(_h(i, 3, seed) % 65) / 100.0) * fade
		var base := img.get_pixel(x, y)
		img.set_pixel(x, y, base.lerp(c("fff6e0"), b))
		if _h(i, 4, seed) % 14 == 0 and x > 1 and y > 1 and x < img.get_width() - 2 and y < max_y - 2:
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				img.set_pixel(x + d.x, y + d.y, img.get_pixel(x + d.x, y + d.y).lerp(c("fff6e0"), b * 0.45))


## A lit mountain range. `haze` blends toward `haze_col` (atmospheric perspective).
static func range_layer(img: Image, base_y: float, amp: float, freq: int, seed: int, rock: Color, shadow: Color,
		snow_line: float, snow: Color, haze_col: Color, haze: float, sun_left := true) -> void:
	var hts := PackedFloat32Array()
	hts.resize(W + 1)
	for x in W + 1:
		hts[x] = base_y - ridged(float(x), freq, 5, seed) * amp
	var mid := rock.lerp(shadow, 0.5)
	for x in W:
		var top := int(hts[x])
		# smoothed slope -> which way this flank faces
		var slope := (hts[posmod(x + 3, W)] - hts[posmod(x - 3, W)]) / 6.0
		var face := slope if sun_left else -slope
		var side := 1.0 if slope > 0.0 else -1.0
		for y in range(maxi(top, 0), H):
			var depth := float(y - top)
			# gullies running down the flank, fading with depth
			var u := float(x) + side * depth * 0.8
			var dg := fbm(posmod(u + 1.0, W), freq * 6, 3, seed + 9) - fbm(posmod(u - 1.0, W), freq * 6, 3, seed + 9)
			var l := clampf(face * 2.2, -1.0, 1.0) * maxf(0.0, 1.0 - depth / 60.0) + dg * 10.0 * (1.0 if sun_left else -1.0)
			var col: Color
			if l > 0.25:
				col = rock
			elif l > -0.25:
				col = dither_mix(mid, rock, (l + 0.25) * 2.0, x, y, 4)
			else:
				col = dither_mix(shadow, mid, clampf(l + 1.0, 0.0, 1.0), x, y, 4)
			# subtle vertical gradient: darker toward the base
			col = col.darkened(clampf(depth / 160.0, 0.0, 0.25))
			var jag := _h(x, 0, seed + 3) % 4
			if y < snow_line + jag and depth < 24.0 + float(_h(x / 3, 1, seed) % 10):
				col = snow if l > -0.1 else snow.lerp(shadow, 0.45)
			# ridge highlight
			if depth < 1.0 and l > -0.2:
				col = col.lightened(0.18)
			var hz := clampf(haze + float(y - base_y + amp) / H * 0.25, 0.0, 0.92)
			col = dither_mix(col, haze_col, hz, x, y, 6)
			img.set_pixel(x, y, col)


static func pine(img: Image, x0: int, base: int, height: int, col: Color, lit: Color) -> void:
	for row in height:
		var t := float(row) / height
		var half := int(t * height * 0.42) + 1
		# layered boughs: notch every few rows
		if row % 4 == 3 and row > 2:
			half -= 1
		var y := base - height + row
		if y < 0 or y >= H:
			continue
		for dx in range(-half, half + 1):
			var px := posmod(x0 + dx, img.get_width())
			img.set_pixel(px, y, lit if (dx < 0 and dx > -half + 0 and row % 4 == 0) else col)
	for y in range(base, mini(base + 3, H)):
		img.set_pixel(posmod(x0, img.get_width()), y, col)


static func cloud(img: Image, cx: int, cy: int, size: int, seed: int, lit: Color, mid: Color, dark: Color, alpha := 1.0) -> void:
	var blobs := []
	var n := 4 + _h(seed, 1, 7) % 4
	for i in n:
		var ox := (i - n / 2) * size + _h(seed, i, 9) % size - size / 2
		var oy := -int(absf(i - n / 2.0)) * size / 3 + _h(seed, i, 11) % 3
		var r := size + _h(seed, i, 13) % size
		blobs.append([ox, oy, r])
	var w := img.get_width()
	for b in blobs:
		var r: int = b[2]
		for y in range(-r, r / 2 + 1):
			for x in range(-r, r + 1):
				if x * x + y * y > r * r:
					continue
				var px := posmod(cx + b[0] + x, w)
				var py: int = cy + b[1] + y
				if py < 0 or py >= img.get_height():
					continue
				var k := clampf((float(y) / r + 1.0) / 1.6, 0.0, 1.0)
				var col := dither_mix(lit, mid, k * 1.4, px, py, 4)
				if k > 0.75:
					col = dither_mix(col, dark, (k - 0.75) * 3.0, px, py, 4)
				var base := img.get_pixel(px, py)
				img.set_pixel(px, py, base.lerp(col, alpha) if base.a > 0.0 else Color(col.r, col.g, col.b, alpha))


static func house(img: Image, x0: int, ground: int, w: int, h: int, wall: Color, roof: Color, win: Color, snow: Color, seed: int) -> void:
	var iw := img.get_width()
	for y in range(ground - h, H):
		for x in range(x0, x0 + w):
			img.set_pixel(posmod(x, iw), y, wall)
	# pitched roof
	var rh := w / 2 + 2
	for row in rh:
		var half := int(float(row) / rh * (w / 2 + 2))
		var y := ground - h - rh + row
		for dx in range(-half, half + 1):
			var col := roof
			if row < 2 and snow.a > 0.0:
				col = snow
			img.set_pixel(posmod(x0 + w / 2 + dx, iw), y, col)
	if snow.a > 0.0:
		for dx in range(-(w / 2 + 2), w / 2 + 3):
			if _h(x0 + dx, 1, seed) % 3 != 0:
				img.set_pixel(posmod(x0 + w / 2 + dx, iw), ground - h, snow)
	# chimney
	if _h(x0, 2, seed) % 2 == 0:
		var chx := x0 + w - 5
		for y in range(ground - h - rh + 1, ground - h - rh / 2):
			img.set_pixel(posmod(chx, iw), y, wall)
			img.set_pixel(posmod(chx + 1, iw), y, wall)
	# windows (warm, some lit)
	var wy := ground - h + 4
	while wy < ground - 4:
		var wx := x0 + 3
		while wx < x0 + w - 4:
			if _h(wx, wy, seed) % 3 != 0:
				for yy in 3:
					for xx in 2:
						img.set_pixel(posmod(wx + xx, iw), wy + yy, win)
				img.set_pixel(posmod(wx, iw), wy, win.lightened(0.35))
			wx += 6
		wy += 7


## Mount Jeste: two sharp peaks like a jester's cap, painted with gullies
## running down the flanks, a lit and a shadowed face, broken snowfields and
## a warm rim light along every ridge.
static func jester_peaks(img: Image, p1: Vector2, p2: Vector2, slope: float, pal: Dictionary, haze_col: Color, haze: float, max_y: int = H) -> void:
	for x in W:
		var f1 := clampf(absf(x - p1.x) / 24.0, 0.0, 1.0)
		var f2 := clampf(absf(x - p2.x) / 24.0, 0.0, 1.0)
		var e1 := p1.y + absf(x - p1.x) * slope + (ridged(float(x), 20, 4, 5) - 0.45) * 14.0 * f1
		var e2 := p2.y + absf(x - p2.x) * slope * 1.06 + (ridged(float(x), 20, 4, 6) - 0.45) * 14.0 * f2
		var own1 := e1 <= e2
		var top := int(minf(e1, e2))
		var pk := p1 if own1 else p2
		var side := -1.0 if x < pk.x else 1.0
		for y in range(maxi(top, 0), max_y):
			var depth := float(y - top)
			# gullies follow the flank: constant along lines parallel to the slope
			var u := float(x) - side * (y - pk.y) * 0.7
			var sd := 91 + (0 if own1 else 7)
			var g := fbm(posmod(u, W), 40, 4, sd)
			var dg := fbm(posmod(u + 1.5, W), 40, 4, sd) - fbm(posmod(u - 1.5, W), 40, 4, sd)
			var l := (0.55 if side < 0.0 else -0.35) - dg * side * 14.0
			# notch between the peaks sits in shadow
			if not own1 and x < p2.x and x > p1.x:
				l -= 0.25
			var snow := y < pk.y + 30.0 + g * 26.0 + (6.0 if l > 0.2 else 0.0)
			var col: Color
			if snow:
				col = pal.snow if l > 0.45 else (pal.snow_mid if l > -0.1 else pal.snow_shadow)
			else:
				col = pal.lit if l > 0.45 else (pal.mid if l > -0.1 else (pal.shadow if l > -0.6 else pal.deep))
				col = dither_mix(col, pal.deep, clampf(depth / 140.0, 0.0, 0.5), x, y, 6)
			# rim light on the silhouette
			if depth < 1.0:
				col = pal.rim
			elif depth < 2.0 and side < 0.0:
				col = col.lerp(pal.rim, 0.5)
			var hz := clampf(haze + (y - pk.y - 30.0) / float(H) * 0.7, 0.0, 0.88)
			img.set_pixel(x, y, dither_mix(col, haze_col, hz, x, y, 8))


## Gothic stained-glass window: equilateral pointed arch, twin lancets under a
## rose window, diamond lead lattice, jewel glass that dims toward the sill.
static func gothic_window(img: Image, cx: int, top: int, bottom: int, w: int, pal: Array, seed: int) -> void:
	var half := w / 2.0
	var spring := top + w * 0.866
	var stone_lt := c("2a4a50")
	var stone := c("16282c")
	var lead := c("0c1214")
	var inside_arch := func(x: float, y: float, cxx: float, hw: float, tp: float) -> bool:
		var sp := tp + hw * 2.0 * 0.866
		if y >= sp:
			return absf(x - cxx) <= hw
		if y < tp:
			return false
		return Vector2(x - (cxx + hw), y - sp).length() <= hw * 2.0 and Vector2(x - (cxx - hw), y - sp).length() <= hw * 2.0
	var rose_c := Vector2(cx, top + w * 0.62)
	var rose_r := w * 0.27
	var lan_top := rose_c.y + rose_r - 2.0
	for y in range(top - 3, bottom + 3):
		for x in range(int(cx - half) - 3, int(cx + half) + 4):
			var px := posmod(x, W)
			var fx := x + 0.5
			var fy := y + 0.5
			var outer: bool = inside_arch.call(fx, fy, float(cx), half + 3.0, float(top) - 3.0 * 1.15) and y < bottom + 3
			if not outer:
				continue
			var inner: bool = inside_arch.call(fx, fy, float(cx), half, float(top)) and y < bottom
			if not inner:
				# carved stone frame, lit on the left
				img.set_pixel(px, y, stone_lt if fx < cx else stone)
				continue
			var col: Color
			var dr := Vector2(fx, fy).distance_to(rose_c)
			var in_l: bool = inside_arch.call(fx, fy, cx - half / 2.0 - 0.5, half / 2.0 - 1.5, lan_top)
			var in_r: bool = inside_arch.call(fx, fy, cx + half / 2.0 + 0.5, half / 2.0 - 1.5, lan_top)
			if dr <= rose_r:
				# rose window: 12 petals and two rings of lead
				var ang := atan2(fy - rose_c.y, fx - rose_c.x)
				var sector := int(floor((ang + PI) / TAU * 12.0))
				var ring := 0 if dr < rose_r * 0.35 else (1 if dr < rose_r * 0.72 else 2)
				var edge := absf(fmod((ang + PI) / TAU * 12.0, 1.0) - 0.5) > 0.42 and ring > 0
				if edge or absf(dr - rose_r * 0.35) < 0.7 or absf(dr - rose_r * 0.72) < 0.7 or dr > rose_r - 1.0:
					col = lead
				else:
					col = pal[(sector * (ring + 1) + ring * 3 + seed) % pal.size()]
					if ring == 0:
						col = c("f8e070")
					col = col.lightened(0.12)
			elif in_l or in_r:
				if (x + y) % 6 == 0 or (x - y + 600) % 6 == 0:
					col = lead
				else:
					var cell := _h((x + y) / 6 + (x - y + 600) / 6 * 7, int(in_r), seed)
					col = pal[cell % pal.size()]
					# a brighter medallion in each lancet
					var my := lan_top + (bottom - lan_top) * 0.42
					var md := Vector2(fx - (cx - half / 2.0 if in_l else cx + half / 2.0), (fy - my) * 0.7).length()
					if md < half * 0.32:
						col = col.lightened(0.25)
					if absf(md - half * 0.32) < 0.6:
						col = lead
				# light falls from above: glass dims toward the sill
				var dim := clampf((fy - lan_top) / float(bottom - lan_top), 0.0, 1.0) * 0.45
				if col != lead:
					col = dither_mix(col, c("0a1a1e"), dim, x, y, 6)
			else:
				col = stone if fx < cx else stone.darkened(0.2)
				if absf(fx - cx) < 1.2:
					col = stone_lt
			img.set_pixel(px, y, col)
	# sill
	for x in range(int(cx - half) - 4, int(cx + half) + 5):
		img.set_pixel(posmod(x, W), bottom + 3, stone_lt)
		img.set_pixel(posmod(x, W), bottom + 4, stone)


static func build(chapter: int) -> Dictionary:
	var sky := Image.create(320, 180, false, Image.FORMAT_RGBA8)
	var far := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var mid := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var near := Image.create(W, H, false, Image.FORMAT_RGBA8)
	far.fill(Color(0, 0, 0, 0))
	mid.fill(Color(0, 0, 0, 0))
	near.fill(Color(0, 0, 0, 0))
	match chapter:
		0:  # dusk at the foot of the mountain
			gradient(sky, [[0.0, c("1e1638")], [0.35, c("4a2a5c")], [0.62, c("a8486a")], [0.82, c("e8805e")], [1.0, c("f6c27a")]])
			stars(sky, 50, 1, 70)
			glow(sky, 236, 146, 70, c("ffd890"), 0.55)
			disc(sky, 236, 146, 13, c("fff0c0"), c("ffc880"))
			# Mount Jeste: two peaks like a jester's cap, backlit by the sunset
			jester_peaks(far, Vector2(210, 30), Vector2(286, 42), 0.95, {
				"rim": c("ffc4a8"), "lit": c("6e4c88"), "mid": c("553a70"), "shadow": c("3e2a56"), "deep": c("2c1e42"),
				"snow": c("fae8f2"), "snow_mid": c("d4bce0"), "snow_shadow": c("9a84bc")}, c("a8486a"), 0.0)
			for k in 5:
				cloud(far, 150 + k * 38 + _h(k, 1, 8) % 20, 96 + _h(k, 2, 8) % 16, 5 + k % 3, 8 + k, c("ffc8b0"), c("d88898"), c("8a4a72"), 0.92)
			range_layer(mid, 150, 40, 6, 7, c("4a3048"), c("33213a"), -1, Color.WHITE, c("c06070"), 0.35)
			for i in 90:
				var x := _h(i, 1, 21) % W
				pine(near, x, 168 + _h(i, 2, 21) % 10, 18 + _h(i, 3, 21) % 22, c("161220"), c("2a2236"))
			for x in W:
				for y in range(172, H):
					near.set_pixel(x, y, c("161220"))
		1:  # night over Lantern Town
			gradient(sky, [[0.0, c("05081c")], [0.55, c("161c48")], [1.0, c("3a3a76")]])
			stars(sky, 170, 11, 150)
			glow(sky, 70, 38, 40, c("8090c8"), 0.35)
			disc(sky, 70, 38, 10, c("f4f2dc"), c("b8b8c8"), true)
			range_layer(far, 108, 60, 5, 13, c("2c3462"), c("1e2448"), 70, c("8c9ac8"), c("3a3a76"), 0.25)
			range_layer(mid, 140, 30, 8, 14, c("1c2244"), c("141832"), 118, c("5a6694"), c("2a2c5c"), 0.15)
			var x := 0
			var i := 0
			while x < W:
				var hw := 22 + _h(i, 1, 17) % 26
				var hh := 16 + _h(i, 2, 17) % 26
				house(near, x, 160, hw, hh, c("0e1024"), c("141632"), c("ffc860"), c("8090b8"), 17 + i)
				x += hw + 2 + _h(i, 3, 17) % 12
				i += 1
			for xx in W:
				for y in range(160, H):
					near.set_pixel(xx, y, c("0e1024"))
		2:  # the dream stage
			gradient(sky, [[0.0, c("0c0418")], [0.45, c("2e0e44")], [0.8, c("6a1e5c")], [1.0, c("9a2e6a")]])
			stars(sky, 200, 21, 180)
			glow(sky, 160, 190, 160, c("ff7ab8"), 0.35)
			# floating theatre masks in the far layer
			for k in 12:
				var mx := (k * 53 + 20) % W
				var my := 24 + (k * 37) % 90
				var r := 5 + k % 4
				for yy in range(-r, r + 1):
					for xx in range(-r, r + 1):
						if xx * xx + yy * yy <= r * r:
							far.set_pixel(posmod(mx + xx, W), my + yy, c("4a1e66") if xx < 0 else c("3a1652"))
				far.set_pixel(posmod(mx - 2, W), my - 1, c("12061f"))
				far.set_pixel(posmod(mx + 2, W), my - 1, c("12061f"))
				for xx in range(-2, 3):
					far.set_pixel(posmod(mx + xx, W), my + 2 + (1 if absi(xx) < 2 else 0) * (1 if k % 2 == 0 else -1), c("12061f"))
			range_layer(mid, 158, 26, 6, 23, c("2e0e3e"), c("200a2c"), -1, Color.WHITE, c("6a1e5c"), 0.2)
			# curtain drapes along the top of the near layer
			for xx in W:
				var drop := int(22 + 12 * sin(xx * 0.06) + 6 * sin(xx * 0.17))
				for y in drop:
					var fold := (xx / 3) % 3
					near.set_pixel(xx, y, [c("6a0f2c"), c("4e0a20"), c("8a1636")][fold])
				near.set_pixel(xx, drop, c("e8b84a") if xx % 4 != 0 else c("a8782a"))
		3:  # carnival at night
			gradient(sky, [[0.0, c("0a0612")], [0.55, c("26102c")], [1.0, c("56203c")]])
			stars(sky, 110, 31, 120)
			glow(sky, 240, 180, 120, c("ff9a5a"), 0.3)
			range_layer(far, 128, 34, 6, 33, c("2a1430"), c("1e0e24"), -1, Color.WHITE, c("46183a"), 0.25)
			# big top tents + ferris wheel silhouettes
			for k in 4:
				var tx := k * 160 + 40 + _h(k, 1, 35) % 50
				var th := 52 + _h(k, 2, 35) % 30
				var half := 44 + _h(k, 3, 35) % 20
				for row in th:
					var hw := int(pow(float(row) / th, 0.75) * half)
					for dx in range(-hw, hw + 1):
						var col := c("1e0c20") if ((dx + 200) / 9) % 2 == 0 else c("2c1028")
						mid.set_pixel(posmod(tx + dx, W), 156 - th + row, col)
				for y in 10:
					mid.set_pixel(posmod(tx, W), 146 - th + y, c("1e0c20"))
				for xx in 6:
					for yy in 3:
						mid.set_pixel(posmod(tx + 1 + xx, W), 146 - th + yy, c("d8344f"))
			var fx := 420
			var fy := 70
			var r := 52
			for a in 720:
				var rad := deg_to_rad(a * 0.5)
				mid.set_pixel(posmod(fx + int(cos(rad) * r), W), fy + int(sin(rad) * r), c("2c1028"))
				if a % 60 == 0:
					for tt in r:
						mid.set_pixel(posmod(fx + int(cos(rad) * tt), W), fy + int(sin(rad) * tt), c("2c1028"))
					for yy in 5:
						for xx in 7:
							mid.set_pixel(posmod(fx + int(cos(rad) * r) - 3 + xx, W), fy + int(sin(rad) * r) + yy, c("ffc860") if yy == 2 and xx % 2 == 0 else c("2c1028"))
			for t in 100:
				mid.set_pixel(posmod(fx - t / 3, W), fy + t, c("2c1028"))
				mid.set_pixel(posmod(fx + t / 3, W), fy + t, c("2c1028"))
			for xx in W:
				for y in range(156, H):
					mid.set_pixel(xx, y, c("1e0c20"))
			# string lights in the near layer
			var cols := [c("ff5a6e"), c("ffd25a"), c("5ad2ff"), c("8aff6e"), c("ff8ae0")]
			for row in 2:
				var y0 := 14 + row * 22
				var sag := 16 - row * 6
				for s in W / 80:
					for i2 in 80:
						var t := float(i2) / 80.0
						var y := y0 + int(sin(t * PI) * sag)
						near.set_pixel(s * 80 + i2, y, c("12080e"))
						if i2 % 8 == 4:
							var col: Color = cols[_h(s, i2 + row * 100, 37) % cols.size()]
							near.set_pixel(s * 80 + i2, y + 1, col)
							near.set_pixel(s * 80 + i2, y + 2, col.darkened(0.3))
		4:  # bright windy ridge
			gradient(sky, [[0.0, c("2f6fc0")], [0.55, c("78b4e6")], [1.0, c("d4ecf8")]])
			glow(sky, 70, 30, 60, c("ffffff"), 0.4)
			for k in 6:
				cloud(sky, 30 + k * 55 + _h(k, 1, 41) % 30, 30 + _h(k, 2, 41) % 60, 6 + k % 3, 41 + k, c("ffffff"), c("dceefa"), c("a8c4e0"))
			range_layer(far, 110, 70, 4, 43, c("8cb0d8"), c("6a8cb8"), 72, c("f4faff"), c("c4dcf0"), 0.35)
			range_layer(mid, 150, 44, 7, 44, c("5a8a52"), c("3e6a3e"), -1, Color.WHITE, c("9ac0d8"), 0.25)
			for k in 10:
				cloud(mid, k * 64 + _h(k, 1, 45) % 40, 150 + _h(k, 2, 45) % 18, 6, 45 + k, c("ffffff"), c("e8f4fc"), c("c0d8ec"), 0.9)
			range_layer(near, 176, 26, 9, 46, c("3a5c34"), c("2a4628"), -1, Color.WHITE, c("3a5c34"), 0.0)
		5:  # mirror cathedral interior
			gradient(sky, [[0.0, c("040b0e")], [1.0, c("142e34")]])
			var glass := [c("2f6f9a"), c("9a2f5a"), c("d9a83a"), c("3a8a5a"), c("6a3aaa"), c("c84a3a")]
			for k in 5:
				var cx := k * 128 + 64
				gothic_window(far, cx, 18, 156, 46, glass, 50 + k)
				# light shaft from the window
				for y in range(60, H):
					for xx in range(-14, 15):
						var sx := cx + xx + (y - 60) / 3
						var a := 0.10 * (1.0 - absf(xx) / 15.0) * (1.0 - float(y - 60) / 140.0)
						if a > 0.0:
							var pp := posmod(sx, W)
							var base := far.get_pixel(pp, y)
							far.set_pixel(pp, y, Color(base.r + a, base.g + a, base.b + a * 0.8, maxf(base.a, a * 2.0)))
			# fluted gothic columns with capitals and bases
			var colr := [c("050d10"), c("0a1a1e"), c("12282e"), c("1c3a42"), c("2a5058")]
			for k in 8:
				var px := k * 80 + 28
				for y in H:
					var cap := y < 12 or y > H - 10
					var wdt := 18 if cap else 14
					var x0 := px - (2 if cap else 0)
					for xx in wdt:
						var t := float(xx) / (wdt - 1)
						var idx := 1 + int(round(sin(t * PI) * 2.0 - t * 0.8))
						if not cap and xx % 4 == 2:
							idx -= 1
						if cap and (y == 11 or y == H - 10 or y % 4 == 0):
							idx = 0 if y % 4 == 0 else 4
						idx = clampi(idx + (1 if xx == 2 else 0), 0, 4)
						mid.set_pixel(posmod(x0 + xx, W), y, colr[idx])
					# soft shadow cast on the right
					if not cap:
						mid.set_pixel(posmod(px + 14, W), y, Color(0, 0, 0, 0.35))
		6:  # undertow caves
			gradient(sky, [[0.0, c("010409")], [0.7, c("061a2c")], [1.0, c("0b2e46")]])
			for i in 90:
				var x := _h(i, 1, 61) % 320
				var y := _h(i, 2, 61) % 180
				sky.set_pixel(x, y, sky.get_pixel(x, y).lerp(c("3fc9a8"), 0.5))
			for layer in 2:
				var img := far if layer == 0 else mid
				var col := c("0a1a2c") if layer == 0 else c("061220")
				for i in 46:
					var x := _h(i, 41, 63 + layer) % W
					var hgt := 14 + _h(i, 42, 63 + layer) % (60 if layer == 0 else 40)
					var half := 3 + _h(i, 43, 63 + layer) % 9
					for row in hgt:
						var hw := int(float(hgt - row) / hgt * half)
						for dx in range(-hw, hw + 1):
							img.set_pixel(posmod(x + dx, W), row, col)
							if H - 1 - row >= 0:
								img.set_pixel(posmod(x + dx + 37, W), H - 1 - row, col)
			for i in 60:
				var x := _h(i, 66, 6) % W
				var y := _h(i, 67, 6) % H
				near.set_pixel(x, y, c("5ff0d0"))
				near.set_pixel(posmod(x + 1, W), y, c("5ff0d0").darkened(0.4))
		7:  # summit sunrise
			gradient(sky, [[0.0, c("16234e")], [0.3, c("4e3e7e")], [0.58, c("c06a8a")], [0.8, c("f4a07a")], [1.0, c("ffe0a0")]])
			stars(sky, 60, 71, 50)
			glow(sky, 160, 176, 110, c("fff0c0"), 0.6)
			disc(sky, 160, 176, 22, c("fff6d8"), c("ffd8a0"))
			range_layer(far, 140, 50, 5, 73, c("d6b8d8"), c("a888b8"), 120, c("fff4ff"), c("f4b090"), 0.45)
			for k in 14:
				cloud(far, k * 46 + _h(k, 1, 74) % 30, 150 + _h(k, 2, 74) % 22, 7, 74 + k, c("fff0e8"), c("f8c8b8"), c("d898a8"))
			range_layer(mid, 168, 34, 8, 75, c("eef2fa"), c("b8c4dc"), 400, c("ffffff"), c("f8d8c8"), 0.15)
		8:  # warm afternoon at Bellamy's
			gradient(sky, [[0.0, c("5fa8d8")], [0.7, c("c4e2f0")], [1.0, c("ffe2b0")]])
			for k in 5:
				cloud(sky, 40 + k * 64, 24 + _h(k, 2, 81) % 40, 6, 81 + k, c("ffffff"), c("eaf4fa"), c("c8dcea"))
			jester_peaks(far, Vector2(420, 26), Vector2(474, 34), 0.9, {
				"rim": c("ffffff"), "lit": c("b0a4c8"), "mid": c("958ab0"), "shadow": c("7a7098"), "deep": c("665c84"),
				"snow": c("ffffff"), "snow_mid": c("e4e0f0"), "snow_shadow": c("bcb4d4")}, c("c4e2f0"), 0.3, 130)
			range_layer(far, 128, 24, 6, 83, c("8aa070"), c("6a8458"), -1, Color.WHITE, c("c4e2f0"), 0.25)
			range_layer(mid, 156, 18, 5, 85, c("5a9a48"), c("447a38"), -1, Color.WHITE, c("8ab070"), 0.1)
			# the bell tower
			for y in range(66, 160):
				for xx in 24:
					mid.set_pixel(120 + xx, y, c("6b4a3a") if xx > 3 else c("8a6450"))
			for row in 22:
				var hw := int(float(row) / 22.0 * 16)
				for dx in range(-hw, hw + 1):
					mid.set_pixel(132 + dx, 44 + row, c("8a3a2a"))
			for yy in 12:
				for xx in 12:
					mid.set_pixel(126 + xx, 78 + yy, c("2a1a14"))
			disc(mid, 132, 86, 4, c("f2c14e"), c("b8862a"))
	return {"sky": sky, "far": far, "mid": mid, "near": near}
