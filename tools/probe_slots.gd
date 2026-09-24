extends SceneTree
## probe_slots.gd — print every equip slot's rect, its stylebox background, and the
## rect of each icon child, so "the icon overflows the slot" can be measured rather
## than argued about.

func _initialize() -> void:
	var main = load("res://scripts/main.gd").new()
	root.add_child(main)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var modal = main_node()._modal()
	main_node().open_modal("inventory")
	await process_frame
	await process_frame
	var inv = modal.inventory()
	inv.refresh()
	await process_frame
	await process_frame
	print("--- DOLL ---")
	for slot in inv._slot_nodes:
		var b: Button = inv._slot_nodes[slot]
		var st: StyleBoxFlat = b.get_theme_stylebox("normal")
		print("slot=%s rect=%s min=%s bg=%s border=%s" % [
			slot, str(b.get_global_rect()), str(b.get_combined_minimum_size()),
			str(st.bg_color), str(st.border_color)])
		for c in b.get_children():
			var tr := c as TextureRect
			if tr == null:
				print("   child %s rect=%s" % [c.get_class(), str(c.get_global_rect())])
				continue
			var tex: Texture2D = tr.texture
			print("   icon %s rect=%s tex=%s stretch=%d expand=%d mod=%s" % [
				tr.name, str(tr.get_global_rect()),
				("null" if tex == null else str(tex.get_size())),
				tr.stretch_mode, tr.expand_mode, str(tr.modulate)])
	print("--- BAG[0] ---")
	if inv._bag_nodes.size() > 0:
		var cell: Button = inv._bag_nodes[0]
		var st2: StyleBoxFlat = cell.get_theme_stylebox("normal")
		print("cell rect=%s bg=%s" % [str(cell.get_global_rect()), str(st2.bg_color)])
		for c in cell.get_children():
			print("   child %s rect=%s" % [c.get_class(), str(c.get_global_rect())])
	print("--- SAVE ---")
	print("equip=", str(main_node().state.equip()))
	print("inv_size=", main_node().state.inventory().size())
	quit()


func main_node() -> Node:
	for c in root.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("main.gd"):
			return c
	return null
