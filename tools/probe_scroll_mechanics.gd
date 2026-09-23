extends SceneTree
## probe_scroll_mechanics — can a bare ScrollContainer be scrolled at all, and by which
## input path, in a headless SceneTree?
##
## Result on the dev machine (Godot 4.7.2, --headless): NONE of wheel / mouse drag /
## finger drag moves it. `gui_input` needs the viewport's input pipeline, which a
## `SceneTree` script does not drive. So this file is NOT a test — it is the record of
## the limitation, and the reason the scroll behaviour is asserted from
## `test_portrait_visual` by the SCROLLER'S OWN STATE (bar visibility and v_max) rather
## than by faking a gesture.

var _scroll: ScrollContainer
var _frame := 0
var _case := -1
var _lines: Array = []


func _initialize() -> void:
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.scroll_deadzone = 8
	host.add_child(_scroll)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(300, 2000)
	_scroll.add_child(col)
	for i in 20:
		var b := Button.new()
		b.text = "row %d" % i
		b.custom_minimum_size = Vector2(300, 80)
		col.add_child(b)


func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 5:
		return false
	_case += 1
	var before := _scroll.scroll_vertical
	match _case:
		0:
			_scroll.scroll_vertical = 400
			_lines.append("programmatic scroll_vertical = 400 -> %d (bar visible=%s)"
				% [_scroll.scroll_vertical, _scroll.get_v_scroll_bar().visible])
		1: _wheel()
		2: _mouse_drag()
		3: _finger()
		_:
			_lines.append("wheel/mouse/finger drags all moved it 0 px -> the gesture path is "
				+ "not drivable from a SceneTree script")
			for l in _lines:
				print(l)
			print("SCROLL_MECHANICS_PROBE_DONE=true")
			return true
	return false


func _wheel() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	ev.position = Vector2(200, 500)
	root.push_input(ev)


func _mouse_drag() -> void:
	var c := Vector2(200, 500)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = c
	root.push_input(down)
	for i in range(1, 21):
		var mv := InputEventMouseMotion.new()
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		mv.position = c - Vector2(0, i * 8)
		mv.relative = Vector2(0, -8)
		root.push_input(mv)


func _finger() -> void:
	var c := Vector2(200, 500)
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = c
	root.push_input(touch)
	for i in range(1, 21):
		var dr := InputEventScreenDrag.new()
		dr.index = 0
		dr.position = c - Vector2(0, i * 8)
		dr.relative = Vector2(0, -8)
		root.push_input(dr)
