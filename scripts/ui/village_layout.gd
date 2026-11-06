extends RefCounted
class_name VillageLayout
## The Village zone as an AUTHORED grid of walkway tiles (Jan's own tileset, Nov 2026).
##
## The village is a treetop settlement: the brown band of a tile is a walkway, the grey rounded
## square is the building's deck (walkable — a junction would be impassable otherwise), and
## everything outside a walkway tile is jungle. Jan drew five tile archetypes and they rotate, so
## all fifteen orientations exist; the atlas below holds every one of them.
##
## ⚠️  THE ONE INVARIANT: an opening on a tile edge must be MUTUALLY matched by its neighbour.
## `mask` is exactly that — bit N=1, S=2, E=4, W=8 — and `tools/probe_village_layout.gd` asserts it,
## plus exactly two openings to the OUTSIDE (the entrance and the exit, both on a walkway, so the
## player walks in from beyond the screen and leaves the same way).

const COLS := 6
const ROWS := 6
## One tile is one screen at the game's zoom (390 wide / 0.82 ≈ 475 world px), so the area is
## 6 x 6 = 36 tiles: 25 walkway tiles and 11 of jungle.
const TILE := 512
const WORLD := Vector2(COLS * TILE, ROWS * TILE)

## The atlas: the FIVE archetypes Jan drew, at full 512 px, in a 3 x 2 grid. The other ten
## orientations are the same art ROTATED — 90° turns are exact on a pixel grid, so nothing is lost
## and the file does not carry each orientation twice.
##
## Jan, Nov 2026: "Určitě chceme detaily." So the tiles are stored at their drawn size and the
## budget goes to detail, not to duplicate rotations: 1536 x 1024 = 6 MB in VRAM (the 15-cell
## version at the same size would be 16 MB). Disk is ~2 KB because it is a three-colour palette.
const ATLAS := "res://assets/village/tiles.png"
const ATLAS_COLS := 3
const ATLAS_CELL := 512
## The drawn archetypes, in the atlas order: dead end, straight, corner, tee, cross.
const ARCHETYPES := [1, 3, 5, 7, 15]

## The jungle that everything else stands in. Seamless, repeated at its own texel size.
const FOREST := "res://assets/village/forest.png"

## `[x, y, mask]` per walkway tile, sorted. Only the 25 listed cells are part of the village.
const CELLS := [
	[0, 0, 6], [0, 1, 7], [0, 2, 11], [0, 3, 3], [0, 4, 7], [0, 5, 5],
	[1, 0, 12], [1, 1, 14], [1, 2, 5], [1, 3, 4], [1, 4, 14], [1, 5, 9],
	[2, 0, 10], [2, 1, 15], [2, 2, 15], [2, 3, 15], [2, 4, 9],
	[3, 0, 2], [3, 1, 11], [3, 2, 15], [3, 3, 9],
	[4, 2, 14], [4, 3, 5],
	[5, 2, 10], [5, 3, 13],
]

## The one way in and the one way out — both on a border, both a walkway running off the screen.
const ENTRY := Vector2i(0, 2)
const EXIT := Vector2i(5, 3)
## Where the hero stands when the zone opens: ON THE WALKWAY, 70 px inside the left edge — never on
## the deck, so he does not appear inside a building.
const SPAWN := Vector2(70.0, 2 * TILE + TILE * 0.5)
## Where the exit is reached: at the mouth of the right-hand walkway, i.e. at the map border.
const EXIT_POINT := Vector2(COLS * TILE - 40.0, 3 * TILE + TILE * 0.5)

const N := 1
const S := 2
const E := 4
const W := 8


## The radius of the hut in the middle of every tile, and of the ring around it (art: 46 and 104).
const HUT_R := 46.0
const RING_R := 104.0


static func mask_at(ix: int, iy: int) -> int:
	for c in CELLS:
		if int(c[0]) == ix and int(c[1]) == iy:
			return int(c[2])
	return 0


static func is_walkway(ix: int, iy: int) -> bool:
	return mask_at(ix, iy) != 0


## Rotating a mask by 90° clockwise: N -> E -> S -> W -> N. A pixel grid makes this exact, which is
## why one drawn tile covers four orientations.
static func turn_mask(mask: int) -> int:
	var out := 0
	if mask & N:
		out |= E
	if mask & E:
		out |= S
	if mask & S:
		out |= W
	if mask & W:
		out |= N
	return out


## Which drawn archetype a mask is, and how many 90° turns to put on it: `Vector2i(base_index,
## turns)`. Index -1 means the mask cannot be built from the archetypes (a data bug).
static func base_and_turns(mask: int) -> Vector2i:
	for i in ARCHETYPES.size():
		var cur := int(ARCHETYPES[i])
		for turns in 4:
			if cur == mask:
				return Vector2i(i, turns)
			cur = turn_mask(cur)
	return Vector2i(-1, 0)


## The atlas region of the DRAWN tile for this mask — the renderer turns the quad by
## `base_and_turns(mask).y * 90°`. Mask 0 (jungle) has no tile.
static func atlas_region(mask: int) -> Rect2:
	var bt := base_and_turns(mask)
	var i := maxi(bt.x, 0)
	return Rect2(float(i % ATLAS_COLS) * ATLAS_CELL, float(i / ATLAS_COLS) * ATLAS_CELL,
		ATLAS_CELL, ATLAS_CELL)


static func cell_rect(ix: int, iy: int) -> Rect2:
	return Rect2(ix * TILE, iy * TILE, TILE, TILE)


## Is this world point on something the hero may stand on? The walkway band is 80 of the 512 px
## (measured off Jan's art: x 216..296), the deck is a 208 px rounded square in the middle.
## Used by the collision once the engine assembles this zone; a plain point query keeps the rule in
## ONE place instead of a per-cell special case.
static func walkable_point(p: Vector2, radius: float = 0.0) -> bool:
	return walkable_in({}, p, radius)


## The same rule for ANY layout (`{"cells": [[x, y, mask], ...]}`), so a generated village and the
## authored one cannot disagree about where a body may stand. An empty layout means `CELLS`.
static func walkable_in(layout: Dictionary, p: Vector2, radius: float = 0.0) -> bool:
	var ix := int(floor(p.x / float(TILE)))
	var iy := int(floor(p.y / float(TILE)))
	if ix < 0 or iy < 0 or ix >= COLS or iy >= ROWS:
		return false
	var m := 0
	for c in (layout.get("cells", CELLS) as Array):
		if int(c[0]) == ix and int(c[1]) == iy:
			m = int(c[2])
			break
	if m == 0:
		return false
	var c := Vector2(ix * TILE + TILE * 0.5, iy * TILE + TILE * 0.5)
	var rel := p - c
	var dist := rel.length()
	# THE HUT IS THE OBSTACLE IN THE MIDDLE of every tile: a round straw-roofed building of
	# 46 px radius. Jan: "kolem něj se dali projít" — so the centre is NOT walkable.
	if dist <= HUT_R + radius:
		return false
	# THE RING: a circular wooden walkway around the hut, 46..104 px from the centre (a 58 px
	# walkway, wide enough for the hero to pass the hut on any side).
	if dist <= RING_R - radius:
		return true
	# The walkway: an 80 px band through the tile centre, towards each open edge (art: x 216..296).
	var half := 40.0 + radius
	if (m & N) and rel.y <= 0.0 and absf(rel.x) <= half:
		return true
	if (m & S) and rel.y >= 0.0 and absf(rel.x) <= half:
		return true
	if (m & E) and rel.x >= 0.0 and absf(rel.y) <= half:
		return true
	if (m & W) and rel.x <= 0.0 and absf(rel.y) <= half:
		return true
	return false

# ============================================================================ generator
## A FRESH village for every entry, from the same five tiles. Jan: "Tenhle grid (pokud tedy bude
## pokaždé jiný, minimálně třeba 10 variant) můžeš použít." The generator is seeded from the zone,
## so coming back to the same zone shows the same village, and a different zone (or act) shows a
## different one — while every layout obeys the same four rules the probe asserts.
##
## The shape is grown by always extending from the cell that has the MOST occupied neighbours: that
## gives a compact blob instead of the thin snake a random walk produces (measured: random growth
## left 1-cell chains where the player walks a 25-tile corridor). The loop count is randomised per
## layout, so some villages are a ring with two branches and others are a dense web.
##
## Returns `{"cells": [[x, y, mask], ...], "entry": Vector2i, "exit": Vector2i, "spawn": Vector2,
## "exit_point": Vector2}` or an EMPTY dictionary when no valid layout was found — the caller then
## falls back to `CELLS`.
static func generate(seed_value: int) -> Dictionary:
	# 64 attempts: about one seed in 300 has a stream that keeps producing a shape without a
	# usable door on both sides, and 24 was not always enough for those (measured: 1 of 300).
	for attempt in 64:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value + attempt * 7919
		var out := _try_generate(rng)
		if not out.is_empty():
			return out
	return {}


static func _try_generate(rng: RandomNumberGenerator) -> Dictionary:
	var start := Vector2i(rng.randi_range(1, 2), rng.randi_range(1, 4))
	var target := 24 + rng.randi_range(0, 3)
	var loops := 4 + 2 * rng.randi_range(0, 3)
	var cells := {start: true}
	while cells.size() < target:
		var best := -1.0
		var best_cell := Vector2i(-1, -1)
		for c in cells:
			for n in _open_neighbours(c):
				if cells.has(n):
					continue
				var near := 0
				for m in _open_neighbours(n):
					if cells.has(m):
						near += 1
				var score := float(near) + rng.randf() * 1.4
				if score > best:
					best = score
					best_cell = n
		if best_cell.x < 0:
			return {}
		cells[best_cell] = true

	# Spanning tree over the blob, then a random handful of extra edges = loops.
	var edges := {}
	var seen := {start: true}
	var stack := [start]
	while not stack.is_empty():
		var c: Vector2i = stack[stack.size() - 1]
		var options: Array = []
		for n in _open_neighbours(c):
			if cells.has(n) and not seen.has(n):
				options.append(n)
		if options.is_empty():
			stack.pop_back()
			continue
		var n: Vector2i = options[rng.randi_range(0, options.size() - 1)]
		edges[_edge_key(c, n)] = true
		seen[n] = true
		stack.append(n)
	if seen.size() != cells.size():
		return {}
	var extra: Array = []
	for c in cells:
		for n in _open_neighbours(c):
			if cells.has(n) and c.x <= n.x and c.y <= n.y and not edges.has(_edge_key(c, n)):
				extra.append(Vector2i(c.x * 8 + n.x, c.y * 8 + n.y))
	for i in extra.size():
		var j := rng.randi_range(i, extra.size() - 1)
		var tmp: Variant = extra[i]
		extra[i] = extra[j]
		extra[j] = tmp
	for i in mini(loops, extra.size()):
		var code: Vector2i = extra[i]
		edges[_edge_key(Vector2i(code.x / 8, code.y / 8), Vector2i(code.x % 8, code.y % 8))] = true

	var masks := {}
	for c in cells:
		var m := 0
		for n in _open_neighbours(c):
			if cells.has(n) and edges.has(_edge_key(c, n)):
				m |= _bit_to(c, n)
		masks[c] = m

	var entry := Vector2i(-1, -1)
	var exits: Array = []
	for c in cells:
		var degree := 0
		for n in _open_neighbours(c):
			if cells.has(n) and edges.has(_edge_key(c, n)):
				degree += 1
		if degree < 2:
			continue
		if c.x == 0:
			entry = c
			break
		if c.x == COLS - 1 or c.y == ROWS - 1:
			exits.append(c)
	if entry.x < 0 or exits.is_empty():
		return {}
	var exit_cell: Vector2i = exits[rng.randi_range(0, exits.size() - 1)]
	masks[entry] = int(masks[entry]) | W
	masks[exit_cell] = int(masks[exit_cell]) | (E if exit_cell.x == COLS - 1 else S)

	var list: Array = []
	for c in cells:
		list.append([c.x, c.y, int(masks[c])])
	list.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out := {
		"cells": list,
		"entry": entry,
		"exit": exit_cell,
		"spawn": Vector2(70.0, float(entry.y) * TILE + TILE * 0.5),
		# ⚠️  The exit point follows the DOOR, not the right edge: a village whose exit is on the
		# bottom border has its walkway running DOWN, and a point at the right edge lands off it.
		"exit_point": (Vector2(float(exit_cell.x) * TILE + TILE - 40.0,
			float(exit_cell.y) * TILE + TILE * 0.5) if exit_cell.x == COLS - 1
			else Vector2(float(exit_cell.x) * TILE + TILE * 0.5,
				float(exit_cell.y) * TILE + TILE - 40.0)),
	}
	if not validate(out):
		return {}
	return out


## The four rules the area must never break. Public so the probe can hammer it: a generated layout
## that fails here is a village the player can get stuck in or walk out of backwards.
static func validate(layout: Dictionary) -> bool:
	var list: Array = layout.get("cells", [])
	if list.size() < 20:
		return false
	var has := {}
	for entry in list:
		has[Vector2i(int(entry[0]), int(entry[1]))] = int(entry[2])
	# 1. every opening is matched by the neighbour's, 2. only the two doors point outside
	var outside := 0
	for c in has:
		var m: int = has[c]
		for pair in [[N, Vector2i(0, -1)], [S, Vector2i(0, 1)], [E, Vector2i(1, 0)], [W, Vector2i(-1, 0)]]:
			if (m & int(pair[0])) == 0:
				continue
			var n: Vector2i = c + (pair[1] as Vector2i)
			if n.x < 0 or n.y < 0 or n.x >= COLS or n.y >= ROWS:
				outside += 1
				continue
			if not has.has(n):
				return false
			if (int(has[n]) & _opposite(int(pair[0]))) == 0:
				return false
	if outside != 2:
		return false
	# 3. the whole village is reachable from the entry, 4. the doors are on the border
	var entry_cell: Vector2i = layout["entry"]
	var exit_cell: Vector2i = layout["exit"]
	if not has.has(entry_cell) or not has.has(exit_cell):
		return false
	var seen := {entry_cell: true}
	var queue := [entry_cell]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		var m: int = has[c]
		for pair in [[N, Vector2i(0, -1)], [S, Vector2i(0, 1)], [E, Vector2i(1, 0)], [W, Vector2i(-1, 0)]]:
			if (m & int(pair[0])) == 0:
				continue
			var n: Vector2i = c + (pair[1] as Vector2i)
			if has.has(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	if seen.size() != has.size():
		return false
	# A compact blob: a thin chain is a corridor, not a village (measured on the first generator).
	var xs := []
	var ys := []
	for c in has:
		xs.append(c.x)
		ys.append(c.y)
	xs.sort()
	ys.sort()
	var box := (int(xs[xs.size() - 1]) - int(xs[0]) + 1) * (int(ys[ys.size() - 1]) - int(ys[0]) + 1)
	# A 6 x 6 box is 36 cells and a village has 24-27 of them, so 0.72 was unreachable once the blob
	# spanned the full grid (the entry is always on x = 0 and the exit on the far side). 0.62 still
	# rejects a snake and accepts every compact blob.
	return float(has.size()) / float(box) >= 0.62


static func _open_neighbours(c: Vector2i) -> Array:
	var out: Array = []
	if c.y > 0:
		out.append(Vector2i(c.x, c.y - 1))
	if c.y < ROWS - 1:
		out.append(Vector2i(c.x, c.y + 1))
	if c.x < COLS - 1:
		out.append(Vector2i(c.x + 1, c.y))
	if c.x > 0:
		out.append(Vector2i(c.x - 1, c.y))
	return out


static func _edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d|%d,%d" % [b.x, b.y, a.x, a.y]


static func _bit_to(from: Vector2i, to: Vector2i) -> int:
	if to.y < from.y:
		return N
	if to.y > from.y:
		return S
	if to.x > from.x:
		return E
	return W


static func _opposite(bit: int) -> int:
	match bit:
		N:
			return S
		S:
			return N
		E:
			return W
	return E
