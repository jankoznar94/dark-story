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
# VELIKOST VEZE. Je to ctverec v bunce pasu - znacka, ktera musi byt videt
# na telefonu, ale nesmi prekryt cestu vedle.
# VEZ je osmihran (viz _draw_towers). Polomer je VETSI nez u nepritele:
# vez ma byt stavba, ktera je videt, ne drobna krabicka.
const TOWER_SIDE := 16.0

# VELIKOST POUTNIKA. Je to znacka, ktera musi byt citelna na telefonu -
# poutnik je to, na co se hrac cely cas kouka, takze je vetsi nez zbytek
# znacek. Polomer je v meritku herni plochy (`s`), takze kruh zustane kruhem
# na kazdem displeji.
const ENEMY_R_OUT := 20.0
const ENEMY_R_IN := 17.0
const ENEMY_GLYPH := 11.0
const ENEMY_HP_R := 25.0
# BARVA ZNACKY CILE. KOST je jedina barva na desce, ktera neznamena zivel -
# cil se proto neda splest s cestou ani s poutnikem.
const CIL_RING := Color(0.90, 0.87, 0.80)

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
# Hraje se level, ktery si hrac prave vyrobil v editoru? Pak se do nej musi
# dat vratit - hrac si level zkousi opakovane a nechce u toho pokazde projit
# menu. V hornim panelu je kvuli tomu navrat do editoru.
var _from_editor: bool = false

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
	elif args.has("--junction-shot"):
		# Snimek editoru s POLOZENOU VYHYBKOU - jediny zpusob, jak okem
		# zkontrolovat, ze se uzly kresli spravne a ze klepnuti na bunku funguje.
		_open_editor()
		editor.tool = Editor.TOOL_VYHYBKA
		editor.tap_cell(Vector2i(5, 3))
		_push_editor_level()
		_shot = true
	elif args.has("--panels-shot"):
		# Snimek editoru S OTEVRENYM PANELEM: jediny zpusob, jak okem (a
		# merenim pixelu) zkontrolovat, ze se panel kresli nad pruhem a ze
		# se popisky vejdou do tlacitek.
		_open_editor()
		editor.level = Level.base()
		editor.level.round_time = 90.0
		editor.level.lives = 9
		editor.sel_lane = 1
		editor.panel = Editor.PANEL_LEVEL
		_push_editor_level()
		_shot = true
	elif args.has("--sel-shot"):
		# Snimek editoru s panelem "vyber" a vybranym usekem: kontrola, ze
		# tlacitka "místa −/+" a "smazat úsek" opravdu jsou v panelu.
		_open_editor()
		editor.level = Level.base()
		editor.sel_lane = 1
		editor.sel_node = -1
		editor.panel = Editor.PANEL_SEL
		_push_editor_level()
		_shot = true
	elif args.has("--box-shot"):
		# Snimek OBDELNIKOVEHO VYBERU S DUCHEM VLOZENI: jediny zpusob, jak
		# zkontrolovat, ze vyber sviti, ze je videt kopie a kam padne.
		# Obdelnik bere ohnivou vetev a usek mezi vyhybkami; kopie se
		# ZRCADLI a polozi do prazdneho leveho horniho rohu, aby byl duch
		# videt (navrzene misto vedle vyberu by padlo na original).
		_open_editor()
		editor.level = Level.base()
		editor.tool = Editor.TOOL_VYBER
		editor.begin_box(Vector2i(6, 1))
		editor.extend_box(Vector2i(21, 7))
		editor.end_box()
		editor.copy_box()
		editor.flip_clip()
		editor.arm_paste()
		editor.paste_cell = Vector2i(0, 0)
		editor.panel = Editor.PANEL_SEL
		_push_editor_level()
		_shot = true
	elif args.has("--tools-shot"):
		# Snimek panelu "nastroje": dve skupiny a tlacitka siroka podle popisku.
		_open_editor()
		editor.level = Level.base()
		editor.sel_lane = -1
		editor.sel_node = -1
		editor.panel = Editor.PANEL_TOOLS
		editor.tool = Editor.TOOL_VYHYBKA
		_push_editor_level()
		_shot = true
	elif args.has("--code-shot"):
		# Snimek KODU LEVELU: panel s kodem se jinak neda vyfotit (zavira se
		# klepnutim na desku) a je to jedina cesta, jak zkontrolovat, ze je
		# cely a citelny. Tlacitko se macka tou PRAVOU cestou (`press`).
		_open_editor()
		editor.level = Level.base()
		editor.press(Editor.BTN_EXPORT)
		_push_editor_level()
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
		# ROZVRZENI PANELU se pocita z OBSAHU, ktery dava editor: panel je
		# jinak velky podle toho, co je v nem (nastroje = jeden radek,
		# level = dva). Tady, aby se prelozilo i pri zmene velikosti okna.
		# Font se predava kvuli mereni kompaktnich tlacitek.
		layout.set_editor_font(_font)
		layout.editor_panel(editor.panel_rows())
		game.rebuild_network(layout.editor_arena, layout.s, layout.editor_bar_top())
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
	# Ukazkova obrana: veze v pasu kazde cesty, aby snimek ukazal, jak vypada
	# deska ve hre (prazdna deska nedokazuje nic).
	for cellv in game.net.strip_cells:
		var c: Vector2i = cellv
		game.try_build(c)
		if game.towers.size() >= 14:
			break
	game.round = 3
	game.gold = 240
	game.lives = 9
	game.phase = "round"
	# Kolo bezi, ale dalsi vstup je daleko - snimek ma ukazat poutniky na
	# usecich, ne nahodne nove vstupy.
	game.round_left = 60.0
	game.spawn_wait = 40.0
	game.set_switch(1)
	for el in [Element.FIRE, Element.EARTH, Element.WATER, Element.AIR, Element.FIRE]:
		game.debug_spawn(el)
	game.run_for(11.0)
	# UKAZKOVE NALEZITOSTI PRO KONTROLU VZHLEDU: vybrana vez (aby byl na
	# snimku videt i panel s vylepsenim/prodejem) a ROZJETA STRELA. Strela se
	# jinak neda vyfotit - leti 0,25 s a snimek se dela po trech snimcich.
	# V rezimu snimku se hra nehybe (viz _process), takze zustane viset.
	for item in game.towers:
		var t: Tower = item
		# Vez i strela musi byt na DESCE: kdyby cíl vysel nad horni radek,
		# kreslil by se nad HUDem a snimek by strelu vubec neukazal.
		if t.cell.y >= 2 and t.cell.y < game.net.level.rows / 2 and t.cell.x < game.net.level.cols - 3:
			game.select_tower(t.cell)
			var aim: Vector2 = game.net.cell_center(Vector2i(t.cell.x + 2, t.cell.y - 1))
			var sc: Shot = game.debug_fire(t, null, aim)
			if sc != null:
				sc.pos = sc.from.lerp(aim, 0.55)
			break
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
	_from_editor = false


# ---------------------------------------------------------------- vstup

# Jeden dotek se dorucuje DVAKRAT (Godot emuluje mys z dotyku), takze
# kazdy handler, ktery na stisk neco udela, udela to dvakrat. Guard drzi
# jen stisky, pohyb propousti.
func _input(event: InputEvent) -> void:
	# TAZENI PRSTEM V EDITORU. Jen tady se neco deje pri pohybu - ve hre
	# pohyb nic nedela (klepnuti staci) a guard odtud vyhazuje dvojita
	# doruceni jednoho doteku.
	if menu.is_editor():
		if event is InputEventScreenDrag:
			var sd: InputEventScreenDrag = event
			_editor_drag(sd.position)
			return
		if event is InputEventMouseMotion and (editor.drawing or editor.moving or editor.box_active or editor.box_move):
			var mm: InputEventMouseMotion = event
			_editor_drag(mm.position)
			return
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
		# PUSTENI PRSTU UZAVRE NAKRESLENOU CESTU. Do te doby je to jen
		# kresba - do levelu se dostane, az kdyz je hotova a v uzlech.
		if menu.is_editor() and editor.drawing:
			editor.end_draw()
			_push_editor_level()
		elif menu.is_editor() and editor.moving:
			# PUSTENI PRSTU UZAVRE I PRESUN UZLU. Kdyz se prst nehnul, je to
			# klepnuti a uzel jen zmeni druh podle zvoleneho nastroje.
			editor.end_move()
			_push_editor_level()
		elif menu.is_editor() and editor.box_move:
			# PUSTENI PRSTU UKONCI POSUN CELEHO VYBERU (a zapise ho jako jednu
			# polozku "zpet").
			editor.end_box_move()
			_push_editor_level()
		elif menu.is_editor() and editor.box_active:
			# PUSTENI PRSTU UZAVRE OBDELNIKOVY VYBER. Kdyz se prst nehnul,
			# je to klepnuti a vybere se jeden prvek pod nim.
			editor.end_box()
			_push_editor_level()


# Tahnuti prstu v editoru. Preskocene bunky doplni Editor sám, aby se cesta
# pri rychlem tahu neroztrhla. U uzlů se stejnym tahem uzel PRESOUVA - a do
# site se kazdy krok posle hned, aby hrac videl, kam uzel leze.
func _editor_drag(pos: Vector2) -> void:
	if editor.box_move:
		# POSUN CELEHO VYBERU: kazdy krok se posle do site, aby hrac videl, jak
		# vyber jede s prstem.
		if editor.extend_box_move(game.net.cell_at(pos)):
			_push_editor_level()
		return
	if editor.drawing:
		editor.extend_draw(game.net.cell_at(pos))
		return
	if editor.box_active:
		editor.extend_box(game.net.cell_at(pos))
		return
	if editor.moving and editor.extend_move(game.net.cell_at(pos)):
		_push_editor_level()


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
	# Navrat do editoru z rozehrane hry. Je to PRVNI, co se testuje: je to
	# v hornim panelu, kde zadna herni interakce neni, takze si to nemuze
	# s nicim rozumet.
	if _from_editor and layout.hud_back.has_point(pos):
		_click()
		_back_to_editor()
		return
	# Na desce uz zadane tlacitko neni - jedina interakce je klepnuti na
	# bunku PASU (stavi / vylepsi vez) a klepnuti kamkoli JINAM na usek
	# (prepne vyhybku). Zadna tlacitka vyhybky nejsou: casem jich bude vic,
	# nez se jich do pruhu vejde, a usek je to, na co se stejne kouka.
	# PANEL VYBRANE VEZE JE NAD DESKOU, takze se testuje PRVNI: jinak by
	# klepnuti na "vylepsit" propadlo na bunku pod tlacitkem a hrac by
	# postavil vez, kterou nechtel.
	var st: Tower = game.selected_tower()
	if st != null:
		if layout.tower_up.has_point(pos):
			_click()
			if st.can_upgrade():
				game.try_upgrade(st.cell)
			return
		if layout.tower_sell.has_point(pos):
			_click()
			game.try_sell(st.cell)
			return
	# PAK UZEL VYHYBKY. Kruh je to, co hrac vidi jako tlacitko. V uzlu se
	# vstupni usek potkava s vystupnimi a vsechny jsou od stredu stejne
	# daleko, takze hledani nejblizsiho useku by mohlo vybrat ten, ktery do
	# vyhybky jen vstupuje - a hrac by prepnul neco jineho, nez na co klepnul.
	var j: int = game.net.junction_tap_at(pos, maxf(16.0, 34.0 * layout.s))
	if j >= 0:
		_click()
		game.cycle_switch(j)
		return
	# PAK BUNKA PASU. Klepnuti na prazdnou bunku stavi vez s elementem te
	# cesty, klepnuti na hotovou vez ji VYBRE (vylepseni a prodej jsou pak
	# tlacitka v panelu). Mimo pas se nestavi.
	var cell: Vector2i = game.net.cell_at(pos)
	if game.net.strip_has(cell):
		_click()
		game.tap_build_cell(cell)
		return
	var lane: int = game.net.lane_tap_at(pos, maxf(12.0, 20.0 * layout.s))
	if lane >= 0:
		_click()
		game.set_switch(lane)
		return
	# KLEPNUTI MIMO DESKU zrusi vyber. Panel s tlacitky nesmi zustat viset na
	# obrazovce, kdyz hrac dela neco jineho - jinak by prekryval desku a hrac
	# by nevedel, proc.
	game.select_tower(Vector2i(-1, -1))


# MENU: ctyři tlacitka. Battle spusti kolo, Navod vysvetli pravidla,
# Settings otevre nastaveni, Update si vyzada novou verzi PWA.
func _handle_menu_tap(pos: Vector2) -> void:
	for i in range(layout.menu_buttons.size()):
		var r: Rect2 = layout.menu_rect(i)
		if not r.has_point(pos):
			continue
		_click()
		# PRES JMENO AKCE, ne pres poradi. Poradi se muze zmenit (a zmenilo
		# se - pribyl EDITOR) a klepnuti musi porad delat to, co je na
		# tlacitku napsane.
		match Menu.MENU_ACTIONS[i]:
			"battle":
				_start_battle()
			"editor":
				_open_editor()
			"guide":
				menu.open_guide()
			"settings":
				menu.open_settings()
			"update":
				menu.request_update()
		return


# NAVOD: jedine tlacitko ZPET.
func _handle_guide_tap(pos: Vector2) -> void:
	if layout.guide_back.has_point(pos):
		_click()
		menu.open_menu()


# EDITOR: klepnuti na bunku polozi prvek z palety, tazenim prstu se kresli
# cesta. Poradi je dulezite: NEJDRIV pruh a panel. Kdyby se hledala bunka
# prvni, klepnuti na panel by kreslilo cestu pod nim a tlacitko by nikdy
# nezabralo.
func _handle_editor_tap(pos: Vector2) -> void:
	# SEZNAM: kazdy radek je level k nacteni (prvni je novy, posledni navrat).
	if editor.is_list():
		var items: Array = editor.list_items()
		var rects: Array = layout.editor_list_rows(items.size())
		for i in range(rects.size()):
			var rr: Rect2 = rects[i]
			if rr.has_point(pos):
				_click()
				editor.pick(items[i])
				_push_editor_level()
				return
		return
	# PRUH: taby oteviraji panel, akce (zpet, seznam, export, hrat) se delaji hned.
	var bar: Array = editor.bar_entries()
	for i in range(mini(bar.size(), layout.ed_buttons.size())):
		var r: Rect2 = layout.ed_buttons[i]
		if not r.has_point(pos):
			continue
		_click()
		var it: Dictionary = bar[i]
		var act: int = int(it["act"])
		editor.tap_bar(i)
		_push_editor_level()
		if editor.is_play(act):
			_play_editor_level()
		return
	# PANEL: klepe se jen na tlacitka. Hodnota (act < 0) je popisek, ne
	# tlacitko - klepnuti na ni nic nedela a NESMI propadnout na desku.
	for row in layout.ed_panel_rows:
		for e in row:
			var pr: Rect2 = e["rect"]
			if not pr.has_point(pos):
				continue
			var pact: int = int(e["item"].get("act", -1))
			if pact < 0:
				return
			_click()
			editor.press(pact)
			_push_editor_level()
			return
	# KOD NA DESCE SE ZAVRE KLEPNUTIM KAMKOLI. Je to PRED klepnuti na desku:
	# hrac cte kod a prvni klepnuti ma jen zavrit okno, ne neco udelat.
	if editor.code_show:
		_click()
		editor.close_code()
		return
	# VLOZENI PRIPRAVENE KOPIE: klepnuti na desku rekne, KAM. Je to PRED
	# pravidlem o zavreni panelu - hrac musi mit tlacitka panelu na ocich,
	# dokud vlozeni nepotvrdi (a muze ho vzit zpet).
	if editor.paste_armed:
		var pc: Vector2i = _editor_cell(pos)
		if editor.level.in_bounds(pc.x, pc.y):
			_click()
			editor.paste_at(pc)
			_push_editor_level()
			return
	# KLEPNUTI NA DESKU S OTEVRENYM PANELEM PANEL JEN ZAVRE. Jinak by hrac
	# polozil prvek pod panelem, tedy nekam, co nevidi.
	if editor.panel != Editor.PANEL_NONE:
		_click()
		editor.close_panel()
		_push_editor_level()
		return
	var cell: Vector2i = _editor_cell(pos)
	if not editor.level.in_bounds(cell.x, cell.y):
		return
	_click()
	# PRST NA CESTE = TVAROVANI CESTY, a to u vsech nastroju krome gumy. Je to
	# PRED ostatnimi gesty: "cesta" by tam kreslila novou cestu (a ta nikdy
	# neplati - nova cesta musi zacit v uzlu) a "výběr" by pres ni obtahl
	# obdelnik. Presne to Janovi branilo cestu upravit: "Tah prstem teď dělá
	# rectangle select. Chtěl bych vybrat jednu cestu a upravit ji."
	if editor.begin_lane_drag(cell):
		return
	# PRST UVNITR HOTOVEHO OBDELNIKU BERE CELY VYBER a tahem ho posune
	# libovolnym smerem. Je to PRED presunem jednoho prvku: obdelnik ma uvnitr
	# i prvky a klepnuti na ne by jinak vzalo jen ten prvek, ne cely vyber.
	# Jen u "vyberu" - u ostatnich nastroju (hlavne u gumy) ma klepnuti do
	# obdelniku porad svuj vyznam.
	if editor.tool == Editor.TOOL_VYBER and editor.begin_box_move(cell):
		return
	# NASTROJ CESTA KRESLI TAZENIM, ostatni se kladou klepnutim. Drzet u
	# kazdeho prvku zvlast "tahni" a "klepni" by hrace jen mátlo.
	if editor.tool == Editor.TOOL_ROAD:
		editor.draw_elem = editor.elem
		editor.begin_draw(cell)
		_push_editor_level()
	elif editor.begin_move(cell):
		# UZEL SE PRESOUVA TAZENIM. Klepnuti (tah bez pohybu) se vyhodnoti
		# az pri pusteni prstu - do te doby se jeste nevi, co to bude.
		pass
	elif editor.tool == Editor.TOOL_VYBER:
		# PRST MIMO OBDELNIK OBTÁHNE NOVY OBDELNIK (a klepnuti bez pohybu
		# vybere jeden prvek pod prstem, takze se da i velky vyber zrusit).
		editor.begin_box(cell)
	else:
		editor.tap_cell(cell)
		_push_editor_level()


# BUNKA POD PRSTEM. Jedno misto, kde se pozice doteku meni na bunku mrizky -
# klepnuti na panel, na desku i vlozeni kopie se musi ptat stejne.
func _editor_cell(pos: Vector2) -> Vector2i:
	return game.net.cell_at(pos)


# Editor si drzi vlastni level a hra dostane jeho kopii. Kdyby dostala level
# sam, sahala by do nej za behu (bonusy se vazi na usek) a hrac by si rozbil
# to, co prave upravuje.
func _push_editor_level() -> void:
	game.set_level(editor.level.clone(), layout.editor_arena, layout.s,
		layout.editor_arena.end.y + 20.0 * layout.s)
	_reflow_editor()


# HRAT Z EDITORU. Hrac si level vyrobi a hned si ho zahraje - bez toho by
# musel level ulozit, vratit se do menu a doufat, ze se hra postavi z toho
# spravneho. Do hry jde KOPIE: editor si svuj level necha. A do hry jde
# PRIZNAK, ze se hraje z editoru - hrac se musi moci vratit zpet.
func _play_editor_level() -> void:
	game.setup(layout.arena, layout.s, layout.board_bottom, editor.level.clone())
	menu.open_battle()
	_from_editor = true


# ZPET DO EDITORU z rozehraneho levelu. Editor si svuj level nechal, takze se
# vrati presne tam, kde byl - a hra se z nej postavi znovu.
func _back_to_editor() -> void:
	menu.open_editor()
	_push_editor_level()


# OTEVRE EDITOR TAM, KDE Hrac SKONCIL. Kdyby se pokazde zacinalo od nuly,
# prisel by hrac o vsechno, co ma ulozene - a ulozene levely by nemely jak
# se dostat zpet.
func _open_editor() -> void:
	menu.open_editor()
	editor.open_last()
	_push_editor_level()


func _draw_editor() -> void:
	if editor.is_list():
		_draw_editor_list()
		return
	_draw_background()
	_draw_grid()
	_draw_lanes()
	_draw_nodes()
	_draw_editor_draft()
	# OBDELNIKOVY VYBER A DUCH VLOZENI: kresli se nad deskou, aby hrac videl
	# jak vyber, tak misto, kam kopie padne.
	_draw_editor_box()
	# PORADI JE DULEZITE: panel se kresli AZ PO desce (prekryva jeji spodni
	# kus), ale PRED hornim pruhem, ktery je vždy videt cely.
	_draw_editor_panel()
	_draw_editor_bar()
	_draw_editor_top()
	# KOD LEVELU JE NAD VSIM: hrac ho cte a prekryva vsechno ostatni.
	_draw_editor_code()


# KÓD LEVELU. Klepnuti na "export" kod zkopiruje do schranky - ale ten zapis
# umi prohlizec i system odmitnout a na telefonu se vypsany radek neda
# oznacit. Proto se kod vykresli I SEM: cely, zalomeny na radky a tak velkym
# pismem, aby se dal precist (a vyfotit). Klepnuti kamkoli okno zavre.
#
# VELIKOST SE HLEDA SHORA DOLU: dokud se cely kod nevejde do desky, pismo se
# zmensuje. Meri se i kresli stejnym pismem (`layout.font`) - jinak by se
# zalomeni rozejislo s tim, co je videt.
func _draw_editor_code() -> void:
	var code: String = editor.code
	if not editor.code_show or code.is_empty():
		return
	var bw: float = layout.view.x * 0.94
	var bx: float = (layout.view.x - bw) * 0.5
	var inner: float = bw - 24.0 * layout.ui
	# PANEL ZUSTAVA NAD SPODNI LISTOU. Kdyby pres ni pretekl, hrac by nemel
	# jak zmacknout znovu export (a klepnuti do listy by zaviralo kod).
	var top: float = layout.editor_arena.position.y
	var max_h: float = maxf(layout.editor_bar_top() - top - 52.0 * layout.ui, 40.0)
	var px: int = 20
	var lines: Array = []
	var lh: float = 0.0
	while px >= 8:
		var dpx: int = layout.font(float(px))
		lh = float(dpx) * 1.30
		lines = Editor.code_lines(_font, dpx, inner, code)
		if float(lines.size()) * lh <= max_h:
			break
		px -= 1
	var bh: float = float(lines.size()) * lh + 52.0 * layout.ui
	var by: float = top + maxf((max_h - float(lines.size()) * lh) * 0.5, 0.0)
	var box := Rect2(bx, by, bw, bh)
	draw_rect(box, Color(0.10, 0.095, 0.085, 0.97))
	draw_rect(box, Color(0.78, 0.62, 0.30), false, layout.ul(2.0))
	_draw_centered("KÓD LEVELU — klepni kamkoli a zavřeš",
		Rect2(box.position, Vector2(bw, 34.0 * layout.ui)), box.position.y + 22.0 * layout.ui,
		15, Color(0.90, 0.87, 0.80))
	var y: float = box.position.y + 44.0 * layout.ui
	for l in lines:
		_label(Vector2(box.position.x + 12.0 * layout.ui, y + float(layout.font(float(px))) * 0.86),
			str(l), px, Color(0.84, 0.82, 0.76))
		y += lh


# SEZNAM ULOZENYCH LEVELU. Kazdy novy level dostane vlastni jmeno, takze se
# predchozi prace nikdy neprepise - a tady se k ni hrac dostane zpatky.
func _draw_editor_list() -> void:
	draw_rect(Rect2(Vector2.ZERO, layout.view), Color(0.10, 0.095, 0.085))
	_label(Vector2(_pad_left(), layout.hud_h * 0.78), "LEVELY", 22, Color(0.90, 0.87, 0.80))
	var items: Array = editor.list_items()
	var rects: Array = layout.editor_list_rows(items.size())
	for i in range(items.size()):
		var r: Rect2 = rects[i]
		var it: Dictionary = items[i]
		var kind: String = str(it["kind"])
		var accent: Color = Color(0.42, 0.40, 0.35)
		if kind == "new":
			accent = Color(0.65, 0.78, 0.60)
		elif kind == "level":
			accent = Color(0.78, 0.62, 0.30) if str(it["key"]) == editor.local_name \
				else Color(0.55, 0.53, 0.48)
		elif kind == "back":
			accent = Color(0.72, 0.70, 0.62)
		draw_rect(r, Color(0.135, 0.125, 0.11))
		draw_rect(r, Color(accent.r, accent.g, accent.b, 0.55), false, layout.ul(2.0))
		_label(Vector2(r.position.x + 14.0 * layout.ui, r.position.y + r.size.y * 0.64),
			str(it["name"]), 17, Color(0.88, 0.85, 0.78))


# CO Hrac PRAVE KRESLI. Do levelu se to dostane, az kdyz prst zvedne - do
# te doby je to jen kresba. Hrac tak vidi, co mu vznikne, a muze tazenim
# pokracovat, i kdyz cestu omylem prejel.
func _draw_editor_draft() -> void:
	var cw: float = game.net.cell_w
	var ch: float = game.net.cell_h
	for cell in editor.draw_cells:
		var v: Vector2i = cell
		var col: Color = Level.value_color(editor.draw_elem)
		var p: Vector2 = game.net.origin + Vector2((float(v.x) + 0.5) * cw, (float(v.y) + 0.5) * ch)
		draw_rect(Rect2(p - Vector2(cw, ch) * 0.5, Vector2(cw, ch)),
			Color(col.r, col.g, col.b, 0.38))
	# BUNKA, KAM Hrac NAPOSLEDY KLEPL. Bez ni by si u posledniho položeného
	# prvku nikdy nebyl jisty, kam to padlo.
	if editor.level.in_bounds(editor.mark.x, editor.mark.y):
		var mp: Vector2 = game.net.origin + Vector2(
			(float(editor.mark.x) + 0.5) * cw, (float(editor.mark.y) + 0.5) * ch)
		draw_rect(Rect2(mp - Vector2(cw, ch) * 0.5, Vector2(cw, ch)),
			Color(0.90, 0.87, 0.80), false, layout.bl(2.0))


# BUNKA JAKO OBDELNIK NA OBRAZOVCE. Jedno misto, kde se z bunky mrizky stane
# obdelnik - obdelnikovy vyber, duch vlozeni i rám okolo kopie se musi pocitat
# stejne, jinak by ramecek ukazoval jinde, nez co se opravdu vlozi.
func _cell_rect(box: Rect2i) -> Rect2:
	var cw: float = game.net.cell_w
	var ch: float = game.net.cell_h
	return Rect2(game.net.origin + Vector2(float(box.position.x) * cw, float(box.position.y) * ch),
		Vector2(float(box.size.x) * cw, float(box.size.y) * ch))


# OBDELNIKOVY VYBER A DUCH VLOZENI. Hrac musi videt dve veci:
#   * CO MA VYBRANE (obtazeny obdelnik sviti),
#   * KAM SE KOPIE POLOZI (duch na miste vlozeni, jeste nez klepne).
# Duch kresli PRESNE ty bunky, ktere pak vlozi `paste_at` - obe strany jdou
# pres `Editor.clip_map`, takze se nemuzou rozejit.
func _draw_editor_box() -> void:
	if not editor.has_box():
		return
	var r: Rect2 = _cell_rect(editor.sel_box)
	draw_rect(r, Color(0.62, 0.74, 0.86, 0.10))
	draw_rect(r, Color(0.62, 0.74, 0.86, 0.80), false, layout.bl(2.0))
	if editor.paste_armed and not editor.clip.is_empty():
		_draw_paste_ghost()


func _draw_paste_ghost() -> void:
	var at: Vector2i = editor.paste_cell
	var cw: float = game.net.cell_w
	var ch: float = game.net.cell_h
	for ln in editor.clip["lanes"]:
		var col: Color = Level.value_color(int(ln["elem"]))
		for q in ln["cells"]:
			var v: Vector2i = q
			var p: Vector2i = at + editor.clip_map(v.x, v.y)
			draw_rect(_cell_rect(Rect2i(p, Vector2i(1, 1))), Color(col.r, col.g, col.b, 0.45))
	var rr: float = game.net.switch_r * 0.30
	for n in editor.clip["nodes"]:
		# PRVEK KOPIE je slovnik ({"c","r","kind"}) - ne bunka.
		var p: Vector2i = at + editor.clip_map(int(n["c"]), int(n["r"]))
		var c: Vector2 = game.net.origin + Vector2(
			(float(p.x) + 0.5) * cw, (float(p.y) + 0.5) * ch)
		var kind: int = int(n["kind"])
		draw_circle(c, rr, Color(0.10, 0.095, 0.085, 0.8))
		draw_arc(c, rr, 0.0, TAU, 20, Color(0.90, 0.87, 0.80, 0.9), layout.bl(2.0))
		if kind == Level.START:
			draw_circle(c, rr * 0.5, Color(0.62, 0.58, 0.50))
		elif kind == Level.CIL:
			var d: float = rr * 0.55
			draw_line(c - Vector2(d, d), c + Vector2(d, d), Color(0.90, 0.87, 0.80), layout.bl(2.0))
			draw_line(c + Vector2(d, -d), c - Vector2(d, -d), Color(0.90, 0.87, 0.80), layout.bl(2.0))
	# RÁM CELÉ KOPIE: hrac vidi, jak velky kus se polozi (i kdyz je v nem
	# treba jen jeden usek).
	draw_rect(_cell_rect(Rect2i(at, editor.clip_size())), Color(0.90, 0.87, 0.80, 0.55), false, layout.bl(2.0))


func _draw_editor_top() -> void:
	# HORNI PRUH EDITORU. Driv tu nebylo nic a vsechno se veslo nad tlacitka -
	# jenze panel se rozbaluje prave tam, takze text by pod nim zmizel. Tady
	# je vždy videt cely (je to mimo desku, stejne jako panel hry).
	var pad: float = 14.0 * layout.ui
	draw_rect(Rect2(0.0, 0.0, layout.view.x, layout.hud_h), Color(0.075, 0.07, 0.065))
	draw_line(Vector2(0.0, layout.hud_h), Vector2(layout.view.x, layout.hud_h),
		Color(0.28, 0.25, 0.21), layout.ul(2.0))
	var half: float = layout.view.x * 0.5 - pad
	var lv_name: String = editor.level.name if editor.level != null else "?"
	if lv_name.is_empty():
		lv_name = "level"
	_label(Vector2(pad, layout.hud_h * 0.48), lv_name, 20, Color(0.90, 0.87, 0.80))
	_label(Vector2(pad, layout.hud_h * 0.88),
		layout.fit_text(editor.sel_text(), _font, layout.font(13.0), half), 13,
		Color(0.58, 0.55, 0.49))
	# HLASKA ZPRAVA: rika, co se prave stalo a proc neco nejde. Kresli se
	# z praveho okraje, aby se s vyberem vlevo nepretlacovala.
	_label_right(layout.fit_text(editor.status, _font, layout.font(14.0), half),
		layout.hud_h * 0.48, 14, Color(0.72, 0.70, 0.62), layout.view.x - pad)
	# KOD LEVELU (kdyz je vyexportovany) je druha sance vedle schranky.
	if not editor.code.is_empty():
		_label_right(layout.fit_text(editor.code, _font, layout.font(11.0), half),
			layout.hud_h * 0.88, 11, Color(0.80, 0.84, 0.70), layout.view.x - pad)


# PANEL OTEVENE KATEGORIE. Kresli se NAD pruhem a PREKRYVA spodni kus desky:
# kdyby deska ujizdela, mrizka by pri kazdem otevreni menu uskocila a hrac by
# ztratil misto, kde prave kreslil. Klepnuti na desku panel zavre.
#
# PANEL MA SVETLEJSI PODBARVENI NEZ PRUH (Jan: "Podmenu vždy uděláme s nějakým
# lehkým podbarvením, ať řádky nesplývají s hlavním panelem"): pruh je tmavy
# (0.075), panel je o stupen svetlejsi a teplejsi, takze je na prvni pohled
# videt, co je otevrene menu a co je spodni lista.
const PANEL_BG := Color(0.175, 0.165, 0.148)
const PANEL_BTN := Color(0.235, 0.222, 0.198)


func _draw_editor_panel() -> void:
	var rows: Array = layout.ed_panel_rows
	if rows.is_empty():
		return
	var top: float = layout.ed_panel_top
	var bot: float = layout.editor_bar_top()
	draw_rect(Rect2(0.0, top, layout.view.x, bot - top), PANEL_BG)
	draw_line(Vector2(0.0, top), Vector2(layout.view.x, top), Color(0.46, 0.42, 0.35), layout.ul(2.0))
	for row in rows:
		var line: Array = row
		var lpx: int = layout.panel_label_px(line, _font)
		for e in line:
			var r: Rect2 = e["rect"]
			var it: Dictionary = e["item"]
			var kind: String = str(it.get("kind", "action"))
			# PRAZDNE MISTO V MRIZCE se jen preskoci - je tam kvuli tomu, aby
			# bunky v obou radcich sedely na stejnem x.
			if kind == "spacer":
				continue
			if kind == "value":
				# HODNOTA NENI TLACITKO. Kresli se jako text: ramecek by
				# slibil klepnuti, ktere nic nedela. Je-li oznacena jako
				# `align: right`, tiskne se k PRAVEMU okraji sve bunky -
				# tlacitka "−"/"+" stoji hned za ni, takze je hrac vidi
				# "nalepena na hodnotu" (Jan). `align: left` je sloupec
				# popisku v tabulce levelu: vsechny popisky zacinaji na
				# stejnem x, aby hodnoty vedle nich staly pod sebou.
				var al: String = str(it.get("align", "center"))
				var base_y: float = r.position.y + r.size.y * 0.62
				if al == "right":
					_draw_right(str(it["label"]), r, base_y, lpx, Color(0.96, 0.93, 0.84))
				elif al == "left":
					_label(Vector2(r.position.x + 6.0 * layout.ui, base_y),
						str(it["label"]), lpx, Color(0.80, 0.77, 0.70))
				else:
					_draw_centered(str(it["label"]), r, base_y, lpx, Color(0.96, 0.93, 0.84))
				continue
			draw_rect(r, PANEL_BTN)
			var accent: Color = _panel_accent(it)
			draw_rect(r, Color(accent.r, accent.g, accent.b, 0.7), false, layout.ul(2.0))
			_draw_centered(str(it["label"]), r, r.position.y + r.size.y * 0.64, lpx,
				Color(0.90, 0.87, 0.80))


# CIM SE TLACITKO V PANELU VYZNACUJE. Barva je tu jen na to, co si ji
# zaslouzi: zivel (barva je jeho identita), mazani (cervena) a prave
# zvoleny nastroj (svetlejsi, ne barevny - barva patri zivlum).
func _panel_accent(it: Dictionary) -> Color:
	var kind: String = str(it.get("kind", "action"))
	if kind == "elem":
		return Level.value_color(editor.elem)
	if kind == "danger":
		return Color(0.66, 0.34, 0.30)
	if kind == "tool" and bool(it.get("on", false)):
		return Color(0.85, 0.82, 0.76)
	return Color(0.44, 0.41, 0.36)


func _draw_editor_bar() -> void:
	var entries: Array = editor.bar_entries()
	var btns: Array = layout.ed_buttons
	if entries.is_empty() or btns.is_empty():
		return
	var labels: Array = []
	for e in entries:
		labels.append(str(e["label"]))
	var label_px: int = layout.ed_label_px(labels, _font)
	var top: float = layout.editor_bar_top()
	draw_rect(Rect2(0.0, top, layout.view.x, layout.view.y - top), Color(0.075, 0.07, 0.065))
	draw_line(Vector2(0.0, top), Vector2(layout.view.x, top), Color(0.28, 0.25, 0.21), layout.ul(2.0))
	for i in range(mini(entries.size(), btns.size())):
		var r: Rect2 = btns[i]
		var e: Dictionary = entries[i]
		draw_rect(r, Color(0.135, 0.125, 0.11))
		var accent: Color = Color(0.44, 0.41, 0.36)
		var tab: int = int(e["tab"])
		var act: int = int(e["act"])
		if tab >= 0:
			# TAB: kdyz je jeho panel otevreny, sviti - hrac vi, kde stoji.
			accent = Color(0.85, 0.82, 0.76) if editor.panel == tab else Color(0.52, 0.49, 0.43)
		elif act == Editor.BTN_EXPORT:
			accent = Color(0.65, 0.78, 0.60)
		elif act == Editor.BTN_PLAY:
			accent = Color(0.78, 0.62, 0.30)
		draw_rect(r, Color(accent.r, accent.g, accent.b, 0.55), false, layout.ul(2.0))
		# Pismo popisku se bere z rozvrzeni (stejne cislo, kterym ho meri test):
		# na uzkem displeji se o stupen zmensi, aby se popisek do tlacitka vesel.
		_draw_centered(str(e["label"]), r, r.position.y + r.size.y * 0.64, label_px,
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
#
# PORADI KRESLENI JE DANE: pas jde POD cesty (je to podbarveni, ne druha
# cesta), veze nad cestami a poutnici nad vezemi.
func _draw_battle() -> void:
	_draw_background()
	_draw_strip()
	_draw_lanes()
	_draw_nodes()
	# PAPRSEK JE POD VEZEMI (i pod poutniky). Kresli se od STREDU veze, takze
	# nad vezi by z nej byla cara pres celou vez - a presne to z nej delalo
	# "sopel": tlusty tah s kouli na spicce, ktery jako by z veze vytekal.
	# Pod vezi paprsek vychazi zpoza ni a spicka se schova v poutnikovi,
	# do ktereho se opira - coz je presne to, co ma hrac videt.
	_draw_shots()
	_draw_towers()
	_draw_enemies()
	# VYBRANA VEZ: oznaceni na desce a panel s vylepsenim/prodejem. Kresli se
	# jako POSLEDNI nad deskou, aby tlacitka nikdy neprekryla nic, co hrac
	# potrebuje videt (panel si sam hlida, na ktere strane lezi).
	var st: Tower = game.selected_tower()
	if st != null:
		var sc: Vector2 = game.net.cell_center(st.cell)
		layout.tower_panel(sc)
		_draw_tower_sel(sc)
	_draw_hud()
	if st != null:
		_draw_tower_panel(st)


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
		draw_rect(r, Color(accent.r, accent.g, accent.b, 0.55), false, layout.ul(2.0))
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

	# MERITKO NAVODU. `_label` kresli pismo jako `size * ui`, takze se vsechno
	# MERI ve stejnem meritku, v jakem se kresli: `fit_px` dostane plochu
	# vydelenou `ui` (hleda tedy velikost pro zakladni displej) a `dpx` je
	# velikost, kterou hra opravdu vykresli. Driv se merilo v zakladnich
	# pixelech a kreslilo ve skalovanych, takze na displeji s dvojnasobnou
	# hustotou text pretekal z bloku (a na telefonu se zase zbytecne zmensoval).
	var base: int = Guide.fit_px(_font, avail_w / layout.ui, avail_h / layout.ui, wide)
	var fs: int = maxi(base, Guide.MIN_PX)
	var dpx: int = layout.font(float(fs))
	var count: int = Guide.BLOCKS.size()
	var cols: int = 2 if wide else 1
	var rows: int = int(ceil(float(count) / float(cols)))
	var cell_w: float = avail_w / float(cols)
	var cell_h: float = (avail_h - float(dpx) * 1.9) / float(rows)

	_label(Vector2(left, top + float(fs) * 1.1), Guide.TITLE, fs + 7,
		Color(0.90, 0.87, 0.80), false, avail_w)

	for i in range(count):
		var b: Dictionary = Guide.BLOCKS[i]
		var col: int = i % cols
		var row: int = i / cols
		var origin := Vector2(left + cell_w * float(col), top + float(dpx) * 1.9 + cell_h * float(row))
		_draw_guide_block(b, origin, cell_w, cell_h, fs, dpx)

	var br: Rect2 = layout.guide_back
	draw_rect(br, Color(0.20, 0.19, 0.17))
	draw_rect(br, Color(0.38, 0.35, 0.30), false, layout.ul(2.0))
	_draw_centered(Guide.BACK, br, br.position.y + br.size.y * 0.64, 18, Color(0.85, 0.82, 0.76))


func _draw_guide_block(b: Dictionary, origin: Vector2, cell_w: float, cell_h: float,
		fs: int, dpx: int) -> void:
	var pad: float = float(fs) * 0.8 * layout.ui
	var art_w: float = Guide.art_width(cell_w, cell_h, true)
	var art_h: float = maxf(float(dpx) * 3.0, cell_h - pad * 2.0)
	var art := Rect2(origin.x + pad, origin.y + pad, art_w, art_h)
	draw_rect(art, Color(0.125, 0.115, 0.10))
	draw_rect(art, Color(0.24, 0.22, 0.19), false, layout.ul(1.0))

	var txt_x: float = art.end.x + float(fs) * 1.1 * layout.ui
	var txt_w: float = origin.x + cell_w - pad - txt_x
	_label(Vector2(txt_x, origin.y + pad + float(fs) * 0.95 * layout.ui), str(b["title"]),
		fs + 4, Color(0.86, 0.83, 0.75), false, txt_w)
	# SIRKA TEXTU SE MERI TEMIS PISMEM, KTERE SE KRESLI (`dpx`), ne zakladnim.
	var lines: Array = Guide.caption(_font, dpx, txt_w, str(b["text"]))
	var ly: float = origin.y + pad + float(fs) * 0.95 * layout.ui + float(dpx) * 1.5
	for line in lines:
		_label(Vector2(txt_x, ly), str(line), fs, Color(0.70, 0.67, 0.60), false, txt_w)
		ly += float(dpx) * 1.35

	# Obrazek kresli hra sama - stejnymi znackami, jake ma na desce.
	match str(b["art"]):
		"_guide_switch":
			_guide_switch(art, fs)
		"_guide_damage":
			_guide_damage(art, fs)
		"_guide_tower":
			_guide_tower(art, fs)
		"_guide_strip":
			_guide_strip(art, fs)
		"_guide_exit":
			_guide_exit(art, fs)


# OBRAZEK 1: vyhybka. Krouzek s Y - presne ta znacka, kterou hrac najde na
# desce. Vybrana vetev je svetlejsi, ostatni jsou utlumene.
func _guide_switch(r: Rect2, fs: int) -> void:
	var c := Vector2(r.position.x + r.size.x * 0.34, r.get_center().y)
	var rr: float = minf(r.size.x * 0.17, r.size.y * 0.30)
	var x1: float = r.position.x + r.size.x * 0.88
	var spread: float = r.size.y * 0.30
	var sel: int = 1
	var cols := [Element.color_of(Element.FIRE), Element.color_of(Element.WATER),
		Element.color_of(Element.EARTH)]
	var tips := [Vector2(x1, c.y - spread), Vector2(x1, c.y), Vector2(x1, c.y + spread)]
	for i in range(tips.size()):
		var col: Color = cols[i]
		var a: float = 0.95 if i == sel else 0.30
		draw_line(c, tips[i], Color(col.r, col.g, col.b, a),
			float(fs) * (0.26 if i == sel else 0.16))
	# Krouzek s Y - znacka uzlu, na ktery se klepe.
	draw_circle(c, rr, Color(0.10, 0.095, 0.085))
	draw_arc(c, rr, 0.0, TAU, 24, Element.color_of(Element.WATER), 2.0)
	_draw_y(c, rr * 0.5, Element.color_of(Element.WATER), false)
	# Kolecko mysi/prstu nad vybranym usekem - znacka "klepni sem".
	var px: float = c.x + (x1 - c.x) * 0.5
	draw_arc(Vector2(px, tips[sel].y), float(fs) * 0.30, 0.0, TAU, 18,
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


# OBRAZEK 3: vez. Pas kolem cesty (svetlejsi odstin) a v nem vez - hrac vidi,
# co ma hledat. Krouzek nad vezi je "klepni sem".
func _guide_tower(r: Rect2, fs: int) -> void:
	var y: float = r.get_center().y
	var col: Color = Element.color_of(Element.WATER)
	var band: Color = Level.strip_color(Element.WATER)
	var x0: float = r.position.x + r.size.x * 0.06
	var x1: float = r.position.x + r.size.x * 0.94
	var half: float = float(fs) * 0.80
	# Pas na obou stranach cesty...
	draw_rect(Rect2(x0, y - half * 2.0, x1 - x0, half), band)
	draw_rect(Rect2(x0, y + half, x1 - x0, half), band)
	# ...a cesta mezi nimi.
	draw_line(Vector2(x0, y), Vector2(x1, y), Color(col.r, col.g, col.b, 0.80),
		maxf(2.0, float(fs) * 0.28))
	# Vez stoji v pasu. Ctverec s runou - presne ta znacka, kterou hrac
	# najde na desce.
	var side: float = minf(r.size.x * 0.09, float(fs) * 0.95)
	var tp := Vector2(r.position.x + r.size.x * 0.68, y - half * 1.5)
	draw_rect(Rect2(tp.x - side - 1.5, tp.y - side - 1.5, side * 2.0 + 3.0, side * 2.0 + 3.0),
		Color(0.09, 0.085, 0.08))
	draw_rect(Rect2(tp.x - side, tp.y - side, side * 2.0, side * 2.0), col)
	_glyph(Element.WATER, tp, side * 0.55, Color(0.07, 0.06, 0.06))
	draw_arc(tp, side * 1.9, 0.0, TAU, 20, Color(0.90, 0.87, 0.80), 2.0)


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


# OBRAZEK 5: pas. Dve cesty - sediva (kmen/neutralni usek) a ohniva - a u
# kazde svetlejsi pas. Sedy pas bere vsem 100 %, barevny patri svemu zivlu.
func _guide_strip(r: Rect2, fs: int) -> void:
	var x0: float = r.position.x + r.size.x * 0.06
	var x1: float = r.position.x + r.size.x * 0.94
	var half: float = float(fs) * 0.80
	var lw: float = maxf(2.0, float(fs) * 0.26)
	for i in range(2):
		var y: float = r.position.y + r.size.y * (0.30 if i == 0 else 0.74)
		var val: int = Level.KMEN if i == 0 else Element.FIRE
		var col: Color = Level.value_color(val)
		var band: Color = Level.strip_color(val)
		draw_rect(Rect2(x0, y - half * 2.0, x1 - x0, half), band)
		draw_rect(Rect2(x0, y + half, x1 - x0, half), band)
		draw_line(Vector2(x0, y), Vector2(x1, y), Color(col.r, col.g, col.b, 0.80), lw)
	# Runa jen u barevne cesty: sedivy pas nema element, bere vsem stejne.
	draw_arc(Vector2((x0 + x1) * 0.5, r.position.y + r.size.y * 0.74),
		float(fs) * 0.60, 0.0, TAU, 22,
		Color(Element.COLORS[Element.FIRE].r, Element.COLORS[Element.FIRE].g,
			Element.COLORS[Element.FIRE].b, 0.45), 2.0)
	_glyph(Element.FIRE, Vector2((x0 + x1) * 0.5, r.position.y + r.size.y * 0.74),
		float(fs) * 0.32, Element.color_of(Element.FIRE))


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
		# Stav prepinace k pravemu okraji radku - zarovnany DOPRAVA, aby
		# nepretekl mimo obrazovku (viz _label_right).
		_label_right("ZAPNUTO" if on else "VYPNUTO",
			row.position.y + row.size.y * 0.62, 15, col, row.end.x - 18.0 * layout.ui)
		# Zaskrtavatko je druha znacka krome barvy - ne jen barva.
		var bx: float = row.end.x - 108.0 * layout.ui
		var by: float = row.get_center().y
		draw_rect(Rect2(bx - 1.0, by - 11.0, 22.0, 22.0), Color(0.09, 0.085, 0.08))
		draw_rect(Rect2(bx - 1.0, by - 11.0, 22.0, 22.0), col, false, layout.ul(2.0))
		if on:
			draw_line(Vector2(bx + 3.0, by), Vector2(bx + 8.0, by + 6.0), col, 3.0)
			draw_line(Vector2(bx + 8.0, by + 6.0), Vector2(bx + 18.0, by - 7.0), col, 3.0)

	var br: Rect2 = layout.settings_back
	draw_rect(br, Color(0.20, 0.19, 0.17))
	draw_rect(br, Color(0.38, 0.35, 0.30), false, layout.ul(2.0))
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


# Barva pruhu. Jedno misto, kde se hodnota useku meni na barvu, je
# `Level.value_color` - hra i editor se musi ptat jeho. Dřív tu stály vlastni
# vetve a jedna z nich sahala na `Element.color_of(lane_element(lane))`, coz
# u kmene (-2) vraci barvu Země, a druha volala `net.lane_is_kmen`, ktera
# neexistovala - kazdy pruh krome neutralniho se pak kreslil CERNY.
func _lane_color(lane: int) -> Color:
	return Level.value_color(game.net.lane_element(lane))


# JE TENHLE USEK PRAVE ZVYRAZNENY? V HRE je to usek, ktery posila vyhybka -
# hrac tak vidi, kam poutniky posle. V EDITORU je to usek, ktery si hrac
# VYBRAL klepnutim (nebo obdelnikem); tlacitka "zivel" a "mista" pak meni JEHO
# vlastnosti. Jedno misto pro obe obrazovky: kdyby si to kazda pocitala sama,
# kreslil by editor neco jineho, nez na co klepnuti opravdu sedi.
func _lane_highlighted(lane: int) -> bool:
	if menu.is_editor():
		if editor.has_box() and editor.box_lanes().has(lane):
			return true
		return editor.sel_lane == lane
	return game.lane_selected(lane)


func _draw_lanes() -> void:
	# CESTA JE JEDEN KUS (Jan, Oct 2026): "Je to silný pruh ve středu a kolem
	# něj jsou jak kdyby ještě dvě světlejší vrstvy. Chtěl bych, aby ta cesta
	# byl zkrátka jednolitý kus."
	#
	# Cesta se driv kreslila TRIKRAT pres sebe: siroky prusvitny podklad,
	# stredni pruh a jasne jadro. Kazda hranice vrstvy mela jeste svuj
	# antialiasing lem, takze cesta nebyla jeden pruh, ale tri pruhy s mekkymi
	# okraji - a mekky lem je porad stejne tlusty v pixelech, kdezto cesta s
	# rozlisenim roste. Presne proto vypadala na velkem displeji "low rez",
	# i kdyz se sirka pocitala z meritka.
	#
	# Ted je to JEDEN tah jednou barvou a neprusvitny - zadny jasnejsi stred,
	# zadny podklad. Sirka je nasobek `layout.s`, takze plati na vsech
	# rozliseni; cesta je porad sirsi nez jedna bunka pasu, proto je videt,
	# kde jsou veze a kam se klepe.
	var lw: float = maxf(6.0, 20.0 * layout.s)
	for lane in range(game.net.lane_count()):
		var col: Color = _lane_color(lane)
		var path: PackedVector2Array = game.net.lane_path[lane]
		# VYBRANY USEK DOSTANE OBRYS KOLEM SEBE, ne dalsi vrstvu v tele: plocha
		# zustava jednolita barva sveho zivlu, takze hrac porad vi, ktery usek
		# to je (kdyby se menil jas plochy, menila by se i barva a hrac by
		# musel hadat, ktery element to je). Kazda vyhybka ma svuj vybrany
		# usek, takze se obrysu kresli tolik, kolik je vyhybek.
		if _lane_highlighted(lane):
			_lane_stroke(lane, path, Color(0.95, 0.88, 0.60, 0.95),
				lw + maxf(4.0, 6.0 * layout.s))
		_lane_stroke(lane, path, col, lw)


# JEDEN TAH CESTY: cela cesta jednim tahem (polyline) + KROUZEK v bodech,
# kde se smer lame. Krouzek ma polomer presne poloviny sirky tahu, takze
# v rozich vznikne zaobleny spoj (ostry zlom je to, co vypadalo "pixelove")
# a na konci cesty kulata spicka. Antialiasing je zapnuty u vsech tahu.
#
# KROUZKY JEN V ROHACH, NE V KAZDEM BODE. Krouzek na rovnem useku je stejne
# pod tahem a nikdo ho nevidi - a byl to nejdrazsi kus celeho snimku: sest
# cest x ctyri tahy x kazdy bod znamenalo pres sest set kreslicich prikazu
# za snimek a hra se kvuli tomu sekala. Seznam rohu je predpocitany v siti
# (`Network.lane_joint`), takze se za snimek nic nepocita.
func _lane_stroke(lane: int, path: PackedVector2Array, col: Color, w: float) -> void:
	if path.size() < 2:
		return
	draw_polyline(path, col, w, true)
	if lane < 0 or lane >= game.net.lane_joint.size():
		return
	var r: float = w * 0.5
	var joints: Array = game.net.lane_joint[lane]
	for k in joints:
		draw_circle(path[int(k)], r, col, true, -1.0, true)


# PAS KOLEM CESTY. Kazda cesta ma po obou stranach jednu bunku ve SVETLEJSIM
# odstinu sve barvy (Jan: "Kolem kazde cesty bude podbarveni ve stejne barve
# jaky ma cesta element, ale bude mit svetlejsi odstin"). Pas je CELA
# STAVEBNI PLOCHA hry, takze se kresli jen tam, kde se opravdu da stavet -
# u vyhybek a spojek zadny neni.
func _draw_strip() -> void:
	var cw: float = game.net.cell_w
	var ch: float = game.net.cell_h
	var o: Vector2 = game.net.origin
	for cellv in game.net.strip_cells:
		var c: Vector2i = cellv
		var lane: int = game.net.strip_lane_of(c)
		if lane < 0:
			continue
		var col: Color = Level.strip_color(game.net.lane_element(lane))
		draw_rect(Rect2(o.x + cw * float(c.x), o.y + ch * float(c.y), cw, ch), col)


# VEZE. Vez je STAVBA, ne poutnik: osmihran s tmavym obrysem, svetlejsi
# "strechou" a poctem zubu nad sebou podle urovne. Element nese BARVA (vez
# runu nekresli - runa je znacka poutniku, a prave v tom se obe pletly).
# Jan (Oct 2026): "Věže by měly být větší a měly by mít jiný design. Teď jsou
# příliš podobné nepříteli."
func _draw_towers() -> void:
	var r: float = maxf(5.0, TOWER_SIDE * layout.s)
	for item in game.towers:
		var t: Tower = item
		var p: Vector2 = game.net.cell_center(t.cell)
		var col: Color = Level.value_color(t.element)
		var pts: PackedVector2Array = _octagon(p, r)
		draw_colored_polygon(pts, col)
		_draw_poly_outline(pts, Color(0.09, 0.085, 0.08), maxf(1.5, 3.0 * layout.s))
		var cap: PackedVector2Array = _octagon(p, r * 0.55)
		draw_colored_polygon(cap, col.lightened(0.32))
		_draw_poly_outline(cap, Color(0.09, 0.085, 0.08, 0.75), maxf(1.0, 1.8 * layout.s))
		# UROVEN: pocet zubu nad vezi (cislo by se do bunky neveslo).
		var pw: float = maxf(2.0, 3.6 * layout.s)
		for l in range(t.level):
			draw_rect(Rect2(p.x - (pw * 1.5 + 1.0) + float(l) * (pw + 1.0),
				p.y - r - 5.0 * layout.s - pw, pw, pw), Color(0.95, 0.88, 0.60))


# STRELY, KTERE PRÁVĚ LETÍ. Strela je predmet s vlastni pozici, takze se
# kresli z toho, kde OPRAVDU je - ne z casovace veze.
#
# JE TO PAPRSEK (LASER), NE PUNTIK. Jan (Oct 2026): "Buď je nechme jako
# obyčejné puntíky, nebo jako laser jak to bylo předtím. Ten laser se mi
# líbil. Byl jen problém v časování, kdy nepřítel obdrží poškození."
# Casovani je vyresene jinde a jinak: poskozeni neubira vystrel, ale DOPAD
# (`Game._impact`), takze paprsek se kresli od veze az po svou spicku a
# rana prijde presne ve chvili, kdy se spicka dotkne poutnika. Kresleni do
# toho nema co mluvit - jen ukazuje, kde strela prave je.
func _draw_shots() -> void:
	for item in game.shots:
		var s: Shot = item
		_draw_laser(s.from, s.pos, Level.value_color(s.element))


# PAPRSEK. Tenky jasny tah s tmavym podkladem - a NIC na spicce. Prave ta
# koule a tlusty obal z toho delaly "sopel" (Jan: "Laser je ale stále jako
# sopel" = z tlustého tahu s velkou hlavou je kapka, ktera z veze vyteká).
# Tři tahy jdou po CELE delce paprsku, takze netvori vrstvy napric.
#
# Tmavy podklad je tam proto, ze pas je svetly: bez nej by paprsek na svetlem
# pasu zmizel. Svetle jadro neni efekt (zadny glow) - je to plocha barva.
func _draw_laser(from: Vector2, head: Vector2, col: Color) -> void:
	draw_line(from, head, Color(0.09, 0.085, 0.08), maxf(2.4, 4.4 * layout.s))
	draw_line(from, head, col, maxf(1.4, 2.6 * layout.s))
	draw_line(from, head, col.lightened(0.60), maxf(0.8, 1.2 * layout.s))


# Osmihran jako PackedVector2Array - jedna funkce pro telo i pro strechu.
func _octagon(p: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(8):
		var a: float = TAU * float(i) / 8.0 + PI / 8.0
		pts.append(p + Vector2(cos(a), sin(a)) * r)
	return pts


func _draw_poly_outline(pts: PackedVector2Array, col: Color, w: float) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, col, w)


# OZNACENI VYBRANE VEZE: ramecek bunky + CTVEREC DOSTRELU. Hrac tak vidi, kam
# vez dosahne, a zaroven ze je vybrana prave tahle (panel s tlacitky k ni
# patri). Neni to hover - stav se meni jen klepnutim.
func _draw_tower_sel(center: Vector2) -> void:
	var cw: float = game.net.cell_w
	var ch: float = game.net.cell_h
	var o: Vector2 = game.net.origin
	draw_rect(Rect2(o.x + cw * float(game.sel_tower.x), o.y + ch * float(game.sel_tower.y),
		cw, ch), Color(0.95, 0.88, 0.60, 0.85), false, maxf(2.0, 3.0 * layout.s))
	var d: int = Tower.RANGE
	var a: Vector2 = o + Vector2(cw * float(game.sel_tower.x - d), ch * float(game.sel_tower.y - d))
	var b: Vector2 = o + Vector2(cw * float(game.sel_tower.x + d + 1), ch * float(game.sel_tower.y + d + 1))
	draw_rect(Rect2(a, b - a), Color(0.95, 0.88, 0.60, 0.30), false, maxf(1.0, 1.8 * layout.s))
	draw_circle(center, maxf(2.0, 3.0 * layout.s), Color(0.95, 0.88, 0.60))


# PANEL VYBRANE VEZE. Jedno misto, kde se vez vylepsuje a prodava - cisla
# (poskozeni, nabijeni, cena) jsou tu vedle tlacitek, takze hrac nemusi nikam
# odchazet. Panel se kresli na protilehlou stranu, nez vez stoji (viz
# ScreenLayout.tower_panel), aby nikdy nezakryl to, co hrac vybral.
func _draw_tower_panel(t: Tower) -> void:
	var bar: Rect2 = layout.tower_bar
	draw_rect(bar, PANEL_BG)
	draw_line(Vector2(bar.position.x, bar.position.y),
		Vector2(bar.end.x, bar.position.y), Color(0.46, 0.42, 0.35), layout.ul(2.0))
	var col: Color = Level.value_color(t.element)
	_label(Vector2(layout.text_x, bar.position.y + bar.size.y * 0.42),
		"Věž %s · úroveň %d" % [Level.value_name(t.element), t.level], 18, col)
	_label(Vector2(layout.text_x, bar.position.y + bar.size.y * 0.78),
		"%.0f poškození · %.2f s · dostřel %d" % [t.damage(), t.cooldown(), Tower.RANGE],
		13, Color(0.58, 0.55, 0.49))
	# VYLEPSIT: cena je na tlacitku, aby hrac nemusel nikam koukat.
	# NA MAXIMU se misto slova "Maximalni" pise POCET ZUBU: uroven veze se
	# na desce cte jako zuby nad ni (Jan, Oct 2026: "Počet zubů"), takze
	# hrac vidi na vezi i v panelu to same cislo.
	if t.can_upgrade():
		_draw_bar_btn(layout.tower_up, "Vylepšit %d" % t.upgrade_cost(), col, true)
	else:
		_draw_bar_btn(layout.tower_up, _teeth_text(t.level), col, false)
	_draw_bar_btn(layout.tower_sell, "Prodat +%d" % t.sell_back(), Color(0.85, 0.42, 0.36), true)


# ZUBY. Uroven veze se na desce cte jako zuby nad ni, takze se poctem zubu
# pise i uroven v panelu na maximu (Jan, Oct 2026: "Počet zubů"). Ceske
# sklonovani: 1 zub, 2-4 zuby, 5+ zubu.
func _teeth_text(n: int) -> String:
	if n == 1:
		return "1 zub"
	if n >= 2 and n <= 4:
		return "%d zuby" % n
	return "%d zubů" % n


func _draw_bar_btn(r: Rect2, text: String, accent: Color, live: bool) -> void:
	draw_rect(r, PANEL_BTN)
	if live:
		draw_rect(r, Color(accent.r, accent.g, accent.b, 0.55), false, layout.ul(2.0))
	_label(Vector2(r.get_center().x, r.position.y + r.size.y * 0.64), text, 16,
		Color(0.90, 0.87, 0.80) if live else Color(0.42, 0.40, 0.36), true, r.size.x)


# MRIZKA. Kresli se JEN V EDITORU - v hre by byla nabytkem, ktery by bral
# misto cestam. Hrac v ni vidi, ze cesta jde po bunkach a kam presne saha.
#
# KAZDA CTVRTA CARA JE VYRAZNEJSI (Level.GRID_STEP): v poli 28x14 se bez
# pravidelneho rytmu neda pocitat bunky. Barvy jsou v `Level`, aby se na ne
# test mohl zeptat - a aby mrizka nebyla tmavsi nez podklad desky, jak se
# stalo driv (0.20 proti podkladu 0.125 vypadalo v ruce jako nic).
func _draw_grid() -> void:
	if game.net.level == null:
		return
	var cw: float = game.net.cell_w
	var ch: float = game.net.cell_h
	var o: Vector2 = game.net.origin
	var gw: float = cw * float(game.net.level.cols)
	var gh: float = ch * float(game.net.level.rows)
	for i in range(game.net.level.cols + 1):
		var x: float = o.x + cw * float(i)
		var major: bool = i > 0 and i < game.net.level.cols and i % Level.GRID_STEP == 0
		draw_line(Vector2(x, o.y), Vector2(x, o.y + gh),
			Level.GRID_MAJOR if major else Level.GRID_LINE,
			layout.bl(2.0) if major else layout.bl(1.5))
	for j in range(game.net.level.rows + 1):
		var y: float = o.y + ch * float(j)
		var major: bool = j > 0 and j < game.net.level.rows and j % Level.GRID_STEP == 0
		draw_line(Vector2(o.x, y), Vector2(o.x + gw, y),
			Level.GRID_MAJOR if major else Level.GRID_LINE,
			layout.bl(2.0) if major else layout.bl(1.5))
	draw_rect(Rect2(o, Vector2(gw, gh)), Color(0.42, 0.39, 0.33, 0.9), false, layout.bl(2.0))


# UZLY. Kazdy uzel je znacka na sve bunce a hrac z ni pozna, co se tam deje:
#
#   VYHYBKA - krouzek s Y. Cesta se tu ROZBOČUJE a hrac svou volbou
#             rozhoduje, kterou vetvi poutnik pujde. Barva krouzku je barva
#             useku, ktery je prave vybrany - takze hrac vidi u kazde
#             vyhybky, kam posle dalsiho poutnika.
#   SPOJKA  - krouzek s OBRACENYM Y. Cesty se tu SLIJI, nerozhoduje se tu
#             nic - proto se nekresli jako volic.
#   START   - plny krouzek. Sem poutnici vstupuji.
#   CIL     - dira v mape s krizkem. Kresli se TADY, ne ve zvlastni
#             funkci pro herni desku: driv ji kreslila jen bitva, takze
#             v editoru cil po položení zmizel (Jan: "cil nema zadnou
#             znacku... a pak uz neni cil videt").
#   UZEL    - maly plny ctverecek. Je to pruchozi bod; musi byt videt, ze
#             tam neco je, i kdyz se v nem nerozhoduje.
#
# Y proti obracenemu Y je zamer: kriz proti krizi by se na malem displeji
# slil a hrac by nepoznal, na co se kouka.
func _draw_nodes() -> void:
	var rr: float = game.net.switch_r * 0.34
	var rim := Color(0.55, 0.53, 0.48)
	for n in range(game.net.node_pos.size()):
		var p: Vector2 = game.net.node_pos[n]
		match int(game.net.node_kind[n]):
			Level.START:
				draw_circle(p, rr * 0.60, Color(0.62, 0.58, 0.50))
			Level.CIL:
				_draw_exit_mark(p)
			Level.UZEL:
				draw_rect(Rect2(p.x - rr * 0.45, p.y - rr * 0.45,
					rr * 0.90, rr * 0.90), Color(0.62, 0.58, 0.50))
			Level.VYHYBKA:
				var lane: int = game.selected_lane(game.net.junction_index_of_node(n))
				var col: Color = _lane_color(lane) if lane >= 0 else rim
				draw_circle(p, rr, Color(0.10, 0.095, 0.085))
				draw_arc(p, rr, 0.0, TAU, 24, col, layout.bl(3.0))
				_draw_y(p, rr * 0.52, col, false)
			Level.SPOJKA:
				draw_circle(p, rr, Color(0.10, 0.095, 0.085))
				draw_arc(p, rr, 0.0, TAU, 24, rim, layout.bl(3.0))
				_draw_y(p, rr * 0.52, Color(0.68, 0.64, 0.56), true)
		# OZNACENY PRVEK je obkresleny - hrac musi videt, co si vybral
		# klepnutim. Kresli se JEN v editoru; v hre se neoznacuje nic.
		# (Musi byt AZ ZA `match` - uvnitr by to GDScript cetl jako dalsi
		# vzor a spadl by na chybe pri nacitani skriptu.)
		if menu.is_editor() and editor.sel_node == n:
			draw_arc(p, rr * 1.55, 0.0, TAU, 28, Color(0.90, 0.87, 0.80), 2.0)
		# A PRVEK V OBDELNIKU je obkresleny taky: hromadny vyber musi byt
		# videt na prvni pohled, ne jen pocet v hlasce.
		if menu.is_editor() and editor.has_box() and editor.box_nodes().has(n):
			draw_arc(p, rr * 2.4, 0.0, TAU, 28, Color(0.62, 0.74, 0.86), 2.0)


# CIL MA ZNACKU: DIRA S PRSTENCEM. Cesta z cile odchazi na okraj displeje a
# poutnik tam zmizi, takze v bitve cil vidi jako konec cesty za obrazovkou -
# tam se nekresli nic.
#
# V EDITORU ALE ZNACKU MIT MUSI. Jan (Oct 2026): "zdá se, že cíl nemá žádnou
# značku. Možná proto jsem si nevšiml, že je zároveň na spojce. Musíme mu dát
# nějakou značku." Maly tmavy bod (co tu byl) na tmave desce splyne - hrac
# cil polozi a nevi, kam presne padl, ani ze stoji na uzlu.
#
# DVOJITY PRSTENEC je zamer: uzly maji uvnitr Y (vyhybka) nebo obracene Y
# (spojka), poutnik ma runu - kruh s necim uvnitr je vzdy neco jineho. Dve
# soustredne kruznice nema nikdo, takze se cil neplete s nicim. Krizek v
# kruhu tu byt NESMI (Jan: "nebude mit tuto vyraznou znacku krizku v kruhu.
# Je to prilis mnoho"). Barva je kost - jedina barva na desce, ktera
# neznamena zivel (a proto se cilem neda splest s cestou).
func _draw_exit_mark(p: Vector2) -> void:
	if not menu.is_editor():
		return
	var r: float = maxf(6.0, game.net.exit_r * 0.62)
	draw_circle(p, r, Color(0.105, 0.10, 0.095))
	draw_arc(p, r, 0.0, TAU, 28, CIL_RING, maxf(2.0, 3.4 * layout.s))
	draw_arc(p, r * 0.52, 0.0, TAU, 20, CIL_RING, maxf(1.2, 2.0 * layout.s))


func _draw_y(c: Vector2, r: float, col: Color, up: bool) -> void:
	var s: float = -1.0 if up else 1.0
	draw_line(c + Vector2(0.0, -r * s), c, col, 2.0)
	draw_line(c, c + Vector2(-r * 0.85, r * s), col, 2.0)
	draw_line(c, c + Vector2(r * 0.85, r * s), col, 2.0)


# NEUTRALNI VYSTUP uz ma vlastni kreslici funkci `_draw_exit_mark` a kresli
# ho `_draw_nodes` - cil je uzel jako kazdy jiny a musi byt videt i v editoru.
# Zvlastni funkce pro herni desku tu driv byla a byla to chyba: v editoru cil
# po položení zmizel.


func _draw_enemies() -> void:
	for item in game.enemies:
		var e: Enemy = item
		if not e.on_lane():
			continue
		var p: Vector2 = _enemy_pos(e)
		var col: Color = Element.color_of(e.element)
		draw_circle(p, ENEMY_R_OUT * layout.s, Color(0.09, 0.085, 0.08))
		draw_circle(p, ENEMY_R_IN * layout.s, col)
		_glyph(e.element, p, ENEMY_GLYPH * layout.s, Color(0.07, 0.06, 0.06))
		if e.hp_frac() < 1.0:
			draw_arc(p, ENEMY_HP_R * layout.s, -PI * 0.5, -PI * 0.5 + TAU * e.hp_frac(), 24,
				Color(0.90, 0.85, 0.55), 3.0)


func _enemy_pos(e: Enemy) -> Vector2:
	return e.pos


# HORNI PANEL. Dva radky s písmem 20/13 px se vejdou do 52 px, takze je
# polovicni proti puvodnimu - kazdy pixel navic jde do herni desky.
# Popisek vybraneho useku je tu ZAMERNE: je to jedine misto, kde hrac vidi,
# jak silna dmg zona ho prave ceka.
func _draw_hud() -> void:
	draw_rect(Rect2(0.0, 0.0, layout.view.x, layout.hud_h), Color(0.075, 0.07, 0.065))
	draw_line(Vector2(0.0, layout.hud_h), Vector2(layout.view.x, layout.hud_h),
		Color(0.28, 0.25, 0.21), layout.ul(2.0))
	var step: float = layout.view.x * 0.19
	var x0: float = 18.0 * layout.s
	_label(Vector2(x0, layout.hud_h * 0.48), "Kolo %d" % game.round, 20, Color(0.90, 0.87, 0.80))
	# Druhy radek leveho sloupce: faze a JMENO LEVELU. Jmeno musi byt videt -
	# hrac ma vedet, co hraje. Driv viselo POD panelem, tedy na herni plose,
	# a bralo desce pixel; v panelu je na to misto.
	var lv_name: String = game.level.name if game.level != null else "?"
	_label(Vector2(x0, layout.hud_h * 0.88), "%s · %s" % [game.phase, lv_name], 13,
		Color(0.58, 0.55, 0.49))
	_label(Vector2(x0 + step, layout.hud_h * 0.48), "Životy %d" % game.lives, 20,
		Color(0.85, 0.42, 0.36) if game.lives <= 4 else Color(0.90, 0.87, 0.80))
	_label(Vector2(x0 + step, layout.hud_h * 0.88), "z %d" % game.lives_max, 13,
		Color(0.58, 0.55, 0.49))
	_label(Vector2(x0 + step * 2.0, layout.hud_h * 0.48), "Zlato %d" % game.gold, 20,
		Color(0.88, 0.78, 0.45))
	_label(Vector2(x0 + step * 2.0, layout.hud_h * 0.88),
		"věž %d · vylepšení %d · %d" % [Tower.level_cost(1), Tower.level_cost(2),
			Tower.level_cost(3)], 13, Color(0.58, 0.55, 0.49))
	# Vybrany usek: kolik obrany u nej stoji. Vyhybkou si hrac kupuje "kam
	# je poslu", takze potrebuje videt, kde ma veze - a je to jedine misto,
	# kde to vidi jako cislo (na desce jsou jen znacky).
	var sel: int = game.switch_lane()
	if sel < 0:
		sel = 0
	var sel_txt: String
	if game.net.lane_count() == 0:
		sel_txt = "—"
	else:
		var n: int = game.towers_of_lane(sel)
		sel_txt = "%s · %d %s" % [game.net.level.lane_type_name(sel), n, _towers_word(n)]
	_label(Vector2(x0 + step * 3.0, layout.hud_h * 0.48), sel_txt, 18, Color(0.72, 0.70, 0.64))
	# FAZE KOLA. Kolo nema pocet poutniku, takze hrac potrebuje dve cisla:
	# kolik sekund jeste vstupy tecou a kolik poutniku je na desce. Ve fazi
	# "dočištění" uz vstupy nejsou a hra jen dobíjí zbytek.
	var info: String
	var info_col: Color = Color(0.58, 0.55, 0.49)
	if game.phase == "build":
		info = "Příprava %.1f s" % game.build_timer
		info_col = Color(0.65, 0.78, 0.60)
	elif game.phase == "round":
		info = "kolo %.0f s · v úsecích %d" % [game.round_left, game.enemies.size()]
	elif game.phase == "clear":
		info = "dočištění · v úsecích %d" % game.enemies.size()
	elif game.phase == "lost":
		info = "síť padla"
	else:
		info = "v úsecích: %d" % game.enemies.size()
	_label(Vector2(x0 + step * 3.0, layout.hud_h * 0.88), info, 13, info_col)

	# NAVRAT DO EDITORU. Kresli se jen kdyz hrac hraje level z editoru - je to
	# jedine tlacitko, ktere se v hornim panelu hry muze objevit, a je mimo
	# herni desku (panel neni hraci plocha).
	if _from_editor:
		var br: Rect2 = layout.hud_back
		draw_rect(br, Color(0.20, 0.19, 0.17))
		draw_rect(br, Color(0.78, 0.62, 0.30), false, layout.ul(2.0))
		_draw_centered("EDITOR", br, br.position.y + br.size.y * 0.66, 16,
			Color(0.90, 0.87, 0.80))

	if game.phase == "lost":
		var bw: float = minf(420.0 * layout.s, layout.view.x * 0.8)
		var bh: float = 116.0 * layout.s
		var bp := Vector2((layout.view.x - bw) * 0.5, layout.view.y * 0.38)
		draw_rect(Rect2(bp, Vector2(bw, bh)), Color(0.13, 0.09, 0.09))
		draw_rect(Rect2(bp, Vector2(bw, bh)), Color(0.55, 0.25, 0.22), false, layout.ul(3.0))
		_label(Vector2(bp.x + bw * 0.5, bp.y + bh * 0.45), "SÍŤ PADLA", 30,
			Color(0.88, 0.46, 0.38), true, bw)
		_label(Vector2(bp.x + bw * 0.5, bp.y + bh * 0.78),
			"vydržels %d %s" % [game.round, _rounds_word(game.round)], 16,
			Color(0.75, 0.71, 0.65), true, bw)
	if toast_t > 0.0:
		_label(Vector2(layout.view.x * 0.5, layout.hud_h + 24.0 * layout.s), toast, 16,
			Color(0.78, 0.75, 0.68), true, layout.view.x * 0.9)


func _draw_centered(text: String, r: Rect2, baseline_y: float, size: int, col: Color) -> void:
	draw_string(_font, Vector2(r.position.x, baseline_y), text, HORIZONTAL_ALIGNMENT_CENTER,
		r.size.x, layout.font(float(size)), col)


# TEXT ZAROVNANY K PRAVEMU OKRAJI SVÉHO OBDELNIKU (hodnota v panelu hned pred
# tlacitky "−"/"+"): text tak stoji tesne u tlacitek, ktera k nemu patri.
# Drobny odstup (4*ui) drzi text od ramecku tlacitka - bez nej se posledni
# pismeno dotyka ramecku a vypada to jako chyba kresleni.
func _draw_right(text: String, r: Rect2, baseline_y: float, size: int, col: Color) -> void:
	var inset: float = 4.0 * layout.ui
	draw_string(_font, Vector2(r.position.x, baseline_y), text, HORIZONTAL_ALIGNMENT_RIGHT,
		maxf(r.size.x - inset, 1.0), layout.font(float(size)), col)


# ČESKÉ SKLOŇOVÁNÍ POČTU VEZI (1 věž, 2-4 věže, 5+ věží). Rovnou tady, aby
# text v panelu nelhal - "3 věž" je vidět a hrac si toho vsimne.
func _towers_word(n: int) -> String:
	if n == 1:
		return "věž"
	if n >= 2 and n <= 4:
		return "věže"
	return "věží"


# ČESKÉ SKLOŇOVÁNÍ POČTU KOL (1 kolo, 2-4 kola, 5+ kol). Rovnou tady, aby
# text v prohře nelhal - "vydržels 1 kol" je vidět a hrac si toho vsimne.
func _rounds_word(n: int) -> String:
	if n == 1:
		return "kolo"
	if n >= 2 and n <= 4:
		return "kola"
	return "kol"


func _label(at: Vector2, text: String, size: int, col: Color,
		centered: bool = false, width: float = 400.0) -> void:
	var fs: int = layout.font(float(size))
	if centered:
		draw_string(_font, Vector2(at.x - width * 0.5, at.y), text,
			HORIZONTAL_ALIGNMENT_CENTER, width, fs, col)
	else:
		draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


# TEXT ZAROVNANY DOPRAVA (k pravemu okraji obrazovky nebo ramecku).
# POZOR: _label() kresli VZDY ZLEVA od zadaneho x a `width` pouzije jen pri
# `centered`. Kdyz se text u praveho okraje kreslil pres _label(), zacal na
# okraji a tekl MIMO obrazovku - hrac nevidel NIC. Presne to se delo hlásce
# editoru ("co se prave stalo"), prepinacum v nastaveni i kodu levelu: hrac
# nemel jak zjistit, proc neco nejde.
func _label_right(text: String, y: float, size: int, col: Color, right_x: float) -> void:
	var fs: int = layout.font(float(size))
	var w: float = maxf(right_x, 40.0)
	draw_string(_font, Vector2(right_x - w, y), text, HORIZONTAL_ALIGNMENT_RIGHT, w, fs, col)


# Sirka textu tak, jak ho opravdu nakresli _label()/_label_right().
func _text_w(text: String, size: int) -> float:
	return _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		layout.font(float(size))).x


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
