extends SceneTree
## Probe: does a negative FontVariation `spacing_top` clip Czech diacritics?
## UIKit.label() wants the PWA's line-height (1.15 x font size) and Godot's default font
## gives 1.43 x, so the height has to come down. Shrinking the font's own ascent is how
## that is done — but if it clips a `Ž` or a `ř` the cure is worse than the drift.
##
## Renders the same string at several spacings and reads the TOP row of glyph pixels:
## if the glyphs touch row 0 the accent has been cut.

const OUT := "/tmp/probe_line_clip.png"

var _root: Control
var _labels: Array = []
var _frames := 0


func _initialize() -> void:
	_root = Control.new()
	_root.size = Vector2(390, 400)
	root.add_child(_root)
	var y := 0.0
	for top in [0, -1, -2, -3, -4, -5]:
		var bg := ColorRect.new()
		bg.color = Color("#000000")
		bg.position = Vector2(0, y)
		bg.size = Vector2(390, 46)
		_root.add_child(bg)
		var l := Label.new()
		l.text = "Žluťoučký kůň úpěl ďábelské ódy 21:30"
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", Color("#ffffff"))
		if top != 0:
			var fv := FontVariation.new()
			fv.spacing_top = top
			fv.spacing_bottom = top
			l.add_theme_font_override("font", fv)
		l.position = Vector2(4, y + 2)
		l.size = Vector2(382, 42)
		_root.add_child(l)
		_labels.append([top, y])
		y += 48


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false
	_capture()
	return false


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(OUT)
	for entry in _labels:
		var top: int = entry[0]
		var y: int = int(entry[1])
		# First row inside this band that carries a white glyph pixel.
		var first := -1
		var last := -1
		for row in range(y, y + 46):
			var hit := false
			for x in range(0, 390):
				var p := img.get_pixel(x, row)
				if p.r > 0.5 and p.g > 0.5 and p.b > 0.5:
					hit = true
					break
			if hit:
				if first < 0:
					first = row
				last = row
		print("spacing_top=%d  first_glyph_row=%d (band starts %d)  last=%d  offset=%d" % [
			top, first, y, last, first - y])
	print("saved ", OUT)
	quit()
