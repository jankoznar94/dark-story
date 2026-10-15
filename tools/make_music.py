#!/usr/bin/env python3
"""Generuje hudbu hry: kratkou primitivni smycku (assets/audio/theme.ogg).

Jan (Oct 2026): "A dáme do hry nějakou primitivní hudbu."

Smycka je 8 taktu v a moll (Am - F - C - G dvakrat), 100 BPM, 19,2 s:
- bas: obdelnik na zakladnim tonu (dum na prvni a treti dobe),
- arpeggio: trojuhelnik ve dvou oktavach, osminy,
- kopak: mekky sinusovy kopanec na prvni a treti dobe,
- hat: tichy sum na rozdelene doby.

Vse se pocita v numpy (zadny model, zadny nahodny vysledek) a zapisuje se
pres ffmpeg do OGG, aby soubor v buildu nebyl megabajt. Delky not jsou
ZAMERNE kratsi nez takt, aby na konci smycky nezbyl dozvuk a smycka
neklikala.
"""
import os
import subprocess
import wave

import numpy as np

SR = 22050
BPM = 100.0
BEAT = 60.0 / BPM
BARS = 8
TOTAL = BARS * 4 * BEAT


def tone(freq, dur, shape="square", amp=1.0, decay=4.0):
    n = max(1, int(dur * SR))
    t = np.arange(n) / SR
    if shape == "square":
        s = np.sign(np.sin(2.0 * np.pi * freq * t))
    elif shape == "tri":
        s = (2.0 / np.pi) * np.arcsin(np.sin(2.0 * np.pi * freq * t))
    else:
        s = np.sin(2.0 * np.pi * freq * t)
    env = np.exp(-decay * t)
    a = min(n, int(0.006 * SR))
    env[:a] *= np.linspace(0.0, 1.0, a)
    return amp * s * env


def kick(dur=0.15):
    # Jan (Oct 2026): "údery na první a třetí dobu jsou příliš výrazné. To bych
    # lehce ztlumil." - kopak je proto tichy (0,26 misto 0,5); zbytek smycky se
    # tim pri normalizaci lehce zvedne, takze se zmeni POMER, ne jen hlasitost.
    n = max(1, int(dur * SR))
    t = np.arange(n) / SR
    f = 120.0 * np.exp(-t * 22.0) + 42.0
    phase = 2.0 * np.pi * np.cumsum(f) / SR
    return 0.26 * np.sin(phase) * np.exp(-t * 14.0)


def hat(dur=0.04):
    n = max(1, int(dur * SR))
    t = np.arange(n) / SR
    rng = np.random.default_rng(7)      # pevny seed = stejny soubor pri kazdem behu
    return 0.06 * rng.uniform(-1.0, 1.0, n) * np.exp(-t * 90.0)


def add(buf, sig, at):
    i = int(at * SR)
    if i < 0:
        return
    j = min(len(buf), i + len(sig))
    if j > i:
        buf[i:j] += sig[:j - i]


def main() -> None:
    buf = np.zeros(int(TOTAL * SR) + 1)

    # Harmonicky plan: (zaklad, tony akordu) pro kazdy takt.
    A2, F2, C3, G2 = 110.00, 87.31, 130.81, 98.00
    plan = [
        (A2, [220.00, 261.63, 329.63]),
        (F2, [174.61, 220.00, 261.63]),
        (C3, [261.63, 329.63, 392.00]),
        (G2, [196.00, 246.94, 293.66]),
        (A2, [220.00, 261.63, 329.63]),
        (F2, [174.61, 220.00, 261.63]),
        (G2, [196.00, 246.94, 293.66]),
        (A2, [220.00, 261.63, 329.63]),
    ]
    for b, (root, tones) in enumerate(plan):
        t0 = b * 4 * BEAT
        add(buf, tone(root, 4 * BEAT * 0.44, "square", 0.22, 3.0), t0)
        add(buf, tone(root, 4 * BEAT * 0.30, "square", 0.16, 5.0), t0 + 2 * BEAT)
        for i in range(8):
            f = tones[i % 3] * (2.0 if i % 6 >= 3 else 1.0)
            add(buf, tone(f, BEAT * 0.42, "tri", 0.10, 6.0), t0 + i * BEAT * 0.5)
        add(buf, kick(), t0)
        add(buf, kick(), t0 + 2 * BEAT)
        for i in range(4):
            add(buf, hat(), t0 + (i + 0.5) * BEAT)

    buf /= max(1e-9, np.abs(buf).max())
    buf *= 0.90
    # Okraje smycky: kratke fade, aby spoj nevzklikl (u 19 s smycky neslyset).
    edge = int(0.010 * SR)
    buf[:edge] *= np.linspace(0.0, 1.0, edge)
    buf[-edge:] *= np.linspace(1.0, 0.0, edge)
    pcm = np.clip(buf * 32767.0, -32768, 32767).astype("<i2")

    tmp = "/tmp/zily2_theme.wav"
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())

    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(here, "assets", "audio")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "theme.ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp,
                    "-c:a", "libvorbis", "-q:a", "3", out], check=True)
    print("zapsano: %s (%.0f kB, %.1f s)" % (out, os.path.getsize(out) / 1024.0, TOTAL))


if __name__ == "__main__":
    main()
