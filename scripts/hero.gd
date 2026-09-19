extends Node3D
## Wraps the rigged, animated hero model so player.gd does not care about
## animation internals.
##
## The model ships with 45 animations. These are the ones the game uses; the
## names must match the GLB exactly or the animation silently does nothing.
##
## The visual is a CHILD of the CharacterBody3D and faces -Z, while gameplay
## logic uses `facing`. That means the visual's yaw is the inverse of player
## rotation, which is set from player.gd.
##
## NOTE: Godot's glTF importer STRIPS the "_Loop" suffix from clip names.
## The source file says "Rig|Walk_Loop" but Godot exposes "Rig|Walk".
## Verified with tools/list_anims.gd - do not guess these.

const CLIP_IDLE := "Rig|Sword_Idle"          ## combat-ready stance, not a relaxed idle
const CLIP_WALK := "Rig|Walk"                ## was Rig|Walk_Loop in the source file
const CLIP_RUN := "Rig|Sprint"               ## the run: short cycle, big stride
const CLIP_ATTACK := "Rig|Sword_Attack"      ## light swing, 1.50 s
const CLIP_ATTACK_HEAVY := "Rig|Sword_Attack_RM"
const CLIP_HIT := "Rig|Hit_Chest"            ## 0.33 s
const CLIP_DEATH := "Rig|Death01"            ## 2.38 s
const CLIP_SPELL := "Rig|Spell_Simple_Shoot" ## 0.50 s

## The sword clips are played at 1x (the clip's own speed). They used to run at
## 2x with a 0.75 s window, which Jan reported as "the attack animation is very
## fast" - the blade swept past before the eye could read the swing. The window
## in player.gd is now 1.08 s and the clip is played at 1x, so the contact frame
## (frame 10 of 36, MEASURED by tools/blender/measure_gait.py) lands exactly on
## the damage frame: windup 0.42 s == 42 % of the 1.5 s clip.
const ATTACK_SPEED := 1.0
const HEAVY_SPEED := 1.0

## MEASURED on the shipped model by tools/blender/measure_gait.py (toe-contact
## method, same as the original walk calibration). Ground covered per cycle at
## 1x playback:
##   Rig|Walk    1.267 m over 1.333 s =  0.951 m/s
##   Rig|Sprint  1.110 m over 0.667 s =  1.666 m/s
## The player moves faster than either clip at 1x, so the clip is re-timed from
## the character's ACTUAL ground speed - otherwise the planted foot slides.
## Re-measure if a locomotion clip is ever replaced; do not re-guess these.
const WALK_GROUND_SPEED := 0.951
const RUN_GROUND_SPEED := 1.666

var model: Node3D
var anim: AnimationPlayer

var _current: String = ""


func _ready() -> void:
	var packed: PackedScene = load("res://models/hero.glb")
	if packed == null:
		push_error("hero.glb could not be loaded")
		return
	model = packed.instantiate()
	# the model faces -Z already, which matches the project's forward
	add_child(model)

	anim = _find_animation_player(model)
	if anim == null:
		push_warning("no AnimationPlayer found in hero.glb")
		return
	_clip_names = anim.get_animation_list()
	print("[hero] animations available: %d" % _clip_names.size())
	for want in [CLIP_IDLE, CLIP_WALK, CLIP_RUN, CLIP_ATTACK, CLIP_HIT]:
		if not _clip_names.has(want):
			push_warning("[hero] missing animation: %s" % want)
	_play(CLIP_IDLE, 1.0, true)


var _clip_names: PackedStringArray = PackedStringArray()


func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_animation_player(c)
		if r != null:
			return r
	return null


func _play(clip: String, speed: float = 1.0, loop: bool = true) -> void:
	if anim == null or not _clip_names.has(clip):
		return
	if _current == clip and anim.is_playing():
		return
	_current = clip
	# custom_speed stays 1.0 and the retime is carried by `speed_scale` ALONE.
	#
	# MEASURED (tools/probe_clip_rate2.gd, matrix of custom_speed x speed_scale):
	# Godot 4 MULTIPLIES the two. `play(clip, -1.0, s)` together with
	# `speed_scale = s` ran every locomotion clip at s^2 - the walk at 2.734^2 =
	# 7.5x and the run at 2.641^2 = 7.0x. Jan reported it as "after switching from
	# walk to run the animation is extremely fast, and only settles after stopping
	# and starting again": the run's acceleration window changes the rate the most,
	# so the doubled multiplier is worst exactly at the switch.
	anim.play(clip, -1.0, 1.0)
	# Set explicitly: play()'s custom_speed is not reliable for RESETTING a
	# speed_scale left over from the walk clip, and the idle then ran at 2.7x.
	anim.speed_scale = speed
	var a: Animation = anim.get_animation(clip)
	if a:
		a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE


func current_clip() -> String:
	return _current


# ---------------------------------------------------------------- API for player.gd
func play_idle() -> void:
	_play(CLIP_IDLE, 1.0, true)


## Locomotion is one call with two inputs: how fast the character is actually
## moving over the ground, and whether the player asked to run. The clip AND its
## playback rate follow from those, so the feet stay planted at every speed.
func play_locomotion(ground_speed: float, running: bool) -> void:
	var clip := CLIP_RUN if running else CLIP_WALK
	var base := RUN_GROUND_SPEED if running else WALK_GROUND_SPEED
	var s := clampf(ground_speed / base, 0.2, 4.0)
	if _current == clip and anim != null and anim.is_playing():
		anim.speed_scale = s
		return
	_play(clip, s, true)


func play_walk() -> void:
	play_locomotion(WALK_GROUND_SPEED, false)


func play_run() -> void:
	play_locomotion(RUN_GROUND_SPEED, true)


func play_attack(heavy: bool = false) -> void:
	_play(CLIP_ATTACK_HEAVY if heavy else CLIP_ATTACK,
		HEAVY_SPEED if heavy else ATTACK_SPEED, false)


func play_hit() -> void:
	_play(CLIP_HIT, 1.0, false)


func play_death() -> void:
	_play(CLIP_DEATH, 1.0, false)


func play_spell() -> void:
	_play(CLIP_SPELL, 1.0, false)
