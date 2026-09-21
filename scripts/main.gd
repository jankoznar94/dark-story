extends Node2D
## Main — the game's entry point and the screen router.
##
## Owns the single instances of GameData / ItemGen / LootSystem / GameState, wires the
## screens together, and implements the pieces of logic that belong to no screen:
## equipping (triggered from the bag, must work while the inventory is open) and the
## town's shop cache (cleared on every town visit).
##
## The PWA had a `showScreen(name)` that toggled 213 DOM ids and a `_currentScreen` it
## read back for the modal. Here a screen is a child node that is shown or hidden, the
## router is the only thing that knows the list, and the fixed bottom nav bar is built
## once and reused — the PWA rebuilt nothing on a screen change except the active class.
##
## The nav bar is the PWA's own idea of where a player can go: it listed town, hero,
## bestiary and the spellbook, and the two screens with no other door (inventory, hero)
## were modal behind it. The port keeps that: the nav is the only global navigation, and
## the town has exactly the tiles the PWA's town had.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const EquipLogic := preload("res://scripts/items/equip_logic.gd")
const InventoryScreen := preload("res://scripts/ui/inventory_screen.gd")
const TownScreen := preload("res://scripts/ui/town_screen.gd")
const MapScreen := preload("res://scripts/ui/map_screen.gd")
const ArenaScreen := preload("res://scripts/ui/arena_screen.gd")
const ChestScreen := preload("res://scripts/ui/chest_screen.gd")
const ShopScreen := preload("res://scripts/ui/shop_screen.gd")
const GambleScreen := preload("res://scripts/ui/gamble_screen.gd")
const CraftScreen := preload("res://scripts/ui/craft_screen.gd")
const CharacterModal := preload("res://scripts/ui/character_modal.gd")
const BestiaryScreen := preload("res://scripts/ui/bestiary_screen.gd")
const SpellbookScreen := preload("res://scripts/ui/spellbook_screen.gd")
const UIKit := preload("res://scripts/ui/ui_kit.gd")
const Socketing := preload("res://scripts/items/socketing.gd")

var data: Node
var gen: ItemGen
var loot: LootSystem
var state

var _screens: Dictionary = {}
var _current := ""
## The PWA's `musicToggle`. The port muted the Master bus rather than stopping the
## stream, so the toggle works whether or not anything is playing yet.
var _music_off := false
var _socket_rng_source: RandomNumberGenerator = null
## The last message a screen emitted, shown as a one-line status strip. The PWA used a
## toast; a plain label above the nav bar is enough and cannot cover the buttons.
var _status: Label
var _status_ticks := 0
var _nav_bar      # UIKit.NavBar


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
	_build_nav()
	show_screen("town")
	print("Dungeon Recall — %s" % ("save loaded" if resumed else "new game"))
	# The data report on boot is what makes a DEPLOYED build checkable from outside:
	# # CI going green says the pipeline ran, not that the published pack has content.
	# An empty or truncated convert boots perfectly and is otherwise invisible.
	var report: Dictionary = data.integrity_report()
	var parts := PackedStringArray()
	for key in report:
		parts.append("%s=%s" % [key, report[key]])
	print("Dungeon Recall — " + " ".join(parts))


func _build_screens() -> void:
	# `inventory`, `talents` and `hero` are ONE modal in the PWA — `showScreen()` routes
	# all three into `openModal()` and the dialog carries an Inventory/Skills/Stats tab
	# strip. They are not three screens here either: CharacterModal owns all three panes,
	# and the old separate `inventory` / `hero` screens produced a character sheet with no
	# stat sheet and a stat sheet with no tabs, which is why the port read as a different
	# game from the PWA.
	var modal := CharacterModal.new(data, gen, state, _resolve)
	modal.back_pressed.connect(_close_modal)
	modal.message.connect(_set_status)
	modal.item_tapped.connect(_on_item_tapped)
	modal.equip_slot_tapped.connect(_on_equip_slot_tapped)
	modal.potion_slot_tapped.connect(_on_potion_slot_tapped)
	modal.socket_armed.connect(_on_socket_armed)
	modal.gem_tapped.connect(_on_gem_tapped)
	_add_screen("character", modal)

	var town := TownScreen.new(data, gen, state, _resolve)
	town.visible = false
	town.tile_selected.connect(_on_town_tile)
	# The wilderness tile opens the MAP, as the PWA's `enterCurrentAct()` did — not a
	# fight. Which stop to fight is the player's choice on the map.
	town.stop_requested.connect(func(_act, _stop): show_screen("map"))
	_add_screen("town", town)

	var map_screen := MapScreen.new(data, state, _resolve)
	map_screen.visible = false
	map_screen.back_pressed.connect(func(): show_screen("town"))
	map_screen.difficulty_selected.connect(_on_difficulty_selected)
	map_screen.enter_stop.connect(_on_stop_selected)
	_add_screen("map", map_screen)

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

	var bestiary := BestiaryScreen.new(data, state)
	bestiary.visible = false
	bestiary.back_pressed.connect(func(): show_screen("town"))
	_add_screen("bestiary", bestiary)

	var spellbook := SpellbookScreen.new(data, state)
	spellbook.visible = false
	spellbook.back_pressed.connect(func(): show_screen("town"))
	_add_screen("spellbook", spellbook)

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


## The PWA's fixed bottom `.nav-bar`. Built once: it never changes except for which entry
## is highlighted, so rebuilding it per screen would only add a place for taps to be lost.
##
## It lives on its own CanvasLayer ABOVE the screens' layer. That is not decoration: the
## screens are re-parented into a `CanvasLayer` (layer 1) while the bar was a plain child
## of the Node2D main (layer 0), and a CanvasLayer always paints over layer 0 no matter
## what the node order says. The bar was correct, visible and completely hidden — the
## town showed an empty box where its chrome should have been.
func _build_nav() -> void:
	var nav_layer := CanvasLayer.new()
	nav_layer.name = "Nav"
	nav_layer.layer = 5
	add_child(nav_layer)

	_nav_bar = UIKit.NavBar.build("town")
	_nav_bar.nav_selected.connect(_on_nav_selected)
	nav_layer.add_child(_nav_bar)

	var status_layer := CanvasLayer.new()
	status_layer.name = "Status"
	status_layer.layer = 10
	add_child(status_layer)
	var box := VBoxContainer.new()
	# The status strip sits just ABOVE the 56px nav bar, so it never covers it.
	box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_top = -84
	box.offset_bottom = -56
	status_layer.add_child(box)
	_status = UIKit.label("", 14, UIKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(_status)


func _add_screen(key: String, screen: Control) -> void:
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	_screens[key] = screen
	# The nav bar is added BEFORE the screens (it is not one of them), so without this
	# the bar's first paint is UNDER the screens' own full-rect background ColorRect —
	# the bar's controls exist, report visible=true, and are never seen. The bar has to
	# be re-raised, not merely "not hidden".
	if _nav_bar != null:
		_nav_bar.move_to_front()


## The nav bar is hidden on the screens the PWA hid it on — the arena replaces the whole
## page (`.battle-active` locked scrolling) and a nav button under a live fight is a way
## to lose a fight by accident.
const NAV_HIDDEN := ["arena"]


func show_screen(name: String) -> void:
	if not _screens.has(name):
		push_error("Main: no screen named %s" % name)
		return
	for key in _screens:
		(_screens[key] as Control).visible = key == name
	_current = name
	if _nav_bar != null:
		_nav_bar.visible = not (name in NAV_HIDDEN)
		_nav_bar.set_active(name)
	match name:
		"town":
			# Entering town heals and refreshes the shop — the behaviour lives in the
			# screen's enter(), because re-entering must heal again.
			_screens["town"].enter(_reset_shop_cache)
		"map":
			_screens["map"].refresh()
		"chest":
			_screens["chest"].refresh()
		"shop":
			_screens["shop"].refresh()
		"gamble":
			_screens["gamble"].reset_stock()
			_screens["gamble"].refresh()
		"craft":
			pass
		"bestiary":
			_screens["bestiary"].refresh()
		"spellbook":
			_screens["spellbook"].refresh()
		"arena":
			# Nothing to set up: _enter_arena already started the fight.
			pass


## The nav bar's active entry is moved by the bar itself (`NavBar.set_active`), so the
## router only has to say which screen is up. The bar is built once and reused; the PWA
## did the same with a CSS class swap on the anchor.
## The PWA's tab keys are not the port's screen keys: `inventory`, `talents` and `hero`
## all open the SAME modal, on a different tab.
const MODAL_TABS := {
	"inventory": "inventory",
	"talents": "skills",
	"hero": "stats",
}


func _on_nav_selected(key: String) -> void:
	# Leaving the arena from the nav is a retreat: the fight must be ended rather than
	# left ticking behind another screen.
	if _current == "arena" and key != "arena":
		var arena = _screens["arena"]
		if arena.battle != null and not arena.battle.ended:
			arena.battle.ended = true

	if MODAL_TABS.has(key):
		open_modal(str(MODAL_TABS[key]))
		return

	# The three PWA nav entries that are toggles rather than screens. They exist in the bar
	# because the PWA's bar has them; a tap has to do something real or the entry is a lie.
	match key:
		"music":
			_toggle_music()
			return
		"testmode":
			_set_status("Testovaci rezim neni v portu preneseny.")
			return
		"clearsave":
			_clear_save()
			return
		"items":
			open_modal("inventory")
			return

	if not _screens.has(key):
		return
	show_screen(key)


## The PWA's `openModal()` — one dialog, three tabs, always entered on a named tab.
##
## Every other screen is hidden explicitly: the modal is a sibling in the same CanvasLayer,
## so leaving the town visible paints it OVER the dialog (screens are added in order and the
## town comes after the modal). A modal that is visible, correct and completely covered is
## exactly the failure the nav bar had — `show_screen()` does this hiding for the ordinary
## screens, and opening the modal is a second way in, so it has to do it too.
func open_modal(tab: String) -> void:
	if not _screens.has("character"):
		return
	for key in _screens:
		(_screens[key] as Control).visible = str(key) == "character"
	var modal = _screens["character"]
	_current = "character"
	if _nav_bar != null:
		# The PWA's modal is a full-screen dialog; its fixed nav bar sits UNDER the
		# overlay and is unreachable while it is open.
		_nav_bar.visible = false
	modal.set_tab(tab)


## The character modal, which now owns the inventory tab. The equip, potion and socket
## handlers used to reach `_screens["inventory"]`; that screen no longer exists, so they
## come through here instead.
func _modal():
	return _screens["character"]


func _close_modal() -> void:
	# The PWA closes the modal back onto whatever screen was showing; the town is the only
	# place the modal is reachable from, so that is where it returns.
	show_screen("town")


func _toggle_music() -> void:
	_music_off = not _music_off
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, _music_off)
	_set_status("Hudba vypnuta." if _music_off else "Hudba zapnuta.")


func _clear_save() -> void:
	state.reset()
	state.save()
	_set_status("Ulozena hra smazana.")
	show_screen("town")


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
	if key == "portal":
		_on_town_portal()
		return
	show_screen(key)


## A stop was tapped on the map: wind the act's progress to that stop and start fighting
## there. This is the PWA's `enterStop(actId, stop)` -> `startLocation(actId, stop, 0)`,
## including its fight counter reset — walking onto a stop always begins at 0/10.
func _on_stop_selected(act_id: int, stop: int) -> void:
	state.set_progress(act_id, stop)
	state.data["areaFightProgress"][act_id] = 0
	state.save()
	_enter_arena(act_id)


## The map's difficulty selector. Switching does NOT touch progress: each difficulty has
## its own boss row and its own act ladder, and the stop a player was standing on the
## previous difficulty stays where they left it.
func _on_difficulty_selected(difficulty: int) -> void:
	var result: Dictionary = state.set_difficulty(difficulty)
	if not result["ok"]:
		var diffs: Array = data.difficulties()
		var name := str((diffs[difficulty] as Dictionary).get("name", "")) \
			if difficulty >= 0 and difficulty < diffs.size() else ""
		_set_status("Obtiznost %s je jeste zamcena" % name)
		return
	state.save()
	# The map's header and cards both read the difficulty, so re-entering is what keeps
	# them consistent rather than patching each in turn.
	show_screen("map")
	_set_status("Obtiznost: %s" % str((data.difficulties()[difficulty] as Dictionary).get("name", "")))


func _enter_arena(act_id: int) -> void:
	var arena = _screens["arena"]
	state.data["_currentAct"] = act_id
	show_screen("arena")
	if not arena.start(state, _resolve):
		_set_status("Arena: zadny souboj pro akt %d" % act_id)
		show_screen("town")


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


func _on_item_tapped(inventory_index: int) -> void:
	var result := EquipLogic.equip_from_bag(state, inventory_index, _resolve)
	if result["ok"]:
		state.save()
		_modal().inventory().refresh()
	else:
		_set_status("Nasazeni odmitnuto: %s" % str(result["reason"]))


func _on_equip_slot_tapped(slot: String) -> void:
	var result := EquipLogic.unequip(state, slot, _resolve)
	if result["ok"]:
		state.save()
		_modal().inventory().refresh()
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
		_modal().inventory().refresh()
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
			_modal().inventory().refresh()
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
	var inventory = _modal().inventory()
	inventory._armed_socket = socket_index
	_set_status("Socket %d pripraven - klepni na gem" % socket_index)


## A gem was tapped: fill the armed socket with it. With no socket armed the gem is
## simply selected as the host's socket 0, so a single-socket item is one tap shorter.
func _on_gem_tapped(host_id: String, gem_id: String) -> void:
	var inventory = _modal().inventory()
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
