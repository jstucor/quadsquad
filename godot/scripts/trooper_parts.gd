class_name TrooperParts
extends RefCounted
## Cuts the trooper GLB into one rigid piece per joint of CharacterModel's rig.
##
## The model is NOT skinned — its three meshes carry only position/normal/uv and
## the 23-bone skeleton in the file is decorative, so there are no weights to
## deform with. That turns out to be exactly right for this game: the character
## has always been rigid parts on clean Node3D joints, so the trooper is chopped
## into the same parts and hung on the same joints. Nothing about the animation
## changes — the clips are pure joint rotations and they drive these pieces
## identically to the boxes they replace.
##
## Segmentation is by nearest BONE SEGMENT, not nearest bone. Nearest-bone puts
## the outer half of an upper arm on the forearm, because the midpoint between
## two joints is the boundary; measuring to the segment between them puts the
## split at the elbow where it belongs.
##
## Cut once and cached: every character in the match shares these meshes.

const MODEL := preload("res://assets/models/rep/p3_heavyglb.glb")
## The model stands 2.055 units tall; the game's character is 1.82 m to the top
## of the head, and gameplay (capsule height, head-shot band, camera height) is
## built around that, so the trooper is scaled to fit rather than the reverse.
const SCALE := 1.82 / 2.055
## A stray placeholder chunk parked off in space, not part of the body.
const JUNK_MESH := "p_mainchunk"
## Cutting a continuous mesh into rigid parts leaves BRIDGING triangles: ones
## spanning from the shoulder pad out onto the arm. Whichever part claims them,
## the far end reaches toward geometry that has since rotated away, and they
## read as spikes shooting out of the shoulders.
##
## Only the ARM/torso boundary tears, because the arms are the only parts turned
## a quarter turn — a bridge across a knee just stretches a little. So the rule
## is precise: drop a triangle whose vertices straddle an arm and something that
## is not that arm. Filtering by edge length instead looks tempting and is
## wrong — this model is low-poly enough that real body triangles are as long as
## the bridges, and at 0.13 it deleted most of the legs.
const ARM_KEYS := ["sL", "sR", "eL", "eR"]

# Bone rest positions read out of the GLB, in model space (metres, Y up).
const B_PELVIS := Vector3(0.0, 1.159, 0.0)
const B_SPINE := Vector3(0.0, 1.322, 0.014)
const B_RIBCAGE := Vector3(0.0, 1.481, 0.023)
const B_NECK := Vector3(0.0, 1.716, 0.018)
const B_HEAD := Vector3(0.0, 1.844, -0.013)
const B_CROWN := Vector3(0.0, 2.055, -0.013)
const B_UPPERARM := Vector3(0.229, 1.649, 0.045)
const B_FOREARM := Vector3(0.462, 1.638, 0.100)
const B_HAND := Vector3(0.754, 1.624, 0.017)
const B_FINGERS := Vector3(0.960, 1.624, 0.017)
const B_THIGH := Vector3(0.094, 1.054, -0.009)
const B_CALF := Vector3(0.169, 0.581, -0.024)
const B_FOOT := Vector3(0.240, 0.128, 0.083)
const B_TOE := Vector3(0.255, 0.000, -0.051)

## Where each joint's piece pivots, in model space. These are the bones our rig's
## joints correspond to, and every piece is re-centred on its own pivot so it
## hangs correctly off the matching Node3D.
const PIVOTS := {
	"hips": B_PELVIS, "spine": B_PELVIS,   # our spine bends at the waist
	"head": B_NECK,
	"sL": Vector3(-0.229, 1.649, 0.045), "eL": Vector3(-0.462, 1.638, 0.100),
	"sR": B_UPPERARM, "eR": B_FOREARM,
	"hL": Vector3(-0.094, 1.054, -0.009), "kL": Vector3(-0.169, 0.581, -0.024),
	"hR": B_THIGH, "kR": B_CALF,
}


## Segment the body: [from, to, joint]. Distances are measured to the segment,
## so a limb splits at its joint rather than halfway along the bone.
static func _segments() -> Array:
	var out := [
		[B_PELVIS, B_SPINE, "hips"],
		[B_SPINE, B_RIBCAGE, "spine"],
		[B_RIBCAGE, B_NECK, "spine"],
		[B_NECK, B_HEAD, "head"],
		[B_HEAD, B_CROWN, "head"],
	]
	# Arms and legs, mirrored. The model's left is -X, and so is the rig's.
	for side in [-1.0, 1.0]:
		var s := "L" if side < 0.0 else "R"
		# The clavicle run belongs to the TORSO, not the arm. Without it the
		# shoulder pad is claimed by the upper arm, and since only the arm gets
		# the quarter turn, half a pauldron swings down with the limb and tears
		# into spikes at the shoulder.
		out.append([B_NECK, _m(B_UPPERARM, side), "spine"])
		out.append([_m(B_UPPERARM, side), _m(B_FOREARM, side), "s" + s])
		out.append([_m(B_FOREARM, side), _m(B_HAND, side), "e" + s])
		out.append([_m(B_HAND, side), _m(B_FINGERS, side), "e" + s])
		out.append([_m(B_THIGH, side), _m(B_CALF, side), "h" + s])
		out.append([_m(B_CALF, side), _m(B_FOOT, side), "k" + s])
		out.append([_m(B_FOOT, side), _m(B_TOE, side), "k" + s])
	return out


static func _m(v: Vector3, side: float) -> Vector3:
	return Vector3(v.x * side, v.y, v.z)


## The rig hangs its arms DOWN; the model is in a T-pose with them straight out.
## Each arm piece is turned a quarter turn so its geometry runs down the joint's
## -Y, which is where the animation expects the limb to lie. The turn is baked
## into the MESH, never into the joint: rotating the joint would rotate the axis
## the clips animate about and change every arm motion.
static func _correction(joint: String) -> Basis:
	match joint:
		"sL", "eL":
			return Basis(Vector3.BACK, PI * 0.5)
		"sR", "eR":
			return Basis(Vector3.BACK, -PI * 0.5)
	return Basis()


## Where each joint sits RELATIVE TO ITS PARENT joint, straight off the bone
## table. The rig has to use these rather than nominal vertical limb lengths:
## the trooper's bones run diagonally (the thigh kicks outward, the forearm
## forward), so hanging a piece on a purely vertical rig leaves it offset from
## where its geometry actually belongs, and the seam tears into spikes.
##
## Arm offsets get the same quarter turn as the arm meshes, so the joint and the
## geometry it carries stay in step.
static func joint_offsets() -> Dictionary:
	var s := SCALE
	var out := {}
	out["head"] = (B_NECK - B_PELVIS) * s          # Head hangs off Spine
	for side in [-1.0, 1.0]:
		var sn := "L" if side < 0.0 else "R"
		var upper := _m(B_UPPERARM, side)
		var fore := _m(B_FOREARM, side)
		out["s" + sn] = (upper - B_PELVIS) * s     # Shoulder hangs off Spine
		out["e" + sn] = _correction("s" + sn) * ((fore - upper) * s)
		var thigh := _m(B_THIGH, side)
		var calf := _m(B_CALF, side)
		out["h" + sn] = (thigh - B_PELVIS) * s     # Hip hangs off Hips
		out["k" + sn] = (calf - thigh) * s
	return out


static var _cache: Dictionary = {}


## joint key -> ArrayMesh, in that joint's local space, scaled and corrected.
## Built on the first call and shared by every character after that.
static func meshes() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var segments := _segments()
	var buckets := {}   # joint -> {verts, norms, uvs}
	for key in PIVOTS:
		buckets[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(),
			"u": PackedVector2Array()}

	var model: Node3D = MODEL.instantiate()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if mi.name.begins_with(JUNK_MESH):
			continue
		_slice(mi, segments, buckets)
	model.free()

	for key in buckets:
		var b: Dictionary = buckets[key]
		if b["v"].is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = b["v"]
		arrays[Mesh.ARRAY_NORMAL] = b["n"]
		arrays[Mesh.ARRAY_TEX_UV] = b["u"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_cache[key] = mesh
	return _cache


## Walk one source mesh triangle by triangle, dropping each into the bucket of
## whichever bone segment its centroid is closest to.
static func _slice(mi: MeshInstance3D, segments: Array, buckets: Dictionary) -> void:
	var mesh: Mesh = mi.mesh
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var count: int = idx.size() if idx.size() > 0 else verts.size()
		var tri := 0
		while tri + 2 < count:
			var i0: int = idx[tri] if idx.size() > 0 else tri
			var i1: int = idx[tri + 1] if idx.size() > 0 else tri + 1
			var i2: int = idx[tri + 2] if idx.size() > 0 else tri + 2
			tri += 3
			var a: Vector3 = verts[i0]
			var b: Vector3 = verts[i1]
			var c: Vector3 = verts[i2]
			var key: String = _nearest((a + b + c) / 3.0, segments)
			if _bridges_an_arm(a, b, c, segments):
				continue  # spans a limb that rotates away; keeping it makes a spike
			var bucket: Dictionary = buckets[key]
			var pivot: Vector3 = PIVOTS[key]
			var fix: Basis = _correction(key)
			for i in [i0, i1, i2]:
				bucket["v"].append(fix * ((verts[i] - pivot) * SCALE))
				bucket["n"].append(fix * (norms[i] if i < norms.size() else Vector3.UP))
				bucket["u"].append(uvs[i] if i < uvs.size() else Vector2.ZERO)


## True when a triangle's corners do not all agree about which arm they are on —
## either one corner is on an arm and another is not, or they are on different
## arms. Those are the only bridges that visibly tear.
static func _bridges_an_arm(a: Vector3, b: Vector3, c: Vector3, segments: Array) -> bool:
	var ka := _arm_of(a, segments)
	var kb := _arm_of(b, segments)
	var kc := _arm_of(c, segments)
	return not (ka == kb and kb == kc)


## Which arm a point belongs to ("" for anything that is not an arm). Both the
## upper and lower arm of a side answer the same, so an elbow seam is allowed to
## bridge — that joint bends in the plane the geometry already lies in.
static func _arm_of(point: Vector3, segments: Array) -> String:
	var key := _nearest(point, segments)
	if not ARM_KEYS.has(key):
		return ""
	return key.substr(1)  # "sL"/"eL" -> "L"


static func _nearest(point: Vector3, segments: Array) -> String:
	var best: String = "spine"
	var best_gap := INF
	for seg in segments:
		var gap := _gap_to_segment(point, seg[0], seg[1])
		if gap < best_gap:
			best_gap = gap
			best = seg[2]
	return best


static func _gap_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)
