class_name Element
extends RefCounted

# Ctyri zivly. Poradi je zamerne: 0<->1 a 2<->3 jsou protiklady,
# takze matice poskozeni je citelna na prvni pohled.

const FIRE := 0
const WATER := 1
const EARTH := 2
const AIR := 3
const COUNT := 4

const NAMES := ["Ohen", "Voda", "Zeme", "Vzduch"]
const COLORS := [
	Color(0.82, 0.34, 0.17),
	Color(0.23, 0.47, 0.76),
	Color(0.58, 0.44, 0.21),
	Color(0.68, 0.68, 0.72),
]

# Nasobky poskozeni: vlastni zivel = neprojitna imunita, protiklad = plna
# palba, zbyle dva = slaby zvuk. Tohle je cela hra v jedne tabulce.
const OWN := 0.0
const OPPOSITE := 1.0
const OTHER := 0.35


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


static func multiplier(enemy_el: int, tower_el: int) -> float:
	if enemy_el == tower_el:
		return OWN
	if tower_el == opposite_of(enemy_el):
		return OPPOSITE
	return OTHER


static func damage_table() -> String:
	var out := ""
	for e in range(COUNT):
		out += name_of(e) + ": "
		for t in range(COUNT):
			out += "%.2f " % multiplier(e, t)
		out += "\n"
	return out
