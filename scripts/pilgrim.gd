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
# VELIKOST KRESBY. Modre kusy po rozpadu jsou mensi - hrac to vidi.
var size: float = 1.0
# MUZE SE JESTE ROZPADNOUT? Rozpad je jen jednou.
var can_split: bool = true
# UZ BYL ZASAZEN? U fialove se na prvni zasah vaze zmizeni.
var was_hit: bool = false
# FIALOVA: kolik sekund jeste bude pro vez neviditelna.
var ghost_left: float = 0.0
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


# VIDI NA NEJ VEZ VUBEC? Fialova po prvnim zasahu na 3 s zmizi - putuje dal,
# ale vez ji nevidi, i kdyz ma hrac zvolenou jeji barvu.
func targetable() -> bool:
	return alive and ghost_left <= 0.0


# JE POUTNIK PRIRAVENY? Kresli se jen obrysem, aby hrac videl, kde je, ale
# poznal, ze na nej ted nema cenu mirrit.
func is_ghost() -> bool:
	return alive and ghost_left > 0.0
