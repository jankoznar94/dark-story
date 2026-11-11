extends SceneTree
## tools/probe_cycle.gd — how often a committed body actually lands, in blows per 10 s.
const GameData   := preload("res://scripts/data/game_data.gd")
const ItemGen    := preload("res://scripts/items/item_gen.gd")
const GameState  := preload("res://scripts/state/game_state.gd")
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
	var r := SurvivorRun.new()
	r.setup(_state, _f, _loot, 0, 7)
	r.monsters.clear()
	r.hp = 9999999
	r.max_hp = 9999999
	var row: Dictionary = r._pick_row(0)
	var m: Dictionary = r._make_monster(row, r.player_pos + Vector2(58, 0), 1)
	m["ranged"] = false
	m["speed"] = 0.0
	m["hp"] = 999999
	m["atk_cd"] = 1.5
	m["atk_ready"] = 0.0
	r.monsters.append(m)
	var blows := 0
	var last := 0
	var t := 0.0
	var log_times: Array = []
	while t < 12.0:
		var before: int = r.hp
		r.step(STEP, Vector2.ZERO)
		if int(r.hp) < before:
			blows += 1
			log_times.append(snappedf(t, 0.01))
		t += STEP
	print("atk_cd=1.5 windup=%.2f blows in 12 s = %d at %s" % [float(m["windup"]), blows, str(log_times)])
	print("atk_t=%.2f atk_ready=%.2f stagger=%.2f" % [float(m["atk_t"]), float(m["atk_ready"]), float(m["stagger"])])
	quit()


func _f(id: Variant) -> Dictionary:
	return {}
