class_name Weapon
extends Node3D
## Class-based weapon. All per-class numbers live in PROFILES; the owning
## player sets `shooter` + the class, holds ADS via `aiming`, and drives firing
## through update_fire() every physics frame. Most classes are hitscan (damage
## lands instantly along a spread-jittered ray, tracer flies the path); the RPG
## launches a real rocket projectile with splash damage.
##
## Fire modes: AUTO fires while held, SEMI once per trigger press, BURST fires a
## fixed count per press. A head hit multiplies damage by HEADSHOT_MULT. Each
## shot emits `fired(cam_recoil)` so the player can kick the camera. Heat
## replaces ammo: shots add heat, 1.0 overheats and locks out until it cools
## below OVERHEAT_RELEASE.

signal heat_changed(heat: float, overheated: bool)
signal fired(cam_recoil: float)

enum Class { SOLDIER, SNIPER, HEAVY, REVOLVER, HMG, BURST, SEMI, RPG, PISTOL }
enum FireMode { AUTO, SEMI, BURST }

# spread = fire-cone half-angle (deg); zoom_fov = FOV while aiming; heat_per_shot
# / cool_rate are fractions of the 0..1 heat pool; recoil = viewmodel kick;
# cam_recoil = camera pitch kick (radians). Optional keys default via .get():
# mode (AUTO), burst_count/burst_interval (BURST), projectile/splash* (RPG).
const PROFILES := {
	Class.SOLDIER: {
		"name": "DC-15 Rifle", "fire_interval": 0.14, "damage": 20.0,
		"range": 120.0, "hip_spread": 2.5, "ads_spread": 0.4, "zoom_fov": 48.0,
		"heat_per_shot": 0.085, "cool_rate": 0.26, "scope": false,
		"recoil": 0.35, "cam_recoil": 0.010,
	},
	Class.SNIPER: {
		"name": "NT-242 Sniper", "fire_interval": 1.1, "damage": 95.0,
		"range": 400.0, "hip_spread": 7.0, "ads_spread": 0.0, "zoom_fov": 20.0,
		"heat_per_shot": 0.45, "cool_rate": 0.28, "scope": true,
		"recoil": 1.0, "cam_recoil": 0.045, "mode": FireMode.SEMI,
	},
	Class.HEAVY: {
		"name": "Z-6 Repeater", "fire_interval": 0.075, "damage": 11.0,
		"range": 85.0, "hip_spread": 4.5, "ads_spread": 2.0, "zoom_fov": 62.0,
		"heat_per_shot": 0.06, "cool_rate": 0.22, "scope": false,
		"recoil": 0.22, "cam_recoil": 0.007,
	},
	Class.REVOLVER: {
		"name": "SE-14 Revolver", "fire_interval": 0.42, "damage": 55.0,
		"range": 100.0, "hip_spread": 1.5, "ads_spread": 0.3, "zoom_fov": 55.0,
		"heat_per_shot": 0.22, "cool_rate": 0.3, "scope": false,
		"recoil": 0.9, "cam_recoil": 0.055, "mode": FireMode.SEMI,
	},
	Class.HMG: {
		"name": "T-21 HMG", "fire_interval": 0.05, "damage": 13.0,
		"range": 110.0, "hip_spread": 5.5, "ads_spread": 2.5, "zoom_fov": 60.0,
		"heat_per_shot": 0.042, "cool_rate": 0.18, "scope": false,
		"recoil": 0.28, "cam_recoil": 0.009,
	},
	Class.BURST: {
		"name": "EL-16 Burst", "fire_interval": 0.42, "damage": 24.0,
		"range": 140.0, "hip_spread": 1.6, "ads_spread": 0.15, "zoom_fov": 50.0,
		"heat_per_shot": 0.09, "cool_rate": 0.3, "scope": false,
		"recoil": 0.5, "cam_recoil": 0.018,
		"mode": FireMode.BURST, "burst_count": 3, "burst_interval": 0.06,
	},
	Class.SEMI: {
		"name": "A280 Semi", "fire_interval": 0.2, "damage": 42.0,
		"range": 200.0, "hip_spread": 1.0, "ads_spread": 0.0, "zoom_fov": 45.0,
		"heat_per_shot": 0.11, "cool_rate": 0.3, "scope": false,
		"recoil": 0.6, "cam_recoil": 0.024, "mode": FireMode.SEMI,
	},
	Class.PISTOL: {
		"name": "DL-44 Pistol", "fire_interval": 0.26, "damage": 32.0,
		"range": 90.0, "hip_spread": 1.8, "ads_spread": 0.35, "zoom_fov": 56.0,
		"heat_per_shot": 0.13, "cool_rate": 0.34, "scope": false,
		"recoil": 0.65, "cam_recoil": 0.028, "mode": FireMode.SEMI,
	},
	Class.RPG: {
		"name": "PLX-1 RPG", "fire_interval": 1.6, "damage": 0.0,
		"range": 300.0, "hip_spread": 0.5, "ads_spread": 0.0, "zoom_fov": 60.0,
		"heat_per_shot": 0.6, "cool_rate": 0.3, "scope": false,
		"recoil": 1.2, "cam_recoil": 0.08, "mode": FireMode.SEMI,
		"projectile": true, "splash": 4.5, "splash_damage": 95.0,
	},
}

# Purchased upgrades (Loadout.UPGRADES) as multipliers on the base profile.
const SCOPE_ZOOM_MULT := 0.6    # smaller FOV = more magnification
const COOLING_HEAT_MULT := 0.75
const COOLING_RATE_MULT := 1.25
const GRIP_SPREAD_MULT := 0.65  # bloom derives from hip_spread, so it shrinks too

const BOLT_SCENE := preload("res://scenes/fx/blaster_bolt.tscn")
const ROCKET_SCENE := preload("res://scenes/fx/rocket.tscn")
const OVERHEAT_RELEASE := 0.35  # heat must fall below this to fire again
const HEADSHOT_MULT := 2.0

var weapon_class: Class = Class.SOLDIER
var aiming := false
var shooter: CollisionObject3D  # the owning player; set by Player
var mods := {}                  # the upgrades this gun was bought with

var _profile: Dictionary = PROFILES[Class.SOLDIER]
var _cooldown := 0.0
var _heat := 0.0
var _overheated := false
var _burst_left := 0
var _bloom := 0.0  # extra hip-fire spread (deg) built up by sustained fire

@onready var _viewmodel: Node3D = get_node_or_null("Viewmodel")


## Equip a gun. `upgrades` is Loadout.weapon_mods() — the flags are folded into
## a private copy of the profile, so the shared PROFILES table stays pristine
## and everything downstream (spread, heat, scope) just reads _profile.
func set_class(c: Class, upgrades := {}) -> void:
	weapon_class = c
	mods = upgrades
	_profile = _upgraded_profile(PROFILES[c], upgrades)
	# Swapping vents heat and cancels any in-flight burst.
	_heat = 0.0
	_overheated = false
	_burst_left = 0
	_bloom = 0.0
	heat_changed.emit(_heat, _overheated)
	if _viewmodel:
		_viewmodel.configure(c, has_scope())


func _upgraded_profile(base: Dictionary, upgrades: Dictionary) -> Dictionary:
	if upgrades.is_empty():
		return base
	var p := base.duplicate()
	if upgrades.get("scope", false):
		p["scope"] = true
		p["zoom_fov"] = float(p["zoom_fov"]) * SCOPE_ZOOM_MULT
	if upgrades.get("cooling", false):
		p["heat_per_shot"] = float(p["heat_per_shot"]) * COOLING_HEAT_MULT
		p["cool_rate"] = float(p["cool_rate"]) * COOLING_RATE_MULT
	if upgrades.get("grip", false):
		p["hip_spread"] = float(p["hip_spread"]) * GRIP_SPREAD_MULT
	return p


func display_name() -> String:
	return _profile["name"]


## Current heat, 0..1. Bots read it to keep off the trigger before they lock out.
func heat() -> float:
	return _heat


func zoom_fov() -> float:
	return _profile["zoom_fov"]


func has_scope() -> bool:
	return _profile["scope"]


## The spread cone half-angle (deg) a shot would use right now — hip fire adds
## the accumulated bloom, aiming stays tight. Used by the bloom crosshair.
func current_spread_deg() -> float:
	if aiming:
		return _profile["ads_spread"]
	return _profile["hip_spread"] + _bloom


# Fixed-timestep so heat/cooldown/burst behave identically regardless of render
# framerate (important on the Pi) and on the same clock as firing.
func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	# Bloom recovers when not actively spraying (scaled to the weapon's spread).
	if _bloom > 0.0:
		_bloom = maxf(_bloom - _profile["hip_spread"] * 4.0 * delta, 0.0)
	if _heat > 0.0:
		_heat = maxf(_heat - _profile["cool_rate"] * delta, 0.0)
		if _overheated and _heat <= OVERHEAT_RELEASE:
			_overheated = false
		heat_changed.emit(_heat, _overheated)
	# Pump queued burst shots on their own short interval.
	if _burst_left > 0 and _can_fire():
		_fire_shot()
		_burst_left -= 1
		_cooldown = _profile["burst_interval"] if _burst_left > 0 else _profile["fire_interval"]


## Drive firing from the player each physics frame. `held` = trigger down now,
## `pressed` = trigger went down this frame (edge). Call only from physics.
func update_fire(held: bool, pressed: bool) -> void:
	match _profile.get("mode", FireMode.AUTO):
		FireMode.AUTO:
			if held:
				_try_shot()
		FireMode.SEMI:
			if pressed:
				_try_shot()
		FireMode.BURST:
			if pressed and _burst_left == 0 and _can_fire():
				_burst_left = _profile.get("burst_count", 3)


func _can_fire() -> bool:
	return _cooldown <= 0.0 and not _overheated


func _try_shot() -> void:
	if not _can_fire():
		return
	_cooldown = _profile["fire_interval"]
	_fire_shot()


func _fire_shot() -> void:
	_heat = minf(_heat + _profile["heat_per_shot"], 1.0)
	if _heat >= 1.0:
		_overheated = true
	heat_changed.emit(_heat, _overheated)
	if _viewmodel:
		_viewmodel.kick(_profile["recoil"])
	fired.emit(_profile["cam_recoil"])
	# Hip fire blooms the cone; aiming down sights stays precise.
	if not aiming:
		_bloom = minf(_bloom + _profile["hip_spread"] * 0.4, _profile["hip_spread"] * 2.2)
	if _profile.get("projectile", false):
		_fire_rocket()
	else:
		_fire_hitscan()


func _fire_hitscan() -> void:
	var from := global_position
	var dir := -global_transform.basis.z
	var spread := current_spread_deg()
	if spread > 0.0:
		var rad := deg_to_rad(spread)
		dir = dir.rotated(global_transform.basis.x, randf_range(-rad, rad))
		dir = dir.rotated(global_transform.basis.y, randf_range(-rad, rad))
	var to := from + dir * float(_profile["range"])

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	var end: Vector3 = hit.get("position", to)
	var col = hit.get("collider")
	if col != null and col.has_method("take_damage"):
		var dmg: float = _profile["damage"]
		if col.has_method("is_headshot") and col.is_headshot(end):
			dmg *= HEADSHOT_MULT
		col.take_damage(dmg, shooter)

	var bolt := BOLT_SCENE.instantiate()
	get_tree().current_scene.add_child(bolt)
	bolt.launch(from - global_transform.basis.y * 0.12, end)


func _fire_rocket() -> void:
	var rocket := ROCKET_SCENE.instantiate()
	get_tree().current_scene.add_child(rocket)
	rocket.launch(global_position, -global_transform.basis.z, shooter,
		_profile["splash"], _profile["splash_damage"], _profile["range"])
