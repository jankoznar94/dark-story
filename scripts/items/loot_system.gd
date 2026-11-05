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
##
## ⚠️  THESE ARE ALSO THE BAG-FILLING DIAL, and Jan's report is the reason they moved:
## "Padá teď příliš mnoho lootu. Po každé oblasti mám plný batoh." Measured before the pass:
## the specials fired on ~30 % of kills and `GOLD_VS_ITEM` 0.70 handed gear to another 30 %,
## so ~51 % of every body left an item and one area filled a 40-cell bag. The GEAR rate is
## the one that matters (potions, gems and scrolls do not fill the grid the way a 2x4 weapon
## does), and it is cut roughly threefold — which is what keeps an area honest now that areas
## are three times larger and hold three times the bodies.
const TOWN_PORTAL_CHANCE := 0.02
const GEM_CHANCE := 0.02
const RUNE_CHANCE := 0.012
const JEWEL_CHANCE := 0.008
const POTION_CHANCE := 0.04
const GOLD_VS_ITEM := 0.91

## --- the kill's GRADE -------------------------------------------------------
## A champion pack pays better and an elite pack better still (Jan: "u elity bude vyrazne
## lepsi sance na lepsi loot"). Grade 0 = a normal body, 1 = champion, 2 = elite. The grade
## moves TWO dials, not one: how often a kill drops an ITEM at all (the gold-vs-item gate
## drops by GRADE_ITEM_SHIFT per step) and how good that item rolls (Magic Find is raised by
## GRADE_MAGIC_FIND). An elite additionally never leaves an empty hand: a gold-only roll is
## topped up with an item, the same rule `boss_drop` uses.
const GRADE_ITEM_SHIFT := 0.25
const GRADE_MAGIC_FIND := 60


var _data: Node
var _items: ItemGen


func _init(game_data: Node, item_gen: ItemGen) -> void:
	_data = game_data
	_items = item_gen


## Roll one drop. Returns {type: "gold"|"item"|"boss", gold: int, item: Dictionary}.
##
## `state` is passed in for the two things the roll reads from it: the accumulated
## floor drops (used for the gem anti-repeat) and the loot-item registry.
##
## `grade` is the kill's rank (0 normal, 1 champion, 2 elite) — see the constants above.
## It defaults to 0 so every older caller keeps the exact old rates.
func roll(state, loc_id: int, floor_num: int, boss_drop: bool, monster_level: int,
		magic_find: int, gold_find: int, rng: RandomNumberGenerator, grade: int = 0) -> Dictionary:
	magic_find += GRADE_MAGIC_FIND * grade
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

	if rng.randf() < GOLD_VS_ITEM - float(grade) * GRADE_ITEM_SHIFT:
		var gold := int(round((2 + floor_num * 2 + rng.randi_range(0, 3)) * (1.0 + gold_find / 100.0)))
		# An elite's hand is never empty: the gold is kept AND an item is added, so the best
		# body in the pack reads as the payoff.
		if grade >= 2:
			var bonus := generate_item(state, loc_id, floor_num, false, monster_level, magic_find, rng)
			if not bonus.is_empty():
				return {"type": "item", "item": bonus, "gold": gold}
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
	var base := _pick_base_item(state, loc_id, floor_num, rng)
	if base.is_empty():
		return {}
	var quality := ItemGen.roll_quality(rng, magic_find)
	return _items.generate(base, quality, monster_level, int(state.hero()["level"]), rng)


## Which base items are eligible: everything whose `dropFloor` this AREA has reached.
##
## ⚠️  `dropFloor` is a GLOBAL depth 0-149 — the same scale the PWA used — and it is the item
## system's whole "which area level may drop this" rule. The port multiplied the floor by 16
## instead (`depth = floor_num * 16`), which is not that scale at all: act 1 normal could reach
## depth 144 and hand out an Ataghan (`dropFloor` 106, an ELITE tier-5 blade). Jan: "z toho
## padne nějaký low level item, například Heavy gloves a z toho padne například Ataghan…
## jelikož jsme stále jen v Actu 1 obtížnosti normal, tak by neměly padat tak silné itemy."
##
## The formula is the PWA's own (`generateLootItem`): difficulty * 50 + act * 10 + floor, i.e.
## the 150-point scale of 3 difficulties x 5 acts x 10 areas. `floor_num` is the AREA within
## the act (0-9), not the number of packs woken — see `_roll_drop` in `survivor_run.gd`.
##
## The pick is WEIGHTED BY `tier`, again as the PWA has it: inside the band a higher tier is
## more likely, so the area's own ceiling is felt without ever exceeding it.
##
## ONLY EQUIPPABLE GEAR IS ELIGIBLE. The table also holds the consumables, the crafting
## rune and the town portal scroll, all at `dropFloor` 0, so an unfiltered pool put 12 of
## its 31 entries at act 1 (38.7 %) outside `generateLootItem` altogether: potions, runes
## and scrolls arrived through the GEAR branch, at full gear weight, unasked. That is what
## made act 1 drop "greater potions" — the branch rolls `quality` and affixes for a base
## that has none, and a tier-5 potion can carry no affixes at all, so `generate` returned
## the raw table entry. Every one of those has its own branch BELOW (`_roll_special`, and
## the 70/30 gold split); this function is the PWA's `generateLootItem`, whose type bands
## are weapon/armor/helmet/shield/belt/gloves/boots/ring/amulet and nothing else.
const GEAR_TYPES := ["weapon", "armor", "helmet", "shield", "belt", "gloves", "boots",
	"ring", "amulet"]


## The global depth of one area, on the PWA's 0-149 scale. `area` is clamped to the act's ten
## areas: the duel's `progress` can count past nine and a pack counter is not a depth at all.
static func area_depth(difficulty: int, act_id: int, area: int) -> int:
	return clampi(difficulty, 0, 2) * 50 + clampi(act_id, 0, 4) * 10 + clampi(area, 0, 9)


func _pick_base_item(state, loc_id: int, floor_num: int,
		rng: RandomNumberGenerator) -> Dictionary:
	var difficulty := int(state.data.get("difficulty", 0)) if state != null else 0
	var depth := area_depth(difficulty, loc_id, floor_num)
	var pool: Array = []
	var total_weight := 0
	for item in _data.items():
		if int(item.get("dropFloor", 0)) > depth or item.get("id") == "fists":
			continue
		if not GEAR_TYPES.has(str(item.get("type", ""))):
			continue
		pool.append(item)
		total_weight += maxi(1, int(item.get("tier", 1)))
	if pool.is_empty():
		# Nothing legal at this depth is a DATA error, not a licence to drop a fist: an empty
		# answer makes the caller pay gold instead of inventing an item the area never had.
		return {}
	var roll := rng.randf() * float(total_weight)
	for item in pool:
		roll -= float(maxi(1, int(item.get("tier", 1))))
		if roll <= 0.0:
			return item
	return pool[pool.size() - 1]


func _item_by_id(id: String) -> Dictionary:
	return _data.item(id)


func _floor_drops(state) -> Array:
	var drops: Variant = state.data.get("_floorLootDrops", [])
	return drops if drops is Array else []
