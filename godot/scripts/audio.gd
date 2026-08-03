extends Node
## AUDIO: the one place that owns sound. Autoload `Audio`.
##
## Everything is synthesised (`Sfx`, `MusicGen`) — no assets, no import step —
## and the whole bank is built ONCE on a worker thread at startup. Until it is
## ready, every call here is a no-op: a menu that appears before its sounds do is
## fine, and a game that hitches for a second on launch because it is rendering
## PCM is not.
##
## THREE THINGS THIS EXISTS TO CENTRALISE:
##
##   1. VOICES ARE POOLED. A single AudioStreamPlayer cuts its own tail off on
##      the next call, and a repeater fires thirteen times a second while four
##      players do the same thing at once. Each pool round-robins.
##   2. LOUDNESS IS DECIDED HERE. Per-sound gain lives in the table below rather
##      than at the hundred call sites, so "the blaster is too loud" is one edit.
##   3. DISTANCE IS VOLUME, not panning (`play_at`). This is a four-way split
##      screen on one pair of speakers: a shot on the left of player 3's viewport
##      has no honest position in the stereo field, but "far away is quieter" is
##      true for everybody. Past HEARING it is not played at all — the same rule
##      `Weapon.IMPACT_VIEW_RANGE` and `Corpse.VIEW_RANGE` already follow.
##
## Volumes are per MACHINE and live in `Controls` next to the other game options.

const SFX_BUS := "SFX"
const MUSIC_BUS := "Music"
const VOICES := 10          # concurrent effects; a busy 4v4 peaks around six
const HEARING := 90.0       # metres past which an effect is not worth playing
const NEAR := 12.0          # ...and within which it plays at full volume
const MUSIC_FADE := 1.2     # seconds to cross from one track to the other

## Per-sound gain in dB and a pitch spread. The spread is what stops a repeater
## sounding like a machine: firing the identical sample thirteen times a second
## is instantly recognisable as one sample, and a few percent of random pitch
## either way is enough to break that up without changing the weapon's voice.
const MIX := {
	"hit":           {"db": -6.0, "spread": 0.04},
	"hit_head":      {"db": -4.0, "spread": 0.03},
	"kill":          {"db": -3.0, "spread": 0.02},
	"blaster":       {"db": -11.0, "spread": 0.07},
	"blaster_heavy": {"db": -9.0, "spread": 0.06},
	"plasma":        {"db": -11.0, "spread": 0.06},
	"bolter":        {"db": -9.0, "spread": 0.05},
	"gauss":         {"db": -11.0, "spread": 0.05},
	"melee_swing":   {"db": -12.0, "spread": 0.08},
	"melee_hit":     {"db": -8.0, "spread": 0.06},
	# The hum is the quietest row in the table on purpose: it is the only sound
	# that is ALWAYS PLAYING, so anything that has to be heard over it — every
	# shot, every hit — would otherwise be fighting it all match. No pitch spread
	# either; a loop whose pitch is re-rolled would drift against itself.
	"saber_hum":     {"db": -17.0, "spread": 0.0},
	"saber_on":      {"db": -7.0, "spread": 0.02},
	"saber_off":     {"db": -8.0, "spread": 0.02},
	"saber_swing":   {"db": -9.0, "spread": 0.05},
	"saber_clash":   {"db": -5.0, "spread": 0.05},
	"explosion":     {"db": -4.0, "spread": 0.08},
	"hurt":          {"db": -6.0, "spread": 0.05},
	"death":         {"db": -7.0, "spread": 0.04},
	"deploy":        {"db": -7.0, "spread": 0.02},
	"pickup":        {"db": -9.0, "spread": 0.02},
	"ui_move":       {"db": -16.0, "spread": 0.02},
	"ui_accept":     {"db": -12.0, "spread": 0.0},
	"ui_back":       {"db": -13.0, "spread": 0.0},
	"ui_deny":       {"db": -12.0, "spread": 0.0},
	"streak":        {"db": -5.0, "spread": 0.0},
	"victory":       {"db": -4.0, "spread": 0.0},
	"defeat":        {"db": -4.0, "spread": 0.0},
	"countdown":     {"db": -10.0, "spread": 0.0},
	"capture":       {"db": -7.0, "spread": 0.0},
}

## `Node.ready` is taken, hence the name: has the bank finished rendering?
var bank_ready := false

var _bank := {}
var _tracks := {}
var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var _music: Array[AudioStreamPlayer] = []   # two, so one can fade into the other
var _music_now := 0
var _playing := ""
var _wanted := ""                           # asked for before the bank was built
var _thread: Thread


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_buses()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = SFX_BUS
		add_child(p)
		_voices.append(p)
	_loop_token.resize(SUSTAINED)
	for i in SUSTAINED:
		var l := AudioStreamPlayer.new()
		l.bus = SFX_BUS
		add_child(l)
		_loops.append(l)
		_loop_at.append(Vector3.ZERO)
		_loop_sound.append("")
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = MUSIC_BUS
		add_child(m)
		_music.append(m)
	apply_volumes()
	# EVERYTHING IS BUILT OFF THE MAIN THREAD. Rendering the bank plus two
	# twenty-second tracks is a per-sample GDScript loop over a couple of million
	# samples; on the main thread that is a visible freeze on launch.
	_thread = Thread.new()
	_thread.start(_build_everything)


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


## IN TWO STAGES, because they are not equally urgent. The effects are 0.3 s of
## work and the player can be shooting within a few seconds of launch; the two
## music tracks are another 3.4 s and nobody misses a bar of music that starts
## when the menu has been up for a moment. Delivering them together would mean no
## gunfire for the first four seconds of a match started briskly.
func _build_everything() -> void:
	var bank := {}
	var builders := Sfx.bank()
	for name: String in builders:
		bank[name] = (builders[name] as Callable).call()
	_sounds_done.call_deferred(bank)
	_music_done.call_deferred({
		"menu": MusicGen.menu_track(),
		"battle": MusicGen.battle_track(),
	})


func _sounds_done(bank: Dictionary) -> void:
	_bank = bank
	bank_ready = true


func _music_done(tracks: Dictionary) -> void:
	_tracks = tracks
	if _wanted != "":
		var want := _wanted
		_wanted = ""
		_playing = ""
		play_music(want)


## The two buses exist so music and effects can be mixed against each other and
## turned down separately. Built in code rather than as a saved bus layout for
## the same reason everything else here is: one less asset to keep in step.
func _make_buses() -> void:
	for bus in [SFX_BUS, MUSIC_BUS]:
		if AudioServer.get_bus_index(bus) >= 0:
			continue
		var at := AudioServer.bus_count
		AudioServer.add_bus(at)
		AudioServer.set_bus_name(at, bus)
		AudioServer.set_bus_send(at, "Master")


## Push the saved volumes onto the buses. Called at startup and by the settings
## screen whenever they move.
func apply_volumes() -> void:
	_set_bus(SFX_BUS, Controls.sfx_volume())
	_set_bus(MUSIC_BUS, Controls.music_volume())


func _set_bus(bus: String, amount: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, amount <= 0.001)
	# A VOLUME SLIDER IS NOT LINEAR IN AMPLITUDE. Half way down a linear gain is
	# barely quieter; loudness follows the log, which is what dB is for.
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(amount, 0.0001, 1.0)))


## Play a sound with no position: UI, and anything that belongs to the match
## rather than to a place in it.
func play(sound: String, extra_db := 0.0) -> void:
	if not bank_ready or not _bank.has(sound):
		return
	var mix: Dictionary = MIX.get(sound, {"db": -8.0, "spread": 0.0})
	var voice := _voices[_next]
	_next = (_next + 1) % VOICES
	voice.stream = _bank[sound]
	voice.volume_db = float(mix["db"]) + extra_db
	var spread := float(mix["spread"])
	voice.pitch_scale = 1.0 + randf_range(-spread, spread)
	voice.play()


## Play a sound that happened SOMEWHERE, attenuated by how far the nearest human
## is from it and dropped entirely if that is far enough. Bots have no ears and
## no camera, so a firefight on the far side of the map is silent — which is also
## what stops two dozen AI saturating every voice in the pool.
func play_at(sound: String, at: Vector3, extra_db := 0.0) -> void:
	if not bank_ready:
		return
	var gap := _nearest_human(at)
	if gap > HEARING:
		return
	# Linear in dB with distance: -22 dB across the audible range, which reads as
	# a smooth fall rather than the inverse-square cliff a real 3D player gives.
	var k: float = clampf((gap - NEAR) / (HEARING - NEAR), 0.0, 1.0)
	play(sound, extra_db - 22.0 * k)


func _nearest_human(at: Vector3) -> float:
	var best := INF
	for c in GameState.combatants:
		if c is Player and is_instance_valid(c):
			best = minf(best, c.global_position.distance_to(at))
	return best if best < INF else 0.0


# --- SUSTAINED VOICES ---------------------------------------------------------
#
# A LOOP HAS AN OWNER, and that is what makes it unlike everything above. The
# pool at the top of this file is round-robin ONE-SHOTS: nothing can stop a voice
# because nothing ever needs to, and a new sound simply takes the oldest slot. A
# lightsaber hum is the first sound in this game that starts when something
# happens, runs for as long as that thing stays true, and has to be SILENCED when
# it stops being true.
#
# Same shape as the night impact-light pool, and for the same reason: a FIXED set
# of slots claimed with a TOKEN, so an owner whose slot has since been taken by
# somebody else quietly does nothing rather than switching that somebody off.
#
# Three slots, and NEAREST WINS. Four hums at a four-way couch with no panning is
# mud — the cap is what makes that impossible rather than merely unlikely, and
# taking the nearest is what makes the cap honest, since the one you can hear is
# the one worth spending a slot on.
const SUSTAINED := 3
const LOOP_SILENT_DB := -60.0   # past hearing: left running, not heard

var _loops: Array[AudioStreamPlayer] = []
var _loop_token := PackedInt64Array()
var _loop_at: Array[Vector3] = []
var _loop_sound: Array[String] = []
var _loop_seq := 0


## Start a looping sound at a position. Returns a CLAIM TOKEN to hand back to
## `move_loop` / `release_loop`, or 0 if every slot is busy with something nearer.
##
## A caller holding 0 has no voice and must carry on regardless — a saber whose
## hum was refused still ignites, still swings and still blocks. That is the whole
## reason this refuses rather than queues.
func claim_loop(sound: String, at: Vector3) -> int:
	if not bank_ready or not _bank.has(sound):
		return 0
	var slot := -1
	for i in SUSTAINED:
		if _loop_token[i] == 0:
			slot = i
			break
	if slot < 0:
		# All busy. Take the FARTHEST, and only if this one is nearer than it.
		var worst := _nearest_human(at)
		for i in SUSTAINED:
			var gap := _nearest_human(_loop_at[i])
			if gap > worst:
				worst = gap
				slot = i
		if slot < 0:
			return 0
	_loop_seq += 1
	_loop_token[slot] = _loop_seq
	_loop_at[slot] = at
	_loop_sound[slot] = sound
	var v := _loops[slot]
	v.stream = _bank[sound]
	v.pitch_scale = 1.0
	v.volume_db = _loop_db(sound, at)
	v.play()
	return _loop_seq


## Follow the thing making the noise, and optionally bend its pitch. Cheap enough
## for every physics frame: a distance and two writes, for at most SUSTAINED
## slots in the whole game however many bodies are holding one.
func move_loop(token: int, at: Vector3, pitch := 1.0) -> void:
	var slot := _loop_slot(token)
	if slot < 0:
		return
	_loop_at[slot] = at
	var v := _loops[slot]
	v.volume_db = _loop_db(_loop_sound[slot], at)
	v.pitch_scale = pitch


func release_loop(token: int) -> void:
	var slot := _loop_slot(token)
	if slot < 0:
		return
	_loop_token[slot] = 0
	_loop_sound[slot] = ""
	_loops[slot].stop()


## Belt and braces for the trap this project already has on record: an AUTOLOAD
## OUTLIVES THE SCENE. Every owner releases on the way out, so this should never
## have anything to do — but a hum left running across a map change would be
## audible for the rest of the session, and Main calls it on load for the price of
## one line.
func stop_all_loops() -> void:
	for i in SUSTAINED:
		_loop_token[i] = 0
		_loop_sound[i] = ""
		_loops[i].stop()


## Does this token still own a slot? The question an owner asks to find out
## whether it was quietly outbid, and what the test drives the pool through.
func has_loop(token: int) -> bool:
	return _loop_slot(token) >= 0


func loops_busy() -> int:
	var n := 0
	for i in SUSTAINED:
		if _loop_token[i] != 0:
			n += 1
	return n


## Which slot a token owns, or -1 if it has been taken since. A scan of three is
## cheaper than a dictionary and allocates nothing.
func _loop_slot(token: int) -> int:
	if token == 0:
		return -1
	for i in SUSTAINED:
		if _loop_token[i] == token:
			return i
	return -1


## A loop's gain: its MIX row, attenuated by distance on the same curve as
## `play_at`, and dropped to inaudible rather than STOPPED past hearing — so it
## comes back when somebody walks toward it without a restart, which on a loop
## would be an audible re-trigger.
func _loop_db(sound: String, at: Vector3) -> float:
	var gap := _nearest_human(at)
	if gap > HEARING:
		return LOOP_SILENT_DB
	var mix: Dictionary = MIX.get(sound, {"db": -8.0})
	var k: float = clampf((gap - NEAR) / (HEARING - NEAR), 0.0, 1.0)
	return float(mix["db"]) - 22.0 * k


## Cross to a track by name, or "" for silence. Repeating the current track does
## nothing, so callers can say what they want every time something changes
## without having to know what is already playing.
func play_music(track: String) -> void:
	if _tracks.is_empty():
		_wanted = track   # still rendering; picked up by _music_done
		return
	if track == _playing:
		return
	_playing = track
	var from := _music[_music_now]
	_music_now = 1 - _music_now
	var to := _music[_music_now]
	var tween := create_tween()
	tween.set_parallel(true)
	if from.playing:
		tween.tween_property(from, "volume_db", -40.0, MUSIC_FADE)
		tween.chain().tween_callback(from.stop)
	if track != "" and _tracks.has(track):
		to.stream = _tracks[track]
		to.volume_db = -40.0
		to.play()
		tween.tween_property(to, "volume_db", 0.0, MUSIC_FADE)


func stop_music() -> void:
	play_music("")
