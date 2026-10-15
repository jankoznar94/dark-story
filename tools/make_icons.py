#!/usr/bin/env python3
"""Generuje ikony kategorii (cat_off = mec, cat_def = stit) jako BILE MASKY.

Jan (Oct 2026): "upravíme ikonu meče a štítu. Tyto verze zkrátka nefungují.
Štít musí mít jiné proporce. Teď je moc tenký a dlouhý. Musí působit
masivnějším dojmem. Stejně tak meč."

Ikony z modelu (Lemonade) se u techto dvou tvaru nedaji uhlidat - proporce
vyjdou vzdycky jinak. Kresli se proto ROVNOU, aby se daly presne zmerit
(pomer stran, tloustka) a aby se daly opakovat.

Vystup: assets/ui/cat_off.png, assets/ui/cat_def.png (128x128, bila na
pruhlednem). Po prepsani je nutny `godot4 --headless --path . --import`,
jinak Godot kresli starou texturu z cache.
"""
import os
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
    rgba = Image.merge("RGBA", (*rgb.split(), out))
    return rgba


def shield() -> Image.Image:
    """STIT: siroky toporny tvar (heater), ne uzka dlouha deska.

    Pomer sirka/vyska ~ 1,0. Taper zacina az v polovine, hrot je TUPY
    (zaobleny), ne jehla - to je ten "masivnejsi dojem".
    """
    img = canvas()
    d = ImageDraw.Draw(img)
    w, h = 112.0, 108.0
    x0, y0 = (SIZE - w) * 0.5, (SIZE - h) * 0.5
    x1, y1 = x0 + w, y0 + h
    cx = (x0 + x1) * 0.5
    waist = y0 + h * 0.42          # odsud se zužuje
    tip_y = y1 - h * 0.06          # tupy hrot (ne do krajniho bodu)
    pts = [
        (x0 + 7, y0), (x1 - 7, y0),
        (x1, y0 + 8),
        (x1, waist),
        (cx + w * 0.19, tip_y - h * 0.10),
        (cx, y1),
        (cx - w * 0.19, tip_y - h * 0.10),
        (x0, waist),
        (x0, y0 + 8),
    ]
    d.polygon(pts, fill=255)
    # Vnitrni pruh (pruhledny) naznacuje lem stitu - plny flek by vypadal
    # jako pentagon, ne jako stit.
    d.line([(x0 + 11, y0 + 11), (x1 - 11, y0 + 11)], fill=0, width=5)
    d.line([(x0 + 11, y0 + 11), (x0 + 11, waist - 4)], fill=0, width=5)
    d.line([(x1 - 11, y0 + 11), (x1 - 11, waist - 4)], fill=0, width=5)
    d.line([(x0 + 11, waist - 4), (cx, y1 - h * 0.13)], fill=0, width=5)
    d.line([(x1 - 11, waist - 4), (cx, y1 - h * 0.13)], fill=0, width=5)
    return finish(img)


def sword() -> Image.Image:
    """MEC: siroka cepel, kratky jilec, vyrazny križ - pak otoceny o 45° vpravo.

    Driv byl mec tenky a dlouhy (20 % inkoustu v ramecku, cepel ~13 % sirky).
    Tady je cepel 28 px ze 128 (22 %) - "masivnejsi dojem".
    """
    img = canvas()
    d = ImageDraw.Draw(img)
    cx = SIZE * 0.5
    bw = 28.0                       # sirka cepele
    d.polygon([(cx - bw / 2, 8), (cx + bw / 2, 8), (cx + bw / 2, 74),
               (cx, 92), (cx - bw / 2, 74)], fill=255)
    # KRIZ: siroky, se zaoblenymi konci (kdo ho udela uzky, mec zmizi).
    d.rounded_rectangle([cx - 33, 74, cx + 33, 90], radius=8, fill=255)
    # JILEC a HLAVICE.
    d.rounded_rectangle([cx - 8, 90, cx + 8, 114], radius=6, fill=255)
    d.ellipse([cx - 11, 106, cx + 11, 126], fill=255)
    return finish(img.rotate(-45, resample=Image.BICUBIC, expand=True))


def main() -> None:
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(here, "assets", "ui")
    shield().save(os.path.join(out, "cat_def.png"))
    sword().save(os.path.join(out, "cat_off.png"))
    print("zapsano: cat_def.png, cat_off.png")


if __name__ == "__main__":
    main()
