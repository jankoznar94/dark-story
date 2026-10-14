class_name Tower
extends RefCounted

# VEZ. Jedina zbran hry. Neklepe se na ni - barva se vybira z palety dole,
# aby hrac nemackal do pole a neztratil prehled (Jan, Oct 2026).
#
# VEZ VIDI JEN SVOJI BARVU. Jan: "Nula. Jako by je vůbec neviděla." Na ostatni
# nejen ze dava nulu - ona na ne VUBEC NESTRILI. Kdyby palila do neceho
# s nulovym poskozenim, plytvala by svazkem a kazda zmena barvy by byla horsi.
#
# SVAZEK DRZI JEDEN CIL, DOKUD NEUMRE. Jan: "Věž bude střílet vždy jen na
# jednoho dokud ho nezabije. Pomocí upgradu časem zvládne třeba vícero targetu
# zaráz." Vic cilu je proto jen cislo v tabulce (TARGETS), ne nova mechanika.
#
# DOSAH JE PODIL POLOMERU PLOCHY, ne pocet pixelu. Na male obrazovce by pevne
# pixely znamenaly kratsi dobu v ohne a tim jinou hru.

const MAX_LEVEL := 3

# STUPEN VEZE. Zaklad drzi "vez vidi maly kousek plochy", aby se rozhodovalo
# o kazde rane; upgrade dostrel zvetsi, ale nikdy ne na "vidim celou plochu" -
# pak by blizkost prestala hrat roli.
#
# DOSTREL JE MEZI KRUHEM DOSTRELU A SPAWNOVACIM KRUHEM (Jan, Oct 2026): "kruh,
# který určuje vzdálenost zjišťování nepřátel je tak malý, že hráč nemá moc času
# reagovat. Zjišťování by mělo být někde mezi těmito dvěma kruhy." Zaklad byl
# 0,40 polomeru plochy, coz dava jen ~2,5 s v ohne - hrac nestihne zareagovat.
# 0,62 dava ~4,6 s (meri to `test_core._test_reaction_window`) a upgrade
# k tomu prida. Strop zustava pod 0,9, aby dostrel nikdy neobsahl celou plochu.
const RANGE_FRACS := [0.62, 0.74, 0.86]
const DPS := [30.0, 48.0, 72.0]
const TARGETS := [1, 1, 2]
const COSTS := [70, 150, 300]

var hue: int = Hue.RED
var level: int = 1
var spent: int = 0
# BARVY, KTERE HRAc MUZE ZVOLIT. Do veze se nesmi dostat barva mimo paletu -
# stribrna tedy nikdy (proto na ni nejde mirrit) a barva, ktera do hry jeste
# nevstoupila, taky ne.
var palette: Array = [Hue.RED, Hue.YELLOW]


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


# CENA ZA DALSÍ STUPEN. `COSTS[0]` je cena cesty z 1. na 2. stupen.
func upgrade_cost() -> int:
	if not can_upgrade():
		return 0
	return int(COSTS[clampi(level, 0, COSTS.size() - 1)])


func upgrade() -> void:
	if not can_upgrade():
		return
	spent += upgrade_cost()
	level += 1


# VIDI TOHOHLE POUTNIKA? Jedno misto, kde se rozhoduje o barve. Poutnik
# v "duchovem" stavu (fialova po prvnim zasahu) tu neni videt, i kdyz ma
# hrac zvolenou jeho barvu.
func sees(p: Pilgrim) -> bool:
	return p.targetable() and p.hue == hue


func set_hue(h: int) -> bool:
	if not palette.has(h):
		return false
	hue = h
	return true
