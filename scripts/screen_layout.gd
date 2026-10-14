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
# Kruhova plocha je vepsana do kratsiho rozmeru prostredniho pruhu. Na telefonu
# na vysku je tim kratsim rozmerem sirka (~390 px), takze plocha ma prumer
# ~366 px; na sirku by ji omezila vyska a barvy by se na 18px poutnikovi
# nedaly precist.

const BAR_FRAC := 0.075
# HORNI PRUH MUSI POJMout TLACITKO VYLEPSENI v dotykove mezi: 44 px + okraje.
const BAR_MIN := 44.0
const PAL_FRAC := 0.115
const PAL_MIN := 64.0
const MARGIN_FRAC := 0.03
const TOWER_FRAC := 0.12
# DOTYKOVA MEZ. Tlacitko barvy je to jedine, na co hrac klika - pod 44 px
# se na telefonu neda spolehlive trefit.
const BTN_MIN := 44.0
const BTN_MAX := 96.0

var view: Vector2 = Vector2.ZERO
var bar_h: float = 0.0
var pal_h: float = 0.0
var arena: Rect2 = Rect2()
var center: Vector2 = Vector2.ZERO
var field_r: float = 0.0
var tower_r: float = 0.0
var pilgrim_r: float = 0.0
var up_rect: Rect2 = Rect2()
var font_px: int = 16
var pal_rects: Array = []


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
		pal_rects = []
		return
	bar_h = maxf(BAR_MIN, v.y * BAR_FRAC)
	pal_h = maxf(PAL_MIN, v.y * PAL_FRAC)
	arena = Rect2(0.0, bar_h, v.x, maxf(1.0, v.y - bar_h - pal_h))
	var m: float = minf(arena.size.x, arena.size.y) * MARGIN_FRAC
	field_r = maxf(20.0, minf(arena.size.x, arena.size.y) * 0.5 - m)
	center = arena.position + arena.size * 0.5
	tower_r = field_r * TOWER_FRAC
	pilgrim_r = field_r * Game.PILGRIM_R_FRAC
	font_px = int(clampf(minf(v.x, v.y) * 0.042, 13.0, 30.0))
	# TLACITKO VYLEPSENI v hornim pruhu
	var pad: float = maxf(4.0, bar_h * 0.10)
	var w: float = clampf(v.x * 0.32, 96.0, 200.0)
	var h: float = maxf(30.0, bar_h - 2.0 * pad)
	up_rect = Rect2(v.x - w - pad, pad, w, h)
	layout_palette(pal_rects.size())


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
