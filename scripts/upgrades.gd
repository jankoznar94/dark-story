class_name Upgrades
extends RefCounted

# TABULKA PERMANENTNICH UPGRADU. Thrower NEMA docasne upgrady (Jan, Oct 2026:
# "Dočasné upgrady by úplně zmizely.") - vsechno se kupuje jednou za BODY
# a plati navzdy. Jedno misto, kde je receno, co ktery upgrade dela a za kolik.

const CAT_OFF := "off"
const CAT_DEF := "def"

const CATEGORIES := [
	{"id": CAT_OFF, "label": "ÚTOK"},
	{"id": CAT_DEF, "label": "OBRANA"},
]

# kind:
#   int   - cele cislo ("6", "3")
#   time  - sekundy, mensi je lepsi ("0,75 s")
#   count - pocet kusu ("2")
const STATS := [
	# POSKOZENI JEDNOHO ZASU. Zaklad 6, krok 3 - prvni poutnik (18 HP) padne na
	# ctyri zasahy, coz je na zacatku citelne.
	{"id": "dmg", "label": "Poškození", "cat": CAT_OFF, "kind": "int",
		"start": 6, "step": 3, "cap": 27, "perm_max": 7},
	# RYCHLOST HAZENI. Je to DOBA MEZI HODY, takze mensi je lepsi; krok je
	# zaporny a `value_of` ho orizne smerem ke stropu. Zaklad 0,75 s - po
	# prvnim zrychleni (1,10 -> 0,88) jeste o kus rychlejsi (Jan, Oct 2026:
	# "Ještě trochu zrychlime výchozí rychlost střelby").
	{"id": "rate", "label": "Rychlost házení", "cat": CAT_OFF, "kind": "time",
		"start": 0.75, "step": -0.05, "cap": 0.25, "perm_max": 10},
	# POCET OSTRU V JEDNOM HODU. Kazdy leti malinko jinam (vedle sebe).
	{"id": "shots", "label": "Víc oštěpů", "cat": CAT_OFF, "kind": "count",
		"start": 1, "step": 1, "cap": 4, "perm_max": 3},
	# ODRAZ: po zasahu preskoci na nejblizsiho dalsiho nepritele se slabsi ranou.
	{"id": "ric", "label": "Odraz", "cat": CAT_OFF, "kind": "count",
		"start": 0, "step": 1, "cap": 3, "perm_max": 3},
	# RYCHLOST LETU. Podil polomeru plochy za sekundu - kdyby to byly pixely,
	# na jinem displeji by letel jinak dlouho.
	{"id": "spd", "label": "Rychlost oštěpu", "cat": CAT_OFF, "kind": "time",
		"start": 1.60, "step": 0.20, "cap": 2.80, "perm_max": 6},
	# ZIVOTY BOJOVNIKA A REGENERACE.
	{"id": "hp", "label": "Životy", "cat": CAT_DEF, "kind": "int",
		"start": 100, "step": 20, "cap": 220, "perm_max": 6},
	{"id": "rg", "label": "Regenerace", "cat": CAT_DEF, "kind": "time",
		"start": 0.0, "step": 0.3, "cap": 1.8, "perm_max": 6},
]

# CENA PERMANENTNIHO STUPNE: kazde tri urovne stoji o bod vic.
const PERM_EVERY := 3


static func stat(id: String) -> Dictionary:
	for s in STATS:
		if String(s["id"]) == id:
			return s
	return {"id": id, "label": id, "cat": CAT_OFF, "kind": "int",
		"start": 0, "step": 0, "cap": 0, "perm_max": 0}


static func stats_in(cat: String) -> Array:
	var out: Array = []
	for s in STATS:
		if String(s["cat"]) == cat:
			out.append(s)
	return out


static func perm_max(id: String) -> int:
	return int(stat(id)["perm_max"])


static func label_of(id: String) -> String:
	return String(stat(id)["label"])


# HODNOTA PARAMETRU. Jedno misto pro hru, obrazovku i testy.
static func value_of(id: String, perm: int) -> float:
	var s: Dictionary = stat(id)
	var n: int = clampi(perm, 0, int(s["perm_max"]))
	var v: float = float(s["start"]) + float(s["step"]) * float(n)
	var a: float = float(s["start"])
	var b: float = float(s["cap"])
	return clampf(v, minf(a, b), maxf(a, b))


static func value_text(id: String, perm: int) -> String:
	var s: Dictionary = stat(id)
	var v: float = value_of(id, perm)
	match String(s["kind"]):
		"time":
			if v <= 0.0001:
				return "—"
			return (("%.2f" % v).replace(".", ",")) + (" s" if String(s["id"]) != "spd" else "×")
		"count", "int":
			return str(int(round(v)))
	return str(int(round(v)))


# CENA DALSIHO STUPNE v bodech. `bought` = kolik stupnu uz hrac ma.
static func perm_cost(id: String, bought: int) -> int:
	if perm_max(id) <= 0:
		return 0
	var n: int = clampi(bought, 0, 99)
	return 1 + n / PERM_EVERY


# SOUHRN PRO KONZOLI/TESTY: "dmg 3 rate 2".
static func summary(perm: Dictionary) -> String:
	var parts: Array = []
	for s in STATS:
		var id: String = String(s["id"])
		var p: int = int(perm.get(id, 0))
		if p > 0:
			parts.append("%s %d" % [id, p])
	return " ".join(parts)
