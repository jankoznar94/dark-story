#!/usr/bin/env python3
"""Rozbor MIDI skladeb od Jana (MuseScore export) - co v nich je.

Pouziti: midi_inspect.py <file.mid> [...]
Vypise: hlavicky (tempo, takt, tonina), seznam stop, rozsah, a noty po taktech
v ceskem zapisu (c1 = stredni C = MIDI 60).
"""
import sys

import mido

NAMES = ["c", "cis", "d", "dis", "e", "f", "fis", "g", "gis", "a", "b", "h"]


def cz(pitch: int) -> str:
    """MIDI -> cesky nazev; c1 = MIDI 60 (stredni C)."""
    octave = pitch // 12 - 1
    return "%s%d" % (NAMES[pitch % 12], octave)


def main(paths):
    for path in paths:
        mid = mido.MidiFile(path)
        print("=" * 70)
        print(path)
        print("  typ %d, stopy %d, delka %.2f s, ticks/beat %d"
              % (mid.type, len(mid.tracks), mid.length, mid.ticks_per_beat))

        for i, tr in enumerate(mid.tracks):
            notes = []
            t = 0
            for msg in tr:
                t += msg.time
                if msg.type == "note_on" and msg.velocity > 0:
                    notes.append([msg.note, t, msg.velocity])
                elif msg.type == "note_off" or (msg.type == "note_on" and msg.velocity == 0):
                    for n in reversed(notes):
                        if n[0] == msg.note and len(n) == 3:
                            n.append(t)
                            break
            notes = [n for n in notes if len(n) == 4]
            metas = [m for m in tr if m.type in ("set_tempo", "time_signature", "key_signature",
                                                 "track_name", "instrument_name")]
            print("  stopa %d: %-28s not=%3d" % (i, repr(tr.name), len(notes)))
            for m in metas:
                if m.type == "set_tempo":
                    print("      tempo %.1f BPM" % (60e6 / m.tempo))
                elif m.type == "time_signature":
                    print("      takt %d/%d" % (m.numerator, m.denominator))
                elif m.type == "key_signature":
                    print("      tonina %s" % m.key)
                elif m.type == "instrument_name":
                    print("      nastroj %s" % m.name)
            if notes:
                ps = sorted(n[0] for n in notes)
                print("      rozsah %s - %s (%d-%d)"
                      % (cz(ps[0]), cz(ps[-1]), ps[0], ps[-1]))
                b0 = min(n[1] for n in notes)
                b1 = max(n[3] for n in notes)
                print("      cas %.2f - %.2f s" % (b0 / mid.ticks_per_beat * 0.5,
                                                  b1 / mid.ticks_per_beat * 0.5))
                # rozlozeni po dobach (predpoklad 4/4, beat = ticks_per_beat)
                beats = sorted({round(n[1] / mid.ticks_per_beat, 2) for n in notes})
                print("      pocatek not na dobach: %s%s"
                      % (", ".join("%.2f" % b for b in beats[:24]),
                         " ..." if len(beats) > 24 else ""))
        print()


if __name__ == "__main__":
    main(sys.argv[1:])
