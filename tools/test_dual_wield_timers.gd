extends SceneTree
## tools/test_dual_wield_timers.gd — the dual wielder's ONE clock and the ALTERNATING hands.
##
## ⚠️  This file asserts the OPPOSITE of what it once did, on purpose, and the history is the
## reason it is written the way it is.
##
## The pair of weapons has had three shapes:
##   1. the PWA: one clock at the MAIN hand's pace, hands alternating
##      (`mb.offhandSwingMs = 0; // offhand nemá vlastní timer — sdílí hlavní (střídá se)`);
##   2. this port, branch `test/attack-dual-wield-speed`: two INDEPENDENT clocks, each hand at
##      its own weapon's pace. The previous version of THIS FILE was written to assert that;
##   3. now: one clock at the AVERAGE of the two intervals, hands STRICTLY ALTERNATING.
##
## Jan's report on (2) is what killed it: "Hráč má dvě zbraně, ale obě sekají ve stejnou dobu.
## Daleko uspokojivější je, když se zbraně plynule střídají." Two independent clocks are correct
## in the numbers and wrong on the screen: the arcs drift apart and the hero visibly strikes with
## both weapons on the same instant, which reads as one weapon hitting twice.
##
## (3) is Diablo 2's rule: with two weapons the engine replaces one hand's speed modifier with the
## AVERAGE of both (`d2r.org/mechanics/attack-speed`), and each attack alternates the hand that
## strikes.
##
## ⚠️  Every measured assertion reads the battle's own LOG, not the fields the rule just wrote. A
## test that compares a field against itself passes for the wrong reasons — that is how the
## averaging bug survived the first version of this file.
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

## The two weapons, chosen for the WIDEST interval gap in the shipped data: the slowest one-hand
## axe against the fastest one-hand blade. Both are one-handed and both are on the barbarian's
## allowed list, so the pair is a legal dual wield.
const MAIN_WEAPON := "axe_axe"              # 1000 ms after the speed retune
const OFF_WEAPON := "blade_scimitar_nm"     # 400 ms
const DUMMY_HP := 10_000_000.0
const TICK_MS := 20.0

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

	_test_the_pair_swings_at_the_average()
	_test_the_hands_alternate()
	_test_there_is_no_second_clock()
	_test_a_single_weapon_runs_one_hand()
	_test_a_skill_restarts_the_beat_with_the_main_hand()

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


## A fight that cannot end, with the gap pinned at contact so no swing is discarded for distance.
## The enemy is a real one out of the act tables — its resistances and block roll are irrelevant
## here, only the BEAT is measured.
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


## The ORDER of the hands, in sequence, off the battle's own log. EVERY swing is counted, hits and
## whiffs alike (`HIT`, `CRIT`, `MISS`, `BLOCK`, `ENEMY EVASION DODGE`), because a missed blow is
## still a beat — counting only the landed ones would show a missed main hand as two off-hand
## blows in a row and the alternation test would fail on a coin flip.
##
## The off hand's entries carry the ` offhand` suffix `_resolve_player_hit` adds to all outcomes.
## Nothing here reads a clock: this is what the player sees.
func _swing_order(b: Battle) -> Array:
	var order: Array = []
	for entry in b.log:
		var kind := str(entry.get("kind", ""))
		var is_swing := kind.begins_with("HIT") or kind.begins_with("CRIT") \
			or kind.begins_with("MISS") or kind.begins_with("BLOCK") \
			or kind.begins_with("ENEMY EVASION DODGE")
		if not is_swing:
			continue
		order.append("off" if kind.ends_with("offhand") else "main")
	return order


# --- 1. the pair beats at the HARMONIC mean of the two hands ---------------------

## The hands do not each keep their own pace, the PAIR beats at 1/T = 1/T_main + 1/T_off — both
## rates SUMMED. Jan's second report: "každá čeká na svůj plný swing … i když jsou to jednoruční
## zbraně, tak se chovají jako velmi pomalé zbraně." An AVERAGE halves each hand's rate; the
## harmonic mean keeps it, so two identical blades really do swing at their own speed.
## The off hand's own number is still carried, as INFORMATION for the HUD, not as a clock.
func _test_the_pair_swings_at_the_average() -> void:
	var s = _hero()
	var b := _rig(s)
	if b == null:
		return
	var find := _resolve(s)
	var dex_total := int(s.hero().get("attrDex", 0)) \
		+ Progression._equip_attr(s.equip(), find, "dex")
	var gloves: Dictionary = find.call(s.equip().get("gloves"))
	var glove_ias := int(gloves.get("ias", 0)) if not gloves.is_empty() else 0
	var main_item: Dictionary = _data.item(MAIN_WEAPON)
	var off_item: Dictionary = _data.item(OFF_WEAPON)
	var want_main := Progression.swing_time(b.rng, main_item, dex_total, glove_ias,
		s.data.get("_speedBoostPct", 0.0))
	var want_off := Progression.swing_time(b.rng, off_item, dex_total, glove_ias, 0.0)
	var want_pair := maxi(150, int(round(1.0 / (1.0 / float(want_main) + 1.0 / float(want_off)))))
	print("  intervals: main %d ms (%s), off %d ms (%s) -> pair %d ms (rates summed)"
		% [want_main, MAIN_WEAPON, want_off, OFF_WEAPON, want_pair])

	if not b.dual_swing:
		_fail("a second weapon in the off hand must arm the alternation (dual_swing is false)")
		return
	if b.player_swing_ms != want_pair:
		_fail("the pair must beat at the harmonic mean of the two hands: want %d ms, got %d ms"
			% [want_pair, b.player_swing_ms])
	if b.offhand_swing_ms != want_off:
		_fail("the off hand's own interval must still be carried: want %d ms, got %d ms"
			% [want_off, b.offhand_swing_ms])
	if b.player_swing_ms >= want_off:
		_fail("the pair must be FASTER than its fastest weapon, not slower: %d ms vs %d ms off hand"
			% [b.player_swing_ms, want_off])


# --- 2. the hands strictly ALTERNATE ---------------------------------------------

## The rule Jan asked for, and the one the previous shape broke: never two blows from the same
## hand in a row, and never both hands on one beat. Measured off the log over ~30 beats.
func _test_the_hands_alternate() -> void:
	var s = _hero()
	var b := _rig(s, 4242)
	if b == null:
		return
	var guard := 0
	while guard < 6000 and b.log.size() < 40:
		guard += 1
		b.tick(TICK_MS, s, _resolve(s))
		if b.ended:
			break
	var order := _swing_order(b)
	if order.size() < 6:
		_fail("the pair must land several blows, got %d" % order.size())
		return
	var flips := 0
	for i in range(1, order.size()):
		if order[i] != order[i - 1]:
			flips += 1
	print("  order: %s" % str(order))
	if flips != order.size() - 1:
		_fail("the hands must ALTERNATE on every beat, got %s" % str(order))
	var main_n := 0
	var off_n := 0
	for h in order:
		if h == "main":
			main_n += 1
		else:
			off_n += 1
	if absi(main_n - off_n) > 1:
		_fail("one clock means an even split: main %d vs off %d" % [main_n, off_n])


# --- 3. there is no second clock -------------------------------------------------

## `offhand_swing_elapsed` is kept only so nothing that pokes it can break: if it ever starts
## advancing again, a screen somewhere could draw a second arc off it.
func _test_there_is_no_second_clock() -> void:
	var s = _hero()
	var b := _rig(s, 77)
	if b == null:
		return
	for _i in 60:
		b.tick(TICK_MS, s, _resolve(s))
		if b.ended:
			break
	if b.offhand_swing_elapsed != 0.0:
		_fail("the off-hand clock must stay dead, got %.1f ms" % b.offhand_swing_elapsed)
	if b.player_swing_elapsed < 0.0 or b.player_swing_elapsed >= float(b.player_swing_ms):
		_fail("the pair's clock must stay inside one interval: %.1f of %d ms"
			% [b.player_swing_elapsed, b.player_swing_ms])


# --- 4. one weapon, one hand -----------------------------------------------------

## Without a second weapon the same clock runs at the main weapon's own pace and EVERY blow is a
## main-hand blow — a shield or an empty off hand must not alternate with anything.
func _test_a_single_weapon_runs_one_hand() -> void:
	var s = _hero(MAIN_WEAPON, "")
	var b := _rig(s, 31337)
	if b == null:
		return
	if b.dual_swing:
		_fail("a lone weapon must NOT arm the alternation")
	var find := _resolve(s)
	var dex_total := int(s.hero().get("attrDex", 0)) \
		+ Progression._equip_attr(s.equip(), find, "dex")
	var gloves: Dictionary = find.call(s.equip().get("gloves"))
	var glove_ias := int(gloves.get("ias", 0)) if not gloves.is_empty() else 0
	var want := Progression.swing_time(b.rng, _data.item(MAIN_WEAPON), dex_total, glove_ias,
		s.data.get("_speedBoostPct", 0.0))
	if b.player_swing_ms != want:
		_fail("a lone weapon must swing at its own interval: want %d ms, got %d ms"
			% [want, b.player_swing_ms])
	if b.offhand_swing_ms != 0:
		_fail("without a second weapon the off-hand interval must be 0, got %d"
			% b.offhand_swing_ms)
	for _i in 400:
		b.tick(TICK_MS, s, _resolve(s))
		if b.ended:
			break
	var order := _swing_order(b)
	if order.is_empty():
		_fail("the lone weapon never landed a blow")
	for h in order:
		if h != "main":
			_fail("a lone weapon must never swing the off hand")
			break


# --- 5. a SKILL restarts the beat, and with the MAIN hand ------------------------

## `_reset_swing_timers()` is the one exception the rule allows: a flurry (or any skill that says
## so) restarts the beat, and the order starts over with the main hand so the player's next blow
## is the one the skill was paid for.
func _test_a_skill_restarts_the_beat_with_the_main_hand() -> void:
	var s = _hero()
	var b := _rig(s, 5)
	if b == null:
		return
	s.data["talentLevels"] = {"barbarian_whirlwind": 1, "barbarian_doubleSwing": 1}
	b.next_hand_off = true
	b.player_swing_elapsed = 123.0
	b.start_whirlwind(["left", "right"], 1500)
	if b.player_swing_elapsed != 0.0 or b.offhand_swing_elapsed != 0.0:
		_fail("starting a flurry must restart the beat (main %.0f, off %.0f)"
			% [b.player_swing_elapsed, b.offhand_swing_elapsed])
	if b.next_hand_off:
		_fail("after a flurry the pair must start over with the MAIN hand")
	# Double Swing spends the pair's swing: the beat restarts too.
	b.player_swing_elapsed = 900.0
	b.enemy_hp = DUMMY_HP
	PlayerSpells.cast(b, "doubleSwing", s, _resolve(s), _data, _rng())
	if b.player_swing_elapsed != 0.0:
		_fail("Double Swing must spend the pair's swing (elapsed %.0f ms)"
			% b.player_swing_elapsed)


func _rng(seed_value: int = 4242) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng
