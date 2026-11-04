extends SceneTree
## probe_overlay_chain.gd — why the item-info overlay lands in the top-left corner.
##
## Prints the SIZES down the chain `root -> main -> character modal -> inventory
## overlay`, because the overlay's `_layout()` returns early on a zero-width rect and
## leaves the panel at its default offsets (top-left). Which node is zero is the whole
## question, and a screenshot cannot answer it.
##
##   godot4 --path . --rendering-driver opengl3 --script res://tools/probe_overlay_chain.gd

var _main: Node = null
var _frames := 0
var _step := 0


func _initialize() -> void:
	root.size = Vector2i(390, 844)
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _main == null or _main._nav_bar == null:
		return false
	_frames += 1
	if _frames < 3:
		return false
	if _step == 0:
		_step = 1
		_main.open_modal("inventory")
		return false
	if _step == 1:
		_step = 2
		_main._screens["character"]._inventory._item_overlay.visible = true
		return false
	if _step == 2:
		_report()
		quit()
	return false


func _report() -> void:
	var overlay = _main._screens["character"]._inventory._item_overlay
	var chain: Array = []
	var n: Node = overlay
	while n != null:
		if n is Control:
			var c := n as Control
			chain.append("%s size=%s pos=%s anchors=%.2f,%.2f,%.2f,%.2f offsets=%.1f,%.1f,%.1f,%.1f" % [
				c.name, str(c.size), str(c.position),
				c.anchor_left, c.anchor_top, c.anchor_right, c.anchor_bottom,
				c.offset_left, c.offset_top, c.offset_right, c.offset_bottom])
		n = n.get_parent()
	for line in chain:
		print("CHAIN ", line)
	print("OVERLAY_VIEWPORT=%s" % str(overlay.get_viewport_rect().size))
	print("PROBE_OVERLAY_CHAIN_DONE=true")
