class_name ScreenLayout
extends RefCounted

# ROZVRZENI. Vsechno, co se pocita z velikosti okna, se pocita TADY — hra
# dostava jen hotove cislo (`Game.set_field`).
#
# Hra je na VYSKU: plocha je KRUH vepsany do kratsiho rozmeru displeje.
# Na telefonu na sirku je tim kratsim rozmerem vyska ~287 px (prohlizec si
# ukousne listu), takze plocha ma prumer ~270 px a na 18px poutnikovi se
# barva a runa nedaji precist. Na vysku je to ~366 px.

const BAR_FRAC := 0.085
const BAR_MIN := 34.0
const MARGIN_FRAC := 0.03
# PODILY POLOMERU PLOCHY. Vsechno je podil, ne pixely — na kazde obrazovce
# tak plati stejne proporce (vez 12 % polomeru, poutnik 5 %).
const TOWER_FRAC := 0.12
const PILGRIM_FRAC := 0.05

var view: Vector2 = Vector2.ZERO
var bar_h: float = 0.0
var arena: Rect2 = Rect2()
var center: Vector2 = Vector2.ZERO
var field_r: float = 0.0
var tower_r: float = 0.0
var pilgrim_r: float = 0.0
var up_rect: Rect2 = Rect2()
var font_px: int = 16


# POZOR: dokud prohlizec neposle prvni zmenu, je velikost okna NULOVA.
# Pocitani se zapornou sirkou znamena chyby v logu (Rect2 size is negative)
# a tlacitka, ktera nejdou zmacknout — proto se tu na neplatnou velikost
# odpovida prazdnymi obdelniky.
func update(v: Vector2) -> void:
	view = v
	if v.x < 1.0 or v.y < 1.0:
		bar_h = 0.0
		arena = Rect2()
		center = Vector2.ZERO
		field_r = 0.0
		tower_r = 0.0
		pilgrim_r = 0.0
		up_rect = Rect2()
		return
	bar_h = maxf(BAR_MIN, v.y * BAR_FRAC)
	arena = Rect2(0.0, bar_h, v.x, v.y - bar_h)
	var m: float = minf(arena.size.x, arena.size.y) * MARGIN_FRAC
	field_r = maxf(20.0, minf(arena.size.x, arena.size.y) * 0.5 - m)
	center = arena.position + arena.size * 0.5
	tower_r = field_r * TOWER_FRAC
	pilgrim_r = field_r * PILGRIM_FRAC
	font_px = int(clampf(minf(v.x, v.y) * 0.045, 13.0, 30.0))
	# TLACITKO VYLEPSENI v hornim pruhu. Sirka i vyska se bere z realneho
	# obdelniku; vyska nikdy nesmi klesnout pod dotykovou mez, jinak se na
	# telefonu neda zmacknout.
	var pad: float = maxf(6.0, bar_h * 0.14)
	var w: float = clampf(v.x * 0.30, 96.0, 190.0)
	var h: float = maxf(30.0, bar_h - 2.0 * pad)
	up_rect = Rect2(v.x - w - pad, pad, w, h)


func notch_in() -> float:
	return tower_r * Game.NOTCH_IN


func notch_out() -> float:
	return tower_r * Game.NOTCH_OUT


func notch_mid() -> float:
	return (notch_in() + notch_out()) * 0.5
