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
## The four edges a walk can enter or leave by, in `SurvivorRun.entry_side` order.
const SIDE_NAMES := ["bottom", "top", "left", "right"]

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
		_test_size(seed_value)
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


## ⚠️  THE AREA'S EXTENT IS A NUMBER NOW ("Každá oblast by měla být minimálně 3x rozsáhlejší").
## The OLD corridor measured 3 240-4 200 px entrance-to-exit on five seeds (`PATH_TARGET` in
## `survivor_run.gd` records it); 3x that is the floor this asserts, and it is a floor for EVERY
## seed — a generator whose length depends on how many turns happened to fit produced 2.4x on
## one seed and 3.6x on the next.
func _test_size(seed_value: int) -> void:
	var r := _run(seed_value)
	var total := 0.0
	var pts: Array = r.path_points
	for k in range(1, pts.size()):
		total += (pts[k - 1] as Vector2).distance_to(pts[k] as Vector2)
	var need := SurvivorRun.PATH_TARGET * 0.95
	if total < need:
		_fail("seed %d: the corridor is %.0f px long, expected at least %.0f (3x the old 3240-4200)"
			% [seed_value, total, need])


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

	# ⚠️  THE SPAN IS ASSERTED ON THE EDGES THE WALK ACTUALLY CONNECTS. Jan, Nov 2026: "Východ nemusí
	# být vždy vpravo nahoře. A vchod nemusí být vždy vpravo dole. Může to být libovolně." A fixed
	# "the floor must climb 70 % of the rows" check measured the old bottom-to-top generator and
	# would fail every area that enters from the left. What has to hold instead is that the walk
	# REACHES both the edge it arrives through and the edge it leaves by.
	var xs: Array = []
	var ys: Array = []
	for c in _floor_cells(r):
		xs.append(c.x)
		ys.append(c.y)
	var span_x: int = int(xs.max()) - int(xs.min()) + 1
	var span_y: int = int(ys.max()) - int(ys.min()) + 1
	if not _reaches_edge(r, r.entry_side, xs, ys):
		_fail("seed %d: the floor does not reach the %s edge the hero arrives through"
			% [seed_value, SIDE_NAMES[r.entry_side]])
	if not _reaches_edge(r, r.exit_side, xs, ys):
		_fail("seed %d: the floor does not reach the %s edge the walk leaves by"
			% [seed_value, SIDE_NAMES[r.exit_side]])
	print("  seed %d: entry=%s exit=%s, floor spans %d x %d cells" % [seed_value,
		SIDE_NAMES[r.entry_side], SIDE_NAMES[r.exit_side], span_x, span_y])

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


# --- 1b. the two edges ----------------------------------------------------------

## Does the floor reach the edge of the map on `side`? The entrance room is carved 5-6 cells in
## from its own edge, so a floor cell within 14 cells of that edge is proof the walk got there.
func _reaches_edge(r: SurvivorRun, side: int, xs: Array, ys: Array) -> bool:
	match side:
		0:
			return int(ys.max()) >= r.ROWS - 14
		1:
			return int(ys.min()) <= 13
		2:
			return int(xs.min()) <= 13
		_:
			return int(xs.max()) >= r.COLS - 14


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
	# WALK THE CORRIDOR, not "hold up". A blind upward hold gets pinned against the first long
	# horizontal turn — with legs of 4-7 cells and turns of 10-18 it revealed 391 of 1254 cells
	# and then stopped moving entirely, which measured the walker and not the fog. Steering from
	# path point to path point is what a player walking the area does.
	var guard := 0
	for wp in r.path_points:
		var target: Vector2 = wp
		while r.player_pos.distance_to(target) > 12.0 and guard < 8000:
			var dir: Vector2 = (target - r.player_pos)
			if dir.length() < 0.001:
				break
			r.step(STEP, dir.normalized())
			# Bodies are SOLID and this test is about the FOG: a monster that walks into the
			# hero pins him (measured: 8 000 steps and 330 px of travel), which would measure
			# the fight instead of the reveal.
			r.monsters.clear()
			r.projectiles.clear()
			guard += 1
	var explored_after := 0
	for cy in r.ROWS:
		for cx in r.COLS:
			if r.is_explored_cell(cx, cy):
				explored_after += 1
	print("  walk: steps=%d pos=%s exit=%s packs=%d" % [guard, str(r.player_pos),
		str(r.path_points[r.path_points.size() - 1]), r.zones.size()])
	print("  fog: %d explored at spawn -> %d after walking the whole corridor (%d floor cells)"
		% [explored_at_start, explored_after, floor_n])
	if explored_after <= explored_at_start:
		_fail("walking up the corridor revealed nothing (%d -> %d cells)"
			% [explored_at_start, explored_after])
	if r.is_explored_cell(far_cell.x, far_cell.y) == false and explored_after < floor_n / 2:
		_fail("after walking the whole corridor only %d of %d floor cells are explored — the reveal radius"
			% [explored_after, floor_n] + " is too small to follow the corridor")
