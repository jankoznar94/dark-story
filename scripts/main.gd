extends Node3D
## Prototype scene wiring. Headless-safe: no rendering calls.

@onready var player: CharacterBody3D = $Player
@onready var cam: Camera3D = $Camera
@onready var hud: CanvasLayer = $HUD

var _posts: Array[Node] = []
var _hits: Array = []


func _ready() -> void:
	_setup_world()
	_spawn_posts()
	player.attack_landed.connect(_on_landed)


func _setup_world() -> void:
	## Atmosphere lives in light + fog, not in textures. All of this works
	## in Mobile AND Compatibility, so a web export costs us nothing here.
	##
	## Lighting was lifted after Jan's report: "everything is the same terrible
	## dark brown - objects, floor, clothes. The world needs a little light and
	## life so the contrasts stand out." Measured on the old settings, the game
	## frame had a per-pixel p10 of 23.3 against a p90 of 23.5 (i.e. almost no
	## tonal range at all) and 87.8 % of the image was ONE brown, rgb(32,16,8).
	## The cause was ambient light carrying almost all the illumination while the
	## sun contributed 0.55, so every surface received the same flat brownish wash
	## and nothing had a lit side and a shadow side.
	##
	## The fix is more DIRECTIONAL light and less flat ambient - contrast comes
	## from the sun, not from raising the ambient floor. The tone is still dark:
	## the sun is warm, the shadow side stays cool and deep.
	var we := WorldEnvironment.new()
	var env := Environment.new()

	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.030, 0.028, 0.026)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	## was Color(0.16, 0.135, 0.115) @ 0.75 - a flat warm wash on everything.
	## Second pass: 0.20/0.42 rendered the scene cheerful and washed out (measured
	## p10 90.7, and the sky-facing surfaces clipped), so this sits between the two.
	env.ambient_light_color = Color(0.14, 0.135, 0.125)
	env.ambient_light_energy = 0.34

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_brightness = 0.94
	env.adjustment_contrast = 1.20
	## was 0.82 - desaturating that far turned green grass back into brown
	env.adjustment_saturation = 0.86

	# depth/height fog: supported in every renderer (volumetric fog is Forward+ only)
	env.fog_enabled = true
	env.fog_light_color = Color(0.115, 0.105, 0.095)
	env.fog_light_energy = 0.6
	## was 0.028 - thick enough to grey out the far half of a 34 m floor
	env.fog_density = 0.018
	env.fog_aerial_perspective = 0.0

	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	## was 0.55 - the main source of the flatness: a 0.55 key against 0.75 ambient
	## is barely directional, so nothing had a readable lit face. 1.25 then washed
	## the scene out; 0.95 keeps a readable lit side without lifting the shadow.
	sun.light_energy = 0.95
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.02
	## Full-strength shadows rendered as hard black cutouts on the grass (reported
	## back after the first render). Partial opacity keeps the direction readable
	## while the shadowed ground stays grass-coloured instead of turning black.
	sun.shadow_opacity = 0.62
	sun.shadow_blur = 1.6
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	add_child(sun)

	# A cool fill from the opposite side so the shadow side is readable instead of
	# black. Kept well under the sun so the direction still reads.
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_energy = 0.22
	fill.light_color = Color(0.62, 0.70, 0.88)
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-24.0, 142.0, 0.0)
	add_child(fill)


func _spawn_posts() -> void:
	## Three inert posts so we can check that a swing lands where it looks like it lands.
	var spots := [Vector3(0, 0, -3.2), Vector3(2.6, 0, -1.0), Vector3(-2.4, 0, -2.0)]
	for i in spots.size():
		var body := StaticBody3D.new()
		body.set_script(load("res://scripts/target_post.gd"))
		body.position = spots[i]

		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 1.3, 0.5)
		mi.mesh = bm
		body.add_child(mi)

		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.5, 1.3, 0.5)
		cs.shape = bs
		body.add_child(cs)

		add_child(body)
		_posts.append(body)


func _process(_delta: float) -> void:
	var st: String = player.state_name()
	var f: Vector3 = player.facing
	hud.set_debug("state: %s   facing: %+.2f,%+.2f   %s" % [st, f.x, f.z, player.debug_text])


func _on_landed(kind: String, collider: Node, point: Vector3) -> void:
	_hits.append({"kind": kind, "who": collider.name})
	print("[hit] %s on %s at %s" % [kind, collider.name, point])
