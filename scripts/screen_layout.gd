class_name ScreenLayout
extends RefCounted

# ROZVRZENI. Vsechno, co se pocita z velikosti okna, se pocita TADY - hra
# dostava jen hotove cislo (`Game.set_field`).
#
# Hra je na VYSKU a ma TRI PRUHY: nahore stav (vlny, zivoty, zlato, vylepseni),
# uprostred kruhova plocha a DOLE PALETA BAREV. Paleta je dole schvalne: hrac
# vybira barvu mimo hraci pole, takze se mu pri volbe neprekryva deska a
# neztrati prehled (Jan, Oct 2026).
#
# SPAWNOVACI KRUH JE VETSI NEZ DISPLEJ (Jan, Oct 2026): "Nepřátelé se budou
# spawnovat v kruhové oblasti, ale tento kruh bude tak velký, že bude jeho horní
# hrana sahat až k vršku displeje. Boky budou jak kdyby mimo obrazovku, ale
# budou brány v potaz."
#
# Polomer plochy je proto POLOVINA VYSKY herniho pruhu (ne vepsana kratka
# strana): horni i spodni okraj kruhu se dotkne okraje herniho pruhu a na
# displeji na vysku (~390x844) vedou boky 147 px MIMO obraz - poutnici odtamtud
# vchazeji z boku. Kruh se NIKDE nekresli (je pomyslny), hrac vidi jen kruh
# dostrelu.
#
# Na sirku (kde hra rika "otoc telefon") je pruh sirsi nez vyssi a kruh se
# vejde do sirky - hra se tim nerozbije, jen se z nej stane vepsany kruh.
#
# MENU je prvni obrazovka (viz `Menu`) a ma vlastni rozvrzeni: tri tlacitka
# pod sebou, svisle vycentrovana. Vysky zustavaji na dotykovem minimu a
# zmensuje se jen mezera - spatne stisknutelne tlacitko je horsi nez tesnejsi
# rozvrzeni.

const BAR_FRAC := 0.075
# HORNI PRUH MUSI POJMout TLACITKO VYLEPSENI v dotykove mezi: 44 px + okraje.
const BAR_MIN := 44.0
const PAL_FRAC := 0.115
const PAL_MIN := 64.0
const TOWER_FRAC := 0.12
# DOTYKOVA MEZ. Tlacitko barvy je to jedine, na co hrac klika - pod 44 px
# se na telefonu neda spolehlive trefit.
const BTN_MIN := 44.0
const BTN_MAX := 96.0
# MENU: vyska tlacitka se nikdy nezmensi pod dotykovou mez, zmensuje se jen
# mezera mezi nimi.
const MENU_BTN_MIN := 48.0
const MENU_BTN_MAX := 76.0

# TLACITKA V HORNIM PRUHU SE MERI, NE ODHADUJI. Driv melo vylepseni pevny
# podil sirky (32 %) - jenze pruh ma TRI prvky: stavovy text, MENU a
# vylepseni. S pevnymi podily se na 360px telefonu stavovy text nevesel a
# musel se zmensit na 10 px. Rozvrzeni proto meri popisky ve SKUTECNEM fontu
# (a rezervuje je pro NEJDELSI mozny popisek, aby tlacitka neposkakovala,
# kdyz se cena zmeni) a stavovemu textu zbyde presne to, co zbylo.
const HUD_UPGRADE_REF := "Vylepšit 300"
const HUD_MENU_LABEL := "MENU"

var view: Vector2 = Vector2.ZERO
var bar_h: float = 0.0
var pal_h: float = 0.0
var arena: Rect2 = Rect2()
var center: Vector2 = Vector2.ZERO
var field_r: float = 0.0
var tower_r: float = 0.0
var pilgrim_r: float = 0.0
var up_rect: Rect2 = Rect2()
var hud_menu: Rect2 = Rect2()
# SIRKA PRO STAVOVY TEXT. Je to presne to, co zbyde vlevo od tlacitek - text
# se na ni zmensuje (viz `GameView._fit_px`), aby se nikdy neprekryl s
# tlacitkem. Driv se text kreslil do sirky tlacitka vylepseni a s tretim
# tlacitkem v pruhu by se text utnul.
var bar_text_w: float = 0.0
var font_px: int = 16
# FONT PRO MERENI POPISKU. Vychozi je patkovy font enginu - stejny, kterym se
# kresli. Kdo by kreslil jinym, musi ho sem predat (`set_font`), jinak by
# rozvrzeni merilo jinou velikost, nez hrac vidi.
var hud_font: Font = ThemeDB.fallback_font
var pal_rects: Array = []
# MENU
var menu_rects: Array = []
var menu_title_y: float = 0.0
var menu_note_y: float = 0.0
var menu_title_px: int = 30
var menu_item_px: int = 18
var menu_sub_px: int = 12
# NASTAVENI
var settings_row: Rect2 = Rect2()
var settings_back: Rect2 = Rect2()
# DOTAZ PRI ODCHODU Z BOJE ("opravdu ukoncit?")
var leave_box: Rect2 = Rect2()
var leave_yes: Rect2 = Rect2()
var leave_no: Rect2 = Rect2()


# POZOR: dokud prohlizec neposle prvni zmenu, je velikost okna NULOVA.
# Pocitani se zapornou sirkou znamena chyby v logu (Rect2 size is negative)
# a tlacitka, ktera nejdou zmacknout - proto se tu na neplatnou velikost
# odpovida prazdnymi obdelniky.
func update(v: Vector2) -> void:
	view = v
	if v.x < 1.0 or v.y < 1.0:
		bar_h = 0.0
		pal_h = 0.0
		arena = Rect2()
		center = Vector2.ZERO
		field_r = 0.0
		tower_r = 0.0
		pilgrim_r = 0.0
		up_rect = Rect2()
		hud_menu = Rect2()
		bar_text_w = 0.0
		pal_rects = []
		menu_rects = []
		settings_row = Rect2()
		settings_back = Rect2()
		leave_box = Rect2()
		leave_yes = Rect2()
		leave_no = Rect2()
		return
	bar_h = maxf(BAR_MIN, v.y * BAR_FRAC)
	pal_h = maxf(PAL_MIN, v.y * PAL_FRAC)
	arena = Rect2(0.0, bar_h, v.x, maxf(1.0, v.y - bar_h - pal_h))
	field_r = maxf(20.0, arena.size.y * 0.5)
	center = arena.position + arena.size * 0.5
	tower_r = field_r * TOWER_FRAC
	pilgrim_r = field_r * Game.PILGRIM_R_FRAC
	font_px = int(clampf(minf(v.x, v.y) * 0.042, 13.0, 30.0))
	# HORNI PRUH: [stavovy text] [MENU] [Vylepsit]. Poradi od praveho okraje
	# je dane tim, jak casto hrac na co klika - vylepseni je herni akce,
	# menu je odchod. Sirky tlacitek se MERI (viz konstanta vyse), text
	# dostane zbytek.
	var pad: float = maxf(4.0, bar_h * 0.10)
	var gap: float = maxf(4.0, bar_h * 0.10)
	var h: float = maxf(30.0, bar_h - 2.0 * pad)
	var w: float = clampf(measure_px(HUD_UPGRADE_REF, font_px) + 12.0, 96.0, 220.0)
	up_rect = Rect2(v.x - w - pad, pad, w, h)
	var mw: float = clampf(measure_px(HUD_MENU_LABEL, font_px) + 12.0, BTN_MIN, 120.0)
	hud_menu = Rect2(up_rect.position.x - gap - mw, pad, mw, h)
	# Text ma vlastni okraj na OBOU stranach, aby se nikdy nedotkl tlacitka.
	bar_text_w = maxf(0.0, hud_menu.position.x - 2.0 * pad)
	layout_palette(pal_rects.size())
	layout_menu(Menu.MENU_ITEMS.size())
	layout_settings()
	leave_panel()


# SIRKA TEXTU VE SKUTECNEM FONTU. Kdo meri jinak nez kresli, meri neco jineho
# nez hrac vidi - proto je to tady jedno misto pro rozvrzeni i pro testy.
func measure_px(s: String, px: int) -> float:
	return hud_font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x


# TLACITKA PALETY. Pocet barev se v prubehu hry meni (barvy pribyvaji), takze
# se rozvrzeni pocita z poctu, ktery dostane - ne z konstanty.
func layout_palette(count: int) -> Array:
	if count <= 0 or view.x < 1.0:
		pal_rects = []
		return pal_rects
	var pad: float = maxf(6.0, view.x * 0.02)
	var gap: float = maxf(4.0, view.x * 0.014)
	var room: float = view.x - 2.0 * pad - gap * float(count - 1)
	var w: float = clampf(room / float(count), BTN_MIN, BTN_MAX)
	var h: float = maxf(BTN_MIN, pal_h - 2.0 * maxf(6.0, pal_h * 0.12))
	var total: float = w * float(count) + gap * float(count - 1)
	var x: float = (view.x - total) * 0.5
	var y: float = view.y - pal_h + (pal_h - h) * 0.5
	pal_rects = []
	for i in range(count):
		pal_rects.append(Rect2(x + (w + gap) * float(i), y, w, h))
	return pal_rects


# TLACITKA MENU. Pocet vi jen ten, kdo je kresli (Menu) - stejne jako paleta.
func layout_menu(count: int) -> Array:
	if count <= 0 or view.x < 1.0 or view.y < 1.0:
		menu_rects = []
		return menu_rects
	var w: float = clampf(view.x * 0.5, 180.0, 420.0)
	var h: float = minf(MENU_BTN_MAX, maxf(MENU_BTN_MIN, view.y * 0.085))
	var gap: float = maxf(10.0, view.y * 0.022)
	var total: float = h * float(count) + gap * float(count - 1)
	# Kdyz je displej nizky, zmensi se MEZERA, ne tlacitko.
	var room: float = view.y - h - 12.0
	if total > room:
		gap = maxf(4.0, (room - h * float(count)) / float(count - 1))
		total = h * float(count) + gap * float(count - 1)
	var y0: float = (view.y - total) * 0.5 + view.y * 0.05
	var x: float = (view.x - w) * 0.5
	menu_rects = []
	for i in range(count):
		menu_rects.append(Rect2(x, y0 + (h + gap) * float(i), w, h))
	# PISMO MENU. Titul je nejvetsi text ve hre, popisek tlacitka musi zustat
	# citelny i na 640x360.
	menu_title_px = clampi(int(float(font_px) * 2.2), 28, 64)
	menu_item_px = clampi(int(float(font_px) * 1.15), 15, 30)
	menu_sub_px = clampi(int(float(font_px) * 0.78), 11, 20)
	menu_title_y = maxf(float(menu_title_px) * 1.6, y0 - float(menu_title_px) * 2.1)
	menu_note_y = y0 + total + float(font_px) * 2.4
	return menu_rects


# NASTAVENI: jeden prepinac a ZPET, svisle vycentrovane. Stejna logika jako
# u menu - vyska zustava na dotykovem minimu.
func layout_settings() -> void:
	if view.x < 1.0 or view.y < 1.0:
		settings_row = Rect2()
		settings_back = Rect2()
		return
	var w: float = clampf(view.x * 0.5, 180.0, 420.0)
	var h: float = minf(MENU_BTN_MAX, maxf(MENU_BTN_MIN, view.y * 0.085))
	var gap: float = maxf(10.0, view.y * 0.03)
	var total: float = h * 2.0 + gap
	var y0: float = (view.y - total) * 0.5
	var x: float = (view.x - w) * 0.5
	settings_row = Rect2(x, y0, w, h)
	settings_back = Rect2(x, y0 + h + gap, w, h)


# DOTAZ "OPRAVDU UKONCIT?". Kresli se NAD VSIM a klepnuti mimo odpovedi nic
# nedela - hrac na dotaz ma odpovedet.
func leave_panel() -> void:
	if view.x < 1.0 or view.y < 1.0:
		leave_box = Rect2()
		leave_yes = Rect2()
		leave_no = Rect2()
		return
	var bw: float = minf(440.0, view.x * 0.86)
	var bh: float = maxf(150.0, view.y * 0.30)
	leave_box = Rect2((view.x - bw) * 0.5, (view.y - bh) * 0.5, bw, bh)
	var pad: float = maxf(10.0, bw * 0.03)
	var btn_h: float = maxf(BTN_MIN, bh * 0.28)
	var btn_w: float = (bw - pad * 3.0) * 0.5
	leave_yes = Rect2(leave_box.position.x + pad, leave_box.end.y - pad - btn_h, btn_w, btn_h)
	leave_no = Rect2(leave_yes.end.x + pad, leave_yes.position.y, btn_w, btn_h)
