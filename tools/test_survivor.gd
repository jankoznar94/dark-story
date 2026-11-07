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
const ActionWheel := preload("res://scripts/combat/action_wheel.gd")
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
	_test_held_attack()
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
	_test_pack_makeup()
	_test_kills_award_xp()
	_test_facing_gate()
	_test_aim_retargets()
	_test_spells_in_the_run()
	_test_whirlwind_flurry()
	_test_bolt_flies_at_the_aimed_body()
	_test_spell_effects()
	_test_screen_action_wheel()
	_test_cast_while_running()
	_test_screen_gesture_and_disc()
	_test_world_draw_transform()
	_test_edge_cull_uses_world_units()
	_test_monster_roster_by_zone()
	_test_strength_ladder()
	_test_refresh_from_save()
	_test_screen_hero_button()
	_test_screen_map()

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


## The one factory for a run. `attacking` is what the SCREEN would write every frame: Jan's new
## rule is that the hero only swings while the attack button is held, so a section that measures
## something else (movement, bodies, a thrower's stand-off) must NOT have the hero walking into a
## pack on his own. Default FALSE — the honest starting state — and the sections that need a fight
## opt in.
func _fresh(seed_value: int = 12345, attacking: bool = false) -> SurvivorRun:
	var run := SurvivorRun.new()
	run.setup(_state, _find_item, _loot, 0, seed_value)
	run.attack_held = attacking
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
	# The corridor holds one SPAWN CELL per stop along its centreline (8..34), each a known
	# quantity before it wakes, and every one of them stands on FLOOR.
	_check(run.zones.size() >= 8 and run.zones.size() <= 34,
		"the corridor must hold 8..34 cells, got %d" % run.zones.size())
	for z in run.zones:
		_check(run.walkable(z["centre"] as Vector2, SurvivorRun.MON_RADIUS),
			"a pack centre must stand on floor: %s" % str(z["centre"]))
		var n: int = (z["members"] as Array).size()
		_check(n >= SurvivorRun.PACK_MIN and n <= SurvivorRun.PACK_MAX,
			"a pack is %d..%d bodies, got %d" % [SurvivorRun.PACK_MIN, SurvivorRun.PACK_MAX, n])
		for m in z["members"]:
			var d: float = (m["pos"] as Vector2).distance_to(z["centre"] as Vector2)
			# A stray pair stands FURTHER out than the old 104 px formation on purpose: two
			# separate wanderers, not a group pressed together.
			var reach: float = SurvivorRun.ZONE_JITTER
			if str(m.get("role", "normal")) == "normal":
				reach = SurvivorRun.STRAY_GAP_MAX + SurvivorRun.ZONE_JITTER
			_check(d <= reach + 1.0,
				"a pack member must stand inside its own cell: %.1f > %.1f" % [d, reach])
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
	# THE ROCK holds. He may slide along it, but he can never end up standing in it — the area is a
	# carved corridor, not a rectangle with an inset, so the old corner test is now a floor test.
	var run3 := _fresh()
	var start3 := run3.player_pos
	for _i in 600:
		run3.step(STEP, Vector2(-1, -1))
	_check(run3.walkable(run3.player_pos, SurvivorRun.HERO_RADIUS),
		"the hero must never stand in the rock: %s" % str(run3.player_pos))
	_check(run3.player_pos.distance_to(start3) > 40.0,
		"the hero must still be able to walk out of the start clearing, moved %.1f"
			% run3.player_pos.distance_to(start3))


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
	# The button is HELD for this section — nothing swings otherwise.
	var run := _fresh(12345, true)
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


## Jan, Nov 2026 — the Diablo 2 Resurrected rule. The hero does NOT attack on his own: a swing
## happens only while the attack button (or an offensive spell) is HELD. While it is held the game
## picks the target in the direction the player looks, prefers the nearly-dead body, and walks the
## hero into reach — the assist, because a phone has no second cursor.
func _test_held_attack() -> void:
	_log("  section: held_attack")
	var idle := SurvivorRun.new()
	idle.setup(_state, _find_item, _loot, 0, 999)
	_check(not idle.attack_held and idle.held_spell == "" and idle.target_id == -1,
		"a fresh run must start with NOTHING held")
	idle.monsters.clear()
	idle._spawn_one()
	var m: Dictionary = idle.monsters[0]
	m["hp"] = 999999
	m["max_hp"] = 999999
	m["speed"] = 0.0
	m["ranged"] = false
	m["dmg_min"] = 0
	m["dmg_max"] = 0
	var hp0 := int(m["hp"])
	for _i in 180:
		m["pos"] = idle.player_pos + Vector2(90, 0)
		idle.step(STEP, Vector2.ZERO)
	_check(int(m["hp"]) == hp0,
		"an UNHELD attack must not swing: %d -> %d" % [hp0, int(m["hp"])])
	_check(idle.target_id == -1, "no attack held = no target picked")

	# Held: the same body is hit, and it is the one the assist chose.
	idle.attack_held = true
	var ticks := 0
	while int(m["hp"]) == hp0 and ticks < 180:
		m["pos"] = idle.player_pos + Vector2(90, 0)
		idle.step(STEP, Vector2.ZERO)
		ticks += 1
	_check(int(m["hp"]) < hp0, "holding the attack must swing")
	_check(idle.target_id == int(m["id"]), "the held attack must pick the body in front")

	# The ranking: a nearly-dead body a little further away beats a healthy one in the face.
	var pick := _fresh(4242, true)
	pick.monsters.clear()
	pick._spawn_one()
	pick._spawn_one()
	var near: Dictionary = pick.monsters[0]
	var weak: Dictionary = pick.monsters[1]
	for mm in [near, weak]:
		mm["speed"] = 0.0
		mm["ranged"] = false
		mm["dmg_min"] = 0
		mm["dmg_max"] = 0
		mm["max_hp"] = 1000
	near["hp"] = 1000
	weak["hp"] = 100
	near["pos"] = pick.player_pos + Vector2(90, 0)
	weak["pos"] = pick.player_pos + Vector2(200, 0)
	pick.facing = Vector2.RIGHT
	pick.step(STEP, Vector2.ZERO)
	_check(pick.target_id == int(weak["id"]),
		"the assist must finish the nearly-dead body first: picked %d, weak is %d"
			% [int(pick.target_id), int(weak["id"])])

	# A body BEHIND a WALKING hero is not a candidate: the direction he walks is what he means.
	var back := _fresh(555, true)
	back.monsters.clear()
	back._spawn_one()
	var b: Dictionary = back.monsters[0]
	b["hp"] = 999999
	b["max_hp"] = 999999
	b["speed"] = 0.0
	b["ranged"] = false
	b["dmg_min"] = 0
	b["dmg_max"] = 0
	b["pos"] = back.player_pos + Vector2(-90, 0)
	# Walking AWAY while holding the attack: the body stays behind and is never hit.
	var hp_back := int(b["hp"])
	for _i in 60:
		back.player_pos = back.nearest_floor_point(SurvivorRun.WORLD * 0.5)
		b["pos"] = back.player_pos + Vector2(-90, 0)
		back.facing = Vector2.RIGHT
		back.step(STEP, Vector2(1, 0))
	_check(int(b["hp"]) == hp_back,
		"a body behind a WALKING hero must not be hit: %d -> %d" % [hp_back, int(b["hp"])])

	# ...but a hero who STANDS with the attack held and everything behind him must not freeze: the
	# assist turns him. Without it a thumb holding the attack could never turn the hero at all,
	# because the facing only ever changed by walking.
	var turn := _fresh(556, true)
	turn.monsters.clear()
	turn._spawn_one()
	var t: Dictionary = turn.monsters[0]
	t["hp"] = 999999
	t["max_hp"] = 999999
	t["speed"] = 0.0
	t["ranged"] = false
	t["dmg_min"] = 0
	t["dmg_max"] = 0
	t["pos"] = turn.player_pos + Vector2(-90, 0)
	turn.facing = Vector2.RIGHT
	turn.step(STEP, Vector2.ZERO)
	_check(turn.target_id == int(t["id"]),
		"a STANDING hero must turn to a body behind him instead of freezing")
	_check(turn.facing.x < -0.9, "the turn must be a real turn, facing=%s" % str(turn.facing))

	# The ASSIST walks him into reach and stops at the WEAPON's arm, not at contact.
	var walk := _fresh(777, true)
	walk.monsters.clear()
	walk._spawn_one()
	var w: Dictionary = walk.monsters[0]
	w["hp"] = 999999
	w["max_hp"] = 999999
	w["speed"] = 0.0
	w["ranged"] = false
	w["dmg_min"] = 0
	w["dmg_max"] = 0
	w["pos"] = walk.player_pos + Vector2(260, 0)
	var d0: float = (w["pos"] as Vector2).distance_to(walk.player_pos)
	for _i in 70:
		walk.step(STEP, Vector2.ZERO)
	var d1: float = (w["pos"] as Vector2).distance_to(walk.player_pos)
	var stop_at: float = walk.reach_main + SurvivorRun.MON_RADIUS
	_check(d1 < d0 - 60.0, "holding the attack must close the distance: %.1f -> %.1f" % [d0, d1])
	_check(absf(d1 - stop_at) < 8.0,
		"the assist must stop AT the weapon's reach (%.1f), got %.1f" % [stop_at, d1])

	# ...but the PLAYER's stick always outranks the assist's step.
	var steer := _fresh(888, true)
	steer.monsters.clear()
	steer._spawn_one()
	var s: Dictionary = steer.monsters[0]
	s["hp"] = 999999
	s["max_hp"] = 999999
	s["speed"] = 0.0
	s["ranged"] = false
	s["dmg_min"] = 0
	s["dmg_max"] = 0
	s["pos"] = steer.player_pos + Vector2(260, 0)
	var pos_before: Vector2 = steer.player_pos
	for _i in 40:
		steer.step(STEP, Vector2(0, -1))
	_check(steer.player_pos.y < pos_before.y - 40.0,
		"the stick must move the hero, got %s" % str(steer.player_pos - pos_before))
	_check(absf(steer.player_pos.x - pos_before.x) < 3.0,
		"a sideways walk must not be turned into an approach: dx=%.1f"
			% (steer.player_pos.x - pos_before.x))

	# A HELD offensive spell repeats itself on the rules' own cooldowns. Double Swing is the one
	# with a 0 s cooldown (its pace IS the weapon's), so the GCD is all that paces it — which is
	# exactly the rule under test: hold = "cast whenever it is ready", never a faster rule.
	var levels: Dictionary = _state.data.get("talentLevels", {})
	levels["barbarian_doubleSwing"] = 1
	_state.equip()["shield"] = "blade_scimitar"
	var cast_run := _fresh(1111)
	cast_run.monsters.clear()
	cast_run._spawn_one()
	var c: Dictionary = cast_run.monsters[0]
	c["hp"] = 999999
	c["max_hp"] = 999999
	c["speed"] = 0.0
	c["ranged"] = false
	c["dmg_min"] = 0
	c["dmg_max"] = 0
	cast_run.held_spell = "doubleSwing"
	var casts := 0
	for _i in 120:
		c["pos"] = cast_run.player_pos + Vector2(80, 0)
		cast_run.step(STEP, Vector2.ZERO)
		for e in cast_run.drain_events():
			if str(e) == "cast":
				casts += 1
	_check(casts >= 2, "a held spell must repeat on its cooldowns, got %d casts" % casts)
	_check(int(c["hp"]) < 999999, "a held spell must land its damage")
	_check(not cast_run.attack_held, "the spell must not also swing the weapon")
	levels.erase("barbarian_doubleSwing")
	_reset_kit()


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
	# On FLOOR 400 px up the CORRIDOR. `+400 px straight up` is inside rock on the assembled chunk
	# maps (the corridor turns every 8 cells), and `nearest_floor_point` pulled the body in to
	# ~180 px — inside the thrower's dead band, so it stood still and the section measured nothing.
	# `_spawn_point` walks the cell field instead, which is where "400 px up the corridor" really is.
	m["pos"] = run._spawn_point(400.0, -PI * 0.5)

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
	var inside := _fresh(12345, true)
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

	var outside := _fresh(12345, true)
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
	var run := _fresh(12345, true)
	_check(not run.off_weapon.is_empty(), "a dual-wielding class must read the OFF hand weapon")
	var dex_total := int(_state.hero().get("attrDex", 0)) \
		+ int(Progression._equip_attr(equip, _find_item, "dex"))
	_check(run.off_swing < float(Progression.swing_time(run.rng, run.main_weapon, dex_total, 0)) / 1000.0,
		"the faster weapon must still be read as the faster one: off %.3f s" % run.off_swing)
	# The PAIR's beat is the HARMONIC mean of the two hands (both rates summed), so `main_swing`
	# is no longer the main weapon's own number.
	var m_s := float(Progression.swing_time(run.rng, run.main_weapon, dex_total, 0)) / 1000.0
	var o_s := float(Progression.swing_time(run.rng, run.off_weapon, dex_total, 0)) / 1000.0
	var want := maxf(SurvivorRun.PAIR_FLOOR, 1.0 / (1.0 / m_s + 1.0 / o_s))
	_check(absf(run.main_swing - want) < 0.002,
		"the pair's interval must be the harmonic mean of the two hands: want %.3f got %.3f"
			% [want, run.main_swing])

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
	var order: Array = []
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
					order.append("main")
				"hit_off":
					off_hits += 1
					order.append("off")
		run.numbers.clear()
	_check(main_hits > 0 and off_hits > 0,
		"both hands must land blows: main %d off %d" % [main_hits, off_hits])
	# STRICT ALTERNATION: the hero never strikes with the same hand twice in a row, and never with
	# both at once. That is what D2 does and what Jan asked for.
	_check(order.size() >= 4, "the pair must land a few blows, got %d" % order.size())
	var flips := 0
	for i in range(1, order.size()):
		if order[i] != order[i - 1]:
			flips += 1
	_check(flips == order.size() - 1,
		"the hands must ALTERNATE, got %s" % str(order))
	_check(off_hits > 0 and main_hits > 0 and absi(off_hits - main_hits) <= 2,
		"both hands share one clock, so neither may dominate: main %d off %d"
			% [main_hits, off_hits])
	_check(run.swing_age_off >= 0.0,
		"the off hand must stamp its OWN animation age, or the screen draws one arc twice")
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
	run.attack_held = true
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

	# 3. Every pack dead = the area is CLEARED, and the run does NOT end by itself: Jan, Nov
	# 2026 — "vítězství je, že dojdu na konec lokace, projdu východem do další a tam si vezmu
	# waypoint". The old assertion said the opposite; inverting it is the feature, deleting it
	# would hide the day the ending comes back.
	for zz in run.zones:
		if not bool(zz["active"]):
			continue
		for id in zz["ids"]:
			for i in range(run.monsters.size() - 1, -1, -1):
				if int(run.monsters[i]["id"]) == int(id):
					run.monsters.remove_at(i)
	# Every ASLEEP cell is emptied too, or `cleared_zones()` never reaches `zones.size()`.
	for zz in run.zones:
		zz["active"] = true
		zz["cleared"] = true
		zz["ids"] = []
	for _i in 120:
		run.step(STEP, Vector2.ZERO)
	_check(run.cleared_zones() >= 1, "a visited, emptied cell must count as cleared")
	_check(run.area_cleared, "an emptied area must be REPORTED as cleared")
	_check(not run.finished,
		"an emptied area must NOT end the run — the exit is the only way on")
	_check(run.outcome == "", "an emptied area must set no outcome, got '%s'" % run.outcome)


## The MAKEUP of a cell: singles by default, champions as a group of one kind, an elite with its
## minions. Jan, Nov 2026 — this is the variety ask, and the two things that can silently go
## wrong are (a) the default drifting back into a pile of bodies and (b) a "champion" pack
## whose members are different kinds, which is a mob, not a champion pack.
func _test_pack_makeup() -> void:
	_log("  section: pack_makeup")
	var seeds := [1, 7, 42, 101, 777, 1234, 4242, 90210, 31337, 65535, 8, 9, 10, 11, 12, 13]
	var normal := 0
	var champions := 0
	var elites := 0
	var stray_pairs := 0
	for s in seeds:
		var run := _fresh(int(s))
		var elite_cells := 0
		for z in run.zones:
			var kind := str(z.get("kind", "normal"))
			var members: Array = z["members"]
			match kind:
				"elite":
					elite_cells += 1
					elites += 1
					_check(members.size() == SurvivorRun.ELITE_MINIONS + 1,
						"an elite cell is 1 leader + %d minions, got %d"
							% [SurvivorRun.ELITE_MINIONS, members.size()])
					var leader: Dictionary = {}
					var minions := 0
					for m in members:
						if str(m.get("role", "")) == "elite":
							leader = m
						elif str(m.get("role", "")) == "minion":
							minions += 1
					_check(not leader.is_empty(), "an elite cell has no leader")
					_check(minions == SurvivorRun.ELITE_MINIONS,
						"an elite cell has %d minions, want %d" % [minions, SurvivorRun.ELITE_MINIONS])
					if not leader.is_empty():
						_check(float(leader.get("hp_mult", 0.0)) == SurvivorRun.ELITE_HP_MULT,
							"the elite must carry its HP multiplier")
						_check(float(leader.get("xp_mult", 0.0)) == SurvivorRun.ELITE_XP_MULT,
							"the elite must pay %sx XP" % SurvivorRun.ELITE_XP_MULT)
						_check(int(leader.get("loot_grade", 0)) == 2,
							"the elite must drop from the elite table")
						_check(str(leader.get("elite_name", "")) != "",
							"the elite must have a name from the D2 tables")
						var affix: Dictionary = leader.get("affix", {})
						_check(not affix.is_empty(), "the elite must carry an affix")
						# The aura is the one affix that changes OTHER bodies. Its minions must
						# carry the bonus, or the aura is a label with no rule behind it.
						var aura := float(affix.get("auraDmgMult", 1.0)) \
							if bool(affix.get("aura", false)) else 1.0
						for m in members:
							if str(m.get("role", "")) != "minion":
								continue
							_check(float(m.get("dmg_mult", 0.0)) == aura,
								"a minion must carry the aura bonus %.2f, got %.2f"
									% [aura, float(m.get("dmg_mult", 0.0))])
							_check(float(m.get("xp_mult", 0.0)) == SurvivorRun.ELITE_XP_MULT,
								"a minion pays the elite's %sx XP" % SurvivorRun.ELITE_XP_MULT)
				"champion":
					champions += 1
					_check(members.size() >= SurvivorRun.CHAMPION_MIN
							and members.size() <= SurvivorRun.CHAMPION_MAX,
						"a champion pack is %d..%d bodies, got %d"
							% [SurvivorRun.CHAMPION_MIN, SurvivorRun.CHAMPION_MAX, members.size()])
					var face := str((members[0]["row"] as Dictionary).get("face", ""))
					for m in members:
						_check(str((m["row"] as Dictionary).get("face", "")) == face,
							"a champion pack is ONE kind — a mixed pack is a mob")
						_check(str(m.get("role", "")) == "champion", "a champion cell holds champions")
						_check(float(m.get("xp_mult", 0.0)) == SurvivorRun.CHAMPION_XP_MULT,
							"a champion pays %sx XP" % SurvivorRun.CHAMPION_XP_MULT)
				_:
					normal += 1
					if members.size() == 2:
						stray_pairs += 1
						var gap: float = (members[0]["pos"] as Vector2).distance_to(
							members[1]["pos"] as Vector2)
						_check(gap >= SurvivorRun.STRAY_GAP_MIN - 1.0,
							"two strays must stand APART (%.1f < %.1f) — Jan's whole point"
								% [gap, SurvivorRun.STRAY_GAP_MIN])
		_check(elite_cells <= 1, "seed %d has %d elite cells, at most 1 is allowed"
			% [int(s), elite_cells])

	_log("    cells: normal=%d (pairs=%d) champion=%d elite=%d"
		% [normal, stray_pairs, champions, elites])
	_check(normal > champions + elites,
		"the DEFAULT must be the stray, not the group: normal=%d special=%d"
			% [normal, champions + elites])
	_check(champions > 0 and elites > 0,
		"16 seeds produced no champion/elite cell at all — the roles are not being dealt")

	# A woken champion is really stronger than the same row as a stray: same kind, more HP.
	var champ_run := SurvivorRun.new()
	champ_run.setup(_state, _find_item, _loot, 0, 4242)
	var row: Dictionary = _pick_any_row(champ_run)
	if not row.is_empty():
		var plain := champ_run._make_monster(row, Vector2.ZERO, 5, {})
		var champ := champ_run._make_monster(row, Vector2.ZERO, 5,
			{"role": "champion", "hp_mult": SurvivorRun.CHAMPION_HP_MULT,
			"dmg_mult": SurvivorRun.CHAMPION_DMG_MULT, "xp_mult": SurvivorRun.CHAMPION_XP_MULT,
			"loot_grade": 1})
		_check(int(champ["hp"]) > int(plain["hp"]),
			"a champion must have MORE hp than a stray of the same row: %d vs %d"
				% [int(champ["hp"]), int(plain["hp"])])
		_check(int(champ["dmg_max"]) > int(plain["dmg_max"]),
			"a champion must hit HARDER than a stray of the same row")
		_check(str(champ["name"]).contains("Champion"), "a champion's name must say so")
		_check(int(champ["loot_grade"]) == 1 and int(plain["loot_grade"]) == 0,
			"the loot grade must travel on the monster, not be guessed at the drop")


## Any monster row of the current act, for the strength comparison above.
func _pick_any_row(run: SurvivorRun) -> Dictionary:
	for tier in [1, 2, 3, 4]:
		var row: Dictionary = run._pick_row(tier)
		if not row.is_empty():
			return row
	return {}



## A kill pays XP, and enough XP levels the hero UP — the run is going to REPLACE the duel, so
## a fight that pays no experience is the whole progression missing.
func _test_kills_award_xp() -> void:
	_log("  section: kills_award_xp")
	var run := _fresh(2024, true)
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
## Jan, Nov 2026: a swing needs the body in the direction the hero is pointed. Since the attack
## became a HELD action the gate means one thing only — **a WALKING hero does not hit what is
## behind him** — because a standing hero holding the attack is turned to the nearest body by the
## assist (a thumb on the attack has no way to turn him otherwise).
##
## Walking away from a pack while holding the attack therefore still costs nothing: the pack stays
## behind and stays unhit. That is the exploit this section exists to keep closed.
func _test_facing_gate() -> void:
	_log("  section: facing_gate")
	var run := _fresh(31337, true)
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
	# WALKING away from a body right behind him: the facing is right, the body is left, no swing.
	for _i in 120:
		run.player_pos = run.nearest_floor_point(SurvivorRun.WORLD * 0.5)
		m["pos"] = run.player_pos + Vector2(-70, 0)
		run.facing = Vector2.RIGHT
		run.step(STEP, Vector2(1, 0))
	_check(int(m["hp"]) == hp0,
		"a body BEHIND a walking hero must not be hit: %d -> %d" % [hp0, int(m["hp"])])

	# Standing still with the attack held: the assist turns him, so the same body IS hit.
	run.player_pos = run.nearest_floor_point(SurvivorRun.WORLD * 0.5)
	m["pos"] = run.player_pos + Vector2(-70, 0)
	run.facing = Vector2.RIGHT
	for _i in 120:
		m["pos"] = run.player_pos + Vector2(-70, 0)
		run.step(STEP, Vector2.ZERO)
	_check(int(m["hp"]) < hp0, "a standing hero must turn and fight — the assist owns the facing")
	_check(run.facing.x < -0.9, "the assist must have turned him, facing=%s" % str(run.facing))

	# The facing is the MOVEMENT's whenever nothing is held: running left then right flips it.
	#
	# ⚠️  The attack must be RELEASED for this half: while it is held the assist owns the facing,
	# so the assertion would measure the assist instead of the walk.
	run.attack_held = false
	# Nothing left to aim at: with a body on the field the ASSIST owns the facing, and this half
	# measures the walk (see `_update_target`).
	run.monsters.clear()
	for _i in 30:
		run.step(STEP, Vector2(-1, 0))
	_check(run.facing.x < -0.9, "walking left must turn the hero left, got %s" % str(run.facing))
	for _i in 30:
		run.step(STEP, Vector2(1, 0))
	_check(run.facing.x > 0.9, "walking right must turn him back, got %s" % str(run.facing))
	_log("  measured: hp %d -> %d" % [hp0, int(m["hp"])])


## Jan, Nov 2026: "když hráč drží útok a během toho mění směr, tak by se měl target změnit. Pokud
## stojí třeba tři nepřátelé vedle sebe a hráč přejez zleva doprava, tak by se měl útok přesměrovat
## na toho vpravo."
##
## The aim is its own field for exactly this reason: while `facing` follows the target (it has to,
## the swing must land where the hero looks), the AIM is what the stick writes, and the picker ranks
## against it. One field for both made the half-plane self-fulfilling and the assist could never
## re-pick.
func _test_aim_retargets() -> void:
	_log("  section: aim_retargets")
	var run := _fresh(4242, true)
	run.monsters.clear()
	# Three bodies side by side to the RIGHT of the hero, all in reach, none moving or hitting.
	var ids: Array = []
	for i in 3:
		run._spawn_one()
		var m: Dictionary = run.monsters[i]
		m["hp"] = 999999
		m["max_hp"] = 999999
		m["speed"] = 0.0
		m["ranged"] = false
		m["dmg_min"] = 0
		m["dmg_max"] = 0
		ids.append(int(m["id"]))

	# Push the stick UP-RIGHT: the top body is the one on the line the thumb points down.
	for _i in 12:
		run.player_pos = run.nearest_floor_point(SurvivorRun.WORLD * 0.5)
		for i in 3:
			run.monsters[i]["pos"] = run.player_pos + Vector2(110.0, (float(i) - 1.0) * 90.0)
		run.step(STEP, Vector2(1, -1))
	_check(run.target_id == ids[0],
		"pushing up-right must target the top body (%d), got %d" % [ids[0], run.target_id])
	_check(run.facing.y < -0.3, "the hero must turn to it, facing=%s" % str(run.facing))

	# ...and slide the thumb DOWN: the same gesture must move the attack to the bottom body.
	for _i in 12:
		run.player_pos = run.nearest_floor_point(SurvivorRun.WORLD * 0.5)
		for i in 3:
			run.monsters[i]["pos"] = run.player_pos + Vector2(110.0, (float(i) - 1.0) * 90.0)
		run.step(STEP, Vector2(1, 1))
	_check(run.target_id == ids[2],
		"pushing down-right must re-target the bottom body (%d), got %d" % [ids[2], run.target_id])
	_check(run.facing.y > 0.3, "the hero must have turned with it, facing=%s" % str(run.facing))

	# Standing still (no stick) must NOT wander: the aim stays where the player left it.
	run.aim = Vector2.RIGHT
	for _i in 6:
		run.player_pos = run.nearest_floor_point(SurvivorRun.WORLD * 0.5)
		for i in 3:
			run.monsters[i]["pos"] = run.player_pos + Vector2(110.0, (float(i) - 1.0) * 90.0)
		run.step(STEP, Vector2.ZERO)
	_check(run.target_id == ids[1],
		"with the stick released the middle body (dead ahead) must be the target, got %d"
			% run.target_id)


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
	# Finger 1 takes the walking stick (RIGHT half) and drags.
	screen._on_press(Vector2(250, 600), 1)
	screen._on_drag(Vector2(300, 600), 1)
	_check(screen._pointer_down and screen._stick_vec.x > 0.8,
		"the first finger must own the stick, vec=%s" % str(screen._stick_vec))
	# Finger 2 uses the ACTION WHEEL (bottom-LEFT, fixed) and pushes UP past the resting disc — the
	# attack wedge. The stick must keep running: one thumb each, two separate indices.
	var wc: Vector2 = screen.wheel_centre()
	screen._on_press(wc, 2)
	screen._on_drag(wc + Vector2(0, -(screen.wheel_inner() + 14.0)), 2)
	_check(screen.run.attack_held,
		"a second finger must be able to attack while the stick is held")
	_check(screen._pointer_down and screen._stick_vec.x > 0.8,
		"the wheel must NOT stop the run: vec=%s" % str(screen._stick_vec))
	# Lifting the wheel finger must not stop the hero either, and must let the attack go.
	screen._on_release(2)
	_check(screen._pointer_down, "releasing the wheel finger must not stop the run")
	_check(not screen.run.attack_held, "releasing the wheel finger must let the attack go")
	screen._on_release(1)
	_check(not screen._pointer_down and screen._stick_vec == Vector2.ZERO,
		"releasing the stick finger must stop the hero")
	screen.queue_free()
	levels.erase("barbarian_heroicStrike")


# ============================================================================ screen

## THE ACTION WHEEL and the flurry row are TOUCH targets. Jan, Nov 2026: "Kouzla a lektvary
## zabírají příliš mnoho místa a hlavně hráč se musí neustále koukat kam kliká … levý joystick, kdy
## podle toho kterým směrem hráč táhne, podle toho se použije kouzlo/lektvar/útok."
##
## So there are no buttons to find any more: a press anywhere in the LEFT half opens the wheel, a
## drag PAST the ring picks a sector, and the sectors hold whatever the player bound. Asserted
## through the screen's own press/drag handlers, because that is the path a thumb takes.
func _test_screen_action_wheel() -> void:
	_log("  section: screen_action_wheel")
	var levels: Dictionary = _state.data.get("talentLevels", {})
	levels["barbarian_heroicStrike"] = 1
	levels["barbarian_whirlwind"] = 1
	# A save without bindings: the wheel is DERIVED (attack, potion, then the bar's spells).
	_state.data.erase("actionWheel")
	var screen = SurvivorScreen.new()
	root.add_child(screen)
	screen.size = Vector2(390, 844)
	screen.setup(_state, _find_item, _loot, 0)
	_check(screen._wheel_slots.size() == ActionWheel.SLOTS,
		"the wheel must have %d sectors, got %d" % [ActionWheel.SLOTS, screen._wheel_slots.size()])
	_check(screen.wheel_action(0) == ActionWheel.ATTACK,
		"the default wheel must start with ATTACK, got '%s'" % screen.wheel_action(0))
	_check(screen.wheel_action(1) == ActionWheel.POTION,
		"the default wheel must hold the potion next, got '%s'" % screen.wheel_action(1))
	_check(screen.wheel_action(2) == "heroicStrike",
		"the default wheel must carry the class's spells, got '%s'" % screen.wheel_action(2))

	# THE WHEEL IS PERMANENT AND FIXED: it sits in the bottom-left before any thumb arrives, and a
	# press never moves it (Jan: "měl by být viditelný permanentně. I s výsečemi.").
	var centre: Vector2 = screen.wheel_centre()
	_check(centre.x < 200.0 and centre.y > 120.0 and centre.y < screen.size.y - 100.0,
		"the wheel must live in the bottom-left, got %s" % str(centre))
	_check(centre.y + screen.wheel_outer() <= screen.size.y - 40.0,
		"the wheel must clear the HP/mana bars, bottom=%s" % str(centre.y + screen.wheel_outer()))

	# A press in the LEFT half but OFF the wheel must not arm anything: the sectors are fixed, so a
	# stray thumb cannot "open" a wheel at its own position any more.
	screen._on_press(Vector2(60, 300), 4)
	_check(screen._wheel_index == -1, "a press off the wheel must not own it")
	screen._on_release(4)

	# A press ON the wheel starts it, and must NOT walk the hero.
	screen._on_press(centre, 1)
	_check(screen._wheel_index == 1 and screen._stick_index == -1,
		"a press on the wheel must open it and not the stick")
	_check(screen.wheel_centre() == centre, "the wheel must not move under the thumb")
	_check(not screen._attack_held, "an untouched wheel must hold nothing")

	# Inside the resting disc nothing happens — a resting thumb is not an action.
	screen._on_drag(centre + Vector2(0, screen.wheel_inner() - 10.0), 1)
	_check(screen._wheel_slot == -1, "a thumb inside the disc must not activate a wedge")
	_check(not screen._attack_held, "a thumb inside the disc must not hold the attack")

	# Into the UP wedge, the whole wedge counting, not an icon: a thumb 10 px past the disc lands
	# on the attack, and an attack is HELD for as long as it stays.
	screen._on_drag(centre + Vector2.from_angle(ActionWheel.centre_angle(0))
		* (screen.wheel_inner() + 10.0), 1)
	_check(screen._wheel_slot == 0, "up must be wedge 0, got %d" % screen._wheel_slot)
	_check(screen._attack_held and screen.run.attack_held,
		"the attack wedge must HOLD the attack")
	_check(screen._wheel_vec.length() <= screen.wheel_outer() + 0.01,
		"the knob must clamp to the ring, got %.1f" % screen._wheel_vec.length())

	# Coming back into the disc lets go, without lifting the thumb.
	screen._on_drag(centre, 1)
	_check(screen._wheel_slot == -1 and not screen.run.attack_held,
		"coming back inside the disc must let the attack go")

	# A SPELL IS NOT FIRED ON ENTRY any more (Jan): dragging into its wedge only ARMS it.
	var spell_dir: Vector2 = Vector2.from_angle(ActionWheel.centre_angle(2))
	screen.run.heroic_queued = false
	screen._on_drag(centre + spell_dir * (screen.wheel_inner() + 10.0), 1)
	_check(screen._wheel_slot == 2, "the spell must be in wedge 2, got %d" % screen._wheel_slot)
	_check(not screen.run.heroic_queued, "a spell wedge must NOT fire while the thumb is down")
	_check(not screen._attack_held, "a spell wedge must not hold the attack")

	# Drifting back into the disc before lifting CANCELS it — the accidental case Jan named.
	screen._on_drag(centre, 1)
	screen._on_release(1)
	_check(not screen.run.heroic_queued,
		"a thumb that left the wedge before lifting must fire nothing")

	# Drag in, then LIFT: the release is the activation, exactly once per gesture.
	screen._on_press(centre, 2)
	screen._on_drag(centre + spell_dir * (screen.wheel_outer() - 8.0), 2)
	_check(not screen.run.heroic_queued, "still nothing while the thumb is down")
	screen._on_release(2)
	_check(screen.run.heroic_queued, "lifting the thumb in a spell wedge must fire it")
	_check(screen._wheel_index == -1 and screen._wheel_slot == -1,
		"lifting the thumb must close the wheel")
	_check(not screen.run.attack_held, "lifting must leave no held action behind")

	# The wheel never plants the movement stick.
	_check(not screen._pointer_down, "the wheel must never move the hero")

	# THE BIND PANEL — Jan's own requirement: any action on any direction.
	screen._open_bind()
	_check(screen._bind_open and screen._bind_rects.size() == ActionWheel.SLOTS,
		"the panel must list every sector, got %d rows" % screen._bind_rects.size())
	var row0: Dictionary = screen._bind_rects[0]
	screen._on_press((row0["rect"] as Rect2).get_center())
	_check(screen._bind_pick == 0, "tapping a row must open its action list")
	# Every action the hero could use is listable, plus the empty sector and the two built-ins.
	var names: Array = []
	for r in screen._bind_rects:
		names.append(str(r["action"]))
	_check(ActionWheel.EMPTY in names and ActionWheel.ATTACK in names and ActionWheel.POTION in names,
		"the list must offer empty, attack and potion: %s" % str(names))
	_check("heroicStrike" in names, "the list must offer the class's spells: %s" % str(names))
	# Bind Whirlwind to sector 0 (up) — and it must MOVE there from wherever it was.
	var ww_row := -1
	for i in screen._bind_rects.size():
		if str(screen._bind_rects[i]["action"]) == "whirlwind":
			ww_row = i
	_check(ww_row >= 0, "whirlwind must be offered")
	if ww_row >= 0:
		screen._on_press((screen._bind_rects[ww_row]["rect"] as Rect2).get_center())
		_check(screen.wheel_action(0) == "whirlwind",
			"sector 0 must now hold whirlwind, got '%s'" % screen.wheel_action(0))
		var dupes := 0
		for i in screen._wheel_slots.size():
			if str(screen._wheel_slots[i]) == "whirlwind":
				dupes += 1
		_check(dupes == 1, "an action must live in ONE sector, found %d" % dupes)
		_check(_state.data.get("actionWheel") is Array,
			"the binding must reach the SAVE, not just the screen")
	screen._on_press(Vector2(240, 620))  # a press in the field must not answer the panel
	_check(screen._bind_pick == -1 or screen._bind_open, "the panel must swallow field presses")
	screen._on_press(screen._bind_back_rect.get_center())
	screen._on_press(screen._bind_back_rect.get_center())
	_check(not screen._bind_open, "the back button must close the panel")

	# A saved binding must be re-read on the next run (a run does not fall back to the default).
	screen.setup(_state, _find_item, _loot, 0)
	_check(screen.wheel_action(0) == "whirlwind",
		"a saved binding must survive the next run, got '%s'" % screen.wheel_action(0))
	_state.data.erase("actionWheel")

	# The flurry row owns the input while it runs: a press anywhere else is swallowed, so an
	# action cannot fire with the thumb that was answering the press.
	screen.run.start_whirlwind(["tri", "circle"], 1500)
	var before: int = screen.run.ww_index
	screen._on_press(Vector2(260, 700))
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
	screen._on_press(Vector2(250, 600))
	_check(screen._pointer_down and screen._stick_origin == Vector2(250, 600),
		"a press in the field must plant the stick at the finger")
	screen._on_drag(Vector2(340, 600))
	_check(screen._stick_vec.x > 0.9 and absf(screen._stick_vec.y) < 0.01,
		"a drag must produce a full-strength direction, got %s" % str(screen._stick_vec))
	screen._on_release()
	_check(not screen._pointer_down and screen._stick_vec == Vector2.ZERO,
		"releasing must stop the hero")

	# ...and the LEFT half is the action wheel, never the stick: the two thumbs must not fight over
	# the same gesture.
	screen._on_press(screen.wheel_centre())
	_check(screen._wheel_index == 0 and not screen._pointer_down and screen._stick_vec == Vector2.ZERO,
		"a left press must open the wheel, not the stick")
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


## The world half of `_draw()` runs under ONE zoom transform, and `draw_set_transform()` REPLACES
## that transform rather than nesting inside it. A "restore" to `Vector2.ONE` inside the world half
## therefore DROPS the zoom, and every prop then scrolls at a different rate than the ground.
##
## Measured on the real frame (tools/probe_zoom_scroll.gd): with the reset, a rock moved 200 px
## over ground that moved 164 px per 200 world px — Jan's "the rocks float". The zoom is 0.82, so
## the ratio between the two is exactly the bug.
##
## `_draw()` never runs under `--headless`, so no pixel test here can see it; the SOURCE can, and
## this is the only headless-checkable form of the rule.
func _test_world_draw_transform() -> void:
	_log("  section: world_draw_transform")
	var src := FileAccess.get_file_as_string("res://scripts/ui/survivor_screen.gd")
	_check(src != "", "the survivor screen's source must be readable")
	# Comments explain the old bug by quoting it, so only executable lines are scanned.
	var code := ""
	for line in src.split("\n"):
		if not line.strip_edges().begins_with("#"):
			code += line + "\n"
	_check(src.contains("func _world_xform()"), "the world transform must be one named matrix")
	_check(code.contains("draw_set_transform_matrix(_world_xform())"),
		"the world half must start from _world_xform(), not from a scale literal")
	_check(not code.contains("draw_set_transform(pos"),
		"a local draw must use _set_local(): draw_set_transform(pos, ...) drops the zoom")
	_check(not code.contains("draw_set_transform(Vector2(pos.x"),
		"a contact shadow must use _set_local(): a raw draw_set_transform drops the zoom")
	_check(not code.contains("draw_set_transform(Vector2(base_pos.x"),
		"the hero's shadow must use _set_local(): a raw draw_set_transform drops the zoom")
	# An identity reset is only legal when the code comes straight BACK to the world (the full-frame
	# flash) or hands over to the HUD, which must stay 1:1.
	var needle := "draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)"
	var identity := 0
	var at := code.find(needle)
	while at >= 0:
		identity += 1
		var tail := code.substr(at, 260)
		_check(tail.contains("_draw_hud()") or tail.contains("_set_world()"),
			"an identity reset must either hand over to the HUD or return via _set_world(): %s"
				% tail.strip_edges().left(70))
		at = code.find(needle, at + 1)
	_check(identity >= 1, "the HUD hand-over reset is missing entirely")


## Jan: "když chodím kolem okrajů oblasti, objekty ohraničující oblast různě mizí a zase se
## objevují. Všechny zaráz." The cull compared the camera-shifted prop position against the
## CANVAS size, while the world is drawn at `ZOOM` — so the real visible stretch of world is
## `size / ZOOM` and anything between the two lines was dropped while still on screen. The
## border is one row per side, so an entire side vanished at once.
##
## The predicate is asserted on its own numbers AND in the source: keeping the helper but
## not calling it would pass a numbers-only test on a build where the bug is back.
func _test_edge_cull_uses_world_units() -> void:
	_log("  section: edge_cull_uses_world_units")
	var view := Vector2(390.0, 844.0) / 0.82
	# The RIGHT wall sits on one x. 460 world px is at screen x 377 — clearly visible, and the
	# old canvas-based line (390+60=450) culled it.
	_check(SurvivorScreen.on_screen(Vector2(460.0, 400.0), 40.0, view),
		"a border prop 460 world px right of the camera is on screen and must not be culled")
	# The BOTTOM wall, measured on a clamped camera: y 933 -> screen 765. The old line was 904.
	_check(SurvivorScreen.on_screen(Vector2(200.0, 933.0), 40.0, view),
		"a border prop 933 world px below the camera is on screen and must not be culled")
	# Past the real edge it must still be culled, or the draw cost grows with the world.
	_check(not SurvivorScreen.on_screen(Vector2(600.0, 500.0), 40.0, view),
		"a prop wholly past the right edge must be culled")
	_check(not SurvivorScreen.on_screen(Vector2(-200.0, 500.0), 40.0, view),
		"a prop wholly behind the left edge must be culled")
	# ...and the prop's own footprint counts: a boulder whose centre is just past the edge but
	# whose body is still visible stays.
	_check(SurvivorScreen.on_screen(Vector2(500.0, 500.0), 40.0, view),
		"a boulder whose body still reaches the screen must not be culled for its centre")

	var src := FileAccess.get_file_as_string("res://scripts/ui/survivor_screen.gd")
	var code := ""
	for line in src.split("\n"):
		if not line.strip_edges().begins_with("#"):
			code += line + "\n"
	_check(code.contains("if not on_screen(pos, rx, view)"),
		"the patch cull must go through on_screen() with the WORLD view")
	_check(code.contains("if not on_screen(pos, extent, view)"),
		"the prop cull must go through on_screen() with the WORLD view")
	_check(not code.contains("pos.x > size.x + 60.0"),
		"the prop cull must not compare against the CANVAS size — the world is drawn at ZOOM")
	_check(not code.contains("pos.x > size.x + 180.0"),
		"the patch cull must not compare against the CANVAS size — the world is drawn at ZOOM")


# ============================================================================ new roster + ladder + refresh


## Jan, Nov 2026: "Teď se všude spawnují jen tři druhy monster z prvního aktu. V bestiáři jich máme
## pro 1. Akt 8. Postupně by se měli objevovat v jednotlivých lokacích."
##
## The pool follows the ZONE, not a fixed tier: zone 1 holds one kind, zone 8 all eight. Sampled
## through `_pick_row` itself, so a change to the pooling rule that only looks right fails here.
func _test_monster_roster_by_zone() -> void:
	_log("  section: monster_roster_by_zone")
	for act in _data.acts():
		var act_id := int(act.get("id", 0))
		var want_theme := int(act.get("theme", 0))
		var theme_run := _run_at(act_id, 0)
		_check(theme_run.act_theme() == want_theme,
			"act %d must spawn theme %d, got %d — the act INDEX is not the theme index"
				% [act_id + 1, want_theme, theme_run.act_theme()])
		_check(theme_run.monster_rows().size() == 8,
			"act %d must have the theme's 8 kinds, got %d" % [act_id + 1,
				theme_run.monster_rows().size()])
		for zone in [0, 3, 7, 9]:
			var want := mini(zone + 1, 8)
			var seen := _kinds_at(act_id, zone)
			_check(seen.size() == want,
				"act %d zone %d must spawn %d kinds, saw %d: %s"
					% [act_id + 1, zone + 1, want, seen.size(), ", ".join(seen)])
	# The first kind of the first zone is the act's own weakest one, and the LAST kind only shows
	# up in the deep half of the act's last zone — the old rule had all of act 1's eight kinds
	# available from the first cell.
	var first := _kinds_at(0, 0)
	_check(first.size() == 1 and first[0] == "Forest Imp",
		"act 1 zone 1 must hold only the Forest Imp, got %s" % ", ".join(first))
	var deep := _kinds_at(0, 9)
	_check(deep.has("Ent") and deep.has("Satyr"),
		"the deep zones must hold the act's heavy kinds, got %s" % ", ".join(deep))


## Which kinds a zone really rolls, over 300 packs. A pack standing in the far half of the zone
## may look one zone ahead (`_depth_for`), which is the peek the design wants — so the sample is
## taken at progress 0, the zone's own pool.
func _kinds_at(act_id: int, zone: int) -> Array:
	var run := _run_at(act_id, zone)
	var seen: Array = []
	for _i in 300:
		var row: Dictionary = run._pick_row(run._depth_for(0))
		var nm := str(row.get("name", ""))
		if not seen.has(nm):
			seen.append(nm)
	return seen


## The strength ladder is ONE curve over act * 10 + zone, and that is the whole point of it: the
## old model scaled by the act index alone, so walking from zone 1 to zone 10 of the same act
## changed nothing. Asserted on the SCALES, so a theme's mean HP cannot smuggle in a second curve.
func _test_strength_ladder() -> void:
	_log("  section: strength_ladder")
	var prev := -1.0
	for act in _data.acts():
		var act_id := int(act.get("id", 0))
		for zone in 10:
			var run := _run_at(act_id, zone)
			# A body of a theme's MEAN kind has exactly BASE * step^depth, whatever the theme is.
			var sc: Dictionary = run._strength_scales({"hp": 100.0, "dmg": 100.0})
			var absolute: float = float(sc["hp"]) * 100.0
			var want: float = SurvivorRun.STRENGTH_BASE_HP \
				* pow(1.0 + SurvivorRun.STRENGTH_HP_STEP, float(act_id * 10 + zone))
			_check(absf(absolute - want) < 0.01,
				"the ladder must read act*10+zone only: act %d zone %d gave %.2f, want %.2f"
					% [act_id + 1, zone + 1, absolute, want])
			_check(absolute > prev, "the ladder must climb at every step: %.2f <= %.2f"
				% [absolute, prev])
			prev = absolute
	# And the bodies themselves: the same act's last zone really is tougher than its first.
	for act in _data.acts():
		var act_id := int(act.get("id", 0))
		var shallow := _mean_hp(act_id, 0)
		var deep := _mean_hp(act_id, 9)
		_check(deep > shallow * 1.3,
			"act %d: the last zone must be visibly tougher than the first (%.0f vs %.0f)"
				% [act_id + 1, deep, shallow])
	# The first zone is the one Jan called too hard. It has to be BELOW the old flat number, which
	# for the imp was 60 HP of the table's own row (the run multiplied by 1 + act*0.35).
	var imp := _run_at(0, 0)._make_monster({"hp": 60, "dmgMin": 5, "dmgMax": 9}, Vector2.ZERO, 1, {})
	_check(int(imp["hp"]) < 60,
		"the first zone must open EASIER than the old 60 HP imp, got %d" % int(imp["hp"]))


func _mean_hp(act_id: int, zone: int) -> float:
	var run := _run_at(act_id, zone)
	var total := 0.0
	for _i in 300:
		var row: Dictionary = run._pick_row(run._depth_for(0))
		if row.is_empty():
			continue
		total += float(run._make_monster(row, Vector2.ZERO, 1, {})["hp"])
	return total / 300.0


## The character modal is reachable from the fight (Jan, Nov 2026). Equipping mid-run must reach
## the RUN: a weapon swapped in the pause really is the weapon the next swing uses, and a bigger
## armour really is a bigger pool — without a free full heal and without rebuilding the zone.
func _test_refresh_from_save() -> void:
	_log("  section: refresh_from_save")
	var run := _fresh(777)
	run.hp = 7
	var before_max: int = run.max_hp
	var before_dmg: int = run.dmg_max
	var equip: Dictionary = _state.equip()
	var old_weapon: Variant = equip.get("weapon")
	equip["weapon"] = "blade2h_greatSword"
	run.refresh_from_save()
	_check(run.dmg_max > before_dmg,
		"a bigger weapon must raise the swing damage: %d -> %d" % [before_dmg, run.dmg_max])
	_check(str(run.main_weapon.get("id", "")) == "blade2h_greatSword",
		"the hands must be re-read from the save, got '%s'" % str(run.main_weapon.get("id", "")))
	_check(run.hp == 7 and run.max_hp == before_max,
		"a weapon must not change the pool or heal: hp %d max %d -> hp %d max %d"
			% [7, before_max, run.hp, run.max_hp])

	# Armour with a VIT bonus: the pool grows and the hero gains exactly the difference, once.
	var armor := ""
	for row in _data.table("ITEMS", []):
		if str(row.get("slot", "")) == "armor":
			armor = str(row.get("id", ""))
			break
	if armor != "":
		equip["armor"] = armor
		var hp_before: int = run.hp
		var max_before: int = run.max_hp
		run.refresh_from_save()
		var gained: int = maxi(0, run.max_hp - max_before)
		var expected: int = mini(hp_before + gained, run.max_hp)
		_check(run.hp == expected,
			"equipping armour must add its pool as health once: hp %d -> %d, want %d"
				% [hp_before, run.hp, expected])
		equip.erase("armor")
	equip["weapon"] = old_weapon
	run.refresh_from_save()
	_check(run.dmg_max == before_dmg,
		"putting the old weapon back must restore the old damage, got %d" % run.dmg_max)


## A run of one act and one zone, with the world itself out of the way — the roster and the ladder
## are read off the RULES, not off a walked map.
func _run_at(act_id: int, zone: int) -> SurvivorRun:
	var run := SurvivorRun.new()
	run.setup(_state, _find_item, _loot, act_id, 4242 + act_id * 10 + zone, zone)
	return run


func _test_screen_map() -> void:
	_log("  section: screen_map")
	var screen = SurvivorScreen.new()
	root.add_child(screen)
	screen.size = Vector2(390, 844)
	screen.setup(_state, _find_item, _loot, 0)
	screen._layout_buttons()

	# The button must not share a rectangle with any other top-bar control and must be on screen.
	var rects := {"map": screen._map_rect, "exit": screen._exit_rect, "bind": screen._bind_rect,
		"hero": screen._hero_rect, "portal": screen._portal_rect}
	for a in rects:
		for b in rects:
			if str(a) >= str(b):
				continue
			_check(not (rects[a] as Rect2).intersects(rects[b] as Rect2),
				"the %s and %s buttons overlap: %s vs %s"
					% [a, b, str(rects[a]), str(rects[b])])
	_check(screen._map_rect.end.x <= 390.0 and screen._map_rect.end.y <= SurvivorScreen.TOP_BAR,
		"the map button must fit inside the top bar: %s" % str(screen._map_rect))

	# A tap opens it, and the fight STOPS behind it (a monster must not walk into a hero who is
	# reading a map).
	screen._on_press(screen._map_rect.get_center(), 0)
	_check(screen._map_open, "a tap on the Mapa button must open the map")
	_check(screen._paused and not screen.is_processing(), "the open map must pause the fight")
	_check(screen._map_tex != null, "the map sheet must be baked on open")
	_check(screen._map_rect.size.x > 100.0 and screen._map_rect.size.y > 100.0,
		"the map sheet must be big enough to read: %s" % str(screen._map_rect.size))

	# Only what he has walked: a cell that is not explored must not be painted.
	var run = screen.run
	var far := Vector2i(SurvivorRun.COLS - 2, SurvivorRun.ROWS - 2)
	_check(int(run.explored_cells[far.y * SurvivorRun.COLS + far.x]) == 0,
		"the far corner must still be unexplored for this check to mean anything")
	var img: Image = screen._map_tex.get_image()
	var px := int((float(far.x) + 0.5) * float(img.get_width()) / float(SurvivorRun.COLS))
	var py := int((float(far.y) + 0.5) * float(img.get_height()) / float(SurvivorRun.ROWS))
	var got := img.get_pixel(px, py)
	_check(got.is_equal_approx(SurvivorScreen.MAP_BG),
		"the map must not show an unexplored cell (%s shows %s)" % [str(far), str(got)])

	# A tap outside the sheet closes it and the clock comes back.
	screen._on_press(Vector2(5, 420), 0)
	_check(not screen._map_open, "a tap outside the sheet must close the map")
	_check(not screen._paused, "closing the map must resume the run")
	screen.queue_free()


## Jan, Nov 2026: "Inventář a staty hrdiny by měly být dostupné i při souboji. Aby hráč mohl hned
## obléct to co našel nebo si vybrat skilly." The door exists, it is reachable with a thumb, it
## does not swallow the walk, and the clock really stops while the dialog is up.
func _test_screen_hero_button() -> void:
	_log("  section: screen_hero_button")
	var screen = SurvivorScreen.new()
	root.add_child(screen)
	screen.size = Vector2(390, 844)
	screen.setup(_state, _find_item, _loot, 0)
	screen._layout_buttons()
	var asked := [false]
	screen.hero_requested.connect(func(): asked[0] = true)

	# No two top-bar controls in one rectangle: a button drawn over another is a button nobody
	# can hit (measured before: the timer sat under "Akce").
	var rects := {"hero": screen._hero_rect, "portal": screen._portal_rect,
		"exit": screen._exit_rect, "bind": screen._bind_rect}
	for a in rects:
		for b in rects:
			if str(a) >= str(b):
				continue
			_check(not (rects[a] as Rect2).intersects(rects[b] as Rect2),
				"the %s and %s buttons overlap: %s vs %s"
					% [a, b, str(rects[a]), str(rects[b])])
	_check(screen._hero_rect.position.y >= SurvivorScreen.TOP_BAR,
		"the hero button must sit on the second row, below the top bar")
	_check(screen._hero_rect.end.x <= 390.0 and screen._hero_rect.end.y <= 844.0,
		"the hero button must be on screen: %s" % str(screen._hero_rect))

	# A tap on it asks for the modal and arms NOTHING else — not a walk, not an action.
	var centre: Vector2 = screen._hero_rect.get_center()
	var before_pos: Vector2 = screen.run.player_pos
	screen._on_press(centre, 0)
	_check(asked[0], "a tap on the hero button must ask for the character modal")
	_check(screen._stick_index == -1 and not screen._pointer_down,
		"the hero button must not start a walk")
	screen._on_release(0)
	_check(screen.run.player_pos == before_pos, "the hero button must not move the hero")

	# The pause is real: the clock stops and the VISIBILITY of the screen (the modal leaves it
	# visible on purpose) must not restart it.
	screen.pause_run()
	_check(screen._paused and not screen.is_processing(),
		"pause_run must stop the clock")
	screen.show()
	screen.hide()
	screen.show()
	_check(not screen.is_processing(),
		"a visibility change must not resume a paused run")
	screen.resume_run()
	_check(not screen._paused and screen.is_processing(),
		"resume_run must restart the clock")
	screen.stop()
	screen.queue_free()
