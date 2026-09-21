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
	# _ready() on a node added in _initialize() has NOT run yet — the SceneTree calls it
	# when the main loop starts, i.e. after this first _process. Waiting only "one frame"
	# was not enough: `show_screen("town")` in main's _ready() runs AFTER _entry() and
	# overwrites whatever the capture asked for, which is why every `--screen` other than
	# town came back as the town. Wait until the screens actually exist, then enter.
	if not _started:
		# Wait for main to be FULLY built, not merely started. `_screens["town"]` exists as
		# soon as its `_add_screen` runs, but `_build_screens()` continues and `_ready()`
		# then calls `show_screen("town")` — which resets every screen's visibility. Entering
		# between those two points let town overwrite whatever was asked for, so every
		# `--screen` came back as the town. `_nav_bar` is built after the screens and before
		# that call, so it is the last cheap marker of "main is done".
		if not _main._screens.has("town") or _main._nav_bar == null:
			return false
		_started = true
		_entry()
		return false

	_frames += 1
	if _frames < _target:
		return false
	# _capture() awaits frame_post_draw, so the tree MUST stay alive this frame or the
	# await never resumes and no PNG is written (the old `return true` here did exactly
	# that): quit() only inside _capture, after the image is saved.
	_capture()
	return false


func _entry() -> void:
	if _screen == "":
		return
	# `inventory`, `talents` and `hero` are the PWA's three tabs of ONE modal — in the port
	# they are `character` plus a tab name, so both the old keys (which the reference set
	# is named after) and explicit `<screen>@<tab>` forms resolve here.
	if _screen.begins_with("character"):
		var tab := "inventory"
		if _screen.contains("@"):
			tab = _screen.split("@")[1]
		_main.open_modal(tab)
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
