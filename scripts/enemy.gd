extends CharacterBody3D
## One test enemy: a melee bruiser that walks at the player, attacks in reach,
## and dies. Everything here is deliberately simple; it exists so the fight can
## be TESTED (does a swing land, does damage read, does death work), not to be
## the final monster.
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

signal attack_landed(collider: Node, point: Vector3)

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
@export var attack_windup: float = 0.40
@export var attack_active: float = 0.12
@export var attack_recover: float = 0.30
@export var attack_range: float = 1.55
@export var attack_arc: float = 70.0
@export var attack_cooldown: float = 0.35
@export var damage_min: float = 7.0
@export var damage_max: float = 13.0

@export_group("Vitals")
@export var max_hp: float = 220.0

@export_group("Behaviour")
@export var aggro_range: float = 11.0    ## wakes up when the player is this close
@export var keep_distance: float = 1.35   ## stops walking in this close
@export var level: int = 2
@export var monster_name: String = "Ravager"

enum Atk { NONE, WINDUP, ACTIVE, RECOVER }

@onready var model_root: Node3D = $Model

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
var anim: AnimationPlayer
var _mat: StandardMaterial3D
var _flash: float = 0.0


func _ready() -> void:
	hp = max_hp
	_build_model()


func _build_model() -> void:
	## Two things happen to the shared base model: the material is swapped for a
	## bruised, desaturated one (so the enemy reads apart from the hero at a
	## glance) and the animation clips are looked up by their real names.
	var packed: PackedScene = load("res://models/enemy.glb")
	if packed == null:
		push_error("enemy.glb could not be loaded")
		return
	var inst := packed.instantiate()
	model_root.add_child(inst)
	anim = _find_animation_player(inst)
	if anim == null:
		push_warning("no AnimationPlayer in enemy.glb")
		return
	_clip_names = anim.get_animation_list()
	for want in [CLIP_ATTACK, CLIP_ATTACK_ALT, CLIP_WALK, CLIP_HIT]:
		if not _clip_names.has(want):
			push_warning("[enemy] missing animation: %s" % want)
	_mat = _tint_meshes(inst)
	_play(CLIP_IDLE, 1.0, true)


func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_animation_player(c)
		if r != null:
			return r
	return null


## Replaces every surface material with one flat desaturated palette so the
## enemy is readable against the hero without any glow (art rule).
func _tint_meshes(n: Node) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.34, 0.20, 0.16)   ## dried blood / boiled leather
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


func _locomotion(gs: float) -> void:
	var clip := CLIP_RUN if gs > 2.6 else CLIP_WALK
	var base := RUN_GROUND_SPEED if gs > 2.6 else WALK_GROUND_SPEED
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


func _physics_process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0 and _mat:
			_mat.albedo_color = Color(0.34, 0.20, 0.16)

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

	# --- attack window: translation blocked, turning reduced but allowed ---
	if _state != Atk.NONE:
		_t += delta
		_advance_attack()
		velocity = velocity.move_toward(Vector3.ZERO, decel * delta)
		if to_target.length() > 0.05:
			_face(to_target.normalized(), delta, turn_speed_attacking)
		move_and_slide()
		return

	var want := Vector3.ZERO
	if aggro and dist < INF:
		if dist > keep_distance:
			want = to_target.normalized()
		if to_target.length() > 0.05:
			_face(to_target.normalized(), delta, turn_speed)

	velocity = velocity.move_toward(want * walk_speed, (accel if want.length() > 0.01 else decel) * delta)
	move_and_slide()

	if anim != null:
		var gs := velocity.length()
		if gs > 0.2:
			_locomotion(gs)
		else:
			_play(CLIP_IDLE, 1.0, true)

	if aggro and _cd <= 0.0 and dist <= attack_range:
		_begin_attack()


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
	var origin := global_position + Vector3(0, 0.55, 0)
	var space := get_world_3d().direct_space_state
	var hit_any := false
	var already: Array = []
	for i in 5:
		var frac := (float(i) / 4.0) * 2.0 - 1.0
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


func take_damage(amount: float) -> void:
	if is_dead():
		return
	hp = maxf(0.0, hp - amount)
	_flash = 0.18
	if _mat:
		_mat.albedo_color = Color(0.75, 0.30, 0.16)
	aggro = true
	if hp <= 0.0:
		_state = Atk.NONE
		velocity = Vector3.ZERO
		_play(CLIP_DEATH, 1.0, false)


## The player's melee fan calls take_hit(kind) on whatever it raycasts into.
func take_hit(_kind) -> void:
	if is_dead():
		return
	take_damage(randf_range(16.0, 25.0))
