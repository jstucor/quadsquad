extends Node3D
## THE LAAT GUNSHIP — the AC-130 of this game, and the one reward you do not
## drive.
##
## IT FLIES ITSELF AND YOU RIDE THE BALL TURRET. That is the whole design and it
## is why this is not a `Vehicle`. A LAAT is not remembered for being piloted; it
## is remembered for the two glass spheres hanging off its flanks with a trooper
## sealed inside each one, hosing green fire down at everything below. Handing the
## player the stick would make it a slow speeder with good armour — handing them
## the TURRET makes it the thing in the reference.
##
## So: the airframe owns the flying, the player owns the gun, and neither can do
## the other's job. It circles the middle of the map at altitude for its duration
## and then leaves, and the gunner is put back exactly where they were standing
## when they called it.
##
## WHY NOT A `Vehicle`: every one of that class's answers is about a machine you
## meet on the ground and climb into — the interact edge, the team gate on the
## mount, the hover ray, the driver bleed, being a combatant that blocks a spawn
## marker. None of them apply to something that arrives in the air, cannot be
## boarded, cannot be shot down and leaves on a timer. What it DOES reuse is the
## seating: `Player.enter_vehicle`/`exit_vehicle` already hide the body, kill its
## collision and slave it to a `Seat`, and that is the hard part.

const GREEN := Color(0.30, 1.0, 0.22)

## The circuit. Big enough that the gunship is a distant shape from the ground
## rather than a ceiling, high enough to clear every structure the generator
## builds, and slow enough that a gunner can actually track something.
const ORBIT_RADIUS := 62.0
const ORBIT_HEIGHT := 46.0
const ORBIT_SPEED := 0.30      # radians/s — a lap takes about twenty seconds
## Banked INTO the turn, hard. A gunship flying a circle dead level reads as a
## model on a stick; the bank is most of what sells the circuit, and it also
## tips the ball turret's own view down toward the ground it is shooting at.
const BANK := 0.42

## THE TURRET IS ON THE INSIDE OF THE TURN, which is not a detail — the whole
## reason a circling gunship works is that its guns stay pointed at the middle,
## so the gunner is looking at the battle for the entire lap instead of half of it.
const TURRET_SIDE := -1.0
const TURRET_ARM := 2.35       # how far out the ball hangs from the hull
const TURRET_DROP := 0.55

## How far the gunner may swing the ball. Wide, but not free: a turret that can
## point anywhere is a floating camera, and the arc is what keeps the airframe's
## own facing meaningful.
const YAW_LIMIT := deg_to_rad(110.0)
const PITCH_MIN := deg_to_rad(-85.0)
const PITCH_MAX := deg_to_rad(12.0)

## The gun. A LASER CANNON, not a repeater: slow, heavy, and it hits hard enough
## that a hit is an event. It is deliberately not hitscan-instant in feel — the
## rate is what stops this being a twenty-second wipe of the map.
const FIRE_INTERVAL := 0.22
const DAMAGE := 62.0
const SPLASH := 3.4
const SPLASH_DAMAGE := 46.0
const RANGE := 260.0
const BEAM_LIFE := 0.09
const SPREAD := deg_to_rad(0.7)

var team := 0

var _gunner: Node3D
var _return_to := Vector3.ZERO
var _left := 0.0
var _angle := 0.0
var _cool := 0.0
var _body: Node3D
var _turret: Node3D          # yaws
var _ball: Node3D            # pitches, and carries the muzzle
var _muzzle: Node3D
var _seat: Node3D
var _beams: Array[MeshInstance3D] = []
var _beam_life: Array[float] = []
var _mats := {}


## `by` is the player who earned it. They are seated immediately and put back
## when it ends — the position is taken NOW, because by the end of the run the
## ground they were standing on may have a firefight on it and their old body has
## been hidden for the whole ride anyway.
func begin(by: Node3D, for_team: int, seconds: float) -> void:
	_gunner = by
	team = for_team
	_left = seconds
	_return_to = by.global_position
	# Start the circuit on the side of the map the caller is on, so the gunship
	# arrives over them rather than behind them.
	var here: Vector3 = by.global_position - _centre()
	_angle = atan2(here.z, here.x)
	_build()
	_place(0.0)
	# A HANDOVER IS A TELEPORT, both ways (house rule 10).
	reset_physics_interpolation()
	if by.has_method("enter_vehicle"):
		by.enter_vehicle(self)


## Where the gunner sits. Asked for by `Player.enter_vehicle` rather than pathed
## to, because this one is nested inside a turret that moves.
func seat() -> Node3D:
	return _seat


func _centre() -> Vector3:
	return Vector3(GameState.map_center.x, 0.0, GameState.map_center.z)


func _physics_process(delta: float) -> void:
	if not GameState.match_live:
		return
	_age_beams(delta)
	_left -= delta
	if _left <= 0.0 or not _gunner_ok():
		_finish()
		return
	_angle += ORBIT_SPEED * delta
	_place(delta)
	_aim(delta)
	# THE GUNNER RIDES THE SEAT, written every frame. The camera follows the head,
	# the head follows the body and the body follows the seat — the same chain a
	# speeder's driver hangs off, and the reason no second camera is needed.
	_gunner.global_position = _seat.global_position
	_shoot(delta)


func _gunner_ok() -> bool:
	# A GUNNER WHO DIED STOPS BEING A GUNNER. They cannot be killed in the ball —
	# nothing can reach them — but the match can end under them, the map can
	# change, and Royale can strand them.
	return _gunner != null and is_instance_valid(_gunner) \
		and _gunner.has_method("is_alive") and _gunner.is_alive()


## Fly the circuit. The hull is placed rather than steered: there is no physics
## body here and nothing to collide with at altitude, so a solved position is
## both cheaper and exactly repeatable.
func _place(delta: float) -> void:
	var c := _centre()
	global_position = c + Vector3(
		cos(_angle) * ORBIT_RADIUS, ORBIT_HEIGHT, sin(_angle) * ORBIT_RADIUS)
	# Face along the tangent, which is the direction of travel.
	var tangent := Vector3(-sin(_angle), 0.0, cos(_angle))
	var yaw := atan2(-tangent.x, -tangent.z)
	rotation.y = yaw
	if _body != null:
		# Bank on the BODY and never on the root, for the same reason a speeder
		# does: rolling the root would roll the seat and the turret's own arc
		# with it, and the gunner would be flying sideways in the ball.
		_body.rotation.z = lerpf(_body.rotation.z, BANK * -TURRET_SIDE,
			clampf(delta * 2.5, 0.0, 1.0))


## The gunner's look drives the ball, inside its arc. Read off the player's own
## aim rather than a control of its own — they are already looking with the right
## stick and the ball should simply follow their eyes.
func _aim(delta: float) -> void:
	if _turret == null or not _gunner.has_method("vehicle_look"):
		return
	# `aim_angles` is the body yaw and head pitch the player is already holding.
	var want_yaw: float = wrapf(_gunner.rotation.y - rotation.y, -PI, PI)
	var want_pitch: float = _gunner.get("_look_pitch")
	var step := clampf(delta * 7.0, 0.0, 1.0)
	_turret.rotation.y = lerpf(_turret.rotation.y,
		clampf(want_yaw, -YAW_LIMIT, YAW_LIMIT), step)
	_ball.rotation.x = lerpf(_ball.rotation.x,
		clampf(want_pitch, PITCH_MIN, PITCH_MAX), step)


func _shoot(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)
	if _cool > 0.0 or not _gunner.has_method("vehicle_firing"):
		return
	if not _gunner.vehicle_firing():
		return
	_cool = FIRE_INTERVAL
	var from: Vector3 = _muzzle.global_position
	var dir: Vector3 = -_muzzle.global_transform.basis.z
	dir = dir.rotated(Vector3.UP, randf_range(-SPREAD, SPREAD)) \
		.rotated(_muzzle.global_transform.basis.x, randf_range(-SPREAD, SPREAD))
	var to := from + dir * RANGE

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0b11        # world + bodies
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var land := to
	if not hit.is_empty():
		land = hit["position"]
		var body = hit.get("collider")
		if body != null and body.has_method("take_damage") \
				and "team" in body and body.team != team:
			body.take_damage(DAMAGE, _gunner, false)
	# THE SPLASH IS WHAT MAKES IT A GUNSHIP ROUND rather than a very long rifle.
	# From this altitude a single-target hitscan on a moving infantryman is close
	# to unusable; a cannon shell that cracks the ground near them is the weapon
	# in the reference.
	Blast.pop(get_tree().current_scene, land, SPLASH, 0.5)
	_splash(land)
	_beam(from, land)
	Audio.play_at("explosion", land, -6.0)


func _splash(at: Vector3) -> void:
	for c in GameState.combatants:
		if not is_instance_valid(c) or not c.is_alive() or c.team == team:
			continue
		var gap: float = at.distance_to(c.global_position + Vector3.UP * 0.9)
		if gap > SPLASH:
			continue
		c.take_damage(SPLASH_DAMAGE * (1.0 - gap / SPLASH), _gunner, false)


## --- the beam ------------------------------------------------------------------
##
## A FIXED POOL, allocated once and only repositioned — the same rule as
## `lightning_arc.gd` and for the same reason: this fires four or five times a
## second for twenty seconds and the obvious rebuild-a-mesh version allocates
## every shot, four viewports deep.
const BEAM_POOL := 6


func _beam(from: Vector3, to: Vector3) -> void:
	var i := _beams.size()
	for n in _beams.size():
		if _beam_life[n] <= 0.0:
			i = n
			break
	if i >= _beams.size():
		if _beams.size() >= BEAM_POOL:
			i = 0     # everything is live: reuse the oldest rather than allocate
		else:
			var mi := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.13
			cyl.bottom_radius = 0.13
			cyl.height = 1.0
			cyl.radial_segments = 6
			cyl.rings = 0
			mi.mesh = cyl
			mi.material_override = _mats["beam"]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			get_tree().current_scene.add_child(mi)
			_beams.append(mi)
			_beam_life.append(0.0)
			i = _beams.size() - 1
	var mi: MeshInstance3D = _beams[i]
	var span := to - from
	mi.global_position = (from + to) * 0.5
	# A cylinder runs along +Y, so it is stood up along the shot the same way
	# every barrel in the game is laid along -Z and then turned.
	if span.length() > 0.01:
		mi.global_basis = Basis(Quaternion(Vector3.UP, span.normalized()))
	mi.scale = Vector3(1.0, span.length(), 1.0)
	mi.visible = true
	_beam_life[i] = BEAM_LIFE


func _age_beams(delta: float) -> void:
	for i in _beams.size():
		if _beam_life[i] <= 0.0:
			continue
		_beam_life[i] -= delta
		if _beam_life[i] <= 0.0 and is_instance_valid(_beams[i]):
			_beams[i].visible = false


## The ride is over: put the gunner back on their feet where they called it and
## take the airframe with us.
func _finish() -> void:
	if _gunner != null and is_instance_valid(_gunner) \
			and _gunner.has_method("exit_vehicle"):
		# PUT THEM BACK WHERE THEY STOOD, and do NOT run it through
		# `clear_of_bodies` — that avoids LIVE players, and the gunner is one, so
		# it shoves them clear of the very spot it is meant to return them to
		# (measured: 12.8 m away). Their body has been hidden and collision-less
		# for the whole ride, so nothing has taken the ground from them, and the
		# ordinary unstick handles anybody who wandered onto it.
		_gunner.exit_vehicle(_return_to + Vector3.UP * 0.4, 0.0, false)
	_gunner = null
	for mi in _beams:
		if is_instance_valid(mi):
			mi.queue_free()
	_beams.clear()
	queue_free()


## --- the airframe ---------------------------------------------------------------
##
## Built to the reference, and the reference is emphatic about four things: the
## hull is a WIDE FLAT SLAB with a rounded nose, the wings sit HIGH with the
## engine nacelles lying ON TOP of them, the ball turrets hang OUTBOARD on visible
## arms, and the whole thing is much wider than it is tall. It is only ever seen
## from below, so every one of those has to read against the sky.

func _build() -> void:
	_body = Node3D.new()
	add_child(_body)
	var steel := _surface(Color(0.62, 0.63, 0.65), 0.36, 0.50)
	var poly := _surface(Color(0.15, 0.16, 0.18), 0.78, 0.20)
	var trim := _surface(GameState.team_colors[
		clampi(team, 0, GameState.team_colors.size() - 1)], 0.42, 0.40)
	var glass := _surface(Color(0.55, 0.72, 0.62), 0.12, 0.85)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color.a = 0.55
	var lit := StandardMaterial3D.new()
	lit.metallic = 0.0
	lit.roughness = 0.4
	lit.emission_enabled = true
	lit.emission = GREEN
	lit.emission_energy_multiplier = 1.4
	lit.albedo_color = GREEN.darkened(0.6)
	# The beam is UNSHADED and additive: it is light, and a lit cylinder goes
	# black on its shadow side exactly like the cable wire did.
	var beam := StandardMaterial3D.new()
	beam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam.albedo_color = Color(GREEN.r, GREEN.g, GREEN.b, 0.85)
	_mats = {"beam": beam}

	# The hull: a wide flat slab, nose dropped, tail squared off.
	_box(Vector3(3.40, 1.30, 7.60), Vector3(0, 0, 0.40), steel, _body)
	_box(Vector3(2.90, 1.00, 2.20), Vector3(0, -0.28, -4.10), steel, _body)   # nose
	_box(Vector3(2.20, 0.70, 1.00), Vector3(0, -0.30, -5.05), poly, _body)    # cockpit
	_box(Vector3(2.40, 0.20, 0.40), Vector3(0, 0.18, -5.20), trim, _body)     # brow
	_box(Vector3(3.60, 0.55, 1.20), Vector3(0, 0.30, 4.20), steel, _body)     # tail
	_box(Vector3(0.50, 1.50, 1.00), Vector3(0, 1.00, 4.30), steel, _body)     # fin

	for sx: float in [-1.0, 1.0]:
		# THE WING IS HIGH AND THE NACELLE LIES ON TOP OF IT. That stack is the
		# LAAT's whole profile from below — a wing with the engine slung UNDER it
		# is every other aircraft ever drawn.
		var wing := Node3D.new()
		_body.add_child(wing)
		wing.position = Vector3(sx * 1.60, 0.75, 0.30)
		wing.rotation = Vector3(0.0, sx * -0.20, sx * -0.13)
		_box(Vector3(4.60, 0.28, 2.30), Vector3(sx * 2.20, 0, 0), steel, wing)
		_box(Vector3(1.10, 0.70, 3.60), Vector3(sx * 1.70, 0.45, -0.20), poly, wing)
		_box(Vector3(0.80, 0.44, 0.50), Vector3(sx * 1.70, 0.45, -2.15), trim, wing)
		_box(Vector3(0.60, 0.34, 0.30), Vector3(sx * 1.70, 0.45, 1.75), lit, wing)
		# Wingtip ball, which the reference has and which stops the wing ending
		# in a bare edge.
		_sphere(0.52, Vector3(sx * 4.40, 0.10, 0.10), steel, wing)

	# The chin turret, and the two door guns behind it.
	_sphere(0.60, Vector3(0, -0.85, -3.30), steel, _body)
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.13, 0.13, 1.40), Vector3(sx * 0.24, -0.95, -4.10), trim, _body)

	_build_turret(steel, poly, trim, glass)
	# The OTHER ball, on the outside of the turn — cosmetic, and the thing that
	# makes the one you are sitting in read as a pair rather than as a growth.
	_ball_shell(-TURRET_SIDE, steel, trim, glass)


## The ball you are actually inside. A sphere of glass on a short arm, with a
## yaw ring and a pitch axis — the two joints a ball turret visibly has.
func _build_turret(steel: Material, poly: Material, trim: Material,
		glass: Material) -> void:
	_turret = Node3D.new()
	_body.add_child(_turret)
	_turret.position = Vector3(TURRET_SIDE * 1.75, -TURRET_DROP, -1.30)
	# The arm out to the ball, and the ring it turns on.
	_box(Vector3(TURRET_ARM, 0.30, 0.34),
		Vector3(TURRET_SIDE * TURRET_ARM * 0.5, 0, 0), steel, _turret)
	_sphere(0.34, Vector3.ZERO, poly, _turret)

	_ball = Node3D.new()
	_turret.add_child(_ball)
	_ball.position = Vector3(TURRET_SIDE * TURRET_ARM, -0.10, 0)
	# The glass sphere, and a darker cradle round its middle so it reads as a
	# ball in a mount rather than as a bubble stuck on a stick.
	_sphere(0.92, Vector3.ZERO, glass, _ball)
	_sphere(0.62, Vector3(0, -0.10, 0), poly, _ball)
	_box(Vector3(1.95, 0.20, 0.24), Vector3(0, 0.05, 0), trim, _ball)
	# The twin cannon barrels, forward out of the ball.
	for sy: float in [-1.0, 1.0]:
		_box(Vector3(0.14, 0.14, 1.70), Vector3(sy * 0.22, -0.06, -1.15), poly, _ball)
		_box(Vector3(0.20, 0.20, 0.26), Vector3(sy * 0.22, -0.06, -1.95), trim, _ball)

	_muzzle = Node3D.new()
	_ball.add_child(_muzzle)
	_muzzle.position = Vector3(0, -0.06, -2.10)

	# THE SEAT IS INSIDE THE BALL, so the camera is inside the glass and the
	# barrels run away from it — which is the shot in the reference.
	_seat = Node3D.new()
	_seat.name = "Seat"
	_ball.add_child(_seat)
	_seat.position = Vector3(0, -0.05, 0.15)


## The far-side ball: the same shell with no working parts.
func _ball_shell(side: float, steel: Material, trim: Material,
		glass: Material) -> void:
	var arm := Node3D.new()
	_body.add_child(arm)
	arm.position = Vector3(side * 1.75, -TURRET_DROP, -1.30)
	_box(Vector3(TURRET_ARM, 0.30, 0.34),
		Vector3(side * TURRET_ARM * 0.5, 0, 0), steel, arm)
	_sphere(0.92, Vector3(side * TURRET_ARM, -0.10, 0), glass, arm)
	_box(Vector3(1.95, 0.20, 0.24), Vector3(side * TURRET_ARM, -0.05, 0), trim, arm)


func _box(size: Vector3, pos: Vector3, mat: Material, into: Node3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.chamfer_box(size)
	mi.position = pos
	mi.material_override = mat
	into.add_child(mi)


func _sphere(radius: float, pos: Vector3, mat: Material, into: Node3D) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	# Coarse on purpose: this is read from the ground at forty metres, and a ball
	# turret is a circle long before it is a sphere.
	s.radial_segments = 12
	s.rings = 6
	mi.mesh = s
	mi.position = pos
	mi.material_override = mat
	into.add_child(mi)


func _surface(albedo: Color, roughness: float, spec: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = 0.0        # house rule 12, on every part of every machine
	m.roughness = roughness
	m.metallic_specular = spec
	return m
