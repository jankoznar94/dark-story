extends SceneTree
## probe_item_info.gd — what the item-info overlay would actually PRINT for a rolled item.
##
## Jan's report: "I looted an amulet with a white name (which should not be possible,
## because Common jewellery should not exist) and it had no stats at all. Just a name."
##
## An item with a white name and no stats has exactly two causes and this tells them
## apart:
##   * the ROLL produced a normal-quality amulet (the PWA promotes that to magic), or
##   * the item HAS affixes and `ItemDetail` drops every one of their lines (a stat key
##     missing from `_mod_stat_order` is invisible in the overlay).
##
##   godot4 --headless --path . --script res://tools/probe_item_info.gd
##
## Prints `KEY=value` lines and the full detail text of every shape it finds.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const ItemDetail := preload("res://scripts/items/item_detail.gd")
const ItemStats := preload("res://scripts/items/item_stats.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")

const ROLLS := 400


func _initialize() -> void:
	var data: Node = GameData.new()
	root.add_child(data)
	var gen := ItemGen.new(data)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260925

	# --- 1. does the GEAR branch ever hand out a normal-quality jewel? -------------
	var loot := LootSystem.new(data, gen)
	var quality_counts := {}
	var amulet_shapes := {}
	for _i in ROLLS:
		var item: Dictionary = loot.generate_item(_state_stub(), 0, 1, false, 3, 0, rng)
		if item.is_empty():
			continue
		var key := "%s/%s" % [str(item.get("type", "")), str(item.get("quality", ""))]
		quality_counts[key] = int(quality_counts.get(key, 0)) + 1
		if str(item.get("type", "")) in ["amulet", "ring"]:
			var name_line := "%s | %s" % [str(item.get("name", "")), str(item.get("quality", ""))]
			amulet_shapes[name_line] = int(amulet_shapes.get(name_line, 0)) + 1
	print("GEAR_BRANCH_QUALITIES=%s" % JSON.stringify(quality_counts))

	# --- 2. a normal-quality amulet, by hand, exactly as the shop or a drop rolls it --
	var base: Dictionary = data.item("silverAmulet")
	var common := gen.generate(base, "normal", 3, 3, rng)
	print("NORMAL_AMULET_NAME=%s" % str(common.get("name", "")))
	print("NORMAL_AMULET_QUALITY=%s" % str(common.get("quality", "")))
	print("NORMAL_AMULET_COLOUR=%s" % ItemStats.quality_color(common).to_html(false))
	print("NORMAL_AMULET_TEXT---")
	print(ItemDetail.build_text(common, data, false))
	print("---")

	# --- 3. every affix whose stats the DETAIL renderer would drop -----------------
	var order := ItemDetail._mod_stat_order()
	var dropped := {}
	for a in data.affixes():
		var stats: Dictionary = a.get("stats", {})
		if stats.is_empty():
			continue
		var all_dropped := true
		for stat in stats:
			if order.has(stat) or stat == "swingMs":
				all_dropped = false
		if all_dropped:
			dropped[str(a.get("id", ""))] = JSON.stringify(stats)
	print("AFFIXES_WHOLLY_INVISIBLE=%d" % dropped.size())
	print("AFFIX_LIST=%s" % JSON.stringify(dropped))

	# --- 4. an item carrying ONLY an invisible affix, rolled for real --------------
	var sample := _roll_until_affix(gen, data, "amulet", "silverAmulet", rng)
	if not sample.is_empty():
		print("INVISIBLE_SAMPLE_NAME=%s" % str(sample.get("name", "")))
		print("INVISIBLE_SAMPLE_QUALITY=%s" % str(sample.get("quality", "")))
		print("INVISIBLE_SAMPLE_AFFIXES=%s" % JSON.stringify(sample.get("affixes", [])))
		print("INVISIBLE_SAMPLE_TEXT---")
		print(ItemDetail.build_text(sample, data, false))
		print("---")

	print("PROBE_ITEM_INFO_DONE=true")
	quit()


## A bare state stub: `generate_item` reads `state.hero()["level"]` and nothing else
## on the gear branch, and this probe is not testing the state.
func _state_stub() -> RefCounted:
	var stub := RefCounted.new()
	stub.set_script(_stub_script())
	return stub


func _stub_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = "extends RefCounted\nvar data := {}\nfunc hero() -> Dictionary:\n\treturn {\"level\": 3}\n"
	script.reload()
	return script


## Roll amulets until one comes out whose whole affix set is invisible to the renderer,
## so the probe prints a REAL item rather than a hand-built dictionary.
func _roll_until_affix(gen: ItemGen, data: Node, item_type: String, base_id: String,
		rng: RandomNumberGenerator) -> Dictionary:
	var base: Dictionary = data.item(base_id)
	var order := ItemDetail._mod_stat_order()
	for _i in 3000:
		var quality := "magic" if rng.randf() < 0.7 else "rare"
		var item := gen.generate(base, quality, 20, 20, rng)
		var visible := false
		for a in item.get("affixes", []):
			for stat in a.get("stats", {}):
				if order.has(stat):
					visible = true
		if not visible and not (item.get("affixes", []) as Array).is_empty():
			return item
	return {}
