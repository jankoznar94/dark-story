extends SceneTree
## tools/test_data.gd — proves the ported JSON actually loads inside Godot.
##
## CI gate. The failure this exists to catch: convert.mjs writes nothing (bad
## source path) and the project boots happily with zero monsters, zero items and
## every screen empty. A data port has to assert its own size, not just "no error".
##
## Run:  godot --headless --path . --script res://tools/test_data.gd
## Pass: prints DATA_ALL_PASS=true

const GameData := preload("res://scripts/data/game_data.gd")

## Minimum counts taken from the PWA source. If a converter change silently drops
## a table, these fail instead of the game shipping with half its content.
const EXPECTED_MIN := {
	"items": 200,
	"unique_items": 195,
	"affixes": 180,
	"monsters": 40,
	"acts": 5,
	"classes": 3,
	"enemy_spells": 11,
	"gems": 4,
}

func _initialize() -> void:
	var data := GameData.new()
	root.add_child(data)   # triggers _ready() and the load
	var report: Dictionary = data.integrity_report()
	var failures: Array[String] = []

	for key in EXPECTED_MIN:
		var got: int = report.get(key, 0)
		var need: int = EXPECTED_MIN[key]
		var ok := got >= need
		print("  %-14s %4d  (min %d)  %s" % [key, got, need, "ok" if ok else "FAIL"])
		if not ok:
			failures.append("%s: got %d, need >= %d" % [key, got, need])

	# Spot-check real content, not just counts: a table can be the right length
	# and still be full of nulls.
	var item: Dictionary = data.item("blade_shortSword")
	if item.is_empty() or item.get("name", "") != "Short Sword":
		failures.append("item lookup failed for blade_shortSword")
	else:
		print("  item blade_shortSword -> %s, dmg %s-%s" % [
			item["name"], item["baseDmgMin"], item["baseDmgMax"]])

	var barb: Dictionary = data.class_by_id("barbarian")
	if barb.is_empty() or barb.get("spells", []).size() < 5:
		failures.append("barbarian class missing or has too few spells")
	else:
		print("  class barbarian -> %d spells, primary %s" % [
			barb["spells"].size(), barb.get("primaryAttr", "?")])

	var forest: Array = data.monsters_for_theme(0)
	if forest.is_empty() or not forest[0].has("name"):
		failures.append("theme 0 monsters missing")
	else:
		print("  theme 0 monsters -> %d, first: %s" % [forest.size(), forest[0]["name"]])

	var act: Dictionary = data.act_by_id(0)
	if act.is_empty() or not act.has("boss"):
		failures.append("act 0 missing or has no boss")
	else:
		print("  act 0 -> %s, boss %s" % [act["name"], act["boss"]["name"]])

	for f in failures:
		print("  FAIL: %s" % f)
	if failures.is_empty():
		print("DATA_ALL_PASS=true")
	else:
		print("DATA_ALL_PASS=false")
	quit(0 if failures.is_empty() else 1)
