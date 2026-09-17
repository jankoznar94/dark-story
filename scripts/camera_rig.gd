extends Camera3D
## Fixed isometric ARPG camera. Follows the player, never rotates with input.
## D1/D2 style: distant, narrow FOV, slight downward tilt.

@export var target_path: NodePath
@export var offset: Vector3 = Vector3(0.0, 12.5, 9.0)
@export var cam_fov: float = 32.0
@export var follow_speed: float = 7.0
@export var look_height: float = 0.6

var _target: Node3D


func _ready() -> void:
	projection = PROJECTION_PERSPECTIVE
	fov = cam_fov
	current = true
	_target = get_node_or_null(target_path)
	if _target:
		global_position = _target.global_position + offset


func _process(delta: float) -> void:
	if _target == null:
		return
	var goal := _target.global_position + offset
	global_position = global_position.lerp(goal, clampf(follow_speed * delta, 0.0, 1.0))
	look_at(_target.global_position + Vector3(0, look_height, 0), Vector3.UP)
