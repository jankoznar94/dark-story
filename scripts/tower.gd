class_name Tower
extends RefCounted

# VEŽ. Uz to neni tabulka stupnu - vsechny jeji hodnoty (dostrel, kadence,
# kritika, cile, ricochet, jed, led) jsou PARAMETRY HRACE a pocita je `Game`
# z tabulky `Upgrades`. Tady zustava jen to, co je opravdu o vezi:
#   * BARVA, na kterou je prebita, a PALETA, ze ktere smi vybirat,
#   * VIDI NA TOHOHLE POUTNIKA? (`sees`) - jedine misto, kde se rozhoduje
#     o barve, a proto to musi zustat tady.
#
# DRIVE tu byla tabulka stupnu (`RATES`, `RANGE_FRACS`, `TARGETS`, `COSTS`).
# Ta je PRYC - kdo ji bude hledat, najde `Upgrades.STATS`.

var hue: int = Hue.RED
# BARVY, KTERE HRAc MUZE ZVOLIT. Do veze se nesmi dostat barva mimo paletu -
# stribrna tedy nikdy (proto na ni nejde mirrit) a barva, ktera do hry jeste
# nevstoupila, taky ne.
var palette: Array = [Hue.RED, Hue.YELLOW]


# VIDI TOHOHLE POUTNIKA? Poutnik v "duchovem" stavu (fialova po prvnim zasahu)
# tu neni videt, i kdyz ma hrac zvolenou jeho barvu.
func sees(p: Pilgrim) -> bool:
	return p.targetable() and p.hue == hue


func set_hue(h: int) -> bool:
	if not palette.has(h):
		return false
	hue = h
	return true
