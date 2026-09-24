extends SceneTree
## probe_alpha_blend.gd — what does Godot ACTUALLY paint for a #aaa box at a given
## modulate alpha?
##
## The CSS says `background:#aaa` + `opacity:0.25`, which on paper is `170 * 0.25 = 43`
## over black. The port measures 59 for the same pair, so either Godot's blend is not
## the sRGB multiply the CSS implies, or something else is in the stack. This probe
## paints the real thing (a Button with the real `item_cell` stylebox) at several alphas
## and reads the pixel back, so the alpha we ship is the one that MEASURES as the PWA's.
##
##   godot4 --path . --rendering-driver opengl3 --script res://tools/probe_alpha_blend.gd

const UIKit := preload("res://scripts/ui/ui_kit.gd")

var _frames := 0
var _printed := false
var _boxes: Array[Button] = []
const ALPHAS := [1.0, 0.25, 0.2, 0.18, 0.15, 0.12]


func _initialize() -> void:
	root.size = Vector2i(390, 844)
	for i in ALPHAS.size():
		var cell := UIKit.item_cell({}, 62.8)
		cell.position = Vector2(10 + i * 64, 100)
		cell.modulate = Color(1, 1, 1, ALPHAS[i])
		root.add_child(cell)
		_boxes.append(cell)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 4:
		return false
	if _printed:
		return false
	_printed = true
	var img := root.get_texture().get_image()
	# the cell's own fill, sampled in a corner far from any child
	for i in _boxes.size():
		var r := _boxes[i].get_global_rect()
		var x := int(r.position.x + 3)
		var y := int(r.position.y + 3)
		var c := img.get_pixel(x, y)
		print("alpha %.2f  drawn fill = (%d,%d,%d)   css expects 170*%.2f = %d" % [
			ALPHAS[i], int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0),
			ALPHAS[i], int(round(170.0 * ALPHAS[i]))])
	# and the same box at alpha 1.0, for the reference value
	var full := _boxes[0].get_global_rect()
	var f := img.get_pixel(int(full.position.x + 3), int(full.position.y + 3))
	print("alpha 1.00  drawn fill = (%d,%d,%d) — the raw constant" % [
		int(f.r * 255.0), int(f.g * 255.0), int(f.b * 255.0)])
	print("ALPHA_PROBE_DONE=true")
	quit()
	return false
