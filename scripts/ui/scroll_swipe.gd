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

## Movement before the drag is allowed to move the page, matching the ScrollContainer's own
## `scroll_deadzone`. Without it every tap would nudge the page.
var deadzone := 8.0

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


func setup(scroll: ScrollContainer) -> void:
	_scroll = scroll
	# Make Godot's OWN finger drag inert so this node is the single scroll path on every
	# platform (see the header). `ScrollContainer` flips `beyond_deadzone` only once
	# `abs(drag_accum) > scroll_deadzone`, so a deadzone larger than the canvas can never be
	# crossed by a finger and its drag stays off — while the WHEEL branch runs earlier and
	# still works for a desktop mouse.
	if scroll != null:
		scroll.scroll_deadzone = 1_000_000


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
			_begin(touch.position, touch.index)
		elif _pointer == touch.index:
			_end()
		return

	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _pointer == drag.index:
			_move(drag.relative.y)
		return

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_begin(button.position, -1)
		elif _pointer == -1:
			_end()
		return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _pointer != -1:
			return
		if not (motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
			return
		_move(motion.relative.y)


## A drag only starts inside the page. A swipe anywhere else in the window is somebody
## else's event — the arena has its own input and must not scroll a hidden town page.
##
## ⚠️ The rect MUST be the scroll container's and NOT the child column's. The town's banner
## uses the PWA's full-bleed trick (`width:100vw; margin-left:calc(50% - 50vw)`), so a drag
## that starts on the banner is still a drag on the PAGE — and so is one in the 8px gutter
## beside the content. Measured on the port's web build: with the child column's rect a
## banner drag did not scroll (0px) while a drag on a tile did, which reads to the player as
## "scrolling works in some places and not others".
func _begin(position: Vector2, pointer: int) -> void:
	if not _scroll.get_global_rect().has_point(position):
		_pointer = INACTIVE
		return
	_pointer = pointer
	_start = position
	_accum = 0.0
	_past_deadzone = false


func _end() -> void:
	_pointer = INACTIVE
	_accum = 0.0
	_past_deadzone = false


## Dragging UP (a negative `dy`) moves the content up, i.e. scrolls DOWN: the value is
## decreased by the drag, which is the direction a phone uses.
func _move(dy: float) -> void:
	# Defensive: a motion with no drag behind it (a stray `_move` from a caller, or a drag
	# whose `_begin` landed outside the page) must not move anything.
	if _pointer == INACTIVE:
		return
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
