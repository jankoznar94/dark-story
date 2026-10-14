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
- **Svazek drží jeden cíl, dokud neumře.** Vylepšení později přidá další cíle.
- **Poutníci vstupují na okraji plochy naslepo**, náhodným směrem, a jdou
  rovně k věži. Cesta od okraje k okraji věže trvá **8 s**.
- **Dosah je kruh** (kreslený na zemi), základ ~1/3 poloměru plochy,
  vylepšením až ~2/3.
- **Levely vypadají stejně**, liší se jen složením vln (každá vlna míchá
  všechny čtyři barvy).

## Rozvržení

Hra je na **výšku**: kruh plochy je vepsaný do kratšího rozměru displeje.
Na telefonu na šířku je plocha malá (~270 px) a barvy se na 18px poutníkovi
nedají přečíst; na výšku má ~366 px.

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
