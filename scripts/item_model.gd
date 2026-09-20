extends RefCounted
## Builds the 3D model of an item from its SHAPE key - the same key the inventory
## icon uses, so the thing lying on the ground and the picture in the bag are one
## object and cannot drift apart.
##
## Art rules that apply here as much as to the props: cheap geometry, a silhouette
## that reads at a glance, ONE flat warm-desaturated material per part, no glow.
## The shapes are built from primitives because a dropped sword is 30 px on
## screen - the detail budget belongs in the silhouette (a distinct guard, a
## distinct head), never in surface detail.

## The palette. Warm, dark, desaturated. Steel reads cold-blue-grey against the
## brown ground, which is what makes a drop visible without any glow.
const COL_STEEL := Color(0.44, 0.45, 0.48)
const COL_WOOD := Color(0.26, 0.19, 0.13)
const COL_LEATHER := Color(0.30, 0.21, 0.14)
const COL_GOLD := Color(0.52, 0.42, 0.20)
const COL_CLOTH := Color(0.30, 0.27, 0.24)
const COL_GEM := Color(0.42, 0.20, 0.24)

## Scale applied to the finished model so a halberd is visibly longer than a
## dagger when both lie on the ground.
const SHAPE_LENGTH := {
	"dagger": 0.45, "sword": 0.95, "axe": 0.75, "mace": 0.80, "hammer": 0.85,
	"polearm": 1.55, "shield": 0.70, "armor": 0.80, "helm": 0.45,
	"gloves": 0.35, "boots": 0.42, "belt": 0.55, "ring": 0.10, "amulet": 0.18,
}


static func build(shape: String, tint: Color = Color(1, 1, 1)) -> Node3D:
	var root := Node3D.new()
	root.name = "ItemModel_" + shape
	match shape:
		"sword": _sword(root, 1.0)
		"dagger": _sword(root, 0.55)
		"axe": _axe(root)
		"mace": _mace(root)
		"hammer": _hammer(root)
		"polearm": _polearm(root)
		"shield": _shield(root)
		"armor": _armor(root)
		"helm": _helm(root)
		"gloves": _gloves(root)
		"boots": _boots(root)
		"belt": _belt(root)
		"ring": _ring(root)
		"amulet": _amulet(root)
		_:
			_box(root, Vector3(0.3, 0.3, 0.3), Vector3.ZERO, COL_WOOD)
	if tint != Color(1, 1, 1):
		for c in root.get_children():
			if c is MeshInstance3D:
				var m: StandardMaterial3D = (c as MeshInstance3D).material_override
				if m:
					m.albedo_color = m.albedo_color * tint
	return root


## --------------------------------------------------------------- primitives
static func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.92
	m.metallic = 0.0
	return m


static func _add(root: Node3D, mesh: Mesh, pos: Vector3, col: Color,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(col)
	mi.position = pos
	mi.rotation_degrees = rot
	root.add_child(mi)
	return mi


static func _box(root: Node3D, size: Vector3, pos: Vector3, col: Color,
		rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return _add(root, bm, pos, col, rot)


static func _cyl(root: Node3D, r: float, h: float, pos: Vector3, col: Color,
		rot: Vector3 = Vector3.ZERO, seg: int = 8) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	return _add(root, cm, pos, col, rot)


static func _sphere(root: Node3D, r: float, pos: Vector3, col: Color,
		scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	var mi := _add(root, sm, pos, col)
	mi.scale = scale
	return mi


## -------------------------------------------------------------- the shapes
## A blade points along +Y (up) in local space; the ground spawner tips it over
## so it lies down, D2 style.
static func _sword(root: Node3D, scale: float) -> void:
	var blade_h := 0.62 * scale
	_box(root, Vector3(0.075 * scale, blade_h, 0.026 * scale),
		Vector3(0, 0.22 * scale + blade_h * 0.5, 0), COL_STEEL)
	# a tapered tip so the silhouette does not read as a rectangle
	var tip := PrismMesh.new()
	tip.size = Vector3(0.075 * scale, 0.10 * scale, 0.026 * scale)
	_add(root, tip, Vector3(0, 0.22 * scale + blade_h + 0.05 * scale, 0), COL_STEEL)
	_box(root, Vector3(0.26 * scale, 0.035 * scale, 0.045 * scale),
		Vector3(0, 0.21 * scale, 0), COL_STEEL)              # crossguard
	_cyl(root, 0.017 * scale, 0.15 * scale, Vector3(0, 0.13 * scale, 0), COL_LEATHER)
	_sphere(root, 0.028 * scale, Vector3(0, 0.045 * scale, 0), COL_GOLD)


static func _axe(root: Node3D) -> void:
	_cyl(root, 0.022, 0.70, Vector3(0, 0.10, 0), COL_WOOD)
	# the head: a wedge that only exists on one side, which is what an axe reads as
	var head := PrismMesh.new()
	head.size = Vector3(0.22, 0.30, 0.05)
	_add(root, head, Vector3(0.13, 0.38, 0), COL_STEEL, Vector3(0, 0, -90))
	_box(root, Vector3(0.04, 0.16, 0.07), Vector3(0.04, 0.38, 0), COL_STEEL)


static func _mace(root: Node3D) -> void:
	_cyl(root, 0.024, 0.62, Vector3(0, 0.06, 0), COL_WOOD)
	_sphere(root, 0.105, Vector3(0, 0.42, 0), COL_STEEL)
	# four studs, cheap and enough to read as a mace rather than a ball on a stick
	for a in [0.0, 90.0, 180.0, 270.0]:
		var d := Vector3(cos(deg_to_rad(a)), 0.0, sin(deg_to_rad(a))) * 0.10
		_box(root, Vector3(0.035, 0.035, 0.035), Vector3(0, 0.42, 0) + d, COL_STEEL)


static func _hammer(root: Node3D) -> void:
	_cyl(root, 0.026, 0.66, Vector3(0, 0.08, 0), COL_WOOD)
	_box(root, Vector3(0.26, 0.16, 0.14), Vector3(0, 0.44, 0), COL_STEEL)
	_box(root, Vector3(0.05, 0.14, 0.12), Vector3(-0.14, 0.44, 0), COL_GOLD)


static func _polearm(root: Node3D) -> void:
	_cyl(root, 0.026, 1.34, Vector3(0, 0.05, 0), COL_WOOD)
	var blade := PrismMesh.new()
	blade.size = Vector3(0.13, 0.40, 0.035)
	_add(root, blade, Vector3(0, 0.86, 0), COL_STEEL)
	_box(root, Vector3(0.20, 0.04, 0.05), Vector3(0, 0.68, 0), COL_STEEL)


static func _shield(root: Node3D) -> void:
	_box(root, Vector3(0.46, 0.60, 0.055), Vector3(0, 0.03, 0), COL_WOOD)
	# a boss in the middle and a band across the top: two cheap reads of "shield"
	_sphere(root, 0.075, Vector3(0, 0.03, 0.045), COL_STEEL,
		Vector3(1.0, 1.0, 0.5))
	_box(root, Vector3(0.48, 0.06, 0.03), Vector3(0, 0.28, 0.035), COL_STEEL)


static func _armor(root: Node3D) -> void:
	# a torso with two shoulders, tapering - NOT a cube (the art rule)
	_box(root, Vector3(0.40, 0.52, 0.20), Vector3(0, 0.0, 0), COL_LEATHER)
	_box(root, Vector3(0.46, 0.16, 0.22), Vector3(0, 0.26, 0), COL_CLOTH)
	_box(root, Vector3(0.14, 0.30, 0.20), Vector3(-0.26, 0.18, 0), COL_LEATHER)
	_box(root, Vector3(0.14, 0.30, 0.20), Vector3(0.26, 0.18, 0), COL_LEATHER)
	_box(root, Vector3(0.10, 0.46, 0.02), Vector3(0, 0.0, 0.11), COL_STEEL)


static func _helm(root: Node3D) -> void:
	_sphere(root, 0.17, Vector3(0, 0.06, 0), COL_STEEL, Vector3(1.0, 0.85, 1.0))
	_cyl(root, 0.20, 0.045, Vector3(0, -0.04, 0), COL_STEEL, Vector3.ZERO, 10)
	_box(root, Vector3(0.03, 0.14, 0.12), Vector3(0, 0.03, 0.15), COL_LEATHER)


static func _gloves(root: Node3D) -> void:
	_box(root, Vector3(0.13, 0.16, 0.09), Vector3(0, 0.0, 0), COL_LEATHER)
	for i in 3:
		_box(root, Vector3(0.03, 0.10, 0.045),
			Vector3(-0.04 + 0.04 * i, 0.13, 0), COL_LEATHER)
	_box(root, Vector3(0.05, 0.05, 0.05), Vector3(-0.09, -0.04, 0.01), COL_LEATHER)


static func _boots(root: Node3D) -> void:
	_box(root, Vector3(0.13, 0.07, 0.30), Vector3(0, -0.06, 0.04), COL_LEATHER)
	_cyl(root, 0.075, 0.20, Vector3(0, 0.06, -0.06), COL_LEATHER)
	_box(root, Vector3(0.14, 0.03, 0.31), Vector3(0, -0.10, 0.04), COL_WOOD)


static func _belt(root: Node3D) -> void:
	_box(root, Vector3(0.52, 0.09, 0.035), Vector3(0, 0, 0), COL_LEATHER)
	_box(root, Vector3(0.10, 0.13, 0.05), Vector3(0.06, 0, 0.01), COL_GOLD)
	_sphere(root, 0.022, Vector3(0.06, 0.0, 0.03), COL_GEM, Vector3(1, 1, 0.6))


static func _ring(root: Node3D) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = 0.030
	tm.outer_radius = 0.055
	tm.rings = 8
	tm.ring_segments = 6
	var mi := _add(root, tm, Vector3.ZERO, COL_GOLD)
	mi.rotation_degrees = Vector3(90, 0, 0)
	_sphere(root, 0.022, Vector3(0, 0.05, 0), COL_GEM, Vector3(1, 1, 0.7))


static func _amulet(root: Node3D) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = 0.055
	tm.outer_radius = 0.070
	tm.rings = 10
	tm.ring_segments = 6
	_add(root, tm, Vector3(0, 0.04, 0), COL_GOLD)
	_sphere(root, 0.032, Vector3(0, 0.0, 0), COL_GEM, Vector3(1, 1.4, 0.7))
