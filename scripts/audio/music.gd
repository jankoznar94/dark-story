extends Node
class_name Music
## Music — the PWA's `switchBGM` / `toggleMusic` / `duckBgm`, in one place.
##
## Source: `game.ts`'s `switchBGM(mode)` plus the `const …Audio = new Audio(…)` block.
## The PWA plays SIX modes, each with its own volume, and only some of them loop:
##
## | mode      | track(s)                     | volume | loop | entered when            |
## |---|---|---|---|---|
## | battle    | `bgm_1/2/3.mp3`, random      | 0.90   | NO   | the map and the arena   |
## | boss      | `boss_bgm.mp3`               | 0.70   | yes  | a fight against a boss  |
## | overworld | `overworld.mp3`              | 1.00   | yes  | town and every other screen |
## | defeat    | `defeat.mp3`                 | 0.85   | yes  | the defeat page         |
## | win       | `win.mp3`                    | 0.90   | no   | the victory page        |
## | minigame  | `minigame-bgm.mp3`           | 0.80   | yes  | the PWA's minigames     |
##
## Three rules come straight from the PWA and each one is load-bearing:
##
##   1. **`switchBGM` RETURNS EARLY when the mode did not change.** "Hudba se nepřerušuje —
##      pokud už hraje stejný mód, necháme ji dohrát." So re-entering the town from the shop
##      does not restart the track from zero, and this is why the mode is not re-`play()`ed
##      per screen.
##   2. **The BATTLE tracks do NOT loop.** `battleBgmTracks.forEach(t => t.loop = false)` and
##      an `ended` handler picks a random one of the three and plays it, but ONLY while the
##      mode is still `battle`. That is the "po patrech se střídají" behaviour: the fight
##      music never repeats the same track back to back by loop, it chains.
##   3. **`toggleMusic` MUTES, it does not stop.** The PWA sets every track's `volume` to 0
##      and keeps it playing, so the toggle is instant and the position is kept. The port's
##      old `_toggle_music` muted the whole Master bus instead, which would also silence
##      every SFX and is not what the PWA's button does.
##
## ⚠️  `bgm.mp3` is loaded by the PWA and **never played** — `switchBGM` has no branch for
## it. It is dead in the source, so it is not ported; the six modes below are the whole of
## what the game can sound like.
##
## ⚠️  `defeat` / `win` are entered from the PWA's `visibilitychange` handler, i.e. when the
## player comes BACK to the tab. `showScreen` deliberately does not switch on the result page
## ("Victory/Lose/boj hudbu nemění"), so a player who never backgrounds the game hears the
## battle music through the result. That is reproduced rather than "fixed": the two tracks are
## implemented and reached through `_resume_for_focus`, the same route the PWA takes.

## mode -> the track it plays. `battle` is the one mode with a pool.
const TRACKS := {
	"battle": ["res://assets/audio/bgm_1.mp3", "res://assets/audio/bgm_2.mp3",
		"res://assets/audio/bgm_3.mp3"],
	"boss": ["res://assets/audio/boss_bgm.mp3"],
	"overworld": ["res://assets/audio/overworld.mp3"],
	"defeat": ["res://assets/audio/defeat.mp3"],
	"win": ["res://assets/audio/win.mp3"],
	"minigame": ["res://assets/audio/minigame-bgm.mp3"],
}

## The PWA's own per-track volumes. A single volume per mode, not per track: all three
## battle tracks are 0.90.
const VOLUMES := {
	"battle": 0.90,
	"boss": 0.70,
	"overworld": 1.00,
	"defeat": 0.85,
	"win": 0.90,
	"minigame": 0.80,
}

## ⚠️  Every mode loops EXCEPT `battle`, whose tracks chain randomly (rule 2 above).
const LOOPS := {
	"battle": false,
	"boss": true,
	"overworld": true,
	"defeat": true,
	"win": false,
	"minigame": true,
}

## Silence in dB. `linear_to_db(0.0)` is `-inf` and some backends warn on it.
const SILENT_DB := -80.0

signal mode_changed(mode: String)

## Who to ask which mode belongs to the current screen, when music has to be restarted after
## the window lost focus. Set by `main`; a null Callable falls back to the mode that was
## playing before the pause.
var mode_provider: Callable = Callable()

var muted := false

var _player: AudioStreamPlayer
var _mode := ""
## The path being played, kept for the report and for the tests — `_player.stream` says the
## same thing but not which of the three battle tracks it was.
var _track := ""
var _battle_index := 0
## How many times the mode actually CHANGED, i.e. how many times a track was restarted.
## "Re-entering the same screen must not restart the music" is a rule, and a counter is the
## only way to assert it — `playing == true` is true either way.
var _switches := 0
var _duck_ms := 0.0
var _duck_level := 1.0
var _duck_restore := 1.0
var _paused_for_focus := false
var _mode_before_pause := ""
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "MusicPlayer"
	_player.bus = "Master"
	add_child(_player)
	_player.finished.connect(_on_track_finished)
	_rng.randomize()


## The PWA's `switchBGM(mode)`. A mode that is already playing is left alone (rule 1).
func switch_mode(mode: String) -> void:
	if mode == _mode:
		return
	if not TRACKS.has(mode):
		push_error("Music: unknown mode '%s'" % mode)
		return
	_mode = mode
	_switches += 1
	if mode == "battle":
		_battle_index = _rng.randi() % (TRACKS["battle"] as Array).size()
	_play_current()
	mode_changed.emit(_mode)


## Current mode. `""` means nothing has been asked for yet.
func mode() -> String:
	return _mode


## The file being played, as a resource path. Empty before the first `switch_mode`.
func track_path() -> String:
	return _track


func is_playing() -> bool:
	return _player != null and _player.playing and not _player.stream_paused


## The mode's own volume, before mute and before any duck — what `toggleMusic` restores.
func base_volume() -> float:
	return float(VOLUMES.get(_mode, 1.0))


## The PWA's `toggleMusic`: volume to zero, the stream keeps its position.
func set_muted(value: bool) -> void:
	muted = value
	_apply_volume()


func _play_current() -> void:
	var pool: Array = TRACKS.get(_mode, [])
	if pool.is_empty():
		return
	var path := str(pool[_battle_index % pool.size()])
	var stream: AudioStream = load(path)
	if stream == null:
		push_error("Music: could not load %s" % path)
		return
	# Set on every play rather than trusting the import: `load()` hands out the CACHED
	# resource, so a loop flag written once would leak into every later use of that file.
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = bool(LOOPS.get(_mode, false))
	_track = path
	_player.stream = stream
	_apply_volume()
	_player.play()


## The PWA's `ended` handler on the battle tracks, plus its loop=false on `win`.
##
## ⚠️  The chain is guarded by the MODE, not by the track that ended: a battle track that
## finishes just after the player entered town must not start the next battle track over the
## overworld music.
func _on_track_finished() -> void:
	if _mode != "battle":
		return
	_battle_index = _rng.randi() % (TRACKS["battle"] as Array).size()
	_play_current()


## Which battle track would come next. Exposed so a test can pin the RANGE without pinning
## the random value (the PWA picks any of the three, repeats included).
func next_battle_index() -> int:
	return _rng.randi() % (TRACKS["battle"] as Array).size()


## The PWA's `duckBgm(level, duration)` — the level-up fanfare drops the music to 30 % for
## 750 ms and then restores it. `_duck_restore` is captured on the way in and only written
## back if the volume has not been changed in the meantime, exactly as the PWA guards it.
func duck(level: float, duration_ms: float) -> void:
	_duck_level = level
	_duck_restore = base_volume()
	_duck_ms = duration_ms
	_apply_volume()


## The duck's clock. Its own function so a test can advance it deterministically instead of
## depending on how many frames the harness happened to run.
func _tick_duck(delta_ms: float) -> void:
	if _duck_ms <= 0.0:
		return
	_duck_ms -= delta_ms
	if _duck_ms > 0.0:
		return
	_duck_ms = 0.0
	# "Vrátit jen pokud se mezitím hlasitost nemění" — a mode switch during the duck must not
	# be overwritten by the restore.
	if is_equal_approx(base_volume(), _duck_restore):
		_duck_restore = base_volume()
	_apply_volume()


func _apply_volume() -> void:
	if _player == null:
		return
	var level := base_volume()
	if _duck_ms > 0.0:
		level = minf(level, _duck_level)
	if muted:
		level = 0.0
	_player.volume_db = SILENT_DB if level <= 0.0 else linear_to_db(level)


func _process(delta: float) -> void:
	_tick_duck(delta * 1000.0)


## The PWA's `visibilitychange` handler, both halves. Hiding the tab pauses the music and
## clears the mode ("currentBGM = null"), and coming back re-enters it — which is the ONLY
## route by which `defeat` and `win` are ever reached, so it is a real feature and not
## decoration.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_pause_for_focus()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_resume_for_focus()


func _pause_for_focus() -> void:
	if _player == null or _paused_for_focus:
		return
	_paused_for_focus = true
	_mode_before_pause = _mode
	_player.stream_paused = true
	# `currentBGM = null` — so the resume always re-enters the mode rather than short-circuiting.
	_mode = ""


func _resume_for_focus() -> void:
	if not _paused_for_focus:
		return
	_paused_for_focus = false
	if _player != null:
		_player.stream_paused = false
	var target := _mode_before_pause
	if mode_provider.is_valid():
		target = str(mode_provider.call())
	if target == "":
		target = "overworld"
	switch_mode(target)
