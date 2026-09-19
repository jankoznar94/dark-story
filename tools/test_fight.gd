extends SceneTree
## Headless fight test: does the one test enemy actually fight?
## Run: godot --headless --path . --script res://tools/test_fight.gd
##
## What is checked, in order:
##   1. the enemy model loaded and exposes the clips it needs
##   2. it notices the player and closes the distance
##   3. in reach it attacks, and the attack damages the player
##   4. the player's directional swing damages the enemy
##   5. the enemy dies, plays its death clip, and then stops acting
##   6. the HUD bars follow both health pools

var main: Node
var fails: Array[String] = []
var checks: int = 0


func _ok(label: String, cond: bool, detail: String = "") -> void:
	checks += 1
	if cond:
		print("  OK   ", label, ("  " + detail) if detail else "")
	else:
		print("  FAIL ", label, "  ", detail)
		fails.append(label)


func _init() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	call_deferred("_run")


## Distance from `p` to the nearest prop the level builder created. Used to prove
## a test position is clear, so a layout change cannot silently invalidate the test
## by putting a body inside geometry.
func _nearest_prop(p: Vector3) -> float:
	var best := INF
	for c in main.get_children():
		if c is StaticBody3D and c.name != "FloorBody":
			var d: float = p.distance_to((c as Node3D).global_position)
			if d < best:
				best = d
	return best


func _run() -> void:
	await physics_frame
	await physics_frame
	var player: Node = main.get_node("Player")
	var enemy: Node = main.get_node_or_null("Enemy")

	print("== 1. the enemy exists and is armed with its animations ==")
	_ok("an Enemy node is in the scene", enemy != null)
	if enemy == null:
		_finish()
		return
	_ok("enemy.glb produced an AnimationPlayer", enemy.anim != null)
	_ok("enemy has a name and a level", enemy.monster_name.length() > 0,
		"%s lv %d" % [enemy.monster_name, enemy.level])
	_ok("enemy has real health", enemy.max_hp > 0.0 and enemy.hp == enemy.max_hp,
		"%.0f hp" % enemy.hp)
	if enemy.anim != null:
		var clips: PackedStringArray = enemy.anim.get_animation_list()
		_ok("enemy model carries its clips", clips.size() > 5, "%d clips" % clips.size())
		for want in [enemy.CLIP_ATTACK, enemy.CLIP_ATTACK_ALT, enemy.CLIP_WALK,
					 enemy.CLIP_HIT, enemy.CLIP_DEATH]:
			_ok("clip present: %s" % want, clips.has(want))

	print("== 2. the enemy notices the player and closes in ==")
	# Stand inside its aggro range but out of its reach, so only walking can bring
	# it into contact. Both spots are asserted clear of level geometry FIRST: the
	# first version of this test placed the enemy against the ruin_arch by accident
	# and then reported a broken chase that was really a wall.
	player.global_position = Vector3(4.6, 0, -9.0)
	player.hp = player.max_hp
	enemy.global_position = Vector3(3.4, 0, -5.6)
	enemy.facing = Vector3(0, 0, 1)
	enemy.velocity = Vector3.ZERO
	await physics_frame
	var clear_enemy: float = _nearest_prop(enemy.global_position)
	var clear_player: float = _nearest_prop(player.global_position)
	# The bar is 1.2 m, not more: the capsule radius is 0.38 m, so 1.2 m leaves
	# 0.8 m of room. Measured here: 1.41 m to the north wall_segment, and the enemy
	# walks freely at that distance. The failure this guards against was 0.36 m
	# (wedged inside the ruin_arch), where it could not move at all.
	_ok("enemy spawn is clear of level geometry", clear_enemy > 1.2,
		"nearest prop %.2f m" % clear_enemy)
	_ok("test position of the player is clear", clear_player > 1.0,
		"nearest prop %.2f m" % clear_player)
	var d0: float = enemy.global_position.distance_to(player.global_position)
	for i in 60:
		await physics_frame
	var d1: float = enemy.global_position.distance_to(player.global_position)
	_ok("enemy aggroed", enemy.aggro)
	_ok("enemy walked toward the player", d1 < d0 - 0.2,
		"%.2f m -> %.2f m" % [d0, d1])

	print("== 3. in reach it attacks, and the player takes damage ==")
	# park the player right in front of it and let the fight run
	player.global_position = enemy.global_position + Vector3(0, 0, 1.05)
	var hp0: float = player.hp
	var saw_attack := false
	for i in 420:
		await physics_frame
		if enemy.state_name() != "idle":
			saw_attack = true
		if player.hp < hp0:
			break
	_ok("enemy ran its attack state machine", saw_attack, "state was seen non-idle")
	_ok("enemy attack damaged the player", player.hp < hp0,
		"%.0f -> %.0f hp" % [hp0, player.hp])
	_ok("damage stayed inside the declared range",
		(hp0 - player.hp) >= enemy.damage_min - 0.01 and
		(hp0 - player.hp) <= enemy.damage_max + 0.01,
		"dealt %.1f (range %.0f-%.0f)" % [hp0 - player.hp, enemy.damage_min, enemy.damage_max])

	print("== 4. the player's directional swing damages the enemy ==")
	var ehp0: float = enemy.hp
	player.global_position = enemy.global_position + Vector3(0, 0, 1.2)
	player.facing = Vector3(0, 0, -1)
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	player._begin_attack(0)
	while player.is_busy():
		await physics_frame
	_ok("swing landed and took enemy health", enemy.hp < ehp0,
		"%.0f -> %.0f" % [ehp0, enemy.hp])

	print("== 5. it dies, plays its death clip, and stops acting ==")
	var guard := 0
	while not enemy.is_dead() and guard < 200:
		enemy.take_hit(0)
		guard += 1
	_ok("enemy dies after enough hits", enemy.is_dead(), "%d hits" % guard)
	_ok("death is visible on the clip", enemy.current_clip() == enemy.CLIP_DEATH,
		enemy.current_clip())
	var pos_at_death: Vector3 = enemy.global_position
	player.global_position = enemy.global_position + Vector3(0, 0, 1.0)
	var php0: float = player.hp
	for i in 90:
		await physics_frame
	_ok("a dead enemy stops moving", enemy.global_position.distance_to(pos_at_death) < 0.05,
		"moved %.3f m" % enemy.global_position.distance_to(pos_at_death))
	_ok("a dead enemy deals no more damage", absf(player.hp - php0) < 0.001)
	_ok("a dead enemy stays dead", enemy.hp == 0.0 and enemy.state_name() == "idle",
		"%.0f hp, state %s" % [enemy.hp, enemy.state_name()])

	print("== 6. the HUD follows both health pools ==")
	main._process(0.016)
	var hud: Node = main.get_node("HUD")
	_ok("enemy bar shows the enemy name", hud.enemy_label.text.contains(enemy.monster_name),
		hud.enemy_label.text)
	_ok("enemy bar shows DEAD", hud.enemy_label.text.contains("DEAD"), hud.enemy_label.text)
	_ok("player bar shows HP", hud.hp_label.text.contains("HP"), hud.hp_label.text)
	_ok("player bar is filled somewhere between 0 and 1",
		hud.hp_fill.size.x > 0.0 and hud.enemy_fill.size.x == 0.0,
		"player %.1f px, enemy %.1f px" % [hud.hp_fill.size.x, hud.enemy_fill.size.x])

	_finish()


func _finish() -> void:
	print("")
	print("checks executed: ", checks)
	if fails.is_empty() and checks >= 20:
		print("FIGHT_ALL_PASS=true")
	else:
		for f in fails:
			print("FAIL: ", f)
		if checks < 20:
			print("FAIL: only %d checks ran - not everything was exercised" % checks)
		print("FIGHT_ALL_PASS=false")
	quit()
