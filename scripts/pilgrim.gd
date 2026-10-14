class_name Pilgrim
extends RefCounted

# POUTNIK. Jde ROVNE od okraje plochy k vezi — nezataci, neobchazi, nema
# cestu ani trasu. Proto tu neni zadny pathfinding a hradby nikdy nesmi
# blokovat pohyb (blokujici hradba by si pathfinding vyzadala).

var element: int = Element.FIRE
# Pozice ve PIXELECH. Rychlost je odvozena z polomeru plochy (`Game`), takze
# se hra na kazde obrazovce chova stejne - cas od okraje k vezi je porad
# stejny, jen jinak dlouhy v pixelech.
var pos: Vector2 = Vector2.ZERO
var dir: Vector2 = Vector2.UP
var hp: float = 1.0
var max_hp: float = 1.0
var speed: float = 0.0
var alive: bool = true


func hp_frac() -> float:
	if max_hp <= 0.0:
		return 0.0
	return clampf(hp / max_hp, 0.0, 1.0)


func dist_to(p: Vector2) -> float:
	return pos.distance_to(p)
