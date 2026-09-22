extends SceneTree
## Probe: the exact `FontVariation.spacing_top/bottom` for each font size and weight that
## makes a Godot Label's line box equal the PWA's.
##
## The reference frames are shot in headless Chromium where `font-family: system-ui` is
## DejaVu Sans (proven: "Truhla" measures 303px @100px in Chromium and 303.3 in
## DejaVuSans.ttf, against 282 in Ubuntu and 313 in Godot's own Open Sans default). So
## DejaVu is what the SPEC is drawn in, and Godot must be told to use it and to give it
## the CSS's line-height (1.15em; measured `14px -> 16`, `22px -> 25`, `13px -> 15`).
##
## Prints the table that `scripts/ui/ui_fonts.gd` hardcodes.

const REGULAR := "res://assets/fonts/DejaVuSans.ttf"
const BOLD := "res://assets/fonts/DejaVuSans-Bold.ttf"
## Measured in the live PWA: getComputedStyle(el).lineHeight / offsetHeight of a bare
## element at that font size. CSS `line-height: normal` for DejaVu Sans.
const CSS_TARGET := {10: 12, 11: 13, 12: 14, 13: 15, 14: 16, 15: 17, 16: 19, 17: 20,
	18: 21, 19: 22, 20: 23, 21: 24, 22: 25, 24: 28, 26: 30, 28: 32, 32: 37, 36: 41}

var _rows: Array = []
var _frames := 0


func _initialize() -> void:
	var regular := FontFile.new()
	regular.load_dynamic_font(REGULAR)
	var bold := FontFile.new()
	bold.load_dynamic_font(BOLD)
	for weight in [["reg", regular], ["bold", bold]]:
		for spacing in [0, -1, -2, -3]:
			for size in CSS_TARGET.keys():
				var fv := FontVariation.new()
				fv.base_font = weight[1]
				if spacing != 0:
					fv.spacing_top = spacing
					fv.spacing_bottom = spacing
				var l := Label.new()
				l.text = "Truhla"
				l.add_theme_font_override("font", fv)
				l.add_theme_font_size_override("font_size", size)
				root.add_child(l)
				_rows.append([weight[0], spacing, size, l])


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false
	var best := {}
	for row in _rows:
		var weight: String = row[0]
		var spacing: int = row[1]
		var size: int = row[2]
		var l: Label = row[3]
		var h := int(round(l.get_combined_minimum_size().y))
		var key := "%s:%d" % [weight, size]
		var target: int = CSS_TARGET[size]
		if not best.has(key) or absi(h - target) < absi(best[key][1] - target):
			best[key] = [spacing, h]
	print("## size -> spacing (resulting height / css target)")
	for weight in ["reg", "bold"]:
		var parts: Array = []
		for size in CSS_TARGET.keys():
			var key := "%s:%d" % [weight, size]
			parts.append("%d:%d" % [size, best[key][0]])
		print("%s  %s" % [weight, " ".join(parts)])
	quit()
	return true
