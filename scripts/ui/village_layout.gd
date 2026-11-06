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
	var ix := int(floor(p.x / float(TILE)))
	var iy := int(floor(p.y / float(TILE)))
	if ix < 0 or iy < 0 or ix >= COLS or iy >= ROWS:
		return false
	var m := mask_at(ix, iy)
	if m == 0:
		return false
	var c := Vector2(ix * TILE + TILE * 0.5, iy * TILE + TILE * 0.5)
	var rel := p - c
	# The deck: a 208 px square with the corners taken off, which is what the art shows
	# (measured: x 152..360 of the 512 px tile). Half of it, minus the body, is 104.
	var deck := 104.0 - radius
	if absf(rel.x) <= deck and absf(rel.y) <= deck:
		return true
	if absf(rel.x) + absf(rel.y) <= deck * 1.72:
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
