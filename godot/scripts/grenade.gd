extends RigidBody3D
## Thrown grenade: a real physics body so it bounces off cover and rolls, unlike
## the RPG's straight-flying rocket. One class covers all three types the buy
## screen sells, because they differ only in what happens when the fuse runs out
## and in whether they bounce:
##
##   FRAG   - bounces off world geometry, then splash damage.
##   STICKY - collides with BODIES too and freezes on whatever it touches,
##            riding along if that was a person, then splash damage.
##   SMOKE  - bounces like a frag, then leaves a sight-blocking cloud and deals
##            no damage at all.
##
## A frag collides with the world only (layer 1), never with players — a live
## grenade that blocked bodies would be a shield, and it lets you toss one past
## a teammate without it bouncing off them. A sticky deliberately gives that up:
## sticking to people is the whole point of it.

const FUSE := 2.0
const STICKY_FUSE := 2.6   # a beat longer, since it stops dead where it lands
const SPLASH := 5.0
const SPLASH_DAMAGE := 110.0
const STICKY_SPLASH := 4.2       # tighter than a frag...
const STICKY_SPLASH_DAMAGE := 135.0  # ...but it lands on the target, so it hurts
const BLAST_TIME := 0.18  # how long the explosion flash lingers
const SMOKE_SCENE := preload("res://scenes/fx/smoke_cloud.tscn")

var _thrower: CollisionObject3D  # for kill attribution
var _fuse_left := FUSE
var _spent := false
var _type := Loadout.GrenadeType.FRAG
var _stuck_to: Node3D      # body a sticky attached to, if any
var _stuck_offset := Vector3.ZERO


func launch(from: Vector3, impulse: Vector3, thrower: CollisionObject3D,
		type := Loadout.GrenadeType.FRAG) -> void:
	global_position = from
	_thrower = thrower
	_type = type
	collision_layer = 0  # nothing collides *with* the grenade
	# A sticky has to notice bodies to stick to them; the other two must not.
	collision_mask = 3 if type == Loadout.GrenadeType.STICKY else 1
	if type == Loadout.GrenadeType.STICKY:
		_fuse_left = STICKY_FUSE
		contact_monitor = true
		max_contacts_reported = 4
		body_entered.connect(_on_body_entered)
	linear_velocity = impulse
	angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	_build_mesh()


## First thing a sticky touches, it stops on. If that was a person it keeps
## following them — tracked by offset rather than reparented, so freeing the
## body it rode never takes the live grenade with it.
func _on_body_entered(body: Node) -> void:
	if _spent or _stuck_to != null or freeze:
		return
	# Never stick to the person who threw it. It leaves the hand close enough to
	# their own capsule that without this, throwing one on the move (or while
	# looking down) glues it to your chest — a self-kill with no counterplay.
	if body == _thrower:
		return
	freeze = true
	if body is Node3D and body.has_method("is_alive"):
		_stuck_to = body
		_stuck_offset = global_position - body.global_position


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
	# Each type reads differently in the air, so you can tell what just landed
	# next to you without waiting to find out.
	match _type:
		Loadout.GrenadeType.SMOKE:
			mat.albedo_color = Color(0.62, 0.64, 0.68)
			mat.emission = Color(0.5, 0.75, 1.0)
		Loadout.GrenadeType.STICKY:
			mat.albedo_color = Color(0.26, 0.20, 0.10)
			mat.emission = Color(1.0, 0.75, 0.1)
		_:
			mat.albedo_color = Color(0.18, 0.22, 0.16)
			mat.emission = Color(1.0, 0.3, 0.15)
	mat.metallic = 0.1  # keep low: a dark sky reflects into metal (Gotchas)
	mat.roughness = 0.7
	mat.emission_enabled = true  # blinking arming light, so it reads as live
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


func _physics_process(delta: float) -> void:
	if _spent:
		return
	# Ride the body a sticky attached to, so it goes off wherever they ran to.
	if is_instance_valid(_stuck_to):
		global_position = _stuck_to.global_position + _stuck_offset
	_fuse_left -= delta
	if _fuse_left <= 0.0:
		_explode()


func _explode() -> void:
	_spent = true
	var pos := global_position
	# Smoke does no damage at all: it buys you the ground, it does not take it.
	if _type == Loadout.GrenadeType.SMOKE:
		var cloud := SMOKE_SCENE.instantiate()
		get_tree().current_scene.add_child(cloud)
		cloud.global_position = pos
		queue_free()
		return
	var radius := STICKY_SPLASH if _type == Loadout.GrenadeType.STICKY else SPLASH
	var damage := STICKY_SPLASH_DAMAGE if _type == Loadout.GrenadeType.STICKY \
		else SPLASH_DAMAGE
	var shape := SphereShape3D.new()
	shape.radius = radius
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
		var falloff := clampf(1.0 - col.global_position.distance_to(pos) / radius, 0.2, 1.0)
		col.take_damage(damage * falloff, _thrower)
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
