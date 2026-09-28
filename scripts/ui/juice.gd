extends Node
class_name Juice
## Juice — the one place the game is allowed to MOVE and to BUZZ.
##
## Why a single node and not a helper per screen: feel is a cross-cutting effect (a tap, a
## hit, a level-up all want the same three things), and this project has already paid once
## for scattering one concern — the click sound had to be re-installed screen by screen
## until `main.gd` took it over wholesale (`_install_click_sfx`). The shape here is copied
## from `sfx.gd` deliberately: one instance created by `main.gd`, static entry points that
## are a NO-OP when no instance exists, so a headless `SceneTree` test that never built the
## game cannot crash on a decoration.
##
## It is NEVER a gate on gameplay. A Tween on a Control is decoration; the rules
## (`battle.gd`'s fixed 100 ms clock) run whatever this node does.

static var instance: Juice = null

## `Input.vibrate_handheld` is implemented on Android, iOS AND Web in Godot 4.7 — but on the
## web it goes through `navigator.vibrate`, which only Chrome/Android implement. iOS Safari
## has no vibration API at all, so the call returns false on exactly the device family Jan
## may be holding. That is why every haptic call site pairs it with something VISIBLE: the
## buzz is a bonus, never the message.
const HAPTIC_TAP_MS := 8
## A landed blow under the hero's own thumb. Deliberately short — a 40 ms buzz on a fast
## weapon reads as a rattle, not as impact.
const HAPTIC_HIT_MS := 18
const HAPTIC_CRIT_MS := 30
const HAPTIC_LEVEL_MS := 45
## Two rules can land in one 100 ms tick (Double Swing), and a buzz is a platform syscall.
## Anything inside this window is swallowed — dropped, never queued, because a queued buzz
## arrives after the moment it was describing.
const HAPTIC_MIN_GAP_MS := 40

## A tap's press animation: 0.97 over 60 ms and BACK to 1.0. Returning is the point — Jan's
## standing rule is that a phone has no hover, so a control shows state only while it IS
## pressed, and a control that shrank and stayed small is exactly the sticky state he
## rejected. One pair of numbers so no call site invents its own feel.
const PRESS_SCALE := 0.97
const PRESS_SECONDS := 0.06
## A screen becoming visible: 0.94 -> 1.0 with a fade, 110 ms. Deliberately small and short
## — the port had NO transition at all (the router flipped `visible`), which is what made
## every navigation read as a cut, but a slide or a crossfade would fight the PWA's own
## `position:fixed` screens.
const ENTER_SCALE := 0.94
const ENTER_SECONDS := 0.11

## The last buzz asked for, and how many were asked for at all — the same shape as
## `Sfx.last_cue` and for the same reason: a headless test has no motor, so the only
## assertable thing is the DECISION ("this event wanted a crit buzz"), never the vibration.
var last_haptic_ms := 0
var haptic_count := 0

var _last_haptic_at := -HAPTIC_MIN_GAP_MS
## Bumped by a test that wants the platform call itself exercised without a phone.
var _force_platform := false


func _ready() -> void:
	instance = self


## One buzz. Safe everywhere: on desktop the platform layer is a no-op and on a phone with
## no motor it returns false, so nothing needs an `OS.has_feature("web")` branch around it.
func vibrate(duration_ms: int) -> void:
	last_haptic_ms = duration_ms
	haptic_count += 1
	var now := Time.get_ticks_msec()
	if now - _last_haptic_at < HAPTIC_MIN_GAP_MS:
		return
	_last_haptic_at = now
	if _force_platform or ClassDB.class_has_method("Input", "vibrate_handheld", true):
		Input.vibrate_handheld(duration_ms)


static func haptic_tap() -> void:
	if instance != null:
		instance.vibrate(HAPTIC_TAP_MS)


static func haptic_hit() -> void:
	if instance != null:
		instance.vibrate(HAPTIC_HIT_MS)


static func haptic_crit() -> void:
	if instance != null:
		instance.vibrate(HAPTIC_CRIT_MS)


static func haptic_level() -> void:
	if instance != null:
		instance.vibrate(HAPTIC_LEVEL_MS)


## Stop whatever tween is stored under `key` on `node`, so a second animation can start.
##
## ⚠️  Guarded by `has_meta`, NOT by `get_meta(key, null)`: on this engine build
## `get_meta("missing", null)` does NOT fall back to the default — it pushes
## `The object does not have any 'meta' values with the key` as an ERROR and returns null, which
## floods the log with a red line per press. `has_meta` first is the honest form.
static func _stop_tween(node: Control, key: String) -> void:
	if not node.has_meta(key):
		return
	var old: Tween = node.get_meta(key)
	if old != null and old.is_valid():
		old.kill()


static func press_on(node: Button) -> void:
	if node == null or not is_instance_valid(node):
		return
	if instance == null:
		# No game built (a headless test). Do not wire a handler that can only no-op.
		return
	# ⚠️  A Button that is ALREADY wired must not be wired twice: two `pressed` handlers
	# would run `_press` back to back, the second one killing the first's tween, and the
	# shove would read as half-length. Factories hand a button back to their caller, and a
	# caller may legitimately pass it through a second factory.
	if node.has_meta("juice_press_wired"):
		return
	node.set_meta("juice_press_wired", true)
	# The lambda captures `self` (a Juice instance) rather than the static name `Juice`: a
	# script cannot reference its own `class_name` from inside itself — that is a hard compile
	# error, not a warning, and it takes the whole file (and every file that preloads it) down
	# with it.
	node.pressed.connect(func(): press(node))


## `press()` — the visual half of a tap, for the controls that do not come out of `UIKit`
## (which applies the same thing itself, so a plain screen button never double-animates).
static func press(node: Control, strength: float = PRESS_SCALE,
		seconds: float = PRESS_SECONDS) -> void:
	if instance == null:
		return
	instance._press(node, strength, seconds)


func _press(node: Control, strength: float, seconds: float) -> void:
	if node == null or not is_instance_valid(node):
		return
	# Two tweens would fight over the same `scale` and the control would end up at whatever the
	# loser wrote.
	_stop_tween(node, "juice_press_tween")
	# The pivot has to be the middle, or the control shrinks toward its top-left corner and
	# reads as moving rather than as being pushed.
	node.pivot_offset = node.size * 0.5
	# ⚠️  THE SHRINK IS APPLIED SYNCHRONOUSLY AND ONLY THE RELEASE IS TWEENED, and both halves of
	# that matter. A press that EASES into its shrunken size arrives after the finger is already
	# up — the tap and the reaction come apart, which is the exact "the phone did not register
	# it" feel this whole layer exists to remove. Measured on the first version (both directions
	# tweened): at the first frame that could observe it the control was still at 1.0000, because
	# a frame here is ~50 ms and the whole 60 ms shrink had not been drawn yet.
	node.scale = Vector2(strength, strength)
	var tween := node.create_tween()
	node.set_meta("juice_press_tween", tween)
	tween.tween_property(node, "scale", Vector2.ONE, seconds)


## `enter()` — the settle a screen plays as it becomes visible: 0.94 -> 1.0 with a fade over
## 110 ms, pivoted on the screen's own centre.
##
## The caller must call this BEFORE setting `visible = true`: `pivot_offset` needs the laid-out
## `size`, and a hidden full-rect Control has not been laid out yet — pivoting on a zero rect
## shrinks the screen into its top-left corner, which reads as the page flying off rather than
## as it settling in.
static func enter(node: Control, from: float = ENTER_SCALE,
		seconds: float = ENTER_SECONDS) -> void:
	if instance == null:
		return
	instance._enter(node, from, seconds)


func _enter(node: Control, from: float, seconds: float) -> void:
	if node == null or not is_instance_valid(node):
		return
	_stop_tween(node, "juice_enter_tween")
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2(from, from)
	node.modulate = Color(1, 1, 1, 0.0)
	var tween := node.create_tween()
	node.set_meta("juice_enter_tween", tween)
	# Parallel: a screen that shrank and THEN faded reads as two events.
	tween.set_parallel(true)
	tween.tween_property(node, "scale", Vector2.ONE, seconds)
	tween.tween_property(node, "modulate", Color.WHITE, seconds)


## A node Juice has animated is NOT safe to leave mid-tween when the screen that owns it is
## torn down, or when it is coming back into view later. Call this from any screen that hides a
## node Juice touched — `show_screen` does it for every screen it routes away from.
## ⚠️  Cleans up even with NO instance, unlike `press` / `enter`: this is the UNDO path, and a
## screen left mid-settle by a run that had an instance and is being torn down by one that does
## not would keep the residue forever. Undoing is safe unconditionally; starting is not.
static func reset(node: Control) -> void:
	if node == null or not is_instance_valid(node):
		return
	for key in ["juice_press_tween", "juice_enter_tween"]:
		_stop_tween(node, key)
	node.scale = Vector2.ONE
	node.modulate = Color.WHITE
