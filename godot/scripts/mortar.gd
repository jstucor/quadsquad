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
const MUZZLE_Y := 1.15        # shells leave the top of the tube
const SKY := 60.0             # how far up the ground probe starts

var team: int = GameState.Team.REPUBLIC
var owner_player: Node3D
var health := MAX_HEALTH

var _dead := false
var _aimed := false         # has it been given a mark yet?
var _aim := Vector3.ZERO
var _firing := false        # true during the burst half of the cycle
var _phase_left := 0.0      # seconds left in the current half
var _next_shell := 0.0

@onready var _tube: Node3D = $Tube


func _ready() -> void:
	GameState.register_combatant(self)


func _exit_tree() -> void:
	GameState.unregister_combatant(self)


func setup(placed_by: Node3D, mortar_team: int) -> void:
	owner_player = placed_by
	team = mortar_team
	_paint(GameState.team_colors[team])


func is_alive() -> bool:
	return not _dead


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
	queue_free()


## The bombardment cycle: burst, rest, burst, for as long as it stands.
func _physics_process(delta: float) -> void:
	if _dead or not _aimed:
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


func _paint(team_color: Color) -> void:
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.24, 0.26, 0.30)
	body_mat.metallic = 0.1  # a dark sky reflects into metal (Gotchas)
	body_mat.roughness = 0.62
	var trim := StandardMaterial3D.new()
	trim.albedo_color = team_color
	trim.metallic = 0.0
	trim.roughness = 0.5
	$Base.material_override = trim
	$Tube/Barrel.material_override = body_mat
