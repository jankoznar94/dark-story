extends SceneTree
## DIAGNOSTIC: is the duplicate delivery caused by Godot's TOUCH->MOUSE emulation?
##
## probe_touch_double_tap.gd showed that one finger tap reaches the panels TWICE and
## the second pass UNDOES the first (tap a bag item -> picked up, then dropped again;
## drag onto a slot -> equipped, then unequipped). This file runs the same taps with
## `input_devices/pointing/emulate_mouse_from_touch` forced OFF at runtime and
## compares, which both confirms the mechanism and settles which fix is the right one.
##
## Run: DISPLAY=:0 godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##        --script res://tools/probe_input_event_trace.gd

const IB := preload("res://scripts/item_base.gd")
const Inv := preload("res://scripts/inventory_model.gd")
const Item := preload("res://scripts/item.gd")

var main: Node
var ui: Control
var model
var _seen: Array = []


func _init() -> void:
	call_deferred("_run")


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _send_touch(pressed: bool, at: Vector2) -> void:
	var ev := InputEventScreenTouch.new()
	ev.pressed = pressed
	ev.index = 0
	ev.position = at
	Input.parse_input_event(ev)


## Counts deliveries by observing what the WINDOW does with them: every state the
## player can see (a carried item, an equipped box) is recorded after each event.
## The panel's own `notify` toast fires once per handled tap, which is the cheap
## counter that made the duplicate visible in the first place.
func _tap_item_then_slot(emulate_mouse: bool) -> Dictionary:
	ProjectSettings.set_setting("input_devices/pointing/emulate_mouse_from_touch", emulate_mouse)
	model.clear()
	var cap = Item.new("cap", IB.Rarity.NORMAL, 5)
	model.add(cap)
	ui.layout_now()
	var i: int = model.placement_index_of(cap)
	var p: Dictionary = model.placements[i]
	var ir: Rect2 = ui.cell_rect(p["pos"], p["size"])
	var ic: Vector2 = ir.position + ir.size * 0.5
	var sr: Rect2 = ui._slot_rect(0)

	_seen = []
	_send_touch(true, ic)
	await process_frame
	_send_touch(false, ic)
	await process_frame
	var carried: bool = ui._held_item == cap
	_send_touch(true, sr.position + sr.size * 0.5)
	await process_frame
	_send_touch(false, sr.position + sr.size * 0.5)
	await process_frame
	var equipped: bool = model.equipped_at(0) == cap
	return {"carried": carried, "equipped": equipped, "toasts": _seen.size()}


func _run() -> void:
	await process_frame
	await process_frame
	ui = main.get_node("HUD/InventoryUI")
	model = Inv.new()
	ui.setup(model, load("res://scripts/hero_stats.gd").new(40))
	ui.set_open(true)
	ui.size = ui.get_viewport_rect().size
	ui.layout_now()
	ui.notify.connect(func(t: String) -> void:
		if t != "":
			_seen.append(t))

	var shipped = ProjectSettings.get_setting(
		"input_devices/pointing/emulate_mouse_from_touch", "unset")
	print("shipped emulate_mouse_from_touch = ", shipped)
	print("emulate_touch_from_mouse = ",
		ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", "unset"))
	print("")

	var a: Dictionary = await _tap_item_then_slot(true)
	print("emulate_mouse_from_touch = TRUE   tap item -> carried=%s | tap helm -> equipped=%s | toasts=%d"
		% [str(a["carried"]), str(a["equipped"]), a["toasts"]])

	var b: Dictionary = await _tap_item_then_slot(false)
	print("emulate_mouse_from_touch = FALSE  tap item -> carried=%s | tap helm -> equipped=%s | toasts=%d"
		% [str(b["carried"]), str(b["equipped"]), b["toasts"]])

	print("")
	print("(one tap = one toast. 2 toasts on ONE tap means the tap was delivered twice:)")
	print("EMULATION_IS_THE_CAUSE=%s" % str(
		not bool(a["carried"]) and bool(b["carried"])))
	quit()
