class_name Foliage
extends RefCounted
## Shared jungle tree builder, used by every outdoor map.
##
## A forest is two MultiMeshes (trunks and canopies) plus one StaticBody holding
## a capsule per trunk, so the whole thing costs two draw calls per viewport
## instead of one per tree — which matters when every mesh renders 4x plus a
## shadow pass. Canopies have no collision, so you can walk under them.

const TRUNK_HEIGHT := 8.0
const TRUNK_RADIUS := 0.34
const CANOPY_RADIUS := 2.6


## Grow a forest at `spots` (positions on the ground) under `parent`. `rng` is
## passed in so the caller owns the seed and its map stays identical every match.
static func grow(parent: Node3D, spots: Array, rng: RandomNumberGenerator) -> void:
	if spots.is_empty():
		return
	var trunks := _multimesh(_trunk_mesh(), spots.size())
	# Trunks skip the shadow pass: the canopies above already cast the shade.
	trunks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var canopies := _multimesh(_canopy_mesh(), spots.size())
	parent.add_child(trunks)
	parent.add_child(canopies)

	var body := StaticBody3D.new()
	parent.add_child(body)

	for i in spots.size():
		var pos: Vector3 = spots[i]
		var height_scale := rng.randf_range(0.8, 1.35)
		var lean := Basis(Vector3.FORWARD, rng.randf_range(-0.05, 0.05)) \
			* Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		trunks.multimesh.set_instance_transform(i,
			Transform3D(lean.scaled(Vector3(1.0, height_scale, 1.0)), pos))
		var canopy_scale := height_scale * rng.randf_range(0.85, 1.2)
		canopies.multimesh.set_instance_transform(i, Transform3D(
			Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * canopy_scale),
			pos + Vector3.UP * TRUNK_HEIGHT * height_scale))
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = TRUNK_RADIUS
		cyl.height = TRUNK_HEIGHT * height_scale
		shape.shape = cyl
		shape.position = pos + Vector3.UP * TRUNK_HEIGHT * height_scale * 0.5
		body.add_child(shape)


static func _multimesh(mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	return mmi


static func _trunk_mesh() -> Mesh:
	var cyl := CylinderMesh.new()
	cyl.top_radius = TRUNK_RADIUS * 0.72
	cyl.bottom_radius = TRUNK_RADIUS * 1.25
	cyl.height = TRUNK_HEIGHT
	cyl.radial_segments = 6  # blocky, to match the character art
	cyl.rings = 1
	# Shift it so instance origins sit on the ground and scaling grows it upward.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(cyl, 0, Transform3D(Basis(), Vector3(0, TRUNK_HEIGHT * 0.5, 0)))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.26, 0.19, 0.13)
	mat.metallic = 0.0
	mat.roughness = 0.9
	st.set_material(mat)
	return st.commit()


static func _canopy_mesh() -> Mesh:
	var sphere := SphereMesh.new()
	sphere.radius = CANOPY_RADIUS
	sphere.height = CANOPY_RADIUS * 1.5  # squashed: a broad jungle crown
	sphere.radial_segments = 7
	sphere.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.14, 0.30, 0.13)
	mat.metallic = 0.0
	mat.roughness = 0.95
	sphere.material = mat
	return sphere
