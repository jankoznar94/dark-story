extends CanvasLayer
## Touch HUD: fixed joystick left, four round buttons in a d-pad cross right.
##
## Circles are drawn by StyleBoxFlat. `flat` MUST stay false - a flat Button
## renders no stylebox at all, which is why the circles were previously invisible
## and only the text showed.
##
## No hover/focus styling anywhere (mobile PWA): normal and hover are the same
## stylebox. A `pressed` style exists only so a tap has visible feedback.

const COL_FILL := Color(0.17, 0.14, 0.11, 0.80)
const COL_FILL_PRESSED := Color(0.30, 0.24, 0.16, 0.92)
const COL_EDGE := Color(0.62, 0.51, 0.34, 0.95)
const COL_EDGE_PRESSED := Color(0.90, 0.74, 0.42, 1.0)
const COL_TEXT := Color(0.90, 0.85, 0.72)
const COL_TEXT_PRESSED := Color(1.0, 0.96, 0.86)

## Slot -> Input Map action. Fixed for now; binding is handled elsewhere.
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

var joystick: VirtualJoystick
var debug_label: Label
var _buttons: Dictionary = {}


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
		var b := Button.new()
		b.name = "Btn_" + slot
		b.text = str(LABELS[action])
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
		# normal == hover == focus: deliberately no hover effect
		b.add_theme_stylebox_override("normal", idle)
		b.add_theme_stylebox_override("hover", idle)
		b.add_theme_stylebox_override("focus", idle)
		b.add_theme_stylebox_override("disabled", idle)
		b.add_theme_stylebox_override("pressed", down)
		# Keep the action pressed for as long as the button is held. The player
		# reads is_action_pressed for the basic attack, so holding = attacking
		# until released, with no extra logic here.
		b.button_down.connect(func() -> void: Input.action_press(action))
		b.button_up.connect(func() -> void: Input.action_release(action))
		add_child(b)
		_buttons[slot] = b

	debug_label = Label.new()
	debug_label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.62))
	debug_label.add_theme_font_size_override("font_size", 16)
	add_child(debug_label)

	var touch := DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	joystick.visible = touch


func _circle(fill: Color, edge: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = edge
	sb.set_border_width_all(3)          # thick enough to read on a phone
	sb.set_corner_radius_all(999)
	sb.set_content_margin_all(0)
	sb.anti_aliasing = true
	return sb


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

	# right thumb: four buttons in a d-pad cross, all the same size.
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

	debug_label.position = Vector2(margin, margin * 0.5)


func _place(b: Button, pos: Vector2, size: float) -> void:
	b.custom_minimum_size = Vector2.ZERO
	b.size = Vector2(size, size)
	b.position = pos
	b.add_theme_font_size_override("font_size", int(max(11.0, size * 0.22)))
	# keep it a perfect circle as the button resizes
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb: StyleBoxFlat = b.get_theme_stylebox(state)
		if sb is StyleBoxFlat:
			sb.set_corner_radius_all(int(size * 0.5) + 1)


func set_debug(text: String) -> void:
	if debug_label:
		debug_label.text = text
