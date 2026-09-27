extends SceneTree
## tools/test_portal_return.gd — Jan's rule for leaving a fight, both halves.
##
##   * a Town Portal SCROLL returns the player to the exact fight he left, and it is SPENT
##     doing so;
##   * walking to town costs the zone's progress, so the scroll is worth carrying.
##
## Why this is its own file rather than a case in `test_arena_pacing.gd`: the wiring lives on
## `main.gd` (`arena.portal_requested` -> `_on_result_portal`, and `_on_town_portal` /
## `_on_walk_to_town`), and main is NOT built during a `SceneTree` script's `_initialize()` —
## the tree does not exist yet. A test that ran there would have to skip, and a skipped test
## that prints PASS is worse than no test. So this one waits in `_process` for main to be built
## and then runs once, the same shape `test_transition.gd` uses.
##
## Run:  godot --headless --path . --script res://tools/test_portal_return.gd
## Pass: prints PORTAL_RETURN_ALL_PASS=true and exits 0.

const Main := preload("res://scripts/main.gd")

## ⚠️  THE SAVE IS GLOBAL STATE AND IT IS SHARED WITH THE PLAYER'S OWN GAME.
##
## `main.gd` resumes `user://…/dungeon_recall_save.json` on boot, so this test used to measure
## whatever the PREVIOUS RUN left behind: with `townPortalReturn` already populated, the portal
## tile never spent a second scroll and the run reported "the portal did not spend a scroll
## (2 -> 2)" on every other invocation — a flaky verdict, which is worse than a red one.
##
## So the test owns the save for its duration: it reads the real file, runs against a FRESH
## game, and puts the real one back. If a run is killed mid-test the player's save is left as a
## new game, which is said out loud in the summary rather than hidden.
var _saved_bytes: PackedByteArray = PackedByteArray()
var _had_save := false

var _main: Node = null
var _started := false
var _failures: Array[String] = []


func _initialize() -> void:
	_stash_save()
	_main = Main.new()
	root.add_child(_main)


func _save_path() -> String:
	return "user://dungeon_recall_save.json"


func _stash_save() -> void:
	_had_save = FileAccess.file_exists(_save_path())
	if _had_save:
		var f := FileAccess.open(_save_path(), FileAccess.READ)
		if f != null:
			_saved_bytes = f.get_buffer(f.get_length())
	# A FRESH game: no save file at all, so `load_from_disk()` fails and main seeds a new one.
	if _had_save:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_path()))


func _restore_save() -> void:
	if not _had_save:
		# There was nothing to keep; drop what the test wrote so the next run is clean too.
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_path()))
		return
	var f := FileAccess.open(_save_path(), FileAccess.WRITE)
	if f != null:
		f.store_buffer(_saved_bytes)


func _process(_delta: float) -> bool:
	if not _started:
		if _main._nav_bar == null or not _main._screens.has("arena") or _main.state == null:
			return false
		_started = true
		_run()
		for f in _failures:
			print("  FAIL: %s" % f)
		if _failures.is_empty():
			print("PORTAL_RETURN_ALL_PASS=true")
		else:
			print("PORTAL_RETURN_ALL_PASS=false")
		_restore_save()
		quit(0 if _failures.is_empty() else 1)
		return true
	return false


func _fail(msg: String) -> void:
	_failures.append(msg)


## Put the save at a known place: zone 2, fight 6 of 10, two scrolls carried. Deep into the
## zone on purpose — "returns to the fight it left" (6) and "restarts the zone" (0) are then
## different numbers and no assertion can pass by accident.
const ZONE := 2
const FIGHT := 6


func _seed() -> void:
	_main.state.data["locationProgress"][0] = ZONE
	_main.state.data["areaFightProgress"][0] = FIGHT
	_main.state.data["townPortalCount"] = 2
	_main.state.data["townPortalReturn"] = null
	# A new game seeds the first class; the hero needs one for the pools and the weapon rules.
	if str(_main.state.data.get("heroClass", "")) == "":
		_main.state.set_class("barbarian")


func _run() -> void:
	var arena = _main._screens["arena"]

	# --- the scroll: spent on the way out, position stored ---------------------------------
	_seed()
	var before := int(_main.state.data["townPortalCount"])
	# Entering a stop is what RESETS the zone's fight counter (the player walked in, so the
	# zone starts again) — so the fight index has to be written AFTER the entry, not by the
	# seed. Doing it the other way round is what made this read 0/10.
	_main._on_stop_selected(0, ZONE)
	_drive_transition()
	_main.state.data["locationProgress"][0] = ZONE
	_main.state.data["areaFightProgress"][0] = FIGHT
	if not _enter_arena_now():
		_drive_transition()
	if arena.battle == null:
		_fail("the arena never started, so the portal could not be tested")
		return
	arena.battle.progress = ZONE
	# The fight index has to be set up the way the SAVE carries it, because killing the enemy
	# runs the win path which does `fight_progress[act] = fight + 1` (battle.gd's `_finish`).
	# Seeding the kill counter at FIGHT would have the portal store FIGHT + 1 — which is the
	# fight the player has NOT reached yet. A player standing on fight 6 of 10 has a save
	# reading 5 fights already won.
	_main.state.data["locationProgress"][0] = ZONE
	_main.state.data["areaFightProgress"][0] = FIGHT - 1
	# The page's tile is armed against the tap that delivered the kill; a test has no frames
	# between the two, so the lock is cleared and the WIRING is what is under test (the lock
	# itself is covered in `test_arena_pacing`, where frames exist).
	arena._button_lock_ms = 0.0

	var stored: Variant = _main.state.data.get("townPortalReturn")
	if stored != null:
		_fail("a return position existed before the portal was used")
		return

	# Drive the tile the way a tap does: the tile's own handler, which emits
	# `portal_requested` into main's connection.
	# The result page is built when the fight SETTLES (`_finish_fight`), and it is that call
	# which decides whether the Portal tile exists — a scroll carried is the condition. Kill
	# through the rules so the win, the loot roll and the page are all real.
	arena.battle.enemy_hp = 0.0
	arena.battle.gap = 0.0
	var guard := 0
	while not arena.battle.ended and guard < 300:
		arena.step()
		guard += 1
	if not arena.battle.ended:
		_fail("the fight never settled, so the result page was never built")
		return
	arena._button_lock_ms = 0.0
	var tiles: Array = _action_labels(arena)
	if not tiles.has("Portal"):
		_fail("the result page offers no Portal tile while a scroll is carried (tiles: %s)"
			% str(tiles))
		return
	# ⚠️  Read the count HERE, not before the kill. A WON fight can DROP a town portal scroll
	# (`battle.gd`'s loot roll routes a `townPortalScroll` to `portals`), so the count is not a
	# clean baseline across the fight — measuring from before it made this assertion fail on
	# every other run depending on one loot roll. The tile is what spends a scroll; that is
	# the transition to measure.
	var before_spend := int(_main.state.data["townPortalCount"])
	if before_spend <= 0:
		_fail("test setup: no scroll to spend after the fight (the tile should not be offered)")
		return
	arena._on_portal_pressed()
	stored = _main.state.data.get("townPortalReturn")
	if stored == null:
		_fail("the Portal tile did not store a return position - the scroll would be lost")
		return
	var p: Dictionary = stored
	# The stored position is the fight the player is ON, i.e. the one after the kill he just
	# made: seeded at FIGHT - 1 wins, so the portal must store FIGHT.
	if int(p.get("zoneId", -1)) != ZONE or int(p.get("areaFight", -1)) != FIGHT:
		_fail("the portal stored the wrong fight: zone %s fight %s, wanted %d/%d"
			% [str(p.get("zoneId")), str(p.get("areaFight")), ZONE, FIGHT])
		return
	if int(_main.state.data["townPortalCount"]) != before_spend - 1:
		_fail("the portal did not spend a scroll (%d -> %d)"
			% [before_spend, int(_main.state.data["townPortalCount"])])
		return
	# Storing a position must not itself move the player.
	if int(_main.state.data["areaFightProgress"][0]) != FIGHT:
		_fail("using the portal moved the save before the player returned")
		return

	# --- coming back restores exactly that fight ------------------------------------------
	# ⚠️  The save must be MOVED AWAY from the stored position first, or this assertion cannot
	# fail: verified by mutation, removing the restore left the test green because the kill
	# had already written the very number the restore writes. The realistic way it moves is
	# the player walking to town instead of portalling (which resets the zone's fights), so
	# that is the state the return has to rescue him from.
	_main._on_walk_to_town()
	if int(_main.state.data["areaFightProgress"][0]) != 0:
		_fail("test setup: walking to town should have reset the zone, it is at %d"
			% int(_main.state.data["areaFightProgress"][0]))
		return
	if _main.state.data.get("townPortalReturn") == null:
		_fail("walking to town destroyed the stored return position - the scroll is wasted")
		return
	_main._on_town_portal()
	if int(_main.state.data["areaFightProgress"][0]) != FIGHT \
			or int(_main.state.data["locationProgress"][0]) != ZONE:
		_fail("the return did not restore the fight: zone %d fight %d, wanted %d/%d"
			% [int(_main.state.data["locationProgress"][0]),
				int(_main.state.data["areaFightProgress"][0]), ZONE, FIGHT])
		return
	if _main.state.data.get("townPortalReturn") != null:
		_fail("the return position survived the return - the town's portal card stays up forever")
		return

	# --- and walking costs the zone's progress, so the two ways out differ ------------------
	_seed()
	_main._on_walk_to_town()
	if int(_main.state.data["areaFightProgress"][0]) != 0:
		_fail("walking to town kept the zone progress (%d) - the scroll would be pointless"
			% int(_main.state.data["areaFightProgress"][0]))
		return
	if int(_main.state.data["locationProgress"][0]) != ZONE:
		_fail("walking to town moved the ZONE - it must only reset the fights inside it")


## `_enter_arena` builds the arena through the transition's callback, and one step past the
## hold runs it. Returns false when the arena is not there yet.
func _enter_arena_now() -> bool:
	return _main._screens.has("arena") and _main._screens["arena"].battle != null


## The transition is an 1800 ms overlay and the arena is built by its CALLBACK, so a caller
## that does not drive it forward gets an arena whose `battle` is still null. One step past the
## hold is exactly what 1.8 s of frames would do.
func _drive_transition() -> void:
	var tr = _main._transition
	if tr != null and tr.is_transitioning():
		tr._process(tr.HOLD_MS / 1000.0 + 0.01)


## The tiles' own labels, so the assertion is about what the page OFFERS rather than about a
## named field that could survive a rebuild.
func _action_labels(screen) -> Array:
	var out: Array = []
	var holder = screen._result_actions
	if holder == null:
		return out
	for child in holder.get_children():
		out.append(str(child.get_meta("label", "<no-label>")))
	return out
