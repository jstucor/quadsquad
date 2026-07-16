"""Add idle + walk animations to the rigged (but animation-less) trooper GLB.

Run:  blender --background --python animate_trooper.py -- <src.glb> <dst.glb>

Strategy: all rotations are built in WORLD space from the bones' measured rest
directions (arm axis, up axis), then converted into pose-bone space — no
guessing about glTF/Blender axis conventions. Animation names end in "-loop"
so Godot's importer marks them as looping and strips the suffix.
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

# Stray icosphere in the source asset — junk, remove it.
ico = bpy.data.objects.get("Icosphere")
if ico:
    bpy.data.objects.remove(ico, do_unlink=True)

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
# side axis (left-right) for fore/aft leg + arm swings
SIDE = (l_arm_dir - l_arm_dir.dot(UP) * UP).normalized()

print("UP:", tuple(round(v, 2) for v in UP),
      "L arm dir:", tuple(round(v, 2) for v in l_arm_dir),
      "R arm dir:", tuple(round(v, 2) for v in r_arm_dir))

# --- base pose: arms down out of T-pose ------------------------------------
rotate_world("bone_l_upperarm", l_axis, 62)
rotate_world("bone_r_upperarm", r_axis, 62)
rotate_world("bone_l_forearm", l_axis, 12)
rotate_world("bone_r_forearm", r_axis, 12)
BASE = snapshot()

arm.animation_data_create()

ALL = ["bone_root", "bone_pelvis", "bone_a_spine", "bone_b_spine",
       "bone_ribcage", "bone_neck", "bone_head",
       "bone_l_clavicle", "bone_l_upperarm", "bone_l_forearm", "bone_l_hand",
       "bone_r_clavicle", "bone_r_upperarm", "bone_r_forearm", "bone_r_hand",
       "bone_l_thigh", "bone_l_calf", "bone_l_foot",
       "bone_r_thigh", "bone_r_calf", "bone_r_foot"]

# --- idle-loop: 3 s breathing sway (24 fps, frames 1..73) ------------------
act = bpy.data.actions.new("idle-loop")
arm.animation_data.action = act

restore(BASE)
key(ALL, 1)

restore(BASE)
rotate_world("bone_ribcage", SIDE, 2.5)
rotate_world("bone_head", SIDE, -1.5)
rotate_world("bone_l_upperarm", l_axis, 1.5)
rotate_world("bone_r_upperarm", r_axis, 1.5)
translate_world("bone_root", UP * 0.012)
key(ALL, 37)

restore(BASE)
key(ALL, 73)

track = arm.animation_data.nla_tracks.new()
track.name = "idle-loop"
track.strips.new(act.name, 1, act)

# --- walk-loop: 1 s cycle (frames 1..25) -----------------------------------
act = bpy.data.actions.new("walk-loop")
arm.animation_data.action = act


def walk_pose(phase):
    """phase 0: left leg forward; phase pi: right leg forward."""
    restore(BASE)
    s = math.sin(phase)
    c = math.cos(phase)
    rotate_world("bone_l_thigh", SIDE, 27 * s)
    rotate_world("bone_r_thigh", SIDE, -27 * s)
    # trailing knee bends most mid-swing
    rotate_world("bone_l_calf", SIDE, max(0.0, -35 * s) + 8 * abs(c))
    rotate_world("bone_r_calf", SIDE, max(0.0, 35 * s) + 8 * abs(c))
    # arms counter-swing
    rotate_world("bone_l_upperarm", SIDE, -14 * s)
    rotate_world("bone_r_upperarm", SIDE, 14 * s)
    rotate_world("bone_ribcage", SIDE, 3)
    # body bobs twice per cycle, lowest at passing
    translate_world("bone_root", UP * (-0.02 * abs(c)))


for i, frame in enumerate([1, 7, 13, 19, 25]):
    walk_pose(i * math.pi / 2)
    key(ALL, frame)

track = arm.animation_data.nla_tracks.new()
track.name = "walk-loop"
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
