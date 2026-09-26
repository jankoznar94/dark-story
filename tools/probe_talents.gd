extends SceneTree
## probe_talents.gd — the PORT's own boxes in the Skills tab, in the shape
## `tools/import/probe_pane_pwa.py talents` prints for the PWA, so the two sides can be
## compared rect by rect instead of by a diff percentage that cannot say WHICH box moved.
##
##   godot4 --path . --rendering-driver opengl3 --script res://tools/probe_talents.gd
##
## Prints `KEY=value` lines (upper-case keys) so the caller can parse them, plus a
## `TREE` line per node in the pane so a missing or invented child is visible.
##
## ⚠️  A REAL renderer is needed (`--rendering-driver opengl3`), not `--headless`: the
## pane's rects only exist once a layout pass has run, and this is the tool that reads them.

var _main: Node = null
var _frames := 0
var _step := 0


func _initialize() -> void:
	root.size = Vector2i(390, 844)
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _rect(node: Control) -> String:
	var r := node.get_global_rect()
	return "[%.1f, %.1f, %.1f, %.1f]" % [r.position.x, r.position.y, r.size.x, r.size.y]


## A node's own declared size floor — what a container would hand it if nothing expands.
func _minsize(node: Control) -> String:
	var m := node.get_combined_minimum_size()
	return "%.1fx%.1f" % [m.x, m.y]


func _process(_delta: float) -> bool:
	if _main == null or _main._nav_bar == null:
		return false
	_frames += 1
	if _frames < 3:
		return false
	if _step == 0:
		_step = 1
		# Through the nav's OWN key vocabulary, not the pane key: the nav entry is
		# `talents` and the pane is `skills`, and driving `open_modal` directly would
		# pass against a wrong mapping (see `test_character_modal`).
		_main.open_modal("skills")
		return false
	if _step == 1:
		_step = 2
		return false
	if _step != 2:
		return false
	_step = 3

	var modal = _main._screens["character"]
	var pane_wrap = modal._panes.get("skills")
	if pane_wrap == null:
		print("ERROR=no skills pane")
		quit(1)
		return true
	# ⚠️  The modal's pane is a `MarginContainer` (it carries the pane's padding) and the
	# `SkillsPanel` is INSIDE it. Reading `_points_label` off the wrapper threw
	# `Invalid access to property or key '_points_label' on a base object of type
	# 'MarginContainer'` — the probe has to walk to the panel, not assume the pane IS it.
	var pane: Control = pane_wrap
	for _i in 4:
		if pane != null and pane.get_script() != null \
				and pane.get_script().resource_path.ends_with("skills_panel.gd"):
			break
		var found: Control = null
		if pane != null:
			for child in pane.get_children():
				if child is Control and child.get_script() != null \
						and child.get_script().resource_path.ends_with("skills_panel.gd"):
					found = child
					break
		if found == null and pane != null and pane.get_child_count() > 0:
			# Not a direct child yet: descend through the single-child wrappers.
			for child in pane.get_children():
				if child is Control:
					pane = child
					break
			continue
		pane = found
		break
	if pane == null or pane.get_script() == null \
			or not pane.get_script().resource_path.ends_with("skills_panel.gd"):
		print("ERROR=skills panel not found under the pane wrapper")
		quit(1)
		return true

	# The pane's own rect and the column inside it. `SkillsPanel` is a `MinSizeBox` whose
	# single child is the content column, exactly like `InventoryScreen`.
	print("PANE=%s" % _rect(pane))
	print("PANE_MIN=%s" % _minsize(pane))
	var column: Control = pane.get_child(0) if pane.get_child_count() > 0 else null
	if column != null:
		print("COLUMN=%s" % _rect(column))
		print("COLUMN_MIN=%s" % _minsize(column))

	# The named blocks. `SkillsPanel` builds them in this order: head, tree_row,
	# talent_grid, skill_info. Read them by their declared members rather than by index,
	# because the point of this probe is to catch a child count that does not match.
	# `.flex-between` is wrapped in a `MarginBox` for its 8px vertical padding, so the label's
	# parent is the HBox and the HBox's parent is the padded box — report BOTH, because the
	# padded box is what occupies the pane's flow.
	var head_inner: Control = pane._points_label.get_parent() if pane._points_label != null else null
	var head: Control = head_inner.get_parent() if head_inner != null else null
	if head_inner != null:
		print("HEAD_INNER=%s min=%s" % [_rect(head_inner), _minsize(head_inner)])
	if head != null:
		print("HEAD=%s" % _rect(head))
		print("HEAD_MIN=%s" % _minsize(head))
	if pane._points_label != null:
		print("POINTS_LABEL=%s" % _rect(pane._points_label))
		print("POINTS_LABEL_FS=%d" % pane._points_label.get_theme_font_size("font_size"))
	if pane._schools != null:
		print("SCHOOLS=%s min=%s kids=%d" % [_rect(pane._schools), _minsize(pane._schools),
			pane._schools.get_child_count()])
		for i in pane._schools.get_child_count():
			var kid: Control = pane._schools.get_child(i)
			print("  SCHOOLS_KID[%d]=%s %s %s" % [i, kid.get_class(), _rect(kid), _minsize(kid)])
	if pane._reset_rule != null:
		print("RESET_RULE=%s visible=%s" % [_rect(pane._reset_rule), str(pane._reset_rule.visible)])
		var rw: Control = pane._reset_rule.get_parent()
		if rw != null:
			print("RESET_WRAP=%s min=%s" % [_rect(rw), _minsize(rw)])
	if pane._reset_button != null:
		print("RESET=%s" % _rect(pane._reset_button))
		print("RESET_MIN=%s" % _minsize(pane._reset_button))
		print("RESET_FS=%d" % pane._reset_button.get_theme_font_size("font_size"))
		print("RESET_DISABLED=%s" % str(pane._reset_button.disabled))
	if pane._tree_row != null:
		print("TREE_ROW=%s" % _rect(pane._tree_row))
		print("TREE_ROW_MIN=%s" % _minsize(pane._tree_row))
		print("TREE_ROW_KIDS=%d" % pane._tree_row.get_child_count())
		for i in pane._tree_row.get_child_count():
			var tab: Control = pane._tree_row.get_child(i)
			print("  TREE_TAB[%d]=%s min=%s" % [i, _rect(tab), _minsize(tab)])
	if pane._talent_grid != null:
		print("TALENT_GRID=%s" % _rect(pane._talent_grid))
		print("TALENT_GRID_MIN=%s" % _minsize(pane._talent_grid))
		print("TALENT_GRID_KIDS=%d" % pane._talent_grid.get_child_count())
		# Every child of the grid: the PWA has ONE `.talent-school`, and a tier label per
		# tier is NOT in the PWA's markup (`.talent-tier-label { display:none }`).
		# ⚠️  The grid's children ARE the tier rows. The port used to wrap each row in a
		# VBox with an invented "Tier N" label in it, so a reader who assumed "child = row"
		# would have measured the wrapper and concluded the rows were fine.
		for i in pane._talent_grid.get_child_count():
			var child: Control = pane._talent_grid.get_child(i)
			print("  GRID_KID[%d]=%s %s %s text=%s" % [i, child.get_class(), _rect(child),
				_minsize(child), ("\"%s\"" % child.text) if child is Label else "-"])
		for i in pane._talent_grid.get_child_count():
			var row: Control = pane._talent_grid.get_child(i)
			if not (row is GridContainer):
				continue
			print("TIER_ROW[%d]=%s cols=%d hsep=%d vsep=%d modulate_a=%.2f" % [
				i, _rect(row), (row as GridContainer).columns,
				row.get_theme_constant("h_separation"), row.get_theme_constant("v_separation"),
				row.modulate.a])
			for j in row.get_child_count():
				var cell_col: Control = row.get_child(j)
				print("  TIER_CELL[%d][%d]=%s min=%s" % [i, j, _rect(cell_col), _minsize(cell_col)])
				if cell_col.get_child_count() > 0:
					var cell: Control = cell_col.get_child(0)
					print("    CELL_BTN=%s min=%s" % [_rect(cell), _minsize(cell)])
				if cell_col.get_child_count() > 1:
					var lv: Control = cell_col.get_child(1)
					print("    CELL_LV=%s" % _rect(lv))
	if pane._skill_info != null:
		print("SKILL_INFO=%s" % _rect(pane._skill_info))
		print("SKILL_INFO_MIN=%s" % _minsize(pane._skill_info))
		print("SKILL_INFO_VISIBLE=%s" % str(pane._skill_info.visible))
	if pane._selected_key != "":
		print("SELECTED=%s" % pane._selected_key)

	quit(0)
	return true
