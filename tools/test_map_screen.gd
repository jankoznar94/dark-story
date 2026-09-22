extends SceneTree
## tools/test_map_screen.gd — the map, driven headlessly.
##
## The map is the screen where the port and the PWA diverged most, and every divergence
## was INVENTED STATE rather than a wrong pixel: a stat line the PWA does not have, a
## "N/10 zastavek" sub-line the PWA does not have, and a stop path that unrolled itself
## on open. A screenshot shows the result; only a test can pin the rule, because each of
## these is a screen that builds, renders and looks plausible while being wrong.
##
## What is pinned here, and why each one needs a test rather than an eye:
##
##   1. **The map STARTS collapsed.** The PWA initialises `_expandedAct = -1`, so the
##      first time the map is opened it is act CARDS ONLY. The port auto-expanded the
##      first unfinished act, which is a different screen — and the difference is a
##      3300px column of stop cards that a reference diff reads as one huge band.
##   2. **Switching difficulty COLLAPSES it again.** `setDifficulty` in the PWA zeroes
##      `_expandedAct` before re-rendering. The port's difficulty button emitted straight
##      at the router, so the stop path stayed open across a switch and `select_difficulty`
##      was unreachable code. This walks the ROUTE the button takes, not the internal call,
##      for the same reason `test_character_modal` does: driving the function directly
##      cannot see a button wired to the wrong target.
##   3. **A collapsed act contributes NO child to the list.** Not "an invisible child" —
##      the list is a VBoxContainer with an 8px separation, and separation is counted
##      between EVERY child, so an empty box moves the next card 8px down. Two of them put
##      act 2 at y=218 where the PWA has y=210.
##   4. **Tapping an act toggles it, and does not write the save.** The PWA's
##      `toggleActExpand` is a pure view toggle; the port saved on every tap.
##   5. **It survives leaving and re-entering the map.** Because (4) removed the save
##      write, the value now lives on the SCREEN — so the PWA's "come back to the act you
##      were working on" behaviour is the port's own responsibility to keep. Pinned so a
##      later cleanup cannot quietly drop it.
##
## Assertions are deferred to `_process` because `Main._ready()` builds the data, the state
## and every screen while `_initialize()` has already run — reaching into `Main` from there
## finds `state == null`.
##
## Run:  godot --headless --path . --script res://tools/test_map_screen.gd
## Pass: prints MAP_SCREEN_ALL_PASS=true and exits 0.

const Main := preload("res://scripts/main.gd")

var _failures: Array[String] = []
var _main: Node = null
var _started := false


func _initialize() -> void:
	_main = Main.new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		if _main._nav_bar == null or _main.state == null:
			return false
		_started = true
		_run()
		return false
	return false


func _run() -> void:
	# NOTE the order: the very first check reads `_expanded_act` before anything in this
	# test touches it. Later checks put the map back to collapsed through the real route.
	_test_starts_collapsed()
	_test_a_collapsed_act_adds_no_child()
	_test_tapping_toggles_without_saving()
	_test_expansion_survives_leaving_the_map()
	_test_difficulty_switch_collapses_the_path()
	_test_locked_acts_are_drawn_only_for_the_first_gate()

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("MAP_SCREEN_ALL_PASS=true")
	else:
		print("MAP_SCREEN_ALL_PASS=false")
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _map() -> Control:
	return _main._screens["map"]


## Put the map back to collapsed through the SAME route the difficulty button uses. Not a
## direct field write: a helper that pokes `_expanded_act` would let the wiring under test
## rot unnoticed.
func _collapse() -> void:
	_map().select_difficulty(0)


## Test 1 must run FIRST and untouched — this is `show_screen("map")` as `Main` left it.
func _test_starts_collapsed() -> void:
	var expanded: int = _map()._expanded_act
	if expanded != -1:
		_fail("the map started with act %d already expanded — the PWA starts at -1 (cards only)"
			% expanded)
	# And entering the map must not expand anything either.
	_main.show_screen("map")
	if _map()._expanded_act != -1:
		_fail("entering the map expanded act %d on its own" % _map()._expanded_act)


## The card is always there; the stop PATH is the extra child. Counting children is the
## assertion, not visibility: an invisible VBox child still eats a separation.
func _test_a_collapsed_act_adds_no_child() -> void:
	_collapse()
	var list: VBoxContainer = _map()._list
	var collapsed_children := list.get_child_count()

	_map()._toggle_act(0)
	var expanded_children := list.get_child_count()
	if expanded_children <= collapsed_children:
		_fail("expanding act 0 did not add its stop path (%d children -> %d)"
			% [collapsed_children, expanded_children])
		return
	# Exactly ONE per act. A collapsed act contributing an empty box would make this 2.
	if expanded_children != collapsed_children + 1:
		_fail("expanding one act added %d children, expected exactly 1 — a collapsed act must add none"
			% (expanded_children - collapsed_children))


## `toggleActExpand` is a view toggle; the only save write the PWA's map makes is
## `setDifficulty`. Compare the serialised save before and after the taps.
func _test_tapping_toggles_without_saving() -> void:
	_collapse()
	var before := JSON.stringify(_main.state.data)

	_map()._toggle_act(0)
	if JSON.stringify(_main.state.data) != before:
		_fail("expanding an act wrote the save — the PWA's toggleActExpand does not")

	if _map()._expanded_act != 0:
		_fail("tapping act 0 left _expanded_act = %d, expected 0" % _map()._expanded_act)

	_map()._toggle_act(0)
	if _map()._expanded_act != -1:
		_fail("tapping the same act twice left it expanded (%d)" % _map()._expanded_act)
	if JSON.stringify(_main.state.data) != before:
		_fail("collapsing an act wrote the save")


## Since the value is no longer saved, the screen is the only thing keeping it — so
## leaving the map and coming back must still show the act the player was working on.
## (This is the PWA behaviour: it opens the map on `_expandedAct`.)
func _test_expansion_survives_leaving_the_map() -> void:
	_collapse()
	_map()._toggle_act(0)
	if _map()._expanded_act != 0:
		_fail("setup failed: act 0 did not expand (%d)" % _map()._expanded_act)
		return
	_main.show_screen("town")
	_main.show_screen("map")
	if _map()._expanded_act != 0:
		_fail("re-entering the map collapsed act 0 — the PWA reopens on the act being worked on")


## The ROUTE the difficulty button takes. `select_difficulty` is what the button is wired
## to; a test that sets `_expanded_act = -1` itself would pass against a button wired
## straight to `difficulty_selected`, which is exactly the state this was found in.
func _test_difficulty_switch_collapses_the_path() -> void:
	_collapse()
	_map()._toggle_act(0)
	if _map()._expanded_act != 0:
		_fail("setup failed: act 0 did not expand (%d)" % _map()._expanded_act)
		return
	# Through the same function the button calls. Difficulty 0 is always unlocked, so the
	# switch commits and the map is re-entered by the router.
	_map().select_difficulty(0)
	if _map()._expanded_act != -1:
		_fail("switching difficulty left act %d expanded — setDifficulty resets it to -1"
			% _map()._expanded_act)

	# And the button itself really is wired to that function, not to the signal.
	_collapse()
	_map()._toggle_act(0)
	for child in _map()._difficulty_row.get_children():
		if child is Button and not (child as Button).disabled:
			(child as Button).pressed.emit()
			break
	if _map()._expanded_act != -1:
		_fail("the difficulty button is not wired to select_difficulty — the stop path stayed open")


## `renderMap` draws a locked act only when it is the FIRST locked one, so the map never
## shows a wall of gates the player cannot reach. A fresh save has act 0 unlocked and act
## 1 locked, so exactly one act card is locked.
func _test_locked_acts_are_drawn_only_for_the_first_gate() -> void:
	_collapse()
	var cards := 0
	for child in _map()._list.get_children():
		if child is Button:
			cards += 1
	if cards != 2:
		_fail("a fresh map drew %d act cards — the PWA draws act 0 and the first locked gate (2)"
			% cards)
