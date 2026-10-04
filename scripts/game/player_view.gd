class_name PlayerView
extends Node2D
## Draws Mira: animated sprite, squash & stretch, the jester-cap tails (whose
## colour shows how many dashes are left), dash afterimages and tired flashes.

const CAP_DASH := Color("e03a5a")       # one dash ready: jester red
const CAP_EMPTY := Color("4f6fd0")      # no dash: slate blue
const CAP_TWO := Color("ff7ad8")        # two dashes: pink
const CAP_GRIN := Color("3a1f5a")

var world: World
var is_grin := false
var visible_player := true
var anim_time := 0.0
var run_dist := 0.0
var scale_fx := Vector2.ONE
var last_frame := 0
var tails: Array = []          # two arrays of Vector2 nodes
var trail: Array = []          # afterimages {pos, frame, flip, col, life}
var trail_timer := 0
var flash := 0.0
var cap_col := CAP_DASH
var prev_state := 0
var prev_ground := false
var prev_vy := 0.0
var override_frame := ""       # cutscenes
var override_facing := 0

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
		var tex := Art.grin() if pv.is_grin else Art.player()
		for t in pv.trail:
			var a: float = t.life / 0.3
			var sx := -1.0 if t.flip else 1.0
			draw_set_transform(Vector2(roundf(t.pos.x), roundf(t.pos.y)), 0, Vector2(sx, 1))
			draw_texture_rect_region(tex, Rect2(-8, -16, 16, 16), Rect2(t.frame * 16, 0, 16, 16), Color(t.col.r, t.col.g, t.col.b, a * 0.6))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _ready() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform vec4 cap_color : source_color = vec4(0.88, 0.23, 0.35, 1.0);
uniform vec4 cap_shade : source_color = vec4(0.6, 0.1, 0.2, 1.0);
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash = 0.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a > 0.5 && distance(c.rgb, vec3(1.0, 0.0, 1.0)) < 0.15) { c.rgb = cap_color.rgb; }
	else if (c.a > 0.5 && distance(c.rgb, vec3(0.753, 0.0, 0.753)) < 0.15) { c.rgb = cap_shade.rgb; }
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


func reset_tails() -> void:
	tails = []
	var base := _head_anchor()
	for t in 2:
		var arr: Array = []
		for i in 4:
			arr.append(base + Vector2(0, i * 2))
		tails.append(arr)


func _feet() -> Vector2:
	if is_grin:
		return ghost_pos + Vector2(4, 11)
	return Vector2(world.x + 4, world.y + 11)


func _facing() -> int:
	if override_facing != 0:
		return override_facing
	if is_grin:
		return -1 if ghost_flip else 1
	return world.facing


func _head_anchor() -> Vector2:
	if world == null and not is_grin:
		return Vector2.ZERO
	return _feet() + Vector2(0, -11)


func current_frame() -> int:
	return last_frame


func _pick_frame(delta: float) -> String:
	if override_frame != "":
		return override_frame
	var st := world.state
	if st == World.ST_DASH or st == World.ST_DREAM:
		return "dash"
	if st == World.ST_BOOST:
		return "rise"
	if st == World.ST_CLIMB:
		if absf(world.vy) > 1.0:
			return "climb0" if int(anim_time * 8.0) % 2 == 0 else "climb1"
		return "climb0"
	if world.on_ground:
		if world.ducking:
			return "duck"
		if absf(world.vx) > 8.0:
			var i := int(run_dist / 5.0) % 6
			return "run%d" % i
		return "idle0" if int(anim_time * 1.6) % 2 == 0 else "idle1"
	if world.wall_slide_dir != 0 or (world.vy > 0.0 and world.move_x == world.facing and world._collide(world.x + world.facing, world.y)):
		return "slide"
	if world.vy < -40.0:
		return "rise"
	if world.vy < 40.0:
		return "peak"
	return "fall"


func on_event(ev: String) -> void:
	match ev:
		"jump", "walljump", "super", "hyper", "wallbounce", "spring", "climbhop":
			scale_fx = Vector2(0.7, 1.35)
		"land":
			scale_fx = Vector2(1.35, 0.7)
		"dash", "launch":
			scale_fx = Vector2(1.3, 0.75) if world.dash_dir_y == 0 else Vector2(0.75, 1.3)
			trail_timer = 0
		"refill", "gem":
			flash = 0.8


func _process(delta: float) -> void:
	anim_time += delta
	if world == null:
		return
	if not is_grin:
		if world.on_ground:
			run_dist += absf(world.vx) * delta
		var fname := _pick_frame(delta)
		last_frame = Art.frame_index(fname)
		# cap colour from dashes
		var target := CAP_DASH
		if world.dashes == 0 and world.max_dashes > 0:
			target = CAP_EMPTY
		elif world.dashes >= 2:
			target = CAP_TWO
		cap_col = target
		# afterimages while dashing
		if world.state == World.ST_DASH or world.state == World.ST_DREAM:
			trail_timer -= 1
			if trail_timer <= 0:
				trail_timer = 4
				trail.append({"pos": _feet(), "frame": last_frame, "flip": _facing() < 0, "col": cap_col, "life": 0.3})
		# tired flash
		if world.state == World.ST_CLIMB and world.stamina < World.CLIMB_TIRED:
			flash = 0.5 if int(anim_time * 10.0) % 2 == 0 else 0.0
	else:
		cap_col = CAP_GRIN
		last_frame = ghost_frame
	for t in trail:
		t.life -= delta
	trail = trail.filter(func(t): return t.life > 0.0)
	scale_fx = scale_fx.lerp(Vector2.ONE, 1.0 - pow(0.0001, delta))
	flash = maxf(flash - delta * 4.0, 0.0)
	_update_tails(delta)
	queue_redraw()


func _update_tails(delta: float) -> void:
	if tails.is_empty():
		reset_tails()
	var f := _facing()
	var head := _head_anchor()
	var anchors := [head + Vector2(-3 * f, -2), head + Vector2(3 * f, -1)]
	var vel := Vector2.ZERO if is_grin else Vector2(world.vx, world.vy)
	for t in 2:
		var arr: Array = tails[t]
		arr[0] = anchors[t]
		var drift := Vector2(-f * (1.4 if t == 0 else 0.6), 1.0)
		if not is_grin and world.state == World.ST_DASH:
			drift = Vector2(-world.dash_dir_x * 1.6, -world.dash_dir_y * 1.6)
		elif vel.length() > 40.0:
			drift += -vel.normalized() * 0.8
		for i in range(1, arr.size()):
			var target: Vector2 = arr[i - 1] + drift * 1.8
			arr[i] = (arr[i] as Vector2).lerp(target, 1.0 - pow(0.00005, delta))
			var d: Vector2 = arr[i] - arr[i - 1]
			if d.length() > 2.2:
				arr[i] = arr[i - 1] + d.normalized() * 2.2


func _draw() -> void:
	if world == null and not is_grin:
		return
	if not visible_player:
		return
	var tex := Art.grin() if is_grin else Art.player()
	_trail_node.queue_redraw()
	var shade := cap_col.darkened(0.3)
	_mat.set_shader_parameter("cap_color", cap_col)
	_mat.set_shader_parameter("cap_shade", shade)
	# tails behind body
	for t in 2:
		var arr: Array = tails[t]
		for i in range(1, arr.size()):
			var p: Vector2 = arr[i]
			var sz := 2 if i < arr.size() - 1 else 2
			var col := cap_col if i < arr.size() - 1 else Color("f2c14e")
			if is_grin and i == arr.size() - 1:
				col = Color("d8344f")
			draw_rect(Rect2(roundf(p.x) - sz / 2, roundf(p.y) - sz / 2, sz, sz), Color("1c1424"))
			draw_rect(Rect2(roundf(p.x) - sz / 2, roundf(p.y) - sz / 2, sz - 1 if sz > 1 else 1, sz - 1 if sz > 1 else 1), col)
	var mod := Color(1, 1, 1, 0.85) if is_grin else Color.WHITE
	_draw_sprite(tex, _feet(), last_frame, _facing() < 0, scale_fx, mod, flash, Color.WHITE)


func _draw_sprite(tex: Texture2D, feet: Vector2, frame: int, flip: bool, sc: Vector2, mod: Color, fl: float, flcol: Color) -> void:
	_mat.set_shader_parameter("flash", fl)
	_mat.set_shader_parameter("flash_color", flcol)
	var sx := -sc.x if flip else sc.x
	draw_set_transform(Vector2(roundf(feet.x), roundf(feet.y)), 0, Vector2(sx, sc.y))
	draw_texture_rect_region(tex, Rect2(-8, -16, 16, 16), Rect2(frame * 16, 0, 16, 16), mod)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
