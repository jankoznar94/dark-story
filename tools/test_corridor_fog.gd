extends SceneTree
## tools/test_corridor_fog.gd — the area is a WINDING CORRIDOR, and it is revealed as you walk.
##
## Jan, Nov 2026: "Oblast by neměla být čtverec nebo obdélník. Spíš takový jakýsi koridor, který má
## různé zatáčky, atd. Teď je mapa strašně jednotvárná a nic neříkající." and "A nejspíš by se měla
## objevovat postupně. To znamená, že tam, kde hráč ještě fyzicky nebyl, by to mělo být černé, nebo
## minimálně zašedlé. Třeba jak ve Warcraft 2."
##
## Three things have to hold, and none of them is visible from a screenshot alone:
##
##   1. THE SHAPE — the walkable area is a small part of the world, it SPANS the map (so it really
##      winds instead of being a small room), and every pack stands on floor;
##   2. THE CONNECTIVITY — one flood fill from the spawn reaches every floor cell and every pack.
##      A corridor with a wall between the hero and the last pack is a run nobody can finish, and
##      the generator is random, so this is asserted over several seeds;
##   3. THE FOG — a cell far from the spawn is UNEXPLORED at the start, and becomes explored once
##      the hero has walked near it. Both states are read off the run, not off the screen.
##
## Run:  godot --headless --path . --script res://tools/test_corridor_fog.gd
## Pass: prints CORRIDOR_FOG_ALL_PASS=true and exits 0.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const SurvivorRun := preload("res://scripts/combat/survivor_run.gd")

const STEP := 0.1
## The seeds the generator is judged on. One seed can be lucky; five cannot all be lucky.
const SEEDS := [1, 7, 4242, 90210, 31337]

var _data: Node
var _gen: ItemGen
var _loot: LootSystem
var _failures: Array[String] = []


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_loot = LootSystem.new(_data, _gen)

	for seed_value in SEEDS:
		_test_shape(seed_value)
		_test_connectivity(seed_value)
		_test_packs_stand_on_floor(seed_value)
	_test_fog_reveals_as_you_walk()

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("CORRIDOR_FOG_ALL_PASS=true")
	else:
		print("CORRIDOR_FOG_ALL_PASS=false")
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _resolve(state) -> Callable:
	return func(id):
		var item_id := str(id)
		if item_id == "":
			return {}
		var static_item: Dictionary = _data.item(item_id)
		if not static_item.is_empty():
			return static_item
		return state.loot_item(item_id)


func _hero():
	var s = GameState.new()
	s.bind_data(_data)
	s.set_class("barbarian")
	s.hero()["level"] = 20
	return s


func _run(seed_value: int) -> SurvivorRun:
	var s = _hero()
	var r := SurvivorRun.new()
	r.setup(s, _resolve(s), _loot, 0, seed_value)
	return r


## Floor cells, as `[x, y]` pairs.
func _floor_cells(r: SurvivorRun) -> Array:
	var out: Array = []
	for cy in r.ROWS:
		for cx in r.COLS:
			if r.is_floor_cell(cx, cy):
				out.append(Vector2i(cx, cy))
	return out


# --- 1. the shape ---------------------------------------------------------------

## The area must not be the rectangle it used to be: a good part of the world is rock, and the
## floor that remains reaches BOTH ends of the map — a corridor snakes up it. A generator that
## carved one small room would pass a "not a rectangle" check and fail the run, so the span is
## asserted too.
func _test_shape(seed_value: int) -> void:
	var r := _run(seed_value)
	var floor_n := _floor_cells(r).size()
	var total := r.COLS * r.ROWS
	var share := float(floor_n) / float(total)
	print("  seed %d: %d/%d cells floor (%.0f %%), %d packs"
		% [seed_value, floor_n, total, share * 100.0, r.zones.size()])
	if share > 0.75:
		_fail("seed %d: %.0f %% of the map is floor — that is still a field, not a corridor"
			% [seed_value, share * 100.0])
	if share < 0.10:
		_fail("seed %d: only %.0f %% of the map is floor — nothing to walk on"
			% [seed_value, share * 100.0])

	var ys: Array = []
	var xs: Array = []
	for c in _floor_cells(r):
		xs.append(c.x)
		ys.append(c.y)
	var span_x: int = int(xs.max()) - int(xs.min()) + 1
	var span_y: int = int(ys.max()) - int(ys.min()) + 1
	if span_y < r.ROWS * 0.7:
		_fail("seed %d: the corridor only spans %d of %d rows — it does not wind up the map"
			% [seed_value, span_y, r.ROWS])
	if span_x < r.COLS * 0.4:
		_fail("seed %d: the corridor only spans %d of %d columns — there are no turns to make"
			% [seed_value, span_x, r.COLS])

	# The start clearing is a ROOM, not a single cell: room to fight the first pack.
	var c := r.cell_of(r.start_point)
	var room := 0
	for y in range(c.y - r.START_ROOM_HALF, c.y + r.START_ROOM_HALF + 1):
		for x in range(c.x - r.START_ROOM_HALF, c.x + r.START_ROOM_HALF + 1):
			if r.is_floor_cell(x, y):
				room += 1
	if room < 49:
		_fail("seed %d: the start clearing is only %d cells, expected at least 7x7"
			% [seed_value, room])
	if not r.walkable(r.player_pos, r.HERO_RADIUS):
		_fail("seed %d: the hero spawns inside the rock at %s" % [seed_value, str(r.player_pos)])


# --- 2. connectivity ------------------------------------------------------------

## One flood fill over the floor, four neighbours, starting at the spawn. Every floor cell and
## every pack centre must be reachable — a pocket behind the rock would be a pack the player can
## see and never fight, and the area would never clear.
func _test_connectivity(seed_value: int) -> void:
	var r := _run(seed_value)
	var seen := {}
	var start := r.cell_of(r.start_point)
	var stack: Array = [start]
	seen[start] = true
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var n: Vector2i = c + d
			if seen.has(n) or not r.is_floor_cell(n.x, n.y):
				continue
			seen[n] = true
			stack.append(n)
	var floor_n := _floor_cells(r).size()
	if seen.size() != floor_n:
		_fail("seed %d: %d of %d floor cells are cut off from the spawn"
			% [seed_value, floor_n - seen.size(), floor_n])
	for z in r.zones:
		var c := r.cell_of(z["centre"] as Vector2)
		if not seen.has(c):
			_fail("seed %d: a pack at %s stands in a pocket the hero cannot reach"
				% [seed_value, str(z["centre"])])
			break


# --- 3. every pack stands on floor ----------------------------------------------

## The pack's whole formation, not just its centre: a member standing in the rock would be a body
## that cannot be hit in melee (the hero cannot walk to it) but still wakes and shoots.
func _test_packs_stand_on_floor(seed_value: int) -> void:
	var r := _run(seed_value)
	if r.zones.size() < 6:
		_fail("seed %d: only %d packs in the corridor, expected 6+" % [seed_value, r.zones.size()])
	for z in r.zones:
		if (z["centre"] as Vector2).distance_to(r.start_point) <= r.ACTIVATE_RADIUS:
			_fail("seed %d: a pack centre is inside the activation radius of the spawn"
				% seed_value)
			break
		for m in z["members"]:
			if not r.walkable(m["pos"] as Vector2, r.MON_RADIUS):
				_fail("seed %d: a pack member stands in the rock at %s"
					% [seed_value, str(m["pos"])])
				break


# --- 4. the fog ------------------------------------------------------------------

## Warcraft 2's rule: what the hero has not been near does not exist yet. At the start, the far
## end of the corridor is unexplored; after walking a few seconds up it, cells that were black
## become explored, and the count only ever grows.
func _test_fog_reveals_as_you_walk() -> void:
	var r := _run(4242)
	var explored_at_start := 0
	for cy in r.ROWS:
		for cx in r.COLS:
			if r.is_explored_cell(cx, cy):
				explored_at_start += 1
	if explored_at_start <= 0:
		_fail("nothing is explored at the spawn — the hero would be standing in the dark")
		return
	var floor_n := _floor_cells(r).size()
	if explored_at_start >= floor_n:
		_fail("the WHOLE corridor is explored at the spawn (%d of %d cells) — there is no fog"
			% [explored_at_start, floor_n])
		return

	# The far end of the corridor must be dark at the start.
	var far: Vector2 = r.path_points[r.path_points.size() - 1]
	var far_cell := r.cell_of(far)
	if r.is_explored_cell(far_cell.x, far_cell.y):
		_fail("the far end of the corridor is already explored at the spawn")

	# Walk up the corridor and count again. The hero cannot steer around the turns on his own, so
	# the walk is driven by the run's own slide: hold "up" and let `_step_body` follow the floor.
	for _i in 900:
		r.step(STEP, Vector2(0, -1))
	var explored_after := 0
	for cy in r.ROWS:
		for cx in r.COLS:
			if r.is_explored_cell(cx, cy):
				explored_after += 1
	print("  fog: %d explored at spawn -> %d after 90 s of walking (%d floor cells)"
		% [explored_at_start, explored_after, floor_n])
	if explored_after <= explored_at_start:
		_fail("walking up the corridor revealed nothing (%d -> %d cells)"
			% [explored_at_start, explored_after])
	if r.is_explored_cell(far_cell.x, far_cell.y) == false and explored_after < floor_n / 2:
		_fail("after 90 s of walking only %d of %d floor cells are explored — the reveal radius"
			% [explored_after, floor_n] + " is too small to follow the corridor")
