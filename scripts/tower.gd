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
# DRUHY VEZI. "Druh" je funkce veze: dostrel, poskozeni, kadence a cena.
# ZIVEL VEZE ZUSTAVA DANY PASEM, ve kterem vez stoji - vez u ohnive cesty je
# ohniva, at je to kterykoli druh. Diky tomu plati vsechna pravidla
# o nasobcich poskozeni (Element.tower_multiplier) pro kazdy druh stejne.
#
# DRUH 0 ("Živlová") JE VYCHOZI a jeho cisla se nesmi menit: stoji na nich
# `RANGE`, HUD i testy. Dalsi druhy se pridavaji SEM - obrazovka si vezme
# pocet z `KIND_COUNT` a rozvrhne presne tolik tlacitek, kolik jich je.
const KINDS := [
	{"name": "Živlová", "range": 2, "cost": [60, 100, 160],
		"dmg": [7.0, 12.0, 20.0], "cd": [1.00, 0.90, 0.80]},
]
# POZOR: tohle cislo musi odpovidat poctu polozek v KINDS - konstanta
# v GDScriptu neumi zavolat KINDS.size(). Je to jedine misto, kde se to
# opakuje, a hlida to `test_game`.
const KIND_COUNT := 1
const DEFAULT_KIND := 0

# ZIVEL VEZE MIMO ELEMENTY. Hodnota je stejna jako `Level.NEUTRAL` (typ
# neutralniho useku) - vez na neutralnim pasu ji dostava pres
# `Network.strip_element` a `Element.tower_multiplier` na ni vraci 100 % vsem.
# Je to jedina hodnota mimo 0..3, kterou vez v hre muze mit.
const NEUTRAL := -1

# TECKY UVNITR VEZE = UROVEN. Driv se uroven kreslila jako zuby NAD vezi a
# Janovi to prislo neuhledne: "Tečky se ale zobrazují nad věžmi a vypadá to
# dost neuhledne. Udělal bych puntíky uprostřed věže. Jeden - uprostřed, dva
# - vedle sebe ale stále na středu, tři - tři puntíky do trojúhelníku."
# Barva je STEJNA jako obrys veze (0.09): vez ma svetlejsi "strechu" a tmava
# tecka na ni je videt u vsech peti typu pasu (i u svetleho vzduchu).
const DOT_COLOR := Color(0.09, 0.085, 0.08)

# POLOMER JEDNE TECKY. Zavisi na polomeru veze (ta je v px podle meritka),
# takze na malem telefonu zustava aspon 1,4 px - mensi by zmizela.
static func dot_radius(r: float) -> float:
	return maxf(1.4, r * 0.13)


# KDE TECKY STOJI, vzhledem ke stredu veze. Je to JEDINE misto, kde se
# rozhoduje, kolik tecek uroven ma a kam padnou - kresleni i test se ptaji
# tady, takze se geometrie nemuze rozejit s tim, co hrac vidi.
# Vsechny posuny jsou uvnitr "strechy" (0.55 r), takze tecky nikdy nevytečou
# na obrys.
static func dot_offsets(level: int, r: float) -> Array:
	match clampi(level, 1, MAX_LEVEL):
		2:
			# DVE VEDLE SEBE - a porad na stred: stred mezi nimi je stred veze.
			return [Vector2(-0.20 * r, 0.0), Vector2(0.20 * r, 0.0)]
		3:
			# TRI DO TROJUHELNIKU - jeden nahore, dva dole. Posuny jsou
			# zvolene tak, aby TEZISTE trojuhelniku vyslo presne do stredu
			# veze ((-0.24 + 0.12 + 0.12) / 3 = 0): kdyby staly tecky
			# "v kruznici", sedel by trojuhelnik niz a vez by vypadala
			# posunuta.
			return [Vector2(0.0, -0.24 * r), Vector2(-0.20 * r, 0.12 * r),
				Vector2(0.20 * r, 0.12 * r)]
	return [Vector2.ZERO]


# POVOLENE ZIVLY VEZE PRO PAS S HODNOTOU `strip_el`. Jan (Oct 2026): "Na
# neutrální cestě může být pouze neutrální věž. Na elementární cestě může být
# jak věž daného elementu, tak i neutrální věž."
# Vraci seznam hodnot elementu, ne druhu: druh veze (KINDS) je funkce, element
# je to, co rozhoduje o nasobcich poskozeni.
static func allowed_elements(strip_el: int) -> Array:
	if strip_el < 0 or strip_el >= Element.COUNT:
		return [NEUTRAL]
	return [strip_el, NEUTRAL]


# POPISEK VOLBY V OBCHODE: jmeno a cena za postaveni. Cena je na tlacitku,
# aby hrac nemusel nikam koukat. U vice druhu vezi stoji v popisku i jmeno
# druhu - dokud je jen jeden, je zbytecne (druh je videt z cisel v panelu).
static func choice_label(kind: int, element: int) -> String:
	var el: String = Level.value_name(element)
	if KIND_COUNT > 1:
		return "%s %s %d" % [kind_name_of(kind), el, kind_cost(kind, 1)]
	return "%s %d" % [el, kind_cost(kind, 1)]

const MAX_LEVEL := 3
# DOSTREL VYCHOZIHO DRUHU. Vez sama odpovida pres `reach()` (kazdy druh ma
# svuj); tahle konstanta je pro HUD, nahledy a testy, ktere se na "zakladni
# dostrel" ptaji jednim cislem. Ctvercovy (Chebyshev), 2 bunky: Jan:
# "Prozatim budou mit vsechny veze dosah 2 policek ve ctvercovem rozsahu."
const RANGE := 2
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
# DRUH VEZI (index do `KINDS`). Rozhoduje o dostrelu, poskozeni, kadenci
# a cene; element dostava vez od pasu, ne od druhu.
var kind: int = DEFAULT_KIND
var level: int = 1
# Kolik zlata do veze hrac celkem dal (postaveni + vsechny upgrady).
var spent: int = 0
# Kolik sekund zbyva, nez muze vystrelit znovu. Nula = vez je pripravena.
var cd: float = 0.0


# RADEK DRUHU. Vsechno, co o druhu nekdo vi, je tady - nikdo si nesmi
# skladat cisla druhu z vlastnich konstant, jinak se casem rozejdou.
static func kind_row(index: int) -> Dictionary:
	return KINDS[clampi(index, 0, KINDS.size() - 1)]


static func kind_name_of(index: int) -> String:
	return String(kind_row(index)["name"])


# Cena za postaveni veze daneho druhu a urovne. Jedno misto, kde o cenach vi
# vsechno - HUD, obchod, pravidla i testy se ptaji tady, ne kazdy zvlast.
static func kind_cost(index: int, l: int = 1) -> int:
	if l < 1 or l > MAX_LEVEL:
		return 0
	var c: Array = kind_row(index)["cost"]
	return int(c[l - 1])


# DOSTREL DRUHU v bunkach. Vez odpovida pres `reach()`.
static func kind_reach(index: int) -> int:
	return int(kind_row(index)["range"])


# Cena za vychozi druh - drzi se kvuli HUDu a starym mistum, kde sel o jediny
# druh. Kazda vez se ale na cenu ptá pres svuj `kind`.
static func level_cost(l: int) -> int:
	return kind_cost(DEFAULT_KIND, l)


func upgrade_cost() -> int:
	return kind_cost(kind, level + 1)


func can_upgrade() -> bool:
	return level < MAX_LEVEL


func damage() -> float:
	var d: Array = kind_row(kind)["dmg"]
	return float(d[clampi(level, 1, MAX_LEVEL) - 1])


func cooldown() -> float:
	var c: Array = kind_row(kind)["cd"]
	return float(c[clampi(level, 1, MAX_LEVEL) - 1])


func reach() -> int:
	return kind_reach(kind)


func dps() -> float:
	return damage() / maxf(cooldown(), 0.01)


# ZA KOLIK SE DA VEZE PRODAT. Vzdy aspon 1 zlaty, aby prodej nikdy nebyl
# "klepnu a nic" (nula by hraci vypadala jako chyba hry).
func sell_back() -> int:
	return maxi(1, int(floor(float(spent) * SELL_BACK)))


# JE CIL V DOSAHU? Ctverec podle druhu veze (2 bunky na kazdou stranu
# u vychoziho druhu), ne kruh.
func in_range(target: Vector2i) -> bool:
	var r: int = reach()
	return absi(target.x - cell.x) <= r and absi(target.y - cell.y) <= r


# MUZE VUZEC TOMUHLE POUTNIKOVI VUBEC UBLIZIT? Vez sameho elementu dava nulu
# (Element.tower_multiplier), takze na nej NESMI utocit - prisla by o ranu,
# kterou mohla dat nekomu, komu opravdu ublizi.
# Jan (Oct 2026): "Věže samozřejmě útočí pouze na nepřítele, který není
# stejného typu. Nemá smysl útočit na nepřítele stejného elementu. Zbytečně to
# věži bere příležitost zaútočit na nepřítele, kterému poškození skutečně udělí."
func can_hurt(enemy_el: int) -> bool:
	return Element.tower_multiplier(enemy_el, element) > 0.0
