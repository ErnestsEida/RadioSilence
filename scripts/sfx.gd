extends Node
## Procedurally synthesized sound effects (no audio files).

const RATE := 22050

var sounds := {}
var pool: Array = []
var idx := 0


func _ready() -> void:
	for i in 20:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	sounds["pistol"] = _make(_hit(0.25, 22.0, 0.5, 160.0, 0.5, rng))
	sounds["rifle"] = _make(_hit(0.18, 30.0, 0.6, 220.0, 0.35, rng))
	sounds["mg"] = _make(_hit(0.15, 35.0, 0.45, 140.0, 0.4, rng))
	sounds["enemy"] = _make(_hit(0.2, 26.0, 0.4, 180.0, 0.3, rng))
	sounds["cannon"] = _make(_hit(0.9, 5.0, 0.12, 55.0, 0.9, rng))
	sounds["explosion"] = _make(_hit(1.4, 3.2, 0.07, 40.0, 0.6, rng))
	sounds["hit"] = _make(_hit(0.07, 60.0, 0.3, 300.0, 0.5, rng))
	sounds["knife"] = _make(_whoosh(0.18, rng))
	sounds["alarm"] = _make(_siren(0.8))
	sounds["beep"] = _make(_tone(0.07, 1200.0))
	sounds["door"] = _make(_hit(1.6, 1.8, 0.03, 35.0, 0.8, rng))
	sounds["win"] = _make(_jingle())
	sounds["step"] = _make(_hit(0.06, 50.0, 0.15, 90.0, 0.4, rng))
	sounds["revolver"] = _make(_hit(0.35, 14.0, 0.45, 120.0, 0.6, rng))
	sounds["smg"] = _make(_hit(0.12, 40.0, 0.7, 260.0, 0.25, rng))
	sounds["shotgun"] = _make(_hit(0.5, 9.0, 0.3, 80.0, 0.8, rng))
	sounds["sniper"] = _make(_hit(0.7, 7.0, 0.85, 140.0, 0.5, rng))
	sounds["lmg"] = _make(_hit(0.17, 28.0, 0.4, 110.0, 0.5, rng))
	sounds["pickup"] = _make(_chime([880.0, 1320.0], 0.09))
	sounds["cash"] = _make(_chime([1046.5, 1318.5, 1568.0], 0.07))
	sounds["unlock"] = _make(_hit(0.4, 10.0, 0.2, 300.0, 0.7, rng))
	sounds["pz_ok"] = _make(_chime([660.0, 990.0], 0.1))
	sounds["pz_bad"] = _make(_tone(0.35, 140.0))
	sounds["clink"] = _make(_chime([2400.0], 0.05))
	sounds["hiss"] = _make(_whoosh(1.2, rng))
	sounds["switch"] = _make(_hit(0.08, 40.0, 0.7, 700.0, 0.3, rng))
	sounds["event"] = _make(_chime([392.0, 523.25, 392.0, 523.25], 0.16))
	sounds["whistle"] = _make(_whistle(1.1))
	sounds["thunder"] = _make(_hit(3.0, 1.1, 0.03, 30.0, 0.5, rng))
	sounds["plane"] = _make(_plane(4.0, rng))
	var wind := _make(_wind(4.0, rng))
	wind.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wind.loop_end = wind.data.size() / 2
	amb_player = AudioStreamPlayer.new()
	amb_player.stream = wind
	amb_player.bus = "Ambience"
	amb_player.volume_db = -8.0
	add_child(amb_player)
	var eng := _make(_engine_loop(1.0, rng))
	eng.loop_mode = AudioStreamWAV.LOOP_FORWARD
	eng.loop_end = int(1.0 * RATE)
	engine_player = AudioStreamPlayer.new()
	engine_player.stream = eng
	engine_player.bus = "SFX"
	add_child(engine_player)


var amb_player: AudioStreamPlayer
var engine_player: AudioStreamPlayer


func set_ambience(on: bool) -> void:
	if on and not amb_player.playing:
		amb_player.play()
	elif not on:
		amb_player.stop()
		engine_player.stop()


## level 0 = off, 1 = idle, 2 = driving
func set_engine(level: int) -> void:
	if level == 0:
		if engine_player.playing:
			engine_player.stop()
		return
	if not engine_player.playing:
		engine_player.play()
	engine_player.volume_db = -14.0 if level == 1 else -8.0
	engine_player.pitch_scale = 0.8 if level == 1 else 1.15


func play(sname: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not sounds.has(sname) or vol_db < -45.0:
		return
	var p: AudioStreamPlayer = pool[idx]
	idx = (idx + 1) % pool.size()
	p.stream = sounds[sname]
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.bus = "SFX"
	p.play()


func _wind(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		y += (rng.randf_range(-1.0, 1.0) - y) * 0.02
		out[i] = y * (0.6 + 0.4 * sin(TAU * t / dur) * sin(TAU * 3.0 * t / dur))
	# crossfade the ends so the loop is seamless
	var fade := int(0.3 * RATE)
	for i in fade:
		var a := float(i) / fade
		out[i] = out[i] * a + out[n - fade + i] * (1.0 - a)
	out.resize(n - fade)
	return out


func _engine_loop(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		y += (rng.randf_range(-1.0, 1.0) - y) * 0.08
		var thump := pow(absf(sin(PI * 30.0 * t)), 6.0)
		out[i] = y * 0.4 + thump * 0.6 + sin(TAU * 60.0 * t) * 0.3
	return out


func _make(samples: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.001
	for v in samples:
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] / peak * 0.9, -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


func _hit(dur: float, decay: float, lp: float, tone: float, tone_amt: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		y += (rng.randf_range(-1.0, 1.0) - y) * lp
		ph += TAU * tone * (1.0 - t * 0.4) / RATE
		out[i] = y * exp(-t * decay) + sin(ph) * tone_amt * exp(-t * decay * 0.7)
	return out


func _whoosh(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		y += (rng.randf_range(-1.0, 1.0) - y) * (0.1 + 0.4 * t / dur)
		out[i] = y * sin(PI * t / dur)
	return out


func _siren(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * (520.0 + 380.0 * sin(PI * t / dur)) / RATE
		out[i] = (0.6 * sin(ph) + 0.4 * signf(sin(ph))) * minf(1.0, (dur - t) * 10.0) * minf(1.0, t * 30.0)
	return out


## Falling-shell whistle: a pitch sliding downwards.
func _whistle(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * (1500.0 - 900.0 * t / dur) / RATE
		out[i] = sin(ph) * minf(1.0, t * 6.0) * minf(1.0, (dur - t) * 20.0) * 0.6
	return out


## Propeller plane passing overhead: throbbing drone that swells and fades.
func _plane(dur: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		y += (rng.randf_range(-1.0, 1.0) - y) * 0.05
		ph += TAU * (95.0 + 15.0 * (0.5 - t / dur)) / RATE
		var env := sin(PI * t / dur)
		out[i] = (sin(ph) * 0.5 + signf(sin(ph * 0.5)) * 0.15 + y * 0.5) * env * env
	return out


func _tone(dur: float, hz: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * hz * t) * minf(1.0, (dur - t) * 40.0)
	return out


func _jingle() -> PackedFloat32Array:
	var notes := [523.25, 659.25, 783.99, 1046.5]
	var out := PackedFloat32Array()
	for k in notes.size():
		var hz: float = notes[k]
		var dur := 0.16 if k < 3 else 0.7
		for i in int(dur * RATE):
			var t := float(i) / RATE
			out.append((sin(TAU * hz * t) + 0.3 * sin(TAU * hz * 2.0 * t)) * exp(-t * 3.0))
	return out


func _chime(notes: Array, each: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in notes.size():
		var hz: float = notes[k]
		var dur := each if k < notes.size() - 1 else each * 3.0
		for i in int(dur * RATE):
			var t := float(i) / RATE
			out.append(sin(TAU * hz * t) * exp(-t * 12.0) * minf(1.0, t * 400.0))
	return out
