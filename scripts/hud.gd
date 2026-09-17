extends CanvasLayer
## Touch HUD: fixed joystick on the left, a four-button d-pad cross on the right.
##
## Deliberately only FOUR actions. Diablo Immortal ships seven targets because it
## is a fast game; that forces the game to be fast. We are not.
##
## Interaction:
##   tap  = use the action
##   hold = rebind that button (a picker appears)
## Long-press rather than a settings menu keeps it inside the game, no separate
## screen to build.

const ControlBindings := preload("res://scripts/controls.gd")

const HOLD_TO_REBIND := 0.40
const COL_IDLE := Color(0.16, 0.13, 0.10, 0.74)
const COL_EDGE := Color(0.55, 0.45, 0.30, 0.85)
const COL_TEXT := Color(0.88, 0.82, 0.68)
const COL_PANEL := Color(0.09, 0.08, 0.07, 0.94)

var joystick: VirtualJoystick
var bindings: ControlBindings
var debug_label: Label

var _buttons: Dictionary = {}          # slot -> Button
var _press_started: Dictionary = {}    # slot -> msec
var _fired: Dictionary = {}            # slot -> bool (did the tap already fire?)
var _picker: Control
var _picker_for_slot: String = ""


func _ready() -> void:
	bindings = ControlBindings.new()
	_build()
	get_viewport().size_changed.connect(func() -> void: _layout())
	_layout()
	_apply_bindings()


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

	for slot in ControlBindings.SLOTS:
		var b := Button.new()
		b.name = "Btn_" + slot
		b.focus_mode = Control.FOCUS_NONE      # no hover/focus states, per art rules
		b.flat = true
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.clip_text = true                     # min size must NOT depend on the label
		b.custom_minimum_size = Vector2.ZERO
		b.add_theme_color_override("font_color", COL_TEXT)
		# normal / hover / pressed are all identical on purpose: no hover effect
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(state, _make_style())
		b.button_down.connect(_on_down.bind(slot))
		b.button_up.connect(_on_up.bind(slot))
		add_child(b)
		_buttons[slot] = b

	debug_label = Label.new()
	debug_label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.62))
	debug_label.add_theme_font_size_override("font_size", 16)
	add_child(debug_label)

	var touch := DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	joystick.visible = touch


func _make_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_IDLE
	sb.border_color = COL_EDGE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(999)       # fully round
	sb.set_content_margin_all(0)        # no padding: keeps min size at zero
	return sb


func _apply_bindings() -> void:
	for slot in ControlBindings.SLOTS:
		var b: Button = _buttons[slot]
		b.text = bindings.label_for_slot(slot)
		b.disabled = bindings.action_for(slot) == "none"


# ------------------------------------------------------------------ input
func _on_down(slot: String) -> void:
	_press_started[slot] = Time.get_ticks_msec()
	_fired[slot] = false
	var action: String = bindings.action_for(slot)
	if action != "none":
		Input.action_press(action)


func _on_up(slot: String) -> void:
	var action: String = bindings.action_for(slot)
	if action != "none":
		Input.action_release(action)
	_press_started.erase(slot)


func _process(_delta: float) -> void:
	# hold detection: long enough and we rebind instead of firing
	for slot in _press_started.keys():
		var held := (Time.get_ticks_msec() - int(_press_started[slot])) / 1000.0
		if held >= HOLD_TO_REBIND:
			var action: String = bindings.action_for(slot)
			if action != "none":
				Input.action_release(action)
			_press_started.erase(slot)
			_open_picker(slot)
			return


# ------------------------------------------------------------------ picker
func _open_picker(slot: String) -> void:
	_close_picker()
	_picker_for_slot = slot

	_picker = Control.new()
	_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_picker)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker.add_child(dim)

	var panel := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = COL_PANEL
	psb.border_color = COL_EDGE
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(10)
	psb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", psb)
	_picker.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var head := Label.new()
	head.text = "Tlačítko: %s" % bindings.label_for_slot(slot)
	head.add_theme_color_override("font_color", COL_TEXT)
	head.add_theme_font_size_override("font_size", 15)
	vbox.add_child(head)

	for action in ControlBindings.AVAILABLE:
		var ob := Button.new()
		ob.text = bindings.label_for_action(action)
		ob.focus_mode = Control.FOCUS_NONE
		ob.custom_minimum_size = Vector2(190, 38)
		var sb := StyleBoxFlat.new()
		sb.bg_color = COL_IDLE
		sb.border_color = COL_EDGE
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		for state in ["normal", "hover", "pressed", "focus"]:
			ob.add_theme_stylebox_override(state, sb)
		ob.add_theme_color_override("font_color", COL_TEXT)
		ob.pressed.connect(_on_pick.bind(action))
		vbox.add_child(ob)

	var rst := Button.new()
	rst.text = "Obnovit výchozí"
	rst.focus_mode = Control.FOCUS_NONE
	rst.custom_minimum_size = Vector2(190, 34)
	rst.add_theme_color_override("font_color", Color(0.75, 0.60, 0.45))
	rst.pressed.connect(_on_reset)
	vbox.add_child(rst)

	_picker.set_meta("panel", panel)
	_center_picker()


func _center_picker() -> void:
	if _picker == null or not _picker.has_meta("panel"):
		return
	var panel: Control = _picker.get_meta("panel")
	var vs := get_viewport().get_visible_rect().size
	panel.position = (vs - panel.size) * 0.5


func _on_pick(action: String) -> void:
	if _picker_for_slot != "":
		bindings.assign(_picker_for_slot, action)
		_apply_bindings()
	_close_picker()


func _on_reset() -> void:
	bindings.reset_to_defaults()
	_apply_bindings()
	_close_picker()


func _close_picker() -> void:
	if _picker != null:
		_picker.queue_free()
		_picker = null
	_picker_for_slot = ""


# ------------------------------------------------------------------ layout
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

	# right thumb: four buttons in a d-pad cross (up / down / left / right of a
	# shared centre), all the same size, like the face buttons on a gamepad.
	var d: float = m * 0.125                        # button diameter
	var r: float = m * 0.155                        # distance centre -> button centre
	var cx: float = vs.x - margin - r - d * 0.5     # cross centre
	var cy: float = vs.y - margin - r - d * 0.5
	var offsets := {
		"up": Vector2(0.0, -r),
		"down": Vector2(0.0, r),
		"left": Vector2(-r, 0.0),
		"right": Vector2(r, 0.0),
	}
	for slot in ControlBindings.SLOTS:
		var off: Vector2 = offsets[slot]
		_place(_buttons[slot], Vector2(cx, cy) + off - Vector2(d, d) * 0.5, d)

	debug_label.position = Vector2(margin, margin * 0.5)
	if _picker != null:
		_center_picker()


func _place(b: Button, pos: Vector2, size: float) -> void:
	b.custom_minimum_size = Vector2.ZERO
	b.size = Vector2(size, size)
	b.position = pos
	# if the engine still refuses the requested size, that is a real layout bug
	# and the control test will catch it - do not silently accept it here
	b.add_theme_font_size_override("font_size", int(max(10.0, size * 0.19)))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb: StyleBoxFlat = b.get_theme_stylebox(state)
		if sb is StyleBoxFlat:
			sb.set_corner_radius_all(int(size * 0.5))   # keep it a perfect circle as it resizes


func set_debug(text: String) -> void:
	if debug_label:
		debug_label.text = text
