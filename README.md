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
- **Svazek drží jeden cíl, dokud neumře.** Střela, jejíž cíl mezitím zmizí
  (umřel, hráč přepnul barvu, fialová se zneviditelnila), zanikne a nikoho
  jiného nezasáhne.
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

## Rozvržení

Hra je na **výšku**. **Plocha a zoom jsou dvě různá čísla:**
- **Zoom** (věž, poutníci, tahy) se počítá z **vepsaného kruhu do kratší strany**
  herního pruhu — přesně jako dřív, takže velikosti zůstávají stejné (na
  390×844 věž 22 px, poutník 9 px) a nic se „nepřibližuje“.
- **Spawnovací kruh** je polovina **výšky** herního pruhu: dotýká se horního
  i spodního okraje pruhu a na výšku vede boky **147 px mimo obraz** (na 390×844),
  takže poutníci vcházejí ze všech směrů. Nikdy není menší než zoom.
  Na šířku je pruh širší než vyšší, kruh se tedy vejde do šířky a hra jen řekne
  „otoč telefon“.

Barvu vždy nese i **tvar** (runa) — u poutníka je runa přímo tvarem těla:
oheň trojúhelník, voda kapka, země čtverec, vzduch prstenec. Barva nikdy
nesmí být jediný nositel informace.

## Testy

```bash
godot4 --headless --path . --import                      # zaregistruje class_name
godot4 --headless --path . --script res://tools/test_scripts_load.gd
godot4 --headless --path . --script res://tools/test_core.gd     # CORE_ALL_PASS=true
godot4 --headless --path . --script res://tools/test_layout.gd   # LAYOUT_ALL_PASS=true
```
