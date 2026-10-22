class_name ScreenLayout
extends RefCounted

# ROZVRZENI. Jedno misto, kde se pocitaji vsechny obdelniky - obrazovka ani hra
# si nic nepocitaji samy, jinak se klepnuti a kresba rozejdou.

const BAR_FRAC := 0.078
const BAR_MIN := 44.0
const BTN_MIN := 44.0
const BTN_MAX := 64.0
const MARGIN_FRAC := 0.05
const PLAY_R := 0.46          # podil kratsi strany plochy, ktery je herni kruh

var view: Vector2 = Vector2.ZERO
var bar_h: float = 0.0
var arena: Rect2 = Rect2()
var center: Vector2 = Vector2.ZERO
var field_r: float = 0.0
var font_px: int = 16
var title_px: int = 30

var hud_pause: Rect2 = Rect2()
var hud_menu: Rect2 = Rect2()

var menu_rects: Array = []
var menu_title_y: float = 0.0
var menu_note_y: float = 0.0

var upg_panel: Rect2 = Rect2()
var upg_rows: Array = []
var upg_back: Rect2 = Rect2()
var upg_note_y: float = 0.0
var upg_title_y: float = 0.0

var dlg_box: Rect2 = Rect2()
var dlg_a: Rect2 = Rect2()
var dlg_b: Rect2 = Rect2()


func update(v: Vector2) -> void:
	view = v
	if v.x < 1.0 or v.y < 1.0:
		bar_h = 0.0
		field_r = 0.0
		center = Vector2.ZERO
		arena = Rect2()
		menu_rects = []
		upg_rows = []
		hud_pause = Rect2()
		hud_menu = Rect2()
		return
	bar_h = maxf(48.0, v.y * BAR_FRAC)
	font_px = int(clampf(minf(v.x, v.y) * 0.042, 13.0, 26.0))
	title_px = int(clampf(minf(v.x, v.y) * 0.075, 22.0, 44.0))
	# HERNI PLOCHA je ctverec pod hornim pruhem. Kruh se do nej musi vejit
	# CELY - hrac nesmi mit nepritele za okrajem displeje.
	arena = Rect2(0.0, bar_h, v.x, maxf(1.0, v.y - bar_h))
	center = arena.position + arena.size * 0.5
	var short: float = minf(arena.size.x, arena.size.y)
	field_r = maxf(40.0, short * PLAY_R)
	_hud()
	layout_menu()
	layout_upgrades()
	layout_dialog()


func _hud() -> void:
	var h: float = maxf(32.0, bar_h - 12.0)
	var w: float = maxf(64.0, minf(120.0, view.x * 0.22))
	var top: float = (bar_h - h) * 0.5
	hud_menu = Rect2(view.x - w - 8.0, top, w, h)
	hud_pause = Rect2(hud_menu.position.x - w - 6.0, top, w, h)


func btn_size() -> float:
	return minf(BTN_MAX, maxf(BTN_MIN, view.y * 0.075))


func layout_menu() -> void:
	menu_rects = []
	if view.x < 1.0 or view.y < 1.0:
		return
	var w: float = clampf(view.x * 0.80, 240.0, 560.0)
	var h: float = btn_size() * 1.5
	var gap: float = maxf(10.0, view.y * 0.02)
	var total: float = h * 2.0 + gap
	var y0: float = view.y * 0.52
	var x: float = (view.x - w) * 0.5
	for i in range(2):
		menu_rects.append(Rect2(x, y0 + (h + gap) * float(i), w, h))
	menu_title_y = view.y * 0.12
	menu_note_y = y0 + total + gap * 1.5


func layout_upgrades() -> void:
	upg_rows = []
	upg_panel = Rect2()
	upg_back = Rect2()
	if view.x < 1.0 or view.y < 1.0:
		return
	var w: float = clampf(view.x * 0.86, 260.0, 620.0)
	var h: float = btn_size()
	var gap: float = maxf(8.0, view.y * 0.012)
	var top: float = view.y * 0.14
	var bottom: float = view.y - h - maxf(18.0, view.y * 0.04)
	var n: int = Upgrades.STATS.size()
	# NA SIROKEM DISPLEJI DVA SLOUPCE. Sedm radku po 44 px se na 360 px vysky
	# nevejde; zmensovat je pod dotykovou velikost by znamenalo, ze se upgrade
	# neda koupit. Poradi je po radcich (index = index statu), takze klepnuti
	# zustava na svem miste.
	var cols: int = 2 if view.x > view.y * 1.15 else 1
	var rows: int = int(ceil(float(n) / float(cols)))
	var avail: float = maxf(1.0, bottom - top - gap * 2.0)
	var rh: float = minf(h, (avail - gap * float(rows - 1)) / float(rows))
	var cw: float = (w - gap * float(cols - 1)) / float(cols)
	var x: float = (view.x - w) * 0.5
	var panel_h: float = rh * float(rows) + gap * float(rows - 1)
	upg_panel = Rect2(x, top, w, panel_h)
	for i in range(n):
		var col: int = i / rows
		var row: int = i % rows
		upg_rows.append(Rect2(x + (cw + gap) * float(col), top + (rh + gap) * float(row), cw, rh))
	upg_back = Rect2(x, view.y - h - maxf(18.0, view.y * 0.04), w, h)
	upg_title_y = top - view.y * 0.08
	upg_note_y = top - view.y * 0.045


func layout_dialog() -> void:
	if view.x < 1.0 or view.y < 1.0:
		dlg_box = Rect2()
		dlg_a = Rect2()
		dlg_b = Rect2()
		return
	var bw: float = minf(520.0, view.x * 0.9)
	var bh: float = maxf(150.0, view.y * 0.26)
	dlg_box = Rect2((view.x - bw) * 0.5, (view.y - bh) * 0.5, bw, bh)
	var pad: float = maxf(10.0, bw * 0.03)
	var btn_h: float = btn_size()
	var btn_w: float = (bw - pad * 3.0) * 0.5
	dlg_a = Rect2(dlg_box.position.x + pad, dlg_box.end.y - pad - btn_h, btn_w, btn_h)
	dlg_b = Rect2(dlg_a.end.x + pad, dlg_a.position.y, btn_w, btn_h)
