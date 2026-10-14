extends SceneTree

# Test ROZVRZENI: spawnovaci kruh ma sahat na vrsek a spodek herniho pruhu
# (a na vysku vest boky mimo displej), kruh dostrelu musi dat hraci cas
# zareagovat, tlacitka palety musi jit zmacknout prstem a hra musi zustat
# hratelna. Vystup: LAYOUT_ALL_PASS=true / false
#
# Neresi se jen "nic se neprekryva": u kazdeho rozliseni se overuje, ze se
# kruh dostrelu vejde do plochy, ze paleta neprekryva plochu a ze poutnik
# kazde barvy z palety stihne umrit v kruhu dostrelu (jinak je hra
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
	_run("neznama velikost okna nic nerozbije", _test_zero_size)
	_run("spawnovaci kruh se nemaluje", _test_spawn_ring_not_drawn)
	_run("strela je tecka, paprsek je zamerovani", _test_shots_are_dots)
	_run("paleta je puntik, ne tvar", _test_palette_is_dot)
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


# SPAWNOVACI KRUH SE NEMALUJE. Jan: "Vnější kruh nemá být viditelný a má být
# pomyslný." Hlida se MISTO VOLANI ve zdroji obrazovky: kdyby se `draw_arc`
# s polomerem SPAWNOVACIHO kruhu vratil, hrac by pres displej videl obrovsky
# oblouk, ktery nic neznamena (kruh je vetsi nez displej).
func _test_spawn_ring_not_drawn() -> void:
	var f := FileAccess.open("res://scripts/game_view.gd", FileAccess.READ)
	_check(f != null, "nectu game_view.gd")
	if f == null:
		return
	var src: String = f.get_as_text()
	_check(not src.contains("draw_arc(layout.center, layout.field_r"),
		"spawnovaci kruh se kresli, i kdyz ma byt pomyslny")
	_check(src.contains("draw_arc(layout.center, game.tower.range_px(layout.field_r)"),
		"kruh dostrelu se nekresli (je to jedina geometrie, kterou hrac vidi)")


# STRELA JE TECKA, PAPRSEK JE JEN ZAMEROVANI. Hlida se MISTO VOLANI ve zdroji
# obrazovky: kdyby z kresleni zmizely strely, hrac by videl prazdny paprsek
# a "rychlost strelby" by nemela jak byt videt; kdyby zmizel paprsek, hrac
# nevi, na koho vez miri.
func _test_shots_are_dots() -> void:
	var f := FileAccess.open("res://scripts/game_view.gd", FileAccess.READ)
	_check(f != null, "nectu game_view.gd")
	if f == null:
		return
	var src: String = f.get_as_text()
	_check(src.contains("for s in game.shots"), "strely se vubec nekresli")
	_check(src.contains("game.shot_r()"), "strela se nekresli jako tecka")
	_check(src.contains("draw_line(layout.center, p.pos, BEAM, 2.0)"),
		"paprsek (zamerovani) zmizel - hrac nevidi, kam vez miri")


# PALETA JE PUNTIK, NE TVAR (Jan, Oct 2026): "bude to zkrátka jen barevný plný
# puntík s borderem. Žádné tvary." Hlida se MISTO VOLANI ve zdroji obrazovky:
# kdyby se do palety vratila runa (`_shape`), hrac by videl sest tvaru a Jan
# chce jen barvu; a bez `draw_circle` by z tlacitka zbyl jen ramecek.
func _test_palette_is_dot() -> void:
	var f := FileAccess.open("res://scripts/game_view.gd", FileAccess.READ)
	_check(f != null, "nectu game_view.gd")
	if f == null:
		return
	var src: String = f.get_as_text()
	var start: int = src.find("func _draw_palette")
	_check(start >= 0, "kresleni palety vubec neexistuje")
	if start < 0:
		return
	var end: int = src.find("\nfunc ", start + 1)
	var body: String = src.substr(start, (end - start) if end > start else src.length() - start)
	_check(body.contains("draw_circle("), "paleta neni plny puntik (chybi draw_circle)")
	_check(not body.contains("_shape("), "paleta kresli tvary, i kdyz ma byt jen puntik s borderem")


func _test_zero_size() -> void:
	var l := ScreenLayout.new()
	l.update(Vector2.ZERO)
	_check(l.arena.size.x >= 0.0 and l.arena.size.y >= 0.0,
		"nulova velikost okna dela zaporny obdelnik")
	_check(l.up_rect.size.x >= 0.0 and l.up_rect.size.y >= 0.0,
		"nulova velikost okna dela zaporne tlacitko")
	_check(l.field_r == 0.0, "nulova velikost okna dela plochu")
	_check(l.layout_palette(5).is_empty(), "nulova velikost okna dela tlacitka palety")
	_check(l.layout_menu(3).is_empty(), "nulova velikost okna dela tlacitka menu")
	_check(l.arena.size.x >= 0.0 and l.hud_menu.size.x >= 0.0
		and l.leave_box.size.x >= 0.0 and l.settings_row.size.x >= 0.0,
		"nulova velikost okna dela zaporne obdelniky rozvrzeni")


func _test_resolution(v: Vector2) -> void:
	var l := ScreenLayout.new()
	l.update(v)
	var tag: String = "%dx%d" % [int(v.x), int(v.y)]

	# 1) SPAWNOVACI KRUH: horni a spodni okraj se dotkne okraje herniho pruhu
	# (nikdy nepreleze do horniho pruhu ani do palety) a NA VYSKU je kruh VETSI
	# nez displej - boky vedou mimo obraz, ale hra je bere v potaz (poutnici
	# odtamtud vchazeji z boku). Kresli se jen kruh dostrelu.
	_check(absf((l.center.y - l.field_r) - l.arena.position.y) < 0.5,
		"%s: spawnovaci kruh nedosahuje na vrsek herniho pruhu (odchylka %.1f px)"
		% [tag, (l.center.y - l.field_r) - l.arena.position.y])
	_check(absf((l.center.y + l.field_r) - l.arena.end.y) < 0.5,
		"%s: spawnovaci kruh nedosahuje na spodek herniho pruhu (odchylka %.1f px)"
		% [tag, (l.center.y + l.field_r) - l.arena.end.y])
	if v.y > v.x:
		_check(l.center.x - l.field_r <= 0.0 and l.center.x + l.field_r >= v.x - 0.5,
			"%s: spawnovaci kruh neni vetsi nez displej (boky maji vest mimo obraz)" % tag)
	else:
		# NA SIRKU hra rika "otoc telefon" - kruh se vejde do sirky, jen se
		# nesmi rozbit.
		_check(l.field_r <= l.arena.size.x * 0.5 + 0.5,
			"%s: na sirku spawnovaci kruh preleza displej" % tag)

	# 2) POUTNIK JE CITELNY (runa je TVAR tela, takze 6 px je spodni mez)
	_check(l.pilgrim_r >= 6.0,
		"%s: poutnik ma polomer %.1f px, barva a tvar nejdou precist" % [tag, l.pilgrim_r])
	_check(l.tower_r >= 12.0, "%s: vez je prilis mala (%.1f px)" % [tag, l.tower_r])

	# 2b) KRESLENI JE Z MERITKA, NE Z PLOCHY. Vez i poutnik jsou z MERITKA
	# (vepsany kruh do kratsi strany herniho pruhu, zmenseno o UNIT_SHRINK),
	# NIKDY z polomeru plochy - jinak by se spawnovacim kruhem "priblizila" cela
	# hra, protoze plocha je vetsi nez displej.
	# (Jan: "Jediné, cos udělala je to, žes celou hru zoomnula.")
	var short_side: float = minf(l.arena.size.x, l.arena.size.y)
	var want_unit: float = (short_side * 0.5 - short_side * ScreenLayout.MARGIN_FRAC) \
		* ScreenLayout.UNIT_SHRINK
	_check(absf(l.unit_r - want_unit) < 0.5,
		"%s: meritko kresleni neni zmensený vepsany kruh do kratsi strany (%.1f, ma byt %.1f)"
		% [tag, l.unit_r, want_unit])
	_check(is_equal_approx(l.tower_r, l.unit_r * Game.TOWER_R_FRAC),
		"%s: vez se pocita z polomeru plochy, ne z meritka (zoom se zmenil)" % tag)
	_check(is_equal_approx(l.pilgrim_r, l.unit_r * Game.PILGRIM_R_FRAC),
		"%s: poutnik se pocita z polomeru plochy, ne z meritka (zoom se zmenil)" % tag)
	# DVE CISLA O VEZI ZNAMENA DVE PRAVDY: hra si polomer veze odvozuje z
	# meritka taky, takze se musi rovnat rozvrzeni (stejna past jako ED_COUNT).
	var gz := Game.new()
	gz.set_field(l.field_r, l.unit_r, l.center)
	_check(is_equal_approx(gz.tower_r, l.tower_r),
		"%s: hra ma jiny polomer veze nez rozvrzeni (%.2f vs %.2f)"
		% [tag, gz.tower_r, l.tower_r])
	if tag == "390x844":
		# CISLA Z DISPLEJE, NA KTEREM JAN HRAJE. Po druhem zmenseni (UNIT_SHRINK
		# 0,85) je vez 18,7 px a poutnik 7,8 px (driv 22 a 9,2). Kdyby se
		# zmenseni pohnulo, spadne to - a kdyby se pocitalo z plochy, spadne
		# jeste vic.
		_check(absf(l.tower_r - 18.7) < 0.3,
			"na 390x844 ma vez %.1f px (ma byt 18,7)" % l.tower_r)
		_check(absf(l.pilgrim_r - 7.79) < 0.3,
			"na 390x844 ma poutnik %.2f px (ma byt 7,8)" % l.pilgrim_r)

	# 2c) DOSTREL PRVNIHO STUPNE SE MUSI VEJIT MEZI BOKY DISPLEJE. Jan:
	# "Rozsah zjišťování nepřátel nesmí mít hned na začátku poloměr jak celá
	# šířka displeje. Musí začínat na menším úseku, aby ho bylo kam upgradovat."
	# Zaklad, ktery dosahne na boky, vypada jako "vidim celou plochu" a upgrade
	# uz nema kam jit.
	var g1 := Game.new()
	g1.set_field(l.field_r, l.unit_r, l.center)
	var r1: float = g1.tower.range_px(l.field_r)
	_check(l.center.x - r1 >= 8.0 and l.center.x + r1 <= v.x - 8.0,
		"%s: zakladni dostrel (%0.0f px) dosahuje na bok displeje - neni kam upgradovat"
		% [tag, r1])
	_check(r1 > l.tower_r * 2.0,
		"%s: zakladni dostrel je skoro u veze (%.0f px)" % [tag, r1])
	g1.tower.level = Tower.MAX_LEVEL
	var rmax: float = g1.tower.range_px(l.field_r)
	_check(rmax >= r1 * 1.5,
		"%s: upgrade prida jen kousek dostrelu (%.0f -> %.0f px)" % [tag, r1, rmax])
	_check(rmax < l.field_r * 0.95,
		"%s: dostrel na maximu pokryva celou plochu (%.0f z %.0f px)" % [tag, rmax, l.field_r])

	# 3) TLACITKO VYLEPSENI SE VEJDE DO PRUHU
	_check(l.up_rect.position.x >= 0.0 and l.up_rect.end.x <= v.x + 0.5,
		"%s: tlacitko vylepseni preleza displej" % tag)
	_check(l.up_rect.end.y <= l.bar_h + 0.5, "%s: tlacitko preleza pruh" % tag)
	_check(l.up_rect.size.y >= 30.0,
		"%s: tlacitko je nizke %.1f px" % [tag, l.up_rect.size.y])

	# 4) PALETA: kazdy pocet barev, ktery muze nastat (2..5), musi mit tlacitka
	# vysoka i siroka pres dotykovou mez a cela uvnitr displeje.
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
				"%s: tlacitko barvy (%d) je male %.0fx%.0f px"
				% [tag, count, rr.size.x, rr.size.y])
			# KRUH SE KRESLI DO CTVERCE - v obdelniku by z puntiku byl oval.
			_check(absf(rr.size.x - rr.size.y) < 0.5,
				"%s: tlacitko barvy (%d) neni ctverec (%.0fx%.0f) - z puntiku by byl oval"
				% [tag, count, rr.size.x, rr.size.y])
		# tlacitka se nesmi prekryvat, jinak hrac zmackne jinou barvu
		for i in range(rects.size()):
			for j in range(i + 1, rects.size()):
				_check(not (rects[i] as Rect2).intersects(rects[j] as Rect2),
					"%s: tlacitka barvy (%d) se prekryvaji" % [tag, count])

	# 5) HRA ZUSTAVA HRATELNA: poutnik kazde barvy z palety (krome fialove
	# a stribrne, ktere maji vlastni pravidla) musi stihnout umrit v kruhu
	# dostrelu zakladni veze.
	var g := Game.new()
	g.set_field(l.field_r, l.unit_r, l.center)
	var palette: Array = Hue.palette_at(10)
	for h in [Hue.RED, Hue.YELLOW, Hue.BLUE, Hue.GREEN]:
		_check(palette.has(h), "%s: barva %s neni v palete" % [tag, Hue.name_of(h)])
		var ttk: float = g.hp_for(1, h) / g.tower.dps()
		var window: float = g.tower.range_frac() * Game.TRAVEL_S / Hue.speed_mult(h)
		_check(ttk < window,
			"%s: %s nema v dostrelu cas na zabiti (%.2f s v ohne, potreba %.2f s)"
			% [tag, Hue.name_of(h), window, ttk])

	_test_menu_layout(v, l, tag)


# 6) MENU, NASTAVENI A ODCHOD Z BOJE: kazde tlacitko musi jit zmacknout prstem
# a musi byt CELE na displeji. Neresi se jen "nic neprekryva" - pocita se
# i to, ze se popisek do tlacitka vejde (na uzke obrazovce jinak text pretece).
func _test_menu_layout(v: Vector2, l: ScreenLayout, tag: String) -> void:
	var rects: Array = l.menu_rects
	_check(rects.size() == Menu.MENU_ITEMS.size(),
		"%s: menu ma %d tlacitek, cekano %d" % [tag, rects.size(), Menu.MENU_ITEMS.size()])
	for i in range(rects.size()):
		var r: Rect2 = rects[i]
		_check(r.position.x >= -0.5 and r.end.x <= v.x + 0.5,
			"%s: tlacitko menu '%s' preleza displej" % [tag, str(Menu.MENU_ITEMS[i])])
		_check(r.size.x >= 44.0 and r.size.y >= 44.0,
			"%s: tlacitko menu '%s' je male %.0fx%.0f px"
			% [tag, str(Menu.MENU_ITEMS[i]), r.size.x, r.size.y])
		_check(_fits(String(Menu.MENU_ITEMS[i]), r.size.x - 16.0, l.menu_item_px),
			"%s: popisek '%s' se nevejde do tlacitka menu"
			% [tag, str(Menu.MENU_ITEMS[i])])
		_check(_fits(String(Menu.MENU_SUBS[i]), r.size.x - 16.0, l.menu_sub_px),
			"%s: podtitulek '%s' se nevejde do tlacitka menu"
			% [tag, str(Menu.MENU_SUBS[i])])
		for j in range(i + 1, rects.size()):
			_check(not r.intersects(rects[j] as Rect2),
				"%s: tlacitka menu %d a %d se prekryvaji" % [tag, i, j])
	_check(l.menu_title_y > 0.0 and l.menu_title_y < (rects[0] as Rect2).position.y,
		"%s: titul menu neni nad tlacitky" % tag)
	_check(l.menu_note_y >= (rects[rects.size() - 1] as Rect2).end.y
		and l.menu_note_y + float(l.menu_sub_px) <= v.y + 0.5,
		"%s: hlaska pod tlacitky menu neni pod nimi (nebo preleza displej)" % tag)

	# MENU JE VELKE. Jan: "A menu uděláme o dost větší" - kdyby se vratilo
	# k polovine sirky displeje, hrac by zase mířil na maly ctverecek. Meze
	# jsou podily displeje (a strop sirky), aby to platilo i na 932x430.
	var first: Rect2 = rects[0]
	_check(first.size.x >= minf(v.x * 0.7, 520.0),
		"%s: tlacitko menu je jen %.0f px siroke (displej %0.0f)" % [tag, first.size.x, v.x])
	_check(first.size.y >= minf(72.0, v.y * 0.13),
		"%s: tlacitko menu je jen %.0f px vysoke" % [tag, first.size.y])
	_check(l.menu_title_px >= 30, "%s: titul menu je jen %d px" % [tag, l.menu_title_px])
	# PODTITULEK SE NESMI DOTKNOUT PRVNIHO TLACITKA - kresli se stejnou barvou,
	# takze by si hrac precetl dve veci pres sebe.
	var sub_bottom: float = l.menu_title_y + float(l.menu_title_px) * 0.5 + float(l.menu_sub_px)
	_check(sub_bottom <= first.position.y + 0.5,
		"%s: podtitulek menu preleza do prvniho tlacitka (%.0f > %.0f)"
		% [tag, sub_bottom, first.position.y])

	# NASTAVENI: dve tlacitka pod sebou, dotykova mez, po jednom sloupci.
	for r in [l.settings_row, l.settings_back]:
		var rr: Rect2 = r
		_check(rr.size.x >= 44.0 and rr.size.y >= 44.0,
			"%s: tlacitko nastaveni je male %.0fx%.0f px" % [tag, rr.size.x, rr.size.y])
		_check(rr.position.x >= -0.5 and rr.end.x <= v.x + 0.5,
			"%s: tlacitko nastaveni preleza displej" % tag)
	_check(not l.settings_row.intersects(l.settings_back),
		"%s: tlacitka nastaveni se prekryvaji" % tag)

	# HORNI PRUH: MENU, stavovy text a Vylepsit se musi vejit VEDLE SEBE.
	_check(l.hud_menu.size.x >= 44.0 and l.hud_menu.size.y >= 30.0,
		"%s: tlacitko MENU v pruhu je male %.0fx%.0f px" % [tag, l.hud_menu.size.x, l.hud_menu.size.y])
	_check(l.hud_menu.position.x >= -0.5 and l.hud_menu.end.x <= v.x + 0.5,
		"%s: tlacitko MENU v pruhu preleza displej" % tag)
	_check(l.hud_menu.end.y <= l.bar_h + 0.5, "%s: tlacitko MENU preleza pruh" % tag)
	_check(not l.hud_menu.intersects(l.up_rect),
		"%s: tlacitko MENU se prekryva s vylepsenim" % tag)
	_check(not l.hud_menu.intersects(l.up_rect) and l.bar_text_w > 0.0,
		"%s: stavovemu textu nezustalo v pruhu zadne misto" % tag)
	# STAVOVY TEXT SE NA UZKEM DISPLEJI ZMENSUJE, ale nesmi spadnout na
	# necitelnych par pixelu - pak je lepsi text zkratit, ne ho zmensit.
	var state: String = ScreenLayout.HUD_STATE_FMT % [10, Game.WAVE_MAX, 12, 100]
	var px: int = _fit_px(state, l.bar_text_w, l.font_px)
	_check(px >= 11, "%s: stavovy text v pruhu ma jen %d px" % [tag, px])
	_check(_fits(state, l.bar_text_w, px), "%s: stavovy text se nevejde do pruhu" % tag)
	_check(_fits("MENU", l.hud_menu.size.x - 8.0, l.font_px) or _fit_px("MENU", l.hud_menu.size.x - 8.0, l.font_px) >= 10,
		"%s: popisek MENU se nevejde do tlacitka" % tag)

	# DOTAZ PRI ODCHODU: kresli se nad vsim, takze musi byt cely na displeji.
	_check(l.leave_box.position.x >= -0.5 and l.leave_box.end.x <= v.x + 0.5
		and l.leave_box.position.y >= -0.5 and l.leave_box.end.y <= v.y + 0.5,
		"%s: dotaz pri odchodu preleza displej" % tag)
	_check(not l.leave_yes.intersects(l.leave_no), "%s: odpovedi dotazu se prekryvaji" % tag)
	for r in [l.leave_yes, l.leave_no]:
		var rr: Rect2 = r
		_check(rr.size.x >= 44.0 and rr.size.y >= 44.0,
			"%s: odpoved dotazu je mala %.0fx%.0f px" % [tag, rr.size.x, rr.size.y])
		_check(l.leave_box.encloses(rr), "%s: odpoved dotazu neni v jeho ramecku" % tag)


# MERI PISMO JAKO OBRAZOVKA: vejde se popisek do dane sirky pri danem poctu
# pixelu? Kdyz ne, rozvrzeni nebo popisek je spatne - a pozna se to CISLY,
# ne okem na snimku.
func _fits(s: String, width: float, px: int) -> bool:
	return ThemeDB.fallback_font.get_string_size(
		s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x <= width


# NEJVETSI PISMO, KTERE SE DO SIRKY VEJDE (stejne jako `GameView._fit_px`).
func _fit_px(s: String, width: float, max_px: int, min_px: int = 10) -> int:
	var px: int = max_px
	while px > min_px and not _fits(s, width, px):
		px -= 1
	return px
