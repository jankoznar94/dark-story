extends SceneTree
## tools/test_music.gd — the BGM rules, headlessly.
##
## The port had NO audio at all: `assets/audio/` shipped 30 tracks and the only thing that
## touched them was a `_toggle_music()` that muted the Master bus. A missing feature is
## invisible to every other test, so this file pins the four things the PWA's `switchBGM`
## actually specifies, each of which can be got wrong while the game still makes noise:
##
##   1. **`switchBGM` RETURNS EARLY on an unchanged mode.** Re-entering the town from the
##      shop must NOT restart the track. Asserted with a SWITCH COUNTER, not with
##      `playing == true` — a restart also leaves it playing, so the flag cannot see this.
##   2. **The battle collection does NOT loop; everything else does.** The PWA sets
##      `loop = false` on all three battle tracks and chains them from an `ended` handler.
##      A looped battle track is a track that repeats instead of handing over.
##   3. **The mode is derived from the SCREEN, and the map is `battle`.** The PWA's
##      `showScreen` gives the wilderness the battle music and excludes the arena and the
##      result page from any switch of its own. Driven through `show_screen`, the real route.
##   4. **The duck restores the mode's OWN volume and does not restart the track.** The
##      level-up duck is a volume change; a `play()` in there would restart the music at the
##      exact moment the player earns a level.
##
## ⚠️  A headless run has no audio device, so NOTHING here asserts that sound is audible —
## it cannot be, and a test that claimed otherwise would be lying. What is pinned is the
## STATE the music object is in: which file, which volume, which loop flag, how many
## switches. `is_playing()` is checked only where a real stream exists.

const Main := preload("res://scripts/main.gd")

var _main: Node = null
var _started := false
var _failures: Array[String] = []


func _initialize() -> void:
	_main = Main.new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		if _main._music == null or _main._nav_bar == null:
			return false
		_started = true
		_run()
		return false
	return false


func _fail(msg: String) -> void:
	_failures.append(msg)


func _run() -> void:
	var music = _main._music

	# --- 1. the boot state: the town is the overworld track -------------------------------
	# `_ready()` ends with `show_screen("town")`, so anything else here is a boot that makes
	# no sound until the player navigates.
	print("  boot: mode=%s track=%s" % [music.mode(), music.track_path()])
	if music.mode() != "overworld":
		_fail("the game boots in mode '%s', the town's is 'overworld'" % music.mode())
	if music.track_path() != "res://assets/audio/overworld.mp3":
		_fail("the town plays '%s', not overworld.mp3" % music.track_path())
	if music.track_path() != "" and load(music.track_path()) == null:
		_fail("the track the music chose does not load: %s" % music.track_path())

	# --- 2. an unchanged mode does not restart --------------------------------------------
	var switches_before: int = music._switches
	_main.show_screen("shop")
	_main.show_screen("town")
	_main.show_screen("craft")
	_main.show_screen("town")
	print("  shop/craft/town round trip: switches %d -> %d" % [switches_before, music._switches])
	if music._switches != switches_before:
		_fail("the shop and the craft restart the overworld music — the PWA's switchBGM returns early on an unchanged mode (switches %d -> %d)"
			% [switches_before, music._switches])

	# --- 3. the map is the BATTLE collection ----------------------------------------------
	_main.show_screen("map")
	print("  map: mode=%s track=%s" % [music.mode(), music.track_path()])
	if music.mode() != "battle":
		_fail("the map is mode '%s'; the PWA gives the wilderness switchBGM('battle')" % music.mode())
	var battle_tracks: Array = music.TRACKS["battle"]
	if not battle_tracks.has(music.track_path()):
		_fail("the map plays '%s', which is not one of the battle tracks" % music.track_path())
	# The PWA's `battleBgmTracks.forEach(t => t.loop = false)`.
	var battle_stream = load(music.track_path())
	if battle_stream is AudioStreamMP3 and (battle_stream as AudioStreamMP3).loop:
		_fail("the battle track %s has loop=true — the PWA chains the three tracks from an `ended` handler instead of looping one"
			% music.track_path())

	# --- 4. the boss mode, and the arena keeping its own music -----------------------------
	_main.show_screen("town")
	_main._on_stop_selected(0, 0)
	print("  arena (stop 0/0): mode=%s track=%s" % [music.mode(), music.track_path()])
	if music.mode() != "battle":
		_fail("entering a normal fight gave mode '%s', not 'battle'" % music.mode())
	if not battle_tracks.has(music.track_path()):
		_fail("a normal fight plays '%s', which is not one of the battle tracks" % music.track_path())

	# The boss: the PWA's own `if (mb.isBoss) switchBGM('boss')`. A boss zone is the act's
	# LAST zone (`progress >= zones - 1`), so rather than fighting through nine zones the
	# state is moved there through `set_progress` and the fight is entered on the real route.
	var arena = _main._screens["arena"]
	var zones: int = _main.data.act_by_id(0).get("zones", 10)
	_main.state.set_progress(0, zones - 1)
	_main._on_stop_selected(0, zones - 1)
	print("  boss zone %d/%d: is_boss=%s mode=%s track=%s"
		% [zones - 1, zones, str(arena.battle.is_boss), music.mode(), music.track_path()])
	if arena.battle == null or not arena.battle.is_boss:
		_fail("the act's last zone (%d of %d) did not start a boss fight" % [zones - 1, zones])
	elif music.mode() != "boss":
		_fail("a boss fight is mode '%s', not 'boss' — the PWA switches to the boss track for it"
			% music.mode())
	elif music.track_path() != "res://assets/audio/boss_bgm.mp3":
		_fail("a boss fight plays '%s', not boss_bgm.mp3" % music.track_path())

	# `boss_bgm` LOOPS in the PWA (unlike the battle collection).
	var boss_stream = load("res://assets/audio/boss_bgm.mp3")
	if boss_stream is AudioStreamMP3 and not (boss_stream as AudioStreamMP3).loop:
		_fail("boss_bgm.mp3 has loop=false — the PWA loops the boss track")

	# --- 5. the duck: volume down, position kept, volume restored -------------------------
	# Driven through `_tick_duck` rather than through frames, so the numbers do not depend on
	# how many frames the harness happened to run.
	_main.show_screen("town")
	music._duck_ms = 0.0
	var base: float = music.base_volume()
	music.duck(0.3, 750.0)
	var ducked: float = music._duck_level
	print("  duck: base %.2f -> %.2f" % [base, ducked])
	if not is_equal_approx(base, 1.0):
		_fail("the overworld's base volume is %.2f; the PWA's is 1.00" % base)
	if not is_equal_approx(ducked, 0.3):
		_fail("duck(0.3) stored %.2f" % ducked)
	music._tick_duck(400.0)
	if music._duck_ms <= 0.0:
		_fail("the duck ended after 400 of its 750 ms")
	music._tick_duck(400.0)
	if music._duck_ms > 0.0:
		_fail("the duck is still running after 800 of its 750 ms (%.0f left)" % music._duck_ms)
	if music.mode() != "overworld":
		_fail("the duck changed the mode to '%s' — a duck is a volume change, not a re-entry"
			% music.mode())

	# And the duck must NOT have restarted the track: a level-up that restarts the music is
	# the failure this pins.
	var switches_at_duck: int = music._switches
	var hero_level_before: int = int(_main.state.hero()["level"])
	_main._on_levelled_up(hero_level_before + 1)
	if music._switches != switches_at_duck:
		_fail("a level-up restarted the music (switches %d -> %d)" % [switches_at_duck, music._switches])
	if music._duck_ms <= 0.0:
		_fail("a level-up did not duck the music at all")

	# --- 6. the mute toggle is a volume, not a stop ---------------------------------------
	music._tick_duck(1000.0)
	music.set_muted(true)
	if not music.muted:
		_fail("set_muted(true) did not set the flag")
	music.set_muted(false)
	if music.muted:
		_fail("set_muted(false) left the flag set")
	# `toggleMusic` must not be able to silence the game permanently through the Master bus:
	# the port used `AudioServer.set_bus_mute`, which also mutes every SFX.
	if AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")):
		_fail("the Master bus is muted — the music toggle must only touch the music's own volume")

	# --- 7. the nav button reaches the same place -----------------------------------------
	var before_toggle: bool = music.muted
	_main._on_nav_selected("music")
	if music.muted == before_toggle:
		_fail("the nav bar's Hudba entry did not toggle the music")
	_main._on_nav_selected("music")
	if music.muted != before_toggle:
		_fail("tapping Hudba twice did not return the mute flag to where it started")

	# --- 8. every mode the PWA has is implemented and its file loads ----------------------
	for mode in music.TRACKS:
		for path in music.TRACKS[mode]:
			if load(path) == null:
				_fail("mode '%s' points at %s, which does not load" % [mode, path])
	for mode in ["battle", "boss", "overworld", "defeat", "win", "minigame"]:
		if not music.TRACKS.has(mode):
			_fail("the PWA's mode '%s' has no track here" % mode)
		if not music.VOLUMES.has(mode):
			_fail("mode '%s' has no volume — the PWA sets one per mode" % mode)
		if not music.LOOPS.has(mode):
			_fail("mode '%s' has no loop flag" % mode)
	print("  modes implemented: %d" % music.TRACKS.size())

	# --- 9. the result page's two tracks are reachable ------------------------------------
	# They are entered from the PWA's `visibilitychange` handler, so the route under test is
	# `_music_mode_for_current_screen` with the result page up — that is the only thing that
	# decides between them.
	#
	# ⚠️  `_current` is set to "result" by hand here. The battle's own `won` flag is NOT read
	# to decide this — `_show_result_page` does that — and nothing else moves the route, so a
	# test that skipped this line would measure `arena` and report the battle track as a wrong
	# answer about a route that was never taken.
	_main._on_stop_selected(0, 0)
	var arena2 = _main._screens["arena"]
	var guard := 0
	if arena2.battle != null and not arena2.battle.ended:
		arena2.battle.enemy_hp = 0.0
		arena2.battle.gap = 0.0
		while (not arena2.battle.ended or not arena2._result_built) and guard < 300:
			arena2.step()
			guard += 1
	if arena2.battle == null or not arena2.battle.won:
		_fail("could not end a fight in a victory, so the victory track is untested")
	else:
		_main._current = "result"
		var win_mode: String = _main._music_mode_for_current_screen()
		print("  victory page asks for mode=%s" % win_mode)
		if win_mode != "win":
			_fail("the victory page asks for mode '%s', not 'win'" % win_mode)
		_main._current = "arena"
		if _main._music_mode_for_current_screen() != "battle":
			_fail("the arena asks for a mode that is not 'battle'")

		# The defeat half. `battle.won` decides which of the two, and a defeat is reached by
		# the hero dying — the same shape the result-page probe uses.
		_main._on_stop_selected(0, 0)
		var arena3 = _main._screens["arena"]
		if arena3.battle != null:
			arena3.battle.hero_max_hp = 1.0
			arena3.battle.hero_hp = 1.0
			arena3.battle.gap = 0.0
			guard = 0
			while (not arena3.battle.ended or not arena3._result_built) and guard < 600:
				arena3.step()
				guard += 1
		if arena3.battle != null and not arena3.battle.won:
			_main._current = "result"
			var lose_mode: String = _main._music_mode_for_current_screen()
			print("  defeat page asks for mode=%s" % lose_mode)
			if lose_mode != "defeat":
				_fail("the defeat page asks for mode '%s', not 'defeat'" % lose_mode)
		else:
			_fail("could not end a fight in a defeat, so the defeat track is untested")

	# --- 10. hiding the tab pauses, coming back RE-ENTERS from the screen -----------------
	# This is the ONLY route by which `defeat` and `win` are ever reached in the PWA, so the
	# resume must ASK the screen rather than replay the mode that was paused — the PWA's
	# `visibilitychange` re-derives it (`if (isDefeat) … else if (isWin) …`).
	_main.show_screen("town")
	music.switch_mode("overworld")
	var switches_before_focus: int = music._switches
	music._pause_for_focus()
	if not music._paused_for_focus:
		_fail("hiding the tab did not pause the music")
	if music.mode() != "":
		_fail("hiding the tab left the mode as '%s'; the PWA clears `currentBGM` so the resume always re-enters"
			% music.mode())
	# While paused, move the game somewhere else — which is exactly the case the re-derivation
	# exists for: the player backgrounds the tab in town and returns to a boss fight.
	_main.state.set_progress(0, _main.data.act_by_id(0).get("zones", 10) - 1)
	_main._on_stop_selected(0, _main.data.act_by_id(0).get("zones", 10) - 1)
	music._resume_for_focus()
	print("  after focus resume on a boss screen: mode=%s track=%s" % [music.mode(), music.track_path()])
	if music.mode() != "boss":
		_fail("coming back from a hidden tab resumed mode '%s'; the screen is a boss fight, so the resume must ask the screen for 'boss' (the PWA re-derives it on visibilitychange)"
			% music.mode())
	if not music._paused_for_focus == false:
		_fail("the resume left the paused flag set")
	if music._switches != switches_before_focus + 1:
		_fail("the focus resume switched %d times, expected exactly one"
			% (music._switches - switches_before_focus))

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("MUSIC_ALL_PASS=true")
	else:
		print("MUSIC_ALL_PASS=false")
	quit(0 if _failures.is_empty() else 1)
