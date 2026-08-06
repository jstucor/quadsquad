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

## HOW MANY BODIES THE FLOOR HOLDS, AND WHO GETS ONE AT ALL.
##
## A corpse is not cheap and it is not brief: it builds a whole CharacterModel
## (thirty-odd meshes, every accessory the unit was wearing), it adds six rigid
## bodies and five joints, and it lies there for LIFETIME seconds being drawn
## once per viewport plus a shadow pass. One at a time that is a bargain. The
## trouble is that nothing bounded how many there could be at once, and the rate
## bodies arrive is set by the ROSTER: a 4-team match with six AI a side was
## measured holding TWELVE ragdolls simultaneously — seventy-two rigid bodies and
## four hundred-odd mesh instances drawn four times over — which is a steady load
## nobody asked for and a hitch every time a fresh one lands on top of it.
##
## Two rules, both of which the project already applies to smaller effects:
##
##   1. A DEATH NOBODY CAN SEE IS NOT WORTH BUILDING — the same rule and the same
##      distance as `Weapon.IMPACT_VIEW_RANGE`. On a 220 m map most deaths in a
##      big match are bots shooting bots somewhere else entirely, and every one
##      of those was building a body, simulating it for nine seconds and freeing
##      it with nobody watching.
##   2. THE FLOOR HAS A LIMIT. Past MAX_ALIVE the oldest body goes, because it is
##      the one that has been lying there longest and is likeliest to be behind
##      whoever is fighting now. A player never loses the body they just made.
##
## A human's own death always builds one (`forced`): you watch that one.
const VIEW_RANGE := 120.0
const MAX_ALIVE := 8
## Every ragdoll currently on the floor, oldest first. Static because the limit
## is a property of the MATCH, not of any one body — and cleaned of freed entries
## on the way past rather than by anything watching it.
static var _alive: Array[Node3D] = []

var _bodies := {}   # segment name -> RigidBody3D
var _stature := 1.0  # the unit's own size, so a corpse is as big as the unit was
var _animated: CharacterModel  # ANIMATED style only; null for the other two


## `style` is a CharacterModel.Style — which body this was. -1 falls back to the
## generic trooper, which is also what the classic flop always drew.
##
## `forced` skips the view-range test for a death that is always worth showing —
## a human's own. Returns having freed itself if the body is not wanted, so the
## caller pays for the instantiate and nothing else; every caller already guards
## its handle with `is_instance_valid`.
## `stature` is the unit's own size (Loadout.stature). A body does not change
## size when it dies — without this an Kobb's corpse stood up to full trooper
## height on the frame it hit the floor.
func launch(xform: Transform3D, team_color: Color, push_dir: Vector3,
		style := -1, forced := false, stature := 1.0) -> void:
	if not forced and not _worth_showing(xform.origin):
		queue_free()
		return
	_make_room()
	_alive.append(self)
	global_transform = xform
	reset_physics_interpolation()   # placed where somebody died, not moved there
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

	_stature = maxf(stature, 0.2)
	match Controls.death_style():
		Controls.Death.CLASSIC: _build_classic(team_color, push)
		Controls.Death.ANIMATED: _build_animated(team_color, style, push)
		_: _build_ragdoll(team_color, style, push)
	get_tree().create_timer(LIFETIME).timeout.connect(_safe_free)


## DEATH AS A CLIP. The same finished model the ragdoll is built from, NOT taken
## apart: it keeps its AnimationPlayer and plays one of `CharacterModel`'s death
## clips, which lays it down by rotating the Hips about the FEET (see the note on
## `build_death_clips`).
##
## The trade against the ragdoll, stated where somebody choosing between them
## will read it: this reads more cleanly and plays the same way every time, and
## it knows NOTHING about what it is falling onto. On the hand-laid arenas that
## barely shows. On the procedural worlds — where the collision mesh already sits
## above the analytic curve, which is what `SPAWN_LIFT` exists for — a body will
## sometimes end up part-way into a slope. That is the cost, it is real, and it
## is why the ragdoll is still the default rather than being replaced.
func _build_animated(team_color: Color, style: int, push: Vector3) -> void:
	var model := CharacterModel.new()
	# NOT `static_pose`: that flag exists to skip building clips for a body that
	# only ever wears one, and this one is about to play a clip.
	add_child(model)
	model.set_style(style if style >= 0 else CharacterModel.Style.GENERIC)
	model.set_team_color(team_color)
	model.scale = Vector3.ONE * _stature
	model.build_death_clips()
	_animated = model
	# WHICH WAY IT GOES DOWN COMES FROM THE SHOVE, so a canned fall still answers
	# the one question the ragdoll answered for free — where the shot came from.
	# Taken in the body's own space, so a round in the back drops it forward
	# whatever direction it was facing when it was hit.
	var fall := CharacterModel.fall_from_push(push, global_rotation.y)
	var clip: String = CharacterModel.DEATH_CLIPS[fall]
	if model.anim_player != null and model.anim_player.has_animation(clip):
		# The last frame HOLDS: an AnimationPlayer that finishes a non-looping clip
		# leaves the joints where the final key put them, which is exactly the
		# behaviour the jump clip already relies on.
		model.anim_player.play(clip)


## Stop the whole ragdoll dead, for anything that wants to photograph the POSE
## rather than the fall (tests/death_look.tscn). One call rather than the caller
## walking six bodies and needing to know there are six.
func freeze_all() -> void:
	for child in get_children():
		if child is RigidBody3D:
			child.freeze = true
			child.linear_velocity = Vector3.ZERO
			child.angular_velocity = Vector3.ZERO
	# An animated corpse has no bodies to stop — what holds it still is pausing
	# the clip. Same call, same contract: whatever is moving, stop it, so a look
	# test photographs a pose rather than a blur.
	if _animated != null and is_instance_valid(_animated) \
			and _animated.anim_player != null:
		_animated.anim_player.pause()


func _safe_free() -> void:
	if is_instance_valid(self):
		queue_free()


## Is anybody with a camera near enough for this to be worth building? Humans
## only — bots have no camera, so a body dropping beside one is seen by nobody.
## Walks GameState.combatants for the same reason `Weapon._worth_showing` does:
## the list is already there and is at most a couple of dozen entries.
static func _worth_showing(at: Vector3) -> bool:
	for c in GameState.combatants:
		if c is Player and is_instance_valid(c) \
				and c.global_position.distance_to(at) <= VIEW_RANGE:
			return true
	return false


## Drop dead entries, then free the oldest until there is room for one more.
## Done on the way IN rather than on a timer: the moment that needs the room is
## the moment a new body arrives, and that is also the only moment this list is
## touched, so nothing has to watch it.
static func _make_room() -> void:
	var live: Array[Node3D] = []
	for c in _alive:
		if is_instance_valid(c):
			live.append(c)
	while live.size() >= MAX_ALIVE:
		var oldest: Node3D = live.pop_front()
		oldest.queue_free()
	_alive = live


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
	# Scaled BEFORE the joints are read, so every joint's world transform — and
	# therefore every mesh that rides it through the reparent — is already the
	# right size. The rigid bodies themselves are left unscaled (see _segment).
	model.scale = Vector3.ONE * _stature
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
		# ORTHONORMALIZED: a scaled unit's joints carry that scale in their
		# basis, and a RigidBody3D with a scaled basis scales its collision
		# shape a second time on top of the size set below — as well as being
		# the thing Godot warns about doing to a physics body. The body stays
		# unit-scale and the meshes keep their own scale through the reparent.
		body.global_transform = first.global_transform.orthonormalized()
	for jname in seg["joints"]:
		var joint: Node3D = joints.get(jname)
		if joint != null:
			joint.reparent(body, true)   # keeping its world transform

	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = seg["size"] * _stature
	cs.shape = box
	cs.position = seg["at"] * _stature
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
	cap.radius = 0.34 * _stature
	cap.height = 1.5 * _stature
	cs.shape = cap
	cs.position.y = 0.85 * _stature
	body.add_child(cs)
	# The meshes hang off a scaled NODE rather than off the body: scaling the
	# RigidBody3D itself would scale the shape above a second time, which is
	# also the thing Godot warns about doing to a physics body.
	var art := Node3D.new()
	art.scale = Vector3.ONE * _stature
	body.add_child(art)

	var suit := _mat(team_color)
	var dark := _mat(Color(0.28, 0.30, 0.36))
	var head := _mat(Color(0.82, 0.80, 0.78))
	_box(art, Vector3(0.42, 0.62, 0.24), Vector3(0, 1.2, 0), suit)      # torso
	_box(art, Vector3(0.28, 0.30, 0.28), Vector3(0, 1.68, 0), head)     # head
	_box(art, Vector3(0.5, 0.12, 0.12), Vector3(-0.34, 1.35, 0), dark)  # left arm
	_box(art, Vector3(0.5, 0.12, 0.12), Vector3(0.34, 1.35, 0), dark)   # right arm
	_box(art, Vector3(0.16, 0.85, 0.17), Vector3(-0.12, 0.42, 0), suit) # left leg
	_box(art, Vector3(0.16, 0.85, 0.17), Vector3(0.12, 0.42, 0), suit)  # right leg

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
