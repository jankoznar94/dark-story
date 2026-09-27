extends SceneTree
## Does a SWING actually make a sound? `test_sfx.gd` pins the decision layer (which cue each
## event raises, which file it resolves to) headlessly, where there is no audio device at all
## — so it deliberately cannot answer whether anything is audible.
##
## This drives the REAL `main.gd`, walks the REAL route into the arena (`_on_stop_selected`),
## and measures the mixer's own `AudioStreamPlayer` after the fight has swung: the stream's
## `get_playback_position()`, which only moves if the engine is feeding samples to a device.
##
##   godot4 --rendering-driver opengl3 --path . --script res://tools/probe_sfx_playback.gd
##
## `--headless` cannot be used: the dummy audio driver accepts a `play()` and never advances
## the position, so a headless "it advanced" is never true and a headless "it did not" says
## nothing at all.
##
## ⚠️  The route into a fight goes through the TRANSITION overlay, which holds for a fixed
## 1800 ms of REAL time (`TransitionScreen.HOLD_MS`) and only then calls `_enter_arena`. A
## frame COUNT is therefore not a waiting strategy: this box renders the empty port at
## ~180 fps, so 240 frames is ~1.3 s and the arena does not exist yet. An earlier version of
## this probe quit at 240 frames and reported "the fight played NO cue at all" about a fight
## that had never started — the count was measuring the engine's frame rate, not the game's
## state. Wait for `arena.battle != null`, with a generous ceiling, and only then count.
##
## The engine pumps the arena's `_process` itself (the arena is a visible child of the real
## `main`), so this probe must NOT call `_process` by hand as well — that would double-pump
## every tick and halve the measured swing intervals.

const MAX_WAIT_FRAMES := 2400
const MEASURE_FRAMES := 600

var _main: Node = null
var _started := false
var _frames := 0
var _battle_frame := -1


func _initialize() -> void:
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		if _main._nav_bar == null:
			return false
		# The real route into a fight, not a hand-built arena: the screen's own `_process`
		# is what drains the cues, and a probe that calls `battle.player_attack` directly
		# would be measuring the battle and not the wiring.
		_main._on_stop_selected(0, 0)
		_started = true
		return false

	_frames += 1
	var arena = _main._screens.get("arena")
	if arena == null:
		return _frames > MAX_WAIT_FRAMES
	if arena.battle == null:
		# The transition is still holding. Not a failure — but if it never ends, say so
		# instead of quietly reporting an empty fight.
		if _frames > MAX_WAIT_FRAMES:
			print("PROBE: the fight never started in %d frames (transition stuck?)" % _frames)
			quit()
			return true
		return false

	if _battle_frame < 0:
		_battle_frame = _frames
	# A few seconds of real fight: enough for several swings on both sides.
	if _frames - _battle_frame < MEASURE_FRAMES:
		return false

	var mixer = arena._sfx
	print("device=%s mix_rate=%d" % [AudioServer.get_driver_name(),
		AudioServer.get_mix_rate()])
	if mixer == null:
		print("PROBE: the arena screen has NO mixer at all")
		quit()
		return true
	var playing := 0
	var longest := 0.0
	var stream_name := ""
	for child in mixer.get_children():
		var p := child as AudioStreamPlayer
		if p == null:
			continue
		if p.playing and not p.stream_paused:
			playing += 1
			var pos := p.get_playback_position()
			if pos > longest:
				longest = pos
				stream_name = p.stream.resource_path if p.stream else ""
	# A device consumed a sample if ANY player that is `playing` has a non-zero position, so
	# `longest` alone is not the test: a cue that just started is legitimately at 0.0. Ask
	# the mixer what it played and the audio server whether it is really mixing.
	var mix_active: bool = AudioServer.get_time_to_next_mix() > 0.0 or mixer.played_count > 0
	print("fight ticks=%d hero_hp=%.0f enemy_hp=%.0f ended=%s"
		% [arena.battle.ticks_elapsed, arena.battle.hero_hp, arena.battle.enemy_hp,
			str(arena.battle.ended)])
	print("last_cue=%s cues_played=%d players=%d"
		% [mixer.last_cue, mixer.played_count, mixer.get_child_count()])
	print("playing_now=%d longest_position=%.3f stream=%s mix_active=%s"
		% [playing, longest, stream_name, str(mix_active)])
	if mixer.played_count == 0:
		print("PROBE: the fight played NO cue at all")
	elif not mix_active:
		print("PROBE: cues were raised but the driver reports no mixing at all")
	elif playing == 0:
		print("PROBE: %d cues were played, but every player has already finished — the "
			% mixer.played_count + "fight is audible but this instant is silent (re-run with "
			+ "a shorter measure window to catch one mid-flight)")
	else:
		print("PROBE: the combat sound is really playing (%d players live, position %.3f)"
			% [playing, longest])
	quit()
	return true
