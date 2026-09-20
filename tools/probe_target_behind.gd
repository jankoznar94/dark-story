extends SceneTree
## DIAGNOSTIC ONLY - why does a target acquired BEHIND the player not turn him?
## Prints target / facing / attack state per frame so the reason is read, not guessed.
## Run: godot --headless --path . --script res://tools/probe_target_behind.gd

var main: Node
var player: Node


func _init() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	call_deferred("_run")


func _run() -> void:
	await physics_frame
	player = main.get_node("Player")
	main.clear_enemies()
	Input.action_release("attack")
	player.global_position = Vector3(0, 0, 0)
	player.facing = Vector3(0, 0, -1)
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	player.target = null
	for i in 40:
		await physics_frame

	var back: Node = main._build_enemy("ghoul", Vector3(0, 0, 2.6))
	back.name = "BACK"
	back.aggro_range = 0.0
	back.aggro = false
	back.leash_range = 0.2
	main._enemies.append(back)
	await physics_frame
	print("== one ghoul at (0,0,2.6), player facing -Z, attack held ==")
	print("dist %.2f  range %.2f  cone %.0f  busy=%s" % [
		player.global_position.distance_to(back.global_position), player.target_range,
		player.target_cone_half_deg, player.is_busy()])
	Input.action_press("attack")
	for i in 90:
		await physics_frame
		if i % 6 == 0 or i < 8:
			print("f%-3d state=%-7s busy=%-5s target=%-6s facing.z=%+.3f approaching=%-5s pos.z=%+.2f" % [
				i, player.state_name(), player.is_busy(),
				(player.target.name if player.target != null else "null"),
				player.facing.z, player.auto_approaching, player.global_position.z])
	print("hp of the body behind: %.0f of %.0f" % [back.hp, back.max_hp])
	quit()
