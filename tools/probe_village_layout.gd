extends SceneTree
## tools/probe_village_layout.gd — the Village grid's own invariants, headless.
##
## The area is authored data (`VillageLayout`), so the ways it can rot are all structural:
##   * an opening with no neighbour opening back (a walkway into jungle),
##   * more than two openings to the OUTSIDE (the area must be closed except for its entrance and
##     its exit, Jan: "jen jedna cesta dovnitř, jedna cesta ven, jinak uzavřeno"),
##   * a tile the hero cannot reach at all,
##   * an entrance or exit that is not a walkway, or that is not on the border,
##   * a spawn point standing on a building instead of on the walkway.
##
## Run: godot --headless --path . --script res://tools/probe_village_layout.gd
## Pass: prints VILLAGE_LAYOUT_OK=true

const VillageLayout := preload("res://scripts/ui/village_layout.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_check(VillageLayout.CELLS.size() == 25,
		"the area must hold 25 walkway tiles, has %d" % VillageLayout.CELLS.size())
	# Every opening is mutual, and every opening that points OUTSIDE is one of the two doors.
	var outside := []
	for c in VillageLayout.CELLS:
		var x := int(c[0])
		var y := int(c[1])
		var m := int(c[2])
		for bit in [VillageLayout.N, VillageLayout.S, VillageLayout.E, VillageLayout.W]:
			if (m & bit) == 0:
				continue
			var nx := x + (1 if bit == VillageLayout.E else -1 if bit == VillageLayout.W else 0)
			var ny := y + (1 if bit == VillageLayout.S else -1 if bit == VillageLayout.N else 0)
			if nx < 0 or ny < 0 or nx >= VillageLayout.COLS or ny >= VillageLayout.ROWS:
				outside.append(Vector2i(x, y))
				continue
			var back := 0
			if bit == VillageLayout.N:
				back = VillageLayout.S
			elif bit == VillageLayout.S:
				back = VillageLayout.N
			elif bit == VillageLayout.E:
				back = VillageLayout.W
			else:
				back = VillageLayout.E
			_check((VillageLayout.mask_at(nx, ny) & back) != 0,
				"tile %d,%d opens into %d,%d, which does not open back — a walkway into jungle"
					% [x, y, nx, ny])
	_check(outside.size() == 2, "exactly two openings to the outside (in and out), got %d: %s"
		% [outside.size(), str(outside)])
	_check(outside.has(VillageLayout.ENTRY) and outside.has(VillageLayout.EXIT),
		"the two openings must be the entrance and the exit, got %s" % str(outside))

	# Both doors are walkway tiles on the border, and the whole village is reachable from the entry.
	for door in [VillageLayout.ENTRY, VillageLayout.EXIT]:
		var d: Vector2i = door
		_check(VillageLayout.is_walkway(d.x, d.y), "door %s must be a walkway tile" % str(d))
		_check(d.x == 0 or d.y == 0 or d.x == VillageLayout.COLS - 1
			or d.y == VillageLayout.ROWS - 1, "door %s must sit on the border" % str(d))
	var reached := _reachable(VillageLayout.ENTRY)
	_check(reached.size() == 25, "all 25 tiles must be reachable from the entry, got %d"
		% reached.size())

	# Jan: "hráč při vstupu do oblasti začínal na lávce (ne v budově)".
	var spawn := VillageLayout.SPAWN
	_check(int(spawn.x / VillageLayout.TILE) == VillageLayout.ENTRY.x
		and int(spawn.y / VillageLayout.TILE) == VillageLayout.ENTRY.y,
		"the spawn must be inside the entrance tile, got %s" % str(spawn))
	_check(VillageLayout.walkable_point(spawn),
		"the spawn point must be ON the walkway, got %s" % str(spawn))
	var deck_centre := Vector2(VillageLayout.ENTRY.x * VillageLayout.TILE + VillageLayout.TILE * 0.5,
		VillageLayout.ENTRY.y * VillageLayout.TILE + VillageLayout.TILE * 0.5)
	_check(spawn.distance_to(deck_centre) > 120.0,
		"the spawn must not be on the deck (%.0f px from the tile centre)" % spawn.distance_to(deck_centre))
	# The exit is reached at the map border, on the walkway that runs off the screen.
	_check(VillageLayout.walkable_point(VillageLayout.EXIT_POINT),
		"the exit point must be on the walkway, got %s" % str(VillageLayout.EXIT_POINT))
	_check(VillageLayout.EXIT_POINT.x > VillageLayout.WORLD.x - 60.0,
		"the exit must be at the map border, got x=%.0f" % VillageLayout.EXIT_POINT.x)

	# The hut in the middle of a tile is an OBSTACLE and the ring around it is the walkway: the hero
	# must be able to pass the hut on all four sides (Jan: "aby se kolem něj dali projít").
	for cell in [Vector2i(0, 0), Vector2i(2, 2), VillageLayout.EXIT]:
		var centre := Vector2(cell.x * 512.0 + 256.0, cell.y * 512.0 + 256.0)
		if not VillageLayout.is_walkway(cell.x, cell.y):
			continue
		_check(not VillageLayout.walkable_point(centre),
			"the hut's centre %s must NOT be walkable — it is the building" % str(centre))
		var ring_mid: float = (VillageLayout.HUT_R + VillageLayout.RING_R) * 0.5
		for dir in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var p: Vector2 = centre + (dir as Vector2) * ring_mid
			_check(VillageLayout.walkable_point(p),
				"the ring must be walkable all the way around: %s is not" % str(p))

	# The atlas really holds all fifteen orientations, and the jungle tile loads.
	var path: String = VillageLayout.ATLAS
	_check(FileAccess.file_exists(path), "the atlas must exist at %s" % path)
	var tex: Texture2D = load(path)
	if tex == null:
		_check(false, "the atlas did not load — run --import first (an unimported PNG is invisible)")
	else:
		_check(tex.get_height() == VillageLayout.ATLAS_CELL * 2,
			"atlas height %d, expected two rows of %d" % [tex.get_height(), VillageLayout.ATLAS_CELL])
		_check(tex.get_width() == VillageLayout.ATLAS_CELL * VillageLayout.ATLAS_COLS,
			"atlas width %d, expected %d" % [tex.get_width(),
				VillageLayout.ATLAS_CELL * VillageLayout.ATLAS_COLS])
		# Every one of the 15 orientations must be ONE drawn archetype plus a whole number of 90°
		# turns — that is what lets the atlas stay at five tiles and still show all fifteen.
		for m in range(1, 16):
			var bt: Vector2i = VillageLayout.base_and_turns(m)
			_check(bt.x >= 0, "mask %d has no archetype — a tile would draw as nothing" % m)
			if bt.x < 0:
				continue
			var cur: int = int(VillageLayout.ARCHETYPES[bt.x])
			for _t in bt.y:
				cur = VillageLayout.turn_mask(cur)
			_check(cur == m, "mask %d: archetype %d turned %d times gives %d"
				% [m, int(VillageLayout.ARCHETYPES[bt.x]), bt.y, cur])
			var r: Rect2 = VillageLayout.atlas_region(m)
			_check(r.position.x >= 0.0 and r.end.x <= tex.get_width()
				and r.end.y <= tex.get_height(),
				"mask %d's atlas region %s falls outside the atlas" % [m, str(r)])
	_check(load(VillageLayout.FOREST) != null, "the jungle tile must load")

	# THE GENERATOR — Jan wants a different village each time ("minimálně třeba 10 variant"), so
	# every seeded layout has to obey the SAME rules as the authored one, and the spawn has to be on
	# the generated walkway, not on the authored one.
	var bad: Array = []
	for s in 300:
		var g: Dictionary = VillageLayout.generate(1000 + s * 37)
		if g.is_empty() or not VillageLayout.validate(g):
			bad.append(1000 + s * 37)
			continue
		var g_spawn: Vector2 = g["spawn"]
		if not VillageLayout.walkable_in(g, g_spawn):
			bad.append(1000 + s * 37)
			continue
		var g_exit: Vector2 = g["exit_point"]
		if not VillageLayout.walkable_in(g, g_exit):
			bad.append(1000 + s * 37)
	_check(bad.is_empty(), "the generator produced %d invalid villages, first seeds: %s"
		% [bad.size(), str(bad.slice(0, 5))])
	# ... and it must really VARY: ten villages may not be ten copies.
	var shapes := {}
	for s in 12:
		var g: Dictionary = VillageLayout.generate(777 + s)
		if g.is_empty():
			continue
		var key := ""
		for c in (g["cells"] as Array):
			key += "%d,%d;" % [int(c[0]), int(c[1])]
		shapes[key] = true
	_check(shapes.size() >= 10, "12 seeds produced only %d distinct villages" % shapes.size())

	for f in _failures:
		print("  FAIL: %s" % f)
	print("VILLAGE_LAYOUT_OK=%s" % ("true" if _failures.is_empty() else "false"))
	quit()


func _reachable(from: Vector2i) -> Dictionary:
	var seen := {from: true}
	var queue := [from]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		var m: int = VillageLayout.mask_at(c.x, c.y)
		var nxt := []
		if m & VillageLayout.N:
			nxt.append(Vector2i(c.x, c.y - 1))
		if m & VillageLayout.S:
			nxt.append(Vector2i(c.x, c.y + 1))
		if m & VillageLayout.E:
			nxt.append(Vector2i(c.x + 1, c.y))
		if m & VillageLayout.W:
			nxt.append(Vector2i(c.x - 1, c.y))
		for n in nxt:
			if n.x < 0 or n.y < 0 or n.x >= VillageLayout.COLS or n.y >= VillageLayout.ROWS:
				continue
			if seen.has(n) or not VillageLayout.is_walkway(n.x, n.y):
				continue
			seen[n] = true
			queue.append(n)
	return seen


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)
