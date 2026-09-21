extends RefCounted
class_name GameState
## GameState — the save model, ported from the PWA's `defaultState()` / `loadSave()`.
##
## The PWA kept this as one big untyped object patched by a dozen migration blocks,
## because saves had to survive four years of schema changes. A fresh port has no
## legacy saves, so the migrations are gone — what remains is the shape itself plus
## the rules that still matter (`_maxLocationProgress` never decreases).
##
## Nothing here touches the DOM or the scene tree; it is a data container plus the
## two functions that read/write it. `user://` is the save location.

const SAVE_PATH := "user://dungeon_recall_save.json"
const SAVE_VERSION := 1

const ItemGen := preload("res://scripts/items/item_gen.gd")

## Slot keys, matching the PWA. Kept in one place so the UI and the stat functions
## cannot drift apart.
const SLOTS := ["weapon", "armor", "helmet", "shield", "ring1", "ring2",
	"amulet", "belt", "gloves", "boots"]

## Default potion slots when no belt is worn (the PWA's DEFAULT_POTION_SLOTS).
const DEFAULT_POTION_SLOTS := 4

const CHEST_SLOTS := 25
const INVENTORY_CELLS := 20

var data: Dictionary = {}

## GameData, bound once at startup — see bind_data().
var _data_ref: Node


func _init() -> void:
	reset()


## Set by whoever owns both, so pure-logic helpers (EquipLogic) can reach the class
## tables without every caller having to thread GameData through by hand.
func data_ref() -> Node:
	return _data_ref


func bind_data(game_data: Node) -> void:
	_data_ref = game_data


## A fresh game. Mirrors the PWA's defaultState() minus the migration flags.
func reset() -> void:
	data = {
		"heroClass": "",
		"difficulty": 0,
		"talentLevels": {},
		"talentPoints": 0,
		"activeSchool": null,
		"hero": {
			"name": "Dobrodruh",
			"face": "hero",
			"level": 1,
			"xp": 0,
			"gold": 0,
			"hp": 100,
			"maxHp": 100,
			"mana": 50,
			"maxMana": 50,
			"baseDmg": 12,
			"inventory": [],
			"equip": _empty_equip(),
			"attrStr": 0, "attrVit": 0, "attrDex": 0, "attrInt": 0,
			"attrPoints": 0,
		},
		"deaths": 0,
		"wins": 0,
		"locationProgress": [0, 0, 0, 0, 0],
		# Highest stop ever reached per act. NEVER decreases — farming an earlier stop
		# lowers locationProgress, and unlocking must not follow it back down.
		"_maxLocationProgress": [0, 0, 0, 0, 0],
		"areaFightProgress": [0, 0, 0, 0, 0],
		# 2D from the start: [difficulty][actId]. The PWA needed a flat -> 2D
		# migration for this, which a new port simply does not have.
		"bossesDefeated": [
			[false, false, false, false, false],
			[false, false, false, false, false],
			[false, false, false, false, false],
		],
		"encounteredMonsters": [],
		"lootItems": {},
		"chest": [],
		"townPortalReturn": null,
		"townPortalCount": 0,
		"comboPoints": 0,
	}
	for _i in CHEST_SLOTS:
		data["chest"].append(null)


func _empty_equip() -> Dictionary:
	var equip := {"beltPotionSlots": []}
	for slot in SLOTS:
		equip[slot] = null
	equip["weapon"] = "fists"
	# The belt slot's potion slots must exist even with no belt, otherwise the first
	# potion the player picks up has nowhere to go.
	for _i in DEFAULT_POTION_SLOTS:
		equip["beltPotionSlots"].append(null)
	return equip


# --- convenience accessors ---------------------------------------------------

func hero() -> Dictionary:
	return data["hero"]


func equip() -> Dictionary:
	return data["hero"]["equip"]


func inventory() -> Array:
	return data["hero"]["inventory"]


func set_class(class_id: String) -> void:
	data["heroClass"] = class_id


## Number of potion slots available: 4 per belt row, or the default without a belt.
func total_potion_slots(find_item: Callable) -> int:
	var belt_id: Variant = equip().get("belt")
	if belt_id == null or belt_id == "":
		return DEFAULT_POTION_SLOTS
	var belt: Dictionary = find_item.call(belt_id)
	if belt.is_empty():
		return DEFAULT_POTION_SLOTS
	return int(belt.get("beltRows", 0)) * 4


## Keep `beltPotionSlots` the right length after a belt is equipped or removed.
## Without this a longer belt leaves the extra slots missing and the UI renders
## fewer buttons than the belt promises.
func sync_potion_slots(find_item: Callable) -> void:
	var want := total_potion_slots(find_item)
	var slots: Array = equip().get("beltPotionSlots", [])
	while slots.size() < want:
		slots.append(null)
	if slots.size() > want:
		slots.resize(want)
	equip()["beltPotionSlots"] = slots


## The highest stop reached in an act — what unlocking is decided from.
func max_progress(act_id: int) -> int:
	var arr: Array = data["_maxLocationProgress"]
	return int(arr[act_id]) if act_id >= 0 and act_id < arr.size() else 0


func set_progress(act_id: int, value: int) -> void:
	if act_id < 0 or act_id >= 5:
		return
	data["locationProgress"][act_id] = value
	data["_maxLocationProgress"][act_id] = maxi(max_progress(act_id), value)


func is_boss_defeated(act_id: int) -> bool:
	var diff: int = data.get("difficulty", 0)
	var rows: Array = data["bossesDefeated"]
	if diff < 0 or diff >= rows.size():
		return false
	return bool(rows[diff][act_id])


func set_boss_defeated(act_id: int) -> void:
	var diff: int = data.get("difficulty", 0)
	data["bossesDefeated"][diff][act_id] = true


## Which acts are enterable at the current difficulty: act 0 always, the rest only
## once the previous act's boss is down.
func act_unlocked(act_id: int) -> bool:
	if act_id == 0:
		return true
	return is_boss_defeated(act_id - 1)


# --- generated loot items ----------------------------------------------------

## Generated items live outside the static table, so they are stored on the save
## and registered on load. The PWA did this with a `lootItems` dict restored into
## ITEM_MAP; same idea, just explicit.
func register_loot_item(item: Dictionary) -> void:
	data["lootItems"][item["id"]] = item


func loot_item(item_id: String) -> Dictionary:
	return data["lootItems"].get(item_id, {})


# --- inventory / chest rules -------------------------------------------------

## add_item — pushes a plain id for gear, or merges into a stack for gems and
## consumables. Thin wrapper so screens never reach for the generator's statics.
func add_item(item_id: String, item: Dictionary, count: int = 1) -> void:
	ItemGen.add_to_inventory(inventory(), item_id, item, count)


func remove_item(item_id: String, count: int = 1) -> void:
	ItemGen.remove_from_inventory(inventory(), item_id, count)


func bag_full() -> bool:
	return inventory().size() >= INVENTORY_CELLS


## Is this item id in ANY equip slot? The PWA's isItemEquipped, which walks every
## key rather than a set — it stays correct even if an id is somehow in both the bag
## and a slot. `beltPotionSlots` holds potion ids, not the belt, so it is skipped.
func is_item_equipped(item_id: String) -> bool:
	if item_id == "":
		return false
	var eq := equip()
	for key in eq:
		if key == "beltPotionSlots":
			continue
		if str(eq[key]) == item_id:
			return true
	return false


## put a consumable into the belt. Column-major, exactly like the PWA: heal and mana
## potions must not share a column. Returns false when there is no room, and the
## caller then falls back to the bag.
##
## `find_item` resolves an id to its item, so this needs no GameData reference.
func add_potion_to_belt(potion_id: String, find_item: Callable) -> bool:
	var potion: Dictionary = find_item.call(potion_id)
	if potion.is_empty() or str(potion.get("type", "")) != "consumable":
		return false
	sync_potion_slots(find_item)
	var total := total_potion_slots(find_item)
	if total <= 0:
		return false
	var slots: Array = equip().get("beltPotionSlots", [])
	var subtype := str(potion.get("subtype", ""))
	var rows := int(ceil(float(total) / 4.0))
	for col in 4:
		# What is already in this column? A column that is already mixed, or holds the
		# other potion type, cannot take this potion — that is the D2 belt rule.
		var column_type := ""
		var mixed := false
		for row in rows:
			var idx := col * rows + row
			if idx >= total:
				continue
			var pid: Variant = slots[idx]
			if pid == null:
				continue
			var p: Dictionary = find_item.call(pid)
			if p.is_empty():
				continue
			var p_sub := str(p.get("subtype", ""))
			if column_type == "":
				column_type = p_sub
			elif column_type != p_sub:
				mixed = true
				break
		if mixed or (column_type != "" and column_type != subtype):
			continue
		for row in rows:
			var idx := col * rows + row
			if idx < total and slots[idx] == null:
				slots[idx] = potion_id
				equip()["beltPotionSlots"] = slots
				return true
	return false


## Take one copy of `potion_id` out of the belt. Returns the slot index used, or -1.
func consume_potion(potion_id: String) -> int:
	var slots: Array = equip().get("beltPotionSlots", [])
	for i in slots.size():
		if str(slots[i]) == potion_id:
			slots[i] = null
			equip()["beltPotionSlots"] = slots
			return i
	return -1


## Move one bag entry into the chest. Stackable items merge into an existing stack;
## gear takes the first free cell. Returns "" on success or the reason it failed.
func stash_from_bag(bag_index: int, item: Dictionary, is_stackable: bool) -> String:
	var inv := inventory()
	if bag_index < 0 or bag_index >= inv.size():
		return "bad index"
	var entry: Variant = inv[bag_index]
	var item_id: String = str(entry.get("id", "")) if entry is Dictionary else str(entry)
	var count: int = int(entry.get("count", 1)) if entry is Dictionary else 1
	if item_id == "":
		return "empty slot"

	var chest: Array = data["chest"]
	if is_stackable:
		for i in chest.size():
			var existing: Variant = chest[i]
			if existing is Dictionary and str(existing.get("id", "")) == item_id:
				existing["count"] = int(existing.get("count", 1)) + count
				inv.remove_at(bag_index)
				return ""
	for i in chest.size():
		if chest[i] == null:
			chest[i] = {"id": item_id, "count": count}
			inv.remove_at(bag_index)
			return ""
	return "chest is full"


## Move one chest cell into the bag. Returns "" on success or the reason.
func take_from_chest(chest_index: int, item: Dictionary) -> String:
	var chest: Array = data["chest"]
	if chest_index < 0 or chest_index >= chest.size():
		return "bad index"
	var entry: Variant = chest[chest_index]
	if entry == null:
		return "empty slot"
	var item_id: String = str(entry.get("id", "")) if entry is Dictionary else str(entry)
	var count: int = int(entry.get("count", 1)) if entry is Dictionary else 1
	if bag_full() and not ItemGen.is_stackable(item):
		return "bag is full"
	add_item(item_id, item, count)
	chest[chest_index] = null
	return ""


# --- persistence -------------------------------------------------------------

func save() -> Error:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("GameState: cannot write %s" % SAVE_PATH)
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return OK


## Load a save, or keep the fresh state if there is none / it is unreadable.
## Returns true when a save was actually loaded, so the caller can tell a new game
## from a resumed one.
func load_from_disk() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary) or not parsed.has("hero"):
		push_warning("GameState: save file is not usable, starting a new game")
		return false
	data = parsed
	_repair_after_load()
	return true


## Anything a save could be missing (a hand-edited file, an older build) is fixed
## here rather than crashing later at the point of use.
func _repair_after_load() -> void:
	if not data.has("lootItems"):
		data["lootItems"] = {}
	if not data.has("chest") or (data["chest"] as Array).size() != CHEST_SLOTS:
		data["chest"] = []
		for _i in CHEST_SLOTS:
			data["chest"].append(null)
	if not data.has("_maxLocationProgress"):
		var lp: Array = data.get("locationProgress", [0, 0, 0, 0, 0])
		data["_maxLocationProgress"] = lp.duplicate()
	var equip_data: Dictionary = data["hero"].get("equip", {})
	for slot in SLOTS:
		if not equip_data.has(slot):
			equip_data[slot] = "fists" if slot == "weapon" else null
	if not equip_data.has("beltPotionSlots"):
		equip_data["beltPotionSlots"] = []
	data["hero"]["equip"] = equip_data


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
