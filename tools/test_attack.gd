extends SceneTree
## Headless gameplay test: does a directional swing actually land on the post
## that is physically in front of the player? Proves the melee cone works
## without touching the GPU.
## Run: godot --headless --path . --script res://tools/test_attack.gd

var main: Node
var hits: Array = []


func _init() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	call_deferred("_drive")


func _drive() -> void:
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

	# --- case 4: attack must lock movement (commitment, not move-cancel) ---
	player.global_position = Vector3(0, 0, 6.0)
	player.facing = Vector3(0, 0, -1)
	player.velocity = Vector3.ZERO
	player._begin_attack(0)
	Input.action_press("move_right")
	for i in 10:
		await physics_frame
	var moved_during: float = absf(player.global_position.x - 0.0)
	Input.action_release("move_right")
	print("CASE4 movement during attack = %.3f (expect ~0)" % moved_during)
	var case4_ok: bool = moved_during < 0.02

	# --- case 5: attack takes real time (windup+active+recover), not one frame ---
	player._begin_attack(0)
	var frames: int = 0
	while player.is_busy() and frames < 300:
		await physics_frame
		frames += 1
	print("CASE5 attack locked the player for ", frames, " physics frames = %.2fs" % (frames / 60.0))
	var case5_ok: bool = frames >= 20

	print("")
	print("RESULT case1_hits=%s case2_miss_when_turned=%s case3_miss_out_of_range=%s case4_no_move_cancel=%s case5_commitment=%s"
		% [case1_ok, case2_ok, case3_ok, case4_ok, case5_ok])
	print("ALL_PASS=", case1_ok and case2_ok and case3_ok and case4_ok and case5_ok)
	quit()
