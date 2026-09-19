extends SceneTree
## Headless test for the touch HUD.
## Run: godot --headless --path . --script res://tools/test_controls.gd
##
## Three things are checked:
##   1. the four circles are actually DRAWN (not just text) - a flat Button
##      renders no stylebox at all, which was the original bug
##   2. the geometry is a real d-pad cross at every landscape resolution
##   3. the input semantics: hold attack = keep attacking, release = stop

const Hud := preload("res://scripts/hud.gd")

const DEVICES := [
	["landscape phone 1080p", Vector2(1920, 1080)],
	["modern phone 2400x1080", Vector2(2400, 1080)],
	["tall phone 2340x1080", Vector2(2340, 1080)],
	["small phone 16:9", Vector2(1280, 720)],
	["tablet 16:10", Vector2(2560, 1600)],
]

var fails: Array[String] = []
var checks_run: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	# This test drives the HUD through Input actions, so it must not be fighting a
	# pack at the same time - a monster attacking the player mid-assertion changes
	# the state the assertions read. tools/test_fight.gd covers fighting monsters.
	main.clear_enemies()

	var hud: Node = main.get_node("HUD")

	_test_circles(hud)
	_test_run_button(hud)
	await _test_layout(hud)
	await _test_hold_to_attack(main, hud)
	await _test_run_latch(main, hud)

	print("")
	print("checks executed: ", checks_run)
	if fails.is_empty() and checks_run >= 40:
		print("CONTROLS_ALL_PASS=true")
	else:
		for f in fails:
			print("FAIL: ", f)
		if checks_run < 40:
			print("FAIL: only %d checks ran - not everything was exercised" % checks_run)
		print("CONTROLS_ALL_PASS=false")
	quit()


## The RUN button is a LATCH (tap = run, tap again = walk), because the joystick
## already owns the thumb and a hold-to-run button could never be pressed at the
## same time as it.
func _test_run_button(hud: Node) -> void:
	print("== the run button is a latch, not a hold ==")
	_ok("run button exists", hud.run_button != null)
	_ok("run button is a toggle", hud.run_button.toggle_mode)
	_ok("run starts OFF", hud.run_latched == false)
	_ok("run button is not flat (it draws a circle)",
		hud.run_button.flat == false)
	_ok("run button has a label", hud.run_button.text.length() > 0, hud.run_button.text)
	_ok("run has no hover effect",
		hud.run_button.get_theme_stylebox("hover") == hud.run_button.get_theme_stylebox("normal"))


func _test_run_latch(main: Node, hud: Node) -> void:
	print("== run latch reaches the player, and running is faster than walking ==")
	var player: Node = main.get_node("Player")
	var idle_in: Vector2 = Vector2(0.0, 0.0)
	var walk_ok: bool = absf(player.current_speed(Vector2(0, -1.0)) - player.walk_speed) < 0.01
	_ok("stick alone = walk speed", walk_ok)

	hud.run_button.button_pressed = true
	hud.run_button.toggled.emit(true)
	await process_frame
	await process_frame
	_ok("latch set by the button", hud.run_latched)
	_ok("RUN reaches the player through main.gd", player.wants_run(Vector2(0, -1.0)))
	_ok("running is faster than walking",
		player.current_speed(Vector2(0, -1.0)) > player.walk_speed,
		"walk %.1f -> run %.1f" % [player.walk_speed, player.run_speed])

	hud.run_button.button_pressed = false
	hud.run_button.toggled.emit(false)
	await process_frame
	await process_frame
	_ok("latch cleared by the button", not hud.run_latched)
	_ok("cleared latch = walk again", not player.wants_run(idle_in))

	# the `run` ACTION is the keyboard/pad path and must work on its own
	Input.action_press("run")
	_ok("run action alone = run (keyboard/pad path)",
		player.wants_run(idle_in) and absf(player.current_speed(idle_in) - player.run_speed) < 0.01)
	Input.action_release("run")
	await process_frame
	_ok("released run action = walk again", not player.wants_run(idle_in))


func _ok(label: String, cond: bool, detail: String = "") -> void:
	checks_run += 1
	if cond:
		print("  OK   ", label, ("  " + detail) if detail else "")
	else:
		print("  FAIL ", label, "  ", detail)
		fails.append(label)


func _test_circles(hud: Node) -> void:
	print("== the circles are actually drawn ==")
	for slot in Hud.SLOTS:
		var b: Button = hud._buttons[slot]
		_ok("%s: not flat (flat=true draws nothing)" % slot, b.flat == false)
		var idle: StyleBox = b.get_theme_stylebox("normal")
		_ok("%s: has a normal stylebox" % slot, idle is StyleBoxFlat)
		if idle is StyleBoxFlat:
			var sb: StyleBoxFlat = idle
			_ok("%s: stylebox is filled, not transparent" % slot, sb.bg_color.a > 0.5,
				"alpha=%.2f" % sb.bg_color.a)
			_ok("%s: has a visible border" % slot, sb.border_width_top >= 2,
				"%d px" % sb.border_width_top)
			var col: Color = sb.border_color
			_ok("%s: border is bright enough to read" % slot,
				maxf(col.r, maxf(col.g, col.b)) > 0.35,
				"max channel %.2f" % maxf(col.r, maxf(col.g, col.b)))
			_ok("%s: corner radius makes it round, not a square" % slot,
				sb.corner_radius_top_left >= 10)
		# a distinct pressed look so a tap has feedback
		var pr: StyleBox = b.get_theme_stylebox("pressed")
		if pr is StyleBoxFlat and idle is StyleBoxFlat:
			_ok("%s: pressed look differs from idle" % slot,
				(pr as StyleBoxFlat).bg_color != (idle as StyleBoxFlat).bg_color)
		# no hover effect, per the art rules
		_ok("%s: hover is identical to normal" % slot,
			b.get_theme_stylebox("hover") == b.get_theme_stylebox("normal"))
		_ok("%s: has a label" % slot, b.text.length() > 0, b.text)


func _test_layout(hud: Node) -> void:
	for device in DEVICES:
		var name: String = device[0]
		var vs: Vector2 = device[1]
		hud._layout(vs)
		await process_frame

		print("== %s  (%d x %d) ==" % [name, int(vs.x), int(vs.y)])

		var pos: Dictionary = {}
		var sizes: Array = []
		for s in Hud.SLOTS:
			var btn: Button = hud._buttons[s]
			pos[s] = btn.position + btn.size * 0.5
			sizes.append(btn.size)

		_ok("%s: all buttons the same size" % name,
			absf(sizes[0].x - sizes[1].x) < 0.01 and absf(sizes[0].x - sizes[2].x) < 0.01,
			str(sizes[0]))
		_ok("%s: round, not oval" % name, absf(sizes[0].x - sizes[0].y) < 0.01)

		var cx: float = (pos["left"].x + pos["right"].x) * 0.5
		var cy: float = (pos["up"].y + pos["down"].y) * 0.5
		_ok("%s: forms a d-pad cross" % name,
			absf(pos["up"].x - cx) < 0.01 and absf(pos["down"].x - cx) < 0.01 and
			absf(pos["left"].y - cy) < 0.01 and absf(pos["right"].y - cy) < 0.01,
			"up=(%.0f,%.0f) down=(%.0f,%.0f) left=(%.0f,%.0f) right=(%.0f,%.0f)"
			% [pos["up"].x, pos["up"].y, pos["down"].x, pos["down"].y,
			   pos["left"].x, pos["left"].y, pos["right"].x, pos["right"].y])
		_ok("%s: attack is the bottom button" % name, pos["down"].y > pos["up"].y)
		_ok("%s: in the lower-right thumb zone" % name,
			pos["left"].x > vs.x * 0.55 and pos["up"].y > vs.y * 0.45)
		_ok("%s: nothing in the screen centre" % name, pos["up"].x > vs.x * 0.6)
		_ok("%s: buttons >= 60 px across" % name, sizes[0].x >= 60.0, "%.0f px" % sizes[0].x)

		var pair := ""
		for a in range(Hud.SLOTS.size()):
			for b in range(a + 1, Hud.SLOTS.size()):
				var ra := Rect2(hud._buttons[Hud.SLOTS[a]].position, hud._buttons[Hud.SLOTS[a]].size)
				var rb := Rect2(hud._buttons[Hud.SLOTS[b]].position, hud._buttons[Hud.SLOTS[b]].size)
				if ra.intersects(rb):
					pair = "%s/%s" % [Hud.SLOTS[a], Hud.SLOTS[b]]
		_ok("%s: no two buttons overlap" % name, pair == "", pair)

		var off := ""
		for s in Hud.SLOTS:
			var rr := Rect2(hud._buttons[s].position, hud._buttons[s].size)
			if rr.position.x < 0.0 or rr.position.y < 0.0 or rr.end.x > vs.x or rr.end.y > vs.y:
				off += "%s " % s
		_ok("%s: every button fully on screen" % name, off == "", off)

		var joy: Control = hud.joystick
		_ok("%s: joystick lower-left" % name, joy.position.x < vs.x * 0.3)
		_ok("%s: joystick clear of the buttons" % name,
			joy.position.x + joy.size.x < pos["left"].x - sizes[0].x * 0.5)

		# the run button sits in the MIDDLE of the cross and must not touch it
		var run: Button = hud.run_button
		var rc: Vector2 = run.position + run.size * 0.5
		_ok("%s: run button is centred in the cross" % name,
			absf(rc.x - cx) < 1.0 and absf(rc.y - cy) < 1.0,
			"run=(%.0f,%.0f) cross=(%.0f,%.0f)" % [rc.x, rc.y, cx, cy])
		_ok("%s: run button is the same size as the others" % name,
			absf(run.size.x - sizes[0].x) < 0.01, str(run.size))
		var clash := ""
		for s in Hud.SLOTS:
			var rr := Rect2(run.position, run.size)
			var rb2 := Rect2(hud._buttons[s].position, hud._buttons[s].size)
			if rr.intersects(rb2):
				clash += "%s " % s
		_ok("%s: run button does not overlap the four actions" % name, clash == "", clash)
		var run_off := Rect2(run.position, run.size)
		_ok("%s: run button fully on screen" % name,
			run_off.position.x >= 0.0 and run_off.position.y >= 0.0 and
			run_off.end.x <= vs.x and run_off.end.y <= vs.y)

		# vitals bars: both on screen, not overlapping, player on the left
		var pb: Control = hud.hp_fill
		var eb: Control = hud.enemy_fill
		_ok("%s: HP bars visible" % name, pb.visible and eb.visible)
		_ok("%s: player bar left, enemy bar right" % name,
			pb.global_position.x < vs.x * 0.5 and eb.global_position.x > vs.x * 0.4,
			"p %.0f e %.0f" % [pb.global_position.x, eb.global_position.x])
		_ok("%s: bars do not overlap" % name,
			not Rect2(pb.global_position, pb.size).intersects(Rect2(eb.global_position, eb.size)))
		_ok("%s: bars clear of the right-hand pad" % name,
			eb.global_position.x + eb.size.x <= pos["right"].x + sizes[0].x * 0.5)


func _test_hold_to_attack(main: Node, hud: Node) -> void:
	print("== hold attack = keep attacking, release = stop ==")
	main._hits.clear()
	var player: Node = main.get_node("Player")
	# stand right in front of the post at (0,0,-3.2)
	player.global_position = Vector3(0, 0, -2.0)
	player.facing = Vector3(0, 0, -1)

	var btn: Button = hud._buttons["down"]
	_ok("bottom button is bound to attack", btn.text == "Útok", btn.text)

	btn.button_down.emit()
	var pressed: bool = Input.is_action_pressed("attack")
	_ok("holding sets the attack action", pressed)

	# run long enough for several full swings
	for i in 140:
		await physics_frame
	var swings: int = main._hits.size()
	_ok("holding produced repeated attacks", swings >= 2, "%d hits in ~2.3 s" % swings)

	btn.button_up.emit()
	_ok("releasing clears the attack action", not Input.is_action_pressed("attack"))

	# After the release no NEW swing may start. One attack that was already in
	# flight when the button was released still lands - that is correct, it is the
	# same commitment as anywhere else. So drain the in-flight attack first, then
	# assert nothing new begins. (Asserting straight after the release counted the
	# in-flight hit as a leak; measured: 2 -> 3, and the 3rd was the one already
	# running at the moment of release.)
	var settled: bool = false
	for i in 120:
		if not player.is_busy():
			settled = true
			break
		await physics_frame
	_ok("in-flight attack finished after release", settled)
	var after_release: int = main._hits.size()
	for i in 60:
		await physics_frame
	_ok("no further attacks after release", main._hits.size() == after_release,
		"%d -> %d" % [after_release, main._hits.size()])

	# the attack must still be a commitment while held
	hud._buttons["down"].button_down.emit()
	await physics_frame
	player.velocity = Vector3.ZERO
	var start_x: float = player.global_position.x
	Input.action_press("move_right")
	for i in 12:
		await physics_frame
	var moved: float = absf(player.global_position.x - start_x)
	Input.action_release("move_right")
	hud._buttons["down"].button_up.emit()
	_ok("still no move-cancel while holding", moved < 0.02, "moved %.3f" % moved)
