extends Control
## The inventory window - D2 LoD: a 10x4 bag of squares with Tetris shapes, a
## column of equipment slots, both drawn by hand and hit-tested by hand.
##
## WHY ONE NODE DRAWS EVERYTHING: a 40-cell bag with an item per cell as separate
## Controls is 40 nodes plus one per item, and every drag would touch them all.
## Here the whole window is ONE Control: `_draw()` paints the grid, the items, the
## slots and the drag ghost, and `_gui_input()` turns a tap into cell coordinates.
## Two nodes for the whole screen, and the hit test is arithmetic rather than a
## scene-tree walk.
##
## Rules it obeys (art direction + Jan's mobile PWA constraints):
##   * NO hover / focus styling. A cell highlights only while it is being
##     TOUCHED, never because a mouse is over it.
##   * flat fills, warm desaturated palette, no glow, no gradients, no emoji.
##   * everything is big enough to hit with a thumb: a cell is a fraction of the
##     screen height, not a fixed pixel size.

const IB := preload("res://scripts/item_base.gd")
const Inv := preload("res://scripts/inventory_model.gd")
const Icon := preload("res://scripts/item_icon.gd")
const TapGuard := preload("res://scripts/tap_guard.gd")

## palette
const COL_PANEL := Color(0.075, 0.065, 0.058, 0.94)
const COL_CELL := Color(0.145, 0.125, 0.105)
const COL_CELL_EDGE := Color(0.26, 0.21, 0.15)
const COL_SLOT_FILL := Color(0.115, 0.10, 0.085)
const COL_SLOT_EDGE := Color(0.38, 0.31, 0.20)
const COL_ITEM_FILL := Color(0.20, 0.17, 0.14)
const COL_ITEM_EDGE := Color(0.46, 0.38, 0.25)
const COL_TEXT := Color(0.90, 0.85, 0.72)
const COL_TEXT_DIM := Color(0.62, 0.57, 0.48)
const COL_HIGHLIGHT := Color(0.95, 0.80, 0.42, 0.30)
const COL_BAD := Color(0.90, 0.35, 0.28, 0.35)
const COL_RULE := Color(0.30, 0.25, 0.17)

const PAD := 10.0                 ## panel padding, in cell-independent px
const GAP := 14.0                 ## between the bag and the equipment column
const SLOT_COLS := 2              ## equipment column width, in cells
const SLOT_ROWS := 5              ## 5 rows x 2 columns = the 10 slots

signal item_used(item)            ## an item was equipped (stat page must refresh)
signal notify(text: String)       ## a refusal reason, shown by the HUD

var model                          ## inventory_model.gd
var stats                          ## hero_stats.gd, read-only here
var open: bool = false

var _cell: float = 40.0
var _bag_origin: Vector2 = Vector2.ZERO
var _slot_origin: Vector2 = Vector2.ZERO
var _slot_size: Vector2 = Vector2.ZERO
var _panel: Rect2 = Rect2()

## --- interaction state (touch-first: press, move, release) -------------------
var _touch_index: int = -1
var _drag_item = null
var _drag_from_slot: int = -1
var _drag_off: Vector2 = Vector2.ZERO
var _pointer: Vector2 = Vector2.ZERO
var _hover_cell: Vector2i = Vector2i(-1, -1)
var _hover_slot: int = -1
var _hover_ok: bool = true
var _press_at: Vector2 = Vector2.ZERO
var _moved: bool = false
## Long-press opens the tooltip: Diablo shows an item's stats while a modifier is
## held, and on a phone the equivalent gesture is holding the item.
var _hold_t: float = 0.0
var _tooltip_item = null
var _tooltip_at: Vector2 = Vector2.ZERO

## The item the player has PICKED UP by tapping a bag cell, waiting for him to tap
## the box he wants it in. This is the phone-sized equivalent of D2's "pick it up,
## put it on", and it exists because a drag on a phone is fiddly and the only other
## paths (a double click, a right click) do not exist on a touchscreen at all.
## Jan's report: "items from the inventory cannot be equipped into the slots."
## Measured in the real window: a drag DOES equip, but "tap the item, then tap the
## box" equipped NOTHING - the tap only opened a tooltip, and a tap on a slot only
## ever UNEQUIPPED. So the whole interaction the player naturally performs did
## nothing.
var _held_item = null
var _held_from_slot: int = -1
var _held_t: float = 0.0

## ONE TAP, ONE ACTION. Input hands the GUI both a synthesised mouse event and the
## real touch for every finger tap, so an unguarded `if pressed: act` runs twice and
## the duplicate undoes the first. See scripts/tap_guard.gd for the measurement.
var _touch_guard = TapGuard.new()

const HOLD_FOR_TOOLTIP := 0.45
const DRAG_SLOP := 12.0
## How long a picked-up item waits for its box before the selection lapses. Without
## a timeout a forgotten selection would be installed by whichever slot the player
## taps next, which is worse than not having the feature.
const HELD_TIMEOUT := 6.0


func _ready() -> void:
	# The window covers the screen so it can swallow taps; `_draw` only paints the
	# panel itself, so the arena stays visible around it.
	# THE RECT IS THE HIT AREA. An anchors preset alone does NOT give a Control a
	# size when its parent is a CanvasLayer - measured: `size == (0, 0)` with the
	# anchors at 0..1, so every tap fell outside and `_gui_input` was never called.
	# This window was hit-tested only through direct `_gui_input` calls in the
	# tests, so the defect had never been visible.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func setup(p_model, p_stats) -> void:
	model = p_model
	stats = p_stats
	if model:
		model.changed.connect(_on_model_changed)
	queue_redraw()


func _on_model_changed() -> void:
	queue_redraw()


func set_open(on: bool) -> void:
	open = on
	visible = on
	_cancel_drag()
	if not on:
		_tooltip_item = null
		_release_held()
	# LAY OUT NOW, do not wait for `_draw`. This window is HIT-TESTED (a tap outside
	# it closes it), and a tap can arrive on the frame it opened - and in a
	# `--headless` run `_draw` is never called at all, so without this the panel's
	# own rect was still (0,0,0,0) and every point read as "outside the window".
	if on:
		layout_now()
	queue_redraw()


func toggle() -> void:
	set_open(not open)


# ------------------------------------------------------------------- geometry
## Everything is sized from the SHORT side of the screen so it fits landscape
## phone and desktop alike, and the panel is centred - never under the thumbs.
func layout_now() -> void:
	var vs: Vector2 = get_viewport_rect().size
	if vs.x <= 0.0 or vs.y <= 0.0:
		return
	var m: float = minf(vs.x, vs.y)
	var total_cols: float = float(Inv.COLS + SLOT_COLS)
	var avail_w: float = vs.x * 0.80 - PAD * 2.0 - GAP
	var avail_h: float = vs.y * 0.86 - PAD * 2.0 - m * 0.10
	_cell = minf(avail_w / total_cols, avail_h / float(Inv.ROWS))
	_cell = maxf(_cell, 18.0)
	var w: float = _cell * total_cols + GAP + PAD * 2.0
	var h: float = _cell * float(Inv.ROWS) + PAD * 2.0 + m * 0.10
	_panel = Rect2(Vector2((vs.x - w) * 0.5, (vs.y - h) * 0.5), Vector2(w, h))
	_bag_origin = _panel.position + Vector2(PAD, PAD + m * 0.045)
	_slot_origin = _bag_origin + Vector2(_cell * float(Inv.COLS) + GAP, 0.0)
	_slot_size = Vector2(_cell * float(SLOT_COLS), _cell * float(SLOT_ROWS))
	# NO `queue_redraw()` HERE. `_draw()` calls this function, so ending it with a
	# redraw request made the Control mark itself dirty from inside its own draw -
	# a redraw loop on every open panel. Callers that CHANGE something already ask
	# for the repaint themselves (set_open, the model's `changed` signal).


func cell_at(p: Vector2) -> Vector2i:
	var rel := p - _bag_origin
	if rel.x < 0.0 or rel.y < 0.0:
		return Vector2i(-1, -1)
	var c := Vector2i(int(rel.x / _cell), int(rel.y / _cell))
	if c.x >= Inv.COLS or c.y >= Inv.ROWS:
		return Vector2i(-1, -1)
	return c


func slot_at(p: Vector2) -> int:
	if not Rect2(_slot_origin, _slot_size).has_point(p):
		return -1
	var rel := p - _slot_origin
	var col := int(rel.x / _cell)
	var row := int(rel.y / _cell)
	if col < 0 or col >= SLOT_COLS or row < 0 or row >= SLOT_ROWS:
		return -1
	# reading order: helm, chest, belt, boots, gloves down the left column, then
	# amulet, ring, ring, main hand, off hand down the right - D2's arrangement.
	var idx := row * SLOT_COLS + col
	return idx if idx < Inv.SLOTS.size() else -1


func placement_at_cell(c: Vector2i) -> int:
	if model == null:
		return -1
	for i in model.placements.size():
		var p: Dictionary = model.placements[i]
		var pos: Vector2i = p["pos"]
		var sz: Vector2i = p["size"]
		if c.x >= pos.x and c.x < pos.x + sz.x and c.y >= pos.y and c.y < pos.y + sz.y:
			return i
	return -1


# --------------------------------------------------------------------- input
func _gui_input(event: InputEvent) -> void:
	if not open or model == null:
		return
	# ONE FINGER TAP MUST BE ONE ACTION. Input synthesises an InputEventMouseButton
	# from every InputEventScreenTouch and the GUI receives BOTH, so without the
	# guard every tap was handled twice and the second pass undid the first -
	# measured: tap a bag item -> picked up, then dropped again; drag onto a box ->
	# equipped, then unequipped with no message. See scripts/tap_guard.gd.
	#
	# Only the event that OPENS or CLOSES the gesture acts; the duplicate is
	# dropped. Drag events are not gated: a finger drag delivers ScreenDrag and NO
	# MouseMotion (measured), and a mouse drag delivers only motion, so gating those
	# would break dragging on whichever device produced the other kind.
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _touch_guard.begin():
				_on_press(t.position, t.index)
		elif _touch_guard.end():
			_on_release(t.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_on_move(d.position, d.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _touch_guard.begin():
					_on_press(mb.position, 0)
			elif _touch_guard.end():
				_on_release(mb.position)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			# right click = use / equip, the D2 desktop habit
			_quick_use(mb.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_on_mouse_motion((event as InputEventMouseMotion).position)


## Mouse motion only updates the CURSOR position (there is no hover styling); a
## button held down turns it into a drag.
func _on_mouse_motion(p: Vector2) -> void:
	_pointer = p
	if _touch_index < 0:
		return
	if p.distance_to(_press_at) > DRAG_SLOP and not _moved:
		_start_drag()
	if _moved:
		_update_hover()
		queue_redraw()


func _on_press(p: Vector2, index: int) -> void:
	if _touch_index >= 0:
		return
	_touch_index = index
	_press_at = p
	_pointer = p
	_moved = false
	_hold_t = 0.0
	_update_hover()
	queue_redraw()


func _on_move(p: Vector2, index: int) -> void:
	if index != _touch_index:
		return
	_pointer = p
	if not _moved and p.distance_to(_press_at) > DRAG_SLOP:
		_start_drag()
	if _moved:
		_update_hover()
		queue_redraw()


func _on_release(p: Vector2) -> void:
	_pointer = p
	var was_drag := _moved
	_touch_index = -1
	_hold_t = 0.0
	_tooltip_item = null
	if was_drag:
		_finish_drag(p)
	else:
		_tap(p)
	_cancel_drag()
	queue_redraw()


func _process(delta: float) -> void:
	# a lost release must not wedge the guard: see TapGuard.MAX_LIVE_FRAMES
	_touch_guard.tick()
	if not open:
		return
	# A picked-up item lapses, so a forgotten selection cannot be installed by the
	# next box the player taps for an unrelated reason.
	if _held_item != null:
		_held_t += delta
		if _held_t >= HELD_TIMEOUT:
			_release_held()
			queue_redraw()
	# long press -> tooltip
	if _touch_index >= 0 and not _moved:
		_hold_t += delta
		if _hold_t >= HOLD_FOR_TOOLTIP and _tooltip_item == null:
			_update_hover()
			var it: Variant = _item_under(_pointer)
			if it != null:
				_tooltip_item = it
				_tooltip_at = _pointer
				queue_redraw()


func _item_under(p: Vector2):
	var si := slot_at(p)
	if si >= 0:
		return model.equipped_at(si)
	var pi := placement_at_cell(cell_at(p))
	if pi >= 0:
		return model.placements[pi]["item"]
	return null


func _start_drag() -> void:
	_moved = true
	var si := slot_at(_press_at)
	if si >= 0 and model.equipped_at(si) != null:
		_drag_item = model.equipped_at(si)
		_drag_from_slot = si
		_drag_off = Vector2(_cell * 0.5, _cell * 0.5)
		return
	var pi := placement_at_cell(cell_at(_press_at))
	if pi >= 0:
		_drag_item = model.placements[pi]["item"]
		_drag_from_slot = -1
		var item_size: Vector2i = model.placements[pi]["size"]
		_drag_off = _press_at - (_bag_origin + Vector2(model.placements[pi]["pos"]) * _cell)


func _cancel_drag() -> void:
	_drag_item = null
	_drag_from_slot = -1
	_moved = false
	_hover_cell = Vector2i(-1, -1)
	_hover_slot = -1
	if _drag_item != null:
		# A drag and a carried item are two halves of the same gesture; starting a
		# drag clears the carried selection so the two can never both be live.
		_release_held()


## Where the dragged item's top-left cell would land, and whether it is legal.
func _update_hover() -> void:
	_hover_cell = Vector2i(-1, -1)
	_hover_slot = -1
	_hover_ok = true
	if _drag_item == null:
		return
	var size: Vector2i = _drag_item.size()
	var si := slot_at(_pointer)
	if si >= 0:
		_hover_slot = si
		_hover_ok = Inv.SLOTS[si] == _drag_item.slot() and not (
			_drag_item.is_two_handed() and Inv.SLOTS[si] == IB.Slot.OFF_HAND)
		return
	var tl := _pointer - _drag_off
	var c := cell_at(tl)
	if c.x < 0:
		# the pointer may be just outside the bag while the item still fits
		var rel := tl - _bag_origin
		c = Vector2i(int(round(rel.x / _cell)), int(round(rel.y / _cell)))
	_hover_cell = c
	_hover_ok = model.can_place(c, size, model.placement_index_of(_drag_item))


func _finish_drag(p: Vector2) -> void:
	if _drag_item == null or model == null:
		return
	var si := slot_at(p)
	if si >= 0:
		var res: Dictionary = model.equip(_drag_item, si) if _drag_from_slot < 0 \
			else {"ok": true, "reason": ""}
		if _drag_from_slot >= 0:
			# moving between slots is not supported by D2 either - a worn ring goes
			# back to the bag first - so a slot-to-slot drag is a refusal, not a swap
			res = {"ok": false, "reason": "Předmět nejdřív sundej do inventáře."}
		if not bool(res.get("ok", false)):
			notify.emit(str(res.get("reason", "")))
		else:
			item_used.emit(_drag_item)
		return
	var tl := p - _drag_off
	var c := cell_at(tl)
	if c.x < 0:
		var rel := tl - _bag_origin
		c = Vector2i(int(round(rel.x / _cell)), int(round(rel.y / _cell)))
	var size: Vector2i = _drag_item.size()
	if _drag_from_slot >= 0:
		# un-equip onto the bag: only legal where the whole item fits
		if model.can_place(c, size) and model.unequip(_drag_from_slot) != null:
			model.place_at(_drag_item, c)
			item_used.emit(_drag_item)
		else:
			notify.emit("Sem se předmět nevejde.")
		return
	if model.place_at(_drag_item, c):
		item_used.emit(_drag_item)
	else:
		notify.emit("Sem se předmět nevejde.")


## A tap: pick a slot or a cell, then either equip (slot) or show the tooltip.
func _tap(p: Vector2) -> void:
	var si := slot_at(p)
	if si >= 0:
		# A tapped BOX: install whatever is being carried from the bag, or take the
		# worn item off. The pick-up path is what makes equipping possible at all on
		# a touchscreen - before it, a tap on a box only ever unequipped, and the
		# only ways to put something ON were a double click and a right click.
		if _held_item != null:
			_install_held(si)
			return
		var worn: Variant = model.equipped_at(si)
		if worn != null:
			if model.unequip(si) != null:
				item_used.emit(worn)
			else:
				notify.emit("V inventáři není místo.")
		return
	var pi := placement_at_cell(cell_at(p))
	if pi >= 0:
		var it: Variant = model.placements[pi]["item"]
		if _held_item == it:
			# tapping the carried item again puts it back down
			_release_held()
			notify.emit("Odloženo.")
			return
		_held_item = it
		_held_from_slot = -1
		_held_t = 0.0
		_tooltip_item = it
		_tooltip_at = p
		notify.emit("Vybráno: nasaď klepnutím na políčko." if it.slot() != IB.Slot.NONE
			else "Vybráno: %s nelze nosit." % it.display_name())
		return
	_tooltip_item = null
	_release_held()


## Puts the carried item into the box the player tapped, with the model answering -
## so a box that does not match the item's TYPE is refused with a reason, and the
## Strength gate and the two-handed rules are the same ones a drag goes through.
func _install_held(slot_index: int) -> void:
	var it = _held_item
	var res: Dictionary = model.equip_with_requirement(it, stats, slot_index)
	if bool(res.get("ok", false)):
		_release_held()
		item_used.emit(it)
	else:
		notify.emit(str(res.get("reason", "")))


func _release_held() -> void:
	_held_item = null
	_held_from_slot = -1
	_held_t = 0.0


## Double click / double tap is the second path to equipping, because dragging on
## a phone is fiddly and D2's own habit is "pick it up, put it on".
func _quick_use(p: Vector2) -> void:
	var si := slot_at(p)
	if si >= 0:
		var worn: Variant = model.equipped_at(si)
		if worn != null and model.unequip(si) != null:
			item_used.emit(worn)
		return
	var pi := placement_at_cell(cell_at(p))
	if pi < 0:
		return
	var it: Variant = model.placements[pi]["item"]
	var res: Dictionary = model.equip_with_requirement(it, stats)
	if bool(res.get("ok", false)):
		item_used.emit(it)
	else:
		notify.emit(str(res.get("reason", "")))


func _unhandled_input(event: InputEvent) -> void:
	# A double click on desktop, and the only way a test can drive the window
	# without a pointer: handled through the same path as a right click.
	if not open or model == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click and mb.pressed:
			_quick_use(mb.position)
			get_viewport().set_input_as_handled()


# --------------------------------------------------------------------- drawing
func _draw() -> void:
	if model == null:
		return
	layout_now()
	_draw_panel()
	_draw_slots()
	_draw_bag()
	_draw_items()
	if _held_item != null:
		_draw_held_marker()
	if _drag_item != null:
		_draw_drag_ghost()
	if _tooltip_item != null and _drag_item == null:
		_draw_tooltip()


func _draw_panel() -> void:
	draw_rect(_panel, COL_PANEL, true)
	draw_rect(_panel, COL_SLOT_EDGE, false, 2.0)
	var vs := get_viewport_rect().size
	var m: float = minf(vs.x, vs.y)
	draw_string(_font(), _panel.position + Vector2(PAD, PAD + m * 0.032),
		"Inventář", HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(maxf(12.0, m * 0.028)), COL_TEXT)
	var hint := "tažením přesouváš, kliknutím nasazuješ, podržením zobrazíš vlastnosti"
	draw_string(_font(), _panel.position + Vector2(PAD, _panel.end.y - PAD * 0.4),
		hint, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(maxf(10.0, m * 0.020)), COL_TEXT_DIM)


func _font() -> Font:
	return ThemeDB.fallback_font


func _draw_bag() -> void:
	for y in Inv.ROWS:
		for x in Inv.COLS:
			var r := Rect2(_bag_origin + Vector2(x, y) * _cell, Vector2(_cell, _cell))
			draw_rect(r.grow(-1.0), COL_CELL, true)
			draw_rect(r.grow(-1.0), COL_CELL_EDGE, false, 1.0)


func _draw_slots() -> void:
	for i in Inv.SLOTS.size():
		var r := _slot_rect(i)
		draw_rect(r.grow(-1.0), COL_SLOT_FILL, true)
		draw_rect(r.grow(-1.0), COL_SLOT_EDGE, false, 1.0)
		if model.equipped_at(i) == null:
			var slot_name := str(IB.SLOT_NAMES.get(Inv.SLOTS[i], ""))
			if Inv.SLOTS[i] == IB.Slot.RING:
				slot_name = "Prsten 1" if not Inv.is_second_ring(i) else "Prsten 2"
			var fs := int(maxf(8.0, _cell * 0.24))
			draw_string(_font(), r.position + Vector2(4.0, r.size.y * 0.5 + fs * 0.35),
				slot_name, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 6.0, fs, COL_TEXT_DIM)


func _slot_rect(i: int) -> Rect2:
	var col := i % SLOT_COLS
	var row := int(i / SLOT_COLS)
	return Rect2(_slot_origin + Vector2(col, row) * _cell, Vector2(_cell, _cell))


func _draw_items() -> void:
	for i in model.placements.size():
		var p: Dictionary = model.placements[i]
		if p["item"] == _drag_item:
			continue
		_draw_item_rect(_bag_rect(p["pos"], p["size"]), p["item"])
	for i in Inv.SLOTS.size():
		var it: Variant = model.equipped_at(i)
		if it != null and it != _drag_item:
			_draw_item_rect(_slot_rect(i), it)


func _bag_rect(pos: Vector2i, size: Vector2i) -> Rect2:
	return Rect2(_bag_origin + Vector2(pos) * _cell, Vector2(size) * _cell)


func _draw_item_rect(r: Rect2, item) -> void:
	var inner := r.grow(-2.0)
	draw_rect(inner, COL_ITEM_FILL, true)
	draw_rect(inner, item.rarity_color().darkened(0.45), false, 1.0)
	# the rarity bar along the top edge: colour alone carries rarity, D2 style
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, maxf(2.0, _cell * 0.05))),
		item.rarity_color(), true)
	var icon_rect := inner.grow(-_cell * 0.14)
	Icon.draw(self, str(item.base().get("shape", "sword")), icon_rect)


## The item carried in the bag is marked, so a player who tapped it knows the game
## is waiting for the box - a selection with no visual state reads as a dead tap.
func _draw_held_marker() -> void:
	var pi: int = model.placement_index_of(_held_item) if _held_item != null else -1
	if pi < 0:
		return
	var p: Dictionary = model.placements[pi]
	var r: Rect2 = _bag_rect(p["pos"], p["size"]).grow(-2.0)
	draw_rect(r, COL_HIGHLIGHT, true)
	draw_rect(r, COL_ITEM_EDGE, false, 3.0)


func _draw_drag_ghost() -> void:
	var size: Vector2i = _drag_item.size()
	var tl := _pointer - _drag_off
	if _hover_slot >= 0:
		tl = _slot_rect(_hover_slot).position
		var col := COL_HIGHLIGHT if _hover_ok else COL_BAD
		draw_rect(_slot_rect(_hover_slot).grow(-1.0), col, true)
	elif _hover_cell.x >= 0:
		var r := _bag_rect(_hover_cell, size)
		draw_rect(Rect2(_bag_origin + Vector2(_hover_cell) * _cell,
			Vector2(size) * _cell).grow(-1.0),
			COL_HIGHLIGHT if _hover_ok else COL_BAD, true)
	var ghost := Rect2(tl, Vector2(size) * _cell)
	draw_rect(ghost, Color(COL_ITEM_FILL, 0.85), true)
	draw_rect(ghost, _drag_item.rarity_color(), false, 2.0)
	Icon.draw(self, str(_drag_item.base().get("shape", "sword")), ghost.grow(-_cell * 0.14))


## The item's own numbers, exactly as `item.tooltip_lines()` prints them - the
## window never formats a stat itself, so a tooltip cannot disagree with the sheet.
func _draw_tooltip() -> void:
	var lines: Array = _tooltip_item.tooltip_lines()
	var vs := get_viewport_rect().size
	var m: float = minf(vs.x, vs.y)
	var fs := int(maxf(11.0, m * 0.022))
	var line_h := fs + 6.0
	var w := 0.0
	for l in lines:
		w = maxf(w, _font().get_string_size(str(l), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x)
	var box_size := Vector2(w + PAD * 2.0, line_h * lines.size() + PAD * 2.0)
	var at := _tooltip_at + Vector2(_cell * 0.6, 0.0)
	# keep the tooltip on screen: a box half off the edge is a bug on a phone
	if at.x + box_size.x > vs.x:
		at.x = vs.x - box_size.x - 4.0
	if at.y + box_size.y > vs.y:
		at.y = vs.y - box_size.y - 4.0
	at.x = maxf(4.0, at.x)
	at.y = maxf(4.0, at.y)
	var box := Rect2(at, box_size)
	draw_rect(box, Color(0.045, 0.040, 0.035, 0.97), true)
	draw_rect(box, _tooltip_item.rarity_color(), false, 2.0)
	for i in lines.size():
		var col := COL_TEXT if i == 0 else COL_TEXT_DIM
		if i == 0:
			col = _tooltip_item.rarity_color()
		draw_string(_font(), at + Vector2(PAD, PAD + line_h * (i + 0.8)), str(lines[i]),
			HORIZONTAL_ALIGNMENT_LEFT, box_size.x - PAD * 2.0, fs, col)


## Screen rectangle of an item's bag slot. Exposed so a test (and the loot pickup
## highlight) can point at a cell without duplicating the layout maths.
func cell_rect(pos: Vector2i, size: Vector2i) -> Rect2:
	return _bag_rect(pos, size)
