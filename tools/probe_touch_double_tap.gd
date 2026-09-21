extends SceneTree
## DIAGNOSTIC: is a single TOUCH tap processed TWICE by the panels?
##
## WHY THIS EXISTS. Jan's report (Sept 2026): *"the items still cannot be equipped
## from the inventory into the equip slots. Either it says the item does not belong
## there, or it just returns to the inventory without a message."*
##
## Every existing instrument in tools/ passes its events straight to the Control:
## `ui._tap(p)` in the headless gate, `get_viewport().push_input(ev, true)` in
## probe_equip_drag.gd. Both work, and both SKIP the one code path a real finger
## goes through - `Input.parse_input_event()`. That matters because Godot's
## `input_devices/pointing/emulate_mouse_from_touch` (a project setting, ON by
## default) makes the Input singleton SYNTHESISE an InputEventMouseButton for every
## InputEventScreenTouch, and BOTH are then delivered to `Control::_gui_input`.
## A panel that writes `if pressed: do_the_thing` therefore does the thing twice:
##   * a drag that equips, then the synthetic release taps the same slot again and
##     UNEQUIPS it  ->  "it just returns to the inventory, no message";
##   * tap-item, tap-slot: the slot tap equips and the duplicate undoes it;
##   * on a tap on a BAG ITEM the duplicate is read as "tapping the carried item
##     again" and drops the selection, so the following slot tap does nothing.
## Nothing in the repository could see it because nothing went through Input.
##
## This probe injects through `Input.parse_input_event()` and reports the model
## state after each step, so the duplicate shows up as a REVERTED action.
##
## Run (needs a real window: --headless routes no GUI input at all):
##   DISPLAY=:0 godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##       --script res://tools/probe_touch_double_tap.gd
## Prints TOUCH_DOUBLE_TAP=<n> - the number of times one tap reached the panel.

const IB := preload("res://scripts/item_base.gd")
const Inv := preload("res://scripts/inventory_model.gd")
const Item := preload("res://scripts/item.gd")

var main: Node
var ui: Control
var model
var _taps := 0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


## The injection a real finger goes through. `Input.parse_input_event` runs the
## emulation rules; `Viewport.push_input` (what the older probes use) does not.
func _send_touch(pressed: bool, at: Vector2, index: int = 0) -> void:
	var ev := InputEventScreenTouch.new()
	ev.pressed = pressed
	ev.index = index
	ev.position = at
	Input.parse_input_event(ev)


func _send_drag(at: Vector2, index: int = 0) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = at
	Input.parse_input_event(ev)


func _setup() -> void:
	model = Inv.new()
	var st = load("res://scripts/hero_stats.gd").new(40)
	ui = main.get_node("HUD/InventoryUI")
	ui.setup(model, st)
	ui.set_open(true)
	ui.size = ui.get_viewport_rect().size
	ui.layout_now()
	# count every tap the window actually handles, whatever the source
	ui.notify.connect(func(t: String) -> void:
		if t != "":
			_taps += 1
			print("     [toast] ", t))


func _cell_center(item) -> Vector2:
	var i: int = model.placement_index_of(item)
	var p: Dictionary = model.placements[i]
	var r: Rect2 = ui.cell_rect(p["pos"], p["size"])
	return r.position + r.size * 0.5


func _slot_center(slot: int) -> Vector2:
	var r: Rect2 = ui._slot_rect(slot)
	return r.position + r.size * 0.5


func _run() -> void:
	await process_frame
	await process_frame
	_setup()

	print("== 1. TAP the item, then TAP the helm box (the phone path) ==")
	var cap = Item.new("cap", IB.Rarity.NORMAL, 5)
	model.add(cap)
	ui.layout_now()
	var ic := _cell_center(cap)
	_send_touch(true, ic)
	await process_frame
	_send_touch(false, ic)
	await process_frame
	print("   after ONE tap on the item: carried=%s  (must be true)"
		% str(ui._held_item == cap))
	var carried_after_tap_item: bool = ui._held_item == cap
	_send_touch(true, _slot_center(0))
	await process_frame
	_send_touch(false, _slot_center(0))
	await process_frame
	var on_helm = model.equipped_at(0) == cap
	print("   after ONE tap on the HELM box: equipped=%s  (must be true)" % str(on_helm))
	print("   -> TAP-THEN-TAP: %s" % ("WORKS" if (carried_after_tap_item and on_helm)
		else "BROKEN (the tap was undone by a duplicate event)"))

	print("")
	print("== 2. DRAG the item onto the helm box (the desktop/finger-drag path) ==")
	model.clear()
	var cap2 = Item.new("cap", IB.Rarity.NORMAL, 5)
	model.add(cap2)
	ui.layout_now()
	var ic2 := _cell_center(cap2)
	var to := _slot_center(0)
	_send_touch(true, ic2)
	await process_frame
	_send_drag(ic2 + Vector2(20.0, 0.0))
	await process_frame
	_send_drag(to)
	await process_frame
	_send_touch(false, to)
	await process_frame
	var drag_on = model.equipped_at(0) == cap2
	print("   after ONE drag into the HELM box: equipped=%s  (must be true)" % str(drag_on))
	print("   -> DRAG: %s" % ("WORKS" if drag_on
		else "BROKEN (equipped and then immediately unequipped)"))

	print("")
	print("== 3. the same two taps, one per frame, to count the deliveries ==")
	model.clear()
	var cap3 = Item.new("cap", IB.Rarity.NORMAL, 5)
	model.add(cap3)
	ui.layout_now()
	var ic3 := _cell_center(cap3)
	_taps = 0
	_send_touch(true, ic3)
	await process_frame
	_send_touch(false, ic3)
	await process_frame
	await process_frame
	print("   taps handled for ONE finger tap on a bag item: %d  (must be 1)" % _taps)
	print("   carried after that tap: %s  (must be true)" % str(ui._held_item == cap3))
	var deliveries := _taps

	var verdict: bool = bool(carried_after_tap_item and on_helm and drag_on and deliveries == 1)
	print("")
	print("TOUCH_DOUBLE_TAP_DELIVERIES=%d" % deliveries)
	print("TOUCH_INPUT_ALL_PASS=%s" % ("true" if verdict else "false"))
	quit()


func _init() -> void:
	call_deferred("_run")
