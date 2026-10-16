#!/usr/bin/env python3
"""Vypise noty MIDI po dobach ve tvaru (zacatek, trvani, vyska) + cesky nazev."""
import sys

import mido

NAMES = ["c", "cis", "d", "dis", "e", "f", "fis", "g", "gis", "a", "b", "h"]
FILES = {
    "A": "/home/martin_fabian/.hermes/profiles/cfsb-agent/cache/audio/audio_2909c59d6ffd.mp3",
    "B": "/home/martin_fabian/.hermes/profiles/cfsb-agent/cache/audio/audio_c5147b2fc5a1.mp3",
    "C": "/home/martin_fabian/.hermes/profiles/cfsb-agent/cache/audio/audio_c8c23b011fc0.mp3",
}


def cz(p):
    return "%s%d" % (NAMES[p % 12], p // 12 - 1)


def notes_of(path):
    mid = mido.MidiFile(path)
    tpb = mid.ticks_per_beat
    out = []
    for i, tr in enumerate(mid.tracks):
        t = 0
        live = {}
        evs = []
        for msg in tr:
            t += msg.time
            if msg.type == "note_on" and msg.velocity > 0:
                live.setdefault(msg.note, []).append([t, msg.velocity])
            elif msg.type == "note_off" or (msg.type == "note_on" and msg.velocity == 0):
                if live.get(msg.note):
                    s, v = live[msg.note].pop(0)
                    evs.append([s / tpb, (t - s) / tpb, msg.note, v])
        evs.sort()
        if evs:
            out.append((i, tr.name, evs))
    return mid, out


for key, path in FILES.items():
    mid, tracks = notes_of(path)
    tempos = [60e6 / m.tempo for tr in mid.tracks for m in tr if m.type == "set_tempo"]
    print("=" * 72)
    print("%s  %s" % (key, path.split("/")[-1]))
    print("   BPM %s  tpb %d  delka %.1f s" % (sorted({round(x, 2) for x in tempos}), mid.ticks_per_beat, mid.length))
    for i, name, evs in tracks:
        print("  -- stopa %d %s (%d not)" % (i, name, len(evs)))
        for s, d, p, v in evs:
            print("     %7.2f  dur %5.2f  %-4s (%2d)  vel %d" % (s, d, cz(p), p, v))
