extends Node3D
## RPG rocket: unlike the hitscan blasters, this is a real travelling
## projectile. It flies forward, ray-checks each step for a world/player hit,
## and on impact (or max range) deals splash damage to every character in a
## radius with linear falloff. Launched by weapon.gd for the RPG class.

const SPEED := 48.0

var _dir := Vector3.FORWARD
var _shooter_rid: RID
var _shooter: CollisionObject3D  # for kill attribution
var _splash := 4.5
var _splash_damage := 90.0
var _range := 300.0
var _traveled := 0.0


func launch(from: Vector3, dir: Vector3, shooter: CollisionObject3D,
		splash: float, splash_damage: float, rng: float) -> void:
	global_position = from
	_dir = dir.normalized()
	if absf(_dir.dot(Vector3.UP)) < 0.99:
		look_at(from + _dir)  # body mesh lies along -Z
	_shooter_rid = shooter.get_rid()
	_shooter = shooter
	_splash = splash
	_splash_damage = splash_damage
	_range = rng
	_build_mesh()


func _build_mesh() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.17)
	mat.metallic = 0.0
	mat.roughness = 0.6
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.07
	cyl.height = 0.42
	body.mesh = cyl
	body.rotation.x = PI / 2.0  # lay along -Z
	body.material_override = mat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)
	# glowing exhaust so you can see it fly
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.5, 0.15)
	glow.emission_energy_multiplier = 5.0
	var flame := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.06
	s.height = 0.12
	flame.mesh = s
	flame.material_override = glow
	flame.position = Vector3(0, 0, 0.24)  # rear
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flame)


func _physics_process(delta: float) -> void:
	var step := SPEED * delta
	var from := global_position
	var to := from + _dir * step
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_shooter_rid]
	query.collision_mask = 0b11  # world (1) + players (2)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		_explode(hit["position"])
		return
	global_position = to
	_traveled += step
	if _traveled >= _range:
		_explode(global_position)


func _explode(pos: Vector3) -> void:
	Audio.play_at("explosion", pos)
	var shape := SphereShape3D.new()
	shape.radius = _splash
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), pos)
	params.collision_mask = 0b10  # players layer
	var results := get_world_3d().direct_space_state.intersect_shape(params, 16)
	var hit_once := {}
	for r in results:
		var col = r.get("collider")
		if col == null or hit_once.has(col) or not col.has_method("take_damage"):
			continue
		hit_once[col] = true
		var dist: float = col.global_position.distance_to(pos)
		var falloff := clampf(1.0 - dist / _splash, 0.2, 1.0)
		col.take_damage(_splash_damage * falloff, _shooter)
	_spawn_blast(pos)
	queue_free()


func _spawn_blast(pos: Vector3) -> void:
	Blast.pop(get_tree().current_scene, pos, _splash, 0.6)
