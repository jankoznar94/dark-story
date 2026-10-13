class_name Enemy
extends RefCounted

# Poutnik. Nema inteligenci - jen zivel, zivoty a pozici na trase.
# Jeho trasu meni HRAC vypinacem, ne on sam.
#
# DRUHY POUTNIKU (Oct 2026). Jan: "Rovnou vymyslíme i další úrovně nepřátel.
# Rychlejší s menšími životy. Pomalejší s vyššími životy." Druh je jen nasobek
# zivotu, rychlosti, odmeny a VELIKOSTI KRESBY - pravidla poskozeni zustavaji
# stejna pro vsechny druhy.
const TIER_BASIC := 0
const TIER_LIGHT := 1
const TIER_HEAVY := 2
# "gold" je ABSOLUTNI odmena za zabiti, ne nasobek: hrac pocita zlato, ne
# procenta. Zakladni druh ma 12 jako dosud.
const TIERS := [
	{"name": "Základní", "hp": 1.0, "speed": 1.0, "gold": 12, "size": 1.0},
	{"name": "Lehký", "hp": 0.6, "speed": 1.6, "gold": 8, "size": 0.86},
	{"name": "Těžký", "hp": 2.2, "speed": 0.6, "gold": 25, "size": 1.18},
]

var element: int = 0
# DRUHY ZIVEL POUTNIKA, nebo -1. Dvojzivelny poutnik (ohen + voda, zeme +
# vzduch) je na desce PUL KOLECKA jednoho a pul druheho a bere NEVYHODY OBOU
# ZIVLU: co je pro jeden z nich silne, plati i pro druhy (viz `mult_against`).
var element2: int = -1
# Druh poutnika - index do `TIERS`.
var tier: int = TIER_BASIC
var max_hp: float = 70.0
var hp: float = 70.0
var speed: float = 52.0
var lane: int = -1
var s: float = 0.0
# KDE POUTNIK PRACE JE, V PIXELECH. Pocita se jednou za snimek pri pohybu
# (`Game._move_enemies`) a odtud si ho bere kresleni, mireni vezi i strely.
# Driv si kazdy pocital `net.point_at(lane, s)` sam - a bylo to trikrat
# (kresleni, hledani cile, strela), tedy trikrat zbytecna prace za snimek.
var pos: Vector2 = Vector2.ZERO
# Kterym kmenem (vstupem) poutnik do mapy vstoupil. Map muze mit kmenu vic.
var trunk: int = 0
var alive: bool = true
var leaked: bool = false


func on_lane() -> bool:
	return lane >= 0


func hp_frac() -> float:
	if max_hp <= 0.0:
		return 0.0
	return clampf(hp / max_hp, 0.0, 1.0)


# JE POUTNIK ZE DVOU ZIVLU? Kresli se pul na pul a nema imunitu.
func dual() -> bool:
	return element2 >= 0


# RADEK DRUHU. Vsechno, co o druhu nekdo vi, je tady.
static func tier_row(index: int) -> Dictionary:
	return TIERS[clampi(index, 0, TIERS.size() - 1)]


static func tier_name(index: int) -> String:
	return String(tier_row(index)["name"])


static func tier_hp(index: int) -> float:
	return float(tier_row(index)["hp"])


static func tier_speed(index: int) -> float:
	return float(tier_row(index)["speed"])


static func tier_size(index: int) -> float:
	return float(tier_row(index)["size"])


# NASOBEK POSKOZENI OD VEZE TOHOTO ZIVLU. Jednozivelny poutnik ma jeden
# nasobek. DVOJZIVELNY MA VYHODY OBOU ZIVLU - je IMUNNI na oba sve zivly,
# proto se bere MINIMUM z obou nasobku:
#
#   ohen+voda proti ohnive vezi   min(0 %, 200 %) =   0 %  -> imunni
#   ohen+voda proti vodni vezi    min(200 %, 0 %) =   0 %  -> imunni
#   ohen+voda proti zemni vezi    min(50 %, 50 %) =  50 %
#   ohen+voda proti neutralni vezi min(100 %,100%)= 100 %
#
# Jan (Oct 2026) to zmenil z maxima: "Nepřátelé s dual elementem budou odteď
# mít naopak výhody obou elementů. Budou imuní na oba elementy. Hráč bude
# nucen použít neutrální věže na jejich zničení." S maximem byl dvojzivelny
# naopak NEJZRANITELNEJSI (dostaval 200 % od obou), takze se z nej stal
# nejsnazsi protivnik - presne obraceny zamer.
#
# POZOR: `mult_against` je JEDNO misto, kde to je rozhodnute. `can_hurt`
# i mireni veze se ptaji jeho, takze vez, ktera dava nulu, na poutnika
# nevystreli vubec (a neplýtvá ranou, ktera by mohla jit na jineho).
func mult_against(tower_el: int) -> float:
	var m: float = Element.tower_multiplier(element, tower_el)
	if element2 >= 0:
		m = minf(m, Element.tower_multiplier(element2, tower_el))
	return m


# MUZE VEZE TOHOTO ZIVLU POUTNIKOVI VUBEC UBLIZIT? Vez, ktera dava nulu, na
# nej nesmi utocit - prisla by o ranu pro nekoho, komu opravdu ublizi.
func can_hurt(tower_el: int) -> bool:
	return mult_against(tower_el) > 0.0


# JMENO PRO HUD A HLASKY. Dvojzivelny poutnik se musi jmenovat obema zivly,
# jinak by hrac v hlasce nevidel, co vlastne proslo.
func title() -> String:
	if element2 < 0:
		return Element.name_of(element)
	return "%s+%s" % [Element.name_of(element), Element.name_of(element2)]


# Kolik zlata hrac dostane za zabiti. Jedno misto, kde o odmene vi vsechno.
# DVOJZIVELNY POUTNIK SE VYPLATI VIC: ma zivoty zakladniho, ale nema imunitu
# a hrac na nej potrebuje veze na oba zivly, takze je nejdrazsi na obranu -
# bez priplatku by se za nej dostalo stejne jako za zakladniho.
const DUAL_BONUS := 1.5


func reward() -> int:
	var g: int = int(tier_row(tier)["gold"])
	if dual():
		return int(round(float(g) * DUAL_BONUS))
	return g
