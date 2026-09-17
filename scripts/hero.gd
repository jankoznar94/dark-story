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

## NOTE: Godot's glTF importer STRIPS the "_Loop" suffix from clip names.
## The source file says "Rig|Walk_Loop" but Godot exposes "Rig|Walk".
## Verified with tools/list_anims.gd - do not guess these.
const CLIP_IDLE := "Rig|Sword_Idle"          ## combat-ready stance, not a relaxed idle
const CLIP_WALK := "Rig|Walk"                ## was Rig|Walk_Loop in the source file
const CLIP_ATTACK := "Rig|Sword_Attack"      ## light swing, 1.50 s
const CLIP_ATTACK_HEAVY := "Rig|Sword_Attack_RM"
const CLIP_HIT := "Rig|Hit_Chest"            ## 0.33 s
const CLIP_SPELL := "Rig|Spell_Simple_Shoot" ## 0.50 s

## Sword_Attack is 1.50 s long. At 2x that is a 0.75 s swing, which matches the
## player's windup+active+recover window (0.30+0.12+0.33=0.75) so the blade lands
## with the hit rather than still swinging afterwards.
const ATTACK_SPEED := 2.0
const HEAVY_SPEED := 1.7

var model: Node3D
var anim: AnimationPlayer

var _current: String = ""
var _busy_until: float = 0.0


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
	for want in [CLIP_IDLE, CLIP_WALK, CLIP_ATTACK, CLIP_HIT]:
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
	anim.play(clip, -1.0, speed)
	var a: Animation = anim.get_animation(clip)
	if a:
		a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE


# ---------------------------------------------------------------- API for player.gd
func play_idle() -> void:
	_play(CLIP_IDLE, 1.0, true)


func play_walk() -> void:
	_play(CLIP_WALK, 1.0, true)


func play_attack(heavy: bool = false) -> void:
	_play(CLIP_ATTACK_HEAVY if heavy else CLIP_ATTACK,
		  HEAVY_SPEED if heavy else ATTACK_SPEED, false)


func play_hit() -> void:
	_play(CLIP_HIT, 1.0, false)


func play_spell() -> void:
	_play(CLIP_SPELL, 1.0, false)
