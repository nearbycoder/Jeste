class_name PostFX
extends CanvasLayer
## Full-screen post-processing over the game world (below the UI):
## soft bloom, per-chapter colour grading (split toning, contrast,
## saturation) and a brief chromatic shimmer on impacts. Options > Graphics
## picks the shader: none at Low (no screen copy at all), a lighter bloom at
## Medium, the original at High, and a wide soft bloom with a filmic curve at
## Ultra.

const GRADES := {
	# shadows tint, highlights tint, saturation, contrast, bloom
	0: [Color(0.10, 0.02, 0.16), Color(0.16, 0.08, 0.0), 1.08, 1.06, 0.32],
	1: [Color(0.02, 0.04, 0.16), Color(0.14, 0.10, 0.0), 1.05, 1.08, 0.40],
	2: [Color(0.12, 0.0, 0.16), Color(0.12, 0.04, 0.10), 1.12, 1.06, 0.42],
	3: [Color(0.10, 0.0, 0.08), Color(0.16, 0.08, 0.0), 1.10, 1.08, 0.40],
	4: [Color(0.0, 0.04, 0.10), Color(0.08, 0.06, 0.0), 1.08, 1.04, 0.22],
	5: [Color(0.0, 0.08, 0.10), Color(0.04, 0.08, 0.10), 1.02, 1.08, 0.36],
	6: [Color(0.0, 0.06, 0.12), Color(0.0, 0.10, 0.08), 1.05, 1.10, 0.45],
	7: [Color(0.06, 0.02, 0.14), Color(0.18, 0.10, 0.02), 1.10, 1.05, 0.30],
	8: [Color(0.04, 0.02, 0.06), Color(0.12, 0.08, 0.0), 1.06, 1.04, 0.22],
}

var rect: ColorRect
var mat: ShaderMaterial
var shimmer := 0.0
var grade: Array = GRADES[1]
var fidelity := -1
static var _shaders := {}


func _init() -> void:
	layer = 3


func _ready() -> void:
	rect = ColorRect.new()
	rect.size = Vector2(320, 180)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	rect.material = mat
	add_child(rect)
	apply_fidelity()
	Game.fidelity_changed.connect(apply_fidelity)


## The shader for a Graphics step (null at Low: the pass is off).
static func shader_for(f: int) -> Shader:
	if f <= Game.FIDELITY_LOW:
		return null
	if not _shaders.has(f):
		var sh := Shader.new()
		sh.code = {Game.FIDELITY_MEDIUM: CODE_MEDIUM, Game.FIDELITY_HIGH: CODE_HIGH}.get(f, CODE_ULTRA)
		_shaders[f] = sh
	return _shaders[f]


func apply_fidelity() -> void:
	fidelity = Game.fidelity()
	var sh := shader_for(fidelity)
	rect.visible = sh != null
	if sh and mat.shader != sh:
		mat.shader = sh
		_apply_grade()


func setup(chapter: int) -> void:
	grade = GRADES.get(chapter, GRADES[1])
	if mat == null:
		await ready
	_apply_grade()


func _apply_grade() -> void:
	var g := grade
	var st: Color = g[0]
	var hi: Color = g[1]
	mat.set_shader_parameter("shadow_tint", Vector3(st.r, st.g, st.b))
	mat.set_shader_parameter("high_tint", Vector3(hi.r, hi.g, hi.b))
	mat.set_shader_parameter("saturation", g[2])
	mat.set_shader_parameter("contrast", g[3])
	mat.set_shader_parameter("bloom", g[4])
	mat.set_shader_parameter("shimmer", shimmer)


func pulse(amount: float = 1.0) -> void:
	shimmer = maxf(shimmer, amount * Game.flash_scale())


func _process(delta: float) -> void:
	if shimmer > 0.0:
		shimmer = maxf(shimmer - delta * 5.0, 0.0)
		if mat:
			mat.set_shader_parameter("shimmer", shimmer)


## High: the original pass. Two rings of bright-pass taps for the bloom.
const CODE_HIGH := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec3 shadow_tint = vec3(0.0);
uniform vec3 high_tint = vec3(0.0);
uniform float saturation = 1.0;
uniform float contrast = 1.0;
uniform float bloom = 0.3;
uniform float threshold = 0.62;
uniform float shimmer = 0.0;

vec3 bright(vec2 uv) {
	vec3 c = texture(screen_tex, uv).rgb;
	float l = max(c.r, max(c.g, c.b));
	return c * smoothstep(threshold, 1.0, l);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 c;
	if (shimmer > 0.001) {
		float o = shimmer * 1.5;
		c = vec3(texture(screen_tex, uv + vec2(px.x * o, 0.0)).r, texture(screen_tex, uv).g, texture(screen_tex, uv - vec2(px.x * o, 0.0)).b);
	} else {
		c = texture(screen_tex, uv).rgb;
	}
	// bloom: two rings of taps (cheap at 320x180)
	vec3 b = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398;
		vec2 d = vec2(cos(a), sin(a));
		b += bright(uv + d * px * 2.0) * 0.6;
		b += bright(uv + d * px * 5.0) * 0.4;
	}
	c += b / 8.0 * bloom;
	// grade
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	c += shadow_tint * (1.0 - l) * 0.35 + high_tint * l * 0.35;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
"""

## Medium: the same grade and shimmer, with one ring of bloom taps.
const CODE_MEDIUM := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec3 shadow_tint = vec3(0.0);
uniform vec3 high_tint = vec3(0.0);
uniform float saturation = 1.0;
uniform float contrast = 1.0;
uniform float bloom = 0.3;
uniform float threshold = 0.62;
uniform float shimmer = 0.0;

vec3 bright(vec2 uv) {
	vec3 c = texture(screen_tex, uv).rgb;
	float l = max(c.r, max(c.g, c.b));
	return c * smoothstep(threshold, 1.0, l);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 c;
	if (shimmer > 0.001) {
		float o = shimmer * 1.5;
		c = vec3(texture(screen_tex, uv + vec2(px.x * o, 0.0)).r, texture(screen_tex, uv).g, texture(screen_tex, uv - vec2(px.x * o, 0.0)).b);
	} else {
		c = texture(screen_tex, uv).rgb;
	}
	vec3 b = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398;
		b += bright(uv + vec2(cos(a), sin(a)) * px * 3.0);
	}
	c += b / 8.0 * bloom * 0.8;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	c += shadow_tint * (1.0 - l) * 0.35 + high_tint * l * 0.35;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
"""

## Ultra: High's pass plus a wide, soft bloom read from the screen's blurred
## mip levels (lights, gems, lanterns and snow caps glow into the air around
## them) and a gentle filmic contrast curve.
const CODE_ULTRA := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D blur_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec3 shadow_tint = vec3(0.0);
uniform vec3 high_tint = vec3(0.0);
uniform float saturation = 1.0;
uniform float contrast = 1.0;
uniform float bloom = 0.3;
uniform float threshold = 0.62;
uniform float shimmer = 0.0;
uniform float wide = 1.6;

vec3 bright(vec2 uv) {
	vec3 c = texture(screen_tex, uv).rgb;
	float l = max(c.r, max(c.g, c.b));
	return c * smoothstep(threshold, 1.0, l);
}

vec3 glow(vec2 uv, float lod) {
	vec3 c = max(textureLod(blur_tex, uv, lod).rgb - 0.3, 0.0);
	return c * c * 2.6;   // past a soft knee and squared: bright areas glow, dark walls don't lift
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 c;
	if (shimmer > 0.001) {
		float o = shimmer * 1.5;
		c = vec3(texture(screen_tex, uv + vec2(px.x * o, 0.0)).r, texture(screen_tex, uv).g, texture(screen_tex, uv - vec2(px.x * o, 0.0)).b);
	} else {
		c = texture(screen_tex, uv).rgb;
	}
	vec3 b = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398;
		vec2 d = vec2(cos(a), sin(a));
		b += bright(uv + d * px * 2.0) * 0.6;
		b += bright(uv + d * px * 5.0) * 0.4;
	}
	c += b / 8.0 * bloom;
	// wide bloom from the blurred mips, screen-blended so it never clips
	vec3 w = (glow(uv, 1.0) * 0.6 + glow(uv, 2.0) * 0.8 + glow(uv, 3.0) * 0.9 + glow(uv, 4.0) * 0.7) * bloom * wide;
	c = 1.0 - (1.0 - clamp(c, 0.0, 1.0)) * (1.0 - clamp(w, 0.0, 1.0));
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	c += shadow_tint * (1.0 - l) * 0.35 + high_tint * l * 0.35;
	c = clamp(c, 0.0, 1.0);
	c = mix(c, c * c * (3.0 - 2.0 * c), 0.22);
	COLOR = vec4(c, 1.0);
}
"""
