class_name WorldScreen
extends Control
## WorldScreen — Jan's "putování": the road HOME, drawn as a road, with a WALKING hero on it.
##
## Three decisions from Jan, in his own words, and each one shapes a piece of this file:
##
##   1. "Po vstupu do oblasti se přepne obrazovka." — entering a stop on the map does NOT open
##      the arena any more. It opens this screen, at fight 1 of 10. The player taps the road to
##      start each fight, and the arena is where a fight ENDS.
##   2. "Vlastní cesta." — the way home is its OWN road, not a stretch of the fight road. The
##      walk home button lives here (it used to be a flat `.map-actions` button on the map) and
##      it wears its price, because losing the zone's fights is the decision.
##   3. "Nechat bez nich." — no waypoints. The PWA deleted them ("waypointy zrušeny") and the
##      art in `assets/waypoints/` is left unused on purpose.
##
## ⚠️  NO RULES LIVE HERE. Which fight is current is the SAVE's (`locationProgress` +
## `areaFightProgress`), walked by `Battle.advance_stop`. The screen reads it, projects it, and
## emits a signal when the player taps the next node — exactly as `arena_screen` does not own
## the fight it draws. A screen that advanced the save itself would be a second source of truth
## for progression, and nothing could test it without a viewport.
##
## The ground is the area's own art (`assets/stops/stop_actN_M.webp`) — the same file the arena
## uses as its backdrop, so the world and the fight agree about where the hero is standing.

const UIKit := preload("res://scripts/ui/ui_kit.gd")
const UIFonts := preload("res://scripts/ui/ui_fonts.gd")
const Battle := preload("res://scripts/combat/battle.gd")

signal next_fight_requested()
signal walk_home_requested()
signal portal_requested()

const BG := Color("#121212")
const GOLD := Color(UIKit.GOLD)
const DIM := Color("#666666")
const NODE_DONE := Color("#5a5a5a")
const NODE_NEXT := Color("#8a8a8a")

## The road runs DOWN the screen, as the shipped map's stop path does (stop 1 at the top), so the
## two screens agree about which way the journey runs.
##
## ⚠️  `ROAD_LEFT`/`ROAD_RIGHT`/`MEANDER` are GONE. They sized a drawn band; there is no band any
## more, only the dots. `SERPENTINE_AMP` is the whole of the route's shape now.
##
## Jan: "puntíky by měly být tak nějak od horní hrany obrázku ke spodní. Aby cesta vedla přes
## celý obrázek." Measured against the real screen (390x844 content, `_probe_world_band.gd`):
## the header's box ends at y=56, the two action buttons start at y=752 and the nav bar at 783.
## The hard limits follow from those, and the two ENDS are not symmetric:
##
##   * the TOP node is the dangerous one, because the hero sprite is drawn UPWARD from his node
##     (96 px tall, his feet ON the node, so his head is `y - HERO_SIZE + 14`). The hard limit is
##     0.1635, where his head touches the header exactly; 0.17 leaves 5 px.
##   * the BOTTOM node has no sprite hanging off it, only its ring (NODE_R + 5 = 21 px). Its hard
##     limit is 0.866, where the ring touches the buttons; 0.86 leaves 5 px.
const ROAD_TOP := 0.17
const ROAD_BOTTOM := 0.86
## How far the route drifts either side of centre, as a fraction of the width. A "lehká
## serpentina": one sine period at 0.10 swings 78 px of 390 (20 %) across the ten stations.
##
## ⚠️  The route is NOT centred any more, and that is what makes room for the hero. Jan: "Hrdina
## ... musí být bokem tak, ať nic nepřekrývá." With the centre at 0.42 the nodes span
## 125..203 px, so the hero's column can own the right of the screen and never touch a node —
## see `HERO_X`. Centring them would have forced the hero either on top of the road or off the
## edge of a 390 px canvas.
const SERPENTINE_CENTER := 0.42
const SERPENTINE_AMP := 0.10

var _state
var _data: Node
var _find_item: Callable

var _header_act: Label
var _header_fight: Label
var _walk_button: Button
var _portal_button: Button
## The road itself. A plain Control with its own `_draw()` rather than a container: everything
## here is positioned by hand from `NODES`, and a container would overwrite those rects (the trap
## that cost the result page its layout twice).
var _canvas: Control
## The hero is a NODE, not a `draw_texture_rect` call. Measured: drawing an RGBA sprite through
## `CanvasItem.draw_texture_rect` in this screen's `_draw()` rendered its transparent area as
## SOLID WHITE (a 96x96 block over the road), while the arena — which uses a `TextureRect` with
## `STRETCH_KEEP_ASPECT_CENTERED` — shows the same file correctly. The node is also what lets the
## walk be an eased position instead of a redraw per frame.
var _hero: TextureRect
## The area's own art, loaded OUTSIDE the draw. `_draw_ground()` used to call `_stop_art()` from
## inside `_draw()`, and that combination renders the texture WHITE: measured, the shipped
## `_draw_ground(390, 844)` alone on a bare canvas came out a flat (0.3176,0.3176,0.3216) —
## 81 % of the whole frame in one colour — while the same three draw calls with the texture
## loaded beforehand gave the art's real dark reading (0.078/0.106 at the same pixels). Loading
## a texture and drawing it in the same `_draw()` is the trap; the file, alpha and destination
## were never wrong. Cached in `refresh()` (and once in `_build()` so the first draw has it).
var _ground_tex: Texture2D

## Where the hero is, in NODES. -1 is "at the very start, not on a node" — which only happens on
## a fresh zone, so the first thing the player sees is the hero walking INTO the road.
var _walk_from := -1
var _walk_progress := 1.0
const WALK_SPEED := 1.6  # nodes per second


func _init(game_data: Node, state, find_item: Callable) -> void:
	_data = game_data
	_state = state
	_find_item = find_item


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


## Every entry into the screen goes through here. `show_screen` calls it, so the header, the
## buttons and the start position can never disagree with the save.
func refresh() -> void:
	_walk_from = _current_fight() - 1
	_walk_progress = 1.0
	# The ground's texture is resolved HERE, once per entry, and never from inside `_draw()`.
	_ground_tex = _area_art()
	if _header_act != null:
		_header_act.text = _zone_name()
		_header_fight.text = "souboj %d/%d" % [_current_fight(), _total_fights()]
	_refresh_actions()
	_place_hero()
	if _canvas != null:
		_canvas.queue_redraw()


## ⚠️  Every read of a progress table goes through `_progress()`, which is RANGE-CHECKED. Measured:
## both `_current_fight()` and `_zone_name()` indexed the save's arrays directly with the act id, so
## an act id no table covers produced `Invalid access of index '99' on a base object of type:
## 'Array'` — and because `_place_hero()` -> `_hero_anchor()` -> `_current_fight()` runs from
## `_process`, that error was logged EVERY FRAME. The save is a JSON file that can hold an act id
## the tables do not, so the screen must read it defensively rather than die (or spam) on it.
##
## A test cannot assert a logged error, so this one is verified by a probe instead:
## `tools/_probe_stop_art_range.gd` with act 99 must print NO `SCRIPT ERROR` line.
func _progress(table: String) -> int:
	var list: Array = _state.data.get(table, [])
	var act := _act_id()
	return int(list[act]) if act >= 0 and act < list.size() else 0


func _current_fight() -> int:
	return _progress("areaFightProgress")


func _total_fights() -> int:
	return int(Battle.FIGHTS_PER_ZONE)


func _act_id() -> int:
	return int(_state.data.get("_currentAct", 0))


## The heading is the STOP's own name ("Meadow"), which is the area the road runs through — the
## same table and the same lookup the map uses for its stop cards, so the two screens name the
## place identically. The STOP_NAMES table is keyed by act id, each act holding its stops.
func _zone_name() -> String:
	var names: Dictionary = _data.table("STOP_NAMES_EN", {})
	var per_act: Variant = names.get(str(_act_id()), null)
	var stop := _progress("locationProgress")
	if per_act is Array and stop < (per_act as Array).size():
		return str((per_act as Array)[stop])
	return "Oblast %d" % (_act_id() + 1)


## `.map-actions`' two buttons, now on the road where they belong. Both are conditional and the
## conditions are DIFFERENT — that is the whole point of the naming work on the handlers:
##
##   * "Jít domů" is always there: the walk is what costs the zone's fights, and a player must be
##     able to take it at any time.
##   * "Town Portal" only while a scroll is carried; it STORES the position and spends the
##     scroll (`_on_map_portal_used` in main), so the return is free.
func _refresh_actions() -> void:
	if _portal_button == null:
		return
	_portal_button.visible = int(_state.data.get("townPortalCount", 0)) > 0


func _process(delta: float) -> void:
	if _canvas == null:
		return
	_place_hero()
	if _walk_progress >= 1.0:
		return
	var target := float(_current_fight() - 1)
	var span := target - float(_walk_from)
	if is_zero_approx(span):
		_walk_progress = 1.0
		return
	_walk_progress = minf(1.0, _walk_progress + delta * WALK_SPEED / absf(span))
	_canvas.queue_redraw()


# ============================================================================ build

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_road)
	add_child(_canvas)

	_hero = TextureRect.new()
	_hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero.texture = UIKit.load_texture("assets/monsters/hero_body_%s.png"
		% str(_state.data.get("heroClass", "barbarian")))
	# ⚠️  The size is set ONCE, here, and never from inside `_draw_road`. Measured: assigning a
	# Control's `size` during another node's `_draw()` did not stick — the hero node stayed 0x0 and
	# drew nothing at all, while the same `TextureRect` works in the arena. Position is cheap and
	# changes every frame; size is a constant.
	_hero.size = Vector2(HERO_SIZE, HERO_SIZE)
	add_child(_hero)

	# The very first draw happens before any `refresh()`, so the ground's texture is resolved here
	# too — same reason as in `refresh()`, and the same rule: never load a texture from `_draw()`.
	_ground_tex = _area_art()

	_build_header()
	_build_actions()


## `.battle-header`'s shape: the place on the left, the fight counter as its second line. No
## invented stat lines — the map's own lesson was that invented state is the biggest visual diff.
func _build_header() -> void:
	var head := VBoxContainer.new()
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.offset_top = 18
	head.offset_left = 16
	head.offset_right = -16
	head.add_theme_constant_override("separation", 2)
	add_child(head)

	_header_act = Label.new()
	_header_act.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_act.add_theme_font_size_override("font_size", 17)
	_header_act.add_theme_color_override("font_color", Color(UIKit.TEXT))
	head.add_child(_header_act)

	_header_fight = Label.new()
	_header_fight.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_fight.add_theme_font_size_override("font_size", 12)
	_header_fight.add_theme_color_override("font_color", GOLD)
	head.add_child(_header_fight)


func _build_actions() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_bottom = -UIKit.NAV_RESERVE + 8
	row.offset_top = row.offset_bottom - 30
	row.offset_left = 12
	row.offset_right = -12
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	_walk_button = UIKit.secondary_button("Jít domů", 30)
	_walk_button.add_theme_font_size_override("font_size", 12)
	_walk_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_walk_button.pressed.connect(func(): walk_home_requested.emit())
	row.add_child(_walk_button)

	_portal_button = UIKit.secondary_button("Town Portal", 30)
	_portal_button.add_theme_font_size_override("font_size", 12)
	_portal_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_portal_button.visible = false
	_portal_button.pressed.connect(func(): portal_requested.emit())
	row.add_child(_portal_button)


# ============================================================================ geometry

## The route is a LIGHT SERPENTINE, and it is pure arithmetic: no random seed, no drifting
## between a redraw and a tap. The nodes' own rects are read back from this by the hit test, which
## is what keeps a tap landing on the node the player aimed at.
##
## Jan: "Nech jen puntíky. V nějakém takovém tvaru pomyslné cesty. Třeba lehká serpentina."
## So the curve is expressed by the NODE POSITIONS alone — there is no road under them — and a
## gentle S is all it should be. Measured against the previous sine-of-index meander, which
## swung 30 % of the width and read as a strong zigzag; this one drifts within 13 %.
##
## Two sines of different periods, so the S is not a single symmetric wave: the first gives the
## main swing, the second bends its ends back.
## ⚠️  Those two sines together made THREE direction changes — a zigzag, not a serpentine.
## Measured, ten nodes: `[1,1,-1,1,1,-1,-1,-1,-1]`. A light S is ONE sine period, which gives two
## gentle turns: `A 0.12, phase -0.6` -> 92 px of swing (23.5 %) and exactly two turns.
func node_pos(index: int) -> Vector2:
	var total := _total_fights()
	if total <= 1:
		return size * 0.5
	var t := float(index) / float(total - 1)
	# One full period across the ten stations: right, back through the middle, and out again.
	var x := size.x * (SERPENTINE_CENTER + SERPENTINE_AMP * sin(t * TAU - 0.6))
	var y := size.y * (ROAD_TOP + t * (ROAD_BOTTOM - ROAD_TOP))
	return Vector2(clampf(x, 34.0, size.x - 34.0), y)


const NODE_R := 16.0
## The hero's drawn height. Constant, so it is set once in `_build()`.
##
## ⚠️  96 was too tall for a road whose stations are 64.7 px apart — his head covered the node
## ABOVE the one he stood on (measured: 1.3 nodes' worth). Jan's instruction was that he must not
## cover anything, so this is a second, independent lever from `HERO_X`: at 72 px he is still a
## readable figure and no longer reaches the node above.
const HERO_SIZE := 72.0

## Where the hero stands, as a fraction of the width — BESIDE the road, never on it. Jan: "Hrdina
## ... musí být bokem tak, ať nic nepřekrývá."
##
## The nodes are centred on `SERPENTINE_CENTER` 0.42, and with the clamp at 34 px the rightmost
## node can only ever reach x = 0.58 * 390 = 226. The hero is drawn `HERO_SIZE` wide around this
## anchor, so 0.87 puts his left edge at 0.87 * 390 - 36 = 303 and every node stays 77 px clear of
## him. Measured across all ten stations, not assumed — pinned by `test_world_screen`.
const HERO_X := 0.87


## Which node a point is on, or -1. Taps are resolved against the DRAWN positions, so the drawing
## and the hit test cannot drift apart.
func node_at(point: Vector2) -> int:
	for i in _total_fights():
		var p := node_pos(i)
		if absf(point.x - p.x) <= 26.0 and absf(point.y - p.y) <= 26.0:
			return i
	return -1


# ============================================================================ drawing

func _draw_road() -> void:
	var w := size.x
	var h := size.y
	_draw_ground(w, h)
	var total := _total_fights()

	# ⚠️  NO ROAD IS DRAWN. Jan: "Nekresli tam ale už tu hnědou cestu navíc... Nech jen
	# puntíky." The route is the CHAIN OF NODES itself — an earlier version laid a 30 px brown
	# band under them, which read as a second, competing road next to the one painted in the
	# background. What carries the eye now is the serpentine the node positions make.
	#
	# The way HOME: a branch off node 0 going up and out of the chain. Jan's "vlastní cesta" —
	# it is its own direction, and it is the ONLY thing on this screen that is not a fight. It
	# keeps a thin line because it is not a station and has to be visibly a different thing.
	var home := node_pos(0)
	var gate := Vector2(w * 0.5, 74.0)
	_canvas.draw_line(home, gate, Color(0.30, 0.26, 0.20, 0.85), 10.0)
	_draw_home(gate)

	# The hero's shadow goes on the canvas (under his feet); the figure itself is the node above,
	# positioned by `_place_hero()` — see the size note in `_build()`.
	var anchor := _hero_anchor()
	_canvas.draw_circle(Vector2(anchor.x, anchor.y + 2.0), 16.0, Color(0, 0, 0, 0.5))

	for i in total:
		_draw_node(i, node_pos(i))


## The area's own art, as the ground — cover-fitted so the portrait screen is filled.
##
## ⚠️  Jan's design, and all three parts matter:
##
##   1. "Obrázek bude jen pozadí, pro efekt." The painting is scenery. NOTHING is placed
##      according to its composition — an earlier attempt painted ten milestone stones into the
##      art and then added ten more on top, which put a second, conflicting set beside the ones
##      the model had invented by itself.
##   2. "Cesta bude normálně interaktivní" — the route is the DOTS, and the dots are the taps.
##      Jan re-stated it after seeing the new art: a dirt road IS painted into the picture now
##      ("Cesta bude vidět na obrázku, ale jen jako vizuální prvek"), and it still has NOTHING
##      to do with the interactive route. Do not place a node on it. The dots follow their own
##      serpentine across the whole screen; the painted road is what makes the landscape read as
##      a place the hero is travelling through.
##   3. "Tento filtr můžeme udělat přímo ve hře. Nemusí to generovat flux." So the dimming is a
##      layer here, not baked into the file: `DARK_FILTER` is tunable without regenerating art.
##
## `DARK_FILTER` was 0.22 and is now 0.12, chosen by measuring the painting's luminance AT THE
## DOTS (which is what decides whether they read): seed 33 gives 71.7 at 0.12 against 65.4 at
## 0.22. Vision's verdict on the 0.22 preview was that the top nodes "nearly dissolve into the
## silhouette" and that the filter cost the upper half of the image; at 0.12 the road, the trees
## and the mist all still read while the top nodes hold. Jan's earlier rejection of 0.62 ("už je
## moc") is the other end of the same scale.
const DARK_FILTER := 0.12

## The painting under the road, one per ACT — `assets/areas/area_<act>.webp`, a view of the area
## with a path winding through it, generated at 512x768 (the largest portrait non-square this
## Flux backend accepts; large SQUARES crash it).
##
## ⚠️  This is NOT the arena's art. `assets/stops/stop_actN_M.webp` is the stop-by-stop backdrop
## the FIGHT uses — the same file the arena shows behind the duel, so the world and the fight
## agree about where the hero stands. This one is a DIFFERENT VIEW of the same area, entered
## whenever the player steps into the area.
##
## Falls back to the stop art and then to the act's placeholder, so a missing new file shows the
## old behaviour rather than a flat field.
func _area_art() -> Texture2D:
	var tex := UIKit.load_texture("assets/areas/area_%d.webp" % _act_id())
	if tex != null:
		return tex
	return _stop_art()


func _draw_ground(w: float, h: float) -> void:
	var tex := _ground_tex
	if tex == null:
		return
	var tex_size := tex.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	var scale_factor := maxf(w / tex_size.x, h / tex_size.y)
	var drawn := tex_size * scale_factor
	var origin := Vector2((w - drawn.x) * 0.5, (h - drawn.y) * 0.5)
	# Full opacity: the painting is the background now, not a wash behind a drawn road, so it is
	# not faded to 0.42 any more — the filter below is what sets how loud it is.
	_canvas.draw_texture_rect(tex, Rect2(origin, drawn), false)
	# The filter. Flat toning, no glow — Jan's standing rule.
	_canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), Color(0.03, 0.03, 0.04, DARK_FILTER))


func _draw_home(gate: Vector2) -> void:
	_canvas.draw_circle(gate, 22.0, Color("#1a1a1a"))
	_canvas.draw_arc(gate, 22.0, 0.0, TAU, 40, Color("#8a7a4a"), 2.0)
	var house := UIKit.load_texture("assets/menu-icons/mesto.png")
	if house != null:
		_canvas.draw_texture_rect(house, Rect2(gate - Vector2(15, 15), Vector2(30, 30)), false)
	var font := UIFonts.get_font(10)
	if font != null:
		# Centred ON the road, which is where the eye already is. The full sentence is on the
		# button that takes the decision ("Jít domů"), so this is a label, not a warning.
		_canvas.draw_string(font, gate + Vector2(-90, 40), "domů",
			HORIZONTAL_ALIGNMENT_CENTER, 180.0, 10, Color("#9a9a9a"))


## Four states, and an empty state is a STYLE rather than a hidden node: done (a tick), current
## (gold, the fight the player is on), next (tappable), locked (dim).
func _draw_node(index: int, p: Vector2) -> void:
	var fight := index + 1
	var current := _current_fight()
	var done := fight < current
	var is_current := fight == current
	var is_next := fight == current + 1

	var fill := Color("#141414")
	var border := DIM
	if done:
		border = NODE_DONE
	elif is_next:
		border = NODE_NEXT
		fill = Color("#1c1c1c")
	_canvas.draw_circle(p, NODE_R, fill)
	if is_current:
		_canvas.draw_arc(p, NODE_R + 5.0, 0.0, TAU, 48, GOLD, 3.0)
		border = GOLD
	_canvas.draw_arc(p, NODE_R, 0.0, TAU, 40, border, 2.0)

	var font := UIFonts.get_font(14)
	if font == null:
		return
	if done:
		# A tick, drawn rather than a glyph: DejaVu has no emoji and the game forbids them.
		_canvas.draw_line(p + Vector2(-6, 0), p + Vector2(-2, 5), NODE_DONE, 2.0)
		_canvas.draw_line(p + Vector2(-2, 5), p + Vector2(7, -6), NODE_DONE, 2.0)
	else:
		var colour := GOLD if is_current else (Color(UIKit.TEXT) if is_next else DIM)
		_canvas.draw_string(font, p + Vector2(0, 5), str(fight), HORIZONTAL_ALIGNMENT_CENTER,
			NODE_R * 2.0, 14, colour)


## The hero's position. He stands BESIDE the road, in his own column, and never on a node — so he
## cannot cover one. Jan: "Hrdina ... musí být bokem tak, ať nic nepřekrývá."
##
## His Y still follows the journey (he walks down from the station he came from), which is what
## keeps him reading as the player's position on the road; his X is the constant `HERO_X` column.
## That split is deliberate: the Y is state, the X is layout.
##
## Jan's "vizuální pohyb" is preserved — the same body sprite the arena uses, one character across
## both screens — and the walk is still an eased Y through `_process`.
func _hero_anchor() -> Vector2:
	var column := size.x * HERO_X
	var to := _current_fight() - 1
	if _walk_from < 0:
		return Vector2(column, node_pos(0).y + 26.0)
	if _walk_from == to:
		return Vector2(column, node_pos(to).y)
	return Vector2(column, lerpf(node_pos(_walk_from).y, node_pos(to).y, _walk_progress))


func _place_hero() -> void:
	if _hero == null:
		return
	var anchor := _hero_anchor()
	_hero.position = Vector2(anchor.x - HERO_SIZE * 0.5, anchor.y - HERO_SIZE + 14.0)


## The area's own art. There is NO stop-by-stop art for every act yet (`assets/stops/` covers acts
## 0 and 1), so the per-stop file is tried first and the act's placeholder second — and when
## neither exists the screen shows the drawn route on a flat field rather than nothing.
##
## ⚠️  The progress lookup goes through `_progress()` — see its note. An unguarded index here was
## what the crash probe found first, and the same defect sat in `_current_fight()` as well.
func _stop_art() -> Texture2D:
	var act := _act_id()
	var stop := _progress("locationProgress")
	var path := "assets/stops/stop_act%d_%d.webp" % [act, stop]
	var tex := UIKit.load_texture(path)
	if tex == null:
		tex = UIKit.load_texture("assets/stops/placeholder_act%d.png" % act)
	return tex
