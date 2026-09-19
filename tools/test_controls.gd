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
	await _test_constant_run_speed(main)

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


## How far a body travelling at `v` can get from a standstill in `t` seconds, given
## the player's own accel. The "did he move" bar has to be derived from this rather
## than picked: peak speed is reached after only 0.314 s of the 0.7 s window, so the
## AVERAGE is ~0.77 x top speed and a bar set at the peak value fails a run that is
## working perfectly. Blocked reads 0.000 m, so a bar at 60 % of the physical
## maximum still separates the two unambiguously.
func _travel_bar(player: Node, v: float, t: float) -> float:
	var a: float = player.accel
	var to_top: float = v / a
	var dist: float = 0.5 * a * to_top * to_top
	if t > to_top:
		dist += v * (t - to_top)
	return dist * 0.6


func _ok(label: String, cond: bool, detail: String = "") -> void:
	checks_run += 1
	if cond:
		print("  OK   ", label, ("  " + detail) if detail else "")
	else:
		print("  FAIL ", label, "  ", detail)
		fails.append(label)


## Jan's report, TWICE. The first time: "the run speed seems to increase the more I
## pull the stick to the side, but the run speed should be constant." The answer
## then was that `Input.get_vector` normalises, and the test pressed every action
## with `Input.action_press(axis, 1.0)` - a synthetic FULL deflection.
##
## The second report says the same thing again and is right: "when my finger is only
## slightly outside the circle he runs slowly, when it is far outside he runs at full
## speed." The old test could not see it because it only ever measured a full
## deflection, i.e. the one case that already worked. Read Godot's
## `VirtualJoystick::_update_joystick()`: above the dead zone it emits
## `direction * inverse_lerp(deadzone*R, R, length)`, a CONTINUOUS 0..1 strength, and
## `Input.get_vector` returns that graded vector unchanged (it normalises only above
## length 1). So the stick really was a throttle.
##
## This test therefore asserts the opposite for the stick, and it does so through the
## real mechanism rather than by poking a property:
##   * a GRADED keyboard press (a device reporting partial strength, e.g. an analogue
##     gamepad axis) must still produce a graded speed - that is the device being
##     honest, and a blanket "force magnitude 1.0" fix would break it;
##   * the SAME graded deflection with the stick flagged must come out at FULL speed
##     and the top speed must not vary with the deflection.
## The regression that matters is the last one: the spread across 0.30 / 0.60 / 1.0
## deflections was 0.30 x run_speed before the fix.
func _test_constant_run_speed(main: Node) -> void:
	print("== run speed is CONSTANT, whatever the stick deflection ==")
	var player: Node = main.get_node("Player")
	var hud: Node = main.get_node("HUD")
	var axes := ["move_up", "move_down", "move_left", "move_right"]

	# DRAIN FIRST. The previous sub-test leaves an attack in flight, and translation
	# is blocked for the whole commitment window - measuring then reads 0.000 m/s and
	# the failure lands on this test instead of on nothing at all. (It did exactly
	# that on the first run: "run speed 0.000 m/s vs 4.400".)
	Input.action_release("attack")
	Input.action_release("skill_1")
	for i in 300:
		if not player.is_busy():
			break
		await physics_frame
	_ok("no attack in flight before measuring run speed", not player.is_busy(),
		"state %s" % player.state_name())

	# CLEAR GROUND. The attack sub-test leaves the player standing right against the
	# post it swung at, and a run of 90 frames drives him into the post 3.2 m away -
	# the measurement then reads 0.000 m/s, which is a collision and not a movement
	# bug. So each deflection starts from the arena centre and runs only ~0.7 s, and
	# the test ASSERTS that he actually travelled rather than being blocked.
	var start := Vector3(0, 0, 0)

	var deflections := [0.30, 0.60, 0.90, 1.0]
	var stick_speeds: Array = []
	var key_speeds: Array = []

	# --- the keyboard/gamepad path: the device's own magnitude must be respected ---
	print("  -- a graded press with NO stick flagged (keyboard / analogue pad) --")
	for f in deflections:
		for a in axes:
			Input.action_release(a)
		Input.action_press("move_up", f)
		await physics_frame
		var iv: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var want: Vector2 = player.call("_move_input")
		hud.stick_active = false
		player.global_position = start
		player.velocity = Vector3.ZERO
		player.set_run(true)
		var peak := 0.0
		for i in 42:
			await physics_frame
			peak = maxf(peak, player.velocity.length())
		var travelled: float = player.global_position.distance_to(start)
		# The expected speed follows the ACTUAL input length, not the press strength:
		# `Input.get_vector` applies each action's own deadzone (`input/<action>/
		# deadzone` is 0.2) and rescales, so a 0.30 press arrives as 0.125. Asserting
		# against `f` here would be asserting the wrong quantity.
		var expected: float = player.run_speed * iv.length()
		_ok("pad %.2f: input stays graded (%.3f) and speed follows it" % [f, iv.length()],
			absf(want.length() - iv.length()) < 0.02 and absf(peak - expected) < 0.15,
			"input %.3f, top speed %.3f m/s vs wanted %.3f" % [want.length(), peak, expected])
		# the bar scales with the distance that deflection can actually cover in
		# 0.7 s: a flat 0.3 m bar fails a legitimately slow press (0.125 x 3.05
		# covers 0.27 m) and would be asserting the wrong thing
		_ok("pad %.2f: the character actually moved (not blocked)" % f,
			travelled > _travel_bar(player, expected, 0.7),
			"travelled %.2f m, bar %.2f m"
			% [travelled, _travel_bar(player, expected, 0.7)])
		key_speeds.append(peak)
		player.set_run(false)
	for a in axes:
		Input.action_release(a)

	# --- the VIRTUAL STICK: a graded deflection must NOT grade the speed ---
	print("  -- the same graded deflection with the stick flagged (the fix) --")
	for f in deflections:
		for a in axes:
			Input.action_release(a)
		Input.action_press("move_up", f)
		await physics_frame
		var iv: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		_ok("stick %.2f: the joystick really does report a graded strength" % f,
			iv.length() > 0.05 and iv.length() < 1.0001,
			"get_vector len %.4f" % iv.length())
		# NOTE: flag the HUD, not the player. main.gd pushes `hud.stick_active` into
		# the player EVERY frame, so a flag set directly on the player is reverted
		# before the first physics frame of the measurement - which is how the first
		# run of this test still measured a graded speed after the fix.
		# Set it on the HUD (main.gd re-pushes it every frame) AND on the player, so
		# the very first iteration cannot read a stale value before main.gd's
		# _process has run. main.gd then keeps them in sync from here on.
		hud.stick_active = true
		player.set_stick_active(true)
		await process_frame
		var want: Vector2 = player.call("_move_input")
		_ok("stick %.2f: the player reads it as a DIRECTION (full magnitude)" % f,
			absf(want.length() - player.touch_move_magnitude) < 0.001,
			"_move_input len %.4f" % want.length())
		player.global_position = start
		player.velocity = Vector3.ZERO
		player.set_run(true)
		var peak := 0.0
		for i in 42:
			await physics_frame
			peak = maxf(peak, player.velocity.length())
		var travelled: float = player.global_position.distance_to(start)
		_ok("stick %.2f: top speed is run_speed" % f,
			absf(peak - player.run_speed) < 0.05,
			"%.3f m/s vs %.3f" % [peak, player.run_speed])
		_ok("stick %.2f: the character actually moved (not blocked)" % f,
			travelled > _travel_bar(player, player.run_speed, 0.7),
			"travelled %.2f m, bar %.2f m"
			% [travelled, _travel_bar(player, player.run_speed, 0.7)])
		stick_speeds.append(peak)
		player.set_run(false)
	for a in axes:
		Input.action_release(a)
	hud.stick_active = false

	# --- the regression itself, as ONE number ---
	var spread: float = 0.0
	for s in stick_speeds:
		spread = maxf(spread, absf(s - stick_speeds[0]))
	_ok("run speed does NOT vary with stick deflection",
		spread < 0.05,
		"spread %.3f m/s over %d deflections (was 0.30 x run_speed = %.2f m/s before the fix)"
		% [spread, stick_speeds.size(), 0.30 * player.run_speed])
	var key_spread: float = 0.0
	for s in key_speeds:
		key_spread = maxf(key_spread, absf(s - key_speeds[0]))
	_ok("...but a GRADED device input still grades the speed (not force-1.0)",
		key_spread > 0.5,
		"spread %.3f m/s across the same deflections with no stick flagged" % key_spread)

	# --- and the HUD must actually track the joystick ---
	print("  -- the HUD knows when the stick is held --")
	var joy: VirtualJoystick = hud.joystick
	_ok("the HUD listens to the joystick's pressed signal",
		joy.pressed.get_connections().size() >= 1)
	_ok("the HUD listens to the joystick's released signal",
		joy.released.get_connections().size() >= 1)
	_ok("the HUD listens to flick_canceled (a flicked stick must not stick)",
		joy.flick_canceled.get_connections().size() >= 1)
	hud.stick_active = false
	joy.pressed.emit()
	await process_frame
	_ok("holding the stick sets the flag", hud.stick_active)
	await process_frame
	_ok("main.gd pushes the flag into the player", player.stick_active)
	joy.released.emit(Vector2.ZERO)
	await process_frame
	_ok("releasing the stick clears the flag", not hud.stick_active)


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
