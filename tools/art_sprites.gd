extends RefCounted
## Hand-drawn ASCII pixel art. Every sprite is a list of strings; each
## character is a palette key ('.' = transparent).

const PAL := {
	"k": "1c1424", # outline
	"s": "f6d2ad", # skin
	"d": "d9a083", # skin shadow
	"e": "1c1424", # eyes
	"h": "4a2a3a", # Mira's hair
	"c": "ff00ff", # cap (key colour, recoloured at runtime by dash state)
	"C": "c000c0", # cap shade (key colour)
	"y": "f2c14e", # gold
	"Y": "b8862a", # gold shade
	"w": "f4efe6", # white
	"W": "bdb4c8", # white shade
	"t": "33a3a0", # teal
	"T": "22706f", # teal dark
	"p": "7a3f9a", # purple
	"P": "552b70", # purple dark
	"l": "2b2340", # leggings
	"b": "6b3f2a", # boots
	"m": "e0707e", # blush / mouth
	"r": "d8344f", # red
	"R": "8f1f35", # red dark
	"o": "ff9a3c", # orange
	"O": "ffd27a", # orange light
	"g": "4fb84f", # green
	"G": "2f7a3a", # green dark
	"n": "8a5a3a", # brown
	"N": "5a3a24", # brown dark
	"a": "9aa3b8", # grey
	"A": "5d6478", # grey dark
	"u": "4a7be0", # blue
	"U": "2a4a99", # blue dark
	"i": "bfe9ff", # ice / light blue
	"x": "ff7ab8", # pink
	"X": "b83a7a", # pink dark
	"z": "ffffff", # pure white (shine)
	"q": "3b3b58", # coat navy
	"Q": "25253a", # coat navy dark
	"f": "f7e3b0", # beard / pale
	"F": "c9b48a", # beard shade
}

# ------------------------------------------------------------------ Mira
# 16x16 frames, facing right. Hitbox is columns 4-11, rows 5-15.

const MIRA_HEAD := [
	"................",
	"................",
	"................",
	"......kkkk......",
	".....kcccck.....",
	"....kcccccCk....",
	"....kyyyyyyk....",
	"....khsssesk....",
	"....khssssmk....",
	"....kwwwwwWk....",
]

const MIRA_BODY := [
	"....ktpttpTk....",
	"...kstpptpTsk...",
	"....kTTTTTTk....",
]

const LEGS := {
	"stand": [".....kllllk.....", ".....klkklk.....", "....kbbkkbbk...."],
	"run_a": [".....kllllk.....", "....kllkkllk....", "...kbbk..kbbk..."],
	"run_b": [".....kllllk.....", ".....kllllk.....", ".....kbbbbk....."],
	"run_c": [".....kllllk.....", "....klk.kllk....", "....kbk.kbbk...."],
	"rise": [".....kllllk.....", "......kllk......", "......kbbk......"],
	"fall": [".....kllllk.....", "....klk..klk....", "...kbbk..kbbk..."],
	"dash": ["....kllllk......", "...kllkkk.......", "..kbbk.........."],
	"climb_a": [".....kllllk.....", ".....klkkllk....", ".....kbk.kbbk..."],
	"climb_b": [".....kllllk.....", "....kllkklk.....", "....kbbk.kbk...."],
	"sit": ["....kllllllk....", "....kllllllbbk..", ".....kkkkkkkk..."],
}


static func _mira_frame(legs: String, body_dy: int = 0, head_dx: int = 0, arms: String = "") -> Array:
	var rows: Array = []
	for i in 16:
		rows.append("................")
	var head: Array = MIRA_HEAD.duplicate()
	var body: Array = MIRA_BODY.duplicate()
	match arms:
		"up":
			body[1] = "....ktpptpTk...."
			head[9] = "...skwwwwwWks..."
		"wall":
			body[1] = "....ktpptpTks..."
			head[8] = "....khssssmks..."
		"wall2":
			body[1] = "....ktpptpTk...."
			head[7] = "....khsssesks..."
			body[2] = "....kTTTTTTks..."
		"back":
			body[1] = "..sktpptpTk....."
		"fwd":
			body[1] = "....ktpptpTkss.."
	for r in 10:
		var line: String = head[r]
		if head_dx != 0:
			line = _shift(line, head_dx)
		_put(rows, r + body_dy, line)
	for r in 3:
		var line: String = body[r]
		if head_dx != 0 and r == 0:
			line = _shift(line, head_dx)
		_put(rows, 10 + r + body_dy, line)
	var lg: Array = LEGS[legs]
	for r in 3:
		_put(rows, 13 + r, lg[r])
	return rows


static func _shift(line: String, dx: int) -> String:
	if dx > 0:
		return ".".repeat(dx) + line.substr(0, line.length() - dx)
	return line.substr(-dx) + ".".repeat(-dx)


static func _put(rows: Array, r: int, line: String) -> void:
	if r < 0 or r >= rows.size():
		return
	var cur: String = rows[r]
	var out := ""
	for i in cur.length():
		var c := line[i] if i < line.length() else "."
		out += c if c != "." else cur[i]
	rows[r] = out


## Frame order used by the player renderer.
const MIRA_FRAMES := [
	"idle0", "idle1", "run0", "run1", "run2", "run3", "run4", "run5",
	"rise", "peak", "fall", "dash", "climb0", "climb1", "slide", "duck", "sit", "look",
]


static func mira_frames() -> Array:
	var f: Array = []
	f.append(_mira_frame("stand"))                       # idle0
	f.append(_mira_frame("stand", 1))                    # idle1 (breath)
	f.append(_mira_frame("run_a", 0, 0, "back"))         # run0
	f.append(_mira_frame("run_b", 1, 0, ""))             # run1
	f.append(_mira_frame("run_c", 0, 0, "fwd"))          # run2
	f.append(_mira_frame("run_a", 0, 0, "fwd"))          # run3
	f.append(_mira_frame("run_b", 1, 0, ""))             # run4
	f.append(_mira_frame("run_c", 0, 0, "back"))         # run5
	f.append(_mira_frame("rise", 0, 0, "up"))            # rise
	f.append(_mira_frame("run_b", 0, 0, ""))             # peak
	f.append(_mira_frame("fall", 0, 0, "up"))            # fall
	f.append(_mira_frame("dash", 1, 1, "fwd"))           # dash
	f.append(_mira_frame("climb_a", 0, 0, "wall"))       # climb0
	f.append(_mira_frame("climb_b", 0, 0, "wall2"))      # climb1
	f.append(_mira_frame("fall", 0, 0, "wall"))          # slide
	f.append(_mira_frame("stand", 2))                    # duck
	f.append(_mira_frame("sit", 2))                      # sit
	var look := _mira_frame("stand")
	look[7] = "....khssssek...."
	f.append(look)                                       # look
	return f


# ------------------------------------------------------------------ NPCs

const BELLAMY := [
	[
		"................",
		"................",
		"......kkkk......",
		".....knnnnk.....",
		"....knnnnnnk....",
		"...kkkkkkkkkk...",
		"....ksssssk.....",
		"....kseksek.....",
		"....ksssssk.....",
		"....kfffffk.....",
		"...kfffFfffk....",
		"...kqfffffqk....",
		"..kqqqfffqqqk...",
		"..kqqqqFqqqqk...",
		"..ksqqqqqqqsk...",
		"..kyqqqqqqqqk...",
		"..kYqqqqqqqqk...",
		"...kqqqqqqqk....",
		"...kQQQQQQQk....",
		"...kqqqkqqqk....",
		"...kqqk.kqqk....",
		"...kNNk.kNNk....",
		"..kNNNk.kNNNk...",
		"..kkkkk.kkkkk...",
	],
	[
		"................",
		"................",
		"................",
		"......kkkk......",
		".....knnnnk.....",
		"....knnnnnnk....",
		"...kkkkkkkkkk...",
		"....ksssssk.....",
		"....kseksek.....",
		"....ksssssk.....",
		"....kfffffk.....",
		"...kfffFfffk....",
		"..kqqfffffqqk...",
		"..kqqqfFfqqqk...",
		"..ksqqqqqqqsk...",
		"..kyqqqqqqqqk...",
		"..kYqqqqqqqqk...",
		"...kqqqqqqqk....",
		"...kQQQQQQQk....",
		"...kqqqkqqqk....",
		"...kqqk.kqqk....",
		"...kNNk.kNNk....",
		"..kNNNk.kNNNk...",
		"..kkkkk.kkkkk...",
	],
]

const TOBI := [
	[
		"................",
		"................",
		"................",
		".....kkkkkk.....",
		"....kkhkkhkk....",
		"....kkssssek....",
		"....kksssssk....",
		".....ksssmk.....",
		"....kgggggGk....",
		"...kyyggggyyk...",
		"...kyyyyyyyyk...",
		"...ksyyyyyysk...",
		"....kyyyyyyk....",
		".....kqqqqk.....",
		".....kqkkqk.....",
		"....kNNkkNNk....",
	],
	[
		"................",
		"................",
		"................",
		"................",
		".....kkkkkk.....",
		"....kkhkkhkk....",
		"....kkssssek....",
		"....kksssssk....",
		".....ksssmk.....",
		"....kgggggGk....",
		"...kyyggggyyk...",
		"...ksyyyyyysk...",
		"....kyyyyyyk....",
		".....kqqqqk.....",
		".....kqkkqk.....",
		"....kNNkkNNk....",
	],
]

const ODDO := [
	[
		"......kkkk......",
		"......kqqk......",
		"......kqqk......",
		"......kqqk......",
		".....krrrrk.....",
		"....kkkkkkkk....",
		".....kwwwwk.....",
		".....kwewek.....",
		".....kwwwwk.....",
		"....kkFkkFkk....",
		".....kwwwwk.....",
		"....krrwwrrk....",
		"...krrrwwrrrk...",
		"...krrrywrrrk...",
		"..kwrrrwwrrrwk..",
		"...krrrywrrrk...",
		"...krrrwwrrrk...",
		"...kRRRRRRRRk...",
		"....kRRkkRRk....",
		"....kwwk.kwk....",
		".....kwk..kk....",
		"......kk........",
		"................",
		"................",
	],
]

const MAGPIE := [
	[
		"........",
		"...kk...",
		"..kkzk..",
		"kkkkkkyy",
		".kzzkk..",
		"..kkkk..",
		"...k.k..",
		"........",
	],
	[
		".k......",
		"kkkk....",
		".kkkkk..",
		"..kkzkyy",
		".kzzkk..",
		"..kkkk..",
		"........",
		"........",
	],
	[
		"........",
		"...kk...",
		"..kkzkyy",
		".kkzzk..",
		"kkkkkk..",
		"kk..k...",
		"........",
		"........",
	],
]

# ------------------------------------------------------------------ Objects (16x16 cells)

const OBJECTS := {
	"berry0": [
		"................",
		"................",
		"................",
		"......gG........",
		".....gGgg.......",
		"....kkkkkk......",
		"...kOooooOk.....",
		"..kOoozooook....",
		"..koooooooRk....",
		"..koooooooRk....",
		"...kooooooRk....",
		"...kooooRRk.....",
		"....kooRRk......",
		".....kkkk.......",
		"................",
		"................",
	],
	"berry1": [
		"................",
		"................",
		"................",
		"................",
		"......gG........",
		".....gGgg.......",
		"....kkkkkk......",
		"...kOooooOk.....",
		"..kOoozooook....",
		"..koooooooRk....",
		"..koooooooRk....",
		"...kooooooRk....",
		"...kooooRRk.....",
		"....kooRRk......",
		".....kkkk.......",
		"................",
	],
	"wing0": [
		"................",
		"................",
		"................",
		"................",
		"..........kk....",
		"........kkzzk...",
		".......kzzzzzk..",
		".......kzzWzzzk.",
		"........kWWzzk..",
		".........kkkk...",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
	],
	"wing1": [
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		".......kkkkk....",
		"......kzzzzzzk..",
		".......kzzWWzzk.",
		"........kkWzzk..",
		"..........kkk...",
		"................",
		"................",
		"................",
		"................",
	],
	"gem0": [
		"................",
		"................",
		"................",
		".......kk.......",
		"......kzgk......",
		".....kzggGk.....",
		"....kzgggGGk....",
		"...kzggggGGGk...",
		"....kgggGGGk....",
		".....kggGGk.....",
		"......kgGk......",
		".......kk.......",
		"................",
		"................",
		"................",
		"................",
	],
	"gem1": [
		"................",
		"................",
		"................",
		"................",
		".......kk.......",
		"......kzgk......",
		".....kzggGk.....",
		"....kzgggGGk....",
		"...kzggggGGGk...",
		"....kgggGGGk....",
		".....kggGGk.....",
		"......kgGk......",
		".......kk.......",
		"................",
		"................",
		"................",
	],
	"spring0": [
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"................",
		"....kkkkkkkk....",
		"....kyyyyyyk....",
		"....krrrrrrk....",
		"....krryyrrk....",
		"....kkkkkkkk....",
	],
	"spring1": [
		"................",
		"................",
		"................",
		"......kkkk......",
		".....kwwwwk.....",
		".....kweewk.....",
		".....kwmmwk.....",
		"......kkkk......",
		".......ak.......",
		"......ak........",
		".......ak.......",
		"....kkkkkkkk....",
		"....kyyyyyyk....",
		"....krrrrrrk....",
		"....krryyrrk....",
		"....kkkkkkkk....",
	],
	"key": [
		"................",
		"................",
		"................",
		"................",
		"................",
		"....kkk.........",
		"...kyyyk........",
		"...ky.ykkkkkkk..",
		"...kyyyyyyyyyk..",
		"....kkkkkyYkYk..",
		".........k.k.k..",
		"................",
		"................",
		"................",
		"................",
		"................",
	],
	"bell0": [
		"................",
		".....kk.kk......",
		"....kxxkxxk.....",
		".....kxxxk......",
		"......kyk.......",
		".....kyzyk......",
		"....kyzyyyk.....",
		"....kyzyyyk.....",
		"...kyyyyyyYk....",
		"...kyyyyyyYk....",
		"..kyyyyyyyyYk...",
		"..kYYYYYYYYYk...",
		"...kkkkkkkkk....",
		"......kYk.......",
		".......k........",
		"................",
	],
	"bell1": [
		"................",
		".....kk.kk......",
		"....kxxkxxk.....",
		".....kxxxk......",
		"......kyk.......",
		".....kyzyk......",
		"....kyzyyyk.....",
		"....kyzyyyk.....",
		"...kyyyyyyYk....",
		"...kyyyyyyYk....",
		"..kyyyyyyyyYk...",
		"..kYYYYYYYYYk...",
		"...kkkkkkkkk....",
		".......kYk......",
		"........k.......",
		"................",
	],
	"balloon0": [
		"................",
		".....kkkkk......",
		"....krrrrrk.....",
		"...krzrrrrRk....",
		"...krzrrrrRk....",
		"...krrrrrrRk....",
		"...krrrrrRRk....",
		"....krrrRRk.....",
		".....kRRRk......",
		"......kkk.......",
		".......a........",
		"......a.........",
		".......a........",
		"........a.......",
		".......a........",
		"................",
	],
	"balloon1": [
		"................",
		"................",
		".....kkkkk......",
		"....krrrrrk.....",
		"...krzrrrrRk....",
		"...krzrrrrRk....",
		"...krrrrrrRk....",
		"...krrrrrRRk....",
		"....krrrRRk.....",
		".....kRRRk......",
		"......kkk.......",
		"......a.........",
		".......a........",
		"........a.......",
		".......a........",
		"................",
	],
	"bumper0": [
		"................",
		".....kkkkkk.....",
		"...kkuuuuuukk...",
		"..kuuuuyuuuuuk..",
		"..kuuuyyyuuuuk..",
		".kuuyyyyyyyuuUk.",
		".kuuuyyyyyuuuUk.",
		".kuuuyyyyyuuuUk.",
		".kuuyyyuyyyuuUk.",
		".kuuyuuuuuyuuUk.",
		"..kuuuuuuuuuUk..",
		"..kUuuuuuuuUUk..",
		"...kkUUUUUUkk...",
		".....kkkkkk.....",
		"................",
		"................",
	],
	"bumper1": [
		"................",
		".....kkkkkk.....",
		"...kkxxxxxxkk...",
		"..kxxxxyxxxxxk..",
		"..kxxxyyyxxxxk..",
		".kxxyyyyyyyxxXk.",
		".kxxxyyyyyxxxXk.",
		".kxxxyyyyyxxxXk.",
		".kxxyyyxyyyxxXk.",
		".kxxyxxxxxyxxXk.",
		"..kxxxxxxxxxXk..",
		"..kXxxxxxxxXXk..",
		"...kkXXXXXXkk...",
		".....kkkkkk.....",
		"................",
		"................",
	],
	"flag0": [
		"....k...........",
		"...kyk..........",
		"....kkkkkkk.....",
		"....krrrrppk....",
		"....krrrrpppkk..",
		"....krrrppppppk.",
		"....kkrrpppkkk..",
		"....k.kkkkk.....",
		"....k...........",
		"....k...........",
		"....k...........",
		"....k...........",
		"....k...........",
		"....k...........",
		"...kAk..........",
		"..kAAAk.........",
	],
	"flag1": [
		"....k...........",
		"...kyk..........",
		"....kkkkkkkk....",
		"....krrrrrppk...",
		"....krrrrpppkk..",
		"....krrrrppppk..",
		"....kkrrppppk...",
		"....k.kkkkkk....",
		"....k...........",
		"....k...........",
		"....k...........",
		"....k...........",
		"....k...........",
		"....k...........",
		"...kAk..........",
		"..kAAAk.........",
	],
	"fire0": [
		"................",
		"................",
		"................",
		"................",
		"................",
		".......o........",
		"......ooo.......",
		"......oOo.o.....",
		".....ooOOoo.....",
		".....oOyyOo.....",
		"....ooOyyOoo....",
		"....oOyzzyOo....",
		"...knNnknNnNk...",
		"..kNnNNkNNnNNk..",
		"...kkkkkkkkkk...",
		"................",
	],
	"fire1": [
		"................",
		"................",
		"................",
		"................",
		"........o.......",
		".......oo.......",
		"......ooOo......",
		".....o.oOo......",
		".....ooOOoo.....",
		".....oOyyOoo....",
		"....ooOyyyOo....",
		"....oOyzzyOo....",
		"...knNnknNnNk...",
		"..kNnNNkNNnNNk..",
		"...kkkkkkkkkk...",
		"................",
	],
	"heart": [
		"................",
		"................",
		"...kkk..kkk.....",
		"..kxxxkkxxxk....",
		".kxzxxxxxxxXk...",
		".kxzxxxxxxxXk...",
		".kxxxxxxxxXXk...",
		"..kxxxxxxXXk....",
		"...kxxxxXXk.....",
		"....kxxXXk......",
		".....kXXk.......",
		"......kk........",
		"................",
		"................",
		"................",
		"................",
	],
	"ball_r": [
		"................", "................", "................", "................",
		"................", "......kkkk......", ".....krzrrk.....", ".....krrrRk.....",
		".....krrRRk.....", "......kkkk......", "................", "................",
		"................", "................", "................", "................",
	],
	"ball_y": [
		"................", "................", "................", "................",
		"................", "......kkkk......", ".....kyzyyk.....", ".....kyyyYk.....",
		".....kyyYYk.....", "......kkkk......", "................", "................",
		"................", "................", "................", "................",
	],
	"ball_u": [
		"................", "................", "................", "................",
		"................", "......kkkk......", ".....kuzuuk.....", ".....kuuuUk.....",
		".....kuuUUk.....", "......kkkk......", "................", "................",
		"................", "................", "................", "................",
	],
}

const OBJECT_ORDER := [
	"berry0", "berry1", "wing0", "wing1", "gem0", "gem1", "spring0", "spring1",
	"key", "bell0", "bell1", "balloon0", "balloon1", "bumper0", "bumper1", "flag0",
	"flag1", "fire0", "fire1", "heart", "ball_r", "ball_y", "ball_u",
]

# ------------------------------------------------------------------ Portraits (32x32)
# Built from a base face plus per-expression eye/mouth patches.

const PORTRAIT_BASE := {
	"mira": [
		"................................",
		"...........kkkkkkkk.............",
		".........kkccccccccCkk..........",
		"......kkkcccccccccccCCkkk.......",
		"....kkcccccccccccccccCCCCkk.....",
		"...kccCkcccccccccccccccCCCCk....",
		"..kcCCk.kccccccccccccccCCCCCk...",
		"..kCCk..kyyyyyyyyyyyyyyyyCCCk...",
		"..kyk..kyyyyyyyyyyyyyyyyyykCk...",
		"..kYk..khhhhhhhhhhhhhhhhhhk.kyk.",
		"...k..khhhhhssssssssshhhhhhk.kYk",
		"......khhhsssssssssssssshhhk..k.",
		"......khhssssssssssssssssshk....",
		"......khsssssssssssssssssshk....",
		"......khssssssssssssssssssk.....",
		"......khssssssssssssssssssk.....",
		"......khsssssssssssssssssdk.....",
		"......khssmmsssssssssmmsdk......",
		".......khssssssssssssssdk.......",
		".......khsssssssssssssddk.......",
		"........khssssssssssssdk........",
		".........kddsssssssddk..........",
		"..........kkddddddkk............",
		"........kkwwwWWWWWwwwkk.........",
		"......kkwwwwwWWWWWwwwwwkk.......",
		".....kwwwwwwwWWWWWwwwwwwwk......",
		"....ktttwwwwwwwwwwwwwwwtttk.....",
		"...kttttpptttttttttttpptttTk....",
		"...ktttpppptttttttttppppttTk....",
		"..kttttppppttttttttttppptTTTk...",
		"..ktttttppttttttttttttpptTTTk...",
		"..kkkkkkkkkkkkkkkkkkkkkkkkkkk...",
	],
	"grin": [
		"................................",
		"...........kkkkkkkk.............",
		".........kkppppppppPkk..........",
		"......kkkpppppppppppPPkkk.......",
		"....kkpppppppppppppppPPPPkk.....",
		"...kppPkpppppppppppppppPPPPk....",
		"..kpPPk.kppppppppppppppPPPPPk...",
		"..kPPk..krrrrrrrrrrrrrrrrPPPk...",
		"..krk..krrrrrrrrrrrrrrrrrrkPk...",
		"..kRk..kwwwwwwwwwwwwwwwwwwk.krk.",
		"...k..kwwwwwwwwwwwwwwwwwwwwk.kRk",
		"......kwwwwwwwwwwwwwwwwwwwwk..k.",
		"......kwwwwwwwwwwwwwwwwwwwwk....",
		"......kwwwwwwwwwwwwwwwwwwwwk....",
		"......kwwwwwwwwwwwwwwwwwwwk.....",
		"......kwwwwwwwwwwwwwwwwwwwk.....",
		"......kwwwwwwwwwwwwwwwwwwWk.....",
		"......kwwxxwwwwwwwwwwxxwWk......",
		".......kwwwwwwwwwwwwwwwWk.......",
		".......kwwwwwwwwwwwwwwWWk.......",
		"........kwwwwwwwwwwwwwWk........",
		".........kWWwwwwwwwWWk..........",
		"..........kkWWWWWWkk............",
		"........kkPPPPPPPPPPPPkk........",
		"......kkPPPPPPPPPPPPPPPPkk......",
		".....kPPPPPPPPPPPPPPPPPPPPk.....",
		"....kpppPPPPPPPPPPPPPPPpppk.....",
		"...kpppprrpppppppppppprrpppk....",
		"...kppprrrrppppppppprrrrppPk....",
		"..kpppprrrrpppppppppprrrpPPPk...",
		"..kppppprrpppppppppppprrpPPPk...",
		"..kkkkkkkkkkkkkkkkkkkkkkkkkkk...",
	],
	"bellamy": [
		"................................",
		"................................",
		"..........kkkkkkkkkk............",
		"........kknnnnnnnnnnkk..........",
		".......knnnnnnnnnnnnnnk.........",
		"......knnnnnnnnnnnnnnnnk........",
		"....kkkkkkkkkkkkkkkkkkkkkk......",
		"...knnnnnnnnnnnnnnnnnnnnnnk.....",
		"....kkkkkkkkkkkkkkkkkkkkkk......",
		"......kssssssssssssssssk........",
		".....kssssssssssssssssssk.......",
		".....ksssssssssssssssssssk......",
		"....kfssssssssssssssssssfk......",
		"....kffssssssssssssssssffk......",
		"....kfsssssssssssssssssssk......",
		"....ksssssssssssssssssssdk......",
		"....kssssssssssddssssssdk.......",
		"....kfffffssssddddssssfffk......",
		"....kffffffffffffffffffffk......",
		"...kffffffffffffffffffffffk.....",
		"...kfffffffFFFFFFfffffffffk.....",
		"...kffffffffFFFFfffffffffFk.....",
		"....kfffffffffffffffffffFk......",
		"....kqffffffffffffffffffqk......",
		"...kqqqfffffffffffffffqqqqk.....",
		"..kqqqqqfffffffffffffqqqqqqk....",
		"..kqqqqqqqffffffffffqqqqqqqqk...",
		".kqqqqqqqqqfffffffqqqqqqqqqqk...",
		".kqqqqqqqqqqqfffqqqqqqyqqqqqQk..",
		".kqqqqqqqqqqqqqqqqqqqyyyqqqqQk..",
		".kqqqqqqqqqqqqqqqqqqqqqqqqqQQk..",
		".kkkkkkkkkkkkkkkkkkkkkkkkkkkkk..",
	],
	"tobi": [
		"................................",
		"................................",
		"..........kkkkkkkkkk............",
		"........kkhhhhhhhhhhkk..........",
		".......khhhhkhhhhhkhhhhk........",
		"......khhhhhhhhhhhhhhhhhk.......",
		".....khhhhhhhhhhhhhhhhhhhk......",
		".....khhhkhhhhhhhhhhkhhhhk......",
		".....khhhhhhhhhhhhhhhhhhhk......",
		".....khhhsssssssssssssshhk......",
		".....khhsssssssssssssssshk......",
		".....khssssssssssssssssshk......",
		".....khssssssssssssssssssk......",
		".....kssssssssssssssssssskk.....",
		".....kssssssssssssssssssdsk.....",
		".....ksssssssssssssssssdsk......",
		"......ksssssssssssssssssdk......",
		"......ksmmssssssssssmmsdk.......",
		".......ksssssssssssssssdk.......",
		".......kssssssssssssssddk.......",
		"........kssssssssssssddk........",
		".........kdssssssssddk..........",
		"..........kkddddddkk............",
		"........kkggggggggggGGkk........",
		"......kkggggggggggggggGGkk......",
		".....kyggggggggggggggggGGyk.....",
		"....kyyyyGGGGGGGGGGGGGGyyyyk....",
		"...kyyyyyyyyyyyyyyyyyyyyyyyyk...",
		"...kyyyyyyyyyyyyyyyyyyyyyyyyk...",
		"..kyyyyyyyyyyyyykyyyyyyyyyyyYk..",
		"..kyyyyyyyyyyyyykyyyyyyyyyyYYk..",
		"..kkkkkkkkkkkkkkkkkkkkkkkkkkkk..",
	],
	"oddo": [
		"..........kkkkkkkkkk............",
		"..........kqqqqqqqqk............",
		"..........kqqqqqqqqk............",
		"..........kqqqqqqqqk............",
		"..........kqqqqqqqqk............",
		"..........krrrrrrrrk............",
		"......kkkkkkkkkkkkkkkkkk........",
		".......kwwwwwwwwwwwwwwk.........",
		"......kwwwwwwwwwwwwwwwwk........",
		"......kwwwwwwwwwwwwwwwwk........",
		".....kwwwwwwwwwwwwwwwwwwk.......",
		".....kwwwwwwwwwwwwwwwwwwk.......",
		".....kwwwwwwwwwwwwwwwwwwk.......",
		".....kwwwwwwwwwwwwwwwwwwk.......",
		".....kwwwwwwwwwwwwwwwwwWk.......",
		".....kwwwwwwwwwwwwwwwwwWk.......",
		".....kwwwwwwwwwwwwwwwwWWk.......",
		"....kkkkkkwwwwwwwwkkkkkkk.......",
		"...kFFFFFFkwwwwwwkFFFFFFk.......",
		"....kkkkkkwwwwwwwwkkkkkk........",
		"......kwwwwwwwwwwwwwwWk.........",
		".......kwwwwwwwwwwwwWk..........",
		"........kkwwwwwwwwkkk...........",
		"........kkrrrrrrrrrrkk..........",
		"......kkrrrrrwwwwrrrrrkk........",
		".....krrrrrrrwwwwrrrrrrrk.......",
		"....krrrrrrrrwyywrrrrrrrrk......",
		"...krrrrrrrrrwwwwrrrrrrrrRk.....",
		"...krrrrrrrrrwyywrrrrrrrRRk.....",
		"..krrrrrrrrrrwwwwrrrrrrrRRRk....",
		"..krrrrrrrrrrwwwwrrrrrrrRRRk....",
		"..kkkkkkkkkkkkkkkkkkkkkkkkkk....",
	],
}

## Eye rows (placed at row 13-15) and mouth rows (row 18-20), all 32 wide.
## '.' leaves the base pixel untouched.
const EYES := {
	"normal": [
		"................................",
		"..........kk.......kk...........",
		"..........ek.......ek...........",
	],
	"happy": [
		"................................",
		"..........kk.......kk...........",
		".........k..k.....k..k..........",
	],
	"sad": [
		".........kk.........kk..........",
		"..........kk.......kk...........",
		"..........ek.......ek...........",
	],
	"angry": [
		"..........kk.......kk...........",
		"...........kk.....kk............",
		"..........ek.......ek...........",
	],
	"closed": [
		"................................",
		"................................",
		".........kkk.......kkk..........",
	],
	"wide": [
		"..........kk.......kk...........",
		".........kzek.....kzek..........",
		".........keek.....keek..........",
	],
}

const MOUTHS := {
	"normal": [
		"................................",
		"..............kkk...............",
		"................................",
	],
	"smile": [
		".............k...k..............",
		"..............kkk...............",
		"................................",
	],
	"grin": [
		"............kkkkkkk.............",
		"............kzzzzzk.............",
		".............kkkkk..............",
	],
	"frown": [
		"..............kkk...............",
		".............k...k..............",
		"................................",
	],
	"open": [
		"..............kkk...............",
		".............kRRRk..............",
		"..............kkk...............",
	],
	"wobble": [
		"................................",
		".............k.k.k..............",
		"..............k.k...............",
	],
	"evil": [
		"..........kk.......kk...........",
		"...........krrrrrrrk............",
		"............kkkkkkk.............",
	],
}

## character -> list of [name, eyes, mouth, extra]
const PORTRAIT_SETS := {
	"mira": [["normal", "normal", "normal"], ["happy", "happy", "smile"], ["grin", "happy", "grin"],
		["sad", "sad", "frown"], ["worried", "sad", "wobble"], ["angry", "angry", "frown"],
		["surprised", "wide", "open"], ["determined", "angry", "normal"], ["tears", "closed", "wobble"]],
	"grin": [["normal", "normal", "evil"], ["smirk", "angry", "evil"], ["angry", "angry", "open"],
		["sad", "sad", "frown"], ["soft", "closed", "smile"]],
	"bellamy": [["normal", "normal", "normal"], ["laugh", "happy", "open"], ["sad", "sad", "frown"], ["smile", "closed", "smile"]],
	"tobi": [["normal", "normal", "normal"], ["happy", "happy", "smile"], ["scared", "wide", "wobble"], ["sad", "sad", "frown"], ["surprised", "wide", "open"]],
	"oddo": [["normal", "normal", "smile"], ["frantic", "wide", "open"], ["sad", "sad", "frown"], ["peace", "closed", "smile"]],
}


static func render(rows: Array, w: int = -1, h: int = -1) -> Image:
	var hh := rows.size() if h < 0 else h
	var ww := 0
	for r in rows:
		ww = maxi(ww, (r as String).length())
	if w > 0:
		ww = w
	var img := Image.create(ww, hh, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	blit_ascii(img, rows, 0, 0)
	return img


static func blit_ascii(img: Image, rows: Array, ox: int, oy: int, pal_override: Dictionary = {}) -> void:
	for y in rows.size():
		var line: String = rows[y]
		for x in line.length():
			var ch := line[x]
			if ch == "." or ch == " ":
				continue
			var hex: String = pal_override.get(ch, PAL.get(ch, ""))
			if hex == "":
				continue
			var px := ox + x
			var py := oy + y
			if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
				img.set_pixel(px, py, Color.html("#" + hex))


static func portrait(character: String, eyes: String, mouth: String) -> Image:
	var base: Array = PORTRAIT_BASE[character]
	var img := render(base, 32, 32)
	var eye_row := 13
	var mouth_row := 18
	if character == "bellamy":
		eye_row = 11
		mouth_row = 16
	elif character == "oddo":
		eye_row = 10
		mouth_row = 19
	elif character == "tobi":
		eye_row = 13
		mouth_row = 18
	var e: Array = EYES[eyes]
	var m: Array = MOUTHS[mouth]
	var pal := {}
	if character == "grin":
		pal = {"e": "ff3a5a", "k": "1c1424"}
	if character == "oddo":
		pal = {"e": "6fd6ff"}
	blit_ascii(img, e, 0, eye_row, pal)
	blit_ascii(img, m, 0, mouth_row, pal)
	if character == "bellamy" and eyes != "closed":
		# spectacles
		for p in [Vector2i(8, 12), Vector2i(9, 12), Vector2i(10, 12), Vector2i(11, 12), Vector2i(12, 12), Vector2i(17, 12), Vector2i(18, 12), Vector2i(19, 12), Vector2i(20, 12), Vector2i(21, 12), Vector2i(13, 13), Vector2i(14, 13), Vector2i(15, 13), Vector2i(16, 13)]:
			img.set_pixel(p.x, p.y, Color.html("#1c1424"))
	if character == "mira" and eyes == "closed" and mouth == "wobble":
		# tear streaks
		for p in [Vector2i(10, 16), Vector2i(10, 17), Vector2i(21, 16), Vector2i(21, 17), Vector2i(10, 18)]:
			img.set_pixel(p.x, p.y, Color.html("#8fd0ff"))
	return img
