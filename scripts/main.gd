extends Node2D
## Main — the game's entry point and the screen router.
##
## Owns the single instances of GameData / ItemGen / LootSystem / GameState, wires the
## screens together, and implements the pieces of logic that belong to no screen:
## equipping (triggered from the bag, must work while the inventory is open) and the
## town's shop cache (cleared on every town visit).
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
const ChestScreen := preload("res://scripts/ui/chest_screen.gd")
const ShopScreen := preload("res://scripts/ui/shop_screen.gd")
const GambleScreen := preload("res://scripts/ui/gamble_screen.gd")
const CraftScreen := preload("res://scripts/ui/craft_screen.gd")
const HeroScreen := preload("res://scripts/ui/hero_screen.gd")
const UIKit := preload("res://scripts/ui/ui_kit.gd")
const Socketing := preload("res://scripts/items/socketing.gd")

var data: Node
var gen: ItemGen
var loot: LootSystem
var state

var _screens: Dictionary = {}
var _current := ""
var _socket_rng_source: RandomNumberGenerator = null
## The last message a screen emitted, shown as a one-line status strip. The PWA used a
## toast; a plain label at the bottom is enough and cannot cover the buttons.
var _status: Label
var _status_ticks := 0


func _ready() -> void:
	data = GameData.new()
	add_child(data)

	gen = ItemGen.new(data)
	loot = LootSystem.new(data, gen)
	state = GameState.new()
	state.bind_data(data)

	# Resume if there is a save. A new game needs a class before anything else works —
	# the skill trees, the weapon restrictions and the mana pool all read it — so a
	# fresh save is seeded with the first class rather than left empty.
	var resumed: bool = state.load_from_disk()
	if not resumed or str(state.data.get("heroClass", "")) == "":
		var classes: Dictionary = data.classes()
		var first: String = str((classes.keys() as Array)[0]) if not classes.is_empty() else "barbarian"
		state.set_class(first)
		state.save()
	_build_screens()
	show_screen("town")
	print("Dungeon Recall — %s" % ("save loaded" if resumed else "new game"))
	# The data report on boot is what makes a DEPLOYED build checkable from outside:
	# CI going green says the pipeline ran, not that the published pack has content.
	# An empty or truncated convert boots perfectly and is otherwise invisible.
	var report: Dictionary = data.integrity_report()
	var parts := PackedStringArray()
	for key in report:
		parts.append("%s=%s" % [key, report[key]])
	print("Dungeon Recall — " + " ".join(parts))


func _build_screens() -> void:
	var inventory := InventoryScreen.new(data, gen, state)
	inventory.visible = false
	inventory.back_pressed.connect(func(): show_screen("town"))
	inventory.item_tapped.connect(_on_item_tapped)
	inventory.equip_slot_tapped.connect(_on_equip_slot_tapped)
	inventory.potion_slot_tapped.connect(_on_potion_slot_tapped)
	inventory.socket_armed.connect(_on_socket_armed)
	inventory.gem_tapped.connect(_on_gem_tapped)
	_add_screen("inventory", inventory)

	var town := TownScreen.new(data, gen, state, _resolve)
	town.visible = false
	town.tile_selected.connect(_on_town_tile)
	_add_screen("town", town)

	var chest := ChestScreen.new(data, gen, state, _resolve)
	chest.visible = false
	chest.back_pressed.connect(func(): show_screen("town"))
	chest.message.connect(_set_status)
	_add_screen("chest", chest)

	var shop := ShopScreen.new(data, gen, state, _resolve)
	shop.visible = false
	shop.back_pressed.connect(func(): show_screen("town"))
	shop.message.connect(_set_status)
	_add_screen("shop", shop)

	var gamble := GambleScreen.new(data, gen, state, _resolve)
	gamble.visible = false
	gamble.back_pressed.connect(func(): show_screen("town"))
	gamble.message.connect(_set_status)
	_add_screen("gamble", gamble)

	var craft := CraftScreen.new(data, gen, state, _resolve)
	craft.visible = false
	craft.back_pressed.connect(func(): show_screen("town"))
	craft.message.connect(_set_status)
	_add_screen("craft", craft)

	var hero_screen := HeroScreen.new(data, gen, state, _resolve)
	hero_screen.visible = false
	hero_screen.back_pressed.connect(func(): show_screen("town"))
	hero_screen.message.connect(_set_status)
	_add_screen("hero", hero_screen)

	var arena := ArenaScreen.new(data, gen, loot, state, _resolve)
	arena.visible = false
	arena.leave_requested.connect(func(): show_screen("town"))
	arena.another_fight_requested.connect(_on_another_fight)
	_add_screen("arena", arena)

	# The screens are Control nodes on a Node2D main; give them a CanvasLayer so they
	# sit above any future world rendering, and keep the status strip on top of them.
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	for key in _screens:
		var screen: Control = _screens[key]
		remove_child(screen)
		layer.add_child(screen)

	var status_layer := CanvasLayer.new()
	status_layer.name = "Status"
	status_layer.layer = 10
	add_child(status_layer)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	status_layer.add_child(box)
	_status = UIKit.label("", 14, UIKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_status)


func _add_screen(key: String, screen: Control) -> void:
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	_screens[key] = screen


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
		"chest":
			_screens["chest"].refresh()
		"shop":
			_screens["shop"].refresh()
		"gamble":
			_screens["gamble"].reset_stock()
			_screens["gamble"].refresh()
		"craft":
			pass
		"hero":
			_screens["hero"].refresh()
		"arena":
			# Nothing to set up: _enter_arena already started the fight.
			pass


## The shop's stock is rebuilt on every town visit. The stock itself lives in the shop
## screen's cache; this is the call site that clears it, which is why it lives here —
## the PWA reset its cache in renderTown, and re-entering town must produce a new offer.
func _reset_shop_cache() -> void:
	if _screens.has("shop"):
		_screens["shop"].reset_stock()


func _set_status(text: String) -> void:
	if _status == null:
		return
	_status.text = text
	_status_ticks = 30


func _process(_delta: float) -> void:
	if _status_ticks > 0:
		_status_ticks -= 1
		if _status_ticks == 0:
			_status.text = ""


func _on_town_tile(key: String) -> void:
	match key:
		"wilderness":
			_on_wilderness()
		"portal":
			_on_town_portal()
		_:
			show_screen(key)


## Wilderness: the arena. Entering it also resets the zone's fight counter, which is
## what the PWA did on act entry — a walk out of town always starts a fresh zone.
func _on_wilderness() -> void:
	var act_id := _first_uncompleted_act()
	if act_id < 0:
		_set_status("Vsechny akty dokonceny")
		return
	state.data["areaFightProgress"][act_id] = 0
	_enter_arena(act_id)


func _enter_arena(act_id: int) -> void:
	var arena = _screens["arena"]
	state.data["_currentAct"] = act_id
	show_screen("arena")
	if not arena.start(state, _resolve):
		_set_status("Arena: zadny souboj pro akt %d" % act_id)


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
		_set_status("Nasazeni odmitnuto: %s" % str(result["reason"]))


func _on_equip_slot_tapped(slot: String) -> void:
	var result := EquipLogic.unequip(state, slot, _resolve)
	if result["ok"]:
		state.save()
		_screens["inventory"].refresh()
	else:
		_set_status("Sundani odmitnuto: %s" % str(result["reason"]))


## A potion slot in the inventory: tapping it moves the potion from the bag into the
## belt, or takes it back out. Drinking happens in the arena, where the HP it restores
## has somewhere to land.
func _on_potion_slot_tapped(index: int) -> void:
	var slots: Array = state.equip().get("beltPotionSlots", [])
	if index < 0 or index >= slots.size():
		return
	if slots[index] != null:
		var potion_id := str(slots[index])
		slots[index] = null
		state.equip()["beltPotionSlots"] = slots
		var item: Dictionary = _resolve(potion_id)
		state.add_item(potion_id, item)
		state.save()
		_screens["inventory"].refresh()
		_set_status("Potion zpet do batohu")
		return
	# Empty slot: fill it from the first potion in the bag, through the belt rule so a
	# heal potion never lands in a mana column.
	for entry in state.inventory():
		var item_id := str(entry.get("id", "")) if entry is Dictionary else str(entry)
		var item: Dictionary = _resolve(item_id)
		if str(item.get("type", "")) != "consumable":
			continue
		if str(item.get("subtype", "")) not in ["heal", "mana"]:
			continue
		if state.add_potion_to_belt(item_id, _resolve):
			state.remove_item(item_id)
			state.save()
			_screens["inventory"].refresh()
			_set_status("Potion do opasku")
		return
	_set_status("Zadny potion v batohu")


## A socket cell was tapped. Only an EMPTY one can be armed — an occupied socket is a
## refusal, not an overwrite, and the message says so rather than silently doing nothing.
func _on_socket_armed(host_id: String, socket_index: int) -> void:
	var host: Dictionary = _resolve(host_id)
	if host.is_empty():
		return
	var reason := Socketing.can_socket(host, {"type": "gem"}, socket_index)
	if reason != "":
		_set_status(reason)
		return
	var inventory = _screens["inventory"]
	inventory._armed_socket = socket_index
	_set_status("Socket %d pripraven - klepni na gem" % socket_index)


## A gem was tapped: fill the armed socket with it. With no socket armed the gem is
## simply selected as the host's socket 0, so a single-socket item is one tap shorter.
func _on_gem_tapped(host_id: String, gem_id: String) -> void:
	var inventory = _screens["inventory"]
	var host: Dictionary = _resolve(host_id)
	var gem: Dictionary = _resolve(gem_id)
	if host.is_empty() or gem.is_empty():
		_set_status("Predmet nebo gem se nenasel")
		return
	var socket_index: int = int(inventory._armed_socket)
	if socket_index < 0:
		# No socket armed: use the first empty one, or say why there is none.
		var filled: Array = host.get("socketedGems", [])
		for i in int(host.get("sockets", 0)):
			if i >= filled.size() or filled[i] == null:
				socket_index = i
				break
		if socket_index < 0:
			_set_status("Vsechny sockety jsou plne")
			return

	var result: Dictionary = Socketing.socket(state, host, gem_id, gem, socket_index, data, _socket_rng())
	if not result["ok"]:
		_set_status(str(result["message"]))
		return
	# A socketed item is a MUTATED item, so it has to be re-registered: the resolver
	# hands out the live loot entry, but a static base must be stored or the stats are
	# lost on the next resolve.
	if not state.loot_item(host_id).is_empty():
		state.register_loot_item(host)
	state.save()
	inventory._armed_socket = -1
	inventory.refresh()
	_set_status(str(result["message"]))


func _socket_rng() -> RandomNumberGenerator:
	if _socket_rng_source == null:
		_socket_rng_source = RandomNumberGenerator.new()
		_socket_rng_source.randomize()
	return _socket_rng_source


## Resolve any item id: a static base, a generated gem, or loot stored on the save.
func _resolve(id: Variant) -> Dictionary:
	var item_id := str(id)
	if item_id == "":
		return {}
	var static_item: Dictionary = data.item(item_id)
	if not static_item.is_empty():
		return static_item
	return state.loot_item(item_id)
