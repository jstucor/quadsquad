extends StaticBody3D
## Placed auto-turret: the stationary cousin of Bot. It acquires the nearest
## enemy combatant it can actually see inside its arc, tracks it, and fires
## until the target dies or leaves. It can be shot: it registers as a combatant,
## so enemy bots and players both treat it as a target worth killing.
##
## Everything it needs from a target is the same duck-typed contract Bot uses
## (is_alive / team / global_position), so no shared base class is involved.

const MAX_HEALTH := 200.0
const RANGE := 44.0
const TURN_SPEED := 3.2      # radians/sec the head tracks at
const FIRE_CONE_DEG := 8.0
const RETARGET_INTERVAL := 0.4
const FIRE_HEAT_CEILING := 0.75
const EYE_HEIGHT := 1.05
const TARGET_AIM_HEIGHT := 1.0

var team: int = GameState.Team.REPUBLIC
var owner_player: Node3D
var health := MAX_HEALTH

var _target: Node3D
var _retarget_in := 0.0
var _dead := false

@onready var head: Node3D = $Head
@onready var weapon: Weapon = $Head/Weapon


func _ready() -> void:
	GameState.register_combatant(self)
	weapon.shooter = self
	_retarget_in = randf() * RETARGET_INTERVAL


func _exit_tree() -> void:
	GameState.unregister_combatant(self)


func setup(placed_by: Node3D, turret_team: int) -> void:
	owner_player = placed_by
	team = turret_team
	weapon.set_class(Weapon.Class.TURRET)
	_paint(GameState.team_colors[team])
	for mi in weapon.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 1  # a world object, not a viewmodel: everyone sees it


func is_alive() -> bool:
	return not _dead


func take_damage(amount: float, attacker: Node = null, headshot := false) -> void:
	if _dead:
		return
	if attacker != null and "team" in attacker and attacker.team == team:
		return  # friendly fire is off, same as everywhere else
	health -= amount
	# Shooting out a turret confirms like any other hit, so wearing one down
	# gives the same feedback as shooting a body.
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


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not GameState.match_live:
		weapon.update_fire(false, false)
		return
	_retarget_in -= delta
	if _retarget_in <= 0.0:
		_retarget_in = RETARGET_INTERVAL
		_acquire_target()
	if not is_instance_valid(_target) or not _target.is_alive():
		_target = null
		weapon.update_fire(false, false)
		return
	_track(delta)


func _acquire_target() -> void:
	var best: Node3D = null
	var best_gap := RANGE
	for c in GameState.combatants:
		if c == self or not c.is_alive() or c.team == team:
			continue
		var gap := global_position.distance_to(c.global_position)
		if gap < best_gap and _can_see(c):
			best_gap = gap
			best = c
	_target = best


func _can_see(other: Node3D) -> bool:
	# A cloaked target is invisible to a turret too — same rule as the bot's.
	if GameState.is_cloaked(other):
		return false
	var from := global_position + Vector3.UP * EYE_HEIGHT
	var to := other.global_position + Vector3.UP * TARGET_AIM_HEIGHT
	# Smoke has no collider (it would stop bullets too), so it is checked
	# separately — this is what makes a smoke grenade break an AI's lock.
	if GameState.sight_blocked(from, to):
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collision_mask = 0b11  # world + bodies
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == other


## Swing the head toward the target in yaw and pitch, and fire once it's lined
## up. Pitch is solved from the head, not the base — the same mistake that made
## every early Bot shot fly high.
func _track(delta: float) -> void:
	var muzzle := head.global_position
	var aim_at: Vector3 = _target.global_position + Vector3.UP * TARGET_AIM_HEIGHT
	var to_aim := aim_at - muzzle
	var flat := Vector3(to_aim.x, 0.0, to_aim.z)
	var want_yaw := atan2(-flat.x, -flat.z)
	head.rotation.y = rotate_toward(head.rotation.y, want_yaw, TURN_SPEED * delta)
	head.rotation.x = lerpf(head.rotation.x, atan2(to_aim.y, maxf(flat.length(), 0.01)),
		clampf(delta * 8.0, 0.0, 1.0))

	var facing := Vector3.FORWARD.rotated(Vector3.UP, head.rotation.y)
	var on_aim := rad_to_deg(facing.angle_to(flat.normalized())) <= FIRE_CONE_DEG
	var may_fire := on_aim and weapon.heat() < FIRE_HEAT_CEILING
	weapon.update_fire(may_fire, may_fire)


func _paint(team_color: Color) -> void:
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.26, 0.28, 0.32)
	body_mat.metallic = 0.1  # a dark sky reflects into metal (Gotchas)
	body_mat.roughness = 0.6
	var trim := StandardMaterial3D.new()
	trim.albedo_color = team_color
	trim.metallic = 0.0
	trim.roughness = 0.5
	$Base.material_override = body_mat
	$Head/Housing.material_override = trim
