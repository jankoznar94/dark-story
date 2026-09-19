extends SceneTree
## How much do the LEGS slow down, and what does it cost in foot slide?
##
## Jan's brief (Sept 2026): "keep the speed, slow the legs down." At a fixed body
## speed, playing a clip SLOWER means it covers less ground per cycle, so the
## planted foot must slide forward - that is unavoidable. The question is only how
## much, so this probe sweeps the retime and reports BOTH numbers per candidate:
##
##   cadence (steps/s) = rate * 2 / clip_length      <- what Jan wants lowered
##   slide   (m/s)     = forward world speed of the planted foot  <- the cost
##
## The retime is set through the hero's instrumentation override, where `base` is
## the clip constant the game divides by - a LARGER base means the clip plays
## SLOWER. `base` of the clip's own authored speed = no slide at all.
##
## Contamination guard: the last run of this probe measured Rig|Sword_Idle because
## the character walked into a prop and stopped. Every sample here asserts that the
## clip is still the candidate AND the body is still moving, and prints STOPPED
## instead of reporting a number if either fails.
##
## Run: godot --headless --path . --script res://tools/probe_leg_speed.gd

const CLIP := "Rig|Jog_Fwd"
const CYCLE := 0.917          ## clip length, from tools/list_anims.gd
const BODY := 3.05            ## the run speed that must not change
const START := Vector3(0, 0.05, 15.5)   ## long clear lane, running toward -Z
const BASES := [1.605, 2.0, 2.3, 2.6, 2.9]
const WINDOW := 60            ## physics frames sampled (1.0 s)
const BAND := 0.04
const MIN_TRAVEL := 1.0       ## below this the sample is contaminated - report it

var main: Node
var player: Node
var hero: Node3D
var skel: Skeleton3D
var toe_l: int
var toe_r: int


func _init() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	call_deferred("_run")


func _run() -> void:
	for i in 3:
		await physics_frame
	main.clear_enemies()
	player = main.get_node("Player")
	hero = player.get_node("Hero")
	skel = _find_skel(hero.model)
	toe_l = skel.find_bone("DEF-toe.L")
	toe_r = skel.find_bone("DEF-toe.R")
	print("== leg speed probe: clip %s, cycle %.3f s, body %.2f m/s (body speed LOCKED)"
		% [CLIP, CYCLE, BODY])
	print("base  | rate  | cadence | stride | slide   | body   | clip_ok | travel")
	for b in BASES:
		await _probe(b)
	print("LEG_SPEED_DONE")
	quit()


func _probe(base: float) -> void:
	hero.clip_run_override = CLIP
	hero.run_ground_speed_override = base
	main.hud.run_latched = true
	player.global_position = START
	player.velocity = Vector3.ZERO
	player.run_speed = BODY
	Input.action_press("move_up")

	# run up to terminal speed over a short, clear stretch
	var t := 0.0
	while t < 1.6 and player.velocity.length() < BODY * 0.97:
		await physics_frame
		t += 1.0 / 60.0
	for i in 6:
		await physics_frame

	var fl: Array = []
	var fr: Array = []
	var steps: Array = []
	var clips: Array = []
	var prev: Vector3 = player.global_position
	for i in WINDOW:
		await physics_frame
		var bp: Vector3 = player.global_position
		fl.append((skel.global_transform * skel.get_bone_global_pose(toe_l)).origin)
		fr.append((skel.global_transform * skel.get_bone_global_pose(toe_r)).origin)
		steps.append(bp - prev)
		clips.append(hero.current_clip())
		prev = bp
	var rate: float = await _measure_rate(hero.anim)
	Input.action_release("move_up")

	var travel := 0.0
	for s in steps:
		travel += Vector2(s.x, s.z).length()
	var body_rates: Array = []
	for s in steps:
		body_rates.append(Vector2(s.x, s.z).length() * 60.0)
	var v_body: float = _median(body_rates)
	var dir: Vector2 = Vector2.ZERO
	for s in steps:
		dir += Vector2(s.x, s.z)
	dir = dir.normalized()

	var ymin_l: float = 1e9
	var ymin_r: float = 1e9
	for i in WINDOW:
		ymin_l = minf(ymin_l, fl[i].y)
		ymin_r = minf(ymin_r, fr[i].y)
	var slides: Array = []
	for i in range(1, WINDOW):
		var li: int = 0 if fl[i - 1].y <= fr[i - 1].y else 1
		var li_now: int = 0 if fl[i].y <= fr[i].y else 1
		if li != li_now:
			continue
		var planted: bool = (fl[i].y <= ymin_l + BAND) if li == 0 else (fr[i].y <= ymin_r + BAND)
		if not planted:
			continue
		var a: Vector3 = fl[i - 1] if li == 0 else fr[i - 1]
		var b: Vector3 = fl[i] if li == 0 else fr[i]
		slides.append(Vector2(b.x - a.x, b.z - a.z).dot(dir) * 60.0)
	var v_slide: float = _median(slides)

	# a contaminated sample is reported as such, never as a number
	var clip_ok := true
	for c in clips:
		if c != CLIP:
			clip_ok = false
	if travel < MIN_TRAVEL or not clip_ok:
		print("%.3f | STOPPED - sample contaminated (travel %.2f m, clip %s) - ignored"
			% [base, travel, clips[WINDOW - 1]])
	else:
		var cadence: float = 0.0 if CYCLE <= 0.0 else rate * 2.0 / CYCLE
		var stride: float = 0.0 if cadence <= 0.0 else v_body / cadence
		print("%.3f | %.3f | %.2f    | %.3f  | %+.3f  | %.3f | %s    | %.2f m"
			% [base, rate, cadence, stride, v_slide, v_body, str(clip_ok), travel])

	hero.clip_run_override = ""
	hero.run_ground_speed_override = -1.0
	main.hud.run_latched = false
	player.velocity = Vector3.ZERO
	for i in 3:
		await physics_frame


func _measure_rate(anim: AnimationPlayer) -> float:
	var prev: float = anim.current_animation_position
	var t_prev: int = Time.get_ticks_usec()
	var moved := 0.0
	var elapsed := 0.0
	for i in 8:
		await process_frame
		var p: float = anim.current_animation_position
		var t: int = Time.get_ticks_usec()
		var d: float = p - prev
		if d >= 0.0:
			moved += d
			elapsed += float(t - t_prev) / 1000000.0
		prev = p
		t_prev = t
	return -1.0 if elapsed <= 0.0 else moved / elapsed


func _median(v: Array) -> float:
	if v.is_empty():
		return 0.0
	var s: Array = v.duplicate()
	s.sort()
	return float(s[s.size() / 2])


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null
