extends SceneTree
## Print the animation names Godot actually exposes after importing hero.glb.
## glTF import sanitises names (the "|" in the source becomes something else),
## so guessing the clip names in code is unreliable.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://models/hero.glb")
	if packed == null:
		print("LOAD FAILED")
		quit()
		return
	var inst := packed.instantiate()
	root.add_child(inst)
	await process_frame

	var ap := _find(inst)
	if ap == null:
		print("NO AnimationPlayer")
	else:
		var names := ap.get_animation_list()
		print("ANIM_COUNT=%d" % names.size())
		var i := 0
		for n in names:
			print("  [%02d] %s   len=%.2fs" % [i, n, ap.get_animation(n).length])
			i += 1
		# which of the ones the game needs actually exist?
		print("")
		print("NEEDED:")
		for want in ["Sword_Idle", "Walk_Loop", "Sword_Attack", "Sword_Attack_RM",
					 "Hit_Chest", "Spell_Simple_Shoot", "Sprint_Loop", "Death01"]:
			var hit := ""
			for n in names:
				if n.contains(want):
					hit = n
					break
			print("  %-20s -> %s" % [want, hit if hit != "" else "MISSING"])
	quit()


func _find(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find(c)
		if r != null:
			return r
	return null
