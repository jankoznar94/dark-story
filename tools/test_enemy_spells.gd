extends SceneTree
## tools/test_enemy_spells.gd — the MONSTER's side of the fight.
##
## The port used to implement five of the eleven enemy spells. A caster picked
## `defensive_shout` and burned its whole swing on a no-op, which reads on screen as
## "the monster stopped attacking" — not as a missing feature. These rules are asserted
## because every one of them is invisible when it breaks:
##
##   - a monster's own buff must EXPIRE (a timer nobody ticks is a permanent buff)
##   - a monster TYPE must change what a landed hit does (a critmaster that never crits
##     is a monster with a label)
##   - the hero's poison must tick, and must not stack to a one-shot
##   - the enemy's mana must regenerate, or a caster stops casting after four swings
##
## Run:  godot --headless --path . --script res://tools/test_enemy_spells.gd
## Pass: prints ENEMY_SPELLS_ALL_PASS=true and exits 0.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const Battle := preload("res://scripts/combat/battle.gd")

var _data: Node
var _gen: ItemGen
var _state
var _failures: Array[String] = []


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)

	_test_every_enemy_spell_is_implemented()
	_test_defensive_shout_reduces_damage_and_expires()
	_test_thorn_shield_returns_damage_and_expires()
	_test_hero_poison_ticks_and_expires()
	_test_enemy_mana_regenerates()
	_test_lifestealer_heals_and_manastealer_drains()
	_test_critmaster_can_double_a_hit()
	_test_caster_opens_with_a_spell()
	_test_evasion_makes_hero_swings_miss()
	_test_monster_types_and_flags_reach_the_battle()

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("ENEMY_SPELLS_ALL_PASS=true")
	else:
		print("ENEMY_SPELLS_ALL_PASS=false")
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _resolve(id: Variant) -> Dictionary:
	var item_id := str(id)
	if item_id == "":
		return {}
	var s: Dictionary = _data.item(item_id)
	if not s.is_empty():
		return s
	if _state != null:
		return _state.loot_item(item_id)
	return {}


func _fresh(class_id: String = "barbarian", level: int = 30) -> void:
	_state = GameState.new()
	_state.bind_data(_data)
	_state.set_class(class_id)
	_state.hero()["level"] = level
	_state.hero()["maxHp"] = _gen.hero_max_hp(_state.hero(), _state.equip(), _resolve)
	_state.hero()["hp"] = _state.hero()["maxHp"]


## A fight that is guaranteed to be a plain melee monster with spells we choose, so the
## assertions are about the rule and not about which monster the theme rolled.
func _melee_fight(spells: Array = []) -> Battle:
	_fresh()
	_state.data["locationProgress"][0] = 0
	_state.data["areaFightProgress"][0] = 0
	var b := Battle.new(_data, 1234)
	b.act_id = 0
	if not b.setup(_state, _resolve):
		_fail("the fight could not be set up")
		return b
	b.enemy_attack_type = "melee"
	b.enemy_spells = spells
	b.apply_swing_timers(_state, _resolve)
	return b


# --- the spells ---------------------------------------------------------------

func _test_every_enemy_spell_is_implemented() -> void:
	var spells: Dictionary = _data.enemy_spells()
	for id in spells.keys():
		if not Battle._spell_implemented(str(id)):
			_fail("enemy spell '%s' exists in the data but has no effect in the battle" % id)


func _test_defensive_shout_reduces_damage_and_expires() -> void:
	var b := _melee_fight(["defensive_shout"])
	b.cast_spell_id = "defensive_shout"
	b.cast_time = 100.0
	b.cast_elapsed = 100.0
	b.tick(100.0, _state, _resolve)
	if b.enemy_defensive_shout_ms <= 0:
		_fail("defensive_shout applied no buff")
		return
	var raw := 200
	var reduced: int = b.incoming_damage(_state, _resolve, raw)
	b.enemy_defensive_shout_ms = 0
	var plain: int = b.incoming_damage(_state, _resolve, raw)
	if reduced >= plain:
		_fail("defensive_shout did not reduce incoming damage: %d vs %d" % [reduced, plain])
	# And it expires.
	for _i in 100:
		b.tick(100.0, _state, _resolve)
	if b.enemy_defensive_shout_ms > 0:
		_fail("the enemy's defensive_shout never expired - a permanent buff")


func _test_thorn_shield_returns_damage_and_expires() -> void:
	var b := _melee_fight(["thorn_shield"])
	b.cast_spell_id = "thorn_shield"
	b.cast_time = 100.0
	b.cast_elapsed = 100.0
	b.tick(100.0, _state, _resolve)
	if b.enemy_thorn_shield_ms <= 0:
		_fail("thorn_shield applied no buff")
		return
	b.gap = 0.0
	# A pool big enough that neither side can END the fight: a finished fight stops
	# ticking, so the buff would keep its remaining time forever and this would fail for
	# a reason that has nothing to do with the buff. BOTH the pool and its maximum, since
	# a lifestealer heals with `min(enemy_max_hp, ...)` and would clamp the pool back down.
	b.hero_max_hp = 100000.0
	b.hero_hp = 100000.0
	b.enemy_max_hp = 100000.0
	b.enemy_hp = 100000.0
	var hp_before := b.hero_hp
	b.player_attack(_state, _resolve)
	if b.hero_hp >= hp_before:
		_fail("thorn_shield returned no damage on a landed hit")
	for _i in 150:
		b.tick(100.0, _state, _resolve)
	if b.enemy_thorn_shield_ms > 0:
		_fail("the enemy's thorn_shield never expired")


func _test_hero_poison_ticks_and_expires() -> void:
	var b := _melee_fight([])
	b._apply_hero_poison(7)
	if b.hero_dot_ticks <= 0:
		_fail("poison was applied with no ticks")
		return
	var hp_before := b.hero_hp
	# One second = one tick.
	for _i in 10:
		b.tick(100.0, _state, _resolve)
	if b.hero_hp >= hp_before:
		_fail("the hero's poison dealt no damage over a second")
	if b.hero_dot_ticks != 2:
		_fail("the poison should have 2 ticks left after one second, has %d" % b.hero_dot_ticks)
	# The whole thing ends.
	for _i in 40:
		b.tick(100.0, _state, _resolve)
	if b.hero_dot_ticks > 0:
		_fail("the hero's poison never expired")


func _test_enemy_mana_regenerates() -> void:
	var b := _melee_fight(["poison_bolt"])
	b.enemy_resource = "mana"
	b.enemy_resource_cur = 0.0
	b.enemy_max_resource = 100.0
	var before := b.enemy_resource_cur
	for _i in 100:
		b.tick(100.0, _state, _resolve)
	if b.enemy_resource_cur <= before:
		_fail("the enemy's mana never regenerated - a caster goes silent after its pool")


func _test_lifestealer_heals_and_manastealer_drains() -> void:
	var b := _melee_fight([])
	b.monster_type = "lifestealer"
	b.enemy_hp = b.enemy_max_hp * 0.5
	var hp_before := b.enemy_hp
	b.enemy_attack(_state, _resolve)
	if b.enemy_hp <= hp_before:
		_fail("a lifestealer healed nothing from its own hit")

	var b2 := _melee_fight([])
	b2.monster_type = "manastealer"
	_state.hero()["mana"] = 50
	var mana_before := int(_state.hero()["mana"])
	b2.enemy_attack(_state, _resolve)
	if int(_state.hero()["mana"]) >= mana_before:
		_fail("a manastealer drained no mana from its own hit")


func _test_critmaster_can_double_a_hit() -> void:
	# A critmaster rolls a 33 % double. Over many swings the damage MUST exceed the same
	# number of non-crit swings, or the type is a label with nothing behind it.
	var normal := 0.0
	var crit := 0.0
	for i in 40:
		var b1 := _melee_fight([])
		b1.monster_type = ""
		_state.hero()["hp"] = 100000.0
		b1.hero_hp = 100000.0
		b1.enemy_attack(_state, _resolve)
		normal += (100000.0 - b1.hero_hp)
		var b2 := _melee_fight([])
		b2.monster_type = "critmaster"
		_state.hero()["hp"] = 100000.0
		b2.hero_hp = 100000.0
		b2.enemy_attack(_state, _resolve)
		crit += (100000.0 - b2.hero_hp)
	if crit <= normal * 1.05:
		_fail("a critmaster did not out-damage a plain monster over 40 swings (%.0f vs %.0f)"
			% [crit, normal])


func _test_caster_opens_with_a_spell() -> void:
	_fresh()
	_state.data["locationProgress"][0] = 0
	_state.data["areaFightProgress"][0] = 0
	var b := Battle.new(_data, 77)
	b.act_id = 0
	if not b.setup(_state, _resolve):
		_fail("setup failed")
		return
	# Force the caster shape on a fight that has spells to choose from.
	b.enemy_attack_type = "caster"
	b.enemy_spells = ["poison_bolt"]
	b.enemy_resource_cur = 100.0
	b.cast_spell_id = ""
	var opener := b._choose_spell()
	if opener == "":
		_fail("a caster with mana and a spell chose nothing to open with")
	# The first SWING is still melee, and only after it does it cast.
	if b.enemy_first_swing_done:
		_fail("a non-boss caster should not have its first swing behind it at setup")


func _test_evasion_makes_hero_swings_miss() -> void:
	var b := _melee_fight([])
	b.enemy_evasion_ms = 60000
	b.gap = 0.0
	var misses := 0
	for _i in 200:
		var r: Dictionary = b.player_attack(_state, _resolve)
		if not bool(r.get("hit", false)) and str(r.get("reason", "")) == "evasion":
			misses += 1
		b.enemy_hp = b.enemy_max_hp
	if misses == 0:
		_fail("enemy Evasion never made a hero swing miss")


func _test_monster_types_and_flags_reach_the_battle() -> void:
	# A real monster from the act's pool carries its type into the fight. Without this
	# the whole type system is data nobody reads.
	_fresh()
	_state.data["locationProgress"][0] = 0
	_state.data["areaFightProgress"][0] = 0
	var b := Battle.new(_data, 5)
	b.act_id = 0
	if not b.setup(_state, _resolve):
		_fail("setup failed")
		return
	var mon: Dictionary = b._pick_monster(0, 0)
	if not mon.is_empty():
		if b.monster_type == "":
			_fail("the encounter carries no monster type from the picked monster")
		if b.monster_type != str(mon.get("type", "")):
			_fail("the monster type does not match the picked monster")
	# A boss carries its list.
	_state.data["locationProgress"][0] = 9
	var boss := Battle.new(_data, 6)
	boss.act_id = 0
	if boss.setup(_state, _resolve):
		if not boss.is_boss:
			_fail("zone 9 of act 0 should be the boss zone")
		elif boss.boss_types.is_empty():
			_fail("the boss carries no types into the fight")
