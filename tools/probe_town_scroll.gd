extends SceneTree
## Probe: does a synthesized finger drag scroll the town page, and does the page
## scroll at all before/after a touch-screen is attached?

const MainScript := preload("res://scripts/main.gd")

var _main: Node
var _frame := 0
var _phase := 0
var _report: Array = []
var _scroll: ScrollContainer


func _initialize() -> void:
	_main = MainScript.new()
	root.add_child(_main)


func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 8:
		return false
	if _phase == 0:
		_boot_report()
		_phase = 1
		return false
	if _phase == 1:
		_drag_report()
		_phase = 2
		return false
	if _phase == 2:
		_touch_report()
		_phase = 3
		return false
	_dump()
	return true


func _find_scroll(node: Node, path: String = "") -> ScrollContainer:
	if node is ScrollContainer:
		return node
	for c in node.get_children():
		var found := _find_scroll(c, path + "/" + c.name)
		if found != null:
			return found
	return null


func _screen(name: String) -> Control:
	if _main.has_method("show_screen"):
		_main.show_screen(name)
	for key in _main.get("_screens"):
		if str(key) == name:
			return _main.get("_screens")[key]
	return null


func _boot_report() -> void:
	_report.append("display server touchscreen available: %s" % DisplayServer.is_touchscreen_available())
	_report.append("Input.emulate_touch_from_mouse = %s" % Input.emulate_touch_from_mouse)
	_report.append("Input.emulate_mouse_from_touch = %s" % Input.emulate_mouse_from_touch)
	var town: Control = _screen("town")
	_report.append("town screen found: %s" % (town != null))
	if town == null:
		return
	_scroll = _find_scroll(town)
	_report.append("town scroll found: %s" % (_scroll != null))
	if _scroll == null:
		return
	_report.append("scroll rect=%s scroll_vertical=%d content_h=%.1f page_h=%.1f" % [
		_scroll.get_global_rect(), _scroll.scroll_vertical,
		_scroll.get_child(0).get_combined_minimum_size().y,
		_scroll.size.y])


## A mouse drag with emulate_touch_from_mouse on the touchscreen-less desktop path.
func _drag_report() -> void:
	if _scroll == null:
		return
	var before: int = _scroll.scroll_vertical
	var c := _scroll.get_global_rect().get_center()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = c
	root.push_input(ev)
	for i in range(1, 21):
		var mv := InputEventMouseMotion.new()
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		mv.position = c - Vector2(0, i * 8)
		mv.relative = Vector2(0, -8)
		root.push_input(mv)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = c - Vector2(0, 160)
	root.push_input(up)
	_report.append("MOUSE drag 160px up: scroll_vertical %d -> %d" % [before, _scroll.scroll_vertical])


## A real finger: ScreenTouch + ScreenDrag, the path a phone takes.
func _touch_report() -> void:
	if _scroll == null:
		return
	var before: int = _scroll.scroll_vertical
	var c := _scroll.get_global_rect().get_center()
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
	var rel := InputEventScreenTouch.new()
	rel.index = 0
	rel.pressed = false
	rel.position = c - Vector2(0, 160)
	root.push_input(rel)
	_report.append("TOUCH drag 160px up: scroll_vertical %d -> %d" % [before, _scroll.scroll_vertical])


func _dump() -> void:
	for line in _report:
		print(line)
	print("TOWN_SCROLL_PROBE_DONE=true")
