extends SceneTree
## What does a MarginContainer / HBoxContainer actually report as a minimum in 4.7?
## The shop's price button came out 20px wide and its MarginContainer ignored 16+16 margins,
## so the primitive itself is the thing to measure before working around it.


func _initialize() -> void:
	var lbl := Label.new()
	lbl.text = "15"
	print("label min=%s" % str(lbl.get_combined_minimum_size()))

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	var inner_lbl := Label.new()
	inner_lbl.text = "15"
	pad.add_child(inner_lbl)
	print("MarginContainer min=%s (label %s + 32 wide, 16 tall expected)"
		% [str(pad.get_combined_minimum_size()), str(inner_lbl.get_combined_minimum_size())])

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var a := TextureRect.new()
	a.custom_minimum_size = Vector2(16, 16)
	box.add_child(a)
	var b := Label.new()
	b.text = "15"
	box.add_child(b)
	print("HBoxContainer min=%s (16 + 6 + label expected)" % str(box.get_combined_minimum_size()))

	var btn := Button.new()
	btn.add_child(box)
	print("Button min after add_child=%s" % str(btn.get_combined_minimum_size()))
	var btn2 := Button.new()
	var box2 := HBoxContainer.new()
	var l2 := Label.new()
	l2.text = "15"
	box2.add_child(l2)
	btn2.add_child(box2)
	print("Button min (plain Label child)=%s" % str(btn2.get_combined_minimum_size()))
	quit()
