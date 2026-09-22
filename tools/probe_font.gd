extends SceneTree
## Probe: what the port's default font MUST be for the reference frames to match.
##
## The PWA's `font-family: system-ui, sans-serif` resolves to DejaVu Sans in the headless
## Chromium the reference frames are shot in — proof: "Truhla" measured 303px wide at
## 100px in Chromium, and DejaVuSans.ttf measures 304 while Ubuntu measures 282 and
## Godot's own default (Open Sans SemiBold) measures 313. So the port's text is 3% too
## wide and, worse, its line box is ~1.43em against the CSS's normal line-height of
## ~1.16em: an Open Sans Label at 14px is 20px tall where the PWA's is 16.
##
## This measures a bundled DejaVu Sans against those CSS line boxes and finds the
## `FontVariation.spacing_top/bottom` that lands each size on the reference height.

const DEJAVU := "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
## Measured in the live PWA (`getComputedStyle(el).lineHeight` / `offsetHeight`):
##   12px -> 14, 13px -> 15, 14px -> 16, 15px -> 17, 16px -> 19, 18px -> 21, 22px -> 25
const CSS_TARGET := {11: 13, 12: 14, 13: 15, 14: 16, 15: 17, 16: 19, 17: 20, 18: 21,
	19: 22, 20: 23, 21: 24, 22: 25}

var _labels: Array = []
var _frames := 0


func _initialize() -> void:
	var base := FontFile.new()
	if base.load_dynamic_font(DEJAVU) != OK:
		print("FAILED to load ", DEJAVU)
		quit()
		return
	for spacing in [0, -1, -2]:
		for size in CSS_TARGET.keys():
			var fv := FontVariation.new()
			fv.base_font = base
			if spacing != 0:
				fv.spacing_top = spacing
				fv.spacing_bottom = spacing
			var l := Label.new()
			l.text = "Truhla"
			l.add_theme_font_override("font", fv)
			l.add_theme_font_size_override("font_size", size)
			root.add_child(l)
			_labels.append([spacing, size, l])


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false
	var best := {}
	for entry in _labels:
		var spacing: int = entry[0]
		var size: int = entry[1]
		var l: Label = entry[2]
		var h := int(round(l.get_combined_minimum_size().y))
		var target: int = CSS_TARGET[size]
		if not best.has(size) or absi(h - target) < absi(best[size][1] - target):
			best[size] = [spacing, h]
		print("spacing=%d fs=%d -> %d  (css %d)" % [spacing, size, h, target])
	print("--- best spacing per size")
	for size in CSS_TARGET.keys():
		print("fs=%d  spacing=%d  h=%d  target=%d" % [
			size, best[size][0], best[size][1], CSS_TARGET[size]])
	quit()
	return true
