extends SceneTree
## DIAGNOSTIC: reproduce Jan's report #2 with the input shapes a real device sends.
##
## Jan: "when I click a corpse, all the items are selected straight away and the
## loot window does not appear at all."
##
## The question is therefore not "does a tap open the window" (probe_loot_tap
## answers that for one hand-made event) but "does the SAME tap then TAKE the items
## and close the window in that frame": the tap's tail reaches the freshly-opened
## full-rect panel, and one row tap empties a one-item body, which closes the window.
## Three shapes are tried on a body holding exactly TWO items:
##   A. one finger (index 0) - what a phone sends for a plain tap;
##   B. a second finger (index 1) - the shape main.gd currently demands;
##   C. a mouse click - what a desktop sends.
##
## Run: DISPLAY=:0 godot --path . --rendering-driver opengl3 --resolution 960x540 \
##        --script res://tools/probe_loot_auto_take.gd

const Item := preload("res://scripts/item.gd")

var main: Node
var cam: Camera3D
var _step := 0
var _t := 0.0
var _seen: Array[String] = []


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	cam = main.get_node("Camera")
	cam.set_process(false)


func _process(delta: float) -> bool:
	_t += delta
	match _step:
		0:
			if _t < 1.2:
				return false
			var kill: Node = main._enemies[0]
			for e in main._enemies:
				if e != kill:
					e.global_position = Vector3(0, -50, 0)
			kill.global_position = Vector3(0, 0, -1.6)
			main.get_node("Player").global_position = Vector3(0, 0, 2.2)
			kill.take_damage(99999.0)
			_step = 1
			_t = 0.0
		1:
			if _t < 0.4:
				return false
			_reset("A: ONE FINGER (index 0), press+release on the corpse")
			_finger(true, 0)
			_finger(false, 0)
			_step = 2
			_t = 0.0
		2:
			if _t < 0.5:
				return false
			_report()
			_reset("B: SECOND FINGER (index 1), press+release on the corpse")
			_finger(true, 1)
			_finger(false, 1)
			_step = 3
			_t = 0.0
		3:
			if _t < 0.5:
				return false
			_report()
			_reset("C: MOUSE press+release on the corpse")
			_mouse(true)
			_mouse(false)
			_step = 4
			_t = 0.0
		4:
			if _t < 0.5:
				return false
			_report()
			print("== events pushed into the viewport ==")
			for s in _seen:
				print("   ", s)
			print("LOOT_AUTO_TAKE_DONE")
			return true
	return false


## A body with exactly TWO fresh items, the player in reach, the camera framing it.
func _reset(label: String) -> void:
	print("== %s ==" % label)
	var hud: Node = main.get_node("HUD")
	hud.close_panels()
	main.clear_enemies()
	main.loot.clear()
	main.inventory.clear()
	var body = main.loot.spawn_body(Vector3(0, 0, -1.6), [], null, "Test")
	main.loot._loot[body] = [Item.new("cap", 0, 5), Item.new("ring", 0, 5)]
	var p: Node = main.get_node("Player")
	p.global_position = Vector3(0, 0, 2.2)
	cam.global_position = body.global_position + Vector3(0, 3.4, 4.4)
	cam.look_at(body.global_position + Vector3(0, 0.3, 0), Vector3.UP)
	var at: Vector2 = cam.unproject_position(body.global_position + Vector3(0, 0.3, 0))
	print("   body %s -> screen %s  items=%d  bag=%d  panel_open=%s"
		% [str(body.global_position), str(at), main.loot.items_in(body).size(),
			main.inventory.bag_items().size(), str(hud.panel_open())])


func _corpse_screen() -> Vector2:
	var body = main.loot.bodies()[-1]
	return cam.unproject_position(body.global_position + Vector3(0, 0.3, 0))


func _finger(press: bool, index: int) -> void:
	var ev := InputEventScreenTouch.new()
	ev.pressed = press
	ev.index = index
	ev.position = _corpse_screen()
	_send(ev)


func _mouse(press: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = press
	mb.position = _corpse_screen()
	_send(mb)


func _send(ev: InputEvent) -> void:
	_seen.append("%s idx=%s pressed=%s @ %s" % [ev.get_class(),
		str(ev.get("index")) if ev.get("index") != null else "-",
		str(ev.get("pressed")), str(ev.get("position"))])
	main.get_viewport().push_input(ev, true)


func _report() -> void:
	var hud: Node = main.get_node("HUD")
	var body = main.loot.bodies()[-1]
	var lp: Control = hud.loot_panel
	var names: Array[String] = []
	for it in main.inventory.bag_items():
		names.append(it.display_name())
	print("   panel_open=%s lp.open=%s rows=%d  items_left=%d  bag=%d  bag=%s"
		% [str(hud.panel_open()), str(lp.open), lp._rows.size(),
			main.loot.items_in(body).size(), main.inventory.bag_items().size(),
			str(names)])
