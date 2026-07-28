extends Node3D
## Death: an ARTICULATED RAGDOLL wearing the dead unit's own body, thrown by
## whatever killed it, left to fall apart for the respawn countdown and then
## freed.
##
## It used to be one stiff rigid body that tumbled, on the argument that the
## motion the eye reads as "they went down" is the tumble and a jointed solver
## would cost four viewports of work per death. Half of that was wrong: the
## RENDER cost is identical either way — the same meshes, drawn the same number
## of times — and what a ragdoll adds is physics bodies, which are simulated
## ONCE regardless of how many cameras are looking.
##
## SIX segments, not eleven: torso, head, two arms, two legs. A forearm and a
## shin that hinge separately are a fuller ragdoll, but at this scale — box limbs
## seen from across a map — they cost twice the bodies and twice the joints to
## say something nobody can see. These are the segments whose SILHOUETTE changes
## when a body goes down.
##
## CLASSIC DEATH (Controls.classic_death, on the controls screen) still gives the
## original: a generic box figure with its arms straight out, on a single body.
## It reads as a T-posing mannequin, which is why it is worth keeping — and it is
## also the cheap path if six bodies a corpse ever stops fitting the Pi budget.

const LIFETIME := 9.0  # safety self-free if nobody else cleans it up

## The ragdoll. Each segment names the model joints that ride on it and the box
## that collides for it — `size` in metres, `at` the box's centre in the
## segment's own space (the joint itself sits at that space's origin).
##
## Masses are RATIOS, not kilograms, and getting them wrong is how a ragdoll
## explodes: a heavy head on a light torso whips, and near-equal masses either
## side of a joint make the solver argue with itself. Roughly anatomical works.
const SEGMENTS := [
	{"name": "torso", "joints": ["Hips"], "mass": 32.0,
		"size": Vector3(0.34, 0.62, 0.26), "at": Vector3(0.0, 0.24, 0.0)},
	{"name": "head", "joints": ["Head"], "mass": 5.0, "parent": "torso",
		"size": Vector3(0.22, 0.26, 0.24), "at": Vector3(0.0, 0.16, 0.0)},
	{"name": "armL", "joints": ["ShoulderL"], "mass": 4.0, "parent": "torso",
		"size": Vector3(0.14, 0.44, 0.14), "at": Vector3(-0.02, -0.20, 0.0)},
	{"name": "armR", "joints": ["ShoulderR"], "mass": 4.0, "parent": "torso",
		"size": Vector3(0.14, 0.44, 0.14), "at": Vector3(0.02, -0.20, 0.0)},
	{"name": "legL", "joints": ["HipL"], "mass": 11.0, "parent": "torso",
		"size": Vector3(0.17, 0.82, 0.19), "at": Vector3(0.0, -0.40, 0.0)},
	{"name": "legR", "joints": ["HipR"], "mass": 11.0, "parent": "torso",
		"size": Vector3(0.17, 0.82, 0.19), "at": Vector3(0.0, -0.40, 0.0)},
]

## Damping is what separates a ragdoll from a rag: with none, limbs windmill and
## the body never settles inside its own lifetime. It is also what stands in for
## the joint limits a pin joint does not have (see _pin).
const LINEAR_DAMP := 0.4
const ANGULAR_DAMP := 4.5

var _bodies := {}   # segment name -> RigidBody3D


## `style` is a CharacterModel.Style — which body this was. -1 falls back to the
## generic trooper, which is also what the classic flop always drew.
func launch(xform: Transform3D, team_color: Color, push_dir: Vector3,
		style := -1) -> void:
	global_transform = xform
	var push := push_dir
	push.y = 0.0
	if push.length() < 0.1:
		push = -global_transform.basis.z
	# GENTLER THAN THE OLD SINGLE BODY, and it has to be. That one impulse used
	# to move one mass through one capsule's worth of drag; the same numbers
	# applied to six lighter segments threw the corpse clean out of frame. A body
	# should drop roughly where it was standing — the reason to see it is to know
	# somebody died there.
	# HORIZONTAL, and small. There is no upward component at all: a body that is
	# shot does not hop, it drops, and every joule of "up" put in here has to be
	# paid back by gravity before anything starts falling. The shove exists only
	# to decide which way it topples — the fall itself is gravity's job, which is
	# the entire point of having a ragdoll.
	push = push.normalized() * randf_range(0.8, 1.6)

	if Controls.classic_death():
		_build_classic(team_color, push)
	else:
		_build_ragdoll(team_color, style, push)
	get_tree().create_timer(LIFETIME).timeout.connect(_safe_free)


## Stop the whole ragdoll dead, for anything that wants to photograph the POSE
## rather than the fall (tests/death_look.tscn). One call rather than the caller
## walking six bodies and needing to know there are six.
func freeze_all() -> void:
	for child in get_children():
		if child is RigidBody3D:
			child.freeze = true
			child.linear_velocity = Vector3.ZERO
			child.angular_velocity = Vector3.ZERO


func _safe_free() -> void:
	if is_instance_valid(self):
		queue_free()


## --- the ragdoll --------------------------------------------------------------

func _build_ragdoll(team_color: Color, style: int, push: Vector3) -> void:
	# The model is built and posed exactly as it always was — same style, same
	# limp collapse pose — and only THEN taken apart. Building it whole first is
	# what keeps every mesh, colour and accessory right without the ragdoll
	# knowing anything about how a body is put together.
	var model := CharacterModel.new()
	model.static_pose = true          # nothing animates a corpse
	add_child(model)
	model.set_style(style if style >= 0 else CharacterModel.Style.GENERIC)
	model.set_team_color(team_color)
	# LEFT IN ITS STANDING REST POSE, and this is the whole difference between a
	# ragdoll and a puppet. The old corpse was posed into a hand-authored curl
	# (`collapse_pose`) because it was ONE rigid body and had no other way to
	# look dead. Doing that to a ragdoll is wrong twice over: the curl is the
	# fetal tuck the body then falls in, and the hip drop it needs put the leg
	# collision boxes 44 cm THROUGH the floor, which the solver resolves by
	# ejecting the whole corpse several metres into the air.
	#
	# Standing, every segment's box starts clear of the ground, and the fold on
	# the way down is solved rather than drawn.
	model.force_update_transform()

	# RESOLVE EVERY JOINT BEFORE MOVING ANY OF THEM. The segments are nested in
	# the model — Head, ShoulderL and HipL are all children of Hips — so the
	# moment the torso reparents Hips onto its body, searching the model for any
	# of the others finds nothing.
	#
	# That was not a small bug. Five of the six bodies came back empty and stayed
	# at the corpse's origin, still pinned to a torso a metre above them, and the
	# joints hauled them up to where they belonged: a body launching several
	# metres into the air, and no limb ever actually articulating, because every
	# mesh was still hanging off Hips on the one body that did resolve.
	var joints := {}
	for seg in SEGMENTS:
		for jname in seg["joints"]:
			joints[jname] = _find(model, jname)

	for seg in SEGMENTS:
		_bodies[seg["name"]] = _segment(joints, seg, push)
	for seg in SEGMENTS:
		if seg.has("parent"):
			_pin(_bodies[seg["parent"]], _bodies[seg["name"]])
	# The shell is empty now: every joint moved out of it onto a body.
	model.queue_free()


## One rigid segment: a body at the joint's current world transform, carrying
## whichever model joints ride on it.
func _segment(joints: Dictionary, seg: Dictionary, push: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.mass = seg["mass"]
	body.linear_damp = LINEAR_DAMP
	body.angular_damp = ANGULAR_DAMP
	# Collides with the WORLD only. A corpse must never block a doorway, shove a
	# player or stop a bullet — layer 0 means nothing can hit it, mask 1 means it
	# still lands on the floor.
	body.collision_layer = 0
	body.collision_mask = 1
	# No continuous detection: nothing here moves fast enough to tunnel now that
	# the launch is a shove rather than a throw, and CCD interacts badly with a
	# jointed stack — it resolves each body separately and the joints then argue
	# with the result.
	add_child(body)

	var first: Node3D = joints.get(seg["joints"][0])
	if first != null:
		body.global_transform = first.global_transform
	for jname in seg["joints"]:
		var joint: Node3D = joints.get(jname)
		if joint != null:
			joint.reparent(body, true)   # keeping its world transform

	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = seg["size"]
	cs.shape = box
	cs.position = seg["at"]
	body.add_child(cs)

	body.linear_velocity = push
	# A gentle shared tumble, not six independent spins: give every segment its
	# own big random spin and the joints spend the first half-second tearing
	# against each other, which reads as a glitch rather than as a fall.
	body.angular_velocity = Vector3(randf_range(-1.6, 1.6), randf_range(-1.2, 1.2),
		randf_range(-1.6, 1.6))
	return body


## Hang `child` off `parent` where the two meet.
##
## A PIN JOINT — a ball with no limits — and that choice is load-bearing. A
## cone-twist is the anatomically right shape (a shoulder IS a cone of swing plus
## a little twist) and it is what this was built with first, but a cone-twist's
## limits are measured about the JOINT'S OWN AXES, and the axes here come from
## the character rig, where an arm has a quarter turn baked into it and a leg
## points down. So the limbs started outside their own cones, the solver spent
## the first frames forcing five joints back inside their limits at once, and the
## energy it put in threw the corpse several metres straight up — with no upward
## impulse anywhere in this file.
##
## A pin joint has no limits to violate, so it cannot do that. What it costs is
## anatomy: an elbow or a knee can rotate somewhere a real one will not. At box-
## limb fidelity, seen for a few seconds from across a map, a limb at an odd
## angle is a far smaller lie than a body launching into the sky — and the
## angular damping above is what stops it looking boneless.
func _pin(parent: RigidBody3D, child: RigidBody3D) -> void:
	var joint := PinJoint3D.new()
	add_child(joint)
	# At the CHILD's origin, which is already the joint position — the arm
	# segment's origin is the shoulder, the leg segment's is the hip.
	joint.global_transform = child.global_transform
	joint.node_a = parent.get_path()
	joint.node_b = child.get_path()
	# Segments sharing a joint are touching by definition.
	joint.set_exclude_nodes_from_collision(true)


func _find(model: CharacterModel, jname: String) -> Node3D:
	return model.find_child(jname, true, false) as Node3D


## --- the classic flop ---------------------------------------------------------

## The original: a generic figure with its arms out to the sides, on ONE body.
func _build_classic(team_color: Color, push: Vector3) -> void:
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 1
	add_child(body)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.5
	cs.shape = cap
	cs.position.y = 0.85
	body.add_child(cs)

	var suit := _mat(team_color)
	var dark := _mat(Color(0.28, 0.30, 0.36))
	var head := _mat(Color(0.82, 0.80, 0.78))
	_box(body, Vector3(0.42, 0.62, 0.24), Vector3(0, 1.2, 0), suit)      # torso
	_box(body, Vector3(0.28, 0.30, 0.28), Vector3(0, 1.68, 0), head)     # head
	_box(body, Vector3(0.5, 0.12, 0.12), Vector3(-0.34, 1.35, 0), dark)  # left arm
	_box(body, Vector3(0.5, 0.12, 0.12), Vector3(0.34, 1.35, 0), dark)   # right arm
	_box(body, Vector3(0.16, 0.85, 0.17), Vector3(-0.12, 0.42, 0), suit) # left leg
	_box(body, Vector3(0.16, 0.85, 0.17), Vector3(0.12, 0.42, 0), suit)  # right leg

	body.linear_velocity = push
	body.angular_velocity = Vector3(randf_range(-7, 7), randf_range(-4, 4),
		randf_range(-7, 7))


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.0
	m.roughness = 0.75
	m.rim_enabled = true
	m.rim = 0.3
	return m


func _box(parent: Node3D, size: Vector3, center: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.chamfer_box(size)   # same bevel as the living body it came off
	mi.position = center
	mi.material_override = mat
	parent.add_child(mi)  # layer 1 (default): every camera sees a corpse
