extends SceneTree
## probe_alpha_calibration.gd — CSS dims by `opacity`, Godot dims by `modulate`, and the
## two do NOT land on the same pixel. The PWA's empty `.chest-cell` is `#aaa` at
## `opacity:0.25` over a `#000` wrap, which the browser renders as **rgb(43,43,43)**.
## A Godot `modulate.a = 0.25` on the same `#aaa` renders as **rgb(56,56,56)** — 13 levels
## too light, which is the whole of the port's remaining empty-cell diff.
##
## So the alpha we ship has to be the one that MEASURES as the PWA's pixel. Sweep for it.
## Sample the CENTRE of an un-rounded box so no corner anti-aliasing gets into the reading.
##
##   godot4 --path . --rendering-driver opengl3 --script res://tools/probe_alpha_calibration.gd

var _frames := 0
var _printed := false

## Fine sweep around the region the earlier probe bracketed (0.15 -> 41, 0.18 -> 45).
const ALPHAS := [0.25, 0.20, 0.19, 0.18, 0.17, 0.16, 0.15, 0.14, 0.12, 0.10, 0.05]
const TARGET := 43  # the PWA's own rendered pixel for an empty cell


func _initialize() -> void:
	root.size = Vector2i(390, 844)
	# A black plate first, exactly as `.inv-grid-wrap { background:#000 }`.
	var plate := ColorRect.new()
	plate.color = Color("000000")
	plate.position = Vector2.ZERO
	plate.size = Vector2(390, 844)
	root.add_child(plate)
	for i in ALPHAS.size():
		# No corner radius, so the centre sample cannot catch an anti-aliased edge.
		var box := ColorRect.new()
		box.color = Color("#aaaaaa")
		# A plain Control's modulate does NOT dim its own `_draw()` — but a ColorRect's
		# colour IS its draw, and Godot applies the CanvasItem modulate to it, which is
		# the same path a Button's stylebox takes.
		box.modulate = Color(1, 1, 1, ALPHAS[i])
		box.position = Vector2(20 + i * 32, 100)
		box.size = Vector2(28, 28)
		root.add_child(box)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false
	if _printed:
		return false
	_printed = true
	var img: Image = root.get_texture().get_image()
	var best := -1.0
	var best_delta := 999
	print("target = %d (the PWA's rendered empty cell, #aaa @ opacity .25 over #000)" % TARGET)
	for i in ALPHAS.size():
		var x := 20 + i * 32 + 14
		var y := 100 + 14
		var c := img.get_pixel(x, y)
		var v := int(round(c.r * 255.0))
		var d: int = absi(v - TARGET)
		if d < best_delta:
			best_delta = d
			best = ALPHAS[i]
		print("  alpha %.3f -> rgb(%d,%d,%d)   delta=%d" % [
			ALPHAS[i], v, int(round(c.g * 255.0)), int(round(c.b * 255.0)), d])
	print("CLOSEST_ALPHA=%.3f  (renders %d, target %d)" % [best, TARGET - best_delta + best_delta, TARGET])
	print("ALPHA_CALIBRATION_DONE=true")
	quit()
	return false
