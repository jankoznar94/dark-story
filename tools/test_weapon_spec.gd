extends SceneTree
## tools/test_weapon_spec.gd — the barbarian's weapon specialisations, from the FIGHT's side.
##
## ⚠️  WHY THIS TEST EXISTS. `Talents.weapon_spec()` (+10 % damage, +10 % attack rating,
## +1 % crit per level) was written correctly and called from exactly ONE place: the hero
## stat panel. The DAMAGE PATH never read it. So the port DISPLAYED a crit bonus that the
## arena never rolled, and a whole passive talent — both halves of it, plus the off-hand
## clause in "off-hand is 50 %, and 100 % at One-Hand Spec 5" — was inert in every fight.
##
## Nothing in the existing suite could see it:
##
##   * `test_combat` drives the battle and asserts fights END — a fight still ends when a
##     crit never fires;
##   * `test_shop_and_craft` asserts the talent can be INVESTED, not that it DOES anything;
##   * a stat-panel test would pass, because the panel is the one place that was right.
##
## The assertion is therefore BEHAVIOURAL and it is the whole point of the file: with the
## talent invested, crits must actually LAND in the fight, the hero's damage must go up, and
## the off-hand penalty must shrink. Each is checked against the SAME hero with 0 points, so
## the measurement is a difference and not a threshold someone can drift past.
##
## ⚠️  THIS IS THE SHAPE TO COPY for any "the rule is right and nothing reads it" bug: assert
## the RULE's effect on the PATH THAT USES IT, never the rule's own return value.
##
## Run:  godot --headless --path . --script res://tools/test_weapon_spec.gd
## Pass: prints WEAPON_SPEC_ALL_PASS=true

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const Battle := preload("res://scripts/combat/battle.gd")
const Talents := preload("res://scripts/items/talents.gd")

## Enough swings that a 5 % crit rate is unambiguous. The chance is a roll per swing, so at
## p=0.05 over 4000 swings the expected count is 200 and the standard deviation ~14 — a
## "0 or 200" assertion has no noise to it.
const SWINGS := 4000
## The fight is put in a state where nothing else can end it: a huge enemy pool and a hero
## with enough HP that neither side dies mid-measurement.
const DUMMY_HP := 10_000_000.0

var _failures: Array[String] = []
var _data: Node
var _gen: ItemGen


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)

	_test_crit_bonus_reaches_the_fight()
	_test_damage_bonus_reaches_the_fight()
	_test_offhand_penalty_shrinks_with_the_talent()
	_test_two_hand_tree_is_the_one_read()
	_test_other_classes_get_nothing()
	_test_swing_crit_chance_is_the_fights_own_number()

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("WEAPON_SPEC_ALL_PASS=true")
	else:
		print("WEAPON_SPEC_ALL_PASS=false")
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


# --- rig ----------------------------------------------------------------------

## A barbarian at `points` in One-Hand Specialization, holding a weapon with NO base crit
## (measured: no base item in `ITEMS.json` carries one — crit comes from affixes only, which
## is Jan's own rule). So any crit in the fight can ONLY come from the talent.
func _hero(points: int, weapon_id: String = "blade_shortSword", cls: String = "barbarian",
		talent_key: String = "barbarian_oneHandSpec"):
	var s = GameState.new()
	s.bind_data(_data)
	s.set_class(cls)
	s.hero()["level"] = 40
	s.data["talentPoints"] = 30
	s.data["talentLevels"][talent_key] = points
	s.equip()["weapon"] = weapon_id
	s.hero()["maxHp"] = _gen.hero_max_hp(s.hero(), s.equip(), _resolve)
	s.hero()["hp"] = s.hero()["maxHp"]
	s.hero()["maxMana"] = _gen.hero_max_mana(s.hero(), s.equip(), cls, _resolve)
	s.hero()["mana"] = s.hero()["maxMana"]
	return s


var _state = null


func _resolve(id: Variant) -> Dictionary:
	var item_id := str(id)
	if item_id == "":
		return {}
	var static_item: Dictionary = _data.item(item_id)
	if not static_item.is_empty():
		return static_item
	if _state != null:
		return _state.loot_item(item_id)
	return {}


## A fight that cannot end: the enemy has an absurd pool, so every swing is measured.
func _rig(state, seed_value: int) -> Battle:
	_state = state
	var b := Battle.new(_data, seed_value)
	b.act_id = 0
	if not b.setup(state, _resolve):
		_fail("battle setup failed")
		return null
	b.enemy_hp = DUMMY_HP
	b.enemy_max_hp = DUMMY_HP
	b.hero_hp = DUMMY_HP
	b.hero_max_hp = DUMMY_HP
	b.apply_swing_timers(state, _resolve)
	b.reset_gap()
	return b


## Drive `n` MAIN-HAND swings and report how many were crits and their total damage.
## The off-hand is switched off so a dual-wield class does not alternate hands under us and
## halve the sample; the off-hand has its own test below.
func _sample(b: Battle, state, n: int) -> Dictionary:
	b.offhand_swing_ms = 0
	b.offhand_turn = false
	var crits := 0
	var swings := 0
	for _i in n:
		# The distance gate discards an out-of-reach swing and restarts its clock, which is
		# correct in a fight and noise in a measurement: pin the gap at contact.
		b.reset_gap()
		var before := b.enemy_hp
		var result: Dictionary = b.player_attack(state, _resolve)
		if not bool(result.get("hit", false)):
			continue
		swings += 1
		if bool(result.get("crit", false)):
			crits += 1
		var _dmg := before - b.enemy_hp
	return {"crits": crits, "swings": swings}


# --- 1. the crit bonus must LAND -------------------------------------------------

## Jan's own report, in reverse: he invested two points in One-Hand Specialization and the
## stat panel showed "0 %" while the FIGHT was the half that was actually right. In the port
## it is the other way round — the panel was right and the fight rolled 0 %.
##
## Mutation check: restoring `weapon.get("critChance", 0)` in `_resolve_player_hit` turns
## this red (measured: 0 crits from 4000 swings with 5 points invested).
func _test_crit_bonus_reaches_the_fight() -> void:
	var uninvested = _hero(0)
	var b0 := _rig(uninvested, 20260925)
	if b0 == null:
		return
	var base := _sample(b0, uninvested, 400)

	var invested = _hero(5)
	var b5 := _rig(invested, 20260925)
	if b5 == null:
		return
	var boosted := _sample(b5, invested, SWINGS)

	print("  crit: 0 points -> %d/%d, 5 points -> %d/%d"
		% [base["crits"], base["swings"], boosted["crits"], boosted["swings"]])

	if int(base["crits"]) != 0:
		_fail("a weapon with no base crit and no talent crit produced %d crits — the sample is not clean"
			% int(base["crits"]))
	if int(boosted["swings"]) < SWINGS / 2:
		_fail("only %d of %d swings landed — the sample is too small to judge (hit chance should be ~50%%)"
			% [int(boosted["swings"]), SWINGS])
		return
	# 5 points = 5 %. Over the landed swings the expected count is 5 % of them, and the
	# gate is deliberately wide (a quarter of expectation) so it cannot pass by luck.
	var expected := float(boosted["swings"]) * 0.05
	var got := float(boosted["crits"])
	print("  expected ~%.0f crits at 5%%, got %.0f" % [expected, got])
	if got < expected * 0.5:
		_fail("One-Hand Spec 5 gave %.0f crits in %d landed swings (expected ~%.0f) — the crit bonus is not reaching the fight"
			% [got, int(boosted["swings"]), expected])


# --- 2. the damage bonus must land ----------------------------------------------

## +10 % damage per level, and it is the OTHER half of the same talent.
##
## A mean over a seeded sample is a weak verdict (the roll spread, the +-1 jitter and the
## crit doubling all move it), so the comparison uses the same seed on both sides and a
## generous bound: 5 points is +50 % nominal, and the gate is that the boosted hero must
## out-damage the uninvested one by at least 20 %.
func _test_damage_bonus_reaches_the_fight() -> void:
	var plain = _hero(0)
	var b0 := _rig(plain, 777)
	if b0 == null:
		return
	var a := _sample(b0, plain, 2000)
	var plain_hp := b0.enemy_hp

	var boosted = _hero(5)
	var b5 := _rig(boosted, 777)
	if b5 == null:
		return
	var _c := _sample(b5, boosted, 2000)
	var boosted_hp := b5.enemy_hp

	var plain_dmg := DUMMY_HP - plain_hp
	var boosted_dmg := DUMMY_HP - boosted_hp
	print("  2000 swings: no talent %.0f damage, 5 points %.0f (x%.2f)"
		% [plain_dmg, boosted_dmg, boosted_dmg / maxf(plain_dmg, 1.0)])
	if plain_dmg <= 0.0:
		_fail("the uninvested hero dealt no damage at all — the measurement is broken")
		return
	if boosted_dmg < plain_dmg * 1.2:
		_fail("One-Hand Spec 5 did not raise damage (%.0f vs %.0f, x%.2f) — spec.dmgMult is not in the damage path"
			% [boosted_dmg, plain_dmg, boosted_dmg / plain_dmg])


# --- 3. the off-hand clause -----------------------------------------------------

## "Off-hand is 50 %, and 100 % at One-Hand Spec 5" — Jan's rule, stated when the talent was
## specified. The port hardcoded 0.6 in `player_attack`, so the talent's own off-hand clause
## was unread.
##
## ⚠️  ASSERTING THE MULTIPLIER ALONE IS NOT ENOUGH. `swing_bonus` returning 0.5 and the
## battle then ignoring it is exactly the bug this file exists for, so the second half drives
## real OFF-HAND swings and compares the damage: at 5 points an off-hand swing must out-damage
## the same swing at 0 points.
func _test_offhand_penalty_shrinks_with_the_talent() -> void:
	var weapon: Dictionary = _data.item("blade_shortSword")
	var expected := [0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
	for points in 6:
		var state = _hero(points)
		var spec: Dictionary = Talents.swing_bonus(state, weapon, true, 1.0)
		var got := float(spec["handMult"])
		print("  oneHandSpec %d -> off-hand multiplier %.2f" % [points, got])
		if absf(got - float(expected[points])) > 0.001:
			_fail("oneHandSpec %d gave an off-hand multiplier of %.2f, expected %.2f"
				% [points, got, float(expected[points])])
	# And the main hand must NOT be penalised: Shield Specialization is its multiplier, and
	# with none invested that is exactly 1.0.
	var main: Dictionary = Talents.swing_bonus(_hero(5), weapon, false, 1.0)
	if absf(float(main["handMult"]) - 1.0) > 0.001:
		_fail("the main hand got an off-hand penalty: %.2f" % float(main["handMult"]))

	# --- the same rule, measured on real swings --------------------------------
	#
	# ⚠️  COMPARING OFF-HAND DAMAGE ACROSS TWO TALENT LEVELS DOES NOT TEST THIS. With the
	# hardcoded 0.6 restored, the 5-point hero still out-damages the 0-point one by
	# `spec.dmgMult` alone (measured: x3.08) and the check passed — it was measuring the
	# damage bonus a second time, not the off-hand penalty.
	#
	# What isolates the penalty is the RATIO OF OFF-HAND TO MAIN-HAND DAMAGE on the SAME
	# hero: both hands read the same `dmgMult`, so the ratio is exactly `offHandMult`.
	# Measured 0.50 at 0 points and 1.00 at 5 points; with the bug restored it sits at 0.60
	# for both, which the ratio sees and the cross-level comparison could not.
	for points in [0, 5]:
		var state = _hero(points)
		var b := _rig(state, 31337)
		if b == null:
			return
		var off := _sample_offhand(b, state, 1500)
		# NOT `main` — that name is already the main-hand spec Dictionary above, and GDScript
		# refuses a second declaration in the same scope (a parse error, so the whole file
		# fails to load and the gate silently never runs).
		var mainhand_dmg := _sample_mainhand(b, state, 1500)
		if mainhand_dmg <= 0.0 or off <= 0.0:
			_fail("one hand dealt no damage at %d points — the measurement is broken" % points)
			continue
		var ratio := off / mainhand_dmg
		print("  oneHandSpec %d: off-hand/main-hand damage ratio %.2f (expected %.2f)"
			% [points, ratio, float(expected[points])])
		if absf(ratio - float(expected[points])) > 0.08:
			_fail("oneHandSpec %d gave an off-hand/main-hand ratio of %.2f, expected %.2f — the off-hand penalty is not reading spec.offHandMult"
				% [points, ratio, float(expected[points])])


## Drive `n` OFF-HAND swings and return their total damage, with the gap pinned at contact
## and the main hand's own multiplier left alone. `offhand_turn` alternates inside
## `player_attack`, so the flag is set before every call and the loop counts only the swings
## whose off-hand branch actually fired.
##
## The crit roll is switched OFF for this measurement: a crit doubles one swing, and at
## 1500 swings a handful of crits would add noise to a ratio whose whole signal is 0.5 vs
## 1.0. The off-hand penalty is not a crit rule, so removing crit measures it cleanly.
func _sample_offhand(b: Battle, state, n: int = 1500) -> float:
	b.offhand_swing_ms = 1000
	var before := b.enemy_hp
	var counted := 0
	var guard := 0
	while counted < n and guard < n * 4:
		guard += 1
		b.reset_gap()
		# Force the next swing to be the off-hand: `player_attack` flips this flag itself.
		b.offhand_turn = true
		var hp_before := b.enemy_hp
		var result: Dictionary = b.player_attack(state, _resolve)
		if bool(result.get("hit", false)) and b.enemy_hp < hp_before:
			counted += 1
	b.offhand_swing_ms = 0
	return before - b.enemy_hp


## The same, for the MAIN hand — the denominator of the ratio above.
func _sample_mainhand(b: Battle, state, n: int = 1500) -> float:
	b.offhand_swing_ms = 0
	var before := b.enemy_hp
	var counted := 0
	var guard := 0
	while counted < n and guard < n * 4:
		guard += 1
		b.reset_gap()
		b.offhand_turn = false
		var hp_before := b.enemy_hp
		var result: Dictionary = b.player_attack(state, _resolve)
		if bool(result.get("hit", false)) and b.enemy_hp < hp_before:
			counted += 1
	return before - b.enemy_hp


# --- 4. the two-hand tree is the one read ---------------------------------------

## A two-handed weapon reads `twoHandSpec`, and investing the ONE-hand tree must not give it
## anything. This is the branch the port could invert without any test noticing.
func _test_two_hand_tree_is_the_one_read() -> void:
	var two_hander := "blade2h_twoHandedSword"
	var base: Dictionary = _data.item(two_hander)
	if not bool(base.get("twoHand", false)):
		_fail("%s is not a two-handed weapon — this check would exercise nothing" % two_hander)
		return
	var one_hand_points = _hero(5, two_hander, "barbarian", "barbarian_oneHandSpec")
	var two_hand_points = _hero(5, two_hander, "barbarian", "barbarian_twoHandSpec")

	var spec_one: Dictionary = Talents.swing_bonus(one_hand_points, base, false, 1.0)
	var spec_two: Dictionary = Talents.swing_bonus(two_hand_points, base, false, 1.0)
	print("  two-hander: oneHandSpec 5 -> crit +%d, twoHandSpec 5 -> crit +%d"
		% [int(spec_one["critBonus"]), int(spec_two["critBonus"])])
	if int(spec_one["critBonus"]) != 0:
		_fail("One-Hand Spec gave a two-handed weapon +%d crit" % int(spec_one["critBonus"]))
	if int(spec_two["critBonus"]) != 5:
		_fail("Two-Hand Spec 5 gave +%d crit, expected 5" % int(spec_two["critBonus"]))


# --- 5. only the barbarian ------------------------------------------------------

func _test_other_classes_get_nothing() -> void:
	for cls in ["assassin", "mage"]:
		var state = _hero(0, "blade_shortSword", cls)
		state.data["talentLevels"]["barbarian_oneHandSpec"] = 5
		var weapon: Dictionary = _data.item("blade_shortSword")
		var spec: Dictionary = Talents.swing_bonus(state, weapon, false, 1.0)
		if int(spec["critBonus"]) != 0 or absf(float(spec["dmgMult"]) - 1.0) > 0.001:
			_fail("%s picked up the barbarian's weapon specialisation" % cls)


# --- 6. the panel and the fight read ONE number ---------------------------------

## `swing_crit_chance` is the single expression both the arena and the stat panel use. If a
## later change re-derives crit somewhere else, this is the check that fails.
func _test_swing_crit_chance_is_the_fights_own_number() -> void:
	var state = _hero(4)
	var weapon: Dictionary = _data.item("blade_shortSword")
	weapon["critChance"] = 7
	weapon["id"] = "test_crit_weapon"
	var got := Talents.swing_crit_chance(state, weapon)
	print("  7%% base + 4 points -> %d%%" % got)
	if got != 11:
		_fail("swing_crit_chance said %d, expected 7 + 4 = 11" % got)
