extends SceneTree
## "Jak bude hra reálně vypadat" - renders the ACTUAL game scene (same camera as
## scripts/camera_rig.gd, same level, same models, same HUD) in three states:
##   1) hero standing opposite an enemy   2) hero mid attack swing
##   3) hero running away with the enemy behind him
##
##   godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##         --script res://tools/render_look.gd
##
## Everything is FROZEN: the camera's follow, the player's _process (which would
## overwrite the clip from _physics_process), the monsters' AI, and finally the
## AnimationPlayer itself (speed_scale = 0 after seek). Without the last one the
## pose drifts between the seek and the framebuffer read - measured here, the
## software renderer needs ~100 ms per frame, so a settled 3-frame wait moved the
## swing from 0.52 s to 0.80 s.
##
## Screen mapping of the game camera (offset (0, 12.5, 9), fov 32, look 0.6):
##   screen RIGHT = world +X, screen UP = world -Z, screen DOWN-RIGHT is nearest
##   to the camera. The HUD owns the bottom-right corner, so actors stay inside
##   |x| < 4, |z| < 3.

const OUT := "/tmp/ds_look"

var t := 0.0
var scene: Node3D
var player: CharacterBody3D
var hero: Node3D
var cam: Camera3D

var _step := 0
var _frames := 0
var _shots := 0

const POSES := [
	"01_stoj_proti_sobe",
	"02_uprostred_utoku",
	"03_utek",
]


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	scene = packed.instantiate()
	root.add_child(scene)
	player = scene.get_node_or_null("Player")
	cam = scene.get_node_or_null("Camera")
	if cam:
		cam.set_process(false)
	if player:
		player.set_physics_process(false)
		player.set_process(false)
		hero = player.get_node_or_null("Hero")
	DirAccess.make_dir_recursive_absolute(OUT)
	print("LOOK_RENDER_SETUP player=", player, " hero=", hero)


## Monsters are built by main.gd in _ready(), and their steering would walk them
## out of the frame - so they are found and frozen on the FIRST frame instead.
func _freeze_enemies() -> int:
	var n := 0
	for c in scene.get_children():
		if str(c.name).begins_with("Enemy_"):
			c.set_physics_process(false)
			c.set_process(false)
			n += 1
	return n


func _enemies() -> Array:
	var out: Array = []
	for c in scene.get_children():
		if str(c.name).begins_with("Enemy_"):
			if c.has_method("play_idle"):
				c.play_idle()
			out.append(c)
	return out


func _hero_anim() -> AnimationPlayer:
	return hero.anim if hero != null and "anim" in hero else null


func _place(pos: Vector3, facing: Vector3) -> void:
	player.position = pos
	player.facing = facing.normalized()
	player.rotation.y = atan2(-facing.x, -facing.z)


func _place_enemy(e: Node3D, pos: Vector3, facing: Vector3) -> void:
	e.position = pos
	e.rotation.y = atan2(-facing.x, -facing.z)


## Play a clip and HOLD it: seek to the wanted time, then stop the clock so the
## pose cannot drift before the capture.
func _hold(anim: AnimationPlayer, clip: String, at: float, speed: float) -> void:
	anim.play(clip, -1.0, 1.0)
	anim.speed_scale = speed
	anim.seek(at, true)
	anim.speed_scale = 0.0


func _configure(i: int) -> String:
	var es := _enemies()
	var ghoul: Node3D = es[0] if es.size() > 0 else null
	var ghoul2: Node3D = es[1] if es.size() > 1 else null
	var anim := _hero_anim()
	if anim == null:
		return "no_animation_player"
	match i:
		0:
			# standing off, both still, a few metres of ground between them
			_place(Vector3(-2.0, 0.0, 0.6), Vector3(1, 0, 0))
			_hold(anim, "Rig|Sword_Idle", 0.4, 1.0)
			if ghoul:
				_place_enemy(ghoul, Vector3(0.6, 0.0, 0.2), Vector3(-1, 0, 0))
			if ghoul2:
				_place_enemy(ghoul2, Vector3(-5.0, 0.0, -2.0), Vector3(0, 0, 1))
		1:
			# mid swing: the light attack's ACTIVE frame sits at 0.42-0.58 s, and the
			# blade has to be at the monster - 1.75 m is inside the 1.7 m reach
			_place(Vector3(-1.2, 0.0, 0.4), Vector3(1, 0, 0))
			_hold(anim, "Rig|Sword_Attack", 0.50, 1.0)
			if ghoul:
				_place_enemy(ghoul, Vector3(0.5, 0.0, 0.1), Vector3(-1, 0, 0))
			if ghoul2:
				_place_enemy(ghoul2, Vector3(-5.5, 0.0, -3.0), Vector3(0, 0, 1))
		2:
			# running away to screen left, pursuer behind him and nearer the camera so
			# it reads as "one is chasing the other"
			_place(Vector3(-0.4, 0.0, 0.6), Vector3(-1, 0, 0))
			_hold(anim, "Rig|Jog_Fwd", 0.35, clampf(3.05 / 2.010, 0.2, 4.0))
			if ghoul:
				_place_enemy(ghoul, Vector3(2.8, 0.0, 1.8), Vector3(-1, 0, 0))
			if ghoul2:
				_place_enemy(ghoul2, Vector3(3.2, 0.0, 0.1), Vector3(-1, 0, 0))
	# the HUD would otherwise overwrite the hero's clip from _physics_process
	if player:
		player.set_physics_process(false)
		player.set_process(false)
	var epos := []
	for e in es:
		epos.append("%s@%s" % [e.name, e.position])
	print("COMPOSITION %d hero@%s enemies %s" % [i, player.position, str(epos)])
	return "ok"


func _process(delta: float) -> bool:
	t += delta
	# let the scene build, the level load and the first frame draw
	if t < 1.5:
		return false
	if _step == 0:
		if _shots == 0:
			print("ENEMIES_FROZEN %d" % _freeze_enemies())
		var r := _configure(_shots)
		_step = 1
		_frames = 0
		return false
	# two settle frames between changing the pose and reading the framebuffer,
	# otherwise the capture can come back as the PREVIOUS state
	_frames += 1
	if _frames < 3:
		return false
	var anim := _hero_anim()
	var clip: String = anim.current_animation if anim != null else "?"
	var pos: float = anim.current_animation_position if anim != null else -1.0
	var img := get_root().get_texture().get_image()
	var path := "%s/%s.png" % [OUT, POSES[_shots]]
	img.save_png(path)
	print("SHOT %s clip=%s at=%.3f %dx%d" % [
		path, clip, pos, img.get_width(), img.get_height()])
	_shots += 1
	if _shots >= POSES.size():
		print("LOOK_RENDER_DONE %d shots" % _shots)
		return true
	_step = 0
	return false
