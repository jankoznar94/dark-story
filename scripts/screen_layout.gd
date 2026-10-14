class_name ScreenLayout
extends RefCounted

# ROZVRZENI. Vsechno, co se pocita z velikosti okna, se pocita TADY - hra
# dostava jen hotove cislo (`Game.set_field`).
#
# Hra je na VYSKU a ma TRI PRUHY: nahore stav (level, vlna, zivoty, zlato),
# uprostred kruhova plocha a DOLE PALETA BAREV. Paleta je dole schvalne: hrac
# vybira barvu mimo hraci pole, takze se mu pri volbe neprekryva deska.
#
# SPAWNOVACI KRUH JE VETSI NEZ DISPLEJ a NEMALUJE SE - hrac vidi jen kruh
# dostrelu, jehoz barvu urcuje barva veze.
#
# PLOCHA A MERITKO KRESLENI JSOU DVE CISLA: `unit_r` = meritko kresleni (vez,
# poutnik, tecka) a `field_r` = spawnovaci kruh. Zmensuje se JEN meritko
# (`UNIT_SHRINK`) - plocha tim opticky naroste, ale rozvrzeni se nemeni.
#
# PANELY S KATEGORIEMI (bitva i menu) MAJI JEDEN PREDEK: `layout_card`. Tab
# kategorie, radky parametru a tlacitko "+cena" se pocitaji na jednom miste,
# takze se bitva a menu nemohou rozejit.

const BAR_FRAC := 0.075
const BAR_MIN := 44.0
const PAL_FRAC := 0.115
const PAL_MIN := 64.0
const MARGIN_FRAC := 0.03
# ZMENSENI KRESLENI (Jan: "A vše uděláme o něco menší ... Musíme opticky
# zvětšit celou tuhle plochu"): plati pro vez, poutnika i tecku strely.
const UNIT_SHRINK := 0.85
const BTN_MIN := 44.0
const PAL_BTN_MAX := 132.0
const MENU_BTN_MIN := 56.0
const MENU_BTN_MAX := 120.0
# TAB KATEGORIE A RADEK PARAMETRU. Tab musi jit zmacknout prstem (44 px),
# radek muze byt nizsi - klepe se jen na tlacitko "+" na jeho konci.
const TAB_MIN := 40.0
const ROW_MIN := 34.0
const BUY_W := 78.0

var view: Vector2 = Vector2.ZERO
var bar_h: float = 0.0
var pal_h: float = 0.0
var arena: Rect2 = Rect2()
var center: Vector2 = Vector2.ZERO
var field_r: float = 0.0
var unit_r: float = 0.0
var tower_r: float = 0.0
var pilgrim_r: float = 0.0
# HORNI PRUH: stavovy text, MENU (odchod) a UPGRADY (panel s nakupem).
var hud_menu: Rect2 = Rect2()
var hud_upgrades: Rect2 = Rect2()
var bar_text_w: float = 0.0
var font_px: int = 16
# DVOURADKOVY STAV: prvni radek je level/vlna, druhy zivoty a zlato. Dvakrat
# delsi text na jednom radku by se musel zmensit tak, ze by ho hrac necetl.
const HUD_LINE1_FMT := "Level %d · vlna %d/%d"
const HUD_LINE2_FMT := "Životy %d/%d · zlato %d"
var hud_font: Font = ThemeDB.fallback_font
# PANEL S NAKUPEM (bitva): tab kategorii + radky parametru s tlacitkem "+cena".
var shop_tab_count: int = 3
var shop_row_count: int = 4
var shop_panel: Rect2 = Rect2()
var shop_tabs: Array = []
var shop_rows: Array = []
var shop_buttons: Array = []
var shop_close: Rect2 = Rect2()
# MENU - OBRAZOVKA UPRAVY: stejny panel, ale pres cely displej a se SPECIALEM.
var upg_panel: Rect2 = Rect2()
var upg_tabs: Array = []
var upg_rows: Array = []
var upg_buttons: Array = []
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
		hud_upgrades = Rect2()
		bar_text_w = 0.0
		shop_panel = Rect2()
		shop_tabs = []
		shop_rows = []
		shop_buttons = []
		shop_close = Rect2()
		upg_panel = Rect2()
		upg_tabs = []
		upg_rows = []
		upg_buttons = []
		upg_back = Rect2()
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
	arena = Rect2(0.0, bar_h, v.x, maxf(1.0, v.y - bar_h - pal_h))
	var short_side: float = minf(arena.size.x, arena.size.y)
	unit_r = maxf(20.0, (short_side * 0.5 - short_side * MARGIN_FRAC) * UNIT_SHRINK)
	field_r = maxf(unit_r, arena.size.y * 0.5)
	center =arena.position + arena.size * 0.5
	tower_r = unit_r * 0.12
	pilgrim_r = unit_r * 0.05
	font_px = int(clampf(minf(v.x, v.y) * 0.046, 14.0, 34.0))
	_hud()
	layout_shop()
	layout_upgrades()
	# DIALOG SE POCITA ZVLAST (`dialog_panel`): pocet odpovedi se lisi podle
	# toho, ktery dialog je otevreny, a to vi jen obrazovka. Kdo ho spocte tady
	# napevno, pripravi hrace o jednu odpoved.
	layout_palette(pal_rects.size())
	layout_menu(Menu.MENU_ITEMS.size())
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


# HORNI PRUH: [stavovy text] [UPGRADY] [MENU]. Poradi od praveho okraje je
# dane tim, jak casto hrac na co klika - upravy jsou herni akce, menu je
# odchod. Sirky tlacitek se MERI (stejne jako driv u "Vylepsit"), text dostane
# zbytek - jinak by se na uzkem displeji utnul.
func _hud() -> void:
	var pad: float = maxf(4.0, bar_h * 0.10)
	var gap: float = maxf(4.0, bar_h * 0.08)
	var h: float = maxf(30.0, bar_h - 2.0 * pad)
	var uw: float = clampf(measure_px("UPGRADY", font_px) + 12.0, 88.0, 200.0)
	hud_upgrades = Rect2(view.x - uw - pad, pad, uw, h)
	var mw: float = clampf(measure_px("MENU", font_px) + 12.0, BTN_MIN, 120.0)
	hud_menu = Rect2(hud_upgrades.position.x - gap - mw, pad, mw, h)
	bar_text_w = maxf(0.0, hud_menu.position.x - 2.0 * pad)


# --------------------------------------------------------------- SPOLECNY PANEL

# PANEL S KATEGORIEMI: taby nahore, radky parametru pod nimi, tlacitko "+cena"
# na konci radku. Vraci {tabs, rows, buttons, close} - jedno misto pro bitvu
# i pro menu, takze se oba panely nemohou rozejit.
func layout_card(r: Rect2, tab_count: int, row_count: int) -> Dictionary:
	var out: Dictionary = {"tabs": [], "rows": [], "buttons": [], "close": Rect2()}
	if r.size.x < 1.0 or r.size.y < 1.0 or tab_count <= 0 or row_count <= 0:
		return out
	var pad: float = maxf(8.0, r.size.x * 0.022)
	var gap: float = maxf(6.0, r.size.x * 0.016)
	# TABY MAJI PRIORITU: kdyz je panel nizky, zmensi se RADEK, ne tab.
	var tabs_h: float = maxf(TAB_MIN, minf(52.0, r.size.y * 0.20))
	var inner: float = r.size.x - 2.0 * pad
	var tw: float = maxf(BTN_MIN, (inner - gap * float(tab_count - 1)) / float(tab_count))
	var t: float = r.position.y + pad
	var tabs: Array = []
	for i in range(tab_count):
		tabs.append(Rect2(r.position.x + pad + (tw + gap) * float(i), t, tw, tabs_h))
	var rows_top: float = t + tabs_h + maxf(4.0, pad * 0.5)
	var room: float = r.end.y - pad - rows_top
	var rh: float = maxf(ROW_MIN, (room - gap * float(row_count - 1)) / float(row_count))
	var rows: Array = []
	var buttons: Array = []
	for i in range(row_count):
		var rr := Rect2(r.position.x + pad, rows_top + (rh + gap) * float(i), inner, rh)
		rows.append(rr)
		var bw: float = minf(BUY_W, inner * 0.34)
		buttons.append(Rect2(rr.end.x - bw, rr.position.y, bw, rh))
	out["tabs"] = tabs
	out["rows"] = rows
	out["buttons"] = buttons
	out["close"] = Rect2(r.end.x - pad - 34.0, r.position.y + 4.0, 34.0, 30.0)
	return out


# PANEL V BITVE. Kresli se NAD SPODNI CASTI POLE (ne pres paletu - barvy musi
# zustat porad videt, hrac je prepina i pri nakupu) a hra pod nim STOJI.
func set_shop_shape(tabs: int, rows: int) -> void:
	shop_tab_count = maxi(1, tabs)
	shop_row_count = maxi(1, rows)
	if view.x >= 1.0 and view.y >= 1.0:
		update(view)


func layout_shop() -> void:
	if view.x < 1.0 or view.y < 1.0:
		shop_panel = Rect2()
		shop_tabs = []
		shop_rows = []
		shop_buttons = []
		shop_close = Rect2()
		return
	var gap: float = maxf(8.0, view.y * 0.012)
	var h: float = maxf(160.0, view.y * 0.44)
	var side: float = maxf(6.0, view.x * 0.02)
	shop_panel = Rect2(side, view.y - pal_h - gap - h, view.x - 2.0 * side, h)
	var card: Dictionary = layout_card(shop_panel, shop_tab_count, shop_row_count)
	shop_tabs = card["tabs"]
	shop_rows = card["rows"]
	shop_buttons = card["buttons"]
	shop_close = card["close"]


# OBRAZOVKA UPRAVY V MENU: stejny panel, ale pres cely displej a se SPECIALEM.
func layout_upgrades() -> void:
	if view.x < 1.0 or view.y < 1.0:
		upg_panel = Rect2()
		upg_tabs = []
		upg_rows = []
		upg_buttons = []
		upg_back = Rect2()
		return
	var side: float = maxf(10.0, view.x * 0.05)
	var top: float = maxf(46.0, view.y * 0.10)
	var btn: float = minf(MENU_BTN_MAX, maxf(MENU_BTN_MIN, view.y * 0.09))
	var bottom: float = view.y - btn - maxf(26.0, view.y * 0.05)
	upg_panel = Rect2(side, top, view.x - 2.0 * side, maxf(180.0, bottom - top))
	var card: Dictionary = layout_card(upg_panel, Upgrades.CATEGORIES.size(), 4)
	upg_tabs = card["tabs"]
	upg_rows = card["rows"]
	upg_buttons = card["buttons"]
	upg_back = Rect2((view.x - minf(440.0, view.x * 0.86)) * 0.5, bottom + 6.0,
		minf(440.0, view.x * 0.86), btn)
	upg_note_y = top - float(font_px) * 1.35


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
func layout_palette(count: int) -> Array:
	if count <= 0 or view.x < 1.0:
		pal_rects = []
		return pal_rects
	var pad: float = maxf(8.0, view.x * 0.025)
	var gap: float = maxf(10.0, view.x * 0.028)
	var room_w: float = (view.x - 2.0 * pad - gap * float(count - 1)) / float(count)
	var room_h: float = pal_h - 2.0 * maxf(6.0, pal_h * 0.10)
	var side: float = minf(clampf(room_w, BTN_MIN, PAL_BTN_MAX), maxf(BTN_MIN, room_h))
	var total: float = side * float(count) + gap * float(count - 1)
	var x: float = (view.x - total) * 0.5
	var y: float = view.y - pal_h + (pal_h - side) * 0.5
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
	var h: float = minf(MENU_BTN_MAX, maxf(MENU_BTN_MIN, view.y * 0.13))
	var gap: float = maxf(14.0, view.y * 0.03)
	var total: float = h * float(count) + gap * float(count - 1)
	var room: float = view.y - h - 12.0
	if total > room:
		gap = maxf(4.0, (room - h * float(count)) / float(count - 1))
		total = h * float(count) + gap * float(count - 1)
	var y0: float = (view.y - total) * 0.5 + view.y * 0.05
	var x: float = (view.x - w) * 0.5
	menu_rects = []
	for i in range(count):
		menu_rects.append(Rect2(x, y0 + (h + gap) * float(i), w, h))
	# TITUL SE MUSI VEJIT NAD TLACITKA: na nizkem displeji se zmensi podle
	# mista, ktere mu zbylo - jinak by prelezl do prvniho tlacitka.
	var above: float = maxf(24.0, y0 - 6.0)
	menu_title_px = clampi(int(minf(float(font_px) * 3.2, above * 0.34)), 22, 110)
	menu_item_px = clampi(int(minf(float(font_px) * 1.65, float(menu_title_px) * 0.62)), 18, 56)
	var sub_max: int = int(minf(float(font_px) * 1.05, float(menu_item_px) * 0.72))
	menu_sub_px = clampi(fit_px(Menu.SUBTITLE, view.x * 0.92, sub_max, 12), 12, 32)
	menu_title_y = maxf(float(menu_title_px) * 1.2,
		y0 - float(menu_title_px) * 1.7 - float(menu_sub_px))
	menu_note_y = y0 + total + float(menu_sub_px) * 2.0
	menu_state_y = maxf(6.0, menu_note_y + float(menu_sub_px) * 1.6)
	return menu_rects


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
