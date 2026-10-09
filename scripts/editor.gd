class_name Editor
extends RefCounted

# LEVEL EDITOR. Jan si v nem macka levely rucne - na telefonu, bez souboru,
# bez klavesnice.
#
# Stav editoru je ZAMERNE mimo hru: hra ma svuj Game a editor si do nej jen
# posila hotovy level pres set_level(). Kdyby editor sahal do rozjete hry,
# musel by se resit, co je rozdeleny poutnik, kdo ma bonus a co zlato.
#
# INTERAKCE: klepnutim na usek se vybere, tlacitka dole meni VYBRANY usek.
# Zadne tazeni - Jan hraje na telefonu a tazeni prstem pres cely displej
# je na male obrazovce nepresne. Tlacitka jsou jednoznacna a vidi se u nich,
# co delaji.
#
# DVA REZIMY: kresleni levelu (EDIT) a SEZNAM ulozenych levelu (LIST). Seznam
# je potreba proto, ze levelu je vic a hrac se k nim musi dostat zpatky -
# jinak by kazde otevreni editoru zacalo od nuly a ulozena prace by byla
# nedostizna.
#
# UKLADANI JE LOKALNI. Nikam se nic neposila - zadna Firestore. Kdo chce
# level prenest do hry natrvalo, zmackne EXPORT a posle mi jednoradkovy KOD
# (vejde se do Telegramu i z telefonu). Ja ho vlozim do BuiltinLevels a level
# se veze s hrou na vsech platformach.
#
# Kazda zmena se rovnou uklada lokalne (localStorage / user://), aby hrac
# neprisel o praci, kdyz mu prohlizec zavre panel. Proto tu neni tlacitko
# "ulozit" - bylo by to tlacitko, ktere nic neresi.

enum { MODE_EDIT, MODE_LIST }

# Tlacitka editoru. Poradi je poradi ve spodnim pruhu.
const BTN_ADD := 0
const BTN_DEL := 1
const BTN_ELEMENT := 2
const BTN_TARGET := 3
# NOVY CIL JE JEN RUKOU. Automaticky vznikaly nove cile s kazdou novou cestou
# a hrac mel v mape diry, ktere nezadal - a cyklus "cíl" se prodluzoval.
const BTN_EXIT := 4
# RUCNI ZRUSENI CILE. Jan: "cíle stále po smazání úseku nemizí. Přidáme tedy
# možnost smazat cíl ručně." Automatika maze jen cil, do ktereho po smazane
# ceste nic nevede; rucne se maze i cil, do ktereho jeste neco vede (ty cesty
# se prepoji na jiny cil).
const BTN_EXIT_DEL := 5
const BTN_BEND_LEFT := 6
const BTN_BEND_RIGHT := 7
const BTN_JUNCTION := 8
const BTN_ENTRY := 9
const BTN_LIST := 10
const BTN_EXPORT := 11
const BTN_PLAY := 12
const BTN_LABELS := [
	"úsek +", "úsek −", "živel", "cíl", "cíl +", "cíl −", "odboč −", "odboč +",
	"výhybka", "vstup", "seznam", "export", "hrát",
]

var level: Level = Level.base()
# Ktery usek je vybrany. Meni se klepnutim na usek.
var sel: int = 0
# Hlaska pro hrace: co se prave stalo. Kresli se nad pruhem.
var status: String = ""
# Kod levelu pro predani. Po exportu se ukaze - hrac ho muze zkopirovat
# a poslat. Je to nejkratsi cesta z telefonu: soubor se z telefonu posila
# slozite, jedna rada textu ne.
var code: String = ""
# Jmeno, pod kterym se level uklada lokalne.
var local_name: String = ""
# Rezim editoru: kresleni, nebo seznam ulozenych levelu.
var mode: int = MODE_EDIT
# Stranka v seznamu. Levelu muze byt vic, nez se jich na displej vejde.
var list_page: int = 0


# NOVY LEVEL. Jmeno se generuje z volneho cisla ("level-1", "level-2", ...),
# aby se v seznamu dalo najit. Nahodne nebo casove jmeno by v seznamu
# neznamenalo nic.
func reset() -> void:
	level = Level.base()
	sel = 0
	code = ""
	mode = MODE_EDIT
	list_page = 0
	local_name = Level.next_free_name()
	level.name = local_name
	level.save()
	status = "nový level: " + local_name


# OTEVRI EDITOR TAM, KDE Hrac SKONCIL. Kdyz ma hrac rozdelany level, vrati se
# do nej; teprve kdyz nic rozdelaneho neni, zacina novy.
func open_last() -> void:
	var last: String = Level.last_name()
	if not last.is_empty() and Level.saved_names().has(last):
		load_named(last)
		return
	reset()


func _clamp_sel() -> void:
	if level.lane_count() <= 0:
		sel = 0
		return
	sel = clampi(sel, 0, level.lane_count() - 1)


# Nacte level - bud zakotveny ve hre, nebo lokalne ulozeny. Jeden vstup pro
# obe cesty: hrac nemusi vedet, odkud level prisel.
#
# ZAKOTVENY LEVEL SE NACTE JAKO KOPIE. Kdyby se upravoval pod svym jmenem,
# ulozil by se do lokalniho seznamu pod jmenem zakotveneho levelu - a pri
# dalsim nacteni by se hledal zase zakotveny, takze by hrac prisel o sve
# upravy. Kopie ma vlastni jmeno a je to jeji vlastni level.
func load_named(n: String) -> void:
	var lv: Level = Level.builtin(n)
	if lv == null:
		level = Level.load_named(n)
		local_name = level.name
		status = "načteno: " + level.name
	else:
		level = lv
		local_name = Level.next_free_name()
		level.name = local_name
		level.save()
		status = "kopie levelu %s → %s" % [n, local_name]
	sel = 0
	code = ""
	mode = MODE_EDIT
	list_page = 0


# Jedno tlacitko editoru. Vsechno, co editor umi, je tady - kdyby se
# operace rozdelila mezi tlacitka a klavesove zkratky, neslo by to na
# telefonu vubec pouzit.
func press(button: int) -> int:
	# VYBER SE SROVNA PRVNI. Hrac mohl klepnout na usek a pak level zmenit
	# (odebrat usek, nacist jiny) - bez toho by zivel nebo cil sahal
	# mimo level a hra by spadla az za behu.
	_clamp_sel()
	match button:
		BTN_ADD:
			var from_j: int = level.from_of(sel) if level.lane_count() > 0 else 0
			var keep: Level = level.clone()
			if level.add_lane(from_j):
				# Kdyby pridanim vznikla mrizka, na kterou uz nejsou radky,
				# zmena se vrati - hrac nesmi dostat level, ktery se mu pak
				# nevyexportuje.
				if not level.rows_fit():
					level = keep
					status = _rows_status()
					return button
				sel = level.lane_count() - 1
				status = "přidán úsek %d z výhybky %d" % [level.lane_count(), from_j + 1]
			else:
				status = "z té výhybky už vede víc úseků nejde"
			_after_change()
		BTN_DEL:
			if level.lane_count() <= Level.MIN_LANES:
				status = "méně než %d úseky nejdou" % Level.MIN_LANES
			elif level.remove_lane(sel):
				_clamp_sel()
				status = "odebrán úsek"
				_after_change()
			else:
				status = "úsek nejde odebrat"
		BTN_ELEMENT:
			_cycle_element()
		BTN_TARGET:
			_cycle_target()
		BTN_EXIT:
			_add_exit()
		BTN_EXIT_DEL:
			_exit_minus()
		BTN_BEND_LEFT:
			_bend(-Level.SPREAD_STEP * 5.0)
		BTN_BEND_RIGHT:
			_bend(Level.SPREAD_STEP * 5.0)
		BTN_JUNCTION:
			_junction()
		BTN_ENTRY:
			_entry()
		BTN_LIST:
			open_list()
		BTN_EXPORT:
			_export()
		BTN_PLAY:
			status = "spouštím hru s tímto levelem"
	return button


# Popisky tlacitek. Tlacitko vyhybky rika, co udela TED - rozdelit usek,
# nebo ho naopak pripojit zpet. Tlacitko, ktere dela neco jineho, nez je na
# nem napsane, je horsi nez zadne.
func button_labels() -> Array:
	var out: Array = []
	for l in BTN_LABELS:
		out.append(str(l))
	out[BTN_JUNCTION] = "výhybka" if can_split() else ("sloučit" if can_merge() else "výhybka")
	# Tlacitko kmene rika presne to, co udela: "vstup −" jen kdyz je opravdu
	# co odebrat. Kdyz by popisek lhal, hrac by dvakrat zmackl "vstup +" a
	# podruhe by o vetev prisel.
	out[BTN_ENTRY] = "vstup +"
	if level.lane_count() > 0:
		var je: int = level.from_of(sel)
		if level.has_entry(je) and je > 0 and level.entries.size() > 1:
			out[BTN_ENTRY] = "vstup −"
	return out


# Hlaska, kdyz je deska plna. Hrac musi videt, PROC to nejde - "nejde to"
# ho necha zkouset to same dokola.
func _rows_status() -> String:
	return "na desku se víc drah nevejde (%d) — bonusy by se překrývaly" % level.rows_total()


# Zmena levelu se rovnou uklada lokalne. Neni to "ukladani pro hrace" - je to
# jen to, aby o praci neprisel. Nic se nikam neposila.
func _after_change() -> void:
	code = ""
	level.name = local_name
	level.save()


# ---------------------------------------------------------------- usek

# Zivel vybraneho useku. Cykli se pres vsechny ctyri a neutralni - hrac tak
# muze postavit treba dve useky stejneho zivlu, nebo naopak udelat mapu bez
# neutralniho useku (coz je tezsi, ale hratelne).
func _cycle_element() -> void:
	if level.lane_count() == 0:
		return
	var l: Dictionary = level.lanes[sel]
	var el: int = int(l["el"]) + 1
	if el > Element.COUNT - 1:
		el = Level.NEUTRAL
	l["el"] = el
	level.lanes[sel] = l
	level.relayout()
	if el == Level.NEUTRAL:
		status = "úsek %d: neutrální" % (sel + 1)
	else:
		status = "úsek %d: %s" % [sel + 1, Element.name_of(el)]
	_after_change()


# CIL vybraneho useku: vystup, nebo VYHYBKA. Takhle se useky SPOJUJI (dva
# useky do stejne vyhybky) i ROZDELUJI (vyhybka ma vic vetvi nez puvodni
# jedna cesta). Preskakuji se cile, ktere by vyrobily smycku.
func _cycle_target() -> void:
	if level.lane_count() == 0:
		return
	if not level.cycle_target(sel):
		status = "jiný cíl pro tenhle úsek není"
		return
	level.relayout()
	# NAPOVEDA, CO BUDE NASLEDOVAT. Bez ni se k napojeni dvou useku (dve cesty
	# se sliji v jednu, "vidlicka") dostane jen ten, kdo vi, ze za vystupy
	# cyklus pokracuje dal - a to je presne otazka "jak se dve cesty spoji".
	status = "úsek %d: %s · další cíl: %s" % [sel + 1, _target_text(sel), _next_text(sel)]
	_after_change()


# Co bude nasledovat po dalsim klepnuti. Kdyz uz nic dalsiho neni, rekne to.
func _next_text(lane: int) -> String:
	var nxt: int = level.next_choice_index(lane)
	if nxt < 0:
		return "žádný"
	var c: Dictionary = level.target_choices(lane)[nxt]
	return level.choice_text(int(c["kind"]), int(c["to"]), int(c.get("node", -1)), lane)


# Popis cile vybraneho useku. Tri druhy cile - a hrac musi videt, ktery z nich
# to prave je, protoze se chovaji jinak.
func _target_text(lane: int) -> String:
	return level.choice_text(level.target_kind(lane), level.to_of(lane),
		level.lane_node(lane), lane)


# ---------------------------------------------------------------- kmen

# KMEN (VSTUP). Kazda vyhybka muze mit vlastni kmen, kterym do mapy vchazeji
# poutnici. Kdyz jich je vic, hrac hlida vic front najednou - a mapa vypada
# jako sit s vic vstupy, ne jen jedna cesta zleva.
#
# POZOR NA PORADI: kdyz je vybrany kmen uz existujici vetve, tlacitko se jmenuje
# "vstup −" a vstup se odebere. Kdyz je vybrany kmen KORENOVY (vyhybka 0), vzit
# se neda - a tlacitko v tu chvili rovnou pridava dalsi vetev. Driv se v tom
# pripade hrac zasekl: druhy stisk mu vetev zase vzal a vypadalo to, ze vstup
# pridat nejde.
func _entry() -> void:
	if level.lane_count() == 0:
		return
	var j: int = level.from_of(sel)
	if level.has_entry(j) and j > 0 and level.entries.size() > 1:
		if level.remove_entry(j):
			status = "výhybka %d přišla o svůj kmen" % (j + 1)
			_after_change()
		else:
			status = "tenhle kmen odebrat nejde"
		return
	if not level.has_entry(j) and level.add_entry(j):
		status = "výhybka %d má vlastní kmen (vstup zleva)" % (j + 1)
		_after_change()
		return
	# Do vyhybky, do ktere uz vede usek, kmen pridat nejde - vede z leveho
	# okraje a sel by pres vsechno pred ni. Zalozime tedy CELOU NOVOU VETEV,
	# ktera ma vlastni kmen: mapa tak dostane druhy vstup.
	# VYBER ZUSTAVA TAM, KDE BYL. Kdyby se presunul do nove vetve, ukazovalo by
	# tlacitko "vstup −" a druhy stisk by vetev zase vzal.
	var keep: Level = level.clone()
	var j2: int = level.add_tree()
	if j2 >= 0:
		if not level.rows_fit():
			level = keep
			status = _rows_status()
			return
		status = "nová větev s vlastním kmenem (výhybka %d)" % (j2 + 1)
		_after_change()
		return
	if level.junctions.size() >= Level.MAX_ENTRIES:
		status = "poslední kmen nechat musíš"
	else:
		status = _rows_status()


# NOVY CIL. Cile (diry, kam poutnici dochazeji) se v mape neobjevuji samy -
# hrac si je pridava timhle tlacitkem, kdyz pro ne ma duvod. Novy cil se
# rovnou pripoji vybranemu useku: hrac ho nepridava do prazdna, ale proto, ze
# tenhle usek ma koncit jinde.
func _add_exit() -> void:
	if level.lane_count() == 0:
		return
	if level.exits.size() >= Level.MAX_EXITS:
		status = "víc než %d cílů nejde" % Level.MAX_EXITS
		return
	var keep: Level = level.clone()
	var idx: int = level.add_exit()
	if idx < 0:
		status = "nový cíl se nepodařilo přidat"
		return
	var l: Dictionary = level.lanes[sel]
	l["kind"] = Level.TO_EXIT
	l["to"] = idx
	level.lanes[sel] = l
	level.relayout()
	# Cil je dira na vlastnim radku mrizky - kdyz se radek uz nevejde, zmena
	# se vrati (stejna mez, jako kdyz hrac pridava drahu).
	if not level.rows_fit():
		level = keep
		status = _rows_status()
		return
	status = "nový cíl %d — úsek %d do něj ústí" % [idx + 1, sel + 1]
	_after_change()


# ZRUSENI CILE RUKOU. Dve situace, jedna hlaska:
#   * vybrany usek do nejakeho cile vede - maze se TEN cil (a useky, ktere do
#     nej vedly, se prepoji na jiny cil; hrac to vidi v hlasce),
#   * vybrany usek do zadneho cile nevede - maze se cil, do ktereho nevede nic
#     (takový zustava po prepojeni useku jinam a jinak by ho nešlo zrusit).
func _exit_minus() -> void:
	if level.lane_count() == 0:
		return
	var e: int = level.exit_of(sel)
	if e >= 0:
		var res: Dictionary = level.remove_exit_forced(e)
		if not bool(res["ok"]):
			status = "poslední cíl nechat musíš — jinak by nebylo kam dojít"
			return
		var moved: Array = res["moved"]
		if moved.is_empty():
			status = "cíl %d zrušen" % (e + 1)
		else:
			var parts: Array = []
			for m in moved:
				var pair: Array = m
				parts.append("%d→%d" % [int(pair[0]) + 1, int(pair[1]) + 1])
			status = "cíl %d zrušen · úseky se přepojily: %s" % [e + 1, ", ".join(parts)]
		_after_change()
		return
	var free: int = level.unused_exit()
	if free < 0:
		status = "vybraný úsek nevede do cíle a volný cíl žádný není"
		return
	level.remove_exit(free)
	status = "zrušen cíl %d, do kterého nic nevedlo" % (free + 1)
	_after_change()


# Kde se usek ohne ke svemu cili. Mensi hodnota = ohne driv (bliz k vyhybce),
# vetsi = jde dele rovne. Diky tomu se daji dve useky sbihat do jednoho
# vystupu, nebo se naopak rozejit hned na zacatku.
func _bend(d: float) -> void:
	if level.lane_count() == 0:
		return
	var l: Dictionary = level.lanes[sel]
	var old: float = float(l.get("divert", Level.BASE_DIVERT))
	var v: float = clampf(old + d, 0.0, 0.98)
	var before: Array = level.validate()
	var keep: Level = level.clone()
	l["divert"] = v
	level.lanes[sel] = l
	level.relayout()
	# OHNUTI NESMI ROZBIT NAPOJENI. Uzel, do ktereho se vetev vleva, musi lezet
	# na ROVNEM useku ciloveho useku; kdyz se usek ohne driv, nez kde uzel lezi,
	# vetev by se vlekla do oblouku a level by se prestal dat vyexportovat.
	# Zmena se proto vrati a hrac dostane hlasku - ticho by bylo horsi.
	if before.is_empty() and not level.validate().is_empty():
		level = keep
		status = "takhle ohnutý úsek by rozbil napojení — odbočení zůstává %.2f" % level.divert_of(sel)
		return
	status = "úsek %d: odbočení %.2f" % [sel + 1, v]
	_after_change()


# ---------------------------------------------------------------- vyhybka

# ROZDELENI: vybrany usek prestane koncit ve vystupu a konci v nove vyhybce,
# ze ktere vedou dve vetve. Prvni pokracuje tam, kam vedl puvodni usek (a nese
# jeho zivel), druha vede do noveho vystupu.
func can_split() -> bool:
	if level.lane_count() == 0 or sel < 0 or sel >= level.lane_count():
		return false
	if level.target_kind(sel) != Level.TO_EXIT:
		return false
	if level.junction_depth(level.from_of(sel)) + 1 > Level.MAX_DEPTH:
		return false
	if level.lane_count() + 2 > Level.MAX_LANES:
		return false
	return true


# SLITI: vybrany usek vede do vyhybky, do ktere vede sam a jeji vetve konci
# ve vystupech. Usek se prepoji na prvni z nich a vyhybka zmizi.
func can_merge() -> bool:
	if level.lane_count() == 0 or sel < 0 or sel >= level.lane_count():
		return false
	var j: int = level.junction_of(sel)
	if j < 0:
		return false
	if level.lanes_into(j).size() != 1:
		return false
	var kids: Array = level.lanes_of(j)
	if kids.is_empty():
		return false
	for k in kids:
		if level.target_kind(k) != Level.TO_EXIT:
			return false
	return true


func _junction() -> void:
	if can_split():
		var n0: int = level.lane_count()
		var keep: Level = level.clone()
		var j: int = level.split_lane(sel)
		if j < 0:
			status = "výhybku tady udělat nejde"
			return
		# Rozdelenim vznikne o radek vic - kdyz uz se nevejde, zmena se vrati.
		if not level.rows_fit():
			level = keep
			status = _rows_status()
			return
		# Vyber prvni novou vetev - hrac hned vidi, co ma upravit.
		sel = mini(n0, level.lane_count() - 1)
		status = "úsek %d se rozdělil výhybkou %d" % [sel, j + 1]
		_after_change()
		return
	if can_merge():
		var j2: int = level.junction_of(sel)
		if level.merge_lane(sel):
			status = "výhybka %d se slila zpět do úseku %d" % [j2 + 1, sel + 1]
			_after_change()
			return
	if level.lane_count() > 0 and not level.lane_is_exit(sel):
		status = "do té výhybky vede víc úseků, nedá se zrušit"
	elif level.lane_count() + 2 > Level.MAX_LANES:
		status = "víc než %d úseků nejde" % Level.MAX_LANES
	elif level.junction_depth(level.from_of(sel)) + 1 > Level.MAX_DEPTH:
		status = "dál už by výhybka neměla místo na bonusy"
	else:
		status = "z výhybky nejde udělat další"


# ---------------------------------------------------------------- seznam

func open_list() -> void:
	mode = MODE_LIST
	list_page = 0
	status = ""


func close_list() -> void:
	mode = MODE_EDIT


func is_list() -> bool:
	return mode == MODE_LIST


# Radky seznamu, ktere se vejdou na displej. Prvni je vzdy "novy level",
# posledni "zpet"; mezi tim stranka levelu a pripadne listovani.
func list_items(rows: int) -> Array:
	var per: int = maxi(rows - 4, 1)
	var names: Array = Level.saved_names()
	names.reverse()
	var pages: int = maxi(int(ceil(float(names.size()) / float(per))), 1)
	list_page = clampi(list_page, 0, pages - 1)
	var out: Array = []
	out.append({"kind": "new", "name": "+ " + Level.next_free_name()})
	var start: int = list_page * per
	for i in range(start, mini(start + per, names.size())):
		out.append({"kind": "level", "name": str(names[i])})
	if names.size() > per:
		if list_page + 1 < pages:
			out.append({"kind": "more", "name": "▸ další úrovně"})
		if list_page > 0:
			out.append({"kind": "older", "name": "◂ předchozí"})
	out.append({"kind": "back", "name": "zpět do editoru"})
	return out


# Klepnuti na radek seznamu.
func pick(item: Dictionary) -> void:
	match str(item.get("kind", "")):
		"new":
			reset()
			status = "nový level: " + local_name
		"level":
			load_named(str(item.get("name", "")))
		"more":
			list_page += 1
		"older":
			list_page -= 1
		"back":
			close_list()


# Popis vybraneho useku. Kresli se do HUDu editoru - deska sama zustava bez
# textu jako ve hre.
func sel_text() -> String:
	if level.lane_count() == 0:
		return "žádný úsek"
	_clamp_sel()
	var el: int = level.el_of(sel)
	var el_name: String = "neutrální" if el == Level.NEUTRAL else Element.name_of(el)
	var target: String
	if level.target_kind(sel) == Level.TO_EXIT:
		target = "výstup %d" % (level.exit_of(sel) + 1)
	elif level.target_kind(sel) == Level.TO_JUNCTION:
		target = "→ výhybka %d" % (level.junction_of(sel) + 1)
	else:
		# U NAPOJENI SE REKNE I UZEL: do jednoho useku se da vlit na vic
		# mistech a bez uzlu by hrac nevidel, ktery z nich to je.
		var t: int = level.lane_target_of(sel)
		if level.node_choice_count(sel, t) > 1:
			target = "→ úsek %d · %s" % [t + 1, level.node_name(level.lane_node(sel))]
		else:
			target = "→ úsek %d" % (t + 1)
	return "úsek %d/%d · z výhybky %d · %s · %s · odbočení %.2f" % [
		sel + 1, level.lane_count(), level.from_of(sel) + 1, el_name, target,
		level.divert_of(sel)]


# EXPORT. Vysledek je jednoradkovy KOD, ktery se vejde do Telegramu, a
# k tomu soubor (ve webu se stahne, na desktopu se zapise do user://export).
# Kod je to, co mi Jan posle; soubor je pro pripad, ze si level chce nechat.
func _export() -> void:
	var errs: Array = level.validate()
	if not errs.is_empty():
		status = "nevyexportováno: " + str(errs[0])
		return
	if level.name.is_empty() or level.name == Level.DEFAULT_NAME:
		level.name = local_name
	code = level.to_code()
	var where: String = level.export_to_file()
	if where.is_empty():
		status = "kód je níže, soubor se nepodařilo uložit"
	else:
		status = "export: " + where


# Co je k dispozici k nacteni: zakotvene levely ve hre + lokalne ulozene.
# Jmena se needuplikuji - zakotveny level ma prednost, protoze ten se
# neztrati smazanim cache.
func available_levels() -> Array:
	var out: Array = []
	var seen := {}
	for item in BuiltinLevels.LEVELS:
		var d: Dictionary = item
		var n: String = str(d.get("name", ""))
		if n.is_empty() or seen.has(n):
			continue
		seen[n] = true
		out.append(n)
	for n2 in Level.saved_names():
		if not seen.has(str(n2)):
			seen[n2] = true
			out.append(str(n2))
	return out
