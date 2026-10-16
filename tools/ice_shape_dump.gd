extends SceneTree

# Docasny nastroj (nepatri do gitu): vypise PRESNE body ledoveho krystalu
# (`Shapes.crystal_ring`) pro nekolik poctu stran, aby se daly vykreslit mimo
# Godot (headless nevykresli) a poslat Janovi k vyberu.

func _init() -> void:
	var ring_r: float = 11.26        # 390x844, poutnik 0,85
	var out := {}
	for sides in [6, 8, 9, 10]:
		var pts: Array = []
		for p in Shapes.crystal_ring(Vector2.ZERO, ring_r, sides):
			pts.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
		out[str(sides)] = pts
	print("CRYSTAL=" + JSON.stringify({"ring_r": ring_r, "profiles": out,
		"sides": Shapes.CRYSTAL_SIDES, "radius": Shapes.CRYSTAL_RADIUS,
		"inner": Shapes.crystal_inner()}))
	quit()
