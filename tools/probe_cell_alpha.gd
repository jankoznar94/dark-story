extends SceneTree
## probe_cell_alpha.gd — the decisive measurement for the bag/chest cell.
##
## The PWA's empty cell renders as rgb(43,43,43): `background:#aaa` + `opacity:0.25` over
## `.inv-grid-wrap { background:#000 }`. A plain ColorRect in Godot at modulate.a = 0.25
## renders 42, i.e. the ordinary over-blend — but the port's real bag cells measure
## rgb(59,59,59) and the real item_cell Button measured 56 in an earlier probe. So the
## discrepancy is in the BUTTON+STYLEBOX path, not in the arithmetic, and it has to be
## measured on the real cell rather than reasoned about.
##
## Samples the CENTRE of each cell (no corner anti-aliasing, no icon child) and sweep the
## alpha, so the constant the port ships is the one that reads as the PWA's pixel.
##
##   godot4 --path . --rendering-driver opengl3 --script res://tools/probe_cell_alpha.gd

const UIKit := preload("res://scripts/ui/ui_kit.gd")

## The two alphas the port actually uses today, plus a sweep around them.
const CASES := [
	["current empty  0.25", 0.25, false],
	["current dimmed 0.35", 0.35, true],
	["sweep 0.22", 0.22, false],
	["sweep 0.20", 0.20, false],
	["sweep 0.16", 0.16, false],
	["sweep 0.14", 0.14, false],
	["sweep 0.12", 0.12, false],
	["opaque      1.00", 1.00, false],
]

var _frames := 0
var _printed := false


func _initialize() -> void:
	root.size = Vector2i(390, 844)
	var plate := ColorRect.new()
	plate.color = Color("000000")
	plate.size = Vector2(390, 844)
	root.add_child(plate)
	for i in CASES.size():
		var cell: Button = UIKit.item_cell({}, 60.0)
		cell.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		cell.custom_minimum_size = Vector2(60, 60)
		cell.size = Vector2(60, 60)
		# Override the alpha AFTER construction, so the sweep is the only variable.
		cell.modulate = Color(1, 1, 1, CASES[i][1])
		cell.position = Vector2(16 + (i % 4) * 92, 100 + (i / 4) * 92)
		root.add_child(cell)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false
	if _printed:
		return false
	_printed = true
	var img: Image = root.get_texture().get_image()
	print("PWA empty cell renders rgb(43,43,43); PWA dimmed is on filled cells only")
	for i in CASES.size():
		var label: String = str(CASES[i][0])
		var a: float = CASES[i][1]
		var x := int(16 + (i % 4) * 92 + 30)
		var y := int(100 + (i / 4) * 92 + 30)
		var c := img.get_pixel(x, y)
		var v := int(round(c.r * 255.0))
		print("  %-20s a=%.2f  centre rgb(%d,%d,%d)   naive #aaa*a = %d" % [
			label, a, v, int(round(c.g * 255.0)), int(round(c.b * 255.0)),
			int(round(170.0 * a))])
	print("CELL_ALPHA_DONE=true")
	quit()
	return false
