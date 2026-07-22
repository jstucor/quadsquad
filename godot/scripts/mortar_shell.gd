extends Node3D
## A mortar round: a real ballistic projectile, unlike the RPG's flat rocket.
##
## The launch velocity is SOLVED, not tuned — given where it starts, where it
## must land and how long it should hang, there is exactly one arc, so a salvo
## lands where the map cursor was regardless of range. It ray-checks each step
## and detonates on the first thing it touches, so a shell that clips a roof on
## the way in blows up on the roof rather than tunnelling through it.

const MIN_FLIGHT := 1.4   # seconds; a short lob still arcs
const MAX_FLIGHT := 4.0
const FLIGHT_PER_M := 1.0 / 26.0

var _vel := Vector3.ZERO
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _shooter: Node          # for kill attribution
var _shooter_rid: RID
var _splash := 4.2
var _splash_damage := 68.0
var _life := 0.0


func launch(from: Vector3, target: Vector3, shooter: Node,
		splash: float, splash_damage: float) -> void:
	global_position = from
	_shooter = shooter
	_shooter_rid = shooter.get_rid() if shooter is CollisionObject3D else RID()
	_splash = splash
	_splash_damage = splash_damage
	# Hang time grows with range, so a long shot arcs high and a close one lobs.
	var flight := clampf(from.distance_to(target) * FLIGHT_PER_M, MIN_FLIGHT, MAX_FLIGHT)
	# Solve p(t) = from + v*t - 0.5*g*t^2 for v such that p(flight) == target.
	_vel = (target - from) / flight + Vector3.UP * 0.5 * _gravity * flight
	_build_mesh()


func _build_mesh() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.14, 0.16)
	mat.metallic = 0.0
	mat.roughness = 0.6
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.075
	cap.height = 0.34
	body.mesh = cap
	body.material_override = mat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)
	# A hot tail, so a salvo arcing overhead is something you can see coming.
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.6, 0.2)
	glow.emission_energy_multiplier = 4.0
	var spark := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.05
	s.height = 0.10
	spark.mesh = s
	spark.material_override = glow
	spark.position = Vector3(0, -0.2, 0)
	spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(spark)


func _physics_process(delta: float) -> void:
	_life += delta
	if _life > 12.0:
		queue_free()  # never found anything (fired off the edge of the level)
		return
	_vel.y -= _gravity * delta
	var from := global_position
	var to := from + _vel * delta
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if _shooter_rid.is_valid():
		query.exclude = [_shooter_rid]  # don't detonate on our own tube
	query.collision_mask = 0b11  # world (1) + bodies (2)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		_explode(hit["position"])
		return
	global_position = to
	# Point the shell along its arc, so it noses over at the top.
	if _vel.length_squared() > 0.01:
		look_at(to + _vel, Vector3.UP)
		rotation.x += PI / 2.0  # the capsule stands along +Y


func _explode(pos: Vector3) -> void:
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
		# Credited to the player who placed the mortar, not to the tube, so the
		# frag lands on the person who called the strike.
		col.take_damage(_splash_damage * falloff, _attributed_to())
	_spawn_blast(pos)
	queue_free()


## Kills go to whoever owns the mortar; if they have since left, the tube itself
## takes the credit so team scoring still works.
func _attributed_to() -> Node:
	if is_instance_valid(_shooter) and "owner_player" in _shooter \
			and is_instance_valid(_shooter.owner_player):
		return _shooter.owner_player
	return _shooter


func _spawn_blast(pos: Vector3) -> void:
	var flash := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = _splash * 0.7
	s.height = _splash * 1.4
	flash.mesh = s
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.6, 0.25, 0.75)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.18)
	mat.emission_energy_multiplier = 6.0
	flash.material_override = mat
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Added first, positioned after: global_position on a node outside the tree
	# is silently treated as local.
	get_tree().current_scene.add_child(flash)
	flash.global_position = pos
	get_tree().create_timer(0.22).timeout.connect(flash.queue_free)
