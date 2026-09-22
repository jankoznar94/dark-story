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
const UIKit := preload("res://scripts/ui/ui_kit.gd")
const UIFonts := preload("res://scripts/ui/ui_fonts.gd")

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
	_test_no_screen_uses_flat_buttons()
	_test_grid_cells_are_the_pwa_light_box()
	_test_the_ui_font_is_dejavu()

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("PORTRAIT_VISUAL_ALL_PASS=true")
	else:
		print("PORTRAIT_VISUAL_ALL_PASS=false")
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


## `Button.flat = true` makes a Button SKIP drawing its stylebox — so a slot built with
## a border style and `flat = true` renders as if it had no border at all. That is
## exactly how every slot in the inventory became invisible while the node tree, the
## sizes and every gameplay test looked perfect. A source scan is the only gate that
## catches it: by the time the button exists, the theme override is present and correct.
func _test_no_screen_uses_flat_buttons() -> void:
	for path in _ui_scripts():
		var source := FileAccess.get_file_as_string(path)
		for line_no in source.split("\n").size():
			var line: String = source.split("\n")[line_no]
			var trimmed := line.strip_edges()
			if trimmed.begins_with("#"):
				continue
			if trimmed.ends_with(".flat = true"):
				_fail("%s:%d sets flat = true, which hides every stylebox border" % [
					UIKit_short(path), line_no + 1])


## Every .gd under scripts/ui, so a new screen cannot slip past the check above.
func _ui_scripts() -> Array:
	var out: Array = []
	var dir := DirAccess.open("res://scripts/ui")
	if dir == null:
		_fail("scripts/ui is not readable")
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".gd"):
			out.append("res://scripts/ui/" + name)
		name = dir.get_next()
	dir.list_dir_end()
	return out


func UIKit_short(path: String) -> String:
	var parts := path.split("/")
	return str(parts[parts.size() - 1])


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


## `.chest-cell { background:#aaa; border:1px solid #777 }` + `.empty { opacity:0.25 }`.
##
## This was the single largest visual error in the port (the chest went from 44.7% of
## pixels differing to 6.7% once it was fixed) and NOTHING else could see it: the chest
## behaved correctly, it just looked wrong. A cell is a LIGHT tile — at the empty opacity
## it renders as rgb(43,43,43) inside a #000 box, a filled one as a light grey tile with
## the quality colour on its border.
##
## Two specific ways to get it wrong, both pinned here:
##   - `flat = true` skips every stylebox the cell carries, turning the tile invisible;
##   - an empty cell must dim by `modulate` (CSS opacity inherits the whole box), not by
##     painting a black background.
func _test_grid_cells_are_the_pwa_light_box() -> void:
	var empty_cell: Button = UIKit.item_cell({}, 44.0)
	root.add_child(empty_cell)
	var empty_style := empty_cell.get_theme_stylebox("normal") as StyleBoxFlat
	if empty_style == null:
		_fail("item_cell has no normal stylebox — a grid cell is invisible without one")
		return
	if empty_cell.flat:
		_fail("item_cell sets flat = true, which skips the stylebox and hides the tile")
	var light_fill := Color(UIKit.CELL_FILL)
	if not empty_style.bg_color.is_equal_approx(light_fill):
		_fail("an empty cell's fill is %s, not the PWA's light #aaa" % empty_style.bg_color)
	if not empty_style.border_color.is_equal_approx(Color(UIKit.CELL_BORDER_EMPTY)):
		_fail("an empty cell's border is %s, not the PWA's #777" % empty_style.border_color)
	if not is_equal_approx(empty_cell.modulate.a, 0.25):
		_fail("an empty cell's alpha is %.2f, not the PWA's `.empty { opacity:0.25 }`"
			% empty_cell.modulate.a)
	if empty_cell.modulate.r < 0.99:
		_fail("the empty cell is tinted (%s); the PWA dims by opacity alone"
			% empty_cell.modulate)

	# A filled cell is the SAME tile with the quality colour on the border. `unique` is
	# the one quality `quality_color` derives from a flag rather than the string, so this
	# also pins that the two agree.
	var item := {"id": "test_sword", "name": "Test Sword", "rarity": "unique",
		"iconImg": ""}
	var filled_cell: Button = UIKit.item_cell(item, 44.0)
	root.add_child(filled_cell)
	var filled_style := filled_cell.get_theme_stylebox("normal") as StyleBoxFlat
	if not filled_style.bg_color.is_equal_approx(light_fill):
		_fail("a filled cell's fill is %s, not the same light #aaa" % filled_style.bg_color)
	var want := UIKit.ItemStats.quality_color(item)
	if not filled_style.border_color.is_equal_approx(want):
		_fail("a unique cell's border is %s, not the quality colour %s"
			% [filled_style.border_color, want])
	if not is_equal_approx(filled_cell.modulate.a, 1.0):
		_fail("a filled cell is dimmed to alpha %.2f; only empty cells dim"
			% filled_cell.modulate.a)
	# `.chest-cell:active { background:#aaa }` is the only state change — no hover.
	for state in ["hover", "focus"]:
		var hover_style := filled_cell.get_theme_stylebox(state) as StyleBoxFlat
		if hover_style == null:
			continue
		if not hover_style.bg_color.is_equal_approx(filled_style.bg_color):
			_fail("the cell's `%s` state repaints the tile (%s); the PWA has no hover"
				% [state, hover_style.bg_color])


## The reference frames are shot in headless Chromium, where the PWA's
## `font-family: system-ui, sans-serif` resolves to **DejaVu Sans**. Godot's own default
## is Open Sans SemiBold, which is ~3% wider per glyph and builds an ~1.43em line box
## against the CSS `line-height: normal` ~1.16em — a 14px Label came out 20px tall where
## the PWA's is 16, and that excess accumulated into vertical drift on EVERY screen.
##
## This is a project-wide setting with no gameplay symptom, so it regresses the moment
## someone re-imports a theme or trusts `Theme.default_font`. Checked at the theme
## `main.gd` actually installs, not at `UIFonts` alone.
func _test_the_ui_font_is_dejavu() -> void:
	var font := UIFonts.regular()
	if font == null:
		_fail("the UI font does not load at all")
		return
	if not font.get_font_name().begins_with("DejaVu"):
		_fail("the UI font is %s, not the DejaVu Sans the reference frames use"
			% font.get_font_name())
	# Advances are the measurement the choice was made from: "Truhla" is 303px at 100px
	# in the reference Chromium. A font swap that keeps the name but changes the file
	# would still be wrong here.
	var width: float = font.get_string_size("Truhla", HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x
	if abs(width - 303.0) > 4.0:
		_fail("\"Truhla\" is %.1fpx at 100px, the reference measures 303" % width)
	# Bold must be a real face: CSS `font-weight: bold` in DejaVu is ~13% wider than the
	# regular, so `variation_embolden` would keep every bold advance wrong.
	var bold_width: float = UIFonts.bold().get_string_size(
		"Back to Town", HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	if bold_width < 105.0:
		_fail("bold \"Back to Town\" is %.1fpx at 15px, the reference measures 111.4 — "
			% bold_width + "the bold face is not the real one")

	# The line box, per size, against the CSS values read off the live PWA.
	for size in UIFonts.CSS_LINE_HEIGHT:
		var want: int = int(UIFonts.CSS_LINE_HEIGHT[size])
		var got: int = int(round(UIFonts.get_font(size).get_height(size)))
		if abs(got - want) > 1:
			_fail("a %dpx Label is %dpx tall, the PWA's line box is %d" % [size, got, want])
