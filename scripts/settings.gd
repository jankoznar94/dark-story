class_name Settings
extends RefCounted

# Ulozene nastaveni hry. Dnes jen zvuk, ale je to jedno misto, kam
# pribudou dalsi volby - hra se nikde nepta na jednotlive hodnoty zvlast.
# Uklada se pres ConfigFile do user://, takze to prezije reload i
# reinstalaci PWA (u webu drzi user:// IndexedDB).
#
# Zvuk je ZVLAST pro hudbu a zvuky, protoze hrac chce casto jen vypnout
# hudbu a efekty nechat. Vychozi stav je ZAPNUTO.

const PATH := "user://settings.cfg"
const SECTION := "zily"

var music: bool = true
var sfx: bool = true


func load_from_disk() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	music = bool(cf.get_value(SECTION, "music", true))
	sfx = bool(cf.get_value(SECTION, "sfx", true))


func save_to_disk() -> void:
	var cf := ConfigFile.new()
	cf.set_value(SECTION, "music", music)
	cf.set_value(SECTION, "sfx", sfx)
	cf.save(PATH)


func toggle_music() -> void:
	music = not music
	save_to_disk()


func toggle_sfx() -> void:
	sfx = not sfx
	save_to_disk()
