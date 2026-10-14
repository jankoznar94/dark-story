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
# DOSTREL JE MEZI SPAWNOVACIM KRUHEM A VEZI (Jan, Oct 2026): "kruh, který
# určuje vzdálenost zjišťování nepřátel je tak malý, že hráč nemá moc času
# reagovat. Zjišťování by mělo být někde mezi těmito dvěma kruhy."
#
# ZAKLAD MUSI BYT MALY, ABY BYLO KAM UPGRADOVAT (Jan, Oct 2026): "Rozsah
# zjišťování nepřátel nesmí mít hned na začátku poloměr jak celá šířka displeje.
# Musí začínat na menším úseku, aby ho bylo kam upgradovat." Na 390x844 je
# polovina šířky displeje 0,57 polomeru plochy, takze 0,62 sahalo presne na boky
# a prvni stupen vypadal jako "cele vidim".
#
# DRUHY PRUCHOD (Jan, Oct 2026): "A vše uděláme o něco menší. Nepřátele, věž,
# rádius zjišťování nepřátel atd." - kruhy se zmensily na 0,34 / 0,46 / 0,60
# (zaklad 0,42 -> 0,34 = 116 px na 390x844, tedy 79 px od kazdeho boku) a
# TRAVEL_S sel na 15 s, takze okno na reakci zustava stejne: 0,34 * 15 = 5,1 s
# proti drivejsim 0,42 * 12 = 5,0 s.
#
# CAS V OHNI pri TRAVEL_S = 15 s: 5,1 / 6,9 / 9,0 s. Meri to
# `test_core._test_reaction_window` a tvar prvniho kruhu hlida
# `test_layout` (nesmi dosahnout na bok displeje).
const RANGE_FRACS := [0.34, 0.46, 0.60]

# RYCHLOST STRELBY JE UPGRADE, KTERY JE VIDET (Jan, Oct 2026): "mám tu možnost
# pracovat s rychlostí střelby, což je velmi uspokojivý upgrade." Poskozeni
# JEDNE rany se nemění (SHOT_DMG) - nahoru jde pocet ran za sekundu, takze
# paprskem rytmicky proudi vic tecek. `dps()` je z toho ODVOZENE (rate * dmg),
# aby prumerne poskozeni za sekundu zustalo 30 / 48 / 72 jako driv.
const RATES := [3.0, 4.8, 7.2]
const SHOT_DMG := 10.0
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


# RYCHLOST STRELBY: kolik ran vez vystreli za sekundu.
func rate() -> float:
	return float(RATES[_idx()])


# POSKOZENI JEDNE RANY (tecka, ktera doleti). Nemeni se - meni se kadence.
func shot_damage() -> float:
	return SHOT_DMG


# PRUMERNE POSKOZENI ZA SEKUNDU. Je odvozene z rany a kadence, aby existovalo
# JEDNO cislo pro HUD, testy a simulaci obtiznosti.
func dps() -> float:
	return rate() * shot_damage()


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
