extends SceneTree
class_name CaptureScreen
## CaptureScreen — boot the game, optionally jump to one screen, save a PNG.
##
## Why this exists: the port is judged against the PWA screenshots, and "the arena looks
## wrong" is not something a headless test can tell you. This drives the real main.gd and
## writes a real frame, so a visual diff is possible without a desktop.
##
##   godot4 --path . --script res://tools/capture_screen.gd -- \
##       --screen arena --out /tmp/port_arena.png --frames 90
##
## `--screen` accepts a router key (town, inventory, arena, shop, chest, craft, gamble,
## hero). `--fight-ticks N` steps the arena N times before the shot so the fight is
## mid-swing rather than on frame zero.

var _main: Node = null
var _frames := 0
var _target := 60
var _out := "/tmp/port_shot.png"
var _screen := ""
var _fight_ticks := 0
var _started := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--out":
				_out = args[i + 1]
			"--frames":
				_target = int(args[i + 1])
			"--screen":
				_screen = args[i + 1]
			"--fight-ticks":
				_fight_ticks = int(args[i + 1])
		i += 2
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	# _ready() on a node added in _initialize() may not have run yet; wait one frame
	# before touching the router, or the screens are not built and every key is missing.
	if not _started:
		_started = true
		_entry()
		return false

	_frames += 1
	if _frames < _target:
		return false
	_capture()
	return true


func _entry() -> void:
	if _screen == "":
		return
	if _screen == "arena":
		_main._on_wilderness()
		_main.show_screen("arena")
	else:
		_main.show_screen(_screen)
	if _fight_ticks > 0 and _screen == "arena":
		var arena = _main._screens["arena"]
		var t := 0
		while t < _fight_ticks and arena.battle != null and not arena.battle.ended:
			arena.step()
			t += 1


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(_out)
	print("capture: %s %dx%d" % [_out, img.get_width(), img.get_height()])
	quit()
