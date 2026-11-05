extends SceneTree
## tools/probe_area_size.gd — how big IS an area? Path length, floor cells, packs, for a few
## seeds. The number Jan's "3x rozsáhlejší" is judged against, measured rather than asserted.
##
## Run: godot4 --headless --path . --script res://tools/probe_area_size.gd [-- seeds]

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const SurvivorRun := preload("res://scripts/combat/survivor_run.gd")

var _data: Node
var _gen: ItemGen
var _loot: LootSystem
var _state
var _seeds: Array = []
var _i := 0
var _cur


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		_seeds.append(int(a))
	if _seeds.is_empty():
		_seeds = [1, 7, 4242]
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_loot = LootSystem.new(_data, _gen)
	_state = GameState.new()
	_state.bind_data(_data)
	_state.set_class("barbarian")
	print("grid=%dx%d cells (%.0fx%.0f px), packs clamp 8..34" % [SurvivorRun.COLS,
		SurvivorRun.ROWS, SurvivorRun.COLS * SurvivorRun.TILE, SurvivorRun.ROWS * SurvivorRun.TILE])


func _process(_delta: float) -> bool:
	if _i >= _seeds.size():
		quit(0)
		return false
	var seed_value: int = int(_seeds[_i])
	_i += 1
	_cur = SurvivorRun.new()
	root.add_child(_cur)
	_cur.setup(_state, func(id): return _data.item(str(id)), _loot, 0, seed_value, 0)
	var total := 0.0
	var pts: Array = _cur.path_points
	for k in range(1, pts.size()):
		total += (pts[k - 1] as Vector2).distance_to(pts[k] as Vector2)
	var floor_cells := 0
	for v in _cur.floor_cells:
		if int(v) == 1:
			floor_cells += 1
	var bodies := 0
	for z in _cur.zones:
		bodies += (z["members"] as Array).size()
	print("seed %-6d path=%6.0f px  floor=%4d cells  packs=%2d  bodies=%2d  exit=%s" % [
		seed_value, total, floor_cells, _cur.zones.size(), bodies, str(_cur.exit_point)])
	return false
