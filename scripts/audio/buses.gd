extends RefCounted
class_name AudioBuses
## The game's two mix buses. A LEAF module on purpose: it preloads nothing, so
## `sfx.gd` and `music.gd` can both reach it without a `preload` cycle between them.
##
## ⚠️  Why the buses exist at all. Every cue used to play into `Master` at the PWA's own
## linear volumes (a hit 0.70, music 0.90-1.00). That was measured as a CLIPPING mix, not
## as a loud one: one ordinary swing (weapon layer + the 30 % impact layer) over the
## overworld track reached +1.2 dBFS, four overlapping sounds +4.3 dBFS and a full
## eight-player pool +6.9 dBFS. Anything over 0 dBFS is the hard limiter clamping, which
## the ear hears as crackle and fizz — Jan's "divně praskají a šumí" — no matter how good
## the files are (they are: peaks -0.7 to -3 dB, no clipping in any of them).
##
## The fix is headroom, not a different limiter. The per-cue volumes in `sfx.gd` are the
## PWA's own and keep their RELATIVE balance; these two bus gains move the whole bed down
## so the sum of the eight-player pool still lands under the ceiling:
##
##   measured peaks with these gains: 4 overlapping hits + music = -1.7 dBFS,
##   full pool + music = -0.9 dBFS  ->  the limiter is a safety net, not a shaper.
##
## ⚠️  A mute must never touch these. `Music.set_muted` writes the MUSIC player's own
## volume; silencing a bus here would silence the effects with it (the exact bug
## `test_music.gd` guards against).

const MUSIC := "Music"
const SFX := "SFX"

## The PWA's music bed, 3 dB down. It carries its own peak around -14 dBFS, so it is never
## what clips — it only has to stop adding to an already hot effect sum.
const MUSIC_DB := -3.0
## The effects, 6 dB down: this is the headroom the eight-player pool needs. A single hit
## still peaks ~9 dB above the music bed, so the balance the PWA had is kept.
const SFX_DB := -6.0


## Create the buses if they are missing and pin their gain. Idempotent: called once by
## `main` before the first player exists, and again by each mixer's `_ready` so a headless
## test that builds only that mixer still gets a valid bus to route into.
static func install() -> void:
	_ensure(MUSIC, MUSIC_DB)
	_ensure(SFX, SFX_DB)


static func _ensure(bus_name: String, volume_db: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")
	AudioServer.set_bus_volume_db(index, volume_db)


## The bus a player should use, or `Master` when the buses could not be created (an
## audio driver without bus support must degrade to "sounds, just not gain-staged" rather
## than to an invalid bus name).
static func bus_or_master(preferred: String) -> String:
	return preferred if AudioServer.get_bus_index(preferred) >= 0 else "Master"
