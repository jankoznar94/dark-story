extends SceneTree
## tools/probe_compare_swipe_gui.gd — does a REAL event reach the compare window's swipe?
##
## `tools/test_compare_swipe.gd` drives `ItemInfoOverlay._on_panel_input()` DIRECTLY, so it
## proves the arithmetic and nothing about the path a finger takes. The port has shipped this
## shape before (a tap test that bypasses the viewport hit test): the handler is right, the
## gesture never arrives.
##
## This probe builds the REAL modal — the character dialog with its scrolling body and its
## `ScrollSwipe`, the inventory inside it and the item detail mounted on the dialog root — and
## pushes events through `Input.parse_input_event`, which is the only route that reproduces
## what a phone delivers (touch + its emulated mouse half). Events are QUEUED by that call and
## delivered on the next frame, so every step below is separated by real frames; printing right
## after the call reads an empty log and a screen that has not acted yet.
##
## Run (needs a real window, headless routes no GUI input):
##   DISPLAY=:0 godot4 --path . --rendering-driver opengl3 --script res://tools/probe_compare_swipe_gui.gd

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const CharacterModal := preload("res://scripts/ui/character_modal.gd")

const BAG_SIZE := 20
const SWIPE := 90.0
const SETTLE := 4

var _data: Node
var _gen: ItemGen
var _state
var _modal
var _overlay
var _seen: Array = []
var _frames := 0
var _steps: Array = []
var _wait := 0
var _centre := Vector2.ZERO


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_state = GameState.new()
	_state.bind_data(_data)
	_state.set_class("barbarian")
	var bag: Array = []
	for i in BAG_SIZE:
		bag.append(null)
	var ids := ["armor_leather", "helm_cap", "copperRing", "boots_boots"]
	var at := [0, 5, 9, 13]
	var placed := 0
	for id in ids:
		if _data.item(str(id)).is_empty():
			continue
		bag[at[placed]] = {"id": str(id), "count": 1}
		placed += 1
	_state.data["hero"]["inventory"] = bag
	print("probe window=%s root=%s" % [DisplayServer.get_name(), str(root.size)])
	_modal = CharacterModal.new(_data, _gen, _state, func(id): return _resolve(str(id)))
	root.add_child(_modal)
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.visible = true


func _resolve(id: String) -> Dictionary:
	var loot: Dictionary = _state.loot_item(id)
	if not loot.is_empty():
		return loot
	return _data.item(id)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 12:
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _steps.is_empty():
		if _overlay == null:
			_modal.set_tab("inventory")
			_modal.refresh()
			_wait = 6
			_setup_steps()
			return false
		print("PROBE_END")
		quit(0)
		return false
	var step: Callable = _steps.pop_front()
	step.call()
	_wait = SETTLE
	return false


func _setup_steps() -> void:
	_steps = [
		func(): _modal.inventory()._on_bag_tapped(0),
		func(): _attach_and_report(),
		func(): _swipe_begin(0.0),
		func(): _swipe_move(0.0),
		func(): _swipe_end(0.0),
		func(): _report("horizontal"),
		func(): _swipe_begin(31.0),
		func(): _swipe_move(31.0),
		func(): _swipe_end(31.0),
		func(): _report("diagonal 31px"),
	]


func _attach_and_report() -> void:
	_overlay = _modal.inventory()._item_overlay
	var rect: Rect2 = _overlay._panel.get_global_rect()
	_centre = rect.get_center()
	print("overlay visible=%s viewport=%s" % [str(_overlay.visible), str(root.size)])
	print("panel rect=%s centre=%s" % [str(rect), str(_centre)])
	print("item before=%s index=%d" % [_overlay.current_item_id(), _overlay.origin_index()])
	_overlay._panel.gui_input.connect(_count)
	_overlay.navigate.connect(func(d): print("NAVIGATE dir=%d" % d))
	print("panel handlers=%d scroll_rect=%s" % [
		_overlay._panel.gui_input.get_connections().size(),
		str(_modal._scroll.get_global_rect())])


func _count(event: InputEvent) -> void:
	var press := "-"
	if event is InputEventScreenTouch:
		press = str((event as InputEventScreenTouch).pressed)
	elif event is InputEventMouseButton:
		press = str((event as InputEventMouseButton).pressed)
	_seen.append("%s(%s) press_pos=%s pressing=%s" % [event.get_class(), press,
		str(_overlay._press_pos), str(_overlay._pressing)])


func _swipe_begin(_dy: float) -> void:
	_seen.clear()
	_centre = _overlay._panel.get_global_rect().get_center()
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = _centre
	Input.parse_input_event(press)


func _swipe_move(dy: float) -> void:
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = _centre + Vector2(-SWIPE, dy)
	drag.relative = Vector2(-SWIPE, dy)
	Input.parse_input_event(drag)


func _swipe_end(dy: float) -> void:
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.pressed = false
	release.position = _centre + Vector2(-SWIPE, dy)
	Input.parse_input_event(release)


func _report(label: String) -> void:
	print("--- %s ---" % label)
	print("visible=%s panel=%s centre=%s" % [str(_overlay.visible),
		str(_overlay._panel.get_global_rect()), str(_centre)])
	print("pressing=%s from_touch=%s" % [str(_overlay._pressing), str(_overlay._press_from_touch)])
	print("panel received %d: %s" % [_seen.size(), " | ".join(_seen)])
	print("index=%d item=%s" % [int(_overlay.origin_index()), _overlay.current_item_id()])
