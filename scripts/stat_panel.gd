extends Control
## The hero's STAT PAGE: attack, life, mana, attributes, defence and resistances,
## in the D2 arrangement (a sheet, not a dashboard).
##
## Like the inventory window this is ONE Control that draws itself, and - the part
## that matters - every number on it comes from `hero_stats.gd`. The page never
## computes a stat, so it cannot show the player a number the game does not use.

const IB := preload("res://scripts/item_base.gd")
const Inv := preload("res://scripts/inventory_model.gd")

const COL_PANEL := Color(0.075, 0.065, 0.058, 0.94)
const COL_EDGE := Color(0.38, 0.31, 0.20)
const COL_TEXT := Color(0.90, 0.85, 0.72)
const COL_DIM := Color(0.60, 0.55, 0.46)
const COL_RULE := Color(0.26, 0.21, 0.15)
const PAD := 12.0

var stats
var inventory
var open: bool = false

signal item_used(item)


func _ready() -> void:
	# THE RECT IS THE HIT AREA. An anchors preset alone does NOT give a Control a
	# size when its parent is a CanvasLayer - measured: `size == (0, 0)` with the
	# anchors at 0..1, so every tap fell outside and `_gui_input` was never called.
	# This window was hit-tested only through direct `_gui_input` calls in the
	# tests, so the defect had never been visible.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func setup(p_stats, p_inventory) -> void:
	stats = p_stats
	inventory = p_inventory
	queue_redraw()


func set_open(on: bool) -> void:
	open = on
	visible = on
	queue_redraw()


func toggle() -> void:
	set_open(not open)


func _draw() -> void:
	if stats == null or inventory == null:
		return
	var vs := get_viewport_rect().size
	var m: float = minf(vs.x, vs.y)
	var fs := int(maxf(11.0, m * 0.024))
	var title_fs := int(maxf(13.0, m * 0.032))
	var line_h := fs + 5.0
	var rows: Array = stats.sheet()
	var equipped: Array = inventory.equipped_items()
	var col_w := m * 0.34
	var w: float = col_w * 2.0 + PAD * 3.0
	var h: float = line_h * maxf(float(rows.size()), 10.0) + title_fs + PAD * 3.0
	var box := Rect2(Vector2((vs.x - w) * 0.5, (vs.y - h) * 0.5), Vector2(w, h))

	draw_rect(box, COL_PANEL, true)
	draw_rect(box, COL_EDGE, false, 2.0)
	draw_string(ThemeDB.fallback_font, box.position + Vector2(PAD, PAD + title_fs * 0.85),
		"HRDINA", HORIZONTAL_ALIGNMENT_LEFT, -1.0, title_fs, COL_TEXT)

	# left column: attributes and vitals
	var y := box.position.y + PAD + title_fs * 1.6
	for i in rows.size():
		var r: Array = rows[i]
		var yy := y + line_h * float(i)
		draw_string(ThemeDB.fallback_font, Vector2(box.position.x + PAD, yy),
			str(r[0]), HORIZONTAL_ALIGNMENT_LEFT, col_w - 8.0, fs, COL_DIM)
		draw_string(ThemeDB.fallback_font,
			Vector2(box.position.x + PAD + col_w * 0.55, yy),
			str(r[1]), HORIZONTAL_ALIGNMENT_LEFT, col_w * 0.45, fs, COL_TEXT)

	# right column: what is actually worn, and what it adds. This is the half that
	# makes the sheet feel like D2 - you can see WHERE a number came from.
	var rx := box.position.x + PAD * 2.0 + col_w
	draw_string(ThemeDB.fallback_font, Vector2(rx, y),
		"NASazeno", HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, COL_DIM)
	var ry := y + line_h * 1.4
	for i in Inv.SLOTS.size():
		var it: Variant = inventory.equipped_at(i)
		var name := str(IB.SLOT_NAMES.get(Inv.SLOTS[i], "?"))
		if Inv.SLOTS[i] == IB.Slot.RING:
			name = "Prsten 1" if not Inv.is_second_ring(i) else "Prsten 2"
		var val := "-"
		var col := COL_DIM
		if it != null:
			val = it.display_name()
			col = it.rarity_color()
		draw_string(ThemeDB.fallback_font, Vector2(rx, ry + line_h * float(i)),
			name, HORIZONTAL_ALIGNMENT_LEFT, col_w * 0.45, fs, COL_DIM)
		draw_string(ThemeDB.fallback_font, Vector2(rx + col_w * 0.40, ry + line_h * float(i)),
			val, HORIZONTAL_ALIGNMENT_LEFT, col_w * 0.60, fs, col)

	var after := ry + line_h * float(Inv.SLOTS.size()) + line_h * 0.4
	draw_line(Vector2(rx, after), Vector2(box.end.x - PAD, after), COL_RULE, 1.0)
	var bonus: String = _gear_summary()
	draw_string(ThemeDB.fallback_font, Vector2(rx, after + line_h),
		"Ze předmětů: " + bonus, HORIZONTAL_ALIGNMENT_LEFT, col_w * 1.9, fs, COL_TEXT)
	if stats.unspent_points > 0:
		draw_string(ThemeDB.fallback_font, Vector2(rx, after + line_h * 2.2),
			"Nerozdané body: %d" % stats.unspent_points,
			HORIZONTAL_ALIGNMENT_LEFT, col_w * 1.9, fs, COL_TEXT)


## A one-line summary of what the gear contributes, summed from the items
## themselves - the same values the totals above are built from.
func _gear_summary() -> String:
	var equipped: Array = inventory.equipped_items()
	if equipped.is_empty():
		return "nic"
	var parts: Array = []
	var def: Vector2 = stats.defense()
	if def != Vector2.ZERO:
		parts.append("obrana %d-%d" % [int(def.x), int(def.y)])
	var res: Dictionary = stats.resists()
	for k in res:
		if res[k] > 0.0:
			parts.append("%s %d %%" % [_short_resist(k), int(res[k])])
	var dmg := 0.0
	for it in equipped:
		dmg += it.stat_value("enhanced_damage_pct")
	if dmg > 0.0:
		parts.append("poškození +%d %%" % int(dmg))
	if parts.is_empty():
		return "%d předmětů, bez modifikátorů" % equipped.size()
	return ", ".join(parts)


func _short_resist(key: String) -> String:
	match key:
		"resist_fire": return "oheň"
		"resist_cold": return "chlad"
		"resist_lightning": return "blesk"
		"resist_poison": return "jed"
	return key
