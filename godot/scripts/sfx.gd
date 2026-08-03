class_name Sfx
extends RefCounted
## EVERY SOUND IN THE GAME, SYNTHESISED IN CODE.
##
## The same argument the models make: no imported assets, no licence to track,
## no import step, and a sound is a table entry plus a few lines of arithmetic —
## so a new weapon gets a voice the way it gets a silhouette. It also keeps the
## repository honest, since a procedural game with a folder of downloaded WAVs is
## only procedural in the parts nobody hears.
##
## Everything renders to 16-bit mono PCM at RATE. Mono because this is a couch
## game: four players share one pair of speakers and a hit on the left of ONE of
## the four screens has no honest place in the stereo field. Distance is carried
## by volume (`Audio.play_at`), which is the part the ear actually uses here.
##
## The cost is paid ONCE, on a worker thread (`Audio`), never in a frame. The
## whole bank is a few hundred kilobytes of PCM.
##
## HOW THESE ARE BUILT, in one paragraph, because the parameters mean nothing
## without it: a sound is an envelope on a pitch on a timbre. The envelope is
## what makes it a hit rather than a note (fast attack, exponential decay); the
## PITCH SWEEP is what makes it read as an event rather than a beep (almost
## everything percussive falls in pitch as it decays, which is what a struck
## object does); and noise mixed under a tone is what makes it physical rather
## than electronic. The three of those are 90% of sound design.

const RATE := 22050


# --- the toolkit ---------------------------------------------------------------

static func buffer(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(RATE * seconds))
	return b


## An oscillator with a pitch sweep and an exponential decay, ADDED into the
## buffer so sounds are built by layering. `shape` 0 sine, 1 saw, 2 square — a
## sine is a body, a saw is a rasp, a square is a machine.
##
## The pitch sweep is exponential rather than linear because pitch is perceived
## in ratios: a linear fall from 800 to 100 spends most of its time sounding low.
static func osc(buf: PackedFloat32Array, at: float, dur: float,
		f0: float, f1: float, amp: float, decay: float, shape := 0) -> void:
	var start := int(at * RATE)
	var count := mini(int(dur * RATE), buf.size() - start)
	if count <= 0:
		return
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		var k := t / maxf(dur, 0.0001)
		var freq: float = f0 * pow(maxf(f1, 1.0) / maxf(f0, 1.0), k)
		phase += TAU * freq / RATE
		var v := 0.0
		match shape:
			1: v = fposmod(phase, TAU) / PI - 1.0                  # saw
			2: v = 1.0 if fposmod(phase, TAU) < PI else -1.0       # square
			_: v = sin(phase)
		buf[start + i] += v * amp * exp(-decay * t)


## Noise through a one-pole lowpass whose cutoff SWEEPS, which is the difference
## between a hiss and a whoosh, an impact and a splash. `cut0`/`cut1` are in Hz.
static func noise(buf: PackedFloat32Array, at: float, dur: float,
		amp: float, decay: float, cut0 := 8000.0, cut1 := 8000.0) -> void:
	var start := int(at * RATE)
	var count := mini(int(dur * RATE), buf.size() - start)
	if count <= 0:
		return
	var last := 0.0
	for i in count:
		var t := float(i) / RATE
		var k := t / maxf(dur, 0.0001)
		var cut: float = cut0 * pow(maxf(cut1, 20.0) / maxf(cut0, 20.0), k)
		var a: float = clampf(TAU * cut / RATE, 0.0, 1.0)
		last += a * (randf_range(-1.0, 1.0) - last)
		buf[start + i] += last * amp * exp(-decay * t)


## Internal damping on the pluck's feedback loop. The lowpass below has unity
## gain at DC, so without this a plucked line can accumulate a standing offset
## that never decays — inaudible itself, and a click when the sound ends.
const PLUCK_DAMP := 0.999


## A PLUCKED RESONANT STRING WITH A PITCH GLIDE — Karplus-Strong on a swept
## fractional delay line. This is the one thing the oscillators above cannot do,
## and it is the sound of a Star Wars blaster.
##
## The real DL-44 is Ben Burtt hitting the guy-wire of a radio tower, and a guy
## wire is a string: what your ear recognises is not the pitch fall on its own
## but the fall happening to a METALLIC, INHARMONIC RING. A swept sine has no
## ring, so it can only ever be a generic sci-fi zap however well the sweep is
## tuned — the same shape of mistake as tuning `metallic` on a weapon when what
## was missing was the albedo split.
##
## How it works, because the parameters are meaningless otherwise: a delay line
## is filled with NOISE (the strike) and then fed back into itself through a
## lowpass. The delay LENGTH is the pitch, and the lowpass is the string losing
## its high partials first, which is what every struck object does. Sweeping the
## length is what bends the note — read at a fractional offset and interpolate,
## or the glide steps between whole samples and buzzes.
##
## `tone` 0..1 is how fast those partials go: low is a dull thud, high is a long
## bright ring.
static func pluck(buf: PackedFloat32Array, at: float, dur: float,
		f0: float, f1: float, amp: float, decay: float, tone := 0.5) -> void:
	var start := int(at * RATE)
	var count := mini(int(dur * RATE), buf.size() - start)
	if count <= 0:
		return
	var len0: float = RATE / maxf(f0, 20.0)
	var len1: float = RATE / maxf(f1, 20.0)
	# The line has to hold the LONGEST delay the sweep will ask for, which is the
	# lowest pitch either end of it names.
	var size := int(maxf(len0, len1)) + 4
	var line := PackedFloat32Array()
	line.resize(size)
	for i in size:
		line[i] = randf_range(-1.0, 1.0)
	var w := 0
	var held := 0.0
	for i in count:
		var t := float(i) / RATE
		var k := t / maxf(dur, 0.0001)
		var delay: float = len0 * pow(len1 / len0, k)
		var read: float = float(w) - delay
		while read < 0.0:
			read += size
		var i0 := int(read)
		var frac: float = read - float(i0)
		var s0: float = line[i0 % size]
		var s1: float = line[(i0 + 1) % size]
		var v: float = s0 + (s1 - s0) * frac
		held += tone * (v - held)
		line[w] = held * PLUCK_DAMP
		w = (w + 1) % size
		buf[start + i] += v * amp * exp(-decay * t)


## Soft clipping. A hit that peaks at 1.0 and a hit that peaks at 3.0 and is then
## folded back are the same loudness and completely different sounds: the folded
## one is DENSE. This is what "punchy" is, and it is why the old hit tick — two
## clean sine partials — sounded thin however loud it was played.
static func saturate(buf: PackedFloat32Array, drive := 2.0) -> void:
	for i in buf.size():
		buf[i] = tanh(buf[i] * drive)


## Cheap tail. Not a reverb — a handful of decaying repeats, which is enough to
## put a sound in a place rather than in a vacuum, and costs one pass.
static func echo(buf: PackedFloat32Array, delay: float, feedback: float,
		taps := 3) -> void:
	var step := int(delay * RATE)
	if step <= 0:
		return
	var gain := feedback
	for tap in taps:
		var offset := step * (tap + 1)
		for i in range(buf.size() - 1, offset - 1, -1):
			buf[i] += buf[i - offset] * gain
		gain *= feedback


## Fade the last `seconds` to nothing. Any sound that ends on a non-zero sample
## clicks, and a click at the end of every shot is audible as a rattle when
## thirteen of them a second overlap.
static func fade_out(buf: PackedFloat32Array, seconds := 0.01) -> void:
	var n := mini(int(seconds * RATE), buf.size())
	for i in n:
		buf[buf.size() - n + i] *= 1.0 - float(i) / n


static func to_stream(buf: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, roundi(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = buf.size()
	return s


# --- the bank ------------------------------------------------------------------

## Name -> builder. Anything that wants a sound asks `Audio.play("name")`, so
## this table is the whole inventory and adding a voice is one row.
static func bank() -> Dictionary:
	return {
		"hit": _hit,
		"hit_head": _hit_head,
		"kill": _kill,
		"blaster": _blaster,
		"blaster_heavy": _blaster_heavy,
		"plasma": _plasma,
		"bolter": _bolter,
		"gauss": _gauss,
		"melee_swing": _melee_swing,
		"melee_hit": _melee_hit,
		"saber_hum": _saber_hum,
		"saber_on": _saber_on,
		"saber_off": _saber_off,
		"saber_swing": _saber_swing,
		"saber_clash": _saber_clash,
		"explosion": _explosion,
		"hurt": _hurt,
		"death": _death,
		"deploy": _deploy,
		"pickup": _pickup,
		"ui_move": _ui_move,
		"ui_accept": _ui_accept,
		"ui_back": _ui_back,
		"ui_deny": _ui_deny,
		"victory": _victory,
		"defeat": _defeat,
		"countdown": _countdown,
		"capture": _capture,
	}


## THE HIT MARKER, which is the sound this game most needed to get right: it is
## the only feedback that a shot landed, it fires hundreds of times a match, and
## the old one was two clean sine partials — a beep, thin at any volume.
##
## Three layers, which is what "satisfying" is made of: a bright TRANSIENT so it
## cuts through gunfire, a short pitched BODY under it so it has weight, and a
## sliver of noise so it sounds like something being struck rather than a tone
## generator. Saturated, which is what makes it dense rather than merely loud.
static func _hit() -> AudioStreamWAV:
	var b := buffer(0.10)
	osc(b, 0.0, 0.05, 2400.0, 1300.0, 0.55, 90.0)     # transient
	osc(b, 0.0, 0.09, 420.0, 190.0, 0.75, 45.0)       # body, falling
	noise(b, 0.0, 0.03, 0.35, 120.0, 6000.0, 1200.0)  # the strike itself
	saturate(b, 2.2)
	fade_out(b)
	return to_stream(b)


## A headshot is not the body hit played higher — that is what the pitch_scale
## trick did, and it sounded like the same beep on a different note. It is a
## harder, more metallic strike: the same transient with a ringing partial pair
## behind it, detuned so they beat against each other.
static func _hit_head() -> AudioStreamWAV:
	var b := buffer(0.16)
	osc(b, 0.0, 0.05, 3300.0, 2100.0, 0.5, 80.0)
	osc(b, 0.0, 0.14, 1810.0, 1780.0, 0.30, 26.0)   # ring, and...
	osc(b, 0.0, 0.14, 1867.0, 1840.0, 0.26, 26.0)   # ...its detuned twin
	osc(b, 0.0, 0.07, 520.0, 260.0, 0.55, 55.0)
	noise(b, 0.0, 0.02, 0.40, 150.0, 9000.0, 3000.0)
	saturate(b, 2.4)
	fade_out(b)
	return to_stream(b)


## A KILL IS A DIFFERENT EVENT, so it is a different sound rather than the same
## click pitched down: a hit, and then a heavy descending confirm with a tail on
## it. The tail is the part that makes it feel like a conclusion.
static func _kill() -> AudioStreamWAV:
	var b := buffer(0.55)
	osc(b, 0.0, 0.06, 2600.0, 1500.0, 0.45, 80.0)
	osc(b, 0.0, 0.30, 300.0, 90.0, 0.85, 12.0)        # the drop
	osc(b, 0.02, 0.26, 600.0, 180.0, 0.35, 14.0, 2)   # square, for grit
	noise(b, 0.0, 0.05, 0.30, 70.0, 7000.0, 800.0)
	echo(b, 0.075, 0.28)
	saturate(b, 2.0)
	fade_out(b, 0.05)
	return to_stream(b)


## THE BLASTER, WHICH IS A STRUCK WIRE AND NOT A SWEPT TONE. The pitch fall was
## always right and was never the whole thing: this was a swept saw plus a
## transient, and a swept saw has no RING in it, so it read as a generic zap. The
## body is a `pluck` now — see the note there — and the sweep is that pluck's
## glide rather than an oscillator's.
##
## The layers on top are unchanged in purpose: a crack so it cuts through a
## firefight, a sliver of noise so it is a physical discharge rather than a tone,
## and the echo so it happens somewhere.
static func _blaster() -> AudioStreamWAV:
	var b := buffer(0.22)
	pluck(b, 0.0, 0.20, 1650.0, 255.0, 0.80, 13.0, 0.62)
	osc(b, 0.0, 0.09, 4200.0, 1100.0, 0.16, 48.0)
	noise(b, 0.0, 0.035, 0.24, 100.0, 9000.0, 1800.0)
	echo(b, 0.055, 0.22)
	saturate(b, 1.8)
	fade_out(b, 0.02)
	return to_stream(b)


## The same event with more mass behind it: lower, longer, and with a real low
## end under it, for the HMG, the rotary and the heavy repeater. A thicker wire
## on a longer fall, plus a sub the small one does not have.
static func _blaster_heavy() -> AudioStreamWAV:
	var b := buffer(0.30)
	pluck(b, 0.0, 0.26, 1050.0, 120.0, 0.85, 9.0, 0.55)
	osc(b, 0.0, 0.16, 190.0, 68.0, 0.50, 22.0)
	osc(b, 0.0, 0.07, 3000.0, 800.0, 0.14, 52.0)
	noise(b, 0.0, 0.07, 0.30, 55.0, 5000.0, 700.0)
	echo(b, 0.07, 0.3)
	saturate(b, 2.1)
	fade_out(b, 0.03)
	return to_stream(b)


## Covenant plasma. It was a hot fizz that swelled and spat — accurate to the
## fiction and wrong for the game: with no transient on the front it did not read
## as a WEAPON DISCHARGING, it read as an appliance, and in a firefight it
## disappeared under everything with a crack in it.
##
## So it is built like the other guns now — TRANSIENT, BODY, character — and only
## the character is alien. The crack is short and bright, there is a real low
## report under it, and the plasma is what is left ringing: two beating partials
## that decay fast instead of a swell that never arrives. Still unmistakably not
## a bullet; now unmistakably a shot.
static func _plasma() -> AudioStreamWAV:
	var b := buffer(0.26)
	noise(b, 0.0, 0.03, 0.75, 110.0, 9000.0, 2500.0)   # the crack
	osc(b, 0.0, 0.14, 260.0, 90.0, 0.60, 26.0)         # the report under it
	osc(b, 0.0, 0.16, 1250.0, 620.0, 0.34, 18.0)       # plasma, and...
	osc(b, 0.0, 0.16, 1262.0, 610.0, 0.30, 18.0)       # ...its beating twin
	noise(b, 0.01, 0.16, 0.22, 22.0, 4000.0, 900.0)    # the tail of the discharge
	saturate(b, 2.0)
	fade_out(b, 0.03)
	return to_stream(b)


## A bolter fires a rocket-propelled shell, so it is a BANG and not a beam: a
## noise-heavy report with a low thump and no pitch sweep to speak of.
static func _bolter() -> AudioStreamWAV:
	var b := buffer(0.34)
	noise(b, 0.0, 0.10, 0.75, 40.0, 6000.0, 400.0)
	osc(b, 0.0, 0.18, 150.0, 60.0, 0.70, 20.0)
	osc(b, 0.0, 0.05, 900.0, 300.0, 0.30, 70.0, 2)
	echo(b, 0.09, 0.32)
	saturate(b, 2.6)
	fade_out(b, 0.03)
	return to_stream(b)


## Necron gauss: still the family that sounds like it is doing something to the
## TARGET rather than to the air — the rising whine is the whole idea — but it now
## fires on a hard percussive front instead of winding up from nothing. Same
## treatment as the plasma and for the same reason: a gun announces itself in the
## first ten milliseconds or it does not read as a gun.
static func _gauss() -> AudioStreamWAV:
	var b := buffer(0.30)
	noise(b, 0.0, 0.02, 0.70, 140.0, 9000.0, 3000.0)   # snap
	osc(b, 0.0, 0.10, 220.0, 80.0, 0.55, 34.0)         # report
	osc(b, 0.0, 0.22, 480.0, 2600.0, 0.34, 11.0, 2)    # the flaying whine
	osc(b, 0.0, 0.22, 484.0, 2560.0, 0.26, 11.0, 1)
	saturate(b, 1.9)
	fade_out(b, 0.04)
	return to_stream(b)


## Air moving round a blade. Nothing but filtered noise with a slow swell — the
## sweep of the cutoff IS the swing.
static func _melee_swing() -> AudioStreamWAV:
	var b := buffer(0.34)
	# Loud at source and shaped down, rather than quiet at source: the swell
	# below multiplies most of this away, and a whoosh that peaks at 0.17 is
	# inaudible under a firefight however generous its mix row is.
	noise(b, 0.0, 0.30, 1.6, 4.0, 400.0, 3500.0)
	for i in b.size():   # swell in, so it does not start at full pelt
		var k := float(i) / b.size()
		b[i] *= sin(PI * clampf(k * 1.15, 0.0, 1.0))
	saturate(b, 1.4)
	fade_out(b, 0.05)
	return to_stream(b)


# --- the lightsaber ------------------------------------------------------------
#
# THE MOST RECOGNISABLE SOUND IN CINEMA, and until now this game did not have it:
# every blade in every universe shared `melee_swing` (filtered noise) and
# `melee_hit` (a clang), so a lightsaber, a chainsword, an ork choppa and a
# Covenant energy sword were one whoosh, and a Jedi drew a metre of plasma in
# total silence.
#
# It is FOUR sounds and not one, because a saber is a thing that is switched on
# and then keeps existing — which is also what makes it the first sound in this
# game with a duration nobody knows in advance. See Audio's sustained voices.
#
# Which blades get it is not a new table: `blade_energy` 0 already separates
# steel from plasma for the geometry (Weapon.BLADE_LOOK_KEYS), so the audio asks
# that same key. A chainsword still whooshes and clangs, exactly as it should.

## The hum's fundamental. Everything else here is built against it so the
## ignition ARRIVES at the pitch the loop then holds.
const SABER_PITCH := 104.0

## THE HUM LOOPS SEAMLESSLY BY CONSTRUCTION, not by crossfade. It is exactly one
## second long and every partial is an INTEGER frequency, so each completes a
## whole number of cycles in the buffer and the last sample runs into the first at
## the same phase and the same slope. `MusicGen._seamless` has to crossfade
## because its material is arbitrary; this does not, and a join that is exact
## beats a join that is hidden.
##
## Note there is deliberately no noise layer and no `fade_out`: both would be
## random or zero at the ends, which is precisely the click the loop must not
## have. The buzz comes from `saturate` folding the partials instead.
const SABER_HUM_SECONDS := 1.0


## Two close partials BEAT against each other at their difference — five times a
## second — and that slow undulation is most of what makes the hum sound ALIVE
## rather than like a held organ note. It is the same reason the headshot tick
## uses a detuned pair.
static func _saber_hum() -> AudioStreamWAV:
	var b := buffer(SABER_HUM_SECONDS)
	var d := SABER_HUM_SECONDS
	osc(b, 0.0, d, 104.0, 104.0, 0.42, 0.0)
	osc(b, 0.0, d, 109.0, 109.0, 0.36, 0.0)   # the beat against it
	osc(b, 0.0, d, 208.0, 208.0, 0.20, 0.0)
	osc(b, 0.0, d, 311.0, 311.0, 0.09, 0.0)
	osc(b, 0.0, d, 415.0, 415.0, 0.05, 0.0)
	saturate(b, 1.7)
	return to_stream(b, true)


## Ignition. A snap of escaping noise, then a rise that LANDS on the hum's own
## pitch — the loop takes over from where this arrives, so the two have to agree
## about what note the blade is. A whine falls in behind it.
static func _saber_on() -> AudioStreamWAV:
	var b := buffer(0.44)
	noise(b, 0.0, 0.07, 0.60, 34.0, 1800.0, 7000.0)
	osc(b, 0.0, 0.32, 38.0, SABER_PITCH, 0.55, 2.6)
	osc(b, 0.0, 0.24, 950.0, 208.0, 0.28, 8.0)
	osc(b, 0.03, 0.36, 109.0, 109.0, 0.20, 1.4)
	saturate(b, 1.7)
	fade_out(b, 0.05)
	return to_stream(b)


## Retraction: the same event backwards and quicker. The pitch falls off the
## bottom rather than settling, because nothing is left running.
static func _saber_off() -> AudioStreamWAV:
	var b := buffer(0.34)
	osc(b, 0.0, 0.26, SABER_PITCH, 30.0, 0.62, 4.5)
	osc(b, 0.0, 0.20, 250.0, 58.0, 0.30, 9.0)
	noise(b, 0.0, 0.05, 0.34, 50.0, 5200.0, 700.0)
	saturate(b, 1.6)
	fade_out(b, 0.05)
	return to_stream(b)


## A SABER SWING IS NOT AIR, IT IS THE HUM BEING MOVED. `melee_swing` is filtered
## noise, which is right for a length of steel and wrong here: what you hear in
## the films is the blade's own pitch bending UP as it comes at you and back DOWN
## as it passes. Two overlapping sweeps in opposite directions is that doppler —
## one oscillator can only bend one way.
static func _saber_swing() -> AudioStreamWAV:
	var b := buffer(0.40)
	osc(b, 0.0, 0.18, 95.0, 168.0, 0.44, 1.2)    # approaching
	osc(b, 0.15, 0.24, 168.0, 88.0, 0.44, 1.6)   # ...and past
	osc(b, 0.0, 0.18, 208.0, 350.0, 0.20, 1.6)
	osc(b, 0.15, 0.22, 350.0, 190.0, 0.20, 2.2)
	noise(b, 0.0, 0.30, 0.40, 4.0, 500.0, 2400.0)
	for i in b.size():   # swell, so the blade passes rather than starting on you
		var k := float(i) / b.size()
		b[i] *= sin(PI * clampf(k * 1.1, 0.0, 1.0))
	saturate(b, 1.6)
	fade_out(b, 0.04)
	return to_stream(b)


## BLADE ON BOLT. Deliberately not the `melee_hit` clang: stopping a blaster
## round is an ELECTRICAL crack with the blade flaring behind it, not two pieces
## of metal meeting. The pluck is what gives the crack a body — a deflection
## rings.
static func _saber_clash() -> AudioStreamWAV:
	var b := buffer(0.34)
	noise(b, 0.0, 0.04, 0.70, 70.0, 11000.0, 2500.0)
	osc(b, 0.0, 0.06, 3100.0, 900.0, 0.45, 60.0)
	pluck(b, 0.0, 0.22, 1250.0, 380.0, 0.50, 14.0, 0.5)
	osc(b, 0.0, 0.20, 108.0, SABER_PITCH, 0.32, 6.0)   # the blade flaring
	echo(b, 0.045, 0.20)
	saturate(b, 2.1)
	fade_out(b, 0.03)
	return to_stream(b)


## Metal on metal: inharmonic partials, which is what separates a bell (tuned)
## from a clang (not). The ratios below are deliberately not integers.
static func _melee_hit() -> AudioStreamWAV:
	var b := buffer(0.45)
	osc(b, 0.0, 0.40, 1240.0, 1200.0, 0.35, 9.0)
	osc(b, 0.0, 0.36, 2107.0, 2060.0, 0.24, 12.0)
	osc(b, 0.0, 0.30, 3491.0, 3400.0, 0.16, 16.0)
	osc(b, 0.0, 0.10, 320.0, 140.0, 0.5, 40.0)
	noise(b, 0.0, 0.03, 0.5, 140.0, 9000.0, 2000.0)
	saturate(b, 1.9)
	fade_out(b, 0.05)
	return to_stream(b)


## A blast is mostly LOW noise plus a pitch drop, and the tail is what sells the
## size of it — a short explosion is a firecracker whatever its amplitude.
static func _explosion() -> AudioStreamWAV:
	var b := buffer(1.10)
	noise(b, 0.0, 0.90, 0.85, 5.0, 3000.0, 120.0)
	osc(b, 0.0, 0.55, 160.0, 35.0, 0.90, 7.0)
	noise(b, 0.0, 0.06, 0.60, 60.0, 9000.0, 2000.0)   # the crack on the front
	echo(b, 0.13, 0.35, 4)
	saturate(b, 2.2)
	fade_out(b, 0.15)
	return to_stream(b)


## Taking a round yourself: a dull thud with no brightness at all, because it is
## information about YOU and must never be mistaken for the hit marker.
static func _hurt() -> AudioStreamWAV:
	var b := buffer(0.30)
	osc(b, 0.0, 0.22, 220.0, 70.0, 0.8, 16.0)
	noise(b, 0.0, 0.10, 0.35, 40.0, 900.0, 200.0)
	saturate(b, 1.6)
	fade_out(b, 0.04)
	return to_stream(b)


static func _death() -> AudioStreamWAV:
	var b := buffer(0.90)
	osc(b, 0.0, 0.80, 320.0, 60.0, 0.55, 4.0, 1)
	osc(b, 0.0, 0.60, 160.0, 40.0, 0.45, 5.0)
	noise(b, 0.0, 0.30, 0.25, 12.0, 1800.0, 200.0)
	echo(b, 0.16, 0.3)
	fade_out(b, 0.12)
	return to_stream(b)


## Dropping into the match: a rising whoosh that lands on a thump.
static func _deploy() -> AudioStreamWAV:
	var b := buffer(0.75)
	noise(b, 0.0, 0.45, 0.40, 2.0, 300.0, 4000.0)
	osc(b, 0.40, 0.30, 180.0, 55.0, 0.85, 12.0)
	noise(b, 0.40, 0.10, 0.35, 40.0, 4000.0, 300.0)
	saturate(b, 1.8)
	fade_out(b, 0.06)
	return to_stream(b)


static func _pickup() -> AudioStreamWAV:
	var b := buffer(0.30)
	osc(b, 0.0, 0.10, 880.0, 880.0, 0.35, 22.0)
	osc(b, 0.07, 0.16, 1320.0, 1320.0, 0.35, 18.0)
	osc(b, 0.14, 0.16, 1760.0, 1760.0, 0.30, 16.0)
	fade_out(b, 0.03)
	return to_stream(b)


## THE UI SET. Quiet, short and unpitched enough not to fight the music: these
## fire on every cursor move on a screen four people are driving at once.
static func _ui_move() -> AudioStreamWAV:
	var b := buffer(0.06)
	osc(b, 0.0, 0.05, 1400.0, 1150.0, 0.30, 90.0)
	noise(b, 0.0, 0.01, 0.12, 200.0, 9000.0, 4000.0)
	fade_out(b, 0.01)
	return to_stream(b)


static func _ui_accept() -> AudioStreamWAV:
	var b := buffer(0.24)
	osc(b, 0.0, 0.10, 660.0, 660.0, 0.35, 26.0)
	osc(b, 0.06, 0.16, 990.0, 990.0, 0.35, 20.0)
	fade_out(b, 0.02)
	return to_stream(b)


static func _ui_back() -> AudioStreamWAV:
	var b := buffer(0.22)
	osc(b, 0.0, 0.10, 700.0, 700.0, 0.32, 30.0)
	osc(b, 0.05, 0.14, 440.0, 440.0, 0.32, 24.0)
	fade_out(b, 0.02)
	return to_stream(b)


static func _ui_deny() -> AudioStreamWAV:
	var b := buffer(0.20)
	osc(b, 0.0, 0.16, 180.0, 140.0, 0.45, 14.0, 2)
	fade_out(b, 0.03)
	return to_stream(b)


## A rising minor triad with the fifth held: the shortest thing that reads as
## "you won" without being a jingle.
static func _victory() -> AudioStreamWAV:
	var b := buffer(1.60)
	var notes := [261.63, 392.00, 523.25, 783.99]
	for i in notes.size():
		var at := i * 0.13
		osc(b, at, 1.2, notes[i], notes[i], 0.30, 2.2)
		osc(b, at, 0.9, notes[i] * 2.0, notes[i] * 2.0, 0.12, 3.0, 1)
	echo(b, 0.22, 0.3)
	fade_out(b, 0.25)
	return to_stream(b)


static func _defeat() -> AudioStreamWAV:
	var b := buffer(1.80)
	var notes := [392.00, 311.13, 261.63, 196.00]
	for i in notes.size():
		var at := i * 0.18
		osc(b, at, 1.3, notes[i], notes[i] * 0.995, 0.32, 1.9, 1)
	echo(b, 0.26, 0.3)
	fade_out(b, 0.3)
	return to_stream(b)


## The pre-match count. One blip a second, and the last one is the go.
static func _countdown() -> AudioStreamWAV:
	var b := buffer(0.28)
	osc(b, 0.0, 0.22, 520.0, 520.0, 0.35, 14.0)
	fade_out(b, 0.03)
	return to_stream(b)


## A command post changing hands: a low bell, so it reads across a firefight.
static func _capture() -> AudioStreamWAV:
	var b := buffer(1.30)
	osc(b, 0.0, 1.10, 196.00, 196.00, 0.40, 3.0)
	osc(b, 0.0, 1.00, 293.66, 293.66, 0.26, 3.4)
	osc(b, 0.0, 0.70, 587.33, 587.33, 0.14, 5.0)
	echo(b, 0.19, 0.32)
	fade_out(b, 0.2)
	return to_stream(b)
