extends SceneTree
const GameData := preload("res://scripts/data/game_data.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const Battle := preload("res://scripts/combat/battle.gd")
func _initialize() -> void:
	var data := GameData.new()
	root.add_child(data)
	var state := GameState.new()
	state.bind_data(data)
	state.set_class("barbarian")
	var find := func(id): return data.item(str(id)) if id != null else {}
	var b := Battle.new(data, 1234)
	b.act_id = 0
	b.setup(state, find)
	b.enemy_attack_type = "melee"
	b.apply_swing_timers(state, find)
	var windows := 0
	var dodges := 0
	var total := 0
	for i in 40:
		state.hero()["hp"] = 100000
		b.hero_hp = 100000.0
		if b.opportunity_open():
			windows += 1
		var before: float = b.hero_hp
		var r: Dictionary = b.enemy_attack(state, find)
		total += int(100000.0 - b.hero_hp)
		if str(r.get("reason","")) == "opportunity":
			dodges += 1
	print("windows_seen=", windows, " dodges=", dodges, " total=", total,
		" cooldown=", b.opp_cooldown_ms, " opp_type=", b.opp_type)
	quit()
