extends SceneTree
## What material does the ENGINE actually have on an imported prop mesh?
## A .mtl-only change does not change the .obj hash, so Godot may keep the old
## import. This prints the real albedo the renderer will use.
##   godot --headless --path . --script res://tools/probe_prop_material.gd

func _initialize() -> void:
	var Lum := func(c: Color) -> float:
		return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
	for name in ["tree_dead", "rock_boulder", "crate_medium", "pillar", "wall_segment",
			"fence_run", "barrel", "stump", "tree_conifer_canopy"]:
		var path := "res://assets/props/%s.obj" % name
		if not ResourceLoader.exists(path):
			print("PROBE missing %s" % name)
			continue
		var m: Mesh = load(path)
		if m == null:
			print("PROBE null %s" % name)
			continue
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			var al := "NO_MATERIAL"
			var lum := -1.0
			if mat is StandardMaterial3D:
				var c: Color = (mat as StandardMaterial3D).albedo_color
				al = "rgba(%.3f, %.3f, %.3f, %.2f)" % [c.r, c.g, c.b, c.a]
				lum = Lum.call(c) * 255.0
			elif mat is BaseMaterial3D:
				var c2: Color = (mat as BaseMaterial3D).albedo_color
				al = "base rgba(%.3f, %.3f, %.3f, %.2f)" % [c2.r, c2.g, c2.b, c2.a]
				lum = Lum.call(c2) * 255.0
			print("PROBE %-22s surf %d  %-12s albedo %s  lum %6.1f"
				% [name, s, mat.get_class() if mat != null else "null", al, lum])
	quit()
