extends Node2D

# Jedina scena hry. Vsechno se KRESLI rucne - zadne Button nody,
# zadne theme, zadne hover/focus efekty. Jeden vstupni bod, jeden hit-test.
#
# POSKOZENI DELA CELEK USEKU, ne vez. Proto se tady kresli DMG ZONY -
# barevny pas pres cely rovny usek kazdeho pruhu. Hrac tak vidi, kde se
# bude poutnikum ubirat zivot, a kde ne.
#
# ROZVRZENI JE RESPONZIVNI: pozice jdou z realne velikosti okna pres
# ScreenLayout, velikosti z jednoho meritka. Pri zmene velikosti okna se
# sit prelozi za behu.

const MAX_TOAST := 3.0
# Sirka pasu dmg zony. Je to ZNACKA, ne presna mechanika - mechanika je
# "cely usek", ale pas to musi ukazat citelne.
const ZONE_THICK := 24.0
# Frekvence basove linky. Dlouha, pomalá - ma byt slyset, ne otravovat.
const MUSIC_HZ := 55.0

var layout := ScreenLayout.new()
var game: Game = null
var menu := Menu.new()
var settings := Settings.new()
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
	elif args.has("--settings-shot"):
		menu.open_settings()
		_shot = true
	elif args.has("--battle"):
		# Rovnou do hry - pouziva se pri kontrole vzhledu herni plochy.
		_start_battle()


func _place_to_window() -> void:
	layout.compute(get_viewport_rect().size)
	if game == null:
		game = Game.new()
		game.setup(layout.arena, layout.s, layout.bar_y)
	else:
		_reflow()


# Preklopeni site na aktualni rozvrzeni. `bar_top` jde do build() jako
# parametr - kdyby se nastavil az na hotove siti, pocital by stary pruh.
func _reflow() -> void:
	game.rebuild_network(layout.arena, layout.s, layout.bar_y)


func _on_resize() -> void:
	layout.compute(get_viewport_rect().size)
	# Stav hry zustava, prelozi se jen geometrie site.
	_reflow()


# Nahledovy rezim pro kontrolu vzhledu: postavi ukazkovou sit a zmrazi hru
# v okamziku, kdy jsou poutnici na usecich, aby snimek neukazal prazdno.
func _setup_shot() -> void:
	menu.open_battle()
	game.gold = 5000
	for lane in range(Network.LANES):
		if Network.lane_accepts(lane, Network.lane_element(lane)):
			game.try_build(lane, 0, Network.lane_element(lane))
			game.try_build(lane, 2, Network.lane_element(lane))
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
# GENERUJE (jednoducha basova linka + tuknuti pri stisku), protoze hra
# zatim zadne audio soubory nema - a ticho by u "zapni/vypni hudbu"
# nešlo poznat. Casem se da nahradit skutecnou hudbou beze zmeny UI.
func _setup_audio() -> void:
	_music = AudioStreamPlayer.new()
	_music.stream = _make_tone(MUSIC_HZ, 3.0, 0.12)
	_music.volume_db = -16.0
	_music.bus = "Master"
	add_child(_music)
	_sfx = AudioStreamPlayer.new()
	_sfx.stream = _make_tone(220.0, 0.09, 0.5)
	_sfx.volume_db = -6.0
	_sfx.bus = "Master"
	add_child(_sfx)


# Obalka (ADSR-like) pres sinusovku - aby ton nepraskal na zacatku a konci.
func _make_tone(hz: float, sec: float, amp: float) -> AudioStreamWAV:
	var rate := 22050
	var n: int = int(sec * float(rate))
	var data := PackedByteArray()
	data.resize(n * 2)
	var fade: float = float(rate) * 0.04
	for i in range(n):
		var x: float = float(i) / float(rate)
		var env: float = 1.0
		if float(i) < fade:
			env = float(i) / fade
		elif float(i) > float(n) - fade:
			env = maxf(0.0, (float(n) - float(i)) / fade)
		var v: int = int(sin(TAU * hz * x) * amp * env * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


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


func _start_battle() -> void:
	game.setup(layout.arena, layout.s, layout.bar_y)
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
	if menu.is_settings():
		_handle_settings_tap(pos)
		return
	if layout.skip_rect.has_point(pos):
		game.run_for(6.0)
		return
	# Misto na bonus ma prednost: klepnuti na nej stavi, pripadne vylepsuje.
	# Klepnuti kamkoli JINAM na usek prepne vyhybku na ten usek. Zadna
	# tlacitka vyhybky nejsou - casem jich bude vic, nez se jich do pruhu
	# vejde, a usek je to, na co se stejne kouka.
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


# MENU: tri tlacitka. Battle spusti kolo, Settings otevre nastaveni,
# Update si vyzada novou verzi PWA.
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
				menu.open_settings()
			2:
				menu.request_update()
		return


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
	if menu.is_settings():
		_draw_settings()
		return
	_draw_battle()


func _draw_battle() -> void:
	_draw_background()
	_draw_lanes()
	_draw_zones()
	_draw_slots()
	_draw_exits()
	_draw_switch()
	_draw_bonuses()
	_draw_enemies()
	_draw_trunk()
	_draw_hud()
	_draw_control_bar()


# ---------------------------------------------------------------- menu

# Prvni obrazovka. Plochy, strojovy design jako zbytek hry - zadne karty,
# zadne efekty. Tri tlacitka: Battle, Settings, Update.
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

	var names := ["BATTLE", "SETTINGS", "UPDATE"]
	var subs := ["spustit kolo", "hudba a zvuky", "stáhnout novou verzi"]
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
		_label(Vector2(cx, layout.menu_buttons[2].end.y + 30.0 * layout.ui), menu.update_note, 13,
			Color(0.72, 0.70, 0.62), true, layout.view.x * 0.9)


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
# ktery dela vsem stejne, takze ma vlastni, klidnou barvu a v navodu
# je popsan slovem.
func _lane_color(lane: int) -> Color:
	if Network.lane_is_neutral(lane):
		return Color(0.55, 0.53, 0.48)
	return Element.color_of(Network.lane_element(lane))


func _draw_lanes() -> void:
	var lw: float = maxf(2.0, 9.0 * layout.s)
	var sel: int = game.switch_lane()
	for lane in range(Network.LANES):
		var col: Color = _lane_color(lane)
		var path: PackedVector2Array = game.net.lane_path[lane]
		# VYBRANY USEK JE SVETLEJSI, ALE PORAD SVOJI BARVY. Hrac tak vidi,
		# kam poutniky posle, aniž by musel hadat, ktery element to je -
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
# se poutnikum ubira zivot. Pas je u vybraneho useku sytější, aby bylo
# videt, kde dmg zona prave pracuje.
func _draw_zones() -> void:
	var thick: float = ZONE_THICK * layout.s
	var sel: int = game.switch_lane()
	for lane in range(Network.LANES):
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
		# Nasobek, ktery zona dava - hrac vidi na prvni pohled, co si
		# vyhybkou kupuje. Cislo, ne jen barva.
		var mid: Vector2 = Vector2((game.net.band_x0 + game.net.band_x1) * 0.5, y)
		var txt: String
		if Network.lane_is_neutral(lane):
			txt = "dmg × 1.0"
		else:
			txt = "dmg × %.1f" % Element.STRONG
		_label(Vector2(mid.x, y + thick * 0.5 + 13.0 * layout.ui), txt, 11,
			Color(0.62, 0.59, 0.53), true, 130.0)


func _draw_trunk() -> void:
	var a: Vector2 = game.net.trunk_start
	var b: Vector2 = game.net.merge
	draw_line(a, b, Color(0.42, 0.38, 0.32, 0.75), maxf(2.0, 9.0 * layout.s))
	draw_line(a, b, Color(0.58, 0.53, 0.44, 0.9), maxf(1.0, 3.0 * layout.s))
	_label(Vector2(b.x - 74.0 * layout.s, b.y - 30.0 * layout.s),
		"neutrální kmen", 12, Color(0.52, 0.49, 0.44))


func _draw_slots() -> void:
	var r: float = game.net.bonus_r
	for lane in range(Network.LANES):
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
			if not Network.lane_is_neutral(lane):
				_glyph(Network.lane_element(lane), p, r * 0.52,
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
	_label(Vector2(game.net.merge.x - 92.0 * layout.s, game.net.merge.y - 30.0 * layout.s),
		"výhybka — klepni na úsek", 13, Color(0.62, 0.59, 0.53))


# NEUTRALNI VYSTUP. Nema element a nikdo ho nevlastni - kazdy poutnik,
# ktery tam dojde, stoji zivot. Krizek je zamerne jiny tvar nez vsechny
# runy, aby se nepletl s elementem.
func _draw_exits() -> void:
	var r: float = game.net.exit_r
	for i in range(game.net.exit_pos.size()):
		var p: Vector2 = game.net.exit_pos[i]
		draw_circle(p, r, Color(0.13, 0.12, 0.11))
		draw_arc(p, r, 0.0, TAU, 32, Color(0.62, 0.58, 0.52), 3.0)
		var d: float = r * 0.42
		draw_line(p - Vector2(d, d), p + Vector2(d, d), Color(0.72, 0.68, 0.60), 3.0)
		draw_line(p + Vector2(d, -d), p - Vector2(d, -d), Color(0.72, 0.68, 0.60), 3.0)
		_label(Vector2(p.x, p.y + 54.0 * layout.s), "výstup", 15,
			Color(0.72, 0.69, 0.62), true, 68.0)


func _draw_enemies() -> void:
	for item in game.enemies:
		var e: Enemy = item
		var p: Vector2 = _enemy_pos(e)
		var col: Color = Element.color_of(e.element)
		draw_circle(p, 13.0 * layout.s, Color(0.09, 0.085, 0.08))
		draw_circle(p, 11.0 * layout.s, col)
		_glyph(e.element, p, 7.0 * layout.s, Color(0.07, 0.06, 0.06))
		if e.hp_frac() < 1.0:
			draw_arc(p, 17.0 * layout.s, -PI * 0.5, -PI * 0.5 + TAU * e.hp_frac(), 24,
				Color(0.90, 0.85, 0.55), 3.0)


func _enemy_pos(e: Enemy) -> Vector2:
	if e.on_lane():
		return game.net.point_at(e.lane, e.s)
	return game.net.trunk_point_at(e.s)


func _draw_hud() -> void:
	draw_rect(Rect2(0.0, 0.0, layout.view.x, layout.hud_h), Color(0.075, 0.07, 0.065))
	draw_line(Vector2(0.0, layout.hud_h), Vector2(layout.view.x, layout.hud_h),
		Color(0.28, 0.25, 0.21), 2.0)
	var step: float = layout.view.x * 0.19
	var x0: float = 18.0 * layout.s
	_label(Vector2(x0, layout.hud_h * 0.46), "Vlna %d" % game.wave, 20, Color(0.90, 0.87, 0.80))
	_label(Vector2(x0, layout.hud_h * 0.82), game.phase, 13, Color(0.58, 0.55, 0.49))
	_label(Vector2(x0 + step, layout.hud_h * 0.46), "Životy %d" % game.lives, 20,
		Color(0.85, 0.42, 0.36) if game.lives <= 4 else Color(0.90, 0.87, 0.80))
	_label(Vector2(x0 + step, layout.hud_h * 0.82), "z %d" % Game.START_LIVES, 13,
		Color(0.58, 0.55, 0.49))
	_label(Vector2(x0 + step * 2.0, layout.hud_h * 0.46), "Zlato %d" % game.gold, 20,
		Color(0.88, 0.78, 0.45))
	_label(Vector2(x0 + step * 2.0, layout.hud_h * 0.82),
		"bonus %d · vylepšení %d" % [Bonus.COST, Bonus.UPGRADE_COST], 13, Color(0.58, 0.55, 0.49))
	# Vybrany usek: kolik dmg zona dava. Tohle je ta informace, kterou si
	# hrac vyhybkou kupuje, tak patri do HUDu.
	var sel: int = game.switch_lane()
	var sel_txt: String
	if Network.lane_is_neutral(sel):
		sel_txt = "neutrální × 1.0"
	else:
		sel_txt = "%s × %.1f" % [Element.name_of(Network.lane_element(sel)),
			Element.STRONG * game.lane_mult(sel)]
	_label(Vector2(x0 + step * 3.0, layout.hud_h * 0.46), sel_txt, 18, Color(0.72, 0.70, 0.64))
	if game.phase == "build":
		_label(Vector2(x0 + step * 3.0, layout.hud_h * 0.82),
			"Příprava %.1f s" % game.build_timer, 13, Color(0.65, 0.78, 0.60))
	else:
		_label(Vector2(x0 + step * 3.0, layout.hud_h * 0.82),
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


func _draw_control_bar() -> void:
	draw_rect(Rect2(0.0, layout.bar_y, layout.view.x, layout.bar_h), Color(0.075, 0.07, 0.065))
	draw_line(Vector2(0.0, layout.bar_y), Vector2(layout.view.x, layout.bar_y),
		Color(0.28, 0.25, 0.21), 2.0)
	_draw_legend()

	draw_rect(layout.skip_rect, Color(0.20, 0.19, 0.17))
	draw_rect(layout.skip_rect, Color(0.38, 0.35, 0.30), false, 2.0)
	_draw_centered("SKIP", layout.skip_rect,
		layout.skip_rect.position.y + layout.skip_rect.size.y * 0.44, 18, Color(0.85, 0.82, 0.76))
	_draw_centered("6 s", layout.skip_rect,
		layout.skip_rect.position.y + layout.skip_rect.size.y * 0.80, 13, Color(0.58, 0.55, 0.49))


# NAVOD. Pruh ukazuje cely cas, jak se na kterem useku pocita poskozeni.
# Dva radky:
#   1. runa zivlu -> runa jeho protikladu (kdo je silny proti komu),
#   2. cisla pro vsechny pripady: neutralni, vlastni, jiny, protiklad.
# Runa je u toho proto, ze barva nesmi byt jediny nosic informace.
func _draw_legend() -> void:
	var r: Rect2 = layout.legend
	var y1: float = r.position.y + r.size.y * 0.30
	var y2: float = r.position.y + r.size.y * 0.78
	var col_w: float = r.size.x / float(Element.COUNT)
	var run_r: float = minf(9.0 * layout.s, col_w * 0.11)
	for e in range(Element.COUNT):
		var x0: float = r.position.x + col_w * float(e)
		var col: Color = Element.color_of(e)
		var opp: int = Element.opposite_of(e)
		var ocol: Color = Element.color_of(opp)
		var cx: float = x0 + col_w * 0.5 - run_r * 3.4
		_glyph(e, Vector2(cx, y1), run_r, col)
		var ax0: float = cx + run_r * 1.7
		var ax1: float = ax0 + run_r * 2.4
		draw_line(Vector2(ax0, y1), Vector2(ax1, y1), Color(0.55, 0.52, 0.46), 2.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(ax1 + 5.0, y1), Vector2(ax1, y1 - 4.5), Vector2(ax1, y1 + 4.5)]),
			Color(0.55, 0.52, 0.46))
		_glyph(opp, Vector2(ax1 + 5.0 + run_r * 0.9, y1), run_r, ocol)
		_label(Vector2(x0 + col_w * 0.5, y1 + layout.ui * 14.0),
			"%s → %s" % [Element.name_of(e), Element.name_of(opp)], 12,
			Color(0.80, 0.77, 0.70), true, col_w)
	_label(Vector2(r.position.x + r.size.x * 0.5, y2),
		"neutrální úsek: všichni 100 %%  ·  vlastní 0 %%  ·  jiný 50 %%  ·  protiklad 200 %%",
		13, Color(0.72, 0.69, 0.62), true, r.size.x)


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
