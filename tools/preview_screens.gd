extends SceneTree
# VYVOJOVA POMUCKA: vyrenderuje obrazovku (menu / vylepseni / konec) v danem
# rozliseni, aby se dalo posoudit pismo. Nic nezapisuje do hry.
#
#   ~/tools/godot/godot4 --path . --rendering-driver opengl3 \
#       --resolution 600x900 --script res://tools/preview_screens.gd \
#       -- --out=/tmp/menu.png --screen=menu

var view: Node2D = null
var frame: int = 0
var out_path: String = "user://screen.png"
var screen: String = "menu"
var size := Vector2(600.0, 900.0)


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.split("=")[1]
		elif a.begins_with("--screen="):
			screen = a.split("=")[1]
		elif a.begins_with("--size="):
			var parts: PackedStringArray = a.split("=")[1].split("x")
			size = Vector2(float(parts[0]), float(parts[1]))


func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		view = load("res://main.tscn").instantiate()
		root.add_child(view)
		return false
	if frame == 2:
		_setup()
		return false
	if frame < 8:
		return false
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("NO_IMAGE")
		return true
	img.save_png(out_path)
	print("SAVED ", out_path, " ", img.get_width(), "x", img.get_height())
	return true


func _setup() -> void:
	view.layout.update(size)
	view._apply_field()
	var g = view.game
	g.start_level(1)
	g.profile.body = 7
	g.profile.perm["dmg"] = 2
	g.profile.perm["rate"] = 1
	g.profile.perm["shots"] = 1
	if screen == "upg":
		view.menu.open_upgrades()
	elif screen == "end":
		view.menu.open_battle()
		g.phase = "lost"
		g.hp = 0.0
	elif screen == "battle":
		view.menu.open_battle()
		g.wave = 5
		g.phase = "build"
		g.build_left = 3.0
	elif screen == "reset":
		# POTVRZENI VYNULOVANI: modal nad menu.
		view.menu.open_menu()
		view.menu.ask_reset()
	else:
		view.menu.open_menu()
