extends SceneTree
## tools/probe_dodgeability.gd — can the player actually AVOID a hit, and at what distance?
##
## Three questions, each measured on the real `SurvivorRun` rules (nothing re-derived here):
##   1. ORB    — a thrower fires from gap X; the hero reacts the frame the orb exists and steps
##               sideways at full speed. Hit or miss, per gap. Plus a "stood still" control.
##   2. MELEE  — a body commits to a blow; the hero leaves at the moment the telegraph starts
##               (and again when only 50 % of it is left). Whiff or hit, and at what distance.
##   3. CHASE  — a real thrower against a hero holding attack: at WHAT GAP does it actually fire?
##
## Run: godot --headless --path . --script res://tools/probe_dodgeability.gd

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const SurvivorRun := preload("res://scripts/combat/survivor_run.gd")

const STEP := 1.0 / 60.0

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
	print("hero %.0f px/s | orb %.0f px/s | hero r %.0f | orb r %.0f | iframe %d ms | reach %.0f"
		% [SurvivorRun.HERO_BASE_SPEED, SurvivorRun.PROJECTILE_SPEED, SurvivorRun.HERO_RADIUS,
			SurvivorRun.PROJECTILE_RADIUS, SurvivorRun.HERO_IFRAME_MS,
			SurvivorRun.BODY_RADIUS * 2.0 + SurvivorRun.STRIKE_PAD])
	_orbs()
	_melee()
	_chase()
	quit()


func _run(act: int, zone: int, seedv: int) -> SurvivorRun:
	var r := SurvivorRun.new()
	r.setup(_state, _find, _loot, act, seedv, zone)
	r.monsters.clear()
	return r


## A thrower that stands exactly where it was put (speed 0, keep_range 0) so `gap` means gap.
func _spawn_ranged(run: SurvivorRun, gap: float) -> Dictionary:
	for _i in 400:
		var row: Dictionary = run._pick_row(run._depth_for(0))
		if not run._is_ranged(row):
			continue
		var off := Vector2(gap, 0)
		var m: Dictionary = run._make_monster(row, run.player_pos + off,
			int(_state.hero().get("level", 1)))
		m["speed"] = 0.0
		m["keep_range"] = 0.0
		run.monsters.append(m)
		return m
	return {}


func _orbs() -> void:
	print("\n=== 1. ORB: react the frame it is thrown, step sideways ===")
	print("gap  flight  stand-still  sidestep  lateral  moved-in")
	for gap in [70, 110, 150, 180, 232, 300]:
		var gapf := float(gap)
		if gapf < SurvivorRun.MIN_SHOT_GAP:
			print("%3d  -------  %-11s" % [gap, "NO SHOT (band)"])
			continue
		var flight: float = (gapf - (SurvivorRun.BODY_RADIUS + 6.0)) / SurvivorRun.PROJECTILE_SPEED
		# (a) control: stand still
		var run0: SurvivorRun = _run(0, 0, 4242 + gap)
		_spawn_ranged(run0, gapf)
		var hp0 := int(run0.hp)
		var t0 := 0.0
		while t0 < 3.0 and int(run0.hp) >= hp0:
			run0.step(STEP, Vector2.ZERO)
			t0 += STEP
		var stood_hit := int(run0.hp) < hp0
		# (b) dodge: hold still until the orb exists, then run
		var run: SurvivorRun = _run(0, 0, 4242 + gap)
		var m: Dictionary = _spawn_ranged(run, gapf)
		if m.is_empty():
			continue
		var hp1 := int(run.hp)
		var start: Vector2 = run.player_pos
		var side := _perp_side(run, m["pos"] as Vector2)
		var t := 0.0
		var armed := false
		var t_arm := 0.0
		var lateral := 0.0
		# Judge the FIRST orb only. `PROJECTILE_LIFETIME` is 3.2 s, so a missed orb still sits in
		# `projectiles` long after it has flown past — waiting for the array to empty reports a
		# HIT from the thrower's NEXT orb, which the player never had a chance to answer.
		while t < 3.0 and int(run.hp) >= hp1:
			if not armed and not run.projectiles.is_empty():
				armed = true
				t_arm = t
			var move := side if armed else Vector2.ZERO
			run.step(STEP, move)
			t += STEP
			if armed:
				lateral = maxf(lateral, (run.player_pos - start).length())
				if t - t_arm > flight + 0.40:
					break
		var dodged := int(run.hp) >= hp1
		print("%3d  %.2f s  %-11s  %-8s  %5.0f px %6.0f px" % [gap, flight,
			"HIT" if stood_hit else "miss", "MISS" if dodged else "HIT", lateral,
			(run.player_pos - start).length()])
	# What the arithmetic allows, for the record.
	var need: float = SurvivorRun.HERO_RADIUS + SurvivorRun.PROJECTILE_RADIUS
	print("a sidestep needs %.0f px of lateral travel = %.2f s at %.0f px/s"
		% [need, need / SurvivorRun.HERO_BASE_SPEED, SurvivorRun.HERO_BASE_SPEED])


## The side that is actually free floor (a corridor is not a plane).
func _free_side(run: SurvivorRun) -> Vector2:
	for v in [Vector2(0, 1), Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0)]:
		if run._line_clear(run.player_pos, run.player_pos + v * 90.0):
			return v
	return Vector2.ZERO


## Perpendicular to the thrower — a sidestep, not a retreat along the orb's own line.
func _perp_side(run: SurvivorRun, from: Vector2) -> Vector2:
	var d := (from - run.player_pos).normalized()
	var p := Vector2(-d.y, d.x)
	for v in [p, -p]:
		if run._line_clear(run.player_pos, run.player_pos + v * 60.0):
			return v
	return Vector2.ZERO


func _melee() -> void:
	print("\n=== 2. MELEE: leave the moment the telegraph starts / at its half ===")
	print("step-at  gap@commit  gap@land  whiff  hp lost  next commit in  moved")
	for frac in [0.0, 0.3, 0.5, 0.7, 0.9]:
		var run: SurvivorRun = _run(0, 0, 909)
		var row: Dictionary = run._pick_row(run._depth_for(0))
		var m: Dictionary = run._make_monster(row, run.player_pos + Vector2(62, 0),
			int(_state.hero().get("level", 1)))
		m["speed"] = 0.0
		m["ranged"] = false
		run.monsters.append(m)
		var hp0 := int(run.hp)
		var away := (run.player_pos - (m["pos"] as Vector2)).normalized()
		var start: Vector2 = run.player_pos
		var t := 0.0
		var stepped := false
		var whiffed := false
		var gap_commit := 0.0
		var gap_land := 0.0
		var t_commit := -1.0
		var t_next := -1.0
		var moved := 0.0
		while t < 6.0:
			var move := Vector2.ZERO
			if not run.monsters.is_empty():
				var mon: Dictionary = run.monsters[0]
				if float(mon["atk_t"]) >= 0.0 and not stepped:
					if t_commit < 0.0:
						t_commit = t
					gap_commit = run.player_pos.distance_to(mon["pos"] as Vector2)
					var total := maxf(0.001, float(mon["windup_total"]))
					var left := float(mon["atk_t"])
					if left <= total * (1.0 - float(frac)):
						stepped = true
				elif stepped and t_next < 0.0 and float(mon["atk_t"]) < 0.0:
					t_next = t - t_commit
					gap_land = run.player_pos.distance_to(mon["pos"] as Vector2)
			if stepped:
				move = away
			run.step(STEP, move)
			t += STEP
			moved = maxf(moved, (run.player_pos - start).length())
			if run.events.has("whiff"):
				whiffed = true
				run.events.clear()
			if int(run.hp) < hp0 and stepped:
				if gap_land == 0.0 and not run.monsters.is_empty():
					gap_land = run.player_pos.distance_to(run.monsters[0]["pos"] as Vector2)
				break
		print("%5.0f%%  %9.0f  %8.0f  %-5s  %7d  %14s  %5.0f px" % [frac * 100.0, gap_commit,
			gap_land, "YES" if whiffed else "no", hp0 - int(run.hp),
			("%.2f s" % t_next) if t_next > 0.0 else "n/a", moved])


func _chase() -> void:
	print("\n=== 3. CHASE: at what gap does a real thrower actually fire? ===")
	var run: SurvivorRun = _run(0, 0, 31337)
	var m: Dictionary = _spawn_ranged(run, 420.0)
	if m.is_empty():
		print("no thrower row found")
		return
	m["speed"] = 60.0
	m["keep_range"] = SurvivorRun.KEEP_RANGE
	run.attack_held = true
	var gaps: Array = []
	var t := 0.0
	var seen := 0
	while t < 12.0 and int(run.hp) > 0:
		run.step(STEP, Vector2.ZERO)
		t += STEP
		if run.projectiles.size() > seen:
			seen = run.projectiles.size()
			gaps.append(snappedf(run.player_pos.distance_to(m["pos"] as Vector2), 1.0))
	gaps.sort()
	if gaps.is_empty():
		print("never fired in 12 s | caster %d/%d hp | hero %d/%d"
			% [int(m["hp"]), int(m["max_hp"]), int(run.hp), int(run.max_hp)])
		return
	var med: float = gaps[gaps.size() / 2]
	print("shots %d | closest %.0f px | median %.0f px | furthest %.0f px | hp %d/%d | kill range %.0f"
		% [gaps.size(), float(gaps[0]), med, float(gaps[-1]), int(run.hp), int(run.max_hp),
			SurvivorRun.SHOOT_RANGE])


func _find(id: Variant) -> Dictionary:
	if id == null:
		return {}
	var s := str(id)
	if s == "":
		return {}
	var item: Dictionary = _data.item(s)
	if item.is_empty():
		item = _state.loot_item(s)
	return item
