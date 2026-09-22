extends RefCounted
class_name UIFonts
## UIFonts — the one place the port's type comes from.
##
## The reference frames are shot in headless Chromium where the PWA's
## `font-family: system-ui, sans-serif` resolves to **DejaVu Sans**. Measured, not
## guessed: "Truhla" is 303px wide at 100px in that Chromium, DejaVuSans.ttf gives
## 303.3, Ubuntu 282 and Godot's own default (Open Sans SemiBold) 313. So DejaVu is the
## face the specification is drawn in, and it is bundled in `assets/fonts/`.
##
## Switching the port to it fixes two drifts at once:
##   - advances: Open Sans is 3% wider, so every measured element was a little long;
##   - line box: Godot's default gives ~1.43em, DejaVu ~1.16em, and the CSS
##     `line-height: normal` is the ~1.15em the reference frames show. That excess
##     accumulated into the vertical drift visible on every screen (a 14px Label was
##     20px tall where the PWA's is 16).
##
## `spacing_top/bottom` is the lever for the last pixel: a Label's minimum height is the
## font's own ascent+descent, and shrinking the ascent is the only way to bring it down
## (`line_spacing` only adds BETWEEN lines, so a single-line label ignores it).
## `tools/probe_font.gd` measures the value per size against the CSS targets.
##
## Bold is a real face, not `variation_embolden`: CSS `font-weight: bold` in DejaVu is
## ~13% wider than the regular ("Back to Town" 111.4 vs 98.6 at 15px), and faking it
## would keep the advances wrong.

const REGULAR_PATH := "res://assets/fonts/DejaVuSans.ttf"
const BOLD_PATH := "res://assets/fonts/DejaVuSans-Bold.ttf"

## CSS `line-height: normal` for DejaVu Sans, read off the live PWA per font size by
## measuring a bare element's `offsetHeight`. `tools/probe_font.gd` checks a Godot
## Label against these; a size missing here gets no spacing adjustment.
const CSS_LINE_HEIGHT := {
	9: 11, 10: 12, 11: 13, 12: 14, 13: 15, 14: 16, 15: 17, 16: 19, 17: 20,
	18: 21, 19: 22, 20: 23, 21: 24, 22: 25, 24: 28, 26: 30, 28: 32, 32: 37, 36: 41,
}
## Measured by `tools/probe_font.gd`: DejaVu needs -1 at exactly these sizes to land on
## the CSS height. Everywhere else it already matches with no adjustment.
const SPACING_FIX := {13: -1, 22: -1, 26: -1, 36: -1}

static var _regular: FontFile = null
static var _bold: FontFile = null
static var _cache: Dictionary = {}


static func regular() -> FontFile:
	if _regular == null:
		_regular = _load(REGULAR_PATH)
	return _regular


static func bold() -> FontFile:
	if _bold == null:
		_bold = _load(BOLD_PATH)
	return _bold


## The font to hand to `add_theme_font_override("font", ...)` for a given size and weight.
## Cached: a screen rebuilds its labels on every refresh and this is called per label.
static func get_font(size: int, is_bold: bool = false) -> Font:
	var key := "%d:%s" % [size, is_bold]
	if _cache.has(key):
		return _cache[key]
	var fv := FontVariation.new()
	fv.base_font = bold() if is_bold else regular()
	var spacing: int = int(SPACING_FIX.get(size, 0))
	if spacing != 0:
		fv.spacing_top = spacing
		fv.spacing_bottom = spacing
	_cache[key] = fv
	return fv


## The project-wide `Theme` (`.godot`/`project.godot` `gui/theme/custom`). Built in code
## by `tools/build_theme.gd` rather than hand-written as a `.tres`, because a theme file
## references font resources by UID and a hand-edited one silently loads nothing.
static func build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = regular()
	theme.default_font_size = 14
	return theme


static func _load(path: String) -> FontFile:
	# `ResourceLoader.load` gets the IMPORTED FontFile (the `.import` beside the .ttf turns
	# it into a resource). `load_dynamic_font` would read the raw file, which works in the
	# editor but is NOT packed into an export — the font would vanish from the built game
	# with no error. The raw path is kept as a fallback for a `--script` tool running
	# before the first import.
	var res := ResourceLoader.load(path)
	if res is FontFile:
		return res
	push_warning("UIFonts: %s is not imported yet, reading the raw file" % path)
	var f := FontFile.new()
	var err := f.load_dynamic_font(path)
	if err != OK:
		push_error("UIFonts: cannot load %s (err %d)" % [path, err])
	return f
