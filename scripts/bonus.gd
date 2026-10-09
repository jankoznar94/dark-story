class_name Bonus
extends RefCounted

# BONUS. Nahrazuje vez: neútočí, posiluje CELY usek, na kterem stoji.
# Je vazany na element toho useku (jako drive vez na kolej) a jeho cena
# je jedina vec, za kterou se ve hre plati.
#
# Proc to nahradilo veze: umisteni veze bylo plytke - element koleje
# urcoval, co tam muze stat, takze tri mista na koleji byla v podstate
# stejna. Bonus posilujici cely usek dela z volby vzacnou vec a hlavne
# propojuje obe rozhodnuti hrace: investice do useku ma cenu jen tehdy,
# kdyz na nej dokazu poslat poutniky.

const COST := 60
const UPGRADE_COST := 90
const MAX_LEVEL := 2
# Nasobek dmg zony celeho useku. Je ZAMERNE velky: usek sam dava poutnika
# jen ZRANI, ne zabije - zabiti je odmena za investici. JEDEN bonus na
# spravnem (protikladnem) useku uz zabiji, takze stavba je POVINNA.
# Vylepseni stoji vic (90) a da min (x4/3) nez novy bonus (x3 za 60) -
# vyplati se teprve tehdy, kdyz jsou vsechna tri mista na useku plna.
const MULT := [2.5, 3.5]

var lane: int = 0
var slot: int = 0
var element: int = 0
var level: int = 1


func mult() -> float:
	var m: float = MULT[level - 1]
	return m


func can_upgrade() -> bool:
	return level < MAX_LEVEL
