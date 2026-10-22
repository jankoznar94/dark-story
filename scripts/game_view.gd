extends Node2D

# KRESLENI A DOTYK. Hra je v `game.gd` (bez uzlu, bez vstupu) - tady se jen cte
# stav a kresli. Zadne Button uzly, zadny theme, zadny hover: plochy strojovy
# vzhled (Jan).
#
# OVLADANI: prst na displeji = napnuty luk. Bojovnik haze PRESNE OPAČNYM
# smerem, nez ukazuje prst. Vizualne je to nakreslene: cara k prstu a sipka
# opacnym smerem.

const BG := Color(0.055, 0.052, 0.062)
const TEXT := Color(0.86, 0.85, 0.82)
const DIM := Color(0.50, 0.49, 0.52)
const GOLD := Color(0.78, 0.62, 0.30)
const WARRIOR := Color(0.62, 0.44, 0.30)
const WARRIOR_DARK := Color(0.30, 0.21, 0.15)
const ENEMY := Color(0.62, 0.30, 0.28)
const ENEMY_EDGE := Color(0.24, 0.10, 0.10)
const SPEAR := Color(0.82, 0.74, 0.55)
const AIM_LINE := Color(0.55, 0.53, 0.48)
const AIM_ARROW := Color(0.86, 0.80, 0.62)
const PANEL := Color(0.095, 0.090, 0.100)
const ROW := Color(0.125, 0.118, 0.128)
const EDGE := Color(0.34, 0.33, 0.36)
const HP_GOOD := Color(0.62, 0.76, 0.56)
const HP_MID := Color(0.86, 0.76, 0.40)
const HP_LOW := Color(0.85, 0.42, 0.36)

var game := Game.new()
var layout := ScreenLayout.new()
var menu := Menu.new()

# PRSTY: index -> pozice. Drzi se pro kazdy dotek zvlast, aby druhy prst
# nesebral mireni prvnimu. Mys je jeden "prst" s indexem -1.
var _touch: Dictionary = {}
var _mouse_down: bool = false
var _mouse_pos: Vector2 = Vector2.ZERO
var _js_t: float = 0.0


func _ready() -> void:
	game.profile.load_from_disk()
	menu.web = OS.has_feature("web")
	menu.load_build_id()
	layout.update(get_viewport_rect().size)
	_apply_field()
	get_viewport().size_changed.connect(_on_resize)


func _on_resize() -> void:
	layout.update(get_viewport_rect().size)
	_apply_field()


func _apply_field() -> void:
	game.set_field(layout.field_r, layout.center, layout.arena)


func _process(dt: float) -> void:
	if menu.is_battle() and not game.is_over() and not game.paused:
		game.step(dt)
	# STAV Z PROHLIZECE (otisk buildu, hlaska k Update) se cte nekolikrat za
	# sekundu - cteni vlastnosti okna je levne, ale ne kazdy snimek.
	_js_t += dt
	if _js_t >= 0.25:
		_js_t = 0.0
		menu.pull_js_state()
	# Hra je kreslena rucne, takze se musi kazdy snimek vyzadat prekresleni.
	queue_redraw()


# =========================================================================
# VSTUP
# =========================================================================

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			_touch[t.index] = t.position
			_press(t.position)
		else:
			_touch.erase(t.index)
			_release_if_empty()
		return
	if event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		_touch[d.index] = d.position
		_drag(d.position)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_down = event.pressed
		_mouse_pos = event.position
		if event.pressed:
			_press(event.position)
		else:
			_release_if_empty()
		return
	if event is InputEventMouseMotion and _mouse_down:
		_mouse_pos = event.position
		_drag(event.position)


func _active_pos() -> Vector2:
	if not _touch.is_empty():
		return _touch[_touch.keys()[0]]
	return _mouse_pos


func _press(pos: Vector2) -> void:
	if menu.is_menu():
		for i in range(layout.menu_rects.size()):
			if (layout.menu_rects[i] as Rect2).has_point(pos) and i < Menu.ACTIONS.size():
				_open_action(String(Menu.ACTIONS[i]))
				return
		return
	if menu.is_upgrades():
		for i in range(layout.upg_rows.size()):
			if (layout.upg_rows[i] as Rect2).has_point(pos):
				if i < Upgrades.STATS.size():
					game.profile.buy_perm(String(Upgrades.STATS[i]["id"]))
				return
		if layout.upg_back.has_point(pos) or not layout.upg_panel.has_point(pos):
			menu.open_menu()
		return
	if menu.is_battle():
		if game.is_over():
			_handle_end(pos)
			return
		if layout.hud_menu.has_point(pos):
			menu.open_menu()
			return
		game.aim_at(pos)


func _drag(pos: Vector2) -> void:
	if menu.is_battle() and not game.is_over():
		game.aim_at(pos)


func _release_if_empty() -> void:
	if _touch.is_empty() and not _mouse_down:
		game.release()


func _open_action(a: String) -> void:
	if a == "battle":
		game.start_level(maxi(1, game.profile.level))
		menu.open_battle()
	elif a == "upgrades":
		layout.layout_upgrades()
		menu.open_upgrades()
	elif a == "update":
		menu.request_update()


# =========================================================================
# KRESLENI
# =========================================================================

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, layout.view), BG)
	if menu.is_menu():
		_draw_menu()
	elif menu.is_upgrades():
		_draw_upgrades()
	else:
		_draw_battle()


func _draw_menu() -> void:
	_label("THROWER", Rect2(0.0, layout.menu_title_y, layout.view.x, float(layout.title_px)),
		layout.title_px, Color(0.90, 0.87, 0.80))
	_label("barbar ve středu, oštěpy opačným směrem než prst",
		Rect2(0.0, layout.menu_title_y + float(layout.title_px) * 0.9,
			layout.view.x, float(layout.font_px) * 1.6), layout.font_px, DIM)
	for i in range(layout.menu_rects.size()):
		var r: Rect2 = layout.menu_rects[i]
		var accent: Color = GOLD if i == 0 else EDGE
		draw_rect(r, PANEL, true)
		draw_rect(r, accent, false, 3.0)
		var item: String = String(Menu.ITEMS[i])
		_label(item, Rect2(r.position.x, r.position.y + r.size.y * 0.18, r.size.x, r.size.y * 0.48),
			int(minf(float(layout.title_px) * 0.7, r.size.y * 0.36)), Color(0.90, 0.87, 0.80))
		_label(String(Menu.SUBS[i]),
			Rect2(r.position.x + 10.0, r.position.y + r.size.y * 0.66, r.size.x - 20.0, r.size.y * 0.3),
			int(maxf(11.0, r.size.y * 0.17)), DIM)
	_label(game.profile.menu_note(), Rect2(0.0, layout.menu_note_y, layout.view.x,
		float(layout.font_px) * 1.5), layout.font_px, GOLD)
	if not menu.update_note.is_empty():
		_label(menu.update_note, Rect2(0.0, layout.menu_note_y + float(layout.font_px) * 1.6,
			layout.view.x, float(layout.font_px) * 1.5),
			int(maxf(11.0, float(layout.font_px) * 0.85)), Color(0.80, 0.72, 0.50))
	_label("build %s" % menu.build_id,
		Rect2(0.0, layout.view.y - float(layout.font_px) * 2.2, layout.view.x,
			float(layout.font_px)), int(maxf(10.0, float(layout.font_px) * 0.75)), DIM)


func _draw_upgrades() -> void:
	_label("VYLEPŠENÍ", Rect2(0.0, layout.upg_title_y, layout.view.x, float(layout.title_px)),
		layout.title_px, Color(0.90, 0.87, 0.80))
	_label("body %d" % game.profile.body, Rect2(0.0, layout.upg_note_y, layout.view.x,
		float(layout.font_px) * 1.4), layout.font_px, GOLD)
	for i in range(layout.upg_rows.size()):
		var r: Rect2 = layout.upg_rows[i]
		if i >= Upgrades.STATS.size():
			break
		var s: Dictionary = Upgrades.STATS[i]
		var id: String = String(s["id"])
		var have: int = game.profile.perm_level(id)
		var maxed: bool = have >= Upgrades.perm_max(id)
		var cost: int = Upgrades.perm_cost(id, have)
		var afford: bool = (not maxed) and game.profile.body >= cost
		var edge: Color = GOLD if afford else EDGE
		draw_rect(r, ROW if afford else PANEL, true)
		draw_rect(r, edge, false, 2.0)
		var pad: float = maxf(8.0, r.size.x * 0.025)
		var name_px: int = int(clampf(r.size.y * 0.34, 11.0, 22.0))
		draw_string(ThemeDB.fallback_font, Vector2(r.position.x + pad, r.position.y + r.size.y * 0.52),
			Upgrades.label_of(id), HORIZONTAL_ALIGNMENT_LEFT,
			r.size.x * 0.52 - pad, name_px, Color(0.88, 0.86, 0.80))
		var val_txt: String = Upgrades.value_text(id, have)
		draw_string(ThemeDB.fallback_font, Vector2(r.position.x + r.size.x * 0.52, r.position.y + r.size.y * 0.52),
			val_txt, HORIZONTAL_ALIGNMENT_LEFT, r.size.x * 0.18, name_px, TEXT)
		var price: String = "MAX" if maxed else "+%d b." % cost
		draw_string(ThemeDB.fallback_font, Vector2(r.position.x + r.size.x * 0.72, r.position.y + r.size.y * 0.52),
			price, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x * 0.26 - pad, name_px,
			GOLD if afford else DIM)
	var br: Rect2 = layout.upg_back
	draw_rect(br, PANEL, true)
	draw_rect(br, EDGE, false, 2.0)
	_label("ZPĚT", br, int(clampf(br.size.y * 0.34, 12.0, 22.0)), Color(0.90, 0.87, 0.80))


func _draw_battle() -> void:
	var c: Vector2 = layout.center
	# SPODNI CARA POD BOJOVNIKEM: hranice, na ktere stoji. Neni to dostrel ani
	# mrizka - jen aby obrazovka nekoncila ve vzduchu.
	var gy: float = c.y + game.warrior_r() * 1.6
	draw_line(Vector2(0.0, gy), Vector2(layout.view.x, gy),
		Color(0.22, 0.21, 0.24), maxf(1.5, layout.view.x * 0.004))
	_draw_enemies()
	_draw_aim()
	_draw_spears()
	_draw_warrior()
	_draw_bar()
	if game.is_over():
		_draw_end()
	elif game.phase == "build":
		_label("Připrav se — %.0f" % maxf(0.0, game.build_left),
			Rect2(0.0, c.y - float(layout.font_px) * 6.0, layout.view.x,
				float(layout.font_px) * 1.6), layout.font_px, DIM)


func _draw_warrior() -> void:
	var c: Vector2 = layout.center
	var r: float = game.warrior_r()
	draw_circle(c, r, WARRIOR)
	draw_arc(c, r * 0.86, 0.0, TAU, 32, WARRIOR_DARK, maxf(2.0, r * 0.18))
	# SEKERA v ruce: krátká násada a klín. Grafika je zamerne jednoducha, jak
	# Jan rekl ("Zatím to zobrazíme graficky jen velmi jednoduše").
	var a: Vector2 = Vector2(0.6, -0.8).normalized()
	draw_line(c, c + a * r * 1.25, WARRIOR_DARK, maxf(2.0, r * 0.16))
	var tip: Vector2 = c + a * r * 1.25
	draw_line(tip - a.orthogonal() * r * 0.35, tip + a.orthogonal() * r * 0.35,
		Color(0.80, 0.78, 0.72), maxf(2.0, r * 0.20))


func _draw_enemies() -> void:
	var er: float = game.enemy_r()
	for e in game.enemies:
		var pos: Vector2 = e["pos"]
		draw_circle(pos, er, ENEMY)
		draw_arc(pos, er, 0.0, TAU, 16, ENEMY_EDGE, maxf(1.5, er * 0.28))
		var frac: float = clampf(float(e["hp"]) / maxf(1.0, float(e["max_hp"])), 0.0, 1.0)
		if frac < 0.999:
			draw_arc(pos, er * 1.55, -PI * 0.5, -PI * 0.5 + TAU * frac, 20,
				_hp_color(frac), maxf(2.0, er * 0.30))


func _draw_spears() -> void:
	var sr: float = game.spear_r()
	for s in game.spears:
		var pos: Vector2 = s["pos"]
		var dir: Vector2 = s["dir"]
		var tail: Vector2 = pos - dir * sr * 5.0
		draw_line(tail, pos, SPEAR, maxf(2.0, sr * 1.6))
		draw_circle(pos, sr * 1.1, SPEAR)


# MIREni: JEN CARA DOZADU (Jan, Oct 2026: "šipku u přední části hrdiny ...
# dáme pryč. Necháme jen tu čáru dozadu."). Cara vede od bojovnika opacnym
# smerem, nez poleti ostep - jako napnuta tetiva. Smer strelby hrac cte
# z toho, kam cara ukazuje (presne naopak).
func _draw_aim() -> void:
	if not game.aiming:
		return
	var c: Vector2 = layout.center
	var back: Vector2 = -game.aim
	var ln: float = layout.field_r * 0.85
	# CARA SE NESMI ZTRATIT ZA OKRAJEM: smerem dolu by jinak zmizela pod
	# displejem a hrac by nevidel, kam se napina. Orizne se podle mista.
	if back.y > 0.05:
		ln = minf(ln, (layout.view.y - 10.0 - c.y) / back.y)
	ln = maxf(24.0, ln)
	var endp: Vector2 = c + back * ln
	draw_line(c, endp, AIM_LINE, maxf(2.0, layout.field_r * 0.006))
	draw_circle(endp, maxf(3.0, layout.field_r * 0.012), AIM_LINE)


func _draw_bar() -> void:
	var pad: float = maxf(8.0, layout.bar_h * 0.20)
	var px: int = int(clampf(layout.bar_h * 0.36, 12.0, 22.0))
	var l1: String = "Level %d · vlna %d/%d" % [game.level, game.wave, game.WAVES_PER_LEVEL]
	draw_string(ThemeDB.fallback_font, Vector2(pad, layout.bar_h * 0.62), l1,
		HORIZONTAL_ALIGNMENT_LEFT, layout.view.x * 0.62, px, TEXT)
	var hp_txt: String = "%d / %d" % [int(ceil(game.hp)), int(game.max_hp)]
	draw_string(ThemeDB.fallback_font,
		Vector2(layout.view.x - layout.view.x * 0.30 - 10.0, layout.bar_h * 0.62), hp_txt,
		HORIZONTAL_ALIGNMENT_RIGHT, layout.view.x * 0.30, px, _hp_color(game.hp / maxf(1.0, game.max_hp)))
	var mr: Rect2 = layout.hud_menu
	draw_rect(mr, PANEL, true)
	draw_rect(mr, EDGE, false, 2.0)
	_label("MENU", mr, int(clampf(mr.size.y * 0.38, 10.0, 18.0)), Color(0.88, 0.86, 0.80))


func _draw_end() -> void:
	var won: bool = game.phase == "won"
	var title: String
	var sub: String
	var first: String
	if won:
		title = "Level %d vyhrán" % game.level
		sub = "Získáno %d bodů." % game.body_earned
		first = "DALŠÍ"
	else:
		title = "Bojovník padl"
		sub = "Dojdi na level %d znovu." % game.level
		first = "ZNOVU"
	_dialog(title, sub, first, "MENU")


func _dialog(title: String, sub: String, a: String, b: String) -> void:
	var box: Rect2 = layout.dlg_box
	draw_rect(box, Color(0.08, 0.075, 0.085), true)
	draw_rect(box, EDGE, false, 3.0)
	_label(title, Rect2(box.position.x, box.position.y + box.size.y * 0.14, box.size.x,
		box.size.y * 0.2), int(clampf(box.size.y * 0.14, 14.0, 30.0)), Color(0.92, 0.89, 0.82))
	_label(sub, Rect2(box.position.x, box.position.y + box.size.y * 0.34, box.size.x,
		box.size.y * 0.2), int(clampf(box.size.y * 0.085, 11.0, 18.0)), DIM)
	_button(layout.dlg_a, a, GOLD)
	_button(layout.dlg_b, b, EDGE)


func _button(r: Rect2, txt: String, accent: Color) -> void:
	draw_rect(r, PANEL, true)
	draw_rect(r, accent, false, 2.0)
	_label(txt, r, int(clampf(r.size.y * 0.36, 11.0, 20.0)), Color(0.90, 0.87, 0.80))


func _handle_end(pos: Vector2) -> void:
	if layout.dlg_a.has_point(pos):
		if game.phase == "won":
			game.next_level()
			menu.open_battle()
		else:
			game.start_level(game.level)
		return
	if layout.dlg_b.has_point(pos):
		menu.open_menu()


func _hp_color(frac: float) -> Color:
	if frac > 0.6:
		return HP_GOOD
	if frac > 0.3:
		return HP_MID
	return HP_LOW


func _label(s: String, r: Rect2, px: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(r.position.x, r.position.y + r.size.y * 0.72),
		s, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, px, col)
