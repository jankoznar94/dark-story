extends Control
class_name ConfirmModal
## ConfirmModal — a flat, two-button confirmation dialog, and the one-line "hotovo" message.
##
## It exists because the trash entry in the nav bar wiped a whole run in ONE tap with no way
## back (and, before that, with a second "tap again" that Jan never saw: he tapped once, the
## numbers were still there, and the report was "nefunguje"). Jan's rule for every dialog in
## this port is a MODAL, not a strip of text: he has to SEE that something happened.
##
## Styling is the PWA's own `#gemSelectModal` box, which is the only confirm-style dialog the
## reference has:
##
##   dim        fixed inset:0; background:rgba(0,0,0,0.8)
##   panel      background:#000; border:1px solid #444; radius 12; padding 20
##              max-width:340px; width:90%
##   title      18px bold #ddd
##   body       13px #aaa
##
## No hover, no focus ring (Jan's mobile rule): a button's own `pressed` face is the only
## feedback. The destructive button is filled `#c0392b` so it never looks like the safe one.

const UIKit := preload("res://scripts/ui/ui_kit.gd")

## The player confirmed (the destructive button).
signal confirmed
## The player backed out — the dim, the X-less cancel button, or a tap outside the panel.
signal dismissed

const MAX_WIDTH := 340.0
const PAD := 20.0
const RADIUS := 12
const BTN_HEIGHT := 44.0
## A tap that OPENS this dialog arrives in the same gesture as the finger going down on the
## nav entry. Anything inside this window is that same finger, not an answer.
const OPEN_GUARD_MS := 320

var _dim: ColorRect
var _panel: PanelContainer
var _title: Label
var _body: Label
var _ok: Button
var _cancel: Button
var _opened_at := 0
var _mode := "ask"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false


func _build() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.0, 0.0, 0.0, 0.8)
	# STOP, so a tap meant for the game underneath cannot land on it.
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(_on_dim_input)
	add_child(_dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(MAX_WIDTH, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#000000")
	style.border_color = Color("#444444")
	style.set_border_width_all(1)
	style.set_corner_radius_all(RADIUS)
	style.set_content_margin_all(PAD)
	_panel.add_theme_stylebox_override("panel", style)
	centre.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)

	_title = UIKit.label("", 18, "#dddddd", HORIZONTAL_ALIGNMENT_CENTER, true)
	box.add_child(_title)

	_body = UIKit.label("", 13, "#aaaaaa", HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_body)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	_cancel = UIKit.secondary_button("Zrušit", BTN_HEIGHT)
	_cancel.add_theme_font_size_override("font_size", 15)
	_cancel.pressed.connect(_on_cancel_pressed)
	row.add_child(_cancel)

	_ok = UIKit.flat_button("Smazat", 0.0, BTN_HEIGHT, 15, "#c0392b", "#c0392b")
	_ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ok.add_theme_color_override("font_color", Color("#ffffff"))
	_ok.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	_ok.pressed.connect(_on_ok_pressed)
	row.add_child(_ok)


## Ask a question with two answers. `on_confirm` runs only on the destructive button.
func ask(title: String, body: String, ok_text := "Smazat", cancel_text := "Zrušit") -> void:
	_mode = "ask"
	_title.text = title
	_body.text = body
	_ok.text = ok_text
	_cancel.text = cancel_text
	_open(true)


## A one-button "this is what happened" message.
func tell(title: String, body: String, ok_text := "Rozumím") -> void:
	_mode = "tell"
	_title.text = title
	_body.text = body
	_ok.text = ok_text
	_open(false)


## Read-only handles for the headless suite: the dialog is asserted from outside by its text
## and by its real buttons (tapped at their own rects), never by its private fields.
func title_text() -> String:
	return _title.text


func body_text() -> String:
	return _body.text


func ok_button() -> Button:
	return _ok


func cancel_button() -> Button:
	return _cancel


func close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _open(with_cancel: bool) -> void:
	_cancel.visible = with_cancel
	# A destructive red is for the button that DELETES. The one-button message only says
	# "understood", and a red one there reads as "this will delete something too".
	_paint_ok(with_cancel)
	_opened_at = Time.get_ticks_msec()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	move_to_front()


func _guarded() -> bool:
	return Time.get_ticks_msec() - _opened_at < OPEN_GUARD_MS


## `UIKit.flat_button` bakes one style into every state, so swapping the fill means replacing
## those boxes — there is no hover/focus difference to preserve (Jan's mobile rule).
func _paint_ok(destructive: bool) -> void:
	var fill := "#c0392b" if destructive else UIKit.BORDER
	var style := StyleBoxFlat.new()
	style.bg_color = Color(fill)
	style.border_color = Color(fill)
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	for state_name in ["normal", "hover", "focus", "disabled", "pressed"]:
		_ok.add_theme_stylebox_override(state_name, style)
	_ok.add_theme_color_override("font_color", Color("#ffffff" if destructive else UIKit.TEXT))
	_ok.add_theme_color_override("font_pressed_color", Color("#ffffff"))
	_ok.add_theme_color_override("font_hover_color", Color("#ffffff" if destructive else UIKit.TEXT))


func _on_dim_input(event: InputEvent) -> void:
	if _guarded():
		return
	var pressed := false
	if event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	if not pressed:
		return
	if _mode == "ask":
		close()
		dismissed.emit()


func _on_ok_pressed() -> void:
	if _guarded():
		return
	var was_tell := _mode == "tell"
	close()
	# A one-button message has nothing to confirm: pressing its button DISMISSES it. Emitting
	# `confirmed` there ran the caller's destructive action a second time (the wipe reopened
	# its own "hotovo" dialog forever).
	if was_tell:
		dismissed.emit()
	else:
		confirmed.emit()


func _on_cancel_pressed() -> void:
	if _guarded():
		return
	close()
	dismissed.emit()
