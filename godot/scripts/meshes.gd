class_name Meshes
extends RefCounted
## Shared procedural mesh builders, with a cache.
##
## Everything in this game is made of boxes, and a box has razor edges: every
## face catches the light at exactly one angle across its whole area, so the
## whole object reads as flat-shaded cardboard however good the material is. A
## CHAMFER fixes that — a narrow bevel round every edge picks up a highlight
## along the silhouette, which is what makes a solid read as solid.
##
## This was deliberately NOT done while the Raspberry Pi was a target: a chamfered
## box is 44 triangles against a box's 12, and a character carries about forty of
## them, four viewports deep, plus a shadow pass. With that target dropped the
## trade is worth taking — and the cache below means the cost is triangles, not
## resources: a character's two arms, two legs and paired armour plates all share
## one mesh each.
##
## `rim` on the materials is still there and still doing work; the two are
## complementary. Rim brightens a face as it turns away from the camera, the
## chamfer puts an actual lit edge on the silhouette.

## Chamfer as a fraction of the box's SMALLEST dimension, so a limb and a helmet
## get proportionally similar edges and nothing ever chamfers itself inside out.
const CHAMFER_FRAC := 0.16
const CHAMFER_MAX := 0.035   # metres; past this a bevel reads as a bevel, not an edge

## Cache key is the box size quantised to a millimetre. Sizes repeat heavily
## inside one model (both arms, both legs, every knee pad), and identically
## across the twelve bodies on a map.
static var _boxes := {}


## A box with every edge chamfered. Same size and centre as a BoxMesh would be,
## so it is a drop-in replacement.
static func chamfer_box(size: Vector3) -> ArrayMesh:
	var key := "%d_%d_%d" % [roundi(size.x * 1000.0), roundi(size.y * 1000.0),
		roundi(size.z * 1000.0)]
	if _boxes.has(key):
		return _boxes[key]
	var c: float = minf(minf(size.x, minf(size.y, size.z)) * CHAMFER_FRAC, CHAMFER_MAX)
	var mesh := _build_chamfer(size, c)
	_boxes[key] = mesh
	return mesh


## Built as a scaled CUBE of 26 vertices: the 8 corners pulled in by the chamfer
## on all three axes, giving 6 face quads, 12 edge quads and 8 corner triangles.
## Flat-shaded on purpose — smoothing the chamfer would round the silhouette off
## and lose exactly the crisp highlight it is there to create.
static func _build_chamfer(size: Vector3, c: float) -> ArrayMesh:
	var h := size * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Inner half-extents: how far the flat part of each face reaches.
	var i := Vector3(h.x - c, h.y - c, h.z - c)
	# The eight corner points, each offset inward on all three axes.
	var signs := [-1.0, 1.0]
	# Six faces, each a quad inset by the chamfer.
	for axis in 3:
		for s: float in signs:
			var n := Vector3.ZERO
			n[axis] = s
			var u := Vector3.ZERO
			var v := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			v[(axis + 2) % 3] = 1.0
			var centre := n * h[axis]
			var eu: float = i[(axis + 1) % 3]
			var ev: float = i[(axis + 2) % 3]
			var a := centre + u * eu + v * ev
			var b := centre - u * eu + v * ev
			var d := centre - u * eu - v * ev
			var e := centre + u * eu - v * ev
			if s > 0.0:
				_tri(st, n, a, b, d)
				_tri(st, n, a, d, e)
			else:
				_tri(st, n, a, d, b)
				_tri(st, n, a, e, d)
	# Twelve edge quads and eight corner triangles, built from the corner cloud.
	# Each corner of the cube contributes three points (one pulled in on each
	# pair of axes); the hull between them is the bevel.
	for sx: float in signs:
		for sy: float in signs:
			for sz: float in signs:
				var px := Vector3(sx * h.x, sy * i.y, sz * i.z)
				var py := Vector3(sx * i.x, sy * h.y, sz * i.z)
				var pz := Vector3(sx * i.x, sy * i.y, sz * h.z)
				var n := Vector3(sx, sy, sz).normalized()
				# Winding flips with the parity of the corner's octant.
				if sx * sy * sz > 0.0:
					_tri(st, n, px, py, pz)
				else:
					_tri(st, n, px, pz, py)
	# The edge strips: between each pair of adjacent corners along an axis.
	for axis in 3:
		var a1 := (axis + 1) % 3
		var a2 := (axis + 2) % 3
		for s1: float in signs:
			for s2: float in signs:
				var lo := Vector3.ZERO
				var hi := Vector3.ZERO
				lo[axis] = -i[axis]
				hi[axis] = i[axis]
				var p1 := lo
				var p2 := hi
				p1[a1] = s1 * h[a1]
				p1[a2] = s2 * i[a2]
				p2[a1] = s1 * h[a1]
				p2[a2] = s2 * i[a2]
				var q1 := lo
				var q2 := hi
				q1[a1] = s1 * i[a1]
				q1[a2] = s2 * h[a2]
				q2[a1] = s1 * i[a1]
				q2[a2] = s2 * h[a2]
				var n := Vector3.ZERO
				n[a1] = s1
				n[a2] = s2
				n = n.normalized()
				# Winding flips with the sign product: walking p1→p2→q2→q1 is
				# outward only when s1 and s2 disagree. Getting this backwards
				# does NOT show up as a hole — the strip is still there, it just
				# faces inward, so it subtracts from the solid instead of adding.
				# Invisible by eye, obvious in the signed volume; see tests/chamfer.gd.
				if s1 * s2 > 0.0:
					_tri(st, n, p1, q1, q2)
					_tri(st, n, p1, q2, p2)
				else:
					_tri(st, n, p1, p2, q2)
					_tri(st, n, p1, q2, q1)
	st.index()
	return st.commit()


## THE WINDING IS GODOT'S, AND IT IS THE OPPOSITE OF THE OBVIOUS ONE.
##
## This whole mesh was built wound the wrong way round, and because every box in
## the game comes through here, EVERY model in the game was inside out: the
## characters, the guns, the corpses, the cover, the vehicles, the deployables.
## With back faces culled that does not look like a winding bug — it looks like
## the models are TRANSPARENT (you see through the near face into the far one's
## interior) and like the lighting is broken (those interior faces carry outward
## normals, so they are lit as though facing away, and the whole model goes flat
## and ambient-only). It is the single most expensive class of bug this project
## has had and this is the second time it has bitten: the planet terrain cost a
## session to the same mistake.
##
## Godot's front face is the CLOCKWISE one, so for correctly-wound geometry
## `cross(b - a, c - a)` points INWARD and a closed solid's signed volume through
## `a · (b × c) / 6` comes out NEGATIVE. Every engine primitive (BoxMesh,
## SphereMesh, CylinderMesh, PrismMesh, QuadMesh) measures that way, and they are
## the authority — `tests/chamfer.gd` now asserts against a real BoxMesh rather
## than against a sign somebody had to remember, which is what let this through:
## the old test demanded a POSITIVE volume, so the mesh passed a check that was
## itself the wrong way round.
##
## The vertices are emitted a, c, b for that reason. The callers above still name
## their triangles in the readable order.
static func _tri(st: SurfaceTool, n: Vector3, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v: Vector3 in [a, c, b]:
		st.set_normal(n)
		st.add_vertex(v)
