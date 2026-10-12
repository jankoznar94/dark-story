extends SceneTree

# Test DATOVEHO MODELU MRÍŽKY (scripts/level.gd).
# Vystup: GRID_ALL_PASS=true / false
#
# Testuje se to, co se neda poznat okem: ze graf opravdu drzi pohromade,
# ze se z kazdeho useku da dojit k cili a ze zly nakres se pozna.

var fails: Array = []
var checks: int = 0


func _init() -> void:
	# Kazda testovaci funkce se pousti pres _run. Kdyz uvnitr spadne
	# GDScript chyba, beh pokracuje a funkce jen nic nezaznamena - test by
	# pak "prosel", i kdyby vsechno selhalo. _run na to ma past.
	_run("zakladni deska", _test_base_board)
	_run("geometrie", _test_base_geometry)
	_run("volba ve vyhybce", _test_choices)
	_run("delka hotove cesty", _test_lane_bend)
	_run("posun vystupku cesty", _test_bump_shift)
	_run("posun cele rovne cary", _test_move_piece)
	_run("kod levelu", _test_code_round_trip)
	_run("mista na useku", _test_lane_slots)
	_run("odmitnuti", _test_rejects)
	_run("mapa z nakresu", _test_jan_map_shape)
	_run("vic vstupu", _test_multi_start)
	_run("posila se jen zivel s protikladem", _test_spawn_needs_opposite)
	_run("neutralni cesta neposila nikoho", _test_neutral_lane_sends_nobody)
	_run("diamant", _test_diamond_survives)
	if fails.is_empty():
		print("GRID_ALL_PASS=true (%d kontrol)" % checks)
		quit(0)
	else:
		for f in fails:
			print("  FAIL: " + str(f))
		print("GRID_ALL_PASS=false (%d kontrol)" % checks)
		quit(1)


func _run(label: String, fn: Callable) -> void:
	var before: int = checks
	fn.call()
	if checks == before:
		fails.append("test '%s' neudelal ani jednu kontrolu - spadl uvnitr" % label)


# POSILA SE JEN ZIVEL, KTERY MA V MAPE SVUJ PROTIKLAD. Poutnik bez protikladu
# se neda zabit (vlastni usek 0 %, ostatni jen polovinu, a to ani s bonusem
# nestaci), takze by byl jen ztraceny zivot. Jan: "aby hra posilala jen zivly,
# ktere maji v mape svuj protiklad".
#
# ZAKLADNI DESKA MA V SOBE I NEUTRALNI USEK a ten se tu ZAMERNE NECHAAVA: je to
# presne to misto, kde stalo zrusene pravidlo. Jan (Oct 2026): "Zrušíme
# pravidlo, že při přítomnosti neutrální cesty se spawnují všechny druhy
# nepřátel. Budou se zkrátka spawnovat jen ty, co mají protiklad."
func _test_spawn_needs_opposite() -> void:
	var lv := Level.base()
	_check(lv.has_neutral_lane(), "zakladni deska nema neutralni usek (test meri neco jineho)")
	_check(lv.spawn_elements() == [0, 1, 2, 3],
		"zakladni deska neposila vsechny ctyri zivly: " + str(lv.spawn_elements()))
	_check(lv.unkillable_elements().is_empty(),
		"zakladni deska hlasi nezabitelny zivel: " + str(lv.unkillable_elements()))

	# Vzduch z mapy pryc -> Zeme ztrati svuj protiklad a nesmi se posilat.
	# NEUTRALNI CESTA V MAPE PORAD JE - a presto se neposila vsechno: presne
	# tady vracel stary kod vsechny ctyri zivly.
	for i in range(lv.lane_count()):
		if lv.lane_element(i) == Element.AIR:
			lv.set_lane_element(i, Level.KMEN)
	_check(lv.present_elements() == [Element.FIRE, Element.WATER, Element.EARTH],
		"z mapy nezmizel jen vzduch: " + str(lv.present_elements()))
	_check(lv.has_neutral_lane(), "neutralni usek z mapy zmizel (test meri neco jineho)")
	_check(lv.spawn_elements() == [Element.FIRE, Element.WATER],
		"Zeme bez vzduchu se porad posila (neutralni cesta se pocita jako protiklad): "
		+ str(lv.spawn_elements()))
	_check(lv.unkillable_elements() == [Element.EARTH],
		"Zeme bez vzduchu neni hlasena jako nezabitelna: " + str(lv.unkillable_elements()))

	# Zbyde Ohen a Zeme, oba bez protikladu -> neposila se nikdo a mapa to rekne
	for i in range(lv.lane_count()):
		if lv.lane_element(i) == Element.WATER:
			lv.set_lane_element(i, Level.KMEN)
	_check(lv.present_elements() == [Element.FIRE, Element.EARTH],
		"z mapy nezmizela jen voda: " + str(lv.present_elements()))
	_check(lv.spawn_elements().is_empty(),
		"mapa bez jedineho protikladu posila poutniky: " + str(lv.spawn_elements()))
	_check(lv.unkillable_elements() == [Element.FIRE, Element.EARTH],
		"zivly bez protikladu nejsou hlaseny: " + str(lv.unkillable_elements()))

	# A HRA TO REKNE V HLASCE - ticha zmena by nechala hrace hledat chybu v siti.
	var g := Game.new()
	g.auto_round = false
	g.setup(Rect2(0, 0, 960, 600), 1.0, 1.0e9, lv)
	g.start_round()
	var last: String = str(g.log[g.log.size() - 1])
	_check(last.contains("protiklad"), "hlaska o chybejicim protikladu neni: " + last)
	_check(g.spawn_pool.is_empty(), "sit si bere zivly, ktere se neposilaji")

	# DRUHE DVE PRICINY, PROC NIKDO NECHODI, VYPAADAJI NA OBRAZOVCE STEJNE
	# (kolo bezi, deska prazdna). Jan: "Po spuštění levelu v editoru teď
	# nepřátelé vůbec nechodí. Nebo je to nějakým nastavením?" - presne proto
	# to hra musi rict slovy.
	var km := Level.new()
	km.add_node(1, 5, Level.START)
	km.add_node(13, 5, Level.CIL)
	km.add_lane(0, 1, "R".repeat(12), Level.KMEN)
	var g2 := Game.new()
	g2.auto_round = false
	g2.setup(Rect2(0, 0, 960, 600), 1.0, 1.0e9, km)
	g2.start_round()
	var last2: String = str(g2.log[g2.log.size() - 1])
	_check(last2.contains("živl"), "mapa bez jedineho zivlu to nerekne: " + last2)

	# MAPA BEZ STARTU: poutnik nema kudy vejit. Siti v tom pripade nevznikne
	# zadny vstupni usek, takze se neposle nikdo - i kdyz je z ceho.
	var ns := Level.new()
	ns.add_node(4, 5, Level.VYHYBKA)
	ns.add_node(3, 1, Level.CIL)
	ns.add_node(3, 9, Level.CIL)
	ns.add_lane(0, 1, "L L U U U U", Element.FIRE)
	ns.add_lane(0, 2, "L L D D D D", Element.WATER)
	var g3 := Game.new()
	g3.auto_round = false
	g3.setup(Rect2(0, 0, 960, 600), 1.0, 1.0e9, ns)
	_check(g3.net.entry_lanes.is_empty(), "mape bez startu se nasel vstup")
	_check(not g3.spawn_pool.is_empty(), "z teto mapy neni co posilat (test meri neco jineho)")
	g3.start_round()
	var last3: String = str(g3.log[g3.log.size() - 1])
	_check(last3.contains("start"), "mapa bez startu to nerekne: " + last3)


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails.append(msg)


# NEUTRALNI CESTA SAMA O SOBE NEPOSILA NIKOHO. Seda vez bere sice vsem 100 %,
# takze se z ni dalo poslat vsechno - ale Jan to zrusil (Oct 2026): "Zrušíme
# pravidlo, že při přítomnosti neutrální cesty se spawnují všechny druhy
# nepřátel. Budou se zkrátka spawnovat jen ty, co mají protiklad."
#
# Kontroluje se i to, co je na obrazovce stejne (kolo bezi, deska prazdna):
# hra musi rict SLOVY, proc nikdo nechodi - neutralni usek neni element,
# takze plati veta "v mape neni ani jeden usek s zivlem".
func _test_neutral_lane_sends_nobody() -> void:
	var lv := Level.new()
	lv.add_node(1, 5, Level.START)
	lv.add_node(6, 5, Level.UZEL)
	lv.add_node(20, 5, Level.CIL)
	lv.add_lane(0, 1, "R R R R R", Level.KMEN)
	lv.add_lane(1, 2, "R".repeat(14), Level.NEUTRAL)
	_check(lv.validate().is_empty(), "mapa s neutralni cestou neprojde: " + str(lv.validate()))
	_check(lv.has_neutral_lane(), "neutralni usek se nenasel")
	_check(lv.present_elements().is_empty(),
		"z neutralni cesty se stal element: " + str(lv.present_elements()))
	_check(lv.spawn_elements().is_empty(),
		"z neutralni cesty se posilaji poutnici: " + str(lv.spawn_elements()))
	_check(lv.unkillable_elements().is_empty(),
		"mapa bez jedineho zivlu hlasi nezabitelny zivel: " + str(lv.unkillable_elements()))

	# HRA SI SEZNAM VEZME Z LEVELU - kdyby ho pocitala sama, meli bychom dve
	# pravdy o tom, kdo muze chodit.
	var g := Game.new()
	g.auto_round = false
	g.setup(Rect2(0, 0, 960, 600), 1.0, 1.0e9, lv)
	_check(g.spawn_pool.is_empty(), "sit posila %s" % str(g.spawn_pool))
	g.start_round()
	var last: String = str(g.log[g.log.size() - 1])
	_check(last.contains("živl"), "mapa z neutralnich cest to nerekne: " + last)

	# OPAK NA DRUHE STRANE: neutralni usek se zmeni na OHEŇ - a ten svuj
	# protiklad (vodu) v mape nema, takze se z nej taky neposila. Rozhoduje
	# protiklad, ne "je to neutralni".
	lv.set_lane_element(1, Element.FIRE)
	_check(not lv.has_neutral_lane(), "neutralni usek z mapy nezmizel")
	_check(lv.present_elements() == [Element.FIRE],
		"z mapy neni jen ohen: " + str(lv.present_elements()))
	_check(lv.spawn_elements().is_empty(),
		"ohen bez vody se posila: " + str(lv.spawn_elements()))
	_check(lv.unkillable_elements() == [Element.FIRE],
		"ohen bez vody neni hlasen jako nezabitelny: " + str(lv.unkillable_elements()))
	var g2 := Game.new()
	g2.auto_round = false
	g2.setup(Rect2(0, 0, 960, 600), 1.0, 1.0e9, lv)
	g2.start_round()
	var last2: String = str(g2.log[g2.log.size() - 1])
	_check(last2.contains("protiklad"), "ohen bez vody se nerekne: " + last2)


# ---------------------------------------------------------------- zakladni deska

func _test_base_board() -> void:
	var lv := Level.base()
	var errs: Array = lv.validate()
	_check(errs.is_empty(), "zakladni deska je rozbita: " + str(errs))
	_check(lv.node_count() == 8, "zakladni deska ma mit 8 uzlu, ma %d" % lv.node_count())
	_check(lv.lane_count() == 7, "zakladni deska ma mit 7 useku, ma %d" % lv.lane_count())
	_check(lv.exit_count() == 5, "zakladni deska ma mit 5 cílu, ma %d" % lv.exit_count())
	_check(lv.first_start() >= 0, "zakladni deska nema start")
	var els: Array = lv.spawn_elements()
	_check(els == [0, 1, 2, 3], "zakladni deska ma posilat vsechny ctyri zivly, posila %s" % str(els))
	# prave jeden usek je vstupni (ze startu) a neposkozuje - a to proto,
	# ze je to KMEN, ne kvuli nejakemu priznaku
	var entries: int = 0
	for i in range(lv.lane_count()):
		if lv.lane_is_entry(i):
			entries += 1
			_check(lv.lane_is_kmen(i),
				"vstupni usek %d neni kmen (je %s)" % [i, lv.lane_type_name(i)])
	_check(entries == 1, "vstupni usek ma byt prave jeden, je %d" % entries)


func _test_base_geometry() -> void:
	var lv := Level.base()
	# kazdy usek: sousedni bunky, prvni a posledni je bunka uzlu
	for i in range(lv.lane_count()):
		var cs: Array = lv.lane_cells(i)
		_check(cs.size() >= 2, "usek %d je kratsi nez dve bunky" % i)
		_check(lv.lane_start_node(i) >= 0, "usek %d nezacina v uzlu" % i)
		_check(lv.lane_end_node(i) >= 0, "usek %d nekonci v uzlu" % i)
		for k in range(1, cs.size()):
			var a: Vector2i = cs[k - 1]
			var b: Vector2i = cs[k]
			_check(absi(a.x - b.x) + absi(a.y - b.y) == 1,
				"usek %d se v bode %d lame sikmo" % [i, k])
	# kazda bunka je v mrizce
	for i in range(lv.lane_count()):
		for cell in lv.lane_cells(i):
			var c: Vector2i = cell
			_check(lv.in_bounds(c.x, c.y), "usek %d vede mimo mrizku (%d,%d)" % [i, c.x, c.y])


# ---------------------------------------------------------------- volba ve vyhybce

func _test_choices() -> void:
	var lv := Level.base()
	var start: int = lv.first_start()
	_check(lv.node_choice_count(start) == 1, "start ma mit prave jeden vystup")
	var first: int = lv.next_lane(start, 0)
	_check(first >= 0, "ze startu se neda nikam jit")
	var j1: int = lv.lane_end_node(first)
	_check(lv.node_kind(j1) == Level.VYHYBKA, "za startem ma byt vyhybka")
	_check(lv.node_choice_count(j1) == 3, "prvni vyhybka ma mit 3 vystupy, ma %d"
		% lv.node_choice_count(j1))
	# volba 0 = ohen, 1 = dal po rade na druhou vyhybku, 2 = vzduch
	# (protiklady musi lezet VEDLE SEBE, aby na ne vez dosahla - viz Level.base)
	var c0: int = lv.node_choice(j1, 0)
	var c1: int = lv.node_choice(j1, 1)
	var c2: int = lv.node_choice(j1, 2)
	_check(lv.lane_element(c0) == Element.FIRE, "volba 0 neni ohen")
	_check(lv.lane_element(c1) == Level.NEUTRAL, "volba 1 neni neutralni")
	_check(lv.lane_element(c2) == Element.AIR, "volba 2 neni vzduch")
	# neutralni volba vede na druhou vyhybku
	_check(lv.node_kind(lv.lane_end_node(c1)) == Level.VYHYBKA, "volba 1 nevede na vyhybku")
	# ze spojky/uzlu se nevybira - maji jeden vystup
	var j2: int = lv.lane_end_node(c1)
	_check(lv.node_choice_count(j2) == 3, "druha vyhybka ma mit 3 vystupy")
	# cesta do cile: kazda volba konci v cili
	for k in range(lv.node_choice_count(j2)):
		var ln: int = lv.node_choice(j2, k)
		_check(lv.node_kind(lv.lane_end_node(ln)) == Level.CIL,
			"vystup %d z druhe vyhybky nevede do cile" % k)


# DELKA HOTOVE CESTY. Jan (Oct 2026): "Ještě by to chtělo možnost
# zvětšovat/zmenšovat existující cesty... abych nemusel vše dokola mazat
# a znovu vkládat." Uzly se nehybou, meni se jen tvar cesty mezi nimi -
# a prodlouzeni i zkraceni musi byt vratne (co se prida, to se zas vezme).
func _test_lane_bend() -> void:
	var lv := Level.base()
	var lane: int = -1
	for i in range(lv.lane_count()):
		if lv.lane_cells(i).size() >= 4:
			lane = i
			break
	_check(lane >= 0, "v mape neni cesta, kterou by slo prodlouzit")
	if lane < 0:
		return
	var before: Array = lv.lane_cells(lane).duplicate()
	var head: Vector2i = before[0]
	var tail: Vector2i = before[before.size() - 1]
	var errs0: int = lv.validate().size()
	# 1) PRODLOUZENI
	_check(lv.bend_lane(lane, true), "cesta nejde prodloužit")
	var mid: Array = lv.lane_cells(lane)
	_check(mid.size() == before.size() + 2,
		"prodlouzeni nepridalo dve bunky (%d -> %d)" % [before.size(), mid.size()])
	_check(mid[0] == head and mid[mid.size() - 1] == tail,
		"prodlouzeni posunulo konec cesty (%s..%s)" % [str(mid[0]), str(mid[mid.size() - 1])])
	for i in range(mid.size() - 1):
		var d: Vector2i = mid[i + 1] - mid[i]
		_check(absi(d.x) + absi(d.y) == 1,
			"cesta po prodlouzeni neni souvisla (krok %d)" % i)
	_check(lv.validate().size() <= errs0, "prodlouzeni rozbilo mapu: %s" % str(lv.validate()))
	# 2) ZKRACENI ZPET - a musi dat PRESNE puvodni cestu
	_check(lv.bend_lane(lane, false), "cestu nejde zase zkrátit")
	var back: Array = lv.lane_cells(lane)
	_check(back.size() == before.size(),
		"zkraceni nedalo puvodni delku (%d vs %d)" % [back.size(), before.size()])
	for i in range(mini(back.size(), before.size())):
		_check(back[i] == before[i], "zkraceni nedalo puvodni cestu (bunka %d)" % i)
	# 3) DVE CESTY VEDLE SEBE: prodlouzeni nesmi pridat bunku, ktera lezi na
	# jine ceste. POZOR: cesty se v UZLECH sdileji odjakziva (vyhybka je
	# koncova bunka vice cest), takze se hlida jen to, ze zadna NOVE pridana
	# bunka na jine ceste nelezi.
	var lv2 := Level.base()
	var done: bool = false
	for i in range(lv2.lane_count()):
		if done:
			break
		var before2: Array = lv2.lane_cells(i).duplicate()
		if lv2.bend_lane(i, true):
			done = true
			var cs: Array = lv2.lane_cells(i)
			for j in range(lv2.lane_count()):
				if j == i:
					continue
				for oc in lv2.lane_cells(j):
					var o: Vector2i = oc
					if not cs.has(o):
						continue
					_check(before2.has(o),
						"prodlouzena cesta %d lezi na ceste %d v bunce %s" % [i, j, str(o)])
	_check(done, "zadna cesta na zakladni desce se neda prodlouzit")
	# 4) MIMO VYBER: neexistujici usek se neupravi
	_check(not lv2.bend_lane(-1, true), "uprava neexistujiciho useku prošla")
	_check(not lv2.bend_lane(lv2.lane_count(), true), "uprava useku za koncem prosla")


# ---------------------------------------------------------------- kod levelu

# POSUN "OBDELNIKOVEHO VYSTUPKU" (Jan, Oct 2026): "Představuji si to tak, že mám
# třeba cestu ve tvaru obdélníkového výstupku, chytnu prstem horní část
# obdélníku, potáhnu nahoru, a celá tato část se posune nahoru, přičemž boční
# strany se automaticky natáhnou."
#
# Hlida se TVAR, ne jen delka: vrsek musi zustat rovny a obe bocni strany stejne
# dlouhe (zadne schodky), a tah zpet musi dat PRESNE puvodni cestu.
func _test_bump_shift() -> void:
	var lv := Level.new()
	var s: int = lv.add_node(2, 5, Level.START)
	var c: int = lv.add_node(7, 5, Level.CIL)
	lv.add_lane(s, c, "RRURDRR", Element.FIRE)
	var before: Array = lv.lane_cells(0).duplicate()
	_check(before.size() == 8, "testovaci vystupek nema 8 bunek (%d)" % before.size())
	# 1) KUS SE NAJDE: vrsek vystupku (4,4),(5,4) se posouva nahoru
	var run: Dictionary = lv.run_at(0, Vector2i(4, 4))
	_check(not run.is_empty(), "na vrsku vystupku se nenasel rovny kus")
	if run.is_empty():
		return
	_check(run["d"] == Vector2i(1, 0), "kus vystupku nema vodorovny smer (%s)" % str(run["d"]))
	_check(run["s"] == Vector2i(0, -1), "vystupek nemiri nahoru (%s)" % str(run["s"]))
	# 1b) DRUHY KONEC VRSEKU je ROH (vstup i vystup se lisi) - i tam se kus
	# musi najit, jinak by prst na pulce vrsku nic nedelal
	var run2: Dictionary = lv.run_at(0, Vector2i(5, 4))
	_check(not run2.is_empty(), "na druhem konci vrsku se vystupek nenajde")
	if not run2.is_empty():
		_check(int(run2["a"]) == int(run["a"]) and int(run2["b"]) == int(run["b"]),
			"druhy konec vrsku vraci jiny kus (%d..%d vs %d..%d)" % [
				int(run2["a"]), int(run2["b"]), int(run["a"]), int(run["b"])])
	# 2) POSUN NAHORU: cely vrsek se posune, obe bocni strany se prodlouzi o bunku
	_check(lv.shift_run(0, Vector2i(4, 4), true), "vystupek se neda posunout nahoru")
	var up: Array = lv.lane_cells(0)
	_check(up.size() == before.size() + 2,
		"posun vystupku nepridal dve bunky (%d -> %d)" % [before.size(), up.size()])
	for want in [Vector2i(4, 5), Vector2i(4, 4), Vector2i(4, 3), Vector2i(5, 3),
			Vector2i(5, 4), Vector2i(5, 5)]:
		_check(up.has(want), "vystupek po posunu nema bunku %s: %s" % [str(want), str(up)])
	_check(lv.validate().size() == 0, "posun vystupku rozbil mapu: %s" % str(lv.validate()))
	# 3) DRUHY KROK: strany maji tri bunky (krok se nikdy nepreskoci)
	_check(lv.shift_run(0, Vector2i(4, 3), true), "vystupek se neda posunout podruhe")
	var up2: Array = lv.lane_cells(0)
	_check(up2.size() == before.size() + 4,
		"druhy posun nepridal dve bunky (%d -> %d)" % [before.size(), up2.size()])
	_check(up2.has(Vector2i(4, 2)) and up2.has(Vector2i(5, 2)),
		"vrsek neni o dve bunky vys: " + str(up2))
	# 4) ZPET DOLU: presne puvodni cesta (krok za krokem)
	_check(lv.shift_run(0, Vector2i(4, 2), false), "vystupek se neda posunout zpet")
	_check(lv.shift_run(0, Vector2i(4, 3), false), "vystupek se neda posunout zpet podruhe")
	var back: Array = lv.lane_cells(0)
	_check(back.size() == before.size(),
		"návrat nedal puvodni delku (%d vs %d)" % [back.size(), before.size()])
	for i in range(mini(back.size(), before.size())):
		_check(back[i] == before[i], "návrat nedal puvodni cestu (bunka %d: %s vs %s)" % [
			i, str(back[i]), str(before[i])])
	_check(lv.validate().size() == 0, "návrat rozbil mapu: %s" % str(lv.validate()))
	# 5) ROVNY KUS NA KONCI CESTY SE TAKTO NEPOSOUVA - tam hybe uzlem
	_check(lv.run_at(0, Vector2i(6, 5)).is_empty(),
		"rovny kus u cile se tvari jako vystupek")
	_check(not lv.shift_run(0, Vector2i(6, 5), true), "posun kusu u cile prosel")
	_check(lv.run_at(0, Vector2i(4, 5)).is_empty(), "roh cesty se tvari jako vystupek")
	# 6) PREKAZKA: kam se kus posouva, stoji prvek - posun se odmitne
	var lv2 := Level.new()
	var s2: int = lv2.add_node(2, 5, Level.START)
	var c2: int = lv2.add_node(7, 5, Level.CIL)
	lv2.add_lane(s2, c2, "RRURDRR", Element.FIRE)
	lv2.add_node(4, 3, Level.VYHYBKA)
	_check(not lv2.shift_run(0, Vector2i(4, 4), true), "posun vystupku prosel pres prvek")
	_check(lv2.lane_cells(0).size() == 8, "odmitnuty posun presto cestu zmenil")
	# 7) MIMO VYBER: neexistujici usek se neupravi
	_check(not lv.shift_run(-1, Vector2i(4, 4), true), "posun neexistujiciho useku prosel")
	_check(not lv.shift_run(lv.lane_count(), Vector2i(4, 4), true), "posun useku za koncem prosel")
	# 8) VYSTUPEK HNED U UZLU: posun se dela z bunky uzlu, uzel zustava
	var lv3 := Level.new()
	var s3: int = lv3.add_node(2, 5, Level.START)
	var c3: int = lv3.add_node(5, 5, Level.CIL)
	lv3.add_lane(s3, c3, "URDRR", Element.FIRE)
	_check(lv3.lane_cells(0)[0] == Vector2i(2, 5), "testovaci cesta nezacina v uzlu")
	_check(not lv3.run_at(0, Vector2i(2, 4)).is_empty(),
		"vystupek hned u uzlu se nenasel")
	_check(lv3.shift_run(0, Vector2i(2, 4), true), "vystupek u uzlu se neda posunout")
	var cs3: Array = lv3.lane_cells(0)
	_check(cs3[0] == Vector2i(2, 5), "posun utrhl cestu z uzlu: " + str(cs3))
	_check(cs3.has(Vector2i(2, 3)) and cs3.has(Vector2i(3, 3)),
		"vystupek u uzlu neni o bunku vys: " + str(cs3))
	_check(lv3.validate().size() == 0, "posun vystupku u uzlu rozbil mapu: %s" % str(lv3.validate()))
	# 9) JINY SMER: vystupek DOLU (dolina) se posouva stejne - smer se bere
	# z tvaru, ne z toho, ze to je "nahoru"
	var lv4 := Level.new()
	var s4: int = lv4.add_node(2, 5, Level.START)
	var c4: int = lv4.add_node(7, 5, Level.CIL)
	lv4.add_lane(s4, c4, "RRDRURR", Element.FIRE)
	var r4: Dictionary = lv4.run_at(0, Vector2i(4, 6))
	_check(not r4.is_empty(), "dolina se nenasla jako rovny kus")
	if not r4.is_empty():
		_check(r4["s"] == Vector2i(0, 1), "dolina nemiri dolu (%s)" % str(r4["s"]))
		_check(lv4.shift_run(0, Vector2i(4, 6), true), "dolina se neda posunout dolu")
		var d4: Array = lv4.lane_cells(0)
		_check(d4.size() == 10, "posun dolu nepridal dve bunky (%d)" % d4.size())
		_check(d4.has(Vector2i(4, 7)) and d4.has(Vector2i(5, 7)),
			"dolina neni o bunku niz: " + str(d4))
		_check(lv4.validate().size() == 0, "posun dolu rozbil mapu")
	# 10) JINY SMER: SVISLY kus se posouva DO STRANY
	var lv5 := Level.new()
	var s5: int = lv5.add_node(5, 2, Level.START)
	var c5: int = lv5.add_node(5, 8, Level.CIL)
	lv5.add_lane(s5, c5, "DDRDDLDD", Element.FIRE)
	var r5: Dictionary = lv5.run_at(0, Vector2i(6, 4))
	_check(not r5.is_empty(), "svistly kus se nenasel jako vystupek")
	if not r5.is_empty():
		_check(r5["d"] == Vector2i(0, 1), "svistly kus nema svistly smer (%s)" % str(r5["d"]))
		_check(r5["s"] == Vector2i(1, 0), "svistly vystupek nemiri do strany (%s)" % str(r5["s"]))
		_check(lv5.shift_run(0, Vector2i(6, 4), true), "svistly kus se neda posunout do strany")
		var d5: Array = lv5.lane_cells(0)
		_check(d5.size() == 11, "posun do strany nepridal dve bunky (%d)" % d5.size())
		_check(d5.has(Vector2i(7, 4)) and d5.has(Vector2i(7, 6)),
			"svistly vystupek neni o bunku vpravo: " + str(d5))
		_check(lv5.validate().size() == 0, "posun do strany rozbil mapu")
	# 11) ZMENŠOVÁNÍ: z kazdeho tvaru se da jit zpatky - a u nejmensiho
	# vystupku (strany po jedne bunce) se posun dovnitr ZPLOSTI cestu
	var lv6 := Level.new()
	var s6: int = lv6.add_node(2, 5, Level.START)
	var c6: int = lv6.add_node(7, 5, Level.CIL)
	lv6.add_lane(s6, c6, "RRURDRR", Element.FIRE)
	_check(lv6.shift_run(0, Vector2i(4, 4), false), "vystupek se neda zplostit")
	var fl: Array = lv6.lane_cells(0)
	_check(fl.size() == 6, "zplosteni nedalo rovnou cestu (%d): %s" % [fl.size(), str(fl)])
	_check(not fl.has(Vector2i(4, 4)) and not fl.has(Vector2i(5, 4)),
		"po zplosteni zustal vystupek v ceste: " + str(fl))
	_check(lv6.validate().size() == 0, "zplosteni rozbilo mapu: %s" % str(lv6.validate()))
	_check(not lv6.shift_run(0, Vector2i(4, 5), false),
		"zplostena cesta se dala zmensovat dal")
	# 12) ROZŠÍŘENÍ VRŠKU (tah PODEL kusu): vrsek se prodlouzi na tu stranu, kam
	# prst taha, roh se s nim posune a vyska vystupku zustava
	var lv7 := Level.new()
	var s7: int = lv7.add_node(2, 5, Level.START)
	var c7: int = lv7.add_node(7, 5, Level.CIL)
	lv7.add_lane(s7, c7, "RRURDRR", Element.FIRE)
	var b0: Array = lv7.lane_cells(0).duplicate()
	_check(lv7.widen_run(0, Vector2i(4, 4), 1, true), "vrsek se neda rozsirit doprava")
	var w1: Array = lv7.lane_cells(0)
	_check(w1.size() == b0.size(),
		"rozsireni vrsku zmenilo pocet bunek (%d vs %d)" % [w1.size(), b0.size()])
	_check(w1.has(Vector2i(6, 4)) and not w1.has(Vector2i(5, 5)),
		"vrsek se nerozsiril doprava: " + str(w1))
	_check(lv7.validate().size() == 0, "rozsireni vrsku rozbilo mapu: %s" % str(lv7.validate()))
	_check(lv7.widen_run(0, Vector2i(4, 4), 1, false), "vrsek se neda zuzit zpet")
	var w2: Array = lv7.lane_cells(0)
	_check(w2.size() == b0.size(), "zuz... zmenilo pocet bunek (%d)" % w2.size())
	for i in range(mini(w2.size(), b0.size())):
		_check(w2[i] == b0[i], "zuz... nedalo puvodni cestu (bunka %d: %s vs %s)" % [
			i, str(w2[i]), str(b0[i])])
	_check(lv7.widen_run(0, Vector2i(4, 4), -1, true), "vrsek se neda rozsirit doleva")
	var w3: Array = lv7.lane_cells(0)
	_check(w3.has(Vector2i(3, 4)) and not w3.has(Vector2i(4, 5)),
		"vrsek se nerozsiril doleva: " + str(w3))
	_check(lv7.validate().size() == 0, "rozsireni vrsku doleva rozbilo mapu")
	# 13) NEJMENSI VRSEK (dve bunky) SE NEDA ZUZIT - zbyl by jednobunkovy kus,
	# ktery uz vystupek neni
	var lv8 := Level.new()
	var s8: int = lv8.add_node(2, 5, Level.START)
	var c8: int = lv8.add_node(7, 5, Level.CIL)
	lv8.add_lane(s8, c8, "RRURDRR", Element.FIRE)
	_check(not lv8.widen_run(0, Vector2i(4, 4), 1, false), "nejmensi vrsek se dal zuzit")
	_check(not lv8.widen_run(0, Vector2i(4, 4), -1, false), "nejmensi vrsek se dal zuzit zleva")
	_check(lv8.lane_cells(0).size() == 8, "odmitnute zuz... presto cestu zmenilo")
	# 14) KDYBY CESTA ZA VRSKEM HNET ZATOCILA, rozsireni se odmitne (roh nema kam
	# posunout); doleva to jde, tam cesta rovne pokracuje
	var lv9 := Level.new()
	var s9: int = lv9.add_node(2, 5, Level.START)
	var c9: int = lv9.add_node(5, 7, Level.CIL)
	lv9.add_lane(s9, c9, "RRURDDD", Element.FIRE)
	_check(not lv9.run_at(0, Vector2i(4, 4)).is_empty(), "vystupek pred zatocenim se nenasel")
	_check(not lv9.widen_run(0, Vector2i(4, 4), 1, true), "rozsireni pres zatoceni proslo")
	_check(lv9.lane_cells(0).size() == 8, "odmitnute rozsireni presto cestu zmenilo")
	_check(lv9.widen_run(0, Vector2i(4, 4), -1, true), "rozsireni doleva se odmitlo")


func _test_code_round_trip() -> void:
	var lv := Level.base()
	var code: String = lv.to_code()
	_check(code.begins_with("ZILY2;"), "kod levelu nezacina ZILY2;")
	_check(not code.contains("\n"), "kod levelu ma byt na jedne radce")
	_check(code.length() < 900, "kod levelu je dlouhy %d znaku (ma se vejit do zpravy)"
		% code.length())
	var back := Level.from_code(code)
	_check(back != null, "kod levelu se neda nacist zpatky")
	if back != null:
		_check(back.to_code() == code, "kod levelu se po nacteni zmenil")
		_check(back.lane_count() == lv.lane_count(), "po nacteni je jiný pocet useku")
		_check(back.node_count() == lv.node_count(), "po nacteni je jiný pocet uzlu")
		_check(back.spawn_elements() == lv.spawn_elements(), "po nacteni se zmenily zivly")
		_check(back.validate().is_empty(), "nacteny level neprojde kontrolou")


# ---------------------------------------------------------------- mista na useku

# POCET MIST NA BONUS JE DATA, NE KONSTANTA. Jan: "Nekde jen 1, nekde 3,
# nekde i vice a nekde uplne bez bonusu." Testuje se to, co se neda poznat
# okem: ze se pocet odnese v kodu levelu, ze nula je platna a ze rucne
# vymysleny kod se stropem odmitne.
func _test_lane_slots() -> void:
	var lv := Level.base()
	for i in range(lv.lane_count()):
		_check(lv.lane_slot_count(i) == Level.SLOTS,
			"usek %d nema vychozi pocet mist (%d)" % [i, lv.lane_slot_count(i)])
	# ZAKLADNI DESKA SE NESMI ROZSIRIT: kod se pise po radcich a ctvrtý
	# prvek (pocet mist) se pridava JEN kdyz se lisi od vychoziho. Kdyby se
	# psal vzdy, zmenil by se kazdy ulozeny kod levelu.
	var d0: Dictionary = lv.to_dict()
	for row in d0["e"]:
		var a: Array = row
		_check(a.size() == 3, "kod zakladni desky se rozsiril o pocet mist")

	lv.set_lane_slots(0, 0)
	lv.set_lane_slots(1, 5)
	_check(lv.lane_slot_count(0) == 0, "usek bez bonusu se neulozil")
	_check(lv.lane_slot_count(1) == 5, "pet mist se neulozilo")
	_check(lv.lane_slot_count(2) == Level.SLOTS, "sousednim usekum se pocet mist zmenil")
	lv.set_lane_slots(3, 99)
	_check(lv.lane_slot_count(3) == Level.MAX_SLOTS, "pocet mist se nezastavil na stropu")
	_check(lv.validate().is_empty(), "mapa s jinym poctem mist neprojde: " + str(lv.validate()))

	var code: String = lv.to_code()
	_check(code.length() < 900, "kod s poctem mist je dlouhy %d znaku" % code.length())
	var back := Level.from_code(code)
	_check(back != null, "kod s jinym poctem mist se neda nacist zpatky")
	if back != null:
		_check(back.to_code() == code, "kod s poctem mist se po nacteni zmenil")
		_check(back.lane_slot_count(0) == 0, "po nacteni nema usek 0 nula mist")
		_check(back.lane_slot_count(1) == 5, "po nacteni nema usek 1 pet mist")
		_check(back.lane_slot_count(2) == Level.SLOTS, "po nacteni se zmenil vychozi pocet")

	# STROP: rucne vymysleny kod s devíti misty se pri nacteni ZASTAVI na
	# stropu a primo v datech (bez nacteni) ho odmitne kontrola mapy.
	var d: Dictionary = lv.to_dict()
	var rows: Array = d["e"]
	var bad_row: Array = rows[2]
	bad_row.append(9)
	rows[2] = bad_row
	d["e"] = rows
	var capped := Level.from_code("ZILY2;" + JSON.stringify(d))
	_check(capped != null, "kod s poctem nad stropem se neda vubec nacist")
	if capped != null:
		_check(capped.lane_slot_count(2) == Level.MAX_SLOTS,
			"pocet mist nad stropem se nezastavil (je %d)" % capped.lane_slot_count(2))
	var raw := Level.base()
	raw.lanes[0]["slots"] = 9
	_check(not raw.validate().is_empty(), "kontrola mapy prosla s devíti misty")


# ---------------------------------------------------------------- co ma spravne odmítnout
func _test_rejects() -> void:
	# dva starty
	var lv := Level.base()
	lv.nodes.append({"c": 2, "r": 8, "kind": Level.START})
	_check(not lv.validate().is_empty(), "dva starty prosly kontrolou")

	# cil, do ktereho nic nevede
	lv = Level.base()
	lv.nodes.append({"c": 17, "r": 0, "kind": Level.CIL})
	_check(not lv.validate().is_empty(), "osirely cil prosel kontrolou")

	# usek, ze ktereho se neda dojit k cili (slepá ulička)
	lv = Level.base()
	var dead_end := lv.add_node(15, 0, Level.UZEL)
	lv.add_lane(5, dead_end, "R R R R R R R R R U U U U U", Element.EARTH)
	_check(not lv.validate().is_empty(), "slepa ulicka prosla kontrolou")

	# usek sikmo
	lv = Level.base()
	lv.lanes[1]["cells"] = [Vector2i(4, 5), Vector2i(5, 4), Vector2i(15, 1)]
	_check(not lv.validate().is_empty(), "sikma cesta prosla kontrolou")

	# vyhybka, ze ktere vede jen jedna cesta (neni to vyhybka)
	lv = Level.base()
	lv.lanes.remove_at(2)
	_check(not lv.validate().is_empty(), "vyhybka s jedinym vystupem prosla kontrolou")

	# kod se neda nacist, kdyz je rozbity
	var bad := Level.from_code("ZILY2;{\"u\":[],\"e\":[]}")
	_check(bad == null, "rozbity kod se nacist povedlo")


# ---------------------------------------------------------------- Janova mapa

# Mapa z nakresu: start vlevo, dve vyhybky v sérii, dve U-trasy (ohen,
# voda), ktere se VRACEJI ZPET a sliji se ve spojce se treti (neutralni)
# cestou, ktera sla z vyhybek rovnou. Presne tenhle tvar stary model
# neumel vubec - proto se testuje.
func _test_jan_map_shape() -> void:
	var lv := Level.new()
	lv.name = "janova"
	var start := lv.add_node(1, 5, Level.START)
	var j_up := lv.add_node(4, 5, Level.VYHYBKA)
	var j_dn := lv.add_node(7, 5, Level.VYHYBKA)
	var mer := lv.add_node(11, 5, Level.SPOJKA)
	var cil := lv.add_node(17, 5, Level.CIL)
	lv.add_lane(start, j_up, "R R R", Level.NEUTRAL)
	# U-trasa ohen: nahoru, doprava, dolu do spojky
	lv.add_lane(j_up, mer, "U U U U R R R R R R R D D D D", Element.FIRE)
	# neutralne dal na druhou vyhybku
	lv.add_lane(j_up, j_dn, "R R R", Level.NEUTRAL)
	# U-trasa voda: dolu, doprava, nahoru do spojky
	lv.add_lane(j_dn, mer, "D D D D R R R R U U U U", Element.WATER)
	# neutralni cesta z druhe vyhybky do te same spojky
	lv.add_lane(j_dn, mer, "R R R R", Level.NEUTRAL)
	lv.add_lane(mer, cil, "R R R R R R", Level.NEUTRAL)

	var errs: Array = lv.validate()
	_check(errs.is_empty(), "mapa z nakresu neprojde: " + str(errs))
	_check(lv.node_kind(mer) == Level.SPOJKA, "spojka neni spojka")
	# do spojky se vleji VSECHNY TRI cesty - to je jadro nakresu
	var ins: Array = lv.lanes_into(mer)
	_check(ins.size() == 3, "do spojky maji vest tri useky, vedou %d" % ins.size())
	_check(lv.lanes_from(mer).size() == 1, "ze spojky nevede prave jeden usek")
	# dve vyhybky v sérii, kazda se dvema vystupy
	_check(lv.node_choice_count(j_up) == 2, "prvni vyhybka nema 2 vystupy")
	_check(lv.node_choice_count(j_dn) == 2, "druha vyhybka nema 2 vystupy")
	# MAPA Z NAKRESU POSILA JEN TO, CO MA PROTIKLAD: ma v sobe ohen, vodu
	# a neutralni cesty - a posilaji se prave Ohen a Voda, protoze ty maji
	# svuj protiklad. (Neutralni cesta je zbran na kohokoli, ale zivly z ni
	# nechodi - Jan: "spawnovat se budou jen ty, co mají protiklad.")
	_check(lv.has_neutral_lane(), "v mape z nakresu neni neutralni cesta")
	_check(lv.spawn_elements() == [Element.FIRE, Element.WATER],
		"mapa z nakresu ma posilat ohen a vodu, posila %s" % str(lv.spawn_elements()))
	_check(lv.unkillable_elements().is_empty(),
		"mapa z nakresu hlasi nezabitelny zivel: " + str(lv.unkillable_elements()))
	# a vsechno se to vejde do kodu, ktery se da vlozit do zpravy
	var code: String = lv.to_code()
	_check(Level.from_code(code) != null, "kod teto mapy se neda nacist zpatky")


# VIC VSTUPU JE PLATNA MAPA. Jan: "chyba: mapa musi mit prave jeden start
# (ma 2). To je blbost. Muze mit libovolny pocet startu/vstupu."
#
# Dva starty = dva nezavisle vstupy do mapy. Hra z nich losuje
# (`Network.entry_lanes`) a kazdy z nich je vstupni usek (kmen). Driv tuhle
# mapu `validate()` odmitl, takze se nedala vyexportovat - a `from_code` by
# ji vratil jako null.
func _test_multi_start() -> void:
	var lv := Level.new()
	var s1 := lv.add_node(1, 2, Level.START)
	var s2 := lv.add_node(1, 8, Level.START)
	var j := lv.add_node(8, 5, Level.SPOJKA)
	var cil := lv.add_node(14, 5, Level.CIL)
	lv.add_lane(s1, j, "R R R R R R R D D D", Level.NEUTRAL)
	lv.add_lane(s2, j, "R R R R R R R U U U", Level.NEUTRAL)
	lv.add_lane(j, cil, "R R R R R R", Element.FIRE)
	var errs: Array = lv.validate()
	_check(errs.is_empty(), "mapa se dvema starty neprojde: " + str(errs))
	_check(lv.start_nodes().size() == 2,
		"start_nodes vraci %d startu" % lv.start_nodes().size())
	# KAZDY usek ze startu je vstupni - ne jen ten z prvniho.
	var net := Network.new()
	net.build(Rect2(0, 0, 960, 600), 1.0, 600.0, lv)
	_check(net.entry_lanes.size() == 2,
		"sit nema dva vstupni useky (%d)" % net.entry_lanes.size())
	for item in net.entry_lanes:
		_check(net.lane_is_entry(int(item)), "usek %d ze startu neni vstupni" % int(item))
	# kod si oba starty odnese a nacte se zpatky
	var code: String = lv.to_code()
	var back := Level.from_code(code)
	_check(back != null, "kod se dvema starty se neda nacist")
	if back != null:
		_check(back.start_nodes().size() == 2,
			"po nacteni ma mapa %d startu" % back.start_nodes().size())
	# a bez startu mapa neplati (to jedine pravidlo zustava)
	var empty := Level.new()
	_check(not empty.validate().is_empty(), "mapa bez startu projde validaci")


# ---------------------------------------------------------------- diamant

# Rozdel -> dve paralelni trasy -> spoj. Presne to, co stary stromovy
# model neumel: usek, do ktereho se vleji dve cesty.
func _test_diamond_survives() -> void:
	var lv := Level.new()
	var start := lv.add_node(1, 5, Level.START)
	var j := lv.add_node(4, 5, Level.VYHYBKA)
	var m := lv.add_node(12, 5, Level.SPOJKA)
	var cil := lv.add_node(16, 5, Level.CIL)
	lv.add_lane(start, j, "R R R", Level.NEUTRAL)
	lv.add_lane(j, m, "U U U U R R R R R R R R D D D D", Element.FIRE)
	lv.add_lane(j, m, "D D D D R R R R R R R R U U U U", Element.WATER)
	lv.add_lane(m, cil, "R R R R", Level.NEUTRAL)
	var errs: Array = lv.validate()
	_check(errs.is_empty(), "diamant neprojde: " + str(errs))
	_check(lv.lanes_into(m).size() == 2, "do spojky nevedou dva useky")
	_check(lv.lanes_from(m).size() == 1, "ze spojky nevede prave jeden usek")
	# rozdel a zase spoj: obe paralelni trasy Konci ve stejnem uzlu
	_check(lv.lane_end_node(lv.lanes_into(m)[0]) == m, "prvni usek nekonci ve spojce")
	_check(lv.lane_end_node(lv.lanes_into(m)[1]) == m, "druhy usek nekonci ve spojce")


# POSUN CELE ROVNE CARY MEZI DVEMA UZLY. Jan (Oct 2026): "Posouvání celých
# úseku teď funguje maximálně o 2 pozice. Bylo by fajn, kdyby s tím šlo hýbat
# neomezeně. A rozšiřování do boků stále rozšiřuje jen kousek celé čáry místo
# celku."
#
# Kus, ktery konci v UZLU, se posouva I S TIM UZLEM - takze se hýbe celou
# rovnou carou (ne jen vyboulenim v ni) a tolik bunek, kolik jich hrac ujede.
# Presne to je "neomezene": kazda poloha prstu je jeden krok, zadny strop
# krome okraje mapy.
func _test_move_piece() -> void:
	var lv := Level.new()
	var s: int = lv.add_node(2, 8, Level.START)
	var c: int = lv.add_node(12, 8, Level.CIL)
	lv.add_lane(s, c, "RRRRRRRRRR", Element.FIRE)
	_check(lv.lane_cells(0).size() == 11, "testovaci cara nema 11 bunek")
	# 1) KUS POD PRSTEM JE CELA CARA (a konci v obou uzlech)
	var pc: Dictionary = lv.piece_at(0, Vector2i(7, 8), Vector2i(1, 0))
	_check(not pc.is_empty(), "na rovne care se nenasel zadny kus")
	if pc.is_empty():
		return
	_check(int(pc["a"]) == 0 and int(pc["b"]) == 10,
		"kus na rovne care nemiri od uzlu k uzlu (%d..%d)" % [int(pc["a"]), int(pc["b"])])
	# 2) PET KROKU DOLU: cara zustane rovna, oba uzly jdou s ni
	var cur: Vector2i = Vector2i(7, 8)
	for step in range(5):
		var res: Dictionary = lv.move_piece(0, cur, Vector2i(0, 1), Vector2i(1, 0))
		_check(bool(res["ok"]), "posun cele cary selhal v kroku %d" % (step + 1))
		if not bool(res["ok"]):
			return
		_check(res["nodes"].size() == 2,
			"posun cary neposunul oba uzly (%d)" % res["nodes"].size())
		lv.lanes[0]["cells"] = res["cells"]
		for item in res["nodes"]:
			lv.nodes[int(item["i"])]["c"] = item["to"].x
			lv.nodes[int(item["i"])]["r"] = item["to"].y
		cur += Vector2i(0, 1)
	var cs: Array = lv.lane_cells(0)
	_check(cs.size() == 11, "posun cary zmenil pocet bunek (%d)" % cs.size())
	for i in range(cs.size()):
		_check(cs[i] == Vector2i(2 + i, 13),
			"cara neni rovna po posunu (bunka %d: %s)" % [i, str(cs[i])])
	_check(lv.node_cell(s) == Vector2i(2, 13) and lv.node_cell(c) == Vector2i(12, 13),
		"uzly nejdou s carou (%s, %s)" % [str(lv.node_cell(s)), str(lv.node_cell(c))])
	_check(lv.validate().is_empty(), "po posunu cary je mapa rozbita: " + str(lv.validate()))
	# 3) KROK ZPET: cara se vrati presne na puvodni radek
	var res2: Dictionary = lv.move_piece(0, Vector2i(7, 13), Vector2i(0, -1), Vector2i(1, 0))
	_check(bool(res2["ok"]), "posun cary zpet selhal")
	if bool(res2["ok"]):
		lv.lanes[0]["cells"] = res2["cells"]
		for item2 in res2["nodes"]:
			lv.nodes[int(item2["i"])]["c"] = item2["to"].x
			lv.nodes[int(item2["i"])]["r"] = item2["to"].y
		_check(lv.lane_cells(0)[0] == Vector2i(2, 12), "krok zpet neposunul caru o bunku")
	# 4) KUS S UZLEM JEN NA JEDNOM KONCI: druhy konec je roh - strana se
	#    prodlouzi, uzel jde s prstem
	var lv2 := Level.new()
	var s2: int = lv2.add_node(2, 8, Level.START)
	var c2: int = lv2.add_node(8, 5, Level.CIL)
	lv2.add_lane(s2, c2, "RRRRRRUUU", Element.FIRE)
	var pc2: Dictionary = lv2.piece_at(0, Vector2i(4, 8), Vector2i(1, 0))
	_check(not pc2.is_empty(), "na care u startu se nenasel kus")
	if pc2.is_empty():
		return
	_check(int(pc2["a"]) == 0 and int(pc2["b"]) < lv2.lane_cells(0).size() - 1,
		"kus u startu nema uzel jen na jednom konci (%d..%d)" % [
			int(pc2["a"]), int(pc2["b"])])
	var res3: Dictionary = lv2.move_piece(0, Vector2i(4, 8), Vector2i(0, -1), Vector2i(1, 0))
	_check(bool(res3["ok"]), "posun kusu s uzlem na jednom konci selhal")
	if bool(res3["ok"]):
		_check(res3["nodes"].size() == 1, "posunl se vic uzlu, nez ma kus na konci")
		for item3 in res3["nodes"]:
			lv2.nodes[int(item3["i"])]["c"] = item3["to"].x
			lv2.nodes[int(item3["i"])]["r"] = item3["to"].y
		lv2.lanes[0]["cells"] = res3["cells"]
		_check(lv2.node_cell(s2) == Vector2i(2, 7), "uzel na konci kusu se neposunul")
		_check(lv2.lane_cells(0).has(Vector2i(4, 7)),
			"kus se neposunul nahoru: " + str(lv2.lane_cells(0)))
		_check(lv2.validate().is_empty(), "posun kusu s uzlem rozbil mapu: " + str(lv2.validate()))
