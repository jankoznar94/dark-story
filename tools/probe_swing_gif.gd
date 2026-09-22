extends SceneTree
## tools/probe_swing_gif.gd — shoot the real arena frame by frame, so the swing can be SEEN.
##
## Jan's report was visual ("the swing is not smooth, it stutters"), so the evidence for the
## fix has to be visual too. This boots the real `main.gd`, enters a fight through the real
## route, then steps the fight in controlled 16.7 ms frames and writes one PNG per frame.
##
## The frames go to /tmp so the repository does not carry a hundred throwaway images:
##
##   godot --rendering-driver opengl3 --path . --script res://tools/probe_swing_gif.gd -- \
##       --out /tmp/swing --frames 90 --per-swing 1
##
## Two knobs matter:
##   --frames      how many PNGs to write
##   --hold-gap    keep the fight at maximum separation so the WALK-IN is the thing on
##                 screen instead of a standing hero (the walk-in only lasts ~1 s per fight).

const FRAME_MS := 16.6667

var _main: Node = null
var _out := "/tmp/swing"
var _frames := 90
var _hold_gap := false
var _hold_damage := false
var _started := false
var _shot := 0
var _last_usec := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--out":
				_out = args[i + 1]
			"--frames":
				_frames = int(args[i + 1])
			"--hold-gap":
				_hold_gap = true
			"--hold-damage":
				_hold_damage = true
		i += 2
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		if not _main._screens.has("town") or _main._nav_bar == null:
			return false
		_started = true
		_main._on_stop_selected(0, 0)
		var arena = _main._screens["arena"]
		arena.battle.enemy_max_hp = 1000000.0
		arena.battle.enemy_hp = arena.battle.enemy_max_hp
		arena.battle.hero_max_hp = 1000000.0
		arena.battle.hero_hp = arena.battle.hero_max_hp
		if _hold_gap:
			arena.battle.gap = 1.0
		_shoot()
		return false

	if _hold_gap:
		# Pinned so the approach is what the frames show, not a finished walk-in.
		_main._screens["arena"].battle.gap = 1.0
	if _hold_damage:
		# Half HP every frame: the ghost ring has a trail to draw on every one of them.
		var arena = _main._screens["arena"]
		arena.battle.enemy_hp = arena.battle.enemy_max_hp * 0.5

	# A controlled frame, not the loop's own `delta`: the captured sequence has to advance by
	# exactly one 60 Hz frame per PNG or the resulting GIF would not play back at the speed
	# the player sees.
	_main._screens["arena"]._process(FRAME_MS / 1000.0)
	_shoot()
	return false


func _shoot() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png("%s_%03d.png" % [_out, _shot])
	_shot += 1
	if _shot >= _frames:
		print("wrote %d frames to %s_*.png" % [_shot, _out])
		quit(0)
