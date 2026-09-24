extends SceneTree
## probe_inventory_slots.gd — the real 390x844 canvas, one line per equip slot:
## the Button's global rect, its stylebox background/border, whether it clips its
## children, and each icon child's rect. Also samples pixels around the slot's edge so
## "the icon covers the border" is a measurement and not an opinion.
##
## The root Window in a SceneTree script starts at the project's window size, but it is
## only final AFTER the first frame, so the size is set explicitly and the dump waits
## three frames. (`test_page_scroll` learned the same thing the hard way: a headless root
## is 64x64 and every event lands outside it.)
##
##   godot4 --path . --rendering-driver opengl3 --script res://tools/probe_inventory_slots.gd

var _frames := 0
var _state := 0
var _main: Node = null


func _initialize() -> void:
	root.size = Vector2i(390, 844)
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _main == null or _main.state == null or _main._nav_bar == null:
		return false
	_frames += 1
	if _frames < 3:
		return false
	if _state == 0:
		_state = 1
		_main.state.set_class("barbarian")
		var h: Dictionary = _main.state.hero()
		h["equip"] = {
			"weapon": "blade_shortSword", "armor": "armor_leather",
			"helmet": "helmet_linen_hood", "shield": null, "ring1": "ring_copper",
			"ring2": null, "amulet": null, "belt": null, "gloves": null, "boots": null,
			"beltPotionSlots": [null, null, null, null],
		}
		h["inventory"] = ["armor_chainmail", "helmet_iron_helm", "ring_silver"]
		_main.open_modal("inventory")
		return false
	_await_and_dump()
	return false


func _await_and_dump() -> void:
	await process_frame
	await process_frame
	_dump()


func _dump() -> void:
	var modal = _main._screens["character"]
	var inv = modal.inventory()
	inv.refresh()
	print("root.size = ", root.size)
	print("--- DOLL (390x844) ---")
	for slot in inv._slot_nodes:
		var b: Button = inv._slot_nodes[slot]
		var st: StyleBoxFlat = b.get_theme_stylebox("normal")
		var r := b.get_global_rect()
		print("slot=%s rect=(%.1f,%.1f %.1fx%.1f) bg=%s border=%s bw=%d clip=%s" % [
			slot, r.position.x, r.position.y, r.size.x, r.size.y,
			_color(st.bg_color), _color(st.border_color),
			st.border_width_left, str(b.clip_contents)])
		for c in b.get_children():
			var tr := c as TextureRect
			if tr == null:
				print("    child=%s rect=%s clip=%s" % [c.get_class(),
					_rect(c.get_global_rect()), str(c.clip_contents)])
				continue
			var tex: Texture2D = tr.texture
			print("    icon rect=%s stretch=%d expand=%d mod=%.2f tex=%s" % [
				_rect(tr.get_global_rect()), tr.stretch_mode, tr.expand_mode,
				tr.modulate.a, ("null" if tex == null else str(tex.get_size()))])
	print("--- BAG cells ---")
	for i in range(3):
		if i >= inv._bag_nodes.size():
			break
		var cell: Button = inv._bag_nodes[i]
		var st2: StyleBoxFlat = cell.get_theme_stylebox("normal")
		print("cell %d rect=%s bg=%s clip=%s" % [i, _rect(cell.get_global_rect()),
			_color(st2.bg_color), str(cell.clip_contents)])
		for c in cell.get_children():
			print("    child=%s rect=%s" % [c.get_class(), _rect(c.get_global_rect())])
	print("--- OVERLAY ---")
	print("_item_overlay exists = ", inv._item_overlay != null)
	if inv._item_overlay != null:
		print("visible=", inv._item_overlay.visible)
	quit()


func _rect(r: Rect2) -> String:
	return "(%.1f,%.1f %.1fx%.1f)" % [r.position.x, r.position.y, r.size.x, r.size.y]


func _color(c: Color) -> String:
	return "#%02x%02x%02x" % [int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0)]
