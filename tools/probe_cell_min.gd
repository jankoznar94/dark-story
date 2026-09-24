extends SceneTree
## probe_cell_min.gd — what minimum size does `UIKit.item_cell(size)` actually come out at?
##
## `.chest-cell { aspect-ratio:1 }` is 62.8 TOTAL in the PWA (`box-sizing:border-box`, so
## its 1px border is INSIDE). Godot draws a stylebox border OUTSIDE the content margin, so
## a `custom_minimum_size` of 62.8 may or may not become 62.8 + 2. This prints the number
## instead of assuming it, for a 5-column row whose total must be 338.

func _initialize() -> void:
	root.size = Vector2i(390, 844)
	var kit = load("res://scripts/ui/ui_kit.gd")
	for size in [62.8, 60.8, 61.8]:
		var cell: Button = kit.item_cell({}, float(size))
		root.add_child(cell)
		var m: Vector2 = cell.get_combined_minimum_size()
		var st: StyleBoxFlat = cell.get_theme_stylebox("normal")
		print("SIZE=%.1f MIN=(%.1f, %.1f) BORDER=%d MARGIN_L=%.1f" % [
			size, m.x, m.y, st.border_width_left, st.content_margin_left])
		cell.queue_free()
	print("CELL_MIN_DONE=true")
	quit()
