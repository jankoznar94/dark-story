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
- **VĚŽ SVÍTÍ LASEREM, NE STŘÍLÍ PROJEKTILY** (Jan, Oct 2026): „Vrátíme se
  k laseru místo projektilů. Tím pádem zrušíme úplně Attack speed upgrady.
  Poškození bude probíhat plynule a čím vyšší bude mít věž dmg, tím rychleji to
  logicky bude nepřítele zabíjet. Barva laseru bude podle barvy věže.“ Paprsek
  je **zbraň sama**: vede od věže k cíli, barvu má podle věže a ubírá **každý
  snímek**, dokud svítí. Žádné projektily, žádná kadence, žádný „swing timer“.
- **Dostřel je konec paprsku, ne doba letu.** Věž svítí jen na to, co má
  v kruhu dostřelu a co vidí (`Tower.sees`). Přepnutí barvy paprsek **utrhne** —
  pravidlo „vystřeleno = doletí“ už neexistuje, protože není co doletovat.
- **PAPRSEK KONČÍ NA OKRAJI PUNTÍKU, NE VE STŘEDU TĚLA** (Jan, Oct 2026: „Laser
  končí ve středu nepřítele… Je to jak dva obdélníky vedle sebe.“ a později
  „Laser směřuje stále do středu nepřítele. Měl by směřovat spíš na jeho obal.“).
  Paprsek se zastaví na **viditelném okraji těla** (`Game.pilgrim_hit_r` =
  `PILGRIM_HIT_FRAC` 0,92 × poloměr kresby — stejné číslo, jakým obrazovka kreslí
  tělo v `_dot`); odraz od něj pokračuje na té straně, která je blíž k dalšímu
  cíli. Prstenec (`Game.pilgrim_ring_r`, 1,70 × poloměr) je **HP bar** a paprsek
  na něm nekončí — mezi ním a tělem byla ~6 px mezera, takže čára mířila do středu
  a ničeho se nedotkla. **Paprsek vychází z okraje věže** (`Game.tower_edge_r` =
  životní oblouk 1,22 r + půlka jeho tloušťky — tatáž čísla, jakými věž kreslí),
  ne z těla věže (Jan: „Laser od věže má začínat na okraji věže. Ne ve středu.“).
  Segmenty na sebe přesně navazují, konce jsou **kulaté**
  (Godot hranaté konce neumí, obrazovka je dokresluje kolečkem) a paprsek je
  **tenčí** než dřív (0,015 meritka místo 0,026 — na telefonu 2,3 px místo 4,1 px).
- **Poškození je ZA SEKUNDU** (`Game.laser_dps`). Základ **14/s** (dřív 10/s) je
  spočítané, ne od oka: poutník je v dostřelu (0,34 pole) jen ~3,2 s, takže základ
  dá za průchod 45 poškození — a nejtvrdsí poutník prvního kola (červená 2,2 × 20 =
  44 životů) se tím dá zabít, kdežto s 10/s to bylo 32 a nešlo to (Jan: „Základní
  poškození hráče musí být o něco vyšší. S tím, jak je nastavený na začátku kola
  nemá skoro šanci nikoho zabít.“).
  **DPS jsou TŘI OSY, každá z tabulky upgradu:** *Poškození laseru* („ad“,
  přičítá), *Síla paprsku* („ap“, **násobí** — chybějící modifikátor po zrušení
  kadence) a kritika. **Síla paprsku** jde v menu 1,0× → 1,5× za body a v bitvě
  za zlato **bez stropu** (každý krok +0,10), takže se hráč má čím držet kroku
  s růstem životů.
- **KRITICKÁ ŠANCE = PODÍL ČASU.** U plynulého paprsku nemá smysl losovat každý
  snímek (hráč by viděl skákat čísla, která nikde nejsou), ale ani se nedá
  „zamlčet“: paprsek proto **blikne** (`CRIT_FLASH_S` = 0,22 s) a během záblesku
  bere `crit_dmg()` násobek. Průměr je přesně stejný jako u losování
  (`× (1 + šance × (násobek − 1))`), jen je vidět — a čím větší šanci si hráč
  koupí, tím častěji bliká (poměr svícení/pauza drží šanci). Záblesk je **plochý
  zbělený tón**, ne světlo kolem světla.
- **ZLATO ROSTE S OBTÍŽNOSTÍ** (`GOLD_LEVEL` 1,30 za level, od Oct 2026): životy
  poutníků rostou 1,40× za level, takže kdyby zlato stálo, hráč by za stejné
  peníze kupoval pořád slabší věž. Změřeno simulatorem: i hráč, který sype
  **všechno** do poškození, padal na 6. levelu v první vlně — permanentní
  žebříčky měl vykoupené a zlato se mu na startu levelu vrátilo na 150.
- **ODRAZ** (dřív Ricochet, Jan: „RICOHET přejmenujeme na Odraz a bude se takhle
  laser šířit na další nepřátele, podobně jako ricochet, ale bez projektilů.
  A každý odraz bude dávat menší poškození. S levelem upgradu se bude zvyšovat
  počet odrazů a bude snižovat penalizace za odraz.“). Paprsek přeskočí na
  nejbližšího dalšího poutníka **ve stejné barvě** (jinou věž nevidí), a to
  i mimo dostřel — je to odraz, ne zaměření. Každý dostane nejvýš jednou a
  **každý další odraz je slabší** (1. stupeň 1 odraz na 50 %, 2. dva na 60 %,
  3. tři na 70 %, 4. čtyři na 80 % — obě čísla drží jedna položka tabulky
  `Upgrades.chain_of`). Paprsek odrazu je **tenčí** a vychází **z prstence
  předchozí oběti**, takže je vidět, kam až se světlo rozšířilo.
- **VÝJIMKA: FIALOVÁ PO ZNEVIDITELNĚNÍ.** Když fialová po prvním zásahu zmizí,
  paprsek na ni **přestane svítit** (a odraz si ji nevybere) — dokud je duch,
  nedá se jí ublížit. Po objevení platí normální pravidla dál.
- **POČET NEPŘÁTEL V JEDNOTLIVÝCH VLNÁCH JE VYŠŠÍ** (Oct 2026): první vlna
  prvního levelu má **15 poutníků**, desátá vlna 51 a každý další **level**
  násobí celou řadu **1,20** — na desátém levelu jde o stovky (strop 400, aby
  se nekonečná partie nezadrhla). **Tempo vstupu se tomu přizpůsobuje:** velká
  vlna se vysype do 55 s (`SPAWN_WAVE_S`), ne pevnou mezerou 2,5 s — jinak by
  jedna vlna trvala desítky minut; a mezera nikdy neklesne pod 0,45 s, aby
  měla věž na zabití čas.
- **Poutníci vstupují na SPAWNOVACÍM KRUHU naslepo**, náhodným směrem, a jdou
  rovně k věži. Cesta od okraje k věži trvá **10 s** (Oct 2026: „Rychlost
  pohybu všech nepřátel se zrychlí na rychlost 1.5x. Bude to nová výchozí
  hodnota. Nové 1.0x = staré 1.5x.“ — dřív 15 s). Zrychlili se tím všichni
  nepřátelé; poměry mezi barvami (`Hue.speed_mult`) zůstávají.
- **Spawnovací kruh je větší než displej a NIKDE se nekreslí** (je pomyslný):
  jeho horní i dolní okraj se dotýká okraje herního pruhu a boky vedou mimo
  obraz — poutníci proto vcházejí ze všech směrů, i z boků. Vnější kruh, který
  je vidět, je jen **kruh dostřelu**.
- **Dosah je kruh** (kreslený na zemi): základ **34 %** poloměru plochy
  (0,34 na 390×844 — 79 px od každého boku, takže je kam upgradovat),
  vylepšením **46 %** a **60 %**; nikdy ne celá plocha. Je to okno, ve kterém
  hráč musí stihnout přepnout barvu: **3,4 s / 4,6 s / 6,0 s** v ohni
  (0,34/0,46/0,60 × 10 s u poutníka s rychlostí 1,0; pomalejší a rychlejší
  barvy mají okno delší, resp. kratší).
- **Levely vypadají stejně**, liší se jen **počtem** a složením vln (každá
  vlna míchá všechny barvy, které jsou v tom levelu ve hře).

## Upgrady a tempo hry (Oct 2026)

- **Dočasné (bitevní) upgrady NEMAJÍ STROP** (Jan: „já prozatím nechci žádné
  stropy. Žádné max.“). Kupují se za zlato tak dlouho, dokud na ně hráč má;
  jediným stropem je rostoucí cena (5, 10, 15, … zlata). V panelu se proto
  nikdy neobjeví „MAX“. **Permanentní upgrady strop mají dál** (platí se body
  z vyhraných levelů) — jejich konec je hodnota v tabulce `Upgrades.STATS`
  (`cap`) a v menu se na něm napíše „MAX“.
- **Zrychlení hry** je speciální permanentní upgrade (`gs`), ale **sám o sobě hru
  nezrychlí**: je to **klíč**, který odemkne přepínání tempa. Hra začíná **vždy
  na 1,0x** a hráč si v bitvě přepíná **1,0x / 1,5x / 2,0x / 2,5x** tlačítkem
  v horním pruhu (je vidět jen s koupeným speciálem; `Game.speed_options()`).
  Násobí se **celý krok hry** (`Game.step`), takže se zrychlí všechno, co je na
  čase — pohyb poutníků, paprsek, jed i led, regenerace i časy vln.
  Kdyby se zrychloval jen pohyb, změnila by se obtížnost.

## Tiché poškození a imunita (Oct 2026)

**Dokud je poutník duch (fialová po prvním zásahu), nedá se mu ublížit ničím.**
Dvě cesty, které to dřív obcházely, jsou zavřené:

- **Jed** tickal i na neviditelného poutníka — první zásah (jed + zmizení) se
  tak v tichosti dokončil přesně ve chvíli, kdy se fialová znovu objevila a
  hráč viděl „umřela sama, aniž by do ní věž střílela“ (`Game._advance_effects`).
- **Odraz** si mohl vybrat ducha za další oběť a poslat na něj střelu, kterou
  hráč nikdy neviděl vystřelit. Dnes to hlídá `Game._chain`, který ducha přeskočí.

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
  dobu jsou příliš výrazné. To bych lehce ztlumil."
- **BAS JE KRÁTKÝ ÚDER, NE PODRŽENÝ TÓN.** Jan: „Ty basy v hudbě jsou stále moc
  silné… Krátké melodické noty jsou v pohodě, dlouhé harmonické ne." Proto:
  basová nota se **zkrátila** (0,30 s na první a 0,20 s na třetí dobu, dřív
  1,06/0,72 s přes skoro celý takt) a přešla z **obdélníku na trojúhelník**
  (obdélník má v basu silné liché harmonické a na malém reproduktoru bzučí).
  **Amplituda zůstala** (0,09/0,07): doznívání se řeší DÉLKOU a DOZVUKEM, ne
  amplitudou — kdo utlumí amplitudu, utlumí i úder a bas zmizí celý.
  Změřeno spektrem (okno, kde dřív zněl jen doznívající bas): **úder −3 dB,
  doznívání −12,5 dB** (proti melodii −19 dB, dřív −2 dB), celý mix −1 dB.
- **POZOR NA MĚŘENÍ:** pásmo 60–250 Hz je z většiny KOPÁK, ne basové noty —
  kdo podle něj soudí „basy", měří údery. Doznívání se musí měřit v okně mezi
  notami (0,5–1,0 s po první době), kde dřív zněl už jen dlouhý bas.
- **Hraje se až po prvním klepnutí** (`touched`): prohlížeč nespustí zvuk bez
  gesta hráče. `_sync_music()` srovnává stav (ne událost), takže vypnutí
  v nastavení hudbu opravdu zastaví.
- Smyčka se nastavuje v kódu (`AudioStreamOggVorbis.loop`), ne až v importu —
  jinak by se po prvním přehrátí zastavila.

## Zvukové efekty (Oct 2026)

Jan: „A střelba a zásah by samozřejmě měly mít také zvukové efekty."

- **Tři zvuky** (`tools/make_sfx.py`, ~4 kB každý): `shot.ogg` (výstřel),
  `hit.ogg` (dopad), `kill.ogg` (smrt poutníka).
- **Hra posílá UDÁLOSTI, ne zvuky.** `Game.events` plní `_burn` („shot", tedy
  *zážeh paprsku na novém cíli*) a `_kill` („kill"). Obrazovka si je jednou za
  snímek vybere (`take_events()` = výběr i smazání) a zahraje. Hra tak zůstává
  hratelná a měřitelná bez obrazovky a zvuk je jen doplněk.
- **PAPRSEK NESMI TIKAT.** Laser svítí na cíl pořád, takže by se zvuk „výstřelu"
  ozval 60× za sekundu; hra si proto drží `Pilgrim.burning` a ozve se jen
  přechod *nesvítil → svítí* (`Game.beams_lit` je toho počítadlo). `hit.ogg`
  zůstává v tabulce zvuků, ale laser ho neposílá.
- **Odpěť mezi zvuky** (`SFX_GAP_S`: výstřel 75 ms) — při více paprscích naráz
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
