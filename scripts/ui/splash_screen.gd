extends Control
class_name SplashScreen
## SplashScreen — the PWA's `#splashScreen`, the black card with the shield and the game's
## name that sits over the game for three seconds on every launch.
##
## Source, measured off `public/style.css` + `index.html` + `src/game.ts`:
##
##   .splash-screen   fixed, full viewport, z-index 9999, flex centred, `background:#000`
##   .splash-content  column, `gap:16px`, `opacity:0`,
##                    `animation:splashContentFadeIn 0.8s ease-out 0.3s forwards`
##   .splash-icon     200x200, `border-radius:24px`
##   .splash-title    `font-size:24px`, bold, `#e8e0e8`, `letter-spacing:2px`,
##                    `text-transform:uppercase`
##   `.fade-out`      `splashFadeOut 0.6s ease-in forwards`
##
## and the clock in `game.ts` is `setTimeout(2500)` -> add `.fade-out` -> `setTimeout(600)`
## -> hide and only THEN show the first screen. The PWA also hid the nav bar for the whole
## splash; this overlay is opaque, so the bar is covered rather than removed.
##
## ⚠️  `@keyframes splashPulse` exists in the PWA's stylesheet and NO rule applies it. The
## icon therefore does not pulse, and this port does not pulse it either — an animation
## that was never seen is an invented visual.
##
## ⚠️  The splash swallows taps (`MOUSE_FILTER_STOP`) for its 3.1 s. In the PWA the overlay
## is a `position:fixed` box, so a tap during the splash lands on it too. Without this, the
## first tap of a launch could hit a town tile hidden behind the black plate.

## `.splash-icon` — 200x200 at the PWA's own scale.
const ICON_SIZE := 200.0
## `.splash-content { gap:16px }`.
const GAP := 16.0
## `splashContentFadeIn 0.8s … 0.3s` — the delay comes first, then the 800 ms ramp.
const FADE_IN_MS := 800.0
const FADE_IN_DELAY_MS := 300.0
## `setTimeout(…, 2500)` in `game.ts`.
const HOLD_MS := 2500.0
## `splashFadeOut 0.6s`.
const FADE_OUT_MS := 600.0
## `.splash-title{ font-size:24px; letter-spacing:2px; text-transform:uppercase; color:#e8e0e8 }`.
const TITLE_SIZE := 24
const TITLE_SPACING := 2
const TITLE_COLOUR := "#e8e0e8"
## The markup's own text, before `text-transform` capitalises it.
const TITLE := "Dungeon Recall"
const ICON_PATH := "res://assets/icon/splash_icon.png"

signal finished

var _elapsed := 0.0
var _done := false
var _content: Control = null
var _icon: TextureRect = null
var _title: Label = null


func _ready() -> void:
	name = "Splash"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# See the note at the top: a tap during the splash must not reach the town behind it.
	mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color.BLACK
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var column := VBoxContainer.new()
	column.name = "Content"
	column.add_theme_constant_override("separation", int(GAP))
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_child(column)
	_content = column
	_content.modulate.a = 0.0

	_icon = TextureRect.new()
	_icon.name = "Icon"
	# The rounded corners are baked into the asset (`assets/icon/splash_icon.png`), which is
	# the port's equivalent of `border-radius:24px` on a square PNG.
	_icon.texture = load(ICON_PATH)
	_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_icon)

	_title = Label.new()
	_title.name = "Title"
	_title.text = TITLE.to_upper()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", Color(TITLE_COLOUR))
	_title.add_theme_font_override("font", _title_font())
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_title)


## `letter-spacing:2px` has no Label property; a `FontVariation` carries it.
func _title_font() -> Font:
	var variation := FontVariation.new()
	variation.base_font = UIFonts.get_font(TITLE_SIZE, true)
	variation.spacing_glyph = TITLE_SPACING
	return variation


func _process(delta: float) -> void:
	_tick(delta * 1000.0)


## The whole animation, driven by milliseconds so a test can advance it deterministically
## instead of depending on how many frames the harness happened to run.
func _tick(delta_ms: float) -> void:
	if _done:
		return
	_elapsed += delta_ms
	if _content != null:
		var ramp := clampf((_elapsed - FADE_IN_DELAY_MS) / FADE_IN_MS, 0.0, 1.0)
		# `ease-out`: fast first, settling at the end.
		_content.modulate.a = ramp * (2.0 - ramp)
	var alpha := 1.0
	if _elapsed > HOLD_MS:
		var out := clampf((_elapsed - HOLD_MS) / FADE_OUT_MS, 0.0, 1.0)
		# `ease-in`: slow first, then gone.
		alpha = 1.0 - out * out
	modulate.a = alpha
	if _elapsed >= HOLD_MS + FADE_OUT_MS:
		_finish()


func _finish() -> void:
	_done = true
	visible = false
	# Stop ticking: the splash never comes back inside one launch.
	set_process(false)
	finished.emit()


func is_done() -> bool:
	return _done


## How long the splash has been up, in ms — the handle a test asserts on.
func elapsed_ms() -> float:
	return _elapsed


## The content column's own alpha, i.e. the fade-in progress.
func content_alpha() -> float:
	return _content.modulate.a if _content != null else 0.0
