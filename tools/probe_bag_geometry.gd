extends SceneTree
## probe_bag_geometry.gd — the PORT's own boxes around the bag, in the shape
## `shoot_both_inventory.py` prints for the PWA, so the two sides can be compared rect by
## rect instead of by a diff percentage that cannot say WHICH box moved.
##
## The three candidates when a cell is a few px off: the cell, the `#invGrid`, or
## `#invGridWrap` — plus the belt row, because the bag's top edge is one collapsed margin
## below the belt's bottom edge.
##
##   godot4 --path . --rendering-driver opengl3 --script res://tools/probe_bag_geometry.gd
##
## Prints `KEY=value` lines (upper-case keys) so the caller can parse them.

var _main: Node = null
var _frames := 0
var _step := 0


func _initialize() -> void:
	root.size = Vector2i(390, 844)
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _bag_grid_sep(inv) -> int:
	return int((inv._bag_grid as GridContainer).get_theme_constant("v_separation"))


func _rect(node: Control) -> String:
	var r := node.get_global_rect()
	return "[%.1f, %.1f, %.1f, %.1f]" % [r.position.x, r.position.y, r.size.x, r.size.y]


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

	var inv = _main._screens["character"]._inventory
	var grid: Control = inv._bag_grid
	var wrap: Control = grid.get_parent()
	var panel: Control = wrap.get_parent()
	# `.inv-equip-panel` is the pane column's FIRST block; the PWA measures it as
	# [12.9, 110.2, 364.2, 326], one collapsed 12px margin under the body. The chain down
	# from the pane is inline-VBox -> _Margined -> panel-VBox -> PanelContainer -> GridContainer,
	# so the blocks are read off the INLINE box and never off a bag block's ancestor.
	var inline: Control = inv.get_child(0)
	var equip_block: Control = inline.get_child(0) as Control
	# the doll grid itself, for its width and x (the PWA centres a 237px grid)
	var equip_grid: Control = (equip_block as Control).get_child(0).get_child(0) as Control
	var potion_block: Control = inline.get_child(1) as Control
	var bag_block: Control = inline.get_child(2) as Control

	# The chain ABOVE the bag, so a block that is a few px off can be attributed to a box
	# instead of guessed at: `.modal-content` -> `.combined-tabs` -> the body -> the pane's
	# own padding box -> `.inv-equip-panel`. The PWA's own numbers for the same six nodes
	# come out of `shoot_both_inventory.py`, so the two sides are comparable rect by rect.
	var modal = _main._screens["character"]
	print("MODAL_PANEL=%s" % _rect(modal._panel as Control))
	print("TABS=%s" % _rect(modal._tabs_wrap as Control))
	print("BODY_SCROLL=%s" % _rect(modal._scroll as Control))
	var pane_margin: Control = modal._panes["inventory"]
	print("PANE_MARGIN=%s" % _rect(pane_margin))
	print("INV_SCREEN=%s" % _rect(inv))
	print("EQUIP_PANEL=%s" % _rect(equip_block))
	print("POTION_BLOCK=%s" % _rect(potion_block))
	print("BAG_BLOCK=%s" % _rect(bag_block))
	print("TAB0=%s" % _rect(modal._tab_buttons["inventory"] as Control))
	print("TAB_COUNT=%d" % modal._tab_buttons.size())
	print("EQUIP_GRID=%s" % _rect(equip_grid))
	# EVERY doll slot, in the PWA's own id order, so the two sides compare rect by rect.
	for _slot in ["weapon", "armor", "helmet", "shield", "gloves", "boots", "belt",
			"ring1", "ring2", "amulet", "townPortal"]:
		if inv._slot_nodes.has(_slot):
			print("SLOT_%s=%s" % [_slot.to_upper(), _rect(inv._slot_nodes[_slot] as Control)])
	print("DOLL_SLOT_NODES=%d" % inv._slot_nodes.size())
	print("DOLL=%s" % _rect(inv._slot_nodes["weapon"] as Control))
	print("POTION_WRAP=%s" % _rect(inv._potion_row))
	print("POTION_COUNT=%d" % inv._potion_row.get_child_count())
	print("POTION_FIRST=%s" % _rect(inv._potion_row.get_child(0) as Control))
	print("WRAP=%s" % _rect(wrap))
	print("GRID=%s" % _rect(grid))
	var cells: Array = inv._bag_nodes
	print("CELL_COUNT=%d" % cells.size())
	if cells.size() > 0:
		print("CELL0=%s" % _rect(cells[0] as Control))
	if cells.size() > 1:
		print("CELL1=%s" % _rect(cells[1] as Control))
	if cells.size() > 4:
		print("CELL4=%s" % _rect(cells[4] as Control))
	if cells.size() > 5:
		print("CELL5=%s" % _rect(cells[5] as Control))
	if cells.size() > 19:
		print("CELL19=%s" % _rect(cells[19] as Control))
	# every cell's y, so the ROW pitch is read off the layout instead of inferred: the PWA's
	# cells are 62.8 tall with a 6px gap (68.8 per row) and 5 equal columns in 338 (62.8).
	var ys := []
	for c in cells:
		ys.append("%.1f" % (c as Control).get_global_rect().position.y)
	print("CELL_ROWS=%s" % ", ".join(ys))
	# the bag panel's own top, which is where the belt row's collapsed margin lands
	print("BAG_PANEL=%s" % _rect(panel))
	# MIN sizes up the bag chain: a grid whose rows are 68.0 apart instead of 68.8 has been
	# COMPRESSED, and only the minimums say which box refused to give its child room.
	print("MIN_GRID=%.1f MIN_WRAP=%.1f MIN_BAG_BLOCK=%.1f MIN_INLINE=%.1f MIN_PANE=%.1f" % [
		grid.get_combined_minimum_size().y, wrap.get_combined_minimum_size().y,
		bag_block.get_combined_minimum_size().y, inline.get_combined_minimum_size().y,
		inv.get_combined_minimum_size().y])
	var cell_min: Vector2 = (cells[0] as Control).get_combined_minimum_size()
	print("MIN_CELL=%.1f MIN_SEP=%d" % [cell_min.y, _bag_grid_sep(inv)])
	print("BAG_GEOMETRY_DONE=true")
	quit()
	return false
