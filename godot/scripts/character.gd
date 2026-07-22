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

# Proportions in metres. Feet rest at y = 0 and the model faces -Z.
const HIP_Y := 0.9
const UPPER_LEG := 0.46
const LOWER_LEG := 0.44
const TORSO := 0.62
const SHOULDER_Y := 0.5   # above the hips
const SHOULDER_X := 0.24
const HIP_X := 0.11
const UPPER_ARM := 0.34
const LOWER_ARM := 0.32

# Held-gun position, spine-local (in front of the chest, barrel toward -Z).
const GUN_POS := Vector3(0.0, 0.34, -0.24)

const IDLE_LEN := 2.4
const WALK_LEN := 1.0
const RUN_LEN := 0.7
const JUMP_LEN := 0.35
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
# Hip height that pose actually produces: both segments fold to the same angle.
const CROUCH_HIP_Y := (UPPER_LEG + LOWER_LEG) * cos(deg_to_rad(CROUCH_HIP_DEG))
const CROUCH_LEAN_DEG := 26.0  # torso out over the knees
const CROUCH_HEAD_DEG := 21.0  # ...and the head back up, so the visor faces front
const CROUCH_SWING_DEG := 26.0  # hip swing either side of the fold, when shuffling
const CROUCH_LIFT_DEG := 20.0   # extra knee tuck on the leg swinging through

# Short name -> node path (relative to this Character) for the animated joints.
const PATHS := {
	"spine": "Hips/Spine",
	"head": "Hips/Spine/Head",
	"sL": "Hips/Spine/ShoulderL", "eL": "Hips/Spine/ShoulderL/ElbowL",
	"sR": "Hips/Spine/ShoulderR", "eR": "Hips/Spine/ShoulderR/ElbowR",
	"hL": "Hips/HipL", "kL": "Hips/HipL/KneeL",
	"hR": "Hips/HipR", "kR": "Hips/HipR/KneeR",
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


func _box(parent: Node3D, size: Vector3, center: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = center
	mi.material_override = mat
	parent.add_child(mi)


## Tint the suit (torso + upper limbs) so teams are readable at a glance.
func set_team_color(c: Color) -> void:
	if _suit_mat:
		_suit_mat.albedo_color = c


func _build_body() -> void:
	var suit := _mat(Color(0.50, 0.53, 0.60))
	_suit_mat = suit
	var dark := _mat(Color(0.28, 0.30, 0.36))
	var head_mat := _mat(Color(0.82, 0.80, 0.78))
	var visor := _mat(Color(0.08, 0.09, 0.12))

	var hips := _joint(self, "Hips", Vector3(0, HIP_Y, 0))

	# Torso pivots at the hips so run/idle can lean from the waist.
	var spine := _joint(hips, "Spine", Vector3.ZERO)
	_box(spine, Vector3(0.42, TORSO, 0.24), Vector3(0, TORSO * 0.5, 0), suit)
	_box(spine, Vector3(0.44, 0.12, 0.26), Vector3(0, 0.06, 0), dark)  # belt

	var head := _joint(spine, "Head", Vector3(0, TORSO, 0))
	_box(head, Vector3(0.28, 0.30, 0.28), Vector3(0, 0.15, 0), head_mat)
	_box(head, Vector3(0.24, 0.09, 0.02), Vector3(0, 0.15, -0.14), visor)  # visor (front = -Z)

	for side in [-1, 1]:
		var sn := "L" if side < 0 else "R"
		var sh := _joint(spine, "Shoulder" + sn, Vector3(side * SHOULDER_X, SHOULDER_Y, 0))
		_box(sh, Vector3(0.13, UPPER_ARM, 0.13), Vector3(0, -UPPER_ARM * 0.5, 0), suit)
		var el := _joint(sh, "Elbow" + sn, Vector3(0, -UPPER_ARM, 0))
		_box(el, Vector3(0.12, LOWER_ARM, 0.12), Vector3(0, -LOWER_ARM * 0.5, 0), dark)
		_box(el, Vector3(0.13, 0.10, 0.14), Vector3(0, -LOWER_ARM, 0), dark)  # hand

	# Third-person blaster, held two-handed in front. Other players see this;
	# the owner sees only the first-person viewmodel. Parented to the spine so
	# it leans with the torso and the CARRY arm pose keeps the hands on it.
	var gunmetal := _mat(Color(0.10, 0.10, 0.12))
	var held := _joint(spine, "HeldGun", GUN_POS)
	_box(held, Vector3(0.05, 0.06, 0.24), Vector3(0, 0, 0.01), gunmetal)        # receiver
	_box(held, Vector3(0.028, 0.028, 0.30), Vector3(0, 0.012, -0.22), gunmetal)  # barrel
	_box(held, Vector3(0.035, 0.10, 0.05), Vector3(0, -0.06, 0.075), gunmetal)   # grip

	for side in [-1, 1]:
		var ln := "L" if side < 0 else "R"
		var hip := _joint(hips, "Hip" + ln, Vector3(side * HIP_X, 0, 0))
		_box(hip, Vector3(0.17, UPPER_LEG, 0.18), Vector3(0, -UPPER_LEG * 0.5, 0), suit)
		var knee := _joint(hip, "Knee" + ln, Vector3(0, -UPPER_LEG, 0))
		_box(knee, Vector3(0.16, LOWER_LEG, 0.17), Vector3(0, -LOWER_LEG * 0.5, 0), dark)
		_box(knee, Vector3(0.17, 0.09, 0.26), Vector3(0, -LOWER_LEG + 0.045, -0.06), dark)  # foot


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
	anim_player.add_animation_library("", lib)


func _clip(length: float, loop: bool, samples: int, pose_fn: Callable, bob_fn: Callable) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var tracks := {}
	for key in PATHS:
		var t := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(t, NodePath(PATHS[key]))
		tracks[key] = t
	var bob_track := -1
	if not bob_fn.is_null():
		bob_track = a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(bob_track, NodePath("Hips"))
	for i in samples:
		var time := length * float(i) / float(samples - 1)
		var pose: Dictionary = pose_fn.call(time)
		for key in PATHS:
			var e: Vector3 = pose.get(key, Vector3.ZERO)
			a.rotation_track_insert_key(tracks[key], time, Quaternion.from_euler(e))
		if bob_track >= 0:
			a.position_track_insert_key(bob_track, time, Vector3(0, HIP_Y, 0) + bob_fn.call(time))
	return a


# Both hands stay on the blaster in every clip, so the arms hold a fixed CARRY
# pose (legs do the locomotion). Shoulders come forward + inward and the elbows
# bend FORWARD (+X — a human elbow bends opposite a knee) to bring the hands
# together onto the gun in front of the chest.
func _carry() -> Dictionary:
	return {
		"sL": Vector3(deg_to_rad(46), deg_to_rad(-14), deg_to_rad(6)),
		"sR": Vector3(deg_to_rad(46), deg_to_rad(14), deg_to_rad(-6)),
		"eL": Vector3(deg_to_rad(64), 0, 0),
		"eR": Vector3(deg_to_rad(74), 0, 0),
	}


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
	# Leaning the torso forward would swing the arms down with it; bring the
	# shoulders back up by the same angle so the gun stays level.
	p["sL"] = Vector3(deg_to_rad(46 + CROUCH_LEAN_DEG), deg_to_rad(-18), deg_to_rad(6))
	p["sR"] = Vector3(deg_to_rad(46 + CROUCH_LEAN_DEG), deg_to_rad(18), deg_to_rad(-6))
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
	return Vector3(0, CROUCH_HIP_Y - HIP_Y + breathe, 0)


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
	return Vector3(0, CROUCH_HIP_Y - HIP_Y + rock, 0)


func _jump_pose(_time: float) -> Dictionary:
	# One simple held tuck (both keys identical): lead knee up, trail leg back,
	# hands stay on the gun. player.gd holds the last frame while airborne.
	var p := _carry()
	p["hL"] = Vector3(deg_to_rad(35), 0, 0)
	p["hR"] = Vector3(-deg_to_rad(18), 0, 0)
	p["kL"] = Vector3(-deg_to_rad(55), 0, 0)
	p["kR"] = Vector3(-deg_to_rad(12), 0, 0)
	return p
