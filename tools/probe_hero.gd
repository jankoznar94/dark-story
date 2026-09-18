extends SceneTree
## Verify the hero in GODOT. Key insight that makes this simple and airtight:
## the welded sword and the fist are BOTH 100% weighted to DEF-hand.R, so they
## receive the SAME skin matrix in every pose. The vector between them is therefore
## POSE-INVARIANT - if the sword sits in the fist at rest, it sits in the fist in
## every animation, and no posing machinery is needed to prove it.
##
## Identification that survives the export (which fragments the welded sword):
##   exclusive = verts whose ONLY influence is DEF-hand.R. That set also contains
##               the hand mesh, so split it by REST distance from the bone origin:
##               hand <= 0.25 m, blade > 0.25 m.
##   fist      = verts dominated by hand/finger bones within 0.15 m of the bone.
## Godot axes: character front is -Z (toes point there), up is +Y.

var _hero: Node
var _t := 0.0
var _done := false
var _frames := 0


func _initialize() -> void:
	_hero = (load("res://models/hero.glb") as PackedScene).instantiate()
	root.add_child(_hero)


func _process(delta: float) -> bool:
	_t += delta
	_frames += 1
	if _done or _frames < 8:
		return false
	_done = true
	_measure()
	print("VERIFY2_DONE")
	quit()
	return true


func _measure() -> void:
	var mi: MeshInstance3D = _find_mesh(_hero)
	var skel: Skeleton3D = _find_skel(_hero)
	var ap: AnimationPlayer = _find_anim(_hero)
	if ap != null and ap.has_animation("Rig|Sword_Idle"):
		ap.play("Rig|Sword_Idle")

	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var names: Array = []
	for i in skel.get_bone_count():
		names.append(skel.get_bone_name(i))
	var handR := skel.find_bone("DEF-hand.R")
	var gt: Transform3D = skel.global_transform
	var rest_h: Transform3D = gt * skel.get_bone_global_rest(handR)
	print("hand.R rest origin (%.3f, %.3f, %.3f)"
		% [rest_h.origin.x, rest_h.origin.y, rest_h.origin.z])

	var exclusive := []
	var fist := []
	var face := []
	var headz := []
	for i in verts.size():
		var used := []
		var dom := -1
		var dw := 0.0
		for k in 4:
			var wi := i * 4 + k
			if wi >= weights.size() or weights[wi] <= 0.0:
				continue
			used.append(bones[wi])
			if weights[wi] > dw:
				dw = weights[wi]
				dom = bones[wi]
		var v: Vector3 = verts[i]
		if used.size() == 1 and used[0] == handR:
			exclusive.append(i)
		if dom >= 0 and dom < names.size():
			var nm: String = names[dom]
			if nm.begins_with("DEF-head") or nm.begins_with("DEF-neck"):
				headz.append(v)
				if uvs[i].x > 0.44 and uvs[i].x < 0.56:
					face.append(v)
			if nm.ends_with(".R") and (nm.begins_with("DEF-hand") or nm.begins_with("DEF-f_")
					or nm.begins_with("DEF-thumb")):
				if (v - rest_h.origin).length() < 0.15:
					fist.append(v)

	var bladeids := []
	var handids := []
	for i in exclusive:
		if (verts[i] - rest_h.origin).length() > 0.25:
			bladeids.append(i)
		else:
			handids.append(i)
	print("EXCLUSIVE hand.R verts %d -> hand mesh %d, blade %d"
		% [exclusive.size(), handids.size(), bladeids.size()])

	# ---------------- FACE ----------------
	if face.size() > 0:
		var fz := 0.0
		for v in face:
			fz += v.z
		fz /= float(face.size())
		var hz := 0.0
		for v in headz:
			hz += v.z
		hz /= float(headz.size())
		print("FACE_PATCH verts %d mean z %+.4f (head mean z %+.4f)"
			% [face.size(), fz, hz])
		print("FACE_ON_FRONT(-Z, where the toes point) %s" % str(fz < hz))

	# ---------------- SWORD (pose-invariant, both rigid on the same bone) -------
	if bladeids.size() == 0 or fist.size() == 0:
		print("SWORD check skipped: blade %d fist %d" % [bladeids.size(), fist.size()])
		return
	var fsum := Vector3.ZERO
	for v in fist:
		fsum += v
	var fc := fsum / float(fist.size())
	var nearest := 1e9
	for i in bladeids:
		for f in fist:
			nearest = minf(nearest, (verts[i] - f).length())
	var bsum := Vector3.ZERO
	var bmin := Vector3(1e9, 1e9, 1e9)
	var bmax := Vector3(-1e9, -1e9, -1e9)
	for i in bladeids:
		bsum += verts[i]
		bmin = bmin.min(verts[i])
		bmax = bmax.max(verts[i])
	var bc := bsum / float(bladeids.size())
	print("FIST %d verts centroid (%.3f, %.3f, %.3f)" % [fist.size(), fc.x, fc.y, fc.z])
	print("BLADE %d verts centroid (%.3f, %.3f, %.3f)"
		% [bladeids.size(), bc.x, bc.y, bc.z])
	print("NEAREST blade-vert to any fist-vert %.4f m" % nearest)
	print("blade-centroid to fist-centroid %.4f m" % (bc - fc).length())
	print("SWORD_IN_HAND %s" % str(nearest < 0.12))
	print("blade bbox min (%.2f, %.2f, %.2f) max (%.2f, %.2f, %.2f)"
		% [bmin.x, bmin.y, bmin.z, bmax.x, bmax.y, bmax.z])

	# blade axis: grip end = blade vert nearest the fist, tip = farthest from it
	var gripv: Vector3 = verts[bladeids[0]]
	var best := 1e9
	for i in bladeids:
		var d: float = (verts[i] - fc).length()
		if d < best:
			best = d
			gripv = verts[i]
	var tipv: Vector3 = gripv
	var bestlen := 0.0
	for i in bladeids:
		var l: float = (verts[i] - gripv).length()
		if l > bestlen:
			bestlen = l
			tipv = verts[i]
	var bl := tipv - gripv
	var bu := bl.normalized()
	print("blade length %.3f m" % bl.length())
	print("REST blade axis (%.2f, %.2f, %.2f) | vertical %s (up is +Y) | %s (front is -Z)"
		% [bu.x, bu.y, bu.z,
		   "UPWARD" if bu.y > 0.3 else ("DOWNWARD" if bu.y < -0.3 else "LEVEL"),
		   "FORWARD" if bu.z < -0.3 else ("BACKWARD" if bu.z > 0.3 else "SIDEWAYS")])

	# ---------------- the idle POSE, sampled from the live bone ----------------
	var hp: Vector3 = (gt * skel.get_bone_global_pose(handR)).origin
	var hrest: Vector3 = rest_h.origin
	print("posed hand origin (%.3f, %.3f, %.3f) vs rest (%.3f, %.3f, %.3f) -> pose %s"
		% [hp.x, hp.y, hp.z, hrest.x, hrest.y, hrest.z,
		   "ACTIVE" if (hp - hrest).length() > 0.01 else "not applied yet"])
	# the blade in the live pose: apply the same skin matrix to the rest positions
	var skin := gt * skel.get_bone_global_pose(handR) \
		* (gt * skel.get_bone_global_rest(handR)).affine_inverse()
	var p_grip: Vector3 = skin * gripv
	var p_tip: Vector3 = skin * tipv
	var p_axis := (p_tip - p_grip).normalized()
	print("POSED blade axis (%.2f, %.2f, %.2f) | vertical %s | %s"
		% [p_axis.x, p_axis.y, p_axis.z,
		   "UPWARD" if p_axis.y > 0.3 else ("DOWNWARD" if p_axis.y < -0.3 else "LEVEL"),
		   "FORWARD" if p_axis.z < -0.3 else ("BACKWARD" if p_axis.z > 0.3 else "SIDEWAYS")])
	print("POSED blade tip y %+.3f vs grip y %+.3f (tip %s the grip)"
		% [p_tip.y, p_grip.y, "ABOVE" if p_tip.y > p_grip.y else "BELOW"])
	print("POSED blade tip z %+.3f vs grip z %+.3f (tip %s)"
		% [p_tip.z, p_grip.z, "IN FRONT" if p_tip.z < p_grip.z else "BEHIND"])
	print("POSED blade points at the ground: %s" % str(p_axis.y < -0.5))
	print("POSED blade points forward: %s" % str(p_axis.z < -0.3))


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r != null:
			return r
	return null


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null
