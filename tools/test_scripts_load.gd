extends SceneTree
## LOAD EVERY SCRIPT. The gate that catches a PARSE ERROR in a file nothing else
## has touched yet.
##
## Why this exists next to `godot --headless --path . --import`: the import run
## does NOT surface a parse error in a script that is not yet reachable from the
## resource cache. Measured (Sept 2026): a `_delta` rename in `enemy_base.gd` left
## six "Identifier \"delta\" not declared" errors, `--import` printed NOTHING at
## all, and the first symptom was a half-built scene with no monsters, no loot and
## an empty test. Loading every script by its real path is the check that catches
## it in one second, with the file and the line.
##
## Run: godot --headless --path . --script res://tools/test_scripts_load.gd
## Prints SCRIPT_LOAD_ALL_PASS=true and exits 0, or the list of failures.

func _init() -> void:
	var failures: Array = []
	var n := 0
	for path in _all_scripts("res://scripts") + _all_scripts("res://tools"):
		n += 1
		var s: Resource = load(path)
		# A PARSE ERROR does not make load() return null - measured: it returns a
		# GDScript object that cannot be instantiated, so a null check alone passed
		# while six files were broken. `can_instantiate()` is the honest question.
		if s == null:
			failures.append("%s -> load() returned null" % path)
		elif not (s as GDScript).can_instantiate():
			failures.append("%s -> PARSE ERROR (cannot instantiate)" % path)
	print("scripts loaded: %d" % n)
	if failures.is_empty() and n > 20:
		print("SCRIPT_LOAD_ALL_PASS=true")
	else:
		for f in failures:
			print("FAIL: ", f)
		print("SCRIPT_LOAD_ALL_PASS=false")
	quit()


## Recursive .gd listing. A plain directory walk rather than `DirAccess` filters,
## so a new folder of scripts cannot be silently skipped.
func _all_scripts(dir_path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			out.append_array(_all_scripts(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()
	return out
