extends RefCounted
## The 2D inventory icon of an item, drawn from the SAME `shape` key that builds
## the 3D model on the ground (scripts/item_model.gd) - one label, two renderers,
## so the picture in the bag cannot drift from the object the player picked up.
##
## Drawn with plain CanvasItem primitives rather than a texture: no atlas to keep
## in sync, no per-item import step, and it costs nothing on a phone. Everything
## is a flat fill plus one darker edge - no glow, no gradient (art rules).

## Palette, matched to item_model.gd so a steel blade is the same steel in both.
const STEEL := Color(0.56, 0.58, 0.62)
const STEEL_DARK := Color(0.34, 0.35, 0.38)
const WOOD := Color(0.34, 0.25, 0.17)
const LEATHER := Color(0.38, 0.27, 0.18)
const GOLD := Color(0.66, 0.54, 0.26)
const CLOTH := Color(0.40, 0.36, 0.32)
const GEM := Color(0.55, 0.26, 0.30)


## Draw `shape` filling `r`. The drawing is normalised: everything is expressed as
## a fraction of `r`, so one function serves a 24 px cell and a 200 px tooltip.
static func draw(canvas: CanvasItem, shape: String, r: Rect2, tint: Color = Color(1, 1, 1)) -> void:
	var s := minf(r.size.x, r.size.y)
	var c := r.position + r.size * 0.5
	match shape:
		"sword", "dagger":
			var L: float = 0.86 if shape == "sword" else 0.6
			_blade(canvas, c, s * L, s * 0.16, tint)
		"axe":
			_haft(canvas, c, s * 0.84, tint)
			_poly(canvas, _scale_pts(PackedVector2Array([
				Vector2(0.0, -0.30), Vector2(0.30, -0.40), Vector2(0.30, -0.14),
				Vector2(0.02, -0.20)]), c, s), _c(STEEL, tint))
			_poly(canvas, _scale_pts(PackedVector2Array([
				Vector2(0.0, -0.30), Vector2(0.30, -0.40), Vector2(0.30, -0.14),
				Vector2(0.02, -0.20)]), c, s), _c(STEEL_DARK, tint), false)
		"mace":
			_haft(canvas, c, s * 0.74, tint)
			canvas.draw_circle(c + Vector2(0, -s * 0.30), s * 0.19, _c(STEEL, tint))
			for a in [0.0, 90.0, 180.0, 270.0]:
				var d := Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a))) * s * 0.19
				canvas.draw_circle(c + Vector2(0, -s * 0.30) + d, s * 0.045, _c(STEEL_DARK, tint))
		"hammer":
			_haft(canvas, c, s * 0.74, tint)
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.24, -s * 0.42), Vector2(s * 0.42, s * 0.20)),
				_c(STEEL, tint))
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.26, -s * 0.42), Vector2(s * 0.06, s * 0.20)),
				_c(GOLD, tint))
		"polearm":
			_haft(canvas, c, s * 0.94, tint)
			_poly(canvas, _scale_pts(PackedVector2Array([
				Vector2(0.0, -0.44), Vector2(0.11, -0.28), Vector2(0.0, -0.10),
				Vector2(-0.11, -0.28)]), c, s), _c(STEEL, tint))
		"shield":
			_poly(canvas, _scale_pts(PackedVector2Array([
				Vector2(-0.32, -0.36), Vector2(0.32, -0.36),
				Vector2(0.32, 0.16), Vector2(0.0, 0.42),
				Vector2(-0.32, 0.16)]), c, s), _c(WOOD, tint))
			canvas.draw_circle(c, s * 0.12, _c(STEEL, tint))
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.32, -s * 0.32), Vector2(s * 0.64, s * 0.07)),
				_c(STEEL, tint))
		"armor":
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.26, -s * 0.34), Vector2(s * 0.52, s * 0.62)),
				_c(LEATHER, tint))
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.34, -s * 0.42), Vector2(s * 0.68, s * 0.16)),
				_c(CLOTH, tint))
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.08, -s * 0.34), Vector2(s * 0.16, s * 0.62)),
				_c(STEEL, tint))
		"helm":
			canvas.draw_circle(c + Vector2(0, -s * 0.02), s * 0.30, _c(STEEL, tint))
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.32, s * 0.14), Vector2(s * 0.64, s * 0.12)),
				_c(STEEL_DARK, tint))
		"gloves":
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.20, -s * 0.02), Vector2(s * 0.34, s * 0.34)),
				_c(LEATHER, tint))
			for i in 3:
				canvas.draw_rect(Rect2(c + Vector2(-s * 0.20 + s * 0.12 * i, -s * 0.32),
					Vector2(s * 0.09, s * 0.30)), _c(LEATHER, tint))
		"boots":
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.30, s * 0.02), Vector2(s * 0.52, s * 0.26)),
				_c(LEATHER, tint))
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.30, -s * 0.36), Vector2(s * 0.24, s * 0.40)),
				_c(LEATHER, tint))
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.32, s * 0.26), Vector2(s * 0.56, s * 0.09)),
				_c(WOOD, tint))
		"belt":
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.40, -s * 0.09), Vector2(s * 0.80, s * 0.18)),
				_c(LEATHER, tint))
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.08, -s * 0.16), Vector2(s * 0.18, s * 0.32)),
				_c(GOLD, tint))
		"ring":
			canvas.draw_arc(c, s * 0.28, 0.0, TAU, 16, _c(GOLD, tint), maxf(1.0, s * 0.09))
			canvas.draw_circle(c + Vector2(0, -s * 0.28), s * 0.09, _c(GEM, tint))
		"amulet":
			canvas.draw_arc(c + Vector2(0, s * 0.04), s * 0.30, PI * 1.15, PI * 1.85, 12,
				_c(GOLD, tint), maxf(1.0, s * 0.07))
			canvas.draw_circle(c + Vector2(0, s * 0.16), s * 0.14, _c(GEM, tint))
		_:
			canvas.draw_rect(Rect2(c, Vector2(s * 0.3, s * 0.3)), _c(CLOTH, tint))


static func _c(col: Color, tint: Color) -> Color:
	return Color(col.r * tint.r, col.g * tint.g, col.b * tint.b, col.a)


static func _scale_pts(pts: PackedVector2Array, c: Vector2, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + p * s)
	return out


static func _poly(canvas: CanvasItem, pts: PackedVector2Array, col: Color, fill: bool = true) -> void:
	if fill:
		canvas.draw_colored_polygon(pts, col)
	else:
		var closed := pts.duplicate()
		closed.append(pts[0])
		canvas.draw_polyline(closed, col, 2.0)


## A vertical blade with a guard and a grip, centred on `c`.
static func _blade(canvas: CanvasItem, c: Vector2, length: float, width: float, tint: Color) -> void:
	var top := c.y - length * 0.5
	var guard := c.y + length * 0.22
	canvas.draw_colored_polygon(_scale_pts(PackedVector2Array([
		Vector2(-width * 0.5, -length * 0.5), Vector2(width * 0.5, -length * 0.5),
		Vector2(width * 0.5, length * 0.22 - (c.y - c.y)),
		Vector2(0.0, length * 0.34), Vector2(-width * 0.5, length * 0.22)]),
		c, 1.0), _c(STEEL, tint))
	canvas.draw_rect(Rect2(Vector2(c.x - width * 1.5, guard - 2.0), Vector2(width * 3.0, 4.0)),
		_c(STEEL_DARK, tint))
	canvas.draw_rect(Rect2(Vector2(c.x - width * 0.4, guard + 2.0),
		Vector2(width * 0.8, length * 0.20)), _c(LEATHER, tint))
	canvas.draw_circle(Vector2(c.x, guard + length * 0.22 + 4.0), width * 0.55, _c(GOLD, tint))


## A wooden shaft for axe / mace / hammer / polearm.
static func _haft(canvas: CanvasItem, c: Vector2, length: float, tint: Color) -> void:
	canvas.draw_rect(Rect2(Vector2(c.x - 0.045 * length, c.y - length * 0.3),
		Vector2(0.09 * length, length * 0.78)), _c(WOOD, tint))
