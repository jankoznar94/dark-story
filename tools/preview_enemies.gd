extends SceneTree
# VYVOJOVA POMUCKA: vyrenderuje obrazovku bitvy se vsemi druhy nepratel, aby se
# dalo posoudit, jak vypadaji portrety, velikosti a střely. Nic nezapisuje do hry.
#
#   ~/tools/godot/godot4 --path . --rendering-driver opengl3 --resolution 600x900 \
#       --script res://tools/preview_enemies.gd -- --out=/tmp/thrower_enemies.png

var view: Node2D = null
var frame: int = 0
var out_path: String = "user://thrower_enemies.png"
var _placed: bool = false


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.split("=")[1]


func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		view = load("res://main.tscn").instantiate()
		root.add_child(view)
		return false
	if frame == 2:
		_layout()
		return false
	if not _placed and frame >= 4:
		_place()
		_placed = true
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
	view.game.start_level(1)
	view.game.phase = "wave"
	view.game.plan = 99
	view.game.spawned = 99
	view.game.wave = 1
	view.game.build_left = 9999.0
	view.menu.open_battle()
	view.game.enemies = []
	view.game.spears = []
	view.game.enemy_shots = []


func _place() -> void:
	var g = view.game
	var c: Vector2 = g.center
	var fr: float = g.field_r
	# SEST DRUHU v mrizce nad bojovnikem, kazdy ve sve velikosti.
	var kinds: Array = ["cobra", "nomad", "treant", "kolos", "ghost", "pyro"]
	var cols: int = 3
	for i in range(kinds.size()):
		var t: Dictionary = Game.enemy_type(String(kinds[i]))
		var er: float = fr * float(t["r"])
		var col: int = i % cols
		var row: int = i / cols
		var pos := Vector2(c.x + (float(col) - 1.0) * fr * 0.52,
			c.y - fr * 1.05 + float(row) * fr * 0.62)
		var e := {
			"pos": pos, "kind": String(t["id"]), "r": er,
			"ranged": bool(t["ranged"]),
			"hp": 10.0, "max_hp": 10.0, "speed": 0.0,
			"dmg": 5.0, "alive": true,
		}
		if bool(t["ranged"]):
			e["stop"] = float(t["stop"])
			e["shot_left"] = 0.25
			e["shot_cd"] = float(t["shot_cd"])
			e["shot_dmg"] = 0.6
			e["spd"] = 0.0
		# ZIVOTNI OBLOUK: u dvou nepratel castecne ubrany, aby byl videt.
		if i == 1:
			e["hp"] = 6.0
		if i == 3:
			e["hp"] = 2.5
		g.enemies.append(e)
	# STRELY STREL CU ve vzduchu, aby bylo videt, jak vypadaji.
	var ghost := Game.enemy_type("ghost")
	var pyro := Game.enemy_type("pyro")
	for i in range(2):
		var from := Vector2(c.x + (float(i) - 0.5) * fr * 0.30, c.y - fr * 0.55)
		var dir: Vector2 = (c - from).normalized()
		g.enemy_shots.append({
			"pos": from + dir * fr * 0.18,
			"dir": dir, "dmg": 5.0, "spd": fr * 0.5,
			"r": fr * 0.013,
			"kind": "ghost" if i == 0 else "pyro",
			"alive": true,
		})
	# PO ZASADENI: faze musi zustat "wave", jinak hra mezi snimky prepne
	# do "build" a pres nepratele se vytiskne odpoctove "Priprav se".
	g.phase = "wave"
	g.plan = 99
	g.spawned = 99
	g.wave = 1
	g.aiming = true
	g.aim = Vector2(-0.35, -1.0).normalized()
