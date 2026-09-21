extends RefCounted
class_name PlayerSpells
## PlayerSpells — the hero's class spells: what may be cast, when, and what it does.
##
## Ported from the PWA's `castClassSpell()` plus the passives it feeds (`getSpellLv`,
## `getSpellCost`, `applyFrenzyStack`, the per-spell cooldown tick). The mechanics are
## split out of `castClassSpell` deliberately: in the PWA every effect was written
## inline into a 900-line function that also moved DOM nodes, so none of it could be
## asserted. Here each effect is a pure function of (battle, spell level, tables) and
## `tools/test_player_spells.gd` drives all of them.
##
## THE KEY RULE, and the reason a spell is not simply always available: a spell is
## castable only once the player has INVESTED A TALENT POINT in it. The PWA rendered
## the bar from `cls.spells.filter(spell => getTalentLv(key) > 0)`, so a talent nobody
## has bought does not exist as a button. That is the gate — not the hero's level, and
## not the tree tier.
##
## Gating that lives here rather than in the screen, because the screen is a rendering
## convenience and this is the rule:
##   - the spell must be one the class actually has (from CLASSES.json)
##   - the talent must be invested (see above)
##   - the mana must cover the cost, which for Double Swing FALLS with talent level
##   - the per-spell cooldown and the global cooldown must both be up
##   - a shield-gated spell needs a shield equipped
##   - Spell Reflect needs the enemy to be casting right now
##
## Cooldowns are on the BATTLE, not on the save: the PWA cleared them on entering town
## (`_sessionSpellCooldowns = {}` in resetSessionState), so they are per-session rather
## than persisted. That also means an unspent cooldown cannot be laundered by quitting.

const ItemGen := preload("res://scripts/items/item_gen.gd")
const Progression := preload("res://scripts/combat/progression.gd")
## Spells whose effect this module actually applies. The rest exist in the data and are
## refused with a reason rather than being pretended at — the same rule the enemy
## spells follow in battle.gd.
##
## The barbarian's twelve are all implemented. The assassin's and the mage's are not:
## they need mechanics this port has no home for yet (combo points, an active spell
## school, enemy DoTs from a player spell, an AoE). Listing them here as unimplemented
## is honest; wiring a damage number to them would not be.
const IMPLEMENTED := [
	"heroicStrike", "thunderClap", "thunderBolt", "battleShout", "defensiveShout",
	"doubleSwing", "shieldSlam", "pummel", "spellReflect", "frenzy",
]

## Whirlwind is deliberately absent from IMPLEMENTED as well as from the port: its PWA
## mechanic is a tap-the-shown-button flurry, which is an interaction model for a DOM
## page, not a rule. See the port notes.
const NOT_PORTED := ["whirlwind"]

## Buff durations, in ms. The PWA counted ticks at 60 fps.
const SHOUT_MS := 30000
const FRENZY_MS := 10000
## Global cooldown, the PWA's 0.5 s.
const GCD_MS := 500
# --- which spells exist for a class ------------------------------------------

static func spells_for_class(data: Node, class_id: String) -> Array:
	var cls: Dictionary = data.class_by_id(class_id)
	return (cls.get("spells", []) as Array).duplicate()


static func spell_def(data: Node, class_id: String, spell_id: String) -> Dictionary:
	for s in spells_for_class(data, class_id):
		if str((s as Dictionary).get("id", "")) == spell_id:
			return s
	return {}


## The talent level invested in this spell, 0 when nothing is bought. The talent key is
## `classId + '_' + spellId`, which is also how the talent trees key their entries.
static func talent_level(state, class_id: String, spell_id: String) -> int:
	var levels: Dictionary = state.data.get("talentLevels", {})
	return int(levels.get("%s_%s" % [class_id, spell_id], 0))


## The level the RULES use. The PWA added a shout bonus on top (Skill Shout); the port
## models no Skill Shout, so the bonus is always 0 — but every call site goes through
## here, so a future global bonus lands in one place.
static func spell_level(state, class_id: String, spell_id: String) -> int:
	return talent_level(state, class_id, spell_id) + int(state.data.get("skillShoutBonus", 0))


## A spell is castable only when a talent point has been spent on it.
static func is_available(state, class_id: String, spell_id: String) -> bool:
	if talent_level(state, class_id, spell_id) <= 0:
		return false
	return spell_id in IMPLEMENTED


static func is_implemented(spell_id: String) -> bool:
	return spell_id in IMPLEMENTED


## The mana a spell costs. Double Swing is the one spell whose cost falls as its talent
## grows — lv1 2, lv2 1.5, lv3 1, lv4 0.5, lv5 0 — which is why the cost is a function
## of the level rather than a field read.
static func spell_cost(state, class_id: String, spell_id: String, base_cost: float) -> float:
	if spell_id == "doubleSwing":
		var lv := clampi(spell_level(state, class_id, spell_id), 1, 5)
		var costs := [2.0, 1.5, 1.0, 0.5, 0.0]
		return float(costs[lv - 1])
	return base_cost


# --- availability ------------------------------------------------------------

## Why a spell cannot be cast right now, or "" when it can. `battle` may be null, which
## means "not in a fight" and is its own reason.
##
## Returns a Czech, player-facing reason: the caller shows it verbatim.
static func blocked_reason(state, data: Node, class_id: String, spell_id: String,
		battle, find_item: Callable, gcd_ms: int, cooldown_ms: int) -> String:
	if not is_implemented(spell_id):
		if spell_id in NOT_PORTED:
			return "Mechanika tohoto kouzla neni v portu"
		return "Kouzlo zatim neni v portu"
	if talent_level(state, class_id, spell_id) <= 0:
		return "Kouzlo nemas naucene"
	if battle == null or battle.ended:
		return "Zadny souboj"
	if gcd_ms > 0:
		return "Globalni cooldown"
	if cooldown_ms > 0:
		return "Cooldown %d s" % int(ceil(float(cooldown_ms) / 1000.0))

	var def := spell_def(data, class_id, spell_id)
	var cost := spell_cost(state, class_id, spell_id, float(def.get("cost", 0)))
	if float(state.hero().get("mana", 0)) < cost:
		return "Malo many"

	if bool(def.get("needsShield", false)):
		var shield: Dictionary = find_item.call(state.equip().get("shield"))
		if str(shield.get("type", "")) != "shield":
			return "Potrebujes stit"
	# Spell Reflect is only meaningful against an enemy that is actually casting: the
	# PWA checked this BOTH in the button state and again inside castClassSpell.
	if spell_id == "spellReflect" and str(battle.cast_spell_id) == "":
		return "Nepritel nekouzli"
	# Double Swing needs something in the off hand to swing with.
	if spell_id == "doubleSwing" and not _has_offhand(state, find_item, class_id):
		return "Potrebujes dve zbrane"
	return ""


static func can_cast(state, data: Node, class_id: String, spell_id: String, battle,
		find_item: Callable, gcd_ms: int, cooldown_ms: int) -> bool:
	return blocked_reason(state, data, class_id, spell_id, battle, find_item,
		gcd_ms, cooldown_ms) == ""


static func _has_offhand(state, find_item: Callable, class_id: String) -> bool:
	var cls: Dictionary = state.data_ref().class_by_id(class_id) if state.has_method("data_ref") else {}
	if not bool(cls.get("dualWield", false)):
		return false
	var off: Dictionary = find_item.call(state.equip().get("shield"))
	return not off.is_empty() and off.has("weaponType")


# --- casting -----------------------------------------------------------------

## Cast a spell. Returns {ok, message, damage, spell}. The GCD and the spell's own
## cooldown are set HERE, before the effect, because the PWA spent them on acceptance
## and a refused cast must not have spent anything either.
##
## `battle` is mutated by the effect (HP, timers, queued flags) — the same shape the
## battle itself uses, so one tick loop drives both.
static func cast(battle, spell_id: String, state, find_item: Callable,
		data: Node, rng: RandomNumberGenerator) -> Dictionary:
	var class_id := str(state.data.get("heroClass", ""))
	var reason := blocked_reason(state, data, class_id, spell_id, battle, find_item,
		int(battle.spell_gcd_ms), int(battle.spell_cooldowns.get(spell_id, 0)))
	if reason != "":
		return {"ok": false, "message": reason, "damage": 0, "spell": spell_id}

	var def := spell_def(data, class_id, spell_id)
	var lv := maxi(spell_level(state, class_id, spell_id), 1)
	var cost := spell_cost(state, class_id, spell_id, float(def.get("cost", 0)))

	state.hero()["mana"] = int(maxf(0.0, float(state.hero().get("mana", 0)) - cost))

	# GCD, then the spell's own cooldown. Pummel and Spell Reflect are the two whose
	# cooldown FALLS with talent level (8 s at lv1, 4 s at lv5).
	battle.spell_gcd_ms = int(round(float(def.get("gcd", 0.5)) * 1000.0))
	var cd_s := float(def.get("cooldown", 0))
	if cd_s > 0.0:
		if spell_id in ["pummel", "spellReflect"]:
			cd_s = maxf(4.0, 8.0 - float(lv - 1))
		battle.spell_cooldowns[spell_id] = int(round(cd_s * 1000.0))

	# A spell with a cast time does not land now: it starts and resolves on its own
	# clock, and the swing timer is reset because the cast replaces the swing. No
	# barbarian spell has one, so this path exists for the data that does.
	var cast_time := float(def.get("castTime", 0.0))
	if cast_time > 0.0:
		battle.player_cast_spell = spell_id
		battle.player_cast_ms = int(round(cast_time * 1000.0))
		battle.player_cast_elapsed = 0.0
		battle.player_swing_elapsed = 0.0
		return {"ok": true, "message": "%s: kouzleni" % str(def.get("name", spell_id)),
			"damage": 0, "spell": spell_id}

	return _apply(battle, spell_id, lv, state, find_item, data, rng)


## Resolve a spell that was mid-cast. Called from the battle's tick.
static func resolve_cast(battle, state, find_item: Callable, data: Node,
		rng: RandomNumberGenerator) -> Dictionary:
	var spell_id := str(battle.player_cast_spell)
	if spell_id == "":
		return {"ok": false, "message": "Nic se nekuzli", "damage": 0, "spell": ""}
	battle.player_cast_spell = ""
	battle.player_cast_elapsed = 0.0
	battle.player_cast_ms = 0
	var class_id := str(state.data.get("heroClass", ""))
	var lv := maxi(spell_level(state, class_id, spell_id), 1)
	return _apply(battle, spell_id, lv, state, find_item, data, rng)


static func _apply(battle, spell_id: String, lv: int, state, find_item: Callable,
		data: Node, rng: RandomNumberGenerator) -> Dictionary:
	match spell_id:
		"heroicStrike":
			# Queued, not instant: the next auto-attack carries the multiplier. The PWA
			# scaled it as 100 + lv*100 %, so lv1 is 200 % and lv5 is 600 %.
			battle.heroic_strike_queued = true
			return _ok(spell_id, "Heroic Strike pripraven na dalsi uder", 0)

		"frenzy":
			# Also queued, and the queued hit takes the damage AND the attack-rating
			# bonus; the stack is applied only if that hit lands.
			battle.frenzy_queued = true
			return _ok(spell_id, "Frenzy pripraven na dalsi uder", 0)

		"doubleSwing":
			return _double_swing(battle, lv, state, find_item, data, rng)

		"thunderClap":
			return _thunder_clap(battle, lv, state, find_item, data, rng)

		"thunderBolt":
			return _thunder_bolt(battle, lv, state, find_item, data, rng)

		"shieldSlam":
			return _shield_slam(battle, lv, state, find_item, data, rng)

		"pummel":
			return _pummel(battle, lv, state, find_item)

		"spellReflect":
			return _spell_reflect(battle, lv, state, find_item, data, rng)

		"battleShout":
			# +5 + lv*5 % damage for 30 s.
			var dmg_pct := 5.0 + float(lv) * 5.0
			battle.battle_shout_dmg_pct = dmg_pct
			battle.battle_shout_ms = SHOUT_MS
			return _ok(spell_id, "Battle Shout: +%d%% poskozeni" % int(dmg_pct), 0)

		"defensiveShout":
			# Armour by talent level, from the PWA's table: 50/75/100/125/150 %.
			var table: Array = [50.0, 75.0, 100.0, 125.0, 150.0]
			var armor_pct: float = float(table[clampi(lv - 1, 0, 4)])
			battle.defensive_shout_armor_pct = armor_pct
			battle.defensive_shout_ms = SHOUT_MS
			return _ok(spell_id, "Defensive Shout: +%d%% obrany" % int(armor_pct), 0)

	return {"ok": false, "message": "Kouzlo nema efekt", "damage": 0, "spell": spell_id}


static func _ok(spell_id: String, message: String, damage: int) -> Dictionary:
	return {"ok": true, "message": message, "damage": damage, "spell": spell_id}


# --- the barbarian's damage spells -------------------------------------------

## Double Swing — both weapons at once, and BOTH swing timers reset, so it replaces a
## swing rather than adding one. Its own cooldown is the SLOWER weapon's interval,
## which is what stops it being spammed with two fast weapons.
##
## The PWA also gave it +10 % attack rating per level on this hit; the hit check below
## therefore runs with a boosted AR rather than the plain one.
static func _double_swing(battle, lv: int, state, find_item: Callable, data: Node,
		rng: RandomNumberGenerator) -> Dictionary:
	var weapon: Dictionary = find_item.call(state.equip().get("weapon", "fists"))
	var offhand: Dictionary = find_item.call(state.equip().get("shield"))
	if str(offhand.get("type", "")) != "weapon" and not offhand.has("weaponType"):
		return {"ok": false, "message": "Potrebujes dve zbrane", "damage": 0, "spell": "doubleSwing"}

	var ar_mult := 1.0 + float(10 * lv) / 100.0
	if not battle.roll_player_hit(state, find_item, ar_mult):
		battle.player_swing_elapsed = 0.0
		battle.spell_cooldowns["doubleSwing"] = maxi(battle.player_swing_ms, battle.offhand_swing_ms)
		return _ok("doubleSwing", "Double Swing: MISS", 0)

	var dmg_mult := 1.0 + float(25 * lv) / 100.0
	var base := _base_swing_damage(battle, state, find_item, rng)
	var main_dmg := maxi(1, int(round((float(base) + float(Progression.weapon_dmg(rng, weapon))) * dmg_mult)))
	var off_dmg := maxi(1, int(round((float(base) + float(Progression.weapon_dmg(rng, offhand))) * dmg_mult)))
	var total := main_dmg + off_dmg

	battle.enemy_hp -= float(total)
	battle.note("DOUBLE SWING", total, false)
	# Both swings were spent, and the cooldown is the slower of the two weapons.
	battle.player_swing_elapsed = 0.0
	battle.offhand_swing_elapsed = 0.0
	battle.spell_cooldowns["doubleSwing"] = maxi(battle.player_swing_ms, battle.offhand_swing_ms)
	if battle.enemy_hp <= 0.0:
		battle.mark_enemy_dead(state, find_item)
	return _ok("doubleSwing", "Double Swing: %d" % total, total)


## Thunder Clap — damage off the weapon plus half of STR, then a 20 % slow for 1+lv
## seconds. The slow is applied by RECOMPUTING the enemy's swing interval while
## preserving how far into the current swing it already was, which is the detail that
## keeps the slow from either doing nothing or handing a free swing.
static func _thunder_clap(battle, lv: int, state, find_item: Callable, data: Node,
		rng: RandomNumberGenerator) -> Dictionary:
	var pct := 0.5 + float(lv) * 0.3
	var weapon: Dictionary = find_item.call(state.equip().get("weapon", "fists"))
	var str_bonus: float = float(battle.equip_attr(state, find_item, "str"))
	var base: float = float(Progression.weapon_dmg(rng, weapon)) * pct + floor(str_bonus * 0.5)
	var dmg := maxi(1, int(round(base * _skill_dmg_mult(battle, state, find_item))))

	battle.enemy_hp -= float(dmg)
	var slow_pct := 20.0
	var slow_ms := (1 + lv) * 1000
	battle.apply_enemy_slow(slow_pct, slow_ms)
	battle.note("THUNDER CLAP", dmg, false)
	if battle.enemy_hp <= 0.0:
		battle.mark_enemy_dead(state, find_item)
	return _ok("thunderClap", "Thunder Clap: %d, slow na %d s" % [dmg, 1 + lv], dmg)


## Thunder Bolt — a flat formula rather than a weapon one: 10 + level*3 + weapon damage
## + twice STR, at 80 + lv*20 %. Stuns for 3 + 0.5 s per level beyond the first.
static func _thunder_bolt(battle, lv: int, state, find_item: Callable, data: Node,
		rng: RandomNumberGenerator) -> Dictionary:
	var pct := float(80 + lv * 20)
	var weapon: Dictionary = find_item.call(state.equip().get("weapon", "fists"))
	var hero: Dictionary = state.hero()
	var str_total: float = float(int(hero.get("attrStr", 0)) + battle.equip_attr(state, find_item, "str"))
	var base: float = 10.0 + floor(float(hero.get("level", 1)) * 3.0) \
		+ float(Progression.weapon_dmg(rng, weapon)) + str_total * 2.0
	var dmg := maxi(1, int(round(base * pct / 100.0)))

	battle.enemy_hp -= float(dmg)
	battle.enemy_stun_ms = int(round((3.0 + float(lv - 1) * 0.5) * 1000.0))
	battle.enemy_swing_elapsed = 0.0
	battle.note("THUNDER BOLT", dmg, false)
	if battle.enemy_hp <= 0.0:
		battle.mark_enemy_dead(state, find_item)
	return _ok("thunderBolt", "Thunder Bolt: %d, omraceni" % dmg, dmg)


## Shield Slam — damage off the SHIELD's own damage range, not the weapon's, like D2's
## Smite. Needs a shield, which the gate already enforced.
static func _shield_slam(battle, lv: int, state, find_item: Callable, data: Node,
		rng: RandomNumberGenerator) -> Dictionary:
	var shield: Dictionary = find_item.call(state.equip().get("shield"))
	var s_min := int(shield.get("baseDmgMin", 1))
	var s_max := maxi(int(shield.get("baseDmgMax", 2)), s_min)
	var roll := s_min + rng.randi_range(0, s_max - s_min)
	var pct := 60.0 + float(lv) * 20.0
	var dmg := maxi(1, int(round(float(roll) * pct / 100.0)))

	battle.enemy_hp -= float(dmg)
	var slow_pct := 15.0 + float(lv) * 5.0
	var slow_ms := (2 + int(floor(float(lv) / 2.0))) * 1000
	battle.apply_enemy_slow(slow_pct, slow_ms)
	battle.note("SHIELD SLAM", dmg, false)
	if battle.enemy_hp <= 0.0:
		battle.mark_enemy_dead(state, find_item)
	return _ok("shieldSlam", "Shield Slam: %d, slow %d%%" % [dmg, int(slow_pct)], dmg)


## Pummel — an interrupt, not a damage spell. Cancels the enemy's cast in progress and
## blocks recasting for 2+lv seconds. The blocked window is a real field the enemy's
## own cast chooser reads; without that it would be an animation with no rule behind it.
static func _pummel(battle, lv: int, state, find_item: Callable) -> Dictionary:
	var block_ms := (2 + lv) * 1000
	var interrupted := str(battle.cast_spell_id) != ""
	if interrupted:
		battle.cast_spell_id = ""
		battle.cast_elapsed = 0.0
		battle.cast_time = 0.0
		# The enemy's swing was spent casting, so it starts a fresh one.
		battle.enemy_swing_elapsed = 0.0
	battle.enemy_cast_blocked_ms = block_ms
	battle.note("PUMMEL" + (" INTERRUPT" if interrupted else ""), 0, false)
	return _ok("pummel", "Pummel: blok kouzleni na %d s" % (2 + lv), 0)


## Spell Reflect — cancels an offensive cast and throws a fraction of it back. The
## reflected damage is computed from the ENEMY's numbers, scaled by 10 % per level,
## which is why it reads the same tables the enemy's own cast resolution does.
static func _spell_reflect(battle, lv: int, state, find_item: Callable, data: Node,
		rng: RandomNumberGenerator) -> Dictionary:
	var incoming := str(battle.cast_spell_id)
	if incoming == "":
		return {"ok": false, "message": "Nepritel nekouzli", "damage": 0, "spell": "spellReflect"}

	var reflect_pct := float(10 * lv)
	battle.cast_spell_id = ""
	battle.cast_elapsed = 0.0
	battle.cast_time = 0.0
	battle.enemy_swing_elapsed = 0.0

	# An offensive spell is one that is not a self-buff or a self-heal. The PWA kept an
	# explicit exempt list; the same idea, expressed as what the spell targets.
	var spells: Dictionary = data.enemy_spells()
	var spell: Dictionary = spells.get(incoming, {})
	var offensive := str(spell.get("target", "player")) == "player" and incoming != "heal"

	var dmg := 0
	if offensive:
		dmg = battle.reflect_damage(reflect_pct, rng)
		battle.enemy_hp -= float(dmg)
		battle.note("REFLECT %s" % incoming, dmg, false)
		if battle.enemy_hp <= 0.0:
			battle.mark_enemy_dead(state, find_item)
	else:
		battle.note("REFLECT %s (neofenzivni)" % incoming, 0, false)
	return _ok("spellReflect", "Spell Reflect: odrazeno %d" % dmg, dmg)


# --- helpers shared with the battle ------------------------------------------

## The base damage of a plain swing, the live path the port documents: the PWA's
## `mb.baseDmg` was never set, so this fallback IS the formula in use.
static func _base_swing_damage(battle, state, find_item: Callable,
		rng: RandomNumberGenerator) -> int:
	var hero: Dictionary = state.hero()
	var str_total: int = int(hero.get("attrStr", 0)) + battle.equip_attr(state, find_item, "str")
	return 2 + int(floor(float(hero.get("level", 1)) * 0.8)) + int(floor(float(str_total) * 0.3))


## Total `skillDmg` on the weapon, rings and amulet, as a multiplier. The PWA applied
## this to Thunder Clap only.
static func _skill_dmg_mult(battle, state, find_item: Callable) -> float:
	var total := 0
	for slot in ["weapon", "ring1", "ring2", "amulet"]:
		var item: Dictionary = find_item.call(state.equip().get(slot))
		if not item.is_empty():
			total += int(item.get("skillDmg", 0))
	if total <= 0:
		return 1.0
	return 1.0 + float(total) / 100.0
