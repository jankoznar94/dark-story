extends "res://scripts/enemy_base.gd"
## Brute - the heavy. Slowest thing in the arena, biggest body, hardest punch.
##
## Behaviourally distinct by the one thing that matters for a slow enemy: it does
## not stop. The base kind halts at `keep_distance` and throws a punch from there;
## a brute presses INTO the player, which turns its slow approach into pressure and
## makes the player spend the space instead of standing still and trading blows.
##
## It is the only kind that should be fought by moving, so it is also the only one
## with a real recovery (0.42 s) - the window to hit it is after it swings, not
## while it walks.

## It stops only when it is genuinely inside the player's own body radius.
const PRESS_DISTANCE := 0.55


func kind_id() -> String:
	return "brute"


func _steer(to_target: Vector3, dist: float, delta: float) -> Vector3:
	if not aggro or dist >= INF or to_target.length() < 0.05:
		return Vector3.ZERO
	var to_player := to_target.normalized()
	_face(to_player, delta, turn_speed)
	if dist <= PRESS_DISTANCE:
		return Vector3.ZERO
	return (to_player + _separation()).normalized()
