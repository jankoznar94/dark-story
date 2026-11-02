extends SceneTree
const ToolHelpers := preload("res://tools/tool_helpers.gd")
var _main: Node = null
var _started := false
var _frames := 0

func _initialize() -> void:
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)

func _dump(ctrl: Control, indent: String) -> void:
	var sb := ctrl.get_theme_stylebox("normal")
	var line := "%s%s pos=%s size=%s" % [indent, ctrl.get_class(), str(ctrl.position), str(ctrl.size)]
	if sb is StyleBoxFlat:
		line += " bg=%s border=%s w=%d r=%s" % [str(sb.bg_color), str(sb.border_color),
			sb.border_width_left, str(sb.corner_radius_top_left)]
	print(line)
	for c in ctrl.get_children():
		if c is Control:
			_dump(c, indent + "  ")

func _process(_d: float) -> bool:
	if not _started:
		if not _main._screens.has("town") or _main._nav_bar == null:
			return false
		_started = true
		ToolHelpers.enter_arena(_main, 0, 0)
		return false
	_frames += 1
	var arena = _main._screens.get("arena", null)
	if arena == null or arena.battle == null:
		return false
	if _frames < 12:
		return false
	arena.battle.opp_type = "dodge"
	arena.battle.opp_resolved = false
	arena.battle.opp_failed = false
	var b: Button = arena._reaction_buttons["dodge"]
	print("=== dodge button ===")
	_dump(b, "")
	print("clip_contents=", b.clip_contents, " focus_mode=", b.focus_mode)
	quit(0)
	return true
