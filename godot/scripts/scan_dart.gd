extends Node3D
## The Legion ARC's scan dart: a small projectile that flies straight, STICKS to
## the first thing it hits (world or body), and then pulses — every SCAN_INTERVAL
## it reveals every enemy within SCAN_RADIUS to the thrower's whole team for a
## short tag, THROUGH walls. That team-wide, wall-piercing reveal is the recon
## value; it is drawn by the per-viewport scan overlay in Main.
##
## Flies like the rocket (ray-step per physics frame); on impact it plants and
## lives for SCAN_LIFETIME, then frees itself.

const SPEED := 55.0
const MAX_RANGE := 60.0
const SCAN_RADIUS := 18.0
const SCAN_INTERVAL := 0.5    # how often it re-pings
const SCAN_TAG := 1.6         # how long each ping keeps a body revealed
const SCAN_LIFETIME := 12.0   # matches the gadget cooldown

var _dir := Vector3.FORWARD
var _shooter_rid: RID
var _team := 0
var _flying := true
var _traveled := 0.0
var _life := SCAN_LIFETIME
var _ping_left := 0.0
var _pulse: MeshInstance3D
var _pulse_mat: StandardMaterial3D
var _pulse_t := 0.0


func launch(from: Vector3, dir: Vector3, shooter: CollisionObject3D, team: int) -> void:
	global_position = from
	_dir = dir.normalized()
	_shooter_rid = shooter.get_rid()
	_team = team
	if absf(_dir.dot(Vector3.UP)) < 0.99:
		look_at(from + _dir)
	_build_mesh()


func _build_mesh() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.14, 0.16, 0.18)
	mat.metallic = 0.0
	mat.roughness = 0.6
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.008
	cyl.bottom_radius = 0.02
	cyl.height = 0.16
	body.mesh = cyl
	body.rotation.x = PI / 2.0   # lay along -Z
	body.material_override = mat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)

	# The scan pulse: an expanding ring while it is planted, in the team colour, so
	# both sides can SEE a scanner is live and go dig it out.
	_pulse = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = SCAN_RADIUS - 0.4
	torus.outer_radius = SCAN_RADIUS
	torus.rings = 24
	torus.ring_segments = 5
	_pulse.mesh = torus
	_pulse.position.y = 0.15
	_pulse.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pulse_mat = StandardMaterial3D.new()
	_pulse_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pulse_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pulse_mat.albedo_color = Color(GameState.team_colors[_team], 0.0)
	_pulse.material_override = _pulse_mat
	_pulse.visible = false
	add_child(_pulse)


func _physics_process(delta: float) -> void:
	if _flying:
		_fly(delta)
		return
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	_ping_left -= delta
	if _ping_left <= 0.0:
		_ping_left += SCAN_INTERVAL
		_ping()
	_animate_pulse(delta)


func _fly(delta: float) -> void:
	var step := SPEED * delta
	var to := global_position + _dir * step
	var query := PhysicsRayQueryParameters3D.create(global_position, to)
	query.exclude = [_shooter_rid]
	query.collision_mask = 0b11   # world (1) + bodies (2)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		_plant(hit["position"] + (hit["normal"] as Vector3) * 0.05)
		return
	global_position = to
	_traveled += step
	if _traveled >= MAX_RANGE:
		_plant(global_position)


func _plant(at: Vector3) -> void:
	global_position = at
	_flying = false
	_ping_left = 0.0   # ping immediately on landing
	_pulse.visible = true


## Reveal every living enemy inside the radius to the thrower's team, walls and
## all. Iterates combatants rather than a shape query — it runs twice a second,
## not per frame, and combatants already holds players, bots and turrets.
func _ping() -> void:
	for c in GameState.combatants:
		if not is_instance_valid(c) or not c.is_alive() or c.team == _team:
			continue
		if global_position.distance_to(c.global_position) <= SCAN_RADIUS:
			GameState.mark_scanned(c, _team, SCAN_TAG)


func _animate_pulse(delta: float) -> void:
	_pulse_t += delta * 2.2
	# A soft breathing ring, brighter right after a ping.
	var a := 0.18 + 0.12 * sin(_pulse_t) + 0.25 * clampf(1.0 - _ping_left / SCAN_INTERVAL, 0.0, 1.0)
	_pulse_mat.albedo_color.a = a * clampf(_life / 2.0, 0.0, 1.0)  # fade out at the end
