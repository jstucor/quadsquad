class_name Mortar
extends StaticBody3D
## Placed mortar: indirect fire you aim from the map screen instead of down a
## barrel. Drop the tube, open the map, put the cursor where you want the
## barrage, and press fire — it lobs a salvo of shells that arc over the level
## and detonate on impact.
##
## Deliberately not a fire-and-forget turret: it never picks its own targets, it
## can be shot out, and a salvo costs a long cooldown. What you are buying is
## the ability to hit somewhere you cannot see.
##
## Same duck-typed combat contract as Turret (is_alive / team / take_damage), so
## it registers as a combatant and enemies treat it as worth killing.

const SHELL_SCENE := preload("res://scenes/fx/mortar_shell.tscn")

const MAX_HEALTH := 130.0     # softer than a turret: it cannot defend itself
const SHELLS := 4             # rounds in one salvo
const SHELL_GAP := 0.42       # seconds between rounds, so they walk in
const SPREAD := 4.0           # metres of scatter around the called point
const COOLDOWN := 14.0
const SPLASH := 4.2
const SPLASH_DAMAGE := 68.0
const MUZZLE_Y := 1.15        # shells leave the top of the tube
const SKY := 60.0             # how far up the ground probe starts

var team: int = GameState.Team.REPUBLIC
var owner_player: Node3D
var health := MAX_HEALTH

var _dead := false
var _cooldown := 0.0
var _queued := 0            # rounds still to leave the tube this salvo
var _next_shell := 0.0
var _aim := Vector3.ZERO

@onready var _tube: Node3D = $Tube


func _ready() -> void:
	GameState.register_combatant(self)


func _exit_tree() -> void:
	GameState.unregister_combatant(self)


func setup(placed_by: Node3D, mortar_team: int) -> void:
	owner_player = placed_by
	team = mortar_team
	_paint(GameState.TEAM_COLORS[team])


func is_alive() -> bool:
	return not _dead


## Ready when it is not already firing and the cooldown has run out.
func ready_to_fire() -> bool:
	return not _dead and _cooldown <= 0.0 and _queued == 0


func cooldown_left() -> float:
	return _cooldown


## Call a salvo onto a world point. Only the XZ matters — the shells find their
## own ground height, so a point called on the map lands on the terrain under it
## rather than at whatever altitude the cursor implied.
func fire_at(point: Vector3) -> void:
	if not ready_to_fire():
		return
	_aim = Vector3(point.x, _ground_y(point), point.z)
	_queued = SHELLS
	_next_shell = 0.0
	_cooldown = COOLDOWN


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


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _cooldown > 0.0:
		_cooldown = maxf(_cooldown - delta, 0.0)
	if _queued <= 0:
		return
	# The match hold applies to placed hardware too, or a salvo called in the
	# opening seconds would land before anyone can move.
	if not GameState.match_live:
		return
	_next_shell -= delta
	if _next_shell > 0.0:
		return
	_next_shell = SHELL_GAP
	_queued -= 1
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


## Drop the tube back and let it settle, so a salvo reads as four distinct shots
## rather than shells appearing out of a static prop.
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
