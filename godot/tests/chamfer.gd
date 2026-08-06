extends SceneTree
## Proves `Meshes.chamfer_box` is a CLOSED, OUTWARD-FACING solid of the right size.
##
## Written because inverted winding is the single most expensive bug this project
## has had: the planet terrain rendered near-black for an entire session and the
## cause was a flipped triangle order, with no error anywhere. A procedural mesh
## that is wrong in that way looks like a LIGHTING problem, so it sends you off
## tuning materials and sun angles for hours. Never ship a generated mesh without
## a signed-volume check.
##
## AND THE SIGN IS TAKEN FROM THE ENGINE, NOT FROM MEMORY. This test used to
## demand a POSITIVE signed volume, which is the wrong way round for Godot — so
## the chamfer box was inside out, it passed a check that was itself inverted,
## and since every box in the game comes from here, every model in the game was
## inside out for as long as that stood. It reads like transparency and like
## broken lighting, never like a winding bug. So the reference is now a real
## `BoxMesh`: whatever convention the engine's own primitives use is the one
## every generated mesh has to match, and nobody has to remember which it is.
##
## Run: godot --headless --path godot --script tests/chamfer.gd

func _init() -> void:
	var fails := 0
	# The engine's own box, measured the same way, is the reference.
	var reference := BoxMesh.new()
	reference.size = Vector3.ONE
	var want := signf(_volume(reference))
	print("engine BoxMesh signed volume is %s — that is the convention"
		% ("NEGATIVE" if want < 0.0 else "POSITIVE"))
	# A cube, a limb-shaped sliver and a wide plate: the three proportions the
	# rig actually asks for, including one where the chamfer is clamped.
	for size: Vector3 in [Vector3(0.3, 0.3, 0.3), Vector3(0.085, 0.42, 0.085),
			Vector3(0.44, 0.06, 0.28), Vector3(1.0, 1.0, 1.0)]:
		fails += _check(size, want)
	print("chamfer: ", "OK" if fails == 0 else "%d FAILURE(S)" % fails)
	quit(1 if fails > 0 else 0)


## The signed volume of a whole mesh, by the divergence theorem.
func _volume(mesh: Mesh) -> float:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var count := idx.size() if not idx.is_empty() else verts.size()
	var vol := 0.0
	var t := 0
	while t + 2 < count:
		var a := verts[idx[t]] if not idx.is_empty() else verts[t]
		var b := verts[idx[t + 1]] if not idx.is_empty() else verts[t + 1]
		var c := verts[idx[t + 2]] if not idx.is_empty() else verts[t + 2]
		vol += a.dot(b.cross(c)) / 6.0
		t += 3
	return vol


func _check(size: Vector3, want: float) -> int:
	var mesh := Meshes.chamfer_box(size)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var bad := 0
	var tris := idx.size() / 3

	# 1. SIGNED VOLUME via the divergence theorem, and it must have THE ENGINE'S
	#    OWN SIGN. The magnitude is the solid's volume either way; the sign is
	#    which way every triangle faces, and getting it backwards is an inside-out
	#    model that renders as a transparent one.
	var vol := 0.0
	for t in tris:
		var a := verts[idx[t * 3]]
		var b := verts[idx[t * 3 + 1]]
		var c := verts[idx[t * 3 + 2]]
		vol += a.dot(b.cross(c)) / 6.0
	var wound_right := signf(vol) == want

	# 2. Every normal must point AWAY from the centre. Catches a face that is
	#    wound right but normalled wrong, which shades black under any light.
	for i in verts.size():
		if norms[i].dot(verts[i]) <= 0.0:
			bad += 1

	# 3. The chamfer must not eat the box: volume within 12% of the true box.
	var box_vol := size.x * size.y * size.z
	var ratio := absf(vol) / box_vol

	# 4. Extents unchanged, so it is a drop-in for BoxMesh and nothing shifts.
	var ext := Vector3.ZERO
	for v in verts:
		ext = Vector3(maxf(ext.x, absf(v.x)), maxf(ext.y, absf(v.y)), maxf(ext.z, absf(v.z)))
	var ext_ok := ext.is_equal_approx(size * 0.5)

	var ok := wound_right and bad == 0 and ratio > 0.88 and ratio <= 1.0 and ext_ok
	print("  %-22s tris=%-4d vol=%.3f%% of box  winding=%-8s outward=%s  extents=%s  %s" % [
		str(size), tris, ratio * 100.0, "engine" if wound_right else "INVERTED",
		"yes" if bad == 0 else "NO (%d)" % bad,
		"yes" if ext_ok else "NO " + str(ext), "ok" if ok else "FAIL"])
	return 0 if ok else 1
