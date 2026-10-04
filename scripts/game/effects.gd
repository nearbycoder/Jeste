class_name Effects
extends Node2D
## Visual-only particle system: dust puffs, streaks, sparkles, shockwave
## rings, debris, death / respawn orbs and floating text.

var parts: Array = []      # {kind, p, v, life, max, col, size, grav, drag}
var rings: Array = []      # shockwaves {c, t, dur, col, r}
var orbs: Array = []       # death / respawn orbs {c, t, dur, col, inward}
var popups: Array = []     # {p, text, life, col}
var time := 0.0


func _add(kind: String, p: Vector2, v: Vector2, life: float, col: Color, size: float, grav: float = 0.0, drag: float = 2.0) -> void:
	if parts.size() > 600:
		return
	parts.append({"kind": kind, "p": p, "v": v, "life": life, "max": life, "col": col, "size": size, "grav": grav, "drag": drag})


## Soft round dust puff that grows and fades.
func puff(pos: Vector2, vel: Vector2, col: Color = Color("e8e0d8"), n: int = 1) -> void:
	for i in n:
		_add("puff", pos + Vector2(randf_range(-1.5, 1.5), randf_range(-1, 0)), vel + Vector2(randf_range(-8, 8), randf_range(-6, 2)), randf_range(0.3, 0.45), col, randf_range(1.0, 1.8), -12.0, 3.5)


func dust(pos: Vector2, dir: float = 0.0, n: int = 5, col: Color = Color("e8e0d8")) -> void:
	for i in n:
		var side := -1.0 if i % 2 == 0 else 1.0
		var v := Vector2(side * randf_range(15, 45) + dir * 25.0, randf_range(-14, -4))
		_add("puff", pos + Vector2(side * randf_range(0, 3), 0), v, randf_range(0.3, 0.5), col, randf_range(1.2, 2.2), -10.0, 4.0)


## Landing: a flat dust ring sliding outward along the ground.
func land(pos: Vector2, strength: float) -> void:
	var n := int(4 + strength * 6)
	for i in n:
		var side := -1.0 if i % 2 == 0 else 1.0
		_add("puff", pos + Vector2(side * 2, 0), Vector2(side * randf_range(25, 60) * strength, randf_range(-8, -2)), randf_range(0.3, 0.5), Color("efe8e0"), randf_range(1.2, 2.4), -6.0, 5.0)


func streak(pos: Vector2, vel: Vector2, col: Color = Color.WHITE) -> void:
	_add("streak", pos, vel, 0.18, col, 1.0, 0.0, 6.0)


func burst(pos: Vector2, col: Color, n: int = 10, speed: float = 70.0, life: float = 0.45) -> void:
	for i in n:
		var a := TAU * i / n + randf_range(-0.2, 0.2)
		var v := Vector2.RIGHT.rotated(a) * speed * randf_range(0.6, 1.0)
		_add("spark", pos, v, life, col, 2.0 if i % 3 == 0 else 1.0, 0.0, 4.0)


func sparkle(pos: Vector2, col: Color, n: int = 6) -> void:
	for i in n:
		var v := Vector2(randf_range(-22, 22), randf_range(-42, -10))
		_add("star", pos + Vector2(randf_range(-4, 4), randf_range(-4, 4)), v, randf_range(0.5, 0.9), col, randf_range(1.0, 2.0), -12.0, 1.8)


func sweat(pos: Vector2) -> void:
	_add("drop", pos, Vector2(randf_range(-20, 20), -30), 0.5, Color("8fd0ff"), 1.0, 220.0, 0.5)


func debris(rect: Rect2, col: Color, n: int = 16) -> void:
	for i in n:
		var p := rect.position + Vector2(randf() * rect.size.x, randf() * rect.size.y)
		var v := Vector2(randf_range(-60, 60), randf_range(-100, -20))
		var c := col.darkened(randf_range(0.0, 0.35))
		_add("chunk", p, v, randf_range(0.6, 1.0), c, float(randi_range(1, 3)), 320.0, 0.4)


func embers(pos: Vector2, n: int = 1) -> void:
	for i in n:
		_add("star", pos + Vector2(randf_range(-4, 4), 0), Vector2(randf_range(-8, 8), randf_range(-30, -15)), randf_range(0.8, 1.4), Color("ffb03a"), 1.0, -5.0, 0.6)


func ring(pos: Vector2, col: Color, radius: float = 16.0, dur: float = 0.3) -> void:
	rings.append({"c": pos, "t": 0.0, "dur": dur, "col": col, "r": radius})


func death(pos: Vector2, col: Color) -> void:
	orbs.append({"c": pos, "t": 0.0, "dur": 0.6, "col": col, "inward": false})
	burst(pos, Color.WHITE, 10, 60.0, 0.35)
	ring(pos, Color.WHITE, 26.0, 0.35)


func respawn(pos: Vector2, col: Color) -> void:
	orbs.append({"c": pos, "t": 0.0, "dur": 0.4, "col": col, "inward": true})


func popup(pos: Vector2, text: String, col: Color = Color("ffd27a")) -> void:
	popups.append({"p": pos, "text": text, "life": 1.3, "col": col})


func clear_all() -> void:
	parts.clear()
	rings.clear()
	orbs.clear()
	popups.clear()


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
	for o in orbs:
		o.t += delta
	orbs = orbs.filter(func(o): return o.t < o.dur)
	for p in popups:
		p.life -= delta
		p.p.y -= 14.0 * delta * clampf(p.life, 0.0, 1.0)
	popups = popups.filter(func(p): return p.life > 0.0)
	queue_redraw()


func _draw() -> void:
	for p in parts:
		var k: float = clampf(p.life / p.max, 0.0, 1.0)
		var c: Color = p.col
		var pos := (p.p as Vector2).round()
		match p.kind:
			"puff":
				var r: float = p.size * (1.0 + (1.0 - k) * 1.2)
				draw_circle(pos, r, Color(c.r, c.g, c.b, c.a * k * 0.85))
				if r > 1.6:
					draw_circle(pos + Vector2(-0.5, -0.5), r * 0.5, Color(1, 1, 1, 0.35 * k))
			"streak":
				var tail: Vector2 = pos - (p.v as Vector2) * 0.05
				draw_line(pos, tail, Color(c.r, c.g, c.b, c.a * k), 1.0)
			"spark":
				var sz: float = p.size
				draw_rect(Rect2(pos.x, pos.y, sz, sz), Color(c.r, c.g, c.b, c.a * minf(1.0, k * 1.5)))
			"star":
				var a := c.a * minf(1.0, k * 1.6)
				var s: float = p.size if fmod(time * 12.0 + pos.x, 2.0) < 1.6 else p.size * 0.5
				draw_rect(Rect2(pos.x, pos.y, 1, 1), Color(1, 1, 1, a))
				if s >= 1.5:
					draw_rect(Rect2(pos.x - 1, pos.y, 3, 1), Color(c.r, c.g, c.b, a * 0.8))
					draw_rect(Rect2(pos.x, pos.y - 1, 1, 3), Color(c.r, c.g, c.b, a * 0.8))
			"drop":
				draw_rect(Rect2(pos.x, pos.y, 1, 2), Color(c.r, c.g, c.b, k))
			"chunk":
				var sz: float = p.size
				draw_rect(Rect2(pos.x, pos.y, sz, sz), Color("1d1428"))
				draw_rect(Rect2(pos.x, pos.y, maxf(sz - 1.0, 1.0), maxf(sz - 1.0, 1.0)), c)
	for r in rings:
		var t: float = r.t / r.dur
		var rad: float = 2.0 + ease(t, 0.35) * r.r
		var c: Color = r.col
		draw_arc(r.c, rad, 0, TAU, 24, Color(c.r, c.g, c.b, (1.0 - t) * 0.9), maxf(1.0, 2.5 * (1.0 - t)))
	for o in orbs:
		var t: float = o.t / o.dur
		var k := 1.0 - t if o.inward else t
		var rad := 3.0 + ease(k, 0.4) * 32.0
		var sz := 4.0 * (1.0 - t * 0.6)
		for i in 8:
			var a: float = TAU * i / 8.0 + o.t * (4.0 if o.inward else 2.0)
			var c: Vector2 = o.c + Vector2.RIGHT.rotated(a) * rad
			draw_circle(c, sz + 1.0, Color("1d1428"))
			draw_circle(c, sz, o.col)
			draw_circle(c + Vector2(-1, -1), maxf(sz - 2.0, 0.6), Color.WHITE.lerp(o.col, 0.3))
	for p in popups:
		var a: float = clampf(p.life * 2.0, 0.0, 1.0)
		var bounce := maxf(0.0, (p.life - 1.0)) * 12.0
		PixelText.draw_centered(self, p.p.x, p.p.y - bounce, p.text, Color(p.col.r, p.col.g, p.col.b, a), Color(0, 0, 0, a * 0.8))
