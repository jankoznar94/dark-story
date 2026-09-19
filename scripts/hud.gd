extends CanvasLayer
## Touch HUD: fixed joystick left, five round buttons in a d-pad cross right
## (attack bottom, potion top, skills left/right, RUN in the middle), plus two
## vitals bars for the player and the enemy.
##
## Circles are drawn by StyleBoxFlat. `flat` MUST stay false - a flat Button
## renders no stylebox at all, which is why the circles were previously invisible
## and only the text showed.
##
## No hover/focus styling anywhere (mobile PWA): normal and hover are the same
## stylebox. A `pressed` style exists only so a tap has visible feedback.
##
## RUN is a LATCH, not a hold: the joystick already owns the thumb, so a
## hold-to-run button cannot be pressed at the same time as it. Tap = run,
## tap again = walk. The joystick can also be pushed past its outer band, which
## does the same thing without the button.

const COL_FILL := Color(0.17, 0.14, 0.11, 0.80)
const COL_FILL_PRESSED := Color(0.30, 0.24, 0.16, 0.92)
const COL_EDGE := Color(0.62, 0.51, 0.34, 0.95)
const COL_EDGE_PRESSED := Color(0.90, 0.74, 0.42, 1.0)
const COL_TEXT := Color(0.90, 0.85, 0.72)
const COL_TEXT_PRESSED := Color(1.0, 0.96, 0.86)

## Slot -> Input Map action. Attack/potion/skills are one-shot action presses
## (the hold semantics live in player.gd reading is_action_pressed).
const SLOTS := ["up", "down", "left", "right"]
const ACTIONS := {
	"down": "attack",
	"up": "potion",
	"left": "skill_1",
	"right": "skill_2",
}
## Short labels: a circle at 90 px cannot fit long words.
const LABELS := {
	"attack": "Útok",
	"potion": "Lektvar",
	"skill_1": "K1",
	"skill_2": "K2",
}

## The fifth, centre button. It is a LATCH (run_toggled), never an Input action.
const RUN_LABEL := "Běh"

var joystick: VirtualJoystick
var debug_label: Label
var run_button: Button
## Latched run state, read by main.gd -> player.gd once per frame. The joystick
## and the `run` key/button are OR-ed into it, so no single control can block the
## others.
var run_latched: bool = false

var hp_fill: ColorRect
var hp_label: Label
var enemy_fill: ColorRect
var enemy_label: Label

var _buttons: Dictionary = {}
var _bar_w: float = 200.0


func _ready() -> void:
	_build()
	get_viewport().size_changed.connect(func() -> void: _layout())
	_layout()


func _build() -> void:
	joystick = VirtualJoystick.new()
	joystick.name = "VirtualJoystick"
	joystick.joystick_mode = VirtualJoystick.JOYSTICK_FIXED
	joystick.action_left = "move_left"
	joystick.action_right = "move_right"
	joystick.action_up = "move_up"
	joystick.action_down = "move_down"
	joystick.deadzone_ratio = 0.18
	add_child(joystick)

	for slot in SLOTS:
		var action: String = ACTIONS[slot]
		var b := _round_button(LABELS[action])
		b.name = "Btn_" + slot
		# Keep the action pressed for as long as the button is held. The player
		# reads is_action_pressed for the basic attack, so holding = attacking
		# until released, with no extra logic here.
		b.button_down.connect(func() -> void: Input.action_press(action))
		b.button_up.connect(func() -> void: Input.action_release(action))
		_buttons[slot] = b

	run_button = _round_button(RUN_LABEL)
	run_button.name = "Btn_run"
	# A latch, not a hold: the joystick already owns the thumb, so hold-to-run
	# could never be pressed at the same time as it. Tap = run, tap again = walk.
	run_button.toggle_mode = true
	run_button.toggled.connect(_on_run_toggled)

	debug_label = Label.new()
	debug_label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.62))
	debug_label.add_theme_font_size_override("font_size", 16)
	add_child(debug_label)

	_build_bars()

	var touch := DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	joystick.visible = touch


## One round button, identical styling everywhere. focus_mode NONE and
## normal == hover == focus, per the art rules.
func _round_button(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.flat = false                     # false => the circle actually draws
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.clip_text = true                 # min size must not follow the label
	b.custom_minimum_size = Vector2.ZERO
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_color_pressed", COL_TEXT_PRESSED)
	b.add_theme_color_override("font_color_hover", COL_TEXT)
	b.add_theme_color_override("font_color_focus", COL_TEXT)
	var idle := _circle(COL_FILL, COL_EDGE)
	var down := _circle(COL_FILL_PRESSED, COL_EDGE_PRESSED)
	b.add_theme_stylebox_override("normal", idle)
	b.add_theme_stylebox_override("hover", idle)
	b.add_theme_stylebox_override("focus", idle)
	b.add_theme_stylebox_override("disabled", idle)
	b.add_theme_stylebox_override("pressed", down)
	add_child(b)
	return b


func _build_bars() -> void:
	## Player vitals top-left, enemy vitals top-centre-right. Plain ColorRects:
	## no theme, no glow, same warm palette as everything else.
	var edge := Color(0.62, 0.51, 0.34, 0.9)

	var pbox := ColorRect.new()
	pbox.name = "HpBack"
	# The BACK rect is the frame: it is edge-coloured and the fill sits on top
	# inset by 2 px, so the remaining rim reads as a border. Two nodes per bar.
	pbox.color = edge
	add_child(pbox)
	hp_fill = ColorRect.new()
	hp_fill.name = "HpFill"
	hp_fill.color = Color(0.62, 0.20, 0.16)
	add_child(hp_fill)
	hp_label = Label.new()
	hp_label.name = "HpLabel"
	hp_label.add_theme_color_override("font_color", COL_TEXT)
	hp_label.add_theme_font_size_override("font_size", 16)
	add_child(hp_label)

	var ebox := ColorRect.new()
	ebox.name = "EnemyBack"
	ebox.color = edge
	add_child(ebox)
	enemy_fill = ColorRect.new()
	enemy_fill.name = "EnemyFill"
	enemy_fill.color = Color(0.66, 0.42, 0.18)
	add_child(enemy_fill)
	enemy_label = Label.new()
	enemy_label.name = "EnemyLabel"
	enemy_label.add_theme_color_override("font_color", COL_TEXT)
	enemy_label.add_theme_font_size_override("font_size", 16)
	add_child(enemy_label)

	# store the boxes so _layout can move them without hunting the tree
	_bars = {
		"p_back": pbox, "p_fill": hp_fill,
		"e_back": ebox, "e_fill": enemy_fill,
	}


var _bars: Dictionary = {}


func _circle(fill: Color, edge: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = edge
	sb.set_border_width_all(3)          # thick enough to read on a phone
	sb.set_corner_radius_all(999)
	sb.set_content_margin_all(0)
	sb.anti_aliasing = true
	return sb


func _on_run_toggled(on: bool) -> void:
	run_latched = on


func _layout(size: Vector2 = Vector2.ZERO) -> void:
	## size defaults to the live viewport; passing one lets tests verify real
	## device resolutions (headless is always square, so landscape needs this).
	var vs: Vector2 = size if size != Vector2.ZERO else get_viewport().get_visible_rect().size
	var m: float = min(vs.x, vs.y)
	var margin: float = m * 0.055

	# left thumb: joystick, fixed
	var jd: float = m * 0.40
	joystick.size = Vector2(jd, jd)
	joystick.joystick_size = jd * 0.5
	joystick.position = Vector2(margin, vs.y - margin - jd)

	# right thumb: d-pad cross + the run button in the middle of it.
	var d: float = m * 0.125                        # diameter
	var r: float = m * 0.158                        # centre -> button centre
	var cx: float = vs.x - margin - r - d * 0.5
	var cy: float = vs.y - margin - r - d * 0.5
	var offsets := {
		"up": Vector2(0.0, -r),
		"down": Vector2(0.0, r),
		"left": Vector2(-r, 0.0),
		"right": Vector2(r, 0.0),
	}
	for slot in SLOTS:
		var off: Vector2 = offsets[slot]
		_place(_buttons[slot], Vector2(cx, cy) + off - Vector2(d, d) * 0.5, d)
	_place(run_button, Vector2(cx, cy) - Vector2(d, d) * 0.5, d)

	debug_label.position = Vector2(margin, margin * 0.5)

	# vitals: player bar under the debug line, enemy bar on the right above the pad
	_bar_w = clampf(vs.x * 0.26, 160.0, 420.0)
	var bh: float = maxf(14.0, m * 0.028)
	var bar_y: float = margin * 0.5 + m * 0.06
	_box(_bars["p_back"], Vector2(margin, bar_y), Vector2(_bar_w, bh))
	_box(_bars["p_fill"], Vector2(margin + 2.0, bar_y + 2.0), Vector2(_bar_w - 4.0, bh - 4.0))
	hp_label.position = Vector2(margin + 6.0, bar_y - m * 0.045)
	hp_label.add_theme_font_size_override("font_size", int(maxf(12.0, m * 0.026)))

	var ex: float = vs.x - margin - _bar_w
	var ey: float = margin * 0.5
	_box(_bars["e_back"], Vector2(ex, ey), Vector2(_bar_w, bh))
	_box(_bars["e_fill"], Vector2(ex + 2.0, ey + 2.0), Vector2(_bar_w - 4.0, bh - 4.0))
	enemy_label.position = Vector2(ex + 6.0, ey - m * 0.045)
	enemy_label.add_theme_font_size_override("font_size", int(maxf(12.0, m * 0.026)))


func _box(c: Control, pos: Vector2, size: Vector2) -> void:
	c.position = pos
	c.size = size


func _place(b: Button, pos: Vector2, size: float) -> void:
	b.custom_minimum_size = Vector2.ZERO
	b.size = Vector2(size, size)
	b.position = pos
	b.add_theme_font_size_override("font_size", int(maxf(11.0, size * 0.22)))
	# keep it a perfect circle as the button resizes
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb: StyleBoxFlat = b.get_theme_stylebox(state)
		if sb is StyleBoxFlat:
			sb.set_corner_radius_all(int(size * 0.5) + 1)


func set_debug(text: String) -> void:
	if debug_label:
		debug_label.text = text


func set_player_hp(fraction: float, text: String) -> void:
	if hp_fill:
		hp_fill.size = Vector2(maxf(0.0, (_bar_w - 4.0) * clampf(fraction, 0.0, 1.0)), hp_fill.size.y)
	if hp_label:
		hp_label.text = text


func set_enemy_hp(fraction: float, text: String) -> void:
	if enemy_fill:
		enemy_fill.size = Vector2(maxf(0.0, (_bar_w - 4.0) * clampf(fraction, 0.0, 1.0)), enemy_fill.size.y)
	if enemy_label:
		enemy_label.text = text
