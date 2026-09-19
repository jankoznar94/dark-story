extends Node3D
## Prototype scene wiring. Headless-safe: no rendering calls.
##
## The training ground now holds a FIGHT, not only posts: `_spawn_enemies()`
## places the test enemy and the wiring below is what makes the loop readable -
## the HUD shows both health bars and the debug line carries the per-swing result
## ("swing: HIT" / "punch: HIT").

@onready var player: CharacterBody3D = $Player
@onready var cam: Camera3D = $Camera
@onready var hud: CanvasLayer = $HUD

## The monster catalogue: one place that says how strong each kind is and which
## behaviour script drives it, so `_spawn_enemies()` below is a list of POSITIONS
## and nothing else.
const MONSTER_KIND := preload("res://scripts/monster_kind.gd")

var _posts: Array[Node] = []
var _enemies: Array[Node] = []
var _hits: Array = []
var _level_nodes: Array = []
var _run_action: bool = false
## The monster the enemy health bar is currently showing: the last one the player
## actually hit, or the nearest engaged one. A single bar for a pack of six is
## otherwise a lie - it would show whichever spawn happened to be first in the
## array, which is unrelated to what the player is fighting.
var _focus: Node = null


func _ready() -> void:
	_setup_world()
	_build_level()
	_spawn_posts()
	_spawn_enemies()
	player.attack_landed.connect(_on_landed)
	player.damaged.connect(_on_player_damaged)
	player.died.connect(_on_player_died)
	# The RUN input exists so the keyboard and a gamepad have a run button too;
	# on touch the HUD latches it (see hud.gd). Both feed the same player flag.
	if not InputMap.has_action("run"):
		InputMap.add_action("run")


func _build_level() -> void:
	## The level is DATA (levels/training_ground.json), not hand-placed nodes.
	## Jan is the tester and has no time to click a scene together, so a layout
	## change is a JSON edit and a new area is a new file. See scripts/level_builder.gd.
	var data: Dictionary = load("res://scripts/level_builder.gd").load_level()
	if data.is_empty():
		push_warning("main: no level data, running with an empty arena")
		_level_nodes = []
		return
	_level_nodes = load("res://scripts/level_builder.gd").build(self, data)
	print("[level] built %d prop nodes from %s"
		% [_level_nodes.size(), data.get("comment", "level data")])


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
	## The fix is more DIRECTIONAL light (sun 0.95 against ambient 0.40) and less
	## fog. Measured after: p10 35, p50 50, p90 69, 284 distinct colours.
	var we := WorldEnvironment.new()
	var env := Environment.new()

	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.030, 0.028, 0.026)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	## Light settings are the "E_soft_shadow" preset chosen by Jan from a rendered
	## contact sheet of 8 variants (tools/sweep_render.gd + tools/sweep_sheet.py,
	## sheet in docs/props_and_lights_sweep.png). He picked E over the contrastier
	## F: softer shadows and a little more ambient, so the world is readable
	## without the shadows reading as hard black cutouts on the grass.
	## Measured for E: p10 35, p50 50, p90 69, 284 distinct colours, 0 % clipped.
	env.ambient_light_color = Color(0.14, 0.135, 0.125)
	env.ambient_light_energy = 0.40

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
	env.fog_density = 0.014
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
	## Full-strength shadows rendered as hard black cutouts on the grass. E's value:
	sun.shadow_opacity = 0.45
	sun.shadow_blur = 1.6
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	add_child(sun)

	# A cool fill from the opposite side so the shadow side is readable instead of
	# black. Kept well under the sun so the direction still reads.
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_energy = 0.30
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


func _spawn_enemies() -> void:
	## A PACK of six, from data. Two rules decide the positions, and both are
	## measured rather than eyeballed (see the notes below): every spawn keeps
	## clearance from the level's props, and none of them sits on a coordinate a
	## gameplay test teleports the player to.
	##
	## The composition is the point of the exercise: the three GHOULS are weaker
	## than the hero (55 hp -> 4 hero swings, 4-7 damage per punch against the
	## hero's 180) and they circle instead of queueing, so killing several of them
	## is a fight rather than a chore. The Ravagers and the Brute are there so the
	## difference in behaviour is visible in the same session.
	var spawns := [
		# --- the fragile pack: close, so they are the first thing encountered ---
		{"kind": "ghoul", "pos": Vector3(-4.25, 0.0, -4.0)},
		{"kind": "ghoul", "pos": Vector3(3.75, 0.0, -4.5)},
		{"kind": "ghoul", "pos": Vector3(-3.0, 0.0, 1.25)},
		# --- the baseline bruisers, further out ---
		{"kind": "ravager", "pos": Vector3(6.25, 0.0, 0.0)},
		{"kind": "ravager", "pos": Vector3(-6.75, 0.0, -0.25)},
		# --- the heavy, furthest out, down the west lane ---
		{"kind": "brute", "pos": Vector3(-9.0, 0.0, -6.75)},
	]
	for i in spawns.size():
		var s: Dictionary = spawns[i]
		var e := _build_enemy(str(s["kind"]), s["pos"] as Vector3)
		e.name = "Enemy_%s_%d" % [str(s["kind"]).capitalize(), i]
		_enemies.append(e)


## Builds one monster from its catalogue entry: the behaviour script decides the
## AI, the entry decides the numbers. Nothing here is hand-set per monster, so a
## new kind is a catalogue line plus a spawn line.
func _build_enemy(kind: String, pos: Vector3) -> CharacterBody3D:
	var k: Dictionary = MONSTER_KIND.kind(kind)
	var e := CharacterBody3D.new()
	e.set_script(load(str(k.get("script", "res://scripts/enemy.gd"))))
	e.position = pos

	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.25
	cs.shape = cap
	cs.position = Vector3(0, 0.65, 0)
	e.add_child(cs)

	add_child(e)
	# `target` is what drives the whole behaviour loop; forgetting it looks exactly
	# like "the enemy stands there doing nothing".
	e.target = player
	# A monster with a leash has to know WHERE HOME IS. Without this every kind
	# would consider itself straying the moment it moved and walk back to (0,0,0).
	e.remember_home()
	return e


## Keeps the enemy health bar honest in a fight with several monsters: the bar
## follows the monster the player last hit, falling back to the nearest one that
## has noticed them.
func _update_focus() -> void:
	if _focus and is_instance_valid(_focus) and _focus.is_engaged() and not _focus.is_dead():
		return
	var best: Node = null
	var best_d := INF
	for e in _enemies:
		if not is_instance_valid(e) or e.is_dead() or not e.is_engaged():
			continue
		var d: float = e.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = e
	_focus = best


func _process(_delta: float) -> void:
	# RUN: the HUD latch and the key/pad action are OR-ed here and pushed to the
	# player, so no single control can block the others and the player never has
	# to ask the HUD about input.
	var run_now: bool = bool(hud.run_latched) or Input.is_action_pressed("run")
	if run_now != _run_action:
		_run_action = run_now
		player.set_run(run_now)

	var st: String = player.state_name()
	var f: Vector3 = player.facing
	_update_focus()
	var extra := ""
	var alive := _alive_count()
	extra = "   monsters alive %d/%d" % [alive, _enemies.size()]
	hud.set_debug("state: %s   facing: %+.2f,%+.2f   %s%s" % [st, f.x, f.z, player.debug_text, extra])
	hud.set_player_hp(player.hp_fraction(), "HP %.0f / %.0f" % [player.hp, player.max_hp])
	if _focus and is_instance_valid(_focus):
		if _focus.is_dead():
			hud.set_enemy_hp(0.0, "%s  DEAD" % _focus.monster_name)
		else:
			hud.set_enemy_hp(_focus.hp_fraction(), "%s  (lv %d)  %.0f / %.0f"
				% [_focus.monster_name, _focus.level, _focus.hp, _focus.max_hp])
	else:
		hud.set_enemy_hp(0.0, "")


func _alive_count() -> int:
	var n := 0
	for e in _enemies:
		if is_instance_valid(e) and not e.is_dead():
			n += 1
	return n


## Removes the whole pack. The gameplay tests that measure a move-lock, a
## miss-when-facing-away or reach on their own fixed coordinates call this after
## instantiating the scene, and the reason is measured, not cosmetic: a monster
## walking into the arc a test is aiming at turns "facing away must miss" into a
## hit, and a body pressed against the player during an attack window moves them
## and reports a broken commitment. The pack itself is verified by test_fight.gd,
## which is the test that is supposed to have monsters in the scene.
func clear_enemies() -> void:
	for e in _enemies:
		if is_instance_valid(e):
			e.queue_free()
	_enemies.clear()
	_focus = null


func _on_landed(kind: String, collider: Node, point: Vector3) -> void:
	_hits.append({"kind": kind, "who": collider.name})
	# whomever the player just swung at is the one whose health bar matters
	if _enemies.has(collider):
		_focus = collider
	print("[hit] %s on %s at %s" % [kind, collider.name, point])


func _on_player_damaged(amount: float, hp_left: float) -> void:
	print("[player] took %.1f damage, %.0f hp left" % [amount, hp_left])


func _on_player_died() -> void:
	print("[player] died")
