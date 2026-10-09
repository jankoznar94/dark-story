extends Node2D

# Jedina scena hry. Vsechno se KRESLI rucne - zadne Button nody,
# zadne theme, zadne hover/focus efekty. Jeden vstupni bod, jeden hit-test.
#
# Dole je jeden pruh ovladani ve dvou skupinach:
#   STAVET  - ktery zivel chci stavet (pak tapnu na misto na koleji)
#   VYHYBKA - kam poslu dalsi poutniky
# Klavesa: vse je jen hit-test na obdelniky, proto se to na mobilu
# chova presne jako na desktopu.

const VIEW_W := 960.0
const VIEW_H := 600.0
const BAR_Y := 500.0
const BTN_Y := 526.0
const BTN_W := 78.0
const BTN_H := 54.0
const BTN_STEP := 84.0

var game: Game = null
var selected: int = Element.FIRE
var speed_button := Rect2(852.0, BTN_Y, 92.0, BTN_H)
var element_buttons: Array = []
var switch_buttons: Array = []
var toast: String = ""
var toast_t: float = 0.0
var last_log_size: int = 0

var _font: Font = null
var _shot: bool = false
var _shot_frames: int = 0


func _ready() -> void:
	_font = ThemeDB.fallback_font
	game = Game.new()
	game.setup(Rect2(40.0, 80.0, 880.0, 420.0))
	_layout_buttons()
	game.set_switch(Element.FIRE)
	if OS.get_cmdline_user_args().has("--shot"):
		_setup_shot()


# Nahledovy rezim pro kontrolu vzhledu: postavi ukazkovou sit a zmrazi hru
# v okamziku, kdy jsou poutnici na kolejich, aby snimek neukazal prazdno.
func _setup_shot() -> void:
	game.gold = 5000
	game.try_build(0, 1, Element.WATER)
	game.try_build(1, 0, Element.FIRE)
	game.try_build(1, 1, Element.FIRE)
	game.try_build(2, 2, Element.AIR)
	game.try_build(3, 0, Element.EARTH)
	game.try_build(3, 2, Element.EARTH)
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


func _layout_buttons() -> void:
	element_buttons = []
	for i in range(Element.COUNT):
		element_buttons.append(Rect2(16.0 + float(i) * BTN_STEP, BTN_Y, BTN_W, BTN_H))
	switch_buttons = []
	for i in range(Element.COUNT):
		switch_buttons.append(Rect2(372.0 + float(i) * BTN_STEP, BTN_Y, BTN_W, BTN_H))


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
			toast_t = 3.0
	if toast_t > 0.0:
		toast_t -= delta


# ---------------------------------------------------------------- vstup

func _input(event: InputEvent) -> void:
	var pos := Vector2(-1.0, -1.0)
	var press := false
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		pos = st.position
		press = st.pressed
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		pos = mb.position
		press = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	if not press:
		return
	_handle_tap(pos)
	get_viewport().set_input_as_handled()


func _handle_tap(pos: Vector2) -> void:
	if speed_button.has_point(pos):
		game.run_for(6.0)
		return
	for i in range(element_buttons.size()):
		var r: Rect2 = element_buttons[i]
		if r.has_point(pos):
			selected = i
			_say("Stavím živel %s." % Element.name_of(i))
			return
	for i in range(switch_buttons.size()):
		var r: Rect2 = switch_buttons[i]
		if r.has_point(pos):
			game.set_switch(i)
			return
	var cell: Vector2i = game.net.nearest_slot(pos)
	if cell.x >= 0:
		var existing: Tower = game.tower_at(cell.x, cell.y)
		if existing == null:
			game.try_build(cell.x, cell.y, selected)
		else:
			game.try_upgrade(cell.x, cell.y)
		return


func _say(text: String) -> void:
	toast = text
	toast_t = 3.0


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
	draw_rect(Rect2(0.0, 0.0, VIEW_W, VIEW_H), Color(0.10, 0.095, 0.085))
	draw_rect(game.net.area, Color(0.125, 0.115, 0.10))
	# Zilky many v pozadi - jen naznak, nesmi soutezit s hernimi liniemi.
	for i in range(9):
		var t: float = float(i) / 8.0
		var y: float = game.net.area.position.y + t * game.net.area.size.y
		draw_line(Vector2(game.net.area.position.x, y + 12.0),
			Vector2(game.net.area.end.x, y - 18.0), Color(0.155, 0.14, 0.12, 0.55), 1.0)


func _draw_lanes() -> void:
	for lane in range(Network.LANES):
		var col: Color = Element.color_of(lane)
		var path: PackedVector2Array = game.net.lane_path[lane]
		var faint := col
		faint.a = 0.28
		for k in range(path.size() - 1):
			draw_line(path[k], path[k + 1], faint, 9.0)
		var bright := col
		bright.a = 0.60
		for k in range(path.size() - 1):
			draw_line(path[k], path[k + 1], bright, 3.0)


func _draw_trunk() -> void:
	var a: Vector2 = game.net.trunk_start
	var b: Vector2 = game.net.merge
	draw_line(a, b, Color(0.42, 0.38, 0.32, 0.75), 9.0)
	draw_line(a, b, Color(0.58, 0.53, 0.44, 0.9), 3.0)


func _draw_slots() -> void:
	for lane in range(Network.LANES):
		var col: Color = Element.color_of(lane)
		for slot in range(game.net.slot_count()):
			var p: Vector2 = game.net.slot_world(lane, slot)
			var t: Tower = game.tower_at(lane, slot)
			if t == null:
				draw_arc(p, Network.TOWER_RADIUS, 0.0, TAU, 24,
					Color(col.r, col.g, col.b, 0.50), 2.0)
			else:
				draw_circle(p, Network.TOWER_RADIUS,
					Color(col.r * 0.40, col.g * 0.40, col.b * 0.40, 0.85))
				draw_arc(p, Network.TOWER_RADIUS, 0.0, TAU, 24, col, 2.0)


func _draw_towers() -> void:
	for item in game.towers:
		var t: Tower = item
		var p: Vector2 = game.net.slot_world(t.lane, t.slot)
		var col: Color = Element.color_of(t.element)
		draw_rect(Rect2(p.x - 13.0, p.y - 13.0, 26.0, 26.0), col)
		_glyph(t.element, p, 8.0, Color(0.07, 0.06, 0.06))
		if t.level > 1:
			draw_rect(Rect2(p.x - 9.0, p.y - 21.0, 6.0, 5.0), Color(0.95, 0.88, 0.6))
			draw_rect(Rect2(p.x + 3.0, p.y - 21.0, 6.0, 5.0), Color(0.95, 0.88, 0.6))


func _draw_switch() -> void:
	var col: Color = Element.color_of(game.switch_lane())
	draw_circle(game.net.merge, 15.0, Color(0.10, 0.095, 0.085))
	draw_arc(game.net.merge, 15.0, 0.0, TAU, 28, col, 3.0)
	draw_circle(game.net.hub, 9.0, col)
	_label(Vector2(game.net.merge.x - 60.0, game.net.merge.y - 30.0), "výhybka",
		13, Color(0.62, 0.59, 0.53))


func _draw_shrines() -> void:
	for lane in range(Network.LANES):
		var p: Vector2 = game.net.shrine_pos[lane]
		var col: Color = Element.color_of(lane)
		draw_circle(p, 30.0, Color(col.r * 0.32, col.g * 0.32, col.b * 0.32, 0.9))
		draw_arc(p, 30.0, 0.0, TAU, 32, col, 3.0)
		_glyph(lane, p, 16.0, col)
		draw_string(_font, Vector2(p.x - 34.0, p.y + 54.0), Element.name_of(lane),
			HORIZONTAL_ALIGNMENT_CENTER, 68.0, 15, Color(0.82, 0.79, 0.72))


func _draw_enemies() -> void:
	for item in game.enemies:
		var e: Enemy = item
		var p: Vector2 = _enemy_pos(e)
		var col: Color = Element.color_of(e.element)
		draw_circle(p, 13.0, Color(0.09, 0.085, 0.08))
		draw_circle(p, 11.0, col)
		_glyph(e.element, p, 7.0, Color(0.07, 0.06, 0.06))
		if e.hp_frac() < 1.0:
			draw_arc(p, 17.0, -PI * 0.5, -PI * 0.5 + TAU * e.hp_frac(), 24,
				Color(0.90, 0.85, 0.55), 3.0)


func _enemy_pos(e: Enemy) -> Vector2:
	if e.on_lane():
		return game.net.point_at(e.lane, e.s)
	return game.net.trunk_point_at(e.s)


func _draw_hud() -> void:
	draw_rect(Rect2(0.0, 0.0, VIEW_W, 72.0), Color(0.075, 0.07, 0.065))
	draw_line(Vector2(0.0, 72.0), Vector2(VIEW_W, 72.0), Color(0.28, 0.25, 0.21), 2.0)
	_label(Vector2(24.0, 32.0), "Vlna %d" % game.wave, 20, Color(0.90, 0.87, 0.80))
	_label(Vector2(24.0, 56.0), game.phase, 14, Color(0.58, 0.55, 0.49))
	_label(Vector2(180.0, 32.0), "Životy %d" % game.lives, 20,
		Color(0.85, 0.42, 0.36) if game.lives <= 4 else Color(0.90, 0.87, 0.80))
	_label(Vector2(180.0, 56.0), "z %d" % Game.START_LIVES, 14, Color(0.58, 0.55, 0.49))
	_label(Vector2(340.0, 32.0), "Zlato %d" % game.gold, 20, Color(0.88, 0.78, 0.45))
	_label(Vector2(340.0, 56.0), "věž %d · vylepšení %d" % [Tower.COST, Tower.UPGRADE_COST],
		14, Color(0.58, 0.55, 0.49))
	if game.phase == "build":
		_label(Vector2(580.0, 32.0), "Příprava %.1f s" % game.build_timer, 18, Color(0.65, 0.78, 0.60))
	else:
		_label(Vector2(580.0, 32.0), "V síti: %d" % game.enemies.size(), 18, Color(0.72, 0.70, 0.64))
	_label(Vector2(580.0, 56.0), "poutníků zbývá %d" % game.spawn_left, 14, Color(0.58, 0.55, 0.49))
	if game.phase == "lost":
		draw_rect(Rect2(270.0, 230.0, 420.0, 116.0), Color(0.13, 0.09, 0.09))
		draw_rect(Rect2(270.0, 230.0, 420.0, 116.0), Color(0.55, 0.25, 0.22), false, 3.0)
		_label(Vector2(480.0, 282.0), "SÍŤ PADLA", 30, Color(0.88, 0.46, 0.38), true)
		_label(Vector2(480.0, 322.0), "vydržels %d vln" % game.wave, 16, Color(0.75, 0.71, 0.65), true)
	if toast_t > 0.0:
		_label(Vector2(VIEW_W * 0.5, 96.0), toast, 16, Color(0.78, 0.75, 0.68), true)


func _draw_control_bar() -> void:
	draw_rect(Rect2(0.0, BAR_Y, VIEW_W, VIEW_H - BAR_Y), Color(0.075, 0.07, 0.065))
	draw_line(Vector2(0.0, BAR_Y), Vector2(VIEW_W, BAR_Y), Color(0.28, 0.25, 0.21), 2.0)
	_label(Vector2(16.0, 518.0), "STAVĚT", 13, Color(0.52, 0.49, 0.44))
	_label(Vector2(372.0, 518.0), "VÝHYBKA", 13, Color(0.52, 0.49, 0.44))

	for i in range(element_buttons.size()):
		var r: Rect2 = element_buttons[i]
		var c: Color = Element.color_of(i)
		var on: bool = i == selected
		draw_rect(r, Color(c.r, c.g, c.b, 0.30) if on else Color(0.135, 0.125, 0.11))
		draw_rect(r, c if on else Color(c.r, c.g, c.b, 0.40), false, 3.0 if on else 2.0)
		_glyph(i, Vector2(r.get_center().x, r.position.y + 18.0), 9.0, c)
		draw_string(_font, Vector2(r.position.x, r.position.y + 46.0), Element.name_of(i),
			HORIZONTAL_ALIGNMENT_CENTER, BTN_W, 12,
			Color(0.90, 0.87, 0.80) if on else Color(0.68, 0.65, 0.59))

	for i in range(switch_buttons.size()):
		var r: Rect2 = switch_buttons[i]
		var c: Color = Element.color_of(i)
		var on: bool = i == game.switch_lane()
		draw_rect(r, Color(c.r, c.g, c.b, 0.30) if on else Color(0.135, 0.125, 0.11))
		draw_rect(r, c if on else Color(c.r, c.g, c.b, 0.40), false, 3.0 if on else 2.0)
		draw_line(Vector2(r.position.x + 16.0, r.position.y + 18.0),
			Vector2(r.position.x + 40.0, r.position.y + 18.0), c, 3.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(r.position.x + 40.0, r.position.y + 12.0),
			Vector2(r.position.x + 50.0, r.position.y + 18.0),
			Vector2(r.position.x + 40.0, r.position.y + 24.0)]), c)
		draw_string(_font, Vector2(r.position.x, r.position.y + 46.0), Element.name_of(i),
			HORIZONTAL_ALIGNMENT_CENTER, BTN_W, 12,
			Color(0.90, 0.87, 0.80) if on else Color(0.68, 0.65, 0.59))

	draw_rect(speed_button, Color(0.20, 0.19, 0.17))
	draw_rect(speed_button, Color(0.38, 0.35, 0.30), false, 2.0)
	_label(speed_button.get_center() + Vector2(0.0, -8.0), "SKIP", 18, Color(0.85, 0.82, 0.76), true)
	_label(speed_button.get_center() + Vector2(0.0, 10.0), "6 s", 13, Color(0.58, 0.55, 0.49), true)


func _label(at: Vector2, text: String, size: int, col: Color, centered: bool = false) -> void:
	if centered:
		draw_string(_font, Vector2(at.x - 210.0, at.y), text, HORIZONTAL_ALIGNMENT_CENTER, 420.0, size, col)
	else:
		draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


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
