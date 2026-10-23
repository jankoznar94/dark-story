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
# HRADBA: kamen, ploche a ztlumene. Zadny svetly nater, aby neodvadela
# pozornost od nepratel.
const WALL := Color(0.315, 0.295, 0.270)
const WALL_DARK := Color(0.180, 0.170, 0.160)
const WALL_EDGE := Color(0.430, 0.400, 0.355)

var game := Game.new()
var layout := ScreenLayout.new()
var menu := Menu.new()

# PRSTY: index -> pozice. Drzi se pro kazdy dotek zvlast, aby druhy prst
# nesebral mireni prvnimu. Mys je jeden "prst" s indexem -1.
var _touch: Dictionary = {}
var _mouse_down: bool = false
var _mouse_pos: Vector2 = Vector2.ZERO
# MYS JE JEDEN "PRST" s indexem -1 (dotyk ma sva cisla).
const MOUSE_PTR := -1
var _js_t: float = 0.0
# Cas posledniho doteku (ms). Brani dvojimu zpracovani doteku jako mysi.
var _touch_ms: int = -100000
# OZVA klepnuti: kratky krouzek v miste doteku. Je to zaroven diagnostika -
# kdyz klepnuti na tlacitko nezanecha krouzek, dotek se do hry vubec nedostal.
var _tap_fx: Array = []
# PORTRETY NEPRATEL: nactou se jednou pri startu. Kruhove PNG (pruhledne okoli)
# pripravi tools/prepare_monsters.py z portretu Dungeon Recall.
var _tex: Dictionary = {}


func _ready() -> void:
	game.profile.load_from_disk()
	menu.web = OS.has_feature("web")
	menu.load_build_id()
	layout.update(get_viewport_rect().size)
	_apply_field()
	_load_textures()
	get_viewport().size_changed.connect(_on_resize)


func _on_resize() -> void:
	layout.update(get_viewport_rect().size)
	_apply_field()


func _apply_field() -> void:
	game.set_field(layout.field_r, layout.center, layout.arena)


func _load_textures() -> void:
	_tex.clear()
	for t in Game.ENEMY_TYPES:
		var path: String = "res://assets/monsters/%s.png" % String(t["img"])
		if ResourceLoader.exists(path):
			_tex[String(t["id"])] = load(path)


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
	for i in range(_tap_fx.size() - 1, -1, -1):
		_tap_fx[i]["t"] = float(_tap_fx[i]["t"]) + dt
		if float(_tap_fx[i]["t"]) > 0.30:
			_tap_fx.remove_at(i)
	queue_redraw()


# =========================================================================
# VSTUP
# =========================================================================

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		_touch_ms = Time.get_ticks_msec()
		if t.pressed:
			_touch[t.index] = t.position
			_press(t.position, t.index)
		else:
			_touch.erase(t.index)
			_release_ptr(t.index)
			_release_if_empty()
		return
	if event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		_touch[d.index] = d.position
		_drag(d.position, d.index)
		return
	# JEDEN DOTYK = JEDNO KLEPNUTI. Prohlizec posle dotek a k tomu jeste
	# emulovanou mys; bez tehle pojistky se kazde klepnuti vykona dvakrat -
	# obrazovka VYLEPSENI se otevrela a hned zase zavrela. Tyká se to jen
	# mysi, dotyk a tazeni prstem jdou vzdy.
	if Time.get_ticks_msec() - _touch_ms < 500:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_down = event.pressed
		_mouse_pos = event.position
		if event.pressed:
			_press(event.position, MOUSE_PTR)
		else:
			_release_ptr(MOUSE_PTR)
			_release_if_empty()
		return
	if event is InputEventMouseMotion and _mouse_down:
		_mouse_pos = event.position
		_drag(event.position, MOUSE_PTR)


# =========================================================================
# VSTUP
# =========================================================================

func _press(pos: Vector2, id: int) -> void:
	_tap_fx.append({"pos": pos, "t": 0.0})
	if menu.is_menu():
		# POTVRZENI RESETU JE MODAL: dokud stoji, tlacitka menu nefunguji.
		if menu.confirm_reset:
			if layout.dlg_a.has_point(pos):
				game.profile.reset()
				game.start_level(1)
				menu.cancel_reset()
				return
			# ZPET, nebo klepnuti mimo dialog: nic se nemaze.
			menu.cancel_reset()
			return
		# TOLERANCE PRO PRST: klepnuti nemusi padnout presne do obdelniku.
		# U velkych tlacitek to nic nezkazi a na telefonu to zachrani minuti
		# o par pixelu (hlavne u spodniho okraje).
		for i in range(layout.menu_rects.size()):
			if (layout.menu_rects[i] as Rect2).grow(12.0).has_point(pos) and i < Menu.ACTIONS.size():
				_open_action(String(Menu.ACTIONS[i]))
				return
		return
	if menu.is_upgrades():
		for i in range(layout.upg_rows.size()):
			if (layout.upg_rows[i] as Rect2).grow(8.0).has_point(pos):
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
			game.release()
			menu.open_menu()
			return
		# PRST PRIMO VE HRISTI: smer = prst, vzdalenost = rozptyl.
		game.aim_at(pos)


func _drag(pos: Vector2, _id: int) -> void:
	if menu.is_battle() and not game.is_over():
		game.aim_at(pos)


func _release_ptr(_id: int) -> void:
	pass


func _release_if_empty() -> void:
	if _touch.is_empty() and not _mouse_down:
		game.release()


func _open_action(a: String) -> void:
	if a == "battle":
		game.release()
		game.start_level(maxi(1, game.profile.level))
		menu.open_battle()
	elif a == "upgrades":
		layout.layout_upgrades()
		menu.open_upgrades()
	elif a == "update":
		menu.request_update()
	elif a == "reset":
		# NEVRATNÉ: nejdriv se zeptat, mazat az po potvrzeni.
		menu.ask_reset()


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
	for fx in _tap_fx:
		var k: float = clampf(float(fx["t"]) / 0.30, 0.0, 1.0)
		var c: Vector2 = fx["pos"]
		draw_arc(c, 10.0 * layout.ui_scale + 22.0 * layout.ui_scale * k, 0.0, TAU, 24,
			Color(0.82, 0.70, 0.42, 0.55 * (1.0 - k)), maxf(1.5, 2.5 * layout.ui_scale))


func _draw_menu() -> void:
	_label("THROWER", Rect2(0.0, layout.menu_title_y, layout.view.x, float(layout.title_px)),
		layout.title_px, Color(0.90, 0.87, 0.80))
	_label("barbar ve středu, oštěpy opačným směrem než prst",
		Rect2(0.0, layout.menu_title_y + float(layout.title_px) * 0.9,
			layout.view.x, float(layout.font_px) * 1.6), layout.font_px, DIM)
	for i in range(layout.menu_rects.size()):
		var r: Rect2 = layout.menu_rects[i]
		var act: String = String(Menu.ACTIONS[i])
		var accent: Color = GOLD if act == "battle" else EDGE
		if act == "reset":
			# NEVRATNA AKCE: rezavy lem. Jen lem - porad plochy strojovy vzhled.
			accent = Color(0.60, 0.34, 0.30)
		draw_rect(r, PANEL, true)
		draw_rect(r, accent, false, 3.0)
		var item: String = String(Menu.ITEMS[i])
		_label(item, Rect2(r.position.x, r.position.y + r.size.y * 0.08, r.size.x, r.size.y * 0.58),
			int(minf(float(layout.title_px) * 0.82, r.size.y * 0.56)), Color(0.90, 0.87, 0.80))
		_label(String(Menu.SUBS[i]),
			Rect2(r.position.x + 10.0, r.position.y + r.size.y * 0.63, r.size.x - 20.0, r.size.y * 0.35),
			int(maxf(18.0, r.size.y * 0.27)), DIM)
	_label("build %s" % menu.build_id, Rect2(0.0, layout.menu_title_y + float(layout.title_px) * 0.9
		+ float(layout.font_px) * 1.9, layout.view.x, float(layout.font_px) * 1.6),
		int(maxf(14.0, float(layout.font_px) * 0.85)), DIM)
	_label(game.profile.menu_note(), Rect2(0.0, layout.menu_note_y, layout.view.x,
		float(layout.font_px) * 1.5), layout.font_px, GOLD)
	if not menu.update_note.is_empty():
		_label(menu.update_note, Rect2(0.0, layout.menu_note_y + float(layout.font_px) * 1.6,
			layout.view.x, float(layout.font_px) * 1.5),
			int(maxf(11.0, float(layout.font_px) * 0.85)), Color(0.80, 0.72, 0.50))
	# POTVRZENI RESETU: prekryje menu, dokud hrac neodpovi. Klepnuti mimo
	# dialog se bere jako ZPET (viz _press) - omylem se nic nesmaze.
	if menu.confirm_reset:
		draw_rect(Rect2(Vector2.ZERO, layout.view), Color(0.02, 0.02, 0.025, 0.72), true)
		_dialog("Vynulovat postup?",
			"Smaže body, vylepšení i levely.",
			"VYNULOVAT", "ZPĚT")


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
		var name_px: int = int(clampf(r.size.y * 0.40, 13.0, 26.0))
		name_px = _fit_px(Upgrades.label_of(id), r.size.x * 0.50 - pad, name_px)
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
	_label("ZPĚT", br, int(clampf(br.size.y * 0.42, 14.0, 26.0)), Color(0.90, 0.87, 0.80))


func _draw_battle() -> void:
	_draw_enemies()
	# HRADBA JE PRED BARBAREM, ale ostepy i mireni kreslime PRES ni: barbar
	# haze pres ni, takze musi byt videt, kam leti.
	_draw_wall()
	_draw_aim()
	_draw_spears()
	_draw_shots()
	_draw_warrior()
	_draw_health()
	_draw_bar()
	if game.is_over():
		_draw_end()
	elif game.phase == "build":
		_label("Připrav se — %.0f" % maxf(0.0, game.build_left),
			Rect2(0.0, layout.center.y - float(layout.font_px) * 6.0, layout.view.x,
				float(layout.font_px) * 1.6), layout.font_px, DIM)


func _draw_wall() -> void:
	var wy: float = game.wall_top()
	var h: float = maxf(10.0, layout.field_r * 0.062)
	var x0: float = 0.0
	var x1: float = layout.view.x
	if game.wall_hp <= 0.0:
		# ZBOURANA HRADBA: jen nizke zbytky kamenu. Hrac na prvni pohled vidi,
		# ze uz ho nic nekryje.
		var sh: float = h * 0.34
		draw_rect(Rect2(x0, wy + h - sh, x1 - x0, sh), WALL_DARK, true)
		var bw2: float = maxf(16.0, layout.field_r * 0.16)
		var bx2: float = x0
		var i2: int = 0
		while bx2 < x1:
			var hh: float = sh * (0.55 + 0.45 * float((i2 * 7) % 3) * 0.5)
			draw_rect(Rect2(bx2, wy + h - hh, bw2 * 0.55, hh), WALL, true)
			bx2 += bw2
			i2 += 1
		return
	var flash: float = clampf(game.wall_flash / 0.30, 0.0, 1.0)
	var base: Color = WALL.lerp(WALL_EDGE, 0.5 * flash)
	draw_rect(Rect2(x0, wy, x1 - x0, h), base, true)
	# SPARY: dve rady kamenu, horni posunuta o pul bloku. Ploche, bez textur.
	var rowh: float = h * 0.5
	var bw: float = maxf(18.0, layout.field_r * 0.20)
	var lw: float = maxf(1.0, h * 0.10)
	draw_line(Vector2(x0, wy + rowh), Vector2(x1, wy + rowh), WALL_DARK, lw)
	var row: int = 0
	while row < 2:
		var off: float = 0.0 if row == 0 else bw * 0.5
		var bx: float = x0 - off
		while bx < x1:
			draw_line(Vector2(bx, wy + rowh * float(row)),
				Vector2(bx, wy + rowh * float(row + 1)), WALL_DARK, lw)
			bx += bw
		row += 1
	# HORNI HRANA: jedina svetlejsi cara, aby hradba mela tvar.
	draw_line(Vector2(x0, wy), Vector2(x1, wy), WALL_EDGE, maxf(2.0, h * 0.14))
	# STAV HRADBY: tenky pruh POD ni (mezi hradbou a Barbarem), aby nelezel
	# nepratelum na nohou a aby hrac videl, kolik jeste vydrzi.
	var frac: float = game.wall_frac()
	var ph: float = maxf(4.0, h * 0.22)
	var m: float = layout.view.x * 0.06
	var bar := Rect2(m, wy + h + ph * 0.9, layout.view.x - m * 2.0, ph)
	draw_rect(bar, Color(0.09, 0.085, 0.095, 0.85), true)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, ph)), _hp_color(frac), true)
	draw_rect(bar, EDGE, false, maxf(1.0, ph * 0.16))


func _draw_warrior() -> void:
	var c: Vector2 = layout.center
	var r: float = game.warrior_r()
	# BARBAR SE OTACI SE SMEREM STRELEY (Jan, Oct 2026: "Barbar se musí otáčet
	# s tím jak se točí směr střelby. Nesmí jen staticky stát."). Kresli se
	# v lokalnich souradnicich, kde "-y" je smer strelby; otoceni ridi `aim`.
	var rot: float = game.aim.angle() + PI * 0.5
	draw_set_transform(c, rot, Vector2.ONE)
	draw_circle(Vector2.ZERO, r, WARRIOR)
	draw_arc(Vector2.ZERO, r * 0.93, 0.0, TAU, 36, WARRIOR_DARK, maxf(2.0, r * 0.10))
	# RAMENO s ostepem dopredu: hrot je to, co hrac sleduje, takze musi byt
	# presne ve smeru letu.
	var hand: Vector2 = Vector2(0.0, -r * 0.62)
	draw_line(Vector2(0.0, -r * 0.10), hand, WARRIOR_DARK, maxf(3.0, r * 0.26))
	var tip: Vector2 = hand + Vector2(0.0, -r * 0.95)
	draw_line(hand - Vector2(0.0, r * 0.10), tip, SPEAR, maxf(2.5, r * 0.14))
	# Hrot ostepu: trojuhelnik (plny, bez glow).
	var w: float = r * 0.20
	draw_colored_polygon(PackedVector2Array([
		tip + Vector2(0.0, -r * 0.16),
		tip + Vector2(-w, r * 0.04),
		tip + Vector2(w, r * 0.04),
	]), Color(0.86, 0.82, 0.66))
	# HLAVA ve smeru pohledu.
	draw_circle(Vector2(0.0, -r * 0.30), r * 0.26, Color(0.70, 0.52, 0.36))
	draw_arc(Vector2(0.0, -r * 0.30), r * 0.26, 0.0, TAU, 20, WARRIOR_DARK, maxf(1.5, r * 0.07))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_enemies() -> void:
	for e in game.enemies:
		var pos: Vector2 = e["pos"]
		var er: float = game.radius_of(e)
		var kind: String = String(e.get("kind", "nomad"))
		var edge: Color = _kind_edge(kind)
		# KRUH: obrazek je jiz predkruhovany s pruhlednym okolim (tools/
		# prepare_monsters.py), takze nikde neni cerny ctverec. Pod nim je jen
		# tenky lem, ktery drzi tvar i kdyz obrazek chybi.
		draw_circle(pos, er, Color(0.085, 0.078, 0.090))
		var tex: Texture2D = _tex.get(kind, null)
		if tex != null:
			draw_texture_rect(tex, Rect2(pos - Vector2(er, er), Vector2(er, er) * 2.0), false)
		else:
			draw_circle(pos, er * 0.94, ENEMY)
		draw_arc(pos, er * 0.97, 0.0, TAU, 28, edge, maxf(1.5, er * 0.10))
		# ZIVOTY: oblouk kolem hlavy, ne cislo - hrac vidi "kolik jeste vydrzi".
		var frac: float = clampf(float(e["hp"]) / maxf(1.0, float(e["max_hp"])), 0.0, 1.0)
		if frac < 0.999:
			draw_arc(pos, er * 1.16, -PI * 0.5, -PI * 0.5 + TAU * frac, 24,
				_hp_color(frac), maxf(2.0, er * 0.22))
		# NABIJENI STRELCE: tesne pred vystrelem se nad hlavou rozsviti tecka.
		# Je to jen plocha, zadny glow - hrac ma cas uskocit ostepem.
		if bool(e.get("ranged", false)) and float(e.get("shot_left", 9.0)) < 0.5:
			draw_circle(pos + Vector2(0.0, -er * 1.32), er * 0.16, edge)


# BARVA DRUHU: jen odstin lemu a strel, zadne neony. Kazdy druh ma byt poznat
# perifernim videnim, ale stale to musi byt strojova, ztlumena paleta.
func _kind_edge(kind: String) -> Color:
	match kind:
		"cobra":
			return Color(0.55, 0.60, 0.32)
		"nomad":
			return Color(0.66, 0.54, 0.36)
		"treant":
			return Color(0.44, 0.52, 0.33)
		"kolos":
			return Color(0.62, 0.48, 0.30)
		"ghost":
			return Color(0.52, 0.62, 0.70)
		"pyro":
			return Color(0.74, 0.44, 0.28)
	return Color(0.62, 0.30, 0.28)


func _draw_shots() -> void:
	for s in game.enemy_shots:
		var pos: Vector2 = s["pos"]
		var dir: Vector2 = s["dir"]
		var r: float = float(s["r"])
		var kind: String = String(s.get("kind", "ghost"))
		var col: Color = _kind_edge(kind)
		# STOPA: dve kratke useky, aby bylo videt, odkud strela leti.
		for i in range(2):
			var t0: Vector2 = pos - dir * r * (5.0 + 3.0 * float(i))
			var t1: Vector2 = pos - dir * r * (2.0 + 3.0 * float(i))
			draw_line(t0, t1, Color(col.r, col.g, col.b, 0.34 - 0.14 * float(i)),
				maxf(1.5, r * 1.2))
		draw_circle(pos, r, col)
		draw_circle(pos, r * 0.45, Color(0.95, 0.90, 0.78))


func _draw_spears() -> void:
	var sr: float = game.spear_r()
	var ln: float = maxf(26.0, game.field_r * 0.11)
	for s in game.spears:
		var pos: Vector2 = s["pos"]
		var dir: Vector2 = s["dir"]
		var side: Vector2 = dir.orthogonal()
		var tail: Vector2 = pos - dir * ln
		# STOPA: tri kratke useky za ostepem, kazdy bledsi. Je to jen plocha s
		# nizkou pruhlednosti - zadny glow, ktery Janovi vadi.
		for i in range(3):
			var t0: Vector2 = tail - dir * (ln * 0.55 * float(i + 1))
			var t1: Vector2 = tail - dir * (ln * 0.55 * float(i))
			draw_line(t0, t1, Color(SPEAR.r, SPEAR.g, SPEAR.b, 0.30 - 0.09 * float(i)),
				maxf(1.5, sr * (1.5 - 0.35 * float(i))))
		# NASADA: tlustsi, tmavsi drevo.
		draw_line(tail, pos - dir * ln * 0.20, Color(0.62, 0.49, 0.32), maxf(3.0, sr * 2.0))
		# OMOTAVKA u hrotu - jedina drobnost, ale ostep pak vypada jako
		# vyrobek, ne jako cara.
		var bind: Vector2 = pos - dir * ln * 0.34
		draw_line(bind - side * sr * 1.7, bind + side * sr * 1.7,
			Color(0.42, 0.36, 0.26), maxf(2.0, sr * 1.0))
		# HROT: svetly klinek, presne ve smeru letu.
		var hw: float = sr * 2.3
		draw_colored_polygon(PackedVector2Array([
			pos + dir * ln * 0.10,
			pos - dir * ln * 0.17 + side * hw,
			pos - dir * ln * 0.17 - side * hw,
		]), Color(0.90, 0.88, 0.78))


# MIREni: PRST UKAZUJE Smer HODU, takze cara vede od bojovnika DOPREDU - presne
# tam, kam poleti ostep. Cara jde az na okraj displeje (i nahoru pod horni pruh),
# aby hrac videl smer mireni i tehdy, kdyz stoji prst uplne na hrane obrazovky.
# Je tenka a bez hrotu, aby neprekazela ve vyhledu.
func _draw_aim() -> void:
	if not game.aiming:
		return
	var c: Vector2 = layout.center
	var fwd: Vector2 = game.aim
	var m: float = maxf(6.0, layout.field_r * 0.02)
	var lo := Vector2(m, layout.bar_h + m)
	var hi := layout.view - Vector2(m, m)
	var t: float = INF
	if fwd.x > 0.0001:
		t = minf(t, (hi.x - c.x) / fwd.x)
	elif fwd.x < -0.0001:
		t = minf(t, (lo.x - c.x) / fwd.x)
	if fwd.y > 0.0001:
		t = minf(t, (hi.y - c.y) / fwd.y)
	elif fwd.y < -0.0001:
		t = minf(t, (lo.y - c.y) / fwd.y)
	if not is_finite(t) or t <= 0.0:
		t = layout.field_r
	var endp: Vector2 = c + fwd * t
	draw_line(c, endp, AIM_LINE, maxf(1.5, layout.field_r * 0.004))
	draw_circle(endp, maxf(2.5, layout.field_r * 0.010), AIM_LINE)
	# ROZPTYL JE VIDET: u vicenasobne strelby se kresli krajni drahy ostepu.
	# Tenke a ztlumene - hrac musi videt, jak si prstem vzdalenym od barbara
	# rozptyl zuzuje, ale nesmi mu to zavazet ve vyhledu.
	if game.shots() > 1:
		var half: float = Game.SPREAD * game.spread_scale * 0.5
		var faint := Color(AIM_LINE.r, AIM_LINE.g, AIM_LINE.b, 0.62)
		var w: float = maxf(1.2, layout.field_r * 0.0035)
		for s in [-1.0, 1.0]:
			draw_line(c, c + fwd.rotated(s * half) * t, faint, w)


func _draw_health() -> void:
	var c: Vector2 = layout.center
	var r: float = game.warrior_r()
	var frac: float = clampf(game.hp / maxf(1.0, game.max_hp), 0.0, 1.0)
	var w: float = r * 3.2
	var h: float = maxf(8.0, r * 0.26)
	# ZIVOTY NAD HLAVOU (Jan, Oct 2026: barbar je u spodni hrany, pod nim uz
	# zadny pruh neni - pruh by se orezal).
	var bar := Rect2(c.x - w * 0.5, c.y - r * 1.95 - h, w, h)
	draw_rect(bar, Color(0.09, 0.085, 0.095), true)
	draw_rect(Rect2(bar.position, Vector2(w * frac, h)), _hp_color(frac), true)
	draw_rect(bar, EDGE, false, maxf(1.5, h * 0.22))
	# ZASAH: cerveny obrys kolem bojovnika a "-X" nad hlavou. Hrac musi videt,
	# ze prisel o zivoty - cislo v hornim pruhu je daleko a snadno se prehledne.
	if game.hit_flash > 0.0:
		var k: float = clampf(game.hit_flash / 0.45, 0.0, 1.0)
		draw_arc(c, r * 1.10, 0.0, TAU, 40, Color(0.88, 0.32, 0.26, 0.95 * k),
			maxf(3.0, r * 0.14))
		_label("-%d" % int(round(game.hit_amount)),
			Rect2(c.x - r * 1.5, c.y - r * 2.4, r * 3.0, float(layout.font_px) * 1.5),
			int(clampf(r * 0.55, 13.0, 30.0)), Color(0.90, 0.40, 0.32, 0.45 + 0.55 * k))
		draw_rect(Rect2(Vector2(1.0, 1.0), layout.view - Vector2(2.0, 2.0)),
			Color(0.80, 0.24, 0.20, 0.30 * k), false, 8.0)


func _draw_bar() -> void:
	var pad: float = maxf(8.0, layout.bar_h * 0.20)
	var px: int = int(clampf(layout.bar_h * 0.42, 14.0, 26.0))
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
	_label("MENU", mr, int(clampf(mr.size.y * 0.44, 12.0, 22.0)), Color(0.88, 0.86, 0.80))


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
		box.size.y * 0.22), int(clampf(box.size.y * 0.17, 16.0, 34.0)), Color(0.92, 0.89, 0.82))
	_label(sub, Rect2(box.position.x, box.position.y + box.size.y * 0.34, box.size.x,
		box.size.y * 0.22), int(clampf(box.size.y * 0.105, 13.0, 22.0)), DIM)
	_button(layout.dlg_a, a, GOLD)
	_button(layout.dlg_b, b, EDGE)


func _button(r: Rect2, txt: String, accent: Color) -> void:
	draw_rect(r, PANEL, true)
	draw_rect(r, accent, false, 2.0)
	_label(txt, r, int(clampf(r.size.y * 0.42, 13.0, 24.0)), Color(0.90, 0.87, 0.80))


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


# TEXT, KTERY SE DO RADKU VEJDE: na sirokem displeji jsou radky ve dvou
# sloupcich a dlouhy nazev by prelezl do ceny. Zmensuje se jen tenhle text a
# jen kdyz je potreba - jinde zustava velke pismo.
func _fit_px(s: String, max_w: float, px: int) -> int:
	var f: Font = ThemeDB.fallback_font
	var p: int = px
	while p > 10 and f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, p).x > max_w:
		p -= 1
	return p


func _label(s: String, r: Rect2, px: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(r.position.x, r.position.y + r.size.y * 0.72),
		s, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, px, col)
