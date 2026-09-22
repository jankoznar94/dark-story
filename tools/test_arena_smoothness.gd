extends SceneTree
## tools/test_arena_smoothness.gd — the arena's OTHER clock: does it MOVE every frame?
##
## Jan's report after playing the port: "the whole thing runs as if it were 5 FPS; the swing
## animation is not smooth at all, it stutters". Every existing test supplied its own clock
## and every existing test passed:
##
##   - `test_arena_pacing` drives `_process(delta)` and asserts the FIGHT's pace (a 1156 ms
##     weapon lands every ~1156 ms of game time). That measures the RULES clock and it was
##     right the whole time.
##   - `test_portrait_visual` asserts the arc's GEOMETRY (radii, drawn sweep) after calling
##     `render()`/`_apply_centring()` by hand.
##
## Neither can see the bug. `render()` runs from `step()`, i.e. TEN TIMES A SECOND, and it
## used to be the only thing that wrote the gauges: the gold swing ring advanced in eleven
## visible jumps per swing and the HP bar stepped with it, while the engine happily drew 60
## frames a second around it. Nothing was slow — the numbers were computed every frame and
## drawn ten times a second. `probe_watch.gd` measured the arc changing in 21 of 120 frames.
##
## So this test measures MOTION PER FRAME: it feeds real 60 Hz frames to `_process` and counts
## how many of them changed what is on screen.
##
## Run:  godot --headless --path . --script res://tools/test_arena_smoothness.gd
## Pass: prints ARENA_SMOOTHNESS_ALL_PASS=true and exits 0.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const ArenaScreen := preload("res://scripts/ui/arena_screen.gd")

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

	_test_the_swing_ring_moves_every_frame()
	_test_the_ring_s_sweep_is_the_weapon_s_interval()
	_test_the_walk_in_moves_every_frame()
	_test_the_damage_ghost_trails_the_fill()
	_test_the_rules_clock_is_still_the_rules_clock()

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("ARENA_SMOOTHNESS_ALL_PASS=true")
	else:
		print("ARENA_SMOOTHNESS_ALL_PASS=false")
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


## A running arena with a fight that cannot end, in contact (this test is about motion, not
## about the walk-in or the outcome).
func _arena(state, fight: int = 0) -> ArenaScreen:
	state.data["locationProgress"][0] = 0
	state.data["areaFightProgress"][0] = fight
	var screen: ArenaScreen = ArenaScreen.new(_data, _gen, _loot, state, _resolve(state))
	root.add_child(screen)
	if screen._mana_track == null:
		screen._build()
	screen._arena.size = Vector2(390, 693)
	if not screen.start(state, _resolve(state)):
		_fail("the arena could not start a fight")
	screen.battle.enemy_max_hp = 1000000.0
	screen.battle.enemy_hp = 1000000.0
	screen.battle.hero_max_hp = 1000000.0
	screen.battle.hero_hp = 1000000.0
	screen.battle.gap = 0.0
	return screen


## THE bug. One real second of 60 Hz frames has to move the swing ring on almost every one of
## them. Before the fix it moved on ~10 of 60 (it only changed inside `step()`); a screen that
## is smooth moves it on all but the frames where the value happens to round to the same
## float.
func _test_the_swing_ring_moves_every_frame() -> void:
	print("== the swing ring moves per frame ==")
	var s = _hero()
	var screen = _arena(s)
	if screen.battle.player_swing_ms < 600:
		_fail("test setup: the weapon swings in %d ms, too fast to sample" % screen.battle.player_swing_ms)
		return

	var frames := 60
	var moved := 0
	var backwards := 0
	var prev: float = screen._arc_player.value
	for _i in frames:
		screen._process(FRAME)
		var now: float = screen._arc_player.value
		if not is_equal_approx(now, prev):
			moved += 1
		# A swing ring only ever fills; only a landed swing restarts it at the bottom. A
		# ring that jumps BACKWARDS in the middle of a swing is a stutter, not a sweep.
		if now < prev - 0.001 and prev < 0.9:
			backwards += 1
		if now < 0.0 or now > 1.0:
			_fail("the swing arc read %.3f, outside 0..1" % now)
		prev = now

	if moved < frames - 2:
		_fail("the swing arc changed in only %d of %d frames - the screen is drawing ten times a second"
			% [moved, frames])
	else:
		print("  the arc changed in %d of %d frames" % [moved, frames])
	if backwards > 0:
		_fail("the swing arc jumped backwards %d times inside a single swing" % backwards)


## The ring's sweep period has to BE the weapon's interval: 1156 ms of real time per lap, so
## the player can feel the weapon's speed. Samples the frames between two restarts.
##
## This is the check that ties the smoothness to the RULES: an animation that is smooth but
## runs at its own speed would pass the frame count above and fail this.
func _test_the_ring_s_sweep_is_the_weapon_s_interval() -> void:
	print("== the ring's sweep is the weapon's interval ==")
	var s = _hero()
	var screen = _arena(s)
	var expected := float(screen.battle.player_swing_ms)
	var restarts: Array[int] = []
	var prev: float = screen._arc_player.value
	# 8 s of frames: several swings at 1156 ms.
	for i in 480:
		screen._process(FRAME)
		var now: float = screen._arc_player.value
		if now < prev - 0.05:
			restarts.append(i)
		prev = now
	if restarts.size() < 2:
		_fail("the swing ring never completed a sweep in 8 s (a %d ms weapon)" % int(expected))
		return
	var gaps: Array[float] = []
	for i in range(1, restarts.size()):
		gaps.append(float(int(restarts[i]) - int(restarts[i - 1])) * FRAME * 1000.0)
	var median: float = gaps[gaps.size() / 2]
	if absf(median - expected) > 120.0:
		_fail("the ring sweeps every %.0f ms against a %d ms weapon - the animation is on its own clock"
			% [median, int(expected)])
	else:
		print("  %d ms weapon -> the ring sweeps every %.0f ms" % [int(expected), median])


## The walk-in is the same class of bug and is NOT a rule: `_gap` only changes inside a tick,
## but the hero has to glide. A hero that teleports in 100 ms hops is the "stuttering" the
## report is about, and `test_duel_distance` cannot see it (it drives `_place_hero` directly).
func _test_the_walk_in_moves_every_frame() -> void:
	print("== the walk-in moves per frame ==")
	var s = _hero()
	var screen = _arena(s)
	# Start at maximum separation: the hero has to close it now.
	screen.battle.gap = 1.0
	screen._place_hero(0.0)
	var moved := 0
	# The approach is ~1030 ms for this weapon (gap 1.0 at 0.97/s), i.e. ~62 frames, so 90
	# frames is long enough to see him arrive and then stand still.
	var frames := 90
	var prev: Vector2 = screen._hero_sprite.position
	for _i in frames:
		screen._process(FRAME)
		var now: Vector2 = screen._hero_sprite.position
		if now != prev:
			moved += 1
		prev = now
	# Assert he ARRIVES, or "never moved" would pass the count trivially against a hero who
	# is simply standing at contact the whole time.
	if screen.battle.gap > 0.0:
		_fail("the hero did not close the distance in %d frames (gap %.2f)"
			% [frames, screen.battle.gap])
	if moved < 40:
		_fail("the hero's position changed in only %d of %d frames while walking in - the walk-in steps in 100 ms hops"
			% [moved, frames])
	else:
		print("  the hero moved on %d of %d frames (gap closed to %.2f)" % [moved, frames, screen.battle.gap])


## `.enemy-hp-ghost-ring` is the PWA's 0.6 s trail behind a 0.2 s fill. The port snapped the
## ghost onto the fill in the same statement, so the trail never existed on screen — and every
## render() wrote the arc's `.value` field directly, which does not queue a redraw at all.
##
## Assert the trail itself: right after damage the ghost is AHEAD of the fill, and it converges
## on the fill within about 0.6 s of real frames.
func _test_the_damage_ghost_trails_the_fill() -> void:
	print("== the damage ghost trails the fill ==")
	var s = _hero()
	var screen = _arena(s)
	# A hit, applied through the battle's own state so the fill ring moves with it.
	screen.battle.enemy_hp = screen.battle.enemy_max_hp * 0.5
	screen._smooth_update()
	var fill: float = screen._arc_enemy_hp.value
	var ghost: float = screen._arc_enemy_hp_ghost.value
	if not is_equal_approx(fill, 0.5):
		_fail("the fill ring reads %.3f after the enemy lost half its HP" % fill)
		return
	if ghost < fill:
		_fail("the ghost ring (%.3f) is already behind the fill (%.3f) after a hit - there is no trail"
			% [ghost, fill])
		return
	# One frame must NOT close the whole trail: 1/60 s of a 0.6 s transition is ~2.8 %.
	screen._process(FRAME)
	var after_one: float = screen._arc_enemy_hp_ghost.value
	if ghost - after_one > 0.05:
		_fail("the ghost lost %.3f of a %.3f trail in one frame - it is snapping, not easing"
			% [ghost - after_one, ghost - fill])
	# And it has to CONVERGE: 0.6 s of frames must land it on the fill.
	for _i in 40:
		screen._process(FRAME)
	var settled: float = screen._arc_enemy_hp_ghost.value
	if absf(settled - screen._arc_enemy_hp.value) > 0.02:
		_fail("the ghost ring settled at %.3f against a fill of %.3f after 0.66 s"
			% [settled, screen._arc_enemy_hp.value])
	else:
		print("  hit -> ghost %.3f, one frame later %.3f, settled %.3f in 0.66 s"
			% [ghost, after_one, settled])


## The other half of the split, and the reason it is safe: none of this may change what the
## RULES decide. One real second of 60 Hz frames is still 1000 ms of fight time and ten ticks
## — the interpolation must never feed a partial tick back into the battle.
func _test_the_rules_clock_is_still_the_rules_clock() -> void:
	print("== the rules clock is untouched ==")
	var s = _hero()
	var screen = _arena(s)
	var before: int = screen.battle.ticks_elapsed
	var elapsed_before: float = screen.battle.player_swing_elapsed
	for _i in 120:
		screen._process(FRAME)
	var ticks: int = screen.battle.ticks_elapsed - before
	var game_ms: int = ticks * screen.TICK_MS
	if game_ms < 1900 or game_ms > 2100:
		_fail("two seconds of 60 Hz frames advanced %d ms of fight time (expected ~2000)" % game_ms)
	else:
		print("  2.00 s of frames -> %d ms of fight, %d ticks" % [game_ms, ticks])
	# And the accumulator may never hold a whole step: that would mean a tick was skipped and
	# the fight's pace would drift against the stopwatch.
	if screen._tick_accumulator >= float(screen.TICK_MS):
		_fail("the accumulator holds %.1f ms at the end of a frame - a whole step was skipped"
			% screen._tick_accumulator)
	if is_nan(elapsed_before) or is_nan(screen.battle.player_swing_elapsed):
		_fail("the swing clock became NaN")
