extends Node
class_name Sfx
## Sfx — the PWA's combat `playSFX(...)` calls, in one mixer.
##
## Source: `game.ts`'s `const …Sfx = (() => { const a = new Audio('…mp3'); a.volume = …; return a; })()`
## block plus every `playSFX(...)` call site in the fight loop. Each entry below carries the
## PWA's own file list and volume, so the mapping is data and not a chain of `if`s in the
## arena screen.
##
## ⚠️  The PWA created each `Audio` object ONCE and `playSFX` did `currentTime = 0; play()`:
## one object per sound, so two swings inside the same 300 ms re-started the same object
## and the sound was CUT OFF. Godot cannot re-trigger an `AudioStreamPlayer` either, so a
## pool of players is what makes two fast hits audible as two hits. That difference is
## deliberate, not a divergence.
##
## ⚠️  `volume` is LINEAR (the PWA's `a.volume`), stored here as the PWA wrote it and
## converted to dB at play time (`SILENT_DB` guards the `linear_to_db(0) == -inf` warning).
##
## A cue is raised by the RULES (`battle.gd` / `player_spells.gd`) and consumed by the
## screen, one per frame — see `Battle.take_sfx_cue()`. A cue with no entry here is a
## programming error and is reported loudly rather than silently dropped.

## --- the cue vocabulary ------------------------------------------------------
## Named after what HAPPENED, not after the file: `melee_hit` and `blunt_hit` are different
## events (a blade vs a club) that merely happen to pick different files.
const CUE_MELEE_HIT := "melee_hit"
const CUE_MELEE_CRIT := "melee_crit"
const CUE_FIST_HIT := "fist_hit"
const CUE_FIST_CRIT := "fist_crit"
const CUE_BLUNT_HIT := "blunt_hit"
const CUE_BLUNT_CRIT := "blunt_crit"
const CUE_STAFF_HIT := "staff_hit"
const CUE_STAFF_CRIT := "staff_crit"
const CUE_DODGE := "dodge"
const CUE_BLOCK := "block"
## The hero answering the enemy's swing with a riposte. The PWA's `counterSfx` reuses
## `hit.mp3` rather than adding a file, so this maps to `assets/audio/hit.mp3` — the same
## arrangement the enemy's hit-sound pool is built from.
const CUE_COUNTER := "counter"
## A completed Whirlwind — the PWA's `playSFX(strongStrikeSfx)` in `endCombo(true)`.
const CUE_STRONG_STRIKE := "strong_strike"
const CUE_HURT := "hurt"
const CUE_ENEMY_CAST := "enemy_cast"
const CUE_SHOUT := "shout"
const CUE_THUNDER_CLAP := "thunder_clap"
const CUE_THUNDER_BOLT := "thunder_bolt"
const CUE_POTION := "potion"
const CUE_TREASURE := "treasure"
## The same `treasure.mp3`, raised at a DIFFERENT event: the PWA's `showMapWithUnlock` plays
## `treasureSfx` when a completed stop reveals the next one. It is a cue of its own because
## the moment is a different one — a map that never plays anything when a path opens reads as
## "nothing happened".
const CUE_ACT_UNLOCK := "act_unlock"
const CUE_SHOP := "shop"
const CUE_EQUIP := "equip"
const CUE_LEVELUP := "levelup"
## The PWA's `levelupSfx` — the sound of SPENDING a talent point or an attribute point,
## which is a different event from gaining a level and is the one that plays a FILE.
const CUE_POINT_SPENT := "point_spent"
const CUE_CLICK := "click"
## The PWA's `sfxSuccess` / `sfxBossDefeat` — the fight-ending jingles, which it SYNTHESISED
## with `playTone` oscillators. This port plays the win STING FILE for both instead; generated
## sound is gone (see the note below the cue list).
const CUE_VICTORY := "victory"
const CUE_BOSS_DEFEAT := "boss_defeat"

## ⚠️  NO SYNTHESISED SOUND PLAYS IN THIS GAME ANY MORE (Jan, Nov 2026: "zruš veškeré
## generované zvuky … ať zůstanou jen zvuky, ze zvukového souboru").
##
## The PWA rendered its three fanfares (level-up, victory, boss defeat) with `playTone`
## oscillator chains instead of files, and this port re-implemented them as generated
## `AudioStreamWAV`s. Generated tones through a phone speaker read as a cheap beep next to the
## sampled hits, and the whole point of the mixer is that every cue is a FILE:
##
##   * gaining a level            -> `assets/sfx/levelup.mp3`
##   * victory page               -> `assets/audio/win.mp3`
##   * boss defeat                -> `assets/audio/win.mp3`
##
## Do not bring `TONES` back. A cue with no file behind it is the thing that was rejected.

## The mixer singleton. A screen with no mixer of its own (the town, the shop) plays through
## this one, so a click on a shop tab is the same sound as a click anywhere else. Set by the
## first mixer that enters the tree; a headless test with no mixer simply gets a no-op.
static var instance: Node = null

## ⚠️  THREE CUES THE PWA'S OWN FILES SUGGEST AND THE PWA NEVER PLAYS. Each was checked
## against the source rather than against the asset list, and each is deliberately ABSENT:
##
##  * `enemy_heal` — the monster's `heal` branch in `executeEnemySpell` sets `amount = 0`,
##    restores 30 % of the boss's HP and spawns a floating text. There is **no `playSFX`**
##    on that path at all. `healSfx` exists as an `Audio` object and is played from two
##    other places, neither of them this one. An earlier revision of this table had an
##    `ENEMY_HEAL` cue wired to `battle.gd`'s heal branch — a sound the player never heard
##    in the PWA, i.e. an invented element, which is the one thing this port must not do.
##  * `double_swing` — a successful Double Swing plays `playSFX(getHitSfx())`, the same
##    generic main-hand hit sound as any other swing. The port does that too
##    (`player_spells.gd`), so a separate cue is dead weight.
##  * `strong_strike` / `heal` — `strongStrikeSfx` belongs to a COMPLETED WHIRLWIND, and
##    `healSfx` to the training minigame's heal reaction and to `townHeal()`. The whirlwind
##    flurry and the minigames are deliberately not ported (see the skill's "Deliberately
##    NOT ported"), and `townHeal()` has **no caller anywhere in the PWA** — it is dead
##    code there, so a heal sound on entering town would be invented here.
##
## Kept as prose rather than as commented-out entries: a table row with no caller reads as
## "wired, just quiet", and that is the failure mode this whole mixer exists to end.


## The enemy's hit-sound pool — `getEnemyHitSfx()` picks one at random out of these seven.
const ENEMY_HIT_POOL := [
	"res://assets/sfx/enemy_hit.mp3",
	"res://assets/sfx/enemy_hit1.mp3",
	"res://assets/sfx/enemy_hit2.mp3",
	"res://assets/sfx/enemy_hit3.mp3",
	"res://assets/sfx/enemy_hit4.mp3",
	"res://assets/sfx/enemy_hit5.mp3",
	"res://assets/sfx/enemy_hit6.mp3",
]
## `getHurtSfx()` — three takes, one at random.
const HURT_POOL := [
	"res://assets/sfx/hurt1.mp3",
	"res://assets/sfx/hurt2.mp3",
	"res://assets/sfx/hurt3.mp3",
]
## The hero's own body-hit pool. `hurt4.mp3` exists in the PWA's asset folder but is never
## loaded by any line of its source, so it is not used here either.
const MELEE_SWING_POOL := [
	"res://assets/audio/melee_hit.mp3",
	"res://assets/sfx/melee_hit2.mp3",
]

## cue -> the layers it plays. A layer is `{paths, volume, chance}`: `paths` is picked from at
## random, `chance` is the probability the layer plays at all (the PWA's "30% chance" impact
## layer under a weapon hit).
const TABLE := {
	CUE_MELEE_HIT: [
		{"paths": MELEE_SWING_POOL, "volume": 0.70, "chance": 1.0},
		{"paths": ENEMY_HIT_POOL, "volume": 0.70, "chance": 0.30},
	],
	CUE_MELEE_CRIT: [
		{"paths": ["res://assets/audio/melee_crit.mp3"], "volume": 0.70, "chance": 1.0},
		{"paths": ENEMY_HIT_POOL, "volume": 0.70, "chance": 0.30},
	],
	CUE_FIST_HIT: [
		{"paths": ["res://assets/audio/fist_hit.mp3"], "volume": 0.70, "chance": 1.0},
		{"paths": ENEMY_HIT_POOL, "volume": 0.70, "chance": 0.30},
	],
	CUE_FIST_CRIT: [
		{"paths": ["res://assets/audio/fist_crit.mp3"], "volume": 0.70, "chance": 1.0},
		{"paths": ENEMY_HIT_POOL, "volume": 0.70, "chance": 0.30},
	],
	CUE_BLUNT_HIT: [
		{"paths": ["res://assets/sfx/blunt_hit.mp3"], "volume": 0.70, "chance": 1.0},
		{"paths": ENEMY_HIT_POOL, "volume": 0.70, "chance": 0.30},
	],
	CUE_BLUNT_CRIT: [
		{"paths": ["res://assets/sfx/blunt_crit.mp3"], "volume": 0.70, "chance": 1.0},
		{"paths": ENEMY_HIT_POOL, "volume": 0.70, "chance": 0.30},
	],
	# `getHitSfx`/`getCritSfx` map a staff onto `hit` / `crit` — the mage's basic attack.
	CUE_STAFF_HIT: [
		{"paths": ["res://assets/audio/hit.mp3"], "volume": 0.70, "chance": 1.0},
		{"paths": ENEMY_HIT_POOL, "volume": 0.70, "chance": 0.30},
	],
	CUE_STAFF_CRIT: [
		{"paths": ["res://assets/audio/crit.mp3"], "volume": 0.70, "chance": 1.0},
		{"paths": ENEMY_HIT_POOL, "volume": 0.70, "chance": 0.30},
	],
	CUE_DODGE: [
		{"paths": ["res://assets/audio/dodge.mp3"], "volume": 0.70, "chance": 1.0},
	],
	CUE_BLOCK: [
		{"paths": ["res://assets/audio/block.mp3"], "volume": 0.70, "chance": 1.0},
	],
	## `counterSfx` IS `hit.mp3` in the PWA (`new Audio('hit.mp3'); volume 0.80`). Same
	## file as the enemy's own hit pool draws from, at the PWA's own louder volume.
	CUE_COUNTER: [
		{"paths": ["res://assets/audio/hit.mp3"], "volume": 0.80, "chance": 1.0},
	],
	## `endCombo(mb, true)` — the fanfare for getting the whole flurry right.
	CUE_STRONG_STRIKE: [
		{"paths": ["res://assets/audio/strong_strike.mp3"], "volume": 0.70, "chance": 1.0},
	],
	CUE_HURT: [
		{"paths": HURT_POOL, "volume": 0.70, "chance": 1.0},
	],
	# The PWA plays these in the spell's PROJECTILE animation rather than at the cast. The
	# port has no projectile, so the sound lands where the cast STARTS — same school, same
	# moment the player can see the enemy's wind-up icon.
	#
	# ⚠️  `assets/sfx/lightning_spell.mp3` (and its `fire_spell` / `ice_spell` siblings in
	# that folder) is a 417-byte LAME header followed by zeros — three of the four files this
	# cue used to draw from carried NO audio at all, so three casts in four were silent and
	# the file list looked complete. Checked with ffprobe/astats, not by ear. The silent
	# names are dropped here; the real takes are `assets/audio/{fire,ice}_spell.mp3`,
	# `assets/sfx/lightning_spell2.mp3` and the bolt pair.
	CUE_ENEMY_CAST: [
		{"paths": ["res://assets/audio/fire_spell.mp3", "res://assets/audio/ice_spell.mp3",
			"res://assets/sfx/lightning_spell2.mp3", "res://assets/sfx/frostbolt.mp3"],
			"volume": 0.70, "chance": 1.0},
	],
	CUE_SHOUT: [
		{"paths": ["res://assets/sfx/shout.mp3"], "volume": 0.70, "chance": 1.0},
	],
	CUE_THUNDER_CLAP: [
		{"paths": ["res://assets/sfx/thunder_clap.mp3"], "volume": 0.70, "chance": 1.0},
	],
	CUE_THUNDER_BOLT: [
		{"paths": ["res://assets/sfx/thunder_bolt.mp3"], "volume": 0.70, "chance": 1.0},
	],
	CUE_POTION: [
		{"paths": ["res://assets/sfx/potion.mp3"], "volume": 0.70, "chance": 1.0},
	],
	CUE_TREASURE: [
		{"paths": ["res://assets/audio/treasure.mp3"], "volume": 0.70, "chance": 1.0},
	],
	## `showMapWithUnlock` — the same file as the chest's fanfare, at the moment the next
	## stop appears on the map.
	CUE_ACT_UNLOCK: [
		{"paths": ["res://assets/audio/treasure.mp3"], "volume": 0.70, "chance": 1.0},
	],
	## ⚠️  `assets/sfx/shop.mp3` is a real sound but a very quiet one — measured mean -38.5 dB,
	## peak -16.2 dBFS, i.e. ~15 dB below the fight hits. At the PWA's 0.70 it was inaudible
	## under the music bed, which reads as "opening the shop makes no sound". The volume is
	## raised here rather than by rewriting the asset (a re-encode would lose quality) and
	## still leaves ~10 dB of headroom under the ceiling.
	CUE_SHOP: [
		{"paths": ["res://assets/sfx/shop.mp3"], "volume": 4.0, "chance": 1.0},
	],
	CUE_EQUIP: [
		{"paths": ["res://assets/sfx/equip.mp3"], "volume": 0.70, "chance": 1.0},
	],
	CUE_LEVELUP: [
		{"paths": ["res://assets/sfx/levelup.mp3"], "volume": 0.70, "chance": 1.0},
	],
	## ⚠️  The FILE, which the PWA also uses for SPENDING a point — the same mp3 on both events
	## now, because a level-up may no longer be a generated jingle (see the note above).
	CUE_POINT_SPENT: [
		{"paths": ["res://assets/sfx/levelup.mp3"], "volume": 0.70, "chance": 1.0},
	],
	## The same story, milder: `click.mp3` peaks at -9.5 dBFS, so at 0.70 it sat 8 dB under
	## every other cue. It is a tap, not an event — audible, never loud.
	CUE_CLICK: [
		{"paths": ["res://assets/sfx/click.mp3"], "volume": 1.40, "chance": 1.0},
	],
	## The two fight-ending fanfares. Both are the game's own win sting, played as a FILE: the
	## PWA's oscillator version is gone for good.
	CUE_VICTORY: [
		{"paths": ["res://assets/audio/win.mp3"], "volume": 0.90, "chance": 1.0},
	],
	CUE_BOSS_DEFEAT: [
		{"paths": ["res://assets/audio/win.mp3"], "volume": 0.90, "chance": 1.0},
	],
}

## How many hits can overlap. A weapon hit is two layers, so 8 players is four overlapping
## hits — more than a 450 ms weapon can produce inside one 100 ms frame.
const POOL_SIZE := 8

## `linear_to_db(0.0)` is `-inf` and some audio backends warn on it.
const SILENT_DB := -80.0

## The last cue actually played, and how many cues were played at all — the only handle a
## headless test has on "the fight was audible", because a headless `AudioStreamPlayer`
## never advances `get_playback_position()`.
var last_cue := ""
var played_count := 0

var _pool: Array[AudioStreamPlayer] = []
var _next := 0
## The streams are cached per PATH: `load()` returns the same resource for the same file,
## so the cache is really about not touching the filesystem on every swing.
var _cache: Dictionary = {}
var _rng := RandomNumberGenerator.new()


## The cue for one landed hero swing, chosen by the WEAPON's type — the PWA's
## `getHitSfx(weaponType)` / `getCritSfx(weaponType)`, which are two maps rather than one
## because a staff crit and a fist crit are different files.
##
## The type is read off the ITEM the swing actually used (the off hand passes its own), so
## a dual-wielding hero hears two different weapons rather than one.
##
## It lives in the MIXER rather than on the battle so that `player_spells.gd` can reach it
## without preloading `battle.gd` — a preload cycle between the two rules modules is a
## parse error, and the mapping is a fact about SOUND, not about the fight.
static func cue_for_weapon(weapon: Dictionary, is_crit: bool) -> String:
	var wt := str(weapon.get("weaponType", "fists"))
	if wt == "blunt":
		return CUE_BLUNT_CRIT if is_crit else CUE_BLUNT_HIT
	if wt == "staff":
		return CUE_STAFF_CRIT if is_crit else CUE_STAFF_HIT
	if wt == "fists":
		return CUE_FIST_CRIT if is_crit else CUE_FIST_HIT
	# blade, axe and claws all fall through to the melee pair, exactly as the PWA's
	# `getHitSfx` returns `meleeHitSfxPool` for anything that is not fists/blunt/staff.
	return CUE_MELEE_CRIT if is_crit else CUE_MELEE_HIT


## Every cue this mixer can play, for the tests and for a build-time check.
static func known_cues() -> Array:
	return TABLE.keys()


static func is_known(cue: String) -> bool:
	return TABLE.has(cue)


## Play one cue. An unknown cue is an error, not a silence: a typo in a rule would
## otherwise be indistinguishable from "the fight has no sound here".
func play(cue: String) -> void:
	if cue == "":
		return
	if not is_known(cue):
		push_error("Sfx: unknown cue '%s'" % cue)
		return
	last_cue = cue
	played_count += 1
	for layer in TABLE[cue]:
		var chance := float(layer.get("chance", 1.0))
		if chance < 1.0 and _rng.randf() >= chance:
			continue
		var paths: Array = layer["paths"]
		if paths.is_empty():
			continue
		_start(str(paths[_rng.randi_range(0, paths.size() - 1)]), float(layer.get("volume", 0.7)))


func _ready() -> void:
	AudioBuses.install()
	_rng.randomize()
	# The shared mixer. A screen that owns no mixer of its own (the town, the shop) plays
	# through this, so one sound for a click is one sound everywhere. The most recent mixer
	# wins, which is the arena's while a fight is up — and it is the only one that matters
	# there, since the arena hides the rest of the UI.
	instance = self
	var bus := AudioBuses.bus_or_master(AudioBuses.SFX)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "SfxPlayer%d" % i
		p.bus = bus
		add_child(p)
		_pool.append(p)
	# ⚠️  Read every cue AT BOOT. Loading a file on the first swing is a disk read (and, on
	# the web export, an AudioStreamMP3 set-up) landing in the middle of a fight — the
	# cheap version of the "it stutters sometimes" report. The whole effect set is under a
	# megabyte, so paying for it once at start costs nothing.
	for cue in TABLE:
		for layer in TABLE[cue]:
			for path in (layer["paths"] as Array):
				_cached(str(path))


## Play a cue through the shared mixer. The screen-side entry point for anything that owns
## no mixer: a ShopScreen cannot reach `main`'s audio device and should not have to.
static func play_global(cue: String) -> void:
	var mixer := instance
	if mixer == null:
		return
	mixer.play(cue)


## One free player.
##
## ⚠️  This used to be plain round-robin with the comment "stealing the oldest is the same
## thing". It is not: a player that is still PLAYING its previous cue is cut mid-waveform
## when the next sound is handed to it, and a cut in the middle of a sample is a click. With
## a pool sized above the worst-case overlap a free player is almost always there, so ask
## for one first and only steal when the pool is genuinely full.
func _start(path: String, volume: float) -> void:
	if _pool.is_empty():
		return
	var stream := _cached(path)
	if stream != null:
		_start_stream(stream, volume)


## Read a cue's file once and keep it. An asset that is not there must be loud: a silent
## miss here is the exact failure mode this whole system exists to fix.
func _cached(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		push_error("Sfx: missing audio asset '%s'" % path)
		return null
	var stream: AudioStream = load(path)
	_cache[path] = stream
	return stream


## Hand an already-built stream to a free player. Split out from `_start` so the caller can
## pass a stream it already holds without going through the path cache again.
func _start_stream(stream: AudioStream, volume: float) -> void:
	if _pool.is_empty() or stream == null:
		return
	var player := _free_player()
	player.stream = stream
	player.volume_db = SILENT_DB if volume <= 0.0 else linear_to_db(volume)
	# ⚠️  NO PITCH JITTER. An earlier revision shifted every hit by ±2 semitones "so forty
	# swings do not sound like one file on a loop". On the phone that reads as a processed,
	# slightly detuned hit — the artefacts of resampling a 22-24 kHz source — and Jan's verdict
	# was "nezní to dobře". The cue is the FILE, at the file's own pitch (Jan, Nov 2026).
	player.pitch_scale = 1.0
	player.play()


## A player that is not currently sounding, or — when every one of them is busy — the next
## in rotation. `playing` is false the moment a sample ends, so a finished cue is reusable
## without any bookkeeping.
func _free_player() -> AudioStreamPlayer:
	for player in _pool:
		if not player.playing:
			return player
	var stolen := _pool[_next]
	_next = (_next + 1) % _pool.size()
	return stolen





## The PWA's `toggleMusic` zeroes the MUSIC tracks only — the SFX go through `playSFX` and
## are never muted, so this mixer has no mute of its own. Kept as one place to say so.
func set_muted(_muted: bool) -> void:
	pass
