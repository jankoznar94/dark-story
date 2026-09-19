extends SceneTree
## List the bones the imported hero skeleton actually exposes, so a foot-slide
## test can name them. glTF import can sanitise names (dots, pipes).
##   godot --headless --path . --script res://tools/probe_bones.gd

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://models/hero.glb")
	var inst: Node = packed.instantiate()
	root.add_child(inst)
	await process_frame
	var sk := _find_skel(inst)
	if sk == null:
		print("NO SKELETON")
		quit()
		return
	print("SKELETON=%s bones=%d" % [sk.name, sk.get_bone_count()])
	for i in sk.get_bone_count():
		var bn: String = sk.get_bone_name(i)
		if bn.to_lower().contains("toe") or bn.to_lower().contains("foot") \
				or bn.to_lower().contains("hand") or bn.to_lower().contains("root") \
				or bn.to_lower().contains("hips"):
			print("  [%02d] %s parent=%d" % [i, bn, sk.get_bone_parent(i)])
	print("BONES_DONE")
	quit()


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null
