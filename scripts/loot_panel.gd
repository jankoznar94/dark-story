extends Control
## The LOOT WINDOW: what is inside the body the player just opened.
##
## Jan's model (Sept 2026): "the player opens the body and picks the items out of
## it". So this is the piece that makes that readable - a short list with each
## item's own icon, its name in its rarity colour, and a tap to take it. A "take
## everything" row sits at the bottom, because on a phone tapping four rows is
## four chances to mis-tap.
##
## Same construction as the inventory: ONE Control that draws itself and
## hit-tests itself, mouse_filter IGNORE while closed so gameplay taps pass
## through, STOP while open so a tap cannot also swing the sword. No hover or
## focus styling (mobile PWA rule) - a row highlights only while the list is up.
##
## The panel PAUSES the fight while it is open, exactly like the bag: main.gd
## reads `hud.panel_open()`, which includes this window.

const IB := preload("res://scripts/item_base.gd")
const Icon := preload("res://scripts/item_icon.gd")
const TapGuard := preload("res://scripts/tap_guard.gd")

const COL_SCRIM := Color(0.02, 0.02, 0.02, 0.34)
const COL_PANEL := Color(0.075, 0.065, 0.058, 0.96)
const COL_EDGE := Color(0.38, 0.31, 0.20)
const COL_ROW := Color(0.145, 0.125, 0.105)
const COL_ROW_ALT := Color(0.125, 0.108, 0.090)
const COL_TEXT := Color(0.90, 0.85, 0.72)
const COL_DIM := Color(0.62, 0.57, 0.48)
const COL_TAKE := Color(0.20, 0.26, 0.17)
const COL_TAKE_EDGE := Color(0.45, 0.55, 0.30)

const PAD := 12.0

## How long the window must be on screen before a tap can dismiss it. THE TAP THAT
## OPENS THE BODY IS THE SAME TAP THE WINDOW SEES: `main.gd` opens the panel off the
## loot manager's `body_opened` signal while the touch is still being delivered, the
## panel is full-rect and swallows what is left of it, and the tap is nowhere near
## the window's own box (the corpse is at the player's feet, the window is centred),
## so the "tap outside the panel closes it" exit fired IMMEDIATELY.
##
## Jan's report (Sept 2026): "when I try to open the loot, nothing appears. The
## joystick and the action buttons just disappear, the loot is not visible and so it
## cannot be selected." That is exactly this: everything the panel does on open
## happened (the HUD hid the fight controls) and the window was gone in the same
## frame. Measured in a real window with a real tap: the panel was open with 1 row
## and CLOSED again from `loot_panel._gui_input` -> `_handle` -> `set_open(false)`.
const CLOSE_ARM_MS := 250

signal item_taken(item)
signal closed

var loot                      ## loot_manager.gd
var inventory                 ## inventory_model.gd
var stats                     ## hero_stats.gd, read-only here
var open: bool = false

var _body = null              ## the loot_body.gd node being shown
var _items: Array = []
var _rows: Array = []         ## Array[Rect2], parallel to _items
var _all_rect: Rect2 = Rect2()
var _close_rect: Rect2 = Rect2()
var _box: Rect2 = Rect2()
## Milliseconds left before a tap may dismiss the window. Set on every open; see
## CLOSE_ARM_MS for why the tap that opened the body must not close it again.
var _arm_ms: float = 0.0

## ONE TAP, ONE ACTION. Input hands the GUI a synthesised mouse event AND the real
## touch for a single finger tap. Without this guard a tap on a row took the item
## twice over (the second `_handle` found the row rects of the refreshed, shorter
## list), and a tap on "Vzít vše" ran the whole take twice. Measured with real
## injected events: one tap produced two handled presses. See scripts/tap_guard.gd.
var _touch_guard = TapGuard.new()


func _ready() -> void:
	# THE RECT IS THE HIT AREA. `set_anchors_preset()` alone was NOT enough:
	# measured, `size == (0, 0)` with the anchors at 0..1, because the OFFSETS were
	# left at their defaults, which cancel the parent rect. Every tap then fell
	# outside the panel and `_gui_input` was never called - Jan's report, "the items
	# in the body cannot be taken", which looked like a broken list rather than a
	# broken rect. The preset that sets BOTH is what makes it full-screen.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# IGNORE while closed: the taps belong to the game then. STOP while open, so
	# the tap that takes an item cannot also reach the world.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func setup(p_loot, p_inventory, p_stats) -> void:
	loot = p_loot
	inventory = p_inventory
	stats = p_stats
	if loot != null:
		loot.item_picked.connect(_on_item_picked)
	queue_redraw()


func _on_item_picked(_item) -> void:
	# The model changed under us (a pickup from anywhere): re-read the body.
	refresh()


## Shows the contents of `body`. An empty body is a message, not a list.
func set_body(body) -> void:
	_body = body
	# set_open() lays out, and it must see the NEW contents: the order here is the
	# whole reason the row rects are right on the frame the window comes up.
	_items = [] if (loot == null or body == null) else loot.items_in(body)
	set_open(true)


func refresh() -> void:
	_items = [] if (loot == null or _body == null) else loot.items_in(_body)
	queue_redraw()


func set_open(on: bool) -> void:
	open = on
	visible = on
	mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	# THE SAME TAP MUST NOT CLOSE WHAT IT JUST OPENED. Every open arms this timer,
	# and `_handle` ignores a dismiss until it runs out (see CLOSE_ARM_MS).
	_arm_ms = CLOSE_ARM_MS if on else 0.0
	# LAY OUT NOW, do not wait for `_draw`. The other two panels only lay out in
	# `_draw` because they are pure pictures; this one is hit-tested, and a tap can
	# arrive on the same frame the window opened. Measured: without this the row
	# rects were still the previous state's (in headless, `_draw` never runs at
	# all, so they were empty) and a tap on a row hit nothing.
	layout_now()
	queue_redraw()
	if not on:
		_body = null
		closed.emit()


## The open guard is TIME-based, so it needs a clock; `_process` is enabled for the
## few frames the timer is alive and nothing else. Without this the guard would be
## frozen at whatever the first frame set it to and the window could never be closed
## by a tap outside it at all.
func _process(delta: float) -> void:
	_touch_guard.tick()
	if _arm_ms > 0.0:
		_arm_ms = maxf(0.0, _arm_ms - delta * 1000.0)


# ------------------------------------------------------------------- geometry
## Sized from the SHORT side of the screen like the other panels, so it fits a
## landscape phone and a desktop alike, and centred so it never sits under a thumb.
func layout_now() -> void:
	var vs: Vector2 = get_viewport_rect().size
	if vs.x <= 0.0 or vs.y <= 0.0:
		return
	var m: float = minf(vs.x, vs.y)
	var row_h: float = maxf(30.0, m * 0.075)
	var title_h: float = maxf(24.0, m * 0.062)
	var lines: int = maxi(_items.size(), 1)
	var w: float = clampf(vs.x * 0.52, 260.0, 620.0)
	var h: float = title_h + row_h * float(lines) + row_h * 1.15 + PAD * 2.0
	_box = Rect2(Vector2((vs.x - w) * 0.5, (vs.y - h) * 0.5), Vector2(w, h))

	var row_w: float = w - PAD * 2.0
	var y: float = _box.position.y + title_h + PAD
	_rows = []
	for i in _items.size():
		_rows.append(Rect2(Vector2(_box.position.x + PAD, y), Vector2(row_w, row_h)))
		y += row_h
	_all_rect = Rect2(Vector2(_box.position.x + PAD, y), Vector2(row_w, row_h))
	var cr: float = title_h * 0.8
	_close_rect = Rect2(Vector2(_box.end.x - PAD - cr, _box.position.y + (title_h - cr) * 0.5),
		Vector2(cr, cr))
	# NO `queue_redraw()` HERE. It used to end this function, and `_draw()` calls
	# this function - so the Control marked itself dirty from inside its own draw
	# and could redraw forever (the "the game locks up" half of the report). Every
	# caller that CHANGES something already asks for the repaint itself.


# ---------------------------------------------------------------------- input
func _gui_input(event: InputEvent) -> void:
	if not open:
		return
	# ONE FINGER TAP, ONE ACTION - see scripts/tap_guard.gd. Only the first of the
	# pair (synthesised mouse + real touch) is handled; otherwise one tap took the
	# item twice and "Vzít vše" ran twice.
	#
	# THE RELEASE MUST END THE GESTURE even though it carries no action of its own.
	# An earlier version of this guard only opened it, so after the FIRST tap the
	# guard stayed live and every later tap was dropped as a duplicate - the panel
	# went permanently deaf. Measured: `test_panels` reported "0 -> 0 bag items" on
	# every tap after the first one.
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _touch_guard.begin():
				_handle(t.position)
			get_viewport().set_input_as_handled()
		else:
			_touch_guard.end()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _touch_guard.begin():
					_handle(mb.position)
			else:
				_touch_guard.end()
			get_viewport().set_input_as_handled()
	# a drag on a list is nothing to do; the events are swallowed so a swipe
	# across the panel cannot reach the world behind it


## A tap: an item row takes that item, the bottom row takes everything, the close
## box closes, and anywhere else on the backdrop closes too (the phone habit).
##
## The dismiss paths are GATED by `_arm_ms`: the touch that opened the body is the
## same touch this Control receives, so without the gate the window closed in the
## same frame it appeared.
##
## THE ROWS ARE GATED TOO - and that is a fix, not a safety net. Jan: *"when I click
## a corpse, all the items are selected straight away and the window does not appear
## at all."* The tap that opens a body arrives while the panel is being built, and
## its tail lands wherever on screen the finger is: the corpse is at the player's
## feet and the window is centred, so a tap at the bottom of the screen can land on
## a ROW. A row is never gated, so the item was taken in the same frame, and a body
## with one item then closed itself ("the body is empty" path) - which is exactly
## "everything got selected and the window never showed". Taking an item is
## unambiguous; taking it from a tap that was aimed at the corpse is not.
func _handle(p: Vector2) -> void:
	if _close_rect.has_point(p):
		if _arm_ms <= 0.0:
			set_open(false)
		return
	if _arm_ms <= 0.0:
		for i in _rows.size():
			if (_rows[i] as Rect2).has_point(p):
				_take(_items[i])
				return
		if _all_rect.has_point(p):
			take_all()
			return
	if not _box.has_point(p) and _arm_ms <= 0.0:
		set_open(false)


func _take(item) -> void:
	if loot == null or _body == null:
		return
	var got: Variant = loot.take_item(_body, item, inventory)
	if got != null:
		item_taken.emit(got)
	else:
		# the bag-full reason is announced by the loot manager's own signal
		pass
	refresh()
	if _items.is_empty():
		# The body is empty: the window has done its job. WoW closes here too.
		set_open(false)


func take_all() -> void:
	if loot == null or _body == null:
		return
	var left: Array = _items.duplicate()
	for item in left:
		if loot.take_item(_body, item, inventory) == null:
			break          # the bag is full; stop instead of skipping the rest
		item_taken.emit(item)
	refresh()
	if _items.is_empty():
		set_open(false)


func close_panel() -> void:
	set_open(false)


# -------------------------------------------------------------------- drawing
func _draw() -> void:
	if not open:
		return
	layout_now()
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), COL_SCRIM, true)
	draw_rect(_box, COL_PANEL, true)
	draw_rect(_box, COL_EDGE, false, 2.0)

	var m: float = minf(get_viewport_rect().size.x, get_viewport_rect().size.y)
	var title_fs := int(maxf(13.0, m * 0.030))
	var row_fs := int(maxf(12.0, m * 0.026))
	var name: String = "Tělo" if _body == null else "Tělo: %s" % _body.monster_name
	draw_string(ThemeDB.fallback_font, _box.position + Vector2(PAD, PAD * 0.6 + title_fs),
		name, HORIZONTAL_ALIGNMENT_LEFT, _box.size.x - PAD * 3.0 - title_fs, title_fs, COL_TEXT)

	# the close box: an X drawn as two lines, not a glyph - no font dependency
	var c := _close_rect.position + _close_rect.size * 0.5
	var r: float = _close_rect.size.x * 0.28
	draw_line(c + Vector2(-r, -r), c + Vector2(r, r), COL_TEXT, 2.0)
	draw_line(c + Vector2(-r, r), c + Vector2(r, -r), COL_TEXT, 2.0)

	if _items.is_empty():
		draw_string(ThemeDB.fallback_font,
			Vector2(_box.position.x + PAD, _box.position.y + _box.size.y * 0.55),
			"Tělo je prázdné.", HORIZONTAL_ALIGNMENT_LEFT, -1.0, row_fs, COL_DIM)
		return

	for i in _items.size():
		var it: Variant = _items[i]
		var rect: Rect2 = _rows[i]
		draw_rect(rect.grow(-1.0), COL_ROW if i % 2 == 0 else COL_ROW_ALT, true)
		draw_rect(Rect2(rect.position, Vector2(maxf(2.0, rect.size.y * 0.06), rect.size.y)),
			it.rarity_color(), true)
		var icon: Rect2 = Rect2(rect.position + Vector2(rect.size.y * 0.18, rect.size.y * 0.14),
			Vector2(rect.size.y * 0.72, rect.size.y * 0.72))
		Icon.draw(self, str(it.base().get("shape", "sword")), icon)
		draw_string(ThemeDB.fallback_font,
			rect.position + Vector2(rect.size.y * 1.05, rect.size.y * 0.68),
			it.display_name(), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - rect.size.y * 1.2,
			row_fs, it.rarity_color())

	draw_rect(_all_rect.grow(-1.0), COL_TAKE, true)
	draw_rect(_all_rect.grow(-1.0), COL_TAKE_EDGE, false, 1.0)
	draw_string(ThemeDB.fallback_font,
		_all_rect.position + Vector2(PAD, _all_rect.size.y * 0.68),
		"Vzít vše", HORIZONTAL_ALIGNMENT_LEFT, -1.0, row_fs, COL_TEXT)
