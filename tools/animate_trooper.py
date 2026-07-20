"""Author idle/walk/run/jump animations onto the rigged (but animation-less)
trooper GLB, then export a new GLB for Godot.

Run:  blender --background --python animate_trooper.py -- <src.glb> <dst.glb>
      (src = assets/models/rep/p3_heavyglb.glb, dst = godot/assets/models/...)
After running, restart/refocus the Godot editor so it reimports the GLB — a
changed animation *library* (a clip added or removed) is not always picked up
by a plain refocus; deleting godot/.godot/imported/*p3_heavyglb* + editor
restart is the reliable path.

ANIMATION STYLE — deliberately BASIC (Minecraft / Krunker.io):
  This model is a set of rigid low-poly armor CHUNKS with crude nearest-bone
  skinning, so subtle, "realistic" secondary motion (breathing, ankle roll,
  pelvis counter-twist, spine flex) lands in the uncanny valley — the chunks
  visibly slide and tear. The style that fits the model is big, simple, rigid
  motion: the legs articulate at just two joints (hip + knee), the arms swing
  as single poles from the shoulder, all in plain opposing sine arcs, and
  NOTHING else moves. Keep it that way. If a clip starts to look "off", the
  fix is almost always LESS motion (fewer joints, bigger simpler swings), not
  more detail. Specifically DO NOT re-add: ankle/foot articulation, pelvis or
  spine twist, chest breathing, head turns, or a landing recoil — all were
  tried and read as freakish here. The knee flex stays subtle and only lifts
  the swing foot mid-step; the leg is straight on contact and while planted.

PIPELINE (top to bottom in this file):
  1. Import GLB, delete junk meshes (p_mainchunk, Icosphere).
  2. Flatten: unparent from the rotated DummyRoot empties, bake transforms so
     bone-rest space == mesh-vertex space == world space.
  3. Reorient the whole model to a canonical frame (up=+Z, fwd=+Y in Blender
     -> up=+Y, facing -Z in Godot) using joint POSITIONS, not bone tails.
  4. Skin: deterministic nearest-two-bone-segment weighting (the asset ships
     with NO skin weights; Blender's auto-weights are nondeterministic here).
  5. Measure world-space axes from joint positions, build a BASE carry pose,
     then author each clip as keyframed offsets from BASE.
  6. Export GLB with sampled animations.

POSE-AUTHORING CONVENTIONS (steps 5-6 — this is what you edit to tune motion):
  * Never trust bone TAILS: this rig's tails are importer-guessed stubs. Every
    direction is derived from joint HEAD positions instead.
  * Axes (all world-space unit vectors): UP (pelvis->head), DOWN, side_lr
    (left hand->right hand, flattened), and l_axis/r_axis (swing each arm down
    in its own plane).
  * rotate_world(bone, axis, deg) rotates a pose bone about a world axis
    through its head. Sign convention about side_lr (right-hand rule): a
    down-pointing limb (thigh / hanging arm) swings FORWARD with +deg; an
    up-pointing bone (spine) leans forward with -deg.
  * Loop clips are functions pose(t), t in [0, 1); inside, phase = 2*pi*t and
    s = sin(phase). add_loop_action() samples pose(t) at evenly spaced frames
    and repeats the first pose on the final frame to close the loop.
  * jump is a one-shot authored by hand with NO "-loop" suffix, so Godot
    imports it as non-looping and holds the last frame while airborne
    (player.gd keeps it assigned until is_on_floor() again).

To add a clip: write a pose(t) (loop) or a couple of hand-keyed frames
(one-shot), then add_loop_action("name-loop", ...) or a manual action+track
block, and teach godot/scripts/player.gd:_update_anim to select it. Names
ending in "-loop" are marked looping and stripped by the Godot importer, so
"walk-loop" here becomes the clip "walk" in-engine. Keep any new clip in the
rigid, big-and-simple style described above.
"""
import sys
import math
import bpy
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, DST = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")

# The source asset has a skeleton but NO skinning (rigid Battlefront-style
# chunks), so bone animation moves nothing. Blender's bone-heat auto-weights
# are nondeterministic and fail on this low-poly chunk mesh, so bind every
# vertex to its two nearest bone segments instead (deterministic, and
# mostly-rigid skinning suits this PS2-era armor model anyway).
# p_mainchunk is a Battlefront destruction/collision chunk (96 verts, ~3 m
# blob) the original node chain kept out of sight — junk once we re-rig.
# Icosphere is stray junk too. The visible body is mesh_part3.
for junk in ("p_mainchunk", "Icosphere"):
    o = bpy.data.objects.get(junk)
    if o:
        bpy.data.objects.remove(o, do_unlink=True)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]

# The asset wraps armature and meshes in rotated empties (DummyRoot etc.),
# so skinning math and node transforms disagree by 90° after export. Flatten
# first: unparent from the empties keeping world transforms, then bake object
# transforms into the data so bone rest space == mesh vertex space == world.
bpy.ops.object.select_all(action="DESELECT")
for o in [arm] + meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# The empties used to stand the model up; without them it would export lying
# sideways. Re-orient using joint POSITIONS (exact, unlike bone tail
# directions which the importer guesses for leaf bones): pelvis->head = up,
# left hand->right hand = side. Target: up=+Z, forward=+Y in Blender, which
# the glTF exporter turns into Godot up=+Y, facing -Z (what main.tscn
# transforms assume). That target frame is the identity basis.
def _bhead(name):
    return arm.data.bones[name].head_local.copy()

up_m = (_bhead("bone_head") - _bhead("bone_pelvis")).normalized()
side_m = (_bhead("bone_r_hand") - _bhead("bone_l_hand")).normalized()
fwd_m = up_m.cross(side_m).normalized()
side_m = fwd_m.cross(up_m)
M = Matrix((side_m, fwd_m, up_m)).transposed()  # columns = measured frame
R = M.inverted().to_4x4()  # target frame = identity (side=+X, fwd=+Y, up=+Z)
for o in [arm] + meshes:
    o.matrix_world = R @ o.matrix_world
bpy.context.view_layer.update()
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

bpy.ops.object.select_all(action="DESELECT")
for m in meshes:
    m.select_set(True)
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.parent_set(type="ARMATURE")  # modifier only, no auto weights


def seg_dist(p, a, b):
    ab = b - a
    t = 0.0 if ab.length_squared == 0 else max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length


# Bone TAILS in this rig are importer-guessed stubs (junk), so build segments
# from joint head -> mean of child joint heads. bone_root is excluded so it
# doesn't steal foot verts (children inherit its bob anyway).
def joint_w(b):
    return arm.matrix_world @ b.head_local


deform_bones = [b for b in arm.data.bones
                if b.name.startswith("bone_") and b.name != "bone_root"]
bone_segs = []
for b in deform_bones:
    a = joint_w(b)
    kids = [c for c in b.children if c.name.startswith("bone_")]
    t = sum((joint_w(c) for c in kids), Vector()) / len(kids) if kids else a
    bone_segs.append((b.name, a, t))

for m in meshes:
    for g in list(m.vertex_groups):
        m.vertex_groups.remove(g)
    groups = {name: m.vertex_groups.new(name=name) for name, _, _ in bone_segs}
    mw = m.matrix_world
    for v in m.data.vertices:
        p = mw @ v.co
        dists = sorted(((seg_dist(p, a, b), name) for name, a, b in bone_segs))
        (d1, n1), (d2, n2) = dists[0], dists[1]
        w1 = 1.0 / (d1 + 1e-4) ** 4
        w2 = 1.0 / (d2 + 1e-4) ** 4
        s = w1 + w2
        groups[n1].add([v.index], w1 / s, "REPLACE")
        groups[n2].add([v.index], w2 / s, "REPLACE")
print("Skinned meshes (nearest-bone):", [m.name for m in meshes])

bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="POSE")

pb = arm.pose.bones
MW = arm.matrix_world


# NOTE: never derive directions from bone TAILS in this rig — they are
# importer-guessed stubs. Joint HEAD positions are the only trustworthy data.


def rotate_world(bone, axis_w, angle_deg, pivot_w=None):
    """Rotate a pose bone about a world-space axis through its head."""
    b = pb[bone]
    piv = pivot_w if pivot_w is not None else (MW @ b.head)
    R = (Matrix.Translation(piv)
         @ Matrix.Rotation(math.radians(angle_deg), 4, axis_w)
         @ Matrix.Translation(-piv))
    b.matrix = MW.inverted() @ R @ MW @ b.matrix
    bpy.context.view_layer.update()


def translate_world(bone, offset_w):
    b = pb[bone]
    m = MW @ b.matrix
    m.translation += offset_w
    b.matrix = MW.inverted() @ m
    bpy.context.view_layer.update()


def key(bones, frame):
    for b in bones:
        pb[b].keyframe_insert("rotation_quaternion", frame=frame)
        pb[b].keyframe_insert("location", frame=frame)


def snapshot():
    return {b.name: b.matrix.copy() for b in pb}


def restore(s):
    for name, m in s.items():
        pb[name].matrix = m
    bpy.context.view_layer.update()


# --- measure the rig in world space ---------------------------------------
# Derive every axis from joint positions (exact) — ALL bone tails in this
# rig are importer-guessed junk, so tail-based directions lie.
UP = ((MW @ pb["bone_head"].head) - (MW @ pb["bone_pelvis"].head)).normalized()
DOWN = -UP
l_arm_dir = ((MW @ pb["bone_l_hand"].head) - (MW @ pb["bone_l_upperarm"].head)).normalized()
r_arm_dir = ((MW @ pb["bone_r_hand"].head) - (MW @ pb["bone_r_upperarm"].head)).normalized()
# axis that swings each arm downward in its own frontal plane
l_axis = l_arm_dir.cross(DOWN).normalized()
r_axis = r_arm_dir.cross(DOWN).normalized()
# left-to-right axis. Sign convention about this axis (right-hand rule):
# down-pointing limbs (thigh / hanging arm) swing FORWARD with +deg;
# up-pointing bones (spine) lean forward with -deg.
side_lr = ((MW @ pb["bone_r_hand"].head) - (MW @ pb["bone_l_hand"].head))
side_lr = (side_lr - side_lr.dot(UP) * UP).normalized()

print("UP:", tuple(round(v, 2) for v in UP),
      "L arm dir:", tuple(round(v, 2) for v in l_arm_dir),
      "R arm dir:", tuple(round(v, 2) for v in r_arm_dir))

# --- base pose: simple upright blaster carry -------------------------------
# Clean and upright — straight legs, no spine lean, no knee/ankle detail. The
# body is a stack of rigid segments; keeping the rest pose plain is what lets
# the big, simple limb swings below read as Minecraft/Krunker locomotion
# instead of a creepy shuffle. Arms come forward and bend at the elbow so the
# hands sit in front of the chest gripping the blaster two-handed.
rotate_world("bone_l_upperarm", l_axis, 48)
rotate_world("bone_r_upperarm", r_axis, 48)
rotate_world("bone_l_upperarm", side_lr, 20)
rotate_world("bone_r_upperarm", side_lr, 20)
rotate_world("bone_l_forearm", side_lr, 66)
rotate_world("bone_r_forearm", side_lr, 72)
rotate_world("bone_l_forearm", UP, -10)
rotate_world("bone_r_forearm", UP, 15)
BASE = snapshot()

arm.animation_data_create()

ALL = ["bone_root", "bone_pelvis", "bone_a_spine", "bone_b_spine",
       "bone_ribcage", "bone_neck", "bone_head",
       "bone_l_clavicle", "bone_l_upperarm", "bone_l_forearm", "bone_l_hand",
       "bone_r_clavicle", "bone_r_upperarm", "bone_r_forearm", "bone_r_hand",
       "bone_l_thigh", "bone_l_calf", "bone_l_foot",
       "bone_r_thigh", "bone_r_calf", "bone_r_foot"]


def add_loop_action(name, poses, frames):
    """poses(t) sets the pose for sample time t in [0, 1); frames are the
    integer keyframe positions (last one == first pose, closing the loop)."""
    act = bpy.data.actions.new(name)
    arm.animation_data.action = act
    n = len(frames) - 1
    for i, frame in enumerate(frames):
        poses((i % n) / n)
        key(ALL, frame)
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(act.name, 1, act)


# --- idle-loop: 3 s gentle bob (24 fps, frames 1..73) ----------------------
# Almost static, like a Minecraft player standing still: a single slow
# up/down bob of the whole body so it isn't a frozen statue. No sway, no
# breathing, no head turn — those all read as creepy on this rigid mesh.
def idle_pose(t):
    phase = t * 2 * math.pi
    restore(BASE)
    translate_world("bone_root", UP * 0.008 * math.sin(phase))


add_loop_action("idle-loop", idle_pose, [1, 10, 19, 28, 37, 46, 55, 64, 73])


# --- walk-loop: 1 s patrol cycle (frames 1..25) -----------------------------
# Basic two-joint gait: the HIP swings the whole leg forward/back, and the
# KNEE flexes just enough to lift the swing foot as it passes under the body.
# Nothing else on the leg moves — the foot/ankle stays rigid, no spine/pelvis.
# s > 0 = right leg forward / left leg back. Arms counter-swing from the
# shoulder (smaller, hands hold the blaster).
def walk_pose(t):
    phase = t * 2 * math.pi
    s = math.sin(phase)
    restore(BASE)
    # hip: whole leg swings as a pole
    rotate_world("bone_l_thigh", side_lr, -32 * s)
    rotate_world("bone_r_thigh", side_lr, 32 * s)
    # knee: subtle flex, peaks at mid-swing (foot clears the ground), zero on
    # contact and through the whole planted stance so the leg reads straight.
    # -cos peaks when the left leg is mid-swing (phase pi); +cos for the right.
    c = math.cos(phase)
    rotate_world("bone_l_calf", side_lr, -22 * max(0.0, -c))
    rotate_world("bone_r_calf", side_lr, -22 * max(0.0, c))
    # arms counter-swing
    rotate_world("bone_l_upperarm", side_lr, 12 * s)
    rotate_world("bone_r_upperarm", side_lr, -12 * s)


add_loop_action("walk-loop", walk_pose, [1, 4, 7, 10, 13, 16, 19, 22, 25])


# --- run-loop: 0.67 s sprint cycle (frames 1..17) ---------------------------
# Same two-joint gait as the walk (hip swing + subtle mid-swing knee flex),
# scaled up (bigger arcs, bigger knee lift) plus one constant tell that reads
# as "running": a slight forward lean of the whole torso. Foot stays rigid.
# The faster cadence comes from player.gd speed_scale.
def run_pose(t):
    phase = t * 2 * math.pi
    s = math.sin(phase)
    c = math.cos(phase)
    restore(BASE)
    rotate_world("bone_a_spine", side_lr, -10)  # lean into the run
    rotate_world("bone_l_thigh", side_lr, -50 * s)
    rotate_world("bone_r_thigh", side_lr, 50 * s)
    rotate_world("bone_l_calf", side_lr, -34 * max(0.0, -c))
    rotate_world("bone_r_calf", side_lr, -34 * max(0.0, c))
    rotate_world("bone_l_upperarm", side_lr, 22 * s)
    rotate_world("bone_r_upperarm", side_lr, -22 * s)


add_loop_action("run-loop", run_pose, [1, 3, 5, 7, 9, 11, 13, 15, 17])

# --- jump: one-shot, single held pose (frames 1..8, no -loop suffix) --------
# Minecraft/Krunker don't animate the jump arc — the legs just snap to a
# simple spread/tuck and hold it for the whole airborne time. Two keyframes:
# ease from BASE into that pose; player.gd holds the last frame until landing
# and there is deliberately NO landing recoil clip (it read as freakish here).
act = bpy.data.actions.new("jump")
arm.animation_data.action = act

restore(BASE)
key(ALL, 1)

restore(BASE)
rotate_world("bone_l_thigh", side_lr, -22)   # lead knee up
rotate_world("bone_r_thigh", side_lr, 14)    # trail leg back — simple spread
rotate_world("bone_l_calf", side_lr, -30)    # lead knee bent under the body
key(ALL, 8)

track = arm.animation_data.nla_tracks.new()
track.name = "jump"
track.strips.new(act.name, 1, act)
arm.animation_data.action = None

# --- export -----------------------------------------------------------------
bpy.ops.object.mode_set(mode="OBJECT")
bpy.ops.export_scene.gltf(
    filepath=DST,
    export_format="GLB",
    export_animations=True,
    export_animation_mode="ACTIONS",
    export_force_sampling=True,
    export_apply=False,
)
print("Exported", DST)
