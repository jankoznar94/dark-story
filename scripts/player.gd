extends CharacterBody3D
## Slow-paced ARPG player. The whole point: movement and attacks are COMMITMENTS.
## Nothing here is interruptible. That is the feel we are testing.

signal attack_started(kind: String, origin: Vector3, direction: Vector3)
signal attack_landed(kind: String, collider: Node, point: Vector3)

enum Atk { NONE, WINDUP, ACTIVE, RECOVER }
enum Kind { LIGHT, HEAVY }

@export_group("Movement")
@export var move_speed: float = 2.6          ## deliberately slow (D2 walk pace)
@export var accel: float = 14.0
@export var decel: float = 20.0
@export var turn_speed: float = 9.0          ## how fast the body swings to face a new direction

@export_group("Light attack (timing in seconds)")
@export var light_windup: float = 0.16
@export var light_active: float = 0.10
@export var light_recover: float = 0.20
@export var light_range: float = 1.7
@export var light_arc: float = 50.0          ## total degrees of the swing cone

@export_group("Heavy attack")
@export var heavy_windup: float = 0.34
@export var heavy_active: float = 0.14
@export var heavy_recover: float = 0.38
@export var heavy_range: float = 2.1
@export var heavy_arc: float = 105.0

@export_group("Weapon swing visual")
@export var light_sweep: float = 120.0
@export var heavy_sweep: float = 210.0

@onready var pivot: Node3D = $Pivot

var facing: Vector3 = Vector3(0, 0, -1)
var _state: int = Atk.NONE
var _kind: int = Kind.LIGHT
var _t: float = 0.0
var _hit_done: bool = false
var debug_text: String = ""


func state_name() -> String:
	match _state:
		Atk.NONE: return "idle"
		Atk.WINDUP: return "windup"
		Atk.ACTIVE: return "ACTIVE"
		Atk.RECOVER: return "recover"
	return "?"


func is_busy() -> bool:
	return _state != Atk.NONE


func _physics_process(delta: float) -> void:
	# --- state machine: attack phases block movement entirely (no move-cancel) ---
	if _state != Atk.NONE:
		_t += delta
		_advance_attack()
		velocity = velocity.move_toward(Vector3.ZERO, decel * delta)
		move_and_slide()
		_animate_weapon()
		return

	# --- movement ---
	var iv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var want := Vector3(iv.x, 0.0, iv.y)
	var target_vel := want * move_speed
	var rate := accel if want.length() > 0.01 else decel
	velocity = velocity.move_toward(target_vel, rate * delta)

	if want.length() > 0.01:
		_face(want.normalized(), delta)

	move_and_slide()

	# --- input ---
	if Input.is_action_just_pressed("attack"):
		_begin_attack(Kind.LIGHT)
	elif Input.is_action_just_pressed("skill_1"):
		_begin_attack(Kind.HEAVY)


func _face(dir: Vector3, delta: float) -> void:
	facing = facing.lerp(dir.normalized(), clampf(turn_speed * delta, 0.0, 1.0)).normalized()
	var yaw := atan2(-facing.x, -facing.z)
	rotation.y = yaw


func _begin_attack(kind: int) -> void:
	_state = Atk.WINDUP
	_kind = kind
	_t = 0.0
	_hit_done = false
	attack_started.emit("light" if kind == Kind.LIGHT else "heavy", global_position, facing)


func _advance_attack() -> void:
	var w := light_windup if _kind == Kind.LIGHT else heavy_windup
	var a := light_active if _kind == Kind.LIGHT else heavy_active
	var r := light_recover if _kind == Kind.LIGHT else heavy_recover
	if _state == Atk.WINDUP and _t >= w:
		_state = Atk.ACTIVE
		_t = 0.0
		_do_melee()
	elif _state == Atk.ACTIVE and _t >= a:
		_state = Atk.RECOVER
		_t = 0.0
	elif _state == Atk.RECOVER and _t >= r:
		_state = Atk.NONE
		_t = 0.0


func _animate_weapon() -> void:
	var w := light_windup if _kind == Kind.LIGHT else heavy_windup
	var a := light_active if _kind == Kind.LIGHT else heavy_active
	var r := light_recover if _kind == Kind.LIGHT else heavy_recover
	var sweep := deg_to_rad(light_sweep if _kind == Kind.LIGHT else heavy_sweep)
	var half := sweep * 0.5
	var ang := 0.0
	if _state == Atk.WINDUP:
		ang = lerpf(0.0, -half, clampf(_t / max(w, 0.001), 0.0, 1.0))
	elif _state == Atk.ACTIVE:
		ang = lerpf(-half, half, clampf(_t / max(a, 0.001), 0.0, 1.0))
	elif _state == Atk.RECOVER:
		ang = lerpf(half, 0.0, clampf(_t / max(r, 0.001), 0.0, 1.0))
	pivot.rotation.y = ang


func _do_melee() -> void:
	## Directional melee: raycast fan forward along `facing`. Misses are possible on purpose.
	var rng: float = light_range if _kind == Kind.LIGHT else heavy_range
	var arc: float = light_arc if _kind == Kind.LIGHT else heavy_arc
	var origin := global_position + Vector3(0, 0.5, 0)
	var space := get_world_3d().direct_space_state
	var rays := 5
	var hit_any := false
	var already: Array = []      # one swing hits a given target at most ONCE
	for i in rays:
		var frac := 0.0 if rays == 1 else (float(i) / float(rays - 1)) * 2.0 - 1.0
		var dir := facing.rotated(Vector3.UP, deg_to_rad(frac * arc * 0.5)).normalized()
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * rng)
		q.exclude = [get_rid()]
		var res := space.intersect_ray(q)
		if res and res.collider:
			var c: Object = res.collider
			var id: int = c.get_instance_id()
			if already.has(id):
				continue
			already.append(id)
			if c.has_method("take_hit"):
				c.take_hit(_kind)
				attack_landed.emit("light" if _kind == Kind.LIGHT else "heavy", c, res.position)
				hit_any = true
	if not hit_any:
		debug_text = "swing: miss"
	else:
		debug_text = "swing: HIT"
