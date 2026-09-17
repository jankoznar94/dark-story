extends StaticBody3D
## Inert training post. Does NOT attack, does NOT move. Only registers hits
## so we can verify that a directional swing actually lands where it looks like it lands.

@onready var mesh: MeshInstance3D = $Mesh
var _flash: float = 0.0
var _mat: StandardMaterial3D


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.30, 0.26, 0.21)
	mesh.material_override = _mat


func take_hit(kind) -> void:
	_flash = 0.25
	_mat.albedo_color = Color(0.85, 0.35, 0.20)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			_mat.albedo_color = Color(0.30, 0.26, 0.21)
