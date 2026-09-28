extends SceneTree
## tools/test_juice.gd — the FEEL layer: the decision half of haptics, the shake, the hit-stop
## and the two presses.
##
## Same split as `test_sfx.gd`, and for the same reason: a headless run has no motor, no
## compositor and no user, so what is assertable is the DECISION layer — which event asked for
## a crit buzz, whether a MISS ever thumps, whether a residue is left on a scale or a position
## after an effect is over. Every bug in this kind of system lives there; the vibration itself
## is not testable and is not pretended to be.
##
## What this gate is here to catch, one by one:
##
##   1. A HIT-STOP THAT LEAVES `Engine.time_scale` SCALED. The node is the only writer of a
##      GLOBAL, and a release path that misses restores it for the rest of the process — the
##      whole game runs at 5 % speed and nothing says why.
##   2. AN EFFECT THAT THUMPS ON A MISS. `is_player_blow()` is a "did the monster attack" test,
##      so MISS and BLOCK pass through it with `amount == 0`. Shaking the screen for a miss
##      tells the player he landed one, which is the single thing this combat must not lie
##      about.
##   3. A RESIDUE. The screen shake writes `position` on a full-rect screen and the HP ring
##      swells `scale`; both are also written by the layout code, so a value left behind is a
##      permanently off-centre screen or a permanently 6 %-oversized ring.
##   4. A SWING THAT NEVER GETS ITS BUZZ. The screen only reacts on a `_drain_log()` entry, and
##      `render()` returns early once `battle.ended` — a killing blow would land silently.
##
## Run:  godot --headless --path . --script res://tools/test_juice.gd
## Pass: prints JUICE_ALL_PASS=true

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const LootSystem := preload("res://scripts/items/loot_system.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const Battle := preload("res://scripts/combat/battle.gd")
const ArenaScreen := preload("res://scripts/ui/arena_screen.gd")
const Juice := preload("res://scripts/ui/juice.gd")
const HitStop := preload("res://scripts/ui/hit_stop.gd")

var _failures: Array[String] = []
var _data: Node
var _gen: ItemGen
var _loot: LootSystem
var _state: GameState
var _juice: Juice
var _hit_stop: HitStop
var _arena: ArenaScreen
## Nodes the tween sections animate. They have to live on the tree ACROSS frames — a tween is
## stepped by the tree's own `process_frame`, and `custom_step()` cannot stand in for that.
var _press_button: Button
var _enter_screen: Control
var _frames := 0
## Wall time when the two tween sections started. They are asserted on a CLOCK, not on a frame
## count: a headless run has no vsync, so "the tenth frame" is a few milliseconds and the 110 ms
## tween would be measured half-finished (it was: 0.94 / alpha 0.0).
var _sections_started_ms := 0
## The LOWEST scale the press reached, and the lowest alpha the enter screen reached. Sampled
## every frame instead of at one chosen instant, because a frame in a headless run is ~50 ms and
## a 60 ms animation has no reliable window to land in — an instant sample measures the
## scheduler, not the effect. The minimum over the whole run is what "the tap did something
## visible" actually means, and it is strictly harder to pass.
var _min_press_scale := 1.0
var _min_enter_alpha := 1.0


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)
	_loot = LootSystem.new(_data, _gen)

	# ⚠️  A `SceneTree` script's `_initialize()` runs BEFORE the first frame, so `_ready()` has
	# not fired on either node and their `instance` static is still null. `Juice.press()` /
	# `HitStop.freeze()` are static entry points that no-op when `instance` is null — which is the
	# property that makes them safe in a game that never built them, and the reason every
	# press/enter section here failed with "no meta value 'juice_press_tween'" until the two
	# statics were assigned by hand. Do it here rather than in `_ready()`, or the whole file
	# measures a game that does not exist yet.
	_juice = Juice.new()
	_juice.name = "Juice"
	root.add_child(_juice)
	Juice.instance = _juice
	_hit_stop = HitStop.new()
	_hit_stop.name = "HitStop"
	root.add_child(_hit_stop)
	HitStop.instance = _hit_stop

	# ⚠️  `GameState` is a `RefCounted`, NOT a Node — `add_child` on it is a parse error, and
	# it takes the whole file down. Its `bind_data()` is what gives it the tables; a `new()`
	# with no `set_class` leaves `heroClass` empty and the fight never starts.
	#
	# A fresh `GameState` writes a save. The suite gives every test its own `XDG_DATA_HOME`
	# exactly so that cannot delete the loadout a parity probe is measuring — see the note in
	# `run_all_tests.sh`. Do not point this at the measurement tree.
	_state = _hero()

	_test_the_buzz_table()
	_test_the_gap_swallows_a_second_buzz()
	_test_a_platform_call_is_reachable()
	_test_a_miss_never_thumps()
	_test_a_crit_is_the_bigger_one()
	_test_the_hit_stop_releases_time_scale()
	_test_a_second_freeze_is_dropped_not_queued()
	_test_the_screen_shake_leaves_no_residue()
	_test_a_button_factory_wires_the_press_once()
	# The two TWEEN sections are not run here: a tween is advanced by the tree, which needs
	# frames, and `_initialize()` runs before the first one. They start a node below and are
	# asserted in `_process`, then the verdict is printed once.
	# ⚠️  THE TWEEN SECTIONS RUN IN A CLEAN CLOCK, and this line is why they exist at all.
	# `HitStop` scales `Engine.time_scale`, which scales `SceneTree.delta` — so a freeze left
	# running by an earlier section makes every tween here advance at 5 % speed. Measured: the
	# 60 ms press reported `scale == 1.000000` after 400 ms of wall time, i.e. it had run barely
	# 20 ms of its own life, and the failure read as "the press never shrinks". The hit-stop
	# sections release their own freeze; this is the belt-and-braces line for the whole run.
	Engine.time_scale = 1.0
	_sections_started_ms = Time.get_ticks_msec()
	_start_the_press_section()
	_start_the_enter_section()


## Run the whole press/enter verification, then report.
##
## ⚠️  `_initialize()` cannot do this. A `Tween` created by `Control.create_tween()` is bound to
## the node and advanced by the SceneTree's own frame processing — and a `SceneTree` script's
## `_initialize()` runs BEFORE the first frame. `custom_step()` looked like the way round it and
## is not: calling it in the same breath measured the control at 0.94 / alpha 0.0, i.e. the
## tween had not started.
##
## ⚠️  And the assertions are on a WALL CLOCK, not on a frame count. A headless run has no vsync,
## so frames come at a few hundred a second: "check on frame 1" measured a 110 ms tween 3 ms in
## and reported it as never settling. Wait out the longest animation (60 + 60 ms press, 110 ms
## enter) with margin.
const SETTLE_MS := 400


func _process(_delta: float) -> bool:
	_frames += 1
	var elapsed := Time.get_ticks_msec() - _sections_started_ms
	# Sample every frame; the assertions read the extremes at the end.
	if _press_button != null and is_instance_valid(_press_button):
		_min_press_scale = minf(_min_press_scale, _press_button.scale.x)
	if _enter_screen != null and is_instance_valid(_enter_screen):
		_min_enter_alpha = minf(_min_enter_alpha, _enter_screen.modulate.a)
	if elapsed >= SETTLE_MS:
		_check_the_extremes()
		_finish_the_press_section()
		_finish_the_enter_section()
		print("JUICE_ALL_PASS=%s" % ("true" if _failures.is_empty() else "false"))
		for f in _failures:
			print("  FAIL: %s" % f)
		quit()
		return true
	return false


## Both animations were actually SEEN mid-flight. The extremes are the evidence: the press's
## lowest scale and the enter screen's lowest alpha over the whole run.
##
## ⚠️  Not an instant sample. The first version checked a single chosen moment and reported
## `scale == 1.000000` — a frame here is ~50 ms, so the 60 ms release had no dependable window and
## the sample measured the scheduler rather than the effect. An extreme over every frame cannot
## miss it, and it is a STRONGER assertion: it fails if the animation never happened at all.
func _check_the_extremes() -> void:
	# A scaled clock is the one way the extremes can lie, so it is asserted rather than assumed.
	_check(is_equal_approx(Engine.time_scale, 1.0),
		"the tween sections must run at time_scale 1.0 (found %f)" % Engine.time_scale)
	_check(_min_press_scale < 1.0,
		"a press must shrink the control at some point (lowest seen %f)" % _min_press_scale)
	_check(_min_enter_alpha < 1.0,
		"an enter must fade the screen in at some point (lowest alpha seen %f)" % _min_enter_alpha)
	_check(_frames > 0, "the tween sections never ran a frame")

	_check(is_equal_approx(Engine.time_scale, 1.0),
		"the tween sections must run at time_scale 1.0 (found %f)" % Engine.time_scale)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)


## Make the buzz gap consider itself over, so the next `vibrate` reaches the decision instead of
## being swallowed. The gap is measured between PLATFORM calls, so this only moves a timestamp.
func _clear_gap() -> void:
	_juice._last_haptic_at = Time.get_ticks_msec() - Juice.HAPTIC_MIN_GAP_MS - 1


# ============================================================== haptics (the decision layer)

## The four named durations are the whole vocabulary of the buzz, and a call site picks one by
## NAME. Assert the mapping, because "the crit feels the same as a normal hit" is a wiring bug
## that no other test can see.
func _test_the_buzz_table() -> void:
	# ⚠️  Clear the gap first. Two buzzes inside `HAPTIC_MIN_GAP_MS` are DROPPED by design, and a
	# test that ignores that measures its own back-to-back calls rather than the table — this
	# section failed with "a hit buzz must report 18 ms, got 30" until the gap was respected.
	_clear_gap()
	_juice.vibrate(Juice.HAPTIC_CRIT_MS)
	_check(_juice.last_haptic_ms == Juice.HAPTIC_CRIT_MS,
		"a crit buzz must report %d ms, got %d" % [Juice.HAPTIC_CRIT_MS, _juice.last_haptic_ms])
	var before := _juice.haptic_count
	_clear_gap()
	Juice.haptic_hit()
	_check(_juice.haptic_count == before + 1, "a hit buzz must increment the counter")
	_check(_juice.last_haptic_ms == Juice.HAPTIC_HIT_MS,
		"a hit buzz must report %d ms, got %d" % [Juice.HAPTIC_HIT_MS, _juice.last_haptic_ms])
	# The ORDER is the design: a tap is the shortest thing the motor can do, a level-up the
	# longest. A table where the tap out-buzzes the blow is not a table, it is a typo.
	_check(Juice.HAPTIC_TAP_MS < Juice.HAPTIC_HIT_MS
		and Juice.HAPTIC_HIT_MS < Juice.HAPTIC_CRIT_MS
		and Juice.HAPTIC_CRIT_MS < Juice.HAPTIC_LEVEL_MS,
		"the buzz durations must ascend tap < hit < crit < level")


## Two rules can land in one 100 ms tick (Double Swing). The second buzz inside the gap is
## DROPPED — but it still has to be COUNTED, or "this event wanted a buzz" becomes unassertable
## from outside.
func _test_the_gap_swallows_a_second_buzz() -> void:
	# Reset the gap by pretending no buzz has happened for a while.
	_juice._last_haptic_at = Time.get_ticks_msec() - Juice.HAPTIC_MIN_GAP_MS - 1
	_juice.vibrate(Juice.HAPTIC_HIT_MS)
	var first_at := _juice._last_haptic_at
	var count_after_first := _juice.haptic_count
	_juice.vibrate(Juice.HAPTIC_HIT_MS)
	_check(_juice._last_haptic_at == first_at,
		"a second buzz inside the gap must not reach the platform")
	_check(_juice.haptic_count == count_after_first + 1,
		"a dropped buzz must still be COUNTED, or the decision is unobservable")


## `Input.vibrate_handheld` has to be a real method on this engine, because the whole haptic
## layer is one call through it and a `ClassDB` guard that silently fails would look identical
## to a phone with no motor.
func _test_a_platform_call_is_reachable() -> void:
	_check(ClassDB.class_has_method("Input", "vibrate_handheld", true),
		"Input.vibrate_handheld must exist in this engine build")
	# The real call must not crash on a desktop with no motor — that is the path every
	# non-Android run takes, CI included.
	_juice._last_haptic_at = Time.get_ticks_msec() - Juice.HAPTIC_MIN_GAP_MS - 1
	_juice.vibrate(Juice.HAPTIC_HIT_MS)
	_check(true, "unreachable")


# ============================================================== what a blow does to the frame

## The hero, built the way `test_arena_screen` builds one — the arena needs a real class and a
## resolved weapon or `start()` refuses.
func _hero() -> GameState:
	var s: GameState = GameState.new()
	s.bind_data(_data)
	s.set_class("barbarian")
	s.hero()["level"] = 20
	var sword: Dictionary = _data.item("blade_shortSword")
	if not sword.is_empty():
		s.equip()["weapon"] = "blade_shortSword"
	return s


func _resolve(state) -> Callable:
	return func(id):
		var item_id := str(id)
		if item_id == "":
			return {}
		var static_item: Dictionary = _data.item(item_id)
		if not static_item.is_empty():
			return static_item
		return state.loot_item(item_id)


## Build a real battle and drive the arena's own entry point for a log entry — never a
## hand-written copy of its logic, because the exclusion of MISS/BLOCK lives in the screen and
## a test that re-implemented it would pass on the broken build.
##
## ⚠️  `ArenaScreen.new()` takes five arguments. `test_arena_screen` had to build the screen by
## hand (`screen._build()`) because a `SceneTree` script's `_initialize()` runs before the first
## frame and `_ready()` has not fired — do the same or the UI does not exist when `start()` runs.
func _enter_arena() -> bool:
	_arena = ArenaScreen.new(_data, _gen, _loot, _state, _resolve(_state))
	root.add_child(_arena)
	if _arena._mana_track == null:
		_arena._build()
	if not _arena.start(_state, _resolve(_state)):
		return false
	# A high enough enemy HP keeps the fight ALIVE across the log entries this test feeds in —
	# `render()` returns early once `battle.ended`, and a dead enemy would make every later
	# `_drain_log` section silently unmeasured.
	_arena.battle.enemy_hp = 100000.0
	_arena.battle.enemy_max_hp = 100000.0
	return true


## Clear the per-frame reactions AND any freeze a previous section left running.
##
## ⚠️  `HitStop` writes a GLOBAL, so a section that fed a blow and moved on leaves `time_scale`
## at 0.05 for everything after it — the next section's freeze request is then DROPPED (one is
## already active), and the hit-stop assertions measured a scale of 0.05 as "did not scale".
## The freeze is released here the way `_process` releases it.
func _reset_reactions() -> void:
	_arena._impact = 0.0
	_arena._hp_ring_flash = 0.0
	_arena._hero_flinch = 0.0
	_arena._hero_flash = 0.0
	_release_any_freeze()


func _release_any_freeze() -> void:
	if not _hit_stop.is_active():
		return
	_hit_stop._until_ms = Time.get_ticks_msec() - 1
	_hit_stop._process(0.016)


## ⚠️  WHICH SIDE AN ENTRY DESCRIBES, and it is the opposite of what the field name suggests.
## Measured against `battle.gd`'s own `_note` call sites: the HERO's swing is
## `_note("HIT", dmg, false)` (a `false`), and a blow the hero TOOK is `_note("ENEMY HIT", dmg,
## true)` (a `true`). So `on_player` answers "is this entry about the player", not "did the
## player land it" — and `not on_player` is the HERO'S OWN ATTACK.
##
## This naming is the trap the whole file exists to pin down: read it the other way and every
## reaction in the screen fires on the wrong side.
const HERO_ATTACK := false
const HERO_WAS_HIT := true


## Drive the screen's own log-drain with one entry. `_drain_log` reads `battle.log` and clears
## it, so the entry goes in there.
func _feed(kind: String, amount: int, on_player: bool) -> void:
	_arena.battle.log.append({"kind": kind, "amount": amount, "onPlayer": on_player})
	_arena._drain_log()


func _test_a_miss_never_thumps() -> void:
	if not _enter_arena():
		_failures.append("the arena would not start a fight")
		return
	# ⚠️  THE case this gate exists for. `is_player_blow("MISS", 0, false)` is TRUE — it is a
	# "did the monster attack" test — so a screen that only asked that question would shake and
	# buzz on a miss.
	# `is_player_blow` answers "did the monster act against the hero". MISS/BLOCK carry
	# `onPlayer: false` (they are the hero's OWN swing, see the note above), so they never reach
	# it — and an `ENEMY <status>` entry with no damage does. That pair is exactly why the screen
	# needs BOTH the kind guard and the `amount > 0` guard.
	_check(not ArenaScreen.is_player_blow("MISS", 0, HERO_ATTACK),
		"a MISS is the hero's own swing and must not read as a monster blow")
	_check(ArenaScreen.is_player_blow("ENEMY SLOW", 0, HERO_WAS_HIT),
		"a monster status entry DOES pass is_player_blow — which is why amount > 0 is required")
	# The hero's OWN swing, which whiffs. `HIT` is asserted separately below as the control case,
	# because "MISS does not thump" means nothing unless "HIT does".
	for kind in ["MISS", "BLOCK"]:
		_reset_reactions()
		_feed(kind, 0, HERO_ATTACK)
		_check(_arena._impact == 0.0,
			"a %s must not thump the screen (impact=%f)" % [kind, _arena._impact])
		_check(_arena._hp_ring_flash == 0.0,
			"a %s must not flash the HP ring" % kind)
		# But the hero DOES react to the swing itself, and that half must not have been
		# removed along with the thump.
		_check(_arena._hero_flinch > 0.0,
			"a %s must still make the hero flinch — only the THUMP is excluded" % kind)
	# A monster's zero-damage STATUS entry is `onPlayer: true` and passes `is_player_blow`, so a
	# screen that gated only on that predicate would shake the frame because it slowed the hero.
	for kind in ["ENEMY SLOW", "ENEMY FAERIE FIRE", "ENEMY EVASION"]:
		_reset_reactions()
		_feed(kind, 0, HERO_WAS_HIT)
		_check(_arena._impact == 0.0,
			"a zero-damage %s must not thump the screen (impact=%f)" % [kind, _arena._impact])


func _test_a_crit_is_the_bigger_one() -> void:
	if _arena == null or _arena.battle == null:
		return
	# The CONTROL case for the MISS assertions above: the same hero, the same field, a landed
	# blow. Without this pair, "a MISS does not thump" would also pass on a screen that never
	# thumps at all.
	_reset_reactions()
	_feed("HIT", 12, HERO_ATTACK)
	_check(_arena._impact > 0.0, "a landed HIT must thump the screen")
	var normal_impact := _arena._impact
	_reset_reactions()
	_feed("CRIT", 40, HERO_ATTACK)
	_check(_arena._hp_ring_flash > 0.0, "a CRIT must flash the HP ring")
	_check(_arena._impact > 0.0, "a CRIT must thump the screen")
	# A crit lands the same shake but asks for the LONGER freeze — the shake itself is
	# deliberately not differentiated, and this asserts that on purpose so a later "make the crit
	# bigger" change lands here with a reason rather than silently.
	_check(is_equal_approx(_arena._impact, normal_impact),
		"the shake amplitude is deliberately the same for a hit and a crit (%f vs %f)"
		% [_arena._impact, normal_impact])

	# The off-hand suffix is part of the SAME swing and must read the same way.
	_reset_reactions()
	_feed("CRIT offhand", 20, HERO_ATTACK)
	_check(_arena._impact > 0.0, "an off-hand CRIT must thump the screen too")

	# And the monster's own blow on the hero — the other side of the same branch.
	_reset_reactions()
	_feed("ENEMY HIT", 9, HERO_WAS_HIT)
	_check(_arena._impact > 0.0, "a blow the HERO took must thump the screen")
	_check(_arena._hero_flash > 0.0, "a blow the hero took must wash the hero red")


# ============================================================== the hit-stop

## ⚠️  THE assert this file exists for. `Engine.time_scale` is GLOBAL and process-wide: a
## release path that never runs leaves the whole game at 5 % speed with nothing on screen
## saying why, and every later test in the same process would inherit it.
func _test_the_hit_stop_releases_time_scale() -> void:
	_release_any_freeze()
	var before := Engine.time_scale
	_hit_stop.hit(HitStop.HIT_MS)
	_check(_hit_stop.is_active(), "a hit-stop request must put the node into the freezing state")
	_check(Engine.time_scale < before,
		"the freeze must actually scale Engine.time_scale (found %f)" % Engine.time_scale)
	# Release it the way `_process` does, without waiting for the wall clock.
	_hit_stop._until_ms = Time.get_ticks_msec() - 1
	_hit_stop._process(0.016)
	_check(not _hit_stop.is_active(), "the freeze must end when its clock expires")
	_check(is_equal_approx(Engine.time_scale, before),
		"the freeze MUST restore Engine.time_scale (expected %f, got %f)" % [before, Engine.time_scale])


func _test_a_second_freeze_is_dropped_not_queued() -> void:
	_release_any_freeze()
	var requested := _hit_stop.requested_count
	var started := _hit_stop.started_count
	_hit_stop.hit(HitStop.HIT_MS)
	_hit_stop.hit(HitStop.HIT_MS)
	_check(_hit_stop.requested_count == requested + 2,
		"both requests must be counted")
	_check(_hit_stop.started_count == started + 1,
		"the second freeze inside a running one must be DROPPED, not queued — two blows in one "
		+ "tick would otherwise freeze the fight for twice as long")
	_hit_stop._until_ms = Time.get_ticks_msec() - 1
	_hit_stop._process(0.016)


# ============================================================== residues

## The screen's own position and the HP ring's scale are written by the layout code too. A
## residue left by an effect is permanent and is exactly the shape of defect that survives a
## frame-by-frame look.
func _test_the_screen_shake_leaves_no_residue() -> void:
	if _arena == null:
		return
	_arena._impact = 1.0
	_arena._apply_impact_shake()
	_check(_arena.position != Vector2.ZERO, "a full impact must actually displace the screen")
	_arena._impact = 0.0
	_arena._apply_impact_shake()
	_check(_arena.position == Vector2.ZERO,
		"the shake MUST restore the screen position to zero (found %s)" % _arena.position)


## A tap must shove the control and then PUT IT BACK. The return is the half that matters: Jan's
## rule is that a phone has no hover, so a control shows state only while it is pressed, and a
## control that shrank and stayed small is exactly the sticky state the rule forbids.
func _start_the_press_section() -> void:
	_press_button = Button.new()
	_press_button.custom_minimum_size = Vector2(80, 40)
	_press_button.size = Vector2(80, 40)
	root.add_child(_press_button)
	Juice.press(_press_button)
	# The pivot has to be the middle, or the shrink reads as the control MOVING rather than as
	# being pushed. It is set synchronously, so this half IS assertable here; the shrink itself
	# is checked mid-flight by `_check_mid_flight`, because at this instant the tween has not
	# run yet.
	_check(_press_button.pivot_offset == _press_button.size * 0.5,
		"the press pivot must be the control's centre")


func _finish_the_press_section() -> void:
	if _press_button == null:
		_failures.append("the press section never started")
		return
	# By now the tree has run frames, so the 60 + 60 ms tween has had time to finish.
	_check(is_equal_approx(_press_button.scale.x, 1.0),
		"the press MUST return to 1.0 — a control that stayed small is the sticky state the "
		+ "design forbids (found %f)" % _press_button.scale.x)
	# And a second press must not stack: two tweens over one `scale` end wherever the loser left it.
	Juice.press(_press_button)
	Juice.press(_press_button)
	_check(_press_button.has_meta("juice_press_tween")
		and _press_button.get_meta("juice_press_tween") != null,
		"a repeated press must leave exactly one live tween")


## A screen coming up settles from 94 % and faded, to full size and opaque, over 110 ms.
func _start_the_enter_section() -> void:
	_enter_screen = Control.new()
	_enter_screen.size = Vector2(390, 844)
	root.add_child(_enter_screen)
	Juice.enter(_enter_screen)
	# The starting values are written synchronously — this is the one half of the animation that
	# IS observable in the same breath as the call, and it is what proves the tween was armed at
	# 0.94 / alpha 0 rather than at full size and opaque.
	_check(_enter_screen.scale.x < 1.0,
		"an enter must start the screen below full size (found %f)" % _enter_screen.scale.x)
	_check(_enter_screen.modulate.a < 1.0,
		"an enter must start the screen faded in (found %f)" % _enter_screen.modulate.a)


func _finish_the_enter_section() -> void:
	if _enter_screen == null:
		_failures.append("the enter section never started")
		return
	_check(is_equal_approx(_enter_screen.scale.x, 1.0)
		and is_equal_approx(_enter_screen.modulate.a, 1.0),
		"an enter must settle at scale 1.0 and alpha 1.0 (got %f / %f)"
		% [_enter_screen.scale.x, _enter_screen.modulate.a])
	# `reset()` is what `show_screen` calls on the way OUT of a screen, and the modal and the
	# inventory are REUSED — a residue left on their scale shows as a permanently 94 % window.
	Juice.reset(_enter_screen)
	_check(_enter_screen.scale == Vector2.ONE and _enter_screen.modulate == Color.WHITE,
		"reset must restore scale and modulate")


## The factory that every screen's buttons come out of. A button wired TWICE runs `_press`
## twice, the second call killing the first's tween, and the shove reads as half-length.
func _test_a_button_factory_wires_the_press_once() -> void:
	var UIKit := load("res://scripts/ui/ui_kit.gd")
	var b: Button = UIKit.flat_button("Test", 100.0, 40.0)
	_check(b.has_meta("juice_press_wired"), "a UIKit button must be wired for the press")
	UIKit.flat_button("Test", 100.0, 40.0)
	Juice.press_on(b)
	var connections := b.pressed.get_connections().size()
	_check(connections == 1,
		"a button passed through the factory twice must still have ONE press connection (got %d)"
		% connections)
	b.queue_free()
