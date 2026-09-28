extends SceneTree
## tools/look_world.gd — photograph the REAL wilderness road from the REAL game.
##
## Not a mockup: this boots `main.gd` through its own `_ready()`, enters the world screen by the
## route a player takes (the map's stop -> `show_world`), and captures the frame. The Python
## mockups exist to argue about a layout; this is the evidence that the layout is what shipped.
##
##   godot4 --path . --rendering-driver opengl3 --resolution 390x844 \
##       --script res://tools/look_world.gd -- --act 0 --fight 3 --out /tmp/look/world_fight3.png [--walk]
##
## `--walk` sets `areaFightProgress` to fight-1 before entering, so the hero walks from the
## previous node — the motion Jan asked to see. Without it he stands still on the node.
##
## ⚠️  `--headless` cannot shoot: it waits on `RenderingServer.frame_post_draw`, which never
## fires there. Use `--rendering-driver opengl3`.

var _main: Node = null
var _out := "/tmp/look/world_fight.png"
var _act := 0
var _fight := 3
var _walk := false
var _frames := 0
var _started := false
## Frames to let the walk finish before shooting (WALK_SPEED is 1.6 nodes/s, so two nodes is
## 1.25 s; 90 frames at ~60 fps is comfortable and still deterministic enough to read).
const SETTLE := 40


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--out":
				_out = args[i + 1]
			"--act":
				_act = int(args[i + 1])
			"--fight":
				_fight = int(args[i + 1])
			"--walk":
				_walk = true
		i += 1
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		# The same gate as capture_screen.gd: `_nav_bar` is the last cheap marker of "main is
		# fully built". Entering before it lets the town overwrite what was asked for.
		if not _main._screens.has("world") or _main._nav_bar == null:
			return false
		_started = true
		_main.state.data["locationProgress"][_act] = 0
		_main.state.data["areaFightProgress"][_act] = _fight - 1 if _walk else _fight
		_main.state.data["townPortalCount"] = 1
		# Through the real route: `show_world` is what the map's stop selection calls.
		_main.show_world(_act)
		return false

	_frames += 1
	if _frames < SETTLE:
		return false
	var w = _main._screens["world"]
	print("PROBE world size=%s canvas=%s nodes=%d" % [str(w.size), str(w._canvas.size),
		w._total_fights()])
	# ⚠️  The hero was removed from this screen (Jan: "Dejme tělo hrdiny úplně pryč"), so there is
	# no `w._hero` to report any more. Printing its position here crashed the tool with a null
	# access and the frame was never captured — the same class of silent breakage as a tool that
	# writes a real frame under a wrong name.
	print("PROBE band top=%s bottom=%s centre=%s amp=%s" % [str(w.ROAD_TOP),
		str(w.ROAD_BOTTOM), str(w.SERPENTINE_CENTER), str(w.SERPENTINE_AMP)])
	_capture()
	return false


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(_out)
	print("look_world: %s %dx%d act=%d fight=%d walk=%s" % [_out, img.get_width(),
		img.get_height(), _act, _fight, str(_walk)])
	quit(0)
