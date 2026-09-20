extends SceneTree
## DRIVE THE REAL GAME LIKE A PLAYER and report what happens, in one headless run.
##
## This is the acceptance probe for Jan's report: it stands the hero in front of a
## monster, kills it, taps the corpse, taps an item row, and prints the bag and the
## body before/after. Every step goes through the PRODUCTION entry points
## (`loot.open_at_screen`, `panel._gui_input`) rather than poking the model, because
## what broke was the path from a tap to the model.
##
## Run: godot --headless --path . --script res://tools/probe_corpse_flow.gd

var main: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	var player: Node = main.get_node("Player")
	var loot: Node = main.loot
	var hud: Node = main.get_node("HUD")
	var panel: Control = hud.loot_panel
	var cam: Camera3D = main.get_node("Camera")

	# a monster in front of the hero, the rest of the pack parked (a body in the ray
	# is the classic false result in a tap measurement)
	loot.clear()
	var kill: Node = null
	for e in main._enemies:
		if kill == null and e.monster_name == "Ghoul":
			kill = e
		else:
			e.global_position = Vector3(e.global_position.x, 0.0,
				e.global_position.z + 200.0)
	kill.global_position = Vector3(0, 0, -1.5)
	player.global_position = Vector3(0, 0, 0)
	for i in 3:
		await physics_frame

	# --- KILL IT through the death path (the hero's swing timing is covered by
	# test_attack; what is under test here is what the corpse BECOMES)
	kill.take_damage(99999.0)
	for i in 8:
		await physics_frame
	print("1. dead: %s (hp %.0f), death clip frozen at speed_scale %.2f"
		% [str(kill.is_dead()), kill.hp, kill.anim.speed_scale if kill.anim else -1.0])
	print("   corpse node: %s  parent=%s"
		% [str(loot.bodies()[0].name), str(loot.bodies()[0].get_parent().name)])
	print("   stray Body_ nodes beside it: %d"
		% main.get_children().filter(func(c): return str(c.name).begins_with("Body_")).size())
	print("   items inside: %d" % loot.drop_count())

	# --- TAP THE CORPSE. Its position on screen via the real camera.
	var body = loot.bodies()[0]
	var at: Vector2 = cam.unproject_position(body.global_position + Vector3(0, 0.3, 0))
	player.global_position = body.global_position + Vector3(0, 0, 1.2)
	for i in 2:
		await physics_frame
	var got: Variant = loot.open_at_screen(at, player.global_position)
	print("2. tap on the corpse at %s -> %s items offered"
		% [str(at), str((got as Array).size() if got != null else -1)])

	# --- OPEN THE WINDOW, then TAP A ROW (this is what did not work)
	hud.open_loot_for(body)
	await process_frame
	var bag_before: int = main.inventory.bag_items().size()
	print("3. window open=%s rows=%d panel size=%s"
		% [str(panel.open), panel._rows.size(), str(panel.size)])
	panel.layout_now()
	var row: Rect2 = panel._rows[0]
	var ev := InputEventScreenTouch.new()
	ev.pressed = true
	ev.index = 1
	ev.position = row.position + row.size * 0.5
	panel._gui_input(ev)
	await process_frame
	print("4. tapped row 0 -> bag %d -> %d, items left in the corpse: %d"
		% [bag_before, main.inventory.bag_items().size(), loot.items_in(body).size()])

	# --- AND "TAKE EVERYTHING"
	var ev2 := InputEventScreenTouch.new()
	ev2.pressed = true
	ev2.index = 1
	ev2.position = panel._all_rect.position + panel._all_rect.size * 0.5
	panel._gui_input(ev2)
	await process_frame
	print("5. 'take all' -> bag %d, corpse empty=%s, window closed=%s"
		% [main.inventory.bag_items().size(), str(loot.items_in(body).is_empty()),
			str(not panel.open)])

	# --- IS THE ENGINE STILL RUNNING (the 'locks up' half)?
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	for i in 90:
		await process_frame
	print("6. engine alive after the interaction: %d frames in %d ms"
		% [Engine.get_frames_drawn() - f0, Time.get_ticks_msec() - t0])
	print("PROBE_DONE")
	quit()
