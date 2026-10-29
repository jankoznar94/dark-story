extends SceneTree

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")


func _initialize() -> void:
	var data := GameData.new()
	root.add_child(data)
	var gen := ItemGen.new(data)
	var loot := LootSystem.new(data, gen)
	var state := GameState.new()
	state.bind_data(data)
	state.reset()
	state.set_class("barbarian")
	print("A")
	var guard := 0
	while not state.bag_full() and guard < 60:
		state.add_item("filler_%d" % guard, {"id": "filler_%d" % guard, "name": "Filler", "quality": "normal"})
		guard += 1
	print("B guard=%d bag=%d full=%s" % [guard, state.inventory().size(), str(state.bag_full())])
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var item: Dictionary = loot.generate_item(state, 0, 1, false, 1, 0, rng)
	print("C item=%s" % str(item.get("id", "-")))
	quit()
