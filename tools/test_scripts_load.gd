extends SceneTree

# Kazdy .gd se musi nacist a instancovat. Parse chyba v souboru, ktery jeste
# nikdo nenacetl, se jinak projevi az jako prazdna obrazovka.
# Vystup: SCRIPT_LOAD_ALL_PASS=true / false

func _init() -> void:
	var files := _all_scripts("res://")
	var bad: Array = []
	for path in files:
		var res: Resource = load(path)
		if res == null:
			bad.append(path + " (load vratil null)")
			continue
		if res is GDScript:
			var s: GDScript = res
			if not s.can_instantiate():
				bad.append(path + " (neinstancovatelny)")
	print("skriptu=%d chyb=%d" % [files.size(), bad.size()])
	for b in bad:
		print("FAIL: " + str(b))
	if bad.is_empty():
		print("SCRIPT_LOAD_ALL_PASS=true")
	else:
		print("SCRIPT_LOAD_ALL_PASS=false")
	quit()


func _all_scripts(root: String) -> Array:
	var out: Array = []
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var full: String = root.path_join(name)
		if name.begins_with("."):
			name = dir.get_next()
			continue
		if dir.current_is_dir():
			out.append_array(_all_scripts(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out
