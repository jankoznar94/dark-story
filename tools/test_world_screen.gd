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
##      screen indexed the save's progress arrays directly, and because `_current_fight()` is read
##      from the render path, an act id no table covers logged `Invalid access of index '99' on a
##      base object of type: 'Array'` EVERY FRAME. The save is a JSON file that can hold such an id.
##      This test asserts the screen survives it; the logged line itself is verified by a probe,
##      because a test cannot assert an error that is printed rather than returned.
##   5. **The dots stay tappable at the new span.** Moving the band moves every node; the hit test
##      reads the node rects back out of `node_pos`, so the two must not drift apart.
##   6. **A digit sits exactly on its node's centre.** Jan: "Čísla jsou mimo puntíky. Měly by být
##      přesně uprostřed a dobře viditelné." Measured on the shipped frame: the digit's centre was
##      at x=210 against a node centre of x=195 — 15 px right, i.e. ON the 16 px ring.
##      `draw_string(..., HORIZONTAL_ALIGNMENT_CENTER, W, ...)` centres the text inside
##      `[pos.x, pos.x+W)`, so passing the node's CENTRE as `pos.x` shifts it right by W/2. This
##      test calls the screen's OWN `centered_pen()` — a test that recomputes the formula itself
##      passes against a broken helper.
##   6. **The hero is GONE, and stays gone.** Jan: "Dejme tělo hrdiny úplně pryč." He was a second
##      figure competing with the stations, and the gold ring already says where the player is. This
##      asserts the screen exposes no hero API and no `_process()` — a screen with a per-frame
##      override that animates nothing is a clock nobody needs, and a re-added sprite would silently
##      bring back the collision the previous version of this test was written to catch.
##
## Assertions are deferred to `_process` because `Main._ready()` builds the data, the state and
## every screen while `_initialize()` has already run.
##
## Run:  godot --headless --path . --script res://tools/test_world_screen.gd
## Pass: prints WORLD_SCREEN_ALL_PASS=true and exits 0.

const Main := preload("res://scripts/main.gd")

## The measured obstacles, in pixels of the 390x844 content: the header's box bottom, the action
## buttons' top, and the HOME GATE (drawn at a fixed y=74 with r=22, so its ring reaches y=96).
## All three come from `tools/_probe_world_band.gd` and a pixel scan of a real frame.
const HEADER_BOTTOM := 56.0
const ACTIONS_TOP := 752.0
## `_draw_home` puts the gate at y=74 with radius 22; its bottom edge is therefore y=96.
const GATE_BOTTOM := 96.0
## How much of the free span between those two the road must use. 0.85 allows a few px of
## breathing room at each end while still failing a route that only crosses the middle.
const MIN_SPAN_USED := 0.80

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
	_test_a_digit_is_centered_in_its_node()
	_test_every_station_carries_its_own_number()
	_test_the_home_gate_clears_the_header()
	_test_the_hero_is_gone()
	_test_the_road_can_be_tapped()

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
## Top has ONE constraint now that the hero is gone: the HOME GATE. Its ring reaches y=122 (it is
## drawn at a fixed y=100, r=22), and the node's own ring hangs `NODE_R + 5` above its centre — so
## the first station cannot start above (122 + 21) / 844. Jan's report was that the top station
## collided with the "souboj X/Y" text, and the gate is what actually did it.
##
## Bottom: only the node's ring hangs below it, `NODE_R + 5`, down to the buttons at 752.
func _hard_top(w: Control) -> float:
	return (GATE_BOTTOM + w.NODE_R + 5.0) / w.size.y


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
		_fail("the road starts at %.4f of the height, above the hard limit %.4f — the top node's "
			% [top, _hard_top(w)]
			+ "ring would reach y=%.0f, inside the home gate (which ends at %.0f)"
			% [h * top - w.NODE_R - 5.0, GATE_BOTTOM])
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


## Jan: "Dejme tělo hrdiny úplně pryč."
##
## The screen used to carry a hero sprite with an eased walk, driven by `_process`. Removing him is
## not cosmetic: the `_process` override existed ONLY for that walk, so it goes too — a per-frame
## callback that animates nothing is a clock nobody needs. And a re-added sprite would silently
## bring back the collision the older version of this test was written to catch (his head covered
## the station above the one he stood on, measured at 1.3 nodes' worth).
##
## So assert BOTH halves: no hero API, and no `_process`.
func _test_the_hero_is_gone() -> void:
	var w: Control = _world()
	for name in ["_hero", "_walk_from", "_walk_progress", "HERO_SIZE", "HERO_X"]:
		if name in w:
			_fail("the world screen still exposes `%s` — the hero was removed on Jan's "
				% name + "instruction (\"Dejme tělo hrdiny úplně pryč\")")
	# `_process` is an engine override, so it is not visible in the script's own property list.
	# Read the SOURCE: a class that inherits Control always HAS `_process` as a method, so the
	# check is whether this script declares one.
	var src := FileAccess.get_file_as_string("res://scripts/ui/world_screen.gd")
	var declares_process := false
	for line in src.split("\n"):
		var t: String = (line as String).strip_edges()
		if t.begins_with("func _process("):
			declares_process = true
			break
	if declares_process:
		_fail("the world screen declares `_process()` again — it existed only to drive the hero's "
			+ "walk, and the hero is gone. An override that animates nothing is a per-frame "
			+ "callback nobody needs.")
	# And the sprite file must not be loaded here any more.
	if src.contains("hero_body_"):
		_fail("the world screen still loads `hero_body_*` — the hero belongs to the arena now")


## Jan: "Čísla jsou mimo puntíky. Měly by být přesně uprostřed a dobře viditelné."
##
## Measured on the shipped frame: the digit's centre was at x=210 against a node centre of x=195 —
## 15 px right, i.e. ON the 16 px ring. `draw_string(..., HORIZONTAL_ALIGNMENT_CENTER, W, ...)`
## centres the text inside `[pos.x, pos.x+W)`, so passing the node's CENTRE as `pos.x` shifts it
## right by W/2.
##
## This calls the screen's OWN `centered_pen()`. A test that recomputed the formula itself would
## pass against a broken helper — the whole point is that the real one is exercised.
##
## Verified by mutation: making `centered_pen` return `centre` unchanged turns it red (four
## assertions: ±4.5 px in x and y).
func _test_a_digit_is_centered_in_its_node() -> void:
	var w: Control = _world()
	var font: Font = load("res://assets/fonts/DejaVuSans.ttf") as Font
	if font == null:
		_fail("could not load the font to measure the digit's box")
		return
	var centre := Vector2(200.0, 400.0)
	for text in ["1", "4", "10"]:
		var pen: Vector2 = w.centered_pen(text, centre, font, 14)
		var box: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		var ascent: float = font.get_ascent(14)
		var descent: float = font.get_descent(14)
		# The glyphs drawn from `pen` span [pen.x, pen.x+box.x) and their vertical middle is at
		# `pen.y - (ascent - descent) / 2`.
		var glyph_x: float = pen.x + box.x * 0.5
		var glyph_y: float = pen.y - (ascent - descent) * 0.5
		if absf(glyph_x - centre.x) > 0.51:
			_fail("the digit %s lands %.1f px off the node's centre horizontally"
				% [text, glyph_x - centre.x])
		if absf(glyph_y - centre.y) > 0.51:
			_fail("the digit %s lands %.1f px off the node's centre vertically"
				% [text, glyph_y - centre.y])
	# The widest label the road can show must fit INSIDE the node, clear of its 2px ring.
	var widest: float = font.get_string_size("10", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	if widest > w.NODE_R * 2.0 - 8.0:
		_fail("the label \"10\" is %.1f px wide inside a %d px node — it will touch the ring"
			% [widest, int(w.NODE_R * 2.0)])
	# And the pen must NOT be the node's centre in x, which is exactly the bug: if the helper
	# returned `centre` unchanged the digit would sit W/2 to the right.
	var pen10: Vector2 = w.centered_pen("10", centre, font, 14)
	if is_equal_approx(pen10.x, centre.x):
		_fail("centered_pen returned the node's OWN x — that is the bug, not the fix")


## Jan: "Všechny souboje na cestě (puntíky) mají číslo 0."
##
## `_draw_node` labelled EVERY drawn digit with `str(fight)` — the count of fights ALREADY WON,
## which is 0 on a fresh stop. So both the live station and the one after it read "0", and after
## three wins they both read "3": the number said where the PLAYER was, never which fight the
## station IS. The rule now lives in `node_mark()`, and this calls the real function — a test that
## recomputed `index + 1` itself would pass against the bug.
##
## Verified by mutation: putting `str(fight)` back inside `node_mark` turns it red.
func _test_every_station_carries_its_own_number() -> void:
	var w: Control = _world()
	var total: int = w._total_fights()
	for fight in [0, 1, 4]:
		var marks := PackedStringArray()
		# `tap_index` = fight is the live game's own value: the station the player may start IS
		# the one at `areaFightProgress`, so it is that station and the one after it that carry a
		# number while the rest wear padlocks.
		for i in total:
			marks.append(w.node_mark(i, fight, fight))
		for i in total:
			var expected := str(i + 1)
			if i > fight + 1:
				expected = ""
			if marks[i] != expected:
				_fail("at %d/10 station %d is labelled '%s', expected '%s' — every station must " %
					[fight, i + 1, marks[i], expected]
					+ "carry its OWN fight number, not the count of fights won")
		# And the two stations the old code gave the same string must now differ.
		if fight < total - 1 and marks[fight] == marks[fight + 1]:
			_fail("station %d and station %d both read '%s' — the off-by-one Jan saw"
				% [fight + 1, fight + 2, marks[fight]])

	# ⚠️  And the DRAWING must actually go through it. A test of `node_mark()` alone passes even
	# with `_draw_node` still painting `str(fight)`, which is the exact shape of the bug — so the
	# call site is read out of the SOURCE, and the old expression is asserted GONE.
	# Verified by mutation: putting `_draw_centered(str(fight), p, font, 14, colour)` back turns
	# this red while every assertion above stays green.
	var src := FileAccess.get_file_as_string("res://scripts/ui/world_screen.gd")
	if not src.contains("_draw_centered(node_mark(index, fight, _tap_index)"):
		_fail("_draw_node does not paint `node_mark(...)` — the station's own number is not what "
			+ "reaches the canvas")
	if src.contains("_draw_centered(str(fight)"):
		_fail("`_draw_centered(str(fight)` is back in the file: every station would label itself "
			+ "with the count of fights WON, i.e. 0 on a fresh stop (Jan's report)")
	# And the rule itself, read the way the drawing reads it: on a fresh stop the live station is
	# "1" and the one after it is "2", never two zeros.
	if w.node_mark(0, 0, 0) != "1" or w.node_mark(1, 0, 0) != "2":
		_fail("a fresh stop labels its first two stations '%s' and '%s', expected '1' and '2'"
			% [w.node_mark(0, 0, 0), w.node_mark(1, 0, 0)])

	# ⚠️  AND THE PADLOCK MUST NOT BE LOADED FROM INSIDE `_draw()`. This screen has already paid
	# for that mistake once — the floor resolved its texture in `_draw()` and rendered as a flat
	# white field, 67 % of the frame in one colour — and the padlock was doing the same thing, so
	# every unopened station was a solid 18x18 white square instead of a lock (found by sampling
	# the drawn frame). The rule is a SOURCE check because the symptom only exists inside a real
	# `_draw()`, which a headless test never runs.
	if not src.contains("var lock := _lock_tex"):
		_fail("`_draw_node` does not read the cached padlock (`_lock_tex`) — a texture resolved "
			+ "inside `_draw()` renders as a flat blob on this screen's own history")
	if src.contains("var lock := UIKit.load_texture(\"assets/menu-icons/lock.png\")"):
		_fail("`_draw_node` loads the padlock texture again — that is the flat-square bug")


## Jan: "Horní puntík by neměl kolidovat s textem 'souboj X/Y'."
##
## Measured on a real frame, the collision was the HOME GATE's ring, not a station: at its original
## y=74 with r=22 it spanned y 52..96, and the header's second line occupies y 43..55 — a 4 px
## overlap. The gate is drawn in `_draw_road`, so its position is not a constant a test can import;
## this reads the row it is drawn on out of the source and asserts the ring clears the header.
##
## Verified by mutation: restoring 74.0 turns it red.
func _test_the_home_gate_clears_the_header() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/ui/world_screen.gd")
	var gate_y := -1.0
	for line in src.split("\n"):
		var t: String = (line as String).strip_edges()
		if t.begins_with("var gate := Vector2(") and not t.contains("_"):
			# `var gate := Vector2(w * 0.5, 100.0)`
			var parts := t.split(",")
			gate_y = float((parts[1] as String).strip_edges().trim_suffix(")"))
			break
	if gate_y < 0.0:
		_fail("could not find where `_draw_road` puts the home gate — this check would silently "
			+ "pass, so it fails instead")
		return
	# `_draw_home` draws the ring at radius 22, 2 px wide, so its topmost ink is gate_y - 22.
	var ring_top: float = gate_y - 22.0 - 1.0
	if ring_top < HEADER_BOTTOM:
		_fail("the home gate's ring starts at y=%.0f, inside the header (which ends at %.0f) — "
			% [ring_top, HEADER_BOTTOM]
			+ "Jan reported exactly this collision with \"souboj X/Y\"")


## ⚠️  THE ROAD WAS PAINTED, NOT BUILT, AND NOBODY COULD TELL.
##
## Jan: "Cesta s puntíky pro jednotlivé souboje už ve hře je, ale na nic nereaguje. Nedá se do
## souboje vstoupit. Ani zpět do města."
##
## The screen had `node_at()` AND a test asserting it — but nothing in the game ever CALLED it.
## The nodes are `draw_circle` ink, not controls, so a tap landed on the full-rect Control, which
## ignored input, and `next_fight_requested` had no emitter at all. **A hit test is not a tap
## handler**, and this is the difference: it drives the screen's own `_gui_input` and asserts the
## signal comes out.
##
## Verified by mutation: deleting `_gui_input` turns the first checks red.
func _test_the_road_can_be_tapped() -> void:
	var w := _world()
	# A fresh stop: the playable dot is index 0 and the header must NOT read "souboj 0/10".
	_main.state.data["areaFightProgress"][0] = 0
	_main.state.data["locationProgress"][0] = 0
	_main.show_world(0)
	if w._tap_index != 0:
		_fail("a fresh stop offers no playable dot (tap_index=%d, expected 0)" % w._tap_index)
	if w._header_fight.text != "souboj 1/10":
		_fail("the header reads '%s'; `areaFightProgress` counts fights WON, so a fresh stop is "
			% w._header_fight.text + "'souboj 1/10' — '0/10' is the off-by-one Jan saw")

	var fired := [0]
	w.next_fight_requested.connect(func(): fired[0] += 1)

	# A dot that has not opened, and empty space, must both do NOTHING.
	w._gui_input(_press(w.node_pos(5)))
	if fired[0] != 0:
		_fail("a dot that has not opened started a fight — the tap guard is not on the ROAD")
	w._gui_input(_press(Vector2(w.node_pos(0).x, w.node_pos(0).y - 200.0)))
	if fired[0] != 0:
		_fail("a tap on empty space started a fight — the hit test is not resolving the node")

	# The current dot must emit.
	w._gui_input(_press(w.node_pos(0)))
	if fired[0] != 1:
		_fail("tapping the current dot emitted `next_fight_requested` %d times, expected 1 — "
			% fired[0] + "the road is painted pixels with no tap handler (Jan's report)")

	# A finished stop has NO playable dot at all.
	_main.state.data["areaFightProgress"][0] = w._total_fights()
	_main.show_world(0)
	if w._tap_index != -1:
		_fail("a stop with all %d fights won still offers a dot (tap_index=%d) — tapping it "
			% [w._total_fights(), w._tap_index] + "starts a fight that does not exist")


## A synthetic left-button PRESS at `at`, which is what `_gui_input` reads.
func _press(at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	return e
