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

const IDLE_LEN := 2.4
const WALK_LEN := 1.0
const RUN_LEN := 0.7
const JUMP_LEN := 0.35

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


func _build_body() -> void:
	var suit := _mat(Color(0.50, 0.53, 0.60))
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


func _idle_pose(_time: float) -> Dictionary:
	# Near-static; just a hair of elbow bend so the arms aren't board-stiff.
	return {"eL": Vector3(-deg_to_rad(12), 0, 0), "eR": Vector3(-deg_to_rad(12), 0, 0)}


func _idle_bob(time: float) -> Vector3:
	return Vector3(0, 0.012 * sin(time / IDLE_LEN * TAU), 0)


func _walk_pose(time: float) -> Dictionary:
	var phase := time / WALK_LEN * TAU
	var s := sin(phase)
	var c := cos(phase)
	var hip := deg_to_rad(30)   # whole-leg swing
	var knee := deg_to_rad(34)  # mid-swing knee lift
	var arm := deg_to_rad(24)
	return {
		"hL": Vector3(hip * s, 0, 0),
		"hR": Vector3(-hip * s, 0, 0),
		# Knee flexes (-X) only mid-swing (peak at the leg's passing frame),
		# straight on contact and through stance — the two-joint gait.
		"kL": Vector3(-knee * maxf(0.0, c), 0, 0),
		"kR": Vector3(-knee * maxf(0.0, -c), 0, 0),
		"sL": Vector3(-arm * s, 0, 0),  # arms counter-swing the same-side leg
		"sR": Vector3(arm * s, 0, 0),
		"eL": Vector3(-deg_to_rad(18), 0, 0),
		"eR": Vector3(-deg_to_rad(18), 0, 0),
	}


func _run_pose(time: float) -> Dictionary:
	var phase := time / RUN_LEN * TAU
	var s := sin(phase)
	var c := cos(phase)
	var hip := deg_to_rad(45)
	var knee := deg_to_rad(50)
	var arm := deg_to_rad(34)
	return {
		"spine": Vector3(-deg_to_rad(14), 0, 0),  # lean into the run
		"head": Vector3(deg_to_rad(10), 0, 0),    # keep the head up
		"hL": Vector3(hip * s, 0, 0),
		"hR": Vector3(-hip * s, 0, 0),
		"kL": Vector3(-knee * maxf(0.0, c), 0, 0),
		"kR": Vector3(-knee * maxf(0.0, -c), 0, 0),
		"sL": Vector3(-arm * s, 0, 0),
		"sR": Vector3(arm * s, 0, 0),
		"eL": Vector3(-deg_to_rad(50), 0, 0),
		"eR": Vector3(-deg_to_rad(50), 0, 0),
	}


func _jump_pose(_time: float) -> Dictionary:
	# One simple held tuck (both keys identical): lead knee up, trail leg back,
	# arms raised. player.gd holds the last frame while airborne.
	return {
		"hL": Vector3(deg_to_rad(35), 0, 0),
		"hR": Vector3(-deg_to_rad(18), 0, 0),
		"kL": Vector3(-deg_to_rad(55), 0, 0),
		"kR": Vector3(-deg_to_rad(12), 0, 0),
		"sL": Vector3(-deg_to_rad(28), 0, 0),
		"sR": Vector3(-deg_to_rad(28), 0, 0),
		"eL": Vector3(-deg_to_rad(42), 0, 0),
		"eR": Vector3(-deg_to_rad(42), 0, 0),
	}
