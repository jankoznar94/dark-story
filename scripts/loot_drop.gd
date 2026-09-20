extends Node3D
## ONE item lying on the ground: its 3D model, its NAME above it, and the click
## target that picks it up.
##
## Jan's brief: "loot falls on the ground, you pick it up from there. You can see
## both the weapon model lying on the ground and its name. Clicking the name
## picks the item up into the inventory."
##
## Two decisions worth keeping:
##   * the click target is an Area3D, NOT a StaticBody3D - an item must never
##     block a step. Diablo does not let a dropped sword stop you either, and a
##     solid body here would also fight the trimesh prop collisions.
##   * the SAME `shape` key drives this model and the inventory icon
##     (scripts/item_icon.gd), so the object on the ground and the picture in the
##     bag are one object seen twice.

const ItemModel := preload("res://scripts/item_model.gd")

## Physics layer 2. The player, monsters and props stay on layer 1, and the pickup
## ray asks for 1|2 so a wall between the camera and an item still blocks the pick.
const LAYER := 2

## The name floats at this height, and the click box is tall enough to cover both
## the name and the model, so a player who taps the sword also picks it up.
const NAME_HEIGHT := 0.52
const PICK_BOX := Vector3(0.95, 1.05, 0.95)

var item: Variant = null
var label: Label3D
var _body: Area3D
var _model: Node3D


func _ready() -> void:
	_build()


func setup(p_item) -> void:
	item = p_item
	if is_inside_tree():
		_build()


func _build() -> void:
	if item == null:
		return
	for c in get_children():
		c.queue_free()
	_model = ItemModel.build(str(item.base().get("shape", "sword")))
	# A dropped item LIES on the ground, tipped over, D2 style - a sword standing
	# on its point reads as a fence post.
	_model.rotation_degrees = Vector3(-90.0, 20.0, 12.0)
	_model.position = Vector3(0, 0.06, 0)
	add_child(_model)

	label = Label3D.new()
	label.name = "Name"
	label.text = item.display_name()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.fixed_size = false
	label.font_size = 44
	label.pixel_size = 0.0032
	label.outline_size = 8
	label.outline_modulate = Color(0.05, 0.04, 0.035, 0.95)
	label.modulate = item.rarity_color()
	label.position = Vector3(0, NAME_HEIGHT, 0)
	add_child(label)

	_body = Area3D.new()
	_body.name = "Pick"
	_body.collision_layer = LAYER
	_body.collision_mask = 0
	# An Area3D never blocks movement, and it is what the pickup ray looks for.
	_body.monitoring = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = PICK_BOX
	cs.shape = bs
	cs.position = Vector3(0, NAME_HEIGHT * 0.5, 0)
	_body.add_child(cs)
	add_child(_body)


## Called by the pickup code when a click ray lands on this item.
func pick_up() -> bool:
	return true


## Placed by the spawner at a spot that is clear of geometry, so two drops never
## sit inside one another.
func drop_at(p: Vector3) -> void:
	global_position = p
