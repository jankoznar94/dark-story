extends RefCounted
class_name ShopStock
## ShopStock — what the shop and the gamble vendor offer, and what happens when you
## buy or sell. Ported from `_generateShopItems`, `_generateGambleItems`, `buyItem`,
## `sellItem` and `buyGambleItem`.
##
## The stock is generated, not authored: bases are picked from the ITEMS table by
## `dropFloor` (the treasure class of the current progress), then rolled into normal /
## magic items. Which means three rules are the whole mechanic and all three are easy
## to get subtly wrong:
##
##   1. The SHOP is gated by the town floor (difficulty + sequential boss kills), NOT
##      by the hero's level. A level-60 hero standing in act 1 still sees act-1 stock.
##   2. The GAMBLE vendor is the opposite: gated purely by the hero's level, and it
##      shows the NORMAL version of each base. The version (normal/NM/Hell) is decided
##      by a roll at purchase time.
##   3. A gamble item is NEVER normal quality: it is at minimum magic, with rare at
##      ~10% and unique at ~0.05% (1 in 2000), which is exactly D2's table.
##
## Everything is a pure function of (tables, state, rng), so a headless test can
## generate a hundred shops and assert the gating rather than tapping buttons.

const ItemGen := preload("res://scripts/items/item_gen.gd")
const ItemStats := preload("res://scripts/items/item_stats.gd")

## The four weapon families; a shop offers two bases from each.
const WEAPON_TYPES := ["blade", "axe", "blunt", "claws"]
## The six armour families, same treatment.
const ARMOR_TYPES := ["armor", "helmet", "shield", "belt", "gloves", "boots"]

## D2 gamble quality table, in percent: unique below 0.05, rare below 10.05, else magic.
const GAMBLE_UNIQUE_PCT := 0.05
const GAMBLE_RARE_PCT := 10.05


# --- base selection ---------------------------------------------------------

## Bases whose dropFloor is reachable at this depth, chosen weighted by TIER so a
## depth can offer a low-tier and a high-tier base but never the same base twice.
static func _find_bases(data: Node, type: String, weapon_type: Variant, count: int,
		floor_cap: int, rng: RandomNumberGenerator) -> Array:
	var pool: Array = []
	for item in data.items():
		if str(item.get("type", "")) != type:
			continue
		if int(item.get("dropFloor", 0)) > floor_cap:
			continue
		if weapon_type != null and str(item.get("weaponType", "")) != str(weapon_type):
			continue
		# The gamble vendor shows only normal-version bases; the _nm / _hell variants
		# are reachable through the version roll instead.
		if str(item.get("id", "")).ends_with("_nm") or str(item.get("id", "")).ends_with("_hell"):
			continue
		pool.append(item)
	if pool.is_empty():
		return []
	var result: Array = []
	for _n in count:
		if pool.is_empty():
			break
		var total_weight := 0
		for candidate in pool:
			total_weight += maxi(1, int(candidate.get("tier", 1)))
		var roll := rng.randf() * float(total_weight)
		var idx := 0
		for i in pool.size():
			roll -= float(maxi(1, int(pool[i].get("tier", 1))))
			if roll <= 0.0:
				idx = i
				break
		result.append(pool[idx])
		pool.remove_at(idx)
	return result


# --- shop -------------------------------------------------------------------

## The shop's full stock, as [{category, items}]. `cache` is owned by the caller so the
## stock survives re-renders but is rebuilt on every town visit (`town.enter`).
static func generate(data: Node, gen: ItemGen, state, find_item: Callable,
		rng: RandomNumberGenerator) -> Array:
	var difficulty := int(state.data.get("difficulty", 0))
	var rows: Array = state.data.get("bossesDefeated", [])
	var boss_row: Array = rows[difficulty] if difficulty >= 0 and difficulty < rows.size() else []
	var kills := ItemGen.sequential_boss_kills(boss_row)
	var floor_cap := gen.town_floor(difficulty, kills)
	var monster_level := 5 + int(state.hero().get("level", 1)) * 2

	# Potions unlock act by act: after N sequential boss kills the shop sells up to
	# tier N+1, so act 1 stock is light potions and act 5 stock is the top tier.
	var potion_tier := mini(5, kills + 1)

	var armor_items: Array = []
	for armor_type in ARMOR_TYPES:
		for base in _find_bases(data, armor_type, null, 2, floor_cap, rng):
			armor_items.append_array(_gen_pair(base, state, gen, monster_level, rng))

	var weapon_items: Array = []
	for weapon_type in WEAPON_TYPES:
		for base in _find_bases(data, "weapon", weapon_type, 2, floor_cap, rng):
			weapon_items.append_array(_gen_pair(base, state, gen, monster_level, rng))

	# Jewellery is magic-only, like D2: common rings and amulets do not exist.
	var jewelry_items: Array = []
	for base in _find_bases(data, "ring", null, 2, floor_cap, rng):
		var item := _gen_single(base, "magic", state, gen, monster_level, rng)
		if not item.is_empty():
			jewelry_items.append(item)
	for base in _find_bases(data, "amulet", null, 2, floor_cap, rng):
		var item := _gen_single(base, "magic", state, gen, monster_level, rng)
		if not item.is_empty():
			jewelry_items.append(item)

	return [
		{"category": "Misc", "items": _misc_items(data, potion_tier)},
		{"category": "Armor", "items": armor_items},
		{"category": "Weapons", "items": weapon_items},
		{"category": "Jewelry", "items": jewelry_items},
	]


## Potions up to the unlocked tier, the town portal scroll, the rune and every gem.
## Built from the tables rather than a hardcoded id list, so adding an item to the
## game data reaches the shop without touching this file.
static func _misc_items(data: Node, potion_tier: int) -> Array:
	var out: Array = []
	for item in data.items():
		var item_type := str(item.get("type", ""))
		var subtype := str(item.get("subtype", ""))
		if item_type == "consumable" and subtype in ["heal", "mana"]:
			if int(item.get("tier", 1)) <= potion_tier:
				out.append(item)
	var scroll: Dictionary = data.item("townPortalScroll")
	if not scroll.is_empty():
		out.append(scroll)
	var rune: Dictionary = data.item("magicRune")
	if not rune.is_empty():
		out.append(rune)
	# Gems: every type at every quality, from the GEMS table (game_data indexes them
	# into items_by_id, so they resolve like any other item).
	for gem_type in data.gems():
		for quality in data.gem_qualities():
			var id: String = str(gem_type) if str(quality) == "normal" else "%s_%s" % [str(gem_type), str(quality)]
			var gem: Dictionary = data.item(id)
			if not gem.is_empty():
				out.append(gem)
	return out


## A normal + magic pair of the same base. The normal one costs the base's own cost
## (the PWA's rule) and the magic one is priced from its tier and affix count.
static func _gen_pair(base: Dictionary, state, gen: ItemGen, monster_level: int,
		rng: RandomNumberGenerator) -> Array:
	var common := gen.generate(base, "normal", monster_level, int(state.hero().get("level", 1)), rng)
	if common.is_empty():
		return []
	common["cost"] = int(base.get("cost", 10))
	state.register_loot_item(common)

	var magic := gen.generate(base, "magic", monster_level, int(state.hero().get("level", 1)), rng)
	if magic.is_empty():
		return [common]
	magic["cost"] = _magic_price(base, magic)
	state.register_loot_item(magic)
	return [common, magic]


static func _gen_single(base: Dictionary, quality: String, state, gen: ItemGen,
		monster_level: int, rng: RandomNumberGenerator) -> Dictionary:
	var item := gen.generate(base, quality, monster_level, int(state.hero().get("level", 1)), rng)
	if item.is_empty():
		return {}
	item["cost"] = _magic_price(base, item)
	state.register_loot_item(item)
	return item


static func _magic_price(base: Dictionary, item: Dictionary) -> int:
	return 10 + int(base.get("tier", 1)) * 20 + (item.get("affixes", []) as Array).size() * 15


# --- buying and selling -----------------------------------------------------

## Buy one stock item. The gold leaves, then the item lands in the belt if it is a
## potion, into the town-portal counter if it is a scroll, otherwise in the bag — and
## a full bag refunds rather than swallowing the gold.
## Returns {ok, message}.
static func buy(state, item: Dictionary, find_item: Callable) -> Dictionary:
	if item.is_empty():
		return {"ok": false, "message": "Neznamy predmet"}
	var item_id := str(item.get("id", ""))
	var cost := int(item.get("cost", 0))
	var hero: Dictionary = state.hero()
	if int(hero.get("gold", 0)) < cost:
		return {"ok": false, "message": "Malo zlata"}

	if item_id == "townPortalScroll":
		hero["gold"] = int(hero["gold"]) - cost
		state.data["townPortalCount"] = int(state.data.get("townPortalCount", 0)) + 1
	elif str(item.get("type", "")) == "consumable" and str(item.get("subtype", "")) in ["heal", "mana"] \
			and state.add_potion_to_belt(item_id, find_item):
		hero["gold"] = int(hero["gold"]) - cost
	else:
		if state.bag_full():
			return {"ok": false, "message": "Inventar je plny"}
		hero["gold"] = int(hero["gold"]) - cost
		if str(item.get("type", "")) == "gem":
			# A gem bought from the shop is the static table entry, so no registration.
			state.add_item(item_id, item)
		else:
			state.register_loot_item(item)
			state.add_item(item_id, item)
	state.save()
	return {"ok": true, "message": "Koupeno: %s" % ItemStats.socket_name(item)}


## Sell one item from the bag for half its cost. An equipped item can never be sold —
## the guard is here rather than only in the list, because the list is a rendering
## convenience and this is the rule.
static func sell(state, item_id: String, find_item: Callable) -> Dictionary:
	var item: Dictionary = find_item.call(item_id)
	if item.is_empty():
		return {"ok": false, "message": "Neznamy predmet"}
	if state.is_item_equipped(item_id):
		return {"ok": false, "message": "Predmet je nasazeny"}
	if ItemGen.stack_count(state.inventory(), item_id) <= 0:
		return {"ok": false, "message": "Predmet nemas v inventari"}
	var price := int(round(float(int(item.get("cost", 0))) * 0.5))
	if price <= 0:
		return {"ok": false, "message": "Tento predmet nelze prodat"}
	state.remove_item(item_id)
	state.hero()["gold"] = int(state.hero().get("gold", 0)) + price
	state.save()
	return {"ok": true, "message": "Prodano za %d" % price, "gold": price}


# --- gamble -----------------------------------------------------------------

## The gamble vendor's stock: one base per weapon family, armour family, ring and
## amulet — the NORMAL version, with the price scaled by the hero's level. The version
## and the quality are both rolled on purchase, which is what makes it a gamble.
static func generate_gamble(data: Node, state, rng: RandomNumberGenerator) -> Array:
	var hero_level := int(state.hero().get("level", 1))
	# 48 * min(1, level/50): a level-50+ hero sees every base in the game.
	var floor_cap := int(round(48.0 * minf(1.0, float(hero_level) / 50.0)))

	var weapons: Array = []
	for weapon_type in WEAPON_TYPES:
		for base in _find_bases(data, "weapon", weapon_type, 1, floor_cap, rng):
			weapons.append(_gamble_entry(base, hero_level))
	var armor: Array = []
	for armor_type in ARMOR_TYPES:
		for base in _find_bases(data, armor_type, null, 1, floor_cap, rng):
			armor.append(_gamble_entry(base, hero_level))
	var jewelry: Array = []
	for base in _find_bases(data, "ring", null, 1, floor_cap, rng):
		jewelry.append(_gamble_entry(base, hero_level))
	for base in _find_bases(data, "amulet", null, 1, floor_cap, rng):
		jewelry.append(_gamble_entry(base, hero_level))

	return [
		{"category": "Weapons", "items": weapons},
		{"category": "Armor", "items": armor},
		{"category": "Jewelry", "items": jewelry},
	]


static func _gamble_entry(base: Dictionary, hero_level: int) -> Dictionary:
	var base_cost := int(base.get("cost", 10))
	return {"baseItem": base, "price": int(round(float(base_cost) * (1.0 + float(hero_level) * 0.15)))}


## The two gamble rolls, separated so a test can pin them without buying anything.
static func roll_gamble_quality(rng: RandomNumberGenerator) -> String:
	var roll := rng.randf() * 100.0
	if roll < GAMBLE_UNIQUE_PCT:
		return "unique"
	if roll < GAMBLE_RARE_PCT:
		return "rare"
	return "magic"


## Which ITEM VERSION the gamble produced. Nothing until level 10, Nightmare from 10,
## Hell from 25, both capped — so at level 60 it is 40% Hell / 50% Nightmare.
static func roll_gamble_version(hero_level: int, rng: RandomNumberGenerator) -> String:
	var nm_chance := 0.0
	var hell_chance := 0.0
	if hero_level >= 10:
		nm_chance = minf(0.5, float(hero_level - 10) / 80.0)
	if hero_level >= 25:
		hell_chance = minf(0.4, float(hero_level - 25) / 62.0)
	var roll := rng.randf()
	if roll < hell_chance:
		return "hell"
	if roll < hell_chance + nm_chance:
		return "nm"
	return "normal"


## Buy a gamble base: pay the fixed price, then roll quality and version.
## Returns {ok, message, item}.
static func buy_gamble(state, entry: Dictionary, gen: ItemGen, data: Node,
		find_item: Callable, rng: RandomNumberGenerator) -> Dictionary:
	var base: Dictionary = entry.get("baseItem", {})
	if base.is_empty():
		return {"ok": false, "message": "Neznamy predmet", "item": {}}
	var price := int(entry.get("price", 0))
	var hero: Dictionary = state.hero()
	if int(hero.get("gold", 0)) < price:
		return {"ok": false, "message": "Malo zlata", "item": {}}
	if state.bag_full():
		return {"ok": false, "message": "Inventar je plny", "item": {}}

	var hero_level := int(hero.get("level", 1))
	var quality := roll_gamble_quality(rng)
	var version := roll_gamble_version(hero_level, rng)

	# The version changes the BASE STATS (armour, damage), so it is applied to the
	# base before anything is generated from it.
	var base_def: Dictionary = base
	if version != "normal":
		var versioned: Dictionary = data.item("%s_%s" % [str(base.get("id", "")), version])
		if not versioned.is_empty():
			base_def = versioned

	var item: Dictionary = {}
	if quality == "unique":
		var unique_def := gen.pick_unique_for_base(str(base.get("id", "")), rng)
		if not unique_def.is_empty():
			item = gen.generate_unique(unique_def, rng)
			if not item.is_empty():
				item["tier"] = int(base.get("tier", 1))
				item["cost"] = price
		if item.is_empty():
			# No unique for this base: fall back to rare rather than handing back nothing.
			quality = "rare"

	if item.is_empty():
		item = gen.generate(base_def, quality, hero_level, hero_level, rng)
	if item.is_empty():
		return {"ok": false, "message": "Generovani selhalo", "item": {}}

	# `rarity` is the display flag the UI colours by; the gamble never yields a common.
	item["tier"] = int(base_def.get("tier", 1))
	var item_quality := str(item.get("quality", "normal"))
	item["rarity"] = "common" if item_quality == "normal" else item_quality
	item["cost"] = price

	hero["gold"] = int(hero["gold"]) - price
	state.register_loot_item(item)
	state.add_item(str(item["id"]), item)
	state.save()
	var suffix := "" if version == "normal" else " (%s)" % version
	return {
		"ok": true,
		"message": "%s - %s%s" % [ItemStats.socket_name(item), str(item.get("rarity", "")), suffix],
		"item": item,
	}
