class_name Weapon
extends Node3D
## Class-based hitscan blaster. All per-class numbers live in PROFILES; the
## owning player picks the class (set_class) and holds ADS via `aiming`.
## Damage lands instantly along the aim ray (jittered by a spread cone that
## tightens when aiming); a glowing bolt tracer flies the same path.
##
## Heat replaces ammo (README roadmap): each shot adds heat, reaching 1.0
## overheats and locks out firing until heat cools back below OVERHEAT_RELEASE.
## Sits under the player's Head so its -Z is always the aim direction.

signal heat_changed(heat: float, overheated: bool)

enum Class { SOLDIER, SNIPER, HEAVY }

# Tuning table. spread values are the half-angle of the fire cone in degrees
# (hip vs. aiming); zoom_fov is the camera FOV while aiming; heat_per_shot and
# cool_rate (per second) are fractions of the 0..1 heat pool.
# Heat tuning: heat_per_shot / fire_interval is the fill rate while firing;
# cool_rate is the drain when not. cool_rate is kept well below the fill rate
# so sustained fire overheats (Soldier ~3 s, Heavy ~2 s, Sniper ~4 shots),
# while short bursts vent fully between them.
const PROFILES := {
	Class.SOLDIER: {
		"name": "DC-15 Rifle", "fire_interval": 0.14, "damage": 20.0,
		"range": 120.0, "hip_spread": 2.5, "ads_spread": 0.4,
		"zoom_fov": 48.0, "heat_per_shot": 0.085, "cool_rate": 0.26,
		"scope": false, "recoil": 0.35,
	},
	Class.SNIPER: {
		"name": "NT-242 Sniper", "fire_interval": 1.1, "damage": 95.0,
		"range": 400.0, "hip_spread": 7.0, "ads_spread": 0.0,
		"zoom_fov": 20.0, "heat_per_shot": 0.45, "cool_rate": 0.28,
		"scope": true, "recoil": 1.0,
	},
	Class.HEAVY: {
		"name": "Z-6 Repeater", "fire_interval": 0.075, "damage": 11.0,
		"range": 85.0, "hip_spread": 4.5, "ads_spread": 2.0,
		"zoom_fov": 62.0, "heat_per_shot": 0.06, "cool_rate": 0.22,
		"scope": false, "recoil": 0.22,
	},
}

const BOLT_SCENE := preload("res://scenes/fx/blaster_bolt.tscn")
const OVERHEAT_RELEASE := 0.35  # heat must fall below this to fire again

var weapon_class: Class = Class.SOLDIER
var aiming := false

var _profile: Dictionary = PROFILES[Class.SOLDIER]
var _cooldown := 0.0
var _heat := 0.0
var _overheated := false

@onready var _viewmodel: Node3D = get_node_or_null("Viewmodel")


func set_class(c: Class) -> void:
	weapon_class = c
	_profile = PROFILES[c]
	# Swapping vents heat, so a fresh weapon is never born mid-overheat.
	_heat = 0.0
	_overheated = false
	heat_changed.emit(_heat, _overheated)
	if _viewmodel:
		_viewmodel.configure(c)


func display_name() -> String:
	return _profile["name"]


func zoom_fov() -> float:
	return _profile["zoom_fov"]


func has_scope() -> bool:
	return _profile["scope"]


# Fixed-timestep so heat/cooldown behave identically regardless of render
# framerate (important on the Pi), and on the same clock as try_fire.
func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _heat > 0.0:
		_heat = maxf(_heat - _profile["cool_rate"] * delta, 0.0)
		if _overheated and _heat <= OVERHEAT_RELEASE:
			_overheated = false
		heat_changed.emit(_heat, _overheated)


## Call from _physics_process (the space state is only safe to query there).
func try_fire(shooter: CollisionObject3D) -> void:
	if _cooldown > 0.0 or _overheated:
		return
	_cooldown = _profile["fire_interval"]
	_heat = minf(_heat + _profile["heat_per_shot"], 1.0)
	if _heat >= 1.0:
		_overheated = true
	heat_changed.emit(_heat, _overheated)
	if _viewmodel:
		_viewmodel.kick(_profile["recoil"])

	var from := global_position
	var dir := -global_transform.basis.z
	var spread: float = _profile["ads_spread"] if aiming else _profile["hip_spread"]
	if spread > 0.0:
		var rad := deg_to_rad(spread)
		dir = dir.rotated(global_transform.basis.x, randf_range(-rad, rad))
		dir = dir.rotated(global_transform.basis.y, randf_range(-rad, rad))
	var range_m: float = _profile["range"]
	var to := from + dir * range_m

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	var end: Vector3 = hit.get("position", to)
	if hit and hit.collider != null and hit.collider.has_method("take_damage"):
		hit.collider.take_damage(_profile["damage"])

	var bolt := BOLT_SCENE.instantiate()
	get_tree().current_scene.add_child(bolt)
	bolt.launch(from - global_transform.basis.y * 0.12, end)
