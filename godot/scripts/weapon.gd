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
## shot emits `fired(cam_recoil, kick_back)` so the shooter can kick its own
## camera and get shoved backwards. Heat replaces ammo: shots add heat, 1.0
## overheats and locks out until it cools below OVERHEAT_RELEASE.

signal heat_changed(heat: float, overheated: bool)
signal fired(cam_recoil: float, kick_back: float)

enum Class {
	SOLDIER, SNIPER, HEAVY, REVOLVER, HMG, BURST, SEMI, RPG, PISTOL, HOLDOUT,
	ROTARY, TURRET,
	SMG, CARBINE, SCATTERGUN, DMR,   # primaries
	DH17, BRYAR,                     # sidearms
	SABER,                           # the Force adept's melee primary
	BOWCASTER,                       # the Wookiee's sidearm, and only theirs
}
enum FireMode { AUTO, SEMI, BURST }

# spread = fire-cone half-angle (deg); zoom_fov = FOV while aiming; heat_per_shot
# / cool_rate are fractions of the 0..1 heat pool; recoil = viewmodel kick;
# cam_recoil = camera pitch kick (radians). Optional keys default via .get():
# mode (AUTO), burst_count/burst_interval (BURST), projectile/splash* (RPG),
# kick_back (m/s the shot shoves the shooter backwards — big guns only).
#
# On kickback: cam_recoil is per shot and settles back at Player.RECOIL_RECOVER,
# so what a gun actually costs you is roughly cam_recoil / (fire_interval *
# RECOIL_RECOVER) of steady climb — a fast gun pays for its rate of fire. The
# fixed cost of one shot (a single-shot gun's whole recoil) is cam_recoil
# itself. Aiming and crouching scale both down; see Player.
const PROFILES := {
	Class.SOLDIER: {
		"name": "DC-15 Rifle", "fire_interval": 0.14, "damage": 20.0,
		"range": 120.0, "hip_spread": 2.5, "ads_spread": 0.4, "zoom_fov": 48.0,
		"heat_per_shot": 0.085, "cool_rate": 0.26, "scope": false,
		"recoil": 0.55, "cam_recoil": 0.046,
	},
	Class.SNIPER: {
		"name": "NT-242 Sniper", "fire_interval": 1.1, "damage": 95.0,
		"range": 400.0, "hip_spread": 7.0, "ads_spread": 0.0, "zoom_fov": 20.0,
		"heat_per_shot": 0.45, "cool_rate": 0.28, "scope": true,
		"recoil": 1.5, "cam_recoil": 0.20, "kick_back": 3.0,
		"mode": FireMode.SEMI,
	},
	Class.HEAVY: {
		"name": "Z-6 Repeater", "fire_interval": 0.075, "damage": 11.0,
		"range": 85.0, "hip_spread": 4.5, "ads_spread": 2.0, "zoom_fov": 62.0,
		"heat_per_shot": 0.06, "cool_rate": 0.22, "scope": false,
		"recoil": 0.34, "cam_recoil": 0.032,
	},
	Class.REVOLVER: {
		"name": "SE-14 Revolver", "fire_interval": 0.42, "damage": 55.0,
		"range": 100.0, "hip_spread": 1.5, "ads_spread": 0.3, "zoom_fov": 55.0,
		"heat_per_shot": 0.22, "cool_rate": 0.3, "scope": false,
		"recoil": 1.3, "cam_recoil": 0.22, "kick_back": 1.6,
		"mode": FireMode.SEMI,
	},
	# The HMG's cooling is double every other gun's relative to its output: it is
	# the one weapon meant to keep firing, so the lockout it earns is short.
	Class.HMG: {
		"name": "T-21 HMG", "fire_interval": 0.05, "damage": 13.0,
		"range": 110.0, "hip_spread": 5.5, "ads_spread": 2.5, "zoom_fov": 60.0,
		"heat_per_shot": 0.042, "cool_rate": 0.36, "scope": false,
		"recoil": 0.42, "cam_recoil": 0.040,
	},
	Class.BURST: {
		"name": "EL-16 Burst", "fire_interval": 0.42, "damage": 24.0,
		"range": 140.0, "hip_spread": 1.6, "ads_spread": 0.15, "zoom_fov": 50.0,
		"heat_per_shot": 0.09, "cool_rate": 0.3, "scope": false,
		"recoil": 0.75, "cam_recoil": 0.080,
		"mode": FireMode.BURST, "burst_count": 3, "burst_interval": 0.06,
	},
	Class.SEMI: {
		"name": "A280 Semi", "fire_interval": 0.2, "damage": 42.0,
		"range": 200.0, "hip_spread": 1.0, "ads_spread": 0.0, "zoom_fov": 45.0,
		"heat_per_shot": 0.11, "cool_rate": 0.3, "scope": false,
		"recoil": 0.9, "cam_recoil": 0.105, "kick_back": 1.0,
		"mode": FireMode.SEMI,
	},
	Class.PISTOL: {
		"name": "DL-44 Pistol", "fire_interval": 0.26, "damage": 32.0,
		"range": 90.0, "hip_spread": 1.8, "ads_spread": 0.35, "zoom_fov": 56.0,
		"heat_per_shot": 0.13, "cool_rate": 0.34, "scope": false,
		"recoil": 0.95, "cam_recoil": 0.118, "mode": FireMode.SEMI,
	},
	Class.HOLDOUT: {
		"name": "RK-3 Holdout", "fire_interval": 0.16, "damage": 19.0,
		"range": 70.0, "hip_spread": 2.4, "ads_spread": 0.7, "zoom_fov": 58.0,
		"heat_per_shot": 0.075, "cool_rate": 0.4, "scope": false,
		"recoil": 0.6, "cam_recoil": 0.061,
	},
	# The rotary gadget's gun: enormous sustained output, but it has to spin up
	# first and it sprays, and carrying it slows you to a walk.
	Class.ROTARY: {
		"name": "R-90 Rotary", "fire_interval": 0.04, "damage": 12.0,
		"range": 95.0, "hip_spread": 4.0, "ads_spread": 2.2, "zoom_fov": 64.0,
		"heat_per_shot": 0.022, "cool_rate": 0.20, "scope": false,
		"recoil": 0.32, "cam_recoil": 0.028, "spinup": 0.7,
	},
	# What a placed turret shoots with. It's bolted to the floor, so it has a
	# viewmodel kick nobody sees and no camera kick or shove at all.
	Class.TURRET: {
		"name": "E-Web Turret", "fire_interval": 0.18, "damage": 18.0,
		"range": 60.0, "hip_spread": 1.2, "ads_spread": 1.2, "zoom_fov": 70.0,
		"heat_per_shot": 0.05, "cool_rate": 0.28, "scope": false,
		"recoil": 0.45, "cam_recoil": 0.0,
	},
	Class.RPG: {
		"name": "PLX-1 RPG", "fire_interval": 1.6, "damage": 0.0,
		"range": 300.0, "hip_spread": 0.5, "ads_spread": 0.0, "zoom_fov": 60.0,
		"heat_per_shot": 0.6, "cool_rate": 0.3, "scope": false,
		"recoil": 1.8, "cam_recoil": 0.30, "kick_back": 5.5,
		"mode": FireMode.SEMI,
		"projectile": true, "splash": 4.5, "splash_damage": 95.0,
	},
	# The cheap primary: it spits, but every round is a pinprick and the cone
	# opens up fast, so it is a room-clearer rather than a rifle.
	Class.SMG: {
		"name": "Westar M5 SMG", "fire_interval": 0.07, "damage": 12.0,
		"range": 55.0, "hip_spread": 3.6, "ads_spread": 1.4, "zoom_fov": 64.0,
		"heat_per_shot": 0.05, "cool_rate": 0.30, "scope": false,
		"recoil": 0.3, "cam_recoil": 0.030,
	},
	# Between the SMG and the DC-15: a shorter, faster rifle that gives up range.
	Class.CARBINE: {
		"name": "DC-15S Carbine", "fire_interval": 0.11, "damage": 16.0,
		"range": 90.0, "hip_spread": 2.2, "ads_spread": 0.35, "zoom_fov": 52.0,
		"heat_per_shot": 0.07, "cool_rate": 0.28, "scope": false,
		"recoil": 0.45, "cam_recoil": 0.038,
	},
	# Pellets, not a bullet: devastating inside a room and near-useless past it.
	# `pellets` rolls the spread cone once per pellet — see _fire_hitscan.
	#
	# The cone is tighter than a shotgun's reputation suggests, because spread is
	# applied as two INDEPENDENT rotations, so the effective corner of the cone
	# is ~1.4x the number here. At 3.2 it measures ~109 dmg/pull at 3.5 m (a
	# one-shot kill, pellets landing in the head band count double) falling to
	# ~18 with half the pulls missing entirely by 12 m. The falloff is the point;
	# being unable to hit anything up close is not.
	Class.SCATTERGUN: {
		"name": "FWMB-10 Scatter", "fire_interval": 0.85, "damage": 12.0,
		"range": 26.0, "hip_spread": 3.2, "ads_spread": 2.0, "zoom_fov": 66.0,
		"heat_per_shot": 0.30, "cool_rate": 0.34, "scope": false,
		"recoil": 1.4, "cam_recoil": 0.175, "kick_back": 2.2,
		"mode": FireMode.SEMI, "pellets": 7,
	},
	# Scoped as issued, so it is pinpoint on the glass without buying a sight —
	# the cheaper, faster-firing alternative to the bolt-action sniper.
	Class.DMR: {
		"name": "A280-CFE Marksman", "fire_interval": 0.55, "damage": 62.0,
		"range": 250.0, "hip_spread": 2.4, "ads_spread": 0.0, "zoom_fov": 32.0,
		"heat_per_shot": 0.30, "cool_rate": 0.30, "scope": true,
		"recoil": 1.1, "cam_recoil": 0.140, "kick_back": 1.4,
		"mode": FireMode.SEMI,
	},
	# Sidearms. The DH-17 is the only automatic one, which is what makes it the
	# sidearm worth dual-wielding.
	Class.DH17: {
		"name": "DH-17 Sidearm", "fire_interval": 0.17, "damage": 17.0,
		"range": 60.0, "hip_spread": 2.6, "ads_spread": 0.8, "zoom_fov": 58.0,
		"heat_per_shot": 0.075, "cool_rate": 0.36, "scope": false,
		"recoil": 0.5, "cam_recoil": 0.049,
	},
	Class.BRYAR: {
		"name": "Bryar Pistol", "fire_interval": 0.5, "damage": 58.0,
		"range": 120.0, "hip_spread": 1.2, "ads_spread": 0.1, "zoom_fov": 50.0,
		"heat_per_shot": 0.28, "cool_rate": 0.32, "scope": false,
		"recoil": 1.15, "cam_recoil": 0.160, "kick_back": 1.2,
		"mode": FireMode.SEMI,
	},
	# The lightsaber: the Force adept's only primary, and the only MELEE weapon.
	# It is still a hitscan — a ray three metres long — so it needs no new code
	# path anywhere, it just cannot reach. That range is the entire balance of
	# the class: it hits harder than any rifle and kills a standard trooper in
	# two swings, but every one of them is a decision to close.
	#
	# No heat: a blade does not overheat, and the exhaustion that limits the
	# class is the BLOCK pool on Player, not the trigger.
	Class.SABER: {
		"name": "Lightsaber", "fire_interval": 0.40, "damage": 55.0,
		"range": 3.4, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 75.0,
		"heat_per_shot": 0.0, "cool_rate": 1.0, "scope": false,
		"recoil": 1.1, "cam_recoil": 0.022, "melee": true,
	},
	# The Wookiee's sidearm: a crossbow that throws a spread of energy quarrels.
	# Three pellets through one cone, which is the scattergun's mechanism and
	# needs no new code — the damage is already pooled per target, so one trigger
	# pull is one hit marker and one tick however many quarrels land.
	#
	# It is a SIDEARM that hits like a primary (78 on a clean hit, more than a
	# rifle's four rounds) and pays for it in everything else: under a shot a
	# second, half a rifle's reach, and a third of the heat pool per pull, so
	# three pulls lock it out. That is deliberate — the class it belongs to is
	# carrying an HMG or a rocket tube in the other hand, and the bowcaster is
	# what it fights with while those are hot or empty of targets.
	#
	# The cone is TIGHT (2.2 hip against the scattergun's 3.2, and remember two
	# independent rotations make the effective corner ~1.4x that) so it stays a
	# weapon at mid range rather than a second shotgun.
	Class.BOWCASTER: {
		"name": "Bowcaster", "fire_interval": 0.9, "damage": 26.0,
		"range": 60.0, "hip_spread": 2.2, "ads_spread": 0.9, "zoom_fov": 58.0,
		"heat_per_shot": 0.34, "cool_rate": 0.30, "scope": false,
		"recoil": 1.5, "cam_recoil": 0.19, "kick_back": 2.6,
		"mode": FireMode.SEMI, "pellets": 3,
	},
}

# Purchased upgrades (Loadout.SIGHTS / UPGRADES) as multipliers on the base
# profile. The holo ring is the cheap sight: a little zoom and a steadier aim,
# with none of the scope's tunnel vision.
const REDDOT_ZOOM_MULT := 0.93    # a reflex sight barely magnifies
const REDDOT_SPREAD_MULT := 0.82  # ...but does steady the aim a little
const HOLO_ZOOM_MULT := 0.85
const HOLO_SPREAD_MULT := 0.7
const SCOPE_ZOOM_MULT := 0.6      # smaller FOV = more magnification
const SCOPE_4X_ZOOM_MULT := 0.3   # ...and the 4x is zoomed much further in
const COOLING_HEAT_MULT := 0.75
const COOLING_RATE_MULT := 1.25
const GRIP_SPREAD_MULT := 0.65     # bloom derives from hip_spread, so it shrinks too
const FOREGRIP_RECOIL_MULT := 0.8  # front grip: -20% kick, the only way to buy it down

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
var _spin := 0.0   # seconds the trigger has been held, for spin-up weapons
## STANCE penalty on the cone, set by the owning Player each frame: >1 while
## moving or airborne, <1 while crouched, 1 standing still. Left at 1 for bots,
## which have their own aim-error model and never touch this.
var stance_spread_mult := 1.0

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
	_spin = 0.0
	heat_changed.emit(_heat, _overheated)
	if _viewmodel:
		_viewmodel.configure(c, has_scope(), has_holo())


func _upgraded_profile(base: Dictionary, upgrades: Dictionary) -> Dictionary:
	if upgrades.is_empty():
		return base
	var p := base.duplicate()
	# A fitted sight REPLACES whatever optics the gun shipped with (the sniper's
	# scope), it never stacks — two sights on one rail is nobody's intent. So the
	# clear-view optics clear `scope` and the scopes set it: has_scope() is what
	# grants pinpoint accuracy, so a gun that shows no scope must not shoot like
	# one, and vice versa.
	var sight: int = upgrades.get("sight", 0)
	match sight:
		Loadout.Sight.RED_DOT:
			# A clear-view dot: the viewmodel treats it like the ring, the HUD
			# draws a dot instead (has_reddot), and it barely magnifies.
			p["holo"] = true
			p["reddot"] = true
			p["scope"] = false
			p["zoom_fov"] = float(p["zoom_fov"]) * REDDOT_ZOOM_MULT
			p["ads_spread"] = float(p["ads_spread"]) * REDDOT_SPREAD_MULT
		Loadout.Sight.HOLO, Loadout.Sight.THERMAL:
			# The thermal holo aims EXACTLY like the ordinary ring — the heat read
			# is a HUD flag, not a ballistic one — so it shares this branch and
			# only marks itself.
			p["holo"] = true
			p["scope"] = false
			p["zoom_fov"] = float(p["zoom_fov"]) * HOLO_ZOOM_MULT
			p["ads_spread"] = float(p["ads_spread"]) * HOLO_SPREAD_MULT
			if sight == Loadout.Sight.THERMAL:
				p["thermal"] = true
		Loadout.Sight.SCOPE:
			p["scope"] = true
			p["zoom_fov"] = float(p["zoom_fov"]) * SCOPE_ZOOM_MULT
		Loadout.Sight.SCOPE_4X:
			p["scope"] = true
			p["zoom_fov"] = float(p["zoom_fov"]) * SCOPE_4X_ZOOM_MULT
	if upgrades.get("cooling", false):
		p["heat_per_shot"] = float(p["heat_per_shot"]) * COOLING_HEAT_MULT
		p["cool_rate"] = float(p["cool_rate"]) * COOLING_RATE_MULT
	# GRIP steadies HIP FIRE only now; the front grip (below) took the recoil.
	if upgrades.get("grip", false):
		p["hip_spread"] = float(p["hip_spread"]) * GRIP_SPREAD_MULT
	# FRONT GRIP tames the kick — the camera climb, the viewmodel kick, and the
	# body shove of the heavy guns — and touches nothing about accuracy.
	if upgrades.get("foregrip", false):
		p["recoil"] = float(p["recoil"]) * FOREGRIP_RECOIL_MULT
		p["cam_recoil"] = float(p["cam_recoil"]) * FOREGRIP_RECOIL_MULT
		p["kick_back"] = float(p.get("kick_back", 0.0)) * FOREGRIP_RECOIL_MULT
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


## A hollow ring sight: aims without blacking out the view, so it gets a ring
## reticle rather than the scope overlay.
func has_holo() -> bool:
	return _profile.get("holo", false)


## The reflex dot: a clear-view optic like the holo (so has_holo is also true and
## the viewmodel/no-blackout logic is shared), but the HUD draws a dot for it
## rather than a ring.
func has_reddot() -> bool:
	return _profile.get("reddot", false)


## The Trandoshan's thermal ring: aims like a holo, but the HUD paints enemy
## heat through smoke while it is raised. Load-bearing for the heat overlay in
## Main, nothing else.
func has_thermal() -> bool:
	return _profile.get("thermal", false)


## A blade rather than a gun: same hitscan, no tracer, no muzzle flash, and no
## sights to raise — the aim control blocks with it instead (see Player).
func is_melee() -> bool:
	return _profile.get("melee", false)


## How far this weapon can actually reach. Bots read it so they never sit at
## their preferred stand-off range holding a weapon that cannot get there.
func max_range() -> float:
	return _profile["range"]


## The spread cone half-angle (deg) a shot would use right now — hip fire adds
## the accumulated bloom, aiming stays tight. Used by the bloom crosshair.
##
## A scope is an absolute promise, not a modifier: while you are on the glass
## the shot goes exactly where the reticle is, on whatever gun it is bolted to.
## The rule lives here rather than as a zeroed `ads_spread` in the table so it
## also covers guns that ship with optics, and so it cannot be quietly undone by
## a future profile that sets a spread alongside "scope": true.
func current_spread_deg() -> float:
	# A scope is pinpoint while aimed no matter the stance — that rule is
	# absolute (see the class docs), so the multiplier below never touches its 0.
	var base: float = 0.0 if (aiming and has_scope()) \
		else (_profile["ads_spread"] if aiming else _profile["hip_spread"] + _bloom)
	# Stance widens the cone on the move and tightens it crouched. The HUD bloom
	# crosshair reads this same value, so the reticle blooms as you run and
	# settles as you stand — the accuracy penalty is legible, not hidden.
	return base * stance_spread_mult


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
	# Spin-up weapons wind the barrels before the first round leaves.
	var spinup: float = _profile.get("spinup", 0.0)
	if spinup > 0.0:
		var step := get_physics_process_delta_time()
		_spin = clampf(_spin + (step if held else -step * 2.0), 0.0, spinup)
		if _spin < spinup:
			return
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


## Which render layer this weapon's first-person model belongs on. Set by the
## owning Player to its own private viewmodel bit; the viewmodel re-applies it
## every time it rebuilds itself, which is what a straight `mi.layers = ...` at
## spawn could not do. Harmless on a bot, which has no viewmodel at all.
func set_view_layer(bits: int) -> void:
	if _viewmodel and "view_layer" in _viewmodel:
		_viewmodel.view_layer = bits
		_viewmodel._apply_view_layer()


## The owner's guard just stopped a hit; show it on the blade. Forwarded rather
## than reached for, because the viewmodel is this node's private child — Player
## knows about the block, and Weapon is the one thing that knows where the model
## holding it lives.
func parry() -> void:
	if _viewmodel and _viewmodel.has_method("parry"):
		_viewmodel.parry()


func _fire_shot() -> void:
	_heat = minf(_heat + _profile["heat_per_shot"], 1.0)
	if _heat >= 1.0:
		_overheated = true
	heat_changed.emit(_heat, _overheated)
	if _viewmodel:
		_viewmodel.kick(_profile["recoil"])
	fired.emit(_profile["cam_recoil"], _profile.get("kick_back", 0.0))
	# Hip fire blooms the cone; aiming down sights stays precise.
	if not aiming:
		_bloom = minf(_bloom + _profile["hip_spread"] * 0.4, _profile["hip_spread"] * 2.2)
	if _profile.get("projectile", false):
		_fire_rocket()
	else:
		_fire_hitscan()


## One trigger pull. Most guns fire a single ray; a scattergun fires `pellets`
## of them through the same cone.
##
## Damage is POOLED per target rather than applied per pellet: seven separate
## take_damage calls would fire seven hit-ticks and seven markers for one shot,
## and would also let a single pellet's headshot flag decide the whole shot. A
## pellet that lands on a head still counts double, but the target is told once.
func _fire_hitscan() -> void:
	var from := global_position
	var muzzle := from - global_transform.basis.y * 0.12
	var pellets: int = _profile.get("pellets", 1)
	var damage: float = _profile["damage"]
	var pooled := {}   # target -> [damage, any_headshot]
	for i in pellets:
		var end := _trace_pellet(from, pooled, damage)
		# A blade fires no bolt: the swing is the viewmodel's, and a tracer three
		# metres long reads as a misfire rather than a strike.
		if is_melee():
			continue
		var bolt := BOLT_SCENE.instantiate()
		get_tree().current_scene.add_child(bolt)
		bolt.launch(muzzle, end)
	for target in pooled:
		var entry: Array = pooled[target]
		target.take_damage(entry[0], shooter, entry[1])


## Trace one pellet, banking any damage it deals into `pooled`. Returns where it
## stopped, for the tracer.
func _trace_pellet(from: Vector3, pooled: Dictionary, damage: float) -> Vector3:
	var dir := -global_transform.basis.z
	var spread := current_spread_deg()
	if spread > 0.0:
		var rad := deg_to_rad(spread)
		dir = dir.rotated(global_transform.basis.x, randf_range(-rad, rad))
		dir = dir.rotated(global_transform.basis.y, randf_range(-rad, rad))
	var to := from + dir * float(_profile["range"])

	var query := PhysicsRayQueryParameters3D.create(from, to)
	# A shooter can name extra bodies its own fire passes through — the front
	# shield gadget, which blocks everyone else but not its owner.
	query.exclude = shooter.hitscan_exclusions() if shooter.has_method("hitscan_exclusions") \
		else [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	var end: Vector3 = hit.get("position", to)
	var col = hit.get("collider")
	if col != null and col.has_method("take_damage"):
		var dmg := damage
		# The target is told it was a head hit as well as how much it cost, so it
		# can confirm the hit back to the shooter without the shooter having to
		# guess from the damage number.
		var head: bool = col.has_method("is_headshot") and col.is_headshot(end)
		if head:
			dmg *= HEADSHOT_MULT
		var entry: Array = pooled.get_or_add(col, [0.0, false])
		entry[0] += dmg
		entry[1] = entry[1] or head
	return end


func _fire_rocket() -> void:
	var rocket := ROCKET_SCENE.instantiate()
	get_tree().current_scene.add_child(rocket)
	rocket.launch(global_position, -global_transform.basis.z, shooter,
		_profile["splash"], _profile["splash_damage"], _profile["range"])
