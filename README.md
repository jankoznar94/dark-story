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
- **VÝJIMKA: FIALOVÁ PO ZNEVIDITELNĚNÍ.** Když fialová po prvním zásahu zmizí,
  rozletá střela **mine** — doletí na místo dopadu, tam zmizí a nic neubírá
  (bez poškození a bez odrazu). Je to jediná barva, na kterou pravidlo
  „vystřeleno = doletí“ neplatí.
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
- **Zrychlení hry** je speciální permanentní upgrade (`gs`), ale **sám o sobě hru
  nezrychlí**: je to **klíč**, který odemkne přepínání tempa. Hra začíná **vždy
  na 1,0x** a hráč si v bitvě přepíná **1,0x / 1,5x / 2,0x / 2,5x** tlačítkem
  v horním pruhu (je vidět jen s koupeným speciálem; `Game.speed_options()`).
  Násobí se **celý krok hry** (`Game.step`), takže se zrychlí všechno, co je na
  čase — pohyb poutníků, kadence, let střely, jed i led, regenerace i časy vln.
  Kdyby se zrychloval jen pohyb, změnila by se obtížnost.

## Tiché poškození a imunita (Oct 2026)

**Dokud je poutník duch (fialová po prvním zásahu), nedá se mu ublížit ničím.**
Dvě cesty, které to dřív obcházely, jsou zavřené:

- **Jed** tickal i na neviditelného poutníka — první zásah (jed + zmizení) se
  tak v tichosti dokončil přesně ve chvíli, kdy se fialová znovu objevila a
  hráč viděl „umřela sama, aniž by do ní věž střílela“ (`Game._advance_effects`).
- **Odraz** si mohl vybrat ducha za další oběť a poslat na něj střelu, kterou
  hráč nikdy neviděl vystřelit (`Game._ricochet_from`).

Platí pravidlo: **zmizení = čas, kdy na poutníka nikdo nedosáhne**. Po objevení
platí normální pravidla dál (jed i odraz zase fungují).

## Menu a ovládání (Oct 2026)

- **Šest tlačítek**: HRÁT / LEVELY / **VYLEPŠENÍ** (dřív „UPRAVY“) / NASTAVENÍ /
  **RESET** / UPDATE.
- **RESET** maže **celý postup** (body, permanentní vylepšení, nejvyšší level)
  a **vždy se na to ptá** dialogem. **UPDATE nic nemazá** — ten jen stahuje
  novou verzi hry (jinak by si hráč smazal postup, když si chtěl jen
  aktualizovat).
- **PAUZA je ikona, ne text**: čtvercové tlačítko s **dvěma čárkami** (hra stojí)
  a po kliknutí s **trojúhelníkem** (běží). Stav nese tvar i barva. **Ikona má
  barvu podle podkladu** — na tmavém tlačítku je světlá (`TEXT`), pod pauzou je
  podklad zlatý a ikona tmavá (`GLYPH`); kdo tam dá `GLYPH` natvrdo, kreslí tmavé
  na tmavém a ikona zmizí.
- **NASTAVENÍ má dva řádky**: *Jakost vykreslování* a *Hudba* (Zapnutá/Vypnutá).
  Řádky jsou **seznam** podle indexu (`ScreenLayout.SETTINGS_ROWS`,
  `_settings_rows()`), takže přidání další volby je jeden řádek navíc, ne nový
  obdélník a nová obsluha klepnutí.

## Hudba (Oct 2026)

Jan: „A dáme do hry nějakou primitivní hudbu."

- **Smyčka `assets/audio/theme.ogg`** (~95 kB, 19,2 s): 8 taktů v a moll
  (Am–F–C–G dvakrát), 100 BPM — bas v obdélníku, arpeggio v trojúhelníku, měkký
  kopák a tichý hat. Skládá se **výpočtem**, ne modelem:
  `tools/make_music.py` (numpy → wav → ffmpeg → ogg, pevný seed, takže soubor je
  při každém běhu stejný). Noty jsou záměrně kratší než takt, aby na konci
  smyčky nezbyl dozvuk a **smyčka neklikala**.
- **Kopák je tichý** (0,26 místo 0,5, tj. −5,7 dB): Jan: „údery na první a třetí
  dobu jsou příliš výrazné. To bych lehce ztlumil." Změřeno: doby s kopákem jsou
  teď 9,7 dB nad dobami bez něj (dřív ~15 dB).
- **Hraje se až po prvním klepnutí** (`touched`): prohlížeč nespustí zvuk bez
  gesta hráče. `_sync_music()` srovnává stav (ne událost), takže vypnutí
  v nastavení hudbu opravdu zastaví.
- Smyčka se nastavuje v kódu (`AudioStreamOggVorbis.loop`), ne až v importu —
  jinak by se po prvním přehrátí zastavila.

## Zvukové efekty (Oct 2026)

Jan: „A střelba a zásah by samozřejmě měly mít také zvukové efekty."

- **Tři zvuky** (`tools/make_sfx.py`, ~4 kB každý): `shot.ogg` (výstřel),
  `hit.ogg` (dopad), `kill.ogg` (smrt poutníka).
- **Hra posílá UDÁLOSTI, ne zvuky.** `Game.events` plní `_fire_at` („shot"),
  `_damage` („hit", tedy *dopad střely* — ne `_hurt`, jinak by jed tikal 60×/s)
  a `_kill` („kill"). Obrazovka si je jednou za snímek vybere
  (`take_events()` = výběr i smazání) a zahraje. Hra tak zůstává hratelná
  a měřitelná bez obrazovky a zvuk je jen doplněk.
- **Odpěť mezi zvuky** (`SFX_GAP_S`: výstřel 75 ms) — při plné kadenci 20 ran/s
  by se jinak zvuk slil do hučení. Měří se hodinami, ne snímky.
- **Čtyři hlasy** (`AudioStreamPlayer`): jeden přehrávač se sám přerušuje, takže
  by druhý výstřel utnul první.
- V **NASTAVENÍ** je třetí řádek *Zvuky* (Zapnuté/Vypnuté) — kdo chce ticho kvůli
  okolí, nemusí přijít o hudbu.
- **POZOR: testy nesmí ukládat nastavení** (`Settings.allow_save`). Test, který
  přepne volbu, ji jinak zapíše hráči na disk — přesně to se stalo a hra pak
  lokálně hrála bez zvuků (a hledalo se to ve zvukových událostech a v kreslení).

## Ikony kategorií (Oct 2026)

Jan: „upravíme ikonu meče a štítu. Tyto verze zkrátka nefungují. Štít musí mít
jiné proporce. Teď je moc tenký a dlouhý. Musí působit masivnějším dojmem.
Stejně tak meč." + „Ikona meče je podivně oříznutá. Bez špičky. A štít má teď
příliš hranatý design."

- **Meč a štít se kreslí výpočtem** (`tools/make_icons.py`, PIL), ne modelem:
  proporce se u modelu nedaří trefit dvakrát za sebou. Měří se přitom
  **poměr stran a výplň** rámečku: štít 0,69 → **1,05**, meč 20 % → **44 %**
  inkoustu (čepel 28 px ze 128).
- **HROT MEČE MÍŘÍ OD JÍLCE.** První verze měla hrot dole a schoval se v kříži —
  meč vypadal jako uražená tyč. Kdo bude měnit geometrii, ať si pohlídá, že hrot
  leží na opačné straně než jílec, a změří šířku inkoustu nahoře (23 px) proti
  prostředku (69 px).
- **Štít je OBLÝ, ne hranatý** (`arc` + kubická `bezier`): rovná široká horní
  hrana se zaoblenými rohy, boky se v 42 % výšky stáčejí hladkou křivkou do
  tupého hrotu; vnitřní lem jde po stejné křivce. Rovné čáry vypadaly jako
  pentagon.
- Mince a hvězdička zůstávají z modelu (`lemonade-image-gen`).
- **Po přepsání PNG je nutný `--import`**, jinak Godot kreslí starou texturu
  z cache a měření lže.
- Náhled se dá složit PILem v **reálné velikosti tabu** (61 px) a poslat modelu
  k posouzení — teprve pak se importuje do hry.

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

**Menu je velké a texty jsou větší**: šest tlačítek (HRÁT / LEVELY / VYLEPŠENÍ /
NASTAVENÍ / RESET / UPDATE) bere 78 % šířky displeje a na 390×844 mají 304 × 108 px — hráč na ně nemusí
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
