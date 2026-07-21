extends RigidBody3D
## Thrown grenade: a real physics body so it bounces off cover and rolls, unlike
## the RPG's straight-flying rocket. Detonates on a fuse (not on contact), then
## deals the same radius splash with linear falloff the rocket uses.
##
## Collides with the world only (layer 1), never with players — a live grenade
## that blocked bodies would be a shield, and it lets you toss one past a
## teammate without it bouncing off them.

const FUSE := 2.0
const SPLASH := 5.0
const SPLASH_DAMAGE := 110.0
const BLAST_TIME := 0.18  # how long the explosion flash lingers

var _thrower: CollisionObject3D  # for kill attribution
var _fuse_left := FUSE
var _spent := false


func launch(from: Vector3, impulse: Vector3, thrower: CollisionObject3D) -> void:
	global_position = from
	_thrower = thrower
	collision_layer = 0  # nothing collides *with* the grenade
	collision_mask = 1   # ...but it bounces off world geometry
	linear_velocity = impulse
	angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	_build_mesh()


func _build_mesh() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.11
	shape.shape = sphere
	add_child(shape)

	var mesh := MeshInstance3D.new()
	var body := SphereMesh.new()
	body.radius = 0.11
	body.height = 0.22
	body.radial_segments = 8
	body.rings = 4
	mesh.mesh = body
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.22, 0.16)
	mat.metallic = 0.1  # keep low: a dark sky reflects into metal (Gotchas)
	mat.roughness = 0.7
	mat.emission_enabled = true  # blinking arming light, so it reads as live
	mat.emission = Color(1.0, 0.3, 0.15)
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


func _physics_process(delta: float) -> void:
	if _spent:
		return
	_fuse_left -= delta
	if _fuse_left <= 0.0:
		_explode()


func _explode() -> void:
	_spent = true
	var pos := global_position
	var shape := SphereShape3D.new()
	shape.radius = SPLASH
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), pos)
	params.collision_mask = 0b10  # players layer
	var hit_once := {}
	for r in get_world_3d().direct_space_state.intersect_shape(params, 16):
		var col = r.get("collider")
		if col == null or hit_once.has(col) or not col.has_method("take_damage"):
			continue
		hit_once[col] = true
		var falloff := clampf(1.0 - col.global_position.distance_to(pos) / SPLASH, 0.2, 1.0)
		col.take_damage(SPLASH_DAMAGE * falloff, _thrower)
	_spawn_blast(pos)
	queue_free()


func _spawn_blast(pos: Vector3) -> void:
	var flash := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = SPLASH * 0.55
	ball.height = SPLASH * 1.1
	flash.mesh = ball
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.6, 0.25, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.18)
	mat.emission_energy_multiplier = 6.0
	flash.material_override = mat
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Placed after add_child: global_position on a node outside the tree is
	# silently treated as local and errors.
	get_tree().current_scene.add_child(flash)
	flash.global_position = pos
	get_tree().create_timer(BLAST_TIME).timeout.connect(flash.queue_free)
