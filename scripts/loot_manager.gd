extends Node3D
## What monsters leave behind, World-of-Warcraft style: a BODY with the items
## inside it, not a carpet of objects on the floor.
##
## Jan's brief (Sept 2026): "maybe it is better if the items do not fall on the
## ground, but it is like in World of Warcraft - the player opens the body and
## picks the items out of it. For testing, make the drop chance 100 % now."
##
## So this class owns two things and nothing else:
##   * a BODY node per corpse (`scripts/loot_body.gd`) - placed near the corpse,
##     clear of geometry, with the items held as DATA (never as nodes);
##   * the OPENING rule: a tap that lands on a body within `OPEN_RANGE` returns
##     the items that were inside and leaves an empty body behind.
##
## The item is still pure data (`item.gd`), so the same object goes from the body
## into the bag without being re-parented - the rule that stops a save or a
## `queue_free` from duplicating or losing it.
##
## D2's rule for the drop POSITION survives: a body is thrown a short distance
## from where the monster fell, on a spot that is not inside a wall. It is never
## under the monster, because the player is standing there.

const LootBody := preload("res://scripts/loot_body.gd")
const ItemGen := preload("res://scripts/item_gen.gd")

## How far from the corpse the body is thrown, and how many spots are tried
## before giving up and leaving it where the monster fell.
const THROW_MIN := 0.7
const THROW_MAX := 1.6
const THROW_TRIES := 8

## How far a tap can reach a body. A little shorter than the old ground-drop
## range: a body is a thing you walk up to, and the rule has to read as such.
const OPEN_RANGE := 6.0

## Physics layer holding the bodies. Items used to be layer 2; the bags' own ray
## asks for 1|2, so a body on its own layer can never be mistaken for an item.
##
## The value mirrors `loot_body.LAYER_CORPSE`. It is a literal because GDScript 4
## cannot read a const out of a preloaded script in a `const` expression
## ("Invalid operands to operator |, int and Nil"), and `tools/test_panels.gd`
## asserts the two really agree so the duplication cannot drift.
const LAYER := 4

signal item_picked(item)
signal bag_full_of(item)
## A body was opened and gave up its items (may be empty when it had none).
signal body_opened(body, items)

var _bodies: Array = []
## body node -> Array of items still inside it.
var _loot: Dictionary = {}
## The camera, used to turn a screen tap into a world ray. Set by main.gd.
var camera: Camera3D


func _ready() -> void:
	camera = get_viewport().get_camera_3d()


## Rolls `ilvl`-appropriate loot for a monster that died and makes THAT MONSTER the
## corpse. Returns the number of items the body holds (0 means nothing to open).
##
## THE MONSTER ITSELF IS THE CORPSE - no second object is created. Jan's report
## (Sept 2026): "when an enemy dies, its corpse shows up as another separate object
## next to the real 3D model. I want the REAL corpse to be the one that gets picked
## - directly the 3D model that fought and died." So the enemy node, which already
## stays in the world after death, gets a label and a tap target as a CHILD, and its
## own rigged model is tipped over onto the ground.
##
## The enemy also stops colliding: a corpse must not block a step or swallow a
## swing, and both of those are layer 1 behaviours.
func spawn_for_death(enemy: Node3D, ilvl: int, rng: RandomNumberGenerator = null) -> int:
	if enemy == null or not is_instance_valid(enemy):
		return 0
	var items: Array = ItemGen.roll_drop(ilvl, rng)
	if items.is_empty():
		return 0
	var node: Node3D = LootBody.new()
	node.name = "Corpse"
	enemy.add_child(node)
	node.dress_corpse(enemy, str(enemy.monster_name))
	_bodies.append(node)
	_loot[node] = items
	return items.size()


## A STAND-IN body at `origin` holding `items`, for a test (or a chest later) where
## there is no monster to adopt. The real path is `spawn_for_death`.
##
## `monster_name` is what the body is LABELLED with: a body reading "Tělo: krátký
## meč" tells the player the wrong thing about what is lying there.
func spawn_body(origin: Vector3, items: Array, rng: RandomNumberGenerator = null,
		monster_name: String = "?") -> Node3D:
	var node: Node3D = LootBody.new()
	node.name = "Body_%d" % (_bodies.size() + 1)
	add_child(node)
	node.setup(monster_name)
	node.global_position = _find_clear_spot(origin, rng)
	_bodies.append(node)
	_loot[node] = items
	return node


## D2's placement rule, unchanged: try a handful of throw angles, take the first
## clear one, fall back to the corpse spot so the body is never lost.
func _find_clear_spot(origin: Vector3, rng: RandomNumberGenerator = null) -> Vector3:
	var r: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
	r.randomize()
	var best := origin
	for i in THROW_TRIES:
		var a := r.randf_range(0.0, TAU)
		var d := r.randf_range(THROW_MIN, THROW_MAX)
		var p := origin + Vector3(cos(a) * d, 0.0, sin(a) * d)
		p = _snap_to_ground(p)
		if _spot_is_clear(p):
			return p
	return _snap_to_ground(best)


## A body must not sit inside a wall or a prop, and must not sit ON another body:
## two corpses in one spot read as one corpse and the second one's loot becomes
## very hard to tap. Measured: without the second query a pack killed in one place
## produced bodies 0.04 m apart, i.e. inside each other.
##
## Two queries, because the two obstacles live on different layers: the level is on
## layer 1 (static bodies), the bodies are Area3D on layer 4 - and an Area3D is
## invisible to a query that does not ask for areas.
func _spot_is_clear(p: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.40
	var at := Transform3D(Basis(), p + Vector3(0, 0.35, 0))

	# 1. the level
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = at
	q.collision_mask = 1
	var hits: Array = space.intersect_shape(q, 4)
	for h in hits:
		var c: Object = h["collider"]
		# the floor is on layer 1 too; a body ON the floor is the normal case
		if c is StaticBody3D and c.name == "FloorBody":
			continue
		return false

	# 2. the bodies already lying there
	var q2 := PhysicsShapeQueryParameters3D.new()
	q2.shape = shape
	q2.transform = at
	q2.collision_mask = LAYER
	q2.collide_with_areas = true
	var hits2: Array = space.intersect_shape(q2, 8)
	if not hits2.is_empty():
		return false
	return true


## Bodies lie on the ground plane. The floor is flat and at y = 0, so this is a
## constant rather than a raycast - a raycast here would find the body's own
## Area3D and report a self-collision.
func _snap_to_ground(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)


# ------------------------------------------------------------------- inspection
## Every body in the world, for tests and for the debug line.
func bodies() -> Array:
	return _bodies.duplicate()


func body_count() -> int:
	return _bodies.size()


## The items still inside a body. Empty array when the body is empty or unknown.
func items_in(body) -> Array:
	if not _loot.has(body):
		return []
	return (_loot[body] as Array).duplicate()


## Total items left on the ground inside every body. What the old `drop_count()`
## answered, kept because the kill wiring is measured with it.
func drop_count() -> int:
	var n := 0
	for b in _loot:
		n += (_loot[b] as Array).size()
	return n


func clear() -> void:
	for b in _bodies:
		if is_instance_valid(b):
			b.queue_free()
	_bodies.clear()
	_loot.clear()


# --------------------------------------------------------------------- opening
## The screen-space tap that opens a body. Ray from the camera through the tap,
## then look for a body among the colliders: its own Area3D covers the bundle and
## the label, so "tap the body" and "tap its name" are one code path.
##
## Mask 1|4: a wall between the camera and the body must block the tap, while the
## bodies themselves live on their own layer. `collide_with_areas` is required -
## a body is an Area3D on purpose, so it never blocks a step.
##
## Returns the items the body held, or null when the tap hit nothing openable.
func open_at_screen(screen_pos: Vector2, player_pos: Vector3) -> Variant:
	if camera == null or not camera.is_inside_tree():
		camera = get_viewport().get_camera_3d()
		if camera == null:
			return null
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	q.collision_mask = 1 | LAYER
	q.collide_with_areas = true
	var res: Dictionary = space.intersect_ray(q)
	if res.is_empty():
		return null
	var node: Node = _body_of(res["collider"])
	if node == null:
		return null
	if node.global_position.distance_to(player_pos) > OPEN_RANGE:
		return null
	return open(node)


## Same rules, driven directly (used by tests, where there is no camera).
##
## OPENING IS NOT TAKING. This returns what is inside and marks the body as
## looked-at; it does NOT empty it. Two reasons, and both are the kind of thing
## that reads as a bug to a player:
##   * closing the window without taking anything must leave the loot where it was
##     - "I opened it, looked, and the items were gone" is a lost rare;
##   * an `open()` that consumed the contents made the two entry points to the same
##     body fight each other: the panel's per-item `take_item()` found nothing left
##     to take. Measured: `take_item` returned null on a body that had just been
##     opened, with an empty bag and a legal cell.
func open(body, player_pos: Vector3 = Vector3.ZERO) -> Variant:
	if not _bodies.has(body):
		return null
	if player_pos != Vector3.ZERO and body.global_position.distance_to(player_pos) > OPEN_RANGE:
		return null
	var items: Array = _loot.get(body, [])
	body.opened = true
	if body.label != null:
		# Read, not taken: the label dims so the player can see he has already been
		# in this one, which is how a field of five bodies stays readable.
		body.label.modulate = Color(0.72, 0.68, 0.60) if not items.is_empty() \
			else Color(0.45, 0.42, 0.37)
	body_opened.emit(body, items)
	return items.duplicate()


## Walks up from a collider to the body that owns it, without relying on node
## names - a name lookup is what breaks the moment there are two bodies.
func _body_of(c: Object) -> Node3D:
	var n := c as Node
	while n != null:
		if n is Node3D and _bodies.has(n):
			return n as Node3D
		n = n.get_parent()
	return null


# ----------------------------------------------------------------- bag transfer
## Moves ONE item from an OPENED body's item list into the bag. The UI calls this
## per item, so a refusal (full bag) leaves that item in the list and the others
## untouched rather than dropping the rest on the floor.
##
## Returns the item on success, null when it did not fit.
func take_item(body, item, inventory):
	if inventory == null or body == null or not _loot.has(body):
		return null
	var items: Array = _loot[body]
	if not items.has(item):
		return null
	if not inventory.add(item):
		# The bag is full: the item STAYS in the body. Never destroy it.
		bag_full_of.emit(item)
		return null
	items.erase(item)
	item_picked.emit(item)
	return item
