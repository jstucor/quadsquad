class_name Locomotion
extends RefCounted
## HOW A BODY IS ANIMATED — the one place, for every body in the game.
##
## Player and Bot are duck-typed against each other and share no base class
## (house rule 15), so for as long as there have been animations they have each
## carried their OWN copy of this: the same state machine, the same
## `_ground_clip` with the same `STRAFE_RATIO`, the same blend time, and the same
## table of stride lengths written out twice with the same magic numbers in it
## (2.6, 1.9, 5.0, and a 0.6..2.2 clamp). `tests/locomotion.tscn` exists BECAUSE
## of that duplication — it drives Player and Bot separately and asserts the two
## agree, which is a test whose whole job is to catch a divergence that should
## not be possible.
##
## They had already drifted. The player paces `crouch_walk` and `guard_walk` off
## their own strides; the bot's copy has neither case and falls through to 1.0.
## Neither is wrong today — a bot never plays those two clips — and that is
## exactly the shape of a fault that goes unnoticed until the day it does.
##
## So this is ONE object per body, made once and ticked once a frame. It owns:
##
##   WHICH CLIP     the state machine, and the direction rule under it
##   HOW FAST       stride-matched playback, so feet do not skate
##   HOW IT BLENDS  per-transition, because settling is not the same as starting
##   THE LEAN       the realism this did not have at all — see `_tick_lean`
##
## It is a RefCounted and not a static module because the last two need STATE
## (the previous velocity, and a smoothed lean), and a static helper would have
## pushed that state back out into the two callers this exists to unify.

## METRES OF GROUND PER ANIMATION CYCLE, per clip. Playback is scaled by the
## body's real speed over this, which is what stops the feet skating — and it is
## per clip because a sidestep covers less ground per cycle than a stride does,
## so pacing all of them off the walk's 2.6 would skate at exactly the speeds
## those clips are for.
const STRIDE := {
	"walk": 2.6,
	"walk_back": 1.9,
	"run": 5.0,
	"guard_walk": 1.8,
}
## Outside this the clip is played at its own pace rather than at an absurd one:
## a body crawling at 0.2 m/s should not play a stride in slow motion.
const RATE_MIN := 0.6
const RATE_MAX := 2.2

## HOW LONG A TRANSITION TAKES, and it is NOT one number.
##
## Every change used to blend over a flat 0.12 s. But a body does not start and
## stop symmetrically: coming to a halt is a settle that takes longer than
## breaking into a stride, and leaving the ground is an EVENT that should not
## ease at all. One number for all three makes starts feel soft and stops feel
## abrupt, which is the same complaint from both ends.
const BLEND := 0.12
const BLEND_TO_IDLE := 0.24     # settling, not stopping
const BLEND_AIRBORNE := 0.05    # a jump is an event
const BLEND_LANDING := 0.09     # ...and so is arriving

## THE LEAN. A body that changes direction with no lean is a puppet being slid
## across the floor, and it was the largest single thing missing here: every
## other part of the rig was solved carefully and then translated rigidly.
##
## It is driven by ACCELERATION rather than by velocity, because leaning is what
## a body does while it CHANGES speed — a sprint held at a constant pace is
## upright, and it is the first two steps and the stop that are not.
##
## Radians at full acceleration, and deliberately small: this is a weight cue,
## not a motorcycle.
const LEAN_PITCH := 0.20
const LEAN_ROLL := 0.16
## What counts as "full" acceleration, in m/s². Above this the lean is capped, so
## being launched by a rocket does not fold the body in half.
const LEAN_FULL_ACCEL := 26.0
## How fast the lean chases its target. Slower than the acceleration that drives
## it, or the body twitches on every frame the stick moves.
const LEAN_EASE := 7.0
## ...and in the air there is nothing to lean against.
const LEAN_AIR_EASE := 3.0

## HOW FAR THE CHEST MAY LEAD THE LEGS while standing still, and how fast the
## feet come round once they must. Moved here whole from Player: the swivel and
## the twist are the same joint being argued over by two rules, so they cannot
## live in two files.
const TWIST_MAX := deg_to_rad(55.0)
const TWIST_STEP_RATE := 7.0     # rad/s the feet shuffle round once out of neck
## ...and how fast the legs come round to the direction of travel. Fast enough to
## feel like part of the step, slow enough that the 180-degree case at the
## backing boundary reads as the body TURNING rather than as a snap.
const SWIVEL_RATE := 11.0

var _anim: AnimationPlayer
var _model: Node          # CharacterModel — duck-typed, Corpse has none
var _lean := Vector2.ZERO         # x = roll, y = pitch, radians
var _last_local := Vector2.ZERO   # body-frame velocity, for the acceleration
var _was_airborne := false
## Which way the LEGS point, in world radians, and whether the body is currently
## resolving its travel as a backpedal (see `_is_backing`).
var feet_yaw := 0.0
var _backing := false
var _started := false


func setup(anim: AnimationPlayer, model: Node) -> void:
	_anim = anim
	_model = model


## One frame of animation for one body.
##
## Arguments rather than a state dictionary on purpose: this runs once per body
## per frame and a hundred bodies is a supported roster, so a dictionary here
## would be a hundred allocations a frame for a call that never outlives itself
## (house rule 1).
## `sliding` DEFAULTS FALSE so a Bot — which has no slide — needs no change and
## cannot accidentally be given one. Player is the only caller that passes it.
func tick(delta: float, velocity: Vector3, body_yaw: float, airborne: bool,
		crouched: bool, guarding: bool, sprinting: bool,
		crouch_stride := 0.0, sliding := false) -> void:
	if _anim == null or not is_instance_valid(_anim):
		return
	# WORLD VELOCITY INTO THE BODY'S OWN FRAME. Everything below is about which
	# way this body is moving relative to where it is FACING, and a world vector
	# cannot answer that — it is the step the bot's copy of this had to remember
	# to take and the player's did not, because a player's input already arrives
	# body-relative.
	var flat := Vector3(velocity.x, 0.0, velocity.z).rotated(Vector3.UP, -body_yaw)
	var local := Vector2(flat.x, flat.z)
	var speed := local.length()

	var moving := speed > 0.15
	# The backing state is sticky, so it is resolved ONCE and then handed to both
	# the clip and the swivel — asking twice would let the two disagree on the
	# frame the hysteresis flips.
	if moving and not airborne and not crouched and not sliding:
		_backing = _is_backing(travel_angle(local), _backing)
	else:
		_backing = false

	var clip := clip_for(local, airborne, crouched, guarding, sprinting, _backing,
		sliding)
	_play(clip, airborne)
	_anim.speed_scale = rate_for(clip, speed, crouch_stride)
	_tick_swivel(delta, body_yaw, local, moving, airborne, crouched)
	_tick_lean(delta, local, airborne)
	_tick_steps(delta, speed, clip, airborne, crouched, sprinting, sliding,
		crouch_stride)
	_probe_feet()
	_was_airborne = airborne


## --- FOOTFALLS -----------------------------------------------------------------
##
## THE GAME HAD NO FOOTSTEPS AT ALL, and that is the loudest thing that can be
## missing from a shooter. A body that crosses a room in silence has no weight
## however good the animation on it is — and it costs more than feel: hearing
## somebody come round a corner is how half of every firefight starts, and
## without it the only warning anybody ever gets is being shot.
##
## IT LIVES HERE FOR THE REASON THE MODULE EXISTS. Player and Bot share no base
## class, so anywhere else is two copies of the same rule — and this one has to
## agree with the CLIP, which is the thing this file already owns. Bots get
## footsteps for free, and that is not a side effect: the AI making noise is
## most of the value.
##
## DRIVEN BY DISTANCE TRAVELLED, OFF THE SAME `STRIDE` TABLE THE CLIP IS PACED
## BY. That is what makes a footfall land on a footfall. Pacing it off a timer
## would drift against the animation the moment speed changed — which is
## constantly — and pacing it off the clip's playback position would break the
## moment a clip was retimed. Two footfalls per cycle, because a stride is two
## steps; sharing `rate_for`'s own table means the sound and the legs cannot
## disagree by construction, and it is also why sprinting steps faster with no
## extra code.
const STEPS_PER_STRIDE := 2.0
## Boots do not carry as far as gunfire. This is honest and it is also what stops
## a hundred bodies at a walk drowning the voice pool — see `Audio.play_at`.
const STEP_HEARING := 26.0
## Crouching is QUIETER, which turns a stance into a tactic: the crouch already
## costs you speed and buys you accuracy and a smaller profile, and this is the
## fourth thing it buys for nothing extra. Sprinting is louder for the same
## reason in reverse — running somewhere is a decision that announces itself.
const STEP_CROUCH_DB := -9.0
const STEP_SPRINT_DB := 2.5
## Below this there is no stride to speak of and any sound is a body shuffling on
## the spot.
const STEP_MIN_SPEED := 0.6
## How far a landing has to have fallen before it is worth a sound. A body
## stepping off a kerb is not an event.
const LAND_MIN_DROP := 1.6

var _step_metres := 0.0
## HOW MANY FOOTFALLS THIS BODY HAS TAKEN, monotonically. Public because it is
## the only unambiguous way to observe the decision: the accumulator below also
## resets on a landing, so watching IT for a drop counts arriving as a step.
var steps_taken := 0
## The highest point reached since leaving the ground, so a landing can tell a
## real drop from stepping off a kerb.
var _fall_top := 0.0


func _tick_steps(delta: float, speed: float, clip: String, airborne: bool,
		crouched: bool, sprinting: bool, sliding: bool,
		crouch_stride: float) -> void:
	if _model == null or not is_instance_valid(_model):
		return
	# ARRIVING IS ITS OWN SOUND, and it is checked before the early-outs below —
	# a body lands with no forward speed all the time.
	var here: float = _model.global_position.y
	if _was_airborne and not airborne:
		# HOW FAR IT FELL, which is the peak of the arc against the ground it
		# arrived on — not the jump's height, because a body that walks off a
		# ledge never had one.
		if _fall_top - here >= LAND_MIN_DROP:
			Audio.play_at("land", _model.global_position, 0.0, STEP_HEARING)
		# A landing IS a footfall, so the stride restarts from it rather than
		# firing a step a few centimetres later.
		_step_metres = 0.0
	if airborne:
		_fall_top = maxf(_fall_top, here)
		return
	_fall_top = here
	# A SLIDE HAS NO FOOTFALLS — that is the whole point of it — and its own
	# scrape is played once when it starts.
	if sliding or speed < STEP_MIN_SPEED:
		return
	var stride: float = float(STRIDE.get(clip, 0.0))
	if clip == "crouch_walk" and crouch_stride > 0.0:
		stride = crouch_stride
	if stride <= 0.0:
		return
	_step_metres += speed * delta
	var every: float = stride / STEPS_PER_STRIDE
	if _step_metres < every:
		return
	# `fmod` rather than zeroing: at a sprint a single frame can cover most of a
	# step, and discarding the remainder makes the cadence drift slow.
	_step_metres = fmod(_step_metres, every)
	var db := 0.0
	if crouched:
		db += STEP_CROUCH_DB
	elif sprinting:
		db += STEP_SPRINT_DB
	steps_taken += 1
	Audio.play_at("footstep", _model.global_position, db, STEP_HEARING)


## THE STATE MACHINE, in priority order, and the order is the design.
##
## The guard sits BELOW the crouch even though it is the more valuable tell:
## there is no crouched guard clip, so putting it above would stand the model up
## out of a capsule that is still crouched — and the head the model draws is the
## head other players are shooting at.
static func clip_for(local: Vector2, airborne: bool, crouched: bool,
		guarding: bool, sprinting: bool, backing := false,
		sliding := false) -> String:
	if airborne:
		return "jump"
	var moving := local.length() > 0.15
	# THE SLIDE OUTRANKS THE CROUCH, and it has to: a sliding body IS crouched
	# (`Player._crouch_held` answers true for it, which is what shrinks the
	# capsule), so below the crouch this branch could never be reached and every
	# slide in the game would play `crouch_walk` — a squatting figure travelling
	# at eight metres a second, which is the artefact the clip exists to remove.
	# It sits under AIRBORNE because leaving the ground ends a slide anyway.
	if sliding:
		return "slide"
	if crouched:
		return "crouch_walk" if moving else "crouch_idle"
	if guarding:
		return "guard_walk" if moving else "guard_idle"
	if not moving:
		return "idle"
	# SPRINTING IS EXEMPT FROM THE DIRECTION RULE on purpose: you cannot sprint
	# sideways or backwards, and a sprint that could would want its own clips
	# rather than these.
	if sprinting:
		return "run"
	return ground_clip(local, backing)


## WHICH WAY THIS BODY IS TRAVELLING, relative to where it is FACING. 0 is
## straight ahead, +right, and it wraps — so the whole of the direction rule
## below is one angle rather than a pile of component comparisons.
static func travel_angle(local: Vector2) -> float:
	if local.length_squared() < 0.0001:
		return 0.0
	# Local +y is BACKWARD (the body faces -Z), so forward is -y.
	return atan2(local.x, -local.y)


## A BODY DOES NOT WALK SIDEWAYS — IT TURNS ITS HIPS AND WALKS.
##
## The old rule picked a dedicated sidestep clip for lateral movement, which is
## the honest thing to do with a fixed clip library and is not what a person
## does: you point your legs where you are going and carry your upper body round
## to keep the gun on target. So the legs now SWIVEL, up to a right angle, and
## everything inside that arc is the ordinary forward stride.
##
## Past a right angle the hips cannot follow — that is roughly where a human
## runs out of hip — so the remaining 180 degrees behind the body is covered by
## the BACKWARD walk with the legs swivelled to the mirror of the travel
## direction. Backing away to your right is therefore hips turned a little LEFT
## and a backpedal, which is exactly what it is in life.
##
## Returns the angle to put the LEGS at, relative to the aim. Always within
## +/- 90 degrees by construction, whichever branch it took.
static func swivel_for(local: Vector2, backing := false) -> float:
	var t := travel_angle(local)
	if _is_backing(t, backing):
		t = wrapf(t - PI, -PI, PI)
	# CLAMPED SEPARATELY FROM THE HYSTERESIS, and that is not a detail. The
	# sticky boundary (`SWIVEL_MARGIN`) is there to stop the CLIP flickering, and
	# inside its band the travel angle runs a little past the right angle — so
	# without this the legs followed it out to 107 degrees, which is past where
	# the hip stops and is the number this whole rule exists to respect. Found by
	# sweeping a full circle of travel rather than by checking the eight cases,
	# every one of which sits comfortably inside the band.
	#
	# In the band the legs sit at the limit while travel is a few degrees beyond
	# it. That mismatch is smaller than the one it replaces and invisible.
	return clampf(t, -SWIVEL_LIMIT, SWIVEL_LIMIT)


## As far as a hip goes.
const SWIVEL_LIMIT := PI / 2.0


static func ground_clip(local: Vector2, backing := false) -> String:
	return "walk_back" if _is_backing(travel_angle(local), backing) else "walk"


## THE BOUNDARY NEEDS HYSTERESIS, and this is the one place the swivel can bite.
##
## At exactly sideways the two answers are both valid — hips right and walking
## forward, or hips left and backing up — and they are 180 DEGREES APART. Without
## a margin, a body strafing along that line flips its legs end over end on
## whatever noise the stick or the pathfinder is producing.
##
## So the crossing is sticky: once walking you keep walking until well past the
## right angle, and once backing you keep backing until well inside it. A real
## crossing still turns the legs round, but it does it once and the swivel is
## smoothed on the way (see `_tick_swivel`), so it reads as the body turning
## rather than as a snap.
const SWIVEL_MARGIN := deg_to_rad(18.0)


static func _is_backing(t: float, was_backing: bool) -> bool:
	var edge := PI / 2.0 + (-SWIVEL_MARGIN if was_backing else SWIVEL_MARGIN)
	return absf(t) > edge


## Playback rate for a clip at a real ground speed. `crouch_stride` lets a caller
## state the pace of its own crouched walk, which is a movement-speed question
## (WALK_SPEED * CROUCH_SPEED_MULT) and so belongs to the body, not to this table.
static func rate_for(clip: String, speed: float, crouch_stride := 0.0) -> float:
	var stride := float(STRIDE.get(clip, 0.0))
	if clip == "crouch_walk" and crouch_stride > 0.0:
		stride = crouch_stride
	if stride <= 0.0:
		return 1.0
	return clampf(speed / stride, RATE_MIN, RATE_MAX)


func _play(clip: String, airborne: bool) -> void:
	# `assigned_animation` and not `current_animation`, so the one-shot jump goes
	# on holding its last frame instead of retriggering every tick.
	if _anim.assigned_animation == clip or not _anim.has_animation(clip):
		return
	_anim.play(clip, _blend_for(clip, airborne))


func _blend_for(clip: String, airborne: bool) -> float:
	if airborne:
		return BLEND_AIRBORNE
	if _was_airborne:
		return BLEND_LANDING
	if clip == "idle" or clip == "crouch_idle" or clip == "guard_idle":
		return BLEND_TO_IDLE
	return BLEND


## LEAN INTO THE CHANGE. See LEAN_PITCH for why acceleration and not velocity.
##
## It is written to the model's TWIST joint, which is the one joint in the rig
## that no clip ever names — the same reason the torso twist lives there. The
## AnimationPlayer rewrites every other joint every frame and would erase this
## on the frame it was set, with nothing to say why. `set_twist` owns that
## joint's Y; this owns its X and Z, so the two compose instead of fighting.
##
## It leans the UPPER BODY and not the whole model, which is also what you want:
## the legs are striding and have to stay under the hips, and a full-body lean
## from the root would take the feet off the floor on every direction change.
func _tick_lean(delta: float, local: Vector2, airborne: bool) -> void:
	var accel := (local - _last_local) / maxf(delta, 0.0001)
	_last_local = local
	var want := Vector2.ZERO
	if not airborne:
		# Forward is local -y, and a positive rotation about X tips the body's up
		# axis BACKWARD — so accelerating forward is a negative pitch.
		want = Vector2(
			-clampf(accel.x / LEAN_FULL_ACCEL, -1.0, 1.0) * LEAN_ROLL,
			clampf(accel.y / LEAN_FULL_ACCEL, -1.0, 1.0) * LEAN_PITCH)
	var ease := LEAN_AIR_EASE if airborne else LEAN_EASE
	_lean = _lean.lerp(want, clampf(delta * ease, 0.0, 1.0))
	if _model != null and is_instance_valid(_model) \
			and _model.has_method("set_lean"):
		_model.set_lean(_lean.y, _lean.x)


## POINT THE LEGS WHERE THE BODY IS GOING, AND CARRY THE CHEST BACK ONTO THE AIM.
##
## This is the whole of the sideways-movement rework and it replaces the sidestep
## clips: the legs take the travel direction (`swivel_for`, at most a right angle
## off the aim) and the model is counter-rotated so they stay there while the
## twist joint puts the chest back where the gun is pointing.
##
## STANDING STILL IS THE OTHER HALF and it is unchanged from what Player used to
## do alone: the feet hold their heading and the chest is allowed to lead them by
## `TWIST_MAX`, and only once it runs out of neck do the feet shuffle round — far
## enough to get back inside the limit and no further, which is what makes it
## read as a shuffle rather than as the legs snapping to the camera.
##
## The 90-degree swivel deliberately exceeds `TWIST_MAX` while moving. A human
## does not hold ninety degrees of waist; a human also does not walk sideways,
## and between the two lies the thing this replaced. The legs are striding, which
## is what sells it.
func _tick_swivel(delta: float, aim_yaw: float, local: Vector2, moving: bool,
		airborne: bool, crouched: bool) -> void:
	if _model == null or not is_instance_valid(_model) \
			or not _model.has_method("set_twist"):
		return
	if not _started:
		feet_yaw = aim_yaw          # a body's first frame is not a turn
		_started = true
	var want := aim_yaw
	if moving and not airborne and not crouched:
		want = aim_yaw + swivel_for(local, _backing)
	var lead := wrapf(want - feet_yaw, -PI, PI)
	if moving or airborne or crouched:
		feet_yaw += lead * minf(SWIVEL_RATE * delta, 1.0)
	elif absf(lead) > TWIST_MAX:
		var over := lead - signf(lead) * TWIST_MAX
		feet_yaw += over * minf(TWIST_STEP_RATE * delta, 1.0)
	var twist := wrapf(aim_yaw - feet_yaw, -PI, PI)
	_model.rotation.y = -twist      # the legs stay where the feet are...
	_model.set_twist(twist)         # ...and the chest comes back onto the aim


## --- WHAT IS UNDER EACH FOOT ---------------------------------------------
##
## The other half of `CharacterModel`'s foot planting, and it lives here for one
## reason: a ray query may only be made while physics is flushing, and this is
## the part of the body's frame that runs there. The model does the SOLVE in
## `_process`, after the AnimationPlayer has had its say — see the note on
## `process_priority`. Splitting it that way costs a frame of latency on the
## ground height, which is nothing, and buys the correct ordering, which is
## everything.
##
## TWO RAYS A BODY. That is the whole cost, and it is why it is gated: a hundred
## bodies in MASSIVE would be two hundred queries a tick for feet nobody is close
## enough to see land. `Locomotion` is told whether this body is worth it.

## How far above and below the ankle to look. Above, so a foot already inside a
## step still finds its top; below, so a foot over a drop knows how far.
const PROBE_UP := 0.55
const PROBE_DOWN := 0.95
## WORLD ONLY (layer 1). Masking bodies too would plant a foot on somebody's head.
const PROBE_MASK := 1

## OFF, AND HERE IS EXACTLY WHERE IT GOT TO. All figures from
## `tests/plant_look.tscn`, which reports each foot against the ground under THAT
## foot and the gap between the ankles.
##
## WORKING:
##   A STEP.       Beside a 0.5 m step the worst foot is 39 mm off the ground
##                 without planting and 5 mm with it — both feet, not one.
##   THE STANCE.   `_leg_ik` corrects the animated pose instead of replacing it
##                 (see its note), so the idle splay survives: 220 mm between the
##                 ankles unplanted against 217 mm planted. This was the reason
##                 the feature was shelved the first time and it is now fixed.
##
## NOT WORKING — and it is one specific thing, on a 14-degree slope:
##   the UPHILL foot is corrected (+67 mm floating becomes -6 mm) and the
##   DOWNHILL one is then driven 60 mm INTO the surface (+12 mm becomes -60 mm).
##   One foot right and one buried is worse than two slightly high, and these
##   maps are heightfields, so slopes are the common case and not the corner one.
##
## RULED OUT, each by measuring rather than reasoning: the sole-vs-ankle offset,
## the reach test's origin, the knee's off-plane rotation, the hip drop
## overwriting the pose's own, a stale lock height, and the probe sampling from
## the animated ankle rather than from the lock. All six were real faults and all
## six are fixed; none of them is this one. What is left is almost certainly the
## HIP DROP and the two locks arguing — the drop is a single number serving both
## feet and is solved from whichever foot needs it most, with nothing stopping it
## overshooting the other.
var plant_feet := false


func _probe_feet() -> void:
	if _model == null or not is_instance_valid(_model) \
			or not ("planting" in _model):
		return
	_model.planting = plant_feet
	if not plant_feet:
		return
	var space: PhysicsDirectSpaceState3D = _model.get_world_3d().direct_space_state
	for i in 2:
		var sn := "L" if i == 0 else "R"
		var ankle := _model.get_node_or_null(
			NodePath(CharacterModel.PATHS["a" + sn])) as Node3D
		if ankle == null:
			_model.foot_ground_hit[i] = false
			continue
		# PROBE UNDER THE LOCK, NOT UNDER THE ANKLE. Once a foot is planted the
		# ankle is being dragged toward the lock and is not there yet, so a ray
		# dropped from the ankle samples the ground under somewhere the foot is
		# not — and on a slope that is a different height. The lock then refreshes
		# to that wrong ground, the solve chases it, and the foot settles BELOW
		# the surface: measured, 60 mm buried on a 14-degree slope while the other
		# foot sat correctly, which reads as one leg through the hill.
		var at: Vector3 = ankle.global_position
		if _model._plant_on[i]:
			at = _model._plant_at[i]
		var q := PhysicsRayQueryParameters3D.create(
			at + Vector3.UP * PROBE_UP, at + Vector3.DOWN * PROBE_DOWN)
		q.collision_mask = PROBE_MASK
		var hit: Dictionary = space.intersect_ray(q)
		_model.foot_ground_hit[i] = not hit.is_empty()
		if not hit.is_empty():
			_model.foot_ground[i] = (hit["position"] as Vector3).y
