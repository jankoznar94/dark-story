extends SceneTree
## GATE: ONE FINGER TAP MUST BE ONE ACTION.
##
## Jan's report (Sept 2026): *"the items still cannot be equipped from the inventory
## into the equip slots. Either it says the item does not belong there, or it just
## returns to the inventory without a message."*
##
## Cause, measured with real injected input: Godot's `Input` synthesises an
## InputEventMouseButton from every InputEventScreenTouch and the GUI receives BOTH,
## so an unguarded `if pressed: act` ran the action TWICE and the second pass undid
## the first - a bag item was picked up and immediately dropped, a slot drag equipped
## and then unequipped. `scripts/tap_guard.gd` is the fix.
##
## WHY THIS FILE EXISTS SEPARATELY FROM test_corpse_fall_and_equip.gd: that gate calls
## `ui._tap()` DIRECTLY, which skips `Input` and with it the emulation, so it passes
## on a build where every real tap is doubled. This one injects through
## `Input.parse_input_event()` - the route a finger takes - and it needs a real
## window, so it is a MANUAL / desktop step and cannot be a headless CI step. Run it
## against any change to a panel's `_gui_input`.
##
##   DISPLAY=:0 godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##       --script res://tools/test_gesture_dedup.gd
## Prints GESTURE_DEDUP_ALL_PASS=true/false.

const IB := preload("res://scripts/item_base.gd")
const Inv := preload("res://scripts/inventory_model.gd")
const Item := preload("res://scripts/item.gd")

var main: Node
var ui: Control
var model
var loot_panel: Control
var fails: Array[String] = []
var checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	checks += 1
	if cond:
		print("  OK   ", label, ("  " + detail) if detail else "")
	else:
		print("  FAIL ", label, "  ", detail)
		fails.append(label)


func _touch(pressed: bool, at: Vector2, index: int = 0) -> void:
	var ev := InputEventScreenTouch.new()
	ev.pressed = pressed
	ev.index = index
	ev.position = at
	Input.parse_input_event(ev)


func _drag(at: Vector2, index: int = 0) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = at
	Input.parse_input_event(ev)


func _center_of(item) -> Vector2:
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
	ui = main.get_node("HUD/InventoryUI")
	loot_panel = main.get_node("HUD/LootPanel")
	model = Inv.new()
	ui.setup(model, load("res://scripts/hero_stats.gd").new(40))
	ui.set_open(true)
	ui.size = ui.get_viewport_rect().size
	ui.layout_now()

	# ---------------------------------------------------------------- tap, then tap
	print("== one finger tap = one action: tap the item, tap the box ==")
	var cap = Item.new("cap", IB.Rarity.NORMAL, 5)
	model.add(cap)
	ui.layout_now()
	_touch(true, _center_of(cap))
	await process_frame
	_touch(false, _center_of(cap))
	await process_frame
	_ok("ONE tap on a bag item LEAVES it carried", ui._held_item == cap,
		"carried=%s" % str(ui._held_item != null))
	_touch(true, _slot_center(0))
	await process_frame
	_touch(false, _slot_center(0))
	await process_frame
	_ok("ONE tap on the HELM box equips it there", model.equipped_at(0) == cap,
		str(model.equipped_at(0)))
	_ok("and the item is no longer in the bag", model.placement_index_of(cap) < 0)

	# ------------------------------------------------------------------ finger drag
	print("== one finger drag = one action ==")
	model.clear()
	var cap2 = Item.new("cap", IB.Rarity.NORMAL, 5)
	model.add(cap2)
	ui.layout_now()
	var from := _center_of(cap2)
	var to := _slot_center(0)
	_touch(true, from)
	await process_frame
	_drag(from + Vector2(20.0, 0.0))
	await process_frame
	_drag(to)
	await process_frame
	_touch(false, to)
	await process_frame
	_ok("a drag into the HELM box equips it and it STAYS equipped",
		model.equipped_at(0) == cap2, str(model.equipped_at(0)))

	# --------------------------------------------- a tap on an occupied box UNEQUIPS
	print("== a genuine second tap still works (the guard is not a dead panel) ==")
	var cap3 = model.equipped_at(0)
	_touch(true, _slot_center(0))
	await process_frame
	_touch(false, _slot_center(0))
	await process_frame
	_ok("a tap on a WORN box takes it off (one action, not two)",
		model.equipped_at(0) == null and model.placement_index_of(cap3) >= 0,
		"worn=%s" % str(model.equipped_at(0)))

	# -------------------------------------------------- the loot panel: one row tap
	print("== the loot panel takes ONE item per tap ==")
	model.clear()
	var body = main.loot.spawn_body(Vector3(1.5, 0, 0),
		[Item.new("ring", IB.Rarity.NORMAL, 5), Item.new("amulet", IB.Rarity.NORMAL, 5)],
		null, "ghoul")
	main.get_node("HUD").open_loot_for(body)
	await process_frame
	loot_panel._arm_ms = 0.0          # the opening-tap guard, not what is measured here
	var rows: Array = loot_panel._rows
	_ok("the body window opened with two rows", rows.size() == 2, "rows=%d" % rows.size())
	if rows.size() == 2:
		var r: Rect2 = rows[0]
		_touch(true, r.position + r.size * 0.5)
		await process_frame
		_touch(false, r.position + r.size * 0.5)
		await process_frame
		var taken: int = main.inventory.bag_items().size()
		_ok("ONE tap on a row takes exactly ONE item", taken == 1,
			"bag=%d, body still holds %d" % [taken, main.loot.items_in(body).size()])
		_ok("...and the other item stays in the body",
			main.loot.items_in(body).size() == 1,
			"left=%d" % main.loot.items_in(body).size())
	main.get_node("HUD").close_panels()
	ui.set_open(false)

	print("")
	print("checks executed: ", checks)
	print("GESTURE_DEDUP_ALL_PASS=%s" % ("true" if fails.is_empty() and checks >= 8 else "false"))
	for f in fails:
		print("FAIL: ", f)
	quit()
