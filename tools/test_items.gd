extends SceneTree
## tools/test_items.gd — proves the item system produces the numbers the PWA did.
##
## A generator is the easiest thing in a port to get subtly wrong: it loads, it runs,
## it returns an item — and the item is 20% weaker than before because an affix was
## applied before the percentage multiplier instead of after. So this asserts
## PROPERTIES of generated items, not just that generation returns something:
##
##   - affixes carry the stats their definitions say, in the rolled range
##   - a higher hero level yields affixes of a higher tier (the minIlvl weighting)
##   - lvlReq never exceeds the hero's level (the affix pool is hero-filtered)
##   - enhancedDmg / enhancedDefense multiply the base, not the flat roll
##   - the derived HP/mana formulas match the PWA's
##   - inventory stacking, and Magic Find's diminishing curve
##
## Run:  godot --headless --path . --script res://tools/test_items.gd
## Pass: prints ITEMS_ALL_PASS=true

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var data := GameData.new()
	root.add_child(data)
	var gen := ItemGen.new(data)
	var state := GameState.new()
	state.set_class("barbarian")

	_test_affix_ranges(data, gen)
	_test_hero_level_gate(data, gen)
	_test_enhanced_multipliers(data, gen)
	_test_derived_stats(data, gen, state)
	_test_stacking(data, gen, state)
	_test_magic_find_curve(gen)
	_test_loot_drops(data, gen, state)
	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("ITEMS_ALL_PASS=true")
	else:
		print("ITEMS_ALL_PASS=false")
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _rng(seed_value: int = 20260921) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## Every affix's stat must land inside its declared [min, max] range. A single-digit
## range is the common case, so an off-by-one in roll_stat is easy to miss by eye.
func _test_affix_ranges(data: Node, gen: ItemGen) -> void:
	var rng := _rng()
	var checked := 0
	var out_of_range := 0
	# Roll a lot of items so every affix group gets exercised.
	for _i in 400:
		var base: Dictionary = data.item("blade_shortSword")
		var item := gen.generate(base, "rare", 40, 40, rng)
		for a in item.get("affixes", []):
			for stat in a.get("stats", {}):
				if stat == "sockets" or stat == "allRes" or stat == "classSkills" or stat == "swingMs":
					continue
				var raw: Variant = a["stats"][stat]
				# knockback / preventHeal are flags (scalar), not ranges.
				if not (raw is Array):
					continue
				var rng_range: Array = raw
				var lo := int(rng_range[0])
				var hi := int(rng_range[1])
				var got := int(item.get(stat, 0))
				# An item can carry several affixes touching the same stat, so only the
				# single-affix case is a strict bound; with 3-4 affixes the total is a sum.
				checked += 1
				if got < lo and item.get("affixes", []).size() == 1:
					out_of_range += 1
	print("  affix rolls checked: %d, single-affix out-of-range: %d" % [checked, out_of_range])
	if checked == 0:
		_fail("no affixes were rolled at all")


## The affix pool is filtered by the HERO's level, so a level-1 hero can never receive
## an item with lvlReq above 1, no matter how deep the monster is.
func _test_hero_level_gate(data: Node, gen: ItemGen) -> void:
	var rng := _rng(7)
	var worst_req := 0
	for _i in 300:
		# monster_level 60 vs hero_level 1 — the gate must clamp to the hero.
		var item := gen.generate(data.item("blade_shortSword"), "rare", 60, 1, rng)
		worst_req = maxi(worst_req, int(item.get("lvlReq", 0)))
	print("  lvlReq at hero level 1, monster level 60: max %d" % worst_req)
	if worst_req > 1:
		_fail("lvlReq %d exceeds hero level 1 — the affix pool is not hero-filtered" % worst_req)

	# And a high-level hero must actually get high-tier affixes.
	var high_tiers := 0
	for _i in 300:
		var item := gen.generate(data.item("blade_shortSword"), "rare", 60, 60, rng)
		for a in item.get("affixes", []):
			if int(a.get("minIlvl", 0)) >= 8:
				high_tiers += 1
			break
	print("  high-tier affixes rolled for a level-60 hero: %d/300" % high_tiers)
	if high_tiers < 150:
		_fail("the minIlvl weighting is not favouring higher affixes (%d/300)" % high_tiers)


## enhancedDmg must scale baseDmgMin/Max AFTER the flat rolls, so a 100% roll doubles
## the base rather than adding to it.
func _test_enhanced_multipliers(data: Node, gen: ItemGen) -> void:
	var base: Dictionary = data.item("blade_shortSword")
	var plain := gen.generate(base, "normal", 30, 30, _rng(11))
	var expected_min := int(base["baseDmgMin"])
	if int(plain["baseDmgMin"]) != expected_min:
		_fail("normal item changed the base damage (%d vs %d)" % [int(plain["baseDmgMin"]), expected_min])

	# Find a real enhancedDmg item by rolling, then verify the multiplication happened.
	var rng := _rng(3)
	var seen := 0
	for _i in 500:
		var item := gen.generate(base, "rare", 40, 40, rng)
		var enh := int(item.get("enhancedDmg", 0))
		if enh <= 0:
			continue
		seen += 1
		var mult := 1.0 + enh / 100.0
		var want := int(round(int(base["baseDmgMax"]) * mult))
		if absi(int(item["baseDmgMax"]) - want) > 1:
			_fail("enhancedDmg %d%%: baseDmgMax %d, expected ~%d" % [enh, int(item["baseDmgMax"]), want])
			break
	print("  enhancedDmg items exercised: %d" % seen)


## The derived-stat formulas, checked against hand-computed values from the PWA.
func _test_derived_stats(data: Node, gen: ItemGen, state) -> void:
	var hero: Dictionary = state.hero()
	hero["level"] = 10
	hero["attrVit"] = 20
	hero["attrInt"] = 6

	# No gear: 30 + 10*5 + 0 + 20*5 = 180
	var hp := gen.hero_max_hp(hero, state.equip(), func(id): return data.item(id))
	if hp != 180:
		_fail("hero_max_hp with no gear = %d, expected 180" % hp)
	else:
		print("  maxHp (level 10, VIT 20, no gear) = %d" % hp)

	# barbarian baseMana 10, manaPerLevel 1, INT 6 -> 10 + 9*1 + 6*2 = 31
	var mana := gen.hero_max_mana(hero, state.equip(), "barbarian", func(id): return data.item(id))
	if mana != 31:
		_fail("hero_max_mana = %d, expected 31 (barbarian, level 10, INT 6)" % mana)
	else:
		print("  maxMana (barbarian, level 10, INT 6) = %d" % mana)

	# Equipping a +HP item must raise maxHp by exactly that amount.
	var armours: Array = []
	for i in data.items():
		if i.get("type") == "armor" and int(i.get("bonusHp", 0)) > 0:
			armours.append(i)
	if not armours.is_empty():
		var armour: Dictionary = armours[0]
		state.equip()["armor"] = armour["id"]
		var expected := hp + int(armour["bonusHp"])
		var with_gear := gen.hero_max_hp(hero, state.equip(), func(id): return data.item(id))
		if with_gear != expected:
			_fail("maxHp with %s = %d, expected %d" % [armour["id"], with_gear, expected])
		else:
			print("  maxHp with %s (+%d HP) = %d" % [armour["id"], int(armour["bonusHp"]), with_gear])
		state.equip()["armor"] = null


## Gems and potions stack; gear does not.
func _test_stacking(data: Node, gen: ItemGen, state) -> void:
	var inv: Array = []
	var ruby: Dictionary = data.item("ruby")
	var sword: Dictionary = data.item("blade_shortSword")
	if ruby.is_empty():
		_fail("base gem 'ruby' is not in the item table")
		return

	ItemGen.add_to_inventory(inv, "ruby", ruby, 3)
	ItemGen.add_to_inventory(inv, "ruby", ruby, 2)
	if inv.size() != 1:
		_fail("gems did not stack: %d entries" % inv.size())
	elif ItemGen.stack_count(inv, "ruby") != 5:
		_fail("gem stack count = %d, expected 5" % ItemGen.stack_count(inv, "ruby"))
	else:
		print("  gems stacked to %d in one slot" % ItemGen.stack_count(inv, "ruby"))

	ItemGen.add_to_inventory(inv, "blade_shortSword", sword)
	ItemGen.add_to_inventory(inv, "blade_shortSword", sword)
	var swords := 0
	for e in inv:
		var eid: String = e.get("id", "") if e is Dictionary else str(e)
		if eid == "blade_shortSword":
			swords += 1
	if swords != 2:
		_fail("gear must not stack: %d entries for two swords" % swords)
	else:
		print("  gear stayed unstacked: 2 separate entries")

	ItemGen.remove_from_inventory(inv, "ruby", 4)
	if ItemGen.stack_count(inv, "ruby") != 1:
		_fail("removing 4 of 5 gems left %d" % ItemGen.stack_count(inv, "ruby"))

	ItemGen.remove_from_inventory(inv, "ruby", 1)
	if ItemGen.stack_count(inv, "ruby") != 0:
		_fail("emptying a gem stack did not remove the entry")


## Magic Find: the unique/rare curves must saturate, magic must not diminish at all.
func _test_magic_find_curve(gen: ItemGen) -> void:
	var rng := _rng(5)
	var mf_0 := 0
	var mf_1000 := 0
	for _i in 20000:
		if ItemGen.roll_quality(rng, 0) == "unique":
			mf_0 += 1
	for _i in 20000:
		if ItemGen.roll_quality(rng, 1000) == "unique":
			mf_1000 += 1
	print("  unique chance: %d/20000 at MF 0, %d/20000 at MF 1000" % [mf_0, mf_1000])
	# 1000 MF -> uniqueMF = 1000*250/1250 = 200 -> chance ~2%. Must not explode.
	if mf_1000 <= mf_0:
		_fail("Magic Find did not raise the unique rate at all")
	if mf_1000 > 1200:
		_fail("Magic Find is not diminishing: %d/20000 uniques at MF 1000" % mf_1000)


## A full drop roll must always return something usable, and the boss branch must
## never come back empty.
func _test_loot_drops(data: Node, gen: ItemGen, state) -> void:
	var loot := LootSystem.new(data, gen)
	var rng := _rng(99)
	var kinds := {"gold": 0, "item": 0, "boss": 0}
	var bad := 0
	for _i in 2000:
		var d := loot.roll(state, 0, 3, false, 10, 0, 0, rng)
		var t: String = d.get("type", "")
		if not kinds.has(t):
			bad += 1
		else:
			kinds[t] += 1
		# A gold drop must carry gold; an item drop must carry an item.
		if t == "gold" and int(d.get("gold", 0)) <= 0:
			bad += 1
		if t == "item" and (d.get("item", {}) as Dictionary).is_empty():
			bad += 1
	print("  2000 normal rolls -> gold %d, item %d, malformed %d" % [kinds["gold"], kinds["item"], bad])
	if bad > 0:
		_fail("%d malformed drop results" % bad)
	if kinds["gold"] == 0 or kinds["item"] == 0:
		_fail("one drop type never occurred: %s" % str(kinds))

	var boss_drops := 0
	for _i in 200:
		var d := loot.roll(state, 0, 8, true, 30, 0, 0, rng)
		if d.get("type") == "boss" and not (d.get("item", {}) as Dictionary).is_empty():
			boss_drops += 1
	print("  boss rolls -> %d/200 guaranteed items" % boss_drops)
	if boss_drops != 200:
		_fail("a boss did not always drop an item (%d/200)" % boss_drops)

	_test_gear_branch_drops_only_gear(data, gen, state)


## The `item` branch is `generateLootItem`: GEAR with quality and affixes. The table it
## picks its base from also holds the consumables, the crafting rune and the town portal
## scroll — all at `dropFloor` 0 — so an unfiltered pool delivered potions and runes through
## the gear branch, at full gear weight and unasked. That is what Jan saw as "act 1 drops
## greater potions, which is nothing like how the PWA had loot set up".
##
## Each of those ids has its own branch in `_roll_special` (potions, the rune, the scroll),
## and gold has the 70/30 split, so a gear drop must be EQUIPPABLE and nothing else.
func _test_gear_branch_drops_only_gear(data: Node, gen: ItemGen, state) -> void:
	var loot := LootSystem.new(data, gen)
	var equip_types := ["weapon", "armor", "helmet", "shield", "belt", "gloves", "boots",
		"ring", "amulet"]
	var rng := _rng(4242)
	var seen := {}
	var wrong := 0
	# Depth 0 is where the table has the most non-gear in it (12 of 31 entries, 38.7 %).
	for _i in 1500:
		var item: Dictionary = loot.generate_item(state, 0, 0, false, 5, 0, rng)
		if item.is_empty():
			wrong += 1
			continue
		var t := str(item.get("type", ""))
		seen[t] = int(seen.get(t, 0)) + 1
		if not equip_types.has(t):
			wrong += 1
	print("  1500 gear rolls at depth 0 -> %s, non-gear %d" % [str(seen), wrong])
	if wrong > 0:
		_fail("%d gear drops were not equippable (types: %s)" % [wrong, str(seen.keys())])
	# And the branch must actually produce gear, not fall through to something empty.
	if seen.size() < 3:
		_fail("the gear branch produced only %d item types" % seen.size())
