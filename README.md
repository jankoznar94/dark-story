# Zily - elementarni tower defense s prepinanim trasy

Hra zije na teto vetvi. Vetev = hra, jeden repozitar pro vsechny namety.

## Co to je

Po zilach many putuji elementarni poutnici ke svatynim. Kazda kolej vede
k jedne svatyni a nese jeden zivel. Vez lze postavit JEN na kolej sveho
zivlu. Hrac prepina vyhybku a rozhoduje, na kterou kolej poutnik vjede.

- **vlastni zivel** = poutnik nedostava ZADNE poskozeni, projde
- **protiklad** = plne poskozeni (ohen <-> voda, zeme <-> vzduch)
- **jiny zivel** = jen zlomek poskozeni

Cilem neni dostat poutnika do spravne svatyně - cilem je zabit ho, nez
tam dorazi. Kazdy dojity poutnik ubere hracovi zivot. Hra je o tom
stihnout prutok, aby se poutnici nehromadili.

## Technicky

Godot 4.7, GDScript, 2D, `gl_compatibility` (nutne pro web + tato GPU).
Zadna fyzika: sit je polyline + vzorkovani bodu, vse se kresli rucne
v `_draw()` - zadne Button nody, zadne theme, zadne hover efekty.
Hra je cela deterministicka, proto ji lze simulovat headless.

| soubor | co to je |
|---|---|
| `scripts/element.gd` | ctyri zivly a matice poskozeni (jedna tabulka = cela hra) |
| `scripts/network.gd` | cista geometrie site (kmen, vyhybka, pet useku, vystupy) |
| `scripts/guide.gd` | text NAVODU + zalamovani a mereni (jedine misto s pravidly) |
| `scripts/bonus.gd` | bonus na useku = nasobek cele dmg zony |
| `scripts/enemy.gd` | poutnik = zivel + zivoty + pozice na trase |
| `scripts/game.gd` | CELA logika. Zadne kresleni, zadny Input |
| `scripts/game_view.gd` | jedina scena: kresleni + hit-test |
| `tools/test_core.gd` | pravidla (359 assertu) |
| `tools/test_layout.gd` | 14 realnych rozliseni, deska bez textu, navod se vejde |
| `tools/test_audio.gd` | zvuk se meri ze vzorku, ne poslechem |
| `tools/test_scripts_load.gd` | kazdy .gd se musi nacist |

## Co je kde na obrazovce

**HERNI DESKA NENESE ZADNY TEXT.** Popisek vyhybky, vystupu i kmene je pryc -
kazdy radek textu v desce je misto, ktere chybi poutnikum. Vsechno vysvetleni
je v MENU pod tlacitkem **NAVOD** (vcetne tabulky poskozeni) a cisla poskozeni
vybraneho useku v hornim panelu. Deska ma jen znacky: runy, barvy, tvary.

- Horni panel: 52 px (byl 72) - Vlna, Zivoty, Zlato, vybrany usek.
- Spodni pruh: 52 px (byl 84) - zustava jen SKIP. Navod tu uz neni.
- Zbytek dostane herni plocha: +48 px vysky na 960x600, +48 px na 932x430.

## Testy

```bash
godot4 --headless --path . --import
godot4 --headless --path . --script res://tools/test_scripts_load.gd
godot4 --headless --path . --script res://tools/test_core.gd    # CORE_ALL_PASS=true
godot4 --headless --path . --script res://tools/test_layout.gd  # LAYOUT_ALL_PASS=true
godot4 --headless --path . --script res://tools/test_audio.gd   # AUDIO_ALL_PASS=true
```

## Nahled

```bash
godot4 --path . --rendering-driver opengl3 --resolution 960x600 -- --shot
# -> user://shot.png
```

## Nasazeni

Push na tuto vetev spusti `.github/workflows/build.yml` (spousti se JEN
na teto vetvi) a publikuje web build do PODADRESARE `ley-lines` na
gh-pages s `keep_files: true`, aby neprepsal build druhe hry.

Stavajici `build.yml` druhe hry ma proto v `on.push` pojistku
`branches-ignore: ["ley-lines"]`.
