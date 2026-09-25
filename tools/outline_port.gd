extends SceneTree
class_name OutlinePort
## OutlinePort — dump the PORT's own Control tree with real geometry, to compare against
## `tools/import/outline_pwa.py`.
##
## Visual parity needs a number on both sides. The PWA side is measured in the live
## browser (`outline_pwa.py`, `getBoundingClientRect` + `getComputedStyle`); this is the
## matching measurement for the port, so "the chest grid starts 20px too low" is a fact
## rather than an impression from a screenshot.
##
##   godot4 --rendering-driver opengl3 --path . --script res://tools/outline_port.gd -- \
##       --screen chest --out /tmp/port_outline.txt
##
## `--screen shop --tab sell` presses the shop's own tab button first, and `--bag a,b,c`
## seeds the hero's inventory, so the BAG-rendering screens can be outlined with a real
## loadout instead of an empty list.
##
## A modal tab is `character@inventory|skills|stats`, the same vocabulary capture_screen
## uses.

var _main: Node = null
var _screen := ""
var _out := "/tmp/port_outline.txt"
var _tab := ""
var _bag := ""
var _frames := 0
var _started := false
var _lines: Array = []
var _last_sig := ""
var _stable := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--screen":
				_screen = args[i + 1]
			"--out":
				_out = args[i + 1]
			"--tab":
				_tab = args[i + 1]
			"--bag":
				_bag = args[i + 1]
		i += 2
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		if not _main._screens.has("town") or _main._nav_bar == null:
			return false
		_started = true
		if _bag != "":
			_main.state.data["hero"]["inventory"] = []
			for id in _bag.split(","):
				var clean := id.strip_edges()
				if clean != "":
					_main.state.data["hero"]["inventory"].append(clean)
			_main.state.data["hero"]["gold"] = 5000
		_entry()
		return false
	_frames += 1
	# Layout needs a couple of frames to settle: containers resolve their sizes on the
	# frame AFTER the children are added — and a screen whose content is REBUILT after the
	# entry (the shop's tab press calls `refresh()`, which frees every row and adds new
	# ones) needs its own wait on top. Waiting a fixed 12 frames from the entry dumped a
	# tree of nodes that had been freed and replaced, with every rect at 0: a measurement
	# that looks like \"the layout is broken\" and is really \"the tool read too early\".
	#
	# So wait for the tree to be STABLE and non-degenerate instead of counting frames: the
	# same signal, and it cannot be fooled by a screen that rebuilds itself.
	if _frames < 8:
		return false
	var sig := _signature()
	if sig == _last_sig:
		_stable += 1
	else:
		_stable = 0
		_last_sig = sig
	if _stable < 4 or _frames > 400:
		return false
	_dump()
	return true


## A cheap fingerprint of the laid-out tree: every visible Control's global rect, rounded.
## Two consecutive identical readings mean the layout has stopped moving.
func _signature() -> String:
	var parts: Array = []
	_collect_sig(_main._screens.get(_screen, null), parts, 0)
	return "|".join(parts)


func _collect_sig(node: Node, parts: Array, depth: int) -> void:
	if node == null or depth > 9:
		return
	for child in node.get_children():
		if not (child is Control):
			continue
		var c: Control = child
		if not c.visible:
			continue
		var r := c.get_global_rect()
		parts.append("%d:%d:%d:%d:%d" % [depth, int(r.position.x), int(r.position.y),
			int(r.size.x), int(r.size.y)])
		_collect_sig(c, parts, depth + 1)


func _entry() -> void:
	if _screen == "":
		_screen = "town"
	if _screen.begins_with("character"):
		var tab := "inventory"
		if _screen.contains("@"):
			tab = _screen.split("@")[1]
		_main.open_modal(tab)
		return
	if _screen == "arena":
		_main._on_stop_selected(0, 0)
	elif _screen == "result":
		pass
	else:
		_main.show_screen(_screen)
	_apply_tab()


## Press the screen's own tab button, so `--tab sell` measures the tab a PLAYER taps into.
func _apply_tab() -> void:
	if _tab == "":
		return
	var screen = _main._screens.get(_screen, null)
	if screen == null or not ("_tab_buttons" in screen):
		return
	var buttons: Array = screen._tab_buttons
	var index := 0 if _tab == "buy" else 1
	if index < buttons.size():
		buttons[index].emit_signal("pressed")


func _dump() -> void:
	var target: Control = null
	if _screen.begins_with("character"):
		target = _main._character_modal if _main.get("_character_modal") != null else null
		if target == null:
			for key in _main._screens:
				if str(key) == "character":
					target = _main._screens[key]
	else:
		target = _main._screens.get(_screen, null)
	if target == null:
		print("outline: no screen %s" % _screen)
		quit(1)
		return
	_walk(target, 0)
	var vp := root.get_visible_rect()
	var win := DisplayServer.window_get_size()
	var f := FileAccess.open(_out, FileAccess.WRITE)
	f.store_string("# viewport=%dx%d window=%dx%d screen=%s\n" % [
		int(vp.size.x), int(vp.size.y), win.x, win.y, _screen]
		+ "\n".join(_lines) + "\n")
	f.close()
	print("outline: %s (%d rows) viewport=%dx%d window=%dx%d" % [
		_out, _lines.size(), int(vp.size.x), int(vp.size.y), win.x, win.y])
	quit()


func _walk(node: Node, depth: int) -> void:
	if depth > 7:
		return
	for child in node.get_children():
		if not (child is Control):
			continue
		var c: Control = child
		if not c.visible or c.size.x < 0.5 or c.size.y < 0.5:
			continue
		var g := c.get_global_rect()
		var cls := c.get_class()
		var script_name := ""
		var scr: Variant = c.get_script()
		if scr != null:
			script_name = str(scr.get_global_name()) if scr.get_global_name() != "" else ""
		var txt := ""
		if c is Label:
			txt = (c as Label).text
		elif c is Button:
			txt = (c as Button).text
		if txt.length() > 44:
			txt = txt.substr(0, 44)
		var extra := ""
		if c is Label:
			extra = "fs=%d" % (c as Label).get_theme_font_size("font_size")
		elif c is Button:
			extra = "fs=%d" % (c as Button).get_theme_font_size("font_size")
		_lines.append("%s%s%s [%d,%d %dx%d] min=%dx%d %s%s" % [
			"  ".repeat(depth), c.name, ("/" + script_name) if script_name != "" else "",
			int(g.position.x), int(g.position.y), int(c.size.x), int(c.size.y),
			int(c.get_combined_minimum_size().x), int(c.get_combined_minimum_size().y),
			extra, (" \"" + txt + "\"") if txt != "" else ""])
		_walk(child, depth + 1)
