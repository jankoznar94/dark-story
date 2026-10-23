extends SceneTree

# Kazdy skript se musi nacist A MUSI BYT PRELOZITELNY. Vystup: SCRIPTS_ALL_PASS=true
#
# PROC `reload()`: `load()` na skriptu s chybou v kodu vrati objekt, ktery
# vypada jako platny GDScript - takze sama kontrola "load != null" prosla i
# tehdy, kdyz obrazovka mela rozbitou promennou a nevykreslila se. `reload()`
# vraci Error a chybu opravdu nahodi.

func _init() -> void:
	var dir := DirAccess.open("res://scripts")
	var names: Array = []
	if dir != null:
		dir.list_dir_begin()
		var f: String = dir.get_next()
		while f != "":
			if f.ends_with(".gd"):
				names.append(f)
			f = dir.get_next()
		dir.list_dir_end()
	var bad: Array = []
	for n in names:
		var s: Resource = load("res://scripts/" + String(n))
		if s == null or not (s is Script):
			bad.append(String(n) + " (nenacte se)")
			continue
		var err: int = (s as Script).reload()
		if err != OK:
			bad.append(String(n) + " (chyba v kodu, err=%d)" % err)
	print("scripts=%d bad=%d" % [names.size(), bad.size()])
	for b in bad:
		print("       FAIL: %s" % b)
	print("SCRIPTS_ALL_PASS=%s" % ("true" if bad.is_empty() and names.size() > 0 else "false"))
	quit()
