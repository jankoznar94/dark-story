extends Node2D

# Jedina scena hry. Vsechno se KRESLI rucne - zadne Button nody,
# zadne theme, zadne hover/focus efekty. Jeden vstupni bod, jeden hit-test.
#
# POSKOZENI DELA CELEK USEKU, ne vez. Proto se tady kresli DMG ZONY -
# barevny pas pres cely rovny usek kazdeho pruhu. Hrac tak vidi, kde se
# bude poutnikum ubirat zivot, a kde ne.
#
# HERNI DESKA NENESE ZADNY TEXT ANI ZADNE OVLADANI. Popisky vyhybky,
# vystupu i kmene jsou pryc (jsou v menu pod NAVODEM) a zmizel i cely spodni
# pruh vcetne tlacitka SKIP - deska saha az k spodnimu okraji displeje.
# Vsechno vysvetleni je v NAVODU a cisla poskozeni v hornim panelu; deska ma
# jen znacky (runy, barvy, tvary).
#
# ROZVRZENI JE RESPONZIVNI: pozice jdou z realne velikosti okna pres
# ScreenLayout, velikosti z jednoho meritka. Pri zmene velikosti okna se
# sit prelozi za behu.

const MAX_TOAST := 3.0
# Sirka pasu dmg zony. Je to ZNACKA, ne presna mechanika - mechanika je
# "cely usek", ale pas to musi ukazat citelne.
const ZONE_THICK := 24.0

# VELIKOST POUTNIKA. Je to znacka, ktera musi byt citelna na telefonu -
# poutnik je to, na co se hrac cely cas kouka, takze je vetsi nez zbytek
# znacek. Polomer je v meritku herni plochy (`s`), takze kruh zustane kruhem
# na kazdem displeji.
const ENEMY_R_OUT := 20.0
const ENEMY_R_IN := 17.0
const ENEMY_GLYPH := 11.0
const ENEMY_HP_R := 25.0

var layout := ScreenLayout.new()
var game: Game = null
var menu := Menu.new()
var settings := Settings.new()
var editor := Editor.new()
var toast: String = ""
var toast_t: float = 0.0
var last_log_size: int = 0

var _font: Font = null
var _shot: bool = false
var _shot_frames: int = 0
var _tap_live: bool = false

var _music: AudioStreamPlayer = null
var _sfx: AudioStreamPlayer = null
var _music_playing: bool = false


func _ready() -> void:
	_font = ThemeDB.fallback_font
	game = Game.new()
	menu.web = OS.has_feature("web")
	if menu.web:
		_install_js_bridge()
		menu.load_build_id()
	settings.load_from_disk()
	_setup_audio()
	_place_to_window()
	get_viewport().size_changed.connect(_on_resize)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--shot"):
		_setup_shot()
	elif args.has("--menu-shot"):
		# Snimek menu: jen se zmrazi a vyfoti prvni obrazovka.
		_shot = true
	elif args.has("--guide-shot"):
		menu.open_guide()
		_shot = true
	elif args.has("--settings-shot"):
		menu.open_settings()
		_shot = true
	elif args.has("--editor-shot"):
		# Snimek editoru: hra se postavi z levelu, ktery je prave v editoru.
		_open_editor()
		_shot = true
	elif args.has("--battle"):
		# Rovnou do hry - pouziva se pri kontrole vzhledu herni plochy.
		_start_battle()

# Most z JavaScriptu zpet do hry. JavaScriptBridge.eval vrati u Promise
# null, ne vysledek, takze vysledky (otisk buildu, stav aktualizace) musi
# poslat JS sam pres tyhle dve funkce.
func _install_js_bridge() -> void:
	JavaScriptBridge.create_callback(_js_set_version)
	JavaScriptBridge.create_callback(_js_on_update)


func _js_set_version(args: Array) -> void:
	if args.size() < 1:
		return
	var s: String = str(args[0])
	if not s.is_empty():
		menu.build_id = s


func _js_on_update(args: Array) -> void:
	if args.size() < 1:
		return
	menu.apply_update_note(str(args[0]))


func _place_to_window() -> void:
	layout.compute(get_viewport_rect().size)
	if game == null:
		game = Game.new()
		game.setup(layout.arena, layout.s, layout.board_bottom)
	else:
		_reflow()


# Preklopeni site na aktualni rozvrzeni. `bar_top` jde do build() jako
# parametr - kdyby se nastavil az na hotove siti, pocital by stary okraj.
func _reflow() -> void:
	# Editor ma svou plochu - ma dole pruh tlacitek, ktery hra nema. Sit se
	# prelozi podle toho, ktera obrazovka je otevrena.
	if menu.is_editor():
		game.rebuild_network(layout.editor_arena, layout.s,
			layout.editor_arena.end.y + 20.0 * layout.s)
		return
	game.rebuild_network(layout.arena, layout.s, layout.board_bottom)


func _on_resize() -> void:
	layout.compute(get_viewport_rect().size)
	# Stav hry zustava, prelozi se jen geometrie site.
	_reflow()


# Nahledovy rezim pro kontrolu vzhledu: postavi ukazkovou sit a zmrazi hru
# v okamziku, kdy jsou poutnici na usecich, aby snimek neukazal prazdno.
func _setup_shot() -> void:
	menu.open_battle()
	game.gold = 5000
	for lane in range(game.net.lane_count()):
		if game.net.lane_accepts(lane, game.net.lane_element(lane)):
			game.try_build(lane, 0, game.net.lane_element(lane))
			game.try_build(lane, 2, game.net.lane_element(lane))
	game.wave = 3
	game.gold = 240
	game.lives = 9
	game.phase = "wave"
	game.spawn_left = 4
	game.set_switch(1)
	for el in [Element.FIRE, Element.EARTH, Element.WATER, Element.AIR, Element.FIRE]:
		game.debug_spawn(el)
	game.run_for(11.0)
	_shot = true


func _process(delta: float) -> void:
	if _shot:
		_shot_frames += 1
		if _shot_frames == 3:
			get_viewport().get_texture().get_image().save_png("user://shot.png")
			print("SHOT_SAVED=true")
			get_tree().quit()
		queue_redraw()
		return
	_sync_audio()
	if menu.is_battle() and game != null and game.phase != "lost":
		game.step(delta)
	if menu.is_battle():
		_pull_toast(delta)
	queue_redraw()


func _pull_toast(delta: float) -> void:
	if game != null and game.log.size() != last_log_size:
		last_log_size = game.log.size()
		if last_log_size > 0:
			toast = game.log[last_log_size - 1]
			toast_t = MAX_TOAST
	if toast_t > 0.0:
		toast_t -= delta


# ---------------------------------------------------------------- zvuk

# Dve vetve zvuku: hudba a efekty, kazda se daji zvlast vypnout. Zvuk se
# GENERUJE (basova linka + tuknuti pri stisku), protoze hra zadne audio
# soubory neveze - a ticho by u "zapni/vypni hudbu" nešlo poznat.
func _setup_audio() -> void:
	var snd := Sound.new()
	_music = AudioStreamPlayer.new()
	_music.stream = snd.music_loop()
	_music.volume_db = -16.0
	_music.bus = "Master"
	add_child(_music)
	_sfx = AudioStreamPlayer.new()
	_sfx.stream = snd.sfx_tap()
	_sfx.volume_db = -12.0
	_sfx.bus = "Master"
	# DULEZITE: bez polyfonie kazde dalsi klepnuti PRERUSI to predchozi a Godot
	# stream restartuje - a to je ostri rez uprostred obalky, tedy cvaknuti.
	# Se polyfonii kazde tuknuti dozni, misto aby ho dalsi utalo.
	#
	# ALE POZOR: hrac klepe rychle a hlasy se scitaji. Osm tuknuti pres sebe
	# je +9 dB a Master zacne limitovat - a limitace je presne to praskani,
	# ktere slysel. Proto strop 4 hlasy a nizsi hlasitost: i ctyri pres sebe
	# zustanou pod limitem.
	_sfx.max_polyphony = 4
	add_child(_sfx)


func _sync_audio() -> void:
	if _music == null:
		return
	if settings.music and not _music_playing:
		_music.play()
		_music_playing = true
	elif not settings.music and _music_playing:
		_music.stop()
		_music_playing = false


func _click() -> void:
	if settings.sfx and _sfx != null:
		_sfx.play()


# Kolo z menu. Hraje se ZAKLADNI deska - ta je na balanc vyladena. Levely
# z editoru se hraji z editoru (a zakotvene si hrac vybere v menu).
func _start_battle() -> void:
	game.setup(layout.arena, layout.s, layout.board_bottom)
	menu.open_battle()


# ---------------------------------------------------------------- vstup

# Jeden dotek se dorucuje DVAKRAT (Godot emuluje mys z dotyku), takze
# kazdy handler, ktery na stisk neco udela, udela to dvakrat. Guard drzi
# jen stisky, pohyb propousti.
func _input(event: InputEvent) -> void:
	var pos := Vector2(-1.0, -1.0)
	var press := false
	var release := false
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		pos = st.position
		press = st.pressed
		release = not st.pressed
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		pos = mb.position
		if mb.button_index == MOUSE_BUTTON_LEFT:
			press = mb.pressed
			release = not mb.pressed
	else:
		return
	if press:
		if _tap_live:
			return
		_tap_live = true
		_handle_tap(pos)
		get_viewport().set_input_as_handled()
	elif release:
		_tap_live = false


func _handle_tap(pos: Vector2) -> void:
	if menu.is_menu():
		_handle_menu_tap(pos)
		return
	if menu.is_guide():
		_handle_guide_tap(pos)
		return
	if menu.is_settings():
		_handle_settings_tap(pos)
		return
	if menu.is_editor():
		_handle_editor_tap(pos)
		return
	# Na desce uz zadne tlacitko neni - jedina interakce je klepnuti na misto
	# na bonus (stavi / vylepsi) a klepnuti kamkoli JINAM na usek (prepne
	# vyhybku). Zadna tlacitka vyhybky nejsou: casem jich bude vic, nez se
	# jich do pruhu vejde, a usek je to, na co se stejne kouka.
	var cell: Vector2i = game.net.nearest_slot(pos)
	if cell.x >= 0:
		_click()
		if game.bonus_at(cell.x, cell.y) != null:
			game.try_upgrade(cell.x, cell.y)
			return
		game.try_build(cell.x, cell.y, game.build_element(cell.x))
		return
	var lane: int = game.net.lane_tap_at(pos, maxf(12.0, 20.0 * layout.s))
	if lane >= 0:
		_click()
		game.set_switch(lane)


# MENU: ctyři tlacitka. Battle spusti kolo, Navod vysvetli pravidla,
# Settings otevre nastaveni, Update si vyzada novou verzi PWA.
func _handle_menu_tap(pos: Vector2) -> void:
	for i in range(layout.menu_buttons.size()):
		var r: Rect2 = layout.menu_rect(i)
		if not r.has_point(pos):
			continue
		_click()
		match i:
			0:
				_start_battle()
			1:
				menu.open_guide()
			2:
				menu.open_settings()
			3:
				menu.request_update()
		return


# NAVOD: jedine tlacitko ZPET.
func _handle_guide_tap(pos: Vector2) -> void:
	if layout.guide_back.has_point(pos):
		_click()
		menu.open_menu()


# EDITOR: klepnuti na usek ho vybere, klepnuti na tlacitko neco zmeni.
# Poradi je dulezite: NEJDRIV tlacitka. Kdyby se hledal usek prvni, klepnuti
# na tlacitko v pruhu by mohlo vybrat usek, ktery pod nim vede - a tlacitko
# by nikdy nezabralo.
func _handle_editor_tap(pos: Vector2) -> void:
	for i in range(layout.ed_buttons.size()):
		var r: Rect2 = layout.ed_buttons[i]
		if not r.has_point(pos):
			continue
		_click()
		editor.press(i)
		_push_editor_level()
		if i == Editor.BTN_PLAY:
			_play_editor_level()
		return
	var lane: int = game.net.lane_tap_at(pos, maxf(16.0, 26.0 * layout.s))
	if lane >= 0:
		_click()
		editor.sel = lane
		editor.status = "úsek %d" % (lane + 1)


# Editor si drzi vlastni level a hra dostane jeho kopii. Kdyby dostala level
# sam, sahala by do nej za behu (bonusy se vazi na usek) a hrac by si rozbil
# to, co prave upravuje.
func _push_editor_level() -> void:
	game.set_level(editor.level.clone(), layout.editor_arena, layout.s,
		layout.editor_arena.end.y + 20.0 * layout.s)
	_reflow_editor()


# HRAT Z EDITORU. Hrac si level vyrobi a hned si ho zahraje - bez toho by
# musel level ulozit, vratit se do menu a doufat, ze se hra postavi z toho
# spravneho. Do hry jde KOPIE: editor si svuj level necha.
func _play_editor_level() -> void:
	game.setup(layout.arena, layout.s, layout.board_bottom, editor.level.clone())
	menu.open_battle()


func _open_editor() -> void:
	menu.open_editor()
	editor.reset()
	_push_editor_level()


func _draw_editor() -> void:
	_draw_background()
	_draw_trunk()
	_draw_lanes()
	_draw_zones()
	_draw_slots()
	_draw_exits()
	_draw_switch()
	_draw_bonuses()
	_draw_editor_markers()
	_draw_editor_bar()


# Vybrany usek je v editoru ZNACKA navic - hrac musi videt, co upravuje.
# Meni se jen jas a tvar ukazatele, ne barva: barva je element.
func _draw_editor_markers() -> void:
	var n: int = game.net.lane_count()
	if n == 0:
		return
	var lane: int = clampi(editor.sel, 0, n - 1)
	var y: float = game.net.rows[lane]
	var r: float = game.net.bonus_r * 0.7
	var col: Color = _lane_color(lane)
	var x: float = game.net.band_x0 - 34.0 * layout.s
	draw_colored_polygon(PackedVector2Array([
		Vector2(x + r, y), Vector2(x - r * 0.7, y - r), Vector2(x - r * 0.7, y + r)]), col)
	draw_arc(Vector2(x, y), r * 1.8, 0.0, TAU, 20, Color(col.r, col.g, col.b, 0.55), 2.0)


func _draw_editor_bar() -> void:
	var btns: Array = layout.ed_buttons
	if btns.is_empty():
		return
	var top: float = float(btns[0].position.y) - 26.0 * layout.ui
	draw_rect(Rect2(0.0, top, layout.view.x, layout.view.y - top), Color(0.075, 0.07, 0.065))
	draw_line(Vector2(0.0, top), Vector2(layout.view.x, top), Color(0.28, 0.25, 0.21), 2.0)
	# Nad pruhem je jedine misto v editoru, kde muze byt text: rika, ktery
	# usek je vybrany a co se prave stalo. Deska zustava bez textu.
	_label(Vector2(14.0 * layout.ui, top - 8.0 * layout.ui), editor.sel_text(), 14,
		Color(0.88, 0.85, 0.78))
	if not editor.status.is_empty():
		_label(Vector2(layout.view.x - 14.0 * layout.ui, top - 8.0 * layout.ui),
			editor.status, 14, Color(0.72, 0.70, 0.62), false, 1.0)
	# KOD LEVELU. Kdyz je vyexportovany, ukaze se nad pruhem - hrac ho odsud
	# opise nebo zkopiruje a posle. Delsi nez sirka displeje se zkrati; cely
	# je v souboru vedle (a v hlásce je cesta k nemu).
	if not editor.code.is_empty():
		var cw: float = layout.view.x - 28.0 * layout.ui
		_label(Vector2(14.0 * layout.ui, top + 16.0 * layout.ui),
			editor.code, 11, Color(0.80, 0.84, 0.70), false, cw)
	for i in range(btns.size()):
		var r: Rect2 = btns[i]
		draw_rect(r, Color(0.135, 0.125, 0.11))
		var accent: Color = Color(0.42, 0.40, 0.35)
		if i == Editor.BTN_EXPORT:
			accent = Color(0.65, 0.78, 0.60)
		elif i == Editor.BTN_PLAY:
			accent = Color(0.78, 0.62, 0.30)
		draw_rect(r, Color(accent.r, accent.g, accent.b, 0.55), false, 2.0)
		_draw_centered(Editor.BTN_LABELS[i], r, r.position.y + r.size.y * 0.64, 13,
			Color(0.88, 0.85, 0.78))


func _reflow_editor() -> void:
	_reflow()


# NASTAVENI: dve prepinaci policka (hudba, zvuky) a zpet do menu.
func _handle_settings_tap(pos: Vector2) -> void:
	if layout.settings_back.has_point(pos):
		_click()
		menu.open_menu()
		return
	# Prepinace jsou prvni dva radky (hudba, zvuky); treti je ZPET vyse.
	var gap: float = layout.row_gap()
	var r: Rect2 = layout.settings_toggle
	for i in range(2):
		var row := Rect2(r.position.x, r.position.y + float(i) * (r.size.y + gap),
			r.size.x, r.size.y)
		if row.has_point(pos):
			_click()
			if i == 0:
				settings.toggle_music()
			else:
				settings.toggle_sfx()
			return


# ---------------------------------------------------------------- kresleni

func _draw() -> void:
	if menu.is_menu():
		_draw_menu()
		return
	if menu.is_guide():
		_draw_guide()
		return
	if menu.is_settings():
		_draw_settings()
		return
	if menu.is_editor():
		_draw_editor()
		return
	_draw_battle()


# HERNI DESKA. Pruh je pryc, takze posledni prvek je HUD - a deska saha
# az k spodnimu okraji displeje.
func _draw_battle() -> void:
	_draw_background()
	_draw_trunk()
	_draw_lanes()
	_draw_zones()
	_draw_slots()
	_draw_exits()
	_draw_switch()
	_draw_bonuses()
	_draw_enemies()
	_draw_hud()


# ---------------------------------------------------------------- menu

# Prvni obrazovka. Plochy, strojovy design jako zbytek hry - zadne karty,
# zadne efekty. Ctyři tlacitka: Battle, Navod, Settings, Update.
func _draw_menu() -> void:
	draw_rect(Rect2(Vector2.ZERO, layout.view), Color(0.10, 0.095, 0.085))
	# Naznak zelek jako v pozadi hry, aby menu a hra vypadaly jako jedna vec.
	for i in range(9):
		var t: float = float(i) / 8.0
		var y: float = t * layout.view.y
		draw_line(Vector2(0.0, y + 12.0 * layout.s),
			Vector2(layout.view.x, y - 18.0 * layout.s),
			Color(0.155, 0.14, 0.12, 0.55), 1.0)

	var cx: float = layout.view.x * 0.5
	_label(Vector2(cx, layout.menu_title_y), Menu.TITLE, 44,
		Color(0.90, 0.87, 0.80), true, layout.view.x)
	_label(Vector2(cx, layout.menu_title_y + 26.0 * layout.ui), Menu.SUBTITLE, 14,
		Color(0.58, 0.55, 0.49), true, layout.view.x)

	var names: Array = Menu.MENU_ITEMS
	var subs: Array = Menu.MENU_SUBS
	for i in range(layout.menu_buttons.size()):
		var r: Rect2 = layout.menu_rect(i)
		var accent: Color = Color(0.72, 0.70, 0.62)
		if i == 0:
			accent = Color(0.78, 0.62, 0.30)
		draw_rect(r, Color(0.135, 0.125, 0.11))
		draw_rect(r, Color(accent.r, accent.g, accent.b, 0.55), false, 2.0)
		_draw_centered(names[i], r, r.position.y + r.size.y * 0.52, 22, Color(0.90, 0.87, 0.80))
		_draw_centered(subs[i], r, r.position.y + r.size.y * 0.86, 12, Color(0.56, 0.53, 0.48))

	if not menu.update_note.is_empty():
		_label(Vector2(cx, layout.menu_buttons[3].end.y + 30.0 * layout.ui), menu.update_note, 13,
			Color(0.72, 0.70, 0.62), true, layout.view.x * 0.9)

	# Otisk buildu. Bez nej se neda poznat, jestli hra po aktualizaci opravdu
	# bezi z nove verze, nebo ji jeste drzi cache service workera - presne to
	# hrace mate. Je to mala informace v rohu, ne ovladaci prvek.
	_label(Vector2(cx, layout.view.y - 10.0 * layout.ui),
		"build %s" % menu.build_id, 11, Color(0.42, 0.40, 0.36), true, layout.view.x)


# NAVOD. Neni to souvisly text - jsou to BLOKY a kazdy blok je OBRAZEK
# s jednou kratkou vetou. Obrazky se kresli stejnymi znackami zivlu jako hra,
# takze se hrac uci presne to, co pak na desce uvidí.
#
# Na sirokem displeji jsou bloky ve DVOU SLOUPCICH (2x2) a kazdy ma obrazek
# vlevo a text vpravo. Na uzke/male obrazovce jdou pod sebe.
func _draw_guide() -> void:
	draw_rect(Rect2(Vector2.ZERO, layout.view), Color(0.10, 0.095, 0.085))
	var left: float = _pad_left()
	var top: float = 10.0 * layout.ui
	var avail_w: float = layout.view.x - left * 2.0
	# ZPET je v rohu obrazovky, text si nad nim nechava misto.
	var avail_h: float = layout.guide_back.position.y - top - 8.0 * layout.ui
	var wide: bool = layout.view.x >= 700.0

	var px: int = Guide.fit_px(_font, avail_w, avail_h, wide)
	var fs: int = maxi(px, Guide.MIN_PX)
	var count: int = Guide.BLOCKS.size()
	var cols: int = 2 if wide else 1
	var rows: int = int(ceil(float(count) / float(cols)))
	var cell_w: float = avail_w / float(cols)
	var cell_h: float = (avail_h - float(fs) * 1.9) / float(rows)

	_label(Vector2(left, top + float(fs) * 1.1), Guide.TITLE, fs + 7,
		Color(0.90, 0.87, 0.80), false, avail_w)

	for i in range(count):
		var b: Dictionary = Guide.BLOCKS[i]
		var col: int = i % cols
		var row: int = i / cols
		var origin := Vector2(left + cell_w * float(col), top + float(fs) * 1.9 + cell_h * float(row))
		_draw_guide_block(b, origin, cell_w, cell_h, fs)

	var br: Rect2 = layout.guide_back
	draw_rect(br, Color(0.20, 0.19, 0.17))
	draw_rect(br, Color(0.38, 0.35, 0.30), false, 2.0)
	_draw_centered(Guide.BACK, br, br.position.y + br.size.y * 0.64, 18, Color(0.85, 0.82, 0.76))


func _draw_guide_block(b: Dictionary, origin: Vector2, cell_w: float, cell_h: float,
		fs: int) -> void:
	var pad: float = float(fs) * 0.8
	var art_w: float = Guide.art_width(cell_w, cell_h, true)
	var art_h: float = maxf(float(fs) * 3.0, cell_h - pad * 2.0)
	var art := Rect2(origin.x + pad, origin.y + pad, art_w, art_h)
	draw_rect(art, Color(0.125, 0.115, 0.10))
	draw_rect(art, Color(0.24, 0.22, 0.19), false, 1.0)

	var txt_x: float = art.end.x + float(fs) * 1.1
	var txt_w: float = origin.x + cell_w - pad - txt_x
	_label(Vector2(txt_x, origin.y + pad + float(fs) * 0.95), str(b["title"]),
		fs + 4, Color(0.86, 0.83, 0.75), false, txt_w)
	var lines: Array = Guide.caption(_font, fs, txt_w, str(b["text"]))
	var ly: float = origin.y + pad + float(fs) * 0.95 + float(fs) * 1.5
	for line in lines:
		_label(Vector2(txt_x, ly), str(line), fs, Color(0.70, 0.67, 0.60), false, txt_w)
		ly += float(fs) * 1.35

	# Obrazek kresli hra sama - stejnymi znackami, jake ma na desce.
	match str(b["art"]):
		"_guide_switch":
			_guide_switch(art, fs)
		"_guide_damage":
			_guide_damage(art, fs)
		"_guide_bonus":
			_guide_bonus(art, fs)
		"_guide_exit":
			_guide_exit(art, fs)
		"_guide_lane":
			_guide_lane(art, fs)


# OBRAZEK 1: vyhybka. Kmen se rozvetvuje na useky, vybrany je svetlejsi -
# presne to, co hrac na desce vidi, kdyz klepne.
func _guide_switch(r: Rect2, fs: int) -> void:
	var y: float = r.get_center().y
	var x0: float = r.position.x + r.size.x * 0.12
	var xm: float = r.position.x + r.size.x * 0.46
	var x1: float = r.position.x + r.size.x * 0.88
	draw_line(Vector2(x0, y), Vector2(xm, y), Color(0.45, 0.41, 0.35), float(fs) * 0.28)
	var spread: float = r.size.y * 0.30
	var lanes := [Vector2(x1, y - spread), Vector2(x1, y), Vector2(x1, y + spread)]
	var sel: int = 1
	for i in range(lanes.size()):
		var col: Color = [Element.color_of(Element.FIRE), Element.color_of(Element.WATER),
			Element.color_of(Element.EARTH)][i]
		var a: float = 0.95 if i == sel else 0.30
		draw_line(Vector2(xm, y), lanes[i], Color(col.r, col.g, col.b, a),
			float(fs) * (0.26 if i == sel else 0.16))
	draw_circle(Vector2(xm, y), float(fs) * 0.34, Color(0.10, 0.095, 0.085))
	draw_arc(Vector2(xm, y), float(fs) * 0.34, 0.0, TAU, 20,
		Element.color_of(Element.WATER), 2.0)
	# Kolecko mysi/prstu nad vybranym usekem - znacka "klepni sem".
	var px: float = xm + (x1 - xm) * 0.45
	draw_arc(Vector2(px, lanes[sel].y), float(fs) * 0.30, 0.0, TAU, 18,
		Color(0.90, 0.87, 0.80), 2.0)


# OBRAZEK 2: poskozeni. Tri useky s runou, u kazdeho nasobek - vlastni 0 %,
# jiné 50 %, protiklad 200 %. Cisla, ne jen barvy.
func _guide_damage(r: Rect2, fs: int) -> void:
	var cx: float = r.position.x + r.size.x * 0.5
	var c := Vector2(cx, r.get_center().y)
	var rr: float = minf(r.size.x * 0.16, r.size.y * 0.22)
	var ring := float(fs) * 0.75
	var els := [Element.FIRE, Element.WATER, Element.EARTH]
	var mults := ["2.0", "0", "0.5"]
	var pos := [c + Vector2(-ring * 1.5, 0.0), c, c + Vector2(ring * 1.5, 0.0)]
	for i in range(els.size()):
		var col: Color = Element.color_of(els[i])
		draw_circle(pos[i], rr, Color(col.r, col.g, col.b, 0.22))
		draw_arc(pos[i], rr, 0.0, TAU, 22, col, 2.0)
		_glyph(els[i], pos[i], rr * 0.52, col)
	# Sipka od Ohne k Vode (protiklad) a k Zemi (jiný).
	_arrow(pos[0] + Vector2(rr + 2.0, 0.0), pos[1] - Vector2(rr + 2.0, 0.0),
		Element.color_of(Element.WATER))
	_arrow(pos[0] + Vector2(rr * 0.8, rr * 0.8), pos[2] - Vector2(rr * 0.8, rr * 0.8),
		Element.color_of(Element.EARTH))
	_label(Vector2(cx, pos[0].y - rr - float(fs) * 0.4), mults[0], fs,
		Color(0.90, 0.85, 0.60), true, r.size.x)
	_label(Vector2(cx, pos[1].y - rr - float(fs) * 0.4), mults[1], fs,
		Color(0.60, 0.57, 0.51), true, r.size.x)
	_label(Vector2(cx, pos[2].y + rr + float(fs) * 1.0), mults[2], fs,
		Color(0.70, 0.67, 0.60), true, r.size.x)


func _arrow(a: Vector2, b: Vector2, col: Color) -> void:
	draw_line(a, b, Color(col.r, col.g, col.b, 0.7), 2.0)
	var d: Vector2 = (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([b, b - d * 7.0 + n * 4.0, b - d * 7.0 - n * 4.0]), col)


# OBRAZEK 3: bonus. Usek s prazdnym mistem (obrys s runou) a vedle hotovy
# bonus - hrac vidi, co ma hledat a co z toho vznikne.
func _guide_bonus(r: Rect2, fs: int) -> void:
	var y: float = r.get_center().y
	var col: Color = Element.color_of(Element.AIR)
	var rr: float = minf(r.size.x * 0.13, r.size.y * 0.24)
	var x0: float = r.position.x + r.size.x * 0.24
	var x1: float = r.position.x + r.size.x * 0.72
	draw_line(Vector2(r.position.x + r.size.x * 0.08, y),
		Vector2(r.position.x + r.size.x * 0.92, y),
		Color(col.r, col.g, col.b, 0.35), float(fs) * 0.20)
	# Prazdne misto: obrys + runa = "sem muzes postavit".
	draw_arc(Vector2(x0, y), rr, 0.0, TAU, 22, Color(col.r, col.g, col.b, 0.45), 2.0)
	_glyph(Element.AIR, Vector2(x0, y), rr * 0.52, Color(col.r, col.g, col.b, 0.5))
	var side: float = minf(r.size.x * 0.10, rr * 1.3)
	draw_rect(Rect2(Vector2(x1, y) - Vector2(side, side), Vector2(side, side) * 2.0), col)
	_glyph(Element.AIR, Vector2(x1, y), side * 0.62, Color(0.07, 0.06, 0.06))
	_arrow(Vector2(x0 + rr + 3.0, y), Vector2(x1 - side - 3.0, y), Color(0.55, 0.52, 0.46))


# OBRAZEK 4: vystup. Krizek je jiny tvar nez vsechny runy - nema element,
# nikdo ho nevlastni a kdo tam dojde, stoji zivot. U toho srdce.
func _guide_exit(r: Rect2, fs: int) -> void:
	var c := Vector2(r.get_center().x - r.size.x * 0.12, r.get_center().y)
	var rr: float = minf(r.size.x * 0.15, r.size.y * 0.30)
	draw_circle(c, rr, Color(0.13, 0.12, 0.11))
	draw_arc(c, rr, 0.0, TAU, 28, Color(0.62, 0.58, 0.52), 3.0)
	var d: float = rr * 0.42
	draw_line(c - Vector2(d, d), c + Vector2(d, d), Color(0.72, 0.68, 0.60), 3.0)
	draw_line(c + Vector2(d, -d), c - Vector2(d, -d), Color(0.72, 0.68, 0.60), 3.0)
	# Srdce = zivot. Kresli se dvema kruhy a trojuhelnikem, aby to nebyl
	# jen dalsi runa - tvar je jedina znacka, ktera tu muze fungovat.
	var hc := Vector2(c.x + rr * 2.4, c.y)
	var hr: float = rr * 0.62
	var col := Color(0.85, 0.42, 0.36)
	draw_circle(hc + Vector2(-hr * 0.5, -hr * 0.35), hr * 0.56, col)
	draw_circle(hc + Vector2(hr * 0.5, -hr * 0.35), hr * 0.56, col)
	draw_colored_polygon(PackedVector2Array([
		hc + Vector2(-hr * 0.98, -hr * 0.12), hc + Vector2(hr * 0.98, -hr * 0.12),
		hc + Vector2(0.0, hr * 1.05)]), col)
	_arrow(Vector2(c.x + rr + 3.0, c.y), Vector2(hc.x - hr * 1.15, c.y), col)


# OBRAZEK 5: useky. Nahore neutralni (sedivy, bere vsem stejne) a pod nim
# elementarni s runou. Hrac vidi rozdil, ktery se jinak pozna jen hranim.
func _guide_lane(r: Rect2, fs: int) -> void:
	var y0: float = r.position.y + r.size.y * 0.30
	var y1: float = r.position.y + r.size.y * 0.72
	var x0: float = r.position.x + r.size.x * 0.08
	var x1: float = r.position.x + r.size.x * 0.92
	var neu := Color(0.55, 0.53, 0.48)
	var fire: Color = Element.color_of(Element.FIRE)
	var lw: float = maxf(2.0, float(fs) * 0.28)
	draw_line(Vector2(x0, y0), Vector2(x1, y0), Color(neu.r, neu.g, neu.b, 0.80), lw)
	draw_line(Vector2(x0, y1), Vector2(x1, y1), Color(fire.r, fire.g, fire.b, 0.80), lw)
	# Neutralni nema runu, elementarni ano - presne ten rozdil, ktery
	# pozna i hrac, ktery barvy nerozlisuje.
	draw_arc(Vector2((x0 + x1) * 0.5, y1), float(fs) * 0.60, 0.0, TAU, 22,
		Color(fire.r, fire.g, fire.b, 0.45), 2.0)
	_glyph(Element.FIRE, Vector2((x0 + x1) * 0.5, y1), float(fs) * 0.32, fire)


func _pad_left() -> float:
	return 22.0 * layout.ui


func _draw_settings() -> void:
	draw_rect(Rect2(Vector2.ZERO, layout.view), Color(0.10, 0.095, 0.085))
	var cx: float = layout.view.x * 0.5
	_label(Vector2(cx, layout.settings_toggle.position.y - 34.0 * layout.ui), "NASTAVENÍ", 30,
		Color(0.90, 0.87, 0.80), true, layout.view.x)

	var r: Rect2 = layout.settings_toggle
	var labels := ["Hudba", "Zvuky"]
	var values := [settings.music, settings.sfx]
	var sgap: float = layout.row_gap()
	for i in range(2):
		var row := Rect2(r.position.x, r.position.y + float(i) * (r.size.y + sgap),
			r.size.x, r.size.y)
		draw_rect(row, Color(0.135, 0.125, 0.11))
		var on: bool = bool(values[i])
		var col: Color = Color(0.65, 0.78, 0.60) if on else Color(0.42, 0.39, 0.35)
		draw_rect(row, Color(col.r, col.g, col.b, 0.55), false, 2.0)
		_label(Vector2(row.position.x + 18.0 * layout.ui,
			row.position.y + row.size.y * 0.62), labels[i], 18, Color(0.88, 0.85, 0.78))
		_label(Vector2(row.end.x - 18.0 * layout.ui, row.position.y + row.size.y * 0.62),
			"ZAPNUTO" if on else "VYPNUTO", 15, col, false, 1.0)
		# Zaskrtavatko je druha znacka krome barvy - ne jen barva.
		var bx: float = row.end.x - 108.0 * layout.ui
		var by: float = row.get_center().y
		draw_rect(Rect2(bx - 1.0, by - 11.0, 22.0, 22.0), Color(0.09, 0.085, 0.08))
		draw_rect(Rect2(bx - 1.0, by - 11.0, 22.0, 22.0), col, false, 2.0)
		if on:
			draw_line(Vector2(bx + 3.0, by), Vector2(bx + 8.0, by + 6.0), col, 3.0)
			draw_line(Vector2(bx + 8.0, by + 6.0), Vector2(bx + 18.0, by - 7.0), col, 3.0)

	var br: Rect2 = layout.settings_back
	draw_rect(br, Color(0.20, 0.19, 0.17))
	draw_rect(br, Color(0.38, 0.35, 0.30), false, 2.0)
	_draw_centered("ZPĚT", br, br.position.y + br.size.y * 0.62, 20, Color(0.85, 0.82, 0.76))


func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, layout.view), Color(0.10, 0.095, 0.085))
	draw_rect(layout.arena, Color(0.125, 0.115, 0.10))
	for i in range(9):
		var t: float = float(i) / 8.0
		var y: float = layout.arena.position.y + t * layout.arena.size.y
		draw_line(Vector2(layout.arena.position.x, y + 12.0 * layout.s),
			Vector2(layout.arena.end.x, y - 18.0 * layout.s),
			Color(0.155, 0.14, 0.12, 0.55), 1.0)


# Barva pruhu. Neutralni pruh NENI sedy "bez vyznamu" - je to pruh,
# ktery dela vsem stejne, takze ma vlastni, klidnou barvu.
func _lane_color(lane: int) -> Color:
	if game.net.lane_is_neutral(lane):
		return Color(0.55, 0.53, 0.48)
	return Element.color_of(game.net.lane_element(lane))


func _draw_lanes() -> void:
	var lw: float = maxf(2.0, 9.0 * layout.s)
	var sel: int = game.switch_lane()
	for lane in range(game.net.lane_count()):
		var col: Color = _lane_color(lane)
		var path: PackedVector2Array = game.net.lane_path[lane]
		# VYBRANY USEK JE SVETLEJSI, ALE PORAD SVOJI BARVY. Hrac tak vidi,
		# kam poutniky posle, aniz by musel hadat, ktery element to je -
		# barva ani runa se ne meni, meni se jen jas.
		var faint := col
		faint.a = 0.28 if lane != sel else 0.42
		var bright := col
		bright.a = 0.60 if lane != sel else 0.95
		var core: float = maxf(1.0, 3.0 * layout.s) if lane != sel else maxf(1.0, 4.5 * layout.s)
		if lane == sel:
			var halo := col
			halo.a = 0.16
			for k in range(path.size() - 1):
				draw_line(path[k], path[k + 1], halo, lw * 1.9)
		for k in range(path.size() - 1):
			draw_line(path[k], path[k + 1], faint, lw)
		for k in range(path.size() - 1):
			draw_line(path[k], path[k + 1], bright, core)
		if lane == sel:
			var rim := col
			rim.a = 0.85
			for k in range(path.size() - 1):
				draw_line(path[k], path[k + 1], rim, maxf(1.0, 1.6 * layout.s))


# DMG ZONA. Pres cely rovny usek kazdeho pruhu vede barevny pas - tady
# se poutnikum ubira zivot. Cislo nasobku tu ZAMERNE NENI - hrac ho ma
# v hornim panelu u vybraneho useku.
func _draw_zones() -> void:
	var thick: float = ZONE_THICK * layout.s
	var sel: int = game.switch_lane()
	for lane in range(game.net.lane_count()):
		var col: Color = _lane_color(lane)
		var y: float = game.net.rows[lane]
		var a: float = 0.10 if lane != sel else 0.17
		draw_rect(Rect2(game.net.band_x0, y - thick * 0.5,
			game.net.band_x1 - game.net.band_x0, thick), Color(col.r, col.g, col.b, a))
		# Hranice dmg zony - dve tenke znacky, aby bylo jasne, kde zacina
		# a kde konci. Bez nich by se pas ztratil v pozadi.
		var edge := col
		edge.a = 0.35 if lane != sel else 0.70
		draw_line(Vector2(game.net.band_x0, y - thick * 0.5),
			Vector2(game.net.band_x0, y + thick * 0.5), edge, 2.0)
		draw_line(Vector2(game.net.band_x1, y - thick * 0.5),
			Vector2(game.net.band_x1, y + thick * 0.5), edge, 2.0)


# Neutralni kmen. Nema popisek - deska je bez textu.
func _draw_trunk() -> void:
	var a: Vector2 = game.net.trunk_start
	var b: Vector2 = game.net.merge
	draw_line(a, b, Color(0.42, 0.38, 0.32, 0.75), maxf(2.0, 9.0 * layout.s))
	draw_line(a, b, Color(0.58, 0.53, 0.44, 0.9), maxf(1.0, 3.0 * layout.s))


func _draw_slots() -> void:
	var r: float = game.net.bonus_r
	for lane in range(game.net.lane_count()):
		var col: Color = _lane_color(lane)
		for slot in range(game.net.slot_count()):
			var p: Vector2 = game.net.slot_world(lane, slot)
			var b: Bonus = game.bonus_at(lane, slot)
			if b != null:
				draw_circle(p, r, Color(col.r * 0.40, col.g * 0.40, col.b * 0.40, 0.85))
				draw_arc(p, r, 0.0, TAU, 24, col, 2.0)
				continue
			# Prazdne misto nese RUNU ZIVLU TOHO USEKU - hrac tak vidi, co
			# tam muze postavit, aniz by to musel zkouset. Na neutralnim
			# useku runa neni, protoze tam stat nic nemuze - misto je jen
			# obrys a to je samo informace.
			draw_arc(p, r, 0.0, TAU, 24, Color(col.r, col.g, col.b, 0.30), 2.0)
			if not game.net.lane_is_neutral(lane):
				_glyph(game.net.lane_element(lane), p, r * 0.52,
					Color(col.r, col.g, col.b, 0.42))


func _draw_bonuses() -> void:
	var half: float = 13.0 * layout.s
	for item in game.bonuses:
		var b: Bonus = item
		var p: Vector2 = game.net.slot_world(b.lane, b.slot)
		var col: Color = Element.color_of(b.element)
		draw_rect(Rect2(p.x - half, p.y - half, half * 2.0, half * 2.0), col)
		_glyph(b.element, p, 8.0 * layout.s, Color(0.07, 0.06, 0.06))
		if b.level > 1:
			draw_rect(Rect2(p.x - 9.0 * layout.s, p.y - 21.0 * layout.s,
				6.0 * layout.s, 5.0 * layout.s), Color(0.95, 0.88, 0.6))
			draw_rect(Rect2(p.x + 3.0 * layout.s, p.y - 21.0 * layout.s,
				6.0 * layout.s, 5.0 * layout.s), Color(0.95, 0.88, 0.6))


func _draw_switch() -> void:
	var col: Color = _lane_color(game.switch_lane())
	draw_circle(game.net.merge, 15.0 * layout.s, Color(0.10, 0.095, 0.085))
	draw_arc(game.net.merge, 15.0 * layout.s, 0.0, TAU, 28, col, 3.0)
	draw_circle(game.net.hub, 9.0 * layout.s, col)


# NEUTRALNI VYSTUP. Nema element a nikdo ho nevlastni - kazdy poutnik,
# ktery tam dojde, stoji zivot. Krizek je zamerne jiny tvar nez vsechny
# runy, aby se nepletl s elementem, a popisek nema - deska je bez textu.
func _draw_exits() -> void:
	var r: float = game.net.exit_r
	for i in range(game.net.exit_pos.size()):
		var p: Vector2 = game.net.exit_pos[i]
		draw_circle(p, r, Color(0.13, 0.12, 0.11))
		draw_arc(p, r, 0.0, TAU, 32, Color(0.62, 0.58, 0.52), 3.0)
		var d: float = r * 0.42
		draw_line(p - Vector2(d, d), p + Vector2(d, d), Color(0.72, 0.68, 0.60), 3.0)
		draw_line(p + Vector2(d, -d), p - Vector2(d, -d), Color(0.72, 0.68, 0.60), 3.0)


func _draw_enemies() -> void:
	for item in game.enemies:
		var e: Enemy = item
		var p: Vector2 = _enemy_pos(e)
		var col: Color = Element.color_of(e.element)
		draw_circle(p, ENEMY_R_OUT * layout.s, Color(0.09, 0.085, 0.08))
		draw_circle(p, ENEMY_R_IN * layout.s, col)
		_glyph(e.element, p, ENEMY_GLYPH * layout.s, Color(0.07, 0.06, 0.06))
		if e.hp_frac() < 1.0:
			draw_arc(p, ENEMY_HP_R * layout.s, -PI * 0.5, -PI * 0.5 + TAU * e.hp_frac(), 24,
				Color(0.90, 0.85, 0.55), 3.0)


func _enemy_pos(e: Enemy) -> Vector2:
	if e.on_lane():
		return game.net.point_at(e.lane, e.s)
	return game.net.trunk_point_at(e.s)


# HORNI PANEL. Dva radky s písmem 20/13 px se vejdou do 52 px, takze je
# polovicni proti puvodnimu - kazdy pixel navic jde do herni desky.
# Popisek vybraneho useku je tu ZAMERNE: je to jedine misto, kde hrac vidi,
# jak silna dmg zona ho prave ceka.
func _draw_hud() -> void:
	draw_rect(Rect2(0.0, 0.0, layout.view.x, layout.hud_h), Color(0.075, 0.07, 0.065))
	draw_line(Vector2(0.0, layout.hud_h), Vector2(layout.view.x, layout.hud_h),
		Color(0.28, 0.25, 0.21), 2.0)
	var step: float = layout.view.x * 0.19
	var x0: float = 18.0 * layout.s
	_label(Vector2(x0, layout.hud_h * 0.48), "Vlna %d" % game.wave, 20, Color(0.90, 0.87, 0.80))
	_label(Vector2(x0, layout.hud_h * 0.88), game.phase, 13, Color(0.58, 0.55, 0.49))
	# Jmeno levelu: hrac musi videt, co hraje. "zakladni" znamena, ze jede
	# puvodni deska balancu.
	var lv_name: String = game.level.name if game.level != null else "?"
	_label(Vector2(x0, layout.hud_h * 1.62), lv_name, 12, Color(0.50, 0.47, 0.42))
	_label(Vector2(x0 + step, layout.hud_h * 0.48), "Životy %d" % game.lives, 20,
		Color(0.85, 0.42, 0.36) if game.lives <= 4 else Color(0.90, 0.87, 0.80))
	_label(Vector2(x0 + step, layout.hud_h * 0.88), "z %d" % Game.START_LIVES, 13,
		Color(0.58, 0.55, 0.49))
	_label(Vector2(x0 + step * 2.0, layout.hud_h * 0.48), "Zlato %d" % game.gold, 20,
		Color(0.88, 0.78, 0.45))
	_label(Vector2(x0 + step * 2.0, layout.hud_h * 0.88),
		"bonus %d · vylepšení %d" % [Bonus.COST, Bonus.UPGRADE_COST], 13, Color(0.58, 0.55, 0.49))
	# Vybrany usek: kolik dmg zona dava. Tohle je ta informace, kterou si
	# hrac vyhybkou kupuje, proto patri do HUDu - a je to jedine misto,
	# kde ji vidi, protoze v desce uz zadny popisek neni.
	var sel: int = game.switch_lane()
	var sel_txt: String
	if game.net.lane_is_neutral(sel):
		sel_txt = "neutrální × 1.0"
	else:
		sel_txt = "%s × %.1f" % [Element.name_of(game.net.lane_element(sel)),
			Element.STRONG * game.lane_mult(sel)]
	_label(Vector2(x0 + step * 3.0, layout.hud_h * 0.48), sel_txt, 18, Color(0.72, 0.70, 0.64))
	if game.phase == "build":
		_label(Vector2(x0 + step * 3.0, layout.hud_h * 0.88),
			"Příprava %.1f s" % game.build_timer, 13, Color(0.65, 0.78, 0.60))
	else:
		_label(Vector2(x0 + step * 3.0, layout.hud_h * 0.88),
			"v úsecích: %d" % game.enemies.size(), 13, Color(0.58, 0.55, 0.49))

	if game.phase == "lost":
		var bw: float = minf(420.0 * layout.s, layout.view.x * 0.8)
		var bh: float = 116.0 * layout.s
		var bp := Vector2((layout.view.x - bw) * 0.5, layout.view.y * 0.38)
		draw_rect(Rect2(bp, Vector2(bw, bh)), Color(0.13, 0.09, 0.09))
		draw_rect(Rect2(bp, Vector2(bw, bh)), Color(0.55, 0.25, 0.22), false, 3.0)
		_label(Vector2(bp.x + bw * 0.5, bp.y + bh * 0.45), "SÍŤ PADLA", 30,
			Color(0.88, 0.46, 0.38), true, bw)
		_label(Vector2(bp.x + bw * 0.5, bp.y + bh * 0.78), "vydržels %d vln" % game.wave, 16,
			Color(0.75, 0.71, 0.65), true, bw)
	if toast_t > 0.0:
		_label(Vector2(layout.view.x * 0.5, layout.hud_h + 24.0 * layout.s), toast, 16,
			Color(0.78, 0.75, 0.68), true, layout.view.x * 0.9)


func _draw_centered(text: String, r: Rect2, baseline_y: float, size: int, col: Color) -> void:
	draw_string(_font, Vector2(r.position.x, baseline_y), text, HORIZONTAL_ALIGNMENT_CENTER,
		r.size.x, layout.font(float(size)), col)


func _label(at: Vector2, text: String, size: int, col: Color,
		centered: bool = false, width: float = 400.0) -> void:
	var fs: int = layout.font(float(size))
	if centered:
		draw_string(_font, Vector2(at.x - width * 0.5, at.y), text,
			HORIZONTAL_ALIGNMENT_CENTER, width, fs, col)
	else:
		draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


# Znacka zivlu. Barva je hlavni nosic informace, ale NIKDY jediny -
# tvar ji vzdy doplni, aby hra fungovala i pri poruse barvociťu.
func _glyph(el: int, c: Vector2, r: float, col: Color) -> void:
	match el:
		Element.FIRE:
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.0, -r), c + Vector2(r, r), c + Vector2(-r, r)]), col)
		Element.WATER:
			draw_circle(c + Vector2(0.0, r * 0.35), r * 0.72, col)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.0, -r), c + Vector2(r * 0.6, r * 0.35),
				c + Vector2(-r * 0.6, r * 0.35)]), col)
		Element.EARTH:
			draw_rect(Rect2(c.x - r * 0.8, c.y - r * 0.8, r * 1.6, r * 1.6), col)
		Element.AIR:
			draw_arc(c, r, 0.0, TAU, 24, col, r * 0.42)
