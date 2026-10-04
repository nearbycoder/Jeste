class_name Effects
extends Node2D
## Lightweight particle + flourish system (purely visual).

var parts: Array = []      # {p, v, life, max, col, size, grav, drag}
var rings: Array = []      # death / respawn orbs {c, t, dur, col, inward}
var popups: Array = []     # {p, text, life, col}
var time := 0.0


func dust(pos: Vector2, dir: float = 0.0, n: int = 5, col: Color = Color("e8e0d8")) -> void:
	for i in n:
		var v := Vector2(randf_range(-30, 30) + dir * 30.0, randf_range(-25, -5))
		parts.append({"p": pos + Vector2(randf_range(-3, 3), 0), "v": v, "life": 0.35, "max": 0.35, "col": col, "size": 1, "grav": 40.0, "drag": 3.0})


func burst(pos: Vector2, col: Color, n: int = 10, speed: float = 70.0, life: float = 0.45) -> void:
	for i in n:
		var a := TAU * i / n + randf_range(-0.2, 0.2)
		var v := Vector2.RIGHT.rotated(a) * speed * randf_range(0.6, 1.0)
		parts.append({"p": pos, "v": v, "life": life, "max": life, "col": col, "size": 2 if i % 3 == 0 else 1, "grav": 0.0, "drag": 4.0})


func sparkle(pos: Vector2, col: Color, n: int = 6) -> void:
	for i in n:
		var v := Vector2(randf_range(-20, 20), randf_range(-40, -10))
		parts.append({"p": pos + Vector2(randf_range(-4, 4), randf_range(-4, 4)), "v": v, "life": 0.7, "max": 0.7, "col": col, "size": 1, "grav": -10.0, "drag": 1.5})


func debris(rect: Rect2, col: Color, n: int = 16) -> void:
	for i in n:
		var p := rect.position + Vector2(randf() * rect.size.x, randf() * rect.size.y)
		var v := Vector2(randf_range(-60, 60), randf_range(-90, -20))
		parts.append({"p": p, "v": v, "life": 0.8, "max": 0.8, "col": col, "size": 2, "grav": 300.0, "drag": 0.5})


func death(pos: Vector2, col: Color) -> void:
	rings.append({"c": pos, "t": 0.0, "dur": 0.55, "col": col, "inward": false})
	burst(pos, Color.WHITE, 8, 50.0, 0.3)


func respawn(pos: Vector2, col: Color) -> void:
	rings.append({"c": pos, "t": 0.0, "dur": 0.4, "col": col, "inward": true})


func popup(pos: Vector2, text: String, col: Color = Color("ffd27a")) -> void:
	popups.append({"p": pos, "text": text, "life": 1.2, "col": col})


func _process(delta: float) -> void:
	time += delta
	for p in parts:
		p.life -= delta
		p.v.y += p.grav * delta
		p.v *= maxf(0.0, 1.0 - p.drag * delta)
		p.p += p.v * delta
	parts = parts.filter(func(p): return p.life > 0.0)
	for r in rings:
		r.t += delta
	rings = rings.filter(func(r): return r.t < r.dur)
	for p in popups:
		p.life -= delta
		p.p.y -= 12.0 * delta
	popups = popups.filter(func(p): return p.life > 0.0)
	queue_redraw()


func _draw() -> void:
	for p in parts:
		var a: float = clampf(p.life / p.max * 1.5, 0.0, 1.0)
		var c: Color = p.col
		draw_rect(Rect2(roundf(p.p.x), roundf(p.p.y), p.size, p.size), Color(c.r, c.g, c.b, c.a * a))
	for r in rings:
		var t: float = r.t / r.dur
		var k := 1.0 - t if r.inward else t
		var rad := 4.0 + ease(k, 0.4) * 34.0
		var sz := 4.0 * (1.0 - t * 0.7)
		for i in 8:
			var a: float = TAU * i / 8.0 + r.t * 3.0
			var c: Vector2 = r.c + Vector2.RIGHT.rotated(a) * rad
			draw_circle(c, sz, r.col)
			draw_circle(c, maxf(sz - 1.5, 0.5), Color.WHITE.lerp(r.col, 0.4))
	for p in popups:
		var a: float = clampf(p.life * 2.0, 0.0, 1.0)
		PixelText.draw_centered(self, p.p.x, p.p.y, p.text, Color(p.col.r, p.col.g, p.col.b, a), Color(0, 0, 0, a * 0.8))
