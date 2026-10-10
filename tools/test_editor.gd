extends SceneTree

# TEST EDITORU. Editor je jedina cesta, jak si Jan muze vyrobit level sam -
# takze se testuje to, co na nem muze potichu prestast fungovat:
#   * kazde tlacitko opravdu zmeni level (a jen to, co ma)
#   * level se da ulozit a znovu nacist (a je stejny)
#   * z upraveneho levelu se da hrat
#   * vyber useku klepnutim sedi na to, co je videt
#
# Vystup: EDITOR_ALL_PASS=true / false

var fails: Array = []
var checks: int = 0


func _init() -> void:
	_test_buttons_change_level()
	_test_element_cycle()
	_test_exit_cycle()
	_test_bend()
	_test_limits()
	_test_many_entries_and_junctions()
	_test_exits_are_manual_only()
	_test_exit_goes_with_its_last_lane()
	_test_join_divides_target()
	_test_join_two_lanes()
	_test_autosave()
	_test_export_code()
	_test_builtin_levels()
	_test_play_custom_level()
	_test_selector_matches_drawn_lanes()
	_test_status_text()
	_test_junction_split_merge()
	_test_junction_depth_limit()
	_test_level_list()
	_test_open_last()
	_test_entry_button()
	_test_target_joins_lane()
	_test_target_hint_tells_the_next_choice()
	_test_join_has_several_nodes()
	_test_deep_branch_joins_other_lanes()
	_test_exit_delete_button()
	_test_node_step_buttons()

	print("checks=%d fails=%d" % [checks, fails.size()])
	for f in fails:
		print("FAIL: " + str(f))
	if fails.is_empty():
		print("EDITOR_ALL_PASS=true")
	else:
		print("EDITOR_ALL_PASS=false")
	quit()


func _ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails.append(what)


func _fresh() -> Editor:
	var e := Editor.new()
	e.reset()
	return e


func _test_buttons_change_level() -> void:
	var ed := _fresh()
	var n0: int = ed.level.lane_count()
	ed.press(Editor.BTN_ADD)
	_ok(ed.level.lane_count() == n0 + 1, "tlacitko 'usek +' prida usek")
	_ok(ed.sel == ed.level.lane_count() - 1, "a hned ho vybere - hrac vidi, co pridal")
	ed.press(Editor.BTN_DEL)
	_ok(ed.level.lane_count() == n0, "tlacitko 'usek −' usek odebere")
	# KAZDE tlacitko musi neco zmenit. Kdyby nejake nedelalo nic, hrac by
	# mackal a nic by se nedelo - a nikdo by nepoznal, ktere to je.
	for b in [Editor.BTN_ELEMENT, Editor.BTN_TARGET, Editor.BTN_BEND_LEFT, Editor.BTN_BEND_RIGHT]:
		var e2 := _fresh()
		var before: String = e2.level.to_code()
		e2.press(b)
		_ok(e2.level.to_code() != before, "tlacitko %d opravdu neco zmeni" % b)
	# HRAT neni zmena levelu - je to prechod do hry. Editor na nej odpovi
	# cislem tlacitka, aby si hra mohla vsimnout, ze ma spustit kolo.
	var e3 := _fresh()
	_ok(e3.press(Editor.BTN_PLAY) == Editor.BTN_PLAY, "tlacitko HRAT se hra dozvi")
	_ok(e3.press(Editor.BTN_EXPORT) == Editor.BTN_EXPORT, "a tlacitko EXPORT taky")
	# i tlacitko noveho cile neco udela - prida cil (viz _test_exits_are_manual_only)


func _test_element_cycle() -> void:
	var ed := _fresh()
	ed.sel = 0
	var seen := {}
	for i in range(Element.COUNT + 1):
		seen[ed.level.el_of(0)] = true
		ed.press(Editor.BTN_ELEMENT)
	_ok(seen.size() == Element.COUNT + 1,
		"zivel se cykli pres vsechny ctyri a neutralni (%d)" % seen.size())
	_ok(seen.has(Level.NEUTRAL), "a neutralni je mezi nimi")
	_ok(seen.has(Element.FIRE) and seen.has(Element.WATER)
		and seen.has(Element.EARTH) and seen.has(Element.AIR), "a vsechny ctyri zivly")


func _test_exit_cycle() -> void:
	# CIL USEKU: vyhybka ho cykli pres vsechny vystupy (a u levelu s dalsi
	# vyhybkou i pres ni - tim se useky SPOJUJI). Na zakladni desce jsou jen
	# vystupy, takze se musi dat projit vsechny. Za vystupy cyklus pokracuje
	# dal (napojeni), proto se chodi jen po vystupove casti - jinak by se do
	# "videnych cilu" michaly i useky, ktere maji cisla ze stejne rady.
	var ed := _fresh()
	ed.sel = 0
	var seen := {}
	for i in range(ed.level.exits.size() + 2):
		if ed.level.target_kind(0) != Level.TO_EXIT:
			break
		seen[ed.level.to_of(0)] = true
		ed.press(Editor.BTN_TARGET)
	_ok(seen.size() == ed.level.exits.size(),
		"cíl se cykli pres vsechny vystupy (%d z %d)" % [seen.size(), ed.level.exits.size()])
	_ok(ed.level.target_kind(0) != Level.TO_EXIT,
		"a za vystupy cyklus pokracuje dal (%d)" % ed.level.target_kind(0))
	# a kazdy vystup musi byt porad v plose
	for i in range(ed.level.exits.size()):
		var p: Array = ed.level.exits[i]
		_ok(float(p[1]) > 0.0 and float(p[1]) < 1.0,
			"vystup %d zustava v plose (%.2f)" % [i, float(p[1])])


func _test_bend() -> void:
	var ed := _fresh()
	ed.sel = 0
	var v0: float = ed.level.divert_of(0)
	ed.press(Editor.BTN_BEND_RIGHT)
	_ok(ed.level.divert_of(0) > v0, "odbočení + ohne usek pozdeji")
	var v1: float = ed.level.divert_of(0)
	ed.press(Editor.BTN_BEND_LEFT)
	_ok(ed.level.divert_of(0) < v1, "odbočení − ohne usek driv")
	# usek musi porad zustat na svem rovnem useku - odboceni nesmi utect
	for i in range(40):
		ed.press(Editor.BTN_BEND_RIGHT)
	_ok(ed.level.divert_of(0) <= 0.98, "odbočení nejde pres celou plochu (%.2f)" % ed.level.divert_of(0))
	for i in range(80):
		ed.press(Editor.BTN_BEND_LEFT)
	_ok(ed.level.divert_of(0) >= 0.0, "a nejde ani pred zacatek (%.2f)" % ed.level.divert_of(0))


func _test_limits() -> void:
	var ed := _fresh()
	for i in range(Level.MAX_LANES + 3):
		ed.press(Editor.BTN_ADD)
	# STROP NENI POCET USEKU, ALE MISTO NA DESCE. Radky se sice zmensuji, ale
	# pod MIN_ROW_GAP uz ne - jinak by se bonusy na sousednich drahach
	# prekryvaly. Na zakladni desce se tak vejde deset drah.
	_ok(ed.level.rows_fit(), "mrizka zustava v rozestupu, kde se bonusy neprekryvaji (%.3f)" % ed.level.row_gap())
	_ok(ed.level.lane_count() >= 9,
		"na desku se vejde aspon 9 drah (%d)" % ed.level.lane_count())
	_ok(ed.level.lane_count() <= Level.MAX_LANES,
		"vic nez %d useku to nejde (%d)" % [Level.MAX_LANES, ed.level.lane_count()])
	# a pres strop se uz nic neprida
	var n: int = ed.level.lane_count()
	ed.press(Editor.BTN_ADD)
	_ok(ed.level.lane_count() == n, "a pres strop uz nic nepribyde (%d)" % ed.level.lane_count())
	_ok(not ed.status.is_empty(), "a hlaska rekne proc (%s)" % ed.status)
	# mrizka se musi vejit nad spodni okraj displeje
	_ok(ed.level.row_of(ed.level.lane_count() - 1) <= Level.BOTTOM,
		"i plna mrizka zustava nad spodnim okrajem (%.2f)" % ed.level.row_of(ed.level.lane_count() - 1))
	_ok(ed.level.validate().is_empty(), "plna mrizka je v poradku: %s" % str(ed.level.validate()))
	for i in range(Level.MAX_LANES + 3):
		ed.press(Editor.BTN_DEL)
	_ok(ed.level.lane_count() == Level.MIN_LANES,
		"pod %d useky to nejde (%d)" % [Level.MIN_LANES, ed.level.lane_count()])
	ed.press(Editor.BTN_DEL)
	_ok(ed.level.lane_count() == Level.MIN_LANES, "a dalsi uz nic neudela")


# VSTUPU A VYHYBEK MUSI JIT PRIDAT KOLIK SE VEJDE. Jan: "v editoru lze ted
# pridat jen 1 vstup, nebo jen 1 dalsi vyhybku." Driv to zastavil pocet useku
# (MAX_LANES = 7), ktery byl nizsi nez misto na desce - hrac tedy narazil na
# strop, ktery nema s hratelnosti nic spolecneho.
func _test_many_entries_and_junctions() -> void:
	# --- VSTUPY (kazdy vlastni kmen = dva nove radky) ---
	var ed := _fresh()
	for i in range(6):
		ed.sel = 0
		ed.press(Editor.BTN_ENTRY)
	_ok(ed.level.entries.size() >= 3,
		"vstupu jde pridat vic nez dva (%d)" % ed.level.entries.size())
	_ok(ed.level.junctions.size() == ed.level.entries.size(),
		"kazdy novy vstup ma vlastni vyhybku (%d kmenu, %d vyhybek)" % [
			ed.level.entries.size(), ed.level.junctions.size()])
	_ok(ed.level.rows_fit(), "a mrizka se porad vejde na desku (%d radku)" % ed.level.rows_total())
	_ok(ed.level.validate().is_empty(), "takovy level je platny: %s" % str(ed.level.validate()))
	# dalsi uz se nevejde - a hrac dostane hlasku, ne ticho
	var e: int = ed.level.entries.size()
	ed.sel = 0
	ed.press(Editor.BTN_ENTRY)
	_ok(ed.level.entries.size() == e, "pres strop uz vstup nepribyde (%d)" % ed.level.entries.size())
	_ok(ed.status.contains("nevejde") or ed.status.contains("nejde"),
		"a hlaska rekne proc (%s)" % ed.status)

	# --- VYHYBKY ---
	var ed2 := _fresh()
	var j0: int = ed2.level.junction_count()
	for i in range(6):
		var pick: int = -1
		for k in range(ed2.level.lane_count()):
			ed2.sel = k
			if ed2.can_split():
				pick = k
				break
		if pick < 0:
			break
		ed2.sel = pick
		ed2.press(Editor.BTN_JUNCTION)
	_ok(ed2.level.junction_count() >= j0 + 3,
		"vyhybek jde pridat vic nez jednu (%d -> %d)" % [j0, ed2.level.junction_count()])
	_ok(ed2.level.rows_fit(), "a mrizka se porad vejde na desku (%d radku)" % ed2.level.rows_total())
	_ok(ed2.level.validate().is_empty(), "a takovy level je platny: %s" % str(ed2.level.validate()))
	var n_net := Network.new()
	n_net.build(Rect2(40.0, 80.0, 880.0, 404.0), 1.0, 500.0, ed2.level)
	_ok(n_net.junction_count() == ed2.level.junction_count(),
		"sit postavi vsechny vyhybky (%d z %d)" % [n_net.junction_count(), ed2.level.junction_count()])


# CILE SE PRIDAVAJI JEN RUKOU. Jan: "pro kazdou novou cestu vzniká nový cíl.
# To není správné chování." Kdyby si cíl vyrobil nový úsek, nová výhybka i
# nový kmen samy, měl by hráč v mapě díry, které nezadal.
func _test_exits_are_manual_only() -> void:
	var ed := _fresh()
	var e0: int = ed.level.exits.size()
	ed.sel = 0
	ed.press(Editor.BTN_ADD)
	_ok(ed.level.exits.size() == e0,
		"nový úsek si cíl nevyrobí (%d -> %d)" % [e0, ed.level.exits.size()])
	var pick: int = -1
	for k in range(ed.level.lane_count()):
		ed.sel = k
		if ed.can_split():
			pick = k
			break
	_ok(pick >= 0, "na desce je co rozdělit")
	ed.sel = pick
	ed.press(Editor.BTN_JUNCTION)
	_ok(ed.level.exits.size() == e0,
		"ani výhybka si cíl nevyrobí (%d -> %d)" % [e0, ed.level.exits.size()])
	_ok(ed.level.validate().is_empty(), "a level je platný: %s" % str(ed.level.validate()))
	# Nove vetve musi vest do RUZNYCH cilu - dve cesty do stejne diry by
	# znamenaly, ze vyhybka nic nerozhoduje.
	var j: int = ed.level.junction_of(pick)
	var kids: Array = ed.level.lanes_of(j)
	_ok(kids.size() == 2, "z nové výhybky vedou dvě větve (%d)" % kids.size())
	if kids.size() == 2:
		_ok(ed.level.to_of(int(kids[0])) != ed.level.to_of(int(kids[1])),
			"a vedou do různých cílů (%d a %d)" % [
				ed.level.to_of(int(kids[0])), ed.level.to_of(int(kids[1]))])
	ed.sel = 0
	ed.press(Editor.BTN_ENTRY)
	_ok(ed.level.exits.size() == e0,
		"ani nový kmen si cíl nevyrobí (%d -> %d)" % [e0, ed.level.exits.size()])

	# --- RUKOU: tlacitko "cíl +" ---
	var ed2 := _fresh()
	ed2.sel = 2
	var c0: int = ed2.level.exits.size()
	ed2.press(Editor.BTN_EXIT)
	_ok(ed2.level.exits.size() == c0 + 1,
		"tlacitko 'cíl +' přidá cíl (%d -> %d)" % [c0, ed2.level.exits.size()])
	_ok(ed2.level.target_kind(2) == Level.TO_EXIT and ed2.level.to_of(2) == c0,
		"a vybraný úsek do něj ústí (míří na %d, čekáno %d)" % [ed2.level.to_of(2), c0])
	_ok(ed2.level.validate().is_empty(), "a level je pořád platný: %s" % str(ed2.level.validate()))
	var c1: int = ed2.level.exits.size()
	ed2.press(Editor.BTN_EXIT)
	_ok(ed2.level.exits.size() == c1 + 1, "a další stisk zase další (%d)" % ed2.level.exits.size())
	var back := Level.from_code(ed2.level.to_code())
	_ok(back.exits.size() == ed2.level.exits.size(),
		"a v kódu levelu jsou všechny cíle (%d)" % back.exits.size())
	_ok(back.to_code() == ed2.level.to_code(), "a kód se vrátí stejný")


# NAPOJENÍ ROZDĚLÍ CÍLOVOU CESTU NA DVA ÚSEKY. Jan: "Když se jedna cesta
# napojí na uzel druhé cesty, tak by se druhá cesta měla tímto napojením
# rozdělit na dva úseky. Nový vzniklý úsek by měl mít možnosti jako všechny
# ostatní. Změnit cíl, změnit element, atd."
func _test_join_divides_target() -> void:
	var ed := _fresh()
	ed.sel = 1
	var lanes0: int = ed.level.lane_count()
	for i in range(30):
		if ed.level.target_kind(1) == Level.TO_LANE:
			break
		ed.press(Editor.BTN_TARGET)
	_ok(ed.level.target_kind(1) == Level.TO_LANE, "úsek se dá napojit na jiný")
	if ed.level.target_kind(1) != Level.TO_LANE:
		return
	var lower: int = ed.level.to_of(1)            # nový (spodní) úsek je cíl napojení
	var j: int = ed.level.from_of(lower)          # a místo rozdělení, ze kterého vede
	_ok(ed.level.is_division(j),
		"napojení cílovou cestu ROZDĚLILO (místo rozdělení je výhybka %d)" % (j + 1))
	_ok(ed.level.lane_count() == lanes0 + 1,
		"a vznikl jeden nový úsek (%d -> %d)" % [lanes0, ed.level.lane_count()])
	if not ed.level.is_division(j):
		return
	var ins: Array = ed.level.lanes_into(j)       # horní část (ta, co se rozdělila)
	if ins.is_empty():
		_ok(false, "do místa rozdělení vede horní část")
		return
	var top: int = int(ins[0])
	var kids: Array = ed.level.lanes_of(j)
	_ok(kids.size() == 1, "z místa rozdělení vede jediná cesta dál (%d)" % kids.size())
	if kids.is_empty():
		return
	_ok(int(kids[0]) == lower, "a tou cestou je nový úsek (%d)" % lower)
	_ok(ed.level.el_of(lower) == ed.level.el_of(top),
		"nový úsek převezme element cesty - mapa tím nepřijde o žádný živel")
	# --- NOVÝ ÚSEK JE PLNOHODNOTNÝ: dá se mu změnit cíl i element ---
	ed.sel = lower
	var el_before: int = ed.level.el_of(lower)
	var to_before: int = ed.level.to_of(lower)
	ed.press(Editor.BTN_ELEMENT)
	_ok(ed.level.el_of(lower) != el_before,
		"novému úseku jde změnit element (%d -> %d)" % [el_before, ed.level.el_of(lower)])
	ed.press(Editor.BTN_TARGET)
	_ok(ed.level.to_of(lower) != to_before or ed.level.target_kind(lower) != Level.TO_EXIT,
		"a taky cíl (%d -> %d)" % [to_before, ed.level.to_of(lower)])
	_ok(ed.level.validate().is_empty(), "takový level je platný: %s" % str(ed.level.validate()))
	_ok(ed.level.target_kind(top) == Level.TO_JUNCTION,
		"horní část vede do místa rozdělení (kind=%d)" % ed.level.target_kind(top))
	# --- ELEMENT SPODNÍHO ÚSEKU SE POČÍTÁ ZVLÁŠŤ ---
	# Rozdělení má smysl jen proto, že každá část má svůj element: poškození se
	# počítá na TÉ části, na které poutník právě je.
	var g := Game.new()
	g.setup(Rect2(40.0, 80.0, 880.0, 404.0), 1.0, 500.0, ed.level)
	g.auto_wave = false
	g.set_switch(0)
	var e: Enemy = g.debug_spawn(Element.FIRE)
	var t := 0.0
	while t < 40.0 and e.alive and e.lane != lower:
		g.step(1.0 / 60.0)
		t += 1.0 / 60.0
	_ok(e.alive and e.lane == lower,
		"poutník projde rozdělením do spodního úseku (lane=%d, čekal %d)" % [e.lane, lower])
	# a kód levelu si rozdělení (i jeho souřadnici) odnese
	var code: String = ed.level.to_code()
	var back := Level.from_code(code)
	_ok(back.to_code() == code and back.lane_count() == ed.level.lane_count(),
		"kód levelu rozdělení udrží (%d znaků)" % code.length())
	_ok(back.validate().is_empty(), "a level z kódu je platný: %s" % str(back.validate()))


# SPOJENI DVOU CEST DO JEDNE. Usek se dá napojit na jiný usek - poutník po něm
# pokračuje dál, takže se z dvou cest stane jedna. Je to v cyklu tlacitka
# "cíl" (za výstupy), takže se k tomu hráč musí proklikat - a musí to jít.
func _test_join_two_lanes() -> void:
	var ed := _fresh()
	ed.sel = 1
	var joined: int = -1
	var taps := 0
	for i in range(40):
		ed.press(Editor.BTN_TARGET)
		taps += 1
		if ed.level.target_kind(1) == Level.TO_LANE:
			joined = ed.level.to_of(1)
			break
	_ok(joined >= 0, "úsek se dá napojit na jiný úsek (%d stisků)" % taps)
	if joined < 0:
		return
	_ok(ed.status.contains("napojuje se"),
		"a hlaska to rekne slovy, kterym hrac rozumi (%s)" % ed.status)
	_ok(ed.level.validate().is_empty(),
		"napojeny level je platny: %s" % str(ed.level.validate()))
	var n_net := Network.new()
	n_net.build(Rect2(40.0, 80.0, 880.0, 404.0), 1.0, 500.0, ed.level)
	_ok(int(n_net.lane_kind[1]) == Level.TO_LANE, "síť ví, že úsek končí napojením")
	# VSTUPNI BOD PATRI PRIVODNIMU USEKU (1), ne cilovemu: do jednoho useku se
	# muze vlit vic vetvi a kazda vstupuje v jinem uzlu.
	_ok(float(n_net.lane_entry_s[1]) > 0.0,
		"napojený úsek má vstup, kde se do cílového vlévá (%.0f px)" % n_net.lane_entry_s[1])
	# a kód levelu to unese - jinak by se hracuv level prenasel spatne
	var back := Level.from_code(ed.level.to_code())
	_ok(back.to_code() == ed.level.to_code(), "a kod levelu napojeni udrzi")


# CIL PO SMAZANE CESTE. Jan: "Jakmile smažu cestu a do jejího cíle už nic
# nevede, tak by se měl cíl automaticky smazat. Ale pouze při mazání cesty.
# Když vytvořím cíl ručně, tak může dočasně zůstat bez cesty."
func _test_exit_goes_with_its_last_lane() -> void:
	var ed := _fresh()
	# usek 5 (posledni na zakladni desce) usti do sveho cile sam
	var last: int = ed.level.lane_count() - 1
	var e: int = ed.level.exit_of(last)
	var uses := 0
	for i in range(ed.level.lane_count()):
		if ed.level.exit_of(i) == e:
			uses += 1
	_ok(uses == 1, "cil posledniho useku vede jen do nej (%d)" % uses)
	var e0: int = ed.level.exits.size()
	ed.sel = last
	ed.press(Editor.BTN_DEL)
	_ok(ed.level.exits.size() == e0 - 1,
		"po smazani cesty zmizel i osirely cil (%d -> %d)" % [e0, ed.level.exits.size()])
	_ok(ed.level.validate().is_empty(), "a level je platny: %s" % str(ed.level.validate()))
	# zadny usek nesmi ukazovat na cil, ktery uz neexistuje
	for i in range(ed.level.lane_count()):
		if ed.level.target_kind(i) == Level.TO_EXIT:
			_ok(ed.level.to_of(i) < ed.level.exits.size(),
				"usek %d miri na neexistujici cil (%d z %d)" % [
					i + 1, ed.level.to_of(i), ed.level.exits.size()])

	# --- RUCNE PRIDANY CIL BEZ CESTY ZUSTAVA ---
	var ed2 := _fresh()
	ed2.sel = 0
	ed2.press(Editor.BTN_EXIT)
	var manual: int = ed2.level.exits.size() - 1
	_ok(ed2.level.to_of(0) == manual, "novy cil si hrac pripojil sam (%d)" % manual)
	# prepojime usek 1 na JINY cil - ten rucne pridany zustane bez cesty
	for i in range(30):
		if ed2.level.target_kind(0) == Level.TO_EXIT and ed2.level.to_of(0) != manual:
			break
		ed2.press(Editor.BTN_TARGET)
	_ok(ed2.level.target_kind(0) == Level.TO_EXIT and ed2.level.to_of(0) != manual,
		"usek 1 se prepojil na jiny cil (%d)" % ed2.level.to_of(0))
	var c1: int = ed2.level.exits.size()
	# Smazeme usek 2 (cislo 0). Jeho cil pouziva i nekdo dalsi, takze zadny cil
	# zmizet nema - a ten rucne pridany teprve ne.
	ed2.sel = 0
	ed2.press(Editor.BTN_DEL)
	_ok(ed2.level.exits.size() == c1,
		"ručně přidaný cíl bez cesty zůstává (%d -> %d)" % [c1, ed2.level.exits.size()])
	_ok(ed2.level.validate().is_empty(), "a level je porad platny: %s" % str(ed2.level.validate()))

	# --- CISLA USEKU SE POSUNOU, ODKAZY SE MUSI POSUNOUT S NIMI ---
	# (jinak by se vetev vleva do jineho useku, nez hrac videl)
	var ed4 := _fresh()
	ed4.sel = 1
	for i in range(30):
		# Hledá se napojení, které ROZDĚLILO úsek 4 (index 3): napojený úsek
		# pak vede do nového spodního úseku, ne do něj samého.
		if ed4.level.target_kind(1) == Level.TO_LANE:
			var t: int = ed4.level.to_of(1)
			var jj: int = ed4.level.from_of(t)
			if ed4.level.is_division(jj) and ed4.level.lanes_into(jj).has(3):
				break
		ed4.press(Editor.BTN_TARGET)
	_ok(ed4.level.target_kind(1) == Level.TO_LANE,
		"usek 2 se napojil na jiny usek (kind=%d, to=%d)" % [
			ed4.level.target_kind(1), ed4.level.to_of(1)])
	# NAPOJENI ROZDĚLILO CÍLOVÝ ÚSEK (cislo 4 = index 3): napojeny usek vede
	# do NOVEHO spodniho useku, horni zustava na svem cisle.
	var joined: int = ed4.level.to_of(1)
	_ok(joined > 3, "napojeny usek vede do noveho useku (%d)" % joined)
	_ok(ed4.level.target_kind(3) == Level.TO_JUNCTION and ed4.level.is_division(ed4.level.to_of(3)),
		"a usek 4 se v tom miste rozdělil")
	# smazeme usek MEZI nimi (cislo 3 = index 2): obe cisla se posunou o jedna
	ed4.sel = 2
	ed4.press(Editor.BTN_DEL)
	_ok(ed4.level.lane_count() == 5, "usek 3 zmizel (%d)" % ed4.level.lane_count())
	_ok(ed4.level.target_kind(1) == Level.TO_LANE and ed4.level.to_of(1) == joined - 1,
		"odkaz na usek se posunul s cisly (cekal %d, je %d)" % [joined - 1, ed4.level.to_of(1)])
	_ok(ed4.level.validate().is_empty(), "a level je platny: %s" % str(ed4.level.validate()))
	for i in range(ed4.level.lane_count()):
		if ed4.level.target_kind(i) == Level.TO_LANE:
			_ok(ed4.level.to_of(i) < ed4.level.lane_count() and ed4.level.to_of(i) != i,
				"usek %d se nenapojuje sam na sebe nebo mimo desku (%d)" % [i + 1, ed4.level.to_of(i)])

	# --- CIL ZMIZI I KDYBY ZMIZELA CELA VETEV ---
	# (slouceni vyhybky zpet do useku nechava druhy cil prazdny)
	var ed3 := _fresh()
	ed3.sel = 0
	ed3.press(Editor.BTN_JUNCTION)
	var e3before: int = ed3.level.exits.size()
	ed3.sel = 0
	_ok(ed3.can_merge(), "rozdeleny usek se da slit zpet")
	ed3.press(Editor.BTN_JUNCTION)
	_ok(ed3.level.exits.size() <= e3before,
		"po sliti nezustal osirely cil (%d -> %d)" % [e3before, ed3.level.exits.size()])
	_ok(ed3.level.validate().is_empty(), "a level je platny: %s" % str(ed3.level.validate()))


func _test_autosave() -> void:
	# KAZDA ZMENA SE UKLADA LOKALNE. Neni to "ulozit pro hrace" - je to jen
	# to, aby o praci neprisel, kdyz mu prohlizec zavre panel. Nikam se nic
	# neposila (zadna Firestore).
	var ed := _fresh()
	ed.press(Editor.BTN_ADD)
	ed.press(Editor.BTN_ELEMENT)
	var name: String = ed.level.name
	_ok(not name.is_empty() and name != Level.DEFAULT_NAME,
		"level dostane lokalni jmeno (%s)" % name)
	_ok(not ed.level.validate().size(), "a je platny")
	var back := Level.load_named(name)
	_ok(back.lane_count() == ed.level.lane_count(),
		"co je ulozene, to se i nacte (%d vs %d)" % [back.lane_count(), ed.level.lane_count()])
	_ok(back.to_code() == ed.level.to_code(), "a beze zmeny")
	_ok(Level.saved_names().has(name), "a je v seznamu lokalnich levelu")


func _test_export_code() -> void:
	# EXPORT: hrac si level odnese jako JEDNU RADU TEXTU, kterou mi posle.
	# Kdyby kod nešel prect, ztratila by se cela cesta "level z telefonu do
	# hry" - a to je presne to, o co tu jde.
	var ed := _fresh()
	ed.press(Editor.BTN_ADD)
	ed.press(Editor.BTN_ELEMENT)
	ed.press(Editor.BTN_BEND_LEFT)
	ed.press(Editor.BTN_EXPORT)
	_ok(not ed.code.is_empty(), "export vyrobi kod levelu")
	_ok(ed.code.begins_with(Level.CODE_PREFIX),
		"kod je oznaceny verzi formatu (%s)" % ed.code.substr(0, 8))
	_ok(not ed.code.contains("\n"), "kod je v jedne rade (vejde se do Telegramu)")
	_ok(ed.code.length() < 900, "a je kratky (%d znaku)" % ed.code.length())
	var back := Level.from_code(ed.code)
	_ok(back.lane_count() == ed.level.lane_count(), "kod se da precist zpet")
	_ok(back.to_code() == ed.code, "a je presne stejny jako predany nivel")
	# a to same musi projit i pro level, ktery prisel z druhe strany
	var base_code: String = Level.base().to_code()
	var from_base := Level.from_code(base_code)
	_ok(from_base.lane_count() == Level.base().lane_count(),
		"a zakladni deska se da predat taky (%d znaku)" % base_code.length())
	# nesmyslny kod nesmi shodit hru - vrati zakladni desku
	_ok(Level.from_code("nesmysl").lane_count() == Level.base().lane_count(),
		"nesmyslny kod vrati zakladni desku")
	# KOD MUSI UNEST I VYHYBKY, NAPOJENI NA JINY USEK A DVA VSTUPY. Tudy se
	# level dostava z telefonu ke mne - kdyby se pri ceste neco ztratilo,
	# dostal by hrac do hry neco jineho, nez si nakreslil.
	var ed2 := _fresh()
	# uberneme useky, aby zbylo misto i na novou vetev s vlastnim kmenem
	while ed2.level.lane_count() > 3:
		ed2.sel = ed2.level.lane_count() - 1
		ed2.press(Editor.BTN_DEL)
	ed2.sel = 0
	ed2.press(Editor.BTN_JUNCTION)        # rozdeleni useku = druha vyhybka
	ed2.press(Editor.BTN_ENTRY)           # druhy vstup (nova vetev s kmenem)
	if ed2.level.lane_count() > 2:
		# usek se napoji na jiny usek
		ed2.sel = ed2.level.lane_count() - 1
		for i in range(ed2.level.lane_count() + 2):
			if ed2.level.target_kind(ed2.sel) == Level.TO_LANE:
				break
			ed2.press(Editor.BTN_TARGET)
	_ok(ed2.level.junction_count() >= 2, "level ma vic vyhybek (%d)" % ed2.level.junction_count())
	_ok(ed2.level.entries.size() >= 2, "a vic vstupu (%d)" % ed2.level.entries.size())
	var rich: String = ed2.level.to_code()
	_ok(not rich.contains("\n"), "kod s vyhybkami je porad v jedne rade (%d znaku)" % rich.length())
	_ok(rich.length() < 900, "a vejde se do Telegramu (%d znaku)" % rich.length())
	var back2 := Level.from_code(rich)
	_ok(back2.junction_count() == ed2.level.junction_count(),
		"vyhybky preziji cestu kodem (%d vs %d)" % [back2.junction_count(), ed2.level.junction_count()])
	_ok(back2.entries.size() == ed2.level.entries.size(),
		"i vstupy (%d vs %d)" % [back2.entries.size(), ed2.level.entries.size()])
	_ok(back2.to_code() == rich, "a kod je po ceste tam a zpet presne stejny")
	_ok(back2.validate().is_empty(), "a level z kodu je platny: %s" % str(back2.validate()))
	var kinds_same := true
	for i in range(mini(back2.lane_count(), ed2.level.lane_count())):
		if back2.target_kind(i) != ed2.level.target_kind(i) or back2.to_of(i) != ed2.level.to_of(i):
			kinds_same = false
	_ok(kinds_same, "a kazdy usek si drzi svuj cil i jeho druh")


func _test_builtin_levels() -> void:
	# ZAKOTVENE LEVELY. Sem prijde level, ktery Jan posle jako kod. Kazdy
	# zakotveny level musi byt platny - kdyby ne, hrac by si vybral level,
	# ktery se ani neda dohrat.
	for item in BuiltinLevels.LEVELS:
		var d: Dictionary = item
		var n: String = str(d.get("name", ""))
		_ok(not n.is_empty(), "zakotveny level ma jmeno")
		var lv := Level.builtin(n)
		_ok(lv != null, "zakotveny level %s se da precist" % n)
		if lv == null:
			continue
		_ok(lv.validate().is_empty(),
			"zakotveny level %s je platny: %s" % [n, str(lv.validate())])
		_ok(lv.to_code() == str(d.get("code", "")), "kod levelu %s neni prepisany rucne" % n)
	# zakladni deska neni zakotvena - je primo ve hre
	_ok(Level.builtin("zakladni") == null or Level.builtin_names().has("zakladni"),
		"zakladni deska neni mezi zakotvenymi (je primo ve hre)")
	var ed := _fresh()
	var names: Array = ed.available_levels()
	_ok(not names.is_empty(), "editor umi vypsat, co je k nacteni (%d)" % names.size())


func _test_play_custom_level() -> void:
	# Z EDITORU SE MUSI DAT HRAT. Hra dostane kopii levelu, ne level sam -
	# kdyby dostala ten sam, sahala by za behu do toho, co hrac upravuje.
	var ed := _fresh()
	ed.press(Editor.BTN_ADD)
	ed.press(Editor.BTN_ADD)
	var n: int = ed.level.lane_count()
	var g := Game.new()
	g.setup(Rect2(40.0, 80.0, 880.0, 404.0), 1.0, 500.0, ed.level.clone())
	_ok(g.net.lane_count() == n, "hra se postavi z upraveneho levelu (%d)" % g.net.lane_count())
	# a hra vi, KTERY level to je - hrac to vidi v HUDu
	_ok(g.level != null and g.level.name == ed.level.name,
		"hra zna jmeno levelu, ktery hraje (%s)" % (g.level.name if g.level != null else "?"))
	# hra si drzi SVOU kopii: uprava v editoru se do rozjete hry nepropise
	ed.press(Editor.BTN_DEL)
	_ok(g.net.lane_count() == n, "a pozdejsi uprava v editoru do hry nesaha")
	# klepnuti na usek vybere prave ten usek (i v editoru, kde je vic useku)
	g.auto_wave = false
	for lane in range(g.net.lane_count()):
		var p: Vector2 = g.net.point_at(lane, g.net.lane_len[lane] * 0.7)
		_ok(g.net.lane_tap_at(p, 16.0) == lane, "v levelu z editoru vybere klepnuti usek %d" % lane)


func _test_selector_matches_drawn_lanes() -> void:
	# VYBER USEKU MUSI SEDET NA TO, CO JE VIDET. Hrac klepne na usek a
	# editor vybere ten usek - ne sousedni. Klepne se na stred kazdeho
	# useku a vysledek se porovna s tim, ktery usek je tam nakresleny.
	var ed := _fresh()
	var g := Game.new()
	g.setup(Rect2(40.0, 80.0, 880.0, 404.0), 1.0, 500.0, ed.level.clone())
	for lane in range(g.net.lane_count()):
		var p: Vector2 = g.net.point_at(lane, g.net.lane_len[lane] * 0.5)
		_ok(g.net.lane_tap_at(p, 16.0) == lane, "stred useku %d vybere usek %d" % [lane, lane])
		# a mimo vsechny useky se nevybere nic - klepnuti do prazdna
		# nesmi prepsat vyber
	var far: Vector2 = Vector2(g.net.area.end.x - 2.0, g.net.area.position.y + 2.0)
	_ok(g.net.lane_tap_at(far, 8.0) == -1, "klepnuti do prazdna nevybere zadny usek")


func _test_status_text() -> void:
	# Hlaska pro hrace. Kdyz je prazdna nebo nesmyslna, hrac nevi, co dela.
	var ed := _fresh()
	_ok(not ed.sel_text().is_empty(), "popis vybraneho useku neni prazdny")
	_ok(ed.sel_text().contains("úsek 1"), "a je v nem cislo useku (%s)" % ed.sel_text())
	var before: String = ed.sel_text()
	ed.press(Editor.BTN_ELEMENT)
	_ok(ed.status != before, "po zmene zivlu se hlaska zmeni (%s)" % ed.status)
	# a kdyz se usek odebere, vyber se nesmi utrhnout mimo level
	ed.sel = 99
	ed.press(Editor.BTN_DEL)
	ed.press(Editor.BTN_ELEMENT)
	_ok(ed.sel < ed.level.lane_count(), "vyber po odebrani zustava v levelu (%d)" % ed.sel)


# --------------------------------------------------------------- vyhybky

# ROZDELENI A SLITI USEKU. Tohle je cela pointa druhe vyhybky: hrac si vyrobi
# dalsi volbu na ceste, ktera dosud zadnou nemela - a kdyz se mu to nelibi,
# zase ji zrusi. Kdyby slo jen pridavat, byl by level jednosmerka.
func _test_junction_split_merge() -> void:
	var ed := _fresh()
	var n0: int = ed.level.lane_count()
	var before_to: int = ed.level.to_of(0)
	ed.sel = 0
	_ok(ed.can_split(), "vybrany usek se da rozdělit výhybkou")
	ed.press(Editor.BTN_JUNCTION)
	_ok(ed.level.junction_count() == 2, "přibyla druhá výhybka (%d)" % ed.level.junction_count())
	_ok(ed.level.lane_count() == n0 + 2, "a s ní dvě nové větve (%d)" % ed.level.lane_count())
	_ok(not ed.level.lane_is_exit(0), "rozdělený úsek už nekončí ve výstupu")
	var j: int = ed.level.junction_of(0)
	_ok(ed.level.lanes_of(j).size() == 2, "z nové výhybky vedou dva úseky")
	# jedna vetev pokracuje tam, kam vedl puvodni usek - cesta se nikam neztratila
	var kept := false
	var diff := false
	for k in ed.level.lanes_of(j):
		if ed.level.to_of(k) == before_to:
			kept = true
		else:
			diff = true
	_ok(kept, "jedna větev pokračuje do původního výstupu")
	_ok(diff, "druhá větev vede jinam - rozdělení něco znamená")
	_ok(ed.level.validate().is_empty(),
		"takový level je platný: %s" % str(ed.level.validate()))
	# usek z prvni vyhybky je kratky, ale i na nem musi byt misto na bonusy
	var n_net := Network.new()
	n_net.build(Rect2(40.0, 80.0, 880.0, 404.0), 1.0, 500.0, ed.level)
	_ok(n_net.junction_count() == 2, "síť postaví obě výhybky")
	_ok(n_net.lane_run[0][1] - n_net.lane_run[0][0] > 40.0,
		"rovný úsek spojovacího useku má rozumnou délku (%.0f)" % (n_net.lane_run[0][1] - n_net.lane_run[0][0]))
	# SLITI ZPET
	ed.sel = 0
	_ok(ed.can_merge(), "rozdělený úsek se dá zase slít")
	ed.press(Editor.BTN_JUNCTION)
	_ok(ed.level.junction_count() == 1, "výhybka zmizela (%d)" % ed.level.junction_count())
	_ok(ed.level.lane_count() == n0, "a s ní i její větve (%d)" % ed.level.lane_count())
	_ok(ed.level.to_of(0) == before_to, "úsek vede zase tam, kam vedl")


# HLOUBKA. Z vetve druhe vyhybky uz treti vest nesmi - mezi vyhybkou a
# vystupem musi zustat misto na rovny usek s bonusy. A cil vetve z vyhybky
# nesmi nabizet jinou vyhybku: vznikla by smycka, po ktere by poutnik sel
# porad dokola.
func _test_junction_depth_limit() -> void:
	var ed := _fresh()
	ed.sel = 0
	ed.press(Editor.BTN_JUNCTION)
	var j: int = ed.level.junction_of(0)
	var sub: int = int(ed.level.lanes_of(j)[0])
	ed.sel = sub
	_ok(not ed.can_split(), "z větve druhé výhybky už další výhybka nejde")
	ed.press(Editor.BTN_JUNCTION)
	_ok(ed.level.junction_count() == 2,
		"a opravdu žádná nepřibyla (%d)" % ed.level.junction_count())
	var bad := 0
	for c in ed.level.target_choices(sub):
		var cc: Dictionary = c
		if int(cc["kind"]) == Level.TO_JUNCTION:
			bad += 1
	_ok(bad == 0, "větev z výhybky míří jen do výstupů nebo na jiné úseky (%d do výhybek)" % bad)
	_ok(ed.level.validate().is_empty(), "a takový level je platný")


# NAPOVEDA V HLASCE: "cíl" je cyklus a hrac musi videt, co bude nasledovat -
# jinak se k napojeni dvou useku (dve cesty se sliji v jednu) dostane jen
# ten, kdo vi, ze za vystupy cyklus pokracuje dal. A napoveda NESMI LHAT:
# dalsi stisk musi dat presne to, co slibila.
func _test_target_hint_tells_the_next_choice() -> void:
	var ed := _fresh()
	ed.sel = 1
	for i in range(12):
		ed.press(Editor.BTN_TARGET)
		_ok(ed.status.contains("další cíl:"), "hlaska rika, co bude nasledovat (%s)" % ed.status)
		var p: int = ed.status.find("další cíl: ")
		if p < 0:
			return
		var promised: String = ed.status.substr(p + "další cíl: ".length()).strip_edges()
		ed.press(Editor.BTN_TARGET)
		# Text se bere STEJNYM volanim jako v editoru - i s uzlem a s usekem,
		# ktery se napojuje. Bez nich by text vzdy tvrdil "uzel 1/3" a test by
		# prosel, i kdyby napoveda lhala.
		var now: String = ed.level.choice_text(ed.level.target_kind(1), ed.level.to_of(1),
			ed.level.lane_node(1), 1)
		# Napoveda muze za text cile pridat " (rozdělí úsek N)" - napojeni
		# cilovy usek ROZDĚLÍ a z textu cile to videt neni. Zbytek musi sedet
		# presne, proto se porovnava text cile a pripadna poznamka zvlast.
		var ok: bool = promised == now or promised.begins_with(now + " (rozdělí úsek ")
		_ok(ok, "napoveda nelhala: slibila \"%s\", stalo se \"%s\"" % [promised, now])
	_ok(ed.level.validate().is_empty(), "a level je pořád platný: %s" % str(ed.level.validate()))


# --------------------------------------------------------------- seznam

# SEZNAM ULOZENYCH LEVELU. Ulozene levely musi byt odnekud videt a klepnutim
# se musi dat nacist zpet - jinak by kazde otevreni editoru zacalo od nuly
# a ulozena prace by byla nedostizna.
func _test_level_list() -> void:
	var ed := _fresh()
	ed.press(Editor.BTN_ADD)
	var name: String = ed.local_name
	var rows := 8
	var items: Array = ed.list_items(rows)
	_ok(items.size() <= rows, "seznam se vejde na displej (%d radku)" % items.size())
	_ok(str(items[0]["kind"]) == "new", "prvni radek je novy level")
	_ok(str(items[items.size() - 1]["kind"]) == "back", "posledni je navrat do editoru")
	var found := false
	for it in items:
		if str(it["kind"]) == "level" and str(it["name"]) == name:
			found = true
	_ok(found, "právě uložený level je v seznamu")
	# klepnuti na radek level nacte - a hrac v nem muze pokracovat
	var want := ed.level.lane_count()
	var ed2 := Editor.new()
	ed2.list_items(rows)
	ed2.load_named(name)
	_ok(ed2.level.lane_count() == want, "načtený level má stejné úseky (%d)" % ed2.level.lane_count())
	_ok(ed2.local_name == name, "a další změny jdou zase do něho, ne do nového")
	ed2.press(Editor.BTN_ELEMENT)
	_ok(Level.load_named(name).lane_count() == want,
		"a uloží se zpátky pod svým jménem")
	# novy level zpet dostane nove jmeno, aby se v seznamu neprekryl
	var ed3 := Editor.new()
	ed3.reset()
	_ok(ed3.local_name != name, "nový level má vlastní jméno (%s vs %s)" % [ed3.local_name, name])
	_ok(Level.saved_names().has(ed3.local_name), "a je hned v seznamu")


# EDITOR SE OTEVRE TAM, KDE Hrac SKONCIL. Kdyby zacinal vzdy od nuly, prisel
# by hrac o rozdelanou praci pri kazdem odskoci do hry.
func _test_open_last() -> void:
	var ed := _fresh()
	ed.press(Editor.BTN_ADD)
	var name: String = ed.local_name
	var lanes: int = ed.level.lane_count()
	var ed2 := Editor.new()
	ed2.open_last()
	_ok(ed2.local_name == name,
		"editor se otevře tam, kde hráč skončil (%s vs %s)" % [ed2.local_name, name])
	_ok(ed2.level.lane_count() == lanes, "a s tím, co měl rozdělané (%d)" % ed2.level.lane_count())


# --------------------------------------------------------------- vstupy

# VSTUP (KMEN). Tlacitkem se pridava dalsi vstup do mapy. Do vyhybky, do ktere
# uz vede usek, kmen pripojit nelze - vede z leveho okraje pres vsechno pred
# ni. Proto se zalozi cela nova vetev s vlastnim kmenem: mapa ma dva vstupy.
func _test_entry_button() -> void:
	var ed := _fresh()
	ed.sel = 0
	var j0: int = ed.level.from_of(0)
	_ok(ed.level.has_entry(j0), "prvni vyhybka ma kmen")
	_ok(ed.button_labels()[Editor.BTN_ENTRY] == "vstup +",
		"dokud je kmen jen jeden, tlacitko pridava")
	ed.press(Editor.BTN_ENTRY)
	_ok(ed.level.entries.size() == 2, "pribyl druhy vstup (%d)" % ed.level.entries.size())
	_ok(ed.level.junction_count() == 2, "a s nim druha vyhybka (%d)" % ed.level.junction_count())
	_ok(ed.level.validate().is_empty(),
		"takovy level je platny: %s" % str(ed.level.validate()))
	# poutnici musi mit kudy - nova vetev ma sve useky
	var j1: int = int(ed.level.entries[1])
	_ok(ed.level.lanes_of(j1).size() == 2, "nova vetev ma dva useky")
	# a kdyz u ni hrac stiskne vstup znovu, kmen zase zmizi
	var sub: int = int(ed.level.lanes_of(j1)[0])
	ed.sel = sub
	_ok(ed.button_labels()[Editor.BTN_ENTRY] == "vstup −",
		"u vetve, ktera kmen ma, se tlacitko meni na vstup −")
	ed.press(Editor.BTN_ENTRY)
	_ok(ed.level.entries.size() == 1, "a kmen zase zmizi (%d)" % ed.level.entries.size())
	_ok(ed.level.junction_count() == 1, "i s celou svou vetvi (%d)" % ed.level.junction_count())
	_ok(ed.level.validate().is_empty(), "level je porad platny")
	# prvni kmen (hlavni vstup) smazat nelze - zmizela by cela deska
	ed.sel = 0
	ed.press(Editor.BTN_ENTRY)
	_ok(ed.level.entries.size() >= 1, "hlavni kmen zustava (%d)" % ed.level.entries.size())
	_ok(ed.level.lane_count() >= Level.MIN_LANES, "a s nim i cela deska (%d useku)" % ed.level.lane_count())


# CIL MUZE BYT I JINY USEK. Vybocena vetev se muze vlejt do druhe vetve, ne
# jen do vystupu nebo do vyhybky. Preskoci se to, co by udelalo smycku.
func _test_target_joins_lane() -> void:
	var ed := _fresh()
	ed.sel = 1
	var joins := 0
	var seen_kinds := {}
	for i in range(ed.level.lane_count() + 2):
		var kind: int = ed.level.target_kind(1)
		seen_kinds[kind] = true
		if kind == Level.TO_LANE:
			joins += 1
		ed.press(Editor.BTN_TARGET)
	_ok(joins > 0, "cíl se dá nastavit i na jiný úsek (%d z %d poloh)" % [
		joins, ed.level.lane_count() + 2])
	_ok(seen_kinds.has(Level.TO_EXIT), "a pořád jde nastavit i výstup")
	# usek se nesmi napojit sam na sebe
	var self_join := false
	ed.sel = 0
	for i in range(ed.level.lane_count() + 2):
		if ed.level.target_kind(0) == Level.TO_LANE and ed.level.lane_target_of(0) == 0:
			self_join = true
		ed.press(Editor.BTN_TARGET)
	_ok(not self_join, "usek se nenapojuje sam na sebe")
	_ok(ed.level.validate().is_empty(),
		"a level zustava platny: %s" % str(ed.level.validate()))


# VETEV Z HLUBSI VYHYBKY SE MUSI DAT NAPOJIT I NA JINE USEKY, NE JEN NA
# SOUROZENCE. Jan: "Jeden úsek jde napojit na uzly jednoho dalšího úseku, ale
# pak už další úseky ignoruje." Driv byla geometrie tak prisna (pevny podil
# rovneho useku v can_target), ze vetvi z druhe vyhybky zbyl JEDINY cilovy
# usek - jeji sourozenec - a ostatni useky se tvarily, jako by neexistovaly.
func _test_deep_branch_joins_other_lanes() -> void:
	var ed := _fresh()
	ed.sel = 4
	ed.press(Editor.BTN_JUNCTION)
	var j: int = ed.level.junction_of(4)
	if j < 0:
		_ok(false, "usek 4 se rozdělil výhybkou")
		return
	var kids: Array = ed.level.lanes_of(j)
	_ok(kids.size() == 2, "z nove vyhybky vedou dve vetve (%d)" % kids.size())
	var branch: int = int(kids[0])
	var sibling: int = int(kids[1])
	var targets := {}
	for c in ed.level.target_choices(branch):
		if int(c["kind"]) == Level.TO_LANE:
			targets[int(c["to"])] = true
	_ok(targets.size() >= 4,
		"vetev z výhybky se dá napojit na vic úseků (%d: %s)" % [targets.size(), str(targets.keys())])
	_ok(targets.has(sibling), "a mezi nimi je i sourozenecká větev")
	var outside := 0
	for t in targets:
		if int(t) != sibling:
			outside += 1
	_ok(outside >= 3, "a taky úseky mimo ni (%d)" % outside)
	# a napojeni musi byt i REALNE: level po nem zustane platny a kod projde
	var pick: int = int(targets.keys()[0])
	for t in targets:
		if int(t) != sibling:
			pick = int(t)
			break
	var node: int = ed.level.usable_nodes(branch, pick)[0]
	var l: Dictionary = ed.level.lanes[branch]
	l["kind"] = Level.TO_LANE
	l["to"] = pick
	l["node"] = node
	ed.level.lanes[branch] = l
	ed.level.relayout()
	_ok(ed.level.validate().is_empty(),
		"napojení vetve na úsek %d (uzel %d) je platné: %s" % [pick + 1, node + 1, str(ed.level.validate())])
	var back := Level.from_code(ed.level.to_code())
	_ok(back.to_code() == ed.level.to_code(), "a kod levelu projde tam i zpet")


# ROZDĚLENÍ SE DÁ POLOŽIT NA NĚKOLIK MÍST CÍLOVÉ CESTY. Jan: "musíme udělat
# komplexnější větvení pomocí výhybek. Aby měl každý úsek X uzlů, do kterých se
# může úsek zakončit... jeden úsek může končit v jiném a měl by mít možnost
# končit v různých uzlech daného úseku. Ne jen v jednom jak je to teď."
#
# Napojení je teď zároveň ROZDĚLENÍ (split_at_join): uzel cílové cesty, do
# kterého hráč napojení postaví, JE místo, kde se cesta rozdělí. Poloha
# rozdělení se posouvá tlačítky "uzel ±" (cyklus "cíl" vlastní cestu přeskakuje,
# aby se na ní nezasekl) - a tenhle test hlídá, že se opravdu dostane na víc
# míst než jedno.
func _test_join_has_several_nodes() -> void:
	var ed := _fresh()
	ed.sel = 1
	for i in range(30):
		if ed.level.target_kind(1) == Level.TO_LANE:
			if ed.level.is_division(ed.level.from_of(ed.level.to_of(1))):
				break
		ed.press(Editor.BTN_TARGET)
	if ed.level.target_kind(1) != Level.TO_LANE:
		_ok(false, "usek 2 se vubec da napojit")
		return
	var places := {}
	var off_run := 0
	for i in range(Level.NODE_COUNT):
		var j: int = ed.level.from_of(ed.level.to_of(1))
		if not ed.level.is_division(j):
			break
		var x: float = ed.level.junction_x(j)
		places[snappedf(x, 0.005)] = true
		# ROZDĚLENÍ LEŽÍ NA ROVNÉM ÚSEKU: spodní úsek začíná přesně tam (proto
		# má první uzel v dělicím bodě) - jinak by na obou částech chybělo
		# místo na bonusy.
		if absf(ed.level.run_x0(ed.level.to_of(1)) - x) > 0.001:
			off_run += 1
		ed.press(Editor.BTN_BEND_RIGHT)          # uzel +
	_ok(places.size() >= 2,
		"jedna cesta se dá rozdělit na několika místech (%d)" % places.size())
	_ok(off_run == 0,
		"a rozdělení vždycky sedí na začátek rovného úseku spodního úseku (%d mimo)" % off_run)
	_ok(ed.level.validate().is_empty(), "level je po celou dobu platný: %s" % str(ed.level.validate()))

	# --- MÍSTO ROZDĚLENÍ SE MUSÍ UDRŽET V KÓDU LEVELU ---
	# (pres kod se level dostava z telefonu do hry; ztracene misto rozdeleni =
	#  jiny level - cesta by se delila jinde, nez si hrac nakreslil)
	var jx: float = ed.level.junction_x(ed.level.from_of(ed.level.to_of(1)))
	var code: String = ed.level.to_code()
	var back := Level.from_code(code)
	_ok(back.to_code() == code, "a kod levelu misto rozdeleni udrzi")
	_ok(back.is_division(back.from_of(back.to_of(1)))
			and absf(back.junction_x(back.from_of(back.to_of(1))) - jx) < 0.002,
		"a po ceste tam a zpet je rozdeleni na stejnem miste (%.3f vs %.3f)" % [
			jx, back.junction_x(back.from_of(back.to_of(1)))])
	_ok(back.validate().is_empty(), "a takovy level je platny: %s" % str(back.validate()))
	# --- VSTUPNÍ BOD JE PŘESNĚ V MÍSTĚ ROZDĚLENÍ ---
	# Poutnik vstupuje do svého (spodního) úseku v jeho prvním uzlu - a ten JE
	# to rozdělení. Měří se ve světe: vstupní bod musí sedět na místo rozdělení.
	var n_net := Network.new()
	n_net.build(Rect2(40.0, 80.0, 880.0, 404.0), 1.0, 500.0, ed.level)
	var j_now: int = ed.level.from_of(ed.level.to_of(1))
	# VSTUPNÍ BOD PATŘÍ CÍLOVÉMU ÚSEKU: hodnota je vzdálenost po JEHO trase
	# (proto se čte z lane_entry_s[privodni] a měří na `to`).
	var p_entry: Vector2 = n_net.point_at(ed.level.to_of(1), n_net.lane_entry_s[1])
	var p_div: Vector2 = n_net.junction_pos[j_now]
	_ok(p_entry.distance_to(p_div) < 45.0,
		"poutník vstoupí přesně v místě rozdělení (%.0f,%.0f vs %.0f,%.0f)" % [
			p_entry.x, p_entry.y, p_div.x, p_div.y])


# RUCNI ZRUSENI CILE. Jan: "cíle stále po smazání úseku nemizí. Přidáme tedy
# možnost smazat cíl ručně." Automatika maze jen cil, do ktereho po smazane
# ceste nic nevede (a to je spravne). Tlacitko "cíl −" maze i cil, do ktereho
# jeste neco vede - ty cesty se prepoji na jiny cil a level zustane platny.
func _test_exit_delete_button() -> void:
	# --- 1) cil, do ktereho vede vybrany usek sam ---
	var ed := _fresh()
	var last: int = ed.level.lane_count() - 1
	ed.sel = last
	var e: int = ed.level.exit_of(last)
	_ok(e >= 0, "posledni usek usti do cile (%d)" % e)
	var n0: int = ed.level.exits.size()
	ed.press(Editor.BTN_EXIT_DEL)
	_ok(ed.level.exits.size() == n0 - 1,
		"tlacitko 'cíl −' cil zrusi (%d -> %d)" % [n0, ed.level.exits.size()])
	_ok(ed.level.validate().is_empty(), "a level zustava platny: %s" % str(ed.level.validate()))
	_ok(not ed.status.is_empty(), "a hlaska rekne, co se stalo (%s)" % ed.status)

	# --- 2) cil, do ktereho vede vic useku ---
	# (na zakladni desce vedou prvni dva useky do stejneho cile - presne to je
	#  ten pripad, kdy automatika cil nechava a Jan ho nevidel zmizet)
	var ed2 := _fresh()
	_ok(ed2.level.exit_of(0) == ed2.level.exit_of(1),
		"prvni dva useky vedou do stejneho cile (%d, %d)" % [
			ed2.level.exit_of(0), ed2.level.exit_of(1)])
	var c0: int = ed2.level.exits.size()
	ed2.sel = 0
	ed2.press(Editor.BTN_EXIT_DEL)
	_ok(ed2.level.exits.size() == c0 - 1,
		"sdileny cil zmizi taky (%d -> %d)" % [c0, ed2.level.exits.size()])
	_ok(ed2.status.contains("přepojil"),
		"a hlaska rekne, ktere useky se prepojily (%s)" % ed2.status)
	for i in range(ed2.level.lane_count()):
		if ed2.level.target_kind(i) == Level.TO_EXIT:
			_ok(ed2.level.exit_of(i) < ed2.level.exits.size(),
				"usek %d nemiri na zruseny cil (%d z %d)" % [
					i + 1, ed2.level.exit_of(i), ed2.level.exits.size()])
	_ok(ed2.level.validate().is_empty(), "a level je platny: %s" % str(ed2.level.validate()))

	# --- 3) posledni cil zustava ---
	# (jinak by nebylo kam dojit - kazdy poutnik by musel vstoupit)
	var ed3 := _fresh()
	var guard := 0
	while ed3.level.exits.size() > 1 and guard < 40:
		guard += 1
		var done := false
		for k in range(ed3.level.lane_count()):
			ed3.sel = k
			if ed3.level.exit_of(k) >= 0:
				ed3.press(Editor.BTN_EXIT_DEL)
				done = true
				break
		if not done:
			break
	_ok(ed3.level.exits.size() == 1, "posledni cil zustava (%d)" % ed3.level.exits.size())
	ed3.sel = 0
	ed3.press(Editor.BTN_EXIT_DEL)
	_ok(ed3.level.exits.size() == 1, "a dalsi uz ho neveme (%d)" % ed3.level.exits.size())
	_ok(not ed3.status.is_empty(), "a hlaska rekne proc (%s)" % ed3.status)
	_ok(ed3.level.validate().is_empty(), "a level je platny: %s" % str(ed3.level.validate()))


# SAMOSTATNE OVLADANI UZLU. Jan: "Samostatné ovládání by bylo lepší." Uzel se
# posouva tlacitky, ktera mimo napojeni hybou odbocenim - u napojeni se
# prejmenuji na "uzel −"/"uzel +" a jeden stisk = sousedni uzel. Hrac tak
# nemusi prokladat cely cyklus "cíl", aby se posunul o uzel dal.
func _test_node_step_buttons() -> void:
	# --- 1) U NAPOJENI POSOUVAJI ROZDĚLENÍ ---
	# Napojení je zároveň místo rozdělení, takže "uzel ±" posouvá ROZDĚLENÍ po
	# cílové cestě. Napojený úsek vždycky vstupuje do prvního uzlu svého cíle -
	# tím uzlem JE to rozdělení, takže se posouvá místo rozdělení, ne číslo
	# uzlu u napojeného úseku.
	var ed := _fresh()
	_join_at_node_zero(ed, 1)
	if ed.level.target_kind(1) != Level.TO_LANE:
		_ok(false, "usek 2 se vubec da napojit")
		return
	var labels: Array = ed.button_labels()
	_ok(str(labels[Editor.BTN_BEND_LEFT]).contains("uzel")
			and str(labels[Editor.BTN_BEND_RIGHT]).contains("uzel"),
		"u napojeni se tlacitka jmenuji 'uzel' (%s, %s)" % [
			labels[Editor.BTN_BEND_LEFT], labels[Editor.BTN_BEND_RIGHT]])
	var x0: float = ed.level.junction_x(ed.level.from_of(ed.level.to_of(1)))
	ed.press(Editor.BTN_BEND_RIGHT)
	var x1: float = ed.level.junction_x(ed.level.from_of(ed.level.to_of(1)))
	_ok(x1 > x0 + 0.001, "a stisk posune rozdeleni po ceste dal (%.3f -> %.3f)" % [x0, x1])
	_ok(ed.status.contains("rozdělení"), "a hlaska rekne co (%s)" % ed.status)
	var code: String = ed.level.to_code()
	var back := Level.from_code(code)
	_ok(back.to_code() == code
			and absf(back.junction_x(back.from_of(back.to_of(1))) - x1) < 0.002,
		"kod si posunute rozdeleni udrzi (%.3f)" % back.junction_x(back.from_of(back.to_of(1))))
	# a zpet na druhou stranu (jen kdyz tam geometrie nechá místo - jinak to
	# editor rekne a nechá rozdeleni tam, kde je)
	ed.press(Editor.BTN_BEND_LEFT)
	var x2: float = ed.level.junction_x(ed.level.from_of(ed.level.to_of(1)))
	_ok(x2 < x1 - 0.001 or ed.status.contains("nedá"),
		"'uzel −' budto posune rozdeleni zpet, nebo rekne ze to nejde (%.3f, %s)" % [x2, ed.status])
	_ok(ed.level.validate().is_empty(), "takovy level je platny: %s" % str(ed.level.validate()))

	# --- 2) MIMO NAPOJENI HYBOU ODBOCENIM (jako driv) ---
	var ed2 := _fresh()
	ed2.sel = 0
	_ok(str(ed2.button_labels()[Editor.BTN_BEND_LEFT]) == "odboč −",
		"mimo napojeni je to porad 'odboč' (%s)" % ed2.button_labels()[Editor.BTN_BEND_LEFT])
	var d0: float = ed2.level.divert_of(0)
	ed2.press(Editor.BTN_BEND_RIGHT)
	_ok(ed2.level.divert_of(0) > d0,
		"a meni se odboceni, ne uzel (%.2f -> %.2f)" % [d0, ed2.level.divert_of(0)])

	# --- 3) POSUN ROZDĚLENÍ NIKDY NEROZBIJE LEVEL ---
	# Editor NIKDY nesmi nechat level v podobě, ktera se neda vyexportovat:
	# kdyz uz posun opravdu nema kam, vrati ho a rekne proc.
	var ed3 := _fresh()
	_join_at_node_zero(ed3, 1)
	if ed3.level.target_kind(1) != Level.TO_LANE:
		return
	for i in range(40):
		ed3.press(Editor.BTN_BEND_RIGHT)
		_ok(ed3.level.validate().is_empty(),
			"ani po mnoha posunech je level platny: %s" % str(ed3.level.validate()))
	for i in range(40):
		ed3.press(Editor.BTN_BEND_LEFT)
		_ok(ed3.level.validate().is_empty(),
			"a plati to i pro posun zpet: %s" % str(ed3.level.validate()))
	_ok(ed3.level.target_kind(1) == Level.TO_LANE,
		"napojeni na cilovy usek zustalo (kind=%d)" % ed3.level.target_kind(1))
	var back3 := Level.from_code(ed3.level.to_code())
	_ok(back3.to_code() == ed3.level.to_code(), "a kod levelu projde tam i zpet")

	# --- 4) ROZDĚLENÍ MÁ SVŮJ KONEC A EDITOR TO REKNE ---
	var ed4 := _fresh()
	_join_at_node_zero(ed4, 1)
	if ed4.level.target_kind(1) != Level.TO_LANE:
		return
	for i in range(10):
		ed4.press(Editor.BTN_BEND_RIGHT)
	_ok(not ed4.status.is_empty(), "hlaska rekne, jak to s rozdelenim je (%s)" % ed4.status)
	_ok(ed4.level.validate().is_empty(), "a level zustava platny: %s" % str(ed4.level.validate()))


# Usek `lane` napojeny na jiny usek v prvnim uzlu (cyklus "cíl" pres vystupy,
# useky az k napojeni).
func _join_at_node_zero(ed: Editor, lane: int) -> void:
	ed.sel = lane
	for i in range(80):
		if ed.level.target_kind(lane) == Level.TO_LANE and ed.level.lane_node(lane) == 0:
			return
		ed.press(Editor.BTN_TARGET)
