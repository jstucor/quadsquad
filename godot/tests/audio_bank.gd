extends SceneTree
## THE SOUND BANK, CHECKED WITHOUT A SPEAKER. Every sound in this game is
## synthesised (`Sfx`, `MusicGen`), which means every sound can be wrong in ways
## a listener would notice and a compiler never will: silent because an envelope
## decayed before the oscillator started, clipped because four layers summed past
## 1.0, or missing from the mix table so it plays at a fallback gain nobody
## chose. All of that is visible in the PCM.
##
##   godot --headless --path godot --script tests/audio_bank.gd
##
## What it does NOT check is whether they sound good. Nothing can; that is what
## ears are for. It checks that they are audible, unclipped, mixed, and — for the
## two music tracks — that the loop joins without a click, which is the one
## defect that makes a generated loop unlistenable and is trivial to measure.

const MIN_PEAK := 0.24     # below this it is lost under gunfire
const MAX_JOIN_STEP := 0.05  # waveform step across the loop point

## A CLICK IS A DISCONTINUITY, NOT A NON-ZERO STEP, and telling those apart is the
## whole difficulty in measuring this. The step across the loop point was compared
## against zero, which silently assumes the waveform is FLAT there — true of the
## two music tracks, whose join happens to sit in a quiet bar, and false of
## anything that loops through its own steepest point.
##
## The saber hum is the case that exposed it. Its partials complete a whole number
## of cycles, so the phase runs dead straight through the join — and it joins AT A
## ZERO CROSSING, which is exactly where a sine moves fastest, so consecutive
## samples there differ by 0.08 with nothing whatsoever wrong. Measured against
## zero that reads as a click four times worse than the music's.
##
## So the join is measured against the buffer's OWN worst sample-to-sample move
## instead: a join that jumps no further than the waveform jumps anyway cannot be
## heard as an edge. The slack is for arithmetic, not for taste.
const JOIN_SLACK := 1.5


## The step across the loop point, and the largest ordinary step inside the
## buffer to judge it against.
func _join(s: AudioStreamWAV) -> Dictionary:
	var n := s.data.size() / 2
	var first: int = s.data.decode_s16(0)
	var last: int = s.data.decode_s16((n - 1) * 2)
	var worst := 0.0
	var prev: int = first
	for i in range(1, n):
		var v: int = s.data.decode_s16(i * 2)
		worst = maxf(worst, absf(v - prev) / 32768.0)
		prev = v
	return {
		"n": n,
		"step": absf(first - last) / 32768.0,
		"worst": worst,
	}


func _init() -> void:
	var bank := Sfx.bank()
	var fails: Array[String] = []
	print("== %d sounds ==" % bank.size())
	for name: String in bank:
		var s: AudioStreamWAV = (bank[name] as Callable).call()
		var n := s.data.size() / 2
		var peak := 0
		var sum := 0.0
		for i in n:
			var v: int = s.data.decode_s16(i * 2)
			peak = maxi(peak, absi(v))
			sum += absf(v) / 32768.0
		print("  %-14s %5.2f s  peak %.2f  level %.3f" % [
			name, float(n) / Sfx.RATE, peak / 32767.0, sum / maxf(n, 1)])
		if peak / 32767.0 < MIN_PEAK:
			fails.append("%s is too quiet to hear (peak %.2f)" % [
				name, peak / 32767.0])
		if peak >= 32767:
			fails.append("%s clips" % name)
		if not Audio.MIX.has(name):
			fails.append("%s has no MIX row, so it plays at a gain nobody chose"
				% name)
	for name: String in Audio.MIX:
		if not bank.has(name):
			fails.append("MIX names %s, which the bank does not build" % name)

	# A LOOPING EFFECT IS HELD TO THE SAME JOIN AS THE MUSIC, and it matters more:
	# a saber hum is up for as long as a blade is drawn, so a click at its loop
	# point is a tick every second for the whole fight.
	print("== looping effects ==")
	for name: String in ["saber_hum"]:
		var s: AudioStreamWAV = (bank[name] as Callable).call()
		var j := _join(s)
		print("  %-10s %5.2f s  join step %.4f  worst ordinary step %.4f" % [
			name, float(j["n"]) / Sfx.RATE, j["step"], j["worst"]])
		if s.loop_mode != AudioStreamWAV.LOOP_FORWARD or s.loop_end != j["n"]:
			fails.append("%s is not set to loop" % name)
		if j["step"] > j["worst"] * JOIN_SLACK:
			fails.append("%s clicks at the loop point (step %.4f against an ordinary %.4f) — a partial is no longer a whole number of cycles"
				% [name, j["step"], j["worst"]])

	print("== 2 tracks ==")
	for track: String in ["menu", "battle"]:
		var t: AudioStreamWAV = MusicGen.menu_track() if track == "menu" \
			else MusicGen.battle_track()
		var j := _join(t)
		print("  %-7s %5.1f s  %4d KB  join step %.4f  worst ordinary step %.4f" % [
			track, float(j["n"]) / Sfx.RATE, t.data.size() / 1024,
			j["step"], j["worst"]])
		if t.loop_mode != AudioStreamWAV.LOOP_FORWARD or t.loop_end != j["n"]:
			fails.append("the %s track is not set to loop" % track)
		# Both bounds, for a crossfaded join: it must be no worse than the track's
		# own slew AND actually quiet there, since the crossfade is what puts it in
		# a quiet bar and losing that is a defect the relative test would forgive.
		if j["step"] > MAX_JOIN_STEP or j["step"] > j["worst"] * JOIN_SLACK:
			fails.append("the %s track clicks at the loop point (step %.3f)" % [
				track, j["step"]])

	print("")
	if fails.is_empty():
		print("==== THE BANK IS SOUND ====")
	else:
		for f in fails:
			print("FAIL  %s" % f)
		print("==== %d FAILURES ====" % fails.size())
	quit()
