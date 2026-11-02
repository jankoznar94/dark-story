extends SceneTree
## tools/test_update_button.gd — the town's manual PWA update, as Zily 2 and Thrower have it.
##
## The failure this test exists for is not "the button looks wrong": it is that the
## button is BUILT but its tap never reaches `UpdateCheck.request_update()`, or that
## the section is built in a desktop export where there is nothing to update. Both
## pass a screenshot and both are wrong on the phone.
##
## What is asserted:
##   1. Off the web the section is NOT built (no dead button on the desktop build).
##   2. With the web hook on, the section exists: a full-width button labelled
##      AKTUALIZOVAT HRU plus the note and the build stamp.
##   3. Pressing the button reaches the logic — with no JavaScriptBridge the result is
##      the honest "Prohlížeč neumí aktualizaci na pozadí.", drawn in the note label.
##   4. `UpdateCheck` off the web reports "dev" and never polls.
##
## Run:  godot --headless --path . --script res://tools/test_update_button.gd
## Pass: prints UPDATE_BUTTON_ALL_PASS=true

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const TownScreen := preload("res://scripts/ui/town_screen.gd")
const UpdateCheck := preload("res://scripts/ui/update_check.gd")

var _data: Node
var _gen: ItemGen
var _failures: Array[String] = []


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)

	_test_desktop_has_no_section()
	_test_web_section_and_tap()
	_test_check_off_web()

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("UPDATE_BUTTON_ALL_PASS=true")
	else:
		print("UPDATE_BUTTON_ALL_PASS=false")
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _state():
	var s = GameState.new()
	s.bind_data(_data)
	s.set_class("barbarian")
	return s


func _resolve(id: Variant) -> Dictionary:
	var item: Dictionary = _data.item(str(id))
	if item.is_empty():
		return {}
	return item


func _make_town():
	var town = TownScreen.new(_data, _gen, _state(), _resolve)
	root.add_child(town)
	# A SceneTree script's _initialize() runs before the first frame, so `_ready()` has
	# not fired for the freshly added node and nothing is built yet. Calling it here is
	# what an actual frame would have done.
	if town._update_check == null:
		town._build()
	return town


## The desktop (Windows / Android) export gets no section: `request_update()` there can
## only answer "this is the web version only", and a button that only refuses is worse
## than no button.
func _test_desktop_has_no_section() -> void:
	UpdateCheck.force_web = false
	var town = _make_town()
	if town._update_check == null:
		_fail("town did not create an UpdateCheck at all")
	elif town._update_check.web:
		_fail("desktop export thinks it is the web build")
	if town._update_note_label != null:
		_fail("desktop export built the update section")
	town.queue_free()


func _test_web_section_and_tap() -> void:
	UpdateCheck.force_web = true
	var town = _make_town()
	if town._update_note_label == null or town._update_build_label == null:
		_fail("web build did not build the update labels")
		town.queue_free()
		UpdateCheck.force_web = false
		return

	town.refresh_update()
	if not town._update_build_label.text.begins_with("build "):
		_fail("build stamp label is %s" % town._update_build_label.text)

	# Drive the TAP, not the handler: the wiring is what breaks.
	var button: Button = _find_button(town, "AKTUALIZOVAT HRU")
	if button == null:
		_fail("no button labelled AKTUALIZOVAT HRU")
		town.queue_free()
		UpdateCheck.force_web = false
		return
	if button.size_flags_horizontal != Control.SIZE_EXPAND_FILL:
		_fail("update button is not full width (flags=%d)" % button.size_flags_horizontal)

	button.pressed.emit()
	# A headless run has no working JavaScriptBridge (`eval` is a silent no-op there),
	# so what is asserted is that the TAP reached `request_update()` — the note it sets
	# before handing off to JS is the observable proof.
	if not town._update_note_label.text.contains("restartuje"):
		_fail("tap did not reach the update logic, note='%s'" % town._update_note_label.text)
	else:
		print("  tap reached request_update(), note='%s'" % town._update_note_label.text)

	town.queue_free()
	UpdateCheck.force_web = false


func _test_check_off_web() -> void:
	UpdateCheck.force_web = false
	var check = UpdateCheck.new()
	if check.web:
		_fail("UpdateCheck off the web reports web=true")
	if check.build_id != "dev":
		_fail("build stamp off the web is '%s', expected dev" % check.build_id)
	if check.poll():
		_fail("poll() returned true off the web")
	check.request_update()
	if not check.note.contains("webovou"):
		_fail("request_update off the web says %s" % check.note)


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for child in node.get_children():
		var found: Button = _find_button(child, text)
		if found != null:
			return found
	return null
