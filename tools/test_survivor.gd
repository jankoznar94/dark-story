extends SceneTree
## tools/test_survivor.gd — the survivor run's RULES, and the one thing about its screen that
## must not be guessed (the portrait crop).
##
## The survivor run is real time, so the two defects that matter are not "a number is wrong" but
## "the run cannot be reproduced" and "a walk over a kill does not pay out". Both are asserted
## here, on a FIXED 1/60 s step, without a renderer:
##
##   1. DETERMINISM — the same seed twice must produce the same arena state. A run that drifts
##      between two identical seeds cannot be debugged and cannot be balanced.
##   2. THE LOOP CLOSES — a monster in range dies, it drops, the drop is collected into the
##      SAVE's gold or bag. A survivor game whose kills do not reach the bag has no loot at all,
##      and it looks perfectly healthy on screen.
##   3. THE FAIR REFUSALS — a full bag leaves the item on the ground, and a monster never
##      spawns on top of the player.
##   4. THE MEDALLION — a portrait cropped to a circle really has transparent corners. This is
##      the one drawing claim that can be checked without a viewport, and it is what keeps the
##      black plate Jan rejected out of the arena.
##
## Run:  godot --headless --path . --script res://tools/test_survivor.gd
## Pass: prints SURVIVOR_ALL_PASS=true

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const SurvivorRun := preload("res://scripts/combat/survivor_run.gd")
const SurvivorScreen := preload("res://scripts/ui/survivor_screen.gd")

const STEP := 1.0 / 60.0

var _failures: Array[String] = []
var _diag_done := false
var _data: Node
var _gen: ItemGen
var _loot: LootSystem
var _state


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_loot = LootSystem.new(_data, _gen)
	_state = GameState.new()
	_state.bind_data(_data)
	_state.reset()
	_state.set_class("barbarian")

	_test_setup_reads_the_hero()
	_test_movement_and_clamp()
	_test_monsters_close_in()
	_test_auto_attack_kills_and_drops()
	_test_walk_over_pays_into_the_save()
	_test_full_bag_leaves_the_item()
	_test_contact_damage_kills()
	_test_bodies_are_solid()
	_test_determinism()
	_test_spawn_cap_and_clearance()
	_test_wave_counter()
	_test_screen_gesture_and_disc()

	for f in _failures:
		print("  FAIL: %s" % f)
	print("SURVIVOR_ALL_PASS=%s" % ("true" if _failures.is_empty() else "false"))
	quit()


## Progress is written to a FILE with an explicit flush: stdout is block-buffered when this
## runs redirected, so a hang loses every line still in the buffer and the log points at the
## section BEFORE the real one. Learned the hard way — the first run of this test looked like
## it hung in the bag case while it was three sections later.
func _log(text: String) -> void:
	print(text)
	var f := FileAccess.open("user://survivor_test.log", FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open("user://survivor_test.log", FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(text)
		f.close()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)


func _fresh(seed_value: int = 12345) -> SurvivorRun:
	var run := SurvivorRun.new()
	run.setup(_state, _find_item, _loot, 0, seed_value)
	return run


func _rng_for_drop() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	return rng


func _find_item(id: Variant) -> Dictionary:
	if id == null:
		return {}
	var s := str(id)
	if s == "":
		return {}
	var item: Dictionary = _data.item(s)
	if item.is_empty():
		item = _state.loot_item(s)
	return item


# ============================================================================ rules

func _test_setup_reads_the_hero() -> void:
	_log("  section: setup_reads_the_hero")
	var run := _fresh()
	_check(run.max_hp > 0, "max_hp must come from the hero, got %d" % run.max_hp)
	_check(run.hp == run.max_hp, "a run starts at full health")
	_check(run.dmg_min > 0 and run.dmg_max >= run.dmg_min,
		"damage range must be a real range: %d..%d" % [run.dmg_min, run.dmg_max])
	_check(run.monsters.size() == 2, "an opening wave of 2, got %d" % run.monsters.size())
	_check(run.wave == 1, "the first wave is 1")


func _test_movement_and_clamp() -> void:
	_log("  section: movement_and_clamp")
	var run := _fresh()
	var start := run.player_pos
	run.step(STEP, Vector2(1, 0))
	var moved := run.player_pos.x - start.x
	_check(absf(moved - SurvivorRun.HERO_SPEED * STEP) < 0.01,
		"one step right must move HERO_SPEED*dt = %.3f, got %.3f"
			% [SurvivorRun.HERO_SPEED * STEP, moved])
	# A diagonal must not be faster than a straight line: the vector is limited, not summed.
	var run2 := _fresh()
	var start2 := run2.player_pos
	run2.step(STEP, Vector2(1, 1))
	_check(absf(run2.player_pos.distance_to(start2) - SurvivorRun.HERO_SPEED * STEP) < 0.01,
		"a diagonal step must have the same length as a straight one")
	# The world edge holds.
	var run3 := _fresh()
	for _i in 600:
		run3.step(STEP, Vector2(-1, -1))
	_check(run3.player_pos.x >= SurvivorRun.HERO_RADIUS - 0.01
			and run3.player_pos.y >= SurvivorRun.HERO_RADIUS - 0.01,
		"the hero must not leave the world: %s" % str(run3.player_pos))


func _test_monsters_close_in() -> void:
	_log("  section: monsters_close_in")
	var run := _fresh()
	var m: Dictionary = run.monsters[0]
	var before := (m["pos"] as Vector2).distance_to(run.player_pos)
	for _i in 60:
		run.step(STEP, Vector2.ZERO)
	var after := (run.monsters[0]["pos"] as Vector2).distance_to(run.player_pos)
	_check(after < before, "a monster must walk toward the hero: %.1f -> %.1f" % [before, after])


func _test_auto_attack_kills_and_drops() -> void:
	_log("  section: auto attack")
	var run := _fresh()
	# Put one monster inside the attack range and keep it there; hold the DICTIONARY, not the
	# index — `_kill()` removes it from the array and `monsters[0]` then reads the next one (or
	# throws), which is how a test loop turns into a hang instead of a failure.
	run.monsters.clear()
	run._spawn_one()
	var m: Dictionary = run.monsters[0]
	var hp_before := int(m["hp"])
	var ticks := 0
	while int(m["hp"]) == hp_before and ticks < 240:
		m["pos"] = run.player_pos + Vector2(SurvivorRun.ATTACK_RANGE * 0.5, 0)
		run.step(STEP, Vector2.ZERO)
		ticks += 1
	_check(int(m["hp"]) < hp_before, "the auto-attack must land inside its range")
	_check(not run.numbers.is_empty(), "a landing blow must produce a damage number")
	# The swing the RENDERER animates: an age the screen can read, and a direction that points at
	# what was hit. Without this the screen has nothing to draw a lunge or a slash from.
	_check(run.swing_age >= 0.0 and run.swing_age < 0.25,
		"a landed blow must stamp swing_age near 0, got %.3f" % run.swing_age)
	var to_target: Vector2 = (m["pos"] as Vector2) - run.player_pos
	_check(run.swing_dir.dot(to_target.normalized()) > 0.9,
		"the swing must point at the target: %s vs %s" % [str(run.swing_dir), str(to_target.normalized())])
	var kills_before := run.kills
	while run.kills == kills_before and ticks < 3000:
		m["pos"] = run.player_pos + Vector2(SurvivorRun.ATTACK_RANGE * 0.5, 0)
		run.step(STEP, Vector2.ZERO)
		ticks += 1
	_check(run.kills >= 1, "the monster must die to repeated swings")
	_check(not run.drops.is_empty(), "a kill must leave loot on the ground")


func _test_walk_over_pays_into_the_save() -> void:
	_log("  section: walk_over_pays_into_the_save")
	var run := _fresh()
	var gold_before := int(_state.hero().get("gold", 0))
	run.drops.append({"pos": run.player_pos, "kind": "gold", "amount": 7, "age": 0.0})
	run.step(STEP, Vector2.ZERO)
	_check(run.gold == 7, "walking over gold must collect it, got %d" % run.gold)
	_check(int(_state.hero().get("gold", 0)) == gold_before + 7,
		"collected gold must reach the SAVE, not just the run counter")

	# An item must reach the bag AND the loot registry (the bag stores ids, not objects).
	var item: Dictionary = _loot.generate_item(_state, 0, 1, false, 1, 0, _rng_for_drop())
	_check(not item.is_empty(), "the item generator must produce an item for the drop test")
	if item.is_empty():
		return
	var bag_before: int = _state.inventory().size()
	run.drops.append({"pos": run.player_pos, "kind": "item", "item": item, "age": 0.0, "color": "#888"})
	run.step(STEP, Vector2.ZERO)
	_check(_state.inventory().size() == bag_before + 1,
		"a collected item must land in the bag: %d -> %d" % [bag_before, _state.inventory().size()])
	_check(not _state.loot_item(str(item.get("id", ""))).is_empty(),
		"a generated item must be registered so the bag can resolve its id")


func _test_full_bag_leaves_the_item() -> void:
	_log("  section: full_bag_leaves_the_item")
	var run := _fresh()
	_log("   a run ready")
	# Fill the bag to its limit with distinct stack entries.
	var guard := 0
	while not _state.bag_full() and guard < 200:
		_state.add_item("survivor_test_filler_%d" % guard, {"id": "survivor_test_filler_%d" % guard, "name": "Filler", "quality": "normal"})
		guard += 1
	_log("   bag full=%s guard=%d" % [str(_state.bag_full()), guard])
	_check(_state.bag_full(), "the bag must be fillable for this case to mean anything")
	var item: Dictionary = _loot.generate_item(_state, 0, 1, false, 1, 0, _rng_for_drop())
	_log("   item=%s" % str(item.get("id", "-")))
	if item.is_empty():
		return
	run.drops.append({"pos": run.player_pos, "kind": "item", "item": item, "age": 0.0, "color": "#888"})
	_log("   drop planted")
	run.step(STEP, Vector2.ZERO)
	_log("   stepped, drops=%d" % run.drops.size())
	_check(run.drops.size() == 1, "a full bag must leave the item ON THE GROUND, got %d drops" % run.drops.size())
	_check(run.events.has("bagfull"), "the refusal must be reported to the screen")
	_state.inventory().clear()
	_log("   bag cleared")


func _test_contact_damage_kills() -> void:
	_log("  section: contact death")
	var run := _fresh()
	run.hp = 5
	run.defense = 0
	run.dmg_min = 1
	run.dmg_max = 1
	run.monsters.clear()
	run._spawn_one()
	var m: Dictionary = run.monsters[0]
	m["hp"] = 99999
	m["dmg_min"] = 6
	m["dmg_max"] = 6
	var ticks := 0
	while not run.finished and ticks < 300:
		m["pos"] = run.player_pos
		run.step(STEP, Vector2.ZERO)
		ticks += 1
	_check(run.finished and run.outcome == "dead",
		"contact damage must be able to end the run, hp=%d finished=%s" % [run.hp, str(run.finished)])
	_check(run.hp == 0, "hp must clamp at 0, got %d" % run.hp)


## Jan's report: "hrdina prochází nepřáteli jakoby to byli duchové. Portréty se nesmí překrývat."
## This is the assertion for it: after a long run with the hero pushing INTO the pack, no two
## bodies may be closer than two disc radii. Asserted on the BODIES (positions), never on a flag.
func _test_bodies_are_solid() -> void:
	_log("  section: bodies_are_solid")
	# ⚠️  The first version walked toward whatever spawned and measured NOTHING: the closest the
	# hero ever came was 186 px against a 62 px bar, i.e. the assertion passed because no body
	# ever touched him. The pack is therefore PLACED, and the hero is driven INTO it.
	var run := _fresh(31337)
	run.max_hp = 999999
	run.hp = 999999
	run.monsters.clear()
	for i in 5:
		run._spawn_one()
		var ang := float(i) * TAU / 5.0
		run.monsters[i]["pos"] = run.player_pos + Vector2(cos(ang), sin(ang)) * 90.0
	var min_gap := SurvivorRun.BODY_RADIUS * 2.0
	var worst_hero := 1e9
	var worst_pair := 1e9
	for i in 180:
		# Walk right INTO the pack for a second, then stand still and let it press in.
		var dir := Vector2(1, 0) if i < 60 else Vector2.ZERO
		run.step(STEP, dir)
		for m in run.monsters:
			worst_hero = minf(worst_hero, (m["pos"] as Vector2).distance_to(run.player_pos))
		for a in run.monsters.size():
			for b in range(a + 1, run.monsters.size()):
				worst_pair = minf(worst_pair,
					(run.monsters[a]["pos"] as Vector2).distance_to(run.monsters[b]["pos"]))
	_check(worst_hero >= min_gap - 1.0,
		"the hero must not pass through a body: closest %.1f < %.1f" % [worst_hero, min_gap])
	_check(worst_pair >= min_gap - 1.0,
		"two portraits must not overlap: closest pair %.1f < %.1f" % [worst_pair, min_gap])
	# ...and the reach has to actually be reachable: contact is 62 px, the swing 76 px.
	_check(SurvivorRun.ATTACK_RANGE > min_gap and SurvivorRun.ATTACK_RANGE <= min_gap + 24.0,
		"the melee reach must be CONTACT plus a short step, got %.1f against contact %.1f"
			% [SurvivorRun.ATTACK_RANGE, min_gap])
	print("  measured: hero_gap=%.1f pair_gap=%.1f (min %.1f)" % [worst_hero, worst_pair, min_gap])


func _test_determinism() -> void:
	_log("  section: determinism")
	var a := _fresh(999)
	var b := _fresh(999)
	for _i in 300:
		a.step(STEP, Vector2(0.4, -0.7))
		b.step(STEP, Vector2(0.4, -0.7))
	_check(a.monsters.size() == b.monsters.size(),
		"the same seed must spawn the same count: %d vs %d" % [a.monsters.size(), b.monsters.size()])
	_check(a.player_pos.distance_to(b.player_pos) < 0.001, "the same seed must move identically")
	var same := a.monsters.size() == b.monsters.size()
	if same:
		for i in a.monsters.size():
			if (a.monsters[i]["pos"] as Vector2).distance_to(b.monsters[i]["pos"]) > 0.001:
				same = false
	_check(same, "the same seed must place every monster identically")


func _test_spawn_cap_and_clearance() -> void:
	_log("  section: spawn_cap_and_clearance")
	var run := _fresh(4242)
	var closest := 1e9
	for _i in 60 * 90:
		run.step(STEP, Vector2(1, 0))
		for m in run.monsters:
			var dd: float = (m["pos"] as Vector2).distance_to(run.player_pos)
			if dd < SurvivorRun.BODY_RADIUS * 2.0 - 1.0 and not _diag_done:
				_diag_done = true
				print("  DIAG dist=%.2f hero=%s mon=%s at_edge=%s n=%d alive=%s"
					% [dd, str(run.player_pos), str(m["pos"]),
						str(run.player_pos.x > SurvivorRun.WORLD.x - 40.0 or run.player_pos.y > SurvivorRun.WORLD.y - 40.0),
						run.monsters.size(), str(m["hp"])])
			closest = minf(closest, dd)
	_check(run.monsters.size() <= SurvivorRun.MAX_ALIVE,
		"the alive cap must hold: %d > %d" % [run.monsters.size(), SurvivorRun.MAX_ALIVE])
	# Clearance is asserted on SPAWN positions, so let a fresh run's first wave speak for it.
	var fresh := _fresh(777)
	for m in fresh.monsters:
		var d: float = (m["pos"] as Vector2).distance_to(fresh.player_pos)
		_check(d >= SurvivorRun.SPAWN_RADIUS_MIN - 1.0,
			"a monster must not spawn on top of the player: %.1f < %.1f" % [d, SurvivorRun.SPAWN_RADIUS_MIN])
	print("  measured: alive=%d closest_contact=%.1f" % [run.monsters.size(), closest])
	_check(closest >= SurvivorRun.BODY_RADIUS * 2.0 - 1.0,
		"the hero must stay clear of every body for a whole run: %.1f" % closest)


func _test_wave_counter() -> void:
	_log("  section: wave_counter")
	var run := _fresh()
	# ⚠️  The first version of this case stood still for 27 s and asserted the wave number —
	# and failed, because the hero DIED at ~12 s and `step()` returns immediately once a run is
	# over. The clock has to be measured on a run that cannot end.
	run.monsters.clear()
	run.max_hp = 999999
	run.hp = 999999
	run.defense = 999
	var ticks := int((SurvivorRun.WAVE_SECONDS + 0.5) / STEP)
	for _i in ticks:
		run.step(STEP, Vector2.ZERO)
	_check(not run.finished, "the wave clock needs a run that is still alive to be measurable")
	_check(run.wave == 2, "the wave must advance after WAVE_SECONDS, got %d" % run.wave)


# ============================================================================ screen

func _test_screen_gesture_and_disc() -> void:
	_log("  section: screen_gesture_and_disc")
	var screen = SurvivorScreen.new()
	root.add_child(screen)
	screen.size = Vector2(390, 844)
	screen.setup(_state, _find_item, _loot, 0)
	_check(screen.run != null, "the screen must own a run after setup")
	# The hero is a WALKING PORTRAIT built from the same face his stat page shows.
	_check(screen._hero_face() != "", "the hero must have a portrait face")
	var hero_tex: Texture2D = screen._disc("assets/monsters/%s.png" % screen._hero_face())
	_check(hero_tex != null, "the hero's medallion must load (%s)" % screen._hero_face())

	# A press in the field starts the stick THERE (the floating control), and a drag sets it.
	screen._on_press(Vector2(140, 600))
	_check(screen._pointer_down and screen._stick_origin == Vector2(140, 600),
		"a press in the field must plant the stick at the finger")
	screen._on_drag(Vector2(230, 600))
	_check(screen._stick_vec.x > 0.9 and absf(screen._stick_vec.y) < 0.01,
		"a drag must produce a full-strength direction, got %s" % str(screen._stick_vec))
	screen._on_release()
	_check(not screen._pointer_down and screen._stick_vec == Vector2.ZERO,
		"releasing must stop the hero")

	# The fixed buttons must NOT be reachable by the stick: they are a separate control area.
	screen._on_press(screen._potion_centre)
	_check(screen._stick_vec == Vector2.ZERO and screen._stick_origin != screen._potion_centre,
		"a tap on the potion button must not start the stick")
	screen._on_release()

	# A portrait cropped to a disc has TRANSPARENT corners — the black plate Jan rejected.
	var tex: Texture2D = screen._disc("assets/monsters/dryada.png")
	_check(tex != null, "the medallion texture must load")
	if tex != null:
		var img := tex.get_image()
		_check(img.get_pixel(1, 1).a < 0.02, "a corner of the medallion must be transparent")
		_check(img.get_pixel(96, 96).a > 0.5, "the middle of the medallion must be opaque")

	screen.queue_free()
