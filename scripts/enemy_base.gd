extends CharacterBody3D
## Base of every monster: a melee enemy that walks at the player, attacks in reach,
## and dies. Behaviour differences live in SUBCLASSES (enemy_ghoul.gd,
## enemy_brute.gd); the numbers live in DATA (scripts/monster_kind.gd), so a new
## monster is an entry in that catalogue plus, only if its behaviour is genuinely
## new, a small subclass.
##
## Rules it shares with the player, because they are the game's feel:
##   * attacking is a commitment - translation stops for the whole window
##   * turning stays available, slower, so it can still track a moving target
##   * melee is directional: the fan raycast runs along `facing`, a miss is real
##
## The model is the same rigged base character as the hero (CC0, Quaternius),
## re-exported with no weapon welded in, so the punches animate out of the box.
## Clip names were printed from Godot by tools/list_anims.gd and cross-checked
## against the Blender action list - never guess them.
##
## TWO STRUCTURAL RULES, both learned the hard way:
##   1. Everything is created in code and held in a VARIABLE (`anim`, `model_root`,
##      `_mat`), never fetched with get_node(). A monster is built by main.gd from
##      the catalogue, so it has no scene file whose node names could be relied on.
##   2. `get_node("Model")` in a base class works for the first kind that ships it
##      and breaks silently for the second - the classic single-enemy prototype
##      trap this refactor exists to remove.

signal attack_landed(collider: Node, point: Vector3)
## Emitted once, when this monster's life reaches zero. main.gd hangs the loot
## roll off it, so the AI never has to know that loot exists.
signal died

## The balance sheet lives in one place (hp, damage, speeds, tint) so a monster is
## a data entry and the "weaker than the hero" claim can be asserted in a test.
const MK := preload("res://scripts/monster_kind.gd")
## The shared pause flag. A monster that ignores it is a monster that keeps walking
## and punching while the player reads his inventory (Jan's report).
const GATE := preload("res://scripts/input_gate.gd")

const CLIP_IDLE := "Rig|Sword_Idle"      ## combat-ready stance
const CLIP_WALK := "Rig|Walk"
const CLIP_RUN := "Rig|Sprint"
const CLIP_ATTACK := "Rig|Punch_Cross"   ## 1.00 s (source) -> 0.917 s imported
const CLIP_ATTACK_ALT := "Rig|Punch_Jab" ## 0.83 s, plays as the follow-up
const CLIP_HIT := "Rig|Hit_Chest"
const CLIP_DEATH := "Rig|Death01"        ## 2.38 s

## Same measured ground speeds as hero.gd (tools/blender/measure_gait.py).
const WALK_GROUND_SPEED := 0.951
const RUN_GROUND_SPEED := 1.666

## Where the melee fan starts and how far below `global_position` it sits.
const MELEE_ORIGIN_Y := 0.55
const MELEE_RAYS := 5

## Distance at which a monster switches from walk to run (m/s). Below this the
## walk clip is the right one; above it the sprint clip, re-timed either way.
const RUN_CLIP_THRESHOLD := 2.6

## Contact frame of the punch clips (tools/blender/measure_gait.py measured the
## same frame for the sword). Damage must land when the fist arrives, so the
## windup is NOT a per-monster tuning knob - cadence is.
const ATTACK_WINDUP := 0.40
const ATTACK_ACTIVE := 0.12

enum Atk { NONE, WINDUP, ACTIVE, RECOVER }

var model_root: Node3D
var anim: AnimationPlayer

var facing: Vector3 = Vector3(0, 0, -1)
var hp: float = 220.0
var aggro: bool = false
var target: Node3D
var debug_text: String = ""

var _state: int = Atk.NONE
var _t: float = 0.0
var _cd: float = 0.0
var _swing: int = 0
var _current: String = ""
var _clip_names: PackedStringArray = PackedStringArray()
var _mat: StandardMaterial3D
var _flash: float = 0.0
var _home: Vector3 = Vector3.ZERO
## Guards the death signal: `take_damage` can be called again on a corpse (a ray
## can still land on it), and loot must not fall twice for one monster.
var _death_announced: bool = false
## Set when this monster dies. The death clip plays once and is then FROZEN, so the
## body the player opens is the last frame of the fight rather than a limp loop.
var _freeze_after_death: bool = false

# --- Movement / attack / vitals, all overridden from the catalogue in _ready ---
@export_group("Movement")
@export var walk_speed: float = 2.2
@export var accel: float = 12.0
@export var decel: float = 18.0
@export var turn_speed: float = 6.0
@export var turn_speed_attacking: float = 2.6

@export_group("Attack")
## Punch_Cross is 1.00 s in the source file (0.917 s after import). The fist
## reaches the target a bit before half the clip; 0.40 s keeps the damage on the
## contact rather than after it.
@export var attack_windup: float = ATTACK_WINDUP
@export var attack_active: float = ATTACK_ACTIVE
@export var attack_recover: float = 0.30
@export var attack_range: float = 1.55
@export var attack_arc: float = 70.0
@export var attack_cooldown: float = 0.35
@export var damage_min: float = 7.0
@export var damage_max: float = 13.0

@export_group("Vitals")
@export var max_hp: float = 220.0

@export_group("Behaviour")
## Aggro is deliberately SHORT. With six monsters in a 34 m arena, a 10 m aggro
## radius means five of them wake at the same instant the scene loads - every
## engagement becomes the whole pack, which is the "hordes" pattern this game
## bans, and it also removes the choice of which lane to fight in. At 5 m the
## pack is met in waves (measured: 1 engaged at spawn, the rest as they are
## approached one lane at a time).
## A monster also forgets the player again: `aggro` drops when it exceeds
## `leash_range` from home, which is what stops the weak pack from trailing the
## player across the arena instead of holding its ground.
@export var aggro_range: float = 5.0    ## wakes up when the player is this close
@export var keep_distance: float = 1.35   ## stops walking in this close
@export var level: int = 2
@export var monster_name: String = "Ravager"
## How far from its spawn a monster will chase (INF = anywhere). This is what lets
## the weak pack defend a spot instead of trailing the player across the arena.
@export var leash_range: float = INF
## How far two monsters of the same pack keep apart, so they do not stack into one
## silhouette and turn a fight into a single blob of polygons.
@export var separation_radius: float = 1.0


func _ready() -> void:
	_apply_kind()
	_build_model()


## Which entry of scripts/monster_kind.gd describes this monster.
func kind_id() -> String:
	return "ravager"


## Copies the catalogue numbers over the exported defaults. Called before the
## model is built so hp, tint and scale are already right when the meshes appear.
func _apply_kind() -> void:
	var k: Dictionary = MK.kind(kind_id())
	if k.is_empty():
		return
	monster_name = str(k.get("name", monster_name))
	level = int(k.get("level", level))
	max_hp = float(k.get("hp", max_hp))
	walk_speed = float(k.get("walk_speed", walk_speed))
	accel = float(k.get("accel", accel))
	decel = float(k.get("decel", decel))
	turn_speed = float(k.get("turn_speed", turn_speed))
	turn_speed_attacking = float(k.get("turn_speed_attacking", turn_speed_attacking))
	attack_windup = float(k.get("windup", attack_windup))
	attack_active = float(k.get("active", attack_active))
	attack_recover = float(k.get("recover", attack_recover))
	attack_cooldown = float(k.get("cooldown", attack_cooldown))
	attack_range = float(k.get("range", attack_range))
	attack_arc = float(k.get("arc", attack_arc))
	damage_min = float(k.get("damage_min", damage_min))
	damage_max = float(k.get("damage_max", damage_max))
	aggro_range = float(k.get("aggro", aggro_range))
	keep_distance = float(k.get("keep_distance", keep_distance))
	leash_range = float(k.get("leash", leash_range))
	separation_radius = float(k.get("separation", separation_radius))
	hp = max_hp


func _build_model() -> void:
	## Two things happen to the shared base model: the material is swapped for the
	## kind's own desaturated tint (so the kinds read apart at a glance) and the
	## animation clips are looked up by their real names.
	var packed: PackedScene = load("res://models/enemy.glb")
	if packed == null:
		push_error("enemy.glb could not be loaded")
		return
	var inst := packed.instantiate()
	## Built from the catalogue too - no scene file, no hand-set node names.
	model_root = Node3D.new()
	model_root.name = "Model"
	add_child(model_root)
	model_root.add_child(inst)
	var k: Dictionary = MK.kind(kind_id())
	var sc := float(k.get("scale", 1.0))
	inst.scale = Vector3(sc, sc, sc)
	anim = _find_animation_player(inst)
	if anim == null:
		push_warning("no AnimationPlayer in enemy.glb")
		return
	_clip_names = anim.get_animation_list()
	for want in [CLIP_ATTACK, CLIP_ATTACK_ALT, CLIP_WALK, CLIP_HIT]:
		if not _clip_names.has(want):
			push_warning("[%s] missing animation: %s" % [monster_name, want])
	_mat = _tint_meshes(inst, k.get("tint", Color(0.34, 0.20, 0.16)))
	_play(CLIP_IDLE, 1.0, true)


func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_animation_player(c)
		if r != null:
			return r
	return null


## Replaces every surface material with one flat desaturated palette so a kind is
## readable against the hero without any glow (art rule).
func _tint_meshes(n: Node, tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = 0.95
	mat.metallic = 0.0
	_apply_override(n, mat)
	return mat


func _apply_override(n: Node, mat: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = mat
	for c in n.get_children():
		_apply_override(c, mat)


func _play(clip: String, speed: float = 1.0, loop: bool = true) -> void:
	if anim == null or not _clip_names.has(clip):
		return
	if _current == clip and anim.is_playing():
		return
	_current = clip
	anim.play(clip, -1.0, speed)
	anim.speed_scale = speed
	var a: Animation = anim.get_animation(clip)
	if a:
		a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE


## Locomotion is re-timed to the ground speed the body is ACTUALLY moving at, the
## same rule as the hero's feet: a 1.55 m/s brute must not have the walk cycle of
## a 2.6 m/s run, or its boots skate and it reads as a puppet.
func _locomotion(gs: float) -> void:
	var running := gs > RUN_CLIP_THRESHOLD
	var clip := CLIP_RUN if running else CLIP_WALK
	var base := RUN_GROUND_SPEED if running else WALK_GROUND_SPEED
	var s := clampf(gs / base, 0.2, 4.0)
	if _current == clip and anim != null and anim.is_playing():
		anim.speed_scale = s
		return
	_play(clip, s, true)


func is_busy() -> bool:
	return _state != Atk.NONE


func current_clip() -> String:
	return _current


func is_dead() -> bool:
	return hp <= 0.0


func state_name() -> String:
	match _state:
		Atk.NONE: return "idle"
		Atk.WINDUP: return "windup"
		Atk.ACTIVE: return "ACTIVE"
		Atk.RECOVER: return "recover"
	return "?"


func hp_fraction() -> float:
	return 0.0 if max_hp <= 0.0 else clampf(hp / max_hp, 0.0, 1.0)


## True while this monster has actually noticed the player. main.gd uses it to
## decide whether to spend HUD space on this monster's health bar.
func is_engaged() -> bool:
	return aggro and not is_dead()


## The rigged model this monster is wearing, so a corpse can be tipped over as the
## real body rather than replaced by a second object (see loot_body.dress_corpse).
func get_model_root() -> Node3D:
	return model_root


func _physics_process(delta: float) -> void:
	if is_dead():
		# FROZEN: stop dead in the death pose. `move_and_slide` here would let a
		# corpse drift for the frames its decay velocity lasts, and re-playing the
		# death clip would make it writhe forever.
		if _freeze_after_death and anim != null:
			anim.speed_scale = 0.0
		return
	## PAUSED: a full-screen panel (the bag, the hero sheet, an opened body) stops
	## the world. Jan's report was "the game should pause when the inventory opens,
	## it does not - the enemies keep attacking and moving, they may not be dealing
	## damage but they move", and this early return is the fix for the AI half of
	## it. The INPUT half is scripts/input_gate.gd: a script that merely stops
	## moving still leaves the virtual buttons and real keys pressed, so the player
	## kept walking and swinging with the bag open until every read went through
	## the gate.
	##
	## The clip is left WHERE IT IS rather than sent to idle: a walk cycle frozen
	## mid-stride is what a paused world looks like, and restarting it on resume
	## would hide that the pause happened.
	if GATE.blocked():
		return

	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0 and _mat:
			_mat.albedo_color = _tint_color()

	if is_dead():
		velocity = velocity.move_toward(Vector3.ZERO, decel * delta)
		move_and_slide()
		return

	_cd = maxf(0.0, _cd - delta)

	var to_target := Vector3.ZERO
	var dist := INF
	if target and is_instance_valid(target):
		to_target = target.global_position - global_position
		to_target.y = 0.0
		dist = to_target.length()
		if not aggro and dist < aggro_range:
			aggro = true

	# a monster on a leash gives up and walks home instead of trailing the player
	# across the whole arena - that is what makes the weak pack a POSITION to take
	if aggro and global_position.distance_to(_home) > leash_range:
		aggro = false
	if not aggro and global_position.distance_to(_home) > 0.6:
		_walk_home(delta)
		return

	# --- attack window: translation blocked, turning reduced but allowed ---
	if _state != Atk.NONE:
		_t += delta
		_advance_attack()
		velocity = velocity.move_toward(Vector3.ZERO, decel * delta)
		if to_target.length() > 0.05:
			_face(to_target.normalized(), delta, turn_speed_attacking)
		move_and_slide()
		return

	var want := _steer(to_target, dist, delta)
	velocity = velocity.move_toward(want * walk_speed,
		(accel if want.length() > 0.01 else decel) * delta)
	move_and_slide()

	if anim != null:
		var gs := velocity.length()
		if gs > 0.2:
			_locomotion(gs)
		else:
			_play(CLIP_IDLE, 1.0, true)

	if aggro and _cd <= 0.0 and dist <= attack_range:
		_begin_attack()


## The direction this monster wants to move. The base kind walks straight in; a
## subclass overrides this to strafe, circle or charge instead. It may call `_face`
## with whatever turn rate its behaviour needs.
func _steer(to_target: Vector3, dist: float, delta: float) -> Vector3:
	if not aggro or dist >= INF:
		return Vector3.ZERO
	if to_target.length() < 0.05:
		return Vector3.ZERO
	_face(to_target.normalized(), delta, turn_speed)
	if dist > keep_distance:
		return to_target.normalized()
	return Vector3.ZERO


## Keeps one monster from standing on another while it is on its way in, so the
## pack reads as several bodies instead of one blob. Applied to the STEERING
## vector, never to the position, so it can only ever nudge a direction and can
## never teleport a body into a wall.
func _separation() -> Vector3:
	var push := Vector3.ZERO
	if target == null or not is_instance_valid(target) or target.get_parent() == null:
		return push
	for sib in target.get_parent().get_children():
		if sib == self or not (sib is CharacterBody3D):
			continue
		if not sib.has_method("is_dead") or sib.is_dead():
			continue
		var away: Vector3 = global_position - (sib as Node3D).global_position
		away.y = 0.0
		var d := away.length()
		if d > 0.01 and d < separation_radius:
			push += away.normalized() * (1.0 - d / separation_radius)
	return push


func _walk_home(delta: float) -> void:
	var back := _home - global_position
	back.y = 0.0
	if back.length() < 0.05:
		return
	if _state != Atk.NONE:
		_state = Atk.NONE
	velocity = velocity.move_toward(back.normalized() * walk_speed, accel * delta)
	if back.length() > 0.05:
		_face(back.normalized(), delta, turn_speed)
	move_and_slide()
	if anim != null:
		var gs := velocity.length()
		if gs > 0.2:
			_locomotion(gs)
		else:
			_play(CLIP_IDLE, 1.0, true)


func _face(dir: Vector3, delta: float, speed: float) -> void:
	facing = facing.lerp(dir, clampf(speed * delta, 0.0, 1.0)).normalized()
	rotation.y = atan2(-facing.x, -facing.z)


func _begin_attack() -> void:
	_state = Atk.WINDUP
	_t = 0.0
	_swing += 1
	_play(CLIP_ATTACK if _swing % 2 == 1 else CLIP_ATTACK_ALT, 1.0, false)


func _advance_attack() -> void:
	if _state == Atk.WINDUP and _t >= attack_windup:
		_state = Atk.ACTIVE
		_t = 0.0
		_do_melee()
	elif _state == Atk.ACTIVE and _t >= attack_active:
		_state = Atk.RECOVER
		_t = 0.0
	elif _state == Atk.RECOVER and _t >= attack_recover:
		_state = Atk.NONE
		_t = 0.0
		_cd = attack_cooldown


func _do_melee() -> void:
	var origin := global_position + Vector3(0, MELEE_ORIGIN_Y, 0)
	var space := get_world_3d().direct_space_state
	var hit_any := false
	var already: Array = []
	for i in MELEE_RAYS:
		var frac := (float(i) / float(MELEE_RAYS - 1)) * 2.0 - 1.0
		var dir := facing.rotated(Vector3.UP, deg_to_rad(frac * attack_arc * 0.5)).normalized()
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * attack_range)
		q.exclude = [get_rid()]
		var res := space.intersect_ray(q)
		if res and res.collider:
			var c: Object = res.collider
			var id: int = c.get_instance_id()
			if already.has(id):
				continue
			already.append(id)
			# the enemy never damages itself or another monster
			if c.has_method("take_damage") and c.has_method("wants_run"):
				c.take_damage(randf_range(damage_min, damage_max))
				attack_landed.emit(c, res.position)
				hit_any = true
	debug_text = "punch: %s" % ("HIT" if hit_any else "miss")


## The hit flash colour: the kind's own tint, handed back so the flash can be
## derived from it. Restoring to a hardcoded brown would repaint every kind.
func _tint_color() -> Color:
	var k: Dictionary = MK.kind(kind_id())
	return k.get("tint", Color(0.34, 0.20, 0.16))


func take_damage(amount: float) -> void:
	if is_dead():
		return
	hp = maxf(0.0, hp - amount)
	_flash = 0.18
	if _mat:
		var base := _tint_color()
		_mat.albedo_color = base.lerp(Color(1.0, 0.42, 0.22), 0.55)
	aggro = true
	if hp <= 0.0:
		_state = Atk.NONE
		velocity = Vector3.ZERO
		_play(CLIP_DEATH, 1.0, false)
		# A corpse must not block a step or swallow a swing, and both are layer 1
		# behaviours. It stays in the world as the body the player opens.
		collision_layer = 0
		# and it keeps the pose it died in: the death clip is played ONCE and then
		# frozen, so the body the player sees is the last frame of the fight.
		_freeze_after_death = true
		if not _death_announced:
			_death_announced = true
			died.emit()


## The player's melee fan calls take_hit(kind, damage) on whatever it raycasts
## into. The damage is passed IN rather than rolled here, because it comes from
## the hero's equipped weapon - the enemy has no business knowing about items.
## A bare tool call without a number falls back to the pre-item range, so the
## tests that only want to kill a monster (take_hit(0)) keep working.
func take_hit(_kind, damage: float = -1.0) -> void:
	if is_dead():
		return
	take_damage(damage if damage > 0.0 else randf_range(16.0, 25.0))


## Called by main.gd right after the monster is placed, so it knows which spot it
## belongs to. Every position-dependent behaviour reads this, never a literal.
func remember_home() -> void:
	_home = global_position
