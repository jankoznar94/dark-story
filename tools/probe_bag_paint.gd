extends SceneTree
## probe_bag_paint.gd — why does the port's EMPTY bag cell measure rgb(59,59,59) when the
## PWA's is rgb(43,43,43)? The CSS pair is `background:#aaa; opacity:0.25` over
## `.inv-grid-wrap { background:#000 }`, and Godot's own blend was measured to be an
## ordinary over-blend (170a + bg*(1-a)), so 43 is what a correct stack produces.
##
##   godot4 --path . --rendering-driver opengl3 --script res://tools/probe_bag_paint.gd
##
## It opens the REAL inventory through the REAL route and prints, per cell: the stylebox
## fill, the modulate, the background behind the cell, and the PIXEL actually drawn.

const UIKit := preload("res://scripts/ui/ui_kit.gd")

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
		return false
	if _step != 2:
		return false
	_step = 3

	var inv = _main._screens["character"]._inventory
	@warning_ignore("integer_division")
	print("--- STACK above the bag grid ---")
	var node: Node = inv._bag_grid
	while node != null:
		var line := "  %-22s %-16s" % [node.name, node.get_class()]
		if node is Control:
			line += " rect=%s" % str((node as Control).get_global_rect())
		if node is CanvasItem:
			line += " mod=%s" % str((node as CanvasItem).modulate)
		if node is PanelContainer or node is Panel:
			var sb: StyleBox = node.get_theme_stylebox("panel")
			if sb is StyleBoxFlat:
				line += " panel_bg=%s" % str((sb as StyleBoxFlat).bg_color)
		print(line)
		node = node.get_parent()

	print("--- CELLS ---")
	var img: Image = root.get_texture().get_image()
	for i in mini(5, inv._bag_nodes.size()):
		var cell: Button = inv._bag_nodes[i]
		var sb: StyleBoxFlat = cell.get_theme_stylebox("normal")
		var r := cell.get_global_rect()
		var drawn := img.get_pixel(int(r.position.x) + 3, int(r.position.y) + 3)
		print("cell %d rect=%s flat=%s sb_bg=%s sb_border=%s mod=%s drawn=(%d,%d,%d)" % [
			i, str(r), str(cell.flat), str(sb.bg_color), str(sb.border_color),
			str(cell.modulate), int(drawn.r * 255.0), int(drawn.g * 255.0),
			int(drawn.b * 255.0)])
	# what is behind the cells (the wrap's own background, between two cells)
	var c0: Control = inv._bag_nodes[0]
	var gap_x := int(c0.get_global_rect().position.x + c0.size.x + 3)
	var gap_y := int(c0.get_global_rect().position.y + 20)
	var behind := img.get_pixel(gap_x, gap_y)
	print("between cells drawn=(%d,%d,%d)  (the wrap's real background)" % [
		int(behind.r * 255.0), int(behind.g * 255.0), int(behind.b * 255.0)])
	# and the wrap's own rect background, sampled 6px inside its top-left
	var wrap: Control = c0.get_parent().get_parent()
	var wr := wrap.get_global_rect()
	var wp := img.get_pixel(int(wr.position.x) + 6, int(wr.position.y) + 6)
	print("wrap %s rect=%s drawn corner=(%d,%d,%d)" % [
		wrap.name, str(wr), int(wp.r * 255.0), int(wp.g * 255.0), int(wp.b * 255.0)])
	print("BAG_PAINT_DONE=true")
	quit()
	return false
