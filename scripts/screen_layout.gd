class_name ScreenLayout
extends RefCounted

# CELE ROZVRZENI se pocita z REALNE velikosti okna. Zakladni navrh je
# 960x600 a na nem je vyladeny vzhled, ale hra se nikde neletterboxuje:
# na sirokem telefonu dostane ARENA vic mista do sirky (useky se prodlouzi),
# na nizkem displeji min do vysky.
#
# DVE MERITKA, protoze jeden druhy nesmi rict, jak ma vypadat:
#   `s`  - meritko HERNI PLOCHY (velikosti bonusu, vystupu, tloustek linii).
#          Kruh musi zustat kruhem, proto se nikdy neroztahuje pres osy.
#   `ui` - meritko OVLADANI A PISMA. Drzi se dotykoveho minima pro prst.
#
# HERNI DESKA NENESE ZADNY TEXT. Kazdy popisek v desce je misto, ktere
# chybi poutnikum, proto z ni zmizely popisky vyhybky, vystupu i kmene.
# Vsechno vysvetleni je v MENU pod tlacitkem NAVOD a cisla poskozeni
# v hornim panelu - obe mimo herni plochu.
#
# MENU je prvni obrazovka hry. Jeho tlacitka se pocitaji z okna stejne
# jako vsechno ostatni, aby se dala na telefonu pohodlne stisknout.

const REF_W := 960.0
const REF_H := 600.0
# Horni panel s císly: Vlna, Životy, Zlato a vybraný úsek. Dva radky, ktere
# se vejdou i s písmem velikosti 20 px do 52 px - vic mista pro desku.
const HUD_H := 52.0
# Spodni pruh. Neni v nem zadny navod (ten je v menu), zustava jen SKIP,
# takze staci 44 px - presne dotykove minimum pro prst.
const BAR_UNIT_H := 52.0
const PAD := 16.0
const BTN_H := 48.0
const SKIP_W := 92.0
# Rozestup mezi prvky, ktere se pocitaji z rozvrzeni (dnes tlacitko ZPET).
const GAP := 40.0
# Dotykove minimum pro prst. Pod tim se tlacitko neda spolehlive trefit.
const MIN_TOUCH := 44.0
# Menu: ctyři tlacitka pod sebou - kolo, navod, nastaveni, aktualizace.
const MENU_BTN_W := 340.0
const MENU_BTN_H := 58.0
const MENU_GAP := 20.0
const MENU_COUNT := 4

var view := Vector2(REF_W, REF_H)
var s := 1.0
var ui := 1.0
var hud_h := HUD_H
var bar_h := BAR_UNIT_H
var bar_y := REF_H - BAR_UNIT_H
var arena := Rect2()
var btn_h := BTN_H
var text_x := 0.0
var skip_rect := Rect2()
# Tlacitko ZPET na obrazovce navodu. Jedine tlacitko, ktere se pocita
# ze spodniho pruhu, proto se do nej take kresli.
var guide_back := Rect2()
# Menu a nastaveni - pocita se z okna, ne z herniho pruhu.
var menu_buttons: Array = []
var menu_title_y := 0.0
var settings_toggle := Rect2()
var settings_back := Rect2()


func compute(v: Vector2) -> void:
	view = v
	s = clampf(minf(v.x / REF_W, v.y / REF_H), 0.45, 4.0)

	var floor_ui: float = MIN_TOUCH / BTN_H
	ui = clampf(s, floor_ui, 1.8)

	hud_h = HUD_H * ui
	bar_h = BAR_UNIT_H * ui
	bar_y = v.y - bar_h

	# Arena si bere vsechno, co zbyde mezi HUDem a ovladacim pruhem.
	arena = Rect2(PAD * s, hud_h + 6.0 * s,
		maxf(40.0, v.x - 2.0 * PAD * s), maxf(40.0, bar_y - hud_h - 12.0 * s))

	text_x = PAD * ui
	btn_h = BTN_H * ui
	# Jedine tlacitko herniho pruhu. Pruh je ted jen ovladaci, ne navod,
	# proto je tak nizky - kazdy pixel navic jde do herni desky.
	skip_rect = Rect2(v.x - PAD * ui - SKIP_W * ui,
		bar_y + (BAR_UNIT_H - BTN_H) * 0.5 * ui, SKIP_W * ui, btn_h)
	# ZPET je na stejnem miste jako SKIP, ale vidi se vzdy jen jedno z nich.
	guide_back = skip_rect

	# --- MENU ---
	# Ctyři tlacitka pod sebou, svisle vycentrovana. Vyska se drzi na
	# dotykovem minimu; kdyz je displej nizky, zmensi se rozestup, ne
	# tlacitko - spatne stisknutelne tlacitko je horsi nez tesnejsi menu.
	var mw: float = minf(MENU_BTN_W * ui, v.x - 2.0 * PAD * ui)
	var mh: float = maxf(MIN_TOUCH, MENU_BTN_H * ui)
	var mgap: float = MENU_GAP * ui
	var mtot: float = mh * float(MENU_COUNT) + mgap * float(MENU_COUNT - 1)
	var room: float = v.y - mh - 12.0 * ui
	if mtot > room:
		mgap = maxf(4.0, (room - mh * float(MENU_COUNT)) / float(MENU_COUNT - 1))
		mtot = mh * float(MENU_COUNT) + mgap * float(MENU_COUNT - 1)
	var my0: float = (v.y - mtot) * 0.5 + 16.0 * ui
	menu_buttons = []
	for i in range(MENU_COUNT):
		menu_buttons.append(Rect2((v.x - mw) * 0.5,
			my0 + float(i) * (mh + mgap), mw, mh))
	menu_title_y = my0 - 28.0 * ui

	# --- NASTAVENI ---
	# Dva prepinace a ZPET pod sebou, svisle vycentrovane. Stejna logika
	# jako u menu: vyska zustava na dotykovem minimu, zmensuje se jen
	# mezera - spatne stisknutelne policko je horsi nez tesnejsi rozvrzeni.
	var sh: float = mh
	var sgap: float = 10.0 * ui
	var stot: float = sh * 3.0 + sgap * 2.0
	if stot > v.y - 40.0 * ui:
		sgap = maxf(4.0, (v.y - 40.0 * ui - sh * 3.0) * 0.5)
		stot = sh * 3.0 + sgap * 2.0
	var sy0: float = (v.y - stot) * 0.5
	settings_toggle = Rect2((v.x - mw) * 0.5, sy0, mw, sh)
	settings_back = Rect2((v.x - mw) * 0.5, sy0 + (sh + sgap) * 2.0, mw, sh)


# Herni dotykove cile. Testy na nich hledaji prekryvy s mistry na bonusy.
# Herni deska je od textu ohnuta, proto tady krome SKIPU nic neni.
func all_buttons() -> Array:
	return [skip_rect]


func menu_rect(i: int) -> Rect2:
	var r: Rect2 = menu_buttons[i]
	return r


# Vsechny dotykove cile MENU. Menu a nastaveni se nikdy nezobrazuji
# soucasne, proto se testuji kazde zvlast - míchat je do jednoho seznamu
# by hlasilo prekryvy, ktere hrac nikdy nevidi.
func all_menu_buttons() -> Array:
	var out: Array = []
	for r in menu_buttons:
		out.append(r)
	return out


# Vsechny dotykove cile NASTAVENI: dva prepinace a ZPET.
func all_settings_buttons() -> Array:
	var out: Array = []
	var sh: float = settings_toggle.size.y
	var gap: float = row_gap()
	out.append(settings_toggle)
	out.append(Rect2(settings_toggle.position.x,
		settings_toggle.position.y + sh + gap, settings_toggle.size.x, sh))
	out.append(settings_back)
	return out


# Mezera mezi radky nastaveni. Pocita se z rozvrzeni, aby kresleni,
# vstup i testy pouzivaly PRESNE stejnou hodnotu - kdyby si ji kazdy
# pocital sam, rozesly by se a klikacka by nesedela na obrazek.
func row_gap() -> float:
	return settings_back.position.y - settings_toggle.position.y - settings_toggle.size.y * 2.0


func overlaps_with(rect: Rect2, margin: float = 0.0) -> bool:
	for b in all_buttons():
		var r: Rect2 = b
		if r.grow(margin).intersects(rect):
			return true
	return false


func font(px: float) -> int:
	return int(roundf(px * ui))
