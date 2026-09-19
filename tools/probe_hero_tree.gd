extends SceneTree
## Print the node tree Godot actually builds from models/hero.glb, with every
## mesh instance's AABB. This is what the game sees - the source of truth for
## "is there a stray object on the model".

func _init() -> void:
	var packed: PackedScene = load("res://models/hero.glb")
	if packed == null:
		print("LOAD FAILED")
		quit()
		return
	var root: Node = packed.instantiate()
	print("ROOT %s (%s)" % [root.name, root.get_class()])
	_dump(root, 0)
	print("PROBE_HERO_TREE_DONE")
	quit()


func _dump(n: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	var extra := ""
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var m := mi.mesh
		var surfaces := 0
		var aabb := AABB()
		if m != null:
			surfaces = m.get_surface_count()
			if surfaces > 0:
				aabb = m.get_aabb()
		extra = " [MeshInstance3D surfaces=%d aabb_pos=%s aabb_size=%s skin=%s]" % [
			surfaces, str(aabb.position), str(aabb.size),
			str(mi.skin != null) if m != null else "-"]
	elif n is Skeleton3D:
		extra = " [Skeleton3D bones=%d]" % (n as Skeleton3D).get_bone_count()
	elif n is AnimationPlayer:
		extra = " [AnimationPlayer anims=%d]" % (n as AnimationPlayer).get_animation_list().size()
	print("%s- %s (%s)%s" % [pad, n.name, n.get_class(), extra])
	for c in n.get_children():
		_dump(c, depth + 1)
