extends SceneTree

# KAZDY SKRIPT SE NACTE. Novy `class_name` se musi nejdriv zaregistrovat
# (`--import`), jinak test, ktery ho pouziva, vubec neparsuje - a vypada to
# jako chyba v kodu.
# Vystup: SCRIPTS_ALL_PASS=true / false

var fails: Array = []
var checks: int = 0


func _init() -> void:
	for dir in ["res://scripts", "res://tools"]:
		var d: DirAccess = DirAccess.open(dir)
		if d == null:
			_check(false, "adresar %s nejde otevrit" % dir)
			continue
		for f in d.get_files():
			if not f.ends_with(".gd"):
				continue
			var path: String = dir + "/" + f
			var res: Resource = load(path)
			_check(res != null, "skript %s se nenacetl" % path)
	print("skriptu=%d chyb=%d" % [checks, fails.size()])
	print("SCRIPTS_ALL_PASS=%s" % ("true" if fails.is_empty() else "false"))
	quit()


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails.append(msg)
		print("  FAIL: %s" % msg)
