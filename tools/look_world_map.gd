extends SceneTree
class_name LookWorldMap
## LookWorldMap — boot the game, open the MAP with one act EXPANDED, and write a PNG.
##
## Why this exists: the map opens COLLAPSED (the PWA's router initialises its expanded pane
## to -1), so `capture_screen.gd --screen map` can only ever show the act cards and never the
## stop path — which is the one part of the screen a world mockup is drawn against. The stop
## path is also where a walking hero would go, so it has to be photographable on its own.
##
##   godot4 --path . --rendering-driver opengl3 --resolution 390x844 \
##       --script res://tools/look_world_map.gd -- --act 0 --out /tmp/map_open.png
##
## The expansion goes through the screen's OWN `_toggle_act()`, i.e. the route the act card's
## press takes, rather than writing `_expanded_act` — a hand-written field would pass against
## broken wiring, which is the same trap the map's own test warns about.

var _main: Node = null
var _out := "/tmp/map_open.png"
var _act := 0
var _frames := 0
var _started := false
## Frames to wait after the act is expanded before shooting. The path is BUILT on the toggle,
## so a shot on the toggle frame photographs the previous layout.
const SETTLE := 25


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--out":
				_out = args[i + 1]
			"--act":
				_act = int(args[i + 1])
		i += 2
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		# Same gate as capture_screen.gd: `_nav_bar` is the last cheap marker of "main is
		# fully built", and entering before it lets the town overwrite what was asked for.
		if not _main._screens.has("town") or _main._nav_bar == null:
			return false
		_started = true
		_main.show_screen("map")
		return false

	_frames += 1
	var screen = _main._screens.get("map")
	if screen == null:
		return false
	if _frames == 5:
		# Expand through the screen's own toggle, i.e. the act card's press route.
		screen._toggle_act(_act)
		return false
	if _frames < 5 + SETTLE:
		return false
	_capture()
	return false


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(_out)
	print("look_world_map: %s %dx%d act=%d expanded=%s" % [_out, img.get_width(),
		img.get_height(), _act, str(_main._screens["map"]._expanded_act)])
	quit(0)
