extends RefCounted
## "Paper doll" pixel character renderer.
## A character is a hand-drawn head + torso plus procedurally drawn limbs,
## posed per frame from a table of joint positions, then given an automatic
## silhouette outline. This yields many smooth, consistent animation frames
## (run cycles, climbs, squashes...) from a handful of drawn parts.
##
## Frame space: FRAME x FRAME pixels, the feet rest on row FRAME-1, centred
## on column FRAME/2. Characters face right.

const FRAME := 24
const GROUND := 23
const CX := 12


class Character:
	var pal: Dictionary = {}        # char -> hex
	var heads: Dictionary = {}      # variant -> rows (facing right, no outline)
	var torso: Array = []           # rows, centred on the hip
	var torso_w := 5
	var leg_len := Vector2i(3, 3)   # thigh, shin
	var arm_len := Vector2i(2, 2)
	var front_leg := "l"
	var back_leg := "L"
	var front_arm := "t"
	var back_arm := "T"
	var boot := "b"
	var boot_back := "B"
	var hand := "s"
	var toe := "y"
	var outline := "k"
	var head_dx := -3               # head left edge relative to hip x
	var arm_thick := 1
	var skin_forearm := true
	var extra: Callable             # optional per-frame overlay (img, pose, origin)


static func _px(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col)


static func _line(img: Image, a: Vector2i, b: Vector2i, col: Color, thick: int) -> void:
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var p := a
	while true:
		_px(img, p.x, p.y, col)
		if thick > 1:
			# thicken along the axis perpendicular to the dominant direction,
			# the extra row is the shadowed side of the limb (volume)
			if dx > -dy:
				_px(img, p.x, p.y - 1, col.lightened(0.12))
			else:
				_px(img, p.x + 1, p.y, col.darkened(0.18))
		if p == b:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy


static func _blit(img: Image, rows: Array, ox: int, oy: int, pal: Dictionary) -> void:
	for y in rows.size():
		var line: String = rows[y]
		for x in line.length():
			var c := line[x]
			if c == ".":
				continue
			if pal.has(c):
				_px(img, ox + x, oy + y, Color.html("#" + pal[c]))


## Rim light from the upper front, soft shade on the back, then a selective
## outline tinted by the colour it borders (pure dark only along the bottom).
static func _outline(img: Image, col: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var src := img.duplicate() as Image
	var solid := func(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < w and y < h and src.get_pixel(x, y).a > 0.5
	# lighting pass
	for y in h:
		for x in w:
			if not solid.call(x, y):
				continue
			var c := src.get_pixel(x, y)
			if c.is_equal_approx(Color.html("#ff00ff")) or c.is_equal_approx(Color.html("#c000c0")) or c.is_equal_approx(Color.html("#ff80ff")):
				continue   # cap key colours are recoloured at runtime
			if not solid.call(x, y - 1):
				c = c.lightened(0.14)
			elif not solid.call(x + 1, y) and not solid.call(x + 1, y - 1):
				c = c.lightened(0.08)
			if not solid.call(x - 1, y) and solid.call(x, y - 1):
				c = c.darkened(0.12)
			img.set_pixel(x, y, c)
	# outline pass
	for y in h:
		for x in w:
			if solid.call(x, y):
				continue
			var near := Color(0, 0, 0, 0)
			var below: bool = solid.call(x, y - 1) and not solid.call(x, y + 1)
			for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
				if solid.call(x + d.x, y + d.y):
					near = src.get_pixel(x + d.x, y + d.y)
					break
			if near.a == 0.0:
				continue
			var oc := col
			if not below and not near.is_equal_approx(Color.html("#ff00ff")) and not near.is_equal_approx(Color.html("#c000c0")) and not near.is_equal_approx(Color.html("#ff80ff")):
				oc = near.darkened(0.72).lerp(col, 0.45)
			img.set_pixel(x, y, oc)


## pose keys (all optional):
##   dy: hip vertical offset (positive = lower), hx: hip x offset
##   lean: torso/head x offset, head: variant, hy: extra head y offset
##   lf/lb: [knee, foot] front/back leg, relative to the hip
##   af/ab: [elbow, hand] front/back arm, relative to the shoulder
static func render(ch: Character, pose: Dictionary) -> Dictionary:
	var img := Image.create(FRAME, FRAME, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := func(k: String) -> Color: return Color.html("#" + ch.pal[k])
	var hip := Vector2i(CX + int(pose.get("hx", 0)), GROUND - ch.leg_len.x - ch.leg_len.y + int(pose.get("dy", 0)))
	var lean: int = pose.get("lean", 0)
	var torso_h: int = ch.torso.size()
	var torso_top := hip.y - torso_h
	var shoulder_f := Vector2i(hip.x + 1 + lean, torso_top + 1)
	var shoulder_b := Vector2i(hip.x - 1 + lean, torso_top + 1)
	var lf: Array = pose.get("lf", [Vector2i(1, 3), Vector2i(1, 6)])
	var lb: Array = pose.get("lb", [Vector2i(-1, 3), Vector2i(-1, 6)])
	var af: Array = pose.get("af", [Vector2i(0, 2), Vector2i(1, 4)])
	var ab: Array = pose.get("ab", [Vector2i(0, 2), Vector2i(-1, 4)])
	# --- back limbs
	_arm(img, ch, shoulder_b, ab, col.call(ch.back_arm), col.call(ch.hand))
	_leg(img, ch, hip + Vector2i(-1, 0), lb, col.call(ch.back_leg), col.call(ch.boot_back), col.call(ch.toe))
	# --- torso (lean shifts the upper rows progressively)
	for r in torso_h:
		var shift := int(round(lean * float(torso_h - r) / torso_h))
		var line: String = ch.torso[r]
		_blit(img, [line], hip.x - ch.torso_w / 2 + shift - (line.length() - ch.torso_w) / 2, torso_top + r, ch.pal)
	# --- front leg
	_leg(img, ch, hip + Vector2i(0, 0), lf, col.call(ch.front_leg), col.call(ch.boot), col.call(ch.toe))
	# --- head
	var head_rows: Array = ch.heads.get(pose.get("head", "normal"), ch.heads["normal"])
	var head_pos := Vector2i(hip.x + ch.head_dx + lean, torso_top - head_rows.size() + int(pose.get("hy", 0)))
	_blit(img, head_rows, head_pos.x, head_pos.y, ch.pal)
	# --- front arm
	_arm(img, ch, shoulder_f, af, col.call(ch.front_arm), col.call(ch.hand))
	if ch.extra.is_valid():
		ch.extra.call(img, pose, hip, head_pos)
	_outline(img, col.call(ch.outline))
	return {"image": img, "head": head_pos, "hip": hip}


static func _leg(img: Image, ch: Character, hip: Vector2i, joints: Array, c: Color, bootc: Color, toec: Color) -> void:
	var knee: Vector2i = hip + joints[0]
	var foot: Vector2i = hip + joints[1]
	_line(img, hip, knee, c, 2)
	_line(img, knee, foot, c, 2)
	# boot: heel at the foot point, pointing forward, with a curled jester toe
	var toe_dir := 1 if (joints.size() < 3 or joints[2] >= 0) else -1
	_px(img, foot.x, foot.y, bootc)
	_px(img, foot.x + toe_dir, foot.y, bootc)
	_px(img, foot.x + toe_dir * 2, foot.y, bootc)
	_px(img, foot.x, foot.y - 1, bootc)
	_px(img, foot.x + toe_dir, foot.y - 1, bootc)
	_px(img, foot.x + toe_dir * 3, foot.y - 1, toec)


static func _arm(img: Image, ch: Character, shoulder: Vector2i, joints: Array, c: Color, handc: Color) -> void:
	var elbow: Vector2i = shoulder + joints[0]
	var hnd: Vector2i = shoulder + joints[1]
	_line(img, shoulder, elbow, c, ch.arm_thick)
	_line(img, elbow, hnd, handc if ch.skin_forearm else c, 1)
	_px(img, hnd.x, hnd.y, handc)


static func V(x: int, y: int) -> Vector2i:
	return Vector2i(x, y)


# ======================================================================
# Pose library (shared by every humanoid)
# ======================================================================

static func poses() -> Dictionary:
	var P := {}
	# --- idle (breathing, one blink)
	var idle_dy := [0, 0, 0, 1, 1, 1]
	for i in 6:
		P["idle%d" % i] = {"dy": idle_dy[i], "head": "blink" if i == 4 else "normal",
			"af": [V(0, 2), V(0, 4 - idle_dy[i])], "ab": [V(0, 2), V(-1, 4 - idle_dy[i])]}
	# --- run (8 frames)
	var run := [
		# lf knee/foot, lb knee/foot, dy, af elbow/hand, ab elbow/hand
		[V(2, 2), V(3, 5), V(-1, 3), V(-3, 5), 0, V(-1, 2), V(-2, 3), V(1, 1), V(3, 1)],
		[V(1, 3), V(1, 6), V(-2, 2), V(-3, 4), 1, V(-1, 2), V(-1, 4), V(1, 2), V(2, 3)],
		[V(0, 3), V(-1, 6), V(1, 2), V(1, 4), 0, V(0, 2), V(0, 4), V(0, 2), V(0, 4)],
		[V(-1, 3), V(-3, 5), V(2, 1), V(3, 3), -1, V(1, 1), V(3, 1), V(-1, 2), V(-2, 3)],
	]
	for i in 8:
		var r: Array = run[i % 4]
		if i < 4:
			P["run%d" % i] = {"dy": r[4], "lean": 1, "lf": [r[0], r[1]], "lb": [r[2], r[3]], "af": [r[5], r[6]], "ab": [r[7], r[8]]}
		else:
			P["run%d" % i] = {"dy": r[4], "lean": 1, "lf": [r[2], r[3]], "lb": [r[0], r[1]], "af": [r[7], r[8]], "ab": [r[5], r[6]]}
	# --- skid / turn
	P["skid"] = {"dy": 1, "lean": -1, "lf": [V(2, 3), V(3, 5)], "lb": [V(-1, 3), V(-1, 5)], "af": [V(1, -1), V(2, -2)], "ab": [V(-1, 1), V(-3, 1)]}
	# --- air
	P["rise0"] = {"dy": -1, "lf": [V(2, 2), V(1, 4)], "lb": [V(-1, 3), V(-1, 6)], "af": [V(1, -2), V(2, -4)], "ab": [V(-1, -1), V(-2, -3)]}
	P["rise1"] = {"dy": -1, "lf": [V(2, 2), V(2, 4)], "lb": [V(0, 3), V(-1, 5)], "af": [V(1, -2), V(1, -4)], "ab": [V(-1, -1), V(-2, -2)]}
	P["peak"] = {"dy": 0, "lf": [V(2, 2), V(2, 5)], "lb": [V(-1, 2), V(-2, 4)], "af": [V(2, 0), V(3, -1)], "ab": [V(-2, 0), V(-3, -1)]}
	P["fall0"] = {"dy": -1, "lf": [V(1, 3), V(2, 6)], "lb": [V(-1, 3), V(-2, 5)], "af": [V(2, -1), V(3, -3)], "ab": [V(-2, -1), V(-3, -3)]}
	P["fall1"] = {"dy": -1, "lf": [V(1, 3), V(1, 6)], "lb": [V(-1, 3), V(-3, 6)], "af": [V(2, -2), V(2, -4)], "ab": [V(-2, -2), V(-2, -4)]}
	P["land"] = {"dy": 3, "lean": 1, "lf": [V(3, 1), V(2, 3)], "lb": [V(-2, 1), V(-2, 3)], "af": [V(1, 1), V(3, 2)], "ab": [V(-1, 1), V(-3, 2)], "head": "blink"}
	P["duck"] = {"dy": 3, "lean": 1, "lf": [V(3, 1), V(2, 3)], "lb": [V(-2, 1), V(-2, 3)], "af": [V(1, 1), V(2, 2)], "ab": [V(-1, 1), V(-2, 2)]}
	# --- dash poses
	P["dash"] = {"dy": 0, "lean": 2, "lf": [V(-1, 2), V(-3, 4)], "lb": [V(-2, 2), V(-5, 3)], "af": [V(-2, 1), V(-4, 1)], "ab": [V(-2, 0), V(-4, -1)]}
	P["dash_up"] = {"dy": -1, "lf": [V(0, 3), V(0, 6)], "lb": [V(-1, 3), V(-2, 6)], "af": [V(1, -2), V(1, -5)], "ab": [V(0, -2), V(0, -5)], "head": "up"}
	P["dash_down"] = {"dy": 2, "lf": [V(2, 1), V(1, 3)], "lb": [V(-1, 1), V(-2, 3)], "af": [V(2, 0), V(3, 1)], "ab": [V(-2, 0), V(-3, 1)]}
	# --- climbing (facing the wall on the right)
	var climb := [
		[V(1, -2), V(2, -4), V(2, 0), V(3, 1), V(2, 2), V(3, 4), V(0, 3), V(-1, 6)],
		[V(1, -1), V(3, -3), V(2, 0), V(3, 0), V(1, 3), V(2, 5), V(1, 2), V(2, 4)],
		[V(2, 0), V(3, 1), V(1, -2), V(2, -4), V(0, 3), V(-1, 6), V(2, 2), V(3, 4)],
		[V(2, 0), V(3, 0), V(1, -1), V(3, -3), V(1, 2), V(2, 4), V(1, 3), V(2, 5)],
	]
	for i in 4:
		var c: Array = climb[i]
		P["climb%d" % i] = {"dy": [0, -1, 0, -1][i], "hx": 1, "af": [c[0], c[1]], "ab": [c[2], c[3]], "lf": [c[4], c[5]], "lb": [c[6], c[7]]}
	P["slide"] = {"dy": 0, "hx": 1, "af": [V(1, -2), V(3, -3)], "ab": [V(1, 0), V(3, 1)], "lf": [V(1, 3), V(1, 6)], "lb": [V(-1, 3), V(-2, 5)], "head": "blink"}
	# --- misc
	P["look"] = {"head": "up", "af": [V(0, 2), V(0, 4)], "ab": [V(0, 2), V(-1, 4)]}
	P["sit"] = {"dy": 4, "lf": [V(2, 0), V(4, 2)], "lb": [V(1, 1), V(3, 2)], "af": [V(1, 2), V(2, 3)], "ab": [V(-1, 2), V(-2, 3)]}
	P["talk0"] = {"af": [V(1, 1), V(2, 2)], "ab": [V(0, 2), V(-1, 4)]}
	P["talk1"] = {"dy": 0, "hy": -1, "af": [V(1, 0), V(3, 0)], "ab": [V(0, 2), V(-1, 4)]}
	return P


const FRAME_ORDER := [
	"idle0", "idle1", "idle2", "idle3", "idle4", "idle5",
	"run0", "run1", "run2", "run3", "run4", "run5", "run6", "run7",
	"skid", "rise0", "rise1", "peak", "fall0", "fall1", "land", "duck",
	"dash", "dash_up", "dash_down", "climb0", "climb1", "climb2", "climb3", "slide",
	"look", "sit", "talk0", "talk1",
]


# ======================================================================
# Characters
# ======================================================================

static func mira() -> Character:
	var c := Character.new()
	c.pal = {
		"k": "1d1428", "s": "f7d4b0", "S": "dea284", "e": "1d1428", "m": "ec7a86",
		"h": "6a3444", "H": "45202f",
		"c": "ff00ff", "C": "c000c0", "a": "ff80ff",      # cap key colours (recoloured at runtime)
		"y": "f2c14e", "Y": "b8862a",
		"w": "f6f1e8", "W": "c9c1d4",
		"t": "36aaa5", "T": "21706f", "u": "5cd2c8", "p": "8a4aaa", "P": "5c2f78",
		"n": "6b3f2a",
		"l": "36aaa5", "L": "6a3a8a",                       # jester tights: one teal, one purple
		"b": "8a5432", "B": "5a3420",
	}
	var cap := ["..Cccca.", ".Cccccca", "YyyyyyyY"]
	c.heads = {
		"normal": cap + ["Hhhhssss", "Hhhsssse", "Hhssssms", ".hsssss.", "..SSSS.."],
		"blink": cap + ["Hhhhssss", "HhhssssS", "Hhssssms", ".hsssss.", "..SSSS.."],
		"up": cap + ["Hhhhsses", "Hhhsssss", "Hhssssms", ".hsssss.", "..SSSS.."],
		"happy": cap + ["Hhhhssss", "HhhsssSs", "Hhssssms", ".hssssS.", "..SSSS.."],
	}
	c.torso = [
		"WwwwwW",
		"tppttT",
		"tTppTT",
		"nnnynn",
	]
	c.torso_w = 6
	c.head_dx = -4
	c.leg_len = Vector2i(2, 3)
	c.front_arm = "u"
	return c


static func grin_palette() -> Dictionary:
	return {"s": "e8e4f0", "S": "b8b0c8", "h": "1a1026", "H": "0e0818", "c": "3a1f5a", "C": "24133a",
		"a": "5a3a7a", "y": "d8344f", "Y": "8f1f35", "w": "2a1a3a", "W": "1a1026", "t": "5a2a7a",
		"T": "3a1a52", "p": "d8344f", "P": "8f1f35", "l": "5a2a7a", "L": "2a1a3a", "b": "2a1a3a",
		"B": "1a1026", "m": "ff3a5a", "e": "ff3a5a", "n": "1a1026"}


static func bellamy() -> Character:
	var c := Character.new()
	c.pal = {
		"k": "1d1428", "s": "f2c9a4", "S": "d29c7c", "e": "1d1428", "f": "f4ead2", "F": "c9b98f",
		"n": "8a5a3a", "N": "5a3a24", "q": "3b3b58", "Q": "25253a", "y": "e8b84a",
		"l": "3b3b58", "L": "25253a", "t": "3b3b58", "T": "25253a", "b": "5a3a24", "B": "3a2416",
		"g": "9aa3b8",
	}
	c.heads = {
		"normal": [
			"..NNNN...",
			".NnnnnN..",
			"NNNNNNNNN",
			".ssssss..",
			".sgggsgg.",
			".ffsssff.",
			"fffffffff",
			".fffFfff.",
			"..fffff..",
		],
		"blink": [
			"..NNNN...",
			".NnnnnN..",
			"NNNNNNNNN",
			".ssssss..",
			".sgSgsSg.",
			".ffsssff.",
			"fffffffff",
			".fffFfff.",
			"..fffff..",
		],
	}
	c.heads["up"] = c.heads.normal
	c.torso = [
		"qqffqqq",
		"qqqfqqq",
		"qqqqqqy",
		"qqqqqqq",
		"QqqqqqQ",
		"QQQQQQQ",
	]
	c.torso_w = 7
	c.head_dx = -4
	c.leg_len = Vector2i(2, 3)
	c.hand = "s"
	c.toe = "b"
	return c


static func tobi() -> Character:
	var c := Character.new()
	c.pal = {
		"k": "1d1428", "s": "f2c9a4", "S": "d29c7c", "e": "1d1428", "h": "1f1a2e", "H": "141020",
		"g": "4fb84f", "G": "2f7a3a", "y": "f2c94e", "Y": "c49a2a", "m": "e0707e",
		"l": "3b4a6a", "L": "2a3550", "t": "f2c94e", "T": "c49a2a", "b": "5a3a24", "B": "3a2416",
	}
	c.heads = {
		"normal": [".GgggG.", "gggggGG", "hhhssss", "hhsssse", "hssssms", ".sssss.", "..SSS.."],
		"blink": [".GgggG.", "gggggGG", "hhhssss", "hhssssS", "hssssms", ".sssss.", "..SSS.."],
	}
	c.heads["up"] = c.heads.normal
	c.torso = [
		"ggggGg",
		"yyGyyY",
		"yyyyyY",
		"YyyyyY",
	]
	c.toe = "b"
	return c


static func oddo() -> Character:
	var c := Character.new()
	c.pal = {
		"k": "1d1428", "w": "f4f4fa", "W": "c8c8dc", "e": "6fd6ff", "q": "2a2a40", "Q": "1a1a2a",
		"r": "d8344f", "R": "8f1f35", "y": "e8b84a", "F": "c9b48a",
		"l": "8f1f35", "L": "5a1420", "t": "d8344f", "T": "8f1f35", "s": "f4f4fa", "b": "1a1a2a", "B": "1a1a2a",
	}
	c.heads = {
		"normal": [
			"..qqqq..",
			"..qqqq..",
			"..qqqq..",
			"..rrrr..",
			"qqqqqqqq",
			".wwwwww.",
			".wwwewe.",
			"FFwwwwFF",
			".wwwwww.",
			"..WWWW..",
		],
		"blink": [
			"..qqqq..",
			"..qqqq..",
			"..qqqq..",
			"..rrrr..",
			"qqqqqqqq",
			".wwwwww.",
			".wwwWwW.",
			"FFwwwwFF",
			".wwwwww.",
			"..WWWW..",
		],
	}
	c.heads["up"] = c.heads.normal
	c.torso = [
		"rrwwrr",
		"rrrwyr",
		"rrrwrR",
		"RRRRRR",
	]
	c.head_dx = -4
	c.toe = "b"
	return c
