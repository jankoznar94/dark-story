extends SceneTree
# KONTROLA VELIKOSTI: spusti REALNOU hru (main.tscn), necha ji spawnout prvni
# vlnu a vypise, jake polomery nepratele opravdu dostali. Slouzi k overeni, ze
# se do buildu dostala spravna cisla - ne k nejakemu obrazku.
#
#   ~/tools/godot/godot4 --headless --path . --script res://tools/check_enemy_size.gd

var view: Node2D = null
var frame: int = 0


func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		view = load("res://main.tscn").instantiate()
		root.add_child(view)
		return false
	if frame == 2:
		var size := Vector2(600.0, 900.0)
		view.layout.update(size)
		view._apply_field()
		view.menu.open_battle()
		var g = view.game
		g.start_level(1)
		g.wave = 7
		g.phase = "wave"
		g.plan = 12
		g.spawned = 12
		print("view=%dx%d field_r=%.1f" % [int(size.x), int(size.y), g.field_r])
		for t in Game.ENEMY_TYPES:
			var er: float = g.field_r * float(t["r"])
			print("  %-7s r=%.1f  prumer=%.1f px  (podil plochy %.3f)" %
				[String(t["id"]), er, er * 2.0, float(t["r"])])
		# Realny spawn: co hra opravdu vlozi do enemies.
		g.enemies = []
		g.spawned = 0
		for i in range(40):
			g._spawn()
		var seen: Dictionary = {}
		for e in g.enemies:
			seen[String(e["kind"])] = g.radius_of(e) * 2.0
		for k in seen:
			print("  spawn %-7s prumer=%.1f px" % [k, float(seen[k])])
		return true
	return false
