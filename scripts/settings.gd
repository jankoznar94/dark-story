class_name Settings
extends RefCounted

# ULOZENE NASTAVENI HRY: jakost vykreslovani a hudba. Je to jedno misto, kam
# pribudou dalsi volby, aby se hra nikde neptala na jednotlive hodnoty zvlast.
#
# Uklada se pres ConfigFile do `user://`, takze to prezije reload i reinstalaci
# PWA (u webu drzi `user://` IndexedDB).
#
# ZADNA VOLBA TU NESMI BYT NAPRAZDNO: prepinac, ktery nic nezmeni, je lez a
# hrac to pozná. Hudba tu proto je az od chvile, kdy hra hudbu opravdu ma
# (Jan, Oct 2026: "A dáme do hry nějakou primitivní hudbu.").

const PATH := "user://settings.cfg"
const SECTION := "zily2"
# POCET RADKU OBRAZOVKY NASTAVENI. Vi to i rozvrzeni (`ScreenLayout.
# SETTINGS_ROWS`), aby se klepnuti, kresleni a obdelniky nerozesly.
const ROWS := 2

# USPORNE VYKRESLOVANI. Hra se jinak kresli v NATIVNIM rozliseni displeje, coz
# na telefonu (DPR 2-3) znamena nekolikanasobne vic pixelu nez na stolnim
# displeji - a kdyz se snimek nevejde do 16,7 ms, pohyb poutniku skube.
# V uspornem rezimu se hra kresli do 960x600 a na displej se roztahne.
# VYCHOZI JE NATIVNI (ostry obraz) - usporny rezim si hrac zapina sam.
var lowres: bool = false

# HUDBA. Vychozi je ZAPNUTA (Jan ji chtel ve hre), ale hrac si ji muze vypnout -
# hra, ktera nedovoli ztichnout, je otrava.
var music: bool = true


func load_from_disk() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	lowres = bool(cf.get_value(SECTION, "lowres", false))
	music = bool(cf.get_value(SECTION, "music", true))


func save_to_disk() -> void:
	var cf := ConfigFile.new()
	cf.set_value(SECTION, "lowres", lowres)
	cf.set_value(SECTION, "music", music)
	cf.save(PATH)


func toggle_lowres() -> void:
	lowres = not lowres
	save_to_disk()


func toggle_music() -> void:
	music = not music
	save_to_disk()


# Popisek hodnoty do nastaveni. Text, ne ZAPNUTO/VYPNUTO: hrac se rozhoduje
# mezi DVEMA MOZNOSTMI, ne mezi zapnuto a vypnuto.
func lowres_text() -> String:
	return "Úsporné" if lowres else "Nativní"


func music_text() -> String:
	return "Zapnutá" if music else "Vypnutá"
