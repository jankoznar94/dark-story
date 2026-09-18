extends SceneTree
## Verify BOTH fixes on the delivered hero.glb, in Godot, in the pose the game
## plays (Rig|Sword_Idle). Godot's front is -Z (the toes point there).
##   FACE: the vertices sampling the atlas face patch (u 0.44..0.56) must be on -Z
##   SWORD: the blade must run along the hand, and its point must NOT hang below
##          the fist (the old build hung it 0.81 m straight down -> "slung rifle")

var _hero: Node
var _t := 0.0
var _done := false


func _initialize() -> void:
	_hero = (load("res://models/hero.glb") as PackedScene).instantiate()
	root.add_child(_hero)


func _process(delta: float) -> bool:
	_t += delta
	if _done or _t < 0.3:
		return false
	_done = true
	var mi: MeshInstance3D = _find_mesh(_hero)
	var skel: Skeleton3D = _find_skel(_hero)
	var ap: AnimationPlayer = _find_anim(_hero)
	if ap != null:
		ap.play("Rig|Sword_Idle")

	var names: Array = []
	for i in skel.get_bone_count():
		names.append(skel.get_bone_name(i))
	var handR := skel.find_bone("DEF-hand.R")
	var handL := skel.find_bone("DEF-hand.L")
	print("hand.R bone %d  hand.L bone %d" % [handR, handL])

	# pose the skeleton so bone positions are live (not just rest)
	var st := skel.get_global_transform()
	# pose is live; no explicit force needed
	var hR: Transform3D = st * skel.get_bone_global_pose(handR)
	var hL: Transform3D = st * skel.get_bone_global_pose(handL)
	print("hand.R pose origin (%.3f, %.3f, %.3f)" % [hR.origin.x, hR.origin.y, hR.origin.z])
	print("hand.L pose origin (%.3f, %.3f, %.3f)" % [hL.origin.x, hL.origin.y, hL.origin.z])
	var hand_axis := hR.basis.y.normalized()
	print("hand.R long axis (+Y) in world (%.3f, %.3f, %.3f)"
		% [hand_axis.x, hand_axis.y, hand_axis.z])

	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]

	# --- FACE ---
	var fy := []
	var fz := []
	var hy := []
	var hz := []
	for i in verts.size():
		var best := -1
		var bw := 0.0
		for k in 4:
			var wi := i * 4 + k
			if wi < weights.size() and weights[wi] > bw:
				bw = weights[wi]
				best = bones[wi]
		if best < 0 or best >= names.size():
			continue
		var nm: String = names[best]
		if not (nm.begins_with("DEF-head") or nm.begins_with("DEF-neck")):
			continue
		hy.append(verts[i].y)
		hz.append(verts[i].z)
		if uvs[i].x > 0.44 and uvs[i].x < 0.56:
			fy.append(verts[i].y)
			fz.append(verts[i].z)
	if fz.size() > 0:
		var mz := 0.0
		for z in fz:
			mz += z
		mz /= float(fz.size())
		var hz_avg := 0.0
		for z in hz:
			hz_avg += z
		hz_avg /= float(hz.size())
		print("FACE_PATCH verts %d mean z %+.4f (head mean z %+.4f)"
			% [fz.size(), mz, hz_avg])
		print("FACE_ON_FRONT(-Z) %s" % str(mz < hz_avg))
		print("FACE_ON_PLUS_Z   %s" % str(mz > hz_avg))

	# --- SWORD: vertices fully weighted to hand.R that form the blade ---
	var wr := []
	for i in verts.size():
		var best := -1
		var bw := 0.0
		for k in 4:
			var wi := i * 4 + k
			if wi < weights.size() and weights[wi] > bw:
				bw = weights[wi]
				best = bones[wi]
		if best == handR:
			wr.append(i)
	print("VERTS dominated by hand.R %d" % wr.size())
	# the blade is the set of those verts far from the bone origin
	var far := []
	var near := []
	for i in wr:
		var d: float = (verts[i] - hR.origin).length()
		if d > 0.25:
			far.append(verts[i])
		elif d < 0.18:
			near.append(verts[i])
	print("hand.R verts >0.25 m from the bone (blade) %d" % far.size())
	if far.size() >= 2:
		var mn := Vector3(1e9, 1e9, 1e9)
		var mx := Vector3(-1e9, -1e9, -1e9)
		for v in far:
			mn = mn.min(v)
			mx = mx.max(v)
		print("blade bbox min (%.3f, %.3f, %.3f) max (%.3f, %.3f, %.3f)"
			% [mn.x, mn.y, mn.z, mx.x, mx.y, mx.z])
		var c := Vector3.ZERO
		for v in far:
			c += v
		c /= float(far.size())
		print("blade centroid (%.3f, %.3f, %.3f)  bone origin (%.3f, %.3f, %.3f)"
			% [c.x, c.y, c.z, hR.origin.x, hR.origin.y, hR.origin.z])
		print("blade is %s the fist vertically"
			% ("ABOVE" if c.y > hR.origin.y else "BELOW"))
		# how far does the blade reach from the hand origin?
		var mx_len := 0.0
		for v in far:
			mx_len = maxf(mx_len, (v - hR.origin).length())
		print("blade reach from hand origin %.3f m" % mx_len)
	print("VERIFY_DONE")
	quit()
	return true


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
