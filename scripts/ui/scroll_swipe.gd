extends Node
class_name ScrollSwipe
## ScrollSwipe — a swipe driver for a `ScrollContainer`, for the platforms where Godot's own
## drag is switched off.
##
## Godot's `ScrollContainer` only drags with a finger when
## `DisplayServer.is_touchscreen_available()` is true — its own source:
##
##     bool is_touchscreen_available = DisplayServer::get_singleton()->is_touchscreen_available();
##     if (!is_touchscreen_available) { return; }
##
## That is `true` on Android (hardcoded) and on any device with a touchscreen, and **false on
## a plain desktop browser** (`'ontouchstart' in window`), in the editor and in a headless run.
## So the WEB build — the one Jan plays — had a page that could only be scrolled by grabbing
## the scrollbar, which is exactly the thing he did not want on screen.
##
## This node listens in `_input`, which runs BEFORE the GUI, and it never marks the incoming
## event as handled: a plain tap still reaches the button under the finger.
##
## A DRAG is a different thing from a tap, and Godot does not separate them for us. A press
## that stays inside the button's own rect keeps `pressing_inside` set, so the release fires
## the button — the player drags the page and opens a shop tile. Measured with
## `tools/probe_tap_drag.gd` through the real Viewport pipeline. So once the movement crosses
## the deadzone this driver CANCELS the press it started over, by pushing a synthetic release
## whose position hits no control at all: the viewport still delivers it to the control that
## took the press (that is how dragging off a button normally clears it), the position is
## outside that control's rect, so no `pressed` signal is emitted and no pressed visual is
## left behind. `_start` is only used for the deadzone's bookkeeping there.
##
## The deadzone is small (8px, the ScrollContainer's own), so a tap remains a tap: it is only
## a finger that actually moved that loses its button press.
##
## ── WHY THIS DRIVER NOW RUNS ON EVERY PLATFORM ───────────────────────────────────────────
##
## It used to stand down on a touchscreen (`is_touchscreen_available()` -> return), on the
## theory that Godot's own finger drag would handle the phone and two drivers would scroll
## twice as fast. **On a phone that theory produced a page which cannot be scrolled from a
## button at all** — measured on the port's own web build under CDP touch emulation:
##
##     desktop profile: drag starting on a town tile -> page scrolled 56px
##     touch   profile: drag starting on a town tile -> page did NOT move
##     touch   profile: drag starting on empty space  -> page scrolled 56px
##
## which is Jan's report exactly: "when I tap a button and want to scroll, it doesn't work at
## all. I have to hit somewhere where nothing is, which is sometimes a problem."
##
## The cause is that Godot's `ScrollContainer` begins its drag on the PRESS
## (`if (mb->is_pressed()) { ... drag_touching = true; }`), and a `Button` under the finger
## consumes that press, so the container never enters drag mode and the following motion is
## ignored. This driver only *cancels* the button's press AFTER the deadzone — by then the
## container has already missed the press it needed. Godot's own drag can therefore never be
## made to start from a button, and the driver is the only thing that can.
##
## `setup()` therefore makes Godot's own drag INERT (a `scroll_deadzone` far larger than any
## finger movement, so `beyond_deadzone` never flips) and this node becomes the ONE scroll
## implementation on every platform. One path is also the only one that can be tested: the
## arithmetic below is what `tools/test_page_scroll.gd` drives, and the same arithmetic is
## what a finger now gets on a phone.
##
## A WHEEL is untouched by all this — `gui_input`'s wheel branch runs before the deadzone is
## ever consulted, so a desktop mouse wheel still scrolls natively.
##
## ── MOMENTUM: the page keeps going after the finger leaves ───────────────────────────────
##
## Jan: "the scroll only moves by the distance the finger moved; I need it like a browser —
## swipe and it keeps going with some inertia, that is much faster to scroll through."
##
## A drag that tracked the finger one-for-one is the *minimum* of a scroll view, not the feel
## of one. The flick is what makes a long page usable: the finger gives the page a velocity
## and the page coasts to a stop. Three things decide whether that reads as a browser or as a
## glitch, and all three are easy to get wrong:
##
##   1. **The velocity comes from the last few MOTION events, not from the whole drag.** A
##      finger that drags slowly, stops, and then lets go must NOT fling — so the velocity is
##      sampled per event with a time stamp and decays to zero once the finger has been still
##      for `flick_hold_ms` before the release.
##   2. **The decay is per SECOND, not per FRAME.** `_vel *= 0.9` every frame is frame-rate
##      dependent: the same flick travels twice as far at 120 fps as at 60. It is
##      `exp(-deceleration * delta)`, so the distance is the same on any device.
##   3. **It has to stop at the end of the page, by itself.** A fling that keeps pushing a
##      bar already sitting at its limit sits there "vibrating" (and, before the check below,
##      simply never ended). The fling ends when the page stops moving in response to it.
##
## Only a FINGER flings: a mouse drag is a deliberate, precise gesture and browsers do not
## coast after one, so a desktop mouse keeps the old one-for-one behaviour.

## Movement before the drag is allowed to move the page, matching the ScrollContainer's own
## `scroll_deadzone`. Without it every tap would nudge the page.
var deadzone := 8.0

## Friction of the coast, as an exponential rate per second: the distance a flick travels is
## `v0 / deceleration` px. 2.5 gives a strong flick (~2000 px/s) roughly 800 px of travel —
## about one page of this app — and a hard one (~4000 px/s) two pages.
var deceleration := 2.5
## Below this speed (px/s) a release is a drag that ended, not a flick, and nothing coasts.
var min_flick_speed := 120.0
## A flick faster than this is clamped, so a violent swipe cannot throw the page across
## several screens.
var max_flick_speed := 4000.0
## Once the coast is slower than this (px/s) it is over.
var stop_speed := 30.0
## How long the finger may be still before letting go and still count as a flick. A release
## arrives a frame or two after the last motion; a real pause means the player stopped on
## purpose, and then the page must stop with them.
var flick_hold_ms := 80

var _scroll: ScrollContainer = null
## Which pointer is mid-drag: -1 = the mouse, >= 0 = a finger's index, INACTIVE = nobody.
const INACTIVE := -2
## Set while this node pushes its OWN synthetic events (see `_cancel_press`), so it does not
## read them back as the player's input and end its own drag.
var _synthetic := false
var _pointer := INACTIVE
var _start := Vector2.ZERO
var _accum := 0.0
var _past_deadzone := false
## The PAGE's own velocity in px/s: positive = the page moves down the content = scrolling
## DOWN. `_move` works out the same quantity as `-dy / dt`, which is what a drag moves the bar
## by, so a flick is exactly the finger's last motion carried on. Sampled per motion event and
## only trusted at the release (see the header).
var _vel := 0.0
## Whether the CURRENT gesture arrived as a finger. Set on the press and kept for the whole
## gesture, because a phone's finger also arrives as an emulated mouse event — see `_begin`.
var _from_touch := false
## Time stamp of the last motion event, 0 = none yet in this gesture.
var _last_ms := 0
var _flinging := false
## The clock the flick is measured on. It is real time; a TEST replaces it so a gesture can be
## given a realistic duration without sleeping (a headless run delivers every event inside the
## same millisecond, where a real velocity does not exist).
var clock: Callable = Callable()


func setup(scroll: ScrollContainer) -> void:
	_scroll = scroll
	# Make Godot's OWN finger drag inert so this node is the single scroll path on every
	# platform (see the header). `ScrollContainer` flips `beyond_deadzone` only once
	# `abs(drag_accum) > scroll_deadzone`, so a deadzone larger than the canvas can never be
	# crossed by a finger and its drag stays off — while the WHEEL branch runs earlier and
	# still works for a desktop mouse.
	if scroll != null:
		scroll.scroll_deadzone = 1_000_000
	# Nothing to do per frame until a flick starts (`_start_fling`).
	set_process(false)


func _input(event: InputEvent) -> void:
	# Our own cancel sequence comes back through this same stage; treating it as the player's
	# finger would end the drag we are trying to keep.
	if _synthetic:
		return
	if _scroll == null or not is_instance_valid(_scroll):
		return
	if not _scroll.is_visible_in_tree():
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_begin(touch.position, touch.index, true)
		elif _pointer == touch.index:
			_end(_now_ms())
		return

	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		# A drag can only come from a finger, so it is what MARKS a phone's gesture as one
		# (see `_begin`). The adoption of a mouse-opened gesture here is a SECOND defence: the
		# touch press already upgrades the gesture, and this only matters if a device delivers
		# the drag without the touch press. (Mutation: removing this line alone leaves the
		# test suite green — the press upgrade is what carries the case.)
		if _pointer == drag.index or (_pointer == -1 and not _from_touch):
			_pointer = drag.index
			_from_touch = true
			_move(drag.relative.y, _now_ms())
		return

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_begin(button.position, -1, false)
		elif _pointer == -1:
			_end(_now_ms())
		return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _pointer != -1:
			return
		if not (motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
			return
		_move(motion.relative.y, _now_ms())


## Real time in milliseconds, or the test's replacement (see `clock`). Every time stamp in this
## file goes through here, so a test can give a gesture a realistic duration.
func _now_ms() -> int:
	if clock.is_valid():
		return int(clock.call())
	return Time.get_ticks_msec()


## The page coasts after a flick, one frame at a time.
##
## `delta` is REAL time and the decay is exponential in it, so the flick travels the same
## distance whether the device runs at 60 or 120 Hz.
func _process(delta: float) -> void:
	if not _flinging:
		set_process(false)
		return
	if _scroll == null or not is_instance_valid(_scroll):
		_stop_fling()
		return
	var bar := _scroll.get_v_scroll_bar()
	var before := bar.value
	bar.value += _vel * delta
	# A bar already sitting at its limit does not move, and a fling that keeps pushing it
	# would never end — the page would look frozen mid-flick. The page not moving IS the end.
	if is_equal_approx(bar.value, before):
		_stop_fling()
		return
	_vel *= exp(-deceleration * delta)
	if absf(_vel) < stop_speed:
		_stop_fling()


## A flick is only ever given by a FINGER — that is why the two release sites in `_input` pass
## their own answer to `_end()`. A mouse drag is a deliberate, precise gesture and no browser
## coasts after one; keeping the mouse one-for-one also keeps a desktop drag testable.


## Let the page coast with the velocity the finger left it with.
func _start_fling() -> void:
	if absf(_vel) < min_flick_speed:
		return
	_vel = clampf(_vel, -max_flick_speed, max_flick_speed)
	_flinging = true
	set_process(true)


func _stop_fling() -> void:
	_flinging = false
	_vel = 0.0
	set_process(false)


## A drag only starts inside the page. A swipe anywhere else in the window is somebody
## else's event — the arena has its own input and must not scroll a hidden town page.
##
## ⚠️ The rect MUST be the scroll container's and NOT the child column's. The town's banner
## uses the PWA's full-bleed trick (`width:100vw; margin-left:calc(50% - 50vw)`), so a drag
## that starts on the banner is still a drag on the PAGE — and so is one in the 8px gutter
## beside the content. Measured on the port's web build: with the child column's rect a
## banner drag did not scroll (0px) while a drag on a tile did, which reads to the player as
## "scrolling works in some places and not others".
## Only a FINGER coasts, and on a device with a touchscreen the finger arrives as BOTH a touch
## and an EMULATED mouse event (`input_devices/pointing/emulate_mouse_from_touch`). Deciding by
## "which event type delivered the release" would therefore read a phone's flick as a mouse and
## kill it exactly where Jan plays. So the gesture remembers how it STARTED, and a press that
## arrives while a gesture is already running does not take it over — that is what keeps the
## pair (touch + its emulated mouse press) one gesture instead of two.
func _begin(position: Vector2, pointer: int, from_touch: bool) -> void:
	if _pointer != INACTIVE:
		# A gesture is already running. A finger's press may UPGRADE the gesture an emulated
		# mouse press opened first (a phone can deliver the two in either order); anything else
		# is the second half of the same press and must not take the gesture over.
		if from_touch and not _from_touch:
			_pointer = pointer
			_from_touch = true
			_accum = 0.0
			_last_ms = _now_ms()
		return
	if not _scroll.get_global_rect().has_point(position):
		_pointer = INACTIVE
		return
	# A new gesture takes over from a coast in progress: tapping a moving page stops it, the
	# same way it does in a browser.
	_stop_fling()
	_pointer = pointer
	_from_touch = from_touch
	_start = position
	_accum = 0.0
	_past_deadzone = false
	_vel = 0.0
	_last_ms = _now_ms()


## The finger left the page. Whether the page coasts from here depends on how the gesture began
## (`_from_touch`), never on which event happened to deliver the release.
func _end(now_ms: int) -> void:
	# A finger that rested before letting go did not flick — a release arriving long after the
	# last motion is a drag that ended. Without this the page jumps away from a finger that was
	# simply held still and then lifted, which is the one way a flick reads as broken.
	var still := now_ms - _last_ms
	var v := _vel
	var dragged := _past_deadzone
	var finger := _from_touch
	_pointer = INACTIVE
	_from_touch = false
	_accum = 0.0
	_past_deadzone = false
	_vel = 0.0
	if finger and dragged and still <= flick_hold_ms:
		_vel = v
		_start_fling()


## Dragging UP (a negative `dy`) moves the content up, i.e. scrolls DOWN: the value is
## decreased by the drag, which is the direction a phone uses.
##
## `now_ms` is the event's own time stamp; it is what makes the flick's velocity a velocity
## rather than "how far the finger went".
func _move(dy: float, now_ms: int = -1) -> void:
	# Defensive: a motion with no drag behind it (a stray `_move` from a caller, or a drag
	# whose `_begin` landed outside the page) must not move anything.
	if _pointer == INACTIVE:
		return
	if now_ms >= 0:
		# Sampled per event, so the velocity at the release is the finger's LAST movement and
		# not an average over a drag that ended in a pause.
		var dt := float(now_ms - _last_ms) / 1000.0
		if dt > 0.0:
			var inst := -dy / dt
			# A tiny weight: one jittery event must not decide the flick, but a real flick
			# (many fast events in a row) lands on the finger's own speed.
			_vel = lerpf(_vel, inst, 0.5)
		_last_ms = now_ms
	if not _past_deadzone:
		# The deadzone is absorbed, not jumped over: 160px of finger must mean 152px of page,
		# never a lurch of the full 8px the instant the finger crosses it.
		_accum += dy
		if absf(_accum) < deadzone:
			return
		var excess := _accum - deadzone * signf(_accum)
		_past_deadzone = true
		_accum = 0.0
		_cancel_press()
		if excess != 0.0:
			_scroll.get_v_scroll_bar().value -= excess
		return
	_scroll.get_v_scroll_bar().value -= dy


## Drop the press of whatever button the finger went down on, so a DRAG does not fire the
## tile it started on.
##
## Measured (`tools/probe_cancel.gd`, against a real Button in the real pipeline): a synthetic
## RELEASE ALONE IS NOT ENOUGH — `BaseButton` emits `pressed` on release whenever
## `pressing_inside` is still true, whatever the release's position, so all three of "did it
## fire" stayed wrong. Two events are needed, in this order:
##
##   1. a motion to a point no control occupies, which is what clears `pressing_inside`
##      (the same path a real finger takes when it slides off a button), then
##   2. a release, so the press does not stay open forever.
##
## Only a finger that actually DRAGGED loses its press: a tap never crosses the deadzone.
## The page keeps scrolling — this node's own `_pointer` is deliberately left alone.
func _cancel_press() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	if vp == null:
		return
	var away := Vector2(-1000.0, -1000.0)
	_synthetic = true
	if _pointer >= 0:
		var move := InputEventScreenDrag.new()
		move.index = _pointer
		move.position = away
		move.relative = Vector2.ZERO
		vp.push_input(move)
		var touch := InputEventScreenTouch.new()
		touch.index = _pointer
		touch.pressed = false
		touch.position = away
		vp.push_input(touch)
	else:
		var motion := InputEventMouseMotion.new()
		motion.position = away
		motion.global_position = away
		motion.relative = Vector2.ZERO
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		vp.push_input(motion)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = false
		click.position = away
		click.global_position = away
		vp.push_input(click)
	_synthetic = false
