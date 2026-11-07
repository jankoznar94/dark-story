extends SceneTree
## tools/test_clear_save.gd — the nav bar's "Smazat ulozenou hru" entry, which is Jan's cache
## button ("Přidáme tam tlačítko na smazání cache, abych mohl zkusit jít od začátku").
##
## The entry wipes a whole run, so it asks through a MODAL (`scripts/ui/confirm_modal.gd`) and
## then SAYS that it happened. Both halves matter: the old double-tap version armed itself with
## a line of small text on the status strip, Jan tapped once, saw no change and reported the
## button as dead — and he asked for a message he cannot miss ("abych věděl, že k tomu
## skutečně došlo").
##
## Two things live OUTSIDE `GameState.data` and a wipe that forgets them leaves the player in a
## game he did not want: `ZoneMemory` (process memory, deliberately not in the save — fog
## lifted, packs dead) and the derived hero (a `reset()` empties `heroClass`, so a wiped hero
## has no skills, no weapon rules and no mana until the class is re-seeded).
##
## Everything is driven through the REAL input pipeline at the buttons' own centres, not by
## calling the handler: the state half and the finger half break independently, and the finger
## half is what the player reports ("nefunguje").
##
## Run:  godot --headless --path . --script res://tools/test_clear_save.gd
## Pass: prints CLEAR_SAVE_ALL_PASS=true

const ZoneMemory := preload("res://scripts/combat/zone_memory.gd")

var _failures: Array[String] = []
var _main


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)


func _verdict() -> void:
	for f in _failures:
		print("  FAIL: %s" % f)
	print("CLEAR_SAVE_ALL_PASS=%s" % ("true" if _failures.is_empty() else "false"))
	quit(0 if _failures.is_empty() else 1)


func _tap_button(button: Button) -> void:
	var centre := button.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = centre
	root.push_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = centre
	root.push_input(release)
	await process_frame
	await process_frame


func _tap(key: String) -> void:
	await _tap_button(_main._nav_bar._buttons[key])


## The dialog ignores input for `OPEN_GUARD_MS` after it opens: the finger that opened it is
## still on the glass. Headless frames do not advance real time, so the test winds the stamp
## back instead of sleeping.
func _age_dialog() -> void:
	_main._confirm._opened_at -= 5000


func _fresh():
	root.size = Vector2i(390, 844)
	await process_frame
	_main = load("res://scripts/main.gd").new()
	root.add_child(_main)
	await process_frame
	# Headless suites must never touch the player's real save.
	_main.state.save_enabled = true
	# The splash swallows every tap for its 3.1 s, and headless frames do not advance real
	# time — tapping "through" it would report a dead button that is simply covered.
	_main._splash.queue_free()
	await process_frame
	_main.state.delete_save()


## A played-in game: progress on every axis the wipe must reset, plus the caches that do NOT
## live in the save file.
func _seed_played_game() -> void:
	var state = _main.state
	state.hero()["level"] = 9
	state.hero()["xp"] = 4242
	state.hero()["gold"] = 1234
	state.hero()["hp"] = 7
	state.hero()["inventory"] = [{"name": "Test Sword", "type": "weapon"}]
	state.data["talentPoints"] = 6
	state.data["talentLevels"] = {"cleave": 2}
	state.data["locationProgress"] = [4, 0, 0, 0, 0]
	state.data["_maxLocationProgress"] = [4, 0, 0, 0, 0]
	state.data["bossesDefeated"][0][0] = true
	state.data["encounteredMonsters"] = ["skeleton"]
	state.data["difficulty"] = 2
	ZoneMemory.store(1, 0, {"fog": 40, "packs": [1, 2]})
	ZoneMemory.store(1, 1, {"fog": 12})
	state.save()


func _run() -> void:
	await _fresh()

	# --- the trash entry is reachable on the 390px bar ----------------------------------
	print("== the entry sits on the bar ==")
	var bar: Button = _main._nav_bar._buttons["clearsave"]
	var r := bar.get_global_rect()
	_check(r.size.x >= 40.0 and r.position.x >= 0.0 and r.end.x <= 390.0,
		"the clearsave entry is off the 390px canvas: %s" % str(r))

	# --- the first tap ASKS, it does not wipe ------------------------------------------
	print("== tapping the trash asks first ==")
	_seed_played_game()
	await _tap("clearsave")
	_check(_main._confirm.visible, "the trash tap opened no dialog — the entry reads as dead")
	_check(_main._confirm.title_text().contains("Smazat"),
		"the dialog does not say what it will do: '%s'" % _main._confirm.title_text())
	_check(_main._confirm.cancel_button().visible,
		"a destructive confirm with no way back has no cancel button")
	_check(int(_main.state.hero()["gold"]) == 1234,
		"opening the dialog already wiped the gold — nothing may change before the answer")
	_check(int(_main.state.hero()["level"]) == 9, "opening the dialog already reset the level")
	_check(int(ZoneMemory.count()) == 2, "opening the dialog already dropped the zone snapshots")

	# --- cancel changes nothing ---------------------------------------------------------
	print("== cancel changes nothing ==")
	_age_dialog()
	await _tap_button(_main._confirm.cancel_button())
	_check(not _main._confirm.visible, "cancel left the dialog on screen")
	_check(int(_main.state.hero()["gold"]) == 1234, "cancel wiped the gold")
	_check(int(_main.state.hero()["level"]) == 9, "cancel reset the level")
	_check(int(ZoneMemory.count()) == 2, "cancel dropped the zone snapshots")

	# --- a tap on the dim outside the panel backs out too -------------------------------
	print("== a tap outside the panel backs out ==")
	await _tap("clearsave")
	_age_dialog()
	var dim_press := InputEventMouseButton.new()
	dim_press.button_index = MOUSE_BUTTON_LEFT
	dim_press.pressed = true
	dim_press.position = Vector2(20, 20)
	root.push_input(dim_press)
	await process_frame
	var dim_release := InputEventMouseButton.new()
	dim_release.button_index = MOUSE_BUTTON_LEFT
	dim_release.pressed = false
	dim_release.position = Vector2(20, 20)
	root.push_input(dim_release)
	await process_frame
	await process_frame
	_check(not _main._confirm.visible, "a tap on the dim did not close the dialog")
	_check(int(_main.state.hero()["gold"]) == 1234, "a tap on the dim wiped the gold")

	# --- the confirming tap: the full wipe AND a message -------------------------------
	print("== confirming wipes everything and says so ==")
	await _tap("clearsave")
	_age_dialog()
	await _tap_button(_main._confirm.ok_button())

	var h: Dictionary = _main.state.hero()
	_check(int(h["gold"]) == 0, "gold survived the wipe: %d" % int(h["gold"]))
	_check(int(h["level"]) == 1, "level survived the wipe: %d" % int(h["level"]))
	_check(int(h["xp"]) == 0, "xp survived the wipe")
	_check((h["inventory"] as Array).is_empty(), "the bag survived the wipe")
	_check(int(_main.state.data["talentPoints"]) == 0, "talent points survived the wipe")
	_check((_main.state.data["talentLevels"] as Dictionary).is_empty(),
		"talent levels survived the wipe")
	_check(int(_main.state.data["locationProgress"][0]) == 0, "act progress survived the wipe")
	_check(int(_main.state.data["_maxLocationProgress"][0]) == 0,
		"the unlocked-max progress survived the wipe")
	_check(not bool(_main.state.data["bossesDefeated"][0][0]), "a defeated boss survived the wipe")
	_check(int(_main.state.data["difficulty"]) == 0, "difficulty survived the wipe")
	_check((_main.state.data["encounteredMonsters"] as Array).is_empty(),
		"the bestiary survived the wipe")
	_check(_main.state.data["townPortalReturn"] == null,
		"the stored town-portal return survived the wipe")
	# THE CACHES. A wipe that leaves the world standing is the report this test exists for.
	_check(ZoneMemory.count() == 0,
		"%d walked-zone snapshots survived the wipe — the fog and the dead packs are back"
		% ZoneMemory.count())
	# A fresh game needs a class, exactly like a first launch: without one there are no
	# skills, no weapon rules and no mana pool.
	_check(str(_main.state.data["heroClass"]) != "",
		"the wiped save has no class — a hero with no skills and no mana")
	_check(int(h["maxMana"]) > 0, "the wiped hero has an empty mana pool (%d)" % int(h["maxMana"]))
	_check(int(h["hp"]) == int(h["maxHp"]),
		"the wiped hero must be at full HP (%d/%d)" % [int(h["hp"]), int(h["maxHp"])])
	_check(_main._current == "town", "the wipe must land back on the town, on '%s'" % _main._current)

	# The message is the half Jan asked for: he has to SEE that it happened.
	print("== the 'hotovo' message ==")
	_check(_main._confirm.visible, "the wipe said nothing — no confirmation message on screen")
	_check(_main._confirm.title_text() == "Hotovo",
		"the message title is '%s'" % _main._confirm.title_text())
	_check(_main._confirm.body_text().to_lower().contains("smaz"),
		"the message does not say the game was deleted: '%s'" % _main._confirm.body_text())
	_check(not _main._confirm.cancel_button().visible,
		"the 'hotovo' message offers a cancel button; it has nothing to cancel")
	# The dialog must be ABOVE the town it just rebuilt, or the player sees the town instead.
	_check(_main._confirm.get_index() > _main._screens["town"].get_index(),
		"the message sits under the town screen — the player sees the town, not the message")
	_age_dialog()
	await _tap_button(_main._confirm.ok_button())
	_check(not _main._confirm.visible, "the message did not close on its button")

	# --- the SAVE on disk is the new game, not the old one ------------------------------
	print("== the save file on disk ==")
	_check(FileAccess.file_exists(_main.state.SAVE_PATH), "the wipe left no save at all")
	var f := FileAccess.open(_main.state.SAVE_PATH, FileAccess.READ)
	if f != null:
		var text := f.get_as_text()
		f.close()
		var parsed: Variant = JSON.parse_string(text)
		_check(parsed is Dictionary, "the written save is not readable JSON")
		if parsed is Dictionary:
			var saved: Dictionary = parsed
			_check(int(saved.get("hero", {}).get("gold", -1)) == 0,
				"the save on disk still holds gold")
			_check(int(saved.get("hero", {}).get("level", -1)) == 1,
				"the save on disk still holds the old level")
			_check(str(saved.get("heroClass", "")) != "", "the save on disk has no class")
			_check(int((saved.get("locationProgress", [9]) as Array)[0]) == 0,
				"the save on disk still holds act progress")

	_main.state.save_enabled = false
	_main.state.delete_save()
	ZoneMemory.clear_all()
	_main.queue_free()
	_verdict()
