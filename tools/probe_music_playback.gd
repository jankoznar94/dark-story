extends SceneTree
## Does the music actually PLAY? `test_music.gd` pins the state (mode, file, volume, loop
## flag) headlessly, where there is no audio device at all — so it deliberately cannot answer
## this. This drives the REAL `main.gd` with a real renderer and reports the stream's own
## playback position, which only moves if the engine is feeding samples to a device.
##
##   godot4 --rendering-driver opengl3 --path . --script res://tools/probe_music_playback.gd
##
## `--headless` cannot be used: the dummy audio driver accepts a `play()` and never advances
## `get_playback_position()`, so a headless "it advanced" is never true and a headless
## "it did not advance" says nothing.

var _main: Node = null
var _started := false
var _frames := 0


func _initialize() -> void:
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		if _main._music == null or _main._nav_bar == null:
			return false
		_started = true
		return false

	_frames += 1
	# A second of real frames is enough for a device to have consumed some samples.
	if _frames < 90:
		return false
	var music = _main._music
	var player: AudioStreamPlayer = music._player
	print("device=%s mix_rate=%d" % [AudioServer.get_driver_name(),
		AudioServer.get_mix_rate()])
	print("mode=%s track=%s playing=%s paused=%s volume_db=%.2f"
		% [music.mode(), music.track_path(), str(player.playing),
			str(player.stream_paused), player.volume_db])
	print("playback_position=%.3f stream_length=%.3f"
		% [player.get_playback_position(), (player.stream.get_length() if player.stream else 0.0)])
	if not player.playing:
		print("PROBE: the stream is NOT playing")
	elif player.get_playback_position() <= 0.0:
		print("PROBE: playing but the position never advanced — the driver is not consuming it")
	else:
		print("PROBE: the music is really playing (position advanced)")
	quit()
	return true
