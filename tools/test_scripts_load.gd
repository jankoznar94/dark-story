extends SceneTree

# Test NACITANI SKRIPTU. Parse error v jedinem souboru shodi vsechno, co ho
# pouziva - a chyba se objevi uplne jinde, nez kde opravdu je. Tenhle test
# to rekne primo. Vystup: SCRIPTS_ALL_PASS=true / false

var fails: Array = []
var checks: int = 0


func _init() -> void:
	var files: Array = []
	for d in ["res://scripts", "res://tools"]:
		files.append_array(_gd_files(d))
	files.sort()
	_check(files.size() >= 10, "naslo se jen %d skriptu" % files.size())
	for f in files:
		checks += 1
		var res = load(str(f))
		if res == null:
			fails.append("skript se nenacetl: %s" % f)
	if fails.is_empty():
		print("SCRIPTS_ALL_PASS=true (%d skriptu)" % checks)
		quit(0)
	else:
		for f in fails:
			print("  FAIL: " + str(f))
		print("SCRIPTS_ALL_PASS=false (%d skriptu)" % checks)
		quit(1)


func _gd_files(path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(path)
	if d == null:
		return out
	d.list_dir_begin()
	var f: String = d.get_next()
	while f != "":
		if not d.current_is_dir() and f.ends_with(".gd"):
			var name: String = f
			# Testy se nactou taky, ale _init() by se spustil - soubor se
			# proto jen prelozi.
			if name.begins_with("test_") or name.begins_with("_"):
				out.append(path + "/" + f)
			else:
				out.append(path + "/" + f)
		f = d.get_next()
	d.list_dir_end()
	return out


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails.append(msg)
