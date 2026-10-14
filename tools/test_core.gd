extends SceneTree

# Test HERNI LOGIKY noveho modelu (srdce a vez).
# Vystup: CORE_ALL_PASS=true / false
#
# Testuje to, co se neda poznat okem: ze poutnik dojde od okraje k vezi presne
# za TRAVEL_S, ze vez vidi JEN svou barvu, ze svazek drzi cil do jeho smrti,
# ze mimo dostrel se nedeje nic a ze klepnuti na vysek prepne barvu.

var fails: Array = []
var checks: int = 0


func _init() -> void:
	_run("hra se postavi", _test_setup)
	_run("poutnik vstoupi na okraji plochy", _test_spawn_on_edge)
	_run("cesta od okraje k vezi trva 8 s", _test_travel_time)
	_run("vez vidi jen svou barvu", _test_sees_only_own_colour)
	_run("svazek drzi jeden cil, dokud neumre", _test_lock_until_death)
	_run("dosah: za kruhem se nic nedeje", _test_range)
	_run("doraz k vezi stoji zivot", _test_reach_costs_life)
	_run("klepnuti na vysek prepne barvu", _test_notch_tap)
	_run("klepnuti na telo veze otoci barvu dal", _test_center_tap)
	_run("vylepseni zvetsi dostrel a ubere zlato", _test_upgrade)
	_run("vlna je mix vsech ctyr barev", _test_wave_mix)
	print("checks=%d fails=%d" % [checks, fails.size()])
	print("CORE_ALL_PASS=%s" % ("true" if fails.is_empty() else "false"))
	quit()


# ------------------------------------------------------------------ POMOCNE

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


func _fresh() -> Game:
	var g := Game.new()
	g.set_field(300.0, 36.0, Vector2(500.0, 500.0))
	return g


# PRAZDNA VLNA: hra nic neposila, takze test meri jen to, na co se ptá.
# Bez toho by do mereni vstoupily vlny hry a kazdy pozdejsi FAIL by patril
# cizimu stavu (presne ta past, ktera uz jednou stala kolo prace).
func _quiet(g: Game) -> void:
	g.phase = "wave"
	g.plan = []
	g.spawned = 0


func _place(g: Game, el: int, frac: float, angle: float = 0.0) -> Pilgrim:
	var p: Pilgrim = g.spawn_at_angle(angle, el)
	p.pos = g.center + Vector2(cos(angle), sin(angle)) * (frac * g.field_r)
	return p


# -------------------------------------------------------------------- TESTY

func _test_setup() -> void:
	var g: Game = _fresh()
	_check(g.phase == "build", "hra nezacina pripravou")
	_check(g.lives == Game.START_LIVES, "spatny pocet zivotu na startu")
	_check(g.gold == Game.START_GOLD, "spatne startovni zlato")
	_check(g.wave == 1, "hra nezacina prvni vlnou")
	_check(g.pilgrims.is_empty(), "na prazdne plose uz neco chodi")
	_check(g.tower.element == Element.FIRE, "vez nezacina ohniva")
	_check(Game.NOTCH_OUT > Game.NOTCH_IN and Game.NOTCH_IN > 1.0,
		"venec barev kolem veze nema smysl")


func _test_spawn_on_edge() -> void:
	var g: Game = _fresh()
	_quiet(g)
	for i in range(8):
		var a: float = TAU * float(i) / 8.0
		var p: Pilgrim = g.spawn_at_angle(a, Element.WATER)
		_check(absf(p.pos.distance_to(g.center) - g.field_r) < 0.01,
			"poutnik nevstoupil na okraj plochy (uhel %.2f)" % a)
		# smer musi byt presne k vezi a jednotkovy
		var want: Vector2 = (g.center - p.pos).normalized()
		_check(p.dir.distance_to(want) < 0.001, "poutnik nejde rovne k vezi")
		_check(absf(p.speed - (g.field_r - g.tower_r) / Game.TRAVEL_S) < 0.001,
			"rychlost neni odvozena z rozvrzeni plochy a TRAVEL_S")


func _test_travel_time() -> void:
	var g: Game = _fresh()
	_quiet(g)
	# POZOR NA OBRACENE PRAVIDLO: v novem modelu vez vidi PRESNE svou barvu.
	# Ohniva vez a ohnivy poutnik znamenaji, ze ho svazek zabije v kruhu
	# dostrelu - na mereni casu cesty je potreba barva, kterou vez NEVIDI.
	g.tower.set_element(Element.FIRE)
	var p: Pilgrim = g.spawn_at_angle(0.0, Element.WATER)
	var t: float = 0.0
	var dt: float = 1.0 / 60.0
	while p.alive and t < 20.0:
		g.step(dt)
		t += dt
	_check(absf(t - Game.TRAVEL_S) < 0.35,
		"cesta od okraje k vezi trvala %.2f s (cekano %.1f)" % [t, Game.TRAVEL_S])


func _test_sees_only_own_colour() -> void:
	var g: Game = _fresh()
	_quiet(g)
	g.tower.set_element(Element.FIRE)
	var own: Pilgrim = _place(g, Element.FIRE, 0.25)
	var other: Pilgrim = _place(g, Element.WATER, 0.25, PI)
	var own0: float = own.hp
	var other0: float = other.hp
	g._beam(1.0)
	_check(own.hp < own0, "zvolena barva nedostava poskozeni")
	_check(is_equal_approx(other.hp, other0),
		"cizi barva dostava poskozeni (ma dostavat nulu a vez na ni nemá ani střílet)")


func _test_lock_until_death() -> void:
	var g: Game = _fresh()
	_quiet(g)
	g.tower.set_element(Element.FIRE)
	var near: Pilgrim = _place(g, Element.FIRE, 0.20)
	var far: Pilgrim = _place(g, Element.FIRE, 0.30, PI)
	near.hp = 30.0
	near.max_hp = 30.0
	far.hp = 400.0
	far.max_hp = 400.0
	g._beam(0.5)
	_check(is_equal_approx(far.hp, 400.0),
		"svazek se rozdelil na dva cile (ma drzet jen jeden)")
	for i in range(4):
		_check(is_equal_approx(far.hp, 400.0) if near.alive else true,
			"druhy cil dostal poskozeni, dokud první žil")
		g._beam(0.2)
	_check(not near.alive, "blizky cil po 1,3 s svazku neumrel")
	g._beam(0.2)
	_check(far.hp < 400.0, "po smrti prvniho cile svazek nepresel na dalsi")


func _test_range() -> void:
	var g: Game = _fresh()
	_quiet(g)
	g.tower.set_element(Element.EARTH)
	var p: Pilgrim = _place(g, Element.EARTH, 0.90)
	var hp0: float = p.hp
	g._beam(1.0)
	_check(is_equal_approx(p.hp, hp0), "poutnik mimo dostrel dostal poskozeni")
	p.pos = g.center + Vector2(0.30 * g.field_r, 0.0)
	g._beam(0.2)
	_check(p.hp < hp0, "poutnik v dostrelu nedostal poskozeni")


func _test_reach_costs_life() -> void:
	var g: Game = _fresh()
	_quiet(g)
	# vez je ohniva, poutnik zemsky -> vez ho nevidi a vubec na nej nestrili,
	# takze dorazi. (Kdyby mel stejnou barvu, svazek by ho v kruhu dostrelu
	# zabil - coz je taky spravne, ale testuje se tim neco jineho.)
	g.tower.set_element(Element.FIRE)
	var p: Pilgrim = g.spawn_at_angle(0.7, Element.EARTH)
	var lives0: int = g.lives
	var t: float = 0.0
	var dt: float = 1.0 / 60.0
	while p.alive and t < 20.0:
		g.step(dt)
		t += dt
	_check(g.lives == lives0 - 1, "doraz k vezi neztratil zivot")
	_check(p.alive == false, "poutnik po dorazu zustal ve hre")
	_check(absf(t - Game.TRAVEL_S) < 0.35,
		"doraz prisel v %.2f s (cekano %.1f)" % [t, Game.TRAVEL_S])


func _test_notch_tap() -> void:
	var g: Game = _fresh()
	var mid: float = g.tower_r * (Game.NOTCH_IN + Game.NOTCH_OUT) * 0.5
	for i in range(Element.COUNT):
		var a: float = -PI + TAU * (float(i) + 0.5) / float(Element.COUNT)
		var pos: Vector2 = g.center + Vector2(cos(a), sin(a)) * mid
		_check(g.notch_of(pos) == i,
			"vysek %d se nenasel (vyslo %d)" % [i, g.notch_of(pos)])
		g.tap_at(pos)
		_check(g.tower.element == i, "klepnuti na vysek %d nepreplo barvu" % i)
	# mimo venec se nesmi stat nic
	var before_el: int = g.tower.element
	g.tap_at(g.center + Vector2(0.0, g.tower_r * 3.0))
	_check(g.tower.element == before_el, "klepnuti mimo vez zmenilo barvu")


func _test_center_tap() -> void:
	var g: Game = _fresh()
	var el0: int = g.tower.element
	g.tap_at(g.center)
	_check(g.tower.element == (el0 + 1) % Element.COUNT,
		"klepnuti na telo veze neotocilo barvu na dalsi")


func _test_upgrade() -> void:
	var g: Game = _fresh()
	g.gold = 1000
	var rf0: float = g.tower.range_frac()
	var dps0: float = g.tower.dps()
	var cost: int = g.tower.upgrade_cost()
	_check(g.tower.can_upgrade(), "vez na prvnim stupni se neda vylepsit")
	_check(g.buy_upgrade(), "vylepseni se neprovedlo, i kdyz bylo na ne")
	_check(g.tower.level == 2, "vylepseni nezvedlo stupen")
	_check(g.tower.range_frac() > rf0, "vylepseni nezvetsilo dostrel")
	_check(g.tower.dps() > dps0, "vylepseni nezvetsilo poskozeni")
	_check(g.gold == 1000 - cost, "vylepseni nestalo spravne zlato")
	# dostrel nikdy nesmi pokryt celou plochu, jinak blizkost prestane hrat roli
	_check(g.tower.range_frac() < 0.9, "dostrel na maximu pokryva celou plochu")


func _test_wave_mix() -> void:
	var g: Game = _fresh()
	for n in [1, 4, 7, 10]:
		var plan: Array = g.wave_plan(n)
		_check(plan.size() == int(Game.WAVE_SIZES[n - 1]),
			"vlna %d ma %d poutniku, cekano %d" % [n, plan.size(), Game.WAVE_SIZES[n - 1]])
		var seen: Dictionary = {}
		for e in plan:
			seen[int(e)] = true
		_check(seen.size() == Element.COUNT,
			"vlna %d nema vsechny ctyri barvy (jen %d)" % [n, seen.size()])
