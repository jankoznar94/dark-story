class_name ScreenLayout
extends RefCounted

# CELE ROZVRZENI se pocita z REALNE velikosti okna. Zakladni navrh je
# 960x600 a na nem je vyladeny vzhled, ale hra se nikde neletterboxuje:
# na sirokem telefonu dostane ARENA vic mista do sirky (koleje se prodlouzi),
# na nizkem displeji min do vysky.
#
# DVE MERITKA, protoze jeden druhy nesmi rict, jak ma vypadat:
#   `s`  - meritko HERNI PLOCHY (velikosti veze, svatyne, tloušťky linii).
#          Kruh musi zustat kruhem, proto se nikdy neroztahuje pres osy.
#   `ui` - meritko OVLADANI A PISMA. Drzi se dotykoveho minima pro prst.
#
# V ovladacim pruhu uz NEJSOU tlacitka vyhybky - prepina se kliknutim na
# kolej, protoze casem bude vyhybek vic a radek tlacitek by prestal stacit.
# Cely pruh je proto NAVOD: ktereho poutnika kam poslat. Zbyva v nem jen
# SKIP, ktery je meritkem ui drzeny na dotykovem minimu.

const REF_W := 960.0
const REF_H := 600.0
const HUD_H := 72.0
const BAR_UNIT_H := 84.0
const PAD := 16.0
const BTN_H := 54.0
const SKIP_W := 92.0
const GAP := 40.0
# Dotykove minimum pro prst. Pod tim se tlacitko neda spolehlive trefit.
const MIN_TOUCH := 44.0

var view := Vector2(REF_W, REF_H)
var s := 1.0
var ui := 1.0
# Priznani, ze je displej tak maly, ze se navod do pruhu nevejde cely.
var narrow := false
var hud_h := HUD_H
var bar_h := BAR_UNIT_H
var bar_y := REF_H - BAR_UNIT_H
var arena := Rect2()
var btn_h := BTN_H
var text_x := 0.0
var skip_rect := Rect2()
# Plocha pro ctyri dvojice run "poutnik -> kolej, ktera ho zabije".
var legend := Rect2()


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
	skip_rect = Rect2(v.x - PAD * ui - SKIP_W * ui,
		bar_y + (BAR_UNIT_H - BTN_H) * 0.5 * ui, SKIP_W * ui, btn_h)

	# Legenda protikladu: po zruseni tlacitek vyhybky je pruh cely volny,
	# takze navod je videt PORAD - hrac nemusi nikam klikat, aby zjistil,
	# ktery zivel kam poslat.
	var lx: float = text_x
	var lw: float = maxf(40.0, skip_rect.position.x - GAP * ui - lx)
	legend = Rect2(lx, bar_y + 28.0 * ui, lw, 34.0 * ui)
	narrow = lw < 330.0


# Vsechny dotykove cile v jednom seznamu - testy na nem hledaji prekryvy.
func all_buttons() -> Array:
	return [skip_rect]


# Testy na nem hledaji prekryvy tlacitek s vežemi v herni plose.
func overlaps_with(rect: Rect2, margin: float = 0.0) -> bool:
	for b in all_buttons():
		var r: Rect2 = b
		if r.grow(margin).intersects(rect):
			return true
	return false


func font(px: float) -> int:
	return int(roundf(px * ui))
