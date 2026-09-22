extends SceneTree
## Probe: can a Control be held at the viewport width when its content's minimum size is
## larger? The port's screens measured 554px wide at a 390px viewport, so this pins down
## WHICH structure actually clamps.

func _initialize() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)

	# A: the current shape — the screen itself is the ScrollContainer, anchored full rect.
	var a := ScrollContainer.new()
	a.set_anchors_preset(Control.PRESET_FULL_RECT)
	var wide_a := Control.new()
	wide_a.custom_minimum_size = Vector2(594, 10)
	a.add_child(wide_a)
	layer.add_child(a)

	# B: a plain Control root (no min of its own) with the ScrollContainer anchored inside.
	var b_root := Control.new()
	b_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(b_root)
	var b := ScrollContainer.new()
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	var wide_b := Control.new()
	wide_b.custom_minimum_size = Vector2(594, 10)
	b.add_child(wide_b)
	b_root.add_child(b)

	await process_frame
	await process_frame
	print("A screen(ScrollContainer) size=", a.size, " min=", a.get_combined_minimum_size())
	print("B root size=", b_root.size, " min=", b_root.get_combined_minimum_size())
	print("B scroll size=", b.size, " min=", b.get_combined_minimum_size())
	quit()
