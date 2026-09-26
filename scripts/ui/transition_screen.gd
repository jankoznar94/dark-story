extends Control
class_name TransitionScreen
## TransitionScreen — the PWA's `#transitionScreen`, the overlay every move between screens
## goes through. The port had NONE of it: the town, the wilderness, a stop and both town
## portals all cut straight to the next screen, and Jan's report is exactly that
## ("všechny transition obrazovky chybí").
##
## Source: `public/style.css`'s `.transition-screen` block plus `showTransition()` in
## `src/game.ts`. Measured on the LIVE PWA (`tools/import/probe_transition_pwa.py`) at
## 390x844, all four types, every number below read off `getComputedStyle`:
##
##   .transition-screen    fixed, [0,0 390x844], `#000`, z-index 9999, flex centred
##   .transition-content   260x260 at [65,292] (centred: (390-260)/2 = 65), column, gap 20
##   .transition-image     260x260, `object-fit:contain`, radius 24, z-index 2,
##                         radial mask `ellipse 66% 66% at 50% 50%, #000 40%, transparent 85%`
##   .transition-content::after
##                         a BLACK plate inset 0, radius 12, z-index 3 — i.e. ON TOP of the
##                         image — animating `transitionReveal` **1.4s ease-out forwards**
##                         from opacity 1 to 0. Measured mid-flight: `opacity 0.83` at
##                         0.15 s and `0` at 1.5 s. That is the "lehká animace": the image is
##                         REVEALED from under a black plate; it does not fade in itself.
##   .transition-screen.fade-out
##                         `transitionScreenFadeOut` **0.4s ease-in**, 1 -> 0
##
## The PWA's timing (`showTransition`) is: show, hold **1800 ms**, then run the callback AND
## start the 0.4 s fade-out in the same tick. The callback runs UNDER the still-opaque
## overlay, so the next screen is fully built when the overlay uncovers it and nothing
## flashes. Both numbers are constants here and the callback fires at the same instant.
##
## FOUR types, each with its own image (the PWA also sets `--glow-low` / `--glow-high`):
##
##   town        assets/town.webp                     (glow gold)
##   wilderness  assets/map.webp                      (glow green)
##   portal      assets/items/town_portal_scroll.png  (glow blue)
##   stop        assets/stops/stop_actN_M.webp, else placeholder_actN.png  (act theme)
##
## ⚠️  **The two glow properties are DEAD in the PWA.** Grepped across `index.html`,
## `public/style.css` and `src/`: `--glow-low` and `--glow-high` appear exactly twice in the
## whole codebase, both times in the declaration that SETS them, and no rule ever reads them.
## So the port draws no glow — that would be inventing a visual the player never saw. (It
## also matches Jan's standing rule: no glow.)
##
## ⚠️  **There is no label.** `.transition-label` exists as a CSS rule, but the markup is
## `<div class="transition-content"><img …></div>` with no label element and `showTransition`
## never writes one. Measured: `labelPresent: false`, text `null`. Image only.
##
## ⚠️  The mask goes on a 260x260 `TextureRect`, NOT on the contain-fitted art: in CSS
## `mask-image` applies to the element's BOX, and the element is 260x260 whatever
## `object-fit` does inside it. `tools/import/probe_transition_pwa.py` reports the mask on
## the img's own 260x260 rect, so this is the measured behaviour, not a simplification.

const IMAGE_SIZE := 260.0
## `.transition-content` is centred by the flex parent: (390 - 260) / 2 = 65, measured.
const CONTENT_X := 65.0
const CONTENT_Y := 292.0
## `showTransition`'s `setTimeout(…, 1800)`.
const HOLD_MS := 1800.0
## `@keyframes transitionScreenFadeOut` — `.transition-screen.fade-out`, 0.4s ease-in.
const FADE_MS := 400.0
## `@keyframes transitionReveal` — `animation:transitionReveal 1.4s ease-out forwards`.
const REVEAL_MS := 1400.0

## The CSS timing functions, as the control points the browser interpolates. `ease-out` is
## `cubic-bezier(0, 0, 0.58, 1)` and `ease-in` is `cubic-bezier(0.42, 0, 1, 1)` — NOT `t*t`.
##
## ⚠️  Measured on the live PWA, the reveal plate's opacity is **0.828 at 0.15 s**; a linear
## ramp would give 0.893 and `t*t` gives 0.985, so a made-up curve is off by more than a tenth
## of the whole animation at the only instant a player's eye is on it. The real curve is
## solved below.
const EASE_OUT := [0.0, 0.0, 0.58, 1.0]
const EASE_IN := [0.42, 0.0, 1.0, 1.0]

const TOWN_ART := "res://assets/town.webp"
const WILDERNESS_ART := "res://assets/map.webp"
const PORTAL_ART := "res://assets/items/town_portal_scroll.png"

var _image: TextureRect
## `::after` — the plate that covers the image and fades away over 1.4 s.
var _reveal: ColorRect
var _hold_ms := 0.0
var _fade_ms := 0.0
## Elapsed time of the `transitionReveal` animation, kept separately from the plate's own
## alpha so the CSS easing can be solved from it (one subtraction per frame drifts).
var _reveal_ms := 0.0
## ⚠️  A clock that ALWAYS grows while the overlay is up. `_reveal_ms` stops at 1.4 s (the
## reveal is `forwards` and its alpha then holds at 0), so anything that samples the overlay
## later — a probe at 1.5 s and 1.85 s — was reading a frozen clock and concluding the fade
## never happened.
var _elapsed_ms := 0.0
## The move to make once the hold is over. Called while the overlay is still OPAQUE.
var _on_done: Callable = Callable()
var _active := false
var _art_path := ""


func _ready() -> void:
	# `set_anchors_preset` alone leaves the rect at 0x0 here: this Control's parent is a
	# `CanvasLayer`, nothing lays it out, and the offsets that the preset recomputes keep the
	# node's current (empty) rect. Measured: the overlay reported `S: (0.0, 0.0)` and the
	# screen behind it showed through everywhere outside the 260x260 image box — the black
	# plate over the image was the only opaque thing on screen. So the ANCHORS **and the
	# OFFSETS** have to be set; that is the pair that makes a full-rect child of a layer.
	# (The size itself needs no assignment — see below.)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# No explicit `size =`: with anchors 0 -> 1 an assignment is overridden by the anchor
	# system right after `_ready()` (Godot warns about exactly that), and the OFFSETS preset
	# above already resolved the rect to the parent's own 390x844. The offsets are relative
	# to the anchors, so the overlay tracks a later viewport change for free.
	# The overlay swallows everything under it, exactly as `z-index:9999` does — a tap on the
	# arena's buttons while the screen is still black must not start a fight.
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var bg := ColorRect.new()
	bg.name = "Backdrop"
	bg.color = Color(0, 0, 0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# `.transition-content` — 260x260, centred. Positioned explicitly rather than by a
	# container: the PWA's flex parent centres it and the port's canvas is the 390 the
	# measurement was taken at.
	var box := Control.new()
	box.position = Vector2(CONTENT_X, CONTENT_Y)
	box.size = Vector2(IMAGE_SIZE, IMAGE_SIZE)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_image = TextureRect.new()
	_image.name = "Art"
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# `object-fit:contain` — the art keeps its own aspect inside the 260x260 box.
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The CSS radial mask is BAKED INTO the texture rather than applied by a shader.
	#
	# ⚠️  A shader was tried first and it is the wrong tool here. `mask-image` is a pure
	# function of UV, so baking produces identical pixels — and it removes a failure mode that
	# did actually bite: a freshly built `ShaderMaterial` reported **null** for all three
	# `hint_range` uniforms (measured), so the shader ran with a zeroed `outer` and
	# `smoothstep(0.40, 0.0, r)` blacked out everything but the centre. Setting them explicitly
	# still left the masked box at **28.1** against the CSS's own **115.7**. Baking is
	# deterministic, needs no uniforms, and its result is a plain texture a test can read.
	box.add_child(_image)

	_reveal = ColorRect.new()
	_reveal.name = "Reveal"
	_reveal.color = Color(0, 0, 0)
	# `border-radius:12px` is NOT expressible on a ColorRect and does not need to be: the plate
	# covers the same 260x260 box the image is masked inside, and at those corners the mask is
	# already fully transparent, so a rounded corner would reveal nothing.
	_reveal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reveal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_reveal)


## Start a transition to `art`. An empty path shows the overlay black, which is what the
## PWA's un-loaded `<img src="">` looked like on the first frame.
func play(art: String, on_done: Callable) -> void:
	_art_path = art
	_image.texture = _masked(load(art)) if art != "" else null
	_on_done = on_done
	_reveal.color = Color(0, 0, 0)
	_reveal_ms = 0.0
	_elapsed_ms = 0.0
	_hold_ms = HOLD_MS
	_fade_ms = 0.0
	modulate = Color(1, 1, 1, 1)
	_active = true
	visible = true
	queue_redraw()


## `getStopImage` — the stop's own art, from the same rule the map and the result page use.
static func stop_art_path(act_id: int, stop: int) -> String:
	var generated := "res://assets/stops/stop_act%d_%d.webp" % [act_id, clampi(stop, 0, 9)]
	if ResourceLoader.exists(generated):
		return generated
	var placeholder := "res://assets/stops/placeholder_act%d.png" % act_id
	if ResourceLoader.exists(placeholder):
		return placeholder
	return ""


## The CSS mask, baked: `radial-gradient(ellipse 66% 66% at 50% 50%, #000 40%,
## transparent 85%)` applied to the ARt's own pixels, so the returned texture is what the PWA
## paints (the art with its edges melted into black).
##
## `ellipse 66% 66%` means the gradient's radius is 66 % of the BOX, so the normalised radius
## is `distance / 0.66` in a centred UV; the stops are then the CSS's own 0.40 and 0.85, which
## is why the core (out to 40 % of the box's half-width) stays fully solid. `smoothstep`
## between the two stops is the CSS gradient's own ramp.
##
## ⚠️  The mask is baked against the BOX, square, even when the art is not: that is what CSS
## does (`mask-image` applies to the element, `object-fit` only decides what is painted
## inside). All four of the PWA's transition images are 512x512, so the square box is also the
## art's own shape and the two agree — but the rule is the box's, not the art's.
static func masked_texture(tex: Texture2D) -> ImageTexture:
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null:
		return null
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return null
	for y in h:
		var v := (float(y) + 0.5) / float(h)
		for x in w:
			var u := (float(x) + 0.5) / float(w)
			var dx := (u - 0.5) / 0.66
			var dy := (v - 0.5) / 0.66
			var r := sqrt(dx * dx + dy * dy)
			var m := 1.0 - smoothstep(0.40, 0.85, r)
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, c.a * m))
	return ImageTexture.create_from_image(img)


func _masked(tex: Texture2D) -> Texture2D:
	return masked_texture(tex)


func is_transitioning() -> bool:
	return _active


## The 260x260 `.transition-content` box in global coordinates — what the PWA's
## `getBoundingClientRect` reports for `.transition-image`. A probe asserts against this; the
## alternative is walking `get_node("Backdrop").get_parent().get_child(1).get_node("Art")`,
## which breaks the moment the node order changes.
func image_rect() -> Rect2:
	return _image.get_global_rect() if _image != null else Rect2()


## What the overlay currently looks like, for a test and for a capture: the reveal's own
## alpha, the fade's progress and the art. `_reveal.color.a` is the `::after` opacity.
func state() -> Dictionary:
	return {
		"active": _active,
		"art": _art_path,
		"reveal_alpha": _reveal.color.a,
		"fade_alpha": modulate.a,
		"hold_ms": _hold_ms,
		"elapsed_ms": _elapsed_ms,
		"reveal_ms": _reveal_ms,
		"fade_ms": _fade_ms,
	}


func _process(delta: float) -> void:
	if not _active:
		return
	var ms := delta * 1000.0
	# The overlay's own monotone clock. `_reveal_ms` stops at 1.4 s (the reveal is `forwards`
	# and then holds at 0), so anything sampling the overlay later — a probe at 1.5 s and
	# 1.85 s — needs a clock that does not freeze.
	_elapsed_ms += ms
	# `transitionReveal` 1.4s ease-out, forwards: opacity 1 -> 0 and it STAYS at 0. The elapsed
	# time is kept separately and the ease solved from it, rather than accumulating the eased
	# value (one subtraction per frame drifts with the frame rate).
	if _reveal_ms < REVEAL_MS:
		_reveal_ms = minf(REVEAL_MS, _reveal_ms + ms)
		var t := clampf(_reveal_ms / REVEAL_MS, 0.0, 1.0)
		_reveal.color.a = 1.0 - cubic_bezier(t, EASE_OUT[0], EASE_OUT[1], EASE_OUT[2], EASE_OUT[3])
		if t >= 1.0:
			_reveal.color.a = 0.0
	# The 1800 ms hold, then the callback and the fade start IN THE SAME TICK — that ordering
	# is the PWA's and is why no screen flashes.
	if _hold_ms > 0.0:
		_hold_ms = maxf(0.0, _hold_ms - ms)
		if _hold_ms > 0.0:
			return
		if _on_done.is_valid():
			_on_done.call()
			_on_done = Callable()
		return
	# `transitionScreenFadeOut` 0.4s ease-in: slow start, fast end.
	_fade_ms += ms
	var t2 := clampf(_fade_ms / FADE_MS, 0.0, 1.0)
	modulate.a = 1.0 - cubic_bezier(t2, EASE_IN[0], EASE_IN[1], EASE_IN[2], EASE_IN[3])
	if t2 >= 1.0:
		_active = false
		visible = false


## A CSS `cubic-bezier(x1, y1, x2, y2)`: the eased PROGRESS at linear time `t`.
##
## ⚠️  The curve is parametric — `x(s)` and `y(s)` are both cubics of `s` — so `y` at a given
## `t` cannot be read off directly. `x(s) == t` is solved by bisection (the x-control points
## are in [0,1] for every CSS timing function, so `x` is monotone) and the resulting `s` gives
## `y`. Newton would need the derivative and can overshoot; 24 bisection steps are exact to
## about 1e-7, which is far below a pixel.
static func cubic_bezier(t: float, x1: float, y1: float, x2: float, y2: float) -> float:
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return 1.0
	var lo := 0.0
	var hi := 1.0
	var s := t
	for _i in 24:
		s = (lo + hi) * 0.5
		if _bezier_axis(s, x1, x2) < t:
			lo = s
		else:
			hi = s
	return _bezier_axis(s, y1, y2)


static func _bezier_axis(s: float, a1: float, a2: float) -> float:
	var u := 1.0 - s
	return 3.0 * u * u * s * a1 + 3.0 * u * s * s * a2 + s * s * s
