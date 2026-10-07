class_name PlayerView
extends Node2D
## Draws Mira (or the Grin): a 24x24 rigged sprite driven by a small animation
## state machine, damped-spring squash & stretch, physically simulated jester
## cap tails with jingle bells (their colour shows the dashes left), gradient
## dash afterimages, a ribbon trail and footstep / skid / slide particles.
## Purely visual: it only *reads* the World.

const CAP_DASH := Color("e03a5a")       # one dash ready: jester red
const CAP_EMPTY := Color("4f6fd0")      # no dash: slate blue
const CAP_TWO := Color("ff7ad8")        # two dashes: pink
const CAP_GRIN := Color("4a2a72")
const OUTLINE := Color("1d1428")
const FS := 24                          # frame size
const TAIL_N := 6
const TAIL_SEG := 2.0

var world: World
var effects: Effects
var is_grin := false
var silent := false            # Route Ghost: animates like Mira but makes no sound
var visible_player := true
var anim_time := 0.0
var run_dist := 0.0
var climb_dist := 0.0
var last_frame := 0
var frame_name := "idle0"
var cap_col := CAP_DASH
var cap_target := CAP_DASH
var flash := 0.0
var flash_col := Color.WHITE
var override_frame := ""       # cutscenes
var override_facing := 0
var dialogue_facing := 0       # face whoever is being talked to
var talking := false           # Mira is the current speaker
var settle_y := 0.0            # visual drop to the ground after the chapter ends
var settle_v := 0.0

# squash & stretch as a damped spring around (1,1)
var squash := Vector2.ONE
var squash_vel := Vector2.ZERO

# animation memory
var land_timer := 0.0
var air_time := 0.0
var prev_ground := true
var prev_vy := 0.0
var prev_state := 0
var prev_dashes := 1
var step_phase := 0
var slide_timer := 0.0
var slide_snd := false

# tails: arrays of positions / previous positions
var tails: Array = []
var tails_prev: Array = []
var bell_glint := 0.0

# trails
var trail: Array = []          # afterimages {pos, frame, flip, col, life, max}
var ribbon: Array = []         # {p, life, col}
var trail_timer := 0

# Ghost (chaser) mode: draws from recorded snapshots instead of the world
var ghost_pos := Vector2(-1000, -1000)
var ghost_frame := 0
var ghost_flip := false

var _mat: ShaderMaterial
var _trail_node: TrailDrawer


class TrailDrawer:
	extends Node2D
	var pv: PlayerView
	func _draw() -> void:
		var tex := pv._tex()
		# ribbon trail (cap colour, tapering)
		for i in range(1, pv.ribbon.size()):
			var a: Dictionary = pv.ribbon[i - 1]
			var b: Dictionary = pv.ribbon[i]
			var k: float = clampf(b.life / 0.35, 0.0, 1.0)
			var c: Color = b.col
			draw_line(a.p, b.p, Color(c.r, c.g, c.b, 0.55 * k), maxf(1.0, 3.0 * k))
		for t in pv.trail:
			var k: float = t.life / t.max
			var c: Color = (t.col as Color).lightened(0.25).lerp(Color("6a4ab0"), 1.0 - k)
			var sx := -1.0 if t.flip else 1.0
			draw_set_transform(Vector2(roundf(t.pos.x), roundf(t.pos.y)), 0, Vector2(sx, 1))
			draw_texture_rect_region(tex, Rect2(-12, -24, 24, 24), Rect2(t.frame * 24, 0, 24, 24), Color(c.r, c.g, c.b, 0.5 * k * k))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _ready() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform vec4 cap_color : source_color = vec4(0.88, 0.23, 0.35, 1.0);
uniform vec4 cap_shade : source_color = vec4(0.6, 0.1, 0.2, 1.0);
uniform vec4 cap_light : source_color = vec4(1.0, 0.6, 0.65, 1.0);
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash = 0.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a > 0.5) {
		if (distance(c.rgb, vec3(1.0, 0.0, 1.0)) < 0.12) { c.rgb = cap_color.rgb; }
		else if (distance(c.rgb, vec3(0.753, 0.0, 0.753)) < 0.12) { c.rgb = cap_shade.rgb; }
		else if (distance(c.rgb, vec3(1.0, 0.5, 1.0)) < 0.12) { c.rgb = cap_light.rgb; }
	}
	c.rgb = mix(c.rgb, flash_color.rgb, flash);
	COLOR = c * COLOR;
}
"""
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	material = _mat
	var tm := ShaderMaterial.new()
	tm.shader = sh
	tm.set_shader_parameter("flash", 1.0)
	_trail_node = TrailDrawer.new()
	_trail_node.pv = self
	_trail_node.material = tm
	_trail_node.show_behind_parent = true
	add_child(_trail_node)
	reset_tails()


func _tex() -> Texture2D:
	return Art.grin() if is_grin else Art.player()


func reset_tails() -> void:
	tails = []
	tails_prev = []
	if world == null and not is_grin:
		return
	var anchors := _tail_anchors()
	for t in 2:
		var arr: Array = []
		for i in TAIL_N:
			arr.append(anchors[t] + Vector2(-_facing() * i * TAIL_SEG, i * 0.5))
		tails.append(arr)
		tails_prev.append(arr.duplicate())
	trail.clear()
	ribbon.clear()


func _feet() -> Vector2:
	if is_grin:
		return ghost_pos + Vector2(4, 11)
	return Vector2(world.x + 4, world.y + 11 + settle_y) + world.view_offset()


func _facing() -> int:
	if override_facing != 0:
		return override_facing
	if dialogue_facing != 0:
		return dialogue_facing
	if is_grin:
		return -1 if ghost_flip else 1
	return world.facing


func current_frame() -> int:
	return last_frame


## Converts a pixel inside the current 24x24 frame to world space.
func _frame_to_world(px: Vector2) -> Vector2:
	var f := _feet()
	var lx := px.x - FS / 2.0
	if _facing() < 0:
		lx = -lx
	return f + Vector2(lx * squash.x, (px.y - FS) * squash.y)


func _tail_anchors() -> Array:
	var heads: Array = Art.index().get("mira_heads", [])
	var h := Vector2(8, 6)
	if last_frame < heads.size():
		h = Vector2(heads[last_frame][0], heads[last_frame][1])
	# back point of the cap, and the front tip
	return [_frame_to_world(h + Vector2(1.5, 0.5)), _frame_to_world(h + Vector2(6.5, 0.0))]


# ---------------------------------------------------------------- animation state machine

func _pick_frame(delta: float) -> String:
	if override_frame != "":
		return override_frame
	if world.end_reached and settle_y > 0.0 and settle_v != 0.0:
		return "fall0"
	if talking and (world.on_ground or world.end_reached):
		return "talk%d" % (int(anim_time * 7.0) % 2)
	var st := world.state
	if st == World.ST_DASH or st == World.ST_DREAM:
		if world.dash_dir_x == 0 and world.dash_dir_y < 0:
			return "dash_up"
		if world.dash_dir_x == 0 and world.dash_dir_y > 0:
			return "dash_down"
		return "dash"
	if st == World.ST_BOOST:
		return "duck"
	if st == World.ST_CLIMB:
		if absf(world.vy) > 1.0:
			return "climb%d" % (int(climb_dist / 3.0) % 4)
		return "climb0"
	if world.on_ground:
		if land_timer > 0.0:
			return "land"
		if world.ducking:
			return "duck"
		if world.move_x != 0 and signf(world.vx) == -world.move_x and absf(world.vx) > 30.0:
			return "skid"
		if absf(world.vx) > 8.0:
			return "run%d" % (int(run_dist / 3.2) % 8)
		var seq := [0, 0, 1, 2, 3, 3, 3, 2, 1, 0, 4, 0]
		return "idle%d" % seq[int(anim_time * 5.0) % seq.size()]
	if world.wall_slide_dir != 0 or (world.vy > 0.0 and world.move_x == world.facing and world._collide(world.x + world.facing, world.y)):
		return "slide"
	if world.vy < -60.0:
		return "rise%d" % (int(anim_time * 12.0) % 2)
	if world.vy < 50.0:
		return "peak"
	return "fall%d" % (int(anim_time * 10.0) % 2)


func on_event(ev: String) -> void:
	match ev:
		"jump", "walljump", "climbhop":
			_kick(Vector2(-0.35, 0.45))
		"super", "hyper", "wallbounce":
			_kick(Vector2(0.4, -0.3))
		"spring", "bumper", "bounce":
			_kick(Vector2(-0.45, 0.6))
		"land":
			var hard := clampf(prev_vy / 240.0, 0.3, 1.0)
			_kick(Vector2(0.55, -0.5) * hard)
			land_timer = 0.07 + 0.05 * hard
		"dash", "launch":
			_kick(Vector2(0.45, -0.35) if world.dash_dir_y == 0 else Vector2(-0.35, 0.45))
			trail_timer = 0
			flash = 0.6
			flash_col = Color.WHITE
		"refill", "gem":
			flash = 1.0
			flash_col = Color.WHITE
			bell_glint = 1.0
		"dream_out":
			flash = 0.8
			flash_col = Color("fff0b0")


func _kick(v: Vector2) -> void:
	squash_vel += v * 14.0


func _process(delta: float) -> void:
	anim_time += delta
	if world == null:
		return
	if not is_grin:
		_update_player(delta)
	else:
		cap_target = CAP_GRIN
		last_frame = ghost_frame
	cap_col = cap_col.lerp(cap_target, 1.0 - pow(0.0005, delta))
	# damped spring squash (stiff, slightly bouncy)
	var acc := (Vector2.ONE - squash) * 420.0 - squash_vel * 24.0
	squash_vel += acc * delta
	squash += squash_vel * delta
	squash = squash.clamp(Vector2(0.55, 0.55), Vector2(1.6, 1.6))
	flash = maxf(flash - delta * 5.0, 0.0)
	bell_glint = maxf(bell_glint - delta * 2.0, 0.0)
	for t in trail:
		t.life -= delta
	trail = trail.filter(func(t): return t.life > 0.0)
	for r in ribbon:
		r.life -= delta
	ribbon = ribbon.filter(func(r): return r.life > 0.0)
	_update_tails(delta)
	queue_redraw()
	_trail_node.queue_redraw()


func _update_player(delta: float) -> void:
	var grounded := world.on_ground and world.state != World.ST_CLIMB
	if grounded:
		run_dist += absf(world.vx) * delta
	if world.state == World.ST_CLIMB:
		var before := int(climb_dist / 6.0)
		climb_dist += absf(world.vy) * delta
		if int(climb_dist / 6.0) != before and visible_player:
			_sfx("climb", randf_range(0.9, 1.15), -11.0)
	land_timer = maxf(land_timer - delta, 0.0)
	if not grounded:
		air_time += delta
	else:
		air_time = 0.0
	frame_name = _pick_frame(delta)
	last_frame = Art.frame_index(frame_name)
	# cap colour from dashes (flash white when a dash is restored)
	var target := CAP_DASH
	if world.dashes == 0 and world.max_dashes > 0:
		target = CAP_EMPTY
	elif world.dashes >= 2:
		target = CAP_TWO
	if world.dashes > prev_dashes and world.state != World.ST_DASH:
		flash = maxf(flash, 0.7)
		bell_glint = 1.0
		if effects and visible_player:
			effects.ring(_feet() + Vector2(0, -8), target.lightened(0.3), 10.0, 0.25)
	cap_target = target
	if not visible_player:
		prev_dashes = world.dashes
		return
	# dash afterimages + ribbon
	var dashing := world.state == World.ST_DASH or world.state == World.ST_DREAM
	if dashing:
		trail_timer -= 1
		if trail_timer <= 0:
			trail_timer = 3
			trail.append({"pos": _feet(), "frame": last_frame, "flip": _facing() < 0, "col": cap_col, "life": 0.4, "max": 0.4})
		if effects and int(anim_time * 60.0) % 2 == 0:
			var back := -Vector2(world.vx, world.vy).normalized()
			effects.streak(_feet() + Vector2(randf_range(-4, 4), randf_range(-12, -2)), back * randf_range(40, 90), Color(1, 1, 1, 0.7))
	if dashing or Vector2(world.vx, world.vy).length() > 200.0:
		var tip: Vector2 = tails[0][TAIL_N - 1] if not tails.is_empty() else _feet()
		ribbon.append({"p": tip, "life": 0.35, "col": cap_col})
	# footstep dust on run contact frames
	if effects and grounded and absf(world.vx) > 30.0:
		var phase := int(run_dist / 3.2) % 8
		if (phase == 0 or phase == 4) and phase != step_phase:
			effects.puff(_feet() + Vector2(-_facing() * 2, 0), Vector2(-signf(world.vx) * 18.0, -6.0), Color("e8e0d8"), 1)
			_sfx("step%d" % (randi() % 4), randf_range(0.92, 1.08), -9.0)
		step_phase = phase
	# skid dust
	if effects and frame_name == "skid" and int(anim_time * 60.0) % 3 == 0:
		effects.puff(_feet() + Vector2(_facing() * 3, 0), Vector2(_facing() * 25.0, -10.0), Color("f0e8e0"), 1)
	# wall slide sparks / dust
	if frame_name == "slide" and world.vy > 10.0:
		slide_timer -= delta
		if effects and slide_timer <= 0.0:
			slide_timer = 0.06
			effects.puff(_feet() + Vector2(_facing() * 5, -6), Vector2(0, -12), Color("d8d0c8"), 1)
			slide_snd = not slide_snd
			if slide_snd:
				_sfx("slide", randf_range(0.9, 1.1), -13.0)
	# tired: flash red while climbing out of stamina
	if world.state == World.ST_CLIMB and world.stamina < World.CLIMB_TIRED:
		flash = 0.45 if int(anim_time * 12.0) % 2 == 0 else 0.0
		flash_col = Color("ff3a4a")
		if effects and int(anim_time * 60.0) % 20 == 0:
			effects.sweat(_feet() + Vector2(-_facing() * 3, -18))
	prev_ground = grounded
	prev_vy = world.vy
	prev_dashes = world.dashes


# ---------------------------------------------------------------- cap tails (verlet)

func _update_tails(delta: float) -> void:
	if tails.is_empty():
		reset_tails()
		if tails.is_empty():
			return
	var f := _facing()
	var anchors := _tail_anchors()
	var vel := Vector2.ZERO if is_grin else Vector2(world.vx, world.vy)
	var dashing := (not is_grin) and world.state == World.ST_DASH
	var wind := Vector2.ZERO if is_grin else Vector2(world.wind_x, world.wind_y) * 0.004
	var gravity := Vector2(0, 0.10)
	for t in 2:
		var arr: Array = tails[t]
		var prev: Array = tails_prev[t]
		arr[0] = anchors[t]
		prev[0] = anchors[t]
		# rest shape: the cap points arc backwards and droop
		var rest := Vector2(-f * (0.9 if t == 0 else 0.55), -0.15 if t == 0 else 0.1)
		for i in range(1, TAIL_N):
			var p: Vector2 = arr[i]
			var v: Vector2 = (p - (prev[i] as Vector2)) * 0.82
			prev[i] = p
			var bias := rest * (1.0 - float(i) / TAIL_N) * 0.35
			if dashing:
				bias = -Vector2(world.dash_dir_x, world.dash_dir_y).normalized() * 0.5
			var flutter := Vector2(0, sin(anim_time * 9.0 + i * 0.9 + t) * 0.05) * minf(vel.length() / 90.0, 1.5)
			arr[i] = p + v + gravity + bias + wind + flutter
		# distance constraints
		for it in 3:
			for i in range(1, TAIL_N):
				var a: Vector2 = arr[i - 1]
				var b: Vector2 = arr[i]
				var d := b - a
				var len := d.length()
				var seg := TAIL_SEG * (1.0 if i > 1 else 0.8)
				if len > 0.0001:
					arr[i] = a + d / len * seg
	if not is_grin and randf() < 0.004:
		bell_glint = maxf(bell_glint, 0.6)


func _draw_tails(back: bool) -> void:
	if tails.is_empty():
		return
	var shade := cap_col.darkened(0.35)
	for t in 2:
		if (t == 0) != back:
			continue
		var arr: Array = tails[t]
		# outline pass
		for i in range(1, TAIL_N):
			var r := _tail_r(i)
			draw_circle((arr[i] as Vector2).round(), r + 1.0, OUTLINE)
		for i in range(1, TAIL_N - 1):
			var a: Vector2 = (arr[i] as Vector2).round()
			var b: Vector2 = (arr[i + 1] as Vector2).round()
			draw_line(a, b, OUTLINE, 2.0 * _tail_r(i + 1) + 2.0)
		# fill
		for i in range(1, TAIL_N - 1):
			var a: Vector2 = (arr[i] as Vector2).round()
			var b: Vector2 = (arr[i + 1] as Vector2).round()
			draw_line(a, b, shade if t == 0 else cap_col, 2.0 * _tail_r(i + 1))
		for i in range(1, TAIL_N - 1):
			draw_circle((arr[i] as Vector2).round(), _tail_r(i), shade if t == 0 else cap_col)
		# jingle bell
		var tip: Vector2 = (arr[TAIL_N - 1] as Vector2).round()
		var bell := Color("f2c14e") if not is_grin else Color("d8344f")
		draw_circle(tip, 1.6, bell)
		draw_rect(Rect2(tip.x - 1, tip.y - 1, 1, 1), bell.lightened(0.6))
		if bell_glint > 0.05:
			var g := bell_glint
			draw_line(tip + Vector2(-3 * g, 0), tip + Vector2(3 * g, 0), Color(1, 1, 0.8, g))
			draw_line(tip + Vector2(0, -3 * g), tip + Vector2(0, 3 * g), Color(1, 1, 0.8, g))


## Soft ground shadow that shrinks and fades with height.
func _draw_contact_shadow(feet: Vector2) -> void:
	if is_grin or world == null:
		return
	var gap := 0
	while gap < 48 and not world._collide(world.x, world.y + gap + 1) and not world._jumpthru_below(world.x, world.y + gap):
		gap += 1
	if gap >= 48:
		return
	var k := 1.0 - gap / 48.0
	var gy := roundf(feet.y + gap - settle_y)
	var hw := roundf(3.0 + 2.0 * k)
	draw_rect(Rect2(roundf(feet.x) - hw, gy - 1, hw * 2.0, 1), Color(0, 0, 0, 0.32 * k))
	draw_rect(Rect2(roundf(feet.x) - hw + 1, gy - 2, hw * 2.0 - 2, 1), Color(0, 0, 0, 0.14 * k))


func _tail_r(i: int) -> float:
	return lerpf(1.6, 0.7, float(i) / (TAIL_N - 1))


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if world == null and not is_grin:
		return
	if not visible_player:
		return
	_mat.set_shader_parameter("cap_color", cap_col)
	_mat.set_shader_parameter("cap_shade", cap_col.darkened(0.3))
	_mat.set_shader_parameter("cap_light", cap_col.lightened(0.35))
	_mat.set_shader_parameter("flash", flash)
	_mat.set_shader_parameter("flash_color", flash_col)
	var feet := _feet()
	_draw_contact_shadow(feet)
	_draw_tails(true)
	var mod := Color(1, 1, 1, 0.9) if is_grin else Color.WHITE
	var sx := -squash.x if _facing() < 0 else squash.x
	draw_set_transform(Vector2(roundf(feet.x), roundf(feet.y)), 0, Vector2(sx, squash.y))
	draw_texture_rect_region(_tex(), Rect2(-12, -24, 24, 24), Rect2(last_frame * FS, 0, FS, FS), mod)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	_draw_tails(false)


func _sfx(name: String, pitch: float = 1.0, vol: float = 0.0) -> void:
	if not silent:
		Sfx.play(name, pitch, vol)
