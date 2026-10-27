#!/usr/bin/env python3
"""Smyčka pro bojovou hudbu Zily 2 — z Janova renderu (34 s, float WAV).

Jan: "Pojede ve smyčce. Do nekonečna. Musí na sebe zcela plynule navazovat."

Zdroj má na konci ~2,4 s ticha, takže naivní smyčka dělá mezeru a restart.
Tenhle skript udělá smyčku s přechodem (equal-power crossfade) na švu:
posledních X sekund doznívání se promíchá s prvním X sekundami, takže se
doznění překryje s novým úderem a šev není slyšet ani jako mezera, ani jako
lupnutí.

Použití:
    python3 tools/make_battle_loop.py <vstup.wav> assets/audio/battle.ogg
"""
import subprocess
import sys

import numpy as np

SR = 44100
XFADE_S = 0.35          # délka přechodu na švu
END_S = 31.70           # kde dozní hudba (dál je ticho; měřeno obálkou)
# Hlasitost se srovnává s theme.ogg (RMS -18,6 dBFS), aby hudba při přepnutí
# neskočila o 4 dB nahoru; špička se jen drží pod stropem.
TARGET_RMS = 0.1176
PEAK_CAP = 0.90


def read_float_wav(path):
    raw = subprocess.run(
        ['ffmpeg', '-v', 'quiet', '-i', path, '-f', 'f32le', '-acodec', 'pcm_f32le', '-'],
        capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype='<f4').reshape(-1, 2).copy()


def fade(n, kind, up):
    """Equal-power fade (sin/cos), aby součet výkonů zůstal 1."""
    t = np.linspace(0.0, 1.0, n, endpoint=False)
    a = np.sin(t * np.pi / 2) ** 2 if up else np.cos(t * np.pi / 2) ** 2
    return a


def write_int16_wav(path, x):
    data = np.clip(x, -1.0, 1.0)
    pcm = (data * 32767.0).astype('<i2')
    subprocess.run(['ffmpeg', '-v', 'quiet', '-y', '-f', 'f32le', '-ar', str(SR), '-ac', '2',
                    '-i', '-', '-acodec', 'pcm_s16le', path],
                   input=data.astype('<f4').tobytes(), check=True)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    src, dst = sys.argv[1], sys.argv[2]

    x = read_float_wav(src)
    end = min(len(x), int(END_S * SR))
    x = x[:end]

    # koncový doznívání nesmí skončit uprostřed vlny — dorovnat na nulu
    tail_n = int(0.05 * SR)
    x[-tail_n:] *= fade(tail_n, 'lin', up=False)[:, None]

    n = int(XFADE_S * SR)
    loop = x[:-n].copy()                      # smyčka bez posledních n vzorků
    seam_a = x[-n:]                           # doznívání, které přesahuje na začátek
    loop[:n] = loop[:n] * fade(n, 'eq', up=True)[:, None] + seam_a * fade(n, 'eq', up=False)[:, None]

    rms = float(np.sqrt((loop.mean(axis=1) ** 2).mean()))
    if rms > 0:
        loop *= TARGET_RMS / rms
    peak = float(np.abs(loop).max())
    if peak > PEAK_CAP:
        loop *= PEAK_CAP / peak

    wav = '/tmp/zily_battle_loop.wav'
    write_int16_wav(wav, loop)
    subprocess.run(['ffmpeg', '-v', 'quiet', '-y', '-i', wav, '-acodec', 'libvorbis',
                    '-q:a', '5', dst], check=True)

    # ---- kontrola: šev z DEKODOVANÉHO ogg (ne ze zdroje) ----
    raw = subprocess.run(['ffmpeg', '-v', 'quiet', '-i', dst, '-f', 'f32le',
                          '-acodec', 'pcm_f32le', '-'], capture_output=True, check=True).stdout
    y = np.frombuffer(raw, dtype='<f4').reshape(-1, 2).mean(axis=1)
    d = np.abs(np.diff(y))
    seam = abs(float(y[0] - y[-1]))
    ms20 = int(0.02 * SR)
    rms_head = float(np.sqrt((y[:ms20] ** 2).mean()))
    rms_tail = float(np.sqrt((y[-ms20:] ** 2).mean()))
    print(f'smyčka: {len(loop) / SR:.3f} s ({len(loop)} vzorků), peak {peak:.3f}')
    print(f'  šev |x0-xN| = {seam:.5f} | max skok uvnitř = {float(d.max()):.5f} '
          f'| 99.9 pct = {float(np.percentile(d, 99.9)):.5f}')
    print(f'  RMS prvních 20 ms = {rms_head:.4f} | posledních 20 ms = {rms_tail:.4f}')
    ok = seam <= float(np.percentile(d, 99.9)) and abs(rms_head - rms_tail) < 0.02
    print(('OK  ' if ok else 'FAIL') + ' šev je plynulý (skok není větší než uvnitř smyčky)')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
