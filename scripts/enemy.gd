extends "res://scripts/enemy_base.gd"
## The baseline bruiser: walks straight in, punches, dies. Everything it does is
## the behaviour in enemy_base.gd plus the numbers from the catalogue entry
## "ravager", so this file exists mainly to NAME the kind - which is the point:
## a kind is an entry in scripts/monster_kind.gd, not a copy of the AI.

func kind_id() -> String:
	return "ravager"
