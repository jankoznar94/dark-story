extends Node3D
## Prototype scene wiring. Headless-safe: no rendering calls.
##
## The training ground now holds a FIGHT, not only posts: `_spawn_enemies()`
## places the test enemy and the wiring below is what makes the loop readable -
## the HUD shows both health bars and the debug line carries the per-swing result
## ("swing: HIT" / "punch: HIT").

@onready var player: CharacterBody3D = $Player
@onready var cam: Camera3D = $Camera
@onready var hud: CanvasLayer = $HUD

## The monster catalogue: one place that says how strong each kind is and which
## behaviour script drives it, so `_spawn_enemies()` below is a list of POSITIONS
## and nothing else.
const MONSTER_KIND := preload("res://scripts/monster_kind.gd")
const InvModel := preload("res://scripts/inventory_model.gd")
const HeroStats := preload("res://scripts/hero_stats.gd")
const ItemGen := preload("res://scripts/item_gen.gd")
## The ONE pause flag every gameplay script reads. Pushed once per physics frame,
## before anything acts on it - see scripts/input_gate.gd for why a per-script
## flag could not work.
const GATE := preload("res://scripts/input_gate.gd")
const TapGuard := preload("res://scripts/tap_guard.gd")

var _posts: Array[Node] = []
var _enemies: Array[Node] = []
var _hits: Array = []
var _level_nodes: Array = []
var _run_action: bool = false
## The loot system: every dropped item lives under this node, and it owns the
## pickup rule. Created in code like the monsters, so it has no scene file to
## keep in sync.
var loot: Node3D
## The hero's gear and the numbers derived from it. player.gd reads `stats` for
## its maximum life and its damage, so the item system never leaks into combat.
var inventory
var stats
## The name of the last thing picked up, only used to make the toast readable.
var _last_pick_toast: String = ""
## The tap that was consumed by a real UI control this frame. An opened-body panel
## takes its taps in `_gui_input`, which is delivered BEFORE `_unhandled_input`, so
## a tap on the panel can never also reach the world. Nothing else should see the
## same tap - the flag is what keeps a tap that closed a panel from immediately
## opening a body behind it.
var _ui_consumed: bool = false
## The monster the enemy health bar is currently showing: the last one the player
## actually hit, or the nearest engaged one. A single bar for a pack of six is
## otherwise a lie - it would show whichever spawn happened to be first in the
## array, which is unrelated to what the player is fighting.
var _focus: Node = null
## ONE TAP, ONE ACTION for the world tap that opens a body - the synthesised mouse
## event and the real touch must not both run the ray. See scripts/tap_guard.gd.
var _world_tap_guard = TapGuard.new()


func _ready() -> void:
	_setup_world()
	_build_level()
	_spawn_posts()
	_setup_loot_and_inventory()
	_spawn_enemies()
	player.attack_landed.connect(_on_landed)
	player.damaged.connect(_on_player_damaged)
	player.died.connect(_on_player_died)
	# The RUN input exists so the keyboard and a gamepad have a run button too;
	# on touch the HUD latches it (see hud.gd). Both feed the same player flag.
	if not InputMap.has_action("run"):
		InputMap.add_action("run")


## The hero's gear, the stat sheet derived from it, and the loot system. All three
## are built in code and wired to each other HERE, so there is exactly one place
## that knows how an item becomes a number on the hero.
func _setup_loot_and_inventory() -> void:
	stats = HeroStats.new(1)
	inventory = InvModel.new()
	# The starting weapon is a real item rolling the same 16-25 the game shipped
	# with, so the balance numbers in monster_kind.gd keep their meaning.
	for it in ItemGen.starter_loadout():
		var res: Dictionary = inventory.equip(it)
		if not bool(res.get("ok", false)):
			push_warning("main: could not equip the starter weapon: %s" % res.get("reason", ""))
	stats.recompute(inventory.equipped_items())
	player.set_loadout(stats)
	player.hp = stats.max_hp()

	loot = load("res://scripts/loot_manager.gd").new()
	loot.name = "Loot"
	add_child(loot)
	loot.bag_full_of.connect(_on_bag_full)
	# A tap (or a button) that lands on a body opens the window for it. The signal
	# carries the body, so main.gd never has to remember which one was hit.
	loot.body_opened.connect(_on_body_opened)

	# The two panels live on the HUD (a CanvasLayer), built in code like the rest
	# of it. They are what the player sees; the MODEL above is what the rules are.
	var inv_ui: Control = load("res://scripts/inventory_ui.gd").new()
	inv_ui.name = "InventoryUI"
	hud.add_child(inv_ui)
	inv_ui.setup(inventory, stats)
	var sp: Control = load("res://scripts/stat_panel.gd").new()
	sp.name = "StatPanel"
	hud.add_child(sp)
	sp.setup(stats, inventory)
	hud.inventory_ui = inv_ui
	hud.stat_panel = sp

	# One signal from either panel: whatever changed, re-derive the hero's numbers
	# and let the sheet redraw. Nothing else is allowed to touch `stats`.
	inv_ui.item_used.connect(_on_loadout_changed)
	sp.item_used.connect(_on_loadout_changed)
	inv_ui.notify.connect(_on_notify)

	# The BODY window: what is inside the corpse the player just opened. It is a
	# HUD panel like the other two (so it pauses the fight through the same
	# `panel_open()` question) but its CONTENT is world state, which is why it is
	# wired here rather than built blind inside hud.gd.
	var lp: Control = load("res://scripts/loot_panel.gd").new()
	lp.name = "LootPanel"
	hud.add_child(lp)
	lp.setup(loot, inventory, stats)
	lp.item_taken.connect(_on_loot_taken)
	hud.loot_panel = lp
	# The HUD's third panel button opens the body within reach - that is a world
	# question (which body is closest to the player), so main.gd answers it.
	hud.loot_button.pressed.connect(_on_loot_button)
	print("[items] starter weapon: %s, life %.0f, damage %.0f-%.0f"
		% [inventory.main_hand().display_name() if inventory.main_hand() else "unarmed",
			stats.max_hp(), stats.damage_range().x, stats.damage_range().y])


func _on_loadout_changed(_item = null) -> void:
	stats.recompute(inventory.equipped_items())
	player.apply_stats()
	# Only the sheet needs a repaint: the inventory window already refreshes off
	# the model's `changed` signal, and a CanvasLayer has no queue_redraw of its own.
	if hud.stat_panel != null:
		hud.stat_panel.queue_redraw()


func _on_notify(text: String) -> void:
	if text != "":
		hud.toast(text)


func _on_bag_full(item) -> void:
	# The item STAYS on the ground - silently destroying it would be the worst bug
	# a loot game can have, so the game says why instead.
	hud.toast("Batoh je plný - %s zůstává na zemi." % item.display_name())


## A monster died: roll what it carried and leave a BODY holding it. This is the
## whole Diablo loop in one line - the rest is already data.
func _on_enemy_died(e: Node) -> void:
	if loot == null or not is_instance_valid(e):
		return
	var ilvl: int = int(e.level) + 3
	# THE MONSTER ITSELF becomes the corpse: same rig, same tint, same death pose the
	# player just watched. Nothing new is spawned next to it.
	var n: int = loot.spawn_for_death(e, ilvl)
	if n > 0:
		print("[loot] %s is now a corpse holding %d item(s)" % [e.name, n])


## The HUD's "Tělo" button: open the nearest body within reach, if there is one.
## A button that silently does nothing is a broken button, so a miss says so.
func _on_loot_button() -> void:
	if hud == null or hud.loot_panel == null:
		return
	if hud.loot_panel.open:
		hud.loot_panel.set_open(false)
		return
	var near: Node = nearest_body()
	if near == null:
		hud.toast("Žádné tělo na dosah (%.0f m)." % loot.OPEN_RANGE)
		return
	_open_body(near)


func nearest_body() -> Node:
	if loot == null:
		return null
	var best: Node = null
	var best_d: float = loot.OPEN_RANGE
	for b in loot.bodies():
		if not is_instance_valid(b):
			continue
		var d: float = b.global_position.distance_to(player.global_position)
		if d <= best_d:
			best_d = d
			best = b
	return best


func _on_body_opened(body, _items) -> void:
	_open_body(body)


func _open_body(body) -> void:
	if hud == null or hud.loot_panel == null or body == null:
		return
	# Panels are mutually exclusive and all of them pause the fight, so opening
	# the body closes whatever was up - through the HUD, so the state stays one
	# question with one answer.
	hud.open_loot_for(body)


func _on_loot_taken(item) -> void:
	# A taken item may change the hero's numbers the moment it is equipped, and the
	# bag window has to repaint - both are already handled by the model's signal.
	hud.toast("Vzato: %s" % item.display_name())
	print("[loot] took %s" % item.display_name())


func _build_level() -> void:
	## The level is DATA (levels/training_ground.json), not hand-placed nodes.
	## Jan is the tester and has no time to click a scene together, so a layout
	## change is a JSON edit and a new area is a new file. See scripts/level_builder.gd.
	var data: Dictionary = load("res://scripts/level_builder.gd").load_level()
	if data.is_empty():
		push_warning("main: no level data, running with an empty arena")
		_level_nodes = []
		return
	_level_nodes = load("res://scripts/level_builder.gd").build(self, data)
	print("[level] built %d prop nodes from %s"
		% [_level_nodes.size(), data.get("comment", "level data")])


func _setup_world() -> void:
	## Atmosphere lives in light + fog, not in textures. All of this works
	## in Mobile AND Compatibility, so a web export costs us nothing here.
	##
	## Lighting was lifted after Jan's report: "everything is the same terrible
	## dark brown - objects, floor, clothes. The world needs a little light and
	## life so the contrasts stand out." Measured on the old settings, the game
	## frame had a per-pixel p10 of 23.3 against a p90 of 23.5 (i.e. almost no
	## tonal range at all) and 87.8 % of the image was ONE brown, rgb(32,16,8).
	## The cause was ambient light carrying almost all the illumination while the
	## sun contributed 0.55, so every surface received the same flat brownish wash
	## and nothing had a lit side and a shadow side.
	##
	## The fix is more DIRECTIONAL light (sun 0.95 against ambient 0.40) and less
	## fog. Measured after: p10 35, p50 50, p90 69, 284 distinct colours.
	var we := WorldEnvironment.new()
	var env := Environment.new()

	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.030, 0.028, 0.026)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	## Light settings are the "E_soft_shadow" preset chosen by Jan from a rendered
	## contact sheet of 8 variants (tools/sweep_render.gd + tools/sweep_sheet.py,
	## sheet in docs/props_and_lights_sweep.png). He picked E over the contrastier
	## F: softer shadows and a little more ambient, so the world is readable
	## without the shadows reading as hard black cutouts on the grass.
	## Measured for E: p10 35, p50 50, p90 69, 284 distinct colours, 0 % clipped.
	env.ambient_light_color = Color(0.14, 0.135, 0.125)
	env.ambient_light_energy = 0.40

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_brightness = 0.94
	env.adjustment_contrast = 1.20
	## was 0.82 - desaturating that far turned green grass back into brown
	env.adjustment_saturation = 0.86

	# depth/height fog: supported in every renderer (volumetric fog is Forward+ only)
	env.fog_enabled = true
	env.fog_light_color = Color(0.115, 0.105, 0.095)
	env.fog_light_energy = 0.6
	## was 0.028 - thick enough to grey out the far half of a 34 m floor
	env.fog_density = 0.014
	env.fog_aerial_perspective = 0.0

	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	## was 0.55 - the main source of the flatness: a 0.55 key against 0.75 ambient
	## is barely directional, so nothing had a readable lit face. 1.25 then washed
	## the scene out; 0.95 keeps a readable lit side without lifting the shadow.
	sun.light_energy = 0.95
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.shadow_enabled = true
	sun.shadow_bias = 0.02
	## Full-strength shadows rendered as hard black cutouts on the grass. E's value:
	sun.shadow_opacity = 0.45
	sun.shadow_blur = 1.6
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	add_child(sun)

	# A cool fill from the opposite side so the shadow side is readable instead of
	# black. Kept well under the sun so the direction still reads.
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_energy = 0.30
	fill.light_color = Color(0.62, 0.70, 0.88)
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-24.0, 142.0, 0.0)
	add_child(fill)


func _spawn_posts() -> void:
	## Three inert posts so we can check that a swing lands where it looks like it lands.
	##
	## The collision is a BoxShape3D here, NOT the trimesh that levels/ use, and that
	## is deliberate: measured, the hero stops cleanly at a box prop and comes away
	## from it in any direction. A trimesh needs `backface_collision = true` to
	## behave (see level_builder.gd); a solid box has no thin faces to embed in at
	## all, so there is no flag to get wrong. These posts are also what
	## tools/test_attack.gd swings at, so keeping them solid keeps that test honest.
	var spots := [Vector3(0, 0, -3.2), Vector3(2.6, 0, -1.0), Vector3(-2.4, 0, -2.0)]
	for i in spots.size():
		var body := StaticBody3D.new()
		body.set_script(load("res://scripts/target_post.gd"))
		body.position = spots[i]

		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 1.3, 0.5)
		mi.mesh = bm
		body.add_child(mi)

		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.5, 1.3, 0.5)
		cs.shape = bs
		body.add_child(cs)

		add_child(body)
		_posts.append(body)


func _spawn_enemies() -> void:
	## Jan's brief (Sept 2026): "at the start there are too many enemies. Leave the
	## starting area completely without enemies and put a few enemies a bit further
	## on, towards the top, for testing. Right now I do not get to try anything
	## before they kill me."
	##
	## So the pack is now ONE GROUP far down the north lane (+Z is behind the
	## player, -Z is in front of him: the camera looks down the -Z axis, so
	## "směrem nahoru" on screen is -Z). The nearest monster stands 13.2 m from the
	## player's spawn at (0,0,0) - outside every kind's 5-5.5 m aggro radius, so a
	## session begins in an empty arena and the fight is something the player walks
	## into. Both numbers are asserted in tools/test_fight.gd, because "far enough
	## away" is exactly the property that a later layout edit would quietly break.
	##
	## Three ghouls and one ravager, all north, spread across the lane: met as a
	## small wave rather than as a line, and the same composition the balance claim
	## in monster_kind.gd is written against.
	var spawns := [
		# --- the pack, north lane, roughly 13-17 m out ---
		{"kind": "ghoul", "pos": Vector3(-2.6, 0.0, -13.2)},
		{"kind": "ghoul", "pos": Vector3(2.4, 0.0, -14.6)},
		{"kind": "ghoul", "pos": Vector3(-0.2, 0.0, -16.4)},
		{"kind": "ravager", "pos": Vector3(3.9, 0.0, -14.6)},
	]
	for i in spawns.size():
		var s: Dictionary = spawns[i]
		var e := _build_enemy(str(s["kind"]), s["pos"] as Vector3)
		e.name = "Enemy_%s_%d" % [str(s["kind"]).capitalize(), i]
		_enemies.append(e)


## Builds one monster from its catalogue entry: the behaviour script decides the
## AI, the entry decides the numbers. Nothing here is hand-set per monster, so a
## new kind is a catalogue line plus a spawn line.
func _build_enemy(kind: String, pos: Vector3) -> CharacterBody3D:
	var k: Dictionary = MONSTER_KIND.kind(kind)
	var e := CharacterBody3D.new()
	e.set_script(load(str(k.get("script", "res://scripts/enemy.gd"))))
	e.position = pos

	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.25
	cs.shape = cap
	cs.position = Vector3(0, 0.65, 0)
	e.add_child(cs)

	add_child(e)
	# `target` is what drives the whole behaviour loop; forgetting it looks exactly
	# like "the enemy stands there doing nothing".
	e.target = player
	# A monster with a leash has to know WHERE HOME IS. Without this every kind
	# would consider itself straying the moment it moved and walk back to (0,0,0).
	e.remember_home()
	# The Diablo loop: something dies, something falls on the ground. Wired as a
	# signal so the AI never calls the loot system directly.
	e.died.connect(func() -> void: _on_enemy_died(e))
	return e


## Keeps the enemy health bar honest in a fight with several monsters: the bar
## follows the monster the player last hit, falling back to the nearest one that
## has noticed them.
func _update_focus() -> void:
	if _focus and is_instance_valid(_focus) and _focus.is_engaged() and not _focus.is_dead():
		return
	var best: Node = null
	var best_d := INF
	for e in _enemies:
		if not is_instance_valid(e) or e.is_dead() or not e.is_engaged():
			continue
		var d: float = e.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = e
	_focus = best


func _unhandled_input(event: InputEvent) -> void:
	## The TAP that OPENS A BODY. Jan's model (Sept 2026): "the player opens the
	## corpse and picks the items out of it" - so a tap on a body (or on its label;
	## one Area3D covers both) casts a ray into the world, and the body's contents
	## come up in the loot window.
	##
	## Deliberately `_unhandled_input`: a tap that lands on the HUD or on a real
	## control is consumed there and never reaches this, so the tap that took an
	## item out of the window cannot also re-open the body behind it.
	##
	## ESC / the phone's back gesture closes a panel. It is handled HERE, before the
	## early return, because "no way to close the window" was exactly Jan's report -
	## and ESC is checked at all only now that a panel really can be dismissed with
	## it.
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			if hud != null and hud.panel_open():
				hud.close_panels()
				get_viewport().set_input_as_handled()
			return
	if hud != null and hud.panel_open():
		return
	# ONE FINGER TAP, ONE ACTION. Input synthesises an InputEventMouseButton for every
	# InputEventScreenTouch and `_unhandled_input` receives BOTH, so a tap on a body
	# ran the ray twice and `body_opened` was emitted twice - the panel was opened,
	# laid out and re-armed a second time in the same frame. See scripts/tap_guard.gd.
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		# THE FIRST FINGER MAY OPEN A BODY. An earlier version demanded `index > 0`
		# on the theory that the joystick owns the first finger - but the joystick is
		# a Control and takes its own events, so a world tap never reaches here from
		# it; meanwhile a browser reports a MOUSE click as a touch with index 0, and
		# on a phone the plain tap everyone makes for "open that" is index 0 too.
		# Refusing it meant the loot window often did not open at all.
		if t.pressed and t.index >= 0 and _world_tap_guard.begin():
			_try_open(t.position)
		elif not t.pressed:
			_world_tap_guard.end()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _world_tap_guard.begin():
					_try_open(mb.position)
			else:
				_world_tap_guard.end()


## The tap itself only runs the ray. The window opens off the loot manager's own
## `body_opened` signal, so there is ONE path into the panel whether the tap or the
## HUD button found the body.
func _try_open(screen_pos: Vector2) -> void:
	if loot == null or inventory == null:
		return
	loot.open_at_screen(screen_pos, player.global_position)


## THE PAUSE. Pushed once per PHYSICS frame and before every child gets its own
## `_physics_process` (Main is the root of the scene, so tree order puts this
## first), which is what makes the flag true for the whole frame the panel opened
## in. Read by player.gd and enemy_base.gd.
func _physics_process(_delta: float) -> void:
	GATE.set_blocked(hud != null and hud.panel_open())
	_world_tap_guard.tick()


func _process(_delta: float) -> void:
	# A panel (inventory / hero sheet / an opened body) PAUSES the fight. Diablo
	# does the same, and on a phone it is also what makes a drag reliable: a
	# monster walking into the player would move the world under the finger mid-drag.
	if hud != null and hud.panel_open():
		hud.set_debug("panel otevřen - hra je pozastavená")
		hud.set_player_hp(player.hp_fraction(), "HP %.0f / %.0f" % [player.hp, player.max_hp])
		# A tap that OPENED a panel never delivers its release here (the early return
		# above swallows it), so the world guard must not stay live behind a panel.
		_world_tap_guard.reset()
		return

	# RUN: the HUD latch and the key/pad action are OR-ed HERE - in main.gd, not in
	# player.gd - and pushed to the player, so no single control can block the
	# others. The latch survives the pause on purpose: a player who comes back from
	# his bag still has run latched, which is what he last asked for.
	var run_now: bool = bool(hud.run_latched) or GATE.held("run")
	if run_now != _run_action:
		_run_action = run_now
		player.set_run(run_now)

	# Which DEVICE is driving the movement this frame. A virtual stick hands out a
	# continuous strength, and the player must read that as a direction rather than a
	# throttle or the run speed grades with how far the thumb is pushed (Jan's
	# report). Pushed once per frame, same pattern as the RUN latch.
	player.set_stick_active(bool(hud.stick_active))

	var st: String = player.state_name()
	var f: Vector3 = player.facing
	_update_focus()
	var extra := ""
	var alive := _alive_count()
	extra = "   monsters alive %d/%d" % [alive, _enemies.size()]
	hud.set_debug("state: %s   facing: %+.2f,%+.2f   %s%s" % [st, f.x, f.z, player.debug_text, extra])
	hud.set_player_hp(player.hp_fraction(), "HP %.0f / %.0f" % [player.hp, player.max_hp])
	if _focus and is_instance_valid(_focus):
		if _focus.is_dead():
			hud.set_enemy_hp(0.0, "%s  DEAD" % _focus.monster_name)
		else:
			hud.set_enemy_hp(_focus.hp_fraction(), "%s  (lv %d)  %.0f / %.0f"
				% [_focus.monster_name, _focus.level, _focus.hp, _focus.max_hp])
	else:
		hud.set_enemy_hp(0.0, "")


func _alive_count() -> int:
	var n := 0
	for e in _enemies:
		if is_instance_valid(e) and not e.is_dead():
			n += 1
	return n


## Removes the whole pack. The gameplay tests that measure a move-lock, a
## miss-when-facing-away or reach on their own fixed coordinates call this after
## instantiating the scene, and the reason is measured, not cosmetic: a monster
## walking into the arc a test is aiming at turns "facing away must miss" into a
## hit, and a body pressed against the player during an attack window moves them
## and reports a broken commitment. The pack itself is verified by test_fight.gd,
## which is the test that is supposed to have monsters in the scene.
func clear_enemies() -> void:
	for e in _enemies:
		if is_instance_valid(e):
			e.queue_free()
	_enemies.clear()
	_focus = null


## Removes everything lying on the ground. Test-only, like clear_enemies(): a
## measured section must not be disturbed by an item its own kills dropped.
func clear_loot() -> void:
	if loot != null and is_instance_valid(loot):
		loot.clear()


## Moves every level prop out of the way so a locomotion test can measure a clean,
## straight run. The arena is only ~15 m across and the props frame the lanes, so a
## run at full speed reaches a wall in well under a second - a test that starts
## outside the arena walks into the south wall and reports its own collision as a
## failure in the animation code (measured: stopped dead at z = 6.7, clip
## `Rig|Sword_Idle`, while the retime it was checking was correct).
##
## Collision lives on the prop node itself, so the whole StaticBody3D is parked.
## A test-only helper - NOTHING in production calls it.
func clear_level_props() -> int:
	var moved := 0
	for n in _level_nodes:
		if not is_instance_valid(n):
			continue
		if n is Node3D:
			(n as Node3D).position.y = -50.0
			n.visible = false
			moved += 1
	return moved


func _on_landed(kind: String, collider: Node, point: Vector3) -> void:
	_hits.append({"kind": kind, "who": collider.name})
	# whomever the player just swung at is the one whose health bar matters
	if _enemies.has(collider):
		_focus = collider
	print("[hit] %s on %s at %s" % [kind, collider.name, point])


func _on_player_damaged(amount: float, hp_left: float) -> void:
	print("[player] took %.1f damage, %.0f hp left" % [amount, hp_left])


func _on_player_died() -> void:
	print("[player] died")
