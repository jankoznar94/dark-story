class_name Tower
extends RefCounted

# VEŽ. Uz to neni tabulka stupnu - vsechny jeji hodnoty (dostrel, kadence,
# kritika, cile, ricochet, jed, led) jsou PARAMETRY HRACE a pocita je `Game`
# z tabulky `Upgrades`. Tady zustava jen to, co je opravdu o vezi:
#   * BARVY, na ktere je prebita (jedna, nebo SMES DVOU - od levelu 6),
#     a PALETA, ze ktere smi vybirat,
#   * VIDI NA TOHOHLE POUTNIKA? (`sees`) - jedine misto, kde se rozhoduje
#     o barve, a proto to musi zustat tady.
#
# DRIVE tu byla tabulka stupnu (`RATES`, `RANGE_FRACS`, `TARGETS`, `COSTS`).
# Ta je PRYC - kdo ji bude hledat, najde `Upgrades.STATS`.

# MNOZINA BAREV VEZE: jedna barva, nebo dve (michani). VZDY serazena od
# nejmensiho id, aby "cervena+zluta" a "zluta+cervena" byl stejny stav.
var hues: Array = [Hue.RED]
# BARVY, KTERE HRAc MUZE ZVOLIT. Do veze se nesmi dostat barva mimo paletu -
# stribrna tedy nikdy (proto na ni nejde mirrit) a barva, ktera do hry jeste
# nevstoupila, taky ne. SMES v palete neni: hrac ji sklada ze DVOU puntiku.
var palette: Array = [Hue.RED, Hue.YELLOW]


# JEDNA BARVA VEZE. Vetsina kodu se ptá jen na ni (`tower.hue = Hue.RED`
# v testech funguje dal), ale kdo chce barvu KRESLIT, musí sáhnout po `color()`:
# u smesi je barva jina nez kterákoli z obou slozek.
var hue: int:
	get:
		return int(hues[0])
	set(value):
		hues = [value]


# ID SMESI, nebo -1, kdyz je zvolena jedna barva.
func mix() -> int:
	if hues.size() < 2:
		return -1
	return Hue.mix_id(int(hues[0]), int(hues[1]))


# BARVA VEZE - tecky strely, kruh dostrelu i prstenec veze. U smesi je to barva
# smesi, ne prvni z obou.
func color() -> Color:
	if hues.size() < 2:
		return Hue.color_of(int(hues[0]))
	return Hue.color_of(mix())


# VIDI TOHOHLE POUTNIKA? Poutnik v "duchovem" stavu (fialova po prvnim zasahu)
# tu neni videt, i kdyz ma hrac zvolenou jeho barvu. U smesi plati, ze kazda
# barva poutnika musi byt v sade veze (`Hue.covers`) - vez s RY vidi cervenou,
# zlutou i oranzovou, kdezto vez s R oranzovou ne.
func sees(p: Pilgrim) -> bool:
	return p.targetable() and Hue.covers(hues, p.hue)


func set_hue(h: int) -> bool:
	if not palette.has(h):
		return false
	hues = [h]
	return true


# PROMICHANI DVOU BAREV (dvojtap na palete). Smi se michat jen to, co hrac
# v palete opravdu ma - jinak by slo vyrobit barvu z barvy, ktera ve hre neni.
func set_pair(a: int, b: int) -> bool:
	if a == b or not palette.has(a) or not palette.has(b):
		return false
	hues = [mini(a, b), maxi(a, b)]
	return true
