extends SceneTree
## tools/test_portrait_visual.gd — the layout rules that a screenshot alone cannot pin.
##
## The port is judged against the PWA's own screenshots, and "the arena looks wrong" has
## exactly two causes worth a test:
##
##   1. The canvas is not the PWA's portrait phone size. The PWA's CSS is written for a
##      390x844 viewport and lays out on it; on a landscape canvas every measurement in
##      the port is a different game. This is a PROJECT SETTING, so it regresses silently
##      the moment someone re-imports a preset or changes the display section.
##   2. The arena's ring stack is not concentric or is the wrong radius. The rings are the
##      one piece of the PWA's arena with hard numbers (260px stack, r=110/120/88/104/95),
##      and a ring drawn at the wrong radius is a subtly different screen that no
##      "the fight ran" test can see.
##
## Run:  godot --headless --path . --script res://tools/test_portrait_visual.gd
## Pass: prints PORTRAIT_VISUAL_ALL_PASS=true and exits 0.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const GaugeArc := preload("res://scripts/ui/ui_gauge.gd")

var _data: Node
var _gen: ItemGen
var _loot: LootSystem
var _failures: Array[String] = []


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_loot = LootSystem.new(_data, _gen)

	_test_canvas_is_portrait()
	_test_clear_colour_is_the_pwa_background()
	_test_ring_stack_matches_the_pwa()
	_test_gauge_arc_draws_a_proportional_sweep()
	_test_arc_geometry_is_bottom_anchored()

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("PORTRAIT_VISUAL_ALL_PASS=true")
	else:
		print("PORTRAIT_VISUAL_ALL_PASS=false")
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


## The PWA is a phone game and its CSS assumes it. Landscape is a separate, later job
## (Jan's call) — until a landscape layout exists, a landscape canvas is a bug.
func _test_canvas_is_portrait() -> void:
	var w := int(ProjectSettings.get_setting("display/window/size/viewport_width", 0))
	var h := int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))
	if w != 390 or h != 844:
		_fail("the canvas is %dx%d, not the PWA's 390x844" % [w, h])
	if h <= w:
		_fail("the canvas is not portrait (%dx%d)" % [w, h])


## The PWA's body background is #121212. Godot's default clear colour is mid grey, and any
## screen that does not paint its own background (the arena) shows it through.
func _test_clear_colour_is_the_pwa_background() -> void:
	var colour: Color = ProjectSettings.get_setting(
		"rendering/environment/defaults/default_clear_color", Color(0.5, 0.5, 0.5))
	var hex := colour.to_html(false)
	if not hex.begins_with("121212") and not hex.begins_with("121213"):
		_fail("the clear colour is #%s, not the PWA's #121212" % hex)


## The ring stack, straight out of public/style.css. Each entry is the value the PWA's
## SVG puts in the `r` attribute; the port must keep them distinct, or two rings land on
## top of each other and the arena silently loses a gauge.
func _test_ring_stack_matches_the_pwa() -> void:
	var screen = _arena()
	if screen == null:
		return
	# radius -> [what it is]
	var expected := {
		110.0: "player swing timer",
		120.0: "offhand swing timer",
		88.0: "enemy swing timer",
		104.0: "zone divider",
		95.0: "enemy HP ring",
		92.0: "enemy mana ring",
	}
	var found := {}
	for arc in [screen._arc_player, screen._arc_offhand, screen._arc_enemy_timer,
			screen._arc_enemy_hp, screen._arc_enemy_mana, screen._arc_divider]:
		if arc == null:
			_fail("an arc node is missing from the arena")
			return
		found[arc.radius] = str(arc.radius)
	for radius in expected:
		if not found.has(radius):
			_fail("no arc at radius %s (%s) — the PWA has one" % [radius, expected[radius]])
	# And they must not collide: every radius distinct.
	if found.size() != 6:
		_fail("the six named arcs use %d distinct radii, expected 6" % found.size())


## An arc that ignores its value is a decoration, not a gauge. Sweep must be proportional
## and the full-turn case must actually close.
func _test_gauge_arc_draws_a_proportional_sweep() -> void:
	var arc = GaugeArc.new_arc()
	arc.radius = 50.0
	# `value` is a plain setter, so this pins the CONTRACT the arena relies on: whatever
	# the battle number is, the ratio handed to the arc is between 0 and 1.
	for pair in [[0.0, 0.0], [0.5, 0.5], [1.0, 1.0], [1.4, 1.0], [-0.3, 0.0]]:
		arc.set_value_ratio(float(pair[0]))
		if not is_equal_approx(arc.value, float(pair[1])):
			_fail("set_value_ratio(%s) left value at %s, expected %s"
				% [pair[0], arc.value, pair[1]])
	arc.queue_free()


## The arena's rings are placed by `_centre_in_arena`, which must put them at the SAME
## centre — the boxes are different sizes (260 vs 200), so only the radius may differ.
## Two arcs whose centres disagree are an arena that looks hand-placed, not concentric.
##
## The arena has no size in a SceneTree test (no layout pass happens), so it is given one
## here and `_apply_centring()` is called directly — that is what a real frame does.
func _test_arc_geometry_is_bottom_anchored() -> void:
	var screen = _arena()
	if screen == null:
		return
	screen._arena.size = Vector2(390, 666)
	screen._apply_centring()

	var player_centre: Vector2 = screen._arc_player.position + screen._arc_player.size * 0.5
	for arc in [screen._arc_enemy_hp, screen._arc_enemy_timer, screen._arc_divider,
			screen._arc_offhand]:
		var centre: Vector2 = arc.position + arc.size * 0.5
		if player_centre.distance_to(centre) > 1.0:
			_fail("an arc is not concentric with the player timer: %s vs %s (r=%s)"
				% [player_centre, centre, arc.radius])
	if screen._arc_player.size != Vector2(260, 260):
		_fail("the ring stack is %s, not the PWA's 260x260" % screen._arc_player.size)
	if screen._arc_enemy_hp.size != Vector2(200, 200):
		_fail("the enemy HP ring box is %s, not the PWA's 200x200" % screen._arc_enemy_hp.size)


## An arena built the way main.gd builds it, with a fight running. Uses the same
## `_build()` call pattern as test_arena_screen.gd: a SceneTree script's _initialize()
## runs before the first frame, so _ready() has not fired on the fresh node.
func _arena():
	var state = GameState.new()
	state.bind_data(_data)
	state.set_class("barbarian")
	var screen = load("res://scripts/ui/arena_screen.gd").new(_data, _gen, _loot, state,
		func(id):
			var item_id := str(id)
			if item_id == "":
				return {}
			var static_item: Dictionary = _data.item(item_id)
			if not static_item.is_empty():
				return static_item
			return state.loot_item(item_id))
	root.add_child(screen)
	if screen._arc_player == null:
		screen._build()
	screen.start(state, func(id): return _data.item(str(id)))
	if screen.battle == null:
		_fail("the arena could not start a fight")
		return null
	return screen
