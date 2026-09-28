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
## The PWA's `sfxSuccess` / `sfxBossDefeat` — the fight-ending jingles, both of which it
## SYNTHESISES with `playTone` oscillators rather than playing a file. See `TONES`.
const CUE_VICTORY := "victory"
const CUE_BOSS_DEFEAT := "boss_defeat"

## ⚠️  THE SAME SOUND, TWO DIFFERENT EVENTS, and the port had them crossed.
##
## The PWA has BOTH a `levelupSfx` FILE (`assets/sfx/levelup.mp3`) and an `sfxLevelUp()`
## OSCILLATOR fanfare, and they are not interchangeable:
##
##   * gaining a level (XP threshold) -> `sfxLevelUp()`, the oscillator + `duckBgm`
##   * spending a talent / attribute point -> `playSFX(levelupSfx)`, the FILE
##
## An earlier revision of this port played the FILE on a level-up. That is the OTHER
## event's sound, and it reads as "the fanfare is wrong" rather than as a wrong mapping.
##
## `playTone` is a WebAudio oscillator and has no Godot equivalent to reuse, so the four
## tones are described as data (`TONES`) and rendered into a `AudioStreamWAV` once. Each
## entry is `{freq, ms, shape, volume, delay_ms}` — the PWA's own numbers, verbatim.
const TONES := {
	CUE_LEVELUP: [
		{"freq": 392.0, "ms": 100.0, "shape": "sine", "volume": 0.12, "delay_ms": 0.0},
		{"freq": 523.0, "ms": 100.0, "shape": "sine", "volume": 0.12, "delay_ms": 100.0},
		{"freq": 659.0, "ms": 120.0, "shape": "sine", "volume": 0.14, "delay_ms": 200.0},
		{"freq": 784.0, "ms": 150.0, "shape": "sine", "volume": 0.16, "delay_ms": 300.0},
	],
	CUE_VICTORY: [
		{"freq": 523.0, "ms": 100.0, "shape": "sine", "volume": 0.12, "delay_ms": 0.0},
		{"freq": 659.0, "ms": 100.0, "shape": "sine", "volume": 0.12, "delay_ms": 80.0},
		{"freq": 784.0, "ms": 150.0, "shape": "sine", "volume": 0.14, "delay_ms": 160.0},
	],
	CUE_BOSS_DEFEAT: [
		{"freq": 523.0, "ms": 150.0, "shape": "sine", "volume": 0.14, "delay_ms": 0.0},
		{"freq": 659.0, "ms": 150.0, "shape": "sine", "volume": 0.14, "delay_ms": 100.0},
		{"freq": 784.0, "ms": 150.0, "shape": "sine", "volume": 0.16, "delay_ms": 200.0},
		{"freq": 1047.0, "ms": 300.0, "shape": "sine", "volume": 0.18, "delay_ms": 300.0},
	],
}

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
	CUE_ENEMY_CAST: [
		{"paths": ["res://assets/audio/fire_spell.mp3", "res://assets/audio/ice_spell.mp3",
			"res://assets/sfx/lightning_spell.mp3", "res://assets/sfx/lightning_spell2.mp3"],
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
	CUE_SHOP: [
		{"paths": ["res://assets/sfx/shop.mp3"], "volume": 0.70, "chance": 1.0},
	],
	CUE_EQUIP: [
		{"paths": ["res://assets/sfx/equip.mp3"], "volume": 0.70, "chance": 1.0},
	],
	CUE_LEVELUP: [
		{"paths": ["res://assets/sfx/levelup.mp3"], "volume": 0.70, "chance": 1.0},
	],
	## ⚠️  The FILE, which belongs to SPENDING a point — see the note above `CUE_LEVELUP`.
	## The PWA's own `upgradeAttr` and its talent-invest handler both call
	## `playSFX(levelupSfx)`, i.e. this same mp3.
	CUE_POINT_SPENT: [
		{"paths": ["res://assets/sfx/levelup.mp3"], "volume": 0.70, "chance": 1.0},
	],
	CUE_CLICK: [
		{"paths": ["res://assets/sfx/click.mp3"], "volume": 0.70, "chance": 1.0},
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
	return TABLE.has(cue) or TONES.has(cue)


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
	# A SYNTHESISED cue is a whole jingle in one stream, so it has no layers and no
	# per-layer volume — its own mixed volume is baked into the samples.
	if TONES.has(cue):
		_start_stream(_jingle_stream(cue), 1.0)
		return
	for layer in TABLE[cue]:
		var chance := float(layer.get("chance", 1.0))
		if chance < 1.0 and _rng.randf() >= chance:
			continue
		var paths: Array = layer["paths"]
		if paths.is_empty():
			continue
		_start(str(paths[_rng.randi_range(0, paths.size() - 1)]), float(layer.get("volume", 0.7)))


func _ready() -> void:
	_rng.randomize()
	# The shared mixer. A screen that owns no mixer of its own (the town, the shop) plays
	# through this, so one sound for a click is one sound everywhere. The most recent mixer
	# wins, which is the arena's while a fight is up — and it is the only one that matters
	# there, since the arena hides the rest of the UI.
	instance = self
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "SfxPlayer%d" % i
		p.bus = "Master"
		add_child(p)
		_pool.append(p)


## Play a cue through the shared mixer. The screen-side entry point for anything that owns
## no mixer: a ShopScreen cannot reach `main`'s audio device and should not have to.
static func play_global(cue: String) -> void:
	var mixer := instance
	if mixer == null:
		return
	mixer.play(cue)


## One free player. The pool is round-robin rather than "find a free one": with eight players
## and at most four overlapping hits, stealing the oldest is the same thing and cannot fail.
func _start(path: String, volume: float) -> void:
	if _pool.is_empty():
		return
	var stream: AudioStream = _cache.get(path, null)
	if stream == null:
		if not ResourceLoader.exists(path):
			# An asset that is not there must be loud: a silent miss here is the exact
			# failure mode this whole system exists to fix.
			push_error("Sfx: missing audio asset '%s'" % path)
			return
		stream = load(path)
		_cache[path] = stream
	_start_stream(stream, volume)


## Hand an already-built stream to a free player. Split out from `_start` because a
## synthesised jingle has no file behind it and no cache key.
func _start_stream(stream: AudioStream, volume: float) -> void:
	if _pool.is_empty() or stream == null:
		return
	var player := _pool[_next]
	_next = (_next + 1) % _pool.size()
	player.stream = stream
	player.volume_db = SILENT_DB if volume <= 0.0 else linear_to_db(volume)
	# ±2 semitones of pitch jitter, so a fight's forty identical swings stop sounding like
	# one file on a loop. The PWA has no variation at all — it re-plays one `Audio` element —
	# and a repeated cue is the cheapest, most audible place to buy "alive". Only a FILE gets
	# it: a synthesised jingle (`TONES`) carries its own intended pitch and is a fanfare, not
	# a repeated blow.
	player.pitch_scale = _rng.randf_range(0.89, 1.12)
	player.play()


## The PWA's `playTone` jingle, rendered to samples.
##
## ⚠️  `playTone` is a WebAudio `OscillatorNode` fed straight into `destination`: nothing
## exists on disk, so there is no asset to port and the shape has to be BUILT. Each tone
## gets its own slot in one buffer at its own `delay_ms` offset, which is what the PWA's
## `setTimeout(() => playTone(...), delay)` chain produces — one stream rather than four
## timers, so it cannot drift and a test can measure its length.
##
## The PWA's `g.exponentialRampToValueAtTime(0.001, now + d)` is the envelope: the tone
## decays to a thousandth of its volume over its own duration.
func _jingle_stream(cue: String) -> AudioStream:
	var cached: AudioStream = _cache.get("tone:%s" % cue, null)
	if cached != null:
		return cached
	var tones: Array = TONES.get(cue, [])
	if tones.is_empty():
		return null
	var rate := 22050
	var pcm := PackedFloat32Array()
	var total_ms := 0.0
	for tone in tones:
		total_ms = maxf(total_ms, float(tone["delay_ms"]) + float(tone["ms"]))
	# A tail so the last tone's decay is not cut off mid-sample.
	var frames := int(round((total_ms + 20.0) / 1000.0 * float(rate)))
	pcm.resize(frames)
	pcm.fill(0.0)
	for tone in tones:
		var freq := float(tone["freq"])
		var dur_ms := float(tone["ms"])
		var vol := float(tone["volume"])
		var shape := str(tone["shape"])
		var start := int(round(float(tone["delay_ms"]) / 1000.0 * float(rate)))
		var count := int(round(dur_ms / 1000.0 * float(rate)))
		for i in count:
			var idx := start + i
			if idx < 0 or idx >= frames:
				continue
			var t := float(i) / float(rate)
			var phase := TAU * freq * t
			var s := 0.0
			match shape:
				"square":
					s = 1.0 if sin(phase) >= 0.0 else -1.0
				"sawtooth":
					# `phase / TAU` normalised to [0,1), then mapped to [-1,1).
					s = 2.0 * (freq * t - floor(freq * t + 0.5))
				_:
					s = sin(phase)
			# `exponentialRampToValueAtTime(0.001, now + d)`, as a per-sample factor.
			var frac := float(i) / float(maxi(1, count))
			var env := pow(0.001 / maxf(vol, 0.0001), frac) if vol > 0.0 else 0.0
			pcm[idx] += s * vol * env
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	for i in frames:
		var v := clampf(pcm[i], -1.0, 1.0)
		bytes.encode_s16(i * 2, int(round(v * 32767.0)))
	stream.data = bytes
	_cache["tone:%s" % cue] = stream
	return stream



## The PWA's `toggleMusic` zeroes the MUSIC tracks only — the SFX go through `playSFX` and
## are never muted, so this mixer has no mute of its own. Kept as one place to say so.
func set_muted(_muted: bool) -> void:
	pass
