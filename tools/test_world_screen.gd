extends SceneTree
## tools/test_world_screen.gd — the wilderness road ("putování"), driven headlessly.
##
## This screen had NO test at all until now, and that is exactly why three of its bugs survived
## a whole session: a floor whose texture was resolved inside `_draw()` (and came out flat white,
## 67 % of the frame in ONE colour), a road band drawn under the dots, and a route that only used
## the middle third of the screen. Every one of them is a screen that builds, renders and looks
## plausible, so only a test can pin the rule.
##
## What is pinned, and why each needs a test rather than an eye:
##
##   1. **The road spans the whole picture.** Jan: "puntíky by měly být tak nějak od horní hrany
##      obrázku ke spodní." The band is bounded by the HEADER (which ends at y=56) and the ACTION
##      BUTTONS (which start at y=752) — and the top node is the dangerous one, because the hero
##      sprite is drawn UPWARD from his node, 96 px tall. The bounds are DERIVED here from that
##      geometry rather than written as constants, so they cannot drift out of date: the test
##      recomputes the hard limits and checks both that the band respects them AND that it uses
##      almost all of the space between them. A two-sided check, because a floor-only assertion
##      passes a route that stops in the middle of the screen.
##   2. **The area art is `assets/areas/area_<act>.webp`, not the arena's stop art.** They are
##      deliberately different files: the stop art is what the FIGHT shows behind the duel, the
##      area art is the view of the same area the player enters. Loading the wrong one is
##      invisible to any geometry assertion — the screen fills either way.
##   3. **Every area's file exists and has real bytes.** Measured, not assumed: this repo shipped
##      a JPEG under a `.png` name, the importer refused it silently, and the screen drew a
##      `visible` TextureRect with a NULL texture. Godot sniffs CONTENT, so the check is the magic
##      bytes, never the extension.
##   4. **An out-of-range act id reads DEFENSIVELY rather than spamming the log.** Measured: the
##      screen indexed the save's progress arrays directly, and because `_place_hero()` ->
##      `_hero_anchor()` -> `_current_fight()` runs from `_process`, an act id no table covers
##      logged `Invalid access of index '99' on a base object of type: 'Array'` EVERY FRAME. The
##      save is a JSON file that can hold such an id. This test asserts the screen survives it;
##      the logged line itself is verified by `tools/_probe_stop_art_range.gd`, because a test
##      cannot assert an error that is printed rather than returned.
##   5. **The dots stay tappable at the new span.** Moving the band moves every node; the hit test
##      reads the node rects back out of `node_pos`, so the two must not drift apart.
##   6. **The hero covers no node.** Jan: "Hrdina ... musí být bokem tak, ať nic nepřekrývá." His
##      sprite is 72 px tall and 72 wide, drawn from his feet UPWARD from `_hero_anchor()`, and
##      the stations are only 64.7 px apart — so standing him ON a node covered the one above
##      (measured: 1.3 nodes' worth). This asserts the RECTANGLES do not intersect, for every
##      fight on the road and mid-walk too, which is the assertion that would have caught it.
##
## Assertions are deferred to `_process` because `Main._ready()` builds the data, the state and
## every screen while `_initialize()` has already run.
##
## Run:  godot --headless --path . --script res://tools/test_world_screen.gd
## Pass: prints WORLD_SCREEN_ALL_PASS=true and exits 0.

const Main := preload("res://scripts/main.gd")

## The measured obstacles, in pixels of the 390x844 content: the header's box bottom and the
## action buttons' top. Both come from `tools/_probe_world_band.gd` against the real screen.
const HEADER_BOTTOM := 56.0
const ACTIONS_TOP := 752.0
## How much of the free span between those two the road must use. 0.85 allows a few px of
## breathing room at each end while still failing a route that only crosses the middle.
const MIN_SPAN_USED := 0.85

var _failures: Array[String] = []
var _main: Node = null
var _started := false


func _initialize() -> void:
	_main = Main.new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		if _main._nav_bar == null or _main.state == null:
			return false
		_started = true
		_run()
		return false
	return false


func _run() -> void:
	_test_the_road_spans_the_picture()
	_test_node_positions_are_monotone_downward()
	_test_the_dots_are_still_tappable()
	_test_the_area_art_is_its_own_file_per_act()
	_test_every_area_file_has_real_bytes()
	_test_an_unknown_act_falls_back_without_crashing()
	_test_the_hero_covers_no_node()

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("WORLD_SCREEN_ALL_PASS=true")
	else:
		print("WORLD_SCREEN_ALL_PASS=false")
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _world() -> Control:
	return _main._screens["world"]


## The hard limits the geometry allows, in screen fractions. Recomputed here so the test states
## the RULE, not a copy of the constant it is checking.
##
## Top: the hero's feet are ON the node and the sprite is 96 px tall, drawn upward, so his head is
## at `y - HERO_SIZE + 14`. Bottom: only the node's ring hangs below it, `NODE_R + 5`.
func _hard_top(w: Control) -> float:
	return (HEADER_BOTTOM + w.HERO_SIZE - 14.0) / w.size.y


func _hard_bottom(w: Control) -> float:
	return (ACTIONS_TOP - w.NODE_R - 5.0) / w.size.y


## TWO-SIDED on purpose: the bug this replaced made the value too SMALL (0.30/0.72 = the middle
## 42 % of the screen), and a floor-only assertion would have passed it.
func _test_the_road_spans_the_picture() -> void:
	var w: Control = _world()
	var h: float = w.size.y
	var top: float = w.ROAD_TOP
	var bottom: float = w.ROAD_BOTTOM

	if bottom <= top:
		_fail("the road band is inverted: top %.3f, bottom %.3f" % [top, bottom])
		return

	# 1. It must not run into the header, nor into the buttons.
	if top < _hard_top(w):
		_fail("the road starts at %.4f of the height, above the hard limit %.4f — the hero on "
			% [top, _hard_top(w)]
			+ "the top node would reach y=%.0f, inside the header (ends at %.0f)"
			% [h * top - w.HERO_SIZE + 14.0, HEADER_BOTTOM])
	if bottom > _hard_bottom(w):
		_fail("the road ends at %.4f of the height, past the hard limit %.4f — the bottom node's "
			% [bottom, _hard_bottom(w)]
			+ "ring would reach y=%.0f, inside the action buttons (start at %.0f)"
			% [h * bottom + w.NODE_R + 5.0, ACTIONS_TOP])

	# 2. And it must USE the space — this is the half a floor-only check misses.
	var used: float = (bottom - top) / (_hard_bottom(w) - _hard_top(w))
	if used < MIN_SPAN_USED:
		_fail("the road uses only %.0f%% of the space between the header and the buttons — the "
			% (used * 100.0)
			+ "journey must cross the picture, not sit in its middle (need %.0f%%)"
			% (MIN_SPAN_USED * 100.0))


## The journey runs DOWN the screen, as the shipped map's stop path does (stop 1 at the top).
## A sign error here mirrors the whole route and no geometry assertion above would notice.
func _test_node_positions_are_monotone_downward() -> void:
	var w: Control = _world()
	var prev: float = -1.0
	for i in w._total_fights():
		var p: Vector2 = w.node_pos(i)
		if i > 0 and p.y <= prev:
			_fail("node %d is at y=%.1f, not below node %d at y=%.1f — the road must run DOWN"
				% [i + 1, p.y, i, prev])
		prev = p.y
		# And every node must stay on screen, clear of the edges the serpentine is clamped to.
		if p.x < 34.0 or p.x > w.size.x - 34.0:
			_fail("node %d is at x=%.1f, off the road's clamped 34..%d band"
				% [i + 1, p.x, int(w.size.x) - 34])


## Moving the band moves every node, and the hit test reads the node rects back out of
## `node_pos` — so the two must not drift apart. A tap that misses its own node is the failure
## this catches.
func _test_the_dots_are_still_tappable() -> void:
	var w: Control = _world()
	var misses := 0
	for i in w._total_fights():
		if w.node_at(w.node_pos(i)) != i:
			misses += 1
	if misses > 0:
		_fail("%d of %d nodes do not resolve to themselves in the hit test"
			% [misses, w._total_fights()])


## The area art is its OWN file per act, and it is NOT the arena's stop art. Loading the stop art
## here would make the world and the fight show the same view, which is the opposite of the design.
func _test_the_area_art_is_its_own_file_per_act() -> void:
	var w: Control = _world()
	var saved: int = int(_main.state.data.get("_currentAct", 0))
	for act in 5:
		_main.state.data["_currentAct"] = act
		var tex: Texture2D = w._area_art()
		if tex == null:
			_fail("act %d resolved NO area art at all" % act)
			continue
		if tex.resource_path.contains("assets/stops/"):
			_fail("act %d resolved the ARENA's stop art (%s) — the area view must be its own file"
				% [act, tex.resource_path])
		elif not tex.resource_path.contains("assets/areas/area_%d" % act):
			_fail("act %d resolved %s, expected assets/areas/area_%d.webp"
				% [act, tex.resource_path, act])
	_main.state.data["_currentAct"] = saved


## Measured, not assumed. Godot's importer sniffs CONTENT, so a file with the wrong bytes under
## the right name is refused silently and the screen draws `visible` with a null texture. This
## repo has already shipped a JPEG named `.png` once.
func _test_every_area_file_has_real_bytes() -> void:
	for act in 5:
		var path := "res://assets/areas/area_%d.webp" % act
		if not FileAccess.file_exists(path):
			_fail("%s does not exist" % path)
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			_fail("%s cannot be opened" % path)
			continue
		var head := f.get_buffer(12)
		f.close()
		if head.size() < 12:
			_fail("%s is truncated (%d bytes)" % [path, head.size()])
			continue
		var is_webp: bool = head.slice(0, 4) == "RIFF".to_ascii_buffer() \
			and head.slice(8, 12) == "WEBP".to_ascii_buffer()
		if not is_webp:
			_fail("%s has the wrong magic bytes — the importer refuses it silently" % path)


## An act id no table covers must fall back, not crash. This is the assertion that found the real
## bug: `_stop_art()` indexed `locationProgress` unchecked and died on an Array out of bounds.
func _test_an_unknown_act_falls_back_without_crashing() -> void:
	var w: Control = _world()
	var saved: int = int(_main.state.data.get("_currentAct", 0))
	_main.state.data["_currentAct"] = 99
	var tex: Texture2D = w._area_art()
	_main.state.data["_currentAct"] = saved
	# It may legitimately resolve nothing if no placeholder exists for act 99; what it must NOT do
	# is take the screen down. Reaching this line at all is most of the assertion.
	if tex != null and tex.resource_path.contains("assets/areas/"):
		_fail("act 99 resolved an area file (%s) — there is none, so the fallback was skipped"
			% tex.resource_path)


## Jan: "Hrdina ... musí být bokem tak, ať nic nepřekrývá." RECTANGLE intersection, not a centre
## distance: the sprite is a box, not a point, and it is drawn UPWARD from his feet.
##
## Checked for EVERY fight, standing and mid-walk, because the walk moves him through the column
## the nodes live in. A test that only checked the resting pose would pass a walk that cuts
## straight through a node.
##
## ⚠️  `size` here is the SceneTree harness's own 844x844, not the game's 390x844 — the documented
## trap. That does NOT weaken this particular check: `node_pos()` and `_hero_anchor()` both
## derive their X as a FRACTION of `size.x`, and the horizontal clamp is a fixed 34 px, so the
## clearance is near-constant in proportion. Verified as a mutation (hero moved to the route's
## own centre 0.42 -> 419 intersecting poses), NOT assumed.
func _test_the_hero_covers_no_node() -> void:
	var w: Control = _world()
	var saved_act: int = int(_main.state.data.get("_currentAct", 0))
	var saved_prog: int = int(_main.state.data["areaFightProgress"][0])
	var half: float = w.HERO_SIZE * 0.5

	var collisions := 0
	# `_walk_from = -1` is the "just arrived, walking in" state; then every pair of stations.
	var walks: Array = [-1, 0, 1, 2, 3, 4, 5, 6, 7, 8]
	for fight in range(1, w._total_fights() + 1):
		_main.state.data["areaFightProgress"][0] = fight
		for walk_from in walks:
			w._walk_from = walk_from
			# Sample the whole walk, not just its ends.
			for step in [0.0, 0.25, 0.5, 0.75, 1.0]:
				w._walk_progress = step
				var a: Vector2 = w._hero_anchor()
				var hero := Rect2(a.x - half, a.y - w.HERO_SIZE + 14.0, w.HERO_SIZE, w.HERO_SIZE)
				for i in w._total_fights():
					var p: Vector2 = w.node_pos(i)
					var ring: float = w.NODE_R + 5.0  # the gold ring is the widest a node gets
					var node := Rect2(p.x - ring, p.y - ring, ring * 2.0, ring * 2.0)
					if hero.intersects(node):
						collisions += 1

	w._walk_from = 0
	w._walk_progress = 1.0
	_main.state.data["_currentAct"] = saved_act
	_main.state.data["areaFightProgress"][0] = saved_prog

	if collisions > 0:
		_fail("the hero's box intersects a node's ring in %d of the sampled poses — he must "
			% collisions + "stand clear of every station, not cover one")

	# And he must stay ON the canvas: a column too far right would be clipped by the edge.
	var anchor: Vector2 = w._hero_anchor()
	if anchor.x - half < 0.0 or anchor.x + half > w.size.x:
		_fail("the hero's column at x=%.0f (box %.0f..%.0f) runs off the %d px canvas"
			% [anchor.x, anchor.x - half, anchor.x + half, int(w.size.x)])
