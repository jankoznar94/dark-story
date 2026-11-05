extends Control
class_name SlashFx
## One drawn BLADE SWEEP: a crescent that crosses the reach plus a cut mark where it lands.
##
## Why it exists: the arena's only attack animation used to be the hero's body lifting 14 px,
## which on a 390 px phone is a twitch you have to be told about. Jan: "animace seknutí musí
## být větší, výraznější, ať má hráč pocit, že se skutečně něco děje." A moving FIGURE cannot
## carry that at this size; a bright shape crossing the space between the two fighters can.
##
## It is PRESENTATION ONLY. The rules' clock is untouched: `age` is advanced by the arena from
## the wall clock, and nothing here reads or writes a rule.
##
## Two things are drawn:
##   * the crescent — a thick band between `INNER_R` and `OUTER_R` of the distance, swept in
##     from one side of the aim to the other, so the eye follows the blade;
##   * the cut mark — a tapered bar across the TARGET, appearing as the sweep completes. It is
##     what says "the blow landed HERE" after the crescent has gone.
##
## Deliberately flat: hard-edged polygons, no glow, no particles — Jan's astigmatism brief is
## large, calm, desaturated shapes, and a soft glowing arc is the opposite of that.

## How long one sweep lasts, in seconds. Long enough to be followed by the eye at 60 fps
## (18 frames), shorter than the fastest weapon's swing interval so two blows never overlap
## into one bright smear.
const DURATION := 0.30
## The blade reaches the far end of the cut at this fraction of the animation; the rest is the
## crescent fading off the target.
const SWEEP_T := 0.55
## The crescent starts fading at this fraction.
const FADE_FROM := 0.45
## The band's radial extent, as a fraction of the distance from `from` to `to`. Picked by
## rendering three shapes over a real arena frame and looking at them: a band hugging the hero
## floated beside him with nothing holding it, a band reaching from the attacker to the target
## covered a third of the screen and read as fog, and this one — a crescent crossing the gap —
## is the one that reads as a blade sweeping INTO the monster.
const INNER_R := 0.34
const OUTER_R := 0.62
## The cut mark's length as a fraction of the distance, and its half-thickness in px.
const CUT_LEN := 0.80
const CUT_HALF_W := 10.0

var age := -1.0
var from := Vector2.ZERO
var to := Vector2.ZERO
var tint := Color("#fff2d2")
var duration := DURATION
## How wide a wedge the sweep covers, in degrees.
var arc_deg := 74.0
## Overall opacity, 0..1. The hero's strike is drawn at full strength; the enemy's is dialled
## BACK, because it fires on every monster swing and a full-strength red fan over the arena
## every two seconds is noise rather than an event.
var strength := 1.0
## The band's radial extent as a fraction of the distance. Kept per-instance: the hero swings a
## short axe and the trail has to sit at HIS arm's length, not at the duel distance, or it
## floats in the middle of the screen with nothing holding it.
var inner_r := INNER_R
var outer_r := OUTER_R
## The cut mark is skipped for a sweep that is not a strike against a body (nothing uses this
## today; kept so a future "ground slash" does not have to fork the script).
var cut := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Start a sweep at `p_from`, landing on `p_to`.
func fire(p_from: Vector2, p_to: Vector2, p_tint: Color, p_duration: float = DURATION) -> void:
	from = p_from
	to = p_to
	tint = p_tint
	duration = p_duration
	age = 0.0
	visible = true
	queue_redraw()


## Advance the animation. `wall_delta` — never `delta`: a hit-stop scales `delta`, and a
## 0.3 s sweep stretched by a 0.05 time scale would hang on screen for six seconds.
func advance(wall_delta: float) -> void:
	if age < 0.0:
		return
	age += wall_delta
	if age >= duration:
		age = -1.0
		visible = false
	queue_redraw()


func active() -> bool:
	return age >= 0.0


func _draw() -> void:
	if age < 0.0:
		return
	var span := to - from
	var radius := span.length()
	if radius < 1.0:
		return
	var dir := span.angle()
	var p := clampf(age / duration, 0.0, 1.0)

	# The swept extent, eased OUT so the blade crosses fast and the crescent hangs for a beat.
	var sweep := clampf(p / SWEEP_T, 0.0, 1.0)
	var swept := 1.0 - pow(1.0 - sweep, 3.0)
	var half := deg_to_rad(arc_deg) * 0.5
	var a0 := dir - half
	var a1 := dir - half + 2.0 * half * swept

	var alpha := 1.0
	if p > FADE_FROM:
		alpha = 1.0 - (p - FADE_FROM) / (1.0 - FADE_FROM)
	alpha = clampf(alpha, 0.0, 1.0) * strength

	_draw_crescent(a0, a1, radius, alpha)
	# The bright leading edge: this is the BLADE. One hard line reads as a weapon where a
	# band alone reads as a light.
	var outer := radius * outer_r
	var inner := radius * inner_r
	var edge_a := from + Vector2(cos(a1), sin(a1)) * inner
	var edge_b := from + Vector2(cos(a1), sin(a1)) * outer
	draw_line(edge_a, edge_b, Color(tint.r, tint.g, tint.b, alpha), 4.0, true)
	# The path the blade has already cut, at mid radius: a hard 2 px line along the swept
	# extent. This is what turns the band from a haze into a trajectory.
	var mid_r := (inner + outer) * 0.5
	var path := PackedVector2Array()
	var seg := 24
	for i in seg + 1:
		var t := lerpf(a0, a1, float(i) / float(seg))
		path.append(from + Vector2(cos(t), sin(t)) * mid_r)
	draw_polyline(path, Color(1, 1, 1, alpha * 0.9), 2.0, true)
	# A hard rim along the OUTER edge, right through the arc: at 390 px the band alone reads as
	# a pale wash over a busy backdrop, and it is this edge that makes it a blade.
	var rim := PackedVector2Array()
	for i in seg + 1:
		var t := lerpf(a0, a1, float(i) / float(seg))
		rim.append(from + Vector2(cos(t), sin(t)) * outer)
	draw_polyline(rim, Color(tint.r, tint.g, tint.b, alpha * 0.95), 3.0, true)
	if cut and p > SWEEP_T * 0.7:
		_draw_cut(dir, radius, alpha)


## The band, as a fan of convex quads (a ring sector is concave, and a single polygon
## triangulates badly on the Compatibility renderer). The radial thickness TAPERS to nothing
## at both ends of the sweep: a uniform band reads as a wedge of light, a tapered one reads as
## the path of a blade.
func _draw_crescent(a0: float, a1: float, radius: float, alpha: float) -> void:
	var steps := 24
	var outer := radius * outer_r
	var inner := radius * inner_r
	for i in steps:
		var u0 := float(i) / float(steps)
		var u1 := float(i + 1) / float(steps)
		var t0 := a0 + (a1 - a0) * u0
		var t1 := a0 + (a1 - a0) * u1
		# Brightest at the LEADING edge, dying toward the tail: the eye finds the blade's
		# position from the gradient, and the tail is what it leaves behind.
		var a := alpha * (0.34 + 0.62 * u0)
		var in0 := outer - (outer - inner) * _taper(u0)
		var in1 := outer - (outer - inner) * _taper(u1)
		var quad := PackedVector2Array([
			from + Vector2(cos(t0), sin(t0)) * outer,
			from + Vector2(cos(t1), sin(t1)) * outer,
			from + Vector2(cos(t1), sin(t1)) * in1,
			from + Vector2(cos(t0), sin(t0)) * in0,
		])
		draw_colored_polygon(quad, Color(tint.r, tint.g, tint.b, a))


## 0 at the ends of the sweep, 1 in the middle — the blade is thick where it is moving and
## comes to a point where the cut starts and ends.
static func _taper(u: float) -> float:
	return 0.06 + 0.94 * pow(sin(PI * clampf(u, 0.0, 1.0)), 0.55)


## A tapered bar across the target, perpendicular to the swing. Two triangles that meet in the
## middle: it reads as a cut rather than as a second bar of the HP ring.
func _draw_cut(dir: float, radius: float, alpha: float) -> void:
	var tangent := Vector2(cos(dir + PI * 0.5), sin(dir + PI * 0.5))
	var mid := to
	var half_len := radius * CUT_LEN
	var grow := clampf((age / duration - SWEEP_T * 0.7) / 0.25, 0.0, 1.0)
	var length := half_len * (0.55 + 0.45 * grow)
	var head := mid + tangent * (length * 0.5)
	var tail := mid - tangent * (length * 0.5)
	var side := Vector2(cos(dir), sin(dir)) * CUT_HALF_W
	var col := Color(tint.r, tint.g, tint.b, alpha)
	draw_colored_polygon(PackedVector2Array([tail, mid + side, mid - side]), col)
	draw_colored_polygon(PackedVector2Array([head, mid - side, mid + side]), col)
	# A white core on the cut so it reads over the portrait's own colours.
	draw_line(tail, head, Color(1, 1, 1, alpha), 4.0, true)
