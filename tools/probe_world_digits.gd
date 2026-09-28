extends SceneTree
## tools/probe_world_digits.gd — READ the digits the road actually draws.
##
## Jan's report: "Všechny souboje má cestě (puntíky) mají číslo 0." The three candidate causes
## are all invisible to a screenshot-free eye, so this probe asks the FONT and the DRAWING
## rather than the layout:
##
##   1. does the bundled DejaVu Sans really have the glyphs '0'..'9'? (a face missing them
##      returns zero-size advances and draws nothing — or the .notdef box)
##   2. what rect does the glyph '0' get from `centered_pen`?
##   3. what string does `_draw_node` hand to the font for each state? (read off the real
##      screen, not from the source)
##
## Run: godot --headless --path . --script res://tools/probe_world_digits.gd

const Main := preload("res://scripts/main.gd")
const UIFonts := preload("res://scripts/ui/ui_fonts.gd")

var _main: Node = null
var _started := false


func _initialize() -> void:
	_main = Main.new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		if _main._nav_bar == null or _main.state == null:
			return false
		_started = true
		_run()
		return false
	return false


func _run() -> void:
	var w: Control = _main._screens["world"]

	print("=== the bundled font (size 14, the road's digits)")
	var font: Font = UIFonts.get_font(14)
	var file: FontFile = UIFonts.regular()
	print("font class=%s" % font.get_class())
	for text in ["0", "1", "5", "9", "10"]:
		var sz: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		print("  '%s' advance=%s" % [text, str(sz)])
	for code in range(48, 58):
		var c := 0
		if file != null:
			c = 1 if file.has_char(code) else 0
		print("  FontFile.has_char('%s')=%d" % [char(code), c])

	print("=== what each node state draws")
	_main.state.data["_currentAct"] = 0
	_main.state.data["locationProgress"][0] = 0
	for fight in [0, 1, 4]:
		_main.state.data["areaFightProgress"][0] = fight
		_main.show_world(0)
		var header: String = w._header_fight.text
		var marks := PackedStringArray()
		for i in w._total_fights():
			marks.append(str(_mark(w, i)))
		print("  areaFightProgress=%d header='%s' marks=%s" % [fight, header, " ".join(marks)])

	_main.state.data["areaFightProgress"][0] = 0
	_main.show_world(0)
	print("=== the pen for the current node")
	var p: Vector2 = w.node_pos(0)
	for text in ["0", "1", "10"]:
		print("  centered_pen('%s', %s) = %s" % [text, str(p), str(w.centered_pen(text, p, font, 14))])
	quit(0)


## Re-derive the MARK `_draw_node` shows for node `index`, from the screen's own state. Mirrors
## the branches in the file, and the probe prints it so the probe and the code can be compared
## by eye.
func _mark(w: Control, index: int) -> String:
	var fight := int(w._current_fight())
	var is_next := index == fight + 1 and int(w._tap_index) >= 0
	if index < fight:
		return "tick"
	if index > fight and not is_next:
		return "lock"
	return "digit:%d" % fight
