extends SceneTree

# TEST ROZVRZENI: spawnovaci kruh saha na vrsek a spodek herniho pruhu, kruh
# dostrelu se vejde mezi boky, tlacitka palety jdou zmacknout prstem, PANELY
# S UPGRADY (bitva i menu) se vejdou na displej a hra zustava HRATELNA.
# Vystup: LAYOUT_ALL_PASS=true / false
#
# Neresi se jen "nic se neprekryva": u kazdeho rozliseni se overuje, ze se
# kruh dostrelu vejde do plochy, ze panel nezakryva paletu a ze poutnik kazde
# barvy z palety stihne umrit v dostrelu zakladni veze (jinak je hra
# nehratelna, i kdyz vypada dobre).

const RESOLUTIONS := [
	Vector2(390, 844),   # iPhone 14 na vysku (cilova obrazovka)
	Vector2(360, 800),   # nejmensi bezny Android na vysku
	Vector2(430, 932),   # iPhone 15 Pro Max na vysku
	Vector2(800, 1280),  # tablet na vysku
	Vector2(932, 430),   # telefon na sirku (jen se nesmi rozbit)
	Vector2(1280, 720),  # desktop
]

var fails: Array = []
var checks: int = 0


func _init() -> void:
	Upgrades.STATS.size()
	Profile.allow_save = false
	_run("neznama velikost okna nic nerozbije", _test_zero_size)
	_run("spawnovaci kruh se nemaluje", _test_spawn_ring_not_drawn)
	_run("strela je tecka nad zamerovanim", _test_shots_are_dots)
	_run("paleta je puntik, ne tvar", _test_palette_is_dot)
	_run("kruh dostrelu ma barvu veze", _test_range_is_colored)
	for r in RESOLUTIONS:
		_run("rozliseni %dx%d" % [int(r.x), int(r.y)], _test_resolution.bind(r))
	print("checks=%d fails=%d" % [checks, fails.size()])
	print("LAYOUT_ALL_PASS=%s" % ("true" if fails.is_empty() else "false"))
	quit()


func _run(name: String, fn: Callable) -> void:
	var before: int = fails.size()
	fn.call()
	if fails.size() == before:
		print("  ok   %s" % name)


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails.append(msg)
		print("       FAIL: %s" % msg)


func _src() -> String:
	var f := FileAccess.open("res://scripts/game_view.gd", FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


# SPAWNOVACI KRUH SE NEMALUJE. Hlida se MISTO VOLANI ve zdroji obrazovky.
func _test_spawn_ring_not_drawn() -> void:
	var src: String = _src()
	_check(src != "", "nectu game_view.gd")
	_check(not src.contains("draw_arc(layout.center, layout.field_r"),
		"spawnovaci kruh se kresli, i kdyz ma byt pomyslny")
	_check(src.contains("game.range_px()"),
		"kruh dostrelu se nekresli (je to jedina geometrie, kterou hrac vidi)")


# STRELA JE TECKA S OBRYSEM A KRESLI SE NAD VSIM V POLI. Poradi v `_draw` je
# zavazne - prehozeni dvou radku vypada v kodu jako kosmetika a na obrazovce
# je to nevidet jen tak.
func _test_shots_are_dots() -> void:
	var src: String = _src()
	_check(src.contains("for s in game.shots"), "strely se vubec nekresli")
	_check(src.contains("game.shot_r()"), "strela se nekresli jako tecka")
	_check(src.contains("game.shot_rim_r()"), "strela nema tmavy obrys - ztrati se")
	_check(src.contains("draw_line(layout.center, p.pos, BEAM, 2.0)"),
		"paprsek (zamerovani) zmizel - hrac nevidi, kam vez miri")
	var i_beam: int = src.find("draw_line(layout.center, p.pos, BEAM")
	var i_tower: int = src.find("\n\t_draw_tower()")
	var i_shots: int = src.find("\n\t_draw_shots()")
	_check(i_beam >= 0 and i_tower >= 0 and i_shots >= 0,
		"kresleni strel neni hned za vezi (v poli se nevi, co je nad cim)")
	_check(i_beam < i_tower and i_tower < i_shots,
		"strely se kresli driv nez paprsek/vez - nejsou nad zamerovanim")


# PALETA JE PLNÝ PUNTÍK S BORDEREM (Jan: "Žádné tvary").
func _test_palette_is_dot() -> void:
	var src: String = _src()
	var start: int = src.find("func _draw_palette")
	_check(start >= 0, "kresleni palety vubec neexistuje")
	if start < 0:
		return
	var end: int = src.find("\nfunc ", start + 1)
	var body: String = src.substr(start, (end - start) if end > start else src.length() - start)
	_check(body.contains("draw_circle("), "paleta neni plny puntik (chybi draw_circle)")
	_check(not body.contains("_shape("), "paleta kresli tvary, i kdyz ma byt jen puntik")


# KRUH DOSTRELU MA BARVU ZVOLENE BARVY VEZE.
func _test_range_is_colored() -> void:
	var src: String = _src()
	_check(src.contains("_range_color()"), "kruh dostrelu nema barvu veze (chybi _range_color())")
	var start: int = src.find("func _range_color")
	var end: int = src.find("\nfunc ", start + 1)
	var body: String = src.substr(start, (end - start) if end > start else 40)
	_check(body.contains("Hue.color_of(game.tower.hue)"), "barva kruhu neni barva veze")


func _test_zero_size() -> void:
	var l := ScreenLayout.new()
	l.update(Vector2.ZERO)
	_check(l.arena.size.x >= 0.0 and l.arena.size.y >= 0.0, "nulova velikost dela zaporny obdelnik")
	_check(l.hud_menu.size.x >= 0.0 and l.hud_upgrades.size.x >= 0.0, "nulova velikost dela zaporne tlacitko")
	_check(l.field_r == 0.0, "nulova velikost okna dela plochu")
	_check(l.layout_palette(5).is_empty(), "nulova velikost okna dela tlacitka palety")
	_check(l.layout_menu(4).is_empty(), "nulova velikost okna dela tlacitka menu")
	_check(l.shop_panel.size.x >= 0.0 and l.upg_panel.size.x >= 0.0
		and l.dlg_box.size.x >= 0.0, "nulova velikost okna dela zaporne panely")
	_check(l.shop_tabs.is_empty() and l.upg_tabs.is_empty(), "nulova velikost okna dela taby")


func _test_resolution(v: Vector2) -> void:
	var l := ScreenLayout.new()
	l.update(v)
	var tag: String = "%dx%d" % [int(v.x), int(v.y)]

	# 1) SPAWNOVACI KRUH: dotyka se okraju herniho pruhu; na vysku je vetsi
	# nez displej (poutnici vchazeji z boku).
	_check(absf((l.center.y - l.field_r) - l.arena.position.y) < 0.5,
		"%s: spawnovaci kruh nedosahuje na vrsek herniho pruhu (odchylka %.1f px)"
		% [tag, (l.center.y - l.field_r) - l.arena.position.y])
	_check(absf((l.center.y + l.field_r) - l.arena.end.y) < 0.5,
		"%s: spawnovaci kruh nedosahuje na spodek herniho pruhu" % tag)
	if v.y > v.x:
		_check(l.center.x - l.field_r <= 0.0 and l.center.x + l.field_r >= v.x - 0.5,
			"%s: spawnovaci kruh neni vetsi nez displej (boky maji vest mimo obraz)" % tag)
	else:
		_check(l.field_r <= l.arena.size.x * 0.5 + 0.5, "%s: na sirku spawnovaci kruh preleza displej" % tag)

	# 2) POUTNIK JE CITELNY a vsechno se pocita Z MERITKA (UNIT_SHRINK).
	_check(l.pilgrim_r >= 6.0, "%s: poutnik ma polomer %.1f px" % [tag, l.pilgrim_r])
	_check(l.tower_r >= 12.0, "%s: vez je prilis mala (%.1f px)" % [tag, l.tower_r])
	var short_side: float = minf(l.arena.size.x, l.arena.size.y)
	var want_unit: float = (short_side * 0.5 - short_side * ScreenLayout.MARGIN_FRAC) * ScreenLayout.UNIT_SHRINK
	_check(absf(l.unit_r - want_unit) < 0.5,
		"%s: meritko kresleni neni zmensený vepsany kruh (%.1f, ma byt %.1f)" % [tag, l.unit_r, want_unit])
	var gz := Game.new()
	gz.set_field(l.field_r, l.unit_r, l.center)
	_check(is_equal_approx(gz.tower_r, l.tower_r),
		"%s: hra ma jiny polomer veze nez rozvrzeni (%.2f vs %.2f)" % [tag, gz.tower_r, l.tower_r])
	if tag == "390x844":
		_check(absf(l.tower_r - 18.7) < 0.3, "na 390x844 ma vez %.1f px (ma byt 18,7)" % l.tower_r)
		_check(absf(l.pilgrim_r - 7.79) < 0.3, "na 390x844 ma poutnik %.2f px (ma byt 7,8)" % l.pilgrim_r)

	# 2b) DOSTREL PRVNIHO STUPNE SE VEJDE MEZI BOKY: zaklad, ktery dosahne na
	# boky, vypada jako "vidim celou plochu" a upgrade uz nema kam jit.
	var g1 := Game.new()
	g1.set_field(l.field_r, l.unit_r, l.center)
	var r1: float = g1.range_px()
	_check(l.center.x - r1 >= 8.0 and l.center.x + r1 <= v.x - 8.0,
		"%s: zakladni dostrel (%.0f px) dosahuje na bok displeje - neni kam upgradovat" % [tag, r1])
	_check(r1 > l.tower_r * 2.0, "%s: zakladni dostrel je skoro u veze (%.0f px)" % [tag, r1])
	g1.profile.perm["ar"] = 6
	g1.temp["ar"] = 20
	var rmax: float = g1.range_px()
	_check(rmax >= r1 * 1.5, "%s: upgrade prida jen kousek dostrelu (%.0f -> %.0f px)" % [tag, r1, rmax])
	_check(rmax < l.field_r * 0.95, "%s: dostrel na maximu pokryva celou plochu" % tag)

	# 3) HORNI PRUH: dve tlacitka a stavovy text VEDLE SEBE.
	_check(l.hud_upgrades.size.x >= 44.0 and l.hud_upgrades.size.y >= 30.0,
		"%s: tlacitko UPGRADY v pruhu je male %.0fx%.0f px" % [tag, l.hud_upgrades.size.x, l.hud_upgrades.size.y])
	_check(l.hud_menu.size.x >= 44.0 and l.hud_menu.size.y >= 30.0,
		"%s: tlacitko MENU v pruhu je male %.0fx%.0f px" % [tag, l.hud_menu.size.x, l.hud_menu.size.y])
	_check(l.hud_upgrades.end.x <= v.x + 0.5 and l.hud_menu.position.x >= -0.5,
		"%s: tlacitka v pruhu prelezaji displej" % tag)
	_check(not l.hud_upgrades.intersects(l.hud_menu), "%s: tlacitka v pruhu se prekryvaji" % tag)
	_check(l.bar_text_w > 0.0, "%s: stavovemu textu nezustalo v pruhu misto" % tag)
	var l1: String = ScreenLayout.HUD_LINE1_FMT % [12, 5, 5]
	var l2: String = ScreenLayout.HUD_LINE2_FMT % [300, 300, 9999]
	var px1: int = _fit_px(l1, l.bar_text_w, l.font_px)
	var px2: int = _fit_px(l2, l.bar_text_w, l.font_px)
	_check(px1 >= 11 and px2 >= 11, "%s: stavovy text v pruhu ma jen %d/%d px" % [tag, px1, px2])

	# 4) PALETA: kazdy pocet barev, ktery muze nastat (2..5).
	for count in range(2, 6):
		var rects: Array = l.layout_palette(count)
		_check(rects.size() == count, "%s: paleta pro %d barev nema %d tlacitek" % [tag, count, count])
		for r in rects:
			var rr: Rect2 = r
			_check(rr.position.y >= v.y - l.pal_h - 0.5 and rr.end.y <= v.y + 0.5,
				"%s: tlacitko barvy (%d) preleza mimo spodni pruh" % [tag, count])
			_check(rr.position.x >= -0.5 and rr.end.x <= v.x + 0.5,
				"%s: tlacitko barvy (%d) preleza displej" % [tag, count])
			_check(rr.size.x >= 44.0 and rr.size.y >= 44.0,
				"%s: tlacitko barvy (%d) je male %.0fx%.0f px" % [tag, count, rr.size.x, rr.size.y])
			_check(absf(rr.size.x - rr.size.y) < 0.5,
				"%s: tlacitko barvy (%d) neni ctverec - z puntiku by byl oval" % [tag, count])
		for i in range(rects.size()):
			for j in range(i + 1, rects.size()):
				_check(not (rects[i] as Rect2).intersects(rects[j] as Rect2),
					"%s: tlacitka barvy (%d) se prekryvaji" % [tag, count])

	# 5) PANEL S UPGRADY V BITVE: cely na displeji, NAD paletou, taby i tlacitka
	# zmacknutelna. Kdyby prekryl paletu, hrac by nemohl prepnout barvu.
	l.set_shop_shape(3, 4)
	_check(l.shop_panel.end.y <= v.y - l.pal_h + 0.5,
		"%s: panel upgradu prekryva paletu barev (%.0f > %.0f)" % [tag, l.shop_panel.end.y, v.y - l.pal_h])
	_check(l.shop_panel.position.y >= l.bar_h - 0.5 and l.shop_panel.end.y <= v.y + 0.5,
		"%s: panel upgradu preleza displej" % tag)
	_check(l.shop_tabs.size() == 3, "%s: v bitve nejsou tri kategorie (%d)" % [tag, l.shop_tabs.size()])
	_check(l.shop_rows.size() == 4 and l.shop_buttons.size() == 4,
		"%s: panel nema ctyri radky s tlacitky" % tag)
	for t in l.shop_tabs:
		var tr: Rect2 = t
		_check(tr.size.y >= ScreenLayout.TAB_MIN - 0.5 and tr.size.x >= 44.0,
			"%s: tab kategorie je maly %.0fx%.0f" % [tag, tr.size.x, tr.size.y])
		_check(l.shop_panel.encloses(tr), "%s: tab kategorie neni v panelu" % tag)
	for i in range(l.shop_buttons.size()):
		var br: Rect2 = l.shop_buttons[i]
		_check(br.size.x >= 56.0 and br.size.y >= ScreenLayout.ROW_MIN - 0.5,
			"%s: tlacitko '+' je male %.0fx%.0f px" % [tag, br.size.x, br.size.y])
		_check(l.shop_rows[i].encloses(br), "%s: tlacitko '+' neni v radku" % tag)
		_check((l.shop_rows[i] as Rect2).size.y >= ScreenLayout.ROW_MIN - 0.5,
			"%s: radek parametru je nizky %.0f px" % [tag, (l.shop_rows[i] as Rect2).size.y])
	for i in range(l.shop_rows.size()):
		for j in range(i + 1, l.shop_rows.size()):
			_check(not (l.shop_rows[i] as Rect2).intersects(l.shop_rows[j] as Rect2),
				"%s: radky panelu se prekryvaji" % tag)
		for t in l.shop_tabs:
			_check(not (l.shop_rows[i] as Rect2).intersects(t as Rect2),
				"%s: radek panelu prekryva taby" % tag)
	# Popisek a hodnota se musi vejit do radku VEDLE tlacitka.
	var br0: Rect2 = l.shop_buttons[0]
	var label_w: float = maxf(40.0, (l.shop_rows[0] as Rect2).size.x - br0.size.x - 3.0 * maxf(6.0, (l.shop_rows[0] as Rect2).size.x * 0.02))
	var longest: String = "Kritické poškození"
	var lpx: int = _fit_px(longest, label_w * 0.52, l.font_px)
	_check(lpx >= 10, "%s: popisek parametru ma jen %d px" % [tag, lpx])
	var cost_px: int = _fit_px("+1000 zl.", br0.size.x - 6.0, l.font_px)
	_check(cost_px >= 9, "%s: cena v tlacitku ma jen %d px" % [tag, cost_px])

	# 6) OBRAZOVKA UPRAVY V MENU: ctyri kategorie + ctyri radky + ZPET.
	_check(l.upg_tabs.size() == Upgrades.CATEGORIES.size(),
		"%s: v menu neni %d kategorii (%d)" % [tag, Upgrades.CATEGORIES.size(), l.upg_tabs.size()])
	_check(l.upg_rows.size() == 4, "%s: obrazovka uprav nema ctyri radky" % tag)
	_check(l.upg_back.size.x >= 44.0 and l.upg_back.size.y >= 44.0,
		"%s: tlacitko ZPET je male" % tag)
	_check(l.upg_panel.position.y >= -0.5 and l.upg_back.end.y <= v.y + 0.5,
		"%s: obrazovka uprav preleza displej" % tag)
	for r in l.upg_rows:
		_check(l.upg_panel.encloses(r as Rect2), "%s: radek uprav neni v panelu" % tag)
	for b in l.upg_buttons:
		var bb: Rect2 = b
		_check(bb.size.x >= 56.0 and bb.size.y >= ScreenLayout.ROW_MIN - 0.5,
			"%s: tlacitko '+' v upravach je male %.0fx%.0f" % [tag, bb.size.x, bb.size.y])

	# 7) DIALOGY: cely na displeji a odpovedi zmacknutelne.
	for two in [true, false]:
		l.dialog_panel(two)
		_check(l.dlg_box.position.x >= -0.5 and l.dlg_box.end.x <= v.x + 0.5
			and l.dlg_box.position.y >= -0.5 and l.dlg_box.end.y <= v.y + 0.5,
			"%s: dialog preleza displej" % tag)
		_check(l.dlg_a.size.x >= 44.0 and l.dlg_a.size.y >= 44.0,
			"%s: odpoved dialogu je mala %.0fx%.0f" % [tag, l.dlg_a.size.x, l.dlg_a.size.y])
		_check(l.dlg_box.encloses(l.dlg_a), "%s: odpoved dialogu neni v ramecku" % tag)
		if two:
			_check(not l.dlg_a.intersects(l.dlg_b), "%s: odpovedi dialogu se prekryvaji" % tag)
			_check(l.dlg_box.encloses(l.dlg_b), "%s: druha odpoved neni v ramecku" % tag)

	# 8) MENU: 4 tlacitka, kazde zmacknutelne, popisky se vejdou.
	_check(l.menu_rects.size() == Menu.MENU_ITEMS.size(),
		"%s: menu ma %d tlacitek, cekano %d" % [tag, l.menu_rects.size(), Menu.MENU_ITEMS.size()])
	for i in range(l.menu_rects.size()):
		var mr: Rect2 = l.menu_rects[i]
		_check(mr.size.x >= 44.0 and mr.size.y >= 44.0, "%s: tlacitko menu '%s' je male" % [tag, str(Menu.MENU_ITEMS[i])])
		_check(mr.end.x <= v.x + 0.5 and mr.position.x >= -0.5, "%s: tlacitko menu preleza displej" % tag)
		_check(_fits(String(Menu.MENU_ITEMS[i]), mr.size.x - 16.0, l.menu_item_px),
			"%s: popisek '%s' se nevejde do tlacitka menu" % [tag, str(Menu.MENU_ITEMS[i])])
		_check(_fits(String(Menu.MENU_SUBS[i]), mr.size.x - 16.0, l.menu_sub_px),
			"%s: podtitulek '%s' se nevejde do tlacitka menu" % [tag, str(Menu.MENU_SUBS[i])])
	_check(l.menu_title_px >= 30, "%s: titul menu je jen %d px" % [tag, l.menu_title_px])

	# 9) HRA ZUSTAVA HRATELNA: poutnik kazde barvy z palety (krome fialove
	# a stribrne, ktere maji vlastni pravidla) musi stihnout umrit v kruhu
	# dostrelu zakladni veze.
	var g := Game.new()
	g.set_field(l.field_r, l.unit_r, l.center)
	var palette: Array = Hue.palette_at(10)
	for h in [Hue.RED, Hue.YELLOW, Hue.BLUE, Hue.GREEN]:
		_check(palette.has(h), "%s: barva %s neni v palete" % [tag, Hue.name_of(h)])
		var ttk: float = g.hp_for(g.kolo(), 1, h) / (g.rate() * Game.SHOT_DMG)
		var window: float = g.range_frac() * Game.TRAVEL_S / Hue.speed_mult(h)
		_check(ttk < window,
			"%s: %s nema v dostrelu cas na zabiti (%.2f s v ohne, potreba %.2f s)"
			% [tag, Hue.name_of(h), window, ttk])


func _fits(s: String, width: float, px: int) -> bool:
	return ThemeDB.fallback_font.get_string_size(
		s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x <= width


func _fit_px(s: String, width: float, max_px: int, min_px: int = 10) -> int:
	var px: int = max_px
	while px > min_px and not _fits(s, width, px):
		px -= 1
	return px
