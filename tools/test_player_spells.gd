extends SceneTree
## tools/test_player_spells.gd — the barbarian's class spells.
##
## Every rule here is invisible when it breaks, which is why they are asserted rather
## than tapped through in the browser:
##
##   - THE GATE: a spell is castable only once a talent point is invested. Nothing else
##     gates it — not the hero's level, not the tree tier. If this stops applying, the
##     spell bar simply offers spells the player never bought, which looks like content.
##   - A queued spell (Heroic Strike, Frenzy) must consume itself on the next MAIN-hand
##     swing. A flag that never clears makes every subsequent swing a Heroic Strike.
##   - A slow or a stun must expire. A timer nobody ticks is a permanent effect, and it
##     still reads as "working" in a fight that ends quickly anyway.
##   - Cooldowns must gate, and they live on the battle (per session), not on the save.
##
## Run:  godot --headless --path . --script res://tools/test_player_spells.gd
## Pass: prints PLAYER_SPELLS_ALL_PASS=true and exits 0.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const Battle := preload("res://scripts/combat/battle.gd")
const PlayerSpells := preload("res://scripts/combat/player_spells.gd")
const Progression := preload("res://scripts/combat/progression.gd")

var _data: Node
var _gen: ItemGen
var _failures: Array[String] = []


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)

	_test_gate_is_the_invested_talent_not_the_level()
	_test_unimplemented_spells_are_refused_not_faked()
	_test_mana_gates_and_is_spent()
	_test_double_swing_cost_falls_with_level()
	_test_cooldown_gates_and_expires()
	_test_heroic_strike_queues_and_consumes_once()
	_test_frenzy_needs_a_landed_hit_for_its_stack()
	_test_frenzy_speed_actually_shortens_the_swing()
	_test_thunder_clap_slows_and_the_slow_expires()
	_test_thunder_bolt_stuns_and_the_stun_expires()
	_test_pummel_interrupts_and_blocks_recasting()
	_test_spell_reflect_needs_a_casting_enemy()
	_test_shield_spells_need_a_shield()
	_test_shouts_expire()
	_test_defensive_shout_reduces_incoming_damage()
	_test_every_class_uses_mana()
	_test_mana_regen_actually_ticks()
	_test_spell_bar_lists_only_learned_spells()

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("PLAYER_SPELLS_ALL_PASS=true")
	else:
		print("PLAYER_SPELLS_ALL_PASS=false")
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _rng(seed_value: int = 4242) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _resolve(state) -> Callable:
	return func(id):
		var item_id := str(id)
		if item_id == "":
			return {}
		var static_item: Dictionary = _data.item(item_id)
		if not static_item.is_empty():
			return static_item
		return state.loot_item(item_id)


## A barbarian with a weapon, armour and an off hand, at a level where every tier is
## open, with a chosen set of talents bought.
func _hero(class_id: String = "barbarian", talents: Dictionary = {}, level: int = 20):
	var s = GameState.new()
	s.bind_data(_data)
	s.set_class(class_id)
	s.hero()["level"] = level
	s.hero()["mana"] = 500
	s.hero()["maxMana"] = 500
	s.hero()["attrStr"] = 40
	var levels := {}
	for key in talents:
		levels["%s_%s" % [class_id, key]] = int(talents[key])
	s.data["talentLevels"] = levels
	# A real weapon: bare fists are 1-2 damage and would make every comparison a tie.
	var sword: Dictionary = _data.item("blade_shortSword")
	if not sword.is_empty():
		s.equip()["weapon"] = "blade_shortSword"
	return s


## A live fight with the enemy's HP set high so a test's own damage is what ends it.
func _fight(state, hp: float = 100000.0):
	var battle = Battle.new(_data, 7)
	battle.act_id = 0
	battle.difficulty = 0
	battle.enemy_hp = hp
	battle.enemy_max_hp = hp
	battle.enemy_name = "Test Dummy"
	battle.enemy_defense = 0
	battle.enemy_dmg_min = 1
	battle.enemy_dmg_max = 2
	battle.hero_hp = 100000.0
	battle.hero_max_hp = 100000.0
	battle.player_swing_ms = 2000
	return battle


# --- the gate -----------------------------------------------------------------

## The one rule that decides whether a spell exists at all. The PWA filtered its bar by
## `getTalentLv(key) > 0`, so an unbought talent is not a weaker spell, it is no spell.
func _test_gate_is_the_invested_talent_not_the_level() -> void:
	var unbought = _hero("barbarian", {}, 60)
	var find := _resolve(unbought)
	if PlayerSpells.is_available(unbought, "barbarian", "heroicStrike"):
		_fail("heroicStrike is available with no talent invested")
	if PlayerSpells.talent_level(unbought, "barbarian", "heroicStrike") != 0:
		_fail("an uninvested talent reports a non-zero level")

	var battle = _fight(unbought)
	var reason: String = PlayerSpells.blocked_reason(unbought, _data, "barbarian",
		"heroicStrike", battle, find, 0, 0)
	if reason == "":
		_fail("an unlearned spell was castable")
	if not reason.to_lower().contains("naucene"):
		_fail("the refusal for an unlearned spell does not say so: '%s'" % reason)

	# Bought: now it is available, and the gate is the TALENT, not the level.
	var bought = _hero("barbarian", {"heroicStrike": 1}, 1)
	var find2 := _resolve(bought)
	if not PlayerSpells.is_available(bought, "barbarian", "heroicStrike"):
		_fail("heroicStrike is unavailable at level 1 WITH a talent point in it")
	var reason2: String = PlayerSpells.blocked_reason(bought, _data, "barbarian",
		"heroicStrike", _fight(bought), find2, 0, 0)
	if reason2 != "":
		_fail("a learned spell is blocked for '%s'" % reason2)


## The assassin's and the mage's spells are NOT implemented. They must be refused with a
## reason rather than quietly doing a wrong thing.
func _test_unimplemented_spells_are_refused_not_faked() -> void:
	var mage = _hero("mage", {"firebolt": 3}, 20)
	var find := _resolve(mage)
	var reason: String = PlayerSpells.blocked_reason(mage, _data, "mage", "firebolt",
		_fight(mage), find, 0, 0)
	if reason == "":
		_fail("an unimplemented mage spell was reported castable")
	if PlayerSpells.is_implemented("firebolt"):
		_fail("firebolt is claimed as implemented")
	# Whirlwind has its own reason: it was deliberately not ported, which is a different
	# statement from "not done yet".
	if not PlayerSpells.NOT_PORTED.has("whirlwind"):
		_fail("whirlwind is not listed as deliberately not ported")


func _test_mana_gates_and_is_spent() -> void:
	var s = _hero("barbarian", {"thunderClap": 1})
	var find := _resolve(s)
	s.hero()["mana"] = 0
	s.hero()["maxMana"] = 0
	var battle = _fight(s)
	var reason: String = PlayerSpells.blocked_reason(s, _data, "barbarian", "thunderClap",
		battle, find, 0, 0)
	if reason == "":
		_fail("a spell was castable with no mana")
	s.hero()["mana"] = 100
	s.hero()["maxMana"] = 100
	var before := int(s.hero()["mana"])
	var result: Dictionary = PlayerSpells.cast(battle, "thunderClap", s, find, _data, _rng())
	if not result["ok"]:
		_fail("thunderClap failed to cast with full mana: %s" % str(result["message"]))
		return
	if int(s.hero()["mana"]) >= before:
		_fail("casting did not spend mana (%d -> %d)" % [before, int(s.hero()["mana"])])


## Double Swing is the one spell whose cost falls as its talent grows. A cost table with
## an off-by-one would make it free at level 4 instead of 5.
func _test_double_swing_cost_falls_with_level() -> void:
	var expected := {1: 2.0, 2: 1.5, 3: 1.0, 4: 0.5, 5: 0.0}
	for lv in expected:
		var s = _hero("barbarian", {"doubleSwing": lv})
		var cost: float = PlayerSpells.spell_cost(s, "barbarian", "doubleSwing", 2.0)
		if absf(cost - float(expected[lv])) > 0.001:
			_fail("doubleSwing at talent %d costs %s, expected %s" % [lv, cost, expected[lv]])


func _test_cooldown_gates_and_expires() -> void:
	var s = _hero("barbarian", {"thunderClap": 1})
	var find := _resolve(s)
	var battle = _fight(s)
	PlayerSpells.cast(battle, "thunderClap", s, find, _data, _rng())
	var cd := int(battle.spell_cooldowns.get("thunderClap", 0))
	if cd <= 0:
		_fail("thunderClap set no cooldown")
	var reason: String = PlayerSpells.blocked_reason(s, _data, "barbarian", "thunderClap",
		battle, find, 0, cd)
	if reason == "":
		_fail("a spell on cooldown was castable again")
	# Tick it out. 15 s of cooldown at 100 ms steps = 150 ticks plus the GCD.
	for _i in 200:
		battle.tick(100.0, s, find)
	if int(battle.spell_cooldowns.get("thunderClap", 0)) > 0:
		_fail("the cooldown did not expire after 20 s of ticks")
	# The GCD also has to clear, or nothing is ever castable again.
	if battle.spell_gcd_ms > 0:
		_fail("the global cooldown did not expire")


## A queued spell must be consumed by exactly one swing. A flag that never clears turns
## every later swing into a Heroic Strike, and the fight ends fast enough that it looks
## like the spell is simply "strong".
func _test_heroic_strike_queues_and_consumes_once() -> void:
	var s = _hero("barbarian", {"heroicStrike": 1})
	var find := _resolve(s)
	var battle = _fight(s)
	var result: Dictionary = PlayerSpells.cast(battle, "heroicStrike", s, find, _data, _rng())
	if not result["ok"]:
		_fail("heroicStrike failed to queue: %s" % str(result["message"]))
		return
	if not battle.heroic_strike_queued:
		_fail("heroicStrike did not set the queued flag")
	# The queue is consumed by the next MAIN-hand swing.
	# Do NOT pre-clear the flag: cast() set it, and consume_queued is what must clear it.
	battle.offhand_swing_ms = 0
	battle.offhand_turn = false
	var queued: Dictionary = battle.consume_queued(s)
	if absf(float(queued["dmgMult"]) - 2.0) > 0.001:
		_fail("heroicStrike at talent 1 gave dmgMult %s, expected 2.0" % queued["dmgMult"])
	# And now it is off, so the NEXT swing is a plain one.
	var plain: Dictionary = battle.consume_queued(s)
	if absf(float(plain["dmgMult"]) - 1.0) > 0.001:
		_fail("the queued bonus applied twice (second consume gave %s)" % plain["dmgMult"])
	if battle.heroic_strike_queued:
		_fail("the queued flag survived being consumed")


## Frenzy's stack is earned only when the queued hit LANDS. A missed Frenzy costs the
## mana and gives nothing — the PWA did that too.
func _test_frenzy_needs_a_landed_hit_for_its_stack() -> void:
	var s = _hero("barbarian", {"frenzy": 1})
	var find := _resolve(s)
	var battle = _fight(s)
	battle.frenzy_queued = true

	# The hit chance floors at 5 %, so a miss cannot be forced by defense alone. Drive
	# the swing through the resolver with the hit check stubbed out instead of hoping a
	# seed misses.
	battle.enemy_defense = 0
	var saved_rng: RandomNumberGenerator = battle.rng
	battle.frenzy_queued = true
	var missed: Dictionary = battle._resolve_player_hit(s, find,
		find.call("blade_shortSword"), 1.0, false)
	if bool(missed.get("hit", false)) and battle.frenzy_stacks != 0:
		_fail("a MISSED frenzy granted a stack (%d)" % battle.frenzy_stacks)

	# A hit that lands grants exactly one stack and refreshes the window.
	battle.frenzy_stacks = 0
	battle.frenzy_speed_pct = 0.0
	battle.frenzy_ms = 0
	battle.frenzy_queued = true
	var res2: Dictionary = battle.player_attack(s, find)
	if not bool(res2.get("hit", false)):
		_fail("the frenzy hit did not land against zero defense")
	elif battle.frenzy_stacks != 1:
		_fail("a landed frenzy gave %d stacks, expected 1" % battle.frenzy_stacks)
	if battle.frenzy_ms <= 0:
		_fail("a landed frenzy did not start its 10 s window")
	# Stacks cap at 5.
	for _i in 10:
		battle.apply_frenzy_stack(s)
	if battle.frenzy_stacks > 5:
		_fail("frenzy stacks went past the cap (%d)" % battle.frenzy_stacks)


## Frenzy's bonus is attack SPEED, so it has to change the interval the tick compares
## against. A speed buff that only writes a number into the log is not a buff.
func _test_frenzy_speed_actually_shortens_the_swing() -> void:
	var s = _hero("barbarian", {"frenzy": 5})
	var find := _resolve(s)
	var slow_fight = _fight(s)
	slow_fight.player_swing_ms = 2000
	slow_fight.frenzy_speed_pct = 0.0
	var fast_fight = _fight(s)
	fast_fight.player_swing_ms = 2000
	# 5 stacks at talent 5 = 5 * 6 = 30 %.
	fast_fight.frenzy_stacks = 5
	fast_fight.frenzy_speed_pct = 30.0
	# The 10 s window has to be running too: the tick self-heals a speed bonus with no
	# timer behind it (that shape of bug is a permanent buff, and invisible in a short
	# fight), so a speed set without its window is wiped on the first tick.
	fast_fight.frenzy_ms = 10000

	var ticks_slow := _ticks_to_first_swing(slow_fight, s, find)
	var ticks_fast := _ticks_to_first_swing(fast_fight, s, find)
	if ticks_fast >= ticks_slow:
		_fail("frenzy did not shorten the swing (%d ticks vs %d)" % [ticks_fast, ticks_slow])
	# And the frenzy window must actually expire, putting the speed back to zero.
	for _i in 200:
		fast_fight.tick(100.0, s, find)
	if fast_fight.frenzy_speed_pct != 0.0:
		_fail("the frenzy window never expired (speed is still %s)" % fast_fight.frenzy_speed_pct)
	if fast_fight.frenzy_stacks != 0:
		_fail("frenzy stacks survived the window expiring")


## Ticks until the hero's first swing, measured by watching the swing CLOCK reset —
## which is the only way to see the effective interval, since Frenzy shortens it inside
## the tick rather than writing it back to `player_swing_ms`.
func _ticks_to_first_swing(battle, s, find) -> int:
	var prev: float = battle.player_swing_elapsed
	for i in 400:
		battle.tick(100.0, s, find)
		if battle.ended:
			return 999
		if battle.player_swing_elapsed < prev:
			return i + 1
		prev = battle.player_swing_elapsed
	return 999


## Thunder Clap slows the enemy, and the slow must END. A slow whose timer is never
## ticked is a permanent 20 % debuff that still looks like a working spell.
func _test_thunder_clap_slows_and_the_slow_expires() -> void:
	var s = _hero("barbarian", {"thunderClap": 5})
	var find := _resolve(s)
	var battle = _fight(s)
	battle.enemy_attack_speed = 2000
	battle.enemy_swing_ms = 2000
	var base_ms: int = battle.enemy_swing_ms
	PlayerSpells.cast(battle, "thunderClap", s, find, _data, _rng())
	if battle.enemy_slow_pct <= 0.0:
		_fail("thunderClap applied no slow")
	if battle.enemy_swing_ms <= base_ms:
		_fail("the slow did not lengthen the enemy's swing (%d -> %d)" % [base_ms, battle.enemy_swing_ms])
	# At talent 5 the slow lasts 1 + 5 = 6 s.
	for _i in 80:
		battle.tick(100.0, s, find)
	if battle.enemy_slow_pct != 0.0:
		_fail("the thunderClap slow never expired (still %s)" % battle.enemy_slow_pct)
	if battle.enemy_swing_ms != base_ms:
		_fail("the enemy's swing interval was not restored after the slow (%d, expected %d)" % [battle.enemy_swing_ms, base_ms])


func _test_thunder_bolt_stuns_and_the_stun_expires() -> void:
	var s = _hero("barbarian", {"thunderBolt": 3})
	var find := _resolve(s)
	var battle = _fight(s)
	battle.enemy_swing_ms = 1000
	PlayerSpells.cast(battle, "thunderBolt", s, find, _data, _rng())
	if battle.enemy_stun_ms <= 0:
		_fail("thunderBolt applied no stun")
		return
	# While stunned the enemy must not land a hit, however long the fight runs.
	var hp_before: float = battle.hero_hp
	for _i in 20:
		battle.tick(100.0, s, find)
	if battle.hero_hp < hp_before:
		_fail("the hero took damage from a STUNNED enemy")
	# The stun expires and the enemy swings again.
	for _i in 60:
		battle.tick(100.0, s, find)
	if battle.enemy_stun_ms > 0:
		_fail("the stun never expired (still %d ms)" % battle.enemy_stun_ms)
	var hp_mid: float = battle.hero_hp
	for _i in 30:
		battle.tick(100.0, s, find)
	if battle.hero_hp >= hp_mid:
		_fail("the enemy never swung again after the stun expired")


## Pummel is an interrupt plus a recast block. Both halves matter: cancelling the cast
## alone lets the enemy simply start another one next swing.
func _test_pummel_interrupts_and_blocks_recasting() -> void:
	var s = _hero("barbarian", {"pummel": 1})
	var find := _resolve(s)
	var battle = _fight(s)
	battle.cast_spell_id = "poison_bolt"
	battle.cast_time = 1000.0
	battle.cast_elapsed = 200.0
	PlayerSpells.cast(battle, "pummel", s, find, _data, _rng())
	if battle.cast_spell_id != "":
		_fail("pummel did not interrupt the enemy's cast")
	if battle.enemy_cast_blocked_ms <= 0:
		_fail("pummel applied no recast block")
	# The block is a real gate on the enemy's chooser, not just a number.
	battle.enemy_attack_type = "caster"
	battle.enemy_spells = ["poison_bolt"]
	battle.enemy_resource_cur = 999.0
	if battle._choose_spell() != "":
		_fail("the enemy chose a spell while the pummel block was up")
	# And it expires: 2 + level seconds.
	for _i in 60:
		battle.tick(100.0, s, find)
	if battle.enemy_cast_blocked_ms > 0:
		_fail("the pummel recast block never expired")
	# Clear the hero's poison first: `poison_bolt` is deliberately filtered out while a
	# poison is already running (the PWA did that), so leaving it on would make this
	# assertion measure that filter instead of the block expiring.
	battle.hero_dot_ticks = 0
	if battle._choose_spell() == "":
		_fail("the enemy still cannot cast after the pummel block expired")


func _test_spell_reflect_needs_a_casting_enemy() -> void:
	var s = _hero("barbarian", {"spellReflect": 1})
	s.equip()["shield"] = "shield_buckler"
	var find := _resolve(s)
	var battle = _fight(s)
	# No cast in progress: refused.
	var reason: String = PlayerSpells.blocked_reason(s, _data, "barbarian", "spellReflect",
		battle, find, 0, 0)
	if reason == "":
		_fail("spellReflect was castable with nothing being cast")
	# With a cast in progress it works, cancels the cast and deals damage back.
	battle.cast_spell_id = "shadow_bolt"
	var hp_before: float = battle.enemy_hp
	var result: Dictionary = PlayerSpells.cast(battle, "spellReflect", s, find, _data, _rng())
	if not result["ok"]:
		_fail("spellReflect failed against a casting enemy: %s" % str(result["message"]))
		return
	if battle.cast_spell_id != "":
		_fail("spellReflect did not cancel the enemy's cast")
	if battle.enemy_hp >= hp_before:
		_fail("spellReflect dealt no damage back")


## A shield-gated spell must actually check the shield. Without the check, Shield Slam
## reads a nil shield and silently does 1 damage.
func _test_shield_spells_need_a_shield() -> void:
	var s = _hero("barbarian", {"shieldSlam": 1, "spellReflect": 1})
	var find := _resolve(s)
	if not s.equip().get("shield"):
		var reason: String = PlayerSpells.blocked_reason(s, _data, "barbarian", "shieldSlam",
			_fight(s), find, 0, 0)
		if reason == "":
			_fail("shieldSlam was castable with no shield")
		if not reason.to_lower().contains("stit"):
			_fail("the shield refusal does not mention the shield: '%s'" % reason)
	# With a shield it casts and does real damage taken from the SHIELD's own range.
	s.equip()["shield"] = "shield_buckler"
	var battle = _fight(s)
	var hp_before: float = battle.enemy_hp
	var result: Dictionary = PlayerSpells.cast(battle, "shieldSlam", s, find, _data, _rng())
	if not result["ok"]:
		_fail("shieldSlam failed with a shield equipped: %s" % str(result["message"]))
		return
	if battle.enemy_hp >= hp_before:
		_fail("shieldSlam dealt no damage")


func _test_shouts_expire() -> void:
	var s = _hero("barbarian", {"battleShout": 5, "defensiveShout": 5})
	var find := _resolve(s)
	var battle = _fight(s)
	PlayerSpells.cast(battle, "battleShout", s, find, _data, _rng())
	if battle.battle_shout_dmg_pct <= 0.0:
		_fail("battleShout applied no damage bonus")
	# The bonus must reach a swing, not just sit in a field.
	battle.heroic_strike_queued = false
	battle.frenzy_queued = false
	var boosted: Dictionary = battle.consume_queued(s)
	if absf(float(boosted["dmgMult"]) - 1.0) > 0.001:
		_fail("consume_queued applied a multiplier that was not queued")
	# And it expires after 30 s, putting the damage back.
	for _i in 320:
		battle.tick(100.0, s, find)
	if battle.battle_shout_dmg_pct != 0.0:
		_fail("the battleShout bonus never expired (still %s)" % battle.battle_shout_dmg_pct)

	PlayerSpells.cast(battle, "defensiveShout", s, find, _data, _rng())
	if battle.defensive_shout_armor_pct <= 0.0:
		_fail("defensiveShout applied no armour bonus")
	for _i in 320:
		battle.tick(100.0, s, find)
	if battle.defensive_shout_armor_pct != 0.0:
		_fail("the defensiveShout bonus never expired")


## Defensive Shout's whole effect is the ARMOUR multiplier, so the test has to prove the
## damage that reaches the hero actually falls. A shout that only writes a percentage
## into a field nothing reads passes every "did it cast" check ever written.
##
## This also pins the armour curve itself: `totalDefense / (totalDefense + 300)`, the
## D2 constant, reached through `battle.incoming_damage`.
func _test_defensive_shout_reduces_incoming_damage() -> void:
	var s = _hero("barbarian", {"defensiveShout": 5})
	var find := _resolve(s)
	var battle = _fight(s)

	# A GENERATED armour, not the static base entry: the static table carries
	# defenseMin/defenseMax and only the generated item gets a `defense` value, which is
	# exactly how the PWA worked too (generateItem -> ITEM_MAP). Equipping the base
	# entry measures 0 and makes this test silently assert nothing.
	var base: Dictionary = _data.item("armor_leather")
	var armour: Dictionary = _gen.generate(base, "normal", 30, 30, _rng())
	if int(armour.get("defense", 0)) <= 0:
		_fail("the generated armour has no defense value (%s)" % str(armour.get("defense", null)))
		return
	s.register_loot_item(armour)
	s.equip()["armor"] = str(armour["id"])

	# Without the shout: armour alone still reduces, so compare against the RAW number.
	var raw := 200
	var plain: int = battle.incoming_damage(s, find, raw)
	if plain >= raw:
		_fail("armour reduced nothing at all (%d raw -> %d, armour defence %d)" % [raw, plain, int(armour["defense"])])
		return
	if plain < 1:
		_fail("incoming damage went below 1 (%d)" % plain)

	# With the shout: strictly less, because the armour is multiplied by 1 + pct/100.
	PlayerSpells.cast(battle, "defensiveShout", s, find, _data, _rng())
	if battle.defensive_shout_armor_pct <= 0.0:
		_fail("defensiveShout applied no armour bonus")
		return
	var shouted: int = battle.incoming_damage(s, find, raw)
	if shouted >= plain:
		_fail("defensiveShout did not reduce incoming damage (%d -> %d)" % [plain, shouted])

	# An enemy swing must land the reduced number, not a number computed elsewhere.
	battle.enemy_dmg_min = raw
	battle.enemy_dmg_max = raw
	battle.hero_hp = 100000.0
	var hp_before: float = battle.hero_hp
	battle.enemy_attack(s, find)
	var taken := int(hp_before - battle.hero_hp)
	if taken != shouted:
		_fail("the enemy swing did not use the armour rule (%d taken, expected %d)" % [taken, shouted])

	# When the shout expires the armour goes back to plain.
	for _i in 320:
		battle.tick(100.0, s, find)
	if battle.defensive_shout_armor_pct != 0.0:
		_fail("the defensiveShout bonus never expired")
	var after: int = battle.incoming_damage(s, find, raw)
	if after != plain:
		_fail("the armour did not return to its unshouted value (%d, expected %d)" % [after, plain])


## Every class pays for its spells out of mana — the barbarian included. The data says
## `resource: 'mana'` for all three, and the arena used to hide his bar on the false
## belief that he ran on rage, which hid the pool his own spells are billed against.
func _test_every_class_uses_mana() -> void:
	for class_id in ["barbarian", "assassin", "mage"]:
		var cls: Dictionary = _data.class_by_id(class_id)
		if str(cls.get("resource", "")) != "mana":
			_fail("%s does not use mana (resource='%s')" % [class_id, str(cls.get("resource", ""))])
		# And the pool must be real, not a zero that no spell could ever be paid from.
		var s = _hero(class_id, {}, 20)
		var max_mana: int = _gen.hero_max_mana(s.hero(), s.equip(), class_id, _resolve(s))
		if max_mana <= 0:
			_fail("%s has a max mana of %d" % [class_id, max_mana])


## Mana regen is sub-1-per-second while the save stores mana as an INT, so an
## implementation that adds the per-second rate each tick rounds to zero and never
## regenerates at all. That reads as "regen is slow" rather than "regen is broken".
func _test_mana_regen_actually_ticks() -> void:
	var s = _hero("barbarian", {})
	var find := _resolve(s)
	s.hero()["maxMana"] = 500
	s.hero()["mana"] = 100
	var battle = _fight(s)
	# 30 s of ticks. The base rate is 0.3/s, so even with no INT this must add several.
	for _i in 300:
		battle.tick(100.0, s, find)
	if int(s.hero()["mana"]) <= 100:
		_fail("mana never regenerated in 30 s (still %d) - the fraction is being rounded away" % int(s.hero()["mana"]))
	# And regen must not overshoot the pool.
	s.hero()["mana"] = 499
	for _i in 600:
		battle.tick(100.0, s, find)
	if int(s.hero()["mana"]) > 500:
		_fail("mana regenerated past the pool (%d > 500)" % int(s.hero()["mana"]))


## The bar is built from the talent levels, so an unlearned spell has no button. This is
## the PWA's own filter and the reason a fresh barbarian sees an empty spell row.
func _test_spell_bar_lists_only_learned_spells() -> void:
	var fresh = _hero("barbarian", {}, 20)
	var find := _resolve(fresh)
	var battle = _fight(fresh)
	if not battle.spell_bar(fresh, find).is_empty():
		_fail("a barbarian with no talents has spells on the bar")
	# Buy two, and exactly two must appear — in the data's order.
	fresh.data["talentLevels"] = {"barbarian_heroicStrike": 1, "barbarian_thunderClap": 1}
	var bar: Array = battle.spell_bar(fresh, find)
	if bar.size() != 2:
		_fail("the bar shows %d spells, expected 2" % bar.size())
		return
	var ids: Array = []
	for entry in bar:
		ids.append(str(entry["id"]))
	for expected in ["heroicStrike", "thunderClap"]:
		if not ids.has(expected):
			_fail("the bar is missing %s (has %s)" % [expected, str(ids)])
	# A spell that is learned but on cooldown must appear as blocked, not vanish.
	PlayerSpells.cast(battle, "thunderClap", fresh, find, _data, _rng())
	var bar2: Array = battle.spell_bar(fresh, find)
	var found_blocked := false
	for entry in bar2:
		if str(entry["id"]) == "thunderClap" and not bool(entry["can"]):
			found_blocked = true
	if not found_blocked:
		_fail("a spell on cooldown disappeared from the bar instead of showing as blocked")
