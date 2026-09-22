extends SceneTree
## Print the result page's own geometry — the rects the layout settled on.
##
## `capture_screen.gd --screen result` writes a PNG, and a PNG cannot say WHY a block
## sits where it does: a page whose container resolved to zero height draws every child
## into the same rows and looks like a black screen. This prints each node's rect next to
## the page's so a layout bug is a number, not an impression.
##
##   godot4 --rendering-driver opengl3 --path . --script res://tools/probe_result.gd -- --result lose

var _main: Node = null
var _started := false
var _frames := 0
var _lose := false
var _printed := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i] == "--result":
			_lose = args[i + 1] == "lose"
		i += 2
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		if not _main._screens.has("town") or _main._nav_bar == null:
			return false
		_started = true
		_main._on_stop_selected(0, 0)
		var arena = _main._screens["arena"]
		if arena.battle != null:
			if _lose:
				arena.battle.hero_max_hp = 1.0
				arena.battle.hero_hp = 1.0
			else:
				arena.battle.enemy_hp = 0.0
			arena.battle.gap = 0.0
			var guard := 0
			while (not arena.battle.ended or not arena._result_built) and guard < 300:
				arena.step()
				guard += 1
		return false

	# `_layout_result_page` runs through `call_deferred`, so a couple of real frames are
	# needed before the rects mean anything.
	_frames += 1
	if _frames < 4:
		return false
	if _printed:
		return false
	_printed = true
	var arena = _main._screens["arena"]
	var page: Vector2 = arena._result_layer.size
	print("page=%s visible=%s tap_to_map=%s" % [str(page), str(arena._result_layer.visible),
		str(arena._result_tap_goes_to_map)])
	_rect("art", arena._result_art)
	_rect("defeat_art", arena._result_defeat_art)
	_rect("overlay", arena._result_overlay)
	_rect("title", arena._result_title)
	_rect("sub", arena._result_sub)
	_rect("stats", arena._result_stats)
	_rect("hp_line", arena._result_hp_line)
	_rect("loot_list", arena._loot_list)
	_rect("actions", arena._result_actions)
	print("actions=%d loot_rows=%d tiles=%s"
		% [arena._result_actions.get_child_count(), arena._loot_list.get_child_count(),
			str(_labels(arena))])
	var b = arena.battle
	print("battle hero_hp=%.0f/%.0f enemy_hp=%.0f/%.0f ended=%s won=%s"
		% [b.hero_hp, b.hero_max_hp, b.enemy_hp, b.enemy_max_hp, str(b.ended), str(b.won)])
	print("title_text='%s' sub_text='%s'" % [arena._result_title.text, arena._result_sub.text])
	quit(0)
	return false


func _rect(what: String, node: Control) -> void:
	if node == null:
		print("  %-11s NULL" % what)
		return
	var g := node.get_global_rect()
	print("  %-11s pos=%s size=%s global=%s visible=%s" % [what, str(node.position), str(node.size),
		str(g), str(node.visible)])


func _labels(arena) -> Array:
	var out: Array = []
	for child in arena._result_actions.get_children():
		out.append(str(child.get_meta("label", "?")))
	return out
