extends SceneTree

# Hluboky test JADRA. Nesaha na kresleni ani na vstup - testuje pravidla.
# Vystup: CORE_ALL_PASS=true / false

var fails: Array = []
var checks: int = 0


func _init() -> void:
	_test_geometry()
	_test_element_table()
	_test_immunity_lane()
	_test_opposite_lane_kills()
	_test_build_rule()
	_test_switch_routes_enemy()
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


# --------------------------------------------------------------- 1 geometrie

func _test_geometry() -> void:
	var g := _fresh()
	_ok(g.net.lane_path.size() == Network.LANES, "ctyri cilove koleje")
	_ok(g.net.slot_count() == 3, "tri mista na vez na kolej")
	for lane in range(Network.LANES):
		var ln: float = g.net.lane_len[lane]
		_ok(ln > 200.0, "kolej %d ma rozumnou delku (%.0f)" % [lane, ln])
		for slot in range(g.net.slot_count()):
			var p: Vector2 = g.net.slot_world(lane, slot)
			_ok(g.net.area.grow(40.0).has_point(p), "misto %d/%d je v hraci plose" % [lane, slot])
	# trasa zacina na kmeni a konci ve svatyni
	_ok(g.net.trunk_len > 250.0, "kmen ma delku (%.0f)" % g.net.trunk_len)
	_ok(g.net.merge.distance_to(g.net.hub) > 10.0, "vyhybka a sberny bod jsou oddelene")
	# kazda kolej konci u sve svatyne
	for lane in range(Network.LANES):
		var end: Vector2 = g.net.shrine_pos[lane]
		var last: Vector2 = g.net.point_at(lane, g.net.lane_len[lane])
		_ok(end.distance_to(last) < 1.0, "kolej %d konci ve svatyni" % lane)
	_ok(g.net.switch_lane == 0, "vyhybka startuje na prvnim zivlu")
	# ROZVRZENI: veze na sousednich kolejich se nesmi prekryvat. Polomer
	# veze uz neni konstanta - jde z meritka plochy, tak ho ber z instance.
	var gap: float = g.net.min_cross_lane_slot_distance()
	_ok(gap > g.net.tower_r * 2.0 + 8.0,
		"mista na veze mezi kolejemi se neprekryvaji (mezera %.0f px)" % gap)
	# a vsechna mista musi byt NAD ovladacim pruhem
	var bar_top: float = 500.0
	for lane in range(Network.LANES):
		for slot in range(g.net.slot_count()):
			var p: Vector2 = g.net.slot_world(lane, slot)
			_ok(p.y + g.net.tower_r < bar_top,
				"misto %d/%d neleze do ovladaciho pruhu (y=%.0f)" % [lane, slot, p.y])
	# zadna herni linie nesmi vest skrz ovladaci pruh
	for lane in range(Network.LANES):
		var path: PackedVector2Array = g.net.lane_path[lane]
		for k in range(path.size()):
			_ok(path[k].y < bar_top, "kolej %d zustava nad pruhem" % lane)
		# ani popisek svatyne se nesmi dotknout pruhu (posledni svatyně
		# byla jednou uříznutá - text se kresli 54 px pod stredem)
		var label_y: float = g.net.shrine_pos[lane].y + 54.0
		_ok(label_y < bar_top - 6.0,
			"popisek svatyne %d zustava nad pruhem (y=%.0f)" % [lane, label_y])


# --------------------------------------------------------------- 2 matice

func _test_element_table() -> void:
	_ok(Element.multiplier(Element.FIRE, Element.FIRE) == 0.0, "vlastni zivel = nula poskozeni")
	_ok(Element.multiplier(Element.FIRE, Element.WATER) == 1.0, "protiklad = plne poskozeni")
	_ok(Element.multiplier(Element.FIRE, Element.EARTH) == 0.35, "cizi zivel = zlomek")
	_ok(Element.multiplier(Element.AIR, Element.EARTH) == 1.0, "protiklad plati i obracene")
	_ok(Element.opposite_of(Element.opposite_of(Element.FIRE)) == Element.FIRE, "protiklad je involuce")
	for e in range(Element.COUNT):
		for t in range(Element.COUNT):
			_ok(Element.multiplier(e, t) >= 0.0, "nasobek neni zaporny (%d,%d)" % [e, t])
	# kazdy zivel ma svoji barvu a jmeno
	var seen := {}
	for e in range(Element.COUNT):
		_ok(not Element.name_of(e).is_empty(), "zivel %d ma jmeno" % e)
		_ok(not seen.has(Element.color_of(e)), "zivel %d ma unikatni barvu" % e)
		seen[Element.color_of(e)] = true


# --------------------------------------------------------------- 3 imunita

func _test_immunity_lane() -> void:
	var g := _fresh()
	g.auto_wave = false
	g.gold = 999
	# Vez stoji na koleji sveho zivlu - ohen na ohni.
	_ok(g.try_build(0, 0, Network.lane_element(0)), "vez ohně postavena na kolej ohně")
	_ok(g.try_build(0, 1, Network.lane_element(0)), "druha vez ohně postavena")
	g.set_switch(0)
	var e: Enemy = _spawn_one(g, Element.FIRE)
	var hp0: float = e.hp
	var lives0: int = g.lives
	g.run_for(40.0)
	_ok(is_equal_approx(e.hp, hp0), "ohen na ohni nedostava ZADNE poskozeni (%.1f)" % e.hp)
	_ok(g.lives == lives0 - 1, "a dojde az do svatyne (zivoty %d -> %d)" % [lives0, g.lives])
	_ok(g.gold < 999, "stavba nestoji zlato navic")


# --------------------------------------------------------------- 4 protiklad

func _test_opposite_lane_kills() -> void:
	var g := _fresh()
	g.auto_wave = false
	g.gold = 999
	# Kolej 1 nese vodu, ohen tam tedy nesmi - ale voda ano, a voda
	# zabiji ohen. Presne tuhle cestu hra od hrace chce.
	_ok(g.try_build(1, 0, Network.lane_element(1)), "voda na kolej vody")
	_ok(g.try_build(1, 1, Network.lane_element(1)), "druha vez vody")
	g.set_switch(1)
	var e: Enemy = _spawn_one(g, Element.FIRE)
	var hp0: float = e.hp
	g.run_for(12.0)
	_ok(e.hp < hp0, "ohen na vode dostava poskozeni (%.1f -> %.1f)" % [hp0, e.hp])
	g.run_for(30.0)
	var lives0: int = g.lives
	_ok(g.lives == lives0, "protikladna kolej ho zastavi (zivoty %d)" % g.lives)
	_ok(g.enemies.is_empty(), "nepritel je mrtev, ne na kolejich")


# --------------------------------------------------------------- 4b staveni

func _test_build_rule() -> void:
	# PRAVIDLO STAVENI: jen stejny zivel na stejny zivel. Testuje se
	# CELA matice, ne jen jeden pripad - jinak by prosla i verze, ktera
	# zakazuje jen jednu kombinaci.
	for lane in range(Network.LANES):
		var own: int = Network.lane_element(lane)
		for el in range(Element.COUNT):
			var g := _fresh()
			g.auto_wave = false
			g.gold = 999
			var before: int = g.gold
			var built: bool = g.try_build(lane, 0, el)
			if el == own:
				_ok(built, "zivel %s na SVOU kolej %d jde postavit" % [Element.name_of(el), lane])
				_ok(g.tower_at(lane, 0) != null, "a vez tam opravdu stoji")
				_ok(g.gold == before - Tower.COST, "a zlato se odecte")
				_ok(g.tower_at(lane, 0).element == el, "a vez ma svuj zivel (%d)" % g.tower_at(lane, 0).element)
			else:
				_ok(not built, "zivel %s na CIZI kolej %d postavit NELZE" % [Element.name_of(el), lane])
				_ok(g.tower_at(lane, 0) == null, "a nic tam nestoji")
				_ok(g.gold == before, "a zlato zustalo nedotcene (%d)" % g.gold)
	# UI si zivel pro kolej bere z hry, ne z nejakeho sveho stavu. Kdyby
	# si ho drzelo zvlast, slo by stavet mimo pravidlo.
	for lane in range(Network.LANES):
		var ui_el: int = _fresh().build_element(lane)
		_ok(ui_el == Network.lane_element(lane),
			"UI stavi na kolej %d zivel te koleje (%d)" % [lane, ui_el])
		_ok(Network.lane_accepts(lane, ui_el),
			"a to je presne to, co kolej prijme")
	# kolej musi mit zivel, ktery existuje, a kazdy prave jednou
	var seen := {}
	for lane in range(Network.LANES):
		var e: int = Network.lane_element(lane)
		_ok(e >= 0 and e < Element.COUNT, "kolej %d ma platny zivel (%d)" % [lane, e])
		_ok(not seen.has(e), "zivel %d neni na dvou kolejich" % e)
		seen[e] = true
	_ok(seen.size() == Element.COUNT, "vsechny zivly maji svou kolej (%d)" % seen.size())
	# vyhybka posila na kolej, ktera existuje
	for lane in range(Network.LANES):
		var g2 := _fresh()
		g2.set_switch(lane)
		_ok(g2.switch_lane() == lane, "vyhybka se da nastavit na kolej %d" % lane)


# --------------------------------------------------------------- 5 prepinani

func _test_switch_routes_enemy() -> void:
	var g := _fresh()
	g.auto_wave = false
	var e: Enemy = _spawn_one(g, Element.EARTH)
	g.set_switch(2)
	g.run_for(3.0)
	_ok(not e.on_lane(), "po 3 s je poutnik jeste na kmeni")
	g.set_switch(3)
	g.run_for(6.0)
	_ok(e.on_lane(), "po projetí vyhybkou je na koleji")
	_ok(e.lane == 3, "a to na te, ktera byla nastavena PRED vjezdem (lane=%d)" % e.lane)


# Klepnuti na kolej je jediny zpusob prepnuti vyhybky. Testuje se CELA
# matice: pro kazdou kolej se klepne na jeji trasu a vyhybka se musi
# preklopit PRAVE na ni. Jinak by stacilo, aby se trefovala jen jedna.
func _test_lane_tap_switches() -> void:
	for lane in range(Network.LANES):
		var g := _fresh()
		g.auto_wave = false
		# klepni doprostred rovneho useku te kolejе, ne na svatyne ani na
		# vyhybku - presne tam hrac miri prstem.
		var p: Vector2 = g.net.point_at(lane, g.net.lane_len[lane] * 0.55)
		var hit: int = g.net.lane_tap_at(p, 14.0)
		_ok(hit == lane, "klepnuti na kolej %d ji vybere (hit=%d)" % [lane, hit])
		g.set_switch(hit)
		_ok(g.switch_lane() == lane, "a vyhybka je na koleji %d" % lane)
	# klepnuti mimo vsechny koleje nic nevybere - jinak by se vyhybka
	# prela nahodne pri klepnuti do prazdneho mista
	var g2 := _fresh()
	g2.auto_wave = false
	var far: Vector2 = Vector2(g2.net.area.end.x - 4.0, g2.net.area.end.y - 4.0)
	_ok(g2.net.lane_tap_at(far, 4.0) == -1, "klepnuti do prazdna nevybere kolej")


# ROZESTUP POUTNIKU. Hrac prepina vyhybku PRO KAZDEHO poutnika zvlast, takze
# mezi dvema poutniky se musi vejit aspon dve klepnuti. Kdyz je mezera
# kratsi nez cas na dve klepnuti, hra je nehratelna bez ohledu na to, jak
# dobre vypada - presne to se stalo pri rozestupu 0.62 s.
func _test_spawn_gap_is_swattable() -> void:
	var gap: float = Game.SPAWN_INTERVAL
	var room: float = Game.ENEMY_SPEED * gap
	# Dve klepnuti, kazde asi 0.2 s i s rozhodnutim: 52 px/s * 0.4 s.
	var need: float = 40.0
	_ok(room > need,
		"mezera mezi poutniky staci na dve klepnuti (%.0f px, potreba %.0f)" % [room, need])
	# a nesmi to byt prehnane - jinak by se jich na kolejich hromadilo malo
	_ok(room < 140.0, "a rozestup neni prehnane velky (%.0f px)" % room)


# --------------------------------------------------------------- 6 hromadeni

func _test_pile_up_loses() -> void:
	var g := _fresh()
	g.phase = "wave"
	g.spawn_left = 0
	g.wave = 1
	for i in range(Game.START_LIVES):
		g._spawn(i % Element.COUNT)
	g.run_for(300.0)
	_ok(g.phase == "lost", "bez vezi sit padne (faze=%s)" % g.phase)
	_ok(g.lives <= 0, "zivoty dosly (lives=%d)" % g.lives)


# --------------------------------------------------------------- 7 ekonomika

func _test_economy() -> void:
	var g := _fresh()
	# Kolej 0 nese ohen - stavime tedy ohnem, ne vodou.
	var fire: int = Network.lane_element(0)
	g.gold = 0
	_ok(not g.try_build(0, 0, fire), "bez zlata se vez nepostavi")
	g.gold = 500
	_ok(g.try_build(0, 0, fire), "se zlatem se postavi")
	_ok(g.gold == 500 - Tower.COST, "cena se odecte presne (%d)" % g.gold)
	_ok(not g.try_build(0, 0, fire), "na obsazene misto se nestavi")
	var t: Tower = g.tower_at(0, 0)
	_ok(t != null and t.level == 1, "vez zacina na urovni 1")
	var dps1: float = t.dps()
	_ok(g.try_upgrade(0, 0), "vylepseni projde")
	_ok(t.level == 2 and t.dps() > dps1, "vylepseni zvysi poskozeni (%.0f -> %.0f)" % [dps1, t.dps()])
	_ok(not g.try_upgrade(0, 0), "nad maximum se vylepsovat neda")
	g.gold = 0
	_ok(not g.try_build(2, 0, Network.lane_element(2)), "a zlato na to nestaci")


# --------------------------------------------------------------- 8 prubeh hry

func _test_wave_flow() -> void:
	var g := _fresh()
	_ok(g.phase == "build", "hra zacina pripravou")
	var before: int = g.wave
	g.run_for(Game.BUILD_TIME + 1.0)
	_ok(g.wave == before + 1, "po case zacne vlna (%d)" % g.wave)
	_ok(g.phase == "wave", "faze je vlna")
	var wave1: int = g.wave
	var lives_before: int = g.lives
	# Vezmi na kazde kole se vlna musí prostřílet. Kazdy zivel ma svoji
	# PROTIKLADNOU kolej - a vez na ni je prave ten zivel, ktery je
	# protikladem toho, kdo po ni pujde. To je jadro hry.
	for el in range(Element.COUNT):
		var h := _fresh()
		h.auto_wave = false
		h.gold = 5000
		var lane_el: int = Element.opposite_of(el)
		var kill_lane: int = -1
		for lane in range(Network.LANES):
			if Network.lane_element(lane) == lane_el:
				kill_lane = lane
		_ok(kill_lane >= 0, "kolej pro %s existuje" % Element.name_of(lane_el))
		for slot in range(h.net.slot_count()):
			h.try_build(kill_lane, slot, lane_el)
		h.set_switch(kill_lane)
		_spawn_one(h, el)
		var before_lives: int = h.lives
		h.run_for(30.0)
		_ok(h.enemies.is_empty(), "zivel %s umre na sve protikladne koleji" % Element.name_of(el))
		_ok(h.lives == before_lives, "a zivy se tam nedostane (zivoty %d)" % h.lives)
	_ok(g.wave == wave1, "testy vyse behaji na vlastnich instancich hry")
	_ok(g.lives == lives_before, "a puvodni hra zustala nedotcena")


# --------------------------------------------------------------- 9 determinismus

func _test_determinism() -> void:
	var a := _fresh()
	var b := _fresh()
	for g in [a, b]:
		g.auto_wave = false
		g.gold = 5000
		for lane in range(Network.LANES):
			g.try_build(lane, 0, Network.lane_element(lane))
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
		_ok(ea.lane == eb.lane, "stejna kolej na pozici %d" % i)
		if ea.hp < ea.max_hp:
			damaged += 1
	_ok(damaged > 0, "a aspon jeden opravdu dostal poskozeni (%d)" % damaged)
	_ok(a.gold == b.gold, "stejne zlato (%d/%d)" % [a.gold, b.gold])
	_ok(a.lives == b.lives, "stejne zivoty (%d/%d)" % [a.lives, b.lives])
