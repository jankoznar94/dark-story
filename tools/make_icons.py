#!/usr/bin/env python3
"""Generuje ikony kategorii (cat_off = mec, cat_def = stit) jako BILE MASKY.

Jan (Oct 2026): "upravíme ikonu meče a štítu. Tyto verze zkrátka nefungují.
Štít musí mít jiné proporce. Teď je moc tenký a dlouhý. Musí působit
masivnějším dojmem. Stejně tak meč." a podruhe: "Ikona meče je podivné
oříznutá. Bez špičky. A štít má teď příliš hranatý design."

Ikony z modelu (Lemonade) se u techto dvou tvaru nedaji uhlidat - proporce
vyjdou vzdycky jinak. Kresli se proto ROVNOU, aby se daly presne zmerit
(pomer stran, tloustka) a aby se daly opakovat.

Vystup: assets/ui/cat_off.png, assets/ui/cat_def.png (128x128, bila na
pruhlednem). Po prepsani je nutny `godot4 --headless --path . --import`,
jinak Godot kresli starou texturu z cache.
"""
import os

import numpy as np
from PIL import Image, ImageDraw

SIZE = 128
MARGIN = 6          # okraj, aby ikona neležela na hrane ramecku
INK = SIZE - 2 * MARGIN   # 116 px, do toho se vejde inkoust


def canvas() -> Image.Image:
    return Image.new("L", (SIZE, SIZE), 0)


def finish(img: Image.Image) -> Image.Image:
    """Orizne na inkoust a zmensi na INK px (ctverec), vycentruje."""
    box = img.getbbox()
    if box is None:
        raise SystemExit("prazdna kresba")
    ink = img.crop(box)
    scale = INK / max(ink.width, ink.height)
    ink = ink.resize((max(1, round(ink.width * scale)), max(1, round(ink.height * scale))),
                     Image.LANCZOS)
    out = Image.new("L", (SIZE, SIZE), 0)
    out.paste(ink, ((SIZE - ink.width) // 2, (SIZE - ink.height) // 2))
    rgba = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    rgba.putalpha(out)
    rgb = Image.new("RGB", (SIZE, SIZE), (255, 255, 255))
    return Image.merge("RGBA", (*rgb.split(), out))


def arc(cx, cy, r, a0, a1, steps=16):
    """Body oblouku ve stupnich (0 = vpravo, 90 = DOLU - souradnice obrazku)."""
    out = []
    for a in np.linspace(a0, a1, steps):
        rad = np.deg2rad(a)
        out.append((cx + r * np.cos(rad), cy + r * np.sin(rad)))
    return out


def bezier(p0, p1, p2, p3, steps=22):
    """Kubicka Bezierova krivka - STIT se bez ni kresli jen rovnymi carami
    a vypada hranate (Jan: "štít má teď příliš hranatý design")."""
    t = np.linspace(0.0, 1.0, steps)[:, None]
    pts = ((1 - t) ** 3 * np.array(p0) + 3 * (1 - t) ** 2 * t * np.array(p1)
           + 3 * (1 - t) * t ** 2 * np.array(p2) + t ** 3 * np.array(p3))
    return [(float(x), float(y)) for x, y in pts]


def shield_outline(x0, y0, w, h, inset):
    """Obrys stitu (heater): rovna siroka horni hrana, zaoblene rohy, hladke
    staceni do tupého hrotu. `inset` zmensi obrys pro vnitrni lem."""
    ox0, oy0 = x0 + inset, y0 + inset
    ox1, oy1 = x0 + w - inset, y0 + h - inset
    ocx = (ox0 + ox1) * 0.5
    rr = max(3.0, 13.0 - inset * 0.5)
    waist = oy0 + (oy1 - oy0) * 0.42
    pts = []
    pts += arc(ox0 + rr, oy0 + rr, rr, 180.0, 270.0)      # levy horni roh
    pts += arc(ox1 - rr, oy0 + rr, rr, 270.0, 360.0)      # pravy horni roh
    pts.append((ox1, waist))
    pts += bezier((ox1, waist), (ox1, oy1 - (oy1 - oy0) * 0.30),
                  (ocx + (ox1 - ox0) * 0.30, oy1 - (oy1 - oy0) * 0.05), (ocx, oy1))
    pts += bezier((ocx, oy1), (ocx - (ox1 - ox0) * 0.30, oy1 - (oy1 - oy0) * 0.05),
                  (ox0, oy1 - (oy1 - oy0) * 0.30), (ox0, waist))
    return pts


def shield() -> Image.Image:
    """STIT: siroky a MASIVNI, ale s OBLYMI krivkami (ne hranaty polygon).

    Pomer sirka/vyska ~ 1,05; taper zacina az v 42 % vysky a hrot je tupy.
    """
    img = canvas()
    d = ImageDraw.Draw(img)
    w, h = 112.0, 106.0
    x0, y0 = (SIZE - w) * 0.5, (SIZE - h) * 0.5
    outer = shield_outline(x0, y0, w, h, 0.0)
    d.polygon(outer, fill=255)
    # Vnitrni lem (pruhledna cara 5 px) naznacuje obrubu - plny flek by
    # vypadal jako pentagon, ne jako stit. Kresli se ZAOBLENE, stejne jako
    # obrys, aby se hrany nerozisly.
    inner = shield_outline(x0, y0, w, h, 11.0)
    d.line(inner + [inner[0]], fill=0, width=5, joint="curve")
    return finish(img)


def sword() -> Image.Image:
    """MEC: hrot NAHORU, siroka cepel, kratky jilec, vyrazny kriz - pak
    otoceny o 45 stupnu vpravo.

    Driv mel hrot DOLE a schoval se v krizi (Jan: "Ikona meče je podivné
    oříznutá. Bez špičky.") - prekryv krize a hrotu neni videt, takze mec
    vypadal jako urazna tyc. Hrot musi mirit od jilce.
    """
    img = canvas()
    d = ImageDraw.Draw(img)
    cx = SIZE * 0.5
    bw = 28.0                       # sirka cepele (22 % platna - masivni)
    tip = 6.0
    d.polygon([(cx, tip), (cx + bw / 2, tip + 26), (cx + bw / 2, 70),
               (cx - bw / 2, 70), (cx - bw / 2, tip + 26)], fill=255)
    d.rounded_rectangle([cx - 33, 68, cx + 33, 84], radius=8, fill=255)
    d.rounded_rectangle([cx - 8, 84, cx + 8, 106], radius=6, fill=255)
    d.ellipse([cx - 11, 98, cx + 11, 120], fill=255)
    return finish(img.rotate(-45, resample=Image.BICUBIC, expand=True))


def main() -> None:
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(here, "assets", "ui")
    shield().save(os.path.join(out, "cat_def.png"))
    sword().save(os.path.join(out, "cat_off.png"))
    print("zapsano: cat_def.png, cat_off.png")


if __name__ == "__main__":
    main()
