extends SceneTree

# Test HERNI LOGIKY (srdce a vez).
# Vystup: CORE_ALL_PASS=true / false
#
# Testuje to, co se neda poznat okem: ze poutnik dojde od okraje k vezi presne
# za TRAVEL_S, ze vez vidi JEN svou barvu, ze svazek drzi cil do jeho smrti,
# ze paleta nikdy neobsahne stribrnou a ze kazda barva dela to, co ma
# (rozpad, regenerace, mizeni, zmena barvy).

var fails: Array = []
var checks: int = 0


func _init() -> void:
	_run("hra se postavi", _test_setup)
	_run("poutnik vstoupi na okraji plochy", _test_spawn_on_edge)
	_run("cesta od okraje k vezi trva 8 s", _test_travel_time)
	_run("vez vidi jen svou barvu", _test_sees_only_own_colour)
	_run("svazek drzi jeden cil, dokud neumre", _test_lock_until_death)
	_run("dosah: za kruhem se nic nedeje", _test_range)
	_run("v kruhu dostrelu ma hrac cas zareagovat", _test_reaction_window)
	_run("doraz k vezi stoji zivot", _test_reach_costs_life)
	_run("paleta roste s obtiznosti a nikdy neobsahne stribrnou", _test_palette)
	_run("barvu mimo paletu nelze zvolit", _test_select_outside_palette)
	_run("fialova po prvnim zasahu zmizi", _test_violet_vanishes)
	_run("modra se po zabiti rozpadne na dva kusy", _test_blue_splits)
	_run("zelená si obnovuje zivoty", _test_green_regenerates)
	_run("stribrna meni barvu a nevraci se", _test_silver_shifts)
	_run("vlna micha barvy, ktere uz vstoupily", _test_wave_mix)
	_run("vylepseni zvetsi dostrel a ubere zlato", _test_upgrade)
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
	# MERITKO = POLOMER PLOCHY (jednotkove rozvrzeni): hra pak ma ve vez stejne
	# cisla jako driv (tower_r = 0.12 * 300 = 36) a testy meri pravidla, ne zoom.
	g.set_field(300.0, 300.0, Vector2(500.0, 500.0))
	return g


# PRAZDNA VLNA: hra nic neposila, takze test meri jen to, na co se ptá.
# Bez toho by do mereni vstoupily vlny hry a kazdy pozdejsi FAIL by patril
# cizimu stavu (presna ta past, ktera uz jednou stala kolo prace).
func _quiet(g: Game, wave: int = 1) -> void:
	g.phase = "wave"
	g.plan = []
	g.spawned = 0
	g.wave = wave
	g.refresh_palette()


func _place(g: Game, h: int, frac: float, angle: float = 0.0) -> Pilgrim:
	var p: Pilgrim = g.spawn_at_angle(angle, h)
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
	_check(g.palette.size() == 2, "hra nezacina se dvema barvami (ma %d)" % g.palette.size())
	_check(g.palette.has(Hue.RED) and g.palette.has(Hue.YELLOW),
		"prvni dve barvy nejsou cervena a zluta")
	for h in range(Hue.COUNT):
		_check(Hue.unlock_wave(h) >= 1, "barva %s nema vlnu, od ktere vstoupi" % Hue.name_of(h))
	_check(Hue.name_of(-1) == "?", "zaporny index barvy vraci jmeno (past na konec pole)")
	_check(Hue.name_of(Hue.COUNT + 3) == "?", "index mimo rozsah vraci jmeno")


func _test_spawn_on_edge() -> void:
	var g: Game = _fresh()
	_quiet(g)
	for i in range(8):
		var a: float = TAU * float(i) / 8.0
		var p: Pilgrim = g.spawn_at_angle(a, Hue.BLUE)
		_check(absf(p.pos.distance_to(g.center) - g.field_r) < 0.01,
			"poutnik nevstoupil na okraj plochy (uhel %.2f)" % a)
		var want: Vector2 = (g.center - p.pos).normalized()
		_check(p.dir.distance_to(want) < 0.001, "poutnik nejde rovne k vezi")
		_check(absf(p.speed - (g.field_r - g.tower_r) / Game.TRAVEL_S * Hue.speed_mult(Hue.BLUE)) < 0.001,
			"rychlost neni odvozena z rozvrzeni a nasobku barvy")
		_check(p.behaviour == Hue.behaviour_of(Hue.BLUE),
			"poutnik si neodnesl chovani sve barvy")


func _test_travel_time() -> void:
	var g: Game = _fresh()
	_quiet(g)
	# POZOR: vez vidi PRESNE svou barvu, takze modreho poutnika ohniva vez
	# nezastavi - meri se cista cesta. Modra ma nasobek rychlosti 1,0.
	g.tower.set_hue(Hue.RED)
	var p: Pilgrim = g.spawn_at_angle(0.0, Hue.BLUE)
	var t: float = 0.0
	var dt: float = 1.0 / 60.0
	while p.alive and t < 30.0:
		g.step(dt)
		t += dt
	_check(absf(t - Game.TRAVEL_S) < 0.35,
		"cesta od okraje k vezi trvala %.2f s (cekano %.1f)" % [t, Game.TRAVEL_S])


func _test_sees_only_own_colour() -> void:
	var g: Game = _fresh()
	_quiet(g)
	g.tower.set_hue(Hue.RED)
	var own: Pilgrim = _place(g, Hue.RED, 0.25)
	var other: Pilgrim = _place(g, Hue.YELLOW, 0.25, PI)
	var own0: float = own.hp
	var other0: float = other.hp
	g._beam(1.0)
	_check(own.hp < own0, "zvolena barva nedostava poskozeni")
	_check(is_equal_approx(other.hp, other0),
		"cizi barva dostava poskozeni (ma dostavat nulu a vez na ni nemá ani střílet)")


func _test_lock_until_death() -> void:
	var g: Game = _fresh()
	_quiet(g)
	g.tower.set_hue(Hue.RED)
	var near: Pilgrim = _place(g, Hue.RED, 0.20)
	var far: Pilgrim = _place(g, Hue.RED, 0.30, PI)
	near.hp = 30.0
	near.max_hp = 30.0
	far.hp = 400.0
	far.max_hp = 400.0
	g._beam(0.5)
	_check(is_equal_approx(far.hp, 400.0),
		"svazek se rozdelil na dva cile (ma drzet jen jeden)")
	for i in range(4):
		g._beam(0.2)
		if near.alive:
			_check(is_equal_approx(far.hp, 400.0),
				"druhy cil dostal poskozeni, dokud první žil")
	_check(not near.alive, "blizky cil po 1,3 s svazku neumrel")
	g._beam(0.2)
	_check(far.hp < 400.0, "po smrti prvniho cile svazek nepresel na dalsi")


func _test_range() -> void:
	var g: Game = _fresh()
	_quiet(g)
	g.tower.set_hue(Hue.RED)
	var p: Pilgrim = _place(g, Hue.RED, 0.90)
	var hp0: float = p.hp
	g._beam(1.0)
	_check(is_equal_approx(p.hp, hp0), "poutnik mimo dostrel dostal poskozeni")
	p.pos = g.center + Vector2(0.30 * g.field_r, 0.0)
	g._beam(0.2)
	_check(p.hp < hp0, "poutnik v dostrelu nedostal poskozeni")


# CAS NA REAKCI. Jan: "kruh, který určuje vzdálenost zjišťování nepřátel je tak
# malý, že hráč nemá moc času reagovat. Zjišťování by mělo být někde mezi těmito
# dvěma kruhy." Meri se cas, ktery poutnik stravi V KRUHU DOSTRELU - presne to je
# okno, ve kterem musi hrac stihnout prepnout barvu. Zaklad (0,40 polomeru
# plochy) daval ~2,5 s, coz bylo malo; dnes je zaklad 0,62 a cas roste s
# vylepsenim. Mimo dostrel se nedeje nic, takze okno je i to, co hra umi.
func _test_reaction_window() -> void:
	# MERI SE NA ROZVRZENI TELEFONU, na kterem Jan hraje (390x844) - cisla
	# z jednotkoveho rozvrzeni testu by o realne hre nerikala nic.
	var lay := ScreenLayout.new()
	lay.update(Vector2(390.0, 844.0))
	var prev: float = -1.0
	for lv in range(1, Tower.MAX_LEVEL + 1):
		var g: Game = Game.new()
		_quiet(g)
		g.set_field(lay.field_r, lay.unit_r, lay.center)
		g.tower.level = lv
		# JINA BARVA: vez na modreho poutnika vubec nestrili, takze se meri
		# cista cesta kruhem dostrelu (zadne poskozeni do mereni nezasahuje).
		g.tower.set_hue(Hue.RED)
		var p: Pilgrim = g.spawn_at_angle(0.7, Hue.BLUE)
		var r: float = g.tower.range_px(g.field_r)
		_check(r > g.tower_r * 2.0, "na %d. stupni je dostrel skoro u veze" % lv)
		_check(r < g.field_r, "na %d. stupni dostrel dosahuje na spawnovaci kruh" % lv)
		var window: float = 0.0
		var t: float = 0.0
		var dt: float = 1.0 / 120.0
		while p.alive and t < 30.0:
			if g.in_range(p, r):
				window += dt
			g.step(dt)
			t += dt
		_check(window >= 4.0,
			"na %d. stupni ma hrac v dostrelu jen %.2f s (potreba aspon 4 s na reakci)"
			% [lv, window])
		_check(window < Game.TRAVEL_S * 0.95,
			"na %d. stupni pokryva dostrel temer celou cestu (%.2f s)" % [lv, window])
		_check(window > prev, "vylepseni nepridalo cas na reakci")
		prev = window


func _test_reach_costs_life() -> void:
	var g: Game = _fresh()
	_quiet(g)
	g.tower.set_hue(Hue.RED)
	var p: Pilgrim = g.spawn_at_angle(0.7, Hue.BLUE)
	var lives0: int = g.lives
	var t: float = 0.0
	var dt: float = 1.0 / 60.0
	while p.alive and t < 30.0:
		g.step(dt)
		t += dt
	_check(g.lives == lives0 - 1, "doraz k vezi neztratil zivot")
	_check(p.alive == false, "poutnik po dorazu zustal ve hre")
	_check(absf(t - Game.TRAVEL_S) < 0.35,
		"doraz prisel v %.2f s (cekano %.1f)" % [t, Game.TRAVEL_S])


# PALETA: barvy pribyvaji s obtiznosti a STRIBRNA V NI NIKDY NENI. Kdyby se
# tam dostala, hrac by mohl mirrit na poutnika, ktery ma byt nepolapitelny -
# a to je cely smysl te barvy.
func _test_palette() -> void:
	var g: Game = _fresh()
	_check(Hue.palette_at(1).size() == 2, "prvni vlna nema dve barvy")
	_check(Hue.palette_at(3).size() == 3, "treti vlna nepridala treti barvu")
	_check(Hue.palette_at(5).size() == 4, "pata vlna nepridala ctvrtou barvu")
	_check(Hue.palette_at(7).size() == 5, "sedma vlna nepridala patou barvu")
	_check(Hue.palette_at(10).size() == 5, "v palete je na konci hry vic nez pet barev")
	_check(Hue.active_at(10).size() == Hue.COUNT,
		"na konci hry nevstupuji vsechny barvy")
	for w in range(1, 12):
		_check(not Hue.palette_at(w).has(Hue.SILVER),
			"stribrna je v palete ve vlne %d" % w)
	# paleta roste, nikdy se nezmensuje
	for w in range(2, 11):
		_check(Hue.palette_at(w).size() >= Hue.palette_at(w - 1).size(),
			"paleta se ve vlne %d zmensila" % w)
	# hra prevezme paletu vlnou
	g.wave = 7
	g.refresh_palette()
	_check(g.palette.size() == 5, "hra si v sedme vlne nedrzi pet barev")
	_check(g.tower.palette.size() == 5, "vez nedostala novou paletu")


func _test_select_outside_palette() -> void:
	var g: Game = _fresh()
	var before: int = g.tower.hue
	_check(not g.select_hue(Hue.SILVER), "hrac zvolil stribrnou")
	_check(g.tower.hue == before, "stribrna se dostala do veze")
	# barva, ktera do hry jeste nevstoupila (violet = 7. vlna), taky ne
	_check(g.select_hue(Hue.YELLOW), "hrac nemuze zvolit zlutou, ktera v palete je")
	_check(not g.select_hue(Hue.VIOLET), "hrac zvolil barvu, ktera jeste nevstoupila")
	_check(g.tower.hue == Hue.YELLOW, "vez si nedrzi zvolenou barvu")


func _test_violet_vanishes() -> void:
	var g: Game = _fresh()
	_quiet(g, 7)
	g.tower.set_hue(Hue.VIOLET)
	_check(g.palette.has(Hue.VIOLET), "v sedme vlne neni fialova v palete")
	var p: Pilgrim = _place(g, Hue.VIOLET, 0.25)
	var hp0: float = p.hp
	g._beam(0.05)
	_check(p.hp < hp0, "fialova nedostala prvni zasah")
	_check(p.ghost_left > 0.0, "fialova po prvnim zasahu nezmizela")
	_check(not p.targetable(), "na fialovou se da mirrit, i kdyz zmizela")
	_check(not g.tower.sees(p), "vez vidi fialovou, i kdyz zmizela")
	var hp1: float = p.hp
	g._beam(1.0)
	_check(is_equal_approx(p.hp, hp1), "zmizela fialova dostala poskozeni")
	# po trech vterinach je zase videt
	g._advance_behaviour(p, Hue.VANISH_S + 0.05)
	_check(p.targetable(), "fialova se po trech vterinach nevratila")
	g._beam(0.05)
	_check(p.hp < hp1, "po navratu fialova nedostava poskozeni")


func _test_blue_splits() -> void:
	var g: Game = _fresh()
	_quiet(g, 3)
	g.tower.set_hue(Hue.BLUE)
	var p: Pilgrim = _place(g, Hue.BLUE, 0.25)
	p.hp = 8.0
	p.max_hp = 40.0
	g._beam(0.5)
	_check(not p.alive, "modra po raně neumrela")
	var pieces: Array = []
	for q in g.pilgrims:
		if q != p:
			pieces.append(q)
	_check(pieces.size() == Hue.SPLIT_PIECES,
		"modra se nerozpadla na dva kusy (kusu: %d)" % pieces.size())
	for q in pieces:
		_check(q.hue == Hue.BLUE, "kus po rozpadu nema barvu rodice")
		_check(not q.can_split, "kus se muze rozpadnout znovu (z jednoho poutnika by bylo nekonecno)")
		_check(q.size < p.size, "kus neni mensi nez rodic")
		_check(absf(q.max_hp - 40.0 * Hue.SPLIT_HP_FRAC) < 0.01, "kus nema spravne zivoty")
		_check(absf((g.center - q.pos).normalized().dot(q.dir)) > 0.999,
			"kus nejde rovne k vezi")


func _test_green_regenerates() -> void:
	var g: Game = _fresh()
	_quiet(g, 5)
	g.tower.set_hue(Hue.RED)
	var p: Pilgrim = _place(g, Hue.GREEN, 0.25)
	p.hp = p.max_hp * 0.5
	g._advance_behaviour(p, 1.0)
	_check(is_equal_approx(p.hp, p.max_hp * (0.5 + Hue.REGEN_FRAC)),
		"zelena si neobnovuje zivoty (%f)" % p.hp)
	# nikdy nad maximum
	p.hp = p.max_hp
	g._advance_behaviour(p, 5.0)
	_check(p.hp <= p.max_hp + 0.001, "zelena se preleciła nad sve maximum")


func _test_silver_shifts() -> void:
	var g: Game = _fresh()
	_quiet(g, 9)
	var p: Pilgrim = g.spawn_at_angle(0.0, Hue.SILVER)
	_check(p.hue == Hue.SILVER, "stribrna nezacina jako stribrna")
	_check(not g.palette.has(Hue.SILVER), "stribrna je v palete")
	_check(not g.select_hue(Hue.SILVER), "na stribrnou se da mirrit")
	# prvni zmena po trech vterinach
	g._advance_behaviour(p, Hue.SHIFT_S - 0.5)
	_check(p.hue == Hue.SILVER, "stribrna zmenila barvu prilis brzy")
	g._advance_behaviour(p, 0.6)
	_check(p.hue != Hue.SILVER, "stribrna po trech vterinach nezmenila barvu")
	# a uz se nikdy nevrati; barvi se jen na barvy, ktere jsou ve hre
	var seen: Dictionary = {}
	for i in range(40):
		g._advance_behaviour(p, Hue.SHIFT_S + 0.01)
		_check(p.hue != Hue.SILVER, "stribrna se vratila na stribrnou")
		_check(Hue.active_at(g.wave).has(p.hue),
			"stribrna si vybrala barvu, ktera ve hre neni (%s)" % Hue.name_of(p.hue))
		seen[p.hue] = true
	_check(seen.size() >= 2, "stribrna porad meni barvu na stejnou (barev: %d)" % seen.size())


func _test_wave_mix() -> void:
	var g: Game = _fresh()
	for n in [1, 4, 7, 10]:
		var plan: Array = g.wave_plan(n)
		_check(plan.size() == int(Game.WAVE_SIZES[n - 1]),
			"vlna %d ma %d poutniku, cekano %d" % [n, plan.size(), Game.WAVE_SIZES[n - 1]])
		var seen: Dictionary = {}
		for h in plan:
			seen[int(h)] = true
		_check(seen.size() == Hue.active_at(n).size(),
			"vlna %d nemicha vsechny barvy, ktere uz vstoupily (%d z %d)"
			% [n, seen.size(), Hue.active_at(n).size()])


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
