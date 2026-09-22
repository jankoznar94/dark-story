extends SceneTree
## Probe: can FontVariation's `spacing_top` / `spacing_bottom` shrink a Label's height?
## Godot's Label minimum height is the font's own ascent+descent (~1.43 x font size with
## the default font) while the PWA's CSS line-height is 1.15 x. `line_spacing` only adds
## BETWEEN lines, so a single-line label ignores it. If negative glyph spacing works,
## UIKit.label() can set a line height that matches the CSS in ONE place.

var _labels: Array = []
var _frames := 0


func _initialize() -> void:
	for top in [0, -1, -2, -3, -4]:
		for bottom in [0, -1, -2, -3]:
			var l := Label.new()
			l.text = "Truhla"
			l.add_theme_font_size_override("font_size", 14)
			var fv := FontVariation.new()
			fv.spacing_top = top
			fv.spacing_bottom = bottom
			l.add_theme_font_override("font", fv)
			root.add_child(l)
			_labels.append([top, bottom, l])


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false
	var seen := {}
	for entry in _labels:
		var top: int = entry[0]
		var bottom: int = entry[1]
		var l: Label = entry[2]
		var h := int(l.get_combined_minimum_size().y)
		seen["%d/%d=%d" % [top, bottom, h]] = true
	for key in seen.keys():
		print(key)
	print("--- css target for 14px = 16")
	quit()
	return true
