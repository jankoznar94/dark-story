class_name Tower
extends RefCounted

# VEZE. Nahrazuji bonusy: vez stoji v PASU kolem cesty (1 bunka na kazdou
# stranu) a SAMA UTOCI na poutniky, kteri prochazeji v jejim dosahu.
#
# Jan (Oct 2026): "Trochu se přiblížíme TD žánru tím, že budeme reálně stavět
# věže kolem tras, které budou útočit na procházející nepřátele."
#
# VEZ JE VAZANA NA BUNKU, NE NA USEK. Element dostava od cesty, ktera tu bunku
# podbarvuje - vez u ohnive cesty ma ohnivy element, vez v sedem pasu (kmen
# nebo neutralni usek) je neutralni a dava fyzicke poskozeni vsem stejne.
#
# DOSAH JE CTVERCOVY (Chebyshev), 2 bunky: Jan: "Prozatim budou mit vsechny
# veze dosah 2 policek ve ctvercovem rozsahu."
const RANGE := 2

const MAX_LEVEL := 3
# CENA JE ZA UROVEN: prvni cislo je postaveni veze, dalsi dve jsou upgrady.
# Kazdy dalsi level je drazsi (Jan: "Kazdy level bude drazsi (upgrade)").
const COST := [60, 100, 160]
# POSKOZENI ZA RANU A DOBA MEZI RANAMI. Kazdy level je o neco rychlejsi
# a o neco silnejsi (Jan: "Kazdy level bude mit o neco rychlejsi a vyssi
# poskozeni.").
const DMG := [7.0, 12.0, 20.0]
const CD := [1.00, 0.90, 0.80]
# Jak dlouho je videt cara vystrelu. Je to ZNACKA, ne mechanika - hrac z ni
# pozna, ze vez opravdu strili a na koho.
const SHOT_FLASH := 0.12

var cell: Vector2i = Vector2i.ZERO
# HODNOTA USEKU, KTERY TEHLE VEZI DAL ELEMENT (0..3, Level.NEUTRAL, Level.KMEN).
# Nikdy se neposila do `Element.name_of` - na jmena je `Level.value_name`.
var element: int = Element.FIRE
var level: int = 1
# Kolik sekund zbyva, nez muze vystrelit znovu. Nula = vez je pripravena.
var cd: float = 0.0
# Odkud a kam naposledy vystrelila (kresli se z toho cara vystrelu).
var shot_to: Vector2 = Vector2.ZERO
var shot_t: float = 0.0


# Cena za postaveni veze dane urovne. Jedno misto, kde se o cenach vi vsechno -
# HUD, pravidla i testy se ptaji tady, ne kazdy zvlast.
static func level_cost(l: int) -> int:
	if l < 1 or l > MAX_LEVEL:
		return 0
	return COST[l - 1]


func upgrade_cost() -> int:
	return level_cost(level + 1)


func can_upgrade() -> bool:
	return level < MAX_LEVEL


func damage() -> float:
	return DMG[clampi(level, 1, MAX_LEVEL) - 1]


func cooldown() -> float:
	return CD[clampi(level, 1, MAX_LEVEL) - 1]


func dps() -> float:
	return damage() / maxf(cooldown(), 0.01)


# JE CIL V DOSAHU? Ctverec 2 bunky na kazdou stranu, ne kruh.
func in_range(target: Vector2i) -> bool:
	return absi(target.x - cell.x) <= RANGE and absi(target.y - cell.y) <= RANGE
