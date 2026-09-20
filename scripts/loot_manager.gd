extends Node3D
## What monsters leave on the ground. One place that owns the drops, so the
## pickup rule exists once and every caller (a death, a chest, a test) uses it.
##
## D2's rule for the drop POSITION: a body is thrown a short distance from the
## corpse, on a spot that is not inside a wall and not inside another drop. Never
## under the corpse, because that is where the player is standing.
##
## Only one item is picked up per click. It goes straight into the bag; if the bag
## is full the drop STAYS on the ground and the game says so, because silently
## destroying a rare the player can see is the worst bug a loot game can have.

const LootDrop := preload("res://scripts/loot_drop.gd")
const ItemGen := preload("res://scripts/item_gen.gd")

## How far from the corpse the drop is thrown, and how many spots are tried
## before giving up and dropping it at the corpse (the D2 "it stays where it
## fell" behaviour - better a reachable item than none).
const THROW_MIN := 0.6
const THROW_MAX := 1.4
const THROW_TRIES := 8

## How far a click can reach a name. Diablo lets you click a name across the
## screen; this is generous on purpose so a phone tap is not a test of aim, but
## still bounded so the player cannot vacuum the arena from one spot.
const PICK_RANGE := 8.0

## Physics layer holding items (see loot_drop.gd).
const LAYER := 2

signal item_picked(item)

var _drops: Array = []
## The camera, used to turn a screen tap into a world ray. Set by main.gd.
var camera: Camera3D


func _ready() -> void:
	camera = get_viewport().get_camera_3d()


## Rolls `ilvl`-appropriate loot for a monster that died at `origin` and puts it
## on the ground. Returns the number of items that actually landed.
func spawn_for_death(origin: Vector3, ilvl: int, rng: RandomNumberGenerator = null) -> int:
	var items: Array = ItemGen.roll_drop(ilvl, rng)
	var placed := 0
	for it in items:
		if spawn_item(it, origin):
			placed += 1
	return placed


## Puts ONE item on the ground near `origin`. Returns false when no clear spot
## exists - the caller then decides whether to drop it anyway.
func spawn_item(item, origin: Vector3, rng: RandomNumberGenerator = null) -> bool:
	var r: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
	r.randomize()
	var best := origin
	var found := false
	for i in THROW_TRIES:
		var a := r.randf_range(0.0, TAU)
		var d := r.randf_range(THROW_MIN, THROW_MAX)
		var p := origin + Vector3(cos(a) * d, 0.0, sin(a) * d)
		p = _snap_to_ground(p)
		if _spot_is_clear(p):
			best = p
			found = true
			break
	if not found:
		best = _snap_to_ground(origin)
	var node := LootDrop.new()
	node.name = "Drop_%d" % item.uid
	add_child(node)
	node.setup(item)
	node.global_position = best
	_drops.append(node)
	return found


## A drop must not sit inside a wall or a prop. Cheaper and more reliable than a
## shape cast: an item is small and the level is coarse, so a sphere overlap test
## against the level's static bodies is exact enough and cannot fail open.
func _spot_is_clear(p: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.35
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), p + Vector3(0, 0.35, 0))
	q.collision_mask = 1
	var hits := space.intersect_shape(q, 4)
	for h in hits:
		var c: Object = h["collider"]
		# the floor is on layer 1 too; an item ON the floor is the normal case
		if c is StaticBody3D and c.name == "FloorBody":
			continue
		return false
	return true


## Drops are placed on the ground plane. The floor is flat and at y = 0, so this
## is a constant rather than a raycast - and a raycast here would find the item's
## own Area3D on layer 2 if the layers were ever mis-set.
func _snap_to_ground(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)


## Everything currently on the ground, for tests and for the debug line.
func drops() -> Array:
	return _drops.duplicate()


func drop_count() -> int:
	return _drops.size()


## Takes one drop away. Returns the item, or null when the node was not ours.
func take(drop_node):
	if not _drops.has(drop_node):
		return null
	_drops.erase(drop_node)
	var it: Variant = drop_node.item
	drop_node.queue_free()
	return it


func clear() -> void:
	for d in _drops:
		if is_instance_valid(d):
			d.queue_free()
	_drops.clear()


# ------------------------------------------------------------------- picking
## The screen-space tap that D2 uses: a click on the NAME (or on the model)
## picks the item up. Ray from the camera through the tap, then look for a drop
## among the colliders - the item's own Area3D covers both the model and the
## name, so "click the name" and "click the sword" are one code path.
##
## Returns the picked item, or null when the tap hit nothing.
func try_pick_at_screen(screen_pos: Vector2, inventory, player_pos: Vector3):
	if camera == null or not camera.is_inside_tree():
		camera = get_viewport().get_camera_3d()
		if camera == null:
			return null
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var space := get_world_3d().direct_space_state
	# mask 1|2: a wall in front of the item must block the pick, but the item's
	# own Area3D is what we are looking for
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	q.collision_mask = 1 | LAYER
	q.collide_with_areas = true
	var res := space.intersect_ray(q)
	if res.is_empty():
		return null
	var hit: Object = res["collider"]
	var node := _drop_of(hit)
	if node == null:
		return null
	if node.global_position.distance_to(player_pos) > PICK_RANGE:
		return null
	return _pick_into(node, inventory)


## Same rules, driven directly (used by the developer picker and by tests, where
## there is no camera).
func try_pick(drop_node, inventory, player_pos: Vector3):
	if not _drops.has(drop_node):
		return null
	if drop_node.global_position.distance_to(player_pos) > PICK_RANGE:
		return null
	return _pick_into(drop_node, inventory)


func _pick_into(drop_node, inventory):
	if inventory == null:
		return null
	var it: Variant = drop_node.item
	if not inventory.add(it):
		# The bag is full: the item STAYS. Never destroy it.
		debug_full(drop_node)
		return null
	take(drop_node)
	item_picked.emit(it)
	return it


## Emitted so main.gd can put a line on screen. Kept as a signal rather than a
## direct HUD call, so the loot code has no UI dependency.
signal bag_full_of(item)

func debug_full(drop_node) -> void:
	bag_full_of.emit(drop_node.item)


## Walks up from a collider to the drop that owns it, without relying on node
## names - a name lookup is what breaks the moment there are two drops.
func _drop_of(c: Object) -> Node:
	var n := c as Node
	while n != null:
		if n is Node3D and _drops.has(n):
			return n
		n = n.get_parent()
	return null
