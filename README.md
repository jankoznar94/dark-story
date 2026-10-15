# Žily 2 — srdce a věž

Nová podoba hry Žily (dřív „ley lines“). Stará verze s mřížkou, kolejemi
a výhybkami žije dál jako archiv na větvi `ley-lines` — nic z ní se tady
nepoužívá.

## Model (rozhodnuto s Janem, Oct 2026)

- **Jedna věž ve středu kruhové plochy, kolem prázdno.**
- **Věž vidí jen svou barvu.** Na ostatní dává nulu a vůbec na ně nestřílí
  („jako by je vůbec neviděla“).
- **Přepnutí barvy = klepnutí na věž.** Přesně na výsek vence kolem věže,
  nebo na tělo věže (otočí barvu na další).
- **Paprsek je jen ZAMĚŘOVÁNÍ** — ukazuje, na koho věž míří, ale sám
  neubírá životy. Poškození přijde **až dopadem střely**: od věže letí tečka
  **v barvě věže** (přes základní dostřel ~0,33 s), takže to vypadá jako
  stabilní paprsek, kterým rytmicky proudí střely.
- **Svazek drží cíle, dokud jsou naživu, a JEDNOU VYSTŘELENÁ STŘELA SVŮJ CÍL
  DOSTIHNE** (Jan, Oct 2026: „Když už věž vystřelí, tak musí projektil doletět
  do cíle a udělit poškození.“). Střela proto zanikne jen s mrtvým cílem —
  přepnutí barvy věže ani to, že se cíl přestal zaměřovat, ji nezastaví.
  Odražená střela **letí z těla předchozí oběti** k dalšímu nepříteli, takže je
  vidět, jak se mezi nimi odráží.
- **Upgrade = rychlost střelby.** Poškození jedné rány zůstává 10, roste počet
  ran za sekundu: **3 → 4,8 → 7,2 ran/s** (tj. 30 / 48 / 72 za sekundu) a od
  3. stupně věž míří na dva cíle. V paprsku je tím vidět hustší proud teček.
- **Poutníci vstupují na SPAWNOVACÍM KRUHU naslepo**, náhodným směrem, a jdou
  rovně k věži. Cesta od okraje k okraji věže trvá **12 s** — poutníci jdou
  pomalu, aby byla vidět vzdálenost, kterou mají před sebou.
- **Spawnovací kruh je větší než displej a NIKDE se nekreslí** (je pomyslný):
  jeho horní i dolní okraj se dotýká okraje herního pruhu a boky vedou mimo
  obraz — poutníci proto vcházejí ze všech směrů, i z boků. Vnější kruh, který
  je vidět, je jen **kruh dostřelu**.
- **Dosah je kruh** (kreslený na zemi): základ **42 %** poloměru plochy
  (143 px na 390×844 — 51 px od každého boku, takže je kam upgradovat),
  vylepšením **55 %** a **70 %**; nikdy ne celá plocha. Je to okno, ve kterém
  hráč musí stihnout přepnout barvu: **4,6 s / 6,2 s / 8,1 s** v ohni
  (dřív 2,5 s, což bylo málo).
- **Levely vypadají stejně**, liší se jen složením vln (každá vlna míchá
  všechny čtyři barvy).

## Upgrady a tempo hry (Oct 2026)

- **Dočasné (bitevní) upgrady NEMAJÍ STROP** (Jan: „já prozatím nechci žádné
  stropy. Žádné max.“). Kupují se za zlato tak dlouho, dokud na ně hráč má;
  jediným stropem je rostoucí cena (5, 10, 15, … zlata). V panelu se proto
  nikdy neobjeví „MAX“. **Permanentní upgrady strop mají dál** (platí se body
  z vyhraných levelů) — jejich konec je hodnota v tabulce `Upgrades.STATS`
  (`cap`) a v menu se na něm napíše „MAX“.
- **Kadence má jen fyzikální pojistku** (`Upgrades.MIN_INTERVAL` = 0,05 s, tj.
  20 ran/s): kadence je čas a nula by dělila nulou. Hráč se k ní dostane až po
  ~19 krocích (přes 900 zlata v jednom levelu).
- **Zrychlení hry** je nový speciální permanentní upgrade (`gs`): **1,0x /
  1,5x / 2,0x / 2,5x** za body. Násobí se **celý krok hry** (`Game.step`), takže
  se zrychlí všechno, co je na čase — pohyb poutníků, kadence, let střely, jed
  i led, regenerace i časy vln. Kdyby se zrychloval jen pohyb, změnila by se
  obtížnost.

## Rozvržení

Hra je na **výšku**. **Plocha a zoom jsou dvě různá čísla:**
- **Zoom** (věž, poutníci, tahy) se počítá z **vepsaného kruhu do kratší strany**
  herního pruhu — přesně jako dřív, takže velikosti zůstávají stejné (na
  390×844 věž 22 px, poutník 9 px) a nic se „nepřibližuje“.
- **Spawnovací kruh** je polovina **výšky** herního pruhu: dotýká se horního
  i spodního okraje pruhu a na výšku vede boky **55 px mimo obraz** (na 390×844),
  takže poutníci vcházejí ze všech směrů. Nikdy není menší než zoom.
  Na širokém pruhu (velký tablet) se kruh vepíše do šířky; na šířku displeje
  hra řekne „otoč telefon“.

**Dole jsou dvě lišty:** barevná paleta a pod ní **panel s upgrady, který je
v levelu otevřený pořád** (dá se v něm nakupovat za pochodu — hra se pod ním
nezastavuje). Herní pruh proto končí **nad paletou**: poutníci nikdy nechodí pod
panel. Buňka upgradu má **dva řádky textu** — nahoře název, pod ním hodnota
(zlatě) a vedle ní cena; v levelu jsou buňky o 12 % nižší než v menu, protože
jsou na obrazovce trvale.

Barvu vždy nese i **tvar** (runa) — u poutníka je runa přímo tvarem těla:
oheň trojúhelník, voda kapka, země čtverec, vzduch prstenec. Barva nikdy
nesmí být jediný nositel informace.

**Menu je velké a texty jsou větší**: čtyři tlačítka (HRÁT / UPRAVY / SETTINGS /
UPDATE) berou 78 % šířky displeje a na 390×844 mají 304 × 108 px — hráč na ně nemusí
mířit prstem; titul má 54 px, popisek 28 px. Větší je i hláška pod pruhem
(kreslí se základním písmem, ne zmenšeným stavovým), obrazovka NASTAVENÍ
a dotaz při odchodu z boje. Titul i podtitulek se na nízkém/úzkém displeji
zmenší tak, aby nepřelezly do tlačítek ani z displeje.

## Testy

```bash
godot4 --headless --path . --import                      # zaregistruje class_name
godot4 --headless --path . --script res://tools/test_scripts_load.gd
godot4 --headless --path . --script res://tools/test_core.gd     # CORE_ALL_PASS=true
godot4 --headless --path . --script res://tools/test_layout.gd   # LAYOUT_ALL_PASS=true
```
