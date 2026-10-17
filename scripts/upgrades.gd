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
#     a POSOUVA START o jeden krok. Poskozeni s permanentem 2 zacina na 14
#     misto 10 - a docasne kroky stoji porad 5, 10, 15 zlata.
#   * SPECIÁL je JEN permanentni (multishot, odraz, jed, led) - v bitve se
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

# CENA DOCASNEHO KROKU: N-ty krok (od jedne) stoji `TEMP_COST * N * N` zlata.
# Neni to zavisle na permanentnim stupni - presne jak Jan chtel ("lvl 1
# dočasného upgradu bude stát vždy například 5 goldů, až začínám na
# střela/1s nebo střela/0.6s").
#
# Oct 2026 (Jan): "Nárůst cen u upgradů bude naopak méně strmý ... ale ať cena
# tak rychle neroste do stovek a tisíců. Jde spíš o optický rozdíl." Zaklad je
# proto 1 (cena kroku je 1, 4, 9, 16, 25 ...) misto 5 - cely zlaty obeh se
# zmensil petkrat VCRETNE vyderlku za zabiti (`Hue.ROWS`, `Game.START_GOLD`).
# Pomer "kolik zabiti na jeden upgrade" je tim PRESNE stejny jako driv; meni se
# jen cislo na obrazovce. Kdo hybe zakladem, MUSI pohnout i zlatem za zabiti.
const TEMP_COST := 1
# CENA PERMANENTNIHO STUPNE: kazde tri urovne stoji o bod vic (1,1,1,2,2,2,...).
const PERM_EVERY := 3
# SPECIALY maji vlastni cenu za stupen (nasobek): multishot 3, ostatni 4.
const PERM_COST_STEP := 4

# NEOMEZENY DOCASNY ZEBRICEK. Jan (Oct 2026): "já prozatím nechci žádné stropy.
# Žádné max. Stanovíme to případně později, ale teď chci neomezené možnosti."
# V bitve proto hrac koupi tolik kroku, na kolik ma zlato - strop plati jen na
# PERMANENTNI zebricek (ten se plati body z vyhranych levelu, takze by jinak
# utekl z ruky). `temp_max == 0` znamena neco jineho: "v bitve se vubec
# nenabizi" (dostrel a specialy).
const UNLIMITED := -1
# kind:
#   time  - cas v sekundach (mensi je lepsi), pise se "0,75 s"
#   frac  - podil, pise se v procentech ("45 %")
#   mult  - nasobek, pise se "1,6x"
#   int   - cele cislo ("180", "+7")
#   levels- hodnota se bere z tabulky `values` (jed/led)
const STATS := [
	# POSKOZENI LASERU (Jan, Oct 2026: "Ještě musíme přidat upgrade pro Attack
	# damage"). Zaklad 10 je tady - `Game.SHOT_DMG` uz neexistuje, jinak by
	# byla druha konstanta, ktera o upgradu nevi.
	#
	# JE TO ZA SEKUNDU, NE ZA RANU (Jan, Oct 2026: "Vrátíme se k laseru místo
	# projektilů. Tím pádem zrušíme úplně Attack speed upgrady. Poškození bude
	# probíhat plynule a čím vyšší bude mít věž dmg, tím rychleji to logicky
	# bude nepřítele zabíjet."). Cislo 10 zustalo stejne jako driv (10 za ranu
	# pri kadenci 1,00 s = 10 za sekundu), takze se zmenil ZPUSOB, ne obtiznost.
	#
	# ZAKLAD 14 (Jan, Oct 2026: "Základní poškození hráče musí být o něco vyšší.
	# S tím, jak je nastavený na začátku kola nemá skoro šanci nikoho zabít.").
	# Odkud cislo je - je to POCITANE, ne od oka: poutnik je v dostrelu
	# (`ar` 0,34 pole) jen `(0,34 * field_r - tower_r) / rychlost` = ~3,2 s,
	# takze zaklad da za pruchod `14 * 3,2 = 45` poskozeni. Nejtvrdsi poutnik
	# prvniho kola (cervena, `hp` 2,2 x 20) ma 44 zivotu - s 10 (32 poskozeni)
	# ho hrac NEMEL cim zabit ani s plnym dostrelem, s 14 ho zabije.
	# `cap` = hodnota na `perm_max` (start + krok * perm_max), jinak by se
	# permanentni zebricek zastavil na jinem cisle, nez tabulka slibuje.
	{"id": "ad", "label": "Poškození laseru", "cat": CAT_OFF, "kind": "int",
		"start": 14, "step": 2, "cap": 28, "perm_max": 7, "temp_max": UNLIMITED},
	# SÍLA PAPRSKU = chybějící modifikátor (Jan, Oct 2026: "Jak zbylo jen dmg,
	# bez attack speed, tak vlastně chybí jeden modifikátor a hráč nestíhá věž
	# vylepšovat tak, aby stíhala zabíjet všechny nepřátele, i když investuje
	# všechny peníze do poškození.").
	#
	# JE TO NÁSOBICÍ OSA, ne druhé "poškození". Kadence za zlato skončila
	# s projektily; tady se místo ní násobí CELÝ paprsek. Proto se hra musí
	# ptát na tuhle hodnotu úplně stejně jako na "ad" - `laser_dps()` je
	# součin: (základ + krok za poškození) x síla paprsku x kritika.
	# Permanentní žebříček je malý (1,0x - 1,5x) a zdražuje se po bodech;
	# v bitvě za zlato není strop - a právě tam se ta osa rozjede.
	{"id": "ap", "label": "Síla paprsku", "cat": CAT_OFF, "kind": "mult",
		"start": 1.0, "step": 0.10, "cap": 1.50, "perm_max": 5, "temp_max": UNLIMITED},
	# DOSTREL JE JEN PERMANENTNI (Jan, Oct 2026: "Rádius vyndáme z dočasných
	# upgradů a bude jen v permanentních"). Diky `temp_max` 0 se v bitve vubec
	# nenabizi (`game_view._shop_stats`) a cely zebricek je v menu.
	{"id": "ar", "label": "Dostřel", "cat": CAT_OFF, "kind": "frac",
		"start": 0.34, "step": 0.01, "cap": 0.60, "perm_max": 26, "temp_max": 0},
	{"id": "cc", "label": "Kritická šance", "cat": CAT_OFF, "kind": "frac",
		"start": 0.0, "step": 0.02, "cap": 0.12, "perm_max": 6, "temp_max": UNLIMITED},
	{"id": "cd", "label": "Kritické poškození", "cat": CAT_OFF, "kind": "mult",
		"start": 1.50, "step": 0.10, "cap": 2.10, "perm_max": 6, "temp_max": UNLIMITED},

	{"id": "hp", "label": "Životy věže", "cat": CAT_DEF, "kind": "int",
		"start": 100, "step": 10, "cap": 160, "perm_max": 6, "temp_max": UNLIMITED},
	{"id": "am", "label": "Zbroj", "cat": CAT_DEF, "kind": "frac",
		"start": 0.0, "step": 0.02, "cap": 0.12, "perm_max": 6, "temp_max": UNLIMITED},
	{"id": "rg", "label": "Regenerace", "cat": CAT_DEF, "kind": "rate1",
		"start": 0.0, "step": 0.5, "cap": 3.0, "perm_max": 6, "temp_max": UNLIMITED},

	{"id": "gk", "label": "Zlato za zabití", "cat": CAT_ECO, "kind": "plus",
		"start": 0, "step": 1, "cap": 6, "perm_max": 6, "temp_max": UNLIMITED,
		# "cost": 5 - viz `temp_cost`: krok je cele +1 zlato za zabiti, takze
		# v petkrat mensi mene (Oct 2026) je petkrat silnejsi.
		"cost": 5},
	# ZLATO ZA VLNU A ZA LEVEL se zmensilo s celym obehem (5 -> 1 a 25 -> 5);
	# strop je hodnota na `perm_max`, takze se posunul s krokem (6 a 30).
	{"id": "gw", "label": "Zlato za vlnu", "cat": CAT_ECO, "kind": "plus",
		"start": 0, "step": 1, "cap": 6, "perm_max": 6, "temp_max": UNLIMITED},
	{"id": "gl", "label": "Zlato za level", "cat": CAT_ECO, "kind": "plus",
		"start": 0, "step": 5, "cap": 30, "perm_max": 6, "temp_max": UNLIMITED},

	{"id": "ms", "label": "Víc cílů", "cat": CAT_SPEC, "kind": "int",
		"start": 1, "step": 1, "cap": 5, "perm_max": 4, "temp_max": 0, "perm_cost": 3},
	# ODRAZ (driv Ricochet). Jan (Oct 2026): "RICOHET přejmenujeme na Odraz a
	# bude se takhle laser šířit na další nepřátele, podobně jako ricochet, ale
	# bez projektilů. A každý odraz bude dávat menší poškození. S levelem
	# upgradu se bude zvyšovat počet odrazů a bude snižovat penalizace za
	# odraz."
	#
	# JEDNA POLOZKA, DVE CISLA: `values[uroven]` = [pocet odrazu, sila odrazu].
	# Sila je podil poskozeni, ktery si odraz jeste odnese (0,50 = polovinu).
	# Kdyby to byly dva radky, hrac by musel koupit dvakrat to same.
	{"id": "rc", "label": "Odraz", "cat": CAT_SPEC, "kind": "chain",
		"start": 0, "step": 1, "cap": 4, "perm_max": 4, "temp_max": 0,
		"values": [[0, 1.00], [1, 0.50], [2, 0.60], [3, 0.70], [4, 0.80]]},
	{"id": "ps", "label": "Jedovatý zásah", "cat": CAT_SPEC, "kind": "levels",
		"start": 0, "step": 1, "cap": 3, "perm_max": 3, "temp_max": 0,
		"values": [0.0, 0.20, 0.35, 0.50], "text": "%d/s"},
	{"id": "ic", "label": "Ledový zásah", "cat": CAT_SPEC, "kind": "levels",
		"start": 0, "step": 1, "cap": 3, "perm_max": 3, "temp_max": 0,
		"values": [0.0, 0.20, 0.35, 0.50], "text": "zpomalení"},
	# ZRYCHLENI HRY (Jan, Oct 2026: "Přidáme do speciálních permanentních
	# upgradů novou mechaniku. Zrychlení hry. 1.5x, 2x, 2.5x. Veškerý čas ve hře
	# se zrychlí. Pohyb, rychlost palby, rychlost animací, vše."). Neni to
	# zvlastni mechanika obrazovky: hra nasobi KROK (`Game.step`) timto
	# nasobkem, takze se zrychli vsechno, co je na case - pohyb, kadence, let
	# strely, jed i led, casy vln.
	{"id": "gs", "label": "Zrychlení hry", "cat": CAT_SPEC, "kind": "mult",
		"start": 1.0, "step": 0.5, "cap": 2.5, "perm_max": 3, "temp_max": 0},
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


# NEOMEZENE DOCASNE KROKY? (viz UNLIMITED). Kdo se ptá na strop, musí se ptát
# TOHOHLE - `temp_max` u neomezeného zebricku vraci -1 a kdejaké `> 0` by ho
# omylem vyradilo z nabidky (presne to dela `_shop_stats`).
static func temp_unlimited(id: String) -> bool:
	return int(stat(id)["temp_max"]) == UNLIMITED


# JE DOCASNY ZEBRICEK UZ U KONCE? Neomezeny nikdy (rozhoduje zlato v `buy_temp`).
static func temp_is_maxed(id: String, have: int) -> bool:
	if temp_unlimited(id):
		return false
	return have >= int(stat(id)["temp_max"])


# JE STAT VUBEC V BITVE K DOSTANI? (`ar` a specialy maji `temp_max` 0.)
static func temp_buyable(id: String) -> bool:
	return int(stat(id)["temp_max"]) != 0


# RYCHLOST HRY (special "gs"). Upgrade nema hodnotu, ktera by se rovnou
# pouzila: je to KLIC, ktery hracovi odemkne PREPINANI tempa v bitve. Hodnota
# na jeho stupni je NEJVYSSI rychlost, kterou si smi zapnout; hra zacina VZDY
# na 1,0x (Jan, Oct 2026: "Výchozí vždy 1.0x. Upgrade jen otevírá možnost to
# přepínat."). Pocet prepinacich poloh = perm_max + 1 (zaklad + kazdy stupen).
static func speed_at(step: int) -> float:
	var s: Dictionary = stat("gs")
	var n: int = clampi(step, 0, int(s["perm_max"]))
	return float(s["start"]) + float(s["step"]) * float(n)


static func speed_steps() -> int:
	return int(stat("gs")["perm_max"]) + 1


static func label_of(id: String) -> String:
	return String(stat(id)["label"])


# KOLIKÁTÝ KROK TO JE (permanentni + docasne). Z toho se pocita hodnota
# i to, kolik kroku jeste zbyva do stropu. PERMANENTNI STUPNE MAJI STROP VZDY;
# docasne jen kdyz nejsou neomezene.
static func level_of(id: String, perm: int, temp: int) -> int:
	var s: Dictionary = stat(id)
	var p: int = clampi(perm, 0, int(s["perm_max"]))
	if temp_unlimited(id):
		return p + maxi(0, temp)
	return p + clampi(temp, 0, int(s["temp_max"]))


# HODNOTA PARAMETRU. Jedno misto pro hru, obrazovku i testy.
#
# STROP (`cap`) plati JEN na permanentni zebricek: je to hodnota, na ktere
# permanentni stupne konci. Docasne kroky jdou dal, dokud na ne ma hrac zlato -
# jinak by se za par kroku objevilo "MAX" uprostred bitvy, a to Jan nechce.
static func value_of(id: String, perm: int, temp: int) -> float:
	var s: Dictionary = stat(id)
	var n: int = level_of(id, perm, temp)
	if String(s["kind"]) == "levels":
		var vals: Array = s["values"]
		return float(vals[clampi(n, 0, vals.size() - 1)])
	if String(s["kind"]) == "chain":
		return chain_of(id, perm, temp).x
	var start: float = float(s["start"])
	var step: float = float(s["step"])
	var v: float = start + step * float(n)
	if temp_unlimited(id):
		return v
	var cap: float = float(s["cap"])
	return clampf(v, minf(start, cap), maxf(start, cap))


# TEXT HODNOTY PRO HRACE. Ceska desetinná carka, jednotky podle druhu - hrac
# nikdy nevidi "0.75", ale "0,75 s".
static func value_text(id: String, perm: int, temp: int) -> String:
	var s: Dictionary = stat(id)
	var v: float = value_of(id, perm, temp)
	match String(s["kind"]):
		"int":
			return str(int(round(v)))
		"chain":
			if int(round(v)) <= 0:
				return "—"
			var c: Vector2 = chain_of(id, perm, temp)
			return "%d %s · %d %% zásahu" % [int(c.x), _odraz_word(int(c.x)),
				int(round(c.y * 100.0))]
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


# ODRAZ: pocet odrazu a sila odrazu (podil poskozeni) pro dany stupen.
# `Vector2(pocet, sila)` - obrazovka z toho pise text, hra z toho pocita
# poskozeni. Nikdo si to nepocita sam.
static func chain_of(id: String, perm: int, temp: int) -> Vector2:
	var s: Dictionary = stat(id)
	var vals: Array = s.get("values", [])
	if vals.is_empty():
		return Vector2.ZERO
	var n: int = clampi(level_of(id, perm, temp), 0, vals.size() - 1)
	var pair: Array = vals[n]
	return Vector2(float(pair[0]), float(pair[1]))


# "1 odraz", "2 odrazy", "5 odrazu" - cesky se to sklonuje, hrac nesmi videt
# "2 odraz".
static func _odraz_word(n: int) -> String:
	if n == 1:
		return "odraz"
	if n >= 2 and n <= 4:
		return "odrazy"
	return "odrazů"


static func _cz(v: float, digits: int) -> String:
	# "%.2f" DRZI POCET DESETIN: String.num(0.9, 2) vytiskne "0.9", takze by
	# hrac videl "0,9 s" jednou a "0,90 s" podruhe.
	if digits > 0:
		return (("%." + str(digits) + "f") % v).replace(".", ",")
	return str(int(round(v)))


# CENA DOCASNEHO KROKU. `bought` = kolik kroku uz hrac v tomto levelu koupil.
# Cena roste (1, 4, 9, 16, ...) - to je jediny "strop" neomezeneho zebricku.
static func temp_cost(id: String, bought: int) -> int:
	if not temp_buyable(id):
		return 0
	# CENA ROSTE KVADRATICKY (Oct 2026). Driv to bylo linearni (5*(n+1)) a
	# hrac s prijmem ~20 000 zlata za level si koupil pres 80 kroku poskozeni -
	# Jan: "Je velmi snadné se brzy dostat na vysoké upgrady poškození a pak je
	# každý mrtvý během chvilky." Strop tu porad ZADNY neni (Jan, Oct 2026:
	# "já prozatím nechci žádné stropy") - draha je az druha polovina zebricku:
	# 1, 4, 9, 16, 25 ... (petkrat mensi cisla nez driv, viz `TEMP_COST`).
	#
	# UROVEN CENY JE VLASTNOST STATU, NE VYJIMKA V KODU (`"cost"` v tabulce).
	# "Zlato za zabití" ji ma petkrat vyssi, protoze jeho krok je cele
	# +1 zlato za zabiti: v petkrat mensi mene je petkrat silnejsi, takze by se
	# z neho stal jednoznacne nejlepsi nakup ve hre. Cislo kroku je tim porad
	# stejne drahe V ZABITICH jako driv (`test_upgrades` to hlida).
	var s: Dictionary = stat(id)
	var mult: int = int(s.get("cost", 1))
	var n: int = clampi(bought, 0, 99) + 1
	return mult * TEMP_COST * n * n


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
