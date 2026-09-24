extends RefCounted
class_name EquipLogic
## EquipLogic — the rules for putting an item on, ported from `equipItem()`.
##
## Every branch here is a rule a player will notice if it is missing:
##
##   - a class that cannot use a weapon type gets the item handed back
##   - a two-handed weapon evicts the shield, and a shield evicts a two-handed weapon
##   - a class with no shield support cannot equip one at all
##   - equipping from the bag removes from the bag BEFORE pushing the old item in,
##     otherwise the old item can land in the slot the new one just vacated
##   - the item being equipped is never duplicated
##
## Pure logic on the state dictionary: no UI, so it can be tested headlessly.

const ItemGen := preload("res://scripts/items/item_gen.gd")


## Equip the item at `inventory_index`. Returns a result dictionary:
##   {ok: bool, reason: String}  — reason is a player-facing Czech-free message key.
static func equip_from_bag(state, inventory_index: int, resolve: Callable) -> Dictionary:
	var inventory: Array = state.inventory()
	if inventory_index < 0 or inventory_index >= inventory.size():
		return {"ok": false, "reason": "empty_slot"}

	var entry: Variant = inventory[inventory_index]
	var item_id: String = entry.get("id", "") if entry is Dictionary else str(entry)
	if item_id == "":
		return {"ok": false, "reason": "empty_slot"}

	var item: Dictionary = resolve.call(item_id)
	if item.is_empty():
		return {"ok": false, "reason": "unknown_item"}

	var equip: Dictionary = state.equip()
	var item_type: String = str(item.get("type", ""))

	# Already worn in a slot this item type can occupy — do nothing rather than
	# creating a second copy.
	if item_type == "weapon" and equip.get("weapon") == item_id:
		return {"ok": false, "reason": "already_equipped"}
	if item_type == "ring" and (equip.get("ring1") == item_id or equip.get("ring2") == item_id):
		return {"ok": false, "reason": "already_equipped"}
	for slot in ["armor", "helmet", "belt", "amulet", "gloves", "boots", "shield"]:
		if item_type == slot and equip.get(slot) == item_id:
			return {"ok": false, "reason": "already_equipped"}

	var cls: Dictionary = state.data_ref().class_by_id(str(state.data.get("heroClass", "")))

	# Class restrictions, checked BEFORE removing anything from the bag so a refused
	# equip leaves the inventory untouched.
	if item_type == "weapon":
		var allowed: Array = cls.get("allowedWeapons", [])
		if not allowed.is_empty() and not allowed.has(str(item.get("weaponType", ""))):
			return {"ok": false, "reason": "class_cannot_use"}
	if item_type == "shield" and cls.get("allowedShield", true) == false:
		return {"ok": false, "reason": "class_cannot_use_shield"}

	# Remove the new item from the bag FIRST (the PWA learned this the hard way).
	ItemGen.remove_from_inventory(inventory, item_id)

	match item_type:
		"weapon":
			# Two-handed evicts the shield; a one-hander leaves the offhand alone.
			if item.get("twoHand", false) == true and equip.get("shield") != null:
				ItemGen.add_to_inventory(inventory, str(equip["shield"]), resolve.call(equip["shield"]))
				equip["shield"] = null
			if equip.get("weapon") != "fists" and equip.get("weapon") != null:
				var old: String = str(equip["weapon"])
				ItemGen.add_to_inventory(inventory, old, resolve.call(old))
			equip["weapon"] = item_id
		"shield":
			# A shield cannot coexist with a two-handed weapon.
			var weapon: Dictionary = resolve.call(equip.get("weapon", "fists"))
			if weapon.get("twoHand", false) == true:
				var old_weapon: String = str(equip["weapon"])
				ItemGen.add_to_inventory(inventory, old_weapon, weapon)
				equip["weapon"] = "fists"
			if equip.get("shield") != null:
				var old_shield: String = str(equip["shield"])
				ItemGen.add_to_inventory(inventory, old_shield, resolve.call(old_shield))
			equip["shield"] = item_id
		"ring":
			# Fill ring1, then ring2, then replace ring1 — D2's behaviour.
			if equip.get("ring1") == null:
				equip["ring1"] = item_id
			elif equip.get("ring2") == null:
				equip["ring2"] = item_id
			else:
				var old_ring: String = str(equip["ring1"])
				ItemGen.add_to_inventory(inventory, old_ring, resolve.call(old_ring))
				equip["ring1"] = item_id
		_:
			# Single-slot types share their name with the slot.
			if equip.has(item_type):
				if equip.get(item_type) != null:
					var old_item: String = str(equip[item_type])
					ItemGen.add_to_inventory(inventory, old_item, resolve.call(old_item))
				equip[item_type] = item_id
			else:
				# Unknown type — put it back rather than losing it.
				ItemGen.add_to_inventory(inventory, item_id, item)
				return {"ok": false, "reason": "unknown_type"}

	# Belt changes the number of potion slots.
	if item_type == "belt":
		state.sync_potion_slots(resolve)

	return {"ok": true, "reason": ""}


## Which equipment slot an item TYPE naturally occupies. The PWA's `typeToSlot`, in one
## place so the overlay's own button routing and `equip_from_bag` cannot disagree.
## A ring maps to `ring1` — `equip_from_bag` still fills ring1 then ring2, which is the
## behaviour a plain "Equip" button wants; only the overlay's two named buttons override
## that.
static func slot_for_type(item_type: String) -> String:
	return str({
		"weapon": "weapon", "armor": "armor", "helmet": "helmet", "shield": "shield",
		"ring": "ring1", "belt": "belt", "amulet": "amulet", "gloves": "gloves",
		"boots": "boots",
	}.get(item_type, ""))


## Equip the item at `inventory_index` into a NAMED slot — the PWA's `equipItemToSlot`,
## which exists only for the cases where the natural slot is not enough:
##
##   * a RING, which can go into either hand  (`Equip Ring 1` / `Equip Ring 2`)
##   * an OFF-HAND weapon for a dual-wielding class
##
## Everything else must agree with the item's natural slot; a mismatch is a refusal with
## a reason, never a silent no-op, because a button that does nothing is the bug this
## function exists to avoid.
##
## `equip_from_bag` still owns the class restrictions, the bag-full case and the
## two-handed eviction; this only redirects the destination.
static func equip_from_bag_into(state, inventory_index: int, slot: String, resolve: Callable) -> Dictionary:
	var inventory: Array = state.inventory()
	if inventory_index < 0 or inventory_index >= inventory.size():
		return {"ok": false, "reason": "empty_slot"}
	var entry: Variant = inventory[inventory_index]
	var item_id: String = entry.get("id", "") if entry is Dictionary else str(entry)
	if item_id == "":
		return {"ok": false, "reason": "empty_slot"}
	var item: Dictionary = resolve.call(item_id)
	if item.is_empty():
		return {"ok": false, "reason": "unknown_item"}
	var item_type := str(item.get("type", ""))
	var natural := slot_for_type(item_type)

	# A ring into a named hand: D2's rule is that the slot is chosen, not searched, so
	# this path does NOT fall through to `equip_from_bag`'s "first empty ring slot".
	if item_type == "ring" and slot in ["ring1", "ring2"]:
		var equip: Dictionary = state.equip()
		ItemGen.remove_from_inventory(inventory, item_id)
		if equip.get(slot) != null:
			var old: String = str(equip[slot])
			ItemGen.add_to_inventory(inventory, old, resolve.call(old))
		equip[slot] = item_id
		return {"ok": true, "reason": ""}

	# An off-hand weapon: only a dual-wielding class may, and only a one-hander.
	if slot == "shield" and item_type == "weapon":
		if bool(item.get("twoHand", false)):
			return {"ok": false, "reason": "two_handed_offhand"}
		var cls: Dictionary = state.data_ref().class_by_id(str(state.data.get("heroClass", "")))
		if not bool(cls.get("dualWield", false)):
			return {"ok": false, "reason": "class_cannot_dual_wield"}
		var equip2: Dictionary = state.equip()
		ItemGen.remove_from_inventory(inventory, item_id)
		if equip2.get("shield") != null:
			var old_shield: String = str(equip2["shield"])
			ItemGen.add_to_inventory(inventory, old_shield, resolve.call(old_shield))
		equip2["shield"] = item_id
		return {"ok": true, "reason": ""}

	if slot != natural:
		return {"ok": false, "reason": "wrong_slot"}
	return equip_from_bag(state, inventory_index, resolve)


## Take an item off. `slot` is an equipment slot name. Returns the result shape
## as equip_from_bag.
static func unequip(state, slot: String, resolve: Callable) -> Dictionary:
	var equip: Dictionary = state.equip()
	if not equip.has(slot):
		return {"ok": false, "reason": "unknown_slot"}
	var item_id: Variant = equip[slot]
	if item_id == null or item_id == "" or item_id == "fists":
		return {"ok": false, "reason": "empty_slot"}

	var inventory: Array = state.inventory()
	if inventory.size() >= state.INVENTORY_CELLS:
		return {"ok": false, "reason": "bag_full"}

	ItemGen.add_to_inventory(inventory, str(item_id), resolve.call(item_id))
	equip[slot] = "fists" if slot == "weapon" else null
	if slot == "belt":
		state.sync_potion_slots(resolve)
	return {"ok": true, "reason": ""}
