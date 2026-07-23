class_name CharacterModel
extends Node3D
## Procedural blocky humanoid (Minecraft / Krunker style), built in code — no
## imported mesh, no skinning. Every limb is a rigid box parented to a clean
## Node3D joint, so the animations are just simple local rotations at the hip,
## knee, shoulder, elbow and neck. Replaces the old imported trooper GLB.
##
## Builds itself + an AnimationPlayer (named "AnimationPlayer", so Player and
## the trooper NPC find it the same way as before) with code-generated
## idle / walk / run / jump clips. The gait is deliberately basic: whole-limb
## swings with a subtle two-joint knee lift, nothing else — the style the
## project settled on. Player drives it via the animation state machine;
## trooper.gd extends this class for decorative NPCs.

var anim_player: AnimationPlayer
var _suit_mat: StandardMaterial3D  # torso/upper-limb colour, tinted per team
## The two things the hands can hold. Both are built once and hidden/shown by
## set_melee, rather than rebuilt on a weapon swap: they hang off an animated
## joint, and a rebuild mid-frame would race the AnimationPlayer for it.
var _gun_parts: Array[MeshInstance3D] = []
var _saber_parts: Array[MeshInstance3D] = []

# Proportions in metres. Feet rest at y = 0 and the model faces -Z.
#
# These are the TROOPER's own bone lengths, measured off the model and scaled to
# the 1.82 m the game is built around. Re-proportioning the rig rather than
# stretching the mesh is what lets the trooper fit with no gaps at the joints,
# and it costs the animation nothing: every clip is a set of joint ROTATIONS, so
# changing a limb's length leaves the motion identical. (See TrooperParts, which
# reads the same bones to cut the mesh up.)
## Written out rather than computed from TrooperParts' bone table, because a
## GDScript `const` cannot call a method — and these have to stay constants,
## since CROUCH_HIP_DROP is derived from them at parse time. The derivation is the
## bone spacing along the rig's own axis (the limbs here are purely vertical, so
## it is the axis distance, not the bone's diagonal length) times SCALE, which
## is 1.82 / 2.055 = 0.8856.
const HIP_Y := 1.0265        # pelvis   1.159
const HIP_DROP := 0.0930     # pelvis -> thigh, 1.159 - 1.054
const UPPER_LEG := 0.4189    # thigh  -> calf,  1.054 - 0.581
const LOWER_LEG := 0.4012    # calf   -> foot,  0.581 - 0.128
const TORSO := 0.4933        # pelvis -> neck,  1.716 - 1.159
const SHOULDER_Y := 0.4340   # pelvis -> upperarm, 1.649 - 1.159
const SHOULDER_X := 0.2028   # upperarm x 0.229
const HIP_X := 0.0832        # thigh x 0.094
const UPPER_ARM := 0.2064    # upperarm -> forearm, x 0.462 - 0.229
const LOWER_ARM := 0.2586    # forearm  -> hand,    x 0.754 - 0.462
## Hip JOINT to ankle with the leg straight. This — not HIP_Y — is what a folded
## leg shortens: the Hips node sits HIP_DROP above the thigh joint and the boot
## hangs below the ankle, so HIP_Y is 20 cm longer than the leg it carries. Any
## pose that drops the hips has to drop them by a fraction of THIS.
const LEG := UPPER_LEG + LOWER_LEG
## Wrist -> the middle of the grip. The IK chain reaches to where the hand
## actually closes, not to the wrist, or the gun sits in the fingertips.
const HAND_REACH := 0.075

# Held-gun position, spine-local (in front of the chest, barrel toward -Z).
const GUN_POS := Vector3(0.0, 0.30, -0.26)

# The third-person lightsaber. Longer than the first-person blade (0.78 m): that
# one is foreshortened by a camera 30 cm from the hilt, while this one is judged
# from across the map, where the blade IS the silhouette.
const BLADE_LENGTH := 1.25
const BLADE_WIDTH := 0.05
const BLADE_CORE := Color(0.75, 0.92, 1.0)
const BLADE_GLOW := Color(0.25, 0.65, 1.0)

const IDLE_LEN := 2.4
const WALK_LEN := 1.0
const RUN_LEN := 0.7
const JUMP_LEN := 0.35
const GUARD_IDLE_LEN := 2.2
const GUARD_WALK_LEN := 0.95
const CROUCH_IDLE_LEN := 2.8
# Short strides at crouch speed means a HIGH cadence, not a slow one: the cycle
# is brief so the stride roughly covers the ground actually travelled instead of
# skating. player.gd paces it off WALK_SPEED * CROUCH_SPEED_MULT.
const CROUCH_WALK_LEN := 0.55

# The crouch is a real POSE, not a squashed model: the hips drop, the knees fold
# under the body and the torso leans out over them. The leg angles are solved,
# not eyeballed — with the thigh forward and the shin swung back by the same
# angle (knee = 2 x hip), the ankle lands directly under the hip, so the
# character settles onto its feet instead of sliding forward out of its own
# collision capsule. That constraint is what makes CROUCH_KNEE twice CROUCH_HIP.
const CROUCH_HIP_DEG := 55.0
const CROUCH_KNEE_DEG := CROUCH_HIP_DEG * 2.0
# How far the hips have to come DOWN for that fold, which is how much shorter a
# leg bent to CROUCH_HIP_DEG stands than a straight one.
#
# It is a fraction of LEG, and the hips track adds it to the rest height. The
# obvious-looking `LEG * cos(angle) - HIP_Y` is not this: it silently assumes the
# hips sit exactly one leg above the ground, which was true of the box rig and
# stopped being true when the rig took the trooper's proportions. It dropped
# every crouch and every guard an extra HIP_Y - LEG = 20 cm, which put the boots
# through the floor — visible as feet that simply vanish while crouched.
const CROUCH_HIP_DROP := LEG * (cos(deg_to_rad(CROUCH_HIP_DEG)) - 1.0)
const CROUCH_LEAN_DEG := 26.0  # torso out over the knees
const CROUCH_HEAD_DEG := 21.0  # ...and the head back up, so the visor faces front
const CROUCH_SWING_DEG := 26.0  # hip swing either side of the fold, when shuffling
const CROUCH_LIFT_DEG := 20.0   # extra knee tuck on the leg swinging through

# The saber guard, seen from outside: a bladed stance with the weapon brought up
# across the body. This is the only tell an opponent gets that a Force adept has
# their guard up — the exhaustion pool and the first-person pose are both private
# to the player holding the blade — so the silhouette has to change enough to
# read at range, not just tilt the wrists.
const GUARD_HIP_DEG := 10.0                     # settle into the stance
const GUARD_KNEE_DEG := GUARD_HIP_DEG * 2.0     # ankle under hip, as in the crouch
const GUARD_HIP_DROP := LEG * (cos(deg_to_rad(GUARD_HIP_DEG)) - 1.0)  # see CROUCH_HIP_DROP
const GUARD_SWING_DEG := 20.0   # hip swing either side of the stance, when walking
const GUARD_LIFT_DEG := 16.0    # extra knee tuck on the leg swinging through
const GUARD_TURN_DEG := 17.0    # torso bladed away, head kept looking front
const GUARD_LEAN_DEG := 7.0
# Where the weapon itself goes. Pitched up and swung across so the blade rises
# past the off shoulder, hilt drawn in low across the chest. Raised further once
# the blade became a real metre-long mesh rather than a blaster: the arm pose is
# solved onto whatever this says, so moving the weapon moves the whole stance,
# and the tell is the BLADE'S angle, not the wrists'.
const GUARD_GUN_POS := Vector3(-0.14, 0.40, -0.20)
const GUARD_GUN_ROT := Vector3(deg_to_rad(74.0), deg_to_rad(-52.0), 0.0)

# Short name -> node path (relative to this Character) for the animated joints.
# "gun" is the held weapon: it is a joint like any other, so the guard can raise
# it and the arms can be solved onto wherever it ends up.
const PATHS := {
	"spine": "Hips/Spine",
	"head": "Hips/Spine/Head",
	"sL": "Hips/Spine/ShoulderL", "eL": "Hips/Spine/ShoulderL/ElbowL",
	"sR": "Hips/Spine/ShoulderR", "eR": "Hips/Spine/ShoulderR/ElbowR",
	"hL": "Hips/HipL", "kL": "Hips/HipL/KneeL",
	"hR": "Hips/HipR", "kR": "Hips/HipR/KneeR",
	"gun": "Hips/Spine/HeldGun",
}


func _ready() -> void:
	_build_body()
	_build_animations()


# --- rig construction ------------------------------------------------------

func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.0  # near-black sky reflects into metal (see project Gotchas)
	m.roughness = 0.75
	return m


func _joint(parent: Node3D, jname: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = jname
	n.position = pos
	parent.add_child(n)
	return n


func _box(parent: Node3D, size: Vector3, center: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = center
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## Tint the suit (torso + upper limbs) so teams are readable at a glance.
func set_team_color(c: Color) -> void:
	if _suit_mat:
		_suit_mat.albedo_color = c


## Swap the held blaster for a lit lightsaber, or back. Everything about a Force
## adept that other players can read is on this model — the exhaustion pool, the
## first-person guard pose and the swing are all private to the owner — and with
## a blaster in its hands the guard stance was a trooper standing oddly. A metre
## of glowing blade held across the chest is the tell.
func set_melee(on: bool) -> void:
	for mi in _gun_parts:
		mi.visible = not on
	for mi in _saber_parts:
		mi.visible = on


## Fade the whole model to `alpha` (1.0 = solid) for the Trandoshan's cloak.
## Walks every mesh and dials its material's transparency; safe to call with 1.0
## to restore, which is what a respawn does. Each character owns its own
## materials (every _mat() news a fresh one), so fading this one never touches
## anybody else on the map.
func set_cloak(alpha: float) -> void:
	var solid := alpha >= 0.999
	for mi in find_children("*", "MeshInstance3D", true, false):
		var sm := (mi as MeshInstance3D).material_override as StandardMaterial3D
		if sm != null:
			sm.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if solid \
				else BaseMaterial3D.TRANSPARENCY_ALPHA
			var c := sm.albedo_color
			c.a = 1.0 if solid else alpha
			sm.albedo_color = c


func _build_body() -> void:
	var suit := _mat(Color(0.72, 0.74, 0.78))   # trooper plate, tinted per team
	_suit_mat = suit
	var parts := TrooperParts.meshes()
	# Joint placement comes from the model's own bones, not from nominal limb
	# lengths, so every piece lands exactly where its geometry was cut from.
	var at := TrooperParts.joint_offsets()

	var hips := _joint(self, "Hips", Vector3(0.0, HIP_Y, 0.0))
	_part(hips, parts, "hips", suit)

	# Torso pivots at the hips so run/idle can lean from the waist.
	var spine := _joint(hips, "Spine", Vector3.ZERO)
	_part(spine, parts, "spine", suit)

	var head := _joint(spine, "Head", at["head"])
	_part(head, parts, "head", suit)

	for side in [-1, 1]:
		var sn := "L" if side < 0 else "R"
		var sh := _joint(spine, "Shoulder" + sn, at["s" + sn])
		_part(sh, parts, "s" + sn, suit)
		var el := _joint(sh, "Elbow" + sn, at["e" + sn])
		_part(el, parts, "e" + sn, suit)

	# Third-person blaster, held two-handed in front. Other players see this;
	# the owner sees only the first-person viewmodel. Parented to the spine so
	# it leans with the torso and the CARRY arm pose keeps the hands on it.
	var gunmetal := _mat(Color(0.10, 0.10, 0.12))
	var held := _joint(spine, "HeldGun", GUN_POS)
	_gun_parts.append(_box(held, Vector3(0.05, 0.06, 0.24), Vector3(0, 0, 0.01), gunmetal))
	_gun_parts.append(_box(held, Vector3(0.028, 0.028, 0.30), Vector3(0, 0.012, -0.22), gunmetal))
	_gun_parts.append(_box(held, Vector3(0.035, 0.10, 0.05), Vector3(0, -0.06, 0.075), gunmetal))
	_build_held_saber(held, gunmetal)

	for side in [-1, 1]:
		var ln := "L" if side < 0 else "R"
		var hip := _joint(hips, "Hip" + ln, at["h" + ln])
		_part(hip, parts, "h" + ln, suit)
		var knee := _joint(hip, "Knee" + ln, at["k" + ln])
		_part(knee, parts, "k" + ln, suit)


## The third-person lightsaber, on the same HeldGun joint as the blaster so the
## solved carry/guard hold puts the hands on it unchanged — the IK reaches for
## grip points derived from GUN_POS, and the hilt sits exactly where the
## receiver did.
##
## The blade runs down -Z out of the emitter, the same axis the barrel uses, so
## every clip that points the weapon somewhere points the blade there too. It is
## UNSHADED for the same reason the first-person one is: a lit blade goes black
## on its shadow side and disappears on the night maps, which is where a glowing
## sword is most of the point.
func _build_held_saber(held: Node3D, hilt_mat: Material) -> void:
	_saber_parts.append(_box(held, Vector3(0.042, 0.042, 0.24),
		Vector3(0, 0, 0.01), hilt_mat))
	var band := _mat(Color(0.42, 0.36, 0.20))
	band.metallic = 0.0
	_saber_parts.append(_box(held, Vector3(0.05, 0.05, 0.03),
		Vector3(0, 0, -0.10), band))

	var core := _mat(BLADE_CORE)
	core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.emission_enabled = true
	core.emission = BLADE_CORE
	core.emission_energy_multiplier = 5.0
	var glow := _mat(Color(BLADE_GLOW.r, BLADE_GLOW.g, BLADE_GLOW.b, 0.5))
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.emission_enabled = true
	glow.emission = BLADE_GLOW
	glow.emission_energy_multiplier = 3.0

	# Boxes rather than cylinders: at this size and this distance a square blade
	# is indistinguishable from a round one, and it is one less mesh type on a
	# model that already renders four times a frame.
	var at := Vector3(0, 0, -0.12 - BLADE_LENGTH * 0.5)
	_saber_parts.append(_box(held,
		Vector3(BLADE_WIDTH, BLADE_WIDTH, BLADE_LENGTH), at, core))
	_saber_parts.append(_box(held,
		Vector3(BLADE_WIDTH * 2.2, BLADE_WIDTH * 2.2, BLADE_LENGTH * 0.99), at, glow))

	for mi in _saber_parts:
		mi.visible = false   # a blaster until somebody says otherwise


## Hang one cut-up piece of the trooper on a joint. Falls back to nothing if the
## slice came out empty, so a bad cut leaves a gap rather than crashing.
func _part(parent: Node3D, parts: Dictionary, key: String, mat: Material) -> void:
	if not parts.has(key):
		return
	var mi := MeshInstance3D.new()
	mi.mesh = parts[key]
	mi.material_override = mat
	parent.add_child(mi)


# --- animation clips (generated in code) -----------------------------------
# Every clip is authored as pose(time) -> {joint: euler}; _clip() samples it
# into rotation keys. Rotations are all about X (pitch): +X swings a downward
# limb FORWARD (toward -Z); knee flex is -X (lower leg kicks back to lift the
# foot). Spine -X leans the torso forward.

func _build_animations() -> void:
	anim_player = AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	add_child(anim_player)
	anim_player.root_node = NodePath("..")  # tracks are relative to this Character

	var lib := AnimationLibrary.new()
	lib.add_animation("idle", _clip(IDLE_LEN, true, 9, _idle_pose, _idle_bob))
	lib.add_animation("walk", _clip(WALK_LEN, true, 9, _walk_pose, Callable()))
	lib.add_animation("run", _clip(RUN_LEN, true, 9, _run_pose, Callable()))
	lib.add_animation("jump", _clip(JUMP_LEN, false, 2, _jump_pose, Callable()))
	# Crouch gets its own clips rather than a runtime pose laid over the others:
	# the AnimationPlayer rewrites every joint each frame, so anything applied
	# on top would depend on process ordering to survive. These go through the
	# same _clip() pipeline as everything else, and they animate the Hips
	# position track to drop the body.
	lib.add_animation("crouch_idle",
		_clip(CROUCH_IDLE_LEN, true, 9, _crouch_idle_pose, _crouch_idle_hips))
	lib.add_animation("crouch_walk",
		_clip(CROUCH_WALK_LEN, true, 9, _crouch_walk_pose, _crouch_walk_hips))
	# The guard is a clip pair for the same reason the crouch is: it has to survive
	# whatever else the AnimationPlayer writes that frame, and you can still walk
	# while holding it — a static stance played over a moving body skates the feet
	# exactly when the guard most needs to read.
	lib.add_animation("guard_idle",
		_clip(GUARD_IDLE_LEN, true, 9, _guard_idle_pose, _guard_idle_hips))
	lib.add_animation("guard_walk",
		_clip(GUARD_WALK_LEN, true, 9, _guard_walk_pose, _guard_walk_hips))
	anim_player.add_animation_library("", lib)


## Sample a pose function into a clip.
##
## Both POSITION tracks are written by every clip, even the ones that hold their
## default the whole way through. A track that exists in one animation and not in
## the next leaves its property wherever the last clip that owned it put it — so
## a clip-only hips drop (the crouch) or weapon lift (the guard) would stay put
## when you stood up or lowered the blade. Rotations are already immune to that
## because every clip keys every joint in PATHS.
func _clip(length: float, loop: bool, samples: int, pose_fn: Callable, bob_fn: Callable) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var tracks := {}
	for key in PATHS:
		var t := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(t, NodePath(PATHS[key]))
		tracks[key] = t
	var bob_track := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(bob_track, NodePath("Hips"))
	var gun_track := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(gun_track, NodePath(PATHS["gun"]))
	for i in samples:
		var time := length * float(i) / float(samples - 1)
		var pose: Dictionary = pose_fn.call(time)
		for key in PATHS:
			var e: Vector3 = pose.get(key, Vector3.ZERO)
			a.rotation_track_insert_key(tracks[key], time, Quaternion.from_euler(e))
		var bob: Vector3 = bob_fn.call(time) if not bob_fn.is_null() else Vector3.ZERO
		a.position_track_insert_key(bob_track, time, Vector3(0, HIP_Y, 0) + bob)
		a.position_track_insert_key(gun_track, time, pose.get("gun_pos", GUN_POS))
	return a


# Both hands stay on the blaster in every clip, so the arms hold a fixed CARRY
# pose and the legs do the locomotion.
#
# The pose is SOLVED onto the gun, not dialled in by hand. Hand-tuned shoulder
# and elbow angles only hold for one set of arm lengths, and the trooper's arms
# are much shorter than the box rig's (0.21 / 0.26 against 0.34 / 0.32) — the old
# angles left both hands hanging in the air well short of the weapon. Two-bone IK
# puts them on the grips whatever the arms measure, so re-proportioning the rig
# can never quietly break the hold again.
static var _carry_pose: Dictionary = {}
static var _guard_hold: Dictionary = {}

# The two grips, in the WEAPON's own space: the trigger grip under the receiver
# and the forward grip along the barrel. Everything that puts hands on the gun
# works from these, so turning or moving the weapon carries both hands with it.
const GRIP_REAR := Vector3(0.0, -0.055, 0.075)
const GRIP_FORE := Vector3(0.0, -0.015, -0.13)


## Solve both arms onto the weapon wherever the pose has put it. `gun_pos` and
## `gun_rot` are the held weapon's transform in spine space — the same values the
## clip keys onto the HeldGun joint — so the hold cannot drift off the gun.
## Returns only the four arm keys; callers merge it into a pose.
func _hold(gun_pos: Vector3, gun_rot: Vector3) -> Dictionary:
	var gun := Basis.from_euler(gun_rot)
	var reach := LOWER_ARM + HAND_REACH
	var rear := gun_pos + gun * GRIP_REAR
	var fore := gun_pos + gun * GRIP_FORE
	var right := _arm_ik(rear - Vector3(SHOULDER_X, SHOULDER_Y, 0.0), UPPER_ARM, reach)
	var left := _arm_ik(fore - Vector3(-SHOULDER_X, SHOULDER_Y, 0.0), UPPER_ARM, reach)
	return {
		"sR": right[0], "eR": Vector3(right[1], 0.0, 0.0),
		"sL": left[0], "eL": Vector3(left[1], 0.0, 0.0),
	}


## Callers all mutate the dictionary they get back (that is how a pose is built
## up), so this hands out a COPY. Returning the cache itself let _crouch_base
## write its shoulder angles straight into it and permanently clobber the solved
## hold for every clip built afterwards.
func _carry() -> Dictionary:
	if _carry_pose.is_empty():
		_carry_pose = _hold(GUN_POS, Vector3.ZERO)
	return _carry_pose.duplicate()


## Two-bone IK for one arm. `target` is where the hand must land, in SHOULDER
## space; `a` and `b` are the upper and lower segment lengths. Returns
## [shoulder euler, elbow flex].
##
## Solved in the order the rig applies it: pick the elbow flex first from the
## law of cosines (that alone fixes how far the hand reaches), which puts the
## hand at a known spot `h` with the arm still hanging in its rest plane, then
## rotate the shoulder by the minimal rotation that carries `h` onto the target.
## Nothing here assumes a particular arm length or gun position.
func _arm_ik(target: Vector3, a: float, b: float) -> Array:
	# A target further than the arm can stretch (or nearer than it can fold)
	# has no solution; clamp so the arm reaches as far as it can instead.
	var span := clampf(target.length(), absf(a - b) + 0.001, a + b - 0.001)
	var cos_elbow := clampf((a * a + b * b - span * span) / (2.0 * a * b), -1.0, 1.0)
	var flex := PI - acos(cos_elbow)   # 0 = straight; bends FORWARD, about +X
	# Where the hand sits with only the elbow bent, arm still hanging down -Y.
	var h := Vector3(0.0, -a - b * cos(flex), -b * sin(flex))
	var swing := Quaternion(h.normalized(), target.normalized())
	return [swing.get_euler(), flex]


func _idle_pose(_time: float) -> Dictionary:
	return _carry()  # near-static; hands on the gun


func _idle_bob(time: float) -> Vector3:
	return Vector3(0, 0.012 * sin(time / IDLE_LEN * TAU), 0)


func _walk_pose(time: float) -> Dictionary:
	var phase := time / WALK_LEN * TAU
	var s := sin(phase)
	var c := cos(phase)
	var hip := deg_to_rad(30)   # whole-leg swing
	var knee := deg_to_rad(34)  # mid-swing knee lift
	var p := _carry()
	p["hL"] = Vector3(hip * s, 0, 0)
	p["hR"] = Vector3(-hip * s, 0, 0)
	# Knee flexes (-X) only mid-swing (peak at the leg's passing frame),
	# straight on contact and through stance — the two-joint gait.
	p["kL"] = Vector3(-knee * maxf(0.0, c), 0, 0)
	p["kR"] = Vector3(-knee * maxf(0.0, -c), 0, 0)
	return p


func _run_pose(time: float) -> Dictionary:
	var phase := time / RUN_LEN * TAU
	var s := sin(phase)
	var c := cos(phase)
	var hip := deg_to_rad(45)
	var knee := deg_to_rad(50)
	var p := _carry()
	p["spine"] = Vector3(-deg_to_rad(14), 0, 0)  # lean into the run
	p["head"] = Vector3(deg_to_rad(10), 0, 0)    # keep the head up
	p["hL"] = Vector3(hip * s, 0, 0)
	p["hR"] = Vector3(-hip * s, 0, 0)
	p["kL"] = Vector3(-knee * maxf(0.0, c), 0, 0)
	p["kR"] = Vector3(-knee * maxf(0.0, -c), 0, 0)
	return p


## The crouch itself: legs folded, torso leaning out over the knees, head lifted
## back to level. Arms tuck in closer than the standing carry, so the gun comes
## in tight to the chest the way it does when you hunker down.
func _crouch_base() -> Dictionary:
	var hip := deg_to_rad(CROUCH_HIP_DEG)
	var knee := deg_to_rad(CROUCH_KNEE_DEG)
	var p := _carry()
	p["spine"] = Vector3(-deg_to_rad(CROUCH_LEAN_DEG), 0, 0)
	p["head"] = Vector3(deg_to_rad(CROUCH_HEAD_DEG), 0, 0)
	# The arms are left exactly as _carry() solved them. The gun hangs off the
	# SPINE, so leaning the torso carries the weapon and both hands with it as
	# one piece — the old pose had to pitch the shoulders back by the lean angle
	# to keep the gun level, and doing that now would drag the hands off it.
	p["hL"] = Vector3(hip, 0, 0)
	p["hR"] = Vector3(hip, 0, 0)
	p["kL"] = Vector3(-knee, 0, 0)
	p["kR"] = Vector3(-knee, 0, 0)
	return p


func _crouch_idle_pose(_time: float) -> Dictionary:
	return _crouch_base()


## Where the hips sit while crouched. The bob function returns an OFFSET from
## the standing hip height (see _clip), so this is the drop, not the height.
func _crouch_idle_hips(time: float) -> Vector3:
	var breathe := 0.008 * sin(time / CROUCH_IDLE_LEN * TAU)
	return Vector3(0, CROUCH_HIP_DROP + breathe, 0)


## Crouch-walking is a waddle: the legs stay folded and take short alternating
## steps around the crouched angle, never straightening back to a standing gait.
##
## The knee holds the base fold through stance and only tucks FURTHER on the leg
## swinging through. That direction matters: with the knee fixed, swinging the
## hip either way SHORTENS the leg (the fold is deepest at the base angle), so
## the planted foot can only rise off the floor, never sink through it. Letting
## the trailing knee open — the obvious way to write this — lengthens the leg
## instead and buries the foot 3 cm in the ground.
func _crouch_walk_pose(time: float) -> Dictionary:
	var phase := time / CROUCH_WALK_LEN * TAU
	var s := sin(phase)
	var c := cos(phase)
	var swing := deg_to_rad(CROUCH_SWING_DEG)
	var lift := deg_to_rad(CROUCH_LIFT_DEG)
	var p := _crouch_base()
	var hip := deg_to_rad(CROUCH_HIP_DEG)
	var knee := deg_to_rad(CROUCH_KNEE_DEG)
	p["hL"] = Vector3(hip + swing * s, 0, 0)
	p["hR"] = Vector3(hip - swing * s, 0, 0)
	p["kL"] = Vector3(-knee - lift * maxf(0.0, c), 0, 0)
	p["kR"] = Vector3(-knee - lift * maxf(0.0, -c), 0, 0)
	return p


## Stepping from a fold this deep rocks the body, twice a cycle. The offset is
## kept non-negative for the same reason the knee only ever tucks further: the
## hips carry the feet with them, so a downward offset would push them through
## the floor.
func _crouch_walk_hips(time: float) -> Vector3:
	var rock := 0.018 * absf(sin(time / CROUCH_WALK_LEN * TAU))
	return Vector3(0, CROUCH_HIP_DROP + rock, 0)


## The saber guard: weight settled back onto bent knees, torso bladed so the
## shoulder leads rather than the chest, and the weapon lifted up across the body
## with both hands still on it.
##
## The arms are re-solved against the RAISED weapon rather than posed by hand,
## for the same reason the carry is: the grips come off the gun's transform, so
## the hold survives any change to where the guard puts the blade. Posing the
## shoulders directly would put the hands next to a weapon that had moved.
##
## The head is turned back by exactly the amount the spine turned away, so the
## visor keeps facing whoever you are guarding against — the torso blades, the
## look does not.
func _guard_base() -> Dictionary:
	var hip := deg_to_rad(GUARD_HIP_DEG)
	var knee := deg_to_rad(GUARD_KNEE_DEG)
	var turn := deg_to_rad(GUARD_TURN_DEG)
	var p := _carry()
	if _guard_hold.is_empty():
		_guard_hold = _hold(GUARD_GUN_POS, GUARD_GUN_ROT)
	p.merge(_guard_hold, true)
	p["gun"] = GUARD_GUN_ROT
	p["gun_pos"] = GUARD_GUN_POS
	p["spine"] = Vector3(-deg_to_rad(GUARD_LEAN_DEG), turn, 0.0)
	p["head"] = Vector3(deg_to_rad(GUARD_LEAN_DEG), -turn, 0.0)
	p["hL"] = Vector3(hip, 0, 0)
	p["hR"] = Vector3(hip, 0, 0)
	p["kL"] = Vector3(-knee, 0, 0)
	p["kR"] = Vector3(-knee, 0, 0)
	return p


func _guard_idle_pose(_time: float) -> Dictionary:
	return _guard_base()


## Holding a guard is work: the stance breathes rather than standing frozen.
func _guard_idle_hips(time: float) -> Vector3:
	var breathe := 0.007 * sin(time / GUARD_IDLE_LEN * TAU)
	return Vector3(0, GUARD_HIP_DROP + breathe, 0)


## Walking behind the blade. Same rule as the crouch shuffle, and for the same
## reason: with the knee held at a fixed fold, swinging the hip either way only
## SHORTENS the leg, so the knee may tuck further but must never open — letting
## the trailing knee straighten lengthens the leg and drives the foot into the
## floor. The stance never returns to a standing gait, which is what keeps the
## guard readable while its owner is closing the distance.
func _guard_walk_pose(time: float) -> Dictionary:
	var phase := time / GUARD_WALK_LEN * TAU
	var s := sin(phase)
	var c := cos(phase)
	var hip := deg_to_rad(GUARD_HIP_DEG)
	var knee := deg_to_rad(GUARD_KNEE_DEG)
	var swing := deg_to_rad(GUARD_SWING_DEG)
	var lift := deg_to_rad(GUARD_LIFT_DEG)
	var p := _guard_base()
	p["hL"] = Vector3(hip + swing * s, 0, 0)
	p["hR"] = Vector3(hip - swing * s, 0, 0)
	p["kL"] = Vector3(-knee - lift * maxf(0.0, c), 0, 0)
	p["kR"] = Vector3(-knee - lift * maxf(0.0, -c), 0, 0)
	return p


## Non-negative for the same reason the crouch rock is: the hips carry the feet,
## so a downward offset would push them through the floor.
func _guard_walk_hips(time: float) -> Vector3:
	var rock := 0.012 * absf(sin(time / GUARD_WALK_LEN * TAU))
	return Vector3(0, GUARD_HIP_DROP + rock, 0)


func _jump_pose(_time: float) -> Dictionary:
	# One simple held tuck (both keys identical): lead knee up, trail leg back,
	# hands stay on the gun. player.gd holds the last frame while airborne.
	var p := _carry()
	p["hL"] = Vector3(deg_to_rad(35), 0, 0)
	p["hR"] = Vector3(-deg_to_rad(18), 0, 0)
	p["kL"] = Vector3(-deg_to_rad(55), 0, 0)
	p["kR"] = Vector3(-deg_to_rad(12), 0, 0)
	return p
