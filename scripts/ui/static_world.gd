extends Node2D
## StaticWorld — the zone's STATIC half, rendered into its own SubViewport at reduced resolution.
##
## Jan, Nov 2026, option C: "Zmenšit jen svět a HUD nechat v nativním rozlišení." The ground, the
## rock, the river, the deck and the baked props cover the whole screen every frame and never move;
## monsters, loot, fog and the HUD are small and must stay crisp. So the static half is rendered
## into a SubViewport that is `RENDER_SCALE` of the screen and stretched back up, and the dynamic
## half is drawn by the screen itself at native resolution.
##
## ⚠️  The drawing math is UNCHANGED — `_world_xform()` here is the screen's ZOOM matrix multiplied
## by `render_scale`, and `_view_world_size()` still answers in the SCREEN's world units. That is
## what keeps the camera, the culling and every prop in exactly the place it was; the only
## difference is how many pixels one world unit is worth.
##
## The functions below are the screen's own painters, moved here because `draw_*()` writes to the
## CanvasItem it is called on: a Control cannot draw into somebody else's viewport, so the painters
## had to live on the node that owns this canvas.

## The screen that owns the run, the camera and the baked meshes. Everything below reads through it.
var screen = null
## How big the world's framebuffer is relative to the screen. 0.5 = a quarter of the pixels.
var render_scale := 0.5
## ⚠️  THE LAYER DRAWS THE WHOLE ZONE, ONCE, WITH NO CAMERA (`bake_world`).
## The first cut of this split re-emitted the static pass every frame with a moving camera inside a
## screen-sized viewport — and measured NOTHING (390x844: 16.3 ms vs 7.2 ms without the split, i.e.
## actually worse; 1080x2340: 20.6 vs 20.8 ms, i.e. flat). The zone is 2460 x 5940 world px, which
## at ZOOM * render_scale = 0.41 is a 1009 x 2436 texture (~10 MB): the whole static world fits in
## one texture, so it is painted ONCE per zone and the screen just blits a window of it. That is
## what turns ~70 static draw calls per frame into ONE.
var bake_world := true

var run:
	get:
		return screen.run
var _theme: Dictionary:
	get:
		return screen._theme
var _cam: Vector2:
	get:
		return Vector2.ZERO if bake_world else screen._cam
var _ground: Texture2D:
	get:
		return screen._ground
var _rock_mesh: ArrayMesh:
	get:
		return screen._rock_mesh
var _prop_mesh: ArrayMesh:
	get:
		return screen._prop_mesh
## ZOOM is the screen's own constant; it is read from the class so the two can never disagree.
const ZOOM := 0.82


func _world_xform() -> Transform2D:
	var s := ZOOM * render_scale
	return Transform2D(Vector2(s, 0.0), Vector2(0.0, s), Vector2.ZERO)


## The world extent this layer paints. In `bake_world` mode that is the WHOLE zone — the texture is
## world-fixed, so the screen's window into it is decided by `_draw()`, not here.
func _view_world_size() -> Vector2:
	if bake_world:
		return SurvivorRun.WORLD
	return screen.size / ZOOM


func _col(key: String, fallback: String) -> Color:
	var value: Variant = _theme.get(key, null)
	if value is Color:
		return value
	return Color(fallback)


## Paint the next shapes in LOCAL world coordinates anchored at `origin` (see the screen's twin).
func _set_local(origin: Vector2, scale: Vector2 = Vector2.ONE) -> void:
	draw_set_transform_matrix(_world_xform() * Transform2D(
		Vector2(scale.x, 0.0), Vector2(0.0, scale.y), origin))


func _set_world() -> void:
	draw_set_transform_matrix(_world_xform())


func _draw() -> void:
	if screen == null or run == null:
		return
	# The backdrop covers THIS canvas, which in `bake_world` mode is the whole zone's texture (the
	# layer is a Node2D inside the SubViewport, so `get_viewport_rect()` is the texture in pixels).
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color("#1b1712"))
	draw_set_transform_matrix(_world_xform())
	_draw_ground()
	_draw_baked(_prop_mesh)
	_set_world()


func _draw_ground() -> void:
	if _ground == null:
		# The world half is drawn under the zoom, so a canvas-sized rect would cover only
		# `ZOOM` of the canvas. Cover the VISIBLE world instead.
		draw_rect(Rect2(_cam, _view_world_size()), Color("#4a4a36"))
		return
	# One tiling call for the whole world, shifted by the camera. `tile = true` repeats the
	# seamless 256px tile; there is no per-tile loop and therefore no tile grid to drift.
	#
	# ⚠️  The grass is painted EVERYWHERE and then the rock is painted OVER it, rather than one
	# draw call per floor cell. `TILE` (60) does not divide the 256 px tile, so drawing the
	# texture cell by cell would break the seamless repeat and the ground would show its grid —
	# exactly the "jednotvárná a nic neříkající" surface Jan complained about.
	#
	# The TINT is the zone's: three new tiles and five palettes would still cover only five
	# places, and a tint costs one multiply where a new 512 px tile costs ~150 KB of first load.
	draw_texture_rect(_ground, Rect2(-_cam, SurvivorRun.WORLD), true,
		_theme.get("tint", Color.WHITE))
	_draw_baked(_rock_mesh)
	# Water and the wooden deck go OVER the rock: the swamp's water is cut through the rock at the
	# area's edge, and a walkway is a thing you see lying on top of the bog.
	_draw_water()
	# The valley's bridge is a STRUCTURE: masonry under the planks. Drawn after the water (its
	# piers stand in it) and BEFORE the deck (the planks cover the middle of a pier, and the few
	# pixels that stick out past them are the whole read).
	_draw_bridge_structure()
	_draw_deck()


## Everything that is NOT the corridor's floor, painted as rock. Cells are merged into runs per
## row, so a wall is one rectangle instead of a row of 60 px squares with seams between them.


func _draw_water() -> void:
	if run == null:
		return
	var view := _view_world_size()
	var c0: Vector2i = run.cell_of(_cam)
	var c1: Vector2i = run.cell_of(_cam + view)
	var t := float(SurvivorRun.TILE)
	var base: Color = _col("water", "#2b3a37")
	var line: Color = _col("water_line", "#435a54")
	var dark := base.darkened(0.35)
	var x0 := maxi(c0.x - 1, 0)
	var x1 := mini(c1.x + 2, SurvivorRun.COLS)
	var y0 := maxi(c0.y - 1, 0)
	var y1 := mini(c1.y + 2, SurvivorRun.ROWS)
	# 1. one rect per run of water in a row.
	for cy in range(y0, y1):
		var x := x0
		while x < x1:
			if not run.is_water_cell(x, cy):
				x += 1
				continue
			var start := x
			while x < x1 and run.is_water_cell(x, cy):
				x += 1
			draw_rect(Rect2(Vector2(float(start) * t, float(cy) * t) - _cam,
				Vector2(float(x - start) * t, t)), base)
	# 2. the bank and 3. the ripples — BATCHED. ⚠️  This used to be up to six `draw_line` calls
	# PER WATER CELL (four bank edges + two ripples), and the valley's river put 80-100 water cells
	# in frame at once: 400-600 draw commands for water alone, which is the frame's whole budget
	# before a single monster is drawn. `draw_multiline` submits the same pixels as ONE command,
	# so the two passes below cost three calls in total no matter how much water is on screen.
	var bank_pts := PackedVector2Array()
	var rip_pts := PackedVector2Array()
	for cy in range(y0, y1):
		for cx in range(x0, x1):
			if not run.is_water_cell(cx, cy):
				continue
			var p := Vector2(float(cx) * t, float(cy) * t) - _cam
			if not run.is_water_cell(cx, cy - 1):
				bank_pts.append(p)
				bank_pts.append(p + Vector2(t, 0))
			if not run.is_water_cell(cx, cy + 1):
				bank_pts.append(p + Vector2(0, t))
				bank_pts.append(p + Vector2(t, t))
			if not run.is_water_cell(cx - 1, cy):
				bank_pts.append(p)
				bank_pts.append(p + Vector2(0, t))
			if not run.is_water_cell(cx + 1, cy):
				bank_pts.append(p + Vector2(t, 0))
				bank_pts.append(p + Vector2(t, t))
			# Two short flat strokes per cell, seeded by the cell so they never crawl.
			var sd := float((cx * 73856093) ^ (cy * 19349663)) * 0.0001
			for k in 2:
				var oy := t * (0.28 + 0.42 * fposmod(sin(sd * (float(k) + 2.3)) * 0.5 + 0.5, 1.0))
				var ox := t * (0.5 + sin(sd + float(k) * 2.1) * 0.18)
				var w := t * (0.14 + 0.09 * fposmod(sd * 1.7, 1.0))
				rip_pts.append(p + Vector2(ox - w, oy))
				rip_pts.append(p + Vector2(ox + w, oy))
	if not bank_pts.is_empty():
		draw_multiline(bank_pts, dark, 3.0)
	if not rip_pts.is_empty():
		draw_multiline(rip_pts, Color(line, 0.55), 2.0)


## THE VALLEY'S BRIDGE AS A STRUCTURE — stone abutments on both banks and piers standing in the
## water. Without it the deck is a strip of planks lying on a river, which is how the first capture
## read ("skôr mólo než most"). Flat colours only: a stone face, one lit top edge, one dark base
## line — the same three tones every other prop in this game uses.


## THE VALLEY'S BRIDGE AS A STRUCTURE — stone abutments on both banks and piers standing in the
## water. Without it the deck is a strip of planks lying on a river, which is how the first capture
## read ("skôr mólo než most"). Flat colours only: a stone face, one lit top edge, one dark base
## line — the same three tones every other prop in this game uses.
func _draw_bridge_structure() -> void:
	if run == null or not run.has_bridge:
		return
	var dir: Vector2i = run.bridge_dir
	if dir == Vector2i.ZERO:
		return
	var t := float(SurvivorRun.TILE)
	var perp := Vector2i(-dir.y, dir.x)
	var stone: Color = _col("stone", "#6a614f")
	var stone_edge: Color = stone.darkened(0.52)
	var stone_top: Color = _col("stone_light", "#857a63")
	var near_c: Vector2i = run.cell_of(run.bridge_near)
	var far_c: Vector2i = run.cell_of(run.bridge_far)
	var steps := maxi(absi(far_c.x - near_c.x), absi(far_c.y - near_c.y))
	if steps < 3:
		return
	var view := _view_world_size()
	var lo := _cam - Vector2(t, t)
	var hi := _cam + view + Vector2(t, t)
	var c0: Vector2i = run.cell_of(_cam)
	var c1: Vector2i = run.cell_of(_cam + view)

	# 1. ABUTMENTS — a stone landing one cell deep on each bank, wider than the deck, so the
	# planks END ON MASONRY instead of stopping in the grass.
	for end in [near_c, far_c]:
		for b in range(-3, 3):
			var cell := Vector2i(end.x + perp.x * b, end.y + perp.y * b)
			var p := Vector2(float(cell.x) * t, float(cell.y) * t) - _cam
			if p.x < lo.x or p.y < lo.y or p.x > hi.x or p.y > hi.y:
				continue
			draw_rect(Rect2(p, Vector2(t, t)), stone)
			draw_line(p, p + Vector2(t, 0), stone_top, 2.0)
			draw_line(p + Vector2(0, t - 2.0), p + Vector2(t, t - 2.0), stone_edge, 2.0)

	# 2. A STONE KERB under the parapet, along every edge of the deck that faces water — and a
	# BUTTRESS where it is thicker, every third cell. This is the whole "it is a built bridge"
	# read: wood over masonry over water, in flat tones. A kerb that is drawn per deck cell is
	# also continuous by construction, so no run of the span is left looking like bare planks.
	for cy in range(maxi(c0.y - 1, 0), mini(c1.y + 2, SurvivorRun.ROWS)):
		for cx in range(maxi(c0.x - 1, 0), mini(c1.x + 2, SurvivorRun.COLS)):
			if not run.is_deck_cell(cx, cy):
				continue
			# How far along the span this cell is, to place the buttresses.
			var along := absi(cx - near_c.x) + absi(cy - near_c.y)
			var thick := 22.0 if along % 3 == 0 else 9.0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := Vector2i(cx + d.x, cy + d.y)
				if not run.is_water_cell(n.x, n.y):
					continue
				var p := Vector2(float(cx) * t, float(cy) * t) - _cam
				var w := Vector2(t, thick) if d.y != 0 else Vector2(thick, t)
				var pos := p
				if d.x > 0:
					pos = p + Vector2(t, 0)
				elif d.y > 0:
					pos = p + Vector2(0, t)
				elif d.x < 0:
					pos = p - Vector2(thick, 0)
				else:
					pos = p - Vector2(0, thick)
				draw_rect(Rect2(pos, w), stone)
				# The lit edge is always on the DECK side: that is the edge you look down at
				# from inside the bridge, and it is what gives the masonry a thickness.
				if d.x > 0:
					draw_line(pos + Vector2(thick - 2.0, 0), pos + Vector2(thick - 2.0, t),
						stone_top, 2.0)
				elif d.x < 0:
					draw_line(pos + Vector2(2.0, 0), pos + Vector2(2.0, t), stone_top, 2.0)
				elif d.y > 0:
					draw_line(pos + Vector2(0, thick - 2.0), pos + Vector2(t, thick - 2.0),
						stone_top, 2.0)
				else:
					draw_line(pos + Vector2(0, 2.0), pos + Vector2(t, 2.0), stone_top, 2.0)

	# 3. The far edge of the masonry, so the kerb does not dissolve into the water: one dark line
	# on the outside of every stone band would double the draw calls for the same read, so the
	# shadow comes from the plank deck's own drop shadow drawn just after this.


## The plank walkway (swamp) and the bridge (river, chasm). `run.feature` decides whether the
## edges facing water get a railing: a walkway through a bog is planks laid on mud, a bridge over
## a river has a rail.


## The plank walkway (swamp) and the bridge (river, chasm). `run.feature` decides whether the
## edges facing water get a railing: a walkway through a bog is planks laid on mud, a bridge over
## a river has a rail.
func _draw_deck() -> void:
	if run == null:
		return
	var view := _view_world_size()
	var c0: Vector2i = run.cell_of(_cam)
	var c1: Vector2i = run.cell_of(_cam + view)
	var t := float(SurvivorRun.TILE)
	var wood: Color = _col("wood", "#4a3a28")
	var light: Color = _col("wood_light", "#5f4b34")
	var seam := wood.darkened(0.42)
	var railed: bool = run.feature == "river" or run.feature == "chasm"
	# The valley's bridge is a LANDMARK, not a crossing: it is 11-15 cells long, and the same 4 px
	# rail that reads fine on a 3-cell swamp walkway disappears into a deck that size. A great
	# bridge gets a taller, lighter parapet with a post on every cell edge — flat, no glow, just
	# more contrast (Jan: "obří most", and the first capture read as a pier with loose stones).
	var great_bridge: bool = railed and run.bridge_span >= 10
	var x0 := maxi(c0.x - 1, 0)
	var x1 := mini(c1.x + 2, SurvivorRun.COLS)
	var y0 := maxi(c0.y - 1, 0)
	var y1 := mini(c1.y + 2, SurvivorRun.ROWS)

	# ⚠️  BATCHED. Every deck cell used to cost 2 rects plus up to eight lines of its own, and the
	# valley's bridge is 4 x 15 cells: measured 525 draw calls with the camera on it against 406 in
	# the start clearing — the bridge alone was a quarter of the frame. Rects now merge into ROW
	# RUNS and every line goes into one `draw_multiline`, so the same picture costs a dozen calls.
	for r in _deck_runs(x0, x1, y0, y1):
		draw_rect(Rect2(r["pos"] + Vector2(2.0, 3.5), r["size"]), Color(0, 0, 0, 0.28))
	for r in _deck_runs(x0, x1, y0, y1):
		draw_rect(Rect2(r["pos"], r["size"]), wood)
	_deck_lines(x0, x1, y0, y1, t, seam, light, railed, great_bridge, wood)


## Deck cells merged into horizontal runs: one rect per run instead of one per cell.


## Deck cells merged into horizontal runs: one rect per run instead of one per cell.
func _deck_runs(x0: int, x1: int, y0: int, y1: int) -> Array:
	var t := float(SurvivorRun.TILE)
	var out: Array = []
	for cy in range(y0, y1):
		var x := x0
		while x < x1:
			if not run.is_deck_cell(x, cy):
				x += 1
				continue
			var start := x
			while x < x1 and run.is_deck_cell(x, cy):
				x += 1
			out.append({
				"pos": Vector2(float(start) * t, float(cy) * t) - _cam,
				"size": Vector2(float(x - start) * t, t),
			})
	return out


## Seams, the lit plank edge and (on a bridge) the rails — each a SINGLE batched multiline call
## instead of a line per cell.


## Seams, the lit plank edge and (on a bridge) the rails — each a SINGLE batched multiline call
## instead of a line per cell.
func _deck_lines(x0: int, x1: int, y0: int, y1: int, t: float, seam: Color, light: Color,
		railed: bool, great_bridge: bool, wood: Color) -> void:
	var seam_pts := PackedVector2Array()
	var edge_pts := PackedVector2Array()
	var rail_pts := PackedVector2Array()
	var rail_shadow_pts := PackedVector2Array()
	var rail: Color = light.lightened(0.55 if great_bridge else 0.30)
	var rail_shadow := wood.darkened(0.55)
	var rail_w: float = 6.0 if great_bridge else 4.0
	for cy in range(y0, y1):
		for cx in range(x0, x1):
			if not run.is_deck_cell(cx, cy):
				continue
			var p := Vector2(float(cx) * t, float(cy) * t) - _cam
			# Planks run ACROSS the walk: east-west walk -> vertical seams, and the other way
			# round. Deciding per CELL (from its own deck neighbours) keeps the seams continuous
			# along a run, which is what makes it read as planks instead of a tile.
			var east_west := bool(run.is_deck_cell(cx - 1, cy)) or bool(run.is_deck_cell(cx + 1, cy))
			var north_south := bool(run.is_deck_cell(cx, cy - 1)) or bool(run.is_deck_cell(cx, cy + 1))
			if east_west and not north_south:
				east_west = false
			for k in [1, 2]:
				var off := t * float(k) / 3.0
				if east_west:
					seam_pts.append(p + Vector2(0, off))
					seam_pts.append(p + Vector2(t, off))
				else:
					seam_pts.append(p + Vector2(off, 0))
					seam_pts.append(p + Vector2(off, t))
			# A lit edge on the north side: the one bright line that gives the plank its thickness.
			edge_pts.append(p)
			edge_pts.append(p + Vector2(t, 0))
			if not railed:
				continue
			# ⚠️  A RAIL IS ONLY A RAIL IF IT READS AGAINST THE PLANKS. A 3 px line in
			# `wood_light` disappeared into the deck in the first capture ("there is no
			# railing, it is a deck lying beside water"), so the rail is an OUTER light edge with
			# a dark line just inside it, plus posts — flat, no glow, but unmistakable.
			if run.is_water_cell(cx, cy - 1):
				rail_pts.append(p + Vector2(0, 2.0))
				rail_pts.append(p + Vector2(t, 2.0))
				rail_shadow_pts.append(p + Vector2(0, 6.0))
				rail_shadow_pts.append(p + Vector2(t, 6.0))
				for px in [10.0, 40.0]:
					rail_pts.append(p + Vector2(px, 0))
					rail_pts.append(p + Vector2(px, 9.0))
			if run.is_water_cell(cx, cy + 1):
				rail_pts.append(p + Vector2(0, t - 2.0))
				rail_pts.append(p + Vector2(t, t - 2.0))
				rail_shadow_pts.append(p + Vector2(0, t - 6.0))
				rail_shadow_pts.append(p + Vector2(t, t - 6.0))
				for px in [10.0, 40.0]:
					rail_pts.append(p + Vector2(px, t - 9.0))
					rail_pts.append(p + Vector2(px, t))
			if run.is_water_cell(cx - 1, cy):
				rail_pts.append(p + Vector2(2.0, 0))
				rail_pts.append(p + Vector2(2.0, t))
				rail_shadow_pts.append(p + Vector2(6.0, 0))
				rail_shadow_pts.append(p + Vector2(6.0, t))
			if run.is_water_cell(cx + 1, cy):
				rail_pts.append(p + Vector2(t - 2.0, 0))
				rail_pts.append(p + Vector2(t - 2.0, t))
				rail_shadow_pts.append(p + Vector2(t - 6.0, 0))
				rail_shadow_pts.append(p + Vector2(t - 6.0, t))
	if not seam_pts.is_empty():
		draw_multiline(seam_pts, seam, 1.5)
	if not edge_pts.is_empty():
		draw_multiline(edge_pts, Color(light, 0.75), 1.5)
	if not rail_shadow_pts.is_empty():
		draw_multiline(rail_shadow_pts, rail_shadow, 1.5)
	if not rail_pts.is_empty():
		draw_multiline(rail_pts, rail, rail_w)


## FOG OF WAR — and after Jan's second pass it has exactly TWO states, not three:
##   * a cell the hero has never been near -> the world under a dark veil (0.45), readable as
##     "there is something there, you have not been there yet", NOT black;
##   * a cell he has been near -> fully lit and it STAYS fully lit. "Již objevená oblast by mohla
##     zůstat normálně barevná. Jen ta neobjevená bude tmavá, ale ne úplně černá."
##
## The first version had Warcraft 2's third state (explored-but-not-visible = veiled again) and it
## read as too aggressive: the map went dark behind the hero every time he walked on.
##
## The veil is a CELL mask (that is the shape the fog is remembered and revealed in) but it is
## PAINTED as a smooth field, not as a cut: every cell is one quad whose four corner alphas are
## the average of the four cells meeting at that corner. Godot interpolates the quad's colour
## across its surface, so the dark ramps up over two cells and there is no grid line anywhere.
## Jan: "udělej ji měkčí" — and a first attempt that merely drew a gradient band along the cell
## border still showed the staircase, because the MASK was blocky even when its edge was soft.
##
## Fully unexplored interior: all four corners 1/1 -> the full 0.45 veil.
## The border between explored and unexplored: corners average 2 of 4 -> half the veil, which is
## what turns the cut into a two-cell fade.


## The baked layer: ONE draw call, with the camera applied as a matrix so the vertices are never
## touched again. The points are stored in world units, so the matrix is exactly what `_world_xform`
## does per point — scale by ZOOM, offset by the camera.
func _draw_baked(mesh: ArrayMesh) -> void:
	if mesh == null:
		return
	draw_set_transform_matrix(Transform2D(Vector2(ZOOM, 0.0), Vector2(0.0, ZOOM), -_cam * ZOOM))
	draw_mesh(mesh, null)
	_set_world()


