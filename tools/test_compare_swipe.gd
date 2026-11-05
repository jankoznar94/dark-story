extends SceneTree
## tools/test_compare_swipe.gd — the PWA's compare-window swipe: while the item detail is open, a
## horizontal swipe steps to the NEXT/PREVIOUS item in the bag instead of making the player
## close the window, tap the next cell and open it again.
##
## Jan, Nov 2026: "V pwa verzi batohu fungovalo to, že když jsi měl zobrazené compare okno a
## swipnul jsi doleva nebo doprava, tak to přepínalo mezi itemy v batohu."
##
## The gesture is asserted where it lives, not through a simulated finger: `ItemInfoOverlay`
## owns the press/release arithmetic and the INVENTORY owns the bag order, so the test drives
## `_on_panel_input` with the two touch events the PWA compares and then reads what the screen
## put in front of the player. Both halves are checked, because a swipe that emits the signal
## and a screen that shows the same item again looks exactly like a working feature in a log.
##
## Run:  godot --headless --path . --script res://tools/test_compare_swipe.gd
## Pass: prints COMPARE_SWIPE_ALL_PASS=true and exits 0.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const InventoryScreen := preload("res://scripts/ui/inventory_screen.gd")

## The PWA's own threshold and a swipe comfortably past it.
const SWIPE := 60.0
const TOO_SHORT := 20.0

const BAG_SIZE := 20

var _data: Node
var _gen: ItemGen
var _loot: LootSystem
var _state
var _screen: InventoryScreen
var _overlay
var _failures: Array[String] = []
var _frames := 0


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_loot = LootSystem.new(_data, _gen)
	_state = GameState.new()
	_state.bind_data(_data)
	_state.set_class("barbarian")


## The screen builds itself in `_ready`, so it needs real frames before it can be driven.
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	if _screen == null:
		_screen = InventoryScreen.new(_data, _gen, _state)
		root.add_child(_screen)
		return false
	if _overlay == null:
		_overlay = _screen._item_overlay
		# The overlay is normally handed to the dialog by `mount_overlay()`; adding it here is
		# what gives its panel a parent (and therefore a viewport for `accept_event()`).
		root.add_child(_overlay)
		return false
	_run()
	for f in _failures:
		print("  FAIL: %s" % f)
	print("COMPARE_SWIPE_ALL_PASS=%s" % ("true" if _failures.is_empty() else "false"))
	quit(0 if _failures.is_empty() else 1)
	return false


func _fail(msg: String) -> void:
	_failures.append(msg)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fail(msg)


## The bag the PWA's own modulo had to be corrected for: items at 0 and 5, empties between.
## `_bag_index_of` walks past the empties, so "next" is a real item, not a dead swipe.
func _fill_bag() -> Array:
	var ids := ["armor_leather", "helm_cap", "copperRing"]
	var bag: Array = []
	for i in BAG_SIZE:
		bag.append(null)
	var placed := 0
	for id in ids:
		var item: Dictionary = _data.item(str(id))
		if item.is_empty():
			continue
		var at := 0 if placed == 0 else (5 if placed == 1 else 9)
		bag[at] = {"id": str(id), "count": 1}
		placed += 1
	return bag


func _run() -> void:
	var bag := _fill_bag()
	var filled := 0
	for e in bag:
		if e != null:
			filled += 1
	if filled < 3:
		_fail("the test bag could not be filled from ITEMS.json (%d items)" % filled)
		return
	_state.data["hero"]["inventory"] = bag
	_screen.refresh()

	# --- the gesture itself ----------------------------------------------------
	# A press and a release 60 px to the LEFT is the NEXT item; the same move to the right is
	# the previous one. The overlay only says WHICH direction, never which item.
	_screen._on_bag_tapped(0)
	if not _overlay.visible:
		_fail("tapping a bag cell did not open the item detail — nothing to swipe")
		return
	_check(_overlay.origin() == "bag", "the detail must know it came from the bag")
	_check(_overlay.origin_index() == 0, "the detail opened on bag index 0")

	var first_id: String = str(_overlay.current_item_id())
	_check(first_id != "", "the detail shows no item at all")

	_swipe(-SWIPE, 0.0)
	_check(_overlay.current_item_id() != first_id,
		"a LEFT swipe did not change the item (still %s)" % first_id)
	_check(_overlay.origin_index() == 5,
		"a LEFT swipe must land on the NEXT filled cell (5), got %d" % _overlay.origin_index())

	# Right, back to 0 — and the previous item WRAPS from the first to the last filled cell.
	_swipe(SWIPE, 0.0)
	_check(_overlay.origin_index() == 0,
		"a RIGHT swipe must go back to 0, got %d" % _overlay.origin_index())
	_swipe(SWIPE, 0.0)
	_check(_overlay.origin_index() == 9,
		"a RIGHT swipe on the FIRST item must WRAP to the last filled cell (9), got %d"
			% _overlay.origin_index())
	_swipe(-SWIPE, 0.0)
	_check(_overlay.origin_index() == 0,
		"a LEFT swipe on the LAST item must wrap back to the first, got %d"
			% _overlay.origin_index())

	# --- the gesture must not fire on things that are not a swipe ---------------
	var before: int = int(_overlay.origin_index())
	_swipe(-TOO_SHORT, 0.0)
	_check(_overlay.origin_index() == before,
		"a %d px move is under the PWA's 40 px threshold and must not switch" % int(TOO_SHORT))
	_swipe(-SWIPE, -SWIPE * 2.0)
	_check(_overlay.origin_index() == before,
		"a mostly VERTICAL drag must scroll, not switch the item")
	# A phone delivers the emulated mouse press/release for the same finger. One finger is ONE
	# gesture: the pair must not switch twice (the ScrollSwipe lesson).
	_swipe_touch_then_mouse(-SWIPE)
	_check(_overlay.origin_index() == 5,
		"a finger + its emulated mouse events must count as ONE swipe, landed on %d"
			% _overlay.origin_index())

	# --- a worn item has no neighbour -----------------------------------------
	_screen._on_equip_slot_pressed("weapon")
	if _overlay.origin() == "equipped":
		var slot_index: int = int(_overlay.origin_index())
		_swipe(-SWIPE, 0.0)
		_check(_overlay.origin() == "equipped" and _overlay.origin_index() == slot_index,
			"a swipe on an EQUIPPED item must not walk the bag")
	else:
		# No weapon equipped in this save: the branch above is the real one, but a test that
		# silently skips it would pass on a build where the guard is missing.
		_fail("could not open an equipped item to prove the bag-only guard")

	# --- the panel is where the gesture is listened to -------------------------
	_check(_overlay._panel.gui_input.get_connections().size() > 0,
		"the panel has no gui_input handler — the swipe is not wired to anything")


## Move the finger 60 px and let go, through the same handler a real event reaches.
func _swipe(dx: float, dy: float) -> void:
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = Vector2(200, 400)
	_overlay._on_panel_input(press)
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.pressed = false
	release.position = Vector2(200 + dx, 400 + dy)
	_overlay._on_panel_input(release)


## A phone's finger arrives as a touch AND as an emulated mouse press/release. The gesture has
## to start on the first and ignore the pair, not switch twice.
func _swipe_touch_then_mouse(dx: float) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = Vector2(200, 400)
	_overlay._on_panel_input(touch)
	var mouse_down := InputEventMouseButton.new()
	mouse_down.button_index = MOUSE_BUTTON_LEFT
	mouse_down.pressed = true
	mouse_down.position = Vector2(200, 400)
	_overlay._on_panel_input(mouse_down)
	var touch_up := InputEventScreenTouch.new()
	touch_up.index = 0
	touch_up.pressed = false
	touch_up.position = Vector2(200 + dx, 400)
	_overlay._on_panel_input(touch_up)
	var mouse_up := InputEventMouseButton.new()
	mouse_up.button_index = MOUSE_BUTTON_LEFT
	mouse_up.pressed = false
	mouse_up.position = Vector2(200 + dx, 400)
	_overlay._on_panel_input(mouse_up)
