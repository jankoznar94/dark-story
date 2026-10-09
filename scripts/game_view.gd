extends Node2D

# Jedina scena hry. Vsechno se KRESLI rucne - zadne Button nody,
# zadne theme, zadne hover/focus efekty. Jeden vstupni bod, jeden hit-test.
#
# ROZVRZENI JE RESPONZIVNI: pozice jdou z realne velikosti okna pres
# ScreenLayout, velikosti z jednoho meritka. Hra NENI letterboxovana -
# na sirokem telefonu vyplni displej a koleje jsou proste delsi.
# Pri zmene velikosti okna (otoceni telefonu) se sit prelozi za behu.

const MAX_TOAST := 3.0

var layout := ScreenLayout.new()
var game: Game = null
var toast: String = ""
var toast_t: float = 0.0
var last_log_size: int = 0

var _font: Font = null
var _shot: bool = false
var _shot_frames: int = 0
var _tap_live: bool = false


func _ready() -> void:
	_font = ThemeDB.fallback_font
	game = Game.new()
	_place_to_window()
	get_viewport().size_changed.connect(_on_resize)
	if OS.get_cmdline_user_args().has("--shot"):
		_setup_shot()


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
# v okamziku, kdy jsou poutnici na kolejich, aby snimek neukazal prazdno.
func _setup_shot() -> void:
	game.gold = 5000
	for lane in range(Network.LANES):
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
	if game != null and game.phase != "lost":
		game.step(delta)
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
	if layout.skip_rect.has_point(pos):
		game.run_for(6.0)
		return
	# Misto na vez ma prednost: klepnuti na nej stavi, pripadne vylepsuje.
	# Klepnuti kamkoli JINAM na kolej prepne vyhybku na tuhle kolej. Zadna
	# tlacitka vyhybky nejsou - casem jich bude vic, nez se jich do pruhu
	# vejde, a cesta je to, na co se stejne kouka.
	var cell: Vector2i = game.net.nearest_slot(pos)
	if cell.x >= 0:
		if game.tower_at(cell.x, cell.y) != null:
			game.try_upgrade(cell.x, cell.y)
			return
		game.try_build(cell.x, cell.y, game.build_element(cell.x))
		return
	var lane: int = game.net.lane_tap_at(pos, maxf(12.0, 20.0 * layout.s))
	if lane >= 0:
		game.set_switch(lane)


func _say(text: String) -> void:
	toast = text
	toast_t = MAX_TOAST


# ---------------------------------------------------------------- kresleni

func _draw() -> void:
	_draw_background()
	_draw_lanes()
	_draw_slots()
	_draw_shrines()
	_draw_switch()
	_draw_towers()
	_draw_enemies()
	_draw_trunk()
	_draw_hud()
	_draw_control_bar()


func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, layout.view), Color(0.10, 0.095, 0.085))
	draw_rect(layout.arena, Color(0.125, 0.115, 0.10))
	# Zilky many v pozadi - jen naznak, nesmi soutezit s hernimi liniemi.
	for i in range(9):
		var t: float = float(i) / 8.0
		var y: float = layout.arena.position.y + t * layout.arena.size.y
		draw_line(Vector2(layout.arena.position.x, y + 12.0 * layout.s),
			Vector2(layout.arena.end.x, y - 18.0 * layout.s),
			Color(0.155, 0.14, 0.12, 0.55), 1.0)


func _draw_lanes() -> void:
	var lw: float = maxf(2.0, 9.0 * layout.s)
	var sel: int = game.switch_lane()
	for lane in range(Network.LANES):
		var col: Color = Element.color_of(lane)
		var path: PackedVector2Array = game.net.lane_path[lane]
		# VYBRANA KOLEJ JE SVETLEJSI, ALE PORAD SVOJI BARVY. Hrac tak vidi,
		# kam poutniky posle, aniž by musel hadat, ktery zivel to je -
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
			# Vnejsi lem vybrane kolejnice - druha znacka krome jasu,
			# aby "vybrano" fungovalo i bez rozliseni barevnych odstinu.
			var rim := col
			rim.a = 0.85
			for k in range(path.size() - 1):
				draw_line(path[k], path[k + 1], rim, maxf(1.0, 1.6 * layout.s))


func _draw_trunk() -> void:
	var a: Vector2 = game.net.trunk_start
	var b: Vector2 = game.net.merge
	draw_line(a, b, Color(0.42, 0.38, 0.32, 0.75), maxf(2.0, 9.0 * layout.s))
	draw_line(a, b, Color(0.58, 0.53, 0.44, 0.9), maxf(1.0, 3.0 * layout.s))


func _draw_slots() -> void:
	var r: float = game.net.tower_r
	for lane in range(Network.LANES):
		var col: Color = Element.color_of(lane)
		for slot in range(game.net.slot_count()):
			var p: Vector2 = game.net.slot_world(lane, slot)
			var t: Tower = game.tower_at(lane, slot)
			if t != null:
				draw_circle(p, r, Color(col.r * 0.40, col.g * 0.40, col.b * 0.40, 0.85))
				draw_arc(p, r, 0.0, TAU, 24, col, 2.0)
				continue
			# Prazdne misto nese RUNU ZIVLU TE KOLEJE - hrac tak vidi, co
			# tam muze postavit, aniz by to musel zkouset. Barva sama stacit
			# nesmi, proto je to rovnou znacka.
			draw_arc(p, r, 0.0, TAU, 24, Color(col.r, col.g, col.b, 0.30), 2.0)
			_glyph(lane, p, r * 0.52, Color(col.r, col.g, col.b, 0.42))


func _draw_towers() -> void:
	var half: float = 13.0 * layout.s
	for item in game.towers:
		var t: Tower = item
		var p: Vector2 = game.net.slot_world(t.lane, t.slot)
		var col: Color = Element.color_of(t.element)
		draw_rect(Rect2(p.x - half, p.y - half, half * 2.0, half * 2.0), col)
		_glyph(t.element, p, 8.0 * layout.s, Color(0.07, 0.06, 0.06))
		if t.level > 1:
			draw_rect(Rect2(p.x - 9.0 * layout.s, p.y - 21.0 * layout.s,
				6.0 * layout.s, 5.0 * layout.s), Color(0.95, 0.88, 0.6))
			draw_rect(Rect2(p.x + 3.0 * layout.s, p.y - 21.0 * layout.s,
				6.0 * layout.s, 5.0 * layout.s), Color(0.95, 0.88, 0.6))


func _draw_switch() -> void:
	var col: Color = Element.color_of(game.switch_lane())
	draw_circle(game.net.merge, 15.0 * layout.s, Color(0.10, 0.095, 0.085))
	draw_arc(game.net.merge, 15.0 * layout.s, 0.0, TAU, 28, col, 3.0)
	draw_circle(game.net.hub, 9.0 * layout.s, col)
	_label(Vector2(game.net.merge.x - 92.0 * layout.s, game.net.merge.y - 30.0 * layout.s),
		"výhybka — klepni na kolej", 13, Color(0.62, 0.59, 0.53))


func _draw_shrines() -> void:
	var r: float = game.net.shrine_r
	for lane in range(Network.LANES):
		var p: Vector2 = game.net.shrine_pos[lane]
		var col: Color = Element.color_of(lane)
		draw_circle(p, r, Color(col.r * 0.32, col.g * 0.32, col.b * 0.32, 0.9))
		draw_arc(p, r, 0.0, TAU, 32, col, 3.0)
		_glyph(lane, p, 16.0 * layout.s, col)
		_label(Vector2(p.x, p.y + 54.0 * layout.s), Element.name_of(lane), 15,
			Color(0.82, 0.79, 0.72), true, 68.0)


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
		"věž %d · vylepšení %d" % [Tower.COST, Tower.UPGRADE_COST], 13, Color(0.58, 0.55, 0.49))
	if game.phase == "build":
		_label(Vector2(x0 + step * 3.0, layout.hud_h * 0.46),
			"Příprava %.1f s" % game.build_timer, 18, Color(0.65, 0.78, 0.60))
	else:
		_label(Vector2(x0 + step * 3.0, layout.hud_h * 0.46),
			"V síti: %d" % game.enemies.size(), 18, Color(0.72, 0.70, 0.64))
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


# NAVOD. Pruh po zruseni tlacitek vyhybky ukazuje cely cas, ktery poutnik
# ma kam jit: u kazdeho zivlu je jeho runa, sipka a kolej, ktera ho zabije
# (tedy kolej jeho protikladu). Hrac tak nemusi nic zkouset - presne vi,
# kam koho poslat. Runa je u toho proto, ze barva nesmi byt jediny nosic.
func _draw_legend() -> void:
	var r: Rect2 = layout.legend
	var y: float = r.position.y + r.size.y * 0.5
	var col_w: float = r.size.x / float(Element.COUNT)
	var run_r: float = minf(9.0 * layout.s, col_w * 0.11)
	for e in range(Element.COUNT):
		var x0: float = r.position.x + col_w * float(e)
		var col: Color = Element.color_of(e)
		var opp: int = Element.opposite_of(e)
		var ocol: Color = Element.color_of(opp)
		var cy: float = y - layout.ui * 5.0
		var cx: float = x0 + col_w * 0.5 - run_r * 3.4
		_glyph(e, Vector2(cx, cy), run_r, col)
		var ax0: float = cx + run_r * 1.7
		var ax1: float = ax0 + run_r * 2.4
		draw_line(Vector2(ax0, cy), Vector2(ax1, cy), Color(0.55, 0.52, 0.46), 2.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(ax1 + 5.0, cy), Vector2(ax1, cy - 4.5), Vector2(ax1, cy + 4.5)]),
			Color(0.55, 0.52, 0.46))
		_glyph(opp, Vector2(ax1 + 5.0 + run_r * 0.9, cy), run_r, ocol)
		_label(Vector2(x0 + col_w * 0.5, y + layout.ui * 15.0),
			"%s → %s" % [Element.name_of(e), Element.name_of(opp)], 15,
			Color(0.80, 0.77, 0.70), true, col_w)


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
# tvar ji vzdy doplni, aby hra fungovala i pri poruise barvociťu.
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
