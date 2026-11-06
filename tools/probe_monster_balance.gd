extends SceneTree
## tools/probe_monster_balance.gd — what the fight ACTUALLY spawns and how strong it is, per act
## and zone, read straight from `SurvivorRun` (never re-derived here: a second copy of the rules
## is exactly how a probe starts lying about the game).
##
## Prints:
##   1. POOL   — how many kinds a zone can spawn, per zone of every act.
##   2. STRENGTH — the HP / damage range a body of that zone really gets.
##   3. HERO   — the damage the hero brings at the same points, so "monsters got stronger" can be
##      read against "so did the hero".
##
## Run: godot --headless --path . --script res://tools/probe_monster_balance.gd

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const SurvivorRun := preload("res://scripts/combat/survivor_run.gd")
const Progression := preload("res://scripts/combat/progression.gd")

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
	_pools()
	_strength()
	_hero()
	quit()


func _run(act: int, zone: int) -> SurvivorRun:
	var run := SurvivorRun.new()
	run.setup(_state, _find, _loot, act, 1000 + act * 10 + zone, zone)
	return run


## 200 rolls of `_pick_row` per zone: the rule's own distribution, not a re-implementation of it.
func _pools() -> void:
	print("=== POOL (kinds a zone can spawn; 200 rolled packs each) ===")
	for act in _data.acts():
		var act_id := int(act.get("id", 0))
		var line := "act %d %-18s theme %d |" % [act_id + 1, str(act.get("name", "")),
			int(act.get("theme", 0))]
		for zone in 10:
			var run := _run(act_id, zone)
			var seen: Array = []
			for _i in 200:
				var row: Dictionary = run._pick_row(run._depth_for(5))
				var nm := str(row.get("name", ""))
				if not seen.has(nm):
					seen.append(nm)
			line += " z%d:%d" % [zone + 1, seen.size()]
		print(line)
	# The whole roster of act 1, with the zone each kind first appears in.
	var run0 := _run(0, 0)
	var z := "act 1 kinds:"
	for row in run0.monster_rows():
		z += " %s@z%d" % [str(row.get("name", "")), int(row.get("minArea", 0)) + 1]
	print(z)


func _strength() -> void:
	print("\n=== STRENGTH (HP / damage a body really gets) ===")
	for act in _data.acts():
		var act_id := int(act.get("id", 0))
		var line := "act %d |" % [act_id + 1]
		for zone in [0, 4, 9]:
			var run := _run(act_id, zone)
			var lo := 1e9
			var hi := 0.0
			var dlo := 1e9
			var dhi := 0.0
			for _i in 200:
				var row: Dictionary = run._pick_row(run._depth_for(5))
				if row.is_empty():
					continue
				var m: Dictionary = run._make_monster(row, Vector2.ZERO, 1, {})
				lo = minf(lo, float(m["hp"]))
				hi = maxf(hi, float(m["hp"]))
				dlo = minf(dlo, float(m["dmg_min"]))
				dhi = maxf(dhi, float(m["dmg_max"]))
			line += " z%d hp %d-%d dmg %d-%d |" % [zone + 1, int(lo), int(hi), int(dlo), int(dhi)]
		print(line)


func _hero() -> void:
	print("\n=== HERO (barbarian, the damage he brings) ===")
	var hero: Dictionary = _state.hero()
	for step in [[1, "start (short sword)"], [5, "level 5, broad sword"],
			[10, "level 10, war sword"], [15, "level 15, battle sword"]]:
		var level: int = int(step[0])
		hero["level"] = level
		hero["attrStr"] = 20 + level * 2
		var weapon := "blade_shortSword"
		if level >= 15:
			weapon = "blade_broadSword_nm"
		elif level >= 10:
			weapon = "blade_warSword"
		elif level >= 5:
			weapon = "blade_broadSword"
		var equip: Dictionary = _state.equip()
		equip["weapon"] = weapon
		var roll: Dictionary = Progression.hero_dmg(hero, equip, _find)
		var w: Dictionary = _find.call(weapon)
		var swing := Progression.swing_time(RandomNumberGenerator.new(), w, int(hero["attrDex"]))
		var dps := (float(roll["min"]) + float(roll["max"])) * 0.5 / (float(swing) / 1000.0)
		print("%-28s dmg %d-%d swing %d ms -> %.1f dps (before hit chance)" % [
			str(step[1]), int(roll["min"]), int(roll["max"]), swing, dps])
	hero["level"] = 1
	hero["attrStr"] = 20
	_state.equip()["weapon"] = "blade_shortSword"


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
