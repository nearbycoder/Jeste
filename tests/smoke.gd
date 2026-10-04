extends SceneTree

func _init() -> void:
	var txt := """@chapter 9
name = Test
=== t-01
exits = right:t-02
---
########################################
#......................................#
#......................................#
#......................................#
#......................................#
#......................................#
#......................................#
#......................................#
#......................................#
#......................................#
#......................................#
#......................................#
#......................................#
#......................................#
#......................................#
#......................................#
#......................................#
#......................................#
#......................................#
#P......................................
########################################
########################################
########################################
"""
	var ch := LevelDB.parse_text(txt)
	var r: RoomDef = ch.room("t-01")
	print("room ", r.w, "x", r.h, " spawns ", r.spawns, " exits ", r.exits)
	var wd := World.new()
	wd.load_room(r, 0, 1)
	print("start ", wd.x, ",", wd.y, " ground ", wd.on_ground)
	# idle 10 frames
	for i in 10: wd.step(0)
	print("after idle ", wd.x, ",", wd.y)
	# jump and hold
	var miny := wd.y
	var t := 0
	for i in 60:
		wd.step(World.IN_JUMP)
		miny = mini(miny, wd.y)
		t += 1
		if wd.on_ground and i > 2: break
	print("full jump height px: ", wd.y - miny, " frames ", t)
	for i in 5: wd.step(0)
	# short hop
	miny = wd.y
	wd.step(World.IN_JUMP)
	for i in 60:
		wd.step(0)
		miny = mini(miny, wd.y)
		if wd.on_ground: break
	print("short hop px: ", wd.y - miny)
	# run right timing
	var x0 := wd.x
	for i in 60: wd.step(World.IN_RIGHT)
	print("run 1s px: ", wd.x - x0, " vx ", wd.vx)
	for i in 30: wd.step(0)
	# dash right
	x0 = wd.x
	wd.step(World.IN_DASH | World.IN_RIGHT)
	for i in 14: wd.step(World.IN_RIGHT)
	print("dash 15f px: ", wd.x - x0, " state ", wd.state, " dashes ", wd.dashes)
	# go to exit
	for i in 400:
		wd.step(World.IN_RIGHT)
		if wd.exited: break
	print("exited ", wd.exited, " ", wd.exit_side, " -> ", wd.exit_target)
	# perf
	wd.load_room(r, 0, 1)
	var t0 := Time.get_ticks_usec()
	var n := 0
	for k in 200:
		wd.reset_room()
		for i in 100:
			wd.step(World.IN_RIGHT | (World.IN_JUMP if (i % 20) < 10 else 0))
			n += 1
	var dt := Time.get_ticks_usec() - t0
	print("perf: %d steps in %d us = %.2f us/step" % [n, dt, float(dt)/n])
	quit()
