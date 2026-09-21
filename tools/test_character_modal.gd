extends SceneTree
## tools/test_character_modal.gd — the character modal, driven headlessly.
##
## In the PWA, `inventory`, `talents` and `hero` are NOT screens. `showScreen()` routes all
## three into `openModal()`, which builds ONE dialog holding a `.combined-tabs` strip and
## three `.combined-screen` panes, and always opens it on the Inventory tab. The port had
## them as three separate screens behind the nav bar — so "the hero screen" carried the
## portrait, the attributes, the stat sheet AND the whole skill trees in one column, which
## is a shape the PWA never had and the main reason the two read as different games.
##
## This test pins the structure back, and the three failures that a *gameplay* test cannot
## see because each one is a screen that is built, visible and correct — and wrong:
##
##   1. **The modal opens but every other screen stays visible.** Screens are siblings in
##      one CanvasLayer and the town is added AFTER the modal, so it paints OVER the
##      dialog. The dialog is visible, correct and completely covered. (`show_screen()`
##      hides the others; opening the modal is a second way in and has to do it too.)
##   2. **The tabs all show the same pane.** The tab key and the pane key are different
##      vocabularies — the PWA's tab ids (`inventory`/`talents`/`hero`) versus this port's
##      pane keys (`inventory`/`skills`/`stats`) — and a mismatch renders one pane for
##      every tab while the strip highlights the tab you tapped.
##   3. **The nav bar stays up over the dialog.** Unreachable behind the overlay in the
##      PWA; tappable in the port, which means a tap meant for the dialog fires a nav entry.
##
## The assertions are deferred to `_process` on purpose. `Main._ready()` builds the data,
## the state and every screen, and `_initialize()` runs BEFORE it — reaching into `Main`
## from there finds `state == null` and every check below fails on a nil-dereference
## instead of on the thing it is checking. So: build in `_initialize`, assert in `_process`
## once `Main` reports itself finished, exactly as `tools/capture_screen.gd` does.
##
## Run:  godot --headless --path . --script res://tools/test_character_modal.gd
## Pass: prints CHARACTER_MODAL_ALL_PASS=true and exits 0.

const Main := preload("res://scripts/main.gd")

var _failures: Array[String] = []
var _main: Node = null
var _started := false


func _initialize() -> void:
	_main = Main.new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		# `_nav_bar` is built after the screens and before `_ready()` hands over to the
		# town, so it is the last cheap marker that Main is fully constructed.
		if _main._nav_bar == null or _main.state == null:
			return false
		_started = true
		_run()
		return false
	return false


func _run() -> void:
	_test_the_old_three_screens_are_gone()
	_test_open_modal_hides_every_other_screen()
	_test_each_tab_shows_its_own_pane()
	_test_nav_keys_map_to_distinct_panes()
	_test_nav_bar_is_hidden_over_the_modal()
	_test_closing_returns_to_town()

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("CHARACTER_MODAL_ALL_PASS=true")
	else:
		print("CHARACTER_MODAL_ALL_PASS=false")
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


## `inventory` and `hero` must NOT exist as screens. Their presence is the regression:
## a character sheet and a stat sheet as separate nav destinations instead of one dialog.
func _test_the_old_three_screens_are_gone() -> void:
	for stale in ["inventory", "hero", "talents"]:
		if _main._screens.has(stale):
			_fail("screen '%s' still exists — the PWA has it as a TAB of the character modal" % stale)
	if not _main._screens.has("character"):
		_fail("no 'character' screen — the modal was never built")


## Failure #1: a dialog that opens but is painted over.
func _test_open_modal_hides_every_other_screen() -> void:
	_main.show_screen("town")
	_main.open_modal("inventory")
	for key in _main._screens:
		var visible: bool = (_main._screens[key] as Control).visible
		if str(key) == "character":
			if not visible:
				_fail("the modal is not visible after open_modal()")
		elif visible:
			_fail("screen '%s' is still visible while the modal is open — it paints over the dialog" % str(key))


## Failure #2: three tabs, one pane. Assert each tab shows a DIFFERENT pane.
func _test_each_tab_shows_its_own_pane() -> void:
	var modal = _main._screens["character"]
	var seen: Dictionary = {}
	for tab in ["inventory", "skills", "stats"]:
		_main.open_modal(tab)
		if str(modal._active) != tab:
			_fail("set_tab('%s') left _active = '%s'" % [tab, str(modal._active)])
		var shown: Array[String] = []
		for pane_key in modal._panes:
			if (modal._panes[pane_key] as Control).visible:
				shown.append(str(pane_key))
		if shown.size() != 1:
			_fail("tab '%s' shows %d panes, expected exactly 1 (%s)" % [tab, shown.size(), str(shown)])
			continue
		if seen.has(shown[0]):
			_fail("tab '%s' shows the same pane ('%s') as tab '%s' — the tabs are aliases"
				% [tab, shown[0], str(seen[shown[0]])])
		seen[shown[0]] = tab
	if seen.size() != 3:
		_fail("the three tabs resolve to %d distinct panes, expected 3" % seen.size())


## The ROUTE a tap takes: `NavBar` emits `inventory`/`talents`/`hero` and the router maps
## them through `MODAL_TABS` onto pane keys. The pane test above drives `open_modal` with
## the PANE key directly, so it cannot see a wrong mapping — and a wrong mapping is the
## realistic bug, because the two vocabularies differ. This walks the real path: emit the
## nav key, then ask which pane is showing.
func _test_nav_keys_map_to_distinct_panes() -> void:
	var modal = _main._screens["character"]
	var seen: Dictionary = {}
	for nav_key in ["inventory", "talents", "hero"]:
		_main._on_nav_selected(nav_key)
		var shown: Array[String] = []
		for pane_key in modal._panes:
			if (modal._panes[pane_key] as Control).visible:
				shown.append(str(pane_key))
		if shown.size() != 1:
			_fail("nav key '%s' shows %d panes, expected 1 (%s)" % [nav_key, shown.size(), str(shown)])
			continue
		if seen.has(shown[0]):
			_fail("nav key '%s' lands on pane '%s', which nav key '%s' already uses"
				% [nav_key, shown[0], str(seen[shown[0]])])
		seen[shown[0]] = nav_key
	if seen.size() != 3:
		_fail("the three nav keys resolve to %d distinct panes, expected 3" % seen.size())


## Failure #3: a nav bar that stays up over the dialog.
func _test_nav_bar_is_hidden_over_the_modal() -> void:
	_main.show_screen("town")
	_main.open_modal("stats")
	if _main._nav_bar != null and _main._nav_bar.visible:
		_fail("the nav bar is still visible over the modal — a tap meant for the dialog hits it")


func _test_closing_returns_to_town() -> void:
	_main.open_modal("skills")
	_main._close_modal()
	if str(_main._current) != "town":
		_fail("closing the modal left _current = '%s', expected 'town'" % str(_main._current))
	for key in _main._screens:
		var visible: bool = (_main._screens[key] as Control).visible
		if str(key) == "town" and not visible:
			_fail("closing the modal did not bring the town back")
		elif str(key) != "town" and visible:
			_fail("screen '%s' is visible after closing the modal" % str(key))
