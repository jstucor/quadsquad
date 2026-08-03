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

## A GRENADE IS A SMALL FAST SPHERE, WHICH IS THE ONE SHAPE PHYSICS LOSES.
## At 22 m/s a 0.11 m ball covers 0.37 m in a 60 Hz tick — more than three times
## its own diameter — so with discrete collision it can start a step above the
## ground and finish below it, having never touched a triangle. That is the
## "grenades fall through the floor" report, and it got WORSE the moment the
## throw got stronger, which is exactly the trap: the fix for one made the other
## more likely.
##
## Two defences, because either alone still leaks:
##   CCD sweeps the shape along the step instead of sampling the end of it.
##   The FLOOR GUARD below catches whatever still gets past, using the map's own
##   `height_at` — the same analytic surface spawns and crates are placed on.
const RADIUS := 0.11
## How far below the ground it has to be before the guard calls it a leak rather
## than ordinary resting contact. The collision mesh sits ABOVE the analytic
## curve across a hollow (the reason SPAWN_LIFT exists), so a grenade legitimately
## rests a little under `height_at` and must not be teleported for it.
const FLOOR_SLACK := 0.35

## HOW MUCH IT ROLLS ONCE IT LANDS, which is a different question from how it
## flies and is why none of this is applied at launch. Damping the throw would
## make a strong throw impossible; damping the LANDING is what stops a grenade
## trickling twenty metres down a slope away from where it was aimed.
##
## Applied on first contact, so the flight stays ballistic and the moment it hits
## anything it settles. A little bounce is kept on purpose — a grenade that dies
## instantly where it lands reads as a beanbag, and bouncing off cover is a thing
## players aim to do.
const GROUND_FRICTION := 1.0
const GROUND_BOUNCE := 0.10
const LAND_LINEAR_DAMP := 4.5
const LAND_ANGULAR_DAMP := 8.0
## Spin at launch. It was +/-8 rad/s on every axis, which is most of where the
## rolling came from: a hard-spinning sphere converts that spin straight into
## travel the moment it touches friction.
const THROW_SPIN := 3.5

const FUSE := 2.0
const STICKY_FUSE := 2.6   # a beat longer, since it stops dead where it lands
const SPLASH := 5.0
const SPLASH_DAMAGE := 110.0
const STICKY_SPLASH := 4.2       # tighter than a frag...
const STICKY_SPLASH_DAMAGE := 135.0  # ...but it lands on the target, so it hurts
const SMOKE_SCENE := preload("res://scenes/fx/smoke_cloud.tscn")

var _thrower: CollisionObject3D  # for kill attribution
var _fuse_left := FUSE
var _spent := false
var _type := Loadout.GrenadeType.FRAG
var _stuck_to: Node3D      # body a sticky attached to, if any
var _stuck_offset := Vector3.ZERO
var _level: Node3D         # the map, for the floor guard
var _landed := false


func launch(from: Vector3, impulse: Vector3, thrower: CollisionObject3D,
		type := Loadout.GrenadeType.FRAG) -> void:
	global_position = from
	_thrower = thrower
	_type = type
	collision_layer = 0  # nothing collides *with* the grenade
	# A sticky has to notice bodies to stick to them; the other two must not.
	collision_mask = 3 if type == Loadout.GrenadeType.STICKY else 1
	# THE SHAPE GOES ON BEFORE THE VELOCITY DOES. `_build_mesh` used to run last,
	# which left a live body in the tree with no collider at all for the frame it
	# was thrown — travelling faster than at any other point in its life.
	_build_mesh()
	# CCD: sweep the sphere along its step rather than testing where it ended up.
	# This is the primary fix for tunnelling and it is nearly free for the two or
	# three grenades that are ever in the air at once.
	continuous_cd = true
	var surface := PhysicsMaterial.new()
	surface.friction = GROUND_FRICTION
	surface.bounce = GROUND_BOUNCE
	physics_material_override = surface
	# Contact monitoring for EVERY type now, not just the sticky. A frag needs it
	# too — not to stick, but to know it has landed, which is when the damping
	# that stops it rolling gets switched on.
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	if type == Loadout.GrenadeType.STICKY:
		_fuse_left = STICKY_FUSE
	linear_velocity = impulse
	angular_velocity = Vector3(randf_range(-THROW_SPIN, THROW_SPIN),
		randf_range(-THROW_SPIN, THROW_SPIN), randf_range(-THROW_SPIN, THROW_SPIN))
	# The map, for the floor guard. Held rather than looked up per frame: the
	# scene root is Main and the level is its child, and neither moves.
	var main := get_tree().current_scene
	if main != null:
		_level = main.get("level") as Node3D


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
	# IT HAS LANDED — whatever it hit, and whatever type it is. From here it is
	# damped hard, which is what turns "rolls off down the hill" into "sits about
	# where it was thrown". Set before the sticky branch so a sticky that somehow
	# fails to freeze still stops travelling.
	if not _landed:
		_landed = true
		linear_damp = LAND_LINEAR_DAMP
		angular_damp = LAND_ANGULAR_DAMP
	if _type != Loadout.GrenadeType.STICKY:
		return   # a frag and a smoke bounce and settle; only a sticky stops dead
	freeze = true
	if body is Node3D and body.has_method("is_alive"):
		_stuck_to = body
		_stuck_offset = global_position - body.global_position


func _build_mesh() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	shape.shape = sphere
	add_child(shape)

	var mesh := MeshInstance3D.new()
	var body := SphereMesh.new()
	body.radius = RADIUS
	body.height = RADIUS * 2.0
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
	else:
		_keep_above_the_floor()
	_fuse_left -= delta
	if _fuse_left <= 0.0:
		_explode()


## THE BACKSTOP FOR A GRENADE THAT GOT THROUGH THE GROUND ANYWAY.
##
## CCD is the real fix and this is the belt to its braces, because the failure it
## catches is total: a grenade under the map detonates where nobody is, and the
## player who threw it sees their gadget do literally nothing and go on cooldown.
## That is worth a couple of floating-point comparisons a frame on the two or
## three grenades ever in flight.
##
## The floor is the map's own `height_at` where there is one — the same analytic
## surface spawn markers and royale crates are placed on — and y = 0 otherwise,
## which is where every arena's slab is and below which no terrain is allowed to
## go (see PROCEDURAL WORLDS). It only acts past `FLOOR_SLACK`, so a grenade
## resting in a hollow, where the collision mesh legitimately sits above the
## curve, is left alone.
func _keep_above_the_floor() -> void:
	var pos := global_position
	var ground := 0.0
	if _level != null and is_instance_valid(_level) and _level.has_method("height_at"):
		ground = maxf(_level.height_at(pos.x, pos.z), 0.0)
	if pos.y >= ground - FLOOR_SLACK:
		return
	global_position = Vector3(pos.x, ground + RADIUS, pos.z)
	# Put it back ON the surface, not just at it: keeping the horizontal travel
	# lets a grenade that clipped a lip carry on roughly where it was going,
	# rather than stopping dead in a way that reads as a different bug.
	linear_velocity = Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	if not _landed:
		_landed = true
		linear_damp = LAND_LINEAR_DAMP
		angular_damp = LAND_ANGULAR_DAMP


func _explode() -> void:
	_spent = true
	var pos := global_position
	# Smoke pops rather than detonates, so it is not given the blast — its own
	# branch below returns before this would have mattered anyway.
	if _type != Loadout.GrenadeType.SMOKE:
		Audio.play_at("explosion", pos)
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
	# THE THROWER MAY BE DEAD BY NOW. A fuse is two seconds and a firefight is
	# faster than that, so the body that threw this can easily be freed before it
	# goes off — and passing a freed Object to `take_damage` raises, which ABORTS
	# THE WHOLE FUNCTION (house rule 6). The visible symptom is not an error
	# anybody sees: it is a grenade that damages the first person in the blast and
	# nobody else, which reads as splash being unreliable.
	var attacker: Node = _thrower if is_instance_valid(_thrower) else null
	var hit_once := {}
	for r in get_world_3d().direct_space_state.intersect_shape(params, 16):
		var col = r.get("collider")
		if col == null or hit_once.has(col) or not col.has_method("take_damage"):
			continue
		hit_once[col] = true
		var falloff := clampf(1.0 - col.global_position.distance_to(pos) / radius, 0.2, 1.0)
		col.take_damage(damage * falloff, attacker)
	_spawn_blast(pos)
	queue_free()


func _spawn_blast(pos: Vector3) -> void:
	Blast.pop(get_tree().current_scene, pos, SPLASH, 0.55)
