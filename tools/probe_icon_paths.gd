extends SceneTree
## tools/probe_icon_paths.gd — does every generated item's `iconImg` actually exist on disk?
##
## A missing icon is INVISIBLE in a headless test that only reads the dictionary: the path
## is a non-empty String and every assertion about `iconImg` passes. It is only visible when
## something tries to LOAD it, which is what this does — for every static item and for every
## gem the data layer builds.
##
## Run: godot4 --headless --path . --script res://tools/probe_icon_paths.gd

const GameData := preload("res://scripts/data/game_data.gd")


func _initialize() -> void:
	var data := GameData.new()
	root.add_child(data)
	var checked := 0
	var missing: Array = []
	var seen := 0
	for item in data.items():
		if not item is Dictionary:
			continue
		seen += 1
		var path := str(item.get("iconImg", ""))
		if path == "":
			missing.append("%s (%s): no iconImg" % [item.get("id", "?"), item.get("type", "?")])
			continue
		checked += 1
		if not ResourceLoader.exists(path):
			missing.append("%s (%s): %s" % [item.get("id", "?"), item.get("type", "?"), path])
	# A dictionary that came back empty would make "all icons present" trivially true.
	if seen == 0:
		missing.append("the data layer exposed NO items, so this checked nothing")
	print("items seen: %d, icon paths checked: %d, missing: %d" % [seen, checked, missing.size()])
	for entry in missing:
		print("  MISSING %s" % entry)
	print("ICON_PATHS_ALL_OK=%s" % ("true" if missing.is_empty() else "false"))
	quit(0 if missing.is_empty() else 1)
