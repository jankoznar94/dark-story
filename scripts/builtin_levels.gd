class_name BuiltinLevels
extends RefCounted

# LEVELY ZAKOTVENE VE HRE. Sem se vklada level, ktery Jan vyrobi v editoru
# a posle mi jeho kod. Je to zdroj pravdy pro "natrvalo": co je tady, to se
# veze s hrou na vsechny platformy a neda se to ztratit smazanim cache.
#
# Kod levelu se do toho vklada doslova - Level.from_code() ho precte a
# Level.validate() overi, ze dava smysl. Nic se neprepisuje rucne.
#
# Priklad (zakladni deska):
#   {"name": "zakladni", "code": "ZILY1;zakladni;..."}
const LEVELS: Array = []
