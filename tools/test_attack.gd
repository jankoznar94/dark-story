extends SceneTree
## Headless gameplay test: does a directional swing actually land on the post
## that is physically in front of the player? Proves the melee cone works
## without touching the GPU.
## Run: godot --headless --path . --script res://tools/test_attack.gd

var main: Node
var hits: Array = []


## Distance from `p` to the nearest prop the level builder created. Used to prove a
## test position is clear, so a layout change cannot silently invalidate the test
## by spawning the player inside geometry.
func _nearest_level_prop_distance(node: Node, p: Vector3) -> float:
	var best := INF
	for c in node.get_children():
		if c is StaticBody3D and c.name != "FloorBody":
			var d: float = p.distance_to((c as Node3D).global_position)
			if d < best:
				best = d
	return best


func _init() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	call_deferred("_drive")


func _drive() -> void:
	await physics_frame
	# The pack is spawned by main.gd, not by the scene, but it has to go: this test
	# teleports the player to fixed coordinates and asserts on a direction, and a
	# monster that walked into that arc would be reported as a broken melee cone.
	# tools/test_fight.gd is the test that runs WITH monsters - this one measures
	# the swing itself.
	main.clear_enemies()
	await physics_frame
	var player: Node = main.get_node("Player")
	player.attack_landed.connect(func(kind: String, collider: Node, pt: Vector3) -> void:
		hits.append({"kind": kind, "who": collider.name, "at": pt}))

	# --- case 1: stand in front of the post at (0,0,-3.2), face it, light attack ---
	player.global_position = Vector3(0, 0, -2.0)
	player.facing = Vector3(0, 0, -1)
	player._begin_attack(0)
	for i in 40:
		await physics_frame
	print("CASE1 facing the post -> hits=", hits.size(), " ", hits)
	var case1_ok: bool = hits.size() > 0

	# --- case 2: same distance, but face AWAY. Must miss (no auto-target). ---
	hits.clear()
	player.facing = Vector3(0, 0, 1)
	player._begin_attack(0)
	for i in 40:
		await physics_frame
	print("CASE2 facing away     -> hits=", hits.size(), " ", hits)
	var case2_ok: bool = hits.size() == 0

	# --- case 3: out of range. Must miss. ---
	hits.clear()
	player.global_position = Vector3(0, 0, 2.0)
	player.facing = Vector3(0, 0, -1)
	player._begin_attack(0)
	for i in 40:
		await physics_frame
	print("CASE3 out of range    -> hits=", hits.size(), " ", hits)
	var case3_ok: bool = hits.size() == 0

	# --- case 4: attack locks TRANSLATION (commitment, no move-cancel) ---
	# NOTE: this used to stand at (0, 0, 6.0). Once the level got props, that spot
	# had a rubble_pile 1.71 m away and a pillar at 2.0 m, so the player spawned
	# against geometry and the physics push-out moved them 0.361 m - which this
	# test correctly reported as a move-cancel failure. It was the LEVEL, not the
	# attack code. Stand in the open arena centre instead, and assert it is clear.
	player.global_position = Vector3(0, 0, 0)
	player.facing = Vector3(0, 0, -1)
	player.velocity = Vector3.ZERO
	var near := _nearest_level_prop_distance(main, player.global_position)
	print("CASE4 arena clearance: nearest prop %.2f m" % near)
	var clear_ok: bool = near > 1.6
	player._begin_attack(0)
	Input.action_press("move_right")
	for i in 10:
		await physics_frame
	var moved_during: float = absf(player.global_position.x - 0.0)
	Input.action_release("move_right")
	print("CASE4 movement during attack = %.3f (expect ~0)" % moved_during)
	var case4_ok: bool = moved_during < 0.02 and clear_ok

	# --- case 5: attack takes real time (windup+active+recover), not one frame ---
	player._begin_attack(0)
	var frames: int = 0
	while player.is_busy() and frames < 300:
		await physics_frame
		frames += 1
	print("CASE5 attack locked the player for ", frames, " physics frames = %.2fs" % (frames / 60.0))
	var case5_ok: bool = frames >= 20

	# --- case 6: TURNING during an attack. Jan: "no movement at all is possible,
	# not even turning a direction - it needs to be a bit more flexible." Turning
	# is now allowed at a reduced rate, and the swing fires along `facing` at the
	# ACTIVE frame, so turning during the windup must change where the blade goes.
	player.global_position = Vector3(0, 0, -2.0)
	player.facing = Vector3(0, 0, -1)
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	player._begin_attack(0)
	var facing_before: Vector3 = player.facing
	Input.action_press("move_left")
	for i in 20:
		await physics_frame
	Input.action_release("move_left")
	var turned: float = facing_before.angle_to(player.facing)
	print("CASE6 turned %.1f deg during the swing window (expect > 5, < 90)"
		% rad_to_deg(turned))
	var case6_ok: bool = rad_to_deg(turned) > 5.0 and rad_to_deg(turned) < 90.0

	# --- case 7: turning during an attack is SLOWER than turning while free ---
	# (it is flexibility, not a free spin). The free measurement must wait for the
	# commitment window to END first - otherwise it measures the attacking rate
	# again and the two numbers agree, which is exactly what happened on the first
	# run of this test.
	player.facing = Vector3(0, 0, -1)
	player._begin_attack(0)
	Input.action_press("move_left")
	for i in 20:
		await physics_frame
	Input.action_release("move_left")
	var turned_attacking: float = rad_to_deg(Vector3(0, 0, -1).angle_to(player.facing))
	while player.is_busy():
		await physics_frame
	player.velocity = Vector3.ZERO

	player.facing = Vector3(0, 0, -1)
	Input.action_press("move_left")
	for i in 20:
		await physics_frame
	Input.action_release("move_left")
	var turned_free: float = rad_to_deg(Vector3(0, 0, -1).angle_to(player.facing))
	print("CASE7 turn while attacking %.1f deg vs free %.1f deg" % [turned_attacking, turned_free])
	var case7_ok: bool = turned_attacking < turned_free * 0.85

	print("")
	print("RESULT case1_hits=%s case2_miss_when_turned=%s case3_miss_out_of_range=%s case4_no_move_cancel=%s case5_commitment=%s case6_turn_allowed=%s case7_turn_slower=%s"
		% [case1_ok, case2_ok, case3_ok, case4_ok, case5_ok, case6_ok, case7_ok])
	print("ALL_PASS=", case1_ok and case2_ok and case3_ok and case4_ok and case5_ok and case6_ok and case7_ok)
	quit()
