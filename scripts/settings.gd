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
# USPORNE ROZHLEDNI. Hra se jinak kresli v NATIVNIM rozliseni displeje, coz
# na telefonu (DPR 2-3) znamena nekolikanasobne vic pixelu nez na stolnim
# displeji - a kdyz se snimek nevejde do 16,7 ms, pohyb poutniku skube.
# V uspornem rezimu se hra kresli do 960x600 a na displej se roztahne.
# VYCHOZI JE NATIVNI (ostry obraz) - usporny rezim si hrac zapina sam.
var lowres: bool = false


func load_from_disk() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	music = bool(cf.get_value(SECTION, "music", true))
	sfx = bool(cf.get_value(SECTION, "sfx", true))
	lowres = bool(cf.get_value(SECTION, "lowres", false))


func save_to_disk() -> void:
	var cf := ConfigFile.new()
	cf.set_value(SECTION, "music", music)
	cf.set_value(SECTION, "sfx", sfx)
	cf.set_value(SECTION, "lowres", lowres)
	cf.save(PATH)


func toggle_music() -> void:
	music = not music
	save_to_disk()


func toggle_sfx() -> void:
	sfx = not sfx
	save_to_disk()


func toggle_lowres() -> void:
	lowres = not lowres
	save_to_disk()


# Popisek hodnoty do nastaveni. Text, ne ZAPNUTO/VYPNUTO: u rozliseni se
# hrac rozhoduje mezi DVEMA MOZNOSTMI, ne mezi zapnuto a vypnuto.
func lowres_text() -> String:
	return "Úsporné" if lowres else "Nativní"
