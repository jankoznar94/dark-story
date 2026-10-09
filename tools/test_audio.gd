extends SceneTree

# Test ZVUKU. Hra si ton generuje za behu, takze se da zmerit - a musi,
# protoze "v reporoduktoru praska" se neda odhalit zadnym testem pravidel.
# Vystup: AUDIO_ALL_PASS=true / false
#
# Co se kontroluje a proc:
#  - jednorazove tuknuti NESMI mit smycku (loopovany 0.09s ton = 11 lupnuti/s)
#  - smycka hudby MUSI mit cely pocet period, jinak na konci smycky skocí fáze
#  - obalka: tuknuti zacina a konci v tichu, smycka obalku mit nesmi

var fails: Array = []
var checks: int = 0


func _init() -> void:
	var snd := Sound.new()

	_test_tap_not_looped(snd)
	_test_sfx_does_not_repeat(snd)
	_test_loop_has_whole_cycles(snd)
	_test_loop_has_no_seam(snd)
	_test_loop_has_no_envelope(snd)
	_test_tap_has_envelope(snd)
	_test_audio_is_audible(snd)

	print("checks=%d fails=%d" % [checks, fails.size()])
	for f in fails:
		print("FAIL: " + str(f))
	if fails.is_empty():
		print("AUDIO_ALL_PASS=true")
	else:
		print("AUDIO_ALL_PASS=false")
	quit()


func _ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails.append(what)


# Vzorky jako cisla (podpisane 16bit), pro mereni obalky a skoku.
func _samples(w: AudioStreamWAV) -> Array:
	var out: Array = []
	for i in range(w.data.size() / 2):
		var lo: int = w.data[i * 2]
		var hi: int = w.data[i * 2 + 1]
		var v: int = lo | (hi << 8)
		if v >= 32768:
			v -= 65536
		out.append(v)
	return out


func _test_tap_not_looped(snd: Sound) -> void:
	var w := snd.sfx_tap()
	_ok(w.loop_mode == AudioStreamWAV.LOOP_DISABLED,
		"tuknuti se nesmi smyckovat (loop_mode=%d)" % w.loop_mode)


# 0.09 s stream ve smycce = 11 obehnuti za sekundu. To je to praskani.
func _test_sfx_does_not_repeat(snd: Sound) -> void:
	var w := snd.sfx_tap()
	var sec := float(w.data.size() / 2) / float(w.mix_rate)
	_ok(sec > 0.05 and sec < 0.2, "tuknuti ma byt kratke (%.3f s)" % sec)
	_ok(w.loop_mode == AudioStreamWAV.LOOP_DISABLED,
		"kratky ton ve smycce opakuje obalku ~%.0f x za sekundu" % (1.0 / maxf(sec, 0.001)))


func _test_loop_has_whole_cycles(snd: Sound) -> void:
	var w := snd.music_loop()
	var period := snd.period_samples(Sound.MUSIC_HZ)
	var n := w.data.size() / 2
	_ok(n % period == 0,
		"smycka musi mit cely pocet period: %d vzorku, perioda %d, zbytek %d"
			% [n, period, n % period])
	_ok(w.loop_mode == AudioStreamWAV.LOOP_FORWARD, "hudba se ma smyckovat")


# Na smycce nesmi byt skok: posledni vzorek -> prvni musi byt plynuly.
func _test_loop_has_no_seam(snd: Sound) -> void:
	var w := snd.music_loop()
	var s := _samples(w)
	var jump: int = absi(int(s[0]) - int(s[s.size() - 1]))
	# Prechod na smycce je normalni krok vzorkovani, ne skok.
	var step: int = absi(int(s[1]) - int(s[0]))
	_ok(jump <= step * 3 + 4, "skok na smycce je %d, bezny krok vzorkovani %d" % [jump, step])


# Obalka ve smycce = ticho na kazdem obehnuti. Prohloupe se RMS na okrajich
# bufferu: u smycky BEZ obalky je stejne silny jako uvnitr, u smycky S obalkou
# kraje utichnou a hrac slysi "dychani" pri kazdem obehnuti.
func _test_loop_has_no_envelope(snd: Sound) -> void:
	var w := snd.music_loop()
	var s := _samples(w)
	var win: int = int(0.02 * float(w.mix_rate))
	var all_rms := _rms(s, 0, s.size())
	var head_rms := _rms(s, 0, win)
	var tail_rms := _rms(s, s.size() - win, s.size())
	_ok(all_rms > 100.0, "hudba musi neco slyset (RMS=%.0f)" % all_rms)
	_ok(head_rms > all_rms * 0.5,
		"zacatek smycky je utlumeny (RMS %.0f vs uvnitr %.0f)" % [head_rms, all_rms])
	_ok(tail_rms > all_rms * 0.5,
		"konec smycky je utlumeny (RMS %.0f vs uvnitr %.0f)" % [tail_rms, all_rms])


func _rms(s: Array, from: int, to: int) -> float:
	var acc := 0.0
	for i in range(from, to):
		var v := float(s[i])
		acc += v * v
	return sqrt(acc / float(maxi(1, to - from)))


# Tuknuti naopak obalku MIT ma - jinak cvakne na zacatku a konci.
func _test_tap_has_envelope(snd: Sound) -> void:
	var w := snd.sfx_tap()
	var s := _samples(w)
	_ok(absi(int(s[0])) < 40, "tuknuti ma zacinat v tichu (%d)" % absi(int(s[0])))
	_ok(absi(int(s[s.size() - 1])) < 40, "tuknuti ma koncit v tichu (%d)" % absi(int(s[s.size() - 1])))
	var mid: int = absi(int(s[s.size() / 2]))
	_ok(mid > 3000, "uprostred ma tuknuti hlasitost (%d)" % mid)


func _test_audio_is_audible(snd: Sound) -> void:
	var w := snd.music_loop()
	_ok(w.mix_rate > 8000, "vzorkovaci frekvence (%d)" % w.mix_rate)
	_ok(w.format == AudioStreamWAV.FORMAT_16_BITS, "format 16 bitu")
	_ok(w.stereo == false, "mono")
	_ok(w.data.size() > 0, "buffer neni prazdny")
