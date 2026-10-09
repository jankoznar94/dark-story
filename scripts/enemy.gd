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
var alive: bool = true
var leaked: bool = false


func on_lane() -> bool:
	return lane >= 0


func hp_frac() -> float:
	if max_hp <= 0.0:
		return 0.0
	return clampf(hp / max_hp, 0.0, 1.0)
