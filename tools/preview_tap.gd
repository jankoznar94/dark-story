extends SceneTree
# KONTROLA KLEPNUTI: simuluje dotek na tlacitka menu a vyrenderuje, co se
# opravdu otevrelo. Slouzi k overeni, ze tlacitka sedi na svych mistech.
#
#   ~/tools/godot/godot4 --path . --rendering-driver opengl3 --resolution 390x844 \
#       --script res://tools/preview_tap.gd -- --out=/tmp/tap.png --i=1

var view: Node2D = null
var frame: int = 0
var out_path: String = "user://tap.png"
var idx: int = 1
var w: float = 390.0
var h: float = 844.0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.split("=")[1]
		elif a.begins_with("--i="):
			idx = int(a.split("=")[1])
		elif a.begins_with("--size="):
			var p: PackedStringArray = a.split("=")[1].split("x")
			w = float(p[0])
			h = float(p[1])


func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		view = load("res://main.tscn").instantiate()
		root.add_child(view)
		return false
	if frame == 2:
		view.layout.update(Vector2(w, h))
		view._apply_field()
		view.menu.open_menu()
		print("menu_rects=", view.layout.menu_rects.size())
		for i in range(view.layout.menu_rects.size()):
			var r: Rect2 = view.layout.menu_rects[i]
			print("  %d %s" % [i, str(r)])
		if idx >= 0 and idx < view.layout.menu_rects.size():
			var r: Rect2 = view.layout.menu_rects[idx]
			view._press(r.position + r.size * 0.5)
			print("after press: view=", view.menu.view, " upgrades=", view.menu.is_upgrades())
		return false
	if frame < 8:
		return false
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("NO_IMAGE")
		return true
	img.save_png(out_path)
	print("SAVED ", out_path)
	return true
