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

# The third-person arc blade. Longer than the first-person blade (0.78 m): that
# one is foreshortened by a camera 30 cm from the hilt, while this one is judged
# from across the map, where the blade IS the silhouette.
const BLADE_LENGTH := 1.25
const BLADE_WIDTH := 0.05
## What viewmodel.gd draws for the ARC BLADE, in its own first-person scale.
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
# --- THE SLIDE ---------------------------------------------------------------
#
# A SLIDE IS ASYMMETRIC AND THAT IS THE WHOLE READ. A crouch is two legs folded
# the same way, which from any angle is a person squatting; what says "sliding"
# is one leg thrown out in front and the other folded underneath, with the torso
# back over the trailing hip. Get that pair of angles right and it is unmistakable
# in a silhouette; get them symmetric and it is a crouch moving quickly, which is
# exactly what the mechanic looked like before this clip existed.
#
# THE TRAILING LEG IS THE ONE THAT CARRIES THE BODY, so it is the one the hip
# drop is solved against — and it keeps the crouch's own knee = 2 x hip
# constraint, which is what puts the ankle under the hip rather than out in front
# of it. Deeper than a crouch, because a slide is lower than a squat.
#
# THE ANGLE ITSELF WAS SOLVED BY MEASUREMENT, and that is worth stating because
# the closed form looks like it should have given it. `CROUCH_HIP_DROP`'s
# derivation is exact only where thigh and shin are equal, and on this rig they
# are not — so it lands at exactly 0.00 mm for the crouch's 55 degrees (which is
# what it was calibrated against) and drifts about 2.7 mm of foot per degree
# beyond that. At 74 degrees the trailing boot was 14.7 mm under the floor.
# `tests/guard_pose.tscn` is what says so, and 68.5 is where it reads 0.00 —
# still comfortably deeper than the crouch, which is all the pose needs.
const SLIDE_TRAIL_HIP_DEG := 68.5
const SLIDE_TRAIL_KNEE_DEG := SLIDE_TRAIL_HIP_DEG * 2.0
# ...and the lead leg is thrown forward, nearly straight, heel first — a bent
# lead leg reads as a stumble.
#
# IT HAS TO BE NEARLY HORIZONTAL, AND THAT IS ARITHMETIC RATHER THAN TASTE. The
# hips are down at `LEG * cos(SLIDE_TRAIL_HIP_DEG)` above the ground, which at 74
# degrees is barely a quarter of a leg. A straight leg reaches almost a whole one
# — so at the 34 degrees this was first written with, the lead foot finished
# **368 mm through the floor** (`tests/guard_pose.tscn` measures exactly this).
# For the foot to clear the ground the leg's VERTICAL reach must be less than the
# hip height, and for a straight leg that means `cos(lead) < cos(trail)` — the
# lead hip has to open FURTHER than the trailing one, not less. Which is also
# what a slide looks like: the front leg is stretched out along the ground.
const SLIDE_LEAD_HIP_DEG := 86.0
const SLIDE_LEAD_KNEE_DEG := 10.0
# The torso goes BACK, not forward. A crouch leans out over its knees because it
# is about to move; a slide is already moving and the weight is behind the lead
# foot. This is the single angle that most decides whether it reads.
const SLIDE_LEAN_DEG := 16.0
const SLIDE_HEAD_DEG := 12.0    # ...and the head brought back up to face front
# Solved off the TRAILING leg for the reason recorded on CROUCH_HIP_DROP: it is a
# fraction of LEG and never of HIP_Y, or the boots go through the floor.
const SLIDE_HIP_DROP := LEG * (cos(deg_to_rad(SLIDE_TRAIL_HIP_DEG)) - 1.0)
const SLIDE_LEN := 0.5

const CROUCH_SWING_DEG := 26.0  # hip swing either side of the fold, when shuffling
const CROUCH_LIFT_DEG := 20.0   # extra knee tuck on the leg swinging through

# The saber guard, seen from outside: a bladed stance with the weapon brought up
# across the body. This is the only tell an opponent gets that a Kinesis adept has
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
##
## THE WRISTS AND ANKLES ARE JOINTS, AND THAT IS THE FIX FOR "CHUNKY". A limb
## that bends in exactly one place reads as a mannequin however good the mesh on
## it is, and the two worst offenders were the two ends: the boot rotated rigidly
## with the shin, so every stride pointed the foot like a ballet dancer's and a
## deep crouch stood the model on its toes; and the hand was a fixed block on the
## end of the forearm, so bending the elbow rolled the grip off the weapon.
##
## They cost NOTHING to add and that is why they are here rather than in a
## rewrite: both sit at exactly the position the boot and hand boxes already
## occupied, so no geometry moved, and a pose that does not name them leaves them
## at rest (`_clip` defaults every joint to zero). Every existing clip kept
## working the moment they were added, and each one opted in on its own terms.
const PATHS := {
	"spine": "Hips/Twist/Spine",
	"head": "Hips/Twist/Spine/Head",
	"sL": "Hips/Twist/Spine/ShoulderL", "eL": "Hips/Twist/Spine/ShoulderL/ElbowL",
	"wL": "Hips/Twist/Spine/ShoulderL/ElbowL/HandL",
	"sR": "Hips/Twist/Spine/ShoulderR", "eR": "Hips/Twist/Spine/ShoulderR/ElbowR",
	"wR": "Hips/Twist/Spine/ShoulderR/ElbowR/HandR",
	"hL": "Hips/HipL", "kL": "Hips/HipL/KneeL", "aL": "Hips/HipL/KneeL/AnkleL",
	"hR": "Hips/HipR", "kR": "Hips/HipR/KneeR", "aR": "Hips/HipR/KneeR/AnkleR",
	"gun": "Hips/Twist/Spine/HeldGun",
}

## HOW MUCH OF THE LEG'S ROTATION THE ANKLE TAKES BACK. 1.0 is a foot held
## perfectly flat, which is right for a squat and robotic for a stride — a real
## foot is flat through stance and rolls off at the end of it. So the levelling
## is partial while walking and total while crouched, and the toe-off below is
## what puts the roll back.
const ANKLE_LEVEL_WALK := 0.85
const ANKLE_LEVEL_FOLD := 1.0    # crouch and guard: you are stood on flat feet
const ANKLE_LEVEL_AIR := 0.45    # airborne, the foot relaxes rather than levels
const ANKLE_TOE_OFF_DEG := 16.0  # the push at the end of a stride

## HOW MUCH OF THE ELBOW'S BEND THE WRIST TAKES BACK. Derived from the solve
## rather than dialled in, which is the same rule the carry pose follows: the
## hand keeps a consistent angle to the WEAPON instead of to the forearm, so
## bending the elbow no longer rolls the grip out of it.
const WRIST_FOLLOW := 0.35


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
enum Finish { PLATE, CLOTH, METAL, HIDE }
## A BODY IS SOLID, AND EVERY FINISH IS A DIELECTRIC. `metallic` is 0.0 on all
## four, and — like the weapons, which reached the same place first — it is a
## switch to leave off rather than a value to tune.
##
## What metallic does is take the albedo OUT of the diffuse and put that energy
## into the reflection. Under GL Compatibility there is no SSR and no reflection
## probe, so the only thing there is to reflect is the SKY: a metallic plate
## stops being its own colour and becomes a picture of the sky gradient wrapped
## round a body, which is what "the characters look see-through" was. It was
## 0.75, then 0.45, and both were the same bug at different strengths.
##
## THE FOUR FINISHES STILL READ APART, because none of what separated them was
## the metallic value: `roughness` decides how tight the highlight is (ceramic
## plate holds a hot one, cloth swallows it), `specular` decides how strong,
## and the albedo does the rest. A dielectric shines — every map has direct
## lights and that is where the shine comes from.
##
## `rim` is a fresnel term that brightens a surface as it turns AWAY from the
## camera. It went in as a stand-in for a chamfer the Raspberry Pi budget would
## not pay for; the parts are genuinely chamfered now, so it is the same edge
## paid for twice, and a bright fresnel running all the way round a part is
## itself a translucency cue — it is what a glass edge does. Kept only as a
## whisper, to stop a face turning away from going flat.
const FINISHES := {
	# Armour plate: hard, a tight bright highlight.
	Finish.PLATE: {"metallic": 0.0, "roughness": 0.42, "specular": 0.55, "rim": 0.08},
	# Undersuit, webbing, boot rubber: matte and light-swallowing.
	Finish.CLOTH: {"metallic": 0.0, "roughness": 0.92, "specular": 0.25, "rim": 0.05},
	# Gun bodies, staff poles, exposed frame: the sharpest highlight of the four,
	# which is what now says "metal" — brushed steel, not a mirror.
	Finish.METAL: {"metallic": 0.0, "roughness": 0.28, "specular": 0.70, "rim": 0.10},
	# Fur, skin, bone: matte, with a little more grazing lift than cloth.
	Finish.HIDE: {"metallic": 0.0, "roughness": 0.85, "specular": 0.30, "rim": 0.14},
}


## A value/saturation shift of one colour, for building tonal variants of a plate
## without inventing a second colour. `value` scales brightness, `sat` scales
## saturation — a highlight is not just a brighter red, it is a paler one, and a
## shadow is a deeper and MORE saturated one. Doing it in HSV rather than by
## multiplying the RGB is what keeps that true.
func _shade(c: Color, value: float, sat: float) -> Color:
	return Color.from_hsv(c.h, clampf(c.s * sat, 0.0, 1.0),
		clampf(c.v * value, 0.0, 1.0), c.a)
func _mat(color: Color, finish := Finish.PLATE) -> StandardMaterial3D:
	var f: Dictionary = FINISHES[finish]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = f["metallic"]
	m.metallic_specular = f["specular"]   # dielectric shine: the finish's whole job
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


## Every body part goes through here, so this is the one place that decides what
## a "box" on this rig actually is: a CHAMFERED box (`Meshes.chamfer_box`), whose
## bevelled edges catch a highlight along the silhouette. A true box shades each
## face at one flat value and reads as cardboard however good the material is.
## The meshes are cached and shared by size, so the two arms, two legs and every
## paired plate on all twelve bodies on a map hold the same handful of resources.
## A SMALL PART IS NOT WORTH DRAWING FROM ACROSS THE MAP, and most of a body is
## small parts: a knee pad, a belt pouch, a photoreceptor, a shoulder trim. A
## unit is thirty-odd meshes and the game draws every one of them FOUR TIMES plus
## a shadow pass, so on a 220 m map with two dozen bodies the accessories are the
## single biggest thing on screen by draw count — and past about forty metres
## they are a couple of pixels each.
##
## `visibility_range_end` is the engine doing this for free and PER CAMERA, which
## is what makes it right for split screen: the same body can be detailed in the
## viewport of the player standing next to it and culled in the other three. It
## costs no script time at all — there is nothing per frame to run.
##
## Deliberately generous distances. This is a draw-call saving, not a fidelity
## dial: at these ranges a part is under a pixel or two, and the silhouette (the
## thing that says which unit you are looking at) is carried by the limbs and the
## head, which are never culled.
const DETAIL_SMALL := 0.085   # m: trim, studs, lenses, pouches
const DETAIL_SMALL_RANGE := 45.0
const DETAIL_MEDIUM := 0.16    # m: pads, plates, packs
const DETAIL_MEDIUM_RANGE := 90.0


## CROWD MODE. A body fielded as one of a hundred (`Bot.line`) is drawn under a
## harsher rule than one of eight, because at that count the bodies ARE the
## frame: it casts no shadow and everything on it culls at a fraction of the
## usual distance.
##
## Set before `set_style`, since it is applied as the meshes are built.
##
## Losing the shadow is the bigger half and the one worth arguing for: a hundred
## shadow casters is a hundred extra draws in the directional pass, and a single
## trooper's shadow in a crowd of a hundred is not information anybody is using —
## whereas the shadow under the PLAYER, and under the handful of veterans, still
## tells you where a body is standing. So the two kinds are drawn differently on
## purpose, and it is invisible in practice.
var crowd := false
const CROWD_RANGE_MULT := 0.45
const CROWD_BODY_RANGE := 130.0   # metres: past this the whole body goes


func _box(parent: Node3D, size: Vector3, center: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.chamfer_box(size)
	mi.position = center
	mi.material_override = mat
	var biggest: float = maxf(size.x, maxf(size.y, size.z))
	var mult := CROWD_RANGE_MULT if crowd else 1.0
	if biggest <= DETAIL_SMALL:
		mi.visibility_range_end = DETAIL_SMALL_RANGE * mult
	elif biggest <= DETAIL_MEDIUM:
		mi.visibility_range_end = DETAIL_MEDIUM_RANGE * mult
	elif crowd:
		mi.visibility_range_end = CROWD_BODY_RANGE
	if crowd:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _bar(parent: Node3D, a: Vector3, b: Vector3, thickness: float,
		mat: Material) -> MeshInstance3D:
	var span := b - a
	var length := span.length()
	if length <= 0.0001:
		return _box(parent, Vector3.ONE * thickness, a, mat)
	var mi := _box(parent, Vector3(thickness, length, thickness), (a + b) * 0.5, mat)
	mi.quaternion = Quaternion(Vector3.UP, span / length)
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
		# The wrist and the ankle, both exactly where the hand and boot boxes were
		# already being drawn — which is the whole reason adding these two joints
		# moved no geometry. They run along their parent bone's own direction, the
		# same way `_limb` spans one, so they stay correct on any proportions.
		out["w" + sn] = out["e" + sn].normalized() * LOWER_ARM
		out["a" + sn] = out["k" + sn].normalized() * LOWER_LEG
	return out


func _arm_correction(sn: String) -> Basis:
	return Basis(Vector3.BACK, PI * 0.5) if sn == "L" else Basis(Vector3.BACK, -PI * 0.5)


## Swap the held blaster for a lit arc blade, or back. Everything about a Force
## adept that other players can read is on this model — the exhaustion pool, the
## first-person guard pose and the swing are all private to the owner — and with
## a blaster in its hands the guard stance was a trooper standing oddly. A metre
## of glowing blade held across the chest is the tell.
## `staff` picks the electrostaff over the arc blade; both are "melee" and both
## get the guard, so a Magna Guard reads as a staff-carrier from across the map
## while a Kinesis adept reads as a blade-carrier.
##
## `look` is Weapon.melee_look() — the colour and size of THIS weapon's blade,
## read off the same profile keys the first-person viewmodel reads, so a
## chain blade is dull steel and a warscythe is green in both views without the
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


## LEAN THE UPPER BODY, in radians — forward/back and side to side.
##
## On the SAME joint as the twist, and for the same reason: `Twist` is the one
## joint in this rig that no clip ever names, so what is written here survives
## the AnimationPlayer rewriting every other joint every frame. On the Spine it
## would be erased on the frame it was set, with nothing anywhere to say why.
##
## The twist owns that joint's Y and this owns its X and Z, so the two compose
## rather than clobbering each other — which is what makes a body able to lean
## into a turn while its chest is still tracking the aim.
##
## Driven by `Locomotion`, which is the thing that knows how fast this body is
## changing direction. Nothing here decides how much to lean.
## --- FOOT PLANTING -----------------------------------------------------------
##
## A CLIP MOVES A FOOT WHETHER OR NOT THE FOOT IS ON ANYTHING. Every stride here
## was a set of joint angles played back at a rate, so the foot went where the
## curve said and the ground was never consulted: on a slope one boot hung in the
## air and the other was buried, on a step both were, and while the body slid
## round a turn the planted foot slid with it.
##
## PLANTING IS ONE IDEA THAT FIXES ALL THREE. A foot near the ground is LOCKED to
## the world point it landed on and the leg is solved to keep it there, so:
##
##   the foot stops sliding      it is pinned to a place, not to the hips
##   turning in place takes STEPS  the pinned foot holds while the body turns,
##                               and only releases when the leg runs out of reach
##   stopping PLANTS             the swinging foot finishes its step and stays
##
## None of those needed a clip. They are what happens once a foot is allowed to
## belong to the ground instead of to the animation.
##
## WHERE IT RUNS IS THE WHOLE TRICK. The AnimationPlayer rewrites every leg joint
## every frame, so the solve has to happen AFTER it — hence `process_priority`
## below and `_process` rather than `_physics_process`. But a ray query may only
## be made during physics, so the GROUND under each foot is probed on the physics
## tick (by `Locomotion`, which is already there) and handed over. A ground height
## one frame old is worth nothing against getting the order wrong.

## How close to the ground a foot has to be before it counts as down.
const PLANT_BAND := 0.09
## ...and how far it may be dragged from where it landed before it gives up and
## takes a new step. This is what makes a turn in place read as FOOTWORK: the
## foot holds, the body turns, the leg stretches, and at this distance it steps.
const PLANT_BREAK := 0.34
## How fast a foot eases onto a new lock, so a step does not snap.
const PLANT_EASE := 18.0
## The lowest a hip may be dropped to keep a foot down (a foot on a step below
## the other pulls the whole body down rather than stretching one leg).
const HIP_DROP_MAX := 0.28

## Set by `Locomotion` — the world height of the ground under each foot, and
## whether the probe found any. Index 0 is LEFT.
var foot_ground := [0.0, 0.0]
var foot_ground_hit := [false, false]
## Turned on by `Locomotion` for bodies that are worth the two rays. Off by
## default, so a bare `CharacterModel` in a look test animates exactly as before.
var planting := false

var _plant_at := [Vector3.ZERO, Vector3.ZERO]
var _plant_on := [false, false]
var _plant_mix := [0.0, 0.0]
var _hip_drop := 0.0


func _process(delta: float) -> void:
	if planting:
		_solve_feet(delta)


## Where the ankle wants to be, and what the leg has to do about it.
func _solve_feet(delta: float) -> void:
	var hips := get_node_or_null(NodePath("Hips")) as Node3D
	if hips == null:
		return
	var want_drop := 0.0
	for i in 2:
		var sn := "L" if i == 0 else "R"
		var ankle := get_node_or_null(NodePath(PATHS["a" + sn])) as Node3D
		if ankle == null:
			continue
		var at := ankle.global_position
		var ground: float = foot_ground[i]
		# THE SOLE TOUCHES THE GROUND, NOT THE JOINT. The ankle sits `FOOT_LIFT`
		# above the bottom of the boot, so measuring the joint against the ground
		# both fails to notice a foot that is standing on it (the first version
		# never planted at all — a planted foot reads 75 mm "above" the ground)
		# and, once locked, buries the boot by the same amount.
		var lift: float = FOOT_LIFT * scale.y
		var down: bool = foot_ground_hit[i] and at.y - lift - ground < PLANT_BAND

		if down and not _plant_on[i]:
			# IT JUST LANDED. Lock it where it touched, sole on the ground.
			_plant_at[i] = Vector3(at.x, ground + lift, at.z)
			_plant_on[i] = true
		elif _plant_on[i]:
			# THE LOCK'S HEIGHT IS REFRESHED, ITS PLACE IS NOT. The XZ is the
			# whole point of a lock and must not move; the Y was captured on the
			# frame the foot touched, which is the frame the body is least
			# settled, and a lock taken a few centimetres wrong stays wrong
			# forever because a foot that is already down never re-captures.
			_plant_at[i].y = ground + lift
			# ...and it lets go once the leg can no longer reach the lock, which
			# is what turns a turn-in-place into a step rather than a stretch.
			var drag := Vector2(at.x - _plant_at[i].x, at.z - _plant_at[i].z).length()
			if not down or drag > PLANT_BREAK:
				_plant_on[i] = false
		_plant_mix[i] = move_toward(_plant_mix[i],
			1.0 if _plant_on[i] else 0.0, delta * PLANT_EASE)
		if _plant_mix[i] <= 0.001:
			continue
		var target := at.lerp(_plant_at[i], _plant_mix[i])
		# A foot that cannot be reached without straightening the leg pulls the
		# HIPS down instead — one leg stretched to a pin is the artefact this is
		# meant to remove, not a new one to introduce.
		#
		# MEASURED FROM THE HIP JOINT AND NOT FROM `Hips`. The pelvis node sits
		# about 10 cm above the joint the thigh actually turns on, and `HIP_Y` is
		# 20 cm longer than the leg it carries (see the note on LEG) — so asking
		# whether a foot is reachable from the pelvis says the leg is a fifth
		# longer than it is, and the drop never fires when it is needed.
		var hip := get_node_or_null(NodePath(PATHS["h" + sn])) as Node3D
		if hip != null:
			var reach := hip.global_position.distance_to(target)
			var limit: float = LEG * scale.y
			if reach > limit:
				want_drop = maxf(want_drop, minf(reach - limit, HIP_DROP_MAX))
		_leg_ik(sn, target)
	_hip_drop = lerpf(_hip_drop, want_drop, clampf(delta * 10.0, 0.0, 1.0))
	# SUBTRACTED FROM WHAT THE CLIP SET, not written over it. Several poses drop
	# the hips themselves — the idle stance pays for its splay that way, and the
	# crouch and the guard are nothing but hip drops — so assigning `HIP_Y` here
	# silently undid all of them and stood the body back up by the exact amount
	# the pose had just crouched it. Safe to subtract every frame because the
	# AnimationPlayer rewrites this joint before this function runs.
	hips.position.y -= _hip_drop


## What the ankle joint sits above the sole, so a locked foot is placed by its
## SOLE and not by the joint inside it.
const FOOT_LIFT := 0.075


## PUT THE ANKLE ON `target` BY CORRECTING THE POSE, NOT BY REPLACING IT.
##
## This is the whole difference between foot planting that works and foot
## planting that flattens every body's stance. The obvious version solves the leg
## from scratch and writes the hip and knee outright — and the hip's rotation is
## where the pose keeps its leg PLACEMENT, so a solved-from-scratch leg loses the
## idle stance's splay, the crouch's knee-out, and every other thing a clip said
## about where that leg should be. A body planted that way stands with its legs
## together, which is a worse artefact than the floating foot it fixed.
##
## So the animated pose is the starting point and this moves it the least it can:
##
##   THE KNEE sets how far the leg REACHES, and is the only joint whose value is
##     solved outright — extension is what has to change and the knee is the one
##     thing that changes it. Its bend axis is the rig's, not the solve's.
##   THE HIP is kept exactly as the clip left it and then SWUNG by the minimum
##     rotation that carries the ankle onto the target. A minimal swing preserves
##     everything about the hip that is perpendicular to it, which is precisely
##     the splay and the toe-out.
##
## Nothing accumulates: the AnimationPlayer rewrites both joints every frame
## before this runs (see `process_priority`), so each frame corrects a fresh pose.
func _leg_ik(sn: String, target: Vector3) -> void:
	var hip := get_node_or_null(NodePath(PATHS["h" + sn])) as Node3D
	var knee := get_node_or_null(NodePath(PATHS["k" + sn])) as Node3D
	if hip == null or knee == null:
		return
	var parent := hip.get_parent() as Node3D
	if parent == null:
		return
	var a := knee.position.length()
	if a <= 0.0001:
		return
	var b := LOWER_LEG
	var rest := knee.position / a          # the straight leg, in the hip's frame
	# Where the ankle has to end up, from the hip JOINT, in the hip's parent frame.
	var want: Vector3 = parent.global_transform.affine_inverse() * target \
		- hip.position
	var d := want.length()
	if d <= 0.0001:
		return
	# THE KNEE, from the extension alone. Same law of cosines `_arm_ik` takes
	# about the rest direction: only the part of the leg perpendicular to the bend
	# axis actually swings, hence the `rest.x²` term.
	var fixed := rest.x * rest.x
	var reach := (d * d - a * a - b * b) / (2.0 * a * b)
	var cos_flex := clampf((reach - fixed) / maxf(1.0 - fixed, 0.001), -1.0, 1.0)
	# NEGATIVE: a knee folds backward. With the elbow's sign the shin swings the
	# foot out in front of the body, which is not subtle to look at.
	var flex := -acos(cos_flex)
	knee.rotation = Vector3(flex, 0.0, 0.0)
	# THE HIP, swung from wherever the pose left it.
	var local_ankle := knee.position + Basis(Vector3.RIGHT, flex) * (rest * b)
	var posed := hip.basis * local_ankle
	if posed.length_squared() < 0.000001:
		return
	var from := posed.normalized()
	var to := want.normalized()
	# `Quaternion(from, to)` is undefined for anti-parallel vectors and hands back
	# a NaN basis, which then propagates into every global transform under this
	# joint and takes the frame with it. A leg asked to point exactly backwards
	# cannot happen with a reachable target, so it is refused rather than
	# approximated.
	if from.dot(to) < -0.9999:
		return
	var swung := Basis(Quaternion(from, to)) * hip.basis
	if not _finite(swung):
		return
	# ORTHONORMALISED: this composes a rotation onto a basis every frame, and
	# without it the numerical drift shows up as a leg that slowly shears.
	hip.basis = swung.orthonormalized()


## A basis with a NaN in it is worse than a wrong one: it spreads to every
## transform below it and there is nothing on screen or in the log to say where
## it started.
static func _finite(b: Basis) -> bool:
	for v in [b.x, b.y, b.z]:
		if not (is_finite(v.x) and is_finite(v.y) and is_finite(v.z)):
			return false
	return true


func set_lean(pitch: float, roll: float) -> void:
	if _twist_joint == null or not is_instance_valid(_twist_joint):
		return
	_twist_joint.rotation.x = pitch
	_twist_joint.rotation.z = roll


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


## Fade the whole model to `alpha` (1.0 = solid) for the Saurian's cloak.
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
# `armor`/`dark` colours are the BODY (so a legionary is white plate, a droid bronze),
# and the TEAM colour rides the ACCENTS (`_suit_mat`: shoulder bells, chest vest,
# belt, knee pads, helmet crest) — the way real armour markings read, and still a
# clear team call at a glance.
## Styles from EVERY universe live in one enum, for the same reason Weapon.Class
## does: STYLES is a dictionary keyed by it, so a Paladin costs a row and shifts
## nothing, and which universe a body belongs to is stated once in Loadout (the
## kit that wears it) rather than repeated here.
enum Style {
	GENERIC, LEGION, LEGION_TECH, LEGION_HEAVY, LEGION_VANGUARD,
	AUTOMATON, AUTOMATON_HEAVY, GLAIVE_DRONE, TACTICAL, HUNTER, WARDEN, URSAN, SAURIAN,
	# The Galactic Civil War: the Dominion's white plate is the legionary's armour
	# twenty years on, so these are the same builder with a colder palette and
	# different heads — which is the whole argument for the STYLES table.
	DOMINION_TROOPER, DOMINION_HEAVY, DOMINION_SCOUT, REAPER_TROOPER,
	DOMINION_OFFICER, DOMINION_GUARD,
	PACT_TROOPER, PACT_VANGUARD, PACT_PILOT, PACT_COMMANDO, PACT_OFFICER,
	# The reinforcements the fanbase actually names. Each is a silhouette before
	# it is a colour: a Aegis Drone is a hunched pod, an Kobb is knee-high, a Skiri
	# carries its shield in front of it.
	AEGIS_DRONE, INFILTRATOR_DRONE, VESPID, LEGION_COMMANDO, INCINERATOR_TROOPER,
	GARRISON_TROOPER, KOBB, SKIRI, ZHAAL_ULTRA,
	# Deep Range
	PALADIN, DROPTROOPER, COALITION_MARINE, ZHAAL, KOPA, URSID,
	# Ironhymn
	SENTINEL, CHORISTER, UNSLEEPING, UNSLEEPING_LORD, SCRAPKIN, SCRAPKIN_BOSS,
}

const STYLES := {
	# --- REINFORCEMENTS -------------------------------------------------------
	Style.AEGIS_DRONE:       {"armor": Color(0.52, 0.44, 0.30), "dark": Color(0.20, 0.17, 0.12), "accent": Color(0.95, 0.35, 0.20), "body": "aegis drone"},
	Style.INFILTRATOR_DRONE: {"armor": Color(0.30, 0.30, 0.33), "dark": Color(0.12, 0.12, 0.14), "accent": Color(0.90, 0.25, 0.20), "head": "b1", "bulk": 0.97, "acc": ["collar"]},
	Style.VESPID:      {"armor": Color(0.46, 0.34, 0.24), "dark": Color(0.22, 0.16, 0.11), "accent": Color(0.72, 0.58, 0.34), "head": "vespid", "bulk": 0.92, "acc": ["wings"]},
	Style.LEGION_COMMANDO: {"armor": Color(0.86, 0.87, 0.90), "dark": Color(0.14, 0.15, 0.18), "accent": Color(0.95, 0.72, 0.18), "head": "commando", "bulk": 1.10, "acc": ["pauldron", "backpack", "gauntlet"]},
	Style.INCINERATOR_TROOPER:   {"armor": Color(0.92, 0.93, 0.95), "dark": Color(0.08, 0.08, 0.09), "accent": Color(0.95, 0.42, 0.12), "head": "incinerator trooper", "bulk": 1.08, "acc": ["tank"]},
	Style.GARRISON_TROOPER:   {"armor": Color(0.80, 0.72, 0.48), "dark": Color(0.16, 0.15, 0.12), "accent": Color(0.38, 0.34, 0.24), "head": "garrison trooper", "acc": ["pauldron", "kama"]},
	Style.KOBB:           {"armor": Color(0.42, 0.30, 0.20), "dark": Color(0.24, 0.17, 0.11), "accent": Color(0.62, 0.48, 0.30), "head": "kobb", "bulk": 0.62, "acc": ["fur"]},
	Style.SKIRI:         {"armor": Color(0.55, 0.45, 0.28), "dark": Color(0.24, 0.20, 0.14), "accent": Color(0.35, 0.70, 0.95), "head": "skiri", "bulk": 0.88, "acc": ["shoulderplate"]},
	Style.ZHAAL_ULTRA:    {"armor": Color(0.88, 0.86, 0.74), "dark": Color(0.24, 0.22, 0.18), "accent": Color(0.95, 0.85, 0.35), "head": "mask", "bulk": 1.12, "acc": ["bigpauldron", "collar"]},
	# --- DOMINION ---------------------------------------------------------------
	Style.DOMINION_TROOPER:   {"armor": Color(0.93, 0.94, 0.96), "dark": Color(0.07, 0.07, 0.08), "accent": Color(0.10, 0.10, 0.12), "head": "dominion trooper"},
	Style.DOMINION_HEAVY: {"armor": Color(0.93, 0.94, 0.96), "dark": Color(0.07, 0.07, 0.08), "accent": Color(0.10, 0.10, 0.12), "head": "dominion trooper", "bulk": 1.20, "acc": ["pauldron", "gauntlet", "greaves"]},
	Style.DOMINION_SCOUT:  {"armor": Color(0.88, 0.89, 0.91), "dark": Color(0.10, 0.10, 0.12), "accent": Color(0.22, 0.22, 0.25), "head": "scout", "bulk": 0.94, "acc": ["thighplate", "greaves"]},
	Style.REAPER_TROOPER:  {"armor": Color(0.13, 0.14, 0.16), "dark": Color(0.05, 0.05, 0.06), "accent": Color(0.75, 0.12, 0.10), "head": "deathtrooper", "bulk": 1.04, "acc": ["gauntlet", "backpack"]},
	Style.DOMINION_OFFICER: {"armor": Color(0.22, 0.23, 0.26), "dark": Color(0.10, 0.10, 0.12), "accent": Color(0.55, 0.56, 0.60), "head": "cap", "bulk": 0.96},
	Style.DOMINION_GUARD: {"armor": Color(0.72, 0.10, 0.10), "dark": Color(0.42, 0.06, 0.06), "accent": Color(0.90, 0.30, 0.25), "head": "royalguard", "acc": ["robe", "collar"]},
	# --- PACT ALLIANCE -------------------------------------------------------
	Style.PACT_TROOPER:  {"armor": Color(0.46, 0.42, 0.30), "dark": Color(0.18, 0.16, 0.12), "accent": Color(0.70, 0.66, 0.50), "head": "rebel", "acc": ["pauldron"]},
	Style.PACT_VANGUARD: {"armor": Color(0.42, 0.38, 0.27), "dark": Color(0.16, 0.14, 0.11), "accent": Color(0.72, 0.62, 0.40), "head": "rebel", "bulk": 1.14, "acc": ["pauldron", "bandolier", "greaves"]},
	Style.PACT_PILOT:    {"armor": Color(0.80, 0.72, 0.24), "dark": Color(0.16, 0.16, 0.18), "accent": Color(0.92, 0.86, 0.40), "head": "pilot", "bulk": 0.98, "acc": ["bandolier", "backpack"]},
	Style.PACT_COMMANDO: {"armor": Color(0.26, 0.34, 0.22), "dark": Color(0.12, 0.15, 0.10), "accent": Color(0.45, 0.55, 0.35), "head": "hood", "bulk": 0.97, "acc": ["backpack", "kama"]},
	Style.PACT_OFFICER:  {"armor": Color(0.36, 0.30, 0.24), "dark": Color(0.14, 0.12, 0.10), "accent": Color(0.62, 0.54, 0.40), "head": "cap", "bulk": 0.96},

	Style.GENERIC:        {"armor": Color(0.70, 0.72, 0.76), "dark": Color(0.16, 0.17, 0.20), "head": "bare"},
	# Concord — white legionary plate, team colour on the body suit, a helmet crest.
	Style.LEGION:          {"armor": Color(0.86, 0.87, 0.90), "dark": Color(0.15, 0.16, 0.19), "head": "legionary"},
	Style.LEGION_TECH: {"armor": Color(0.86, 0.87, 0.90), "dark": Color(0.15, 0.16, 0.19), "head": "legionary", "acc": ["backpack"]},
	Style.LEGION_HEAVY:    {"armor": Color(0.88, 0.89, 0.92), "dark": Color(0.15, 0.16, 0.19), "head": "legionary", "bulk": 1.28, "acc": ["pauldron", "greaves"]},
	Style.LEGION_VANGUARD:      {"armor": Color(0.84, 0.85, 0.88), "dark": Color(0.14, 0.15, 0.18), "head": "legionary", "acc": ["antenna", "kama", "pauldron"]},
	# Automata — thin bronze light automaton, hulking heavy automaton, cloaked glaive drone, slim tactical.
	# The light automaton's BACKPLATE is the flared slab behind its neck: at range that shape
	# is what says "battle droid" well before the skull is readable.
	Style.AUTOMATON:             {"armor": Color(0.62, 0.50, 0.30), "dark": Color(0.30, 0.24, 0.14), "head": "b1", "bulk": 0.78, "acc": ["b1back"]},
	Style.AUTOMATON_HEAVY:             {"armor": Color(0.34, 0.36, 0.42), "dark": Color(0.14, 0.15, 0.18), "head": "b2", "bulk": 1.40, "acc": ["bigpauldron"]},
	Style.GLAIVE_DRONE:     {"armor": Color(0.30, 0.31, 0.34), "dark": Color(0.12, 0.13, 0.15), "head": "mask", "bulk": 0.96, "acc": ["cape"]},
	Style.TACTICAL:       {"armor": Color(0.40, 0.46, 0.54), "dark": Color(0.16, 0.18, 0.22), "head": "b1", "bulk": 0.86, "acc": ["b1back", "collar"]},
	# Base kits.
	Style.HUNTER:    {"armor": Color(0.55, 0.57, 0.62), "dark": Color(0.16, 0.17, 0.20), "head": "visor", "acc": ["jetpack"]},
	Style.WARDEN:           {"armor": Color(0.40, 0.31, 0.20), "dark": Color(0.22, 0.17, 0.11), "head": "hood", "acc": ["robe"]},
	Style.URSAN:        {"armor": Color(0.34, 0.23, 0.13), "dark": Color(0.22, 0.15, 0.09), "head": "furry", "bulk": 1.45, "acc": ["fur", "bandolier"]},
	Style.SAURIAN:     {"armor": Color(0.42, 0.47, 0.30), "dark": Color(0.24, 0.28, 0.18), "head": "bare", "bulk": 1.08, "acc": ["scales"]},
	# HALO — COALITION. A Paladin is a head taller than the marines it fights beside,
	# which is the only thing anyone needs to read at a glance; the DROPTROOPER is the
	# same soldier in black with the pod-visor helmet. The Paladin carries plate
	# on every limb — without the greaves and gauntlets a slab of a chest sat on
	# bare pipe-cleaner legs and read top-heavy.
	Style.PALADIN:        {"armor": Color(0.30, 0.40, 0.29), "dark": Color(0.11, 0.13, 0.12), "accent": Color(0.86, 0.66, 0.20), "head": "paladin", "bulk": 1.24, "acc": ["pauldron", "gauntlet", "greaves", "thighplate"]},
	Style.DROPTROOPER:           {"armor": Color(0.17, 0.19, 0.22), "dark": Color(0.07, 0.08, 0.10), "accent": Color(0.45, 0.48, 0.54), "head": "droptrooper", "bulk": 1.02, "acc": ["backpack", "gauntlet", "greaves"]},
	Style.COALITION_MARINE:         {"armor": Color(0.36, 0.38, 0.28), "dark": Color(0.14, 0.15, 0.12), "accent": Color(0.52, 0.48, 0.34), "head": "droptrooper", "bulk": 0.96, "acc": ["greaves"]},
	# HALO — Hierophany. The Elite is tall and armoured over a dark bodysuit, the
	# Grunt is tiny behind a methane tank bigger than it is, the Brute is the
	# widest thing in the game and wears half a set of plate.
	Style.ZHAAL:          {"armor": Color(0.36, 0.31, 0.56), "dark": Color(0.13, 0.11, 0.19), "accent": Color(0.72, 0.66, 0.95), "head": "elite", "bulk": 1.22, "acc": ["bigpauldron", "gauntlet", "greaves"]},
	Style.KOPA:          {"armor": Color(0.76, 0.44, 0.16), "dark": Color(0.22, 0.15, 0.09), "accent": Color(0.30, 0.34, 0.38), "head": "grunt", "bulk": 0.88, "acc": ["tank"]},
	Style.URSID:          {"armor": Color(0.46, 0.36, 0.28), "dark": Color(0.27, 0.21, 0.16), "accent": Color(0.58, 0.53, 0.47), "head": "brute", "bulk": 1.52, "acc": ["fur", "spikes", "shoulderplate", "greaves"]},
	# IRONHYMN — Order. Both chapters are the same power armour in different
	# heraldry, which is exactly how the setting works. The pack and the enormous
	# pauldrons ARE the silhouette: without them a marine is a coloured rectangle.
	Style.SENTINEL:    {"armor": Color(0.13, 0.26, 0.60), "dark": Color(0.08, 0.09, 0.12), "accent": Color(0.80, 0.68, 0.26), "head": "order", "bulk": 1.38, "acc": ["bigpauldron", "powerpack", "aquila", "gauntlet", "greaves", "thighplate"]},
	Style.CHORISTER:    {"armor": Color(0.62, 0.10, 0.10), "dark": Color(0.12, 0.07, 0.07), "accent": Color(0.85, 0.75, 0.32), "head": "order", "bulk": 1.38, "acc": ["bigpauldron", "jetpack", "aquila", "gauntlet", "greaves", "thighplate"]},
	# IRONHYMN — Necrons. Bare metal skeletons: no undersuit, no soft parts, an
	# exposed ribcage over a lit core, and the eyes are the only colour on them.
	Style.UNSLEEPING:         {"armor": Color(0.50, 0.52, 0.54), "dark": Color(0.13, 0.15, 0.15), "accent": Color(0.35, 1.0, 0.40), "head": "unsleeping", "bulk": 0.86, "acc": ["ribs"]},
	Style.UNSLEEPING_LORD:    {"armor": Color(0.40, 0.38, 0.30), "dark": Color(0.12, 0.14, 0.14), "accent": Color(0.40, 1.0, 0.45), "head": "unsleeping", "bulk": 1.12, "acc": ["ribs", "cape", "collar", "crest"]},
	# IRONHYMN — Orks. Green, wide, and wearing whatever they found, bolted on
	# crooked: the ASYMMETRY is the read.
	Style.SCRAPKIN:            {"armor": Color(0.29, 0.47, 0.21), "dark": Color(0.22, 0.18, 0.12), "accent": Color(0.42, 0.36, 0.28), "head": "ork", "bulk": 1.34, "acc": ["spikes", "bandolier", "shoulderplate", "scrap"]},
	Style.SCRAPKIN_BOSS:        {"armor": Color(0.25, 0.43, 0.19), "dark": Color(0.19, 0.16, 0.11), "accent": Color(0.46, 0.40, 0.30), "head": "ork", "bulk": 1.62, "acc": ["spikes", "shoulderplate", "scrap", "gauntlet", "greaves"]},
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
	# rather than the whole body — so a legionary reads as white plate with team markings
	# the way real armour does, and the accents still call the side at a glance.
	_suit_mat = _mat(_team_color, Finish.PLATE)
	var armor := _mat(style["armor"], Finish.PLATE)   # the class's main plate colour
	# TWO MORE TONES OF THE SAME PLATE, and the reason these stopped reading as
	# moulded plastic. Every plate on the body shared one material, so a pauldron
	# facing the sky, a chest facing you and a skirt flap hanging in shadow all
	# came back at exactly the same value — and a single flat value across a whole
	# figure is the loudest "toy" cue there is. Real armour is one COLOUR at many
	# values, because it is many separate pieces at many angles.
	#
	# Deliberately three materials rather than a per-part tint: a fresh material
	# per box would be forty a character and twelve characters a map, which is the
	# allocation rule this project cares most about. Three is free and gets almost
	# all of it, because the eye is reading the BREAK between panels, not a smooth
	# gradient. Raised/sky-facing pieces take `armor_hi`, hanging and recessed ones
	# `armor_lo`; the rest stay on the base tone.
	var armor_hi := _mat(_shade(style["armor"], 1.22, 0.90), Finish.PLATE)
	var armor_lo := _mat(_shade(style["armor"], 0.66, 1.10), Finish.PLATE)
	var dark := _mat(style["dark"], Finish.CLOTH)     # undersuit, joints, hands, boots
	# A THIRD colour, and the reason these units stopped reading as coloured
	# blocks. Two tones plus the team accent is enough for a trooper in one
	# palette, but a Paladin's gold visor, a Unsleeping's green light and an ork's
	# bare scrap metal are none of those three — every one of them was being
	# painted in the body colour and vanishing into it. Defaults to `dark`, so a
	# style that has nothing to say says nothing.
	var accent := _mat(style.get("accent", style["dark"]),
		style.get("accent_finish", Finish.METAL))
	var furry: bool = acc.has("fur")

	if style.get("body", "") == "aegis drone":
		_build_droideka_body(style, at, armor, armor_hi, armor_lo, dark, accent)
		_merge_parts()
		_apply_layers()
		_built = true
		return

	var hips := _joint(self, "Hips", Vector3(0.0, HIP_Y, 0.0))
	_box(hips, Vector3(0.27 * bulk, 0.15, 0.19 * bulk), Vector3(0, 0.03, 0), armor)        # pelvis
	_box(hips, Vector3(0.29 * bulk, 0.055, 0.205 * bulk), Vector3(0, -0.035, 0), _suit_mat)  # team belt
	_box(hips, Vector3(0.055, 0.06, 0.03), Vector3(0, -0.035, -0.105 * bulk), dark)        # buckle (front)
	if acc.has("kama"):   # ARC skirt: plated flaps hanging front and back
		for kz in [0.11, -0.11]:
			_box(hips, Vector3(0.30, 0.26, 0.04), Vector3(0, -0.17, kz * bulk), armor_lo)
	if acc.has("robe"):   # Warden tabard hanging from the waist, at the front
		_box(hips, Vector3(0.24, 0.36, 0.05), Vector3(0, -0.20, -0.10), armor_lo)

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
	_box(spine, Vector3(0.22 * bulk, 0.10, 0.19 * bulk), Vector3(0, 0.46, 0), armor_hi)    # collar (sky-facing)
	if acc.has("backpack"):                   # on the back (+z)
		_box(spine, Vector3(0.23, 0.28, 0.11), Vector3(0, 0.30, 0.15 * bulk), dark)
		_box(spine, Vector3(0.05, 0.14, 0.05), Vector3(0.09, 0.44, 0.14 * bulk), _suit_mat)  # antenna
	if acc.has("jetpack"):                     # on the back (+z)
		_box(spine, Vector3(0.21, 0.30, 0.10), Vector3(0, 0.32, 0.15 * bulk), armor_lo)
		for jx in [-0.07, 0.07]:
			_box(spine, Vector3(0.05, 0.07, 0.05), Vector3(jx, 0.14, 0.18), dark)      # nozzles
	if acc.has("cape") or acc.has("robe"):    # cloth down the back (+z)
		_box(spine, Vector3(0.32, 0.66, 0.03), Vector3(0, 0.15, 0.13 * bulk), armor_lo)
	if acc.has("bandolier"):                  # a team sash across a Ursan's fur (front)
		_box(spine, Vector3(0.085, 0.56, 0.04), Vector3(0.0, 0.24, -0.13 * bulk), _suit_mat).rotation.z = 0.34
	if acc.has("antenna"):                    # ARC trooper's rangefinder stalk
		_box(spine, Vector3(0.018, 0.22, 0.018), Vector3(0.10, 0.52, 0.0), dark)
	if acc.has("b1back"):
		# The battle droid's BACK PLATE: a flared slab standing behind the neck.
		# It is what a light automaton is recognised by at the range where its head is two
		# pixels, and it is also what stops a thin droid reading as an
		# underfed trooper.
		_box(spine, Vector3(0.21, 0.24, 0.055), Vector3(0, 0.42, 0.10 * bulk), armor)
		_box(spine, Vector3(0.25, 0.05, 0.05), Vector3(0, 0.535, 0.095 * bulk), armor_lo)
		_box(spine, Vector3(0.055, 0.16, 0.042), Vector3(0, 0.44, 0.132 * bulk), _suit_mat)
	if acc.has("wings"):
		# Vespid wings. The class flies (Gadget.WINGS), so the body has to
		# say so while it is standing still — and a winged insect is the one
		# silhouette in this roster nothing else can be mistaken for.
		#
		# LONG and swept BACK off the shoulder blades, not a flap beside each
		# shoulder: at square-ish proportions they clipped through the arms and
		# read as loose armour panels. Note `Basis(UP, t)` sends +X to
		# (cos t, 0, -sin t), so sweeping a wing REARWARD is a NEGATIVE yaw on
		# the right-hand side — the same sign trap as the tower greebles.
		# A box rotates about its own CENTRE, so the centre has to sit half a
		# wing BEHIND the shoulder blade or the inner end swings forward through
		# the chest and the wing reads as a panel strapped across the arm.
		for wx: float in [-1.0, 1.0]:
			var wing := _box(spine, Vector3(0.56, 0.17, 0.014),
				Vector3(wx * 0.27, 0.46, 0.20 + 0.14 * bulk), armor_lo)
			wing.rotation.y = wx * -0.89   # swept back along the body
			wing.rotation.z = wx * -0.22   # and lifted at the tip
			_box(spine, Vector3(0.06, 0.11, 0.08),
				Vector3(wx * 0.10, 0.44, 0.13 * bulk), dark)   # wing root
	if acc.has("powerpack"):
		# The Order power pack: the single most recognisable thing about the
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
		# The Kopa methane tank, which is most of a Grunt's silhouette: it is
		# bigger than the torso carrying it, and the hose to the mask is what
		# makes it read as breathing gear rather than as a rucksack.
		_box(spine, Vector3(0.26, 0.34, 0.20), Vector3(0, 0.26, 0.19 * bulk), accent)
		_box(spine, Vector3(0.05, 0.05, 0.05), Vector3(0.09, 0.44, 0.19 * bulk), dark)
		_box(spine, Vector3(0.035, 0.22, 0.035), Vector3(0.10, 0.50, 0.13 * bulk), dark)
	if acc.has("collar"):
		# A standing collar behind the skull: what a Unsleeping lord has instead of
		# pauldrons, which on a skeleton read as borrowed power armour.
		_box(spine, Vector3(0.30 * bulk, 0.26, 0.04), Vector3(0, 0.50, 0.10 * bulk), armor)
		# ...and it WRAPS, so there is something either side of the head from the
		# front. A collar that exists only at +z is a collar nobody looking at you
		# can see, which is how the lord came to read as a bare body.
		for cx in [-1.0, 1.0]:
			var wing := _box(spine, Vector3(0.05, 0.24, 0.17),
				Vector3(cx * 0.15 * bulk, 0.50, 0.04 * bulk), armor)
			wing.rotation.y = cx * 0.55
			_box(spine, Vector3(0.04, 0.20, 0.10),
				Vector3(cx * 0.14 * bulk, 0.52, 0.06 * bulk), accent)
	if acc.has("ribs"):
		# A Unsleeping has no flesh on it: the chest is an exposed cage over a lit
		# core. Three ribs and a spine, with the body colour showing between.
		for ry in [0.16, 0.26, 0.36]:
			_box(spine, Vector3(0.26 * bulk, 0.035, 0.21 * bulk), Vector3(0, ry, 0), armor)
		_box(spine, Vector3(0.05, 0.34, 0.05), Vector3(0, 0.26, 0.08 * bulk), armor)
		# THE CORE IS THE ONLY LIT THING ON THE UNIT, so it is the only thing that
		# carries at range, through smoke and on a night map — the same argument
		# as the turret's sensor slit. It was 9 cm square and invisible past ten
		# metres; a taller slot down the sternum reads as a power source rather
		# than as a pilot light. Energy stays at the shared 1.3: AgX at this
		# project's exposure takes emission much past unity to white, and a white
		# core stops being green.
		var core := _emit(Color(style.get("accent", Color(0.35, 1.0, 0.40))))
		_box(spine, Vector3(0.075, 0.26, 0.04), Vector3(0, 0.27, -0.105 * bulk), core)
		for gx in [-1.0, 1.0]:
			_box(spine, Vector3(0.03, 0.10, 0.03),
				Vector3(gx * 0.10 * bulk, 0.34, -0.10 * bulk), core)
	if acc.has("scrap"):
		# Ork armour is whatever was to hand, bolted on crooked. ASYMMETRY is the
		# whole point — a matched pair reads as issued kit, which orks do not have.
		_box(spine, Vector3(0.17, 0.22, 0.05), Vector3(-0.07, 0.30, -0.11 * bulk),
			accent).rotation.z = 0.16
		_box(spine, Vector3(0.22 * bulk, 0.09, 0.05), Vector3(0.03, 0.14, -0.11 * bulk), accent)

	var head := _joint(spine, "Head", at["head"])
	_build_head(style, head, armor_hi, dark)

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
			# The Order shoulder: enormous, standing well clear of the arm and
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
		if acc.has("crest"):
			# THE UNSLEEPING LORD'S SHOULDER: a bladed crest raked up and back, well
			# clear of the arm. It is NOT `bigpauldron` — an Order shoulder is
			# a slab of ceramite and a lord's is a thin standing FIN, and a
			# skeleton wearing a marine's pauldron reads as borrowed armour
			# (which is the note already on `collar`).
			#
			# It exists because the lord read as a plain body FROM THE FRONT: the
			# collar and the cape both sit at +z, so head-on there was nothing in
			# the silhouette at all — the one thing that is supposed to separate
			# a faction's signature from a trooper.
			# NO ROTATION ON THESE. The shoulder joint carries the rig's baked
			# quarter turn (see the T-pose note on `_build_body`), so its local
			# axes are NOT the world's — a `rotation.z` here rakes the fin out
			# SIDEWAYS instead of up, and the lord grew two extra limbs. Every
			# other shoulder accessory is placed and never turned, for the same
			# reason.
			# Sized and placed against `bigpauldron`, which is the shoulder piece
			# already known to sit right: its slab is at y 0.075 and its trim at
			# 0.17. Anything much above that floats off the joint, which is what
			# the first two attempts did.
			_box(sh, Vector3(0.05, 0.20, 0.16), Vector3(0.05 * side, 0.09, 0.01), armor)
			_box(sh, Vector3(0.03, 0.15, 0.05), Vector3(0.05 * side, 0.17, -0.04), accent)
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
		# THE HAND IS ITS OWN JOINT NOW, sitting exactly where its box already was —
		# so no geometry moved — and it can hold an angle to the WEAPON instead of
		# being a rigid extension of the forearm.
		var wrist := _joint(el, "Hand" + sn, at["w" + sn])
		_box(wrist, Vector3(0.075, 0.075, 0.075), handv.normalized() * 0.045, dark)     # hand

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
				at["k" + ln] * 0.42 + Vector3(0, 0, -0.08 * bulk), armor_hi)
		var footv: Vector3 = at["k" + ln].normalized() * LOWER_LEG
		if acc.has("greaves"):
			# Shin plate on the front of the lower leg. Cheap, and it stops a
			# heavily armoured unit having bare pipe-cleaner legs under a slab
			# of a chest — which is what made the Paladin read top-heavy.
			_box(knee, Vector3(0.15 * bulk, 0.26, 0.06),
				footv * 0.45 + Vector3(0, 0, -0.07 * bulk), armor_hi)
		_limb(knee, footv, 0.105 * bulk, 0.11 * bulk, armor)                            # shin
		# THE FOOT IS ITS OWN JOINT, at exactly the ankle the boot was already drawn
		# around. This is the single most visible of the two: the boot used to turn
		# rigidly with the shin, so every stride pointed the toe and a deep crouch
		# stood the whole unit on tiptoe with its heels in the air.
		var ankle := _joint(knee, "Ankle" + ln, at["a" + ln])
		_box(ankle, Vector3(0.115 * bulk, 0.10, 0.24 * bulk), Vector3(0, 0.0, -0.05), dark)  # boot
	_merge_parts()
	_apply_layers()
	_built = true


## The Aegis Drone cannot share the humanoid body and still read as a destroyer
## droid: the silhouette is the wheel shell, tripod legs and paired arm cannons.
## It still builds the SAME joint names, so the existing animation tracks, held
## weapon hook, corpses and render-layer restamping all keep their contracts.
func _build_droideka_body(style: Dictionary, at: Dictionary, armor: Material,
		armor_hi: Material, armor_lo: Material, dark: Material, accent: Material) -> void:
	var hips := _joint(self, "Hips", Vector3(0.0, HIP_Y, 0.0))
	_box(hips, Vector3(0.28, 0.12, 0.22), Vector3(0, 0.0, 0.02), dark)
	_box(hips, Vector3(0.24, 0.06, 0.26), Vector3(0, -0.07, 0.06), armor_lo)

	var twist := _joint(hips, "Twist", Vector3.ZERO)
	_twist_joint = twist
	twist.rotation.y = _twist
	var spine := _joint(twist, "Spine", Vector3.ZERO)

	# Armoured core: a hunched oval suggested by overlapping chamfered plates.
	_box(spine, Vector3(0.42, 0.30, 0.34), Vector3(0, 0.22, 0.04), armor)
	_box(spine, Vector3(0.34, 0.20, 0.24), Vector3(0, 0.34, -0.09), armor_hi)
	_box(spine, Vector3(0.32, 0.10, 0.12), Vector3(0, 0.12, -0.18), dark)
	_box(spine, Vector3(0.22, 0.08, 0.06), Vector3(0, 0.31, -0.25), _suit_mat)
	_box(spine, Vector3(0.08, 0.10, 0.035), Vector3(0, 0.38, -0.285), accent)

	# The rolled-up wheel halves stay visible even unfolded. Segmented bars keep
	# the outline round enough without adding a new mesh type.
	for side: float in [-1.0, 1.0]:
		var x := side * 0.245
		var pts := [
			Vector3(x, 0.48, -0.02),
			Vector3(x, 0.38, 0.18),
			Vector3(x, 0.15, 0.24),
			Vector3(x, -0.04, 0.08),
			Vector3(x, 0.06, -0.15),
			Vector3(x, 0.30, -0.20),
		]
		for i in pts.size():
			_bar(spine, pts[i], pts[(i + 1) % pts.size()], 0.035, armor_lo)
		_box(spine, Vector3(0.035, 0.22, 0.08), Vector3(x, 0.22, 0.02), dark)

	# Small forward sensor head, not a light automaton skull. It rides the normal head joint so
	# looking/aiming still gives the droid a visible facing.
	var head := _joint(spine, "Head", at["head"])
	_box(head, Vector3(0.13, 0.08, 0.12), Vector3(0, 0.06, -0.08), armor_hi)
	_box(head, Vector3(0.17, 0.045, 0.05), Vector3(0, 0.08, -0.16), dark)
	var eye := _emit(Color(style.get("accent", Color(1.0, 0.35, 0.18))))
	for ex in [-0.045, 0.045]:
		_box(head, Vector3(0.026, 0.022, 0.02), Vector3(ex, 0.09, -0.19), eye)

	for side in [-1, 1]:
		var sn := "L" if side < 0 else "R"
		var sh := _joint(spine, "Shoulder" + sn, at["s" + sn])
		_box(sh, Vector3(0.16, 0.16, 0.16), Vector3(0, 0.0, 0), armor)
		_bar(sh, Vector3.ZERO, at["e" + sn] * 0.86, 0.060, dark)
		var el := _joint(sh, "Elbow" + sn, at["e" + sn])
		var handv: Vector3 = at["e" + sn].normalized() * LOWER_ARM
		_bar(el, Vector3.ZERO, handv * 0.72, 0.052, dark)
		_box(el, Vector3(0.11, 0.10, 0.18), handv * 0.70, armor)
		# One cannon per arm: the barrel is an extension of the forearm, not a
		# separate rifle or a pair of tubes bolted to the wrist.
		_bar(el, handv * 0.70, handv * 1.38, 0.052, dark)
		_box(el, Vector3(0.070, 0.070, 0.070), handv * 1.43, accent)
		# EMPTY, AND THAT IS THE POINT. A Aegis Drone has no wrist and no boot, but it
		# builds every joint name the humanoid does — the comment above this builder
		# says so, and it is what keeps the shared clips, the corpse segments and
		# the render-layer restamp working without a single test for "is this the
		# droid". A clip keying a path that does not exist is a warning per track
		# per body, which is exactly the kind of noise that buries a real error.
		_joint(el, "Hand" + sn, at["w" + sn])

	var held := _joint(spine, "HeldGun", GUN_POS)
	_held = held
	# Integrated guns are on the arms above; keep the held joint as the animation
	# anchor and melee rebuild target, but do not add a humanoid rifle to it.

	for side in [-1, 1]:
		var ln := "L" if side < 0 else "R"
		var hip := _joint(hips, "Hip" + ln, at["h" + ln])
		var knee := _joint(hip, "Knee" + ln, at["k" + ln])
		_joint(knee, "Ankle" + ln, at["a" + ln])   # empty; see the note on Hand above

	# Tripod legs, fixed to the pelvis. A Aegis Drone rolls and braces more than it
	# walks, so the readable shape beats trying to reuse the humanoid leg swing.
	for side: float in [-1.0, 1.0]:
		var hip_plate := Vector3(0.16 * side, -0.02, -0.02)
		var knee_plate := Vector3(0.34 * side, -0.48, -0.12)
		var foot := Vector3(0.43 * side, -0.96, -0.20)
		_box(hips, Vector3(0.11, 0.09, 0.14), hip_plate, armor)
		_bar(hips, hip_plate, knee_plate, 0.066, dark)
		_bar(hips, knee_plate, foot, 0.058, dark)
		_box(hips, Vector3(0.23, 0.055, 0.30), foot + Vector3(0.03 * side, -0.01, -0.04), armor_lo)

	# Third stabiliser leg at the rear: the tripod read is more important than
	# strict animation, and this part stays on the pelvis.
	var rear_start := Vector3(0, -0.03, 0.13)
	var rear_knee := Vector3(0, -0.45, 0.30)
	var rear_end := Vector3(0, -0.96, 0.42)
	_bar(hips, rear_start, rear_knee, 0.064, dark)
	_bar(hips, rear_knee, rear_end, 0.056, dark)
	_box(hips, Vector3(0.24, 0.055, 0.32), rear_end + Vector3(0, -0.01, 0.04), armor_lo)


## WHAT MOVES TOGETHER AND SHADES THE SAME IS ONE MESH.
##
## A body is thirty-odd boxes and every one of them is its own draw call, four
## viewports deep, plus a shadow pass — measured at **109 draws per body**, which
## on a game made of boxes is the frame. But most of those boxes are siblings on
## the SAME JOINT wearing the SAME MATERIAL: a chest plate, a collar and an
## aquila all hang off the spine and all move as one piece, so nothing is lost by
## welding them into a single mesh.
##
## Merging is done as a POST-PASS rather than while building, and that is the
## point: the builders stay as they are — one `_box` call per shape, readable,
## with rotations and offsets applied afterwards by whoever wants them — and this
## runs once at the end, when every transform is final and can be baked.
##
## Grouped by everything that has to stay separate: the material, the shadow
## setting and the visibility range (a merged mesh has ONE of each, so a knee pad
## that culls at 45 m cannot join a thigh that never culls). Held weapon parts
## are excluded outright — they are toggled by name and by reference.
func _merge_parts() -> void:
	if not has_node("Hips"):
		return
	var held := {}
	for mi in _gun_parts + _saber_parts + _staff_parts:
		held[mi] = true
	for joint in [get_node("Hips")] + get_node("Hips").find_children("*", "Node3D", true, false):
		var groups := {}
		for child in joint.get_children():
			if not (child is MeshInstance3D) or held.has(child):
				continue
			var mi := child as MeshInstance3D
			if mi.mesh == null:
				continue
			var key := [mi.material_override, mi.cast_shadow, mi.visibility_range_end]
			if not groups.has(key):
				groups[key] = []
			groups[key].append(mi)
		for key in groups:
			var parts: Array = groups[key]
			if parts.size() < 2:
				continue   # nothing to weld
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			for mi: MeshInstance3D in parts:
				tool.append_from(mi.mesh, 0, mi.transform)
			var merged := MeshInstance3D.new()
			merged.mesh = tool.commit()
			merged.material_override = key[0]
			merged.cast_shadow = key[1]
			merged.visibility_range_end = key[2]
			joint.add_child(merged)
			for mi: MeshInstance3D in parts:
				joint.remove_child(mi)
				mi.queue_free()


## The third-person arc blade, on the same HeldGun joint as the blaster so the
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

	# `blade_energy` 0 is a STEEL weapon — a chain blade, a choppa, a hammer — and
	# steel is LIT, not emitting. Unshaded bypasses lighting but not the tonemap,
	# so a mid-grey albedo came out of AgX as a flat near-white slab at one value
	# on every face, which reads as frosted glass rather than as metal. Only
	# plasma is unshaded, and for the reason above: it has no shadow side.
	var core := _mat(core_col, Finish.METAL)
	if energy > 0.0:
		core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		core.emission_enabled = true
		core.emission = core_col
		core.emission_energy_multiplier = energy
	var glow := _mat(Color(glow_col.r, glow_col.g, glow_col.b, 0.5))
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.emission_enabled = true
	glow.emission = glow_col
	glow.emission_energy_multiplier = 3.0

	# Boxes rather than cylinders: at this size and this distance a square blade
	# is indistinguishable from a round one, and it is one less mesh type on a
	# model that already renders four times a frame.
	var at := Vector3(0, 0, -hilt * 0.5 - length * 0.5)
	_saber_parts.append(_box(held, Vector3(width, width, length), at, core))
	# The aura is ADDITIVE, so anything it is drawn over becomes translucent —
	# which is exactly right for plasma and exactly wrong for steel. The viewmodel
	# splits it on the same rule and for the same reason: a sleeve only ever goes
	# round a blade that IS light, a boxed HEAD (grav hammer, thunder hammer,
	# power klaw — every one of them a power weapon) gets a cap on its striking
	# face, and a steel cylinder (chain blade, choppa) gets nothing at all.
	if energy > 0.0:
		_saber_parts.append(_box(held,
			Vector3(width * 2.2, width * 2.2, length * 0.99), at, glow))
	elif float(_melee_look.get("blade_width", VM_BLADE_WIDTH)) * 0.5 \
			> Weapon.BLADE_HEAD_WIDTH:
		_saber_parts.append(_box(held,
			Vector3(width * 0.85, width * 0.85, length * 0.10),
			at + Vector3(0, 0, -length * 0.52), glow))

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
	# but a pole weapon that states its own colour (a Unsleeping warscythe's green)
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
	if crowd:
		mi.visibility_range_end = CROWD_BODY_RANGE
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.mesh = Meshes.chamfer_box(Vector3(tx, length, tz))
	mi.material_override = mat
	var dir := to.normalized()
	if not dir.is_equal_approx(Vector3.UP):
		mi.quaternion = Quaternion(Vector3.UP, dir)
	mi.position = to * 0.5
	parent.add_child(mi)
	return mi


## The per-unit head. The shape is the loudest part of the silhouette, so each
## archetype gets its own — a crested legionary helmet, a light automaton's photoreceptor stalk, a
## heavy automaton's sunken block, the glaive drone's masked cowl, a Ursan's muzzle, a hood.
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
		"legionary":
			# PHASE II. The tell is the T: a wide brow bar with a stem down the
			# nose, under a crown that sweeps to a point at the front and carries
			# a keel ridge front to back. Everything else on a legionary is paint.
			_box(joint, Vector3(0.175, 0.145, 0.185), Vector3(0, 0.175, 0), armor)       # crown
			_box(joint, Vector3(0.155, 0.095, 0.085), Vector3(0, 0.115, -0.065), armor)  # faceplate
			_box(joint, Vector3(0.19, 0.05, 0.07), Vector3(0, 0.215, -0.075), armor)     # swept brow
			_box(joint, Vector3(0.135, 0.045, 0.035), Vector3(0, 0.175, -0.115), dark)   # T bar
			_box(joint, Vector3(0.05, 0.10, 0.035), Vector3(0, 0.125, -0.115), dark)     # T stem
			for ex in [-0.092, 0.092]:
				_box(joint, Vector3(0.025, 0.11, 0.09), Vector3(ex, 0.155, -0.015), dark)   # comm plates
			_box(joint, Vector3(0.035, 0.05, 0.20), Vector3(0, 0.255, 0.005), _suit_mat)    # unit crest
			_box(joint, Vector3(0.16, 0.055, 0.05), Vector3(0, 0.10, 0.085), armor)      # rear neck flare
		"commando":
			# Katarn-class. A heavier legionary helmet with ONE wide lit visor band
			# instead of the T, and the rangefinder stalk on the left — which is
			# what stops Delta Squad reading as a legionary in slightly thicker plate.
			_box(joint, Vector3(0.195, 0.16, 0.195), Vector3(0, 0.175, 0), armor)
			_box(joint, Vector3(0.175, 0.10, 0.10), Vector3(0, 0.10, -0.06), armor)      # heavy chin
			_box(joint, Vector3(0.17, 0.06, 0.04), Vector3(0, 0.175, -0.115), dark)      # visor band
			var cme := _emit(Color(0.35, 0.85, 1.0))
			_box(joint, Vector3(0.145, 0.024, 0.02), Vector3(0, 0.178, -0.128), cme)     # lit visor line
			_box(joint, Vector3(0.045, 0.045, 0.05), Vector3(-0.10, 0.215, -0.06), dark) # rangefinder
			_box(joint, Vector3(0.024, 0.024, 0.10), Vector3(-0.10, 0.215, -0.115), dark)
			_box(joint, Vector3(0.09, 0.035, 0.035), Vector3(0, 0.105, -0.11), dark)     # chin vent
			_box(joint, Vector3(0.045, 0.05, 0.19), Vector3(0, 0.26, 0.005), _suit_mat)  # squad crest
		"dominion trooper":
			# The one helmet everybody can draw from memory: brow band, two
			# lenses, the raised trapezoid nose, and the FROWN — a black vent
			# with vertical teeth. Without the frown it is just a white legionary.
			_box(joint, Vector3(0.185, 0.15, 0.185), Vector3(0, 0.175, 0), armor)        # dome
			_box(joint, Vector3(0.175, 0.085, 0.115), Vector3(0, 0.105, -0.05), armor)   # cheeks
			_box(joint, Vector3(0.17, 0.055, 0.045), Vector3(0, 0.185, -0.10), dark)     # brow band
			for ex in [-0.052, 0.052]:
				_box(joint, Vector3(0.055, 0.045, 0.03), Vector3(ex, 0.18, -0.115), dark)   # lenses
			_box(joint, Vector3(0.045, 0.055, 0.04), Vector3(0, 0.145, -0.105), armor)   # raised nose
			_box(joint, Vector3(0.10, 0.045, 0.035), Vector3(0, 0.095, -0.108), dark)    # frown vent
			for tx in [-0.03, 0.0, 0.03]:
				_box(joint, Vector3(0.011, 0.045, 0.022), Vector3(tx, 0.095, -0.117), armor)  # teeth
			for sx in [-0.075, 0.075]:
				_box(joint, Vector3(0.028, 0.05, 0.022), Vector3(sx, 0.115, -0.10), _suit_mat)  # tube stripes
			_box(joint, Vector3(0.165, 0.05, 0.055), Vector3(0, 0.09, 0.08), armor)      # rear flare
		"garrison trooper":
			# Scarif. A dominion trooper shell with the tall centre KEEL over the
			# crown and a much wider neck guard — the two things that make a
			# garrison trooper read as its own unit rather than as a beach repaint.
			_box(joint, Vector3(0.18, 0.145, 0.19), Vector3(0, 0.175, 0), armor)
			_box(joint, Vector3(0.165, 0.09, 0.10), Vector3(0, 0.11, -0.06), armor)      # faceplate
			_box(joint, Vector3(0.055, 0.055, 0.21), Vector3(0, 0.25, 0.0), armor)       # keel
			_box(joint, Vector3(0.03, 0.03, 0.16), Vector3(0, 0.283, -0.01), _suit_mat)  # keel stripe
			_box(joint, Vector3(0.15, 0.05, 0.035), Vector3(0, 0.175, -0.115), dark)     # visor slot
			for ex in [-0.088, 0.088]:
				_box(joint, Vector3(0.028, 0.10, 0.10), Vector3(ex, 0.15, -0.01), dark)  # ear vents
			_box(joint, Vector3(0.085, 0.045, 0.035), Vector3(0, 0.10, -0.105), dark)    # mouth grille
			_box(joint, Vector3(0.19, 0.06, 0.075), Vector3(0, 0.085, 0.075), armor)     # neck guard
		"scout":
			# The biker scout: a bulbous crown and one enormous wraparound
			# goggle band covering the whole upper face, over a small chin cup.
			# It is the least "helmet-shaped" helmet the Dominion fields.
			_box(joint, Vector3(0.20, 0.155, 0.20), Vector3(0, 0.19, 0.005), armor)      # crown
			_box(joint, Vector3(0.205, 0.075, 0.10), Vector3(0, 0.16, -0.075), dark)     # goggle band
			_box(joint, Vector3(0.11, 0.075, 0.09), Vector3(0, 0.095, -0.065), armor)    # chin cup
			_box(joint, Vector3(0.075, 0.03, 0.03), Vector3(0, 0.085, -0.11), dark)      # mouth vent
			_box(joint, Vector3(0.05, 0.05, 0.10), Vector3(0, 0.27, 0.045), armor)       # crown ridge
			_box(joint, Vector3(0.10, 0.03, 0.07), Vector3(0, 0.268, -0.035), _suit_mat) # team flash
		"deathtrooper":
			# Long, black and featureless except for the visor: no frown, no
			# fin, no ear caps. The red lenses are the only thing on it, which
			# is exactly why the unit is frightening at a glance.
			_box(joint, Vector3(0.175, 0.155, 0.20), Vector3(0, 0.175, 0.005), armor)    # long skull
			_box(joint, Vector3(0.155, 0.115, 0.075), Vector3(0, 0.125, -0.085), armor)  # faceplate
			_box(joint, Vector3(0.145, 0.075, 0.03), Vector3(0, 0.16, -0.12), dark)      # visor plate
			var dte := _emit(Color(0.95, 0.16, 0.12))
			for ex in [-0.048, 0.048]:
				_box(joint, Vector3(0.036, 0.022, 0.02), Vector3(ex, 0.165, -0.132), dte)
			_box(joint, Vector3(0.055, 0.03, 0.05), Vector3(0, 0.095, -0.115), dark)     # respirator
			_box(joint, Vector3(0.016, 0.14, 0.016), Vector3(0.075, 0.29, 0.03), dark)   # comms antenna
			_box(joint, Vector3(0.03, 0.04, 0.12), Vector3(0, 0.26, 0.01), _suit_mat)
		"incinerator trooper":
			# The incinerator trooper wears a breather, not a visor: a smooth
			# dome with a narrow sight slot and a big round filter block where
			# the face should be, with the hose running back to the fuel pack.
			_box(joint, Vector3(0.185, 0.16, 0.185), Vector3(0, 0.18, 0.005), armor)     # smooth dome
			_box(joint, Vector3(0.16, 0.05, 0.04), Vector3(0, 0.195, -0.10), dark)       # sight slot
			_box(joint, Vector3(0.115, 0.10, 0.09), Vector3(0, 0.105, -0.075), dark)     # respirator
			_box(joint, Vector3(0.085, 0.085, 0.045), Vector3(0, 0.105, -0.125), armor)  # filter face
			for ex in [-0.028, 0.028]:
				_box(joint, Vector3(0.02, 0.055, 0.022), Vector3(ex, 0.105, -0.15), dark)   # intakes
			_box(joint, Vector3(0.034, 0.034, 0.16), Vector3(0.085, 0.115, 0.07), dark)  # hose
			_box(joint, Vector3(0.10, 0.035, 0.08), Vector3(0, 0.268, 0.0), _suit_mat)
		"royalguard":
			# Deliberately the plainest head in the game. A tall smooth helm
			# with ONE vertical slit and a skirt flaring to the shoulders — the
			# Emperor's guard reads as a silhouette, and detail would spoil it.
			_box(joint, Vector3(0.155, 0.26, 0.165), Vector3(0, 0.205, 0.005), armor)    # helm
			_box(joint, Vector3(0.175, 0.10, 0.185), Vector3(0, 0.085, 0.015), armor)    # skirt
			_box(joint, Vector3(0.034, 0.19, 0.03), Vector3(0, 0.19, -0.085), dark)      # the slit
			_box(joint, Vector3(0.16, 0.028, 0.17), Vector3(0, 0.075, 0.015), _suit_mat) # base band
		"cap":
			# An officer wears a UNIFORM, and the flat-topped peaked cap is the
			# whole read: disc crown, band, jutting brim, rank disc. The face is
			# bare, which on a field of helmets is itself the signal.
			var oskin := _mat(Color(0.62, 0.50, 0.42), Finish.HIDE)
			_box(joint, Vector3(0.15, 0.17, 0.155), Vector3(0, 0.135, -0.005), oskin)    # head
			_box(joint, Vector3(0.175, 0.055, 0.175), Vector3(0, 0.235, 0.005), armor)   # crown
			_box(joint, Vector3(0.18, 0.022, 0.18), Vector3(0, 0.268, 0.005), armor)     # flat top
			_box(joint, Vector3(0.182, 0.028, 0.182), Vector3(0, 0.205, 0.005), dark)    # band
			_box(joint, Vector3(0.155, 0.022, 0.065), Vector3(0, 0.202, -0.105), dark)   # peak
			_box(joint, Vector3(0.05, 0.03, 0.02), Vector3(0, 0.238, -0.09), _suit_mat)  # rank disc
		"rebel":
			# The Alliance helmet is a BOWL, not a mask: it sits on top of a
			# face you can see, and the flared rear guard is what tells it from
			# an Dominion lid at a hundred metres.
			var rskin := _mat(Color(0.58, 0.45, 0.35), Finish.HIDE)
			_box(joint, Vector3(0.155, 0.16, 0.16), Vector3(0, 0.14, -0.01), rskin)      # face
			_box(joint, Vector3(0.185, 0.09, 0.185), Vector3(0, 0.215, 0.005), armor)    # bowl
			_box(joint, Vector3(0.205, 0.055, 0.09), Vector3(0, 0.19, 0.085), armor)     # neck guard
			_box(joint, Vector3(0.145, 0.045, 0.03), Vector3(0, 0.175, -0.09), dark)     # goggle band
			for ex in [-0.088, 0.088]:
				_box(joint, Vector3(0.028, 0.075, 0.05), Vector3(ex, 0.15, -0.02), dark)    # chin strap
			_box(joint, Vector3(0.06, 0.035, 0.12), Vector3(0, 0.263, 0.02), _suit_mat)  # unit flash
		"pilot":
			# Flight gear: a squared shell with a rectangular visor block, comms
			# boxes on both sides and an oxygen mask over the mouth with the
			# hose down to the chest. Nothing else in The Compact Wars looks like it.
			_box(joint, Vector3(0.195, 0.15, 0.19), Vector3(0, 0.18, 0), armor)          # shell
			_box(joint, Vector3(0.155, 0.07, 0.045), Vector3(0, 0.19, -0.105), dark)     # visor block
			_box(joint, Vector3(0.12, 0.085, 0.085), Vector3(0, 0.11, -0.065), dark)     # oxygen mask
			_box(joint, Vector3(0.034, 0.034, 0.14), Vector3(0.085, 0.09, 0.03), dark)   # hose
			for ex in [-0.10, 0.10]:
				_box(joint, Vector3(0.03, 0.09, 0.11), Vector3(ex, 0.175, 0.0), _suit_mat)  # comm boxes
			_box(joint, Vector3(0.13, 0.045, 0.06), Vector3(0, 0.255, -0.05), _suit_mat) # squadron flash
		"vespid":
			# Long horizontal skull on a thin neck, a swept-back cranial crest,
			# a jutting jaw with mandibles and the big black compound eyes. An
			# insect, not a man in a mask.
			var chitin := _mat(Color(style["dark"]), Finish.HIDE)
			_box(joint, Vector3(0.055, 0.13, 0.055), Vector3(0, 0.11, 0), chitin)        # long neck
			_box(joint, Vector3(0.115, 0.13, 0.19), Vector3(0, 0.245, -0.02), armor)     # skull
			_box(joint, Vector3(0.09, 0.13, 0.075), Vector3(0, 0.29, 0.085), armor)      # cranial crest
			_box(joint, Vector3(0.10, 0.07, 0.09), Vector3(0, 0.185, -0.085), armor)     # jutting jaw
			for mx in [-0.032, 0.032]:
				_box(joint, Vector3(0.022, 0.05, 0.035), Vector3(mx, 0.155, -0.115), chitin)  # mandibles
			for ex in [-0.05, 0.05]:
				_box(joint, Vector3(0.045, 0.055, 0.05), Vector3(ex, 0.255, -0.085), dark)    # compound eyes
		"kobb":
			# Knee-high, so the HEAD carries the whole character: a furry face
			# with a snout and ears, inside the leather cowl. The head is
			# deliberately not scaled by bulk — an Kobb's head is too big for it.
			var pelt := _mat(Color(style["dark"]), Finish.HIDE)
			_box(joint, Vector3(0.185, 0.175, 0.175), Vector3(0, 0.145, 0), pelt)        # head
			_box(joint, Vector3(0.10, 0.085, 0.085), Vector3(0, 0.115, -0.11), pelt)     # snout
			_box(joint, Vector3(0.04, 0.03, 0.025), Vector3(0, 0.128, -0.155), dark)     # nose
			for ex in [-0.045, 0.045]:
				_box(joint, Vector3(0.026, 0.026, 0.022), Vector3(ex, 0.185, -0.085), dark)   # eyes
			for ax in [-0.10, 0.10]:
				_box(joint, Vector3(0.05, 0.075, 0.045), Vector3(ax, 0.20, 0.01), pelt)  # ears
			_box(joint, Vector3(0.21, 0.115, 0.20), Vector3(0, 0.245, 0.02), armor)      # cowl crown
			_box(joint, Vector3(0.215, 0.085, 0.06), Vector3(0, 0.205, -0.085), armor)   # cowl brim
			_box(joint, Vector3(0.045, 0.03, 0.10), Vector3(0, 0.30, 0.02), _suit_mat)   # clan band
		"skiri":
			# Kig-Yar: a narrow bird skull with a hooked beak and a swept crest
			# of quills. The head is the only part of a Skiri you can see when
			# it is behind its gauntlet, so it has to carry the species alone.
			var jhide := _mat(Color(style["dark"]), Finish.HIDE)
			_box(joint, Vector3(0.115, 0.13, 0.15), Vector3(0, 0.185, 0.01), jhide)      # skull
			_box(joint, Vector3(0.06, 0.055, 0.13), Vector3(0, 0.155, -0.10), armor)     # upper beak
			_box(joint, Vector3(0.045, 0.03, 0.05), Vector3(0, 0.132, -0.145), jhide)    # lower beak
			for qx in [-0.05, 0.0, 0.05]:
				_box(joint, Vector3(0.02, 0.10, 0.09), Vector3(qx, 0.265, 0.055), armor) # quill crest
			var jeye := _emit(Color(0.95, 0.80, 0.25))
			for ex in [-0.045, 0.045]:
				_box(joint, Vector3(0.026, 0.026, 0.022), Vector3(ex, 0.205, -0.055), jeye)
		"b1":
			# The light automaton's long, tapering skull on a thin neck, with two photoreceptors
			# and a slit mouth.
			_box(joint, Vector3(0.045, 0.11, 0.045), Vector3(0, 0.10, 0), dark)          # long neck
			_box(joint, Vector3(0.10, 0.20, 0.12), Vector3(0, 0.25, -0.01), armor)       # elongated head
			_box(joint, Vector3(0.115, 0.055, 0.03), Vector3(0, 0.24, -0.055), dark)     # brow
			_box(joint, Vector3(0.06, 0.02, 0.02), Vector3(0, 0.17, -0.06), dark)        # mouth slit
			var eye := _emit(Color(0.12, 0.12, 0.13))
			for ex in [-0.027, 0.027]:
				_box(joint, Vector3(0.022, 0.03, 0.02), Vector3(ex, 0.25, -0.065), eye)
		"b2":
			# The heavy automaton has no neck: a low blocky head sunk between huge shoulders, one
			# glowing photoreceptor visor.
			_box(joint, Vector3(0.19, 0.14, 0.18), Vector3(0, 0.07, 0), armor)
			_box(joint, Vector3(0.13, 0.05, 0.03), Vector3(0, 0.09, -0.095), dark)       # visor recess
			var eye := _emit(Color(1.0, 0.35, 0.18))
			_box(joint, Vector3(0.11, 0.02, 0.02), Vector3(0, 0.09, -0.10), eye)
		"mask":
			# The glaive drone's cowled head: a tall block with a raised centre mask
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
		"paladin":
			# MJOLNIR: a smooth dome with no ear caps and one big GOLD faceplate,
			# which is the entire silhouette people know it by.
			_box(joint, Vector3(0.19, 0.16, 0.19), Vector3(0, 0.17, 0), armor)
			_box(joint, Vector3(0.16, 0.10, 0.05), Vector3(0, 0.155, -0.095), dark)     # visor recess
			var gold := _emit(Color(0.95, 0.72, 0.20))
			_box(joint, Vector3(0.145, 0.075, 0.03), Vector3(0, 0.155, -0.105), gold)   # faceplate
			_box(joint, Vector3(0.055, 0.04, 0.10), Vector3(0, 0.255, -0.03), _suit_mat)  # team crest
		"droptrooper":
			# The DROPTROOPER/marine helmet: a rounded shell with a wide black visor band
			# and a comms pod on the left side.
			_box(joint, Vector3(0.185, 0.145, 0.19), Vector3(0, 0.165, 0), armor)
			_box(joint, Vector3(0.155, 0.065, 0.045), Vector3(0, 0.155, -0.10), dark)   # visor band
			_box(joint, Vector3(0.05, 0.05, 0.06), Vector3(-0.10, 0.145, -0.02), dark)  # comms pod
			_box(joint, Vector3(0.06, 0.035, 0.14), Vector3(0.06, 0.245, 0.0), _suit_mat)  # team stripe
		"elite":
			# Zhaal: a long crested crown over a SPLIT jaw. The four mandibles
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
			# Kopa: a small head almost entirely covered by a methane rebreather,
			# with the hose running back to the tank on its pack.
			_box(joint, Vector3(0.15, 0.13, 0.15), Vector3(0, 0.13, 0), armor)
			_box(joint, Vector3(0.12, 0.09, 0.06), Vector3(0, 0.115, -0.085), dark)     # mask cup
			_box(joint, Vector3(0.035, 0.035, 0.16), Vector3(0.055, 0.145, 0.06), dark) # hose
			var geye := _emit(Color(0.35, 0.85, 0.95))
			for ex in [-0.038, 0.038]:
				_box(joint, Vector3(0.026, 0.02, 0.02), Vector3(ex, 0.165, -0.075), geye)
		"brute":
			# Ursid: a heavy brow over a jutting muzzle, a bone crest along the
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
		"order":
			# A Mk VII helm: domed skull, a RESPIRATOR GRILLE jutting out where a
			# face would be, and two lenses. The snout is the tell — without it a
			# power-armoured marine reads as a very large legionary trooper.
			_box(joint, Vector3(0.20, 0.16, 0.20), Vector3(0, 0.175, 0), armor)         # skull
			_box(joint, Vector3(0.09, 0.09, 0.10), Vector3(0, 0.125, -0.125), armor)    # snout
			_box(joint, Vector3(0.075, 0.055, 0.03), Vector3(0, 0.125, -0.175), dark)   # grille
			_box(joint, Vector3(0.21, 0.045, 0.06), Vector3(0, 0.235, -0.075), armor)   # brow rim
			var aeye := _emit(Color(0.85, 0.20, 0.12))
			for ex in [-0.062, 0.062]:
				_box(joint, Vector3(0.042, 0.03, 0.025), Vector3(ex, 0.175, -0.10), aeye)
			_box(joint, Vector3(0.03, 0.06, 0.20), Vector3(0, 0.265, 0.0), _suit_mat)   # team crest
		"unsleeping":
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
			# A bare head with a simple face band (Saurian and the generic trooper).
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
	# THE FOOT SOLVE MUST RUN AFTER THE ANIMATION HAS WRITTEN THE LEG JOINTS, and
	# `_process` runs parents before children by default — which is exactly the
	# wrong order. A later priority puts this model's `_process` behind every
	# priority-0 node, the AnimationPlayer included. Without it the IK is written
	# and then overwritten on the same frame, with nothing anywhere to say why.
	process_priority = 1
	anim_player.root_node = NodePath("..")  # tracks are relative to this Character

	var lib := AnimationLibrary.new()
	lib.add_animation("idle", _clip(IDLE_LEN, true, 9, _idle_pose, _idle_bob))
	lib.add_animation("walk", _clip(WALK_LEN, true, 9, _walk_pose, Callable()))
	lib.add_animation("run", _clip(RUN_LEN, true, 9, _run_pose, Callable()))
	# DIRECTIONAL LOCOMOTION. Separate clips rather than one walk played at an
	# angle, for the reason the crouch is a clip pair: anything laid over the walk
	# at runtime is fighting the AnimationPlayer, which rewrites every joint in
	# PATHS every frame. They cost one table row each and nothing at runtime.
	lib.add_animation("walk_back", _clip(BACK_LEN, true, 9, _back_pose, Callable()))
	lib.add_animation("strafe_l",
		_clip(STRAFE_LEN, true, 9, _strafe_l_pose, Callable()))
	lib.add_animation("strafe_r",
		_clip(STRAFE_LEN, true, 9, _strafe_r_pose, Callable()))
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
	# THE SLIDE. Its own clip for the same reason the crouch has one, and NOT a
	# loop: a slide is an event with a beginning and an end, so it settles into
	# its pose and holds rather than cycling. `Locomotion` plays it for as long as
	# the state lasts and blends out of it when the state ends.
	lib.add_animation("slide", _clip(SLIDE_LEN, false, 5, _slide_pose, _slide_hips))
	# The guard is a clip pair for the same reason the crouch is: it has to survive
	# whatever else the AnimationPlayer writes that frame, and you can still walk
	# while holding it — a static stance played over a moving body skates the feet
	# exactly when the guard most needs to read.
	lib.add_animation("guard_idle",
		_clip(GUARD_IDLE_LEN, true, 9, _guard_idle_pose, _guard_idle_hips))
	lib.add_animation("guard_walk",
		_clip(GUARD_WALK_LEN, true, 9, _guard_walk_pose, _guard_walk_hips))
	anim_player.add_animation_library("", lib)


## --- dying ------------------------------------------------------------------
##
## DEATH AS A CLIP, which is the alternative to the ragdoll and not a replacement
## for it — both ship, and `Controls.death_style()` picks (see corpse.gd).
##
## What each buys is different enough that neither wins outright. The ragdoll
## lands correctly on a slope, against a cover box, half over a ledge, and it is
## thrown by whatever killed you; it cannot be built on a skinned mesh and it
## cannot be made to look like anything in particular. A clip is authored, plays
## identically every time, works on any rig — and knows nothing about the ground
## it is falling onto, which on this game's heightfield terrain is a real cost
## and not a theoretical one.
##
## THE TOPPLE PIVOTS AT THE FEET, and that is the whole trick. Rotating the Hips
## joint alone would swing the body about hip height and drive the head into the
## floor, so the hips TRANSLATE by exactly what the rotation moved them —
## `Basis * (0, HIP_Y, 0)` — which puts the pivot on the ground where a falling
## body's actually is. That one line is the difference between falling over and
## being spun on a spit.
enum Fall { BACK, FRONT, LEFT, RIGHT, CRUMPLE }

## WHERE THE ARMS END UP, PER DIRECTION, and this is a table rather than one pose
## because A BODY DOES NOT FALL ONTO ITS OWN ARM.
##
## The first version used a single asymmetric "arms flung out" pose for all five
## directions and it read fine standing still — then measured 71 cm of limb
## through the floor on a fall to the LEFT, because the arm that ends up
## underneath is exactly the one being flung outward. Whichever side goes down
## tucks IN across the chest; the other goes over the top. Face-down, both go out
## to the sides so neither is under the ribs.
##
## Values are degrees, converted once below. `tests/death_clip.tscn` is what says
## whether a change here is still above ground.
const DEATH_ARMS := {
	# Landing on the back: both arms are above the body, so they may splay.
	Fall.BACK: {"sL": Vector3(-52, 14, 28), "sR": Vector3(-38, -20, -34),
		"eL": Vector3(24, 0, 0), "eR": Vector3(38, 0, 0)},
	# Face down: out to the SIDES, clear of the chest, and the weapon with them.
	Fall.FRONT: {"sL": Vector3(-8, 0, 74), "sR": Vector3(-8, 0, -74),
		"eL": Vector3(26, 0, 0), "eR": Vector3(30, 0, 0)},
	# On the left side: the left arm comes in across the chest, the right flings
	# over the top of the body.
	Fall.LEFT: {"sL": Vector3(-62, 16, -46), "sR": Vector3(-26, -12, -66),
		"eL": Vector3(52, 0, 0), "eR": Vector3(30, 0, 0)},
	Fall.RIGHT: {"sL": Vector3(-26, 12, 66), "sR": Vector3(-62, -16, 46),
		"eL": Vector3(30, 0, 0), "eR": Vector3(52, 0, 0)},
	# Collapsing straight down: the arms come in, not out — there is no direction
	# to be flung in.
	Fall.CRUMPLE: {"sL": Vector3(-34, 10, -24), "sR": Vector3(-30, -10, 22),
		"eL": Vector3(58, 0, 0), "eR": Vector3(54, 0, 0)},
}

## THE LEGS FOLD THE SAME WAY, for the same reason: the down-side leg has to come
## under the body rather than out from it. One number per direction, applied as a
## hip ROLL — the fold itself is shared.
const DEATH_LEG_ROLL := {
	Fall.BACK: 1.0, Fall.FRONT: 1.0, Fall.LEFT: -1.0, Fall.RIGHT: 1.0,
	Fall.CRUMPLE: 0.4,
}

## WHICH WAY THE RIFLE SWINGS AS IT IS DROPPED, in degrees of yaw — and this is
## the table that cost the most to find. The weapon is the LONGEST thing on the
## body: the barrel reaches 37 cm past the joint it hangs on, further than any
## limb, so it is the first thing into the ground on any fall that swings it
## toward the down side. A single shared swing put 71 cm of rifle under a body
## falling left, and the obvious suspect — the arm on that side — was innocent.
##
## `Basis(Y, t)` sends the barrel (-Z) to (-sin t, 0, -cos t), so a POSITIVE yaw
## swings it to the body's left. Each entry therefore points it at the side that
## ends up on TOP.
const DEATH_GUN_YAW := {
	Fall.BACK: 40.0,      # lands on its back; the rifle rests across the chest
	Fall.FRONT: 70.0,     # face down; out to the side, clear of the ribs
	Fall.LEFT: -50.0,     # falling left, so the barrel goes right
	Fall.RIGHT: 50.0,
	Fall.CRUMPLE: 22.0,
}

## ...and WHERE it lands, in spine space. Yaw alone was not enough and the reason
## is worth writing down: a body toppling sideways rotates about Z, and a Z
## rotation leaves the barrel (which runs along -Z) pointing exactly where it
## was. Nothing about the weapon's ANGLE moves it out of the ground — only its
## POSITION does. So each fall shoves it toward the side that ends up on top.
## WHERE THE BODY TIPS OVER, on the floor, in metres from between the feet.
##
## "Pivot at the feet" is not one point — it is the EDGE you go over, and which
## edge depends on which way you are going. Toppling sideways about a point
## between both feet swings the down-side leg below the ground (measured: 26 cm
## of boot under the floor on a fall to the left, with the hips doing exactly
## what they were told). Pivoting about the outside of the foot you are falling
## over keeps that leg on the surface, which is what actually happens.
const DEATH_PIVOT := {
	Fall.BACK: Vector3(0.0, 0.0, 0.11),      # over the heels
	Fall.FRONT: Vector3(0.0, 0.0, -0.15),    # over the toes
	Fall.LEFT: Vector3(-0.25, 0.0, 0.0),     # over the outside of the left foot
	Fall.RIGHT: Vector3(0.25, 0.0, 0.0),
	Fall.CRUMPLE: Vector3(0.0, 0.0, -0.13),  # straight down, barely anywhere
}

const DEATH_GUN_SHIFT := {
	Fall.BACK: Vector3(0.05, -0.16, 0.06),
	Fall.FRONT: Vector3(0.23, -0.14, 0.36),
	Fall.LEFT: Vector3(0.28, -0.10, 0.10),    # falling left: the gun goes right
	Fall.RIGHT: Vector3(-0.28, -0.10, 0.10),
	Fall.CRUMPLE: Vector3(0.14, -0.18, 0.14),
}

const DEATH_LEN := 1.15
## More samples than a locomotion clip: those are periodic and read fine at nine,
## a fall is a one-shot accelerating curve and shows its corners.
const DEATH_SAMPLES := 14
const DEATH_CLIPS := {
	Fall.BACK: "death_back", Fall.FRONT: "death_front",
	Fall.LEFT: "death_left", Fall.RIGHT: "death_right",
	Fall.CRUMPLE: "death_crumple",
}
## How far the hips are allowed to end below their pivot once the knees have
## folded. A body lying down with its feet a few centimetres off the floor is
## invisible; hips driven through the floor are not.
const DEATH_MIN_HIP := 0.16

## A BODY DOES NOT TIP A FULL NINETY DEGREES, and this is the number that stops
## the fall putting geometry through the ground.
##
## A pure rotation about the feet maps every point behind the pivot axis to
## NEGATIVE y — so a backward fall drives the pack and the heels under the floor,
## and a face-down fall buries the rifle, which sticks out 35 cm in front of the
## chest. Measured: at a full 90 degrees the worst joint sat 76 cm below ground.
## Stopping short leaves the body unmistakably down (the head still ends around
## knee height) with everything above the floor, and the last few degrees were
## never legible anyway.
const DEATH_TIP_DEG := 74.0
## ...and the body rides a little proud of the pivot arc as it goes, because it
## is landing ON itself: a person lying down has their spine half a torso's
## thickness off the ground, not on it.
##
## DELIBERATELY SMALL. It is tempting to raise this until the floor test passes,
## and that is the wrong fix twice over — it hides which part is actually low,
## and a body whose hips end half a metre up is hovering, which is a worse
## artefact than the one being papered over. The parts that were going under (the
## rifle, the boots) are dealt with where they are, below.
const DEATH_LIE_LIFT := 0.14


## Built on DEMAND, not with the locomotion clips. Only a corpse ever plays one,
## and a living body paying to build five extra clips it will use once — at four
## viewports, twelve bodies, every respawn — is exactly the cost `static_pose`
## already exists to avoid.
func build_death_clips() -> void:
	if anim_player == null or anim_player.has_animation("death_back"):
		return
	var lib := anim_player.get_animation_library("")
	for fall: int in DEATH_CLIPS:
		lib.add_animation(DEATH_CLIPS[fall], _clip(DEATH_LEN, false, DEATH_SAMPLES,
			_death_pose.bind(fall), _death_hips.bind(fall)))


## Which way a body goes down, from the direction it was shoved. Taken in the
## body's OWN space so a shot in the back drops it forward wherever it is facing.
static func fall_from_push(push: Vector3, facing_yaw: float) -> int:
	var flat := Vector2(push.x, push.z)
	if flat.length() < 0.05:
		return Fall.CRUMPLE
	# Rotate the shove into body space: -Z is the way the model looks.
	var local := flat.rotated(facing_yaw)
	if absf(local.y) > absf(local.x):
		return Fall.BACK if local.y > 0.0 else Fall.FRONT
	return Fall.RIGHT if local.x > 0.0 else Fall.LEFT


## How far over the body is at `time`, 0..1. SQUARED, because a topple
## accelerates — at a constant rate it reads as being laid down rather than
## dropping, which is the single tell that separates a death from a lie-down.
func _death_fall(time: float) -> float:
	return pow(clampf(time / DEATH_LEN, 0.0, 1.0), 2.0)


func _death_hips_rot(time: float, fall: int) -> Vector3:
	var tip := deg_to_rad(DEATH_TIP_DEG) * _death_fall(time)
	match fall:
		Fall.BACK: return Vector3(tip, 0.0, 0.0)
		Fall.FRONT: return Vector3(-tip, 0.0, 0.0)
		Fall.LEFT: return Vector3(0.0, 0.0, tip)
		Fall.RIGHT: return Vector3(0.0, 0.0, -tip)
		# CRUMPLE folds rather than toppling — but it still has to end up DOWN.
		# At 0.55 it stopped at a 41-degree lean with the head at chest height,
		# which reads as a body sitting back on its heels, not one that has been
		# killed. It goes most of the way over and takes the hips with it.
		_: return Vector3(-tip * 0.92, 0.0, 0.0)


## The translation that keeps the pivot on the FLOOR rather than at the hips —
## and at the right PLACE on the floor, which is the edge being tipped over.
func _death_hips(time: float, fall: int) -> Vector3:
	var rot := _death_hips_rot(time, fall)
	var pivot: Vector3 = DEATH_PIVOT[fall]
	var rest := Vector3(0.0, HIP_Y, 0.0)
	var swung := pivot + Basis.from_euler(rot) * (rest - pivot)
	var g := _death_fall(time)
	# The knees fold as well as the body going over, so the hips end lower than a
	# rigid pivot would put them. Clamped, because the one thing a canned fall
	# must never do is sink the body into the ground it cannot see.
	var buckle := (0.22 if fall == Fall.CRUMPLE else 0.10) * g
	var y := maxf(swung.y - buckle, DEATH_MIN_HIP) + DEATH_LIE_LIFT * g
	return Vector3(swung.x, y, swung.z) - Vector3(0.0, HIP_Y, 0.0)


## The limbs on the way down. Deliberately loose and asymmetric — a body that
## folds symmetrically reads as a puppet being lowered. The arms give up the
## weapon (nothing is holding it any more), the knees buckle, and the head lolls
## the way the body is going.
func _death_pose(time: float, fall: int) -> Dictionary:
	var g := _death_fall(time)
	var t := clampf(time / DEATH_LEN, 0.0, 1.0)
	var p := _carry()
	p["hips_rot"] = _death_hips_rot(time, fall)
	# THE ARMS LET GO. They are solved onto the gun in every other clip; here they
	# fall away from it, which is most of what says this body is not fighting any
	# more. Blended in over the first part of the fall rather than snapped, so the
	# transition out of whatever clip was playing does not pop.
	var loose := clampf(t * 2.2, 0.0, 1.0)
	var arms: Dictionary = DEATH_ARMS[fall]
	for key in ["sL", "sR", "eL", "eR"]:
		p[key] = (p[key] as Vector3).lerp(_rad(arms[key]), loose)
	p["wL"] = Vector3(deg_to_rad(-16) * loose, 0, 0)
	p["wR"] = Vector3(deg_to_rad(-22) * loose, 0, 0)
	# The spine curls and the head lolls back — a dead body has no neck tone, and
	# the head is the part an onlooker reads first.
	p["spine"] = Vector3(deg_to_rad(-14) * g, deg_to_rad(9) * g, deg_to_rad(6) * g)
	p["head"] = Vector3(deg_to_rad(26) * g, deg_to_rad(-14) * g, 0)
	# The knees give way. Asymmetric on purpose, and further on the crumple, which
	# is the death that has no direction to fall in and has to say "collapsed".
	var fold := deg_to_rad(74.0 if fall == Fall.CRUMPLE else 42.0)
	var roll := deg_to_rad(7.0) * float(DEATH_LEG_ROLL[fall]) * g
	p["hL"] = Vector3(deg_to_rad(16) * g, 0, roll)
	p["hR"] = Vector3(deg_to_rad(26) * g, 0, roll)
	p["kL"] = Vector3(-fold * g, 0, 0)
	p["kR"] = Vector3(-fold * 0.72 * g, 0, 0)
	# THE BOOTS LIE FLAT, not pointed. A relaxed foot is right in the air (the jump
	# clip uses it) and wrong on the ground: with the body over on its side the
	# toe is the lowest thing on it, and a pointed one goes straight through the
	# floor. This is a case the ankle joint made FIXABLE — before it there was no
	# way to say it at all.
	# THE BOOTS LIE FLAT ON THE GROUND, which means cancelling the HIPS as well as
	# the hip and knee. `_ankle` levels a foot against the leg above it, and that
	# is the whole job while the body is upright — but a toppled body has rotated
	# the entire chain, so a foot level with respect to its own leg is still 74
	# degrees off the floor, and the toe is the lowest point on a body lying on
	# its side. Both axes, because a fall can be about either.
	var tip: Vector3 = p["hips_rot"]
	p["aL"] = _ankle(p["hL"].x + tip.x, p["kL"].x, ANKLE_LEVEL_FOLD) \
		+ Vector3(0.0, 0.0, -tip.z)
	p["aR"] = _ankle(p["hR"].x + tip.x, p["kR"].x, ANKLE_LEVEL_FOLD) \
		+ Vector3(0.0, 0.0, -tip.z)
	# THE WEAPON IS DROPPED, and where it goes is the fall's business too. It hangs
	# 35 cm in FRONT of the chest, so a face-down body carrying it in the hold
	# buries the whole rifle — it is shoved out to the side and back instead. It
	# stays keyed either way, because every clip keys the gun joint (see _carry)
	# and one that did not would snap the weapon back to the sternum.
	# ...and it ENDS FLAT. The gun hangs off the spine, so it inherits the whole
	# topple and comes down at whatever angle the body did — a rifle standing on
	# its muzzle. Cancelling the hips rotation as the fall completes lays it out
	# level, which is what a dropped weapon does and also the only way to keep the
	# longest object on the body out of the ground.
	p["gun"] = Vector3(GUN_ROT.x - tip.x,
		GUN_ROT.y + deg_to_rad(float(DEATH_GUN_YAW[fall])) * g,
		GUN_ROT.z - deg_to_rad(55) * g - tip.z)
	p["gun_pos"] = GUN_POS + (DEATH_GUN_SHIFT[fall] as Vector3) * g
	return p


## Degrees to radians, componentwise. The death tables are written in degrees for
## the reason every other angle in this file is: 74 is a number somebody can
## picture and 1.2915 is not.
static func _rad(degrees: Vector3) -> Vector3:
	return Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))


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
	# THE HIPS ROTATE AS WELL AS TRANSLATE, which no locomotion clip uses and the
	# death clips are built entirely out of: it is the only joint above the legs,
	# so it is the only one that can lay a whole body down. Every other pose leaves
	# it at identity, which costs one track of constant keys.
	var hips_track := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(hips_track, NodePath("Hips"))
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
		a.rotation_track_insert_key(hips_track, time,
			Quaternion.from_euler(pose.get("hips_rot", Vector3.ZERO)))
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
	# THE WRIST TAKES BACK PART OF THE ELBOW'S BEND, so the hand keeps its angle to
	# the WEAPON rather than to the forearm. It is read off the solve rather than
	# posed, which is the same rule the hold itself follows — a hand-set wrist
	# angle would be right for one gun position and wrong for the guard, the run
	# carry and every unit whose arms are a different length.
	return {
		"sR": right[0], "eR": Vector3(right[1], 0.0, 0.0),
		"wR": Vector3(-right[1] * WRIST_FOLLOW, 0.0, 0.0),
		"sL": left[0], "eL": Vector3(left[1], 0.0, 0.0),
		"wL": Vector3(-left[1] * WRIST_FOLLOW, 0.0, 0.0),
	}


## THE FOOT STAYS ON THE FLOOR. An ankle rotation that cancels what the hip and
## knee did, so the sole stays parallel to the ground instead of turning rigidly
## with the shin. `share` is how much of it to take back: total while crouched
## (you are stood on flat feet), partial while striding (a real foot rolls off),
## least in the air (it relaxes, it does not level).
##
## Composing about X all the way down the chain means the foot's pitch is simply
## the SUM of the two angles above it, which is why this is one line and not a
## transform solve.
func _ankle(hip_x: float, knee_x: float, share: float, toe_off := 0.0) -> Vector3:
	return Vector3(-(hip_x + knee_x) * share + toe_off, 0.0, 0.0)


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
## `bend` is which way the middle joint folds: +1 for an elbow, -1 for a KNEE.
## A leg is the same solve as an arm run backwards — the shin has to swing the
## foot behind the body, and with the elbow's sign it swings it in front, which
## is a knee bending the wrong way and is not subtle to look at.
func _arm_ik(target: Vector3, elbow: Vector3, b: float, bend := 1.0) -> Array:
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
	var h := elbow + Basis(Vector3.RIGHT, flex * bend) * (rest * b)
	var swing := Quaternion(h.normalized(), target.normalized())
	return [swing.get_euler(), flex * bend]


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
	# ...and the SOLE stays flat while the leg rolls out. The splay is a roll at
	# the hip, so without this the boot stands on its outside edge — which at a
	# stance this wide is the most visible thing about the idle pose, because the
	# idle is what a body is doing most of the time.
	p["aL"] = p.get("aL", Vector3.ZERO) + Vector3(0.0, 0.0, -splay)
	p["aR"] = p.get("aR", Vector3.ZERO) + Vector3(0.0, 0.0, splay)
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
	var toe := deg_to_rad(ANKLE_TOE_OFF_DEG)
	p["hL"] = Vector3(hip * s, 0, 0)
	p["hR"] = Vector3(-hip * s, 0, 0)
	# Knee flexes (-X) only mid-swing (peak at the leg's passing frame),
	# straight on contact and through stance — the two-joint gait.
	p["kL"] = Vector3(-knee * maxf(0.0, c), 0, 0)
	p["kR"] = Vector3(-knee * maxf(0.0, -c), 0, 0)
	# The foot rolls off at the END of the stride — the leg trailing (s < 0) is
	# the one pushing — and is held flat the rest of the way. Without the toe-off
	# a levelled foot reads as sliding rather than walking, which is the opposite
	# failure to the one the ankle was added for.
	p["aL"] = _ankle(p["hL"].x, p["kL"].x, ANKLE_LEVEL_WALK, toe * maxf(0.0, -s))
	p["aR"] = _ankle(p["hR"].x, p["kR"].x, ANKLE_LEVEL_WALK, toe * maxf(0.0, s))
	return p


## --- moving in a direction other than forwards -------------------------------
##
## A BODY THAT STRAFES MUST NOT TAKE A FORWARD STRIDE. The state machine picked
## its clip off the MAGNITUDE of the move input and ignored its DIRECTION, so
## every unit in the game side-stepped and backpedalled with a full forward walk
## cycle underneath it — feet striding one way, body travelling another. It is
## the most visible thing wrong with the animation and it is visible on every
## body on the field, all the time, because sidestepping is what a firefight IS.
##
## THE BACKPEDAL IS NOT THE WALK PLAYED BACKWARDS. Running a clip in reverse
## reverses the knee too, and a knee that leads the shin forwards is the one
## thing a leg cannot do — it reads instantly as broken rather than as reversed.
## What actually changes when you walk backwards is that the stride SHORTENS, the
## knee lifts MORE (you pick the foot up rather than rolling it), and the toe-off
## disappears entirely, because there is nothing to push off against behind you.
const BACK_LEN := 1.05      # backing up is slower than walking forward
const BACK_HIP_DEG := 19.0  # ...and a shorter stride
const BACK_KNEE_DEG := 40.0 # ...with a higher foot lift

## A SIDESTEP IS A ROLL AT THE HIP, NOT A SWING. The legs scissor apart and
## together in the frontal plane (rotation about Z) rather than fore-and-aft, the
## trailing leg closing after the leading one — which is why the two hips share a
## phase here instead of being half a cycle apart like a stride.
const STRAFE_LEN := 0.85
const STRAFE_SPREAD_DEG := 15.0   # how far the legs scissor apart
const STRAFE_KNEE_DEG := 22.0     # the trailing leg's tuck as it closes
const STRAFE_LEAN_DEG := 5.0      # into the direction of travel


## `dir` is +1 stepping to the body's RIGHT and -1 to its LEFT. One pose function
## for both, because a sidestep is genuinely symmetric — the leading and trailing
## legs swap and nothing else does.
func _strafe_pose(time: float, dir: float) -> Dictionary:
	var phase := time / STRAFE_LEN * TAU
	var s := sin(phase)
	var c := cos(phase)
	var spread := deg_to_rad(STRAFE_SPREAD_DEG)
	var knee := deg_to_rad(STRAFE_KNEE_DEG)
	var p := _carry()
	# Both hips roll the same way and the legs open and close together: the lead
	# leg reaches out on the half-cycle the trail leg is closing up.
	p["hL"] = Vector3(0, 0, spread * s * dir)
	p["hR"] = Vector3(0, 0, spread * s * dir)
	# Whichever leg is TRAILING tucks its knee to clear the ground as it closes.
	# `dir` picks which of the two that is without a branch.
	p["kL"] = Vector3(-knee * maxf(0.0, c * dir), 0, 0)
	p["kR"] = Vector3(-knee * maxf(0.0, -c * dir), 0, 0)
	# The ankles level against the knee only — there is no hip pitch to cancel
	# here, and no toe-off, because a sidestep pushes sideways off the edge of the
	# foot rather than rolling off the front of it.
	p["aL"] = _ankle(0.0, p["kL"].x, ANKLE_LEVEL_WALK, 0.0)
	p["aR"] = _ankle(0.0, p["kR"].x, ANKLE_LEVEL_WALK, 0.0)
	# Lean into the step. Small: this is a shuffle under a levelled weapon, not a
	# slalom, and the carry has to stay pointed where the player is aiming.
	p["spine"] = Vector3(0, 0, deg_to_rad(STRAFE_LEAN_DEG) * dir)
	return p


func _strafe_l_pose(time: float) -> Dictionary:
	return _strafe_pose(time, -1.0)


func _strafe_r_pose(time: float) -> Dictionary:
	return _strafe_pose(time, 1.0)


func _back_pose(time: float) -> Dictionary:
	var phase := time / BACK_LEN * TAU
	var s := sin(phase)
	var c := cos(phase)
	var hip := deg_to_rad(BACK_HIP_DEG)
	var knee := deg_to_rad(BACK_KNEE_DEG)
	var p := _carry()
	p["hL"] = Vector3(hip * s, 0, 0)
	p["hR"] = Vector3(-hip * s, 0, 0)
	# The knee lift peaks with the leg's REARWARD reach rather than mid-swing:
	# backing up, the foot comes up and goes down behind you.
	p["kL"] = Vector3(-knee * maxf(0.0, -s), 0, 0)
	p["kR"] = Vector3(-knee * maxf(0.0, s), 0, 0)
	# No toe-off at all — see the note above.
	p["aL"] = _ankle(p["hL"].x, p["kL"].x, ANKLE_LEVEL_WALK, 0.0)
	p["aR"] = _ankle(p["hR"].x, p["kR"].x, ANKLE_LEVEL_WALK, 0.0)
	# Weight back over the heels. A body walking backwards leaning FORWARD is the
	# tell that a forward clip is being reused, so this is worth the one line.
	p["spine"] = Vector3(deg_to_rad(6), 0, 0)
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
	# A harder push than the walk's, because that is what a run IS — the same
	# stride length taken faster would just be a fast walk.
	var toe := deg_to_rad(ANKLE_TOE_OFF_DEG * 1.6)
	p["aL"] = _ankle(p["hL"].x, p["kL"].x, ANKLE_LEVEL_WALK, toe * maxf(0.0, -s))
	p["aR"] = _ankle(p["hR"].x, p["kR"].x, ANKLE_LEVEL_WALK, toe * maxf(0.0, s))
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
	# THE BIGGEST SINGLE WIN THE ANKLE BOUGHT. With the knee folded to twice the
	# hip angle the shin runs back at 55 degrees, so a boot rigid to it pointed 55
	# degrees into the air and every crouched unit in the game was balanced on its
	# heels. Levelled in full here: a squat is stood on flat feet.
	p["aL"] = _ankle(hip, -knee, ANKLE_LEVEL_FOLD)
	p["aR"] = _ankle(hip, -knee, ANKLE_LEVEL_FOLD)
	return p


func _crouch_idle_pose(_time: float) -> Dictionary:
	return _crouch_base()


## GOING TO GROUND. Built from the carry like every other pose, so both hands
## stay on the weapon — a slide is a fighting move and the gun has to stay up,
## which is also why nothing here touches the arms.
##
## It EASES IN over the clip rather than snapping to the final angles: the body
## is dropping into this over about a fifth of a second, and a pose that is fully
## down on frame one reads as the model teleporting into a squat. `_clip` samples
## this at five points across `SLIDE_LEN` and the clip does not loop, so the last
## sample is the pose it holds for the rest of the slide.
func _slide_pose(time: float) -> Dictionary:
	var k: float = clampf(time / (SLIDE_LEN * 0.55), 0.0, 1.0)
	# Smoothstepped, for the reason the ADS zoom is: a linear settle reads as a
	# machine moving a limb, an eased one reads as a body arriving.
	k = k * k * (3.0 - 2.0 * k)
	var trail_hip := deg_to_rad(SLIDE_TRAIL_HIP_DEG) * k
	var trail_knee := deg_to_rad(SLIDE_TRAIL_KNEE_DEG) * k
	var lead_hip := deg_to_rad(SLIDE_LEAD_HIP_DEG) * k
	var lead_knee := deg_to_rad(SLIDE_LEAD_KNEE_DEG) * k
	var p := _carry()
	# BACK, not forward — see SLIDE_LEAN_DEG. Positive pitch on the spine is the
	# opposite sign to the crouch's lean, which is the one thing to check if this
	# ever starts reading as a squat again.
	p["spine"] = Vector3(deg_to_rad(SLIDE_LEAN_DEG) * k, 0, 0)
	p["head"] = Vector3(-deg_to_rad(SLIDE_HEAD_DEG) * k, 0, 0)
	# LEFT LEADS. Which leg is arbitrary — nothing else in the rig is handed —
	# but it has to be CHOSEN rather than left symmetric, because symmetric is
	# precisely what makes it a crouch.
	p["hL"] = Vector3(lead_hip, 0, 0)
	p["kL"] = Vector3(-lead_knee, 0, 0)
	p["hR"] = Vector3(trail_hip, 0, 0)
	p["kR"] = Vector3(-trail_knee, 0, 0)
	# The trailing foot is under the body and carrying it, so it is levelled the
	# way a crouched foot is; the lead foot is off the ground with the toe up,
	# which is what a heel-first leg does and what stops it reading as a kick.
	p["aR"] = _ankle(trail_hip, -trail_knee, ANKLE_LEVEL_FOLD)
	p["aL"] = _ankle(lead_hip, -lead_knee, ANKLE_LEVEL_FOLD, -0.20 * k)
	return p


## The hips drop into the slide over the same eased curve the joints do, or the
## body would arrive at its final height before its legs had folded to match.
func _slide_hips(time: float) -> Vector3:
	var k: float = clampf(time / (SLIDE_LEN * 0.55), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	return Vector3(0, SLIDE_HIP_DROP * k, 0)


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
	p["aL"] = _ankle(p["hL"].x, p["kL"].x, ANKLE_LEVEL_FOLD)
	p["aR"] = _ankle(p["hR"].x, p["kR"].x, ANKLE_LEVEL_FOLD)
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
	p["aL"] = _ankle(hip, -knee, ANKLE_LEVEL_FOLD)
	p["aR"] = _ankle(hip, -knee, ANKLE_LEVEL_FOLD)
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
	p["aL"] = _ankle(p["hL"].x, p["kL"].x, ANKLE_LEVEL_FOLD)
	p["aR"] = _ankle(p["hR"].x, p["kR"].x, ANKLE_LEVEL_FOLD)
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
	# Airborne the feet RELAX rather than level — nothing is holding them flat,
	# and a body in the air with its soles parallel to a floor it is nowhere near
	# is the one place levelling reads as wrong.
	p["aL"] = _ankle(p["hL"].x, p["kL"].x, ANKLE_LEVEL_AIR)
	p["aR"] = _ankle(p["hR"].x, p["kR"].x, ANKLE_LEVEL_AIR)
	return p
