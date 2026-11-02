extends RefCounted
class_name RunSpells
## RunSpells — the hero's class spells in the SURVIVOR fight.
##
## The duel's rules live in `player_spells.gd` and are written against a `battle` that has ONE
## enemy, one HP pool and one swing clock. The run has a LIST of monsters, so the effects had to
## be written again for it — but nothing else was invented: the gate (an INVESTED talent point is
## what makes a spell exist), the mana cost, the cooldowns, the damage percentages and the sound
## cues are the duel's own, read from the same `PlayerSpells` statics and the same
## `CLASSES.json` rows. `player_spells.gd` remains the source of truth for a number; when the two
## disagree, this file is the one that is wrong.
##
## The mapping of "the enemy" onto a crowd, in one place:
##   * a MELEE spell (Thunder Clap, Shield Slam, Pummel, Double Swing) needs a body inside the
##     hand's drawn reach and IN FRONT of the hero — the same facing rule the swings obey, or a
##     fleeing hero could clap backwards;
##   * Thunder Bolt is a BOLT: it picks the nearest body within `SPELL_RANGE` and does not care
##     which way the hero faces, because magic is not a swing;
##   * a self-buff (both Shouts, Frenzy, Heroic Strike) needs no target at all;
##   * Whirlwind is the flurry the duel already had — a sequence of PS presses on a deadline,
##     resolved by `SurvivorRun.answer_whirlwind()`.
##
## Cooldowns and the GCD live on the RUN (a session, like the duel's), never on the save.

const PlayerSpells := preload("res://scripts/combat/player_spells.gd")
const Progression := preload("res://scripts/combat/progression.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")

## How far a BOLT reaches. Longer than any weapon, shorter than a thrower's stand-off (232) so a
## caster still has a reason to keep its distance.
const SPELL_RANGE := 300.0
## Global cooldown, the PWA's 0.5 s — the same number the duel uses.
const GCD_MS := 500
## Both buffs last 30 s in the duel (`PlayerSpells.SHOUT_MS`), Frenzy's stacks 10 s.
const SHOUT_MS := 30000
const FRENZY_MS := 10000
## How long the player has to press each PS button of a Whirlwind strike.
const WHIRLWIND_REACTION_MS := 1500


static func class_id(run) -> String:
	if run == null or run._state == null:
		return ""
	return str(run._state.data.get("heroClass", ""))


# ============================================================================ the bar

## Everything the hero can see as a BUTTON: spells with a talent point in them, exactly the
## filter the duel's bar applies (`PlayerSpells.is_available`). A blocked spell is still listed,
## with the reason, because a dimmed button explains itself and a missing one does not.
static func bar(run) -> Array:
	var out: Array = []
	if run == null or run._data == null:
		return out
	var cid := class_id(run)
	for s in PlayerSpells.spells_for_class(run._data, cid):
		var def: Dictionary = s
		var spell_id := str(def.get("id", ""))
		if not PlayerSpells.is_available(run._state, cid, spell_id):
			continue
		var blocked := blocked_reason(run, spell_id)
		out.append({
			"id": spell_id,
			"name": str(def.get("name", spell_id)),
			"def": def,
			"blocked": blocked,
			"can": blocked == "",
			"cost": PlayerSpells.spell_cost(run._state, cid, spell_id,
				float(def.get("cost", 0))),
			"cooldown": int(run.spell_cooldowns.get(spell_id, 0)),
			"queued": (spell_id == "heroicStrike" and run.heroic_queued)
				or (spell_id == "frenzy" and run.frenzy_queued),
		})
	return out


## Why a spell cannot be cast right now, or "" when it can. Czech, shown verbatim — the same
## contract `PlayerSpells.blocked_reason` has in the duel.
static func blocked_reason(run, spell_id: String) -> String:
	if run == null or run._state == null:
		return "Zadny souboj"
	var cid := class_id(run)
	if not PlayerSpells.is_implemented(spell_id):
		return "Kouzlo zatim neni v portu"
	if PlayerSpells.talent_level(run._state, cid, spell_id) <= 0:
		return "Kouzlo nemas naucene"
	if run.finished or run.hp <= 0:
		return "Souboj skoncil"
	if run.ww_active:
		return "Whirlwind bezi"
	if run.spell_gcd_ms > 0:
		return "Globalni cooldown"
	var cd := int(run.spell_cooldowns.get(spell_id, 0))
	if cd > 0:
		return "Cooldown %d s" % int(ceil(float(cd) / 1000.0))

	var def := PlayerSpells.spell_def(run._data, cid, spell_id)
	var cost := PlayerSpells.spell_cost(run._state, cid, spell_id, float(def.get("cost", 0)))
	if float(run.mana) < cost:
		return "Malo many"

	if bool(def.get("needsShield", false)):
		var shield: Dictionary = run._find_item.call(run._state.equip().get("shield"))
		if str(shield.get("type", "")) != "shield":
			return "Potrebujes stit"

	match spell_id:
		"doubleSwing":
			if run.off_weapon.is_empty():
				return "Potrebujes dve zbrane"
			if run._nearest_in_reach(run.reach_off, -1) < 0:
				return "Zadny nepritel v dosahu"
		"thunderClap", "shieldSlam", "pummel":
			if run._nearest_in_reach(run.reach_main, -1) < 0:
				return "Zadny nepritel v dosahu"
		"thunderBolt":
			if _nearest_within(run, SPELL_RANGE) < 0:
				return "Zadny nepritel v dosahu"
		"whirlwind":
			if run._nearest_in_reach(run.reach_main, -1) < 0:
				return "Zadny nepritel v dosahu"
		"spellReflect":
			# The run's own "the enemy is casting": a thrown orb is the only thing on this
			# battlefield that is already on its way. Nothing in the air = nothing to reflect.
			if _nearest_orb(run) < 0:
				return "Nepritel nekouzli"
	return ""


static func can_cast(run, spell_id: String) -> bool:
	return blocked_reason(run, spell_id) == ""


# ============================================================================ casting

## Cast a spell. Returns {ok, message, damage, spell}. The GCD and the spell's own cooldown are
## spent on ACCEPTANCE, before the effect — a refused cast costs nothing, exactly as in the duel.
static func cast(run, spell_id: String) -> Dictionary:
	var reason := blocked_reason(run, spell_id)
	if reason != "":
		return {"ok": false, "message": reason, "damage": 0, "spell": spell_id}

	var cid := class_id(run)
	var def := PlayerSpells.spell_def(run._data, cid, spell_id)
	var lv := maxi(PlayerSpells.spell_level(run._state, cid, spell_id), 1)
	var cost := PlayerSpells.spell_cost(run._state, cid, spell_id, float(def.get("cost", 0)))

	run.mana = maxf(0.0, float(run.mana) - cost)
	run._sync_mana()

	# GCD, then the spell's own cooldown. Pummel and Spell Reflect are the two whose cooldown
	# FALLS with talent level (8 s at lv1, 4 s at lv5) — the duel's rule, unchanged.
	run.spell_gcd_ms = int(round(float(def.get("gcd", 0.5)) * 1000.0))
	var cd_s := float(def.get("cooldown", 0))
	if cd_s > 0.0:
		if spell_id in ["pummel", "spellReflect"]:
			cd_s = maxf(4.0, 8.0 - float(lv - 1))
		run.spell_cooldowns[spell_id] = int(round(cd_s * 1000.0))

	return _apply(run, spell_id, lv, def)


static func _ok(spell_id: String, message: String, damage: int) -> Dictionary:
	return {"ok": true, "message": message, "damage": damage, "spell": spell_id}


static func _apply(run, spell_id: String, lv: int, def: Dictionary) -> Dictionary:
	match spell_id:
		"heroicStrike":
			# Queued, not instant: the next MAIN-HAND swing carries the multiplier, and the
			# roll is spent whether that swing lands or not (the same as the duel's queue).
			run.heroic_queued = true
			run._say_word("HEROIC STRIKE")
			return _ok(spell_id, "Heroic Strike pripraven na dalsi uder", 0)

		"frenzy":
			run.frenzy_queued = true
			return _ok(spell_id, "Frenzy pripraven na dalsi uder", 0)

		"doubleSwing":
			return _double_swing(run, lv)

		"thunderClap":
			return _thunder_clap(run, lv)

		"thunderBolt":
			return _thunder_bolt(run, lv)

		"shieldSlam":
			return _shield_slam(run, lv)

		"pummel":
			return _pummel(run, lv)

		"spellReflect":
			return _spell_reflect(run, lv)

		"whirlwind":
			return _whirlwind(run, lv)

		"battleShout":
			var dmg_pct := 5.0 + float(lv) * 5.0
			run.buff_dmg_pct = dmg_pct
			run.buff_dmg_ms = SHOUT_MS
			run.events.append(Sfx.CUE_SHOUT)
			run._say_word("BATTLE SHOUT")
			return _ok(spell_id, "Battle Shout: +%d%% poskozeni" % int(dmg_pct), 0)

		"defensiveShout":
			var table: Array = [50.0, 75.0, 100.0, 125.0, 150.0]
			var armor_pct: float = float(table[clampi(lv - 1, 0, 4)])
			run.buff_armor_pct = armor_pct
			run.buff_armor_ms = SHOUT_MS
			run.events.append(Sfx.CUE_SHOUT)
			run._say_word("DEFENSIVE SHOUT")
			return _ok(spell_id, "Defensive Shout: +%d%% obrany" % int(armor_pct), 0)

	return {"ok": false, "message": "Kouzlo nema efekt", "damage": 0, "spell": spell_id}


# ============================================================================ the effects

## Double Swing — both weapons at once on ONE body, both swing clocks spent, and the cooldown is
## the SLOWER weapon's interval (which is what stops it being spammed with two fast weapons).
static func _double_swing(run, lv: int) -> Dictionary:
	var idx: int = run._nearest_in_reach(run.reach_off, -1)
	if idx < 0:
		return {"ok": false, "message": "Zadny nepritel v dosahu", "damage": 0,
			"spell": "doubleSwing"}
	var mult := 1.0 + float(25 * lv) / 100.0
	var main_dmg := maxi(1, int(round(float(run._roll_damage(false)) * mult)))
	var off_dmg := maxi(1, int(round(float(run._roll_damage(true)) * mult)))
	var total := main_dmg + off_dmg
	run._hurt_monster(idx, total, "DOUBLE SWING")
	run.events.append(Sfx.cue_for_weapon(run.main_weapon, false))
	run._main_clock = maxf(run.main_swing, run.off_swing)
	run._off_clock = run._main_clock
	return _ok("doubleSwing", "Double Swing: %d" % total, total)


## Thunder Clap — the weapon's roll at `0.5 + 0.3 * lv`, plus the weapon's `skillDmg` multiplier,
## then a 20 % slow for `1 + lv` seconds. In the run a slow that only stretched an attack
## cooldown would be felt once every second and a half, so it stretches the walk too: the same
## intent (the kind is slowed) in a fight where movement is the resource.
static func _thunder_clap(run, lv: int) -> Dictionary:
	var idx: int = run._nearest_in_reach(run.reach_main, -1)
	if idx < 0:
		return {"ok": false, "message": "Zadny nepritel v dosahu", "damage": 0,
			"spell": "thunderClap"}
	var pct := 0.5 + float(lv) * 0.3
	var dmg := maxi(1, int(round(float(run._roll_damage(false)) * pct
		* _skill_dmg_mult(run))))
	run._slow_monster(idx, 20.0, (1 + lv) * 1000)
	run._hurt_monster(idx, dmg, "THUNDER CLAP")
	run.events.append(Sfx.CUE_THUNDER_CLAP)
	return _ok("thunderClap", "Thunder Clap: %d, slow na %d s" % [dmg, 1 + lv], dmg)


## Thunder Bolt — the duel's flat formula rather than a weapon one: 10 + level*3 + a weapon roll
## + twice STR, at 80 + lv*20 %. Stuns, and a stunned body neither walks nor hits.
static func _thunder_bolt(run, lv: int) -> Dictionary:
	var idx: int = _nearest_within(run, SPELL_RANGE)
	if idx < 0:
		return {"ok": false, "message": "Zadny nepritel v dosahu", "damage": 0,
			"spell": "thunderBolt"}
	var hero: Dictionary = run._state.hero()
	var str_total: float = float(int(hero.get("attrStr", 0))
		+ int(Progression._equip_attr(run._state.equip(), run._find_item, "str")))
	var base: float = 10.0 + floorf(float(hero.get("level", 1)) * 3.0) \
		+ float(Progression.weapon_dmg(run.rng, run.main_weapon)) + str_total * 2.0
	var dmg := maxi(1, int(round(base * float(80 + lv * 20) / 100.0)))
	var stun_ms := int(round((3.0 + float(lv - 1) * 0.5) * 1000.0))
	run._stun_monster(idx, stun_ms)
	run._hurt_monster(idx, dmg, "THUNDER BOLT")
	run.events.append(Sfx.CUE_THUNDER_BOLT)
	return _ok("thunderBolt", "Thunder Bolt: %d, omraceni" % dmg, dmg)


## Shield Slam — damage off the SHIELD's own range, not the weapon's (D2's Smite), plus a slow.
static func _shield_slam(run, lv: int) -> Dictionary:
	var idx: int = run._nearest_in_reach(run.reach_main, -1)
	if idx < 0:
		return {"ok": false, "message": "Zadny nepritel v dosahu", "damage": 0,
			"spell": "shieldSlam"}
	var shield: Dictionary = run._find_item.call(run._state.equip().get("shield"))
	var s_min := int(shield.get("baseDmgMin", 1))
	var s_max := maxi(int(shield.get("baseDmgMax", 2)), s_min)
	var roll: int = s_min + run.rng.randi_range(0, s_max - s_min)
	var pct := 60.0 + float(lv) * 20.0
	var dmg := maxi(1, int(round(float(roll) * pct / 100.0)))
	var slow_pct := 15.0 + float(lv) * 5.0
	var slow_ms := (2 + int(floor(float(lv) / 2.0))) * 1000
	run._slow_monster(idx, slow_pct, slow_ms)
	run._hurt_monster(idx, dmg, "SHIELD SLAM")
	run.events.append(Sfx.CUE_BLUNT_HIT)
	return _ok("shieldSlam", "Shield Slam: %d, slow %d%%" % [dmg, int(slow_pct)], dmg)


## Pummel — an interrupt, not a damage spell: the body's next attacks are blocked for `2 + lv`
## seconds. In the duel it also cancelled a cast in progress; the run's monsters have no cast
## clock, so the blocked window is the whole of it here.
static func _pummel(run, lv: int) -> Dictionary:
	var idx: int = run._nearest_in_reach(run.reach_main, -1)
	if idx < 0:
		return {"ok": false, "message": "Zadny nepritel v dosahu", "damage": 0,
			"spell": "pummel"}
	var block_ms := (2 + lv) * 1000
	run._block_monster(idx, block_ms)
	run._add_number((run.monsters[idx]["pos"] as Vector2) + Vector2(0, -30), "PUMMEL", "word")
	run.events.append(Sfx.CUE_DODGE)
	return _ok("pummel", "Pummel: blok utoku na %d s" % (2 + lv), 0)


## Spell Reflect — the run's cast in progress is an ORB IN FLIGHT: it is cancelled, and a fraction
## of its own damage (10 % per level) is thrown back at the body that threw it.
static func _spell_reflect(run, lv: int) -> Dictionary:
	var pi: int = _nearest_orb(run)
	if pi < 0:
		return {"ok": false, "message": "Nepritel nekouzli", "damage": 0, "spell": "spellReflect"}
	var orb: Dictionary = run.projectiles[pi]
	var raw := int(orb.get("dmg", 1))
	var owner_id := int(orb.get("owner", -1))
	run.projectiles.remove_at(pi)
	var dmg := maxi(1, int(round(float(raw) * 0.7 * float(10 * lv) / 100.0)))
	var idx: int = run._index_of_monster(owner_id)
	if idx >= 0:
		run._hurt_monster(idx, dmg, "REFLECT")
	run.events.append(Sfx.CUE_SHOUT)
	return _ok("spellReflect", "Spell Reflect: odrazeno %d" % dmg, dmg)


## Whirlwind — the flurry. `3 + lv` strikes, each on a deadline, a wrong press ending the run of
## them. The strikes are resolved by `answer_whirlwind`, not here: a flurry that finished inside
## one call would be a damage spell with extra steps, and the whole point is that it stops when
## the player gets one wrong.
static func _whirlwind(run, lv: int) -> Dictionary:
	var count := 3 + maxi(lv, 1)
	var dirs: Array = []
	var keys := ["tri", "circle", "cross", "square"]
	for _i in count:
		dirs.append(keys[run.rng.randi_range(0, keys.size() - 1)])
	run.start_whirlwind(dirs, WHIRLWIND_REACTION_MS)
	return _ok("whirlwind", "Whirlwind: %d uderu" % count, 0)


# ============================================================================ clocks

## Every clock a spell owns, ticked in ONE place — a buff whose timer nobody ticks never expires,
## and a cooldown that is never decremented is a spell that can be cast once. Driven by the run's
## fixed step, so a deadline is the same on every machine.
static func tick(run, dt: float) -> void:
	var ms := int(round(dt * 1000.0))
	if run.spell_gcd_ms > 0:
		run.spell_gcd_ms = maxi(0, run.spell_gcd_ms - ms)
	if not run.spell_cooldowns.is_empty():
		var keys: Array = run.spell_cooldowns.keys()
		for k in keys:
			var left := int(run.spell_cooldowns[k]) - ms
			if left <= 0:
				run.spell_cooldowns.erase(k)
			else:
				run.spell_cooldowns[k] = left

	if run.buff_dmg_ms > 0:
		run.buff_dmg_ms = maxi(0, run.buff_dmg_ms - ms)
		if run.buff_dmg_ms <= 0:
			run.buff_dmg_pct = 0.0
	if run.buff_armor_ms > 0:
		run.buff_armor_ms = maxi(0, run.buff_armor_ms - ms)
		if run.buff_armor_ms <= 0:
			run.buff_armor_pct = 0.0
	if run.frenzy_ms > 0:
		run.frenzy_ms = maxi(0, run.frenzy_ms - ms)
		if run.frenzy_ms <= 0:
			run.frenzy_stacks = 0

	_tick_mana(run, dt)
	if run.ww_active:
		run.ww_deadline_ms = maxi(0, run.ww_deadline_ms - ms)
		if run.ww_deadline_ms <= 0:
			run.whirlwind_timeout()


## Mana regen, the duel's own number: 0.3/s + INT*0.01 + gear `manaRegen`. The save stores mana as
## an INT, so it accumulates as a FRACTION — adding an int per tick rounds to zero and never ticks
## at all, which reads as "slow" and is actually "broken".
static func _tick_mana(run, dt: float) -> void:
	var hero: Dictionary = run._state.hero()
	if float(run.mana) >= float(run.max_mana):
		return
	var int_total := int(hero.get("attrInt", 0)) \
		+ int(Progression._equip_attr(run._state.equip(), run._find_item, "int"))
	var per_second := 0.3 + float(int_total) * 0.01 \
		+ float(int(Progression._equip_attr(run._state.equip(), run._find_item, "manaRegen")))
	run.mana = minf(float(run.max_mana), float(run.mana) + per_second * dt)
	run._sync_mana()


# ============================================================================ helpers

## Total `skillDmg` on weapon, rings and amulet, as a multiplier — the duel applies it to Thunder
## Clap only, and so does this.
static func _skill_dmg_mult(run) -> float:
	var total := 0
	for slot in ["weapon", "ring1", "ring2", "amulet"]:
		var item: Dictionary = run._find_item.call(run._state.equip().get(slot))
		if not item.is_empty():
			total += int(item.get("skillDmg", 0))
	if total <= 0:
		return 1.0
	return 1.0 + float(total) / 100.0


## The nearest body whose rim is inside `radius`, IGNORING facing. A bolt is not a swing.
static func _nearest_within(run, radius: float) -> int:
	if run == null:
		return -1
	var limit: float = radius + run.MON_RADIUS
	var best: float = limit * limit
	var found := -1
	for i in run.monsters.size():
		var d2: float = (run.monsters[i]["pos"] as Vector2).distance_squared_to(run.player_pos)
		if d2 <= best:
			best = d2
			found = i
	return found


## The orb closest to the hero — the one that is about to matter.
static func _nearest_orb(run) -> int:
	if run == null:
		return -1
	var best := INF
	var found := -1
	for i in run.projectiles.size():
		var d: float = (run.projectiles[i]["pos"] as Vector2).distance_to(run.player_pos)
		if d < best:
			best = d
			found = i
	return found