extends SceneTree
## Probe: does the layout stay CENTRED when the canvas is not exactly 390 wide?
##
## Jan: "Některé obrazovky mi přijdou lehce uhnuté doleva. Například tlačítka na stránce města
## (zprava je větší mezera od kraje než zleva), nebo třeba transition stránky, kde není obrázek
## na středu ale spíš lehce vlevo."
##
## ⚠️  Every read waits WAIT frames, because `Juice.enter()` leaves a screen at 0.94 scale until
## its 110 ms settle finishes — measuring on the next frame measures the ANIMATION, not the
## layout (that mistake made the world's canvas come back 366.6x793.36, i.e. exactly 0.94).
##
## Run: godot --path . --rendering-driver opengl3 --script res://tools/probe_centering.gd

const Main := preload("res://scripts/main.gd")

const WAIT := 12

var _main: Node = null
var _sizes: Array = [390, 393, 412, 430]
var _index := 0
var _step := 0
var _wait := 0


func _initialize() -> void:
	root.size = Vector2i(390, 844)
	_main = Main.new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _main._nav_bar == null or _main.state == null:
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _index >= _sizes.size():
		quit(0)
		return true

	var w: int = _sizes[_index]
	match _step:
		0:
			root.size = Vector2i(w, 844)
			_wait = WAIT
		1:
			_main.show_screen("town")
			_wait = WAIT
		2:
			_report_town(w)
			_main.show_screen("map")
			_wait = WAIT
		3:
			_report_map(w)
			_main.show_screen("world")
			_wait = WAIT
		4:
			_report_world(w)
			_main._transition.play("", func(): pass)
			_wait = WAIT
		5:
			_report_transition(w)
			_main._transition._active = false
			_main._transition.visible = false
			_index += 1
			_step = 0
			_wait = WAIT
			return false
	_step += 1
	return false


func _head(w: int) -> void:
	print("=== viewport %dx%d (asked %d)" % [root.size.x, root.size.y, w])


func _report_town(w: int) -> void:
	_head(w)
	print("  town rect=%s" % str(_main._screens["town"].get_global_rect()))
	var tiles := _buttons(_main._screens["town"])
	if tiles.size() >= 2:
		var a: Rect2 = tiles[0].get_global_rect()
		var b: Rect2 = tiles[1].get_global_rect()
		print("  tiles: left=%.1f right=%.1f gap=%.1f" % [a.position.x,
			float(root.size.x) - b.end.x, b.position.x - a.end.x])


func _report_map(w: int) -> void:
	var map = _main._screens["map"]
	var acts := _buttons(map._list)
	if acts.size() >= 1:
		var r: Rect2 = acts[0].get_global_rect()
		print("  map act card: left=%.1f right=%.1f" % [r.position.x,
			float(root.size.x) - r.end.x])
	var diff := _buttons(map._difficulty_row)
	if not diff.is_empty():
		var r0: Rect2 = diff[0].get_global_rect()
		var rn: Rect2 = diff[diff.size() - 1].get_global_rect()
		print("  diff row: left=%.1f right=%.1f centre=%.1f (canvas centre %.1f)"
			% [r0.position.x, float(root.size.x) - rn.end.x,
				(r0.position.x + rn.end.x) * 0.5, float(root.size.x) * 0.5])


func _report_world(w: int) -> void:
	var world = _main._screens["world"]
	print("  world canvas=%s" % str(world._canvas.get_global_rect()))
	var p0: Vector2 = world.node_pos(0)
	var pl: Vector2 = world.node_pos(world._total_fights() - 1)
	print("  world nodes: first x=%.1f last x=%.1f" % [p0.x, pl.x])
	var row: Control = world._walk_button.get_parent()
	print("  world actions=%s" % str(row.get_global_rect()))
	var gate := Vector2(world.size.x * 0.5, 100.0)
	print("  world home gate x=%.1f (canvas centre %.1f)" % [gate.x, world.size.x * 0.5])


func _report_transition(w: int) -> void:
	var tr = _main._transition
	var box: Control = tr._image.get_parent()
	var r: Rect2 = box.get_global_rect()
	print("  transition box=%s centre=%.1f (canvas centre %.1f)"
		% [str(r), r.get_center().x, float(root.size.x) * 0.5])


func _buttons(node: Node) -> Array:
	var out: Array = []
	if node is Button:
		out.append(node)
	for child in node.get_children():
		out.append_array(_buttons(child))
	return out
