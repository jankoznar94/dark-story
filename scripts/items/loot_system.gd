extends RefCounted
class_name LootSystem
## LootSystem — what a monster drops, ported from the PWA's `rollLoot()`.
##
## The whole drop table is here in one function because that is how it was written:
## a chain of independent percentage checks, each with its own early return, ending
## in a 70/30 gold-or-item split. The ORDER is the mechanic — a town portal scroll
## takes priority over a gem, which takes priority over a rune, and so on. Reordering
## them silently changes every drop rate, so the order is preserved and commented.
##
## Gold amounts scale with Gold Find; item quality scales with Magic Find. Both
## multipliers come from gear and are passed in.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")

## Drop chances, in the order they are tested. Named so the rates are readable
## instead of being magic numbers in a chain.
const TOWN_PORTAL_CHANCE := 0.08
const GEM_CHANCE := 0.05
const RUNE_CHANCE := 0.04
const JEWEL_CHANCE := 0.03
const POTION_CHANCE := 0.10
const GOLD_VS_ITEM := 0.70


var _data: Node
var _items: ItemGen


func _init(game_data: Node, item_gen: ItemGen) -> void:
	_data = game_data
	_items = item_gen


## Roll one drop. Returns {type: "gold"|"item"|"boss", gold: int, item: Dictionary}.
##
## `state` is passed in for the two things the roll reads from it: the accumulated
## floor drops (used for the gem anti-repeat) and the loot-item registry.
func roll(state, loc_id: int, floor_num: int, boss_drop: bool, monster_level: int,
		magic_find: int, gold_find: int, rng: RandomNumberGenerator) -> Dictionary:
	var item := _roll_special(state, loc_id, floor_num, boss_drop, monster_level, rng)
	if not item.is_empty():
		return {"type": "item", "item": item}

	if boss_drop:
		# A boss always drops an item plus gold, never an empty hand.
		var boss_item := generate_item(state, loc_id, floor_num, true, monster_level, magic_find, rng)
		if boss_item.is_empty():
			return {"type": "gold", "gold": 10 + floor_num * 3}
		var boss_gold := int(round((5 + floor_num * 3 + rng.randi_range(0, 5)) * (1.0 + gold_find / 100.0)))
		return {"type": "boss", "item": boss_item, "gold": boss_gold}

	if rng.randf() < GOLD_VS_ITEM:
		var gold := int(round((2 + floor_num * 2 + rng.randi_range(0, 3)) * (1.0 + gold_find / 100.0)))
		return {"type": "gold", "gold": gold}

	var rolled := generate_item(state, loc_id, floor_num, false, monster_level, magic_find, rng)
	if rolled.is_empty():
		return {"type": "gold", "gold": 3 + floor_num * 2}
	return {"type": "item", "item": rolled}


## The special drops, in the exact priority order of the PWA. First hit wins.
func _roll_special(state, loc_id: int, floor_num: int, boss_drop: bool,
		monster_level: int, rng: RandomNumberGenerator) -> Dictionary:
	if boss_drop:
		return {}

	if rng.randf() < TOWN_PORTAL_CHANCE:
		var scroll := _item_by_id("townPortalScroll")
		if not scroll.is_empty():
			return scroll

	if rng.randf() < GEM_CHANCE:
		# Anti-repeat: if the same gem TYPE already dropped on this floor, prefer a
		# different one. Without this a floor can hand out four rubies in a row.
		var used: Array = []
		for d in _floor_drops(state):
			if d.get("type") == "item":
				var it: Dictionary = d.get("item", {})
				if it.get("type") == "gem":
					used.append(str(it.get("id", "")).split("_")[0])
		var types := ["ruby", "sapphire", "emerald", "topaz"]
		var available: Array = []
		for t in types:
			if not used.has(t):
				available.append(t)
		if available.is_empty():
			available = types
		var gem_type: String = available[rng.randi_range(0, available.size() - 1)]

		# Gem quality widens with depth: floor 0 gives the lowest tier only, floor 7+
		# can give any of the five.
		var qualities: Array = _data.gem_qualities()
		var max_idx := 0
		if floor_num < 1:
			max_idx = 0
		elif floor_num < 3:
			max_idx = 1
		elif floor_num < 5:
			max_idx = 2
		elif floor_num < 7:
			max_idx = 3
		else:
			max_idx = 4
		var q_idx := rng.randi_range(0, max_idx)
		var quality: String = qualities[mini(q_idx, qualities.size() - 1)]
		var gem_id := gem_type if quality == "normal" else "%s_%s" % [gem_type, quality]
		var gem := _item_by_id(gem_id)
		if not gem.is_empty():
			return gem

	if rng.randf() < RUNE_CHANCE:
		var rune := _item_by_id("magicRune")
		if not rune.is_empty():
			return rune

	if rng.randf() < JEWEL_CHANCE:
		var jewel := _items.generate_jewel(monster_level, int(state.hero()["level"]), rng)
		if not jewel.is_empty():
			# Jewels are generated, so they must be registered before they can be
			# referenced by id from an inventory slot.
			state.register_loot_item(jewel)
			return jewel

	if rng.randf() < POTION_CHANCE:
		# Potion tier follows the act: act N gives mostly tier N+1, sometimes a lower
		# tier the player has already outgrown. 60% heal / 40% mana.
		var pot_tier := mini(5, loc_id + 1)
		var is_heal := rng.randf() < 0.6
		var pick_tier := pot_tier if rng.randf() < 0.7 else (1 + rng.randi_range(0, pot_tier - 1))
		var base_name := "healingPotion" if is_heal else "manaPotion"
		var potion_id := base_name if pick_tier == 1 else "%s%d" % [base_name, pick_tier]
		var potion := _item_by_id(potion_id)
		if not potion.is_empty():
			return potion

	return {}


## generateLootItem — pick a base item appropriate to the depth, then roll quality
## and affixes onto it.
func generate_item(state, loc_id: int, floor_num: int, boss_drop: bool,
		monster_level: int, magic_find: int, rng: RandomNumberGenerator) -> Dictionary:
	var base := _pick_base_item(floor_num, rng)
	if base.is_empty():
		return {}
	var quality := ItemGen.roll_quality(rng, magic_find)
	return _items.generate(base, quality, monster_level, int(state.hero()["level"]), rng)


## Which base items are eligible: everything whose dropFloor has been reached.
## `dropFloor` in the data is a global depth (0-~150), not a per-act floor number,
## which is why it is compared against floor_num scaled by the act.
func _pick_base_item(floor_num: int, rng: RandomNumberGenerator) -> Dictionary:
	var depth := floor_num * 16
	var pool: Array = []
	for item in _data.items():
		if int(item.get("dropFloor", 0)) <= depth and item.get("id") != "fists":
			pool.append(item)
	if pool.is_empty():
		for item in _data.items():
			if item.get("id") == "fists":
				return item
		return {}
	return pool[rng.randi_range(0, pool.size() - 1)]


func _item_by_id(id: String) -> Dictionary:
	return _data.item(id)


func _floor_drops(state) -> Array:
	var drops: Variant = state.data.get("_floorLootDrops", [])
	return drops if drops is Array else []
