class_name Enemy
extends RefCounted

# Poutnik. Nema inteligenci - jen zivel, zivoty a pozici na trase.
# Jeho trasu meni HRAC vypinacem, ne on sam.

var element: int = 0
var max_hp: float = 70.0
var hp: float = 70.0
var speed: float = 52.0
var lane: int = -1
var s: float = 0.0
# KDE POUTNIK PRAVE JE, V PIXELECH. Pocita se jednou za snimek pri pohybu
# (`Game._move_enemies`) a odtud si ho bere kresleni, mireni vezi i strely.
# Driv si kazdy pocital `net.point_at(lane, s)` sam - a bylo to trikrat
# (kresleni, hledani cile, strela), tedy trikrat zbytecna prace za snimek.
var pos: Vector2 = Vector2.ZERO
# Kterym kmenem (vstupem) poutnik do mapy vstoupil. Map muze mit kmenu vic.
var trunk: int = 0
var alive: bool = true
var leaked: bool = false


func on_lane() -> bool:
	return lane >= 0


func hp_frac() -> float:
	if max_hp <= 0.0:
		return 0.0
	return clampf(hp / max_hp, 0.0, 1.0)
