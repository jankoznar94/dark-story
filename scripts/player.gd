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
## Emitted when the auto-acquired target changes (including to null). main.gd uses
## it to draw the target marker, so the marker is never out of sync with the AI.
signal target_changed(target: Node3D)

enum Atk { NONE, WINDUP, ACTIVE, RECOVER }
enum Kind { LIGHT, HEAVY }

@export_group("Movement")
## PACING CHANGE (Jan, Sept 2026): "the run speed is too high, make it about 30 %
## slower, and adapt the animation to it."
##
## Top speeds scaled by 0.70:
##   walk  2.6 -> 1.8      run  4.4 -> 3.05
##
## The clip retime follows automatically, because `play_locomotion()` is fed the
## ACTUAL ground speed - that is the "adapt the animation" half of the request, and
## no new constant is needed for it. What is NOT automatic is the feel: the accel,
## decel and turn figures below are RATES, and leaving them alone would make the
## character cover less ground per second while still snapping to full speed and
## spinning just as fast - twitchy, which is the opposite of the point.
##
## So they are scaled to preserve the invariants that produce the feel:
##   time to top speed  4.4/14.0 = 0.314 s  ->  3.05/9.7  = 0.314 s
##   time to a stop     4.4/20.0 = 0.220 s  ->  3.05/13.9 = 0.219 s
##   turn radius        2.6/9.0  = 0.289 m  ->  1.8/6.2   = 0.290 m
##   turn while swinging is a fixed FRACTION of the free turn rate (0.38 x), so it
##   scales with it: 3.4 -> 2.35. Never share one constant between the two call
##   sites or the pair silently collapses into one rate.
@export var walk_speed: float = 1.8          ## deliberately slow (D2 walk pace)
@export var run_speed: float = 3.05          ## 0.70 x the old 4.4, per Jan's request
@export var accel: float = 9.7
@export var decel: float = 13.9
@export var turn_speed: float = 6.2          ## how fast the body swings to face a new direction
@export var turn_speed_attacking: float = 2.35 ## ... and how fast while swinging (reduced, not zero)
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
## How far the blade must be off the target before the swing will start. Jan's rule
## (Sept 2026): "if I have no enemy in front of me, I should not swing the sword at
## all - finding the target has priority. Once the target is directly in front of me,
## the attack may start."
##
## His report was a hero who swung after every step while a monster stood behind him
## and turned "a few degrees after every swing". Two things caused it and both are
## fixed here:
##   * `_auto_approach()` reported "swing now" the instant the body was inside
##     `auto_approach_stop`, but `_begin_attack` snapshots `facing` at the ACTIVE frame
##     - so the blade left along a facing that was still tens of degrees off the target.
##     The swing has to WAIT for the aim, not fire and let the body catch up.
##   * the distance-only fallback (below) re-fired the swing every time the commitment
##     window closed, so the turn was chopped into one slice per swing.
## This is the gate that makes the approach a continuous run + turn instead: no swing
## until the aim is settled. Measured with the aim gate at 12 deg, a held attack on a
## monster directly behind produced ZERO swings in 180 frames while still completing
## the turn and then hitting - instead of roughly one swing per 1.1 s slice.
@export var attack_aim_tolerance_deg: float = 12.0
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

## ------------------------------------------------------------------ auto-target
## Jan's brief: "in Diablo 2 with a gamepad the player does not just swing into
## thin air. He first walks to a target, and the game helps him by picking it by
## DIRECTION and DISTANCE." This is that helper.
##
## The D2 controller blog describes it as a CONE that scans the playfield and
## prioritises by kind, distance and whether the target is already engaged. The
## cone is the part that matters here: it is what makes the choice readable, so a
## player can predict it. A pure "nearest monster" rule would pick a body BEHIND
## the character, which reads as a broken game, not as help.
@export_group("Auto-target")
## How far the cone reaches. Light reach is 1.7 m, so this leaves room to notice a
## target before the swing would already connect.
@export var target_range: float = 6.0
## Half-width of the scan cone, in degrees off `facing`. 55 deg total.
@export var target_cone_half_deg: float = 55.0
## Hysteresis: an acquired target is kept while it is inside this slightly wider
## cone, even if a body nearer the centre appears. Without it the target flickers
## between two monsters on every frame and the walk-in stutters.
@export var target_keep_half_deg: float = 75.0
## How close the auto-walk stops. Just inside light_range (1.7 m) so the swing
## that follows can actually reach.
@export var auto_approach_stop: float = 1.45
## How much of the run speed the auto-approach uses when the player has asked to RUN.
## Jan's second pass: "when it searches for a target and walks to it, it always goes
## at a slow walk - I need it to run to it too." The approach follows the player's own
## run intent (the HUD latch / Shift / pad), so the answer is "run when the RUN button
## is on". At 1.0 it matches `run_speed` exactly and `play_locomotion()` retimes the
## clip from the actual ground speed, so there is no new animation constant.
@export var auto_approach_run_speed_scale: float = 1.0
## How much of the walk speed the auto-approach uses when the player has NOT asked to
## run. Deliberately below 1.0: the approach should read as a deliberate step-in, not
## as the player being yanked.
@export var auto_approach_speed_scale: float = 0.85
## Seconds after LOSING a target before a new one may be acquired. Measured, not
## guessed: two Ghouls 3.4 m and 3.6 m away sit at nearly the same score, and
## without this window the pick alternated every frame - the player walked in and
## out between them and never committed to either. 0.35 s is longer than a frame
## of flicker and shorter than a deliberate re-aim.
@export var target_rearm: float = 0.35
## Score margin within which a monster that is ALREADY FIGHTING us beats an idle
## one. The score is (-angle_deg * 2 - distance_m), so 1.2 points is roughly "half
## a metre, or 0.6 deg". It is a tie-break, not a priority: an engaged monster that
## is clearly further away does not get picked over one standing on the nose.
@export var engagement_margin: float = 1.2
## Jan's rule (Sept 2026): "the search works by the direction the player looks, but
## when nobody is in that direction the hero attacks nobody - not even when an enemy
## stands right behind him. When there is nobody WHERE HE LOOKS, other directions must
## count too, by how CLOSE the enemy is. He turns to the nearest one and attacks."
##
## So the cone is the PREFERENCE, not a filter that can leave the player swinging at
## air. The scan has two tiers, in this order:
##   1. the 55 deg cone around `facing`, scored by angle first and distance second
##      (unchanged - a monster you are looking at always wins);
##   2. only when the cone is EMPTY, the NEAREST monster inside `target_range`,
##      whatever direction it stands in - including directly behind. The turn that
##      follows is what makes the pick readable: the marker and the body both swing
##      onto it before the blade does.
## The distance tier is NOT a proximity radius of its own; it is still bounded by
## `target_range`, so a held attack never drags the player across the arena to
## something he had no way of knowing about.
##
## A monster acquired this way is kept while it is alive and in range, WITHOUT the
## keep-cone test - otherwise the keep check would drop it on the next frame (it is
## behind, which is outside the 75 deg keep-cone) and the re-arm window would stop him
## ever turning round. It becomes an ordinary cone target the moment the turn brings it
## inside `target_cone_half_deg`.

@onready var hero: Node3D = $Hero

var facing: Vector3 = Vector3(0, 0, -1)
var hp: float = 180.0
var debug_text: String = ""
var last_move_input: Vector2 = Vector2.ZERO
## Pushed by main.gd from the HUD's latched RUN button.
var run_requested: bool = false
## The monster the game picked for the held attack, or null. Read-only for other
## systems; it is written only by _acquire_target() / _drop_target().
var target: Node3D = null
## True while the player is on auto-approach toward `target`.
var auto_approaching: bool = false
## True when `target` was chosen by the cone (tier 1), false when it came from the
## nearest-in-range fallback (tier 2). It relaxes the keep test for a target the
## player is still turning toward - see the scan comment above.
var _target_from_cone: bool = true

var _state: int = Atk.NONE
var _kind: int = Kind.LIGHT
var _t: float = 0.0
var _hit_done: bool = false
var _rearm_t: float = 0.0


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
##
## ---------------------------------------------------------------- WHY THIS EXISTS
## Jan's report (Sept 2026): "the run speed is still dependent on the position of
## the left joystick. When my finger is only slightly outside the circle he runs
## slowly, when it is far outside he runs at full speed. The run speed should be
## CONSTANT."
##
## He is right, and the earlier "constant run speed" test could not see it. Read
## Godot's VirtualJoystick source: `_update_joystick()` does NOT emit a unit
## vector for a pushed stick. Above the dead zone it computes
##
##     scaled = inverse_lerp(deadzone*R, R, length)      # 0.0 .. 1.0
##     input_vector = direction * scaled
##
## and `_handle_input_actions()` presses each action with that magnitude. So the
## joystick hands out a CONTINUOUS 0..1 strength, and the old code fed it straight
## into `target_vel = want * current_speed(iv)`. A stick 30 % out walked at 0.30 x
## run speed and only a fully-deflected one reached `run_speed` - exactly the
## graded speed Jan describes. `Input.get_vector()` does not launder it either:
## it combines action strengths per axis and only normalises when the result is
## LONGER than 1, so it returns the graded vector unchanged.
##
## tools/test_controls.gd missed it because it pressed the actions with
## `Input.action_press(axis, 1.0)` - a synthetic FULL deflection, i.e. it measured
## the one case that already worked. The assertion it made in response was true and
## useless.
##
## THE FIX: the stick is a DIRECTION, not a throttle. `get_vector` keeps whatever
## magnitude it likes and `_move_input` returns `direction * speed_magnitude`,
## where the magnitude is a per-device setting:
##
##   * TOUCH (and the virtual joystick generally) -> `touch_move_magnitude`, 1.0:
##     any deflection past the dead zone travels at FULL speed. That is the
##     constant run Jan asked for. Note this is NOT the same thing as the "run when
##     the stick is pushed far" rule that was tried and removed - run is still the
##     separate latch/action, never derived from the stick. It only decides HOW
##     FAST you travel while running, never WHETHER you run.
##   * KEYBOARD -> whatever the device reports, i.e. `Input.get_vector`'s own
##     magnitude, which for digital keys is 1.0 anyway.
##
## `deadzone_ratio` on the joystick is 0.18 and `VirtualJoystick` applies it
## itself, so anything that arrives here already passed a deliberate push.
##
## The keyboard branch is what makes the test meaningful: a test can drive the
## actions with a graded strength and MUST then see a graded speed (that is the
## device being honest), while the same graded push through a VirtualJoystick must
## come out at full speed. A single rule that forces 1.0 for everything would pass
## the joystick case and destroy analogue input everywhere else.
const JOYSTICK_DEVICE_DEADZONE := 0.15   ## ignore stick noise on the DEVICE check
@export var touch_move_magnitude: float = 1.0  ## stick deflection -> travel speed (1.0 = constant)


## True while a virtual stick is driving the movement, pushed by main.gd from the
## HUD's joystick state (VirtualJoystick.is_pressed is C++-only, so the HUD tracks
## it). A stick deflection is a DIRECTION here, not a throttle - see _move_input().
var stick_active: bool = false


## Called by main.gd once per frame, exactly like set_run().
func set_stick_active(on: bool) -> void:
	stick_active = on


## True when this frame's movement came from a stick rather than keys.
##
## A real joypad axis is checked first: when analogue movement is wired to the
## actions (the gamepad path), the stick's own partial deflection is a legitimate
## throttle and must stay one. The virtual stick is the case that must NOT be, which
## is what the HUD flag covers.
func input_is_stick() -> bool:
	for d in Input.get_connected_joypads():
		if absf(Input.get_joy_axis(d, JOY_AXIS_LEFT_X)) > JOYSTICK_DEVICE_DEADZONE \
				or absf(Input.get_joy_axis(d, JOY_AXIS_LEFT_Y)) > JOYSTICK_DEVICE_DEADZONE:
			return true
	return stick_active


func _move_input() -> Vector2:
	var iv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	last_move_input = iv
	if iv.length() < 0.001:
		return Vector2.ZERO
	if input_is_stick():
		# direction, not throttle: full speed for any deliberate deflection
		return iv.normalized() * touch_move_magnitude
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
	var attack_held := Input.is_action_pressed("attack")

	# --- auto-target bookkeeping ---
	# Deliberately BEFORE the attack-window early return. A released button or a
	# stick pushed the other way must let go of the target IMMEDIATELY, even while
	# the character is still committed to a 1.08 s swing. Running it only outside
	# the window made a released target survive for the whole swing - the character
	# then turned and walked to a monster nobody was attacking any more.
	_update_target(delta, want, attack_held)

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

	# The "held attack walks you to the monster" half of the brief. When the
	# approach actually drove the body this frame, everything below must be
	# skipped - otherwise the free-movement block would immediately overwrite the
	# approach velocity with zero and the player would never arrive (measured: 0.2 m
	# of travel in 7 s).
	if attack_held:
		var approach := _auto_approach(delta, iv)
		if approach != Vector3.ZERO:
			_begin_attack(Kind.LIGHT)
			return
		if auto_approaching:
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

	# --- skills + the basic attack ---
	# The basic attack reads is_action_pressed, NOT just_pressed: holding the button
	# keeps the character swinging until it is released (Jan's brief). Skills stay
	# on just_pressed so they cannot be spammed by holding.
	#
	# NOTE: this is the FALLBACK path, and it is deliberately NOT reached while a live
	# auto-target exists. Jan's rule (Sept 2026): "if I have no enemy in front of me,
	# I should not swing the sword at all - finding the target has priority." With a
	# target held, the distance-only fallback used to re-fire the swing every time the
	# commitment window closed, which chopped a 180 deg turn into one slice per swing
	# AND made him chop at nothing while still turning. The assist above owns the
	# attack in that case and starts it only once the aim is settled.
	#
	# What must keep working here, exactly as before auto-target existed: swinging at
	# something that is NOT a monster (the training posts) and swinging with no target
	# at all. Removing that made a held attack do nothing whenever no monster was
	# around - tools/test_controls.gd caught it. The distinction is `target == null`,
	# NOT `target out of range`: a target that died or walked away mid-swing has
	# already been dropped by the bookkeeping at the top, so it cannot get stuck here.
	if attack_held and target == null:
		_begin_attack(Kind.LIGHT)
	elif Input.is_action_just_pressed("skill_1"):
		_begin_attack(Kind.HEAVY)


## ---------------------------------------------------------------- auto-target
## Acquires, keeps or drops `target` for this frame and keeps `auto_approaching`
## honest. Called from _physics_process BEFORE any movement decision.
##
## Rules, in the order they are applied:
##   1. A held attack is the only thing that scans. Without it there is no target.
##   2. An already-acquired target is KEPT while it is alive and within the wider
##      keep-cone (hysteresis) - this is what stops the marker flickering.
##   3. A DROPPED target is only re-acquired after `target_rearm` seconds. Without
##      that window, two monsters at the same distance trade the target every
##      other frame and the walk-in never commits.
##   4. The player's own movement input wins: pushing the stick away from the held
##      target means "I am repositioning", so the target is dropped immediately.
##
## The scan itself is a cone around `facing`, scored by angle first and distance
## second. Angle is weighted higher on purpose: a body 20 deg off the nose at 4 m
## is a better answer than one 50 deg off at 2 m, because the player is facing the
## first one and will read the choice as obvious.
func _update_target(delta: float, want: Vector3, attack_held: bool) -> void:
	_rearm_t -= delta

	if not attack_held:
		_drop_target()
		return

	# (4) THE PLAYER STEERING OUTRANKS THE AUTO-TARGET, ALWAYS. While the stick is
	# pushed he is driving: no acquisition, and anything already held is let go.
	# This is the rule that makes the assist safe. An earlier version only dropped a
	# target that sat BEHIND the pushed direction, and then re-acquired it 0.35 s
	# later - so a player walking away from a monster was pulled back toward it.
	# "Hold attack and the game moves you" is the assist; "push the stick" is the
	# player, and there is no third case worth the ambiguity.
	if want.length() > 0.01:
		_drop_target()
		return

	# (2) keep what we have, while it is still a sensible target
	if target != null:
		if not is_instance_valid(target) or not target.has_method("take_hit"):
			_drop_target()
		elif target.is_dead():
			# a corpse is not a target - fall through and pick again
			_drop_target()
		else:
			var keep := _flat_to(target.global_position)
			var keep_d := keep.length()
			var keep_angle := rad_to_deg(facing.angle_to(keep.normalized()))
			if _target_from_cone:
				if keep_d > target_range or (keep_d > 0.05
						and keep_angle > target_keep_half_deg):
					_drop_target()
			else:
				# Acquired by the DISTANCE tier: held on RANGE ALONE, because the body
				# may sit outside any keep-cone for the whole turn (he is behind us -
				# that is why he was picked). An angle test here would drop him on the
				# very next frame and the re-arm window would stop the player ever
				# turning round; measured, he acquired and lost it every 0.35 s and
				# never turned a single degree. The moment the turn brings him inside
				# `target_cone_half_deg` he becomes an ordinary cone target and the
				# keep-cone applies again.
				if keep_angle <= target_cone_half_deg:
					_target_from_cone = true
				elif keep_d > target_range:
					_drop_target()

	if target != null:
		return
	# (3) do not re-acquire in the same breath as dropping one
	if _rearm_t > 0.0:
		return

	var best: Node3D = null
	var best_score := -INF
	var best_engaged: Node3D = null
	var best_engaged_score := -INF
	# Tier 2 candidate: the NEAREST monster inside `target_range`, whatever direction
	# it stands in. Used only when the cone came up empty.
	var nearest: Node3D = null
	var nearest_d := INF
	for c in get_parent().get_children():
		if c == self or not (c is CharacterBody3D):
			continue
		if not c.has_method("take_hit") or not c.has_method("is_dead"):
			continue
		if c.is_dead():
			continue
		var to := _flat_to((c as Node3D).global_position)
		var d := to.length()
		if d < 0.01 or d > target_range:
			continue
		if d < nearest_d:
			nearest_d = d
			nearest = c
		var off := rad_to_deg(facing.angle_to(to.normalized()))
		if off > target_cone_half_deg:
			continue
		# angle dominates (it is what the player can see and predict); distance
		# breaks ties. A monster already fighting us is NOT scored higher here - see
		# the tie-break below.
		var score := -off * 2.0 - d
		if score > best_score:
			best_score = score
			best = c
		if c.has_method("is_engaged") and c.is_engaged() and score > best_engaged_score:
			best_engaged_score = score
			best_engaged = c

	# A monster already in the fight wins over an idle one, but ONLY as a TIE-BREAK:
	# the engaged candidate has to be within `engagement_margin` of the best score.
	# An earlier version just added a flat bonus to the score, and measured, that
	# bonus was smaller than the distance term - an engaged monster 5 m away still
	# lost to an idle one 3 m away on the nose, so the rule did nothing at all. It
	# is also the honest reading of the D2 behaviour: being in combat decides between
	# comparable targets, it does not make a far one beat a near one.
	if best_engaged != null and best_engaged_score >= best_score - engagement_margin:
		best = best_engaged

	# NOTHING IN THE CONE -> fall through to the nearest body in range, even directly
	# behind. Jan's report: "when nobody is in the direction he looks he attacks nobody,
	# not even an enemy standing right behind him." The cone stays the PREFERENCE (a
	# monster the player is looking at is always taken first, however close the one
	# behind is); this tier exists so a held attack is never a swing at nothing. It
	# still obeys `target_range`, so it never drags the player somewhere unexpected.
	var from_cone := true
	if best == null:
		best = nearest
		from_cone = false

	if best != target:
		target = best
		_target_from_cone = from_cone
		auto_approaching = false
		debug_text = "target: %s" % (best.name if best != null else "none")
		target_changed.emit(best)


func _drop_target() -> void:
	if target == null:
		auto_approaching = false
		return
	target = null
	auto_approaching = false
	# the rearm window starts when a target is LOST, not when one is found
	_rearm_t = target_rearm
	debug_text = "target: none"
	target_changed.emit(null)


## Walks the player in to `target` if he is too far to hit, and reports whether an
## attack should start this frame.
##
## This is the "held attack walks you to the monster" half of the brief. It only
## ever moves the player FORWARD along the target direction, so it can never be
## mistaken for a strafe or a teleport, and it stops at auto_approach_stop, which
## is just inside light_range.
func _auto_approach(delta: float, iv: Vector2) -> Vector3:
	auto_approaching = false
	if target == null or not is_instance_valid(target):
		return Vector3.ZERO
	if is_busy():
		return Vector3.ZERO

	var to := _flat_to(target.global_position)
	var d := to.length()
	if d < 0.01:
		return Vector3.ZERO

	# The player's own input is ALWAYS honoured - the auto-walk is an assist, never
	# a takeover. If he is pushing the stick, he is driving; we only turn him to
	# face the target so the swing that fires next lands.
	if iv.length() > 0.01:
		_face(to.normalized(), delta, turn_speed_attacking)
		return Vector3.ZERO

	# RUN to him when the player asked to run. Jan: "it always goes at a slow walk -
	# I need it to run to it too." The approach follows the player's OWN run intent
	# (the HUD latch / Shift / pad), so the answer is "run when RUN is on". One speed
	# for both legs of the move (turn-in and walk-in) - switching speeds between them
	# was an accident of when the `d <= stop` branch started swinging.
	var running := wants_run(iv)
	var speed := (run_speed * auto_approach_run_speed_scale) if running \
		else (walk_speed * auto_approach_speed_scale)
	_face(to.normalized(), delta, turn_speed)
	if d <= auto_approach_stop:
		# In reach. Hold still and swing - but ONLY once the aim is settled:
		# `_begin_attack` snapshots `facing` at the ACTIVE frame, so a swing started
		# while the body is still turning lands along an off-target facing. That is
		# what made the hero chop the turn into one slice per swing ("after every
		# swing it turns a few degrees"). Waiting here turns the approach into a
		# continuous run + turn, and the swing fires the moment the target is in front.
		if rad_to_deg(facing.angle_to(to.normalized())) <= attack_aim_tolerance_deg:
			velocity = velocity.move_toward(Vector3.ZERO, decel * delta)
			move_and_slide()
			if hero and hero.has_method("play_idle"):
				hero.play_idle()
			return to.normalized()
		# not lined up yet: keep the legs moving so the turn reads as a movement, not
		# as standing still and pivoting on the spot
		auto_approaching = true
		velocity = velocity.move_toward(to.normalized() * speed, accel * delta)
		move_and_slide()
		if hero and hero.has_method("play_locomotion"):
			var gs0 := velocity.length()
			if gs0 > 0.25:
				hero.play_locomotion(gs0, running and gs0 > walk_speed * 1.2)
			else:
				hero.play_idle()
		return Vector3.ZERO

	auto_approaching = true
	velocity = velocity.move_toward(to.normalized() * speed, accel * delta)
	move_and_slide()
	if hero and hero.has_method("play_locomotion"):
		var gs := velocity.length()
		if gs > 0.25:
			hero.play_locomotion(gs, running and gs > walk_speed * 1.2)
		else:
			hero.play_idle()
	return Vector3.ZERO


## Horizontal vector from the player to `p`, y zeroed: combat is fought on the
## ground plane and a monster's origin is at its feet, so a height difference must
## never change the angle or the distance the cone measures.
func _flat_to(p: Vector3) -> Vector3:
	var v := p - global_position
	v.y = 0.0
	return v


func _face(dir: Vector3, delta: float, speed: float = -1.0) -> void:
	var ts: float = turn_speed if speed < 0.0 else speed
	var d := dir.normalized()
	if d.length_squared() < 0.5:
		return
	# THE TURN IS DONE ON THE ANGLE, NOT ON THE VECTOR.
	#
	# This used to be `facing.lerp(d, ts*delta).normalized()`, which is exponential
	# decay of the angle and feels right for well-separated directions - but a lerp
	# between two nearly OPPOSITE unit vectors collapses to a vector of ~zero length,
	# and normalising that turns the body almost nothing. Measured with a monster
	# exactly behind: the player acquired it, walked BACKWARD to it facing away, swung
	# away from it and never landed a hit, with `facing.z` pinned at -1.000 for 90
	# straight frames. The failure was invisible before the distance tier existed,
	# because nothing ever picked a body behind the player.
	#
	# Decaying the SIGNED ANGLE by the same `ts*delta` factor reproduces the old
	# dynamics exactly for every direction that used to work (same exponential, same
	# rate) and has no degenerate case: a 180 deg turn starts turning immediately, the
	# short way.
	var ang := facing.signed_angle_to(d, Vector3.UP)
	var step := ang * clampf(ts * delta, 0.0, 1.0)
	facing = facing.rotated(Vector3.UP, step).normalized()
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
