extends SceneTree

# Hluboky test JADRA. Nesaha na kresleni ani na vstup - testuje pravidla.
# Vystup: CORE_ALL_PASS=true / false

var fails: Array = []
var checks: int = 0


func _init() -> void:
	_test_geometry()
	_test_element_table()
	_test_zone_damage()
	_test_neutral_lane()
	_test_own_lane_is_free_pass()
	_test_strong_and_weak_lane()
	_test_build_rule()
	_test_lane_tap_switches()
	_test_spawn_gap_is_swattable()
	_test_pile_up_loses()
	_test_economy()
	_test_wave_flow()
	_test_determinism()

	print("checks=%d fails=%d" % [checks, fails.size()])
	for f in fails:
		print("FAIL: " + str(f))
	if fails.is_empty():
		print("CORE_ALL_PASS=true")
	else:
		print("CORE_ALL_PASS=false")
	quit()


func _ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails.append(what)


func _fresh() -> Game:
	var g := Game.new()
	# Zakladni rozvrzeni, stejne jako v tele hry. `bar_top` se predava
	# build() - kdyby chybel, sit by si myslela, ze pruh neexistuje.
	g.setup(Rect2(40.0, 80.0, 880.0, 404.0), 1.0, 500.0)
	return g


func _spawn_one(g: Game, el: int) -> Enemy:
	g.phase = "wave"
	g.spawn_left = 0
	g.wave = 1
	g._spawn(el)
	var e: Enemy = g.enemies[0]
	return e


# Posun cas, dokud poutnik NEDORAZI na svuj usek. Bez toho meri testy
# jen neutralni kmen, kde se nic neposkozuje - presne to se stalo na
# prvnim behu a vypadalo to jako chyba v poskozeni.
func _run_to_lane(g: Game, e: Enemy, budget: float = 12.0) -> void:
	var t := 0.0
	while e.on_lane() == false and t < budget and e.alive:
		g.step(1.0 / 60.0)
		t += 1.0 / 60.0


# Postav n bonusu na usek. Sama cesta poutnika jen ZRANI - k zabiti je
# potreba investice, takze kazdy test, ktery chce mrtvolu, si ji koupi.
func _dress(g: Game, lane: int, n: int) -> void:
	if Network.lane_is_neutral(lane):
		return
	g.gold += 999
	for i in range(mini(n, g.net.slot_count())):
		g.try_build(lane, i, Network.lane_element(lane))


# Kolej, ktera nese dany zivel. U neutralniho pruhu vraci -1.
func _lane_of(el: int) -> int:
	for lane in range(Network.LANES):
		if Network.lane_element(lane) == el:
			return lane
	return -1


func _neutral_lane() -> int:
	for lane in range(Network.LANES):
		if Network.lane_is_neutral(lane):
			return lane
	return -1


# --------------------------------------------------------------- 1 geometrie

func _test_geometry() -> void:
	var g := _fresh()
	_ok(g.net.lane_path.size() == Network.LANES, "pet pruhu (4 elementarni + neutralni)")
	_ok(g.net.slot_count() == 3, "tri mista na bonus na usek")
	_ok(Network.LANES == Element.COUNT + 1, "ctyři zivly plus prave jeden neutralni")
	# prave jeden neutralni pruh a prave ctyři elementarni
	var neutrals := 0
	var els := {}
	for lane in range(Network.LANES):
		if Network.lane_is_neutral(lane):
			neutrals += 1
		else:
			els[Network.lane_element(lane)] = true
	_ok(neutrals == 1, "neutralni pruh je prave jeden (je jich %d)" % neutrals)
	_ok(els.size() == Element.COUNT, "kazdy zivel ma svuj pruh (%d)" % els.size())
	for lane in range(Network.LANES):
		var ln: float = g.net.lane_len[lane]
		_ok(ln > 200.0, "usek %d ma rozumnou delku (%.0f)" % [lane, ln])
		for slot in range(g.net.slot_count()):
			var p: Vector2 = g.net.slot_world(lane, slot)
			_ok(g.net.area.grow(40.0).has_point(p), "misto %d/%d je v hraci plose" % [lane, slot])
			# mista na bonus musi lezet na ROVNEM useku, kde je dmg zona
			_ok(absf(p.y - float(g.net.rows[lane])) < 0.001,
				"misto %d/%d lezi na rovném useku" % [lane, slot])
	_ok(g.net.trunk_len > 150.0, "neutralni kmen ma smysluplnou delku (%.0f)" % g.net.trunk_len)
	_ok(g.net.merge.distance_to(g.net.hub) > 10.0, "vyhybka a sberny bod jsou oddelene")
	# kazdy pruh konci ve SVEM vystupu a vystupy jsou neutralni
	_ok(g.net.exit_pos.size() == Network.EXIT_ROWS.size(), "ctyři vystupy z mapy")
	for lane in range(Network.LANES):
		var last: Vector2 = g.net.point_at(lane, g.net.lane_len[lane])
		var ex: int = g.net.lane_exit[lane]
		_ok(last.distance_to(g.net.exit_pos[ex]) < 1.0,
			"usek %d konci ve svem vystupu %d" % [lane, ex])
	# a aspon dva pruhy se v jednom vystupu SBÍHAJÍ - "cesty se sliji"
	var used := {}
	for lane in range(Network.LANES):
		var ex: int = g.net.lane_exit[lane]
		used[ex] = int(used.get(ex, 0)) + 1
	var shared := 0
	for k in used:
		if int(used[k]) > 1:
			shared += 1
	_ok(shared > 0, "aspon jeden vystup je spolecny pro vic pruhu (%d)" % shared)
	_ok(g.net.switch_lane == 0, "vyhybka startuje na prvnim pruhu")
	# ROZVRZENI: bonusy na sousednich pruhach se nesmi prekryvat.
	var gap: float = g.net.min_cross_lane_slot_distance()
	_ok(gap > g.net.bonus_r * 2.0 + 8.0,
		"mista na bonusy mezi pruhy se neprekryvaji (mezera %.0f px)" % gap)
	# a vsechna mista musi byt NAD ovladacim pruhem
	var bar_top: float = 500.0
	for lane in range(Network.LANES):
		for slot in range(g.net.slot_count()):
			var p: Vector2 = g.net.slot_world(lane, slot)
			_ok(p.y + g.net.bonus_r < bar_top,
				"misto %d/%d neleze do ovladaciho pruhu (y=%.0f)" % [lane, slot, p.y])
	for lane in range(Network.LANES):
		var path: PackedVector2Array = g.net.lane_path[lane]
		for k in range(path.size()):
			_ok(path[k].y < bar_top, "usek %d zustava nad pruhem" % lane)
		# Deska nema popisek vystupu, ale vystup SAM musi zustat nad pruhem -
		# jinak by rucka kreslila do ovladani.
		var exit_p: Vector2 = g.net.exit_pos[g.net.lane_exit[lane]]
		_ok(exit_p.y + g.net.exit_r < bar_top,
			"vystup %d zustava nad pruhem (y=%.0f)" % [lane, exit_p.y])


# --------------------------------------------------------------- 2 matice

func _test_element_table() -> void:
	_ok(Element.multiplier(Element.FIRE, Element.FIRE) == 0.0, "vlastni zivel = nula poskozeni")
	_ok(Element.multiplier(Element.FIRE, Element.WATER) == 2.0, "protiklad = dvojnasobek")
	_ok(Element.multiplier(Element.FIRE, Element.EARTH) == 0.5, "cizi zivel = polovina")
	_ok(Element.multiplier(Element.AIR, Element.EARTH) == 2.0, "protiklad plati i obracene")
	_ok(Element.multiplier(Element.WATER, Element.FIRE) == 2.0, "a pro vodu stejne")
	_ok(Element.opposite_of(Element.opposite_of(Element.FIRE)) == Element.FIRE, "protiklad je involuce")
	_ok(Element.NEUTRAL == 1.0, "neutralni usek dava presne 100 %")
	for e in range(Element.COUNT):
		# na neutralnim useku dostane KAZDY zivel stejne - to je cela pointa
		_ok(Element.lane_multiplier(e, -1, true) == 1.0,
			"zivel %d dostava na neutralnim useku 100 %%" % e)
		# slabych je prave dvojice, silny je prave jeden, vlastni jeden
		var weak: Array = Element.weak_against(e)
		_ok(weak.size() == 2, "zivel %d ma prave dva slabe (%d)" % [e, weak.size()])
		_ok(not weak.has(e), "a mezi nimi neni on sam")
		_ok(not weak.has(Element.opposite_of(e)), "ani jeho protiklad")
		for t in range(Element.COUNT):
			_ok(Element.multiplier(e, t) >= 0.0, "nasobek neni zaporny (%d,%d)" % [e, t])
			# kazda kombinace je jedna ze ctyř hodnot a soucet pres vsechny
			# elementy na jednom useku je pokazde stejny (2.0+0.5+0.5+0.0)
			var m: float = Element.multiplier(e, t)
			_ok(m == 0.0 or m == 0.5 or m == 2.0, "nasobek je z mnoziny 0/0.5/2 (%d,%d=%f)" % [e, t, m])
		var sum := 0.0
		for t in range(Element.COUNT):
			sum += Element.multiplier(e, t)
		_ok(is_equal_approx(sum, 3.0), "soucet pres vsechny pruhy je 3.0 (%d: %.1f)" % [e, sum])
	var seen := {}
	for e in range(Element.COUNT):
		_ok(not Element.name_of(e).is_empty(), "zivel %d ma jmeno" % e)
		_ok(not seen.has(Element.color_of(e)), "zivel %d ma unikatni barvu" % e)
		seen[Element.color_of(e)] = true


# --------------------------------------------------------------- 3 dmg zona

func _test_zone_damage() -> void:
	# POSKOZENI DELA CELEK USEKU: i s NULOU bonusu poutnik na elementarnim
	# useku krvaci. Kdyby to tak nebylo, hra by nebyla o vyhybce, ale o vezi.
	var g := _fresh()
	g.auto_wave = false
	g.gold = 0
	var lane: int = _lane_of(Element.opposite_of(Element.FIRE))
	_ok(g.bonuses.is_empty(), "zadny bonus postaven")
	g.set_switch(lane)
	var e: Enemy = _spawn_one(g, Element.FIRE)
	var hp0: float = e.hp
	_run_to_lane(g, e)
	g.run_for(4.0)
	_ok(e.hp < hp0, "usek poskozuje i BEZ bonusu (%.1f -> %.1f)" % [hp0, e.hp])
	# a cim dele tam je, tim vic ran - dmg zona je cas, ne jeden zasah
	var after4: float = e.hp
	g.run_for(3.0)
	_ok(e.alive and e.hp < after4, "cim dele jde po useku, tim vic dostava (%.1f -> %.1f)" % [after4, e.hp])
	# ALE sama cesta poutnika NEZABIJE. Kdyby zabila, byla by stavba
	# zbytecna a hra by nemela o cem rozhodovat.
	var g_solo := _fresh()
	g_solo.auto_wave = false
	g_solo.set_switch(lane)
	var sol: Enemy = _spawn_one(g_solo, Element.FIRE)
	_run_to_lane(g_solo, sol)
	g_solo.run_for(40.0)
	_ok(sol.hp > 0.0, "bez bonusu poutnik usek PREZIJE (hp=%.1f z %.0f)" % [sol.hp, sol.max_hp])
	_ok(sol.hp < sol.max_hp * 0.75,
		"ale dostane citelnou ranu (%.0f z %.0f)" % [sol.hp, sol.max_hp])
	_ok(g_solo.lives < Game.START_LIVES, "a dojde na vystup (zivoty %d)" % g_solo.lives)
	# bonus posiluje CELY usek, ne jen sve misto: jedna vez na useku
	# musi zvednout poskozeni na libovolnem miste useku
	var g2 := _fresh()
	g2.auto_wave = false
	g2.gold = 500
	g2.try_build(lane, 0, Network.lane_element(lane))
	_ok(g2.lane_mult(lane) > 1.0, "bonus zvedne nasobek celeho useku (%.2f)" % g2.lane_mult(lane))
	var g3 := _fresh()
	g3.auto_wave = false
	g3.gold = 500
	g3.try_build(lane, 2, Network.lane_element(lane))
	_ok(is_equal_approx(g2.lane_mult(lane), g3.lane_mult(lane)),
		"a je jedno, na ktere misto useku ho postavis (%.2f vs %.2f)" %
		[g2.lane_mult(lane), g3.lane_mult(lane)])
	# dva bonusy se nasobi a UZ ZABIJI - stavba je tedy povinna
	var g4 := _fresh()
	g4.auto_wave = false
	g4.gold = 500
	g4.try_build(lane, 0, Network.lane_element(lane))
	g4.try_build(lane, 1, Network.lane_element(lane))
	_ok(g4.lane_mult(lane) > g2.lane_mult(lane),
		"dva bonusy daji vic nez jeden (%.2f vs %.2f)" % [g4.lane_mult(lane), g2.lane_mult(lane)])
	g4.set_switch(lane)
	var e4: Enemy = _spawn_one(g4, Element.FIRE)
	_run_to_lane(g4, e4)
	g4.run_for(40.0)
	_ok(not e4.alive, "se dvema bonusy poutnik na useku UMRE (hp=%.1f)" % e4.hp)
	# bonus zvedne poskozeni na libovolnem miste useku - pocita se
	# z jedne tabulky, ne z polohy bonusu
	var g5 := _fresh()
	g5.auto_wave = false
	g5.gold = 500
	var e5: Enemy = g5.debug_spawn(Element.FIRE)
	e5.lane = lane
	e5.s = 50.0
	var base_dps: float = g5.dps_on(e5)
	_ok(base_dps > 0.0, "zakladni dmg zona neco dava (%.2f)" % base_dps)
	g5.try_build(lane, 2, Network.lane_element(lane))
	e5.s = g5.net.lane_len[lane] - 50.0
	var far_dps: float = g5.dps_on(e5)
	_ok(far_dps > base_dps,
		"a bonus ji zvedne i na druhem konci useku (%.2f -> %.2f)" % [base_dps, far_dps])


# --------------------------------------------------------------- 4 neutralni

func _test_neutral_lane() -> void:
	var nl: int = _neutral_lane()
	_ok(nl >= 0, "neutralni usek existuje (%d)" % nl)
	# na neutralni usek NELZE postavit nic - nema co posilovat
	var g := _fresh()
	g.auto_wave = false
	g.gold = 9999
	for el in range(Element.COUNT):
		_ok(not g.try_build(nl, 0, el),
			"na neutralni usek nelze postavit bonus %s" % Element.name_of(el))
	_ok(g.bonus_at(nl, 0) == null, "a nic tam nestoji")
	_ok(g.gold == 9999, "a zlato zustalo nedotcene (%d)" % g.gold)
	_ok(not Network.lane_accepts(nl, 0), "pravidlo je v siti, ne jen v herni logice")
	# a poskozuje VSECHNY stejne - to je jeho smysl
	var g2 := _fresh()
	g2.auto_wave = false
	g2.set_switch(nl)
	var hps := {}
	for el in range(Element.COUNT):
		var h := _fresh()
		h.auto_wave = false
		h.set_switch(nl)
		var e: Enemy = _spawn_one(h, el)
		_run_to_lane(h, e)
		h.run_for(4.0)
		_ok(e.hp < e.max_hp, "na neutralnim useku dostava zivel %s poskozeni" % Element.name_of(el))
		hps[el] = e.hp
	var first: float = hps[0]
	for el in range(1, Element.COUNT):
		_ok(is_equal_approx(float(hps[el]), first),
			"a vsichni dostavaji PRESNE stejne (%s %.2f vs %s %.2f)" %
			[Element.name_of(0), first, Element.name_of(el), float(hps[el])])


# --------------------------------------------------------------- 5 vlastni

func _test_own_lane_is_free_pass() -> void:
	var g := _fresh()
	g.auto_wave = false
	g.gold = 500
	var lane: int = _lane_of(Element.FIRE)
	# bonusy na useku, aby bylo jasne, ze ani investice vlastni pruh neposkodi
	_dress(g, lane, 2)
	_ok(Network.lane_element(lane) == Element.FIRE, "usek nese ohen")
	var e: Enemy = _spawn_one(g, Element.FIRE)
	g.set_switch(lane)
	var hp0: float = e.hp
	var lives0: int = g.lives
	g.run_for(30.0)
	_ok(is_equal_approx(e.hp, hp0), "ohen na svem useku nedostava ZADNE poskozeni (%.1f)" % e.hp)
	_ok(g.lives == lives0 - 1, "a dojde az na vystup (zivoty %d -> %d)" % [lives0, g.lives])


# --------------------------------------------------------------- 6 silny/slaby

func _test_strong_and_weak_lane() -> void:
	# PROTIKLAD (200 %) musi zabit uz s jednim bonusem, JINY (50 %) ani se
	# dvema. Rozdil mezi "silnym" a "cizim" usekem je ta informace, kterou
	# hrac vyhybkou kupuje - kdyby se smazal, byla by hra nahodna.
	for el in range(Element.COUNT):
		var strong_lane: int = _lane_of(Element.opposite_of(el))
		var weak_lane: int = _lane_of(int(Element.weak_against(el)[0]))
		_ok(strong_lane >= 0 and weak_lane >= 0,
			"pro %s existuje silny i slaby usek" % Element.name_of(el))
		var gs := _fresh()
		gs.auto_wave = false
		_dress(gs, strong_lane, 1)
		gs.set_switch(strong_lane)
		var es: Enemy = _spawn_one(gs, el)
		_run_to_lane(gs, es)
		gs.run_for(40.0)
		_ok(not es.alive, "zivel %s umre na protikladnem useku s 1 bonusem" % Element.name_of(el))
		_ok(gs.lives == Game.START_LIVES, "a zivy se tam nedostane")
		# a slaby usek ho ani s bonusem neudrzi
		var gw := _fresh()
		gw.auto_wave = false
		_dress(gw, weak_lane, 1)
		gw.set_switch(weak_lane)
		var ew: Enemy = _spawn_one(gw, el)
		_run_to_lane(gw, ew)
		gw.run_for(40.0)
		_ok(ew.hp > 0.0, "zivel %s na CIZIM useku i s bonusem prezije (hp=%.1f)" %
			[Element.name_of(el), ew.hp])
		_ok(gw.lives == Game.START_LIVES - 1, "a dojde na vystup (zivoty %d)" % gw.lives)
		# a zmer silovy rozdil: protiklad da vyrazne vic nez cizi
		var gstr := _fresh()
		gstr.auto_wave = false
		gstr.set_switch(strong_lane)
		var estr: Enemy = _spawn_one(gstr, el)
		_run_to_lane(gstr, estr)
		gstr.run_for(5.0)
		var strong_lost: float = estr.max_hp - estr.hp
		var gweak := _fresh()
		gweak.auto_wave = false
		gweak.set_switch(weak_lane)
		var eweak: Enemy = _spawn_one(gweak, el)
		_run_to_lane(gweak, eweak)
		gweak.run_for(5.0)
		var weak_lost: float = eweak.max_hp - eweak.hp
		_ok(strong_lost > weak_lost * 3.5,
			"protikladny usek da vyrazne vic nez cizi (%s: %.1f vs %.1f)" %
			[Element.name_of(el), strong_lost, weak_lost])


# --------------------------------------------------------------- 7 staveni

func _test_build_rule() -> void:
	# PRAVIDLO STAVENI: jen stejny zivel na stejny usek. Testuje se CELA
	# matice, ne jen jeden pripad - jinak by prosla i verze, ktera zakazuje
	# jen jednu kombinaci. Neutralni pruh neprijme NIC.
	for lane in range(Network.LANES):
		var own: int = Network.lane_element(lane)
		for el in range(Element.COUNT):
			var g := _fresh()
			g.auto_wave = false
			g.gold = 999
			var before: int = g.gold
			var built: bool = g.try_build(lane, 0, el)
			if Network.lane_is_neutral(lane):
				_ok(not built, "na neutralni usek %d nelze postavit %s" % [lane, Element.name_of(el)])
				_ok(g.gold == before, "a zlato zustalo nedotcene")
			elif el == own:
				_ok(built, "zivel %s na SVUJ usek %d jde postavit" % [Element.name_of(el), lane])
				_ok(g.bonus_at(lane, 0) != null, "a bonus tam opravdu stoji")
				_ok(g.gold == before - Bonus.COST, "a zlato se odecte")
				_ok(g.bonus_at(lane, 0).element == el, "a ma svuj zivel")
			else:
				_ok(not built, "zivel %s na CIZI usek %d postavit NELZE" % [Element.name_of(el), lane])
				_ok(g.bonus_at(lane, 0) == null, "a nic tam nestoji")
				_ok(g.gold == before, "a zlato zustalo nedotcene (%d)" % g.gold)
	# UI si zivel pro usek bere z hry, ne z nejakeho sveho stavu.
	for lane in range(Network.LANES):
		var ui_el: int = _fresh().build_element(lane)
		_ok(ui_el == Network.lane_element(lane),
			"UI stavi na usek %d zivel toho useku (%d)" % [lane, ui_el])
	# vyhybka posila na usek, ktery existuje - vcetne neutralniho
	for lane in range(Network.LANES):
		var g2 := _fresh()
		g2.set_switch(lane)
		_ok(g2.switch_lane() == lane, "vyhybka se da nastavit na usek %d" % lane)


# --------------------------------------------------------------- 8 prepinani

func _test_lane_tap_switches() -> void:
	for lane in range(Network.LANES):
		var g := _fresh()
		g.auto_wave = false
		var p: Vector2 = g.net.point_at(lane, g.net.lane_len[lane] * 0.55)
		var hit: int = g.net.lane_tap_at(p, 14.0)
		_ok(hit == lane, "klepnuti na usek %d ho vybere (hit=%d)" % [lane, hit])
		g.set_switch(hit)
		_ok(g.switch_lane() == lane, "a vyhybka je na useku %d" % lane)
	var g2 := _fresh()
	g2.auto_wave = false
	var far: Vector2 = Vector2(g2.net.area.end.x - 4.0, g2.net.area.end.y - 4.0)
	_ok(g2.net.lane_tap_at(far, 4.0) == -1, "klepnuti do prazdna nevybere usek")


# --------------------------------------------------------------- 9 rozestup

func _test_spawn_gap_is_swattable() -> void:
	var gap: float = Game.SPAWN_INTERVAL
	var room: float = Game.ENEMY_SPEED * gap
	# Dve klepnuti, kazde asi 0.2 s i s rozhodnutim: 52 px/s * 0.4 s.
	var need: float = 40.0
	_ok(room > need,
		"mezera mezi poutniky staci na dve klepnuti (%.0f px, potreba %.0f)" % [room, need])
	_ok(room < 140.0, "a rozestup neni prehnane velky (%.0f px)" % room)


# --------------------------------------------------------------- 10 hromadeni

func _test_pile_up_loses() -> void:
	var g := _fresh()
	g.phase = "wave"
	g.spawn_left = 0
	g.wave = 1
	for i in range(Game.START_LIVES):
		g._spawn(i % Element.COUNT)
	g.run_for(300.0)
	_ok(g.phase == "lost", "bez bonusu sit padne (faze=%s)" % g.phase)
	_ok(g.lives <= 0, "zivoty dosly (lives=%d)" % g.lives)


# --------------------------------------------------------------- 11 ekonomika

func _test_economy() -> void:
	var g := _fresh()
	var fire_lane: int = _lane_of(Element.FIRE)
	g.gold = 0
	_ok(not g.try_build(fire_lane, 0, Element.FIRE), "bez zlata se bonus nepostavi")
	g.gold = 500
	_ok(g.try_build(fire_lane, 0, Element.FIRE), "se zlatem se postavi")
	_ok(g.gold == 500 - Bonus.COST, "cena se odecte presne (%d)" % g.gold)
	_ok(not g.try_build(fire_lane, 0, Element.FIRE), "na obsazene misto se nestavi")
	var b: Bonus = g.bonus_at(fire_lane, 0)
	_ok(b != null and b.level == 1, "bonus zacina na urovni 1")
	var m1: float = g.lane_mult(fire_lane)
	_ok(g.try_upgrade(fire_lane, 0), "vylepseni projde")
	_ok(b.level == 2 and g.lane_mult(fire_lane) > m1,
		"vylepseni zvysi nasobek useku (%.2f -> %.2f)" % [m1, g.lane_mult(fire_lane)])
	_ok(not g.try_upgrade(fire_lane, 0), "nad maximum se vylepsovat neda")
	g.gold = 0
	_ok(not g.try_build(_lane_of(Element.EARTH), 0, Element.EARTH), "a zlato na to nestaci")


# --------------------------------------------------------------- 12 prubeh

func _test_wave_flow() -> void:
	var g := _fresh()
	_ok(g.phase == "build", "hra zacina pripravou")
	var before: int = g.wave
	g.run_for(Game.BUILD_TIME + 1.0)
	_ok(g.wave == before + 1, "po case zacne vlna (%d)" % g.wave)
	_ok(g.phase == "wave", "faze je vlna")
	# Kazdy zivel umre na sve PROTIKLADNE useku, kdyz je usek vystrojen -
	# ale na SVEM vlastnim useku ho neposkodi ani investice. Presne tenhle
	# rozdil je cele jadro hry, proto se testuji obe strany.
	for el in range(Element.COUNT):
		var own_lane: int = _lane_of(el)
		var kill_lane: int = _lane_of(Element.opposite_of(el))
		_ok(kill_lane >= 0, "usek pro %s existuje" % Element.name_of(Element.opposite_of(el)))
		# a) spravne poslany umre, kdyz je usek vystrojen (1 bonus staci)
		var h := _fresh()
		h.auto_wave = false
		_dress(h, kill_lane, 1)
		h.set_switch(kill_lane)
		var he: Enemy = _spawn_one(h, el)
		_run_to_lane(h, he)
		h.run_for(40.0)
		_ok(he.hp <= 0.0, "zivel %s umre na svem protikladnem useku (hp=%.1f)" %
			[Element.name_of(el), he.hp])
		_ok(h.lives == Game.START_LIVES, "a zivy se tam nedostane (zivoty %d)" % h.lives)
		# b) spatne poslany (na svuj vlastni) prezije i s plnou investici
		var h2 := _fresh()
		h2.auto_wave = false
		_dress(h2, own_lane, 3)
		h2.set_switch(own_lane)
		var he2: Enemy = _spawn_one(h2, el)
		h2.run_for(40.0)
		_ok(he2.hp > 0.0, "zivel %s na SVEM useku se tremi bonusy prezije (hp=%.1f)" %
			[Element.name_of(el), he2.hp])
		_ok(h2.lives == Game.START_LIVES - 1, "a dojde az na vystup (zivoty %d)" % h2.lives)


# --------------------------------------------------------------- 13 determinismus

func _test_determinism() -> void:
	var a := _fresh()
	var b := _fresh()
	for g in [a, b]:
		g.auto_wave = false
		g.gold = 5000
		g.try_build(_lane_of(Element.FIRE), 0, Element.FIRE)
		g.try_build(_lane_of(Element.WATER), 0, Element.WATER)
		g.set_switch(0)
		g.phase = "wave"
		g.spawn_left = 8
	a.run_for(16.0)
	b.run_for(16.0)
	_ok(a.enemies.size() == b.enemies.size(), "stejny pocet nepratel (%d/%d)" % [a.enemies.size(), b.enemies.size()])
	var damaged := 0
	for i in range(mini(a.enemies.size(), b.enemies.size())):
		var ea: Enemy = a.enemies[i]
		var eb: Enemy = b.enemies[i]
		_ok(ea.element == eb.element, "stejny zivel na pozici %d" % i)
		_ok(is_equal_approx(ea.hp, eb.hp), "stejne zivoty na pozici %d" % i)
		_ok(ea.lane == eb.lane, "stejna usek na pozici %d" % i)
		if ea.hp < ea.max_hp:
			damaged += 1
	_ok(damaged > 0, "a aspon jeden opravdu dostal poskozeni (%d)" % damaged)
	_ok(a.gold == b.gold, "stejne zlato (%d/%d)" % [a.gold, b.gold])
	_ok(a.lives == b.lives, "stejne zivoty (%d/%d)" % [a.lives, b.lives])
