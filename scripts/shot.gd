class_name Shot
extends RefCounted

# STRELA. Neni to jen znacka, ktera se mihne u veze: je to predmet, ktery LETI
# od veze k poutnikovi, a poskozeni ubira teprve pri DOPADU.
#
# Jan (Oct 2026): "Nepřátelé obdrží poškození instantně po výstřelu věže.
# Hra nebere v potaz dobu letu projektilu. Nepřítel musí obdržet poškození
# při impactu."
#
# Z toho plynou tri pravidla, ktera se nesmi nikde obejit:
#   * pri vystrelu se jen ZAZNAMENA rana, zivoty se neubiraji,
#   * zivoty ubira jedine dopad (`Game._impact`),
#   * strela, ktera leti na poutnika, jenz cestou umrel, doleti na jeho
#     posledni misto a VYHASI - nikoho jineho nezrani.

# DOBA LETU V SEKUNDACH. Zamerne to neni rychlost v pixelech: cas je stejny
# na kazdem rozliseni i na kazde desce, takze se mechanika nerozjede podle
# toho, jak velky displej hrac ma.
#
# JE TO SKORO INSTANTNI (Jan, Oct 2026): "Laser je teď hodně pomalý. Měl by
# být skoro instantní. Hra ale musí s poškozením čekat na impact." Paprsek
# proto doleti za 0,07 s (cca 4 snimky pri 60 fps) - hrac vidi zapulsovani
# z veze, ne putujici strelu. Poskozeni se ale porad nepocita pri vystrelu:
# ceka se na DOPAD (`_impact`), takze rana sedne presne ve chvili, kdy se
# spicka paprsku dotkne poutnika.
#
# NESMI BYT NULA ani pod jeden snimek: hra je deterministicka a testy meri
# "po vystrelu jeste leti, po dobe letu uz ne" - s nulovou dobou by strela
# dopadla ve stejnem snimku, ve kterem vznikla, a poskozeni by bylo zase
# instantni (presne to, co Jan nechce).
const FLIGHT := 0.07

# Ktery zivel strela nese. Barvu si z toho bere kresleni, aby strela mela
# barvu sve veze - stejne jako vez.
var element: int = 0
# Kolik zivotu ubere PRI DOPADU. Nasobek (protiklad 200 %, slaby 50 %,
# neutralni 100 %) je uz zapocitany tady, aby se pocital prave jednou.
var dmg: float = 0.0
# Poutnik, na ktereho strela leti. Strela je "navadena" - leti na jeho
# skutecnou pozici, ne na misto, kde stal pri vystrelu. Duvod je hratelnostni:
# vez strelila na TOHOTO poutnika, takze tenhle a zadny jiny ma ranu dostat.
var target: Enemy = null
# Odkud strela vystrelila (stred veze). Kresleni z toho bere smer ocasku.
var from: Vector2 = Vector2.ZERO
# Kde strela prave je a kam miri. `aim` se kazdy snimek prepocitava, kdyz
# poutnik jeste zije; kdyz umre, zustane posledni misto, kam doleti.
var pos: Vector2 = Vector2.ZERO
var aim: Vector2 = Vector2.ZERO
# Rychlost v px/s. Pocita se z prvni vzdalenosti k cili, aby let trval
# `FLIGHT` sekund. Neni to volba hrace ani levelu - je to jen prepocet casu
# na pixely.
var speed: float = 1.0


# Nova strela z veze `t` na poutnika `e`. Jedno misto, kde strela vznika:
# kdyby si ji sestavoval nekdo druhy (napr. nastroje), rozejdou se pravidla.
static func launch(t: Tower, e: Enemy, at: Vector2, aim_at: Vector2,
		dmg: float) -> Shot:
	var s := Shot.new()
	s.element = t.element
	s.dmg = dmg
	s.target = e
	s.from = at
	s.pos = at
	s.aim = aim_at
	# Delka letu je dana casem, ne rychlosti: `speed` je jen prepocet.
	s.speed = maxf(at.distance_to(aim_at) / FLIGHT, 1.0)
	return s
