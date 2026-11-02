extends SceneTree
## Isolated: is a 2px orange border with corner radius 28 on a 56x56 StyleBoxFlat
## actually a FULL ring? Renders it big (zoom via a scale) and saves a PNG.
var _frames := 0

func _initialize() -> void:
	var rootc := Control.new()
	rootc.size = Vector2(390, 200)
	root.add_child(rootc)
	for i in 3:
		var holder := Control.new()
		holder.position = Vector2(20 + i * 90, 40)
		holder.size = Vector2(56, 56)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#000000")
		style.border_color = Color("#e67e22")
		if i == 0:
			style.set_border_width_all(2)
			style.set_corner_radius_all(28)
		elif i == 1:
			style.set_border_width_all(2)
			style.set_corner_radius_all(26)
		else:
			style.set_border_width_all(2)
			style.set_corner_radius_all(28)
			style.anti_aliasing = false
		var panel := Panel.new()
		panel.position = Vector2.ZERO
		panel.size = Vector2(56, 56)
		panel.add_theme_stylebox_override("panel", style)
		holder.add_child(panel)
		rootc.add_child(holder)

func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false
	if _frames == 5:
		await RenderingServer.frame_post_draw
		var img := get_root().get_texture().get_image()
		img.save_png("/tmp/stylebox_ring.png")
		print("saved, size=", img.get_size())
		quit(0)
	return true
