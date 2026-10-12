class_name Level
extends RefCounted

# =========================================================================
# LEVEL JE GRAF V MRÍŽCE. Zadne automaticke rozvrhovani, zadne radky.
#
# Jan (Oct 2026): "Cesty budu kreslit prstem, libovolneho smeru a tvaru.
# Vzdy bude drzet rovinu. Bude se lamat v 90 stupnovych uhlech."
#
# Dve veci, ktere z toho plynou a ktere urcuji cely tento soubor:
#
#   1. GRAF NENI STROM. Nekresli se jen "fan" z vyhybky do cile - cesta se
#      ohne, vrati se zpatky a spoji se s jinou (v nakresu ma mapa DIAMANTY:
#      rozdel -> dve paralelni trasy -> spoj). Proto ma usek SEZNAM PRITOKU,
#      ne jednoho predchudce, a proto je "spojka" (N vstupu -> 1 vystup)
#      rovnocenny prvek s "vyhybkou" (1 vstup -> N vystupu).
#
#   2. UZEL JE BUNKA. Usek (hrana) zacina a konci ve STREDU bunky uzlu.
#      Diky tomu staci na prechod poutnika z useku na usek jen "dosel jsem
#      na konec useku -> v uzlu vyber dalsi usek", bez vstupniho bodu,
#      bez lane_entry_s a bez TO_LANE (vlej se do jineho useku). Napojovani
#      cest nahrazuje UZEL polozeny na cizi usek - usek se tam ROZDELI.
#
# Co z puvodniho modelu zmizelo: relayout, rows_fit, MIN_ROW_GAP, NODE_FRACS,
# run_frac_for, divert, MAX_DEPTH, span/_jspan, automaticke umistovani.
# Co zustalo: damage model (Element), pas kolem cest se vezemi, rng a kola
# (ty jsou ve Game, ne tady).
# =========================================================================

# --------------------------------------------------------------- mrizka
# MRIZKA VYPLNUJE ARENU: `Network` pocita cell_w = arena.w/cols a
# cell_h = arena.h/rows, takze bunka neni ctvercova a okraj nezustava
# zadny. Natazeni po ose ale nic nelame - cesty vedou PO OSE, takze se
# z kazdeho ohybu stane i tak pravy uhel.
#
# HUSTOTA. Jan (Oct 2026): "Mohl by být grid ještě hustší? Aby byly
# čtverečky menší a tím pádem se mohly cesty stavět o něco flexibilněji."
# 20x10 -> 28x14 (krok 0.4): na 932x430 je bunka v editoru 33x23 px misto
# 47x32, takze ohyb cesty stoji 33 px a dve trasy se daji slozit tesne
# vedle sebe. Hranici je prst: na 640x360 (nejmensi podporovany displej)
# vyjde bunka na 23x18 px a mensi uz by se nedala trefit.
const COLS := 28
const ROWS := 14

# --------------------------------------------------------------- druhy uzlu
const START := 0      # vstup poutniku, 1 vystup
const CIL := 1        # konec cesty, >= 1 vstup, zadny vystup
const VYHYBKA := 2    # 1 vstup, >= 2 vystupy - hrac voli, kterym poutnik pujde
const SPOJKA := 3     # >= 2 vstupy, 1 vystup - trasu slucuje, nerozhoduje
const UZEL := 4       # 1 vstup, 1 vystup - pruchozi bod (bonus, pripojeni)

const KIND_NAMES := ["start", "cíl", "výhybka", "spojka", "uzel"]

# Element useku. Neutralni usek nema element a dava vsem 100 %.
const NEUTRAL := -1
# KMEN je druhy usek BEZ ELEMENTU: neposkozuje vubec (jako vstupni usek ze
# startu). Jan: "v nabidce typu cest chybi neutralni a kmen (nedava zadne
# poskozeni)". Neni to element, proto se nikdy nesmi dostat do
# Element.name_of - na jmena je tu `value_name()`.
const KMEN := -2

# --------------------------------------------------------------- zakladni cisla
const BASE_SPEED := 52.0
# LEGACY: prumerna mezera mezi poutniky z modelu VLAK (0.6-1.4 nasobek).
# Dnesni kolo si mezery losuje samo z rozpeti Game.ROUND_GAP_MIN..MAX, takze
# hra tuhle hodnotu nikde necte. Zustava jen proto, aby se stary kod levelu
# (klic "p") dal precti a zapsat - nic se podle ni nedeje.
const BASE_SPAWN := 1.9
# CASOVY LIMIT KOLA ve vterinach. Kolo neni pocet poutniku, ale okno, po
# ktere vstupy tecou (Jan: "Kolo bude mít časový limit. Třeba 2 minuty.").
const BASE_ROUND := 120.0
const BASE_LIVES := 12
const BASE_GOLD := 260
# KOLIK MIST NA BONUS SE VEJDE NA JEDEN USEK. LEGACY: hodnota se jeste
# uklada do kodu levelu (klic "slots"), ale do hry nevstupuje - veze se
# stavi do PASU kolem cesty, ne na mista na useku. Slouzi jen k tomu, aby
# se stara ulozena mapa dala precist a zapsat presne tak, jak byla.
const SLOTS := 3
# Strop poctu mist na jednom useku. Neni to geometrie (mista se vejdou i
# vic), je to mez, za kterou uz by se klepnuti na jedno misto nedalo
# odlisit od sousedniho. Editor cykluje 0..MAX_SLOTS.
const MAX_SLOTS := 6

var name: String = ""
var cols: int = COLS
var rows: int = ROWS

# UZLY: [{c:int, r:int, kind:int}]
var nodes: Array = []
# USEKY: [{cells: Array[Vector2i], elem:int, entry:bool, slots:int}]
#   cells[0] je bunka pocatecniho uzlu, cells[-1] bunka koncoveho uzlu.
#   entry = vede ze STARTu (odvozeno z grafu, ne z ruky hrace). Je to
#   STRUKTURALNI priznak: z takoveho useku poutnici vstupuji do mapy a
#   prodluzuje se na okraj displeje. O poskozeni ROZHODUJE HODNOTA USEKU,
#   ne tenhle priznak - vstupni usek je od vychoziho stavu KMEN, ale hrac
#   ho muze prepnout na element.
#   slots = kolik mist na bonus tenhle usek ma (LEGACY - do hry nevstupuje,
#   viz `lane_slot_count`).
var lanes: Array = []

var speed: float = BASE_SPEED
var spawn: float = BASE_SPAWN
var round_time: float = BASE_ROUND
var lives: int = BASE_LIVES
var gold: int = BASE_GOLD

# Stav posledni kontroly - editor i UI z nej ctou, co se prave stalo.
var last_error: String = ""


# =========================================================================
# UZLY A USEKY - zakladni pristup
# =========================================================================

func node_count() -> int:
	return nodes.size()


func lane_count() -> int:
	return lanes.size()


func node_kind(n: int) -> int:
	if n < 0 or n >= nodes.size():
		return -1
	return int(nodes[n]["kind"])


func node_cell(n: int) -> Vector2i:
	if n < 0 or n >= nodes.size():
		return Vector2i(-1, -1)
	return Vector2i(int(nodes[n]["c"]), int(nodes[n]["r"]))


func kind_name(kind: int) -> String:
	if kind < 0 or kind >= KIND_NAMES.size():
		return "?"
	var s: String = KIND_NAMES[kind]
	return s


# Uzel lezi na te bunce? -1 kdyz tam nic neni.
func node_at(c: int, r: int) -> int:
	for i in range(nodes.size()):
		if int(nodes[i]["c"]) == c and int(nodes[i]["r"]) == r:
			return i
	return -1


func node_at_cell(cell: Vector2i) -> int:
	return node_at(cell.x, cell.y)


func lane_cells(lane: int) -> Array:
	if lane < 0 or lane >= lanes.size():
		return []
	var a: Array = lanes[lane]["cells"]
	return a


# POSUN CELYCH CCASTI MAPY: obdelnikovy vyber se da uchopit a posunout
# libovolnym smerem (Jan, Oct 2026). Je to CISTA GEOMETRIE - posouvaji se bunky
# useku a bunky uzlu, zadna pravidla se tu neresi. Jestli mapa po posunu plati,
# se ptá az volajici (`Editor._after_change`), protoze jen on umi posun vzit
# zpet a rict hracovi, co se rozbilo.
func shift_cells(lane_ids: Array, node_ids: Array, d: Vector2i) -> void:
	if d == Vector2i.ZERO:
		return
	for i in lane_ids:
		var li: int = int(i)
		if li < 0 or li >= lanes.size():
			continue
		var out: Array = []
		for c in lanes[li]["cells"]:
			var v: Vector2i = c
			out.append(v + d)
		lanes[li]["cells"] = out
	for n in node_ids:
		var ni: int = int(n)
		if ni < 0 or ni >= nodes.size():
			continue
		nodes[ni]["c"] = int(nodes[ni]["c"]) + d.x
		nodes[ni]["r"] = int(nodes[ni]["r"]) + d.y


# KTERA CESTA VEDE TOUTO BUNKOU (-1, kdyz zadna). Jedno misto, kde se na to da
# zeptat - testy si odpoved nesmi skladat z `lane_cells`, protoze pak meri svuj
# vlastni preklad a ne to, co vidi hrac.
func lane_at_cell(cell: Vector2i) -> int:
	for i in range(lanes.size()):
		for c in lane_cells(i):
			var v: Vector2i = c
			if v == cell:
				return i
	return -1


func lane_element(lane: int) -> int:
	if lane < 0 or lane >= lanes.size():
		return NEUTRAL
	return int(lanes[lane]["elem"])


func lane_is_neutral(lane: int) -> bool:
	return lane_element(lane) == NEUTRAL


func lane_is_kmen(lane: int) -> bool:
	return lane_element(lane) == KMEN


# JMENO HODNOTY USEKU. `Element.name_of` se na neutralni usek a kmen NESMI
# volat: dostane -1/-2 a v GDScriptu to neni chyba, ale tichy nesmysl
# (NAMES[-1] je "Vzduch"), takze by hra lhala o tom, na co se hrac kouka.
static func value_name(e: int) -> String:
	if e == NEUTRAL:
		return "neutrální"
	if e == KMEN:
		return "kmen"
	if e < 0 or e >= Element.COUNT:
		return "?"
	return Element.name_of(e)


# BARVA HODNOTY USEKU. Druhy par k `value_name` a JEDINE misto, kde se hodnota
# useku meni na barvu: kmen je tmavy sedy (neposkuzuje vubec), neutralni usek
# svetle sedy (dela vsem stejne) a element svoji barvu. Pouziva ji hra i
# editor - kdyby si to kazda obrazovka pocitala sama, kreslil by editor neco
# jineho, nez na co klepnuti sedi.
#
# POZOR: nikdy na tohle nepouzivej `Element.color_of(lane_element(lane))`.
# Kmen ma -2 a `COLORS[-2]` je barva Země (zaporny index jde od konce pole),
# takze se kmen kreslil jako zemni cesta a nikdo si toho nevsiml.
static func value_color(e: int) -> Color:
	if e == KMEN:
		return Color(0.36, 0.35, 0.33)
	if e == NEUTRAL or e < 0 or e >= Element.COUNT:
		return Color(0.55, 0.53, 0.48)
	return Element.color_of(e)


# =========================================================================
# DELKA EXISTUJICI CESTY
#
# Jan (Oct 2026): "Ještě by to chtělo možnost zvětšovat/zmenšovat existující
# cesty... Abych nemusel vše dokola mazat a znovu vkládat."

# ZVETSENI/ZMENSENI HOTOVE CESTY. Uzly (start, vyhybka, spojka, cil) se
# NEHYBOU - meni se jen tvar cesty mezi nimi: do cesty se vlozi "vybouleni"
# (cesta obejde o bunku vedle), takze se prodlouzi o DVE bunky, a "kratsi" to
# same vybouleni zase slozi. Dve bunky proto, ze cesta vede po mrizce: o jednu
# bunku se neda obejit tak, aby zustala souvisla.
#
# `near` je bunka, za kterou hrac chytil CESTU PRSTEM - vybouleni se dela u ni,
# ne na zacatku cesty. Hrac tak tvaruje presne to misto, na ktere saha.
#
# Nepoužije se misto, ktere je obsazene (jina cesta, uzel, mimo mrizku) -
# a stejne jako kazda jina zmena v editoru projde kontrolou mapy (validate).
func bend_lane(lane: int, grow: bool, near: Vector2i = Vector2i(-1, -1)) -> bool:
	if lane < 0 or lane >= lane_count():
		return false
	var old: Array = lane_cells(lane)
	if old.size() < 3:
		# Kratka cesta (dve bunky) nema kam vybouleni vlozit.
		return false
	if grow:
		return _bend_grow(lane, old, near)
	return _bend_shrink(lane, old, near)


func _bend_grow(lane: int, old: Array, near: Vector2i) -> bool:
	var best: int = -1
	var best_p: Vector2i = Vector2i.ZERO
	var best_d: float = 1.0e12
	for i in range(old.size() - 1):
		var a: Vector2i = old[i]
		var b: Vector2i = old[i + 1]
		var d: Vector2i = b - a
		if absi(d.x) + absi(d.y) != 1:
			continue
		for p in [Vector2i(-d.y, d.x), Vector2i(d.y, -d.x)]:
			var c1: Vector2i = a + p
			var c2: Vector2i = b + p
			if not _bend_cell_free(lane, old, c1) or not _bend_cell_free(lane, old, c2):
				continue
			var dist: float = _bend_dist(c1, near)
			if dist < best_d:
				best_d = dist
				best = i
				best_p = p
	if best < 0:
		return false
	var out: Array = []
	out.append_array(old.slice(0, best + 1))
	out.append(old[best] + best_p)
	out.append(old[best + 1] + best_p)
	out.append_array(old.slice(best + 1, old.size()))
	lanes[lane]["cells"] = out
	return true


func _bend_shrink(lane: int, old: Array, near: Vector2i) -> bool:
	var best: int = -1
	var best_d: float = 1.0e12
	for i in range(old.size() - 3):
		var a: Vector2i = old[i]
		var m1: Vector2i = old[i + 1]
		var m2: Vector2i = old[i + 2]
		var b: Vector2i = old[i + 3]
		var d: Vector2i = b - a
		if absi(d.x) + absi(d.y) != 1:
			continue
		# Vybouleni ma tvar a -> a+p -> b+p -> b.
		if m1 != a + Vector2i(-d.y, d.x) and m1 != a + Vector2i(d.y, -d.x):
			continue
		if m2 != b + (m1 - a):
			continue
		var dist: float = _bend_dist(m1, near)
		if dist < best_d:
			best_d = dist
			best = i
	if best < 0:
		return false
	var out: Array = []
	out.append_array(old.slice(0, best + 1))
	out.append_array(old.slice(best + 3, old.size()))
	lanes[lane]["cells"] = out
	return true


# Vzdalenost od bunky, za kterou hrac chytil cestu. Bez zadane bunky (near =
# -1,-1) je vsechno stejne daleko - vybouleni se pak dela na prvnim moznem
# miste, coz pouzivaji testy a stara data.
func _bend_dist(c: Vector2i, near: Vector2i) -> float:
	if near.x < 0:
		return 0.0
	return absf(float(c.x - near.x)) + absf(float(c.y - near.y))


# MUZE TAM VYBOULE­NI VUBCE VYJIT? Nesmi to byt mimo mrizku, na uzlu, na
# vlastni ceste a ani na ceste jine.
func _bend_cell_free(lane: int, old: Array, c: Vector2i) -> bool:
	if not in_bounds(c.x, c.y):
		return false
	if node_at_cell(c) >= 0:
		return false
	for oc in old:
		var o: Vector2i = oc
		if o == c:
			return false
	for j in range(lane_count()):
		if j == lane:
			continue
		for oc in lane_cells(j):
			var o: Vector2i = oc
			if o == c:
				return false
	return true


# =========================================================================
# POSUN ROVNEHO KUSU UPROSTRED CESTY ("obdelnikovy vystupek")
#
# Jan (Oct 2026): "Představuji si to tak, že mám třeba cestu ve tvaru
# obdélníkového výstupku, chytnu prstem horní část obdélníku, potáhnu nahoru,
# a celá tato část se posune nahoru, přičemž boční strany se automaticky
# natáhnou."
#
# Tvar, ktery se tim mysli:
#
#      ... --s--> R0 --d--> R1 --d--> ... --d--> Rm --(-s)--> ...
#
# `R0..Rm` je rovny kus (vrsek vystupku), `s` je smer, kterym vystupek trci
# ven. Posun kusu o `s` znamena, ze se CELY vrsek posune a obe bocni strany se
# prodlouzi o jednu bunku - cesta zustane souvisla a vystupek zustane
# obdelnikovy (zadne schodky). Dve bunky u kusu (R0 a Rm) pri tom zustavaji na
# miste a stanou se prvnimi bunkami bocnich stran.
#
# Tohle je jina operace nez `bend_lane` (ta do cesty vlozi vybouleni na JEDNOM
# kroku) - Janovo pero kresli tenhle posun.

# ROVNY KUS POD BUNKOU, KTERY SE DA POSUNOUT DO STRANY. Vraci {} nebo
# {a, b, d, s}: kus jsou bunky cs[a..b], `d` je jeho smer a `s` smer, kterym
# se posouva ven z tvaru.
#
# Kusa na KONCI cesty (u uzlu) se to netyka - tam se hybe uzel, ne kus.
func run_at(lane: int, cell: Vector2i) -> Dictionary:
	if lane < 0 or lane >= lane_count():
		return {}
	var cs: Array = lane_cells(lane)
	var n: int = cs.size()
	var i: int = -1
	for k in range(n):
		if cs[k] == cell:
			i = k
			break
	if i < 0:
		return {}
	var here: Vector2i = cs[i]
	# KUS MIMO STRED: bunka muze byt ROH (vstup a vystup se lisi), takze smer
	# kusu neni jednoznacny - zkousi se oba a vezme se ten, ktery da vystupek.
	var dirs: Array = []
	if i + 1 < n:
		var nxt: Vector2i = cs[i + 1]
		dirs.append(nxt - here)
	if i > 0:
		var prv: Vector2i = cs[i - 1]
		dirs.append(here - prv)
	for item in dirs:
		var d: Vector2i = item
		if absi(d.x) + absi(d.y) != 1:
			continue
		var a: int = i
		while a > 0 and (cs[a] - cs[a - 1]) == d:
			a -= 1
		var b: int = i
		while b + 1 < n and (cs[b + 1] - cs[b]) == d:
			b += 1
		if a == 0 or b == n - 1:
			continue
		var A: Vector2i = cs[a - 1]
		var B: Vector2i = cs[b + 1]
		var s: Vector2i = cs[a] - A
		# Obdelnikovy vystupek: prvni strana je kolma na kus a druha jde
		# presne zpet. Kdyz ne, neni to vystupek a posun by cestu preklopil
		# sam na sebe.
		if absi(s.x) + absi(s.y) != 1:
			continue
		if s.x * d.x + s.y * d.y != 0:
			continue
		if B - cs[b] != -s:
			continue
		return {"a": a, "b": b, "d": d, "s": s}
	return {}


# POSUN ROVNEHO KUSU O JEDNU BUNKU DO STRANY (`grow`) NEBO ZPET (`false`).
# Projde kontrolou: kus se musi vejit do mrizky, nove bunky nesmi byt na uzlu
# ani na jine ceste a cesta musi zustat souvisla a bez smycky.
func shift_run(lane: int, cell: Vector2i, grow: bool) -> bool:
	var run: Dictionary = run_at(lane, cell)
	if run.is_empty():
		return false
	var cs: Array = lane_cells(lane)
	var n: int = cs.size()
	var a: int = int(run["a"])
	var b: int = int(run["b"])
	var d: Vector2i = run["d"]
	var s: Vector2i = run["s"]
	var A: Vector2i = cs[a - 1]
	var out: Array = []
	var added: Array = []
	if grow:
		out.append_array(cs.slice(0, a))
		out.append(cs[a])
		for k in range(a, b + 1):
			var c: Vector2i = cs[k] + s
			out.append(c)
			added.append(c)
		out.append(cs[b])
		out.append_array(cs.slice(b + 1, n))
	else:
		# STEJNA OPERACE ZPET: kus se vrati a bunky, ktere drzely bocni
		# strany, se zase slozi (dopočítá se, co mezi krajnimi bunkami chybi).
		out.append_array(cs.slice(0, a))
		for k in range(1, b - a):
			var c2: Vector2i = A + d * k
			out.append(c2)
			added.append(c2)
		out.append_array(cs.slice(b + 1, n))
	if not _is_simple_path(out):
		return false
	for item in added:
		var c3: Vector2i = item
		if not in_bounds(c3.x, c3.y):
			return false
		if node_at_cell(c3) >= 0:
			return false
		for j in range(lane_count()):
			if j == lane:
				continue
			for o in lane_cells(j):
				if o == c3:
					return false
	lanes[lane]["cells"] = out
	return true


# ROZŠÍŘENÍ / ZÚŽENÍ VRŠKU VYSTUPKU (posun po ose kusu).
#
# Jan (Oct 2026): "Ano, myslím tím i rozšíření vršku." Hrac vezme vrsek a taha
# PODEL nej: na tu stranu, kam taha, se vrsek prodlouzi a roh (bocni strana) se
# s nim posune - vyska vystupku zustava stejna. Tah zpet vrsek zase zuzi.
#
#   `side` = +1 znamena stranu ve smeru `d` (doprava), -1 opacnou.
#   `grow` = true vrsek rozsiri, false zuzi.
#
# Vzdy se meni dve bunky: jedna se prida (kousek vrsku) a jedna se z cesty
# vypusti (roh, ktery uz neni potreba) - proto cesta zustava souvisla a delka
# se nemeni.
func widen_run(lane: int, cell: Vector2i, side: int, grow: bool) -> bool:
	var run: Dictionary = run_at(lane, cell)
	if run.is_empty():
		return false
	var cs: Array = lane_cells(lane)
	var n: int = cs.size()
	var a: int = int(run["a"])
	var b: int = int(run["b"])
	var d: Vector2i = run["d"]
	var s: Vector2i = run["s"]
	var out: Array = []
	var added: Array = []
	if side > 0:
		var Rm: Vector2i = cs[b]
		if grow:
			# Za koncem kusu musi cesta jeste pokracovat ve smeru `d` - jinak
			# neni kam roh posunout (cesta by se musela ohne o roh dal).
			if b + 2 >= n or (cs[b + 2] - cs[b + 1]) != d:
				return false
			var add: Vector2i = Rm + d
			out.append_array(cs.slice(0, b + 1))
			out.append(add)
			out.append_array(cs.slice(b + 2, n))
			added.append(add)
		else:
			# Vrsek musi mit aspon 3 bunky - jinak by po zuz... zbyl jednobunkovy
			# "kus", ktery uz vystupek neni.
			if b - a < 2:
				return false
			var back: Vector2i = Rm - d - s
			out.append_array(cs.slice(0, b))
			out.append(back)
			out.append_array(cs.slice(b + 1, n))
			added.append(back)
	else:
		var R0: Vector2i = cs[a]
		if grow:
			# Pred zacatkem kusu musi cesta vest ve smeru `d`
			if a < 2 or (cs[a - 1] - cs[a - 2]) != d:
				return false
			var add2: Vector2i = R0 - d
			out.append_array(cs.slice(0, a - 1))
			out.append(add2)
			out.append_array(cs.slice(a, n))
			added.append(add2)
		else:
			if b - a < 2:
				return false
			var back2: Vector2i = R0 + d - s
			out.append_array(cs.slice(0, a))
			out.append(back2)
			out.append_array(cs.slice(a + 1, n))
			added.append(back2)
	if not _is_simple_path(out):
		return false
	for item in added:
		var c: Vector2i = item
		if not in_bounds(c.x, c.y):
			return false
		if node_at_cell(c) >= 0:
			return false
		for j in range(lane_count()):
			if j == lane:
				continue
			for o in lane_cells(j):
				if o == c:
					return false
	lanes[lane]["cells"] = out
	return true


# ROVNY KUS CESTY POD BUNKOU (bez ohledu na to, co je na jeho koncich).
# Vraci {} nebo {a, b, d}: kus jsou bunky cs[a..b] ve smeru `d`.
#
# Na rozdil od `run_at` (ktery hleda "vystupek", tedy kus s bocnimi stranami
# presne jednou bunkou zpet) bere i kus, ktery ZACINA nebo KONCI V UZLU -
# takovy kus se da posunout i s tim uzlem, takze se da hýbat celou rovnou
# carou (Jan: "Posouvání celých úseku teď funguje maximálně o 2 pozice. Bylo
# by fajn, kdyby s tím šlo hýbat neomezeně.").
#
# Smer se vybira tak, aby kus byl co NEJDELSI (u rohu pod prstem jsou dva
# mozne - jeden je kus, druhy jeho rameno); pri stejne delce vyhrava smer,
# kterym cesta z bunky pokracuje.
func piece_at(lane: int, cell: Vector2i, hint: Vector2i = Vector2i.ZERO) -> Dictionary:
	if lane < 0 or lane >= lane_count():
		return {}
	var cs: Array = lane_cells(lane)
	var n: int = cs.size()
	var i: int = -1
	for k in range(n):
		if cs[k] == cell:
			i = k
			break
	if i < 0:
		return {}
	var here: Vector2i = cs[i]
	var dirs: Array = []
	if i + 1 < n:
		var nxt: Vector2i = cs[i + 1]
		dirs.append(nxt - here)
	if i > 0:
		var prv: Vector2i = cs[i - 1]
		dirs.append(here - prv)
	var best: Dictionary = {}
	for item in dirs:
		var d: Vector2i = item
		if absi(d.x) + absi(d.y) != 1:
			continue
		# `hint` = smer kusu, ktery uz drzime: behem tahu se kus hybe a jeho
		# rameno muze byt delsi nez on - bez tohoto by prst po par krocích
		# chytil rameno a tah by se zastavil.
		if hint != Vector2i.ZERO and d != hint and d != -hint:
			continue
		var a: int = i
		while a > 0 and (cs[a] - cs[a - 1]) == d:
			a -= 1
		var b: int = i
		while b + 1 < n and (cs[b + 1] - cs[b]) == d:
			b += 1
		# Jedna bunka neni kus - neni co posouvat.
		if b - a < 1:
			continue
		if best.is_empty() or (b - a) > int(best["b"]) - int(best["a"]):
			best = {"a": a, "b": b, "d": d}
	return best


# POSUN ROVNEHO KUSU POD BUNKOU O JEDNU BUNKU KOLMO NA NEJ (`p`).
#
# Vsechny bunky kusu se posunou o `p` a na kazdem konci se kus musi znovu
# napojit na zbytek cesty:
#   * konec je ROH (cesta pokracuje bokem): kdyz kus jde VEN z tvaru, vlozi se
#     jedna bunka strany; kdyz jde DOVNITR, jedna bunka strany se vypusti,
#   * konec je UZEL: uzel se posune s kusem - vrati se v "nodes", aby ho editor
#     mohl presunout i s tim, co je na nej napojene.
#
# NIC NEMENI (je to cista geometrie): vraci {"ok", "cells", "nodes"}. Uzel si
# posouva volajici - drzi si tim kontrolu nad celym krokem (kdyz to nepujde,
# krok se vezme zpet).
func move_piece(lane: int, cell: Vector2i, p: Vector2i, hint: Vector2i = Vector2i.ZERO) -> Dictionary:
	var no: Dictionary = {"ok": false, "cells": [], "nodes": []}
	var pc: Dictionary = piece_at(lane, cell, hint)
	if pc.is_empty():
		return no
	var cs: Array = lane_cells(lane)
	var n: int = cs.size()
	var a: int = int(pc["a"])
	var b: int = int(pc["b"])
	var d: Vector2i = pc["d"]
	if absi(p.x) + absi(p.y) != 1:
		return no
	if p.x * d.x + p.y * d.y != 0:
		return no
	var out: Array = []
	var added: Array = []
	var nodes: Array = []
	# LEVA STRANA
	if a == 0:
		var sn: int = lane_start_node(lane)
		if sn < 0:
			return no
		nodes.append({"i": sn, "to": cs[0] + p})
	else:
		var A: Vector2i = cs[a - 1]
		var o: Vector2i = cs[a] - A
		if absi(o.x) + absi(o.y) != 1:
			return no
		if p == o:
			out.append_array(cs.slice(0, a))
			var conn: Vector2i = A + p
			out.append(conn)
			added.append(conn)
		elif p == -o:
			# Kus dosedne na sousedni bunku - ta uz neni potreba.
			out.append_array(cs.slice(0, a - 1))
		else:
			return no
	# KUS SE POSUNE
	for k in range(a, b + 1):
		var c: Vector2i = cs[k] + p
		out.append(c)
		added.append(c)
	# PRAVA STRANA
	if b == n - 1:
		var en: int = lane_end_node(lane)
		if en < 0:
			return no
		for item in nodes:
			if int(item["i"]) == en:
				return no
		nodes.append({"i": en, "to": cs[n - 1] + p})
	else:
		var B: Vector2i = cs[b + 1]
		var ob: Vector2i = cs[b] - B
		if absi(ob.x) + absi(ob.y) != 1:
			return no
		if p == ob:
			var conn2: Vector2i = B + p
			out.append(conn2)
			added.append(conn2)
			out.append_array(cs.slice(b + 1, n))
		elif p == -ob:
			out.append_array(cs.slice(b + 2, n))
		else:
			return no
	if not _is_simple_path(out):
		return no
	for item2 in added:
		var c2: Vector2i = item2
		if not in_bounds(c2.x, c2.y):
			return no
		if node_at_cell(c2) >= 0 and node_at_cell(c2) != _node_at(c2, nodes):
			return no
		for j in range(lane_count()):
			if j == lane:
				continue
			for o2 in lane_cells(j):
				if o2 == c2:
					return no
	return {"ok": true, "cells": out, "nodes": nodes}


# KTERY Z PRESOUVANYCH UZLU SE OCTNE NA TE BUNCE (jinak -1). Bunka, na kterou
# se uzel posouva, je pro nas volna i kdyz je na ni uzel - vždyť ten uzel je
# ten, ktery se hybe.
func _node_at(c: Vector2i, nodes: Array) -> int:
	for item in nodes:
		var to: Vector2i = item["to"]
		if to == c:
			return int(item["i"])
	return -1


# SOUVISLA CESTA BEZ SMYCKY: sousedni bunky a zadna se neopakuje. Posun kusu
# se tim da vyloucit, kdyby mel cestu preklopit sam na sebe.
func _is_simple_path(cells: Array) -> bool:
	for k in range(cells.size()):
		var c: Vector2i = cells[k]
		if k > 0:
			var p: Vector2i = cells[k - 1]
			if absi(c.x - p.x) + absi(c.y - p.y) != 1:
				return false
		for m in range(k):
			if cells[m] == c:
				return false
	return true


func lane_type_color(lane: int) -> Color:
	return Level.value_color(lane_element(lane))


# BARVA PASU KOLEM CESTY: STEJNA BARVA jako cesta, ale SVETLEJSI ODSTIN
# (Jan: "bude mit svetlejsi odstin"). Pas je podbarveni, ne druha cesta -
# proto zustava pruhledny a cesta nad nim je porad to nejjasnejsi.
#
# Barva je tady a ne v kresleni: test se na ni musi moct zeptat a overit,
# ze pas je opravdu svetlejsi nez cesta a ze neni pruhlednejsi nez podklad.
const STRIP_LIGHTEN := 0.45
const STRIP_ALPHA := 0.28


static func strip_color(e: int) -> Color:
	var c: Color = value_color(e)
	var l: Color = c.lerp(Color(1.0, 1.0, 1.0), STRIP_LIGHTEN)
	l.a = STRIP_ALPHA
	return l


# MRIZKA JE VIDET. Driv se kreslila barvou 0.20 (skoro jako podklad desky) a
# hrac v ni nevnimal bunky - Jan: "Mřížku uděláme viditelnější." Barvy jsou
# tady, ne v kresleni: test se na ne muze zeptat primo (a hlida, ze prvni
# radek mrizky neni tmavsi nez podklad desky).
#
# KAZDA CTVRTA CARA JE SVETLEJSI. Neni to dekorace: pole ma 28x14 bunek a bez
# pravidelnejsiho rytmu se v nem neda pocitat, kolik bunek cesta zabira.
const GRID_LINE := Color(0.34, 0.32, 0.28, 0.85)
const GRID_MAJOR := Color(0.46, 0.43, 0.37, 0.95)
const GRID_STEP := 4


# KOLIK MIST NA BONUS MA USEK OPRAVDU (tedy kolik jich lze postavit). Od
# `lane_slot_count` se lisi u useku, kde stavet NELZE (kmen, neutralni usek):
# ta cisla v datech zustavaji (hracuv pocet mist se nesmi pri zmene typu
# ztratit), ale UI je nesmi hlásit - jinak popisek u kmene tvrdi "míst 3",
# zatimco tlacitko vedle "místa 0". Jan: "na kmenu se zobrazuji mista pro
# upgrady, ktera by tam nemela existovat".
func lane_type_name(lane: int) -> String:
	return Level.value_name(lane_element(lane))


# KOLIK MIST NA BONUS TENHLE USEK MA. LEGACY: dnes se veze nestavi na mista
# na useku, ale do PASU kolem cesty (viz `Network.strip_lane`), takze tahle
# hodnota do hry nevstupuje. Zustava jen v DATECH a v kodu levelu, aby se
# stara ulozena mapa dala precist a zapsat presne tak, jak byla - a aby se
# pocet mist neztratil, kdyby se sem nejaka podoba stavby vratila.
func lane_slot_count(lane: int) -> int:
	if lane < 0 or lane >= lanes.size():
		return 0
	return clampi(int(lanes[lane].get("slots", SLOTS)), 0, MAX_SLOTS)


func set_lane_slots(lane: int, n: int) -> void:
	if lane < 0 or lane >= lanes.size():
		return
	lanes[lane]["slots"] = clampi(n, 0, MAX_SLOTS)


func set_lane_element(lane: int, element: int) -> void:
	if lane < 0 or lane >= lanes.size():
		return
	lanes[lane]["elem"] = element


# Usek, ze ktereho poutnici vstupuji do mapy. Odvozeno z grafu (usek ze
# STARTu), ne z priznaku - prislo by o nej pri kazde zmene tvaru mapy.
# Sam o sobe NERIKA nic o poskozeni: to je vec hodnoty useku (KMEN = zadne).
func lane_is_entry(lane: int) -> bool:
	if lane < 0 or lane >= lanes.size():
		return false
	return bool(lanes[lane]["entry"])


func lane_start_node(lane: int) -> int:
	var cs: Array = lane_cells(lane)
	if cs.is_empty():
		return -1
	var c: Vector2i = cs[0]
	return node_at_cell(c)


func lane_end_node(lane: int) -> int:
	var cs: Array = lane_cells(lane)
	if cs.is_empty():
		return -1
	var c: Vector2i = cs[cs.size() - 1]
	return node_at_cell(c)


# Useky, ktere z uzlu VYCHAZEJI (zacina v nem jejich prvni bunka).
func lanes_from(n: int) -> Array:
	var out: Array = []
	for i in range(lanes.size()):
		if lane_start_node(i) == n:
			out.append(i)
	return out


# Useky, ktere do uzlu USTI.
func lanes_into(n: int) -> Array:
	var out: Array = []
	for i in range(lanes.size()):
		if lane_end_node(i) == n:
			out.append(i)
	return out


# Useky, ktere se uzlu dotykaji z jakekoli strany.
func lanes_at(n: int) -> Array:
	var out: Array = []
	for i in range(lanes.size()):
		if lane_start_node(i) == n or lane_end_node(i) == n:
			out.append(i)
	return out


func first_start() -> int:
	for i in range(nodes.size()):
		if int(nodes[i]["kind"]) == START:
			return i
	return -1


# VSECHNY starty. Startu muze byt LIBOVOLNE MNOZSTVI - kazdy je vlastni
# vstup do mapy a hra z nich losuje (Jan: "chyba: mapa musi mit prave jeden
# start (ma 2). To je blbost. Muze mit libovolny pocet startu/vstupu.").
# `first_start()` zustava pro mista, ktera opravdu chteji JEDEN (kresleni
# vstupniho useku v editoru); pravidla (validate, dosazitelnost) se musi
# ptat TOHOHLE seznamu, jinak by druhy vstup zustal mimo kontrolu.
func start_nodes() -> Array:
	var out: Array = []
	for i in range(nodes.size()):
		if int(nodes[i]["kind"]) == START:
			out.append(i)
	return out


func exit_count() -> int:
	var c := 0
	for i in range(nodes.size()):
		if int(nodes[i]["kind"]) == CIL:
			c += 1
	return c


func exit_nodes() -> Array:
	var out: Array = []
	for i in range(nodes.size()):
		if int(nodes[i]["kind"]) == CIL:
			out.append(i)
	return out


# =========================================================================
# PRECHOD UZLEM - jedine misto, kde se rozhoduje, kam poutnik pujde dal
# =========================================================================

# Kolik voleb uzel nabizi. Pro hrace je to pocet vystupu z vyhybky.
func node_choice_count(n: int) -> int:
	return lanes_from(n).size()


# Vystup c. `sel` z uzlu. -1 = nikam (slepota).
func node_choice(n: int, sel: int) -> int:
	var outs: Array = lanes_from(n)
	if sel < 0 or sel >= outs.size():
		return -1
	return int(outs[sel])


# Dalsi usek pri pruchodu uzlem. `sel` je volba hrace pro VYHYBKU;
# start, spojka a uzel zadnou volbu nemaji - maji jeden vystup, takze se
# `sel` ignoruje. -1 = poutnik dosel na konec (vstup do cile).
#
# START vystup MA: poutnici do mapy vstupuji prave tudy, takze se z nej
# odchazi stejne jako ze spojky. Kdyby vracel -1, nikdo by se nikdy
# nerozesel.
func next_lane(n: int, sel: int = 0) -> int:
	var kind: int = node_kind(n)
	if kind == CIL:
		return -1
	if kind == VYHYBKA:
		return node_choice(n, sel)
	return node_choice(n, 0)


# =========================================================================
# ZIVLY V MAPE
# =========================================================================

# JE ZIVEL Z TÉTO MAPY ZABITELNY? Jedine meritko je PROTIKLAD: vez na ceste
# protikladu dava 200 %, a to poutnika (s bonusem) polozi. Jan (Oct 2026):
# "Zrušíme pravidlo, že při přítomnosti neutrální cesty se spawnují všechny
# druhy nepřátel. Budou se zkrátka spawnovat jen ty, co mají protiklad."
#
# NEUTRALNI USEK SE DO TOHOTO ROZHODNUTI NEPOCITA. Seda vez bere sice vsem
# 100 %, ale "neutralni cesta = chodi vsechno" posilalo i zivly, ktere v mape
# nemaji svuj usek - mapa tim ztratila rukopis. Z mista, kde poutnik svuj
# protiklad nema, se neposila (a hra to rekne v hlasce).
#
# KMEN zabit neda: nema pas, vez se u nej postavit neda (a dava 0 %).
func element_killable(e: int) -> bool:
	if e < 0 or e >= Element.COUNT:
		return false
	return present_elements().has(Element.opposite_of(e))


# Je v mape neutralni usek? Seda cesta bere vsem 100 %, takze je to zbran na
# kazdy zivel - ale POSILANI POUTNIKU z toho uz nic nevyvozuje (viz
# `element_killable`): kdo v mape nema svuj protiklad, nechodi.
func has_neutral_lane() -> bool:
	for i in range(lanes.size()):
		if lane_element(i) == NEUTRAL:
			return true
	return false


# Zivly, ktere se v teto mape posilaji. Neni to kosmetika: poutnik, jehoz
# v mape NENI cim zabit, je ztraceny zivot bez sance zasahnout. Posilame proto
# JEN zivly, ktere maji v mape svuj usek A svuj PROTIKLAD (viz
# `element_killable`). Zivly, ktere v mape nejsou vubec, do hry nepatri - mapa
# ma svuj "rukopis" (Jan: "mapa, ktera ma jen vodu a ohen, posila jen vodni
# a ohnive poutniky"). Ostatni se vynechavaji a hra to rekne v hlasce na
# zacatku kola.
#
# NEUTRALNI CESTA DO TOHOTO SEZNAMU NIC NEPRIDAVA (Jan: "Budou se zkrátka
# spawnovat jen ty, co mají protiklad."). Mapa z neutralnich cest sama o sobe
# neposila nikoho.
func spawn_elements() -> Array:
	var out: Array = []
	for e in present_elements():
		if element_killable(e):
			out.append(e)
	out.sort()
	return out


# Zivly, ktere v mape JSOU, ale neda se z nich posilat: neni cim je zabit.
# Hraje se to hraci (je to cely duvod, proc nektere poutniky nevidi). Do
# seznamu patri JEN zivly, ktere v mape opravdu maji svuj usek - hlasit
# "Vzduch nemá protiklad" na mape bez vzduchu by bylo matouci.
func unkillable_elements() -> Array:
	var out: Array = []
	for e in present_elements():
		if not element_killable(e):
			out.append(e)
	return out


# Zivly, ktere se v mape vubec vyskytuji (i kdyz se z nich treba neposila).
func present_elements() -> Array:
	var seen: Array = []
	for i in range(lanes.size()):
		var e: int = lane_element(i)
		# Neutralni usek ani kmen nejsou element - z nich se posilat nesmi.
		if e < 0:
			continue
		if not seen.has(e):
			seen.append(e)
	seen.sort()
	return seen


# =========================================================================
# ROZMERY
# =========================================================================

func cell_center(c: int, r: int) -> Vector2:
	var cc: int = maxi(cols, 1)
	var rr: int = maxi(rows, 1)
	return Vector2((float(c) + 0.5) / float(cc), (float(r) + 0.5) / float(rr))


# Sirka/vyska mrizky v normalizovanych jednotkach - Network z ni pocita
# velikost bunky. Mrizka se do areny vejde CELA (bunka ctvercova), takze
# na sirokem displeji zustanou po stranach okraje. To je zamer.
func grid_aspect() -> float:
	return float(cols) / float(maxi(rows, 1))


func in_bounds(c: int, r: int) -> bool:
	return c >= 0 and r >= 0 and c < cols and r < rows


# =========================================================================
# KOPIE
# =========================================================================

func clone() -> Level:
	var lv := Level.new()
	lv.name = name
	lv.cols = cols
	lv.rows = rows
	lv.speed = speed
	lv.spawn = spawn
	lv.round_time = round_time
	lv.lives = lives
	lv.gold = gold
	lv.last_error = last_error
	for n in nodes:
		lv.nodes.append({"c": int(n["c"]), "r": int(n["r"]), "kind": int(n["kind"])})
	for ln in lanes:
		var cells: Array = []
		for cell in ln["cells"]:
			var v: Vector2i = cell
			cells.append(Vector2i(v.x, v.y))
		lv.lanes.append({
			"cells": cells,
			"elem": int(ln["elem"]),
			"entry": bool(ln["entry"]),
			"slots": clampi(int(ln.get("slots", SLOTS)), 0, MAX_SLOTS),
		})
	return lv


# =========================================================================
# KONTROLA MAPY
#
# Vsechno, co kdy mohlo vzniknout jen rukou, se kontroluje tady. Editor
# a nacteni kodu se ptaji teto jedne funkce - kdyby si kazdy kontroloval
# sve, casem se rozejdou a mapa, ktera se v editoru tvari dobre, se ve
# hre neda dohrat.
#
# Navratova hodnota je seznam ceskych vet - prazdny = mapa je v poradku.
# =========================================================================

func validate() -> Array:
	var errs: Array = []
	var starts: int = 0
	for n in range(nodes.size()):
		if node_kind(n) == START:
			starts += 1
	# STARTU MUZE BYT LIBOVOLNE MNOZSTVI. Driv tu stalo "prave jeden" a
	# druhy vstup se nedal vyexportovat, i kdyz graf s nim pocita
	# (`Network` ma seznam `entry_lanes`, hra z nich losuje). Jedine, co
	# plati, je "aspon jeden" - bez startu nema poutnik kudy vejit.
	if starts < 1:
		errs.append("mapa nemá žádný start.")
	if exit_count() < 1:
		errs.append("mapa nemá žádný cíl.")

	# --- rozmery a poloha
	for n in range(nodes.size()):
		var c: Vector2i = node_cell(n)
		if not in_bounds(c.x, c.y):
			errs.append("uzel %d leží mimo mřížku." % n)
	if nodes.size() > cols * rows:
		errs.append("uzlů je víc než buněk.")

	# --- kolik ma ktery uzel vstupu a vystupu
	for n in range(nodes.size()):
		var ins: int = lanes_into(n).size()
		var outs: int = lanes_from(n).size()
		var kn: String = kind_name(node_kind(n))
		match node_kind(n):
			START:
				if ins != 0:
					errs.append("start má %d vstupních úseků (má jich být 0)." % ins)
				if outs != 1:
					errs.append("start má %d výstupních úseků (má být 1)." % outs)
			CIL:
				if outs != 0:
					errs.append("cíl má %d výstupních úseků (má jich být 0)." % outs)
				if ins < 1:
					errs.append("do cíle nevede žádný úsek.")
			VYHYBKA:
				if ins != 1:
					errs.append("výhybka má %d vstupních úseků (má být 1)." % ins)
				if outs < 2:
					errs.append("výhybka má %d výstupních úseků (mají být aspoň 2)." % outs)
			SPOJKA:
				if ins < 2:
					errs.append("spojka má %d vstupních úseků (mají být aspoň 2)." % ins)
				if outs != 1:
					errs.append("spojka má %d výstupních úseků (má být 1)." % outs)
			UZEL:
				if ins != 1 or outs != 1:
					errs.append("uzel %d má %d vstupů a %d výstupů (má být 1 a 1)." % [n, ins, outs])
			_:
				errs.append("uzel %d má neznámý druh %s." % [n, kn])

	# --- kazdy usek: souvisla cesta po mrizce, z uzlu do uzlu
	var used: Dictionary = {}
	for i in range(lanes.size()):
		var cs: Array = lane_cells(i)
		if cs.size() < 2:
			errs.append("úsek %d je kratší než jedna buňka." % i)
			continue
		var sn: int = lane_start_node(i)
		var en: int = lane_end_node(i)
		if sn < 0:
			errs.append("úsek %d nezačíná v uzlu." % i)
		if en < 0:
			errs.append("úsek %d nekončí v uzlu." % i)
		# Mista na bonus jsou DATA, ne konstanta - proto se kontroluji tady
		# a ne pocitanim nekde v kresleni. Hodnota mimo rozsah znamena kod,
		# ktery si nekdo vymyslel rucne.
		var raw_slots: int = int(lanes[i].get("slots", SLOTS))
		if raw_slots < 0 or raw_slots > MAX_SLOTS:
			errs.append("úsek %d má %d míst na bonus (0 až %d)." % [i, raw_slots, MAX_SLOTS])
		if sn >= 0 and sn == en:
			errs.append("úsek %d se vrací do stejného uzlu." % i)
		for k in range(cs.size()):
			var cell: Vector2i = cs[k]
			if not in_bounds(cell.x, cell.y):
				errs.append("úsek %d vede mimo mřížku." % i)
				break
			# sousedni bunky se lisi presne v jedne ose o 1 - jinak by
			# se cesta lámala šikmo nebo skákala
			if k > 0:
				var prev: Vector2i = cs[k - 1]
				var dx: int = absi(cell.x - prev.x)
				var dy: int = absi(cell.y - prev.y)
				if dx + dy != 1:
					errs.append("úsek %d se v buňce %d láme šikmo nebo skáče." % [i, k])
					break
			# bunka uzlu smi byt sdilena (je to uzel) - ostatni ne
			if node_at_cell(cell) >= 0:
				continue
			if used.has(cell):
				errs.append("úsek %d se kříží s úsekem %d v buňce %d,%d." % [
					i, int(used[cell]), cell.x, cell.y])
				break
			used[cell] = i
		if sn >= 0 and sn == en:
			continue
		# bunky uzlu nesmi lezet UPROSTRED useku - usek by se musel rozdelit
		for k in range(1, maxi(cs.size() - 1, 1)):
			var mid: Vector2i = cs[k]
			var mn: int = node_at_cell(mid)
			if mn >= 0 and k != cs.size() - 1:
				errs.append("úsek %d prochází uzlem %d, aniž by tam končil." % [i, mn])
				break

	# --- dosazitelnost: z KAZDEHO startu se musi dat dojit na kazdy usek i cil
	# Startu muze byt vic, takze se hleda ze vsech najednou (multi-source BFS).
	# Ptat se jen na prvni start by u druheho vstupu tise propustilo
	# nedosazitelny kus mapy.
	var start_list: Array = start_nodes()
	if not start_list.is_empty():
		var seen_nodes: Dictionary = {}
		var seen_lanes: Dictionary = {}
		var queue: Array = []
		for s in start_list:
			seen_nodes[int(s)] = true
			queue.append(int(s))
		while not queue.is_empty():
			var n: int = int(queue.pop_front())
			for ln in lanes_from(n):
				var l: int = int(ln)
				if seen_lanes.has(l):
					continue
				seen_lanes[l] = true
				var en: int = lane_end_node(l)
				if en >= 0 and not seen_nodes.has(en):
					seen_nodes[en] = true
					queue.append(en)
		for i in range(lanes.size()):
			if not seen_lanes.has(i):
				errs.append("úsek %d se nedá ze startu vůbec dojít." % i)
		for n in range(nodes.size()):
			if node_kind(n) == CIL and not seen_nodes.has(n):
				errs.append("do cíle %d se nedá dojít." % n)
				break
		# ze zadneho useku nesmi vest slepa ulicka - kazdy musi mit
		# cestu do nejakeho cile
		var reaches: Dictionary = {}
		for i in range(lanes.size()):
			if not _reaches_exit(i):
				errs.append("úsek %d nevede do žádného cíle." % i)
				break
	return errs


# Dá se z tohohle useku vubec dojit k cili?
func _reaches_exit(lane: int) -> bool:
	var seen: Dictionary = {}
	var stack: Array = [lane]
	while not stack.is_empty():
		var l: int = int(stack.pop_back())
		if seen.has(l):
			continue
		seen[l] = true
		var en: int = lane_end_node(l)
		if en < 0:
			continue
		if node_kind(en) == CIL:
			return true
		for ln in lanes_from(en):
			stack.append(int(ln))
	return false


# =========================================================================
# SERIALIZACE
#
# Kod je to, jak level cestuje z telefonu - Jan ho vlozi do zpravy a
# vlozi zpatky. Jedna minifikovana radka, zadne odsazovani.
# =========================================================================

func to_dict() -> Dictionary:
	var ns: Array = []
	for n in nodes:
		ns.append([int(n["c"]), int(n["r"]), int(n["kind"])])
	var ls: Array = []
	for ln in lanes:
		var cells: Array = []
		var cs: Array = ln["cells"]
		for cell in cs:
			var v: Vector2i = cell
			cells.append([v.x, v.y])
		# CTVRTY PRVEK JE POCET MIST NA BONUS a pise se JEN KDYBY SE LISI
		# od vychoziho. Zakladni deska i vsechny drive ulozene levely tak
		# maji kod PRESNE stejny jako predtim - a stara ulozena mapa se
		# nacte (ctvrty prvek chybi -> vychozi hodnota).
		var row: Array = [int(ln["elem"]), 1 if bool(ln["entry"]) else 0, cells]
		var sl: int = clampi(int(ln.get("slots", SLOTS)), 0, MAX_SLOTS)
		if sl != SLOTS:
			row.append(sl)
		ls.append(row)
	return {
		"v": 2,
		"n": name,
		"w": cols,
		"h": rows,
		"s": speed,
		"p": spawn,
		"rt": round_time,
		"l": lives,
		"g": gold,
		"u": ns,
		"e": ls,
	}


static func from_dict(d: Dictionary) -> Level:
	var lv := Level.new()
	lv.name = str(d.get("n", ""))
	lv.cols = int(d.get("w", COLS))
	lv.rows = int(d.get("h", ROWS))
	lv.speed = float(d.get("s", BASE_SPEED))
	lv.spawn = float(d.get("p", BASE_SPAWN))
	lv.round_time = float(d.get("rt", BASE_ROUND))
	lv.lives = int(d.get("l", BASE_LIVES))
	lv.gold = int(d.get("g", BASE_GOLD))
	for raw in d.get("u", []):
		var a: Array = raw
		if a.size() < 3:
			continue
		lv.nodes.append({"c": int(a[0]), "r": int(a[1]), "kind": int(a[2])})
	for raw in d.get("e", []):
		var a: Array = raw
		if a.size() < 3:
			continue
		var cells: Array = []
		for rc in a[2]:
			var b: Array = rc
			if b.size() < 2:
				continue
			cells.append(Vector2i(int(b[0]), int(b[1])))
		var slots: int = SLOTS
		if a.size() >= 4:
			slots = clampi(int(a[3]), 0, MAX_SLOTS)
		lv.lanes.append({"cells": cells, "elem": int(a[0]), "entry": int(a[1]) == 1,
			"slots": slots})
	return lv


func to_json() -> String:
	return JSON.stringify(to_dict())


static func from_json(text: String) -> Level:
	var d = JSON.parse_string(text)
	if typeof(d) != TYPE_DICTIONARY:
		return null
	var lv := from_dict(d)
	return lv


func to_code() -> String:
	return "ZILY2;" + to_json()


static func from_code(code: String) -> Level:
	var t: String = code.strip_edges()
	if not t.begins_with("ZILY2;"):
		return null
	var lv := from_json(t.substr(6))
	if lv == null:
		return null
	if not lv.validate().is_empty():
		return null
	return lv


# NACTENI VLASTNIHO ROZPRACOVANEHO LEVELU - BEZ KONTROLY MAPY.
#
# `from_code` je pro kod z CIZIHO zdroje (vlozeny, poslany), takze u nej ma
# smysl pozadovat, aby byl v poradku. Jenze `load_from_disk` ho pouzival taky
# - a editor uklada level po KAZDE zmene, klidne i rozepsany (bez cile, s
# cestou, ktera nikam nevede). Takovy level se pak "nepodarilo otevrit":
# prace byla v souboru, ale hrac se k ni nedostal. Jan (Oct 2026):
# "Načítání, ukládání a vytváření nových levelů nefunguje moc dobře. Některé
# nejdou otevřít."
#
# Proto se pri nacitani z disku kontroluje JEN to, ze je to nas format.
static func from_code_unchecked(code: String) -> Level:
	var t: String = code.strip_edges()
	if not t.begins_with("ZILY2;"):
		return null
	return from_json(t.substr(6))


# =========================================================================
# UKLADANI - lokalne, na server se neposila nic
# =========================================================================

# Staticka proto, ze ji pouziva i staticka saved_keys().
static func storage_dir() -> String:
	return "user://levels/"


func storage_key() -> String:
	var s: String = name if name != "" else "vlastni"
	var out := ""
	for ch in s:
		if ch == "/" or ch == "\\" or ch == ":":
			out += "_"
		else:
			out += ch
	if out == "":
		out = "vlastni"
	return out


func save() -> bool:
	if name == "": 
		name = "vlastni"
	DirAccess.make_dir_recursive_absolute(storage_dir())
	var f := FileAccess.open(storage_dir() + storage_key() + ".zily", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(to_code())
	f.close()
	return true


func load_from_disk(key: String) -> bool:
	var path: String = storage_dir() + key + ".zily"
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text: String = f.get_as_text()
	f.close()
	var lv := from_code_unchecked(text)
	if lv == null:
		return false
	# JMENO = JMENO SOUBORU. Kdyby zustalo jmeno z obsahu (klidne prazdne),
	# ulozilo by se to podruhe do JINEHO souboru a v seznamu by zustala
	# stara verze - hrac by mel dve mapy a ta, kterou upravoval, by se
	# neukladala. Jedno jmeno, jeden soubor.
	name = key if key != "" else lv.name
	cols = lv.cols
	rows = lv.rows
	speed = lv.speed
	spawn = lv.spawn
	lives = lv.lives
	gold = lv.gold
	nodes = lv.nodes
	lanes = lv.lanes
	return true


static func saved_keys() -> Array:
	var out: Array = []
	var d := DirAccess.open(storage_dir())
	if d == null:
		return out
	d.list_dir_begin()
	var f: String = d.get_next()
	while f != "":
		if not d.current_is_dir() and f.ends_with(".zily"):
			out.append(f.substr(0, f.length() - 5))
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


# =========================================================================
# POMOCNIK PRO STAVBU - pouziva ho zakladni deska i testy
# =========================================================================

func add_node(c: int, r: int, kind: int) -> int:
	nodes.append({"c": c, "r": r, "kind": kind})
	return nodes.size() - 1


# Nakresli usek z uzlu `a` do uzlu `b` po zadanych smerech.
# `dirs` je retezec "U R D L" - kde se cesta ohne. Zapisuje se bez pocatecni
# bunky (ta je bunka uzlu `a`) a bez koncove (ta je bunka uzlu `b`).
func add_lane(a: int, b: int, dirs: String, elem: int) -> int:
	var cells: Array = []
	var cur: Vector2i = node_cell(a)
	cells.append(cur)
	for ch in dirs:
		match ch:
			"U":
				cur = Vector2i(cur.x, cur.y - 1)
			"D":
				cur = Vector2i(cur.x, cur.y + 1)
			"L":
				cur = Vector2i(cur.x - 1, cur.y)
			"R":
				cur = Vector2i(cur.x + 1, cur.y)
			_:
				continue
		cells.append(cur)
	lanes.append({"cells": cells, "elem": elem, "entry": false, "slots": SLOTS})
	return lanes.size() - 1


# =========================================================================
# ZAKLADNI DESKA - na ni se kalibruje obtiznost
# =========================================================================

static func base() -> Level:
	var lv := Level.new()
	lv.name = "zakladni"
	# START vlevo, dve vyhybky v sérii, pet cílu vpravo.
	#
	#   rada 1  ohen     (6,1) --------------------> (21,1)
	#   rada 4                 voda (12,4) --------> (21,4)
	#   rada 7  start (1,7) -> j1 (6,7) -> j2 (12,7) - neutr ---> (21,7)
	#   rada 10                zeme (12,10) -------> (21,10)
	#   rada 13 vzduch   (6,13) -------------------> (21,13)
	#
	# DESKA JE PREPOCTENA NA HUSTSI MRIZKU 28x14 (puvodne 20x10, krok 0.4).
	# Drzi se stejnych POMERU, takze i vsechna vyladena cisla zustavaji.
	#
	# PROC JSOU ZIVLY PREROVANE PROTI PUVODNI DESCE. Vez ma ctvercovy dosah
	# 2 bunky, takze utoci na cesty, ktere jsou od ni do 2 radku - a pas
	# u cesty je 1 bunku od ni. Aby na sebe cesty vubec dosahly, musi byt
	# PROTIKLADY VEDLE SEBE:
	#
	#   * vez u ohnive cesty (rada 2) dosahne na radu 4, tedy na vodu,
	#   * vez u vodni cesty (rada 3) dosahne na radu 1, tedy na ohen,
	#   * vez u zemske cesty (rada 11) dosahne na radu 13, tedy na vzduch,
	#   * vez u vzduchove cesty (rada 12) dosahne na radu 10, tedy na zemi.
	#
	# Na puvodni desce (ohen 1, zeme 4, neutral 7, vzduch 10, voda 13) lezely
	# protiklady 12 radku od sebe a ZADNA vez nedosahla na svuj protiklad -
	# hra by nemela cim zabijet. Rada 7 zustava neutralni: sedive veze
	# uprostred berou vsem 100 % a kryji obe vnitrni cesty.
	#
	# Poradi je dane tim, aby se cesty NEKRIZILY: kdo odbocuje vys, musi
	# odbocit drive (nalevo), a sestup zpet dolu ma vlastni sloupec.
	# Vsechny ctyri zivly + neutralni usek - na te same desce se da
	# kalibrovat cela matice poskozeni.
	var start := lv.add_node(1, 7, START)
	var j1 := lv.add_node(6, 7, VYHYBKA)
	# Druha vyhybka je na 12, ne na 11 (presne 11.2): usek mezi vyhybkami je
	# pak 6 bunek, tedy stejne siroky jako predtim (4 z 20 = 0.20). Pri 5
	# bunkach vysel uzsi nez driv a mista na nem se prerusovala (odhalil to
	# test rozlozeni) - zaokrouhleni na bunku se musi drzet POMERU.
	var j2 := lv.add_node(12, 7, VYHYBKA)
	var e_fire := lv.add_node(21, 1, CIL)
	var e_water := lv.add_node(21, 4, CIL)
	var e_neutral := lv.add_node(21, 7, CIL)
	var e_earth := lv.add_node(21, 10, CIL)
	var e_air := lv.add_node(21, 13, CIL)

	# VSTUPNI USEK JE KMEN: kresli se sedy a jeho vez bere vsem 100 %.
	# Hrac po nem teprve prichazi, takze by kazda rana byla zdarma; dnes
	# ale rany dava vez, ne cesta, takze sedivy pas u vstupu je prvni
	# misto, kde se da stavet.
	#
	# Smery se skladaji z opakovani, ne rucne: u hustsi mrizky se do
	# retezce "U U U" snadno napise o pismeno min a cesta pak minne
	# skonci o bunku vedle (tichy posun celeho levelu).
	lv.add_lane(start, j1, "R".repeat(5), KMEN)
	lv.add_lane(j1, e_fire, "U".repeat(6) + "R".repeat(15), Element.FIRE)
	lv.add_lane(j1, j2, "R".repeat(6), NEUTRAL)
	lv.add_lane(j1, e_air, "D".repeat(6) + "R".repeat(15), Element.AIR)
	lv.add_lane(j2, e_water, "U".repeat(3) + "R".repeat(9), Element.WATER)
	lv.add_lane(j2, e_earth, "D".repeat(3) + "R".repeat(9), Element.EARTH)
	lv.add_lane(j2, e_neutral, "R".repeat(9), NEUTRAL)

	for i in range(lv.lanes.size()):
		var ln: Dictionary = lv.lanes[i]
		ln["entry"] = lv.lane_start_node(i) == start
	return lv
