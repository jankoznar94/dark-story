extends SceneTree
## tools/test_arena_screen.gd — the arena screen, driven headlessly.
##
## `battle.gd` owns every rule and `tools/test_player_spells.gd` already asserts them.
## What that test CANNOT see is the wiring between the two: whether the screen actually
## builds a button per learned spell, whether tapping it reaches the rules, and whether
## the mana bar the barbarian pays from is on screen at all.
##
## Those are exactly the failures that look like working features:
##   - a spell bar that is built but never clickable (buttons freed and recreated every
##     render tick, so the tap lands on a node that no longer exists),
##   - a bar built once and never refreshed, so a spell stays greyed out after its
##     cooldown has expired,
##   - the hero's mana bar hidden for a class that does use mana, which is what the port
##     used to do for the barbarian on a false belief about rage.
##
## Run:  godot --headless --path . --script res://tools/test_arena_screen.gd
## Pass: prints ARENA_SCREEN_ALL_PASS=true and exits 0.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const Battle := preload("res://scripts/combat/battle.gd")
const ArenaScreen := preload("res://scripts/ui/arena_screen.gd")
const TransitionScreen := preload("res://scripts/ui/transition_screen.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")

var _data: Node
var _gen: ItemGen
var _loot: LootSystem
var _failures: Array[String] = []


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_loot = LootSystem.new(_data, _gen)

	_test_barbarian_has_a_mana_bar()
	_test_spell_bar_builds_one_button_per_learned_spell()
	_test_cast_through_the_screen_changes_the_battle()
	_test_the_bar_refreshes_when_a_cooldown_expires()
	_test_buttons_survive_a_render_tick()
	_test_the_result_tiles_come_down_on_the_tap_clock()
	_test_backdrop_is_the_stop_being_fought()
	_test_reaction_buttons_reach_the_rules()
	_test_the_reaction_row_tracks_the_battle()
	_test_counter_and_block_are_offered_only_when_usable()
	_test_one_reaction_plays_one_sound()
	_test_the_flurry_row_replaces_the_reaction_row()

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("ARENA_SCREEN_ALL_PASS=true")
	else:
		print("ARENA_SCREEN_ALL_PASS=false")
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _resolve(state) -> Callable:
	return func(id):
		var item_id := str(id)
		if item_id == "":
			return {}
		var static_item: Dictionary = _data.item(item_id)
		if not static_item.is_empty():
			return static_item
		return state.loot_item(item_id)


func _hero(class_id: String = "barbarian", talents: Dictionary = {}, level: int = 20):
	var s = GameState.new()
	s.bind_data(_data)
	s.set_class(class_id)
	s.hero()["level"] = level
	s.hero()["mana"] = 60
	s.hero()["maxMana"] = 100
	s.hero()["attrStr"] = 40
	var levels := {}
	for key in talents:
		levels["%s_%s" % [class_id, key]] = int(talents[key])
	s.data["talentLevels"] = levels
	var sword: Dictionary = _data.item("blade_shortSword")
	if not sword.is_empty():
		s.equip()["weapon"] = "blade_shortSword"
	return s


## An arena built the way main.gd builds it, with a fight already running.
func _arena(state, hp: float = 100000.0) -> ArenaScreen:
	var screen: ArenaScreen = ArenaScreen.new(_data, _gen, _loot, state, _resolve(state))
	root.add_child(screen)
	# A SceneTree script's _initialize() runs before the first frame, so _ready() has
	# not fired for the freshly added node and the UI does not exist yet. Building it
	# here is what an actual frame would have done.
	if screen._mana_track == null:
		screen._build()
	# start() picks a real monster out of the act tables; the fight itself is not what
	# is under test here, so a high enough enemy HP keeps it alive across the ticks.
	if not screen.start(state, _resolve(state)):
		_fail("the arena could not start a fight")
		return screen
	screen.battle.enemy_hp = hp
	screen.battle.enemy_max_hp = hp
	screen.battle.hero_hp = 100000.0
	screen.battle.hero_max_hp = 100000.0
	return screen


## The spell buttons are the only thing on the row that is tappable, so count Buttons.
func _spell_buttons(screen: ArenaScreen) -> Array:
	var out: Array = []
	for child in screen._spell_row.get_children():
		if child is Button:
			out.append(child)
	return out


## The barbarian pays for his warcries out of MANA, exactly like the other two classes.
## The port used to hide his bar on the belief that he ran on rage, which hid the pool
## his own spells are billed against.
func _test_barbarian_has_a_mana_bar() -> void:
	var s = _hero("barbarian", {}, 20)
	var screen = _arena(s)
	if screen._mana_track == null or screen._mana_label == null:
		_fail("the arena has no mana bar nodes")
		return
	if not screen._mana_track.visible:
		_fail("the barbarian's mana bar is hidden")
	if not screen._mana_label.text.begins_with("Mana"):
		_fail("the mana label does not read as mana: '%s'" % screen._mana_label.text)
	# And it shows the hero's real pool, not a placeholder.
	var text: String = screen._mana_label.text
	if not text.contains("/ %d" % int(s.hero()["maxMana"])) and not text.contains("/ 1"):
		_fail("the mana label does not carry the pool: '%s'" % text)


## A spell is on the bar only once a talent point is in it — and then it is a real,
## enabled Button.
func _test_spell_bar_builds_one_button_per_learned_spell() -> void:
	var fresh = _hero("barbarian", {}, 20)
	var screen_fresh = _arena(fresh)
	if not _spell_buttons(screen_fresh).is_empty():
		_fail("a barbarian with no talents has spell buttons on the bar")

	var s = _hero("barbarian", {"heroicStrike": 1, "thunderClap": 1}, 20)
	var screen = _arena(s)
	var buttons := _spell_buttons(screen)
	if buttons.size() != 2:
		_fail("the bar built %d spell buttons, expected 2" % buttons.size())
		return
	var enabled := 0
	for b in buttons:
		if not (b as Button).disabled:
			enabled += 1
	if enabled != 2:
		_fail("%d of 2 fresh spells are disabled" % (2 - enabled))


## A tap has to reach the RULES. This is the wiring the spell test cannot see: the
## screen could build perfect buttons that do nothing at all.
func _test_cast_through_the_screen_changes_the_battle() -> void:
	var s = _hero("barbarian", {"heroicStrike": 1}, 20)
	var screen = _arena(s)
	var battle = screen.battle
	var mana_before: int = int(s.hero()["mana"])
	# The button's own callback is what a player's finger reaches.
	var result: Dictionary = screen.cast_spell("heroicStrike")
	if not bool(result["ok"]):
		_fail("casting heroicStrike through the screen failed: %s" % str(result["message"]))
		return
	if not battle.heroic_strike_queued:
		_fail("the cast through the screen did not queue the spell on the battle")
	if int(s.hero()["mana"]) >= mana_before:
		_fail("the cast through the screen spent no mana (%d -> %d)" % [mana_before, int(s.hero()["mana"])])
	# A refused cast must be refused, not silently accepted.
	var refused: Dictionary = screen.cast_spell("whirlwind")
	if bool(refused["ok"]):
		_fail("the screen accepted whirlwind, which is deliberately not ported")


## The bar is rebuilt when its contents change — a spell that comes off cooldown must
## become clickable again rather than staying greyed out forever.
func _test_the_bar_refreshes_when_a_cooldown_expires() -> void:
	var s = _hero("barbarian", {"thunderClap": 1}, 20)
	var screen = _arena(s)
	screen.cast_spell("thunderClap")
	if int(screen.battle.spell_cooldowns.get("thunderClap", 0)) <= 0:
		_fail("thunderClap set no cooldown through the screen")
		return
	screen.render()
	var blocked := 0
	for b in _spell_buttons(screen):
		if (b as Button).disabled:
			blocked += 1
	if blocked != 1:
		_fail("the spell on cooldown is not shown as blocked (%d disabled)" % blocked)
	# Tick the cooldown out (15 s) and render again: the button must come back.
	for _i in 200:
		screen.step()
	screen.render()
	var still_blocked := 0
	for b in _spell_buttons(screen):
		if (b as Button).disabled:
			still_blocked += 1
	if still_blocked != 0:
		_fail("the spell stayed blocked after its cooldown expired")


## render() runs ten times a second. If the bar were rebuilt every time, the node under
## the player's finger would be freed before the tap is delivered and the spell would
## never fire — so the buttons must SURVIVE a render.
func _test_buttons_survive_a_render_tick() -> void:
	var s = _hero("barbarian", {"heroicStrike": 1}, 20)
	var screen = _arena(s)
	screen.render()
	var buttons := _spell_buttons(screen)
	if buttons.is_empty():
		_fail("no spell buttons to check across a render tick")
		return
	var first: Button = buttons[0]
	screen.render()
	screen.render()
	var after := _spell_buttons(screen)
	if after.is_empty():
		_fail("the spell row was emptied by render()")
		return
	# Same instance, still alive: a freed button would not be identical to itself. The
	# `is_inside_tree()` check cannot be used here — a SceneTree test runs before the
	# loop starts, so no node reports being in the tree — but `is_queued_for_deletion()`
	# is exactly the failure mode: render() freeing the node under the player's finger.
	if after[0] != first:
		_fail("render() replaced the spell buttons instead of leaving them alone")
	if first.is_queued_for_deletion():
		_fail("render() queued the spell button for deletion")


## The end-of-fight tap guard must come down on the PLAYER's clock, and it must come down
## once the fight is over.
##
## Jan's report: "the Dalsi souboj button on the victory page sometimes does not work and I
## have to tap it repeatedly." The guard used to be decremented inside `step()`, i.e. once
## per 100 ms FIGHT tick — and `_process` only pumps ticks while the fight is LIVE, so after
## the kill the countdown depended on stray ticks from leftover accumulator time and a frame
## that delivered several spent the whole guard at once. A tap during those frames was lost.
##
## Two halves, because either one alone can be broken:
##   1. frames of REAL time bring the guard down (0.3 s of frames, not of fight time), and
##   2. the guard does NOT come down at all when only `step()` is called, which is what a
##      tick-only countdown did.
const FRAME := 1.0 / 60.0


func _test_the_result_tiles_come_down_on_the_tap_clock() -> void:
	var s = _hero("barbarian", {}, 20)
	var screen = _arena(s)
	screen.battle.enemy_hp = 0.0
	screen.battle.gap = 0.0
	var guard := 0
	while (not screen.battle.ended or not screen._result_built) and guard < 500:
		screen.step()
		guard += 1
	if not screen._result_built:
		_fail("the fight never settled, so the result page was never built")
		return
	if screen._button_lock_ms <= 0:
		_fail("the result page came up with no tap guard at all")
		return
	var locked_ms: int = screen._button_lock_ms
	# Half the guard in real frames: still locked. A tap here would be the lost one.
	var frames := int(round(float(locked_ms) / 2.0 / (FRAME * 1000.0)))
	for _i in frames:
		screen._process(FRAME)
	if screen._button_lock_ms <= 0:
		_fail("half of the tap guard (%d ms of frames) already came down" % locked_ms)
		return
	# The rest of it, and a little past: now a tap must land.
	for _i in frames + 4:
		screen._process(FRAME)
	if screen._button_lock_ms > 0:
		_fail("the tap guard was still up after %d ms of real frames" % locked_ms)
		return
	# And the guard must be spent by FRAMES, not by ticks: a page with the guard up that
	# only receives `step()` calls must stay locked, which is the bug in one line.
	var fresh = _arena(_hero("barbarian", {}, 20))
	fresh.battle.enemy_hp = 0.0
	fresh.battle.gap = 0.0
	guard = 0
	while (not fresh.battle.ended or not fresh._result_built) and guard < 500:
		fresh.step()
		guard += 1
	var before: int = fresh._button_lock_ms
	for _i in 6:
		fresh.step()
	if fresh._button_lock_ms != before:
		_fail("step() moved the tap guard: it is still counted in FIGHT ticks")


## The fight has to happen where the hero is standing, so the arena carries the STOP's own
## art behind it. Three things are asserted, and the third is the one that has bitten this
## project before: the art is the stop the BATTLE names (not the one the caller passed), the
## veil that keeps the HUD readable is present, and the backdrop sits UNDER the HUD in draw
## order — a backdrop added after the content is a backdrop nobody sees, which reads as
## "the background does not work" rather than as a z-order bug.
func _test_backdrop_is_the_stop_being_fought() -> void:
	var state = _new_state()
	var screen := _arena(state)
	var art: TextureRect = screen._hero_backdrop
	if art == null:
		_fail("the arena has no backdrop node at all")
		return

	# 1. The art is the one the battle's own act/zone resolves to.
	var act_id := int(screen.battle.act_id)
	var stop := int(screen.battle.progress)
	var want := TransitionScreen.stop_art_path(act_id, stop)
	if want == "":
		_fail("the stop the fight is in has no art path at all")
		return
	if art.texture == null:
		_fail("the backdrop has no texture - the stop art did not load")
		return
	# A wrong-but-loadable texture is the failure this catches: the placeholder is a valid
	# image, so "it loaded" is not evidence that it loaded the RIGHT place.
	var want_tex: Texture2D = load(want)
	if want_tex == null:
		_fail("the stop art at %s does not load" % want)
		return
	if art.texture.get_width() != want_tex.get_width() \
			or art.texture.get_size() != want_tex.get_size():
		_fail("the backdrop is not the stop's art (got %sx%s, want %sx%s)" % [
			art.texture.get_width(), art.texture.get_height(),
			want_tex.get_width(), want_tex.get_height()])
		return
	if art.stretch_mode != TextureRect.STRETCH_KEEP_ASPECT_COVERED:
		_fail("the backdrop must COVER: the art is square and the viewport is portrait")

	# 2. The veil exists, so the HUD is not drawn straight onto a mid-tone painting.
	var holder: Control = art.get_parent()
	if holder == null:
		_fail("the backdrop has no holder")
		return
	var veil := holder.get_node_or_null("BackdropVeil")
	if veil == null:
		_fail("the backdrop has no veil - dark labels on a painting are unreadable")
		return
	if not veil.draw.is_connected(screen._draw_backdrop_veil):
		_fail("the veil never connects its draw - it would be an invisible node")

	# 3. DRAW ORDER. The HUD is added after the backdrop, so the backdrop must come first
	#    among the screen's own children or it paints over the fight.
	var holder_index := holder.get_index()
	for child in screen.get_children():
		if child == holder:
			continue
		# Non-Control children (the sfx player) do not paint anything.
		if child is Control and child.get_index() < holder_index:
			_fail("a Control (%s) is added BEFORE the backdrop - it would be painted under it"
				% child.name)
			return
	if holder_index != 0:
		_fail("the backdrop is not the first child (index %d)" % holder_index)


func _new_state():
	# Built the way the other arena tests build it: bind the data, pick a class, then let
	# `battle.setup()` read the real act/zone off the save.
	var st = GameState.new()
	st.bind_data(_data)
	st.set_class("barbarian")
	return st


## The reaction buttons are the only thing about this feature a player can see, and every
## way they can be wrong is silent from a rules test: a row built but never shown, a
## button wired to nothing, a press that never reaches the battle.
##
## ⚠️  The press is driven through the BUTTON's own `pressed` signal, not by calling the
## screen's handler. A call to `on_reaction_button` passes against a button wired to
## nothing at all — that is exactly the failure this test exists for, and it is the same
## mistake the portal button made (see the port skill's "a button whose `visible` is set
## once in `_build()`").
func _test_reaction_buttons_reach_the_rules() -> void:
	var s = _hero("barbarian", {}, 20)
	var screen = _arena(s)
	var battle = screen.battle
	# Force a window of a KNOWN kind: the roll is `test_reactions`' business, this is about
	# the wiring.
	battle.opp_type = "dodge"
	battle.opp_resolved = false
	battle.opp_failed = false
	screen._refresh_reaction_layer(0.016)
	if not screen._reaction_row.visible:
		_fail("an open window did not show the reaction row")
		return
	var button: Button = screen._reaction_buttons["dodge"]
	if button == null:
		_fail("the reaction row has no dodge button")
		return
	button.pressed.emit()
	if not battle.opp_resolved:
		_fail("pressing Dodge through its own signal did not reach the battle")
	# ...and the row goes away once the window is settled, or the player keeps tapping a
	# window that no longer exists.
	battle.resolve_opportunity(s)
	screen._refresh_reaction_layer(0.016)
	if screen._reaction_row.visible:
		_fail("the reaction row stayed up after the window was settled")


## The row is driven from the BATTLE's state, so there is exactly one place that can
## disagree — and this asserts the direction of that dependency: the screen must follow
## the battle, never track a window of its own.
func _test_the_reaction_row_tracks_the_battle() -> void:
	var s = _hero("barbarian", {}, 20)
	var screen = _arena(s)
	var battle = screen.battle
	battle.opp_type = ""
	screen._refresh_reaction_layer(0.016)
	if screen._reaction_row.visible:
		_fail("the reaction row is up with no window open")
	# The middle icon names the press, and for a window with no deadline it must NOT carry
	# the flurry's countdown ring — that ring belongs to a strike's deadline only.
	battle.opp_type = "dodge"
	screen._refresh_reaction_layer(0.016)
	if not screen._action_icon.visible:
		_fail("the middle icon is hidden while a window is open")
	if screen._action_ring.visible:
		_fail("the countdown ring is up for a window that has no deadline")
	# ⚠️  And the correct BUTTON is never highlighted. Jan's rule: a highlighted button
	# turns the reaction into "press the one that lights up", which is not a reaction.
	for kind in screen._reaction_buttons:
		var b: Button = screen._reaction_buttons[kind]
		for state_name in ["normal", "hover", "pressed", "focus"]:
			var style = b.get_theme_stylebox(state_name)
			if style is StyleBoxFlat and style.border_color == Color("#ffffff"):
				_fail("the %s button is highlighted white - the answer must not be shown" % kind)


## Block and Counter are offered only to a hero who can USE them (the PWA's
## `updateDefBtnsVisibility`): dodge always, block only with a shield, counter only once
## the talent is invested. A button that would always be wrong is not a choice.
func _test_counter_and_block_are_offered_only_when_usable() -> void:
	# A shield-less barbarian with no counter: dodge only.
	var s = _hero("barbarian", {}, 20)
	s.equip()["shield"] = ""
	var screen = _arena(s)
	screen.battle.opp_type = "dodge"
	screen._refresh_reaction_layer(0.016)
	if (screen._reaction_buttons["block"] as Button).visible:
		_fail("Block is offered to a hero with no shield")
	if (screen._reaction_buttons["counter"] as Button).visible:
		_fail("Counter is offered to a hero who never bought the talent")
	if not (screen._reaction_buttons["dodge"] as Button).visible:
		_fail("Dodge is hidden - it is the one reaction every hero has")

	# Invested counter and a shield on: both appear. A REAL shield from the item table,
	# because the gate reads the item's own type and a made-up id would have none.
	var s2 = _hero("barbarian", {"counterAttack": 1}, 20)
	s2.equip()["shield"] = "shield_buckler"
	var screen2 = _arena(s2)
	screen2.battle.opp_type = "dodge"
	screen2._refresh_reaction_layer(0.016)
	if not (screen2._reaction_buttons["block"] as Button).visible:
		_fail("Block is hidden from a hero wearing a shield")
	if not (screen2._reaction_buttons["counter"] as Button).visible:
		_fail("Counter is hidden from a hero who invested in it")


## ONE cue per resolved reaction window, counted at the MIXER — the press and the swing's
## resolution together.
##
## ⚠️  This is a regression test. `arena_screen.on_reaction_button` played the cue on the
## correct press as well, reading the PWA's `showOpportunitySuccess` as if it made a sound:
## it does not. The PWA plays the cue inside `resolveOpportunity`, once, when the swing is
## settled (measured: an answered dodge put the press's cue into the battle's queue and then
## the same cue again out of `enemy_attack`).
##
## ⚠️  AND THE CUE REALLY IS RAISED BY THE SWING'S RESOLUTION, not by `resolve_opportunity`
## itself — the battle plays it in `enemy_attack`, in the branch that reads `opp_last_kind`.
## So the swing has to be DRIVEN here; calling `resolve_opportunity` alone consumes the
## window and then leaves `enemy_attack` to land a plain hit, which is why an earlier version
## of this check read "0 sounds" against a port that was already correct.
##
## The count is taken on `Sfx.played_count`, not on `battle.take_sfx_cues()`, because the
## screen's stray copy never entered the battle's queue at all — a rules-level check is blind
## to it. The battle half is pinned in `test_sfx`; this half is the WIRING.
func _test_one_reaction_plays_one_sound() -> void:
	var s = _hero("barbarian", {}, 20)
	var screen = _arena(s)
	var battle = screen.battle
	# The mixer only exists once the screen is in the tree — `_ready()` builds it, and a
	# `_build()`-only rig has none. Build it the way a real frame would.
	if screen._sfx == null:
		screen._sfx = Sfx.new()
		screen.add_child(screen._sfx)
	screen._sfx.played_count = 0
	battle.opp_type = "dodge"
	battle.opp_resolved = false
	battle.opp_failed = false
	screen._refresh_reaction_layer(0.016)
	(screen._reaction_buttons["dodge"] as Button).pressed.emit()
	if not battle.opp_resolved:
		_fail("the press did not reach the battle")
		return
	# ⚠️  THE PRESS IS SILENT. This is the half the regression lived in: restoring the
	# screen's own `_play()` on the correct press turns this red and nothing else.
	if screen._sfx.played_count != 0:
		_fail("the reaction PRESS played %d sounds; the PWA's press is a tick-mark only"
			% screen._sfx.played_count)
	# ...and the swing's resolution plays it exactly once, through the real path.
	battle.hero_hp = 100000.0
	battle.hero_max_hp = 100000.0
	var settle: Dictionary = battle.enemy_attack(s, screen._find_item)
	if str(settle.get("reason", "")) != "opportunity":
		_fail("test setup: the answered window did not settle as an avoided blow (%s)"
			% str(settle))
		return
	screen._play_cues()
	if screen._sfx.played_count != 1:
		_fail("one answered reaction played %d sounds, expected 1" % screen._sfx.played_count)


## The flurry row replaces the reaction row — and the strike's press goes through the PS
## button's own signal, the same "a call to the handler passes against a button wired to
## nothing" rule the reaction row is checked with.
func _test_the_flurry_row_replaces_the_reaction_row() -> void:
	var s = _hero("barbarian", {"whirlwind": 1, "oneHandSpec": 1}, 20)
	var screen = _arena(s)
	var battle = screen.battle
	# An open window AND a flurry is the state the rules forbid; prove the screen resolves
	# it in the flurry's favour rather than drawing both.
	battle.opp_type = "dodge"
	battle.start_whirlwind(["tri", "circle", "cross"], 1500)
	screen._refresh_reaction_layer(0.016)
	if screen._reaction_row.visible:
		_fail("the reaction row is up during a flurry - the two share one strip")
	if not screen._combo_row.visible:
		_fail("the flurry's PS row is not shown")
	if not screen._action_icon.visible:
		_fail("the flurry shows no middle icon - the player cannot know what to press")
	if not screen._action_ring.visible:
		_fail("the flurry's countdown ring is missing - the deadline is the whole pressure")

	# The strike's own press goes through the PS button's signal, same rule as above.
	var prompt: String = battle.whirlwind_prompt()
	var button: Button = screen._combo_buttons[prompt]
	if button == null:
		_fail("there is no PS button for the prompted key '%s'" % prompt)
		return
	var landed_before: int = battle.ww_landed
	button.pressed.emit()
	if battle.ww_landed == landed_before:
		_fail("pressing the prompted PS button did not land a strike")

	# After the flurry, the reaction row is free again.
	battle.ww_active = false
	battle.opp_type = ""
	screen._refresh_reaction_layer(0.016)
	if screen._combo_row.visible:
		_fail("the PS row stayed up after the flurry ended")
	if screen._action_icon.visible or screen._action_ring.visible:
		_fail("the middle icon stayed up after the flurry ended")
