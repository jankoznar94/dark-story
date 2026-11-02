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
const Progression := preload("res://scripts/combat/progression.gd")

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
	_test_reach_is_the_drawn_circle()
	_test_weapon_pace_and_two_hands()
	_test_two_hander_reach()
	_test_move_speed_boots()
	_test_boots_roll_speed_affix()
	_test_ranged_kinds()
	_test_thrower_keeps_distance_and_fires()
	_test_orb_hits_and_can_be_dodged()
	_test_determinism()
	_test_spawn_cap_and_clearance()
	_test_pack_discovery()
	_test_kills_award_xp()
	_test_facing_gate()
	_test_spells_in_the_run()
	_test_whirlwind_flurry()
	_test_bolt_flies_at_the_aimed_body()
	_test_spell_effects()
	_test_screen_spell_buttons()
	_test_cast_while_running()
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
	_check(run.monsters.is_empty(), "the hero starts in an EMPTY clearing, got %d monsters" % run.monsters.size())
	_check(run.wave == 0, "no pack has woken yet, wave=%d" % run.wave)
	# 3x3 cells minus the hero's own clearing: eight packs, each a known quantity before it wakes.
	_check(run.zones.size() == SurvivorRun.ZONE_COLS * SurvivorRun.ZONE_ROWS - 1,
		"the area must hold one pack per cell but the clearing, got %d" % run.zones.size())
	for z in run.zones:
		var n: int = (z["members"] as Array).size()
		_check(n >= SurvivorRun.PACK_MIN and n <= SurvivorRun.PACK_MAX,
			"a pack is %d..%d bodies, got %d" % [SurvivorRun.PACK_MIN, SurvivorRun.PACK_MAX, n])
		for m in z["members"]:
			var d: float = (m["pos"] as Vector2).distance_to(z["centre"] as Vector2)
			_check(d <= SurvivorRun.ZONE_JITTER + 1.0,
				"a pack member must stand inside its own cell: %.1f > %.1f" % [d, SurvivorRun.ZONE_JITTER])
		# A pack must never wake on the hero's first frame.
		_check((z["centre"] as Vector2).distance_to(run.player_pos) > SurvivorRun.ACTIVATE_RADIUS,
			"a pack centre is inside the activation radius at spawn")


func _test_movement_and_clamp() -> void:
	_log("  section: movement_and_clamp")
	var run := _fresh()
	var start := run.player_pos
	run.step(STEP, Vector2(1, 0))
	var moved := run.player_pos.x - start.x
	_check(absf(moved - run.hero_speed() * STEP) < 0.01,
		"one step right must move hero_speed()*dt = %.3f, got %.3f"
			% [run.hero_speed() * STEP, moved])
	# A diagonal must not be faster than a straight line: the vector is limited, not summed.
	var run2 := _fresh()
	var start2 := run2.player_pos
	run2.step(STEP, Vector2(1, 1))
	_check(absf(run2.player_pos.distance_to(start2) - run2.hero_speed() * STEP) < 0.01,
		"a diagonal step must have the same length as a straight one")
	# The world edge holds — at the WALL inset, which is where the boundary props stand.
	var run3 := _fresh()
	for _i in 600:
		run3.step(STEP, Vector2(-1, -1))
	var wall := SurvivorRun.AREA_MARGIN + SurvivorRun.HERO_RADIUS - 0.01
	_check(run3.player_pos.x >= wall and run3.player_pos.y >= wall,
		"the hero must stop at the wall: %s (wall %.1f)" % [str(run3.player_pos), wall])


func _test_monsters_close_in() -> void:
	_log("  section: monsters_close_in")
	var run := _fresh()
	run._spawn_one()
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
	# ⚠️  Explicitly MELEE: this section is about contact damage, and the spawn table can hand
	# back a thrower (Rarach) that never touches the hero. Pinning the flag keeps the test
	# about the thing it names instead of about which row the dice picked.
	m["ranged"] = false
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


# ============================================================================ ranged units

## WHICH kinds throw. The rule is the port's own (the PWA had no range at all), so it is
## asserted rather than assumed: a data regeneration or a renamed face silently turns Rarach
## back into a melee imp, and nothing else in the game would say so.
func _test_ranged_kinds() -> void:
	_log("  section: ranged_kinds")
	var run := _fresh()
	var rarach := _row_with_face("assets/monsters/lesni_rarach.png")
	_check(not rarach.is_empty(), "act 0 must offer Rarach (lesni_rarach)")
	if not rarach.is_empty():
		_check(run._is_ranged(rarach), "Rarach must be a THROWER, not a melee imp")
	var wolf := _row_with_face("assets/monsters/vlk.png")
	if not wolf.is_empty():
		_check(not run._is_ranged(wolf), "Wolf must stay melee")
	# The PWA's own vocabulary: a caster row throws.
	_check(run._is_ranged({"attackType": "caster"}), "attackType=caster must count as ranged")


## The point of a ranged unit is DISTANCE. It walks in to `KEEP_RANGE` and stops there — if it
## walks to contact distance anyway, the range is a number in a table and nothing else.
func _test_thrower_keeps_distance_and_fires() -> void:
	_log("  section: thrower_keeps_distance")
	var run := _fresh()
	run.max_hp = 999999
	run.hp = 999999
	run.monsters.clear()
	run.projectiles.clear()
	run._spawn_one()
	var m: Dictionary = run.monsters[0]
	# Pinned to a thrower: this section is about the stand-off, not about the dice.
	m["ranged"] = true
	m["keep_range"] = SurvivorRun.KEEP_RANGE
	m["hp"] = 999999
	m["speed"] = 60.0
	m["atk_cd"] = 0.6
	m["atk_ready"] = 0.0
	m["pos"] = run.player_pos + Vector2(400.0, 0.0)

	var fired := 0
	for i in 240:
		var before := run.projectiles.size()
		run._move_monsters(STEP)
		if run.projectiles.size() > before:
			fired += 1
		run._step_projectiles(STEP)
	var gap: float = (m["pos"] as Vector2).distance_to(run.player_pos)
	_check(fired > 0, "a thrower in range must fire, fired=%d" % fired)
	_check(gap >= SurvivorRun.KEEP_RANGE - 2.0,
		"a thrower must keep its distance, gap=%.1f keep=%.1f" % [gap, SurvivorRun.KEEP_RANGE])
	_check(gap <= SurvivorRun.KEEP_RANGE + 60.0,
		"a thrower must CLOSE to its keep distance, not hang back, gap=%.1f" % gap)


## An orb is a body: it hits the hero's disc, it hurts, and it MISSES when the hero steps out
## of the line. The miss is the half that makes movement matter, so it is asserted too.
func _test_orb_hits_and_can_be_dodged() -> void:
	_log("  section: orb_hits_and_dodges")
	var run := _fresh()
	run.max_hp = 500
	run.hp = 500
	run.defense = 0
	run.monsters.clear()
	run.projectiles.clear()
	run._spawn_one()
	var m: Dictionary = run.monsters[0]
	m["dmg_min"] = 12
	m["dmg_max"] = 12

	# A. Straight in: the orb must hurt.
	run._shoot(m, run.player_pos - (m["pos"] as Vector2))
	_check(run.projectiles.size() == 1, "a throw must put exactly one orb in the air")
	var hit_hp := run.hp
	for i in 120:
		run._step_projectiles(STEP)
		if run.hp < 500:
			break
	_check(run.hp < 500, "an orb aimed at a standing hero must hit, hp=%d" % run.hp)
	hit_hp = run.hp
	_check(run.projectiles.is_empty(), "a spent orb must leave the air, %d left" % run.projectiles.size())

	# B. Step out of the line: the same throw must miss.
	run.projectiles.clear()
	run._shoot(m, run.player_pos - (m["pos"] as Vector2))
	var dir := (run.player_pos - (m["pos"] as Vector2)).normalized()
	run.player_pos += dir.orthogonal() * 140.0
	for i in 120:
		run._step_projectiles(STEP)
	_check(run.hp == hit_hp, "an orb must MISS a hero who stepped aside, hp %d -> %d" % [hit_hp, run.hp])


## The data row for a face in the act-0 pool. A helper rather than an index, because the pool
## order comes from the converter.
func _row_with_face(face: String) -> Dictionary:
	for row in _data.monsters_for_theme(0):
		if str(row.get("face", "")) == face:
			return row
	return {}


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
	# ...and the reach has to read as a real step: bodies touch at 62 px, a target whose rim
	# crosses the drawn circle stands HIT_REACH away, and that must be a whole body off contact.
	_check(SurvivorRun.HIT_REACH - min_gap >= SurvivorRun.BODY_RADIUS,
		"the reach must be a visible step beyond contact, got %.1f against contact %.1f"
			% [SurvivorRun.HIT_REACH, min_gap])
	print("  measured: hero_gap=%.1f pair_gap=%.1f (min %.1f)" % [worst_hero, worst_pair, min_gap])


## The drawn circle is the promise: a target whose BODY touches it is hit, one that is still
## outside is not. Jan's report was that the hero only swung at point-blank, which is exactly what
## a CENTRE-based check against a 31 px body looks like on screen.
func _test_reach_is_the_drawn_circle() -> void:
	_log("  section: reach_is_the_drawn_circle")
	var inside := _fresh()
	inside.monsters.clear()
	inside._spawn_one()
	var m: Dictionary = inside.monsters[0]
	m["speed"] = 0.0
	var hp_before := int(m["hp"])
	var gap := SurvivorRun.HIT_REACH - 1.0
	m["pos"] = inside.player_pos + Vector2(gap, 0)
	for _i in 2:
		m["pos"] = inside.player_pos + Vector2(gap, 0)
		inside.step(STEP, Vector2.ZERO)
	_check(int(m["hp"]) < hp_before,
		"a body whose rim touches the drawn circle must be hit at gap %.1f" % gap)

	var outside := _fresh()
	outside.monsters.clear()
	outside._spawn_one()
	var m2: Dictionary = outside.monsters[0]
	m2["speed"] = 0.0
	var hp2 := int(m2["hp"])
	var far := SurvivorRun.HIT_REACH + 3.0
	for _i in 10:
		m2["pos"] = outside.player_pos + Vector2(far, 0)
		outside.step(STEP, Vector2.ZERO)
	_check(int(m2["hp"]) == hp2,
		"a body fully outside the circle must NOT be hit at gap %.1f" % far)


## The weapon's OWN pace, and two hands that are genuinely independent.
##
## The slice before this shipped ONE constant 0.85 s for every weapon, so a 700 ms scimitar and a
## 1580 ms two-hander swung identically and the whole `swingMs` column in the item table was
## decoration. The off hand was not read at all. Both are asserted here on the two things that
## are visible on screen: how often each hand lands, and that each hand stamps its own animation.
func _test_weapon_pace_and_two_hands() -> void:
	_log("  section: weapon_pace_and_two_hands")
	var equip: Dictionary = _state.equip()
	# SLOW in the main hand, FAST in the off hand: if the two hands shared a clock the off hand
	# could never land more often than the main one.
	equip["weapon"] = "blade_shortSword"
	equip["shield"] = "blade_scimitar"
	var run := _fresh()
	_check(not run.off_weapon.is_empty(), "a dual-wielding class must read the OFF hand weapon")
	_check(run.main_swing > run.off_swing,
		"each hand swings at its own weapon's pace: main %.3f s vs off %.3f s"
			% [run.main_swing, run.off_swing])
	var dex_total := int(_state.hero().get("attrDex", 0)) \
		+ int(Progression._equip_attr(equip, _find_item, "dex"))
	var want := float(Progression.swing_time(run.rng, run.main_weapon, dex_total, 0)) / 1000.0
	_check(absf(run.main_swing - want) < 0.002,
		"the main interval must come from swing_time: want %.3f got %.3f" % [want, run.main_swing])

	run.monsters.clear()
	run._spawn_one()
	run._spawn_one()
	var a: Dictionary = run.monsters[0]
	var b: Dictionary = run.monsters[1]
	for m in [a, b]:
		m["hp"] = 999999
		m["max_hp"] = 999999
		m["speed"] = 0.0
		m["ranged"] = false
		m["dmg_min"] = 0
		m["dmg_max"] = 0
	var main_hits := 0
	var off_hits := 0
	for _i in 180:
		# ⚠️  BOTH bodies are IN FRONT of a hero who never walks (facing = RIGHT, see
		# `SurvivorRun.FACING_MIN_DOT`). The off hand used to be aimed at a body at -70 px, which
		# is behind him now and can no longer be hit at all — the test would be measuring the
		# facing rule instead of the two clocks.
		a["pos"] = run.player_pos + Vector2(70, 30)
		b["pos"] = run.player_pos + Vector2(70, -30)
		run.step(STEP, Vector2.ZERO)
		for n in run.numbers:
			match str(n["kind"]):
				"hit", "crit":
					main_hits += 1
				"hit_off":
					off_hits += 1
		run.numbers.clear()
	_check(main_hits > 0 and off_hits > 0,
		"both hands must land blows: main %d off %d" % [main_hits, off_hits])
	_check(off_hits > main_hits,
		"the FASTER weapon must land more often: off %d vs main %d" % [off_hits, main_hits])
	_check(run.swing_age_off >= 0.0,
		"the off hand must stamp its OWN animation age, or the screen draws one arc twice")
	# The two arcs must point at DIFFERENT bodies. Both are in front now, so the two directions
	# are merely DIFFERENT, not opposite — one direction twice is a mirror, not a second weapon.
	_check(run.swing_dir_off.dot(run.swing_dir) < 0.9,
		"the off hand must swing at its own target: %s vs %s"
			% [str(run.swing_dir), str(run.swing_dir_off)])
	_reset_kit()


## A two-handed weapon has no off hand and a LONGER arm. Both are rules, not cosmetics: the
## reach table is what makes a two-hander a different weapon rather than a bigger number.
func _test_two_hander_reach() -> void:
	_log("  section: two_hander_reach")
	var equip: Dictionary = _state.equip()
	equip["weapon"] = "blade_shortSword"
	equip["shield"] = null
	var one := _fresh()
	_check(absf(one.reach_main - SurvivorRun.ATTACK_RANGE) < 0.01,
		"a one-handed blade reaches the drawn ATTACK_RANGE, got %.1f" % one.reach_main)

	equip["weapon"] = "blade2h_greatSword"
	var two := _fresh()
	_check(two.off_weapon.is_empty(), "a two-handed weapon leaves NO off hand")
	_check(two.reach_main > one.reach_main + 5.0,
		"a two-hander must reach noticeably further: %.1f vs %.1f"
			% [two.reach_main, one.reach_main])

	# A body the two-hander can reach and the one-hander cannot: the ONLY way to prove the reach
	# table is live is a gap that falls between the two circles.
	var gap := one.reach_main + SurvivorRun.MON_RADIUS + 3.0
	var far_hit := _hit_once_at(two, gap)
	var near_miss := _hit_once_at(one, gap)
	_check(far_hit, "the two-hander must hit a body at gap %.1f" % gap)
	_check(not near_miss, "a one-hander must NOT hit a body at gap %.1f" % gap)
	_reset_kit()


## Puts one stationary, harmless body at `gap` and reports whether a swing landed within 4 frames.
func _hit_once_at(run: SurvivorRun, gap: float) -> bool:
	run.monsters.clear()
	run._spawn_one()
	var m: Dictionary = run.monsters[0]
	m["hp"] = 999999
	m["max_hp"] = 999999
	m["speed"] = 0.0
	m["ranged"] = false
	m["dmg_min"] = 0
	m["dmg_max"] = 0
	var hp_before := int(m["hp"])
	for _i in 4:
		m["pos"] = run.player_pos + Vector2(gap, 0)
		run.step(STEP, Vector2.ZERO)
	return int(m["hp"]) < hp_before


## Walking had no number of its own before this slice. The BASE must be slower than the 168 the
## first pass shipped (a bonus against an already-fast walk is not felt), and a `moveSpeed` roll
## must reach the actual step, not just the tooltip.
func _test_move_speed_boots() -> void:
	_log("  section: move_speed_boots")
	_check(SurvivorRun.HERO_BASE_SPEED < 168.0,
		"the base walk must be slower than the old 168, got %.1f" % SurvivorRun.HERO_BASE_SPEED)
	_reset_kit()
	var slow := _fresh()
	_check(slow.speed_pct == 0, "no boots = no bonus, got %d %%" % slow.speed_pct)

	var boots: Dictionary = _data.item("boots_boots").duplicate(true)
	boots["id"] = "test_boots_fast"
	boots["moveSpeed"] = 20
	_state.register_loot_item(boots)
	_state.equip()["boots"] = "test_boots_fast"
	var fast := _fresh()
	_check(fast.speed_pct == 20, "a +20 %% boot must reach the run, got %d" % fast.speed_pct)
	_check(absf(fast.hero_speed() - SurvivorRun.HERO_BASE_SPEED * 1.2) < 0.01,
		"walk speed must be base * 1.2, got %.2f" % fast.hero_speed())
	var start := fast.player_pos
	fast.step(STEP, Vector2(1, 0))
	_check(absf((fast.player_pos.x - start.x) - SurvivorRun.HERO_BASE_SPEED * 1.2 * STEP) < 0.01,
		"the bonus must be WALKED, not only printed")
	# The cap holds: a hand-made +90 % boot cannot make the hero a projectile.
	boots["moveSpeed"] = 90
	_state.register_loot_item(boots)
	var capped := _fresh()
	_check(capped.speed_pct == SurvivorRun.MAX_SPEED_PCT,
		"move speed must cap at %d %%, got %d" % [SurvivorRun.MAX_SPEED_PCT, capped.speed_pct])
	_reset_kit()


## The boot affix has to be ROLLABLE, and it has to be one group so two speed lines never stack.
func _test_boots_roll_speed_affix() -> void:
	_log("  section: boots_roll_speed_affix")
	var groups := {}
	for a in ItemGen.EXTRA_AFFIXES:
		groups[int(a.get("group", -1))] = true
	_check(groups.size() == 1,
		"every speed tier must share ONE affix group, got %d" % groups.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var base: Dictionary = _data.item("boots_boots")
	var rolled := 0
	var total := 200
	for _i in total:
		var it: Dictionary = _gen.generate(base, "rare", 30, 30, rng)
		# One line, one value: a second speed affix would sum into a bigger number here.
		if int(it.get("moveSpeed", 0)) > 0:
			rolled += 1
	_check(rolled > 0, "%d rare boots at ilvl 30 must roll movement speed at least once" % total)
	print("  measured: boots_with_speed=%d/%d" % [rolled, total])


## Puts the class starting kit back, because every test above mutates the SAME save.
func _reset_kit() -> void:
	var equip: Dictionary = _state.equip()
	equip["weapon"] = "blade_shortSword"
	equip["shield"] = null
	equip["boots"] = null
	equip["gloves"] = null


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


## A pack is a DISCOVERY, not a clock: nothing wakes while the hero stands in his clearing, one
## pack wakes when he walks into the next cell, and the area ends only when every cell has been
## emptied. This section is the whole area model in three steps.
func _test_pack_discovery() -> void:
	_log("  section: pack_discovery")
	var run := _fresh(4242)
	run.max_hp = 999999
	run.hp = 999999
	run.defense = 999
	# 1. Standing still is not a spawn: 60 s in the clearing leaves the area asleep.
	for _i in 60 * 60:
		run.step(STEP, Vector2.ZERO)
	_check(run.monsters.is_empty() and run.wave == 0,
		"a hero who stands still must not be fed enemies: alive=%d wave=%d" % [run.monsters.size(), run.wave])

	# 2. Walking into a cell wakes exactly that pack — and only that one.
	var z: Dictionary = run.zones[0]
	var target: Vector2 = z["centre"]
	# Standing where a player actually arrives: inside the cell, ~250 px off its centre.
	run.player_pos = target + Vector2(0, 250)
	run.step(STEP, Vector2.ZERO)
	var members: int = (z["members"] as Array).size()
	_check(bool(z["active"]), "walking into a cell must wake its pack")
	_check(run.monsters.size() == members,
		"the woken pack must be exactly its members: %d vs %d" % [run.monsters.size(), members])
	_check(run.wave == 1, "waking one pack is wave 1, got %d" % run.wave)
	# No pop: every body has to arrive from OUTSIDE the phone screen (390x844, half = 195/422).
	for m in run.monsters:
		var d: float = (m["pos"] as Vector2).distance_to(run.player_pos)
		_check(d >= SurvivorRun.WAKE_MIN_DIST - 2.0,
			"a pack must wake off screen, %s is %.1f away" % [str(m["name"]), d])
	# A woken pack is the ONLY source: no trickle may arrive on top of it.
	var after_wake := run.monsters.size()
	for _i in 10 * 60:
		run.step(STEP, Vector2.ZERO)
	_check(run.monsters.size() <= mini(after_wake, SurvivorRun.MAX_ALIVE),
		"no monster may arrive from off screen: %d > %d" % [run.monsters.size(), after_wake])

	# 3. Every pack dead = the area is cleared, and the run ends by itself.
	for zz in run.zones:
		if not bool(zz["active"]):
			continue
		for id in zz["ids"]:
			for i in range(run.monsters.size() - 1, -1, -1):
				if int(run.monsters[i]["id"]) == int(id):
					run.monsters.remove_at(i)
	for _i in int((SurvivorRun.CLEAR_DELAY + 0.5) / STEP):
		run.step(STEP, Vector2.ZERO)
	_check(run.cleared_zones() >= 1, "a visited, emptied cell must count as cleared")
	_check(not run.finished or run.outcome == "cleared",
		"the area must only end as 'cleared', outcome='%s'" % run.outcome)
	_check(not run.finished,
		"an UNVISITED pack must keep the area open — the run ended with cells still asleep")


## A kill pays XP, and enough XP levels the hero UP — the run is going to REPLACE the duel, so
## a fight that pays no experience is the whole progression missing.
func _test_kills_award_xp() -> void:
	_log("  section: kills_award_xp")
	var run := _fresh(2024)
	var hero: Dictionary = _state.hero()
	hero["xp"] = 0
	hero["level"] = 2
	var before := int(hero.get("xp", 0))
	run.monsters.clear()
	run._spawn_one()
	var m: Dictionary = run.monsters[0]
	m["hp"] = 1
	m["ranged"] = false
	var ticks := 0
	while run.kills == 0 and ticks < 600:
		m["pos"] = run.player_pos + Vector2(SurvivorRun.ATTACK_RANGE * 0.5, 0)
		run.step(STEP, Vector2.ZERO)
		ticks += 1
	_check(run.kills >= 1, "the seeded monster must die so the XP can be measured")
	_check(int(run.xp_gained) > 0, "a kill must pay XP, xp_gained=%d" % int(run.xp_gained))
	var after := int(hero.get("xp", 0))
	_check(after >= before, "the hero's XP must not go down: %d -> %d" % [before, after])
	# Enough XP buys a level. Level 2 needs 80 XP; a level also pays 5 attribute points.
	var attr_before := int(hero.get("attrPoints", 0))
	run._award_xp(500)
	_check(int(hero.get("level", 2)) > 2, "500 XP must buy at least one level, level=%d" % int(hero["level"]))
	_check(int(hero.get("attrPoints", 0)) > attr_before, "a level must pay attribute points")
	_check(int(run.levels_gained) >= 1, "the run must count the levels it bought")


# ============================================================================ facing & spells

## Jan, Nov 2026: a swing needs the body in REACH **and** in FRONT. Attacking backwards while
## running away was the exploit being closed, so the section pins both halves: a body behind an
## untouched hero is never hit, and the same body IS hit the moment he walks toward it.
func _test_facing_gate() -> void:
	_log("  section: facing_gate")
	var run := _fresh(31337)
	run.monsters.clear()
	run._spawn_one()
	var m: Dictionary = run.monsters[0]
	m["hp"] = 999999
	m["max_hp"] = 999999
	m["speed"] = 0.0
	m["ranged"] = false
	m["dmg_min"] = 0
	m["dmg_max"] = 0
	_check(run.facing == Vector2.RIGHT, "a hero who never walked faces RIGHT, got %s" % str(run.facing))
	var hp0 := int(m["hp"])
	for _i in 120:
		# Well inside the reach, straight BEHIND him.
		m["pos"] = run.player_pos + Vector2(-70, 0)
		run.step(STEP, Vector2.ZERO)
	_check(int(m["hp"]) == hp0,
		"a body BEHIND the hero must not be hit: %d -> %d" % [hp0, int(m["hp"])])

	# Walking at it turns him: the same body, the same gap, now in front.
	for _i in 120:
		m["pos"] = run.player_pos + Vector2(70, 0)
		run.step(STEP, Vector2.ZERO)
	_check(int(m["hp"]) < hp0, "a body in FRONT must be hit")

	# And the turn is the MOVEMENT's: running right then left flips the facing, and the body
	# that was hittable is behind again.
	var hp1 := int(m["hp"])
	m["pos"] = run.player_pos + Vector2(70, 0)
	for _i in 30:
		run.step(STEP, Vector2(-1, 0))
	var facing_left: bool = run.facing.x < -0.9
	_check(facing_left, "walking left must turn the hero left, got %s" % str(run.facing))
	var hp2 := int(m["hp"])
	for _i in 120:
		m["pos"] = run.player_pos + Vector2(70, 0)
		run.step(STEP, Vector2.ZERO)
	_check(int(m["hp"]) == hp2,
		"after turning away, a body at +X must not be hit: %d -> %d" % [hp2, int(m["hp"])])
	_log("  measured: hp %d -> %d -> %d" % [hp0, hp1, hp2])


## The spell bar is the duel's rule, unchanged: a spell with no talent point in it does not
## exist as a button, and an invested one really lands its damage in the run.
func _test_spells_in_the_run() -> void:
	_log("  section: spells_in_the_run")
	var levels: Dictionary = _state.data.get("talentLevels", {})
	levels.erase("barbarian_thunderClap")
	levels.erase("barbarian_doubleSwing")
	var run := _fresh(4711)
	_check(run.spell_bar().is_empty(),
		"no invested talent = no spell buttons, got %d" % run.spell_bar().size())

	levels["barbarian_thunderClap"] = 3
	levels["barbarian_doubleSwing"] = 1
	var bar: Array = run.spell_bar()
	var ids: Array = []
	for e in bar:
		ids.append(str((e as Dictionary)["id"]))
	_check(ids.has("thunderClap") and ids.has("doubleSwing"),
		"invested spells must appear in the bar, got %s" % str(ids))
	_check(not ids.has("pummel"), "an uninvested spell must NOT appear in the bar")

	# Thunder Clap needs a body in reach and in front; a refused cast costs nothing.
	var mana0 := float(run.mana)
	var refused: Dictionary = run.cast_spell("thunderClap")
	_check(not bool(refused["ok"]), "casting with nothing in reach must be refused")
	_check(absf(float(run.mana) - mana0) < 0.01, "a refused cast must cost no mana")

	run.monsters.clear()
	run._spawn_one()
	var m: Dictionary = run.monsters[0]
	m["hp"] = 999999
	m["max_hp"] = 999999
	m["speed"] = 0.0
	m["ranged"] = false
	m["dmg_min"] = 0
	m["dmg_max"] = 0
	m["pos"] = run.player_pos + Vector2(60, 0)
	var hp0 := int(m["hp"])
	var res: Dictionary = run.cast_spell("thunderClap")
	_check(bool(res["ok"]), "an invested spell must cast: %s" % str(res.get("message", "")))
	_check(int(res["damage"]) > 0, "Thunder Clap must deal damage, got %d" % int(res["damage"]))
	_check(int(m["hp"]) < hp0, "the damage must reach the body")
	_check(float(run.mana) < mana0, "a cast must cost mana: %.1f -> %.1f" % [mana0, float(run.mana)])
	_check(int(m.get("slow_ms", 0)) > 0, "Thunder Clap must slow the body it hit")
	_check(int(_state.hero().get("mana", 0)) == int(floor(float(run.mana))),
		"the mana pool must reach the SAVE (hero.mana=%d, run=%d)"
			% [int(_state.hero().get("mana", 0)), int(floor(float(run.mana)))])

	# The GCD is a real clock, not a message: a second cast in the same instant is refused.
	var again: Dictionary = run.cast_spell("thunderClap")
	_check(not bool(again["ok"]), "the global cooldown must refuse a second cast")
	for _i in 40:
		run.step(STEP, Vector2.ZERO)
	_check(run.spell_gcd_ms == 0, "the GCD must tick down on the run's own step")

	levels.erase("barbarian_thunderClap")
	levels.erase("barbarian_doubleSwing")


## Whirlwind is the duel's flurry with the pause removed: a sequence of PS presses on a deadline,
## a wrong press ending it, and the strikes landing on EVERY body in reach (a spin, not a swing).
func _test_whirlwind_flurry() -> void:
	_log("  section: whirlwind_flurry")
	var levels: Dictionary = _state.data.get("talentLevels", {})
	levels["barbarian_whirlwind"] = 2
	var run := _fresh(90210)
	run.monsters.clear()
	for _i in 2:
		run._spawn_one()
	for m in run.monsters:
		(m as Dictionary)["hp"] = 999999
		(m as Dictionary)["max_hp"] = 999999
		(m as Dictionary)["speed"] = 0.0
		(m as Dictionary)["ranged"] = false
		(m as Dictionary)["dmg_min"] = 0
		(m as Dictionary)["dmg_max"] = 0
	var a: Dictionary = run.monsters[0]
	var b: Dictionary = run.monsters[1]
	a["pos"] = run.player_pos + Vector2(40, 0)
	b["pos"] = run.player_pos + Vector2(40, 20)
	var res: Dictionary = run.cast_spell("whirlwind")
	_check(bool(res["ok"]), "Whirlwind must cast with a body in reach: %s" % str(res.get("message", "")))
	_check(run.whirlwind_open(), "the flurry must be open after the cast")
	_check(run.ww_dirs.size() == 3 + 2, "3 + lv strikes, got %d" % run.ww_dirs.size())
	# A cast while the flurry runs is refused: one prompt at a time.
	_check(not bool(run.cast_spell("thunderClap")["ok"]),
		"no second spell may start while a flurry is open")

	var hp_a := int(a["hp"])
	var hp_b := int(b["hp"])
	var key := run.whirlwind_prompt()
	var strike: Dictionary = run.answer_whirlwind(key)
	_check(bool(strike["ok"]), "the shown key must land a strike")
	_check(int(a["hp"]) < hp_a or int(b["hp"]) < hp_b,
		"a flurry strike must hit the bodies in reach (a spin, not a single swing)")

	# A WRONG press ends it, and what was landed stays landed.
	var wrong := "square" if run.whirlwind_prompt() != "square" else "tri"
	var bad: Dictionary = run.answer_whirlwind(wrong)
	_check(str(bad["result"]) == "fail", "a wrong press must end the flurry")
	_check(not run.whirlwind_open(), "the flurry must be closed after a wrong press")

	# The deadline is a real clock on the run's own step.
	run.start_whirlwind(["tri", "circle"], 500)
	_check(run.whirlwind_open(), "a fresh flurry must be open")
	var ticks := int(0.6 / STEP)
	for _i in ticks:
		run.step(STEP, Vector2.ZERO)
	_check(not run.whirlwind_open(), "the strike deadline must expire on the run's clock")
	var verdict: Dictionary = run.take_whirlwind_result()
	_check(str(verdict["feedback"]) == "fail", "an expired flurry must report fail")

	levels.erase("barbarian_whirlwind")


# ============================================================================ bolts & effects

## Jan, Nov 2026: "kouzla, která jsou mířena na konkrétního nepřítele, například Thunder Bolt,
## musí letět na nejbližšího nepřítele ve směru kam hrdina kouká." Three claims, and all three
## are rules, not looks: the bolt EXISTS in the air, it lands on the body it was aimed at, and a
## body behind the hero is never the target however close it stands.
func _test_bolt_flies_at_the_aimed_body() -> void:
	_log("  section: bolt_flies_at_the_aimed_body")
	var levels: Dictionary = _state.data.get("talentLevels", {})
	levels["barbarian_thunderBolt"] = 2
	var run := _fresh(555)
	run.monsters.clear()
	run._spawn_one()
	var m: Dictionary = run.monsters[0]
	m["hp"] = 999999
	m["max_hp"] = 999999
	m["speed"] = 0.0
	m["ranged"] = false
	m["dmg_min"] = 0
	m["dmg_max"] = 0
	# Well out of weapon reach, straight ahead: the bolt is the only thing that can reach it.
	m["pos"] = run.player_pos + Vector2(200, 0)
	var hp0 := int(m["hp"])
	var res: Dictionary = run.cast_spell("thunderBolt")
	_check(bool(res["ok"]), "Thunder Bolt must cast with a body in front: %s"
		% str(res.get("message", "")))
	_check(run.bolts.size() == 1, "the bolt must EXIST in the air, got %d" % run.bolts.size())
	_check(int(m["hp"]) == hp0, "a flying bolt must not damage on the frame it is cast")
	# It travels and lands on its own clock.
	for _i in 40:
		m["pos"] = run.player_pos + Vector2(200, 0)
		run.step(STEP, Vector2.ZERO)
	_check(int(m["hp"]) < hp0,
		"the bolt must reach the body: %d -> %d" % [hp0, int(m["hp"])])
	_check(int(m.get("stun_ms", 0)) > 0, "a landed bolt must stun")

	# A body BEHIND is never the target, however close it stands.
	run.monsters.clear()
	run._spawn_one()
	var back: Dictionary = run.monsters[0]
	back["hp"] = 999999
	back["max_hp"] = 999999
	back["pos"] = run.player_pos + Vector2(-60, 0)
	_check(not bool(run.cast_spell("thunderBolt")["ok"]),
		"a body behind the hero must not be a bolt target")

	# With one behind and one ahead, the aim is the one AHEAD — the nearest is the one in front.
	run._spawn_one()
	var front: Dictionary = run.monsters[1]
	front["hp"] = 999999
	front["max_hp"] = 999999
	front["pos"] = run.player_pos + Vector2(240, 0)
	run.spell_gcd_ms = 0
	run.spell_cooldowns.clear()
	run.mana = float(run.max_mana)
	_check(bool(run.cast_spell("thunderBolt")["ok"]), "the aimed cast must fire")
	_check(run.bolts.size() >= 1, "the bolt must be in the air")
	if run.bolts.size() >= 1:
		var vel: Vector2 = run.bolts[run.bolts.size() - 1]["vel"]
		_check(vel.x > 0.0, "the bolt must fly FORWARD (vx>0), got %s" % str(vel))
	levels.erase("barbarian_thunderBolt")


## The duel's spell effects, carried over: a shout is a WAVE of rings leaving the hero, a Thunder
## Clap a flash plus lightning, and every effect expires on the run's own clock (an effect that
## never ages is a permanent white rectangle on the screen).
func _test_spell_effects() -> void:
	_log("  section: spell_effects")
	var levels: Dictionary = _state.data.get("talentLevels", {})
	levels["barbarian_battleShout"] = 2
	levels["barbarian_thunderClap"] = 2
	var run := _fresh(606)
	run.monsters.clear()
	run.effects.clear()
	var res: Dictionary = run.cast_spell("battleShout")
	_check(bool(res["ok"]), "Battle Shout must cast (no target needed)")
	var rings := 0
	for e in run.effects:
		if str(e["kind"]) == "ring":
			rings += 1
			_check(str(e["colour"]).to_lower().begins_with("#e74c3c"),
				"Battle Shout is the RED wave in the duel, got %s" % str(e["colour"]))
	_check(rings >= 1, "Battle Shout must spawn its ring wave, got %d effects" % run.effects.size())

	# ...and it expires, or every shout would leave its rings on the arena forever.
	for _i in int(2.0 / STEP):
		run.step(STEP, Vector2.ZERO)
	_check(run.effects.is_empty(), "effects must expire on the run's clock, %d left"
		% run.effects.size())

	# The clap: a white flash plus lightning cracks.
	run.monsters.clear()
	run._spawn_one()
	var m: Dictionary = run.monsters[0]
	m["hp"] = 999999
	m["max_hp"] = 999999
	m["speed"] = 0.0
	m["ranged"] = false
	m["dmg_min"] = 0
	m["dmg_max"] = 0
	m["pos"] = run.player_pos + Vector2(50, 0)
	run.spell_gcd_ms = 0
	run.spell_cooldowns.clear()
	run.mana = float(run.max_mana)
	_check(bool(run.cast_spell("thunderClap")["ok"]), "Thunder Clap must cast")
	var kinds: Array = []
	for e in run.effects:
		kinds.append(str(e["kind"]))
	_check(kinds.has("flash"), "Thunder Clap must flash")
	_check(kinds.has("cracks"), "Thunder Clap must crack")
	levels.erase("barbarian_battleShout")
	levels.erase("barbarian_thunderClap")


## A SECOND FINGER must be able to cast while the first one holds the stick. Jan: "kouzla musí
## jít vykouzlit i za běhu." Asserted on touch INDICES, because a single `_pointer_down` flag is
## exactly what made this impossible: the second press looked like the duplicate event this
## engine synthesises from every touch and was dropped.
func _test_cast_while_running() -> void:
	_log("  section: cast_while_running")
	var levels: Dictionary = _state.data.get("talentLevels", {})
	levels["barbarian_heroicStrike"] = 1
	var screen = SurvivorScreen.new()
	root.add_child(screen)
	screen.size = Vector2(390, 844)
	screen.setup(_state, _find_item, _loot, 0)
	# Finger 1 takes the stick and drags.
	screen._on_press(Vector2(120, 640), 1)
	screen._on_drag(Vector2(170, 640), 1)
	_check(screen._pointer_down and screen._stick_vec.x > 0.8,
		"the first finger must own the stick, vec=%s" % str(screen._stick_vec))
	# Finger 2 presses a spell button — and the stick must keep running.
	var btn: Dictionary = screen._spell_buttons[0]
	screen._on_press(btn["centre"], 2)
	_check(screen.run.heroic_queued,
		"a second finger must be able to cast while the stick is held")
	_check(screen._pointer_down and screen._stick_vec.x > 0.8,
		"casting must NOT stop the run: vec=%s" % str(screen._stick_vec))
	# Lifting the spell finger must not stop the hero either.
	screen._on_release(2)
	_check(screen._pointer_down, "releasing the spell finger must not stop the run")
	screen._on_release(1)
	_check(not screen._pointer_down and screen._stick_vec == Vector2.ZERO,
		"releasing the stick finger must stop the hero")
	screen.queue_free()
	levels.erase("barbarian_heroicStrike")


# ============================================================================ screen

## The spell column and the flurry row are TOUCH targets, and a button that also plants the
## movement stick would make the hero run in the direction of a cast. Asserted through the
## screen's own press handler, because that is the path a thumb takes.
func _test_screen_spell_buttons() -> void:
	_log("  section: screen_spell_buttons")
	var levels: Dictionary = _state.data.get("talentLevels", {})
	levels["barbarian_heroicStrike"] = 1
	levels["barbarian_whirlwind"] = 1
	var screen = SurvivorScreen.new()
	root.add_child(screen)
	screen.size = Vector2(390, 844)
	screen.setup(_state, _find_item, _loot, 0)
	_check(screen._spell_buttons.size() >= 2,
		"invested spells must produce buttons, got %d" % screen._spell_buttons.size())

	# A tap on a spell button must NOT plant the stick.
	var first: Dictionary = screen._spell_buttons[0]
	screen._on_press(first["centre"])
	_check(not screen._pointer_down or screen._stick_origin == Vector2.ZERO,
		"a spell button must not start the movement stick")
	screen._on_release()

	# The buttons must stay inside the screen and clear of the potion button.
	for b in screen._spell_buttons:
		var c: Vector2 = b["centre"]
		_check(c.x + SurvivorScreen.SPELL_BUTTON_RADIUS < 390.0 and c.y > 60.0,
			"a spell button must be on screen, got %s" % str(c))
		_check(c.distance_to(screen._potion_centre)
			> SurvivorScreen.SPELL_BUTTON_RADIUS + SurvivorScreen.BUTTON_RADIUS + 8.0,
			"a spell button must clear the potion button, gap %.1f"
				% c.distance_to(screen._potion_centre))

	# The flurry row owns the input while it runs: a press anywhere else is swallowed, so a
	# spell cannot be cast with the thumb that was answering the press.
	screen.run.start_whirlwind(["tri", "circle"], 1500)
	var before: int = screen.run.ww_index
	screen._on_press(Vector2(60, 700))
	_check(screen.run.ww_index == before, "a press outside the flurry row must not answer it")
	_check(not screen._pointer_down, "the flurry must swallow the press (no stick)")
	var ww: Dictionary = screen._ww_buttons[0]
	screen._on_press(ww["centre"])
	_check(screen.run.ww_index == before + 1 or not screen.run.whirlwind_open(),
		"a press on the shown symbol must answer the flurry")
	screen._on_release()
	screen.run.whirlwind_timeout()

	screen.queue_free()
	levels.erase("barbarian_heroicStrike")
	levels.erase("barbarian_whirlwind")


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

	# ⚠️  A HIDDEN SCREEN MUST NOT KEEP THE FIGHT RUNNING. Leaving the run used to leave `_process`
	# alive, so the arena kept spawning behind the town and the player was dragged back when the
	# hero died. Asserted on `is_processing()`, which is what actually stops the clock.
	screen.show()
	_check(screen.is_processing(), "a visible survivor screen must run its clock")
	var t_before: float = screen.run.elapsed
	for i in 30:
		screen._process(1.0 / 60.0)
	var t_moved: bool = screen.run.elapsed > t_before
	screen.hide()
	_check(not screen.is_processing(), "a HIDDEN survivor screen must stop its clock")
	t_before = screen.run.elapsed
	for i in 30:
		if screen.is_processing():
			screen._process(1.0 / 60.0)
	_check(t_moved, "a visible screen must advance the run")
	_check(absf(screen.run.elapsed - t_before) < 0.0001,
		"a hidden screen must not advance the run (%.3f -> %.3f)" % [t_before, screen.run.elapsed])

	# ...and the death is reported ONCE, not once per frame.
	var deaths := [0]
	screen.run_finished.connect(func(_o): deaths[0] += 1)
	screen.show()
	screen.setup(_state, _find_item, _loot, 0)
	screen.run.hp = 0
	screen.run.finished = true
	screen.run.outcome = "dead"
	for i in 20:
		screen._process(1.0 / 60.0)
	_check(deaths[0] == 1, "a death must be reported exactly once, got %d" % deaths[0])

	screen.queue_free()
