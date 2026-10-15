extends Node2D

# KRESLENI A DOTYK. Hra sama (`game.gd`) je bez uzlu a nic nekresli - tady se
# jen cte stav a kresli. Zadne Button uzly, zadny theme, zadny hover ani
# focus: plochy strojovy vzhled.
#
# OBRAZOVKY. `Menu` vi, ktera je otevrena (MENU / UPRAVY / SETTINGS / BITVA)
# a podle toho se kresli i vyhodnocuje vstup.
#
# DVE MISTA, KDE SE NAKUPUJE:
#   * V BITVE (panel u spodniho okraje) - docasne kroky za ZLATO, kazdy level
#     znovu. Panel je otevreny PORAD a hra se pod nim NEZASTAVUJE.
#   * V MENU (obrazovka "UPRAVY") - permanentni stupne za BODY.
# Oba panely kresli STEJNY predpis (`_draw_card` + `_draw_grid`), takze se
# nemohou rozejit ani popiskem, ani cenou.

const BG := Color(0.055, 0.052, 0.062)
const TOWER_BODY := Color(0.11, 0.105, 0.115)
const TOWER_DOT := Color(0.90, 0.88, 0.84)
const TEXT := Color(0.86, 0.85, 0.82)
const DIM := Color(0.50, 0.49, 0.52)
const BEAM := Color(0.93, 0.91, 0.86)
const GLYPH := Color(0.09, 0.085, 0.09)
const MENU_BG := Color(0.135, 0.125, 0.11)
const MENU_EDGE := Color(0.72, 0.70, 0.62)
const MENU_EDGE_FIRST := Color(0.78, 0.62, 0.30)
const PAL_IDLE := 0.72
# PANEL: podklad je o stupen svetlejsi nez pole a ramecek tmavy, aby se daly
# od sebe poznat tri vrstvy (pole, panel, tab).
const CARD_BG := Color(0.095, 0.090, 0.100)
const CARD_ROW := Color(0.125, 0.118, 0.128)
const CARD_EDGE := Color(0.34, 0.33, 0.36)
# ZIVOTY VEZE: zelena dokud drzi, cervena pod tretinou. Barva NENI jediny
# nositel - cislo je i v hornim pruhu.
const HP_GOOD := Color(0.62, 0.76, 0.56)
const HP_MID := Color(0.86, 0.76, 0.40)
const HP_LOW := Color(0.85, 0.42, 0.36)

# USPORNE VYKRESLOVANI (nastaveni hrace) - viz puvodni poznamka.
const RENDER_W := 960
const RENDER_H := 600

# KATEGORIE V BITVE: specialy se za zlato NEKUPUJI (jsou jen permanentni),
# takze jejich tab v bitve nema co nabidnout - a tab, ktery nic nenabizi, je
# pro hrace lez.
const SHOP_CATS := [Upgrades.CAT_OFF, Upgrades.CAT_DEF, Upgrades.CAT_ECO]

var game: Game
var layout: ScreenLayout
var menu := Menu.new()
var settings := Settings.new()
var _pressed: bool = false
# DOTAZ PRI ODCHODU Z BOJE. Dokud je otevreny, partie se NEKROKUJE - hrac se
# nema rozhodovat, zatimco mu umiraji poutnici.
var leave_ask: bool = false
var shop_cat: int = 0
var upg_cat: int = 0
# STRANKA VYBERU LEVELU. Strankuje se jen tehdy, kdyz je odemcenych levelu vic
# nez 12; rozvrzeni si ji drzi taky (`layout.lvl_page`), aby klepnuti pocitalo
# s tim, co je na obrazovce.
var lvl_page: int = 0


func _ready() -> void:
	layout = ScreenLayout.new()
	game = Game.new()
	game.profile.load_from_disk()
	game.start_level(game.profile.level)
	settings.load_from_disk()
	menu.web = OS.has_feature("web")
	if menu.web:
		menu.load_build_id()
	_apply_render_scale()
	_refield()
	get_viewport().size_changed.connect(_refield)


# DIALOG MA JEDNU NEBO DVE ODPOVEDI - rozvrzeni se proto prelozi podle toho,
# ktery dialog je prave otevreny. Bez toho by "ZPET DO HRY" u dotazu na
# ukonceni neexistovalo (a klepnuti by nikam nevedlo).
func _sync_dialogs() -> void:
	layout.dialog_panel(leave_ask or (menu.is_battle() and game.phase == "won"))


func _refield() -> void:
	layout.update(get_viewport_rect().size)
	game.set_field(layout.field_r, layout.unit_r, layout.center)
	layout.layout_palette(game.palette.size())
	_sync_shop_shape()
	_sync_dialogs()


# POCET RADKU PANELU SE MENI S KATEGORII. Rozvrzeni si ho musi vzit z TOHO,
# co se opravdu kresli - jinak by tlacitka "+" sedela na radcich jine
# kategorie (a klepalo by se na neco jineho, nez hrac vidi).
func _sync_shop_shape() -> void:
	var want_tabs: int = SHOP_CATS.size()
	var want_cells: int = _shop_stats().size()
	var moved: bool = false
	if layout.shop_tab_count != want_tabs or layout.shop_cell_count != want_cells:
		layout.set_shop_shape(want_tabs, maxi(1, want_cells))
		moved = true
	# MENU - UPRAVY: kategorie ma 4, 3, 3 nebo 4 parametry, takze i mrizka se
	# musi prelozit pri kazdem prepnuti tabu.
	var want_upg: int = _upg_stats().size()
	if layout.upg_cell_count != want_upg:
		layout.set_upg_shape(maxi(1, want_upg))
	# PANEL SE PRELOZIL = HERNI PLOCHA SE MOHLA POHNOUT. Hra si ji musi vzit
	# znovu, jinak by stavela poutniky podle starych cisel.
	if moved:
		game.set_field(layout.field_r, layout.unit_r, layout.center)


func _shop_stats() -> Array:
	# JEN STATY, KTERE JDOU V BITVE KOUPIT. Stat s `temp_max` 0 (dostrel,
	# specialy) by jinak zabiral bunku, ukazoval cenu 0 a "MAX" - hrac by
	# videl tlacitko, ktere nic nedela a nerekne proc.
	var out: Array = []
	for s in Upgrades.stats_in(String(SHOP_CATS[clampi(shop_cat, 0, SHOP_CATS.size() - 1)])):
		if Upgrades.temp_max(String(s["id"])) > 0:
			out.append(s)
	return out


func _upg_stats() -> Array:
	var cat: String = String(Upgrades.CATEGORIES[clampi(upg_cat, 0, Upgrades.CATEGORIES.size() - 1)]["id"])
	return Upgrades.stats_in(cat)


# PODLE CEHO SE ROZHODUJE, JESTLI HRA STOJI. Jedno misto - kdyby si to hlídalo
# vic funkci, stacilo by jedno opomenute volani a hra by pod panelem bezela.
# PANEL S UPGRADY TU NENI: stoji mimo herni plochu a hrac pod nim nakupuje ZA
# POCHODU (Jan, Oct 2026).
func is_halted() -> bool:
	return leave_ask or game.is_over()


func _process(dt: float) -> void:
	if menu.is_battle() and not is_halted():
		game.step(dt)
	_pull_js_state()
	if layout.pal_rects.size() != game.palette.size():
		layout.layout_palette(game.palette.size())
	_sync_shop_shape()
	_sync_dialogs()
	queue_redraw()


# =========================================================================
# STAV Z PROHLIZECE (viz puvodni poznamka: callback z JS do hry NEDOJDE)
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
# na stisk (pohyb nema akci) a stav se resetuje pri pusteni.
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


# PORADI JE ZAVAZNE: to, co stoji NAD VSIM (dialog), je prvni. Hrac na dotaz
# ma odpovedet, ne ho odklepnout necim jinym.
func _tap(pos: Vector2) -> void:
	if leave_ask:
		_handle_leave_tap(pos)
		return
	if menu.is_battle() and game.is_over():
		_handle_end_tap(pos)
		return
	if menu.is_menu():
		_handle_menu_tap(pos)
		return
	if menu.is_levels():
		_handle_levels_tap(pos)
		return
	if menu.is_settings():
		_handle_settings_tap(pos)
		return
	if menu.is_upgrades():
		_handle_upgrades_tap(pos)
		return
	_handle_battle_tap(pos)


# =========================================================================
# MENU
# =========================================================================

func _handle_menu_tap(pos: Vector2) -> void:
	for i in range(layout.menu_rects.size()):
		if not (layout.menu_rects[i] as Rect2).has_point(pos):
			continue
		if i >= Menu.MENU_ACTIONS.size():
			return
		match String(Menu.MENU_ACTIONS[i]):
			"battle":
				start_battle()
			"levels":
				open_levels()
			"upgrades":
				upg_cat = 0
				layout.layout_upgrades()
				menu.open_upgrades()
			"settings":
				menu.open_settings()
			"update":
				menu.request_update()
		return


# NOVA PARTIE. Hra zacina na NEJVYSSIM odemcenem levelu; profil (body
# i permanentni upgrady) zustava - to je cely smysl permanentnich bonusu.
func start_battle() -> void:
	leave_ask = false
	game.start_level(game.profile.level)
	_refield()
	menu.open_battle()


# VYBER LEVELU. Otevira se na strance s NEJVYSSIM odemcenym levelem - tam hrac
# pokracuje, takze ho zajima prvni. Klepnuti na dlazdici spusti PRESNE ten
# level (i vyhrany) a profil se tim nemaze.
func open_levels() -> void:
	lvl_page = (game.profile.level - 1) / ScreenLayout.LVL_PER_PAGE
	layout.set_levels(game.profile.level, lvl_page)
	lvl_page = layout.lvl_page
	menu.open_levels()


func _handle_levels_tap(pos: Vector2) -> void:
	for i in range(layout.lvl_tiles.size()):
		if not (layout.lvl_tiles[i] as Rect2).has_point(pos):
			continue
		var n: int = layout.lvl_page * ScreenLayout.LVL_PER_PAGE + i + 1
		if n > game.profile.level:
			return
		leave_ask = false
		game.start_level(n)
		_refield()
		menu.open_battle()
		return
	if layout.lvl_back.has_point(pos):
		menu.open_menu()
		return
	if layout.lvl_prev.has_point(pos) and layout.lvl_page > 0:
		lvl_page = layout.lvl_page - 1
		layout.set_levels(game.profile.level, lvl_page)
		return
	if layout.lvl_next.has_point(pos) and layout.lvl_page < layout.lvl_pages - 1:
		lvl_page = layout.lvl_page + 1
		layout.set_levels(game.profile.level, lvl_page)


func _handle_settings_tap(pos: Vector2) -> void:
	if layout.settings_row.has_point(pos):
		settings.toggle_lowres()
		_apply_render_scale()
		_refield()
		return
	if layout.settings_back.has_point(pos):
		menu.open_menu()


# =========================================================================
# UPRAVY V MENU (permanentni, za body)
# =========================================================================

func _handle_upgrades_tap(pos: Vector2) -> void:
	for i in range(layout.upg_tabs.size()):
		if (layout.upg_tabs[i] as Rect2).has_point(pos):
			# Kategorie se prekresli HNAD: kazda ma jiny pocet parametru
			# (4, 3, 3, 4), takze by bunky zustaly rozvrzene pro tu predchozi.
			upg_cat = i
			_sync_shop_shape()
			return
	for i in range(layout.upg_cells.size()):
		if (layout.upg_cells[i] as Rect2).has_point(pos):
			var stats: Array = _upg_stats()
			if i < stats.size():
				game.buy_perm(String(stats[i]["id"]))
			return
	if layout.upg_back.has_point(pos):
		menu.open_menu()
		return
	# KLEPNUTI MIMO PANEL = ZPET (na telefonu je to nejrychlejsi odchod).
	if not layout.upg_panel.has_point(pos):
		menu.open_menu()


# =========================================================================
# ODCHOD Z BOJE PREDCASNE
# =========================================================================

func ask_leave() -> void:
	leave_ask = true
	_sync_dialogs()


func _handle_leave_tap(pos: Vector2) -> void:
	if layout.dlg_a.has_point(pos):
		_do_leave()
		return
	if layout.dlg_b.has_point(pos):
		leave_ask = false
		return
	# KLEPNUTI MIMO ODPOVED NIC NEDELA: dotaz neni hlaseni, hrac na nej ma
	# odpovedet.


func _do_leave() -> void:
	leave_ask = false
	menu.open_menu()


# =========================================================================
# KONEC LEVELU: VYHRA A PROHRA
#
# Vyhra NENI konec hry: hrac si v klidu nakoupi permanentni upgrady a jde na
# dalsi level. Prohra vraci do menu - zlato z rozehraneho levelu propada,
# upgrady i body zustavaji (Jan, Oct 2026).
# =========================================================================

func _handle_end_tap(pos: Vector2) -> void:
	if game.phase == "won":
		if layout.dlg_a.has_point(pos):
			game.next_level()
			_refield()
			return
		if layout.dlg_b.has_point(pos):
			_do_leave()
		return
	# PROHRA: jedina odpoved je navrat do menu.
	if layout.dlg_a.has_point(pos):
		_do_leave()


# =========================================================================
# BITVA
# =========================================================================

func _handle_battle_tap(pos: Vector2) -> void:
	# PAUZA / POKRAČOVAT. Je to prvni cil, na ktery klepnuti v bitve muze
	# dosahnout - kdo chce zastavit, nesmi minout.
	if layout.hud_pause.has_point(pos):
		game.toggle_pause()
		return
	if layout.hud_menu.has_point(pos):
		ask_leave()
		return
	# POD PAUZOU DESKA NEREAGUJE NA NIC (krome pauzy a MENU vys): hrac ma cas
	# premyslet, ne menit stav. Kdyby se pod pauzou dalo stavet a nakupovat,
	# hrac by si "rozmyslel" veci, ktere uz jsou davno rozhodnute.
	if game.is_paused():
		return
	for i in range(layout.pal_rects.size()):
		if (layout.pal_rects[i] as Rect2).has_point(pos):
			if i < game.palette.size():
				game.select_hue(int(game.palette[i]))
			return
	if layout.hud_menu.has_point(pos):
		ask_leave()
		return
	# PANEL S UPGRADY NENI CO OTEVIRAT ANI ZAVIRAT: stoji tam porad a klepnuti
	# mimo nej (do pole, do pruhu) nedela nic - hra bezi dal.
	for i in range(layout.shop_tabs.size()):
		if (layout.shop_tabs[i] as Rect2).has_point(pos):
			shop_cat = i
			_sync_shop_shape()
			return
	for i in range(layout.shop_cells.size()):
		if (layout.shop_cells[i] as Rect2).has_point(pos):
			var stats: Array = _shop_stats()
			if i < stats.size():
				game.buy_temp(String(stats[i]["id"]))
			return


# =========================================================================
# KRESLENI
# =========================================================================

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, layout.view), BG)
	if menu.is_menu():
		_draw_menu()
		return
	if menu.is_levels():
		_draw_levels()
		return
	if menu.is_settings():
		_draw_settings()
		return
	if menu.is_upgrades():
		_draw_upgrades()
		return
	_draw_battle()


func _draw_battle() -> void:
	if layout.field_r <= 0.0:
		return
	draw_arc(layout.center, game.range_px(), 0.0, TAU, 96, _range_color(),
		maxf(2.0, layout.unit_r * 0.014))
	for p in game.locks:
		draw_line(layout.center, p.pos, BEAM, 2.0)
	for p in game.pilgrims:
		_draw_pilgrim(p)
	_draw_tower()
	if game.is_paused() and not game.is_over() and not leave_ask:
		_draw_pause_hint()
	# STRELY SE KRESLI NAD VSIM V POLI (Jan: "Projektily musí být výraznější
	# a musí být z indexem nad zaměřováním").
	_draw_shots()
	_draw_bar()
	_draw_palette()
	# PANEL S NAKUPEM JE V BITVE PORAD - kresli se vzdy, ne "kdyz je otevreny".
	_draw_shop()
	if game.is_over():
		_draw_end()
	if leave_ask:
		_draw_leave()


# PISMO, KTERE SE VEJDE. Stavovy text v hornim pruhu ma pevne misto a na
# uzkem displeji je puvodni velikost vetsi nez to misto.
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
	# POUTNIK JDE K VEZI "OBLICEJEM" (Jan, Oct 2026). Smer bere z `p.dir`, ktery
	# je smer chuze - kdyz se zmeni chuze, tvary se otoci samy.
	_shape(p.hue, p.pos, r, col, p.is_ghost(), Shapes.facing(p.dir))
	if p.hp_frac() < 0.999:
		draw_arc(p.pos, r * 1.55, -PI * 0.5, -PI * 0.5 + TAU * p.hp_frac(), 24, TEXT, 2.0)
	# JED A LED musi byt VIDET, jinak hrac nevi, ze mu upgrady pracuji.
	if p.ice_left > 0.0:
		draw_arc(p.pos, r * 1.9, 0.0, TAU, 20, Color(0.45, 0.72, 0.90, 0.85), 2.0)
	if p.poison_left > 0.0:
		draw_arc(p.pos, r * 2.2, 0.0, TAU, 20, Color(0.55, 0.80, 0.35, 0.85), 2.0)


# TVAR BAREV. Barva nikdy neni jediny nositel informace - u sesti barev to
# plati dvojnasob (cervena se zelenou je nejcastejsi porucha barvocitu).
# `toward` = smer, kterym ma tvar hledet (u poutnika k vezi); kdyz je nulovy,
# tvary stoji rovne (runa veze, puntik v palete). Otaceni je v `Shapes`.
func _shape(h: int, p: Vector2, r: float, col: Color, hollow: bool = false,
		toward: Vector2 = Vector2.ZERO) -> void:
	var w: float = maxf(1.6, r * 0.26)
	var shape: String = Hue.shape_of(h)
	if shape == "square":
		var rect := Rect2(p - Vector2(0.80 * r, 0.80 * r), Vector2(1.60 * r, 1.60 * r))
		if hollow:
			draw_rect(rect, col, false, w)
		else:
			draw_rect(rect, col, true)
		return
	var pts: PackedVector2Array = Shapes.pts(shape, p, r, toward)
	if pts.is_empty():
		# KRUH (a cokoli neznaneho): nema se co otacet.
		if hollow:
			draw_arc(p, 0.85 * r, 0.0, TAU, 28, col, w)
		else:
			draw_circle(p, 0.92 * r, col)
		return
	if hollow:
		draw_polyline(_closed(pts), col, w)
	else:
		draw_colored_polygon(pts, col)


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(pts)
	out.append(pts[0])
	return out


# BARVA KRUHU DOSTRELU = BARVA VEZE. Ztlumena (0,62), aby kruh neprebijel
# poutniky a paprsek - je to geometrie, ne zbran.
func _range_color() -> Color:
	var col: Color = Hue.color_of(game.tower.hue)
	return Color(col.r, col.g, col.b, 0.62)


func _draw_shots() -> void:
	var col: Color = Hue.color_of(game.tower.hue)
	for s in game.shots:
		var sp: Vector2 = s["pos"]
		draw_circle(sp, game.shot_rim_r(), GLYPH)
		draw_circle(sp, game.shot_r(), col)


# VEZ. Misto stupnu ma ZIVOTY: tlusty oblouk kolem tela, barva podle toho,
# kolik jestli zbylo. Cislo je vzdy i v hornim pruhu, takze barva nikdy neni
# jediny nositel informace.
func _draw_tower() -> void:
	var c: Vector2 = layout.center
	var tr: float = layout.tower_r
	draw_circle(c, tr, TOWER_BODY)
	draw_arc(c, tr * 0.92, 0.0, TAU, 48, Hue.color_of(game.tower.hue), maxf(2.0, tr * 0.13))
	_shape(game.tower.hue, c, tr * 0.52, Hue.color_of(game.tower.hue))
	var frac: float = clampf(game.hp / maxf(1.0, game.max_hp), 0.0, 1.0)
	draw_arc(c, tr * 1.22, -PI * 0.5, -PI * 0.5 + TAU * frac, 64, _hp_color(frac),
		maxf(3.0, tr * 0.24))


func _hp_color(frac: float) -> Color:
	if frac > 0.6:
		return HP_GOOD
	if frac > 0.3:
		return HP_MID
	return HP_LOW


# =========================================================================
# HORNI PRUH A PALETA
# =========================================================================

# PAUZA PRES POLE. Hrac se diva na srdce, ne do pruhu - kdyz se hra zastavi,
# musi to videt tam, kam se diva. Text stoji NAD srdcem, ne na nem (zakryte
# srdce by hrac videl jako chybu kresleni) a je stejne zluty jako tlacitko.
func _draw_pause_hint() -> void:
	var px: int = clampi(int(layout.field_r * 0.26), 16, 52)
	var w: float = layout.field_r * 1.4
	var y: float = layout.center.y - layout.field_r * 0.80 - float(px) * 0.8
	_label("PAUZA", Rect2(layout.center.x - w * 0.5, y, w, float(px) * 1.6), px, MENU_EDGE_FIRST)


func _draw_bar() -> void:
	var pad: float = maxf(8.0, layout.bar_h * 0.18)
	var l1: String = ScreenLayout.HUD_LINE1_FMT % [game.level, game.wave, game.waves_in_level()]
	var l2: String = ScreenLayout.HUD_LINE2_FMT % [int(ceil(game.hp)), int(game.max_hp), game.gold]
	var px1: int = _fit_px(l1, layout.bar_text_w, layout.font_px)
	var px2: int = _fit_px(l2, layout.bar_text_w, layout.font_px)
	draw_string(ThemeDB.fallback_font, Vector2(pad, layout.bar_h * 0.34 + float(px1) * 0.36),
		l1, HORIZONTAL_ALIGNMENT_LEFT, layout.bar_text_w, px1, TEXT)
	draw_string(ThemeDB.fallback_font, Vector2(pad, layout.bar_h * 0.78 + float(px2) * 0.36),
		l2, HORIZONTAL_ALIGNMENT_LEFT, layout.bar_text_w, px2, DIM)
	# TLACITKO MENU (odchod z partie). Tlacitko UPGRADY tady NENI: panel
	# s nakupem je v bitve otevreny porad, takze nebylo co prepinat.
	var mr: Rect2 = layout.hud_menu
	draw_rect(mr, TOWER_BODY, true)
	draw_rect(mr, DIM, false, 2.0)
	_label("MENU", mr, _fit_px("MENU", mr.size.x - 8.0, layout.font_px, 10), TEXT)
	# PAUZA / POKRAČOVAT: jedno tlacitko, dva vyznamy. Hra bezi -> "PAUZA",
	# hra stoji -> "POKRAČOVAT" a tlacitko se prebarvi na zlatou, takze stav
	# nese barva i slovo (barva nikdy nesmi byt jedina znacka stavu). Sirka je
	# z delsiho popisku, takze se pri prepnuti nic neposune.
	var pr: Rect2 = layout.hud_pause
	var hold: bool = game.is_paused()
	draw_rect(pr, MENU_EDGE_FIRST if hold else TOWER_BODY, true)
	draw_rect(pr, MENU_EDGE_FIRST if hold else DIM, false, 2.0)
	_label("POKRAČOVAT" if hold else "PAUZA", pr,
		_fit_px("POKRAČOVAT", pr.size.x - 8.0, layout.font_px, 10),
		GLYPH if hold else TEXT)
	var note: String = game.last_note()
	if note != "":
		var npx: int = _fit_px(note, layout.view.x - 2.0 * pad, layout.font_px)
		draw_string(ThemeDB.fallback_font, Vector2(pad, layout.bar_h + float(npx) * 1.6), note,
			HORIZONTAL_ALIGNMENT_LEFT, layout.view.x - 2.0 * pad, npx, DIM)


# PALETA BAREV NAD PANELEM S UPGRADY. Tlacitko je PLNÝ KRUH v barve s rameckem
# (Jan: "jen barevný plný puntík s borderem. Žádné tvary.") a VE STREDU JE
# PISMENO BARVY (Jan, Oct 2026: "Každá barva bude mít ve středu kruhu písmeno
# podle názvu barvy... Kombinované barvy budou mít dvě písmena"). Pismeno je
# tmave (GLYPH) - na sytou barvu je to jedina barva, ktera ma vsude kontrast, a
# je to stejny jazyk jako tmavy obrys tecky strely.
func _draw_palette() -> void:
	for i in range(layout.pal_rects.size()):
		if i >= game.palette.size():
			break
		var h: int = int(game.palette[i])
		var r: Rect2 = layout.pal_rects[i]
		var col: Color = Hue.color_of(h)
		var active: bool = (h == game.tower.hue)
		var c: Vector2 = r.position + r.size * 0.5
		var rad: float = minf(r.size.x, r.size.y) * 0.5
		if active:
			draw_circle(c, rad * 0.86, col)
			draw_arc(c, rad * 0.86, 0.0, TAU, 64, Color(0.93, 0.91, 0.86), maxf(3.0, rad * 0.14))
		else:
			draw_circle(c, rad * 0.86, Color(col.r, col.g, col.b, PAL_IDLE))
			draw_arc(c, rad * 0.86, 0.0, TAU, 64, Color(col.r, col.g, col.b, 0.9), maxf(2.0, rad * 0.10))
		var lip: String = Hue.letter_of(h)
		if lip != "":
			_label(lip, r, maxi(10, int(rad * 0.94)), GLYPH)


# =========================================================================
# PANEL S NAKUPEM (SPOLECNY PRO BITVU I MENU)
# =========================================================================

func _text(s: String, r: Rect2, px: int, col: Color, align: int) -> void:
	draw_string(ThemeDB.fallback_font,
		Vector2(r.position.x, r.position.y + r.size.y * 0.5 + float(px) * 0.36),
		s, align, r.size.x, px, col)


func _label(s: String, r: Rect2, px: int, col: Color, dy: float = 0.0) -> void:
	_text(s, Rect2(r.position.x, r.position.y + dy, r.size.x, r.size.y), px, col,
		HORIZONTAL_ALIGNMENT_CENTER)


func _card_frame(r: Rect2) -> void:
	draw_rect(r, CARD_BG, true)
	draw_rect(r, CARD_EDGE, false, 2.0)


# IKONY KATEGORII (mec / stit / zlataky / hvezdicka). Nahrazuji text na tabu
# (Jan, Oct 2026: "tlacitka kategorii nahradit obrázky. Ikonami ... jednoduché,
# ale výstižné"). Soubory jsou BILE MASKY s pruhlednym pozadim - barvu dostanou
# az tady (`modulate`), takze sedi do palety jako zbytek obrazovky. Kdyz soubor
# chybi, kresli se misto ikony popisek: tab nesmi zustat prazdny.
var cat_icon_paths: Dictionary = {
	Upgrades.CAT_OFF: "res://assets/ui/cat_off.png",
	Upgrades.CAT_DEF: "res://assets/ui/cat_def.png",
	Upgrades.CAT_ECO: "res://assets/ui/cat_eco.png",
	Upgrades.CAT_SPEC: "res://assets/ui/cat_spec.png",
}
var _cat_icons: Dictionary = {}


func _cat_icon(cat_id: String) -> Texture2D:
	if not _cat_icons.has(cat_id):
		var path: String = String(cat_icon_paths.get(cat_id, ""))
		var tex: Texture2D = null
		if path != "" and ResourceLoader.exists(path):
			tex = load(path) as Texture2D
		_cat_icons[cat_id] = tex
	return _cat_icons[cat_id]


func _cat_label(cat_id: String) -> String:
	for row in Upgrades.CATEGORIES:
		if String(row["id"]) == cat_id:
			return String(row["label"])
	return cat_id


func _draw_card(panel: Rect2, tabs: Array, icons: Array, active: int, cats: Array) -> void:
	_card_frame(panel)
	for i in range(tabs.size()):
		var tr: Rect2 = tabs[i]
		var on: bool = (i == active)
		draw_rect(tr, CARD_ROW if on else CARD_BG, true)
		var col: Color = TEXT if on else DIM
		draw_rect(tr, col if on else CARD_EDGE, false, 2.0 if on else 1.0)
		var cat: String = String(cats[i]) if i < cats.size() else ""
		var tex: Texture2D = _cat_icon(cat)
		if tex != null:
			var ir: Rect2 = icons[i] if i < icons.size() else tr
			draw_texture_rect(tex, ir, false, col)
		else:
			var lb: String = _cat_label(cat)
			_label(lb, tr, _fit_px(lb, tr.size.x - 8.0, layout.font_px, 10), col)


# BUNKA UPGRADU JE CELE TLACITKO. Uvnitr jsou DVA RADKY TEXTU: nahore nazev,
# pod nim AKTUALNI HODNOTA (zlute - to je to, co se koupi zmeni) a na TOM SAMEM
# radku vpravo cena (kdyz uz je na maximu, stoji tam "MAX"). Po koupi se preepise
# jen hodnota a cena - zadna tabulka s tlacitkem na konci radku.
#
# `afford` = jestli na to hrac ma; kdyz ne, je ramecek i cena ztlumeny, ale
# castka zustava videt (jinak by hrac nevedel, na co setri).
func _draw_grid(cells: Array, stats: Array, names: Array, values: Array,
		prices: Array, afford: Array) -> void:
	for i in range(cells.size()):
		var c: Rect2 = cells[i]
		if i >= stats.size():
			# Prazdna bunka (kategorie ma lichy pocet) zustava jen jako podklad.
			draw_rect(c, CARD_BG, true)
			continue
		var col: Color = TEXT if bool(afford[i]) else DIM
		# TELO BUNKY JE O STUPEN SVETLEJSI NEZ PANEL (jako driv radek) - jinak by
		# z tlačítka byl jen ramecek na stejne barve jako podklad.
		draw_rect(c, CARD_ROW, true)
		draw_rect(c, col, false, 2.0)
		var pad: float = maxf(8.0, c.size.x * 0.05)
		var inner_w: float = c.size.x - 2.0 * pad
		var line: float = c.size.y / 2.0
		var nm: String = String(names[i])
		_text(nm, Rect2(c.position.x + pad, c.position.y, inner_w, line),
			_fit_px(nm, inner_w, layout.font_px, 10), TEXT, HORIZONTAL_ALIGNMENT_LEFT)
		# DRUHY RADEK: hodnota vlevo, cena vpravo. Cena si vezme jen tolik mista,
		# kolik opravdu potrebuje - hodnota dostane zbytek a nikdy se neprekryji.
		var pr: String = String(prices[i])
		var pr_room: float = maxf(24.0, inner_w * 0.45)
		var pr_px: int = _fit_px(pr, pr_room, layout.font_px, 10)
		var pr_w: float = layout.measure_px(pr, pr_px)
		var vl: String = String(values[i])
		var vl_w: float = maxf(10.0, inner_w - pr_w - 8.0)
		_text(vl, Rect2(c.position.x + pad, c.position.y + line, vl_w, line),
			_fit_px(vl, vl_w, layout.font_px, 10), MENU_EDGE_FIRST,
			HORIZONTAL_ALIGNMENT_LEFT)
		_text(pr, Rect2(c.position.x + pad + inner_w - pr_w, c.position.y + line, pr_w, line),
			pr_px, col, HORIZONTAL_ALIGNMENT_RIGHT)


# PANEL V BITVE: docasne kroky za zlato. Stoji porad u spodniho okraje, hra
# pod nim BEZI - proto tu neni zadny krizek na zavreni (Jan, Oct 2026).
func _draw_shop() -> void:
	# Kategorie se predavaji jako ID (ikony, ne text) - popisek se pouzije jen
	# jako zaloha, kdyby soubor s ikonou chybel.
	_draw_card(layout.shop_panel, layout.shop_tabs, layout.shop_tab_icons, shop_cat, SHOP_CATS)
	var stats: Array = _shop_stats()
	var names: Array = []
	var prices: Array = []
	var values: Array = []
	var afford: Array = []
	for s in stats:
		var id: String = String(s["id"])
		var have: int = game.temp_level(id)
		var maxed: bool = have >= Upgrades.temp_max(id)
		var c: int = Upgrades.temp_cost(id, have)
		names.append(Upgrades.label_of(id))
		values.append(Upgrades.value_text(id, game.profile.perm_level(id), have))
		prices.append("MAX" if maxed else "+%d zl." % c)
		afford.append((not maxed) and game.gold >= c)
	_draw_grid(layout.shop_cells, stats, names, values, prices, afford)


# OBRAZOVKA UPRAVY V MENU: permanentni stupne za body.
func _draw_upgrades() -> void:
	_label("UPRAVY", Rect2(0.0, upg_title_y(), layout.view.x, float(layout.menu_title_px)),
		layout.menu_title_px, Color(0.90, 0.87, 0.80))
	_label(game.profile.menu_note(), Rect2(0.0, layout.upg_note_y, layout.view.x, float(layout.font_px) * 1.4),
		layout.menu_sub_px, MENU_EDGE)
	var cats: Array = []
	for row in Upgrades.CATEGORIES:
		cats.append(String(row["id"]))
	_draw_card(layout.upg_panel, layout.upg_tabs, layout.upg_tab_icons, upg_cat, cats)
	var stats: Array = _upg_stats()
	var names: Array = []
	var prices: Array = []
	var values: Array = []
	var afford: Array = []
	for s in stats:
		var id: String = String(s["id"])
		var have: int = game.profile.perm_level(id)
		var maxed: bool = have >= Upgrades.perm_max(id)
		var c: int = Upgrades.perm_cost(id, have)
		names.append(Upgrades.label_of(id))
		values.append(Upgrades.value_text(id, have, 0))
		prices.append("MAX" if maxed else "+%d b." % c)
		afford.append((not maxed) and game.profile.body >= c)
	_draw_grid(layout.upg_cells, stats, names, values, prices, afford)
	var br: Rect2 = layout.upg_back
	draw_rect(br, MENU_BG, true)
	draw_rect(br, Color(MENU_EDGE.r, MENU_EDGE.g, MENU_EDGE.b, 0.55), false, 2.0)
	_label("ZPĚT", br, _fit_px("ZPĚT", br.size.x - 16.0, layout.menu_item_px, 13), Color(0.90, 0.87, 0.80))


func upg_title_y() -> float:
	return maxf(6.0, layout.upg_panel.position.y - float(layout.menu_title_px) * 1.5)


# =========================================================================
# MENU A NASTAVENI
# =========================================================================

func _draw_menu() -> void:
	for i in range(9):
		var t: float = float(i) / 8.0
		var y: float = t * layout.view.y
		draw_line(Vector2(0.0, y + 12.0), Vector2(layout.view.x, y - 18.0),
			Color(0.145, 0.135, 0.115, 0.55), 1.0)
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
	# STAV PROFILU: ktery level hrac hraje a kolik ma bodu. Bez toho by hrac
	# nevidel, ze se neco za vyhrane levely nasbiralo.
	_label(game.profile.menu_note(), Rect2(0.0, layout.menu_state_y, layout.view.x,
		float(layout.menu_sub_px) * 1.4), layout.menu_sub_px, MENU_EDGE)
	if not menu.update_note.is_empty():
		_label(menu.update_note, Rect2(layout.view.x * 0.05, layout.menu_note_y,
			layout.view.x * 0.9, float(layout.menu_sub_px) * 1.4),
			layout.menu_sub_px, Color(0.72, 0.70, 0.62))
	_label("build %s" % menu.build_id, Rect2(0.0, layout.view.y - float(layout.menu_sub_px) * 2.0,
		layout.view.x, float(layout.menu_sub_px)), layout.menu_sub_px, Color(0.42, 0.40, 0.36))


# VYBER LEVELU. Kazda dlazdice je cislo levelu; vyhrane maji zlaty ramecek a
# popisek "vyhráno", odemcene (a jeste nevyhrane) sedy. Zamcene levely se
# VUBEC nekresli (stranky se pocitaji z odemcenych), aby hrac nevidel neco, na
# co nema klepnout.
func _draw_levels() -> void:
	_label("VÝBĚR LEVELU", Rect2(0.0, layout.lvl_title_y,
		layout.view.x, float(layout.lvl_title_px)), layout.lvl_title_px, Color(0.90, 0.87, 0.80))
	var won: int = mini(game.profile.best, game.profile.level)
	_label("Vyhráno %d z %d · body %d" % [won, game.profile.level, game.profile.body],
		Rect2(0.0, layout.lvl_note_y, layout.view.x, float(layout.menu_sub_px) * 1.4),
		layout.menu_sub_px, MENU_EDGE)
	var f: Font = ThemeDB.fallback_font
	for i in range(layout.lvl_tiles.size()):
		var r: Rect2 = layout.lvl_tiles[i]
		var n: int = layout.lvl_page * ScreenLayout.LVL_PER_PAGE + i + 1
		var done: bool = n <= game.profile.best
		var accent: Color = MENU_EDGE_FIRST if done else MENU_EDGE
		draw_rect(r, MENU_BG, true)
		draw_rect(r, Color(accent.r, accent.g, accent.b, 0.55), false, 2.0)
		var npx: int = _fit_px(str(n), r.size.x - 12.0, int(r.size.y * 0.46), 14)
		draw_string(f, Vector2(r.position.x, r.position.y + r.size.y * 0.56),
			str(n), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, npx, Color(0.90, 0.87, 0.80))
		var cap: String = "vyhráno" if done else "odemčeno"
		var cpx: int = _fit_px(cap, r.size.x - 10.0, int(r.size.y * 0.24), 9)
		draw_string(f, Vector2(r.position.x, r.position.y + r.size.y * 0.88),
			cap, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, cpx, Color(accent.r, accent.g, accent.b, 0.9))
	# STRANKY: sipky jsou videt vzdy, ale kdyz neni kam, jsou ztlumene.
	var pages: String = "%d / %d" % [layout.lvl_page + 1, layout.lvl_pages]
	_label(pages, Rect2(layout.lvl_prev.end.x, layout.lvl_prev.position.y,
		layout.lvl_next.position.x - layout.lvl_prev.end.x, layout.lvl_prev.size.y),
		layout.menu_sub_px, MENU_EDGE)
	_arrow(layout.lvl_prev, layout.lvl_page > 0)
	_arrow(layout.lvl_next, layout.lvl_page < layout.lvl_pages - 1)
	var br: Rect2 = layout.lvl_back
	draw_rect(br, MENU_BG, true)
	draw_rect(br, Color(MENU_EDGE.r, MENU_EDGE.g, MENU_EDGE.b, 0.55), false, 2.0)
	_label("ZPĚT", br, _fit_px("ZPĚT", br.size.x - 16.0, layout.menu_item_px, 13), Color(0.90, 0.87, 0.80))


# SIPKA NA STRANKU. Kdyz neni kam listovat, je ztlumena - hrac vidi, ze tlacitko
# existuje, ale ted nic nedela.
func _arrow(r: Rect2, live: bool) -> void:
	var edge: Color = MENU_EDGE if live else Color(0.34, 0.33, 0.30)
	var text: Color = Color(0.90, 0.87, 0.80) if live else Color(0.44, 0.42, 0.38)
	draw_rect(r, MENU_BG, true)
	draw_rect(r, Color(edge.r, edge.g, edge.b, 0.55), false, 2.0)
	_label("PŘEDCHOZÍ" if r.position.x < layout.view.x * 0.5 else "DALŠÍ", r,
		_fit_px("PŘEDCHOZÍ", r.size.x - 12.0, layout.menu_item_px - 4, 11), text)


func _draw_settings() -> void:
	_label("NASTAVENÍ", Rect2(0.0, layout.settings_row.position.y - float(layout.menu_title_px) * 1.6,
		layout.view.x, float(layout.menu_title_px)), layout.menu_title_px, Color(0.90, 0.87, 0.80))
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


# =========================================================================
# DIALOGY
# =========================================================================

func _draw_dialog(title: String, sub: String, a: String, a_col: Color, b: String, b_col: Color) -> void:
	draw_rect(Rect2(Vector2.ZERO, layout.view), Color(0.03, 0.028, 0.034, 0.72), true)
	var bx: Rect2 = layout.dlg_box
	draw_rect(bx, MENU_BG, true)
	draw_rect(bx, Color(MENU_EDGE.r, MENU_EDGE.g, MENU_EDGE.b, 0.7), false, 2.0)
	var px: int = _fit_px(title, bx.size.x - 24.0, layout.menu_item_px, 12)
	var box := Rect2(bx.position.x, bx.position.y + bx.size.y * 0.14, bx.size.x, float(px) * 1.5)
	_label(title, box, px, Color(0.90, 0.87, 0.80))
	if sub != "":
		var spx: int = _fit_px(sub, bx.size.x - 24.0, layout.menu_sub_px, 10)
		_label(sub, Rect2(bx.position.x, box.position.y + float(px) * 1.35, bx.size.x,
			float(spx) * 1.5), spx, MENU_EDGE)
	if layout.dlg_a.size.x > 0.0:
		_label(a, layout.dlg_a,
			_fit_px(a, layout.dlg_a.size.x - 12.0, layout.menu_item_px, 11), a_col)
		draw_rect(layout.dlg_a, Color(a_col.r, a_col.g, a_col.b, 0.45), false, 2.0)
	if b != "" and layout.dlg_b.size.x > 0.0:
		_label(b, layout.dlg_b,
			_fit_px(b, layout.dlg_b.size.x - 12.0, layout.menu_item_px, 11), b_col)
		draw_rect(layout.dlg_b, Color(b_col.r, b_col.g, b_col.b, 0.45), false, 2.0)


func _draw_leave() -> void:
	_draw_dialog("Opravdu ukončit rozehranou partii?", "Zlato z levelu propadne, upgrady zůstávají.",
		"UKONČIT", Color(0.85, 0.42, 0.36), "ZPĚT DO HRY", Color(0.65, 0.78, 0.60))


func _draw_end() -> void:
	if game.phase == "won":
		var sub: String = "+%d bodů · další level má %d vln" % [game.body_earned, game.level + 1]
		if game.body_earned <= 0:
			# OPAKOVANY LEVEL: body se davaji jen za novy level (Jan, Oct 2026).
			sub = "Už vyhráno — body jsou jen za nový level."
		_draw_dialog("Level %d vyhrán" % game.level, sub,
			"DALŠÍ LEVEL", Color(0.65, 0.78, 0.60), "MENU", Color(0.72, 0.70, 0.62))
		return
	_draw_dialog("Konec — věž padla na levelu %d" % game.level,
		"Zlato propadá, body a upgrady zůstávají.",
		"ZPĚT DO MENU", Color(0.72, 0.70, 0.62), "", Color.WHITE)
