extends SceneTree
## Headless test for AUTO-TARGET: does a held attack pick the monster the player is
## facing and walk him in to it?
## Run: godot --headless --path . --script res://tools/test_autotarget.gd
##
## Jan's brief was the D2-with-a-gamepad behaviour: "the player does not swing into
## thin air, he first walks to a target, and the game picks the target by direction
## and distance". Every rule of that is a measurable claim, so every rule gets a
## case here. The rules that a naive implementation would get wrong, and that this
## file exists to pin down:
##   * a monster BEHIND the player must NOT be picked (that reads as a broken game)
##   * a monster out of the cone must NOT be picked
##   * out of range must NOT be picked
##   * the pick must not flicker between two equidistant monsters
##   * the player's own stick must outrank the auto-target
##   * releasing the button must let go of the target
##   * a corpse must be let go of, and the next monster picked
##   * swinging at a NON-monster (the training posts) must still work - auto-target
##     is an addition to the melee, not a replacement for it

const MK := preload("res://scripts/monster_kind.gd")

var main: Node
var player: Node
var fails: Array[String] = []
var checks: int = 0
var changes: Array = []


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


## Spawns one monster at a known spot and keeps it a pure MEASURING STICK: it never
## aggros and never walks. Without this the two test monsters drifted in and out of
## their own aggro range, and the "already engaged" bonus in _update_target flipped
## the pick away from the nearer one - the assertion was right and the setup was
## leaking. The engaged-priority rule has its own case below.
func _spawn(kind: String, pos: Vector3) -> Node:
	var e: Node = main._build_enemy(kind, pos)
	e.name = "T_%s_%d_%d" % [kind, int(pos.x * 10.0), int(pos.z * 10.0)]
	e.aggro_range = 0.0
	e.aggro = false
	e.leash_range = 0.2
	main._enemies.append(e)
	return e


## Puts the world into a known state: no monsters, the player at the origin facing
## -Z, attack released, and the re-arm window expired.
func _reset(settle: int = 40) -> void:
	Input.action_release("attack")
	Input.action_release("move_right")
	Input.action_release("move_left")
	main.clear_enemies()
	player.global_position = Vector3(0, 0, 0)
	player.facing = Vector3(0, 0, -1)
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	player.hp = player.max_hp
	player.target = null
	await physics_frame
	for i in settle:
		await physics_frame


## How far the nearest level prop sits from the straight line between `a` and `b`.
## Used to prove an approach path is clear, so a layout change cannot silently make
## the player's swing land on a prop instead of the monster he is walking to - which
## is exactly what the first version of this test measured.
func _line_clearance(a: Vector3, b: Vector3) -> float:
	var best := INF
	var seg := b - a
	var seg_len := seg.length()
	if seg_len < 0.01:
		return INF
	var dir := seg / seg_len
	for c in main.get_children():
		if not (c is StaticBody3D) or c.name == "FloorBody":
			continue
		var p: Vector3 = (c as Node3D).global_position - a
		p.y = 0.0
		var t: float = clampf(p.dot(dir), 0.0, seg_len)
		var off: Vector3 = p - dir * t
		best = minf(best, off.length())
	return best


func _run() -> void:
	await physics_frame
	player = main.get_node("Player")
	player.target_changed.connect(func(t): changes.append(t))
	main.clear_enemies()

	print("== 1. a held attack picks the monster in front and walks him in ==")
	await _reset()
	# The spot matters, and it is asserted rather than eyeballed. (0,0,-4) looks
	# ideal - dead ahead, 4 m - but the level has a training post at (0,0,-3.2)
	# sitting ON that line. The player walked in, stopped at 1.37 m, and his swing
	# hit the POST instead of the monster: the measurement read "auto-target never
	# lands a hit" while the auto-target was working fine. Same class of trap as the
	# level-clearance note in tools/test_attack.gd and tools/test_fight.gd.
	var spot := Vector3(-1.5, 0, -4.0)
	var m: Node = _spawn("ghoul", spot)
	await physics_frame
	var clearance: float = _line_clearance(Vector3(0, 0, 0), spot)
	_ok("the approach line is clear of level geometry", clearance > 0.7,
		"nearest prop %.2f m off the line" % clearance)
	var d0: float = player.global_position.distance_to(m.global_position)
	var mhp0: float = m.hp
	var acquired := false
	Input.action_press("attack")
	var frames_used := 0
	for i in 420:
		await physics_frame
		frames_used = i
		if player.target == m:
			acquired = true
		if m.hp < mhp0:
			break
	var d1: float = player.global_position.distance_to(m.global_position)
	_ok("the held attack acquired the monster in front", acquired,
		"target=%s" % (player.target.name if player.target != null else "null"))
	_ok("he closed the distance to it", d1 < d0 - 1.0,
		"%.2f m -> %.2f m" % [d0, d1])
	_ok("he stopped inside his own light reach, not on top of it",
		d1 >= 0.6 and d1 <= player.light_range + 0.35, "%.2f m" % d1)
	_ok("the walk-in ended in a swing that landed", m.hp < mhp0,
		"%.0f -> %.0f hp in %.1f s" % [mhp0, m.hp, frames_used / 60.0])

	print("== 2. a monster BEHIND the player is NOT picked WHILE one is in front ==")
	await _reset()
	# Jan's correction (Sept 2026) split this case in two. The old version asserted "a
	# monster behind is never picked", and that was too strong: he reported a hero who
	# "attacks nobody when nobody is in the direction he looks - not even an enemy
	# standing right behind him". What must survive is PRECEDENCE: while something is
	# in the cone, the body behind it stays ignored (case 2), and only when the cone is
	# EMPTY does the nearest body win, wherever it stands (case 2b).
	var front2: Node = _spawn("ghoul", Vector3(-1.5, 0, -3.6))
	var behind: Node = _spawn("ghoul", Vector3(0, 0, 1.5))
	await physics_frame
	Input.action_press("attack")
	var saw_behind := false
	for i in 90:
		await physics_frame
		if player.target == behind:
			saw_behind = true
	_ok("the monster in the cone was preferred over the nearer one behind",
		player.target == front2, "target=%s" % (player.target.name if player.target != null else "null"))
	_ok("the body behind was never picked while one was in the cone", not saw_behind)
	Input.action_release("attack")

	print("== 2b. with the cone EMPTY, the nearest body is picked even BEHIND him ==")
	await _reset()
	# Nothing in front at all; one monster directly behind, close. Before this rule
	# existed the hero swung at air and the monster never took a hit.
	var back: Node = _spawn("ghoul", Vector3(0, 0, 2.6))
	await physics_frame
	var back_hp0: float = back.hp
	Input.action_press("attack")
	var acquired_behind := false
	for i in 180:
		await physics_frame
		if player.target == back:
			acquired_behind = true
		if back.hp < back_hp0:
			break
	_ok("the nearest body behind him was acquired", acquired_behind,
		"target=%s" % (player.target.name if player.target != null else "null"))
	_ok("he turned round and hit it", back.hp < back_hp0,
		"%.0f -> %.0f hp" % [back_hp0, back.hp])
	# the turn is what makes the pick readable: it must END up facing the monster
	var dot: float = player.facing.dot(Vector3(0, 0, 1))
	_ok("he finished the turn facing it", dot > 0.8, "facing.z %.3f" % player.facing.z)
	Input.action_release("attack")

	print("== 2c. a body behind him but OUT OF RANGE is still not picked ==")
	await _reset()
	var far_behind: Node = _spawn("ghoul", Vector3(0, 0, 12.0))
	await physics_frame
	Input.action_press("attack")
	for i in 60:
		await physics_frame
	_ok("the distance tier still obeys target_range", player.target == null,
		"target=%s" % (player.target.name if player.target != null else "null"))
	Input.action_release("attack")

	print("== 3. the cone is a PREFERENCE: outside it, only the distance tier applies ===")
	await _reset()
	# 80 deg off the nose, 3 m away: well inside range, outside the 55 deg cone AND
	# nothing else in range - so this is now the distance tier's own boundary check
	# (before the distance tier existed it tested the cone as a hard filter).
	var wide := Vector3(0, 0, -1).rotated(Vector3.UP, deg_to_rad(80.0)) * 3.0
	var side: Node = _spawn("ghoul", wide)
	await physics_frame
	Input.action_press("attack")
	var picked_side := false
	for i in 60:
		await physics_frame
		if player.target == side:
			picked_side = true
	# 80 deg is outside the 55 deg cone but INSIDE range: the distance tier MUST pick it
	_ok("a body 80 deg off the nose is picked once the cone is empty", picked_side,
		"target=%s" % (player.target.name if player.target != null else "null"))
	Input.action_release("attack")

	print("== 3b. ...but one inside the cone at the same distance IS picked ==")
	await _reset()
	var inner := Vector3(0, 0, -1).rotated(Vector3.UP, deg_to_rad(35.0)) * 3.0
	var inside: Node = _spawn("ghoul", inner)
	await physics_frame
	Input.action_press("attack")
	var picked := false
	for i in 90:
		await physics_frame
		if player.target == inside:
			picked = true
			break
	_ok("a monster 35 deg off the facing was picked", picked,
		"target=%s" % (player.target.name if player.target != null else "null"))

	print("== 4. out of range is NOT picked ==")
	await _reset()
	var far: Node = _spawn("ghoul", Vector3(0, 0, -10.0))
	await physics_frame
	Input.action_press("attack")
	for i in 60:
		await physics_frame
	_ok("a monster beyond target_range was not picked", player.target == null,
		"target=%s" % (player.target.name if player.target != null else "null"))

	print("== 5. the pick does not flicker between two monsters ==")
	await _reset()
	# Two Ghouls at almost the same distance and angle: without hysteresis and the
	# re-arm window these alternate on nearly every frame and the walk-in never
	# commits - measured as "he never arrived" before the window existed.
	var a: Node = _spawn("ghoul", Vector3(-1.2, 0, -3.6))
	var b: Node = _spawn("ghoul", Vector3(1.2, 0, -3.6))
	await physics_frame
	changes.clear()
	Input.action_press("attack")
	for i in 180:
		await physics_frame
	var distinct: Array = []
	for c in changes:
		if distinct.is_empty() or distinct[-1] != c:
			distinct.append(c)
	_ok("the target did not flicker between the pair", distinct.size() <= 3,
		"%d changes in 3 s (%s)" % [distinct.size(),
			", ".join(distinct.map(func(x): return x.name if x != null else "null"))])
	_ok("it settled on exactly one of them and walked in",
		player.target == a or player.target == b,
		"target=%s" % (player.target.name if player.target != null else "null"))

	print("== 6. the player's own stick outranks the auto-target ==")
	await _reset()
	var front: Node = _spawn("ghoul", Vector3(0, 0, -3.6))
	await physics_frame
	Input.action_press("attack")
	for i in 30:
		await physics_frame
	var had: bool = player.target == front
	# pushing AWAY from the target: the player is repositioning, not attacking
	Input.action_press("move_right")
	for i in 30:
		await physics_frame
	_ok("a target is picked while standing still", had)
	_ok("pushing the stick away drops the target", player.target == null,
		"target=%s" % (player.target.name if player.target != null else "null"))
	Input.action_release("move_right")

	print("== 7. releasing the attack lets go of the target ==")
	await _reset()
	var m7: Node = _spawn("ghoul", Vector3(0, 0, -3.6))
	await physics_frame
	Input.action_press("attack")
	var got := false
	for i in 60:
		await physics_frame
		if player.target == m7:
			got = true
			break
	Input.action_release("attack")
	await physics_frame
	await physics_frame
	_ok("holding the attack held a target", got)
	_ok("releasing the attack dropped it", player.target == null,
		"target=%s" % (player.target.name if player.target != null else "null"))

	print("== 8. a corpse is let go of and the next monster is picked ==")
	await _reset()
	var first: Node = _spawn("ghoul", Vector3(0, 0, -3.6))
	var second: Node = _spawn("ghoul", Vector3(0, 0, -5.0))
	await physics_frame
	Input.action_press("attack")
	for i in 90:
		await physics_frame
		if player.target == first:
			break
	_ok("the nearer monster was picked first", player.target == first,
		"target=%s" % (player.target.name if player.target != null else "null"))
	# kill it outright, so the pick has to move on with no extra fighting
	while not first.is_dead():
		first.take_hit(0)
	var moved_on := false
	for i in 180:
		await physics_frame
		if player.target == second:
			moved_on = true
			break
	_ok("after the kill it moved on to the next monster", moved_on,
		"target=%s" % (player.target.name if player.target != null else "null"))
	Input.action_release("attack")

	print("== 9. auto-target did NOT replace the plain melee ==")
	await _reset()
	# A post is not a monster (no take_hit/is_dead pair), so the cone must ignore it
	# and the ordinary held attack must still swing. main._posts are the level's
	# training posts; the swing at them is what tools/test_attack.gd measures.
	#
	# The assertion reads main._hits, NOT the post's colour. The post flashes and
	# resets its material inside one 0.25 s timer, so by the time the loop finishes
	# the colour is already back to default - reading it proves nothing.
	var post: Node = main._posts[0]
	player.global_position = post.global_position + Vector3(0, 0, 1.2)
	player.facing = Vector3(0, 0, -1)
	player.velocity = Vector3.ZERO
	main._hits.clear()
	Input.action_press("attack")
	for i in 150:
		await physics_frame
	var post_hits: int = main._hits.size()
	Input.action_release("attack")
	_ok("a held attack still swings with monsters absent", post_hits >= 1,
		"%d hits on the post" % post_hits)
	_ok("the post was the thing that got hit",
		main._hits.size() > 0 and main._hits[0]["who"] == post.name,
		str(main._hits[0]) if main._hits.size() > 0 else "no hits")

	print("== 10. an ALREADY ENGAGED monster is preferred over a nearer idle one ==")
	await _reset()
	# Both monsters passive except this one. The engaged monster is placed FURTHER,
	# so if the pick comes out on it, the bonus is what did it - and if it comes out
	# on the nearer idle one, the bonus is not wired up.
	var engaged: Node = _spawn("ghoul", Vector3(0.6, 0, -4.0))
	var nearer: Node = _spawn("ghoul", Vector3(2.2, 0, -3.0))
	await physics_frame
	engaged.aggro = true
	Input.action_press("attack")
	var picked_engaged := false
	for i in 30:
		await physics_frame
		if player.target == engaged:
			picked_engaged = true
			break
	Input.action_release("attack")
	_ok("the engaged monster won over the nearer idle one", picked_engaged,
		"target=%s (nearer idle=%s)"
		% [player.target.name if player.target != null else "null", nearer.name])

	print("")
	print("checks executed: ", checks)
	if fails.is_empty() and checks >= 18:
		print("AUTOTARGET_ALL_PASS=true")
	else:
		for f in fails:
			print("FAIL: ", f)
		if checks < 18:
			print("FAIL: only %d checks ran - not everything was exercised" % checks)
		print("AUTOTARGET_ALL_PASS=false")
	quit()
