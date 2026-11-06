extends SceneTree
## tools/test_clear_save.gd — the nav bar's "Smazat ulozenou hru" entry, which is Jan's cache
## button ("Přidáme tam tlačítko na smazání cache, abych mohl zkusit jít od začátku").
##
## The old handler called `state.reset()` + `state.save()` and left three things alive, so the
## player tapped it, saw his numbers go to zero and STILL walked into the same half-cleared
## world: `ZoneMemory` (process memory, deliberately outside the save) kept fog lifted and packs
## dead, the hero came out with NO class (no skills, no weapon rules, no mana) because
## `reset()` empties `heroClass`, and the shop/gamble stock caches survived.
##
## Everything is driven through the REAL input pipeline at the button's own centre, not by
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


func _tap(key: String) -> void:
	var button: Button = _main._nav_bar._buttons[key]
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


## A played-in game: progress on every axis the wipe must reset, plus the two caches that do
## NOT live in the save file.
func _seed_played_game() -> void:
	var state = _main.state
	state.hero()["level"] = 9
	state.hero()["xp"] = 4242
	state.hero()["gold"] = 1234
	state.hero()["hp"] = 7
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

	# --- the gate: the first tap ARMS and changes nothing -------------------------------
	print("== the first tap only arms ==")
	_seed_played_game()
	await _tap("clearsave")
	_check(int(_main.state.hero()["gold"]) == 1234,
		"the FIRST tap already wiped the gold (%d) — an irreversible wipe needs its confirm"
		% int(_main.state.hero()["gold"]))
	_check(int(_main.state.hero()["level"]) == 9, "the first tap already reset the level")
	_check(int(ZoneMemory.count()) == 2, "the first tap already dropped the zone snapshots")
	_check(_main._status.text.contains("ZNOVU"),
		"the arming tap must say so on the status strip, got '%s'" % _main._status.text)
	print("  status after the arming tap: '%s'" % _main._status.text)

	# --- another nav entry cancels the arming -------------------------------------------
	print("== a tap elsewhere disarms ==")
	await _tap("music")
	_check(_main._clear_armed_at == 0, "another nav entry must drop the pending wipe")
	await _tap("clearsave")
	_check(int(_main.state.hero()["gold"]) == 1234,
		"the wipe ran on a tap that was only arming again")

	# --- the second tap: the full wipe --------------------------------------------------
	print("== the confirming tap wipes everything ==")
	await _tap("clearsave")
	var h: Dictionary = _main.state.hero()
	_check(int(h["gold"]) == 0, "gold survived the wipe: %d" % int(h["gold"]))
	_check(int(h["level"]) == 1, "level survived the wipe: %d" % int(h["level"]))
	_check(int(h["xp"]) == 0, "xp survived the wipe")
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
	_check(_main._clear_armed_at == 0, "the arming must be consumed by the wipe")

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
			_check(int(saved.get("locationProgress", [9])[0]) == 0,
				"the save on disk still holds act progress")

	# --- the arming EXPIRES ------------------------------------------------------------
	print("== a stale arming does not commit ==")
	_seed_played_game()
	_main._on_clear_save_tapped()
	_check(_main._clear_armed_at != 0, "the handler did not arm")
	_main._clear_armed_at = Time.get_ticks_msec() - _main.CLEAR_ARM_MS - 1000
	_main._on_clear_save_tapped()
	_check(int(_main.state.hero()["gold"]) == 1234,
		"a tap after the window still wiped the game — the arming never expires")

	_main.state.save_enabled = false
	_main.state.delete_save()
	ZoneMemory.clear_all()
	_main.queue_free()
	_verdict()
