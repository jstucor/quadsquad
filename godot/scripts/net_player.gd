class_name NetPlayer
extends CharacterBody3D
## A BODY SIMULATED ON SOMEBODY ELSE'S MACHINE. One of these stands in for every
## remote human and every host-side bot, and it is the only new kind of combatant
## networking adds.
##
## IT IS A COMBATANT AND NOTHING MORE (house rule 15). Because every combatant in
## this game is duck-typed rather than sharing a base class, a proxy only has to
## answer `is_alive()` / `team` / `take_damage()` / `body_height()` — plus
## `is_headshot()`, which `Weapon._trace_pellet` asks the same way. That is the
## whole reason gunfire, splash, melee arcs, the aim assist, the AI's sight
## checks, spawn-marker blocking and the capsule unstick all work against a
## remote player with NO change to any of them. Nothing about this design was
## luck; it is what the duck typing was for.
##
## IT IS NEVER SIMULATED. `move_and_slide` is never called, gravity is never
## applied, and no input is ever read. Its transform is written from the wire and
## eased between packets — a proxy that ran the movement code would be a second
## opinion about where a body is, and the machine that owns it already has the
## only one that counts.
##
## THE MODEL IS THE REAL MODEL. A remote player is built from the same
## `CharacterModel` and the same `Weapon` as a local one, because the whole
## roster reads by SILHOUETTE — a Droideka is not a Droideka at a generic 1.0
## stature, and a class you cannot identify across the map is a class you cannot
## fight. Style, stature and weapon arrive once at spawn; only motion is per tick.

const CHARACTER := preload("res://scripts/character.gd")
const WEAPON := preload("res://scripts/weapon.gd")
const CORPSE_SCENE := preload("res://scenes/fx/corpse.tscn")

## THE ANIMATION IS A BYTE, and this table is what it means. Sent as an index
## rather than a string for the obvious reason (a name is 5-11 bytes a body a
## tick against one), and kept here rather than in `net_sync.gd` because it is
## part of what a BODY is. APPEND ONLY — this is an index-addressed table and
## inserting a row silently re-animates every remote body in the game
## (house rule 8).
const CLIPS: Array[String] = [
	"idle", "walk", "run", "jump",
	"crouch_idle", "crouch_walk", "guard_idle", "guard_walk",
]

## Bit meanings inside the flag byte. Same rule: append only.
const F_ALIVE := 1 << 0
const F_CROUCH := 1 << 1
const F_AIM := 1 << 2
const F_CLOAK := 1 << 3

## HOW LONG A PACKET'S WORTH OF MOTION IS SPREAD OVER. Snapshots arrive at
## `NetSync.SEND_HZ` and frames are drawn at up to sixty, so a proxy written
## straight from the wire steps three times a second per packet and reads as a
## body being dragged. Easing over slightly MORE than the send interval is what
## absorbs jitter: a packet that arrives late finds the body still moving toward
## where the last one said, rather than stopped and waiting.
const EASE_OVER := 0.075
## Past this the body is being teleported, not walked — a respawn, a cable vault,
## a rewind after a stall — so it is placed outright and the interpolation is
## reset. Easing a respawn across the map draws the body smeared over the whole
## distance, which is house rule 10's symptom arriving over the network instead
## of over a physics step.
const SNAP_DISTANCE := 6.0

var net_id := 0
var team := 0
var display_name := ""
var health := 100.0
var max_health := 100.0
var is_bot := false

var model: Node3D           # CharacterModel
var weapon: Node3D          # Weapon, for the muzzle flash and the tracer
var head: Node3D

var _anim: AnimationPlayer
var _collision: CollisionShape3D
var _style := 0
var _stature := 1.0
var _alive := true
var _clip := 0
var _shots := 0             # last shot counter seen; see NetSync's wrap note

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _ease := 0.0
var _yaw := 0.0
var _yaw_from := 0.0
var _yaw_to := 0.0
var _pitch := 0.0


## Build the body. Called once, by NetSync, from a spawn record.
func setup(id: int, on_team: int, style: int, stature: float, weapon_class: int,
		body_name: String, bot := false) -> void:
	net_id = id
	team = on_team
	display_name = body_name
	is_bot = bot
	name = "Net%d" % id

	# Layer 2 (players), and the mask is deliberately ZERO. It has to be ON the
	# player layer or no ray, splash or melee arc would ever find it. It must not
	# COLLIDE with anything, because it is never moved by physics — and a body
	# that both writes its own position and sweeps against the world would fight
	# whatever the owner's machine already decided.
	collision_layer = 2
	collision_mask = 0

	_collision = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	_collision.shape = capsule
	_collision.position = Vector3(0.0, 0.9, 0.0)
	add_child(_collision)

	model = CHARACTER.new()
	model.name = "Model"
	add_child(model)

	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 1.5, 0.0)
	add_child(head)

	weapon = WEAPON.new()
	weapon.name = "Weapon"
	weapon.position = Vector3(0.22, -0.1, -0.35)
	head.add_child(weapon)
	# The proxy's gun exists to be SEEN, so it gets no shooter and never resolves
	# a shot. `shooter` is what `_trace_pellet` excludes and what credits a kill;
	# leaving it null is what guarantees a proxy can never deal damage locally,
	# rather than relying on nobody calling try_fire.
	weapon.shooter = null

	_style = style
	model.set_style(style)
	model.set_team_color(GameState.team_colors[team % GameState.team_colors.size()])
	weapon.set_class(weapon_class)
	set_stature(stature)
	_anim = model.find_child("AnimationPlayer", true, false)
	GameState.register_combatant(self)


func _exit_tree() -> void:
	GameState.unregister_combatant(self)


## Mirrors `Player._apply_stature` — one number drives model scale, capsule
## height, eye height and therefore the headshot line, because the moment they
## disagree you get a head you can see and cannot hit. On a proxy that matters
## MORE, not less: this is the body everyone else is actually shooting at.
func set_stature(scale_to: float) -> void:
	_stature = clampf(scale_to, 0.5, 1.16)
	model.scale = Vector3.ONE * _stature
	var capsule: CapsuleShape3D = _collision.shape
	capsule.height = 1.8 * _stature
	_collision.position = Vector3(0.0, 0.9 * _stature, 0.0)
	head.position = Vector3(0.0, 1.5 * _stature, 0.0)


func body_height() -> float:
	return 1.8 * _stature


func is_alive() -> bool:
	return _alive


## Where the head line is, in world Y. Same fraction Player uses, so a headshot
## on a proxy and a headshot on the body it stands for are the same shot.
func is_headshot(world_pos: Vector3) -> bool:
	return world_pos.y - global_position.y > body_height() * 0.82


## SOMEBODY SHOT THIS BODY ON THIS MACHINE. The damage is NOT applied here — this
## is a picture of a body, and a picture has no health. It is forwarded to the
## machine that owns it, which applies it to the real body and answers back.
##
## That is what makes the guard work over a network without rewinding anything:
## whether the blade was up is a question only the owner can answer, and it
## answers it at the moment the shot lands rather than at the moment it was
## fired. It favours the victim on the block and the shooter on the hit, which is
## the trade nearly every shooter makes and the one that feels right at both ends.
func take_damage(amount: float, attacker: Node = null, headshot := false) -> void:
	if not _alive:
		return
	var sync := NetSync.current
	if sync == null:
		return
	sync.report_damage(net_id, amount, attacker, headshot)


## A LOCAL BODY CONFIRMING A HIT BACK TO A REMOTE SHOOTER. `Player.take_damage`
## calls this on whatever shot it, which over a network is this proxy — so the
## marker, the click and the kill streak reach the machine that actually pulled
## the trigger. Without it a player shooting somebody on another machine gets no
## confirmation at all, which reads exactly like rounds passing through people.
func on_hit_confirmed(headshot: bool, killed: bool) -> void:
	var sync := NetSync.current
	if sync != null:
		sync.report_hit_confirm(net_id, headshot, killed)


## The kill streak, forwarded the same way. `Player._die` credits whatever killed
## it; when that is a remote shooter this is the proxy standing in for them, and
## the streak has to reach the HUD on the machine holding the trigger.
func credit_kill() -> void:
	var sync := NetSync.current
	if sync != null:
		sync.report_credit_kill(net_id)


## No-op impulses. Both Player and Bot expose `apply_impulse` so a Force shove can
## move them; a proxy takes the shove on its OWNER'S machine, arriving as ordinary
## motion in the next snapshot. Answering the method but doing nothing locally is
## deliberate — dropping it would make `ForcePowers` skip remote bodies entirely,
## and the power would look broken rather than merely delayed.
func apply_impulse(_impulse: Vector3) -> void:
	pass


## The owning machine's shot, drawn here. Cosmetic only: flash, sound and tracer,
## with no ray, no damage and no heat — the shot that mattered was resolved where
## it was fired.
func play_shot() -> void:
	if weapon != null and is_instance_valid(weapon):
		weapon.fire_cosmetic()


func set_cloaked(on: bool) -> void:
	# Same treatment a local cloak gets: a shimmer to a human, and out of the AI's
	# sight set entirely. Safe to drive per body because each character owns its
	# own materials.
	model.set_cloak(0.25 if on else 1.0)
	GameState.set_cloaked(self, on)


## A snapshot landed. Everything here is a WRITE — nothing is derived, nothing is
## simulated, and the only decision made locally is whether the move was a walk
## or a teleport.
func take_state(pos: Vector3, yaw: float, pitch: float, clip: int, flags: int,
		health_frac: float, shots: int) -> void:
	var alive := (flags & F_ALIVE) != 0
	if alive != _alive:
		_alive = alive
		visible = alive
	health = health_frac * max_health

	if pos.distance_to(_to) > SNAP_DISTANCE or not _alive:
		global_position = pos
		_from = pos
		_to = pos
		_ease = EASE_OVER
		# Placed, not walked — house rule 10, and it applies to a body arriving
		# over a wire exactly as it does to one arriving from a respawn.
		reset_physics_interpolation()
	else:
		_from = global_position
		_to = pos
		_ease = 0.0
	_yaw_from = _yaw
	_yaw_to = yaw
	_pitch = pitch
	set_cloaked((flags & F_CLOAK) != 0)

	if clip != _clip:
		_clip = clip
		if _anim != null and clip >= 0 and clip < CLIPS.size() \
				and _anim.has_animation(CLIPS[clip]):
			_anim.play(CLIPS[clip], 0.12)

	# THE SHOT COUNTER IS A DIFFERENCE, NOT AN EVENT, and that is what makes
	# gunfire survive packet loss without a reliable channel per trigger pull. A
	# repeater fires thirteen times a second; sending each as its own reliable
	# RPC would be thirteen acknowledged packets per shooter per second for a
	# muzzle flash. Instead every body carries a wrapping count of shots fired,
	# and a receiver plays the difference — a dropped packet catches up on the
	# next one instead of losing the shot.
	if shots != _shots:
		var missed := (shots - _shots) & 0xff
		_shots = shots
		# Capped: a body that was out of range, or a peer that stalled, can hand
		# back a difference of two hundred, and two hundred muzzle flashes on one
		# frame is a freeze (house rule 2 — per-shot cost is the one that bites).
		for i in mini(missed, 3):
			play_shot()


func _physics_process(delta: float) -> void:
	if _ease < EASE_OVER:
		_ease = minf(_ease + delta, EASE_OVER)
		var t := _ease / EASE_OVER
		global_position = _from.lerp(_to, t)
		_yaw = lerp_angle(_yaw_from, _yaw_to, t)
	else:
		global_position = _to
		_yaw = _yaw_to
	rotation.y = _yaw
	# The head carries the aim, which is what the tracer and the muzzle flash come
	# out of — a proxy whose gun always pointed at the horizon would show every
	# remote player shooting flat while their rounds went uphill.
	head.rotation.x = _pitch
	# The model's own facing: a proxy has no torso twist of its own (the owner's
	# feet/chest split is cosmetic and not worth four bytes a tick), so the whole
	# body faces the aim, which is what the twist nets to while moving anyway.
	model.rotation.y = 0.0


## Build the ragdoll for a death that happened somewhere else. Called by NetSync
## on the death event rather than inferred from the alive flag, because the SHOVE
## is what makes a corpse read as having been shot rather than switched off, and
## a flag going false carries no direction.
## Not forced: `Corpse.VIEW_RANGE` and `MAX_ALIVE` still apply (house rules 3 and
## 4). A local player's own death is forced past both because that is the one
## body its owner is certain to be looking at — but every death on this machine
## is somebody ELSE'S, so a remote one is exactly the case those caps exist for.
func drop_corpse(shove: Vector3) -> void:
	var corpse: Node3D = CORPSE_SCENE.instantiate()
	get_tree().current_scene.add_child(corpse)
	var xform := Transform3D(Basis(Vector3.UP, rotation.y), global_position)
	corpse.launch(xform, GameState.team_colors[team % GameState.team_colors.size()],
		shove, _style, false, _stature)
