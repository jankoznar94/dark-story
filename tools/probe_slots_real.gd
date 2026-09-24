extends SceneTree
## probe_slots_real.gd — the REAL 390x844 canvas: every equip slot's rect, its stylebox
## background/border, and each icon child's rect. A headless root Window is 64x64, so
## probe_slots.gd's numbers are not the player's — this one runs under opengl3 like
## capture_screen.gd and prints after a few real frames.
##
##   godot4 --path . --rendering-driver opengl3 --script res://tools/probe_slots_real.gd

var _frames := 0
var _started := false


func _initialize() -> void:
	var main = load("res://scripts/main.gd").new()
	root.add_child(main)
	print("root size = ", root.size)


func _process(_delta: float) -> bool:
	var main = _main()
	if main == null or main._nav_bar == null:
		return false
	if not _started:
		_started = true
		main.open_modal("inventory")
		return false
	_frames += 1
	if _frames < 3:
		return false
	var modal = main._screens["character"]
	var inv = modal.inventory()
	inv.refresh()
	_frames = -100  # only once
	await process_frame
	_dump(main, inv)
	quit()
	return false


func _main() -> Node:
	for c in root.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("main.gd"):
			return c
	return null


func _dump(main: Node, inv) -> void:
	print("--- DOLL (real canvas) ---")
	for slot in inv._slot_nodes:
		var b: Button = inv._slot_nodes[slot]
		var st: StyleBoxFlat = b.get_theme_stylebox("normal")
		print("slot=%s rect=%s bg=%s border=%s bw=%d" % [slot, str(b.get_global_rect()),
			str(st.bg_color), str(st.border_color), st.border_width_left])
		for c in b.get_children():
			var tr := c as TextureRect
			if tr == null:
				print("   child %s rect=%s" % [c.get_class(), str(c.get_global_rect())])
				continue
			var tex: Texture2D = tr.texture
			print("   icon rect=%s anchor_l=%.3f anchor_r=%.3f off_l=%.1f off_r=%.1f tex=%s stretch=%d mod=%s" % [
				str(tr.get_global_rect()), tr.anchor_left, tr.anchor_right,
				tr.offset_left, tr.offset_right,
				("null" if tex == null else str(tex.get_size())),
				tr.stretch_mode, str(tr.modulate)])
	print("--- BAG[0..2] ---")
	for i in range(3):
		if i >= inv._bag_nodes.size():
			break
		var cell: Button = inv._bag_nodes[i]
		var st2: StyleBoxFlat = cell.get_theme_stylebox("normal")
		print("cell %d rect=%s bg=%s" % [i, str(cell.get_global_rect()), str(st2.bg_color)])
		for c in cell.get_children():
			print("   child %s rect=%s" % [c.get_class(), str(c.get_global_rect())])
	print("--- PWA for comparison: equip slot bg #000, border 1.5 #4a4a4a, icon object-fit:cover in a #000 box ---")
