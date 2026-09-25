extends RefCounted
class_name Talents
## Talents — the class skill trees: what may be learned, when, and what the learned
## levels actually change. Ported from `SKILL_MAP` / `getClassSkillTree` / `getTalentLv`
## / `getSkillLv` / `isSkillUnlocked` / `investTalent` / `resetTalents` plus the derived
## stat helpers in game.ts (`getWeaponSpecBonus`, `getPlayerBlockChance`,
## `getTotalPlayerDefense`, `getPlayerResist`, `upgradeAttr`).
##
## The TREE RULES are the content here and they are easy to lose:
##
##   1. Three tiers per tree, unlocked by HERO LEVEL: tier 1 at level 1, tier 2 at 6,
##      tier 3 at 12. A tier's skills can be seen but not bought while locked.
##   2. A skill additionally requires its prerequisite at a given level — either
##      `requires` (one parent) or `requiresAny` (any of several). Both shapes exist in
##      the data and both must be honoured, or late-tier skills become buyable at
##      level 1 and the tree stops being a tree.
##   3. The key is `classId + '_' + skillKey`, because two classes can share a skill name.
##
## Not every talent has a modelled effect yet. `effect_summary()` reports what a level
## does in this port so the UI never promises a number the combat does not read, and
## `INERT_SKILLS` lists the ones whose mechanic was deliberately not ported (shouts,
## whirlwind's flurry, the reaction windows).

## Skills whose mechanic the port does not model. Investing is still allowed — the
## points and the prerequisite gating are real — but the UI says so instead of showing
## a bonus that never lands.
##
## Battle Shout, Defensive Shout and Frenzy came OFF this list when the class spells
## landed in the arena: the shouts now actually multiply the hero's damage and armour
## for their 30 s, and Frenzy actually shortens the swing interval. Leaving them here
## would have the UI deny a bonus the combat reads, which is the same lie in the other
## direction. Whirlwind stays: its PWA mechanic is a tap-the-button flurry with no
## equivalent in a portrait auto-combat arena.
const INERT_SKILLS := ["whirlwind", "skillShout", "thornShield", "faerieFire", "slow"]


## Flattened skill lookup, built once: key -> {key, classId, treeId, tierIdx, name, maxLv, ...}
var _skill_map: Dictionary = {}
var _class_skills: Dictionary = {}
var _data: Node


func _init(data: Node) -> void:
	_data = data
	_class_skills = data.class_skills()
	for class_id in _class_skills:
		var cls: Dictionary = _class_skills[class_id]
		var trees: Dictionary = cls.get("trees", {})
		for tree_id in trees:
			var tree: Dictionary = trees[tree_id]
			var tiers: Array = tree.get("tiers", [])
			for ti in tiers.size():
				for choice in tiers[ti].get("choices", []):
					var key := "%s_%s" % [str(class_id), str(choice.get("k", ""))]
					var entry: Dictionary = choice.duplicate(true)
					entry["key"] = key
					entry["classId"] = str(class_id)
					entry["treeId"] = str(tree_id)
					entry["tierIdx"] = ti
					_skill_map[key] = entry


# --- lookup -----------------------------------------------------------------

func class_tree(class_id: String) -> Dictionary:
	return _class_skills.get(class_id, {})


func skill(key: String) -> Dictionary:
	return _skill_map.get(key, {})


func tree_ids(class_id: String) -> Array:
	var cls: Dictionary = class_tree(class_id)
	return (cls.get("trees", {}) as Dictionary).keys()


## Icon path for a skill's image. The data stores a bare filename; the assets live
## under assets/spells/. Null when the data has no image, and then the caller draws the
## name instead — never an emoji, which the data also carries but the game does not use.
func icon_path(key: String) -> String:
	var s := skill(key)
	var file := str(s.get("iconImg", ""))
	if file == "":
		return ""
	return "assets/spells/%s" % file


# --- levels -----------------------------------------------------------------

## getTalentLv — the invested level. STATIC so the damage path can reach it: `battle.gd`
## holds no `Talents` instance (the class needs `_data` to build its skill map, and the
## battle is constructed before any screen), and a non-static reader is a parse error when
## called from the class directly — which also takes out every script that preloads this
## one. It reads nothing but the save, so there is nothing instance-bound about it.
static func talent_level(state, key: String) -> int:
	var levels: Dictionary = state.data.get("talentLevels", {})
	return int(levels.get(key, 0))


## getSkillLv — the level the RULES see. The PWA added a shout bonus on top; in this
## port the bonus is always 0 (the shouts are not modelled), so this is the invested
## level. Kept as a separate function because call sites must not read talentLevels
## directly: that is how a future global bonus gets applied in one place.
func skill_level(state, key: String) -> int:
	return talent_level(state, key) + int(state.data.get("skillShoutBonus", 0))


func max_level(key: String) -> int:
	return int(skill(key).get("maxLv", 0))


## Tier unlocked by hero level: 1 / 6 / 12. Tier index, not tier number.
static func tier_unlocked(tier_idx: int, hero_level: int) -> bool:
	if tier_idx <= 0:
		return true
	if tier_idx == 1:
		return hero_level >= 6
	if tier_idx == 2:
		return hero_level >= 12
	return false


## isSkillUnlocked — prerequisite only, ignoring the hero's level.
func prerequisites_met(state, key: String) -> bool:
	var s := skill(key)
	if s.is_empty():
		return false
	var requirement: Variant = s.get("requiresAny", null)
	if requirement is Array and not (requirement as Array).is_empty():
		var required_lv := int(s.get("requiresLv", 1))
		for req in requirement:
			if skill_level(state, str(req)) >= required_lv:
				return true
		return false
	var single: Variant = s.get("requires", null)
	if single == null or str(single) == "":
		return true
	return skill_level(state, str(single)) >= int(s.get("requiresLv", 1))


func is_available(state, key: String) -> bool:
	var s := skill(key)
	if s.is_empty():
		return false
	# The trees are per CLASS: a barbarian skill must not be buyable by an assassin.
	# The PWA enforced this only by rendering the hero's own tree, which is a screen
	# rule — and any path that reaches invest() without the screen would have bypassed
	# it. The gate belongs here, where the rules are.
	if str(s.get("classId", "")) != str(state.data.get("heroClass", "")):
		return false
	if not tier_unlocked(int(s.get("tierIdx", 0)), int(state.hero().get("level", 1))):
		return false
	return prerequisites_met(state, key)


## Why a skill cannot be bought, for the UI. "" means it can.
func blocked_reason(state, key: String) -> String:
	var s := skill(key)
	if s.is_empty():
		return "Neznamy skill"
	if str(s.get("classId", "")) != str(state.data.get("heroClass", "")):
		return "Nepatri tomuto povolani"
	if not tier_unlocked(int(s.get("tierIdx", 0)), int(state.hero().get("level", 1))):
		var need := 6 if int(s.get("tierIdx", 0)) == 1 else 12
		return "Odemkne se na levelu %d" % need
	if not prerequisites_met(state, key):
		return "Chybi predpoklad"
	if talent_level(state, key) >= max_level(key):
		return "Maximalni uroven"
	if int(state.data.get("talentPoints", 0)) <= 0:
		return "Zadne body"
	return ""


# --- investing --------------------------------------------------------------

## investTalent — one point from the pool into one level of a skill. Returns
## {ok, message}.
func invest(state, key: String) -> Dictionary:
	var reason := blocked_reason(state, key)
	if reason != "":
		return {"ok": false, "message": reason}
	var levels: Dictionary = state.data.get("talentLevels", {})
	levels[key] = int(levels.get(key, 0)) + 1
	state.data["talentLevels"] = levels
	state.data["talentPoints"] = int(state.data.get("talentPoints", 0)) - 1
	state.save()
	return {"ok": true, "message": "%s na urovni %d" % [str(skill(key).get("name", key)), int(levels[key])]}


## resetTalents — 50 gold returns every invested point to the pool.
##
## Nothing may change until the reset is certain. The first version zeroed the levels
## while counting them and only restored the copy on the gold branch, so a REFUSED
## reset still wiped every invested point while reporting "not enough gold".
static func reset(state) -> Dictionary:
	const COST := 50
	var levels: Dictionary = state.data.get("talentLevels", {})
	var total := 0
	for key in levels:
		total += int(levels[key])
	if total == 0:
		return {"ok": false, "message": "Zadne body k resetu"}
	var hero: Dictionary = state.hero()
	if int(hero.get("gold", 0)) < COST:
		return {"ok": false, "message": "Malo zlata (%d)" % COST}
	# Certain now: charge, zero, refund.
	for key in levels:
		levels[key] = 0
	hero["gold"] = int(hero["gold"]) - COST
	state.data["talentPoints"] = int(state.data.get("talentPoints", 0)) + total
	state.save()
	return {"ok": true, "message": "Vraceno %d bodu" % total}


## spendAttrPoint — one attribute point. The shape of the effect is the PWA's:
## STR raises damage, DEX the crit/block/dodge window, INT max mana, VIT max HP.
func spend_attr(state, attr: String, find_item: Callable, gen: ItemGen) -> Dictionary:
	var hero: Dictionary = state.hero()
	if int(hero.get("attrPoints", 0)) <= 0:
		return {"ok": false, "message": "Zadne atributove body"}
	match attr:
		"str":
			hero["attrStr"] = int(hero.get("attrStr", 0)) + 1
		"dex":
			hero["attrDex"] = int(hero.get("attrDex", 0)) + 1
		"int":
			hero["attrInt"] = int(hero.get("attrInt", 0)) + 1
		"vit":
			hero["attrVit"] = int(hero.get("attrVit", 0)) + 1
		_:
			return {"ok": false, "message": "Neznamy atribut"}
	hero["attrPoints"] = int(hero["attrPoints"]) - 1
	var max_hp := gen.hero_max_hp(hero, state.equip(), find_item)
	var max_mana := gen.hero_max_mana(hero, state.equip(), str(state.data.get("heroClass", "")), find_item)
	hero["maxHp"] = max_hp
	hero["maxMana"] = max_mana
	# The PWA topped HP and mana up to full on every attribute point, and the port does
	# the same: the pool and the current value must not drift apart on a level-up.
	hero["hp"] = max_hp
	hero["mana"] = max_mana
	state.save()
	return {"ok": true, "message": "%s +1" % attr.to_upper()}


# --- what a talent actually changes ------------------------------------------

## getWeaponSpecBonus — weapon specialisation: +10% damage, +10% attack rating and
## +1% crit per level. Only barbarians have it, and a two-handed weapon reads the
## two-hand tree. Off-hand attacks are penalised 50%, less 10% per one-hand level.
##
## STATIC because the DAMAGE PATH calls it: `battle.gd` has no `Talents` instance, and
## the whole point of this function is that the fight and the stat panel read the same
## numbers. An INSTANCE version here is what let the port display a crit bonus the fight
## never applied.
static func weapon_spec(state, weapon: Dictionary, is_offhand: bool = false) -> Dictionary:
	const ONE_HAND := "barbarian_oneHandSpec"
	const TWO_HAND := "barbarian_twoHandSpec"
	var hero_class := str(state.data.get("heroClass", ""))
	if hero_class != "barbarian" or weapon.is_empty():
		return {"dmgMult": 1.0, "arMult": 1.0, "critBonus": 0, "offHandMult": 0.5}
	var is_two_hand := bool(weapon.get("twoHand", false))
	var level := talent_level(state, TWO_HAND if is_two_hand else ONE_HAND)
	var one_hand_level := talent_level(state, ONE_HAND)
	if level <= 0:
		return {"dmgMult": 1.0, "arMult": 1.0, "critBonus": 0,
			"offHandMult": 0.5 + 0.1 * float(one_hand_level)}
	return {
		"dmgMult": 1.0 + 0.10 * float(level),
		"arMult": 1.0 + 0.10 * float(level),
		"critBonus": level,
		"offHandMult": 0.5 + 0.1 * float(one_hand_level),
	}


## The three numbers the DAMAGE PATH reads off a weapon specialization, as floats.
##
## ⚠️  `weapon_spec` is easy to write and easy to leave INERT: it existed here for a whole
## session with exactly one caller (the hero stat panel), so the port DISPLAYED a crit
## bonus from One-Hand/Two-Hand Specialization that the fight never applied. The PWA
## computed `(weapon.critChance || 0) + spec.critBonus` INSIDE `dealPlayerDamage`, and its
## `spec.dmgMult` / `spec.offHandMult` multiplied the same swing — three numbers, one
## expression, no second source of truth. This is that expression, and `battle.gd` calls it
## so the arena and the stat panel cannot drift apart again.
##
## A `Dictionary` of ints comes back deliberately: `Variant` arithmetic in GDScript is
## where a silent `1` instead of `1.0` would truncate a roll.
static func swing_bonus(state, weapon: Dictionary, is_offhand: bool,
		shield_mult: float) -> Dictionary:
	var spec := weapon_spec(state, weapon, is_offhand)
	# The off-hand penalty is the same slot the PWA scaled: an off-hand swing reads
	# `offHandMult` (0.5, rising to 1.0 at One-Hand Spec 5) and a MAIN-hand swing reads
	# Shield Specialization's +20 %/level. `weapon_spec` returns `offHandMult` for both.
	var hand_mult := float(spec["offHandMult"]) if is_offhand else shield_mult
	return {
		"dmgMult": float(spec["dmgMult"]),
		"arMult": float(spec["arMult"]),
		"critBonus": int(spec["critBonus"]),
		"handMult": hand_mult,
	}


## The crit chance one swing rolls against, as an integer PERCENT: the weapon's own base
## crit (which is where a crit affix lands, see `ItemGen`) plus the specialization bonus.
## A shared function because the arena, the stat panel and any future tooltip must print
## the same number the fight rolls.
static func swing_crit_chance(state, weapon: Dictionary) -> int:
	if weapon.is_empty():
		return 0
	return int(weapon.get("critChance", 0)) + int(weapon_spec(state, weapon)["critBonus"])


## Shield Specialization: +20% main-hand damage and +5% block per level. It lives on
## the shield tree, so it is read by both the damage path and the block path.
##
## STATIC for the same reason as `weapon_spec`: the arena's damage path needs it and has
## no `Talents` instance.
static func shield_spec_dmg_mult(state) -> float:
	return 1.0 + 0.20 * float(talent_level(state, "barbarian_shieldSpec"))


## getPlayerBlockChance — shield block, plus 1% per 10 DEX, plus 5% per Shield
## Specialization level, capped at 75%. No shield means no block at all, which is why
## this returns 0 rather than just the DEX term.
func player_block_chance(state, find_item: Callable, gen: ItemGen) -> int:
	var shield: Dictionary = find_item.call(state.equip().get("shield"))
	if shield.is_empty() or str(shield.get("type", "")) != "shield":
		return 0
	var attrs := gen.equip_attr_sum(state.equip(), find_item, ["dex"])
	var dex := int(state.hero().get("attrDex", 0)) + int(attrs["dex"])
	var spec := talent_level(state, "barbarian_shieldSpec") * 5
	return mini(int(shield.get("blockChance", 0)) + int(dex / 10) + spec, 75)


## getTotalPlayerDefense — the five armour slots.
## Total defence from every armour slot. STATIC because it reads nothing but the gear:
## the battle's incoming-damage rule needs it, and an instance would mean the battle
## owning a Talents object purely to add up five numbers.
static func total_defense(state, find_item: Callable) -> int:
	var total := 0
	for slot in ["armor", "helmet", "shield", "gloves", "boots"]:
		var item: Dictionary = find_item.call(state.equip().get(slot))
		if not item.is_empty():
			total += int(item.get("defense", 0))
	return total


## The defence percentage the character sheet shows.
static func defense_percent(total_def: int) -> int:
	return int(round(100.0 - 10000.0 / (100.0 + float(total_def))))


## DEX-driven dodge and hit chance, capped the way the PWA capped them.
static func dodge_percent(dex: int) -> int:
	return mini(50, int(round(float(dex) * 0.5)))


static func hit_percent(dex: int) -> int:
	return mini(95, 80 + int(round(float(dex) * 0.3)))


## getPlayerResist — resistances summed over the ten slots. The PWA mapped the four
## damage schools onto the four stats; the mapping is kept because the battle reads
## resists by school name.
static func player_resist(state, school: String, find_item: Callable) -> int:
	var stat := ""
	match school:
		"fire":
			stat = "fireRes"
		"ice", "cold":
			stat = "coldRes"
		"lightning":
			stat = "lightningRes"
		"nature", "poison":
			stat = "poisonRes"
		_:
			return 0
	var total := 0
	for slot in GameStateSlots():
		var item: Dictionary = find_item.call(state.equip().get(slot))
		if not item.is_empty():
			total += int(item.get(stat, 0))
	return total


static func GameStateSlots() -> Array:
	return ["weapon", "armor", "helmet", "shield", "ring1", "ring2", "amulet", "belt", "gloves", "boots"]


## One line of what a level of this skill buys, for the UI. Says so plainly when the
## skill's mechanic is not modelled, rather than showing a number nothing reads.
func effect_summary(key: String) -> String:
	var s := skill(key)
	if s.is_empty():
		return ""
	var k := str(s.get("k", ""))
	if k in INERT_SKILLS:
		return "Mechanika zatim neportovana"
	if k == "oneHandSpec" or k == "twoHandSpec":
		return "+10%% dmg, +10%% AR, +1%% crit za uroven"
	if k == "shieldSpec":
		return "+20%% dmg a +5%% block za uroven"
	if k == "pummel":
		return "+5%% dmg za uroven"
	return str(s.get("desc", ""))
