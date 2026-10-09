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
| `scripts/level.gd` | LEVEL jako data: koleje, elementy, vystupy, obtiznost + JSON a KOD pro export |
| `scripts/builtin_levels.gd` | levely zakotvene ve hre (sem prijde kod levelu z editoru) |
| `scripts/editor.gd` | level editor: klepnutim vyberes usek, tlacitky ho menis |
| `scripts/network.gd` | cista geometrie site postavena z LEVELU (kmen, vyhybka, useky, vystupy) |
| `scripts/guide.gd` | text NAVODU + zalamovani a mereni (jedine misto s pravidly) |
| `scripts/bonus.gd` | bonus na useku = nasobek cele dmg zony |
| `scripts/enemy.gd` | poutnik = zivel + zivoty + pozice na trase |
| `scripts/game.gd` | CELA logika. Zadne kresleni, zadny Input |
| `scripts/game_view.gd` | jedina scena: kresleni + hit-test |
| `tools/test_core.gd` | pravidla (439 assertu) |
| `tools/test_layout.gd` | 14 realnych rozliseni, deska bez textu, navod se vejde, EDITOR se vejde |
| `tools/test_editor.gd` | editor: tlacitka meni level, export kodu, zakotvene levely |
| `tools/test_audio.gd` | zvuk se meri ze vzorku, ne poslechem |
| `tools/test_scripts_load.gd` | kazdy .gd se musi nacist |

## Co je kde na obrazovce

**HERNI DESKA NENESE ZADNY TEXT ANI ZADNE OVLADANI.** Zmizely popisky
(vyhybka, vystupy, kmen, nasobky u dmg zon) i cely spodni pruh vcetne SKIP.
Deska proto saha az k spodnimu okraji displeje a jeji jedina interakce je
klepnuti na usek (prepne vyhybku) nebo na misto s runou (stavi / vylepsi).

- Horni panel: 48 px (byl 72). Vlna, Zivoty, Zlato, vybrany usek.
- Spodni pruh: ZADNY. Jeho vyska i vyska SKIPu patri hraci plose.
- **Navod** je v menu (druhe tlacitko): pet obrazkovych bloku, kazdy
  s kratkym popiskem do 8 slov.

## Zvuk

Hra neveze zadne audio soubory - ton se generuje za behu (`scripts/sound.gd`).
Ctyri priciny "v reporoduktoru praska", vsechny opravene a zmerene v
`tools/test_audio.gd`:

1. jednorazove tuknuti melo smycku (11 lupnuti za sekundu),
2. smycka hudby nemela cely pocet period (skok ve fazi),
3. ton se generoval na 22050 Hz, ale hra micha na 44100/48000 (prepočet),
4. hlasitosti se pri rychlem klepani scitaly do limitace - proto strop
   4 hlasy a `volume_db = -12`.

## Testy

```bash
godot4 --headless --path . --import
godot4 --headless --path . --script res://tools/test_scripts_load.gd
godot4 --headless --path . --script res://tools/test_core.gd    # CORE_ALL_PASS=true
godot4 --headless --path . --script res://tools/test_layout.gd  # LAYOUT_ALL_PASS=true
godot4 --headless --path . --script res://tools/test_audio.gd   # AUDIO_ALL_PASS=true
godot4 --headless --path . --script res://tools/test_editor.gd  # EDITOR_ALL_PASS=true
```

## Level editor

Menu -> EDITOR. Klepnutim na usek se usek vybere, tlacitky dole se meni:

- **usek + / usek −** - pocet useku (2 az 7). Pridanim se mrizka vystredi,
  takze se ostatni useky neposunou.
- **zivel** - cykli se pres vsechny ctyri zivly a neutralni.
- **vystup** - do ktere diry v mape usek usti.
- **odbočení − / +** - kde se usek ohne k vystupu. Diky tomu se daji dve
  kolejе sbihat do jednoho vystupu.
- **export** - vyrobi KOD levelu (jedna rada textu) a soubor.
- **hrat** - spusti kolo s prave upravenym levelem.

**Vse se uklada LOKALNE** (ve webu do localStorage, na desktopu do `user://levels/`).
Nikam se nic neposila - zadna Firestore.

### Jak dostat level do hry natrvalo

1. V editoru zmackni **export**. Nad pruhem se objevi kod typu
   `ZILY1;{"name":"...","lanes":[...],...}`.
2. Posli mi ten kod (vejde se do Telegramu i z telefonu).
3. Ja ho vlozim do `scripts/builtin_levels.gd` - a level se od te doby veze
   s hrou na vsech platformach, prezije smazani cache i reinstalaci.

Kod se do toho souboru vklada **doslova**, niceho se rucne neprepisuje:
`Level.from_code()` ho precte a test (`tools/test_editor.gd`) u kazdeho
zakotveneho levelu overi, ze je platny a ze jeho kod neni pozmeneny.

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
