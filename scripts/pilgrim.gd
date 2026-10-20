class_name Pilgrim
extends RefCounted

# POUTNIK. Jde ROVNE od okraje plochy k vezi - nezataci, neobchazi, nema cestu
# ani trasu. Proto tu neni zadny pathfinding a hradby nikdy nesmi blokovat
# pohyb.
#
# Chovani jednotlivych barev (rozpad, regenerace, mizeni, zmena barvy) je
# tady, protoze je to vlastnost POUTNIKA - hra je jen spousti a hlida casy.

var hue: int = Hue.RED
var pos: Vector2 = Vector2.ZERO
var dir: Vector2 = Vector2.UP
var hp: float = 1.0
var max_hp: float = 1.0
var speed: float = 0.0
var alive: bool = true
# CHOVANI BARVY SI POUTNIK NESE S SEBOU. Necte se z jeho barvy: stribrna po
# prvni zmene barvu zmeni, ale sve chovani si musi nechat dal.
var behaviour: String = Hue.B_NONE
# VSECHNY SCHOPNOSTI BARVY. U jednoduche barvy je to jedna, u SMESI (kombinovany
# poutnik) dve - plan (Jan): "prvni verze dá kombinovanému poutníkovi OBĚ chování
# (dělení i regenerace apod.)". `behaviour` zustava PRVNI z nich, protoze stribrna
# si pri zmene podoby prebira prave ji. Kdo se v bitve ptá, jestli poutnik neco
# umi, musi se ptát `has_behaviour()` - jinak smesi polovina schopnosti zmizi.
var behaviours: Array = [Hue.B_NONE]
# VELIKOST KRESBY. Modre kusy po rozpadu jsou mensi - hrac to vidi.
var size: float = 1.0
# UROVEN (TIER) TÉTO BARVY. Uroven je nasobek NAD zakladni hodnoty barvy
# (`Hue.tier_hp`, `Hue.tier_size`, `Hue.tier_gold`) - barva, pismeno i chovani
# zustavaji, meni se jen zivoty, velikost a zlato. Nese si ji POUTNIK, ne hra:
# vez i rozpadle kusy se pak musi ptat jeho, jinak by se uroven na tech dvou
# mistech rozešla (boss ma vzdy uroven 1 - je "úroveň sama pro sebe", Jan).
var tier: int = 1
# BOSS. Velky, pomaly a vytrvaly poutnik (Jan, Oct 2026: "Taky musime pridat
# boss fighty." a "Pomaly, extra vydrz, extra velikost, pripadne nejaky stit
# navic nebo tak."). NENI to nova entita: je to poutnik s jinymi cisly
# (zivoty, rychlost, velikost), takze barvy, paprsek, jed, led i chovani
# barvy plati dal - hrac na nej miri stejnou zbrani, jen mu to trva dele.
var is_boss: bool = false
# MUZE SE JESTE ROZPADNOUT? Rozpad je jen jednou.
var can_split: bool = true
# MENI PODOBU? Stribrna poutnik neni "poutnik s chovanim shift" - je to poutnik,
# ktery MENI PODOBU, a v kazde podobe ma chovani te barvy (`behaviour` se pri
# zmene prepisuje). Kdyby se menici podstata drzela v `behaviour`, prvni zmena
# by ji smazala a poutnik by zustal navzdy v te podobe - proto je to zvlastni
# policko (Jan, Oct 2026).
var shifting: bool = false
# UZ BYL ZASAZEN? (historie - u fialove se na prvni zasah vazalo zmizeni;
# dnes uz nic, ale policko zustava kvuli stribrne a ukladani stavu)
var was_hit: bool = false
# FIALOVA (B_RANGED): kolik sekund zbyva do dalsiho vystrelu na vez. Bezi jen
# kdyz uz stoji na svem miste - dokud jde, nestrili.
var shot_left: float = 0.0
# STRIBRNA: za kolik sekund zmeni barvu.
var shift_left: float = 0.0
# JED (poison shot): kolik sekund ucinek jeste potrva a kolik poskozeni za
# sekundu dava. Aplikuje se pri kazdem zasahu (cas se obnovi), takze slabsi
# kadence znamená i slabsi jed.
var poison_left: float = 0.0
var poison_dps: float = 0.0
# LED (ice shot): o kolik je poutnik zpomaleny a jak dlouho to jeste potrva.
var ice_left: float = 0.0
var ice_frac: float = 0.0
# SVITI NA NEJ PAPRSEK? Dve policka, protoze hra potrebuje PRECHOD: zvuk
# zazehnuti se smi ozvat jen ve chvili "nesvitil -> sviti", ne kazdy snimek.
# `burning` = svitil i minuly snimek, `burning_now` = sviti ted.
var burning: bool = false
var burning_now: bool = false


func hp_frac() -> float:
	if max_hp <= 0.0:
		return 0.0
	return clampf(hp / max_hp, 0.0, 1.0)


# ZPOMALENI POHYBU. Jedno misto, odkud se bere rychlost - kdyby si to hra
# pocitala sama, zapomnelo by se to na nekterem miste.
func slow_mult() -> float:
	if ice_left <= 0.0:
		return 1.0
	return clampf(1.0 - ice_frac, 0.1, 1.0)


# VIDI NA NEJ VEZ VUBEC? (Dnes vzdy ziva - mechanika mizeni je zrusena;
# metoda zustava, protoze na ni stoji `tower.sees` a je to jedno misto.)
func targetable() -> bool:
	return alive


# UMI POUTNIK TOHLE? U smesi se musi ptat TAKHLE - `behaviour` je jen prvni
# schopnost, takze `behaviour == B_SPLIT` by u oranzove (regen + rozpad) pulku
# schopnosti zahodilo (plan: "dá kombinovanému poutníkovi OBĚ chování").
# Ptá se i na `behaviour`: ten je prvni z `behaviours`, takze se obe policka
# nemuzou rozejit (a kod, ktery plni jen `behaviour`, neztrati schopnost).
func has_behaviour(b: String) -> bool:
	return behaviours.has(b) or behaviour == b
