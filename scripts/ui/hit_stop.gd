extends Node
class_name HitStop
## HitStop — the few-frame freeze that makes a blow read as an IMPACT rather than as a
## number change. It scales `Engine.time_scale` for a few tens of milliseconds.
##
## ⚠️  IT IS NOT A GAMEPLAY GATE, AND THAT IS THE WHOLE DESIGN. The combat runs on a fixed
## 100 ms tick inside `battle.gd` and the RULES must never see a partial tick. The safe shape
## is `arena_screen`'s: hold the tick budget in a float accumulator in MILLISECONDS and spend
## it in whole `TICK_MS` steps. `Engine.time_scale` scales `SceneTree.delta`, so a frozen
## frame adds proportionally less to that accumulator and the next unfrozen frames carry the
## rest — no tick is ever split, no rule ever sees a partial one.
##
## ⚠️  AND THE FIGHT REALLY IS 50 ms LONGER. This is a FREEZE, not a pause that gives the time
## back: the world's clock genuinely loses that 50 ms, so a fight sees
## `floor((wall_ms - freeze_ms_total) / 100)` ticks. Claiming "the same tick count" would be
## wrong, and it is the kind of wrong that only shows up as a subtly long fight. What is
## guaranteed is the DISCRETENESS — the rules advance in whole ticks and nothing else about
## them changes. A test must assert the tick count against the wall time it actually got, not
## against a fight that never froze.
##
## What the player gets: the swing arc, the HP rings, the float numbers and the hit wash all
## move on real time, so they stall for those 50 ms too, and the instant of the blow stands
## still. That is the effect.
##
## `Engine.time_scale` is GLOBAL, so this node is the only thing in the game allowed to write
## it, and it always restores the value it found.

static var instance: HitStop = null

## A landed blow. Any longer than this and a fight with a 450 ms weapon reads as hitching
## rather than as hitting.
const HIT_MS := 50
## A crit gets a touch more. The game already says "crit" three other ways (the cue, the
## number, the hit wash); this is the fourth and it adds no rule.
const CRIT_MS := 80
## A level-up. Short on purpose — the fanfare is the event.
const BIG_MS := 120

## How many freezes were requested and how many actually ran — the decision layer a headless
## test can assert, in the same shape as `Sfx.played_count`.
var requested_count := 0
var started_count := 0

var _active := false
var _restore := 1.0
var _until_ms := 0


func _ready() -> void:
	instance = self
	# ⚠️  `_process` must keep running while the tree is scaled, or the freeze could never
	# end: a node in PROCESS_MODE_PAUSABLE is not paused by time_scale, but an inherited mode
	# on a child of a paused subtree would be, and this one has to be unconditional.
	process_mode = Node.PROCESS_MODE_ALWAYS


## The entry point every call site uses. A request arriving while a freeze is already running
## is DROPPED rather than queued: two blows inside one 100 ms tick (Double Swing) would
## otherwise freeze the fight for twice as long, which reads as a stall, not as two hits.
static func freeze(duration_ms: int) -> void:
	if instance != null:
		instance.hit(duration_ms)


func hit(duration_ms: int = HIT_MS) -> void:
	requested_count += 1
	if _active:
		return
	started_count += 1
	_active = true
	_restore = Engine.time_scale
	Engine.time_scale = maxf(0.01, _restore * 0.05)
	# ⚠️  The clock has to be the WALL clock, never `delta`: `delta` is already multiplied by
	# `time_scale`, so a freeze timed from it would stretch its own duration by 1/scale and a
	# 50 ms freeze would last a second. This project has already measured that exact class of
	# bug on an animation that ran 20x short.
	_until_ms = Time.get_ticks_msec() + duration_ms


func is_active() -> bool:
	return _active


func _process(_delta: float) -> void:
	if not _active:
		return
	if Time.get_ticks_msec() >= _until_ms:
		_release()


func _release() -> void:
	_active = false
	Engine.time_scale = _restore
