class_name Upgrades
extends RefCounted

# TABULKA UPGRADU. JEDNO MISTO, kde je receno, co ktery upgrade dela, o kolik
# a za kolik. Kdo chce jinou obtiznost nebo cenu, meni TADY - nikdy v obrazovce
# ani v pravidlech hry.
#
# MODEL (rozhodnuto s Janem, Oct 2026 - "jako ve hře Tower"):
#   * DOCASNY krok se kupuje v bitve za ZLATO a na kazdem levelu se kupuje
#     ZNOVU od nuly. Cena kroku je VZDY stejna (5, 10, 15, ... zlata), at hrac
#     zacina na jakekoli startovni hodnote.
#   * PERMANENTNI stupen se kupuje v menu za BODY (ziskane za vyhrany level)
#     a POSOUVA START o jeden krok. Attack speed s permanentem 2 zacina na
#     0,90 s misto 1,00 s - a docasne kroky stoji porad 5, 10, 15 zlata.
#   * SPECIÁL je JEN permanentni (multishot, ricochet, jed, led) - v bitve se
#     nekupuje, proto ma `temp_max` nula. Stejne je na tom DOSTREL (Jan, Oct
#     2026) - v bitve se proste nenabizi.
#
# HODNOTA = start + krok * (permanentni + docasne), orezana stropem. Jedno
# misto pro hru, obrazovku i testy - kdyby si obrazovka pocitala hodnotu sama,
# ukazovala by neco jineho, nez co hra opravdu pouziva.

const CAT_OFF := "off"
const CAT_DEF := "def"
const CAT_ECO := "eco"
const CAT_SPEC := "spec"

# PORADI KATEGORII JE PORADI TABU V PANELU. Prepinaji se tlacitky, takze se
# hrac v kazdem panelu (bitva i menu) uci poradi jen jednou.
const CATEGORIES := [
	{"id": CAT_OFF, "label": "ÚTOK"},
	{"id": CAT_DEF, "label": "OBRANA"},
	{"id": CAT_ECO, "label": "EKONOMIKA"},
	{"id": CAT_SPEC, "label": "SPECIÁL"},
]

# CENA DOCASNEHO KROKU: N-ty krok (od jedne) stoji 5 * N zlata. Neni to zavisle
# na permanentnim stupni - presne jak Jan chtel ("lvl 1 dočasného upgradu bude
# stát vždy například 5 goldů, ať začínám na střela/1s nebo střela/0.6s").
const TEMP_COST := 5
# CENA PERMANENTNIHO STUPNE: kazde tri urovne stoji o bod vic (1,1,1,2,2,2,...).
const PERM_EVERY := 3
# SPECIALY maji vlastni cenu za stupen (nasobek): multishot 3, ostatni 4.
const PERM_COST_STEP := 4

# kind:
#   time  - cas v sekundach (mensi je lepsi), pise se "0,75 s"
#   frac  - podil, pise se v procentech ("45 %")
#   mult  - nasobek, pise se "1,6x"
#   int   - cele cislo ("180", "+7")
#   levels- hodnota se bere z tabulky `values` (jed/led)
const STATS := [
	# KADENCE: "Attack speed by neměl být omezen na min střela/0,6s" (Jan, Oct
	# 2026). 0,60 s bylo presne to, kam dosahl DOCASNY zebricek (8 kroku po
	# 0,05 s z jednicky) - panel pak ukazal "MAX" a hrac mel za tim zed. Zed
	# je pryc: docasnych kroku je vic, krok je stejny a strop (0,10 s) lezi az
	# ZA koncem obou zebricku, takze "MAX" znamena "koupil jsi vsechno".
	{"id": "as", "label": "Rychlost střelby", "cat": CAT_OFF, "kind": "time",
		"start": 1.00, "step": -0.05, "cap": 0.10, "perm_max": 8, "temp_max": 10},
	# POSKOZENI RANY (Jan, Oct 2026: "Ještě musíme přidat upgrade pro Attack
	# damage"). Zaklad 10 je tady - `Game.SHOT_DMG` uz neexistuje, jinak by
	# byla druha konstanta, ktera o upgradu nevi.
	{"id": "ad", "label": "Poškození střely", "cat": CAT_OFF, "kind": "int",
		"start": 10, "step": 2, "cap": 40, "perm_max": 7, "temp_max": 8},
	# DOSTREL JE JEN PERMANENTNI (Jan, Oct 2026: "Rádius vyndáme z dočasných
	# upgradů a bude jen v permanentních"). Diky `temp_max` 0 se v bitve vubec
	# nenabizi (`game_view._shop_stats`) a cely zebricek je v menu.
	{"id": "ar", "label": "Dostřel", "cat": CAT_OFF, "kind": "frac",
		"start": 0.34, "step": 0.01, "cap": 0.60, "perm_max": 26, "temp_max": 0},
	{"id": "cc", "label": "Kritická šance", "cat": CAT_OFF, "kind": "frac",
		"start": 0.0, "step": 0.02, "cap": 0.40, "perm_max": 6, "temp_max": 14},
	{"id": "cd", "label": "Kritické poškození", "cat": CAT_OFF, "kind": "mult",
		"start": 1.50, "step": 0.10, "cap": 2.50, "perm_max": 6, "temp_max": 4},

	{"id": "hp", "label": "Životy věže", "cat": CAT_DEF, "kind": "int",
		"start": 100, "step": 10, "cap": 300, "perm_max": 6, "temp_max": 14},
	{"id": "am", "label": "Zbroj", "cat": CAT_DEF, "kind": "frac",
		"start": 0.0, "step": 0.02, "cap": 0.60, "perm_max": 6, "temp_max": 24},
	{"id": "rg", "label": "Regenerace", "cat": CAT_DEF, "kind": "rate1",
		"start": 0.0, "step": 0.5, "cap": 8.0, "perm_max": 6, "temp_max": 10},

	{"id": "gk", "label": "Zlato za zabití", "cat": CAT_ECO, "kind": "plus",
		"start": 0, "step": 1, "cap": 20, "perm_max": 6, "temp_max": 14},
	{"id": "gw", "label": "Zlato za vlnu", "cat": CAT_ECO, "kind": "plus",
		"start": 0, "step": 5, "cap": 50, "perm_max": 6, "temp_max": 4},
	{"id": "gl", "label": "Zlato za level", "cat": CAT_ECO, "kind": "plus",
		"start": 0, "step": 25, "cap": 250, "perm_max": 6, "temp_max": 4},

	{"id": "ms", "label": "Víc cílů", "cat": CAT_SPEC, "kind": "int",
		"start": 1, "step": 1, "cap": 5, "perm_max": 4, "temp_max": 0, "perm_cost": 3},
	{"id": "rc", "label": "Ricochet", "cat": CAT_SPEC, "kind": "int",
		"start": 0, "step": 1, "cap": 3, "perm_max": 3, "temp_max": 0},
	{"id": "ps", "label": "Jedovatý zásah", "cat": CAT_SPEC, "kind": "levels",
		"start": 0, "step": 1, "cap": 3, "perm_max": 3, "temp_max": 0,
		"values": [0.0, 0.20, 0.35, 0.50], "text": "%d/s"},
	{"id": "ic", "label": "Ledový zásah", "cat": CAT_SPEC, "kind": "levels",
		"start": 0, "step": 1, "cap": 3, "perm_max": 3, "temp_max": 0,
		"values": [0.0, 0.20, 0.35, 0.50], "text": "zpomalení"},
]


# BEZPECNY PRISTUP. Neznamy identifikator vraci neutral (nic nedela), nikdy
# nerozbije hru - obrazovka se muze splest v jmene a hra pojede dal.
static func stat(id: String) -> Dictionary:
	for s in STATS:
		if String(s["id"]) == id:
			return s
	return {"id": id, "label": id, "cat": CAT_OFF, "kind": "int",
		"start": 0, "step": 0, "cap": 0, "perm_max": 0, "temp_max": 0}


static func stats_in(cat: String) -> Array:
	var out: Array = []
	for s in STATS:
		if String(s["cat"]) == cat:
			out.append(s)
	return out


static func perm_max(id: String) -> int:
	return int(stat(id)["perm_max"])


static func temp_max(id: String) -> int:
	return int(stat(id)["temp_max"])


static func label_of(id: String) -> String:
	return String(stat(id)["label"])


# KOLIKÁTÝ KROK TO JE (permanentni + docasne). Z toho se pocita hodnota
# i to, kolik kroku jeste zbyva do stropu.
static func level_of(id: String, perm: int, temp: int) -> int:
	var s: Dictionary = stat(id)
	return clampi(perm, 0, int(s["perm_max"])) + clampi(temp, 0, int(s["temp_max"]))


# HODNOTA PARAMETRU. Jedno misto pro hru, obrazovku i testy.
static func value_of(id: String, perm: int, temp: int) -> float:
	var s: Dictionary = stat(id)
	var n: int = level_of(id, perm, temp)
	if String(s["kind"]) == "levels":
		var vals: Array = s["values"]
		return float(vals[clampi(n, 0, vals.size() - 1)])
	var start: float = float(s["start"])
	var step: float = float(s["step"])
	var cap: float = float(s["cap"])
	var v: float = start + step * float(n)
	return clampf(v, minf(start, cap), maxf(start, cap))


# TEXT HODNOTY PRO HRACE. Ceska desetinná carka, jednotky podle druhu - hrac
# nikdy nevidi "0.75", ale "0,75 s".
static func value_text(id: String, perm: int, temp: int) -> String:
	var s: Dictionary = stat(id)
	var v: float = value_of(id, perm, temp)
	match String(s["kind"]):
		"time":
			return _cz(v, 2) + " s"
		"frac":
			return str(int(round(v * 100.0))) + " %"
		"mult":
			return _cz(v, 1) + "x"
		"rate1":
			return _cz(v, 1) + "/s"
		"plus":
			return "+" + str(int(round(v)))
		"levels":
			if int(round(v * 100.0)) <= 0:
				return "—"
			return str(int(round(v * 100.0))) + " %"
	return _cz(v, 1)


static func _cz(v: float, digits: int) -> String:
	# "%.2f" DRZI POCET DESETIN: String.num(0.9, 2) vytiskne "0.9", takze by
	# hrac videl "0,9 s" jednou a "0,90 s" podruhe.
	if digits > 0:
		return (("%." + str(digits) + "f") % v).replace(".", ",")
	return str(int(round(v)))


# CENA DOCASNEHO KROKU. `bought` = kolik kroku uz hrac v tomto levelu koupil.
static func temp_cost(id: String, bought: int) -> int:
	if int(stat(id)["temp_max"]) <= 0:
		return 0
	return TEMP_COST * (clampi(bought, 0, 99) + 1)


# CENA PERMANENTNIHO STUPNE. `bought` = kolik stupnu uz hrac ma.
static func perm_cost(id: String, bought: int) -> int:
	var s: Dictionary = stat(id)
	if int(s["perm_max"]) <= 0:
		return 0
	var n: int = clampi(bought, 0, 99)
	# SPECIALY maji vlastni cenu za stupen (multishot 3, ostatni 4) - jsou to
	# nove mechaniky, ne cisla, takze se musi koupit "za vic".
	if String(s["cat"]) == CAT_SPEC:
		return int(s.get("perm_cost", PERM_COST_STEP)) * (n + 1)
	return 1 + n / PERM_EVERY


# SOUHRN PRO KONZOLI/TESTY: "as 3/6+2" (permanentni/docasne).
static func summary(perm: Dictionary, temp: Dictionary) -> String:
	var parts: Array = []
	for s in STATS:
		var id: String = String(s["id"])
		var p: int = int(perm.get(id, 0))
		var t: int = int(temp.get(id, 0))
		if p > 0 or t > 0:
			parts.append("%s %d+%d" % [id, p, t])
	return " ".join(parts)
