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
	_test_switch_routes_enemy()
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
	g.setup(Rect2(40.0, 80.0, 880.0, 404.0))
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
	# ROZVRZENI: veze na sousednich kolejich se nesmi prekryvat.
	var gap: float = g.net.min_cross_lane_slot_distance()
	_ok(gap > Network.TOWER_RADIUS * 2.0 + 8.0,
		"mista na veze mezi kolejemi se neprekryvaji (mezera %.0f px)" % gap)
	# a vsechna mista musi byt NAD ovladacim pruhem
	var bar_top: float = 500.0
	for lane in range(Network.LANES):
		for slot in range(g.net.slot_count()):
			var p: Vector2 = g.net.slot_world(lane, slot)
			_ok(p.y + Network.TOWER_RADIUS < bar_top,
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
	_ok(g.try_build(0, 0, Element.FIRE), "vez ohně postavena")
	_ok(g.try_build(0, 1, Element.FIRE), "druha vez ohně postavena")
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
	g.try_build(1, 0, Element.WATER)
	g.try_build(1, 1, Element.WATER)
	g.set_switch(1)
	_spawn_one(g, Element.FIRE)
	var lives0: int = g.lives
	g.run_for(40.0)
	_ok(g.lives == lives0, "protikladna kolej ho zastavi (zivoty %d)" % g.lives)
	_ok(g.enemies.is_empty(), "nepritel je mrtev, ne na kolejich")


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
	g.gold = 0
	_ok(not g.try_build(0, 0, Element.FIRE), "bez zlata se vez nepostavi")
	g.gold = 500
	_ok(g.try_build(0, 0, Element.FIRE), "se zlatem se postavi")
	_ok(g.gold == 500 - Tower.COST, "cena se odecte presne (%d)" % g.gold)
	_ok(not g.try_build(0, 0, Element.FIRE), "na obsazene misto se nestavi")
	var t: Tower = g.tower_at(0, 0)
	_ok(t != null and t.level == 1, "vez zacina na urovni 1")
	var dps1: float = t.dps()
	_ok(g.try_upgrade(0, 0), "vylepseni projde")
	_ok(t.level == 2 and t.dps() > dps1, "vylepseni zvysi poskozeni (%.0f -> %.0f)" % [dps1, t.dps()])
	_ok(not g.try_upgrade(0, 0), "nad maximum se vylepsovat neda")
	g.gold = 0
	_ok(not g.try_build(2, 0, Element.AIR), "a zlato na to nestaci")


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
	# Vezmi na kazde kole se vlna musí prostřílet - kazdy zivel ma svoji
	# protikladnou kolej, ktera ho zabije. Testujeme vsechny ctyri zvlast.
	for el in range(Element.COUNT):
		var h := _fresh()
		h.auto_wave = false
		h.gold = 5000
		var kill_lane: int = Element.opposite_of(el)
		for slot in range(h.net.slot_count()):
			h.try_build(kill_lane, slot, Element.opposite_of(el))
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
		g.try_build(0, 0, Element.opposite_of(0))
		g.try_build(1, 1, Element.opposite_of(1))
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
