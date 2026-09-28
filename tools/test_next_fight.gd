extends SceneTree
## tools/test_next_fight.gd — "Další souboj" must WALK, not fight behind the road.
##
## Jan: "Když na vítězné obrazovce hráč klikne na Další souboj, tak ho hra přesměruje na mapu a
## na pozadí zároveň rovnou odstartuje souboj. Hráč tedy vidí cestu, ale slyšíš zvuky souboje."
##
## Two separate defects, and each gets its own assertion because each can come back alone:
##
##   1. THE ARENA STARTED THE NEXT FIGHT. `ArenaScreen.another_fight()` advanced the stop and then
##      called its own `start()` — so the tile did two things at once: it put the player on the
##      road AND began a fight he could not see. The port already has the rule that a fight begins
##      on a station's own tap; the tile must only settle the stop.
##
##      ⚠️  Asserted on the BATTLE, not on `battle != null`: a fresh fight from the bug is a live
##      battle object in exactly the same field. `ended` is the difference between "the fight that
##      just finished" and "a fight that is running".
##
##   2. A HIDDEN SCREEN KEPT TICKING AND KEPT SPEAKING. `ArenaScreen._process` had no visibility
##      guard, so a live battle behind another screen went on swinging and its cues kept reaching
##      the mixer. This half is asserted with the mixer's own PLAY COUNT, which is the thing Jan
##      actually perceived — a rule still ticking would be invisible, a noise is not.
##
## Run:  godot --headless --path . --script res://tools/test_next_fight.gd
## Pass: prints NEXT_FIGHT_ALL_PASS=true and exits 0.

const Main := preload("res://scripts/main.gd")

## The stop's fight counter after the kill. A fresh stop entered through the map is 0, the win
## makes it 1, and the tile's `advance_stop` must not move it again (10/10 is the zone rollover,
## which is a different branch and is covered in `test_arena_pacing`).
const SEEDED_FIGHT := 0

var _main: Node = null
var _started := false
var _failures: Array[String] = []


func _initialize() -> void:
	_main = Main.new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		if _main._nav_bar == null or _main.state == null or not _main._screens.has("arena"):
			return false
		_started = true
		_run()
		for f in _failures:
			print("  FAIL: %s" % f)
		print("NEXT_FIGHT_ALL_PASS=%s" % ("true" if _failures.is_empty() else "false"))
		quit(0 if _failures.is_empty() else 1)
		return true
	return false


func _fail(msg: String) -> void:
	_failures.append(msg)


func _arena():
	return _main._screens["arena"]


func _run() -> void:
	_test_the_tile_walks_and_starts_nothing()
	_test_a_hidden_arena_does_not_tick_or_speak()


## The whole chain a tap takes: the page's tile -> `_on_next_pressed` -> `another_fight_requested`
## -> `main._on_another_fight` -> the road.
func _test_the_tile_walks_and_starts_nothing() -> void:
	_main.state.data["locationProgress"][0] = 0
	_main.state.data["areaFightProgress"][0] = SEEDED_FIGHT
	_main.state.data["_currentAct"] = 0
	_main.show_screen("town")

	var arena = _enter_fight()
	if arena == null:
		return

	# Win through the RULES, so the save, the loot and the result page are all real.
	arena.battle.enemy_hp = 0.0
	arena.battle.gap = 0.0
	var guard := 0
	while (not arena.battle.ended or not arena._result_built) and guard < 600:
		arena.step()
		guard += 1
	if not arena.battle.ended or not arena.battle.won:
		_fail("the seeded fight never ended in a win, so the tile could not be pressed")
		return

	var fight_after_win := int(_main.state.data["areaFightProgress"][0])

	# The tap guard is armed against the tap that delivered the kill; a test has no frames between
	# the two, so the lock is cleared and the WIRING is what is under test (the lock itself is
	# covered in `test_arena_pacing`, where frames exist).
	arena._button_lock_ms = 0.0
	var tile := _tile(arena, "Dalsi souboj")
	if tile == null:
		_fail("the victory page offers no \"Dalsi souboj\" tile (tiles: %s)"
			% str(_labels(arena)))
		return
	tile.emit_signal("pressed")

	# 1. The player is ON THE ROAD.
	if str(_main._current) != "world":
		_fail("the tile left the player on '%s', expected the road" % str(_main._current))
	if arena.visible:
		_fail("the arena is still visible over the road")
	# ⚠️  THE ASSERTION THE BUG FAILS: a battle that is not `ended` is a fight RUNNING behind the
	# road — the thing Jan could hear. `battle != null` cannot see this, because the bug builds a
	# real battle into the very same field.
	if arena.battle != null and not arena.battle.ended:
		_fail("a live fight was started behind the road (ended=%s, ticks=%d) — the tile must "
			% [str(arena.battle.ended), int(arena.battle.ticks_elapsed)]
			+ "settle the stop and leave the fight to the station's own tap")
	# 2. And the stop advanced by the ONE fight that was won, not by two.
	if int(_main.state.data["areaFightProgress"][0]) != fight_after_win:
		_fail("the tile moved the stop's counter from %d to %d — one win is one fight"
			% [fight_after_win, int(_main.state.data["areaFightProgress"][0])])


## Jan's own half of the symptom: "slyšíš zvuky souboje" behind the road. A hidden arena must
## neither advance the rules nor reach the mixer.
##
## Both quantities are the PLATFORM's, not the screen's: `ticks_elapsed` is the fight's game
## clock and `played_count` is how many cues the mixer actually played.
func _test_a_hidden_arena_does_not_tick_or_speak() -> void:
	_main.state.data["locationProgress"][0] = 0
	_main.state.data["areaFightProgress"][0] = 0
	var arena = _enter_fight()
	if arena == null:
		return
	if arena.visible == false:
		_fail("the arena is not visible right after entering a fight")
		return
	var sfx = arena._sfx
	if sfx == null:
		_fail("the arena built no mixer, so the sound half cannot be measured")
		return

	# The player taps the nav bar and walks away — the same move the router makes.
	_main.show_screen("town")
	if arena.visible:
		_fail("the router left the arena visible after switching to town")
		return

	var ticks_before := int(arena.battle.ticks_elapsed)
	var played_before := int(sfx.played_count)
	# Two seconds of wall time fed straight into the screen's own clock.
	for _i in 20:
		arena._process(0.1)
	if int(arena.battle.ticks_elapsed) != ticks_before:
		_fail("the hidden arena advanced the fight's clock by %d ticks — a fight nobody can see "
			% (int(arena.battle.ticks_elapsed) - ticks_before)
			+ "is still being fought")
	if int(sfx.played_count) != played_before:
		_fail("the hidden arena played %d sounds after the player left — this is the noise Jan "
			% (int(sfx.played_count) - played_before)
			+ "heard behind the road")


## Enter a fight the way a player does (a stop on the map, then the road's station), so the route
## under test is the real one. Returns the arena, or null after recording why not.
func _enter_fight():
	_main._on_stop_selected(0, 0)
	_drive_transition()
	if str(_main._current) != "world":
		_fail("a stop no longer opens the road (current='%s')" % str(_main._current))
		return null
	var world = _main._screens["world"]
	world.next_fight_requested.emit()
	_drive_transition()
	var arena = _arena()
	if arena == null or arena.battle == null:
		_fail("tapping the road did not start a fight")
		return null
	return arena


## The transition is an 1800 ms overlay whose callback builds the next screen; one step past the
## hold is exactly what 1.8 s of frames would do.
func _drive_transition() -> void:
	var tr = _main._transition
	if tr != null and tr.is_transitioning():
		tr._process(tr.HOLD_MS / 1000.0 + 0.01)


## The page's tile with `label`, as the tile factory tags it. Read off the tiles rather than off a
## named field: a named field that survives a rebuild is exactly how the port once advertised a
## fight the stop did not have.
func _tile(arena, label: String) -> Button:
	var holder = arena._result_actions
	if holder == null:
		return null
	for child in holder.get_children():
		if str(child.get_meta("label", "")) == label:
			return child as Button
	return null


func _labels(arena) -> Array:
	var out: Array = []
	var holder = arena._result_actions
	if holder == null:
		return out
	for child in holder.get_children():
		out.append(str(child.get_meta("label", "<no-label>")))
	return out
