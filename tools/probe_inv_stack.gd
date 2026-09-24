extends SceneTree
## probe_inv_stack.gd — the PORT's whole vertical stack inside the character modal, one
## line per block, from the dialog's top edge down to the bag's last cell. Printed as
## `KEY=[x, y, w, h]` so it can be diffed against the PWA's own numbers.
##
##   godot4 --path . --rendering-driver opengl3 --script res://tools/probe_inv_stack.gd
##
## The point is to find WHERE a drift of 4px enters, not to restate that one exists: the
## doll is 4px high and everything below it is 8px high, so there are two separate gaps
## to account for and a single "the pane is off" reading cannot tell them apart.

var _main: Node = null
var _frames := 0
var _step := 0


func _initialize() -> void:
	root.size = Vector2i(390, 844)
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _r(node: Control) -> String:
	var g := node.get_global_rect()
	return "[%.1f, %.1f, %.1f, %.1f]" % [g.position.x, g.position.y, g.size.x, g.size.y]


func _p(key: String, node: Control) -> void:
	print("%s=%s  min=%s" % [key, _r(node), str(node.get_combined_minimum_size())])


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
		return false
	if _step != 2:
		return false
	_step = 3

	var modal = _main._screens["character"]
	var inv = modal._inventory
	_p("MODAL_CONTENT", modal._panel)
	_p("TABS_STRIP", modal._tabs_wrap)
	var row: Control = modal._tabs_wrap.get_child(0) as Control
	_p("TABS_ROW", row)
	for i in row.get_child_count():
		var b := row.get_child(i) as Control
		_p("TAB_%d" % i, b)
	_p("PANE", modal._panes["inventory"])
	_p("INV_ROOT", inv)
	_p("POTION_ROW", inv._potion_row)
	if inv._bag_nodes.size() > 0:
		_p("CELL0", inv._bag_nodes[0] as Control)
	# every doll slot, in visual order
	var order := ["helmet", "amulet", "townPortal", "weapon", "armor", "shield",
		"ring1", "belt", "ring2", "gloves", "boots"]
	for slot in order:
		if inv._slot_nodes.has(slot):
			_p("SLOT_" + slot.to_upper(), inv._slot_nodes[slot] as Control)
	# the box the doll grid puts around its slots
	var any_slot: Control = inv._slot_nodes["helmet"]
	_p("DOLL_GRID", any_slot.get_parent())
	_p("DOLL_WRAP", any_slot.get_parent().get_parent())
	_p("BAG_WRAP", (inv._bag_nodes[0] as Control).get_parent().get_parent())
	_p("BAG_GRID", inv._bag_nodes[0].get_parent())
	print("INV_STACK_DONE=true")
	quit()
	return false
