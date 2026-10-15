class_name Hue
extends RefCounted

# SEST BAREV. "Zivel" (ohen, voda, zeme, vzduch) uz neexistuje - barva je
# jedina identita poutnika i veze a kazda barva ma SVOJE CHOVANI. Presne to
# dela z hry rozhodovani: barva sama je jen jmeno, chovani je duvod, proc ji
# zabit zrovna teď.
#
# PORADI INDEXU JE ZAVAZNE (0..5). Je to identita barvy v kodu, v palete
# i v nahodnem losovani - prehazet se nesmi.
#
# BARVA NIKDY NENI JEDINY NOSITEL INFORMACE. U sesti barev to plati
# dvojnasob: cervena se zelenou je nejcastejsi porucha barvocitu a fialova
# s modrou se pletou taky. Proto ma kazda barva SVUJ TVAR a tvar je to, co
# hrac na plose opravdu cte.

const RED := 0
const YELLOW := 1
const BLUE := 2
const GREEN := 3
const VIOLET := 4
const SILVER := 5
const COUNT := 6

# CHOVANI:
#   none   - nic zvlastniho
#   split  - po zabiti se rozpadne na dva mensi kusy
#   regen  - obnovuje si zivoty
#   vanish - po prvnim zasahu na chvili zmizi (pro vez je neviditelna)
#   shift  - kazde 3 s zmeni barvu na jinou; zacina jako stribrna
const B_NONE := "none"
const B_SPLIT := "split"
const B_REGEN := "regen"
const B_VANISH := "vanish"
const B_SHIFT := "shift"

# JEDNA TABULKA PRO VSE, CO O BARVE NEKDO VI. Kdo chce jinou obtiznost barev,
# meni tady - nikdy v obrazovce ani v pravidlech.
#   letter      = PISMENO BARVY ve stredu puntiku palety. Je to POCATECNI
#                 PISMENO ANGLICKEHO NAZVU (Jan, Oct 2026: "Kazda barva bude mit
#                 ve stredu kruhu pismeno podle nazvu barvy. Cervena - R jako
#                 Red"). Anglicky proto, ze ceske "cervena/zluta/modra" dava
#                 C/Z/M a to se plete. Barva tak NIKDY neni jediny nositel
#                 informace - pismeno je druha cesta, jak barvu precte i hrac
#                 s poruchou barvocitu.
#   unlock_wave = vlna, od ktere barva do hry vstoupi (barvy pribyvaji
#                 s obtiznosti; dokud levely nejsou, odemykaji se vlnami)
#   palette     = je barva v palete hracе? Stribrna NENI - proto na ni na
#                 zacatku nejde mirrit a je to cely jeji smysl.
const ROWS := [
	{
		"name": "Červená", "letter": "R", "color": Color(0.80, 0.22, 0.17), "shape": "square",
		"hp": 2.2, "speed": 0.60, "gold": 18, "behaviour": B_NONE,
		"unlock_wave": 1, "palette": true,
	},
	{
		"name": "Žlutá", "letter": "Y", "color": Color(0.90, 0.78, 0.22), "shape": "triangle",
		"hp": 0.6, "speed": 1.60, "gold": 10, "behaviour": B_NONE,
		"unlock_wave": 1, "palette": true,
	},
	{
		"name": "Modrá", "letter": "B", "color": Color(0.22, 0.46, 0.80), "shape": "droplet",
		"hp": 1.0, "speed": 1.00, "gold": 14, "behaviour": B_SPLIT,
		"unlock_wave": 3, "palette": true,
	},
	{
		"name": "Zelená", "letter": "G", "color": Color(0.26, 0.62, 0.30), "shape": "cross",
		"hp": 1.2, "speed": 1.00, "gold": 16, "behaviour": B_REGEN,
		"unlock_wave": 5, "palette": true,
	},
	{
		"name": "Fialová", "letter": "V", "color": Color(0.58, 0.34, 0.74), "shape": "diamond",
		"hp": 0.7, "speed": 1.00, "gold": 14, "behaviour": B_VANISH,
		"unlock_wave": 7, "palette": true,
	},
	{
		"name": "Stříbrná", "letter": "S", "color": Color(0.78, 0.80, 0.82), "shape": "circle",
		"hp": 2.5, "speed": 0.60, "gold": 26, "behaviour": B_SHIFT,
		"unlock_wave": 9, "palette": false,
	},
]

# ROZPAD MODRE: dva kusy, kazdy se 40 % zivotu rodice, mensi a nikdy se
# nedeli znovu (jinak by z jednoho poutnika bylo nekonecno).
const SPLIT_PIECES := 2
const SPLIT_HP_FRAC := 0.40
const SPLIT_SIZE := 0.72
const SPLIT_GOLD := 6

# REGENERACE ZELENE: podil maximalnich zivotu za sekundu. Musi byt vyrazne
# mensi nez kadence veze, jinak je poutnik nesmrtelny.
const REGEN_FRAC := 0.04

# FIALOVA: jak dlouho po prvnim zasahu je pro vez neviditelna.
const VANISH_S := 3.0
# STRIBRNA: jak casto meni barvu.
const SHIFT_S := 3.0


static func is_valid(h: int) -> bool:
	return h >= 0 and h < COUNT


static func _row(h: int) -> Dictionary:
	return ROWS[clampi(h, 0, COUNT - 1)]


# Bezpecne prevody. GDScript bere zaporny index od konce pole, takze
# `ROWS[-1]` je Stribrna - kdo si toho nevsimne, kresli neco jineho, nez si
# mysli, a je presvedceny, ze je to spravne.
static func name_of(h: int) -> String:
	if not is_valid(h):
		return "?"
	return String(_row(h)["name"])


static func color_of(h: int) -> Color:
	if not is_valid(h):
		return Color(0.36, 0.35, 0.33)
	return _row(h)["color"]


static func shape_of(h: int) -> String:
	if not is_valid(h):
		return "square"
	return String(_row(h)["shape"])


# PISMENO BARVY: pocatecni pismeno anglickeho nazvu ("R" jako Red) - viz ROWS.
static func letter_of(h: int) -> String:
	if not is_valid(h):
		return "?"
	return String(_row(h)["letter"])


# PISMENO SMESI DVOU BAREV ("RY" = Red + Yellow). Poradi pismen je dane poradim
# barev v tabulce (0..5), takze cervena+zluta je VZDY "RY" a nikdy "YR" - jinak
# by jedna barva mela dve jmena. Aby se to nemuselo hlídat ve obrazovce, je
# jedina cesta k pismenu smesi tady.
static func letter_of_pair(a: int, b: int) -> String:
	if not is_valid(a) or not is_valid(b) or a == b:
		return letter_of(a)
	return letter_of(mini(a, b)) + letter_of(maxi(a, b))


static func hp_mult(h: int) -> float:
	return float(_row(h)["hp"])


static func speed_mult(h: int) -> float:
	return float(_row(h)["speed"])


static func gold_of(h: int) -> int:
	return int(_row(h)["gold"])


static func behaviour_of(h: int) -> String:
	return String(_row(h)["behaviour"])


# JE BARVA V PALETE? Stribrna ne - a presne proto na ni hrac nemuze mirrit.
static func in_palette(h: int) -> bool:
	if not is_valid(h):
		return false
	return bool(_row(h)["palette"])


static func unlock_wave(h: int) -> int:
	return int(_row(h)["unlock_wave"])


# BARVY, KTERE V TOMTO MOMENTE VSTUPUJI DO HRY (vsechny, i nepolapitelne).
static func active_at(wave: int) -> Array:
	var out: Array = []
	for h in range(COUNT):
		if unlock_wave(h) <= wave:
			out.append(h)
	return out


# CO UKAZUJE PALETA HRACE. Stribrna v ni nikdy neni.
static func palette_at(wave: int) -> Array:
	var out: Array = []
	for h in range(COUNT):
		if in_palette(h) and unlock_wave(h) <= wave:
			out.append(h)
	return out
