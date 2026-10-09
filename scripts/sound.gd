class_name Sound
extends RefCounted

# Generovany zvuk. Hra neveze zadne audio soubory - ton se pocita za behu,
# takze "zapni/vypni zvuk" ma co prepnout a nemusi se posilat asset.
#
# TRI VECI, ktere se v praxi projevily jako "v reporoduktoru neustale praska":
#
# 1) SMYCKA. Kazdy ton mel loop_mode = LOOP_FORWARD, i jednorazove tuknuti.
#    Stream se proto opakoval kazdych 0.09 s - obalka tuknuti 11x za sekundu
#    sjela na nulu a zpet, coz v reporoduktoru zni jako nepricetne praskani,
#    ne jako tuknuti. Smycku smi mit JEN hudba.
#
# 2) PERIODA. Aby na smycke nebyl skok, musi se do bufferu vejit CELY pocet
#    period. Hrat "3.0 s pri 55 Hz" znamena 165 period, ale vzorkovaci
#    frekvence neni nasobkem 55, takze posledni perioda byla useknuta a na
#    konci kazde smycky to lupnulo. Delka se proto pocita z period, ne ze
#    sekund: pocet period = round(sec * hz).
#
# 3) OBALKA. Tuknuti potrebuje nabeh a dobeh, aby necvaklo. Smycka zadnou
#    obalku mit NESMI - kazdy nabeh z nuly by znamenal ticho na kazdem
#    obehnuti.
#
# Zvuk se generuje presne na zlomky vzorkovaci frekvence: perioda je cele
# cislo vzorku, takze sinusovka se na smycce potka sama se sebou a nevznikne
# ani skok ve fazi.

const RATE := 22050
const FADE := 0.04
const MUSIC_HZ := 55.0
const MUSIC_SEC := 3.0
const MUSIC_AMP := 0.12
const TAP_HZ := 220.0
const TAP_SEC := 0.09
const TAP_AMP := 0.5


# Jednorazove tuknuti. BEZ smycky - to je cela oprava praskani.
func sfx_tap() -> AudioStreamWAV:
	return tone(TAP_HZ, TAP_SEC, TAP_AMP, false)


# Podkladova smycka. Bez obalky a s celym poctem period.
func music_loop() -> AudioStreamWAV:
	return tone(MUSIC_HZ, MUSIC_SEC, MUSIC_AMP, true)


func tone(hz: float, sec: float, amp: float, looped: bool) -> AudioStreamWAV:
	var data := samples(hz, sec, amp, looped)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
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
	var n: int = cycles * period if looped else maxi(1, int(round(sec * float(RATE))))
	var f := float(RATE) / float(period)
	var data := PackedByteArray()
	data.resize(n * 2)
	var fade: float = float(RATE) * FADE
	for i in range(n):
		var env := 1.0
		if not looped:
			if float(i) < fade:
				env = float(i) / fade
			elif float(i) > float(n) - fade:
				env = maxf(0.0, (float(n) - float(i)) / fade)
		var v: int = int(sin(TAU * f * float(i) / float(RATE)) * amp * env * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	return data


# Vzorku na jednu periodu - zaokrouhleno na cele cislo, aby sinusovka
# prosla presne celym poctem vzorku a na smycce nevznikl skok.
func period_samples(hz: float) -> int:
	return maxi(2, int(round(float(RATE) / hz)))
