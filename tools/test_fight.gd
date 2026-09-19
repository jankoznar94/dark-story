extends SceneTree
## Headless fight test: does the PACK actually fight, and is it genuinely weaker
## than the hero?
## Run: godot --headless --path . --script res://tools/test_fight.gd
##
## What is checked, in order:
##   1. every kind in the catalogue is well-formed and WEAKER THAN THE HERO, which
##      is Jan's actual brief ("weaker, so I can try killing several") and is a
##      measurable claim, not a mood: hits-to-kill from the hero's numbers.
##   2. the pack spawns, one node per entry, each with its own kind's numbers
##   3. every spawn keeps clearance from the level's props and from the
##      coordinates the other gameplay tests teleport to
##   4. they notice the player and close the distance
##   5. in reach they attack, and the attack damages the player
##   6. the player's directional swing damages them
##   7. one dies, plays its death clip, and then stops acting
##   8. the ghouls actually CIRCLE instead of queueing (their whole reason to exist)
##   9. the HUD bars follow both health pools

var main: Node
var fails: Array[String] = []
var checks: int = 0

const MK := preload("res://scripts/monster_kind.gd")

## Coordinates the OTHER tools teleport the player to. A monster spawn - and the
## space a monster walks through on its way in - must not sit on them. This is the
## rule the level notes learned the hard way: a body in a test's spot gets reported
## as a failure in unrelated code.
const TEST_POSITIONS := [
	Vector3(0, 0, -2), Vector3(0, 0, 2), Vector3(0, 0, 0), Vector3(4.6, 0, -9),
]


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
## a position is clear, so a layout change cannot silently invalidate the test.
func _nearest_prop(p: Vector3) -> float:
	var best := INF
	for c in main.get_children():
		if c is StaticBody3D and c.name != "FloorBody":
			var d: float = p.distance_to((c as Node3D).global_position)
			if d < best:
				best = d
	return best


func _run() -> void:
	_test_catalogue()

	await physics_frame
	await physics_frame
	var player: Node = main.get_node("Player")

	print("== 2. the pack spawned, one node per kind entry ==")
	var pack: Array = main._enemies
	_ok("several monsters are in the scene", pack.size() >= 5, "%d monsters" % pack.size())
	var kinds := {}
	for e in pack:
		kinds[e.monster_name] = int(kinds.get(e.monster_name, 0)) + 1
	print("     composition: ", kinds)
	_ok("there are at least three distinct kinds", kinds.size() >= 3, str(kinds.keys()))
	_ok("there is a weak pack of several", int(kinds.get("Ghoul", 0)) >= 3,
		"%d Ghouls" % int(kinds.get("Ghoul", 0)))
	for e in pack:
		_ok("%s carries its own numbers" % e.name,
			e.max_hp > 0.0 and e.hp == e.max_hp and e.attack_range > 0.0
			and e.damage_max > 0.0 and e.anim != null,
			"%.0f hp, reach %.2f m, %.0f-%.0f damage"
			% [e.max_hp, e.attack_range, e.damage_min, e.damage_max])

	print("== 3. no spawn sits in geometry or on another test's coordinates ==")
	for e in pack:
		var near: float = _nearest_prop(e.global_position)
		_ok("%s spawn is clear of level geometry" % e.name, near > 1.5,
			"nearest prop %.2f m" % near)
		var nearest_test := INF
		for t in TEST_POSITIONS:
			nearest_test = minf(nearest_test, e.global_position.distance_to(t))
		_ok("%s spawn is off the other tests' spots" % e.name, nearest_test > 3.0,
			"nearest test position %.2f m" % nearest_test)

	print("== 4. they notice the player WHEN THE PLAYER COMES TO THEM ==")
	# One at a time, on purpose. Six monsters all waking at once was measured as
	# real and rejected: it turns every engagement into the whole pack ("hordes",
	# which this game bans) and removes the choice of lane. Aggro is 5 m, so
	# standing in the open centre wakes at most the nearest one.
	var ghoul0: Node = _first_of(pack, "Ghoul")
	_ok("the pack does NOT all wake at spawn",
		pack.filter(func(e): return e.aggro).size() <= 2,
		"%d of %d engaged immediately" % [pack.filter(func(e): return e.aggro).size(), pack.size()])
	player.global_position = ghoul0.global_position + Vector3(4.0, 0, 0)
	player.hp = player.max_hp
	await physics_frame
	var closest0: float = ghoul0.global_position.distance_to(player.global_position)
	_ok("the ghoul is inside its own aggro radius for this measurement",
		closest0 < ghoul0.aggro_range, "%.2f m vs %.2f m" % [closest0, ghoul0.aggro_range])
	for i in 150:
		await physics_frame
	var closest1: float = ghoul0.global_position.distance_to(player.global_position)
	_ok("it noticed the player and closed the distance", closest1 < closest0 - 0.5,
		"%.2f m -> %.2f m" % [closest0, closest1])
	_ok("the pack is not standing on top of itself",
		_min_pairwise_gap(pack) > 0.6, "smallest gap %.2f m" % _min_pairwise_gap(pack))

	print("== 5. in reach they attack, and the player takes damage ==")
	# Test a GHOUL specifically: it is the kind the brief is about.
	var ghoul: Node = _first_of(pack, "Ghoul")
	_ok("there is a Ghoul to test with", ghoul != null)
	if ghoul != null:
		# EVERY OTHER MONSTER GOES AWAY FOR THIS SECTION. Without it the hp delta
		# measured "the ghoul's damage" was 16.6 while a Ravager and two ghouls were
		# also punching: the assertion was right and the attribution was wrong, the
		# same class of error as the level clearance trap.
		_park_others(pack, ghoul)
		# park the player right in front of it and let the fight run
		player.global_position = ghoul.global_position + Vector3(0, 0, 1.05)
		player.hp = player.max_hp
		var hp0: float = player.hp
		var saw_attack := false
		for i in 420:
			await physics_frame
			if ghoul.state_name() != "idle":
				saw_attack = true
			if player.hp < hp0:
				break
		_ok("the ghoul ran its attack state machine", saw_attack)
		_ok("the ghoul's attack damaged the player", player.hp < hp0,
			"%.0f -> %.0f hp" % [hp0, player.hp])
		_ok("ghoul damage stayed inside the declared range",
			(hp0 - player.hp) >= ghoul.damage_min - 0.01
			and (hp0 - player.hp) <= ghoul.damage_max + 0.01,
			"dealt %.1f (range %.0f-%.0f)"
			% [hp0 - player.hp, ghoul.damage_min, ghoul.damage_max])
		_ok("only the ghoul was in the fight for that measurement",
			_parked_count(pack, ghoul) == pack.size() - 1,
			"%d monsters parked" % _parked_count(pack, ghoul))

	print("== 6. the player's directional swing damages a monster ==")
	if ghoul != null:
		var ehp0: float = ghoul.hp
		player.global_position = ghoul.global_position + Vector3(0, 0, 1.2)
		player.facing = Vector3(0, 0, -1)
		player.rotation.y = 0.0
		player.velocity = Vector3.ZERO
		player._begin_attack(0)
		while player.is_busy():
			await physics_frame
		_ok("swing landed and took monster health", ghoul.hp < ehp0,
			"%.0f -> %.0f" % [ehp0, ghoul.hp])

	print("== 7. a ghoul dies in a few swings, and stays dead ==")
	if ghoul != null:
		var guard := 0
		while not ghoul.is_dead() and guard < 200:
			ghoul.take_hit(0)
			guard += 1
		_ok("the ghoul died", ghoul.is_dead(), "%d hits" % guard)
		# The brief: "weaker than the hero, so I can kill several". A ghoul must not
		# take more swings than the hero has patience for.
		_ok("it died in a handful of hits", guard <= 8, "%d hits" % guard)
		_ok("death is visible on the clip", ghoul.current_clip() == ghoul.CLIP_DEATH,
			ghoul.current_clip())
		var pos_at_death: Vector3 = ghoul.global_position
		player.global_position = ghoul.global_position + Vector3(0, 0, 1.0)
		var php0: float = player.hp
		for i in 90:
			await physics_frame
		_ok("a dead monster stops moving",
			ghoul.global_position.distance_to(pos_at_death) < 0.05,
			"moved %.3f m" % ghoul.global_position.distance_to(pos_at_death))
		_ok("a dead monster deals no more damage", absf(player.hp - php0) < 0.001)
		_ok("a dead monster stays dead",
			ghoul.hp == 0.0 and ghoul.state_name() == "idle")

	print("== 8. a ghoul circles instead of walking straight in ==")
	# This is the behaviour that makes three weak enemies worth having: they must
	# not arrive along one line and turn into a queue. Measured as the angle
	# between the monster's approach direction and the straight line to the player.
	var g2: Node = _alive_of(pack, "Ghoul", ghoul)
	if g2 == null:
		_ok("a second ghoul is alive to measure the flank", false, "none left")
	else:
		player.global_position = Vector3(0, 0, 0)
		player.hp = player.max_hp
		# put it at a known distance, where the orbit is active
		g2.global_position = Vector3(0, 0, -3.0)
		g2.velocity = Vector3.ZERO
		g2.aggro = true
		await physics_frame
		var max_lateral := 0.0
		for i in 120:
			await physics_frame
			var to_player: Vector3 = player.global_position - g2.global_position
			to_player.y = 0.0
			if to_player.length() < 0.2:
				continue
			var vel: Vector3 = g2.velocity
			vel.y = 0.0
			if vel.length() < 0.2:
				continue
			# 0 deg = walking straight at the player, 90 deg = purely sideways
			var lateral: float = rad_to_deg(acos(clampf(
				vel.normalized().dot(to_player.normalized()), -1.0, 1.0)))
			max_lateral = maxf(max_lateral, lateral)
		_ok("the ghoul moves across the approach line, not along it",
			max_lateral > 25.0, "peak sideways angle %.1f deg" % max_lateral)

	print("== 9. the HUD follows both health pools ==")
	main._process(0.016)
	var hud: Node = main.get_node("HUD")
	_ok("the enemy bar names a monster of the pack",
		hud.enemy_label.text.length() > 0
		and _any_name_matches(pack, hud.enemy_label.text),
		hud.enemy_label.text)
	_ok("the player bar shows HP", hud.hp_label.text.contains("HP"), hud.hp_label.text)
	_ok("the player bar is filled", hud.hp_fill.size.x > 0.0,
		"%.1f px" % hud.hp_fill.size.x)

	_finish()


func _test_catalogue() -> void:
	print("== 1. every kind is WEAKER THAN THE HERO (the brief) ==")
	var all: Dictionary = MK.kinds()
	_ok("the catalogue has several kinds", all.size() >= 3, "%d kinds" % all.size())
	for id in all:
		var k: Dictionary = all[id]
		var hits: int = MK.hits_to_kill(k)
		var dps_ok: bool = float(k["damage_max"]) < MK.HERO_MAX_HP * 0.12
		_ok("%s is killable in a handful of swings" % k["name"], hits <= 12,
			"%.0f hp -> %d hero swings" % [float(k["hp"]), hits])
		_ok("%s cannot kill the hero quickly" % k["name"], dps_ok,
			"max %.0f damage vs hero %.0f hp" % [float(k["damage_max"]), MK.HERO_MAX_HP])
		_ok("%s declares a behaviour script" % k["name"],
			ResourceLoader.exists(str(k["script"])), str(k["script"]))
		_ok("%s shares the punch contact frame" % k["name"],
			absf(float(k["windup"]) - MK.PUNCH_WINDUP) < 0.0001,
			"windup %.2f s" % float(k["windup"]))


func _first_of(pack: Array, name_wanted: String) -> Node:
	for e in pack:
		if e.monster_name == name_wanted and not e.is_dead():
			return e
	return null


## Moves every monster except `keep` far off the map for the duration of a
## measurement. They are not freed: freeing them would change the node order the
## later sections rely on, and moving one body is cheaper than rebuilding the pack.
func _park_others(pack: Array, keep: Node) -> void:
	for e in pack:
		if e == keep or not is_instance_valid(e):
			continue
		e.global_position = Vector3(e.global_position.x, e.global_position.y,
			e.global_position.z + 200.0)


func _parked_count(pack: Array, keep: Node) -> int:
	var n := 0
	for e in pack:
		if e != keep and is_instance_valid(e) and e.global_position.z > 100.0:
			n += 1
	return n


func _alive_of(pack: Array, name_wanted: String, exclude: Node) -> Node:
	for e in pack:
		if e == exclude:
			continue
		if e.monster_name == name_wanted and not e.is_dead():
			return e
	return null


func _any_name_matches(pack: Array, text: String) -> bool:
	for e in pack:
		if text.contains(e.monster_name):
			return true
	return false


func _min_pairwise_gap(pack: Array) -> float:
	var best := INF
	for i in pack.size():
		for j in range(i + 1, pack.size()):
			best = minf(best, pack[i].global_position.distance_to(pack[j].global_position))
	return best


func _finish() -> void:
	print("")
	print("checks executed: ", checks)
	if fails.is_empty() and checks >= 25:
		print("FIGHT_ALL_PASS=true")
	else:
		for f in fails:
			print("FAIL: ", f)
		if checks < 25:
			print("FAIL: only %d checks ran - not everything was exercised" % checks)
		print("FIGHT_ALL_PASS=false")
	quit()
