extends SceneTree

const ToolHelpers := preload("res://tools/tool_helpers.gd")
## tools/probe_loot_rows.gd — what is a victory-page loot row actually made of?
##
## The screenshot shows grey bars with no text, and a PNG cannot say whether the Label is
## missing, zero-width, mis-coloured or simply not drawn. This walks the row's real subtree
## and prints class, rect, colour and text for every node in it.
##
## Run: godot4 --headless --path . --script res://tools/probe_loot_rows.gd

var _main: Node = null
var _started := false
var _frames := 0
var _printed := false


func _initialize() -> void:
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		if not _main._screens.has("town") or _main._nav_bar == null:
			return false
		_started = true
		ToolHelpers.enter_arena(_main, 0, 0)
		var arena = _main._screens["arena"]
		if arena.battle != null:
			arena.battle.enemy_hp = 0.0
			arena.battle.gap = 0.0
			var guard := 0
			while (not arena.battle.ended or not arena._result_built) and guard < 300:
				arena.step()
				guard += 1
		return false
	_frames += 1
	if _frames < 4:
		return false
	if _printed:
		return false
	_printed = true
	var arena = _main._screens["arena"]
	print("gold_won=%d result_rows=%d loot_list_visible=%s"
		% [arena._result_gold_won, arena._result_loot_rows.size(), str(arena._loot_list.visible)])
	print("loot_list rect=%s children=%d"
		% [str(arena._loot_list.get_global_rect()), arena._loot_list.get_child_count()])
	for child in arena._loot_list.get_children():
		_walk(child, 1)
	quit(0)
	return false


func _walk(node: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	if node is Control:
		var c := node as Control
		var extra := ""
		if c is Label:
			var l := c as Label
			extra = " text='%s' colour=%s font=%s" % [l.text, str(l.get_theme_color("font_color")),
				str(l.get_theme_font_size("font_size"))]
		if c is TextureRect:
			var t := c as TextureRect
			extra = " texture=%s" % ("NULL" if t.texture == null else t.texture.resource_path)
		if c is ColorRect:
			extra = " colour=%s" % str((c as ColorRect).color)
		print("%s%s rect=%s min=%s visible=%s%s" % [pad, c.get_class(), str(c.get_global_rect()),
			str(c.get_combined_minimum_size()), str(c.visible), extra])
	else:
		print("%s%s" % [pad, node.get_class()])
	for child in node.get_children():
		_walk(child, depth + 1)
