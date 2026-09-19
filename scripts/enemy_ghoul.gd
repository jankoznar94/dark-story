extends "res://scripts/enemy_base.gd"
## Ghoul - the fragile one, and the reason the pack is worth fighting.
##
## Its behaviour is different, not just its numbers. A straight-line chaser turns
## three weak enemies into one enemy with three health bars: they all walk the same
## line, arrive together, and stack. So a ghoul does not charge the player - it
## CIRCLES to a flank first and strikes from the side, which is what makes several
## of them a real fight instead of a queue.
##
## It also works in a pack: `_separation` keeps the bodies apart, and the orbit is
## what makes them fan out around the player instead of lining up.

## Distance at which it leaves the approach line and starts sweeping around.
const ORBIT_ENTER := 3.4
## Distance at which the circling stops turning into "running away".
const ORBIT_KEEP := 1.15
## Seconds spent sweeping to one side before it picks the other; the switch is
## what keeps a lone ghoul from being predictable, and what spreads a pack out.
const ORBIT_SWITCH := 3.2

var _orbit_dir: float = 1.0
var _orbit_t: float = 0.0


func kind_id() -> String:
	return "ghoul"


func _steer(to_target: Vector3, dist: float, delta: float) -> Vector3:
	if not aggro or dist >= INF or to_target.length() < 0.05:
		return Vector3.ZERO

	var to_player := to_target.normalized()
	var side := to_player.cross(Vector3.UP).normalized() * _orbit_dir
	var sep := _separation()

	# --- far out: close the gap, but already angled off the straight line ---
	if dist > ORBIT_ENTER:
		_face(to_player, delta, turn_speed)
		return (to_player + side * 0.45 + sep * 0.8).normalized()

	# --- in the ring: keep the flank, do not stand in front ---
	_orbit_t += delta
	if _orbit_t > ORBIT_SWITCH:
		_orbit_t = 0.0
		_orbit_dir = -_orbit_dir
		side = to_player.cross(Vector3.UP).normalized() * _orbit_dir

	# face the player while moving sideways, so the punch still points at them
	_face(to_player, delta, turn_speed)
	if dist < ORBIT_KEEP:
		# too close: back out along the orbit rather than pushing into the player
		return (side - to_player * 0.5 + sep).normalized()
	# the flanking move itself
	return (side + to_player * 0.25 + sep).normalized()
