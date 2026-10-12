extends SceneTree

# Test HERNI LOGIKY nad novym modelem mrizky.
# Vystup: GAME_ALL_PASS=true / false
#
# Testuje to, co se neda poznat okem: ze poutnik opravdu dojde od startu
# k cili, ze vstupni usek neposkozuje, ze hracovo prepnuti zmeni trasu
# a ze cesta sama nikoho nezabije.

var fails: Array = []
var checks: int = 0


func _init() -> void:
	_run("hra se postavi", _test_setup)
	_run("cesta sama nebere", _test_path_deals_no_damage)
	_run("vez bere protikladu dvojnasobek", _test_tower_damage)
	_run("obrana zabiji", _test_defense_kills)
	_run("vlastni zivel je imunni", _test_own_element_is_free)
	_run("vez nestrili na sveho", _test_tower_skips_own_element)
	_run("stavba a vylepseni veze", _test_tower_build_and_levels)
	_run("vyber, vylepseni a prodej veze", _test_tower_select_sell)
	_run("pas kolem cest", _test_strip_rules)
	_run("typ vstupniho useku", _test_entry_type)
	_run("prepnuti vyhybky", _test_switch_changes_route)
	_run("poutnik dojde do cile", _test_reaches_exit)
	_run("vstupy v kole", _test_round_spawns)
	_run("determinismus", _test_determinism)
	_run("prohra pri zahlceni", _test_pile_up_loses)
	_run("neutralni cesta zabiji vsechny zivly", _test_neutral_lane_kills_all)
	if fails.is_empty():
		print("GAME_ALL_PASS=true (%d kontrol)" % checks)
		quit(0)
	else:
		for f in fails:
			print("  FAIL: " + str(f))
		print("GAME_ALL_PASS=false (%d kontrol)" % checks)
		quit(1)


func _run(label: String, fn: Callable) -> void:
	var before: int = checks
	fn.call()
	if checks == before:
		fails.append("test '%s' neudelal ani jednu kontrolu - spadl uvnitr" % label)


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails.append(msg)


func _new_game(lv: Level = null) -> Game:
	var g := Game.new()
	g.auto_round = false
	g.setup(Rect2(0, 0, 960, 600), 1.0, 1.0e9, lv if lv != null else Level.base())
	return g


# Najdi prvni usek s tim elementem.
func _lane_with(g: Game, element: int) -> int:
	for i in range(g.net.lane_count()):
		if g.net.lane_element(i) == element:
			return i
	return -1


# BUNKA V PASU TÉ CESTY: prostredni bunka useku posunuta o (dx,dy). Pas je
# osm okoli cesty, takze (0,1) je bunka pod cestou a (0,-1) nad ni.
func _strip_cell_on(g: Game, lane: int, dx: int, dy: int) -> Vector2i:
	var cs: Array = g.level.lane_cells(lane)
	var c: Vector2i = cs[cs.size() / 2]
	return Vector2i(c.x + dx, c.y + dy)


# VZDALENOST NA USEK, VE KTERE POUTNIK STOJI PRESNE V TÉ BUNCE. Hleda se
# v krocich, protoze se pocita z geometrie site - test tak nestoji na tom,
# ze bunka (x, y) je zrovna na nejakem hezkem nasobku delky.
func _s_at_cell(g: Game, lane: int, cell: Vector2i) -> float:
	var steps: int = 400
	for i in range(steps + 1):
		var s: float = g.net.lane_len[lane] * float(i) / float(steps)
		if g.net.cell_at(g.net.point_at(lane, s)) == cell:
			return s
	return -1.0


# PUST POUTNIKA PO CELY USEK od jeho zacatku. Vraci ho, aby se dalo merit,
# co mu zustalo ze zivota.
func _walk_lane(g: Game, lane: int, element: int) -> Enemy:
	var e: Enemy = g.debug_spawn(element)
	e.lane = lane
	e.s = 0.0
	var speed: float = maxf(e.speed, 1.0)
	g.run_for(float(g.net.lane_len[lane]) / speed * 1.2 + 0.5)
	return e


# ---------------------------------------------------------------- zaklad

func _test_setup() -> void:
	var g := _new_game()
	_check(g.level != null, "hra nema level")
	_check(g.net.lane_count() == 7, "sit ma %d useku, ceka se 7" % g.net.lane_count())
	_check(g.net.junction_count() == 2, "sit ma %d vyhybek, cekaji se 2" % g.net.junction_count())
	_check(g.switch_sel.size() == 2, "hra si nedrzi volbu pro obe vyhybky")
	_check(g.spawn_pool == [0, 1, 2, 3], "spawn_pool je %s" % str(g.spawn_pool))
	_check(g.net.entry_lane >= 0, "sit nema vstupni usek")
	_check(g.net.exit_pos.size() == 5, "sit ma %d cílu, ceka se 5" % g.net.exit_pos.size())
	# kazda vyhybka ma aspon dva vystupy a hra na ne umi klepnout
	for j in range(g.net.junction_count()):
		_check(g.net.junction_lanes[j].size() >= 2, "vyhybka %d ma malo vystupu" % j)
	# KAZDA CESTA S ELEMENTEM MA PAS; U KMENE (a tedy i u vstupu) SE NESTAVI.
	# Jan: "U kmene, vstupu, vyhybky a spojky se nestavi."
	var with_strip: int = 0
	for i in range(g.net.lane_count()):
		if g.level.lane_is_kmen(i):
			_check(g.net.strip_cells_of_lane(i) == 0,
				"u kmene (usek %d) je pas, i kdyz se tam nestavi" % i)
			continue
		_check(g.net.strip_cells_of_lane(i) > 0,
			"u useku %d neni zadna bunka pasu" % i)
		with_strip += 1
	_check(with_strip > 0, "v mape neni zadna cesta, u ktere by se dalo stavet")


# CESTA SAMA NEBERE. Jan: "Jinak cesta sama o sobě dávat poškození nebude."
# Je to zaklad celeho modelu: kdyby cesta brala, byly by veze zbytecne a hra
# by nemela zadne rozhodnuti.
func _test_path_deals_no_damage() -> void:
	var g := _new_game()
	var fire: int = _lane_with(g, Element.FIRE)
	_check(fire >= 0, "v mape neni ohnivy usek")
	if fire < 0:
		return
	var e: Enemy = _walk_lane(g, fire, Element.WATER)
	_check(e.hp >= e.max_hp - 0.001,
		"cesta sama ubrala zivoty (hp %.2f z %.2f)" % [e.hp, e.max_hp])


# VEZ BERE PODLE TABULKY. Voda na ohni (protiklad) dostane dvojnasobek, ale
# JEDNA vez prvniho levelu jeste nezabije - presne jako driv: cesta sama
# nesmi byt resenim, obrana musi byt investice.
func _test_tower_damage() -> void:
	var g := _new_game()
	g.gold = 5000
	var fire: int = _lane_with(g, Element.FIRE)
	if fire < 0:
		return
	var cell: Vector2i = _strip_cell_on(g, fire, 0, 1)
	_check(g.net.strip_has(cell), "bunka %s neni v pasu ohnive cesty" % str(cell))
	_check(g.try_build(cell), "vez do pasu nejde postavit")
	var t: Tower = g.tower_at(cell)
	_check(t != null and t.element == Element.FIRE,
		"vez v pasu ohnive cesty nema ohnivy element (%s)" %
		Level.value_name(-1 if t == null else t.element))
	var e: Enemy = _walk_lane(g, fire, Element.WATER)
	var got: float = e.max_hp - e.hp
	_check(got > 0.0, "vodni poutnik po ohnive ceste s ohnivou vezi nedostal nic")
	_check(got > t.damage() * Element.STRONG,
		"jedna rana ma byt aspon %.1f, dostal %.1f" % [t.damage() * Element.STRONG, got])
	_check(e.hp > 0.0, "jedna vez prvniho levelu nemá sama zabíjet (balance)")


# CELA OBRANA ZABIJI. Tri vodni veze pod ohnivou cestou (vez je 2 bunky od
# rady 1, takze na ohnivou cestu dosahnou) zabiji ohniveho poutnika.
func _test_defense_kills() -> void:
	var g := _new_game()
	g.gold = 5000
	var fire: int = _lane_with(g, Element.FIRE)
	var water: int = _lane_with(g, Element.WATER)
	if fire < 0 or water < 0:
		return
	var cs: Array = g.level.lane_cells(water)
	# bunky 2 radky NAD vodni cestou (rada 4 -> rada 3) kryji ohnivou cestu
	var base: Vector2i = cs[cs.size() / 2]
	var row: int = base.y - 1
	var built: int = 0
	for c in [base.x - 3, base.x, base.x + 3]:
		var cell := Vector2i(c, row)
		if g.net.strip_has(cell) and g.try_build(cell):
			built += 1
	_check(built == 3, "pod ohnivou cestou se postavily jen %d veze" % built)
	var e: Enemy = _walk_lane(g, fire, Element.FIRE)
	_check(not e.alive, "ohnivy poutnik po ohnive ceste s vodnimi vezemi neumrel (hp %.1f)" % e.hp)


func _test_own_element_is_free() -> void:
	var g := _new_game()
	g.gold = 5000
	var fire: int = _lane_with(g, Element.FIRE)
	if fire < 0:
		return
	# OHNIVE VEZE PRIMO V PASU OHNIVE CESTY na sve vlastni poutniky
	# nedosahnou: vlastni zivel je 0 %.
	for c in [11, 14, 17]:
		var cell: Vector2i = _strip_cell_on(g, fire, c - 13, 1)
		if g.net.strip_has(cell):
			g.try_build(cell)
	_check(g.tower_count() > 0, "v pasu ohnive cesty se nepostavila zadna vez")
	var e: Enemy = _walk_lane(g, fire, Element.FIRE)
	_check(e.hp >= e.max_hp - 0.01,
		"poutnik na sve vlastni ceste dostal rany od vlastnich vezi (hp %.2f z %.2f)" %
		[e.hp, e.max_hp])


# STAVBA A VYLEPSENI. Kazdy dalsi level je drazsi a o neco silnejsi
# a rychlejsi; stavet se da jen do pasu a jen jedno na bunku.
func _test_tower_build_and_levels() -> void:
	var g := _new_game()
	g.gold = 5000
	var fire: int = _lane_with(g, Element.FIRE)
	var neutral: int = _lane_with(g, Level.NEUTRAL)
	if fire < 0:
		return
	var cell: Vector2i = _strip_cell_on(g, fire, 0, 1)
	_check(g.try_build(cell), "vez do pasu nejde postavit")
	# na obsazenou bunku se nestavi druha
	_check(not g.try_build(cell), "na obsazenou bunku se postavila druha vez")
	# na cestu se nestavi
	_check(not g.try_build(Vector2i(cell.x, cell.y - 1)), "vez se postavila na cestu")
	# mimo pas se nestavi
	_check(not g.try_build(Vector2i(2, 2)), "vez se postavila mimo pas")
	# U VYHYBKY A SPOJKY JE JEDNO POLICKO VOLNE (Jan). Uzel j1 je na (6,7).
	for d in [Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(1, 1)]:
		var n := Vector2i(6 + d.x, 7 + d.y)
		_check(not g.net.strip_has(n),
			"bunka %s u vyhybky je v pasu (musi byt volna)" % str(n))
		_check(not g.try_build(n), "u vyhybky se postavila vez")

	var t: Tower = g.tower_at(cell)
	var dmg1: float = t.damage()
	var cd1: float = t.cooldown()
	var gold_before: int = g.gold
	_check(g.try_upgrade(cell), "vez nejde vylepsit")
	_check(t.level == 2, "vez po vylepseni nema level 2 (%d)" % t.level)
	_check(Tower.level_cost(2) > Tower.level_cost(1),
		"druhy level neni drazsi nez prvni")
	_check(gold_before - g.gold == Tower.level_cost(2), "vylepseni nestalo cenu 2. levelu")
	_check(t.damage() > dmg1 and t.cooldown() < cd1,
		"vylepsena vez neni silnejsi a rychlejsi (%.1f/%.2f -> %.1f/%.2f)" %
		[dmg1, cd1, t.damage(), t.cooldown()])
	_check(g.try_upgrade(cell), "vez nejde vylepsit na treti level")
	_check(not g.try_upgrade(cell), "vez jde vylepsit pres maximu")
	_check(t.level == Tower.MAX_LEVEL, "vez nema maximalni level (%d)" % t.level)
	# neutralni vez: sedivy pas bere vsem 100 %
	if neutral >= 0:
		var ncell: Vector2i = _strip_cell_on(g, neutral, 0, 1)
		if g.net.strip_has(ncell) and g.try_build(ncell):
			var nt: Tower = g.tower_at(ncell)
			_check(nt.element == Level.NEUTRAL,
				"vez v neutralnim pasu ma element %d" % nt.element)
			for el in range(Element.COUNT):
				_check(is_equal_approx(Element.tower_multiplier(el, nt.element), 1.0),
					"neutralni vez nebere zivlu %d presne 100 %%" % el)


# VEZ SE NA SVEHO NEOBRACI. Jan (Oct 2026): "Věže samozřejmě útočí pouze na
# nepřítele, který není stejného typu... Zbytečně to věži bere příležitost
# zaútočit na nepřítele, kterému poškození skutečně udělí."
# Test stoji na tom, ze v dosahu jsou OBA najednou: kdyby vez cílila sveho,
# zahodila by ranu a ten druhy by zustal bez skrabnuti.
func _test_tower_skips_own_element() -> void:
	var g := _new_game()
	g.gold = 5000
	var fire: int = _lane_with(g, Element.FIRE)
	if fire < 0:
		return
	var cell: Vector2i = _strip_cell_on(g, fire, 0, 1)
	if not g.net.strip_has(cell):
		return
	_check(g.try_build(cell), "vez do pasu nejde postavit")
	var t: Tower = g.tower_at(cell)
	if t == null:
		return
	_check(t.can_hurt(Element.WATER), "ohniva vez neumi ublizit vode")
	_check(t.can_hurt(Element.EARTH), "ohniva vez neumi ublizit zemi")
	_check(not t.can_hurt(Element.FIRE), "ohniva vez si mysli, ze ublizi ohni")
	# SEGMENT ohnive cesty, ktery je v dosahu veze (bunka hned nad pasem)
	var seg: Vector2i = Vector2i(cell.x, cell.y - 1)
	var s: float = _s_at_cell(g, fire, seg)
	_check(s >= 0.0, "na ohnivem useku neni bunka %s" % str(seg))
	if s < 0.0:
		return
	# 1) V DOSAHU JE JEN SVUJ: vez NESMI vystrelit a zustava nabita.
	var own: Enemy = g.debug_spawn(Element.FIRE)
	own.lane = fire
	own.s = s
	g.run_for(0.30)
	_check(own.hp >= own.max_hp - 0.001,
		"vez vystrelila na poutnika sveho elementu (hp %.1f z %.1f)" % [own.hp, own.max_hp])
	_check(t.shot_t <= 0.0, "vez si vystrelem na sveho vybila strelu")
	_check(t.cd <= 0.0, "vez si na sveho vybila nabijeni (cd %.2f)" % t.cd)
	# 2) PRIJDE CIZI: vez vystreli na NEJ, ne na sveho.
	var other: Enemy = g.debug_spawn(Element.WATER)
	other.lane = fire
	other.s = s
	g.run_for(0.30)
	_check(other.hp < other.max_hp - 0.001,
		"vodni poutnik v dosahu ohnive veze nedostal ránu (hp %.1f z %.1f)" %
		[other.hp, other.max_hp])
	_check(own.hp >= own.max_hp - 0.001,
		"vez si nasla svuj element, i kdyz mela ciziho")


# VEZ JE SAMOSTATNY OBJEKT: klepnutim se vybere, vylepsi a proda. Jan (Oct
# 2026): "Věže se musí chovat jako samostatné objekty. Musí být možné je
# vložit, vybrat, vylepšit a prodat."
func _test_tower_select_sell() -> void:
	var g := _new_game()
	g.gold = 5000
	var fire: int = _lane_with(g, Element.FIRE)
	if fire < 0:
		return
	var cell: Vector2i = _strip_cell_on(g, fire, 0, 1)
	if not g.net.strip_has(cell):
		return
	_check(g.try_build(cell), "vez do pasu nejde postavit")
	var t: Tower = g.tower_at(cell)
	if t == null:
		return
	_check(g.selected_tower() == t, "po postaveni neni vez vybrana")
	_check(t.spent == Tower.level_cost(1), "vez si nepamatuje investici (%d)" % t.spent)
	# KLEPNUTI NA VEZ = VYBER, NE VYLEPSENI. Kdyby klepnuti vylepsovalo,
	# nemel by hrac jak zjistit, co vez umi, a nemohl by ji prodat.
	var gold_before: int = g.gold
	var lvl: int = t.level
	g.tap_build_cell(cell)
	_check(t.level == lvl, "klepnuti na vez ji vylepsilo (ma byt vyber)")
	_check(g.gold == gold_before, "klepnuti na vez si vzalo zlato")
	_check(g.selected_tower() == null, "druhe klepnuti na vybranou vez nezrusilo vyber")
	# VYBER PRES JINOU VEZ
	g.tap_build_cell(cell)
	_check(g.selected_tower() == t, "vez se neda vybrat klepnutim")
	# VYLEPSENI Z PANELU
	var up: int = t.upgrade_cost()
	gold_before = g.gold
	_check(g.try_upgrade(cell), "vybrana vez nejde vylepsit")
	_check(t.level == 2, "vez po vylepseni nema level 2 (%d)" % t.level)
	_check(gold_before - g.gold == up, "vylepseni nestalo svoji cenu")
	_check(t.spent == Tower.level_cost(1) + up, "investice do veze nesedi (%d)" % t.spent)
	gold_before = g.gold
	# PRODEJ: vrati vetsinu investice, ale ne vsechno
	var back: int = t.sell_back()
	_check(back > 0, "prodej veze vraci nulu")
	_check(back < t.spent, "prodej vraci vic, nez hrac do veze dal (%d z %d)" % [back, t.spent])
	# PRODEJ VRACI POLOVINU INVESTICE (Jan: "Prodej vrátí 50 %.")
	_check(back == int(floor(float(t.spent) * Tower.SELL_BACK)),
		"prodej nevraci %.0f %% investice (%d z %d)" % [
			Tower.SELL_BACK * 100.0, back, t.spent])
	_check(is_equal_approx(Tower.SELL_BACK, 0.5), "prodej nevraci 50 %% (%.2f)" % Tower.SELL_BACK)
	_check(g.try_sell(cell), "vez nejde prodat")
	_check(g.tower_count() == 0, "prodana vez zustala na desce")
	_check(g.gold - gold_before == back, "prodej nepridal zlato (%d)" % (g.gold - gold_before))
	_check(g.selected_tower() == null, "po prodeji zustal vyber")
	_check(g.sel_tower.x < 0, "po prodeji zustala vybrana bunka %s" % str(g.sel_tower))
	_check(not g.try_sell(cell), "prodej prazdne bunky prosel")
	_check(not g.try_upgrade(cell), "vylepseni prazdne bunky proslo")
	# PO PRODEJI SE DA NA BUNKU POSTAVIT ZNOVU (jinak by prodej byl past)
	_check(g.try_build(cell), "po prodeji nejde na bunku postavit nova vez")
	_check(g.tower_at(cell) != null, "nova vez po prodeji nikde")


# PAS. Nikdy nelezi na ceste ani na uzlu, nikdy neni bliz nez jedno policko
# k vyhybce nebo spojce a vzdy je v mrizce. Kdyby se tohle rozbilo, hrac
# postavi vez tam, kde ji nema mit, a nikdo si toho nevsimne.
func _test_strip_rules() -> void:
	var g := _new_game()
	var clear: int = Network.STRIP_JUNCTION_CLEAR
	_check(g.net.strip_cells.size() > 0, "sit nema zadny pas")
	for cellv in g.net.strip_cells:
		var c: Vector2i = cellv
		_check(g.level.in_bounds(c.x, c.y), "bunka pasu %s je mimo mrizku" % str(c))
		_check(g.level.node_at_cell(c) < 0, "bunka pasu %s je uzel" % str(c))
		var lane: int = g.net.strip_lane_of(c)
		_check(lane >= 0, "bunka pasu %s nepatri zadne ceste" % str(c))
		for lc in g.level.lane_cells(lane):
			_check(lc != c, "bunka pasu %s lezi na ceste %d" % [str(c), lane])
		for n in range(g.level.node_count()):
			var k: int = g.level.node_kind(n)
			if k != Level.VYHYBKA and k != Level.SPOJKA:
				continue
			var nc: Vector2i = g.level.node_cell(n)
			var far: bool = absi(nc.x - c.x) > clear or absi(nc.y - c.y) > clear
			_check(far, "bunka pasu %s je u uzlu %d (ma byt jedno policko volno)" % [str(c), n])


# ---------------------------------------------------------------- hrac

func _test_switch_changes_route() -> void:
	var g := _new_game()
	var j1: int = 0
	var lane0: int = g.net.junction_lane(j1, 0)
	var lane1: int = g.net.junction_lane(j1, 1)
	_check(lane0 != lane1, "vyhybka posila na obe volby stejny usek")
	g.set_switch(lane0)
	_check(g.selected_lane(j1) == lane0, "po klepnuti na usek vyhybka neposila ten usek")
	g.set_switch(lane1)
	_check(g.selected_lane(j1) == lane1, "prepnuti na druhy usek nefunguje")
	# klepnuti na usek, ktery z zadne vyhybky nevede, nesmi nic zmenit
	var before: int = g.selected_lane(j1)
	g.set_switch(g.net.entry_lane)
	_check(g.selected_lane(j1) == before, "klepnuti na vstupni usek preplo vyhybku")


func _test_reaches_exit() -> void:
	var g := _new_game()
	var lives0: int = g.lives
	# posli poutnika na kazdou volbu prvni vyhybky a vzdy musi dojit do cile
	for k in range(g.net.junction_lanes[0].size()):
		var h := _new_game()
		h.lives = 99
		h.set_switch(h.net.junction_lane(0, k))
		var e: Enemy = h.debug_spawn(Element.WATER)
		# poutnik projde vsechny useky, dokud nedojde do cile
		var guard: int = 0
		while e.alive and guard < 4000:
			h.step(1.0 / 60.0)
			guard += 1
		_check(not e.alive, "poutnik z volby %d nikdy nedosel na konec" % k)
		_check(e.leaked, "poutnik z volby %d nedosel do cile (nezmizel spravne)" % k)
	_check(g.lives == lives0, "test si sam neco rozbil")


# ---------------------------------------------------------------- obtiznost

# ---------------------------------------------------------------- kolo

# KOLO JE CASOVE OKNO, NE POCET POUTNIKU. Jan: "Během této doby budou v
# náhodném pořadí a intervalech (min 1s, max 5s) chodit nepřátelé z
# náhodných vstupů. Po uplynutí časového limitu hra čeká na zabití všech
# nepřátel nebo porážku hráče."
#
# Test meri SKUTECNE casy vstupu (krokuje hru po 1/60 s a chyta, kdy
# `spawned` stoupne), ne konstanty - jinak by proslo i kolo s pevnou
# periodou, coz je presne to, co Jan nechtel.
func _test_round_spawns() -> void:
	var lv := Level.base()
	# Cas levelu, ne konstanta hry: kolo musi jet podle levelu.
	lv.round_time = 40.0
	# ZIVOTY: bez bonusu poutnici dojdou a hra by skoncila driv, nez by se
	# stihlo neco zmerit. Nas zajimaji VSTUPY, ne obrana.
	lv.lives = 100000
	var g := _new_game(lv)
	# DVA VSTUPY: zakladni deska ma jeden kmen, na nem by se losovani vstupu
	# nedalo poznat. Pujcime si dva indexy useku - test tim meri pravidlo
	# "vstup se losuje", ne geometrii (tu hlida test_grid).
	g.net.entry_lanes = [2, 3]
	g.start_round()
	_check(g.phase == "round", "kolo nezacalo (faze %s)" % g.phase)
	_check(absf(g.round_left - 40.0) < 0.001,
		"kolo si nevzalo cas levelu (%.1f vs 40.0)" % g.round_left)
	# PRVNI POUTNIK VSTUPUJE HNED - hrac nesmi koukat do prazdne mapy.
	g.step(1.0 / 60.0)
	_check(g.spawned == 1, "na zacatku kola nevstoupil poutnik (%d)" % g.spawned)

	var dt: float = 1.0 / 60.0
	var t: float = dt
	var times: Array = [0.0]
	var entries: Array = [0 if g.enemies.is_empty() else g.net.entry_lanes.find(
		g.enemies[g.enemies.size() - 1].lane)]
	var prev: int = g.spawned
	while t < 40.0 - dt * 0.5:
		g.step(dt)
		t += dt
		if g.spawned > prev:
			# Novy poutnik je na konci seznamu: _spawn() ho tam prida a
			# _move_enemies() poradi zachovava (v jednom kroku neumre).
			times.append(t)
			entries.append(g.net.entry_lanes.find(g.enemies[g.enemies.size() - 1].lane))
			prev = g.spawned

	_check(g.spawned >= 6, "v kole vstoupilo jen %d poutniku" % g.spawned)
	var sum: float = 0.0
	var seen: Dictionary = {}
	for i in range(1, times.size()):
		var gap: float = float(times[i]) - float(times[i - 1])
		sum += gap
		seen[int(roundf(gap * 20.0))] = true
		# ROZPETI 1-5 s. Toleruje se jeden krok: cas vstupu se meri po
		# krocich, ne presne.
		_check(gap >= Game.ROUND_GAP_MIN - dt and gap <= Game.ROUND_GAP_MAX + dt,
			"mezera %.2f s je mimo rozpeti %.0f-%.0f s" % [
				gap, Game.ROUND_GAP_MIN, Game.ROUND_GAP_MAX])
	# NEPRAVIDELNE: kdyby vsechny mezery vysly stejne, je to perioda.
	_check(seen.size() >= 3, "mezery mezi poutniky jsou porad stejne (%d hodnot)" % seen.size())
	if times.size() >= 3:
		var mean: float = sum / float(times.size() - 1)
		_check(mean > 2.0 and mean < 4.0,
			"prumerna mezera %.2f s neodpovida rozpeti 1-5 s (stred 3)" % mean)
	# VSTUP SE LOSUJE, NE STRIDA. Stridani by proslo testem na "pouzity oba
	# vstupy", ale podle vzoru se hrac pozna - tak se hlida vzor.
	var both: Dictionary = {}
	var alternating: bool = true
	for i in range(entries.size()):
		both[entries[i]] = true
		if i > 0 and entries[i] == entries[i - 1]:
			alternating = false
	_check(both.size() == 2, "poutnici nechodili z obou vstupu: %s" % str(entries))
	_check(not alternating, "vstupy se stridaji po porade: %s" % str(entries))

	# PO LIMITU UZ NIKDO NEVSTOUPI - kolo ceka, nez se deska vycisti.
	var guard: int = 0
	while g.phase == "round" and guard < 120:
		g.step(dt)
		guard += 1
	_check(g.phase == "clear", "po limitu kola faze neni docisteni (je %s)" % g.phase)
	var frozen: int = g.spawned
	if not g.enemies.is_empty():
		var gold_before: int = g.gold
		g.step(dt)
		_check(g.phase == "clear" and g.gold == gold_before,
			"kolo se uzavrelo, i kdyz jsou na desce poutnici")
	guard = 0
	while g.phase == "clear" and guard < 60 * 60:
		g.step(dt)
		guard += 1
	_check(g.phase == "build", "kolo se neuzavrelo prazdnou deskou (faze %s, %d poutniku)"
		% [g.phase, g.enemies.size()])
	_check(g.spawned == frozen and g.round == 1,
		"po konci vstupu jeste nekdo vstoupil (%d -> %d)" % [frozen, g.spawned])


# VSTUPNI USEK JE OD VYCHOZIHO STAVU KMEN, ALE JE TO NORMALNI TYP USEKU: hrac
# ho muze prepnout na element a zpet. Sedivy pas u nej bere vsem 100 %,
# barevny podle tabulky poskozeni.
func _test_entry_type() -> void:
	var g := _new_game()
	var entry: int = g.net.entry_lane
	_check(entry >= 0, "sit nema vstupni usek")
	if entry < 0:
		return
	_check(g.level.lane_is_kmen(entry), "vstupni usek neni kmen (je %s)"
		% g.level.lane_type_name(entry))
	# U KMENE A VSTUPU SE NESTAVI. Jan: "U kmene, vstupu, vyhybky a spojky
	# se nestavi." Pas tam proto vubec neni - kreslit misto, kde se neda
	# stavet, by hrace nechalo klepat do prazdna.
	g.gold = 5000
	var cell: Vector2i = _strip_cell_on(g, entry, 0, 1)
	_check(not g.net.strip_has(cell), "u vstupniho useku (kmen) je pas")
	_check(not g.try_build(cell), "u vstupu se postavila vez")

	# PREPNUTI NA ELEMENT: cesta uz je element, takze u ni pas JE a vez bere
	# podle tabulky. PO ZMENE LEVELU SE SIT STAVI ZNOVU - pas se pocita pri
	# stavbe site.
	g.level.set_lane_element(entry, Element.WATER)
	g.setup(Rect2(0, 0, 960, 600), 1.0, 1.0e9, g.level)
	g.gold = 5000
	var cell2: Vector2i = _strip_cell_on(g, g.net.entry_lane, 0, 1)
	_check(g.net.strip_has(cell2), "po prepnuti vstupniho useku na element neni pas")
	if g.net.strip_has(cell2) and g.try_build(cell2):
		var t2: Tower = g.tower_at(cell2)
		_check(t2.element == Element.WATER, "vez u vstupu nema vodni element")
		_check(is_equal_approx(Element.tower_multiplier(Element.FIRE, t2.element), 2.0),
			"ohnivy poutnik nema od vodni veze dvojnasobek")

	# ZPET NA KMEN: pas zase zmizi
	g.level.set_lane_element(entry, Level.KMEN)
	g.setup(Rect2(0, 0, 960, 600), 1.0, 1.0e9, g.level)
	_check(g.level.lane_is_kmen(g.net.entry_lane), "vstupni usek se nevratil na kmen")
	_check(not g.net.strip_has(_strip_cell_on(g, g.net.entry_lane, 0, 1)),
		"po navratu na kmen zustal u vstupu pas")


func _test_determinism() -> void:
	var a := _new_game()
	var b := _new_game()
	a.auto_round = false
	b.auto_round = false
	a.start_round()
	b.start_round()
	a.run_for(12.0)
	b.run_for(12.0)
	_check(a.enemies.size() == b.enemies.size(),
		"dve stejne hry maji jiny pocet poutniku (%d vs %d)" % [a.enemies.size(), b.enemies.size()])
	_check(a.lives == b.lives, "dve stejne hry maji jiny pocet zivotu")
	_check(a.gold == b.gold, "dve stejne hry maji jine zlato")


func _test_pile_up_loses() -> void:
	# Bez jedineho bonusu musi vlny poutniku nakonec projit - hra se da
	# prohrat a tlak je v tom, ze jich nesmi byt vic, nez hrac stiha.
	var g := _new_game()
	g.auto_round = true
	g.run_for(30.0 * 60.0)
	_check(g.lives < Level.BASE_LIVES, "bez bonusu hrac nikdy neztratil zivot")


# NEUTRALNI CESTA JE ZBRAN NA KOHOKOLI. Seda vez bere vsem presne 100 %, takze
# se na ni da položit kazdy zivl - a prave to je duvod, proc se z neutralni
# cesty dalo kdysi poslat vsechno. Spawnovani se tim uz NERIDI (Jan: "spawnovat
# se budou jen ty, co mají protiklad"), ale poskozeni plati dal a neda se
# overit jinak nez hrou.
# Test proto postavi obranu za ZAKLADNI zlato (ctyri veze) na neutralni cestu
# a pozene po ni kazdy zivel - kazdy na CERSTVE hre (spolecna hra by dalsimu
# poutnikovi pujcovala veze i zivoty toho predchoziho).
func _test_neutral_lane_kills_all() -> void:
	for el in range(Element.COUNT):
		var g := _new_game(_neutral_level())
		g.auto_round = false
		var lane: int = _lane_with(g, Level.NEUTRAL)
		_check(lane >= 0, "v mape neni neutralni usek")
		if lane < 0:
			return
		var cells: Array = []
		for cellv in g.net.strip_cells:
			var c: Vector2i = cellv
			if g.net.strip_lane_of(c) == lane:
				cells.append(c)
		cells.sort_custom(func(a, b): return a.x < b.x)
		_check(cells.size() >= 4, "u neutralni cesty je malo mista na veze (%d)" % cells.size())
		var built: int = 0
		for k in range(4):
			var idx: int = int(round(float(k) * float(cells.size() - 1) / 3.0))
			if g.try_build(cells[idx]):
				built += 1
		_check(built == 4, "za zakladni zlato se postavily %d veze, cekaji se 4" % built)
		var e: Enemy = _walk_lane(g, lane, el)
		_check(not e.alive and not e.leaked,
			"%s po neutralni ceste se ctyrmi vezmi prospel (hp %.1f z %.1f)" % [
				Element.name_of(el), e.hp, e.max_hp])


# Mapa s jednou neutralni cestou (a vstupnim kmenem). Zakladni zlato z ni dela
# merici desku pro predchozi test.
func _neutral_level() -> Level:
	var lv := Level.new()
	lv.add_node(2, 5, Level.START)
	lv.add_node(6, 5, Level.UZEL)
	lv.add_node(26, 5, Level.CIL)
	lv.add_lane(0, 1, "R R R R", Level.KMEN)
	lv.add_lane(1, 2, "R".repeat(20), Level.NEUTRAL)
	return lv
