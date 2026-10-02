extends SceneTree
## tools/test_dual_wield_timers.gd — the two swing clocks of a dual wielder.
##
## ⚠️  WHY THIS TEST EXISTS. The port (and the PWA before it) ran ONE swing clock for the
## hero, at the AVERAGE of the two weapons, and ALTERNATED the hands on it —
## `mb.offhandSwingMs = 0; // offhand nemá vlastní timer — sdílí hlavní (střídá se)` in
## `src/game.ts`. Two consequences, and Jan reported the second as a bug:
##
##   1. The off hand swung at the MAIN hand's pace. A 700 ms cutlass in the off hand and a
##      1580 ms axe in the main hand both landed every 1160 ms (the average × 0.85), so the
##      second weapon was a damage bonus and not a second weapon.
##   2. ⚠️  THE REPORTED BUG: "off hand timer se neustále resetuje s main hand timerem."
##      Every main-hand swing reset the off-hand arc, because the arc was drawn from
##      `battle.player_swing_elapsed` and the alternation meant one hand's landing always
##      restarted the other's turn. The screen showed two rings and only ever had one clock.
##
## Jan's rule: "Každý swing timer by si měl jet svým tempem. Neměly by být na sebe navzájem
## navázané. Až na výjimky, kdy třeba nějaký SKILL záměrně resetuje oba timery."
##
## So this file asserts BOTH halves of that sentence:
##
##   * independent — each hand's interval is its own weapon's, each clock advances on its
##     own, a main-hand landing does not touch the off-hand clock, and the two arcs on the
##     arena are drawn from two different numbers;
##   * the exception — a SKILL (Whirlwind start/complete/fail, Double Swing) restarts BOTH,
##     and `_reset_swing_timers()` is the one place allowed to.
##
## ⚠️  The failure mode is invisible in every existing test: `test_combat` asserts fights
## END, and a fight ends on the average clock too; `test_weapon_spec` measures off-hand
## DAMAGE with the off hand called directly, so a shared interval cannot show up there.
## What only this file can see is the two clocks' RATE and their independence — a
## relationship, not a number.
##
## Every assertion is verified by MUTATION (restore the average/alternation and confirm it
## goes red), because a test that only exercises code you just wrote passes for the wrong
## reasons.
##
## Run:  godot --headless --path . --script res://tools/test_dual_wield_timers.gd
## Pass: prints DUAL_WIELD_TIMERS_ALL_PASS=true and exits 0.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const Battle := preload("res://scripts/combat/battle.gd")
const Progression := preload("res://scripts/combat/progression.gd")
const PlayerSpells := preload("res://scripts/combat/player_spells.gd")
const ArenaScreen := preload("res://scripts/ui/arena_screen.gd")

## The two weapons, chosen for the WIDEST interval gap in the shipped data: the slowest
## one-hand axe against the fastest one-hand blade. Both are one-handed and both are on the
## barbarian's allowed list, so the pair is a legal dual wield.
const MAIN_WEAPON := "axe_axe"              # 1580 ms
const OFF_WEAPON := "blade_scimitar_nm"     # 700 ms
const DUMMY_HP := 10_000_000.0

var _data: Node
var _gen: ItemGen
var _loot: LootSystem
var _failures: Array[String] = []
var _state = null


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_loot = LootSystem.new(_data, _gen)

	_test_the_two_intervals_are_not_averaged()
	_test_each_hand_swings_at_its_own_pace()
	_test_a_main_hand_landing_does_not_reset_the_offhand()
	_test_a_single_weapon_runs_one_clock()
	_test_the_two_arcs_are_drawn_from_different_clocks()
	_test_a_skill_resets_both_clocks()

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("DUAL_WIELD_TIMERS_ALL_PASS=true")
	else:
		print("DUAL_WIELD_TIMERS_ALL_PASS=false")
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


## A barbarian holding `MAIN_WEAPON` and `OFF_WEAPON`, at a level where nothing is gated.
## `off` is switched off by passing "" — that is the single-weapon case below.
func _hero(main_id: String = MAIN_WEAPON, off_id: String = OFF_WEAPON, cls: String = "barbarian"):
	_state = GameState.new()
	_state.bind_data(_data)
	_state.set_class(cls)
	_state.hero()["level"] = 40
	_state.hero()["attrStr"] = 40
	_state.hero()["attrDex"] = 20
	_state.hero()["mana"] = 500
	_state.hero()["maxMana"] = 500
	_state.equip()["weapon"] = main_id
	if off_id != "":
		_state.equip()["shield"] = off_id
	return _state


## A fight that cannot end, with the gap pinned at contact so no swing is discarded for
## distance. The enemy is a real one out of the act tables — its resistances and block roll
## are irrelevant here, only the CLOCKS are measured.
func _rig(state, seed_value: int = 909) -> Battle:
	_state = state
	var b := Battle.new(_data, seed_value)
	b.act_id = 0
	if not b.setup(state, _resolve(state)):
		_fail("battle setup failed")
		return null
	b.enemy_hp = DUMMY_HP
	b.enemy_max_hp = DUMMY_HP
	b.hero_hp = DUMMY_HP
	b.hero_max_hp = DUMMY_HP
	b.enemy_dmg_min = 1
	b.enemy_dmg_max = 2
	b.apply_swing_timers(state, _resolve(state))
	b.gap = 0.0
	return b


## How many swings of one hand landed, counted from the battle's own log. A landed blow is
## `HIT` / `CRIT`, and the OFF hand's entries carry the ` offhand` suffix the port adds
## (`_resolve_player_hit`). A MISS/BLOCK carries no suffix for either hand — which is why
## only LANDED blows are counted and both hands are measured against the same bias.
func _count_swings(b: Battle, offhand: bool) -> int:
	var n := 0
	for entry in b.log:
		var kind := str(entry.get("kind", ""))
		if not (kind.begins_with("HIT") or kind.begins_with("CRIT")):
			continue
		var is_off := kind.ends_with("offhand")
		if is_off == offhand:
			n += 1
	return n


# --- 1. the intervals are each weapon's own, not their average ------------------

## The core of the bug: the port averaged the two weapons into ONE interval and gave the off
## hand no interval of its own at all (`offhand_swing_ms = 0` after the average was taken, so
## the off-hand arc read the main-hand clock). Each hand must now carry the interval
## `Progression.swing_time()` produces for ITS OWN weapon, in the same fight.
##
## ⚠️  The assertion is against an INDEPENDENT computation, not against a comparison of the
## two fields. A first version here only checked "the off hand's interval is smaller" and
## "they are not both the average" — and it PASSED with the averaging restored, because
## averaging makes the main hand's interval SMALLER and never equal to the off hand's, so
## both of those held while the bug was back. Recomputing the expected number from the same
## data the rule reads is what makes the mutation go red.
func _test_the_two_intervals_are_not_averaged() -> void:
	var s = _hero()
	var b := _rig(s)
	if b == null:
		return
	var main_item: Dictionary = _data.item(MAIN_WEAPON)
	var off_item: Dictionary = _data.item(OFF_WEAPON)
	var main_base := int(main_item.get("swingMs", 0))
	var off_base := int(off_item.get("swingMs", 0))
	# The rig must actually produce a gap, or the whole file measures nothing.
	if main_base <= off_base:
		_fail("test setup: %s (%d ms) is not slower than %s (%d ms)"
			% [MAIN_WEAPON, main_base, OFF_WEAPON, off_base])
		return
	if b.offhand_swing_ms <= 0:
		_fail("the off hand has NO interval of its own (offhand_swing_ms = %d) — the pair is running one clock"
			% b.offhand_swing_ms)
		return
	if b.offhand_swing_ms >= b.player_swing_ms:
		_fail("the fast off hand (%d ms) is not faster than the slow main hand (%d ms)"
			% [b.offhand_swing_ms, b.player_swing_ms])

	# The expected interval, computed the way the rule computes it: the DEX total, the glove
	# IAS and the weapon's own swingMs. Nothing is shared between the two hands except those
	# fight-wide inputs, which is exactly the claim.
	var find := _resolve(s)
	var dex_total := int(s.hero().get("attrDex", 0)) \
		+ Progression._equip_attr(s.equip(), find, "dex")
	var gloves: Dictionary = find.call(s.equip().get("gloves"))
	var glove_ias := int(gloves.get("ias", 0)) if not gloves.is_empty() else 0
	var want_main := Progression.swing_time(b.rng, main_item, dex_total, glove_ias,
		s.data.get("_speedBoostPct", 0.0))
	var want_off := Progression.swing_time(b.rng, off_item, dex_total, glove_ias, 0.0)
	var average := int(round((float(want_main) + float(want_off)) / 2.0 * 0.85))
	print("  intervals: main %d ms (%s), off %d ms (%s) — average would be %d"
		% [b.player_swing_ms, MAIN_WEAPON, b.offhand_swing_ms, OFF_WEAPON, average])

	if b.offhand_swing_ms != want_off:
		_fail("the off hand's interval is %d ms, but %s swings in %d — it is not this weapon's own clock"
			% [b.offhand_swing_ms, OFF_WEAPON, want_off])
	if b.player_swing_ms != want_main:
		_fail("the main hand's interval is %d ms, but %s swings in %d (the average would be %d)"
			% [b.player_swing_ms, MAIN_WEAPON, want_main, average])


# --- 2. measured, each hand at its own rate -------------------------------------

## Drive a real fight and count what each hand landed. The off hand's interval is ~2.26×
## shorter, so it must land visibly more often — measured, not derived from the fields the
## assertion above already read.
##
## ⚠️  A MISS/block/evasion is not counted, and that is deliberate: the two hands run the
## same attack table, so the miss RATE is the same and the swing RATE is the signal. The
## ratio has ~50 landed blows of noise on it, which a 2.26× gap clears easily (the
## tolerance is 35 %).
func _test_each_hand_swings_at_its_own_pace() -> void:
	var s = _hero()
	var b := _rig(s, 31337)
	if b == null:
		return
	# 60 s of fight, in the screen's own 100 ms steps.
	var ticks := 0
	while ticks < 600 and not b.ended:
		b.tick(100.0, s, _resolve(s))
		ticks += 1
	var main_swings := _count_swings(b, false)
	var off_swings := _count_swings(b, true)
	if main_swings < 10 or off_swings < 10:
		_fail("test setup: too few swings to measure (main %d, off %d)" % [main_swings, off_swings])
		return
	var measured := float(off_swings) / float(main_swings)
	var expected := float(b.player_swing_ms) / float(b.offhand_swing_ms)
	print("  %d ticks: main %d landed, off %d landed -> ratio %.2f (intervals predict %.2f)"
		% [ticks, main_swings, off_swings, measured, expected])
	if absf(measured - expected) > expected * 0.35:
		_fail("the off hand landed %d swings to the main hand's %d (ratio %.2f) but its own interval predicts %.2f — the two hands are not on independent clocks"
			% [off_swings, main_swings, measured, expected])


# --- 3. the reported bug: a main-hand landing must not reset the off hand --------

## ⚠️  THIS IS JAN'S BUG, ASSERTED DIRECTLY. The port alternated hands on one clock, so
## landing a main-hand blow handed the turn to the off hand and restarted its arc — the
## screen's off-hand ring never once ran a full sweep of its own.
##
## The assertion is on the CLOCK, not on the arc: run the off-hand clock part way, land a
## main-hand swing, and the off-hand elapsed count must not have moved.
func _test_a_main_hand_landing_does_not_reset_the_offhand() -> void:
	var s = _hero()
	var b := _rig(s)
	if b == null:
		return
	b.offhand_swing_ms = 5000
	b.player_swing_ms = 1000
	b.player_swing_elapsed = 999.0
	b.offhand_swing_elapsed = 2500.0
	# One tick is enough for the main-hand clock to expire and land a swing.
	b.tick(100.0, s, _resolve(s))
	if b.offhand_swing_elapsed < 2500.0:
		_fail("landing a MAIN-hand blow reset the off-hand clock (2500 -> %.0f ms) — the two timers are still linked"
			% b.offhand_swing_elapsed)
	if b.player_swing_elapsed >= 1000.0:
		_fail("the main-hand clock did not expire in the tick under test (%.0f ms)" % b.player_swing_elapsed)
	# And the reverse: an off-hand landing must not touch the main-hand clock either.
	b.player_swing_ms = 5000
	b.offhand_swing_ms = 1000
	b.player_swing_elapsed = 2500.0
	b.offhand_swing_elapsed = 999.0
	b.tick(100.0, s, _resolve(s))
	if b.player_swing_elapsed < 2500.0:
		_fail("landing an OFF-hand blow reset the main-hand clock (2500 -> %.0f ms)"
			% b.player_swing_elapsed)


# --- 4. one weapon is one clock -------------------------------------------------

## A hero with a single weapon has no off-hand clock at all, and nothing must invent one:
## the tick runs one swing and the off-hand arc stays hidden.
func _test_a_single_weapon_runs_one_clock() -> void:
	var s = _hero(MAIN_WEAPON, "")
	var b := _rig(s)
	if b == null:
		return
	if b.offhand_swing_ms != 0:
		_fail("a hero with no second weapon has an off-hand interval (%d ms)" % b.offhand_swing_ms)
		return
	var ticks := 0
	while ticks < 300 and not b.ended:
		b.tick(100.0, s, _resolve(s))
		ticks += 1
	if _count_swings(b, true) > 0:
		_fail("a single-weapon hero landed %d OFF-hand swings" % _count_swings(b, true))
	if _count_swings(b, false) < 5:
		_fail("test setup: a single-weapon hero landed only %d swings in %d ticks"
			% [_count_swings(b, false), ticks])


# --- 5. two arcs, two clocks ----------------------------------------------------

## The screen half of the bug. `_arc_offhand` used to be driven by
## `battle.player_swing_elapsed` — the main hand's number — divided by the off-hand's
## interval, so the two rings always swept together. Set the two clocks to DIFFERENT points
## and the two arcs must show different fills; swap them and the arcs must swap.
func _test_the_two_arcs_are_drawn_from_different_clocks() -> void:
	var s = _hero()
	var screen: ArenaScreen = ArenaScreen.new(_data, _gen, _loot, s, _resolve(s))
	root.add_child(screen)
	if screen._mana_track == null:
		screen._build()
	if not screen.start(s, _resolve(s)):
		_fail("the arena could not start a fight")
		return
	var b = screen.battle
	b.enemy_hp = DUMMY_HP
	b.enemy_max_hp = DUMMY_HP
	b.hero_hp = DUMMY_HP
	b.hero_max_hp = DUMMY_HP
	b.player_swing_ms = 2000
	b.offhand_swing_ms = 1000
	# The off-hand arc is hidden by `render()` when there is no off hand; here there is one.
	screen._arc_offhand.visible = true

	# The main hand is 4/5 through its swing, the off hand has just landed.
	b.player_swing_elapsed = 1600.0
	b.offhand_swing_elapsed = 0.0
	screen._tick_accumulator = 0.0
	screen._smooth_update()
	var main_a: float = screen._arc_player.value
	var off_a: float = screen._arc_offhand.value

	# Now the reverse. If the two arcs read one clock these two states are INDISTINGUISHABLE
	# (the same elapsed count drives both), so this is the assertion that catches it.
	b.player_swing_elapsed = 0.0
	b.offhand_swing_elapsed = 1600.0
	screen._tick_accumulator = 0.0
	screen._smooth_update()
	var main_b: float = screen._arc_player.value
	var off_b: float = screen._arc_offhand.value
	print("  arcs (main, off): state A (%.2f, %.2f) -> state B (%.2f, %.2f)"
		% [main_a, off_a, main_b, off_b])

	if absf(main_a - off_a) < 0.05:
		_fail("the two arcs show the same fill (%.2f / %.2f) with the clocks 1600/0 ms apart — the off-hand arc is reading the main-hand clock"
			% [main_a, off_a])
	if absf(main_b - off_b) < 0.05:
		_fail("the two arcs still show the same fill (%.2f / %.2f) after the clocks were swapped"
			% [main_b, off_b])
	# A full ring must be the hand that just landed, and only that one.
	if main_b > 0.05 or off_a > 0.05:
		_fail("a hand that just landed does not start its arc from zero (main B %.2f, off A %.2f)"
			% [main_b, off_a])
	screen.queue_free()


# --- 6. the exception: a SKILL restarts both ------------------------------------

## Jan's own carve-out: "až na výjimky, kdy třeba nějaký SKILL záměrně resetuje oba timery."
## `_reset_swing_timers()` is that exception and it is the ONLY place allowed to zero both.
## All three ways a Whirlwind can end go through it, and Double Swing spends both swings.
func _test_a_skill_resets_both_clocks() -> void:
	var s = _hero(MAIN_WEAPON, OFF_WEAPON, "barbarian")
	s.data["talentLevels"] = {"barbarian_whirlwind": 1, "barbarian_doubleSwing": 1}
	var b := _rig(s)
	if b == null:
		return

	# --- Whirlwind START: the flurry replaces the hero's swings, both hands'.
	b.player_swing_elapsed = 900.0
	b.offhand_swing_elapsed = 400.0
	b.start_whirlwind(["left", "right"], 1500)
	if b.player_swing_elapsed != 0.0 or b.offhand_swing_elapsed != 0.0:
		_fail("starting a flurry did not restart both clocks (main %.0f, off %.0f)"
			% [b.player_swing_elapsed, b.offhand_swing_elapsed])

	# --- Whirlwind COMPLETE: press both keys correctly.
	b.player_swing_elapsed = 900.0
	b.offhand_swing_elapsed = 400.0
	b.answer_whirlwind("left", s, _resolve(s))
	var done: Dictionary = b.answer_whirlwind("right", s, _resolve(s))
	if str(done.get("result", "")) != "strike" or b.whirlwind_open():
		_fail("test setup: the flurry did not complete (%s, open=%s)"
			% [str(done.get("result", "")), str(b.whirlwind_open())])
	if b.player_swing_elapsed != 0.0 or b.offhand_swing_elapsed != 0.0:
		_fail("a COMPLETED flurry did not restart both clocks (main %.0f, off %.0f)"
			% [b.player_swing_elapsed, b.offhand_swing_elapsed])

	# --- Whirlwind FAIL (a wrong key): same reset, because the strikes were still spent.
	b.start_whirlwind(["left", "right"], 1500)
	b.player_swing_elapsed = 900.0
	b.offhand_swing_elapsed = 400.0
	var wrong: Dictionary = b.answer_whirlwind("cross", s, _resolve(s))
	if str(wrong.get("result", "")) != "fail":
		_fail("test setup: a wrong key did not fail the flurry (%s)" % str(wrong.get("result", "")))
	if b.player_swing_elapsed != 0.0 or b.offhand_swing_elapsed != 0.0:
		_fail("a BROKEN flurry did not restart both clocks (main %.0f, off %.0f)"
			% [b.player_swing_elapsed, b.offhand_swing_elapsed])

	# --- Whirlwind TIMEOUT: the deadline running out is the same failure.
	#
	# ⚠️  Asserted through the CLOCK, not through the tick's side effect: the timeout is
	# resolved INSIDE `tick()`, and that same tick then advances both clocks by its own
	# delta (900 -> 0 -> +300). Asserting `== 0.0` after a tick would be asserting that the
	# tick stops advancing the clocks, which is the opposite of what is wanted.
	b.start_whirlwind(["left"], 1000)
	b.player_swing_elapsed = 900.0
	b.offhand_swing_elapsed = 400.0
	b.whirlwind_timeout()
	if b.whirlwind_open():
		_fail("test setup: the deadline did not end the flurry")
	if b.player_swing_elapsed != 0.0 or b.offhand_swing_elapsed != 0.0:
		_fail("a TIMED-OUT flurry did not restart both clocks (main %.0f, off %.0f)"
			% [b.player_swing_elapsed, b.offhand_swing_elapsed])
	# And the TICK really routes its own deadline through that same reset: a 100 ms deadline
	# and a 300 ms step must leave both clocks at exactly the step, i.e. the pre-timeout 900
	# and 400 were thrown away rather than carried.
	b.start_whirlwind(["left"], 100)
	b.player_swing_elapsed = 900.0
	b.offhand_swing_elapsed = 400.0
	b.tick(300.0, s, _resolve(s))
	if b.whirlwind_open():
		_fail("test setup: the flurry deadline did not end the flurry")
	if b.player_swing_elapsed != 300.0 or b.offhand_swing_elapsed != 300.0:
		_fail("the tick's own deadline timeout did not restart both clocks (main %.0f, off %.0f — expected 300/300)"
			% [b.player_swing_elapsed, b.offhand_swing_elapsed])

	# --- Double Swing: both weapons swing at once, so both clocks are spent by the cast.
	b.player_swing_elapsed = 900.0
	b.offhand_swing_elapsed = 400.0
	b.enemy_hp = DUMMY_HP
	PlayerSpells.cast(b, "doubleSwing", s, _resolve(s), _data, _rng())
	if b.player_swing_elapsed != 0.0 or b.offhand_swing_elapsed != 0.0:
		_fail("Double Swing did not spend both swings (main %.0f, off %.0f)"
			% [b.player_swing_elapsed, b.offhand_swing_elapsed])


func _rng(seed_value: int = 4242) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng
