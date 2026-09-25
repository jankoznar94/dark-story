extends SceneTree
## probe_item_overlay_port.gd — the PORT's item-info overlay, measured box by box.
##
## The port side of `tools/import/probe_item_info_pwa.py`, so the two are compared rect by
## rect instead of by eye. It prints the panel, the close button, every `.stat-row`'s rect
## and both of its ends, and the row's own text.
##
##   godot4 --path . --rendering-driver opengl3 --script res://tools/probe_item_overlay_port.gd
##
## An item is taken from the SHOP's pool (real generated items with affixes) and shown
## through `ItemInfoOverlay.show_for_bag`, which is the same element a bag tap opens — so
## the measured shapes are the ones a player sees.
##
## ⚠️  The measurement happens SEVERAL FRAMES after the overlay is shown. A Control added
## this frame reports its parent's origin and its own minimum: measured without the wait,
## every row came back `[45.0, 84.4, 46.0, 88.0]` — the panel's own corner — which reads as
## "the rows are not laid out" and is really "the sort pass has not run yet".

const ItemGen := preload("res://scripts/items/item_gen.gd")
const ItemDetail := preload("res://scripts/items/item_detail.gd")

const SETTLE_FRAMES := 6
## Where the frame goes. `--out` overrides it.
var SHOT := "/tmp/port_item_overlay.png"

var _main: Node = null
var _frames := 0
var _step := 0
var _settle := 0
var _item: Dictionary = {}


func _initialize() -> void:
	root.size = Vector2i(390, 844)
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _rect(node: Control) -> String:
	var r := node.get_global_rect()
	return "[%.1f, %.1f, %.1f, %.1f]" % [r.position.x, r.position.y, r.size.x, r.size.y]


func _process(_delta: float) -> bool:
	if _main == null or _main._nav_bar == null:
		return false
	_frames += 1
	if _frames < 3:
		return false
	if _step == 0:
		_step = 1
		_main.open_modal("inventory")
		return false
	if _step == 1:
		_step = 2
		return false
	if _step == 2:
		_step = 3
		_show()
		return false
	if _step == 3:
		_settle += 1
		if _settle < SETTLE_FRAMES:
			return false
		_step = 4
		_report()
		_save()
		return false
	if _step == 4:
		_shot()
		return false
	return false


## A frame of the overlay, for a visual check against the PWA's own.
func _save() -> void:
	pass


func _shot() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(SHOT)
	print("shot=%s %dx%d" % [SHOT, img.get_width(), img.get_height()])
	quit()


## A real generated item, with as many stats as the tables will give. A rare amulet at a
## high level is the densest shape and is the item Jan looted.
func _show() -> void:
	var data: Node = _main.data
	var gen := ItemGen.new(data)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var best := 0
	for _i in 200:
		var candidate := gen.generate(data.item("goldAmulet"), "rare", 40, 40, rng)
		var lines: int = ItemDetail.build_text(candidate, data, false).split("\n").size()
		if lines > best:
			best = lines
			_item = candidate
	var overlay = _main._screens["character"]._inventory._item_overlay
	overlay.show_for_bag(_item, 0)


func _report() -> void:
	var data: Node = _main.data
	print("ITEM=%s QUALITY=%s" % [str(_item.get("name", "")), str(_item.get("quality", ""))])
	print("TEXT---")
	print(ItemDetail.build_text(_item, data, false))
	print("---")

	var overlay = _main._screens["character"]._inventory._item_overlay
	var panel: Control = overlay._panel
	var content: Control = overlay._content
	print("OVERLAY_RECT=%s" % _rect(overlay))
	print("PANEL=%s" % _rect(panel))
	print("CONTENT=%s" % _rect(content))

	# `.inv-item-overlay-close` — the X. It is a SIBLING of the panel (the PWA's
	# `position:absolute`), so it is read off the overlay and not off the content column.
	var close_holder: Control = overlay._close_holder
	var close_btn: Control = close_holder.get_child(0) as Control
	var hit_btn: Control = close_holder.get_child(1) as Control
	print("CLOSE=%s" % _rect(close_btn))
	print("CLOSE_HIT=%s" % _rect(hit_btn))

	# Every row of the stats block: the wrapper the port built, and the two labels inside.
	var stats_box: Control = null
	for child in content.get_children():
		if child is VBoxContainer and child.get_child_count() > 0:
			var first: Node = child.get_child(0)
			if first is VBoxContainer and first.get_child_count() > 0:
				stats_box = child
				break
	var rows := 0
	if stats_box != null:
		print("STATS_BOX=%s" % _rect(stats_box))
		for wrap in stats_box.get_children():
			if not (wrap is Control):
				continue
			var row := _find_hbox(wrap as Control)
			if row == null:
				continue
			if row.get_child_count() < 2:
				continue
			var left: Control = row.get_child(0) as Control
			var right: Control = row.get_child(row.get_child_count() - 1) as Control
			var left_label := left as Label
			var right_label := right as Label
			rows += 1
			print("ROW%d wrap=%s row=%s | label=%s '%s' | value=%s '%s' | left_expand=%s right_align=%d" % [
				rows, _rect(wrap as Control), _rect(row), _rect(left),
				left_label.text if left_label != null else "?",
				_rect(right), right_label.text if right_label != null else "?",
				str((left.size_flags_horizontal & Control.SIZE_EXPAND) != 0),
				right_label.horizontal_alignment if right_label != null else -1])
	print("ROW_COUNT=%d" % rows)
	print("PROBE_ITEM_OVERLAY_PORT_DONE=true")


## The first HBoxContainer under `node` — a row's chain is wrap -> MarginContainer -> HBox.
func _find_hbox(node: Control) -> Control:
	for child in node.get_children():
		if child is HBoxContainer:
			return child as Control
		if child is Control:
			var found := _find_hbox(child as Control)
			if found != null:
				return found
	return null
