extends SceneTree
## tools/test_scripts_load.gd — loads EVERY .gd by its real path.
##
## A parse error in a script nothing has loaded yet does not surface during
## `--import`: measured on the Dark Story side, six "Identifier not declared"
## errors produced no import output at all and the first symptom was a half-built
## scene at runtime. This takes about a second and turns that into a hard gate.
##
## Run:  godot --headless --path . --script res://tools/test_scripts_load.gd
## Pass: prints SCRIPT_LOAD_ALL_PASS=true

func _initialize() -> void:
	var failures: Array[String] = []
	var checked := 0

	for dir_path in ["res://scripts", "res://tools"]:
		for file_path in _all_gd_files(dir_path):
			checked += 1
			var res: Resource = load(file_path)
			if res == null:
				failures.append(file_path)
				continue
			# A script that parses but whose base was missing still loads as a
			# Resource; get_instance_base_type() catches the broken ones.
			if res is Script and (res as Script).can_instantiate() == false:
				failures.append("%s (cannot instantiate)" % file_path)

	print("  checked %d .gd files" % checked)
	for f in failures:
		print("  FAIL: %s" % f)
	if failures.is_empty():
		print("SCRIPT_LOAD_ALL_PASS=true")
	else:
		print("SCRIPT_LOAD_ALL_PASS=false")
	quit(0 if failures.is_empty() else 1)


func _all_gd_files(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file_name in dir.get_files():
		if file_name.ends_with(".gd"):
			out.append(dir_path.path_join(file_name))
	for sub in dir.get_directories():
		if sub.begins_with("."):
			continue
		out.append_array(_all_gd_files(dir_path.path_join(sub)))
	return out
