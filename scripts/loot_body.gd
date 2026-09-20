extends Node3D
## A corpse the player can open. TWO WAYS TO GET ONE, and the difference matters:
##
##   1. `dress_corpse(enemy)` - THE REAL ONE. Jan's report (Sept 2026): "when an
##      enemy dies, its corpse shows up as another separate object next to the real
##      3D model. I want the REAL corpse to be the one that gets picked - directly
##      the 3D model that fought and died." So on death the monster's OWN rigged
##      model is kept, tipped over onto the ground, and this node only adds the
##      label and the tap target to it. Nothing new is drawn.
##   2. `_build()` - a stand-in bundle, for a hand-built body (a test, or a chest
##      later) where there is no model to adopt.
##
## The tap target is an `Area3D` on its OWN layer (4) with mask 0: it never blocks a
## step, and it can never be mistaken for an item by the bag's own ray (layer 2).

const LAYER_CORPSE := 4

## The label floats at this height; the click box is wide enough to cover a body
## lying down, which is why it is not a small cube.
const NAME_HEIGHT := 0.55
const PICK_BOX := Vector3(1.5, 1.0, 1.5)

const COL_BODY := Color(0.16, 0.13, 0.12)
const COL_TEXT := Color(0.72, 0.66, 0.55)

var monster_name: String = "?"
## True once the player has looked inside. Only used to dim the label - the loot
## itself is untouched by opening it (see loot_manager.gd::open).
var opened: bool = false
## The model that is the corpse: the monster's own, or the built stand-in.
var model: Node3D = null
var label: Label3D
var _area: Area3D
var _built: bool = false


func setup(p_name: String, tint: Color = COL_BODY) -> void:
	monster_name = p_name
	if not is_inside_tree():
		return
	if _area == null:
		_build(tint)
		return
	if label != null:
		label.text = "Tělo: %s" % monster_name


## KEEPS THIS MONSTER'S OWN MODEL as the corpse and tips it over. Called by
## loot_manager when a monster dies, so the thing the player walks up to and taps is
## the body that fought him - same rig, same tint, same death pose.
func dress_corpse(enemy: Node3D, p_name: String) -> void:
	monster_name = p_name
	model = enemy
	# --- tip it onto the ground --------------------------------------------------
	# The rig stands with its feet at y = 0, so a rotation about X lays it out along
	# Z from where it fell. Rotated in the DEATH POSE rather than reset to the rest
	# pose: the last frame the player saw is the one that stays.
	if enemy.has_method("get_model_root") and enemy.get_model_root() != null:
		var mr: Node3D = enemy.get_model_root()
		mr.rotation_degrees = Vector3(-82.0, mr.rotation_degrees.y, 8.0)
		mr.position.y = 0.14
	_add_label()
	_add_area()
	_built = true


func _ready() -> void:
	if not _built:
		_build(COL_BODY)


## The stand-in for a hand-built body. A slumped bundle, not a cube - the same
## silhouette rule every prop in this game follows.
func _build(tint: Color) -> void:
	if _built:
		return
	_built = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint.darkened(0.25)
	mat.roughness = 0.98
	mat.metallic = 0.0

	var torso := MeshInstance3D.new()
	torso.name = "Torso"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.62, 0.34, 0.42)
	torso.mesh = bm
	torso.position = Vector3(0, 0.17, 0)
	torso.material_override = mat
	add_child(torso)
	model = torso

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

	_add_label()
	_add_area()


func _add_label() -> void:
	if label != null:
		label.text = "Tělo: %s" % monster_name
		return
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


func _add_area() -> void:
	if _area != null:
		return
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
	cs.position = Vector3(0, 0.30, 0)
	_area.add_child(cs)
	add_child(_area)
