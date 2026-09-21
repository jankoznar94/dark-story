extends RefCounted
## ONE FINGER TAP, ONE ACTION.
##
## Godot delivers a real touch to `Control::_gui_input` TWICE. `Input` synthesises
## an InputEventMouseButton from every InputEventScreenTouch
## (`input_devices/pointing/emulate_mouse_from_touch`, ON by default - and a browser
## reports a finger as a touch, so this is the normal path on a phone), and BOTH
## events are routed to the GUI. Measured on a windowed run with real injected
## events, one tap on a bag item delivered:
##     MouseButton(pressed, device=-1)   <- synthesised
##     ScreenTouch(pressed, device=0)    <- the finger
## and on release the same pair again.
##
## Every handler shaped `if pressed: act` therefore acts TWICE, and the second act
## UNDOES the first. That is Jan's report: *"the items still cannot be equipped from
## the inventory into the equip slots. Either it says the item does not belong
## there, or it just returns to the inventory without a message."* Traced, both
## halves of that sentence are the same defect:
##   * tap the bag item  -> picked up, then the duplicate release reads as "tapping
##     the carried item again" and drops it, so the next tap on the box does nothing;
##   * drag onto a box   -> equipped, then the duplicate release lands on a slot that
##     is now occupied and UNEQUIPS it, with no message.
##
## WHY NO EARLIER MEASUREMENT SAW IT: every existing instrument injects input with
## `Control._tap()`, `_on_press/_on_release` (the headless gate) or
## `Viewport.push_input()` (probe_equip_drag.gd). All three skip `Input` and with it
## the emulation, so they deliver each tap exactly once. Only a real finger - or
## `Input.parse_input_event()` - doubles it.
##
## THE GUARD IS DELIBERATELY SOURCE-AGNOSTIC AND ORDER-AGNOSTIC. It remembers only
## that a gesture is LIVE, so whichever of the two events arrives first wins and the
## other is dropped. It must NOT lock onto the first event'S SOURCE: the emulated
## mouse is not a full duplicate - a finger DRAG delivers ScreenDrag events and no
## MouseMotion at all (measured), so a mouse-locked guard would kill dragging on a
## phone. Drops are also not assumed: on a desktop browser and a touchscreen laptop
## either event may arrive alone, and a lone event runs the gesture normally.
##
## Usage - press begins, release ends, and ONLY the event that opens or closes the
## gesture is allowed to act:
##     if touch.pressed:
##         if _tap_guard.begin():
##             _on_press(...)
##     elif _tap_guard.end():
##         _on_release(...)
## Drag/move events are NOT gated: they carry no action of their own.

## True while a gesture is in progress.
var _live: bool = false
## Frames since the gesture began, so a LOST release cannot wedge the panel. A
## finger that leaves the window, a browser that drops the release, or a panel that
## closes mid-press would otherwise leave `_live` set and the panel would ignore
## every later tap - a worse bug than the one this fixes.
var _frames: int = 0

## How long a gesture may stay live without a release before the guard gives up on
## it. ~2.5 s at 60 fps: longer than any tap or drag, short enough that a wedged
## guard heals while the player is still watching the screen.
const MAX_LIVE_FRAMES := 150


## True when this event STARTS the gesture; false for the duplicate.
func begin() -> bool:
	if _live:
		return false
	_live = true
	_frames = 0
	return true


## True when this event ENDS the gesture; false for the duplicate. A release with no
## live gesture (the synthesised second one, or a stray event) returns false, which
## is what stops the tap being performed twice.
func end() -> bool:
	if not _live:
		return false
	_live = false
	_frames = 0
	return true


func live() -> bool:
	return _live


## Called once per frame by the owner. Expires a gesture whose release never came.
func tick() -> void:
	if not _live:
		return
	_frames += 1
	if _frames > MAX_LIVE_FRAMES:
		reset()


func reset() -> void:
	_live = false
	_frames = 0
