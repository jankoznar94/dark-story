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
# SEDM POLOZEEK V PRUHU: taby (nastroje / vyber / level) a akce (zpet,
# seznam, export, hrat). Na 640x360 dava kazda 84 px pri mezere 3.4 px -
# popisky se do toho vejdou pri 13 px (meri to `ed_label_px`, stejnym cislem
# jako kresleni). Vic polozek do rady nejde, ale nemusi: vsechno ostatni
# bydli v PANELU, ktery se rozbali nad pruhem.
const ED_COUNT := 7
# REFERENCNI SIRKA PRO "KOMPAKTNI" TLACITKO V PANELU. Tlacitko, ktere ma
# `compact`, se neocekava na celou sirku - rozvrzeni si ho zmeri podle
# popisku (viz `editor_panel`). Vaha 1.0 znamena tuhle sirku.
const ED_COMPACT_REF := 56.0

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
# Kolik radku ma obrazovka NASTAVENI (bez tlacitka ZPET). Cislo je tady,
# protoze z nej pocita rozvrzeni, kresleni, vstup i testy - kdyby si ho
# kazdy psal sam, rozesly by se a klepnuti by nesedlo na obrazek.
const SETTINGS_ROWS := 3
# Navrat do editoru v hornim panelu hry (jen kdyz hrac hraje level z editoru).
var hud_back := Rect2()

# --- PANEL VYBRANE VEZE ---
# Vyskoci JEN kdyz je vez vybrana, takze si nesmi brat misto desce natrvalo
# (deska ma pevny pocet bunek a kazdy pixel navic ji zmensi). Kresli se na
# PROTILEHLOU stranu, nez na ktere vez stoji - hrac musi porad videt, co
# vybral, i kdyz se mu pod prstem objevi tlacitka.
const TOWER_BAR_H := 58.0
var tower_bar := Rect2()
var tower_up := Rect2()
var tower_sell := Rect2()


func tower_panel(center: Vector2) -> void:
	var h: float = maxf(MIN_TOUCH + 10.0 * ui, TOWER_BAR_H * ui)
	var bar_y: float = (view.y - h) if center.y <= view.y * 0.5 else hud_h + 1.0 * s
	tower_bar = Rect2(0.0, bar_y, view.x, h)
	var pad: float = 6.0 * ui
	var bh: float = h - pad * 2.0
	var bw: float = minf(maxf(MIN_TOUCH * 2.2, 190.0 * ui), (view.x - 4.0 * PAD * ui) * 0.5)
	var bx: float = view.x - PAD * ui * 0.5 - bw
	tower_sell = Rect2(bx, bar_y + pad, bw, bh)
	tower_up = Rect2(bx - bw - pad, bar_y + pad, bw, bh)


# --- OBCHOD S VEZEMI (stavba ve dvou krocich) ---
# Vyskoci, kdyz hrac oznaci stavebni misto - tedy JESTE PRED stavbou. Je to
# stejny pruh jako u vybrane veze a ze stejneho duvodu na PROTILEHLOU stranu:
# hrac musi porad videt misto, ktere si vybral.
const BUILD_BAR_H := 58.0
# Nejsirsi tlacitko druhu veze. Sirsi uz je jen prazdna plocha: obchod ma byt
# prehledny a tlacitka maji byt u sebe, ne rozhozena pres displej.
const KIND_BTN_W := 240.0
var build_bar := Rect2()
# TLACITKA VOLBY VEZE v obchode, vlevo, v poradi jako v nabidce mista
# (`Game.build_choices`). Pocet dava obrazovka (`build_panel`) - je to pocet
# povolenych voleb na oznacenem miste, takze u neutralni cesty je jedno
# a u elementarni dve (zivel cesty + neutralni vez).
var build_choices: Array = []
var build_ok := Rect2()
var build_cancel := Rect2()


func build_panel(center: Vector2, choices: int) -> void:
	var n: int = maxi(choices, 1)
	var h: float = maxf(MIN_TOUCH + 10.0 * ui, BUILD_BAR_H * ui)
	var bar_y: float = (view.y - h) if center.y <= view.y * 0.5 else hud_h + 1.0 * s
	build_bar = Rect2(0.0, bar_y, view.x, h)
	var pad: float = 6.0 * ui
	var bh: float = h - pad * 2.0
	# Postavit a Zrusit jsou STEJNE velka jako u panelu vybrane veze (a na
	# stejnem miste, jen na opacne strane podle toho, kde je oznacene misto):
	# obe tlacitka se mackaji prstem a hrac se mezi taby nema co ucit.
	var bw: float = minf(maxf(MIN_TOUCH * 2.2, 190.0 * ui), (view.x - 4.0 * PAD * ui) * 0.5)
	var bx: float = view.x - PAD * ui * 0.5 - bw
	build_ok = Rect2(bx, bar_y + pad, bw, bh)
	build_cancel = Rect2(bx - bw - pad, bar_y + pad, bw, bh)
	# DRUHY VEZI dostanou vsechno, co zbyde vlevo. Sirka se deli poctem druhu,
	# aby se cely obchod vesel na displej i na malem telefonu - nikdy ale
	# neklesne pod dotykove minimum, aby se druh dal vubec trefit, a nikdy
	# nevyroste pres KIND_BTN_W (u jednoho druhu by z nej bylo prazdne
	# pole pres pul displeje).
	var left: float = PAD * ui * 0.5
	var room: float = maxf(build_cancel.position.x - pad - left, MIN_TOUCH)
	var kw: float = clampf((room - pad * float(n - 1)) / float(n),
		MIN_TOUCH, KIND_BTN_W * ui)
	build_choices = []
	for i in range(n):
		build_choices.append(Rect2(left + float(i) * (kw + pad), bar_y + pad, kw, bh))
# Editor: pruh tabu dole, panel otevrene kategorie a plocha, kterou zabira.
var ed_buttons: Array = []
# OTEVRENY PANEL: seznam radku (dole -> nahoru), kazdy radek seznam polozek
# {"rect": Rect2, "item": {...}}. Prazdny = zadny panel otevreny.
var ed_panel_rows: Array = []
var ed_panel_top := 0.0
# FONT PRO MERENI SIRKY TLACITEK PANELU. Editor vi, CO v panelu je; jak je
# text siroky, vi jen obrazovka - proto si rozvrzeni bere font zvenku
# (`set_editor_font`) a meri s nim stejnym cislem jako kresleni.
var ed_font: Font = null
var editor_arena := Rect2()


# Font pro mereni popisku v panelu editoru. Vole se z obrazovky, ktera font
# vlastni; bez nej se kompaktni tlacitka vezmou v puvodni (vyssi) vaze.
func set_editor_font(f: Font) -> void:
	ed_font = f


# TLOUSTKA TAHU ODVOZENA Z MERITKA. Jan (Oct 2026): "Ať to vypadá stejně
# nehledě na rozlišení." Vsechny obrysy, kresba uzlu, mrizka a linky se proto
# kresli NASOBCEM `s` (deska), nebo `ui` (pruh, panel, menu, HUD) - ne pevnym
# poctem pixelu. Duvod je fyzikalni: displej s dvojnasobnou hustotou dostane
# dvojnasobne platno, takze pevny 2px tah je na nem relativne POLOVICNI -
# prave proto vypadala hra na velkem displeji jinak nez na malem. Podlaha
# 0.6 px je jen aby tah nezmizel na drobnem displeji.
func bl(w: float) -> float:
	return maxf(0.6, w * s)


func ul(w: float) -> float:
	return maxf(0.6, w * ui)


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

	# Arena si bere vsechno, co zbyde pod HUDem, a to CELE DO SIRKY: pole
	# (mrizka) je pres celou sirku displeje a poutnici vstupuji z jeho
	# okraje (Jan: "aby nepratele prichazeli jak kdyby zpoza displeje").
	# Zadny PAD do stran - kazdy pixel u okraje je bunka mrizky.
	arena = Rect2(0.0, hud_h + 1.0 * s,
		maxf(40.0, v.x),
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
	# Tri prepinace a ZPET pod sebou, svisle vycentrovane. Stejna logika
	# jako u menu: vyska zustava na dotykovem minimu, zmensuje se jen
	# mezera - spatne stisknutelne policko je horsi nez tesnejsi rozvrzeni.
	var sh: float = mh
	var sgap: float = 10.0 * ui
	var srows: int = SETTINGS_ROWS
	var stot: float = sh * float(srows + 1) + sgap * float(srows)
	if stot > v.y - 40.0 * ui:
		sgap = maxf(4.0, (v.y - 40.0 * ui - sh * float(srows + 1)) / float(srows))
		stot = sh * float(srows + 1) + sgap * float(srows)
	var sy0: float = (v.y - stot) * 0.5
	settings_toggle = Rect2((v.x - mw) * 0.5, sy0, mw, sh)
	settings_back = Rect2((v.x - mw) * 0.5, sy0 + (sh + sgap) * float(srows), mw, sh)

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
	# Panel se pocita zvlast (`editor_panel`) z obsahu, ktery da editor -
	# tady se jen uklidi, aby po zmene velikosti okna nezustaly stare recty.
	ed_panel_rows = []
	ed_panel_top = v.y
	var ex0: float = PAD * ui
	var ey: float = v.y - eh - 6.0 * ui
	for i in range(ED_COUNT):
		ed_buttons.append(Rect2(ex0 + float(i) * (ew + egap), ey, ew, eh))
	# ARENA EDITORU KONCI NAD PRUHEM. Pruh se kresli od `editor_bar_top()`
	# nahoru (kvuli popiskum nad tlacitky) - kdyby arena koncila az u tlacitek,
	# prekryl by pruh spodni cast mrizky, kterou hrac upravuje.
	editor_arena = Rect2(0.0, hud_h + 1.0 * s,
		maxf(40.0, v.x),
		maxf(40.0, editor_bar_top() - 2.0 * ui - hud_h - 1.0 * s))


# Horni hrana pruhu tlacitek editoru. Pocita se na JEDNOM miste: kresleni
# pruhu, arena editoru i sit, ktera pod nej nesmi kreslit, pouzivaji tuhle
# hodnotu. Kdyz si ji kazdy pocital sam, pruh prekryl kus herni plochy.
#
# NAD TALCITKY JE JEN MALE ODSTUPENI: driv tu bylo 26 px pro popiskovou
# radku (vybrany usek + hlaska), ale ta se prestehovala do HORNIHO pruhu -
# nechat tu rezervu by znamenalo brat desce 22 px a posouvat panel zbytecne
# vysoko.
func editor_bar_top() -> float:
	if ed_buttons.is_empty():
		return view.y
	return float(ed_buttons[0].position.y) - 4.0 * ui


# ROZVRZENI OTEVRENEHO PANELU. `spec` = radky ZDOLA NAHOR, kazda polozka
# {"w": vaha sirky}. Sirka se v ramci radku deli podle vah, vyska zustava na
# dotykovem minimu (stejne pravidlo jako u pruhu: zmensuje se sirka, nikdy
# vyska). Panel se kresli NAD pruhem a PREKRYVA spodni kus desky - kdyby
# arena ujizdela, mrizka by pri kazdem otevreni menu uskocila a hrac by
# ztratil misto, kde prave kreslil.
#
# DVE VECI NAVIC, obe z Janovych poznamek:
#   * "group" - polozky se stejnym neprazdnym jmenem skupiny stoji TESNE u
#     sebe (bez mezery). Hodnota a jeji "−"/"+" tak tvorí JEDEN celek:
#     Jan chtel tlacitka "malá a ideálně přímo nalepená na hodnotu".
#   * "abs_w" - pevna sirka v px (nasobi se `ui`). Tlacitka "-"/"+" maji
#     presnou sirku, takze se ridi hodnotou vedle, ne vahou celeho radku.
#
# Panel neni soucasti `editor_arena`: deska se neposouva, jen se pod panelem
# neda klepat (klepnuti na desku panel zavre).
func editor_panel(spec: Array) -> void:
	ed_panel_rows = []
	ed_panel_top = editor_bar_top()
	if spec.is_empty():
		return
	var rh: float = maxf(MIN_TOUCH, ED_BAR_H * ui)
	var gap: float = ED_GAP * ui
	var y: float = editor_bar_top() - gap - rh
	for row in spec:
		var items: Array = row
		if items.is_empty():
			continue
		# MEZERY: uvnitr skupiny zadna, mezi skupinami jedna. Pocitaji se
		# PRED delenim sirky - jinak by se sirka pocitala s jinym poctem
		# mezer, nez se pak kresli, a posledni bunka by utekla z displeje.
		var gaps: float = 0.0
		for i in range(1, items.size()):
			if not _same_group(items[i - 1], items[i]):
				gaps += gap
		var fixed: float = 0.0
		var sum: float = 0.0
		for it in items:
			if _abs_w(it) > 0.0:
				fixed += _abs_w(it)
			else:
				sum += maxf(_panel_weight(it), 0.05)
		var avail: float = maxf(view.x - 2.0 * PAD * ui - gaps - fixed, 1.0)
		var x: float = PAD * ui
		var line: Array = []
		for i in range(items.size()):
			var it: Dictionary = items[i]
			var step_gap: float = gap
			if i == 0 or _same_group(items[i - 1], it):
				step_gap = 0.0
			var bw: float = _abs_w(it)
			if bw <= 0.0:
				bw = maxf(avail * maxf(_panel_weight(it), 0.05) / maxf(sum, 0.001), 1.0)
			var r := Rect2(x + step_gap, y, bw, rh)
			line.append({"rect": r, "item": it})
			# DALSÍ POLOZKA ZACINA PRESNE NA KONCI TÉHLE, ale na konci, jak
			# ho VIDI Rect2 (float32). Kdyby se pocitala z puvodniho souctu,
			# vysla by o par tisícin px vedle a dve "nalepena" tlacitka by se
			# o ten zlomek prekryvala (test na prekryv to odhalil).
			x = r.end.x
		ed_panel_rows.append(line)
		y -= rh + gap
	if not ed_panel_rows.is_empty():
		var top_row: Array = ed_panel_rows[ed_panel_rows.size() - 1]
		var first: Dictionary = top_row[0]
		ed_panel_top = float(first["rect"].position.y) - gap


# PEVNA SIRKA POLOZKY (px, nasobeno `ui`). Nula = polozka se deli vahou.
func _abs_w(it: Dictionary) -> float:
	return maxf(float(it.get("abs_w", 0.0)), 0.0) * ui


# JSOU POLOZKY VE STEJNE SKUPINE? (hodnota a jeji "-"/"+" stoji u sebe).
func _same_group(a: Dictionary, b: Dictionary) -> bool:
	var ga: String = str(a.get("group", ""))
	return ga != "" and ga == str(b.get("group", ""))


# VAHA POLOZKY V PANELU. Vetsina polozek si nosi vahu ("w") z editoru, ale
# KOMPAKTNI tlacitko se meri podle sveho popisku: "cíl" ma byt uzke, "výhybka"
# siroke. Driv mela vsechna tlacitka v panelu stejny obdelnik, i kdyz na nich
# bylo jedno slovo (Jan: "Hodnoty ... mohou být daleko úspornější na prostor").
# Podlaha je dotykove minimum, aby se zadne tlacitko nedalo minout prstem.
#
# `pad` a `min_w` si muze polozka zuzit: tlacitko "-"/"+" je jen znak, takze
# mu staci mensi odsazeni, a hodnota ("kolo 120 s") je TEXT - ta zadne
# dotykove minimum nepotrebuje, jen aby se vesla.
func _panel_weight(it: Dictionary) -> float:
	if not bool(it.get("compact", false)):
		return float(it.get("w", 1.0))
	var w: float = float(it.get("w", 1.0))
	if ed_font != null:
		var px: int = font(13.0)
		var need: float = ed_font.get_string_size(str(it.get("label", "")),
			HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + float(it.get("pad", 26.0))
		w = maxf(need, float(it.get("min_w", MIN_TOUCH + 6.0))) / ED_COMPACT_REF
	return w


# VSECHNA KLEPATKA EDITORU: pruh + otevreny panel. Jedno misto pro kontrolu,
# ze se tlacitka neprekryvaji a ze se vejdou na displej.
func all_editor_buttons() -> Array:
	var out: Array = []
	for r in ed_buttons:
		out.append(r)
	for row in ed_panel_rows:
		for e in row:
			# PRAZDNE MISTO V MRIZCE neni tlacitko - do seznamu klepatek
			# nepatri (jinak by test hlasil prekryv s necim, na co se neda
			# klepnout).
			if str(e["item"].get("kind", "")) == "spacer":
				continue
			out.append(e["rect"])
	return out


# VELIKOST PISMA POPISKU V PRUHU EDITORU. Tlacitek je sedm, ale popisek
# "nástroje" je nejdelsi - kdyby se pismo zmensovat nemohlo, prisel by hrac
# o popisek (a tlacitko bez popisku je horsi nez zadne). Pocita se na JEDNOM
# miste: kresleni i test meri stejnym cislem, jinak by test meril neco
# jineho, nez hrac vidi.
func ed_label_px(labels: Array, f: Font) -> int:
	if ed_buttons.is_empty():
		return 13
	return label_px_for(labels, f, ed_buttons[0].size.x - 4.0)


# VELIKOST PISMA V JEDNOM RADKU PANELU. Kazdy popisek se meri proti SVEMU
# tlacitku (driv se meril proti nejuzsimu v radku, coz po zavedeni kompaktnich
# tlacitek "−"/"+" srazilo pismo i dlouhemu textu, ktery ma mista dost).
func panel_label_px(row: Array, f: Font) -> int:
	for px in range(13, 9, -1):
		var fpx: int = font(float(px))
		var fits := true
		for e in row:
			# Prazdne misto v mrizce nema co merit.
			if str(e["item"].get("kind", "")) == "spacer":
				continue
			var room: float = float(e["rect"].size.x) - 4.0
			var txt: String = str(e["item"].get("label", ""))
			if f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fpx).x > room:
				fits = false
				break
		if fits:
			return px
	return 10


func label_px_for(labels: Array, f: Font, room: float) -> int:
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


func menu_rect(i: int) -> Rect2:
	var r: Rect2 = menu_buttons[i]
	return r


# HERNI DESKA JE BEZ OVLADANI. Vraci prazdny seznam a testy na tom trvaji:
# jedina interakce na desce je klepnuti na usek nebo na misto na bonus,
# a to zadne tlacitko nepotrebuje. Kdyby tu nejake pribylo, ubralo by misto
# hraci plose - presne to se stalo s pruhem, ktery jsme odstranili.
func all_buttons() -> Array:
	return []


# Tlacitka EDITORU. Nejsou na herni desce - ta je porad bez ovladani; editor
# je jina obrazovka se svym vlastnim pruhem dole.
func editor_bar_buttons() -> Array:
	var out: Array = []
	for r in ed_buttons:
		out.append(r)
	return out


# VELIKOST PISMA POPISKU V PRUHU EDITORU je jen JEDNA (`ed_label_px` vyse):
# druhy vypocet by se s nim rozešel a test by meril neco jineho, nez hrac vidi.


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


# Vsechny dotykove cile NASTAVENI: vsechny radky prepinacu a ZPET.
func all_settings_buttons() -> Array:
	var out: Array = []
	var sh: float = settings_toggle.size.y
	var gap: float = row_gap()
	for i in range(SETTINGS_ROWS):
		out.append(Rect2(settings_toggle.position.x,
			settings_toggle.position.y + float(i) * (sh + gap), settings_toggle.size.x, sh))
	out.append(settings_back)
	return out


# Mezera mezi radky nastaveni. Pocita se z rozvrzeni, aby kresleni,
# vstup i testy pouzivaly PRESNE stejnou hodnotu - kdyby si ji kazdy
# pocital sam, rozesly by se a klikacka by nesedela na obrazek.
func row_gap() -> float:
	return (settings_back.position.y - settings_toggle.position.y
		- settings_toggle.size.y * float(SETTINGS_ROWS)) / float(SETTINGS_ROWS)


# --- OBSAH RADKU NASTAVENI ---
# Jedno misto, odkud si kresleni I TEST berou obdelniky radku: popisek vlevo,
# hodnota pred zaskrtravatkem a zaskrtravatko u praveho okraje. Mezi hodnotou
# a zaskrtravatkem je VZDY mezera - presne to se rozbilo, kdyz se hodnota
# zarovnavala k pravemu okraji radku a zaskrtravatko stalo 108*ui od nej:
# u "ZAPNUTO" zbylo 69 px, text se ramecku dotýkal a popisek "Rozlišení"
# navic utece z tlacitka. Kdo meni rozvrzeni, meni TADY.
const SET_PAD := 18.0
const SET_CHECK := 22.0
const SET_GAP := 16.0
# Kde zacina hodnota: vlevo od ni je popisek, vpravo zaskrtravatko.
const SET_VAL_FRAC := 0.46


func settings_row(i: int) -> Rect2:
	var gap: float = row_gap()
	return Rect2(settings_toggle.position.x,
		settings_toggle.position.y + float(i) * (settings_toggle.size.y + gap),
		settings_toggle.size.x, settings_toggle.size.y)


# ZASKRTRAVATKO u praveho okraje radku, velikost z meritka (jinak by na
# velkem displeji z ramecku vylezla fajfka kreslena pevnymi pixely).
func settings_check(i: int) -> Rect2:
	var row: Rect2 = settings_row(i)
	var box: float = SET_CHECK * ui
	return Rect2(row.end.x - SET_PAD * ui - box, row.get_center().y - box * 0.5, box, box)


# HODNOTA: konci PRED zaskrtravatkem, s mezerou SET_GAP.
func settings_value_box(i: int) -> Rect2:
	var row: Rect2 = settings_row(i)
	var chk: Rect2 = settings_check(i)
	var x: float = row.position.x + row.size.x * SET_VAL_FRAC
	return Rect2(x, row.position.y,
		maxf(chk.position.x - SET_GAP * ui - x, 24.0), row.size.y)


# POPISEK: vlevo, oriznuty na misto pred hodnotou.
func settings_label_box(i: int) -> Rect2:
	var row: Rect2 = settings_row(i)
	var val: Rect2 = settings_value_box(i)
	var x: float = row.position.x + SET_PAD * ui
	return Rect2(x, row.position.y,
		maxf(val.position.x - SET_GAP * ui - x, 24.0), row.size.y)


func overlaps_with(rect: Rect2, margin: float = 0.0) -> bool:
	for b in all_buttons():
		var r: Rect2 = b
		if r.grow(margin).intersects(rect):
			return true
	return false


func font(px: float) -> int:
	return int(roundf(px * ui))
