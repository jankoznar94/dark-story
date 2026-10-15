extends SceneTree

# TEST PRAVIDEL HRY. Vystup: CORE_ALL_PASS=true / false
#
# Testuje se to, co hrac opravdu pozna: ze poutnik dojde k vezi za TRAVEL_S,
# ze vez vidi jen svou barvu, ze poskozeni dava az DOPAD strely, ze level ma
# DESET VLN a ze se za vyhru dostavaji BODY. Kdo hleda "kde se ubiraji zivoty",
# hleda `Game._arrive` a `Game._damage`.

var fails: Array = []
var checks: int = 0


func _init() -> void:
	Profile.allow_save = false
	_run("cesta od okraje k vezi trva TRAVEL_S", _test_travel_time)
	_run("poutnik u veze ubere svoje zivoty (a zbroj to zkrati)", _test_arrive_damage)
	_run("regenerace dolici zivoty veze", _test_regen)
	_run("nula zivotu = prohra", _test_lose)
	_run("vez vidi jen svou barvu", _test_only_own_hue)
	_run("strela poskozuje az v dopadu, a to prave jednou ranou", _test_shots_hit_on_impact)
	_run("strela po smrti cile nezasahne nikoho jineho", _test_dead_target_shot_fizzles)
	_run("strela ma dostupnost i obrys pod sebou", _test_shot_size)
	_run("kriticka sance a poskozeni jsou z tabulky upgradu", _test_crit)
	_run("multishot drzi vic cilu zaraz", _test_multishot)
	_run("ricochet se odrazi na stejnou barvu a kazdy dostane nejvyse jednou", _test_ricochet)
	_run("jedovaty zasah dava poskozeni v case", _test_poison)
	_run("ledovy zasah zpomaluje pohyb", _test_ice)
	_run("docasny krok stoji 5xN zlata a hodnota roste", _test_temp_buy)
	_run("permanentni stupen posouva start bitvy", _test_perm_shift)
	_run("level ma deset vln a za vyhru jsou body", _test_level_flow)
	_run("dalsi level: zlato znovu, docasne kroky pryc", _test_next_level)
	_run("obtiznost roste s levelem, barvy po levelech", _test_difficulty)
	_run("nove barvy prichazeji po levelech, ne uprostred bitvy", _test_hue_unlock)
	_run("pauza zastavi hru (krok nekrokuje)", _test_pause)
	print("checks=%d fails=%d" % [checks, fails.size()])
	print("CORE_ALL_PASS=%s" % ("true" if fails.is_empty() else "false"))
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


func _fresh() -> Game:
	var g := Game.new()
	g.profile = Profile.new()
	# MERITKO = POLOMER PLOCHY (jednotkove rozvrzeni): hra pak ma stejna cisla
	# jako driv a testy meri pravidla, ne rozvrzeni.
	g.set_field(300.0, 300.0, Vector2(500.0, 500.0))
	g.start_level(1)
	_quiet(g)
	return g


func _phone() -> Game:
	var l := ScreenLayout.new()
	l.update(Vector2(390.0, 844.0))
	var g := Game.new()
	g.profile = Profile.new()
	g.set_field(l.field_r, l.unit_r, l.center)
	g.start_level(1)
	_quiet(g)
	return g


# ZADNA VLNA SE NESPOUSTI. Faze "test" neni ani build, ani wave, takze
# `_phase_step` se hned vrati - ale pohyb, strileni i efekty bezi dal. Bez
# toho by si hra zacala posilat vlastni vlnu a kazde mereni by patrilo ji.
func _quiet(g: Game) -> void:
	g.phase = "test"
	g.plan = []
	g.spawned = 0
	g.pilgrims = []
	g.locks = []
	g.shots = []


func _tick(g: Game, sec: float, dt: float = 1.0 / 240.0) -> void:
	var t: float = 0.0
	while t < sec:
		g.step(dt)
		t += dt


func _place(g: Game, h: int, frac: float, angle: float = 0.0) -> Pilgrim:
	var p: Pilgrim = g.spawn_at_angle(angle, h)
	p.pos = g.center + Vector2(cos(angle), sin(angle)) * (frac * g.field_r)
	return p


func _test_travel_time() -> void:
	# MODRA MA NASOBEK RYCHLOSTI 1,0 - proto je to prave ona, na ktere se
	# "cesta trva TRAVEL_S" meri. Cervena jde 0,6x pomaleji (a to je jeji
	# vlastnost, ne chyba).
	var g: Game = _fresh()
	var p: Pilgrim = g.spawn_at_angle(0.0, Hue.BLUE)
	var t: float = 0.0
	while p.alive and t < 40.0:
		g.step(1.0 / 240.0)
		t += 1.0 / 240.0
	_check(absf(t - Game.TRAVEL_S) < 0.5,
		"cesta od okraje k vezi trvala %.2f s (cekano %.1f)" % [t, Game.TRAVEL_S])


# POUTNIK TESNE U VEZE. Vzdycky se stavi K TOMU, aby ho krok (nebo dva) dovedl
# na dostrel veze - jinak by test meril jen to, ze jeste nedosel.
func _at_tower(g: Game, h: int) -> Pilgrim:
	var p: Pilgrim = g.spawn_at_angle(0.0, h)
	p.pos = g.center + Vector2(0.0, -g.tower_r * 1.05)
	p.dir = (g.center - p.pos).normalized()
	return p


func _test_arrive_damage() -> void:
	# VEZ SE DIVA NA JINOU BARVU, nez je poutnik: kdyby do nej strilila, meril
	# by test poskozeni strelou, ne to, co ubere dosly poutnik.
	var g: Game = _fresh()
	g.tower.hue = Hue.YELLOW
	var hp0: float = g.hp
	var p: Pilgrim = _at_tower(g, Hue.RED)
	p.hp = 50.0
	p.max_hp = 50.0
	_tick(g, 1.0)
	_check(not p.alive, "poutnik u veze nezmizel")
	_check(absf((hp0 - g.hp) - 50.0) < 0.01,
		"dosel poutnik se 50 zivoty a ubral %.2f" % (hp0 - g.hp))
	# ZBROJ TO ZKRATI: 20 % redukce z 50 = 40.
	var g2: Game = _fresh()
	g2.tower.hue = Hue.YELLOW
	g2.temp["am"] = 10      # 10 krocích po 2 % = 20 %
	g2.hp = g2.max_hp
	var hp2: float = g2.hp
	var q: Pilgrim = _at_tower(g2, Hue.RED)
	q.hp = 50.0
	q.max_hp = 50.0
	_tick(g2, 1.0)
	_check(absf((hp2 - g2.hp) - 40.0) < 0.01,
		"zbroj nezkratila poskozeni (ubralo %.2f, cekano 40)" % (hp2 - g2.hp))


func _test_regen() -> void:
	var g: Game = _fresh()
	g.temp["rg"] = 4        # 4 krocích po 0,5/s = 2/s
	g.hp = 10.0
	_tick(g, 1.0)
	_check(absf(g.hp - 12.0) < 0.1, "regenerace pridala %.2f zivotu (cekana 2)" % (g.hp - 10.0))
	# NIKDY NAD MAXIMUM.
	g.hp = g.max_hp - 0.5
	_tick(g, 3.0)
	_check(absf(g.hp - g.max_hp) < 0.01, "regenerace prekrocila maximum (%.1f z %.1f)" % [g.hp, g.max_hp])


func _test_lose() -> void:
	var g: Game = _fresh()
	g.hp = 5.0
	var p: Pilgrim = _at_tower(g, Hue.RED)
	p.hp = 40.0
	p.max_hp = 40.0
	_tick(g, 1.0)
	_check(g.phase == "lost", "vez padla, ale hra neskoncila (faze %s)" % g.phase)
	_check(g.hp == 0.0, "zivoty veze nejsou na nule (%.2f)" % g.hp)
	_check(g.is_over(), "prohrana hra neni over")
	# KDO JE PO PROHRE, UZ SE NEKROKUJE.
	var before: Vector2 = p.pos
	g.step(1.0)
	_check(p.pos.is_equal_approx(before), "krok po prohre neco udelal")


func _test_only_own_hue() -> void:
	var g: Game = _fresh()
	g.tower.hue = Hue.RED
	# OBA POUTNICI MUSI BYT V DOSTRELU: mimo dostrel by test meril jen to, ze
	# nikdo neni v dostrelu (zaklad je 0,34 polomeru plochy, ne 0,5).
	var inside: float = g.range_frac() * 0.7
	var r: Pilgrim = _place(g, Hue.RED, inside)
	var y: Pilgrim = _place(g, Hue.YELLOW, inside, PI)
	y.speed = 0.0
	r.speed = 0.0
	var y_hp: float = y.hp
	_tick(g, 2.0)
	_check(r.hp < r.max_hp, "poutnik ve barve veze nedostal poskozeni")
	_check(is_equal_approx(y.hp, y_hp), "vez poskodila poutnika v jine barve")
	_check(g.locks.size() == 1 and g.locks[0] == r, "vez zamirila na vic nez svoji barvu")


func _test_shots_hit_on_impact() -> void:
	var g: Game = _phone()
	g.tower.hue = Hue.RED
	var p: Pilgrim = _place(g, Hue.RED, g.range_frac() * 0.85)
	p.hp = 1000.0
	p.max_hp = 1000.0
	p.speed = 0.0
	var hp0: float = p.hp
	var want: float = (p.pos.distance_to(g.center) - g.tower_r) / g.shot_speed()
	g.step(1.0 / 240.0)
	_check(g.shots.size() >= 1, "vez pri zamereni vubec nevystrelila")
	_check(is_equal_approx(p.hp, hp0), "poskozeni prislo driv, nez strela doletela")
	var t: float = 0.0
	while is_equal_approx(p.hp, hp0) and t < 3.0:
		g.step(1.0 / 240.0)
		t += 1.0 / 240.0
	_check(absf((hp0 - p.hp) - g.shot_dmg()) < 0.01,
		"dopad strely neubral prave poskozeni jedne rany (ubral %.2f)" % (hp0 - p.hp))
	_check(t >= 0.15, "strela doletela okamzite (let ma byt videt, je %.3f s)" % t)
	_check(absf(t - want) < 0.06,
		"let strely nesedi s rychlosti (mereno %.3f s, cekano %.3f)" % [t, want])


func _test_dead_target_shot_fizzles() -> void:
	var g: Game = _fresh()
	g.tower.hue = Hue.RED
	var near: Pilgrim = _place(g, Hue.RED, g.range_frac() * 0.55)
	var far: Pilgrim = _place(g, Hue.RED, g.range_frac() * 0.92, PI)
	near.speed = 0.0
	far.speed = 0.0
	near.hp = 5.0
	near.max_hp = 5.0
	far.hp = 400.0
	far.max_hp = 400.0
	var t: float = 0.0
	while near.alive and t < 3.0:
		g.step(1.0 / 240.0)
		t += 1.0 / 240.0
	_check(not near.alive, "blizky poutnik neumrel")
	_check(is_equal_approx(far.hp, 400.0),
		"poskozeni dostal poutnik, na ktereho vez nemirila")
	# OKNO MUSI POJMOUT JEDNU RANU: doba do dalsi rany je 1/rate (zaklad 1 s po
	# upgradu na 5 krocích 0,75 s) plus let strely. Kratky tik by meril jen to,
	# ze vez jeste nenabili - a to neni chyba hry.
	_tick(g, 3.0)
	_check(far.hp < 400.0, "svazek se po smrti cile neprepjal na druhy")


func _test_shot_size() -> void:
	var g: Game = _phone()
	_check(g.shot_r() > 3.0, "tecka strely je prilis mala (%.2f px)" % g.shot_r())
	_check(g.shot_rim_r() > g.shot_r(), "tecka strely nema obrys pod sebou")


func _test_crit() -> void:
	var g: Game = _fresh()
	# MAXIMUM: 0,40 sance na krit a 2,5x poskozeni (perm 6 + temp = 10 kroku).
	g.profile.perm["cc"] = 6
	g.profile.perm["cd"] = 6
	g.temp["cc"] = 14
	g.temp["cd"] = 4
	_check(absf(g.crit_chance() - 0.40) < 0.001, "kriticka sance neni 40 %% (%.2f)" % g.crit_chance())
	_check(absf(g.crit_dmg() - 2.5) < 0.001, "kriticke poskozeni neni 2,5x (%.2f)" % g.crit_dmg())
	var p: Pilgrim = _place(g, Hue.RED, 0.5)
	p.speed = 0.0
	p.hp = 100000.0
	p.max_hp = 100000.0
	var crits: int = 0
	var normal: int = 0
	for i in range(200):
		g.shots = []
		g._fire_at(p)
		var d: float = float(g.shots[0]["dmg"])
		if absf(d - g.shot_dmg()) < 0.001:
			normal += 1
		elif absf(d - g.shot_dmg() * 2.5) < 0.001:
			crits += 1
	_check(normal + crits == 200,
		"strela ma jiné poskozeni nez zaklad nebo krit (krit %d, zaklad %d)" % [crits, normal])
	_check(crits > 40 and crits < 160,
		"kriticka sance 40 %% dala %d kritu z 200 - losovani nefunguje" % crits)


func _test_multishot() -> void:
	var g: Game = _fresh()
	g.tower.hue = Hue.RED
	_check(g.targets() == 1, "zakladni vez drzi vic nez jeden cil")
	# MULTISHOT JE SPECIAL: kupuje se JEN v menu za body, v bitve za zlato ne.
	g.profile.perm["ms"] = 4
	_check(g.targets() == 5, "multishot nedrzi pet cilu (drzi %d)" % g.targets())
	_check(g.temp_level("ms") == 0, "special se da koupit i v bitve")
	for i in range(3):
		_place(g, Hue.RED, g.range_frac() * (0.4 + 0.1 * float(i)), float(i) * 0.4)
	g.step(1.0 / 240.0)
	_check(g.locks.size() == 3, "svazek nedrzi tri cile, i kdyz na to ma (drzi %d)" % g.locks.size())


func _test_ricochet() -> void:
	# BEZ ODRAZU: druhy poutnik stejne barvy nedostane nic.
	var g: Game = _fresh()
	g.tower.hue = Hue.RED
	_check(g.ricochet() == 0, "zakladni vez uz ma odraz")
	var inside: float = g.range_frac() * 0.8
	var a: Pilgrim = _place(g, Hue.RED, inside)
	var b: Pilgrim = _place(g, Hue.RED, inside * 0.92, 0.35)
	a.speed = 0.0
	b.speed = 0.0
	a.hp = 100000.0
	a.max_hp = 100000.0
	b.hp = 100000.0
	b.max_hp = 100000.0
	_tick(g, 1.5)
	var b0: float = b.hp
	# DAL UZ VEZ NESTRILI (docasne vypnuta kadence) - meri se jen odraz.
	g.fire_left = 999.0
	_tick(g, 1.0)
	_check(is_equal_approx(b.hp, b0), "bez odrazu dostal poskozeni druhy poutnik")
	# S ODRAZEM: stejna barva, jeden odraz, kazdy nejvyse jednou.
	var g2: Game = _fresh()
	g2.tower.hue = Hue.RED
	g2.profile.perm["rc"] = 1
	_check(g2.ricochet() == 1, "odraz se neda koupit")
	var c: Pilgrim = _place(g2, Hue.RED, inside)
	var d: Pilgrim = _place(g2, Hue.RED, inside * 0.92, 0.35)
	var other: Pilgrim = _place(g2, Hue.YELLOW, inside * 0.90, -0.35)
	for q in [c, d, other]:
		q.speed = 0.0
		q.hp = 100000.0
		q.max_hp = 100000.0
	_tick(g2, 1.5)
	_check(c.hp < c.max_hp, "prvni poutnik nedostal ranu")
	_check(d.hp < d.max_hp, "odraz nezasahl druheho poutnika stejne barvy")
	_check(is_equal_approx(other.hp, other.max_hp), "odraz zasahl i jinou barvu")
	# KAZDY NEJVYSE JEDNOU: prvni poutnik nema druhou ranu od odrazu (po
	# prvnim zásahu uz vez nestrili - kadence je vypnuta).
	g2.fire_left = 999.0
	var c_hp: float = c.hp
	var d_hp: float = d.hp
	_tick(g2, 2.0)
	_check(absf(c.hp - c_hp) < 0.01 and absf(d.hp - d_hp) < 0.01,
		"odraz zasahl stejneho poutnika vickrat")


func _test_poison() -> void:
	var g: Game = _fresh()
	g.tower.hue = Hue.YELLOW       # vez do poutnika nestrili - meri se jen jed
	g.profile.perm["ps"] = 1        # 20 % poskozeni rany za sekundu
	_check(absf(g.poison_frac() - 0.20) < 0.001, "jed neni 20 %% (%.2f)" % g.poison_frac())
	# POUTNIK STOJI: jinak by dosel do dostrelu a vez by do mereni strilila.
	var p: Pilgrim = _place(g, Hue.RED, g.range_frac() * 0.9)
	p.speed = 0.0
	p.hp = 1000.0
	p.max_hp = 1000.0
	g._damage(p, 10.0)
	_check(absf(p.poison_dps - 2.0) < 0.001, "poskozeni jedu za sekundu neni 2 (%.2f)" % p.poison_dps)
	var hp0: float = p.hp
	_tick(g, 1.0)
	_check(absf((hp0 - p.hp) - 2.0) < 0.2, "jed za sekundu ubral %.2f (cekano 2)" % (hp0 - p.hp))
	# JED VYPRSI: po POISON_S uz neubira.
	_tick(g, Game.POISON_S + 0.5)
	var hp1: float = p.hp
	_tick(g, 1.0)
	_check(absf(hp1 - p.hp) < 0.01, "jed ublizuje i po vyprseni (%.2f)" % (hp1 - p.hp))


func _test_ice() -> void:
	var g: Game = _fresh()
	g.tower.hue = Hue.YELLOW       # vez do poutnika nestrili - meri se jen led
	g.profile.perm["ic"] = 2        # 35 % zpomaleni
	var p: Pilgrim = _place(g, Hue.RED, 0.9)
	p.speed = 0.0
	g._damage(p, 1.0)
	_check(p.slow_mult() < 0.99, "led nezpomalil pohyb (%.2f)" % p.slow_mult())
	_check(absf(p.slow_mult() - 0.65) < 0.001, "zpomaleni neni 35 %% (%.2f)" % p.slow_mult())
	# PUSTIME HO: musi jit pomaleji nez zdrava cervena.
	p.speed = g.pilgrim_speed() * Hue.speed_mult(Hue.RED)
	var from: float = p.pos.distance_to(g.center)
	_tick(g, 1.0)
	var moved: float = from - p.pos.distance_to(g.center)
	var full: float = g.pilgrim_speed() * Hue.speed_mult(Hue.RED)
	_check(moved < full * 0.9, "zpomaleny poutnik usel %.1f px, zdrava rychlost je %.1f px/s" % [moved, full])
	# PO VYPRSENI JDE ZNOVU PLNou RYCHLOSTI.
	p.ice_left = 0.0
	var from2: float = p.pos.distance_to(g.center)
	_tick(g, 1.0)
	_check(absf((from2 - p.pos.distance_to(g.center)) - full) < 1.0,
		"po vyprseni ledu poutnik nejde plnou rychlosti")


func _test_temp_buy() -> void:
	var g: Game = _fresh()
	g.gold = 100
	var v0: float = g.val("as")
	_check(g.buy_temp("as"), "prvni krok se neda koupit")
	_check(g.gold == 95, "prvni krok nestal 5 zlata (zbyva %d)" % g.gold)
	_check(g.val("as") < v0, "krok nezmenil hodnotu parametru")
	_check(g.buy_temp("as"), "druhy krok se neda koupit")
	_check(g.gold == 85, "druhy krok nestal 10 zlata (zbyva %d)" % g.gold)
	# BEZ ZLATA SE NEKUPUJE.
	var g2: Game = _fresh()
	g2.gold = 4
	_check(not g2.buy_temp("as"), "krok se koupil bez zlata")
	_check(g2.gold == 4, "zlato se ubralo, i kdyz se nekoupilo")
	# STROP: dal uz nejde, ani za zlato.
	var g3: Game = _fresh()
	g3.gold = 100000
	for i in range(Upgrades.temp_max("as")):
		g3.buy_temp("as")
	_check(not g3.buy_temp("as"), "nad strop docasneho kroku se da koupit")
	# ZIVOTY SE DOSTANOU HNAD, ne az v dalsim levelu.
	var g4: Game = _fresh()
	g4.gold = 5
	var hp0: float = g4.max_hp
	g4.buy_temp("hp")
	_check(absf(g4.max_hp - (hp0 + 10.0)) < 0.01, "krok zivotu nezvetsil maximum")
	_check(absf(g4.hp - hp0 - 10.0) < 0.01, "koupe zivotu nedala zivoty hned")


func _test_perm_shift() -> void:
	# PERMANENTNI STUPEN POSOUVA START (Jan: "Když bude permanentní upgrade lvl 2,
	# tak budu začínat na střela/0.9s. Cena dočasných upgradů ale zůstává.")
	var g: Game = _fresh()
	g.profile.perm["as"] = 2
	g.start_level(1)
	_quiet(g)
	_check(absf(g.val("as") - 0.90) < 0.001, "start po dvou permanentních neni 0,90 s (%.2f)" % g.val("as"))
	var gold0: int = g.gold
	_check(g.buy_temp("as"), "krok po permanentnim upgradu nejde koupit")
	_check(gold0 - g.gold == 5, "krok po permanentnim upgradu stoJI jinak nez 5 zlata (%d)" % (gold0 - g.gold))
	_check(absf(g.val("as") - 0.85) < 0.001, "krok se neprisel k posunutemu startu (%.2f)" % g.val("as"))


func _test_level_flow() -> void:
	var g := Game.new()
	g.profile = Profile.new()
	g.set_field(300.0, 300.0, Vector2(500.0, 500.0))
	g.start_level(1)
	var n: int = g.waves_in_level()
	_check(n == Game.WAVES_PER_LEVEL,
		"prvni level nema %d vln (ma %d)" % [Game.WAVES_PER_LEVEL, n])
	# PRAZDNA DESKA = VLNA JE ODRAZENA. Takhle se projde celym levelem, aniž by
	# se cekalo na poutniky.
	for i in range(n):
		g.phase = "wave"
		g.plan = []
		g.spawned = 0
		g.pilgrims = []
		var w: int = g.wave
		g.step(0.02)
		if i < n - 1:
			_check(g.wave == w + 1, "%d. vlna neposunula na dalsi (wave %d)" % [w, g.wave])
			_check(g.phase == "build", "po vlně neni priprava (faze %s)" % g.phase)
	_check(g.phase == "won", "po posledni vlne neni level vyhrany (faze %s)" % g.phase)
	_check(g.body_earned == 30, "za prvni level neni 30 bodu (je %d)" % g.body_earned)
	_check(g.profile.body == 30, "body se neprisly do profilu (je %d)" % g.profile.body)
	_check(g.profile.level == 2 and g.profile.best == 1, "profil nezapsal vyhru (level %d, best %d)"
		% [g.profile.level, g.profile.best])


func _test_next_level() -> void:
	var g := Game.new()
	g.profile = Profile.new()
	g.set_field(300.0, 300.0, Vector2(500.0, 500.0))
	g.start_level(1)
	g.buy_temp("as")
	g.buy_temp("ar")
	var temp_before: int = g.temp.size()
	_check(temp_before > 0, "kroky se vubec nekoupily")
	g.phase = "won"
	g.next_level()
	_check(g.level == 2, "dalsi level neni druhy (%d)" % g.level)
	_check(g.wave == 1, "dalsi level nezacina prvni vlnou (%d)" % g.wave)
	_check(g.temp.is_empty(), "docasne kroky prezily do dalsiho levelu (%s)" % str(g.temp))
	_check(g.gold == Game.START_GOLD + int(round(g.val("gl"))),
		"zlato nezacalo znovu (%d)" % g.gold)
	_check(g.phase == "build", "dalsi level nezacina pripravou (%s)" % g.phase)
	_check(absf(g.hp - g.max_hp) < 0.01, "vez nezacina s plnými zivoty")


func _test_difficulty() -> void:
	var g := Game.new()
	g.profile = Profile.new()
	g.set_field(300.0, 300.0, Vector2(500.0, 500.0))
	# ZIVOTY POUTNIKA ROSTOU S LEVELEM (schvaleno: 1,22 za level). Kolo je
	# poradi vlny pres cely pruchod hrou, tedy level 2 zacina kolem 11.
	var h1: float = g.hp_for(1, 1, Hue.RED)
	var h11: float = g.hp_for(11, 1, Hue.RED)
	var h21: float = g.hp_for(21, 1, Hue.RED)
	_check(h11 > h1, "druhy level nema tuzsi poutniky")
	_check(absf(h11 / h1 - Game.LEVEL_HP) < 0.02, "rust mezi levely neni 1,22 (%.3f)" % (h11 / h1))
	_check(absf(h21 / h11 - Game.LEVEL_HP) < 0.02, "rust mezi levely neni 1,22 (%.3f)" % (h21 / h11))
	# KOLO SE POCITA PO DESETI VLNACH: prvni vlna druheho levelu je 11. kolo.
	g.start_level(1)
	_check(g.kolo() == 1, "prvni kolo prvniho levelu neni 1 (%d)" % g.kolo())
	g.wave = 3
	_check(g.kolo() == 3, "treti vlna prvniho levelu neni 3. kolo (%d)" % g.kolo())
	g.start_level(2)
	_check(g.kolo() == Game.WAVES_PER_LEVEL + 1,
		"prvni vlna druheho levelu neni %d. kolo (%d)" % [Game.WAVES_PER_LEVEL + 1, g.kolo()])
	# VELIKOST VLNY: v ramci levelu roste po jednom poutnikovi, kazdy dalsi
	# LEVEL prida jednoho navic (a strop to drzi).
	_check(g.wave_size(1, 1) < g.wave_size(2, 1), "druha vlna neni vetsi nez prvni")
	_check(g.wave_size(1, 5) == g.wave_size(1, 1) + 4,
		"velikost vlny neroste s levelem po jednom (%d vs %d)" % [g.wave_size(1, 5), g.wave_size(1, 1)])
	_check(g.wave_size(Game.WAVES_PER_LEVEL, 99) <= Game.WAVE_SIZES_MAX, "velikost vlny pretekla strop")


# BARVY PRICHAZEJI PO LEVELECH, NE UPROSTRED BITVY. Jan (Oct 2026): "Už prvním
# levelu přibude modrá barva. To je špatně. Co level, to nová barva." Prvni
# level = cervena a zluta, a kazdy dalsi prida PRAVE JEDNU barvu (stribrna
# nikdy - ta se meni na jinou barvu, proto na ni nejde mirrit).
func _test_hue_unlock() -> void:
	var in_pal: int = 0
	for h in range(Hue.COUNT):
		if Hue.in_palette(h):
			in_pal += 1
	var g := Game.new()
	g.profile = Profile.new()
	for lv in range(1, Hue.COUNT + 1):
		g.start_level(lv)
		_check(Hue.active_at(lv).size() == mini(lv + 1, Hue.COUNT),
			"level %d: do hry vstoupilo %d barev, ceka se %d"
			% [lv, Hue.active_at(lv).size(), mini(lv + 1, Hue.COUNT)])
		_check(g.palette.size() == mini(lv + 1, in_pal),
			"level %d: paleta ma %d barev, ceka se %d" % [lv, g.palette.size(), mini(lv + 1, in_pal)])
		_check(not g.palette.has(Hue.SILVER), "stribrna se objevila v palete")
		# KAZDA BARVA, KTERA CHODI PO PLOSE, MUSI BYT V PALETE - jinak by
		# poutnik nemel cim umrit. Stribrna je vyjimka (meni barvu).
		for h in Hue.active_at(lv):
			if h == Hue.SILVER:
				continue
			_check(g.palette.has(h),
				"level %d: %s chodi po plose, ale neni v palete" % [lv, Hue.name_of(h)])
	# A PRESNY OPACNY PRIPAD, KTERY JAN NASEL: v prvnim levelu modra neni.
	var first := Game.new()
	first.profile = Profile.new()
	first.start_level(1)
	_check(first.palette == [Hue.RED, Hue.YELLOW],
		"prvni level nema paletu cervena+zluta (%s)" % str(first.palette))
	_check(not first.spawn_pool().has(Hue.BLUE), "modri poutnici chodi uz v prvnim levelu")
	first.start_level(2)
	_check(first.palette.has(Hue.BLUE), "ve druhem levelu modra neprisla")


func _test_pause() -> void:
	var g: Game = _fresh()
	var p: Pilgrim = g.spawn_at_angle(0.0, Hue.RED)
	var before: Vector2 = p.pos
	g.paused = true
	_tick(g, 1.0)
	_check(p.pos.is_equal_approx(before), "pod pauzou se poutnik pohnul")
	g.paused = false
	_tick(g, 0.5)
	_check(not p.pos.is_equal_approx(before), "po zruseni pauzy se poutnik nepohnul")
