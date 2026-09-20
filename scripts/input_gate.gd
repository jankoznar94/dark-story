extends RefCounted
## The ONE place that says whether gameplay INPUT is live.
##
## WHY A SHARED GATE AND NOT A FLAG PER SCRIPT: Jan's report was "the game should
## pause when the inventory opens, it does not - the enemies keep attacking and
## moving", and the first design (a flag inside `player.gd`) could never have
## fixed that: setting state on ONE script only silences that script, while every
## other reader of Godot's `Input` singleton - the HUD's own buttons, the enemy
## AI, the hero wrapper - keeps seeing the key or the virtual button that is still
## physically down. The player then walked and swung his sword with the bag open.
##
## So gameplay scripts no longer call `Input.get_vector` / `Input.is_action_*`
## for READS; they ask this gate, and every read is false while a panel is up.
## Nothing has to be restored on resume: the physical key and the virtual button
## stay down, and the next frame simply reads the real input again.
##
## `tools/test_panels.gd` asserts that the gameplay scripts make no direct Input
## read at all, because "one script missed the gate" is the failure mode this
## class exists to prevent, and it looks exactly like a working pause.

static var _blocked: bool = false


## Called once per physics frame by main.gd, BEFORE anything reads it.
static func set_blocked(on: bool) -> void:
	_blocked = on


static func blocked() -> bool:
	return _blocked


## True only while gameplay input is live. Movement, attack, run and the panel
## hotkey all read through here.
static func held(action: String) -> bool:
	return false if _blocked else Input.is_action_pressed(action)


static func just(action: String) -> bool:
	return false if _blocked else Input.is_action_just_pressed(action)


## A movement vector that is exactly zero while blocked. Returning a zero vector
## rather than "no call" is deliberate: the callers all treat zero as "no input",
## so a blocked frame follows the same path as an idle one.
static func vector(neg_x: String, pos_x: String, neg_y: String, pos_y: String) -> Vector2:
	if _blocked:
		return Vector2.ZERO
	return Input.get_vector(neg_x, pos_x, neg_y, pos_y)


## True while a real joypad axis is deflected. Lives here for the same reason as
## the rest: the player must not ask `Input` anything directly.
static func joypad_deflected(deadzone: float) -> bool:
	if _blocked:
		return false
	for d in Input.get_connected_joypads():
		if absf(Input.get_joy_axis(d, JOY_AXIS_LEFT_X)) > deadzone \
				or absf(Input.get_joy_axis(d, JOY_AXIS_LEFT_Y)) > deadzone:
			return true
	return false
