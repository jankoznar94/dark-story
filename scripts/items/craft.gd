extends RefCounted
class_name CraftSystem
## CraftSystem — the D2 crafting recipes, ported from the PWA's CRAFT_RECIPES +
## `craftItem` / `craftDoInner`.
##
## Five recipes: four gem crafts (ruby/sapphire x weapon/armor) and the gem upgrade
## (3 identical gems -> 1 of the next quality). A craft NEVER rolls from the inserted
## item — it regenerates from the base item, so the inputs are consumed, not improved.
## That surprised the PWA's own author, so it is stated here and asserted in the test.
##
## Everything is a pure function of (state, slots, tables). The screen only collects
## which inventory slot went into which craft slot; the rules live here so a headless
## test can drive a craft end to end.

const ItemGen := preload("res://scripts/items/item_gen.gd")
const ItemStats := preload("res://scripts/items/item_stats.gd")

## Gem qualities in ascending order — the index into this list is what the version
## guards compare.
const GEM_QUALITIES := ["chipped", "flawed", "normal", "flawless", "perfect"]

## The recipe table. `guaranteed` lists the stat keys that are rolled at the HIGHEST
## affix tier available for the hero's level, in addition to the item's random affixes.
const RECIPES := [
	{
		"id": "bloodWeapon", "name": "Blood Weapon", "gemType": "ruby",
		"itemTypes": ["weapon"], "guaranteed": ["ias", "enhancedDmg"],
		"desc": "Ruby + Weapon + Rune -> Attack Speed, Enhanced Damage, zvysok random",
	},
	{
		"id": "bloodArmor", "name": "Blood Armor", "gemType": "ruby",
		"itemTypes": ["armor", "helmet", "belt", "gloves", "boots", "shield"],
		"guaranteed": ["attackRating", "critChance"],
		"desc": "Ruby + Armor + Rune -> Attack Rating, Crit, zvysok random",
	},
	{
		"id": "safetyWeapon", "name": "Safety Weapon", "gemType": "sapphire",
		"itemTypes": ["weapon"], "guaranteed": ["enhancedDmg", "lifesteal"],
		"desc": "Sapphire + Weapon + Rune -> Enhanced Damage, Life Steal, zvysok random",
	},
	{
		"id": "safetyArmor", "name": "Safety Armor", "gemType": "sapphire",
		"itemTypes": ["armor", "helmet", "belt", "gloves", "boots", "shield"],
		"guaranteed": ["enhancedDefense", "bonusHp"],
		"desc": "Sapphire + Armor + Rune -> Enhanced Defense, HP, zvysok random",
	},
	{
		"id": "gemUpgrade", "name": "Gem Upgrade", "isGemUpgrade": true,
		"itemTypes": [], "guaranteed": [],
		"desc": "3 stejne gemy stejneho typu i kvality -> 1 gem vyssi kvality",
	},
]


static func recipe_by_id(recipe_id: String) -> Dictionary:
	for r in RECIPES:
		if r["id"] == recipe_id:
			return r
	return {}


static func gem_quality_index(quality: String) -> int:
	return GEM_QUALITIES.find(quality)


## The upgrade result for the three gem slots: same type AND same quality, and not
## already perfect. Returns {} when the combination is not an upgrade.
static func gem_upgrade_result(slots: Dictionary, find_item: Callable) -> Dictionary:
	var keys := ["gem1", "gem2", "gem3"]
	var items: Array = []
	for key in keys:
		var slot: Variant = slots.get(key)
		if slot == null:
			return {}
		var item: Dictionary = find_item.call(slot.get("id", ""))
		if str(item.get("type", "")) != "gem":
			return {}
		items.append(item)
	var first: Dictionary = items[0]
	for item in items:
		if str(item.get("gemType", "")) != str(first.get("gemType", "")):
			return {}
		if str(item.get("gemQuality", "")) != str(first.get("gemQuality", "")):
			return {}
	var idx := gem_quality_index(str(first.get("gemQuality", "")))
	if idx < 0 or idx >= GEM_QUALITIES.size() - 1:
		return {}
	var next_quality: String = str(GEM_QUALITIES[idx + 1])
	var next_id := str(first["gemType"]) if next_quality == "normal" else "%s_%s" % [str(first["gemType"]), next_quality]
	return find_item.call(next_id)


## Check a standard craft's inputs. Returns "" when the craft may proceed, otherwise
## the reason, worded as the PWA worded it (it is the player-facing message).
static func validate(recipe: Dictionary, slots: Dictionary, data: Node, find_item: Callable) -> String:
	for key in ["gem", "item", "rune", "jewel"]:
		if slots.get(key) == null:
			return "Chybi vstup: %s" % key
	var gem: Dictionary = find_item.call(slots["gem"].get("id", ""))
	var base_item: Dictionary = find_item.call(slots["item"].get("id", ""))
	var rune: Dictionary = find_item.call(slots["rune"].get("id", ""))
	var jewel: Dictionary = find_item.call(slots["jewel"].get("id", ""))
	if gem.is_empty() or base_item.is_empty() or rune.is_empty() or jewel.is_empty():
		return "Vstup se neda najit"

	# Only MAGIC (blue) items can be crafted — not normal, not rare, not unique.
	var quality := str(base_item.get("quality", base_item.get("rarity", "")))
	if quality != "magic":
		return "Predmet musi byt Magic kvality"
	if not (str(base_item.get("type", "")) in recipe.get("itemTypes", [])):
		return "Predmet nema typ pro tento recept"
	if str(gem.get("gemType", "")) != str(recipe.get("gemType", "")):
		return "Spatny typ gemu"
	if str(rune.get("type", "")) != "crafting":
		return "Runa musi byt crafting material"
	if str(jewel.get("type", "")) != "jewel":
		return "Jewel musi byt jewel"

	# Gem quality must match the item's VERSION: a Nightmare item needs at least a
	# Flawless gem, a Hell item a Perfect one. The version comes from the base id, not
	# the loot id — that is the detail the PWA comments on.
	var version := ItemStats.item_version(base_item)
	var required_idx := 1
	if version == 3:
		required_idx = 4
	elif version == 2:
		required_idx = 3
	var have_idx := gem_quality_index(str(gem.get("gemQuality", "")))
	if have_idx < required_idx:
		return "%s predmet vyzaduje %s gem" % [
			"Normal" if version == 1 else ("Nightmare" if version == 2 else "Hell"),
			GEM_QUALITIES[required_idx]]
	return ""


## craftItem — regenerate from the BASE item at rare quality, then roll each
## guaranteed stat from the highest affix tier available at `ilvl`, and take the MAX
## against any random affix carrying the same stat.
##
## That max() is deliberate: a guaranteed Quickness 40 plus a random Swiftness 30 must
## not add up to 70 IAS, which would be out of the game's range.
static func craft_item(recipe: Dictionary, gem: Dictionary, inserted_item: Dictionary,
		gen: ItemGen, hero_level: int, rng: RandomNumberGenerator, data: Node) -> Dictionary:
	var base_id := str(inserted_item.get("baseId", inserted_item.get("id", "")))
	var base: Dictionary = data.item(base_id)
	if base.is_empty():
		# A static base used directly (not a generated loot item).
		base = data.item(str(inserted_item.get("id", "")))
	if base.is_empty():
		return {}

	var new_item: Dictionary = gen.generate(base, "rare", hero_level, hero_level, rng)
	if new_item.is_empty():
		return {}

	# Every guaranteed stat takes the highest affix at this ilvl that carries it for
	# this item type, then rolls inside that affix's range.
	for stat in recipe.get("guaranteed", []):
		var candidates: Array = []
		for a in data.affixes():
			if int(a.get("minIlvl", 0)) > hero_level:
				continue
			if not (str(base.get("type", "")) in a.get("types", [])):
				continue
			if a.get("stats", {}).get(stat) == null:
				continue
			candidates.append(a)
		if candidates.is_empty():
			continue
		var max_ilvl := 0
		for a in candidates:
			max_ilvl = maxi(max_ilvl, int(a.get("minIlvl", 0)))
		var top: Array = []
		for a in candidates:
			if int(a.get("minIlvl", 0)) == max_ilvl:
				top.append(a)
		var affix: Dictionary = top[rng.randi_range(0, top.size() - 1)]
		var value: Variant = affix["stats"][stat]
		var rolled: int = ItemGen.roll_stat(rng, value)

		# Keep the range on the item so the tooltip shows it, as the PWA did.
		var affixes: Array = new_item.get("affixes", [])
		var craft_id := "craft_%s" % stat
		var seen := false
		for a in affixes:
			if a.get("id", "") == craft_id:
				seen = true
		if not seen:
			var stat_range := {}
			stat_range[stat] = value if value is Array else [int(value), int(value)]
			affixes.append({
				"id": craft_id, "name": affix.get("name", stat),
				"type": "prefix", "stats": stat_range,
			})
			new_item["affixes"] = affixes
		new_item[stat] = maxi(int(new_item.get(stat, 0)), maxi(1, rolled))

	# The percentage mods apply to the base numbers, after the rolls.
	if int(new_item.get("enhancedDmg", 0)) > 0:
		var mult := 1.0 + int(new_item["enhancedDmg"]) / 100.0
		for key in ["baseDmgMin", "baseDmgMax", "baseDmg"]:
			if int(new_item.get(key, 0)) > 0:
				new_item[key] = int(round(int(new_item[key]) * mult))
	if int(new_item.get("enhancedDefense", 0)) > 0 and int(new_item.get("defense", 0)) > 0:
		new_item["defense"] = int(round(int(new_item["defense"]) * (1.0 + int(new_item["enhancedDefense"]) / 100.0)))

	# A crafted item is rare quality with its own generated name, orange in the UI.
	new_item["name"] = gen.generate_rare_name(str(base.get("type", "weapon")))
	new_item["rarity"] = "rare"
	new_item["quality"] = "rare"
	new_item["crafted"] = true
	new_item["tier"] = int(base.get("tier", 1))
	new_item["iconImg"] = inserted_item.get("iconImg", base.get("iconImg", ""))
	new_item["cost"] = int(base.get("cost", 50))
	return new_item


## Run a craft for real: validate, consume the inputs, generate, and put the result in
## the bag. Returns {ok: bool, message: String, item: Dictionary}.
##
## Inputs are removed by ID, and the gem-upgrade path counts how many copies each slot
## needs because two slots can point at the same stack.
static func do_craft(state, recipe: Dictionary, slots: Dictionary, gen: ItemGen,
		rng: RandomNumberGenerator, data: Node, find_item: Callable) -> Dictionary:
	if recipe.is_empty():
		return {"ok": false, "message": "Zadny recept", "item": {}}

	if recipe.get("isGemUpgrade", false):
		return _do_gem_upgrade(state, slots, rng, gen, data, find_item)

	var problem := validate(recipe, slots, data, find_item)
	if problem != "":
		return {"ok": false, "message": problem, "item": {}}
	if state.bag_full():
		return {"ok": false, "message": "Inventar je plny", "item": {}}

	var gem: Dictionary = find_item.call(slots["gem"].get("id", ""))
	var inserted: Dictionary = find_item.call(slots["item"].get("id", ""))
	var jewel: Dictionary = find_item.call(slots["jewel"].get("id", ""))
	var hero_level := int(state.hero().get("level", 1))

	var result: Dictionary = craft_item(recipe, gem, inserted, gen, hero_level, rng, data)
	if result.is_empty():
		return {"ok": false, "message": "Craft selhal", "item": {}}

	# Consume the four inputs, then store the result.
	state.remove_item(str(slots["gem"]["id"]))
	state.remove_item(str(slots["item"]["id"]))
	state.remove_item(str(slots["rune"]["id"]))
	state.remove_item(str(slots["jewel"]["id"]))
	state.register_loot_item(result)
	state.add_item(str(result["id"]), result)
	state.save()
	return {"ok": true, "message": "Vycrafteno: %s" % ItemStats.socket_name(result), "item": result}


static func _do_gem_upgrade(state, slots: Dictionary, rng: RandomNumberGenerator,
		gen: ItemGen, data: Node, find_item: Callable) -> Dictionary:
	var up: Dictionary = gem_upgrade_result(slots, find_item)
	if up.is_empty():
		return {"ok": false, "message": "Vloz 3 stejne gemy (typ i kvalita)", "item": {}}
	if state.bag_full():
		return {"ok": false, "message": "Inventar je plny", "item": {}}

	# How many copies of each id the slots need — slots may share one stack.
	var need := {}
	for key in ["gem1", "gem2", "gem3"]:
		var id := str(slots[key]["id"])
		need[id] = int(need.get(id, 0)) + 1
	for id in need:
		if ItemGen.stack_count(state.inventory(), id) < int(need[id]):
			return {"ok": false, "message": "Nedostatek gemu v inventari", "item": {}}
	for id in need:
		state.remove_item(id, int(need[id]))

	state.add_item(str(up["id"]), up)
	state.save()
	return {"ok": true, "message": "Vylepseno na %s" % ItemStats.socket_name(up), "item": up}
