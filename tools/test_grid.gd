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
	_run("kod levelu", _test_code_round_trip)
	_run("mista na useku", _test_lane_slots)
	_run("odmitnuti", _test_rejects)
	_run("mapa z nakresu", _test_jan_map_shape)
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


func _check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails.append(msg)


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
			_check(lv.lane_is_kmen(i) and not lv.lane_deals_damage(i),
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
	# volba 0 = ohen, 1 = dal po rade 5, 2 = voda
	var c0: int = lv.node_choice(j1, 0)
	var c1: int = lv.node_choice(j1, 1)
	var c2: int = lv.node_choice(j1, 2)
	_check(lv.lane_element(c0) == Element.FIRE, "volba 0 neni ohen")
	_check(lv.lane_element(c1) == Level.NEUTRAL, "volba 1 neni neutralni")
	_check(lv.lane_element(c2) == Element.WATER, "volba 2 neni voda")
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


# ---------------------------------------------------------------- kod levelu

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
	# mapa posila ohen i vodu
	_check(lv.spawn_elements() == [0, 1], "mapa ma posilat ohen a vodu, posila %s"
		% str(lv.spawn_elements()))
	# a vsechno se to vejde do kodu, ktery se da vlozit do zpravy
	var code: String = lv.to_code()
	_check(Level.from_code(code) != null, "kod teto mapy se neda nacist zpatky")


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
