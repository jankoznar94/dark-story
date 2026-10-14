extends Node2D

# KRESLENI A DOTYK. Hra sama (`game.gd`) je bez uzlu a nic nekresli — tady se
# jen cte stav a kresli. Jedna plocha, jeden hit-test, zadne Button uzly,
# zadny theme, zadny hover ani focus: plochy strojovy vzhled.

const BG := Color(0.055, 0.052, 0.062)
const FIELD_LINE := Color(0.17, 0.16, 0.18)
const RANGE_LINE := Color(0.28, 0.27, 0.30)
const TOWER_BODY := Color(0.11, 0.105, 0.115)
const TOWER_DOT := Color(0.90, 0.88, 0.84)
const TEXT := Color(0.86, 0.85, 0.82)
const DIM := Color(0.50, 0.49, 0.52)
const BEAM := Color(0.93, 0.91, 0.86)

var game: Game
var layout: ScreenLayout
var _pressed: bool = false


func _ready() -> void:
	layout = ScreenLayout.new()
	game = Game.new()
	_refield()
	get_viewport().size_changed.connect(_refield)


func _refield() -> void:
	layout.update(get_viewport_rect().size)
	game.set_field(layout.field_r, layout.tower_r, layout.center)


func _process(dt: float) -> void:
	game.step(dt)
	queue_redraw()


# STRAZCE KLEPNUTI: Godot vyrabi z kazdeho dotyku i mys, takze se reaguje JEN
# na stisk (pohyb nema akci) a stav se resetuje pri pusteni. Bez toho se jeden
# dotyk provede dvakrat.
func _unhandled_input(ev: InputEvent) -> void:
	var pos: Vector2 = Vector2.ZERO
	var press: bool = false
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		pos = ev.position
		press = ev.pressed
	elif ev is InputEventScreenTouch:
		pos = ev.position
		press = ev.pressed
	else:
		return
	if not press:
		_pressed = false
		return
	if _pressed:
		return
	_pressed = true
	if layout.up_rect.has_point(pos):
		game.buy_upgrade()
		return
	game.tap_at(pos)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, layout.view), BG)
	if layout.field_r <= 0.0:
		return
	# KRUH PLOCHY a KRUH DOSTRELU. Dostrel je jedina geometrie hry, kterou hrac
	# potrebuje videt — je to misto, kde se rozhoduje.
	draw_arc(layout.center, layout.field_r, 0.0, TAU, 128, FIELD_LINE, 2.0)
	draw_arc(layout.center, game.tower.range_px(layout.field_r), 0.0, TAU, 96, RANGE_LINE, 1.5)
	for p in game.locks:
		draw_line(layout.center, p.pos, BEAM, 2.0)
	for p in game.pilgrims:
		_draw_pilgrim(p)
	_draw_tower()
	_draw_hud()


func _draw_pilgrim(p: Pilgrim) -> void:
	var col: Color = Element.color_of(p.element)
	_rune(p.element, p.pos, layout.pilgrim_r, col)
	if p.hp_frac() < 0.999:
		var r: float = layout.pilgrim_r * 1.55
		draw_arc(p.pos, r, -PI * 0.5, -PI * 0.5 + TAU * p.hp_frac(), 24, TEXT, 2.0)


# RUNA = TVAR. U poutnika je to CELE TELO, ne drobna znacka uvnitr: plocha ma
# prumer ~370 px a poutnik ~18 px, takze znacka uvnitr by zmizela. Barva nikdy
# nesmi byt jediny nositel informace.
func _rune(el: int, p: Vector2, r: float, col: Color) -> void:
	match el:
		Element.FIRE:
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(0.0, -1.05 * r),
				p + Vector2(-0.95 * r, 0.75 * r),
				p + Vector2(0.95 * r, 0.75 * r)]), col)
		Element.WATER:
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(0.0, -1.15 * r),
				p + Vector2(-0.62 * r, -0.26 * r),
				p + Vector2(0.62 * r, -0.26 * r)]), col)
			draw_circle(p + Vector2(0.0, 0.20 * r), 0.80 * r, col)
		Element.EARTH:
			draw_rect(Rect2(p - Vector2(0.78 * r, 0.78 * r), Vector2(1.56 * r, 1.56 * r)), col)
		_:
			# VZDUCH = PRSTENEC, dutina je videt i v malem rozmeru
			draw_arc(p, 0.85 * r, 0.0, TAU, 28, col, maxf(2.0, 0.30 * r))


func _draw_tower() -> void:
	var c: Vector2 = layout.center
	var tr: float = layout.tower_r
	draw_circle(c, tr, TOWER_BODY)
	# VENEC BAREV: kazdy vysek je jedna barva. Zvoleny je TLUSTSI A SVETLEJSI —
	# meni se jen jas, barva zustava identitou a nikdy se neprebarvuje.
	var mid: float = layout.notch_mid()
	var thick: float = layout.notch_out() - layout.notch_in()
	for i in range(Element.COUNT):
		var a0: float = -PI + TAU * (float(i) / float(Element.COUNT))
		var col: Color = Element.color_of(i)
		var active: bool = (i == game.tower.element)
		if not active:
			col = Color(col.r, col.g, col.b, 0.42)
		draw_arc(c, mid, a0, a0 + TAU / float(Element.COUNT), 20, col,
			thick if active else thick * 0.5)
	_rune(game.tower.element, c, tr * 0.52, Element.color_of(game.tower.element))
	# TECKY STUPNE uvnitr veze (jeden az tri), v dolni casti tela, aby se
	# nepletly s runou.
	var dr: float = maxf(1.6, tr * 0.10)
	for i in range(game.tower.level):
		var dx: float = (float(i) - (float(game.tower.level) - 1.0) * 0.5) * dr * 3.0
		draw_circle(c + Vector2(dx, tr * 0.70), dr, TOWER_DOT)


func _draw_hud() -> void:
	var f: Font = ThemeDB.fallback_font
	var fs: int = layout.font_px
	var pad: float = maxf(8.0, layout.bar_h * 0.18)
	draw_string(f, Vector2(pad, layout.bar_h * 0.5 + fs * 0.36),
		"Vlna %d/%d    Životy %d    Zlato %d"
		% [game.wave, Game.WAVE_MAX, game.lives, game.gold],
		HORIZONTAL_ALIGNMENT_LEFT, layout.up_rect.position.x - pad, fs, TEXT)
	# TLACITKO VYLEPSENI (jedine tlacitko hry; zbytek je klepnuti na desku)
	var r: Rect2 = layout.up_rect
	var can: bool = game.tower.can_upgrade() and game.gold >= game.tower.upgrade_cost()
	var bc: Color = TEXT if can else DIM
	draw_rect(r, TOWER_BODY, true)
	draw_rect(r, bc, false, 2.0)
	var label: String = ("Vylepšit %d" % game.tower.upgrade_cost()) if game.tower.can_upgrade() else "Max"
	draw_string(f, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + fs * 0.36),
		label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, bc)
	var note: String = game.last_note()
	if note != "":
		draw_string(f, Vector2(pad, layout.bar_h + fs * 1.6), note,
			HORIZONTAL_ALIGNMENT_LEFT, layout.view.x - 2.0 * pad, fs, DIM)
	if game.is_over():
		var line: String = "Vyhráno" if game.phase == "won" else "Konec"
		draw_string(f, Vector2(0.0, layout.view.y * 0.5),
			line, HORIZONTAL_ALIGNMENT_CENTER, layout.view.x, fs * 3, TEXT)
