extends SceneTree
## Throwaway layout probe: boot main.gd, show one screen, dump the control tree with
## each node's size/position, so a layout that renders as an empty box can be read.

var _main: Node = null
var _started := false
var _frames := 0
var _screen := "town"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--screen":
				_screen = args[i + 1]
		i += 2
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_main.show_screen(_screen)
		return false
	_frames += 1
	if _frames < 5:
		return false
	var screen: Control = _main._screens[_screen]
	_dump(screen, 0)
	var bar = _main._nav_bar
	print("nav_bar: visible=%s size=%s pos=%s layer_parent=%s" % [bar.visible, bar.size, bar.position, bar.get_parent().name])
	quit()
	return true


func _dump(node: Node, depth: int) -> void:
	var info := ""
	if node is Control:
		var c: Control = node
		info = " size=%s pos=%s vis=%s" % [c.size, c.position, c.visible]
	print("%s%s (%s)%s" % ["  ".repeat(depth), node.name, node.get_class(), info])
	if depth > 6:
		return
	for child in node.get_children():
		_dump(child, depth + 1)
