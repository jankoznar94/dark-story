#!/usr/bin/env python3
"""Smycka pro hru: tri Janovy skladby z MuseScore navazane do jedne smycky.

Zdroje (assets/music/*.mid, export z MuseScore):
  A skladba_a_ab.mid     25,5 s  Ab dur, 4/4, 80 BPM, violoncello + kontrabas
  B skladba_b_sbor.mid   57,0 s  G dur/a moll, 6/8, 60 BPM, viola + varhany + violoncello + kontrabas
  C skladba_c_kratka.mid 18,0 s  Ab dur, 4/4, 60 BPM, violoncello + kontrabas

Proc to jde navazat (overeno z not, ne z poslechu):
  * vsechny tri kusy konci i zacinaji na pedalu Bb - A i C konci na b (Bb) a B zacina
    i konci na Bbm (po transpozici); spoj je tedy drzeny ton, ne slep.
  * B je v G, A/C v Ab. Transponujeme B o pulton nahoru (G -> Ab): jeho akordy
    Am-D-G-C-Em se tim stanou Bbm-Eb-Ab-Db-Fm, coz je v Ab dur ii-V-I-IV-vi,
    tedy zadny modalni exot, ale uplne normalni harmonie.

Vystup: assets/audio/theme.ogg  (prepisuje se JEN s parametrem --write-theme)

Zvukovy aparat je prevzaty z tools/make_music.py (tone/kick/hat/add, SR=22050),
takze smycka zni stejnou rodinou jako stavajici hudba ve hre.
"""
import argparse
import os
import subprocess
import sys
import wave

import mido
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import make_music as mm  # tone(), add(), SR  (puvodni generator hry)

NAMES = ["c", "cis", "d", "dis", "e", "f", "fis", "g", "gis", "a", "b", "h"]


def cz(p):
    return "%s%d" % (NAMES[p % 12], p // 12 - 1)


def hz(p):
    return 440.0 * 2.0 ** ((p - 69) / 12.0)


# ---------------------------------------------------------------- nacteni MIDI
def load(path):
    """Vrati stopy jako seznam (nazev, [(takt_beat, dur_beat, vyska)]).

    Cas je v "beat" = ctvrtovych notach (ticks_per_beat), tempo je vsude 60 nebo
    80 BPM na ctvrtku, takze 1 beat = 60/BPM sekundy.
    """
    mid = mido.MidiFile(path)
    tpb = mid.ticks_per_beat
    tracks = []
    for tr in mid.tracks:
        t = 0
        live = {}
        evs = []
        for msg in tr:
            t += msg.time
            if msg.type == "note_on" and msg.velocity > 0:
                live.setdefault(msg.note, []).append(t)
            elif msg.type == "note_off" or (msg.type == "note_on" and msg.velocity == 0):
                if live.get(msg.note):
                    t0 = live[msg.note].pop(0)
                    evs.append((t0 / tpb, (t - t0) / tpb, msg.note))
        evs.sort()
        tracks.append((tr.name, evs))
    return {"tpb": tpb, "tracks": tracks, "len_s": mid.length}


A = load(os.path.join(ROOT, "assets/music/skladba_a_ab.mid"))
B = load(os.path.join(ROOT, "assets/music/skladba_b_sbor.mid"))
C = load(os.path.join(ROOT, "assets/music/skladba_c_kratka.mid"))

# ------------------------------------------------------------------ skladatelia
# Harmonicky plan doprovodu pro A a C (akordy, ktere v originalu nejsou - v
# predloze hraje jen violoncello a kontrabas). Kazdy akord je vybran tak, aby
# obsahoval ton basu a co nejvic tonu melodie, ktere v tom okne zni; kontrola
# nize to vypise a pri spatnem vyberu to je videt.
#   (od_beat, do_beat, nazev, [noty])
CHORDS_C = [
    (0, 2, "Bbm7", [58, 61, 65, 68]),
    (2, 4, "Ab", [56, 60, 63]),
    (4, 6, "Bbm", [58, 61, 65]),
    (6, 8, "Ab7", [56, 60, 63, 66]),
    (8, 10, "Db", [61, 65, 68]),
    (10, 12, "Ab", [56, 60, 63]),
    (12, 14, "Fm7", [53, 56, 60, 63]),
    (14, 16, "Bbm7", [58, 61, 65, 68]),
    (16, 18, "Bbm", [58, 61, 65]),
]
CHORDS_A = [
    (0, 2, "Bbm7", [58, 61, 65, 68]),
    (2, 4, "Bbm7", [58, 61, 65, 68]),
    (4, 6, "Bbm7", [58, 61, 65, 68]),
    (6, 8, "Gbmaj7", [61, 65, 66, 70]),
    (8, 10, "Ab", [56, 60, 63]),
    (10, 12, "Bbm7", [58, 61, 65, 68]),
    (12, 14, "Cm7", [60, 63, 67, 70]),
    (14, 18, "Gbmaj7", [54, 58, 61, 65]),
    (18, 22, "Bbm7", [58, 61, 65, 68]),
    (22, 24, "Gbmaj7", [61, 65, 66, 70]),
    (24, 26, "Bbm", [58, 61, 65]),
    (26, 27, "Ab", [56, 60, 63]),
    (27, 28, "Db", [49, 53, 56]),
    (28, 29, "Ebm", [51, 55, 58]),
    (29, 30, "Bbm7", [46, 49, 53, 56]),
    (30, 32, "Ab", [44, 48, 51]),
    (32, 34, "Bbm", [58, 61, 65]),
]

# ------------------------------------------------------------------ casova osa
class Line:
    """Sekce na absolutni casove ose v sekundach."""

    def __init__(self, name, t0, spp):
        self.name = name
        self.t0 = t0
        self.spp = spp              # sekund na beat
        self.notes = []             # (t_sec, dur_sec, vyska, druh)
        self.gain = 1.0             # uroven sekce ve vyslednem mixu

    def add(self, t_beat, dur_beat, pitch, kind):
        self.notes.append((self.t0 + t_beat * self.spp, dur_beat * self.spp, pitch, kind))

    def end(self):
        return max((t + d for t, d, _, _ in self.notes), default=self.t0)


class RampLine(Line):
    """Prechod s plynulou zmenou tempa (A je 80, B a C jsou 60 - slepit je
    pevnym tempem by bylo slyset, proto se tempo mezi sekcemi plynule meni)."""

    def __init__(self, name, t0, beats, bpm0, bpm1):
        Line.__init__(self, name, t0, 1.0)
        self.times = [0.0]
        for i in range(beats):
            f = i / max(1.0, beats - 1.0)
            self.times.append(self.times[-1] + 60.0 / (bpm0 + (bpm1 - bpm0) * f))

    def at(self, beat):
        i = int(beat)
        f = beat - i
        if i + 1 >= len(self.times):
            return self.times[-1] + f * (self.times[-1] - self.times[-2])
        return self.times[i] + (self.times[i + 1] - self.times[i]) * f

    def add(self, t_beat, dur_beat, pitch, kind):
        t = self.at(t_beat)
        d = self.at(t_beat + dur_beat) - t
        self.notes.append((self.t0 + t, d, pitch, kind))


def add_piece(line, piece, melody_tr, bass_tr, chords=None, transpose=0):
    _, mel = piece["tracks"][melody_tr]
    for tb, db, p in mel:
        line.add(tb, db, p + transpose, "mel")
    if bass_tr is not None:
        _, bas = piece["tracks"][bass_tr]
        for tb, db, p in bas:
            line.add(tb, db, p + transpose, "bas")
    if chords:
        for a, b, name, notes in chords:
            for p in notes:
                line.add(a, b - a, p, "pad")


# Smycka je A -> B -> C -> (zpet na A). Poradi je dane tim, ze hlavni veta ma
# pri hrani zaznit hned; kazdy spoj je pritom jeden a ten sam drzeny Bb, proto
# je jedno, kterym smerem se skladby poskladaji.
ORDER = ["A", "T2", "B", "T3", "C", "T1"]

# STRIDMY = jen to, co je v predloze. Zadny dokomponovany doprovod k A a C
# (v predloze hraje jen violoncello a kontrabas), zadne rozbehy v prechodech -
# jen drzeny Bb, ktery uzavira kazdy spoj. Jan (Oct 2026): "Mozna jsi to
# prekomponoval. Ty harmonie mi prijdou komplikovanejsi nez original."
STRIDMY = True

SECTIONS = []
_t = [0.0]


def new(name, bpm):
    ln = Line(name, _t[0], 60.0 / bpm)
    SECTIONS.append(ln)
    return ln


# 1) A - hlavni veta (Ab dur, 4/4, 80 BPM)
sec_a = new("A", 80.0)
add_piece(sec_a, A, 0, 1, None if STRIDMY else CHORDS_A)
_t[0] = sec_a.end()

# 2) prechod A -> B: 4 doby, Bb drzi a pribere se k nemu Bbm (akord, kterym B zacina)
sec_t2 = RampLine("T2", _t[0], 4, 80.0, 60.0)
SECTIONS.append(sec_t2)
sec_t2.add(0.0, 4.0, 34, "bas")
if STRIDMY:
    sec_t2.add(0.0, 4.0, 41, "ped")                 # jen drzena kvinta na Bb
else:
    sec_t2.add(0.0, 4.0, 58, "pad")
    sec_t2.add(2.0, 2.0, 61, "pad")
    sec_t2.add(2.0, 2.0, 65, "pad")
    for i, p in enumerate([46, 49, 53, 56, 58, 61]):   # arpeggio Bbm7 -> Bbm
        sec_t2.add(i * 0.7, 1.2, p, "pad")
_t[0] = sec_t2.end()

# 3) B - sborova epizoda, transponovana +1 (G -> Ab)
sec_b = new("B", 60.0)
add_piece(sec_b, B, 3, None, transpose=1)
for tb, db, p in B["tracks"][4][1]:          # violoncello = akordy
    sec_b.add(tb, db, p + 1, "pad")
# pedal Bb v basech: v predloze drzi cely kus; na malem reproduktoru drzeny
# ton zmizi, proto se obnovuje po taktech (6/8 takt = 3 ctvrtky).
for i in range(int(B["len_s"] / 3.0) + 1):
    sec_b.add(i * 3.0, 2.6, 34, "bas")
    sec_b.add(i * 3.0, 2.6, 45, "bas2")
sec_b.gain = 0.78   # sbor ma tri vrstvy, sam by prehlusil A i C
_t[0] = sec_b.end()

# 4) prechod B -> C: 2 doby na vydechnuti, konci na Bbm = presne to, cim C zacina
sec_t3 = new("T3", 60.0)
sec_t3.add(0.0, 2.0, 34, "bas")
for p in ((41,) if STRIDMY else (58, 61, 65)):
    sec_t3.add(0.0, 2.0, p, "ped" if STRIDMY else "pad")
_t[0] = sec_t3.end()

# 5) C - ticha varianta tehoz tematu (Ab dur, 4/4, 60 BPM)
sec_c = new("C", 60.0)
add_piece(sec_c, C, 0, 1, None if STRIDMY else CHORDS_C)
_t[0] = sec_c.end()

# 6) prechod C -> A a zaroven uzavreni smycky: Bb drzi, zrychleni do hlavni vety
sec_t1 = RampLine("T1", _t[0], 2, 60.0, 80.0)
SECTIONS.append(sec_t1)
sec_t1.add(0.0, 2.0, 34, "bas")
if STRIDMY:
    sec_t1.add(0.0, 2.0, 41, "ped")
else:
    for i, p in enumerate([58, 61, 65, 68, 70]):
        sec_t1.add(i * 0.4, 1.6, p, "pad")
_t[0] = sec_t1.end()

assert [s.name for s in SECTIONS] == ORDER, [s.name for s in SECTIONS]
ALL = [n for s in SECTIONS for n in s.notes]
TOTAL = _t[0]

# ---------------------------------------------------------------------- mix
# stejne tvary vlny jako v make_music.tone(), jen s obalkou, ktera umi ton i
# PODRZET: smyckova hudba z make_music mela vsechno perkusivni (kratky dozvuk),
# ale tady jsou to smyccove linky - dlouha nota musi znit, ne hned zmizet.
def waveform(shape, freq, n):
    t = np.arange(n) / float(mm.SR)
    if shape == "square":
        return np.sign(np.sin(2.0 * np.pi * freq * t))
    if shape == "tri":
        return (2.0 / np.pi) * np.arcsin(np.sin(2.0 * np.pi * freq * t))
    return np.sin(2.0 * np.pi * freq * t)


def held(shape, freq, dur, amp, atk=0.030, dec=0.22, sus=0.70, rel=0.30):
    n = max(1, int(dur * mm.SR))
    env = np.full(n, sus)
    a = max(1, int(atk * mm.SR))
    a = min(a, n)
    env[:a] = np.linspace(0.0, 1.0, a)
    d = min(n - a, max(1, int(dec * mm.SR))) if n > a else 0
    if d > 0:
        env[a:a + d] = np.linspace(1.0, sus, d)
    r = min(int(rel * mm.SR), n)
    env[n - r:] *= np.linspace(1.0, 0.0, r)
    return amp * waveform(shape, freq, n) * env


VOICE = {
    #            tvar,   amp,   sustain? (atk, dec, sus, rel)
    "mel":  ("tri", 0.150, (0.040, 0.30, 0.72, 0.35)),
    "pad":  ("tri", 0.045, (0.060, 0.40, 0.60, 0.45)),
    "bas":  ("tri", 0.060, None),          # bas = kratky uder, ne drzeny ton
    "bas2": ("tri", 0.030, None),
    "ped":  ("tri", 0.050, (0.080, 0.50, 0.55, 0.50)),
}


def render():
    buf = np.zeros(int((TOTAL + 0.6) * mm.SR))   # 0,6 s ticha na konci smycky
    gain_of = {}
    for s in SECTIONS:
        for n in s.notes:
            gain_of[n] = s.gain
    for t_sec, dur, pitch, kind in ALL:
        shape, amp, env = VOICE[kind]
        amp *= gain_of.get((t_sec, dur, pitch, kind), 1.0)
        dur = max(dur, 0.05)
        if env is None:
            sig = mm.tone(hz(pitch), dur, shape, amp, 1.5)
        else:
            sig = held(shape, hz(pitch), dur, amp, *env)
        mm.add(buf, sig, t_sec)
    buf /= max(1e-9, np.abs(buf).max())
    buf *= 0.90
    edge = int(0.010 * mm.SR)
    buf[:edge] *= np.linspace(0.0, 1.0, edge)
    buf[-edge:] *= np.linspace(1.0, 0.0, edge)
    return buf


def band_db(x, lo, hi):
    """Prumerna energie pasma v dB pres cely soubor (segmentovany spektrum)."""
    n = 1 << 15
    hop = n // 2
    win = np.hanning(n)
    fr = np.fft.rfftfreq(n, 1.0 / mm.SR)
    sel = (fr >= lo) & (fr < hi)
    acc = 0.0
    segs = 0
    for i in range(0, len(x) - n, hop):
        spec = np.fft.rfft(x[i:i + n] * win)
        acc += float((np.abs(spec[sel]) ** 2).sum())
        segs += 1
    return 10.0 * np.log10(max(1e-24, acc / max(1, segs)))


def check_chords():
    """Kontrola doprovodu A a C: noty melodie proti AKORDUM, ktere v tu chvili
    skutecne zni. Hlasi se jen realny ostny zvuk - kdyz je doprovodni ton od
    melodie bliz nez oktavu a tvori s ni malou sekundu nebo triton. Vzdaleny
    pultón (9. nebo 13. stupen pres oktavu) je normalni extenze, ne chyba."""
    if STRIDMY:
        print("kontrola doprovodu: vynechano (stridma verze nema dokomponovany doprovod)")
        return 0
    ok = ext = 0
    bad = []
    for sec, _table in ((sec_c, CHORDS_C), (sec_a, CHORDS_A)):
        pads = [(t, t + d, p) for t, d, p, k in sec.notes if k == "pad"]
        for t_sec, dur, pitch, kind in sec.notes:
            if kind != "mel":
                continue
            hits = [p for (pt, pe, p) in pads if pt < t_sec + dur and pe > t_sec]
            if not hits:
                bad.append((sec.name, cz(pitch), t_sec - sec.t0, "-- zadny doprovod"))
                continue
            near = [p for p in hits if abs(p - pitch) < 12]
            if not near:
                ext += 1
                continue
            cls = {p % 12 for p in hits}
            # souzvuk do oktavy: mala sekunda vzdy, triton jen kdyz nota neni
            # tonem akordu (Gb nad Ab7 je septima, ne ostny ton)
            clash = [p for p in near
                     if abs(p - pitch) == 1
                     or (abs(p - pitch) == 6 and pitch % 12 not in cls)]
            if clash:
                bad.append((sec.name, cz(pitch), (t_sec - sec.t0) / sec.spp,
                            "blizke: " + ",".join(cz(p) for p in sorted(clash))))
            else:
                ok += 1
    for name, note, tb, what in bad:
        print("  OSTRY TON: %-2s %-4s beat %6.2f  %s" % (name, note, tb, what))
    print("kontrola doprovodu: %d v poradku, %d pres oktavu (extenze), %d ostrych"
          % (ok, ext, len(bad)))
    return len(bad)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--write-theme", action="store_true",
                    help="prepsat assets/audio/theme.ogg (jinak pise theme_suite.ogg)")
    ap.add_argument("--preview", default="/tmp/zily2_suite_preview.mp3")
    args = ap.parse_args()

    print("delky: A %.1f s, B %.1f s, C %.1f s" % (A["len_s"], B["len_s"], C["len_s"]))
    for s in SECTIONS:
        print("  %-3s %6.2f - %6.2f s  (%d not)" % (s.name, s.t0, s.end(), len(s.notes)))
    print("celkem %.2f s = %.2f min" % (TOTAL, TOTAL / 60.0))
    print("not celkem: %d" % len(ALL))
    check_chords()

    buf = render()
    print("vzorku: %d (%.2f s vcetne ticha na konci)" % (len(buf), len(buf) / mm.SR))
    print("hlasitost po sekcich (RMS):")
    for s in SECTIONS:
        a, b = int(s.t0 * mm.SR), int(s.end() * mm.SR)
        seg = buf[a:b]
        print("  %-3s %6.1f s  RMS %.4f  spicka %.3f"
              % (s.name, (b - a) / mm.SR, float(np.sqrt((seg ** 2).mean())), np.abs(seg).max()))
    n30 = int(0.030 * mm.SR)
    print("spoj smycky: prvnich 30 ms RMS %.5f, poslednich 30 ms RMS %.5f, "
          "posledni vzorek %.6f, prvni vzorek %.6f"
          % (float(np.sqrt((buf[:n30] ** 2).mean())),
             float(np.sqrt((buf[-n30:] ** 2).mean())), buf[-1], buf[0]))
    print("bas 40-250 Hz %6.1f dB   melodie 400-2000 Hz %6.1f dB   rozdil %+.1f dB"
          % (band_db(buf, 40, 250), band_db(buf, 400, 2000),
             band_db(buf, 40, 250) - band_db(buf, 400, 2000)))
    print("spicka %.3f  RMS %.4f" % (np.abs(buf).max(), float(np.sqrt((buf ** 2).mean()))))

    pcm = np.clip(buf * 32767.0, -32768, 32767).astype("<i2")
    tmp = "/tmp/zily2_suite.wav"
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(mm.SR)
        w.writeframes(pcm.tobytes())

    out_dir = os.path.join(ROOT, "assets", "audio")
    os.makedirs(out_dir, exist_ok=True)
    name = "theme.ogg" if args.write_theme else (
        "theme_suite_stridmy.ogg" if STRIDMY else "theme_suite.ogg")
    out = os.path.join(out_dir, name)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp,
                    "-c:a", "libvorbis", "-q:a", "3", out], check=True)
    print("zapsano: %s (%.0f kB)" % (out, os.path.getsize(out) / 1024.0))

    if args.preview:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp,
                        "-c:a", "libmp3lame", "-b:a", "96k", args.preview], check=True)
        print("nahled: %s (%.0f kB)" % (args.preview, os.path.getsize(args.preview) / 1024.0))
