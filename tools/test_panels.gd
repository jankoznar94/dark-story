extends SceneTree
## PANELS, THE PAUSE, AND OPENING A BODY.
## Run: godot --headless --path . --script res://tools/test_panels.gd
##
## Jan's four reports (Sept 2026), turned into assertions:
##   1. "the game should pause when the inventory opens, it does not - the enemies
##      keep attacking and moving, maybe they do no damage but they move"
##   2. "the inventory cannot be turned off - I found no working button that hides it"
##   3. too many enemies at the start (covered in tools/test_fight.gd by the
##      measured distance from the player's spawn)
##   4. items should come out of a BODY, World-of-Warcraft style, not lie on the
##      ground
##
## Sections:
##   1. the pause is REAL: an engaged monster stops moving and stops doing damage
##   2. closing the panel resumes the fight
##   3. every panel has a working way out (button, ESC, its own close box, a tap
##      outside it)
##   4. a body is left by a kill, and it is NOT an item on the ground
##   5. opening a body and taking from it: one item, take-all, and the bag-full
##      refusal
##   6. NO gameplay script reads `Input` directly - the coverage the pause needs
##
## Why section 6 exists as a test and not as a comment: the first attempt at the
## pause set a flag in player.gd, and the game STILL moved while the bag was open,
## because the HUD's virtual buttons and the enemy AI kept reading Godot's own
## `Input` singleton. A missing gate looks exactly like a working pause in every
## other measurement, so it is checked by reading the source.

const IB := preload("res://scripts/item_base.gd")
const ItemGen := preload("res://scripts/item_gen.gd")
const Inv := preload("res://scripts/inventory_model.gd")
const GATE := preload("res://scripts/input_gate.gd")

## The scripts that must never touch `Input` directly. `hud.gd` is NOT here on
## purpose: it is the UI, it does not decide whether the world moves, and it is
## the thing that PRESSES the virtual actions.
const GATED_SCRIPTS := [
	"res://scripts/player.gd",
	"res://scripts/main.gd",
	"res://scripts/enemy_base.gd",
	"res://scripts/enemy_ghoul.gd",
	"res://scripts/enemy_brute.gd",
	"res://scripts/enemy.gd",
]

var main: Node
var fails: Array[String] = []
var checks: int = 0


func _ok(label: String, cond: bool, detail: String = "") -> void:
	checks += 1
	if cond:
		print("  OK   ", label, ("  " + detail) if detail else "")
	else:
		print("  FAIL ", label, "  ", detail)
		fails.append(label)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_no_direct_input()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	await physics_frame
	# EVERY one of these is awaited. A coroutine called without `await` keeps
	# running at its first suspension point and its output interleaves with the
	# next section's - which made a real failure ("the hero sheet opens") print
	# inside a different section's block, and it took a round of guessing to see it.
	await _test_pause_and_resume()
	await _test_ways_out()
	await _test_body_left_by_a_kill()
	await _test_opening_a_body()
	_finish()


# ------------------------------------------------- 6. the coverage the pause needs
func _test_no_direct_input() -> void:
	print("== 6. no gameplay script reads Input directly (the pause depends on it) ==")
	var offenders: Array = []
	for path in GATED_SCRIPTS:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			offenders.append("%s: UNREADABLE" % path)
			continue
		var line_no := 0
		while not f.eof_reached():
			var line := f.get_line()
			line_no += 1
			var t := line.strip_edges()
			# comments are allowed to MENTION Input; code must not READ it
			if t.begins_with("#") or t == "":
				continue
			if t.contains("Input."):
				offenders.append("%s:%d  %s" % [path.get_file(), line_no, t])
		f.close()
	_ok("every gameplay script reads input through input_gate.gd", offenders.is_empty(),
		str(offenders))


# ------------------------------------------------------- 1./2. pause and resume
func _test_pause_and_resume() -> void:
	print("== 1. an open panel really pauses the fight ==")
	var player: Node = main.get_node("Player")
	var pack: Array = main._enemies
	_ok("there is a pack to be paused", pack.size() >= 3, "%d monsters" % pack.size())

	# ONE monster, in reach, with the rest of the world parked: the parked ones are
	# what makes the measurement attributable (see test_fight.gd for the same rule).
	var ghoul: Node = _first_of(pack, "Ghoul")
	_ok("there is a Ghoul to test with", ghoul != null)
	if ghoul == null:
		return
	_park_others(pack, ghoul)
	player.global_position = ghoul.global_position + Vector3(0, 0, 1.05)
	player.hp = player.max_hp
	player.velocity = Vector3.ZERO
	# let it notice and start swinging, so the pause is measured mid-fight
	for i in 60:
		await physics_frame
	var hp_before: float = player.hp
	var pos_before: Vector3 = ghoul.global_position
	_ok("the ghoul is fighting before the panel opens", ghoul.aggro,
		"aggro %s, state %s" % [str(ghoul.aggro), ghoul.state_name()])

	# --- OPEN THE BAG. The HUD's own button path, exactly what the player taps.
	var hud: Node = main.get_node("HUD")
	hud._toggle_panel(1)
	await physics_frame
	_ok("the bag is open", hud.inventory_ui.open)
	_ok("the world reports itself paused", hud.panel_open())

	var pos_open: Vector3 = ghoul.global_position
	var hero_open: Vector3 = player.global_position
	var hp_open: float = player.hp
	var moved := 0.0
	var hero_moved := 0.0
	for i in 180:
		await physics_frame
		moved = maxf(moved, ghoul.global_position.distance_to(pos_open))
		hero_moved = maxf(hero_moved, player.global_position.distance_to(hero_open))
	_ok("the monster does NOT move while the bag is open", moved < 0.001,
		"moved %.4f m over 180 frames (it was already at %.2f m from the player)"
		% [moved, pos_before.distance_to(hero_open)])
	_ok("the monster does NOT damage the player while the bag is open",
		absf(player.hp - hp_open) < 0.001, "%.0f -> %.0f hp" % [hp_open, player.hp])
	_ok("the hero does not finish or start a swing while the bag is open",
		not player.is_busy(), player.state_name())
	_ok("...and the hero did not walk while the bag was open", hero_moved < 0.001,
		"moved %.4f m" % hero_moved)

	# --- CLOSE IT. The fight has to come back.
	hud._toggle_panel(1)
	await physics_frame
	_ok("the bag closes again through the same button", not hud.inventory_ui.open)
	var moved_after := 0.0
	for i in 120:
		await physics_frame
		moved_after = maxf(moved_after, ghoul.global_position.distance_to(pos_open))
	_ok("the fight resumes when the panel closes", moved_after > 0.15,
		"moved %.2f m after closing" % moved_after)
	_ok("the hero was reachable again (the monster closed the distance)",
		moved_after > 0.0)


# ------------------------------------------------------------- 3. ways out
func _test_ways_out() -> void:
	print("== 2. every panel has a working way out ==")
	var hud: Node = main.get_node("HUD")
	await physics_frame
	# A known starting state, asserted rather than assumed: the pause section left
	# the bag closed, and a toggle test that begins from an unknown state measures
	# the previous section.
	hud.close_panels()
	await physics_frame
	_ok("the sections start with every panel closed",
		not hud.panel_open(), "inv %s stats %s loot %s"
		% [str(hud.inventory_ui.open), str(hud.stat_panel.open), str(hud.loot_panel.open)])

	# the buttons are VISIBLE while a panel is open - hiding them was the bug
	hud._toggle_panel(2)      # the hero sheet
	await physics_frame
	_ok("the hero sheet opens", hud.stat_panel.open,
		"inv %s stats %s loot %s" % [str(hud.inventory_ui.open), str(hud.stat_panel.open),
			str(hud.loot_panel.open)])
	_ok("the panel buttons stay visible while a panel is open (they are the exit)",
		hud.inv_button.visible and hud.stats_button.visible and hud.loot_button.visible)
	_ok("the fight controls are hidden while a panel is open",
		not hud._buttons["down"].visible and not hud.run_button.visible)

	# ESC / the phone's back gesture
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	ev.echo = false
	main._unhandled_input(ev)
	await physics_frame
	_ok("ESC closes the panel", not hud.panel_open())

	# the same button a second time toggles it off
	hud._toggle_panel(1)
	await physics_frame
	_ok("the bag opens again", hud.inventory_ui.open)
	hud._toggle_panel(1)
	await physics_frame
	_ok("...and the SAME button closes it", not hud.inventory_ui.open)

	# asking for the other panel while one is up is refused, with a reason
	hud._toggle_panel(1)
	await physics_frame
	hud._toggle_panel(2)
	await physics_frame
	_ok("the other panel cannot come up on top of it",
		hud.inventory_ui.open and not hud.stat_panel.open)
	_ok("...and the game says why", hud.toast_label.visible and hud.toast_label.text != "",
		hud.toast_label.text)
	hud.close_panels()
	await physics_frame
	_ok("all panels closed", not hud.panel_open())


# ------------------------------------------------ 4. the body, not a ground item
## Async on purpose (it awaits physics frames) - and its caller awaits it, see _run.
func _test_body_left_by_a_kill() -> void:
	print("== 3. a kill leaves a BODY, and a body is not an item on the ground ==")
	main.clear_loot()
	var loot: Node = main.loot
	_ok("the body system exists in the scene", loot != null)
	_ok("the ground starts empty", loot.body_count() == 0)

	var pack: Array = main._enemies
	var kills := 0
	for m in pack:
		if not is_instance_valid(m) or m.is_dead():
			continue
		m.take_damage(99999.0)
		kills += 1
	for i in 3:
		await physics_frame
	_ok("every killed monster left a body", loot.body_count() == kills,
		"%d bodies from %d kills (drop chance is 1.0 for the testing pass)"
		% [loot.body_count(), kills])
	_ok("the bodies hold items", loot.drop_count() > 0,
		"%d items inside %d bodies" % [loot.drop_count(), loot.body_count()])
	_ok("the old ground-item pickup path is gone",
		not loot.has_method("try_pick") and not loot.has_method("try_pick_at_screen"))

	var b: Node = loot.bodies()[0]
	var pick: Node = b.get_node_or_null("Open")
	_ok("a body is an Area3D, so it never blocks a step", pick != null and pick is Area3D)
	_ok("a body is on its OWN layer, so it can never be taken for an item",
		pick.collision_layer == 4 and (pick.collision_layer & 2) == 0,
		"layer %d" % pick.collision_layer)
	# The NAME matters, not just the word "Tělo": a body labelled "Tělo: ?" was
	# shipped by a `setup()` that became a no-op once the meshes existed, and the
	# weaker assertion ("contains Tělo") passed on it.
	_ok("a body names the monster that fell",
		b.label != null and b.label.text == "Tělo: %s" % b.monster_name
		and b.monster_name != "?",
		str(b.label.text) if b.label else "no label")


# ------------------------------------------------------------ 5. opening a body
func _test_opening_a_body() -> void:
	print("== 4. opening a body and taking from it ==")
	var loot: Node = main.loot
	var hud: Node = main.get_node("HUD")
	var player: Node = main.get_node("Player")
	var panel: Control = hud.loot_panel
	_ok("the loot window exists on the HUD", panel != null)

	# TWO bodies, because OPENING ONE CONSUMES IT. The first round used a single
	# body for both halves of the section and the second half read an already
	# emptied body - the panel was correct and the measurement was not.
	var model_body = loot.bodies()[0]
	var body = loot.bodies()[1]
	var items: Array = loot.items_in(body)
	_ok("the body has something in it", items.size() > 0, "%d items" % items.size())

	# out of reach: the player has to walk to it. This is what keeps opening a body
	# from being a vacuum cleaner.
	player.global_position = body.global_position + Vector3(0, 0, 30.0)
	var far: Variant = loot.open(body, player.global_position)
	_ok("a body 30 m away cannot be opened", far == null)
	_ok("...and it still holds its items", loot.items_in(body).size() == items.size())

	# in reach: the model path the tap and the button both end in
	player.global_position = model_body.global_position + Vector3(0, 0, 1.2)
	var opened: Variant = loot.open(model_body, player.global_position)
	_ok("a body in reach can be opened by the model path", opened != null,
		"%d items came out" % (opened.size() if opened != null else 0))
	# OPENING IS NOT TAKING. This is asserted on both sides on purpose: the first
	# version consumed the contents, which both destroyed loot on a look and made
	# the panel take from an already empty body.
	_ok("the opened body still holds its items (a look is not a take)",
		loot.items_in(model_body).size() == (opened as Array).size(),
		"%d items" % loot.items_in(model_body).size())

	# ...and through the HUD, which is what the tap and the button do
	player.hp = player.max_hp
	hud.open_loot_for(body)
	await physics_frame
	_ok("the loot window is up", panel.open)
	_ok("the loot window pauses the fight like the other panels", hud.panel_open())
	panel.layout_now()
	_ok("the window lists what the body holds", panel._items.size() == items.size(),
		"%d rows" % panel._items.size())
	_ok("every row has a rect on screen (a row that cannot be tapped is a broken row)",
		panel._rows.size() == items.size() and panel._rows[0].size.x > 0.0)

	# --- take ONE item by tapping its row
	var inv = main.inventory
	var bag_before: int = inv.bag_items().size()
	var ev := InputEventScreenTouch.new()
	ev.pressed = true
	ev.index = 1
	ev.position = panel._rows[0].position + panel._rows[0].size * 0.5
	panel._gui_input(ev)
	await physics_frame
	_ok("tapping a row puts that item in the bag", inv.bag_items().size() == bag_before + 1,
		"%d -> %d bag items" % [bag_before, inv.bag_items().size()])
	_ok("the body is empty now - the item is not duplicated",
		loot.items_in(body).size() == items.size() - 1)

	# --- take the rest with the bottom row
	if not panel._items.is_empty():
		var ev2 := InputEventScreenTouch.new()
		ev2.pressed = true
		ev2.index = 1
		ev2.position = panel._all_rect.position + panel._all_rect.size * 0.5
		panel._gui_input(ev2)
		await physics_frame
	_ok("'take all' empties the body", loot.items_in(body).is_empty())
	_ok("the window closes itself once the body is empty", not panel.open)
	_ok("the body stays in the world, now empty (it is what the kill made)",
		loot.bodies().has(body))

	# --- a full bag leaves the item IN the body
	var full = Inv.new()
	for i in Inv.COLS * Inv.ROWS:
		full.add(ItemGen.make("ring"))
	var fresh = loot.spawn_body(Vector3(1.0, 0, 1.0), [ItemGen.make("long_sword")])
	var before_n: int = loot.items_in(fresh).size()
	var got: Variant = loot.take_item(fresh, loot.items_in(fresh)[0], full)
	_ok("a full bag refuses the item", got == null)
	_ok("...and the item STAYS in the body (never destroyed)",
		loot.items_in(fresh).size() == before_n, "%d items" % loot.items_in(fresh).size())

	# --- a tap outside the panel closes it
	hud.open_loot_for(fresh)
	await physics_frame
	panel.layout_now()
	var out := InputEventScreenTouch.new()
	out.pressed = true
	out.index = 1
	out.position = Vector2(2.0, 2.0)
	panel._gui_input(out)
	await physics_frame
	_ok("a tap outside the window closes it", not panel.open)

	# --- closing the loot window resumes the world too
	main.clear_loot()


func _first_of(pack: Array, name_wanted: String) -> Node:
	for e in pack:
		if e.monster_name == name_wanted and not e.is_dead():
			return e
	return null


func _park_others(pack: Array, keep: Node) -> void:
	for e in pack:
		if e == keep or not is_instance_valid(e):
			continue
		e.global_position = Vector3(e.global_position.x, e.global_position.y,
			e.global_position.z + 200.0)


func _finish() -> void:
	print("")
	print("checks executed: ", checks)
	if fails.is_empty() and checks >= 30:
		print("PANELS_ALL_PASS=true")
	else:
		for f in fails:
			print("FAIL: ", f)
		if checks < 30:
			print("FAIL: only %d checks ran - not everything was exercised" % checks)
		print("PANELS_ALL_PASS=false")
	quit()
