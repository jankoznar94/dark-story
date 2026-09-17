extends SceneTree
## Regression test: the hero must actually HOLD the sword, and the sword must
## move with the hand.
##
## The bug this locks down (both symptoms Jan reported):
##   * "the bar is in his crotch" - a procedural Pivot+Blade bar hung at the
##     player's hip and rotated independently of the animation
##   * "he swings his arms but the bar is not in them" - the source rig does NOT
##     animate the fingers in the sword/walk clips, so the hand stayed OPEN
##     (thumb-tip to middle-fingertip = 78 mm). The closed-hand pose exists only
##     in the pistol clip (0.9 mm) and had to be baked into the sword clips.
##
## What is asserted here (things that can be measured correctly from Godot):
##   1. the steel surface is bound 100% to the hand bone (that is what makes it
##      follow the arm at all)
##   2. the fist is closed in the clips we ship
##   3. the hand bone actually travels through the swing, so the welded sword does
##   4. the hero is ~1.8 m and not 100x off (a stray scale is the classic trap)
##
## NOT asserted here: exact blade points in world space. A skinned MeshInstance3D
## ignores its own transform, and re-deriving the skin matrix by hand produced
## 193 m instead of 1.9 m, so blade-vs-floor and blade-vs-body were verified in
## Blender on the source data instead (tip stays 0.32 m above the floor at the
## strike, 3.6 cm clearance from the torso and legs).
##
## Run: godot --headless --path . --script res://tools/test_weapon.gd
const HERO := "res://models/hero.glb"
const CLIP_IDLE := "Rig|Sword_Idle"
const CLIP_ATTACK := "Rig|Sword_Attack"

var fails: Array[String] = []
var checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _ok(label: String, cond: bool, detail: String = "") -> void:
	checks += 1
	if cond:
		print("  OK   ", label, ("  " + detail) if detail else "")
	else:
		print("  FAIL ", label, "  ", detail)
		fails.append(label)


func _find(n: Node, t: String) -> Node:
	if t == "skel" and n is Skeleton3D:
		return n
	if t == "mesh" and n is MeshInstance3D:
		return n
	if t == "anim" and n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find(c, t)
		if r != null:
			return r
	return null


func _run() -> void:
	var packed: PackedScene = load(HERO)
	if packed == null:
		print("LOAD_FAILED")
		print("WEAPON_ALL_PASS=false")
		quit()
		return
	var inst := packed.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame

	var skel: Skeleton3D = _find(inst, "skel")
	var mi: MeshInstance3D = _find(inst, "mesh")
	var anim: AnimationPlayer = _find(inst, "anim")
	_ok("hero.glb has a Skeleton3D", skel != null)
	_ok("hero.glb has a MeshInstance3D", mi != null)
	_ok("hero.glb has an AnimationPlayer", anim != null)
	if skel == null or mi == null or anim == null:
		print("ALL_PASS=false")
		quit()
		return

	var names := anim.get_animation_list()
	_ok("idle clip present", names.has(CLIP_IDLE), CLIP_IDLE)
	_ok("attack clip present", names.has(CLIP_ATTACK), CLIP_ATTACK)

	# --- 1. one mesh, two surfaces: body + steel -------------------------------
	# NOTE: a GDScript lambda captures by VALUE, so a counter inside a lambda
	# never updates the outer variable (it silently read 0). Use an array, which
	# is passed by reference.
	var found: Array = []
	_collect_meshes(inst, found)
	_ok("hero is a single skinned mesh", found.size() == 1,
		"%d mesh nodes" % found.size())
	_ok("mesh has 2 surfaces (body + steel)", mi.mesh.get_surface_count() == 2,
		"%d" % mi.mesh.get_surface_count())

	# --- 2. the steel is welded to the hand bone ------------------------------
	# surface 1 = steel. Every vertex with weight > 0.5 must point at DEF-hand.R.
	var hand_idx := skel.find_bone("DEF-hand.R")
	_ok("hand bone found", hand_idx != -1)
	var steel: Array = mi.mesh.surface_get_arrays(1)
	var bones: PackedInt32Array = steel[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = steel[Mesh.ARRAY_WEIGHTS]
	var verts: PackedVector3Array = steel[Mesh.ARRAY_VERTEX]
	_ok("steel surface carries skin data", bones != null and weights != null)
	var bound_hand := 0
	var bound_other := 0
	for i in weights.size():
		if weights[i] > 0.5:
			if bones[i] == hand_idx:
				bound_hand += 1
			else:
				bound_other += 1
	print("  info steel verts=%d bound_to_hand=%d bound_to_other=%d"
		% [verts.size(), bound_hand, bound_other])
	_ok("every steel vertex is bound to DEF-hand.R", bound_other == 0 and bound_hand > 0,
		"%d to hand, %d elsewhere" % [bound_hand, bound_other])

	# --- 3. the fist is CLOSED in the clips we ship ---------------------------
	# measured as the posed bone distance thumb-tip <-> middle-fingertip: the
	# source rig gives 0.9 mm closed and 78 mm wide open.
	var thumb := skel.find_bone("DEF-thumb.03.R")
	var middle := skel.find_bone("DEF-f_middle.03.R")
	_ok("finger tip bones found", thumb != -1 and middle != -1)
	for clip in [CLIP_IDLE, CLIP_ATTACK]:
		anim.play(clip, -1.0, 1.0)
		await process_frame
		await physics_frame
		var a: Vector3 = skel.get_bone_global_pose(thumb).origin
		var b: Vector3 = skel.get_bone_global_pose(middle).origin
		var gap := a.distance_to(b)
		_ok("%s: fist is closed" % clip, gap < 0.01, "thumb-middle gap %.4f m" % gap)

	# --- 4. the hand bone really moves through the swing ----------------------
	# the sword rides this bone, so if the bone travels, the sword travels with it.
	# Bone poses come back in the Skeleton3D's own space, which the glTF importer
	# scaled by 100 relative to world space, so the raw numbers look tiny and a
	# metre-based threshold is wrong. Normalise by that scale instead of guessing.
	var sscale: float = maxf(skel.global_transform.basis.get_scale().x, 0.0001)
	anim.play(CLIP_ATTACK, -1.0, 1.0)
	await process_frame
	var travelled := 0.0
	var prev := Vector3.ZERO
	var first := true
	for frac in [0.0, 0.15, 0.3, 0.45, 0.6, 0.75]:
		anim.seek(frac, true)
		await process_frame
		var o: Vector3 = skel.get_bone_global_pose(hand_idx).origin
		if not first:
			travelled += prev.distance_to(o)
		prev = o
		first = false
	var world_travel := travelled * sscale
	_ok("hand travels through the attack swing", world_travel > 0.5,
		"hand path %.2f m in world terms (%.4f in bone space, scale %.0f)"
		% [world_travel, travelled, sscale])

	# --- 5. the hero is about 1.8 m, not 100x off -----------------------------
	var aabb: AABB = mi.get_aabb()
	print("  info mesh AABB position=%s size=%s" % [aabb.position, aabb.size])
	_ok("hero is roughly 1.8 m tall", aabb.size.y > 1.5 and aabb.size.y < 2.2,
		"%.3f m" % aabb.size.y)
	_ok("hero is not 100x too big", aabb.size.y < 3.0, "%.3f m" % aabb.size.y)

	print("")
	print("checks run: ", checks)
	if fails.is_empty() and checks >= 10:
		print("WEAPON_ALL_PASS=true")
	else:
		for f in fails:
			print("FAIL: ", f)
		print("WEAPON_ALL_PASS=false")
	quit()


func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)
