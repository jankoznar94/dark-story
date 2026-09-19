extends CharacterBody3D
## Slow-paced ARPG player. Movement is a commitment, attacks are a commitment -
## but NOT a paralysis. Jan's correction (Sept 2026): "during an attack no
## movement at all is possible, not even turning. It needs to be a bit more
## flexible."
##
## So the rule is now:
##   * TRANSLATION is fully blocked for the whole attack window (no move-cancel,
##     no attack-cancel) - that is the weight and it stays.
##   * TURNING stays available, at a reduced rate (`turn_speed_attacking`), so a
##     held attack can be aimed. The swing reads `facing` at the moment it fires,
##     so turning during the windup genuinely changes where the blade lands.
##   * WALK vs RUN are two speeds. Run is an Input action (`run`) OR the joystick
##     pushed past `run_deadzone`, so both the touch button and the stick work.

signal attack_started(kind: String, origin: Vector3, direction: Vector3)
signal attack_landed(kind: String, collider: Node, point: Vector3)
signal damaged(amount: float, hp_left: float)
signal died

enum Atk { NONE, WINDUP, ACTIVE, RECOVER }
enum Kind { LIGHT, HEAVY }

@export_group("Movement")
@export var walk_speed: float = 2.6          ## deliberately slow (D2 walk pace)
@export var run_speed: float = 4.4           ## the "run" the player asked for
@export var accel: float = 14.0
@export var decel: float = 20.0
@export var turn_speed: float = 9.0          ## how fast the body swings to face a new direction
@export var turn_speed_attacking: float = 3.4 ## ... and how fast while swinging (reduced, not zero)
@export var run_deadzone: float = 0.72       ## joystick magnitude that means "run"

@export_group("Light attack (timing in seconds)")
## Tuned to the CLIP, not picked by feel. tools/blender/measure_gait.py measured
## the contact frame of Rig|Sword_Attack on the shipped model: the blade reaches
## the front at frame 10 of 36 = 0.42 s into the 1.50 s clip. The clip is played
## at 1x now (it used to run at 2x, which Jan reported as "very fast"), so the
## windup is 0.42 s to make the damage land exactly when the blade passes.
## Total window 1.08 s < the 1.50 s clip: the recovery is trimmed by playing the
## next clip over the tail, which is what makes a held attack chain smoothly.
@export var light_windup: float = 0.42
@export var light_active: float = 0.16
@export var light_recover: float = 0.50
@export var light_range: float = 1.7
@export var light_arc: float = 50.0          ## total degrees of the swing cone

@export_group("Heavy attack")
@export var heavy_windup: float = 0.42
@export var heavy_active: float = 0.20
@export var heavy_recover: float = 0.72
@export var heavy_range: float = 2.1
@export var heavy_arc: float = 105.0

@export_group("Vitals")
@export var max_hp: float = 180.0

@onready var hero: Node3D = $Hero

var facing: Vector3 = Vector3(0, 0, -1)
var hp: float = 180.0
var debug_text: String = ""
var last_move_input: Vector2 = Vector2.ZERO
## Pushed by main.gd from the HUD's latched RUN button.
var run_requested: bool = false

var _state: int = Atk.NONE
var _kind: int = Kind.LIGHT
var _t: float = 0.0
var _hit_done: bool = false


func _ready() -> void:
	hp = max_hp


func state_name() -> String:
	match _state:
		Atk.NONE: return "idle"
		Atk.WINDUP: return "windup"
		Atk.ACTIVE: return "ACTIVE"
		Atk.RECOVER: return "recover"
	return "?"


func is_busy() -> bool:
	return _state != Atk.NONE


func is_dead() -> bool:
	return hp <= 0.0


## Movement input this frame, normalised joystick + keyboard in one vector.
func _move_input() -> Vector2:
	var iv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	last_move_input = iv
	return iv


## Run when the player asks for it: the HUD's latched RUN button (main.gd pushes
## it into `run_requested`) or the `run` action (Shift / L1).
##
## NOT from the joystick's magnitude. It was tempting ("push the stick far = run")
## but keyboard and pad input is DIGITAL: Input.get_vector reports magnitude 1.0
## the moment WASD is pressed, so every keyboard step would have become a run and
## the game would have had no walk at all. A separate run input is the only thing
## that works for touch, keyboard and pad alike.
func wants_run(_iv: Vector2 = Vector2.ZERO) -> bool:
	return run_requested or Input.is_action_pressed("run")


## Called by main.gd from the HUD's RUN latch. Kept as a plain flag so the player
## never has to reach back into the HUD for input.
func set_run(on: bool) -> void:
	run_requested = on


func current_speed(iv: Vector2) -> float:
	return run_speed if wants_run(iv) else walk_speed


func _physics_process(delta: float) -> void:
	if is_dead():
		velocity = velocity.move_toward(Vector3.ZERO, decel * delta)
		move_and_slide()
		return

	var iv := _move_input()
	var want := Vector3(iv.x, 0.0, iv.y)

	# --- attack state machine ---
	if _state != Atk.NONE:
		_t += delta
		_advance_attack()
		# TRANSLATION: blocked for the whole window (commitment, no move-cancel).
		velocity = velocity.move_toward(Vector3.ZERO, decel * delta)
		# ROTATION: still allowed, just slower. This is the flexibility Jan asked
		# for - a held attack can be aimed, and the swing fires along `facing` at
		# the ACTIVE frame, so the aim is real.
		if want.length() > 0.01:
			_face(want.normalized(), delta, turn_speed_attacking)
		move_and_slide()
		return

	# --- free movement ---
	var target_vel := want * current_speed(iv)
	var rate := accel if want.length() > 0.01 else decel
	velocity = velocity.move_toward(target_vel, rate * delta)

	if want.length() > 0.01:
		_face(want.normalized(), delta, turn_speed)

	move_and_slide()

	if hero and hero.has_method("play_locomotion"):
		var gs := velocity.length()
		if gs > 0.25:
			hero.play_locomotion(gs, wants_run(iv))
		else:
			hero.play_idle()

	# --- input ---
	# Basic attack reads is_action_pressed, NOT just_pressed: holding the button
	# keeps the character swinging until it is released, which is what Jan asked
	# for. Skills stay on just_pressed so they cannot be spammed by holding.
	if Input.is_action_pressed("attack"):
		_begin_attack(Kind.LIGHT)
	elif Input.is_action_just_pressed("skill_1"):
		_begin_attack(Kind.HEAVY)


func _face(dir: Vector3, delta: float, speed: float = -1.0) -> void:
	var ts: float = turn_speed if speed < 0.0 else speed
	facing = facing.lerp(dir.normalized(), clampf(ts * delta, 0.0, 1.0)).normalized()
	var yaw := atan2(-facing.x, -facing.z)
	rotation.y = yaw


func _begin_attack(kind: int) -> void:
	_state = Atk.WINDUP
	_kind = kind
	_t = 0.0
	_hit_done = false
	if hero and hero.has_method("play_attack"):
		hero.play_attack(kind == Kind.HEAVY)
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


## The sword is NOT animated here. It is welded to the hand bone inside
## models/hero.glb, so it swings with the hand of the clip itself. The old
## procedural pivot rotation fought the animation - that is what made the bar
## look detached from the arms.


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


# ---------------------------------------------------------------- vitals
func take_damage(amount: float) -> void:
	if is_dead():
		return
	hp = maxf(0.0, hp - amount)
	damaged.emit(amount, hp)
	if hp <= 0.0:
		_state = Atk.NONE
		if hero and hero.has_method("play_death"):
			hero.play_death()
		died.emit()


func heal(amount: float) -> void:
	if is_dead():
		return
	hp = minf(max_hp, hp + amount)


func hp_fraction() -> float:
	return 0.0 if max_hp <= 0.0 else clampf(hp / max_hp, 0.0, 1.0)
