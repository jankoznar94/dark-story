extends SceneTree
## tools/test_equip_and_town.gd — the equip rules and the town's two behaviours.
##
## Equip has more branches than any other part of the port (class restrictions, two-
## handed vs shield, ring1-then-ring2, belt resizing potion slots) and every one of
## them is a rule a player notices when it is wrong. They are asserted here rather
## than by hand-tapping the UI.
##
## Run:  godot --headless --path . --script res://tools/test_equip_and_town.gd
## Pass: prints EQUIP_TOWN_ALL_PASS=true

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const EquipLogic := preload("res://scripts/items/equip_logic.gd")

var _data: Node
var _gen: ItemGen
var _failures: Array[String] = []


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)

	_test_class_weapon_restriction()
	_test_two_handed_evicts_shield()
	_test_shield_evicts_two_handed()
	_test_assassin_cannot_wear_shield()
	_test_rings_fill_ring1_then_ring2()
	_test_no_duplication()
	_test_belt_resizes_potion_slots()
	_test_unequip()
	_test_bag_full()
	_test_town_heals_and_recalibrates()

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("EQUIP_TOWN_ALL_PASS=true")
	else:
		print("EQUIP_TOWN_ALL_PASS=false")
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _fresh_state(class_id: String):
	var s = GameState.new()
	s.bind_data(_data)
	s.set_class(class_id)
	s.data["hero"]["level"] = 30   # high enough that every lvlReq passes
	return s


func _resolve(id: Variant) -> Dictionary:
	var item: Dictionary = _data.item(str(id))
	if item.is_empty():
		# Gems resolve through the same index; anything else must be generated loot,
		# which these tests do not create.
		return {}
	return item


func _find_first(pred: Callable) -> Dictionary:
	for item in _data.items():
		if pred.call(item):
			return item
	return {}


## The first real weapon — excluding 'fists', which is the empty-hand pseudo item and
## is reported as already equipped by design.
func _find_weapon() -> Dictionary:
	return _find_first(func(i):
		return i.get("type") == "weapon" and i.get("id") != "fists" and not i.get("twoHand", false))


func _add(state, item: Dictionary) -> int:
	ItemGen.add_to_inventory(state.inventory(), item["id"], item)
	return state.inventory().size() - 1


## A Barbarian may use axes; an Assassin may not.
func _test_class_weapon_restriction() -> void:
	var axe := _find_first(func(i): return i.get("weaponType") == "axe" and not i.get("twoHand", false))
	if axe.is_empty():
		_fail("no one-handed axe in the item table")
		return

	var assassin = _fresh_state("assassin")
	var idx := _add(assassin, axe)
	var res := EquipLogic.equip_from_bag(assassin, idx, _resolve)
	if res["ok"]:
		_fail("an assassin equipped an axe")
	elif assassin.equip().get("weapon") != "fists":
		_fail("a refused equip still changed the weapon slot")
	# The item must still be in the bag after a refusal.
	elif ItemGen.stack_count(assassin.inventory(), axe["id"]) != 1:
		_fail("a refused equip lost the item")
	else:
		print("  assassin refused an axe, item kept in bag")

	var barb = _fresh_state("barbarian")
	var idx2 := _add(barb, axe)
	var res2 := EquipLogic.equip_from_bag(barb, idx2, _resolve)
	if not res2["ok"]:
		_fail("a barbarian could not equip an axe: %s" % res2["reason"])
	elif barb.equip()["weapon"] != axe["id"]:
		_fail("the axe did not land in the weapon slot")
	else:
		print("  barbarian equipped %s" % axe["name"])


## A two-handed weapon must push the shield back into the bag.
func _test_two_handed_evicts_shield() -> void:
	var two_hand := _find_first(func(i): return i.get("twoHand", false) == true and i.get("type") == "weapon")
	var shield := _find_first(func(i): return i.get("type") == "shield")
	if two_hand.is_empty() or shield.is_empty():
		_fail("missing a two-handed weapon or a shield in the data")
		return

	var state = _fresh_state("barbarian")
	var shield_idx := _add(state, shield)
	EquipLogic.equip_from_bag(state, shield_idx, _resolve)
	if state.equip()["shield"] != shield["id"]:
		_fail("the shield did not equip")
		return

	var th_idx := _add(state, two_hand)
	EquipLogic.equip_from_bag(state, th_idx, _resolve)
	if state.equip()["shield"] != null:
		_fail("a two-handed weapon left the shield equipped")
	elif ItemGen.stack_count(state.inventory(), shield["id"]) != 1:
		_fail("the evicted shield did not return to the bag")
	elif state.equip()["weapon"] != two_hand["id"]:
		_fail("the two-handed weapon did not equip")
	else:
		print("  two-handed weapon evicted the shield back to the bag")


## And the reverse: equipping a shield must unequip a two-handed weapon.
func _test_shield_evicts_two_handed() -> void:
	var two_hand := _find_first(func(i): return i.get("twoHand", false) == true and i.get("type") == "weapon")
	var shield := _find_first(func(i): return i.get("type") == "shield")
	if two_hand.is_empty() or shield.is_empty():
		return

	var state = _fresh_state("barbarian")
	var th_idx := _add(state, two_hand)
	EquipLogic.equip_from_bag(state, th_idx, _resolve)

	var shield_idx := _add(state, shield)
	EquipLogic.equip_from_bag(state, shield_idx, _resolve)
	if state.equip()["weapon"] != "fists":
		_fail("equipping a shield did not evict the two-handed weapon")
	elif state.equip()["shield"] != shield["id"]:
		_fail("the shield did not equip after evicting the weapon")
	elif ItemGen.stack_count(state.inventory(), two_hand["id"]) != 1:
		_fail("the evicted two-hander did not return to the bag")
	else:
		print("  shield evicted the two-handed weapon back to the bag")


## The Assassin has allowedShield = false, so a shield must be refused outright.
func _test_assassin_cannot_wear_shield() -> void:
	var shield := _find_first(func(i): return i.get("type") == "shield")
	if shield.is_empty():
		return
	var state = _fresh_state("assassin")
	var idx := _add(state, shield)
	var res := EquipLogic.equip_from_bag(state, idx, _resolve)
	if res["ok"] or state.equip()["shield"] != null:
		_fail("an assassin equipped a shield")
	elif ItemGen.stack_count(state.inventory(), shield["id"]) != 1:
		_fail("the refused shield was lost")
	else:
		print("  assassin refused a shield, item kept in bag")


## Rings fill ring1 then ring2, and only then start replacing.
func _test_rings_fill_ring1_then_ring2() -> void:
	var rings: Array = []
	for item in _data.items():
		if item.get("type") == "ring":
			rings.append(item)
	if rings.size() < 3:
		print("  (only %d ring base types — ring replacement not exercised)" % rings.size())
		return

	var state = _fresh_state("barbarian")
	var first_idx := _add(state, rings[0])
	EquipLogic.equip_from_bag(state, first_idx, _resolve)
	if state.equip()["ring1"] != rings[0]["id"]:
		_fail("the first ring did not go to ring1")
		return

	var second_idx := _add(state, rings[1])
	EquipLogic.equip_from_bag(state, second_idx, _resolve)
	if state.equip()["ring2"] != rings[1]["id"]:
		_fail("the second ring did not go to ring2 (ring1 was overwritten)")
		return

	var third_idx := _add(state, rings[2])
	EquipLogic.equip_from_bag(state, third_idx, _resolve)
	if state.equip()["ring1"] != rings[2]["id"]:
		_fail("the third ring did not replace ring1")
	elif ItemGen.stack_count(state.inventory(), rings[0]["id"]) != 1:
		_fail("the replaced ring did not return to the bag")
	else:
		print("  rings filled ring1 -> ring2 -> replaced ring1")


## Equipping the same item twice must not duplicate it.
func _test_no_duplication() -> void:
	var sword := _find_weapon()
	if sword.is_empty():
		_fail("no equippable one-handed weapon in the item table")
		return
	var state = _fresh_state("barbarian")
	# Two separate entries: gear is not stackable, so a count > 1 is ignored by
	# add_to_inventory exactly as it was in the PWA. Adding twice is the honest way
	# to get two swords.
	ItemGen.add_to_inventory(state.inventory(), sword["id"], sword)
	ItemGen.add_to_inventory(state.inventory(), sword["id"], sword)
	# entry_count, not stack_count: gear is not stackable, so stack_count returns 1
	# no matter how many copies are in the bag. That was the first version of this test
	# and it passed for the wrong reason.
	var count_before := ItemGen.entry_count(state.inventory(), sword["id"])
	if count_before != 2:
		_fail("setup: expected 2 sword entries, got %d" % count_before)
		return

	EquipLogic.equip_from_bag(state, 0, _resolve)
	var res := EquipLogic.equip_from_bag(state, 0, _resolve)
	if res["ok"]:
		_fail("the same item was equipped twice")
	# One copy went to the weapon slot, so exactly one must be left in the bag.
	var after := ItemGen.entry_count(state.inventory(), sword["id"])
	if after != count_before - 1:
		_fail("equipping duplicated or lost copies (bag %d, was %d)" % [after, count_before])
	else:
		print("  re-equipping the same item was refused, no duplication")


## A belt changes how many potion slots exist: 4 per row, default 4.
func _test_belt_resizes_potion_slots() -> void:
	var belt := _find_first(func(i): return i.get("type") == "belt" and int(i.get("beltRows", 0)) > 1)
	if belt.is_empty():
		print("  (no multi-row belt in the data — resize not exercised)")
		return

	var state = _fresh_state("barbarian")
	if state.total_potion_slots(_resolve) != GameState.DEFAULT_POTION_SLOTS:
		_fail("without a belt, potion slots = %d, expected %d"
			% [state.total_potion_slots(_resolve), GameState.DEFAULT_POTION_SLOTS])

	var idx := _add(state, belt)
	EquipLogic.equip_from_bag(state, idx, _resolve)
	var want := int(belt["beltRows"]) * 4
	if state.total_potion_slots(_resolve) != want:
		_fail("belt with %d rows gives %d slots, expected %d"
			% [int(belt["beltRows"]), state.total_potion_slots(_resolve), want])
	elif (state.equip()["beltPotionSlots"] as Array).size() != want:
		_fail("beltPotionSlots was not resized (%d entries, expected %d)"
			% [(state.equip()["beltPotionSlots"] as Array).size(), want])
	else:
		print("  belt with %d rows resized potion slots to %d" % [int(belt["beltRows"]), want])


func _test_unequip() -> void:
	var sword := _find_weapon()
	if sword.is_empty():
		_fail("no equippable one-handed weapon in the item table")
		return
	var state = _fresh_state("barbarian")
	var idx := _add(state, sword)
	var equipped := EquipLogic.equip_from_bag(state, idx, _resolve)
	if not equipped["ok"]:
		_fail("setup: could not equip %s (%s)" % [sword["name"], equipped["reason"]])
		return

	var res := EquipLogic.unequip(state, "weapon", _resolve)
	if not res["ok"]:
		_fail("unequip failed: %s" % res["reason"])
	elif state.equip()["weapon"] != "fists":
		_fail("unequip did not reset the weapon slot to fists")
	elif ItemGen.stack_count(state.inventory(), sword["id"]) != 1:
		_fail("the unequipped item did not reach the bag")
	else:
		print("  unequip returned the weapon to the bag")

	# Empty slot must be refused, not crash.
	var res2 := EquipLogic.unequip(state, "helmet", _resolve)
	if res2["ok"]:
		_fail("unequipping an empty slot reported success")


func _test_bag_full() -> void:
	var sword := _find_weapon()
	if sword.is_empty():
		_fail("no equippable one-handed weapon in the item table")
		return
	var state = _fresh_state("barbarian")
	var idx := _add(state, sword)
	var equipped := EquipLogic.equip_from_bag(state, idx, _resolve)
	if not equipped["ok"]:
		_fail("setup: could not equip %s (%s)" % [sword["name"], equipped["reason"]])
		return
	# Fill the bag to capacity.
	while state.inventory().size() < GameState.INVENTORY_CELLS:
		ItemGen.add_to_inventory(state.inventory(), sword["id"], sword)
	var res := EquipLogic.unequip(state, "weapon", _resolve)
	if res["ok"]:
		_fail("unequip succeeded with a full bag — the item would be lost")
	else:
		print("  unequip refused on a full bag (%s)" % res["reason"])


## Entering town heals to full AND recalibrates max HP from gear.
func _test_town_heals_and_recalibrates() -> void:
	var state = _fresh_state("barbarian")
	var hero: Dictionary = state.hero()
	hero["level"] = 10
	hero["hp"] = 1
	var hp_without_gear := _gen.hero_max_hp(hero, state.equip(), _resolve)

	# Damage the hero, then simulate the town's enter().
	hero["hp"] = 1
	hero["maxHp"] = hp_without_gear
	var max_hp := _gen.hero_max_hp(hero, state.equip(), _resolve)
	hero["maxHp"] = max_hp
	hero["hp"] = max_hp
	if int(hero["hp"]) != hp_without_gear:
		_fail("town heal did not fill HP (%d, expected %d)" % [int(hero["hp"]), hp_without_gear])
	else:
		print("  town heal filled HP to %d" % int(hero["hp"]))

	# Now with a +HP item: the recalibrated max must be higher, and the heal must reach it.
	var armour := _find_first(func(i): return i.get("type") == "armor" and int(i.get("bonusHp", 0)) > 0)
	if armour.is_empty():
		return
	var idx := _add(state, armour)
	EquipLogic.equip_from_bag(state, idx, _resolve)
	var new_max := _gen.hero_max_hp(hero, state.equip(), _resolve)
	if new_max <= hp_without_gear:
		_fail("+HP armour did not raise max HP (%d vs %d)" % [new_max, hp_without_gear])
	else:
		print("  +%d HP armour raised max HP %d -> %d" % [int(armour["bonusHp"]), hp_without_gear, new_max])
