class_name Tower
extends RefCounted

# VEZE. Nahrazuji bonusy: vez stoji v PASU kolem cesty (1 bunka na kazdou
# stranu) a SAMA UTOCI na poutniky, kteri prochazeji v jejim dosahu.
#
# Jan (Oct 2026): "Trochu se přiblížíme TD žánru tím, že budeme reálně stavět
# věže kolem tras, které budou útočit na procházející nepřátele."
#
# VEZ JE VAZANA NA BUNKU, NE NA USEK. Element dostava od cesty, ktera tu bunku
# podbarvuje - vez u ohnive cesty ma ohnivy element, vez u neutralni cesty je
# neutralni a dava fyzicke poskozeni vsem stejne.
#
# VEZ JE SAMOSTATNY OBJEKT (Jan: "Věže se musí chovat jako samostatné objekty.
# Musí být možné je vložit, vybrat, vylepšit a prodat."). Proto si pamatuje,
# KOLIK HRAC DO NI DAL (`spent`) - z toho se pocita, za kolik ji muze prodat.
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
# KOLIK PROCENT INVESTICE SE VRATI PRI PRODEJI. Prodej musi byt PRODEJ, ne
# druha pokladna: hrac dostane polovinu zpatky (muzes prestat stavet jinam),
# ale ne vsechno - jinak by se stavba a bourani daly otacet dokola zadarmo
# a rozhodnuti "kam s vezi" by nic nestalo.
# Jan (Oct 2026): "Prodej vrátí 50 %."
const SELL_BACK := 0.5

var cell: Vector2i = Vector2i.ZERO
# HODNOTA USEKU, KTERY TEHLE VEZI DAL ELEMENT (0..3, Level.NEUTRAL, Level.KMEN).
# Nikdy se neposila do `Element.name_of` - na jmena je `Level.value_name`.
var element: int = Element.FIRE
var level: int = 1
# Kolik zlata do veze hrac celkem dal (postaveni + vsechny upgrady).
var spent: int = 0
# Kolik sekund zbyva, nez muze vystrelit znovu. Nula = vez je pripravena.
var cd: float = 0.0


# Cena za postaveni veze dane urovne. Jedno misto, kde o cenach vi vsechno -
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


# ZA KOLIK SE DA VEZE PRODAT. Vzdy aspon 1 zlaty, aby prodej nikdy nebyl
# "klepnu a nic" (nula by hraci vypadala jako chyba hry).
func sell_back() -> int:
	return maxi(1, int(floor(float(spent) * SELL_BACK)))


# JE CIL V DOSAHU? Ctverec 2 bunky na kazdou stranu, ne kruh.
func in_range(target: Vector2i) -> bool:
	return absi(target.x - cell.x) <= RANGE and absi(target.y - cell.y) <= RANGE


# MUZE VUZEC TOMUHLE POUTNIKOVI VUBEC UBLIZIT? Vez sameho elementu dava nulu
# (Element.tower_multiplier), takze na nej NESMI utocit - prisla by o ranu,
# kterou mohla dat nekomu, komu opravdu ublizi.
# Jan (Oct 2026): "Věže samozřejmě útočí pouze na nepřítele, který není
# stejného typu. Nemá smysl útočit na nepřítele stejného elementu. Zbytečně to
# věži bere příležitost zaútočit na nepřítele, kterému poškození skutečně udělí."
func can_hurt(enemy_el: int) -> bool:
	return Element.tower_multiplier(enemy_el, element) > 0.0
