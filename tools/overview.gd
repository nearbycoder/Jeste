extends Node
## Renders every room of a chapter (static, at spawn) into one contact sheet.
## godot --path . --rendering-method mobile res://tools/overview.tscn -- <chapter> <out.png>
var rooms: Array = []
var idx := 0
var sv: SubViewport
var world: World
var view: RoomView
var pv: PlayerView
var bd: Backdrop
var imgs: Array[Image] = []
var names: Array = []
var ch: LevelDB.ChapterDef
var wait := 0
var out := ""

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	ch = LevelDB.get_chapter(int(a[0]))
	out = a[1]
	rooms = Array(ch.order)
	sv = SubViewport.new()
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.transparent_bg = false
	add_child(sv)
	bd = Backdrop.new()
	sv.add_child(bd)
	bd.setup(ch.number)
	world = World.new()
	view = RoomView.new()
	sv.add_child(view)
	pv = PlayerView.new()
	pv.world = world
	sv.add_child(pv)
	_load()

func _load() -> void:
	var r: RoomDef = ch.rooms[rooms[idx]]
	world.load_room(r, 0, ch.dashes)
	sv.size = Vector2i(r.w * 8, r.h * 8)
	view.build(r, world, ch.tileset, ch.number)
	pv.reset_tails()
	wait = 6

func _process(_d: float) -> void:
	wait -= 1
	if wait > 0:
		return
	var img := sv.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	imgs.append(img)
	names.append(rooms[idx])
	idx += 1
	if idx < rooms.size():
		_load()
		return
	var cols := 3
	var cw := 0
	var chh := 0
	for im in imgs:
		cw = maxi(cw, im.get_width())
		chh = maxi(chh, im.get_height())
	var rows := int(ceil(imgs.size() / float(cols)))
	var sheet := Image.create(cw * cols + (cols - 1) * 4, chh * rows + (rows - 1) * 4, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.2, 0.2, 0.25))
	for i in imgs.size():
		sheet.blit_rect(imgs[i], Rect2i(Vector2i.ZERO, imgs[i].get_size()), Vector2i((i % cols) * (cw + 4), (i / cols) * (chh + 4)))
	sheet.save_png(out)
	print("rooms: ", names)
	get_tree().quit()
