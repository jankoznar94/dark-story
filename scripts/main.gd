extends Node2D
## Main — the port's entry point. It currently does nothing but prove the data
## layer is alive, which is the only honest thing it can do before the arena exists.
##
## Replace the body of _ready() with the first real screen once the arena is in.
## The DataProbe output is what makes a broken convert visible at runtime (a black
## screen with a working build is a much worse failure mode).

const GameData := preload("res://scripts/data/game_data.gd")

var data: Node


func _ready() -> void:
	data = GameData.new()
	add_child(data)
	_report()


func _report() -> void:
	var r: Dictionary = data.integrity_report()
	print("Dungeon Recall — data layer")
	print("  tables=%d items=%d uniques=%d affixes=%d monsters=%d acts=%d classes=%d" % [
		r["tables"], r["items"], r["unique_items"], r["affixes"],
		r["monsters"], r["acts"], r["classes"]])
