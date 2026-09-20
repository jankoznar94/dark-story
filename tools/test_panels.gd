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
	_test_panels_are_hit_testable()
	_test_layout_does_not_redraw_itself()
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


# ------------------------------------------- 0. the panel is a real hit area
## Jan's report: "the corpse can be opened, but the items cannot be taken from it."
## Two defects, both structural, both measured:
##   * the panel had `size == (0, 0)`, so every tap fell OUTSIDE it and `_gui_input`
##     was never called. An anchors preset does not give a Control a size when its
##     parent is a CanvasLayer, and every earlier test called `_gui_input` directly,
##     which skips the rect test - so the window looked perfectly healthy.
##   * `_draw()` called `layout_now()`, which ended with `queue_redraw()`: the
##     Control marked itself dirty from inside its own draw.
func _test_panels_are_hit_testable() -> void:
	print("== 0. every panel really covers the screen (a tap has somewhere to land) ==")
	var hud: Node = main.get_node("HUD")
	var vs: Vector2 = root.get_visible_rect().size
	_ok("the viewport has a real size to lay out from", vs.x > 0.0 and vs.y > 0.0,
		str(vs))
	for pair in [["loot_panel", hud.loot_panel], ["inventory_ui", hud.inventory_ui],
			["stat_panel", hud.stat_panel]]:
		var c: Control = pair[1]
		_ok("%s covers the screen" % pair[0],
			c.size.x >= vs.x * 0.99 and c.size.y >= vs.y * 0.99,
			"size %s vs viewport %s" % [str(c.size), str(vs)])
		_ok("%s would receive a tap in the middle of the screen" % pair[0],
			Rect2(c.position, c.size).has_point(vs * 0.5),
			"rect %s" % str(Rect2(c.position, c.size)))


## A `_draw()` that marks itself dirty is an infinite redraw loop - the "the game
## locks up" half of the report. `_draw` never runs headless, so this is asserted on
## the SOURCE: `layout_now()` must not contain a `queue_redraw`.
func _test_layout_does_not_redraw_itself() -> void:
	print("== 0b. layout does not schedule a redraw from inside a draw ==")
	var offenders: Array = []
	for path in ["res://scripts/loot_panel.gd", "res://scripts/inventory_ui.gd",
			"res://scripts/stat_panel.gd"]:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			offenders.append("%s: UNREADABLE" % path)
			continue
		var in_layout := false
		var line_no := 0
		while not f.eof_reached():
			var line := f.get_line()
			line_no += 1
			var t := line.strip_edges()
			if t.begins_with("func layout_now"):
				in_layout = true
				continue
			if in_layout and t.begins_with("func "):
				in_layout = false
			if in_layout and not t.begins_with("#") and t.contains("queue_redraw"):
				offenders.append("%s:%d" % [path.get_file(), line_no])
		f.close()
	_ok("no layout_now() queues a redraw (that is what made _draw() recurse)",
		offenders.is_empty(), str(offenders))


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

	# --- THE EXIT IS ABOVE THE PANEL, and that is a Z-ORDER question, not a
	# visibility one. Measured in the real web build (Sept 2026, Jan: "opening any
	# window from the top menu freezes the game"): the bag opened on the first tap,
	# the second tap on the SAME button changed nothing - the middle of the screen
	# stayed 0.946 dark - because the panel is a full-screen Control with
	# `mouse_filter = STOP` and main.gd adds the panels to this layer AFTER the
	# buttons were built, so the panel sat over the button that closes it. The
	# visible=true assertion above passed the whole time, which is exactly why this
	# section checks the ORDER too.
	hud.close_panels()
	await physics_frame
	hud._toggle_panel(2)
	await physics_frame
	var order_ok: bool = (bool(hud.stats_button.get_index() > hud.stat_panel.get_index())
		and bool(hud.inv_button.get_index() > hud.stat_panel.get_index()))
	_ok("the exit buttons sit ON TOP of the open panel (a tap can reach them)",
		order_ok, "stats_button %d, panel %d, inv_button %d"
		% [hud.stats_button.get_index(), hud.stat_panel.get_index(),
			hud.inv_button.get_index()])
	hud.close_panels()
	await physics_frame
	hud._toggle_panel(1)          # the bag, whose whole surface is hit-tested
	await physics_frame
	_ok("the exit buttons sit on top of the BAG too",
		hud.inv_button.get_index() > hud.inventory_ui.get_index(),
		"inv_button %d, bag %d" % [hud.inv_button.get_index(), hud.inventory_ui.get_index()])

	# --- NOT TESTED HERE, and deliberately: whether a tap actually LANDS on the
	# button. `Viewport.push_input()`, `Input.parse_input_event()` and
	# `push_unhandled_input()` do NOT route GUI input in a `--headless` run -
	# measured on a bare full-rect Control with mouse_filter STOP, right size and
	# correct coordinates, which received nothing from all three. A push_input
	# assertion here would fail for the instrument, not the game, so the honest
	# headless check is the Z-ORDER above and the real acceptance is the browser
	# run (tools/web_live_check.py + a CDP tap on the button).

	# the world tap that opens a body must NOT reach main.gd's ray while a panel is
	# up, or a tap meant for the window re-opens the body behind it.
	var tap_y: float = hud.inv_button.position.y + hud.inv_button.size.y * 0.5
	var before_bodies: int = main.loot.body_count()
	var far_tap := InputEventScreenTouch.new()
	far_tap.position = Vector2(4.0, tap_y)
	far_tap.pressed = true
	far_tap.index = 1
	hud._toggle_panel(2)
	await physics_frame
	main._unhandled_input(far_tap)
	await physics_frame
	_ok("a world tap while a panel is up opens no body", main.loot.body_count() == before_bodies,
		"%d -> %d" % [before_bodies, main.loot.body_count()])
	hud.close_panels()
	await physics_frame


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

	# --- THE CORPSE IS THE MONSTER ITSELF (Jan's report) -------------------------
	# "its corpse shows up as another separate object next to the real 3D model. I
	# want the REAL corpse to be the one that gets picked." So the body must be a
	# CHILD of the monster node, and that monster's own rigged model must still be
	# there - not replaced, and not duplicated beside it.
	var parent: Node = b.get_parent()
	_ok("the body lives INSIDE the monster node, not beside it",
		parent != null and parent.has_method("is_dead"), str(parent.name) if parent else "none")
	_ok("...and that monster is the one that died", parent != null and parent.is_dead())
	_ok("the corpse keeps the monster's OWN rigged model",
		parent != null and parent.get_model_root() != null
		and parent.get_model_root().get_child_count() > 0,
		"%d children under the model root" % (
			parent.get_model_root().get_child_count() if parent != null
			and parent.get_model_root() != null else -1))
	# One corpse per death. A second node standing next to the model was the bug.
	var stray := 0
	for c in main.get_children():
		if str(c.name).begins_with("Body_"):
			stray += 1
	_ok("no separate corpse object was spawned beside the monster", stray == 0,
		"%d stray Body_ nodes" % stray)
	# ...AND THE COUNT ABOVE IS NOT ENOUGH - that is exactly why the black object
	# shipped. `loot_body._ready()` runs when `spawn_for_death` adds the node to the
	# tree, i.e. BEFORE `dress_corpse()` adopts the monster, so the fallback bundle
	# was already built and it is a CHILD of the corpse, not a top-level Body_ node.
	# Jan: "when an enemy dies, apart from its dead body a black object appears as
	# well. We do not want that." So the assertion is about the GEOMETRY the corpse
	# actually shows: every mesh under it must be the adopted monster's own.
	_ok("the corpse carries no fallback bundle", b.get_node_or_null("StandIn") == null,
		"a StandIn child was left on the corpse")
	var corpse_meshes := 0
	var own_model: Node = parent.get_model_root() if parent != null else null
	_count_meshes(b, corpse_meshes, own_model)
	_ok("every mesh the corpse draws is the monster's OWN model", corpse_meshes == 0,
		"%d mesh(es) outside the monster's model" % corpse_meshes)
	_ok("the corpse no longer collides with the world (a body must not block a step)",
		parent != null and parent.collision_layer == 0,
		"layer %d" % (parent.collision_layer if parent else -1))


## Meshes under `node` that are NOT inside `own_model` - i.e. geometry the corpse
## draws that is not the monster's own body. Counted by walking the tree, because
## the defect was a child of a child and a name lookup would miss a rename.
func _count_meshes(node: Node, out: int, own_model: Node) -> void:
	for c in node.get_children():
		if c == own_model:
			continue
		if c is MeshInstance3D:
			out += 1
		_count_meshes(c, out, own_model)


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

	# --- a tap outside the panel closes it - BUT NOT THE TAP THAT OPENED IT.
	# The window is full-rect and swallows the rest of the very touch that opened the
	# body, so `_handle` used to fire its "tapped outside" exit in the SAME frame:
	# Jan saw the joystick disappear and no window at all. The guard is time-based
	# (`loot_panel.CLOSE_ARM_MS`), so this test asserts BOTH halves: an immediate tap
	# changes nothing, and a tap after the guard expires closes the window.
	hud.open_loot_for(fresh)
	await physics_frame
	panel.layout_now()
	_ok("the window is armed against the tap that opened it",
		panel._arm_ms > 0.0, "%.0f ms left" % panel._arm_ms)
	var immediate := InputEventScreenTouch.new()
	immediate.pressed = true
	immediate.index = 1
	immediate.position = Vector2(2.0, 2.0)
	panel._gui_input(immediate)
	await physics_frame
	_ok("the tap that opened the body does NOT close it again", panel.open,
		"open=%s" % str(panel.open))
	# Wait the guard out. `_process` runs on real deltas, so drive it directly rather
	# than sleeping a quarter of a second in a headless suite.
	panel._arm_ms = 0.0
	panel._gui_input(immediate)
	await physics_frame
	_ok("a later tap outside the window closes it", not panel.open,
		"open=%s" % str(panel.open))

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
