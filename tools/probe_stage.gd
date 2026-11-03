extends SceneTree
## tools/probe_stage.gd — what the LANDSCAPE stage actually does to the screens.
##
## The canvas is 844x390 and every screen except the arena hangs in `Main._portrait_root`
## (390x844, scaled). A screen that reports `visible = true` and paints nothing is the exact
## failure this prints: size, scale and position, per screen, after the router has opened it.
##
##   godot4 --path . --rendering-driver opengl3 --resolution 844x390 \
##       --script res://tools/probe_stage.gd -- --screen inventory

var _main: Node = null
var _frames := 0
var _target := 120
var _screen := "inventory"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--screen" and i + 1 < args.size():
			_screen = args[i + 1]
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _main == null:
		return false
	if not _main._screens.has("town") or _main._nav_bar == null:
		return false
	_frames += 1
	if _frames == 2:
		_main.show_screen("character")
		var modal = _main._screens["character"]
		if modal.has_method("set_tab"):
			modal.set_tab("inventory")
		return false
	if _frames < _target:
		return false
	var stage: Control = _main._portrait_root
	print("stage: pos=%s scale=%s size=%s canvas=%s" % [str(stage.position), str(stage.scale),
		str(stage.size), str(root.get_visible_rect().size)])
	for key in _main._screens:
		var sc: Control = _main._screens[key]
		print("%-10s visible=%-5s size=%s scale=%s pos=%s parent=%s" % [str(key), str(sc.visible),
			str(sc.size), str(sc.scale), str(sc.position),
			str(sc.get_parent().name) if sc.get_parent() != null else "-"])
	var modal = _main._screens["character"]
	if modal.has_method("debug_panel"):
		print("panel: %s" % str(modal.debug_panel()))
	return true
