extends SceneTree
## DIAGNOSTIC (read-only): WHY does an item from the bag not land in an equip slot?
## It drives the REAL window with REAL input events (a windowed run, not headless),
## because the model-level rules already say yes and the defect must therefore live
## in the UI path. Three paths are tried, each reported separately:
##   A. touch: press on the item, drag past the slop, release over the slot;
##   B. mouse: the same with a held left button;
##   C. tap-then-tap: tap the item, then tap the slot (a phone cannot double click).
## Every case is compared against the model: `slot_at()` maps the point to a slot
## index, `_hover_ok` says whether the window thinks it is legal, and the item's
## final home is read back from inventory_model.
##
## Run: DISPLAY=:0 godot --path . --rendering-driver opengl3 --resolution 960x540 \
##        --script res://tools/probe_equip_drag.gd

const IB := preload("res://scripts/item_base.gd")
const Item := preload("res://scripts/item.gd")

var main: Node
var ui: Control
var _step := 0
var _t := 0.0
var _item
var _item_rect: Rect2
var _slot_rect: Rect2
var _mid: Vector2


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	print(("  OK   " if cond else "  FAIL "), label, ("  " + detail) if detail else "")


func _setup_case(id: String) -> void:
	main.inventory.clear()
	_item = Item.new(id, IB.Rarity.NORMAL, 5)
	main.inventory.add(_item)
	var p: Dictionary = main.inventory.placements[0]
	ui = main.get_node("HUD").inventory_ui
	ui.set_open(true)
	ui.layout_now()
	_item_rect = ui.cell_rect(p["pos"], p["size"])
	_slot_rect = ui._slot_rect(0)                 # slot 0 is the HELM
	_mid = _item_rect.position + _item_rect.size * 0.5
	var from := _mid
	var to := _slot_rect.position + _slot_rect.size * 0.5
	print("-- case %s  item rect %s  slot0 rect %s  size %s"
		% [id, str(_item_rect), str(_slot_rect), str(ui.size)])
	print("   slot_at(item centre)=%d  slot_at(slot0 centre)=%d"
		% [ui.slot_at(from), ui.slot_at(to)])


func _touch(ev: InputEvent) -> void:
	# push_input() routes through the GUI hit test (the documented injection
	# route). `Input.parse_input_event()` did NOT reach the Control at all in this
	# run - hover stayed -1 and `moved` stayed false, i.e. every one of the three
	# paths "failed" for the same reason, which is the injection and not the game.
	ui.get_viewport().push_input(ev, true)


func _touch_send(pressed: bool, at: Vector2, index: int = 1) -> void:
	var ev := InputEventScreenTouch.new()
	ev.pressed = pressed
	ev.index = index
	ev.position = at
	_touch(ev)


func _drag_send(at: Vector2, index: int = 1) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = at
	_touch(ev)


func _mouse_send(pressed: bool, at: Vector2) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.position = at
	_touch(mb)


func _motion_send(at: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.relative = Vector2.ONE
	_touch(mm)


func _process(delta: float) -> bool:
	_t += delta
	match _step:
		0:
			if _t < 1.2:
				return false
			_setup_case("cap")
			_step = 1
			_t = 0.0
		1:
			if _t < 0.25:
				return false
			print("== A. TOUCH: press, drag, release over the slot ==")
			var to := _slot_rect.position + _slot_rect.size * 0.5
			_touch_send(true, _mid)
			_drag_send(_mid + Vector2(20, 0))
			_drag_send(to)
			_touch_send(false, to)
			print("   hover_slot=%d hover_ok=%s moved=%s" % [ui._hover_slot, str(ui._hover_ok), str(ui._moved)])
			_ok("A: the helmet is on slot 0 after a touch drag",
				main.inventory.equipped_at(0) == _item,
				"equipped_at(0)=%s" % str(main.inventory.equipped_at(0)))
			_step = 2
			_t = 0.0
		2:
			if _t < 0.3:
				return false
			_setup_case("cap")
			_step = 3
			_t = 0.0
		3:
			if _t < 0.25:
				return false
			print("== B. MOUSE: press, move, release over the slot ==")
			var to := _slot_rect.position + _slot_rect.size * 0.5
			_mouse_send(true, _mid)
			_motion_send(_mid + Vector2(20, 0))
			_motion_send(to)
			_mouse_send(false, to)
			print("   hover_slot=%d hover_ok=%s moved=%s" % [ui._hover_slot, str(ui._hover_ok), str(ui._moved)])
			_ok("B: the helmet is on slot 0 after a mouse drag",
				main.inventory.equipped_at(0) == _item,
				"equipped_at(0)=%s" % str(main.inventory.equipped_at(0)))
			_step = 4
			_t = 0.0
		4:
			if _t < 0.3:
				return false
			_setup_case("cap")
			_step = 5
			_t = 0.0
		5:
			if _t < 0.25:
				return false
			print("== C. TAP the item, then TAP the slot (the phone path) ==")
			var to := _slot_rect.position + _slot_rect.size * 0.5
			_touch_send(true, _mid)
			_touch_send(false, _mid)
			print("   after the tap on the item: tooltip=%s equipped_at(0)=%s"
				% [str(ui._tooltip_item != null), str(main.inventory.equipped_at(0))])
			_touch_send(true, to)
			_touch_send(false, to)
			_ok("C: tap-then-tap puts the helmet on slot 0",
				main.inventory.equipped_at(0) == _item,
				"equipped_at(0)=%s" % str(main.inventory.equipped_at(0)))
			_step = 6
			_t = 0.0
		6:
			if _t < 0.3:
				return false
			print("== C2. the direct call, as the older tests do it ==")
			_setup_case("cap")
			_step = 7
			_t = 0.0
		7:
			if _t < 0.25:
				return false
			var to := _slot_rect.position + _slot_rect.size * 0.5
			ui._on_press(_mid, 1)
			ui._on_move(to, 1)
			ui._on_release(to)
			_ok("C2: direct _on_press/_on_move/_on_release equips it",
				main.inventory.equipped_at(0) == _item,
				"equipped_at(0)=%s" % str(main.inventory.equipped_at(0)))
			print("EQUIP_DRAG_DONE")
			return true
	return false
