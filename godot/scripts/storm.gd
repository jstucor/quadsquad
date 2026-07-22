class_name Storm
extends Node3D
## The battle-royale storm: a circle that holds, then closes on a point picked
## at random inside itself, over and over, damaging anything left outside it.
##
## The new centre is drawn from INSIDE the current circle rather than anywhere
## on the map, which is the whole reason a closing circle works as a mechanic:
## wherever it goes next, the ground you are standing on might still be in it,
## so moving early is a bet rather than a certainty. Drawing from the whole map
## would regularly strand everyone and turn every round into the same race.
##
## Damage is per second and RISES with each phase, so the first ring is a nudge
## and the last one is lethal — late in a round the storm has to be able to end
## a stalemate, and early on it must not punish a slow looter too hard.

const HOLD_TIME := 22.0       # seconds the circle sits still before closing
const CLOSE_TIME := 26.0      # seconds it takes to shrink
const SHRINK := 0.62          # each phase leaves this share of the radius
const MIN_RADIUS := 12.0      # it stops here; a duel needs somewhere to happen
const DAMAGE_BASE := 4.0      # per second outside, on the first ring
const DAMAGE_STEP := 3.5      # ...plus this much more each phase
const WALL_HEIGHT := 60.0
const SEGMENTS := 48

var centre := Vector3.ZERO
var radius := 0.0

var _next_centre := Vector3.ZERO
var _next_radius := 0.0
var _from_centre := Vector3.ZERO
var _from_radius := 0.0
var _phase := 0
var _closing := false
var _left := HOLD_TIME
var _rng := RandomNumberGenerator.new()
var _wall: MeshInstance3D
var _mat: StandardMaterial3D
var _tick := 0.0


## Called by Main after the level exists. Starts covering the whole map.
func setup(seed_value: int) -> void:
	_rng.seed = seed_value
	centre = GameState.map_center
	# Big enough to contain the whole playable area from the off, corners and
	# all, so nobody starts outside it.
	radius = GameState.map_extents.length()
	_from_centre = centre
	_from_radius = radius
	_pick_next()
	_build_wall()


func _pick_next() -> void:
	_next_radius = maxf(radius * SHRINK, MIN_RADIUS)
	# Somewhere inside the CURRENT circle that the next one still fits within.
	var wander := maxf(radius - _next_radius, 0.0)
	var angle := _rng.randf_range(0.0, TAU)
	var reach := sqrt(_rng.randf()) * wander
	_next_centre = centre + Vector3(cos(angle) * reach, 0.0, sin(angle) * reach)


func seconds_left() -> int:
	return ceili(_left)


func is_closing() -> bool:
	return _closing


func phase() -> int:
	return _phase


## Damage per second for anything outside the ring right now.
func damage_rate() -> float:
	return DAMAGE_BASE + DAMAGE_STEP * float(_phase)


func _physics_process(delta: float) -> void:
	if not GameState.match_live or GameState.match_over:
		return
	_left -= delta
	if _closing:
		var t := 1.0 - clampf(_left / CLOSE_TIME, 0.0, 1.0)
		centre = _from_centre.lerp(_next_centre, t)
		radius = lerpf(_from_radius, _next_radius, t)
		if _left <= 0.0:
			centre = _next_centre
			radius = _next_radius
			_closing = false
			_left = HOLD_TIME
			_phase += 1
			if radius > MIN_RADIUS:
				_pick_next()
	elif _left <= 0.0:
		# Nothing left to close to: the last ring just stays and keeps burning.
		if radius <= MIN_RADIUS:
			_left = HOLD_TIME
		else:
			_closing = true
			_left = CLOSE_TIME
			_from_centre = centre
			_from_radius = radius
	_move_wall()
	_burn(delta)


## Anything outside the ring takes damage, players and bots alike — the storm
## is not a player-only rule, or the AI would simply ignore it and win.
##
## Applied a few times a second rather than every frame: take_damage fans out to
## hit markers, the damage flash and the kill feed, and calling that 60 times a
## second per body outside would drown all of them.
func _burn(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	var step := 0.5
	_tick = step
	var hurt := damage_rate() * step
	for c in GameState.combatants:
		if not is_instance_valid(c) or not c.is_alive():
			continue
		var flat := Vector2(c.global_position.x - centre.x, c.global_position.z - centre.z)
		if flat.length() > radius:
			c.take_damage(hurt, null, false)


## The visible wall: a tall, unshaded, double-sided cylinder. Unshaded so it
## reads the same from inside and out, and scaled rather than rebuilt so a
## closing ring costs nothing.
func _build_wall() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.albedo_color = Color(0.45, 0.55, 1.0, 0.30)
	_mat.emission_enabled = true
	_mat.emission = Color(0.40, 0.55, 1.0)
	_mat.emission_energy_multiplier = 1.6
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = WALL_HEIGHT
	cyl.radial_segments = SEGMENTS
	cyl.rings = 1
	# No cap: you have to be able to see out of the top of it.
	cyl.cap_top = false
	cyl.cap_bottom = false
	_wall = MeshInstance3D.new()
	_wall.mesh = cyl
	_wall.material_override = _mat
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wall)
	_move_wall()


func _move_wall() -> void:
	if _wall == null:
		return
	_wall.position = Vector3(centre.x, WALL_HEIGHT * 0.5 - 4.0, centre.z)
	_wall.scale = Vector3(radius, 1.0, radius)
	# Angrier as it tightens, so a late ring reads as something to run from.
	var heat := clampf(float(_phase) / 5.0, 0.0, 1.0)
	var tint := Color(0.45, 0.55, 1.0).lerp(Color(1.0, 0.35, 0.30), heat)
	_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.26 + 0.12 * heat)
	_mat.emission = tint
