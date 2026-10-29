extends SceneTree
class_name LookSurvivor
## LookSurvivor — boot the game, enter the SURVIVOR RUN, play a couple of seconds and write a PNG.
##
## Why this exists: the survivor screen is drawn entirely in `_draw()`, so a headless run proves
## the rules and NOTHING about what the player sees. This is the only way to answer "how does it
## actually look on the phone" without asking Jan to look at a mockup.
##
##   godot4 --path . --rendering-driver opengl3 --resolution 390x844 \
##       --script res://tools/look_survivor.gd -- --out /tmp/survivor.png [--frames 300] [--walk 1]
##
## The hero is driven through the screen's OWN gesture path (`_on_press` + `_on_drag`), so the
## floating stick that a real thumb produces is in the frame — a hand-set `_stick_vec` would
## photograph a control state that cannot happen.

var _main: Node = null
var _out := "/tmp/survivor.png"
var _frames_to_run := 300
var _walk := true
## How long the thumb holds the stick. The rest of the frames are STOOD STILL, so the monsters
## close in and the auto-attack actually fires — a shot taken while running away from everything
## shows an empty arena and no fight.
var _walk_frames := 130
## Keep the thumb DOWN at capture time, so the floating stick is in the frame. The control is
## half of what this slice is; a shot without it photographs a game with no controls.
var _stick := "1"
## Wait for a blow to be LANDING before the shot. A screenshot of a swing that is not happening
## photographs the game as if it had no attack animation at all.
var _wait_swing := true
## Place N bodies in the hero's reach before the shot. A look-frame needs a fight IN it; waiting
## for the spawner to walk one over costs the timeout and photographs an empty field.
var _pack := 5

var _screen = null
var _started := false
var _frames := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--out":
				_out = args[i + 1]
			"--frames":
				_frames_to_run = int(args[i + 1])
			"--walk":
				_walk = args[i + 1] != "0"
			"--stick":
				_stick = args[i + 1]
			"--swing":
				_wait_swing = args[i + 1] != "0"
			"--pack":
				_pack = int(args[i + 1])
		i += 2
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		# `_nav_bar` is the last cheap marker of "main is fully built" — the same gate
		# capture_screen.gd uses, because entering a screen before that gets overwritten.
		if not _main._screens.has("survivor") or _main._nav_bar == null:
			return false
		_started = true
		_main._enter_survivor(0)
		_screen = _main._screens["survivor"]
		if _pack > 0 and _screen.run != null:
			var run = _screen.run
			run.monsters.clear()
			for i in _pack:
				run._spawn_one()
				var ang := TAU * float(i) / float(_pack) + 0.4
				run.monsters[i]["pos"] = run.player_pos + Vector2(cos(ang), sin(ang)) * 105.0
		return false

	if _screen == null:
		return false
	if _frames == 4 and _walk:
		_screen._on_press(Vector2(110, 660))
		_screen._on_drag(Vector2(150, 610))
	if _frames == 4 + _walk_frames and _walk and _stick == "0":
		_screen._on_release()
	if _frames == _frames_to_run - 3 and _walk and _stick == "1":
		_screen._on_drag(Vector2(150, 614))
	_frames += 1
	if _frames < _frames_to_run:
		return false
	if _wait_swing and _screen.run != null:
		var age: float = _screen.run.swing_age
		if age < 0.0 or age > 0.07:
			_frames -= 1
			return false
	_capture()
	return false


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(_out)
	var run = _screen.run
	print("look_survivor: %s %dx%d kills=%d drops=%d alive=%d hp=%d/%d wave=%d t=%.1f"
		% [_out, img.get_width(), img.get_height(), run.kills, run.drops.size(),
			run.monsters.size(), run.hp, run.max_hp, run.wave, run.elapsed])
	quit(0)
