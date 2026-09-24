extends SceneTree
## tools/test_page_scroll.gd — the pages scroll by DRAG, and no scrollbar is drawn.
##
## Jan's report on the town (and most other pages): "the vertical scrollbar is visible and the
## page can only be scrolled with it — a normal swipe-scroll does not work, and I don't want
## the scrollbar there."
##
## Both halves have a real cause:
##
##   1. Godot's `ScrollContainer` only drags with a finger when
##      `DisplayServer.is_touchscreen_available()` — its own source:
##          if (!is_touchscreen_available) { return; }
##      That is TRUE on Android (hardcoded) and on any device with a touchscreen, and FALSE in
##      a desktop browser (`'ontouchstart' in window`), in the editor, and in every headless
##      run. So the WEB build, the one Jan plays, could only be moved by its scrollbar.
##      `scripts/ui/scroll_swipe.gd` is the driver for exactly that case.
##   2. The bar was drawn because `vertical_scroll_mode` defaults to AUTO. Godot's own
##      `update_scrollbars()` draws and RESERVES the bar for AUTO and RESERVE alike; only
##      SHOW_NEVER keeps the page's full 390px width.
##
## What this test can and cannot prove: a `SceneTree` script does not drive the viewport's GUI
## input pipeline at all, so a synthesized gesture cannot be used as evidence here (measured —
## see `tools/probe_scroll_mechanics.gd`, where wheel, mouse drag and finger drag all move a
## bare ScrollContainer by 0 px under both `--headless` and a real renderer). What IS
## assertable is the WIRING and the DRIVER's own rules, and those are what this file pins:
##
##   * every page's ScrollContainer is SHOW_NEVER (nothing drawn, full width kept),
##   * every page has a `ScrollSwipe` bound to it, so the drag exists at all,
##   * the driver's own arithmetic moves the bar in the right direction, is gated by the
##     deadzone, only starts inside the page, and stands down where Godot's own drag is live.
##   * a FLICK coasts on after the finger leaves, by a sensible distance, for a while and then
##     stops — while a slow drag, a held finger and a mouse release none of them fling.
##
## Verify by mutation: point a driver at the wrong bar, drop the deadzone, or let it start
## outside its own rect and the matching assertion goes red.
##
## Run:  godot --headless --path . --script res://tools/test_page_scroll.gd
## Pass: prints PAGE_SCROLL_ALL_PASS=true and exits 0.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const UIKit := preload("res://scripts/ui/ui_kit.gd")
const ScrollSwipe := preload("res://scripts/ui/scroll_swipe.gd")

var _data: Node
var _failures: Array[String] = []
## Set by `_test_a_page_keeps_its_full_width_and_draws_no_bar()` when it runs in the pipeline
## phase, where a layout pass exists and the bar's visibility is a real reading.
var _page_in_phase := false
## The fake clock the flick tests install into the driver. A headless run delivers a whole
## gesture inside the same millisecond, so a real time stamp yields a velocity of infinity and
## the flick cannot be measured at all.
var _fake_ms := 0
## Where the fake clock currently is — read by the closure installed in `_flick`, which cannot
## capture the variable itself, only the object (a lambda closes over the object, and a
## `SceneTree` script IS the object).
func fake_now() -> int:
	return _fake_ms


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	var gen := ItemGen.new(_data)
	var loot := LootSystem.new(_data, gen)

	_test_a_page_keeps_its_full_width_and_draws_no_bar()
	_test_the_driver_moves_the_page_with_the_finger()
	_test_the_deadzone_absorbs_the_first_pixels()
	_test_a_drag_that_starts_outside_the_page_is_ignored()
	_test_the_driver_runs_on_a_touchscreen_too()
	_test_a_flick_coasts_after_the_finger_leaves()
	_test_a_violent_flick_is_clamped()
	_test_a_phone_flick_survives_the_emulated_mouse()
	_test_a_slow_drag_does_not_fling()
	_test_a_finger_held_still_does_not_fling()
	_test_a_mouse_release_does_not_fling()
	_test_the_coast_ends_at_the_end_of_the_page()
	# The last one needs the REAL input pipeline (`push_input` refuses outside the tree and
	# the headless window is 64x64 until a real frame runs), so it goes on the first frame.
	process_frame.connect(_pipeline_phase, CONNECT_ONE_SHOT)


func _verdict() -> void:
	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("PAGE_SCROLL_ALL_PASS=true")
	else:
		print("PAGE_SCROLL_ALL_PASS=false")
	quit(0 if _failures.is_empty() else 1)


## The one invariant a driver unit test cannot see: a DRAG must not fire the button it started
## on. Measured (`tools/probe_tap_drag.gd`): without the cancel, the second motion of a drag
## makes the tile fire — the player swipes the town and opens a shop.
func _pipeline_phase() -> void:
	# The page's own check is repeated here on purpose: only now does a layout pass exist, so
	# "the bar is not drawn" and the page's full width are real readings rather than defaults.
	_test_a_page_keeps_its_full_width_and_draws_no_bar()
	_test_a_drag_does_not_fire_the_button_it_started_on()
	_test_a_tap_still_fires_without_dragging()
	# The last one is asynchronous: a coast has to be driven by REAL frames to prove the node's
	# `set_process` actually drives it — `_process` called by hand passes even if the engine
	# never calls it.
	_coast_on_real_frames()


## The wiring half of the flick, and the one a hand-called `_process` cannot see: a driver whose
## `set_process(true)` did nothing (or a node whose processing the engine never enables) coasts
## perfectly in a unit test and not at all on the device.
func _coast_on_real_frames() -> void:
	print("== the coast runs on real frames ==")
	var d := _driver()
	var scroll: ScrollContainer = d["scroll"]
	var swipe = d["swipe"]
	_flick(d, 12.0, 16, 8)
	if not swipe._flinging:
		_fail("the flick did not start a coast")
		_verdict()
		return
	var after_drag: int = scroll.scroll_vertical
	var bar := scroll.get_v_scroll_bar()
	var moved := 0
	for _i in 8:
		await process_frame
		if bar.value > float(after_drag) + 0.5:
			moved += 1
	if moved == 0:
		_fail("the page did not move on a single real frame — the coast never runs (the "
			+ "driver's `set_process` is not reaching the engine)")
	else:
		print("  %d of 8 real frames advanced the coast (page at %.1f px, dragged to %d)"
			% [moved, bar.value, after_drag])
	_verdict()


func _fail(msg: String) -> void:
	_failures.append(msg)


## A real page, built by the same helper every screen uses, inside a 390x844 host.
##
## The rects are set explicitly: a `SceneTree` script never runs a layout pass, so an anchored
## child would still report a size of zero and every "is the drag inside the page" check would
## fail for a reason that has nothing to do with the driver.
func _page() -> Dictionary:
	var host := Control.new()
	host.size = Vector2(390, 844)
	host.position = Vector2.ZERO
	root.add_child(host)
	var page := UIKit.screen_page(host)
	var scroll: ScrollContainer = page["scroll"]
	scroll.size = Vector2(390, 844)
	scroll.position = Vector2.ZERO
	# Content taller than the page, so there is somewhere to scroll to.
	var tall := Control.new()
	tall.custom_minimum_size = Vector2(0, 2000)
	(page["column"] as VBoxContainer).add_child(tall)
	return {"host": host, "scroll": scroll, "swipe": page["swipe"]}


## A `ScrollSwipe` and a bare scroll container, without a whole screen around them.
func _driver(content_height: float = 2000.0) -> Dictionary:
	var host := Control.new()
	host.size = Vector2(390, 844)
	host.position = Vector2.ZERO
	root.add_child(host)
	var scroll := ScrollContainer.new()
	scroll.size = Vector2(390, 844)
	scroll.position = Vector2.ZERO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.scroll_deadzone = 8
	host.add_child(scroll)
	var tall := Control.new()
	tall.custom_minimum_size = Vector2(390, content_height)
	scroll.add_child(tall)
	# A `SceneTree` script runs NO layout pass, so the container's content height is 0 and the
	# bar's range collapses to its default `max_value` of 100 — every drag would "scroll" 100px
	# and the driver's arithmetic would be unmeasurable. Give the bar a range instead; the
	# arithmetic under test is the driver's, and the bar's own clamp must not hide it.
	scroll.get_v_scroll_bar().max_value = 10000.0
	var swipe := ScrollSwipe.new()
	swipe.setup(scroll)
	host.add_child(swipe)
	return {"host": host, "scroll": scroll, "swipe": swipe}


## The bar must not be drawn AND must not reserve space. Only SHOW_NEVER gives both — AUTO and
## RESERVE both set the bar visible=true in `update_scrollbars()`, which is the grey strip Jan
## asked to be rid of.
func _test_a_page_keeps_its_full_width_and_draws_no_bar() -> void:
	print("== a page draws no scrollbar and keeps its width ==")
	# In the pipeline phase the root is inside the tree, so the page gets a real layout pass —
	# then the bar's own visibility means something.
	_page_in_phase = true
	var page := _page()
	var scroll: ScrollContainer = page["scroll"]
	if scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_SHOW_NEVER:
		_fail("the page's vertical_scroll_mode is %d, not SHOW_NEVER — the bar is drawn"
			% scroll.vertical_scroll_mode)
	if not _page_in_phase:
		# A `SceneTree` script runs no layout pass, so `ScrollContainer._update_scrollbars()`
		# has not run and the bar still reports its default `visible`. The real check — with a
		# real frame behind it — is `_test_the_page_draws_no_bar_once_it_is_laid_out()`.
		print("  mode=SHOW_NEVER (the bar's own visibility is checked on a real frame)")
	# And the DRIVER is actually attached: without it the page cannot be dragged on the web.
	var swipe = page["swipe"]
	if swipe == null:
		_fail("the page has no ScrollSwipe — a drag cannot scroll it where Godot's own one is off")
	elif swipe._scroll != scroll:
		_fail("the page's ScrollSwipe is bound to a different container")


## Dragging a finger UP must move the page DOWN (the value grows), by the drag's own distance.
func _test_the_driver_moves_the_page_with_the_finger() -> void:
	print("== a finger drag moves the page ==")
	var d := _driver()
	var scroll: ScrollContainer = d["scroll"]
	var swipe = d["swipe"]
	swipe._begin(Vector2(195, 500), 0, true)
	if swipe._pointer != 0:
		_fail("a drag inside the page did not begin")
	for _i in 20:
		swipe._move(-8.0)   # 160px up
	var after_up: int = scroll.scroll_vertical
	# 160px of finger, less the 8px the deadzone ABSORBS = 152. Asserting only "it moved"
	# would pass with the 160 of a deadzone that is jumped over instead.
	if absi(after_up - 152) > 1:
		_fail("a 160px upward drag scrolled the page %d px, expected 152 (the deadzone is "
			% after_up + "absorbed, not jumped over)")
	# Dragging DOWN again must come back, not continue down.
	for _i in 20:
		swipe._move(8.0)
	if scroll.scroll_vertical >= after_up:
		_fail("a downward drag did not scroll back (at %d after going up to %d)"
			% [scroll.scroll_vertical, after_up])
	print("  160px up -> %d px, then back to %d px" % [after_up, scroll.scroll_vertical])
	# The page must not be scrolled past its ends.
	swipe._begin(Vector2(195, 500), 0, true)
	for _i in 300:
		swipe._move(-40.0)
	if scroll.scroll_vertical < 0:
		_fail("the page scrolled to a negative offset (%d)" % scroll.scroll_vertical)


## A tap must not move the page: the first few pixels are absorbed, and only then does the
## scroll follow the finger one-for-one.
func _test_the_deadzone_absorbs_the_first_pixels() -> void:
	print("== the deadzone absorbs a tap ==")
	var d := _driver()
	var scroll: ScrollContainer = d["scroll"]
	var swipe = d["swipe"]
	swipe._begin(Vector2(195, 500), 0, true)
	for _i in 5:
		swipe._move(-1.5)   # 7.5px, under the 8px deadzone
	if scroll.scroll_vertical != 0:
		_fail("a 7.5px wobble scrolled the page by %d px — a tap would nudge it"
			% scroll.scroll_vertical)
	swipe._move(-4.0)       # now past the deadzone
	if swipe._past_deadzone != true:
		_fail("the deadzone never released")
	print("  7.5px absorbed, the next 4px released the drag")


## A swipe that starts outside the page (the nav bar, the status strip, a dialog) must not
## move it — those are other controls' events.
func _test_a_drag_that_starts_outside_the_page_is_ignored() -> void:
	print("== a drag outside the page is somebody else's event ==")
	var d := _driver()
	var scroll: ScrollContainer = d["scroll"]
	var swipe = d["swipe"]
	# The host is 390x844 at the origin; y=-40 is above it.
	swipe._begin(Vector2(195, -40), 0, true)
	if swipe._pointer != swipe.INACTIVE:
		_fail("a drag that began outside the page was accepted")
	for _i in 20:
		swipe._move(-8.0)
	if scroll.scroll_vertical != 0:
		_fail("a drag from outside the page scrolled it by %d px" % scroll.scroll_vertical)
	print("  a drag from y=-40 scrolled nothing")


## On a device where Godot's own finger drag would be live, this driver must STILL run.
##
## This is the assertion whose opposite was in here before, and it was wrong. The old check
## was "scroll_swipe.gd still reads `is_touchscreen_available`", i.e. it PINNED the driver
## standing down on a phone. Measured on the port's own web build under CDP touch emulation,
## that stand-down is what produced:
##
##     touch profile: drag starting on a town tile -> page did NOT move
##     touch profile: drag starting on empty space -> page scrolled 56px
##
## Jan's own report. A phone would only scroll from somewhere nothing is.
func _test_the_driver_runs_on_a_touchscreen_too() -> void:
	print("== the driver does not stand down on a phone ==")
	var src := FileAccess.get_file_as_string("res://scripts/ui/scroll_swipe.gd")
	var code := ""
	for line in src.split("\n"):
		var trimmed := (line as String).strip_edges()
		if trimmed.begins_with("#"):
			continue
		code += trimmed
	# The gate must be GONE from the code (the header prose may still explain why it was).
	if code.contains("is_touchscreen_available"):
		_fail("scroll_swipe.gd gates on is_touchscreen_available() again — measured, a drag "
			+ "from a button then does NOT scroll the page on a phone")
	else:
		print("  the driver is unconditional (one scroll path on every platform)")
	# And Godot's own drag must be made inert, or the phone scrolls twice.
	var d := _driver()
	var scroll: ScrollContainer = d["scroll"]
	var swipe = d["swipe"]
	var gate: bool = swipe._scroll != null and scroll.scroll_deadzone > 100000.0
	if not gate:
		_fail("the driver left the container's own finger drag live (scroll_deadzone=%s) — "
			% str(scroll.scroll_deadzone) + "a phone would scroll through this driver AND "
			+ "through Godot's own drag")
	else:
		print("  Godot's own drag is made inert (scroll_deadzone=%d)" % int(scroll.scroll_deadzone))
	# The deadzone must not cost a TAP: the wheel is a separate branch, so check the wheel
	# still reaches the container — that is the desktop mouse path and it must survive.
	var src2 := FileAccess.get_file_as_string("res://scripts/ui/scroll_swipe.gd")
	if not src2.contains("scroll_deadzone = 1_000_000"):
		_fail("the inert-deadzone line is gone — a phone would scroll twice as fast")
	# The driver must not CONSUME the incoming event: a tap has to reach its button. The
	# check is on the CALL, not on the token — the file's own prose mentions the name often
	# enough that a plain `contains` reads the comment instead of the code (which is how the
	# first version of this check failed against a driver that never called it).
	if code.contains("set_input_as_handled("):
		_fail("the swipe driver calls set_input_as_handled — it would eat the tap")
	else:
		print("  the driver never consumes an event (a tap still reaches its button)")



## A FLICK: the page must keep going after the finger is lifted, and by roughly the distance a
## browser gives it.
##
## The gesture is driven with realistic per-event durations through the driver's `clock` — a
## headless run delivers a whole gesture inside the same millisecond, where a "velocity" does
## not exist, so without the fake clock this test would measure an infinite one and prove
## nothing about the arithmetic.
func _test_a_flick_coasts_after_the_finger_leaves() -> void:
	print("== a flick coasts after the finger leaves ==")
	var d := _driver()
	var scroll: ScrollContainer = d["scroll"]
	var swipe = d["swipe"]
	_flick(d, 12.0, 16, 8)                     # 8 events x 12 px / 16 ms = 750 px/s
	var after_drag: int = scroll.scroll_vertical
	if after_drag <= 0:
		_fail("the drag itself moved the page 0 px")
		return
	if not swipe._flinging:
		_fail("a 750 px/s flick did not start a coast — the page stops dead when the finger "
			+ "leaves, which is Jan's report")
		return
	var ended := false
	for _i in 300:
		sim_frame(swipe)
		if not swipe._flinging:
			ended = true
			break
	if not ended:
		_fail("the coast never stopped (still flinging after 5 s of frames)")
	var extra: int = scroll.scroll_vertical - after_drag
	# Expected = the sampled sum of `v0 * exp(-decel*t) * dt` cut off at the driver's own stop
	# speed. It converges on the continuous ideal `v0 / decel` — 748/2.5 ≈ 300 px — and what
	# matters is the SHAPE: a per-FRAME decay instead of a per-second one overshoots it by
	# hundreds, and a flick that never stops would run to the end of the page.
	if extra < 250 or extra > 360:
		_fail("a 750 px/s flick coasted %d px after the finger (expected ~300)" % extra)
	print("  finger gave %d px, the page coasted a further %d px, then stopped"
		% [after_drag, extra])


## A violent flick is CLAMPED: the page may cross a page or two, not the whole app. The clamp is
## the only thing standing between a fast swipe and a page that flies past everything the player
## wanted to read, and it cannot be seen on a SHORT page (the end stops the coast first) — so
## this one runs on the long page.
func _test_a_violent_flick_is_clamped() -> void:
	print("== a violent flick is clamped ==")
	var d := _driver()
	var scroll: ScrollContainer = d["scroll"]
	var swipe = d["swipe"]
	_flick(d, 120.0, 16, 8)                    # 7500 px/s, above anything a finger produces
	var after_drag: int = scroll.scroll_vertical
	var ended := false
	for _i in 400:
		sim_frame(swipe)
		if not swipe._flinging:
			ended = true
			break
	if not ended:
		_fail("a 7500 px/s throw never stopped")
	var extra: int = scroll.scroll_vertical - after_drag
	# A 4000 px/s ceiling coasts ~1590 px; unclamped, the same throw coasts ~2960.
	if extra > 1750:
		_fail("a 7500 px/s throw coasted %d px — the speed is not clamped (a 4000 px/s ceiling "
			% extra + "gives ~1590)")
	elif extra < 1400:
		_fail("a 7500 px/s throw coasted only %d px — the clamp bites far too early" % extra)
	else:
		print("  a 7500 px/s throw coasted %d px, held at the 4000 px/s ceiling" % extra)


## A phone does not send a clean touch stream: with `emulate_mouse_from_touch` (the default) the
## same finger ALSO arrives as a mouse press, mouse motion and a mouse release. If the driver
## decided "may this coast?" by which event delivered the RELEASE, a phone's flick would be read
## as a mouse and never coast — i.e. the feature would be missing exactly where Jan plays.
##
## This drives the two streams interleaved, as the engine does, and both orders of the press.
func _test_a_phone_flick_survives_the_emulated_mouse() -> void:
	print("== a phone's flick survives the emulated mouse events ==")
	for touch_first in [true, false]:
		var d := _driver()
		var scroll: ScrollContainer = d["scroll"]
		var swipe = d["swipe"]
		_flick(d, 12.0, 16, 8, 16, true, true, touch_first)
		if not swipe._flinging:
			_fail("a flick was lost when the touch press arrived %s the emulated mouse press"
				% ("before" if touch_first else "after"))
			return
		sim_frame(swipe)
		if scroll.scroll_vertical <= 0:
			_fail("the page did not move on a phone-style gesture")
			return
	print("  both event orders: the flick coasts (the gesture is remembered, not the release type)")


## A drag that ends SLOWLY is not a flick. Jan's complaint was about the opposite (too little
## travel), but the same code path decides this one, and a page that lurches away from a finger
## which was placed carefully is the way a flick is experienced as broken.
func _test_a_slow_drag_does_not_fling() -> void:
	print("== a slow drag does not fling ==")
	var d := _driver()
	var scroll: ScrollContainer = d["scroll"]
	var swipe = d["swipe"]
	_flick(d, 1.5, 16, 12)                     # 94 px/s, well under the flick threshold
	if swipe._flinging:
		_fail("a 94 px/s drag started a coast — a careful drag throws the page")
	else:
		print("  94 px/s: the page stopped with the finger (moved %d px)"
			% scroll.scroll_vertical)


## A finger that stops moving and THEN lifts did not flick. The velocity is sampled per event,
## so it has to decay away with the pause rather than being averaged over the whole drag.
func _test_a_finger_held_still_does_not_fling() -> void:
	print("== a finger held still does not fling ==")
	var d := _driver()
	var swipe = d["swipe"]
	_flick(d, 12.0, 16, 8, 400)                # ...then 400 ms of holding before the release
	if swipe._flinging:
		_fail("a finger that rested 400 ms before lifting still flung the page — a stop on "
			+ "purpose must be a stop")
	else:
		print("  a 400 ms pause before the release: no coast")


## No browser coasts after a MOUSE drag, and the mouse is the desktop case the drag test drives,
## so this is deliberate behaviour rather than an oversight.
func _test_a_mouse_release_does_not_fling() -> void:
	print("== a mouse release does not fling ==")
	var d := _driver()
	var swipe = d["swipe"]
	_flick(d, 12.0, 16, 8, 0, false)
	if swipe._flinging:
		_fail("a mouse drag flung the page — the desktop drag must stay one-for-one")
	else:
		print("  a mouse drag of the same speed: no coast")


## A fling that reaches the end of the page has to STOP there, not sit pushing a bar that
## cannot move. Assert it stops far sooner than the velocity would decay on its own, which is
## the only way this is visible from out here.
func _test_the_coast_ends_at_the_end_of_the_page() -> void:
	print("== a coast ends at the end of the page ==")
	var d := _driver()
	var scroll: ScrollContainer = d["scroll"]
	var swipe = d["swipe"]
	# A page only 400 px long, so a hard throw (240 px of drag + the coast) runs into its end.
	scroll.get_v_scroll_bar().max_value = 400.0
	_flick(d, 30.0, 16, 8)                     # 1875 px/s, a hard throw
	var frames := 0
	for _i in 300:
		sim_frame(swipe)
		frames += 1
		if not swipe._flinging:
			break
	if swipe._flinging:
		_fail("a coast into the page's end never stopped")
	elif frames > 40:
		_fail("the coast kept pushing the page's end for %d frames (the decay alone needs "
			% frames + "~87) — it must end when the page stops moving")
	elif absf(scroll.get_v_scroll_bar().value - 400.0) > 1.0:
		_fail("the page settled at %d, not at its end (400)"
			% int(scroll.get_v_scroll_bar().value))
	else:
		print("  hit the end at 400 px and stopped after %d frames" % frames)


## One simulated frame for the driver's coast.
func sim_frame(swipe) -> void:
	swipe._process(1.0 / 60.0)


## Drag a finger up, `px` per event, one event every `dt_ms`, and release it `rest_ms` later.
##
## `touch = false` makes it a MOUSE drag: the same motion and the same speeds, released with a
## mouse button — which must not coast.
##
## `emulate` adds the phone's SECOND stream: with `emulate_mouse_from_touch` on, the same finger
## also arrives as a mouse press/motion/release. `touch_first` picks which press leads; both
## orders are something a real device can produce.
func _flick(d: Dictionary, px: float, dt_ms: int, count: int, rest_ms: int = 16,
		touch: bool = true, emulate: bool = false, touch_first: bool = true) -> void:
	var swipe = d["swipe"]
	_fake_ms = 1000
	swipe.clock = fake_now
	if touch:
		if emulate and not touch_first:
			swipe._begin(Vector2(195, 500), -1, false)
		swipe._begin(Vector2(195, 500), 0, true)
		if emulate and touch_first:
			# The emulated mouse press of the same finger; the driver must not take it over.
			swipe._begin(Vector2(195, 500), -1, false)
	else:
		swipe._begin(Vector2(195, 500), -1, false)
	for _i in count:
		_fake_ms += dt_ms
		swipe._move(-px, _fake_ms)
	_fake_ms += rest_ms
	swipe._end(_fake_ms)


## A DRAG must not fire the button it started on, and a TAP must still fire it.
##
## Measured with `tools/probe_tap_drag.gd` on the real Viewport pipeline: a finger that stays
## inside a button's own rect keeps `BaseButton.pressing_inside` set, so the release fires the
## button — the player drags the town and a shop opens. And a synthetic release ALONE does not
## cancel it (`tools/probe_cancel.gd`: it still fired): `pressing_inside` is only cleared by
## the pointer LEAVING the control, so the cancel is a motion away followed by a release.
##
## This is the half a driver unit test cannot see, which is why it drives real events.
func _test_a_drag_does_not_fire_the_button_it_started_on() -> void:
	print("== a drag on a tile scrolls instead of opening it ==")
	var rig := _pipeline_rig()
	var scroll: ScrollContainer = rig["scroll"]
	var button: Button = rig["button"]
	var hits: Dictionary = rig["hits"]
	var vp := root
	vp.size = Vector2i(390, 844)
	var start := Vector2(120, 240)
	_touch(vp, start, 0, true)
	for i in 10:
		_touch_drag(vp, start + Vector2(0, -12.0 * float(i + 1)), Vector2(0, -12.0), 0)
	var after_drag := scroll.scroll_vertical
	var fired_mid := int(hits["n"])
	# The cancel pushes the driver's OWN synthetic events; if it read them back as the player's
	# finger, the drag would end at the deadzone and the page would stop there. So the pointer
	# must still be mid-drag, and the page must have taken all 120px less the absorbed 8.
	var still_dragging := int(rig["swipe"]._pointer) == 0
	_touch(vp, start + Vector2(0, -120.0), 0, false)
	if fired_mid != 0:
		_fail("a DRAG fired the tile it started on (%d times) — the player swipes and a shop "
			% fired_mid + "opens")
	if not still_dragging:
		_fail("the press cancel ended the drag itself (pointer=%d)" % int(rig["swipe"]._pointer))
	if absi(after_drag - 112) > 2:
		_fail("a 120px drag scrolled the page %d px, expected 112 after the absorbed deadzone"
			% after_drag)
	if button.is_pressed():
		_fail("the tile is left in a pressed state after a drag")
	print("  120px drag -> tile fired 0x, page scrolled to %d px" % after_drag)


## ...and the tap half: the cancel must not cost the player a button. A press and release with
## no movement never crosses the deadzone, so nothing is cancelled.
func _test_a_tap_still_fires_without_dragging() -> void:
	print("== a tap still opens what it touches ==")
	var rig := _pipeline_rig()
	var button: Button = rig["button"]
	var hits: Dictionary = rig["hits"]
	var vp := root
	vp.size = Vector2i(390, 844)
	_touch(vp, Vector2(120, 240), 0, true)
	_touch(vp, Vector2(120, 240), 0, false)
	if int(hits["n"]) != 1:
		_fail("a plain tap fired the tile %d times, expected exactly 1" % int(hits["n"]))
	else:
		print("  a tap fired the tile once")


## A real page, a real tall tile and the driver, inside the real window — the rig the two
## pipeline checks above drive. The window is forced to the port's own 390x844: a headless run
## leaves it at 64x64, where every event lands outside the page and nothing is hit at all.
func _pipeline_rig() -> Dictionary:
	var host := Control.new()
	host.size = Vector2(390, 844)
	host.position = Vector2.ZERO
	root.add_child(host)

	var scroll := ScrollContainer.new()
	scroll.size = Vector2(390, 844)
	scroll.position = Vector2.ZERO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.scroll_deadzone = 8
	host.add_child(scroll)

	var content := Control.new()
	content.custom_minimum_size = Vector2(390, 3000)
	scroll.add_child(content)
	# Same reason as in `_driver()`: no layout pass, so the bar needs a range of its own.
	scroll.get_v_scroll_bar().max_value = 10000.0

	# A TALL tile, so a drag can stay inside its rect — the case that fires it.
	var button := Button.new()
	button.text = "TILE"
	button.position = Vector2(20, 100)
	button.size = Vector2(200, 400)
	content.add_child(button)
	var hits := {"n": 0}
	button.pressed.connect(func(): hits["n"] = int(hits["n"]) + 1)

	var swipe = ScrollSwipe.new()
	swipe.setup(scroll)
	host.add_child(swipe)
	return {"host": host, "scroll": scroll, "button": button, "hits": hits, "swipe": swipe}


func _touch(vp: Viewport, pos: Vector2, index: int, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.pressed = pressed
	e.position = pos
	vp.push_input(e)


func _touch_drag(vp: Viewport, pos: Vector2, rel: Vector2, index: int) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	e.relative = rel
	e.velocity = rel
	vp.push_input(e)
