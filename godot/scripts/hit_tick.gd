extends Node
## The hit confirmation click. One short procedural tick, generated in code like
## everything else in this game — no audio asset, no import step.
##
## Pitch carries the detail rather than three separate sounds: a body hit is the
## click as generated, a headshot is the same click sharpened, and a kill is a
## second, lower click chased in behind the first.
##
## Voices are pooled because a single AudioStreamPlayer cuts its own tail off on
## the next shot, and with four players sharing one speaker there are genuinely
## four streams of hits arriving at once.
##
## Local co-op caveat: sound is NOT split per player the way the screen is, so
## every tick is audible to the whole couch. There is no per-viewport audio bus
## to route it to, and a 55 ms click is short enough not to be confusing.

const RATE := 22050
const LENGTH := 0.055   # seconds; long enough to hear, short enough to overlap
const TONE_A := 1500.0  # the two partials that make it read as a "tick" rather
const TONE_B := 2600.0  # than a beep
const DECAY := 70.0     # exponential envelope; e^-70t is silent by ~50 ms
const ATTACK := 0.0018  # a sliver of noise on the front, for the transient
const VOICES := 6

const HEADSHOT_PITCH := 1.45
const KILL_PITCH := 0.78
const KILL_DELAY := 0.07  # the second click of a kill, behind the first

var _voices: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	var stream := _build_click()
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = -7.0
		add_child(player)
		_voices.append(player)


## Your shot landed on someone. Called from the HUD wiring, once per hit.
func play(headshot: bool, killed: bool) -> void:
	_play_one(HEADSHOT_PITCH if headshot else 1.0)
	if killed:
		# A bound method, not a lambda: a lambda that never touches self has no
		# target object, so Godot would keep it alive past this node's death.
		get_tree().create_timer(KILL_DELAY).timeout.connect(_play_one.bind(KILL_PITCH))


func _play_one(pitch: float) -> void:
	var voice := _voices[_next]
	_next = (_next + 1) % VOICES
	voice.pitch_scale = pitch
	voice.play()


## Two decaying partials plus a noise transient, rendered to 16-bit PCM.
func _build_click() -> AudioStreamWAV:
	var count := int(RATE * LENGTH)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / RATE
		var env := exp(-DECAY * t)
		var value := (sin(TAU * TONE_A * t) * 0.6 + sin(TAU * TONE_B * t) * 0.4) * env
		if t < ATTACK:
			value += randf_range(-0.5, 0.5)
		data.encode_s16(i * 2, roundi(clampf(value, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream
