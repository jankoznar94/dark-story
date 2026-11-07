extends SceneTree
## tools/test_zone_persistence.gd — the WIRING of zone persistence, through `main.gd` itself.
##
## `test_zone_memory` proves the model (snapshot → restore). This file proves the ROUTE: that the
## waypoint button freezes the zone, that entering the zone again puts it back, and that death
## throws the act's world away. The model passing while a button is wired to nothing is exactly
## the shape of defect this project has shipped before ("it looks right in a screenshot").
##
## Run:  godot --headless --path . --script res://tools/test_zone_persistence.gd
## Pass: prints ZONE_PERSISTENCE_ALL_PASS=true and exits 0.

const Main := preload("res://scripts/main.gd")
const ZoneMemory := preload("res://scripts/combat/zone_memory.gd")

var _main: Node = null
var _started := false
var _failures: Array[String] = []


func _initialize() -> void:
	_main = Main.new()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		if _main.state == null or _main._screens.get("survivor", null) == null:
			return false
		_started = true
		_run()
		quit(0 if _failures.is_empty() else 1)
		return true
	return false


func _fail(msg: String) -> void:
	_failures.append(msg)


## A known portal state for every case: no belt scroll, no stored return, no scroll in the bag.
## The bag entries are stripped by ID, because a leftover stack is exactly what made the button
## case pass standalone and fail in a batch.
func _reset_portal_state() -> void:
	_main.state.data["townPortalCount"] = 0
	_main.state.data["townPortalReturn"] = null
	var inv: Array = _main.state.inventory()
	var kept: Array = []
	for entry in inv:
		var eid := str(entry.get("id", "")) if entry is Dictionary else str(entry)
		if eid != "townPortalScroll":
			kept.append(entry)
	inv.clear()
	for e in kept:
		inv.append(e)
	ZoneMemory.reset()


func _run() -> void:
	# Never touch the local save, and start from a known portal state: a scroll or a return left
	# by an earlier process made one case pass alone and fail in the batch.
	_main.state.save_enabled = false
	_reset_portal_state()
	_test_waypoint_freezes_and_reentry_restores()
	_test_death_rolls_the_act_again()
	_test_the_portal_button_exists_only_with_a_scroll()
	_test_a_scroll_in_the_bag_counts_too()
	_test_portal_opens_where_he_stands_and_returns_him_there()
	for f in _failures:
		print("  FAIL: %s" % f)
	print("ZONE_PERSISTENCE_ALL_PASS=%s" % ("true" if _failures.is_empty() else "false"))


## Wakes a pack on the live run and wounds one of its monsters. Returns the id it wounded, or -1.


func _test_waypoint_freezes_and_reentry_restores() -> void:
	ZoneMemory.reset()
	_main._enter_survivor(0, 2)
	var first = _main._screens["survivor"].run
	if first == null:
		_fail("entering a zone built no run")
		return
	var pack: int = 2
	var ids: Array = []
	if pack < first.zones.size():
		first.player_pos = first.zones[pack]["centre"] as Vector2
		first._zone_tick()
		ids = (first.zones[pack]["ids"] as Array).duplicate()
	if ids.is_empty():
		_fail("no pack woke in zone 2 — the wiring case would prove nothing")
		return
	var left: int = first.monsters.size()
	first.monsters[0]["hp"] = 7
	var wounded := int(first.monsters[0]["id"])

	# The WAYPOINT stone: the only path that goes to town without a scroll.
	_main._on_zone_waypoint_used()
	if not ZoneMemory.has(0, 2):
		_fail("the waypoint did not freeze the zone — coming back would re-roll it")
	var portal: Variant = _main.state.data.get("townPortalReturn")
	if not (portal is Dictionary) or not bool((portal as Dictionary).get("zone", false)):
		_fail("the waypoint stored no ZONE return position (the town's portal card would be dead)")
	elif int((portal as Dictionary).get("zoneId", -1)) != 2:
		_fail("the waypoint stored zone %d, the player stood in 2"
			% int((portal as Dictionary).get("zoneId", -1)))

	# The town's portal card returns into the zone (not the old arena duel).
	_main._on_town_portal_return()
	var back = _main._screens["survivor"].run
	print("  waypoint -> town -> portal: %d monsters (left %d), pack awake=%s"
		% [back.monsters.size(), left, str(back.zones[pack]["active"] if pack < back.zones.size() else false)])
	if back.monsters.size() != left:
		_fail("re-entry restored %d monsters, %d were left fighting"
			% [back.monsters.size(), left])
	if pack < back.zones.size() and not bool(back.zones[pack]["active"]):
		_fail("the pack is not awake after the portal — it would spawn a second copy")
	var found := false
	for m in back.monsters:
		if int(m["id"]) == wounded:
			found = true
			if int(m["hp"]) != 7:
				_fail("the wounded monster came back at %d hp, it was left at 7" % int(m["hp"]))
	if not found:
		_fail("monster id %d was lost across the waypoint trip" % wounded)
	if back.player_pos.distance_to(back.start_point) > 1.0:
		_fail("the portal put the hero at the far end of the zone instead of its entrance")


func _test_death_rolls_the_act_again() -> void:
	_main._enter_survivor(0, 2)
	var run = _main._screens["survivor"].run
	if run.monsters.is_empty():
		_fail("the counterfactual run had no monsters — the restore is not what put them there")
	_main._end_survivor("dead")
	if ZoneMemory.has(0, 2):
		_fail("a death kept the zone snapshot — Jan's rule is that death RESETS it")
	_main._enter_survivor(0, 2)
	var fresh = _main._screens["survivor"].run
	print("  after death: %d monsters standing where %d died" % [fresh.monsters.size(), run.monsters.size()])
	if not fresh.monsters.is_empty():
		_fail("death left %d monsters from the previous run in the zone" % fresh.monsters.size())
	if int(fresh.hp) != int(fresh.max_hp):
		_fail("a fresh zone after death did not start the hero at full life")


## The button that USES the scroll lives in the zone's own HUD, and it may only exist while a
## scroll is carried — a permanently drawn control that does nothing is the "dead road button"
## this project already shipped once. Its rectangle also must not sit on any other plate.
## ⚠️  Nov 2026: Jan moved EVERY control into the top bar as an icon, so this used to assert the
## opposite (`position.y >= TOP_BAR`) and became the one CI step that failed the icon-bar change.
## The rule now is the same as the rest of the row: inside the bar, clear of its neighbours.
func _test_the_portal_button_exists_only_with_a_scroll() -> void:
	_main.state.data["townPortalCount"] = 0
	_main._enter_survivor(0, 1)
	var screen = _main._screens["survivor"]
	if screen._has_portal_scroll():
		_fail("the zone thinks it carries a scroll with a count of 0")
	var r: Rect2 = screen._portal_rect
	if r.size.x < 1.0:
		_fail("the portal button has no rect")
	for other in [screen._exit_rect, screen._bind_rect, screen._map_rect, screen._hero_rect]:
		if r.intersects(other):
			_fail("the portal button overlaps another top-bar plate: %s vs %s" % [str(r), str(other)])
	if r.end.y > screen.TOP_BAR or r.position.y < 0.0:
		_fail("the portal button must sit inside the top bar: %s" % str(r))

	# With no scroll the press must do NOTHING — neither open a portal nor store a return.
	var before: String = JSON.stringify(_main.state.data.get("townPortalReturn"))
	screen.portal_requested.emit()
	if JSON.stringify(_main.state.data.get("townPortalReturn")) != before:
		_fail("using a portal with no scroll stored a return position")

	# With a scroll the button must exist and its press must ask for the portal.
	_main.state.data["townPortalCount"] = 1
	if not screen._has_portal_scroll():
		_fail("the zone does not offer the portal button while a scroll is carried")
	var fired := [0]
	screen.portal_requested.connect(func(): fired[0] += 1)
	screen.portal_requested.emit()
	if fired[0] != 1:
		_fail("the portal button's signal is not connected to anything")


## Jan reported the button missing "ani když mám scrolly" while the counter was 0: a scroll that
## DROPPED lives in the bag as an item, and the first version of the button read the belt counter
## only. Both forms must count, and using one must spend exactly one.
func _test_a_scroll_in_the_bag_counts_too() -> void:
	_main.state.data["townPortalCount"] = 0
	var inv: Array = _main.state.inventory()
	var kept: Array = []
	for entry in inv:
		var eid := str(entry.get("id", "")) if entry is Dictionary else str(entry)
		if eid != "townPortalScroll":
			kept.append(entry)
	inv.clear()
	for e in kept:
		inv.append(e)
	_main.state.add_item("townPortalScroll", _main.data.item("townPortalScroll"), 2)

	_main._enter_survivor(0, 5)
	var screen = _main._screens["survivor"]
	if not screen._has_portal_scroll():
		_fail("a scroll in the BAG did not make the portal button available")
	screen.run.player_pos = screen.run.nearest_floor_point(screen.run.start_point
		+ Vector2(40.0, 0.0))
	_main._on_zone_portal_used()
	if int(_main.state.data.get("townPortalCount", 0)) != 0:
		_fail("spending a BAG scroll invented a belt counter")
	var left := 0
	for entry in _main.state.inventory():
		var eid := str(entry.get("id", "")) if entry is Dictionary else str(entry)
		if eid == "townPortalScroll":
			left += int(entry.get("count", 1)) if entry is Dictionary else 1
	print("  bag scrolls left after one trip: %d (started with 2)" % left)
	if left != 1:
		_fail("the trip consumed %d of 2 bag scrolls, one was expected" % (2 - left))


## Jan: "na místě, kde hráč stojí, se při použití vytvoří portál, hráč se přesune do města a po
## návratu z města pomocí portálu to hráče musí vrátit na stejnou pozici kde stál a do stejného
## stavu monster a lokace."
func _test_portal_opens_where_he_stands_and_returns_him_there() -> void:
	ZoneMemory.reset()
	_main.state.data["townPortalCount"] = 2
	_main.state.data["townPortalReturn"] = null
	_main._enter_survivor(0, 3)
	var screen = _main._screens["survivor"]
	var run = screen.run
	# A pack awake and one monster wounded, so "the same state" is something a check can SEE.
	var pack: int = 1
	run.player_pos = run.zones[pack]["centre"] as Vector2
	run._zone_tick()
	if run.monsters.is_empty():
		_fail("no pack woke before the portal trip")
		return
	run.monsters[0]["hp"] = 4
	var wounded := int(run.monsters[0]["id"])
	var left: int = run.monsters.size()
	# Where he STANDS when he uses the scroll: not the entrance, and on real floor.
	var spot: Vector2 = run.nearest_floor_point(run.zones[pack]["centre"] as Vector2
		+ Vector2(46.0, 18.0))
	run.player_pos = spot

	_main._on_zone_portal_used()
	if int(_main.state.data.get("townPortalCount", 0)) != 1:
		_fail("the trip did not spend one of two scrolls")
	var portal: Variant = _main.state.data.get("townPortalReturn")
	if not (portal is Dictionary):
		_fail("using the scroll stored no return position")
		return
	var p: Dictionary = portal
	var stored: Variant = p.get("pos")
	if not (stored is Array) or (stored as Array).size() != 2:
		_fail("the return position was not stored as a JSON-safe pair")
		return
	var saved := Vector2(float(stored[0]), float(stored[1]))
	if saved.distance_to(spot) > 1.0:
		_fail("the portal opened %.0f px from where the hero stood" % saved.distance_to(spot))
	if not ZoneMemory.has(0, 3):
		_fail("the portal trip did not freeze the zone")
	if not run.portal_open:
		_fail("no portal was opened in the world")

	# The town's own button. Everything must come back: the spot, the monsters, the wound.
	_main._on_town_portal_return()
	var back = _main._screens["survivor"].run
	print("  portal: back at %.0f px from the spot, %d/%d monsters, pack awake=%s, mouth open=%s"
		% [back.player_pos.distance_to(spot), back.monsters.size(), left,
			str(back.zones[pack]["active"] if pack < back.zones.size() else false),
			str(back.portal_open)])
	if back.player_pos.distance_to(spot) > 1.0:
		_fail("the town portal returned the hero %.0f px from where he left"
			% back.player_pos.distance_to(spot))
	if back.monsters.size() != left:
		_fail("the portal restored %d of %d monsters" % [back.monsters.size(), left])
	var found := false
	for m in back.monsters:
		if int(m["id"]) == wounded:
			found = true
			if int(m["hp"]) != 4:
				_fail("the wounded monster came back at %d hp, he left it at 4" % int(m["hp"]))
	if not found:
		_fail("the wounded monster was lost across the portal")
	if not back.portal_open:
		_fail("the hero did not come back out of a portal — nothing is drawn where he stands")
	if _main.state.data.get("townPortalReturn") != null:
		_fail("the return position survived the return — the town card would offer it again")
	# The old arena path must still own a return that a ZONE did not store.
	_main.state.data["townPortalReturn"] = {"actId": 0, "zoneId": 1, "areaFight": 2}
	_main._on_town_portal_return()
	if not (_main._screens["arena"].battle != null):
		_fail("a return stored by the old path did not reach the arena")
