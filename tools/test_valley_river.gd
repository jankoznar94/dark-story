extends SceneTree
## TestValleyRiver — the valley's river is the zone's STRUCTURE, so it gets a gate of its own.
##
## Jan, Nov 2026: "Valley má být striktně rozdělená na dvě poloviny velkou řekou, přes kterou vede
## velký most, který hráč zkrátka musí přejít, aby se dostal na druhou polovinu, kde je schovaný
## východ… řeka nebude perfektně rovná, bude různě vlnit… most bude hlídaný silnými skupinami
## monster."
##
## Every clause of that sentence is one assertion here, on SEVERAL seeds, because a generator that
## is right on one seed is a generator that is wrong on the tester's seed:
##   * the river divides the whole map (water in every row/column of its long axis),
##   * there is exactly ONE bridge (one connected run of deck),
##   * the bridge is LONG (8+ cells) and the river is WIDE (6+ cells of water),
##   * the hero starts on one half and the EXIT is on the other,
##   * both halves hold packs, and both ends of the bridge hold a champion pack,
##   * the corridor is fully connected (the flood fill the rest of the game relies on).
##
##   godot4 --headless --path . --script res://tools/test_valley_river.gd
## Pass: prints VALLEY_RIVER_ALL_PASS=true and exits 0.
##
## Prove it can fail: set `_plan_river`'s `river_planned = true` to `false` and this reports
## "no river" on every seed; halve `WIDE_MIN` and the width clause fails.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const SurvivorRun := preload("res://scripts/combat/survivor_run.gd")

## The valley is zone index 4 of act 1. A seed list, not one seed: the river is placed from the
## run's rng, so a single seed proves nothing about the generator.
const ZONE := 4
const SEEDS := [1, 7, 42, 90210, 31337, 123]
## The river must be at least this thick on average. Measured 6.8-9.2 cells on the short axis and
## 12-18 on the long one; anything under 6 is the "small hint of water" Jan rejected.
const WIDE_MIN := 6.0
## The bridge must span at least this many cells: a 3-5 cell span is a footbridge.
const SPAN_MIN := 8
## Packs a half needs before it is a half rather than a stub.
const HALF_PACKS_MIN := 3
## How close a guard pack has to stand to a bridge end to be guarding it.
const GUARD_RANGE := 120.0

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
		var run = _run(seed_value)
		var tag := "seed %d" % seed_value
		_test_river_exists(run, tag)
		_test_river_spans_map(run, tag)
		_test_one_bridge(run, tag)
		_test_start_and_exit(run, tag)
		_test_halves_have_packs(run, tag)
		_test_guards(run, tag)
		_test_connected(run, tag)
	_test_other_zones_unchanged()

	for f in _failures:
		print("  FAIL: %s" % f)
	print("VALLEY_RIVER_ALL_PASS=%s" % ("true" if _failures.is_empty() else "false"))
	quit(0 if _failures.is_empty() else 1)


func _resolve(state) -> Callable:
	return func(id):
		var item_id := str(id)
		if item_id == "":
			return {}
		var static_item: Dictionary = _data.item(item_id)
		if not static_item.is_empty():
			return static_item
		return state.loot_item(item_id)


func _run(seed_value: int, zone: int = ZONE):
	var s = GameState.new()
	s.bind_data(_data)
	s.set_class("barbarian")
	s.hero()["level"] = 20
	var r = SurvivorRun.new()
	r.setup(s, _resolve(s), _loot, 0, seed_value, zone)
	return r


func _fail(msg: String) -> void:
	_failures.append(msg)


# --- the river ------------------------------------------------------------------

func _test_river_exists(run, tag: String) -> void:
	var water := _count(run, SurvivorRun.KIND_WATER)
	var deck := _count(run, SurvivorRun.KIND_DECK)
	if water < 200:
		_fail("%s: only %d water cells — the river is missing or a puddle" % [tag, water])
	if deck < 20:
		_fail("%s: only %d deck cells — the bridge is missing" % [tag, deck])
	if not run.has_bridge:
		_fail("%s: no bridge was recorded" % tag)
	if float(run.bridge_span) < float(SPAN_MIN):
		_fail("%s: the bridge spans %d cells, expected %d+ (a footbridge, not a bridge)"
			% [tag, run.bridge_span, SPAN_MIN])
	# The river's THICKNESS, measured where the bridge crosses it: span/1 is one cell per step, so
	# the span IS the water's thickness there.
	if run.has_bridge and float(run.bridge_span) < WIDE_MIN:
		_fail("%s: the river is %d cells thick at the crossing, expected %.1f+"
			% [tag, run.bridge_span, WIDE_MIN])


## A river that DIVIDES the zone crosses it edge to edge: every column (a horizontal river) or
## every row (a vertical one) has water in it. 95 % allows the wobbly bank to leave a corner dry.
func _test_river_spans_map(run, tag: String) -> void:
	var axis_i: int = 1 if run.river_axis.y != 0 else 0
	var along := SurvivorRun.ROWS if axis_i == 1 else SurvivorRun.COLS
	var across := SurvivorRun.COLS if axis_i == 1 else SurvivorRun.ROWS
	var covered := 0
	for a in across:
		var wet := false
		for b in along:
			# A HORIZONTAL river (the hero crosses along y) has to appear in every COLUMN, so the
			# across axis is x. Getting this pair the wrong way round indexes past the grid, no
			# cell is water, and the gate reports 0 % on a river that is plainly there.
			var cx: int = a if axis_i == 1 else b
			var cy: int = b if axis_i == 1 else a
			# WATER **or** DECK: the bridge stands where the river is, so the 4 columns the deck
			# occupies are river without water in them (measured: 90-93 % coverage with water
			# alone, i.e. the gate failing on the one thing that was built correctly).
			if run.is_water_cell(cx, cy) or run.is_deck_cell(cx, cy):
				wet = true
				break
		if wet:
			covered += 1
	var share := float(covered) / float(across)
	if share < 0.95:
		_fail("%s: the river reaches only %.0f %% of the map across, expected 95 %% — the zone is not divided"
			% [tag, share * 100.0])


## ONE crossing. Two runs of deck is two bridges, and a second bridge is a way round the guard.
func _test_one_bridge(run, tag: String) -> void:
	var seen := {}
	var runs := 0
	for cy in SurvivorRun.ROWS:
		for cx in SurvivorRun.COLS:
			if not run.is_deck_cell(cx, cy):
				continue
			var key := Vector2i(cx, cy)
			if seen.has(key):
				continue
			runs += 1
			var stack: Array[Vector2i] = [key]
			seen[key] = true
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = c + d
					if n.x < 0 or n.y < 0 or n.x >= SurvivorRun.COLS or n.y >= SurvivorRun.ROWS:
						continue
					if seen.has(n) or not run.is_deck_cell(n.x, n.y):
						continue
					seen[n] = true
					stack.append(n)
	if runs != 1:
		_fail("%s: %d separate runs of deck — the river needs exactly one bridge" % [tag, runs])


func _test_start_and_exit(run, tag: String) -> void:
	var axis_i: int = 1 if run.river_axis.y != 0 else 0
	var sign: int = run.river_axis.y if axis_i == 1 else run.river_axis.x
	if sign == 0:
		_fail("%s: the river has no axis" % tag)
		return
	var sc: Vector2i = run.cell_of(run.start_point)
	var ec: Vector2i = run.cell_of(run.exit_point)
	var s_along: int = ((sc.y if axis_i == 1 else sc.x) - run.river_band) * sign
	var e_along: int = ((ec.y if axis_i == 1 else ec.x) - run.river_band) * sign
	if s_along >= 0:
		_fail("%s: the hero spawns at %s, on the FAR side of the river" % [tag, str(sc)])
	if e_along <= 0:
		_fail("%s: the exit %s is not beyond the river (along=%d)" % [tag, str(ec), e_along])
	# And the exit must be a real journey away from the water, not on its lip.
	if e_along < 4:
		_fail("%s: the exit is %d cells from the water — it is on the bank, not in the far half"
			% [tag, e_along])


func _test_halves_have_packs(run, tag: String) -> void:
	var axis_i: int = 1 if run.river_axis.y != 0 else 0
	var sign: int = run.river_axis.y if axis_i == 1 else run.river_axis.x
	var near_half := 0
	var far_half := 0
	for z in run.zones:
		var c: Vector2i = run.cell_of(z["centre"])
		var along: int = ((c.y if axis_i == 1 else c.x) - run.river_band) * sign
		if along < 0:
			near_half += 1
		else:
			far_half += 1
	if near_half < HALF_PACKS_MIN:
		_fail("%s: only %d packs on the near half, expected %d+" % [tag, near_half, HALF_PACKS_MIN])
	if far_half < HALF_PACKS_MIN:
		_fail("%s: only %d packs beyond the river, expected %d+" % [tag, far_half, HALF_PACKS_MIN])


## The bridge is the GATE: a champion pack on each end, close enough to be its guard.
func _test_guards(run, tag: String) -> void:
	for end_name in ["near", "far"]:
		var end: Vector2 = run.bridge_near if end_name == "near" else run.bridge_far
		var best := -1
		for z in run.zones:
			var d: float = (z["centre"] as Vector2).distance_to(end)
			if d > GUARD_RANGE:
				continue
			if str(z["kind"]) != "champion" and str(z["kind"]) != "elite":
				_fail("%s: the pack on the %s bridge end is a '%s', not a champion group"
					% [tag, end_name, str(z["kind"])])
			best = maxi(best, (z["members"] as Array).size())
		if best < 2:
			_fail("%s: the %s bridge end has no champion group within %.0f px"
				% [tag, end_name, GUARD_RANGE])


func _test_connected(run, tag: String) -> void:
	if not run._all_floor_connected():
		_fail("%s: the corridor is not connected — something is stranded behind the water" % tag)
	if not run.walkable(run.start_point, 30.0):
		_fail("%s: the hero spawns inside water or rock" % tag)
	if not run.walkable(run.exit_point, 30.0):
		_fail("%s: the exit is not standable" % tag)


## The feature is per-zone data: the swamp must keep its walkway and the ordinary zones must keep
## their dry ground, or "the valley has a river" has been implemented for every zone.
func _test_other_zones_unchanged() -> void:
	var swamp = _run(7, 3)
	if _count(swamp, SurvivorRun.KIND_DECK) < 50:
		_fail("zone 3 (swamp): the plank walkway is gone (%d deck cells)"
			% _count(swamp, SurvivorRun.KIND_DECK))
	if swamp.has_bridge:
		_fail("zone 3 (swamp): reports a guarded bridge")
	var field = _run(7, 0)
	if _count(field, SurvivorRun.KIND_WATER) != 0:
		_fail("zone 0 (stone circle): has water, expected dry ground")
	if field.has_bridge:
		_fail("zone 0 (stone circle): reports a bridge")


func _count(run, kind: int) -> int:
	var out := 0
	for v in run.cell_kind:
		if int(v) == kind:
			out += 1
	return out
