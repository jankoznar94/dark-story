extends SceneTree
## Print every control the SHOP actually put on screen for one card: rect, visible flag,
## and where a tap at the button's own centre lands.
##
##   godot4 --rendering-driver opengl3 --path . --script res://tools/probe_shop_buttons.gd
##
## Jan's report was "the Buy and Sell buttons are not in the shop at all". A screenshot
## cannot say why a Button is missing: it can be laid out at zero size, laid out off the
## canvas, hidden behind a sibling, or never added. This prints the rect AND the hit test.

var _main: Node = null
var _started := false
var _frames := 0
var _stage := 0
var _buy_buttons: Array = []
var _tapped := false


func _initialize() -> void:
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		if not _main._screens.has("town") or _main._nav_bar == null:
			return false
		_started = true
		# Give the hero money and something in the bag, so BOTH tabs have cards.
		var state = _main.state
		state.data["hero"]["gold"] = 5000
		state.data["hero"]["inventory"] = ["helm_helm", "armor_leather"]
		_main.show_screen("shop")
		_main._screens["shop"].refresh()
		return false

	_frames += 1
	if _stage == 0:
		if _frames < 4:
			return false
		_stage = 1
		_dump("BUY", _main._screens["shop"]._list)
		return false

	if _stage == 1:
		# Tap the FIRST buy button at its own centre through the real input pipeline.
		if not _tapped:
			_tapped = true
			var b: Button = _buy_buttons[0] if not _buy_buttons.is_empty() else null
			if b == null:
				print("PROBE: no buy button to tap")
				quit()
				return true
			var gold_before: int = int(_main.state.hero().get("gold", 0))
			var centre := b.get_global_rect().get_center()
			print("PROBE: tapping at %s (rect %s)" % [str(centre), str(b.get_global_rect())])
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_LEFT
			press.pressed = true
			press.position = centre
			root.push_input(press)
			var release := InputEventMouseButton.new()
			release.button_index = MOUSE_BUTTON_LEFT
			release.pressed = false
			release.position = centre
			root.push_input(release)
			print("PROBE: gold %d -> %d after tapping the first Buy button"
				% [gold_before, int(_main.state.hero().get("gold", 0))])
		# Second card: the SELL tab.
		_main._screens["shop"]._tab_buttons[1].emit_signal("pressed")
		_main._screens["shop"].refresh()
		_stage = 2
		return false

	if _frames < 12:
		return false
	_dump("SELL", _main._screens["shop"]._list)
	quit()
	return true


func _dump(label: String, list: Node) -> void:
	print("--- %s: list rect=%s children=%d" % [label, str(list.get_global_rect()),
		list.get_child_count()])
	_buy_buttons = []
	_walk(list, 0)


func _walk(node: Node, depth: int) -> void:
	for child in node.get_children():
		var pad := "  ".repeat(depth)
		if child is Control:
			var c: Control = child
			var line := "%s%s %s rect=%s visible=%s min=%s" % [pad, c.get_class(),
				(c.name if c.name != "" else "<unnamed>"), str(c.get_global_rect()),
				str(c.visible), str(c.get_combined_minimum_size())]
			if c is Button:
				line += " mouse_filter=%d" % c.mouse_filter
				_buy_buttons.append(c)
			print(line)
		if depth < 6:
			_walk(child, depth + 1)
