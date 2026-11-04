extends SceneTree
## probe_zoom_scroll.gd — proves a PROP scrolls at the SAME screen rate as the GROUND.
##
## The "rocks float" report: after the zoom pass the arena's ground was painted at ZOOM while
## every prop was painted at 1.0, so walking moved the rocks faster than the grass under them.
## This probe renders ONE known rock on a real frame and reports where its pixels landed, so the
## rate can be measured from the IMAGE rather than argued from the code:
##
##   godot4 --path . --rendering-driver opengl3 --resolution 390x844 \
##     --script res://tools/probe_zoom_scroll.gd -- --dx 0   --out /tmp/zs_a.png
##   godot4 --path . --rendering-driver opengl3 --resolution 390x844 \
##     --script res://tools/probe_zoom_scroll.gd -- --dx 200 --out /tmp/zs_b.png
##
## `--dx` moves the HERO 200 world px to the right, which moves the camera by the same 200 world
## px (the hero sits in the middle of an unclamped view). The rock's screen x must therefore drop
## by ZOOM * 200 = 164 px. A 200 px drop is the bug: the rock would be travelling 1.0x over grass
## travelling 0.82x.

const SurvivorRun := preload("res://scripts/combat/survivor_run.gd")

## One big rock on an empty field, at a fixed WORLD position.
const ROCK_AT := Vector2(800.0, 800.0)
const ROCK_SIZE := 120.0

var _main: Node = null
var _shot := false
var _dx := 0.0
var _out := "/tmp/probe_zoom_scroll.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var step := 2
		match args[i]:
			"--dx":
				_dx = float(args[i + 1])
			"--out":
				_out = args[i + 1]
			_:
				step = 1
		i += step
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _shot:
		return false
	if _main._screens == null or not _main._screens.has("town") or _main._nav_bar == null:
		return false
	_shot = true
	var splash := _main.get_node_or_null("SplashLayer")
	if splash != null:
		splash.visible = false
	_main._enter_survivor(0)
	var screen = _main._screens.get("survivor", null)
	if screen == null or screen.run == null:
		print("probe: FAIL no survivor run")
		quit(2)
		return false
	# Freeze the fight: the picture must differ between the two runs ONLY by the camera.
	screen.set_process(false)
	var run = screen.run
	run.monsters.clear()
	run.projectiles.clear()
	run.bolts.clear()
	run.effects.clear()
	run.drops.clear()
	run.numbers.clear()
	run.player_pos = SurvivorRun.WORLD * 0.5 + Vector2(_dx, 0.0)
	screen._props = [{"pos": ROCK_AT, "kind": "rock", "size": ROCK_SIZE, "seed": 0.4}]
	screen._patches.clear()
	screen._place_camera()
	screen.queue_redraw()
	_capture(screen)
	return false


func _capture(screen) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(_out)
	print("probe: %s dx=%.0f zoom=%.2f cam=%s rock=%s  expected_screen=%s"
		% [_out, _dx, screen.ZOOM, str(screen._cam), str(ROCK_AT),
			str((ROCK_AT - screen._cam) * screen.ZOOM)])
	quit(0)
