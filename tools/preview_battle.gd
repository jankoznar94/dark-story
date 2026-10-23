extends SceneTree
# VYVOJOVA POMUCKA: odehraje kus 5. vlny (kde uz jsou strelci) a vyrenderuje
# snimek. Slouzi k posouzeni velikosti, rozestupu a citelnosti nepratel.
# Nic nezapisuje do hry ani na disk hry.
#
#   ~/tools/godot/godot4 --path . --rendering-driver opengl3 --resolution 600x900 \
#       --script res://tools/preview_battle.gd -- --out=/tmp/thrower_battle.png

var view: Node2D = null
var frame: int = 0
var out_path: String = "user://thrower_battle.png"
var _simmed: bool = false
var _steps: int = 780


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.split("=")[1]
		elif a.begins_with("--steps="):
			_steps = int(a.split("=")[1])


func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		view = load("res://main.tscn").instantiate()
		root.add_child(view)
		return false
	if frame == 2:
		_layout()
		return false
	if not _simmed and frame >= 4:
		_sim()
		_simmed = true
		return false
	if frame < 10:
		return false
	var img: Image = root.get_texture().get_image()
	if img == null:
		print("NO_IMAGE")
		return true
	img.save_png(out_path)
	print("SAVED ", out_path, " ", img.get_width(), "x", img.get_height())
	return true


func _layout() -> void:
	view.layout.update(Vector2(600.0, 900.0))
	view._apply_field()
	view.menu.open_battle()
	var g = view.game
	g.start_level(1)
	g.wave = 5
	g.phase = "build"
	g.build_left = 0.01


# SIMULACE: hrac miri na nejvyssiho nepritele, aby se bitva opravdu hrala.
func _sim() -> void:
	var g = view.game
	for i in range(_steps):
		var target := Vector2.ZERO
		var best_y: float = 1e9
		for e in g.enemies:
			var p: Vector2 = e["pos"]
			if p.y < best_y:
				best_y = p.y
				target = p
		if target != Vector2.ZERO:
			g.aim_at(target)
		else:
			g.release()
		g.step(1.0 / 60.0)
	g.release()
