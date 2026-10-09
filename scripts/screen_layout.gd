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
# HERNI DESKA NENESE ZADNY TEXT ANI ZADNE OVLADANI. Popisky z ni zmizely
# (jsou v menu pod NAVODEM) a zmizel i cely spodni pruh vcetne tlacitka SKIP.
# Deska proto saha az k spodnimu okraji displeje - kazdy pixel navic dostane
# hraci plocha. Zbyva jen horni panel s císly, ktery je mimo desku.
#
# Hraci plocha je proto ZAMERNE bez jedineho tlacitka: `all_buttons()` vraci
# prazdny seznam a testy to kontroluji. Kdyby se do desky nekdo pokusil
# vratit tlacitko, hrac by o nej zacal pricházet mista.
#
# MENU je prvni obrazovka hry. Jeho tlacitka se pocitaji z okna stejne
# jako vsechno ostatni, aby se dala na telefonu pohodlne stisknout.

const REF_W := 960.0
const REF_H := 600.0
# Horni panel s císly: Vlna, Životy, Zlato a vybraný úsek. Dva radky
# s písmem 20/13 px se vejdou do 48 px - vic mista pro desku.
const HUD_H := 48.0
const PAD := 16.0
# Dotykove minimum pro prst. Pod tim se tlacitko neda spolehlive trefit.
const MIN_TOUCH := 44.0
# Sirka tlacitka ZPET v navodu.
const SKIP_W := 92.0
# Menu: pet tlacitek pod sebou - kolo, editor, navod, nastaveni, aktualizace.
const MENU_BTN_W := 340.0
const MENU_BTN_H := 58.0
const MENU_GAP := 20.0
const MENU_COUNT := 5

# EDITOR ma svuj pruh tlacitek DOLE - jako jedina obrazovka. Hraci deska
# zustava bez ovladani (a test na tom trva), ale level se na telefonu bez
# tlacitek vubec neda upravit. Pruh je ZAMERNE nizky: kazdy pixel navic
# bere editoru misto na mrizku, kterou upravuje.
const ED_BAR_H := 40.0
const ED_GAP := 4.0
const ED_COUNT := 12

# HERNI DESKA JE BEZ OVLADANI - jedina vyjimka je navrat do editoru, kdyz
# hrac hraje level, ktery si prave vyrobil. Je to v HORNIM PANELU, ne na
# desce: panel neni hraci plocha a hrac se z rozdelaneho levelu musi dostat
# zpet. Sirka je zamerne velkorysa - je to cil pro prst.
const HUD_BACK_W := 104.0

var view := Vector2(REF_W, REF_H)
var s := 1.0
var ui := 1.0
var hud_h := HUD_H
# Spodni okraj hraci plochy. Pruh uz neexistuje, takze je to jen okraj
# displeje s malou rezervou - sit pod nej nesmi kreslit.
var board_bottom := REF_H
var arena := Rect2()
var text_x := 0.0
# Tlacitko ZPET na obrazovce navodu. Neni v zadnem pruhu (ten je pryc),
# stoji v rohu obrazovky a text si nad nim nechava misto.
var guide_back := Rect2()
# Menu a nastaveni - pocita se z okna, ne z herni plochy.
var menu_buttons: Array = []
var menu_title_y := 0.0
var settings_toggle := Rect2()
var settings_back := Rect2()
# Navrat do editoru v hornim panelu hry (jen kdyz hrac hraje level z editoru).
var hud_back := Rect2()
# Editor: pruh tlacitek dole + plocha, kterou zabira.
var ed_buttons: Array = []
var editor_arena := Rect2()


func compute(v: Vector2) -> void:
	view = v
	s = clampf(minf(v.x / REF_W, v.y / REF_H), 0.45, 4.0)

	# Podlaha meritka ovladani. Neni to jen dotykove minimum: pismo v HUDu
# by pri 0.76 vyslo na 15 px a to se na telefonu necte. 0.85 drzi
# tlacitka NAD minimem (58*0.85 = 49 px) a text citelny.
	var floor_ui: float = maxf(MIN_TOUCH / MENU_BTN_H, 0.85)
	ui = clampf(s, floor_ui, 1.8)

	hud_h = HUD_H * ui
	# Deska jde az k spodnimu okraji displeje. Pruh, ktery tu driv byl,
	# je pryc - jeho vyska je ted hraci plocha.
	board_bottom = v.y - 3.0 * s

	# Arena si bere vsechno, co zbyde pod HUDem. Mezera pod panelem je jen
	# mala: kazdy pixel tady je pixel, ktery hrac dostane na desku.
	arena = Rect2(PAD * s, hud_h + 1.0 * s,
		maxf(40.0, v.x - 2.0 * PAD * s),
		maxf(40.0, board_bottom - hud_h - 1.0 * s))

	text_x = PAD * ui
	# ZPET v navodu: v rohu obrazovky, na dotykovem minimu.
	guide_back = Rect2(v.x - PAD * ui - SKIP_W * ui,
		v.y - MIN_TOUCH - 8.0 * ui, SKIP_W * ui, MIN_TOUCH)
	# NAVRAT DO EDITORU v hornim panelu. Kresli se jen tehdy, kdyz hrac hraje
	# level z editoru - jinak by na desce bylo tlacitko, ktere nema co delat.
	# Je to v panelu, ne na desce, a je to co nejvetsi: prst se na telefon
	# nema kam jinam vejit.
	hud_back = Rect2(v.x - PAD * ui * 0.5 - HUD_BACK_W * ui, 3.0 * ui,
		HUD_BACK_W * ui, maxf(MIN_TOUCH * 0.8, hud_h - 6.0 * ui))

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

	# --- EDITOR ---
	# Pruh tlacitek dole, vyska z dotykoveho minima pro prst (nemeni se),
	# mezera a sirka se pocitaji z mista. Osm tlacitek v jedne rade se na
	# 640 px vejde jen tak, ze se zmensi MEZERA, ne vyska - nizke tlacitko
	# se prstem netrefi.
	var eh: float = maxf(MIN_TOUCH, ED_BAR_H * ui)
	var egap: float = ED_GAP * ui
	var etot: float = v.x - 2.0 * PAD * ui
	var ew: float = (etot - egap * float(ED_COUNT - 1)) / float(ED_COUNT)
	if ew < MIN_TOUCH * 0.8:
		egap = 2.0
		ew = (etot - egap * float(ED_COUNT - 1)) / float(ED_COUNT)
	ed_buttons = []
	var ex0: float = PAD * ui
	var ey: float = v.y - eh - 6.0 * ui
	for i in range(ED_COUNT):
		ed_buttons.append(Rect2(ex0 + float(i) * (ew + egap), ey, ew, eh))
	# ARENA EDITORU KONCI NAD PRUHEM. Pruh se kresli od `editor_bar_top()`
	# nahoru (kvuli popiskum nad tlacitky) - kdyby arena koncila az u tlacitek,
	# prekryl by pruh spodni cast mrizky, kterou hrac upravuje.
	editor_arena = Rect2(PAD * s, hud_h + 1.0 * s,
		maxf(40.0, v.x - 2.0 * PAD * s),
		maxf(40.0, editor_bar_top() - 2.0 * ui - hud_h - 1.0 * s))


# Horni hrana pruhu tlacitek editoru. Pocita se na JEDNOM miste: kresleni
# pruhu, arena editoru i sit, ktera pod nej nesmi kreslit, pouzivaji tuhle
# hodnotu. Kdyz si ji kazdy pocital sam, pruh prekryl kus herni plochy.
func editor_bar_top() -> float:
	if ed_buttons.is_empty():
		return view.y
	return float(ed_buttons[0].position.y) - 26.0 * ui


# HERNI DESKA JE BEZ OVLADANI. Vraci prazdny seznam a testy na tom trvaji:
# jedina interakce na desce je klepnuti na usek nebo na misto na bonus,
# a to zadne tlacitko nepotrebuje. Kdyby tu nejake pribylo, ubralo by misto
# hraci plose - presne to se stalo s pruhem, ktery jsme odstranili.
func all_buttons() -> Array:
	return []


func menu_rect(i: int) -> Rect2:
	var r: Rect2 = menu_buttons[i]
	return r


# Tlacitka EDITORU. Nejsou na herni desce - ta je porad bez ovladani; editor
# je jina obrazovka se svym vlastnim pruhem dole.
func all_editor_buttons() -> Array:
	var out: Array = []
	for r in ed_buttons:
		out.append(r)
	return out


# VELIKOST PISMA POPISKU V PRUHU EDITORU. Tlacitek je dvanact a popisek
# "výhybka" je na 640x360 o par pixelu sirsi nez tlacitko - kdyby se pismo
# zmensovat nemohlo, prisel by hrac o popisek (a tlacitko bez popisku je
# horsi nez zadne). Pocita se na JEDNOM miste: kresleni i test meri stejnym
# cislem, jinak by test meril neco jineho, nez hrac vidi.
func ed_label_px(labels: Array, f: Font) -> int:
	if ed_buttons.is_empty():
		return 13
	var room: float = ed_buttons[0].size.x - 4.0
	for px in range(13, 9, -1):
		var fpx: int = font(float(px))
		var fits := true
		for l in labels:
			if f.get_string_size(str(l), HORIZONTAL_ALIGNMENT_LEFT, -1, fpx).x > room:
				fits = false
				break
		if fits:
			return px
	return 10


# ZKRACENI TEXTOVÉHO POLE NA SIRKU. Dlouhy text (kod levelu je pres 700
# znaku) by jinak pretekl mimo obrazovku a hrac by videl jen jeho zacatek.
# Pocita se pulenim intervalu: text se meri v kazdem kroku znovu a u 800
# znaku by to bylo 800 merení na kazdy snimek.
func fit_text(text: String, f: Font, px: int, max_w: float) -> String:
	if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x <= max_w:
		return text
	var lo := 0
	var hi: int = text.length()
	while lo < hi:
		var mid: int = int((lo + hi + 1) / 2)
		if f.get_string_size(text.substr(0, mid) + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, px).x <= max_w:
			lo = mid
		else:
			hi = mid - 1
	return text.substr(0, lo) + "…"


# SEZNAM ULOZENYCH LEVELU v editoru. Kolik radku se vejde, pocita rozvrzeni -
# jinak by hrac s hodne levely mel seznam, ktery mu pretece z displeje.
func editor_list_fit() -> int:
	var top: float = hud_h + 8.0 * ui
	var bottom: float = view.y - 6.0 * ui
	var h: float = editor_list_row_h()
	return maxi(int((bottom - top + editor_list_gap()) / (h + editor_list_gap())), 1)


func editor_list_row_h() -> float:
	return maxf(MIN_TOUCH, 30.0 * ui)


func editor_list_gap() -> float:
	return 6.0 * ui


func editor_list_rows(count: int) -> Array:
	var out: Array = []
	if count <= 0:
		return out
	var h: float = editor_list_row_h()
	var gap: float = editor_list_gap()
	var top: float = hud_h + 8.0 * ui
	var w: float = view.x - 2.0 * PAD * ui
	for i in range(count):
		out.append(Rect2(PAD * ui, top + float(i) * (h + gap), w, h))
	return out


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
