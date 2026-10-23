extends SceneTree
# KONTROLA VSTUPU: posle tlacitka menu SKUTECNYMI vstupnimi udalostmi
# (dotek i mys), ne primym volanim _press. Overi celou cestu _input().
#
#   ~/tools/godot/godot4 --headless --path . --script res://tools/check_tap.gd

var view: Node2D = null
var frame: int = 0
var step: int = 0


func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		view = load("res://main.tscn").instantiate()
		root.add_child(view)
		return false
	if frame == 2:
		view.layout.update(Vector2(390.0, 844.0))
		view._apply_field()
		view.menu.open_menu()
		print("rects=", view.layout.menu_rects.size())
		return false
	if frame == 3:
		var r: Rect2 = view.layout.menu_rects[1]
		var p: Vector2 = r.position + r.size * 0.5
		print("tap at ", p, " rect ", r)
		var ev := InputEventScreenTouch.new()
		ev.index = 0
		ev.position = p
		ev.pressed = true
		Input.parse_input_event(ev)
		return false
	if frame == 5:
		print("po doteku: view=", view.menu.view, " (2 = VYLEPSENI)")
		# druha cast: zpet do menu a klepnuti mysi (desktop)
		view.menu.open_menu()
		return false
	if frame == 6:
		var r2: Rect2 = view.layout.menu_rects[1]
		var p2: Vector2 = r2.position + r2.size * 0.5
		var ev2 := InputEventMouseButton.new()
		ev2.button_index = MOUSE_BUTTON_LEFT
		ev2.position = p2
		ev2.pressed = true
		ev2.global_position = p2
		Input.parse_input_event(ev2)
		return false
	if frame == 8:
		print("po mysi: view=", view.menu.view)
		return true
	return false
