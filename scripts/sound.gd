class_name Sound
extends RefCounted

# Generovany zvuk. Hra neveze zadne audio soubory - ton se pocita za behu,
# takze "zapni/vypni zvuk" ma co prepnout a nemusi se posilat asset.
#
# CTYRI VECI, ktere se v praxi projevily jako "v reporoduktoru praska":
#
# 1) SMYCKA. Kazdy ton mel loop_mode = LOOP_FORWARD, i jednorazove tuknuti.
#    Stream se proto opakoval kazdych 0.09 s - obalka tuknuti 11x za sekundu
#    sjela na nulu a zpet, coz v reporoduktoru zni jako nepricetne praskani,
#    ne jako tuknuti. Smycku smi mit JEN hudba.
#
# 2) PERIODA. Aby na smycke nebyl skok, musi se do bufferu vejit CELY pocet
#    period. Hrat "3.0 s pri 55 Hz" znamena 165 period, ale vzorkovaci
#    frekvence nasobkem 55 neni, takze posledni perioda byla useknuta a na
#    konci kazde smycky to lupnulo.
#
# 3) VZORKOVACI FREKVENCE. Tenhle ton se generoval na 22050 Hz, ale zvukova
#    karta systemu jede na 44100 (a prohlizec na 48000). Kazdy vzorek se tedy
#    musel PREPOCITAVAT a u smycky navic nevysel prechod na konec bufferu na
#    cely vzorek -> na kazdem obehnuti lupnuti. Ton se proto generuje ROVNOU
#    na frekvenci, na ktere hra Opravdu micha (AudioServer.get_mix_rate()).
#
# 4) PRERUSOVANE TUKNUTI. AudioStreamPlayer prehrava jeden stream; kdyz hrac
#    klepne znovu, dokud predchozi tuknuti dozniva, Godot stream RESTARTUJE -
#    a to je ostri rez uprostred obalky, tedy cvaknuti. max_polyphony to
#    resi: kazde tuknuti dozni, misto aby ho dalsi utalo.
#
# Zvuk se generuje presne na zlomky vzorkovaci frekvence: perioda je cele
# cislo vzorku, takze sinusovka se na smycke potka sama se sebou.

const FALLBACK_RATE := 44100
# Doba nabehu tuknuti. Delsi nabeh zni jako "vzdechnuti", kratsi cvakne.
const TAP_ATTACK := 0.002
# Casova konstanta dobehu tuknuti, v podilu jeho delky. Vetsi cislo =
# kratsi, ostrejsi tuknuti. 0.35 necha tuknuti zni 40-50 ms.
const TAP_TAU := 0.35
const MUSIC_SEC := 3.0
# Dva tony v oktave. 55 Hz telefonni reproduktor neumi - kmita na doraz
# a chrasti. 110 Hz uz zahraje ciste a je to porad hluboky, klidny ton.
const MUSIC_HZ := 110.0
const MUSIC_AMP := 0.10
const MUSIC_AMP2 := 0.035
const TAP_HZ := 220.0
const TAP_SEC := 0.09
const TAP_AMP := 0.45

var _rate: int = FALLBACK_RATE


func _init() -> void:
	_rate = _mix_rate()


# Frekvence, na ktere hra opravdu micha. Kdyz se ton vyrobi na te same
# frekvenci, odpadne prepoctove kolo a s nim i lupnuti na smycce.
static func _mix_rate() -> int:
	var r: int = int(AudioServer.get_mix_rate())
	if r <= 0:
		r = FALLBACK_RATE
	return r


func rate() -> int:
	return _rate


# Jednorazove tuknuti. BEZ smycky - to je prvni pulka opravy praskani.
func sfx_tap() -> AudioStreamWAV:
	return tone(TAP_HZ, TAP_SEC, TAP_AMP, false)


# Podkladova smycka: zakladni ton + jeho oktava. Obe frekvence maji v bufferu
# cely pocet period, takze se smycka potka sama se sebou.
func music_loop() -> AudioStreamWAV:
	var period := period_samples(MUSIC_HZ)
	var cycles: int = maxi(1, int(round(MUSIC_SEC * MUSIC_HZ)))
	var data := PackedByteArray()
	data.resize(cycles * period * 2)
	for i in range(cycles * period):
		var a: float = sin(TAU * float(i) / float(period))
		var b: float = sin(TAU * 2.0 * float(i) / float(period))
		var v: int = int((a * MUSIC_AMP + b * MUSIC_AMP2) * 32767.0)
		_put(data, i, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = _rate
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = cycles * period
	return w


func tone(hz: float, sec: float, amp: float, looped: bool) -> AudioStreamWAV:
	var data := samples(hz, sec, amp, looped)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = _rate
	w.stereo = false
	w.data = data
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size() / 2
	else:
		w.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return w


# Vzorky jako 16bitove mono. Vraci presne `cycles * period` vzorku.
func samples(hz: float, sec: float, amp: float, looped: bool) -> PackedByteArray:
	var period := period_samples(hz)
	# Smycka musi mit cely pocet period; jednorazovy ton staci priblizne.
	var cycles: int = maxi(1, int(round(sec * hz)))
	var n: int = cycles * period if looped else maxi(1, int(round(sec * float(_rate))))
	var data := PackedByteArray()
	data.resize(n * 2)
	var attack: float = float(_rate) * TAP_ATTACK
	# Normalizovany dobeh: presne 1.0 na zacatku a PRESNE 0.0 na konci.
	# Kdyby na konci nezustala nula, uslysel by hrac lupnuti - a primka
	# dobeh dela v obalce zlom, ktery je slyset jako druhe cvaknuti.
	var k: float = exp(-1.0 / TAP_TAU)
	for i in range(n):
		var env := 1.0
		if not looped:
			var t: float = float(i) / float(n)
			var decay: float = (exp(-t / TAP_TAU) - k) / (1.0 - k)
			env = minf(1.0, float(i) / attack) * maxf(0.0, decay)
		# Faze se pocita z periody, ne z frekvence: tak je zaručene, ze
		# v bufferu je cely pocet period a smycka sedi.
		var v: int = int(sin(TAU * float(i) / float(period)) * amp * env * 32767.0)
		_put(data, i, v)
	return data


func _put(data: PackedByteArray, i: int, v: int) -> void:
	var c: int = clampi(v, -32768, 32767)
	data[i * 2] = c & 0xFF
	data[i * 2 + 1] = (c >> 8) & 0xFF


# Vzorku na jednu periodu - zaokrouhleno na cele cislo, aby sinusovka
# prosla presne celym poctem vzorku a na smycke nevznikl skok.
func period_samples(hz: float) -> int:
	return maxi(2, int(round(float(_rate) / hz)))
