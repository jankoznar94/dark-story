extends RefCounted
class_name Progression
## Progression — levels, difficulty scaling, XP and the attack table.
##
## Ported from `src/core/progression.ts` plus the level/XP helpers in `src/game.ts`.
## Everything here is a pure function of the state and the tables: no timers, no
## nodes, no scene tree. That is deliberate — this is the part of the combat that
## can be asserted headless, and it is where the balance lives.
##
## The formulas are copied literally, including the magic numbers, because they ARE
## the balance. Where a number looks arbitrary the comment says where it came from.

const GameData := preload("res://scripts/data/game_data.gd")

## Player level cap — `applyLevelUp` stops here in the PWA.
const LEVEL_CAP := 60

## Zone scaling. Normal starts at x1.0 and adds 0.50 per zone; Nightmare starts at
## 5.5 (where act 5 Normal ends) and adds 0.72; Hell starts at 12.0 and adds 0.89.
const ZONE_SCALING := [
	{"base": 1.0, "step": 0.50},
	{"base": 5.5, "step": 0.72},
	{"base": 12.0, "step": 0.89},
]

var _data: Node


func _init(game_data: Node) -> void:
	_data = game_data


# --- difficulty scaling ------------------------------------------------------

## getZoneMult — the whole difficulty curve is this one function.
func zone_mult(progress: int, difficulty: int) -> float:
	var cfg: Dictionary = ZONE_SCALING[difficulty] if difficulty >= 0 and difficulty < ZONE_SCALING.size() else ZONE_SCALING[0]
	return float(cfg["base"]) + float(maxi(progress, 0)) * float(cfg["step"])


## How many zones an act has (the PWA's `loc.zones || 10`).
func total_zones(act_id: int) -> int:
	var act: Dictionary = _data.act_by_id(act_id)
	return int(act.get("zones", 10)) if not act.is_empty() else 10


## The last zone of an act is the boss zone. The PWA compared `progress >=
## totalZones - 1`; an earlier `>= totalZones` never fired because progress resets
## to 0 after a boss, so the boss simply never spawned.
func is_boss_zone(progress: int, act_id: int) -> bool:
	return progress >= total_zones(act_id) - 1


# --- monster level -----------------------------------------------------------

## getMonsterLevel — the monster's level, from the difficulty's per-act band and
## how far into the zone the player is. The bands chain across difficulties
## (Normal 1-15, Nightmare 16-30, Hell 31-60) so the curve is continuous.
func monster_level(act_id: int, progress: int, difficulty: int) -> int:
	var act: Dictionary = _data.act_by_id(act_id)
	if act.is_empty():
		return 1
	var diffs: Array = _data.difficulties()
	var diff: Dictionary = diffs[difficulty] if difficulty >= 0 and difficulty < diffs.size() else {}
	var min_level := int(act.get("minLevel", 1))
	var max_level := int(act.get("maxLevel", 3))
	var bands: Variant = diff.get("actLevels", null)
	if bands is Array and act_id < (bands as Array).size():
		var band: Array = bands[act_id]
		if band.size() >= 2:
			min_level = int(band[0])
			max_level = int(band[1])
	var zones := total_zones(act_id)
	var pct := float(progress) / float(zones) if zones > 0 else 0.0
	return min_level + int(round(float(max_level - min_level) * pct))


## The enemy's swing interval, slowed by an active chill. `slow_pct` and
## `slow_timer` come from the battle state.
func enemy_swing_time(monster_attack_speed: int, slow_pct: float, slow_timer: int) -> int:
	var ms := float(monster_attack_speed) if monster_attack_speed > 0 else 2000.0
	if slow_pct > 0.0 and slow_timer > 0:
		ms = round(ms / (1.0 - slow_pct / 100.0))
	return int(ms)


# --- XP ----------------------------------------------------------------------

## getXpMultiplier — D2's level-difference penalty. Three tiers, and the tables are
## 256ths because that is how D2 expresses them.
func xp_multiplier(hero_level: int, monster_level_value: int) -> float:
	var diff := monster_level_value - hero_level
	var below_x := {5: 256, 6: 207, 7: 159, 8: 110, 9: 61, 10: 13}
	var above_x := {5: 256, 6: 174, 7: 92, 8: 38, 9: 5}
	if hero_level < 25:
		if diff >= 0:
			var d: int = diff
			if d <= 5:
				return 1.0
			return float(above_x.get(d, 5)) / 256.0
		var db: int = absi(diff)
		if db <= 5:
			return 1.0
		return float(below_x.get(db, 13)) / 256.0
	if hero_level <= 69:
		if diff > 0:
			return maxf(0.05, float(hero_level) / float(monster_level_value))
		var d2: int = absi(diff)
		if d2 <= 5:
			return 1.0
		return float(below_x.get(d2, 13)) / 256.0
	# Tier 3 — above the cap (60), kept for completeness even though it cannot fire.
	var x := maxi(5, 1024 - (hero_level - 69) * 48)
	return float(x) / 1024.0


## XP needed to go from `level` to `level + 1`: 40 at level 1-2, then 80 per level.
func xp_needed(level: int) -> int:
	return level * 40 if level <= 2 else level * 80


## One kill's XP: monster level x 30, scaled by the level-difference penalty and by
## how many enemies were in the pack.
func kill_xp(hero_level: int, monster_level_value: int, pack_size: int) -> int:
	var mult := xp_multiplier(hero_level, monster_level_value)
	return int(round(float(monster_level_value) * 30.0 * mult * float(maxi(pack_size, 1))))


## Gold from one normal kill: (1 + rand(0..2)) * 5, i.e. 5, 10 or 15.
func kill_gold(rng: RandomNumberGenerator) -> int:
	return (1 + rng.randi_range(0, 2)) * 5


# --- hero derived damage -----------------------------------------------------

## getHeroDmg — the hero's damage range before any swing multiplier.
##
## Note the STR term is 0.5 per point and the level term is a flat +1 per level.
## `shield_spec_mult` is Shield Specialization (barbarian): +20% per level.
static func hero_dmg(hero: Dictionary, equip: Dictionary, find_item: Callable,
		shield_spec_mult: float = 1.0) -> Dictionary:
	var weapon: Dictionary = find_item.call(equip.get("weapon", "fists"))
	if weapon.is_empty():
		weapon = find_item.call("fists")
	var str_total := int(hero.get("attrStr", 0)) + _equip_attr(equip, find_item, "str")
	var str_bonus := float(str_total) * 0.5
	var lv_bonus := int(floor(float(hero.get("level", 1))))
	var w_min := weapon_dmg_min(weapon)
	var w_max := weapon_dmg_max(weapon)
	var dmg_min := maxi(1, int(round((2.0 + float(lv_bonus) + float(w_min) + str_bonus) * shield_spec_mult)))
	var dmg_max := maxi(1, int(round((2.0 + float(lv_bonus) + float(w_max) + str_bonus) * shield_spec_mult)))
	return {"min": dmg_min, "max": dmg_max}


## Total weapon damage including elemental rolls. Fire/cold/lightning may be stored
## either as a scalar or as a [min, max] pair — the PWA's getWeaponTotalDmgMin/Max
## handled both, so this does too.
static func weapon_dmg_min(weapon: Dictionary) -> int:
	return int(weapon.get("baseDmgMin", 0)) + _elem_min(weapon.get("fireDmg")) \
		+ _elem_min(weapon.get("coldDmg")) + _elem_min(weapon.get("lightningDmg"))


static func weapon_dmg_max(weapon: Dictionary) -> int:
	return int(weapon.get("baseDmgMax", 0)) + _elem_max(weapon.get("fireDmg")) \
		+ _elem_max(weapon.get("coldDmg")) + _elem_max(weapon.get("lightningDmg"))


## One random weapon damage roll in [min, max], inclusive.
static func weapon_dmg(rng: RandomNumberGenerator, weapon: Dictionary) -> int:
	var lo := weapon_dmg_min(weapon)
	var hi := weapon_dmg_max(weapon)
	return lo + rng.randi_range(0, maxi(hi - lo, 0))


static func _elem_min(v: Variant) -> int:
	if v is Array:
		return int(v[0]) if (v as Array).size() > 0 else 0
	return int(v) if v != null else 0


static func _elem_max(v: Variant) -> int:
	if v is Array:
		return int(v[1]) if (v as Array).size() > 1 else 0
	return int(v) if v != null else 0


static func _equip_attr(equip: Dictionary, find_item: Callable, key: String) -> int:
	var total := 0
	for slot in ItemGen.EQUIP_SLOTS:
		var item_id: Variant = equip.get(slot)
		if item_id == null or item_id == "" or item_id == "fists":
			continue
		var item: Dictionary = find_item.call(item_id)
		if not item.is_empty():
			total += int(item.get(key, 0))
	return total


# --- swing timing ------------------------------------------------------------

## getSwingTime — weapon speed in ms, shortened by DEX and by Increased Attack
## Speed. IAS uses D2's diminishing returns and the result is floored at 450 ms
## (550 before IAS is applied), so no amount of gear makes a swing instant.
static func swing_time(rng: RandomNumberGenerator, weapon: Dictionary, dex_total: int,
		ias_bonus: int = 0, speed_boost_pct: float = 0.0) -> int:
	var base := int(weapon.get("swingMs", 2000)) if not weapon.is_empty() else 2000
	var ms := maxi(550, int(round(float(base) * (1.0 - float(dex_total) * 0.01))))
	var ias := int(weapon.get("ias", 0)) + ias_bonus
	if ias > 0:
		var eias := int(round(float(ias) * 100.0 / float(ias + 120)))
		ms = maxi(450, int(round(float(ms) * 100.0 / (100.0 + float(eias)))))
	if speed_boost_pct > 0.0:
		ms = maxi(450, int(round(float(ms) * (1.0 - speed_boost_pct / 100.0))))
	return ms


# --- attack resolution -------------------------------------------------------

## getPlayerAttackTable — D2's chance to hit:
##   200 * AR / (AR + DR) * Alvl / (Alvl + Dlvl), clamped to [5, 95].
##
## Attack Rating comes from the class's primary attribute (barbarian STR x2 + DEX,
## assassin DEX x3 + STR, mage INT + DEX x2) plus any `attackRating` affix on gear.
static func hit_chance(attack_rating: int, monster_defense: int, hero_level: int,
		monster_level_value: int) -> float:
	var ar := maxf(1.0, float(attack_rating))
	var dr := maxf(1.0, float(monster_defense))
	var ml := maxi(monster_level_value, 1)
	var chance := 200.0 * ar / (ar + dr) * float(hero_level) / float(hero_level + ml)
	return clampf(chance, 5.0, 95.0)


## The hero's Attack Rating, from the class's primary attribute plus gear.
func hero_attack_rating(hero: Dictionary, equip: Dictionary, hero_class: String,
		find_item: Callable) -> int:
	var s := int(hero.get("attrStr", 0)) + _equip_attr(equip, find_item, "str")
	var d := int(hero.get("attrDex", 0)) + _equip_attr(equip, find_item, "dex")
	var i := int(hero.get("attrInt", 0)) + _equip_attr(equip, find_item, "int")
	var base_ar := 0
	if hero_class == "barbarian":
		base_ar = s * 2 + d
	elif hero_class == "assassin":
		base_ar = d * 3 + s
	else:
		base_ar = i + d * 2
	var gear_ar := 0
	for slot in ItemGen.EQUIP_SLOTS:
		var item_id: Variant = equip.get(slot)
		if item_id == null or item_id == "" or item_id == "fists":
			continue
		var item: Dictionary = find_item.call(item_id)
		if not item.is_empty():
			gear_ar += int(item.get("attackRating", 0))
	return maxi(1, base_ar + gear_ar)


## The enemy's chance to land a hit on the hero: the same D2 formula from the other
## side, with the hero's total armor defense as DR.
static func enemy_hit_chance(monster_ar: int, hero_defense: int, monster_level_value: int,
		hero_level: int) -> float:
	var ar := maxf(1.0, float(monster_ar))
	var dr := maxf(1.0, float(hero_defense))
	var ml := maxi(monster_level_value, 1)
	var chance := 200.0 * ar / (ar + dr) * float(ml) / float(ml + hero_level)
	return clampf(chance, 5.0, 95.0)


## Total armor defense from the five defense-bearing slots, plus the hero's DEX
## contribution. Armor is what makes the enemy's chance to hit fall.
func total_defense(equip: Dictionary, find_item: Callable) -> int:
	var total := 0
	for slot in ["armor", "helmet", "shield", "gloves", "boots"]:
		var item_id: Variant = equip.get(slot)
		if item_id == null or item_id == "":
			continue
		var item: Dictionary = find_item.call(item_id)
		if not item.is_empty():
			total += int(item.get("defense", 0))
	return total


## Damage the hero takes from one enemy hit, after the hero's damage reduction.
## `dmg_reduction` is a percentage from gear (D2's "Damage Reduced By x%").
static func incoming_damage(raw: int, dmg_reduction_pct: int) -> int:
	return maxi(1, int(round(float(raw) * (100.0 - float(mini(dmg_reduction_pct, 90))) / 100.0)))


# --- loot rarity -------------------------------------------------------------

## getRarity — the boss drop table is far more generous than a normal one, and the
## values here are the PWA's exactly (0.01/0.06/0.35 vs 0.15/0.40/0.70).
static func roll_rarity(rng: RandomNumberGenerator, boss_drop: bool) -> String:
	var r := rng.randf()
	if boss_drop:
		if r < 0.15:
			return "unique"
		if r < 0.40:
			return "rare"
		if r < 0.70:
			return "magic"
		return "common"
	if r < 0.01:
		return "unique"
	if r < 0.06:
		return "rare"
	if r < 0.35:
		return "magic"
	return "common"
