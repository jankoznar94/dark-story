class_name ChunkLibrary
extends RefCounted
## ChunkLibrary — the authored pieces a zone is assembled from (Diablo 2 style), instead of one
## procedural walk drawn all the way through the grid.
##
## WHY: Jan, Nov 2026: "Chci plnou mřížku dílů." A hand-drawn piece is deliberate — a room reads as
## a room, a bridge as a bridge — where a drunk walk gives every zone the same wobbly tube. The grid
## is 5 x 12 chunks of 8 x 8 cells (480 x 480 px), so a zone is 40 x 96 cells.
##
## A TEMPLATE is a mask plus a connector contract:
##   mask  8 rows of 8 characters, '#' walkable, '.' rock. (Water and deck are stamped by the
##         zone's terrain feature on top of the assembled floor — see `_apply_zone_feature`.)
##   conn  the edge openings the piece offers: "n", "e", "s", "w". An opening is always the four
##         middle cells of that edge (x 2..5 for n/s, y 2..5 for e/w), so two pieces that face each
##         other ALWAYS line up, whatever their masks look like. That contract is the whole trick.
##   weight how likely the assembler is to pick it among the pieces that fit.
##
## Every template can be used in four rotations; the mask and the connector list are rotated
## together, so "corner n+e" is also "corner e+s", "s+w" and "w+n".
##
## Authoring a new piece = adding one dictionary. No code, no coordinates written twice: the mask
## is the picture and the connector list has to agree with it (a connector with no floor under it
## is refused by `_validate`, so a typo cannot become an unreachable room).

const SIZE := 8
## The opening is SIX cells of the eight. Four was the first draw and it is the mistake Jan already
## rejected once in the walked generator ("teď je příliš úzký s přímý"): 4 cells = 240 px, and a
## thrower that has to keep 232 px of distance cannot back off inside it — measured by
## `test_survivor`, which failed with gap=180 keep=232. Six cells = 360 px, i.e. the 5-7 cell range
## the old `CORRIDOR_HALF_MIN..MAX` produced.
const EDGE_AT := [1, 2, 3, 4, 5, 6]

## Canonical orientation is what is written here; the assembler rotates it. Names say which edges
## the piece OFFERS, so a mismatch is visible in the id itself.
const TEMPLATES := [
	{
		"id": "straight",
		"weight": 12,
		"conn": ["n", "s"],
		"mask": [
			"..######.",
			"..######.",
			"..######.",
			"..######.",
			"..######.",
			"..######.",
			"..######.",
			"..######.",
		],
	},
	{
		"id": "corner",
		"weight": 10,
		"conn": ["n", "e"],
		# Comes down from the north, turns east. A real elbow, not a diagonal chamfer: from the
		# top-down camera a diagonal wall reads as a cut corner, not as a turn.
		"mask": [
			"..######.",
			"..#######",
			"..#######",
			"..#######",
			"..#######",
			"..#######",
			"..#######",
			"..######.",
		],
	},
	{
		"id": "tee",
		"weight": 7,
		"conn": ["n", "e", "s"],
		"mask": [
			"..######.",
			"..#######",
			"..#######",
			"..#######",
			"..#######",
			"..#######",
			"..#######",
			"..######.",
		],
	},
	{
		"id": "room",
		"weight": 6,
		"conn": ["n", "s"],
		# The corridor passes through a chamber: same mask as the tee, but it only PROMISES north
		# and south, so the east bulge is where a pack can stand in formation.
		"mask": [
			"..######.",
			"..######.",
			"#########",
			"#########",
			"#########",
			"#########",
			"..######.",
			"..######.",
		],
	},
	{
		"id": "hall",
		"weight": 3,
		"conn": ["n", "e", "s", "w"],
		# Fully open: the zone's crossroads, the gates, and the only piece wide enough for an elite
		# pack and the hero to move around each other.
		"mask": [
			"########",
			"########",
			"########",
			"########",
			"########",
			"########",
			"########",
			"########",
		],
	},
	{
		"id": "grand",
		"weight": 3,
		"conn": ["n", "e", "s", "w"],
		# The cathedral: an 8x8 hall with four pillars. Two-cell lanes everywhere, so a pack can
		# circle a pillar while the hero picks his angle — the one piece that reads as a ROOM rather
		# than as a corridor that widened. Pillars are rock in the mask, so nothing else had to learn
		# about them.
		"mask": [
			"########",
			"########",
			"##.##.##",
			"########",
			"########",
			"##.##.##",
			"########",
			"########",
		],
	},
	{
		"id": "wide",
		"weight": 5,
		"conn": ["n", "s"],
		# A bulge to the FULL eight cells with only north and south promised: the side chambers where
		# a pack stands in formation, and what stops a zone from reading as a tube with scenery.
		"mask": [
			"..######.",
			"..######.",
			"########",
			"########",
			"########",
			"########",
			"..######.",
			"..######.",
		],
	},
	{
		"id": "pocket",
		"weight": 4,
		"conn": ["n"],
		# A dead end with a wide chamber at the bottom: the loot/elite pocket. Branches exist so the
		# main route is a CHOICE — a single path with scenery is a corridor, not a dungeon.
		"mask": [
			"..######.",
			"..######.",
			"..######.",
			"..######.",
			"..######.",
			"########",
			"########",
			"########",
		],
	},
]

const DIR_STEPS := {"n": 0, "e": 1, "s": 2, "w": 3}
const STEPS_DIR := ["n", "e", "s", "w"]


## Every template in all four rotations, as {id, mask, conn, weight, steps}. Built once.
static func variants() -> Array:
	var out: Array = []
	for t in TEMPLATES:
		var mask: Array = t["mask"]
		var conn: Array = t["conn"]
		for steps in 4:
			if steps > 0:
				mask = rotate(mask)
				conn = _rotate_conn(conn)
			out.append({
				"id": str(t["id"]),
				"weight": int(t["weight"]),
				"mask": mask,
				"conn": conn.duplicate(),
				"steps": steps,
			})
	return out


## 90 degrees clockwise: the cell at (x, y) lands at (SIZE-1-y, x).
static func rotate(mask: Array) -> Array:
	var out: Array = []
	for y in SIZE:
		var row := ""
		for x in SIZE:
			row += str(mask[SIZE - 1 - x])[y]
		out.append(row)
	return out


static func _rotate_conn(conn: Array) -> Array:
	var out: Array = []
	for c in conn:
		out.append(STEPS_DIR[(DIR_STEPS[str(c)] + 1) % 4])
	return out


## The piece to use for a chunk that must offer `needed` (an array of "n"/"e"/"s"/"w").
## Prefers an EXACT fit — a room must not silently grow a third opening that leads into rock —
## and only falls back to a superset when nothing matches.
static func pick(needed: Array, rng: RandomNumberGenerator, pool: Array = []) -> Dictionary:
	var all: Array = pool if not pool.is_empty() else variants()
	var best: Array = []
	var best_extra := 99
	for v in all:
		var extra := 0
		var ok := true
		for d in needed:
			if not (v["conn"] as Array).has(d):
				ok = false
				break
		if not ok:
			continue
		extra = (v["conn"] as Array).size() - needed.size()
		if extra < best_extra:
			best_extra = extra
			best = [v]
		elif extra == best_extra:
			best.append(v)
	if best.is_empty():
		return {}
	var total := 0
	for v in best:
		total += int(v["weight"])
	var roll := rng.randi_range(1, maxi(total, 1))
	var acc := 0
	for v in best:
		acc += int(v["weight"])
		if roll <= acc:
			return v
	return best[0]


## Every rotation of one template id — used when a chunk MUST be a particular piece (the gates are
## always an open hall, so the hero never materialises in a 4-wide tube).
static func pool(id: String) -> Array:
	var out: Array = []
	for v in variants():
		if str(v["id"]) == id:
			out.append(v)
	return out


## The gate piece: a chunk on the map's edge that the hero enters (or leaves) through. It must be
## a room in the middle — the hero materialises there — and offer exactly one way further in.
static func gate(rng: RandomNumberGenerator) -> Dictionary:
	var all: Array = []
	for v in variants():
		if str(v["id"]) == "room" or str(v["id"]) == "hall" or str(v["id"]) == "tee":
			all.append(v)
	return pick([], rng, all)


## A connector only counts if there is floor under it. Called on the canonical set at load; a piece
## whose mask and connector list disagree is a bug that would otherwise show up as a hero walking
## into a wall forty minutes into a run.
static func validate() -> Array:
	var bad: Array = []
	for v in variants():
		var id := str(v["id"])
		var mask: Array = v["mask"]
		for d in v["conn"]:
			var cells := _edge_cells(str(d))
			var open := 0
			for c in cells:
				if str(mask[c.y])[c.x] == "#":
					open += 1
			if open != cells.size():
				bad.append("%s (rot %d) offers %s but only %d/%d of its edge is floor"
					% [id, int(v["steps"]), d, open, cells.size()])
	return bad


static func _edge_cells(d: String) -> Array:
	var out: Array = []
	match d:
		"n":
			for i in EDGE_AT:
				out.append(Vector2i(i, 0))
		"s":
			for i in EDGE_AT:
				out.append(Vector2i(i, SIZE - 1))
		"w":
			for i in EDGE_AT:
				out.append(Vector2i(0, i))
		"e":
			for i in EDGE_AT:
				out.append(Vector2i(SIZE - 1, i))
	return out
