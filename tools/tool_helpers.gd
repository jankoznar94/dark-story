extends RefCounted
class_name ToolHelpers
## Shared helpers for the `--script` tools (probes, captures, tests).
##
## ## Why this exists: `_on_stop_selected` is no longer synchronous
##
## A transition is an 1800 ms overlay, and the PWA runs the move's CALLBACK under the still
## opaque plate — so `_on_stop_selected(act, stop)` no longer enters the arena by the time it
## returns. It starts a transition and the arena is built 1.8 s later, when the overlay's
## `_process` reaches the end of its hold.
##
## Nine tools assumed the old synchronous shape and broke the moment it changed: measured,
## `test_music.gd` died with `Invalid access to property or key 'is_boss' on a base object of
## type 'Nil'` because `_main._screens["arena"].battle` was still null on the next line. Every
## probe in `tools/` that wants an arena has to run the overlay past its hold first — this is
## the one place that knows how.
##
## A tool that needs the arena must therefore either drive the overlay here (`enter_arena`)
## while it is already parked on a frame, or, when it works from `_process`, call
## `enter_arena_now` and let itself be called again on the next frame (see `test_music.gd`).


## Start a fight the way a player does — a tap on a stop — and run the transition's hold out so
## the arena EXISTS when this returns. Returns the arena screen (or null if the move did not
## happen, which is a real failure and the caller should say so).
##
## ⚠️  The overlay is driven with `_process(HOLD_MS)` rather than by waiting for frames. A
## `SceneTree` tool's own frame loop is the test's to control, and blocking it on frames is not
## possible from inside a single call. Running the hold in one step runs the stored callback,
## which is exactly what 1.8 s of frames would do.
static func enter_arena(main, act: int, stop: int):
	main._on_stop_selected(act, stop)
	var tr = main._transition
	if tr != null and tr.is_transitioning():
		# One step past the hold: `_process` calls the callback and starts the fade.
		tr._process(tr.HOLD_MS / 1000.0 + 0.01)
	if not main._screens.has("arena"):
		return null
	return main._screens["arena"]


## The same move for a tool that lives in `_process`: start the fight and report whether the
## arena is ready YET. `false` means "call me again on the next frame" — the overlay is real
## time and the tool must let it elapse.
##
## ⚠️  Driving the overlay's `_process` directly from the tool's own `_process` is fine, but the
## tool must not then also read the arena in the SAME frame: the engine has not laid the screen
## out and the battle exists while the arena is still the previous screen. Wait one frame.
static func enter_arena_now(main, act: int, stop: int) -> bool:
	var arena = main._screens.get("arena")
	if arena != null and arena.battle != null:
		return true
	enter_arena(main, act, stop)
	arena = main._screens.get("arena")
	return arena != null and arena.battle != null
