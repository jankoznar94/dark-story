#!/usr/bin/env python3
"""Generuje zvukove efekty hry (assets/audio/*.ogg).

Jan (Oct 2026): "A střelba a zásah by samozřejmě měly mít také zvukové efekty."

- hit.ogg   - zasah poutnika (tupnuti + kovovy cvak, 90 ms)
- kill.ogg  - poutnik padl (sestupny sum, 180 ms)

Vse se pocita v numpy a pise pres ffmpeg do OGG (kratke zvuky = par kB).
Efekty musi byt KRATKE a TICHE: hra je omezuje minimalnim odstupem
(`SFX_GAP_S`) - viz `game_view.gd`.

Laser neni jednorazovy zvuk, ale SMYCKA (laser.wav): paprsek sviti, dokud
existuje, takze jeho zvuk musi byt nepretrzity a kolísavy. WAV proto, ze
Vorbis pri kodovani odrizne 128 vzorku a smycka pak nesedi na celou periodu.
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


def write(name, sig, out_dir, sr=SR, fade=True):
    sig = sig / max(1e-9, np.abs(sig).max()) * 0.75
    if fade:
        edge = int(0.003 * sr)
        sig[:edge] *= np.linspace(0.0, 1.0, edge)
        sig[-edge:] *= np.linspace(1.0, 0.0, edge)
    pcm = np.clip(sig * 32767.0, -32768, 32767).astype("<i2")
    tmp = "/tmp/zily2_%s.wav" % name
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())
    out = os.path.join(out_dir, "%s.ogg" % name)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp,
                    "-c:a", "libvorbis", "-q:a", "2", out], check=True)
    return out


# ============================================================================
# SMYCKA PAPRSKU (laser.ogg). Jan (Oct 2026): "Zvuk palby laserem se mi moc
# nelibi. Udela to jen jeden zvuk pri zasahu. U letícího projektilu by to bylo
# v poradku, ale kdyz je to nepretrzity paprsek, tak by to mohlo delat nejaky
# kolísavy zvuk po celou dobu trvani."
#
# JE TO SMYCKA, TAKZE PLATI JINA PRAVIDLA NEZ U JEDNORAZOVYCH ZVUKU:
#   * ZADNY fade na zacatku ani na konci (ten by na spojnici udelal diru),
#   * VSECHNY frekvence jsou nasobky 50 Hz a vsechny LFO deli 300 Hz, takze
#     presne 1,000 s obsahuje CELY pocet period - pri 44100 i 48000 vzorku
#     (44100/50 = 882, 48000/50 = 960). Spojnice je proto spojita i po
#     prevzorkovani; nahodna faze by to rozbila,
#   * sirka pasma se "hybe" - kazda harmonicka ma vlastni pomalou amplitudovou
#     modulaci, takze zvuk kolisa, ale porad zni jako paprsek, ne jako more.
# Delka 1 s a harmonicka struktura 150 Hz = bzučivy paprsek, ktery nema ton
# (hrac ho slysi jako "zzzz", ne jako hudebni notu).
# ============================================================================
def laser_loop(sr):
    dur = 1.0
    n = int(round(dur * sr))
    t = np.arange(n) / float(sr)
    tau = 2.0 * np.pi
    s = 0.22 * np.sin(tau * 75.0 * t)
    for k in range(1, 8):
        am = 0.75 + 0.25 * np.sin(tau * 3.75 * t + 0.9 * k)
        s += am * np.sin(tau * 150.0 * k * t) / (k ** 0.9)
    s += 0.05 * np.sin(tau * 900.0 * t) * (0.5 + 0.5 * np.sin(tau * 7.5 * t))
    env = 0.55 + 0.22 * np.sin(tau * 5.0 * t + 0.7) + 0.13 * np.sin(tau * 2.5 * t + 2.1)
    return s * env


def write_wav(name, sig, out_dir, sr):
    sig = sig / max(1e-9, np.abs(sig).max()) * 0.75
    pcm = np.clip(sig * 32767.0, -32768, 32767).astype("<i2")
    out = os.path.join(out_dir, "%s.wav" % name)
    with wave.open(out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())
    return out


def main() -> None:
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(here, "assets", "audio")
    os.makedirs(out_dir, exist_ok=True)
    files = [
        ("hit", noise_burst(0.090, 40.0, 0.60, tone=170.0)),
        ("kill", noise_burst(0.180, 16.0, 0.55) + sweep(520.0, 130.0, 0.180, "sine", 0.35, 12.0)),
    ]
    for name, sig in files:
        p = write(name, sig, out_dir)
        print("zapsano: %s (%.1f kB)" % (p, os.path.getsize(p) / 1024.0))
    # SMYCKA PAPRSKU JE WAV, NE OGG: Vorbis pri kodovani odrizne 128 vzorku
    # (43972 misto 44100), takze smycka nesedi na celou periodu a kazdou
    # sekundu lupne. WAV ma presne tolik vzorku, kolik se vyrobilo, a Godot
    # u nej umi `LOOP_FORWARD` bez prevzorkovani.
    p = write_wav("laser", laser_loop(44100), out_dir, sr=44100)
    print("zapsano: %s (%.1f kB)" % (p, os.path.getsize(p) / 1024.0))


if __name__ == "__main__":
    main()
