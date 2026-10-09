class_name Level
extends RefCounted

# LEVEL. Jedno jezero dat: koleje (useky), jejich tvary, elementy, vystupy
# a obtiznost. Hra, testy i EDITOR pracuji s timhle jedinym objektem a
# Network z nej postavi geometrii.
#
# SOURADNICE JSOU NORMALIZOVANE (0..1 v ose hraci plochy), takze level se sam
# roztahne na displej hrace - a stejny level vypada na telefonu i na monitoru.
#
# Kdyz level chybi, pouzije se ZAKLADNI DESKA (base()) - presne ta, na ktere
# je hra vyladena. Je to jen level mezi ostatnimi, zadna vyjimka v kodu.

const NEUTRAL := -1
const DEFAULT_NAME := "vlastni"
const MAX_LANES := 7
const MIN_LANES := 2

# Pas, do ktereho se mrizka kolejí rozmistuje. Nahore je HUD, dole okraj
# displeje; mezi tim se radky VYSTREDI - kdyz je kolejí min, drzi se u sebe
# ve stredu a kdyz vic, mezera se zmensi. Diky tomu se prida kolej, aniž by
# se vsechny ostatni posunuly.
const TOP := 0.05
const BOTTOM := 0.93

# --- ZAKLADNI DESKA -------------------------------------------------------
# Vsechno, co bylo driv natvrdo v Network. Je to zakladni level a zaroven
# zakladni deska balancu: na ni se ladi hratelnost, ne na novych levelech.
const BASE_LANE_ELEMENTS := [0, 1, 2, 3, NEUTRAL]
const BASE_EXITS := [0, 0, 1, 2, 3]
const BASE_EXIT_ROWS := [0, 1, 3, 4]
# Rozestup pruhu. Byl 0.175; Jan chtel mezi kolejemi vic mista, proto 0.22.
# Hlida to test (mista na bonusy se nesmi prekryvat) a test_layout na
# 14 rozlisenich.
const BASE_SPREAD := 0.22
const BASE_BAND0 := 0.40
const BASE_BAND1 := 0.80
const BASE_EXIT_X := 0.945
const BASE_DIVERT := 0.80

# Obtiznost. Cisla jsou zakladni deska; level si je muze prepsat.
const BASE_ZONE_DMG := 30.0
const BASE_SPEED := 52.0
# Mezera mezi poutniky v sekundach. Byla 1.05; Jan chtel mezi nimi vic
# mista, proto 1.35 (poutnici jsou navic vetsi, takze svetla mezera mezi
# nimi se zmensila - 1.35 ji vraci zpet).
const BASE_SPAWN := 1.35
const BASE_LIVES := 12
const BASE_GOLD := 260

# Krok, o ktery se hybou rucky v editoru.
const SPREAD_STEP := 0.01
const ZONE_STEP := 2.0
const SPEED_STEP := 2.0
const SPAWN_STEP := 0.05
const DIVERTS := [0.62, 0.72, 0.80, 0.88]

var name: String = DEFAULT_NAME
# Koleje. Kazda je slovnik:
#   el       - element (0..3) nebo NEUTRAL (-1)
#   exit     - index do exits
#   harmless - kdyz true, usek NEDAVA ZADNE poskozeni (cesta bez ran)
#   divert   - podil delky rovneho useku, kde se kolej ohne k vystupu
#   row      - radek v mrizce (pocita ho relayout(), needituje se)
var lanes: Array = []
# Vystupy z mapy. Normalizovane souradnice [x, y]. Vystup je dira v mape -
# nema element a nikdo ho "nevlastni".
var exits: Array = []
var spread: float = BASE_SPREAD
var band0: float = BASE_BAND0
var band1: float = BASE_BAND1
var exit_x: float = BASE_EXIT_X
var zone_dmg: float = BASE_ZONE_DMG
var speed: float = BASE_SPEED
var spawn: float = BASE_SPAWN
var lives: int = BASE_LIVES
var gold: int = BASE_GOLD


func lane_count() -> int:
	return lanes.size()


func el_of(lane: int) -> int:
	var l: Dictionary = lanes[lane]
	return int(l["el"])


func exit_of(lane: int) -> int:
	var l: Dictionary = lanes[lane]
	return int(l["exit"])


func is_neutral(lane: int) -> bool:
	return el_of(lane) == NEUTRAL


# Na neutralni usek nema smysl stavet - uz bere vsem stejne.
func accepts(lane: int, element: int) -> bool:
	if is_neutral(lane):
		return false
	return element == el_of(lane)


# Sirka useku v podilu delky rovneho useku, kde se ohne k vystupu.
func divert_of(lane: int) -> float:
	var l: Dictionary = lanes[lane]
	return float(l.get("divert", BASE_DIVERT))


# Uhel, pod kterym se kolej ohne k vystupu, v normalizovanych souradnicich.
# Geometrii z toho stavi Network - editor si ZADNOU vlastni kopii nedrzi,
# jinak by se rozešly a uložený level by nebyl ten, který hráč viděl.
func divert_x(lane: int) -> float:
	return band0 + divert_of(lane) * (band1 - band0)


# Kmen je prvni cesta v mape: vede do vyhybky a NEDAVA ZADNE POSKOZENI.
# Jeho tvar neni level - kazda mapa ma prave jeden, stejny - ale jeho
# VIDITELNOST je vec hry: kdyz se prestane kreslit, hrac vidi, jak poutnici
# jdou do vyhybky odnikud. Hlida to test_layout.
func row_of(lane: int) -> float:
	var l: Dictionary = lanes[lane]
	return float(l.get("row", TOP))


func exit_row(idx: int) -> float:
	var e: Array = exits[clampi(idx, 0, exits.size() - 1)]
	return float(e[1])


# Prepocte tvary vsech kolejí z jejich specifikace (pocet, mezera, vystup,
# divert). Editor meni jen specifikaci a tvary se do ni promitnou - kdyby si
# drzel vlastni kopii geometrie, rozejdou se a level by se ulozil jiny,
# nez jaky hrac videl.
#
# RADKY SE VYSTREDI: pri peti kolejich je mezera presne `spread`, ale pri
# trech se stejna mezera neroztahne pres celou plochu - mrizka zustane
# uprostred. Jinak by pridani koleje posunulo vsechny ostatni.
func relayout() -> void:
	var n: int = maxi(lanes.size(), 1)
	var gap: float = spread
	var span: float = gap * float(n - 1)
	if span > BOTTOM - TOP:
		gap = (BOTTOM - TOP) / float(maxi(n - 1, 1))
		span = gap * float(n - 1)
	var y0: float = TOP + (BOTTOM - TOP - span) * 0.5
	for i in range(lanes.size()):
		var l: Dictionary = lanes[i]
		l["row"] = y0 + gap * float(i)
		lanes[i] = l
	# Vystupy si drzi radek, ktery je v mrizce nejbliz sve podlaze - vystup
	# nema "vlastni" radek, je to dira v mape.
	var used := {}
	for i in range(lanes.size()):
		used[exit_of(i)] = true
	var keys: Array = used.keys()
	keys.sort()
	for k in range(keys.size()):
		var idx: int = int(keys[k])
		exits[idx] = [exit_x, y0 + gap * float(mini(idx, n - 1))]


func add_lane() -> bool:
	if lanes.size() >= MAX_LANES:
		return false
	# Novy usek dostane element, ktery v mape jeste chybi; kdyz jsou vsechny
	# ctyri, je neutralni. Takze nova kolej nikdy nerozbije matici zivlu.
	var seen := {}
	for i in range(lanes.size()):
		seen[el_of(i)] = true
	var el: int = NEUTRAL
	for e in range(Element.COUNT):
		if not seen.has(e):
			el = e
			break
	# Vystup, ktery jeste nikdo nepouziva; kdyz jsou vsechny obsazene,
	# pouzije se posledni (dve koleje se tak sbihati do jednoho vystupu).
	var exit: int = exits.size() - 1
	for i in range(exits.size()):
		if not _exit_used(i):
			exit = i
			break
	lanes.append({"el": el, "exit": exit, "divert": BASE_DIVERT})
	relayout()
	return true


func remove_lane(at: int = -1) -> bool:
	if lanes.size() <= MIN_LANES:
		return false
	var i: int = at
	if i < 0:
		i = lanes.size() - 1
	if i < 0 or i >= lanes.size():
		return false
	lanes.remove_at(i)
	relayout()
	return true


func _exit_used(idx: int) -> bool:
	for i in range(lanes.size()):
		if exit_of(i) == idx:
			return true
	return false


# ---------------------------------------------------------------- zakladni

static func base() -> Level:
	var l := Level.new()
	l.name = "zakladni"
	for i in range(BASE_LANE_ELEMENTS.size()):
		l.lanes.append({
			"el": int(BASE_LANE_ELEMENTS[i]),
			"exit": int(BASE_EXITS[i]),
			"divert": BASE_DIVERT,
		})
	l.exits = []
	for r in BASE_EXIT_ROWS:
		l.exits.append([BASE_EXIT_X, TOP])
	l.relayout()
	return l


func clone() -> Level:
	return Level.from_dict(to_dict())


# ---------------------------------------------------------------- data

func to_dict() -> Dictionary:
	# "row" se NEEDITUJE: pocita ho relayout() z poctu kolejí a mezery.
	# V souboru by byl jen balast a kod levelu by se zbytecne prodlouzil -
	# pritom se musi vejit do jedne rady Telegramu.
	var brief: Array = []
	for i in range(lanes.size()):
		var l: Dictionary = lanes[i]
		brief.append({
			"el": int(l["el"]),
			"exit": int(l["exit"]),
			"divert": float(l.get("divert", BASE_DIVERT)),
		})
	return {
		"name": name,
		"lanes": brief,
		"exits": exits.duplicate(true),
		"spread": spread,
		"band0": band0,
		"band1": band1,
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
		l.lanes.append({
			"el": int(m.get("el", NEUTRAL)),
			"exit": int(m.get("exit", 0)),
			"divert": float(m.get("divert", BASE_DIVERT)),
			"row": float(m.get("row", TOP)),
		})
	if l.lanes.is_empty():
		return Level.base()
	var ex: Array = d.get("exits", [])
	for item in ex:
		var p: Array = item
		l.exits.append([float(p[0]), float(p[1])])
	if l.exits.is_empty():
		l.exits.append([BASE_EXIT_X, TOP])
	l.spread = float(d.get("spread", BASE_SPREAD))
	l.band0 = float(d.get("band0", BASE_BAND0))
	l.band1 = float(d.get("band1", BASE_BAND1))
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
# se pozná a necte se naslepo.
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


# Rucky se daji utect mimo rozumne meze; level se po kazde zmene srovna,
# aby se z nej nedal vyrobit level, ktery se nevejde na displej.
func clamp_all() -> void:
	spread = clampf(spread, 0.06, 0.30)
	band0 = clampf(band0, 0.28, 0.70)
	band1 = clampf(band1, band0 + 0.06, 0.92)
	exit_x = clampf(exit_x, band1 + 0.04, 0.99)
	zone_dmg = clampf(zone_dmg, 10.0, 90.0)
	speed = clampf(speed, 20.0, 120.0)
	spawn = clampf(spawn, 0.6, 3.0)
	lives = clampi(lives, 3, 40)
	gold = clampi(gold, 0, 5000)
	for i in range(lanes.size()):
		var l: Dictionary = lanes[i]
		l["el"] = clampi(int(l["el"]), NEUTRAL, Element.COUNT - 1)
		l["exit"] = clampi(int(l["exit"]), 0, maxi(exits.size() - 1, 0))
		l["divert"] = clampf(float(l.get("divert", BASE_DIVERT)), 0.0, 0.98)
		lanes[i] = l


# ---------------------------------------------------------------- ulozeni

# Levely se ukladaji jako JSON. Ve webovem exportu do localStorage (aby
# hrac o svou praci neprisel zavrenim panelu), na desktopu do user://.
# Cteni i zapis jsou synchronni, takze k nim nepotrebujeme zadny callback.
const WEB_PREFIX := "zily.level."
const DIR := "user://levels"
const INDEX_KEY := "zily.levels"


func storage_key() -> String:
	return WEB_PREFIX + name


static func _web() -> Object:
	if not OS.has_feature("web"):
		return null
	return Engine.get_singleton("JavaScriptBridge")


func save() -> bool:
	var text: String = to_json()
	var jb: Object = _web()
	if jb != null:
		jb.call("eval",
			"localStorage.setItem(%s, %s)" % [JSON.stringify(storage_key()), JSON.stringify(text)],
			false)
		_remember_web(str(name))
		return true
	DirAccess.make_dir_recursive_absolute(DIR)
	var f: FileAccess = FileAccess.open(DIR + "/" + name + ".json", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	_remember_disk(str(name))
	return true


static func load_named(n: String) -> Level:
	var jb: Object = _web()
	if jb != null:
		var t: Variant = jb.call("eval",
			"localStorage.getItem(%s)" % JSON.stringify(WEB_PREFIX + n), false)
		if typeof(t) == TYPE_STRING and not str(t).is_empty():
			var lv := Level.from_json(str(t))
			lv.name = n
			return lv
		return Level.base()
	var f: FileAccess = FileAccess.open(DIR + "/" + n + ".json", FileAccess.READ)
	if f == null:
		return Level.base()
	var text: String = f.get_as_text()
	f.close()
	var lv2 := Level.from_json(text)
	lv2.name = n
	return lv2


func _remember_web(n: String) -> void:
	var jb: Object = _web()
	if jb == null:
		return
	jb.call("eval", "(function(){var k=%s;var l=JSON.parse(localStorage.getItem(k)||'[]');" % INDEX_KEY +
		"if(l.indexOf(%s)<0){l.push(%s);localStorage.setItem(k,JSON.stringify(l));}})()" % [
			JSON.stringify(n), JSON.stringify(n)], false)


func _remember_disk(n: String) -> void:
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


# Seznam ulozenych levelu. Pouziva ho editor v pickeru.
static func saved_names() -> Array:
	var out: Array = []
	var jb: Object = _web()
	if jb != null:
		var t: Variant = jb.call("eval",
			"localStorage.getItem(%s)||''" % INDEX_KEY, false)
		if typeof(t) == TYPE_STRING:
			var parsed: Variant = JSON.parse_string(str(t))
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


# Export levelu do souboru, ktery si hrac muze poslat. Ve webu se soubor
# stahne (blob), na desktopu se zapise do user://export.
func export_to_file() -> String:
	var text: String = to_json()
	var jb: Object = _web()
	if jb != null:
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


# Rychla kontrola, ze level dava smysl. Editor ji pousti pred ulozenim -
# prazdny nebo rozbity level by hrac poznal az ve hre.
func validate() -> Array:
	var errs: Array = []
	if lanes.size() < MIN_LANES:
		errs.append("méně než %d koleje" % MIN_LANES)
	if lanes.size() > MAX_LANES:
		errs.append("více než %d kolejí" % MAX_LANES)
	if exits.is_empty():
		errs.append("žádný výstup")
	for i in range(lanes.size()):
		if exit_of(i) < 0 or exit_of(i) >= exits.size():
			errs.append("kolej %d míří na neexistující výstup" % (i + 1))
	if band1 - band0 < 0.06:
		errs.append("rovný úsek je moc krátký")
	if exits.size() > 1 and exit_row(exits.size() - 1) - exit_row(0) > BOTTOM - TOP:
		errs.append("výstupy se nevejdou do plochy")
	var killable := 0
	for i in range(lanes.size()):
		if not is_neutral(i):
			killable += 1
	if killable < 2:
		errs.append("v mapě není dost úseků, které umí zabíjet")
	return errs