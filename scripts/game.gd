class_name Game
extends RefCounted

# CELA HRA. Zadny uzel, zadny Input, zadne _draw - proto ji jde hrat a merit
# headless a proto se da overit, ze se chova stejne na kazde obrazovce.
#
# MODEL (rozhodnuty s Janem, Oct 2026 - "jako ve hře Tower"):
#   * hra je delena na LEVELY; level ma 3-5 VLN a bonus je az za vyhrany level,
#   * v bitve se za ZLATO kupuji docasne kroky upgradu a na kazdem levelu se
#     kupuji ZNOVU (zlato zacina na kazdem levelu znovu),
#   * v menu se za BODY (za vyhrany level) kupuji PERMANENTNI stupne, ktere
#     posouvaji START kazdeho parametru,
#   * SPECIÁL (multishot, odraz, jed, led) je jen permanentni,
#   * VEZ STRIli LASEREM, ne projektily (Jan, Oct 2026: "Vrátíme se k laseru
#     místo projektilů... Poškození bude probíhat plynule"). Dostrel je konec
#     paprsku, poskozeni tece kazdy snimek (`laser_dps`) a odraz paprsek
#     rozvetvi na dalsi poutniky (`odraz`), kazdy dalsi za mene,
#   * vez ma ZIVOTY: poutnik, ktery dojde, ubere tolik, kolik mu zbylo zivotu,
#     zbroj to zredukuje a regenerace doléčí,
#   * prohra vraci hrace do menu; zlato z rozehraneho levelu propada, upgrady
#     i body zustavaji.
#
# Kdo chce zmenit cisla, meni `Upgrades.STATS` (upgrady) nebo konstanty tady
# (obtiznost). Obrazovka ani testy si NIKDY nepocitaji hodnotu samy.

# ---------------------------------------------------------------- KONSTANTY

# CESTA OD OKRAJE K VEZI. Je to CAS, ne rychlost v pixelech: na kazdem displeji
# ma poutnik na cestu stejne dlouho, takze "jde pomalu" je vlastnost hry, ne
# rozliseni. Jan dvakrat: "Rychlost všech nepřátel se musí snížit" (8 -> 12 s)
# a "Celkově ještě zpomalíme pohyb nepřátel" (12 -> 15 s).
#
# Oct 2026 - OPACNY SMER: "Rychlost pohybu všech nepřátel se zrychlí na rychlost
# 1.5x. Bude to nová výchozí hodnota. Nové 1.0x = staré 1.5x. Jsou teď příliš
# pomalí." 15 / 1,5 = 10 s.
#
# Oct 2026 (Jan): "Všechny nepřátele o 15 % zpomalíme. Ať to vytvoří pocit ještě
# větší vzdálenosti a rozlohy." 10 / 0,85 = 11,8 s. POZOR: okno na reakci je
# `dostrel * TRAVEL_S`, takze s pomalejsi chuzi roste i okno na reakci - kdo
# hybe timhle cislem, hybe obtiznosti a musi to merit (`tools/balance_sim.gd`).
const TRAVEL_S := 11.8
const BASE_HP := 20.0
# OBTIZNOST: kazdy dalsi LEVEL je o 22 % tuzsi (Jan schvalil 1,22; driv 1,15)
# a kazda dalsi vlna v levelu jen nepatrne (`WAVE_HP`). Driv to bylo 13 % za
# vlnu v nekonecne partii - s levelem a resetenym zlatem by to bylo nehratelne.
const LEVEL_HP := 1.40
# Vlna v ramci levelu zveda obtiznost jen NECITELNE. INVARIANT: krok za vlnu
# zustava 1,018 (stejna obtiznost vlny jako driv). Oct 2026 (Jan): "Mozna
# snizime pocet vln jednotlivych levelu na 30. Tech 50 je uz moc dlouha doba."
# Level se tim ZKRATI, ale obtiznost jednotlivych vln se NEMENI - rust za cely
# level je 1,018^29 = 1,68 misto 2,40, takze level-to-level je 2,35x (s
# `LEVEL_HP` 1,40). Kdo by chtel zachovat 2,4x za level, musi krok zvednout na
# 1,031 - to se ZKOUSELO a hlupy hrac padl uz v 10. vlne prvniho levelu
# (boss), takze se obtiznost nesmi zvedat spolu se zkracenim.
const WAVE_HP := 1.018
# START ZLATA. Jan (Oct 2026): "hráč začíná s příliš mnoho penězi. Je velmi
# snadné se brzy dostat na vysoké upgrady poškození a pak je každý mrtvý během
# chvilky." 150 -> 60: na zacatku levelu si hrac koupi dva az tri docasne kroky
# (5 + 10 + 15), ne deset. Zlato za zabiti zustava - hrac ma rust pocitit
# v bitve, ne hned na startu.
#
# Oct 2026 (Jan): "Nárůst cen u upgradů bude naopak méně strmý a výdělky za
# zabití poutníků budou úměrně taky nižší. Ať je pocitově upgrade stejně drahý
# v poměru počet zabitých/nový upgrade, ale ať cena tak rychle neroste do
# stovek a tisíců. Jde spíš o optický rozdíl."
#
# => CELY ZLATY OBEH SE ZMENŠIL PETKRAT a je to VEDOME jen opticka zmena:
#    * cena docasneho kroku je `n^2` misto `5 * n^2` (1, 4, 9, 16, 25 ...),
#    * zakladni zlato za zabiti 18/10/14/16/14/26 -> 4/2/3/3/3/5,
#    * start 60 -> 12, bonus za vlnu 4/0,1 -> 0,8/0,02,
#    * "Zlato za zabiti" ma cenu 5x vyssi nez ostatni (`Upgrades.temp_cost`):
#      jeho krok je cele +1 zlato, takze v petkrat mensi mene je petkrat
#      silnejsi - jinak by se z nej stal nejlepsi nakup ve hre.
#    Kdo hybe jednou stranou, MUSI pohnout i druhou: rozhoduje POMER (kolik
#    zabiti hrac na jeden upgrade potrebuje), ne velikost cisla na obrazovce.
#    Overuje se to simulatorem - pocet koupenych kroku za level musi vyjit
#    stejne jako pred zmenou.
const START_GOLD := 12
# PRUJEM PENEZ V LEVELU. Jan (Oct 2026): "Jeste o trochu snizime prutok penez
# v levelu. Docasne upgrady se shani snadno a vetsinu casu na hrace neni kladen
# velky narpor."
#
# Snizuje se JEN to, co hrac vydela BEHEM levelu (zlato za zabiti a za vlnu),
# ne start levelu ani koupene "zlato za zabiti": hrac ma mit horsi pocit z
# toho, ze mu utika prijem, ne ze ho hra okrada na startu. Hodnota je zamerne
# jedno cislo - kdyby se snizovaly tri tabulky zvlast, rozejdou se.
# Mereno `tools/balance_sim.gd` (pocet koupenych docasnych kroku za level).
const GOLD_INCOME := 0.80
const GOLD_LEVEL := 1.30
# ZLATO ROSTE S OBTIZNOSTI: zivoty rostou 1,40x za level, takze i zlato (za
# zabiti, za vlnu i na startu) musi rust stejnym krokem - jinak by hrac za
# stejne penize kupoval porad slabsi vez. (Zmereno driv: hrac sypajici vsechno
# do poskozeni padl na 6. levelu v prvni vlne, protoze zlato se mu vracelo na
# stejnou startovni hodnotu.)
const BUILD_TIME := 5.0
# VELIKOST VLNY (Oct 2026). Jan: "Počet nepřátel v jednotlivých vlnách bude
# obecně vyšší. V prvních levelech bude začínat třeba na 15. Ve vyšších to budou
# klidně desítky až stovky. Samozřejmě musí chodit v takovém tempu a pořadí, aby
# bylo možné je zabít."
#
# JSOU TO DVE CISLA, NE JEDNO: tabulka je pocet poutniku v TECHTO vlnech PRVNIHO
# levelu (od Oct 2026 PADESAT vlna na level, Jan: "Kazde kolo bude mit 50
# levelu" = level ma 50 vln) a kazdy dalsi level ji NASOBI
# (`WAVE_SIZE_PER_LEVEL`). Driv se k tabulce pricitaval jeden poutnik za level,
# takze se stropu (24) dosahlo uz ve tretim levelu a "vyssi levely" se v
# poctech vubec neprojevily. Nasobenim se z desítek stanou stovky.
#
# TABULKA MA PADESAT POLOZEK (ne deset): vlna 1 zacina na 15 (Janovo cislo)
# a padesata konci na 72.
#
# Oct 2026 (Jan): "Nárůst počtu poutníků v jednotlivých vlnách musí být o něco
# strmější." - tabulka je proto GEOMETRICKA (15 x 4,8^(i/49)), ne skoro
# rovnomerne rozlozena jako driv. Pomer prvni a posledni vlny levelu sel
# z 3,4x na 4,8x (+41 % strmosti); prumer vlny z 29,5 na 36,4 poutniku
# (+23 %). Prvni tri desitky vln jsou tim o par poutniku vetsi, posledni
# desitka narostla vyrazne (51 -> 72).
#
# POZOR: vetsi vlny znamenaji delsi level (doba vlny = max(vstupni okno,
# doba zabijeni) a doba zabijeni roste s poctem). Kdo hybe tabulkou, at
# zmeri `tools/balance_sim.gd --levels=1` - a kdo chce level zkratit, hybe
# `SPAWN_SPREAD` (mene michani barev) nebo `BUILD_TIME`, ne pocty zpet dolu.
#
# Kdo meni pocet vln, musi prodlouzit/zkratit TUHLE tabulku: `wave_size` bere
# `WAVE_SIZES[vlna]`, takze kratka tabulka by vsechny pozdejsi vlny srovnala
# na sve posledni cislo (a level by prestal gradovat).
# TABULKA MA TRICET POLOZEK (Oct 2026, Jan snizil level z 50 vln na 30): vlna
# 1 zacina na 15 (Janovo cislo) a tricata konci na 72 - stejny rozsah jako
# driv, ale v mene krocich, takze rust mezi vlnami je o neco strmejsi.
# Geometricky rust 15 x 4,8^(i/29).
const WAVE_SIZES := [15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
	26, 27, 29, 30, 32, 34, 36, 38, 40, 42,
	44, 47, 49, 52, 55, 58, 61, 65, 68, 72]
const WAVE_SIZE_PER_LEVEL := 1.20
# STROP VELIKOSTI VLNY: hra je nekonecna, takze pocet musi nekam dojit - na 20.
# levelu by jinak chodily tisice poutniku a hra by se zadrhla.
const WAVE_SIZES_MAX := 400
# ODMENA ZA VLNU. Soucet za CELY LEVEL se drzi na tom, kde byl driv (~65
# zlata): s 30 vlnami 30*1,56 + 0,039*465 = 65. Pomer bonusu k vydelku ze
# zabiti zustava stejny jako pred zmensenim celeho zlateho obehu.
# Petkrat mensi cislo je soucast zmenseni celeho zlateho obehu (viz
# `START_GOLD`). Oct 2026 se navic cely prijem behem levelu krati
# `GOLD_INCOME` (0,80).
const WAVE_BONUS := 1.56
const WAVE_BONUS_PER_WAVE := 0.039
# ODMENA ZA VYHRANY LEVEL V BODECH (Jan schvalil): 25 + 5 * level.
const BODY_BASE := 25
const BODY_PER_LEVEL := 5
# BODY ZA ODRAZENOU VLNU. Jan (Oct 2026): "hráč by měl dostávat body pro
# permanentní upgrady i během boje. Ne jen po dokončení levelu. Takhle to
# logicky nedává smysl."
#
# V The Tower je to stejne: mince (permanentni mena) se vydelavaji BEHEM
# partie - za zabiti ne-zakladnich nepritel, za vlnu a za milniky - a utraceji
# se az ve Workshopu mezi partiemi. Body se proto pripisuji HNED a ukladaji
# (`Profile.add_body`), takze hrac o ne neprijde, kdyz partii vzdá.
#
# POCITAJI SE JEN V NOVEM LEVELU (`level > profile.best`): jinak by si hrac
# opakovanim prvniho levelu vykupil cely permanentni zebricek.
# BODY ZA ODRAZENOU VLNU. Oct 2026 se level zkratil z 50 na 30 vln, takze
# 1 bod za vlnu by dal o 40 % mene permanentnich stupnu za stejnou praci - hra
# by byla tezsi jen proto, ze je kratsi. Proto 2: 30 vln = 60 bodu za level
# (driv 50), takze tempo permanentniho zebricku zustava.
const BODY_PER_WAVE := 2
# KAZDY LEVEL MA TRICET VLN (Oct 2026: "Mozna snizime pocet vln jednotlivych
# levelu na 30. Tech 50 je uz moc dlouha doba."). Pozor: kdo hybe timhle
# cislem, hybe i `WAVE_HP` (rust za level), `WAVE_SIZES` (tabulka musi mit
# stejne polozek), `WAVE_BONUS` (soucet zlata za level), `BOSS_EVERY_WAVES`
# (pocet bossu za level) a `KOLO_PER_LEVEL`, ze ktereho se pocita `kolo()`.
# Vsechno to hlida `tools/test_core.gd` a meri `tools/balance_sim.gd`.
const WAVES_PER_LEVEL := 30
# KOLO SE POCITA VZDY PO CELY LEVEL (dnes tricet vln), takze "kolo" je proste
# poradi vlny pres cely pruchod hrou. Odtud se bere obtiznost (hp_for) i velikost
# vlny (wave_size) - jedno pocitadlo, ne dve.
const KOLO_PER_LEVEL := WAVES_PER_LEVEL

# VSTUPNI OKNO VLNY. Neni to pevna mezera: pocita se z ROZDILU CASU CESTY barev
# ve vlne (`wave_gap`).
#
# Jan (Oct 2026, druhy pruchod): "Nemá smysl, aby došli ve stejnou chvíli. Ta
# hra potřebuje, aby chodili různě. Náhodně. Aby hráč neustále musel hlídat
# barvu a průběžně přepínat." - takze ZADNE srovnavani dorazu: barvy vstupuji
# v nahodnem poradi a dlouho (okno je nasobek rozdilu rychlosti), takze se
# u veze MIJEJI CELY CAS. Kdo hleda "dorazi spolu", hleda starou verzi teto
# opravy - srovnavani dorazu Jan zamitl.
#
# PROC ZROVNA ROZDIL CASU CESTY: zluta je u veze o ~8 s driv nez cervena a to
# se neda obejit (rozhoduje rychlost). Kdyz vlna vstupuje krátce, obe barvy se
# minou a prepinani barev nema smysl (zmereno 0 %). Kdyz vstupuje DELE nez je
# ten rozdil, obe barvy jsou v dostrelu porad a hrac musí prepinat prubezne.
const SPAWN_SPREAD := 3.0
# DNO A STROP OKNA: prvni vlny nesmi vstupovat v jednom okamziku a vlna
# o stovkach poutniku nesmi vstupovat pul minuty. STROP MA VYJIMKU - na boss
# vlne je okno aspon tak dlouhe, jak dlouho jde boss k vezi (viz `wave_gap`).
const SPAWN_WINDOW_MIN := 6.0
const SPAWN_WINDOW_MAX := 30.0
# DNO NA JEDNOHO POUTNIKA. Je to ZAROVEN HRANICE OBTIZNOSTI: cim kratsi mezera,
# tim vic poutniku je na plose naraz a tim vic prace pro vez.
const SPAWN_GAP_MIN := 0.10

# BOSS. Jan (Oct 2026): "Taky musime pridat boss fighty." Vzor je hra The
# Tower: na normalnich vlnach je boss vylouceny a na boss vlne zaruceny, ma
# 20x zivoty a 30 % rychlosti bezneho poutnika (tam: 20x health, 30 % speed),
# je vyrazne vetsi a pada z nej 5x vic zlata (tam: 5 coinu misto 1).
#
# NENI to nova mechanika: boss je poutnik TE vlny s jinymi cisly, takze plati
# vsechno ostatni - barvy, paprsek, odraz, jed, led i chovani barvy. Proto je
# boss ZKOUSKA POSKOZENI, ne hadanka.
const BOSS_EVERY_WAVES := 10
const BOSS_HP_MULT := 20.0
# RYCHLOST BOSSE JE PETINA ZAKLADNI, ALE UZ NE ZAVISLA NA BARVE (Oct 2026).
# Driv se nasobila i `Hue.speed_mult`, takze cerveny boss sel k vezi 65 s a
# zluty 30 s - cas, kdy boss dojde, se nedal naplanovat a cerveny boss stravil
# posledni pulminutu cesty sam (presne to Jan kritizoval).
#
# Dve veci, ktere se tim zmenily, a obe se MUSELY premerit (`tools/balance_sim`):
#   * DRIV BYL BOSS UVNITR VLNY, ne za ni. Vez se musi delit mezi bosse a
#     poutniky, kteri jeste jdou - boss proto dostane za stejnou dobu mene ran
#     a MUSI mit vic casu v dostrelu. Odtud petina (0,20) misto 30 %: presne
#     tolik mel nejpomalejsi boss ve stare hre (cervena a stribrna, jejichz
#     `speed_mult` je 0,60 x 0,30), takze nejtvrdsi bossove zustali zabitelni.
#     0,30 uz hrace v 10. vlne zabilo (zmereno: hlupy hrac padl na 10. vlne).
#   * DOBA CESTY JE PRO KAZDEHO BOSSE STEJNA: `TRAVEL_S / 0.20` = ~59 s. Diky
#     tomu se da vlna rozvrhnout tak, aby jeste prichazela, kdyz boss dochazi
#     k vezi (`wave_gap` na boss vlne prodluzuje vstupni okno na tuhle dobu).
const BOSS_SPEED_MULT := 0.20
const BOSS_SIZE := 2.5
const BOSS_GOLD_MULT := 5.0
# KDE VE VLNE SE BOSS OJEVI.
#
# Oct 2026 (Jan): "Kola s bossem musí být udělaná trochu jinak. Boss musí
# vyrazit dříve. Teď vždy hráč pobije všechny ostatní a boss sám pak cestuje
# strašně dlouho k věži o samotě. Ve chvíli, kdy boss dochází k věži, ještě
# musí zabývat nějací nepřátelé."
#
# => 0,0 = BOSS VYRAZI PRVNI, na cele vlny. Je pomaly (30 % rychlosti), takze
#    ho beznou poutnici, kteri vstupuji za nim, cestou dohoní a predhoní - takze
#    k vezi nedojde sam v prazdnem poli, ale uprostred vlny. Driv stál uprostred
#    vstupu a hrac mel vsechno ostatni dawno mrtve.
# The Tower: na tierech 1-6 v pevnem bode vlny (uprostred), od tieru 7 nahodne
# mezi 5 a 75 % vlny - Janovo reseni je jednodussi a odpovida jeho pripomince.
const BOSS_SPAWN_FRAC := 0.0

# LASER. Neni to strela, co leti - je to paprsek, ktery sviti, dokud je cil
# v dostrelu a vez ho vidi. Sirka je podil MERITKA a s kazdym odrazem se
# zužuje, aby hrac na prvni pohled videl, ktery cil je hlavni.
const BEAM_W_FRAC := 0.015
const BEAM_TAPER := 0.72
# PRSTENEC KOLEM POUTNIKA = jeho HP BAR (kruh, ktery je i VIDET). Paprsek na nem
# uz NEKONCI: Jan (Oct 2026) "Laser směřuje stále do středu nepřítele. Měl by
# směřovat spíš na jeho obal." - konci na TELI poutnika (`PILGRIM_HIT_FRAC`),
# protoze prstenec je od tela dal a cara mezi nimi visela ve vzduchu. Prstenec
# kresli obrazovka dal, aby hrac videl, kde konci zivoty poutnika.
#
# Oct 2026 (Jan): "Udělejme větší vnitřní padding. Ať kruh není nalepený přímo
# na tvář uvnitř." Pri 1,30 sel prstenec tesne kolem tvaru (spicka trojuhelniku
# je v 1,00 r, brisko kapky v 1,15 r) - na telefonu zbyla mezera 1-4 px a kruh
# vypadal, jako by obkresloval oblicej. Pri 1,70 je mezera 4-6 px podle tvaru:
# poutnik je v kruhu, ne v jeho obrysu. Paprsek tim konci o kousek dal od tela.
# Zmereno na snimku 390x844 (`zily2_ring_probe.py`): tvár 11 px, prstenec 22 px.
const RING_FRAC := 1.70
# VELIKOST POUTNIKA je NASOBEK ZAKLADNI velikosti kresby (`ScreenLayout.pilgrim_r`).
# Puvodne 0,85 (Jan: "Všechny nepřátele o 15 % zmenšíme"). Od Oct 2026 je poutnik
# PUNTIK S PISMENY a Jan k tomu rekl: "Všichni budou mít tvar puntíku. V něm budou
# mít iniciály barvy nebo kombinace barev. Zbytek zůstává. Takže musí být o něco
# větší, aby to bylo čitelné." Proto 1,05: do prumeru 16 px se vejdou dve pismena.
# Nese si ji poutnik (ne rozvrzeni), takze se zvetsi i jeho prstenec (= HP bar) -
# vetsi vnitrni padding z `RING_FRAC` zustava. Hlida to `test_layout`
# (`_test_pilgrim_stays_readable`).
const PILGRIM_SIZE := 1.05
# POSKOZENI LASERU (za sekundu) JE PARAMETR HRACE ("Ještě musíme přidat upgrade
# pro Attack damage", Jan Oct 2026) - hledej `laser_dps()` v sekci PARAMETRY.
# JED A LED: jak dlouho ucinek drzi. Podil (20/35/50 %) je v tabulce upgradu.
const POISON_S := 3.0
# JAK DLOUHO DRZI CHLAD. Jan (Oct 2026): "Chill effect by měl trvat třeba 3s po
# ukončení dmg." Je to i doba, po kterou je poutnik ZPOMALENY - stav je jeden
# (`ice_left`), takze se nerozejde to, co hrac vidi, od toho, co se deje.
const ICE_S := 3.0
# ODRAZ: jak daleko od sebe mohou byt dva poutnici, aby paprsek preskocil.
# Na kazdeho se v jednom paprsku dostane nejvyce jednou (Jan: "vždy jen jeden
# odraz za každého unikátního nepřítele").
const ODRAZ_RANGE_FRAC := 0.55
# STRAZCE (turret). Male puntiky stojici na okraji veze. Je to DRUHA ZBRAN:
# kazdy strili na nejblizsiho poutnika BEZ OHLEDU NA BARVU, takze je to pojistka
# pro hrace, ktery nestiha prepinat. Barvu necte vubec (`Game._turret`), takze
# ji nemuze ovlivnit ani paleta, ani michani.
#
# JSOU AZ TRI A STOJI V TROJUHELNIKU (Jan, Oct 2026): "se budou dát dokoupit
# další dva strážci. Každý bude mít jinou pozici na věži. Budou rozmístěný do
# trojúhelníku. Budou to malé puntíky a z nich bude vycházet paprsek."
# Uhly jsou 120 stupnu od sebe (rovnostranny trojuhelnik) a prvni stoji NAHORU,
# aby ho hrac nasel na stejnem miste, kam se diva nejvic.
const TURRET_ANGLES := [-PI * 0.5, PI / 6.0, PI * 5.0 / 6.0]
# Vzdalenost od stredu veze = nasobek `tower_r` (1,85 = tesne za zivotnim
# obloukem veze, ktery konci na 1,34 r).
const TURRET_DIST := 1.85
# Polomer puntiku = nasobek `tower_r`. MUSI zustat MALY: strazce je doplnek,
# ne druha vez (Jan: "Budou to malé puntíky").
const TURRET_BODY := 0.26
# POSKOZENI JEDNOHO STRAZCE = podil ZAKLADNIHO poskozeni veze (`laser_base`).
# Kazdy strazce ma sve cislo nezavisle na tom, kolik jich je - tri strazci tedy
# daji 3 x 30 % zakladu. Kdo chce, aby se poskozeni s poctem nedelilo, meni
# TADY (a nic jineho).
const TURRET_DPS_FRAC := 0.30

# ------------------------------------------------------------------ ROZVRZENI

var field_r: float = 300.0
var unit_r: float = 300.0
var tower_r: float = 30.0
var center: Vector2 = Vector2.ZERO

# ------------------------------------------------------------------- STAV HRY

var profile: Profile = Profile.new()
var tower: Tower = Tower.new()
# PALETA HRACE = barvy, ktere hrac muze zvolit. Je to vlastnost HRY (ne veze),
# protoze z ni obrazovka kresli tlacitka dole; vez si ji jen prevzima
# (`tower.palette = palette` v `refresh_palette`).
# POZOR: `game_view` ji cte na peti mistech. Kdyz tu chybi, GDScript to ohlasí
# jen do logu ("Invalid get index 'palette'"), tlacitka se nedokresli a hrac
# nemuze prenastavit barvu - cela mechanika hry zmizi a testy pritom projdou.
var palette: Array = []

# LEVEL = sada vln; WAVE = kolikata vlna v tomto levelu.
var level: int = 1
var wave: int = 1
# DOCASNE KROKY TOHOTO LEVELU: id -> kolik kroku hrac koupil. Na kazdem levelu
# se zacina s prazdnym slovnikem - presne to je "kupuje se znovu od nuly".
var temp: Dictionary = {}
var gold: int = 0
var hp: float = 100.0
var max_hp: float = 100.0
# KOLIK BODU DAL POSLEDNI VYHRANY LEVEL (kresli se v dialogu).
var body_earned: int = 0
# "build" (priprava) / "wave" (vstupy) / "won" (level vyhran) / "lost" (konec)
var phase: String = "build"
var build_left: float = BUILD_TIME
var spawn_left: float = 0.0
# PORADI VSTUPU (barvy, jak opravdu vstupuji na plochu). POZOR: NENI to poradi
# dorazu - viz `wave_spawn_order`. Kdo kresli "co prijde", at se ptá tady.
var plan: Array = []
# UROVEN (TIER) JEDNOTLIVYCH POUTNIKU VLNY - stejny index jako `plan`. Drzi se
# ZVLAST, aby `plan` zustal jen seznam barev (ctou ho obrazovka i testy) a aby
# se uroven nemusela pocitat znovu na kazdem miste zvlast.
var plan_tier: Array = []
# CAS VSTUPU JEDNOTLIVYCH POUTNIKU VLNY (sekundy od zacatku vlny), stejne
# dlouhe jako `plan`. Driv tu byl jen jeden odpočet a pevna mezera - s ni se
# barvy rozpadly na dve skupiny (zluti u veze o deset vterin driv nez cerveni).
var spawn_at: Array = []
# KOLIK SEKUND UZ VLNA VSTUPUJE (`step` ho posouva jen ve fazi "wave").
var wave_clock: float = 0.0
var spawned: int = 0
# KTERY POUTNIK VLNY JE BOSS (-1 = zadny). Boss se rodi z poutnika te vlny,
# takze nese jeji barvu - jen je vetsi, tvrdsi a pomalejsi.
var boss_at: int = -1
var log: Array = []
# PAUZA HRY. Drzi ji obrazovka (panel upgradu, dotaz pri odchodu) - hra sama
# jen vi, ze stoji, a `step` opravdu nekrokuje.
var paused: bool = false

# HERNI HODINY: bezi, kdykoli bezi krok hry (`step`). Meri se jimi DVA PRSTY na
# palete - kdyby se meril hodinami systemu, testy by nebyly deterministicke.
var clock: float = 0.0
# PRSTY NA PALETE: index prstu -> barva pod nim a herni cas, kdy dosedl. Z toho
# se pozna "dva prsty zaraz" - viz `finger_down`. Drzi se ve HRE (ne na
# obrazovce), aby se michani dalo testovat bez prohlizece.
var finger_hue: Dictionary = {}
var finger_at: Dictionary = {}

var pilgrims: Array = []
# ZAMERENE CILE (multishot): vez jich drzi tolik, kolik ma koupeno.
var locks: Array = []
# PAPRSKY PRO OBRAZOVKU: [{from, target, hop}]. Hra je pocita kazdy snimek
# znovu (cile se hybou), obrazovka z nich jen kresli - nic si nepocita sama.
var beams: Array = []
# STRELY POUTNIKU NA VEZ (fialova, B_RANGED): [{from, pos, to, t, dur, dmg, hue}].
# Poskozeni se NEDELA pri vystrelu, ale az pri dopadu (`t >= dur`) - Jan: strela
# leti a hrac ji vidi. Nekresli se z `beams` (ty patri vezi).
var enemy_shots: Array = []
# STRAZCE (turret, special "tw"): jejich paprsky a cile. Paprsku je tolik, kolik
# je strazcu (0-3) - kazdy {from, to, target, guard}, takze si obrazovka nic
# nepocita sama. `turret_locks` je pole cilu po strazcich; drzi se, dokud je
# poutnik zivy a v dostrelu, aby paprsek nekmital mezi dvema stejne blizkymi.
var turret_beams: Array = []
var turret_locks: Array = []
# KOLIK PAPRSKU SE ZA CELOU BITVU ROZSVITILO. Neni to kosmetika: je to jedine
# merko toho, ze vez opravdu "vystrelila" (kadence uz neexistuje).
var beams_lit: int = 0
# KRITICKY ZASAH JAKO ZABLESK. U spojiteho paprsku se neda losovat kazdy
# snimek - hrac by videl skakat cisla, ktera nikde nejsou. Sance se proto
# prevede na PODIL CASU: paprsek blika ostrym svetlem kratce po sobe
# (`CRIT_FLASH_S`) a behem zabliknuti bere `crit_dmg()` nasobek. Stredni
# poskozeni je presne stejne jako driv (`laser_dps()`), ale hrac ho VIDI -
# a kdyz si koupi vetsi sanci, blika to casteji, ne "vic do prazdna".
const CRIT_FLASH_S := 0.22
# Kolik jeste bude zablesk svitit / kolik se ma cekat na dalsi.
var crit_left: float = 0.0
var crit_wait: float = 0.0
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 20261014
	refresh_palette()


func set_field(r: float, u: float, c: Vector2) -> void:
	field_r = maxf(r, 1.0)
	unit_r = maxf(u, 1.0)
	tower_r = unit_r * 0.12
	center = c


# --------------------------------------------------------------- PARAMETRY

# HODNOTA PARAMETRU. Hra, obrazovka i testy se ptaji TOHOHLE - nikdo si ji
# nepocita sam, jinak by ukazoval neco jineho, nez co hra opravdu pouziva.
func val(id: String) -> float:
	return Upgrades.value_of(id, profile.perm_level(id), int(temp.get(id, 0)))


func temp_level(id: String) -> int:
	return int(temp.get(id, 0))


# ZRYCHLENI HRY (specialni permanentni upgrade "gs"). Upgrade je KLIC, ne
# hodnota: hra zacina VZDY na 1,0x a hrac si tempo prepina v bitve tlacitkem v
# pruhu (Jan, Oct 2026: "Výchozí vždy 1.0x. Upgrade jen otevírá možnost to
# přepínat."). Kdo si special nekoupil, nema co prepinat - tlacitko v pruhu
# vubec neni (`speed_options() == 1`).
var speed_step: int = 0


# KOLIK POLOH TEMPA MA HRAC ODEMCENYCH (1 = jen zakladni 1,0x).
func speed_options() -> int:
	return 1 + profile.perm_level("gs")


# PRAVE ZVOLENE TEMPO. Nikdy neni vyssi, nez co ma hrac koupene.
func time_scale() -> float:
	return Upgrades.speed_at(mini(speed_step, speed_options() - 1))


# PREPNUTI TEMPA (tlacitko v pruhu). Vraci true, kdyz se neco zmenilo -
# obrazovka se na to ptá, ne na to, "co se asi stalo".
func cycle_speed() -> bool:
	var n: int = speed_options()
	if n <= 1:
		return false
	speed_step = (speed_step + 1) % n
	# HLASKA: hrac ma videt, co si prave zapnul. Cislo je i na tlacitku, ale
	# hlaska rekne, ze se zmenil CAS CELE HRY (pohyb, kadence, vsechno).
	_note("Tempo hry: %s." % Upgrades.value_text("gs", speed_step, 0))
	return true


func range_frac() -> float:
	return val("ar")


# POSKOZENI LASERU ZA SEKUNDU. Zaklad 10 je v `Upgrades.STATS` pod id "ad" -
# zadna druha konstanta, ktera by o upgradu nevedela.
#
# JSOU TO TRI OSY, KAZDA Z TABULKY UPGRADU:
#   * "ad" - pevne poskozeni (start + krok za kazdou koupenou uroven),
#   * "ap" - SÍLA PAPRSKU, nasobici osa (1,0x - a v bitve za zlato dal),
#   * kritika - nasobic prumeru.
#
# KRITIKA SE ROZPOCITAVA DO PRUMERU: u plynuleho paprsku nema smysl losovat
# kazdy snimek (a hrac by videl skakat cisla, ktera nikde nejsou). Stredni
# hodnota je stejna, jako kdyby se losovalo: dps * (1 + sance * (nasobek - 1)).
# TO CISLO JE "CO HRAC DOSTANE V PRUMERU" - okamzity vykon behem zablesku je
# `laser_now_dps()` a obrazovka ho kresli svetlejsim paprskem.
func laser_base() -> float:
	return maxf(1.0, val("ad")) * maxf(0.05, val("ap"))


func laser_dps() -> float:
	return laser_base() * (1.0 + crit_chance() * (crit_dmg() - 1.0))


# SVITI PRAVE TED ZABLESK KRITIKY?
func crit_active() -> bool:
	return crit_left > 0.0


# OKAMZITY VYKON PAPRSKU (behem zablesku nasobek kritiky). Hra ubira TOHLE,
# obrazovka to i tak kresli - kdyby hra brala prumer a obrazek ukazoval
# zablesk, hrac by videl neco jineho, nez co se deje.
func laser_now_dps() -> float:
	return laser_base() * (crit_dmg() if crit_active() else 1.0)


# ZABLESK KRITIKY. Sance na krit = podil casu, kdy paprsek sviti ostře:
# zablesk trva `CRIT_FLASH_S` a pauza mezi zablesky je `CRIT_FLASH_S * (1-sance)/sance`.
# Soucet je porad presne 1 - proto se stredni poskozeni nezmeni, jen je videt.
# Sance >= 1 znamena, ze paprsek sviti ostře porad (a dalsi kroky uz nic nepridaji).
func _tick_crit(dt: float) -> void:
	var cc: float = clampf(crit_chance(), 0.0, 1.0)
	if cc <= 0.0:
		crit_left = 0.0
		crit_wait = 0.0
		return
	if crit_left > 0.0:
		crit_left = maxf(0.0, crit_left - dt)
		if crit_left <= 0.0:
			crit_wait = CRIT_FLASH_S * (1.0 - cc) / cc
		return
	crit_wait = maxf(0.0, crit_wait - dt)
	if crit_wait <= 0.0:
		crit_left = CRIT_FLASH_S


# ODRAZ: kolik skoku paprsek udela a kolik si kazdy jeste odnese. Obe cisla
# jsou v JEDNE polozce tabulky (`Upgrades.chain_of`), aby se nedala koupit
# polovina upgradu.
func odraz() -> int:
	return int(round(_chain_pair().x))


func odraz_strength() -> float:
	return clampf(_chain_pair().y, 0.0, 1.0)


func _chain_pair() -> Vector2:
	return Upgrades.chain_of("rc", profile.perm_level("rc"), int(temp.get("rc", 0)))


func range_px() -> float:
	return range_frac() * field_r


# KDE SE ZASTAVI FIALOVA (B_RANGED). Je to VYCHOZI dostrel hrace, ne aktualni:
# hrac bez upgradu dostrelu na ni musi dosahnout, a kdo si dostrel koupil, ma ji
# jeste bliz. Necte se z `range_px()` - jinak by kazdy upgrade odsunul cil dal.
func ranged_stop_px() -> float:
	return float(Upgrades.stat("ar")["start"]) * field_r


func targets() -> int:
	return int(round(val("ms")))


func crit_chance() -> float:
	return val("cc")


func crit_dmg() -> float:
	return val("cd")


func armor() -> float:
	return clampf(val("am"), 0.0, 0.9)


func regen() -> float:
	return val("rg")


func ricochet() -> int:
	return int(round(val("rc")))


func poison_frac() -> float:
	return val("ps")


func ice_frac() -> float:
	return val("ic")


func pilgrim_speed() -> float:
	return maxf(0.001, (field_r - tower_r) / TRAVEL_S)


# --------------------------------------------------------------- STRAZCE (turret)
#
# Jan (Oct 2026): "byl by to takový malý turret, který by způsoboval třeba jen
# 30% poškození, ale útočil by automaticky vždy na nejbližšího nepřítele,
# nehledě na barvu ... Byla by to taková ta pojistka když hráč nestíhá."
#
# JE TO SPECIAL ("tw"), takze se kupuje JEN v menu za body a na kazdem levelu
# plati od zacatku. `temp_max` 0 znamena, ze se v bitve nekupuje - strazce neni
# dalsi cislo v zebricku, je to druha zbran.
#
# STUPEN = POCET STRAZCU (0-3), ne poskozeni. Kazdy strazce bere porad stejny
# podil zakladu (`TURRET_DPS_FRAC`).
func turret_count() -> int:
	return clampi(int(round(val("tw"))), 0, Upgrades.perm_max("tw"))


func turret_active() -> bool:
	return turret_count() > 0


# POSKOZENI JEDNOHO STRAZCE ZA SEKUNDU. Jan (Oct 2026): "Strazce by mel pocitat
# poskozeni procentualne ze ZAKLADNIHO poskozeni veze. Bez multishotu a
# ricochetu."
#
# Zaklad = `laser_base()` (poskozeni x sila paprsku) - NE `laser_dps()`, ktere
# do prumeru zapocitava kritiku, a uz vubec ne multishot/odraz: ty nejsou v
# zadne jedne rane, ale v tom, ze jich vez vede vic najednou. Strazce vede
# jednu zbran na jeden cil, takze se o ne neopira. Diky tomu zustava pojistkou:
# kdo investuje do sireni paprsku, dostane odmenu jen z miry, ne z automaticky
# mireneho strazce.
func turret_dps() -> float:
	return laser_base() * TURRET_DPS_FRAC


# KDE STRAZCI STOJI: rovnostranny trojuhelnik kolem veze, mimo jeji zivotni
# oblouk. Prvni je nahore, dalsi dva vpravo-dolu a vlevo-dolu (120 stupnu).
# Vraci presne tolik pozic, kolik je koupeno strazcu.
func turret_positions() -> Array:
	var out: Array = []
	var n: int = turret_count()
	for i in range(n):
		var a: float = float(TURRET_ANGLES[i % TURRET_ANGLES.size()])
		out.append(center + Vector2(cos(a), sin(a)) * tower_r * TURRET_DIST)
	return out


func turret_radius() -> float:
	return tower_r * TURRET_BODY


# ------------------------------------------------------------------ LEVELY

# KOLO = poradi vlny pres cely pruchod hrou (pocita se po peti vlnach na level).
func kolo() -> int:
	return KOLO_PER_LEVEL * (level - 1) + wave


func waves_in_level() -> int:
	return WAVES_PER_LEVEL


# VELIKOST VLNY. Bere se z VLNY V LEVELU (patnact az padesat poutniku v prvnim
# levelu) a kazdy dalsi LEVEL ji NASOBI - viz `WAVE_SIZE_PER_LEVEL`. Strop drzi
# nekonecnou partii hratelnou.
func wave_size(w: int, lv: int) -> int:
	var base: int = int(WAVE_SIZES[clampi(w, 1, WAVE_SIZES.size()) - 1])
	var grown: float = float(base) * pow(WAVE_SIZE_PER_LEVEL, float(maxi(0, lv - 1)))
	return clampi(int(round(grown)), 1, WAVE_SIZES_MAX)


func is_over() -> bool:
	return phase == "won" or phase == "lost"


# NOVY LEVEL. Zlato zacina znovu (jen se zakladnim bonusem), docasne kroky se
# smazou - presne to je smysl "v kazdem kole se kupuje od znovu".
func start_level(n: int) -> void:
	level = maxi(1, n)
	wave = 1
	temp = {}
	phase = "build"
	build_left = BUILD_TIME
	body_earned = 0
	pilgrims = []
	locks = []
	beams = []
	enemy_shots = []
	turret_beams = []
	turret_locks = []
	beams_lit = 0
	crit_left = 0.0
	crit_wait = 0.0
	# TEMPO ZACINA VZDY NA 1,0x (Jan, Oct 2026: "Výchozí vždy 1.0x."). Upgrade
	# jen otevira moznost si ho v bitve prepnout - hrac si ma kazdou partii
	# zvolit, jak rychle ji chce hrat.
	speed_step = 0
	max_hp = val("hp")
	hp = max_hp
	gold = int(round(float(START_GOLD) * gold_mult())) + int(round(val("gl")))
	plan = []
	plan_tier = []
	spawn_at = []
	spawned = 0
	wave_clock = 0.0
	refresh_palette()
	_note("Level %d — %d vln." % [level, waves_in_level()])


# VYHRANY LEVEL: body za level, odemkne se dalsi. Hra dal nekrokuje, dokud se
# hrac nerozhodne (`next_level` / obrazovka do menu).
#
# BODY SE DAVAJI JEN ZA NOVY LEVEL (Jan, Oct 2026: "Abych se mohl vrátit i k
# hotovým."). Kdo si vyhrany level zahraje znovu, nedostane nic - jinak by
# stacilo opakovat prvni level a body by se jen sypaly.
func _level_won() -> void:
	phase = "won"
	var first: bool = level > profile.best
	# `body_earned` uz nese body za odrazene vlny (`BODY_PER_WAVE`) - pricitá se
	# k nim odmena za level, aby dialog rekl CELY zisk teto partie.
	if first:
		var bonus: int = BODY_BASE + BODY_PER_LEVEL * level
		body_earned += bonus
		profile.add_body(bonus)
	profile.clear_level(level)
	if first:
		_note("Level %d vyhrán — %d bodů do menu." % [level, body_earned])
	else:
		_note("Level %d vyhrán znovu — body se dávají jen za nový level." % level)


func next_level() -> void:
	if phase != "won":
		return
	start_level(level + 1)


func _lose() -> void:
	phase = "lost"
	hp = 0.0
	_note("Konec — věž padla na levelu %d." % level)


# ---------------------------------------------------------------- UPGRADY

# DOCASNY KROK ZA ZLATO (kupuje se kazdy level znovu). Vraci true, kdyz se
# opravdu koupil - obrazovka se na to ptá, ne na to, "co se asi stalo".
# DOCASNE KROKY NEJSOU SHORA OMEZENE (Jan, Oct 2026): jedinym stropem je zlato
# hrace, proto se ptáme na cenu, ne na "kolik jich jeste zbývá".
func buy_temp(id: String) -> bool:
	var have: int = temp_level(id)
	if Upgrades.temp_is_maxed(id, have):
		return false
	var cost: int = Upgrades.temp_cost(id, have)
	if gold < cost:
		return false
	gold -= cost
	temp[id] = have + 1
	_after_hp_change()
	_note("%s %s (dočasně %d) za %d zlata."
		% [Upgrades.label_of(id), Upgrades.value_text(id, profile.perm_level(id), have + 1),
			have + 1, cost])
	return true


# PERMANENTNI STUPEN ZA BODY (kupuje se v menu, plati se z profilu).
func buy_perm(id: String) -> bool:
	if not profile.buy_perm(id):
		return false
	_after_hp_change()
	_note("%s na %d. permanentním stupni."
		% [Upgrades.label_of(id), profile.perm_level(id)])
	return true


# ZIVOTY SE MUSI PREPOCITAT HNAD: kdyz hrac koupi zivoty, ma je dostat i ted
# (a ne az v dalsim levelu) - jinak by tlacitko "zaplat a nic se nestalo"
# vypadalo rozbite.
func _after_hp_change() -> void:
	var new_max: float = val("hp")
	if new_max > max_hp:
		hp += new_max - max_hp
	max_hp = new_max
	hp = clampf(hp, 0.0, max_hp)


# ------------------------------------------------------------------ PAUZA

# Pauza je stav HRY, ne obrazovky: krok se ji ptá (`step`), takze ji nemuze
# obejit nikdo, kdo hru rozjede. Obrazovka ji jen prepina a pod pauzou
# nenecha desku reagovat.
func toggle_pause() -> void:
	paused = not paused


func is_paused() -> bool:
	return paused


# ------------------------------------------------------------------ KROK HRY

func step(dt: float) -> void:
	if is_over() or paused:
		return
	# HERNI HODINY. Bezi JEN v kroku hry (ne kdyz je pauza nebo konec), takze se
	# dvojtap meri hernim casem - testy pak zustavaji deterministicke.
	clock += dt
	# ZRYCHLENI HRY: nasobi se CELY krok, takze se zrychli vsechno, co je na
	# case (pohyb, kadence, let strely, jed, led, regenerace, casy vln).
	dt *= time_scale()
	_phase_step(dt)
	_regen(dt)
	_move(dt)
	_enemy_shots(dt)
	_aim()
	_tick_crit(dt)
	_laser(dt)
	_turret(dt)
	_advance_effects(dt)
	_prune()


# POSUNOUT JEN HODINY. Pro testy michani dvema prsty: hrac v pauze (nebo v
# testu) potrebuje nechat cas bezet, aby druhy prst uz nebyl "zaraz".
func tick(dt: float) -> void:
	clock += dt


func _phase_step(dt: float) -> void:
	if phase == "build":
		build_left -= dt
		if build_left <= 0.0:
			_start_wave()
		return
	if phase != "wave":
		return
	wave_clock += dt
	if spawned < plan.size():
		spawn_left -= dt
		if spawn_left <= 0.0:
			_spawn_next()
			# DALSI POUTNIK VSTOUPI V CAS, KTERY RIKA PLAN VLNY - ne za pevnou
			# mezeru. Kdyz mel vstoupit uz driv (rychla barva se drzi zpet),
			# je odpočet nula a vstoupi hned v dalsim snimku.
			if spawned < plan.size():
				spawn_left = maxf(0.0, float(spawn_at[spawned]) - wave_clock)
	elif pilgrims.is_empty():
		_wave_clear()


# MEZERA MEZI VSTUPY = VSTUPNI OKNO / (N-1). Okno je nasobek rozdilu casu cesty
# nejrychlejsi a nejpomalejsi barvy vlny - je to presne to, co rozhoduje
# o tom, jestli se barvy u veze budou mijet.
func wave_gap(arrivals: Array) -> float:
	var n: int = arrivals.size()
	if n < 2:
		return SPAWN_WINDOW_MIN
	var lo: float = 1.0e9
	var hi: float = -1.0
	for h in arrivals:
		var t: float = travel_time(int(h))
		lo = minf(lo, t)
		hi = maxf(hi, t)
	var window: float = clampf((hi - lo) * SPAWN_SPREAD, SPAWN_WINDOW_MIN, SPAWN_WINDOW_MAX)
	# BOSS VLNA: VSTUPNI OKNO JE ASPON TAK DLOUHE, JAK DLOUHO JDE BOSS K VEZI.
	# Boss vyrazi PRVNI a je petkrat pomalejsi - kdyby vlna vstupovala krátce,
	# prisel by k vezi sam (Jan, Oct 2026: "Ve chvíli, kdy boss dochází k věži,
	# ještě musí zabývat nějací nepřátelé."). Kdyz vlna vstupuje prave tak
	# dlouho, jako boss jde, vstupuje posledni poutnik ve chvili, kdy boss
	# dorazi, a cely bossuv pochod je obklopen proudem nepritel.
	#
	# Pocita se z BOSSOVY CESTY, ne opsanym cislem: kdo zrychli bosse, zkrati
	# tim i okno jeho vlny (a naopak). `wave > 0` je pojistka - `boss_wave(0)`
	# by jinak platilo a hra bez vlny by dostala bossovsky strop.
	if wave > 0 and boss_wave(wave):
		window = maxf(window, TRAVEL_S / BOSS_SPEED_MULT)
	return maxf(SPAWN_GAP_MIN, window / float(n - 1))


# JAK DLOUHO JDE POUTNIK OD OKRAJE, NEZ SE OBJEVI V DOSTRELU (sekundy).
# NENI to cesta az k vezi: hrac prepina barvu ve chvili, kdy barvu v dostrelu
# vidi - a prave tenhle cas rozhoduje o michani. Vzdalenost i rychlost se berou
# z rozvrzeni (`field_r`, `range_px`, `pilgrim_speed`), takze cislo sedi na
# kazdem displeji a meni se i s koupenym dostrelem (ten je permanentni a hra se
# tim sama prekompenzuje).
func travel_time(h: int) -> float:
	var ring: float = pilgrim_r() * PILGRIM_SIZE * RING_FRAC
	var d: float = maxf(1.0, field_r - range_px() - ring)
	return d / maxf(0.001, pilgrim_speed() * Hue.speed_mult(h))


# KDY KDO VSTOUPI. Plan vlny je PORADI VSTUPU (nahodne promichane barvy, viz
# `wave_plan`) a vstupuji v nem po celou dobu vstupniho okna (`wave_gap`).
#
# Jan (Oct 2026): "Nemá smysl, aby došli ve stejnou chvíli. Ta hra potřebuje,
# aby chodili různě. Náhodně. Aby hráč neustále musel hlídat barvu a průběžně
# přepínat." - proto se tu casy NEPOCITAJI zpetne z dorazu (to byla prvni verze
# opravy a Jan ji zamitl). Rychle barvy vstupuji driv a k vezi dojdou driv; to
# je v poradku - dulezite je, ze se OBE BARVY MIJEJI U VEZE CELY CAS, protoze
# vlna vstupuje dele, nez je rozdil jejich rychlosti.
#
# CO SE NEMENI: rychlosti (`Hue.speed_mult`), pocty ani poskozeni. Meni se jen
# to, KDY ktera barva vstoupi.
func wave_spawn_order(arrivals: Array) -> Array:
	var out: Array = []
	if arrivals.is_empty():
		return out
	var gap: float = wave_gap(arrivals)
	for i in range(arrivals.size()):
		out.append({"h": int(arrivals[i]), "at": float(i) * gap, "i": i})
	return out


func _start_wave() -> void:
	# PORADI DORAZU a casy vstupu. `plan` je pak PORADI VSTUPU - obrazovka
	# i testy se ptaji jeho, takze se nikde nesmi predpokladat, ze prvni
	# vstupujici je i prvni u veze.
	var arrivals: Array = wave_plan(wave)
	plan = []
	spawn_at = []
	for it in wave_spawn_order(arrivals):
		plan.append(int(it["h"]))
		spawn_at.append(float(it["at"]))
	# UROVNE POUTNIKU VLNY: stejny index jako `plan`, takze barva i uroven
	# patri jednomu poutnikovi od vstupu az do smrti.
	plan_tier = roll_tiers(plan.size())
	spawned = 0
	spawn_left = 0.0
	wave_clock = 0.0
	phase = "wave"
	# BOSS SE OJEVI UPROSTRED VLNY (The Tower: na nizsich tierech v pevnem
	# bode vlny) - takze hrac nejdriv neco postrili a pak prijde boss.
	boss_at = -1
	if boss_wave(wave):
		boss_at = int(round(float(plan.size()) * BOSS_SPAWN_FRAC))
	# BOSS JE "UROVEN SAMA PRO SEBE" (Jan, Oct 2026) - nema tedy uroven barvy:
	# kdyby mel tier 4, byl by z 20x zivotu 58x a hrac by na nej nemel sanci.
	if boss_at >= 0 and boss_at < plan_tier.size():
		plan_tier[boss_at] = 0
	if boss_at >= 0:
		_note("Level %d · vlna %d/%d — BOSS a %d poutníků."
			% [level, wave, waves_in_level(), plan.size()])
	else:
		_note("Level %d · vlna %d/%d — %d poutníků."
			% [level, wave, waves_in_level(), plan.size()])
	_announce_new_enemies()


# KONEC VLNY. Kdyz to byla posledni vlna levelu, level je vyhrany - a to je
# jedine misto, kde hrac dostane body.
func _wave_clear() -> void:
	gold += gold_income(float(WAVE_BONUS + WAVE_BONUS_PER_WAVE * wave) * gold_mult()) + int(round(val("gw")))
	_note("Vlna %d odražena." % wave)
	# BODY PRUBEZNE, ne az na konci levelu - viz `BODY_PER_WAVE`.
	if level > profile.best:
		profile.add_body(BODY_PER_WAVE)
		body_earned += BODY_PER_WAVE
	if wave >= waves_in_level():
		_level_won()
		return
	wave += 1
	phase = "build"
	build_left = BUILD_TIME
	refresh_palette()


# BARVY, KTERE NEJSOU V PALETE, SE OHLASTI ZVLAST: hrac je nemuze zvolit, takze
# by jen videl, ze "neco" jde po plose a neslo to zabit.
func _announce_new_enemies() -> void:
	# NOVA UROVEN BARVY: je to zmena pravidel (vetsi a tvrdsi poutnici te same
	# barvy), takze se hlasi stejne jako nova barva - ticha zmena by nechala
	# hrace hledat, proc mu neco umira pomaleji.
	if level > 1 and Hue.tier_unlocked(level) > Hue.tier_unlocked(level - 1):
		var tier: int = Hue.tier_unlocked(level) - 1
		_note("Objevují se %s poutníci — mají víc životů a padá z nich víc zlata."
			% Hue.tier_name(tier))
	var prev: Array = Hue.active_at(level - 1)
	for h in Hue.active_at(level):
		if prev.has(h) or Hue.in_palette(h):
			continue
		_note("Na ploše se objeví %s. %s" % [Hue.name_of(h), _behaviour_hint(h)])


func _behaviour_hint(h: int) -> String:
	match Hue.behaviour_of(h):
		Hue.B_SPLIT:
			return "Po zabití se rozpadne na dva menší kusy."
		Hue.B_REGEN:
			return "Obnovuje si životy — musíš ho stihnout dřív."
		Hue.B_RANGED:
			return "Zastaví se kousek od věže a odtud na ni střílí."
		Hue.B_SHIFT:
			return "Mění každých pět vteřin podobu — bere si schopnost, rychlost i životy té barvy. Na stříbrnou se už nevrátí."
	return ""


# PALETA HRACE. Bere se z LEVELU, ne z kola: "Co level, to nová barva" (Jan,
# Oct 2026). Kdyz se paleta rozsiri, hra to rekne: nova barva znamena nove
# pravidlo a ticha zmena by nechala hrace hledat, proc se neco deje jinak.
func refresh_palette() -> void:
	var before: int = palette.size()
	palette = Hue.palette_at(level)
	# VEZ SI PALETU BER Z HRY, ne naopak: tlacitka dole kresli `game_view` z
	# `game.palette`, takze kdyby si vez drzela vlastni kopii, hrac by videl
	# jednu paletu a `Tower.set_hue` by se rozhodoval podle druhe.
	tower.palette = palette
	if not palette.has(tower.hue) and not palette.is_empty():
		tower.hue = int(palette[0])
	# SMES: kdyby nekterá z obou barev z palety vypadla (nemeni se to, ale kdo
	# bude menit pravidla odemykani, at to nerozbije), vez zustane na te, ktera
	# v palete je - nikdy nesmi mirrit barvou, kterou hrac nema.
	if tower.hues.size() > 1:
		for h in tower.hues:
			if not palette.has(h):
				tower.hue = int(palette[0]) if not palette.is_empty() else Hue.RED
				break
	if before > 0 and palette.size() > before:
		for h in palette:
			if not Hue.palette_at(level - 1).has(h):
				_note("Přibyla barva: %s. %s" % [Hue.name_of(h), _behaviour_hint(h)])


func spawn_pool() -> Array:
	return Hue.active_at(level)


func select_hue(h: int) -> bool:
	return tower.set_hue(h)


# --------------------------------------------------------------- MICHANI BAREV
#
# Jan (Oct 2026): "Jeden klik na jednu barvu znamená reset, výběr jen jedné
# barvy a pro mixování to bude tak, že hráč klepne dvěma prsty zároveň. Na obě
# barvy zároveň."
#
# DRIV to byl DVOJTAP (dva tapy na stejnou barvu do 0,3 s). Proc uz ne: hrac
# musi druhy tap trefit do casoveho okna a prvni tap ho na chvili prebije na
# jednoduchou barvu - takze chvilku hraje barvou, kterou nechtel. U dvou prstu
# hrac drzi obe barvy pod prsty a vidi, co dela.
#
# Je to STAVOVY AUTOMAT HRY (ne obrazovky) a meri se HERNIM casem (`clock`), aby
# se dalo testovat bez prohlizece.
#
# PRVNI PRST SE PROJEVI OKAMZITE: cekat, jestli neprijde druhy, by pusobilo
# mrtve. Kdyz druhy prst dosedne do `TOUCH_MIX_S` na JINOU barvu, prvni volba se
# tim promicha. Pozdejsi druhy prst je novy vyber (jedna barva).
#
# Vraci "mix" (promichano), "single" (jedna barva) nebo "none" (barva neni
# v palete) - obrazovka si podle toho muze prehrat zvuk.
const TOUCH_MIX_S := 0.35


func finger_down(index: int, h: int) -> String:
	if not palette.has(h):
		return "none"
	# DRUHY PRST ZARAZ: hleda se prst, ktery je jeste dole, dosedl nedavno a lezi
	# na JINE barve. Kdyby se hledalo i na stejne barve, dve klepnuti na jednu
	# barvu by vyrabela smes te barvy se sebou.
	var other: int = -1
	for i in finger_hue.keys():
		if int(i) == index:
			continue
		if clock - float(finger_at[i]) > TOUCH_MIX_S:
			continue
		if int(finger_hue[i]) == h:
			continue
		other = int(i)
		break
	finger_hue[index] = h
	finger_at[index] = clock
	if other >= 0 and Hue.mix_unlocked(level) \
			and tower.set_pair(int(finger_hue[other]), h):
		_note("Barvy se míchají: %s (%s)." % [Hue.name_of(tower.mix()), Hue.letter_of(tower.mix())])
		return "mix"
	tower.set_hue(h)
	return "single"


# PRST NAHORU. Kdo prst zvedne, prestava platit jako "druhy prst zaraz" - bez
# toho by michani fungovalo i mezi dvema dotyky, ktere od sebe deli minuty.
func finger_up(index: int) -> void:
	finger_hue.erase(index)
	finger_at.erase(index)


# --------------------------------------------------------------- VSTUP POUTNIKU

# KOMBINOVANI POUTNICI. Jan: "Jejich výskyt nesmí být vysoký, jinak by to hráč
# nemohl zvládnout." Do vlny jich jde nejvyce MIX_MAX a jen kdyz uz je michani
# odemcene (a existuje smes, kterou hrac dokaze zasahnout - potrebuje na ni obe
# barvy ve vezi).
const MIX_SHARE := 0.10
const MIX_MAX := 2


# UROVNE (TIERY) JEDNOTLIVYCH POUTNIKU VLNY. Rovnako dlouhe jako `plan`, stejny
# index = stejny poutnik. Losuje se VAZENE (vyssi uroven je vzacnejsi), takze
# od 7. levelu nezmizi malí poutníci - prestali by chodit ti, na ktere ma hrac
# postavene dalsi rozhodovani.
#
# UROVEN JE VLASTNOST VSTUPU, NE VLNY: kdyby mela cely vlnu jednu uroven, hrac
# by na ni prisel jednim pohledem a hra by se zase zjednodusila.
func roll_tiers(n: int) -> Array:
	var out: Array = []
	var pool: Array = Hue.tier_pool(level)
	# JEDINA UROVEN = NENI CO LOSOVAT. A hlavne se NESMI spotřebovat nahoda:
	# kazdy zbytecny `randf()` posune cely zbytek partie (poradi barev ve vlne
	# i uhly vstupu), takze by se zmenily i prvni dva levely, na kterych se
	# menit NEMA NIC. Zmereno: bez tehle vetve hlupy hrac dohral level 1 a 2 a
	# padl az ve tretim, i kdyz uroven 2 zivoty vubec nemeni.
	if pool.size() <= 1:
		for i in range(n):
			out.append(0)
		return out
	var total: float = 0.0
	for t in pool:
		total += Hue.tier_weight(int(t), level)
	for i in range(n):
		var pick: int = int(pool[0])
		var r: float = rng.randf() * maxf(0.0001, total)
		for t in pool:
			r -= Hue.tier_weight(int(t), level)
			if r <= 0.0:
				pick = int(t)
				break
		out.append(pick)
	return out


# JE TAHLE VLNA BOSS VLNA? Kazda desata - stejne jako v The Tower ("boss waves
# every 10 waves"). Kdo zmeni tuhle funkci, meni, kolikrat za partii hrac
# potka bosse; hra i testy se ptaji TOHLE, nikdy na cislo 10.
func boss_wave(n: int) -> bool:
	return n % BOSS_EVERY_WAVES == 0


func wave_plan(n: int) -> Array:
	var total: int = wave_size(wave, level)
	var pool: Array = spawn_pool()
	var out: Array = []
	if pool.is_empty():
		return out
	for i in range(total):
		out.append(int(pool[i % pool.size()]))
	# STRIDANI PO CYKLECH. Cely plan se driv zamichal najednou (Fisher-Yates
	# pres celou vlnu), takze vedle sebe staly klidne tri stejne barvy a hrac
	# videl "zhluk zlutych". Kazdy cyklus ma od kazde barvy jednu a poradi
	# uvnitr cyklu je nahodne - barvy se stridaji a vlna se neopakuje porad
	# stejne. (Nahoda jde vlastnim rng, takze hra zustava deterministicka.)
	var step: int = maxi(1, pool.size())
	var pos: int = 0
	while pos < out.size():
		var take: int = mini(step, out.size() - pos)
		for j in range(take - 1, 0, -1):
			var k: int = rng.randi_range(0, j)
			var t: Variant = out[pos + j]
			out[pos + j] = out[pos + k]
			out[pos + k] = t
		pos += take
	# SMES MISTO JEDNODUCHE BARVY. Az PO zamichani, aby se michalo do cele vlny
	# (a aby se smes neobjevila vzdy na stejnem miste poradi).
	var mixes: Array = Hue.mix_pool_at(level)
	var used: int = 0
	for i in range(out.size()):
		if mixes.is_empty() or used >= MIX_MAX:
			break
		if rng.randf() < MIX_SHARE:
			out[i] = int(mixes[rng.randi_range(0, mixes.size() - 1)])
			used += 1
	return out


# NASOBEK ZLATA PRO TENTO LEVEL. Jedno misto, odkud se bere - kdyby si to
# kazde misto pocitalo samo, jedna cast hry by rostla a druha ne.
func gold_mult() -> float:
	return pow(GOLD_LEVEL, float(maxi(0, level - 1)))


# PRUJEM PENEZ: kazda odmena, kterou hrac ziska BEHEM levelu, jde pres tuhle
# funkci (zlato za zabiti i za vlnu). Diky tomu je snizeni prijmu JEDNO cislo
# (`GOLD_INCOME`) a neda se stat, ze by na nej jedno misto zapomnelo.
func gold_income(base: float) -> int:
	return int(round(base * GOLD_INCOME))


# ZIVOTY POUTNIKA. Obtiznost roste s levelem (a malo i s vlnou v levelu) a
# UROVEN BARVY (tier) je nasobek NAD tim - viz `Hue.TIER_HP`. Uroven se sem
# predava jako parametr (ne cte z hry), protoze ji poutnik zna uz pri vstupu
# a stribrna si ji pri zmene podoby musi nechat. VYCHOZI JE ZAKLADNI UROVEN
# (0), aby kazde volani, ktere uroven neresi, dostalo presne stara cisla.
func hp_for(k: int, wave_n: int, h: int, tier: int = 0) -> float:
	var lv: int = 1 + (k - 1) / KOLO_PER_LEVEL
	var lvl_mult: float = pow(LEVEL_HP, float(lv - 1))
	var wave_mult: float = pow(WAVE_HP, float(maxi(0, wave_n - 1)))
	return BASE_HP * lvl_mult * wave_mult * Hue.hp_mult(h) * Hue.tier_hp(tier)


# ZIVOTY BOSSE. NEZAVISI NA BARVE - a to je cely smysl.
#
# Jan (Oct 2026): "Zluty nemuze zemrit drive, nez si ho vsimnu. Ma byt veliky.
# Vyrazne jiny nez ostatni nepratele kolem." Zmereno (`tools/boss_color_probe`):
# barvy se stridaji (level 1: cervena, cervena, zluta, zluta, zluta), ale kdyz
# se zivoty nasobily barvou, mel zluty boss na 30. vlne 470 ziv. proti 1033
# cerveneho - a protoze vez se v boss vlne deli mezi bosse a poutniky, zluty
# boss umrel mezi nimi TISE, drive nez dosel k vezi. Hrac tedy videl jen
# cervene bosse a mel pocit, ze jine barvy nejsou.
#
# REFERENCI JE NEJTVRDSI BARVA (`Hue.RED`, 2,2x): boss je presne tak tvrdy jako
# dnesni cerveny boss, at ma kteroukoli barvu, takze se "boss" pozna vzdycky.
# Kdo hybe timhle cislem, hybe OBTIZNOSTI BOSS VLN U VSECH BAREV - a MUSI
# premerit `tools/balance_sim.gd`.
func boss_hp() -> float:
	return hp_for(kolo(), wave, Hue.RED, 0) * BOSS_HP_MULT


func spawn_at_angle(a: float, h: int = -1, tier: int = 0) -> Pilgrim:
	var pool: Array = spawn_pool()
	var hue: int = h
	if not Hue.is_valid(hue):
		hue = int(pool[rng.randi_range(0, maxi(0, pool.size() - 1))])
	var p := Pilgrim.new()
	p.hue = hue
	p.behaviour = Hue.behaviour_of(hue)
	p.behaviours = Hue.behaviours_of(hue)
	p.tier = tier
	# VELIKOST KRESBY (Jan: o 15 % mensi nez driv) - viz `PILGRIM_SIZE`.
	# UROVEN ji zvetsuje (druha cesta k informaci "tenhle je tvrdsi" - nezávisí
	# na barve) a rozpadly kus modre ji dale zmensi pres `Hue.SPLIT_SIZE`.
	p.size = PILGRIM_SIZE * Hue.tier_size(tier)
	p.pos = center + Vector2(cos(a), sin(a)) * field_r
	p.dir = (center - p.pos).normalized()
	p.max_hp = hp_for(kolo(), wave, hue, tier)
	p.hp = p.max_hp
	p.speed = pilgrim_speed() * Hue.speed_mult(hue)
	if p.behaviour == Hue.B_SHIFT:
		p.shift_left = Hue.SHIFT_S
	# MENICI PODSTATA JE ZVLAST (viz `Pilgrim.shifting`): `behaviour` se pri
	# zmene podoby prepisuje schopnosti nove barvy, takze "je to menic" se z nej
	# neda precist.
	p.shifting = (p.behaviour == Hue.B_SHIFT)
	# KOMBINOVANY POUTNIK: hrac musi vedet, PROC ho nedokaze zasahnout. Bez
	# poznamky by to vypadalo jako chyba hry (plan, ukol 6 krok 3).
	if Hue.is_mix(hue):
		_note("%s - potřebuješ obě barvy!" % Hue.name_of(hue))
	pilgrims.append(p)
	return p


func _spawn_next() -> void:
	var idx: int = clampi(spawned, 0, plan.size() - 1)
	var p: Pilgrim = spawn_at_angle(rng.randf() * TAU,
		int(plan[idx]), int(plan_tier[idx]))
	if spawned == boss_at:
		_make_boss(p)
	spawned += 1


# BOSS Z BEZNEHO POUTNIKA VLNY: stejna barva i chovani, jen vetsi, tvrdsi
# a pomalejsi. Dela se TADY, ne ve `spawn_at_angle` - kdyby mel boss vlastni
# vetev, casem by se ta dve mista rozešla a hrac by potkal bosse bez barvy
# nebo bez zlata te vlny.
func _make_boss(p: Pilgrim) -> void:
	p.is_boss = true
	# BOSS JE "UROVEN SAMA PRO SEBE" (Jan, Oct 2026): nema uroven barvy, proto
	# se zivoty pocitaji ZNOVU s urovni 0 (a stejne tak je nastavena uroven ve
	# `_start_wave`, aby si `plan_tier` a poutnik neodporovaly). Kdyby boss
	# zdedil uroven 4, bylo by z 20x zivotu 58x a hrac by na nej nemel sanci.
	p.tier = 0
	p.max_hp = boss_hp()
	p.hp = p.max_hp
	# RYCHLOST SE POCITA ZE ZAKLADU, NE Z POUTNIKA: kdyby se nasobila i jeji
	# barva (`p.speed` uz `Hue.speed_mult` ma), byl by cerveny boss o vic nez
	# dvojnasobne pomalejsi nez zluty a nešlo by rict, kdy dojde k vezi.
	# Doba cesty je tim pro kazdeho bosse stejna (TRAVEL_S / 0.20 = ~59 s) -
	# viz `BOSS_SPEED_MULT` a `wave_gap`.
	p.speed = pilgrim_speed() * BOSS_SPEED_MULT
	p.size *= BOSS_SIZE


# ------------------------------------------------------------------- POHYB

func _move(dt: float) -> void:
	for p in pilgrims:
		if not p.alive:
			continue
		_advance_behaviour(p, dt)
		# FIALOVA STRILEJICI Z DALKU: jakmile je na okraji vychoziho dostrelu,
		# ZASTAVI SE (dal uz nejde) a odtud strili na vez. Je to tlak, ne druhy
		# zpusob, jak dojit k vezi - hrac ji musi zabit, ne jen prezit.
		if p.has_behaviour(Hue.B_RANGED) and p.pos.distance_to(center) <= ranged_stop_px():
			p.shot_left -= dt
			if p.shot_left <= 0.0:
				p.shot_left = Hue.ranged_every(p.tier)
				_ranged_shot(p)
			continue
		p.pos += p.dir * p.speed * p.slow_mult() * dt
		if p.pos.distance_to(center) <= tower_r:
			_arrive(p)


# POUTNIK DOSEL K VEZI. Ubere tolik, kolik mu zbylo zivotu, zbroj to zkrati.
# Tohle je jedine misto, kde hrac prichazi o zivoty veze.
#
# BOSS NESMI DAT INSTANT KILL (Jan, Oct 2026): "A koukam, ze boss da vzdy
# instant kill. Pravda? To neni spravne chovani. Mel by dat slusnou slupu, ale
# ne treba 400 zivotu." Boss ma 20x zivoty (`BOSS_HP_MULT`), takze "tolik, kolik
# mu zbylo" znamenalo 400+ poskozeni do veze o 100 zivotech = vzdy konec hry.
# Proto ma STROP: nejvyse `BOSS_LEAK_FRAC` maximalnich zivotu veze. Je to podil,
# ne pevne cislo - hrac, ktery si koupil zivoty, ma z bossa porad stejne velky
# problem a strop se s jeho investici posouva. Zbytek poskozovani zustava
# stejny (`min`): boss, ktereho hrac temer zabil, ubere malo.
const BOSS_LEAK_FRAC := 0.40
func _arrive(p: Pilgrim) -> void:
	p.alive = false
	var raw: float = maxf(1.0, p.hp)
	if p.is_boss:
		raw = minf(raw, max_hp * BOSS_LEAK_FRAC)
	var dmg: float = raw * (1.0 - armor())
	hp -= dmg
	_note("%s došel k věži — %d poškození." % [Hue.name_of(p.hue), int(round(dmg))])
	if hp <= 0.0:
		_lose()


# FIALOVA STRELA Z DALKU. Stojici poutnik posle kazdych `ranged_every(tier)`
# sekund strelu na vez. STRELA LETI (`ranged_flight(tier)`) a poskozeni se
# dela az pri dopadu - hrac vidi, ze neco leti, a muze fialovou zabit driv, nez
# dorazi. Vyssi uroven = vic poskozeni, rychlejsi kadence i rychlejsi let.
func _ranged_shot(p: Pilgrim) -> void:
	enemy_shots.append({
		"from": p.pos, "pos": p.pos, "to": center,
		"t": 0.0, "dur": Hue.ranged_flight(p.tier),
		"dmg": Hue.ranged_dmg(p.tier), "hue": p.hue,
	})


# DOPAD STREL POUTNIKU. Poskozeni se pocita az tady, ne pri vystrelu; zbroj
# veze ho krati stejne jako prulom. Strela, ktera doleti po konci hry, uz nic
# neudela (`step` po konci nekrokuje, takze se sem ani nedostane).
func _enemy_shots(dt: float) -> void:
	var live: Array = []
	for s in enemy_shots:
		s["t"] = float(s["t"]) + dt
		var k: float = clampf(float(s["t"]) / maxf(0.001, float(s["dur"])), 0.0, 1.0)
		s["pos"] = (s["from"] as Vector2).lerp(s["to"] as Vector2, k)
		if k < 1.0:
			live.append(s)
			continue
		var dmg: float = float(s["dmg"]) * (1.0 - armor())
		hp -= dmg
		_event("hit")
		if hp <= 0.0:
			_lose()
	enemy_shots = live


func _regen(dt: float) -> void:
	var r: float = regen()
	if r > 0.0 and hp > 0.0:
		hp = minf(max_hp, hp + r * dt)


func _advance_behaviour(p: Pilgrim, dt: float) -> void:
	if p.has_behaviour(Hue.B_REGEN):
		p.hp = minf(p.max_hp, p.hp + p.max_hp * Hue.REGEN_FRAC * dt)
	if p.shifting:
		p.shift_left -= dt
		if p.shift_left <= 0.0:
			p.shift_left = Hue.SHIFT_S
			_shift(p)


# STRIBRNA MENI PODOBU (Jan, Oct 2026): "Nově budou měnit po 5s. A se změnou
# podoby budou přebírat i výhody jednotlivých barev. Zelená = léčení, žlutá =
# rychlost, modrá = při smrti se rozdělí, fialová = střílí z dálky, červená
# = vysoká odolnost. Měly by se měnit i životy. Hra by měla přepočítávat podle
# procentuální hodnoty."
#
# Forma se bere CELA: nova barva da poutnikovi svou schopnost, svou rychlost
# i SVUJ ZIVOTNI POOL. Zivoty se NEPRICITAJI ani neprepisuji - prenasi se
# PROCENTO: `hp_frac()` pred zmenou se nasadi na pool nove barvy. Proto ma
# stribrna v kazde podobe jinak zivotu a cervena je vzdycky ta tlustsi (2,2x).
func _shift(p: Pilgrim) -> void:
	var frac: float = p.hp_frac()
	p.hue = _random_other_hue(p.hue)
	p.behaviour = Hue.behaviour_of(p.hue)
	p.behaviours = Hue.behaviours_of(p.hue)
	p.max_hp = hp_for(kolo(), wave, p.hue, p.tier)
	p.hp = maxf(1.0, p.max_hp * frac)
	# RYCHLOST JE VYHODA ZLUTE, takze nova podoba znamena i novou chuzi.
	p.speed = pilgrim_speed() * Hue.speed_mult(p.hue)
	# CASOVAC STRELBY SE ZACINA OD NULY: nova podoba nesmi zdedit "nabito" po
	# fialove (a fialova nesmi zdedit cizi). Tyká se to i zastaveni - `_move`
	# ho pocita z polohy, ne z ulozeneho stavu, takze se nema co rozejit.
	p.shot_left = 0.0


# JED A LED SE ODPOCITAVAJI ZVLAST: plati i na poutnika, ktery uz je z dosahu
# (jed je jed) - jinak by upgrady "po zasahu" nic nedelaly. Dnes uz zadna
# neviditelna fialova neexistuje, takze `targetable()` je jen "je zivy".
func _advance_effects(dt: float) -> void:
	for p in pilgrims:
		if not p.alive:
			continue
		if p.ice_left > 0.0:
			p.ice_left = maxf(0.0, p.ice_left - dt)
		if p.poison_left > 0.0:
			p.poison_left = maxf(0.0, p.poison_left - dt)
			if p.targetable():
				_hurt(p, p.poison_dps * dt)


func _random_other_hue(cur: int) -> int:
	var pool: Array = []
	for h in spawn_pool():
		if h != cur and h != Hue.SILVER:
			pool.append(h)
	if pool.is_empty():
		return Hue.RED
	return int(pool[rng.randi_range(0, pool.size() - 1)])


# JE POUTNIK V DOSTRELU? Jan (Oct 2026): "Věž si všimne nepřítele ve chvíli,
# kdy se HP bar nepřítele dotkne rádiusu zjišťování." Proto se k dostrelu
# PRICITA polomer prstence cile (= jeho HP bar): hranici dostrelu prekroci uz
# svym okrajem, ne az stredem tela. Vetsi poutnik (boss, rozpadly kus modre)
# ma vetsi i prstenec, takze jeho okraj "dosahne" dal - a to je spravne:
# je to vetsi teleso.
func in_range(p: Pilgrim, r: float) -> bool:
	return p.pos.distance_to(center) <= r + pilgrim_ring_r(p)


# --------------------------------------------------------------- ZAMEROVANI

# ------------------------------------------------------------------ ZVUKOVE UDALOSTI
#
# HRA NEREKNE "prehraj zvuk" (nevi, jestli je vubec nejaky prehravac, a v
# testech by nic nehrala): zapisuje, CO se stalo. Obrazovka si z toho zvuky
# udela (`Game.take_events`) - a je to zaroven jedine misto, kde se da overit,
# ze vystrel opravdu vystrelil a dopad opravdu ubral.
#
# STROP: zvuk je doplnek, ne zaznam. Kdo hru kroka bez obrazovky (simulátor),
# by si jinak pamatoval tisice udalosti.
const MAX_EVENTS := 24
var events: Array = []


func _event(kind: String) -> void:
	if events.size() >= MAX_EVENTS:
		events.remove_at(0)
	events.append(kind)


# VYBRANI UDALOSTI = JEJICH SMAZANI. Kdo je precte bez vybrani, prehraje je
# znovu (a zvuk by se opakoval).
func take_events() -> Array:
	var out: Array = events
	events = []
	return out


# SVAZEK DRZI CIL, DOKUD JEJ VEZ VIDI A JE V DOSTRELU. Pocet cilu zaraz je
# upgradovatelny parametr (multishot) a KAZDY cil ma svuj paprsek (a svuj
# retez odrazu) - "vic cilu" tedy od teď znamena vic paprsku naraz.
func _aim() -> void:
	var r: float = range_px()
	var keep: Array = []
	for p in locks:
		if tower.sees(p) and in_range(p, r):
			keep.append(p)
	locks = keep
	if locks.size() < targets():
		var pool: Array = []
		for p in pilgrims:
			if tower.sees(p) and in_range(p, r) and not locks.has(p):
				pool.append(p)
		pool.sort_custom(_closer)
		while locks.size() < targets() and not pool.is_empty():
			locks.append(pool.pop_front())


# ------------------------------------------------------------------- LASER
#
# Jan (Oct 2026): "Vrátíme se k laseru místo projektilů. Tím pádem zrušíme
# úplně Attack speed upgrady. Poškození bude probíhat plynule a čím vyšší bude
# mít věž dmg, tím rychleji to logicky bude nepřítele zabíjet. Barva laseru
# bude podle barvy věže. RICOHET přejmenujeme na Odraz a bude se takhle laser
# šířit na další nepřátele, podobně jako ricochet, ale bez projektilů. A každý
# odraz bude dávat menší poškození. S levelem upgradu se bude zvyšovat počet
# odrazů a bude snižovat penalizace za odraz."
#
# Z TOHO PLYNE CELY MODEL - a je to zamerne JEDNA funkce, proto:
#   * zadny projektil, zadna kadence a zadny "swing timer": dokud vez na
#     neco vidi, paprsek sviti a `laser_dps()` tece kazdy snimek,
#   * barva paprsku je BARVA VEZE (kresli ji obrazovka z `beams`),
#   * odraz je druhy, treti... cil paprsku se snizujicim se poskozenim,
#   * "vystreleno = doleti" uz neexistuje - neni co doletovat. Paprsek proste
#     prestane svitit ve chvili, kdy cil zmizi z dostrelu nebo zustane sam
#     (`tower.sees`), a to same plati pro fialovou v duchovem stavu.
func _laser(dt: float) -> void:
	beams = []
	for p in pilgrims:
		p.burning_now = false
	var r: float = range_px()
	var dps: float = laser_now_dps()
	var strength: float = odraz_strength()
	var crit: bool = crit_active()
	for p in locks:
		if not p.alive or not tower.sees(p) or not in_range(p, r):
			continue
		var chain: Array = _chain(p)
		# PAPRSEK ZACINA NA OKRAJI VEZE (`tower_edge_r` - ne ve stredu a ne uvnitr
		# jejiho prstence) a konci na VNEJSIM PLASHTI cile (`pilgrim_ring_r` = HP
		# prstenec). Jan (Oct 2026): "Hlavni paprsek ma koncit na vnejsim plasti
		# prvniho nepritele a odraz ma zacinat opet na vnejsim plasti."
		#
		# PRES TELO SE NEKRESLI NIC. Driv tu byl jeste segment vstup-vystup, takze
		# pres poutnika vedl maly paprsek skrz stred ("uplne zbytecny mini paprsek",
		# Jan). Ted paprsek na plasti skonci a odraz z plasti (na strane k dalsimu
		# cili) zase vyjde - mezi tim je poutnik, ne cara.
		var from_pt: Vector2 = center + (chain[0].pos - center).normalized() * tower_edge_r()
		for i in range(chain.size()):
			var q: Pilgrim = chain[i]
			var rr: float = pilgrim_ring_r(q)
			var entry: Vector2 = q.pos - (q.pos - from_pt).normalized() * rr
			beams.append({"from": from_pt, "to": entry, "target": q, "hop": i,
				"crit": crit})
			_burn(q, dps * pow(strength, float(i)) * dt)
			if i + 1 < chain.size():
				var nxt: Pilgrim = chain[i + 1]
				from_pt = q.pos + (nxt.pos - q.pos).normalized() * rr
	# `burning` = svitil paprsek na tohle poutnika i v PREDCHOZIM snimku.
	# Prelozi se az tady, kdyz je hotove cely paprsek - kdyby se to delalo za
	# pochodu, zvuk zazehnuti by se ozval u kazdeho odrazu zvlast.
	for p in pilgrims:
		p.burning = p.burning_now


# STRAZCE: DRUHA ZBRAN VEDLE PAPRSKU. Jan (Oct 2026): "útocil by automaticky
# vždy na nejbližšího nepřítele, nehledě na barvu ... pojistka když hráč
# nestíhá."
#
# TADY SE BARVA NECTE VUBEC - ani `tower.sees`, ani paleta. Prave proto je to
# pojistka: hrac muze mit prebito na cervenou a strazce si vezme zlutou, ktera
# mu utika. SEDOU (stribrnou) zasahne taky - je to jedina zbran ve hre, ktera
# na ni dosahne.
#
# Poskozeni je PODIL ZAKLADU veze (`turret_dps` = `laser_base` x podil) -
# multishot a odraz do nej NEVSTUPUJI, takze ze strazce zustava pojistka a ne
# druha hlavni zbran. Jed a led nedava, je to cista rana. Cil se drzi,
# dokud je zivy a v dostrelu - jinak by paprsek kmital mezi dvema poutniky
# a hrac by nevidel, na co vlastne miri.
#
# KAZDY STRAZCE MA SVUJ CIL (Oct 2026): tri paprsky na jednoho poutnika by byly
# jen drahy zpusob, jak zvysit poskozeni jednoho cile - a hrac ma tri strazce
# prave proto, aby mu pojistka pokryla vic barev naraz. Strazce proto bere
# nejblizsiho poutnika, ktereho jeste nema JINY strazce; kdyz je v dostrelu
# min poutniku nez strazcu, dva se sejdou na stejnem (lepsi nez aby treti
# strazce stal a nic nedelal).
func _turret(dt: float) -> void:
	turret_beams = []
	var n: int = turret_count()
	if n <= 0:
		turret_locks = []
		return
	var r: float = range_px()
	# 1) DRZET STARE CILE, dokud jsou platne. Kdyby se cile pocitaly kazdy
	# snimek znovu, paprsek by pri kazdem priblizeni jineho poutnika preskocil.
	var chosen: Array = []
	for i in range(n):
		var prev: Pilgrim = null
		if i < turret_locks.size():
			prev = turret_locks[i]
		if prev != null and prev.alive and prev.targetable() and in_range(prev, r) \
				and not chosen.has(prev):
			chosen.append(prev)
		else:
			chosen.append(null)
	# 2) DOPLNIT CHYBEJICI: nejblizsi volny poutnik, jinak nejblizsi vubec.
	for i in range(n):
		if chosen[i] != null:
			continue
		var best: Pilgrim = _turret_pick(chosen, r, true)
		if best == null:
			best = _turret_pick(chosen, r, false)
		chosen[i] = best
	turret_locks = chosen
	var pos_list: Array = turret_positions()
	for i in range(n):
		var target: Pilgrim = turret_locks[i]
		if target == null or not target.alive:
			continue
		var from_pt: Vector2 = pos_list[i]
		var to_pt: Vector2 = target.pos
		var dir: Vector2 = to_pt - from_pt
		if dir.length() <= 0.001:
			continue
		dir = dir.normalized()
		# PAPRSEK VYCHAZI Z OKRAJE PUNTIKU a konci na TELI poutnika - stejna
		# pravidla jako u paprsku veze, jen mensi (strazce je mala vec).
		from_pt += dir * turret_radius()
		to_pt -= dir * pilgrim_hit_r(target)
		turret_beams.append({"from": from_pt, "to": to_pt, "target": target,
			"guard": i})
		_hurt(target, turret_dps() * dt)


# NEJBLIZSI POUTNIK V DOSTRELU PRO STRAZCE. `only_free` vynecha ty, ktere uz ma
# jiny strazce; bez nej se vraci nejblizsi vubec (fallback, kdyz je poutniku
# mene nez strazcu).
func _turret_pick(taken: Array, r: float, only_free: bool) -> Pilgrim:
	var best: Pilgrim = null
	var best_d: float = 1.0e18
	for p in pilgrims:
		if not p.alive or not p.targetable() or not in_range(p, r):
			continue
		if only_free and taken.has(p):
			continue
		var d: float = p.pos.distance_squared_to(center)
		if d < best_d:
			best_d = d
			best = p
	return best


# ODRAZ. Paprsek preskoci na nejblizsiho dalsiho poutnika, na ktereho se v tom
# samem paprsku jeste nedostalo - a to i mimo dostrel (je to odraz, ne
# zamereni). "Stejna barva" neni zvlast podminka: vez jinou barvu nevidi
# (`tower.sees`), takze by ji ani nezamirila.
func _chain(p: Pilgrim) -> Array:
	var out: Array = [p]
	var reach: float = ODRAZ_RANGE_FRAC * field_r
	var cur: Pilgrim = p
	for i in range(odraz()):
		var best: Pilgrim = null
		var best_d: float = reach
		for q in pilgrims:
			if not q.alive or not tower.sees(q) or out.has(q):
				continue
			var d: float = q.pos.distance_to(cur.pos)
			if d <= best_d:
				best_d = d
				best = q
		if best == null:
			break
		out.append(best)
		cur = best
	return out


# HORI CIL PAPRSKEM - vcetne jedn a ledu, ktere plati, dokud paprsek sviti.
# Odraz je porad zasah tou samou zbrani, takze si veze i jed (jen slabsi, proto
# `laser_dps` v sile, ne v poskozeni - jed se pocita z plne rany veze).
#
# ZADNY ZVUK "VYSTRELU" TADY NENI (Oct 2026). Paprsek neni jednorazova rana,
# ale nepretrzity svit - zvuk je proto SMYCKA v obrazovce, ktera hraje, dokud
# je `beams` neprazdny (viz `game_view._sync_laser`). Kdyby hra posilala
# udalost na kazde zazehnuti, obrazovka by musela stejne koukat na stav, a
# vznikla by druha pravda o tom, co hraje.
#
# `beams_lit` zustava: je to POCITADLO ROZSVICENI (kolikrat paprsek rozsvitil
# cil, ktery predtim nesvitil) a testy si ho ctou.
func _burn(p: Pilgrim, amount: float) -> void:
	if not p.alive or amount <= 0.0:
		return
	p.burning_now = true
	if not p.burning:
		beams_lit += 1
	if poison_frac() > 0.0:
		p.poison_left = POISON_S
		p.poison_dps = laser_dps() * poison_frac()
	if ice_frac() > 0.0:
		p.ice_left = ICE_S
		p.ice_frac = ice_frac()
	_hurt(p, amount)


# ------------------------------------------------------------------ POSKOZENI

# UBRAT ZIVOTY. Jedno misto pro kazdy zdroj poskozeni (dopad strely, jed) -
# hra se nikdy nesmi dostat pod nulu a smrt je taky jen tady.
func _hurt(p: Pilgrim, amount: float) -> void:
	if not p.alive or amount <= 0.0:
		return
	var before: float = p.hp
	p.hp -= amount
	if p.hp < before and not p.was_hit:
		p.was_hit = true
	if p.hp <= 0.0:
		_kill(p)


func _kill(p: Pilgrim) -> void:
	p.alive = false
	_event("kill")
	# BOSS PADA ZA PETINASOBNE ZLATO (The Tower: 5 coinu misto 1) - kdyby padal
	# za stejne, hrac by se bossum vyhybal a zkouska poskozeni by se nevyplatila.
	# UROVEN BARVY ZLATO ZVEDA TAKY (`Hue.TIER_GOLD`): vetsi poutnik = vic prace
	# = vic penez, jinak by byl jenom otrava navic.
	#
	# BOSS PLATI STEJNE VE VSECH BARVACH (jako jeho zivoty, viz `boss_hp`):
	# kdyby se zlato bralo z jeho barvy, bral by hrac za stejne tezky souboj
	# 2 zlata (zluty) nebo 4 (cerveny) - a to je presne ten rozdil, ktery
	# z barev dela neco, co hrac nema jak ovlivnit.
	var pay_hue: int = Hue.RED if p.is_boss else p.hue
	var mult: float = BOSS_GOLD_MULT if p.is_boss else Hue.tier_gold(p.tier)
	gold += gold_income(float(Hue.gold_of(pay_hue)) * gold_mult() * mult) \
		+ int(round(val("gk")))
	# MODRA: rozpadne se na dva mensi kusy. Hra se tim zhusti presne tam, kde
	# ma vez nejmene casu. Kusy se dal nedeli a jdou porad ROVNE k vezi.
	if p.has_behaviour(Hue.B_SPLIT) and p.can_split:
		var side: Vector2 = p.dir.rotated(PI * 0.5)
		for i in range(Hue.SPLIT_PIECES):
			var q := Pilgrim.new()
			q.hue = p.hue
			q.behaviour = Hue.B_NONE
			q.can_split = false
			# KUS JE O JEDEN STUPEN NIZ (Jan, Oct 2026: "Modří poutníci se vždy
			# budou rozpadat na dva poutníky o 1 level nižší úrovně. Modrý puntík
			# levelu 1 se pak rozpadne na dva poutníky lvl 0"). UROVEN 0 (index
			# -1) existuje JEN takhle - `tier_pool` ji nikdy nelosuje.
			q.tier = p.tier - 1
			q.size = PILGRIM_SIZE * Hue.tier_size(q.tier) * Hue.SPLIT_SIZE
			q.max_hp = maxf(1.0, p.max_hp * Hue.SPLIT_HP_FRAC)
			q.hp = q.max_hp
			q.speed = p.speed
			q.pos = p.pos + side * (pilgrim_r() * 1.6 * (float(i) * 2.0 - 1.0))
			q.dir = (center - q.pos).normalized()
			pilgrims.append(q)


func _closer(a: Pilgrim, b: Pilgrim) -> bool:
	return a.pos.distance_squared_to(center) < b.pos.distance_squared_to(center)


func _prune() -> void:
	var keep: Array = []
	for p in pilgrims:
		if p.alive:
			keep.append(p)
	pilgrims = keep


func pilgrim_r() -> float:
	return unit_r * 0.05


# POLOMER PRSTENCE. Je to ta VIDITELNA kruzna hranice kolem poutnika (kresli ji
# obrazovka) a ZAROVEN jeho HP BAR - paprsek na nem uz NEKONCI (viz nize).
# Vetsi poutnik (rozpadly kus modre) ma vetsi i prstenec.
func pilgrim_ring_r(p: Pilgrim) -> float:
	return pilgrim_r() * maxf(0.1, p.size) * RING_FRAC


# POLOMER, NA KTEREM PAPRSEK OPRAVDU KONCI = VIDITELNY OKRAJ PUNTIKA.
# Jan (Oct 2026): "Laser směřuje stále do středu nepřítele. Měl by směřovat
# spíš na jeho obal." Paprsek proto konci na TELE poutnika, ne na prstenci:
# prstenec je HP bar v 1,70 r a mezi nim a puntikem zustavala ~6 px mezera -
# cara sice mirila do stredu, ale niceho se nedotkla.
#
# 0,92 JE STEJNE CISLO, jakym obrazovka kresli telo puntika (`_dot` kresli
# `draw_circle(p, 0.92 * r, col)`) - kdyby se ta dve cisla rozešla, paprsek by
# koncil ve vzduchu nebo uvnitr tela. Hlida to `test_core`
# (`_test_odraz_beam_is_visible`) i `test_layout`.
const PILGRIM_HIT_FRAC := 0.92


func pilgrim_hit_r(p: Pilgrim) -> float:
	return pilgrim_r() * maxf(0.1, p.size) * PILGRIM_HIT_FRAC


# ODKUD PAPRSEK VYCHAZI: Z OKRAJE VEZE. Vez kresli tri kruhy (`_draw_tower`):
# telo (`tower_r`), barevny prstenec v 0,92 r a ZIVOTY ve `TOWER_ARC_R` o
# tloustce `TOWER_ARC_W` - nejvnejsi viditelna hranice je tedy
# `TOWER_ARC_R + TOWER_ARC_W / 2`. Jan (Oct 2026): "Laser od věže má začínat
# na okraji věže. Ne ve středu." Cisla jsou TU a obrazovka je odtud bere -
# kdyby si je opsala, paprsek by jednou vysel zevnitr veze.
const TOWER_ARC_R := 1.22
const TOWER_ARC_W := 0.24


func tower_edge_r() -> float:
	return tower_r * (TOWER_ARC_R + TOWER_ARC_W * 0.5)


# SIRKA PAPRSKU. S kazdym odrazem se zuzi, ale nikdy nezmizi - hrac musi
# videt i to, kam az odraz dosahl. Kresli to obrazovka, proto to hra jen
# pocita (a obrazovka si to nepocita sama).
func beam_w(hop: int) -> float:
	return unit_r * BEAM_W_FRAC * pow(BEAM_TAPER, float(maxi(0, hop)))


# ------------------------------------------------------------------ HLASKY

func _note(s: String) -> void:
	log.append(s)
	if log.size() > 40:
		log.pop_front()


func last_note() -> String:
	if log.is_empty():
		return ""
	return String(log[log.size() - 1])


# =========================================================================
# STAV BITVY (ukladani rozehrane partie, viz `BattleSave`)
# =========================================================================
#
# DVE FUNKCE, KTERE PATRI K SOBE. `to_state` a `from_state` jsou jedine misto,
# kde se stav hry meni na slovnik a zpet - obrazovka ani soubor do toho
# nesaha, takze se nerozejde to, co se uklada, od toho, co hra opravdu pouziva
# (stejna zasada jako u `Profile`).
#
# UKLADA SE VSECHNO, CO DO PRISTIHO SNIMKU VSTUPUJE: hodiny, faze, plan vlny
# i s urovnemi, rozestupy vstupu, pozice a casovace poutniku a hlavne STAV
# GENERATORU NAHODY. Bez nej by se po navratu rozjela jina partie (jina poradi
# barev, jine uhly vstupu) - hrac by se vratil do jine hry.
#
# CO SE NEUKLADA: paprsky (`beams`), zamky (`locks`), zvukove udalosti a prsty
# na palete. Vsechno to plati jen pro jeden snimek - vynechany snimek neni
# ztrata, kdezto ulozeny paprsek by se musel "doridit" a mohl by poskodit
# poutnika, ktery uz je jinde.
func to_state() -> Dictionary:
	var ps: Array = []
	for p in pilgrims:
		if not p.alive:
			continue
		ps.append({
			"hue": p.hue, "tier": p.tier, "boss": p.is_boss,
			"x": p.pos.x, "y": p.pos.y, "dx": p.dir.x, "dy": p.dir.y,
			"hp": p.hp, "max_hp": p.max_hp, "speed": p.speed, "size": p.size,
			"behaviour": p.behaviour, "behaviours": p.behaviours.duplicate(),
			"split": p.can_split, "shifting": p.shifting, "was_hit": p.was_hit,
			"shot": p.shot_left, "shift": p.shift_left,
			"poison_left": p.poison_left, "poison_dps": p.poison_dps,
			"ice_left": p.ice_left, "ice_frac": p.ice_frac,
			"burning": p.burning, "burning_now": p.burning_now,
		})
	return {
		"v": 1,
		"level": level, "wave": wave, "phase": phase,
		"build_left": build_left, "spawn_left": spawn_left,
		"gold": gold, "hp": hp, "max_hp": max_hp, "body_earned": body_earned,
		"temp": temp.duplicate(),
		"plan": plan.duplicate(), "plan_tier": plan_tier.duplicate(),
		"spawn_at": spawn_at.duplicate(),
		"wave_clock": wave_clock, "spawned": spawned, "boss_at": boss_at,
		"clock": clock, "speed_step": speed_step,
		"crit_left": crit_left, "crit_wait": crit_wait,
		"hues": tower.hues.duplicate(),
		# STAV GENERATORU NAHODY JAKO TEXT: je to 64bitove cislo a text prezije
		# kazdou cestu souborem bez ohledu na to, jak ho zapise.
		"rng_seed": str(rng.seed), "rng_state": str(rng.state),
		"log": log.slice(maxi(0, log.size() - 6), log.size()),
		"pilgrims": ps,
	}


# OBNOVIT STAV BITVY. Vraci true, kdyz se obnovilo - prazdny nebo cizi stav se
# neobnovi a hra zustane, jak byla (nikdy "napul nactena").
#
# ROZVRZENI (`field_r`, `center`) si drzi obrazovka a MUSI BYT nastavene pred
# volanim (`set_field`): polohy poutniku jsou v pixelech tehoz displeje, na
# kterem se ukladalo. Kdo obnovuje partii na jinem displeji, musi pocitat
# s tim, ze se plocha zmenila - proto se ukladaji polohy a ne "bunka v plose".
func from_state(d: Dictionary) -> bool:
	if d.is_empty() or int(d.get("v", 0)) != 1:
		return false
	level = int(d["level"])
	wave = int(d["wave"])
	phase = String(d["phase"])
	build_left = float(d["build_left"])
	spawn_left = float(d["spawn_left"])
	gold = int(d["gold"])
	hp = float(d["hp"])
	max_hp = float(d["max_hp"])
	body_earned = int(d.get("body_earned", 0))
	temp = (d.get("temp", {}) as Dictionary).duplicate()
	plan = (d.get("plan", []) as Array).duplicate()
	plan_tier = (d.get("plan_tier", []) as Array).duplicate()
	spawn_at = (d.get("spawn_at", []) as Array).duplicate()
	wave_clock = float(d.get("wave_clock", 0.0))
	spawned = int(d.get("spawned", 0))
	boss_at = int(d.get("boss_at", -1))
	clock = float(d.get("clock", 0.0))
	speed_step = int(d.get("speed_step", 0))
	crit_left = float(d.get("crit_left", 0.0))
	crit_wait = float(d.get("crit_wait", 0.0))
	# PAUZA SE NEOBNOVUJE: hrac se vraci do hry, ktera bezi. Kdyby se vratil
	# do pauzy, hral by dal s prazdnym displejem a nevedel by proc.
	paused = false
	locks = []
	beams = []
	enemy_shots = []
	turret_beams = []
	turret_locks = []
	beams_lit = 0
	events = []
	finger_hue = {}
	finger_at = {}
	# PALETA SE POCITA Z LEVELU (jedno misto, `refresh_palette`), ale BARVA
	# VEZE se bere z ulozeneho stavu - hrac si ji zvolil a nesmi o ni prijit.
	var saved_hues: Array = (d.get("hues", []) as Array).duplicate()
	refresh_palette()
	if saved_hues.size() > 0:
		var ok: bool = true
		for h in saved_hues:
			if not palette.has(int(h)):
				ok = false
		if ok:
			tower.hues = saved_hues
	rng.seed = int(String(d.get("rng_seed", "0")))
	rng.state = int(String(d.get("rng_state", "0")))
	log = (d.get("log", []) as Array).duplicate()
	pilgrims = []
	for raw in (d.get("pilgrims", []) as Array):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var q: Dictionary = raw
		var p := Pilgrim.new()
		p.hue = int(q["hue"])
		p.tier = int(q.get("tier", 0))
		p.is_boss = bool(q.get("boss", false))
		p.pos = Vector2(float(q["x"]), float(q["y"]))
		p.dir = Vector2(float(q.get("dx", 0.0)), float(q.get("dy", 1.0)))
		p.hp = float(q["hp"])
		p.max_hp = float(q["max_hp"])
		p.speed = float(q["speed"])
		p.size = float(q["size"])
		p.behaviour = String(q.get("behaviour", Hue.B_NONE))
		p.behaviours = (q.get("behaviours", [p.behaviour]) as Array).duplicate()
		p.can_split = bool(q.get("split", true))
		p.shifting = bool(q.get("shifting", false))
		p.was_hit = bool(q.get("was_hit", false))
		p.shot_left = float(q.get("shot", 0.0))
		p.shift_left = float(q.get("shift", 0.0))
		p.poison_left = float(q.get("poison_left", 0.0))
		p.poison_dps = float(q.get("poison_dps", 0.0))
		p.ice_left = float(q.get("ice_left", 0.0))
		p.ice_frac = float(q.get("ice_frac", 0.0))
		p.burning = bool(q.get("burning", false))
		p.burning_now = bool(q.get("burning_now", false))
		pilgrims.append(p)
	return true
