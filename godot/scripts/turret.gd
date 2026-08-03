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

var team: int = GameState.Team.REPUBLIC
var owner_player: Node3D
var health := MAX_HEALTH

var _target: Node3D
var _retarget_in := 0.0
var _dead := false

@onready var head: Node3D = $Head
## The head YAWS and the cradle PITCHES, which is one node more than the old
## model needed and is what stops an armoured housing tipping its whole self at
## the sky every time the gun elevates. A turret swings; only its gun climbs.
@onready var _cradle: Node3D = $Head/Cradle
@onready var weapon: Weapon = $Head/Cradle/Weapon

var _mats := {}


func _ready() -> void:
	GameState.register_combatant(self)
	weapon.shooter = self
	_retarget_in = randf() * RETARGET_INTERVAL
	# Built here rather than in setup(), so a turret dropped into a scene by a
	# test or a look shot has a body without anybody remembering to ask. `setup`
	# only re-tints, and does it by writing an albedo onto these same materials.
	_build_model()


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


func combatant_name() -> String:
	return "TURRET"


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
	# Destroying hardware is a kill in the feed too — it cost somebody a purchase
	# and it is exactly the kind of thing a player wants credit for out loud.
	GameState.record_kill(attacker, self)
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
	var to := other.global_position + Vector3.UP * GameState.aim_height(other)
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
	var aim_at: Vector3 = _target.global_position \
		+ Vector3.UP * GameState.aim_height(_target)
	var to_aim := aim_at - muzzle
	var flat := Vector3(to_aim.x, 0.0, to_aim.z)
	var want_yaw := atan2(-flat.x, -flat.z)
	head.rotation.y = rotate_toward(head.rotation.y, want_yaw, TURN_SPEED * delta)
	_cradle.rotation.x = lerpf(_cradle.rotation.x,
		atan2(to_aim.y, maxf(flat.length(), 0.01)), clampf(delta * 8.0, 0.0, 1.0))

	var facing := Vector3.FORWARD.rotated(Vector3.UP, head.rotation.y)
	var on_aim := rad_to_deg(facing.angle_to(flat.normalized())) <= FIRE_CONE_DEG
	var may_fire := on_aim and weapon.heat() < FIRE_HEAT_CEILING
	weapon.update_fire(may_fire, may_fire)


## Re-tint, never rebuild. The materials are made once in `_build_model` and this
## only writes colours onto them — the same rule the command posts learned the
## hard way, where three fresh materials a frame per post cost 1.7 ms.
func _paint(team_color: Color) -> void:
	if _mats.is_empty():
		return
	_mats["trim"].albedo_color = team_color
	var eye: StandardMaterial3D = _mats["lit"]
	eye.albedo_color = team_color.darkened(0.7)
	eye.emission = team_color


## --- the model ----------------------------------------------------------------
##
## AN AUTO-SENTRY IS A TRIPOD, A POST AND A HEAD. This used to be a cone with a
## box balanced on it: two meshes, no scale, and nothing saying a soldier carried
## the thing here and set it down. The tripod is what does most of that work —
## legs planted on the ground read as DEPLOYED in a way no pedestal can, and they
## also give the silhouette something no body in the game has, which matters on a
## quarter screen where the only question is "is that a man or a gun".
##
## Built to the same rules as the weapons: chamfered boxes (`Meshes.chamfer_box`
## caches per size, so the three legs and the two trunnion cheeks are one mesh
## each), `metallic` 0.0 on everything with steel separated from polymer by
## ALBEDO and ROUGHNESS, and one repeated small feature — the vent slats — to
## give a flat roof a sense of size.
##
## The sensor slit is EMISSIVE IN THE TEAM COLOUR on purpose. It is the only part
## of the model that carries information: at forty metres, through smoke, in a
## night map, a lit eye is what tells you whose turret is tracking you, and the
## painted trim is not readable at that distance.

## Offset by half a turn, so TWO legs face the way the gun does and one braces
## behind it. The other way round puts a single leg between the viewer and the
## post, which from the front is a bipod with something odd in the middle — and
## a two-legged thing with a head on top is a body, which is the one thing this
## silhouette must never be mistaken for.
const LEG_ANGLES := [PI, PI + TAU / 3.0, PI + TAU * 2.0 / 3.0]


func _build_model() -> void:
	var steel := _surface(Color(0.47, 0.49, 0.53), 0.30, 0.52)
	var poly := _surface(Color(0.12, 0.13, 0.15), 0.82, 0.20)
	var trim := _surface(Color(0.7, 0.7, 0.7), 0.45, 0.40)
	var lit := StandardMaterial3D.new()
	lit.metallic = 0.0
	lit.roughness = 0.4
	lit.emission_enabled = true
	# 1.3, not the 2.6 this started at. AgX at the project's 1.6 exposure takes
	# any emission much past unity to white, and a WHITE slit carries no team —
	# which is the entire reason the slit is lit rather than painted.
	lit.emission_energy_multiplier = 1.3
	_mats = {"steel": steel, "poly": poly, "trim": trim, "lit": lit}
	_paint(GameState.team_colors[team])

	# --- the tripod -----------------------------------------------------------
	for a: float in LEG_ANGLES:
		var leg := Node3D.new()
		add_child(leg)
		leg.rotation.y = a
		# The leg's own box is tipped so its TOP tucks into the hub and its foot
		# lands out on the ground; the pad is a separate flat plate, because a
		# leg ending in a cut face reads as a leg somebody snapped off. Steel
		# rather than polymer: on a night map a dark leg on dark ground leaves
		# the head floating, and the legs are half of what makes this a tripod.
		var shin := _box(Vector3(0.085, 0.46, 0.11), Vector3(0, 0.16, -0.24), steel, leg)
		shin.rotation.x = 0.74
		_box(Vector3(0.19, 0.05, 0.22), Vector3(0, 0.03, -0.40), poly, leg)
	_box(Vector3(0.32, 0.15, 0.32), Vector3(0, 0.29, 0), steel)   # hub
	_box(Vector3(0.25, 0.32, 0.25), Vector3(0, 0.50, 0), poly)    # pedestal
	_cyl(0.22, 0.10, Vector3(0, 0.72, 0), steel)                  # traverse ring

	# --- the head -------------------------------------------------------------
	_box(Vector3(0.34, 0.22, 0.34), Vector3(0, -0.20, 0), steel, head)   # basket
	_box(Vector3(0.42, 0.30, 0.44), Vector3(0, 0.02, 0.02), steel, head) # housing
	_box(Vector3(0.36, 0.05, 0.40), Vector3(0, 0.185, 0.02), poly, head) # roof
	# A SLOPED glacis rather than a flat face: one tilted plate is the difference
	# between armour and a crate, and it costs a rotation.
	var glacis := _box(Vector3(0.40, 0.26, 0.09), Vector3(0, 0.03, -0.20), poly, head)
	glacis.rotation.x = 0.24
	_box(Vector3(0.30, 0.06, 0.07), Vector3(0, 0.155, -0.205), steel, head)  # brow
	_box(Vector3(0.24, 0.045, 0.03), Vector3(0, 0.075, -0.247), lit, head)   # sensor slit
	for i in 3:
		_box(Vector3(0.22, 0.022, 0.03), Vector3(0, 0.215, -0.02 + i * 0.07),
			poly, head, false)                                              # vent slats
	# The ammo drum hangs off ONE side. A matched pair would read as styling; one
	# drum and a feed chute reads as a mechanism.
	_cyl(0.125, 0.13, Vector3(0.245, -0.01, 0.07), poly, head, AXIS_X)
	_cyl(0.132, 0.035, Vector3(0.245, -0.01, 0.07), trim, head, AXIS_X, false)
	_box(Vector3(0.09, 0.07, 0.20), Vector3(0.17, -0.03, -0.06), poly, head)
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.05, 0.19, 0.19), Vector3(sx * 0.215, 0.0, -0.10), steel, head)
	_box(Vector3(0.025, 0.22, 0.025), Vector3(-0.15, 0.32, 0.13), poly, head, false)
	_box(Vector3(0.035, 0.035, 0.035), Vector3(-0.15, 0.44, 0.13), trim, head, false)

	# --- the gun, on the cradle so it climbs and the housing stays level -------
	#
	# THE TURRET HAD NO GUN. Its `Weapon` node has no `Viewmodel` child — that is
	# a first-person rig, built for a camera 30 cm away and driven by bob, ADS
	# slide and a sprint carry that mean nothing bolted to a post — so the thing
	# fired hitscans and a muzzle light out of an empty node and read as a
	# television on legs. Twin barrels at the turret's OWN scale is the honest
	# version, and it puts the muzzle where the flash already was.
	_box(Vector3(0.20, 0.17, 0.16), Vector3(0, 0.0, -0.04), steel, _cradle)  # mantlet
	for sx: float in [-1.0, 1.0]:
		_cyl(0.044, 0.40, Vector3(sx * 0.068, 0.012, -0.28), poly, _cradle, AXIS_Z)
		_cyl(0.056, 0.05, Vector3(sx * 0.068, 0.012, -0.46), steel, _cradle,
			AXIS_Z, false)                                                   # muzzle
		_cyl(0.058, 0.04, Vector3(sx * 0.068, 0.012, -0.15), trim, _cradle,
			AXIS_Z, false)                                                   # heat band
	# A jacket across both barrels. Two bare pipes read as thin from anywhere but
	# head-on; one piece bridging them is what makes the gun a mass rather than a
	# pair of lines, which is the difference at the twenty metres a player
	# actually decides this thing is shooting at them.
	_box(Vector3(0.19, 0.075, 0.16), Vector3(0, 0.012, -0.24), steel, _cradle)


## Steel is a lighter albedo at a low roughness and polymer a dark one at a high
## roughness — `metallic` is 0.0 on both, as it is on every weapon in the game.
## Under GL Compatibility the only thing a metal has to reflect is the sky, so a
## metallic surface stops being its own colour and becomes a picture of the sky
## hanging in the air, which is what "the guns look see-through" was.
func _surface(albedo: Color, roughness: float, spec: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = 0.0
	m.roughness = roughness
	m.metallic_specular = spec
	return m


## `shadow` is off for the small trim. Every mesh here is drawn four times plus a
## shadow pass, and a 3 cm vent slat's shadow is not information anybody uses.
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


## A CylinderMesh runs along +Y, so anything lying on another axis is a quarter
## turn — the same correction every barrel in the viewmodel needs.
enum {AXIS_X, AXIS_Y, AXIS_Z}


func _cyl(radius: float, height: float, pos: Vector3, mat: Material,
		into: Node3D = null, axis := AXIS_Y, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	# Ten sides, not the default sixty-four: at this size the facets ARE the
	# look, and they match the faceted columns the maps are built from.
	m.radial_segments = 10
	m.rings = 1
	mi.mesh = m
	mi.position = pos
	if axis == AXIS_X:
		mi.rotation.z = PI * 0.5
	elif axis == AXIS_Z:
		mi.rotation.x = PI * 0.5
	mi.material_override = mat
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(into if into != null else self).add_child(mi)
	return mi
