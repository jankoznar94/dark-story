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
# Devet tlacitek v jednom pruhu je na uzky displej hodne, takze sirka
# tlacitka se zmensuje NEZAVISLE na vysce: radek se vzdycky vejde presne,
# ale vyska zustava na dotykovem minimu. Kdyz se nevejde ani to, `narrow`
# to prizná - hra se nerozbije, jen se to vi.

const REF_W := 960.0
const REF_H := 600.0
const HUD_H := 72.0
const BAR_UNIT_H := 92.0
const PAD := 16.0
const BTN_W := 78.0
const BTN_H := 54.0
const BTN_STEP := 84.0
const SKIP_W := 92.0
const GAP := 40.0
# Dotykove minimum pro prst. Pod tim se tlacitko neda spolehlive trefit.
const MIN_TOUCH := 44.0

var view := Vector2(REF_W, REF_H)
var s := 1.0
var ui := 1.0
var narrow := false
var hud_h := HUD_H
var bar_h := BAR_UNIT_H
var bar_y := REF_H - BAR_UNIT_H
var arena := Rect2()
var btn_w := BTN_W
var btn_h := BTN_H
var btn_step := BTN_STEP
var btn_y := 0.0
var element_x := 0.0
var switch_x := 0.0
var skip_rect := Rect2()


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

	# --- radek tlacitek ---
	# Nejdřív zjistime, kolik sirky zbude na osm tlacitek, kdyz se pocita
	# i s okraji, mezerou mezi skupinami a tlacitkem SKIP. Z toho vyjde
	# rozestup, a teprve z nej sirka tlacitka. Takhle se radek vejde VZDY,
	# i kdyz se musi rozestup zmensit pod zakladni navrh.
	var gap: float = GAP * ui
	btn_step = (v.x - 2.0 * PAD * ui - gap - SKIP_W * ui) / 8.0
	btn_step = minf(btn_step, BTN_STEP * ui)
	btn_w = maxf(MIN_TOUCH * 0.5, btn_step - (BTN_STEP - BTN_W) * ui)
	btn_h = BTN_H * ui
	narrow = btn_step < MIN_TOUCH

	btn_y = bar_y + 26.0 * ui
	element_x = PAD * ui
	switch_x = element_x + 4.0 * btn_step + gap
	skip_rect = Rect2(v.x - PAD * ui - SKIP_W * ui, btn_y, SKIP_W * ui, btn_h)


func element_button(i: int) -> Rect2:
	return Rect2(element_x + float(i) * btn_step, btn_y, btn_w, btn_h)


func switch_button(i: int) -> Rect2:
	return Rect2(switch_x + float(i) * btn_step, btn_y, btn_w, btn_h)


# Vsechny dotykove cile v jednom seznamu - testy na nem hledaji prekryvy.
func all_buttons() -> Array:
	var out: Array = []
	for i in range(4):
		out.append(element_button(i))
	for i in range(4):
		out.append(switch_button(i))
	out.append(skip_rect)
	return out


# Testy na nem hledaji prekryvy tlacitek s vežemi v herni plose.
func overlaps_with(rect: Rect2, margin: float = 0.0) -> bool:
	for b in all_buttons():
		var r: Rect2 = b
		if r.grow(margin).intersects(rect):
			return true
	return false


func font(px: float) -> int:
	return int(roundf(px * ui))
