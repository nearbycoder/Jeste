class_name TerrainArt
extends RefCounted
## Per-pixel terrain painter.
##
## Instead of stamping 8x8 tiles, each room is painted pixel by pixel from its
## collision map, the way a pixel artist would shade it:
##   * a 7-step colour ramp per material,
##   * a distance field from the air gives bevelled edges, a top-lit rim and
##     ambient occlusion that deepens inside large masses,
##   * per-material detail (individual bricks, cobbles, planks, ice facets...),
##   * cap layers (grass, snow, moss, gold trim...) with irregular drips,
##   * rounded / chipped convex corners and dithered shade transitions,
##   * hanging decorations under ceilings (icicles, stalactites, vines, roots).
## Collision is untouched - this is purely the look.

const T := 8

# ramp index: 0 outline, 1 deepest, 2 dark, 3 shade, 4 base, 5 light, 6 highlight
const STYLES := {
	"meadow": {
		"ramp": ["1b1120", "2c1a22", "40262a", "573530", "70472f", "8f5e3c", "b07a4e"],
		"pattern": "dirt",
		"alt_ramp": ["1b1622", "2b2733", "3d3946", "524e5d", "6a6677", "86829a", "a7a3b9"],
		"alt_pattern": "stone",
		"cap": "grass", "cap_ramp": ["d0f080", "9ad85a", "6cb244", "4a8a36", "2f5f2c"],
		"hang": "roots", "hang_ramp": ["3a2416", "5a3a24", "7a5236"],
		"bg_ramp": ["24150f", "33201a", "432c22", "54382a"], "bg_pattern": "plank",
	},
	"town": {
		"ramp": ["12111c", "1c1b2b", "28283d", "363852", "47496a", "5d6187", "7c80a6"],
		"pattern": "brick",
		"alt_ramp": ["1a1214", "2a1c1a", "3c2a22", "54392b", "6e4c36", "8c6545", "ab8258"],
		"alt_pattern": "plank",
		"cap": "snow", "cap_ramp": ["ffffff", "e8eef8", "c4d0e6", "98a8c8", "6a7aa0"],
		"hang": "icicle", "hang_ramp": ["7088b8", "a8c0e0", "e8f2ff"],
		"bg_ramp": ["141420", "1a1a2a", "212236", "282a40"], "bg_pattern": "brick",
	},
	"dream": {
		"ramp": ["10091c", "1a102c", "271840", "362258", "482f72", "614294", "8460bc"],
		"pattern": "crystal",
		"alt_ramp": ["0e1024", "171a36", "212650", "2d3468", "3c4686", "5260a8", "7480c8"],
		"alt_pattern": "brick",
		"cap": "crystal", "cap_ramp": ["fff0ff", "f4b8ff", "d488f0", "a85ed0", "7a3aa8"],
		"hang": "crystal", "hang_ramp": ["7a3aa8", "c47ae8", "ffd8ff"],
		"bg_ramp": ["150c22", "1c112e", "24163a", "2c1c46"], "bg_pattern": "crystal",
	},
	"carnival": {
		"ramp": ["1a0c0c", "2a1311", "3f1d18", "582920", "73372a", "934a36", "b5644a"],
		"pattern": "plank",
		"alt_ramp": ["2a0c14", "4a1020", "6e1a2c", "9a2438", "c8344a", "e8586a", "f8f0e8"],
		"alt_pattern": "stripe",
		"cap": "gold", "cap_ramp": ["fff4b0", "f2c94e", "c8962e", "8a5e1e", "4a2e10"],
		"hang": "bunting", "hang_ramp": ["d8344f", "f2c94e", "5ab0e0"],
		"bg_ramp": ["1e0e12", "271318", "31191e", "3b1f25"], "bg_pattern": "plank",
	},
	"ridge": {
		"ramp": ["21170f", "33241a", "4a3526", "634836", "7f5e47", "9d7a5c", "c09c78"],
		"pattern": "stone",
		"alt_ramp": ["1c1612", "2c221a", "403024", "564230", "6e563e", "8a6e50", "a88a66"],
		"alt_pattern": "plank",
		"cap": "grass", "cap_ramp": ["e0f890", "b2e068", "7cbc4a", "568e38", "37632a"],
		"hang": "roots", "hang_ramp": ["3a2a1a", "5a4028", "7a5a3a"],
		"bg_ramp": ["2e241e", "382c24", "42342a", "4c3c30"], "bg_pattern": "stone",
	},
	"cathedral": {
		"ramp": ["091416", "102226", "183136", "224349", "2e5960", "40767e", "5c9aa2"],
		"pattern": "marble",
		"alt_ramp": ["14121c", "1e1b2a", "2a263a", "38334c", "484262", "5e577e", "7c74a0"],
		"alt_pattern": "brick",
		"cap": "silver", "cap_ramp": ["ffffff", "d8eef0", "a8c8cc", "70949a", "40646a"],
		"hang": "cobweb", "hang_ramp": ["a8b8c0", "d0dce0", "ffffff"],
		"bg_ramp": ["0c1a1d", "112226", "162a2f", "1b3338"], "bg_pattern": "marble",
	},
	"undertow": {
		"ramp": ["050a14", "0a1322", "111e34", "1a2c4a", "233c62", "2e507e", "40689e"],
		"pattern": "stone",
		"alt_ramp": ["0c0a1e", "15122e", "1f1a42", "2a2458", "383072", "4a4092", "6456b0"],
		"alt_pattern": "crystal",
		"cap": "moss", "cap_ramp": ["b0fff0", "5ff0d0", "30c8a8", "1f8a78", "125a52"],
		"hang": "stalactite", "hang_ramp": ["111e34", "233c62", "40689e"],
		"bg_ramp": ["080f1c", "0c1626", "101c30", "14223a"], "bg_pattern": "stone",
	},
	"summit": {
		"ramp": ["1e2740", "2e3b5e", "435480", "5c70a0", "7c92c0", "a2b8dc", "d0e0f4"],
		"pattern": "ice",
		"alt_ramp": ["1c1e28", "2a2d3a", "3a3e50", "4c5168", "626884", "7c83a2", "9aa2c0"],
		"alt_pattern": "stone",
		"cap": "snow", "cap_ramp": ["ffffff", "f0f6ff", "d4e2f4", "aabfdc", "7c94bc"],
		"hang": "icicle", "hang_ramp": ["7c92c0", "b8cce8", "ffffff"],
		"bg_ramp": ["34405e", "3c4a6a", "445476", "4c5e82"], "bg_pattern": "ice", "ao_max": 1,
	},
	"village": {
		"ramp": ["1f120c", "301c14", "45291d", "5d3a28", "784d34", "966645", "b8845c"],
		"pattern": "brick",
		"alt_ramp": ["1c140c", "2c2014", "40301e", "56422a", "6e5638", "8a6e48", "a88a5c"],
		"alt_pattern": "plank",
		"cap": "grass", "cap_ramp": ["d8f488", "a4dc62", "72b648", "4e8a36", "33602a"],
		"hang": "vine", "hang_ramp": ["2f5f2c", "4e8a36", "8ad05a"],
		"bg_ramp": ["2a1c16", "33221b", "3c2920", "453025"], "bg_pattern": "brick",
	},
}


static func _h(x: int, y: int, s: int = 0) -> int:
	var h := (x * 374761393 + y * 668265263 + s * 982451653) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return h ^ (h >> 16)


static func _hf(x: int, y: int, s: int = 0) -> float:
	return float(_h(x, y, s) % 10000) / 10000.0


static func _col(hex: String) -> Color:
	return Color.html("#" + hex)


# ---------------------------------------------------------------- material detail patterns
# Return a shade offset (-2..+1) for a solid pixel.

static func _pattern(kind: String, x: int, y: int) -> int:
	match kind:
		"brick":
			var row := y / 5
			var off := 5 if row % 2 == 1 else 0
			var bx := (x + off) / 10
			var lx := (x + off) % 10
			var ly := y % 5
			if ly == 4 or lx == 9:
				return -2
			var v := _h(bx, row, 3) % 5
			var o := 0
			if v == 0: o = -1
			elif v == 4: o = 1
			if ly == 0 and lx < 8:
				o += 1
			if lx == 8 or ly == 3:
				o -= 1
			if _h(x, y, 5) % 23 == 0:
				o -= 1
			return o
		"stone":
			# jittered-grid cobbles
			var gx := x / 7
			var gy := y / 6
			var best := 1e9
			var second := 1e9
			var best_id := 0
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var cx := gx + ox
					var cy := gy + oy
					var px := cx * 7 + 1 + _h(cx, cy, 11) % 5
					var py := cy * 6 + 1 + _h(cx, cy, 13) % 4
					var d := float((x - px) * (x - px) + (y - py) * (y - py))
					if d < best:
						second = best
						best = d
						best_id = _h(cx, cy, 17)
					elif d < second:
						second = d
			if sqrt(second) - sqrt(best) < 1.0:
				return -2
			var o := (best_id % 3) - 1
			if _h(x, y, 19) % 17 == 0:
				o += 1
			return clampi(o, -1, 1)
		"dirt":
			var n := _h(x / 3, y / 3, 23) % 100
			var o := 0
			if n < 18: o = -1
			elif n > 90: o = 1
			var p := _h(x, y, 29) % 100
			if p < 4: o = -2
			elif p > 97: o = 1
			# little buried pebbles
			if _h(x / 5, y / 4, 31) % 37 == 0 and (x % 5) in [1, 2] and (y % 4) in [1, 2]:
				o = 1
			return o
		"plank":
			var row := y / 5
			var ly := y % 5
			var seam := (_h(row, 7, 37) % 24) + 8
			var lx := (x + _h(row, 3, 41)) % (seam + 18)
			if ly == 4:
				return -2
			if lx == 0:
				return -2
			var o := 1 if ly == 0 else 0
			if (_h(x, row, 43) % 13 == 0):
				o -= 1
			if lx == 2 and ly == 2:
				return -1
			# wood grain
			if (x + row * 3) % 11 == 0 and ly in [1, 2]:
				o -= 1
			return o
		"marble":
			var bx := x / 16
			var by := y / 8
			var lx := x % 16
			var ly := y % 8
			var off := 8 if by % 2 == 1 else 0
			lx = (x + off) % 16
			if ly == 7 or lx == 15:
				return -2
			var vein := absf(sin((x + _h(bx, by, 47) % 20) * 0.37 + y * 0.61))
			var o := 0
			if vein < 0.08:
				o = 1
			elif ly == 0:
				o = 1
			if (_h(bx, by, 53) % 4) == 0:
				o -= 1
			return o
		"ice":
			# smooth ice with sparse bright fracture streaks and air bubbles
			var o := 0
			var d1 := (x + y * 2 + _h(x / 24, y / 16, 61) % 11) % 23
			if d1 == 0 and _h(x / 6, y / 6, 63) % 3 == 0:
				o = 1
			if _h(x, y, 67) % 97 == 0:
				o = 1
			if (x * 3 - y + 900) % 31 == 0 and _h(x / 8, y / 8, 69) % 4 == 0:
				o = -1
			return o
		"crystal":
			var gx := x / 6
			var gy := y / 6
			var lx := x % 6
			var ly := y % 6
			var flip := _h(gx, gy, 71) % 2 == 0
			var diag := (lx + ly) if flip else (lx - ly + 6)
			var o := 1 if diag < 5 else -1 if diag > 7 else 0
			if lx == 0 or ly == 0:
				o -= 1
			return clampi(o, -2, 1)
		"stripe":
			return 0
	return 0


# ---------------------------------------------------------------- distance field

static func _chamfer(solid: PackedByteArray, w: int, h: int, cap: int) -> PackedInt32Array:
	var big := cap + 1
	var d := PackedInt32Array()
	d.resize(w * h)
	for i in w * h:
		d[i] = big if solid[i] != 0 else 0
	# forward
	for y in h:
		for x in w:
			var i := y * w + x
			if d[i] == 0:
				continue
			var v := d[i]
			if x > 0: v = mini(v, d[i - 1] + 1)
			if y > 0:
				v = mini(v, d[i - w] + 1)
				if x > 0: v = mini(v, d[i - w - 1] + 1)
				if x < w - 1: v = mini(v, d[i - w + 1] + 1)
			d[i] = v
	# backward
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := y * w + x
			if d[i] == 0:
				continue
			var v := d[i]
			if x < w - 1: v = mini(v, d[i + 1] + 1)
			if y < h - 1:
				v = mini(v, d[i + w] + 1)
				if x < w - 1: v = mini(v, d[i + w + 1] + 1)
				if x > 0: v = mini(v, d[i + w - 1] + 1)
			d[i] = v
	return d


# ---------------------------------------------------------------- main painter

## Returns {fg, bg, fake, deco}: Images the size of the room in pixels.
static func render(def: RoomDef, tileset: String) -> Dictionary:
	var st: Dictionary = STYLES.get(tileset, STYLES["town"])
	var W := def.w * T
	var H := def.h * T
	var PAD := 8   # pixels of out-of-bounds solid context around the room
	var w := W + PAD * 2
	var h := H + PAD * 2
	# material map with padding (0 air, 1 main, 2 alt, 3 fake)
	var mat := PackedByteArray()
	mat.resize(w * h)
	var cell_mat := func(cx: int, cy: int) -> int:
		if cx < 0 or cy < 0 or cx >= def.w or cy >= def.h:
			# beyond the room: continue whatever is at the nearest border cell
			var ncx := clampi(cx, 0, def.w - 1)
			var ncy := clampi(cy, 0, def.h - 1)
			var t0 := def.cells[ncy * def.w + ncx]
			if t0 == RoomDef.SOLID: return 1
			if t0 == RoomDef.SOLID_ALT: return 2
			if t0 == RoomDef.FAKE: return 1
			return 0
		var t := def.cells[cy * def.w + cx]
		if t == RoomDef.SOLID: return 1
		if t == RoomDef.SOLID_ALT: return 2
		if t == RoomDef.FAKE: return 3
		return 0
	for py in h:
		var cy := floori(float(py - PAD) / T)
		for px in w:
			var cx := floori(float(px - PAD) / T)
			mat[py * w + px] = cell_mat.call(cx, cy)
	# round convex corners a little (visual only)
	for cy in range(-1, def.h + 1):
		for cx in range(-1, def.w + 1):
			if cell_mat.call(cx, cy) == 0:
				continue
			for corner in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
				var nx: int = corner.x
				var ny: int = corner.y
				if cell_mat.call(cx + nx, cy) != 0 or cell_mat.call(cx, cy + ny) != 0 or cell_mat.call(cx + nx, cy + ny) != 0:
					continue
				var ox := PAD + cx * T + (T - 1 if nx > 0 else 0)
				var oy := PAD + cy * T + (T - 1 if ny > 0 else 0)
				var pts := [Vector2i(0, 0), Vector2i(-nx, 0), Vector2i(0, -ny)]
				if _h(cx, cy, 79 + nx * 3 + ny) % 2 == 0:
					pts.append(Vector2i(-nx * 2, 0))
				for p in pts:
					var xx: int = ox + p.x
					var yy: int = oy + p.y
					if xx >= 0 and yy >= 0 and xx < w and yy < h:
						mat[yy * w + xx] = 0
	var solid := PackedByteArray()
	solid.resize(w * h)
	for i in w * h:
		solid[i] = 1 if mat[i] != 0 else 0
	var dist := _chamfer(solid, w, h, 16)
	# distance to air straight above / below
	var up := PackedInt32Array()
	up.resize(w * h)
	var down := PackedInt32Array()
	down.resize(w * h)
	for x in w:
		var run := 99
		for y in h:
			var i := y * w + x
			if solid[i] == 0:
				run = 0
				up[i] = 0
			else:
				run = mini(run + 1, 99)
				up[i] = run
		run = 99
		for y in range(h - 1, -1, -1):
			var i := y * w + x
			if solid[i] == 0:
				run = 0
				down[i] = 0
			else:
				run = mini(run + 1, 99)
				down[i] = run
	# per-column cap thickness (irregular drips)
	var cap_kind: String = st.cap
	var ramp := []
	var aramp := []
	var cramp := []
	for c in st.ramp: ramp.append(_col(c))
	for c in st.alt_ramp: aramp.append(_col(c))
	for c in st.cap_ramp: cramp.append(_col(c))
	var fg := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var fake := Image.create(W, H, false, Image.FORMAT_RGBA8)
	fg.fill(Color(0, 0, 0, 0))
	fake.fill(Color(0, 0, 0, 0))
	var white := _col(st.alt_ramp[6])
	for y in H:
		for x in W:
			var i := (y + PAD) * w + (x + PAD)
			var m := mat[i]
			if m == 0:
				continue
			var d := dist[i]
			var u := up[i]
			var dn := down[i]
			var r: Array = aramp if m == 2 else ramp
			var pat: String = st.alt_pattern if m == 2 else st.pattern
			var col: Color
			# --- cap (only on the main material's exposed tops)
			var cap_depth := 2 + _h(x / 2, 0, 83) % 3
			if cap_kind == "gold" or cap_kind == "silver":
				cap_depth = 2
			if m != 2 and cap_kind != "none" and u <= cap_depth and u >= 1:
				var k := clampi(u - 1, 0, 4)
				col = cramp[k]
				if cap_kind == "grass" and u == cap_depth and _h(x, 1, 89) % 3 == 0:
					col = cramp[3]
				elif cap_kind == "gold" and u == 2 and x % 6 == 2:
					col = cramp[4]
				elif cap_kind == "silver" and u == 2 and x % 8 == 3:
					col = cramp[3]
				elif cap_kind == "crystal" and _h(x / 2, y, 97) % 4 == 0:
					col = cramp[mini(k + 1, 4)]
				elif cap_kind == "moss" and u == 1 and _h(x, 3, 101) % 4 == 0:
					col = cramp[0]
				_put(fg, fake, m, x, y, col)
				continue
			# grass / moss drips hanging just below the cap
			if m != 2 and (cap_kind == "grass" or cap_kind == "moss") and u > cap_depth and u <= cap_depth + 3:
				var drip := _h(x, 2, 103) % 7
				if drip < 2 and u <= cap_depth + 1 + drip:
					_put(fg, fake, m, x, y, cramp[3])
					continue
			# snow lips sliding over vertical edges
			if m != 2 and cap_kind == "snow" and u <= cap_depth + 2 and d == 1 and dn > 1:
				_put(fg, fake, m, x, y, cramp[2])
				continue
			# --- outline on exposed edges
			if d == 1:
				var oc: Color = r[0]
				if u == 1:
					oc = r[6]   # top edge without cap: bright rim
				elif dn == 1:
					oc = r[0]
				else:
					oc = r[1] if (x + y) % 2 == 0 else r[0]
				_put(fg, fake, m, x, y, oc)
				continue
			# --- body shading
			var s := 4
			if u <= 3:
				s = 5
			if u == 2 and cap_kind == "none":
				s = 6
			if d == 2 and dn > 2 and u > 3:
				s = 3      # bevel just inside side edges
			if dn <= 2:
				s = 3
			# ambient occlusion deeper inside, dithered between bands
			var ao := 0
			var ao_max: int = st.get("ao_max", 2)
			if d >= 7: ao = 1
			if d >= 13: ao = 2
			# wide ordered-dither transition so bands never read as rings
			var bay: int = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5][(y % 4) * 4 + (x % 4)]
			if d >= 4 and d < 7 and bay < (d - 3) * 4:
				ao = 1
			elif d >= 10 and d < 13 and bay < (d - 9) * 4:
				ao = 2
			s -= mini(ao, ao_max)
			if pat == "stripe":
				var stripe := ((x + y) / 4) % 2 == 0
				var base: Color = r[clampi(s, 1, 5)] if stripe else white.darkened(0.08 * ao)
				if d == 2 or dn <= 2:
					base = base.darkened(0.2)
				_put(fg, fake, m, x, y, base)
				continue
			s += _pattern(pat, x, y)
			col = r[clampi(s, 1, 6)]
			_put(fg, fake, m, x, y, col)
	# --- background walls
	var bg := _render_bg(def, st)
	# --- hanging decorations under ceilings
	var deco := _render_hangers(def, st, solid, w, h, PAD)
	return {"fg": fg, "fake": fake, "bg": bg, "deco": deco}


static func _put(fg: Image, fake: Image, m: int, x: int, y: int, c: Color) -> void:
	if m == 3:
		fake.set_pixel(x, y, c)
	else:
		fg.set_pixel(x, y, c)


static func _render_bg(def: RoomDef, st: Dictionary) -> Image:
	var W := def.w * T
	var H := def.h * T
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var br := []
	for c in st.bg_ramp: br.append(_col(c))
	var is_bg := func(cx: int, cy: int) -> bool:
		if cx < 0 or cy < 0 or cx >= def.w or cy >= def.h:
			return false
		var t := def.cells[cy * def.w + cx]
		return t == RoomDef.BGWALL or ((t == RoomDef.SOLID or t == RoomDef.SOLID_ALT) and false)
	var any := false
	for t in def.cells:
		if t == RoomDef.BGWALL:
			any = true
			break
	if not any:
		return img
	var w := W
	var h := H
	var solid := PackedByteArray()
	solid.resize(w * h)
	for y in h:
		for x in w:
			var cx := x / T
			var cy := y / T
			var t := def.cells[cy * def.w + cx]
			# bg walls continue behind solids and decorations
			var on := t == RoomDef.BGWALL
			if not on and t != RoomDef.EMPTY:
				# fill behind solids/entities if a neighbour is a bg wall
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if is_bg.call(cx + d.x, cy + d.y):
						on = true
						break
			elif not on and t == RoomDef.EMPTY:
				var c := def.rows[cy][cx]
				if c != "." and c != " ":
					var n := 0
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						if is_bg.call(cx + d.x, cy + d.y):
							n += 1
					on = n >= 2
			solid[y * w + x] = 1 if on else 0
	var dist := _chamfer(solid, w, h, 8)
	for y in h:
		for x in w:
			var i := y * w + x
			if solid[i] == 0:
				continue
			var d := dist[i]
			var s := 2
			if d == 1:
				s = 0
			elif d == 2:
				s = 1
			var p := _pattern(st.bg_pattern, x, y)
			if p < -1:
				s -= 1
			elif p > 0 and d > 2:
				s += 1
			img.set_pixel(x, y, br[clampi(s, 0, 3)])
	return img


static func _render_hangers(def: RoomDef, st: Dictionary, solid: PackedByteArray, w: int, h: int, PAD: int) -> Image:
	var W := def.w * T
	var H := def.h * T
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var kind: String = st.hang
	var hr := []
	for c in st.hang_ramp: hr.append(_col(c))
	var outline := _col(st.ramp[0])
	var cramp := []
	for c in st.cap_ramp: cramp.append(_col(c))
	var air := func(x: int, y: int) -> bool:
		if x < 0 or y < 0 or x >= W or y >= H:
			return false
		return solid[(y + PAD) * w + (x + PAD)] == 0
	var setp := func(x: int, y: int, c: Color) -> void:
		if x >= 0 and y >= 0 and x < W and y < H and img.get_pixel(x, y).a == 0.0:
			img.set_pixel(x, y, c)
	for y in range(0, H):
		for x in range(0, W):
			# ceiling: solid at (x,y-1), air at (x,y)
			if not air.call(x, y) or air.call(x, y - 1):
				continue
			if y - 1 < 0:
				continue
			var hv := _h(x, y, 107)
			match kind:
				"icicle", "stalactite", "crystal":
					if hv % 9 != 0:
						continue
					var length := 2 + hv % (6 if kind != "crystal" else 4)
					if not (air.call(x - 1, y) and air.call(x + 1, y)):
						length = mini(length, 2)
					for k in length:
						if not air.call(x, y + k):
							break
						var c: Color = hr[1] if k < length - 1 else hr[2]
						setp.call(x, y + k, c)
						if k < length / 2:
							setp.call(x + 1, y + k, hr[0])
					setp.call(x - 1, y, hr[0])
				"roots", "vine":
					if hv % 7 != 0:
						continue
					var length := 2 + hv % 7
					var xx := x
					for k in length:
						if not air.call(xx, y + k):
							break
						setp.call(xx, y + k, hr[1] if k % 3 != 2 else hr[2])
						if (hv >> (k + 3)) % 4 == 0:
							xx += 1 if (hv >> k) % 2 == 0 else -1
					if kind == "vine":
						setp.call(xx, y + length, hr[2])
				"cobweb":
					pass
				"bunting":
					pass
	# grass tufts / snow mounds standing on top edges
	var cap_kind: String = st.cap
	for y in range(1, H):
		for x in range(0, W):
			if not air.call(x, y - 1) or air.call(x, y):
				continue
			if x >= W or y - 1 < 0:
				continue
			# (x, y) is the top pixel of solid ground; place things at y-1 and above
			var hv := _h(x, y, 113)
			match cap_kind:
				"snow":
					if hv % 11 == 0 and air.call(x - 1, y - 1) and air.call(x + 1, y - 1):
						setp.call(x, y - 1, cramp[1])
						setp.call(x - 1, y - 1, cramp[2])
						setp.call(x + 1, y - 1, cramp[2])
				"crystal":
					if hv % 13 == 0:
						var length := 2 + hv % 3
						for k in length:
							if air.call(x, y - 1 - k):
								setp.call(x, y - 1 - k, cramp[1] if k < length - 1 else cramp[0])
						setp.call(x + 1, y - 1, cramp[3])
				"moss":
					if hv % 6 == 0:
						setp.call(x, y - 1, cramp[1])
						if hv % 12 == 0:
							setp.call(x, y - 2, cramp[0])
				"gold":
					pass
	# cobwebs in upper inside corners
	if kind == "cobweb":
		for cy in def.h:
			for cx in def.w:
				var px := cx * T
				var py := cy * T
				if not air.call(px + 1, py + 1):
					continue
				var wall_l: bool = not air.call(px - 1, py + 1)
				var ceil: bool = not air.call(px + 1, py - 1)
				if wall_l and ceil and _h(cx, cy, 127) % 3 == 0:
					for k in 6:
						setp.call(px + k, py, Color(hr[1], 0.6))
						setp.call(px, py + k, Color(hr[1], 0.6))
						if k < 5:
							setp.call(px + k, py + 5 - k, Color(hr[0], 0.45))
						if k < 3:
							setp.call(px + k * 2, py + 2, Color(hr[0], 0.35))
	return img
