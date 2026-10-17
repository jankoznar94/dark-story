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
# PRSTENEC KOLEM POUTNIKA (na jehoz plasti konci paprsek) a ZABLESK KRITIKY.
# Kriticky paprsek zbela - PLOCHY tón, ne svetlo kolem svetla (Jan ma
# astigmatismus).
const RING_ALPHA := 0.80
const CRIT_TINT := 0.45
# OBVOD PAPRSKU. Drzi se jako PRIDAVEK k sirce paprsku, ne jako nasobek:
# u tlustsiho paprsku by se nasobenim obrys rozlezl do dvojite cary.
const BEAM_EDGE := 1.7
# PANEL: podklad je o stupen svetlejsi nez pole a ramecek tmavy, aby se daly
# od sebe poznat tri vrstvy (pole, panel, tab).
const CARD_BG := Color(0.095, 0.090, 0.100)
const CARD_ROW := Color(0.125, 0.118, 0.128)
const CARD_EDGE := Color(0.34, 0.33, 0.36)
# RAMEK BUNKY UPGRADU. Jan (Oct 2026): "Rámečky všechny tlačítek upgradů budou
# tlustší. Třeba 3px." Ani 3 px ani 4 px to nevyřešily - Jan je vracel slovy
# "bordery tlačítek s upgrady je stále tenký" (dvakrát) a "stále stejně tenký".
# Na bunce 176x48 se 4 px cte jako obrys, ne jako ramecek; 6 px uz je ramecek,
# ktery je videt jako ramecek. Zmereno v prohlizeci na zive strance
# (`zily2_frame_probe.py` ve skillu) - kdo bude hybat, at to zmeri znovu.
const CELL_FRAME := 6.0
# TABY KATEGORII A RAMEK PANELU. Jsou to taky tlacitka upgradu (a ty nevybrane
# mely 1 px, takze vypadaly rozbite) - se 6 px bunkou musi drzet krok, jinak
# panel vypada, jako by kazda cast byla z jine hry.
const TAB_FRAME := 4.0
const PANEL_FRAME := 4.0
# ZIVOTY VEZE: zelena dokud drzi, cervena pod tretinou. Barva NENI jediny
# nositel - cislo je i v hornim pruhu.
const HP_GOOD := Color(0.62, 0.76, 0.56)
const HP_MID := Color(0.86, 0.76, 0.40)
const HP_LOW := Color(0.85, 0.42, 0.36)
# HOTOVO = ZELENA. Je to stejna zelená jako zivoty veze - v cele hre znamena
# jedna barva jednu vec. Vyzene levely maji zeleny ramecek a zelenou fajfku
# (Jan, Oct 2026: "Hotové levely budou mít zelený Border a zelenou fajfku").
const WON_GREEN := HP_GOOD

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
# INDEX PRSTU, KTERY ZACAL SOUCASNE KLEPNUTI. Druhy prst se pozna podle toho, ze
# ma JINY index (`InputEventScreenTouch.index`); u mysi je to vzdy 0.
var _first_index: int = 0
# DOTAZ PRI ODCHODU Z BOJE. Dokud je otevreny, partie se NEKROKUJE - hrac se
# nema rozhodovat, zatimco mu umiraji poutnici.
var leave_ask: bool = false
# DOTAZ "POKRACOVAT?" - ukazuje se po klepnuti na HRAT, kdyz je na disku
# rozehrana partie (viz `BattleSave`). Je to stejna mechanika jako `leave_ask`:
# hrac na dotaz odpovida, klepnuti mimo odpovedi nic nedela.
var resume_ask: bool = false
# UKLADANI ROZEHRANE PARTIE: odpočet do dalsiho zapisu. Kadence je 2 s - kdyz
# prohlizec zalozku na pozadi zahodi, prijde hrac maximalne o dve vteriny hry
# z dvacetiminutoveho levelu (a ne o cely level, coz byl jeho problem).
const SAVE_EVERY := 2.0
var _save_left: float = 0.0
# DOTAZ NA SMAZANI POSTUPU (tlacitko RESET v menu). Je to jedina akce, ktera
# maze, takze se na ni VZDY ptá - a stejne jako odchod z boje partii zastavi.
var reset_ask: bool = false
# HLASKA PO SMAZANI POSTUPU (kresli se v menu; jinak by hrac nevidel, ze se
# neco opravdu stalo).
var reset_note: String = ""
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
	_make_music()
	_make_sfx()
	get_viewport().size_changed.connect(_refield)


# DIALOG MA JEDNU NEBO DVE ODPOVEDI - rozvrzeni se proto prelozi podle toho,
# ktery dialog je prave otevreny. Bez toho by "ZPET DO HRY" u dotazu na
# ukonceni neexistovalo (a klepnuti by nikam nevedlo).
func _sync_dialogs() -> void:
	layout.dialog_panel(leave_ask or reset_ask or resume_ask
		or (menu.is_battle() and game.phase == "won"))


func _refield() -> void:
	layout.update(get_viewport_rect().size)
	game.set_field(layout.field_r, layout.unit_r, layout.center)
	layout.layout_palette(game.palette.size())
	# PRUH SE SMESI SE REZERVUJE OD ZACATKU LEVELU, ve kterem je michani odemcene
	# (ne az kdyz hrac dvojici zvoli) - plocha se nesmi hybat pod rukama.
	layout.set_mix_unlocked(Hue.mix_unlocked(game.level))
	_sync_mix_strip()
	_sync_shop_shape()
	_sync_dialogs()


# KOlecko SE SMESI A DVE CARY. Pocita se z TOHO, co je opravdu zvolene: dve
# barvy veze a jejich MISTA v palete (rozvrzeni zna jen puntiky, ne barvy).
func _sync_mix_strip() -> void:
	if not layout.mix_unlocked or game.tower.hues.size() < 2:
		layout.mix_rects = []
		return
	var a: int = game.palette.find(game.tower.hues[0])
	var b: int = game.palette.find(game.tower.hues[1])
	layout.layout_mix(a, b)


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
	# JEN STATY, KTERE JDOU V BITVE KOUPIT. Stat, ktery v bitve nema co
	# nabidnout (`temp_max` 0 = dostrel, specialy), by jinak zabiral bunku,
	# ukazoval cenu 0 a "MAX" - hrac by videl tlacitko, ktere nic nedela
	# a nerekne proc. STATY S NEOMEZENYM ZEBRICKEM (`temp_max` -1) sem PATRI.
	var out: Array = []
	for s in Upgrades.stats_in(String(SHOP_CATS[clampi(shop_cat, 0, SHOP_CATS.size() - 1)])):
		if Upgrades.temp_buyable(String(s["id"])):
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
	return leave_ask or reset_ask or resume_ask or game.is_over()


func _process(dt: float) -> void:
	if menu.is_battle() and not is_halted():
		game.step(dt)
		# UKLADANI ROZEHRANE PARTIE: dokud bitva bezi, stav se kazde dve
		# vteriny zapise. Neni to "uklid pri odchodu" - kdyz prohlizec zalozku
		# zahodi, zadny odchod hry se nekona.
		_save_left -= dt
		if _save_left <= 0.0:
			_save_left = SAVE_EVERY
			_save_battle()
	# DOHRANA PARTIE SE Z DISKU MAZE: hrac ma po prichodu hrat novou, ne se
	# vracet do mrtve veze. Kontroluje se i mimo bitvu (hrac muze odejit hned).
	if game.is_over() and BattleSave.has():
		BattleSave.clear()
	_pull_js_state()
	if layout.pal_rects.size() != game.palette.size():
		layout.layout_palette(game.palette.size())
	# MICHANI BAREV: pruh se smesi se objevi v tom levelu, ve kterem se michani
	# odemkne (a od te chvile je rezervovany porad, i kdyz hrac zadnou dvojici
	# zvolenou nema) - plocha se pod rukama nehybe.
	if layout.mix_unlocked != Hue.mix_unlocked(game.level):
		layout.set_mix_unlocked(Hue.mix_unlocked(game.level))
		game.set_field(layout.field_r, layout.unit_r, layout.center)
	if layout.mix_rects.size() != (3 if game.tower.hues.size() > 1 else 0):
		_sync_mix_strip()
	# ZRYCHLENI HRY: tlacitko v pruhu je jen kdyz si hrac koupil special.
	# Rozvrzeni si to musi vzit z obrazovky (pocita to MISTO v pruhu).
	if layout.speed_visible != (game.speed_options() > 1):
		layout.set_speed_visible(game.speed_options() > 1)
	# ZVUKOVE EFEKTY: hra rekla, co se stalo; obrazovka z toho udela zvuk. Bere
	# se to JEDNOU za snimek (vyber = smazani), takze se zvuk nezopakuje.
	for ev in game.take_events():
		_play_sfx(String(ev))
	_sync_music()
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
#
# DRUHY PRST JE VYJIMKA - MICHANI BAREV (Jan, Oct 2026): druhy prst dosedne,
# dokud je prvni jeste dole, takze by ho strazce zahodil. Dotyk na paletu se
# proto pred strazcem posila hre a ta rozhodne (`Game.finger_down`): bud z nej
# je smes, nebo novy vyber jedne barvy. Kdyz druhy prst mine paletu, plati
# strazce dal a nic se nedeje.
func _unhandled_input(ev: InputEvent) -> void:
	var touch: bool = ev is InputEventScreenTouch
	if not touch and not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	var pos: Vector2 = ev.position
	if not ev.pressed:
		if touch:
			game.finger_up(ev.index)
			if ev.index == _first_index:
				_pressed = false
		else:
			_pressed = false
		return
	if touch:
		var h: int = _palette_hue_at(pos)
		if _pressed and h >= 0:
			# Vysledek muze byt smes i novy vyber jedne barvy - pruh se smesi
			# se proto prekresli vzdy, ne jen u smesi.
			game.finger_down(ev.index, h)
			_sync_mix_strip()
			return
	if _pressed:
		return
	_pressed = true
	if touch:
		_first_index = ev.index
	_tap(pos)


# BARVA POD PRSTEM (id barvy), nebo -1. Mimo bitvu, po konci hry a pod pauzou
# paleta neexistuje - pres paletu se tedy ani nemicha.
func _palette_hue_at(pos: Vector2) -> int:
	if not menu.is_battle() or game.is_over() or game.is_paused():
		return -1
	for i in range(layout.pal_rects.size()):
		if (layout.pal_rects[i] as Rect2).has_point(pos) and i < game.palette.size():
			return int(game.palette[i])
	return -1


# PORADI JE ZAVAZNE: to, co stoji NAD VSIM (dialog), je prvni. Hrac na dotaz
# ma odpovedet, ne ho odklepnout necim jinym.
func _tap(pos: Vector2) -> void:
	# PRVNI KLEPNUTI ODEMYKA ZVUK (prohlizec nespusti hudbu bez gesta hrace).
	touched = true
	_sync_music()
	if reset_ask:
		_handle_reset_tap(pos)
		return
	if resume_ask:
		_handle_resume_tap(pos)
		return
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
	reset_note = ""
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
			"reset":
				# MAZANI SE VZDY PTÁ: tlacitko je na kraji, ale i tak - hrac
				# ma videt, o co prijde, nez se neco smaze.
				reset_ask = true
				_sync_dialogs()
			"update":
				menu.request_update()
		return


# NOVA PARTIE. Hra zacina na NEJVYSSIM odemcenem levelu; profil (body
# i permanentni upgrady) zustava - to je cely smysl permanentnich bonusu.
#
# ROZEHRANA PARTIE MA PREDNOST: kdyz je na disku ulozena bitva (hrac se vracel
# z pozadi), "HRÁT" se nejdriv zeptá, jestli ma pokracovat, nebo zacit znovu.
# Neni to otrava navic: "HRÁT" je i cesta, jak zacit novou partii, a tiche
# preskoceni rozjeteho levelu by hrace pripravilo o praci.
func start_battle() -> void:
	if BattleSave.has():
		resume_ask = true
		leave_ask = false
		_sync_dialogs()
		return
	start_new_battle()


# NOVA PARTIE (bez dotazu). Ulozena bitva se maze - hrac si vybral znovu.
func start_new_battle() -> void:
	leave_ask = false
	resume_ask = false
	BattleSave.clear()
	game.start_level(game.profile.level)
	_refield()
	menu.open_battle()
	_save_battle()


# UKLADANI ROZEHRANE PARTIE. Jedno misto, odkud se uklada - obrazovka jinak
# nemusi vedet, co vsechno stav hry obsahuje (`Game.to_state`).
func _save_battle() -> void:
	if game.is_over():
		return
	BattleSave.save(game)


# POKRACOVANI V ROZEHRANE PARTII. Plocha se prelozi na AKTUALNI displej (hrac
# se muze vratit na jinem telefone) a teprve pak se do hry nasadi ulozeny stav -
# polohy poutniku jsou v pixelech plochy, takze poradi je dane.
func _do_resume() -> void:
	resume_ask = false
	leave_ask = false
	_refield()
	if BattleSave.load_into(game):
		_save_left = SAVE_EVERY
		menu.open_battle()
		return
	# SOUBOR JE PRYC NEBO POSKOZENY: hrac dostane novou partii, ne prazdnou
	# obrazovku s vezi bez nepritele.
	start_new_battle()


func _handle_resume_tap(pos: Vector2) -> void:
	if layout.dlg_a.has_point(pos):
		_do_resume()
		return
	if layout.dlg_b.has_point(pos):
		start_new_battle()
		return
	# KLEPNUTI MIMO ODPOVED NIC NEDELA (dotaz neni hlaseni).


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
		resume_ask = false
		# VYBRANY LEVEL JE NOVA PARTIE: ulozena rozehrana bitva se maze, jinak
		# by se hrac po vyberu jineho levelu vracel do te stare.
		BattleSave.clear()
		game.start_level(n)
		_refield()
		menu.open_battle()
		_save_battle()
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
	for i in range(layout.settings_rows.size()):
		if not (layout.settings_rows[i] as Rect2).has_point(pos):
			continue
		# PORADI RADKU = PORADI v `_settings_rows()` (jeden zdroj pravdy).
		match i:
			0:
				settings.toggle_lowres()
				_apply_render_scale()
				_refield()
			1:
				settings.toggle_music()
				_sync_music()
			2:
				settings.toggle_sfx()
		return
	if layout.settings_back.has_point(pos):
		menu.open_menu()


# RADKY OBRAZOVKY NASTAVENI: popisek + hodnota. Poradi je zavazne (klepnuti
# i kresleni jdou podle indexu) a musi jich byt presne `ScreenLayout.
# SETTINGS_ROWS` - hlida to test_menu.
func _settings_rows() -> Array:
	return [
		["Jakost vykreslování", settings.lowres_text()],
		["Hudba", settings.music_text()],
		["Zvuky", settings.sfx_text()],
	]


# =========================================================================
# HUDBA (Jan, Oct 2026: "A dáme do hry nějakou primitivní hudbu.")
#
# Jedna kratka smycka (soubor z `tools/make_music.py`) hraje porad dokola.
#
# PROCHRAMEC NESPUSTI ZVUK BEZ GESTA HRAVE: hudba se proto rozjede az po
# PRVNIM klepnuti (`touched`). Hra, ktera "sama hraje", by v prohlizeci jen
# hlasila chybu - a hrac by videl tlacitko, ktere nic nedela.
# =========================================================================

const MUSIC_PATH := "res://assets/audio/theme.ogg"
const MUSIC_DB := -15.0
var music: AudioStreamPlayer = null
var touched: bool = false


func _make_music() -> void:
	music = AudioStreamPlayer.new()
	var s: AudioStream = load(MUSIC_PATH)
	if s != null:
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		elif s is AudioStreamWAV:
			(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	music.stream = s
	music.volume_db = MUSIC_DB
	add_child(music)


# =========================================================================
# ZVUKOVE EFEKTY (Jan, Oct 2026: "A střelba a zásah by samozřejmě měly mít
# také zvukové efekty.")
#
# Hra posila UDALOSTI ("shot", "hit", "kill") a obrazovka si z nich dela zvuk.
#
# DVE VECI, bez kterych by to hrac nesnesl:
#   1. ODPOCET MEZI ZVUKY. Pri plne kadenci (20 ran/s) by zvuk vystrelu sel
#      20x za sekundu a slil se do huceni - `SFX_GAP_S` drzi odstup.
#   2. BAZEN PREHRAVACU. Jeden prehravac prerusuje sam sebe (druhy vystrel by
#      utnul prvni). Ctyri staci.
# =========================================================================

const SFX_DB := {"shot": -14.0, "hit": -10.0, "kill": -8.0}
const SFX_GAP_S := {"shot": 0.075, "hit": 0.045, "kill": 0.0}
const SFX_VOICES := 4
var sfx_streams: Dictionary = {}
var sfx_voices: Array = []
var sfx_at: Dictionary = {}


func _make_sfx() -> void:
	for kind in SFX_DB.keys():
		var s: AudioStream = load("res://assets/audio/%s.ogg" % String(kind))
		if s != null:
			sfx_streams[String(kind)] = s
	for i in range(SFX_VOICES):
		var pl := AudioStreamPlayer.new()
		pl.volume_db = 0.0
		add_child(pl)
		sfx_voices.append(pl)


# ZVUK SE PREHRAJE JEN KDYZ MA SMYSL: hrac chce zvuky (nastaveni), uz neco
# udelal (prohlizec bez gesta nic nepustí) a od posledniho stejneho zvuku
# uplynul odstup. Jinak se udalost zahodi - zvuk je doplnek, ne fronta.
#
# Odstup se meri HODINAMI, ne snimky: kdyby se scital `dt`, posunul by se cas
# jen o snimky, ve kterych neco priletlo, a po pauze by se zdravy zvuk zahodil.
func _play_sfx(kind: String) -> void:
	if not settings.sfx or not touched:
		return
	if not sfx_streams.has(kind):
		return
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	if now - float(sfx_at.get(kind, -999.0)) < float(SFX_GAP_S.get(kind, 0.0)):
		return
	sfx_at[kind] = now
	for pl in sfx_voices:
		var p: AudioStreamPlayer = pl
		if not p.playing:
			p.stream = sfx_streams[kind]
			p.volume_db = float(SFX_DB.get(kind, -12.0))
			p.play()
			return
	# VSECHNY HLASY HRAJI: prerusi se PRVNI (rajcsi utaty stary zvuk nez
	# zahodit novy - novy je ten, ktery hrac prave vidi).
	var p0: AudioStreamPlayer = sfx_voices[0]
	p0.stream = sfx_streams[kind]
	p0.volume_db = float(SFX_DB.get(kind, -12.0))
	p0.play()


# HUDBA SE SROVNAVA SE STAVEM, ne s udalosti: kdo ji vypne v nastaveni, ten
# nema resit, jestli zrovna hraje - tady se to srovna samo (a je to na jednom
# miste, takze se neda zapomenout).
func _sync_music() -> void:
	if music == null:
		return
	var want: bool = touched and settings.music and music.stream != null
	if want and not music.playing:
		music.play()
	elif not want and music.playing:
		music.stop()


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
# SMAZANI POSTUPU (RESET)
#
# Jedina akce, ktera maze. Neni to "restart partie" (to je tlacitko HRAT) ani
# "stahni novou verzi" (UPDATE nic nemaze): maze se CELY PROFIL - body,
# permanentni vylepseni, nejvyssi level i vyhrane levely. Proto se na ni vzdy
# ptá dialogem a podtitul rekne, o co hrac prijde.
# =========================================================================

func _handle_reset_tap(pos: Vector2) -> void:
	if layout.dlg_a.has_point(pos):
		_do_reset()
		return
	if layout.dlg_b.has_point(pos):
		reset_ask = false
		return
	# KLEPNUTI MIMO ODPOVED NIC NEDELA - na tohle se neodpovida mimochodem.


func _do_reset() -> void:
	var lost: int = game.profile.body
	var lvl: int = game.profile.level
	game.profile.reset()
	game.start_level(1)
	_refield()
	reset_ask = false
	menu.open_menu()
	reset_note = "Postup smazán (bylo %d bodů, level %d)." % [lost, lvl]


func _draw_reset() -> void:
	var p: Profile = game.profile
	var sub: String = "Přijdeš o %d bodů, permanentní vylepšení a postup do levelu %d." % [p.body, p.level]
	var perm_total: int = 0
	for k in p.perm.keys():
		perm_total += p.perm_level(String(k))
	if p.body <= 0 and p.best <= 1 and perm_total == 0:
		sub = "Zatím není co smazat."
	_draw_dialog("Smazat celý postup?", sub,
		"SMAZAT", HP_LOW, "ZPĚT", Color(0.65, 0.78, 0.60))


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
	# ZRYCHLENI HRY: prepne tempo. Je to ovladani HRY (jako pauza), takze funguje
	# i pod pauzou - hrac si muze rozmyslet, jak rychle bude pokracovat.
	if layout.hud_speed.size.x > 0.0 and layout.hud_speed.has_point(pos):
		game.cycle_speed()
		return
	# POD PAUZOU DESKA NEREAGUJE NA NIC (krome pauzy a MENU vys): hrac ma cas
	# premyslet, ne menit stav. Kdyby se pod pauzou dalo stavet a nakupovat,
	# hrac by si "rozmyslel" veci, ktere uz jsou davno rozhodnute.
	if game.is_paused():
		return
	for i in range(layout.pal_rects.size()):
		if (layout.pal_rects[i] as Rect2).has_point(pos):
			if i < game.palette.size():
				# MICHANI DVA PRSTY: hra rozhodne, jestli je to smes (druhy
				# prst na jinou barvu do `Game.TOUCH_MIX_S`), nebo vyber jedne
				# barvy. Cas se meri hernimi hodinami, ne systemovymi.
				game.finger_down(_first_index, int(game.palette[i]))
				_sync_mix_strip()
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
		if reset_ask:
			_draw_reset()
		if resume_ask:
			_draw_resume()
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
	for p in game.pilgrims:
		_draw_pilgrim(p)
	_draw_tower()
	if game.is_paused() and not game.is_over() and not leave_ask:
		_draw_pause_hint()
	# LASER SE KRESLI NAD VSIM V POLI (Jan: "Projektily musí být výraznější
	# a musí být z indexem nad zaměřováním"). Paprsek je od Oct 2026 zbran
	# sama - zadne zaměřování pod nim uz neni.
	_draw_beams()
	_draw_bar()
	# PRUH SE SMESI JE NAD PALETOU (kolecko se do pruhu palety nevejde).
	_draw_mix_strip()
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
	var true_col: Color = Hue.color_of(p.hue)
	var r: float = layout.pilgrim_r * p.size
	# CHLAD SE NA TELE POUTNIKA VUBEC NEPROJEVUJE. Jan (Oct 2026): "Chill effect
	# nesmí měnit barvu nepřítele. Proto jsme kolem něj dali devitihran, aby
	# naznačil zmrazení. Změna barvy je dost matoucí."
	#
	# DRIV se telo zbarvovalo do zimnava modrobila (`ICE_BODY`/`ICE_TINT`) a Jan
	# v tom videl druhou barvu: zledovany poutnik vypadal jako JINA barva, nez
	# jakou ma - a barva je tu jedina informace, podle ktere se miri (vez vidi
	# jen svou barvu). Hrac tak miril na barvu, ktera na plose vubec nebyla.
	# Stav "mrznu" proto nese VYHRADNE DEVITIHRAN kolem prstence (viz nize) a
	# zpozdeni v chuzi; barva tela zustava PRESNE barva poutnika, i kdyz je
	# zledovany.
	# POUTNIK JE PUNTIK S INICIALAMI BARVY. Jan (Oct 2026): "Všichni budou mít
	# tvar puntíku. V něm budou mít iniciály barvy nebo kombinace barev. Zbytek
	# zůstává. Takže musí být o něco větší, aby to bylo čitelné."
	#
	# PROC SE TVARY ZRUSILY: hrac z tvaru poznal barvu, ale u SMESE (dva tvary
	# spojene) nepoznal, na kterou kombinaci ma mirrit - "hráč podle pouhého
	# odstínu nepozná o kterou kombinaci nepřítele se jedná. Takže na něj nedokáže
	# zaútočit." Pismena "R"/"RY" reknou kombinaci PRIMO.
	_dot(p.hue, p.pos, r, true_col, p.is_ghost())
	# PRSTENEC JE ZAROVEN HP BAR POUTNIKA (Jan, Oct 2026: "Kruhy kolem nepřátel
	# budou sloužit rovnou jako jejich HP bary."). Oblouk zacina nahore a jde po
	# smeru hodinovych rucicek - stejne jako zivoty veze; plny kruh = plne
	# zivoty. Barva zustava barva poutnika (nese ji zamereni veze), takze tvar,
	# barvu i zbyvajici zivoty nese JEDEN kruh. Paprsek se ho NEDOTYKA: konci na
	# tele poutnika (`Game.PILGRIM_HIT_FRAC`, stejne cislo jako `_dot` nize) -
	# prstenec je jen zivoty. Duch ho nema: je pruhledny a neda se na nej
	# mirrit.
	#
	# DRUHY, BILY OBLOUK SE ZRUSIL (byl v 1,55 r, barva TEXT). Objevoval se pri
	# kazdem zasahu a Jan ho videl jako "jeden kruhovy border (svetle modry nebo
	# bily) kolem jejich zivotu" - byl to HP bar vedle HP baru, ktery tam nema
	# co delat (Oct 2026).
	if not p.is_ghost():
		# 24 usecek staci: prstenec ma na telefonu ~10 px v polomeru. Na plose
		# muze byt naraz i nekolik stovek poutniku, tak se pocet usecek drzi
		# nizko - je to jedina kresba, ktera pribyla KAZDEMU z nich.
		draw_arc(p.pos, game.pilgrim_ring_r(p), -PI * 0.5,
			-PI * 0.5 + TAU * p.hp_frac(), 24,
			Color(true_col.r, true_col.g, true_col.b, RING_ALPHA), maxf(1.6, r * 0.20))
	# LEDOVY KRYSTAL: namrazovy prstenec KOLEM HP baru. Jan (Oct 2026): "Ten vnější
	# kruh ještě kolem HP baru byl možná skutečně nejlepší řešení. Jen bych ho
	# udělal tak, aby více evokoval zmrazení. Předtím spíš evokoval silové pole."
	# a "Zkusme ledový krystal", nakonec "Devitihran je nejlepší": PRAVIDELNY
	# devitihran (6 nebo 12 vrcholu vypadalo spatne). Geometrie je v `Shapes`,
	# aby se dala otestovat bez prohlizece: krystal se nesmi dotknout prstence
	# (= HP bar) ani jedoveho krouzku.
	#
	# Kresli se po cely chlad (`p.ice_left`), tedy i ty tri sekundy po poslednim
	# zasahu, kdy uz zadny paprsek nesviti - prave proto musi byt stav videt na
	# poutnikovi a ne jen na paprsku.
	if p.ice_left > 0.0 and not p.is_ghost():
		draw_polyline(_closed(Shapes.crystal_ring(p.pos, game.pilgrim_ring_r(p))),
			ICE_RING, maxf(1.6, r * 0.20))
	# JED A LED SE NEKRESLI JAKO KROUZEK. Jan (Oct 2026): "Kolem nepřátel, do
	# kterých střílím, je stále navíc světle modrý kroužek. Nechci ho tam." Kolem
	# poutnika smi byt JEDINY kruh, a to jeho prstenec (= HP bar) - led je proto
	# videt na TELE poutnika, na paprsku a v LEDOVEM KRYSTALU (vyse), ne na
	# dalsim hladkem krouzku.
	#
	# JED (zeleny) zustava: je to stav, ktery ubira zivoty v case, a bez nej by
	# hrac nevidel, ze mu zakoupeny "Jedovatý zásah" pracuje.
	if p.poison_left > 0.0:
		draw_arc(p.pos, r * 2.35, 0.0, TAU, 20, Color(0.55, 0.80, 0.35, 0.85), 2.0)


# PUNTIK S INICIALAMI. Jedina kresba, kterou ma kazdy nepritel i runa veze.
# Jan (Oct 2026): "Všichni budou mít tvar puntíku. V něm budou mít iniciály barvy
# nebo kombinace barev." Barva nikdy neni jediny nositel informace - u smesi to
# plati dvojnasob, protoze "hráč podle pouhého odstínu nepozná o kterou kombinaci
# nepřítele se jedná".
#
# `hollow` = duch (fialova po prvnim zasahu): jen obrys, ale pismena zustavaji -
# hrac musi vedet, na co ceka, i kdyz na nej prave mirrit neda.
func _dot(h: int, p: Vector2, r: float, col: Color, hollow: bool = false) -> void:
	var w: float = maxf(1.6, r * 0.22)
	# PODIL TELA JE Z `Game.PILGRIM_HIT_FRAC`: na tom samem polomeru konci
	# paprsek (`Game.pilgrim_hit_r`). Kdyby tu stalo jine cislo, hra by
	# mirila na teleso, ktere obrazovka nekresli (nebo mimo nej).
	if hollow:
		draw_arc(p, Game.PILGRIM_HIT_FRAC * 0.96 * r, 0.0, TAU, 28, col, w)
	else:
		draw_circle(p, Game.PILGRIM_HIT_FRAC * r, col)
	var txt: String = Hue.letter_of(h)
	if txt == "":
		return
	# VELIKOST PISMEN SE HLEDA, NE HADA: dve pismena ("RY") jsou sirsi nez jedno
	# a na mensim telefonu je puntik mensi. `_fit_px` zmensuje, dokud se text do
	# puntiku nevejde - a nikdy pod 8 px (menssi pismo hrac neprecte).
	var px: int = _fit_px(txt, r * 1.55, maxi(9, int(r * 1.35)), 8)
	# NA STŘEDU PUNTIKU. Jan (Oct 2026): "Iniciály musí být logicky na středu."
	# `_label` (bez `dy`) centruje text ve obdelniku, ktery je presne kolem
	# stredu puntiku - zadny posun stranou ani dolu.
	_label(txt, Rect2(p.x - r, p.y - r, 2.0 * r, 2.0 * r), px, GLYPH)


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(pts)
	out.append(pts[0])
	return out


# BARVA KRUHU DOSTRELU = BARVA VEZE. Ztlumena (0,62), aby kruh neprebijel
# poutniky a paprsek - je to geometrie, ne zbran.
func _range_color() -> Color:
	var col: Color = game.tower.color()
	return Color(col.r, col.g, col.b, 0.62)


# LASER. Barva paprsku je BARVA VEZE (Jan, Oct 2026: "Barva laseru bude podle
# barvy věže") - a proto se barva prebitim veze zmeni i paprsku, ktery prave
# sviti: neni to strela, ktera uz leti, je to zbran, kterou hrac drzi v ruce.
#
# TM AVY OBRYS POD PAPRSKEM je stejny trik jako u byvalych tecek strel: na
# svetlem poutnikovi nebo na karte by se barevna cara ztratila.
func _draw_beams() -> void:
	var col: Color = game.tower.color()
	# MRZIVY PAPRSEK. Kdyz vez zpomaluje, paprsek zledovati - vybledne do
	# zimnava. PRERUSOVANI SE ZRUSILO (Jan, Oct 2026: "Laser je teď čárkovaný...
	# Nevím proč jsi to změnila. Starý laser byl lepší."): chlad nese BARVA
	# paprsku a ledovy krystal na cili, paprsek zustava v JEDNOM KUSE. Hrac
	# o chladu vi i tak, a laser je to, co ma byt: laser.
	var chill: bool = game.ice_frac() > 0.0
	if chill:
		col = col.lerp(Color(0.78, 0.89, 1.0), CHILL_TINT)
	# ZABLESK KRITIKY: paprsek zbela (PLOCHY tón, zadny glow - Jan ma
	# astigmatismus a svetla kolem svetla je pro nej to nejhorsi).
	if game.crit_active():
		col = col.lerp(Color(1.0, 1.0, 1.0), CRIT_TINT)
	for b in game.beams:
		var q: Pilgrim = b["target"]
		if q == null or not q.alive:
			continue
		var w: float = maxf(1.0, game.beam_w(int(b["hop"])))
		# TM AVY OBRYS POD PAPRSKEM: na svetlem poutnikovi nebo na karte by se
		# barevna cara ztratila. Je to obrys, ne druha cara - paprsek zustava
		# barevny, obrys ho jen oddeluje od podkladu.
		_beam_line(b["from"], b["to"], GLYPH, w + BEAM_EDGE)
		_beam_line(b["from"], b["to"], col, w)


# JEDEN SEGMENT PAPRSKU S KULATYMI KONCI. Godot kresli caru s hranatym koncem
# a nic jineho neumi - hrac to videl jako "dva obdelniky vedle sebe" (Jan,
# Oct 2026), proto se kazdy konec dokresli koleckem o polomeru sirky paprsku.
# Diky tomu na sebe segmenty v prstenci poutnika plynule navazuji.
#
# PAPRSEK JE VZDY V JEDNOM KUSE. Prerusovana cara (mrzivy paprsek) se zrusila:
# Jan (Oct 2026): "Laser je teď čárkovaný... Starý laser byl lepší."
const CHILL_TINT := 0.45
# LEDOVY KRYSTAL: barva namrazoveho prstence kolem HP baru. Je to ZIMNAVA MODRA,
# ne bilá: nahled s bledou barvou (0,72/0,86/0,97) vypadal jako bily obrys -
# a "bily obrys" uz u poutniku jednou byl a Jan ho vracel. Plocha, zadny glow
# (Jan ma astigmatismus).
const ICE_RING := Color(0.55, 0.76, 0.96)


func _beam_line(a: Vector2, b: Vector2, c: Color, w: float) -> void:
	draw_line(a, b, c, w)
	draw_circle(a, w * 0.5, c)
	draw_circle(b, w * 0.5, c)


# VEZ. Misto stupnu ma ZIVOTY: tlusty oblouk kolem tela, barva podle toho,
# kolik jestli zbylo. Cislo je vzdy i v hornim pruhu, takze barva nikdy neni
# jediny nositel informace.
func _draw_tower() -> void:
	var c: Vector2 = layout.center
	var tr: float = layout.tower_r
	var col: Color = game.tower.color()
	draw_circle(c, tr, TOWER_BODY)
	draw_arc(c, tr * 0.92, 0.0, TAU, 48, col, maxf(2.0, tr * 0.13))
	# RUNA VEZE JSOU INICIALY BARVY - stejne jako u poutniku a v palete. U smesi
	# dve pismena ("RY"), u jedne barvy jedno. Tvary ve hre nejsou (Jan, Oct 2026:
	# "Všichni budou mít tvar puntíku"), takze i runa veze je puntik s pismeny.
	# Barvu prstence i paprsku nese SMES, takze hrac vidi, co ma.
	var rune: int = game.tower.mix()
	if rune < 0:
		rune = int(game.tower.hues[0])
	_dot(rune, c, tr * 0.52, col)
	var frac: float = clampf(game.hp / maxf(1.0, game.max_hp), 0.0, 1.0)
	# ZIVOTY VEZE: oblouk je ZAROVEN nejvnejsi hranice veze - prave odtud
	# vychazi paprsek (`Game.tower_edge_r`), takze se ta dve cisla nesmi rozejit.
	draw_arc(c, tr * Game.TOWER_ARC_R, -PI * 0.5, -PI * 0.5 + TAU * frac, 64,
		_hp_color(frac), maxf(3.0, tr * Game.TOWER_ARC_W))


func _hp_color(frac: float) -> Color:
	if frac > 0.6:
		return HP_GOOD
	if frac > 0.3:
		return HP_MID
	return HP_LOW


# =========================================================================
# HORNI PRUH A PALETA
# =========================================================================

# FAJFKA U VYHRANEHO LEVELU. Dve tlusty cary pod cislem levelu - velikost se
# bere z dlazdice, aby byla citelna i na malem displeji (Jan: velke prvky).
# TRI BODY jsou ve vlastni funkci, aby se daly ZMERIT - kresleni se testovat
# neda, geometrie ano.
func check_mark_points(r: Rect2) -> Array:
	var w: float = r.size.y * 0.46
	var h: float = r.size.y * 0.30
	var x: float = r.position.x + (r.size.x - w) * 0.5
	var y: float = r.position.y + r.size.y * 0.60
	return [Vector2(x + w * 0.02, y + h * 0.48),
		Vector2(x + w * 0.36, y + h * 0.94),
		Vector2(x + w * 0.98, y + h * 0.04)]


func _check_mark(r: Rect2) -> void:
	# FAJFKA misto popisku: dve tlusty cary. Znak "✓" v zakladnim pismu Godotu
	# neni - kdyz chybi, nakresli se prazdny ctverecek.
	var p: Array = check_mark_points(r)
	var lw: float = maxf(3.0, r.size.y * 0.075)
	draw_line(p[0], p[1], WON_GREEN, lw)
	draw_line(p[1], p[2], WON_GREEN, lw)


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
	# PAUZA / POKRAČOVAT: jedno tlacitko, dva vyznamy. NENI NA NEM TEXT, ale
	# IKONA (Jan, Oct 2026: "Tlačítko Pause nebude mít text ale velkou ikonu.
	# Ikonu pauzy, po kliknutí ikonu resume."). Stav nese TVAR (dve carky =
	# stoji, trojuhelnik = bezi) i BARVA tlacitka (zlata = stoji), takze barva
	# nikdy neni jediny nositel informace.
	var pr: Rect2 = layout.hud_pause
	var hold: bool = game.is_paused()
	draw_rect(pr, MENU_EDGE_FIRST if hold else TOWER_BODY, true)
	draw_rect(pr, MENU_EDGE_FIRST if hold else DIM, false, 2.0)
	_draw_pause_icon(pr, hold)
	# ZRYCHLENI HRY: tlacitko je v pruhu JEN kdyz si hrac koupil special
	# (`layout.speed_visible`). Nese NAPSANOU hodnotu ("1,5x") - cislo je
	# nositel stavu, barva jen doplnek.
	if layout.hud_speed.size.x > 0.0:
		var sr: Rect2 = layout.hud_speed
		var fast: bool = game.time_scale() > 1.001
		draw_rect(sr, MENU_EDGE_FIRST if fast else TOWER_BODY, true)
		draw_rect(sr, MENU_EDGE_FIRST if fast else DIM, false, 2.0)
		_label(Upgrades.value_text("gs", game.speed_step, 0), sr,
			_fit_px("2,5x", sr.size.x - 8.0, layout.font_px, 10), GLYPH if fast else TEXT)
	var note: String = game.last_note()
	if note != "":
		var npx: int = _fit_px(note, layout.view.x - 2.0 * pad, layout.font_px)
		draw_string(ThemeDB.fallback_font, Vector2(pad, layout.bar_h + float(npx) * 1.6), note,
			HORIZONTAL_ALIGNMENT_LEFT, layout.view.x - 2.0 * pad, npx, DIM)


# IKONA PAUZY / POKRACOVAT. Dve tlusty carky = hra stoji, trojuhelnik (play) =
# hra bezi - znak, ktery hrac zna z kazdeho prehravace. Kresli se do stredu
# tlacitka, velikost z jeho strany (tlacitko je ctverec), takze je "velka" na
# kazdem displeji. Barvu dostava zvenci: tmava na svetlem, tmava i na zlate.
func _draw_pause_icon(r: Rect2, hold: bool) -> void:
	# BARVA IKONY MUSI BYT CITELNA NA PODKLADU TLACITKA (Jan, Oct 2026: "Tlačítko
	# Pause samozřejmě musí mít takové barvy, aby byla ikona čitelná. Teď splývá
	# s pozadím."): tlacitko ma tmavy podklad (`TOWER_BODY`), takze ikona je
	# SVETLA jako popisek MENU; pod pauzou je podklad zlaty a ikona TMAVA.
	# Kdo sem da `GLYPH` natvrdo, kresli tmave na tmavem.
	var icon: Color = GLYPH if hold else TEXT
	var c: Vector2 = r.get_center()
	var s: float = minf(r.size.x, r.size.y) * 0.26
	if hold:
		# TROJUHELNIK DOPRAVA (play / pokracovat).
		var tri := PackedVector2Array([
			c + Vector2(-s * 0.66, -s), c + Vector2(-s * 0.66, s), c + Vector2(s * 0.98, 0.0)])
		draw_colored_polygon(tri, icon)
		return
	# DVE CARKY (pause).
	var w: float = maxf(3.0, s * 0.44)
	draw_rect(Rect2(c.x - s * 0.78, c.y - s, w, 2.0 * s), icon, true)
	draw_rect(Rect2(c.x + s * 0.78 - w, c.y - s, w, 2.0 * s), icon, true)


# PALETA BAREV NAD PANELEM S UPGRADY. Tlacitko je PLNÝ KRUH v barve s rameckem
# (Jan: "jen barevný plný puntík s borderem. Žádné tvary.") a VE STREDU JE
# PISMENO BARVY (Jan, Oct 2026: "Každá barva bude mít ve středu kruhu písmeno
# podle názvu barvy... Kombinované barvy budou mít dvě písmena"). Pismeno je
# tmave (GLYPH) - na sytou barvu je to jedina barva, ktera ma vsude kontrast, a
# je to stejny jazyk jako tmavy obrys tecky strely.
# PRUH SE SMESI: dve tiche cary od zvolenych puntiku do kolecka, kolecko v barve
# smesi a v nem DVE PISMENA. Barva nikdy neni jediny nositel informace - smes
# dvou barev se da splést s barvou treti, proto jsou v kolecku pismena.
func _draw_mix_strip() -> void:
	var mix: int = game.tower.mix()
	if mix < 0 or layout.mix_rects.is_empty():
		return
	var dot: Rect2 = layout.mix_rects[0]
	var col: Color = Hue.color_of(mix)
	var c: Vector2 = dot.get_center()
	var side: float = minf(dot.size.x, dot.size.y)
	var quiet: Color = Color(col.r, col.g, col.b, 0.55)
	# CARY JDOU POD KOLECKO - kdyby se kreslily po nem, prekryly by pismena.
	for ln in layout.mix_lines:
		draw_line(ln[0], ln[1], quiet, maxf(2.0, side * 0.06))
	draw_circle(c, side * 0.5, col)
	draw_arc(c, side * 0.5, 0.0, TAU, 48, GLYPH, maxf(2.0, side * 0.09))
	_label(Hue.letter_of(mix), dot, maxi(10, int(side * 0.46)), GLYPH)


func _draw_palette() -> void:
	for i in range(layout.pal_rects.size()):
		if i >= game.palette.size():
			break
		var h: int = int(game.palette[i])
		var r: Rect2 = layout.pal_rects[i]
		var col: Color = Hue.color_of(h)
		var active: bool = game.tower.hues.has(h)
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
	draw_rect(r, CARD_EDGE, false, PANEL_FRAME)


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


# BARVY KATEGORII (Jan, Oct 2026: "Meč červeny. Štít modrý. Ekonomika žlutá.
# Speciál fialový."). Bere se PALETA HRY, ne nove barvy: cervena je cervena
# ohne, modra modra vody a fialova fialova vzduchu - v hre nejsou dve cervene
# (zluta uz je i barva penez, takze ekonomika sedi taky).
var cat_icon_colors: Dictionary = {
	Upgrades.CAT_OFF: Hue.color_of(Hue.RED),
	Upgrades.CAT_DEF: Hue.color_of(Hue.BLUE),
	Upgrades.CAT_ECO: Hue.color_of(Hue.YELLOW),
	Upgrades.CAT_SPEC: Hue.color_of(Hue.VIOLET),
}
# ZTLUMENI ZAVRENE KATEGORIE. Barvu dostane i tab, ktery zrovna neni otevreny -
# hrac ma videt, ktera kategorie je ktera, i kdyz se na ni zrovna nediva.
const CAT_IDLE_A := 0.5


func _cat_icon_color(cat_id: String, on: bool) -> Color:
	var c: Color = cat_icon_colors.get(cat_id, TEXT)
	if on:
		return c
	return Color(c.r, c.g, c.b, CAT_IDLE_A)


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
		draw_rect(tr, col if on else CARD_EDGE, false, TAB_FRAME if on else 3.0)
		var cat: String = String(cats[i]) if i < cats.size() else ""
		var tex: Texture2D = _cat_icon(cat)
		if tex != null:
			var ir: Rect2 = icons[i] if i < icons.size() else tr
			draw_texture_rect(tex, ir, false, _cat_icon_color(cat, on))
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
		draw_rect(c, col, false, CELL_FRAME)
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
		var maxed: bool = Upgrades.temp_is_maxed(id, have)
		var c: int = Upgrades.temp_cost(id, have)
		names.append(Upgrades.label_of(id))
		values.append(Upgrades.value_text(id, game.profile.perm_level(id), have))
		prices.append("MAX" if maxed else "+%d zl." % c)
		afford.append((not maxed) and game.gold >= c)
	_draw_grid(layout.shop_cells, stats, names, values, prices, afford)


# OBRAZOVKA VYLEPSENI V MENU (driv "UPRAVY"): permanentni stupne za body.
func _draw_upgrades() -> void:
	_label("VYLEPŠENÍ", Rect2(0.0, upg_title_y(), layout.view.x, float(layout.menu_title_px)),
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
	# HLASKA PO SMAZANI POSTUPU: jinak by hrac nevidel, ze reset opravdu
	# probehl (a myslel by si, ze tlacitko nic nedela).
	if reset_note != "":
		_label(reset_note, Rect2(layout.view.x * 0.05, layout.menu_note_y,
			layout.view.x * 0.9, float(layout.menu_sub_px) * 1.4),
			layout.menu_sub_px, HP_LOW)
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
		# VYHRANY LEVEL: ZELENY ramecek a zelena fajfka. Zelenou nese i TVAR
		# (fajfka) - kdyby stav nesla jen barva, hrac s poruchou videni barvy
		# vidi jen "nejaky" ramecek.
		var accent: Color = WON_GREEN if done else MENU_EDGE
		var edge_a: float = 0.90 if done else 0.55
		draw_rect(r, MENU_BG, true)
		draw_rect(r, Color(accent.r, accent.g, accent.b, edge_a), false, maxf(2.0, r.size.x * 0.03))
		var npx: int = _fit_px(str(n), r.size.x - 12.0, int(r.size.y * 0.46), 14)
		draw_string(f, Vector2(r.position.x, r.position.y + r.size.y * 0.56),
			str(n), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, npx, Color(0.90, 0.87, 0.80))
		if done:
			# FAJFKA misto popisku: dve tlusty cary. Znak "✓" v zakladnim pismu
			# Godotu neni - kdyz chybi, nakresli se prazdny ctverecek.
			_check_mark(r)
		else:
			var cpx: int = _fit_px("odemčeno", r.size.x - 10.0, int(r.size.y * 0.24), 9)
			draw_string(f, Vector2(r.position.x, r.position.y + r.size.y * 0.88),
				"odemčeno", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, cpx,
				Color(accent.r, accent.g, accent.b, 0.9))
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
	var rows: Array = _settings_rows()
	var r0: Rect2 = layout.settings_rows[0] if not layout.settings_rows.is_empty() else Rect2()
	_label("NASTAVENÍ", Rect2(0.0, r0.position.y - float(layout.menu_title_px) * 1.6,
		layout.view.x, float(layout.menu_title_px)), layout.menu_title_px, Color(0.90, 0.87, 0.80))
	var f: Font = ThemeDB.fallback_font
	# RADKY SE KRESLI PODLE INDEXU (jeden zdroj pravdy s klepanim): kdo prida
	# volbu do `_settings_rows()`, dostane i radek - a nic se nerozjede.
	for i in range(mini(rows.size(), layout.settings_rows.size())):
		var r: Rect2 = layout.settings_rows[i]
		var name: String = String(rows[i][0])
		var val: String = String(rows[i][1])
		var px: int = _fit_px(name, r.size.x * 0.6, layout.menu_item_px, 12)
		draw_rect(r, MENU_BG, true)
		draw_rect(r, Color(MENU_EDGE.r, MENU_EDGE.g, MENU_EDGE.b, 0.55), false, 2.0)
		draw_string(f, Vector2(r.position.x + 12.0, r.position.y + r.size.y * 0.5 + float(px) * 0.36),
			name, HORIZONTAL_ALIGNMENT_LEFT, r.size.x * 0.6, px, Color(0.90, 0.87, 0.80))
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


# ROZEHRANA PARTIE SE NASLA NA DISKU (hrac se vratil z pozadi). Text rekne,
# KDE se vrati - hrac ma poznat, ze neprijde o level, ktery uz rozjel.
func _draw_resume() -> void:
	var i: Dictionary = BattleSave.info()
	var sub: String = "Uložená partie se nenačetla."
	if not i.is_empty():
		sub = "Level %d · vlna %d · na ploše %d poutníků." % [
			int(i["level"]), int(i["wave"]), int(i["pilgrims"])]
	_draw_dialog("Pokračovat v rozehrané partii?", sub,
		"POKRAČOVAT", Color(0.65, 0.78, 0.60), "NOVÁ PARTIE", Color(0.72, 0.70, 0.62))


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
