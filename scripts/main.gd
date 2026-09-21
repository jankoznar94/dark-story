extends Node2D
## Main — the game's entry point and the screen router.
##
## Owns the single instances of GameData / ItemGen / LootSystem / GameState, wires the
## screens together, and implements the one piece of logic that belongs to no screen:
## equipping, because it is triggered from the bag and must work while the inventory
## is open.
##
## The PWA had a `showScreen(name)` that toggled 213 DOM ids. Here a screen is a child
## node that is shown or hidden, and the router is the only thing that knows the list.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const EquipLogic := preload("res://scripts/items/equip_logic.gd")
const InventoryScreen := preload("res://scripts/ui/inventory_screen.gd")
const TownScreen := preload("res://scripts/ui/town_screen.gd")
const ArenaScreen := preload("res://scripts/ui/arena_screen.gd")

var data: Node
var gen: ItemGen
var loot: LootSystem
var state

var _screens: Dictionary = {}
var _current := ""


func _ready() -> void:
	data = GameData.new()
	add_child(data)

	gen = ItemGen.new(data)
	loot = LootSystem.new(data, gen)
	state = GameState.new()
	state.bind_data(data)

	# Resume if there is a save. A new game starts in town so there is somewhere to
	# stand while the arena does not exist yet.
	var resumed: bool = state.load_from_disk()
	_build_screens()
	# Town in both cases: it is the only fully ported screen, and it is where a new
	# game starts anyway. The `resumed` flag is kept because it is worth knowing in
	# the log whether a save was picked up.
	show_screen("town")
	print("Dungeon Recall — %s" % ("save loaded" if resumed else "new game"))


func _build_screens() -> void:
	var inventory := InventoryScreen.new(data, gen, state)
	inventory.set_anchors_preset(Control.PRESET_FULL_RECT)
	inventory.visible = false
	inventory.back_pressed.connect(func(): show_screen("town"))
	inventory.item_tapped.connect(_on_item_tapped)
	inventory.equip_slot_tapped.connect(_on_equip_slot_tapped)
	inventory.potion_slot_tapped.connect(_on_potion_slot_tapped)
	add_child(inventory)
	_screens["inventory"] = inventory

	var town := TownScreen.new(data, gen, state, _resolve)
	town.set_anchors_preset(Control.PRESET_FULL_RECT)
	town.visible = false
	town.tile_selected.connect(_on_town_tile)
	add_child(town)
	_screens["town"] = town

	var arena := ArenaScreen.new(data, gen, loot, state, _resolve)
	arena.set_anchors_preset(Control.PRESET_FULL_RECT)
	arena.visible = false
	arena.leave_requested.connect(func(): show_screen("town"))
	arena.another_fight_requested.connect(_on_another_fight)
	add_child(arena)
	_screens["arena"] = arena

	# The screens are Control nodes on a Node2D main; give them a CanvasLayer so they
	# sit above any future world rendering.
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	for key in _screens:
		var screen: Control = _screens[key]
		remove_child(screen)
		layer.add_child(screen)


func show_screen(name: String) -> void:
	if not _screens.has(name):
		push_error("Main: no screen named %s" % name)
		return
	for key in _screens:
		(_screens[key] as Control).visible = key == name
	_current = name
	match name:
		"town":
			# Entering town heals and refreshes the shop — the behaviour lives in the
			# screen's enter(), because re-entering must heal again.
			_screens["town"].enter(_reset_shop_cache)
		"inventory":
			_screens["inventory"].refresh()
		"arena":
			# Nothing to set up: _enter_arena already started the fight.
			pass


## The shop's stock is rebuilt on every town visit, so there is nothing to invalidate
## until the shop exists. The hook is here so the town call site is already correct.
func _reset_shop_cache() -> void:
	pass


func _on_town_tile(key: String) -> void:
	match key:
		"wilderness":
			_on_wilderness()
		"chest", "shop", "craft", "gamble":
			print("%s: not ported yet" % key.capitalize())
		"portal":
			_on_town_portal()
		_:
			show_screen(key)


## Wilderness: the arena. Entering it also resets the zone's fight counter, which is
## what the PWA did on act entry — a walk out of town always starts a fresh zone.
func _on_wilderness() -> void:
	var act_id := _first_uncompleted_act()
	if act_id < 0:
		return
	state.data["areaFightProgress"][act_id] = 0
	_enter_arena(act_id)


func _enter_arena(act_id: int) -> void:
	var arena = _screens["arena"]
	state.data["_currentAct"] = act_id
	show_screen("arena")
	if not arena.start(state, _resolve):
		print("Arena: no fight available for act %d" % act_id)


func _on_another_fight() -> void:
	var arena = _screens["arena"]
	if not arena.another_fight():
		show_screen("town")


## Town portal: only offered while a return position is stored. Returning rewinds to
## the stored act/zone/fight and consumes nothing — the scroll was spent on the way
## out, which is how the PWA did it.
func _on_town_portal() -> void:
	var portal: Variant = state.data.get("townPortalReturn")
	if portal == null:
		return
	var p: Dictionary = portal
	state.data["locationProgress"][int(p.get("actId", 0))] = int(p.get("zoneId", 0))
	state.data["areaFightProgress"][int(p.get("actId", 0))] = int(p.get("areaFight", 0))
	state.data["townPortalReturn"] = null
	state.save()
	_enter_arena(int(p.get("actId", 0)))


func _first_uncompleted_act() -> int:
	var acts: Array = data.acts()
	for i in acts.size():
		if not state.is_boss_defeated(i):
			return i
	return -1


func _on_item_tapped(inventory_index: int) -> void:
	var result := EquipLogic.equip_from_bag(state, inventory_index, _resolve)
	if result["ok"]:
		state.save()
		_screens["inventory"].refresh()
	else:
		print("Equip refused: %s" % result["reason"])


func _on_equip_slot_tapped(slot: String) -> void:
	var result := EquipLogic.unequip(state, slot, _resolve)
	if result["ok"]:
		state.save()
		_screens["inventory"].refresh()
	else:
		print("Unequip refused: %s" % result["reason"])


func _on_potion_slot_tapped(index: int) -> void:
	print("Potion slot %d: drinking is not ported yet" % index)


## Resolve any item id: a static base, a generated gem, or loot stored on the save.
func _resolve(id: Variant) -> Dictionary:
	var item_id := str(id)
	if item_id == "":
		return {}
	var static_item: Dictionary = data.item(item_id)
	if not static_item.is_empty():
		return static_item
	return state.loot_item(item_id)
