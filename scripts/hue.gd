class_name Hue
extends RefCounted

# SEST BAREV. "Zivel" (ohen, voda, zeme, vzduch) uz neexistuje - barva je
# jedina identita poutnika i veze a kazda barva ma SVOJE CHOVANI. Presne to
# dela z hry rozhodovani: barva sama je jen jmeno, chovani je duvod, proc ji
# zabit zrovna teď.
#
# PORADI INDEXU JE ZAVAZNE (0..5). Je to identita barvy v kodu, v palete
# i v nahodnem losovani - prehazet se nesmi.
#
# BARVA NIKDY NENI JEDINY NOSITEL INFORMACE. U sesti barev to plati
# dvojnasob: cervena se zelenou je nejcastejsi porucha barvocitu a fialova
# s modrou se pletou taky. Proto ma kazda barva SVOJE PISMENO a poutnik ho nosi
# ve svem puntiku ("R" jako Red, smes dve pismena "RY") - pismeno je to, co hrac
# na plose opravdu cte.

const RED := 0
const YELLOW := 1
const BLUE := 2
const GREEN := 3
const VIOLET := 4
const SILVER := 5
const COUNT := 6

# CHOVANI:
#   none   - nic zvlastniho
#   split  - po zabiti se rozpadne na dva mensi kusy
#   regen  - obnovuje si zivoty
#   vanish - po prvnim zasahu na chvili zmizi (pro vez je neviditelna)
#   shift  - kazdych PET SEKUND zmeni podobu: vezme si barvu, jeji schopnost
#            (leceni / rychlost / rozpad / zmizeni / odolnost), jeji rychlost
#            i jeji zdravotni pool; zacina jako stribrna a na stribrnou se uz
#            nevrati
const B_NONE := "none"
const B_SPLIT := "split"
const B_REGEN := "regen"
const B_VANISH := "vanish"
const B_SHIFT := "shift"

# JEDNA TABULKA PRO VSE, CO O BARVE NEKDO VI. Kdo chce jinou obtiznost barev,
# meni tady - nikdy v obrazovce ani v pravidlech.
#   letter      = PISMENO BARVY ve stredu puntiku palety. Je to POCATECNI
#                 PISMENO ANGLICKEHO NAZVU (Jan, Oct 2026: "Kazda barva bude mit
#                 ve stredu kruhu pismeno podle nazvu barvy. Cervena - R jako
#                 Red"). Anglicky proto, ze ceske "cervena/zluta/modra" dava
#                 C/Z/M a to se plete. Barva tak NIKDY neni jediny nositel
#                 informace - pismeno je druha cesta, jak barvu precte i hrac
#                 s poruchou barvocitu.
#   unlock_level = LEVEL, od ktereho barva do hry vstoupi. Jan (Oct 2026):
#                 "Už prvním levelu přibude modrá barva. To je špatně. Co
#                 level, to nová barva." Vstupuje se tedy LEVELem, ne vlnou:
#                 barva, ktera prijde uprostred bitvy, je pro hrace ticha
#                 zmena pravidel - a v prvnim levelu navic nikdo nevi, co
#                 modra (rozpadnuti) znamena.
#   palette     = je barva v palete hracе? Stribrna NENI - proto na ni na
#                 zacatku nejde mirrit a je to cely jeji smysl.
#   gold        = zlato za zabiti TOHLE barvy. Oct 2026 (Jan: "výdělky za
#                 zabití poutníků budou úměrně taky nižší ... jde spíš
#                 o optický rozdíl") je cely zlaty obeh PETKRAT mensi - viz
#                 `Game.START_GOLD`: 18/10/14/16/14/26 -> 4/2/3/3/3/5. Pomer
#                 mezi barvami (zluta nejlevnejsi, stribrna nejdrazsi) se
#                 NEMENI; kdo hybe jednim cislem, hybe i cenou upgradů.
const ROWS := [
	{
		"name": "Červená", "letter": "R", "color": Color(0.80, 0.22, 0.17),
		"hp": 2.2, "speed": 0.60, "gold": 4, "behaviour": B_NONE,
		"unlock_level": 1, "palette": true,
	},
	{
		# ZLUTA JE PORAD NEJRYCHLEJSI BARVA, ale uz ne o tolik. Jan (Oct 2026):
		# "Tak muzeme zlutou lehce zpomalit." Duvod je michani barev: o michani
		# rozhoduje ROZDIL casu cesty zlute a cervene (`Game.wave_gap`) - cim
		# mensi rozdil, tim kratsi vstupni okno staci, aby se barvy u veze
		# mijely, a tim kratsi je vlna i cely level. 1,60 -> 1,30 snizilo rozdil
		# na 390x844 z 8,0 s na 6,9 s (zluta zustava o 30 % rychlejsi nez modra
		# a zelena, ktere maji 1,00). Kdo hybe timhle cislem, hybe obtiznosti
		# i delkou levelu - a MUSI to premerit `tools/balance_sim.gd`.
		#
		# A ZA TU RYCHLOST PLATI ZIVOTY. Jan (Oct 2026): "A žlutí musí mít
		# o trochu vyšší životy. Vzali jsme jim trochu rychlosti, tak musíme
		# kompenzovat trochu vyššími životy." Rozhoduje `hp * speed` (cim
		# rychlejsi barva, tim kratsi dobu je v dostrelu, takze tim min ran
		# schytá): pred zpomalenim 0,60 * 1,60 = 0,96, po nem 0,60 * 1,30 =
		# 0,78 - zluta by byla nejlehci barva hry. Presna kompenzace je
		# 0,60 * 1,60 / 1,30 = 0,74; zvoleno 0,70, aby zluta zustala na urovni
		# nejkrehci barvy (fialova ma 0,70) a "nejrychlejsi = nejlehci" se
		# nerozjelo. Hlida to `test_core._test_fastest_is_not_free`.
		"name": "Žlutá", "letter": "Y", "color": Color(0.90, 0.78, 0.22),
		"hp": 0.7, "speed": 1.30, "gold": 2, "behaviour": B_NONE,
		"unlock_level": 1, "palette": true,
	},
	{
		"name": "Modrá", "letter": "B", "color": Color(0.22, 0.46, 0.80),
		"hp": 1.0, "speed": 1.00, "gold": 3, "behaviour": B_SPLIT,
		"unlock_level": 2, "palette": true,
	},
	{
		"name": "Zelená", "letter": "G", "color": Color(0.26, 0.62, 0.30),
		"hp": 1.2, "speed": 1.00, "gold": 3, "behaviour": B_REGEN,
		"unlock_level": 3, "palette": true,
	},
	{
		# NEJPOMALEJSI BARVA VE HRE (0,50 < 0,60 cervene i stribrne). Jan (Oct
		# 2026): "Upravime rychlost fialovych nepratel. Budou ze vsech
		# nejpomalejsi." Pomer 0,50/1,00 znamena, ze fialovy poutnik jde po
		# stejne ceste dvakrat tak dlouho nez modry - a protoze po prvnim
		# zasahu na 3 s zmizi, ma hrac vic casu ho vubec najit. Kdo hybe timhle
		# cislem, hybe obtiznosti; hlida to `tools/test_core.gd`
		# (`_test_hue_speed_order`).
		"name": "Fialová", "letter": "V", "color": Color(0.58, 0.34, 0.74),
		"hp": 0.7, "speed": 0.50, "gold": 3, "behaviour": B_VANISH,
		"unlock_level": 4, "palette": true,
	},
	{
		"name": "Stříbrná", "letter": "S", "color": Color(0.78, 0.80, 0.82),
		"hp": 2.5, "speed": 0.60, "gold": 5, "behaviour": B_SHIFT,
		"unlock_level": 5, "palette": false,
	},
]

# SMESI BAREV. Michani se odemyka v PETEM levelu (kdyz uz nova barva neni co
# pridat - Jan: "Dosáhl jsem teď do levelu 6 a nová barva už nepřibyla.") a dalsi
# tri levely pribyvaji dalsi dvojice (viz `MIX_UNLOCK_LEVEL`).
# míchání barev."
#
# SMES JE BARVA, ne nova entita: ma sve id, barvu, dve pismena i jmeno, a proto
# se nikde nemusi psat "kdyz je to smes, tak...". ID zacina na 100, aby se nikdy
# nepletlo s jednoduchou barvou (0..5) - diky tomu zustaly VSECHNY smycky
# `for h in range(Hue.COUNT)` (paleta, odemykani, tabulky) nedotcene.
#
# BARVA SMESI JE ADITIVNI PRUMER OBOU BAREV (Jan: "reálná kombinace"): cervena
# + zluta = oranzova. Nektere smesi vyjdou blizko sebe (zluta+modra vs
# zluta+fialova) - presne proto ma smes DVE PISMENA a vlastni tvar; barva nikdy
# neni jediny nositel informace.
const SINGLE_COUNT := 6
const MIX_BASE := 100
# LEVEL, OD KTEREHO SE MICHÁ, A KOLIK BAREV SE V KAZDEM LEVELU MICHÁ.
# Jan (Oct 2026) rozdelil michani do ctyr levelu, aby si hrac na kombinace zvykal
# postupne (samotne barvy se odemykaji po jedne - `unlock_level` v ROWS):
#   1.-4. level - 2, 3, 4 a 5 barev (michani jeste ne),
#   5. level - kombinace PRVNICH DVOU barev (R+Y),
#   6. level - kombinace prvnich TRI (RY, RB, YB),
#   7. level - kombinace prvnich CTYR,
#   8. level - kombinace VSECH PETI.
# "Prvnich N" je poradi v palete (`palette_at`): cervena, zluta, modra, zelena,
# fialova. Hlida to `test_core` (`mix_colors_at` i pocty v `mix_pool_at`).
const MIX_UNLOCK_LEVEL := 5

# TABULKA SMESI. Klic je dvojice pismen v poradi barev ("RY" = Red+Yellow), takze
# se nikdy nevygeneruje "YR". Barvy jsou spoctene aditivnim prumerem (viz vyse),
# sytost je drzena nad 0,32 - jinak by nekolik smesi vybledlo do sede a na tmave
# plose by zmizely.
const MIXES := {
	"RY": {"name": "Oranžová", "letter": "RY", "color": Color(0.85, 0.59, 0.20)},
	"RB": {"name": "Purpurová", "letter": "RB", "color": Color(0.60, 0.36, 0.60)},
	"RG": {"name": "Hnědá", "letter": "RG", "color": Color(0.61, 0.47, 0.24)},
	"RV": {"name": "Malinová", "letter": "RV", "color": Color(0.70, 0.29, 0.55)},
	"YB": {"name": "Šedá", "letter": "YB", "color": Color(0.68, 0.58, 0.45)},
	"YG": {"name": "Limetková", "letter": "YG", "color": Color(0.68, 0.71, 0.26)},
	"YV": {"name": "Písková", "letter": "YV", "color": Color(0.76, 0.57, 0.50)},
	"BG": {"name": "Petrolejová", "letter": "BG", "color": Color(0.24, 0.55, 0.62)},
	"BV": {"name": "Šeříková", "letter": "BV", "color": Color(0.45, 0.41, 0.77)},
	"GV": {"name": "Olivová", "letter": "GV", "color": Color(0.38, 0.46, 0.58)},
}
# Kdyby tabulka nekryla vsech 10 dvojic, jede se na tuhle barvu - nikdy se
# nekresli "neco jineho, nez si hra mysli". Test hlida, ze se sem nikdy nesahne.
const MIX_FALLBACK := {"name": "Směs", "letter": "??", "color": Color(0.50, 0.49, 0.46)}

# ROZPAD MODRE: dva kusy, kazdy se 40 % zivotu rodice, mensi a nikdy se
# nedeli znovu (jinak by z jednoho poutnika bylo nekonecno).
const SPLIT_PIECES := 2
const SPLIT_HP_FRAC := 0.40
# VELIKOST ROZPADLEHO KUSU (modra). Byl 0,72 - ale od Oct 2026 nosi kazdy poutnik
# ve svem puntiku PISMENO barvy, a v 0,72 se uz "B" do puntiku neveslo (na 390x844
# vyslo 5,9 px v polomeru). 0,85 drzi kus mensi nez rodic, ale pismeno se do nej
# vejde - hlida to `test_layout._test_enemy_is_dot_with_letters`.
const SPLIT_SIZE := 0.85

# ---------------------------------------------------- UROVNE POUTNIKA (TIER)
# Jan (Oct 2026): "kazda barva (nepratele) by nemely mit jen jeden typ
# nepritele. ... Cervena by mela mit nejmensi, od prvniho levelu, a pak by se
# mohly objevovat dalsi urovne. Vyssi. Vizualne vetsi, s vyssemi zivoty. ...
# Poměrově ke svým základním životům. Takových úrovní by byly třeba 3 nebo 4.
# Bosse nepočítám, to je úroveň sama pro sebe." + "Přidat navíc nad dnešní
# růst" a "4" urovne (rozhodnuti ze ctyř otázek, Oct 2026).
#
# UROVEN JE NASOBEK NAD ZAKLADNÍ HODNOTY TÉ BARVY (`ROWS`), ne nova barva:
# cervena urovne 3 je porad cervena (barva, pismeno, chovani i zlato), jen ma
# 2,1x zivotu, je o 24 % vetsi a pada z ni 1,9x zlata. Nesmi se plest ani s
# `mix` (smes je JINA barva s vlastnim id a pismeny), ani s bossem (`is_boss`
# = jedina bytost sve vlny, na tierech nezavisla).
#
# UROVEN SE ODEMYKA LEVELem a NIZSI UROVNE ZUSTAVAJI: od 7. levelu chodi ve
# vlne vsechny ctyri vedle sebe, takze hrac vidi, jak rostou. LEVEL 1 JE BEZ
# ZMENY (vsechno uroven 1) - prvni dojem z hry zustava presne jak byl.
const TIER_COUNT := 4
const TIER_UNLOCK := [1, 3, 5, 7]
# ZIVOTY JDOU NAVIC NAD SOUCASNY RUST (`LEVEL_HP`), takze je hra od 3. levelu
# tezsi - od 7. levelu ma prumerna vlna o ~48 % vic zivotu. JE TO VEDOME
# (Janovo rozhodnuti) a cisla se overuji `tools/balance_sim.gd`, ne dojmem.
# Zlato roste pomaleji nez zivoty (1,39x proti 1,48x), aby vetsi poutnik nebyl
# zdarma - to je jedina cast, ktera hru ztizuje.
const TIER_HP := [1.0, 1.5, 2.1, 2.9]
# VELIKOST KRESBY je druha cesta k informaci "tenhle je tvrdsi" - nezávisí na
# barve, takze ji precte i hrac s poruchou barvocitu. Oct 2026 (Jan: "velikostni
# rozdil mezi urovnemi nepřátel se ztratil"): kroky 1,12/1,24/1,36 byly na
# telefonu nerozeznatelne, dnes 1,28/1,60/1,95 - kazdy stupen je nejmene o
# ctvrtinu vetsi nez predchozi, takze se velikost cte na prvni pohled.
const TIER_SIZE := [1.0, 1.28, 1.60, 1.95]
const TIER_GOLD := [1.0, 1.4, 1.9, 2.5]
# CETNOST VE VLNE, kdyz je uroven odemcena (hra ji normalizuje pres soucet
# odemcenych). Vyssi uroven je vzacnejsi - jinak by od 7. levelu zmizeli malí
# poutníci a s nimi i cela prvni pulka hry.
const TIER_WEIGHT := [0.45, 0.30, 0.18, 0.07]
# JMENO PRO HUD A HLASKY ("objeví se větší poutníci").
const TIER_NAME := ["menší", "větší", "velcí", "obří"]

# REGENERACE ZELENE: podil maximalnich zivotu za sekundu. Musi byt vyrazne
# mensi nez kadence veze, jinak je poutnik nesmrtelny.
const REGEN_FRAC := 0.04

# FIALOVA: jak dlouho po prvnim zasahu je pro vez neviditelna.
const VANISH_S := 3.0
# STRIBRNA: jak casto meni podobu. Pet vterin (Jan, Oct 2026: "Teď mění podobu
# po 3s. Nově budou měnit po 5s.") - za tu dobu ji hrac stihne zabit, i kdyz
# cestou projde dvema podobami.
const SHIFT_S := 5.0


static func is_mix(h: int) -> bool:
	return h >= MIX_BASE and h < MIX_BASE + SINGLE_COUNT * SINGLE_COUNT


# ID SMESI DVOU BAREV. V poradi barev (mini, maxi), aby "cervena+zluta" a
# "zluta+cervena" bylo VZDY to same id - jinak by jedna smes mela dve jmena.
# Vraci -1, kdyz se michat neda (stejna barva nebo barva mimo tabulku).
static func mix_id(a: int, b: int) -> int:
	if a < 0 or b < 0 or a >= COUNT or b >= COUNT or a == b:
		return -1
	return MIX_BASE + mini(a, b) * SINGLE_COUNT + maxi(a, b)


# NA JAKYCH BARVACH JE TAHLE BARVA POSTAVENA. U jednoduche barvy vraci sebe
# samu, u smesi obe slozky - diky tomu se da o kazde barve mluvit jednim kódem.
static func pair_of(h: int) -> Array:
	if not is_mix(h):
		return [h]
	var rest: int = h - MIX_BASE
	return [rest / SINGLE_COUNT, rest % SINGLE_COUNT]


# KLIC DO TABULKY SMESI ("RY"). Sklada se z pismen v poradi barev, takze se
# nikdy nevygeneruje "YR".
static func mix_key(h: int) -> String:
	var p: Array = pair_of(h)
	if p.size() < 2:
		return ""
	return letter_of(int(p[0])) + letter_of(int(p[1]))


# MUZE VEZE S TOUTO SADOU BAREV ZASahnout TOHOTO POUTNIKA? Kazda barva poutnika
# musi byt v sade veze: vez s R vidi cervenou, ale oranzovou (R+Y) ne. Je to
# JEDINE misto, kde se o barve rozhoduje - vsechno ostatni se na `sees` jen ptá.
static func covers(tower_hues: Array, enemy_hue: int) -> bool:
	for h in pair_of(enemy_hue):
		if not tower_hues.has(int(h)):
			return false
	return true


# JE MICHANI V TOMTO LEVELU ODEMCENE?
static func mix_unlocked(level: int) -> bool:
	return level >= MIX_UNLOCK_LEVEL


# KOLIK PRVNICH BAREV SE V TOMTO LEVELU SMI MICHAT. Je to jedine misto, kde je
# receno, jak rychle si hrac na michani zvyka (viz `MIX_UNLOCK_LEVEL`).
static func mix_colors_at(level: int) -> int:
	if not mix_unlocked(level):
		return 0
	return clampi(level - MIX_UNLOCK_LEVEL + 2, 0, palette_at(level).size())


# VSECHNY SMESI, KTERE V TETO CHVILI MAJI SMYSL: michani je odemcene, obe barvy
# uz ve hre jsou a je to dvojice z prvnich `mix_colors_at` barev.
static func mix_pool_at(level: int) -> Array:
	var n: int = mini(mix_colors_at(level), palette_at(level).size())
	var out: Array = []
	if n < 2:
		return out
	var pal: Array = palette_at(level)
	for i in range(n):
		for j in range(i + 1, n):
			out.append(mix_id(int(pal[i]), int(pal[j])))
	return out


# JEDNA TABULKA PRO VSE, CO O BARVE NEKDO VI.
static func _row(h: int) -> Dictionary:
	if is_mix(h):
		var key: String = mix_key(h)
		if MIXES.has(key):
			return MIXES[key]
		return MIX_FALLBACK
	return ROWS[clampi(h, 0, COUNT - 1)]


# SCHOPNOSTI SMESI: MA OBE. Plan (Jan): "prvni verze dá kombinovanému poutníkovi
# OBĚ chování (dělení i regenerace apod.)". U jednoduche barvy je to jedna
# schopnost, u smesi dve - proto se vsude v bitve ptá `Pilgrim.has_behaviour()`,
# ne na jednu hodnotu `behaviour` (ta zustava jako PRVNI schopnost kvuli stribrne,
# ktera si pri zmene podoby prebira prave ji).
static func behaviours_of(h: int) -> Array:
	if not is_mix(h):
		return [behaviour_of(h)]
	var out: Array = []
	for part in pair_of(h):
		var b: String = behaviour_of(int(part))
		if b != B_NONE and not out.has(b):
			out.append(b)
	if out.is_empty():
		out.append(B_NONE)
	return out


# Bezpecne prevody. GDScript bere zaporny index od konce pole, takze
# `ROWS[-1]` je Stribrna - kdo si toho nevsimne, kresli neco jineho, nez si
# mysli, a je presvedceny, ze je to spravne.
static func is_valid(h: int) -> bool:
	return (h >= 0 and h < COUNT) or is_mix(h)


static func name_of(h: int) -> String:
	if not is_valid(h):
		return "?"
	return String(_row(h).get("name", "?"))


static func color_of(h: int) -> Color:
	if not is_valid(h):
		return Color(0.36, 0.35, 0.33)
	return _row(h)["color"]


# PISMENO BARVY: pocatecni pismeno anglickeho nazvu ("R" jako Red) - viz ROWS.
# SMES MA DVE PISMENA ("RY" = Red + Yellow); sklada se z poradi barev, takze
# "cervena+zluta" je VZDY "RY" a nikdy "YR".
static func letter_of(h: int) -> String:
	if is_mix(h):
		return mix_key(h)
	if not is_valid(h):
		return "?"
	return String(_row(h).get("letter", "?"))


# PISMENO SMESI DVOU BAREV ("RY" = Red + Yellow). Poradi pismen je dane poradim
# barev v tabulce (0..5), takze cervena+zluta je VZDY "RY" a nikdy "YR" - jinak
# by jedna barva mela dve jmena. Aby se to nemuselo hlídat ve obrazovce, je
# jedina cesta k pismenu smesi tady.
static func letter_of_pair(a: int, b: int) -> String:
	if not is_valid(a) or not is_valid(b) or a == b:
		return letter_of(a)
	return letter_of(mini(a, b)) + letter_of(maxi(a, b))


# ------------------------------------------------------------- UROVNE (TIER)
# KOLIK UROVNI JE V TOMTO LEVELU ODEMCENO. Nikdy nula - prvni uroven je hra
# od prvniho levelu (nema smysl, aby hra bezela bez nepritele).
static func tier_unlocked(level: int) -> int:
	var n: int = 0
	for t in range(TIER_COUNT):
		if int(TIER_UNLOCK[t]) <= level:
			n += 1
	return maxi(1, n)


# UROVNE, KTERE V TOMTO LEVELU SMI VSTOUPIT. Hra z toho losuje - jedine misto,
# odkud se seznam bere (obrazovka ani testy si ho neskládaji samy).
static func tier_pool(level: int) -> Array:
	var out: Array = []
	for t in range(tier_unlocked(level)):
		out.append(t)
	return out


# VAHA UROVNE V TETO VLNE (0 = jeste neni odemcena). Normalizuje si ji hra;
# tady se nedeli, aby se dala vaha cist primo z tabulky.
static func tier_weight(t: int, level: int) -> float:
	if t < 0 or t >= tier_unlocked(level):
		return 0.0
	return float(TIER_WEIGHT[t])


# NEBEZPECNE PREVODY: uroven mimo tabulku NESMI shodit hru ani potichu zmenit
# obtiznost - neznama uroven je vzdy ta prvni (zakladni) hodnota.
static func tier_hp(t: int) -> float:
	return float(TIER_HP[clampi(t, 0, TIER_COUNT - 1)])


static func tier_size(t: int) -> float:
	return float(TIER_SIZE[clampi(t, 0, TIER_COUNT - 1)])


static func tier_gold(t: int) -> float:
	return float(TIER_GOLD[clampi(t, 0, TIER_COUNT - 1)])


static func tier_name(t: int) -> String:
	return String(TIER_NAME[clampi(t, 0, TIER_COUNT - 1)])


# HODNOTY SOUHRNU. U SMESI JE TO PRUMER OBOU BAREV, ne maximum (Jan: "S
# průměrováním síly souhlasím."). Zluta je rychla a slaba, cervena pomala
# a silna - maximum z obou by bylo ~3,7x tezsi nez cervena sama.
static func hp_mult(h: int) -> float:
	if is_mix(h):
		var p: Array = pair_of(h)
		return (hp_mult(int(p[0])) + hp_mult(int(p[1]))) * 0.5
	return float(_row(h)["hp"])


static func speed_mult(h: int) -> float:
	if is_mix(h):
		var p: Array = pair_of(h)
		return (speed_mult(int(p[0])) + speed_mult(int(p[1]))) * 0.5
	return float(_row(h)["speed"])


static func gold_of(h: int) -> int:
	if is_mix(h):
		var p: Array = pair_of(h)
		return int(round(float(gold_of(int(p[0])) + gold_of(int(p[1]))) * 0.5))
	return int(_row(h)["gold"])


# CHOVANI SMESI: obe (reseno v `Pilgrim.behaviours`). Tady vraci prvni z nich -
# je to zaloha pro mista, ktera potrebuji jedno jmeno chovani.
static func behaviour_of(h: int) -> String:
	if is_mix(h):
		var p: Array = pair_of(h)
		return behaviour_of(int(p[0]))
	return String(_row(h).get("behaviour", B_NONE))


# JE BARVA V PALETE? Stribrna ne - a presne proto na ni hrac nemuze mirrit.
static func in_palette(h: int) -> bool:
	if not is_valid(h):
		return false
	return bool(_row(h).get("palette", false))


static func unlock_level(h: int) -> int:
	return int(_row(h).get("unlock_level", 1))


# BARVY, KTERE V TOMTO LEVELU VSTUPUJI DO HRY (vsechny, i nepolapitelne).
static func active_at(level: int) -> Array:
	var out: Array = []
	for h in range(COUNT):
		if unlock_level(h) <= level:
			out.append(h)
	return out


# CO UKAZUJE PALETA HRACE. Stribrna v ni nikdy neni.
static func palette_at(level: int) -> Array:
	var out: Array = []
	for h in range(COUNT):
		if in_palette(h) and unlock_level(h) <= level:
			out.append(h)
	return out
