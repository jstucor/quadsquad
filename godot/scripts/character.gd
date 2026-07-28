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
var _staff_parts: Array[MeshInstance3D] = []
## The joint the held weapon hangs off, kept so the melee parts can be rebuilt
## for a different blade without touching the rest of the rig.
var _held: Node3D
## Which melee weapon is currently modelled here (Weapon.melee_look()). Compared
## rather than reapplied, so a rebuild only happens on an actual weapon swap.
var _melee_look := {}
## Which render layer this model's meshes belong on, REMEMBERED rather than
## stamped once from outside. Fresh MeshInstance3Ds default to the shared layer,
## and this model rebuilds itself in two places now — a style change and a melee
## swap — so an owner that stamped its layer at spawn would see its own
## third-person blade hanging in front of its camera the first time it drew one.
## Exactly the trap the viewmodel's view_layer exists to avoid, same shape.
var render_layers := 0
## The upper body's yaw relative to the legs, in radians (see set_twist). Kept on
## the model rather than written straight onto the node, so a style rebuild — the
## one thing that frees and replaces the whole joint tree — restores it.
var _twist := 0.0
var _twist_joint: Node3D

# Proportions in metres. Feet rest at y = 0 and the model faces -Z.
#
# These are the retired trooper's own bone lengths, measured off the model and
# scaled to the 1.82 m the game is built around, and kept because the animations
# were tuned to them. Now the boxes are BUILT to fit the rig rather than the rig
# fitted to a mesh, but the proportions stay so the gait, crouch and guard are
# unchanged. It costs the animation nothing: every clip is a set of joint
# ROTATIONS, so a limb length only changes where a box reaches, not how it moves.
## Written out rather than computed, because a
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

# Held-gun transform, spine-local. The barrel runs toward -Z, and the model
# faces -Z, so +X is the character's own RIGHT.
#
# A RIFLE IS CARRIED ON THE RIGHT SHOULDER, NOT FLAT ACROSS THE CHEST. The old
# pose sat the weapon dead-centre (x = 0) with no rotation, which put the
# receiver in the middle of the sternum and both arms in a symmetric hug — the
# single most toy-like thing about the model, and very visible on the wide-
# shouldered units where the gun read as a bar sticking out of the ribs.
#
# So: pushed out to the right, and yawed so the muzzle crosses slightly inward
# with a small cant. That makes the hold ASYMMETRIC, which is what a real one is
# — the right hand tucks in at the trigger (it solves to ~55% arm extension) and
# the left reaches across the body to the handguard (~94%). Nothing else had to
# change: _hold() solves both arms onto grip points in the WEAPON's own space, so
# moving the weapon carries the hands, and every clip is built from _carry().
## Tuned against the ARM EXTENSION the solve comes out at, because that is what
## decides whether the pose reads as a hold or as a reach: pushed out to
## x 0.10 / z -0.235 the left arm solved to 94% of its length, and a two-bone IK
## at 94% is a straight arm, which drags the shoulder up and gives every unit a
## hunch. Drawn in and yawed further across, the left settles at ~86% (a bent
## elbow) and the right at ~52% (tucked in at the trigger).
const GUN_POS := Vector3(0.085, 0.29, -0.20)
const GUN_ROT := Vector3(0.0, deg_to_rad(20.0), deg_to_rad(-6.0))

## THE SPRINT CARRY. Dropped from chest height, pulled in tight against the body
## and yawed most of the way across so the barrel lies over the chest rather than
## pointing where the eyes are. The big number is the YAW: at the carry's 20
## degrees a running figure still reads as aiming, and it is only past about 55
## that the weapon reads as stowed.
##
## Both hands stay on it — this goes through _hold like every other pose — so the
## arms are still a hold rather than swinging free. That is deliberate: a rifle
## needs two hands whatever you are doing with your legs, and the arms swinging
## empty while a gun floats alongside is worse than no sprint carry at all.
const RUN_GUN_POS := Vector3(0.05, 0.235, -0.135)
const RUN_GUN_ROT := Vector3(deg_to_rad(-6.0), deg_to_rad(62.0), deg_to_rad(-14.0))

# The third-person lightsaber. Longer than the first-person blade (0.78 m): that
# one is foreshortened by a camera 30 cm from the hilt, while this one is judged
# from across the map, where the blade IS the silhouette.
const BLADE_LENGTH := 1.25
const BLADE_WIDTH := 0.05
## What viewmodel.gd draws for the LIGHTSABER, in its own first-person scale.
## A weapon states its blade in those numbers (Weapon.melee_look), and this pair
## is what converts them to the third-person size above — one source of truth for
## how long a blade is, two viewing distances.
const VM_BLADE_LEN := 0.78
const VM_BLADE_WIDTH := 0.038
const BLADE_CORE := Color(0.75, 0.92, 1.0)
const BLADE_GLOW := Color(0.25, 0.65, 1.0)
# The electrostaff's charge is violet, not the saber's blue (the IG-100 look).
const STAFF_CORE := Color(0.86, 0.62, 1.0)
const STAFF_GLOW := Color(0.58, 0.16, 0.98)

## STANDING STILL, A BODY STANDS WITH ITS FEET APART. Legs together under the
## hips is a mannequin on a stand; a shoulder-width stance is what a person at
## rest — never mind a soldier expecting to be shot at — actually does, and it
## widens the silhouette, which is worth something on a four-way split screen.
##
## Splayed at the HIP (a roll about Z), so the thighs open outward and the knees
## follow. Only the standing clips get it: walk and run put the legs back under
## the body, which is where they have to be to carry it.
const STANCE_SPLAY_DEG := 7.0
## ...and the hips have to COME DOWN by what the splay costs in height, or the
## feet hang above the floor. A leg rolled out by t reaches `LEG * cos t` down
## instead of `LEG`, exactly the rule CROUCH_HIP_DROP follows -- and, like it, a
## fraction of the LEG rather than of HIP_Y (see the note there). The ankle
## column of tests/guard_pose.tscn is what catches getting this wrong.
const STANCE_HIP_DROP := LEG * (cos(deg_to_rad(STANCE_SPLAY_DEG)) - 1.0)
## The feet turn out with the splay, the way a real stance does.
const STANCE_TOE_OUT_DEG := 5.0

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
## NOTE THE `Twist` NODE between the hips and the spine. Nothing animates it —
## it exists precisely so that the runtime torso twist (set_twist) has a joint of
## its own to write, above the legs and below everything else.
##
## Laying the twist on the Spine instead would put it in a fight with the
## AnimationPlayer, which rewrites every joint in this table every frame. That is
## the same trap recorded for the crouch: anything applied ON TOP of a clip
## survives only by process ordering. A joint the clips never name cannot be
## clobbered, and needs no ordering rule to be correct.
const PATHS := {
	"spine": "Hips/Twist/Spine",
	"head": "Hips/Twist/Spine/Head",
	"sL": "Hips/Twist/Spine/ShoulderL", "eL": "Hips/Twist/Spine/ShoulderL/ElbowL",
	"sR": "Hips/Twist/Spine/ShoulderR", "eR": "Hips/Twist/Spine/ShoulderR/ElbowR",
	"hL": "Hips/HipL", "kL": "Hips/HipL/KneeL",
	"hR": "Hips/HipR", "kR": "Hips/HipR/KneeR",
	"gun": "Hips/Twist/Spine/HeldGun",
}


## Build the rig but NOT the AnimationPlayer. A corpse wears one pose for the
## few seconds it exists, and building eight clips (eleven tracks each, sampled
## nine times, per death, four viewports deep) to hold one of them still is work
## nobody sees. Set it before the model enters the tree.
var static_pose := false


func _ready() -> void:
	_build_body()
	if not static_pose:
		_build_animations()


# --- rig construction ------------------------------------------------------

## HOW A SURFACE IS FINISHED, which is most of what tells two materials apart at
## a glance. Everything used to come back at metallic 0 / roughness 0.75, so a
## ceramic plate, a rubber undersuit and a gun barrel all caught the light
## identically and the whole model read as one moulded piece.
##
## The metallic values are usable again because the sky is graded now (see
## Arena._grade_environment): the old "keep metallic under 0.15" rule existed
## because metal reflected a near-black void and rendered as a black hole. Give
## it a sky with a horizon in it and metal reflects something.
enum Finish { PLATE, CLOTH, METAL, HIDE }
const FINISHES := {
	# Armour plate: hard, slightly glossy, a touch of specular sheen.
	Finish.PLATE: {"metallic": 0.15, "roughness": 0.45, "rim": 0.35},
	# Undersuit, webbing, boot rubber: matte and light-swallowing.
	Finish.CLOTH: {"metallic": 0.0, "roughness": 0.92, "rim": 0.15},
	# Gun bodies, staff poles, exposed frame: properly metallic.
	Finish.METAL: {"metallic": 0.75, "roughness": 0.32, "rim": 0.45},
	# Fur, skin, bone: matte with a strong rim, which is what reads as a soft
	# edge against a hard one.
	Finish.HIDE: {"metallic": 0.0, "roughness": 0.85, "rim": 0.5},
}


## `rim` is a fresnel term that brightens a surface as it turns away from the
## camera — which on a box lands as a bright line down every silhouette edge.
## That is the cheapest available stand-in for a CHAMFER: a real bevel would
## quadruple the triangle count of every body part (thirty boxes a character,
## four viewports, plus a shadow pass), and this costs one extra term in a shader
## that is already running.
func _mat(color: Color, finish := Finish.PLATE) -> StandardMaterial3D:
	var f: Dictionary = FINISHES[finish]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = f["metallic"]
	m.roughness = f["roughness"]
	m.rim_enabled = true
	m.rim = f["rim"]
	m.rim_tint = 0.35   # toward the light's colour rather than the albedo's
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


## Tint the team frame (torso, hips, upper limbs) so sides read at a glance.
## Stored, so a set_style rebuild keeps the colour instead of reverting to grey.
func set_team_color(c: Color) -> void:
	_team_color = c
	if _suit_mat:
		_suit_mat.albedo_color = c


# Skeleton offsets in metres, from the retired trooper's own bones (scaled to the
# game's 1.82 m character). The MESH is procedural now, but keeping the exact RIG
# proportions means every animation — foot placement, the solved carry pose, the
# crouch and guard hip drops — lands precisely where it always did.
const _SKEL := 1.82 / 2.055
const _B_PELVIS := Vector3(0.0, 1.159, 0.0)
const _B_NECK := Vector3(0.0, 1.716, 0.018)
const _B_UPPERARM := Vector3(0.229, 1.649, 0.045)
const _B_FOREARM := Vector3(0.462, 1.638, 0.100)
const _B_THIGH := Vector3(0.094, 1.054, -0.009)
const _B_CALF := Vector3(0.169, 0.581, -0.024)


## Each joint's position RELATIVE TO ITS PARENT. The arms get a quarter-turn
## correction that turns the T-pose bone into a hanging-arm offset — the same
## correction the old trooper parts used, so the arms hang down, not out.
func _joint_offsets() -> Dictionary:
	var out := {}
	out["head"] = (_B_NECK - _B_PELVIS) * _SKEL
	for side in [-1.0, 1.0]:
		var sn := "L" if side < 0.0 else "R"
		var upper := Vector3(_B_UPPERARM.x * side, _B_UPPERARM.y, _B_UPPERARM.z)
		var fore := Vector3(_B_FOREARM.x * side, _B_FOREARM.y, _B_FOREARM.z)
		out["s" + sn] = (upper - _B_PELVIS) * _SKEL
		out["e" + sn] = _arm_correction(sn) * ((fore - upper) * _SKEL)
		var thigh := Vector3(_B_THIGH.x * side, _B_THIGH.y, _B_THIGH.z)
		var calf := Vector3(_B_CALF.x * side, _B_CALF.y, _B_CALF.z)
		out["h" + sn] = (thigh - _B_PELVIS) * _SKEL
		out["k" + sn] = (calf - thigh) * _SKEL
	return out


func _arm_correction(sn: String) -> Basis:
	return Basis(Vector3.BACK, PI * 0.5) if sn == "L" else Basis(Vector3.BACK, -PI * 0.5)


## Swap the held blaster for a lit lightsaber, or back. Everything about a Force
## adept that other players can read is on this model — the exhaustion pool, the
## first-person guard pose and the swing are all private to the owner — and with
## a blaster in its hands the guard stance was a trooper standing oddly. A metre
## of glowing blade held across the chest is the tell.
## `staff` picks the electrostaff over the lightsaber; both are "melee" and both
## get the guard, so a Magna Guard reads as a staff-carrier from across the map
## while a Force adept reads as a blade-carrier.
##
## `look` is Weapon.melee_look() — the colour and size of THIS weapon's blade,
## read off the same profile keys the first-person viewmodel reads, so a
## chainsword is dull steel and a warscythe is green in both views without the
## two ever agreeing by hand. It only rebuilds when the look actually changes,
## which is a weapon swap and nothing else.
func set_melee(on: bool, staff := false, look := {}) -> void:
	if on and look != _melee_look:
		_melee_look = look.duplicate()
		_rebuild_melee()
	for mi in _gun_parts:
		mi.visible = not on
	for mi in _saber_parts:
		mi.visible = on and not staff
	for mi in _staff_parts:
		mi.visible = on and staff


## Put this model on a render layer, and keep it there through every rebuild.
func set_render_layers(bits: int) -> void:
	render_layers = bits
	_apply_layers()


func _apply_layers() -> void:
	if render_layers == 0:   # nobody asked; leave the engine default alone
		return
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = render_layers


## TWIST THE UPPER BODY relative to the legs, in radians.
##
## What it is for: a body that pans its aim while standing still turns its TORSO
## first and only moves its feet when it runs out of neck. Rotating the whole
## model with the camera — which is what a CharacterBody3D yawing under a look
## input does on its own — makes a character pirouette on the spot, and it is one
## of the loudest tells that something is a game object rather than a person.
##
## The caller (Player) owns the policy: how far the torso may go before the feet
## have to follow, and how fast they catch up. This just applies it.
func set_twist(radians: float) -> void:
	_twist = radians
	if _twist_joint != null and is_instance_valid(_twist_joint):
		_twist_joint.rotation.y = radians


## Rebuild just the held blade and pole for the melee weapon now in hand. The
## rest of the rig is untouched: these hang off the HeldGun joint, which survives
## a weapon swap, so this is four boxes rather than a whole model.
##
## remove_child before queue_free, the same rule the viewmodel keeps: freeing is
## deferred to the end of the frame, so a swap and a rebuild in one frame would
## otherwise leave the old blade stacked inside the new one.
func _rebuild_melee() -> void:
	if _held == null or not is_instance_valid(_held):
		return
	for mi in _saber_parts + _staff_parts:
		if is_instance_valid(mi):
			_held.remove_child(mi)
			mi.queue_free()
	_saber_parts.clear()
	_staff_parts.clear()
	var gunmetal := _mat(Color(0.10, 0.10, 0.12), Finish.METAL)
	_build_held_saber(_held, gunmetal)
	_build_held_staff(_held, gunmetal)
	_apply_layers()


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


# --- character styles ------------------------------------------------------
#
# Each unit is its OWN procedural model now, not one imported trooper tinted per
# team. A style is a colour scheme + a HEAD shape + a bulk multiplier + a set of
# accessories; the skeleton (joint layout, from the same offsets) and every
# animation are shared, so a new look costs a table row, not a rig. The class
# `armor`/`dark` colours are the BODY (so a clone is white plate, a droid bronze),
# and the TEAM colour rides the ACCENTS (`_suit_mat`: shoulder bells, chest vest,
# belt, knee pads, helmet crest) — the way real armour markings read, and still a
# clear team call at a glance.
## Styles from EVERY universe live in one enum, for the same reason Weapon.Class
## does: STYLES is a dictionary keyed by it, so a Spartan costs a row and shifts
## nothing, and which universe a body belongs to is stated once in Loadout (the
## kit that wears it) rather than repeated here.
enum Style {
	GENERIC, CLONE, CLONE_ENGINEER, CLONE_HEAVY, CLONE_ARC,
	B1, B2, MAGNAGUARD, TACTICAL, MANDALORIAN, JEDI, WOOKIEE, TRANDOSHAN,
	# Halo
	SPARTAN, ODST, MARINE, ELITE, GRUNT, BRUTE,
	# Warhammer 40,000
	ULTRAMARINE, BLOOD_ANGEL, NECRON, NECRON_LORD, ORK, ORK_NOB,
}

const STYLES := {
	Style.GENERIC:        {"armor": Color(0.70, 0.72, 0.76), "dark": Color(0.16, 0.17, 0.20), "head": "bare"},
	# Republic — white clone plate, team colour on the body suit, a helmet crest.
	Style.CLONE:          {"armor": Color(0.86, 0.87, 0.90), "dark": Color(0.15, 0.16, 0.19), "head": "helmet"},
	Style.CLONE_ENGINEER: {"armor": Color(0.86, 0.87, 0.90), "dark": Color(0.15, 0.16, 0.19), "head": "helmet", "acc": ["backpack"]},
	Style.CLONE_HEAVY:    {"armor": Color(0.88, 0.89, 0.92), "dark": Color(0.15, 0.16, 0.19), "head": "helmet", "bulk": 1.28, "acc": ["pauldron"]},
	Style.CLONE_ARC:      {"armor": Color(0.84, 0.85, 0.88), "dark": Color(0.14, 0.15, 0.18), "head": "helmet", "acc": ["antenna", "kama"]},
	# Separatist — thin bronze B1, hulking B2, cloaked MagnaGuard, slim tactical.
	Style.B1:             {"armor": Color(0.62, 0.50, 0.30), "dark": Color(0.30, 0.24, 0.14), "head": "b1", "bulk": 0.78},
	Style.B2:             {"armor": Color(0.34, 0.36, 0.42), "dark": Color(0.14, 0.15, 0.18), "head": "b2", "bulk": 1.40},
	Style.MAGNAGUARD:     {"armor": Color(0.30, 0.31, 0.34), "dark": Color(0.12, 0.13, 0.15), "head": "mask", "bulk": 0.96, "acc": ["cape"]},
	Style.TACTICAL:       {"armor": Color(0.40, 0.46, 0.54), "dark": Color(0.16, 0.18, 0.22), "head": "b1", "bulk": 0.86},
	# Base kits.
	Style.MANDALORIAN:    {"armor": Color(0.55, 0.57, 0.62), "dark": Color(0.16, 0.17, 0.20), "head": "visor", "acc": ["jetpack"]},
	Style.JEDI:           {"armor": Color(0.40, 0.31, 0.20), "dark": Color(0.22, 0.17, 0.11), "head": "hood", "acc": ["robe"]},
	Style.WOOKIEE:        {"armor": Color(0.34, 0.23, 0.13), "dark": Color(0.22, 0.15, 0.09), "head": "furry", "bulk": 1.45, "acc": ["fur", "bandolier"]},
	Style.TRANDOSHAN:     {"armor": Color(0.42, 0.47, 0.30), "dark": Color(0.24, 0.28, 0.18), "head": "bare", "bulk": 1.08, "acc": ["scales"]},
	# HALO — UNSC. A Spartan is a head taller than the marines it fights beside,
	# which is the only thing anyone needs to read at a glance; the ODST is the
	# same soldier in black with the pod-visor helmet. The Spartan carries plate
	# on every limb — without the greaves and gauntlets a slab of a chest sat on
	# bare pipe-cleaner legs and read top-heavy.
	Style.SPARTAN:        {"armor": Color(0.30, 0.40, 0.29), "dark": Color(0.11, 0.13, 0.12), "accent": Color(0.86, 0.66, 0.20), "head": "spartan", "bulk": 1.24, "acc": ["pauldron", "gauntlet", "greaves", "thighplate"]},
	Style.ODST:           {"armor": Color(0.17, 0.19, 0.22), "dark": Color(0.07, 0.08, 0.10), "accent": Color(0.45, 0.48, 0.54), "head": "odst", "bulk": 1.02, "acc": ["backpack", "gauntlet", "greaves"]},
	Style.MARINE:         {"armor": Color(0.36, 0.38, 0.28), "dark": Color(0.14, 0.15, 0.12), "accent": Color(0.52, 0.48, 0.34), "head": "odst", "bulk": 0.96, "acc": ["greaves"]},
	# HALO — Covenant. The Elite is tall and armoured over a dark bodysuit, the
	# Grunt is tiny behind a methane tank bigger than it is, the Brute is the
	# widest thing in the game and wears half a set of plate.
	Style.ELITE:          {"armor": Color(0.36, 0.31, 0.56), "dark": Color(0.13, 0.11, 0.19), "accent": Color(0.72, 0.66, 0.95), "head": "elite", "bulk": 1.22, "acc": ["bigpauldron", "gauntlet", "greaves"]},
	Style.GRUNT:          {"armor": Color(0.76, 0.44, 0.16), "dark": Color(0.22, 0.15, 0.09), "accent": Color(0.30, 0.34, 0.38), "head": "grunt", "bulk": 0.88, "acc": ["tank"]},
	Style.BRUTE:          {"armor": Color(0.46, 0.36, 0.28), "dark": Color(0.27, 0.21, 0.16), "accent": Color(0.58, 0.53, 0.47), "head": "brute", "bulk": 1.52, "acc": ["fur", "spikes", "shoulderplate", "greaves"]},
	# WARHAMMER — Astartes. Both chapters are the same power armour in different
	# heraldry, which is exactly how the setting works. The pack and the enormous
	# pauldrons ARE the silhouette: without them a marine is a coloured rectangle.
	Style.ULTRAMARINE:    {"armor": Color(0.13, 0.26, 0.60), "dark": Color(0.08, 0.09, 0.12), "accent": Color(0.80, 0.68, 0.26), "head": "astartes", "bulk": 1.38, "acc": ["bigpauldron", "powerpack", "aquila", "gauntlet", "greaves", "thighplate"]},
	Style.BLOOD_ANGEL:    {"armor": Color(0.62, 0.10, 0.10), "dark": Color(0.12, 0.07, 0.07), "accent": Color(0.85, 0.75, 0.32), "head": "astartes", "bulk": 1.38, "acc": ["bigpauldron", "jetpack", "aquila", "gauntlet", "greaves", "thighplate"]},
	# WARHAMMER — Necrons. Bare metal skeletons: no undersuit, no soft parts, an
	# exposed ribcage over a lit core, and the eyes are the only colour on them.
	Style.NECRON:         {"armor": Color(0.50, 0.52, 0.54), "dark": Color(0.13, 0.15, 0.15), "accent": Color(0.35, 1.0, 0.40), "head": "necron", "bulk": 0.86, "acc": ["ribs"]},
	Style.NECRON_LORD:    {"armor": Color(0.58, 0.55, 0.40), "dark": Color(0.12, 0.14, 0.14), "accent": Color(0.40, 1.0, 0.45), "head": "necron", "bulk": 1.12, "acc": ["ribs", "cape", "collar"]},
	# WARHAMMER — Orks. Green, wide, and wearing whatever they found, bolted on
	# crooked: the ASYMMETRY is the read.
	Style.ORK:            {"armor": Color(0.29, 0.47, 0.21), "dark": Color(0.22, 0.18, 0.12), "accent": Color(0.42, 0.36, 0.28), "head": "ork", "bulk": 1.34, "acc": ["spikes", "bandolier", "shoulderplate", "scrap"]},
	Style.ORK_NOB:        {"armor": Color(0.25, 0.43, 0.19), "dark": Color(0.19, 0.16, 0.11), "accent": Color(0.46, 0.40, 0.30), "head": "ork", "bulk": 1.62, "acc": ["spikes", "shoulderplate", "scrap", "gauntlet", "greaves"]},
}

var _style_id := Style.GENERIC
var _team_color := Color(0.72, 0.74, 0.78)
var _built := false


## Pick which unit this model looks like. Rebuilds the meshes in place — the
## AnimationPlayer and its joint-name tracks survive, so the animation never
## stops. Player/Bot call this from the loadout before the first frame.
func set_style(id: int) -> void:
	if id == _style_id and _built:
		return
	_style_id = id
	if _built:
		_build_body()


func _build_body() -> void:
	# Re-callable: free the old rig (the AnimationPlayer, a sibling, is untouched)
	# and forget the held-weapon part lists before rebuilding for the new style.
	if has_node("Hips"):
		get_node("Hips").free()
	_gun_parts.clear()
	_saber_parts.clear()
	_staff_parts.clear()
	var style: Dictionary = STYLES.get(_style_id, STYLES[Style.GENERIC])
	var bulk: float = style.get("bulk", 1.0)
	var acc: Array = style.get("acc", [])
	var at := _joint_offsets()   # our own skeleton math — the GLB is gone

	# TEAM colour rides the ACCENTS (shoulder bells, chest vest, belt, helmet crest)
	# rather than the whole body — so a clone reads as white plate with team markings
	# the way real armour does, and the accents still call the side at a glance.
	_suit_mat = _mat(_team_color, Finish.PLATE)
	var armor := _mat(style["armor"], Finish.PLATE)   # the class's main plate colour
	var dark := _mat(style["dark"], Finish.CLOTH)     # undersuit, joints, hands, boots
	# A THIRD colour, and the reason these units stopped reading as coloured
	# blocks. Two tones plus the team accent is enough for a trooper in one
	# palette, but a Spartan's gold visor, a Necron's green light and an ork's
	# bare scrap metal are none of those three — every one of them was being
	# painted in the body colour and vanishing into it. Defaults to `dark`, so a
	# style that has nothing to say says nothing.
	var accent := _mat(style.get("accent", style["dark"]),
		style.get("accent_finish", Finish.METAL))
	var furry: bool = acc.has("fur")

	var hips := _joint(self, "Hips", Vector3(0.0, HIP_Y, 0.0))
	_box(hips, Vector3(0.27 * bulk, 0.15, 0.19 * bulk), Vector3(0, 0.03, 0), armor)        # pelvis
	_box(hips, Vector3(0.29 * bulk, 0.055, 0.205 * bulk), Vector3(0, -0.035, 0), _suit_mat)  # team belt
	_box(hips, Vector3(0.055, 0.06, 0.03), Vector3(0, -0.035, -0.105 * bulk), dark)        # buckle (front)
	if acc.has("kama"):   # ARC skirt: plated flaps hanging front and back
		for kz in [0.11, -0.11]:
			_box(hips, Vector3(0.30, 0.26, 0.04), Vector3(0, -0.17, kz * bulk), armor)
	if acc.has("robe"):   # Jedi tabard hanging from the waist, at the front
		_box(hips, Vector3(0.24, 0.36, 0.05), Vector3(0, -0.20, -0.10), armor)

	# Torso pivots at the hips so run/idle can lean from the waist. The model faces
	# -Z, so front detail is at NEGATIVE z and anything worn on the back at positive.
	# The un-animated twist joint the upper body hangs off (see PATHS).
	var twist := _joint(hips, "Twist", Vector3.ZERO)
	_twist_joint = twist
	twist.rotation.y = _twist
	var spine := _joint(twist, "Spine", Vector3.ZERO)
	_box(spine, Vector3(0.30 * bulk, 0.36, 0.20 * bulk), Vector3(0, 0.24, 0), armor)       # torso
	if furry:
		_box(spine, Vector3(0.34 * bulk, 0.40, 0.24 * bulk), Vector3(0, 0.22, 0), dark)    # shaggy chest
	else:
		_box(spine, Vector3(0.28 * bulk, 0.26, 0.055), Vector3(0, 0.31, -0.105 * bulk), _suit_mat)  # team chest vest
		_box(spine, Vector3(0.29 * bulk, 0.05, 0.062), Vector3(0, 0.18, -0.105 * bulk), dark)       # ab seam
	_box(spine, Vector3(0.22 * bulk, 0.10, 0.19 * bulk), Vector3(0, 0.46, 0), armor)       # collar
	if acc.has("backpack"):                   # on the back (+z)
		_box(spine, Vector3(0.23, 0.28, 0.11), Vector3(0, 0.30, 0.15 * bulk), dark)
		_box(spine, Vector3(0.05, 0.14, 0.05), Vector3(0.09, 0.44, 0.14 * bulk), _suit_mat)  # antenna
	if acc.has("jetpack"):                     # on the back (+z)
		_box(spine, Vector3(0.21, 0.30, 0.10), Vector3(0, 0.32, 0.15 * bulk), armor)
		for jx in [-0.07, 0.07]:
			_box(spine, Vector3(0.05, 0.07, 0.05), Vector3(jx, 0.14, 0.18), dark)      # nozzles
	if acc.has("cape") or acc.has("robe"):    # cloth down the back (+z)
		_box(spine, Vector3(0.32, 0.66, 0.03), Vector3(0, 0.15, 0.13 * bulk), armor)
	if acc.has("bandolier"):                  # a team sash across a Wookiee's fur (front)
		_box(spine, Vector3(0.085, 0.56, 0.04), Vector3(0.0, 0.24, -0.13 * bulk), _suit_mat).rotation.z = 0.34
	if acc.has("antenna"):                    # ARC trooper's rangefinder stalk
		_box(spine, Vector3(0.018, 0.22, 0.018), Vector3(0.10, 0.52, 0.0), dark)
	if acc.has("powerpack"):
		# The Astartes power pack: the single most recognisable thing about the
		# silhouette after the pauldrons, and it was missing entirely. A slab on
		# the back with two exhaust stacks standing proud of the shoulders.
		_box(spine, Vector3(0.30 * bulk, 0.34, 0.14), Vector3(0, 0.30, 0.15 * bulk), dark)
		for sx in [-0.10, 0.10]:
			_box(spine, Vector3(0.06, 0.20, 0.06), Vector3(sx, 0.52, 0.15 * bulk), accent)
			_box(spine, Vector3(0.075, 0.04, 0.075), Vector3(sx, 0.63, 0.15 * bulk), dark)
	if acc.has("aquila"):
		# A raised plate across the chest. Not a literal eagle — at this
		# resolution what reads is the BREAK in a flat expanse of colour.
		# Narrow, and PROUD of the team vest rather than level with it — at the
		# same z the two were coplanar and the chest read as one flat inset panel.
		_box(spine, Vector3(0.15 * bulk, 0.055, 0.04), Vector3(0, 0.37, -0.128 * bulk), accent)
		_box(spine, Vector3(0.045, 0.20, 0.04), Vector3(0, 0.31, -0.128 * bulk), accent)
	if acc.has("tank"):
		# The Unggoy methane tank, which is most of a Grunt's silhouette: it is
		# bigger than the torso carrying it, and the hose to the mask is what
		# makes it read as breathing gear rather than as a rucksack.
		_box(spine, Vector3(0.26, 0.34, 0.20), Vector3(0, 0.26, 0.19 * bulk), accent)
		_box(spine, Vector3(0.05, 0.05, 0.05), Vector3(0.09, 0.44, 0.19 * bulk), dark)
		_box(spine, Vector3(0.035, 0.22, 0.035), Vector3(0.10, 0.50, 0.13 * bulk), dark)
	if acc.has("collar"):
		# A standing collar behind the skull: what a Necron lord has instead of
		# pauldrons, which on a skeleton read as borrowed power armour.
		_box(spine, Vector3(0.30 * bulk, 0.26, 0.04), Vector3(0, 0.50, 0.10 * bulk), armor)
		for cx in [-0.14, 0.14]:
			_box(spine, Vector3(0.04, 0.20, 0.10), Vector3(cx * bulk, 0.52, 0.06 * bulk), accent)
	if acc.has("ribs"):
		# A Necron has no flesh on it: the chest is an exposed cage over a lit
		# core. Three ribs and a spine, with the body colour showing between.
		for ry in [0.16, 0.26, 0.36]:
			_box(spine, Vector3(0.26 * bulk, 0.035, 0.21 * bulk), Vector3(0, ry, 0), armor)
		_box(spine, Vector3(0.05, 0.34, 0.05), Vector3(0, 0.26, 0.08 * bulk), armor)
		var core := _emit(Color(style.get("accent", Color(0.35, 1.0, 0.40))))
		_box(spine, Vector3(0.09, 0.09, 0.04), Vector3(0, 0.27, -0.105 * bulk), core)
	if acc.has("scrap"):
		# Ork armour is whatever was to hand, bolted on crooked. ASYMMETRY is the
		# whole point — a matched pair reads as issued kit, which orks do not have.
		_box(spine, Vector3(0.17, 0.22, 0.05), Vector3(-0.07, 0.30, -0.11 * bulk),
			accent).rotation.z = 0.16
		_box(spine, Vector3(0.22 * bulk, 0.09, 0.05), Vector3(0.03, 0.14, -0.11 * bulk), accent)

	var head := _joint(spine, "Head", at["head"])
	_build_head(style, head, armor, dark)

	for side in [-1, 1]:
		var sn := "L" if side < 0 else "R"
		var sh := _joint(spine, "Shoulder" + sn, at["s" + sn])
		_box(sh, Vector3(0.15 * bulk, 0.14 * bulk, 0.16 * bulk), Vector3(0, 0.02, 0), _suit_mat)  # team bell
		_limb(sh, at["e" + sn], 0.085 * bulk, 0.085 * bulk, armor)                      # upper arm
		if furry:
			_limb(sh, at["e" + sn] * 1.06, 0.13 * bulk, 0.13 * bulk, dark)              # shaggy over-layer
		if acc.has("pauldron"):                                                         # heavy's big plate
			_box(sh, Vector3(0.20, 0.14, 0.22), Vector3(-0.05 * side, 0.05, 0), _suit_mat)
		if acc.has("bigpauldron"):
			# The Astartes shoulder: enormous, standing well clear of the arm and
			# ABOVE the collar line. The generic pauldron above sits flush and
			# merges into the torso, which is why a marine read as a rectangle.
			_box(sh, Vector3(0.22, 0.17, 0.24), Vector3(0.042 * side, 0.075, 0), _suit_mat)
			# A TRIM, not a lid. At 0.05 deep the accent cap was half the pauldron
			# and the shoulder read as a gold-topped crate rather than as a rim.
			_box(sh, Vector3(0.235, 0.032, 0.255), Vector3(0.042 * side, 0.17, 0), accent)
		if acc.has("shoulderplate"):
			# One big plate, one bare shoulder: an ork or a brute wears half a set.
			if side > 0:
				_box(sh, Vector3(0.24, 0.17, 0.26), Vector3(0.05, 0.08, 0), accent)
				for gx in [-0.05, 0.05]:
					_box(sh, Vector3(0.028, 0.10, 0.028), Vector3(0.05 + gx, 0.17, 0), dark)
		if acc.has("spikes"):   # ork/brute shoulder spikes, angled out and back
			for k in 2:
				var spike := _box(sh, Vector3(0.035, 0.16, 0.035),
					Vector3(-0.04 * side, 0.09, -0.05 + 0.10 * k), dark)
				spike.rotation.z = 0.5 * side
		var el := _joint(sh, "Elbow" + sn, at["e" + sn])
		var handv: Vector3 = at["e" + sn].normalized() * LOWER_ARM
		if acc.has("gauntlet"):
			# Forearm armour, on the ELBOW joint so it swings with the forearm.
			_box(el, Vector3(0.13 * bulk, 0.16, 0.13 * bulk),
				handv.normalized() * 0.10, armor)
		_limb(el, handv, 0.072 * bulk, 0.072 * bulk, armor)                             # forearm
		_box(el, Vector3(0.085, 0.075, 0.05), (handv.normalized()) * 0.02, dark)        # wrist guard
		_box(el, Vector3(0.075, 0.075, 0.075), handv + handv.normalized() * 0.045, dark)  # hand

	# Third-person blaster, held two-handed in front. Other players see this; the
	# owner sees only the first-person viewmodel. Parented to the spine so it leans
	# with the torso and the CARRY arm pose keeps the hands on it.
	var gunmetal := _mat(Color(0.10, 0.10, 0.12), Finish.METAL)
	var held := _joint(spine, "HeldGun", GUN_POS)
	_held = held
	_gun_parts.append(_box(held, Vector3(0.05, 0.06, 0.24), Vector3(0, 0, 0.01), gunmetal))
	_gun_parts.append(_box(held, Vector3(0.028, 0.028, 0.30), Vector3(0, 0.012, -0.22), gunmetal))
	_gun_parts.append(_box(held, Vector3(0.035, 0.10, 0.05), Vector3(0, -0.06, 0.075), gunmetal))
	_build_held_saber(held, gunmetal)
	_build_held_staff(held, gunmetal)

	for side in [-1, 1]:
		var ln := "L" if side < 0 else "R"
		var hip := _joint(hips, "Hip" + ln, at["h" + ln])
		_limb(hip, at["k" + ln], 0.125 * bulk, 0.135 * bulk, armor)                     # thigh
		if furry:
			_limb(hip, at["k" + ln] * 1.04, 0.17 * bulk, 0.17 * bulk, dark)
		var knee := _joint(hip, "Knee" + ln, at["k" + ln])
		_box(knee, Vector3(0.13 * bulk, 0.09, 0.14 * bulk), Vector3(0, 0.0, -0.02), _suit_mat)  # team knee pad (front)
		if acc.has("thighplate"):
			_box(hip, Vector3(0.16 * bulk, 0.24, 0.06),
				at["k" + ln] * 0.42 + Vector3(0, 0, -0.08 * bulk), armor)
		var footv: Vector3 = at["k" + ln].normalized() * LOWER_LEG
		if acc.has("greaves"):
			# Shin plate on the front of the lower leg. Cheap, and it stops a
			# heavily armoured unit having bare pipe-cleaner legs under a slab
			# of a chest — which is what made the Spartan read top-heavy.
			_box(knee, Vector3(0.15 * bulk, 0.26, 0.06),
				footv * 0.45 + Vector3(0, 0, -0.07 * bulk), armor)
		_limb(knee, footv, 0.105 * bulk, 0.11 * bulk, armor)                            # shin
		_box(knee, Vector3(0.115 * bulk, 0.10, 0.24 * bulk), footv + Vector3(0, 0.0, -0.05), dark)  # boot
	_apply_layers()
	_built = true


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
	# The weapon's own colour and proportions, scaled from the FIRST-PERSON
	# numbers the profile states: this blade is judged from across the map and
	# the viewmodel's from 30 cm away, so they are the same weapon at two sizes
	# rather than two sets of numbers that can drift apart.
	var core_col: Color = _melee_look.get("blade_core", BLADE_CORE)
	var glow_col: Color = _melee_look.get("blade_glow", BLADE_GLOW)
	var energy: float = _melee_look.get("blade_energy", 5.0)
	var length := BLADE_LENGTH * float(_melee_look.get("blade_len", VM_BLADE_LEN)) / VM_BLADE_LEN
	var width := BLADE_WIDTH * float(_melee_look.get("blade_width", VM_BLADE_WIDTH)) / VM_BLADE_WIDTH
	var hilt := 0.24 * float(_melee_look.get("hilt_len", 0.24)) / 0.24

	_saber_parts.append(_box(held, Vector3(0.042, 0.042, hilt),
		Vector3(0, 0, 0.01), hilt_mat))
	var band := _mat(Color(0.42, 0.36, 0.20), Finish.METAL)
	band.metallic = 0.0
	_saber_parts.append(_box(held, Vector3(0.05, 0.05, 0.03),
		Vector3(0, 0, -hilt * 0.42), band))

	var core := _mat(core_col)
	core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if energy > 0.0:
		core.emission_enabled = true
		core.emission = core_col
		core.emission_energy_multiplier = energy
	var glow := _mat(Color(glow_col.r, glow_col.g, glow_col.b, 0.5))
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	# The aura stays lit even when the core does not — see the viewmodel's copy
	# of this rule: `blade_energy` 0 is a metal weapon with a power field on it.
	glow.emission_enabled = true
	glow.emission = glow_col
	glow.emission_energy_multiplier = 3.0 if energy > 0.0 else 1.6

	# Boxes rather than cylinders: at this size and this distance a square blade
	# is indistinguishable from a round one, and it is one less mesh type on a
	# model that already renders four times a frame.
	var at := Vector3(0, 0, -hilt * 0.5 - length * 0.5)
	_saber_parts.append(_box(held, Vector3(width, width, length), at, core))
	_saber_parts.append(_box(held,
		Vector3(width * 2.2, width * 2.2, length * 0.99), at, glow))

	for mi in _saber_parts:
		mi.visible = false   # a blaster until somebody says otherwise


## The third-person ELECTROSTAFF: a metal pole through the HeldGun joint with a
## glowing electro-tip at each end, on the same joint as the saber so the solved
## carry/guard hold is unchanged. Read from across the map like the blade, so it
## is unshaded for the same reason — a lit pole goes black on its shadow side and
## vanishes on the night maps.
func _build_held_staff(held: Node3D, pole_mat: Material) -> void:
	# The pole itself, longer than the blade and running both ways out of the grip.
	_staff_parts.append(_box(held, Vector3(0.035, 0.035, 1.7),
		Vector3(0, 0, -0.25), pole_mat))
	# Violet electro-charge by default, not the saber's blue — the IG-100 look —
	# but a pole weapon that states its own colour (a Necron warscythe's green)
	# gets that instead, from the same profile keys the viewmodel reads.
	var core_col: Color = _melee_look.get("blade_core", STAFF_CORE)
	var glow_col: Color = _melee_look.get("blade_glow", STAFF_GLOW)
	var core := _mat(core_col)
	core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.emission_enabled = true
	core.emission = core_col
	core.emission_energy_multiplier = 5.0
	var glow := _mat(Color(glow_col.r, glow_col.g, glow_col.b, 0.5))
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.emission_enabled = true
	glow.emission = glow_col
	glow.emission_energy_multiplier = 3.0
	# A charged tip at each end of the pole, each wrapped in its aura.
	for z in [-0.25 - 0.85, -0.25 + 0.85]:
		_staff_parts.append(_box(held, Vector3(0.06, 0.06, 0.22), Vector3(0, 0, z), core))
		_staff_parts.append(_box(held, Vector3(0.12, 0.12, 0.26), Vector3(0, 0, z), glow))
	for mi in _staff_parts:
		mi.visible = false


## A limb box spanning from a joint's origin to `to` (its child joint, in local
## space), so it always reaches exactly the next joint however the skeleton is
## proportioned. The box's long axis (local Y) is rotated onto the direction.
func _limb(parent: Node3D, to: Vector3, tx: float, tz: float, mat: Material) -> MeshInstance3D:
	var length := to.length()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(tx, length, tz)
	mi.mesh = bm
	mi.material_override = mat
	var dir := to.normalized()
	if not dir.is_equal_approx(Vector3.UP):
		mi.quaternion = Quaternion(Vector3.UP, dir)
	mi.position = to * 0.5
	parent.add_child(mi)
	return mi


## The per-unit head. The shape is the loudest part of the silhouette, so each
## archetype gets its own — a crested clone helmet, a B1's photoreceptor stalk, a
## B2's sunken block, the MagnaGuard's masked cowl, a Wookiee's muzzle, a hood.
func _build_head(style: Dictionary, joint: Node3D, armor: Material, dark: Material) -> void:
	# The model FACES -Z (the blaster points -Z), so all face detail sits at
	# NEGATIVE z (the front) and anything on the back at positive z.
	var kind: String = style.get("head", "bare")
	_box(joint, Vector3(0.085, 0.06, 0.085), Vector3(0, 0.02, 0), dark)   # neck
	match kind:
		"helmet", "visor":
			# Dome + a forward brow that overhangs a dark visor recess, plus side
			# "ear" caps and a team crest — reads as a trooper helmet, not a box.
			_box(joint, Vector3(0.18, 0.15, 0.185), Vector3(0, 0.17, 0), armor)          # dome
			_box(joint, Vector3(0.17, 0.07, 0.115), Vector3(0, 0.11, -0.055), armor)     # lower face/jaw
			_box(joint, Vector3(0.155, 0.055, 0.05), Vector3(0, 0.155, -0.10), dark)     # brow shadow
			for ex in [-0.093, 0.093]:
				_box(joint, Vector3(0.02, 0.10, 0.10), Vector3(ex, 0.15, 0.0), dark)     # ear caps
			if kind == "visor":
				_box(joint, Vector3(0.055, 0.13, 0.03), Vector3(0, 0.135, -0.115), dark) # T-visor stem
				_box(joint, Vector3(0.15, 0.05, 0.03), Vector3(0, 0.185, -0.115), dark)  # T-visor bar
			else:
				_box(joint, Vector3(0.13, 0.045, 0.03), Vector3(0, 0.14, -0.115), dark)  # visor slit
				_box(joint, Vector3(0.03, 0.055, 0.20), Vector3(0, 0.255, 0.01), _suit_mat)  # team crest fin
		"b1":
			# The B1's long, tapering skull on a thin neck, with two photoreceptors
			# and a slit mouth.
			_box(joint, Vector3(0.045, 0.11, 0.045), Vector3(0, 0.10, 0), dark)          # long neck
			_box(joint, Vector3(0.10, 0.20, 0.12), Vector3(0, 0.25, -0.01), armor)       # elongated head
			_box(joint, Vector3(0.115, 0.055, 0.03), Vector3(0, 0.24, -0.055), dark)     # brow
			_box(joint, Vector3(0.06, 0.02, 0.02), Vector3(0, 0.17, -0.06), dark)        # mouth slit
			var eye := _emit(Color(0.12, 0.12, 0.13))
			for ex in [-0.027, 0.027]:
				_box(joint, Vector3(0.022, 0.03, 0.02), Vector3(ex, 0.25, -0.065), eye)
		"b2":
			# The B2 has no neck: a low blocky head sunk between huge shoulders, one
			# glowing photoreceptor visor.
			_box(joint, Vector3(0.19, 0.14, 0.18), Vector3(0, 0.07, 0), armor)
			_box(joint, Vector3(0.13, 0.05, 0.03), Vector3(0, 0.09, -0.095), dark)       # visor recess
			var eye := _emit(Color(1.0, 0.35, 0.18))
			_box(joint, Vector3(0.11, 0.02, 0.02), Vector3(0, 0.09, -0.10), eye)
		"mask":
			# The MagnaGuard's cowled head: a tall block with a raised centre mask
			# ridge, side cheek plates and a photoreceptor slit.
			_box(joint, Vector3(0.14, 0.23, 0.15), Vector3(0, 0.15, 0), armor)
			_box(joint, Vector3(0.055, 0.25, 0.06), Vector3(0, 0.16, -0.06), dark)       # mask ridge
			for ex in [-0.055, 0.055]:
				_box(joint, Vector3(0.03, 0.20, 0.08), Vector3(ex, 0.15, -0.04), dark)   # cheek plates
			var eye := _emit(Color(1.0, 0.55, 0.15))
			_box(joint, Vector3(0.03, 0.035, 0.02), Vector3(0, 0.21, -0.085), eye)
		"furry":
			var fur := _mat(Color(style["dark"]), Finish.HIDE)
			_box(joint, Vector3(0.23, 0.22, 0.22), Vector3(0, 0.16, 0), fur)             # big shaggy head
			_box(joint, Vector3(0.25, 0.09, 0.20), Vector3(0, 0.245, 0.01), fur)         # brow tuft
			_box(joint, Vector3(0.13, 0.11, 0.11), Vector3(0, 0.12, -0.135), armor)      # muzzle
			_box(joint, Vector3(0.05, 0.03, 0.03), Vector3(0, 0.10, -0.19), dark)        # nose
			var eye := _emit(Color(0.85, 0.7, 0.35))
			for ex in [-0.055, 0.055]:
				_box(joint, Vector3(0.028, 0.028, 0.02), Vector3(ex, 0.185, -0.115), eye)
		"spartan":
			# MJOLNIR: a smooth dome with no ear caps and one big GOLD faceplate,
			# which is the entire silhouette people know it by.
			_box(joint, Vector3(0.19, 0.16, 0.19), Vector3(0, 0.17, 0), armor)
			_box(joint, Vector3(0.16, 0.10, 0.05), Vector3(0, 0.155, -0.095), dark)     # visor recess
			var gold := _emit(Color(0.95, 0.72, 0.20))
			_box(joint, Vector3(0.145, 0.075, 0.03), Vector3(0, 0.155, -0.105), gold)   # faceplate
			_box(joint, Vector3(0.055, 0.04, 0.10), Vector3(0, 0.255, -0.03), _suit_mat)  # team crest
		"odst":
			# The ODST/marine helmet: a rounded shell with a wide black visor band
			# and a comms pod on the left side.
			_box(joint, Vector3(0.185, 0.145, 0.19), Vector3(0, 0.165, 0), armor)
			_box(joint, Vector3(0.155, 0.065, 0.045), Vector3(0, 0.155, -0.10), dark)   # visor band
			_box(joint, Vector3(0.05, 0.05, 0.06), Vector3(-0.10, 0.145, -0.02), dark)  # comms pod
			_box(joint, Vector3(0.06, 0.035, 0.14), Vector3(0.06, 0.245, 0.0), _suit_mat)  # team stripe
		"elite":
			# Sangheili: a long crested crown over a SPLIT jaw. The four mandibles
			# are the whole reason an Elite is recognisable from behind cover.
			_box(joint, Vector3(0.15, 0.17, 0.20), Vector3(0, 0.18, 0.01), armor)       # crown
			_box(joint, Vector3(0.075, 0.06, 0.22), Vector3(0, 0.27, 0.02), armor)      # swept crest
			var jaw := _mat(Color(style["dark"]), Finish.HIDE)
			for mx in [-0.048, 0.048]:
				for my in [0.075, 0.125]:
					_box(joint, Vector3(0.034, 0.042, 0.13),
						Vector3(mx, my, -0.10), jaw)                                    # mandibles
			var eeye := _emit(Color(1.0, 0.62, 0.15))
			for ex in [-0.05, 0.05]:
				_box(joint, Vector3(0.03, 0.022, 0.02), Vector3(ex, 0.19, -0.095), eeye)
		"grunt":
			# Unggoy: a small head almost entirely covered by a methane rebreather,
			# with the hose running back to the tank on its pack.
			_box(joint, Vector3(0.15, 0.13, 0.15), Vector3(0, 0.13, 0), armor)
			_box(joint, Vector3(0.12, 0.09, 0.06), Vector3(0, 0.115, -0.085), dark)     # mask cup
			_box(joint, Vector3(0.035, 0.035, 0.16), Vector3(0.055, 0.145, 0.06), dark) # hose
			var geye := _emit(Color(0.35, 0.85, 0.95))
			for ex in [-0.038, 0.038]:
				_box(joint, Vector3(0.026, 0.02, 0.02), Vector3(ex, 0.165, -0.075), geye)
		"brute":
			# Jiralhanae: a heavy brow over a jutting muzzle, a bone crest along the
			# top, and tusks. Read as an ape in armour rather than a helmeted man.
			var pelt := _mat(Color(style["dark"]), Finish.HIDE)
			_box(joint, Vector3(0.22, 0.20, 0.21), Vector3(0, 0.16, 0), pelt)
			_box(joint, Vector3(0.24, 0.06, 0.16), Vector3(0, 0.235, -0.01), armor)     # brow ridge
			_box(joint, Vector3(0.06, 0.08, 0.18), Vector3(0, 0.28, 0.01), armor)       # crest
			_box(joint, Vector3(0.14, 0.10, 0.10), Vector3(0, 0.11, -0.13), pelt)       # muzzle
			for tx in [-0.045, 0.045]:
				_box(joint, Vector3(0.022, 0.055, 0.022), Vector3(tx, 0.115, -0.175), _bone())  # tusks
			var beye := _emit(Color(0.85, 0.25, 0.12))
			for ex in [-0.055, 0.055]:
				_box(joint, Vector3(0.026, 0.022, 0.02), Vector3(ex, 0.20, -0.105), beye)
		"astartes":
			# A Mk VII helm: domed skull, a RESPIRATOR GRILLE jutting out where a
			# face would be, and two lenses. The snout is the tell — without it a
			# power-armoured marine reads as a very large clone trooper.
			_box(joint, Vector3(0.20, 0.16, 0.20), Vector3(0, 0.175, 0), armor)         # skull
			_box(joint, Vector3(0.09, 0.09, 0.10), Vector3(0, 0.125, -0.125), armor)    # snout
			_box(joint, Vector3(0.075, 0.055, 0.03), Vector3(0, 0.125, -0.175), dark)   # grille
			_box(joint, Vector3(0.21, 0.045, 0.06), Vector3(0, 0.235, -0.075), armor)   # brow rim
			var aeye := _emit(Color(0.85, 0.20, 0.12))
			for ex in [-0.062, 0.062]:
				_box(joint, Vector3(0.042, 0.03, 0.025), Vector3(ex, 0.175, -0.10), aeye)
			_box(joint, Vector3(0.03, 0.06, 0.20), Vector3(0, 0.265, 0.0), _suit_mat)   # team crest
		"necron":
			# A metal SKULL: narrow, hollow-cheeked, with an exposed grin and two
			# green points where the eyes were. No helmet, because there is nothing
			# in there to protect.
			_box(joint, Vector3(0.055, 0.10, 0.055), Vector3(0, 0.09, 0), dark)         # spine neck
			_box(joint, Vector3(0.135, 0.15, 0.16), Vector3(0, 0.21, -0.01), armor)     # cranium
			_box(joint, Vector3(0.11, 0.05, 0.09), Vector3(0, 0.135, -0.03), armor)     # jaw
			for gx in [-0.03, 0.0, 0.03]:
				_box(joint, Vector3(0.014, 0.045, 0.02), Vector3(gx, 0.145, -0.075), dark)  # teeth
			var neye := _emit(Color(0.35, 1.0, 0.40))
			for ex in [-0.038, 0.038]:
				# z clear of the cranium's front face (-0.09), or the only colour
				# on an all-grey skeleton is buried inside its own skull.
				_box(joint, Vector3(0.03, 0.03, 0.025), Vector3(ex, 0.225, -0.10), neye)
		"ork":
			# All jaw. The head is small, the lower jaw is enormous, and two tusks
			# come up past the nose — an ork is a mouth with a body attached.
			_box(joint, Vector3(0.19, 0.13, 0.18), Vector3(0, 0.19, 0.01), armor)       # skull
			_box(joint, Vector3(0.22, 0.05, 0.14), Vector3(0, 0.22, -0.055), armor)     # heavy brow
			_box(joint, Vector3(0.21, 0.10, 0.16), Vector3(0, 0.115, -0.03), armor)     # jaw
			for tx in [-0.07, 0.07]:
				_box(joint, Vector3(0.028, 0.075, 0.028), Vector3(tx, 0.155, -0.095), _bone())  # tusks
			var oeye := _emit(Color(0.95, 0.30, 0.20))
			for ex in [-0.05, 0.05]:
				_box(joint, Vector3(0.024, 0.018, 0.02), Vector3(ex, 0.195, -0.085), oeye)
		"hood":
			_box(joint, Vector3(0.15, 0.17, 0.16), Vector3(0, 0.14, -0.01), _mat(Color(0.58, 0.5, 0.4), Finish.HIDE))  # face
			_box(joint, Vector3(0.24, 0.24, 0.22), Vector3(0, 0.18, 0.04), armor)        # hood shell (behind)
			_box(joint, Vector3(0.20, 0.09, 0.10), Vector3(0, 0.10, -0.09), armor)       # hood brim over the face
		_:
			# A bare head with a simple face band (Trandoshan and the generic trooper).
			_box(joint, Vector3(0.17, 0.19, 0.18), Vector3(0, 0.14, 0), armor)
			_box(joint, Vector3(0.16, 0.04, 0.03), Vector3(0, 0.145, -0.09), dark)       # eye band
			if style.get("acc", []).has("scales"):
				var eye := _emit(Color(0.9, 0.75, 0.2))
				for ex in [-0.045, 0.045]:
					_box(joint, Vector3(0.025, 0.02, 0.02), Vector3(ex, 0.15, -0.095), eye)


## Ivory, for tusks and teeth — the one colour that has to stay off a style's
## palette, since a green tusk on a green ork disappears.
func _bone() -> StandardMaterial3D:
	return _mat(Color(0.86, 0.83, 0.72), Finish.HIDE)


## An unshaded emissive material for photoreceptor eyes and lenses.
func _emit(color: Color) -> StandardMaterial3D:
	var m := _mat(color)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.r + color.g + color.b > 0.8:   # only the bright ones actually glow
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 2.5
	return m


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
	var at := _joint_offsets()
	var right := _arm_ik(rear - at["sR"], at["eR"], reach)
	var left := _arm_ik(fore - at["sL"], at["eL"], reach)
	return {
		"sR": right[0], "eR": Vector3(right[1], 0.0, 0.0),
		"sL": left[0], "eL": Vector3(left[1], 0.0, 0.0),
	}


## Callers all mutate the dictionary they get back (that is how a pose is built
## up), so this hands out a COPY. Returning the cache itself let _crouch_base
## write its shoulder angles straight into it and permanently clobber the solved
## hold for every clip built afterwards.
## The carry carries the WEAPON's transform too, not just the arms. Every clip is
## built from this and `_clip` keys the gun joint from the pose, so a pose that
## did not name the gun would key it back to the origin with no rotation — which
## is what put the weapon back in the middle of the chest on every frame of every
## clip the moment the carry stopped being centred.
func _carry() -> Dictionary:
	if _carry_pose.is_empty():
		_carry_pose = _hold(GUN_POS, GUN_ROT)
		_carry_pose["gun"] = GUN_ROT
		_carry_pose["gun_pos"] = GUN_POS
	return _carry_pose.duplicate()


## Two-bone IK for one arm. `target` is where the hand must land, in SHOULDER
## space; `elbow` is that shoulder's ELBOW OFFSET (which carries both the upper
## arm's length and the direction the arm rests along) and `b` is how far past
## the elbow the hand closes. Returns [shoulder euler, elbow flex].
##
## Solved in the order the rig applies it: pick the elbow flex first (that alone
## fixes how far the hand reaches), which puts the hand at a known spot `h` with
## the arm still in its rest plane, then rotate the shoulder by the minimal
## rotation that carries `h` onto the target.
##
## It reads the rest direction out of `elbow` rather than assuming the arm hangs
## down -Y, because on this rig it does NOT: the skeleton is the trooper's, whose
## elbow offset is tilted ~13 degrees back off vertical, and the forearm and hand
## are built along that same direction. Assuming -Y solved a DIFFERENT arm from
## the one the model is made of and left every hand 8-14 cm off its grip — the
## shoulders visibly rotated wrong on every character holding a gun.
func _arm_ik(target: Vector3, elbow: Vector3, b: float) -> Array:
	var a := elbow.length()
	var rest := elbow / a          # the straight arm's direction, in shoulder space
	if target.length_squared() < 0.000001:
		return [Vector3.ZERO, 0.0]
	# Law of cosines, taken about the rest direction instead of about -Y. The
	# elbow bends about +X, so only the part of the arm PERPENDICULAR to X swings:
	# |h|^2 = a^2 + b^2 + 2ab(rest.x^2 + (1 - rest.x^2) cos flex).
	var fixed := rest.x * rest.x   # the share of the arm the elbow cannot swing
	var span := target.length()
	var reachable := (span * span - a * a - b * b) / (2.0 * a * b)
	# A target further than the arm can stretch (or nearer than it can fold) has
	# no solution; clamping leaves the arm reaching as far as it can toward it.
	var cos_flex := clampf((reachable - fixed) / maxf(1.0 - fixed, 0.001), -1.0, 1.0)
	var flex := acos(cos_flex)     # 0 = straight; bends FORWARD, about +X
	# Where the hand sits with only the elbow bent, arm still in its rest plane.
	var h := elbow + Basis(Vector3.RIGHT, flex) * (rest * b)
	var swing := Quaternion(h.normalized(), target.normalized())
	return [swing.get_euler(), flex]


func _idle_pose(_time: float) -> Dictionary:
	return _stance(_carry())  # near-static; hands on the gun, feet apart


## Open the legs into a standing stance. Returns the same dictionary it was
## given, so it can be dropped into any pose that is not walking.
func _stance(p: Dictionary) -> Dictionary:
	var splay := deg_to_rad(STANCE_SPLAY_DEG)
	var toe := deg_to_rad(STANCE_TOE_OUT_DEG)
	# +Z roll opens the LEFT leg outward and -Z the right: the two hips sit on
	# opposite sides of the X axis, so the same sign closes one and opens the
	# other.
	p["hL"] = p.get("hL", Vector3.ZERO) + Vector3(0.0, -toe, splay)
	p["hR"] = p.get("hR", Vector3.ZERO) + Vector3(0.0, toe, -splay)
	return p


func _idle_bob(time: float) -> Vector3:
	# The stance drop rides the bob track, the same way the crouch's does.
	return Vector3(0, STANCE_HIP_DROP + 0.012 * sin(time / IDLE_LEN * TAU), 0)


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
	# A SPRINT CARRY, not the ready carry with the legs going faster. Nobody runs
	# with a rifle levelled: the weapon comes down and across the chest, muzzle
	# swung inboard, so it is out of the way of the arms and of everything you are
	# running past. It is also the clearest read a player gets at a distance that
	# somebody is CLOSING rather than holding — which matters here, because a bot
	# that has broken cover to advance now looks different from one that is posted.
	#
	# Solved onto the weapon like every other hold (see _hold): move the gun and
	# both hands follow it, so this is four numbers rather than four arm angles.
	var p := _hold(RUN_GUN_POS, RUN_GUN_ROT)
	p["gun"] = RUN_GUN_ROT
	p["gun_pos"] = RUN_GUN_POS
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


## Write a pose (the same {joint: euler} dictionaries the clips are built from)
## straight onto the joints. For a model with no AnimationPlayer to do it — a
## corpse — since nothing would otherwise ever set these.
func apply_pose(pose: Dictionary, hips_drop := 0.0) -> void:
	for key in PATHS:
		var joint := get_node_or_null(NodePath(PATHS[key])) as Node3D
		if joint == null:
			continue
		joint.rotation = pose.get(key, Vector3.ZERO)
	var hips := get_node_or_null("Hips") as Node3D
	if hips != null:
		hips.position = Vector3(0.0, HIP_Y + hips_drop, 0.0)
	var gun := get_node_or_null(NodePath(PATHS["gun"])) as Node3D
	if gun != null:
		gun.position = pose.get("gun_pos", GUN_POS)


func _jump_pose(_time: float) -> Dictionary:
	# One simple held tuck (both keys identical): lead knee up, trail leg back,
	# hands stay on the gun. player.gd holds the last frame while airborne.
	var p := _carry()
	p["hL"] = Vector3(deg_to_rad(35), 0, 0)
	p["hR"] = Vector3(-deg_to_rad(18), 0, 0)
	p["kL"] = Vector3(-deg_to_rad(55), 0, 0)
	p["kR"] = Vector3(-deg_to_rad(12), 0, 0)
	return p
