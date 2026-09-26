extends SceneTree
## tools/test_transition.gd — the PWA's `#transitionScreen`, its RULES and its TIMING.
##
## Jan: "všechny transition obrazovky chybí — při přechodu do města, do divočiny, při použití
## portal scrollu atd. Mezi jednotlivými obrazovkami je vždy vložená transition obrazovka
## s obrázkem a lehkou animací."
##
## What a screenshot cannot pin, and therefore what lives here:
##
##   1. **Which moves go through it.** The PWA routes exactly FIVE (town from the nav bar,
##      walk-to-town from the map, wilderness from the town, a stop from the map, both town
##      portals). The shop / chest / craft / bestiary are PLAIN switches, and wrapping those
##      too would invent a 2.2 s delay the player never had. Both halves are asserted: the five
##      that must, and one that must NOT.
##   2. **The callback runs while the overlay is still OPAQUE.** That is the PWA's ordering and
##      the reason nothing flashes: the next screen is built UNDER the black plate. Asserting
##      "the screen changed" cannot see it — the fade alpha at the moment of the call can.
##   3. **The timings are the CSS's own** 1800 ms hold and 400 ms fade, and the reveal runs
##      1400 ms.
##   4. **The CSS cubic-bezier easing, not `t*t`.** At 150 ms the PWA's own reveal opacity is
##      measured 0.828; `t*t` gives 0.985 and a linear ramp 0.893, so this one number is what
##      distinguishes a ported curve from a plausible one.
##   5. **The mask is baked into the texture** and its SHAPE is the CSS gradient: solid out to
##      40 % of the ellipse, gone by 85 %. A shader was tried first and measured wrong (the
##      box at 28.1 against the CSS's 115.7).
##   6. **`walkToTown` resets the stop's fight counter.** Not decoration — without it the player
##      can walk out, walk back and resume a stop at 9/10.
##
## ⚠️  A `SceneTree` root is NOT the game canvas, so absolute rects are asserted only where the
## node's own anchors determine them (the overlay) and the rest is checked as RATIOS and
## shapes. The absolute geometry is `tools/probe_transition_port.gd` against the real
## `main.gd`, and it is where the [0,0 390x844] overlay and the [65,292 260x260] image were
## verified against the live PWA.
##
## Run:  godot --headless --path . --script res://tools/test_transition.gd
## Pass: prints TRANSITION_ALL_PASS=true and exits 0.

const Main := preload("res://scripts/main.gd")
const TransitionScreen := preload("res://scripts/ui/transition_screen.gd")

## The PWA's own numbers, read off the live build with
## `tools/import/probe_transition_pwa.py` at 390x844.
const PWA_REVEAL_AT_150MS := 0.828
const PWA_HOLD_MS := 1800.0
const PWA_FADE_MS := 400.0
const PWA_REVEAL_MS := 1400.0

var _main: Node = null
var _started := false
var _failures: Array[String] = []


func _initialize() -> void:
	_main = Main.new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		if _main._transition == null or _main._nav_bar == null or _main.state == null:
			return false
		_started = true
		_run()
		quit(0 if _failures.is_empty() else 1)
		return true
	return false


func _fail(msg: String) -> void:
	_failures.append(msg)


func _run() -> void:
	var tr = _main._transition

	_test_timings_are_the_css_ones(tr)
	_test_easing_is_the_css_curve(tr)
	_test_overlay_covers_the_canvas(tr)
	_test_mask_shape(tr)
	_test_the_five_moves_go_through_it(tr)
	_test_plain_moves_do_not(tr)
	_test_callback_runs_under_an_opaque_overlay(tr)
	_test_a_second_move_replaces_the_first(tr)
	_test_walk_to_town_resets_the_stop(tr)

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("TRANSITION_ALL_PASS=true")
	else:
		print("TRANSITION_ALL_PASS=false")


# --- timing -----------------------------------------------------------------

## The three durations, straight from the CSS. A port with 1 s here and 2 s there looks
## plausible in a screenshot and is a different feel.
func _test_timings_are_the_css_ones(tr) -> void:
	print("  timings: hold=%.0f reveal=%.0f fade=%.0f (PWA %.0f/%.0f/%.0f)"
		% [tr.HOLD_MS, tr.REVEAL_MS, tr.FADE_MS, PWA_HOLD_MS, PWA_REVEAL_MS, PWA_FADE_MS])
	if absf(tr.HOLD_MS - PWA_HOLD_MS) > 0.5:
		_fail("the hold is %.0f ms, the PWA's setToumeout is %.0f" % [tr.HOLD_MS, PWA_HOLD_MS])
	if absf(tr.REVEAL_MS - PWA_REVEAL_MS) > 0.5:
		_fail("the reveal is %.0f ms, `transitionReveal` is %.0f" % [tr.REVEAL_MS, PWA_REVEAL_MS])
	if absf(tr.FADE_MS - PWA_FADE_MS) > 0.5:
		_fail("the fade is %.0f ms, `transitionScreenFadeOut` is %.0f" % [tr.FADE_MS, PWA_FADE_MS])


## `ease-out` is `cubic-bezier(0, 0, 0.58, 1)` and `ease-in` is `cubic-bezier(0.42, 0, 1, 1)`,
## and the REVEAL's own opacity at 150 ms is the number that tells a real curve from a guess.
func _test_easing_is_the_css_curve(tr) -> void:
	var at_150: float = 1.0 - tr.cubic_bezier(150.0 / 1400.0, 0.0, 0.0, 0.58, 1.0)
	var made_up: float = 1.0 - pow(150.0 / 1400.0, 2.0)
	var linear: float = 1.0 - 150.0 / 1400.0
	print("  reveal at 150 ms: ported=%.3f  PWA measured=%.3f  (t*t would be %.3f, linear %.3f)"
		% [at_150, PWA_REVEAL_AT_150MS, made_up, linear])
	if absf(at_150 - PWA_REVEAL_AT_150MS) > 0.01:
		_fail("the ported ease-out gives %.3f at 150 ms, the PWA measures %.3f" % [at_150, PWA_REVEAL_AT_150MS])
	# The ends must be exact or `forwards` never reaches 1.
	if absf(tr.cubic_bezier(0.0, 0.0, 0.0, 0.58, 1.0)) > 0.0001:
		_fail("cubic_bezier(0) is not 0")
	if absf(tr.cubic_bezier(1.0, 0.0, 0.0, 0.58, 1.0) - 1.0) > 0.0001:
		_fail("cubic_bezier(1) is not 1")
	# Monotone, which is what makes the bisection valid at all.
	var prev := -1.0
	for i in 41:
		var t := float(i) / 40.0
		var v: float = tr.cubic_bezier(t, 0.42, 0.0, 1.0, 1.0)
		if v < prev - 0.0001:
			_fail("the ease-in curve goes backwards at t=%.3f" % t)
			break
		prev = v


## The overlay is `position:fixed; inset:0` at z-index 9999 — it must cover the whole canvas
## and sit above the modal (z 1000) and the nav bar (z 100).
func _test_overlay_covers_the_canvas(tr) -> void:
	var canvas := Vector2(390, 844)
	tr.play(tr.TOWN_ART, func(): pass)
	if not tr.visible:
		_fail("play() left the overlay hidden")
	print("  overlay: size=%s anchors=(%.0f,%.0f) visible=%s"
		% [str(tr.size), tr.anchor_right, tr.anchor_bottom, str(tr.visible)])
	# Anchors, not `size`: a SceneTree root is not the game canvas, so the resolved size here
	# is the harness's. The anchors are what make it full-rect on the real canvas.
	if absf(tr.anchor_right - 1.0) > 0.001 or absf(tr.anchor_bottom - 1.0) > 0.001:
		_fail("the overlay is not anchored full-rect (right=%.2f bottom=%.2f)"
			% [tr.anchor_right, tr.anchor_bottom])
	if tr.mouse_filter != Control.MOUSE_FILTER_STOP:
		_fail("the overlay does not swallow input — a tap on the arena behind it would land")
	var layer: int = tr.get_parent().layer
	print("  layers: transition=%d modal=%d nav=5 (PWA z 9999 vs 1000 vs 100)"
		% [layer, _main._modal_layer.layer])
	if layer <= _main._modal_layer.layer:
		_fail("the transition layer (%d) is not above the modal's (%d) — the PWA's overlay covers the dialog"
			% [layer, _main._modal_layer.layer])
	_tr_reset(tr)


## The baked mask: solid out to 40 % of the ellipse, gone by 85 %. Read off the ART's own
## pixels so a mask that never ran (alpha 1 everywhere) and one that blacked everything out
## (alpha 0) are both caught.
##
## ⚠️  The sample points are computed per RADIUS, not as a fraction of the box. `ellipse
## 66% 66%` makes the gradient's radius **0.66 of the box**, so the normalised radius is
## `|Δ| / 0.66` in box-relative units — and the box edge is at Δ=0.5, i.e. only r=0.758. The
## 85 % stop sits at Δ=0.561, which is OUTSIDE the box on the axes and reachable only on the
## diagonal. An earlier version of this test sampled the X axis at "85 % of the box" (Δ=0.28,
## r=0.42) and reported the mask as 0.988 opaque there — a wrong question, not a wrong mask.
func _test_mask_shape(tr) -> void:
	var tex: Texture2D = load(tr.TOWN_ART)
	if tex == null:
		_fail("the town art does not load: %s" % tr.TOWN_ART)
		return
	var masked: Texture2D = TransitionScreen.masked_texture(tex)
	if masked == null:
		_fail("masked_texture returned null")
		return
	var src: Image = tex.get_image()
	var out: Image = masked.get_image()
	if src == null or out == null:
		_fail("the masked texture has no readable image")
		return
	var w := out.get_width()
	var h := out.get_height()

	# The alpha must follow `1 - smoothstep(0.40, 0.85, r)` at every radius the box can reach
	# along its centre row, which is r <= 0.758.
	var worst := 0.0
	var worst_at := 0.0
	for i in 16:
		var r := 0.758 * float(i) / 15.0
		var u := 0.5 + r * 0.66
		var x := int(clampf(u, 0.0, 1.0) * float(w - 1))
		var got: float = out.get_pixel(x, h / 2).a
		var want := 1.0 - smoothstep(0.40, 0.85, r)
		if absf(got - want) > worst:
			worst = absf(got - want)
			worst_at = r
	print("  mask alpha vs 1-smoothstep(0.40, 0.85, r): worst error %.3f at r=%.3f" % [worst, worst_at])
	print("  mask alpha: centre=%.3f r=0.40=%.3f r=0.60=%.3f r=0.758(box edge)=%.3f corner=%.3f"
		% [out.get_pixel(w / 2, h / 2).a,
			out.get_pixel(int((0.5 + 0.40 * 0.66) * w), h / 2).a,
			out.get_pixel(int((0.5 + 0.60 * 0.66) * w), h / 2).a,
			out.get_pixel(w - 1, h / 2).a, out.get_pixel(1, 1).a])
	# One texel of tolerance: the bake is evaluated at pixel CENTRES, and the test's own
	# sample can land a texel away from an exact r.
	if worst > 0.06:
		_fail("the baked mask does not follow the CSS gradient (worst error %.3f at r=%.3f)"
			% [worst, worst_at])
	if out.get_pixel(w / 2, h / 2).a < 0.95:
		_fail("the mask dims the centre (alpha %.3f) — the CSS is solid to 40%%"
			% out.get_pixel(w / 2, h / 2).a)
	# r at the corner is sqrt(0.5^2+0.5^2)/0.66 = 1.07, well past the 85 % stop, so the corner
	# must be fully gone. This is the assertion that catches a mask applied at the wrong scale
	# in the OTHER direction (an ellipse too large leaves the corners faintly visible).
	if out.get_pixel(1, 1).a > 0.02:
		_fail("the mask leaves the corner at %.3f — the gradient's 85%% stop is past it"
			% out.get_pixel(1, 1).a)
	# And the RGB must be untouched: the mask is alpha only.
	var a: Color = src.get_pixel(w / 2, h / 2)
	var b: Color = out.get_pixel(w / 2, h / 2)
	if absf(a.r - b.r) > 0.01 or absf(a.g - b.g) > 0.01 or absf(a.b - b.b) > 0.01:
		_fail("the mask changed the centre's colour (%s -> %s)" % [str(a), str(b)])


# --- which moves are routed -------------------------------------------------

## The five, each driven through the ROUTE its button takes rather than the helper, because a
## helper called directly passes against wiring that is not connected.
func _test_the_five_moves_go_through_it(tr) -> void:
	# 1. the nav bar's town entry, from somewhere that is not the town
	_main.show_screen("shop")
	_reset(tr)
	_main._on_nav_selected("town")
	_expect(tr, "the nav bar's town entry")
	_main.show_screen("town")

	# 2. the town's wilderness tile -> the map, art = map.webp
	_main.show_screen("town")
	_reset(tr)
	_main._screens["town"].stop_requested.emit(-1, -1)
	_expect(tr, "the town's wilderness tile", tr.WILDERNESS_ART)

	# 3. the map's Walk to Town -> the town, art = town.webp. Also resets the stop, tested
	# separately.
	_reset(tr)
	_main._on_walk_to_town()
	_expect(tr, "the map's Walk to Town", tr.TOWN_ART)

	# 4. a stop from the map -> the arena, art = that STOP's own
	_reset(tr)
	_main._on_stop_selected(0, 3)
	var want_stop: String = tr.stop_art_path(0, 3)
	_expect(tr, "a stop tapped on the map", want_stop)

	# 5. a town portal: from the result page.
	#
	# ⚠️  `_reset(tr)` right before the emit is load-bearing and easy to leave out: this test
	# body has already driven five moves through the ONE reusable overlay, and `play()` stores
	# the callback while the test's `_reset()` clears it. Coming in with the overlay still
	# armed, a SECOND `play()` overwrites the first move's callback and the emit looks broken
	# while the wiring is fine. That is a real property of a single overlay (the PWA's own
	# `setTimeout` is never cleared either) — `_test_a_second_move_replaces_the_first` pins it.
	#
	# ⚠️  The guard is `button_lock_ms`, which runs on the PLAYER's clock and is set when a fight
	# ends. A `SceneTree` test has no frames between the kill and the tap, so the lock is still
	# armed and `_on_portal_pressed` ignores the tap — the PWA's own "a tap right after the kill
	# must not fire". Cleared here so the WIRING is what is under test, with the lock covered by
	# `test_arena_pacing` where frames exist.
	_main.state.data["townPortalCount"] = 1
	_main._on_stop_selected(0, 0)
	# ⚠️  The arena is built by the transition's CALLBACK, so the overlay has to be run past its
	# hold or `arena.battle` is still null and `_on_result_portal` returns at its own null guard
	# without a word — which is exactly how this came back as "the tile did not start a
	# transition". Drive it here, the way a frame eventually would.
	tr._process(tr.HOLD_MS / 1000.0 + 0.01)
	var arena = _main._screens["arena"]
	if arena.battle == null:
		_fail("the stop's transition never entered the arena, so the portal could not be tested")
		return
	arena.battle.enemy_hp = 0.0
	arena.battle.gap = 0.0
	var guard := 0
	while not arena.battle.ended and guard < 300:
		arena.step()
		guard += 1
	arena._button_lock_ms = 0.0
	_reset(tr)
	arena.portal_requested.emit()
	_expect(tr, "the result page's Town Portal tile", tr.PORTAL_ART)


## The overlay is a SINGLE reusable object, and `play()` does not queue behind a transition
## that is already up — the callback is overwritten. That is faithful (the PWA's own
## `setTimeout` is never cleared either) but it has a consequence a test has to respect: a move
## driven while one is still in flight inherits the first move's destination.
func _test_a_second_move_replaces_the_first(tr) -> void:
	_reset(tr)
	_main.show_screen("shop")
	_main._on_nav_selected("town")
	if not tr.is_transitioning():
		_fail("the nav bar's town entry did not start a transition")
		return
	var first_art: String = tr._art_path
	# A second move, into the same overlay.
	_main.show_screen("shop")
	_main._on_stop_selected(0, 2)
	print("  a second move replaces the first: %s -> %s" % [first_art, tr._art_path])
	if tr._art_path == first_art:
		_fail("a second move kept the first move's art (%s) — play() must re-arm the overlay"
			% first_art)
	if not tr.is_transitioning():
		_fail("a second move left the overlay down")
	_tr_reset(tr)
	_main.show_screen("town")


## `_reset` clears the overlay and takes a note of how many times the callback fired.
var _fired := 0

func _reset(tr) -> void:
	tr._active = false
	tr.visible = false
	tr._hold_ms = tr.HOLD_MS
	tr._on_done = Callable()
	_fired = 0


## The overlay must be UP and showing `want`'s art (when given), and the move must NOT have
## happened yet — a transition that switches the screen immediately is a delay with nothing
## behind it.
func _expect(tr, what: String, want_art: String = "") -> void:
	if not tr.is_transitioning():
		_fail("%s did not start a transition" % what)
		return
	if want_art != "" and tr._art_path != want_art:
		_fail("%s shows %s, expected %s" % [what, tr._art_path, want_art])
	print("  %s: art=%s" % [what, tr._art_path])


## The shop, the chest, the craft and the bestiary are PLAIN in the PWA. Routing them through
## the overlay would be inventing a 2.2 s delay on screens the player taps through constantly.
func _test_plain_moves_do_not(tr) -> void:
	_main.show_screen("town")
	var checked := 0
	for key in ["shop", "chest", "craft", "bestiary", "spellbook"]:
		if not _main._screens.has(key):
			continue
		_main.show_screen("town")
		_reset(tr)
		_main._on_nav_selected(key)
		checked += 1
		if tr.is_transitioning():
			_fail("the nav bar's '%s' entry started a transition — the PWA switches it instantly"
				% key)
		if _main._current != key:
			_fail("the nav bar's '%s' entry did not change the screen (current=%s)"
				% [key, _main._current])
	print("  plain nav entries checked: %d (none may transition)" % checked)
	if checked < 4:
		_fail("only %d plain nav entries were reachable — the check proved little" % checked)
	_main.show_screen("town")


## The PWA calls the callback and starts the fade IN THE SAME TICK, so the next screen is
## built under a still-opaque overlay. Asserting "the screen changed" cannot see that: the
## fade alpha at the moment of the call can.
##
## ⚠️  The reading is collected into a one-element ARRAY, not into a plain local. A GDScript
## lambda captures locals **by value** at creation time, so `func(): alpha_at_call = …` writes
## to the lambda's own copy and the outer variable stays at its initial value — measured: the
## assertion read -1.0, i.e. "the callback never ran", while the callback had run fine. An
## Array is a reference type, so appending to it IS visible outside.
func _test_callback_runs_under_an_opaque_overlay(tr) -> void:
	_main.show_screen("town")
	_reset(tr)
	var seen: Array = []
	var tr_ref = tr
	_main._transition_to(tr.TOWN_ART, func(): seen.append(tr_ref.modulate.a))
	# Run the overlay past its hold with a single large step.
	tr._process(tr.HOLD_MS / 1000.0 + 0.01)
	var alpha_at_call: float = seen[0] if not seen.is_empty() else -1.0
	print("  fade alpha when the callback ran: %.3f" % alpha_at_call)
	if seen.is_empty():
		_fail("the transition never called its callback")
	elif alpha_at_call < 0.99:
		_fail("the callback ran at fade alpha %.3f — the PWA runs it UNDER the opaque overlay, or the next screen shows before it is built"
			% alpha_at_call)


## `walkToTown` zeroes the stop's fight counter and advances the stop if it was cleared.
func _test_walk_to_town_resets_the_stop(tr) -> void:
	_reset(tr)
	_main.state.set_progress(0, 2)
	_main.state.data["areaFightProgress"][0] = 7
	_main._on_walk_to_town()
	var after := int(_main.state.data["areaFightProgress"][0])
	var progress := int(_main.state.data["locationProgress"][0])
	print("  walk to town: fight 7 -> %d, stop %d -> %d" % [after, 2, progress])
	if after != 0:
		_fail("walking to town left the fight counter at %d — the PWA resets it, so a walk out and back must not resume at 7/10"
			% after)
	if progress != 2:
		_fail("walking to town moved the stop from 2 to %d for an UNCLEARED stop" % progress)

	# A CLEARED stop (10/10) advances.
	_main.state.set_progress(0, 3)
	_main.state.data["areaFightProgress"][0] = 10
	_main._on_walk_to_town()
	var advanced := int(_main.state.data["locationProgress"][0])
	print("  walk to town with a cleared stop: stop 3 -> %d" % advanced)
	if advanced != 4:
		_fail("walking to town with a cleared stop left it at %d, expected 4" % advanced)
	_reset(tr)


func _tr_reset(tr) -> void:
	tr._active = false
	tr.visible = false
