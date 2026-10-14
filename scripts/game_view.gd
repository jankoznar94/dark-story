extends Node2D

# KRESLENI A DOTYK. Hra sama (`game.gd`) je bez uzlu a nic nekresli - tady se
# jen cte stav a kresli. Jedna plocha, jeden hit-test, zadne Button uzly,
# zadny theme, zadny hover ani focus: plochy strojovy vzhled.
#
# OBRAZOVKY. `Menu` vi, ktera je otevrena (MENU / SETTINGS / BATTLE) a podle
# toho se kresli i vyhodnocuje vstup. Hra se krokuje JEN v bitve - jinak by
# pod menu bezela partie, kterou hrac jeste nezacal.

const BG := Color(0.055, 0.052, 0.062)
const RANGE_LINE := Color(0.28, 0.27, 0.30)
const TOWER_BODY := Color(0.11, 0.105, 0.115)
const TOWER_DOT := Color(0.90, 0.88, 0.84)
const TEXT := Color(0.86, 0.85, 0.82)
const DIM := Color(0.50, 0.49, 0.52)
const BEAM := Color(0.93, 0.91, 0.86)
const GLYPH := Color(0.09, 0.085, 0.09)
# MENU: podklad tlacitka je o stupen svetlejsi nez pozadi, ramecek zlaty u
# prvniho (HRAT) a sedy u ostatnich - hrac vidi, co je hlavni cesta.
const MENU_BG := Color(0.135, 0.125, 0.11)
const MENU_EDGE := Color(0.72, 0.70, 0.62)
const MENU_EDGE_FIRST := Color(0.78, 0.62, 0.30)
# ZTLUMENI NEAKTIVNÍCH TALCÍČEK PALETY. Driv to bylo 42 % a zeme se vzduchem
# v tom ztlumeni skoro zmizely (zmereno proti pozadi) - hrac pak nevidi, na co
# ma klepnout. Tvar je proto VZDY v plne barve, ztlumuje se jen podklad.
const PAL_IDLE := 0.55

# USPORNE VYKRESLOVANI (nastaveni hrace). Hra se jinak kresli v NATIVNIM
# rozliseni displeje, coz na telefonu (DPR 2-3) znamena nekolikanasobne vic
# pixelu nez na stolnim displeji - a kdyz se snimek nevejde do 16,7 ms, pohyb
# poutniku skube. Male platno se na displej roztahne (`MODE_VIEWPORT` - v
# `CANVAS_ITEMS` by se zmensily jen souradnice a obraz by se porad
# rasterizoval do plneho rozliseni, takze zadna uspora).
const RENDER_W := 960
const RENDER_H := 600

var game: Game
var layout: ScreenLayout
var menu := Menu.new()
var settings := Settings.new()
var _pressed: bool = false
# DOTAZ PRI ODCHODU Z BOJE. Dokud je otevreny, partie se NEKROKUJE - hrac se
# nema rozhodovat, zatimco mu umiraji poutnici.
var leave_ask: bool = false


func _ready() -> void:
	layout = ScreenLayout.new()
	game = Game.new()
	settings.load_from_disk()
	menu.web = OS.has_feature("web")
	if menu.web:
		menu.load_build_id()
	_apply_render_scale()
	_refield()
	get_viewport().size_changed.connect(_refield)


func _refield() -> void:
	# `layout.update` pocita VSE, co jde z velikosti okna (menu, nastaveni,
	# dotaz pri odchodu) - tady se doplni jen to, co vi az hra: pocet barev.
	layout.update(get_viewport_rect().size)
	game.set_field(layout.field_r, layout.tower_r, layout.center)
	layout.layout_palette(game.palette.size())


func _process(dt: float) -> void:
	if menu.is_battle() and not leave_ask:
		game.step(dt)
	_pull_js_state()
	# POCET BAREV SE V PRUBEHU HRY MENI (barvy pribyvaji). Kdyz se paleta
	# roztahne, musi se prekreslit i tlacitka - jinak by hrac videl barvu,
	# ktera se neda zmacknout.
	if layout.pal_rects.size() != game.palette.size():
		layout.layout_palette(game.palette.size())
	queue_redraw()


# =========================================================================
# STAV Z PROHLIZECE
#
# Otisk buildu a vysledek aktualizace posila prohlizec do globalnich promennych
# a hra si je VYCTE. `JavaScriptBridge.create_callback` se sice podari
# zaregistrovat (v prohlizeci je videt jako funkce), ale zavolani z JS do hry
# NEDOJDE - v Chromiu po rucnim `setVersion('PROBE99')` zustal v menu otisk
# "dev". Necte se to kazdy snimek: staci nekolikrat za sekundu.
# =========================================================================

const JS_POLL_S := 0.25

var _poll_left: float = 0.0


func _pull_js_state() -> void:
	if not menu.web:
		return
	_poll_left -= get_process_delta_time()
	if _poll_left > 0.0:
		return
	_poll_left = JS_POLL_S
	menu.pull_js_state()


# USPORNE ROZHLEDNI. NIKDY NEPRIRAZUJE, KDYBY TO ZHORSILO: na displeji mensim
# nez cilove platno (nebo jen o chlup vetsim) zustava nativni rozliseni - jinak
# by se kreslilo do vetsiho platna, nez je obrazovka.
func _apply_render_scale() -> void:
	var w: Window = get_window()
	if w == null:
		return
	var size: Vector2i = w.size
	var big: bool = size.x >= RENDER_W * 1.2 and size.y >= RENDER_H * 1.2
	if settings.lowres and big:
		w.content_scale_size = Vector2i(RENDER_W, RENDER_H)
		w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		w.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	else:
		w.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED


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


# PORADI JE ZAVAZNE: dotaz pri odchodu stoji NAD VSIM vstupem (hrac na nej ma
# odpovedet), pak obrazovka, ktera je otevrena. Klepnuti do hraciho pole
# NEDELA NIC - hrac ma vybirat barvu mimo desku, aby neztratil prehled.
func _tap(pos: Vector2) -> void:
	if leave_ask:
		_handle_leave_tap(pos)
		return
	if menu.is_menu():
		_handle_menu_tap(pos)
		return
	if menu.is_settings():
		_handle_settings_tap(pos)
		return
	_handle_battle_tap(pos)


# =========================================================================
# MENU
# =========================================================================

# AKCE SE VYHODNOCUJE PRES JMENO (`Menu.MENU_ACTIONS`), ne podle poradi -
# prehozeni tlacitek v seznamu tak nikdy neprehodi, co ktery dela.
func _handle_menu_tap(pos: Vector2) -> void:
	for i in range(layout.menu_rects.size()):
		if not (layout.menu_rects[i] as Rect2).has_point(pos):
			continue
		if i >= Menu.MENU_ACTIONS.size():
			return
		match String(Menu.MENU_ACTIONS[i]):
			"battle":
				start_battle()
			"settings":
				menu.open_settings()
			"update":
				menu.request_update()
		return


# NOVA PARTIE. Hra se zaklada ZNOVU (ne "reset" na miste): hrac, ktery se
# vratil do menu a zmackl HRAT, musi dostat cistou desku, ne zbytek te
# predchozi.
func start_battle() -> void:
	leave_ask = false
	game = Game.new()
	_refield()
	menu.open_battle()


func _handle_settings_tap(pos: Vector2) -> void:
	if layout.settings_row.has_point(pos):
		settings.toggle_lowres()
		_apply_render_scale()
		_refield()
		return
	if layout.settings_back.has_point(pos):
		menu.open_menu()


# =========================================================================
# ODCHOD Z BOJE PREDCASNE
#
# Hra se PTÁ, protoze rozehrana partie je prace. Dotaz partii POZASTAVI
# (viz `_process`) - bez toho by se hrac rozhodoval, zatimco mu umiraji
# poutnici. Dohrana partie se neptá: tam uz neni o co přijít.
# =========================================================================

func ask_leave() -> void:
	if game.is_over():
		leave_battle()
		return
	leave_ask = true


func _handle_leave_tap(pos: Vector2) -> void:
	if layout.leave_yes.has_point(pos):
		leave_battle()
		return
	if layout.leave_no.has_point(pos):
		leave_ask = false
		return
	# KLEPNUTI MIMO ODPOVED NIC NEDELA: dotaz neni hlaseni, hrac na nej ma
	# odpovedet.


func leave_battle() -> void:
	leave_ask = false
	menu.open_menu()


# =========================================================================
# BITVA
# =========================================================================

func _handle_battle_tap(pos: Vector2) -> void:
	for i in range(layout.pal_rects.size()):
		if (layout.pal_rects[i] as Rect2).has_point(pos):
			if i < game.palette.size():
				game.select_hue(int(game.palette[i]))
			return
	if layout.up_rect.has_point(pos):
		game.buy_upgrade()
		return
	if layout.hud_menu.has_point(pos):
		ask_leave()


# =========================================================================
# KRESLENI
# =========================================================================

func _draw() -> void:
	if menu.is_menu():
		_draw_menu()
		return
	if menu.is_settings():
		_draw_settings()
		return
	draw_rect(Rect2(Vector2.ZERO, layout.view), BG)
	if layout.field_r <= 0.0:
		return
	# KRUH DOSTRELU. Je to jedina geometrie, kterou hrac potrebuje videt - misto,
	# kde se rozhoduje. SPAWNOVACI KRUH se NEKRESLI (Jan: "Vnější kruh nemá být
	# viditelný a má být pomyslný"): je vetsi nez displej a poutnici z nej
	# vchazeji z boku a shora, takze by z nej byl jen oblouk pres celou obrazovku.
	draw_arc(layout.center, game.tower.range_px(layout.field_r), 0.0, TAU, 96, RANGE_LINE, 1.5)
	for p in game.locks:
		draw_line(layout.center, p.pos, BEAM, 2.0)
	for p in game.pilgrims:
		_draw_pilgrim(p)
	_draw_tower()
	_draw_bar()
	_draw_palette()
	if leave_ask:
		_draw_leave()


# PISMO, KTERE SE VEJDE. Stavovy text v hornim pruhu ma pevne misto (vlevo od
# tlacitek) a na uzke obrazovce je puvodni velikost vetsi nez to misto - bez
# zmenseni by se text utnul o tlacitko. Radsi mensi pismo nez utnute slovo.
func _fit_px(s: String, width: float, max_px: int, min_px: int = 10) -> int:
	if width <= 1.0:
		return min_px
	var f: Font = ThemeDB.fallback_font
	var px: int = max_px
	while px > min_px and f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > width:
		px -= 1
	return px


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


# TEXT V PRUHU. Vzdy na stred sveho obdelniku - `draw_string` ma sirku, do
# ktere se vejde, takze se nikdy nesmi kreslit do sirky ciziho tlacitka.
func _label(s: String, r: Rect2, px: int, col: Color, dy: float = 0.0) -> void:
	var f: Font = ThemeDB.fallback_font
	draw_string(f, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + float(px) * 0.36 + dy),
		s, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, px, col)


func _draw_bar() -> void:
	var f: Font = ThemeDB.fallback_font
	var pad: float = maxf(8.0, layout.bar_h * 0.18)
	var state: String = "Vlna %d/%d    Životy %d    Zlato %d" \
		% [game.wave, Game.WAVE_MAX, game.lives, game.gold]
	var fs: int = _fit_px(state, layout.bar_text_w, layout.font_px)
	draw_string(f, Vector2(pad, layout.bar_h * 0.5 + float(fs) * 0.36),
		state, HORIZONTAL_ALIGNMENT_LEFT, layout.bar_text_w, fs, TEXT)
	# TLACITKO MENU (odchod z partie). Kresli se VZDY, i po dohrani - jinak by
	# hrac po prohre nemel jak odejit.
	var mr: Rect2 = layout.hud_menu
	draw_rect(mr, TOWER_BODY, true)
	draw_rect(mr, DIM, false, 2.0)
	_label("MENU", mr, _fit_px("MENU", mr.size.x - 8.0, layout.font_px, 10), TEXT)
	# TLACITKO VYLEPSENI
	var r: Rect2 = layout.up_rect
	var can: bool = game.tower.can_upgrade() and game.gold >= game.tower.upgrade_cost()
	var bc: Color = TEXT if can else DIM
	draw_rect(r, TOWER_BODY, true)
	draw_rect(r, bc, false, 2.0)
	var label: String = ("Vylepšit %d" % game.tower.upgrade_cost()) if game.tower.can_upgrade() else "Max"
	_label(label, r, _fit_px(label, r.size.x - 8.0, layout.font_px, 10), bc)
	var note: String = game.last_note()
	if note != "":
		draw_string(f, Vector2(pad, layout.bar_h + float(fs) * 1.6), note,
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


# =========================================================================
# MENU A NASTAVENI
# =========================================================================

# Prvni obrazovka. Plochy strojovy design jako zbytek hry - zadne karty,
# zadne efekty. Podbarveni je naznak puvodnich zelek, aby menu a hra
# vypadaly jako jedna vec.
func _draw_menu() -> void:
	draw_rect(Rect2(Vector2.ZERO, layout.view), BG)
	for i in range(9):
		var t: float = float(i) / 8.0
		var y: float = t * layout.view.y
		draw_line(Vector2(0.0, y + 12.0), Vector2(layout.view.x, y - 18.0),
			Color(0.145, 0.135, 0.115, 0.55), 1.0)
	var cx: float = layout.view.x * 0.5
	_label(Menu.TITLE, Rect2(0.0, layout.menu_title_y - float(layout.menu_title_px) * 0.8,
		layout.view.x, float(layout.menu_title_px)), layout.menu_title_px, Color(0.90, 0.87, 0.80))
	_label(Menu.SUBTITLE, Rect2(0.0, layout.menu_title_y + float(layout.menu_title_px) * 0.5,
		layout.view.x, float(layout.menu_sub_px)), layout.menu_sub_px, Color(0.58, 0.55, 0.49))
	for i in range(layout.menu_rects.size()):
		if i >= Menu.MENU_ITEMS.size():
			break
		var r: Rect2 = layout.menu_rects[i]
		var accent: Color = MENU_EDGE_FIRST if i == 0 else MENU_EDGE
		draw_rect(r, MENU_BG, true)
		draw_rect(r, Color(accent.r, accent.g, accent.b, 0.55), false, 2.0)
		# POPISEK A PODTITULEK jsou dva radky jednoho tlacitka - podtitulek
		# neni druhe tlacitko, takze se macka cely obdelnik.
		var item: String = String(Menu.MENU_ITEMS[i])
		var ipx: int = _fit_px(item, r.size.x - 16.0, layout.menu_item_px, 13)
		var sub: String = String(Menu.MENU_SUBS[i])
		var spx: int = _fit_px(sub, r.size.x - 16.0, layout.menu_sub_px, 10)
		draw_string(ThemeDB.fallback_font,
			Vector2(r.position.x, r.position.y + r.size.y * 0.52),
			item, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, ipx, Color(0.90, 0.87, 0.80))
		draw_string(ThemeDB.fallback_font,
			Vector2(r.position.x, r.position.y + r.size.y * 0.86),
			sub, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, spx, Color(0.56, 0.53, 0.48))
	if not menu.update_note.is_empty():
		_label(menu.update_note, Rect2(layout.view.x * 0.05, layout.menu_note_y,
			layout.view.x * 0.9, float(layout.menu_sub_px) * 1.4),
			layout.menu_sub_px, Color(0.72, 0.70, 0.62))
	# OTAZK BUILDU. Bez nej se neda poznat, jestli hra po aktualizaci opravdu
	# bezi z nove verze, nebo ji jeste drzi cache service workera. Je to mala
	# informace v rohu, ne ovladaci prvek.
	_label("build %s" % menu.build_id, Rect2(0.0, layout.view.y - float(layout.menu_sub_px) * 2.0,
		layout.view.x, float(layout.menu_sub_px)), layout.menu_sub_px, Color(0.42, 0.40, 0.36))


func _draw_settings() -> void:
	draw_rect(Rect2(Vector2.ZERO, layout.view), BG)
	_label("NASTAVENÍ", Rect2(0.0, layout.settings_row.position.y - float(layout.menu_title_px) * 1.6,
		layout.view.x, float(layout.menu_title_px)), layout.menu_title_px, Color(0.90, 0.87, 0.80))
	# HODNOTA JE TEXT, TLACITKO JEN TO, CO SE MACKA: cely radek je prepinac,
	# takze se popisek kresli vlevo a hodnota vpravo - ramecek je jeden.
	var r: Rect2 = layout.settings_row
	var f: Font = ThemeDB.fallback_font
	var px: int = _fit_px("Jakost vykreslování", r.size.x * 0.6, layout.menu_item_px, 12)
	draw_rect(r, MENU_BG, true)
	draw_rect(r, Color(MENU_EDGE.r, MENU_EDGE.g, MENU_EDGE.b, 0.55), false, 2.0)
	draw_string(f, Vector2(r.position.x + 12.0, r.position.y + r.size.y * 0.5 + float(px) * 0.36),
		"Jakost vykreslování", HORIZONTAL_ALIGNMENT_LEFT, r.size.x * 0.6, px, Color(0.90, 0.87, 0.80))
	var val: String = settings.lowres_text()
	var vpx: int = _fit_px(val, r.size.x * 0.32 - 12.0, layout.menu_item_px, 12)
	draw_string(f, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + float(vpx) * 0.36),
		val, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 12.0, vpx, Color(0.78, 0.62, 0.30))
	var br: Rect2 = layout.settings_back
	draw_rect(br, MENU_BG, true)
	draw_rect(br, Color(MENU_EDGE.r, MENU_EDGE.g, MENU_EDGE.b, 0.55), false, 2.0)
	_label("ZPĚT", br, _fit_px("ZPĚT", br.size.x - 16.0, layout.menu_item_px, 13), Color(0.90, 0.87, 0.80))


# DOTAZ PRI ODCHODU. Podbarvi cely displej, aby bylo videt, ze hra stoji.
func _draw_leave() -> void:
	draw_rect(Rect2(Vector2.ZERO, layout.view), Color(0.03, 0.028, 0.034, 0.72), true)
	var b: Rect2 = layout.leave_box
	draw_rect(b, MENU_BG, true)
	draw_rect(b, Color(MENU_EDGE.r, MENU_EDGE.g, MENU_EDGE.b, 0.7), false, 2.0)
	var px: int = _fit_px("Opravdu ukončit rozehranou partii?",
		b.size.x - 24.0, layout.menu_item_px, 12)
	_label("Opravdu ukončit rozehranou partii?",
		Rect2(b.position.x, b.position.y + b.size.y * 0.16, b.size.x, float(px) * 1.6),
		px, Color(0.90, 0.87, 0.80))
	# UKONCIT je cervene, ZPET DO HRY zelene: hrac vidi, ktera odpoved ho
	# vrati do hry a ktera ho o partii pripravi.
	_label("UKONČIT", layout.leave_yes,
		_fit_px("UKONČIT", layout.leave_yes.size.x - 12.0, layout.menu_item_px, 12),
		Color(0.85, 0.42, 0.36))
	_label("ZPĚT DO HRY", layout.leave_no,
		_fit_px("ZPĚT DO HRY", layout.leave_no.size.x - 12.0, layout.menu_item_px, 12),
		Color(0.65, 0.78, 0.60))
	draw_rect(layout.leave_yes, Color(0.85, 0.42, 0.36, 0.45), false, 2.0)
	draw_rect(layout.leave_no, Color(0.65, 0.78, 0.60, 0.45), false, 2.0)
