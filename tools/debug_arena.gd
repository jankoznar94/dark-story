extends SceneTree
## Debug: where does the arena actually put things? Positions, not eyeballing.
func _initialize() -> void:
	var main = load("res://scripts/main.gd").new()
	root.add_child(main)
	_go.call_deferred(main)


func _go(main) -> void:
	await process_frame
	await process_frame
	main._on_stop_selected(0, 0)
	var arena = main._screens["arena"]
	for _i in 40:
		arena.step()
	await process_frame
	await process_frame
	print("arena rect=", arena._arena.get_rect())
	print("hero pos=", arena._hero_sprite.position, " size=", arena._hero_sprite.size,
		" visible=", arena._hero_sprite.visible, " tex=", arena._hero_sprite.texture)
	print("portrait pos=", arena._portrait.position, " size=", arena._portrait.size,
		" tex=", arena._portrait.texture)
	print("enemy_hp_label pos=", arena._enemy_hp_label.position)
	print("arc_player pos=", arena._arc_player.position, " size=", arena._arc_player.size)
	print("arc_enemy_hp pos=", arena._arc_enemy_hp.position, " size=", arena._arc_enemy_hp.size)
	print("spell_row=", arena._spell_row.get_rect(), " children=", arena._spell_row.get_child_count())
	print("potion_row children=", arena._potion_row.get_child_count())
	print("mana_label=", arena._mana_label.text, " hero_hp_label=", arena._hero_hp_bar_label.text)
	print("location=", arena._location_label.text)
	print("enemy=", arena.enemy_name if arena.enemy_name != null else "", arena.battle.enemy_name, " face=", arena.battle.enemy_face)
	quit(0)
