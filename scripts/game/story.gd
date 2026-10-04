class_name Story
extends RefCounted
## Loads cutscene scripts from res://data/story/*.txt
##
##   @script_id
##   speaker:expression: Text to say. Use \n for a manual line break.
##   !command arg arg      (wait, shake, flash, sfx, music, npc_hide, npc_show,
##                          face, title, fade_out, fade_in, frame)
##   ; comment

const FILES := [
	"res://data/story/prologue.txt",
	"res://data/story/ch1.txt",
	"res://data/story/ch2.txt",
	"res://data/story/ch3.txt",
	"res://data/story/ch4.txt",
	"res://data/story/ch5.txt",
	"res://data/story/ch6.txt",
	"res://data/story/ch7.txt",
	"res://data/story/epilogue.txt",
]

const NAMES := {
	"mira": "Mira", "grin": "The Grin", "bellamy": "Bellamy", "tobi": "Tobi",
	"oddo": "Ringmaster Oddo", "magpie": "Magpie", "sign": "", "narrator": "",
	"nana": "Nana Odile",
}

static var _scripts: Dictionary = {}


static func get_script_lines(id: String) -> Array:
	if _scripts.is_empty():
		load_all()
	return _scripts.get(id, [])


static func has(id: String) -> bool:
	if _scripts.is_empty():
		load_all()
	return _scripts.has(id)


static func all_ids() -> Array:
	if _scripts.is_empty():
		load_all()
	return _scripts.keys()


static func load_all() -> void:
	_scripts = {}
	for path in FILES:
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		var cur := ""
		for raw in f.get_as_text().split("\n"):
			var line := raw.strip_edges()
			if line == "" or line.begins_with(";"):
				continue
			if line.begins_with("@"):
				cur = line.substr(1).strip_edges()
				_scripts[cur] = []
				continue
			if cur == "":
				continue
			if line.begins_with("!"):
				var parts := line.substr(1).split(" ", false)
				_scripts[cur].append({"type": "cmd", "cmd": parts[0], "args": parts.slice(1)})
				continue
			var c1 := line.find(":")
			var c2 := line.find(":", c1 + 1)
			if c1 < 0 or c2 < 0:
				push_error("Story: bad line in %s: %s" % [cur, line])
				continue
			var who := line.substr(0, c1).strip_edges()
			var expr := line.substr(c1 + 1, c2 - c1 - 1).strip_edges()
			var text := line.substr(c2 + 1).strip_edges().replace("\\n", "\n")
			_scripts[cur].append({"type": "say", "who": who, "expr": expr, "text": text})
