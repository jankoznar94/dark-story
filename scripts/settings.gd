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
const ROWS := 3

# TESTOVACI POJISTKA (stejna jako u profilu): testy prepinaji volby, aby
# overily chovani - a nesmi tim prepsat nastaveni, ktere ma hrac na disku.
# Presne to se stalo: test vypnul zvuky, ulozil je a lokalni hra pak hrala
# tise (a hledalo se to v kresleni a ve zvukovych udalostech).
static var allow_save: bool = true

# USPORNE VYKRESLOVANI. Hra se jinak kresli v NATIVNIM rozliseni displeje, coz
# na telefonu (DPR 2-3) znamena nekolikanasobne vic pixelu nez na stolnim
# displeji - a kdyz se snimek nevejde do 16,7 ms, pohyb poutniku skube.
# V uspornem rezimu se hra kresli do 960x600 a na displej se roztahne.
# VYCHOZI JE NATIVNI (ostry obraz) - usporny rezim si hrac zapina sam.
var lowres: bool = false

# HUDBA A ZVUKOVE EFEKTY. Hudba je vychozi ZAPNUTA (Jan ji chtel ve hre), ale
# hrac si ji muze vypnout - hra, ktera nedovoli ztichnout, je otrava. Zvuky
# maji vlastni prepinac: kdo chce ticho kvuli okoli, nemusi prijit o hudbu
# (a naopak).
var music: bool = true
var sfx: bool = true


func load_from_disk() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	lowres = bool(cf.get_value(SECTION, "lowres", false))
	music = bool(cf.get_value(SECTION, "music", true))
	sfx = bool(cf.get_value(SECTION, "sfx", true))


func save_to_disk() -> void:
	if not allow_save:
		return
	var cf := ConfigFile.new()
	cf.set_value(SECTION, "lowres", lowres)
	cf.set_value(SECTION, "music", music)
	cf.set_value(SECTION, "sfx", sfx)
	cf.save(PATH)


func toggle_lowres() -> void:
	lowres = not lowres
	save_to_disk()


func toggle_music() -> void:
	music = not music
	save_to_disk()


func toggle_sfx() -> void:
	sfx = not sfx
	save_to_disk()


# Popisek hodnoty do nastaveni. Text, ne ZAPNUTO/VYPNUTO: hrac se rozhoduje
# mezi DVEMA MOZNOSTMI, ne mezi zapnuto a vypnuto.
func lowres_text() -> String:
	return "Úsporné" if lowres else "Nativní"


func music_text() -> String:
	return "Zapnutá" if music else "Vypnutá"


func sfx_text() -> String:
	return "Zapnuté" if sfx else "Vypnuté"
