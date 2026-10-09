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
	# vystupy, takze se musi dat projit vsechny.
	var ed := _fresh()
	ed.sel = 0
	var seen := {}
	for i in range(ed.level.exits.size() + 1):
		seen[ed.level.to_of(0)] = true
		ed.press(Editor.BTN_TARGET)
	_ok(seen.size() == ed.level.exits.size(),
		"cíl se cykli pres vsechny vystupy (%d z %d)" % [seen.size(), ed.level.exits.size()])
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
	_ok(float(n_net.lane_entry_s[joined]) > 0.0,
		"napojený úsek má vstup, kde se do něj větev vlévá (%.0f px)" % n_net.lane_entry_s[joined])
	# a kód levelu to unese - jinak by se hracuv level prenasel spatne
	var back := Level.from_code(ed.level.to_code())
	_ok(back.to_code() == ed.level.to_code(), "a kod levelu napojeni udrzi")


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
		var now: String = ed.level.choice_text(ed.level.target_kind(1), ed.level.to_of(1))
		_ok(now == promised,
			"napoveda nelhala: slibila \"%s\", stalo se \"%s\"" % [promised, now])
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
