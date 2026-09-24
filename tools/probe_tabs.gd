extends SceneTree
## probe_tabs.gd — the character modal's TAB STRIP, in the port's own numbers.
##
## The strip is the first band in every inventory diff and it was never measured in the
## port: the PWA's live numbers are `.combined-tab` 101x32 at x=21/126/232, y=59 and
## `.modal-close` 32x32 at x=337, all inside `.modal-content` at (4, 46, 382x752).
##
##   godot4 --path . --rendering-driver opengl3 --script res://tools/probe_tabs.gd

var _frames := 0
var _started := false


func _initialize() -> void:
	root.size = Vector2i(390, 844)
	root.add_child(load("res://scripts/main.gd").new())


func _process(_delta: float) -> bool:
	var main = _main()
	if main == null or main._nav_bar == null:
		return false
	if not _started:
		_started = true
		main.open_modal("inventory")
		return false
	_frames += 1
	if _frames < 4:
		return false
	var modal = main._screens["character"]
	print("modal panel rect = ", modal._panel.get_global_rect())
	print("tab strip rect   = ", modal._tabs_wrap.get_global_rect())
	for child in modal._tabs_wrap.get_children():
		var row := child as Control
		if row == null:
			continue
		for b in row.get_children():
			var ctrl := b as Control
			if ctrl == null:
				continue
			var label := ""
			if ctrl is Button:
				label = (ctrl as Button).text
			print("  %s '%s' rect=%s min=%s" % [ctrl.get_class(), label,
				str(ctrl.get_global_rect()), str(ctrl.get_combined_minimum_size())])
	var inv_pane: Control = modal._panes["inventory"]
	print("inventory pane rect = ", inv_pane.get_global_rect())
	var inner = modal.inventory()
	print("  inventory screen rect = ", inner.get_global_rect())
	# The three blocks and their own contents, so a block that is 6px tall can be aimed at.
	var inline: Control = inner.get_child(0)
	for i in inline.get_child_count():
		var block: Control = inline.get_child(i)
		print("BLOCK %d rect=%s" % [i, str(block.get_global_rect())])
		_report(block, 1)
	quit()
	return true


func _report(node: Node, depth: int) -> void:
	for child in node.get_children():
		var ctrl := child as Control
		if ctrl == null:
			continue
		print("%s%s rect=%s min=%s" % ["  ".repeat(depth), ctrl.get_class(),
			str(ctrl.get_global_rect()), str(ctrl.get_combined_minimum_size())])
		if depth < 3:
			_report(ctrl, depth + 1)


func _main() -> Node:
	for c in root.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("main.gd"):
			return c
	return null
