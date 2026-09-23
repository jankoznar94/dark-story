extends SceneTree
## probe_tap_drag.gd — an EMPIRICAL probe, not a test.
##
## Jan wants a page scrolled by DRAGGING with no scrollbar. Two things cannot be reasoned out
## from the docs and have to be measured on the real Viewport pipeline:
##
##   1. Which events the port's own driver (`ScrollSwipe._input`) actually RECEIVES — Godot's
##      `ScrollContainer` consumes the ones it handles, and the browser may deliver a touch as
##      an emulated mouse.
##   2. What a drag does to a BUTTON under the finger: a finger that never leaves the button's
##      rect keeps `pressing_inside` set, so the release fires the button and the player drags
##      the page and opens a shop tile.
##
## Trace mode prints the driver's own state at every step, so the mechanism is visible instead
## of inferred.

const ScrollSwipe := preload("res://scripts/ui/scroll_swipe.gd")


## A raw event logger: every event the INPUT stage sees, in order, so the delivery path is
## measured rather than inferred. Prints one line per event.
class EventLog extends Node:
	var lines: Array[String] = []

	func _input(event: InputEvent) -> void:
		var kind := event.get_class()
		var extra := ""
		if event is InputEventScreenTouch:
			var t := event as InputEventScreenTouch
			extra = "index=%d pressed=%s pos=%s" % [t.index, str(t.pressed), str(t.position)]
		elif event is InputEventScreenDrag:
			var d := event as InputEventScreenDrag
			extra = "index=%d pos=%s rel=%s" % [d.index, str(d.position), str(d.relative)]
		elif event is InputEventMouseButton:
			var b := event as InputEventMouseButton
			extra = "button=%d pressed=%s pos=%s" % [b.button_index, str(b.pressed), str(b.position)]
		elif event is InputEventMouseMotion:
			var m := event as InputEventMouseMotion
			extra = "pos=%s rel=%s mask=%d" % [str(m.position), str(m.relative), m.button_mask]
		lines.append("%s %s" % [kind, extra])



func _initialize() -> void:
	# `push_input` refuses while the viewport is not inside the tree, which it is not during
	# `_initialize` of a SceneTree script. Build the scene now and run on the first real frame.
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var vp := root
	# A headless run leaves the root Window at 64x64, so every event would be outside it and
	# the GUI hit test would find nothing at all. The port's own canvas is 390x844.
	vp.size = Vector2i(390, 844)

	var host := Control.new()
	host.size = Vector2(390, 844)
	host.position = Vector2.ZERO
	vp.add_child(host)

	var scroll := ScrollContainer.new()
	scroll.size = Vector2(390, 844)
	scroll.position = Vector2.ZERO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.scroll_deadzone = 8
	host.add_child(scroll)

	var content := Control.new()
	content.custom_minimum_size = Vector2(390, 2000)
	scroll.add_child(content)

	# A tall tile, so a drag can stay INSIDE it — that is the case that fires a button.
	var button := Button.new()
	button.text = "TILE"
	button.position = Vector2(20, 100)
	button.size = Vector2(200, 300)
	content.add_child(button)
	var hits := {"n": 0}
	button.pressed.connect(func(): hits["n"] = int(hits["n"]) + 1)

	var swipe := ScrollSwipe.new()
	swipe.setup(scroll)
	host.add_child(swipe)

	print("window %s, scroll rect %s" % [str(vp.size), str(scroll.get_global_rect())])
	print("touchscreen_available=%s emulate_mouse_from_touch=%s"
		% [str(DisplayServer.is_touchscreen_available()),
			str(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch"))])

	var log := EventLog.new()
	host.add_child(log)
	log.set_process_input(true)

	print("-- RAW EVENTS: one touch drag on the tile --")
	log.lines.clear()
	_touch(vp, Vector2(120, 240), 0, true)
	for i in 4:
		_touch_move(vp, Vector2(120, 240 - 6 * (i + 1)), Vector2(0, -6), 0)
	_touch(vp, Vector2(120, 216), 0, false)
	for line in log.lines:
		print("   ", line)

	print("-- TOUCH: tap then a 10-step drag on the tile, driver state each step --")
	_touch(vp, Vector2(120, 123), 0, true)
	print("   tap press   -> pointer=%d" % swipe._pointer)
	_touch(vp, Vector2(120, 123), 0, false)
	print("   tap release -> pointer=%d fired=%d" % [swipe._pointer, int(hits["n"])])

	hits["n"] = 0
	scroll.scroll_vertical = 0
	var start := Vector2(120, 240)
	_touch(vp, start, 0, true)
	print("   drag press   -> pointer=%d scroll=%d fired=%d"
		% [swipe._pointer, scroll.scroll_vertical, int(hits["n"])])
	for i in 10:
		_touch_move(vp, start + Vector2(0, -6 * (i + 1)), Vector2(0, -6), 0)
		print("   motion %2d    -> pointer=%d past=%s scroll=%d fired=%d"
			% [i + 1, swipe._pointer, str(swipe._past_deadzone), scroll.scroll_vertical,
				int(hits["n"])])
	_touch(vp, start + Vector2(0, -60), 0, false)
	print("   drag release -> pointer=%d scroll=%d fired=%d"
		% [swipe._pointer, scroll.scroll_vertical, int(hits["n"])])

	print("-- MOUSE: same gesture, to compare the two delivery paths --")
	hits["n"] = 0
	scroll.scroll_vertical = 0
	_click(vp, start, true)
	print("   drag press   -> pointer=%d scroll=%d fired=%d"
		% [swipe._pointer, scroll.scroll_vertical, int(hits["n"])])
	for i in 10:
		_motion(vp, start + Vector2(0, -6 * (i + 1)), Vector2(0, -6))
		print("   motion %2d    -> pointer=%d past=%s scroll=%d fired=%d"
			% [i + 1, swipe._pointer, str(swipe._past_deadzone), scroll.scroll_vertical,
				int(hits["n"])])
	_click(vp, start + Vector2(0, -60), false)
	print("   drag release -> pointer=%d scroll=%d fired=%d"
		% [swipe._pointer, scroll.scroll_vertical, int(hits["n"])])
	quit(0)


func _touch(vp: Viewport, pos: Vector2, index: int, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.pressed = pressed
	e.position = pos
	vp.push_input(e)


func _touch_move(vp: Viewport, pos: Vector2, rel: Vector2, index: int) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	e.relative = rel
	e.velocity = rel
	vp.push_input(e)


func _click(vp: Viewport, pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	vp.push_input(e)


func _motion(vp: Viewport, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	vp.push_input(e)
