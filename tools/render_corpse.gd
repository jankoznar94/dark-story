extends SceneTree
## PIXELS OF THE TWO THINGS JAN REPORTED. Kills a monster, then captures the frame
## around the corpse and the frame with the loot window open, so "a black object"
## and "the loot window shows nothing" can be LOOKED AT instead of inferred from a
## headless dump (the headless flow probe says both are healthy, which is exactly
## why it cannot settle either report).
##
## Run: DISPLAY=:0 godot --path . --rendering-driver opengl3 --resolution 960x540 \
##        --script res://tools/render_corpse.gd

var main: Node
var cam: Camera3D
var _step := 0
var _t := 0.0


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	cam = main.get_node("Camera")
	cam.set_process(false)


func _process(delta: float) -> bool:
	_t += delta
	match _step:
		0:
			if _t < 1.5:
				return false
			_kill_one()
			_step = 1
			_t = 0.0
		1:
			if _t < 1.6:
				return false
			# A GAMEPLAY-LIKE FRAME: the camera the player really sees. Framing the
			# body from straight above hides the thing the report is about.
			var body = main.loot.bodies()[0]
			cam.global_position = body.global_position + Vector3(0.0, 3.2, 4.2)
			cam.look_at(body.global_position + Vector3(0, 0.45, 0), Vector3.UP)
			_step = 2
			_t = 0.0
		2:
			if _t < 0.6:
				return false
			_shot("user://corpse_world.png")
			main.hud.open_loot_for(main.loot.bodies()[0])
			_step = 3
			_t = 0.0
		3:
			if _t < 0.6:
				return false
			_shot("user://corpse_loot_window.png")
			print("RENDER_CORPSE_DONE")
			return true
	return false


func _kill_one() -> void:
	var player: Node = main.get_node("Player")
	var kill: Node = null
	for e in main._enemies:
		if kill == null and e.monster_name == "Ghoul":
			kill = e
		else:
			e.global_position = Vector3(e.global_position.x, 0.0,
				e.global_position.z + 200.0)
	kill.global_position = Vector3(0, 0, -1.5)
	player.global_position = Vector3(0, 0, 1.5)
	kill.take_damage(99999.0)


func _shot(path: String) -> void:
	var img := get_root().get_texture().get_image()
	img.save_png(path)
	print("CAPTURED ", ProjectSettings.globalize_path(path), " ",
		img.get_width(), "x", img.get_height())
