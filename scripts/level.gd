class_name Level
extends RefCounted

# LEVEL. Jedno jezero dat: useky (lanes), jejich elementy, VYHYBKY (junctions),
# vystupy a obtiznost. Hra, testy i EDITOR pracuji s timhle jedinym objektem
# a Network z nej postavi geometrii.
#
# SOURADNICE JSOU NORMALIZOVANE (0..1 v ose hraci plochy), takze level se sam
# roztahne na displej hrace - a stejny level vypada na telefonu i na monitoru.
#
# Kdyz level chybi, pouzije se ZAKLADNI DESKA (base()) - presne ta, na ktere
# je hra vyladena. Je to jen level mezi ostatnimi, zadna vyjimka v kodu.
#
# ---------------------------------------------------------------- TOPOLOGIE
# Kmen vede do KORENOVE VYHYBKY (junction 0). Kazdy usek z ni vede bud do
# VYSTUPU (to >= 0) nebo do dalsi VYHYBKY (to < 0, viz target encoding nize).
# Z dalsi vyhybky vedou useky uz jen do vystupu - hloubka je omezena
# (MAX_DEPTH), protoze mezi vyhybkou a vystupem musi zustat misto na rovny
# usek, na kterem stoji bonusy.
#
# VYHYBKA JE VZDY CELY VENTILATOR: hrac na ni klepne (klepnutim na usek, ktery
# z ni vede) a dalsi poutnik po ni pujde. Vic vyhybek = vic nezavislych voleb,
# kazda se prepina tim usekem, ktery pod ni vede - proto zadna tlacitka.
#
# ZADNA GEOMETRIE SE V LEVELU NEDRZI. Radky, hloubky i souradnice vyhybek
# pocita relayout() - kdyby si je level drzel, rozejdou se s tim, co kresli
# Network, a ulozeny level by nebyl ten, ktery hrac videl.

const NEUTRAL := -1
const DEFAULT_NAME := "vlastni"
# NEJMENSI ROZESTUP DRAH, pri kterem se bonusy na sousednich drahach jeste
# neprekryvaji. Tohle je SKUTECNY strop levelu - pocet useku ani vyhybek sam
# o sobe nic neomezuje, omezuje mrizka radku. Zmereno na nejmensi podporovane
# obrazovce (640x360): pri 10 radcich je mezera 31 px a potreba 28 px,
# jedenacty radek uz test rozvrzeni na vsech 14 rozlisenich odmita.
const MIN_ROW_GAP := 0.095
# Kolik useku muze level mit. NENI to hranice hratelnosti (tu drzi MIN_ROW_GAP
# vyskovym mistem), je to jen pojistka pro cykly a pro to, aby se kod levelu
# vešel do jedne rady Telegramu.
const MAX_LANES := 24
const MIN_LANES := 2
# Kolik useku muze vest z jedne vyhybky. Vic nez se vejde radku na desku nema
# kam - druha hranice je stejne MIN_ROW_GAP.
const MAX_FAN := 10
const MAX_EXITS := 24
# Kolik kmenu (vstupu) muze do mapy vest. Kazdy kmen je jedna cesta, po ktere
# poutnici do mapy vchazeji - vic kmenu znamena, ze hrac musi hlidat vic míst
# najednou. Kazdy vlastni kmen si bere dva radky, takze driv nez tady zastavi
# hrace plna deska.
const MAX_ENTRIES := 8
# Hloubka vyhybek. 0 = korenova, 1 = vyhybka na konci useku. Hloubka 2 by se
# do mrizky jeste vesla, ale rovny usek za ni by mel jen 0.121 - presne na
# hranici MIN_RUN, tedy bez rezervy na bonusy. Zustava proto 1 (a test to
# hlida: "z vetve druhe vyhybky uz treti vest nesmi").
const MAX_DEPTH := 1

# CIL USEKU. Usek muze vest do vystupu, do dalsi vyhybky, nebo se NAPOJIT NA
# JINY USEK (vetev se do druhe vetve vleje a poutnik po ni pokracuje dal).
const TO_EXIT := 0
const TO_JUNCTION := 1
const TO_LANE := 2

# Pas, do ktereho se mrizka radek rozmistuje. Nahore je HUD, dole okraj
# displeje; mezi tim se radky VYSTREDI - kdyz je jich min, drzi se u sebe ve
# stredu, a kdyz vic, mezera se zmensi. Diky tomu se prida usek, aniz by se
# vsechny ostatni posunuly.
const TOP := 0.03
const BOTTOM := 0.93

# --- ZAKLADNI DESKA -------------------------------------------------------
# Vsechno, co bylo driv natvrdo v Network. Je to zakladni level a zaroven
# zakladni deska balancu: na ni se ladi hratelnost, ne na novych levelech.
const BASE_LANE_ELEMENTS := [0, 1, 2, 3, NEUTRAL]
const BASE_EXITS := [0, 0, 1, 2, 3]
# Rozestup pruhu. Byl 0.175; Jan chtel mezi useky vic mista, proto 0.22.
const BASE_SPREAD := 0.22
const BASE_EXIT_X := 0.945
const BASE_DIVERT := 0.80

# KORENOVA VYHYBKA a krok hloubky. Kazda dalsi vyhybka stoji o krok dal od
# kraje, aby jeji useky mely pred vystupy misto na rovny usek.
const BASE_JUNCTION_X := 0.25
const DEPTH_DX := 0.24
# Vzdalenost stredu ventilatoru od bodu, kde konci privodni usek. Kresli se
# z toho "kratky kmen" uvnitr vyhybky.
const MERGE_GAP := 0.03

# Podil drahy, ktery zustava PRED rovným usekem a ZA nim. 0.22 z rozpeti
# 0.25..0.945 da presne pas 0.40..0.80 zakladni desky, na ktere je hra
# vyladena. Usek, ktery vede do dalsi vyhybky, je kratky - bere se skoro cely,
# aby se na nem bonusy nemačkaly (0.06).
# Podil delky rovneho useku, kde se ohne ke svemu cili.
const RUN_FRAC := 0.22
const RUN_FRAC_CONNECTOR := 0.06
# UZLY USEKU. Kde presne se muze privodni vetev vlit do druheho useku: ne na
# jeho zacatek, ale v nekolika bodech jeho rovneho useku. Kazdy usek ma
# NODE_COUNT uzlu a hrac u napojeni vybira nejen KAM se vetev vleje, ale i
# VE KTEREM UZLU - do jednoho useku se tak muze vlit vic vetvi, kazda jinam.
#
# Driv tu byl JEDEN bod (LAND_FRAC 0.30). Kdyz mel hrac pro vetev jedny dvere,
# nemel jak resit, ze se do stejneho useku vleva vic vetvi: vsechny se slily
# v jednom bode a rozdelit je neslo.
#
# Uzel MUSI lezet na ROVNEM useku ciloveho useku (za jeho zatackou uz rovny
# usek neni a vetev by se vlekla do oblouku) - hlida to can_target pres
# bend_x(). Kvuli tomu je prvni uzel 0.30 a posledni 0.74: vychozi odboceni je
# 0.80, takze vsechny tri uzly lezi na rovine.
# prvni uzel (0.30) je presne tam, kde byval jediny bod napojeni; kdo ho ma
# v kodu, chova se znak po znaku jako driv
const NODE_FRACS := [0.30, 0.52, 0.74]
const NODE_COUNT := 3
# Nejmensi rovny usek, na ktery se jeste vejdou tri bonusy vedle sebe.
const MIN_RUN := 0.12

# Obtiznost. Cisla jsou zakladni deska; level si je muze prepsat.
const BASE_ZONE_DMG := 30.0
const BASE_SPEED := 52.0
# Mezera mezi poutniky v sekundach. Byla 1.05, pak 1.35; Jan chtel jeste vic
# mista ("o dost větší"), proto 1.9 (52 px/s * 1.9 = 99 px mezi poutniky).
const BASE_SPAWN := 1.9
const BASE_LIVES := 12
const BASE_GOLD := 260

# Krok, o ktery se hybou rucky v editoru.
const SPREAD_STEP := 0.01
const ZONE_STEP := 2.0
const SPEED_STEP := 2.0
const SPAWN_STEP := 0.05
const DIVERTS := [0.62, 0.72, 0.80, 0.88]

var name: String = DEFAULT_NAME
# Useky. Kazdy je slovnik:
#   from   - z ktere vyhybky vede (index do junctions)
#   el     - element (0..3) nebo NEUTRAL (-1)
#   kind   - kam vede: TO_EXIT / TO_JUNCTION / TO_LANE
#   to     - index vystupu, vyhybky, nebo jineho useku (podle `kind`)
#   divert - podil delky rovneho useku, kde se usek ohne ke svemu cili
var lanes: Array = []
# Vyhybky. Kazda je jen "ventilator" - seznam jejich useku se pocita z lanes
# (kdo ma from == index). Vlastni stav (ktera vetev je vybrana) drzi az hra:
# je to stav rozehrane partie, ne level.
var junctions: Array = []
# KMENY. Indexy vyhybek, do kterych vede VLASTNI kmen - tedy vstup do mapy.
# Kdyz jich je vic, poutnici vchazeji na vic mist a hrac musi hlidat vic
# front najednou. Kazdy kmen je vodorovna cara z leveho okraje.
var entries: Array = []
# Vystupy z mapy. Normalizovane souradnice [x, y]. Vystup je dira v mape -
# nema element a nikdo ho "nevlastni".
var exits: Array = []
var spread: float = BASE_SPREAD
var exit_x: float = BASE_EXIT_X
var zone_dmg: float = BASE_ZONE_DMG
var speed: float = BASE_SPEED
var spawn: float = BASE_SPAWN
var lives: int = BASE_LIVES
var gold: int = BASE_GOLD

# Vypoctena geometrie. NENI soucasti levelu - pocita ji relayout() a do
# souboru se neuklada.
# POZOR: useky a vyhybky maji kazde svuj slovnik rozpeti. Kdyby sdilely jeden,
# prekryl by se usek 0 s vyhybkou 0 (oba maji index 0) - a prvni usek by se
# prekreslil doprostred mrizky.
var _row: Dictionary = {}      # usek -> normalizovana y rovneho useku
var _jrow: Dictionary = {}     # vyhybka -> normalizovana y stredu ventilatoru
var _span: Dictionary = {}     # usek -> [prvni radek, posledni radek]
var _jspan: Dictionary = {}    # vyhybka -> [prvni radek, posledni radek]
var _rows_total: int = 0
# Radky cele mrizky: drahy i cile. Kazdy cil je dira na svem radku, takze
# kdyz je cilu vic nez drah, mrizka ma vic radku nez kolik je drah.
var _grid_rows: int = 0
# Skutecna mezera radku po relayoutu. Neni to `spread`: kdyz se radky nevejdou,
# zmensi se VSEM stejne - a prave tahle mezera rozhoduje o tom, jestli se
# bonusy na sousednich drahach neprekryvaji (MIN_ROW_GAP).
var _gap: float = BASE_SPREAD


# ---------------------------------------------------------------- useky

func lane_count() -> int:
	return lanes.size()


func el_of(lane: int) -> int:
	var l: Dictionary = lanes[lane]
	return int(l["el"])


# Kam usek vede. Druh cile je v `kind` - proto se da zamerit i na JINY USEK
# (vetev se vleje do druhe vetve), ne jen do vystupu nebo vyhybky.
func target_kind(lane: int) -> int:
	var l: Dictionary = lanes[lane]
	if l.has("kind"):
		return int(l["kind"])
	# Starsi kody "kind" nemely: >= 0 byl vzdy vystup a < 0 vyhybka.
	return TO_EXIT if int(l["to"]) >= 0 else TO_JUNCTION


func to_of(lane: int) -> int:
	var l: Dictionary = lanes[lane]
	return int(l["to"])


func from_of(lane: int) -> int:
	var l: Dictionary = lanes[lane]
	return int(l.get("from", 0))


func lane_is_exit(lane: int) -> bool:
	return target_kind(lane) == TO_EXIT


# Vystup, do ktereho usek usti. -1, kdyz vede jinam.
func exit_of(lane: int) -> int:
	return to_of(lane) if lane_is_exit(lane) else -1


# Vyhybka, do ktere usek vede. -1, kdyz vede jinam.
func junction_of(lane: int) -> int:
	return to_of(lane) if target_kind(lane) == TO_JUNCTION else -1


# Usek, na ktery se tenhle usek napojuje. -1, kdyz vede jinam.
func lane_target_of(lane: int) -> int:
	return to_of(lane) if target_kind(lane) == TO_LANE else -1


# UZEL, DO KTEREHO SE TENHLE USEK NAPOJUJE. Ma vyznam jen u napojeni
# (TO_LANE) - jinde se neuklada a neposila do kodu. Uzel je poradi diraveho
# bodu na cilovem useku (viz NODE_FRACS).
func lane_node(lane: int) -> int:
	var l: Dictionary = lanes[lane]
	return clampi(int(l.get("node", 0)), 0, NODE_COUNT - 1)


func node_frac(node: int) -> float:
	return float(NODE_FRACS[clampi(node, 0, NODE_COUNT - 1)])


func node_name(node: int) -> String:
	return "uzel %d/%d" % [clampi(node, 0, NODE_COUNT - 1) + 1, NODE_COUNT]


func is_neutral(lane: int) -> bool:
	return el_of(lane) == NEUTRAL


# Na neutralni usek nema smysl stavet - uz bere vsem stejne.
func accepts(lane: int, element: int) -> bool:
	if is_neutral(lane):
		return false
	return element == el_of(lane)


# Sirka useku v podilu delky rovneho useku, kde se ohne ke svemu cili.
func divert_of(lane: int) -> float:
	var l: Dictionary = lanes[lane]
	return float(l.get("divert", BASE_DIVERT))


# ---------------------------------------------------------------- vyhybky

func junction_count() -> int:
	return junctions.size()


# Useky, ktere vedou Z te vyhybky - v poradi, v jakem jsou pod sebou.
func lanes_of(j: int) -> Array:
	var out: Array = []
	for i in range(lanes.size()):
		if from_of(i) == j:
			out.append(i)
	return out


# Hloubka vyhybky: 0 = korenova (kmen), 1 = na konci useku, ... Vyhybka, do
# ktere vede vlastni kmen, je VZDY korenova: jeji vstup je z leveho okraje,
# ne z jine vyhybky.
func junction_depth(j: int) -> int:
	if has_entry(j):
		return 0
	var d := 0
	var guard := 0
	var cur := j
	while cur > 0 and guard < 16:
		var parent := -1
		for i in range(lanes.size()):
			if junction_of(i) == cur:
				parent = from_of(i)
				break
		if parent < 0:
			break
		d += 1
		# Vyhybka s vlastnim kmenem je korenova (hloubka 0), takze dite je
		# o jedna hlubsi a dal se uz nahoru nechodi.
		if has_entry(parent) or parent == cur:
			break
		cur = parent
		guard += 1
	return d


# ---------------------------------------------------------------- kmeny

func has_entry(j: int) -> bool:
	for e in entries:
		if int(e) == j:
			return true
	return false


func add_entry(j: int) -> bool:
	if j < 0 or j >= junctions.size():
		return false
	if has_entry(j):
		return false
	if entries.size() >= MAX_ENTRIES:
		return false
	# Do vyhybky, do ktere uz vede usek, vlastni kmen pridat nelze: kmen vede
	# z leveho okraje a sel by pres vsechno, co je pred tou vyhybkou.
	if not lanes_into(j).is_empty():
		return false
	entries.append(j)
	relayout()
	return true


# NOVA SAMOSTATNA VETEV S VLASTNIM KMENEM. To je jedina cesta, jak udelat mapu
# s druhym vstupem: nova vyhybka, ktera nikam nenavazuje, dostane vlastni kmen
# a dva nove useky do vystupu. Kdyby se kmen jen "pripnul" k existujici
# vyhybce, vedl by pres cely obrazek a krizil, co je pred ni.
func add_tree() -> int:
	if lanes.size() + 2 > MAX_LANES:
		return -1
	if junctions.size() >= MAX_ENTRIES:
		return -1
	var j: int = junctions.size()
	junctions.append({})
	# Cile se nevyrabi: obe vetve noveho kmene konci v nekterem z EXISTUJICICH
	# cilu. Novy cil si hrac prida sam, kdyz ho chce.
	var e1: int = free_exit()
	lanes.append({"from": j, "el": _free_element(), "kind": TO_EXIT, "to": e1,
		"divert": BASE_DIVERT})
	var e2: int = free_exit(e1)
	lanes.append({"from": j, "el": _free_element(), "kind": TO_EXIT, "to": e2,
		"divert": BASE_DIVERT})
	entries.append(j)
	relayout()
	return j


func remove_entry(j: int) -> bool:
	if entries.size() <= 1:
		return false
	# Prvni kmen zustava: je to hlavni vstup mapy a jeho smazanim by zmizela
	# i cela zakladni deska. Odebrat se da jen kmen, ktery hrac pridal.
	if j <= 0:
		return false
	var at: int = entries.find(j)
	if at < 0:
		return false
	entries.remove_at(at)
	if lanes_into(j).is_empty() and not lanes_of(j).is_empty():
		# Vetev, ktera ma jen svuj kmen, je bez nej nedostizna - zmizi cely
		# strom (vyhybka i jeji useky).
		_drop_junction(j)
	else:
		relayout()
	return true


func junction_row(j: int) -> float:
	return float(_jrow.get(j, TOP))


func junction_x(j: int) -> float:
	return clampf(BASE_JUNCTION_X + float(junction_depth(j)) * DEPTH_DX, BASE_JUNCTION_X, 0.86)


# Vystup, ktery nema zadny usek. Pouziva se pri pridavani useku - novy usek
# ma jit nekam, kde jeste nikdo neni.
func _exit_used(idx: int) -> bool:
	return _exit_uses(idx) > 0


# Kolik useku do toho vystupu usti.
func _exit_uses(idx: int) -> int:
	var n := 0
	for i in range(lanes.size()):
		if exit_of(i) == idx:
			n += 1
	return n


# VYSTUPY SE NEPRIDAVAJI SAMY. Level si je drzi jako zdroj, ktery hrac
# spravuje rucne ("cíl +"). Kdyz je kazda nova cesta vyrabela sama, mel hrac
# v mape cile, ktere nezadal - a cyklus "cíl" se prodluzoval, takze se k
# napojovani dvou useku skoro nedostal.
# Novy vystup dostane vlastni radek mrizky (viz relayout), aby se dve diry
# nekreslily pres sebe.
func add_exit() -> int:
	if exits.size() >= MAX_EXITS:
		return -1
	exits.append([exit_x, TOP])
	relayout()
	return exits.size() - 1


# ZRUSENI CILE. Pouziva se, kdyz mizi CESTA: kdyz je cesta smazana a do
# jejiho cile uz nic nevede, cil zmizi s ni. Rucne pridany cil (tlacitkem
# "cíl +") zustava - ten si hrac hlida sam a muze docasne zustat bez cesty,
# dokud ho nejaka cesta nepouzije.
# Indexy vystupu se posunou, proto se vsechny odkazy na ne premapuji: jinak
# by nejaky usek mířil na cil, ktery uz neexistuje.
func remove_exit(idx: int) -> bool:
	if idx < 0 or idx >= exits.size():
		return false
	if exits.size() <= 1:
		return false
	if _exit_uses(idx) > 0:
		return false
	exits.remove_at(idx)
	for i in range(lanes.size()):
		if target_kind(i) == TO_EXIT and to_of(i) > idx:
			var l: Dictionary = lanes[i]
			l["to"] = to_of(i) - 1
			lanes[i] = l
	relayout()
	return true


# Nejnizsi (a tedy nejdriv kresleny) cil, do ktereho nic nevede. -1, kdyz
# takovy neni. Pouziva ho rucni mazani cile: kdyz vybrany usek do zadneho
# cile nevede, maze se cil, ktery nikdo nepouziva.
func unused_exit() -> int:
	var best: int = -1
	for i in range(exits.size()):
		if _exit_uses(i) == 0:
			best = i
			break
	return best


# RUCNI ZRUSENI CILE. Jan: "cíle stále po smazání úseku nemizí. Přidáme tedy
# možnost smazat cíl ručně." Automatika (remove_exit) maze jen cil, do
# ktereho po smazane ceste nic nevede - a to je spravne: hrac nesmi prijit
# o cil, ktery jeste pouziva. Rucni mazani je VEDOME rozhodnuti, takze maze
# i cil, do ktereho jeste neco vede: useky, ktere do nej vedly, se prepoji na
# jiny (volny) cil. Cisla useku se nemene, takze se prepojuje jen "to".
#
# Vraci {"ok": bool, "moved": [[usek, novy cil], ...]} - editor z toho dela
# hlasku, aby hrac videl, co se stalo s cestami, ktere o cil prisly.
func remove_exit_forced(idx: int) -> Dictionary:
	var out := {"ok": false, "moved": []}
	if idx < 0 or idx >= exits.size() or exits.size() <= 1:
		return out
	var users: Array = []
	for i in range(lanes.size()):
		if exit_of(i) == idx:
			users.append(i)
	exits.remove_at(idx)
	for i in range(lanes.size()):
		if target_kind(i) == TO_EXIT and to_of(i) > idx:
			var l: Dictionary = lanes[i]
			l["to"] = to_of(i) - 1
			lanes[i] = l
	# Prepojeni az PO premapovani: teprve ted je videt, ktere cile jsou volne.
	for u in users:
		var ui: int = int(u)
		var l2: Dictionary = lanes[ui]
		l2["kind"] = TO_EXIT
		l2.erase("node")
		l2["to"] = free_exit()
		lanes[ui] = l2
		out["moved"].append([ui, int(l2["to"])])
	out["ok"] = true
	relayout()
	return out


# Volny vystup pro novy usek: prednostne takovy, do ktereho nic neusta; kdyz
# jsou vsechny obsazene, tak ten s nejmensim poctem useku (aby se cesty
# nehrnuly vsechny do posledniho). `avoid` se pouzije, kdyz usek potrebuje
# cil JINY, nez ma jeho sourozenec - jinak by obe vetve vedly do stejne diry
# a vyhybka by nic nerozhodovala.
func free_exit(avoid: int = -1) -> int:
	var best: int = -1
	var best_uses: int = 1 << 30
	for i in range(exits.size()):
		if i == avoid:
			continue
		var uses: int = _exit_uses(i)
		if uses == 0:
			return i
		if uses < best_uses:
			best_uses = uses
			best = i
	if best >= 0:
		return best
	return maxi(exits.size() - 1, 0)


# ---------------------------------------------------------------- zmeny

# Novy usek z dane vyhybky. Element se vybere tak, aby v mape nechybel
# zadny zivly (a neutralni az kdyz uz vsechny jsou) - nova kolej tak nikdy
# nerozbije matici zivlu.
func _free_element() -> int:
	var seen := {}
	for i in range(lanes.size()):
		seen[el_of(i)] = true
	for e in range(Element.COUNT):
		if not seen.has(e):
			return e
	return NEUTRAL


# ZIVLY, KTERE SE V TOMHLE LEVELU POSILAJI. Jan: "Když jsou na mapě jen úseky
# s vodou a ohněm, tak budou pouze vodní a ohniví nepřátelé."
#
# Neni to kosmetika: poutnik, na ktereho v mape neni protiklad, se neda zabit
# (vlastni zivel bere 0 %) a level by se nedal vyhrat. Dokud se posilaly
# vsechny ctyri zivly, byla pulka poutniku neporazitelna na kazde mape, ktera
# nemela vsechny ctyri useky.
#
# Neutralni usek sem nepatri: nema element, takze "neutralni poutnik" by
# nemel na cem dostat vic nez 100 %.
func spawn_elements() -> Array:
	var out: Array = []
	for i in range(lanes.size()):
		var e: int = el_of(i)
		if e != NEUTRAL and not out.has(e):
			out.append(e)
	out.sort()
	return out


func add_lane(from_j: int = 0) -> bool:
	if lanes.size() >= MAX_LANES:
		return false
	var j: int = clampi(from_j, 0, maxi(junctions.size() - 1, 0))
	if lanes_of(j).size() >= MAX_FAN:
		return false
	lanes.append({
		"from": j,
		"el": _free_element(),
		"to": free_exit(),
		"divert": BASE_DIVERT,
	})
	_ensure_junctions()
	relayout()
	return true


# Odebere usek. Cil, do ktereho uz po nem nic nevede, zmizi s nim - cesta
# i s cilem, kam vedla. Rucne pridany cil zustava (viz remove_exit).
# Kdyz po nem zustane prazdna vyhybka, odebere se i ta (jinak by v mape
# zustal ventilator, do ktereho nikdo nevede).
func remove_lane(at: int = -1) -> bool:
	if lanes.size() <= MIN_LANES:
		return false
	var i: int = at
	if i < 0:
		i = lanes.size() - 1
	if i < 0 or i >= lanes.size():
		return false
	var j: int = from_of(i)
	var gone_exit: int = exit_of(i)
	lanes.remove_at(i)
	# Cisla useku se posunula - odkazy "napojuje se na usek N" se musi posunout
	# s nimi, jinak by se vetev vleva do JINEHO useku, nez hrac videl.
	_shift_lane_refs(i)
	if gone_exit >= 0:
		remove_exit(gone_exit)
	if j > 0 and lanes_of(j).is_empty():
		_drop_junction(j)
	else:
		relayout()
	return true


# Po smazani useku `gone` se indexy ostatnich posunou. Kdo se na smazany usek
# napojoval, zustal by s cilem do prazdna - z toho se stane vystup.
func _shift_lane_refs(gone: int) -> void:
	for i in range(lanes.size()):
		if target_kind(i) != TO_LANE:
			continue
		var t: int = to_of(i)
		var l: Dictionary = lanes[i]
		if t == gone:
			l["kind"] = TO_EXIT
			l["to"] = free_exit()
			lanes[i] = l
		elif t > gone:
			l["to"] = t - 1
			lanes[i] = l
	_fix_lane_refs()


# ROZDĚLENÍ ÚSEKU. Vybrany usek prestane koncit ve vystupu a skonci v NOVE
# vyhybce; z te vedou dva useky - jeden pokracuje tam, kam vedl puvodni usek
# (a nese jeho element), druhy vede do noveho vystupu. Presne to je "rozdelit
# usek": hrac si vyrobi dalsi volbu na ceste, ktera dosud volbu nemela.
func split_lane(lane: int) -> int:
	if lane < 0 or lane >= lanes.size():
		return -1
	if not lane_is_exit(lane):
		return -1
	if junction_depth(from_of(lane)) + 1 > MAX_DEPTH:
		return -1
	if lanes.size() + 2 > MAX_LANES:
		return -1
	var j_new: int = junctions.size()
	var keep_el: int = el_of(lane)
	var keep_to: int = to_of(lane)
	var l: Dictionary = lanes[lane]
	l["kind"] = TO_JUNCTION
	l["to"] = j_new
	lanes[lane] = l
	# Druha vetev musi vest JINAM nez ta prvni - jinak by se hrac rozhodoval
	# mezi dvema cestami do stejne diry. Novy cil se pritom nevyrabi.
	var new_to: int = free_exit(keep_to)
	junctions.append({})
	lanes.append({"from": j_new, "el": keep_el, "kind": TO_EXIT, "to": keep_to, "divert": BASE_DIVERT})
	lanes.append({"from": j_new, "el": _free_element(), "kind": TO_EXIT, "to": new_to,
		"divert": BASE_DIVERT})
	relayout()
	return j_new


# SLITÍ ÚSEKU ZPĚT. Vybrany usek vede do vyhybky, do ktere vede sam a jeji
# useky konci ve vystupech: usek se prepoji na prvni z nich a vyhybka zmizi.
func merge_lane(lane: int) -> bool:
	if lane < 0 or lane >= lanes.size():
		return false
	var j: int = junction_of(lane)
	if j < 0:
		return false
	var incoming: Array = []
	for i in range(lanes.size()):
		if junction_of(i) == j:
			incoming.append(i)
	if incoming.size() != 1:
		return false
	var kids: Array = lanes_of(j)
	if kids.is_empty():
		return false
	for k in kids:
		if not lane_is_exit(k):
			return false
	var target: int = to_of(kids[0])
	var l: Dictionary = lanes[lane]
	l["kind"] = TO_EXIT
	l["to"] = target
	lanes[lane] = l
	_drop_junction(j)
	return true


# Zrusi vyhybku a vsechny jeji useky. Indexy ostatnich vyhybek i useku se
# posunou, proto se vsechny odkazy premapuji - jinak by nejaky usek mířil na
# neco, co uz neexistuje (a hra by spadla az za behu).
func _drop_junction(j: int) -> void:
	var kids: Array = lanes_of(j)
	kids.sort()
	# Cile, ktere s tou vetvi zmizi. Sesbiraji se PRED smazanim useku a na
	# konci se osirele cile zrusi - rucne pridane (nepouzite) zustavaji.
	var gone_exits: Array = []
	for k in kids:
		var e: int = exit_of(int(k))
		if e >= 0 and not gone_exits.has(e):
			gone_exits.append(e)
	# Stara -> nova cisla useku.
	var remap := {}
	var shift := 0
	for i in range(lanes.size()):
		if kids.has(i):
			shift += 1
			remap[i] = -1
		else:
			remap[i] = i - shift
	for k in range(kids.size() - 1, -1, -1):
		lanes.remove_at(int(kids[k]))
	junctions.remove_at(j)
	var new_entries: Array = []
	for e in entries:
		var ei: int = int(e)
		if ei == j:
			continue
		new_entries.append(ei - 1 if ei > j else ei)
	entries = new_entries
	if entries.is_empty():
		entries = [0]
	for i in range(lanes.size()):
		var l: Dictionary = lanes[i]
		var kind: int = int(l.get("kind", TO_EXIT))
		var to: int = int(l["to"])
		if kind == TO_JUNCTION:
			if to > j:
				l["to"] = to - 1
		elif kind == TO_LANE:
			# Cil je usek: bud se posune, nebo (kdyz zmizel) se z toho stane
			# vystup - neco rozumneho misto odkazu do prazdna.
			var new_to: int = int(remap.get(to, -1))
			if new_to < 0:
				l["kind"] = TO_EXIT
				l["to"] = clampi(to, 0, maxi(exits.size() - 1, 0))
			else:
				l["to"] = new_to
		var f: int = int(l.get("from", 0))
		if f > j:
			l["from"] = f - 1
		lanes[i] = l
	_fix_lane_refs()
	# Osirele cile te vetve zmizi. Indexy se posouvaji, proto az tady - vsechny
	# odkazy na vystupy uz jsou premapovane na nove indexy useku. Maze se od
	# nejvyssiho indexu, aby zbyvajici cisla zustala platna.
	gone_exits.sort()
	gone_exits.reverse()
	for e2 in gone_exits:
		remove_exit(int(e2))
	relayout()


# Po zruseni vyhybky (i jejich useku) se indexy useku posunou. Kazdy odkaz na
# usek, ktery uz neexistuje, se prevede na vystup - radsi neco rozumneho nez
# index mimo seznam.
func _fix_lane_refs() -> void:
	for i in range(lanes.size()):
		if target_kind(i) != TO_LANE:
			continue
		var t: int = int(lanes[i]["to"])
		if t < 0 or t >= lanes.size():
			var l: Dictionary = lanes[i]
			l["kind"] = TO_EXIT
			l["to"] = clampi(t, 0, maxi(exits.size() - 1, 0))
			lanes[i] = l


# CIL VYBRANEHO USEKU. Cykli se pres vsechny vystupy, pak pres ostatni useky
# (vetev se vleje do druhe vetve) a nakonec pres vyhybky. Tim se daji useky
# SPOJOVAT (dva useky do stejne vyhybky, nebo jeden na druhy) i ROZDELOVAT
# (vyhybka sama). Preskakuji se cile, ktere by vyrobily smycku, moc hlubokou
# vyhybku, nebo usek tak kratky, ze by se na nej nevesly bonusy.
#
# NAPOJENI MA VIC UZLU: kazdy pouzitelny uzel ciloveho useku je vlastni volba,
# takze se do jednoho useku da vlit na vic mistech. Kazda volba si nese i
# "node" - bez nej by se tri ruzna napojeni tvarila jako jedno a hrac by
# nemel jak vybrat, do ktereho uzlu ma vetev spadnout.
func target_choices(lane: int) -> Array:
	var out: Array = []
	for e in range(exits.size()):
		if can_target(lane, TO_EXIT, e):
			out.append({"kind": TO_EXIT, "to": e})
	for k in range(lanes.size()):
		for n in range(NODE_COUNT):
			if can_target(lane, TO_LANE, k, n):
				out.append({"kind": TO_LANE, "to": k, "node": n})
	for j in range(junctions.size()):
		if can_target(lane, TO_JUNCTION, j):
			out.append({"kind": TO_JUNCTION, "to": j})
	return out


# Popis cile lidsky. Tri druhy cile se chovaji jinak, takze hrac musi videt,
# ktery z nich to je - a rika se to na JEDNOM miste (editor i hlaska).
# U napojeni se rekne i uzel: kdyz jich je vic, hrac vidi, ktery z nich to je
# a kolik jich jeste ma ("uzel 2/3").
func choice_text(kind: int, to: int, node: int = -1, lane: int = -1) -> String:
	if kind == TO_EXIT:
		return "ústí do výstupu %d" % (to + 1)
	if kind == TO_JUNCTION:
		return "vede do výhybky %d" % (to + 1)
	var n: int = clampi(node if node >= 0 else 0, 0, NODE_COUNT - 1)
	if lane < 0:
		return "napojuje se na úsek %d · %s" % [to + 1, node_name(n)]
	if node_choice_count(lane, to) <= 1:
		return "napojuje se na úsek %d" % (to + 1)
	return "napojuje se na úsek %d · %s" % [to + 1, node_name(n)]


# KTERY CIL BUDE NASLEDOVAT po dalsim klepnuti na "cíl". Jedno misto, kde se
# to rozhoduje - ptá se ho samotny cyklus i napoveda v hlásce. Dve kopie by
# se rozešly a napoveda by hracovi lhala.
#
# U napojeni se porovnava I UZEL: stejny cil ve dvou ruznych uzlech jsou dve
# ruzne volby a cyklus musi vedet, na ktere z nich prave stoji.
func next_choice_index(lane: int) -> int:
	var choices: Array = target_choices(lane)
	if choices.size() < 2:
		return -1
	var kind: int = target_kind(lane)
	var node: int = lane_node(lane)
	var at: int = -1
	for i in range(choices.size()):
		var c: Dictionary = choices[i]
		if int(c["kind"]) != kind or int(c["to"]) != to_of(lane):
			continue
		if kind == TO_LANE and int(c.get("node", 0)) != node:
			continue
		at = i
		break
	return 0 if at < 0 else (at + 1) % choices.size()


func cycle_target(lane: int) -> bool:
	if lane < 0 or lane >= lanes.size():
		return false
	var choices: Array = target_choices(lane)
	var next: int = next_choice_index(lane)
	if next < 0 or next >= choices.size():
		return false
	var pick: Dictionary = choices[next]
	var l: Dictionary = lanes[lane]
	var kind: int = int(pick["kind"])
	l["kind"] = kind
	l["to"] = int(pick["to"])
	# Uzel se drzi JEN u napojeni. Kdyz usek vede do vystupu nebo do vyhybky,
	# uzel nema vyznam a v kodu by byl jen balast.
	if kind == TO_LANE:
		l["node"] = int(pick.get("node", 0))
	else:
		l.erase("node")
	lanes[lane] = l
	relayout()
	return true


# ---------------------------------------------------------------- geometrie

# Kdo vsechno vede do te vyhybky (jeji privodni usek).
func lanes_into(j: int) -> Array:
	var out: Array = []
	for i in range(lanes.size()):
		if junction_of(i) == j:
			out.append(i)
	return out


# Vyhybky musi existovat, i kdyz o nich level jeste nic nevi (stare kody).
func _ensure_junctions() -> void:
	var need := 1
	for i in range(lanes.size()):
		need = maxi(need, from_of(i) + 1)
		if not lane_is_exit(i):
			need = maxi(need, junction_of(i) + 1)
	while junctions.size() < need:
		junctions.append({})
	while junctions.size() > need:
		junctions.remove_at(junctions.size() - 1)


# Rozvrzi radky. Kazdy usek koncici ve vystupu je jeden radek; usek, ktery vede
# do dalsi vyhybky, zabira tolik radku, kolik ma ta vyhybka useku - a sedi
# uprostred nich (proto jeho vetve "rozkvetou" na obe strany presne jako
# zakladni deska). Radky se VYSTREDI: pri peti usecich je mezera presne
# `spread`, pri trech se neroztahne pres celou plochu, ale zustane uprostred.
func relayout() -> void:
	_ensure_junctions()
	_row = {}
	_jrow = {}
	_span = {}
	_jspan = {}
	var cursor := 0
	for root in _roots():
		cursor = _walk(int(root), cursor, 0)
	_rows_total = cursor
	# Cile jsou radky ve STEJNE mrizce jako drahy: kazda dira potrebuje svuj
	# radek, aby se dve nekreslily pres sebe. Kdyz je cilu vic nez drah, radky
	# se pridaji - a mezera se zmensi vsem stejne (coz hlida rows_fit()).
	var n: int = maxi(maxi(_rows_total, exits.size()), 1)
	_grid_rows = n
	var gap: float = spread
	var span: float = gap * float(n - 1)
	if span > BOTTOM - TOP:
		gap = (BOTTOM - TOP) / float(maxi(n - 1, 1))
		span = gap * float(n - 1)
	_gap = gap
	var y0: float = TOP + (BOTTOM - TOP - span) * 0.5
	for j in _jspan:
		var s: Array = _jspan[j]
		_jrow[int(j)] = y0 + gap * (float(int(s[0])) + float(int(s[1]))) * 0.5
	for i in range(lanes.size()):
		# Usek sedi uprostred sveho vlastniho rozpeti. U useku do vystupu je to
		# proste jeho radek; u useku do vyhybky prostredek jejich vetvi.
		_row[i] = y0 + gap * _lane_row_index(i)
	# Vystupy jsou diry v mape: drzi si radek podle sveho indexu v mrizce.
	for idx in range(exits.size()):
		var e: Array = exits[idx]
		var keep_x: float = float(e[0])
		exits[idx] = [keep_x, y0 + gap * float(mini(idx, n - 1))]


# Kolik radku mrizka zabira a jakou mezeru ma. Radky jsou to, co level
# opravdu omezuje: bonusy na sousednich drahach se nesmi prekryvat.
func rows_total() -> int:
	return _grid_rows


func row_gap() -> float:
	return _gap


# VEJDE SE MRIZKA JESTE NA DESKU? Jedno misto, kde se to rozhoduje - ptá se
# ho editor (smí hrac pridat dalsi drahu nebo cil?) i validate (smí se level
# vyvézt?). Dve kopie podminky by se rozešly: hrac by si postavil level, ktery
# se mu nevyexportuje.
func rows_fit() -> bool:
	if _grid_rows <= 1:
		return true
	return _gap >= MIN_ROW_GAP


# Z kterych vyhybek se mrizka sklada. Kmen (vstup) zaklada vlastni strom, takze
# map se dvema kmeny ma dva stromy a kazdy si drzi sve radky. Kdyby se pocital
# jen strom prvni vyhybky, druhy kmen by nemel kde byt.
func _roots() -> Array:
	var roots: Array = []
	var covered := {}
	var cands: Array = []
	for e in entries:
		cands.append(int(e))
	for j in range(junctions.size()):
		cands.append(j)
	for c in cands:
		var j: int = int(c)
		if j < 0 or j >= junctions.size() or covered.has(j):
			continue
		roots.append(j)
		_mark_reachable(j, covered)
	return roots


func _mark_reachable(j: int, covered: Dictionary) -> void:
	var guard := 0
	var stack: Array = [j]
	while not stack.is_empty() and guard < 64:
		guard += 1
		var cur: int = int(stack.pop_back())
		if covered.has(cur):
			continue
		covered[cur] = true
		for i in range(lanes.size()):
			var k: int = junction_of(i)
			if k >= 0 and from_of(i) == cur and not covered.has(k):
				stack.append(k)


# Rekurzivni prichod mrizkou: kazdemu useku priridi rozpeti radku a vrati
# index prvniho volneho radku. Usek, ktery se napojuje na JINY USEK, je
# z pohledu mrizky list - ma svuj radek jako usek do vystupu.
func _walk(j: int, cursor: int, depth: int) -> int:
	var first: int = cursor
	var jl: Array = lanes_of(j)
	for lane in jl:
		if lane_is_exit(lane) or depth >= MAX_DEPTH:
			_span[lane] = [cursor, cursor]
			cursor += 1
		else:
			var k: int = junction_of(lane)
			if k < 0:
				_span[lane] = [cursor, cursor]
				cursor += 1
			else:
				cursor = _walk(k, cursor, depth + 1)
				_span[lane] = _jspan.get(k, [cursor, cursor])
	if jl.is_empty():
		_jspan[j] = [cursor, cursor]
	else:
		_jspan[j] = [first, cursor - 1]
	return cursor


# Stred rozpeti daneho useku jako index radku.
func _lane_row_index(lane: int) -> float:
	var s: Array = _span.get(lane, [0, 0])
	return (float(int(s[0])) + float(int(s[1]))) * 0.5


func row_of(lane: int) -> float:
	return float(_row.get(lane, TOP))


func exit_row(idx: int) -> float:
	var e: Array = exits[clampi(idx, 0, exits.size() - 1)]
	return float(e[1])


# Rovny usek toho useku v podilu sirky plochy: od bodu, kde se ohne z vyhybky,
# k bodu, kde se ohne ke svemu cili. Pocita se v NORMALIZOVANYCH souradnicich
# (level je nezavisly na displeji) - Network z toho jen prevede na pixely.
func run_frac(lane: int) -> float:
	return RUN_FRAC if target_kind(lane) != TO_JUNCTION else RUN_FRAC_CONNECTOR


# X-ova souradnice bodu, do ktereho usek vede. Pro cil = jiny usek je to
# ZVOLENY UZEL toho druheho useku - tam se vetev vleje do te druhe.
func target_x_of(lane: int, guard: int = 0) -> float:
	return _target_x(target_kind(lane), to_of(lane), guard, lane, lane_node(lane))


func _target_x(kind: int, to: int, guard: int, self_lane: int = -1, node: int = 0) -> float:
	if kind == TO_EXIT:
		return exit_x
	if kind == TO_JUNCTION:
		return junction_x(to) - MERGE_GAP
	# Cil = jiny usek. Kdyby se useky odkazovaly dokola (rozbitý level),
	# rekurze se zastavi - validate to stejne odmitne.
	if guard > 8 or to < 0 or to >= lanes.size() or to == self_lane:
		return exit_x
	return run_land_x(to, node, guard + 1)


# Kde se do toho useku vleje privodni vetev: v uzlu `node` jeho rovneho useku.
func run_land_x(lane: int, node: int = 0, guard: int = 0) -> float:
	var x0: float = run_x0(lane, guard)
	var x1: float = run_x1(lane, guard)
	return x0 + (x1 - x0) * node_frac(node)


# UZEL USEKU jako x-ova souradnice. Jedno misto, kde se to pocita - kresleni
# sitě, geometrie napojeni i testy se musi ptat tady, jinak by se uzel, ktery
# hrac vidi, rozešel s uzlem, do ktereho poutnik opravdu vstoupi.
func node_x(lane: int, node: int, guard: int = 0) -> float:
	var x0: float = run_x0(lane, guard)
	var x1: float = run_x1(lane, guard)
	return x0 + (x1 - x0) * node_frac(node)


# Kde se usek zacina stacet ke svemu cili. Za timhle bodem uz rovny usek neni,
# takze tam zadny uzel lezet nemuze.
func bend_x(lane: int, guard: int = 0) -> float:
	var x0: float = run_x0(lane, guard)
	var x1: float = run_x1(lane, guard)
	return x0 + (x1 - x0) * clampf(divert_of(lane), 0.0, 0.98)


# Kolik uzlu ciloveho useku je pro tenhle usek vubec pouzitelnych. Jedno
# misto, kde se to pocita - hlaska editoru z toho dela "uzel 2/3".
func node_choice_count(lane: int, to: int) -> int:
	var n := 0
	for k in range(NODE_COUNT):
		if can_target(lane, TO_LANE, to, k):
			n += 1
	return n


func run_x0(lane: int, guard: int = 0) -> float:
	var span: float = target_x_of(lane, guard) - junction_x(from_of(lane))
	if span <= 0.0:
		return junction_x(from_of(lane))
	return junction_x(from_of(lane)) + span * run_frac(lane)


func run_x1(lane: int, guard: int = 0) -> float:
	var span: float = target_x_of(lane, guard) - junction_x(from_of(lane))
	if span <= 0.0:
		return junction_x(from_of(lane))
	return target_x_of(lane, guard) - span * run_frac(lane)


func run_of(lane: int) -> float:
	return run_x1(lane) - run_x0(lane)


# Smi tenhle usek vest tam? Jedno misto, kde se to rozhoduje - ptá se ho
# editor (co nabizet), validate (co proslo) i hra. Tri ruzne podminky by se
# drive nebo pozdeji rozešly.
#
# `node` je uzel, do ktereho se vetev napoji (ma vyznam jen pro TO_LANE);
# -1 znamena "ten, ktery je na useku nastaveny". Editor zkousi i jine uzly,
# proto se sem uzel predava.
func can_target(lane: int, kind: int, to: int, node: int = -1) -> bool:
	if lane < 0 or lane >= lanes.size():
		return false
	var n: int = lane_node(lane) if node < 0 else node
	if kind == TO_EXIT:
		if to < 0 or to >= exits.size():
			return false
	elif kind == TO_JUNCTION:
		if to < 0 or to >= junctions.size() or to == from_of(lane):
			return false
		# Usek vede o patro hloub, ale jen do meze MAX_DEPTH.
		if junction_depth(from_of(lane)) + 1 > MAX_DEPTH:
			return false
		if junction_depth(to) > MAX_DEPTH:
			return false
	elif kind == TO_LANE:
		if to < 0 or to >= lanes.size() or to == lane:
			return false
		if _chains_to(to, lane):
			return false
		if n < 0 or n >= NODE_COUNT:
			return false
		# UZEL MUSI LEZET NA ROVNEM USEKU CILOVEHO USEKU. Za jeho zatackou uz
		# rovny usek neni - vetev by se vlekla do oblouku a na rovnem useku by
		# zustalo min misto na bonusy, nez level potrebuje.
		if node_x(to, n) > bend_x(to) + 0.0001:
			return false
	else:
		return false
	# Geometrie: mezi vyhybkou a cilem musi zustat misto na rovny usek.
	var span: float = _target_x(kind, to, 0, lane, n) - junction_x(from_of(lane))
	if span <= 0.0:
		return false
	var frac: float = RUN_FRAC if kind != TO_JUNCTION else RUN_FRAC_CONNECTOR
	if span * (1.0 - 2.0 * frac) < MIN_RUN:
		return false
	return true


# Vede z useku `from` cesta (pres napojovani na dalsi useky) az na usek `to`?
# Presne to je smycka, ktera se nesmi stat: poutnik by po ni sel porad dokola.
func _chains_to(from: int, to: int) -> bool:
	var cur: int = from
	var guard := 0
	while cur >= 0 and guard <= lanes.size():
		if cur == to:
			return true
		var nxt: int = lane_target_of(cur)
		if nxt < 0:
			return false
		cur = nxt
		guard += 1
	return true


# ---------------------------------------------------------------- zakladni

static func base() -> Level:
	var l := Level.new()
	l.name = "zakladni"
	for i in range(BASE_LANE_ELEMENTS.size()):
		l.lanes.append({
			"from": 0,
			"el": int(BASE_LANE_ELEMENTS[i]),
			"kind": TO_EXIT,
			"to": int(BASE_EXITS[i]),
			"divert": BASE_DIVERT,
		})
	l.exits = []
	for r in BASE_EXITS:
		l.exits.append([BASE_EXIT_X, TOP])
	l.junctions = [{}]
	l.entries = [0]
	l.relayout()
	return l


func clone() -> Level:
	return Level.from_dict(to_dict())


# ---------------------------------------------------------------- data

func to_dict() -> Dictionary:
	# Radky, hloubky ani souradnice vyhybek se NEUKLADaji: pocita je relayout().
	# V souboru by byly jen balast a kod levelu by se zbytecne prodlouzil -
	# pritom se musi vejit do jedne rady Telegramu.
	var brief: Array = []
	for i in range(lanes.size()):
		var l: Dictionary = lanes[i]
		var one: Dictionary = {
			"from": from_of(i),
			"el": int(l["el"]),
			"kind": target_kind(i),
			"to": to_of(i),
			"divert": float(l.get("divert", BASE_DIVERT)),
		}
		# UZEL SE POSILA JEN KDYBY NENI NULA. Kod levelu musi zustat kratky
		# (vejde se do Telegramu) a zakotvene levely musi mit kod znak po
		# znaku stejny - kdyby se uzel psal vzdy, zmenil by se kazdy level,
		# ktery uzel vubec nepouziva.
		if target_kind(i) == TO_LANE and lane_node(i) > 0:
			one["node"] = lane_node(i)
		brief.append(one)
	return {
		"name": name,
		"lanes": brief,
		"junctions": junctions.size(),
		"entries": entries.duplicate(),
		"exits": exits.duplicate(true),
		"spread": spread,
		"exit_x": exit_x,
		"zone_dmg": zone_dmg,
		"speed": speed,
		"spawn": spawn,
		"lives": lives,
		"gold": gold,
	}


static func from_dict(d: Dictionary) -> Level:
	var l := Level.new()
	l.name = str(d.get("name", DEFAULT_NAME))
	var raw: Array = d.get("lanes", [])
	for item in raw:
		var m: Dictionary = item
		# "exit" je stary nazev klice pro cil useku a chybejici "kind" znamena
		# stary format (>= 0 byl vystup, < 0 vyhybka). Stare levely se musi
		# nacist taky, jinak by hrac prisel o to, co ma ulozene.
		if m.has("kind"):
			var kind: int = int(m["kind"])
			l.lanes.append({
				"from": int(m.get("from", 0)),
				"el": int(m.get("el", NEUTRAL)),
				"kind": kind,
				"to": int(m.get("to", 0)),
				"divert": float(m.get("divert", BASE_DIVERT)),
				"node": clampi(int(m.get("node", 0)), 0, NODE_COUNT - 1),
			})
		else:
			var to: int = int(m.get("to", m.get("exit", 0)))
			l.lanes.append({
				"from": int(m.get("from", 0)),
				"el": int(m.get("el", NEUTRAL)),
				"kind": TO_EXIT if to >= 0 else TO_JUNCTION,
				"to": to if to >= 0 else (-1 - to),
				"divert": float(m.get("divert", BASE_DIVERT)),
				"node": clampi(int(m.get("node", 0)), 0, NODE_COUNT - 1),
			})
	if l.lanes.is_empty():
		return Level.base()
	var ex: Array = d.get("exits", [])
	for item in ex:
		var p: Array = item
		l.exits.append([float(p[0]), float(p[1])])
	if l.exits.is_empty():
		l.exits.append([BASE_EXIT_X, TOP])
	var jn: int = maxi(int(d.get("junctions", 0)), 0)
	while l.junctions.size() < jn:
		l.junctions.append({})
	var ent: Array = d.get("entries", [])
	for e in ent:
		var ei: int = int(e)
		if ei >= 0 and ei < jn and not l.has_entry(ei):
			l.entries.append(ei)
	if l.entries.is_empty():
		l.entries = [0]
	l.spread = float(d.get("spread", BASE_SPREAD))
	l.exit_x = float(d.get("exit_x", BASE_EXIT_X))
	l.zone_dmg = float(d.get("zone_dmg", BASE_ZONE_DMG))
	l.speed = float(d.get("speed", BASE_SPEED))
	l.spawn = float(d.get("spawn", BASE_SPAWN))
	l.lives = int(d.get("lives", BASE_LIVES))
	l.gold = int(d.get("gold", BASE_GOLD))
	l.clamp_all()
	l.relayout()
	return l


func to_json() -> String:
	return JSON.stringify(to_dict())


# KOD LEVELU pro predani mimo hru. Je to stejny JSON, jen zbaveny mezer,
# aby se vesel do jedne rady Telegramu i z telefonu:
#   ZILY1;{"name":"...","lanes":[...],...}
# Cislo za ZILY je verze formatu - kdyby se data jednou zmenila, stary kod
# se pozna a necte se naslepo.
const CODE_PREFIX := "ZILY1;"


func to_code() -> String:
	var t: String = to_json()
	t = t.replace(": ", ":").replace(", ", ",")
	return CODE_PREFIX + t


static func from_code(code: String) -> Level:
	var t: String = code.strip_edges()
	# Hrac muze poslat i cely JSON ze souboru - oboji je stejny format.
	if t.begins_with(CODE_PREFIX):
		t = t.substr(CODE_PREFIX.length())
	if not t.begins_with("{"):
		return Level.base()
	return Level.from_json(t)


# LEVEL ZAKOTVENY VE HRE. Cte se z BuiltinLevels - to je jedina cesta, jak
# se level dostane natrvalo do hry na vsechny platformy. Vraci null, kdyz
# takovy level neni (pak se hleda lokalne ulozeny).
static func builtin(n: String) -> Level:
	for item in BuiltinLevels.LEVELS:
		var d: Dictionary = item
		if str(d.get("name", "")) != n:
			continue
		var lv := from_code(str(d.get("code", "")))
		lv.name = n
		return lv
	return null


static func builtin_names() -> Array:
	var out: Array = []
	for item in BuiltinLevels.LEVELS:
		var d: Dictionary = item
		out.append(str(d.get("name", "")))
	return out


static func from_json(text: String) -> Level:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return Level.base()
	var d: Dictionary = parsed
	return Level.from_dict(d)


# Rucky se daji utect mimo rozumne meze; level se po kazde zmene srovna, aby
# se z nej nedal vyrobit level, ktery se nevejde na displej.
func clamp_all() -> void:
	spread = clampf(spread, 0.06, 0.30)
	exit_x = clampf(exit_x, 0.80, 0.99)
	zone_dmg = clampf(zone_dmg, 10.0, 90.0)
	speed = clampf(speed, 20.0, 120.0)
	spawn = clampf(spawn, 0.6, 3.0)
	lives = clampi(lives, 3, 40)
	gold = clampi(gold, 0, 5000)
	for i in range(lanes.size()):
		var l: Dictionary = lanes[i]
		l["from"] = clampi(int(l.get("from", 0)), 0, MAX_LANES - 1)
		l["el"] = clampi(int(l["el"]), NEUTRAL, Element.COUNT - 1)
		var kind: int = int(l.get("kind", TO_EXIT))
		if kind < TO_EXIT or kind > TO_LANE:
			kind = TO_EXIT
		l["kind"] = kind
		var to: int = int(l["to"])
		if kind == TO_EXIT:
			l["to"] = clampi(to, 0, maxi(exits.size() - 1, 0))
		elif kind == TO_JUNCTION:
			l["to"] = clampi(to, 0, maxi(junctions.size() - 1, 0))
		else:
			l["to"] = clampi(to, 0, maxi(lanes.size() - 1, 0))
		l["divert"] = clampf(float(l.get("divert", BASE_DIVERT)), 0.0, 0.98)
		# Uzel ma vyznam jen u napojeni - jinde se zahodi, aby v datech
		# nezustaval balast, ktery by se jednou mohl zacit cist.
		if kind == TO_LANE:
			l["node"] = clampi(int(l.get("node", 0)), 0, NODE_COUNT - 1)
		else:
			l.erase("node")
		lanes[i] = l
	# Kmeny: prvni musi existovat vzdy, jinak by do mapy nikdo nevstoupil.
	var clean: Array = []
	for e in entries:
		var ei: int = int(e)
		if ei >= 0 and ei < junctions.size() and not clean.has(ei):
			clean.append(ei)
	entries = clean
	if entries.is_empty():
		entries = [0]


# ---------------------------------------------------------------- ulozeni

# Levely se ukladaji jako JSON. Ve webovem exportu do localStorage (aby hrac
# o svou praci neprisel zavrenim panelu), na desktopu do user://.
# Cteni i zapis jsou synchronni, takze k nim nepotrebujeme zadny callback.
const WEB_PREFIX := "zily.level."
const DIR := "user://levels"
const INDEX_KEY := "zily.levels"
const LAST_KEY := "zily.last"


func storage_key() -> String:
	return WEB_PREFIX + name


static func _web() -> Object:
	if not OS.has_feature("web"):
		return null
	return Engine.get_singleton("JavaScriptBridge")


static func _js_get(key: String) -> String:
	var jb: Object = _web()
	if jb == null:
		return ""
	var t: Variant = jb.call("eval", "localStorage.getItem(%s)||''" % JSON.stringify(key), false)
	if typeof(t) == TYPE_STRING:
		return str(t)
	return ""


static func _js_set(key: String, value: String) -> void:
	var jb: Object = _web()
	if jb != null:
		jb.call("eval", "localStorage.setItem(%s,%s)" % [
			JSON.stringify(key), JSON.stringify(value)], false)


func save() -> bool:
	var text: String = to_json()
	if _web() != null:
		_js_set(storage_key(), text)
		_remember(str(name))
		save_last(str(name))
		return true
	DirAccess.make_dir_recursive_absolute(DIR)
	var f: FileAccess = FileAccess.open(DIR + "/" + name + ".json", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	_remember(str(name))
	save_last(str(name))
	return true


static func load_named(n: String) -> Level:
	var t: String = _js_get(WEB_PREFIX + n)
	if not t.is_empty():
		var lv := Level.from_json(t)
		lv.name = n
		return lv
	if _web() != null:
		return Level.base()
	var f: FileAccess = FileAccess.open(DIR + "/" + n + ".json", FileAccess.READ)
	if f == null:
		return Level.base()
	var text: String = f.get_as_text()
	f.close()
	var lv2 := Level.from_json(text)
	lv2.name = n
	return lv2


static func _remember(n: String) -> void:
	if _web() != null:
		var jb: Object = _web()
		jb.call("eval", "(function(){var k=%s;var l=JSON.parse(localStorage.getItem(k)||'[]');" % INDEX_KEY +
			"if(l.indexOf(%s)<0){l.push(%s);localStorage.setItem(k,JSON.stringify(l));}})()" % [
				JSON.stringify(n), JSON.stringify(n)], false)
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	var f: FileAccess = FileAccess.open(DIR + "/_index.txt", FileAccess.READ)
	var known: String = f.get_as_text() if f != null else ""
	if f != null:
		f.close()
	if not known.contains("\n" + n + "\n"):
		var w: FileAccess = FileAccess.open(DIR + "/_index.txt", FileAccess.WRITE)
		if w != null:
			w.store_string(known + "\n" + n + "\n")
			w.close()


# Seznam ulozenych levelu. Pouziva ho editor v seznamu.
static func saved_names() -> Array:
	var out: Array = []
	var t: String = _js_get(INDEX_KEY)
	if _web() != null:
		var parsed: Variant = JSON.parse_string(t)
		if typeof(parsed) == TYPE_ARRAY:
			for x in parsed:
				out.append(str(x))
		return out
	var f: FileAccess = FileAccess.open(DIR + "/_index.txt", FileAccess.READ)
	if f == null:
		return out
	var text: String = f.get_as_text()
	f.close()
	for line in text.split("\n", false):
		out.append(str(line))
	return out


# Posledni otevreny level. Editor se po otevreni vrati presne tam, kde hrac
# skoncil - jinak by pri kazdem vstupu do editoru prisel o to, co delal.
static func save_last(n: String) -> void:
	if _web() != null:
		_js_set(LAST_KEY, n)
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	var f: FileAccess = FileAccess.open(DIR + "/_last.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(n)
		f.close()


static func last_name() -> String:
	if _web() != null:
		return _js_get(LAST_KEY)
	var f: FileAccess = FileAccess.open(DIR + "/_last.txt", FileAccess.READ)
	if f == null:
		return ""
	var t: String = f.get_as_text()
	f.close()
	return t.strip_edges()


# Jmeno pro novy level: "level-1", "level-2", ... Prvni, ktere jeste nikdo
# nepouziva. Nahodne jmeno by se v seznamu nedalo najit.
static func next_free_name() -> String:
	var used := {}
	for n in saved_names():
		used[str(n)] = true
	var i := 1
	while used.has("level-%d" % i):
		i += 1
	return "level-%d" % i


# Export levelu do souboru, ktery si hrac muze poslat. Ve webu se soubor
# stahne (blob), na desktopu se zapise do user://export.
func export_to_file() -> String:
	var text: String = to_json()
	if _web() != null:
		var js := """
		(() => {
		  const blob = new Blob([%s], {type: 'application/json'});
		  const a = document.createElement('a');
		  a.href = URL.createObjectURL(blob);
		  a.download = 'zily-%s.json';
		  document.body.appendChild(a); a.click(); a.remove();
		  return 'ok';
		})()
		""" % [JSON.stringify(text), name]
		var jb: Object = _web()
		jb.call("eval", js, false)
		return "zily-%s.json (staženo)" % name
	DirAccess.make_dir_recursive_absolute("user://export")
	var path: String = "user://export/zily-%s.json" % name
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(text)
	f.close()
	return ProjectSettings.globalize_path(path)


# Rychla kontrola, ze level dava smysl. Editor ji pousti pred exportem -
# prazdny nebo rozbity level by hrac poznal az ve hre.
func validate() -> Array:
	var errs: Array = []
	if lanes.size() < MIN_LANES:
		errs.append("méně než %d úseky" % MIN_LANES)
	if lanes.size() > MAX_LANES:
		errs.append("více než %d úseků" % MAX_LANES)
	if exits.is_empty():
		errs.append("žádný výstup")
	for i in range(exits.size()):
		if exits[i].size() < 2:
			errs.append("výstup %d nemá souřadnice" % (i + 1))
	# MRIZKA SE MUSI VEJIT NA DESKU. Tohle je strop, na ktery hrac narazi pri
	# pridavani drah i kmenu - ne pocet useku sam o sobe.
	if not rows_fit():
		errs.append("na desku se tolik drah nevejde (%d řádků, mezera %.3f, potřeba %.3f)" % [
			_grid_rows, _gap, MIN_ROW_GAP])
	if entries.is_empty():
		errs.append("do mapy nevede žádný kmen")
	for j in entries:
		if int(j) < 0 or int(j) >= junctions.size():
			errs.append("kmen vede do neexistující výhybky")
		elif not lanes_into(int(j)).is_empty():
			errs.append("do výhybky %d vede kmen i úsek" % (int(j) + 1))
	# Kazdy usek musi mit platny cil. Rozhoduje o tom JEDNA funkce - stejna,
	# kterou se ptá editor, kdyz cile nabizi.
	for i in range(lanes.size()):
		if from_of(i) < 0 or from_of(i) >= junctions.size():
			errs.append("úsek %d vede z neexistující výhybky" % (i + 1))
		elif not can_target(i, target_kind(i), to_of(i)):
			var kind: int = target_kind(i)
			if kind == TO_EXIT:
				errs.append("úsek %d míří na neexistující výstup" % (i + 1))
			elif kind == TO_JUNCTION:
				errs.append("úsek %d vede do výhybky, která je moc hluboko, nebo do sebe" % (i + 1))
			else:
				var t: int = to_of(i)
				if t < 0 or t >= lanes.size():
					errs.append("úsek %d se napojuje na neexistující úsek" % (i + 1))
				elif _chains_to(t, i):
					errs.append("úseky %d a %d se napojují dokola" % [i + 1, t + 1])
				elif node_x(t, lane_node(i)) > bend_x(t) + 0.0001:
					errs.append("úsek %d se napojuje do zatáčky úseku %d — uzel leží za jeho odbočením" % [
						i + 1, t + 1])
				else:
					errs.append("úsek %d je moc krátký na to, aby na něm stály bonusy" % (i + 1))
		if lanes_of(from_of(i)).size() > MAX_FAN:
			errs.append("z výhybky %d vede víc než %d úseků" % [from_of(i) + 1, MAX_FAN])
	for j in range(1, junctions.size()):
		var kids: Array = lanes_of(j)
		if kids.size() < 2:
			errs.append("výhybka %d má míň než dva úseky" % (j + 1))
		if lanes_into(j).is_empty() and not has_entry(j):
			errs.append("do výhybky %d nikdo nevede" % (j + 1))
		for k in kids:
			if target_kind(k) == TO_JUNCTION:
				errs.append("z výhybky %d vede úsek do další výhybky" % (j + 1))
	if lanes_of(0).size() < MIN_LANES:
		errs.append("z první výhybky nevedou aspoň dva úseky")
	if not has_entry(0) and lanes_into(0).is_empty():
		errs.append("do první výhybky nevede kmen")
	var killable := 0
	for i in range(lanes.size()):
		if not is_neutral(i):
			killable += 1
	if killable < 2:
		errs.append("v mapě není dost úseků, které umí zabíjet")
	return errs
