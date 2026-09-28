extends SceneTree
## tools/test_sfx.gd — the fight's SOUND: what plays, when, and out of which file.
##
## The port had music and NO combat sound at all: `assets/audio/` and `assets/sfx/` shipped
## every file the PWA uses, and the only code in the tree that read any of them was
## `music.gd`. Jan's report was "hudba funguje, zvuky v souboji ne" — and the reason is
## that the feature did not exist, which no test could see because there was nothing to test.
##
## A headless run has no audio device and a headless `AudioStreamPlayer.play()` never
## advances `get_playback_position()`, so audibility is NOT assertable here. What IS
## assertable is the whole decision layer, which is where every bug in this kind of system
## actually lives:
##
##   1. THE CUES THE FIGHT RAISES. A landed hero swing, a miss, a block, a dodge, the
##      enemy's hit and cast — each one has to put its cue on the queue, and the queue has
##      to survive two cues in ONE tick (Double Swing lands two blows at once; a single
##      field would silently drop the second).
##   2. THE FILE A CUE RESOLVES TO. Fists, blunt, staff and blade are four different noises
##      in the PWA and the mapping is the point — a port that plays one sound for every
##      weapon "works" and is wrong.
##   3. EVERY ASSET EXISTS. A cue pointing at a renamed file is a silent miss at runtime and
##      the whole reason the mixer pushes an error. Read the bytes, not the import cache.
##   4. THE MUTATION-TESTED RULE: `take_sfx_cues()` must EMPTY the queue. A drain that
##      returns the list without clearing it replays the fight's whole sound history every
##      frame, which is a machine gun, not a bug anyone would catch by ear.
##
## Run:  godot --headless --path . --script res://tools/test_sfx.gd
## Pass: prints SFX_ALL_PASS=true

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const GameState := preload("res://scripts/state/game_state.gd")
const Battle := preload("res://scripts/combat/battle.gd")
const PlayerSpells := preload("res://scripts/combat/player_spells.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")

var _failures: Array[String] = []
var _data: Node
var _gen: ItemGen


func _initialize() -> void:
	_data = GameData.new()
	root.add_child(_data)
	_gen = ItemGen.new(_data)

	_test_every_cue_resolves_to_a_real_file()
	_test_weapon_cue_mapping()
	_test_a_landed_swing_raises_a_cue()
	_test_a_miss_raises_the_dodge_cue()
	_test_the_enemy_raises_its_own_cues()
	_test_two_cues_in_one_tick_both_survive()
	_test_the_drain_empties_the_queue()
	_test_an_unknown_cue_is_refused()
	_test_the_shouts_and_the_reflect_raise_the_shout_cue()
	_test_the_enemy_hit_carries_the_monsters_own_weapon()
	_test_the_victory_page_raises_its_own_fanfare()
	_test_a_resolved_reaction_window_plays_exactly_one_cue()
	_test_a_completed_flurry_raises_the_strong_strike()

	for f in _failures:
		print("  FAIL: %s" % f)
	if _failures.is_empty():
		print("SFX_ALL_PASS=true")
	else:
		print("SFX_ALL_PASS=false")
	quit(0 if _failures.is_empty() else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _fresh_state(class_id: String = "barbarian", level: int = 20):
	var s = GameState.new()
	s.bind_data(_data)
	s.set_class(class_id)
	s.hero()["level"] = level
	s.hero()["maxHp"] = _gen.hero_max_hp(s.hero(), s.equip(), _resolve)
	s.hero()["hp"] = s.hero()["maxHp"]
	return s


func _resolve(id: Variant) -> Dictionary:
	var item_id := str(id)
	if item_id == "":
		return {}
	var static_item: Dictionary = _data.item(item_id)
	return static_item


func _fresh_battle(class_id: String = "barbarian", level: int = 20) -> Dictionary:
	var state = _fresh_state(class_id, level)
	var battle = Battle.new(_data, 12345)
	battle.setup(state, _resolve)
	battle.apply_swing_timers(state, _resolve)
	# A cue may be left over from `setup` (a caster opens with a spell). Drain it so a
	# per-test assertion starts from silence.
	battle.take_sfx_cues()
	return {"battle": battle, "state": state}


# --- 3. every asset exists ----------------------------------------------------

## `ResourceLoader.exists()` answers for the IMPORT CACHE, not for the bytes, so a file that
## was renamed out from under a cue still "exists" here. Read the magic bytes: an MP3 starts
## with `ID3` or an `0xFF 0xFB` frame sync.
func _test_every_cue_resolves_to_a_real_file() -> void:
	var checked := 0
	for cue in Sfx.TABLE.keys():
		var layers: Array = Sfx.TABLE[cue]
		if layers.is_empty():
			_fail("cue '%s' has no layers" % cue)
			continue
		for layer in layers:
			var paths: Array = layer.get("paths", [])
			if paths.is_empty():
				_fail("cue '%s' has a layer with no paths" % cue)
				continue
			for path in paths:
				checked += 1
				var p := str(path)
				if not FileAccess.file_exists(p):
					_fail("cue '%s' points at a missing file %s" % [cue, p])
					continue
				var f := FileAccess.open(p, FileAccess.READ)
				if f == null:
					_fail("cue '%s': cannot open %s" % [cue, p])
					continue
				var head := f.get_buffer(4)
				f.close()
				var is_mp3 := head.size() >= 3 and (
					(head[0] == 0x49 and head[1] == 0x44 and head[2] == 0x33)
					or (head.size() >= 2 and head[0] == 0xFF and (head[1] & 0xE0) == 0xE0))
				if not is_mp3:
					_fail("cue '%s': %s is not an MP3 (first bytes %s)"
						% [cue, p, head.hex_encode()])
	if checked < 30:
		_fail("only %d audio files checked - the table lost layers" % checked)


# --- 2. the weapon mapping ----------------------------------------------------

## The PWA's `getHitSfx` / `getCritSfx`. A blade, an axe and claws share the melee pair;
## fists, blunt and staff each get their own; a crit is never the same file as a hit.
func _test_weapon_cue_mapping() -> void:
	var cases := [
		["fists", false, "fist_hit"], ["fists", true, "fist_crit"],
		["blunt", false, "blunt_hit"], ["blunt", true, "blunt_crit"],
		["staff", false, "staff_hit"], ["staff", true, "staff_crit"],
		["blade", false, "melee_hit"], ["blade", true, "melee_crit"],
		["axe", false, "melee_hit"], ["axe", true, "melee_crit"],
		["claws", false, "melee_hit"], ["claws", true, "melee_crit"],
	]
	for c in cases:
		var got := Sfx.cue_for_weapon({"weaponType": str(c[0])}, bool(c[1]))
		if got != str(c[2]):
			_fail("cue_for_weapon(%s, crit=%s) = '%s', expected '%s'"
				% [c[0], c[1], got, c[2]])
	# A weapon with NO type is a fist, exactly as the PWA's `getWeaponType()` defaults.
	if Sfx.cue_for_weapon({}, false) != "fist_hit":
		_fail("a weapon with no type should read as fists")
	# A crit must never resolve to the plain hit file.
	for wt in ["fists", "blunt", "staff", "blade"]:
		var hit := Sfx.cue_for_weapon({"weaponType": wt}, false)
		var crit := Sfx.cue_for_weapon({"weaponType": wt}, true)
		if hit == crit:
			_fail("a %s crit plays the same cue as a hit ('%s')" % [wt, hit])


# --- 1. the cues the fight raises ---------------------------------------------

## A landed hero swing has to raise SOME cue, and the empty-handed hero's has to be the
## fist's — the class kit gives a barbarian a blade, so this also pins that the type is read
## off the weapon actually equipped rather than guessed.
func _test_a_landed_swing_raises_a_cue() -> void:
	var rig := _fresh_battle("barbarian", 30)
	var battle = rig["battle"]
	var state = rig["state"]
	var weapon: Dictionary = _resolve(state.equip().get("weapon", "fists"))
	var expected := Sfx.cue_for_weapon(weapon, false)
	# A hit is a coin flip in an even fight, so swing until one lands rather than assuming
	# the first one does.
	var landed := false
	for i in 40:
		battle.take_sfx_cues()
		var r: Dictionary = battle.player_attack(state, _resolve)
		var cues: Array = battle.take_sfx_cues()
		if bool(r.get("hit", false)):
			landed = true
			if not cues.has(expected) and not cues.has(Sfx.cue_for_weapon(weapon, true)):
				_fail("a landed swing raised %s, expected '%s'" % [str(cues), expected])
			break
	if not landed:
		_fail("test setup: 40 hero swings never landed")


## The PWA plays the DODGE sound on a MISS as well as on a dodge — its attack-table branch
## is `playSFX(dodgeSfx)`. Assert the cue, not the word, so a screen renaming the float text
## cannot silently take the sound with it.
func _test_a_miss_raises_the_dodge_cue() -> void:
	var rig := _fresh_battle("barbarian", 1)
	var battle = rig["battle"]
	var state = rig["state"]
	# A level-1 hero against a deep-act monster misses far more often than he hits, but the
	# roll is seeded — drive swings until a miss shows up rather than trusting the seed.
	var saw_miss := false
	for i in 60:
		battle.take_sfx_cues()
		var r: Dictionary = battle.player_attack(state, _resolve)
		var cues: Array = battle.take_sfx_cues()
		if str(r.get("reason", "")) == "miss":
			saw_miss = true
			if not cues.has(Sfx.CUE_DODGE):
				_fail("a MISS raised %s, expected the dodge cue" % str(cues))
			break
		if battle.ended:
			break
	if not saw_miss:
		_fail("test setup: 60 swings produced no miss (the attack table should be tight at level 1)")


## The enemy's own sounds: it is hit (no cue of its own — the hero's swing carries it), it
## hits the hero (hurt), it starts a cast (the school's sound) and it is dodged (dodge).
func _test_the_enemy_raises_its_own_cues() -> void:
	var rig := _fresh_battle("barbarian", 20)
	var battle = rig["battle"]
	var state = rig["state"]
	var saw_hurt := false
	for i in 60:
		battle.take_sfx_cues()
		var r: Dictionary = battle.enemy_attack(state, _resolve)
		var cues: Array = battle.take_sfx_cues()
		if bool(r.get("hit", false)):
			saw_hurt = true
			if not cues.has(Sfx.CUE_HURT):
				_fail("a landed enemy hit raised %s, expected the hurt cue" % str(cues))
			break
		if battle.hero_hp <= 0.0:
			break
	if not saw_hurt:
		_fail("test setup: 60 enemy swings never landed on the hero")

	# A caster's wind-up is the only place the port can put the school's sound (it draws no
	# projectile), so pin that the cast raises it.
	var rig2 := _fresh_battle("barbarian", 20)
	var b2 = rig2["battle"]
	b2.take_sfx_cues()
	b2.enemy_first_swing_done = true
	b2.enemy_attack_type = "caster"
	b2.enemy_spells = ["shadow_bolt"]
	b2.enemy_resource_cur = 999.0
	b2.enemy_max_resource = 999.0
	b2.cast_spell_id = ""
	var cast_cues: Array = []
	for i in 8:
		b2.take_sfx_cues()
		b2.enemy_attack(rig2["state"], _resolve)
		var c: Array = b2.take_sfx_cues()
		if b2.cast_spell_id != "" or c.has(Sfx.CUE_ENEMY_CAST):
			cast_cues = c
			break
	if not cast_cues.has(Sfx.CUE_ENEMY_CAST):
		_fail("a caster starting a spell raised %s, expected the cast cue" % str(cast_cues))


## A tick can raise more than one cue — Double Swing lands two blows at once. A single
## `sfx_cue` field would keep only the last, which is the bug a one-field design cannot
## see. Assert the QUEUE.
func _test_two_cues_in_one_tick_both_survive() -> void:
	var rig := _fresh_battle("barbarian", 20)
	var battle = rig["battle"]
	battle.take_sfx_cues()
	battle.sound(Sfx.CUE_THUNDER_CLAP)
	battle.sound(Sfx.CUE_DODGE)
	var cues: Array = battle.take_sfx_cues()
	if cues.size() != 2:
		_fail("two cues in one tick came back as %d" % cues.size())
	elif not (cues.has(Sfx.CUE_THUNDER_CLAP) and cues.has(Sfx.CUE_DODGE)):
		_fail("two cues in one tick lost one: %s" % str(cues))


## MUTATION CHECK: a drain that does not CLEAR the queue replays the fight's whole sound
## history on every frame. This is the assertion that catches it.
func _test_the_drain_empties_the_queue() -> void:
	var rig := _fresh_battle("barbarian", 20)
	var battle = rig["battle"]
	battle.sound(Sfx.CUE_MELEE_HIT)
	var first: Array = battle.take_sfx_cues()
	if first.size() != 1:
		_fail("the first drain returned %d cues, expected 1" % first.size())
	var second: Array = battle.take_sfx_cues()
	if not second.is_empty():
		_fail("the drain did not clear the queue: a second call returned %s" % str(second))
	if battle.sfx_cue != "":
		_fail("the drain left sfx_cue='%s' behind" % str(battle.sfx_cue))


## A typo in a rule must be LOUD. A mixer that silently drops an unknown cue is a mixer that
## makes "no sound here" indistinguishable from "the name is wrong", which is exactly the
## failure this whole feature exists to end.
func _test_an_unknown_cue_is_refused() -> void:
	if Sfx.is_known("no_such_cue"):
		_fail("the mixer claims to know 'no_such_cue'")
	var battle = Battle.new(_data, 1)
	battle.sound("no_such_cue")
	if not battle.sfx_cues.is_empty():
		_fail("an unknown cue was queued anyway: %s" % str(battle.sfx_cues))


# --- the spells the bar raises, and the enemy's own weapon ---------------------

## ⚠️  THE COMBAT BAR'S OWN SPELLS WERE SILENT. `test_player_spells` asserts their EFFECTS and
## the effects were right; what no rules test looked at was that the same branch also raises
## the sound. The PWA plays `shoutSfx` from the shout branches of `castClassSpell` and from
## BOTH halves of its Spell Reflect, and `thunderClapSfx` / `thunderBoltSfx` from the two
## thunder spells.
func _test_the_shouts_and_the_reflect_raise_the_shout_cue() -> void:
	var state = _fresh_state("barbarian", 40)
	state.data["talentLevels"] = {
		"barbarian_battleShout": 1,
		"barbarian_defensiveShout": 1,
		"barbarian_thunderClap": 1,
		"barbarian_thunderBolt": 1,
		"barbarian_spellReflect": 1,
	}
	var battle = Battle.new(_data, 4242)
	battle.setup(state, _resolve)
	battle.apply_swing_timers(state, _resolve)

	# Every shout resolves on its own — no target and no roll, but the global spell cooldown
	# (the PWA's GCD) applies between two casts, so it is cleared before each one.
	for spell_id in ["battleShout", "defensiveShout"]:
		battle.take_sfx_cues()
		battle.spell_gcd_ms = 0
		var r: Dictionary = PlayerSpells.cast(battle, spell_id, state, _resolve, _data, battle.rng)
		var cues: Array = battle.take_sfx_cues()
		if not bool(r.get("ok", false)):
			_fail("%s did not cast: %s" % [spell_id, str(r.get("message", ""))])
		elif not cues.has(Sfx.CUE_SHOUT):
			_fail("%s raised %s, expected the shout cue" % [spell_id, str(cues)])

	for pair in [["thunderClap", Sfx.CUE_THUNDER_CLAP], ["thunderBolt", Sfx.CUE_THUNDER_BOLT]]:
		battle.take_sfx_cues()
		battle.spell_gcd_ms = 0
		battle.spell_cooldowns.clear()
		var r2: Dictionary = PlayerSpells.cast(battle, str(pair[0]), state, _resolve, _data, battle.rng)
		var cues2: Array = battle.take_sfx_cues()
		if not bool(r2.get("ok", false)):
			_fail("%s did not cast: %s" % [pair[0], str(r2.get("message", ""))])
		elif not cues2.has(str(pair[1])):
			_fail("%s raised %s, expected '%s'" % [pair[0], str(cues2), pair[1]])

	# Spell Reflect only resolves against a cast in progress AND with a shield in the off hand
	# (it is a shield spell — `blocked_reason` refuses it without one). The shout belongs to
	# BOTH of the PWA's reflect branches; the offensive one is driven here.
	# `shield_buckler` is the id the OTHER shield tests use (`test_player_spells`).
	state.equip()["shield"] = "shield_buckler"
	battle.apply_swing_timers(state, _resolve)
	battle.cast_spell_id = "shadow_bolt"
	battle.cast_time = 2000.0
	battle.cast_elapsed = 0.0
	battle.spell_gcd_ms = 0
	battle.spell_cooldowns.clear()
	battle.take_sfx_cues()
	var r3: Dictionary = PlayerSpells.cast(battle, "spellReflect", state, _resolve, _data, battle.rng)
	var cues3: Array = battle.take_sfx_cues()
	if not bool(r3.get("ok", false)):
		_fail("Spell Reflect did not cast: %s" % str(r3.get("message", "")))
	elif not cues3.has(Sfx.CUE_SHOUT):
		_fail("Spell Reflect raised %s, expected the shout cue" % str(cues3))


## The PWA's enemy hit is TWO sounds: `getHitSfx()` with NO override — which reads
## `getWeaponType()`, the MONSTER's own weapon type — and then `getHurtSfx()`. A port that
## plays only the hurt cue leaves a bear's paw sounding like a sword.
func _test_the_enemy_hit_carries_the_monsters_own_weapon() -> void:
	var rig := _fresh_battle("barbarian", 30)
	var battle = rig["battle"]
	battle.enemy_attack_type = "fists"
	var cues: Array = []
	for i in 40:
		battle.take_sfx_cues()
		battle.enemy_attack(rig["state"], _resolve)
		cues = battle.take_sfx_cues()
		if battle.hero_hp < battle.hero_max_hp:
			break
	if not cues.has(Sfx.CUE_FIST_HIT):
		_fail("a monster with fists landing a hit raised %s, expected 'fist_hit'" % str(cues))
	if not cues.has(Sfx.CUE_HURT):
		_fail("a landed enemy hit raised %s without the hurt cue" % str(cues))
	# And the mapping follows the monster, not a constant.
	if Sfx.cue_for_weapon({"weaponType": "blunt"}, false) != Sfx.CUE_BLUNT_HIT:
		_fail("a blunt monster should read as blunt_hit")


## `endMapBattle` plays `treasureSfx`, and the loot popup that opens over it plays `shopSfx`.
## Both are the PAGE's sound, so they belong to the screen's `_finish_fight` and not to the
## loot that happened to drop.
func _test_the_victory_page_raises_its_own_fanfare() -> void:
	var mixer := preload("res://scripts/audio/sfx.gd")
	if not mixer.is_known(mixer.CUE_TREASURE):
		_fail("the mixer does not know the victory page's treasure cue")
	if not mixer.is_known(mixer.CUE_SHOP):
		_fail("the mixer does not know the shop cue the loot popup needs")
	# The map's own reveal sound reuses the same file but is a cue of its own, so a screen
	# renaming one cannot silently take the other with it.
	if mixer.CUE_ACT_UNLOCK == mixer.CUE_TREASURE:
		_fail("the map's unlock cue and the chest's are the same constant")
	var a: Array = mixer.TABLE.get(mixer.CUE_ACT_UNLOCK, [])
	var b: Array = mixer.TABLE.get(mixer.CUE_TREASURE, [])
	if a.is_empty() or b.is_empty():
		_fail("the treasure / unlock cues lost their layers")
	elif str((a[0] as Dictionary).get("paths", [""])[0]) != str((b[0] as Dictionary).get("paths", [""])[0]):
		_fail("the map's unlock should play the same file as the chest's fanfare")


## ONE cue per resolved reaction window — and the sound comes from the BATTLE's resolution,
## not from the press.
##
## ⚠️  This is a regression test: `arena_screen.on_reaction_button` used to play the cue on
## the correct press as well, reading the PWA's `showOpportunitySuccess` as if it made a
## sound. It does not — the PWA plays the cue inside `resolveOpportunity`, once, when the
## swing is settled. Measured before the fix: an answered dodge put the press's cue into the
## queue AND then the same cue again out of `enemy_attack`, i.e. two plays about one swing.
## A screen that plays its own copy of a rule's sound is invisible to every rules assertion,
## which is why the count is pinned here rather than the presence.
func _test_a_resolved_reaction_window_plays_exactly_one_cue() -> void:
	var rig := _fresh_battle("barbarian", 30)
	var battle = rig["battle"]
	battle.enemy_attack_type = "melee"
	# A window of a KNOWN kind: the roll itself is `test_reactions`' business.
	battle.opp_type = "dodge"
	battle.opp_resolved = false
	battle.opp_failed = false
	battle.take_sfx_cues()
	var answer: Dictionary = battle.answer_opportunity("dodge")
	if str(answer.get("result", "")) != "hit":
		_fail("test setup: the window refused the correct answer (%s)" % str(answer))
		return
	if not battle.take_sfx_cues().is_empty():
		_fail("answering the window raised a sound - the cue belongs to the swing's resolution, once")
	rig["state"].hero()["hp"] = 100000.0
	battle.hero_hp = 100000.0
	var settle: Dictionary = battle.enemy_attack(rig["state"], _resolve)
	if str(settle.get("reason", "")) != "opportunity":
		_fail("test setup: the answered window did not settle as an avoided blow (%s)" % str(settle))
		return
	var cues: Array = battle.take_sfx_cues()
	if cues.count(Sfx.CUE_DODGE) != 1:
		_fail("one resolved dodge played the dodge cue %d times: %s" % [cues.count(Sfx.CUE_DODGE), str(cues)])

	# A wrong answer is silent too — the PWA's `showOpportunityFail` is a cross, not a noise.
	var rig2 := _fresh_battle("barbarian", 30)
	var b2 = rig2["battle"]
	b2.enemy_attack_type = "melee"
	b2.opp_type = "block"
	b2.opp_resolved = false
	b2.opp_failed = false
	b2.take_sfx_cues()
	b2.answer_opportunity("dodge")
	if not b2.take_sfx_cues().is_empty():
		_fail("a WRONG reaction answer raised a sound; the cross is the feedback")


## A completed flurry plays `strong_strike` — the PWA's `playSFX(strongStrikeSfx)` in
## `endCombo(true)`. A flurry that breaks early plays nothing, and the two are easy to swap.
func _test_a_completed_flurry_raises_the_strong_strike() -> void:
	var rig := _fresh_battle("barbarian", 30)
	var battle = rig["battle"]
	battle.take_sfx_cues()
	battle.start_whirlwind(["tri"], 1500)
	battle.answer_whirlwind("tri", rig["state"], _resolve)
	var cues: Array = battle.take_sfx_cues()
	if not cues.has(Sfx.CUE_STRONG_STRIKE):
		_fail("a completed whirlwind flurry raised %s, expected 'strong_strike'" % str(cues))

	var rig2 := _fresh_battle("barbarian", 30)
	var b2 = rig2["battle"]
	b2.take_sfx_cues()
	b2.start_whirlwind(["tri", "circle"], 1500)
	b2.answer_whirlwind("square", rig2["state"], _resolve)
	if b2.take_sfx_cues().has(Sfx.CUE_STRONG_STRIKE):
		_fail("a flurry broken by a wrong press still played the completion fanfare")

