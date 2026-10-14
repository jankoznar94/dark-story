class_name Tower
extends RefCounted

# VEZ. Jedina zbran hry a jedina vec, na kterou hrac klepe.
#
# VEZ VIDI JEN SVOJI BARVU. Jan: "Nula. Jako by je vůbec neviděla." Na ostatni
# tedy nejen ze dava nulu — ona na ne VUBEC NESTRILI. Kdyby palila do neceho
# s nulovym poskozenim, plytvala by svazkem a prepnuti by bylo vzdycky horsi.
#
# SVAZEK DRZI JEDEN CIL, DOKUD NEUMRE. Jan: "Věž bude střílet vždy jen na
# jednoho dokud ho nezabije. Pomocí upgradu časem zvládne třeba vícero targetu
# zaráz." Vic cilu je proto jen cislo v tabulce (TARGETS), ne nova mechanika.
#
# DOSAH JE PODIL POLOMERU PLOCHY, ne pocet pixelu. Na male obrazovce by pevne
# pixely znamenaly kratsi dobu v ohne a tim jinou hru.

const MAX_LEVEL := 3

# STUPEN VEZE: 1 = vychozi. Cisla drzi "vez vidi maly kousek plochy"
# (zaklad ~1/3 polomeru), aby se rozhodovalo o kazde rane; upgrade dostrel
# zvetsi, ale nikdy ne na "vidim celou plochu" — pak by blizkost prestala
# hrat roli.
const RANGE_FRACS := [0.33, 0.45, 0.60]
const DPS := [26.0, 42.0, 66.0]
const TARGETS := [1, 1, 1]
const COSTS := [60, 130, 260]

var element: int = Element.FIRE
var level: int = 1
var spent: int = 0


func _idx() -> int:
	return clampi(level, 1, MAX_LEVEL) - 1


func range_frac() -> float:
	return float(RANGE_FRACS[_idx()])


func range_px(field_r: float) -> float:
	return range_frac() * field_r


func dps() -> float:
	return float(DPS[_idx()])


func targets() -> int:
	return int(TARGETS[_idx()])


func can_upgrade() -> bool:
	return level < MAX_LEVEL


func upgrade_cost() -> int:
	if not can_upgrade():
		return 0
	return int(COSTS[level])


func upgrade() -> void:
	if not can_upgrade():
		return
	spent += upgrade_cost()
	level += 1


# VIDI TOHOHLE POUTNIKA? Jedno misto, kde se rozhoduje o barve.
func sees(p: Pilgrim) -> bool:
	return p.alive and Element.is_valid(element) and p.element == element


func set_element(e: int) -> void:
	if Element.is_valid(e):
		element = e
