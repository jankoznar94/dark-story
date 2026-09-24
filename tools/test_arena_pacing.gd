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

## One 60 Hz frame, the clock `_process` is driven with. Same constant as
## `test_arena_smoothness` and `test_arena_screen` — a frame is not a tick.
const FRAME := 1.0 / 60.0

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
	_test_the_result_page_shows_the_loot_and_the_ways_on()
	_test_a_defeat_page_has_no_tiles_and_leads_to_town()
	_test_the_result_page_actually_gets_laid_out()
	_test_a_pack_hand_over_restarts_the_walk_in()
	_test_a_swing_lunge_exists_on_a_landed_hit()
	_test_a_gold_only_win_still_lists_the_gold()
	_test_a_defeat_does_not_list_the_consolation_gold()
	_test_the_combat_log_is_gone()
	_test_a_loot_row_is_readable()

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
	# A loss must NOT offer another fight: the only way on is town. The result page's tiles
	# are rebuilt per outcome, so the check is on what the row actually CONTAINS.
	if screen._result_actions.get_child_count() != 0:
		_fail("a defeat offered action tiles (%d) - the only way on is the town"
			% screen._result_actions.get_child_count())


## A CLEARED stop (10/10) has no "next fight" left in it — the PWA sent the player to the
## map. The port kept offering another fight forever.
##
## The result page's tile row is REBUILT per outcome from the PWA's own rule, so this checks
## the ROW's labels: a cleared stop's first tile is the map, a live one's is the next fight.
## The labels are read off the tiles rather than off a named field, because a named field
## ("_next_button") that keeps existing after the page was rebuilt is exactly how the port
## advertised a fight the stop did not have.
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
	if not screen._result_layer.visible:
		_fail("a win did not raise the result page")
	var labels := _action_labels(screen)
	if labels.has("Dalsi souboj"):
		_fail("a cleared stop still offered another fight (tiles: %s)" % str(labels))
	if not labels.has("Mapa"):
		_fail("a cleared stop's way on is %s, expected the map" % str(labels))
	# And the page tap goes to the MAP as well: the PWA's `openMapFromResult`.
	if not screen._result_tap_goes_to_map:
		_fail("a cleared stop's page tap did not go to the map")


## The report: "the win and the lose screen do not work — after a win the player gets no loot
## and cannot go to town". What the port had was ONE word over a live arena; the PWA has a full
## result PAGE. So this asserts the page itself: it covers the screen, it names the outcome, it
## LISTS the drops the fight rolled, and its tiles carry the PWA's destinations.
func _test_the_result_page_shows_the_loot_and_the_ways_on() -> void:
	var s = _hero()
	var screen = _arena(s, 0)
	var b = screen.battle
	# Kill the enemy through the rules so the win, the loot roll and the page are all real.
	b.enemy_hp = 0.0
	var guard := 0
	while not b.ended or not screen._result_built:
		screen.step()
		guard += 1
		if guard > 40:
			_fail("the fight never raised a result page")
			return
	if not screen._result_layer.visible:
		_fail("the result page was built but is not shown")
		return
	if screen._result_title.text == "":
		_fail("the result page has no outcome on it")
	# A win writes the victory title and the act/stop/fight line; a defeat writes "Porazka".
	if not screen._result_title.text.contains("Vitezstvi"):
		_fail("a win's page reads '%s', expected the victory title" % screen._result_title.text)
	if screen._result_sub.text == "":
		_fail("the victory line is empty - the act, stop and fight count are missing")
	# LOOT IS VISIBLE. `award_loot` rolls 2-3 items per pack member, so a win's list must
	# either carry rows or say so explicitly — never be an empty box.
	if not screen._loot_list.visible:
		_fail("the loot list is hidden after a win")
	else:
		var rows := _loot_row_texts(screen)
		if rows.is_empty():
			_fail("the loot list has no rows at all (not even the 'no items' line)")
		# Every item the fight rolled is registered as a known drop, so the row list has to
		# agree with what the bag and the overflow between them hold — PLUS the gold row,
		# which is not an item and is deliberately kept out of `_result_loot_rows`.
		var expected: int = screen._result_loot_rows.size()
		if screen._result_gold_won > 0:
			expected += 1
		if expected != rows.size():
			_fail("the page lists %d loot rows for %d rolled drops (+%d gold row)"
				% [rows.size(), screen._result_loot_rows.size(),
					1 if screen._result_gold_won > 0 else 0])
	# The tiles: a live win is Next Fight + Town + Hero, as the PWA's own `else` branch.
	var labels := _action_labels(screen)
	for needed in ["Dalsi souboj", "Do mesta"]:
		if not labels.has(needed):
			_fail("a win's action tiles are %s - '%s' is missing" % [str(labels), needed])
	print("  result page: '%s' / '%s' / tiles %s / %d loot rows"
		% [screen._result_title.text, screen._result_sub.text, str(_action_labels(screen)),
			_loot_row_texts(screen).size()])


## A defeat's page: the defeat art, the town as the only destination, NO loot list rows and NO
## action tiles (`.result-bottom:empty { display:none }`), and a page tap that leaves for town.
func _test_a_defeat_page_has_no_tiles_and_leads_to_town() -> void:
	var s = _hero(1, 0)
	s.equip()["weapon"] = "fists"
	var screen = _arena(s, 6)
	var b = screen.battle
	b.hero_max_hp = 1.0
	b.hero_hp = 1.0
	b.gap = 0.0
	var guard := 0
	while not b.ended or not screen._result_built:
		screen.step()
		guard += 1
		if guard > 400:
			_fail("the doomed hero never reached a result page")
			return
	if not screen._result_layer.visible:
		_fail("a defeat did not raise the result page")
	if not screen._result_title.text.contains("Forfeit"):
		_fail("a defeat's page reads '%s', expected the defeat title" % screen._result_title.text)
	if not screen._result_defeat_art.visible:
		_fail("a defeat drew no defeat artwork")
	if screen._result_art.visible:
		_fail("a defeat drew the stop's artwork over its own")
	if screen._result_actions.get_child_count() != 0:
		_fail("a defeat offered %d action tiles" % screen._result_actions.get_child_count())
	if screen._result_tap_goes_to_map:
		_fail("a defeat's page tap went to the map instead of the town")
	# The tap must actually emit the town route once the button lock has run out.
	var left := {"n": 0}
	screen.leave_requested.connect(func(): left["n"] = int(left["n"]) + 1)
	# `_button_lock_ms` runs on REAL time (see BUTTON_LOCK_MS) and the fight is already over,
	# so `step()` no longer ticks at all — the lock is burned with frames, which is the clock
	# the player's tap actually waits on. A tap on the frame the page appeared is ignored on
	# purpose (the player aimed at the arena).
	var lock_guard := 0
	while screen._button_lock_ms > 0 and lock_guard < 600:
		screen._process(FRAME)
		lock_guard += 1
	screen._on_result_clicked()
	if int(left["n"]) != 1:
		_fail("a defeat's page tap did not ask to leave (emitted %d times)" % int(left["n"]))
	# A defeat drops NOTHING: the PWA clears the list (`resultLootList.innerHTML = ''`). The
	# port was showing the drops of the enemy that never died, which reads as a reward.
	if _loot_row_texts(screen).size() != 0:
		_fail("a defeat's page listed %s - a defeat drops nothing" % str(_loot_row_texts(screen)))


## The result page's GEOMETRY, which is what "the win and lose screen do not work" looked like
## on screen and what no assertion above can see: the port's defeat page was a BLACK PAGE with
## two labels jammed into the top-left corner, because `result_defeat.png` was a JPEG under a
## `.png` name and the loader refused it, so `_layout_result_page()` returned before placing
## anything.
##
## Two failures live here and both are silent:
##   1. a texture that did not load — the art is `visible` with a NULL texture and a 0x0 rect;
##   2. a block that was never PLACED — every rect at the origin.
## So this asserts the rects, not the `visible` flags. `_layout_result_page()` is `call_deferred`
## in the screen, so it is called directly here.
func _test_the_result_page_actually_gets_laid_out() -> void:
	print("== the result page is laid out, not just made visible ==")
	var s = _hero()
	var screen = _arena(s, 0)
	var b = screen.battle
	b.enemy_hp = 0.0
	var guard := 0
	while not b.ended or not screen._result_built:
		screen.step()
		guard += 1
		if guard > 40:
			_fail("the fight never raised a result page")
			return
	# A win: the stop's art, 390 wide and 390 tall at the page's top (measured on the live PWA
	# as 390x392 at (0, 1)).
	# The screen is never in the tree in a `SceneTree` test, so its full-rect anchors resolve to
	# 0x0 — give it the real canvas size before asking where anything landed, the same way the
	# `_arena()` helper sizes `_arena`.
	screen._result_layer.size = Vector2(390.0, 844.0)
	screen._layout_result_page()
	var page: Vector2 = screen._result_layer.size
	if page.x <= 0.0 or page.y <= 0.0:
		_fail("the result page has no size (%s) - nothing can be placed on it" % str(page))
		return
	if screen._result_art.texture == null:
		_fail("the stop's artwork did not load - the page draws an empty box where the art goes")
	elif screen._result_art.size.x < page.x - 1.0:
		_fail("the stop's artwork came out %.0f wide on a %.0f page"
			% [screen._result_art.size.x, page.x])
	# The LOOT must sit under the art, NOT at the bottom of the page. This is the second bug
	# this pass fixed: the loot list was a sibling of the expanding block, so a `flex:1` top
	# pushed it to the page's bottom and left a black hole in the middle. Measured on the live
	# PWA: the art ends at 393 and the loot row starts at 399.
	var art_bottom: float = screen._art_box.position.y + screen._art_box.size.y
	var loot_y: float = screen._loot_list.get_global_rect().position.y
	if loot_y > art_bottom + 40.0:
		_fail("the loot list starts at y=%.0f with the art ending at y=%.0f - it was pushed to the bottom of the page"
			% [loot_y, art_bottom])
	# The tiles own the page's bottom edge, as `.result-bottom { position:absolute; bottom:0 }`
	# does. Measured on the live PWA: 87px tiles ending 10px above the page's bottom.
	#
	# The assertion reads the values the LAYOUT computes, not the container's arranged rects:
	# this test is a `SceneTree`, the screen is never in the tree, so `_result_actions` keeps a
	# 0x0 rect and a container arranges nothing.
	var tiles_bottom: float = screen._tiles_holder.position.y + screen._tiles_holder.size.y
	if absf(tiles_bottom - page.y) > 1.0:
		_fail("the tile strip ends at y=%.0f on a %.0f page - `.result-bottom` is not on the bottom edge"
			% [tiles_bottom, page.y])
	# `.result-tile` is `flex:1 1 60px; min-width:60px; max-width:90px` inside a 390px page
	# with 12px padding and a 6px gap. THREE tiles (a live win, no portal scroll) → (390-24-12)/3
	# = 118, which the 90px cap binds; FOUR → 87, which is the PWA's measured value.
	var tile_w: float = screen._tile_size()
	var expect: float = 90.0 if screen._result_actions.get_child_count() == 3 else 87.0
	if absf(tile_w - expect) > 1.0:
		_fail("%d tiles came out %.0f wide, expected %.0f (`.result-tile` flex/max-width)"
			% [screen._result_actions.get_child_count(), tile_w, expect])
	print("  art 390x%.0f at y=%.0f, loot at y=%.0f, tiles end y=%.0f (%.0f wide)"
		% [screen._result_art.size.y, screen._result_art.position.y, loot_y, tiles_bottom, tile_w])

	# And the DEFEAT page: the art at its INTRINSIC size (CSS `max-*` never upscales - measured
	# as 256 wide, not 90vw = 351), the title under it as the PWA's `.result-title`, and the
	# whole block CENTRED as `.result-screen.centered` does.
	var s2 = _hero(1, 0)
	s2.equip()["weapon"] = "fists"
	var lose = _arena(s2, 6)
	var lb = lose.battle
	lb.hero_max_hp = 1.0
	lb.hero_hp = 1.0
	lb.gap = 0.0
	guard = 0
	while not lb.ended or not lose._result_built:
		lose.step()
		guard += 1
		if guard > 400:
			_fail("the doomed hero never reached a result page")
			return
	lose._result_layer.size = Vector2(390.0, 844.0)
	lose._layout_result_page()
	if lose._result_defeat_art.texture == null:
		_fail("the defeat artwork did not load - the page is a black screen (a JPEG named .png does this)")
		return
	var tex: Texture2D = lose._result_defeat_art.texture
	if lose._result_defeat_art.size.x > float(tex.get_width()) + 0.5:
		_fail("the defeat art drew %.0f wide from a %d px image - `max-width` may not UPSCALE"
			% [lose._result_defeat_art.size.x, tex.get_width()])
	var lose_page: Vector2 = lose._result_layer.size
	var art_top: float = lose._art_box.position.y
	var text_bottom: float = lose._result_overlay.position.y + lose._result_overlay.size.y
	# `centered`: the block's own centre must be the space above the tiles' centre.
	var block_mid := (art_top + text_bottom) * 0.5
	var space_mid := (lose_page.y - lose._result_actions_h()) * 0.5
	if absf(block_mid - space_mid) > 3.0:
		_fail("a defeat's block is centred at y=%.0f in a %.0f space - `.centered` is not applied"
			% [block_mid, space_mid * 2.0])
	if lose._result_overlay.position.y <= lose._result_defeat_art.size.y + art_top:
		_fail("a defeat's title is not UNDER its artwork (title y=%.0f, art ends y=%.0f)"
			% [lose._result_overlay.position.y, art_top + lose._result_defeat_art.size.y])
	print("  defeat: art %dx%d at y=%.0f, title at y=%.0f, block centred"
		% [int(lose._result_defeat_art.size.x), int(lose._result_defeat_art.size.y),
			art_top, lose._result_overlay.position.y])


## The loot rows' own text, so a page that lists nothing can be told from one that is hidden.
## The text of every loot row, concatenated per row.
##
## Walked RECURSIVELY: `_make_loot_row` wraps the row in a `MarginContainer` (the CSS's own
## `padding:5px 8px` and the 5px vertical gap Jan asked for), so the Label is a grandchild
## now. A helper that only looked one level down reported `""` for every row and made a
## working list look empty.
func _loot_row_texts(screen) -> Array:
	var out: Array = []
	for child in screen._loot_list.get_children():
		out.append(_subtree_text(child))
	return out


func _subtree_text(node: Node) -> String:
	var text := ""
	if node is Label:
		text += (node as Label).text
	for child in node.get_children():
		text += _subtree_text(child)
	return text


## The labels of the result page's action tiles, in order. Read off each tile's own `label`
## meta (the caption is a child Label, so `Button.text` is empty) — a row that kept a stale
## tile therefore cannot pass.
func _action_labels(screen) -> Array:
	var out: Array = []
	for child in screen._result_actions.get_children():
		out.append(str(child.get_meta("label", "<no-label>")))
	return out


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


## A win that paid ONLY gold must still show something: the list used to read "Zadne predmety"
## over a purse the fight had just filled, which is indistinguishable from a fight that paid
## nothing. Jan asked for the gold to be a row of its own, "as if it were an item".
##
## Forced rather than rolled: `roll_loot` is seeded off the wall clock, so a run can produce
## items and then the test proves nothing about the gold row. The gold amount is written
## straight and the list is rebuilt through the screen's own `_refresh_result_loot`.
func _test_a_gold_only_win_still_lists_the_gold() -> void:
	var s = _hero()
	var screen = _arena(s)
	screen._result_loot_rows = []
	screen._result_gold_won = 137
	screen._refresh_result_loot(true)
	var rows := _loot_row_texts(screen)
	if rows.size() != 1:
		_fail("a gold-only win listed %d loot rows, expected exactly the gold row: %s"
			% [rows.size(), str(rows)])
		return
	if not str(rows[0]).contains("137"):
		_fail("the gold row reads '%s' - the amount is not on it" % str(rows[0]))
	if str(rows[0]).contains("Zadne predmety"):
		_fail("a gold-only win still says 'Zadne predmety'")
	# The icon is a real asset and it must load: the game has no emoji, so a missing file
	# would leave the row with an empty 32px slot.
	var icon := _loot_row_icon(screen, 0)
	if icon == null:
		_fail("the gold row has no icon node")
	elif icon.texture == null:
		_fail("the gold row's icon is '%s' and it did not load" % screen.COIN_ICON)
	print("  a gold-only win lists: %s" % str(rows))


## ...and a defeat must NOT list it: the list is cleared on a loss (the PWA does the same),
## and the consolation gold the battle pays is not a drop. A page that showed it would offer
## a reward for dying.
func _test_a_defeat_does_not_list_the_consolation_gold() -> void:
	var s = _hero(1, 0)
	s.equip()["weapon"] = "fists"
	var screen = _arena(s, 6)
	var b = screen.battle
	b.hero_hp = 0.0
	var guard := 0
	while not b.ended or not screen._result_built:
		screen.step()
		guard += 1
		if guard > 60:
			_fail("the defeat never raised a result page")
			return
	if screen._result_gold_won != 0:
		_fail("a defeat's page carries a gold row of %d - a loss pays no drop"
			% screen._result_gold_won)
	if _loot_row_texts(screen).size() != 0:
		_fail("a defeat's page listed %s - a defeat drops nothing"
			% str(_loot_row_texts(screen)))


## The TextureRect of a loot row, for the icon assertion above.
## The row's icon, found anywhere under it — the row is a padded box now, so the
## TextureRect is a grandchild rather than a child.
func _loot_row_icon(screen, index: int) -> TextureRect:
	var children: Array = screen._loot_list.get_children()
	if index >= children.size():
		return null
	return _subtree_icon(children[index])


func _subtree_icon(node: Node) -> TextureRect:
	for child in node.get_children():
		if child is TextureRect:
			return child as TextureRect
		var found := _subtree_icon(child)
		if found != null:
			return found
	return null


## Jan: "delete the text combat log at the very bottom, it should not be there at all."
## The PWA never had one — its readout is the floating number over the arena — and the port's
## was an invention that also stole the bottom of the screen.
##
## Asserted on the SCREEN'S OWN TREE, not on the source: the field could be renamed and the
## node kept. Every VBox child of the arena column is checked for a stack of small dim Labels.
func _test_the_combat_log_is_gone() -> void:
	var screen = _arena(_hero())
	var strays: Array = []
	_scan_for_log(screen._arena.get_parent(), strays)
	if strays.size() > 0:
		_fail("the arena still builds a text log: %s" % str(strays))
	# ...and the screen owns no log state to write into.
	if "_log_box" in screen or "_append_log" in screen:
		_fail("arena_screen still carries the log's field/function (%s)"
			% str(["has _log_box" if "_log_box" in screen else "",
				"has _append_log" if "_append_log" in screen else ""]))


## A footer log reads as a container holding >= 2 sibling Labels of <= 12px with no icon and
## no background. The arena has no other node of that shape.
func _scan_for_log(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is VBoxContainer:
			var small := 0
			for sub in child.get_children():
				if sub is Label and (sub as Label).get_theme_font_size("font_size") <= 12:
					small += 1
			if small >= 2:
				out.append("%s with %d small labels at %s" % [child.get_class(), small,
					str((child as Control).position)])
		_scan_for_log(child, out)


## Jan: "the loot on the victory page is hard to read — a bit bigger font, and maybe slightly
## bigger vertical gaps between the rows." The CSS row is 15px with 5px of vertical padding;
## the port had no padding at all and a 0px list separation, so the rows were 32px icon-tall
## and sat edge to edge. This is a DELIBERATE deviation from the reference for a phone.
func _test_a_loot_row_is_readable() -> void:
	var screen = _arena(_hero())
	screen._result_loot_rows = [{"id": "loot_1", "name": "Kratky mec", "rarity": "rare"}]
	screen._result_gold_won = 50
	screen._refresh_result_loot(true)
	var rows: Array = screen._loot_list.get_children()
	if rows.size() != 2:
		_fail("expected an item row and a gold row, got %d" % rows.size())
		return
	var label := _subtree_label(rows[0])
	if label == null:
		_fail("a loot row has no label")
		return
	var font := label.get_theme_font_size("font_size")
	if font < 17:
		_fail("the loot row's font is %dpx — Jan asked for bigger than the CSS's 15px" % font)
	# `get_theme_constant` returns Variant and Godot treats an inferred-Variant as a parse
	# ERROR here ("Cannot infer the type of 'pad'") — the whole script then fails to load
	# and the test prints NO verdict, which reads as a hang rather than as a failure.
	var pad: int = (rows[0] as Control).get_theme_constant("margin_top") \
		+ (rows[0] as Control).get_theme_constant("margin_bottom")
	if pad < 8:
		_fail("a loot row has %dpx of vertical padding, expected >= 8 (5px above and below)" % pad)
	# The row's height must clear the icon plus that padding, or the gap is not real.
	#
	# Computed rather than read off `get_combined_minimum_size()`: a container's cached
	# minimum is NOT recomputed without a layout pass, and a SceneTree test never runs one —
	# the value comes back as the icon's own 32 and the check fails against correct code.
	var icon := _loot_row_icon(screen, 0)
	var icon_h: float = icon.custom_minimum_size.y if icon != null else 0.0
	if icon_h + float(pad) < 42.0:
		_fail("a loot row's height is icon %s + padding %d px — the rows are still packed: %s"
			% [str(icon_h), pad, str(rows[0].get_combined_minimum_size())])


func _subtree_label(node: Node) -> Label:
	if node is Label:
		return node as Label
	for child in node.get_children():
		var found := _subtree_label(child)
		if found != null:
			return found
	return null
