class_name MusicGen
extends RefCounted
## THE SCORE, GENERATED. Two looping tracks — a menu piece and a battle piece —
## built out of the same oscillators the sound effects use (`Sfx`).
##
## Written as a SEQUENCE rather than as a texture, because the thing that makes
## music sound composed instead of generated is that its parts agree: one key,
## one chord progression, and every voice reading from it. The key is D minor
## with a flattened second on the tension chord — near enough Phrygian to sound
## military without being a pastiche of anything in particular.
##
## Four voices, which is as many as this synthesis can keep distinct:
##
##   BASS    saw through the oscillator's own decay: the root, on the beat.
##   PAD     two detuned sines an octave apart, held across the whole bar. This
##           is the voice that makes it music rather than a drum loop, and it is
##           also the cheapest one to render.
##   LEAD    a square arpeggio picking out the chord — quiet in the menu, and in
##           the battle track it is the part that carries the tune.
##   DRUMS   kick (a sine dropping 120 -> 45 Hz), snare (noise plus a pitched
##           body) and hat (a very short bright noise burst).
##
## LOOP LENGTH is a compromise measured in memory: 16-bit mono at 22050 Hz costs
## 44 KB a second, so eight bars at 96 BPM is 20 seconds and about 900 KB per
## track. Long enough not to nag, small enough to hold two of them.
##
## Rendered on a worker thread by `Audio` — a per-sample GDScript loop over a
## million samples is not something to do inside a frame.

const RATE := Sfx.RATE

## Semitone offsets from the root, per bar, for the eight-bar loop: i, i, bII,
## i, iv, i, bVII, V. The bII is the Phrygian colour and the V at the end is what
## makes it want to come round again.
const PROGRESSION := [0, 0, 1, 0, 5, 0, 10, 7]
const MENU_ROOT := 55.00     # A1, low and calm
const BATTLE_ROOT := 73.42   # D2, up a fourth and more urgent


static func note(semitones: float, root: float) -> float:
	return root * pow(2.0, semitones / 12.0)


## MENU: slow, wide, mostly pad. Nothing percussive at all — a menu track with a
## beat starts a clock in the player's head, and this screen is where four people
## are arguing about teams.
static func menu_track() -> AudioStreamWAV:
	var bpm := 62.0
	var bar := 240.0 / bpm            # four beats
	var buf := Sfx.buffer(bar * PROGRESSION.size())
	for i in PROGRESSION.size():
		var at := i * bar
		var root: float = note(PROGRESSION[i], MENU_ROOT)
		# Pad: root, fifth and octave, each detuned against a twin so the chord
		# breathes instead of sitting still.
		for interval: float in [0.0, 7.0, 12.0]:
			var f := note(interval, root)
			Sfx.osc(buf, at, bar * 1.05, f, f, 0.16, 0.9)
			Sfx.osc(buf, at, bar * 1.05, f * 1.004, f * 1.004, 0.13, 0.9)
		# Bass on the downbeat only.
		Sfx.osc(buf, at, bar * 0.6, root * 0.5, root * 0.5, 0.28, 2.0, 1)
		# A sparse three-note figure over the second half of every other bar.
		if i % 2 == 1:
			var scale := [12.0, 15.0, 19.0]
			for k in scale.size():
				var f2 := note(scale[k], root)
				Sfx.osc(buf, at + bar * 0.5 + k * bar * 0.14, bar * 0.4,
					f2, f2, 0.10, 3.5)
	Sfx.echo(buf, 0.31, 0.24)
	_normalise(buf, 0.72)
	_seamless(buf)
	return Sfx.to_stream(buf, true)


## BATTLE: the same progression at twice the pace with drums and a lead. Mixed
## deliberately quiet and mid-heavy — it plays UNDER four people shouting and a
## firefight, and anything with real low end in it eats the explosions.
static func battle_track() -> AudioStreamWAV:
	var bpm := 104.0
	var beat := 60.0 / bpm
	var bar := beat * 4.0
	var buf := Sfx.buffer(bar * PROGRESSION.size())
	for i in PROGRESSION.size():
		var at := i * bar
		var root: float = note(PROGRESSION[i], BATTLE_ROOT)
		# Driving eighth-note bass: the engine of the whole track.
		for eighth in 8:
			var t := at + eighth * beat * 0.5
			var f: float = root * 0.5
			if eighth == 6:
				f = note(7.0, root) * 0.5   # a push into the next bar
			Sfx.osc(buf, t, beat * 0.45, f, f, 0.34, 7.0, 1)
		# Pad, quieter than the menu's and an octave up so it does not fight the
		# bass for the same space.
		for interval: float in [0.0, 7.0]:
			var pf := note(interval + 12.0, root)
			Sfx.osc(buf, at, bar * 1.05, pf, pf, 0.09, 1.1)
			Sfx.osc(buf, at, bar * 1.05, pf * 1.005, pf * 1.005, 0.07, 1.1)
		# Lead: a four-note arpeggio, with the last bar of each half answering.
		var figure := [0.0, 7.0, 12.0, 15.0] if i % 4 != 3 else [15.0, 12.0, 7.0, 3.0]
		for k in figure.size():
			var lf := note(figure[k] + 12.0, root)
			Sfx.osc(buf, at + k * beat, beat * 0.9, lf, lf, 0.11, 5.0, 2)
		# Kit. Kick on 1 and 3, snare on 2 and 4, hats on the eighths.
		for k in [0, 2]:
			_kick(buf, at + k * beat)
		for s in [1, 3]:
			_snare(buf, at + s * beat)
		for h in 8:
			_hat(buf, at + h * beat * 0.5, 0.05 if h % 2 == 0 else 0.032)
	Sfx.echo(buf, 0.19, 0.16)
	Sfx.saturate(buf, 1.4)
	_normalise(buf, 0.80)
	_seamless(buf)
	return Sfx.to_stream(buf, true)


static func _kick(buf: PackedFloat32Array, at: float) -> void:
	Sfx.osc(buf, at, 0.22, 120.0, 45.0, 0.55, 22.0)
	Sfx.noise(buf, at, 0.012, 0.20, 120.0, 4000.0, 800.0)


static func _snare(buf: PackedFloat32Array, at: float) -> void:
	Sfx.noise(buf, at, 0.16, 0.28, 26.0, 6000.0, 1400.0)
	Sfx.osc(buf, at, 0.09, 210.0, 160.0, 0.22, 40.0)


static func _hat(buf: PackedFloat32Array, at: float, amp: float) -> void:
	Sfx.noise(buf, at, 0.05, amp, 90.0, 9000.0, 7000.0)


## Bring the peak to `peak` rather than trusting the sum of a dozen voices to
## land somewhere sensible. Without this the two tracks are mixed by accident.
static func _normalise(buf: PackedFloat32Array, peak: float) -> void:
	var loudest := 0.0
	for v in buf:
		loudest = maxf(loudest, absf(v))
	if loudest < 0.0001:
		return
	var gain := peak / loudest
	for i in buf.size():
		buf[i] *= gain


## A LOOP THAT CLICKS IS A LOOP NOBODY CAN LISTEN TO TWICE. The tail of the last
## bar does not line up with the head of the first, so the join is a step in the
## waveform — audible as a tick every twenty seconds, which is worse than no
## music at all. Crossfading the last moments over the start removes it, and
## takes the decaying tails of the final chord round to where they belong.
static func _seamless(buf: PackedFloat32Array, seconds := 0.35) -> void:
	var n := mini(int(seconds * RATE), buf.size() / 4)
	for i in n:
		var k := float(i) / n
		var tail := buf[buf.size() - n + i]
		buf[i] = buf[i] * k + tail * (1.0 - k)
	for i in n:
		buf[buf.size() - n + i] *= 1.0 - float(i) / n
