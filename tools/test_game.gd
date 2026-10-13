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
	_run("poskozeni prijde az pri dopadu strely", _test_damage_on_impact)
	_run("strela na mrtveho cili nikoho nezrani", _test_shot_on_dead_target_hurts_nobody)
	_run("obrana zabiji", _test_defense_kills)
	_run("vlastni zivel je imunni", _test_own_element_is_free)
	_run("vez nestrili na sveho", _test_tower_skips_own_element)
	_run("stavba a vylepseni veze", _test_tower_build_and_levels)
	_run("stavba ve dvou krocich (oznacit, vybrat, Postavit)", _test_build_two_steps)
	_run("druhy poutniku (lehky, tezky)", _test_enemy_tiers)
	_run("dvojzivelny poutnik bere nevyhody obou", _test_dual_enemy)
	_run("vyber, vylepseni a prodej veze", _test_tower_select_sell)
	_run("pas kolem cest", _test_strip_rules)
	_run("stavba podle typu cesty (zivel, nebo neutralni vez)", _test_build_elements)
	_run("tecky urovne uvnitr veze", _test_tower_dots)
	_run("efekt pruchodu vyhybkou", _test_junction_flash)
	_run("typ vstupniho useku", _test_entry_type)
	_run("prepnuti vyhybky", _test_switch_changes_route)
	_run("poutnik dojde do cile", _test_reaches_exit)
	_run("vlny: pocet, poradi a mezery", _test_wave_spawns)
	_run("kazda vlna je tezsi", _test_waves_get_harder)
	_run("pocet poutniku je vlastnost levelu", _test_wave_count_is_level_data)
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
	g.auto_wave = false
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

# STAVBA VE DVOU KROCICH. Jan (Oct 2026): "Věž by se neměla postavit hned při
# prvním kliknutí na stavební půdu. Zaprvé bude na výběr více druhů věží a za
# druhé se takhle snadno postaví věž omylem. Musíme označit půdu, dostat na
# výběr věže, vybrat věž a kliknout na 'postavit'."
func _test_build_two_steps() -> void:
	var g := _new_game()
	g.gold = 5000
	var fire: int = _lane_with(g, Element.FIRE)
	if fire < 0:
		return
	var cell: Vector2i = _strip_cell_on(g, fire, 0, 1)
	_check(g.net.strip_has(cell), "zakladni deska nema pod ohnivou cestou stavebni pudu")
	if not g.net.strip_has(cell):
		return
	# 1) KLEPNUTI NA PUDU NIC NEPOSTAVI - jen ji oznaci a otevre obchod.
	_check(g.tap_build_cell(cell), "klepnuti na stavebni pudu misto neoznacilo")
	_check(g.tower_count() == 0, "vez se postavila hned pri prvnim klepnuti")
	_check(g.gold == 5000, "klepnuti na pudu si vzalo zlato")
	_check(g.build_cell == cell, "oznacene stavebni misto nesedi")
	_check(g.build_selected(), "obchod s vezemi se neotevrel")
	_check(g.selected_tower() == null, "oznaceni mista nechalo vybranou vez")
	# 2) VOLBA VEZE SE VYBERI ZVLAST A JEN Z NABIDKY. Nabidka je to, co
	# obrazovka kresli jako tlacitka - jedno misto pravdy pro obe.
	var ch: Array = g.build_choices()
	_check(ch.size() > 0, "oznacene misto nema zadnou volbu veze")
	_check(g.pick_choice(0), "volba veze nejde vybrat")
	_check(not g.pick_choice(-1), "obchod vzal volbu mimo nabidku (-1)")
	_check(not g.pick_choice(ch.size()), "obchod vzal volbu za rozsahem nabidky")
	# Cislo KIND_COUNT a tabulka KINDS se musi shodovat - je to jedine misto,
	# kde se pocet druhu opakuje (const v GDScriptu neumi KINDS.size()).
	_check(Tower.KIND_COUNT == Tower.KINDS.size(),
		"KIND_COUNT (%d) nesedi s poctem druhu (%d)" % [Tower.KIND_COUNT, Tower.KINDS.size()])
	# 3) DRUHE KLEPNUTI NA OZNACENE MISTO OBCHOD ZAVRE (jinak by klepnuti
	# na uz oznacene misto nedelalo nic)
	_check(not g.tap_build_cell(cell), "druhe klepnuti na oznacene misto nic neznamenalo")
	_check(not g.build_selected(), "druhe klepnuti nechalo obchod otevreny")
	_check(g.tower_count() == 0, "zrusena stavba neco postavila")
	_check(not g.confirm_build(), "Postavit bez oznaceneho mista proslo")
	# 4) POSTAVIT AZ NA POKYN HRACE
	g.tap_build_cell(cell)
	var before: int = g.gold
	_check(g.confirm_build(), "Postavit nepostavilo vez")
	var t: Tower = g.tower_at(cell)
	_check(t != null, "po Postavit vez nikde")
	_check(g.gold == before - Tower.kind_cost(Tower.DEFAULT_KIND, 1),
		"stavba nestala cenu druhu (%d)" % (before - g.gold))
	_check(t != null and t.kind == Tower.DEFAULT_KIND, "vez nema zvoleny druh")
	_check(t != null and t.element == g.net.strip_element(cell),
		"vez nema element sveho pasu (%d vs %d)" % [t.element, g.net.strip_element(cell)])
	_check(not g.build_selected(), "po postaveni zustal obchod otevreny")
	_check(g.selected_tower() == t, "po postaveni neni vez vybrana")
	# 5) OZNACENI JINE PUDY OBCHOD PRENESE, NIC NEPOSTAVI
	var cell2 := Vector2i(-1, -1)
	for cellv in g.net.strip_cells:
		var c: Vector2i = cellv
		if c != cell and g.tower_at(c) == null:
			cell2 = c
			break
	if cell2.x >= 0:
		g.tap_build_cell(cell2)
		_check(g.build_cell == cell2, "obchod se nepresunul na jinou pudu")
		_check(g.tower_count() == 1, "klepnuti na druhou pudu neco postavilo")
	# 6) VYBER VEZE A OBCHOD SE VZAJEMNE VYLUCUJI: na obrazovce je pro ne jen
	# jeden pruh, takze nesmi platit oba zaroven.
	g.tap_build_cell(cell)
	_check(g.selected_tower() == t, "klepnuti na postavenou vez ji nevybralo")
	_check(not g.build_selected(), "vyber veze nechal otevreny obchod s vezemi")
	# 7) MALO ZLATA: misto se oznaci (hrac vidi ceny), ale Postavit to rekne
	g.tap_build_cell(cell2)
	_check(g.build_selected(), "druhe oznaceni mista se neprovedlo")
	g.gold = 0
	_check(not g.confirm_build(), "vez se postavila bez zlata")
	_check(g.tower_count() == 1, "stavba bez zlata neco postavila")
	g.cancel_build()
	_check(g.tower_count() == 1, "zruseni stavby neco postavilo")


# DRUHY POUTNÍKŮ. Jan (Oct 2026): "Rovnou vymyslíme i další úrovně nepřátel.
# Rychlejší s menšími životy. Pomalejší s vyššími životy." Test hlida, ze
# cisla opravdu delaji to, co maji: lehky je RYCHLEJSI a ma MENE zivotu,
# tezky je POMALEJSI a ma VIC zivotu, a odmena odpovida druhu.
func _test_enemy_tiers() -> void:
	var g := _new_game()
	var basic: Enemy = g.debug_spawn(Element.FIRE, Enemy.TIER_BASIC)
	var light: Enemy = g.debug_spawn(Element.FIRE, Enemy.TIER_LIGHT)
	var heavy: Enemy = g.debug_spawn(Element.FIRE, Enemy.TIER_HEAVY)
	_check(basic != null and light != null and heavy != null, "druhy poutniku se nepodarilo spawnout")
	if basic == null or light == null or heavy == null:
		return
	_check(light.speed > basic.speed, "lehky poutnik neni rychlejsi (%.1f vs %.1f)" % [
		light.speed, basic.speed])
	_check(heavy.speed < basic.speed, "tezky poutnik neni pomalejsi (%.1f vs %.1f)" % [
		heavy.speed, basic.speed])
	_check(light.max_hp < basic.max_hp, "lehky poutnik nema mene zivotu (%.1f vs %.1f)" % [
		light.max_hp, basic.max_hp])
	_check(heavy.max_hp > basic.max_hp, "tezky poutnik nema vic zivotu (%.1f vs %.1f)" % [
		heavy.max_hp, basic.max_hp])
	_check(basic.reward() == Game.REWARD, "zakladni druh nema odmenu %d (%d)" % [
		Game.REWARD, basic.reward()])
	_check(light.reward() < basic.reward(), "lehky poutnik se vyplati vic nez zakladni")
	_check(heavy.reward() > basic.reward(), "tezky poutnik se nevyplati vic nez zakladni")
	# PRVNI DVE VLNY: CHODI JEN ZAKLADNI DRUH. Hrac se musi nejdriv
	# rozkoukat a pochopit vyhybku, nez zacne resit, co vlastne jde.
	for r in [1, 2]:
		var w: Dictionary = g.wave_counts(r)
		_check(int(w["light"]) == 0 and int(w["heavy"]) == 0 and int(w["dual"]) == 0,
			"ve vlne %d chodi i jine druhy nez zakladni" % r)
	# NOVE DRUHY PRIBYVAJI POSTUPNE: lehky ve 3. vlne, tezky v 5., dvojzivelny
	# v 7. - a od te doby uz v kazde dalsi zustavaji.
	var w3: Dictionary = g.wave_counts(3)
	var w5: Dictionary = g.wave_counts(5)
	var w7: Dictionary = g.wave_counts(7)
	_check(int(w3["light"]) > 0, "ve treti vlne nechodi lehci")
	_check(int(w3["heavy"]) == 0 and int(w3["dual"]) == 0,
		"ve treti vlne chodi druhy, ktere prijit nemaji")
	_check(int(w5["heavy"]) > 0, "v pate vlne nechodi tezci")
	_check(int(w5["dual"]) == 0, "v pate vlne chodi dvojzivelni")
	_check(int(w7["dual"]) > 0, "v sedme vlne nechodi dvojzivelni")
	for n in [8, 12, 20]:
		var w: Dictionary = g.wave_counts(n)
		_check(int(w["light"]) > 0 and int(w["heavy"]) > 0 and int(w["dual"]) > 0,
			"ve vlne %d chybi drive ohlaseny druh" % n)
	# A PLAN VLNY OPRAVDU TY DRUHY POSLE (ne ze jsou jen v tabulce).
	var kinds := {}
	for item in g.wave_plan(8):
		var row: Dictionary = item
		kinds[str(row["tier"]) + ("d" if bool(row["dual"]) else "")] = true
	_check(kinds.size() >= 4, "plan vlny 8 neposila vsechny ctyri druhy: %s" % str(kinds.keys()))


# DVOJZIVELNY POUTNIK (ohen + voda). Jan (Oct 2026): "Nepřátelé s dual
# elementem budou odteď mít naopak výhody obou elementů. Budou imuní na oba
# elementy. Hráč bude nucen použít neutrální věže na jejich zničení."
#
# Test hlida PRAVIDLO: bere MINIMUM z obou nasobku, takze je imunni na oba
# sve zivly a zbyle dva mu daji jen polovinu. (Drive to bylo maximum -
# dvojzivelny byl naopak nejzranitelnejsi.)
func _test_dual_enemy() -> void:
	var g := _new_game()
	var e: Enemy = g.debug_spawn(Element.FIRE, Enemy.TIER_BASIC, [Element.FIRE, Element.WATER])
	_check(e != null, "dvojzivelny poutnik se nepodarilo spawnout")
	if e == null:
		return
	_check(e.dual(), "poutnik nema druhy zivel")
	_check(e.element2 == Element.WATER, "druhy zivel neni voda (%d)" % e.element2)
	# IMUNITA NA OBA SVOJE ZIVLY: ani jedna z protikladnych vezi mu neublizi
	for el in [Element.FIRE, Element.WATER]:
		_check(is_equal_approx(e.mult_against(el), 0.0),
			"zivel %d bere dvojzivelnemu %.2f, ma brat 0" % [el, e.mult_against(el)])
		_check(not e.can_hurt(el), "vez zivlu %d si mysli, ze ublizi dvojzivelnemu" % el)
	# ZBYLE DVA ZIVLY berou jen polovinou
	_check(is_equal_approx(e.mult_against(Element.EARTH), 0.5),
		"země bere dvojzivelnemu jine nez 0.5 (%.2f)" % e.mult_against(Element.EARTH))
	_check(is_equal_approx(e.mult_against(Element.AIR), 0.5),
		"vzduch bere dvojzivelnemu jine nez 0.5 (%.2f)" % e.mult_against(Element.AIR))
	# NEUTRALNI VEZ JE JEDINA, KTERA HO ZNIČI PLNOU SILOU - Jan: "Hráč bude
	# nucen použít neutrální věže na jejich zničení."
	_check(is_equal_approx(e.mult_against(Tower.NEUTRAL), 1.0),
		"neutralni vez nebere dvojzivelnemu plnou silu (%.2f)" % e.mult_against(Tower.NEUTRAL))
	_check(e.can_hurt(Tower.NEUTRAL), "neutralni vez na dvojzivelneho nevystreli")
	# A VEZ to vi taky - mireni se ptá poutnika, ne sveho elementu.
	var t := Tower.new()
	t.element = Element.FIRE
	_check(not t.can_hurt(e.element), "ohniva vez si na dvojzivelneho dovoli vystrelit")
	t.element = Tower.NEUTRAL
	_check(t.can_hurt(e.element), "neutralni vez na dvojzivelneho nevystreli")
	# Jednozivelny poutnik se chova jako driv (zadna zmena pravidel)
	var one: Enemy = g.debug_spawn(Element.FIRE)
	_check(not one.dual(), "jednozivelny poutnik ma druhy zivel")
	_check(is_equal_approx(one.mult_against(Element.FIRE), 0.0),
		"ohniva vez bere ohnivemu poutnikovi neco jineho nez nulu")
	_check(not one.can_hurt(Element.FIRE), "ohniva vez si mysli, ze ublizi ohnivemu poutnikovi")
	# JMENO: v hlasce musi byt videt oba zivly
	_check(e.title() == "Oheň+Voda", "dvojzivelny poutnik se jmenuje '%s'" % e.title())
	# DVOJICE SE BERE JEN Z ZIVLU, KTERE MAPA POSILA
	g.wave = 6
	var ok: bool = true
	for i in range(50):
		var pair: Array = g._next_dual_pair()
		if pair.size() != 2:
			continue
		if not g.spawn_pool.has(int(pair[0])) or not g.spawn_pool.has(int(pair[1])):
			ok = false
	_check(ok, "dvojice zivlu obsahuje zivel, ktery mapa neposila")


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
	_check(e.hp > 0.0, "jedna vez prvního levelu nemá sama zabíjet (balance)")


# POSKOZENI PRIJDE AZ PRI DOPADU. Jan (Oct 2026): "Nepřátelé obdrží poškození
# instantně po výstřelu věže. Hra nebere v potaz dobu letu projektilu.
# Nepřítel musí obdržet poškození při impactu."
#
# Test hlida obe strany pravidla: po vystrelu jeste NIKDO nic nedostal a po
# dobe letu rana doopravdy sedne - presne jednou.
func _test_damage_on_impact() -> void:
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
	# Segment v dosahu veze: bunka hned nad pasem.
	var seg: Vector2i = Vector2i(cell.x, cell.y - 1)
	var s: float = _s_at_cell(g, fire, seg)
	if s < 0.0:
		return
	var e: Enemy = g.debug_spawn(Element.WATER)
	e.lane = fire
	e.s = s
	e.pos = g.net.point_at(e.lane, e.s)
	# Poutnik stoji: test tak meri jen dobu letu strely, ne jeho pohyb.
	e.speed = 0.0
	# JEDEN SNIMEK: vez vystrelila, ale rana je teprve na ceste.
	g.step(1.0 / 60.0)
	_check(g.shots.size() == 1, "po vystrelu leti %d strel, ceka se 1" % g.shots.size())
	_check(e.hp >= e.max_hp - 0.001,
		"poskozeni prislo uz pri vystrelu (hp %.2f z %.2f)" % [e.hp, e.max_hp])
	_check(t.cd > 0.0, "vez po vystrelu nema nabijeci dobu (cd %.2f)" % t.cd)
	# PO DOBE LETU rana sedne.
	g.run_for(Shot.FLIGHT + 0.05)
	_check(g.shots.is_empty(), "strela po dopadu zustala ve vzduchu")
	var want: float = t.damage() * Element.tower_multiplier(e.element, t.element)
	var got: float = e.max_hp - e.hp
	_check(is_equal_approx(got, want),
		"po dopadu dostal %.2f, ceka se %.2f" % [got, want])


# STRELA NA MRTVEHO CILI NIKOHO NEZRANI. Rana patri tomu poutnikovi, na
# ktereho vez vystrelila - kdyz ten cestou umre, strela vyhasi a NEPRENESE
# se na souseda. Kdyby se prenasela, hrac by dostaval rany, ktere si
# nezaslouzil, a obrana by byla silnejsi, nez rikaji cisla v panelu.
func _test_shot_on_dead_target_hurts_nobody() -> void:
	var g := _new_game()
	g.gold = 5000
	var fire: int = _lane_with(g, Element.FIRE)
	if fire < 0:
		return
	var cell: Vector2i = _strip_cell_on(g, fire, 0, 1)
	if not g.net.strip_has(cell):
		return
	_check(g.try_build(cell), "vez do pasu nejde postavit")
	var seg: Vector2i = Vector2i(cell.x, cell.y - 1)
	var s: float = _s_at_cell(g, fire, seg)
	if s < 0.0:
		return
	# DVA POUTNICI VE STEJNEM MISTE: oba v dosahu, oba stejne daleko od cile.
	# Vez si vezme prvniho z nich - a prave ten mezitim umre.
	var e: Enemy = g.debug_spawn(Element.WATER)
	e.lane = fire
	e.s = s
	e.pos = g.net.point_at(e.lane, e.s)
	e.speed = 0.0
	var mate: Enemy = g.debug_spawn(Element.WATER)
	mate.lane = fire
	mate.s = s
	mate.pos = g.net.point_at(mate.lane, mate.s)
	mate.speed = 0.0
	g.step(1.0 / 60.0)
	_check(g.shots.size() == 1, "po vystrelu leti %d strel, ceka se 1" % g.shots.size())
	var mate_hp: float = mate.hp
	# CIL UMRE DRIV, NEZ RANA DOLETI (napr. ho dorazila jina vez).
	e.alive = false
	e.hp = 0.0
	g.run_for(Shot.FLIGHT + 0.1)
	_check(g.shots.is_empty(), "strela po mrtvem cili zustala ve vzduchu")
	_check(is_equal_approx(mate.hp, mate_hp),
		"rana po mrtvem cili ubrala zivemu sousedovi (%.2f -> %.2f)" % [mate_hp, mate.hp])


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
	# U VYHYBKY A SPOJKY SE STAVI TAKY (Jan, Oct 2026: "Kolem spojek a výhybek
	# nakonec uděláme stavební plochu také."). Uzel j1 je na (6,7) a zustava
	# volny jen on sam - na nej hrac klepe, aby prepnul vyhybku.
	_check(not g.net.strip_has(Vector2i(6, 7)), "bunka uzlu vyhybky je stavebni plocha")
	for d in [Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(1, 1)]:
		var n := Vector2i(6 + d.x, 7 + d.y)
		_check(g.net.strip_has(n), "bunka %s u vyhybky neni stavebni plocha" % str(n))
		_check(g.try_build(Vector2i(n.x, n.y)), "u vyhybky se vez postavit neda")

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
	_check(g.shots.is_empty(), "vez si vystrelem na sveho vybila strelu")
	_check(t.cd <= 0.0, "vez si na sveho vybila nabijeni (cd %.2f)" % t.cd)
	# 2) PRIJDE CIZI: vez vystreli na NEJ, ne na sveho. POZOR: rana leti
	# 0,25 s, takze se na dopad musi pockat dele nez na vystrel.
	var other: Enemy = g.debug_spawn(Element.WATER)
	other.lane = fire
	other.s = s
	g.run_for(0.60)
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


# PAS. Nikdy nelezi na ceste ani na uzlu a vzdy je v mrizce. U VYHYBEK
# A SPOJEK SE STAVI TAKY (Jan, Oct 2026: "Kolem spojek a výhybek nakonec
# uděláme stavební plochu také.") - uzel sam ale zustava volny, protoze na nej
# hrac klepe (prepne vyhybku). Kdyby se tohle rozbilo, hrac postavi vez tam,
# kde ji nema mit, a nikdo si toho nevsimne.
func _test_strip_rules() -> void:
	var g := _new_game()
	_check(g.net.strip_cells.size() > 0, "sit nema zadny pas")
	for cellv in g.net.strip_cells:
		var c: Vector2i = cellv
		_check(g.level.in_bounds(c.x, c.y), "bunka pasu %s je mimo mrizku" % str(c))
		_check(g.level.node_at_cell(c) < 0, "bunka pasu %s je uzel" % str(c))
		var lane: int = g.net.strip_lane_of(c)
		_check(lane >= 0, "bunka pasu %s nepatri zadne ceste" % str(c))
		for lc in g.level.lane_cells(lane):
			_check(lc != c, "bunka pasu %s lezi na ceste %d" % [str(c), lane])
	# KOLEM VYHYBKY JE STAVEBNI PLOCHA. Uzel sam zustava volny, ale bunky
	# kolem nej (na ktere se driv nestavělo) jsou soucasti pasu.
	var around: int = 0
	for n in range(g.level.node_count()):
		if g.level.node_kind(n) != Level.VYHYBKA:
			continue
		var nc: Vector2i = g.level.node_cell(n)
		_check(not g.net.strip_has(nc), "bunka uzlu vyhybky %s je stavebni plocha" % str(nc))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if g.net.strip_has(Vector2i(nc.x + dx, nc.y + dy)):
					around += 1
	_check(around > 0, "kolem vyhybky neni ani jedna stavebni bunka")
	# a klepnuti na uzel vyhybky porad prepne vyhybku (ne stavi)
	var jn: int = int(g.net.junction_nodes[0])
	var j: int = g.net.junction_tap_at(g.net.node_world(jn), 20.0)
	_check(j == 0, "klepnuti na uzel vyhybky nevybralo vyhybku (%d)" % j)


# STAVBA PODLE TYPU CESTY. Jan (Oct 2026): "Na neutrální cestě může být pouze
# neutrální věž. Na elementární cestě může být jak věž daného elementu, tak
# i neutrální věž." Nabidka mista (`build_choices`) je zdroj pravdy pro
# obrazovku, klepnuti i stavbu: kdyby se rozesla, hrac by mackal tlacitko,
# ktere hra odmitne.
func _test_build_elements() -> void:
	var g := _new_game()
	g.gold = 5000
	# --- ELEMENTARNI CESTA: na vyber zivel cesty I neutralni vez
	var fire: int = _lane_with(g, Element.FIRE)
	_check(fire >= 0, "zakladni deska nema ohnivou cestu")
	var fcell: Vector2i = _strip_cell_on(g, fire, 0, 1)
	_check(g.net.strip_element(fcell) == Element.FIRE,
		"bunka u ohnive cesty nema ohnivy element (%d)" % g.net.strip_element(fcell))
	var fel: Array = g.build_elements(fcell)
	_check(fel.size() == 2 and fel[0] == Element.FIRE and fel[1] == Level.NEUTRAL,
		"nabidka na ohnive ceste neni [ohen, neutral] (%s)" % str(fel))
	# a) vez sveho elementu
	_check(g.try_build(fcell, Tower.DEFAULT_KIND, Element.FIRE),
		"ohniva vez na ohnive ceste nejde postavit")
	var t: Tower = g.tower_at(fcell)
	_check(t != null and t.element == Element.FIRE, "postavena vez nema element cesty")
	_check(g.try_sell(fcell), "postavenou vez nejde prodat")
	# b) NEUTRALNI VEZ NA ELEMENTARNI CESTE SMI
	_check(g.try_build(fcell, Tower.DEFAULT_KIND, Level.NEUTRAL),
		"neutralni vez na ohnive ceste nejde postavit")
	t = g.tower_at(fcell)
	_check(t != null and t.element == Level.NEUTRAL,
		"neutralni vez dostala cizi element (%s)" % (str(t.element) if t != null else "zadna vez"))
	if t == null:
		return
	_check(is_equal_approx(Element.tower_multiplier(Element.WATER, t.element), 1.0),
		"neutralni vez nebere vsem 100 %%")
	_check(g.try_sell(fcell), "neutralni vez nejde prodat")
	# c) CIZI ZIVEL SEM NESMI - a hra rekne, co tu muze stat
	_check(not g.try_build(fcell, Tower.DEFAULT_KIND, Element.WATER),
		"vodni vez na ohnive ceste prosla")
	_check(g.tower_at(fcell) == null, "odmitnuta stavba neco postavila")
	var msg: String = String(g.log[g.log.size() - 1])
	_check(msg.contains("Oheň") and msg.contains("neutrální"),
		"hlaska nerika, co tu muze stat (%s)" % msg)
	# --- NEUTRALNI CESTA: jen neutralni vez
	var neu: int = _lane_with(g, Level.NEUTRAL)
	_check(neu >= 0, "zakladni deska nema neutralni cestu")
	var ncell: Vector2i = _strip_cell_on(g, neu, 0, 1)
	_check(g.net.strip_element(ncell) == Level.NEUTRAL,
		"bunka u neutralni cesty nema neutralni element (%d)" % g.net.strip_element(ncell))
	var nel: Array = g.build_elements(ncell)
	_check(nel.size() == 1 and nel[0] == Level.NEUTRAL,
		"nabidka na neutralni ceste neni jen [neutral] (%s)" % str(nel))
	_check(not g.try_build(ncell, Tower.DEFAULT_KIND, Element.FIRE),
		"ohniva vez na neutralni ceste prosla")
	_check(String(g.log[g.log.size() - 1]).contains("neutrální věž"),
		"hlaska u neutralni cesty nerika, ze tu muze stat jen neutralni vez")
	_check(g.try_build(ncell, Tower.DEFAULT_KIND, Level.NEUTRAL),
		"neutralni vez na neutralni ceste nejde postavit")
	# --- OBCHOD: co hrac vidi, to se postavi
	var cell2: Vector2i = _strip_cell_on(g, fire, 0, -1)
	_check(g.tap_build_cell(cell2), "klepnuti na pudu neoznacilo misto")
	var ch: Array = g.build_choices()
	_check(ch.size() == 2, "obchod na elementarni ceste nabizi %d voleb, ma 2" % ch.size())
	_check(g.build_choice_index() == 0, "vychozi volba neni zvyraznena (index %d)" % g.build_choice_index())
	_check(g.pick_choice(1), "volba neutralni veze nejde vybrat")
	_check(g.build_choice_index() == 1, "po volbe nesviti druha volba")
	_check(g.confirm_build(), "Postavit nepostavilo zvolenou vez")
	var t2: Tower = g.tower_at(cell2)
	_check(t2 != null and t2.element == Level.NEUTRAL,
		"postavila se jina vez, nez hrac videl (%s)" % (str(t2.element) if t2 != null else "zadna"))


# TECKY UVNITR VEZE (uroven). Jan (Oct 2026): "Jeden - uprostřed, dva - vedle
# sebe ale stále na středu, tři - tři puntíky do trojúhelníku." Test meri
# GEOMETRII, ne barvu: pocet tecek, jejich teziste (stred veze) a to, ze
# vsechny zustanou uvnitr "strechy" - jinak by tekla barva obrysu a vez by
# vypadala jako skvrna.
func _test_tower_dots() -> void:
	var r: float = 16.0
	var rd: float = Tower.dot_radius(r)
	_check(rd > 0.0, "tecka veze nema polomer")
	for lv in range(1, Tower.MAX_LEVEL + 1):
		var offs: Array = Tower.dot_offsets(lv, r)
		_check(offs.size() == lv, "uroven %d ma %d tecek, ma mit %d" % [lv, offs.size(), lv])
		var sum := Vector2.ZERO
		for o in offs:
			var v: Vector2 = o
			sum += v
			_check(v.length() + rd <= r * 0.55,
				"tecka urovne %d utika ze strechy veze (%.2f z %.2f)" % [lv, v.length() + rd, r * 0.55])
		_check(sum.length() < 0.01, "tecky urovne %d nejsou na stredu veze (%s)" % [lv, str(sum)])
	# JEDNA = presne stred
	var one: Array = Tower.dot_offsets(1, r)
	_check(one[0] == Vector2.ZERO, "jedina tecka neni ve stredu veze (%s)" % str(one[0]))
	# DVE = vedle sebe, stejna vyska, symetricke
	var two: Array = Tower.dot_offsets(2, r)
	_check(is_equal_approx(two[0].y, two[1].y), "dve tecky nejsou ve stejne vysce")
	_check(is_equal_approx(two[0].x, -two[1].x), "dve tecky nejsou symetricke kolem stredu")
	# TRI = trojuhelnik: jedna nahore, dve dole
	var three: Array = Tower.dot_offsets(3, r)
	_check(three[0].y < three[1].y and three[0].y < three[2].y,
		"u trojuhelniku neni prvni tecka nahore")
	_check(is_equal_approx(three[1].x, -three[2].x),
		"spodni dve tecky trojuhelniku nejsou symetricke")
	# PRAVIDLA ELEMENTU PRO VEZE
	_check(Tower.NEUTRAL == Level.NEUTRAL,
		"neutralni element veze (%d) nesedi s typem neutralniho useku (%d)" % [
			Tower.NEUTRAL, Level.NEUTRAL])
	_check(Tower.allowed_elements(Level.NEUTRAL) == [Tower.NEUTRAL],
		"neutralni pas nepripousti jen neutralni vez")
	_check(Tower.allowed_elements(Element.FIRE) == [Element.FIRE, Tower.NEUTRAL],
		"elementarni pas nepripousti svuj zivel a neutralni vez")
	_check(Tower.choice_label(Tower.DEFAULT_KIND, Element.FIRE).contains("Oheň"),
		"popisek volby nema jmeno elementu")
	_check(Tower.choice_label(Tower.DEFAULT_KIND, Tower.NEUTRAL).contains("neutrální"),
		"popisek neutralni volby nema jmeno")


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


# ---------------------------------------------------------------- vlny

# VLNA MA POCET, NE CAS. Jan (Oct 2026): "Musíme tedy vrátit princip vln místo
# kol. Že každá vlna bude mít pevně daný počet nepřátel určitého typu, kteří
# budou přicházet v náhodném pořadí."
#
# Test meri SKUTECNE casy a POCET vstupu (krokuje hru po 1/60 s a chyta, kdy
# `spawned` stoupne), ne konstanty - kolo s casovym oknem by tim neproslo.
func _test_wave_spawns() -> void:
	var lv := Level.base()
	# ZIVOTY: bez obrany poutnici dojdou a hra by skoncila driv, nez by se
	# stihlo neco zmerit. Nas zajimaji VSTUPY, ne obrana.
	lv.lives = 100000
	var g := _new_game(lv)
	# DVA VSTUPY: zakladni deska ma jeden kmen, na nem by se losovani vstupu
	# nedalo poznat. Pujcime si dva indexy useku - test tim meri pravidlo
	# "vstup se losuje", ne geometrii (tu hlida test_grid).
	g.net.entry_lanes = [2, 3]
	# SEDMA VLNA ma vsechny ctyri druhy - jedine na ni se da overit i to, ze
	# se poradi druhu losuje.
	g.wave = 6
	g.start_wave()
	_check(g.wave == 7, "vlna se nepocitala (%d)" % g.wave)
	_check(g.phase == "wave", "vlna nezacala (faze %s)" % g.phase)
	var want: int = g.wave_size(7)
	_check(g.plan.size() == want,
		"plan vlny ma %d poutniku, tabulka rika %d" % [g.plan.size(), want])
	# SLOZENI SEDI NA TABULKU: pocet kazdeho druhu v planu je dany, nahodne je
	# jen poradi.
	var c: Dictionary = g.wave_counts(7)
	var got: Dictionary = {"basic": 0, "light": 0, "heavy": 0, "dual": 0}
	for item in g.plan:
		var row: Dictionary = item
		var tier: int = int(row["tier"])
		if bool(row["dual"]) and tier == Enemy.TIER_BASIC:
			got["dual"] = int(got["dual"]) + 1
		elif tier == Enemy.TIER_BASIC:
			got["basic"] = int(got["basic"]) + 1
		elif tier == Enemy.TIER_LIGHT:
			got["light"] = int(got["light"]) + 1
		else:
			got["heavy"] = int(got["heavy"]) + 1
	for key in ["basic", "light", "heavy", "dual"]:
		_check(int(got[key]) == int(c[key]),
			"v planu je %d %s, tabulka rika %d" % [int(got[key]), key, int(c[key])])

	# PRVNI POUTNIK VSTUPUJE HNED - hrac nesmi koukat do prazdne mapy.
	var dt: float = 1.0 / 60.0
	g.step(dt)
	_check(g.spawned == 1, "na zacatku vlny nevstoupil poutnik (%d)" % g.spawned)

	var t: float = dt
	var times: Array = [0.0]
	var order: Array = [_kind_key(g)]
	var entries: Array = [0 if g.enemies.is_empty() else g.net.entry_lanes.find(
		g.enemies[g.enemies.size() - 1].lane)]
	var prev: int = g.spawned
	while g.spawning() and t < 600.0:
		g.step(dt)
		t += dt
		if g.spawned > prev:
			# Novy poutnik je na konci seznamu: _spawn() ho tam prida a
			# _move_enemies() poradi zachovava (v jednom kroku neumre).
			times.append(t)
			order.append(_kind_key(g))
			entries.append(g.net.entry_lanes.find(g.enemies[g.enemies.size() - 1].lane))
			prev = g.spawned

	# POCET JE PEVNY. Tohle je jadro cele zmeny: vlna posle presne to, co ma
	# v tabulce - ne "kolik se jich vejde do casoveho okna".
	_check(g.spawned == want, "vstoupilo %d poutniku, tabulka rika %d" % [g.spawned, want])
	_check(times.size() == want, "casu vstupu je %d, poutniku %d" % [times.size(), want])

	# ROZPETI MEZER 1-5 s. Toleruje se jeden krok: cas vstupu se meri po
	# krocich, ne presne.
	var sum: float = 0.0
	var seen: Dictionary = {}
	for i in range(1, times.size()):
		var gap: float = float(times[i]) - float(times[i - 1])
		sum += gap
		seen[int(roundf(gap * 20.0))] = true
		_check(gap >= Game.WAVE_GAP_MIN - dt and gap <= Game.WAVE_GAP_MAX + dt,
			"mezera %.2f s je mimo rozpeti %.0f-%.0f s" % [
				gap, Game.WAVE_GAP_MIN, Game.WAVE_GAP_MAX])
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

	# PORADI DRUHU JE NAHODNE: kdyby se druhy lepily do bloku (vsechny
	# zakladni, pak lehci...), hrac by vlnu precetl predem.
	var sorted_order: Array = order.duplicate()
	sorted_order.sort()
	_check(order != sorted_order, "druhy vstupuji v poradi tabulky: %s" % str(order))

	# PO KONCI PLANU UZ NIKDO NEVSTOUPI - vlna ceka, nez se deska vycisti.
	_check(g.phase == "clear", "po poslednim vstupu faze neni docisteni (je %s)" % g.phase)
	var frozen: int = g.spawned
	var gold_before: int = g.gold
	var guard: int = 0
	while g.phase == "clear" and guard < 60 * 60:
		g.step(dt)
		guard += 1
	_check(g.phase == "build", "vlna se neuzavrela prazdnou deskou (faze %s, %d poutniku)"
		% [g.phase, g.enemies.size()])
	_check(g.spawned == frozen and g.wave == 7,
		"po konci vstupu jeste nekdo vstoupil (%d -> %d)" % [frozen, g.spawned])
	# ODRAZENA VLNA PLATI ZLATO: i hrac, ktery vsechno nezastavil, dostane na
	# dalsi obranu (jinak je z jednoho spatneho rozhodnuti odsouzeny).
	_check(g.gold > gold_before, "odrazena vlna nedala zadne zlato (%d -> %d)"
		% [gold_before, g.gold])


# DRUH POUTNIKA JAKO KLIC PRO POROVNANI PORADI ("basic", "light", "heavy",
# "dual"). Zakladni a dvojzivelny maji stejny tier, takze se rozlisuji
# priznakem - jinak by test tvrdil, ze poradi je nahodne, i kdyby nebylo.
func _kind_key(g: Game) -> String:
	if g.enemies.is_empty():
		return "?"
	var e: Enemy = g.enemies[g.enemies.size() - 1]
	if e.dual():
		return "dual"
	if e.tier == Enemy.TIER_LIGHT:
		return "light"
	if e.tier == Enemy.TIER_HEAVY:
		return "heavy"
	return "basic"


# KAZDA VLNA JE O TROCHU TEZSI NEZ TA PREDCHOZI. Jan: "Každá vlna bude buď
# více nepřátel, nebo přibude nový typ. zkrátka každá vlna musí být o trochu
# těžší než ta předchozí."
#
# "Tezsi" se meri SOUCTEM ZIVOTU, ne poctem: tezky poutnik ma 2,2x zivoty
# zakladniho, takze vlna o stejnem poctu poutniku muze byt tezsi. Pocita se
# z DAT tabulky (slozeni + rust zivotu), ne hrou - do hry by se michala obrana.
func _test_waves_get_harder() -> void:
	var g := _new_game()
	var prev_hp: float = -1.0
	var prev_cnt: int = 0
	var prev_kinds: int = 0
	for n in range(1, 13):
		var c: Dictionary = g.wave_counts(n)
		var hp: float = float(c["basic"])
		hp += float(c["light"]) * Enemy.tier_hp(Enemy.TIER_LIGHT)
		hp += float(c["heavy"]) * Enemy.tier_hp(Enemy.TIER_HEAVY)
		# DVOJZIVELNY ma zivoty zakladniho (dva zivly jsou vyhoda v obrane,
		# ne vic zivotu).
		hp += float(c["dual"])
		hp *= Game.BASE_HP * pow(1.0 + Game.HP_GROWTH, float(n - 1))
		_check(hp > prev_hp, "vlna %d neni tezsi nez vlna %d (%.0f vs %.0f zivotu)"
			% [n, n - 1, hp, prev_hp])
		prev_hp = hp
		var cnt: int = g.wave_size(n)
		var kinds: int = _kinds_in(g, n)
		_check(cnt >= prev_cnt, "vlna %d ma mene poutniku nez %d (%d vs %d)"
			% [n, n - 1, cnt, prev_cnt])
		_check(cnt > prev_cnt or kinds > prev_kinds,
			"vlna %d nepridala ani poutnika, ani druh (%d poutniku, %d druhu)"
			% [n, cnt, kinds])
		prev_cnt = cnt
		prev_kinds = kinds
	# NOVE DRUHY SE OHLAZUJI POSTUPNE: prvni dve vlny zakladni, ve treti
	# pribude lehky, v pate tezky a v sedme dvojzivelny.
	_check(_kinds_in(g, 1) == 1, "prvni vlna nema jediny druh (%d)" % _kinds_in(g, 1))
	_check(_kinds_in(g, 3) == 2, "ve treti vlne nepribyl lehky (%d druhu)" % _kinds_in(g, 3))
	_check(_kinds_in(g, 5) == 3, "v pate vlne nepribyl tezky (%d druhu)" % _kinds_in(g, 5))
	_check(_kinds_in(g, 7) == 4, "v sedme vlne nepribyl dvojzivelny (%d druhu)" % _kinds_in(g, 7))


# Kolik DRUHU vlna posila (0 poutniku se nepocita).
func _kinds_in(g: Game, n: int) -> int:
	var c: Dictionary = g.wave_counts(n)
	var k: int = 0
	for key in ["basic", "light", "heavy", "dual"]:
		if int(c[key]) > 0:
			k += 1
	return k


# POCET POUTNIKU JE VLASTNOST LEVELU. `Level.wave_count` je pocet v prvni
# vlne a nasobi cely tvar rustu, takze se level da udelat tezsi i lehci.
func _test_wave_count_is_level_data() -> void:
	var lv := Level.base()
	lv.wave_count = 12
	var g := _new_game(lv)
	_check(g.wave_size(1) == 12, "dvojnasobny level neposila dvojnasobek (%d)" % g.wave_size(1))
	lv.wave_count = 3
	var g2 := _new_game(lv)
	_check(g2.wave_size(1) == 3, "polovicni level neposila polovinu (%d)" % g2.wave_size(1))
	# DO KODU LEVELU SE POCET PISE JEN KDYBY SE LISI - stara ulozena mapa musi
	# mit kod PRESNE stejny jako predtim (a nacte se z nej vychozi hodnota).
	var base := Level.base()
	_check(not base.to_code().contains("\"wc\""),
		"zakladni level pise pocet poutniku, i kdyz je vychozi")
	base.wave_count = 9
	var back := Level.from_code(base.to_code())
	_check(back != null, "level s poctem poutniku se neda nacist z kodu")
	if back != null:
		_check(back.wave_count == 9, "pocet poutniku se v kodu ztratil (%d)" % back.wave_count)


# EFEKT PO PRUCHODU VYHYBKOU. Jan (Oct 2026): "Když projde nepřítel
# výhybkou a dojde k 'rozřazení' na kolej, tak to mělo udělat nějaký drobný
# vizuální efekt. Aby hráč věděl, že už výhybkou prošel."
#
# Meri se STAV HRY (kdy efekt vznikne, kam ukazuje a kdy zmizi), ne pixely:
# obrazovka z toho jen kresli krouzek, takze se neda rozejit s hrou.
func _test_junction_flash() -> void:
	var g := _new_game()
	var entry: int = g.net.entry_lane
	_check(entry >= 0, "sit nema vstupni usek")
	if entry < 0:
		return
	var node: int = g.net.lane_end_node(entry)
	var j: int = g.net.junction_index_of_node(node)
	_check(j >= 0, "vstupni usek nekonci ve vyhybce")
	if j < 0:
		return
	# DRUHA VYHYBKA: efekt se na ni nesmi objevit, kdyz poutnik prosel prvni.
	var other: int = -1
	for k in range(g.net.junction_nodes.size()):
		if k != j:
			other = int(g.net.junction_nodes[k])
	_check(other >= 0, "zakladni deska nema dve vyhybky")
	# Volba prvni vyhybky: ohniva kolej (na tu se da poslat kazdy poutnik).
	var want: int = -1
	for lane in range(g.net.lane_count()):
		if g.net.lane_junction(lane) == j and g.level.lane_element(lane) == Element.FIRE:
			want = lane
	_check(want >= 0, "vyhybka nema ohnivou kolej")
	if want < 0:
		return
	g.set_switch(want)
	var e: Enemy = g.debug_spawn(Element.FIRE)
	_check(e != null, "poutnik se neobjevil")
	if e == null:
		return
	_check(g.junction_flash_at(node).is_empty(), "efekt sviti jeste pred pruchodem")
	var dt: float = 1.0 / 60.0
	var guard: int = 0
	while e.on_lane() and e.lane == entry and guard < 600:
		g.step(dt)
		guard += 1
	_check(e.lane == want, "poutnik odesel z vyhybky na usek %d, cekal se %d" % [e.lane, want])
	# EFEKT JE TU A UKAZUJE, KAM POUTNIK ODESEL.
	var f: Dictionary = g.junction_flash_at(node)
	_check(not f.is_empty(), "po pruchodu vyhybkou se nerozsvitil zadny efekt")
	if not f.is_empty():
		_check(int(f["lane"]) == want, "efekt ukazuje usek %d, poutnik sel na %d"
			% [int(f["lane"]), want])
		_check(float(f["k"]) > 0.5, "efekt je hned po pruchodu slaby (%.2f)" % float(f["k"]))
	_check(g.junction_flash_at(other).is_empty(),
		"efekt se rozsvitil na vyhybce, kterou poutnik neprosel")
	# A ZHASINA: po FLASH_TIME (a chvilku navic) uz nesviti.
	guard = 0
	while guard < int((Game.FLASH_TIME + 0.2) / dt):
		g.step(dt)
		guard += 1
	_check(g.junction_flash_at(node).is_empty(), "efekt po case nezmizel")


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
	a.auto_wave = false
	b.auto_wave = false
	a.start_wave()
	b.start_wave()
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
	g.auto_wave = true
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
		g.auto_wave = false
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
