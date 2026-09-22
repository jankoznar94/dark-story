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

	# EVERY asset the port loads must actually LOAD, and a file whose CONTENT does not match its
	# extension is the silent way that fails: Godot refuses it with "Failed loading resource"
	# and the caller gets `null`, so a screen draws an empty box where an image should be.
	# This is not hypothetical — `assets/result_defeat.png` shipped as a JPEG and the whole
	# defeat page was a black screen with two labels in the corner, and NO test could see it
	# because a null texture is not a parse error and the node is still `visible`.
	#
	# `ResourceLoader.exists()` is not enough (it answers for the IMPORT cache, not the bytes),
	# so the file's own magic bytes are checked against its extension.
	var bad_assets: Array[String] = []
	var checked := 0
	for path in _image_paths("res://assets"):
		checked += 1
		if not _magic_matches(path):
			bad_assets.append(path)
	if bad_assets.is_empty():
		print("  %d image assets -> all match their extensions" % checked)
	for bad in bad_assets:
		failures.append("%s: its CONTENT does not match its extension (Godot will refuse it)" % bad)

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


## Every image under a `res://` directory, recursively. `DirAccess` is used rather than
## `ResourceLoader` because the point is to read the RAW files.
func _image_paths(dir: String) -> Array[String]:
	var out: Array[String] = []
	var handle := DirAccess.open(dir)
	if handle == null:
		return out
	for sub in handle.get_directories():
		out.append_array(_image_paths(dir.path_join(sub)))
	for file in handle.get_files():
		var lower := file.to_lower()
		if lower.ends_with(".png") or lower.ends_with(".webp") or lower.ends_with(".jpg"):
			out.append(dir.path_join(file))
	return out


## Does the file's own magic bytes match what its extension promises? Godot's importer sniffs
## the CONTENT, so a JPEG named `.png` is a file that reports as an image and loads as nothing.
func _magic_matches(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var head := f.get_buffer(12)
	f.close()
	if head.size() < 12:
		return false
	var is_png := head[0] == 0x89 and head[1] == 0x50 and head[2] == 0x4E and head[3] == 0x47
	var is_jpeg := head[0] == 0xFF and head[1] == 0xD8 and head[2] == 0xFF
	var is_webp := head[0] == 0x52 and head[1] == 0x49 and head[2] == 0x46 and head[3] == 0x46 \
		and head[8] == 0x57 and head[9] == 0x45 and head[10] == 0x42 and head[11] == 0x50
	var lower := path.to_lower()
	if lower.ends_with(".png"):
		return is_png
	if lower.ends_with(".webp"):
		return is_webp
	if lower.ends_with(".jpg"):
		return is_jpeg
	return false
