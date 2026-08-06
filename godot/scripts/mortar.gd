class_name Mortar
extends StaticBody3D
## Placed mortar: indirect fire you aim from the map screen instead of down a
## barrel. Drop the tube, put the cursor where you want the barrage, and press
## fire — it then shells that spot INDEFINITELY, in five-second bursts with five
## seconds of quiet between them, lobbing shells in a high arc that detonate on
## impact. Re-aiming moves the barrage and starts a fresh burst.
##
## Deliberately not a turret: it never picks its own target, it only ever hits
## the ground it was pointed at, and it can be shot out. What you are buying is
## sustained pressure on somewhere you cannot see, not a second gun.
##
## Same duck-typed combat contract as Turret (is_alive / team / take_damage), so
## it registers as a combatant and enemies treat it as worth killing.

const SHELL_SCENE := preload("res://scenes/fx/mortar_shell.tscn")

const MAX_HEALTH := 130.0     # softer than a turret: it cannot defend itself
# Once it has a mark it bombards it INDEFINITELY, in bursts: five seconds of
# outgoing shells, five seconds of quiet, repeating until it is re-aimed, picked
# up or destroyed. The quiet half is the window the target gets to move through
# the area — that plus the shells' long hang time is the whole counterplay, so
# the two halves being equal is deliberate.
const BURST_TIME := 5.0
const REST_TIME := 5.0
const SHELL_GAP := 0.7        # seconds between rounds inside a burst (~7 a burst)
const SPREAD := 4.0           # metres of scatter around the called point
const SPLASH := 4.2
const SPLASH_DAMAGE := 68.0
const MUZZLE_Y := 1.13        # shells leave the top of the tube
const TRAVERSE_SPEED := 2.4   # radians/sec the tube swings toward a new mark
const SKY := 60.0             # how far up the ground probe starts

var team: int = GameState.Team.CONCORD
var owner_player: Node3D
var health := MAX_HEALTH

var _dead := false
var _aimed := false         # has it been given a mark yet?
var _aim := Vector3.ZERO
var _firing := false        # true during the burst half of the cycle
var _phase_left := 0.0      # seconds left in the current half
var _next_shell := 0.0

var _want_yaw := 0.0

## The turntable carries the tube and the bipod and swings to face the barrage;
## the baseplate and the ammo rack are bolted to the ground and do not.
@onready var _turntable: Node3D = $Turntable
@onready var _tube: Node3D = $Turntable/Tube

var _mats := {}


func _ready() -> void:
	GameState.register_combatant(self)
	_build_model()


func _exit_tree() -> void:
	GameState.unregister_combatant(self)


func setup(placed_by: Node3D, mortar_team: int) -> void:
	owner_player = placed_by
	team = mortar_team
	_paint(GameState.team_colors[team])


func is_alive() -> bool:
	return not _dead


func combatant_name() -> String:
	return "MORTAR"


## A live tube always accepts a new mark — re-aiming mid-bombardment is the
## point of having it, not something to wait out.
func ready_to_fire() -> bool:
	return not _dead


## Has it been given somewhere to shell?
func is_aimed() -> bool:
	return _aimed


## True while shells are actually going out (the burst half of the cycle).
func is_firing() -> bool:
	return _aimed and _firing


## Seconds left in whichever half of the cycle it is in.
func phase_left() -> float:
	return _phase_left


## Point the barrage at a world point. Only the XZ matters — the shells find their
## own ground height, so a point called on the map lands on the terrain under it
## rather than at whatever altitude the cursor implied.
func fire_at(point: Vector3) -> void:
	if not ready_to_fire():
		return
	_aim = Vector3(point.x, _ground_y(point), point.z)
	_aimed = true
	# SWING TO FACE IT. The shells solve their own arc from the tube's origin, so
	# where the barrel points has never affected where they land — which is
	# exactly why it was left pointing wherever it was dropped, and why a tube
	# shelling a hill behind it looked broken. It is cosmetic and it is the whole
	# read: a mortar that traverses is a mortar somebody is aiming.
	var local := to_local(_aim)
	_want_yaw = atan2(-local.x, -local.z)
	# A fresh mark starts a fresh burst, so re-aiming pays off immediately
	# instead of landing in the middle of a rest phase.
	_firing = true
	_phase_left = BURST_TIME
	_next_shell = 0.0


func take_damage(amount: float, attacker: Node = null, headshot := false) -> void:
	if _dead:
		return
	if attacker != null and "team" in attacker and attacker.team == team:
		return  # friendly fire is off, same as everywhere else
	health -= amount
	if attacker != null and attacker.has_method("on_hit_confirmed"):
		attacker.on_hit_confirmed(headshot, health <= 0.0)
	if health <= 0.0:
		_destroy(attacker)


func _destroy(attacker: Node) -> void:
	_dead = true
	if attacker != null and "team" in attacker and attacker.team != team:
		GameState.add_frag(attacker.team)
		if attacker.has_method("credit_kill"):
			attacker.credit_kill()
	# Destroying hardware is a kill in the feed too — it cost somebody a purchase
	# and it is exactly the kind of thing a player wants credit for out loud.
	GameState.record_kill(attacker, self)
	queue_free()


## The bombardment cycle: burst, rest, burst, for as long as it stands.
func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _turntable != null:
		_turntable.rotation.y = rotate_toward(_turntable.rotation.y, _want_yaw,
			TRAVERSE_SPEED * delta)
	if not _aimed:
		return
	# The match hold applies to placed hardware too, or a barrage called in the
	# opening seconds would land before anyone can move.
	if not GameState.match_live:
		return
	_phase_left -= delta
	if _phase_left <= 0.0:
		_firing = not _firing
		_phase_left = BURST_TIME if _firing else REST_TIME
		_next_shell = 0.0   # a new burst opens immediately
	if not _firing:
		return
	_next_shell -= delta
	if _next_shell > 0.0:
		return
	_next_shell = SHELL_GAP
	_launch_shell()


func _launch_shell() -> void:
	var scatter := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	if scatter.length() > 1.0:
		scatter = scatter.normalized()
	var target := _aim + Vector3(scatter.x, 0.0, scatter.y) * SPREAD
	target.y = _ground_y(target)
	var shell := SHELL_SCENE.instantiate()
	get_tree().current_scene.add_child(shell)
	shell.launch(global_position + Vector3.UP * MUZZLE_Y, target, self,
		SPLASH, SPLASH_DAMAGE)
	_recoil()


## Drop the tube back and let it settle between rounds, so a burst reads as
## distinct shots rather than shells appearing out of a static prop.
func _recoil() -> void:
	if _tube == null:
		return
	_tube.rotation.x = deg_to_rad(-26.0)
	var tween := create_tween()
	tween.tween_property(_tube, "rotation:x", deg_to_rad(-38.0), SHELL_GAP * 0.8)


## Ground height under an XZ point, probed from well above so it works on the
## terrain map and on top of cover alike. Falls back to the mortar's own height
## when the probe finds nothing (a point off the edge of the level).
func _ground_y(point: Vector3) -> float:
	var from := Vector3(point.x, global_position.y + SKY, point.z)
	var to := Vector3(point.x, global_position.y - SKY, point.z)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # world only: aim at the ground, not at a body
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"].y if hit else global_position.y


## Re-tint, never rebuild — see the same note on Turret._paint.
func _paint(team_color: Color) -> void:
	if _mats.is_empty():
		return
	_mats["trim"].albedo_color = team_color


## --- the model ----------------------------------------------------------------
##
## A MORTAR IS A BASEPLATE, A BIPOD AND A TUBE, and those three masses in roughly
## the right proportions are what the eye recognises — the same lesson as the
## Civis towers, where no amount of detail rescues the wrong shapes. It used
## to be a cone with a cylinder leaning out of it, which is a signpost.
##
## The three masses are also what makes it read as ARTILLERY rather than as a
## small turret at a glance, which matters: they are bought from the same screen,
## they are the same size, and one of them you should walk up to and shoot while
## the other you should not. The baseplate spreads on the ground, the bipod
## reaches forward, and the tube is the only thing on the model that is long.
##
## The AMMO RACK is three shells standing on the plate behind the breech. It is
## the cheapest thing here and does the most work: it says what the machine eats,
## and it is what a player sees while walking past their own tube between bursts.

func _build_model() -> void:
	var steel := _surface(Color(0.45, 0.47, 0.51), 0.32, 0.52)
	var poly := _surface(Color(0.12, 0.13, 0.15), 0.82, 0.20)
	var trim := _surface(Color(0.7, 0.7, 0.7), 0.45, 0.40)
	_mats = {"steel": steel, "poly": poly, "trim": trim}
	_paint(GameState.team_colors[team])

	# --- the baseplate, which does not swing ----------------------------------
	_box(Vector3(0.64, 0.10, 0.64), Vector3(0, 0.05, 0), steel)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			# Spade lugs: the teeth that stop a firing plate walking backwards.
			_box(Vector3(0.11, 0.05, 0.11), Vector3(sx * 0.24, 0.10, sz * 0.24),
				poly, null, false)
	_cyl(0.14, 0.09, Vector3(0, 0.12, 0), poly)   # the socket the tube sits in
	# The rack, behind the breech (forward is -Z, so this is where a crew stands).
	_box(Vector3(0.34, 0.05, 0.11), Vector3(0, 0.11, 0.29), poly, null, false)
	for i in 3:
		_cyl(0.045, 0.24, Vector3(-0.10 + i * 0.10, 0.25, 0.29), trim, null, false)

	# --- the bipod, which swings with the tube --------------------------------
	# Each leg hangs off a NODE placed at the yoke and rotated, rather than a box
	# carrying its own compound rotation: two tilts on one box means guessing at
	# Godot's rotation order, and the foot ends up somewhere near the ground
	# rather than on it.
	for sx: float in [-1.0, 1.0]:
		var hip := Node3D.new()
		_turntable.add_child(hip)
		hip.position = Vector3(sx * 0.09, 0.50, -0.26)
		hip.rotation = Vector3(0.18, 0.0, sx * -0.40)
		_box(Vector3(0.05, 0.62, 0.07), Vector3(0, -0.31, 0), steel, hip)
		_box(Vector3(0.15, 0.045, 0.18), Vector3(0, -0.64, 0), poly, hip, false)
	_box(Vector3(0.26, 0.09, 0.14), Vector3(0, 0.50, -0.26), steel, _turntable)
	# The elevating screw. A hand-turned thread on the outside of the yoke is the
	# detail that says a person sets this thing, and it is one cylinder.
	_cyl(0.022, 0.30, Vector3(0.15, 0.38, -0.20), steel, _turntable, false)

	# --- the tube -------------------------------------------------------------
	_cyl(0.082, 1.00, Vector3(0, 0.50, 0), steel, _tube)
	for i in 3:
		# REINFORCING BANDS, and they are here for scale rather than for realism:
		# a bare cylinder could be any length, and three repeats along it are
		# what let the eye read how long it actually is.
		_cyl(0.098, 0.04, Vector3(0, 0.26 + i * 0.24, 0), poly, _tube, false)
	# A LIP, not a cap. At r 0.10 over 0.10 this stepped out far enough for long
	# enough that the tube stopped reading as a tube and started reading as a
	# telescope — the muzzle wants to be the thinnest part of the barrel, not the
	# fattest.
	_cyl(0.092, 0.05, Vector3(0, 1.01, 0), steel, _tube)
	_cyl(0.095, 0.12, Vector3(0, 0.02, 0), poly, _tube)      # breech cap
	_cyl(0.101, 0.035, Vector3(0, 0.88, 0), trim, _tube, false)
	_box(Vector3(0.06, 0.13, 0.05), Vector3(0.115, 0.40, 0), poly, _tube, false)


func _surface(albedo: Color, roughness: float, spec: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = 0.0   # see the weapon-materials note: metal reflects the sky
	m.roughness = roughness
	m.metallic_specular = spec
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, into: Node3D = null,
		shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.chamfer_box(size)
	mi.position = pos
	mi.material_override = mat
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(into if into != null else self).add_child(mi)
	return mi


func _cyl(radius: float, height: float, pos: Vector3, mat: Material,
		into: Node3D = null, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = 10
	m.rings = 1
	mi.mesh = m
	mi.position = pos
	mi.material_override = mat
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(into if into != null else self).add_child(mi)
	return mi
