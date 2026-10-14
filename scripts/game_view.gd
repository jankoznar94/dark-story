extends Node2D

# KRESLENI A DOTYK. Hra sama (`game.gd`) je bez uzlu a nic nekresli - tady se
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
const GLYPH := Color(0.09, 0.085, 0.09)
# ZTLUMENI NEAKTIVNÍCH TALCÍČEK PALETY. Driv to bylo 42 % a zeme se vzduchem
# v tom ztlumeni skoro zmizely (zmereno proti pozadi) - hrac pak nevidi, na co
# ma klepnout. Tvar je proto VZDY v plne barve, ztlumuje se jen podklad.
const PAL_IDLE := 0.55

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
	layout.layout_palette(game.palette.size())


func _process(dt: float) -> void:
	game.step(dt)
	# POCET BAREV SE V PRUBEHU HRY MENI (barvy pribyvaji). Kdyz se paleta
	# roztahne, musi se prekreslit i tlacitka - jinak by hrac videl barvu,
	# ktera se neda zmacknout.
	if layout.pal_rects.size() != game.palette.size():
		layout.layout_palette(game.palette.size())
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
	_tap(pos)


# PORADI JE ZAVAZNE: paleta, pak tlacitko vylepseni. Klepnuti do hraciho pole
# NEDELA NIC - hrac ma vybirat barvu mimo desku, aby neztratil prehled.
func _tap(pos: Vector2) -> void:
	for i in range(layout.pal_rects.size()):
		if (layout.pal_rects[i] as Rect2).has_point(pos):
			if i < game.palette.size():
				game.select_hue(int(game.palette[i]))
			return
	if layout.up_rect.has_point(pos):
		game.buy_upgrade()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, layout.view), BG)
	if layout.field_r <= 0.0:
		return
	# KRUH PLOCHY a KRUH DOSTRELU. Dostrel je jedina geometrie hry, kterou hrac
	# potrebuje videt - je to misto, kde se rozhoduje.
	draw_arc(layout.center, layout.field_r, 0.0, TAU, 128, FIELD_LINE, 2.0)
	draw_arc(layout.center, game.tower.range_px(layout.field_r), 0.0, TAU, 96, RANGE_LINE, 1.5)
	for p in game.locks:
		draw_line(layout.center, p.pos, BEAM, 2.0)
	for p in game.pilgrims:
		_draw_pilgrim(p)
	_draw_tower()
	_draw_bar()
	_draw_palette()


func _draw_pilgrim(p: Pilgrim) -> void:
	var col: Color = Hue.color_of(p.hue)
	var r: float = layout.pilgrim_r * p.size
	# PRIRAVA (fialova po prvnim zasahu): kresli se JEN OBRYS v plne barve.
	# Hrac tak vidi, kde poutnik je, ale pozna, ze na nej ted nema cenu mirrit.
	_shape(p.hue, p.pos, r, col, p.is_ghost())
	if p.hp_frac() < 0.999:
		draw_arc(p.pos, r * 1.55, -PI * 0.5, -PI * 0.5 + TAU * p.hp_frac(), 24, TEXT, 2.0)


# TVAR BAREV. Barva nikdy neni jediny nositel informace - u sesti barev to
# plati dvojnasob (cervena se zelenou je nejcastejsi porucha barvocitu,
# fialova s modrou se pletou taky). Tvar je to, co hrac na plose opravdu cte.
func _shape(h: int, p: Vector2, r: float, col: Color, hollow: bool = false) -> void:
	var w: float = maxf(1.6, r * 0.26)
	match Hue.shape_of(h):
		"square":
			var rect := Rect2(p - Vector2(0.80 * r, 0.80 * r), Vector2(1.60 * r, 1.60 * r))
			if hollow:
				draw_rect(rect, col, false, w)
			else:
				draw_rect(rect, col, true)
		"triangle":
			var tri := PackedVector2Array([
				p + Vector2(0.0, -1.00 * r),
				p + Vector2(-0.95 * r, 0.70 * r),
				p + Vector2(0.95 * r, 0.70 * r)])
			if hollow:
				draw_polyline(_closed(tri), col, w)
			else:
				draw_colored_polygon(tri, col)
		"droplet":
			var body := PackedVector2Array([
				p + Vector2(0.0, -1.15 * r),
				p + Vector2(-0.68 * r, -0.20 * r),
				p + Vector2(-0.80 * r, 0.35 * r),
				p + Vector2(0.0, 0.95 * r),
				p + Vector2(0.80 * r, 0.35 * r),
				p + Vector2(0.68 * r, -0.20 * r)])
			if hollow:
				draw_polyline(_closed(body), col, w)
			else:
				draw_colored_polygon(body, col)
		"cross":
			var a := Rect2(p - Vector2(0.28 * r, 1.00 * r), Vector2(0.56 * r, 2.00 * r))
			var b := Rect2(p - Vector2(1.00 * r, 0.28 * r), Vector2(2.00 * r, 0.56 * r))
			if hollow:
				draw_rect(a, col, false, w)
				draw_rect(b, col, true)
				draw_rect(a, BG, true)
			else:
				draw_rect(a, col, true)
				draw_rect(b, col, true)
		"diamond":
			var d := PackedVector2Array([
				p + Vector2(0.0, -0.95 * r),
				p + Vector2(0.95 * r, 0.0),
				p + Vector2(0.0, 0.95 * r),
				p + Vector2(-0.95 * r, 0.0)])
			if hollow:
				draw_polyline(_closed(d), col, w)
			else:
				draw_colored_polygon(d, col)
		_:
			# KRUH (stribrna). Dutina nema smysl, ale obrys ano.
			if hollow:
				draw_arc(p, 0.85 * r, 0.0, TAU, 28, col, w)
			else:
				draw_circle(p, 0.92 * r, col)


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(pts)
	out.append(pts[0])
	return out


func _draw_tower() -> void:
	var c: Vector2 = layout.center
	var tr: float = layout.tower_r
	draw_circle(c, tr, TOWER_BODY)
	# PRSTENEC ZVOLENE BARVY. Meni se jen barva prstence, telo veze zustava -
	# vez je porad ta sama vec, jen se prebiji.
	draw_arc(c, tr * 0.92, 0.0, TAU, 48, Hue.color_of(game.tower.hue), maxf(2.0, tr * 0.13))
	_shape(game.tower.hue, c, tr * 0.52, Hue.color_of(game.tower.hue))
	# TECKY STUPNE uvnitr veze (jeden az tri).
	var dr: float = maxf(1.6, tr * 0.10)
	for i in range(game.tower.level):
		var dx: float = (float(i) - (float(game.tower.level) - 1.0) * 0.5) * dr * 3.0
		draw_circle(c + Vector2(dx, tr * 0.70), dr, TOWER_DOT)


func _draw_bar() -> void:
	var f: Font = ThemeDB.fallback_font
	var fs: int = layout.font_px
	var pad: float = maxf(8.0, layout.bar_h * 0.18)
	draw_string(f, Vector2(pad, layout.bar_h * 0.5 + fs * 0.36),
		"Vlna %d/%d    Životy %d    Zlato %d"
		% [game.wave, Game.WAVE_MAX, game.lives, game.gold],
		HORIZONTAL_ALIGNMENT_LEFT, layout.up_rect.position.x - pad, fs, TEXT)
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
		draw_string(f, Vector2(0.0, layout.center.y),
			line, HORIZONTAL_ALIGNMENT_CENTER, layout.view.x, fs * 3, TEXT)


# PALETA BAREV DOLE. Je to jedine misto, kam hrac klika - proto nema vyznam
# klepat do pole. Zvolena barva je znacena SVETLYM RAMECKEM a plnym podkladem;
# neaktivni jsou ztlumene, ale jejich TVAR je porad v plne barve.
func _draw_palette() -> void:
	for i in range(layout.pal_rects.size()):
		if i >= game.palette.size():
			break
		var h: int = int(game.palette[i])
		var r: Rect2 = layout.pal_rects[i]
		var active: bool = (h == game.tower.hue)
		var col: Color = Hue.color_of(h)
		if active:
			draw_rect(r, Color(col.r, col.g, col.b, 0.30), true)
			draw_rect(r, Color(0.92, 0.90, 0.86), false, 3.0)
		else:
			draw_rect(r, Color(col.r, col.g, col.b, PAL_IDLE * 0.35), true)
			draw_rect(r, Color(col.r, col.g, col.b, PAL_IDLE), false, 2.0)
		# TVAR JE VZDY V PLNE BARVE - je to jediny nositel informace, ktery
		# funguje i pri poruse barvocitu.
		_shape(h, r.position + r.size * 0.5, minf(r.size.x, r.size.y) * 0.30, col)
