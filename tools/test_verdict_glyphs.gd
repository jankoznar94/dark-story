extends SceneTree
## tools/test_verdict_glyphs.gd — the tick and the cross the reaction row shows.
##
## Jan: "po úspěšném Dodge se má zobrazit fajfka a po neúspěšném křížek. Místo obrázku Dodge
## uvnitř hlavního kruhu." The PWA's own pair is `showOpportunitySuccess` /
## `showOpportunityFail` (a green tick / a red cross, `#2ecc71` / `#e74c3c`, on `#mbArrow`),
## and this pins the port's version of them:
##
##   * a CORRECT press raises the tick and hides the middle icon,
##   * a WRONG press raises the cross and closes the window,
##   * the two are never up together,
##   * the cross survives the window's closure (the PWA's `setTimeout(hide, 500)`), and
##   * `_drain_opportunity`'s "missed" also raises the cross — the same signal the PWA uses
##     for an unanswered window.
##
## Run:  godot4 --path . --script res://tools/test_verdict_glyphs.gd
## Pass: prints VERDICT_GLYPHS_ALL_PASS=true and exits 0.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const ArenaScreen := preload("res://scripts/ui/arena_screen.gd")

var _data: Node
var _gen: ItemGen
var _loot: LootSystem
var _failures: Array[String] = []


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_loot = LootSystem.new(_data, _gen)

	_test_the_tick_and_the_cross_are_the_pwas_two_drawings()
	_test_a_correct_press_raises_the_tick_and_drops_the_icon()
	_test_a_wrong_press_raises_the_cross_and_closes_the_window()
	_test_the_cross_outlives_the_window_by_the_pwas_500ms()
	_test_a_missed_window_raises_the_cross_too()
	_test_the_two_are_never_up_together()

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("VERDICT_GLYPHS_ALL_PASS=true")
	else:
		print("VERDICT_GLYPHS_ALL_PASS=false")
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _resolve(state) -> Callable:
	return func(id):
		var item_id := str(id)
		if item_id == "":
			return {}
		var static_item: Dictionary = _data.item(item_id)
		if not static_item.is_empty():
			return static_item
		return state.loot_item(item_id)


func _hero(class_id: String = "barbarian"):
	var s = GameState.new()
	s.bind_data(_data)
	s.set_class(class_id)
	s.hero()["level"] = 20
	s.hero()["attrStr"] = 40
	var sword: Dictionary = _data.item("blade_shortSword")
	if not sword.is_empty():
		s.equip()["weapon"] = "blade_shortSword"
	return s


func _arena(state) -> ArenaScreen:
	var screen: ArenaScreen = ArenaScreen.new(_data, _gen, _loot, state, _resolve(state))
	root.add_child(screen)
	if screen._mana_track == null:
		screen._build()
	if not screen.start(state, _resolve(state)):
		_fail("the arena could not start a fight")
		return screen
	screen.battle.enemy_hp = 100000.0
	screen.battle.enemy_max_hp = 100000.0
	screen.battle.hero_hp = 100000.0
	screen.battle.hero_max_hp = 100000.0
	return screen


## Both glyphs exist, one per verdict, at the PWA's `.boss-attack-arrow` 110px.
func _test_the_tick_and_the_cross_are_the_pwas_two_drawings() -> void:
	var screen = _arena(_hero())
	if not screen._verdict_glyphs.has("success") or not screen._verdict_glyphs.has("fail"):
		_fail("the arena does not build both verdict glyphs")
		return
	for which in ["success", "fail"]:
		var glyph: Control = screen._verdict_glyphs[which]
		if not glyph.visible:
			continue  # nothing to check about a glyph that is not up
		_fail("the %s glyph is up before any press" % which)
	# ⚠️  The colours are the PWA's own two, compared as `Color`s. `int("0x2ecc71")` is 0 in
	# GDScript (the string-to-int cast does not read a hex prefix), which made an earlier
	# version of this check fail against constants that were already right.
	if Color(ArenaScreen.TICK_COLOUR) != Color("#2ecc71"):
		_fail("the tick's colour is not the PWA's #2ecc71")
	if Color(ArenaScreen.CROSS_COLOUR) != Color("#e74c3c"):
		_fail("the cross's colour is not the PWA's #e74c3c")
	if not is_equal_approx(ArenaScreen.ARROW_GLYPH, 110.0):
		_fail("the glyph box is %s, the PWA's .boss-attack-arrow is 110px"
			% str(ArenaScreen.ARROW_GLYPH))


## A CORRECT press: `showOpportunitySuccess` — the tick up, the middle icon gone.
func _test_a_correct_press_raises_the_tick_and_drops_the_icon() -> void:
	var s = _hero()
	var screen = _arena(s)
	var battle = screen.battle
	battle.opp_type = "dodge"
	battle.opp_resolved = false
	battle.opp_failed = false
	screen._refresh_reaction_layer(0.016)
	if not screen._action_icon.visible:
		_fail("test setup: the middle icon is not up with a window open")
		return
	(screen._reaction_buttons["dodge"] as Button).pressed.emit()
	screen._refresh_reaction_layer(0.016)
	if screen._verdict != "success":
		_fail("a correct Dodge press left the verdict at '%s', expected 'success'"
			% screen._verdict)
	if not (screen._verdict_glyphs["success"] as Control).visible:
		_fail("the tick is not visible after a correct press")
	if (screen._verdict_glyphs["fail"] as Control).visible:
		_fail("the cross is visible after a CORRECT press")
	if screen._action_icon.visible:
		_fail("the middle icon is still up after a correct press - the tick replaces it")


## A WRONG press: `showOpportunityFail` — the cross up, the window closed, the icon gone.
func _test_a_wrong_press_raises_the_cross_and_closes_the_window() -> void:
	var s = _hero()
	var screen = _arena(s)
	var battle = screen.battle
	battle.opp_type = "dodge"
	battle.opp_resolved = false
	battle.opp_failed = false
	screen._refresh_reaction_layer(0.016)
	(screen._reaction_buttons["block"] as Button).visible = true
	(screen._reaction_buttons["block"] as Button).pressed.emit()
	if not battle.opp_failed:
		_fail("the wrong press did not close the window")
	if battle.opportunity_open():
		_fail("the window is still open after a wrong press")
	screen._refresh_reaction_layer(0.016)
	if screen._verdict != "fail":
		_fail("a wrong press left the verdict at '%s', expected 'fail'" % screen._verdict)
	if not (screen._verdict_glyphs["fail"] as Control).visible:
		_fail("the cross is not visible after a wrong press")
	if (screen._verdict_glyphs["success"] as Control).visible:
		_fail("the tick is visible after a WRONG press")
	if screen._action_icon.visible:
		_fail("the middle icon is still up after a wrong press")


## ⚠️  The regression this test exists for: the window closes on the spot for a wrong press,
## so a verdict ticked only while the window was open vanished on the next frame. The PWA's
## `setTimeout(() => hideOpportunityArrow(mb), 500)` is the whole reason the cross is visible
## at all, so the port keeps it for 500 ms too.
func _test_the_cross_outlives_the_window_by_the_pwas_500ms() -> void:
	var s = _hero()
	var screen = _arena(s)
	var battle = screen.battle
	battle.opp_type = "dodge"
	screen._refresh_reaction_layer(0.016)
	(screen._reaction_buttons["block"] as Button).visible = true
	(screen._reaction_buttons["block"] as Button).pressed.emit()
	if not is_equal_approx(ArenaScreen.HIDE_AFTER_MS, 500.0):
		_fail("the hide delay is %s, the PWA's setTimeout is 500"
			% str(ArenaScreen.HIDE_AFTER_MS))
	# Half of it gone: still up.
	screen._refresh_reaction_layer(0.25)
	if not (screen._verdict_glyphs["fail"] as Control).visible:
		_fail("the cross disappeared before its 500 ms")
	# Past it: gone.
	screen._refresh_reaction_layer(0.30)
	if (screen._verdict_glyphs["fail"] as Control).visible:
		_fail("the cross is still up after 550 ms")


## An UNANSWERED window: `resolveOpportunity` writes the "missed" word, which the PWA draws
## with the same cross it draws for a mistake.
func _test_a_missed_window_raises_the_cross_too() -> void:
	var s = _hero()
	var screen = _arena(s)
	var battle = screen.battle
	battle.opp_type = "dodge"
	battle.opp_resolved = false
	battle.opp_failed = false
	battle.opp_feedback = "missed"
	screen._refresh_reaction_layer(0.016)
	screen._drain_opportunity()
	screen._refresh_reaction_layer(0.016)
	if screen._verdict != "fail":
		_fail("a missed window left the verdict at '%s', expected 'fail'" % screen._verdict)
	if not (screen._verdict_glyphs["fail"] as Control).visible:
		_fail("a missed window shows no cross")


## Never both, on any frame of either path.
func _test_the_two_are_never_up_together() -> void:
	var s = _hero()
	var screen = _arena(s)
	var battle = screen.battle
	for kind in ["dodge", "block"]:
		battle.opp_type = "dodge"
		battle.opp_type = "dodge"
		screen._refresh_reaction_layer(0.016)
		var button: Button = screen._reaction_buttons[kind]
		button.visible = true
		button.pressed.emit()
		for step in 12:
			screen._refresh_reaction_layer(0.05)
			var tick := (screen._verdict_glyphs["success"] as Control).visible
			var cross := (screen._verdict_glyphs["fail"] as Control).visible
			if tick and cross:
				_fail("the tick and the cross are up together (after pressing %s)" % kind)
				return
		# And a fresh window clears whatever was held.
		battle.opp_type = "dodge"
		screen._refresh_reaction_layer(0.016)
		if screen._verdict != "":
			_fail("a new window inherited the previous verdict '%s'" % screen._verdict)
			return
