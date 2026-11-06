extends SceneTree
## tools/probe_soak.gd — a scripted player walks a zone, and the run reports what happened.
##
## The balance question ("is zone 10 of act 3 survivable at the gear a player has there?") cannot
## be answered by reading HP numbers; it needs a body that walks, swings and dies. The driver is
## deliberately dumb and identical for every zone: hold the attack, walk at the nearest living
## monster. That makes the RESULT comparable across zones — a zone the dumb driver cannot finish is
## a zone that asks the player for more than standing still and holding one button.
##
## Run: godot --headless --path . --script res://tools/probe_soak.gd

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const SurvivorRun := preload("res://scripts/combat/survivor_run.gd")

const STEP := 1.0 / 60.0
## Seconds of fight per configuration. Long enough to walk a zone, short enough to finish.
const LIMIT := 240.0

## act, zone, hero level, weapon the player plausibly has when he gets there
const CASES := [
	[0, 0, 1, "blade_shortSword"],
	[0, 4, 2, "blade_shortSword"],
	[0, 9, 3, "blade_scimitar"],
	[1, 0, 4, "blade_broadSword"],
	[1, 9, 6, "blade_broadSword"],
	[2, 0, 7, "blade_crystalSword"],
	[3, 0, 10, "blade_warSword"],
	[4, 9, 15, "blade_broadSword_nm"],
]

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
	print("act zone  lvl weapon                    | secs  kills  gold  items  hp end  verdict")
	for case in CASES:
		_soak(int(case[0]), int(case[1]), int(case[2]), str(case[3]))
	quit()


func _soak(act: int, zone: int, level: int, weapon: String) -> void:
	var hero: Dictionary = _state.hero()
	hero["level"] = level
	hero["attrStr"] = 20 + (level - 1) * 2
	hero["attrVit"] = 25 + (level - 1) * 2
	_state.equip()["weapon"] = weapon
	hero["hp"] = 999999
	var run := SurvivorRun.new()
	run.setup(_state, _find, _loot, act, 4242 + act * 100 + zone, zone)
	var t := 0.0
	var low := 1.0
	while t < LIMIT and not run.finished:
		# Walk toward the exit — that is the only way to meet a pack, because packs WAKE by
		# proximity. A body already close enough gets chased instead, so the driver really fights.
		var dir: Vector2 = (run.exit_point - run.player_pos).normalized()
		var best := 1e9
		for m in run.monsters:
			var d: float = (m["pos"] as Vector2).distance_to(run.player_pos)
			if d < best and d < 420.0:
				best = d
				dir = ((m["pos"] as Vector2) - run.player_pos).normalized()
		run.attack_held = true
		run.step(STEP, dir)
		low = minf(low, float(run.hp) / maxf(1.0, float(run.max_hp)))
		t += STEP
	print("%d   %-4d %-3d %-25s | %5.0f %6d %5d %6d %7d  %s" % [act + 1, zone + 1, level,
		weapon, t, run.kills, run.gold, run.items_taken, run.hp,
		"DIED" if run.finished else "alive (low %d%%)" % int(low * 100.0)])


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
