class_name Tower
extends RefCounted

# Vez stoji VZDY na cilove koleji a ma vzdy zivel te koleje.
# Tim je sit citelna: kolej = zivel = druh palby.

const COST := 60
const UPGRADE_COST := 90
const MAX_LEVEL := 2
const DPS := [14.0, 28.0]

var lane: int = 0
var slot: int = 0
var element: int = 0
var level: int = 1


func dps() -> float:
	var d: float = DPS[level - 1]
	return d


func can_upgrade() -> bool:
	return level < MAX_LEVEL
