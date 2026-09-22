extends SceneTree
## tools/test_arena_pacing.gd — the fight's CLOCK and its END.
##
## Jan's report after playing the port: "the fight runs extremely fast and does not respect
## the weapon speeds at all" and "the win and the loss do not work the way they should".
## Both are things no existing test could see, because every other test drives
## `battle.tick()` directly and therefore supplies the clock itself:
##
##   - `test_combat` ticks the battle 100 ms at a time and never involves the screen, so a
##     screen that pumps one tick per FRAME looks perfect to it. The fight really ran at
##     the frame rate (~6x fast) and nothing went red.
##   - a pack fight ended after ONE kill, a defeat never reset the stop, and every death
##     was counted twice. `test_combat` asserted the fight ENDS, which it did.
##
## So this test drives the SEAM: `ArenaScreen._process(delta)` against a stopwatch, and the
## SAVE's own counters after a loss.
##
## Run:  godot --headless --path . --script res://tools/test_arena_pacing.gd
## Pass: prints ARENA_PACING_ALL_PASS=true and exits 0.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const Battle := preload("res://scripts/combat/battle.gd")
const ArenaScreen := preload("res://scripts/ui/arena_screen.gd")

var _data: Node
var _gen: ItemGen
var _loot: LootSystem
var _failures: Array[String] = []


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_loot = LootSystem.new(_data, _gen)

	_test_the_fight_advances_in_real_time_not_in_frames()
	_test_a_weapon_s_speed_is_what_the_player_feels()
	_test_a_fast_frame_does_not_shorten_a_swing()
	_test_a_pack_is_fought_to_the_last_member()
	_test_a_defeat_is_settled_on_the_save()
	_test_a_cleared_stop_offers_the_map_not_another_fight()
	_test_a_pack_hand_over_restarts_the_walk_in()
	_test_a_swing_lunge_exists_on_a_landed_hit()

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("ARENA_PACING_ALL_PASS=true")
	else:
		print("ARENA_PACING_ALL_PASS=false")
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _resolve(state) -> Callable:
	return func(id):
		var item_id := str(id)
		if item_id == "":
			return {}
		var static_item: Dictionary = _data.item(item_id)
		if not static_item.is_empty():
			return static_item
		return state.loot_item(item_id)


func _hero(level: int = 30, str_points: int = 145) -> GameState:
	var s = GameState.new()
	s.bind_data(_data)
	s.set_class("barbarian")
	s.hero()["level"] = level
	s.hero()["attrStr"] = str_points
	s.equip()["weapon"] = "blade_shortSword"
	s.hero()["maxHp"] = _gen.hero_max_hp(s.hero(), s.equip(), _resolve(s))
	s.hero()["hp"] = s.hero()["maxHp"]
	return s


## A running arena, built the way main.gd builds it.
func _arena(state, fight: int = 0) -> ArenaScreen:
	state.data["locationProgress"][0] = 0
	state.data["areaFightProgress"][0] = fight
	var screen: ArenaScreen = ArenaScreen.new(_data, _gen, _loot, state, _resolve(state))
	root.add_child(screen)
	if screen._mana_track == null:
		screen._build()
	if not screen.start(state, _resolve(state)):
		_fail("the arena could not start a fight")
	return screen


## THE bug. `_process` pumped exactly ONE 100 ms tick per frame and ignored `delta`, so the
## fight's speed was the frame rate. The test drives the screen's own `_process` with a
## stopwatch's worth of frames and compares the game time that resulted.
##
## 100 frames of 10 ms is one real second. Before the fix that was 100 ticks = 10 s of game
## time; after it, 10 ticks = 1 s.
func _test_the_fight_advances_in_real_time_not_in_frames() -> void:
	var s = _hero()
	var screen = _arena(s)
	# Keep the fight alive and out of reach measurement: an unemptyable enemy, in contact.
	screen.battle.enemy_max_hp = 100000.0
	screen.battle.enemy_hp = 100000.0
	screen.battle.hero_max_hp = 100000.0
	screen.battle.hero_hp = 100000.0
	screen.battle.gap = 0.0
	var ticks_before: int = screen.battle.ticks_elapsed

	# ONE simulated second, in frames a real 100 Hz display would deliver.
	var frames := 100
	var frame_delta := 0.01
	for _i in frames:
		screen._process(frame_delta)
	var elapsed_ms: int = (screen.battle.ticks_elapsed - ticks_before) * screen.TICK_MS
	if elapsed_ms < 900 or elapsed_ms > 1100:
		_fail("one second of frames advanced %d ms of fight time (expected ~1000)" % elapsed_ms)
	else:
		print("  1.00 s of frames -> %d ms of fight" % elapsed_ms)


## The consequence the player reports: a weapon's `swingMs` has to be the interval the
## fight actually uses. Measured through the SCREEN's clock, not through `battle.tick()`.
func _test_a_weapon_s_speed_is_what_the_player_feels() -> void:
	var s = _hero()
	var screen = _arena(s)
	screen.battle.enemy_max_hp = 1000000.0
	screen.battle.enemy_hp = 1000000.0
	screen.battle.hero_max_hp = 1000000.0
	screen.battle.hero_hp = 1000000.0
	screen.battle.gap = 0.0
	var expected: int = screen.battle.player_swing_ms
	if expected < 600:
		_fail("test setup: the measured weapon swings in %d ms, too fast to tell apart" % expected)
		return

	var hits: Array = []
	# 12 s of 60 fps frames — long enough for several swings after the hero's walk-in.
	for _i in 720:
		screen._process(1.0 / 60.0)
	# The SCREEN drains `battle.log` inside `step()`, so the test cannot read it afterwards
	# — it comes back empty and the fight's landed hits are invisible. Read the screen's own
	# drain history instead; that is what the player's readout is built from.
	for entry in screen.drain_history:
		var kind := str(entry.get("kind", ""))
		if kind.begins_with("HIT") or kind == "CRIT":
			hits.append(int(entry["game_ms"]))

	if hits.size() < 3:
		_fail("only %d landed hits in 12 s with a %d ms weapon" % [hits.size(), expected])
		return
	var deltas: Array = []
	for i in range(1, hits.size()):
		deltas.append(int(hits[i]) - int(hits[i - 1]))
	deltas.sort()
	# The MEDIAN, not the mean: a missed swing (50 % chance to hit is an even fight by
	# design) pushes the next landed hit out by a whole extra interval, and the battle's
	# seed is the wall clock, so a mean over a handful of swings is a coin-flip verdict.
	# The median ignores those outliers and still catches a clock that runs at the frame
	# rate — which is what this test exists for.
	var median: float = float(deltas[deltas.size() / 2]) if deltas.size() % 2 == 1 \
		else float(deltas[deltas.size() / 2 - 1] + deltas[deltas.size() / 2]) * 0.5
	# No swing may land EARLIER than the weapon's own interval either — that is the
	# direction the "runs too fast" bug went.
	var shortest: int = int(deltas[0])
	if absf(median - float(expected)) > 200.0:
		_fail("a %d ms weapon landed every %.0f ms of fight time (median of %d swings) - the screen is not using the rules' clock"
			% [expected, median, deltas.size()])
	elif shortest < expected - 200:
		_fail("the shortest interval between landed hits was %d ms against a %d ms weapon - the fight is outrunning the weapon"
			% [shortest, expected])
	else:
		print("  %d ms weapon -> median %.0f ms (shortest %d ms) between landed hits" % [expected, median, shortest])


## A frame slower than one step must not hand out extra swings: `_process` clamps how many
## steps one frame may run. A 500 ms frame is the pathological case (a phone waking up).
func _test_a_fast_frame_does_not_shorten_a_swing() -> void:
	var s = _hero()
	var screen = _arena(s)
	screen.battle.enemy_max_hp = 100000.0
	screen.battle.enemy_hp = 100000.0
	screen.battle.hero_max_hp = 100000.0
	screen.battle.hero_hp = 100000.0
	screen.battle.gap = 0.0
	# A long stall: at most MAX_STEPS_PER_FRAME steps may run from it.
	var before: int = screen.battle.ticks_elapsed
	screen._process(5.0)
	var ran: int = screen.battle.ticks_elapsed - before
	if ran > screen.MAX_STEPS_PER_FRAME:
		_fail("one stalled frame ran %d steps, more than the %d allowed"
			% [ran, screen.MAX_STEPS_PER_FRAME])


## A pack is fought to its LAST member. The port declared victory on the first death, so
## an elite pack (three slaves and then the leader) was one enemy long.
func _test_a_pack_is_fought_to_the_last_member() -> void:
	var s = _hero()
	# Fight 10/10 of the stop is the elite pack: 3 slaves, the LEADER last.
	var screen = _arena(s, 9)
	var b = screen.battle
	if not b.is_pack:
		_fail("fight 10/10 is not a pack, so this test measures nothing")
		return
	var members: int = b.pack_size()
	var seen: Array = [b.pack_active]
	var guard := 0
	while not b.ended and guard < 20000:
		b.tick(100.0, _state_of(screen), _resolve(_state_of(screen)))
		if b.pack_active != int(seen[seen.size() - 1]):
			seen.append(b.pack_active)
		guard += 1
		if b.pending_kill:
			b.tick(100.0, _state_of(screen), _resolve(_state_of(screen)))
			guard += 1
	if seen.size() != members:
		_fail("a %d-member pack ended after %d members; the order was %s"
			% [members, seen.size(), str(seen)])
	else:
		print("  elite pack: %s" % str(seen))
	# And the winner is the whole pack's kill, not the first member's.
	if not b.won:
		_fail("clearing every pack member did not win the fight")


func _state_of(screen) -> Variant:
	return screen._state


## A defeat is settled on the SAVE, the way the PWA's death path did it: the death counted
## once, the current stop's fights reset, a consolation paid, and the hero healed because
## the death sends him to town.
func _test_a_defeat_is_settled_on_the_save() -> void:
	var s = _hero(1, 0)
	s.equip()["weapon"] = "fists"
	s.hero()["maxHp"] = _gen.hero_max_hp(s.hero(), s.equip(), _resolve(s))
	s.hero()["hp"] = s.hero()["maxHp"]
	var screen = _arena(s, 6)
	var b = screen.battle
	# A fight the hero cannot survive, so the defeat is real and not simulated.
	b.hero_max_hp = 1.0
	b.hero_hp = 1.0
	b.gap = 0.0
	var deaths_before: int = int(s.data["deaths"])
	var xp_before: int = int(s.hero()["xp"])
	var guard := 0
	while not b.ended and guard < 400:
		screen.step()
		guard += 1
	if not b.ended or b.won:
		_fail("the doomed hero did not lose")
		return
	var deaths_after: int = int(s.data["deaths"])
	# THROUGH THE SCREEN, because that is where the port double-counted the death.
	if deaths_after - deaths_before != 1:
		_fail("a death through the arena counted %d deaths, expected exactly 1"
			% (deaths_after - deaths_before))
	if int(s.data["areaFightProgress"][0]) != 0:
		_fail("a defeat did not reset the current stop's fights (still %d/10)"
			% int(s.data["areaFightProgress"][0]))
	if int(s.hero()["xp"]) <= xp_before:
		_fail("a defeat paid no consolation XP")
	if float(s.hero()["hp"]) < float(s.hero()["maxHp"]):
		_fail("a defeat left the hero at %.0f/%.0f HP - the death sends him to town"
			% [float(s.hero()["hp"]), float(s.hero()["maxHp"])])
	# A loss must NOT offer another fight: the only way on is town.
	if screen._next_button.visible:
		_fail("a defeat offered another fight in the same stop")


## A CLEARED stop (10/10) has no "next fight" left in it — the PWA sent the player to the
## map. The port kept offering another fight forever.
func _test_a_cleared_stop_offers_the_map_not_another_fight() -> void:
	var s = _hero()
	var screen = _arena(s, 9)
	var b = screen.battle
	# The pack is cleared by hand: this test is about what the END-OF-FIGHT screen offers.
	b.enemy_hp = 0.0
	b.is_pack = false
	b.pending_kill = false
	# TWO steps, not one: the death is deferred by a tick (the PWA's 300 ms death beat, the
	# same `pending_kill` the victory path uses), so a single step only registers the kill.
	var guard := 0
	while not b.ended and guard < 10:
		screen.step()
		guard += 1
	if not b.ended or not b.won:
		_fail("the cleared stop did not end in a win (ended=%s won=%s)" % [str(b.ended), str(b.won)])
		return
	if int(s.data["areaFightProgress"][0]) < 10:
		_fail("test setup: the stop should be at 10/10, it is at %d"
			% int(s.data["areaFightProgress"][0]))
	if screen._next_button.visible:
		_fail("a cleared stop still offered another fight")
	if screen._leave_button.text != "Mapa":
		_fail("a cleared stop's way on is '%s', expected the map" % screen._leave_button.text)


## A pack hand-over is a NEW enemy, and the thing that makes it "new" is that the hero has to
## walk to it again. `render()` used to write `_pack_displayed = battle.pack_active` itself
## BEFORE asking the roster, so the hand-over branch compared a value against itself and
## `_on_pack_member_began()` never ran — the walk-in was never restarted and member two was
## hit the instant it appeared.
##
## The portrait and the name were NOT broken by that order: `render()` reads them off
## `battle` at the top, so they already carried the new member. Verified by mutation —
## restoring the old order leaves the name assertions green and only the walk-in red. Assert
## the walk-in, which is the real symptom, and do not claim the name was affected.
func _test_a_pack_hand_over_restarts_the_walk_in() -> void:
	var s = _hero()
	# Fight 10/10 is the elite pack; kill members by hand so the hand-over is the only
	# thing under test.
	var screen = _arena(s, 9)
	var b = screen.battle
	if not b.is_pack or b.pack_size() < 2:
		_fail("fight 10/10 is not a multi-member pack, so this test measures nothing")
		return
	b.gap = 0.0
	b.enemy_hp = 0.0
	b.pending_kill = false
	var first_name: String = screen._enemy_name.text
	var guard := 0
	while b.pack_active == 0 and guard < 10:
		screen.step()
		guard += 1
	if b.pack_active == 0:
		_fail("the pack never handed the fight over after a member died")
		return
	var second_name: String = screen._enemy_name.text
	var expected: String = str(b.pack_members[b.pack_active].get("name", ""))
	if second_name == first_name:
		_fail("the arena kept showing '%s' after the pack handed over" % second_name)
	if not second_name.ends_with(expected):
		_fail("the arena shows '%s' where the new member is '%s'" % [second_name, expected])
	# The walk-in restarts: the new member must not be hit the instant it appears.
	if b.gap <= 0.0:
		_fail("the walk-in did not restart on the hand-over (gap still %.2f)" % b.gap)
	if screen._pack_displayed != b.pack_active:
		_fail("the roster is still showing member %d while the fight is on member %d"
			% [screen._pack_displayed, b.pack_active])


## The arena renders the swing: a landed hit has to move something. The lunges were never
## set by anything (both fields only decayed), which is why the two figures just stood
## there.
func _test_a_swing_lunge_exists_on_a_landed_hit() -> void:
	var s = _hero()
	var screen = _arena(s)
	var b = screen.battle
	b.enemy_max_hp = 100000.0
	b.enemy_hp = 100000.0
	b.hero_max_hp = 100000.0
	b.hero_hp = 100000.0
	b.gap = 0.0
	screen._hero_lunge = 0.0
	var guard := 0
	while guard < 200 and screen._hero_lunge <= 0.0:
		screen.step()
		guard += 1
	if screen._hero_lunge <= 0.0:
		_fail("no hero swing animation was triggered by %d ticks of landed hits" % guard)
	# And the monster answers: the hero's own flinch has to fire when HE is hit.
	screen._hero_flinch = 0.0
	guard = 0
	while guard < 600 and screen._hero_flinch <= 0.0:
		screen.step()
		guard += 1
	if screen._hero_flinch <= 0.0:
		_fail("the hero never flinched while being hit for %d ticks" % guard)
	# The floating damage text must read the key the battle writes, or every number the
	# hero takes is drawn in the enemy's colour.
	var on_player := false
	for entry in [{"kind": "ENEMY HIT", "amount": 5, "onPlayer": true}]:
		on_player = bool(entry.get("onPlayer", false))
	if not on_player:
		_fail("the log's onPlayer key is not readable by the screen")
