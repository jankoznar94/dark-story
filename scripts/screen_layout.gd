class_name ScreenLayout
extends RefCounted

# ROZVRZENI. Vsechno, co se pocita z velikosti okna, se pocita TADY - hra
# dostava jen hotove cislo (`Game.set_field`).
#
# Hra je na VYSKU a ma CTYRI PRUHY: nahore stav (level, vlna, zivoty, zlato),
# uprostred kruhova plocha, pod ni PALETA BAREV a uplne dole PANEL S UPGRADY.
# Paleta i panel stoji MIMO hraci plochu, takze se hrac pri volbe barvy ani pri
# nakupu neprekryva desku - plocha konci nad paletou (`pal_top`).
# Panel s upgrady je v bitve otevreny PORAD (viz `layout_shop`).
#
# SPAWNOVACI KRUH JE VETSI NEZ DISPLEJ a NEMALUJE SE - hrac vidi jen kruh
# dostrelu, jehoz barvu urcuje barva veze.
#
# PLOCHA A MERITKO KRESLENI JSOU DVE CISLA: `unit_r` = meritko kresleni (vez,
# poutnik, tecka) a `field_r` = spawnovaci kruh. Zmensuje se JEN meritko
# (`UNIT_SHRINK`) - plocha tim opticky naroste, ale rozvrzeni se nemeni.
#
# PANELY S KATEGORIEMI (bitva i menu) MAJI JEDEN PREDEK: `layout_grid`. Taby
# kategorie i bunky upgradu se pocitaji na jednom miste, takze se bitva a menu
# nemohou rozejit.

const BAR_FRAC := 0.075
const BAR_MIN := 44.0
# PRUH PALETY JE O NECO VYSSI NEZ DRIV (Jan, Oct 2026: "Trochu zvětšíme barevná
# tlačítka palety."): tlacitko je kruh, takže ho zvetsi jen vyska pruhu a to,
# kolik z nej si vezme - sirka je dana poctem barev.
const PAL_FRAC := 0.125
const PAL_MIN := 72.0
const MARGIN_FRAC := 0.03
# ZMENSENI KRESLENI (Jan: "A vše uděláme o něco menší ... Musíme opticky
# zvětšit celou tuhle plochu"): plati pro vez, poutnika i tecku strely.
const UNIT_SHRINK := 0.85
const BTN_MIN := 44.0
const PAL_BTN_MAX := 150.0
const MENU_BTN_MIN := 56.0
const MENU_BTN_MAX := 120.0
# PAUZA / POKRAČOVAT: sirka se MERI z delsiho popisku, aby tlacitko pri
# prepnuti neměnilo velikost (a aby se na uzkem displeji veslo).
const PAUSE_BTN_MIN := 56.0
const PAUSE_BTN_MAX := 132.0
# TAB KATEGORIE A BUNKA UPGRADU. Tab musi jit zmacknout prstem (52 px) a IKONA
# KATEGORIE V NEM MUSI BYT VIDET (Jan, Oct 2026: "Ikony tlačítek kategorií
# upgradu jsou stále příliš malé.") - tab je proto jeste vyssi nez v prvnim
# kole a ikona bere 90 % jeho vysky.
const TAB_MIN := 52.0
# MRIZKA UPGRADU: DVE BUNKY NA RADEK a kazda bunka je CELE TLACITKO - nazev,
# aktualni hodnota a cena jsou UVNITR (Jan, Oct 2026: "Bude to grid. Dvě
# obdélníková tlačítka na řádek. Každé tlačítko obsahuje název, cenu a aktuální
# hodnotu. Nechci z upgradů dělat tabulky s tlačítky."). Vyska bunky se pocita
# z pisma (musi se do ni vejit dva radky textu) a je shora omezena, aby na
# velkem displeji nevznikly prazdne plochy.
const GRID_COLS := 2
# BUNKA UPGRADU MA DVA RADKY TEXTU: nahore nazev, pod nim HODNOTA a hned vedle
# (u praveho okraje) CENA (Jan, Oct 2026: "Hodnota a cena budou na stejném
# řádku"). Vyska se proto pocita jako DVA radky pisma, ne tri - bunka je o tretinu
# nizsi a hraci plose to vraci desitky pixelu.
const CELL_LINES := 2.0
const CELL_LINE_FACTOR := 1.6
const CELL_MIN_H := 48.0
const CELL_MAX_H := 96.0
# TLACITKA UPGRADU V LEVELU JSOU TRVALE NA OBRAZOVCE (Jan, Oct 2026: "Budou tam
# totiz permanentne") - kazdy pixel jejich vysky ubere hraci plose, proto jsou
# v bitve O NECO NIZSI nez stejna mrizka v menu. Cislo je podil, ne pixely:
# na kazdem displeji tak zustane zmenseni stejne videt.
const CELL_LEVEL_SHRINK := 0.88

## VYBER LEVELU (Jan, Oct 2026: "dáme možnost si levely ručně vybírat. Abych se
## mohl vrátit i k hotovým."). Dlazdice s cislem levelu ve mrizce 4x3 na
## strance; strankuje se jen tehdy, kdyz je odemcenych levelu vic. Urovne je
## nekonecne, takze bez stranek by seznam nemel kam rust.
const LVL_COLS := 4
const LVL_ROWS := 3
const LVL_PER_PAGE := 12

var view: Vector2 = Vector2.ZERO
var bar_h: float = 0.0
var pal_h: float = 0.0
var arena: Rect2 = Rect2()
var center: Vector2 = Vector2.ZERO
var field_r: float = 0.0
var unit_r: float = 0.0
var tower_r: float = 0.0
var pilgrim_r: float = 0.0
# HORNI PRUH: stavovy text a MENU (odchod). Tlacitko UPGRADY zmizelo - panel
# s nakupem je v bitve TRVALE OTEVRENY, takze nebylo co prepinat.
var hud_menu: Rect2 = Rect2()
# PAUZA / POKRAČOVAT - druhe tlacitko pruhu, VLEVO od MENU (odchod stoji
# na kraji, kde ho hrac nehleda omylem). Je to CTVEREC s IKONOU.
var hud_pause: Rect2 = Rect2()
# ZRYCHLENI HRY - treti tlacitko pruhu, vlevo od pauzy. Je VIDET jen kdyz si
# hrac koupil special `gs` (`speed_visible`); jinak je prazdny obdelnik a jeho
# misto dostane stavovy text.
var hud_speed: Rect2 = Rect2()
var speed_visible: bool = false
var bar_text_w: float = 0.0
var font_px: int = 16
# DVOURADKOVY STAV: prvni radek je level/vlna, druhy zivoty a zlato. Dvakrat
# delsi text na jednom radku by se musel zmensit tak, ze by ho hrac necetl.
const HUD_LINE1_FMT := "Level %d · vlna %d/%d"
const HUD_LINE2_FMT := "Životy %d/%d · zlato %d"
var hud_font: Font = ThemeDB.fallback_font
# PANEL S NAKUPEM (bitva): tab kategorii + MRIZKA BUNEK (2 na radek), kde je
# kazda bunka CELE TLACITKO s nazvem, hodnotou a cenou. V bitve stoji U SPODNIHO
# OKRAJE a je otevreny porad (`layout_shop`).
var shop_tab_count: int = 3
var shop_cell_count: int = 4
var shop_panel: Rect2 = Rect2()
var shop_tabs: Array = []
var shop_tab_icons: Array = []
var shop_cells: Array = []
# HORNI HRANA SPODNIHO PRUHU S BARVAMI. Neni to `view.y - pal_h` jako driv:
# paleta je v bitve NAD panelem s upgrady, takze ji posouva panel.
var pal_top: float = 0.0
# MENU - OBRAZOVKA UPRAVY: stejna mrizka, ale pres cely displej a se SPECIALEM.
var upg_panel: Rect2 = Rect2()
var upg_tabs: Array = []
var upg_tab_icons: Array = []
var upg_cell_count: int = 4
var upg_cells: Array = []
var upg_back: Rect2 = Rect2()
var upg_note_y: float = 0.0
var pal_rects: Array = []
# MENU
var menu_rects: Array = []
var menu_title_y: float = 0.0
var menu_note_y: float = 0.0
var menu_title_px: int = 30
var menu_item_px: int = 18
var menu_sub_px: int = 12
# VYBER LEVELU: dlazdice s cisly levelu, sipky na stranky a ZPET. Pocet
# odemcenych levelu a stranka se sem NASTAVUJI (`set_levels`) - rozvrzeni si je
# jinak nesmi vymyslet, jinak by klepnuti pocitalo s jinym poctem dlazdic, nez
# hrac vidi.
var lvl_tiles: Array = []
var lvl_prev: Rect2 = Rect2()
var lvl_next: Rect2 = Rect2()
var lvl_back: Rect2 = Rect2()
var lvl_unlocked: int = 1
var lvl_page: int = 0
var lvl_pages: int = 1
var lvl_title_y: float = 0.0
var lvl_note_y: float = 0.0
# NADPIS VYBERU JE MENSI NEZ NADPIS MENU. Na sirokem displeji je pismo menu
# obri (105 px), a tolik mista si obrazovka s mrizkou nemuze dovolit - dlazdice
# by spadly pod 44 px. Je to vlastni cislo, aby ho kresleni cetlo odtud.
var lvl_title_px: int = 30
var menu_state_y: float = 0.0
# NASTAVENI
var settings_row: Rect2 = Rect2()
var settings_back: Rect2 = Rect2()
# DIALOG (ukoncit partii / level vyhran / konec). Jedno misto pro vsechny tri:
# kdo by si psal vlastni obdelniky, rozejde se s testy i s kreslenim.
var dlg_box: Rect2 = Rect2()
var dlg_a: Rect2 = Rect2()
var dlg_b: Rect2 = Rect2()


# POZOR: dokud prohlizec neposle prvni zmenu, je velikost okna NULOVA.
# Pocitani se zapornou sirkou znamena chyby v logu a tlacitka, ktera nejdou
# zmacknout - proto se na neplatnou velikost odpovida prazdnymi obdelniky.
func update(v: Vector2) -> void:
	view = v
	if v.x < 1.0 or v.y < 1.0:
		bar_h = 0.0
		pal_h = 0.0
		arena = Rect2()
		center = Vector2.ZERO
		field_r = 0.0
		unit_r = 0.0
		tower_r = 0.0
		pilgrim_r = 0.0
		hud_menu = Rect2()
		hud_pause = Rect2()
		hud_speed = Rect2()
		bar_text_w = 0.0
		shop_panel = Rect2()
		shop_tabs = []
		shop_tab_icons = []
		shop_cells = []
		pal_top = 0.0
		upg_panel = Rect2()
		upg_tabs = []
		upg_tab_icons = []
		upg_cells = []
		upg_back = Rect2()
		lvl_tiles = []
		lvl_prev = Rect2()
		lvl_next = Rect2()
		lvl_back = Rect2()
		pal_rects = []
		menu_rects = []
		settings_row = Rect2()
		settings_back = Rect2()
		dlg_box = Rect2()
		dlg_a = Rect2()
		dlg_b = Rect2()
		return
	bar_h = maxf(BAR_MIN, v.y * BAR_FRAC)
	pal_h = maxf(PAL_MIN, v.y * PAL_FRAC)
	font_px = int(clampf(minf(v.x, v.y) * 0.046, 14.0, 34.0))
	_hud()
	# PORADI JE ZAVAZNE: panel s upgrady stoji v bitve U SPODNIHO OKRAJE a nad
	# nim je paleta, takze se nejdriv spocte panel, z nej horni hrana palety
	# a teprve z ni herni plocha. Kdo spocte plochu driv, necha poutniky chodit
	# pod panel (a hrac je nevidi).
	layout_shop()
	arena = Rect2(0.0, bar_h, v.x, maxf(1.0, pal_top - bar_h))
	var short_side: float = minf(arena.size.x, arena.size.y)
	unit_r = maxf(20.0, (short_side * 0.5 - short_side * MARGIN_FRAC) * UNIT_SHRINK)
	field_r = maxf(unit_r, arena.size.y * 0.5)
	center =arena.position + arena.size * 0.5
	tower_r = unit_r * 0.12
	pilgrim_r = unit_r * 0.05
	# DIALOG SE POCITA ZVLAST (`dialog_panel`): pocet odpovedi se lisi podle
	# toho, ktery dialog je otevreny, a to vi jen obrazovka. Kdo ho spocte tady
	# napevno, pripravi hrace o jednu odpoved.
	layout_upgrades()
	layout_palette(pal_rects.size())
	# MENU SE POCITA PRED VYBEREM LEVELU: nadpis obrazovky levelu pouziva stejne
	# pismo jako nadpis menu, takze musi byt hotove prvni.
	layout_menu(Menu.MENU_ITEMS.size())
	layout_levels()
	layout_settings()


# SIRKA TEXTU VE SKUTECNEM FONTU. Kdo meri jinak nez kresli, meri neco jineho
# nez hrac vidi - proto je to tady jedno misto pro rozvrzeni i pro testy.
func measure_px(s: String, px: int) -> float:
	return hud_font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x


func fit_px(s: String, max_w: float, max_px: int, min_px: int = 10) -> int:
	if max_w <= 1.0:
		return min_px
	var px: int = max_px
	while px > min_px and measure_px(s, px) > max_w:
		px -= 1
	return px


# HORNI PRUH: [stavovy text] [ZRYCHLENI] [PAUZA] [MENU]. Sirka tlacitek se MERI
# (stejne jako driv u "Vylepsit"), text dostane zbytek - jinak by se na uzkem
# displeji utnul.
#
# PAUZA JE IKONA, NE TEXT (Jan, Oct 2026: "Tlačítko Pause nebude mít text ale
# velkou ikonu."). Nemerí se tedy z popisku: je to CTVEREC z vysky tlacitka,
# takze je stejne velka jako ostatni a ikona se do ni vejde.
#
# ZRYCHLENI HRY (`hud_speed`) je v pruhu JEN kdyz si hrac koupil special -
# dokud ho nema, neni co prepinat a prazdne tlacitko by bylo lez. Jeho misto
# dostane stavovy text (`bar_text_w`).
func _hud() -> void:
	var pad: float = maxf(4.0, bar_h * 0.10)
	var h: float = maxf(30.0, bar_h - 2.0 * pad)
	var mw: float = clampf(measure_px("MENU", font_px) + 12.0, MENU_BTN_MIN, MENU_BTN_MAX)
	hud_menu = Rect2(view.x - mw - pad, pad, mw, h)
	var pw: float = maxf(BTN_MIN, h)
	hud_pause = Rect2(hud_menu.position.x - pad - pw, pad, pw, h)
	var left: float = hud_pause.position.x
	if speed_visible:
		var sw: float = clampf(measure_px("2,5x", font_px) + 16.0, PAUSE_BTN_MIN, PAUSE_BTN_MAX)
		hud_speed = Rect2(left - pad - sw, pad, sw, h)
		left = hud_speed.position.x
	else:
		hud_speed = Rect2()
	bar_text_w = maxf(0.0, left - 2.0 * pad)


# --------------------------------------------------------------- PANEL S MRIZKOU

# VYSKA BUNKY UPGRADU. Uvnitr jsou DVA radky textu (nazev a pod nim hodnota
# s cenou), takze se pocita z pisma; shora je omezena, aby na velkem displeji
# z bunek nebyly prazdne plochy. `shrink` je zmenseni pro mrizku V BITVE (viz
# CELL_LEVEL_SHRINK) a pocita se AZ ZA stropem - kde by se jinak na velkem
# displeji obe mrizky zastavily na stejnem cisle a zmenseni by v levelu zmizelo.
func grid_cell_h(shrink: float = 1.0) -> float:
	var h: float = clampf(float(font_px) * CELL_LINES * CELL_LINE_FACTOR,
		CELL_MIN_H, CELL_MAX_H)
	return maxf(CELL_MIN_H, h * shrink)


func grid_rows(cell_count: int) -> int:
	return int(ceil(float(maxi(1, cell_count)) / float(GRID_COLS)))


# VYSKA TABU KATEGORIE. Je to NOSNIK IKONY (ikona bere 90 % z ni), takze se
# pocita z pisma a je vyssi nez driv - vetsi ikona je to, co Jan chtel videt
# ("Ikony tlačítek kategorií upgradu jsou stále příliš malé.").
func card_tabs_h() -> float:
	return maxf(60.0, minf(84.0, float(font_px) * 4.0))


# VELIKOST PANELU PRO DANY POCET UPGRADU. Pocita se Z MRIZKY, ne naopak -
# jindy by panel zbyl prazdny (nebo by bunky pretekly z ramecku).
func card_panel_size(w: float, cell_count: int, shrink: float = 1.0) -> Vector2:
	var pad: float = maxf(8.0, w * 0.022)
	var gap: float = maxf(6.0, w * 0.016)
	var rows: int = grid_rows(cell_count)
	var h: float = 2.0 * pad + card_tabs_h() + maxf(4.0, pad * 0.5)
	h += float(rows) * grid_cell_h(shrink) + float(rows - 1) * gap
	return Vector2(w, h)


# MRIZKA UPGRADU: taby nahore, pod nimi DVE BUNKY NA RADEK a kazda bunka je
# CELE TLACITKO. Vraci {tabs, cells} - jedno misto pro bitvu i pro menu, takze
# se oba panely nemohou rozejit. Poradi bunek je PO RADCICH, takze index bunky
# = index parametru v kategorii (na tom stoji klepnuti).
func layout_grid(r: Rect2, tab_count: int, cell_count: int, shrink: float = 1.0) -> Dictionary:
	var out: Dictionary = {"tabs": [], "cells": []}
	if r.size.x < 1.0 or r.size.y < 1.0 or tab_count <= 0 or cell_count <= 0:
		return out
	var pad: float = maxf(8.0, r.size.x * 0.022)
	var gap: float = maxf(6.0, r.size.x * 0.016)
	# TABY MAJI PRIORITU: kdyz je panel nizky, zmensi se bunka, ne tab. Podil je
	# 0,36 (driv 0,30) - tab je nosnik IKONY, ktera ma byt videt, a bunky maji
	# vlastni podlahu (`CELL_MIN_H`), takze se nikdy nezmensi pod ni.
	var tabs_h: float = minf(card_tabs_h(), maxf(TAB_MIN, r.size.y * 0.36))
	var inner: float = r.size.x - 2.0 * pad
	var tw: float = maxf(BTN_MIN, (inner - gap * float(tab_count - 1)) / float(tab_count))
	var t: float = r.position.y + pad
	var tabs: Array = []
	var icons: Array = []
	for i in range(tab_count):
		var tr := Rect2(r.position.x + pad + (tw + gap) * float(i), t, tw, tabs_h)
		tabs.append(tr)
		icons.append(tab_icon_rect(tr))
	var rows: int = grid_rows(cell_count)
	var rows_top: float = t + tabs_h + maxf(4.0, pad * 0.5)
	var room: float = r.end.y - pad - rows_top
	var rh: float = maxf(1.0, minf(grid_cell_h(shrink), (room - gap * float(rows - 1)) / float(rows)))
	var cw: float = (inner - gap * float(GRID_COLS - 1)) / float(GRID_COLS)
	var cells: Array = []
	for i in range(cell_count):
		var row: int = i / GRID_COLS
		var col: int = i % GRID_COLS
		cells.append(Rect2(r.position.x + pad + (cw + gap) * float(col),
			rows_top + (rh + gap) * float(row), cw, rh))
	out["tabs"] = tabs
	out["tab_icons"] = icons
	out["cells"] = cells
	return out


# IKONA KATEGORIE VE TABU. Ctverec UPROSTRED tabu - ikony jsou ctvercove masky
# (bile na pruhlednem), takze se do nej vejdou bez orezani a maji stejnou
# velikost ve vsech tabech. Text popisku se do tabu uz nekresli.
#
# IKONA ZABIRA 90 % VYSKY TABU (Jan, Oct 2026: "Ikony tlačítek kategorií
# upgradu jsou stále příliš malé."): driv 66 %, pak 84 % - tab je nosnik ikony
# a hrac ji ma cist, ne hadat. Sirku orezava jen okraj tabu, aby ikona nikdy
# neprelezla ramecek.
func tab_icon_rect(tr: Rect2) -> Rect2:
	var side: float = minf(maxf(18.0, tr.size.y * 0.90), maxf(18.0, tr.size.x - 8.0))
	return Rect2(tr.position + (tr.size - Vector2(side, side)) * 0.5, Vector2(side, side))


# PANEL V BITVE. JE OTEVRENY PORAD (Jan, Oct 2026: "Budou tam [tlacitka] totiz
# permanentne") a stoji U SPODNIHO OKRAJE; barevna paleta je NAD NIM (Jan,
# Oct 2026: "barevna paleta bude nad upgrady"), takze hrac vidi barvy i nakup
# zaroven. Hra se pod panelem NEZASTAVUJE (`is_halted`) - hrac nakupuje za
# pochodu a poutnici nikdy nechodi POD panelem: herni plocha konci nad paletou.
func set_shop_shape(tabs: int, cells: int) -> void:
	shop_tab_count = maxi(1, tabs)
	shop_cell_count = maxi(1, cells)
	if view.x >= 1.0 and view.y >= 1.0:
		update(view)


# MENU - UPRAVY. Pocet bunek se meni s kategorii (4, 3, 3, 4), takze se rozvrzeni
# musi prelozit pri kazdem prepnuti tabu - jinak by klepnuti na bunku pocitalo
# s jinym poctem, nez je radku.
func set_upg_shape(cells: int) -> void:
	upg_cell_count = maxi(1, cells)
	if view.x >= 1.0 and view.y >= 1.0:
		update(view)


# ZRYCHLENI HRY: ma se v pruhu ukazat tlacitko? Vi to jen obrazovka (podle
# toho, jestli si hrac koupil special), ale MISTO v pruhu pocita rozvrzeni -
# tak si to musi predat. Kdyby si to obrazovka kreslila po svem, sedelo by
# tlacitko jinde, nez se klika.
func set_speed_visible(on: bool) -> void:
	if speed_visible == on:
		return
	speed_visible = on
	if view.x >= 1.0 and view.y >= 1.0:
		update(view)


func layout_shop() -> void:
	if view.x < 1.0 or view.y < 1.0:
		shop_panel = Rect2()
		shop_tabs = []
		shop_cells = []
		pal_top = 0.0
		return
	var gap: float = maxf(8.0, view.y * 0.012)
	var side: float = maxf(6.0, view.x * 0.02)
	var w: float = view.x - 2.0 * side
	var h: float = card_panel_size(w, shop_cell_count, CELL_LEVEL_SHRINK).y
	shop_panel = Rect2(side, maxf(bar_h, view.y - gap - h), w, h)
	var card: Dictionary = layout_grid(shop_panel, shop_tab_count, shop_cell_count, CELL_LEVEL_SHRINK)
	shop_tabs = card["tabs"]
	shop_tab_icons = card["tab_icons"]
	shop_cells = card["cells"]
	# PALETA SE VEJDE TESNE NAD PANEL. Kdyby zustala dole, panel by ji zakryl
	# a hrac by prisel o jedinou cestu, jak prehodit barvu veze.
	pal_top = maxf(bar_h, shop_panel.position.y - gap - pal_h)


# OBRAZOVKA UPRAVY V MENU: stejna mrizka, ale uprostred displeje mezi nadpisem
# a tlacitkem ZPET. Panel dostane jen tolik mista, kolik mrizka potrebuje,
# takze na vysokem displeji nezustane velky prazdny ramecek.
func layout_upgrades() -> void:
	if view.x < 1.0 or view.y < 1.0:
		upg_panel = Rect2()
		upg_tabs = []
		upg_cells = []
		upg_back = Rect2()
		return
	var side: float = maxf(10.0, view.x * 0.05)
	var top_limit: float = maxf(46.0, view.y * 0.10)
	var btn: float = minf(MENU_BTN_MAX, maxf(MENU_BTN_MIN, view.y * 0.09))
	var bottom: float = view.y - btn - maxf(26.0, view.y * 0.05)
	var w: float = view.x - 2.0 * side
	var avail: float = maxf(1.0, bottom - top_limit)
	var h: float = minf(card_panel_size(w, upg_cell_count).y, avail)
	upg_panel = Rect2(side, top_limit + (avail - h) * 0.5, w, h)
	var card: Dictionary = layout_grid(upg_panel, Upgrades.CATEGORIES.size(), upg_cell_count)
	upg_tabs = card["tabs"]
	upg_tab_icons = card["tab_icons"]
	upg_cells = card["cells"]
	upg_back = Rect2((view.x - minf(440.0, view.x * 0.86)) * 0.5, bottom + 6.0,
		minf(440.0, view.x * 0.86), btn)
	upg_note_y = upg_panel.position.y - float(font_px) * 1.7


# DIALOG. Jedno misto pro "opravdu ukoncit", "level vyhran" i "konec" - kdo by
# si psal vlastni obdelniky, rozejde se s kreslenim i s testy.
func dialog_panel(two_buttons: bool) -> void:
	if view.x < 1.0 or view.y < 1.0:
		dlg_box = Rect2()
		dlg_a = Rect2()
		dlg_b = Rect2()
		return
	var bw: float = minf(520.0, view.x * 0.90)
	var bh: float = maxf(150.0, view.y * 0.30)
	dlg_box = Rect2((view.x - bw) * 0.5, (view.y - bh) * 0.5, bw, bh)
	var pad: float = maxf(10.0, bw * 0.03)
	var btn_h: float = maxf(BTN_MIN, bh * 0.28)
	if two_buttons:
		var btn_w: float = (bw - pad * 3.0) * 0.5
		dlg_a = Rect2(dlg_box.position.x + pad, dlg_box.end.y - pad - btn_h, btn_w, btn_h)
		dlg_b = Rect2(dlg_a.end.x + pad, dlg_a.position.y, btn_w, btn_h)
	else:
		var w1: float = minf(bw - 2.0 * pad, 320.0)
		dlg_a = Rect2(dlg_box.position.x + (bw - w1) * 0.5,
			dlg_box.end.y - pad - btn_h, w1, btn_h)
		dlg_b = Rect2()


# TLACITKA PALETY. Pocet barev se v prubehu hry meni (barvy pribyvaji), takze
# se rozvrzeni pocita z poctu, ktery dostane - ne z konstanty. Tlacitko je
# KRUH: kresli se do CTVERCE, proto ctvercove bunky (v obdelniku by z puntiku
# byl oval).
#
# VETSÍ NEZ DRIV (Jan, Oct 2026: "Trochu zvětšíme barevná tlačítka palety.").
# Kruh roste jen s VYSKOU pruhu, takze se bere vic z pruhu (vnitrni odsazeni
# 5 %) a mene z okraju - na pet barev je sirka to, co ho drzi, takze se
# zmensily mezery a krajovy odstup.
func layout_palette(count: int) -> Array:
	if count <= 0 or view.x < 1.0:
		pal_rects = []
		return pal_rects
	var pad: float = maxf(6.0, view.x * 0.015)
	var gap: float = maxf(8.0, view.x * 0.020)
	var room_w: float = (view.x - 2.0 * pad - gap * float(count - 1)) / float(count)
	var room_h: float = pal_h - 2.0 * maxf(4.0, pal_h * 0.05)
	var side: float = minf(clampf(room_w, BTN_MIN, PAL_BTN_MAX), maxf(BTN_MIN, room_h))
	var total: float = side * float(count) + gap * float(count - 1)
	var x: float = (view.x - total) * 0.5
	# PALETA STOJI VE SVEM PRUHU - v bitve je to pruh NAD panelem s upgrady
	# (`pal_top`), jinde ji nikdo nekresli.
	var y: float = pal_top + (pal_h - side) * 0.5
	pal_rects = []
	for i in range(count):
		pal_rects.append(Rect2(x + (side + gap) * float(i), y, side, side))
	return pal_rects


# TLACITKA MENU. Pocet vi jen ten, kdo je kresli (Menu) - stejne jako paleta.
func layout_menu(count: int) -> Array:
	if count <= 0 or view.x < 1.0 or view.y < 1.0:
		menu_rects = []
		return menu_rects
	var w: float = clampf(view.x * 0.78, 260.0, 560.0)
	# PET POLOZEK NA MALEM DISPLEJI: nadpis, staz profilu, hlaska a otisk
	# buildu potrebuji sve misto, takze se tlacitka zmensi - ne oni. Kdo
	# zmensi nadpis pod 30 px, tomu hrac neprecte, jak se hra jmenuje.
	var per: float = view.y * (0.105 if count > 4 else 0.13)
	var h: float = minf(MENU_BTN_MAX, maxf(MENU_BTN_MIN, per))
	var gap: float = maxf(14.0, view.y * 0.03)
	# NADPIS SE POCITA Z DISPLEJE, ne z toho, co zbylo pod nim.
	menu_title_px = clampi(int(float(font_px) * 3.2), 30, 110)
	menu_item_px = clampi(int(minf(float(font_px) * 1.65, float(menu_title_px) * 0.62)), 18, 56)
	var sub_max: int = int(minf(float(font_px) * 1.05, float(menu_item_px) * 0.72))
	menu_sub_px = clampi(fit_px(Menu.SUBTITLE, view.x * 0.92, sub_max, 12), 12, 32)
	# MISTO NAD TLACITKY (nadpis, podtitulek, stav profilu) a POD NIMI (hlaska
	# o aktualizaci, otisk buildu).
	var above: float = float(menu_title_px) * 1.7 + float(menu_sub_px) * 2.9
	var below: float = float(menu_sub_px) * 3.2
	var room: float = maxf(float(count) * MENU_BTN_MIN, view.y - above - below)
	if h * float(count) + gap * float(count - 1) > room:
		h = maxf(MENU_BTN_MIN * 0.8, (room - gap * float(count - 1)) / float(count))
		room = maxf(float(count) * MENU_BTN_MIN, view.y - above - below)
		if h * float(count) + gap * float(count - 1) > room:
			gap = maxf(4.0, (room - h * float(count)) / float(count - 1))
	var total: float = h * float(count) + gap * float(count - 1)
	# TITUL SE MUSI VEJIT NAD TLACITKA a stav profilu pod nej; kdyz se to
	# nevejde na stred, tlacitka se posunou dolu (nadpis ma vzdy prednost).
	var y0: float = maxf(above, minf((view.y - total) * 0.5 + view.y * 0.05, view.y - below - total))
	var x: float = (view.x - w) * 0.5
	menu_rects = []
	for i in range(count):
		menu_rects.append(Rect2(x, y0 + (h + gap) * float(i), w, h))
	menu_title_y = maxf(float(menu_title_px) * 1.2,
		y0 - float(menu_title_px) * 1.7 - float(menu_sub_px))
	# STAV PROFILU PATRI POD PODTITULEK, ne pod tlacitka: na pet polozek uz
	# dole neni misto a radek "Level 4 · body 120" se tam prekryval s otiskem
	# buildu.
	menu_state_y = menu_title_y + float(menu_title_px) * 0.5 + float(menu_sub_px) * 1.3
	menu_note_y = y0 + total + float(menu_sub_px) * 1.5
	return menu_rects


# VYBER LEVELU. Pocet ODEMCENYCH levelu a aktualni stranku vi jen obrazovka
# (profil), rozvrzeni si je prevzme - stejne jako u panelu s upgrady. Klepnuti
# pak pocita se stejnym poctem dlazdic, jaky hrac vidi.
#
# POZOR: `layout_levels` STRANKU NENULUJE, jen ji oreze na pocet stranek.
# Kdo ji tu vynuluje, ten si ji v zapeti prebije zpet na prvni - a listovani
# prestane fungovat, i kdyz sipky vypadaji v poradku.
func set_levels(unlocked: int, page: int) -> void:
	lvl_unlocked = maxi(1, unlocked)
	lvl_page = maxi(0, page)
	if view.x >= 1.0 and view.y >= 1.0:
		update(view)


# DLAZDICE LEVELU: 4 sloupce x 3 radky na strance, kazda dlazdice je CELE
# TLACITKO. Mrizka se drzi dole u ZPET a nahore u nadpisu; kdyz je na strance
# min levelu, mrizka se svisle vycentruje, aby nezustala viset u stropu.
# Vsechno, co se kresli, je tady - obrazovka si nic nepocita sama.
func layout_levels() -> void:
	lvl_tiles = []
	lvl_prev = Rect2()
	lvl_next = Rect2()
	lvl_back = Rect2()
	lvl_pages = 1
	lvl_title_y = 0.0
	lvl_note_y = 0.0
	if view.x < 1.0 or view.y < 1.0:
		lvl_page = 0
		return
	lvl_pages = int(ceil(float(lvl_unlocked) / float(LVL_PER_PAGE)))
	lvl_page = clampi(lvl_page, 0, lvl_pages - 1)
	var first: int = lvl_page * LVL_PER_PAGE
	var count: int = clampi(lvl_unlocked - first, 1, LVL_PER_PAGE)
	var rows: int = int(ceil(float(count) / float(LVL_COLS)))
	var side: float = maxf(10.0, view.x * 0.05)
	var gap: float = maxf(6.0, view.x * 0.018)
	var btn: float = minf(MENU_BTN_MAX, maxf(MENU_BTN_MIN, view.y * 0.085))
	var m: float = maxf(10.0, view.y * 0.035)
	var stack: float = maxf(8.0, view.y * 0.016)
	lvl_back = Rect2(0.0, view.y - m - btn, minf(view.x - 2.0 * side, 360.0), btn)
	lvl_back.position.x = (view.x - lvl_back.size.x) * 0.5
	var arrows_y: float = lvl_back.position.y - stack - btn
	# NADPIS A STAZ PROFILU STOJI NAD DLAZDICEMI: kdyz se nevejdou do mista nad
	# mrizkou, mrizka se posune dolu (a zmensi), ne nadpis.
	# MEZI STAZEM PROFILU A PRVNI DLAZDICI MUSI ZUSTAT MEZERA: bez ni se pocita
	# cislo na hranici a float32 v `Rect2` ho posune o zlomek pixelu - kontrola
	# pak hlasi prekryvani, ktere hrac nevidi.
	lvl_title_px = clampi(mini(menu_title_px, int(float(font_px) * 2.2)), 20, 110)
	var head: float = float(lvl_title_px) * 1.05 + float(menu_sub_px) * 1.4 + float(font_px) * 0.35
	var top: float = maxf(view.y * 0.16, float(font_px) * 2.2 + head)
	var bottom: float = arrows_y - stack
	var grid_w: float = minf(view.x - 2.0 * side, 620.0)
	var cw: float = (grid_w - gap * float(LVL_COLS - 1)) / float(LVL_COLS)
	var ch: float = minf(cw, maxf(24.0, (bottom - top - gap * float(rows - 1)) / float(rows)))
	var x0: float = (view.x - grid_w) * 0.5
	var y0: float = top + maxf(0.0, (bottom - top - ch * float(rows) - gap * float(rows - 1)) * 0.5)
	for i in range(count):
		var row: int = i / LVL_COLS
		var col: int = i % LVL_COLS
		lvl_tiles.append(Rect2(x0 + (cw + gap) * float(col), y0 + (ch + gap) * float(row), cw, ch))
	# SIPKY NA STRANKY: vlevo a vpravo od prostredku, aby mezi nimi zustalo
	# misto na "1 / 3".
	var aw: float = minf(grid_w, 420.0) * 0.36
	var acx: float = (view.x - minf(grid_w, 420.0)) * 0.5
	lvl_prev = Rect2(acx, arrows_y, aw, btn)
	lvl_next = Rect2(acx + minf(grid_w, 420.0) - aw, arrows_y, aw, btn)
	lvl_title_y = maxf(float(font_px) * 1.2, top - head)
	lvl_note_y = lvl_title_y + float(lvl_title_px) * 1.05


# NASTAVENI: jeden prepinac a ZPET, svisle vycentrovane.
func layout_settings() -> void:
	if view.x < 1.0 or view.y < 1.0:
		settings_row = Rect2()
		settings_back = Rect2()
		return
	var w: float = clampf(view.x * 0.78, 260.0, 560.0)
	var h: float = minf(MENU_BTN_MAX, maxf(MENU_BTN_MIN, view.y * 0.09))
	var gap: float = maxf(10.0, view.y * 0.03)
	var total: float = h * 2.0 + gap
	var y0: float = (view.y - total) * 0.5
	var x: float = (view.x - w) * 0.5
	settings_row = Rect2(x, y0, w, h)
	settings_back = Rect2(x, y0 + h + gap, w, h)
