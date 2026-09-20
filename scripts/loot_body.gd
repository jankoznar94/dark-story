extends Node3D
## ONE corpse with loot in it.
##
## Jan's change of model (Sept 2026): items no longer lie on the ground. "Maybe
## it is better if the items do not fall on the ground, but it is like in World
## of Warcraft - the player opens the body and picks the items out of it."
## So a kill leaves a BODY, the items live inside it as data (see
## `loot_manager.gd`), and the player opens it and takes what he wants.
##
## What this node is: the thing the player SEES and TAPS. A slumped bundle plus a
## label naming the monster. What it is NOT: an item - its Area3D sits on its own
## layer (4) with an empty mask, so the item pickup ray (mask 1|2) never mistakes
## a corpse for a drop, and a corpse never blocks a step.

const LAYER_CORPSE := 4

## The name floats at this height; the click box covers the bundle and the label.
const NAME_HEIGHT := 0.42
const PICK_BOX := Vector3(0.9, 0.9, 0.9)

const COL_BODY := Color(0.16, 0.13, 0.12)
const COL_TEXT := Color(0.72, 0.66, 0.55)

var monster_name: String = "?"
## True once the player has looked inside. Only used to dim the label - the loot
## itself is untouched by opening it (see loot_manager.gd::open).
var opened: bool = false
var label: Label3D
var _area: Area3D


## Sets the body's name. TWO PATHS ON PURPOSE: the node is added to the tree
## before it is positioned (so `_ready()` already built it), which means `_build()`
## returns early on its own guard and a rebuild would be a silent no-op - measured:
## every body in the game was labelled "Tělo: ?" because of exactly that. So when
## the meshes already exist, only the LABEL is updated.
func setup(p_name: String, tint: Color = COL_BODY) -> void:
	monster_name = p_name
	if not is_inside_tree():
		return
	if _area == null:
		_build(tint)
		return
	if label != null:
		label.text = "Tělo: %s" % monster_name


func _ready() -> void:
	_build(COL_BODY)


func _build(tint: Color) -> void:
	if _area != null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint.darkened(0.25)
	mat.roughness = 0.98
	mat.metallic = 0.0

	# A slumped bundle, not a cube: a body lying on its side. Cheap primitives,
	# readable silhouette - the same rule every prop follows.
	var torso := MeshInstance3D.new()
	torso.name = "Torso"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.62, 0.34, 0.42)
	torso.mesh = bm
	torso.position = Vector3(0, 0.17, 0)
	torso.material_override = mat
	add_child(torso)

	var head := MeshInstance3D.new()
	head.name = "Head"
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	sm.radial_segments = 10
	sm.rings = 5
	head.mesh = sm
	head.position = Vector3(0.34, 0.16, 0.05)
	head.material_override = mat
	add_child(head)

	var limb := MeshInstance3D.new()
	limb.name = "Limb"
	var lm := BoxMesh.new()
	lm.size = Vector3(0.5, 0.14, 0.16)
	limb.mesh = lm
	limb.position = Vector3(-0.42, 0.10, -0.12)
	limb.rotation_degrees = Vector3(0, 22, 0)
	limb.material_override = mat
	add_child(limb)

	label = Label3D.new()
	label.name = "Name"
	label.text = "Tělo: %s" % monster_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 34
	label.pixel_size = 0.0030
	label.outline_size = 8
	label.outline_modulate = Color(0.05, 0.04, 0.035, 0.95)
	label.modulate = COL_TEXT
	label.position = Vector3(0, NAME_HEIGHT, 0)
	add_child(label)

	_area = Area3D.new()
	_area.name = "Open"
	_area.collision_layer = LAYER_CORPSE
	# mask 0: the body is what the OPENING ray looks for, never what it blocks
	_area.collision_mask = 0
	_area.monitoring = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = PICK_BOX
	cs.shape = bs
	cs.position = Vector3(0, 0.25, 0)
	_area.add_child(cs)
	add_child(_area)
