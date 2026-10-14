class_name Element
extends RefCounted

# CTYRI ZIVLY = CTYRI BARVY. V novem modelu uz nic nedela tabulka nasobku
# (0/50/200) — vez ma jednu barvu a vidi jen ji. Zivel zustava IDENTITA:
# barva poutnika, barva veze, runa.

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

# RUNA JE DRUHY NOSITEL INFORMACE. Barva nesmi byt nikdy jedina - ma ji
# prectenou vetsina hracu, ale ne vsichni. V tomhle modelu je to jeste
# dulezitejsi nez driv: rozlisit barvu na prvni pohled JE ta hra.
# U poutnika je runa primo TVAR tela, ne drobna znacka uvnitr - na plose
# o prumeru ~370 px je poutnik ~18 px velky a znacka uvnitr by zmizela.

# Bezpecne prevody: GDScript bere zaporny index od konce pole, takze
# `COLORS[-1]` je Vzduch a `NAMES[-2]` je Země. Kdo si toho nevsimne, kresli
# neco jineho, nez si mysli, a je presvedceny, ze je to spravne.
static func name_of(e: int) -> String:
	if e < 0 or e >= COUNT:
		return "?"
	return String(NAMES[e])


static func color_of(e: int) -> Color:
	if e < 0 or e >= COUNT:
		return Color(0.36, 0.35, 0.33)
	return COLORS[e]


static func is_valid(e: int) -> bool:
	return e >= 0 and e < COUNT
