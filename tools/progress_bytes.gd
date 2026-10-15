extends SceneTree

# Vypise PRESNE bajty, ktere hra uklada do `user://zily2_progress.cfg` - sonda
# v prohlizeci je pak zapise do IndexedDB (Godot si `user://` drzi tam) a hra
# si prebere profil, jako by hrac level 1 uz vyhral.
func _init() -> void:
	Profile.allow_save = true
	var p: Profile = Profile.new()
	p.level = 2
	p.best = 1
	p.save()
	var f: FileAccess = FileAccess.open(Profile.PATH, FileAccess.READ)
	if f == null:
		print("CFG_ERR")
		quit()
		return
	var raw: PackedByteArray = f.get_buffer(f.get_length())
	print("CFG_PATH=%s" % ProjectSettings.globalize_path(Profile.PATH))
	print("CFG_HEX=%s" % raw.hex_encode())
	print("CFG_TEXT=%s" % raw.get_string_from_utf8().replace("\n", "\\n"))
	quit()
