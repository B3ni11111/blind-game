extends SceneTree
## Synthesizes the prototype's sound effects into res://audio/*.wav.
## Run:  godot --headless --path . --script res://tools/gen_audio.gd
## These are placeholders: any of them can be swapped for a real recording
## with the same file name.

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 1234
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://audio"))
	_save(_tongue_click(44100), 44100, "res://audio/tongue_click.wav")
	_save(_fan(22050), 22050, "res://audio/fan_loop.wav")
	_save(_fridge(22050), 22050, "res://audio/fridge_loop.wav")
	_save(_clock(22050), 22050, "res://audio/clock_loop.wav")
	_save(_tv_ad(22050), 22050, "res://audio/tv_ad.wav")
	_save(_drip(44100), 44100, "res://audio/drip_loop.wav")
	_save(_washer(22050), 22050, "res://audio/washer_loop.wav")
	_save(_step_foot(44100), 44100, "res://audio/step_foot.wav")
	_save(_step_peg(44100), 44100, "res://audio/step_peg.wav")
	print("audio generated")
	quit()


func _save(s: PackedFloat32Array, rate: int, path: String) -> void:
	var peak := 0.0001
	for v in s:
		peak = maxf(peak, absf(v))
	var gain := 0.9 / peak
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		bytes.encode_s16(i * 2, int(clampf(s[i] * gain, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	w.save_to_wav(ProjectSettings.globalize_path(path))
	print("  ", path, "  ", snappedf(s.size() / float(rate), 0.01), " s")


# --- helpers ----------------------------------------------------------------

func _noise() -> float:
	return rng.randf() * 2.0 - 1.0


## Blend the tail into the head so a noisy buffer loops without a seam.
func _loopify(s: PackedFloat32Array, xfade: int) -> PackedFloat32Array:
	var n := s.size() - xfade
	var out := s.slice(0, n)
	for i in xfade:
		var k := float(i) / xfade
		out[i] = s[n + i] * (1.0 - k) + s[i] * k
	return out


class Biquad:
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0

	func bandpass(f: float, q: float, rate: float) -> Biquad:
		var w0 := TAU * f / rate
		var alpha := sin(w0) / (2.0 * q)
		var a0 := 1.0 + alpha
		b0 = alpha / a0
		b1 = 0.0
		b2 = -alpha / a0
		a1 = -2.0 * cos(w0) / a0
		a2 = (1.0 - alpha) / a0
		return self

	func lowpass(f: float, q: float, rate: float) -> Biquad:
		var w0 := TAU * f / rate
		var alpha := sin(w0) / (2.0 * q)
		var c := cos(w0)
		var a0 := 1.0 + alpha
		b0 = (1.0 - c) / 2.0 / a0
		b1 = (1.0 - c) / a0
		b2 = b0
		a1 = -2.0 * c / a0
		a2 = (1.0 - alpha) / a0
		return self

	func highpass(f: float, q: float, rate: float) -> Biquad:
		var w0 := TAU * f / rate
		var alpha := sin(w0) / (2.0 * q)
		var c := cos(w0)
		var a0 := 1.0 + alpha
		b0 = (1.0 + c) / 2.0 / a0
		b1 = -(1.0 + c) / a0
		b2 = b0
		a1 = -2.0 * c / a0
		a2 = (1.0 - alpha) / a0
		return self

	func process(x: float) -> float:
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		return y


# --- sounds -------------------------------------------------------------------

## A short palatal tongue click: a sharp transient with a hollow mouth resonance.
func _tongue_click(rate: int) -> PackedFloat32Array:
	var n := int(0.07 * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var bp := Biquad.new().bandpass(2200.0, 3.0, rate)
	for i in n:
		var t := float(i) / rate
		var attack := clampf(t / 0.0004, 0.0, 1.0)
		var burst := _noise() * exp(-t / 0.0015)
		var ring := sin(TAU * 1750.0 * t) * exp(-t / 0.0045) * 0.8
		var body := sin(TAU * 520.0 * t) * exp(-t / 0.007) * 0.35
		out[i] = attack * (bp.process(burst) * 2.5 + ring + body)
	return out


## Standing fan: airflow noise pulsing at blade rate + motor hum. 6 s seamless loop.
func _fan(rate: int) -> PackedFloat32Array:
	var len_s := 6.0
	var xfade := int(0.3 * rate)
	var n := int(len_s * rate) + xfade
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := Biquad.new().lowpass(900.0, 0.7, rate)
	var lp2 := Biquad.new().lowpass(220.0, 0.7, rate)
	for i in n:
		var t := float(i) / rate
		var blade := 1.0 + 0.22 * sin(TAU * 18.0 * t) + 0.06 * sin(TAU * 36.0 * t + 1.0)
		var air := lp.process(_noise()) * 0.8 + lp2.process(_noise()) * 1.2
		var hum := sin(TAU * 100.0 * t) * 0.05 + sin(TAU * 200.0 * t) * 0.02 + sin(TAU * 300.0 * t) * 0.008
		out[i] = air * blade + hum
	return _loopify(out, xfade)


## Fridge compressor: low drone with a little rattle. 4 s seamless loop.
func _fridge(rate: int) -> PackedFloat32Array:
	var xfade := int(0.25 * rate)
	var n := int(4.0 * rate) + xfade
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := Biquad.new().lowpass(300.0, 0.7, rate)
	for i in n:
		var t := float(i) / rate
		var drone := sin(TAU * 50.0 * t) * 0.5 + sin(TAU * 100.0 * t) * 0.35 + sin(TAU * 150.0 * t) * 0.12
		var rattle := lp.process(_noise()) * (0.25 + 0.1 * sin(TAU * 7.0 * t))
		out[i] = drone + rattle
	return _loopify(out, xfade)


## Wall clock: tick ... tock, 2 s loop.
func _clock(rate: int) -> PackedFloat32Array:
	var n := 2 * rate
	var out := PackedFloat32Array()
	out.resize(n)
	var hp := Biquad.new().highpass(1500.0, 0.7, rate)
	for i in n:
		var t := fmod(float(i) / rate, 1.0)
		var tock := i >= rate
		var f := 3100.0 if not tock else 2500.0
		var click := sin(TAU * f * t) * exp(-t / 0.003) + hp.process(_noise()) * exp(-t / 0.001) * 0.6
		out[i] = click
	return out


## Dripping tap: irregular "plinks" (a rising resonant blip) in a 7 s loop.
func _drip(rate: int) -> PackedFloat32Array:
	var n := 7 * rate
	var out := PackedFloat32Array()
	out.resize(n)
	for when in [0.3, 1.55, 2.6, 4.1, 4.9, 6.2]:
		var f0 := rng.randf_range(900.0, 1300.0)
		var amp := rng.randf_range(0.6, 1.0)
		var i0 := int(when * rate)
		var ph := 0.0
		for i in int(0.12 * rate):
			var t := float(i) / rate
			var f := f0 * (1.0 + 1.4 * minf(t / 0.03, 1.0)) # pitch rises as the drop's cavity closes
			ph += TAU * f / rate
			var env := clampf(t / 0.001, 0.0, 1.0) * exp(-t / 0.025)
			out[i0 + i] += sin(ph) * env * amp
			# a softer echo off the tub
			if i0 + i + int(0.045 * rate) < n:
				out[i0 + i + int(0.045 * rate)] += sin(ph) * env * amp * 0.18
	return out


## Washing machine: tumbling drum, a soft thump each turn, motor whine. 6 s loop.
func _washer(rate: int) -> PackedFloat32Array:
	var xfade := int(0.3 * rate)
	var n := int(6.0 * rate) + xfade
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := Biquad.new().lowpass(250.0, 0.7, rate)
	var bp := Biquad.new().bandpass(700.0, 1.5, rate)
	for i in n:
		var t := float(i) / rate
		var turn := fmod(t, 1.5) / 1.5 # one drum turn per 1.5 s
		var slosh := bp.process(_noise()) * (0.25 + 0.35 * maxf(0.0, sin(TAU * turn)))
		var rumble := lp.process(_noise()) * 1.4
		var thump_t := fmod(t + 0.4, 1.5)
		var thump := sin(TAU * 55.0 * thump_t) * exp(-thump_t / 0.06) * 0.9
		var whine := sin(TAU * 420.0 * t) * 0.03 + sin(TAU * 840.0 * t) * 0.01
		out[i] = rumble + slosh + thump + whine
	return _loopify(out, xfade)


## A shoe on a wooden floor: soft low thud with a little scuff.
func _step_foot(rate: int) -> PackedFloat32Array:
	var n := int(0.25 * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := Biquad.new().lowpass(500.0, 0.8, rate)
	var bp := Biquad.new().bandpass(1800.0, 1.2, rate)
	for i in n:
		var t := float(i) / rate
		var thud := sin(TAU * 85.0 * t) * exp(-t / 0.035) * 0.9
		var body := lp.process(_noise()) * exp(-t / 0.03) * 1.5
		var scuff := bp.process(_noise()) * exp(-maxf(0.0, t - 0.02) / 0.04) * 0.25 * clampf((t - 0.01) / 0.02, 0.0, 1.0)
		out[i] = clampf(t / 0.002, 0.0, 1.0) * (thud + body) + scuff
	return out


## A wooden peg leg striking the floor: hard, hollow "tok" with a short ring.
func _step_peg(rate: int) -> PackedFloat32Array:
	var n := int(0.25 * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var bp := Biquad.new().bandpass(2500.0, 2.0, rate)
	for i in n:
		var t := float(i) / rate
		var knock := sin(TAU * 420.0 * t) * exp(-t / 0.02) * 0.8
		knock += sin(TAU * 980.0 * t) * exp(-t / 0.012) * 0.5
		knock += sin(TAU * 1730.0 * t) * exp(-t / 0.006) * 0.3
		var click := bp.process(_noise()) * exp(-t / 0.002) * 1.2
		var floor_thud := sin(TAU * 110.0 * t) * exp(-t / 0.025) * 0.4
		out[i] = clampf(t / 0.0005, 0.0, 1.0) * (knock + click + floor_thud)
	return out


## A TV commercial heard from across the room: jingle, an upbeat announcer
## (synthetic voice-like babble, no real words), music bed, closing jingle.
func _tv_ad(rate: int) -> PackedFloat32Array:
	var total := 13.5
	var n := int(total * rate)
	var out := PackedFloat32Array()
	out.resize(n)

	# Jingles
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for j in 2:
		var start := 0.1 if j == 0 else 11.4
		for k in notes.size():
			_tone(out, rate, start + k * 0.17, 0.3, notes[k], 0.5)
		_tone(out, rate, start + 0.7, 1.0, notes[0], 0.25)
		_tone(out, rate, start + 0.7, 1.0, notes[2], 0.25)
		_tone(out, rate, start + 0.7, 1.0, notes[3], 0.2)

	# Music bed under the voice (soft chords)
	var chords := [[261.63, 329.63, 392.0], [293.66, 349.23, 440.0], [246.94, 311.13, 392.0], [261.63, 329.63, 392.0]]
	for c in 4:
		for f in chords[c]:
			_tone(out, rate, 1.9 + c * 2.3, 2.3, f, 0.06)

	# Announcer
	_voice(out, rate, 1.9, 11.1)

	# TV speaker: tinny band
	var hp := Biquad.new().highpass(280.0, 0.7, rate)
	var lp := Biquad.new().lowpass(3600.0, 0.7, rate)
	for i in n:
		out[i] = lp.process(hp.process(out[i]))
	return out


func _tone(out: PackedFloat32Array, rate: int, start: float, dur: float, f: float, amp: float) -> void:
	var i0 := int(start * rate)
	var cnt := int(dur * rate)
	for i in cnt:
		if i0 + i >= out.size():
			break
		var t := float(i) / rate
		var env := clampf(t / 0.01, 0.0, 1.0) * exp(-t / (dur * 0.45))
		var s := sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t) + 0.12 * sin(TAU * f * 3.0 * t)
		out[i0 + i] += s * env * amp


const VOWELS := [
	[730.0, 1090.0], [270.0, 2290.0], [530.0, 1840.0], [300.0, 870.0],
	[660.0, 1720.0], [440.0, 1020.0], [490.0, 1350.0], [400.0, 2000.0],
]

func _voice(out: PackedFloat32Array, rate: int, start: float, end: float) -> void:
	var t := start
	var phase := 0.0
	var f1 := Biquad.new()
	var f2 := Biquad.new()
	var f3 := Biquad.new().bandpass(2600.0, 6.0, rate)
	while t < end - 0.3:
		# a phrase: 3-6 words, pitch falls across it
		var words := rng.randi_range(3, 6)
		var phrase_start := t
		var phrase_len_est := words * 0.42
		for w in words:
			var syl := rng.randi_range(1, 3)
			for s in syl:
				var dur := rng.randf_range(0.09, 0.2)
				var v: Array = VOWELS[rng.randi() % VOWELS.size()]
				f1.bandpass(v[0], 7.0, rate)
				f2.bandpass(v[1], 9.0, rate)
				var i0 := int(t * rate)
				var cnt := int(dur * rate)
				var consonant := rng.randf() < 0.6
				for i in cnt:
					var idx := i0 + i
					if idx >= out.size():
						break
					var lt := float(i) / rate
					var prog := clampf((t + lt - phrase_start) / phrase_len_est, 0.0, 1.0)
					var f0 := 175.0 - 45.0 * prog + 18.0 * sin(TAU * 3.0 * (t + lt))
					phase = fmod(phase + f0 / rate, 1.0)
					var src := (2.0 * phase - 1.0)
					var env := clampf(lt / 0.015, 0.0, 1.0) * clampf((dur - lt) / 0.03, 0.0, 1.0)
					var voiced := f1.process(src) * 1.0 + f2.process(src) * 0.6 + f3.process(src) * 0.15
					var cons := 0.0
					if consonant and lt < 0.03:
						cons = f3.process(_noise()) * 0.8 * (1.0 - lt / 0.03)
					out[idx] += (voiced * env + cons) * 0.9
				t += dur
			t += rng.randf_range(0.05, 0.12)
		t += rng.randf_range(0.25, 0.45)
