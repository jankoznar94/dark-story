extends SceneTree
## Check that the walk clip is re-timed to the ground speed.
## The animation must cover exactly as much ground per second as the character
## actually moves, i.e. speed_scale * WALK_GROUND_SPEED == ground speed.

func _init() -> void:
	# instantiate the real player scene so hero.gd's _ready() runs with a parent
	var ps: PackedScene = load("res://scenes/player.tscn")
	var player: Node = ps.instantiate()
	root.add_child(player)
	var h: Node3D = player.get_node("Hero")
	await process_frame
	await process_frame
	if h.anim == null:
		print("NO ANIMATION PLAYER - abort")
		quit()
		return
	var ok := true
	for gs in [0.963, 1.5, 2.6]:
		h.walk_speed_scale = gs
		h.play_walk()
		var got: float = h.anim.speed_scale
		var implied: float = got * h.WALK_GROUND_SPEED
		var err: float = abs(implied - gs)
		print("ground %.3f m/s -> speed_scale %.3f -> implied %.3f m/s | error %.4f | %s"
			% [gs, got, implied, err, "OK" if err < 0.001 else "FAIL"])
		if err >= 0.001:
			ok = false
	# idle must not be retimed
	h.play_idle()
	print("idle speed_scale %.3f (must be 1.0) | %s"
		% [h.anim.speed_scale, "OK" if abs(h.anim.speed_scale - 1.0) < 1e-6 else "FAIL"])
	print("WALK_RETIME_ALL_PASS=%s" % str(ok))
	quit()
