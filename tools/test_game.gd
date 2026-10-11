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
	_run("vstupni usek", _test_entry_free)
	_run("poskozeni na useku", _test_zone_damage)
	_run("cesta sama nezabiji", _test_path_alone_wont_kill)
	_run("vlastni zivel", _test_own_element_is_free)
	_run("prepnuti vyhybky", _test_switch_changes_route)
	_run("poutnik dojde do cile", _test_reaches_exit)
	_run("vstupy v kole", _test_round_spawns)
	_run("typ vstupniho useku", _test_entry_type)
	_run("determinismus", _test_determinism)
	_run("prohra pri zahlceni", _test_pile_up_loses)
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


func _test_entry_free() -> void:
	var g := _new_game()
	var e: Enemy = g.debug_spawn(Element.FIRE)
	_check(e.lane == g.net.entry_lane, "poutnik nevstoupil na vstupni usek")
	_check(g.dps_on(e) == 0.0, "na vstupnim useku se poskozuje")
	# projdi cely vstupni usek - porad bez skrabnuti
	g.run_for(g.net.lane_len[e.lane] / e.speed * 0.9)
	_check(e.hp >= e.max_hp - 0.001, "poutnik dostal rany jeste pred vyhybkou")


# ---------------------------------------------------------------- poskozeni

func _test_zone_damage() -> void:
	var g := _new_game()
	var fire: int = _lane_with(g, Element.FIRE)
	_check(fire >= 0, "v mape neni ohnivy usek")
	if fire < 0:
		return
	var e: Enemy = g.debug_spawn(Element.WATER)
	var full: float = e.max_hp
	e.lane = fire
	e.s = 0.0
	var traverse: float = g.net.lane_len[fire] / e.speed
	g.run_for(traverse * 0.97)
	# voda na ohni = protiklad = 2x, tedy 60 za cele projeti
	_check(e.hp > 0.0, "poutnik mel po projeti ohniveho useku prezit")
	var got: float = full - e.hp
	var want: float = g.level.zone_dmg * 2.0 * 0.97
	_check(absf(got - want) < 2.0, "voda na ohni ma dostat %.1f, dostala %.1f" % [want, got])
	# S BONUSEM UZ ALE MUSI UMRIT. Presne to je jadro hry: cesta sama
	# nedokaze zabit, investice ano.
	g.gold = 1000
	_check(g.try_build(fire, 0, Element.FIRE), "bonus na ohnivy usek nejde postavit")
	var e2: Enemy = g.debug_spawn(Element.WATER)
	e2.lane = fire
	e2.s = 0.0
	g.run_for(g.net.lane_len[fire] / e2.speed * 1.05)
	_check(not e2.alive, "s bonusem mel poutnik na svem protikladu umrit")


func _test_path_alone_wont_kill() -> void:
	# CELE JADRO BALANCE: cesta sama nesmi nikoho zabit. Kdyby ano,
	# stavet bonusy by bylo zbytecne a hra by nemela zadne rozhodnuti.
	var g := _new_game()
	var fire: int = _lane_with(g, Element.FIRE)
	if fire < 0:
		return
	var e: Enemy = g.debug_spawn(Element.WATER)
	e.lane = fire
	e.s = 0.0
	g.run_for(g.net.lane_len[fire] / e.speed * 0.99)
	_check(e.hp > 0.0, "cesta sama zabila - balance je rozbita")


func _test_own_element_is_free() -> void:
	var g := _new_game()
	var fire: int = _lane_with(g, Element.FIRE)
	if fire < 0:
		return
	var e: Enemy = g.debug_spawn(Element.FIRE)
	e.lane = fire
	e.s = 0.0
	g.run_for(g.net.lane_len[fire] / e.speed * 0.99)
	_check(e.hp >= e.max_hp - 0.01,
		"poutnik na svem vlastnim useku dostal rany (hp %.2f z %.2f)" % [e.hp, e.max_hp])


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


# VSTUPNI USEK JE OD VYCHOZIHO STAVU KMEN, ALE JE TO NORMALNI TYP USEKU:
# hrac ho muze prepnout na element (pak poskozuje a da se na nem stavet)
# a zpet na kmen. Jan: "Slo by rucne tuto vstupni cestu take prepnout na
# neco jineho nez kmen, nebo naopak prepnout na kmen."
func _test_entry_type() -> void:
	var g := _new_game()
	var entry: int = g.net.entry_lane
	_check(entry >= 0, "sit nema vstupni usek")
	if entry < 0:
		return
	_check(g.level.lane_is_kmen(entry), "vstupni usek neni kmen (je %s)"
		% g.level.lane_type_name(entry))
	var e: Enemy = g.debug_spawn(Element.FIRE)
	e.lane = entry
	e.s = 0.0
	_check(g.dps_on(e) == 0.0, "na kmeni se poskozuje")

	# PREPNUTI NA ELEMENT: poskozuje (a proto se na nem da i stavet).
	# PO ZMENE LEVELU SE SIT STAVI ZNOVU - mista na bonus se pocitaji pri
	# stavbe site (neposkrzujici usek zadna nema), takze teprve prestavena
	# sit vi, ze se na vstupnim useku da stavet. Presne to dela i editor,
	# kdyz hrac zmackne "hrat".
	g.level.set_lane_element(entry, Element.WATER)
	g.setup(Rect2(0, 0, 960, 600), 1.0, 1.0e9, g.level)
	var e2: Enemy = g.debug_spawn(Element.FIRE)
	e2.lane = entry
	e2.s = 0.0
	_check(g.dps_on(e2) > 0.0, "vstupni usek prepnuty na element neposkozuje")
	_check(g.level.lane_takes_bonus(entry), "na elementarnim vstupnim useku nejde stavet")
	_check(g.net.slot_count(entry) > 0, "na vstupnim useku se neobjevila mista na bonus")
	_check(g.try_build(entry, 0, Element.WATER), "bonus na vstupni usek nejde postavit")

	# ZPET NA KMEN: zase neposkozuje a bonus se na nej nevejde
	g.level.set_lane_element(entry, Level.KMEN)
	g.setup(Rect2(0, 0, 960, 600), 1.0, 1.0e9, g.level)
	var e3: Enemy = g.debug_spawn(Element.FIRE)
	e3.lane = g.net.entry_lane
	e3.s = 0.0
	_check(g.dps_on(e3) == 0.0, "po prepnuti zpet na kmen se porad poskozuje")
	_check(not g.level.lane_takes_bonus(g.net.entry_lane), "kmen bere bonus")
	_check(g.net.slot_count(g.net.entry_lane) == 0, "na kmeni jsou mista na bonus")


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
