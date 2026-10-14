class_name BuiltinLevels
extends RefCounted

# LEVELY ZAKOTVENE VE HRE. Sem se vklada level, ktery Jan vyrobi v editoru
# a posle mi jeho kod. Je to zdroj pravdy pro "natrvalo": co je tady, to se
# veze s hrou na vsechny platformy a neda se to ztratit smazanim cache.
#
# Kod levelu se do toho vklada doslova - Level.from_code() ho precte a
# Level.validate() overi, ze dava smysl. Nic se neprepisuje rucne (ani jmeno
# uvnitr kodu: to, co hrac vidi v seznamu, je `name` tady - hracuv level ma
# sve jmeno zapsane ve svem kodu a to se nemeni).
#
# HRACI SE V PORADI, V JAKEM JSOU TADY. Prvni level je odemceny vzdy, kazdy
# dalsi se odemkne vyhrou toho predchoziho (viz `Campaign`). Poradi v seznamu
# je tedy postup hrou - nic se podle nej nepocita, ale prehazovat se nesmi.

const LEVELS: Array = [
	{
		"name": "Level 1",
		# Januv level (Oct 2026): vstupni usek vlevo nahore, jedna vyhybka,
		# ohniva a vodni vetev se sliji spojkou a neutralni usek vede do cile.
		"code": "ZILY2;{\"e\":[[-1,1,[[0,1],[1,1],[2,1],[3,1],[4,1],[5,1],[6,1],[7,1],[8,1],[9,1],[10,1],[11,1]]],[0,0,[[11,1],[12,1],[13,1],[14,1],[15,1],[16,1],[17,1],[17,2],[17,3],[17,4],[17,5],[17,6],[17,7],[17,8],[17,9],[17,10],[17,11]]],[1,0,[[11,1],[11,2],[11,3],[11,4],[11,5],[11,6],[11,7],[11,8],[11,9],[11,10],[11,11],[12,11],[13,11],[14,11],[15,11],[16,11],[17,11]]],[-1,0,[[17,11],[18,11],[19,11],[20,11],[21,11],[22,11],[23,11],[24,11],[25,11],[26,11],[27,11]]]],\"g\":180,\"h\":14,\"l\":12,\"n\":\"level-4\",\"p\":1.9,\"rt\":120.0,\"s\":48.0,\"u\":[[0,1,0],[11,1,2],[17,11,3],[27,11,1]],\"v\":2,\"w\":28}",
	},
]
