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
	_run("laser ubira plynule, hned a bez kadence", _test_laser_burns_continuously)
	_run("paprsek se po smrti cile prepoji na dalsi", _test_laser_retargets_after_death)
	_run("paprsek ma sirku a odraz je tensi", _test_beam_width)
	_run("prepinani barvy neprida poskozeni", _test_hue_switch_does_not_double_damage)
	_run("kriticka sance a poskozeni jsou z tabulky upgradu", _test_crit)
	_run("bez sance na krit paprsek neblika", _test_crit_flash_needs_chance)
	_run("multishot drzi vic cilu a kazdy ma svuj paprsek", _test_multishot)
	_run("odraz se siri na stejnou barvu, kazdy dostane nejvyse jednou a mene", _test_odraz)
	_run("paprsek odrazu vychazi z prstence predchozi obeti (odraz je videt)", _test_odraz_beam_is_visible)
	_run("prepsani barvy paprsek utrhne (laser neni strela, ktera uz leti)", _test_hue_switch_stops_the_beam)
	_run("zmizele fialove paprsek zhasne (duch je imunni)", _test_vanish_stops_the_beam)
	_run("zrychleni hry zrychli cely cas, ne jen pohyb", _test_game_speed_scales_time)
	_run("zvukove udalosti: vystrel, zásah, smrt (a jed ne)", _test_sound_events)
	_run("neviditelna fialova je imunni (jed ani odraz na ni nedosahnou)", _test_ghost_is_immune)
	_run("jedovaty zasah dava poskozeni v case", _test_poison)
	_run("ledovy zasah zpomaluje pohyb", _test_ice)
	_run("docasny krok stoji 5xN zlata a hodnota roste", _test_temp_buy)
	_run("permanentni stupen posouva start bitvy", _test_perm_shift)
	_run("level ma deset vln a za vyhru jsou body", _test_level_flow)
	_run("dalsi level: zlato znovu, docasne kroky pryc", _test_next_level)
	_run("obtiznost roste s levelem, barvy po levelech", _test_difficulty)
	_run("zlato roste s obtiznosti (start i za zabiti)", _test_gold_scales_with_level)
	_run("nove barvy prichazeji po levelech, ne uprostred bitvy", _test_hue_unlock)
	_run("opakovany level nedava body (a profil se nemaze)", _test_replay_no_body)
	_run("pauza zastavi hru (krok nekrokuje)", _test_pause)
	_run("fialova je nejpomalejsi barva ve hre", _test_hue_speed_order)
	_run("stribrna meni po peti vterinach podobu i se schopnostmi barvy",
		_test_silver_shift_form)
	_run("modra podoba stribrne se rozpadne na dve obycejne kapky",
		_test_silver_split_form)
	_run("smes dvou barev je barva: id, dve pismena, vlastni barva", _test_mix_ids)
	_run("vez vidi jen to, co ma v sade barev (a smes potrebuje obe)", _test_covers)
	_run("dvojtap na palete michani barev (a pred sestym levelem ne)", _test_mix_taps)
	_run("kombinovany poutnik: obe barvy, obe schopnosti, prumer sil",
		_test_mix_pilgrim)
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
	g.beams = []


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


# LASER NEMA ANI LET, ANI KADENCI. Jan (Oct 2026): "Vrátíme se k laseru místo
# projektilů. Tím pádem zrušíme úplně Attack speed upgrady. Poškození bude
# probíhat plynule a čím vyšší bude mít věž dmg, tím rychleji to logicky bude
# nepřítele zabíjet." Test meri presny opak toho byvaleho: poskozeni prijde v
# PRVNIM snimku a za kazdou sekundu je ho presne tolik, kolik ma byt.
func _test_laser_burns_continuously() -> void:
	var g: Game = _phone()
	g.tower.hue = Hue.RED
	var p: Pilgrim = _place(g, Hue.RED, g.range_frac() * 0.85)
	p.hp = 1000.0
	p.max_hp = 1000.0
	p.speed = 0.0
	var dt: float = 1.0 / 240.0
	var hp0: float = p.hp
	g.step(dt)
	_check(p.hp < hp0, "laser v prvnim snimku neubira - ceka na neco, co uz neexistuje")
	_check(absf((hp0 - p.hp) - g.laser_dps() * dt) < 0.02,
		"za snimek laser ubral %.4f, cekano %.4f" % [hp0 - p.hp, g.laser_dps() * dt])
	_check(g.beams.size() == 1, "na zamereny cil nesviti prave jeden paprsek (%d)" % g.beams.size())
	var a0: float = p.hp
	_tick(g, 1.0)
	_check(absf((a0 - p.hp) - g.laser_dps()) < 0.05,
		"za sekundu laser ubral %.2f, cekano %.2f" % [a0 - p.hp, g.laser_dps()])
	# A PLYNULE DAL: zadny cil nema "davky", po kterych by se dalo utect.
	var b0: float = p.hp
	_tick(g, 0.5)
	_check(absf((b0 - p.hp) - g.laser_dps() * 0.5) < 0.05,
		"za pul sekundy laser ubral %.2f, cekano %.2f" % [b0 - p.hp, g.laser_dps() * 0.5])


# PO SMRTI CILE PAPRSEK PREJDE NA DRUHY. Laser nema "svazek, ktery drzi cil,
# dokud neumre" jako strela - pocita se kazdy snimek znovu, takze se smrt
# pozna hned a paprsek se prepoji.
func _test_laser_retargets_after_death() -> void:
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
	_check(is_equal_approx(far.hp, 400.0), "smycka zacina uz poskozenym dalekym poutnikem")
	_tick(g, 1.0)
	_check(not near.alive, "blizky poutnik neumrel")
	_check(far.hp < 400.0, "paprsek se po smrti cile neprepjal na druhy")


func _test_beam_width() -> void:
	var g: Game = _phone()
	# PAPRSEK JE TENSI (Jan, Oct 2026: "Laser je teď příliš tlustý."). Driv
	# 0,026 z meritka = 4,05 px na telefonu; ted 0,015 = 2,34 px. Hranice
	# v testu je proto 2 px, ne 3 - hlida jen to, ze paprsek nezmizi.
	_check(g.beam_w(0) > 2.0, "paprsek je prilis tenky (%.2f px)" % g.beam_w(0))
	_check(g.beam_w(3) < g.beam_w(0),
		"odraz je stejne silny jako hlavni paprsek - hrac nevidi, ktery cil je hlavni")
	_check(g.beam_w(3) > 0.5, "odraz se zuzil na nulu (%.2f px)" % g.beam_w(3))


# PREPINANI BARVY NESMI VYROBIT POSKOZENI NAVIC. U strely to byl "swing timer"
# (Jan, Oct 2026: "Když přepnu na jinou barvu, tak se resetuje Attack timer...
# Věž útočí rychleji než má"). U laseru je to jeste prisnejsi, protoze paprsek
# sviti jen na to, co vez zrovna vidi: prepnuti barvy ho UTRHNE a prepnuti zpet
# ho znovu rozsviti. Za cele okno proto NIKDY nesmi dat vic nez bez prepinani.
func _test_hue_switch_does_not_double_damage() -> void:
	var plain: float = _damage_in_5s(false)
	var flick: float = _damage_in_5s(true)
	_check(plain > 1.0, "laser za 5 s vubec neubral (%f)" % plain)
	_check(flick <= plain + 0.01,
		"prepinani barvy pridalo poskozeni: %.2f proti %.2f" % [flick, plain])


func _damage_in_5s(flicker: bool) -> float:
	var g: Game = _fresh()
	g.tower.hue = Hue.RED
	var p: Pilgrim = _place(g, Hue.RED, g.range_frac() * 0.7)
	p.speed = 0.0
	p.hp = 100000.0
	p.max_hp = 100000.0
	var hp0: float = p.hp
	var dt: float = 1.0 / 60.0
	var i: int = 0
	var t: float = 0.0
	while t < 5.0:
		# PRESNE TO, CO DELAL HRAC: prepni na barvu, ktera na plose neni
		# (vez ztrati cile), a hned zpet.
		if flicker and (i % 4) == 0:
			g.select_hue(Hue.YELLOW if g.tower.hue == Hue.RED else Hue.RED)
		g.step(dt)
		i += 1
		t += dt
	return hp0 - p.hp


func _test_crit() -> void:
	var g: Game = _fresh()
	# MAXIMUM: 0,40 sance na krit a 2,5x poskozeni (perm 6 + temp = 10 kroku).
	g.profile.perm["cc"] = 6
	g.profile.perm["cd"] = 6
	g.temp["cc"] = 14
	g.temp["cd"] = 4
	_check(absf(g.crit_chance() - 0.40) < 0.001, "kriticka sance neni 40 %% (%.2f)" % g.crit_chance())
	_check(absf(g.crit_dmg() - 2.5) < 0.001, "kriticke poskozeni neni 2,5x (%.2f)" % g.crit_dmg())
	# U PLYNULEHO PAPRSKU SE KRITIKA ZAPOCITAVA DO PRUMERU (losovat kazdy
	# snimek by znamenalo cisla, ktera hrac nikde nevidi). Stredni hodnota je
	# stejna, jako kdyby se losovalo: 10 * (1 + 0,40 * (2,5 - 1)) = 16/s.
	var want: float = 10.0 * (1.0 + 0.40 * 1.5)
	_check(absf(g.laser_dps() - want) < 0.01,
		"stredni poskozeni s kritikou neni %.1f (je %.2f)" % [want, g.laser_dps()])
	# KRIT JE VIDET JAKO ZABLESK, ne jako skakani cisel: sanci jsme prevedli na
	# PODIL CASU. Meri se proto dve veci - ze prumer za deset sekund sedi na
	# `laser_dps()` a ze kazdy snimek je presne bud zaklad, nebo zaklad x krit.
	var p: Pilgrim = _place(g, Hue.RED, g.range_frac() * 0.7)
	p.speed = 0.0
	var dt: float = 1.0 / 240.0
	var steps: int = 2400
	var lit: int = 0
	var total: float = 0.0
	var off_scale: bool = false
	for i in range(steps):
		p.hp = 1000000.0
		p.max_hp = 1000000.0
		var before: float = p.hp
		g.step(dt)
		var drop: float = before - p.hp
		total += drop
		if g.crit_active():
			lit += 1
		var base: float = g.laser_base() * dt
		if absf(drop - base) > 0.001 and absf(drop - base * g.crit_dmg()) > 0.001:
			off_scale = true
	var want10: float = want * float(steps) * dt
	_check(not off_scale, "snimek neni ani zaklad, ani nasobek kritiky - hrac vidi cisla, ktera nikde nejsou")
	_check(absf(total - want10) < want10 * 0.02,
		"za 10 s paprsek ubral %.1f, cekano %.1f" % [total, want10])
	var duty: float = float(lit) / float(steps)
	_check(absf(duty - 0.40) < 0.02,
		"sance na krit se nepromitla do podilu casu (sviti %.3f, sance je 0,40)" % duty)


# SANCE 0 = ZADNY ZABLESK. Kdyby zablesk svitil i bez koupene kritiky, hrac by
# videl ucinek, ktery si nezaplatil (a cisla v tabulce by lhala).
func _test_crit_flash_needs_chance() -> void:
	var g: Game = _fresh()
	g.tower.hue = Hue.RED
	_check(g.crit_chance() <= 0.0, "novy profil uz ma sanci na krit")
	_place(g, Hue.RED, g.range_frac() * 0.7).speed = 0.0
	var flashed: int = 0
	for i in range(1200):
		g.step(1.0 / 240.0)
		if g.crit_active():
			flashed += 1
	_check(flashed == 0, "krit blika i bez sance na krit (%d snimku)" % flashed)
	_check(absf(g.laser_now_dps() - g.laser_base()) < 0.001,
		"okamzity vykon neni zakladni, i kdyz krit nemuze nastat")


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
	_check(g.beams.size() == 3, "na tri cile nesviti tri paprsky (%d)" % g.beams.size())


# ODRAZ (driv Ricochet). Jan (Oct 2026): "RICOHET přejmenujeme na Odraz a bude
# se takhle laser šířit na další nepřátele, podobně jako ricochet, ale bez
# projektilů. A každý odraz bude dávat menší poškození." Test meri OBE cisla:
# kolik poskozeni dostane prvni cil a kolik druhy (a ze treti barva nedostane
# nic, protoze ji vez nevidi).
func _test_odraz() -> void:
	# BEZ ODRAZU: druhy poutnik stejne barvy nedostane nic.
	var g: Game = _fresh()
	g.tower.hue = Hue.RED
	_check(g.odraz() == 0, "zakladni vez uz ma odraz")
	var inside: float = g.range_frac() * 0.8
	var a: Pilgrim = _place(g, Hue.RED, inside)
	var b: Pilgrim = _place(g, Hue.RED, inside * 0.92, 0.35)
	a.speed = 0.0
	b.speed = 0.0
	a.hp = 100000.0
	a.max_hp = 100000.0
	b.hp = 100000.0
	b.max_hp = 100000.0
	_tick(g, 1.0)
	# VEZ MIRI NA BLIZSIHO (b), ne na vzdalenejsiho - proto se druhy poutnik
	# bez odrazu vubec nema jak dostat k raně.
	_check(b.hp < 100000.0, "na blizsiho poutnika laser vubec neubira")
	_check(is_equal_approx(a.hp, 100000.0), "bez odrazu dostal poskozeni druhy poutnik")

	# S ODRAZEM: kazdy dostane mene a kazdy nejvyse jednou.
	var g2: Game = _fresh()
	g2.tower.hue = Hue.RED
	g2.profile.perm["rc"] = 1
	_check(g2.odraz() == 1, "odraz se neda koupit")
	_check(absf(g2.odraz_strength() - 0.50) < 0.001,
		"sila prvniho odrazu neni 50 %% (%.2f)" % g2.odraz_strength())
	# PRVNI CIL JE TEN BLIZSI (c) - na nem se meri plne poskozeni, na odrazu (d)
	# polovina. Kdyby byly oba ve stejne dalku, nepoznalo by se, kdo je kdo.
	var c: Pilgrim = _place(g2, Hue.RED, 0.24, 0.0)
	var d: Pilgrim = _place(g2, Hue.RED, 0.26, 0.35)
	var other: Pilgrim = _place(g2, Hue.YELLOW, 0.25, -0.35)
	for q in [c, d, other]:
		q.speed = 0.0
		q.hp = 100000.0
		q.max_hp = 100000.0
	var dt: float = 1.0 / 240.0
	var c0: float = c.hp
	var d0: float = d.hp
	var o0: float = other.hp
	g2.step(dt)
	var drop_c: float = c0 - c.hp
	var drop_d: float = d0 - d.hp
	_check(absf(drop_c - g2.laser_dps() * dt) < 0.02,
		"prvni cil nedostal plne poskozeni (%.4f, cekano %.4f)" % [drop_c, g2.laser_dps() * dt])
	_check(drop_d > 0.0, "odraz nezasahl druheho poutnika stejne barvy")
	_check(absf(drop_d - g2.laser_dps() * 0.5 * dt) < 0.02,
		"odraz nedava polovinu poskozeni (%.4f, cekano %.4f)" % [drop_d, g2.laser_dps() * 0.5 * dt])
	_check(is_equal_approx(other.hp, o0), "odraz zasahl i jinou barvu")
	_check(g2.beams.size() == 3,
		"na dva cile v retezu nesviti tri segmenty (%d)" % g2.beams.size())

	# DRUHY STUPEN: vic odrazu, mensi penalizace (Jan: "S levelem upgradu se bude
	# zvyšovat počet odrazů a bude snižovat penalizace za odraz").
	var g3: Game = _fresh()
	g3.profile.perm["rc"] = 2
	_check(g3.odraz() == 2, "druhy stupen nepridal druhy odraz (%d)" % g3.odraz())
	_check(g3.odraz_strength() > 0.50,
		"druhy stupen nezlepsil silu odrazu (%.2f)" % g3.odraz_strength())


# ODRAZ JE VIDET (Jan, Oct 2026: "Ricochet musí mít nějakou animaci... Teď
# uděluje poškození, ale není nic vidět."). Paprsek odrazu musi VZNIKNOUT
# NA PRSTENCI predchozi obeti, ne v novem cili - jinak by to byl druhy paprsek
# z veze a hrac by nevidel, ze se svetlo siri. Jan (Oct 2026): "Laser by mohl
# končit (a odraz začínat) na plášti toho kruhu."
func _test_odraz_beam_is_visible() -> void:
	var g: Game = _fresh()
	g.tower.hue = Hue.RED
	g.profile.perm["rc"] = 1
	var a: Pilgrim = _place(g, Hue.RED, g.range_frac() * 0.70, 0.0)
	var b: Pilgrim = _place(g, Hue.RED, g.range_frac() * 0.70, 0.0)
	b.pos = a.pos + Vector2(60.0, 0.0)
	for q in [a, b]:
		q.speed = 0.0
		q.hp = 100000.0
		q.max_hp = 100000.0
	g.step(1.0 / 240.0)
	var first: Dictionary = {}
	var second: Dictionary = {}
	for bm in g.beams:
		if int(bm["hop"]) == 0 and first.is_empty():
			first = bm
		elif int(bm["hop"]) == 1:
			second = bm
	_check(not first.is_empty(), "hlavni paprsek vubec nevznikl - neni co kreslit")
	_check(not second.is_empty(), "odraz vubec nevznikl - hrac nevidi, ze se paprsek siri")
	_check((first["from"] as Vector2).distance_to(g.center) <= g.tower_r + 1.0,
		"hlavni paprsek nevychazi z veze")
	var victim: Pilgrim = first["target"]
	var want_r: float = g.pilgrim_ring_r(victim)
	_check(absf((second["from"] as Vector2).distance_to(victim.pos) - want_r) < 0.5,
		"odraz nevychazi z prstence predchozi obeti (je %.2f od stredu, prstenec je %.2f)"
		% [(second["from"] as Vector2).distance_to(victim.pos), want_r])
	# A KONEC PAPRSKU JE NA PLASHTI, NE VE STREDU TELA (Jan: "Laser končí ve
	# středu nepřítele, s hranatým zakončením... Je to jak dva obdélníky.").
	var last: Dictionary = g.beams[g.beams.size() - 1]
	_check(absf((last["to"] as Vector2).distance_to((last["target"] as Pilgrim).pos) - want_r) < 0.5,
		"paprsek nekonci na prstenci cile, ale ve stredu tela")


# LASER NENI STRELA, KTERA UZ LETI. Jan (Oct 2026): "Barva laseru bude podle
# barvy věže." Prepnuti barvy paprsek UTRHNE (vez jinou barvu nevidi) a na
# puvodni cil prestane ubirat - to je spravne, ne chyba jako driv u projektilu
# ("vystřeleno = doletí" uz neexistuje, neni co doletovat).
func _test_hue_switch_stops_the_beam() -> void:
	var g: Game = _fresh()
	g.tower.hue = Hue.RED
	var p: Pilgrim = _place(g, Hue.RED, g.range_frac() * 0.85)
	p.speed = 0.0
	p.hp = 1000.0
	p.max_hp = 1000.0
	_tick(g, 0.5)
	_check(p.hp < 1000.0, "laser na svoji barvu vubec neubira")
	_check(g.select_hue(Hue.YELLOW), "barva veze se neprepla")
	var hp1: float = p.hp
	_tick(g, 1.0)
	_check(is_equal_approx(p.hp, hp1),
		"po prepsani barvy paprsek ubira dal (o %.2f) - vez by videla jinou barvu" % (hp1 - p.hp))
	_check(g.beams.is_empty(), "paprsek po prepsani barvy sviti dal (%d)" % g.beams.size())


# ZRYCHLENI HRY (Jan, Oct 2026: "Veškerý čas ve hře se zrychlí. Pohyb, rychlost
# palby, rychlost animací, vše." + "Zrychlení hry by mělo být volitelně
# přepínatelné během souboje. Výchozí vždy 1.0x. Upgrade jen otevírá možnost to
# přepínat."). Upgrade je tedy KLIC: nasobi se CELY krok hry, ale teprve kdyz
# si hrac tempo v bitve prepne.
func _test_game_speed_scales_time() -> void:
	var g: Game = _fresh()
	_check(absf(g.time_scale() - 1.0) < 0.001, "hra nezacina na 1,0x")
	# KDO SI SPECIAL NEKOUPIL, NEMA CO PREPINAT.
	_check(g.speed_options() == 1, "bez upgradu je vic poloh tempa (%d)" % g.speed_options())
	_check(not g.cycle_speed(), "tempo se da prepnout bez upgradu")
	# UPGRADE SAM O SOBE HRU NEZRYCHLI.
	g.profile.perm["gs"] = 3
	_check(g.speed_options() == 4, "se tremi stupni nejsou ctyri polohy tempa (%d)" % g.speed_options())
	_check(absf(g.time_scale() - 1.0) < 0.001,
		"koupe tempa hru zrychli, i kdyz ma byt do prepnuti 1,0x (%.2f)" % g.time_scale())
	# PREPINANI: 1,0 -> 1,5 -> 2,0 -> 2,5 -> zpatky na 1,0.
	var want: Array = [1.5, 2.0, 2.5, 1.0]
	for i in range(4):
		_check(g.cycle_speed(), "tempo se neda prepnout")
		_check(absf(g.time_scale() - float(want[i])) < 0.001,
			"%d. prepnuti tempa neni %.1fx (je %.2fx)" % [i + 1, float(want[i]), g.time_scale()])
	# POMER POHYBU: v 2,5x tempu musi poutnik ujit 2,5x vic za stejny cas.
	var slow: Game = _fresh()
	var a: Pilgrim = slow.spawn_at_angle(0.0, Hue.BLUE)
	var a0: Vector2 = a.pos
	_tick(slow, 1.0)
	var slow_move: float = a0.distance_to(a.pos)
	_check(slow_move > 1.0, "poutnik se vubec nepohnul")
	var fast: Game = _fresh()
	fast.profile.perm["gs"] = 3
	fast.cycle_speed()
	fast.cycle_speed()
	fast.cycle_speed()
	_check(absf(fast.time_scale() - 2.5) < 0.001, "treti prepnuti neni 2,5x (%.2f)" % fast.time_scale())
	var q: Pilgrim = fast.spawn_at_angle(0.0, Hue.BLUE)
	var b0: Vector2 = q.pos
	_tick(fast, 1.0)
	var fast_move: float = b0.distance_to(q.pos)
	_check(absf(fast_move / slow_move - 2.5) < 0.05,
		"poutnik se v 2,5x tempu nepohnul 2,5x dal (%.1f vs %.1f px)" % [fast_move, slow_move])
	# KAZDA PARTIE ZACINA NA 1,0x - hrac si ma kazdou partii zvolit sve tempo.
	fast.start_level(2)
	_check(absf(fast.time_scale() - 1.0) < 0.001, "nova partie nezacina na 1,0x")


# ZVUKOVE UDALOSTI. Hra musi rict, CO se stalo (obrazovka z toho dela zvuk);
# kdyby je neposilala, hra by hrala tise a nikdo by nepoznal proc. A kdyby je
# nezmazala pri vybrani, zvuk by se opakoval dokola.
func _test_sound_events() -> void:
	var g: Game = _fresh()
	g.tower.hue = Hue.RED
	var p: Pilgrim = _place(g, Hue.RED, g.range_frac() * 0.7)
	p.speed = 0.0
	p.hp = 100000.0
	p.max_hp = 100000.0
	g.take_events()
	_tick(g, 2.0)
	var ev: Array = g.take_events()
	_check(ev.has("shot"), "zazehnuti paprsku neposlalo zvukovou udalost (%s)" % str(ev))
	# PAPRSEK NESMI TIKAT: kdyz sviti na cil dve sekundy, zvuk zazehnuti se smi
	# ozvat JEDNOU. (Driv to byl dopad strely; dnes je to okamzik, kdy paprsek
	# rozsvitil novy cil.)
	var lit: int = 0
	for e in ev:
		if String(e) == "shot":
			lit += 1
	_check(lit == 1, "paprsek tika: %d zvuku zazehnuti za 2 s" % lit)
	_check(g.beams_lit == 1, "pocitadlo zazehnuti paprsku neni 1 (%d)" % g.beams_lit)
	_check(g.take_events().is_empty(), "udalosti se po vybrani nevymazaly")
	# SMRT POUTNIKA. Vlastni hra: vez DRZI CIL, dokud neumre, takze v predchozi
	# hre by se porad strelilo do poutnika s 100000 zivoty a druhy by nikdy
	# neprisel na radu (a test by hlasil chybejici zvuk smrti).
	var gk: Game = _fresh()
	gk.tower.hue = Hue.RED
	var q: Pilgrim = _place(gk, Hue.RED, gk.range_frac() * 0.7)
	q.speed = 0.0
	q.hp = 1.0
	q.max_hp = 1.0
	gk.take_events()
	_tick(gk, 2.0)
	_check(gk.take_events().has("kill"), "smrt poutnika neposlala zvukovou udalost")
	# JED NESMI TIKAT: jed skodi pres `_hurt` kazdy snimek, takze zvuk zasahu
	# patri k DOPADU strely - jinak by hrac poslouchal tikani 60x za sekundu.
	var g2: Game = _fresh()
	g2.tower.hue = Hue.YELLOW
	g2.profile.perm["ps"] = 3
	var w: Pilgrim = _place(g2, Hue.RED, 0.9)
	w.speed = 0.0
	w.hp = 100000.0
	w.max_hp = 100000.0
	w.poison_left = 3.0
	w.poison_dps = 5.0
	g2.take_events()
	_tick(g2, 1.0)
	_check(g2.take_events().is_empty(), "jed posila zvukovou udalost kazdy snimek")
	# STROP UDALOSTI: kdo hru kroka bez obrazovky (simulator), nesmi si
	# pamatovat tisice udalosti.
	var g3: Game = _fresh()
	for i in range(200):
		g3._event("shot")
	_check(g3.events.size() <= Game.MAX_EVENTS,
		"seznam zvukovych udalosti roste bez stropu (%d)" % g3.events.size())


# NEVIDITELNA FIALOVA JE IMUNNI VUCI VSEMU. Jan (Oct 2026): "Fialoví nepřátelé
# teď po prvním zásahu sice zmizí, ale po objevení automaticky samo zemřou.
# Aniž by do nich věž znovu střílela." Byly to dve TICHE cesty, obe bez
# projektilu: JED (ticka dal, i kdyz je poutnik duch) a ODRAZ (vybral si ducha
# za dalsi obet). Zmizeni je pritom cas, kdy na poutnika NEMÁ NIKDO DOSÁHNOUT.
func _test_ghost_is_immune() -> void:
	var g: Game = _fresh()
	g.tower.hue = Hue.YELLOW          # vez do poutnika nestrili
	g.profile.perm["ps"] = 3          # jed 50 % poskozeni rany za sekundu
	var p: Pilgrim = _place(g, Hue.VIOLET, 0.9)
	p.speed = 0.0
	# (test si schvalne dela fialovou schopnost u jine barvy - a schopnosti se
	# v bitve ctou z `behaviours`, takze se musi nastavit i to)
	p.behaviour = Hue.B_VANISH
	p.behaviours = [Hue.B_VANISH]
	g._burn(p, 10.0)                 # prvni zasah: rozjede jed a fialova zmizi
	_check(p.ghost_left > 0.0, "fialova po prvnim zasahu nezmizela")
	_check(p.poison_left > 0.0, "jed se pri zasahu vubec nerozjel")
	var hp0: float = p.hp
	_tick(g, 1.5)
	_check(is_equal_approx(p.hp, hp0),
		"neviditelna fialova ztratila zivoty (o %.2f) - ubira ji jed, i kdyz je duch" % (hp0 - p.hp))
	# PO OBJEVENI uz ji jed ubirat smi - je zase videt.
	p.ghost_left = 0.0
	var hp1: float = p.hp
	_tick(g, 1.0)
	_check(p.hp < hp1, "po objeveni fialove ji jed neubira (%.1f)" % p.hp)
	# ODRAZ SI DUCHE NESMI VYBRAT: dostal by strelu, kterou hrac nikdy nevidel.
	var g2: Game = _fresh()
	g2.tower.hue = Hue.RED
	g2.profile.perm["rc"] = 1
	var a: Pilgrim = _place(g2, Hue.RED, g2.range_frac() * 0.7)
	var ghost: Pilgrim = _place(g2, Hue.RED, g2.range_frac() * 0.7)
	ghost.pos = a.pos + Vector2(50.0, 0.0)
	for w in [a, ghost]:
		w.speed = 0.0
		w.hp = 100000.0
		w.max_hp = 100000.0
	ghost.ghost_left = Hue.VANISH_S
	_check(not g2._chain(a).has(ghost),
		"odraz si vybral neviditelnou fialovou (dostala by ranu od nikud)")


# FIALOVA PO ZNEVIDITELNENI JE VYJIMKA (Jan, Oct 2026): "Když zmizí, projektil
# zkrátka mine. Doletí na místo impaktu, zmizí a neudělí poškození." Pro
# vsechny ostatni barvy plati "vystreleno = doleti" (`_test_shot_lands_after_hue_switch`).
func _test_vanish_stops_the_beam() -> void:
	var g: Game = _fresh()
	g.tower.hue = Hue.RED
	var p: Pilgrim = _place(g, Hue.RED, g.range_frac() * 0.85)
	p.speed = 0.0
	p.hp = 1000.0
	p.max_hp = 1000.0
	# (test si schvalne dela fialovou schopnost u jine barvy - a schopnosti se
	# v bitve ctou z `behaviours`, takze se musi nastavit i to)
	p.behaviour = Hue.B_VANISH
	p.behaviours = [Hue.B_VANISH]
	g.step(1.0 / 240.0)
	_check(p.ghost_left > 0.0, "fialova po prvnim zasahu nezmizela")
	_check(g.beams.size() == 1, "na cervenou fialovou nesviti paprsek (%d)" % g.beams.size())
	var hp0: float = p.hp
	_tick(g, 1.0)
	_check(is_equal_approx(p.hp, hp0), "zmizele fialove paprsek ubiral dal (o %.2f)" % (hp0 - p.hp))
	_check(g.beams.is_empty(), "paprsek sviti na ducha - ten je pritom imunni")


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
	g._burn(p, 10.0)
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
	g._burn(p, 1.0)
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
	# CHLAD DRZI I PO UKONCENI POSKOZOVANI. Jan (Oct 2026): "Chill effect by měl
	# trvat třeba 3s po ukončení dmg." Poutnik zustava zledovany jeste tri sekundy
	# potom, co do nej vez prestala strilet - proto je videt i na tech, kteri uz
	# odesli z dostrelu (a proto to musi byt videt na NEM, ne na paprsku).
	_check(absf(Game.ICE_S - 3.0) < 0.001, "chlad netrva tri sekundy (%.2f s)" % Game.ICE_S)
	var q: Pilgrim = _place(g, Hue.RED, 0.9)
	q.speed = 0.0
	g._burn(q, 1.0)
	_tick(g, 2.0)
	_check(q.slow_mult() < 0.99, "chlad vyprchal driv nez po trech sekundach")
	_check(q.ice_left > 0.9, "po dvou sekundach zbyva chladu %.2f s" % q.ice_left)
	_tick(g, 1.2)
	_check(q.ice_left <= 0.0, "chlad drzi dele nez tri sekundy (%.2f s)" % q.ice_left)


# KOMBINOVANY POUTNIK (plan, ukol 6). Jan: "Žlutý nepřítel je rychlý, ale slabý.
# Červený je pomalý, ale silný. Oranžový bude rychlý a silný. Jejich výskyt
# nesmí být vysoký, jinak by to hráč nemohl zvládnout." + "S průměrováním síly
# souhlasím."
func _test_mix_pilgrim() -> void:
	var g: Game = _fresh()
	# PRED ODEMCENIM MICHANI NEEXISTUJE - ani v planu vlny.
	g.level = 1
	g.refresh_palette()
	_check(Hue.mix_pool_at(1).is_empty(), "v prvnim levelu jde michat")
	for i in range(20):
		for h in g.wave_plan(1):
			_check(not Hue.is_mix(int(h)),
				"kombinovany poutnik se objevil pred odemcenim michani")
	# PO ODEMCENI: chodi, ale vzacne - nejvyc MIX_MAX na vlnu.
	g.level = Hue.MIX_UNLOCK_LEVEL
	g.refresh_palette()
	var seen: int = 0
	for i in range(40):
		var mixes: int = 0
		for h in g.wave_plan(1):
			if Hue.is_mix(int(h)):
				mixes += 1
		seen += mixes
		_check(mixes <= Game.MIX_MAX,
			"na vlnu slo %d kombinovanych poutniku (strop je %d)" % [mixes, Game.MIX_MAX])
	_check(seen > 0, "po odemceni michani se neobjevil zadny kombinovany poutnik")
	# SILA JE PRUMER OBOU BAREV (ne maximum): cervena je silna a pomalá, modra
	# slaba a rychla - oranzova z nich ma byt uprostred.
	var mix: int = Hue.mix_id(Hue.RED, Hue.BLUE)
	var p: Pilgrim = g.spawn_at_angle(0.0, mix)
	var want_hp: float = (g.hp_for(g.kolo(), g.wave, Hue.RED)
		+ g.hp_for(g.kolo(), g.wave, Hue.BLUE)) * 0.5
	_check(absf(p.max_hp - want_hp) < 0.01,
		"kombinovany poutnik nema prumer zivotu (%.1f, ma byt %.1f)" % [p.max_hp, want_hp])
	var want_speed: float = g.pilgrim_speed() * Hue.speed_mult(mix)
	_check(absf(p.speed - want_speed) < 0.01, "kombinovany poutnik nema prumer rychlosti")
	# NA KOMBINOVANEHO POUTNIKA POTREBUJE VEZ OBE BARVY - barva samotna ho nezastavi.
	g.tower.palette = [Hue.RED, Hue.BLUE, Hue.GREEN]
	g.tower.set_hue(Hue.RED)
	_check(not g.tower.sees(p), "vez s jednou barvou vidi kombinovaneho poutnika")
	_check(g.tower.set_pair(Hue.RED, Hue.BLUE), "vez nevzala dvojici cervena+modra")
	_check(g.tower.sees(p), "vez se obema barvama nevidi kombinovaneho poutnika")
	# MA OBE SCHOPNOSTI: zelena leci, modra se rozpadne.
	var q: Pilgrim = g.spawn_at_angle(1.0, Hue.mix_id(Hue.GREEN, Hue.BLUE))
	_check(q.has_behaviour(Hue.B_REGEN) and q.has_behaviour(Hue.B_SPLIT),
		"kombinovany poutnik nema obe schopnosti (%s)" % str(q.behaviours))
	q.hp = q.max_hp * 0.5
	g._advance_behaviour(q, 1.0)
	_check(q.hp > q.max_hp * 0.5, "kombinovany poutnik se neléčí")
	var before: int = g.pilgrims.size()
	g._kill(q)
	# Mrtvy poutnik zustava v poli, dokud ho hra neuklidi - proto + SPLIT_PIECES
	# (a ne -1).
	_check(g.pilgrims.size() == before + Hue.SPLIT_PIECES,
		"kombinovany poutnik se nerozpadl (%d poutniku)" % g.pilgrims.size())
	# A POZNAMKA: hrac musi vedet, proc ho nedokaze zasahnout.
	g.pilgrims.clear()
	g.log.clear()
	g.spawn_at_angle(2.0, Hue.mix_id(Hue.RED, Hue.YELLOW))
	_check(g.last_note().contains("obě barvy"),
		"hra nerekla, ze kombinovany poutnik chce obe barvy (%s)" % g.last_note())


func _test_temp_buy() -> void:
	# MERI SE NA POSKOZENI ("ad"): kadenci ("as") hra od Oct 2026 vubec nema -
	# vez sviti laserem a poskozeni je za sekundu, ne za ranu.
	var g: Game = _fresh()
	g.gold = 100
	var v0: float = g.val("ad")
	_check(g.buy_temp("ad"), "prvni krok se neda koupit")
	_check(g.gold == 95, "prvni krok nestal 5 zlata (zbyva %d)" % g.gold)
	_check(g.val("ad") > v0, "krok nezmenil hodnotu parametru")
	_check(g.buy_temp("ad"), "druhy krok se neda koupit")
	_check(g.gold == 85, "druhy krok nestal 10 zlata (zbyva %d)" % g.gold)
	# BEZ ZLATA SE NEKUPUJE.
	var g2: Game = _fresh()
	g2.gold = 4
	_check(not g2.buy_temp("ad"), "krok se koupil bez zlata")
	_check(g2.gold == 4, "zlato se ubralo, i kdyz se nekoupilo")
	# BEZ STROPU: docasny zebricek uz "MAX" nema (Jan, Oct 2026: "já prozatím
	# nechci žádné stropy"). Kupuje se tak dlouho, dokud je zlato.
	var g3: Game = _fresh()
	g3.gold = 100000
	var want: int = 24
	var sold: int = 0
	for i in range(want):
		if g3.buy_temp("ad"):
			sold += 1
	_check(sold == want, "docasnych kroku poskozeni se koupilo %d z %d" % [sold, want])
	_check(absf(g3.val("ad") - 58.0) < 0.0001,
		"po %d docasnych krocich neni poskozeni 58/s (je %.2f)" % [want, g3.val("ad")])
	_check(g3.val("ad") > 24.0, "docasny zebricek porad konci na stropu 24")
	var paid: int = 100000 - g3.gold
	_check(paid == 5 * (want * (want + 1) / 2), "cena %d docasnych kroku neni %d zlata (%d)" % [want, 5 * (want * (want + 1) / 2), paid])
	_check(g3.buy_temp("ad"), "posledni krok se nedal koupit, i kdyz je zlato")
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
	g.profile.perm["ad"] = 2
	g.start_level(1)
	_quiet(g)
	_check(absf(g.val("ad") - 14.0) < 0.001, "start po dvou permanentních neni 14/s (%.2f)" % g.val("ad"))
	var gold0: int = g.gold
	_check(g.buy_temp("ad"), "krok po permanentnim upgradu nejde koupit")
	_check(gold0 - g.gold == 5, "krok po permanentnim upgradu stoJI jinak nez 5 zlata (%d)" % (gold0 - g.gold))
	_check(absf(g.val("ad") - 16.0) < 0.001, "krok se neprisel k posunutemu startu (%.2f)" % g.val("ad"))


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
	g.buy_temp("ad")
	g.buy_temp("ar")
	var temp_before: int = g.temp.size()
	_check(temp_before > 0, "kroky se vubec nekoupily")
	g.phase = "won"
	g.next_level()
	_check(g.level == 2, "dalsi level neni druhy (%d)" % g.level)
	_check(g.wave == 1, "dalsi level nezacina prvni vlnou (%d)" % g.wave)
	_check(g.temp.is_empty(), "docasne kroky prezily do dalsiho levelu (%s)" % str(g.temp))
	# ZLATO ZACINA ZNOVU, ALE S NASOBILEM LEVELU (viz `Game.GOLD_LEVEL`): hrac
	# nedostane vzdy 150, ale tolik, kolik si zadá obtiznost levelu.
	_check(g.gold == int(round(float(Game.START_GOLD) * g.gold_mult())) + int(round(g.val("gl"))),
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
	# VELIKOST VLNY: v ramci levelu roste a kazdy dalsi LEVEL ji NASOBI (Oct
	# 2026, Jan: "Počet nepřátel v jednotlivých vlnách bude obecně vyšší. V
	# prvních levelech bude začínat třeba na 15. Ve vyšších to budou klidně
	# desítky až stovky."). Strop drzi nekonecnou partii hratelnou.
	_check(g.wave_size(1, 1) < g.wave_size(2, 1), "druha vlna neni vetsi nez prvni")
	_check(g.wave_size(1, 1) >= 15, "prvni vlna nezacina na patnacti (%d)" % g.wave_size(1, 1))
	_check(g.wave_size(1, 5) > g.wave_size(1, 1),
		"druhy level nema vetsi vlnu (%d vs %d)" % [g.wave_size(1, 5), g.wave_size(1, 1)])
	_check(g.wave_size(1, 12) >= 100,
		"ve vysokem levelu nema prvni vlna stovky (%d)" % g.wave_size(1, 12))
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


# OPAKOVANY LEVEL NEDAVA BODY. Hrac se muze vratit k vyhranemu levelu
# (Jan, Oct 2026: "Abych se mohl vrátit i k hotovým.") - ale kdyby se za kazdy
# pruchod platilo, stacilo by opakovat prvni level a body by se jen sypaly.
func _test_replay_no_body() -> void:
	var g := Game.new()
	g.profile = Profile.new()
	g.set_field(300.0, 300.0, Vector2(500.0, 500.0))
	g.profile.best = 5
	g.profile.level = 6
	g.start_level(3)
	var body0: int = g.profile.body
	_win_now(g)
	_check(g.phase == "won", "level se nevyhral (faze %s)" % g.phase)
	_check(g.body_earned == 0, "opakovany level dal %d bodu" % g.body_earned)
	_check(g.profile.body == body0, "opakovany level zmenil body (%d -> %d)" % [body0, g.profile.body])
	_check(g.profile.best == 5 and g.profile.level == 6, "opakovany level posunul postup")
	# A NOVY LEVEL DAL PLATI: sesty level jeste vyhrany nebyl.
	g.next_level()
	_check(g.level == 4, "dalsi level neni ctvrty (%d)" % g.level)
	g.start_level(6)
	_win_now(g)
	_check(g.body_earned == Game.BODY_BASE + Game.BODY_PER_LEVEL * 6,
		"novy level nedal %d bodu (dal %d)" % [Game.BODY_BASE + Game.BODY_PER_LEVEL * 6, g.body_earned])
	_check(g.profile.best == 6 and g.profile.level == 7, "novy level neposunul postup")


# VYHRA LEVELU BEZ CEKANI: prazdna deska znamena, ze vlna je odrazena.
func _win_now(g: Game) -> void:
	g.wave = g.waves_in_level()
	g.phase = "wave"
	g.plan = []
	g.spawned = 0
	g.pilgrims = []
	g.step(0.02)


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
	# PREPINANI: jedno tlacitko, dva stavy. Stav je na HRE, ne na obrazovce -
	# kdyby si ho drzela obrazovka, rozjel by hru kdokoli, kdo zavola `step`.
	g.toggle_pause()
	_check(g.is_paused(), "toggle_pause hru nezastavilo")
	_tick(g, 1.0)
	var held: Vector2 = p.pos
	_tick(g, 1.0)
	_check(p.pos.is_equal_approx(held), "po toggle_pause se poutnik pohnul")
	g.toggle_pause()
	_check(not g.is_paused(), "druhy toggle_pause hru nespustil")
	_tick(g, 0.5)
	_check(not p.pos.is_equal_approx(held), "po druhem toggle_pause se poutnik nepohnul")


# ZLATO ROSTE S OBTIZNOSTI. Zivoty poutniku jdou 1,40x za level; kdyby zlato
# stalo na miste, hrac by za stejne penize kupoval porad slabsi vez a hra by se
# zlomila na startu levelu. Meri se OBÉ strany: zlato za zabiti i zlato na startu.
func _test_gold_scales_with_level() -> void:
	var a: Game = _fresh()
	a.tower.hue = Hue.RED
	var p1: Pilgrim = _place(a, Hue.RED, a.range_frac() * 0.5)
	p1.speed = 0.0
	p1.hp = 1.0
	p1.max_hp = 1.0
	var a0: int = a.gold
	_tick(a, 0.5)
	var drop1: int = a.gold - a0
	_check(drop1 == Hue.gold_of(Hue.RED),
		"zabiti na prvnim levelu neda zakladni zlato (%d, cekano %d)" % [drop1, Hue.gold_of(Hue.RED)])

	var b: Game = _fresh()
	b.tower.hue = Hue.RED
	b.start_level(4)
	_check(b.gold_mult() > 1.0, "nasobek zlata na 4. levelu je porad 1,0")
	_check(b.gold > Game.START_GOLD,
		"start 4. levelu neni bohatsi nez prvni (%d)" % b.gold)
	var want: float = float(Hue.gold_of(Hue.RED)) * b.gold_mult()
	var p2: Pilgrim = _place(b, Hue.RED, b.range_frac() * 0.5)
	p2.speed = 0.0
	p2.hp = 1.0
	p2.max_hp = 1.0
	var b0: int = b.gold
	_tick(b, 0.5)
	var drop2: int = b.gold - b0
	_check(absf(float(drop2) - want) <= 1.0,
		"zabiti na 4. levelu neda vetsi zlato (%d, cekano %.1f)" % [drop2, want])


# FIALOVA JE NEJPOMALEJSI. Jan (Oct 2026): "Upravime rychlost fialovych
# nepratel. Budou ze vsech nejpomalejsi." Test meri SKUTECNE ujete pixely
# vsech sesti barev za stejnou dobu - kdyby `Game` nasobek barvy prestal
# pouzivat, tabulka by lhala dal a test na ni samotnou by to nepoznal.
# Zivoty jsou zamerne obrovske: vez ma merit POHYB, ne to, kdo umre drive.
func _test_hue_speed_order() -> void:
	var g: Game = _fresh()
	var live: Array = []
	var from: Array = []
	for h in range(Hue.COUNT):
		var p: Pilgrim = _place(g, h, 0.75, float(h) * PI / 3.0)
		p.hp = 1.0e9
		live.append(p)
		from.append(p.pos)
	_tick(g, 2.0)
	var moved: Array = []
	for i in range(live.size()):
		moved.append(live[i].pos.distance_to(from[i]))
	_check(moved[Hue.VIOLET] > 1.0, "fialova se vubec nepohnula (%f px)" % moved[Hue.VIOLET])
	for h in range(Hue.COUNT):
		if h == Hue.VIOLET:
			continue
		_check(moved[Hue.VIOLET] < moved[h],
			"fialova (%f px) neni pomalejsi nez barva %d (%f px)" % [moved[Hue.VIOLET], h, moved[h]])


# STRIBRNA MENI PODOBU I SE SCHOPNOSTMI BARVY (Jan, Oct 2026: "Nově budou měnit
# po 5s. A se změnou podoby budou přebírat i výhody jednotlivých barev. Zelená =
# léčení, žlutá = rychlost, modrá = při smrti se rozdělí, fialová = po první ráně
# zmizí, červená = vysoká odolnost. Měly by se měnit i životy. Hra by měla
# přepočítávat podle procentuální hodnoty.")
#
# Testuji se obe pulky zadani: (a) meni podobu po PETI vterinach (ne po trech)
# a meni se dal, (b) nova podoba ma schopnost, rychlost i ZIVOTNI POOL sve barvy -
# a zivoty se prenaseji jako PROCENTO, ne jako cislo. V kazde podobe ma tedy jiny
# pocet zivotu, ale stejny podil.
func _test_silver_shift_form() -> void:
	var g: Game = _fresh()
	var p: Pilgrim = g.spawn_at_angle(0.0, Hue.SILVER)
	p.speed = 0.0
	_check(p.shifting, "stribrna neni oznacena jako menici podobu")
	_check(absf(Hue.SHIFT_S - 5.0) < 0.001,
		"stribrna meni podobu po %.1f s (ma byt 5)" % Hue.SHIFT_S)
	# (a) CAS: po ctyrech vterinach se jeste nic nezmenilo, po peti uz ano.
	var h0: int = p.hue
	g._advance_behaviour(p, 4.0)
	_check(p.hue == h0, "stribrna zmenila podobu driv nez po peti vterinach")
	g._advance_behaviour(p, 1.5)
	_check(p.hue != h0, "stribrna po peti vterinach podobu nezmenila")

	# (b) PROCENTO ZIVOTU A POOL NOVE BARVY.
	p.hp = p.max_hp * 0.4
	g._shift(p)
	var pool: float = g.hp_for(g.kolo(), g.wave, p.hue)
	_check(absf(p.max_hp - pool) < 0.001,
		"nova podoba si nevzala zivotni pool sve barvy (%.1f, ma byt %.1f)"
		% [p.max_hp, pool])
	_check(absf(p.hp_frac() - 0.4) < 0.001,
		"zmena podoby neudrzela procento zivotu (%.3f)" % p.hp_frac())
	_check(p.behaviour == Hue.behaviour_of(p.hue),
		"nova podoba si nevzala schopnost sve barvy (%s)" % p.behaviour)
	_check(absf(p.speed - g.pilgrim_speed() * Hue.speed_mult(p.hue)) < 0.001,
		"nova podoba si nevzala rychlost sve barvy")
	_check(p.shifting, "po zmene podoby se stribrna prestala menit")

	# FIALOVA PODOBA: neviditelnost se zmenou konci a nova podoba ma svuj "prvni
	# zasah" znovu (Jan: "...tak o neviditelnost v rámci změny přijde").
	p.ghost_left = Hue.VANISH_S
	p.was_hit = true
	g._shift(p)
	_check(p.ghost_left == 0.0, "neviditelnost prezila zmenu podoby")
	_check(not p.was_hit, "nova podoba si nese zasah z podoby predchozi")


# ROZPAD MODRE PODOBY STRIBRNE (Jan: "modrá = při smrti se rozdělí (pak už se dvě
# malé kapky chovají standardně)"). Kusy jsou OBYCEJNI poutnici - nemeni podobu
# a maji chovani `none`, takze z jednoho menice nevznikne nekonecny pocet menicu.
func _test_silver_split_form() -> void:
	var g: Game = _fresh()
	# Modra vstupuje do hry ve druhem levelu - v prvnim ji `_random_other_hue`
	# vubec nemuze vybrat (bere jen barvy, ktere na plose jsou).
	g.start_level(3)
	_quiet(g)
	var p: Pilgrim = g.spawn_at_angle(0.0, Hue.SILVER)
	p.speed = 0.0
	var blue: bool = false
	for i in range(200):
		g._shift(p)
		if p.hue == Hue.BLUE:
			blue = true
			break
	_check(blue, "stribrna se v modre podobe vubec neobjevila")
	if not blue:
		return
	_check(p.behaviour == Hue.B_SPLIT, "modra podoba stribrne se nerozpada")
	g._hurt(p, p.max_hp * 2.0)
	var pieces: Array = []
	for q in g.pilgrims:
		if q != p:
			pieces.append(q)
	_check(pieces.size() == Hue.SPLIT_PIECES,
		"modra podoba se nerozpadla na %d kusy (%d)" % [Hue.SPLIT_PIECES, pieces.size()])
	for q in pieces:
		_check(not q.shifting and q.behaviour == Hue.B_NONE,
			"kus po rozpadu meni podobu - ma se chovat standardne")


# SMES DVOU BAREV JE BARVA (Jan, Oct 2026: "Oranžová bude mít - RY jako Red
# Yellow."). Testuji se vsechny slozky, na kterych stoji zbytek hry: id (podle
# poradi barev), dve pismena, vlastni barva a radek v tabulce pro KAZDOU dvojici.
func _test_mix_ids() -> void:
	_check(Hue.mix_id(Hue.RED, Hue.YELLOW) == Hue.mix_id(Hue.YELLOW, Hue.RED),
		"smes cervene a zlute ma jine id podle poradi")
	_check(Hue.is_mix(Hue.mix_id(Hue.RED, Hue.YELLOW)), "id smesi se nepozna jako smes")
	_check(not Hue.is_mix(Hue.RED), "obycejna barva se hlasi jako smes")
	_check(Hue.mix_id(Hue.RED, Hue.RED) == -1, "michani barvy se sebou proslo")
	_check(Hue.pair_of(Hue.mix_id(Hue.RED, Hue.YELLOW)) == [Hue.RED, Hue.YELLOW],
		"smes se nerozlozi na puvodni barvy")
	_check(Hue.pair_of(Hue.RED) == [Hue.RED], "jedna barva se nerozlozi na sebe")
	var ry: int = Hue.mix_id(Hue.RED, Hue.YELLOW)
	_check(Hue.letter_of(ry) == "RY", "smes R+Y nema dve pismena (%s)" % Hue.letter_of(ry))
	_check(Hue.name_of(ry) == "Oranžová", "smes R+Y se nejmenuje Oranzova (%s)" % Hue.name_of(ry))
	_check(Hue.color_of(ry) != Hue.color_of(Hue.RED)
		and Hue.color_of(ry) != Hue.color_of(Hue.YELLOW),
		"smes ma stejnou barvu jako nekterá z obou slozek")
	# ZADNA DVOJICE Z PALETY NESMI ZUSTAT BEZ RADKU V TABULCE - jinak by se
	# kreslila zalozni seda a hrac by nevidel, co si to vlastne namichal.
	# (Stribrna v palete nikdy neni, takze smes s ni vzniknout nemuze.)
	for i in Hue.palette_at(Hue.MIX_UNLOCK_LEVEL):
		for j in Hue.palette_at(Hue.MIX_UNLOCK_LEVEL):
			if int(j) <= int(i):
				continue
			var m: int = Hue.mix_id(int(i), int(j))
			_check(Hue.MIXES.has(Hue.mix_key(m)),
				"dvojice %s nema radek v tabulce smesi" % Hue.mix_key(m))
			_check(Hue.color_of(m) != Hue.MIX_FALLBACK["color"],
				"dvojice %s se kresli zalozni barvou" % Hue.mix_key(m))
			_check(Hue.letter_of(m).length() == 2,
				"smes %s nema dve pismena" % Hue.mix_key(m))
	# HODNOTY SMESI = PRUMER OBOU BAREV (Jan: "S průměrováním síly souhlasím."),
	# ne maximum - zluta je rychla a slaba, cervena pomala a silna.
	var want_hp: float = (Hue.hp_mult(Hue.RED) + Hue.hp_mult(Hue.YELLOW)) * 0.5
	_check(absf(Hue.hp_mult(ry) - want_hp) < 0.001,
		"smes R+Y nema prumer zivotu obou barev (%.2f, ma byt %.2f)" % [Hue.hp_mult(ry), want_hp])
	var want_sp: float = (Hue.speed_mult(Hue.RED) + Hue.speed_mult(Hue.YELLOW)) * 0.5
	_check(absf(Hue.speed_mult(ry) - want_sp) < 0.001, "smes R+Y nema prumer rychlosti")


# VEZ VIDI JEN SVOU BARVU - A U SMESI MUSI MIT POUTNIK VSEchny JEJI BARVY
# (Jan: "RY - Věž může útočit na červenou, žlutou a oranžovou. R - Věž útočí jen
# na červenou, ne na oranžovou.").
func _test_covers() -> void:
	var r: Array = [Hue.RED]
	var ry: Array = [Hue.RED, Hue.YELLOW]
	var oranzova: int = Hue.mix_id(Hue.RED, Hue.YELLOW)
	_check(Hue.covers(r, Hue.RED), "cervena vez nevidi cervenou")
	_check(not Hue.covers(r, oranzova), "cervena vez vidi oranzovou")
	_check(not Hue.covers(r, Hue.BLUE), "cervena vez vidi modrou")
	_check(Hue.covers(ry, Hue.RED) and Hue.covers(ry, Hue.YELLOW) and Hue.covers(ry, oranzova),
		"vez s RY nevidi cervenou, zlutou a oranzovou")
	_check(not Hue.covers(ry, Hue.BLUE), "vez s RY vidi modrou")
	# A OPRAVDU SE TO PROJEVI VE HRE: vez se smesi zamiri na obe sve barvy,
	# ale na treti ne. (Tohle je jedine misto, kde se o barve rozhoduje.)
	var g: Game = _fresh()
	g.tower.palette = [Hue.RED, Hue.YELLOW, Hue.BLUE]
	_check(g.tower.set_pair(Hue.RED, Hue.YELLOW), "vez nevzala dvojici R+Y")
	var a: Pilgrim = _place(g, Hue.RED, 0.5)
	var b: Pilgrim = _place(g, Hue.YELLOW, 0.5)
	var c: Pilgrim = _place(g, Hue.BLUE, 0.5)
	_check(g.tower.sees(a) and g.tower.sees(b), "vez s RY nevidi jednu ze svych barev")
	_check(not g.tower.sees(c), "vez s RY vidi modrou")
	_check(g.tower.mix() == oranzova, "vez s dvojici nehlasi smes")
	_check(g.tower.color() != Hue.color_of(Hue.RED), "vez s dvojici ma barvu jedne slozky")


# DVOJTAP NA PALETE (Jan: "Jeden obyčejný tap = výběr jednoduché barvy. Dva tapy
# za sebou na stejnou barvu = promíchání barvy do již zvolené ... Jakmile je
# navolena kombinace, tak pro změnu musí hráč vždy udělat prvně jeden tap na
# jinou barvu a tím výběr resetuje.").
func _test_mix_taps() -> void:
	var g: Game = _fresh()
	g.level = 1
	g.refresh_palette()
	_quiet(g)
	# PRED SESTYM LEVELEM SE NEMICHA: hrac ma dve barvy, ale michani jeste nema.
	g.tap_hue(Hue.RED)
	g.tap_hue(Hue.RED)
	_check(g.tower.hues == [Hue.RED], "michani slo uz v prvnim levelu")
	_check(not Hue.mix_unlocked(1) and Hue.mix_unlocked(Hue.MIX_UNLOCK_LEVEL),
		"michani je odemcene v jinem levelu nez v sestem")
	_check(Hue.mix_pool_at(1).is_empty(), "v prvnim levelu existuje smes")
	# OD SESTEHO LEVELU: dvojtap do 0,3 s promicha, druhy tap pozdeji ne.
	g.level = Hue.MIX_UNLOCK_LEVEL
	g.refresh_palette()
	_quiet(g)
	_check(not Hue.mix_pool_at(Hue.MIX_UNLOCK_LEVEL).is_empty(),
		"v sestem levelu neni zadna smes k dispozici")
	g.tap_hue(Hue.RED)
	_check(g.tower.hues == [Hue.RED], "obycejny tap nevybral cervenou")
	g.tap_hue(Hue.YELLOW)
	_check(g.tower.hues == [Hue.YELLOW], "druha barva nevybrala jednoduse")
	g.tap_hue(Hue.YELLOW)
	_check(g.tower.hues == [Hue.RED, Hue.YELLOW], "dvojtap nepromichal cervenou se zlutou")
	_check(g.tower.mix() == Hue.mix_id(Hue.RED, Hue.YELLOW), "smes neni oranzova")
	g.tap_hue(Hue.BLUE)
	_check(g.tower.hues == [Hue.BLUE], "tap z kombinace nevybral jednoduchou barvu")
	g.tick(1.0)
	g.tap_hue(Hue.BLUE)
	_check(g.tower.hues == [Hue.BLUE], "dva tapy s odstupem se pocitaly jako dvojtap")
	g.tap_hue(Hue.RED)
	g.tap_hue(Hue.RED)
	_check(g.tower.hues == [Hue.RED, Hue.BLUE],
		"dvojtap nepromichal modrou s cervenou (%s)" % str(g.tower.hues))
