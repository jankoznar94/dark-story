extends SceneTree
## tools/test_combat.gd — the balance and progression of the ported combat.
##
## This is the test that could not exist before the port: in the PWA the same numbers
## lived inside a 900-line requestAnimationFrame loop that also moved DOM nodes, so
## nothing about the combat was assertable. Here the fight is a RefCounted that ticks
## in 100 ms steps, so a whole encounter runs in a loop with no renderer.
##
## It asserts three kinds of thing, and the third is the one that matters:
##
##   1. SCALING — the formulas still produce the documented curve, not just "a number".
##      Normal zone 0 is x1.0 and zone 9 is x5.5; Nightmare starts where Normal ended;
##      monster levels chain 1-15 / 16-30 / 31-60 across the difficulties.
##   2. PACING — a fight between real monsters and a real hero terminates in a sane
##      number of ticks, on every act and every difficulty, and neither side wins
##      instantly or never.
##   3. PROGRESSION — after a win the fight counter moves, after 10 fights the zone
##      advances, after a boss the act flag is set and the zone resets, and XP levels
##      the hero up at the documented thresholds.
##
## Run:  godot --headless --path . --script res://tools/test_combat.gd
## Pass: prints COMBAT_ALL_PASS=true

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const Battle := preload("res://scripts/combat/battle.gd")
const Progression := preload("res://scripts/combat/progression.gd")

var _failures: Array[String] = []
var _data: Node
var _gen: ItemGen
var _state
var _loot: LootSystem


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_loot = LootSystem.new(_data, _gen)

	_test_zone_scaling()
	_test_monster_levels()
	_test_xp_curve()
	_test_hit_chance()
	_test_swing_time()
	_test_fight_terminates()
	_test_progression_after_win()
	_test_boss_win()
	_test_unarmed_hero_loses_to_boss()
	_test_zone_advance()
	_test_pack_stats()

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("COMBAT_ALL_PASS=true")
	else:
		print("COMBAT_ALL_PASS=false")
	# Without this the SceneTree keeps running: the test prints its verdict and then
	# hangs until the CI timeout, which reads as a failing job rather than a pass.
	quit(0 if _failures.is_empty() else 1)


func _fresh_state(class_id: String = "barbarian", level: int = 1, difficulty: int = 0):
	var s = GameState.new()
	s.bind_data(_data)
	s.set_class(class_id)
	s.data["difficulty"] = difficulty
	s.hero()["level"] = level
	s.hero()["maxHp"] = _gen.hero_max_hp(s.hero(), s.equip(), _resolve)
	s.hero()["hp"] = s.hero()["maxHp"]
	return s


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


# --- 1. scaling --------------------------------------------------------------

## The difficulty curve is the whole progression system in one function, and the
## documented values are exact: if this drifts, every act is mis-tuned at once.
func _test_zone_scaling() -> void:
	var prog := Progression.new(_data)
	var cases := [
		# difficulty, zone, expected
		[0, 0, 1.0], [0, 9, 5.5],
		[1, 0, 5.5], [1, 9, 11.98],
		[2, 0, 12.0], [2, 9, 20.01],
	]
	for c in cases:
		var got := prog.zone_mult(int(c[1]), int(c[0]))
		if absf(got - float(c[2])) > 0.02:
			_fail("zone_mult(difficulty %d, zone %d) = %.2f, expected %.2f"
				% [int(c[0]), int(c[1]), got, float(c[2])])
	# Nightmare must start exactly where Normal ends, or the curve has a cliff.
	if absf(prog.zone_mult(0, 1) - prog.zone_mult(9, 0)) > 0.02:
		_fail("Nightmare does not start where Normal ends")


## Monster levels chain across difficulties: the band is per act per difficulty and
## the value inside the band follows how deep into the zone the player is.
func _test_monster_levels() -> void:
	var prog := Progression.new(_data)
	var first_normal := prog.monster_level(0, 0, 0)
	var last_hell := prog.monster_level(4, 9, 2)
	if first_normal != 1:
		_fail("first monster level should be 1, got %d" % first_normal)
	if last_hell < 55:
		_fail("hell act 5 should reach level 55+, got %d" % last_hell)
	# Every act, every difficulty: levels must rise with depth and never go backwards.
	for d in 3:
		for act_id in 5:
			var prev := -1
			for zone in prog.total_zones(act_id):
				var lv := prog.monster_level(act_id, zone, d)
				if lv < prev:
					_fail("monster level went backwards in act %d zone %d difficulty %d" % [act_id, zone, d])
				prev = lv
	# The bands must not overlap backwards across difficulties.
	if prog.monster_level(0, 0, 1) < prog.monster_level(4, 9, 0) - 3:
		_fail("Nightmare starts below where Normal ended")


## D2's XP penalty table. A monster 5 levels above gives full XP; 9 above gives ~2%.
func _test_xp_curve() -> void:
	var prog := Progression.new(_data)
	if absf(prog.xp_multiplier(10, 10) - 1.0) > 0.001:
		_fail("same level should give full XP")
	if absf(prog.xp_multiplier(10, 15) - 1.0) > 0.001:
		_fail("5 levels above should still give full XP")
	var nine_above := prog.xp_multiplier(10, 19)
	if nine_above > 0.03:
		_fail("9 levels above should be heavily penalised, got %.3f" % nine_above)
	var six_below := prog.xp_multiplier(10, 4)
	if six_below > 0.9 or six_below < 0.7:
		_fail("6 levels below should be ~0.81, got %.3f" % six_below)
	# Level thresholds: 40 XP for level 2, 80 for level 3.
	if prog.xp_needed(1) != 40 or prog.xp_needed(2) != 80 or prog.xp_needed(10) != 800:
		_fail("xp_needed thresholds are wrong: %d %d %d"
			% [prog.xp_needed(1), prog.xp_needed(2), prog.xp_needed(10)])


## D2's chance-to-hit, clamped to [5, 95]. Equal attack rating and defense means
## 200 * 0.5 * (10/20) = 50% — the formula is symmetric, so an even fight is a
## coin flip, not a near-certainty.
func _test_hit_chance() -> void:
	var prog := Progression.new(_data)
	var equal := prog.hit_chance(100, 100, 10, 10)
	if absf(equal - 50.0) > 0.5:
		_fail("an even fight should be a 50%% chance, got %.1f" % equal)
	var hopeless := prog.hit_chance(1, 10000, 1, 60)
	if hopeless < 5.0:
		_fail("hit chance must never fall below 5%%, got %.1f" % hopeless)
	var overwhelming := prog.hit_chance(100000, 1, 60, 1)
	if overwhelming > 95.0:
		_fail("hit chance must never exceed 95%%, got %.1f" % overwhelming)
	# More attack rating must never mean a worse chance.
	if prog.hit_chance(500, 100, 10, 10) < prog.hit_chance(200, 100, 10, 10):
		_fail("more attack rating gave a lower hit chance")


## Weapon speed: DEX and IAS both shorten a swing, and neither can take it below the
## hard floors (550 ms by DEX, 450 ms once IAS applies).
##
## The IAS numbers are the D2 diminishing curve as the PWA wrote it: a weapon with
## 100 IAS on a 2 s base lands at 1379 ms, not 1000 — the formula is
## ms * 100 / (100 + ias * 100 / (ias + 120)), so the bonus saturates near +120%.
func _test_swing_time() -> void:
	var rng := RandomNumberGenerator.new()
	var weapon := {"swingMs": 2000, "ias": 0}
	var base := Progression.swing_time(rng, weapon, 0)
	if base != 2000:
		_fail("a 2s weapon with no DEX should swing in 2000 ms, got %d" % base)
	var dexxy := Progression.swing_time(rng, weapon, 50)
	if dexxy >= base:
		_fail("DEX did not shorten the swing")
	var floored := Progression.swing_time(rng, weapon, 500)
	if floored != 550:
		_fail("DEX floor should be 550 ms, got %d" % floored)
	var fast := Progression.swing_time(rng, {"swingMs": 2000, "ias": 100}, 0)
	if fast != 1379:
		_fail("100 IAS on a 2s weapon should give 1379 ms (D2 diminishing), got %d" % fast)
	# More IAS must always mean a shorter swing, even if it saturates.
	var faster := Progression.swing_time(rng, {"swingMs": 2000, "ias": 200}, 0)
	if faster >= fast:
		_fail("doubling IAS did not shorten the swing further")
	var silly := Progression.swing_time(rng, {"swingMs": 2000, "ias": 100000}, 500)
	if silly != 450:
		_fail("IAS floor should be 450 ms, got %d" % silly)


# --- 2. pacing ---------------------------------------------------------------

## A fight has to END, in a sane number of ticks, for every act and difficulty. A
## fight that never resolves is the failure a "does it run" check cannot see: the loop
## keeps ticking, nothing happens, and the game looks frozen.
##
## It also has to be a fight: an enemy that dies in one tick, or a hero that dies in
## one tick, means the scaling is wrong even though the code "works".
func _test_fight_terminates() -> void:
	var checked := 0
	var min_ticks := 1 << 30
	var max_ticks := 0
	for difficulty in 3:
		for act_id in 5:
			_state = _fresh_state("barbarian", 1 + difficulty * 20 + act_id * 4, difficulty)
			var b := Battle.new(_data, 424242)
			b.act_id = act_id
			_state.data["locationProgress"][act_id] = 0
			_state.data["areaFightProgress"][act_id] = 0
			if not b.setup(_state, _resolve):
				_fail("setup failed for act %d difficulty %d" % [act_id, difficulty])
				continue
			b.apply_swing_timers(_state, _resolve)
			var ticks := _run(b, 4000)
			checked += 1
			min_ticks = mini(min_ticks, ticks)
			max_ticks = maxi(max_ticks, ticks)
			if not b.ended:
				_fail("fight in act %d difficulty %d never ended in 4000 ticks" % [act_id, difficulty])
			elif ticks < 3:
				_fail("fight in act %d difficulty %d ended in %d ticks - too fast to be a fight"
					% [act_id, difficulty, ticks])
	if checked != 15:
		_fail("expected to check 15 act/difficulty combinations, checked %d" % checked)
	print("  fights checked: %d, ticks %d-%d" % [checked, min_ticks, max_ticks])


## Drive one fight to its end. Returns the number of ticks it took.
func _run(b: Battle, limit: int) -> int:
	var ticks := 0
	while not b.ended and ticks < limit:
		b.tick(100.0, _state, _resolve)
		# The kill is deferred by one tick, the way the PWA deferred it by 300 ms.
		if b.pending_kill:
			b.tick(100.0, _state, _resolve)
		ticks += 1
	return ticks


# --- 3. progression ----------------------------------------------------------

## A normal win: the fight counter advances by exactly one, the hero gains XP and
## gold, and the zone does not move until ten fights are done.
func _test_progression_after_win() -> void:
	_state = _fresh_state("barbarian", 30, 0)
	var b := _win_one_fight(0, 0)
	if not b.won:
		_fail("the hero lost a fight they should win")
		return
	if int(_state.data["areaFightProgress"][0]) != 1:
		_fail("a win should advance the fight counter to 1, got %d"
			% int(_state.data["areaFightProgress"][0]))
	if int(_state.hero()["xp"]) <= 0:
		_fail("a win gave no XP")
	if int(_state.hero()["gold"]) <= 0:
		_fail("a win gave no gold")
	if int(_state.data["locationProgress"][0]) != 0:
		_fail("one win must not advance the zone")
	if int(_state.data["wins"]) != 1:
		_fail("the win was not counted")


## A boss win: the act flag flips, the zone AND the fight counter reset, and the XP
## is 150x the monster level rather than the normal 30x.
##
## The hero is GIVEN a weapon here. A level-60 hero with bare fists loses this fight,
## and that is correct: `mb.baseDmg` is set nowhere in the PWA, so its fallback in
## dealPlayerDamage is the live path — `2 + level * 0.8 + weapon dmg + STR * 0.3`,
## with no crit and no skill multipliers on a plain swing. Fists are 1-2 damage.
## A boss test that does not equip a weapon is testing the wrong thing.
func _test_boss_win() -> void:
	_state = _fresh_state("barbarian", 60, 0)
	_give_weapon(_state, "blade_shortSword")
	_state.data["locationProgress"][0] = 9
	_state.data["areaFightProgress"][0] = 0
	var b := Battle.new(_data, 99)
	b.act_id = 0
	if not b.setup(_state, _resolve):
		_fail("boss setup failed")
		return
	if not b.is_boss:
		_fail("zone 9 of a 10-zone act should be the boss zone")
		return
	b.apply_swing_timers(_state, _resolve)
	var before := int(_state.hero()["xp"])
	_run(b, 6000)
	if not b.won:
		_fail("the hero lost to the act 1 boss while armed at level 60")
		return
	if not bool(_state.data["bossesDefeated"][0][0]):
		_fail("the boss flag was not set")
	if int(_state.data["locationProgress"][0]) != 0:
		_fail("a boss win should reset the zone to 0")
	if int(_state.data["areaFightProgress"][0]) != 0:
		_fail("a boss win should reset the fight counter")
	if int(_state.hero()["xp"]) <= before:
		_fail("a boss gave no XP")
	if not _state.act_unlocked(1):
		_fail("act 2 did not unlock after the boss")


## A bare-handed hero must LOSE the boss fight. This pins the fallback damage path
## documented above, so if someone later "fixes" baseDmg to be non-zero the test says
## so instead of the balance silently changing.
func _test_unarmed_hero_loses_to_boss() -> void:
	_state = _fresh_state("barbarian", 60, 0)
	_state.data["locationProgress"][0] = 9
	_state.data["areaFightProgress"][0] = 0
	var b := Battle.new(_data, 99)
	b.act_id = 0
	if not b.setup(_state, _resolve):
		return
	b.apply_swing_timers(_state, _resolve)
	_run(b, 6000)
	if b.won:
		_fail("bare fists beat the act 1 boss at level 60 - the unarmed damage path changed")


## Ten fights finish a zone: the eleventh call to advance_stop moves the zone on and
## resets the fight counter. Before ten, it must not move.
func _test_zone_advance() -> void:
	_state = _fresh_state("barbarian", 30, 0)
	_state.data["areaFightProgress"][0] = 5
	var b := Battle.new(_data, 7)
	b.act_id = 0
	if b.advance_stop(_state):
		_fail("a half-finished zone advanced anyway")
	_state.data["areaFightProgress"][0] = 10
	if not b.advance_stop(_state):
		_fail("a finished zone did not advance")
	if int(_state.data["locationProgress"][0]) != 1:
		_fail("the zone should be 1 after finishing zone 0, got %d"
			% int(_state.data["locationProgress"][0]))
	if int(_state.data["areaFightProgress"][0]) != 0:
		_fail("advancing a zone must reset the fight counter")
	if _state.max_progress(0) != 1:
		_fail("_maxLocationProgress was not raised - unlocking would follow the player back down")
	# The last zone of an act is the boss zone and must NOT advance again.
	_state.data["locationProgress"][0] = 9
	_state.data["areaFightProgress"][0] = 10
	if b.advance_stop(_state):
		_fail("the boss zone advanced past the boss")


## Packs: a champion pack is three members, an elite pack is four with the LEADER
## LAST, and the pack must be worth more XP than a single monster.
func _test_pack_stats() -> void:
	_state = _fresh_state("barbarian", 30, 0)
	_state.data["locationProgress"][0] = 0
	_state.data["areaFightProgress"][0] = 4   # champion pack fight
	var champ := Battle.new(_data, 1234)
	champ.act_id = 0
	champ.setup(_state, _resolve)
	if not champ.is_pack:
		_fail("fight 5/10 should be a champion pack")
	elif champ.pack_size() != 3:
		_fail("a champion pack should have 3 members, got %d" % champ.pack_size())

	var elite_b := Battle.new(_data, 5678)
	elite_b.act_id = 0
	_state.data["areaFightProgress"][0] = 9   # elite pack fight
	elite_b.setup(_state, _resolve)
	if not elite_b.is_elite:
		_fail("fight 10/10 should be an elite fight")
	elif elite_b.pack_size() != 4:
		_fail("an elite pack should have 4 members (3 slaves + leader), got %d" % elite_b.pack_size())
	else:
		var last: Dictionary = elite_b.pack_members[elite_b.pack_members.size() - 1]
		if not bool(last.get("isLeader", false)):
			_fail("the elite leader must be LAST in the pack")
	# A pack member's death must hand over to the next one, in order, and the elite
	# leader must be the LAST to be reached. `pack_active` is the index of the member
	# currently fighting, so the sequence of indices IS the proof.
	var order: Array = [elite_b.pack_active]
	var guard := 0
	while elite_b.pack_advance():
		order.append(elite_b.pack_active)
		guard += 1
		if guard > 8:
			_fail("pack_advance never reported the end")
			break
	if order != [0, 1, 2, 3]:
		_fail("a 4-member elite pack should be fought 0,1,2,3 in order, got %s" % str(order))
	if not bool(elite_b.pack_members[3].get("isLeader", false)):
		_fail("the last member fought must be the elite leader")


# --- helpers -----------------------------------------------------------------

## Put a real weapon on the hero and spend the attribute points a hero of that level
## would have. Used where a fight has to be winnable: both matter. The unarmed damage
## path is deliberately weak, and a level-60 hero with 0 STR hits like a level-1 one
## because damage scales with attributes, not with level alone.
func _give_weapon(state, item_id: String) -> void:
	var item: Dictionary = _data.item(item_id)
	if item.is_empty():
		_fail("test setup: no such weapon '%s'" % item_id)
		return
	state.equip()["weapon"] = item_id
	_spend_attribute_points(state)


## 5 attribute points per level, all into the class's primary attribute — what a
## player who never thought about it would have.
func _spend_attribute_points(state) -> void:
	var hero: Dictionary = state.hero()
	var points := (int(hero["level"]) - 1) * 5
	var cls: Dictionary = _data.class_by_id(str(state.data.get("heroClass", "")))
	var primary := str(cls.get("primaryAttr", "str"))
	hero["attrStr"] = points if primary == "str" else 0
	hero["attrDex"] = points if primary == "dex" else 0
	hero["attrInt"] = points if primary == "int" else 0
	hero["attrVit"] = 0
	hero["maxHp"] = _gen.hero_max_hp(hero, state.equip(), _resolve)
	hero["hp"] = hero["maxHp"]

func _win_one_fight(act_id: int, zone: int) -> Battle:
	_state.data["locationProgress"][act_id] = zone
	_state.data["areaFightProgress"][act_id] = 0
	var b := Battle.new(_data, 2024)
	b.act_id = act_id
	if not b.setup(_state, _resolve):
		_fail("setup failed for act %d zone %d" % [act_id, zone])
	b.apply_swing_timers(_state, _resolve)
	_run(b, 4000)
	return b


func _fail(msg: String) -> void:
	_failures.append(msg)
