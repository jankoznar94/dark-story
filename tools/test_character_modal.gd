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
	_test_open_modal_keeps_the_screen_underneath()
	_test_each_tab_shows_its_own_pane()
	_test_nav_keys_map_to_distinct_panes()
	_test_nav_bar_is_drawn_under_the_modal_not_hidden()
	_test_closing_returns_to_town()
	_test_inventory_pane_has_exactly_the_pwas_children()
	_test_each_pane_carries_its_own_padding()
	_test_bag_cells_are_the_measured_width()
	_test_doll_slots_carry_their_measured_sizes()
	_test_equip_slots_clip_their_children()
	_test_item_info_overlay_exists_outside_the_pane()
	_test_bag_tap_opens_the_overlay_without_equipping()
	_test_closing_the_overlay_clears_the_selection()
	_test_equip_slot_tap_shows_info_then_unequips()
	_test_empty_slot_opens_nothing()

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


## Failure #1 used to be "a dialog that opens but is painted over" — the port hid every
## other screen. The PWA does NOT: measured on the live build with the dialog open,
## `townScreen` is still laid out and `.nav-bar` is still up, both merely covered by the
## `rgba(0,0,0,0.7)` overlay. Hiding them turned the dialog into a black page where the
## original is a half-transparent one over the town, which is most of the visual diff.
##
## So the assertion is the real one: the screen UNDER the dialog stays visible, every
## OTHER screen is hidden, and the dialog is on a layer that paints above them.
func _test_open_modal_keeps_the_screen_underneath() -> void:
	_main.show_screen("town")
	_main.open_modal("inventory")
	for key in _main._screens:
		var visible: bool = (_main._screens[key] as Control).visible
		if str(key) == "character" or str(key) == "town":
			if not visible:
				_fail("screen '%s' is hidden while the modal is open — the PWA leaves it visible under the overlay" % str(key))
		elif visible:
			_fail("screen '%s' is visible while the modal is open" % str(key))
	# And it must be painted UNDER the dialog, not over it: the dialog has its own layer.
	if _main._modal_layer == null:
		_fail("the modal has no CanvasLayer of its own — node order cannot put it over the nav bar")
	else:
		var ui_layer := _main.get_node_or_null("UI") as CanvasLayer
		if ui_layer == null:
			_fail("the screens' CanvasLayer 'UI' is missing")
		elif _main._modal_layer.layer <= ui_layer.layer:
			_fail("the modal layer (%d) is not above the screens' layer (%d)"
				% [_main._modal_layer.layer, ui_layer.layer])
		if _main._nav_bar != null and _main._modal_layer.layer <= 5:
			_fail("the modal layer (%d) is not above the nav bar's layer (5)"
				% _main._modal_layer.layer)


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


## The nav bar stays VISIBLE over the dialog, as it does in the PWA (`nav_hidden: false`
## measured with the modal open). It is not hidden — it is covered: the dialog's overlay
## sits on a higher layer, which is how `.modal-overlay { z-index:1000 }` swallows the
## taps that `.nav-bar { z-index:100 }` would otherwise receive. Hiding the bar was the
## port's own invention and it showed, because the PWA's bar is still drawn behind the dim.
func _test_nav_bar_is_drawn_under_the_modal_not_hidden() -> void:
	_main.show_screen("town")
	_main.open_modal("stats")
	if _main._nav_bar == null:
		_fail("the nav bar was never built")
		return
	if not _main._nav_bar.visible:
		_fail("the nav bar is hidden over the modal — the PWA keeps it visible under the overlay")
	if _main._modal_layer == null or _main._modal_layer.layer <= 5:
		_fail("nothing puts the dialog above the nav bar, so the bar is tappable through it")


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


## The PWA's `#inventoryScreen` holds exactly THREE children and nothing else. Measured
## live (`probe_pane_pwa.py inventory`): `inv-equip-panel [13,112 364x326]`,
## `inv-potion-slots [13,450 364x36]`, `inv-grid-wrap [13,494 364x295]`.
##
## The port carried six: the three real ones plus a "Batoh" heading, a "Belt" heading and a
## permanent "Sockets" block with a stat line. All three were INVENTIONS, and invented state
## is the largest visual diff on any screen because it moves every real element below it.
## The PWA's item detail (socketing included) is `#invItemOverlay`, a tap-through overlay
## OUTSIDE this element — so a socket block in the pane is wrong however useful it looks.
func _test_inventory_pane_has_exactly_the_pwas_children() -> void:
	var modal = _main._screens["character"]
	_main.open_modal("inventory")
	var inventory = modal._panes["inventory"].get_child(0).get_child(0)
	# `_build()` puts ONE column in the pane; that column carries the three blocks.
	if inventory.get_child_count() != 1:
		_fail("the embedded inventory built %d children, expected 1 column"
			% inventory.get_child_count())
		return
	var column: Control = inventory.get_child(0)
	if column.get_child_count() != 3:
		var names: Array[String] = []
		for child in column.get_children():
			names.append(child.get_class())
		_fail("the inventory column has %d blocks, the PWA has 3 (%s) — an extra block is invented state"
			% [column.get_child_count(), ", ".join(names)])


## Each pane has its OWN padding in the PWA and the port applied one uniform 4px body
## margin to all three. Measured with `probe_pane_pwa.py`:
##   inventory `[9,100 372x697]`   its `.container` overridden to `padding:0 4px`
##   talents   `[9,117 372x590]`   `.container { padding:16px 16px 70px }`
##   hero      `[9,117 372x591]`   overridden to `padding:0 4px 16px`
## With a uniform margin the talents tree was 34px too wide and its cells came out 118
## against the PWA's 106.7 — the "skilly jsou moc siroké" report.
func _test_each_pane_carries_its_own_padding() -> void:
	var modal = _main._screens["character"]
	var pads := {"inventory": [0, 4, 0, 4], "skills": [16, 16, 70, 16],
		"stats": [0, 4, 16, 4]}
	for key in pads:
		_main.open_modal(key)
		var pane = modal._panes[key]
		if not (pane is MarginContainer):
			_fail("pane '%s' is a %s — the padding has to come from a MarginContainer"
				% [key, pane.get_class()])
			continue
		var want: Array = pads[key]
		for axis in [["margin_top", 0], ["margin_right", 1], ["margin_bottom", 2],
				["margin_left", 3]]:
			var got := int(pane.get_theme_constant(str(axis[0])))
			if got != int(want[int(axis[1])]):
				_fail("pane '%s' %s is %d, the PWA's CSS says %d"
					% [key, str(axis[0]), got, int(want[int(axis[1])])])


## `.inv-grid { grid-template-columns:repeat(5, 1fr); gap:6px }` inside `#invGridWrap`
## (364 wide, minus 2px border, minus 24px padding = 338). The live PWA computes
## `cols=62.8281px 62.8438px 62.8281px 62.8438px 62.8438px`.
##
## The port hardcoded 55, so every cell was 8px narrow and the fifth landed at x=313
## instead of 301 — the row visibly stopped short of its own frame.
func _test_bag_cells_are_the_measured_width() -> void:
	var modal = _main._screens["character"]
	_main.open_modal("inventory")
	var inventory = modal._panes["inventory"].get_child(0).get_child(0)
	var cell: float = inventory.BAG_CELL
	if absf(cell - 62.8) > 0.1:
		_fail("the bag cell is %.1fpx, the live PWA computes 62.8" % cell)
	if inventory.GRID_COLUMNS != 5:
		_fail("the bag grid has %d columns, the PWA's `repeat(5, 1fr)` says 5"
			% inventory.GRID_COLUMNS)


## Every slot's own measured size, and which edge it hugs. `style.css`:
##   `.inv-slot-square { 75x75 }`  `.inv-slot-tall { 75x110 }`
##   `.inv-slot-small { 48x48 }`   `.inv-slot-belt { 75x48 }`  `.inv-slot-tp { 48x48 }`
##   `#invSlotTownPortal/#invSlotWeapon/#invSlotRing1 { justify-self:end }`
##   `#invSlotShield/#invSlotGloves { justify-self:start }`
## The port drew the amulet and both rings at 75 and had no town-portal slot at all, so a
## 75px icon overflowed a 48px border — the "itemy byly větší než equip sloty" report.
##
## ⚠️ The assertion is the TOTAL drawn size, not `custom_minimum_size`. The PWA has
## `* { box-sizing:border-box }`, so its 75px INCLUDES the 1px border; Godot draws a
## stylebox border OUTSIDE the content box, so the minimum is 73 and the drawn slot is 75.
## Comparing the minimum against the CSS number demands a 75px slot that DRAWS 77 — the
## assertion has to add the border back, or it pins the very bug it is meant to catch.
func _test_doll_slots_carry_their_measured_sizes() -> void:
	var modal = _main._screens["character"]
	_main.open_modal("inventory")
	var inventory = modal._panes["inventory"].get_child(0).get_child(0)
	var want := {
		"townPortal": Vector2(48, 48), "helmet": Vector2(75, 75), "amulet": Vector2(48, 48),
		"weapon": Vector2(75, 110), "armor": Vector2(75, 110), "shield": Vector2(75, 110),
		"ring1": Vector2(48, 48), "belt": Vector2(75, 48), "ring2": Vector2(48, 48),
		"gloves": Vector2(75, 75), "boots": Vector2(75, 75),
	}
	for slot in want:
		if not inventory._slot_nodes.has(slot):
			_fail("no '%s' slot — the PWA's paper doll has it (town portal included)" % slot)
			continue
		var button: Button = inventory._slot_nodes[slot]
		var expect: Vector2 = want[slot]
		var style: StyleBoxFlat = button.get_theme_stylebox("normal")
		var drawn: Vector2 = button.custom_minimum_size + Vector2(
			style.border_width_left + style.border_width_right,
			style.border_width_top + style.border_width_bottom)
		if not drawn.is_equal_approx(expect):
			_fail("slot '%s' draws %.0fx%.0f, the PWA's CSS says %.0fx%.0f"
				% [slot, drawn.x, drawn.y, expect.x, expect.y])


## `overflow:hidden` on the live PWA's slots, and the port had no equivalent: Godot does
## NOT clip a Button's children, so an icon that reached the slot's edge drew over the
## border and past the rounded corner. `clip_contents` is the one property that fixes it,
## and it is invisible to every other test in this suite.
func _test_equip_slots_clip_their_children() -> void:
	var modal = _main._screens["character"]
	_main.open_modal("inventory")
	var inventory = modal._panes["inventory"].get_child(0).get_child(0)
	for slot in inventory._slot_nodes:
		var button: Button = inventory._slot_nodes[slot]
		if not button.clip_contents:
			_fail("slot '%s' does not clip its children — the PWA's slot is `overflow:hidden`"
				% slot)


## The item-info overlay: the PWA's `#invItemOverlay`, opened by a tap on a bag cell or an
## equipment slot. It was missing from the port entirely, so a player could equip but
## never read an item's stats or compare it against what is worn. These assertions are the
## structure — the overlay exists, is mounted OUTSIDE the inventory pane at full size, and
## is closed until something is tapped.
func _test_item_info_overlay_exists_outside_the_pane() -> void:
	var modal = _main._screens["character"]
	_main.open_modal("inventory")
	var inventory = modal._panes["inventory"].get_child(0).get_child(0)
	if inventory._item_overlay == null:
		_fail("the inventory has no item-info overlay — the PWA's `#invItemOverlay` is missing")
		return
	if inventory._item_overlay.visible:
		_fail("the item-info overlay is visible with nothing selected")
	# It must NOT be a child of the inventory pane: a fourth child there is invented state
	# and the pane's own box would clip a full-screen overlay.
	var column: Control = inventory.get_child(0)
	if column.get_child_count() != 3:
		_fail("the inventory column has %d blocks after the overlay was added, the PWA has 3 — the overlay belongs OUTSIDE the pane"
			% column.get_child_count())
	if inventory._item_overlay.get_parent() == null:
		_fail("the item-info overlay was never mounted, so it cannot be shown")


## A tap on a bag cell OPENS the overlay and does NOT equip. That ordering is the PWA's:
## the item info comes first and equipping is the overlay's own button.
func _test_bag_tap_opens_the_overlay_without_equipping() -> void:
	var modal = _main._screens["character"]
	_main.open_modal("inventory")
	var inventory = modal._panes["inventory"].get_child(0).get_child(0)
	var state = _main.state
	state.set_class("barbarian")
	# A weapon the barbarian may NOT wear, so an accidental equip is visible.
	# ⚠️ The id has to be REAL: a nonexistent one makes `_resolve` return {} and the tap
	# refuses to open the overlay, which reads as "the overlay is broken" instead of "the
	# test named an item the table does not have".
	state.inventory().clear()
	state.inventory().append("claws_katar")
	state.equip()["weapon"] = "blade_shortSword"
	var weapon_before: Variant = state.equip().get("weapon")
	inventory._on_bag_tapped(0)
	if not inventory._item_overlay.visible:
		_fail("tapping a bag cell did not open the item-info overlay")
	if state.equip().get("weapon") != weapon_before:
		_fail("tapping a bag cell EQUIPPED the item — the PWA shows the info and equips from its button")
	if inventory.shown_item_id() != "claws_katar":
		_fail("the overlay shows '%s', expected the tapped item 'claws_katar'"
			% inventory.shown_item_id())


## Closing the overlay clears the selection, so the next tap starts clean.
func _test_closing_the_overlay_clears_the_selection() -> void:
	var modal = _main._screens["character"]
	_main.open_modal("inventory")
	var inventory = modal._panes["inventory"].get_child(0).get_child(0)
	state_reset_for_overlay(inventory)
	inventory._on_bag_tapped(0)
	if not inventory._item_overlay.visible:
		_fail("could not open the overlay to test closing it")
		return
	inventory.close_item_info()
	if inventory._item_overlay.visible:
		_fail("closing the overlay left it visible")
	if inventory._selected_bag != -1 or inventory._selected_slot != "":
		_fail("closing the overlay left a selection behind (bag=%d slot='%s')"
			% [inventory._selected_bag, inventory._selected_slot])


func state_reset_for_overlay(inventory) -> void:
	_main.state.set_class("barbarian")
	_main.state.inventory().clear()
	_main.state.inventory().append("blade_shortSword")


## An equip-slot tap shows the WORN item with an Unequip button; a second tap on the same
## slot takes it off. That two-step is the PWA's `_invSelectedSlot` behaviour and it is why
## one tap never silently removes a piece of gear.
func _test_equip_slot_tap_shows_info_then_unequips() -> void:
	var modal = _main._screens["character"]
	_main.open_modal("inventory")
	var inventory = modal._panes["inventory"].get_child(0).get_child(0)
	var state = _main.state
	state.set_class("barbarian")
	state.inventory().clear()
	state.equip()["armor"] = "armor_leather"
	var slot_before: Variant = state.equip().get("armor")

	inventory._on_equip_slot_pressed("armor")
	if not inventory._item_overlay.visible:
		_fail("tapping a filled equip slot did not open the item-info overlay")
		return
	if inventory._item_overlay.origin() != "equipped":
		_fail("the overlay opened with origin '%s', expected 'equipped'"
			% inventory._item_overlay.origin())
	if state.equip().get("armor") != slot_before:
		_fail("the FIRST tap on a filled equip slot already took the item off")

	# The second tap on the SAME slot: the router's unequip path.
	inventory._on_equip_slot_pressed("armor")
	if state.equip().get("armor") != null:
		_fail("the second tap on the same equip slot did not unequip it")


## An empty slot has nothing to show: the tap must not open an empty overlay.
func _test_empty_slot_opens_nothing() -> void:
	var modal = _main._screens["character"]
	_main.open_modal("inventory")
	var inventory = modal._panes["inventory"].get_child(0).get_child(0)
	_main.state.equip()["boots"] = null
	inventory._on_equip_slot_pressed("boots")
	if inventory._item_overlay.visible:
		_fail("tapping an EMPTY equip slot opened the item-info overlay")
