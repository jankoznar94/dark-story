extends SceneTree
## tools/probe_sockets_visibility.gd — what the item-info overlay actually builds for an
## EQUIPPED item vs a BAG item, when both carry sockets.
##
## Asserts the two things Jan reported:
##   1. an equipped item shows its socket circles (they were only drawn by
##      `refresh_sockets()`, which the equipped path never called);
##   2. nothing from the BAG is listed under the circles — the picker is a separate modal.
##
## Run: godot --headless --path . --script res://tools/probe_sockets_visibility.gd

const Main := preload("res://scripts/main.gd")

var _main: Node = null
var _started := false
var _failures: Array[String] = []


func _initialize() -> void:
	_main = Main.new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		if _main._nav_bar == null or _main.state == null:
			return false
		_started = true
		_run()
		return false
	return false


func _fail(msg: String) -> void:
	_failures.append(msg)


func _item(tag: String) -> Dictionary:
	var base: Dictionary = _main.data.item("blade_shortSword")
	var item := base.duplicate(true)
	item["id"] = "loot_probe_%s" % tag
	item["quality"] = "magic"
	item["sockets"] = 2
	item["socketedGems"] = []
	_main.state.register_loot_item(item)
	return item


func _gem(tag: String) -> Dictionary:
	# Gem ids are synthesised by GameData: the normal quality of "ruby" is exactly "ruby",
	# and the entry already carries gemType/gemQuality/iconImg.
	var item: Dictionary = _main.data.item("ruby").duplicate(true)
	item["id"] = "gem_probe_%s" % tag
	item["lootId"] = item["id"]
	_main.state.register_loot_item(item)
	_main.state.add_item(item["id"], item)
	return item


func _check(label: String, overlay, want_cells: int) -> void:
	print("--- %s" % label)
	print("  overlay.visible=%s item_id=%s sockets=%d" % [
		overlay.visible, overlay._item_id, int(overlay._item.get("sockets", 0))])
	var row = overlay._socket_row
	if row == null:
		_fail("%s: no socket row at all" % label)
		return
	var cells: int = row.get_child_count()
	print("  socket cells=%d (want %d)" % [cells, want_cells])
	if cells != want_cells:
		_fail("%s: %d socket circles, want %d" % [label, cells, want_cells])
	# The gem picker must be CLOSED until a circle is tapped, and the panel must not carry
	# a second row of gem cells.
	if overlay._gem_modal == null:
		_fail("%s: no gem picker" % label)
	elif overlay._gem_modal.visible:
		_fail("%s: gem picker is open without a socket tap" % label)
	var content_kinds := []
	for ch in overlay._content.get_children():
		content_kinds.append(ch.get_class())
	print("  content children=%s" % str(content_kinds))
	if content_kinds.count("HBoxContainer") > 0 and int(overlay._item.get("sockets", 0)) > 0:
		# exactly one HBox: the socket row (the compare block is a VBox)
		var hboxes := 0
		for ch in overlay._content.get_children():
			if ch is HBoxContainer and ch == overlay._socket_row:
				hboxes += 1
		if hboxes != 1:
			_fail("%s: expected exactly one socket row, found %d" % [label, hboxes])


func _run() -> void:
	var modal = _main._screens["character"]
	_main.open_modal("inventory")
	var inventory = modal._panes["inventory"].get_child(0).get_child(0)
	var state = _main.state
	state.set_class("barbarian")
	state.inventory().clear()

	# --- a BAG item with sockets, and one gem in the bag ---
	var bag_item := _item("bag")
	state.add_item(bag_item["id"], bag_item)
	var gem := _gem("ruby")
	inventory.refresh()
	print("bag inventory size=%d" % state.inventory().size())
	inventory._on_bag_tapped(0)
	_check("BAG item", inventory._item_overlay, 2)

	# Tapping an EMPTY socket opens the picker, and the picker lists the bag's gem.
	inventory._item_overlay.socket_tapped.emit(0)
	var picker = inventory._item_overlay._gem_modal
	print("gem picker visible=%s cells=%d" % [picker.visible, picker._grid.get_child_count()])
	if not picker.visible:
		_fail("tapping an empty socket did not open the gem picker")
	if picker._grid.get_child_count() != 1:
		_fail("gem picker lists %d gems, want 1" % picker._grid.get_child_count())

	# A choice routes through the picker -> overlay -> inventory -> main (the real wiring;
	# calling `_on_gem_tapped` directly would skip the two signals this change is about).
	picker.gem_chosen.emit(gem["id"])
	var live: Dictionary = _main.state.loot_item(bag_item["id"])
	print("after insert socketedGems=%s bag size=%d" % [str(live.get("socketedGems", [])), state.inventory().size()])
	if live.get("socketedGems", []).size() == 0:
		_fail("the gem never landed in the socket")
	inventory.close_item_info()

	# --- the SAME kind of item, EQUIPPED ---
	var worn := _item("worn")
	state.equip()["weapon"] = worn["id"]
	inventory.refresh()
	print("equip weapon=%s resolve_sockets=%d" % [
		str(state.equip().get("weapon")),
		int(_main._resolve(state.equip().get("weapon")).get("sockets", 0))])
	inventory._on_equip_slot_pressed("weapon")
	_check("EQUIPPED item", inventory._item_overlay, 2)

	for f in _failures:
		print("  FAIL: %s" % f)
	print("SOCKETS_VISIBILITY_PASS=%s" % ("true" if _failures.is_empty() else "false"))
	quit(0 if _failures.is_empty() else 1)
