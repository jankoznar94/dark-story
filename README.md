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
| `scripts/network.gd` | cista geometrie site (kmen, vyhybka, ctyri koleje) |
| `scripts/tower.gd` | vez = kolej + zivel + uroven |
| `scripts/enemy.gd` | poutnik = zivel + zivoty + pozice na trase |
| `scripts/game.gd` | CELA logika. Zadne kresleni, zadny Input |
| `scripts/game_view.gd` | jedina scena: kresleni + hit-test |
| `tools/test_core.gd` | pravidla (139 assertu) |
| `tools/test_scripts_load.gd` | kazdy .gd se musi nacist |

## Testy

```bash
godot4 --headless --path . --import
godot4 --headless --path . --script res://tools/test_scripts_load.gd
godot4 --headless --path . --script res://tools/test_core.gd   # CORE_ALL_PASS=true
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
