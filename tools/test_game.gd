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
	_run("mezera mezi poutniky", _test_spawn_gap)
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
	g.auto_wave = false
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

func _test_spawn_gap() -> void:
	# HRAC MUSI STIHNOUT PREPNOUT VYHYBKU PRO KAZDEHO POUTNIKA ZVLAST, takze
	# dve klepnuti se musi vejit do mezery mezi dvema poutniky. Rozvrh se
	# losuje pri kazde vlne zvlast, takze se to hlida na nekolika vlnach:
	# meri se SKUTECNE mezery z rozvrhu, ne konstanta.
	for w in range(1, 8):
		var g := _new_game()
		g.wave = w - 1
		g.start_wave()
		var n: int = g.spawn_times.size()
		_check(n == 3 + w, "vlna %d ma naplanovat %d poutniku, ma %d" % [w, 3 + w, n])
		if n < 2:
			continue
		_check(float(g.spawn_times[0]) == 0.0,
			"vlna %d nezacina vstupem - hrac by koukal do prazdne mapy" % w)
		var seen: Dictionary = {}
		for i in range(1, n):
			var gap: float = (float(g.spawn_times[i]) - float(g.spawn_times[i - 1]))
			# mezera v pixelech: presne to, co hrac vidi mezi poutniky
			var px: float = gap * float(g.level.speed)
			_check(px >= 90.0, "vlna %d: poutnici jsou moc u sebe (%.0f px)" % [w, px])
			seen[int(roundf(gap * 100.0))] = true
		# NEPRAVIDELNE: kdyby vysly vsechny mezery stejne, je to porad ta
		# stara perioda a Janovo "chodí předvídatelně" by zustalo.
		_check(seen.size() >= 2, "vlna %d: mezery mezi poutniky jsou vsechny stejne" % w)
		# ROZLOZENE DO KOLA: posledni poutnik vstoupi nejpozdeji ve trech
		# ctvtinach kola. Zbytek kola uz jen dochazi do cile - presne to
		# Jan chtel ("3/4 času kola ... a pak už jen hráč počká").
		var walk: float = g.walk_time()
		var last: float = float(g.spawn_times[n - 1])
		var share: float = last / maxf(last + walk, 0.001)
		_check(share >= 0.6,
			"vlna %d: poutnici vstupuji jen v %.0f %% kola, maji ve trech ctvtinach" % [
				w, share * 100.0])


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
