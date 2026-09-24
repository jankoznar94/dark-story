extends SceneTree
## probe_border_box.gd — where does a Godot Button's stylebox border actually land?
##
## The port's equip slots are built as `custom_minimum_size = 75 - 2*border` on the theory
## that Godot draws the border OUTSIDE the content box, so a 73px minimum renders as a 75px
## slot (the PWA's `box-sizing:border-box` 75px). Measured on the real pane, the helmet slot
## came out S=(75.0, 73.0) — 75 wide because the grid column stretched it, but only 73 TALL,
## which says the drawn height IS the minimum and the border is INSIDE.
##
## This settles it on a bare Button, no pane involved: two buttons, one 75 with a 1px
## border, one 73 with a 1px border, each printed after a real layout pass.
##
##   godot4 --path . --rendering-driver opengl3 --script res://tools/probe_border_box.gd

func _initialize() -> void:
	root.size = Vector2i(390, 844)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	await process_frame
	await process_frame
	for spec in [[75.0, "custom 75"], [73.0, "custom 73"]]:
		var size: float = spec[0]
		var b := Button.new()
		b.text = ""
		b.custom_minimum_size = Vector2(size, size)
		var st := StyleBoxFlat.new()
		st.bg_color = Color("#000000")
		st.border_color = Color("#4a4a4a")
		st.set_border_width_all(1)
		st.set_corner_radius_all(8)
		st.set_content_margin_all(0)
		for s in ["normal", "hover", "focus", "disabled"]:
			b.add_theme_stylebox_override(s, st)
		root.add_child(b)
		await process_frame
		await process_frame
		print("%s: combined_min=%s drawn=%s" % [spec[1],
			str(b.get_combined_minimum_size()), str(b.size)])
		# The stylebox's own minimum is the thing a Container consults.
		print("   stylebox min=%s border=%d content_margin_l=%s" % [
			str(st.get_minimum_size()), st.border_width_left, str(st.content_margin_left)])
		b.queue_free()
	quit()
