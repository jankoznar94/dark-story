extends CanvasLayer
## Touch + keyboard HUD. Built in code so layout is resolution-independent
## (phone landscape, tablet, desktop all get sane thumb reach).
##
## Deliberately only FOUR targets: attack, skill_1, skill_2, potion.
## Diablo Immortal ships seven; that forces a fast game. We do not want that.

const COL_IDLE := Color(0.16, 0.13, 0.10, 0.72)
const COL_EDGE := Color(0.55, 0.45, 0.30, 0.85)

var joystick: VirtualJoystick
var _buttons: Dictionary = {}
var debug_label: Label


func _ready() -> void:
	_build()
	get_viewport().size_changed.connect(_layout)
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

	_buttons["attack"] = _make_button("ATTACK", "attack", 1.45)
	_buttons["skill_1"] = _make_button("HEAVY", "skill_1", 1.0)
	_buttons["skill_2"] = _make_button("SKILL", "skill_2", 1.0)
	_buttons["potion"] = _make_button("POT", "potion", 0.85)

	debug_label = Label.new()
	debug_label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.62))
	debug_label.add_theme_font_size_override("font_size", 16)
	debug_label.position = Vector2(16, 12)
	add_child(debug_label)

	# Touch controls only make sense on touch hardware.
	var touch := DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	joystick.visible = touch


func _make_button(text: String, action: String, scale_f: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE          # Jan: no hover/focus states
	b.flat = true
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_IDLE
	sb.border_color = COL_EDGE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(999)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)     # same as normal: no hover effect
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_color_override("font_color", Color(0.88, 0.82, 0.68))
	b.set_meta("scale_f", scale_f)
	b.button_down.connect(func() -> void: Input.action_press(action))
	b.button_up.connect(func() -> void: Input.action_release(action))
	add_child(b)
	return b


func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var m: float = min(vs.x, vs.y)
	var margin: float = m * 0.055

	# left thumb: joystick, fixed, bottom-left
	var jd: float = m * 0.42
	joystick.size = Vector2(jd, jd)
	joystick.joystick_size = jd * 0.5
	joystick.position = Vector2(margin, vs.y - margin - jd)

	# right thumb: attack cluster, bottom-right, nothing in screen centre
	var base: float = m * 0.20
	var ax: float = vs.x - margin
	var ay: float = vs.y - margin
	_place(_buttons["attack"], Vector2(ax - base * 1.45, ay - base * 1.45), base * 1.45)
	_place(_buttons["skill_1"], Vector2(ax - base * 1.45, ay - base * 0.55), base * 0.80)
	_place(_buttons["skill_2"], Vector2(ax - base * 0.55, ay - base * 1.45), base * 0.80)
	_place(_buttons["potion"], Vector2(ax - base * 0.60, ay - base * 0.60), base * 0.62)

	debug_label.position = Vector2(margin, margin * 0.5)


func _place(b: Button, pos: Vector2, size: float) -> void:
	b.size = Vector2(size, size)
	b.position = pos
	b.add_theme_font_size_override("font_size", int(max(11.0, size * 0.20)))


func set_debug(text: String) -> void:
	if debug_label:
		debug_label.text = text
