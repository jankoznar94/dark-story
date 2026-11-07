extends SceneTree
## tools/probe_village_zone.gd — does the VILLAGE zone actually work as a zone?
##
## The tiles and the generator existed before this, but nothing in the game read them. This probe
## drives the REAL `SurvivorRun` (never a second copy of the rules) and answers:
##   1. WHICH zone is the village, found by theme name — not by an index someone has to remember.
##   2. Can the hero stand where he spawns, and can he reach the exit (the BFS a monster follows)?
##   3. Are the packs ON the walkways, and is the route long enough to hold them?
##   4. Does a CORRIDOR zone of the same act still build the old way (the integration must not
##      have bent the areas that were already fine)?
##
## Run: godot --headless --path . --script res://tools/probe_village_zone.gd

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const SurvivorRun := preload("res://scripts/combat/survivor_run.gd")
const ZoneThemeData := preload("res://scripts/ui/zone_theme.gd")
const VillageLayout := preload("res://scripts/ui/village_layout.gd")

var _data: Node
var _gen: ItemGen
var _loot: LootSystem
var _state
var _fails := 0


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_loot = LootSystem.new(_data, _gen)
	_state = GameState.new()
	_state.bind_data(_data)
	_state.reset()
	_state.set_class("barbarian")

	var found := _find_village_zone()
	_check(found.size() > 0, "there is a zone with the village theme")
	if found.size() > 0:
		_village(found[0])
	# The SAME act's first zone is a corridor: it must still be one.
	if found.size() > 0:
		_corridor(int(found[0].x), 0)
	print("VILLAGE_ZONE_FAILS=%d" % _fails)
	print("VILLAGE_ZONE_OK=%s" % ("true" if _fails == 0 else "false"))
	quit()


func _find_village_zone() -> Array:
	var out: Array = []
	for act in 5:
		for zone in 10:
			var row: Dictionary = ZoneThemeData.for_zone(act, zone)
			if str(row.get("name", "")) == SurvivorRun.VILLAGE_THEME_NAME:
				out.append(Vector2i(act, zone))
	return out


func _run(act: int, zone: int) -> SurvivorRun:
	var run := SurvivorRun.new()
	run.setup(_state, _find, _loot, act, 4242, zone)
	return run


func _find(id) -> Variant:
	return _data.item(str(id)) if _data.has_method("item") else null


func _village(at: Vector2i) -> void:
	print("--- village at act %d zone %d" % [at.x, at.y])
	var run := _run(at.x, at.y)
	_check(not run.village.is_empty(), "the run assembled a village layout")
	if run.village.is_empty():
		return
	var cells: Array = run.village.get("cells", [])
	print("    tiles=%d world=%s" % [cells.size(), str(run.world)])
	_check(cells.size() >= 20, "the layout has at least 20 walkable tiles")
	_check(is_equal_approx(run.world.x, VillageLayout.WORLD.x * VillageLayout.SCALE),
		"the world is the village size, not the corridor size")
	_check(is_equal_approx(run._flow_cell, SurvivorRun.FLOW_CELL_VILLAGE),
		"the flow lattice switched to 48 px")

	# Where the hero stands, and where he must be able to leave.
	_check(run.walkable(run.start_point, SurvivorRun.HERO_RADIUS),
		"the hero can stand on the spawn: %s" % str(run.start_point.round()))
	_check(run.walkable(run.exit_point, SurvivorRun.HERO_RADIUS),
		"the exit is standable: %s" % str(run.exit_point.round()))
	# A point in the jungle must NOT be walkable, or the tiles mean nothing.
	_check(not run.walkable(Vector2(20.0, 20.0), SurvivorRun.HERO_RADIUS),
		"the jungle is solid")
	# The hut in the middle of a tile is the obstacle.
	var hut_cell: Array = cells[0]
	var hut_centre := Vector2(int(hut_cell[0]) * VillageLayout.TILE + VillageLayout.TILE * 0.5,
		int(hut_cell[1]) * VillageLayout.TILE + VillageLayout.TILE * 0.5) * VillageLayout.SCALE
	_check(not run.walkable(hut_centre, 0.0), "the hut is solid")

	var route: Array = []
	for p in run.path_points:
		route.append(p)
	var total := 0.0
	for i in range(1, route.size()):
		total += (route[i - 1] as Vector2).distance_to(route[i] as Vector2)
	print("    route points=%d length=%.0f px" % [route.size(), total])
	_check(route.size() >= 5, "the route has enough points to lay packs along")
	_check(total >= 1500.0, "the route is long enough for a zone (%.0f px)" % total)

	# Every pack must stand on a walkway — a pack in the jungle would never be reachable.
	var bad := 0
	var members := 0
	for z in run.zones:
		if not run.walkable(z["centre"] as Vector2, SurvivorRun.MON_RADIUS):
			bad += 1
		members += (z["members"] as Array).size()
	print("    packs=%d bodies=%d off_walkway=%d" % [run.zones.size(), members, bad])
	_check(run.zones.size() >= 6, "the zone holds at least six packs")
	_check(bad == 0, "every pack centre is on a walkway")
	_check(members > 0, "the packs have bodies")

	# THE PATH A MONSTER FOLLOWS: the exit must be reachable in the flow field, or a body that
	# loses sight of the hero (i.e. always, on a village) would stand still.
	var field := run._flow_field()
	var exit_cell := run._flow_cell_of(run.exit_point)
	var idx := exit_cell.y * run._flow_w + exit_cell.x
	var reachable := idx >= 0 and idx < field.size() and field[idx] >= 0
	_check(reachable, "the exit is reachable through the flow field")
	# And it must take real distance, not one step: the field is the map's shape.
	if reachable:
		print("    exit is %d flow cells from the hero" % field[idx])
		_check(field[idx] > 20, "the exit is a real walk away")


func _corridor(act: int, zone: int) -> void:
	print("--- corridor at act %d zone %d (must be untouched)" % [act, zone])
	var run := _run(act, zone)
	_check(run.village.is_empty(), "a corridor zone does NOT assemble a village")
	_check(is_equal_approx(run.world.x, SurvivorRun.WORLD.x), "the corridor world is unchanged")
	_check(is_equal_approx(run._flow_cell, SurvivorRun.TILE), "the corridor flow lattice is 60 px")
	_check(run.walkable(run.start_point, SurvivorRun.HERO_RADIUS), "the hero can stand on the start")
	_check(run.zones.size() > 0, "the corridor still holds packs")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
