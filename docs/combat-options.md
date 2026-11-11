# DR Godot — souboj bez nové grafiky: katalog možností

Cíl: souboj musí bavit sám o sobě, jen se stávajícími 63 portréty monster, hero portrétem,
primitivy v `_draw()` (kruhy, oblouky, polygony) a existujícími zvuky. **Žádná varianta níže
nepotřebuje nový obrázek.** Cena je uvedená v řádcích kódu a v riziku, ne v grafice.

---

## 0. Změřený stav (ne dojem)

Naměřeno `tools/probe_ttk.gd` + `tools/probe_monster_balance.gd` na `test/corridor-fog-speed`:

| Veličina | Hodnota | Co z toho plyne |
|---|---|---|
| Hero DPS | 24 (start) → 91 (akt 5, z 10) | roste ~4x za celou hru |
| Čas na zabití JEDNOHO těla | 0,8 s → 3,7 s | rozhodnutí nemá čas vzniknout |
| DPS jednoho monstra | 4,6 → 67,9 | |
| Hero HP | 160 → 375 | |
| Jak dlouho zabíjí JEDNO monstrum hrdinu | 30 s (a1z1) → 5,9 s (a5z10) | v aktu 1 je monstrum neškodné |
| Rychlost monstra | 46–68 px/s (+4/akt, +1,2/oblast) | |
| Rychlost hrdiny | 140 px/s | **nic ho nikdy nedohoní** |
| MAX_ALIVE | 7 (paky 1–4, champion 2–4, elita 3 otroci) | strop hustoty |
| Elite affix | uložený na rekordu, souboj ho **nečte** (jen aura otrokům) | elita = jen vyšší čísla |
| Boss | `is_boss` se nastaví, ale **nikde se nepoužije** | boss zóna = normální paky |
| Hit-stop | `HitStop` existuje, v `survivor_screen` se **nepoužívá** | |

**Diagnóza ve třech větách.** (1) Nepřítel udeří v okamžiku, kdy se dotkne – `atk_age` je
animace *po* ráně, ne návěstí před ní – takže zranění se nedá uhýbat, jen před ním utéct.
(2) Utéct jde vždy, protože hrdina je 2–3x rychlejší než cokoli, co ho pronásleduje; souboj je
tedy DPS závod, ve kterém se nedá prohrát, jen zdržet. (3) Jediné hráčovo rozhodnutí je směr
palce; timing, pozice, riziko ani odměna za agresi v systému neexistují.

Souboj je dnes **čtecí cvičení čísel**, ne hra. Všechno níže je o tom, jak z něj udělat hru
bez jediného nového pixelu.

---

## A. Pocit z rány (impact) — nejrychlejší výhra

Vše je prezentace, nemění pravidla ani balanc. `HitStop` i `Juice` už v projektu jsou.

- **A1. Hit-stop 45 ms na zásah, 90 ms na crit a na kill.** Neexistuje levnější „wow“.
  Riziko: `Engine.time_scale` je globální, musí se vracet; síla ~10 % času souboje.
- **A2. Knockback + hit-stun.** 6–10 px odstrčení a 120–180 ms, kdy monstrum nic nedělá a jeho
  `atk_ready` se **resetuje**. Tím rány začnou být „moje“ – nepřítelovu akci přeruším.
- **A3. Micro-shake kamery** 2 px na zásah, 5 px na crit (wall-clock, ne `delta`).
- **A4. Zoom-punch na kill** – kamera 1,00 → 0,985 → 1,00 za 120 ms.
- **A5. Smrt těla: rozpad.** Portrét v 250 ms zprůhlední a klesne, místo aby zmizel v jedné
  snímce. Dnes kill „není vidět“ – číslo zmizí a tělo je pryč.
- **A6. Zvukové schody.** Každý další zásah v řadě +1 půltón (`pitch_scale`), po 1,5 s ticha
  reset. Mechanicky nic, pocitově „combo“.
- **A7. Číslo damage:** crit větší písmo + jiná barva, `HEROIC` už existuje; přidat „přebytek“
  (overkill) jinou barvou.
- **A8. Bílý záblesk rámu na zásah** (1 snímek, 0,4 alfy) – bez glow, jen plochá barva.

Cena: 1–3 hodiny na položku, 10–40 řádků. **Doporučené pořadí: A1, A2, A5, A6.**

---

## B. Spravedlnost a čitelnost — strukturální jádro

Bez tohoto zůstane každá další vrstva jen dekorace. Tady se mění pravidla, ne obrázky.

- **B1. Wind-up (návěstí) u nepřátelského útoku.** 300–500 ms před dopadem: monstrum se
  zatáhne, pod ním se kreslí **oblouk/kruh, který se plní**, a damage přijde na konci. Krok
  ven ho zruší. Jediná změna, která z „stat race“ udělá souboj. Kresba = 2 oblouky.
- **B2. Různé tvary útoku podle druhu** (všechno primitiva):
  - *kousnutí* – jeden cíl vpředu (dnešní stav),
  - *slam* – kruh kolem těla (AoE, uhýbá se krokem),
  - *výpad/charge* – přímka, po výpadu 1 s okno na potrestání,
  - *hod* – už existuje (orb).
- **B3. Barva návěstí = druh.** Bílá = jde uhnout, červená = neuhnutelné (AoE), modrá = stun.
  Bez legendy to hráč přečte za dvě rány.
- **B4. i-frames.** 0,25 s nesmrtelnosti po zásahu (nebo po dodge) – brání „tři rány v jedné
  snímce“ z paku, což je dnes nejčastější pocit „to je nefér“.
- **B5. Dodge/roll jako akce na kolečku.** Kolečko má 6 výsečí a bindable seznam – dodge se
  vejde bez nového UI. 160–190 px, 0,22 s, 1,2 s cooldown. Kresba: jen šmouha (2 polygony).
- **B6. Blok/parry** (volitelné, dražší): držený blok -60 % damage, perfektní parry 150 ms =
  stun monstra. Přidává druhé gesto; na telefonu s jedním palcem u pohybu to může být moc.
  Doporučuji **odložit** – dodge dělá 80 % práce.
- **B7. Stamina** – nedoporučuji. U mobilu s jedním palcem trestá pohyb, což je jediná
  obrana, kterou hráč má.

Cena B1: ~150 řádků + testy (nejvyšší riziko, ale nejvyšší zisk). B2: ~60 řádků na archetyp.
B5: ~80 řádků (pravidla) + 20 (kresba).

---

## C. Hloubka rozhodování (jeden palec, víc než „drž útok“)

- **C1. Nabíjený útok.** Držení > **1,6 × vlastní swing time zbraně** (NE konstanta!) → těžká
  rána: širší oblouk, +80 % damage, knockback. Riziko/výnos přímo pod palcem, který už drží.
  S palicí se nabíjí 1,6 s, s dýkou 0,53 s — zbraň rozhoduje i tady.
- **C2. Combo 1-2-3.** Každá třetí rána = finisher (širší oblouk, zasáhne 2 těla). Odměňuje
  zůstat v boji místo kroužení. Nula nové grafiky, jen jiný oblouk.
- **C3. Bonus zezadu/boku.** Útok mimo zorný úhel monstra = +50 %. Donutí hráče obcházet pak,
  ne stát na místě. Indikace = malý znak nad tělem.
- **C4. Momentum / vztek.** Měřič plněný zásahy; utratí se za vylepšené kouzlo nebo léčení.
  Agrese se vyplácí, kroužení ne. Kresba = stávající gauge (`ui_gauge.gd`).
- **C5. Štít jako mechanika.** Štítonoš blokuje zepředu → musí se obejít nebo omráčit.
  Postava = existující portrét, mechanika = jeden `if`.
- **C6. Kombinace stavů.** Stun → +crit, chill → „shatter“ (bonus damage). Kouzla už stavy
  mají; chybí jen násobič. Vnímaná hloubka za pár řádků.
- **C7. Prioritní cíl.** Asist už vybírá podle HP; volitelně „tap na monstrum = zamkni“.
  Spíš odložit – UI navíc, zisk malý.

**Doporučené: C1, C2, C3** (jedno gesto, tři vrstvy). C4 až po B1.

---

## D. Nepřátelské archetypy — data, ne grafika

Portréty jsou busty; chování je jen vlajka na rekordu. Každý archetyp mění **jak** se s ním
bojuje, ne jak vypadá.

- **D1. Nájezdník (charger).** Návěstí, pak výpad 2–3x rychlostí, přestřelí, 1 s okno.
  Konečně něco, co hrdinu dohoní – řeší „nic mě nedohoní“.
- **D2. Výbušník (bomber).** Dojde blízko, 1,2 s svítí (kruh se plní), vybouchne v kruhu.
  Zabít dřív = bezpečno. Učí prioritu cíle bez UI.
- **D3. Štítonoš.** Blok zepředu (C5).
- **D4. Přivolávač.** Sesílá 2 slimáky, musí se fokusovat. Využívá existující spawn API.
- **D5. Léčitel/posilovač.** Healuje pak; priorita. Jeden `if` v ticku.
- **D6. Elitní affixy, které souboj SKUTEČNĚ čte.** Dnes se ukládají a zahazují. Tři affixy
  stačí: *Swift* (nedá se utéct), *Thorny* (melee bolí víc – nutí kouzel), *Vampiric*
  (nutné burstnout). Zviditelnit barvou prstence a písmenem.
- **D7. Dva druhy střelby.** Pomalá velká (uhnutelná krokem) vs rychlá malá (nutný dodge).

Cena: 30–70 řádků na archetyp + test. **D1, D2, D6** mají nejlepší poměr.

---

## E. Struktura běhu — proč to hrát znovu

- **E1. Boss na konci aktu.** `is_boss` se už nastavuje a je nepoužitý. Tři vzory (charge,
  summon, slam) + HP bar nahoře. Největší „beat“, který hře chybí, a je to jen AI skript.
- **E2. Truhla na konci chodby** za vyčištěnou zónu (existuje `chest_screen` + `loot_system`).
- **E3. Volba 1 ze 3 na východu** (bonus do běhu / kouzlo / zlato). Řádky textu, žádná grafika.
  Dělá z „dojdi k východu“ rozhodnutí.
- **E4. Riziko za odměnu: zkratka přes elitu** vs. delší bezpečná cesta.
- **E5. Prokletá svatyně** – +30 % damage do konce běhu, -20 % max HP. Klasika, nulová grafika.
- **E6. Zdravotní orb** z 5 % killů – agrese se vyplácí, hráč nemusí utíkat domů.

---

## F. Čísla a rytmus (bez nových systémů)

- **F1. Prvních 20 sekund.** Zaručit slabý pak do 200 px od startu, aby první kill přišel do
  3 s. Dnes první zóna začíná prázdným středem a hráč jde 20+ s.
- **F2. Hustota.** MAX_ALIVE 7 je dobrý strop pro 390px displej; přidat **jednu řízenou vlnu**
  (10–12 slabých těl) jako moment „tohle je jiné“, ne jako nový standard.
- **F3. TTK paku.** 4 těla × 2 s = 8 s stojení. To je moc na to, aby to bylo napínavé a málo
  na to, aby to bylo epické. Cíl: 3–5 s na pak, s jedním rozhodnutím uvnitř (uhnout, obejít,
  použít kouzlo).
- **F4. Méně, ale čitelných ran.** Dnes 0,78–1,95 s mezi ranami od každého těla → 4 těla =
  damage každých ~0,3 s, což se nedá číst. Přesunout váhu z frekvence do **velikosti**
  (jedna těžká, návěstěná rána za 2,5 s). Toto je přímý důsledek B1.
- **F5. Rychlost monstra.** Normální 60–80 (kroužení funguje), charger 150+ v impulzu.
  Bez tohohle zůstává „utíkej a nic se neděje“ dominantní strategie.

---

## G. Informační vrstva (HUD, kreslený v `_draw`)

- **G1. Návěstí nad tělem** – „!“ nebo plnící se oblouk (patří k B1).
- **G2. Role na portrétu** – champion/elita = jiný prstenec + písmeno; dnes je rozdíl jen
  v číslech, která hráč nevidí.
- **G3. Šipky na okraji** pro nepřítele mimo obraz (hlavně střelce).
- **G4. Směrový indikátor zásahu** – oblouk na okraji obrazu podle směru rány (dnes jen
  červený záblesk bez informace „odkud“).
- **G5. Kill-streak** – čítač + zvukové schody (A6). Čistě motivační, nula kódu v pravidlech.
- **G6. HP bar hrdiny** už je; přidat „ghost“ (bílý pruh dobíhající za skutečným HP) – čte se
  jako rána, ne jako číslo.

---

## H. Meta vrstva, která se propíše do souboje

- **H1. Talenty jako nová slovesa**, ne +%. „Třetí rána omráčí“, „dodge nechá krvácení“,
  „crit vrací manu“. Tabulka talentů existuje.
- **H2. Zbraň = chování.** Dýka: rychlá + bonus zezadu. Sekera: oblouk zasáhne 2 těla.
  Palice: knockback/stun. Nula nové grafiky, obrovský rozdíl v pocitu – a tabulka zbraní už
  existuje.
- **H3. Gemy/proky** – socket systém existuje, proky čte souboj.

---

## I. Co NEDĚLAT (šetří kolo)

- **Víc monster.** 16 už bylo moc; 7 je strop pro 390 px. Hustota není odpověď.
- **Stamina.** Trestá jediný dostupný pohyb.
- **Particle systémy.** Proti briefu (žádný glow) a jediná GPU položka.
- **Větší hitboxy jako „fix“ pocitu.** Problém je timing, ne zásah.
- **Parry + dodge + blok najednou.** Tři obranná gesta na jeden palec = nehratelné.

---

## Doporučené pořadí (tři vlny, každá sama o sobě hratelná)

**Vlna 1 — „cítit ránu“ (1 větev, ~1 den):**
A1 hit-stop · A2 knockback+stun · A5 rozpad těla · A6 zvukové schody · A3 shake.
Nic z toho nemění balanc; hra okamžitě přestane být „klikací“.

**Vlna 2 — „souboj, ne závod“ (1–2 větve, ~2–3 dny):**
B1 wind-up + B2 tvary útoků · B4 i-frames · B5 dodge · F4/F5 čísla · D1 charger · D6 elitní affixy.

**Stav po prvním průchodu (implementováno, commit `36b7bb5`):**
hotové B1 (wind-up 0,4 × `atk_cd`, whiff při odchodu), B4 (i-frames 220 ms), knockback +
stagger, crit ruší návěstí, rozpad těla, hit-stop 30/65/45 ms a sweep na okraji portrétu.
**Zbývá:** B2 (tvary útoků podle druhu), B5 dodge, D1 charger, D6 affixy, C1–C3, E1 boss.

**Stav po druhém průchodu (commity `9a25315` + tento):**
Naměřeno `tools/probe_dodgeability.gd`. Střelec: `SHOOT_RANGE` 470 → 300 (dřív pálil z 421–428 px,
tj. za okrajem obrazu), `MIN_SHOT_GAP` 150 — zblízka nestřílí, ale uskočí (0,30 s / 320 px/s,
cooldown 0,9 s); zaražený o skálu nestřílí vůbec; vběhnutí do návěstí ránu ruší. **Punish okno:**
whiffnutá rána nechá tělo 700 ms otevřené, bere 1,5×, nekráčí a neútočí, kreslí se přerušený
prstenec s mezerou. Před tímhle byla obrana zdarma a tankování matematicky lepší.
**Zbývá pořád:** B2 (tvary útoků podle druhu), B5 dodge, D1 charger, D6 affixy, C1–C3, E1 boss.

⚠️ **A6 (zvukové schody) NEPLATÍ** — Jan dřív odmítl jakýkoli pitch shift („nezní to dobře"),
cue se hraje na své vlastní výšce. Pocit comba musí nést vizuál (čísla, hit-stop), ne hudba.

**Vlna 3 — „proč další běh“ (~3–4 dny):**
E1 boss · E6 zdravotní orb · C1 nabíjený útok · C2 finisher · C3 bonus zezadu · E2/E3 truhla + volba.

Každá vlna jde nasadit samostatně a každá se dá na telefonu odmítnout bez ztráty ostatních.

---

## J. Smlouva: které RPG staty nesmí ztratit platnost

Námitka, která tenhle oddíl vyvolala, je správná: **nové gesto nesmí být druhý soubojní
systém.** Pokud by těžký útok, combo finisher nebo dodge měly vlastní pevné časy nezávislé na
zbrani, pak `swingMs` / IAS / DEX přestanou něco znamenat a celá tabulka zbraní se stane
dekorací. Proto platí pro každou novou mechaniku jedno pravidlo:

> **Každý nový čas se DERIVUJE z existujícího statu, nikdy není konstanta.**

| Nová mechanika | Špatně (zabíjí stat) | Správně (stat zesiluje) |
|---|---|---|
| Nabíjený útok | pevných 0,45 s pro všechny | `1,6 × main_swing` → palice 1,6 s, dýka 0,53 s |
| Combo finisher | samostatná animace | **třetí rána na témže clocku** – rychlá zbraň se k finisheru dostane 3× dřív |
| Dodge | jen cooldown | cooldown **plus** ztracený čas na swing clocku: kdo má vysoké DPS, zaplatí za úhyb víc |
| Nepřátelský wind-up | pevných 400 ms všem | `0,4 × atk_cd` monstra → vlk návěstí krátce (těsné), medvěd dlouze (čitelné, ale bolí) |
| Bonus zezadu | plochý | násobič **existujícího** rollu, kadence se nemění |
| Archetyp útočníka | vlastní damage tabulka | `dmg_min/max` a `atk_cd` monstra zůstávají zdrojem |

**Co se tím chrání:** rychlost zbraně, IAS, DEX cap, `critChance`, `skillDmg` i celý loot systém
zůstávají jediným zdrojem tempa. Nové vrstvy jen mění, *kdy* se ten výkon uplatní (otevřené
okno vs. commit), ne *jaký* je. To je přesně rozdíl mezi „rychlá dýka = víc ran“ a „rychlá
dýka = víc příležitostí trefit otevřené okno“ — druhé je hlubší, ne mělčí.

**Jediné, co se reálně posune:** když každý nepřítel dostane čitelné návěstí, builds postavené
na „zabij dřív, než udeří“ zeslábnou ve prospěch positioning buildu. To je záměr, ne vedlejší
účinek — a je to věc jednoho čísla (podíl wind-upu na `atk_cd`), ne nového systému.
