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
	_run("tlacitko pauzy je ikona (carky / trojuhelnik)", _test_pause_is_icon)
	_run("nulova velikost okna nic nerozbije", _test_zero_size)
	_run("spawnovaci kruh se nemaluje", _test_spawn_ring_not_drawn)
	_run("laser je cara s obrysem a kresli se nad vezi", _test_beams_are_lines)
	_run("prstenec poutnika je jeho HP bar a nic jineho", _test_ring_is_hp_bar)
	_run("poutnik je i po zmenseni citelny", _test_pilgrim_stays_readable)
	_run("paleta je puntik, ne tvar", _test_palette_is_dot)
	_run("pismeno barvy je jedno a jedinecne", _test_letters)
	_run("kruh dostrelu ma barvu veze", _test_range_is_colored)
	_run("panel s upgrady je v bitve trvale otevreny", _test_panel_is_permanent)
	_run("panel v bitve nenabizi upgrade, ktery v ni nejde koupit", _test_shop_hides_perm_only)
	_run("bunka upgradu ma hodnotu a cenu na jednom radku", _test_cell_lines)
	_run("taby kategorii maji ikony", _test_tabs_are_icons)
	_run("poutnici jdou k vezi oblicejem", _test_shapes_face_the_tower)
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


# LASER JE CARA S OBRYSEM A KRESLI SE NAD VSIM V POLI. Poradi v `_draw` je
# zavazne - prehozeni dvou radku vypada v kodu jako kosmetika a na obrazovce
# je to nevidet jen tak.
func _test_beams_are_lines() -> void:
	var src: String = _src()
	_check(src.contains("for b in game.beams"), "paprsky se vubec nekresli")
	_check(src.contains("game.beam_w("), "paprsek se nekresli jako cara")
	_check(src.contains("_beam_line(b[\"from\"], b[\"to\"], GLYPH"),
		"paprsek nema tmavy obrys - na svetlem poutnikovi se ztrati")
	# KULATE ZAKONCENI. Godot kresli caru s hranatym koncem; kdyby se kazdy
	# konec nedokreslil koleckem, hrac vidi "dva obdelniky vedle sebe" (Jan,
	# Oct 2026).
	_check(src.contains("draw_circle(a, w * 0.5, c)") and src.contains("draw_circle(b, w * 0.5, c)"),
		"paprsek ma hranate konce - v prstenci poutnika je videt svar")
	# PRSTENEC KOLEM POUTNIKA. Je to hranice, na ktere paprsek konci; kdyby se
	# nekreslil, hrac vidi caru, ktera se z niceho nic zastavi ve vzduchu.
	_check(src.contains("game.pilgrim_ring_r(p)"),
		"prstenec kolem poutnika se nekresli - paprsek konci ve prazdnu")
	# POZOR: `check_symbols.py` hlida kazdy vyskyt "game.<neco>" v obrazovkach,
	# takze se ten nazev sklada az za behu - jinak by si nastroj myslel, ze se
	# obrazovka porad dozaduje projektu, ktere hra uz nema.
	_check(not src.contains("game." + "shots"),
		"obrazovka porad kresli projektily, ktere hra uz nema")
	var i_tower: int = src.find("\n	_draw_tower()")
	var i_beams: int = src.find("\n	_draw_beams()")
	_check(i_tower >= 0 and i_beams >= 0,
		"kresleni paprsku neni hned za vezi (v poli se nevi, co je nad cim)")
	_check(i_tower < i_beams, "paprsky se kresli driv nez vez - nejsou nad ni")


# PRSTENEC KOLEM POUTNIKA JE ZAROVEN JEHO HP BAR (Jan, Oct 2026: "Kruhy kolem
# nepřátel budou sloužit rovnou jako jejich HP bary.") a NIC JINEHO kolem nej
# neni. Druhy, bily oblouk (`r * 1.55`, barva TEXT) se zrusil - Jan ho videl
# jako "ještě jeden kruhový Border (světle modrý nebo bílý) kolem jejich životů.
# Ten je tam navíc." Hlida se MISTO VOLANI ve zdroji obrazovky: kdyby se vratil,
# obrazovka k tomu nic nerekne a hrac vidi dve kolecka misto jednoho.
func _test_ring_is_hp_bar() -> void:
	var src: String = _src()
	var at: int = src.find("func _draw_pilgrim")
	_check(at >= 0, "ve zdroji obrazovky chybi _draw_pilgrim")
	if at < 0:
		return
	var end: int = src.find("\nfunc ", at + 1)
	var body: String = src.substr(at, (end - at) if end > at else src.length() - at)
	_check(body.contains("TAU * p.hp_frac()"),
		"prstenec poutnika nekresli zbyvajici zivoty - kruh neni HP bar")
	_check(not body.contains("1.55"),
		"kolem poutnika se kresli druhy (bily) oblouk, ktery tam nema byt")
	# PRSTENEC SE NESMI DOTYKAT TVARE. Tvar saha k 1,15 r (kapka brisko), takze
	# s `RING_FRAC` pod 1,45 je mezera mensi nez tretina polomeru a kruh vypada,
	# jako by obkresloval oblicej (Jan: "Ať kruh není nalepený přímo na tvář").
	_check(Game.RING_FRAC >= 1.45,
		"prstenec je nalepeny na tvár (RING_FRAC %.2f)" % Game.RING_FRAC)


# POUTNIK JE I PO ZMENSENI CITELNY. Jan (Oct 2026): "Všechny nepřátele o 15 %
# zmenšíme" - ale zmenseni o par procent vic a z tvaru je necitelny puntik;
# hranice je 5 px v polomeru na nejmensim beznem telefonu.
func _test_pilgrim_stays_readable() -> void:
	for r in RESOLUTIONS:
		# NA SIRKU SE VELIKOST NEHLIDA (stejne jako u `_test_resolution`): hra je
		# na vysku a na sirokem displeji vyjdou jednotky male i v poradku.
		if r.y <= r.x:
			continue
		var l := ScreenLayout.new()
		l.update(r)
		var r_px: float = l.pilgrim_r * Game.PILGRIM_SIZE
		_check(r_px >= 5.0, "%dx%d: poutnik ma po zmenseni %.1f px v polomeru"
			% [int(r.x), int(r.y), r_px])


# PANEL V BITVE NENABIZI UPGRADE, KTERY V NI NEJDE KOUPIT. Stat s `temp_max` 0
# (dostrel, specialy) by zabral bunku, ukazoval cenu 0 a "MAX" - hrac by videl
# tlacitko, ktere nic nedela a nerekne proc. Hlida se MISTO VOLANI ve zdroji:
# kdyby se filtr vratil, testy rozvrzeni by zustaly zelene a panel by zase
# nabizel mrtve tlacitko.
func _test_shop_hides_perm_only() -> void:
	var src: String = _src()
	var at: int = src.find("func _shop_stats()")
	_check(at >= 0, "ve zdroji obrazovky chybi _shop_stats()")
	if at < 0:
		return
	var end: int = src.find("\nfunc ", at + 1)
	var body: String = src.substr(at, (end - at) if end > at else src.length() - at)
	_check(body.contains("temp_max"), "panel v bitve nabizi i stat bez docasnych kroku")
	# A dostrel opravdu zadne docasne kroky nema - jinak by filtr nemel co delat.
	_check(Upgrades.temp_max("ar") == 0, "dostrel ma docasne kroky, filtr nema co delat")


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
	# PISMENO BARVY VE STREDU (Jan, Oct 2026). Bez nej je barva jediny nositel
	# informace - presne to, co u sesti barev nefunguje.
	_check(body.contains("Hue.letter_of("), "puntik palety nema pismeno barvy")


# POUTNIK JDE K VEZI "OBLICEJEM" (Jan, Oct 2026: "všichni nepřátelé by měli k věži
# směřovat 'obličejem'. Trojúhelník jedno z vrcholů, ne stěnou. Kapka bříškem, ne
# stranou."). Trojuhelnik ma k vezi VRCHOL, kapka BRISKO, kosostverec vrchol, kriz
# rameno. Ctverec a kruh se NEOTACI - ctverec otoceny o 45 stupnu je kosostverec
# fialove, a to je jina barva.
func _test_shapes_face_the_tower() -> void:
	var c := Vector2(100.0, 100.0)
	var r := 10.0
	var right := Vector2(1.0, 0.0)
	var tri: PackedVector2Array = Shapes.pts("triangle", c, r, right)
	_check(tri.size() == 3, "trojuhelnik nema tri vrcholy")
	var tip: float = -99999.0
	for v in tri:
		tip = maxf(tip, v.x)
	_check(absf(tip - (c.x + r)) < 0.01,
		"trojuhelnik nedrzi vrcholem k vezi (spicka %.2f, ma byt %.2f)" % [tip, c.x + r])
	var dr: PackedVector2Array = Shapes.pts("droplet", c, r, right)
	var belly: float = -99999.0
	for v in dr:
		belly = maxf(belly, v.x)
	_check(absf(belly - (c.x + 0.95 * r)) < 0.01, "kapka nedrzi brisko k vezi")
	_check(not Shapes.pts("diamond", c, r, right).is_empty(), "kosostverec se neotaci")
	_check(not Shapes.pts("cross", c, r, right).is_empty(), "kriz se neotaci")
	_check(Shapes.pts("square", c, r, right).is_empty(), "ctverec se otaci (byl by z nej kosostverec)")
	_check(Shapes.pts("circle", c, r, right).is_empty(), "kruh se otaci, i kdyz je to jedno")
	var still: PackedVector2Array = Shapes.pts("triangle", c, r, Vector2.ZERO)
	_check(absf(still[0].y - (c.y - r)) < 0.01, "bez smeru se tvar prece jen otocil")
	_check(_src().contains("Shapes.facing(p.dir)"),
		"obrazovka neposila do tvaru smer chuze - poutnici by chodili bokem")


# PISMENO MA KAZDA BARVA JINE, JEDNOPISMENNOVE A NIKDY PRAZDNE. Dve barvy se
# stejnym pismenem by hrac nerozlisil a prazdny puntik by nechal barvu jako
# jediny nositel informace. Poradi pismen ve smesi je dane poradim barev, takze
# cervena+zluta je VZDY "RY" - jinak by jedna barva mela dve jmena.
func _test_letters() -> void:
	var used: Dictionary = {}
	for h in range(Hue.COUNT):
		var l: String = Hue.letter_of(h)
		_check(l.length() == 1, "barva %s nema jednopismennove oznaceni (%s)" % [Hue.name_of(h), l])
		_check(not used.has(l), "pismeno %s maji dve barvy (%s a %s)"
			% [l, used.get(l, "?"), Hue.name_of(h)])
		used[l] = Hue.name_of(h)
	_check(Hue.letter_of_pair(Hue.RED, Hue.YELLOW) == "RY",
		"smes cervene a zlute se nejmenuje RY (%s)" % Hue.letter_of_pair(Hue.RED, Hue.YELLOW))
	_check(Hue.letter_of_pair(Hue.YELLOW, Hue.RED) == "RY",
		"smes ma jine pismeno podle poradi, jak se barvy vybraly")
	_check(Hue.letter_of_pair(Hue.RED, Hue.RED) == "R",
		"jedna barva sama se sebou nedostala jednopismennove jmeno")


# KRUH DOSTRELU MA BARVU ZVOLENE BARVY VEZE.
func _test_range_is_colored() -> void:
	var src: String = _src()
	_check(src.contains("_range_color()"), "kruh dostrelu nema barvu veze (chybi _range_color())")
	var start: int = src.find("func _range_color")
	var end: int = src.find("\nfunc ", start + 1)
	var body: String = src.substr(start, (end - start) if end > start else 40)
	_check(body.contains("Hue.color_of(game.tower.hue)"), "barva kruhu neni barva veze")


# PANEL S UPGRADY JE V BITVE TRVALE OTEVRENY (Jan, Oct 2026: "Tlacitka v levelu
# ... budou tam totiz permanentne" + "Krizek pro zavreni upgradu v levelu tedy
# smazeme"). Hlida se MISTO VOLANI ve zdroji, protoze obrazovka se v headless
# testu nevykresluje: kdyby se vratilo `if shop_open`, panel by zase mizel
# a testy rozvrzeni by byly zelene.
func _test_panel_is_permanent() -> void:
	var src: String = _src()
	_check(src != "", "nectu game_view.gd")
	_check(not src.contains("shop_open"),
		"obrazovka ma porad prepinac panelu (shop_open) - panel ma byt otevreny porad")
	_check(not src.contains("hud_upgrades"),
		"tlacitko UPGRADY v hornim pruhu existuje, i kdyz je panel otevreny porad")
	_check(not src.contains("_draw_close") and not src.contains("shop_close"),
		"krizek na zavreni panelu v levelu existuje, i kdyz se smazal")
	var i_battle: int = src.find("func _draw_battle")
	_check(i_battle >= 0, "kresleni bitvy (func _draw_battle) ve zdroji neexistuje")
	var battle_body: String = ""
	if i_battle >= 0:
		var i_next: int = src.find("\nfunc ", i_battle + 1)
		battle_body = src.substr(i_battle, (i_next - i_battle) if i_next > i_battle else 400)
	_check(battle_body.contains("_draw_shop()"),
		"panel s nakupem se v bitve vubec nekresli")
	# HRA POD PANELEM BEZI: kdyby byl panel v `is_halted`, partie by se zastavila
	# hned po vstupu do bitvy a hrac by si ani neskrtl.
	var i_halt: int = src.find("func is_halted")
	var end: int = src.find("\nfunc ", i_halt + 1)
	var halt_body: String = src.substr(i_halt, (end - i_halt) if end > i_halt else 120)
	# POZOR: `is_halted` se od Oct 2026 ptá i na `reset_ask` (dialog na smazani
	# postupu), takze se hlida jen to podstatne - ze v nem NENI panel s upgrady.
	_check(halt_body.contains("leave_ask") and halt_body.contains("game.is_over()"),
		"hra se pod trvale otevrenym panelem zastavuje (is_halted)")
	_check(not halt_body.contains("shop"),
		"panel s upgrady je v is_halted - pod panelem by se partie zastavila")


# HODNOTA A CENA JSOU NA JEDNOM RADKU (Jan, Oct 2026: "Hodnota a cena budou na
# stejném řádku"). Hlida se MISTO VOLANI ve zdroji obrazovky: kdyby se cena
# vratila na treti radek, bunka by zase narostla a testy rozvrzeni to nepoznaji.
func _test_cell_lines() -> void:
	var src: String = _src()
	var start: int = src.find("func _draw_grid")
	_check(start >= 0, "kresleni bunky upgradu (_draw_grid) ve zdroji neexistuje")
	if start < 0:
		return
	var end: int = src.find("\nfunc ", start + 1)
	var body: String = src.substr(start, (end - start) if end > start else 900)
	_check(body.contains("c.size.y / 2.0"), "bunka upgradu nema dva radky textu")
	_check(not body.contains("line * 2.0"), "cena je porad na tretim radku bunky")
	_check(body.contains("layout.measure_px(pr, pr_px)"),
		"cena si nebere misto vedle hodnoty - hodnota a cena se mohou prekryt")


# PAUZA JE IKONA, NE TEXT (Jan, Oct 2026: "Tlačítko Pause nebude mít text ale
# velkou ikonu. Ikonu pauzy, po kliknutí ikonu resume."). Hlida se ZDROJ:
# kdyby se vratil popisek, test to rekne - a zaroven se overi, ze ikona ma OBE
# podoby (carky = stoji, trojuhelnik = bezi).
func _test_pause_is_icon() -> void:
	var src: String = _src()
	_check(src.contains("_draw_pause_icon("), "tlacitko PAUZA se nekresli jako ikona")
	_check(not src.contains("\"POKRAČOVAT\" if"),
		"tlacitko PAUZA ma porad textovy popisek")
	var start: int = src.find("func _draw_pause_icon")
	_check(start >= 0, "chybi kresleni ikony pauzy")
	var end: int = src.find("\nfunc ", start + 1)
	var body: String = src.substr(start, (end - start) if end > start else 900)
	_check(body.contains("draw_rect("), "ikona pauzy nema dve carky")
	_check(body.contains("draw_colored_polygon("), "ikona resume nema trojuhelnik")


func _test_zero_size() -> void:
	var l := ScreenLayout.new()
	l.update(Vector2.ZERO)
	_check(l.arena.size.x >= 0.0 and l.arena.size.y >= 0.0, "nulova velikost dela zaporny obdelnik")
	_check(l.hud_menu.size.x >= 0.0, "nulova velikost dela zaporne tlacitko")
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
	# Rozhoduje TVAR HERNIHO PRUHU, ne tvar displeje: kruh se vzdy vepise do vysky
	# pruhu, takze kdyz je pruh vyssi nez siroky, vede na vysku boky mimo obraz
	# (a poutnici vchazeji ze vsech stran). Na sirokem pruhu se kruh vepise
	# do sirky - to je pripad velkeho tabletu, kde panel s upgrady pruh zkrati.
	if l.arena.size.y >= l.arena.size.x:
		_check(l.center.x - l.field_r <= 0.0 and l.center.x + l.field_r >= v.x - 0.5,
			"%s: spawnovaci kruh neni vetsi nez displej (boky maji vest mimo obraz)" % tag)
	else:
		_check(l.field_r <= l.arena.size.x * 0.5 + 0.5, "%s: na sirku spawnovaci kruh preleza displej" % tag)

	# 2) POUTNIK JE CITELNY a vsechno se pocita Z MERITKA (UNIT_SHRINK).
	# NA SIRKU SE VELIKOST NEHLIDA: hra je na vysku ("otoc telefon") a trvale
	# otevreny panel s upgrady tam z herniho pruhu ubere skoro vsechno - jednotky
	# vyjdou male, i kdyz je rozvrzeni v poradku.
	if v.y > v.x:
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
	g1.profile.perm["ar"] = Upgrades.perm_max("ar")
	g1.temp["ar"] = Upgrades.temp_max("ar")
	var rmax: float = g1.range_px()
	_check(rmax >= r1 * 1.5, "%s: upgrade prida jen kousek dostrelu (%.0f -> %.0f px)" % [tag, r1, rmax])
	_check(rmax < l.field_r * 0.95, "%s: dostrel na maximu pokryva celou plochu" % tag)

	# 3) HORNI PRUH: stavovy text a tlacitko MENU. Tlacitko UPGRADY zmizelo -
	# panel s nakupem je v bitve otevreny porad (`_test_panel_is_permanent`).
	_check(l.hud_menu.size.x >= 44.0 and l.hud_menu.size.y >= 30.0,
		"%s: tlacitko MENU v pruhu je male %.0fx%.0f px" % [tag, l.hud_menu.size.x, l.hud_menu.size.y])
	_check(l.hud_menu.end.x <= v.x + 0.5 and l.hud_menu.position.x >= -0.5,
		"%s: tlacitko v pruhu preleza displej" % tag)
	_check(l.hud_menu.end.y <= l.bar_h + 0.5, "%s: tlacitko v pruhu preleza do plochy" % tag)
	# PAUZA / POKRAČOVAT stoji VLEVO od MENU (odchod je na kraji, kde ho hrac
	# nehleda omylem) a meri se z DELSIHO popisku, takze se pri prepnuti stavu
	# nic neposune. Na uzkem displeji musi zbytek pruhu jeste uzivit stavovy text.
	_check(l.hud_pause.size.x >= 44.0 and l.hud_pause.size.y >= 30.0,
		"%s: tlacitko PAUZA v pruhu je male %.0fx%.0f px" % [tag, l.hud_pause.size.x, l.hud_pause.size.y])
	_check(l.hud_pause.position.x >= -0.5 and l.hud_pause.end.x <= l.hud_menu.position.x + 0.5,
		"%s: tlacitka PAUZA a MENU se prekryvaji (nebo pauza preleza displej)" % tag)
	_check(l.hud_pause.end.y <= l.bar_h + 0.5, "%s: tlacitko PAUZA preleza do plochy" % tag)
	# PAUZA JE CTVEREC S IKONOU (Jan, Oct 2026: "Tlačítko Pause nebude mít text
	# ale velkou ikonu."). Hlida se TVAR. Na nizkych (na lezato) se do pruhu
	# nevejde ctverec 44 px, tak se drzi aspon PRSTENI MINIMUM - proto se
	# pripousti 11 px rozdil; zaklad je ale vzdy vyska, nikdy popisek.
	_check(absf(l.hud_pause.size.x - l.hud_pause.size.y) < 11.0,
		"%s: tlacitko PAUZA neni ctverec (%.0fx%.0f px)" % [tag, l.hud_pause.size.x, l.hud_pause.size.y])
	_check(l.hud_pause.size.x < l.measure_px("POKRAČOVAT", l.font_px),
		"%s: sirka tlacitka PAUZA se porad meri z popisku" % tag)
	_check(l.bar_text_w > 0.0, "%s: stavovemu textu nezustalo v pruhu misto" % tag)
	var l1: String = ScreenLayout.HUD_LINE1_FMT % [12, 5, 5]
	var l2: String = ScreenLayout.HUD_LINE2_FMT % [300, 300, 9999]
	var px1: int = _fit_px(l1, l.bar_text_w, l.font_px)
	var px2: int = _fit_px(l2, l.bar_text_w, l.font_px)
	_check(px1 >= 11 and px2 >= 11, "%s: stavovy text v pruhu ma jen %d/%d px" % [tag, px1, px2])

	# 4) PALETA: kazdy pocet barev, ktery muze nastat (2..5). Pruh palety uz NENI
	# u spodniho okraje - je NAD panelem s upgrady (`pal_top`).
	for count in range(2, 6):
		var rects: Array = l.layout_palette(count)
		_check(rects.size() == count, "%s: paleta pro %d barev nema %d tlacitek" % [tag, count, count])
		for r in rects:
			var rr: Rect2 = r
			_check(rr.position.y >= l.pal_top - 0.5 and rr.end.y <= l.pal_top + l.pal_h + 0.5,
				"%s: tlacitko barvy (%d) neni v pruhu palety" % [tag, count])
			_check(rr.end.y <= l.shop_panel.position.y - 0.5,
				"%s: tlacitko barvy (%d) leze pod panel s upgrady" % [tag, count])
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

	# 5) PANEL S UPGRADY V BITVE: MRIZKA DVOU BUNEK NA RADEK, TRVALE OTEVRENY
	# U SPODNIHO OKRAJE. Paleta je nad nim a HERNI PLOCHA KONCI NAD PALETOU -
	# poutnici nikdy nechodi pod panel (hrac by je nevidel).
	l.set_shop_shape(3, 4)
	_check(l.shop_panel.end.y <= v.y - 0.5, "%s: panel upgradu nedrzi spodni okraj" % tag)
	_check(v.y - l.shop_panel.end.y <= maxf(8.0, v.y * 0.012) + 0.5,
		"%s: mezi panelem a spodnim okrajem zustala dira %.0f px" % [tag, v.y - l.shop_panel.end.y])
	_check(l.shop_panel.position.y >= l.bar_h - 0.5, "%s: panel upradu preleza displej" % tag)
	_check(l.pal_top <= l.shop_panel.position.y - 0.5,
		"%s: paleta neni nad panelem s upgrady" % tag)
	_check(l.arena.end.y <= l.pal_top + 0.5,
		"%s: herni plocha leze do palety nebo pod panel (%.0f > %.0f)" % [tag, l.arena.end.y, l.pal_top])
	_check(l.arena.position.y >= l.bar_h - 0.5, "%s: herni plocha leze do horniho pruhu" % tag)
	_check(l.shop_tabs.size() == 3, "%s: v bitve nejsou tri kategorie (%d)" % [tag, l.shop_tabs.size()])
	_check(l.shop_cells.size() == 4, "%s: panel nema ctyri bunky (%d)" % [tag, l.shop_cells.size()])
	for t in l.shop_tabs:
		var tr: Rect2 = t
		_check(tr.size.y >= ScreenLayout.TAB_MIN - 0.5 and tr.size.x >= 44.0,
			"%s: tab kategorie je maly %.0fx%.0f" % [tag, tr.size.x, tr.size.y])
		_check(l.shop_panel.encloses(tr), "%s: tab kategorie neni v panelu" % tag)
	_check_icons(l.shop_tabs, l.shop_tab_icons, tag, "bitve")
	for i in range(l.shop_cells.size()):
		var br: Rect2 = l.shop_cells[i]
		_check(br.size.x >= 56.0 and br.size.y >= ScreenLayout.CELL_MIN_H - 0.5,
			"%s: bunka upgradu je mala %.0fx%.0f px" % [tag, br.size.x, br.size.y])
		_check(l.shop_panel.encloses(br), "%s: bunka upgradu neni v panelu" % tag)
		for t in l.shop_tabs:
			_check(not br.intersects(t as Rect2), "%s: bunka upgradu prekryva taby" % tag)
	for i in range(l.shop_cells.size()):
		for j in range(i + 1, l.shop_cells.size()):
			_check(not (l.shop_cells[i] as Rect2).intersects(l.shop_cells[j] as Rect2),
				"%s: bunky upgradu se prekryvaji" % tag)
	# DVE BUNKY NA RADEK: prvni dve museji byt na stejne vysce vedle sebe.
	var c0: Rect2 = l.shop_cells[0]
	var c1: Rect2 = l.shop_cells[1]
	_check(absf(c0.position.y - c1.position.y) < 0.5 and c1.position.x > c0.end.x - 0.5,
		"%s: prvni dve bunky nejsou dve na radku" % tag)
	_check(absf(c0.size.x - c1.size.x) < 0.5, "%s: bunky v rade nemaji stejnou sirku" % tag)
	# TEXT SE MUSI VEJIT DO BUNKY: nazev nahore, pod nim hodnota a cena na TOM
	# SAMEM radku (cena ma 45 % vnitrni sirky, hodnota zbytek).
	var text_w: float = c0.size.x - 2.0 * maxf(8.0, c0.size.x * 0.05)
	var longest: String = "Kritické poškození"
	var lpx: int = _fit_px(longest, text_w, l.font_px)
	_check(lpx >= 10, "%s: nazev parametru ma v bunce jen %d px" % [tag, lpx])
	var pr_room: float = maxf(24.0, text_w * 0.45)
	var cpx: int = _fit_px("+1000 zl.", pr_room, l.font_px)
	_check(cpx >= 9, "%s: cena v bunce ma jen %d px" % [tag, cpx])
	var vl_room: float = maxf(10.0, text_w - _font_w("+1000 zl.", cpx) - 8.0)
	_check(_fit_px("1,00 s", vl_room, l.font_px) >= 10,
		"%s: hodnota parametru se do bunky nevejde" % tag)

	# 3b) ZRYCHLENI HRY: tlacitko je v pruhu JEN kdyz si hrac koupil special.
	# Kdyz neni, jeho misto dostane stavovy text (proto se to hlida i tady).
	l.set_speed_visible(true)
	_check(l.hud_speed.size.x >= 44.0 and l.hud_speed.size.y >= 30.0,
		"%s: tlacitko tempa je male %.0fx%.0f px" % [tag, l.hud_speed.size.x, l.hud_speed.size.y])
	_check(l.hud_speed.position.x >= -0.5 and l.hud_speed.end.x <= l.hud_pause.position.x + 0.5,
		"%s: tlacitko tempa preleza displej nebo se prekryva s pauzou" % tag)
	_check(l.hud_speed.end.y <= l.bar_h + 0.5, "%s: tlacitko tempa preleza do plochy" % tag)
	_check(l.bar_text_w > 0.0, "%s: po pridani tlacitka tempa nezustalo misto na stavovy text" % tag)
	l.set_speed_visible(false)
	_check(l.hud_speed.size.x <= 0.0,
		"%s: tlacitko tempa je v pruhu, i kdyz si hrac special nekoupil" % tag)

	# 6) OBRAZOVKA UPRAVY V MENU: ctyri kategorie + mrizka + ZPET.
	_check(l.upg_tabs.size() == Upgrades.CATEGORIES.size(),
		"%s: v menu neni %d kategorii (%d)" % [tag, Upgrades.CATEGORIES.size(), l.upg_tabs.size()])
	l.set_upg_shape(4)
	_check(l.upg_cells.size() == 4, "%s: obrazovka uprav nema ctyri bunky (%d)" % [tag, l.upg_cells.size()])
	_check(l.upg_back.size.x >= 44.0 and l.upg_back.size.y >= 44.0,
		"%s: tlacitko ZPET je male" % tag)
	_check(l.upg_panel.position.y >= -0.5 and l.upg_back.end.y <= v.y + 0.5,
		"%s: obrazovka uprav preleza displej" % tag)
	_check_icons(l.upg_tabs, l.upg_tab_icons, tag, "upravach")
	# NADPIS I POZNAMKA MUSI ZUSTAT NAD PANELEM - jinak je mrizka prekryje.
	_check(l.upg_note_y >= -0.5 and l.upg_note_y <= l.upg_panel.position.y,
		"%s: poznamka profilu leze do panelu uprav (%.0f > %.0f)"
		% [tag, l.upg_note_y, l.upg_panel.position.y])
	for b in l.upg_cells:
		var bb: Rect2 = b
		_check(bb.size.x >= 56.0 and bb.size.y >= ScreenLayout.CELL_MIN_H - 0.5,
			"%s: bunka v upravach je mala %.0fx%.0f" % [tag, bb.size.x, bb.size.y])
		_check(l.upg_panel.encloses(bb), "%s: bunka uprav neni v panelu" % tag)
	# TLACITKA V LEVELU JSOU NIZSI NEZ V MENU: v levelu stoji na obrazovce PORAD,
	# takze kazdy pixel vysky ubere hraci plose (Jan, Oct 2026). V menu je mista
	# dost a zmenseni by tam bylo jen na skodu.
	_check(l.shop_cells.size() > 0 and l.upg_cells.size() > 0,
		"%s: chybi bunky pro srovnani vysky" % tag)
	if l.shop_cells.size() > 0 and l.upg_cells.size() > 0:
		var lvl_h: float = (l.shop_cells[0] as Rect2).size.y
		var menu_h: float = (l.upg_cells[0] as Rect2).size.y
		_check(lvl_h < menu_h - 1.0,
			"%s: tlacitka v levelu nejsou nizsi nez v menu (%.0f vs %.0f px)" % [tag, lvl_h, menu_h])

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
	var palette: Array = Hue.palette_at(99)
	for h in [Hue.RED, Hue.YELLOW, Hue.BLUE, Hue.GREEN]:
		_check(palette.has(h), "%s: barva %s neni v palete" % [tag, Hue.name_of(h)])
		# U LASERU JE TTK PROSTY: zivoty delene poskozenim za sekundu.
		var ttk: float = g.hp_for(g.kolo(), 1, h) / g.laser_dps()
		var window: float = g.range_frac() * Game.TRAVEL_S / Hue.speed_mult(h)
		_check(ttk < window,
			"%s: %s nema v dostrelu cas na zabiti (%.2f s v ohne, potreba %.2f s)"
			% [tag, Hue.name_of(h), window, ttk])

	# 10) VYBER LEVELU: dlazdice se vejdou na displej, jsou dost velke na prst,
	# neprekryvaji se, nadpis s stazem profilu stoji nad nimi a mezi sipkami
	# zustava misto na "1 / 2".
	l.set_levels(14, 0)
	_check(l.lvl_tiles.size() == ScreenLayout.LVL_PER_PAGE,
		"%s: prvni stranka nema %d dlazdic (%d)" % [tag, ScreenLayout.LVL_PER_PAGE, l.lvl_tiles.size()])
	var first_y: float = 1.0e9
	for i in range(l.lvl_tiles.size()):
		var tr: Rect2 = l.lvl_tiles[i]
		first_y = minf(first_y, tr.position.y)
		_check(tr.size.x >= 44.0 and tr.size.y >= 44.0,
			"%s: dlazdice levelu je mala na prst (%.0fx%.0f)" % [tag, tr.size.x, tr.size.y])
		_check(tr.position.x >= -0.5 and tr.end.x <= v.x + 0.5
			and tr.position.y >= -0.5 and tr.end.y <= v.y + 0.5,
			"%s: dlazdice levelu preleza displej" % tag)
		for j in range(i + 1, l.lvl_tiles.size()):
			_check(not tr.intersects(l.lvl_tiles[j] as Rect2), "%s: dlazdice levelu se prekryvaji" % tag)
	_check(l.lvl_title_y >= 0.0 and l.lvl_note_y + float(l.menu_sub_px) * 1.4 <= first_y,
		"%s: nadpis vyberu levelu preleza do dlazdic" % tag)
	_check(l.lvl_tiles[0].position.y >= l.lvl_note_y and l.lvl_prev.position.y > l.lvl_tiles[l.lvl_tiles.size() - 1].end.y,
		"%s: sipky na stranky nejsou pod dlazdicemi" % tag)
	# VYHRANY LEVEL = ZELENY ramecek + ZELENA FAJFKA (Jan, Oct 2026: "Hotové
	# levely budou mít zelený Border a zelenou fajfku"). Kresleni se testem
	# nezmeri, hlida se MISTO VOLANI ve zdroji obrazovky - stejna strazce jako
	# u ostatnich obrazovek. Barva NESMI byt jedina znacka: fajfka je i TVAR.
	_check(_src().contains("_check_mark("),
		"vyhrany level nema fajfku (v obrazovce chybi _check_mark)")
	_check(_src().contains("WON_GREEN"),
		"vyhrany level nema zeleny ramecek (chybi WON_GREEN)")
	_check(_src().contains("if done:") and _src().contains("_check_mark(r)"),
		"fajfka se nekresli ve vetvi vyhraneho levelu (popisek zustal)")
	# FAJFKA SE DA ZMERIT: `check_mark_points` vraci tri body, takze se hlida
	# TVAR (prostredni bod je dole, pravy nahore - to je fajfka, ne strecha),
	# ze se vejde do dlazdice a ze je dost velka na precteni.
	var MARK_S: GDScript = load("res://scripts/game_view.gd")
	var mark: Node2D = MARK_S.new()
	var wg: Color = MARK_S.get_script_constant_map()["WON_GREEN"]
	_check(wg.g > wg.r and wg.g > wg.b, "WON_GREEN neni zelena (%.2f/%.2f/%.2f)" % [wg.r, wg.g, wg.b])
	var pts: Array = mark.call("check_mark_points", l.lvl_tiles[0] as Rect2)
	_check(pts.size() == 3, "fajfka nema tri body (%d)" % pts.size())
	if pts.size() == 3:
		var a: Vector2 = pts[0]
		var b: Vector2 = pts[1]
		var c: Vector2 = pts[2]
		_check(a.x < b.x and b.x < c.x, "fajfka nejde zleva doprava")
		_check(b.y > a.y and b.y > c.y, "prostredni bod fajfky neni dole (neni to fajfka)")
		var tr: Rect2 = l.lvl_tiles[0] as Rect2
		for p in pts:
			_check(tr.grow(-1.0).has_point(p), "fajfka preleza z dlazdice %.0fx%.0f" % [tr.size.x, tr.size.y])
		_check(c.x - a.x >= tr.size.y * 0.30,
			"fajfka je mala (%.0f px na dlazdici %.0f px)" % [c.x - a.x, tr.size.y])
	mark.free()
	_check(l.lvl_next.position.x - l.lvl_prev.end.x > l.measure_px("1 / 2", l.menu_sub_px) + 8.0,
		"%s: mezi sipkami neni misto na cislo stranky" % tag)
	_check(l.lvl_prev.position.x >= -0.5 and l.lvl_next.end.x <= v.x + 0.5
		and l.lvl_back.position.x >= -0.5 and l.lvl_back.end.x <= v.x + 0.5,
		"%s: sipky nebo ZPET prelezaji displej" % tag)
	_check(l.lvl_prev.end.y <= l.lvl_back.position.y + 0.5,
		"%s: sipky na stranky preleza ZPET" % tag)
	_check(l.lvl_back.end.y <= v.y + 0.5, "%s: ZPET je pod spodnim okrajem" % tag)
	l.set_levels(1, 0)
	_check(l.lvl_tiles.size() == 1, "%s: jeden odemceny level nema jednu dlazdici" % tag)


func _fits(s: String, width: float, px: int) -> bool:
	return ThemeDB.fallback_font.get_string_size(
		s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x <= width


func _fit_px(s: String, width: float, max_px: int, min_px: int = 10) -> int:
	var px: int = max_px
	while px > min_px and not _fits(s, width, px):
		px -= 1
	return px


func _font_w(s: String, px: int) -> float:
	return ThemeDB.fallback_font.get_string_size(
		s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x


# IKONA KATEGORIE SEDI VE SVEM TABU: ctverec, uprostred, dost velky na precteni
# a stejne velky ve vsech tabech (jinak by sada vypadala rozhozeně).
func _check_icons(tabs: Array, icons: Array, tag: String, kde: String) -> void:
	_check(icons.size() == tabs.size(),
		"%s: v %s chybi ikony kategorii (%d z %d)" % [tag, kde, icons.size(), tabs.size()])
	if icons.size() != tabs.size() or tabs.is_empty():
		return
	var side: float = -1.0
	for i in range(tabs.size()):
		var ir: Rect2 = icons[i]
		var tr: Rect2 = tabs[i]
		_check(absf(ir.size.x - ir.size.y) < 0.5,
			"%s: ikona kategorie v %s neni ctverec (%.0fx%.0f)" % [tag, kde, ir.size.x, ir.size.y])
		_check(ir.size.x >= 18.0 and ir.size.x <= tr.size.x - 8.0,
			"%s: ikona kategorie v %s je moc velka nebo moc mala (%.0f px)" % [tag, kde, ir.size.x])
		# IKONA MA BYT VIDET, NE HADAT (Jan, Oct 2026: "Ikony tlačítek
		# kategorií upgradu jsou stále příliš malé."). Bere 90 % vysky tabu,
		# takze se hlida, ze ji nikdo zase nezmensi pod 85 %.
		_check(ir.size.x >= 44.0,
			"%s: ikona kategorie v %s je mala (%.0f px) - Jan ji chce velkou" % [tag, kde, ir.size.x])
		_check(ir.size.x >= tr.size.y * 0.85,
			"%s: ikona kategorie v %s nevyplnuje tab (%.0f z %.0f px)" % [tag, kde, ir.size.x, tr.size.y])
		_check(tr.encloses(ir), "%s: ikona kategorie v %s preleza tab" % [tag, kde])
		_check((ir.get_center() - tr.get_center()).length() < 1.0,
			"%s: ikona kategorie v %s neni uprostred tabu" % [tag, kde])
		if side < 0.0:
			side = ir.size.x
		_check(absf(ir.size.x - side) < 0.5,
			"%s: ikony kategorii v %s nemaji stejnou velikost" % [tag, kde])


# TABY KATEGORII MAJI IKONY A VSECHNY CTYRI SOUBORY EXISTUJI (Jan, Oct 2026:
# "tlacitka kategorii nahradit obrázky. Ikonami"). Hlida se MISTO VOLANI ve
# zdroji: kdyby se kresleni ikony zahodilo, v testech rozvrzeni to nepoznas -
# obdelnik tabu zustane stejny a jen se do nej prestane neco kreslit.
func _test_tabs_are_icons() -> void:
	var src: String = _src()
	var start: int = src.find("func _draw_card")
	_check(start >= 0, "kresleni tabu (_draw_card) ve zdroji neexistuje")
	if start >= 0:
		var end: int = src.find("\nfunc ", start + 1)
		var body: String = src.substr(start, (end - start) if end > start else 1500)
		_check(body.contains("_cat_icon("), "taby kategorii nekresli ikony")
		_check(body.contains("draw_texture_rect(tex"), "ikona kategorie se nekresli jako textura")
		_check(src.contains("cat_icon_paths"), "v obrazovce chybi tabulka ikon kategorii")
	for row in Upgrades.CATEGORIES:
		var id: String = String(row["id"])
		_check(FileAccess.file_exists("res://assets/ui/cat_%s.png" % id),
			"chybi soubor s ikonou kategorie %s (res://assets/ui/cat_%s.png)" % [id, id])
	# BARVY KATEGORII (Jan, Oct 2026: "Meč červeny. Štít modrý. Ekonomika žlutá.
	# Speciál fialový."). Ocekavana barva je tady NAPSANA, ne opsana z obrazovky -
	# jinak by test prosel i s prehozenymi barvami.
	var gv: Node2D = (load("res://scripts/game_view.gd") as GDScript).new()
	var want: Dictionary = {
		Upgrades.CAT_OFF: Hue.color_of(Hue.RED),
		Upgrades.CAT_DEF: Hue.color_of(Hue.BLUE),
		Upgrades.CAT_ECO: Hue.color_of(Hue.YELLOW),
		Upgrades.CAT_SPEC: Hue.color_of(Hue.VIOLET),
	}
	var cols: Dictionary = gv.get("cat_icon_colors")
	var names: Dictionary = {
		Upgrades.CAT_OFF: "mec", Upgrades.CAT_DEF: "stit",
		Upgrades.CAT_ECO: "ekonomika", Upgrades.CAT_SPEC: "special",
	}
	for id in want:
		var have: Color = cols.get(id, Color(0, 0, 0))
		_check(have.is_equal_approx(want[id]),
			"ikona (%s) nema predepsanou barvu (%.2f/%.2f/%.2f misto %.2f/%.2f/%.2f)"
			% [names[id], have.r, have.g, have.b, want[id].r, want[id].g, want[id].b])
	# IKONA MUSI VYPLNIT RAMEČEK. Mec byl tenky (26 % sirky) a hralo to jako
	# "prilis maly" - hlida se, ze inkoust zabira aspon 55 % kazde strany.
	# A mec je pod 45 stupnu DOPRAVA: korelace inkoustu je vyrazne zaporna
	# (cara "/"), stojici mec ma nulu (0,02).
	var paths: Dictionary = gv.get("cat_icon_paths")
	for id in want:
		var img: Image = _icon_image(String(paths.get(id, "")))
		_check(img != null, "ikonu kategorie %s nejde precist" % names[id])
		if img == null:
			continue
		var bb: Rect2i = _ink_box(img)
		var fw: float = float(bb.size.x) / float(img.get_width())
		var fh: float = float(bb.size.y) / float(img.get_height())
		_check(fw >= 0.55 and fh >= 0.55,
			"ikona (%s) nevyplnuje ramecek: %.0f%% x %.0f%%" % [names[id], fw * 100.0, fh * 100.0])
		var corr: float = _ink_corr(img)
		if id == Upgrades.CAT_OFF:
			_check(corr < -0.5, "mec neni sikmo doprava (korelace %.2f, ma byt pod -0.5)" % corr)
		else:
			_check(absf(corr) < 0.5, "ikona (%s) je nakrivena (korelace %.2f)" % [names[id], corr])
	gv.free()


# OBSAH IKONY: z textury se vezme obrazek. Kdyz ho textura nevyda (u importu se
# to muze stat), precte se soubor primo - test ma merit, ne se vymlouvat.
func _icon_image(path: String) -> Image:
	if path == "":
		return null
	var tex: Texture2D = load(path) as Texture2D
	if tex != null:
		var im: Image = tex.get_image()
		if im != null:
			return im
	if not FileAccess.file_exists(path):
		return null
	return Image.load_from_file(path)


# INKOUST = nepruhledne pixely. Vraci jejich obdelnik a korelaci (smer kresby).
func _ink_box(img: Image) -> Rect2i:
	var x0: int = img.get_width()
	var y0: int = img.get_height()
	var x1: int = -1
	var y1: int = -1
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.12:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < x0 or y1 < y0:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


func _ink_corr(img: Image) -> float:
	var pts: Array = []
	var sx: float = 0.0
	var sy: float = 0.0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.12:
				pts.append(Vector2(x, y))
				sx += x
				sy += y
	if pts.size() < 8:
		return 0.0
	var mx: float = sx / float(pts.size())
	var my: float = sy / float(pts.size())
	var sxy: float = 0.0
	var sxx: float = 0.0
	var syy: float = 0.0
	for p in pts:
		var dx: float = p.x - mx
		var dy: float = p.y - my
		sxy += dx * dy
		sxx += dx * dx
		syy += dy * dy
	if sxx <= 0.0 or syy <= 0.0:
		return 0.0
	return sxy / sqrt(sxx * syy)
