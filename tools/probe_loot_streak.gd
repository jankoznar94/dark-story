extends SceneTree
## tools/probe_loot_streak.gd — 12 fights in a row, the way a player plays them.
##
## Checks whether loot KEEPS working after the first fight: the first fight can look fine
## while every later one drops nothing because the screen was not reset.
##
## Run: godot --headless --path . --script res://tools/probe_loot_streak.gd

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const ArenaScreen := preload("res://scripts/ui/arena_screen.gd")

var _data: Node
var _gen: ItemGen
var _loot: LootSystem


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_loot = LootSystem.new(_data, _gen)
	_streak()
	quit(0)


func _resolve(state) -> Callable:
	return func(id):
		var item_id := str(id)
		if item_id == "":
			return {}
		var static_item: Dictionary = _data.item(item_id)
		if not static_item.is_empty():
			return static_item
		return state.loot_item(item_id)


func _streak() -> void:
	var s = GameState.new()
	s.bind_data(_data)
	s.set_class("barbarian")
	s.hero()["level"] = 20
	s.hero()["attrStr"] = 40
	var screen: ArenaScreen = ArenaScreen.new(_data, _gen, _loot, s, _resolve(s))
	root.add_child(screen)
	if screen._mana_track == null:
		screen._build()

	var bag_rows := 0
	for fight in range(12):
		if not screen.start(s, _resolve(s)):
			print("fight %d: start FAILED" % fight)
			return
		screen.battle.enemy_hp = 1.0
		screen.battle.enemy_max_hp = 1.0
		screen.battle.hero_hp = 100000.0
		screen.battle.hero_max_hp = 100000.0
		screen.battle.gap = 0.0
		var guard := 0
		while (not screen.battle.ended or not screen._result_built) and guard < 4000:
			screen.step()
			guard += 1
		var names: Array = []
		for item in screen._result_loot_rows:
			names.append(str(item.get("id", "?")))
		bag_rows += screen._result_loot_rows.size()
		print("fight %d: ticks=%d won=%s rows=%d %s | bag=%d gold=%d" % [
			fight, guard, str(screen.battle.won), screen._result_loot_rows.size(),
			str(names), s.inventory().size(), int(s.hero().get("gold", 0))])
		# Leave the result page the way the "Dalsi souboj" tile does.
		screen.another_fight()
	print("total rows over 12 fights = %d" % bag_rows)
