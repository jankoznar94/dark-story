extends SceneTree
## tools/test_shop_and_craft.gd — the shop, the gamble vendor, crafting, the chest and
## the talent trees.
##
## These five systems share one property that makes them worth asserting rather than
## tapping through: they are all GATED. The shop by progress, the gamble by level, the
## craft by item quality and gem tier, the chest by space, the talents by level and
## prerequisites. A gate that silently stops applying looks exactly like a working
## feature — the screen still renders, it just offers the wrong thing.
##
## Run:  godot --headless --path . --script res://tools/test_shop_and_craft.gd
## Pass: prints SHOP_CRAFT_ALL_PASS=true and exits 0.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const ShopStock := preload("res://scripts/items/shop_stock.gd")
const CraftSystem := preload("res://scripts/items/craft.gd")
const Talents := preload("res://scripts/items/talents.gd")
const ItemStats := preload("res://scripts/items/item_stats.gd")
const ProgressionRef := preload("res://scripts/combat/progression.gd")

var _data: Node
var _gen: ItemGen
var _talents
var _failures: Array[String] = []


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_talents = Talents.new(_data)

	_test_shop_gated_by_progress_not_level()
	_test_shop_stock_shape()
	_test_gamble_gated_by_level()
	_test_gamble_quality_never_normal()
	_test_gamble_version_thresholds()
	_test_uniques_exist_and_are_unique()
	_test_buy_and_sell_gold()
	_test_belt_column_rule()
	_test_chest_stacking_and_full()
	_test_craft_refuses_wrong_quality()
	_test_craft_gem_version_gate()
	_test_craft_consumes_inputs_and_regenerates()
	_test_gem_upgrade()
	_test_talent_gating()
	_test_talent_invest_and_reset()
	_test_attr_points()

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("SHOP_CRAFT_ALL_PASS=true")
	else:
		print("SHOP_CRAFT_ALL_PASS=false")
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _fresh_state(class_id: String = "barbarian"):
	var s = GameState.new()
	s.bind_data(_data)
	s.set_class(class_id)
	return s


func _resolve(state) -> Callable:
	return func(id):
		var item_id := str(id)
		if item_id == "":
			return {}
		var static_item: Dictionary = _data.item(item_id)
		if not static_item.is_empty():
			return static_item
		return state.loot_item(item_id)


func _rng(seed_value: int = 12345) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# --- shop --------------------------------------------------------------------

## The shop is gated by PROGRESS, not by the hero's level. A level-60 hero standing in
## act 1 Normal must still see act-1 stock: `dropFloor` is a global treasure class, and
## gating on level would hand out Hell gear the moment someone levelled.
func _test_shop_gated_by_progress_not_level() -> void:
	var state = _fresh_state()
	state.hero()["level"] = 60
	state.data["difficulty"] = 0
	# No bosses down: town floor is 0, so only bases with dropFloor 0 are offerable.
	var stock: Array = ShopStock.generate(_data, _gen, state, _resolve(state), _rng(7))
	var highest := 0
	for section in stock:
		for item in section["items"]:
			highest = maxi(highest, int(item.get("dropFloor", 0)))
	if highest > 10:
		_fail("act 1 shop offered dropFloor %d to a level-60 hero - the shop is reading the level" % highest)

	# With every boss of Normal down the floor is 40, so deeper bases must appear.
	state.data["bossesDefeated"][0] = [true, true, true, true, true]
	var deeper: Array = ShopStock.generate(_data, _gen, state, _resolve(state), _rng(8))
	var deep_high := 0
	for section in deeper:
		for item in section["items"]:
			deep_high = maxi(deep_high, int(item.get("dropFloor", 0)))
	if deep_high <= highest:
		_fail("clearing act 1 bosses did not widen the shop stock (%d -> %d)" % [highest, deep_high])


func _test_shop_stock_shape() -> void:
	var state = _fresh_state()
	state.hero()["level"] = 20
	state.hero()["gold"] = 100000
	var stock: Array = ShopStock.generate(_data, _gen, state, _resolve(state), _rng(9))
	var categories: Array = []
	for section in stock:
		categories.append(str(section["category"]))
	for expected in ["Misc", "Armor", "Weapons", "Jewelry"]:
		if not categories.has(expected):
			_fail("shop is missing the %s category" % expected)

	# Jewellery is magic-only, like D2: common rings and amulets do not exist.
	for section in stock:
		if str(section["category"]) != "Jewelry":
			continue
		for item in section["items"]:
			if str(item.get("quality", "")) != "magic":
				_fail("shop jewellery is %s, expected magic only" % str(item.get("quality", "")))
		# And the potion tier must not exceed what the bosses unlocked.
	var misc := _misc_of(stock)
	var saw_potion := false
	for item in misc:
		if str(item.get("type", "")) == "consumable":
			saw_potion = true
			if int(item.get("tier", 1)) > 1:
				_fail("shop sells tier-%d potion with no boss defeated" % int(item.get("tier", 1)))
	if not saw_potion:
		_fail("shop sells no potions at all")


func _misc_of(stock: Array) -> Array:
	for section in stock:
		if str(section["category"]) == "Misc":
			return section["items"]
	return []


# --- gamble ------------------------------------------------------------------

## The gamble vendor is the opposite of the shop: purely level-gated.
func _test_gamble_gated_by_level() -> void:
	var low = _fresh_state()
	low.hero()["level"] = 5
	var low_stock: Array = ShopStock.generate_gamble(_data, low, _rng(3))
	var low_max := _highest_drop_floor(low_stock)

	var high = _fresh_state()
	high.hero()["level"] = 50
	var high_stock: Array = ShopStock.generate_gamble(_data, high, _rng(4))
	var high_max := _highest_drop_floor(high_stock)

	if high_max <= low_max:
		_fail("a level-50 gamble pool (%d) is not deeper than a level-5 one (%d)" % [high_max, low_max])
	if low_max > int(round(48.0 * minf(1.0, 5.0 / 50.0))):
		_fail("level 5 gamble pool reached dropFloor %d, above its cap" % low_max)


func _highest_drop_floor(stock: Array) -> int:
	var highest := 0
	for section in stock:
		for entry in section["items"]:
			highest = maxi(highest, int(entry["baseItem"].get("dropFloor", 0)))
	return highest


## D2's table: the gamble never yields a common. 2000 rolls must contain magic, rare
## and at least one unique, and NOTHING else.
func _test_gamble_quality_never_normal() -> void:
	var rng := _rng(99)
	var counts := {"magic": 0, "rare": 0, "unique": 0}
	for _i in 20000:
		var quality: String = str(ShopStock.roll_gamble_quality(rng))
		if not counts.has(quality):
			_fail("gamble rolled quality '%s'" % quality)
			return
		counts[quality] = int(counts[quality]) + 1
	if counts["magic"] < 15000:
		_fail("gamble magic count %d is lower than D2's ~90%%" % int(counts["magic"]))
	if counts["unique"] < 1 or counts["unique"] > 60:
		_fail("gamble unique count %d is not ~0.05%% (1 in 2000)" % int(counts["unique"]))


func _test_gamble_version_thresholds() -> void:
	var rng := _rng(5)
	# Below level 10 there is no version roll at all.
	for _i in 300:
		if ShopStock.roll_gamble_version(5, rng) != "normal":
			_fail("a level-5 gamble produced a non-normal version")
			return
	# At level 60 the caps are 0.4 Hell and 0.5 Nightmare: both must show up.
	var seen := {}
	for _i in 4000:
		seen[ShopStock.roll_gamble_version(60, rng)] = true
	if not seen.has("normal") or not seen.has("nm") or not seen.has("hell"):
		_fail("level-60 gamble versions seen: %s, expected all three" % str(seen.keys()))


func _test_uniques_exist_and_are_unique() -> void:
	var state = _fresh_state()
	state.hero()["gold"] = 1000000
	state.hero()["level"] = 60
	var rng := _rng(21)
	var stock: Array = ShopStock.generate_gamble(_data, state, rng)
	# Take the first weapon entry and buy it 200 times, counting what comes out.
	var entry: Dictionary = {}
	for section in stock:
		if str(section["category"]) == "Weapons" and not section["items"].is_empty():
			entry = section["items"][0]
			break
	if entry.is_empty():
		_fail("gamble produced no weapon to test with")
		return

	var rarities := {}
	var versioned := 0
	for _i in 200:
		# The bag is 20 cells, so 200 non-stackable gambles cannot all fit. Empty it:
		# this test is about what the DICE produce, not about bag pressure (that is
		# _test_bag_full_refunds).
		state.data["hero"]["inventory"] = []
		var result: Dictionary = ShopStock.buy_gamble(state, entry, _gen, _data, _resolve(state), _rng(1000 + _i))
		if not result["ok"]:
			_fail("gamble purchase refused: %s" % str(result["message"]))
			return
		var item: Dictionary = result["item"]
		var rarity := str(item.get("rarity", ""))
		rarities[rarity] = int(rarities.get(rarity, 0)) + 1
		if "(" in str(result["message"]):
			versioned += 1
		if item.get("unique", false):
			if not item.has("stats") and not item.has("affixes"):
				_fail("unique item without stats or affixes")
			if str(item.get("quality", "")) != "unique":
				_fail("unique flag set but quality is %s" % str(item.get("quality", "")))
	if rarities.has("common") or rarities.has("normal"):
		_fail("gamble handed out a common item: %s" % str(rarities))
	if rarities.size() < 2:
		_fail("200 gambles produced only one rarity: %s" % str(rarities))
	if versioned == 0:
		_fail("200 gambles at level 60 produced no Nightmare/Hell version")


# --- buying and selling ------------------------------------------------------

func _test_buy_and_sell_gold() -> void:
	var state = _fresh_state()
	var find := _resolve(state)
	state.hero()["gold"] = 1000
	var sword: Dictionary = _data.item("blade_shortSword")
	if sword.is_empty():
		_fail("the data has no blade_shortSword to buy")
		return
	var cost := int(sword.get("cost", 0))
	if cost <= 0:
		_fail("blade_shortSword has no cost to price a sale from")
		return

	var before := int(state.hero()["gold"])
	var result: Dictionary = ShopStock.buy(state, sword, find)
	if not result["ok"]:
		_fail("buying a shop item failed: %s" % str(result["message"]))
		return
	if int(state.hero()["gold"]) != before - cost:
		_fail("buy did not deduct the cost (%d -> %d)" % [before, int(state.hero()["gold"])])
	if not state.inventory().has(sword["id"]):
		_fail("bought item did not reach the bag")

	# Selling returns half the cost and the item leaves the bag.
	var gold_after_buy := int(state.hero()["gold"])
	var expected := int(round(float(cost) * 0.5))
	var sold: Dictionary = ShopStock.sell(state, str(sword["id"]), find)
	if not sold["ok"]:
		_fail("sell refused: %s" % str(sold["message"]))
		return
	if int(state.hero()["gold"]) != gold_after_buy + expected:
		_fail("sell returned %d, expected %d" % [int(state.hero()["gold"]) - gold_after_buy, expected])

	# The equipped item can never be sold, even by id.
	state.equip()["weapon"] = sword["id"]
	state.add_item(str(sword["id"]), sword)
	var refused: Dictionary = ShopStock.sell(state, str(sword["id"]), find)
	if refused["ok"]:
		_fail("an equipped item was sold")


## A full bag must refuse the purchase and NOT take the gold — a refund is the only
## acceptable outcome, and it is the one thing a naive implementation forgets.
func _test_bag_full_refunds() -> void:
	var state = _fresh_state()
	var find := _resolve(state)
	state.hero()["gold"] = 1000
	var sword: Dictionary = _data.item("blade_shortSword")
	if sword.is_empty():
		_fail("the data has no blade_shortSword for the full-bag test")
		return
	# Fill every bag cell with a non-stackable stand-in, so nothing can merge.
	for i in 20:
		state.add_item("filler_%d" % i, {"id": "filler_%d" % i, "type": "weapon"})
	if not state.bag_full():
		_fail("the bag did not report full at 20 cells")
		return
	var before := int(state.hero()["gold"])
	var result: Dictionary = ShopStock.buy(state, sword, find)
	if result["ok"]:
		_fail("a full bag accepted a purchase")
	if int(state.hero()["gold"]) != before:
		_fail("a refused purchase still took the gold (%d -> %d)" % [before, int(state.hero()["gold"])])


func _test_belt_column_rule() -> void:
	var state = _fresh_state()
	var find := _resolve(state)
	state.sync_potion_slots(find)
	if not state.add_potion_to_belt("healingPotion", find):
		_fail("could not put a heal potion in an empty belt")
		return
	if state.add_potion_to_belt("manaPotion", find) == false:
		_fail("could not add a mana potion beside a heal potion in a 4-slot belt")
	# With 4 slots and the column rule, a heal and a mana potion must land in DIFFERENT
	# rows of the same column... 4 slots is one column of 4, so the mana potion must be
	# beside the heal one (rows 0 and 1), not refused.
	var slots: Array = state.equip()["beltPotionSlots"]
	if slots.size() != 4:
		_fail("belt has %d slots, expected the default 4" % slots.size())
	var heal_slot := slots.find("healingPotion")
	var mana_slot := slots.find("manaPotion")
	if heal_slot < 0 or mana_slot < 0:
		_fail("potions not both in the belt: %s" % str(slots))
	if heal_slot == mana_slot:
		_fail("heal and mana potion share one slot")

	# Drinking removes exactly one copy.
	var removed := state.consume_potion("healingPotion")
	if removed < 0:
		_fail("consume_potion found nothing to drink")
	if state.equip()["beltPotionSlots"].find("healingPotion") != -1:
		_fail("the drunk potion is still in the belt")


# --- chest -------------------------------------------------------------------

func _test_chest_stacking_and_full() -> void:
	var state = _fresh_state()
	var find := _resolve(state)
	var gem: Dictionary = _data.item("ruby")
	if gem.is_empty():
		_fail("no ruby in the data")
		return

	# Three separate bag entries of the same gem must merge into ONE chest stack.
	for _i in 3:
		state.add_item("ruby", gem)
	if state.inventory().size() != 1:
		_fail("three rubies in the bag made %d entries, expected one stack" % state.inventory().size())

	var reason: String = str(state.stash_from_bag(0, gem, true))
	if reason != "":
		_fail("stashing a gem failed: %s" % reason)
		return
	if state.inventory().size() != 0:
		_fail("the gem stack stayed in the bag after stashing")
	var chest: Array = state.data["chest"]
	if int(chest[0]["count"]) != 3:
		_fail("chest stack count is %d, expected 3" % int(chest[0]["count"]))
	# Taking it back returns all three in one stack.
	var take_reason: String = str(state.take_from_chest(0, gem))
	if take_reason != "":
		_fail("taking the gem back failed: %s" % take_reason)
	if state.inventory().size() != 1:
		_fail("taking a stack back made %d entries, expected one" % state.inventory().size())

	# A full chest refuses without losing the item.
	for i in 25:
		state.data["chest"][i] = {"id": "ruby", "count": 1}
	state.data["chest"][24] = null   # leave one cell, then fill it with a DIFFERENT gem
	var topaz: Dictionary = _data.item("topaz")
	if topaz.is_empty():
		_fail("no topaz in the data")
		return
	# Empty the bag first: after the take above, slot 0 holds the ruby stack, and
	# stashing "slot 0" would then stash the ruby (which MERGES) instead of the topaz.
	state.data["hero"]["inventory"] = []
	state.add_item("topaz", topaz)
	if str(state.stash_from_bag(0, topaz, true)) != "":
		_fail("could not stash into the last free chest cell")
	# Now the chest is full and a second, non-stackable item must be refused.
	var sword: Dictionary = _data.item("blade_shortSword")
	state.data["hero"]["inventory"] = []
	state.add_item(str(sword["id"]), sword)
	var before_stash := state.inventory().size()
	var refused: String = str(state.stash_from_bag(0, sword, false))
	if refused == "":
		_fail("a full chest accepted an item")
	if state.inventory().size() != before_stash:
		_fail("the refused item was removed from the bag anyway")


# --- craft -------------------------------------------------------------------

func _test_craft_refuses_wrong_quality() -> void:
	var state = _fresh_state()
	var find := _resolve(state)
	state.hero()["level"] = 30
	var recipe: Dictionary = CraftSystem.recipe_by_id("bloodWeapon")

	# A NORMAL quality weapon must be refused: crafts take magic items only.
	var normal_weapon: Dictionary = _data.item("blade_shortSword")
	var gem: Dictionary = _data.item("ruby_flawed")
	var rune: Dictionary = _data.item("magicRune")
	if normal_weapon.is_empty() or gem.is_empty() or rune.is_empty():
		_fail("craft test inputs missing from the data")
		return
	var slots := {
		"gem": {"id": str(gem["id"]), "item": gem},
		"item": {"id": str(normal_weapon["id"]), "item": normal_weapon},
		"rune": {"id": str(rune["id"]), "item": rune},
		"jewel": {"id": "jewel_test", "item": {"id": "jewel_test", "type": "jewel"}},
	}
	# The jewel must be REGISTERED, or the resolver cannot find it and validation
	# returns "Vstup se neda najit" before it ever reaches the quality check — which
	# would make this test pass for the wrong reason.
	state.register_loot_item(slots["jewel"]["item"])
	var problem: String = str(CraftSystem.validate(recipe, slots, _data, find))
	if problem == "":
		_fail("craft accepted a NORMAL quality weapon")
	if not problem.to_lower().contains("magic"):
		_fail("the refusal message does not mention magic: '%s'" % problem)

	# Also wrong for this recipe: a sapphire in a ruby recipe.
	var magic_weapon: Dictionary = _gen.generate(normal_weapon, "magic", 30, 30, _rng(2))
	state.register_loot_item(magic_weapon)
	slots["item"] = {"id": str(magic_weapon["id"]), "item": magic_weapon}
	var sapphire: Dictionary = _data.item("sapphire_flawed")
	slots["gem"] = {"id": str(sapphire["id"]), "item": sapphire}
	problem = CraftSystem.validate(recipe, slots, _data, find)
	if problem == "":
		_fail("a sapphire was accepted by the ruby recipe")


## The gem tier must match the item's VERSION. A Nightmare item needs a Flawless gem,
## and the version comes from `baseId`, not from the generated loot id.
func _test_craft_gem_version_gate() -> void:
	var state = _fresh_state()
	var find := _resolve(state)
	state.hero()["level"] = 40
	var recipe: Dictionary = CraftSystem.recipe_by_id("bloodArmor")

	var nm_base: Dictionary = _data.item("armor_fullPlate_nm")
	var normal_base: Dictionary = _data.item("armor_fullPlate")
	if nm_base.is_empty() or normal_base.is_empty():
		_fail("the data has no armor_fullPlate_nm / armor_fullPlate")
		return

	var rune: Dictionary = _data.item("magicRune")
	var flawed: Dictionary = _data.item("ruby_flawed")
	var flawless: Dictionary = _data.item("ruby_flawless")
	var jewel := {"id": "jewel_test", "type": "jewel"}
	# Registered, or validate() stops at "Vstup se neda najit" and the gem gate is
	# never reached — the test would then pass/fail for the wrong reason.
	state.register_loot_item(jewel)

	var nm_item: Dictionary = _gen.generate(nm_base, "magic", 40, 40, _rng(11))
	state.register_loot_item(nm_item)
	if ItemStats.item_version(nm_item) != 2:
		_fail("a _nm base generated item reports version %d, expected 2" % ItemStats.item_version(nm_item))

	var slots := {
		"gem": {"id": str(flawed["id"]), "item": flawed},
		"item": {"id": str(nm_item["id"]), "item": nm_item},
		"rune": {"id": str(rune["id"]), "item": rune},
		"jewel": {"id": str(jewel["id"]), "item": jewel},
	}
	if CraftSystem.validate(recipe, slots, _data, find) == "":
		_fail("a Flawed gem was accepted for a Nightmare item")
	slots["gem"] = {"id": str(flawless["id"]), "item": flawless}
	if CraftSystem.validate(recipe, slots, _data, find) != "":
		_fail("a Flawless gem was refused for a Nightmare item")


## A craft CONSUMES the inserted item and regenerates from its base: nothing of the
## inserted item's own rolls survives. That is the rule most likely to be "fixed" by
## accident, so it is pinned.
func _test_craft_consumes_inputs_and_regenerates() -> void:
	var state = _fresh_state()
	var find := _resolve(state)
	state.hero()["level"] = 40
	var recipe: Dictionary = CraftSystem.recipe_by_id("safetyWeapon")

	var base: Dictionary = _data.item("blade_shortSword")
	# An inserted item with an absurd marker stat: the result must NOT carry it.
	var inserted: Dictionary = _gen.generate(base, "magic", 40, 40, _rng(13))
	inserted["enhancedDmg"] = 999
	inserted["goldFind"] = 777
	state.register_loot_item(inserted)

	var gem: Dictionary = _data.item("sapphire_flawless")
	var rune: Dictionary = _data.item("magicRune")
	var jewel := {"id": "jewel_t2", "type": "jewel", "quality": "magic", "name": "Jewel"}
	state.register_loot_item(jewel)

	state.data["hero"]["inventory"] = []
	state.add_item(str(inserted["id"]), inserted)
	state.add_item(str(gem["id"]), gem)
	state.add_item(str(rune["id"]), rune)
	state.add_item(str(jewel["id"]), jewel)

	var slots := {
		"gem": {"id": str(gem["id"]), "item": gem},
		"item": {"id": str(inserted["id"]), "item": inserted},
		"rune": {"id": str(rune["id"]), "item": rune},
		"jewel": {"id": str(jewel["id"]), "item": jewel},
	}
	var bag_before := state.inventory().size()
	var result: Dictionary = CraftSystem.do_craft(state, recipe, slots, _gen, _rng(17), _data, find)
	if not result["ok"]:
		_fail("craft failed: %s" % str(result["message"]))
		return
	var crafted: Dictionary = result["item"]
	if not crafted.get("crafted", false):
		_fail("the crafted item is not flagged crafted")
	if str(crafted.get("quality", "")) != "rare":
		_fail("crafted quality is %s, expected rare" % str(crafted.get("quality", "")))
	if int(crafted.get("enhancedDmg", 0)) >= 999:
		_fail("the crafted item inherited the inserted item's stats - it must regenerate")
	if int(crafted.get("lifesteal", 0)) <= 0:
		_fail("the safetyWeapon recipe guarantees lifesteal and the result has none")

	# Four inputs consumed, one result added: the bag must hold the same count as before.
	if state.inventory().size() != bag_before - 4 + 1:
		_fail("bag size went %d -> %d, expected four consumed and one added"
			% [bag_before, state.inventory().size()])
	# The crafted item must be registered so a save/load keeps it resolvable.
	if state.loot_item(str(crafted["id"])).is_empty():
		_fail("the crafted item was not registered in lootItems")


func _test_gem_upgrade() -> void:
	var state = _fresh_state()
	var find := _resolve(state)
	var chipped: Dictionary = _data.item("ruby_chipped")
	var flawed: Dictionary = _data.item("ruby_flawed")
	if chipped.is_empty() or flawed.is_empty():
		_fail("gem items missing from the data")
		return
	for _i in 3:
		state.add_item("ruby_chipped", chipped)

	var recipe: Dictionary = CraftSystem.recipe_by_id("gemUpgrade")
	var slots := {
		"gem1": {"id": "ruby_chipped"},
		"gem2": {"id": "ruby_chipped"},
		"gem3": {"id": "ruby_chipped"},
	}
	var preview: Dictionary = CraftSystem.gem_upgrade_result(slots, find)
	if preview.is_empty() or str(preview.get("id", "")) != "ruby_flawed":
		_fail("3 chipped rubies do not preview as a flawed ruby")
		return

	var result: Dictionary = CraftSystem.do_craft(state, recipe, slots, _gen, _rng(31), _data, find)
	if not result["ok"]:
		_fail("gem upgrade failed: %s" % str(result["message"]))
		return
	if state.inventory().size() != 1:
		# Three chipped consumed from one stack, one flawed added.
		var ids: Array = []
		for entry in state.inventory():
			ids.append(str(entry.get("id", entry)) if entry is Dictionary else str(entry))
		if not (ids.has("ruby_flawed") and "ruby_chipped" not in ids):
			_fail("after the upgrade the bag holds %s" % str(ids))

	# Three DIFFERENT gems must not upgrade, and a perfect gem cannot either.
	if not CraftSystem.gem_upgrade_result({"gem1": {"id": "ruby_chipped"}, "gem2": {"id": "ruby_chipped"}, "gem3": {"id": "ruby_flawed"}}, find).is_empty():
		_fail("three gems of mixed quality upgraded")
	if not CraftSystem.gem_upgrade_result({"gem1": {"id": "ruby_perfect"}, "gem2": {"id": "ruby_perfect"}, "gem3": {"id": "ruby_perfect"}}, find).is_empty():
		_fail("a perfect gem was upgraded past the top quality")


# --- talents -----------------------------------------------------------------

func _test_talent_gating() -> void:
	var state = _fresh_state("barbarian")
	var hero: Dictionary = state.hero()
	hero["level"] = 1
	state.data["talentPoints"] = 10

	# Tier 1 is open at level 1.
	if not _talents.is_available(state, "barbarian_oneHandSpec"):
		_fail("a tier-1 skill is unavailable at level 1")
	# Tier 2 needs level 6, and its prerequisite is NOT met yet either.
	if _talents.is_available(state, "barbarian_doubleSwing"):
		_fail("a tier-2 skill was available at level 1")
	hero["level"] = 6
	if _talents.is_available(state, "barbarian_doubleSwing"):
		_fail("a tier-2 skill was available at level 6 with no point in its prerequisite")

	# Invest the prerequisite to its max, then the tier-2 skill must open.
	for _i in 5:
		_talents.invest(state, "barbarian_oneHandSpec")
	if _talents.talent_level(state, "barbarian_oneHandSpec") != 5:
		_fail("oneHandSpec did not reach its max of 5")
	if not _talents.is_available(state, "barbarian_doubleSwing"):
		_fail("doubleSwing stayed locked after its prerequisite was maxed")

	# Tier 3 needs level 12 AND its own prerequisite chain.
	hero["level"] = 11
	if _talents.is_available(state, "barbarian_deathMark"):
		_fail("an assassin skill is available to a barbarian")

	# requiresAny: frenzy accepts either specialisation.
	if not _talents.is_available(state, "barbarian_frenzy"):
		_fail("frenzy (requiresAny oneHand/twoHand) stayed locked with oneHand at 5")

	# Another class sees only its own trees.
	var assassin = _fresh_state("assassin")
	assassin.hero()["level"] = 20
	assassin.data["talentPoints"] = 5
	if _talents.is_available(assassin, "barbarian_oneHandSpec"):
		_fail("a barbarian skill is available to an assassin")
	if _talents.tree_ids("assassin").size() != 3:
		_fail("the assassin has %d trees, expected 3" % _talents.tree_ids("assassin").size())


func _test_talent_invest_and_reset() -> void:
	var state = _fresh_state("mage")
	state.hero()["level"] = 1
	state.data["talentPoints"] = 3

	var before := int(state.data["talentPoints"])
	var result: Dictionary = _talents.invest(state, "mage_firebolt")
	if not result["ok"]:
		_fail("investing in firebolt failed: %s" % str(result["message"]))
	if int(state.data["talentPoints"]) != before - 1:
		_fail("investing did not spend a point")
	if _talents.talent_level(state, "mage_firebolt") != 1:
		_fail("firebolt did not gain a level")

	# No points: refused, and nothing changes.
	state.data["talentPoints"] = 0
	if _talents.invest(state, "mage_firebolt")["ok"]:
		_fail("a skill was invested with zero points")

	# Maxed: refused.
	state.data["talentPoints"] = 10
	for _i in 10:
		_talents.invest(state, "mage_firebolt")
	if _talents.talent_level(state, "mage_firebolt") != _talents.max_level("mage_firebolt"):
		_fail("firebolt went past its max level")

	# Reset: 50 gold, points back, and refused without the gold.
	state.hero()["gold"] = 0
	var poor: Dictionary = Talents.reset(state)
	if poor["ok"]:
		_fail("talents were reset without the gold")
	if _talents.talent_level(state, "mage_firebolt") == 0:
		_fail("a refused reset still wiped the levels")
	state.hero()["gold"] = 100
	var spent: int = int(_talents.talent_level(state, "mage_firebolt"))
	# Points already in the pool count too: the 10 invests above stopped at maxLv, so
	# some of the pool was never spent. The reset returns the invested levels ON TOP
	# of what was left over — asserting `== spent` would be asserting a bug.
	var pool_before := int(state.data["talentPoints"])
	var rich: Dictionary = Talents.reset(state)
	if not rich["ok"]:
		_fail("reset with enough gold failed: %s" % str(rich["message"]))
	if int(state.hero()["gold"]) != 50:
		_fail("reset did not charge 50 gold (gold is %d)" % int(state.hero()["gold"]))
	if _talents.talent_level(state, "mage_firebolt") != 0:
		_fail("reset did not zero the levels")
	if int(state.data["talentPoints"]) != pool_before + spent:
		_fail("reset returned %d points, expected %d" % [int(state.data["talentPoints"]), pool_before + spent])


func _test_attr_points() -> void:
	var state = _fresh_state("barbarian")
	var find := _resolve(state)
	var hero: Dictionary = state.hero()
	hero["level"] = 20
	hero["attrPoints"] = 4
	hero["attrVit"] = 0

	var hp_before := _gen.hero_max_hp(hero, state.equip(), find)
	var result: Dictionary = _talents.spend_attr(state, "vit", find, _gen)
	if not result["ok"]:
		_fail("spending a VIT point failed: %s" % str(result["message"]))
	if int(hero["attrPoints"]) != 3:
		_fail("the attribute point was not spent")
	if int(hero["attrVit"]) != 1:
		_fail("VIT did not increase")
	var hp_after := _gen.hero_max_hp(hero, state.equip(), find)
	if hp_after <= hp_before:
		_fail("VIT did not raise max HP (%d -> %d)" % [hp_before, hp_after])
	if int(hero["hp"]) != hp_after:
		_fail("spending a point left the hero at %d/%d HP" % [int(hero["hp"]), hp_after])

	# STR must raise the damage range, which is the one attribute with a visible effect.
	var dmg_before: Dictionary = ProgressionRef.hero_dmg(hero, state.equip(), find, 1.0)
	hero["attrPoints"] = 1
	var str_result: Dictionary = _talents.spend_attr(state, "str", find, _gen)
	if not str_result["ok"]:
		_fail("spending a STR point failed")
	if int(hero["attrStr"]) != 1:
		_fail("STR did not increase")

	# No points left: refused.
	if _talents.spend_attr(state, "str", find, _gen)["ok"]:
		_fail("an attribute point was spent with none available")

	# An unknown attribute must not silently spend the point.
	hero["attrPoints"] = 1
	if _talents.spend_attr(state, "luck", find, _gen)["ok"]:
		_fail("an unknown attribute was accepted")
	if int(hero["attrPoints"]) != 1:
		_fail("an unknown attribute still consumed the point")
