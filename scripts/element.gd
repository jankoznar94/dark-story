class_name Element
extends RefCounted

# Ctyri zivly. Poradi je zamerne: 0<->1 a 2<->3 jsou protiklady,
# takze matice poskozeni je citelna na prvni pohled.
#
# POSKOZENI UZ NEDELA VEZ, ALE CELEK KOLOJE. Proto se nasobky premenovaly
# a zmenily hodnoty: silny = 2.0 (byl 1.0), slaby = 0.5 (byl 0.35),
# vlastni = 0.0 beze zmeny, a pribylo NEUTRAL = 1.0 pro neutralni useky.
# Hra tim ziskala tri jasne urovne: 0 / 0.5 / 1 / 2 - hrac je vidi
# v navodu dole a nemusi si nic pamatovat.

const FIRE := 0
const WATER := 1
const EARTH := 2
const AIR := 3
const COUNT := 4

const NAMES := ["Oheň", "Voda", "Země", "Vzduch"]
const COLORS := [
	Color(0.82, 0.34, 0.17),
	Color(0.23, 0.47, 0.76),
	Color(0.58, 0.44, 0.21),
	Color(0.68, 0.68, 0.72),
]

# Nasobky poskozeni na ELEMENTARNIM useku.
const OWN := 0.0
const STRONG := 2.0
const WEAK := 0.5
# Nasobek na NEUTRALNIM useku - plati pro vsechny stejne.
const NEUTRAL := 1.0


static func name_of(e: int) -> String:
	var s: String = NAMES[e]
	return s


static func color_of(e: int) -> Color:
	var c: Color = COLORS[e]
	return c


static func opposite_of(e: int) -> int:
	if e == FIRE:
		return WATER
	if e == WATER:
		return FIRE
	if e == EARTH:
		return AIR
	return EARTH


# Zivly, ktere jsou proti tomuhle SLABE (tedy dostavaji polovinu).
# Jsou to zbylé dva - protiklad je silny a vlastni nedava nic.
static func weak_against(e: int) -> Array:
	var out: Array = []
	for t in range(COUNT):
		if t != e and t != opposite_of(e):
			out.append(t)
	return out


# Poskozeni na ELEMENTARNIM useku, ktery nese zivel `lane_el`.
static func multiplier(enemy_el: int, lane_el: int) -> float:
	if enemy_el == lane_el:
		return OWN
	if opposite_of(enemy_el) == lane_el:
		return STRONG
	return WEAK


# Poskozeni na libovolnem useku. Neutralni usek nema element - dava
# vsem presne 100 %, takze je to spolehlivy zaklad pro kazdou kolej.
static func lane_multiplier(enemy_el: int, lane_el: int, neutral: bool) -> float:
	if neutral:
		return NEUTRAL
	return multiplier(enemy_el, lane_el)


static func damage_table() -> String:
	var out := ""
	for e in range(COUNT):
		out += name_of(e) + ": "
		for t in range(COUNT):
			out += "%.2f " % multiplier(e, t)
		out += "neutral %.2f\n" % NEUTRAL
	return out
