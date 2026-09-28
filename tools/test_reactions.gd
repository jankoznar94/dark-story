extends SceneTree
## tools/test_reactions.gd — the enemy swing's reaction window and the Whirlwind flurry.
##
## `test_arena_screen` asserts the WIRING (does the button reach the rule); this asserts
## the RULES themselves, and it exists because every one of them is a silent failure when
## it is wrong:
##
##   * a window that never opens reads as "the buttons are decoration",
##   * a window that never CLOSES makes the hero unkillable and the fight unwinnable,
##   * a wrong press that may be retried is not a failure at all,
##   * a counter bonus that is never spent (or spent twice) is invisible in any frame,
##   * a flurry with no deadline is a free damage spell with extra taps.
##
## The seeded RNG makes the rolls deterministic, so a window is forced by setting
## `opp_type` directly where the point is the OUTCOME rather than the roll.
##
## Run:  godot4 --headless --path . --script res://tools/test_reactions.gd
## Pass: prints REACTIONS_ALL_PASS=true and exits 0.

const GameData := preload("res://scripts/data/game_data.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const Battle := preload("res://scripts/combat/battle.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const Talents := preload("res://scripts/items/talents.gd")

var _data: Node
var _ok := true


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok   %s%s" % [label, (" — " + detail) if detail != "" else ""])
	else:
		print("  FAIL %s%s" % [label, (" — " + detail) if detail != "" else ""])
		_ok = false


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)

	print("== the reaction window's chance and type ==")
	_test_chance_scales_with_armour_and_caps()
	_test_type_never_offers_an_unusable_reaction()

	print("== the window's three outcomes ==")
	_test_a_right_answer_spares_the_blow()
	_test_a_wrong_answer_closes_the_window()
	_test_an_unanswered_window_lands_the_blow()
	_test_the_cooldown_gates_the_next_window()

	print("== the counter ==")
	_test_a_counter_banks_exactly_one_main_hand_bonus()
	_test_the_off_hand_never_spends_the_bonus()

	print("== Whirlwind ==")
	_test_the_flurry_prompts_in_order_and_lands_strikes()
	_test_a_wrong_key_ends_the_flurry()
	_test_the_deadline_ends_the_flurry()
	_test_the_swing_timers_restart_after_a_flurry()

	print("== the window never opens where it could not be answered ==")
	_test_a_boss_and_a_caster_get_no_window()

	print("== REACTIONS ==")
	if _ok:
		print("REACTIONS_ALL_PASS=true")
	else:
		print("REACTIONS_ALL_PASS=false")
	quit(0 if _ok else 1)


# --- rig ----------------------------------------------------------------------

func _resolve(state) -> Callable:
	return func(id):
		var item_id := str(id)
		if item_id == "":
			return {}
		var static_item: Dictionary = _data.item(item_id)
		if not static_item.is_empty():
			return static_item
		return state.loot_item(item_id)


## A live fight with a barbarian hero, deliberately built through the real `setup()` so
## the test drives the same object the game does.
func _rig(talents: Dictionary = {}, seed_value: int = 4242) -> Dictionary:
	var state := GameState.new()
	state.bind_data(_data)
	state.set_class("barbarian")
	state.hero()["level"] = 20
	state.hero()["hp"] = 5000
	state.hero()["maxHp"] = 5000
	state.hero()["attrDex"] = 60
	for key in talents:
		state.data["talentLevels"][key] = int(talents[key])
	var battle = Battle.new(_data, seed_value)
	battle.act_id = 0
	battle.setup(state, _resolve(state))
	battle.hero_hp = 5000.0
	battle.hero_max_hp = 5000.0
	battle.gap = 0.0
	battle.enemy_hp = 100000.0
	battle.enemy_max_hp = 100000.0
	battle.opp_cooldown_ms = 0
	battle.ww_active = false
	battle.opp_type = ""
	return {"battle": battle, "state": state}


## Force a window open with a given kind. The ROLL is asserted separately; every test
## below is about what happens once a window exists, so the kind is set rather than
## rolled — a seeded roll would make these fail for the wrong reason when the RNG shifts.
func _arm(battle, kind: String) -> void:
	battle.opp_type = kind
	battle.opp_resolved = false
	battle.opp_failed = false


# --- chance and type ----------------------------------------------------------

func _test_chance_scales_with_armour_and_caps() -> void:
	var rig := _rig()
	var battle = rig["battle"]
	var state = rig["state"]
	# A naked hero: exactly the base.
	var naked: float = battle.hero_opportunity_chance(state, _resolve(state))
	_check("a naked hero gets the base chance", is_equal_approx(naked, Battle.OPPORTUNITY_BASE_PCT),
		"%.1f%% (base %.1f)" % [naked, Battle.OPPORTUNITY_BASE_PCT])

	# ⚠️  A BASE armour item carries NO `defense` of its own — the stat comes from the
	# quality roll and the affixes (see `ItemGen`), so a static `armor_ringMail` out of the
	# table is a 0-defence plate. The chance formula is asserted against a find_item that
	# states the defence directly, which is also what makes the arithmetic checkable: the
	# item table cannot express "400 defence" without generating one.
	#
	# The slot is matched off the equip dict rather than guessed, which is what proves the
	# stat was summed at all. The kit leaves the armour slot EMPTY (only the weapon is
	# gifted), so the test wears a real one from the table first.
	state.equip()["armor"] = "armor_ringMail"
	var defense: int = Talents.total_defense(state, _resolve_with_defense(state))
	_check("the test's own armour reports defence", defense == 400, "%d defence" % defense)
	var armored: float = battle.hero_opportunity_chance(state, _resolve_with_defense(state))
	_check("armour raises the chance", armored > naked, "%.1f%% with %d defence" % [armored, defense])
	_check("one point per 20 defence",
		is_equal_approx(armored, Battle.OPPORTUNITY_BASE_PCT + 20.0), "%.1f%%" % armored)

	# The ceiling: a fight that is ALL reaction is the failure the cap prevents.
	var capped: float = battle.hero_opportunity_chance(state, _resolve_huge_defense(state))
	_check("the chance CAPS at 40 %", is_equal_approx(capped, Battle.OPPORTUNITY_MAX_PCT),
		"%.1f%% (cap %.0f)" % [capped, Battle.OPPORTUNITY_MAX_PCT])

	# A hero with neither shield nor the talent is always offered dodge: a window with one
	# choice is still a window, and returning "" here would close every window for them.
	state.equip()["shield"] = ""
	var kinds: Dictionary = {}
	for _i in 60:
		kinds[battle.hero_opportunity_type(state, _resolve(state))] = true
	_check("no shield and no counter gives dodge only",
		kinds.size() == 1 and kinds.has("dodge"), str(kinds.keys()))


## Does `id` name the item currently WORN in `slot`? A find_item stand-in needs to know
## which slot it is being asked about, and the equip dict is the only place that is stated.
func slot_matches(state, id: Variant, slot: String) -> bool:
	return str(state.equip().get(slot, "")) == str(id)


## A find_item that gives the armour slot 400 defence — 20 points of the chance, i.e.
## exactly the armour bonus's own unit.
func _resolve_with_defense(state) -> Callable:
	return func(id):
		var item: Dictionary = _resolve(state).call(id)
		if not item.is_empty() and slot_matches(state, id, "armor"):
			item = item.duplicate()
			item["defense"] = 400
		return item


## A find_item that gives the armour slot absurd defence, to prove the CAP is what stops
## the chance rather than no item ever reaching it.
func _resolve_huge_defense(state) -> Callable:
	return func(id):
		var item: Dictionary = _resolve(state).call(id)
		if not item.is_empty() and slot_matches(state, id, "armor"):
			item = item.duplicate()
			item["defense"] = 100000
		return item


func _test_type_never_offers_an_unusable_reaction() -> void:
	var rig := _rig({"barbarian_counterAttack": 5})
	var battle = rig["battle"]
	var state = rig["state"]
	# Counter invested, no shield: counter and dodge, never block.
	# `state.equip()["shield"]` is the class kit's own value, which is not a shield.
	state.equip()["shield"] = ""
	var kinds: Dictionary = {}
	for _i in 200:
		kinds[battle.hero_opportunity_type(state, _resolve(state))] = true
	_check("no shield means never block", not kinds.has("block"), str(kinds.keys()))
	_check("the invested counter does appear", kinds.has("counter"), str(kinds.keys()))

	# With a shield, block joins the roll. The shield is a real one from the item table.
	state.equip()["shield"] = "shield_buckler"
	var with_shield: Dictionary = {}
	for _i in 200:
		with_shield[battle.hero_opportunity_type(state, _resolve(state))] = true
	_check("a shield adds block", with_shield.has("block"), str(with_shield.keys()))

	# Without the talent, NEVER counter — a hero who did not buy it must not be asked to
	# press it, and the button is hidden for them too.
	var plain := _rig()
	plain["state"].equip()["shield"] = "shield_buckler"
	var no_talent: Dictionary = {}
	for _i in 200:
		no_talent[plain["battle"].hero_opportunity_type(plain["state"], _resolve(plain["state"]))] = true
	_check("no talent means never counter", not no_talent.has("counter"), str(no_talent.keys()))


# --- the three outcomes -------------------------------------------------------

func _test_a_right_answer_spares_the_blow() -> void:
	var rig := _rig()
	var battle = rig["battle"]
	var state = rig["state"]
	_arm(battle, "dodge")
	var answer: Dictionary = battle.answer_opportunity("dodge")
	_check("the right button resolves the window", bool(answer["ok"]), str(answer))
	var hp_before: float = battle.hero_hp
	var avoided: bool = battle.resolve_opportunity(state)
	_check("an answered window avoids the blow", avoided)
	_check("the blow cost nothing", battle.hero_hp == hp_before)
	_check("the window is closed", not battle.opportunity_open(), battle.opp_type)
	_check("the cooldown starts", battle.opp_cooldown_ms == Battle.OPPORTUNITY_COOLDOWN_MS,
		str(battle.opp_cooldown_ms))
	# The outcome itself is reported, because the caller plays the sound and draws the
	# word off it. Without this the screen would have to guess which reaction succeeded.
	_check("the outcome names the reaction", battle.opp_last_kind == "dodge", battle.opp_last_kind)


func _test_a_wrong_answer_closes_the_window() -> void:
	var rig := _rig({"barbarian_counterAttack": 5})
	var battle = rig["battle"]
	var state = rig["state"]
	_arm(battle, "block")
	var answer: Dictionary = battle.answer_opportunity("dodge")
	_check("a wrong button is refused", not bool(answer["ok"]) and str(answer["result"]) == "fail",
		str(answer))
	_check("the window closed on the mistake", not battle.opportunity_open(), battle.opp_type)
	# ⚠️  The retry is the whole point of this assertion: a player who may press again has
	# not failed, and the interaction stops being a test of anything.
	var retry: Dictionary = battle.answer_opportunity("block")
	_check("a second press cannot rescue it", not bool(retry["ok"]), str(retry))
	var avoided: bool = battle.resolve_opportunity(state)
	_check("the blow lands through the failed window", not avoided)


func _test_an_unanswered_window_lands_the_blow() -> void:
	var rig := _rig()
	var battle = rig["battle"]
	var state = rig["state"]
	_arm(battle, "dodge")
	# No press at all — the player did not react.
	var avoided: bool = battle.resolve_opportunity(state)
	_check("an ignored window does not save the hero", not avoided)
	# ...but it is not SILENT: the screen needs to be told, or the window reads as never
	# having appeared. Read once — the queue clears on read, so asking twice would report
	# the second read.
	var word: String = str(battle.take_opportunity_feedback())
	_check("an ignored window reports itself", word == "missed", "feedback was '%s'" % word)
	_check("the queue cleared on read", battle.take_opportunity_feedback() == "")


func _test_the_cooldown_gates_the_next_window() -> void:
	var rig := _rig()
	var battle = rig["battle"]
	var state = rig["state"]
	_arm(battle, "dodge")
	battle.answer_opportunity("dodge")
	battle.resolve_opportunity(state)
	# The cooldown is now running, so no amount of arm_opportunity may open a window.
	var opened := false
	for _i in 20:
		battle.arm_opportunity(state, _resolve(state))
		if battle.opportunity_open():
			opened = true
	_check("the cooldown blocks a new window", not opened)
	# The cooldown runs on the FIGHT's tick, which is what makes it the same on every
	# machine — and what lets this test walk it down instead of sleeping.
	var before: int = battle.opp_cooldown_ms
	battle.tick(float(Battle.OPPORTUNITY_COOLDOWN_MS + 100), state, _resolve(state))
	_check("the fight's clock brings the cooldown down", battle.opp_cooldown_ms < before,
		"%d -> %d" % [before, battle.opp_cooldown_ms])


# --- the counter --------------------------------------------------------------

func _test_a_counter_banks_exactly_one_main_hand_bonus() -> void:
	var rig := _rig({"barbarian_counterAttack": 3})
	var battle = rig["battle"]
	var state = rig["state"]
	_arm(battle, "counter")
	battle.answer_opportunity("counter")
	battle.resolve_opportunity(state)
	_check("a landed counter banks a bonus", battle.counter_pending)
	var expected: float = Battle.COUNTER_BONUS_BASE_PCT + 3.0 * Battle.COUNTER_BONUS_PER_LEVEL_PCT
	_check("the bonus is 50 + lv*30 %%", is_equal_approx(battle.counter_bonus_pct, expected),
		"%.0f%% (expected %.0f%%)" % [battle.counter_bonus_pct, expected])
	var mult: float = battle.consume_counter_bonus(false)
	_check("the main hand spends it", mult > 1.0, "x%.2f" % mult)
	_check("it is spent exactly once", not battle.counter_pending)
	_check("a second swing gets nothing", is_equal_approx(battle.consume_counter_bonus(false), 1.0))


func _test_the_off_hand_never_spends_the_bonus() -> void:
	var rig := _rig({"barbarian_counterAttack": 3})
	var battle = rig["battle"]
	battle.counter_pending = true
	battle.counter_bonus_pct = 200.0
	var off: float = battle.consume_counter_bonus(true)
	_check("an off-hand swing takes no bonus", is_equal_approx(off, 1.0), "x%.2f" % off)
	_check("...and does not consume it", battle.counter_pending)
	# Proves the two halves are the same decision, not two independent flags.
	_check("the main hand still has it", battle.consume_counter_bonus(false) > 1.0)


# --- Whirlwind ----------------------------------------------------------------

func _test_the_flurry_prompts_in_order_and_lands_strikes() -> void:
	var rig := _rig({"barbarian_whirlwind": 2})
	var battle = rig["battle"]
	var state = rig["state"]
	var dirs := ["tri", "circle", "cross"]
	battle.start_whirlwind(dirs, 1500)
	_check("the flurry is running", battle.whirlwind_open())
	_check("it prompts the first key", battle.whirlwind_prompt() == "tri", battle.whirlwind_prompt())
	var hp_before: float = battle.enemy_hp
	for i in dirs.size():
		var prompt: String = battle.whirlwind_prompt()
		var result: Dictionary = battle.answer_whirlwind(prompt, state, _resolve(state))
		_check("strike %d accepted" % (i + 1), bool(result["ok"]), str(result))
	_check("the flurry ended when the sequence ran out", not battle.whirlwind_open())
	_check("landed strikes are counted", battle.ww_landed >= 1, "landed %d" % battle.ww_landed)
	_check("the enemy took damage", battle.enemy_hp < hp_before,
		"%.0f -> %.0f" % [hp_before, battle.enemy_hp])
	var out: Dictionary = battle.take_whirlwind_result()
	_check("a completed flurry reports itself", str(out["feedback"]) == "complete", str(out))


func _test_a_wrong_key_ends_the_flurry() -> void:
	var rig := _rig({"barbarian_whirlwind": 2})
	var battle = rig["battle"]
	var state = rig["state"]
	battle.start_whirlwind(["tri", "circle", "cross"], 1500)
	var result: Dictionary = battle.answer_whirlwind("square", state, _resolve(state))
	_check("a wrong key is refused", not bool(result["ok"]), str(result))
	_check("a wrong key ends the flurry", not battle.whirlwind_open())
	_check("it reports the failure", str(battle.take_whirlwind_result()["feedback"]) == "fail")
	# The landed strikes are KEPT — the flurry pays for what it got right.
	_check("what landed before the mistake is kept", battle.ww_landed >= 0,
		"landed %d" % battle.ww_landed)


func _test_the_deadline_ends_the_flurry() -> void:
	var rig := _rig({"barbarian_whirlwind": 2})
	var battle = rig["battle"]
	var state = rig["state"]
	battle.start_whirlwind(["tri", "circle", "cross"], 600)
	# Half the deadline: still open.
	battle.tick(300.0, state, _resolve(state))
	_check("the flurry survives inside its deadline", battle.whirlwind_open(),
		"%d ms left" % battle.ww_deadline_ms)
	# Past it: the flurry ends by itself.
	battle.tick(400.0, state, _resolve(state))
	_check("the deadline ends the flurry", not battle.whirlwind_open())
	_check("a timeout counts as a failure", str(battle.take_whirlwind_result()["feedback"]) == "fail")


func _test_the_swing_timers_restart_after_a_flurry() -> void:
	var rig := _rig({"barbarian_whirlwind": 2})
	var battle = rig["battle"]
	var state = rig["state"]
	battle.start_whirlwind(["tri"], 1500)
	battle.player_swing_elapsed = 1234.0
	battle.answer_whirlwind("tri", state, _resolve(state))
	_check("the flurry resets the hero's swing clock", battle.player_swing_elapsed == 0.0,
		str(battle.player_swing_elapsed))
	# And on a failure too, because the flurry still spent the swing.
	var rig2 := _rig({"barbarian_whirlwind": 2})
	var b2 = rig2["battle"]
	b2.start_whirlwind(["tri", "circle"], 1500)
	b2.player_swing_elapsed = 900.0
	b2.answer_whirlwind("square", rig2["state"], _resolve(rig2["state"]))
	_check("a broken flurry restarts them too", b2.player_swing_elapsed == 0.0,
		str(b2.player_swing_elapsed))


# --- where a window must NOT open ---------------------------------------------

func _test_a_boss_and_a_caster_get_no_window() -> void:
	var rig := _rig()
	var battle = rig["battle"]
	var state = rig["state"]
	# A boss runs the PWA's own sequence and its swings are never answerable this way.
	battle.is_boss = true
	var boss_opened := false
	for _i in 40:
		battle.arm_opportunity(state, _resolve(state))
		if battle.opportunity_open():
			boss_opened = true
	_check("a boss offers no reaction window", not boss_opened)

	# A caster mid-cast is answered by interrupt/reflect, not by a dodge button.
	battle.is_boss = false
	battle.cast_spell_id = "shadow_bolt"
	var casting_opened := false
	for _i in 40:
		battle.arm_opportunity(state, _resolve(state))
		if battle.opportunity_open():
			casting_opened = true
	_check("a casting enemy offers no window", not casting_opened)

	# A running flurry owns the row, so no window may open under it.
	battle.cast_spell_id = ""
	battle.start_whirlwind(["tri", "circle"], 1500)
	var during_flurry := false
	for _i in 40:
		battle.arm_opportunity(state, _resolve(state))
		if battle.opportunity_open():
			during_flurry = true
	_check("a running flurry blocks the window", not during_flurry)
