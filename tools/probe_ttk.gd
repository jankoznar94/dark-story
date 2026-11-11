extends SceneTree
## tools/probe_ttk.gd — how long ONE even fight lasts, and how many blows the hero eats.
## Spawns exactly one body of the zone's real table next to the hero (speed 0 so it stands),
## holds the attack and steps the REAL rules until it dies. A second pass lets the body hit a
## hero who never swings, to measure the damage side separately.
## Run: godot --headless --path . --script res://tools/probe_ttk.gd

const GameData    := preload("res://scripts/data/game_data.gd")
const ItemGen     := preload("res://scripts/items/item_gen.gd")
const GameState   := preload("res://scripts/state/game_state.gd")
const LootSystem  := preload("res://scripts/items/loot_system.gd")
const SurvivorRun  := preload("res://scripts/combat/survivor_run.gd")

const STEP := 1.0 / 60.0

var _data: Node
var _gen: ItemGen
var _loot: LootSystem
var _state

const CASES := [[0, 0, 1, "blade_shortSword"], [0, 9, 3, "blade_scimitar"],
	[1, 0, 4, "blade_broadSword"], [2, 0, 7, "blade_crystalSword"],
	[3, 0, 10, "blade_warSword"], [4, 9, 15, "blade_broadSword_nm"]]


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_loot = LootSystem.new(_data, _gen)
	_state = GameState.new()
	_state.bind_data(_data)
	_state.reset()
	_state.set_class("barbarian")
	print("act z lvl weapon                   | heroHP heroDPS | monHP monDPS | TTK  hitsTaken | hitsToDie")
	for c in CASES:
		_case(int(c[0]), int(c[1]), int(c[2]), str(c[3]))
	quit()


func _case(act: int, zone: int, level: int, weapon: String) -> void:
	var hero: Dictionary = _state.hero()
	hero["level"] = level
	hero["attrStr"] = 20 + (level - 1) * 2
	hero["attrVit"] = 25 + (level - 1) * 2
	_state.equip()["weapon"] = weapon
	hero["hp"] = _gen.hero_max_hp(hero, _state.equip(), _find)
	# --- the hero's side: kill one standing body -------------------------------------------
	var run: SurvivorRun = _run(act, zone)
	var mon: Dictionary = _spawn(run)
	var hp_before := int(run.hp)
	run.attack_held = true
	var t := 0.0
	var ttk := -1.0
	while t < 120.0 and not run.finished:
		run.step(STEP, Vector2.ZERO)
		t += STEP
		if run.monsters.is_empty():
			ttk = t
			break
	var hits_taken := int(ceil(float(hp_before - int(run.hp)) / maxf(1.0, float(int(mon["dmg_min"]) + int(mon["dmg_max"])) * 0.5)))
	# --- the monster's side: a hero who does nothing ---------------------------------------
	var run2: SurvivorRun = _run(act, zone)
	var mon2: Dictionary = _spawn(run2, 58.0)
	var t2 := 0.0
	while t2 < 120.0 and not run2.finished:
		run2.step(STEP, Vector2.ZERO)
		t2 += STEP
	var died := run2.finished
	var hero_dps := _hero_dps(run, mon)
	var mon_dps := 0.5 * (float(mon2["dmg_min"]) + float(mon2["dmg_max"])) / maxf(0.001, float(mon2["atk_cd"]))
	print("%d   %d %-3d %-25s | %6d %7.1f | %5d %6.1f | %4.1f %10d | %s" % [act + 1, zone + 1, level,
		weapon, _hero_hp(), hero_dps, int(mon2["max_hp"]), mon_dps, ttk, hits_taken,
		("%.1f s" % t2) if died else "survives 120 s"])


func _hero_hp() -> int:
	return int(_gen.hero_max_hp(_state.hero(), _state.equip(), _find))


func _hero_dps(run: SurvivorRun, mon: Dictionary) -> float:
	return float(run.dmg_min + run.dmg_max) * 0.5 / maxf(0.001, run.main_swing) \
		* float(1.0 + run.speed_pct * 0.0)


func _run(act: int, zone: int) -> SurvivorRun:
	var r := SurvivorRun.new()
	r.setup(_state, _find, _loot, act, 999 + act * 10 + zone, zone)
	r.monsters.clear()
	return r


func _spawn(run: SurvivorRun, gap: float = 90.0) -> Dictionary:
	var row: Dictionary = run._pick_row(run._depth_for(0))
	var m: Dictionary = run._make_monster(row, run.player_pos + Vector2(gap, 0), int(_state.hero().get("level", 1)))
	m["speed"] = 0.0
	m["ranged"] = false
	m["keep_range"] = 0.0
	run.monsters.append(m)
	return m


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
