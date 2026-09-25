extends RefCounted
class_name Battle
## Battle — the arena encounter: who is fighting, at what stats, and what happens.
##
## This is the RULES half of the ported combat. It holds one fight's state (the
## enemy's HP, the hero's HP, swing clocks, debuffs) and advances it in discrete
## ticks. It draws nothing and plays no sound: the arena scene reads this and
## renders it.
##
## Splitting it this way is the point of the port. In the PWA the same numbers lived
## inside a 900-line `autoCombatLoop` that also moved DOM nodes, so no part of the
## combat could be tested. Here `battle.gd` runs headless under `test_combat.gd`,
## which is how the balance gets asserted at all.
##
## Timing: the PWA drove everything off `performance.now()` and requestAnimationFrame.
## A RefCounted has no _process, so the caller pumps `tick(delta_ms)`. Millisecond
## clocks, not frame counts, so the pace does not change with the frame rate.

const GameData := preload("res://scripts/data/game_data.gd")
const ItemGen := preload("res://scripts/items/item_gen.gd")
const Progression := preload("res://scripts/combat/progression.gd")
const PlayerSpells := preload("res://scripts/combat/player_spells.gd")
const Talents := preload("res://scripts/items/talents.gd")

## How many fights a zone takes before it is complete (the PWA's `af >= 10`).
const FIGHTS_PER_ZONE := 10

## The fight index within a zone that spawns a pack instead of a single monster.
## Champion pack at 5/10 (three champs), elite pack at 10/10 (elite + three slaves,
## the leader last).
const CHAMPION_PACK_FIGHT := 4
const ELITE_PACK_FIGHT := 9

## The last `minArea` a monster needs to be able to appear is the zone index.
var _data: Node
var prog: Progression

## --- encounter definition, built once per fight -----------------------------

var act_id := 0
var progress := 0              # zone index within the act
var area_fight := 0            # fight index within the zone, 0..9
var difficulty := 0
var is_boss := false
var is_elite := false
var is_pack := false

var enemy_name := ""
var enemy_face := ""
var enemy_attack_type := "melee"
var enemy_hp := 0.0
var enemy_max_hp := 0.0
var enemy_dmg_min := 0
var enemy_dmg_max := 0
var enemy_attack_speed := 2000
var enemy_block_chance := 0.0
var enemy_defense := 0
var enemy_resource := "mana"
var enemy_max_resource := 50.0
var enemy_resource_cur := 50.0
var enemy_spells: Array = []
var enemy_resists: Dictionary = {}
var enemy_dmg_reduction := 1.0     # Stone Skin: incoming physical damage multiplier
var elite_affix: Dictionary = {}
var elite_name := ""
## The monster's own TYPE (`critmaster`, `lifestealer`, `manastealer`, `poison`) and a
## boss's list of them. These are not decoration: the type changes what a landed hit
## DOES — a critmaster rolls a x2, a lifestealer heals itself for half the hit, a
## manastealer drains the hero's mana, a poison one leaves a DoT. A boss carries several.
var monster_type := ""
var boss_types: Array = []
## Satyr's flag: every melee hit applies a poison DoT on the hero. A monster without
## this keeps its poison to `poison_bolt`.
var passive_poison_weapon := false

## Pack members: the fight runs on the ACTIVE member, the rest wait. The leader is
## deliberately last, so an elite pack is three slaves and then the elite.
var pack_members: Array = []
var pack_active := 0

## --- running state -----------------------------------------------------------

## The fight's OWN clock: how many fixed steps have been ticked. The screen is what
## decides how many of these a real second contains, so this is the only handle a test
## has on "did the fight advance in real time or in frames".
var ticks_elapsed := 0

var hero_hp := 0.0
var hero_max_hp := 0.0
var ended := false
var won := false
var pending_kill := false

var player_swing_ms := 2000
var player_swing_elapsed := 0.0
var offhand_swing_ms := 0
var enemy_swing_ms := 2000
var enemy_swing_elapsed := 0.0

var offhand_turn := false        # dual wield alternates hands
var player_slow_pct := 0.0       # slow applied BY the enemy TO the hero
var player_slow_ms := 0
var enemy_slow_pct := 0.0        # chill applied by a cold weapon
var enemy_slow_ms := 0

## Damage over time: the hero's poison on the enemy.
var enemy_dot := 0
var enemy_dot_ticks := 0
var enemy_dot_clock := 0.0

## The hero's DODGE (Evasion): +50 % for 10 s on top of the passive DEX dodge. The PWA
## modelled it as a coin flip in the enemy's attack path; kept as a percentage here so
## the passive and the buff compose in one place (`hero_dodge_chance`).
var hero_dodge_buff_ms := 0
const HERO_DODGE_BUFF_PCT := 50.0
## The hero's ATTACK SPEED buff (Assassin's Speed Boost), as a percentage and a clock.
var hero_speed_boost_pct := 0.0
var hero_speed_boost_ms := 0

## Poison on the HERO (a poison monster's melee, Satyr's poisoned weapon, the
## `poison_bolt` spell). Per-tick damage and a tick count; re-applying refreshes.
var hero_dot := 0
var hero_dot_ticks := 0
var hero_dot_clock := 0.0

## Cursed (elite): the hero takes 50 % more physical damage while it lasts.
var amplify_dmg_ms := 0
## The enemy's own Defensive Shout (a caster buff): 30 % off incoming damage for 8 s.
var enemy_defensive_shout_ms := 0
## The enemy's Thorn Shield: returns a flat 5-10 to whoever hits it.
var enemy_thorn_shield_ms := 0
## The enemy's Faerie Fire: halves what the hero's spells get through its resistances.
var enemy_faerie_fire_ms := 0
## The enemy's Battle Shout: +50 % on its own hits.
var enemy_battle_shout_ms := 0
## The enemy's Evasion: 30 % dodge against the hero's swings.
var enemy_evasion_ms := 0
## The enemy's Poison Weapon: a DoT added to its melee hits.
var enemy_poison_weapon_ms := 0
var enemy_poison_weapon_dmg := 0

## The Assassin's combo points: spent by Eviscerate, Kidney Shot, Speed Boost and
## Poison Explosion, earned by Sinister Strike. On the SAVE in the PWA (it survives a
## fight), so it stays on `state.data` and is only read here.
##
## `activeSchool` is the mage's spell school, also on the save; it decides which resist
## one of his spells is rolled against, and it is set by the spell that is cast.

## Enemy casting. A caster monster's swing is a spell, not a melee hit: it spends
## the swing wind-up casting and the effect lands when the cast time is up. The PWA
## wove a melee swing and a follow-up cast together; one cast per swing is the same
## pace and one clock instead of three.
var cast_spell_id := ""
var cast_elapsed := 0.0
var cast_time := 0.0

## Queued abilities consumed by the next swing (Heroic Strike, Frenzy).
var heroic_strike_queued := false
var frenzy_queued := false
var frenzy_stacks := 0
var frenzy_speed_pct := 0.0
## Frenzy stacks expire 10 s after the last one, and the SPEED has to be recomputed on
## the swing interval when they do — a buff that only changes a number in the log is
## not a buff.
var frenzy_ms := 0

var battle_shout_dmg_pct := 0.0
var battle_shout_ms := 0
var defensive_shout_armor_pct := 0.0
var defensive_shout_ms := 0

## --- class spell bookkeeping ------------------------------------------------
## Cooldowns live HERE rather than on the save, because the PWA cleared them on
## entering town (`resetSessionState`), so they are per-session. Keeping them off the
## save also means quitting cannot launder an unspent cooldown.
var spell_cooldowns: Dictionary = {}
var spell_gcd_ms := 0
var player_cast_spell := ""
var player_cast_ms := 0
var player_cast_elapsed := 0.0

## Enemy control: a stun stops its swings entirely, and a pummel blocks recasting.
var enemy_stun_ms := 0
var enemy_cast_blocked_ms := 0
## The PWA made the FIRST enemy swing a plain melee hit and only decided about casting
## from the second one on. A boss never used the caster path at all.
var enemy_first_swing_done := false

## Accumulator for mana regen: the save stores mana as an int, so a sub-1-per-second
## regen has to be carried as a fraction or it rounds away and never ticks.
var mana_regen_frac := 0.0

var rng := RandomNumberGenerator.new()

## Every damage number, miss and heal this fight produced, in order. The arena
## renders it; the test asserts on it. Text only — no emoji, no colour codes beyond
## what the renderer needs.
var log: Array = []

## Set by `_spawn` so the caller can attach gold/xp bookkeeping.
var monster_level_value := 1


func _init(game_data: Node, seed_value: int = 0) -> void:
	_data = game_data
	prog = Progression.new(game_data)
	if seed_value != 0:
		rng.seed = seed_value


# --- encounter setup ---------------------------------------------------------

## Build the fight for (act, zone, fight index). Returns false when the act does
## not exist.
func setup(state, find_item: Callable) -> bool:
	var act: Dictionary = _data.act_by_id(act_id)
	if act.is_empty():
		return false
	difficulty = int(state.data.get("difficulty", 0))
	progress = int(state.data["locationProgress"][act_id])
	area_fight = int(state.data["areaFightProgress"][act_id])

	is_boss = prog.is_boss_zone(progress, act_id)
	is_elite = not is_boss and area_fight >= ELITE_PACK_FIGHT
	var is_champion_pack := not is_boss and not is_elite and area_fight == CHAMPION_PACK_FIGHT
	is_pack = not is_boss and (is_elite or is_champion_pack)
	monster_level_value = prog.monster_level(act_id, progress, difficulty)

	var diffs: Array = _data.difficulties()
	var diff_mult := float((diffs[difficulty] as Dictionary).get("mult", 1.0)) \
		if difficulty < diffs.size() else 1.0
	var zone_mult := prog.zone_mult(progress, difficulty)

	var hp := 0.0
	if is_boss:
		var boss: Dictionary = act.get("boss", {})
		hp = float(boss.get("hp", 500)) * diff_mult
		enemy_dmg_min = int(boss.get("dmgMin", 12))
		enemy_dmg_max = int(boss.get("dmgMax", 18))
		enemy_attack_speed = int(boss.get("attackSpeed", 1800))
		enemy_block_chance = float(boss.get("blockChance", 0))
		enemy_resource = str(boss.get("resource", "mana"))
		enemy_max_resource = float(boss.get("maxResource", 200))
		enemy_spells = (boss.get("spells", []) as Array).duplicate()
		enemy_face = str(boss.get("face", ""))
		enemy_name = str(boss.get("name", "Boss"))
		enemy_attack_type = str(boss.get("attackType", "melee"))
		enemy_defense = int(act.get("monsterDefense", 0))
		enemy_resists = (act.get("resists", {}) as Dictionary).duplicate()
		# A boss carries a LIST of types, and all of them apply to every hit.
		boss_types = (boss.get("types", []) as Array).duplicate()
	else:
		var mon: Dictionary = _pick_monster(int(act.get("theme", 0)), progress)
		if mon.is_empty():
			return false
		# The 2.0 multiplier here is the PWA's: a zone fight takes ~2x the monster
		# table's HP so a fight lasts longer than one swing.
		hp = round(float(mon.get("hp", 80)) * diff_mult * 2.0 * zone_mult)
		enemy_dmg_min = int(mon.get("dmgMin", 5))
		enemy_dmg_max = int(mon.get("dmgMax", 10))
		enemy_attack_speed = int(mon.get("attackSpeed", 2000))
		enemy_block_chance = float(mon.get("blockChance", 0))
		enemy_resource = str(mon.get("resource", "mana"))
		enemy_max_resource = float(mon.get("maxResource", 50))
		enemy_spells = (mon.get("spells", []) as Array).duplicate()
		enemy_face = str(mon.get("face", ""))
		enemy_name = str(mon.get("name", "Monster"))
		enemy_attack_type = str(mon.get("attackType", "melee"))
		enemy_defense = int(mon.get("defense", 0))
		enemy_resists = (mon.get("resists", {}) as Dictionary).duplicate()
		monster_type = str(mon.get("type", ""))
		passive_poison_weapon = bool(mon.get("passivePoisonWeapon", false))

		if is_elite:
			hp = round(hp * 2.5)
			enemy_dmg_min = int(round(float(enemy_dmg_min) * 1.5))
			enemy_dmg_max = int(round(float(enemy_dmg_max) * 1.5))
			enemy_max_resource = round(enemy_max_resource * 1.5)
			var extra: String = _roll_elite_spell(int(act.get("theme", 0)), enemy_spells)
			if extra != "":
				enemy_spells.append(extra)
			elite_affix = _roll_elite_affix()
			elite_name = "%s %s %s" % [
				_pick(_data.table("ELITE_PREFIXES", [])),
				_pick(_data.table("ELITE_SUFFIXES", [])),
				_pick(_data.table("ELITE_APPELATIONS", [])),
			]
			_apply_elite_affix()

	var boss_hp_mult := 1.0
	var boss_dmg_mult := 1.0
	if is_boss:
		var affixes := _roll_boss_affixes()
		for a in affixes:
			match str(a.get("name", "")):
				"Indestructible":
					boss_hp_mult += 0.5
				"Fiery", "Icy":
					boss_dmg_mult += 1.0
				"Swift":
					boss_dmg_mult += 0.5

	# Boss HP gets the PWA's x4 on top of everything.
	var base_hp: float = roundf(hp * 4.0) if is_boss else roundf(hp)
	enemy_max_hp = roundf(base_hp * boss_hp_mult)
	enemy_hp = enemy_max_hp
	enemy_dmg_min = int(round(float(enemy_dmg_min) * boss_dmg_mult))
	enemy_dmg_max = int(round(float(enemy_dmg_max) * boss_dmg_mult))
	enemy_resource_cur = enemy_max_resource

	if is_pack and not is_boss:
		_build_pack(is_champion_pack, int(act.get("theme", 0)), hp, diff_mult, zone_mult)

	# Bestiary — the PWA records every face the player has met.
	if not is_boss and enemy_face != "":
		_record_encounter(state, enemy_face)
	elif is_boss:
		var boss_face := str((act.get("boss", {}) as Dictionary).get("face", ""))
		if boss_face != "":
			_record_encounter(state, boss_face)

	hero_max_hp = float(ItemGen.new(_data).hero_max_hp(state.hero(), state.equip(), find_item))
	hero_hp = minf(float(state.hero().get("hp", hero_max_hp)), hero_max_hp)

	_pick_enemy_spells_sanity()
	_reset_clocks()
	# A CASTER monster opens with a spell, not a melee swing — the PWA did this in
	# startLocation for non-boss casters. Without it the first enemy action is always a
	# melee hit and a caster reads as a melee monster for the first few seconds.
	enemy_first_swing_done = is_boss
	if enemy_attack_type == "caster" and not is_boss:
		var opener := _choose_spell()
		if opener != "":
			var spells_tbl: Dictionary = _data.enemy_spells()
			var sp: Dictionary = spells_tbl.get(opener, {})
			cast_spell_id = opener
			cast_time = float(sp.get("castTime", 1200))
			cast_elapsed = 0.0
	return true


func _reset_clocks() -> void:
	player_swing_elapsed = 0.0
	enemy_swing_ms = prog.enemy_swing_time(enemy_attack_speed, enemy_slow_pct, enemy_slow_ms)
	enemy_swing_elapsed = 0.0
	ended = false
	won = false
	pending_kill = false
	cast_spell_id = ""
	cast_elapsed = 0.0
	cast_time = 0.0


## The player's swing interval for this fight, from the equipped weapon(s). Dual
## wield runs ONE timer that alternates hands, averaged and given D2's 0.85 bonus.
##
## Also stores the main-hand weapon TYPE, because the duel arena's reach and closing
## speed are keyed off it (`getWeaponReach()` reads the equipped weapon live in the PWA,
## and the weapon cannot change mid-fight).
func apply_swing_timers(state, find_item: Callable) -> void:
	var cls: Dictionary = _data.class_by_id(str(state.data.get("heroClass", "")))
	var main_weapon: Dictionary = find_item.call(state.equip().get("weapon", "fists"))
	weapon_type = str(main_weapon.get("weaponType", "fists")) if not main_weapon.is_empty() else "fists"
	var dex_total := int(state.hero().get("attrDex", 0)) \
		+ Progression._equip_attr(state.equip(), find_item, "dex")
	var gloves: Dictionary = find_item.call(state.equip().get("gloves"))
	var glove_ias := int(gloves.get("ias", 0)) if not gloves.is_empty() else 0

	player_swing_ms = Progression.swing_time(rng, main_weapon, dex_total, glove_ias,
		state.data.get("_speedBoostPct", 0.0))
	offhand_swing_ms = 0
	if bool(cls.get("dualWield", false)):
		var off_item: Dictionary = find_item.call(state.equip().get("shield"))
		if not off_item.is_empty() and off_item.has("weaponType"):
			var off_ms := Progression.swing_time(rng, off_item, dex_total, glove_ias, 0.0)
			offhand_swing_ms = off_ms
			player_swing_ms = int(round((float(player_swing_ms) + float(off_ms)) / 2.0 * 0.85))
	player_swing_elapsed = 0.0
	enemy_swing_ms = prog.enemy_swing_time(enemy_attack_speed, enemy_slow_pct, enemy_slow_ms)
	enemy_swing_elapsed = 0.0
	reset_gap()


# --- monster selection -------------------------------------------------------

## getFloorMonsterSet — a monster from the act's theme pool that may appear at this
## zone, weighted so recently-seen monsters are less likely. The PWA kept the
## last-seen zone per theme ON THE SAVE, which is why this writes back to state.
func _pick_monster(theme: int, zone: int) -> Dictionary:
	var pool: Array = []
	for m in _data.monsters_for_theme(theme):
		if int(m.get("minArea", 0)) <= zone:
			pool.append(m)
	if pool.is_empty():
		return {}
	var seen: Dictionary = _monster_seen
	var weights: Array = []
	for i in pool.size():
		if not seen.has(i):
			weights.append(10)
		else:
			var floors_ago := zone - int(seen[i])
			weights.append(maxi(1, 10 - floors_ago * 2))
	var total := 0
	for w in weights:
		total += int(w)
	var roll := rng.randi_range(1, maxi(total, 1))
	var idx := 0
	for i in pool.size():
		roll -= int(weights[i])
		if roll <= 0:
			idx = i
			break
	seen[idx] = zone
	return pool[idx]


## The per-theme last-seen table. The PWA kept it on the save so the weighting
## survives a reload; the owner pushes it in with set_monster_seen().
var _monster_seen: Dictionary = {}


func set_monster_seen(seen: Dictionary) -> void:
	_monster_seen = seen


func monster_seen() -> Dictionary:
	return _monster_seen


func _roll_elite_spell(theme: int, existing: Array) -> String:
	var ids: Array = []
	for m in _data.monsters_for_theme(theme):
		for s in m.get("spells", []):
			if not ids.has(s):
				ids.append(s)
	var spells: Dictionary = _data.enemy_spells()
	var candidates: Array = []
	for id in ids:
		if existing.has(id) or not spells.has(id):
			continue
		var sp: Dictionary = spells[id]
		if enemy_resource == "rage":
			if int(sp.get("rageCost", 0)) > 0:
				candidates.append(id)
		elif int(sp.get("manaCost", 0)) > 0:
			candidates.append(id)
	if candidates.is_empty():
		return ""
	return str(_pick(candidates))


func _roll_elite_affix() -> Dictionary:
	var pool: Array = _data.table("ELITE_AFFIXES", [])
	return _pick(pool) if not pool.is_empty() else {}


## D2 elite mods. The affix writes into the encounter's stats; the resist and
## damage-reduction parts are read back at damage time.
func _apply_elite_affix() -> void:
	if elite_affix.is_empty():
		return
	if elite_affix.has("hpMult"):
		enemy_hp = round(enemy_hp * float(elite_affix["hpMult"]))
	if elite_affix.has("dmgMult"):
		enemy_dmg_min = int(round(float(enemy_dmg_min) * float(elite_affix["dmgMult"])))
		enemy_dmg_max = int(round(float(enemy_dmg_max) * float(elite_affix["dmgMult"])))
	if elite_affix.has("attackSpeedMult"):
		enemy_attack_speed = int(round(float(enemy_attack_speed) * float(elite_affix["attackSpeedMult"])))
	if elite_affix.has("resistSelf"):
		enemy_resists[str(elite_affix["resistSelf"])] = 1.5
	if elite_affix.has("drMult"):
		enemy_dmg_reduction = float(elite_affix["drMult"])


## rollBossAffixes — one, or two 40% of the time, no duplicates.
func _roll_boss_affixes() -> Array:
	var pool: Array = _data.table("BOSS_AFFIXES", [])
	var count := 1 + (1 if rng.randf() < 0.4 else 0)
	var out: Array = []
	for _i in count:
		if pool.is_empty():
			break
		var a: Dictionary = _pick(pool)
		var dup := false
		for e in out:
			if str(e.get("name", "")) == str(a.get("name", "")):
				dup = true
		if not dup:
			out.append(a)
	return out


## Champion pack = three champs at 1.6x HP / 1.3x damage. Elite pack = three slaves
## (normal stats) and the elite LEADER LAST, so the fight ends on the elite.
##
## Every member carries its OWN full stat block, because `pack_advance()` hands the fight
## over to the next one: a slave list of HP and damage alone left the elite leader with a
## slave's attack speed, defence and spells.
func _build_pack(champion: bool, theme: int, base_hp: float, diff_mult: float,
		zone_mult: float) -> void:
	var m: Dictionary = _pick_monster(theme, progress)
	if m.is_empty():
		return
	var normal_hp: float = roundf(float(m.get("hp", 80)) * diff_mult * 2.0 * zone_mult)
	pack_members = []
	if champion:
		for _i in 3:
			pack_members.append({
				"name": "%s Champion" % str(m.get("name", "Monster")),
				"face": str(m.get("face", "")),
				"hp": round(normal_hp * 1.6), "maxHp": round(normal_hp * 1.6),
				"dmgMin": int(round(float(m.get("dmgMin", 5)) * 1.3)),
				"dmgMax": int(round(float(m.get("dmgMax", 10)) * 1.3)),
				"attackSpeed": int(m.get("attackSpeed", 2000)),
				"defense": int(m.get("defense", 0)),
				"blockChance": float(m.get("blockChance", 0.0)),
				"attackType": str(m.get("attackType", "melee")),
				"spells": (m.get("spells", []) as Array).duplicate(),
				"resists": (m.get("resists", {}) as Dictionary).duplicate(),
				"type": str(m.get("type", "")),
				"passivePoisonWeapon": bool(m.get("passivePoisonWeapon", false)),
				"resource": str(m.get("resource", "mana")),
				"maxResource": float(m.get("maxResource", 50)),
				"dead": false,
			})
	else:
		var aura_boost := 1.0
		if elite_affix.has("auraDmgMult"):
			aura_boost = float(elite_affix["auraDmgMult"])
		for _i in 3:
			pack_members.append({
				"name": "%s Slave" % str(m.get("name", "Monster")),
				"face": str(m.get("face", "")),
				"hp": normal_hp, "maxHp": normal_hp,
				"dmgMin": int(round(float(m.get("dmgMin", 5)) * aura_boost)),
				"dmgMax": int(round(float(m.get("dmgMax", 10)) * aura_boost)),
				"attackSpeed": int(m.get("attackSpeed", 2000)),
				"defense": int(m.get("defense", 0)),
				"blockChance": float(m.get("blockChance", 0.0)),
				"attackType": str(m.get("attackType", "melee")),
				"spells": (m.get("spells", []) as Array).duplicate(),
				"resists": (m.get("resists", {}) as Dictionary).duplicate(),
				"type": str(m.get("type", "")),
				"passivePoisonWeapon": bool(m.get("passivePoisonWeapon", false)),
				"resource": str(m.get("resource", "mana")),
				"maxResource": float(m.get("maxResource", 50)),
				"dead": false,
			})
		# The leader is the ELITE, so it carries the elite's own stats (already scaled by
		# the affixes when the encounter was built).
		pack_members.append({
			"name": elite_name if elite_name != "" else str(m.get("name", "Monster")),
			"face": str(m.get("face", "")),
			"hp": enemy_max_hp, "maxHp": enemy_max_hp,
			"dmgMin": enemy_dmg_min, "dmgMax": enemy_dmg_max,
			"attackSpeed": enemy_attack_speed,
			"defense": enemy_defense,
			"blockChance": enemy_block_chance,
			"attackType": enemy_attack_type,
			"spells": enemy_spells.duplicate(),
			"resists": enemy_resists.duplicate(),
			"type": monster_type,
			"passivePoisonWeapon": passive_poison_weapon,
			"resource": enemy_resource,
			"maxResource": enemy_max_resource,
			"isLeader": true, "dead": false,
		})
	pack_active = 0


func pack_size() -> int:
	return pack_members.size() if not pack_members.is_empty() else 1


## Death of an active pack member. The next LIVING one steps up and takes the fight over —
## the PWA did this through `packTryAdvance` before it ever reached the victory path.
##
## A member needs its OWN stats carried over, not just its HP: the port used to keep the
## dead member's attack speed, defence, spells and monster type, so the elite LEADER of a
## pack swung as fast as a slave and lost its own spell list. The fight that "worked" was
## measuring the wrong monster entirely.
##
## Returns false when the pack is finished, which lets the normal victory path run.
func pack_advance() -> bool:
	if pack_members.is_empty():
		return false
	pack_members[pack_active]["dead"] = true
	for i in range(pack_active + 1, pack_members.size()):
		if not bool(pack_members[i]["dead"]):
			pack_active = i
			var m: Dictionary = pack_members[i]
			enemy_name = str(m["name"])
			enemy_face = str(m["face"])
			enemy_max_hp = float(m["maxHp"])
			enemy_hp = enemy_max_hp
			enemy_dmg_min = int(m["dmgMin"])
			enemy_dmg_max = int(m["dmgMax"])
			enemy_attack_speed = int(m.get("attackSpeed", enemy_attack_speed))
			enemy_defense = int(m.get("defense", enemy_defense))
			enemy_block_chance = float(m.get("blockChance", 0.0))
			enemy_attack_type = str(m.get("attackType", "melee"))
			enemy_spells = (m.get("spells", []) as Array).duplicate()
			enemy_resists = (m.get("resists", {}) as Dictionary).duplicate()
			monster_type = str(m.get("type", ""))
			passive_poison_weapon = bool(m.get("passivePoisonWeapon", false))
			enemy_resource = str(m.get("resource", enemy_resource))
			enemy_max_resource = float(m.get("maxResource", enemy_max_resource))
			enemy_resource_cur = enemy_max_resource
			enemy_dot = 0
			enemy_dot_ticks = 0
			enemy_dot_clock = 0.0
			# The new member gets a fresh clock: it must not inherit the dead one's
			# wind-up and hit the instant it appears.
			enemy_swing_elapsed = 0.0
			enemy_swing_ms = prog.enemy_swing_time(enemy_attack_speed, enemy_slow_pct, enemy_slow_ms)
			cast_spell_id = ""
			cast_elapsed = 0.0
			cast_time = 0.0
			enemy_first_swing_done = false
			return true
	return false


# --- the duel arena's distance ------------------------------------------------

## The PWA's Duel Arena: the fight starts at MAXIMUM separation and the hero walks in.
## While he is out of his weapon's reach the swing clock still runs, but the swing is
## RESET instead of landing — "no more swinging at thin air". The first hit lands when he
## arrives, measured in the PWA at 624-1024 ms depending on the weapon.
##
## These numbers are the PWA's, verbatim (`CLOSE_SPEED` / `WEAPON_REACH` in its game.ts).
## Porting the walk-in is not decoration: without it the port's hero hits the instant the
## fight starts, which is exactly the "the swing timers do not work" symptom.
const WEAPON_REACH := {"fists": 0.26, "claws": 0.26, "blade": 0.20, "axe": 0.16,
	"blunt": 0.16, "staff": 0.92}
const CLOSE_SPEED := {"fists": 0.85, "claws": 0.80, "blade": 0.62, "axe": 0.52,
	"blunt": 0.48, "staff": 0.70}
## A melee monster walks in too, so the gap closes faster; a caster backs away and the
## hero has to close it alone.
const ENEMY_CLOSE_BONUS := 0.35
## A melee monster only reaches the hero in contact; a caster casts from anywhere.
const ENEMY_REACH := 0.24

var gap := 1.0                   # 1 = maximum separation, 0 = contact
var weapon_type := "fists"


func reset_gap() -> void:
	gap = 1.0


## How fast the gap closes right now, in gap-units per SECOND. Exposed because the renderer
## has to project the approach between two ticks: `gap` itself only moves inside a tick, so a
## hero placed straight off it walked in 100 ms hops (measured: 10 moves in 60 frames) while
## the engine drew 60. A caster enemy retreats, which is why the enemy's walk-in is a BONUS
## to the closing speed rather than a symmetric change.
func gap_speed() -> float:
	var speed := float(CLOSE_SPEED.get(weapon_type, 0.6))
	# A boss keeps the PWA's old geometry and does not walk in; a caster backs away.
	if not is_boss and enemy_attack_type != "caster":
		speed += ENEMY_CLOSE_BONUS
	return speed


## Close the distance by `delta_ms`. Returns true if it moved — the arena re-places the
## hero off this.
func advance_gap(delta_ms: float) -> bool:
	var next := maxf(0.0, gap - gap_speed() * (delta_ms / 1000.0))
	if is_equal_approx(next, gap):
		return false
	gap = next
	return true


func weapon_reach() -> float:
	return float(WEAPON_REACH.get(weapon_type, 0.2))


## Can the hero land a swing right now? Out of reach the swing is discarded, not held.
func player_in_reach() -> bool:
	return gap <= weapon_reach()


## Can the enemy reach the hero? A boss keeps the PWA's old geometry (always), and a
## caster casts from any distance.
func enemy_in_reach() -> bool:
	if is_boss:
		return true
	if enemy_attack_type == "caster":
		return true
	return gap <= ENEMY_REACH


# --- the tick ----------------------------------------------------------------

## Advance the fight by `delta_ms`. The caller pumps this every frame; nothing here
## sleeps or schedules. Returns true while the fight is live.
func tick(delta_ms: float, state, find_item: Callable) -> bool:
	if ended:
		return false
	ticks_elapsed += 1
	if pending_kill:
		# The PWA delayed the kill by 300 ms so the death animation could play. The
		# arena keeps that by simply not ending until the caller resumes us.
		pending_kill = false
		# A PACK DOES NOT END WHEN ONE MEMBER DIES. The next living member steps up and the
		# fight goes on — the leader is LAST, so an elite pack is four kills. The port
		# declared victory on the first death here, which is the whole reason a pack fight
		# was one enemy long and the win "did not work".
		if is_pack and pack_advance():
			return true
		_finish(true, state, find_item)
		return false

	_tick_dots(delta_ms)
	_tick_spell_clocks(delta_ms, state, find_item)
	advance_gap(delta_ms)

	player_swing_elapsed += delta_ms
	enemy_swing_elapsed += delta_ms
	if player_slow_ms > 0:
		player_slow_ms = maxi(0, player_slow_ms - int(delta_ms))
		if player_slow_ms == 0:
			player_slow_pct = 0.0
	if enemy_slow_ms > 0:
		enemy_slow_ms = maxi(0, enemy_slow_ms - int(delta_ms))
		if enemy_slow_ms == 0:
			enemy_slow_pct = 0.0
			enemy_swing_ms = prog.enemy_swing_time(enemy_attack_speed, 0.0, 0)

	# Poison can finish the enemy between swings.
	if enemy_hp <= 0.0:
		_on_enemy_dead(state, find_item)
		return false

	var eff_player_ms := float(player_swing_ms)
	if player_slow_pct > 0.0 and player_slow_ms > 0:
		eff_player_ms = round(eff_player_ms / (1.0 - player_slow_pct / 100.0))
	# Frenzy shortens the swing rather than adding damage to it, so the reduction is
	# applied to the interval the tick compares against.
	if frenzy_speed_pct > 0.0:
		eff_player_ms = maxf(450.0, round(eff_player_ms * (1.0 - frenzy_speed_pct / 100.0)))
	# The Assassin's Speed Boost, on the same hook. It is a flat percentage off the
	# interval, which the PWA applied when the spell was CAST; here it is read every
	# tick so the buff's expiry restores the pace by itself.
	if hero_speed_boost_pct > 0.0 and hero_speed_boost_ms > 0:
		eff_player_ms = maxf(450.0, round(eff_player_ms * (1.0 - hero_speed_boost_pct / 100.0)))

	if player_swing_elapsed >= eff_player_ms:
		player_swing_elapsed -= eff_player_ms
		# Out of reach the swing is discarded and the clock restarted, which is what the
		# PWA did: the hero is still walking in, so the first hit lands when he arrives.
		if not player_in_reach():
			player_swing_elapsed = 0.0
		else:
			player_attack(state, find_item)
			if ended or enemy_hp <= 0.0:
				return not ended

	# A stunned enemy does not swing, and its swing clock does not advance either.
	if enemy_stun_ms <= 0 and enemy_swing_elapsed >= float(enemy_swing_ms):
		enemy_swing_elapsed -= float(enemy_swing_ms)
		# Melee monsters only reach the hero in contact; a caster casts from anywhere.
		if not enemy_in_reach():
			enemy_swing_elapsed = 0.0
		else:
			enemy_attack(state, find_item)

	# A started cast resolves on its own clock, so a slow enemy still lands it.
	if cast_spell_id != "":
		cast_elapsed += delta_ms
		if cast_elapsed >= cast_time:
			_resolve_cast(state, find_item)

	return not ended


## Everything that runs on a clock the player's spells control: the two cooldowns, the
## queued buffs' durations, the enemy's stun and cast block, the hero's mana regen and a
## spell the hero has mid-cast.
##
## All of it is in one place because every one of these was a silent failure mode: a
## buff whose timer is never ticked never expires, and a stun whose timer is never
## ticked is permanent.
func _tick_spell_clocks(delta_ms: float, state, find_item: Callable) -> void:
	var dt := int(delta_ms)

	if spell_gcd_ms > 0:
		spell_gcd_ms = maxi(0, spell_gcd_ms - dt)
	for spell_id in spell_cooldowns.keys():
		var left := int(spell_cooldowns[spell_id]) - dt
		if left <= 0:
			spell_cooldowns.erase(spell_id)
		else:
			spell_cooldowns[spell_id] = left

	# Shouts and Frenzy. Each recomputes what it changed, so a buff that ends puts the
	# numbers back rather than leaving the fight permanently faster or stronger.
	if battle_shout_ms > 0:
		battle_shout_ms = maxi(0, battle_shout_ms - dt)
		if battle_shout_ms == 0:
			battle_shout_dmg_pct = 0.0
	if defensive_shout_ms > 0:
		defensive_shout_ms = maxi(0, defensive_shout_ms - dt)
		if defensive_shout_ms == 0:
			defensive_shout_armor_pct = 0.0
	if frenzy_ms > 0:
		frenzy_ms = maxi(0, frenzy_ms - dt)
	# Guard on the SPEED rather than the timer: a speed bonus with no timer behind it
	# would be permanent, and that is the one shape of this bug that is invisible in a
	# fight that ends quickly. Self-healing rather than trusting the pair to stay in sync.
	if frenzy_ms <= 0 and frenzy_speed_pct > 0.0:
		frenzy_stacks = 0
		frenzy_speed_pct = 0.0

	if enemy_stun_ms > 0:
		enemy_stun_ms = maxi(0, enemy_stun_ms - dt)
	if enemy_cast_blocked_ms > 0:
		enemy_cast_blocked_ms = maxi(0, enemy_cast_blocked_ms - dt)

	# The monster's own buffs, on the same clock as everything else. Without these the
	# Thorn Shield and the shouts would never expire — the exact "permanent buff" failure
	# the hero's side already had a test for.
	for key in ["enemy_defensive_shout_ms", "enemy_battle_shout_ms", "enemy_thorn_shield_ms",
			"enemy_faerie_fire_ms", "enemy_evasion_ms", "enemy_poison_weapon_ms",
			"amplify_dmg_ms", "hero_dodge_buff_ms", "hero_speed_boost_ms"]:
		var left := int(get(key)) - dt
		if left <= 0:
			set(key, 0)
			if key == "enemy_poison_weapon_ms":
				enemy_poison_weapon_dmg = 0
			if key == "hero_speed_boost_ms":
				hero_speed_boost_pct = 0.0
		else:
			set(key, left)

	# Enemy resource regen. The PWA ran this on a 100 ms interval: mana at 0.5/s so a
	# caster can eventually cast again, energy at 1.5/s, and RAGE only from being hit.
	# Without it a caster spends its pool in the first few swings and then only ever
	# melees for the rest of the fight, which is not what the PWA did.
	if enemy_max_resource > 0.0 and enemy_resource_cur < enemy_max_resource:
		if enemy_resource == "mana":
			enemy_resource_cur = minf(enemy_max_resource, enemy_resource_cur + 0.5 * delta_ms / 1000.0)
		elif enemy_resource == "energy":
			enemy_resource_cur = minf(enemy_max_resource, enemy_resource_cur + 1.5 * delta_ms / 1000.0)

	# Poison on the HERO ticks once a second, like the enemy's.
	if hero_dot_ticks > 0:
		hero_dot_clock += delta_ms
		while hero_dot_clock >= 1000.0 and hero_dot_ticks > 0:
			hero_dot_clock -= 1000.0
			hero_dot_ticks -= 1
			hero_hp -= float(hero_dot)
			_note("HERO POISON", hero_dot, true)
			if hero_hp <= 0.0:
				_finish(false, state, find_item)
				return

	# Mana regen, the PWA's 0.3/s plus 0.01 per INT point, both per second. It has to be
	# accumulated as a FRACTION: the save stores mana as an int, so an int-only regen of
	# under 1 per second would round to zero and never tick at all.
	var hero: Dictionary = state.hero()
	var max_mana := int(hero.get("maxMana", 0))
	if max_mana > 0 and float(hero.get("mana", 0)) < float(max_mana):
		var int_total := int(hero.get("attrInt", 0)) + _equip_stat(state.equip(), find_item, "int")
		var per_second := 0.3 + float(int_total) * 0.01 + float(_equip_stat(state.equip(), find_item, "manaRegen"))
		mana_regen_frac += per_second * delta_ms / 1000.0
		if mana_regen_frac >= 1.0:
			var whole := int(floor(mana_regen_frac))
			mana_regen_frac -= float(whole)
			hero["mana"] = mini(max_mana, int(hero.get("mana", 0)) + whole)

	# A spell the hero started casting resolves here, on its own clock.
	if player_cast_spell != "":
		player_cast_elapsed += delta_ms
		if player_cast_elapsed >= float(player_cast_ms):
			PlayerSpells.resolve_cast(self, state, find_item, _data, rng)


## The effect of a finished cast. The caster's resource is spent here, not when the
## cast started, so an interrupted-looking swing still costs nothing.
##
## Every spell in ENEMY_SPELLS is applied, including the ones that change the MONSTER's
## own behaviour (the shouts, the shields, Faerie Fire, Evasion, Poison Weapon). Leaving
## them out was the one place the port silently diverged from the PWA: a caster picked
## `defensive_shout` and burned its swing on a no-op, which reads as a monster that
## simply stops attacking.
func _resolve_cast(state, find_item: Callable) -> void:
	var spells: Dictionary = _data.enemy_spells()
	var spell: Dictionary = spells.get(cast_spell_id, {})
	var spell_id := cast_spell_id
	cast_spell_id = ""
	cast_elapsed = 0.0
	cast_time = 0.0
	if spell.is_empty():
		return
	# A rage monster pays a rage cost, the rest pay mana. The PWA made that distinction
	# at the swing-decision step; the resource is still spent at the END of the cast.
	var cost := float(spell.get("rageCost", 0)) if enemy_resource == "rage" \
		else float(spell.get("manaCost", 0))
	enemy_resource_cur = maxf(0.0, enemy_resource_cur - cost)

	var diffs: Array = _data.difficulties()
	var diff_mult := float((diffs[difficulty] as Dictionary).get("mult", 1.0)) \
		if difficulty < diffs.size() else 1.0
	# Spell damage is 0.8x a swing, scaled by the zone like melee is — except for a
	# boss, whose stats are already absolute and so are not zone-scaled twice.
	var base := float(rng.randi_range(enemy_dmg_min, maxi(enemy_dmg_max, enemy_dmg_min))) \
		* diff_mult * 0.8 * (1.0 if is_boss else prog.zone_mult(progress, difficulty))

	match spell_id:
		"poison_bolt":
			var amount := int(round(base * 0.3))
			amount = _hero_magic_damage(state, "nature", amount)
			# Poison Bolt leaves a DoT, not a lump of damage — the PWA applied the whole
			# 0.3x as three ticks on the hero.
			_apply_hero_poison(maxi(1, amount))
			_note("ENEMY POISON", amount, true)
		"drain_life":
			var amount2 := _hero_magic_damage(state, "nature", int(round(base * 0.7)))
			var drained := _hero_damage_after_mitigation(state, find_item, amount2)
			hero_hp -= float(drained)
			enemy_hp = minf(enemy_max_hp, enemy_hp + round(float(drained) * 0.6))
			_note("ENEMY DRAIN", drained, true)
		"mana_drain":
			var amount3 := _hero_magic_damage(state, "nature", int(round(base * 0.6)))
			var drained2 := _hero_damage_after_mitigation(state, find_item, amount3)
			hero_hp -= float(drained2)
			state.hero()["mana"] = maxi(0, int(state.hero().get("mana", 0)) - int(round(float(drained2) * 0.8)))
			_note("ENEMY MANA DRAIN", drained2, true)
		"shadow_bolt":
			var amount4 := int(round(base * 1.2))
			var crit := rng.randf() < 0.5
			if crit:
				amount4 = int(round(float(amount4) * 2.0))
			amount4 = _hero_magic_damage(state, "fire", amount4)
			var landed := _hero_damage_after_mitigation(state, find_item, amount4)
			hero_hp -= float(landed)
			_note("ENEMY CRIT" if crit else "ENEMY BOLT", landed, true)
		"heal":
			var heal := int(round(enemy_max_hp * 0.3))
			enemy_hp = minf(enemy_max_hp, enemy_hp + float(heal))
			_note("ENEMY HEAL", heal, false)
		# The monster's own buffs. 60 fps ticks in the PWA: 8 s = 480 ticks.
		"defensive_shout":
			enemy_defensive_shout_ms = 8000
			_note("ENEMY DEFENSIVE SHOUT", 0, false)
		"battle_shout":
			enemy_battle_shout_ms = 8000
			_note("ENEMY BATTLE SHOUT", 0, false)
		"thorn_shield":
			enemy_thorn_shield_ms = 10000
			_note("ENEMY THORN SHIELD", 0, false)
		"faerie_fire":
			enemy_faerie_fire_ms = 10000
			_note("ENEMY FAERIE FIRE", 0, false)
		"slow":
			# 50 % off the hero's attack speed for 5 s — applied by lengthening the swing
			# interval, which is the only place the hero's own clock reads it.
			player_slow_pct = 50.0
			player_slow_ms = 5000
			_note("ENEMY SLOW", 0, true)
		"evasion":
			enemy_evasion_ms = 6000
			_note("ENEMY EVASION", 0, false)
		"poison_weapon":
			enemy_poison_weapon_ms = 8000
			enemy_poison_weapon_dmg = maxi(1, int(round(base * 0.15)))
			_note("ENEMY POISON WEAPON", 0, false)

	if hero_hp <= 0.0:
		_finish(false, state, find_item)


## Damage a caster's spell does to the HERO, after the hero's armour, flat reduction and
## the Cursed debuff. The PWA chained exactly this for spell damage too (an earlier port
## note that claimed spells used a separate formula was wrong).
func _hero_damage_after_mitigation(state, find_item: Callable, raw: int) -> int:
	return incoming_damage(state, find_item, raw)


## The hero's gear resistance against one school, applied BEFORE the armour curve — the
## order the PWA used (`getPlayerResist` first, then the defence curve then the flat
## reduction). Faerie Fire halves it, which is the only effect that spell has.
func _hero_magic_damage(state, school: String, raw: int) -> int:
	return maxi(1, int(round(float(raw) * hero_school_resist(state, school))))


## One hero swing. Dual wield alternates hands and the off hand swings at 0.6x.
##
## The queued class spells (Heroic Strike, Frenzy) are consumed HERE rather than in the
## screen: they modify this swing's damage and attack rating, so the rule has to live
## where the swing is resolved or no test could reach it.
func player_attack(state, find_item: Callable) -> Dictionary:
	var is_offhand := offhand_swing_ms > 0 and offhand_turn
	offhand_turn = not offhand_turn
	var slot := "shield" if is_offhand else "weapon"
	var weapon: Dictionary = find_item.call(state.equip().get(slot, "fists"))
	if weapon.is_empty():
		weapon = find_item.call("fists")

	# The off-hand penalty is NOT a constant here: it is `spec.offHandMult`, which rises
	# from 0.5 to 1.0 as One-Hand Specialization is invested. Hardcoding 0.6 made the
	# talent's own off-hand clause unread — the same class of bug as the crit bonus.
	var spec := Talents.swing_bonus(state, weapon, is_offhand,
		Talents.shield_spec_dmg_mult(state))
	var mult: float = float(spec["handMult"])
	var ar_mult: float = 1.0
	var queued_frenzy := false
	# The queued spells apply to the MAIN hand only — an off-hand swing is not the hit
	# the player queued.
	if not is_offhand:
		var queued: Dictionary = consume_queued(state)
		mult *= float(queued["dmgMult"])
		ar_mult = float(queued["arMult"])
		queued_frenzy = bool(queued["frenzy"])
	if battle_shout_dmg_pct > 0.0:
		mult *= 1.0 + battle_shout_dmg_pct / 100.0
	# The weapon specialisation's damage and attack-rating multipliers, straight from the
	# talent. `ar_mult` starts at the queued spells' value and compounds with it, exactly
	# as the PWA multiplied `spec.arMult * arMultOverride`.
	mult *= float(spec["dmgMult"])
	ar_mult *= float(spec["arMult"])

	var result := _resolve_player_hit(state, find_item, weapon, mult, is_offhand, ar_mult)
	# The enemy's Thorn Shield returns a flat 5-10 to whoever hits it. The PWA rolled
	# this inside the player's attack resolution; it is the MONSTER's buff, but it fires
	# on the hero's swing, so it lands here — right after the hit that triggered it.
	if bool(result.get("hit", false)) and enemy_thorn_shield_ms > 0:
		var thorn := 5 + rng.randi_range(0, 5)
		hero_hp -= float(thorn)
		_note("THORN SHIELD", thorn, true)
		if hero_hp <= 0.0:
			_finish(false, state, find_item)
			return result
	# A Frenzy stack is earned only by a hit that LANDED, and only by the main hand.
	if queued_frenzy and bool(result.get("hit", false)):
		apply_frenzy_stack(state)
	return result


func _resolve_player_hit(state, find_item: Callable, weapon: Dictionary, mult: float,
		is_offhand: bool, ar_mult: float = 1.0) -> Dictionary:
	var hero: Dictionary = state.hero()
	var cls_id := str(state.data.get("heroClass", ""))
	var is_staff := str(weapon.get("weaponType", "")) == "staff"

	if not is_staff:
		var ar := int(round(float(prog.hero_attack_rating(hero, state.equip(), cls_id, find_item)) * ar_mult))
		var chance := prog.hit_chance(ar, enemy_defense, int(hero.get("level", 1)), monster_level_value)
		if rng.randf() * 100.0 >= chance:
			_note("MISS", 0, false)
			return {"hit": false, "reason": "miss"}

	if enemy_block_chance > 0.0 and rng.randf() * 100.0 < enemy_block_chance:
		_note("BLOCK", 0, false)
		return {"hit": false, "reason": "block"}

	# The enemy's own Evasion: 30 % of the hero's swings miss outright while it lasts.
	# This is the mirror of the hero's dodge and the only thing the spell does.
	if enemy_evasion_ms > 0 and rng.randf() < 0.3:
		_note("ENEMY EVASION DODGE", 0, false)
		return {"hit": false, "reason": "evasion"}

	var base_dmg := 0.0
	if is_staff:
		var int_bonus := int(hero.get("attrInt", 0)) \
			+ Progression._equip_attr(state.equip(), find_item, "int")
		base_dmg = 2.0 + floor(float(hero.get("level", 1)) * 0.8) \
			+ float(prog.weapon_dmg(rng, weapon)) + floor(float(int_bonus) * 0.3)
	else:
		base_dmg = 2.0 + floor(float(hero.get("level", 1)) * 0.8) \
			+ float(prog.weapon_dmg(rng, weapon)) \
			+ float(int(hero.get("attrStr", 0)) + Progression._equip_attr(state.equip(), find_item, "str")) * 0.3

	var dmg := base_dmg * mult
	if is_staff:
		dmg = maxf(1.0, round(dmg * _school_resist(state)))
	# Stone Skin: the elite takes reduced incoming physical damage.
	if enemy_dmg_reduction < 1.0:
		dmg *= enemy_dmg_reduction
	# The PWA's +-1 spread, so no two swings are identical.
	dmg += float(rng.randi_range(-1, 1))
	dmg = maxf(1.0, round(dmg))

	# The crit roll: the weapon's own base crit PLUS the weapon-specialisation bonus.
	# Reading `weapon.critChance` alone is what left the whole One-Hand/Two-Hand
	# Specialization crit clause inert in the fight while the stat panel showed it.
	var crit_chance := float(Talents.swing_crit_chance(state, weapon))
	var is_crit := false
	if crit_chance > 0.0 and rng.randf() * 100.0 < crit_chance:
		dmg = round(dmg * 2.0)
		is_crit = true

	enemy_hp -= dmg
	_note(("CRIT" if is_crit else "HIT") + (" offhand" if is_offhand else ""), int(dmg), false)

	_apply_weapon_on_hit(state, weapon)
	if enemy_hp <= 0.0:
		_on_enemy_dead(state, find_item)
	return {"hit": true, "damage": int(dmg), "crit": is_crit}


## Cold chills the enemy, poison starts a DoT. Both come off the weapon's own rolls.
func _apply_weapon_on_hit(state, weapon: Dictionary) -> void:
	var cold := Progression._elem_max(weapon.get("coldDmg"))
	if cold > 0:
		enemy_slow_pct = 15.0
		enemy_slow_ms = 3000
		enemy_swing_ms = prog.enemy_swing_time(enemy_attack_speed, enemy_slow_pct, enemy_slow_ms)
	var poison := Progression._elem_max(weapon.get("poisonDmg"))
	var poison_dur := int(weapon.get("poisonDur", 0))
	if poison > 0 and poison_dur > 0:
		var tick := maxi(1, int(round(float(poison) / float(poison_dur))))
		enemy_dot = tick
		enemy_dot_ticks = poison_dur
		enemy_dot_clock = 0.0


func _tick_dots(delta_ms: float) -> void:
	if enemy_dot_ticks > 0:
		enemy_dot_clock += delta_ms
		while enemy_dot_clock >= 1000.0 and enemy_dot_ticks > 0:
			enemy_dot_clock -= 1000.0
			enemy_dot_ticks -= 1
			enemy_hp -= float(enemy_dot)
			_note("POISON", enemy_dot, true)


## One enemy swing. If the monster is a caster with an affordable spell, this swing
## is that spell — it starts casting and the effect lands when the cast time is up.
## Otherwise it is a melee hit, reduced by the hero's armour and damage reduction.
func enemy_attack(state, find_item: Callable) -> Dictionary:
	if cast_spell_id != "":
		return {"hit": false, "reason": "casting"}
	# The hero's own dodge, passive plus Evasion. A dodged swing is spent: the monster
	# does not get to hit anyway, and the PWA started a fresh swing.
	if _roll_hero_dodge(state, find_item):
		_note("DODGE", 0, true)
		return {"hit": false, "reason": "dodge"}
	if enemy_attack_type == "caster" and enemy_first_swing_done:
		var chosen := _choose_spell()
		if chosen != "":
			var spells: Dictionary = _data.enemy_spells()
			var spell: Dictionary = spells[chosen]
			cast_spell_id = chosen
			cast_time = float(spell.get("castTime", 1200))
			cast_elapsed = 0.0
			_note("ENEMY CAST %s" % chosen, 0, true)
			return {"hit": false, "reason": "cast"}
	# The first swing of a caster is still a melee hit — the PWA's decision about
	# casting only starts from the second swing on.
	enemy_first_swing_done = true

	var raw := rng.randi_range(enemy_dmg_min, maxi(enemy_dmg_max, enemy_dmg_min))
	# A melee hit is scaled by the zone and by the difficulty exactly as the PWA did it,
	# and by the monster's OWN multipliers (a critmaster's x2, an elite's aura).
	var amount := _enemy_melee_damage(raw)
	var life_steal := 0
	var mana_steal := 0
	# The monster's type changes what a landed hit DOES. A boss carries a list, and every
	# type on it applies.
	for t in _active_types():
		match str(t):
			"critmaster":
				if rng.randf() < 0.33:
					amount = int(round(float(amount) * 2.0))
			"lifestealer":
				life_steal += int(round(float(amount) * 0.5))
			"manastealer":
				mana_steal += int(round(float(amount) * 0.5))
			"poison":
				_apply_hero_poison(maxi(1, int(round(float(amount) * 0.2))))
	# D2 elite mods that ride on the hit itself.
	_apply_elite_on_hit(amount, state)
	# The hero's armour and flat reduction, in ONE place.
	var dmg := incoming_damage(state, find_item, amount)
	# A rage monster builds rage by being hit; the PWA granted it on both sides.
	if enemy_resource == "rage":
		enemy_resource_cur = minf(enemy_max_resource, enemy_resource_cur + 5.0)
	hero_hp -= float(dmg)
	# Satyr: its weapon is poisoned, so every melee hit leaves a DoT behind.
	if passive_poison_weapon:
		_apply_hero_poison(maxi(1, int(round(float(dmg) * 0.15))))
	if enemy_poison_weapon_ms > 0 and enemy_poison_weapon_dmg > 0:
		_apply_hero_poison(enemy_poison_weapon_dmg)
	if life_steal > 0:
		enemy_hp = minf(enemy_max_hp, enemy_hp + float(life_steal))
		_note("ENEMY LIFESTEAL", life_steal, false)
	if mana_steal > 0:
		state.hero()["mana"] = maxi(0, int(state.hero().get("mana", 0)) - mana_steal)
		_note("ENEMY MANA STEAL", mana_steal, true)
	_note("ENEMY HIT", dmg, true)
	if hero_hp <= 0.0:
		_finish(false, state, find_item)
	return {"hit": true, "damage": dmg}


## The monster's raw melee base for this fight: its own damage roll, the difficulty
## multiplier, the zone scaling (a boss's stats are already absolute) and the elite's
## aura. Kept as one function so a spell on the enemy side is scaled the same way.
func _enemy_melee_damage(raw: int) -> int:
	var diffs: Array = _data.difficulties()
	var diff_mult := float((diffs[difficulty] as Dictionary).get("mult", 1.0)) \
		if difficulty < diffs.size() else 1.0
	var zone := 1.0 if is_boss else prog.zone_mult(progress, difficulty)
	var aura := 1.0
	if is_elite and elite_affix.has("auraDmgMult"):
		aura = float(elite_affix["auraDmgMult"])
	return int(round(float(raw) * diff_mult * zone * aura))


## The monster's own types for this fight. A boss's list wins over the single type a
## normal monster carries.
func _active_types() -> Array:
	if not boss_types.is_empty():
		return boss_types
	if monster_type == "":
		return []
	return [monster_type]


## Elite affixes that fire on the enemy's own landing hit: an elemental rider, Mana
## Burn, the Lightning burst and the Cursed debuff. The rest (resist, dr, hp, speed)
## are applied when the encounter is built.
func _apply_elite_on_hit(amount: int, state) -> void:
	if not is_elite or elite_affix.is_empty():
		return
	var ea := elite_affix
	if ea.has("element") and ea.has("elementDmgMult"):
		var school := str(ea["element"])
		var rider := maxi(1, int(round(float(amount) * float(ea["elementDmgMult"]))))
		hero_hp -= float(rider)
		_note("ENEMY %s" % school.to_upper(), rider, true)
	if bool(ea.get("manaBurn", false)):
		var burn := mini(int(state.hero().get("mana", 0)), int(round(float(amount) * 0.25)))
		if burn > 0:
			state.hero()["mana"] = int(state.hero().get("mana", 0)) - burn
			enemy_hp = minf(enemy_max_hp, enemy_hp + float(int(round(float(burn) * 0.5))))
			_note("ENEMY MANA BURN", burn, true)
	if str(ea.get("onHit", "")) == "lightning":
		var bolt := maxi(1, int(round(float(amount) * 0.3)))
		hero_hp -= float(bolt)
		_note("ENEMY LIGHTNING", bolt, true)
	if str(ea.get("onHit", "")) == "poison":
		_apply_hero_poison(maxi(1, int(round(float(amount) * 0.2))))
	if bool(ea.get("curse", false)) and rng.randf() < 0.75 and amplify_dmg_ms <= 0:
		amplify_dmg_ms = 10000
		_note("CURSED", 0, true)


## A poison DoT on the hero: damage per second and a count of ticks. Re-applying it
## REFRESHES the duration without resetting the clock, which is what stops a monster
## that poisons every swing from stacking to a one-shot.
func _apply_hero_poison(per_tick: int) -> void:
	if per_tick <= 0:
		return
	if hero_dot_ticks <= 0:
		hero_dot_clock = 0.0
	hero_dot = per_tick
	hero_dot_ticks = 3


## The hero's chance to dodge this swing, in percent: the passive DEX dodge plus the
## Evasion buff. The PWA's Evasion was a flat coin flip (50 %) on top; keeping both in
## one percentage means the two compose instead of one silently overriding the other.
func _roll_hero_dodge(state, find_item: Callable) -> bool:
	var chance := hero_dodge_chance(state, find_item)
	return rng.randf() * 100.0 < chance


## `getPlayerDodgeChance` — passive dodge from the hero's level difference and DEX,
## capped at 50 %, plus Evasion's 50 % while it is up (capped at 75 % together).
func hero_dodge_chance(state, find_item: Callable) -> float:
	var hero: Dictionary = state.hero()
	var diff := float(int(hero.get("level", 1)) - monster_level_value)
	var base := clampf(2.0 - diff * 1.5, 0.0, 30.0)
	var dex := int(hero.get("attrDex", 0)) + _equip_stat(state.equip(), find_item, "dex")
	var passive := minf(base + floor(float(dex) / 10.0), 50.0)
	if hero_dodge_buff_ms <= 0:
		return passive
	return minf(passive + HERO_DODGE_BUFF_PCT, 75.0)


## What an enemy hit actually costs the hero, after armour and flat reduction.
##
## This is the PWA's chain in one place (`getTotalPlayerDefense` -> the
## `totalDefense / (totalDefense + 300)` curve -> flat `dmgReduction`), and it is a
## rule, not a rendering detail, so it lives on the battle where a test can reach it.
##
## The 300 is the D2 armour constant: 300 defence is 50 % reduction, and the curve
## never reaches 100 %, so armour alone can never make the hero immortal.
const ARMOR_K := 300.0

func incoming_damage(state, find_item: Callable, raw: int) -> int:
	var amount := float(raw)
	# Battle Shout on the ENEMY: +50 % on its own hits for 8 s.
	if enemy_battle_shout_ms > 0:
		amount = round(amount * 1.5)
	# Cursed (elite amplify damage): the hero takes 50 % more physical damage.
	if amplify_dmg_ms > 0:
		amount = round(amount * 1.5)
	var defense := Talents.total_defense(state, find_item)
	# Defensive Shout multiplies the armour for its 30 s, which is the ONLY thing it
	# does — a shout that writes a percentage into a field nothing reads is not a buff.
	if defensive_shout_armor_pct > 0.0:
		defense = int(round(float(defense) * (1.0 + defensive_shout_armor_pct / 100.0)))
	if defense > 0:
		amount = round(amount * (1.0 - float(defense) / (float(defense) + ARMOR_K)))
	# Flat reduction is applied AFTER the percentage, so the two compose the way the
	# PWA composed them rather than double-dipping on the same number.
	var out := maxi(1, int(round(amount)) - _equip_stat(state.equip(), find_item, "dmgReduction"))
	# The enemy's own Defensive Shout cuts what it takes by 30 % — the mirror of the
	# hero's, and it has to sit on the INCOMING side or it protects nothing.
	if enemy_defensive_shout_ms > 0:
		out = maxi(1, int(round(float(out) * 0.7)))
	return out



## Which spell the caster would cast now, or "" for none affordable. The PWA's
## `pickEnemySpell` in full: it skips a spell that is already running (a second Thorn
## Shield is a wasted swing), skips Heal at (near) full HP, skips Poison Bolt while the
## hero is already poisoned, and only ever picks something the monster can pay for.
func _choose_spell() -> String:
	if enemy_spells.is_empty():
		return ""
	# A pummel blocks recasting outright, so no spell is chosen while the window is up.
	# Without this the interrupt would cancel one cast and the enemy would simply start
	# another on its next swing.
	if enemy_cast_blocked_ms > 0:
		return ""
	var spells: Dictionary = _data.enemy_spells()
	var affordable: Array = []
	for id in enemy_spells:
		var sp: Dictionary = spells.get(id, {})
		if sp.is_empty():
			continue
		var cost := float(sp.get("rageCost", 0)) if enemy_resource == "rage" \
			else float(sp.get("manaCost", 0))
		# The PWA required a MINIMUM resource percentage for several spells; without it a
		# caster with 1 mana spams its cheapest spell forever.
		var min_pct := float(sp.get("minManaPct", 0.0))
		if min_pct > 0.0 and enemy_max_resource > 0.0 \
				and enemy_resource_cur < min_pct * enemy_max_resource:
			continue
		if cost > 0.0 and enemy_resource_cur < cost:
			continue
		if id == "heal" and enemy_hp / maxf(enemy_max_hp, 1.0) >= 0.9:
			continue
		if id == "poison_bolt" and hero_dot_ticks > 0:
			continue
		# A buff already running is not worth a swing — the PWA filtered each of these.
		if id == "thorn_shield" and enemy_thorn_shield_ms > 0:
			continue
		if id == "defensive_shout" and enemy_defensive_shout_ms > 0:
			continue
		if id == "battle_shout" and enemy_battle_shout_ms > 0:
			continue
		if id == "faerie_fire" and enemy_faerie_fire_ms > 0:
			continue
		if id == "evasion" and enemy_evasion_ms > 0:
			continue
		if id == "poison_weapon" and enemy_poison_weapon_ms > 0:
			continue
		if id == "slow" and player_slow_ms > 0:
			continue
		affordable.append(id)
	if affordable.is_empty():
		return ""
	return str(_pick(affordable))


## Spells whose effect this port actually applies. Kept as the assertion the enemy's
## spell list is checked against in `test_combat`: every one of the eleven is
## implemented, so a monster can never pick a spell that does nothing.
const IMPLEMENTED_ENEMY_SPELLS := [
	"poison_bolt", "drain_life", "mana_drain", "shadow_bolt", "heal",
	"defensive_shout", "battle_shout", "thorn_shield", "faerie_fire", "slow",
	"evasion", "poison_weapon",
]


static func _spell_implemented(id: String) -> bool:
	return id in IMPLEMENTED_ENEMY_SPELLS


## The hero's resistance against one magic school, as the multiplier the damage is
## scaled by. It is 1.0 minus the summed gear resistances (capped at 75 %, D2 style),
## halved again by the enemy's Faerie Fire — which is the ONE thing Faerie Fire does
## and the reason it cannot be a number nobody reads.
func hero_school_resist(state, school: String) -> float:
	var total := 0
	var key: String = {"fire": "fireRes", "ice": "coldRes", "lightning": "lightningRes",
		"nature": "poisonRes"}.get(school, "")
	if key != "":
		for slot in ItemGen.EQUIP_SLOTS:
			var item_id: Variant = state.equip().get(slot)
			if item_id == null or item_id == "":
				continue
			var item: Dictionary = _find_item_any(state, item_id)
			if not item.is_empty():
				total += int(item.get(key, 0))
	var pct := mini(75, total)
	if enemy_faerie_fire_ms > 0:
		pct = int(round(float(pct) * 0.5))
	return 1.0 - float(pct) / 100.0


## The battle only carries the caller's `find_item` for its own lifetime, and the
## resistance lookup happens on the save's equipped items too, so this keeps the
## simplest possible resolution: the same table the rest of the battle reads.
func _find_item_any(state, item_id: Variant) -> Dictionary:
	if _data == null:
		return {}
	return _data.item(str(item_id))


## The resist multiplier for the hero's own spells, from the ENEMY's resistances. The
## monster's table is a multiplier already (0.9 = 10 % resist), so it is returned as-is;
## `activeSchool` picks which entry — the mage sets it when he casts.
func _school_resist(state) -> float:
	var school := str(state.data.get("activeSchool", "") or "fire")
	var resist := float(enemy_resists.get(school, 1.0))
	# Faerie Fire halves the enemy's own resistances against the hero's spells too.
	if enemy_faerie_fire_ms > 0 and resist != 1.0:
		if resist < 1.0:
			resist = 1.0 - (1.0 - resist) * 0.5
		else:
			resist = 1.0 + (resist - 1.0) * 0.5
	return resist if resist > 0.0 else 1.0


# --- ending a fight ----------------------------------------------------------

func _on_enemy_dead(state, find_item: Callable) -> void:
	if pending_kill:
		return
	pending_kill = true


## Settle the fight. On a win this is where progression moves: the fight counter,
## the stop advance, XP, gold and the boss flag. All of it lives here, not in the UI.
##
## A LOSS is not just "not a win": the PWA's death path counts the death, pays a
## consolation XP/gold, RESETS the fights of the current stop (`areaFightProgress = 0`)
## and puts the hero back to full HP, because the death sends him to town. The port
## counted the death and then left the fight counter and the HP alone, so a death was
## an invisible no-op on the save — the exact "the loss does not work" symptom.
func _finish(won_flag: bool, state, find_item: Callable) -> void:
	ended = true
	won = won_flag
	var act_id_local := act_id
	var hero: Dictionary = state.hero()
	var loc_progress: Array = state.data["locationProgress"]
	var fight_progress: Array = state.data["areaFightProgress"]

	if not won_flag:
		state.data["deaths"] = int(state.data.get("deaths", 0)) + 1
		# Consolation: 20 % of the kill XP, floored at 3, plus 5-15 gold. A death with
		# no consolation at all made a lost fight cost the player a whole stop AND pay
		# nothing for it, which reads as the game eating the attempt.
		var cons_xp := maxi(3, int(round(float(monster_level_value) * 30.0 * 0.2)))
		hero["xp"] = int(hero.get("xp", 0)) + cons_xp
		hero["gold"] = int(hero.get("gold", 0)) + prog.kill_gold(rng)
		# Death resets the fights of the CURRENT stop only; the stop itself is kept.
		fight_progress[act_id_local] = 0
		state.data["areaFightProgress"] = fight_progress
		hero["maxHp"] = ItemGen.new(_data).hero_max_hp(hero, state.equip(), find_item)
		hero["hp"] = hero["maxHp"]
		return

	state.data["wins"] = int(state.data.get("wins", 0)) + 1
	hero["hp"] = hero_hp
	var pack := pack_size()

	if is_boss:
		state.set_boss_defeated(act_id_local)
		hero["xp"] = int(hero.get("xp", 0)) \
			+ int(round(float(monster_level_value) * 150.0 * prog.xp_multiplier(int(hero.get("level", 1)), monster_level_value)))
		loc_progress[act_id_local] = 0
		fight_progress[act_id_local] = 0
		var act: Dictionary = _data.act_by_id(act_id_local)
		var reward: Dictionary = act.get("reward", {})
		hero["gold"] = int(hero.get("gold", 0)) + int(reward.get("gold", 0))
	else:
		var af := int(fight_progress[act_id_local]) + 1
		fight_progress[act_id_local] = mini(af, FIGHTS_PER_ZONE)
		hero["gold"] = int(hero.get("gold", 0)) + prog.kill_gold(rng)
		hero["xp"] = int(hero.get("xp", 0)) \
			+ prog.kill_xp(int(hero.get("level", 1)), monster_level_value, pack)

	state.data["locationProgress"] = loc_progress
	state.data["areaFightProgress"] = fight_progress
	hero["maxHp"] = ItemGen.new(_data).hero_max_hp(hero, state.equip(), find_item)


## The loot a finished fight hands out. Gold and XP are settled in `_finish`; the
## items ride through here because they need the loot system, which the battle does
## not own.
##
## The drop count is the PWA's: 2-3 rolls per kill, PER PACK MEMBER, so an elite pack
## is four times the loot of a normal fight. That is deliberate — packs are the
## reward spike, not a difficulty spike.
##
## Returns {items: Array[Dictionary], gold: int, portals: int}. Nothing here writes
## to the inventory: the caller decides what the bag can take.
func roll_loot(loot, state, find_item: Callable, magic_find: int, gold_find: int) -> Dictionary:
	var items: Array = []
	var gold := 0
	var portals := 0
	var rolls := 2 + rng.randi_range(0, 1)
	for _member in pack_size():
		for _i in rolls:
			var drop: Dictionary = loot.roll(state, act_id, progress, is_boss,
				monster_level_value, magic_find, gold_find, rng)
			match str(drop.get("type", "")):
				"item":
					var it: Dictionary = drop.get("item", {})
					if not it.is_empty():
						if str(it.get("id", "")) == "townPortalScroll":
							portals += 1
						else:
							items.append(it)
				"boss":
					var bit: Dictionary = drop.get("item", {})
					if not bit.is_empty():
						items.append(bit)
					gold += int(drop.get("gold", 0))
				"gold":
					gold += int(drop.get("gold", 0))
	return {"items": items, "gold": gold, "portals": portals}


## Advance to the next stop when the current one is finished. Mirrors the PWA's
## continueToNextStop: 10/10 fights and not the boss zone moves the zone on.
func advance_stop(state) -> bool:
	var total := prog.total_zones(act_id)
	var loc_progress: Array = state.data["locationProgress"]
	var fight_progress: Array = state.data["areaFightProgress"]
	var p := int(loc_progress[act_id])
	var f := int(fight_progress[act_id])
	if f >= FIGHTS_PER_ZONE and p < total - 1:
		state.set_progress(act_id, p + 1)
		fight_progress[act_id] = 0
		return true
	if f >= FIGHTS_PER_ZONE:
		fight_progress[act_id] = FIGHTS_PER_ZONE
		return false
	return false


# --- helpers -----------------------------------------------------------------

## Public wrappers over the private helpers below, so `player_spells.gd` can reach the
## battle's own rules without a second copy of them. Anything a spell needs lives here
## once; a spell module that re-derived the damage formula would be a second source of
## truth for the balance.
func note(kind: String, amount: int, on_player: bool) -> void:
	_note(kind, amount, on_player)


func equip_attr(state, find_item: Callable, stat: String) -> int:
	return _equip_stat(state.equip(), find_item, stat)


func mark_enemy_dead(state, find_item: Callable) -> void:
	_on_enemy_dead(state, find_item)


## The hit check for a spell that swings a weapon (Double Swing), with an optional
## attack-rating multiplier on top. The PWA ran this hit check INSIDE the spell rather
## than letting the normal swing carry it, which is why it is exposed.
func roll_player_hit(state, find_item: Callable, ar_mult: float = 1.0) -> bool:
	var hero: Dictionary = state.hero()
	var cls_id := str(state.data.get("heroClass", ""))
	var weapon: Dictionary = find_item.call(state.equip().get("weapon", "fists"))
	# A staff does not roll to hit at all — the PWA's `is_staff` branch skipped it.
	if str(weapon.get("weaponType", "")) == "staff":
		return true
	var ar := int(round(float(prog.hero_attack_rating(hero, state.equip(), cls_id, find_item)) * ar_mult))
	var chance := prog.hit_chance(ar, enemy_defense, int(hero.get("level", 1)), monster_level_value)
	return rng.randf() * 100.0 < chance


## Apply a slow to the enemy, preserving how far into its current swing it already was.
## Recomputing the interval without that correction would either hand the enemy a free
## swing or swallow one, and the PWA went to the trouble of doing it properly.
func apply_enemy_slow(slow_pct: float, slow_ms: int) -> void:
	enemy_slow_pct = slow_pct
	enemy_slow_ms = slow_ms
	var old_ms := float(enemy_swing_ms)
	var progress := 0.0
	if old_ms > 0.0:
		progress = clampf(enemy_swing_elapsed / old_ms, 0.0, 1.0)
	enemy_swing_ms = prog.enemy_swing_time(enemy_attack_speed, enemy_slow_pct, enemy_slow_ms)
	enemy_swing_elapsed = progress * float(enemy_swing_ms)


## Damage a reflected spell throws back: a fraction of what the enemy's own cast would
## have done to the hero. Built from the enemy's OWN numbers, so a stronger enemy
## reflects harder.
func reflect_damage(reflect_pct: float, rng_for_roll: RandomNumberGenerator) -> int:
	var diffs: Array = _data.difficulties()
	var diff_mult := float((diffs[difficulty] as Dictionary).get("mult", 1.0)) \
		if difficulty < diffs.size() else 1.0
	var raw := float(rng_for_roll.randi_range(enemy_dmg_min, maxi(enemy_dmg_max, enemy_dmg_min)))
	var zone := 1.0 if is_boss else prog.zone_mult(progress, difficulty)
	var base := raw * diff_mult * 0.8 * zone
	return maxi(1, int(round(base * 0.7 * reflect_pct / 100.0)))


## Consume the queued Heroic Strike / Frenzy flags and return the damage multiplier and
## the attack-rating multiplier for the swing that follows. Called by the battle's own
## attack so the queued spells stay rules, not screen state.
##
## Frenzy's stack is applied by `apply_frenzy_stack()` only once the hit LANDS — the
## PWA did that too, so a missed Frenzy costs the mana and gives no stack.
func consume_queued(state) -> Dictionary:
	var dmg_mult := 1.0
	var ar_mult := 1.0
	var is_frenzy := false
	var class_id := str(state.data.get("heroClass", ""))
	if heroic_strike_queued:
		var hs_lv := maxi(PlayerSpells.spell_level(state, class_id, "heroicStrike"), 1)
		dmg_mult *= float(100 + hs_lv * 100) / 100.0
		heroic_strike_queued = false
	if frenzy_queued:
		var f_lv := maxi(PlayerSpells.spell_level(state, class_id, "frenzy"), 1)
		dmg_mult *= 1.0 + float(20 * f_lv) / 100.0
		ar_mult = 1.0 + float(100 + 20 * f_lv) / 100.0
		frenzy_queued = false
		is_frenzy = true
	return {"dmgMult": dmg_mult, "arMult": ar_mult, "frenzy": is_frenzy}


## One Frenzy stack, and the swing interval recomputed from it. Stacks cap at 5 and each
## one refreshes the 10 s window; the speed bonus is (talent level + 1) % per stack.
func apply_frenzy_stack(state) -> void:
	var class_id := str(state.data.get("heroClass", ""))
	var f_lv := maxi(PlayerSpells.spell_level(state, class_id, "frenzy"), 1)
	frenzy_stacks = mini(5, frenzy_stacks + 1)
	frenzy_ms = 10000
	frenzy_speed_pct = float(frenzy_stacks * (f_lv + 1))
	_note("FRENZY %d/5" % frenzy_stacks, 0, false)


## The class spells available right now, as [{id, name, def, blocked, cost, cooldown}].
## The arena renders this and owns no rule about which spells exist — that is the whole
## reason it is a function on the battle rather than a loop in the screen.
func spell_bar(state, find_item: Callable) -> Array:
	var class_id := str(state.data.get("heroClass", ""))
	var out: Array = []
	for s in PlayerSpells.spells_for_class(_data, class_id):
		var def: Dictionary = s
		var spell_id := str(def.get("id", ""))
		# A spell with no talent point in it does not exist as a button, exactly as the
		# PWA filtered its bar.
		if not PlayerSpells.is_available(state, class_id, spell_id):
			continue
		var blocked := PlayerSpells.blocked_reason(state, _data, class_id, spell_id, self,
			find_item, spell_gcd_ms, int(spell_cooldowns.get(spell_id, 0)))
		out.append({
			"id": spell_id,
			"name": str(def.get("name", spell_id)),
			"def": def,
			"blocked": blocked,
			"can": blocked == "",
			"cost": PlayerSpells.spell_cost(state, class_id, spell_id, float(def.get("cost", 0))),
			"cooldown": int(spell_cooldowns.get(spell_id, 0)),
			"queued": (spell_id == "heroicStrike" and heroic_strike_queued)
				or (spell_id == "frenzy" and frenzy_queued),
		})
	return out


func _note(kind: String, amount: int, is_player_taking: bool) -> void:
	log.append({"kind": kind, "amount": amount, "onPlayer": is_player_taking})


func _pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[rng.randi_range(0, arr.size() - 1)]


func _equip_stat(equip: Dictionary, find_item: Callable, stat: String) -> int:
	var total := 0
	for slot in ItemGen.EQUIP_SLOTS:
		var item_id: Variant = equip.get(slot)
		if item_id == null or item_id == "" or item_id == "fists":
			continue
		var item: Dictionary = find_item.call(item_id)
		if not item.is_empty():
			total += int(item.get(stat, 0))
	return total


func _record_encounter(state, face: String) -> void:
	var list: Array = state.data.get("encounteredMonsters", [])
	if not list.has(face):
		list.append(face)
	state.data["encounteredMonsters"] = list


func _pick_enemy_spells_sanity() -> void:
	var spells: Dictionary = _data.enemy_spells()
	var kept: Array = []
	for id in enemy_spells:
		if spells.has(id):
			kept.append(id)
	enemy_spells = kept
