#!/usr/bin/env python3
"""Generuje zvukove efekty hry (assets/audio/*.ogg).

Jan (Oct 2026): "A střelba a zásah by samozřejmě měly mít také zvukové efekty."

- shot.ogg  - vystrel z veze (kratky sestupny piskot, 70 ms)
- hit.ogg   - zasah poutnika (tupnuti + kovovy cvak, 90 ms)
- kill.ogg  - poutnik padl (sestupny sum, 180 ms)

Vse se pocita v numpy a pise pres ffmpeg do OGG (kratke zvuky = par kB).
Efekty musi byt KRATKE a TICHE: pri plne kadenci (20 ran/s) se zvuk vystrelu
opakuje 20x za sekundu, takze dlouhy zvuk by se slil do huceni. Hra ho proto
navic jeste omezuje (`Sfx` minimalni odstup) - viz `game_view.gd`.
"""
import os
import subprocess
import wave

import numpy as np

SR = 22050


def sweep(f0, f1, dur, shape="square", amp=1.0, decay=30.0):
    n = max(1, int(dur * SR))
    t = np.arange(n) / SR
    f = f0 * (f1 / f0) ** (t / max(1e-6, dur))
    phase = 2.0 * np.pi * np.cumsum(f) / SR
    if shape == "square":
        s = np.tanh(3.0 * np.sin(phase))          # mekky obdelnik (bez chrapotu)
    else:
        s = np.sin(phase)
    env = np.exp(-decay * t)
    a = min(n, int(0.003 * SR))
    env[:a] *= np.linspace(0.0, 1.0, a)
    return amp * s * env


def noise_burst(dur, decay, amp=1.0, tone=None, tone_amp=0.6):
    n = max(1, int(dur * SR))
    t = np.arange(n) / SR
    rng = np.random.default_rng(11)
    s = rng.uniform(-1.0, 1.0, n)
    # Jednoduchy "dolnopropustny" filtr (klouzavy prumer) - bez nej je to sycak.
    k = 6
    s = np.convolve(s, np.ones(k) / k, mode="same")
    if tone is not None:
        s = s / max(1e-9, np.abs(s).max()) + tone_amp * np.sin(2.0 * np.pi * tone * t)
    return amp * s * np.exp(-decay * t)


def write(name, sig, out_dir):
    sig = sig / max(1e-9, np.abs(sig).max()) * 0.75
    edge = int(0.003 * SR)
    sig[:edge] *= np.linspace(0.0, 1.0, edge)
    sig[-edge:] *= np.linspace(1.0, 0.0, edge)
    pcm = np.clip(sig * 32767.0, -32768, 32767).astype("<i2")
    tmp = "/tmp/zily2_%s.wav" % name
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    out = os.path.join(out_dir, "%s.ogg" % name)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp,
                    "-c:a", "libvorbis", "-q:a", "2", out], check=True)
    return out


def main() -> None:
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(here, "assets", "audio")
    os.makedirs(out_dir, exist_ok=True)
    files = [
        ("shot", sweep(880.0, 300.0, 0.070, "square", 0.55, 26.0)),
        ("hit", noise_burst(0.090, 40.0, 0.60, tone=170.0)),
        ("kill", noise_burst(0.180, 16.0, 0.55) + sweep(520.0, 130.0, 0.180, "sine", 0.35, 12.0)),
    ]
    for name, sig in files:
        p = write(name, sig, out_dir)
        print("zapsano: %s (%.1f kB)" % (p, os.path.getsize(p) / 1024.0))


if __name__ == "__main__":
    main()
