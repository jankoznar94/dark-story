extends SceneTree
## The port's TRANSITION overlay, sampled on the transition's OWN clock and put next to the
## PWA's measured numbers.
##
##   godot4 --rendering-driver opengl3 --path . --script res://tools/probe_transition_port.gd \
##       -- --type town --shots 0.15,1.5,1.85
##
## ⚠️  `--headless` is useless here: `frame_post_draw` never fires without a real renderer, so
## the capture hangs forever.
##
## ⚠️  The samples are taken on the TRANSITION's clock (`_reveal_ms`, `_fade_ms`, `_hold_ms`),
## not on a counter kept here. A probe that accumulates `delta` itself is a SECOND clock: it
## reported 0.15 s while the transition had actually been running ~0.30 s (the transition is a
## child node and gets its own `_process` ordering), so every comparison against the PWA's
## mid-animation numbers was being made at the wrong instant and read as a wrong curve.
##
## What it prints that a PNG cannot: the overlay's own rect and layer, and the reveal plate's
## alpha at each sample. The reveal is a 1.4 s fade of a black plate OVER the image, so one
## frame cannot show that it animates at all — the alphas prove it, and they are compared
## against the live PWA's (0.828 at 0.15 s, 0 at 1.5 s).

var _main: Node = null
var _started := false
var _shot_times: Array[float] = []
var _shot_index := 0
var _type := "town"
var _out_dir := "/tmp/transition_port"
var _printed_geometry := false
var _samples: Array = []
var _done := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--type":
				_type = args[i + 1]
			"--shots":
				for s in args[i + 1].split(","):
					_shot_times.append(float(s))
			"--out":
				_out_dir = args[i + 1]
		i += 2
	if _shot_times.is_empty():
		_shot_times = [0.15, 1.5, 1.85]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		if _main._transition == null or _main._nav_bar == null:
			return false
		_started = true
		_main.show_screen("town")
		_start_transition()
		return false

	if _done:
		_finish()
		return true

	var tr = _main._transition
	if not _printed_geometry:
		_printed_geometry = true
		var layer: int = tr.get_parent().layer
		print("overlay rect=%s layer=%d modal_layer=%d nav_layer=5 (the PWA's overlay is z 9999, the modal 1000)"
			% [str(tr.get_global_rect()), layer, _main._modal_layer.layer])

	var elapsed_ms: float = tr._elapsed_ms
	if _shot_index < _shot_times.size() and elapsed_ms >= _shot_times[_shot_index] * 1000.0:
		_capture(_shot_index, elapsed_ms)
		return false
	# The whole sequence is 2.2 s (1800 hold + 400 fade). ⚠️  The check is on `_done` being
	# already set: `_finish()` is called on the frame AFTER, because `_capture` awaits a frame
	# and a `quit()` inside an awaited path is what leaves the tool hanging.
	if _shot_index >= _shot_times.size() and not tr.is_transitioning():
		_done = true
	return false


func _start_transition() -> void:
	var tr = _main._transition
	match _type:
		"wilderness":
			_main._transition_to(tr.WILDERNESS_ART, func(): pass)
		"portal":
			_main._transition_to(tr.PORTAL_ART, func(): pass)
		"stop":
			_main._transition_to(tr.stop_art_path(0, 3), func(): pass)
		_:
			_main._transition_to(tr.TOWN_ART, func(): pass)


func _capture(index: int, elapsed_ms: float) -> void:
	_shot_index += 1
	# ⚠️  State BEFORE the await. `frame_post_draw` costs a frame or two, during which the
	# transition keeps ticking — reading the alpha after it reported 0.792 for a sample taken
	# at 0.150 s, where the CSS curve says 0.828, i.e. the measurement looked like a wrong
	# easing when it was a measurement taken one frame late.
	var st: Dictionary = _main._transition.state()
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var path := "%s/%s_%d.png" % [_out_dir, _type, index]
	img.save_png(path)
	var rec := {
		"requested_s": _shot_times[index],
		"at_s": elapsed_ms / 1000.0,
		"reveal_alpha": st["reveal_alpha"],
		"fade_alpha": st["fade_alpha"],
		"hold_ms": st["hold_ms"],
		"png": path,
	}
	_samples.append(rec)
	print("sample %d requested=%.2fs at=%.3fs reveal_alpha=%.3f fade_alpha=%.3f hold_ms=%.0f -> %s"
		% [index, _shot_times[index], elapsed_ms / 1000.0, st["reveal_alpha"], st["fade_alpha"],
			st["hold_ms"], path])


## The PWA's own numbers, from `tools/import/probe_transition_pwa.py` at 390x844.
const PWA := {
	"art_rect": [65.0, 292.0, 260.0, 260.0],
	"overlay_rect": [0.0, 0.0, 390.0, 844.0],
	"reveal_alpha_at_0_15": 0.828,
	"reveal_alpha_at_1_50": 0.0,
}
## `.transition-screen.fade-out` at t=0.125 (50 ms into a 400 ms ease-in) from the CSS curve.
const PWA_FADE_ALPHA_AT_1_85 := 1.0 - 0.005

## The CSS `cubic-bezier(x1, y1, x2, y2)` evaluated at linear progress `t`, as a static
## helper on this tool — the transition screen's own is on its instance.
##
## ⚠️  NOT `TransitionScreen.cubic_bezier(...)`. Calling a `static func` on a `class_name`
## whose script is not otherwise loaded fails with "Function … not found in base self", which
## is the same trap the arena's `GaugeArc.new()` hit. Reaching it through the main's instance
## (`_main._transition.cubic_bezier`) works, and this local copy keeps the probe readable.
static func bezier(t: float, x1: float, y1: float, x2: float, y2: float) -> float:
	if t <= 0.0:
		return 0.0
	if t >= 1.0:
		return 1.0
	var lo := 0.0
	var hi := 1.0
	var s := t
	for _i in 24:
		s = (lo + hi) * 0.5
		var u := 1.0 - s
		var x := 3.0 * u * u * s * x1 + 3.0 * u * s * s * x2 + s * s * s
		if x < t:
			lo = s
		else:
			hi = s
	var u2 := 1.0 - s
	return 3.0 * u2 * u2 * s * y1 + 3.0 * u2 * s * s * y2 + s * s * s


func _finish() -> void:
	var tr = _main._transition
	var failures: Array[String] = []
	var rect: Rect2 = tr.get_global_rect()
	var overlay: Array = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	print("PWA overlay rect=%s, port=%s" % [str(PWA["overlay_rect"]), str(overlay)])
	for i in 4:
		if absf(overlay[i] - PWA["overlay_rect"][i]) > 0.5:
			failures.append("overlay rect differs at %d: port %s PWA %s" % [i, str(overlay), str(PWA["overlay_rect"])])
	var art: Rect2 = tr.image_rect()
	var art_rect: Array = [art.position.x, art.position.y, art.size.x, art.size.y]
	print("PWA image rect=%s, port=%s" % [str(PWA["art_rect"]), str(art_rect)])
	for i in 4:
		if absf(art_rect[i] - PWA["art_rect"][i]) > 0.5:
			failures.append("image rect differs at %d: port %s PWA %s" % [i, str(art_rect), str(PWA["art_rect"])])
	for s in _samples:
		if absf(float(s["requested_s"]) - 0.15) < 0.001:
			# ⚠️  Compared against the CSS curve at the time the sample ACTUALLY landed, not the
			# time it asked for. A frame is 16.7 ms and the reveal is 1400 ms, so the sample
			# lands up to a frame late: at the requested 0.150 s the curve gives 0.828 (the
			# PWA's own measured number), and at a 0.183 s landing it gives 0.792. Comparing the
			# late sample against the earlier instant reported a 0.036 "curve error" that was
			# purely the sampler's own latency.
			var at: float = float(s["at_s"])
			var expected: float = 1.0 - bezier(clampf(at * 1000.0 / 1400.0, 0.0, 1.0), 0.0, 0.0, 0.58, 1.0)
			var d: float = absf(float(s["reveal_alpha"]) - expected)
			print("reveal at %.3fs: port=%.3f curve=%.3f (diff %.3f); at the PWA's own 0.150s the curve is %.3f vs its measured %.3f"
				% [at, s["reveal_alpha"], expected, d, PWA["reveal_alpha_at_0_15"], PWA["reveal_alpha_at_0_15"]])
			if d > 0.02:
				failures.append("reveal alpha at %.3f s is %.3f, the CSS ease-out gives %.3f"
					% [at, s["reveal_alpha"], expected])
			if absf(bezier(150.0 / 1400.0, 0.0, 0.0, 0.58, 1.0)
					- (1.0 - float(PWA["reveal_alpha_at_0_15"]))) > 0.01:
				failures.append("the ported ease-out curve does not reproduce the PWA's measured 0.828 at 0.150 s")
		if absf(float(s["requested_s"]) - 1.5) < 0.001:
			if float(s["reveal_alpha"]) > 0.001:
				failures.append("the reveal plate is still at %.3f after 1.5 s — the PWA's animation is 1.4 s, forwards"
					% s["reveal_alpha"])
	for f in failures:
		print("  FAIL: %s" % f)
	print("TRANSITION_PROBE_ALL_PASS=%s" % ("true" if failures.is_empty() else "false"))
	quit(0 if failures.is_empty() else 1)
