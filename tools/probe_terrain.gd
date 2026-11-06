extends SceneTree
## tools/probe_terrain.gd — what an area's GROUND is made of, per zone and seed.
##
## Jan, Nov 2026: a zone stopped being a tinted texture and became a PLACE — the bog is water you
## cannot step in, crossed by a plank walkway; the valley is a river crossed by a bridge. This
## prints the cell make-up of the result, plus the three things that make it playable rather than
## just pretty: the entrance/exit edges, whether every walkable cell is reachable, and whether the
## walkway is ONE piece (a hole in a boardwalk is a zone the player cannot cross).
##
## Run: godot --headless --path . --script res://tools/probe_terrain.gd [-- seeds] [-- zones]

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const SurvivorRun := preload("res://scripts/combat/survivor_run.gd")
const ZoneTheme := preload("res://scripts/ui/zone_theme.gd")

const SIDES := ["bottom", "top", "left", "right"]

var _data: Node
var _gen: ItemGen
var _loot: LootSystem
var _state
var _seeds: Array = []
var _zones: Array = []
var _i := 0
var _j := 0
var _cur = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var k := 0
	while k < args.size():
		match args[k]:
			"--seeds":
				_seeds = []
				for part in str(args[k + 1]).split(","):
					_seeds.append(int(part))
			"--zones":
				_zones = []
				for part in str(args[k + 1]).split(","):
					_zones.append(int(part))
		k += 2
	if _seeds.is_empty():
		_seeds = [1, 7, 4242]
	if _zones.is_empty():
		_zones = [0, 3, 4, 5, 8]
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_loot = LootSystem.new(_data, _gen)
	_state = GameState.new()
	_state.bind_data(_data)
	_state.set_class("barbarian")
	print("grid=%dx%d cells, PATH_TARGET=%.0f px" % [SurvivorRun.COLS, SurvivorRun.ROWS,
		SurvivorRun.PATH_TARGET])


func _process(_delta: float) -> bool:
	if _i >= _seeds.size():
		quit(0)
		return false
	if _j >= _zones.size():
		_i += 1
		_j = 0
		return false
	var seed_value: int = int(_seeds[_i])
	var zone: int = _zones[_j]
	_j += 1
	_cur = SurvivorRun.new()
	_cur.setup(_state, func(id): return _data.item(str(id)), _loot, 0, seed_value, zone)

	var ground := 0
	var water := 0
	var deck := 0
	var rock := 0
	for cy in SurvivorRun.ROWS:
		for cx in SurvivorRun.COLS:
			match _cur.cell_kind_at(cx, cy):
				SurvivorRun.KIND_GROUND:
					ground += 1
				SurvivorRun.KIND_WATER:
					water += 1
				SurvivorRun.KIND_DECK:
					deck += 1
				_:
					rock += 1
	var total := 0.0
	var pts: Array = _cur.path_points
	for n in range(1, pts.size()):
		total += (pts[n - 1] as Vector2).distance_to(pts[n] as Vector2)
	var theme: Dictionary = ZoneTheme.for_zone(0, zone)
	print("seed %-6d zone %d %-18s feature=%-9s entry=%-6s exit=%-6s path=%6.0f"
		% [seed_value, zone, str(theme.get("name", "")), str(_cur.feature),
			SIDES[_cur.entry_side], SIDES[_cur.exit_side], total])
	print("         ground=%4d water=%4d deck=%4d rock=%4d  walkable=%4d  connected=%s"
		% [ground, water, deck, rock, _count_floor(), _connected()])
	return false


func _count_floor() -> int:
	var n := 0
	for v in _cur.floor_cells:
		if int(v) == 1:
			n += 1
	return n


## One flood fill from the entrance: every walkable cell has to be reachable, or a hole in the
## walkway has cut the zone in two.
func _connected() -> bool:
	var seen := {}
	var start: Vector2i = _cur.cell_of(_cur.start_point)
	var stack: Array = [start]
	seen[start] = true
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in SurvivorRun.DIRS:
			var n: Vector2i = c + d
			if seen.has(n) or not _cur.is_floor_cell(n.x, n.y):
				continue
			seen[n] = true
			stack.append(n)
	for i in _cur.floor_cells.size():
		if int(_cur.floor_cells[i]) == 1:
			var x: int = i % SurvivorRun.COLS
			var y: int = i / SurvivorRun.COLS
			if not seen.has(Vector2i(x, y)):
				return false
	return true
