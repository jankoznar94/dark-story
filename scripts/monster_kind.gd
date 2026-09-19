extends RefCounted
## Catalogue of MONSTER KINDS. A kind is DATA - numbers, a tint, a model scale and
## which behaviour script drives it - so a new monster is an entry here, not a new
## scene, and the arena JSON stays the only place that says WHERE it stands.
##
## Jan's brief for the pack: "weaker than the hero, so I can try killing several".
## That is a measurable claim, not a mood, so both sides of it are written down
## here and asserted in tools/test_fight.gd:
##   * the hero is HERO_MAX_HP (180) and lands HERO_HIT_MIN..HERO_HIT_MAX per swing
##   * every kind dies in at most `max_hits_to_kill()` hero swings
##   * every kind deals far less damage per hit than the hero takes to die
##
## Numbers are in the same units as the hero: metres, seconds, hp.
## `attack_windup` is anchored to the CLIP the punch plays, exactly as the hero's
## sword window is anchored to its measured contact frame (0.40 s into
## Rig|Punch_Cross) - do not "tune" it by feel.

## The hero's own measured numbers, mirrored from player.gd so the strength claim
## can be checked without instantiating the hero.
const HERO_MAX_HP := 180.0
const HERO_HIT_MIN := 16.0
const HERO_HIT_MAX := 25.0

## Contact frame of the punch clips, from the same measurement pass as the sword:
## the fist reaches the target a little before half of the 0.917 s imported clip.
## ALL kinds share this windup - damage has to land when the fist arrives, so the
## variety lives in hp, damage, cadence (recover + cooldown) and behaviour, never
## in a windup that disagrees with the animation.
const PUNCH_WINDUP := 0.40
const PUNCH_ACTIVE := 0.12

static func kinds() -> Dictionary:
	return {
		# --- the fragile one: fast, weak, and it does not walk straight at you ---
		"ghoul": {
			"name": "Ghoul",
			"level": 1,
			"hp": 55.0,
			"walk_speed": 2.45,
			"accel": 14.0, "decel": 20.0,
			"turn_speed": 7.5, "turn_speed_attacking": 3.0,
			"windup": PUNCH_WINDUP, "active": PUNCH_ACTIVE, "recover": 0.30,
			"cooldown": 0.50, "range": 1.45, "arc": 70.0,
			"damage_min": 4.0, "damage_max": 7.0,
			"aggro": 5.0, "keep_distance": 1.10,
			"tint": Color(0.26, 0.30, 0.22),   ## cold grey-green, desaturated
			"scale": 0.92,
			"leash": 9.0,
			"separation": 1.15,
			"script": "res://scripts/enemy_ghoul.gd",
		},
		# --- the baseline bruiser: straight in, the original test enemy ---
		"ravager": {
			"name": "Ravager",
			"level": 2,
			"hp": 110.0,
			"walk_speed": 2.20,
			"accel": 12.0, "decel": 18.0,
			"turn_speed": 6.0, "turn_speed_attacking": 2.6,
			"windup": PUNCH_WINDUP, "active": PUNCH_ACTIVE, "recover": 0.30,
			"cooldown": 0.35, "range": 1.55, "arc": 70.0,
			"damage_min": 8.0, "damage_max": 13.0,
			"aggro": 5.5, "keep_distance": 1.35,
			"tint": Color(0.34, 0.20, 0.16),   ## dried blood / boiled leather
			"scale": 1.0,
			"leash": 16.0,
			"separation": 1.05,
			"script": "res://scripts/enemy.gd",
		},
		# --- the heavy: slow, big, hits hard and does not stop walking into you ---
		"brute": {
			"name": "Brute",
			"level": 3,
			"hp": 180.0,
			"walk_speed": 1.55,
			"accel": 8.0, "decel": 12.0,
			"turn_speed": 3.6, "turn_speed_attacking": 1.4,
			"windup": PUNCH_WINDUP, "active": PUNCH_ACTIVE, "recover": 0.42,
			"cooldown": 1.05, "range": 1.80, "arc": 95.0,
			"damage_min": 14.0, "damage_max": 20.0,
			"aggro": 5.0, "keep_distance": 0.85,
			"tint": Color(0.19, 0.17, 0.16),   ## wet iron, nearly black
			"scale": 1.16,
			"leash": 14.0,
			"separation": 1.40,
			"script": "res://scripts/enemy_brute.gd",
		},
	}


static func kind(id: String) -> Dictionary:
	var all := kinds()
	if not all.has(id):
		push_error("monster_kind: unknown kind '%s'" % id)
		return {}
	return (all[id] as Dictionary).duplicate(true)


## How many hero swings this kind survives at the hero's WORST case (a minimum
## roll). The claim "weaker than the hero" is this number being small.
static func hits_to_kill(k: Dictionary) -> int:
	return int(ceil(float(k.get("hp", 0.0)) / HERO_HIT_MIN))
