class_name Props
extends RefCounted
## Shared set-dressing builder for the arena maps.
##
## The maps' COVER is built by arena.gd as real colliders; this is everything
## that makes a map read as a place rather than a box of blocks — floodlight
## pylons, pipe runs, braziers, dishes, crates. None of it collides. That is
## deliberate: the cover layout is what the map plays like and it is tuned, so
## decoration must never quietly become a wall you can hide behind. Anything
## meant to be shot around belongs in `cover_boxes`.
##
## Everything goes through `batch()`, which draws N copies of one mesh in a
## single MultiMesh. On the Pi budget every mesh renders 4x plus a shadow pass,
## so a map dressed with fifty individual MeshInstance3Ds would cost more than
## the map itself. One call per prop TYPE, not per prop.

## A plain surface. Metallic stays low by default: a near-black sky reflects
## into metal and renders it pitch dark (see the project Gotchas).
static func material(color: Color, metallic := 0.08, roughness := 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


## A light fixture, molten channel, hologram — anything that should read as its
## own light source. Unshaded so it stays bright on the shadow side, and it
## emits nothing into the scene: real lights cost a pass per viewport, and four
## viewports make that the most expensive thing on the map.
static func glow(color: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


## Draw `xforms.size()` copies of `mesh` as one MultiMesh under `parent`.
static func batch(parent: Node3D, mesh: Mesh, xforms: Array, mat: Material,
		shadows := true) -> MultiMeshInstance3D:
	if xforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = mat
	if not shadows:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	return node


## Upright transforms at a list of ground positions, each with its own yaw, so a
## row of pylons or pipes doesn't read as a stamped-out copy.
static func upright(spots: Array, y: float, rng: RandomNumberGenerator = null) -> Array:
	var out := []
	for s in spots:
		var pos: Vector3 = s
		var yaw := 0.0 if rng == null else rng.randf_range(0.0, TAU)
		out.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, y, pos.z)))
	return out


## The four corners of a rectangle, inset by `inset`. Most maps want their
## floodlights, masts or braziers exactly here.
static func corners(half: Vector2, inset: float) -> Array:
	var x := half.x - inset
	var z := half.y - inset
	return [
		Vector3(-x, 0, -z), Vector3(x, 0, -z),
		Vector3(-x, 0, z), Vector3(x, 0, z),
	]


## A box mesh, the workhorse for slabs, beams, crates and banners.
static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


## A cylinder, for masts, pipes, drums and barrels. `sides` stays low: these are
## background dressing and the silhouette is what reads, not the smoothness.
static func cyl(radius: float, height: float, sides := 8, top := -1.0) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius if top < 0.0 else top
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = sides
	m.rings = 1
	return m


## A low-poly sphere, for brazier flames, snow drifts and lamp heads.
static func ball(radius: float, sides := 8) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = sides
	m.rings = maxi(sides / 2, 3)
	return m
