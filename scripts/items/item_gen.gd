extends RefCounted
class_name ItemGen
## ItemGen — item generation and the derived hero stats, ported from the PWA.
##
## This is the load-bearing half of the port: the numbers here ARE the game's item
## system, so the rules are copied from `src/game.ts` and `src/core/loot.ts`
## deliberately and literally, including the parts that look like odd choices
## (affixes filtered by HERO level rather than monster level, the weight multiplier
## of minIlvl, lvlReq = 0.75 * maxAffixIlvl). Changing any of them changes the game,
## so they are commented with the reason they exist, not just what they do.
##
## Pure logic: no nodes, no signals, no engine state. Callables that need randomness
## take a RandomNumberGenerator so tests can seed it and get reproducible items.

const GameData := preload("res://scripts/data/game_data.gd")

## Slots in the order the inventory UI shows them. The PWA listed them inline in
## nine separate functions; here it exists once.
const EQUIP_SLOTS := ["weapon", "armor", "helmet", "shield", "ring1", "ring2",
	"amulet", "belt", "gloves", "boots"]

## Every affix-rolled stat an item can carry. The PWA initialised these to 0 on the
## generated item so that `item.stat += roll` never produced NaN; keeping the full
## list means a missing key is a bug rather than a silent 0.
const AFFIX_STATS := ["fireDmg", "coldDmg", "lightningDmg", "poisonDmg", "poisonDur",
	"lifesteal", "manaSteal", "enhancedDefense", "enhancedDmg", "str", "vit", "int", "dex",
	"skillDmg", "manaRegen", "fireRes", "coldRes", "lightningRes", "poisonRes", "allRes",
	"goldFind", "magicFind", "allSkills", "classSkills", "ias", "thorns",
	"dmgReduction", "lifeRegen", "knockback", "preventHeal"]

var _data: Node


func _init(game_data: Node) -> void:
	_data = game_data


# --- small helpers ported verbatim ------------------------------------------

## Inclusive integer roll in [min, max] — the PWA's rollStat.
##
## Two affixes in the data carry a SCALAR rather than a range: `ofBear` is
## `{knockback: 1}` and `ofVileness` is `{preventHeal: 1}` — flags, not magnitudes.
## The PWA's rollStat would have produced NaN on those and the JS `+=` would have
## silently swallowed it; in GDScript an Array parameter would be a hard error, so
## the scalar shape is handled explicitly here.
static func roll_stat(rng: RandomNumberGenerator, stat_range: Variant) -> int:
	if stat_range is float or stat_range is int:
		return int(stat_range)
	var arr: Array = stat_range
	if arr.size() < 2:
		return int(arr[0]) if arr.size() == 1 else 0
	var lo := int(arr[0])
	var hi := int(arr[1])
	return lo + rng.randi_range(0, hi - lo)


## D2 socket roll: only normal-quality items, and only if the base allows sockets.
static func roll_sockets(rng: RandomNumberGenerator, quality: String, base_item: Dictionary, chance: float) -> int:
	if quality != "normal":
		return 0
	var max_sockets := int(base_item.get("maxSockets", 0))
	if max_sockets <= 0:
		return 0
	if rng.randf() >= chance:
		return 0
	return 1 + rng.randi_range(0, max_sockets - 1)


## Weighted pick where the weight GROWS with the affix's minIlvl.
##
## This is not the naive `weight` pick: the raw weights favour the weakest affixes
## (Firey 1-2 rolls weight 8, Scorching 19-30 weight 4), so a naive pick would keep
## handing out tier-1 damage at level 40. Multiplying by minIlvl is what makes a
## high-level item roll high-level affixes.
static func pick_affix(rng: RandomNumberGenerator, pool: Array, used_groups: Dictionary) -> Dictionary:
	var available: Array = []
	for a in pool:
		if not used_groups.has(a.get("group", -1)):
			available.append(a)
	if available.is_empty():
		return {}

	var total := 0.0
	for a in available:
		total += float(a.get("weight", 1)) * float(max(1, int(a.get("minIlvl", 1))))
	if total <= 0.0:
		return available[0]

	var r := rng.randf() * total
	for a in available:
		r -= float(a.get("weight", 1)) * float(max(1, int(a.get("minIlvl", 1))))
		if r <= 0.0:
			return a
	return available[-1]


## Quality roll with the D2 Magic Find diminishing returns.
##
## Magic: no diminishing (MF counts fully). Rare and Unique get a separate curve so
## that stacking MF cannot make uniques trivial — the same rule maxroll documents
## and the PWA implements.
static func roll_quality(rng: RandomNumberGenerator, magic_find: int) -> String:
	var unique_mf := int(floor((magic_find * 250.0) / (magic_find + 250.0)))
	var rare_mf := int(floor((magic_find * 600.0) / (magic_find + 600.0)))
	var unique_chance := 1 + int(floor(unique_mf * 0.01))
	var rare_chance := 5 + int(floor(rare_mf * 0.05))
	var magic_chance := 24 + int(floor(magic_find * 0.1))

	var roll := int(rng.randf() * 100.0)
	if roll < unique_chance:
		return "unique"
	if roll < rare_chance:
		return "rare"
	if roll < magic_chance:
		return "magic"
	return "normal"


# --- the main generator -----------------------------------------------------

## Generate a ready-to-equip item from a base definition.
##
## `hero_level` is passed in rather than read from global state: the affix pool is
## filtered by the HERO's level, not the monster's, so a player can never receive an
## item they cannot wear. `rng` is injected so a test can reproduce a roll exactly.
func generate(base_item: Dictionary, quality: String, monster_level: int,
		hero_level: int, rng: RandomNumberGenerator) -> Dictionary:
	var ilvl: int = mini(monster_level, hero_level)

	var candidates: Array = []
	for a in _data.affixes():
		if int(a.get("minIlvl", 0)) <= ilvl and base_item.get("type", "") in a.get("types", []):
			candidates.append(a)

	# Not every item type has affixes; an armour-less base degrades to normal rather
	# than producing a "magic" item with nothing magical about it.
	if candidates.is_empty():
		quality = "normal"

	var prefixes: Array = []
	var suffixes: Array = []
	for a in candidates:
		if a.get("type") == "prefix":
			prefixes.append(a)
		elif a.get("type") == "suffix":
			suffixes.append(a)

	var chosen: Array = []
	var used_groups := {}

	match quality:
		"magic":
			# 1-2 affixes, each rolled independently at 75%, but never zero.
			if rng.randf() < 0.75:
				var p := pick_affix(rng, prefixes, used_groups)
				if not p.is_empty():
					chosen.append(p)
					used_groups[p.get("group", -1)] = true
			if rng.randf() < 0.75:
				var s := pick_affix(rng, suffixes, used_groups)
				if not s.is_empty():
					chosen.append(s)
					used_groups[s.get("group", -1)] = true
			if chosen.is_empty():
				var fb := pick_affix(rng, prefixes, used_groups)
				if not fb.is_empty():
					chosen.append(fb)
					used_groups[fb.get("group", -1)] = true
		"rare":
			# 3-4 affixes. Rare can only get Mechanic's (max 2 sockets), never
			# Artisan's/Jeweler's — hence the magicOnly filter.
			var rare_prefixes: Array = []
			for a in prefixes:
				if not a.get("magicOnly", false):
					rare_prefixes.append(a)
			var rare_count := 3 + (1 if rng.randf() < 0.5 else 0)
			for _i in rare_count:
				var p_count := 0
				var s_count := 0
				for a in chosen:
					if a.get("type") == "prefix":
						p_count += 1
					else:
						s_count += 1
				var pool: Array = rare_prefixes if p_count <= s_count else suffixes
				var a := pick_affix(rng, pool, used_groups)
				if a.is_empty():
					a = pick_affix(rng, suffixes if pool == rare_prefixes else rare_prefixes, used_groups)
				if not a.is_empty():
					chosen.append(a)
					used_groups[a.get("group", -1)] = true

	var item := base_item.duplicate(true)
	item["id"] = "loot_%d_%d" % [Time.get_ticks_usec(), rng.randi()]
	item["baseId"] = base_item.get("id", "")
	item["affixes"] = chosen
	item["quality"] = quality
	item["ilvl"] = ilvl
	item["sockets"] = roll_sockets(rng, quality, base_item, socket_chance_normal())
	item["socketedGems"] = []

	# Base stats, exactly as the PWA derives them.
	item["baseDmg"] = int(round((int(base_item.get("baseDmgMin", 0)) + int(base_item.get("baseDmgMax", 0))) / 2.0)) \
		if base_item.get("type", "") == "weapon" else int(base_item.get("baseDmg", 0))
	item["bonusHp"] = int(base_item.get("bonusHp", 0))
	item["bonusMana"] = int(base_item.get("bonusMana", 0))
	if base_item.has("defenseMin"):
		item["defense"] = int(base_item["defenseMin"]) + rng.randi_range(0, int(base_item["defenseMax"]) - int(base_item["defenseMin"]))
	else:
		item["defense"] = int(base_item.get("defense", 0))
	item["critChance"] = int(base_item.get("critChance", 0))
	item["attackRating"] = int(base_item.get("attackRating", 0))

	for stat in AFFIX_STATS:
		item[stat] = 0

	for a in chosen:
		# A socket affix adds sockets instead of carrying stats.
		if a.has("sockets"):
			var from_base := int(base_item.get("maxSockets", 0))
			var add := mini(int(a["sockets"]), from_base)
			if add > 0:
				item["sockets"] = int(item["sockets"]) + add
			continue
		for stat in a.get("stats", {}):
			var value: Variant = a["stats"][stat]
			if stat == "swingMs":
				item[stat] = int(item.get(stat, 0)) + roll_stat(rng, value)
			elif stat == "allRes":
				# allRes spreads onto all four resists rather than staying its own stat.
				var v := roll_stat(rng, value)
				for res in ["fireRes", "coldRes", "lightningRes", "poisonRes"]:
					item[res] = int(item[res]) + v
			elif stat == "classSkills":
				# classSkills is [className, min, max] — a three-element array where the
				# first entry is a string. The class is remembered so the UI can show
				# "+2 Barbarian Skills".
				item["classSkills"] = int(item.get("classSkills", 0)) + roll_stat(rng, [value[1], value[2]])
				item["_classSkillsClass"] = value[0]
			else:
				item[stat] = int(item.get(stat, 0)) + roll_stat(rng, value)

	# Percentages apply AFTER the flat rolls, on the base values.
	if int(item.get("enhancedDefense", 0)) > 0 and int(item.get("defense", 0)) > 0:
		item["defense"] = int(round(int(item["defense"]) * (1.0 + int(item["enhancedDefense"]) / 100.0)))
	if int(item.get("enhancedDmg", 0)) > 0:
		var mult := 1.0 + int(item["enhancedDmg"]) / 100.0
		for key in ["baseDmgMin", "baseDmgMax", "baseDmg"]:
			if int(item.get(key, 0)) > 0:
				item[key] = int(round(int(item[key]) * mult))

	# lvlReq is derived from the strongest affix, not from ilvl.
	var max_affix_ilvl := 0
	for a in chosen:
		max_affix_ilvl = maxi(max_affix_ilvl, int(a.get("minIlvl", 0)))
	item["lvlReq"] = int(floor(0.75 * max_affix_ilvl))

	item["name"] = _name_for(item, base_item, chosen, quality)
	return item


## generateJewel — a 1-4 affix item that is inserted into a socket and applies all
## of its affixes to the host item. Unlike gear, a jewel's affix pool is NOT filtered
## by item type: a jewel may carry any affix. Quality is derived from the affix count
## (3+ = rare), not rolled.
func generate_jewel(monster_level: int, hero_level: int, rng: RandomNumberGenerator) -> Dictionary:
	var ilvl: int = mini(monster_level, hero_level)
	var candidates: Array = []
	for a in _data.affixes():
		# A socket affix has no stats to give a jewel.
		if int(a.get("minIlvl", 0)) <= ilvl and not a.has("sockets"):
			candidates.append(a)
	if candidates.is_empty():
		return {}

	var prefixes: Array = []
	var suffixes: Array = []
	for a in candidates:
		if a.get("type") == "prefix":
			prefixes.append(a)
		elif a.get("type") == "suffix":
			suffixes.append(a)

	var count := 1 + rng.randi_range(0, 3)
	var chosen: Array = []
	var used_groups := {}
	for _i in count:
		var p_count := 0
		var s_count := 0
		for a in chosen:
			if a.get("type") == "prefix":
				p_count += 1
			else:
				s_count += 1
		var pool: Array = prefixes if p_count <= s_count else suffixes
		var a := pick_affix(rng, pool, used_groups)
		if a.is_empty():
			a = pick_affix(rng, suffixes if pool == prefixes else prefixes, used_groups)
		if not a.is_empty():
			chosen.append(a)
			used_groups[a.get("group", -1)] = true

	if chosen.is_empty():
		return {}

	var colours := ["ruby", "sapphire", "emerald", "topaz"]
	var jewel_colour: String = colours[rng.randi_range(0, 3)]
	var jewel := {
		"id": "jewel_%d_%d" % [Time.get_ticks_usec(), rng.randi()],
		"name": "Jewel",
		"type": "jewel",
		"affixes": chosen,
		"quality": "rare" if chosen.size() >= 3 else "magic",
		"rarity": "rare" if chosen.size() >= 3 else "magic",
		"ilvl": ilvl,
		"jewelColor": jewel_colour,
		"iconImg": "assets/items/jewel_%s.png" % jewel_colour,
		"cost": 30 + chosen.size() * 20,
		"tier": 1,
	}
	for stat in AFFIX_STATS:
		jewel[stat] = 0
	for a in chosen:
		for stat in a.get("stats", {}):
			var value: Variant = a["stats"][stat]
			if stat == "allRes":
				var v := roll_stat(rng, value)
				for res in ["fireRes", "coldRes", "lightningRes", "poisonRes"]:
					jewel[res] = int(jewel[res]) + v
			elif stat == "classSkills":
				jewel["classSkills"] = int(jewel.get("classSkills", 0)) + roll_stat(rng, [value[1], value[2]])
				jewel["_classSkillsClass"] = value[0]
			else:
				jewel[stat] = int(jewel.get(stat, 0)) + roll_stat(rng, value)
	return jewel


func _name_for(item: Dictionary, base_item: Dictionary, chosen: Array, quality: String) -> String:
	if quality == "rare":
		return generate_rare_name(base_item.get("type", "weapon"))
	var prefix_parts: Array = []
	var suffix_parts: Array = []
	for a in chosen:
		if a.get("type") == "prefix":
			prefix_parts.append(a.get("name", ""))
		else:
			suffix_parts.append(a.get("name", ""))
	var parts: Array = []
	if not prefix_parts.is_empty():
		parts.append(" ".join(prefix_parts))
	parts.append(base_item.get("name", ""))
	if not suffix_parts.is_empty():
		parts.append(" ".join(suffix_parts))
	return " ".join(parts)


## D2-style rare name: <prefix word> <base label> <suffix word>, e.g. "Viper Song Blade".
func generate_rare_name(item_type: String) -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var first: Array = _data.table("RARE_FIRST_WORDS", [])
	var second: Dictionary = _data.table("RARE_SECOND_WORDS", {})
	if first.is_empty():
		return item_type.capitalize()
	var name: String = first[rng.randi_range(0, first.size() - 1)]
	var words: Array = second.get(item_type, [])
	if not words.is_empty():
		name += " " + words[rng.randi_range(0, words.size() - 1)]
	return name


func socket_chance_normal() -> float:
	return float(_data.table("SOCKET_CHANCE_NORMAL", 0.0))


# --- uniques -----------------------------------------------------------------


## pickUniqueForBase — a random unique whose base matches. Uniques are per-base in
## this data (one entry each), but the PWA picked from a list, so this does too.
func pick_unique_for_base(base_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var candidates: Array = []
	for u in _data.unique_items():
		if u is Dictionary and str(u.get("baseId", "")) == base_id:
			candidates.append(u)
	if candidates.is_empty():
		return {}
	return candidates[rng.randi_range(0, candidates.size() - 1)]


## generateUniqueItem — a unique is its base item plus the unique's own fixed stat
## block, rolled per stat. Note it does NOT go through the affix pool: a unique's
## numbers are authored, which is exactly what makes it a unique.
##
## Ported from `generateUniqueItem`, including the detail that the unique's `stats`
## values are either a scalar (exact D2 value) or a [min, max] range.
func generate_unique(unique_def: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var base_item: Dictionary = _data.item(str(unique_def.get("baseId", "")))
	if base_item.is_empty():
		return {}
	var item := base_item.duplicate(true)
	item["id"] = str(unique_def.get("id", "unique_%d" % rng.randi()))
	item["baseId"] = base_item.get("id", "")
	item["name"] = str(unique_def.get("name", base_item.get("name", "")))
	item["affixes"] = []
	item["quality"] = "unique"
	item["rarity"] = "unique"
	item["unique"] = true
	item["uniqueProp"] = unique_def.get("uniqueProp", null)
	item["tier"] = int(unique_def.get("tier", 5))
	item["iconImg"] = str(unique_def.get("iconImg", base_item.get("iconImg", "")))
	item["lvlReq"] = int(unique_def.get("minLevel", 1))
	# Sockets: the unique rolls them like any other normal-quality item. `roll_sockets`
	# returns 0 for a non-normal quality, which is why the call passes "unique" and
	# then the base's maxSockets: the PWA did exactly this and got 0 sockets every
	# time. Kept as-is rather than "fixed" — uniques have no sockets in this game.
	item["sockets"] = roll_sockets(rng, "unique", base_item, socket_chance_normal())
	item["socketedGems"] = []
	item["baseDmg"] = int(round((int(base_item.get("baseDmgMin", 0)) + int(base_item.get("baseDmgMax", 0))) / 2.0)) \
		if base_item.get("type", "") == "weapon" else int(base_item.get("baseDmg", 0))
	item["bonusHp"] = int(base_item.get("bonusHp", 0))
	item["bonusMana"] = int(base_item.get("bonusMana", 0))
	if base_item.has("defenseMin"):
		item["defense"] = int(base_item["defenseMin"]) + rng.randi_range(0, int(base_item["defenseMax"]) - int(base_item["defenseMin"]))
	else:
		item["defense"] = int(base_item.get("defense", 0))
	item["critChance"] = int(base_item.get("critChance", 0))
	item["attackRating"] = int(base_item.get("attackRating", 0))
	item["swingMs"] = int(base_item.get("swingMs", 0))

	for stat in AFFIX_STATS:
		item[stat] = 0

	var stats: Dictionary = unique_def.get("stats", {})
	for stat in stats:
		item[stat] = int(item.get(stat, 0)) + roll_stat(rng, stats[stat])

	# The percentage bonuses apply after the flat rolls, same as on a generated item.
	if int(item.get("enhancedDefense", 0)) > 0 and int(item.get("defense", 0)) > 0:
		item["defense"] = int(round(int(item["defense"]) * (1.0 + int(item["enhancedDefense"]) / 100.0)))
	if int(item.get("enhancedDmg", 0)) > 0:
		var mult := 1.0 + int(item["enhancedDmg"]) / 100.0
		for key in ["baseDmgMin", "baseDmgMax", "baseDmg"]:
			if int(item.get(key, 0)) > 0:
				item[key] = int(round(int(item[key]) * mult))
	return item


## The town's treasure class: how deep the shop and the gamble pool go. Driven by the
## difficulty and how many bosses are down, NOT by the hero's level — `dropFloor` is a
## global depth, so a level-60 hero in act 1 still sees act-1 stock.
func town_floor(difficulty: int, boss_kills: int) -> int:
	return difficulty * 50 + mini(4, boss_kills) * 10


## Number of bosses already killed at a difficulty, in act order. The shop's potion
## tier and the town floor both stop counting at the first act still alive.
static func sequential_boss_kills(bosses_row: Array) -> int:
	var kills := 0
	while kills < 5 and kills < bosses_row.size() and bool(bosses_row[kills]):
		kills += 1
	return kills


# --- derived hero stats ------------------------------------------------------

## Sum of a stat across all equipped items. `equip` maps slot -> item id, and
## `find_item` resolves an id to the item (base or generated).
func equip_attr_sum(equip: Dictionary, find_item: Callable, keys: Array) -> Dictionary:
	var total := {}
	for k in keys:
		total[k] = 0
	for slot in EQUIP_SLOTS:
		var item_id: Variant = equip.get(slot)
		if item_id == null or item_id == "" or item_id == "fists":
			continue
		var item: Dictionary = find_item.call(item_id)
		if item.is_empty():
			continue
		for k in keys:
			if item.get(k, 0):
				total[k] = int(total[k]) + int(item[k])
	return total


## getHeroMaxHp: 30 + level*5 + flat bonusHp + VIT*5.
func hero_max_hp(hero: Dictionary, equip: Dictionary, find_item: Callable) -> int:
	var bonus := 0
	for slot in EQUIP_SLOTS:
		var item_id: Variant = equip.get(slot)
		if item_id == null or item_id == "":
			continue
		var item: Dictionary = find_item.call(item_id)
		if not item.is_empty():
			bonus += int(item.get("bonusHp", 0))
	var attrs := equip_attr_sum(equip, find_item, ["vit"])
	return maxi(1, 30 + int(floor(int(hero.get("level", 1)) * 5)) + bonus \
		+ (int(hero.get("attrVit", 0)) + int(attrs["vit"])) * 5)


## getHeroMaxMana: class base + per-level + INT*2 + gear bonus.
func hero_max_mana(hero: Dictionary, equip: Dictionary, hero_class: String,
		find_item: Callable) -> int:
	var cls: Dictionary = _data.class_by_id(hero_class)
	var base_mana := int(cls.get("baseMana", 50)) if not cls.is_empty() else 50
	var per_level := float(cls.get("manaPerLevel", 0)) if not cls.is_empty() else 0.0
	var bonus := 0
	# The weapon counts too (weapon.bonusMana), which is why 'fists' is included here
	# even though the other stat functions skip it.
	var weapon_id: Variant = equip.get("weapon", "fists")
	var weapon: Dictionary = find_item.call(weapon_id) if weapon_id else {}
	if not weapon.is_empty():
		bonus += int(weapon.get("bonusMana", 0))
	for slot in EQUIP_SLOTS:
		var item_id: Variant = equip.get(slot)
		if item_id == null or item_id == "":
			continue
		var item: Dictionary = find_item.call(item_id)
		if not item.is_empty():
			bonus += int(item.get("bonusMana", 0))
	var attrs := equip_attr_sum(equip, find_item, ["int"])
	return maxi(10, base_mana + int(floor((int(hero.get("level", 1)) - 1) * per_level)) \
		+ (int(hero.get("attrInt", 0)) + int(attrs["int"])) * 2 + bonus)


## Magic Find summed over equipped gear — feeds roll_quality's diminishing curves.
func magic_find(equip: Dictionary, find_item: Callable) -> int:
	var attrs := equip_attr_sum(equip, find_item, ["magicFind"])
	return int(attrs["magicFind"])


## Gold Find, same shape.
func gold_find(equip: Dictionary, find_item: Callable) -> int:
	var attrs := equip_attr_sum(equip, find_item, ["goldFind"])
	return int(attrs["goldFind"])


# --- inventory rules ---------------------------------------------------------

## Stackable = gems, crafting materials, consumables. Stored as {id, count}.
static func is_stackable(item: Dictionary) -> bool:
	var t: String = item.get("type", "")
	return t == "gem" or t == "crafting" or t == "consumable"


## addToInventory — pushes a plain id for gear, or merges into a stack for gems.
static func add_to_inventory(inventory: Array, item_id: String, item: Dictionary, count: int = 1) -> void:
	if not is_stackable(item):
		inventory.append(item_id)
		return
	for entry in inventory:
		if entry is Dictionary and entry.get("id") == item_id:
			entry["count"] = int(entry.get("count", 1)) + count
			return
	inventory.append({"id": item_id, "count": count})


## removeFromInventory — decrements a stack, otherwise removes the entry.
static func remove_from_inventory(inventory: Array, item_id: String, count: int = 1) -> void:
	for i in inventory.size():
		var entry = inventory[i]
		var eid: String = entry.get("id", "") if entry is Dictionary else str(entry)
		if eid != item_id:
			continue
		if entry is Dictionary:
			entry["count"] = int(entry.get("count", 1)) - count
			if int(entry["count"]) <= 0:
				inventory.remove_at(i)
		else:
			inventory.remove_at(i)
		return


## How many are in the STACK for `item_id`. Ported from the PWA's getStackCount,
## which returns on the first match — so for NON-stackable gear (two separate sword
## entries) this returns 1, not 2. It answers "how many in the stack", not "how many
## entries exist"; use entry_count() for the latter.
static func stack_count(inventory: Array, item_id: String) -> int:
	for entry in inventory:
		var eid: String = entry.get("id", "") if entry is Dictionary else str(entry)
		if eid == item_id:
			return int(entry.get("count", 1)) if entry is Dictionary else 1
	return 0


## How many separate ENTRIES exist for an id, regardless of stacking. Gear occupies
## one entry per copy, so this is the honest count for anything non-stackable —
## stack_count returns 1 for two swords in the bag.
static func entry_count(inventory: Array, item_id: String) -> int:
	var n := 0
	for entry in inventory:
		var eid: String = entry.get("id", "") if entry is Dictionary else str(entry)
		if eid == item_id:
			n += 1
	return n
