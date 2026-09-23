extends SceneTree
## probe_cancel.gd — which synthetic event actually CANCELS a button's press?
##
## Measured in `probe_tap_drag.gd`: a drag that stays inside a button leaves `pressing_inside`
## set, so the button fires. A synthetic release alone does not cancel it — Godot's
## `BaseButton` emits `pressed` on release whenever `pressing_inside` is still true, whatever
## the release's position. `pressing_inside` is only cleared by the mouse LEAVING the control.
##
## So this probe compares the candidate sequences against a real button in the real pipeline
## and prints, for each, whether the button fired. Nothing here is a test — it is the
## measurement the fix is chosen from.

const VARIANTS := [
	"release away only",
	"motion away (mask LEFT) then release away",
	"motion away (mask 0) then release away",
]


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	for variant in VARIANTS:
		_run_one(variant)
	quit(0)


func _run_one(variant: String) -> void:
	var vp := root
	vp.size = Vector2i(390, 844)

	var host := Control.new()
	host.size = Vector2(390, 844)
	vp.add_child(host)

	var button := Button.new()
	button.text = "TILE"
	button.position = Vector2(20, 100)
	button.size = Vector2(200, 300)
	host.add_child(button)
	var hits := {"n": 0}
	button.pressed.connect(func(): hits["n"] = int(hits["n"]) + 1)

	var away := Vector2(-1000, -1000)
	# Press in the middle of the tile.
	_click(vp, Vector2(120, 240), true)
	# A tiny drag that stays inside the tile — the case that fires the button.
	_motion(vp, Vector2(120, 234), Vector2(0, -6), MOUSE_BUTTON_MASK_LEFT)
	var fired_before := int(hits["n"])
	var pressed_before := button.is_pressed()

	match variant:
		"release away only":
			_click(vp, away, false)
		"motion away (mask LEFT) then release away":
			_motion(vp, away, away, MOUSE_BUTTON_MASK_LEFT)
			_click(vp, away, false)
		"motion away (mask 0) then release away":
			_motion(vp, away, away, 0)
			_click(vp, away, false)

	print("%-46s fired before=%d/%s  after=%d pressed_after=%s"
		% [variant, fired_before, str(pressed_before), int(hits["n"]),
			str(button.is_pressed())])
	host.queue_free()


func _click(vp: Viewport, pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	vp.push_input(e)


func _motion(vp: Viewport, pos: Vector2, rel: Vector2, mask: int) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.button_mask = mask
	vp.push_input(e)
