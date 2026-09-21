extends Control
class_name GaugeArc
## GaugeArc — one arc of the arena's ring stack, drawn from code.
##
## The PWA built these as SVG `<circle>` elements with `stroke-dasharray` and animated
## `stroke-dashoffset`. Godot has no stroke-dasharray, but `draw_arc` is the same idea:
## draw a segment from a start angle to an end angle and the un-drawn part IS the gap.
##
## They are Controls rather than a CanvasItem in a .tscn because every one of them is
## driven by a live number off `battle.gd` (the enemy's HP, the swing timers), and a
## scene file would be a second place for that wiring to live.
##
## All five rings sit in the SAME coordinate space — one instance per ring, each with its
## own radius — so they stay concentric without any of them owning the layout.

enum Direction {
	CLOCKWISE,        ## from 12 o'clock clockwise
	COUNTER_CLOCKWISE ## from 12 o'clock counter-clockwise
}

@export var radius := 100.0
@export var thickness := 9.0
@export var colour := Color("#e74c3c")
## 0..1 of a full turn. Set to 0 to hide the arc without hiding the node.
@export var value := 1.0
@export var direction := Direction.CLOCKWISE
## Leaves a gap at the top so a ring that is not part of a pair still reads as a gauge.
@export var gap_degrees := 0.0
## Dashes, in degrees: on/off. `stroke-dasharray: 4 5` in the PWA's `.zone-divider` is
## roughly this at its radius, and the dashes are the only thing that tells the divider
## apart from a gauge ring.
@export var dash_on_degrees := 0.0
@export var dash_off_degrees := 0.0
@export var antialiased := true


func set_value_ratio(ratio: float) -> void:
	var next := clampf(ratio, 0.0, 1.0)
	if is_equal_approx(next, value):
		return
	value = next
	queue_redraw()


func _draw() -> void:
	if value <= 0.0 or radius <= 0.0:
		return
	var centre := size * 0.5
	var sweep := TAU * value
	if gap_degrees > 0.0:
		sweep = minf(sweep, TAU - deg_to_rad(gap_degrees))
	# 12 o'clock is -PI/2 in Godot's angle space, which is what the PWA's
	# `transform:rotate(-90deg)` achieved on its SVGs.
	var start := -PI * 0.5
	if dash_on_degrees > 0.0 and dash_off_degrees > 0.0:
		_draw_dashed(centre, start, sweep)
		return
	var end := start + sweep if direction == Direction.CLOCKWISE else start - sweep
	# Points scale with the sweep: a 3-point arc is a triangle, and a full ring drawn
	# with too few segments shows visible corners at 200px.
	var points := maxi(8, int(absf(sweep) / TAU * 64.0) + 2)
	draw_arc(centre, radius, start, end, points, colour, thickness, antialiased)


func _draw_dashed(centre: Vector2, start: float, sweep: float) -> void:
	var on := deg_to_rad(dash_on_degrees)
	var off := deg_to_rad(dash_off_degrees)
	var step := on + off
	var travelled := 0.0
	var sign_sweep := 1.0 if sweep >= 0.0 else -1.0
	while travelled < absf(sweep):
		var a0 := start + travelled * sign_sweep
		var a1 := start + minf(travelled + on, absf(sweep)) * sign_sweep
		draw_arc(centre, radius, a0, a1, 4, colour, thickness, antialiased)
		travelled += step


## A transparent full-circle track behind the arc, the way the PWA's `.enemy-timer-bg`
## sits under the enemy timer.
static func track(radius_px: float, thickness_px: float, colour_hex: String) -> Control:
	var arc := new_arc()
	arc.radius = radius_px
	arc.thickness = thickness_px
	arc.colour = Color(colour_hex)
	arc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return arc


## `GaugeArc.new()` inside the class' own static functions does not resolve — the global
## class name is not registered yet while the script is still loading. Loading the script
## and instantiating from it works in every context, including this one.
static func new_arc() -> Control:
	return load("res://scripts/ui/ui_gauge.gd").new()
