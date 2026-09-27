extends SceneTree
## tools/test_portal_use.gd — where a Town Portal scroll can be USED, and what each place does.
##
## Jan's correction: "ještě musí být někde možnost portal scroll použít. Ne jen pro návrat."
##
## There are exactly THREE places in this game that spend a scroll, and they are NOT the same
## rule — the fourth place (the town's own card) only RETURNS and spends nothing. Reading them
## as one thing is how the map ends up with a button that never appears:
##
##   arena result page  `useTownPortalScrollFromResult`  stores the position, spends a scroll
##   the MAP            `useTownPortalScrollFromMap`     stores the position, spends a scroll
##   the inventory      `useTownPortalScroll`            (PWA only — see below)
##   the town's card    `useTownPortal`                  RETURNS to the stored position, free
##
## ⚠️  `map_screen._portal_button.visible` was set only in `_build()`, i.e. once, to `false` —
## nothing ever raised it. The map's second use was unreachable code with a dead button on top
## of it, and no existing test could see it: `test_portal_return` drives the RESULT page's tile
## and asserts the position and the count, both of which are correct. A button that is never
## visible is invisible to every assertion about what a tap does.
##
## ⚠️  The third place does not exist here on purpose. The PWA's `useTownPortalScroll` is a
## function with NO caller anywhere in the build (grepped across `src/` and `index.html`), and
## no item in the save is a town portal scroll — the count is a NUMBER (`townPortalCount`
## incremented by `buyItem`), so the inventory shows no item to act on. Porting it would be
## inventing an item the player never had. That is asserted below so the decision is visible
## rather than looking like an omission.
##
## Run:  godot --headless --path . --script res://tools/test_portal_use.gd
## Pass: prints PORTAL_USE_ALL_PASS=true and exits 0.

const Main := preload("res://scripts/main.gd")

## The save is global state shared with the player's own game — read it, run on a fresh one,
## put it back. Same shape as `test_portal_return.gd`, which learned this the hard way.
var _saved_bytes: PackedByteArray = PackedByteArray()
var _had_save := false

var _main: Node = null
var _started := false
var _failures: Array[String] = []


func _initialize() -> void:
	_stash_save()
	_main = Main.new()
	root.add_child(_main)


func _save_path() -> String:
	return "user://dungeon_recall_save.json"


func _stash_save() -> void:
	_had_save = FileAccess.file_exists(_save_path())
	if _had_save:
		var f := FileAccess.open(_save_path(), FileAccess.READ)
		if f != null:
			_saved_bytes = f.get_buffer(f.get_length())
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_path()))


func _restore_save() -> void:
	if not _had_save:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_path()))
		return
	var f := FileAccess.open(_save_path(), FileAccess.WRITE)
	if f != null:
		f.store_buffer(_saved_bytes)


func _process(_delta: float) -> bool:
	if not _started:
		if _main._nav_bar == null or _main.state == null or not _main._screens.has("map"):
			return false
		_started = true
		_run()
		for f in _failures:
			print("  FAIL: %s" % f)
		print("PORTAL_USE_ALL_PASS=%s" % ("true" if _failures.is_empty() else "false"))
		_restore_save()
		quit(0 if _failures.is_empty() else 1)
		return true
	return false


func _fail(msg: String) -> void:
	_failures.append(msg)


## A fresh game with the hero mid-zone and `count` scrolls carried.
func _seed(count: int) -> void:
	_main.state.data["locationProgress"][0] = 2
	_main.state.data["areaFightProgress"][0] = 6
	_main.state.data["townPortalCount"] = count
	_main.state.data["townPortalReturn"] = null
	if str(_main.state.data.get("heroClass", "")) == "":
		_main.state.set_class("barbarian")


func _run() -> void:
	_test_the_map_button_appears_only_when_a_scroll_is_carried()
	_test_the_map_button_spends_a_scroll_and_stores_the_fight()
	_test_the_town_card_returns_for_free()
	_test_the_inventory_does_not_offer_a_scroll()
	_test_using_the_portal_does_not_move_the_player()


## --- 1. visibility: this is the whole bug ------------------------------------------------
func _test_the_map_button_appears_only_when_a_scroll_is_carried() -> void:
	_seed(0)
	_main.show_screen("map")
	var button: Button = _main._screens["map"]._portal_button
	if button == null:
		_fail("the map has no portal button at all")
		return
	if button.visible:
		_fail("the map offers a Town Portal with no scroll carried - the button is a lie")
		return
	_seed(1)
	_main.show_screen("map")
	if not button.visible:
		_fail("the map never offers the Town Portal, so a carried scroll cannot be used there")
	# And it must come back DOWN again: a one-way flag is the same bug in the other direction.
	_main.state.data["townPortalCount"] = 0
	_main.show_screen("map")
	if button.visible:
		_fail("the map still offers the Town Portal after the last scroll is gone")


## --- 2. the map's own rule: store the position AND spend the scroll ----------------------
func _test_the_map_button_spends_a_scroll_and_stores_the_fight() -> void:
	_seed(2)
	_main.show_screen("map")
	# Drive the BUTTON's own handler, not `_refresh_actions` — the wiring is what a player
	# touches, and a test that calls the function directly passes against a dead button.
	var button: Button = _main._screens["map"]._portal_button
	button.pressed.emit()
	var before := int(_main.state.data["townPortalCount"])
	if before != 1:
		_fail("the map's Town Portal did not spend a scroll (2 -> %d)" % before)
	var stored: Variant = _main.state.data.get("townPortalReturn")
	if stored == null:
		_fail("the map's Town Portal stored no return position - the scroll is simply lost")
		return
	var p: Dictionary = stored
	var act: int = _main._current_act_on_map()
	if int(p.get("actId", -1)) != act:
		_fail("the map stored act %s against the current act %d" % [str(p.get("actId")), act])
	if int(p.get("zoneId", -1)) != 2 or int(p.get("areaFight", -1)) != 6:
		_fail("the map stored zone %s fight %s, wanted 2/6 (the fight the player is on)"
			% [str(p.get("zoneId")), str(p.get("areaFight"))])


## --- 3. the town's card is the RETURN, and it is free ------------------------------------
func _test_the_town_card_returns_for_free() -> void:
	_seed(1)
	_main.show_screen("map")
	_main._screens["map"]._portal_button.pressed.emit()
	var spent := int(_main.state.data["townPortalCount"])
	# Walking to town is what a player does after taking the portal; the zone's fights reset,
	# and the RETURN is what has to put him back.
	_main._on_walk_to_town()
	_main._on_town_portal()
	if int(_main.state.data["areaFightProgress"][0]) != 6:
		_fail("the town's return did not restore the fight (%d, wanted 6)"
			% int(_main.state.data["areaFightProgress"][0]))
	if int(_main.state.data["townPortalCount"]) != spent:
		_fail("the RETURN spent a scroll (%d -> %d) - it was already spent on the way out"
			% [spent, int(_main.state.data["townPortalCount"])])
	if _main.state.data.get("townPortalReturn") != null:
		_fail("the stored position survived the return - the town's card stays up forever")


## --- 4. the third place does NOT exist here, on purpose ----------------------------------
func _test_the_inventory_does_not_offer_a_scroll() -> void:
	# The scroll is a COUNT, not an item: `buyItem` increments `townPortalCount` and never puts
	# it in the bag, so there is nothing in the inventory to use. If a later change ever adds
	# the item to the bag, this assertion is the thing that says "now the PWA's third entry
	# point has a home" — and porting `useTownPortalScroll` becomes the right move.
	_seed(1)
	var bag: Array = _main.state.data.get("inventory", [])
	for entry in bag:
		var id := str(entry)
		if id == "townPortalScroll":
			_fail("a town portal scroll is now a real item in the bag - the PWA's"
				+ " `useTownPortalScroll` (inventory) is the missing entry point, not a"
				+ " count-only design")


## --- 5. taking the portal must not move the player before he returns ---------------------
func _test_using_the_portal_does_not_move_the_player() -> void:
	_seed(1)
	_main.show_screen("map")
	_main._screens["map"]._portal_button.pressed.emit()
	if int(_main.state.data["areaFightProgress"][0]) != 6:
		_fail("taking the portal moved the player's own position before he returned")
