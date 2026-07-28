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

## Every gun in the game, ACROSS ALL UNIVERSES. One flat enum on purpose:
## PROFILES is a dictionary keyed by it, so a new weapon shifts nothing, and the
## universe a gun belongs to is stated once in Loadout's catalogue rows rather
## than smeared through the shooting code. Nothing in this file knows or cares
## which universe is being played — a bolter is a hitscan with a heavy round.
enum Class {
	SOLDIER, SNIPER, HEAVY, REVOLVER, HMG, BURST, SEMI, RPG, PISTOL, HOLDOUT,
	ROTARY, TURRET,
	SMG, CARBINE, SCATTERGUN, DMR,   # primaries
	DH17, BRYAR,                     # sidearms
	SABER,                           # the Force adept's melee primary
	BOWCASTER,                       # the Wookiee's sidearm, and only theirs
	WRIST_CANNON,                    # the Super Battle Droid's arm gun (Conquest)
	STAFF,                           # the Magna Guard's electrostaff (Conquest)

	# --- HALO ----------------------------------------------------------------
	# UNSC: ballistic, loud, and accurate in short controlled bursts.
	MA5B, BR55, M7_SMG, M90_SHOTGUN, SRS99, SPNKR, M6D, M247_HMG, M392_DMR,
	SPARTAN_LASER,
	# Covenant: plasma — hotter, softer, and it melts shields rather than plate.
	PLASMA_RIFLE, PLASMA_PISTOL, NEEDLER, COV_CARBINE, BEAM_RIFLE, FUEL_ROD,
	BRUTE_SHOT, MAULER, ENERGY_SWORD, GRAV_HAMMER,

	# --- WARHAMMER 40,000 -----------------------------------------------------
	# Adeptus Astartes: mass-reactive bolts, plasma that cooks its own operator,
	# and chain teeth for whatever survives the walk in.
	BOLTER, HEAVY_BOLTER, STALKER_BOLT, PLASMA_GUN, MELTAGUN, FLAMER,
	BOLT_PISTOL, PLASMA_PISTOL_40K, GRENADE_LAUNCHER,
	CHAINSWORD, POWER_SWORD, THUNDER_HAMMER,
	# Necrons: gauss flays, tesla arcs, and none of it ever jams.
	GAUSS_FLAYER, GAUSS_BLASTER, TESLA_CARBINE, SYNAPTIC_DISINTEGRATOR,
	HEAT_RAY, TRANSDIMENSIONAL_BEAMER, GAUSS_PISTOL, WARSCYTHE, STAFF_OF_LIGHT,
	# Orks: more dakka, less accuracy, and a very large choppy thing.
	SHOOTA, BIG_SHOOTA, SLUGGA, ROKKIT_LAUNCHA, MEGA_BLASTA, BURNA,
	CHOPPA, POWER_KLAW,
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
	# The Super Battle Droid's arm gun (Conquest): an HMG's weight of fire on an
	# AR's frame. It fires nearly as fast as the T-21 and hits between a rifle and
	# that HMG, but its bloom is TIGHT — a low hip_spread, which is what bloom
	# derives from — so unlike the spray-heavy heavies it stays accurate in
	# sustained fire. It is arm-mounted, so no stock and no grip in the silhouette.
	Class.WRIST_CANNON: {
		"name": "Wrist Cannon", "fire_interval": 0.09, "damage": 16.0,
		"range": 115.0, "hip_spread": 1.8, "ads_spread": 0.5, "zoom_fov": 54.0,
		"heat_per_shot": 0.06, "cool_rate": 0.24, "scope": false,
		"recoil": 0.38, "cam_recoil": 0.03,
	},
	# The Magna Guard's ELECTROSTAFF (Conquest): a melee weapon like the saber —
	# hitscan with a `melee` flag that simply cannot reach past its range, so it
	# needs no new code path — but with more REACH (a two-ended pole) and heavier,
	# slower strikes. `staff` flags the pole-and-shield viewmodel; aim raises the
	# same GUARD the saber does, drawn as a shield in the off hand.
	Class.STAFF: {
		"name": "Electrostaff", "fire_interval": 0.45, "damage": 78.0,
		"range": 4.3, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 75.0,
		"heat_per_shot": 0.0, "cool_rate": 1.0, "scope": false,
		"recoil": 1.1, "cam_recoil": 0.02, "melee": true, "staff": true,
	},

	# =========================================================================
	# HALO — UNSC
	# =========================================================================
	# The reason these are here and not a re-skin of the DC-15: a universe's guns
	# are how it FEELS. UNSC weapons are ballistic — they bloom fast, they kick,
	# and they reward the three-round burst; Covenant plasma barely kicks at all
	# and pays for it in heat, which is a mechanic this game already has.
	Class.MA5B: {
		"name": "MA5B Assault Rifle", "fire_interval": 0.085, "damage": 14.0,
		"range": 70.0, "hip_spread": 3.4, "ads_spread": 1.2, "zoom_fov": 62.0,
		"heat_per_shot": 0.048, "cool_rate": 0.30, "scope": false,
		"recoil": 0.38, "cam_recoil": 0.034,
	},
	Class.BR55: {
		"name": "BR55 Battle Rifle", "fire_interval": 0.36, "damage": 22.0,
		"range": 150.0, "hip_spread": 1.5, "ads_spread": 0.12, "zoom_fov": 44.0,
		"heat_per_shot": 0.085, "cool_rate": 0.30, "scope": false,
		"recoil": 0.72, "cam_recoil": 0.074,
		"mode": FireMode.BURST, "burst_count": 3, "burst_interval": 0.055,
	},
	Class.M7_SMG: {
		"name": "M7 SMG", "fire_interval": 0.06, "damage": 10.0,
		"range": 45.0, "hip_spread": 4.2, "ads_spread": 1.7, "zoom_fov": 66.0,
		"heat_per_shot": 0.042, "cool_rate": 0.32, "scope": false,
		"recoil": 0.28, "cam_recoil": 0.028,
	},
	Class.M90_SHOTGUN: {
		"name": "M90 Shotgun", "fire_interval": 0.82, "damage": 13.0,
		"range": 22.0, "hip_spread": 3.4, "ads_spread": 2.2, "zoom_fov": 68.0,
		"heat_per_shot": 0.30, "cool_rate": 0.34, "scope": false,
		"recoil": 1.45, "cam_recoil": 0.185, "kick_back": 2.4,
		"mode": FireMode.SEMI, "pellets": 8,
	},
	Class.SRS99: {
		"name": "SRS99 Sniper", "fire_interval": 1.15, "damage": 100.0,
		"range": 400.0, "hip_spread": 7.5, "ads_spread": 0.0, "zoom_fov": 19.0,
		"heat_per_shot": 0.46, "cool_rate": 0.28, "scope": true,
		"recoil": 1.6, "cam_recoil": 0.22, "kick_back": 3.2,
		"mode": FireMode.SEMI,
	},
	Class.SPNKR: {
		"name": "M41 SPNKr", "fire_interval": 1.5, "damage": 0.0,
		"range": 300.0, "hip_spread": 0.6, "ads_spread": 0.0, "zoom_fov": 60.0,
		"heat_per_shot": 0.58, "cool_rate": 0.30, "scope": false,
		"recoil": 1.8, "cam_recoil": 0.30, "kick_back": 5.2,
		"mode": FireMode.SEMI,
		"projectile": true, "splash": 4.6, "splash_damage": 95.0,
	},
	Class.M6D: {
		"name": "M6D Magnum", "fire_interval": 0.30, "damage": 36.0,
		"range": 95.0, "hip_spread": 1.6, "ads_spread": 0.25, "zoom_fov": 46.0,
		"heat_per_shot": 0.16, "cool_rate": 0.34, "scope": false,
		"recoil": 1.05, "cam_recoil": 0.135, "mode": FireMode.SEMI,
	},
	Class.M247_HMG: {
		"name": "M247 Machine Gun", "fire_interval": 0.055, "damage": 14.0,
		"range": 105.0, "hip_spread": 5.6, "ads_spread": 2.6, "zoom_fov": 60.0,
		"heat_per_shot": 0.044, "cool_rate": 0.34, "scope": false,
		"recoil": 0.44, "cam_recoil": 0.042,
	},
	Class.M392_DMR: {
		"name": "M392 DMR", "fire_interval": 0.35, "damage": 40.0,
		"range": 190.0, "hip_spread": 2.0, "ads_spread": 0.0, "zoom_fov": 36.0,
		"heat_per_shot": 0.18, "cool_rate": 0.30, "scope": true,
		"recoil": 0.95, "cam_recoil": 0.118, "mode": FireMode.SEMI,
	},
	# The one gun in the game that has to be CHARGED. `spinup` already exists for
	# the rotary's barrels, and a charge is the same thing said backwards: hold
	# the trigger, nothing happens, then the whole magazine's worth arrives at
	# once. AUTO rather than SEMI because the spin-up gate eats the press edge —
	# a semi-automatic charge weapon would never fire at all.
	Class.SPARTAN_LASER: {
		"flash": Color(1.0, 0.35, 0.30),
		"name": "M6 Spartan Laser", "fire_interval": 1.6, "damage": 180.0,
		"range": 320.0, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 34.0,
		"heat_per_shot": 0.85, "cool_rate": 0.22, "scope": true,
		"recoil": 1.7, "cam_recoil": 0.24, "kick_back": 2.0, "spinup": 1.2,
	},

	# =========================================================================
	# HALO — Covenant
	# =========================================================================
	Class.PLASMA_RIFLE: {
		"flash": Color(0.45, 0.75, 1.0),
		"name": "Plasma Rifle", "fire_interval": 0.10, "damage": 15.0,
		"range": 60.0, "hip_spread": 2.8, "ads_spread": 1.0, "zoom_fov": 62.0,
		"heat_per_shot": 0.075, "cool_rate": 0.26, "scope": false,
		"recoil": 0.26, "cam_recoil": 0.020,
	},
	Class.PLASMA_PISTOL: {
		"flash": Color(0.45, 0.85, 0.7),
		"name": "Plasma Pistol", "fire_interval": 0.22, "damage": 21.0,
		"range": 50.0, "hip_spread": 2.0, "ads_spread": 0.55, "zoom_fov": 58.0,
		"heat_per_shot": 0.11, "cool_rate": 0.30, "scope": false,
		"recoil": 0.4, "cam_recoil": 0.030, "mode": FireMode.SEMI,
	},
	# The needler's crystals track, which this engine has no room for — so what
	# makes it a needler here is VOLUME on a very tight cone: it is the only
	# automatic weapon that stays accurate while you hold it down, and it hurts
	# in proportion to how long you can keep it on somebody.
	Class.NEEDLER: {
		"flash": Color(0.95, 0.45, 1.0),
		"name": "Type-33 Needler", "fire_interval": 0.075, "damage": 11.0,
		"range": 50.0, "hip_spread": 1.3, "ads_spread": 0.5, "zoom_fov": 64.0,
		"heat_per_shot": 0.05, "cool_rate": 0.28, "scope": false,
		"recoil": 0.22, "cam_recoil": 0.016,
	},
	Class.COV_CARBINE: {
		"flash": Color(0.65, 1.0, 0.55),
		"name": "Covenant Carbine", "fire_interval": 0.24, "damage": 30.0,
		"range": 165.0, "hip_spread": 1.4, "ads_spread": 0.1, "zoom_fov": 40.0,
		"heat_per_shot": 0.13, "cool_rate": 0.28, "scope": false,
		"recoil": 0.8, "cam_recoil": 0.090, "mode": FireMode.SEMI,
	},
	Class.BEAM_RIFLE: {
		"flash": Color(0.55, 0.75, 1.0),
		"name": "Particle Beam Rifle", "fire_interval": 1.0, "damage": 92.0,
		"range": 400.0, "hip_spread": 6.5, "ads_spread": 0.0, "zoom_fov": 18.0,
		"heat_per_shot": 0.50, "cool_rate": 0.24, "scope": true,
		"recoil": 1.2, "cam_recoil": 0.14, "mode": FireMode.SEMI,
	},
	Class.FUEL_ROD: {
		"flash": Color(0.55, 1.0, 0.35),
		"name": "Fuel Rod Cannon", "fire_interval": 1.1, "damage": 0.0,
		"range": 220.0, "hip_spread": 1.2, "ads_spread": 0.4, "zoom_fov": 60.0,
		"heat_per_shot": 0.34, "cool_rate": 0.26, "scope": false,
		"recoil": 1.5, "cam_recoil": 0.24, "kick_back": 3.4,
		"mode": FireMode.SEMI,
		"projectile": true, "splash": 3.8, "splash_damage": 72.0,
	},
	Class.BRUTE_SHOT: {
		"name": "Brute Shot", "fire_interval": 0.75, "damage": 0.0,
		"range": 150.0, "hip_spread": 1.8, "ads_spread": 0.8, "zoom_fov": 62.0,
		"heat_per_shot": 0.26, "cool_rate": 0.30, "scope": false,
		"recoil": 1.3, "cam_recoil": 0.19, "kick_back": 2.2,
		"mode": FireMode.SEMI,
		"projectile": true, "splash": 3.0, "splash_damage": 55.0,
	},
	Class.MAULER: {
		"name": "Mauler", "fire_interval": 0.55, "damage": 11.0,
		"range": 18.0, "hip_spread": 3.0, "ads_spread": 2.0, "zoom_fov": 66.0,
		"heat_per_shot": 0.26, "cool_rate": 0.34, "scope": false,
		"recoil": 1.2, "cam_recoil": 0.16, "kick_back": 1.6,
		"mode": FireMode.SEMI, "pellets": 5,
	},
	# The energy sword is the saber's mechanism with a different blade: a melee
	# hitscan that lands on the forward arc. Longer reach than the lightsaber and
	# it kills a standard body outright, which is the lunge everybody remembers.
	Class.ENERGY_SWORD: {
		"name": "Energy Sword", "fire_interval": 0.55, "damage": 95.0,
		"range": 4.0, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 75.0,
		"heat_per_shot": 0.0, "cool_rate": 1.0, "scope": false,
		"recoil": 1.2, "cam_recoil": 0.026, "melee": true,
		"blade_core": Color(0.72, 0.94, 1.0), "blade_glow": Color(0.20, 0.75, 1.0),
		"blade_len": 0.62, "blade_width": 0.055,
	},
	Class.GRAV_HAMMER: {
		"name": "Gravity Hammer", "fire_interval": 0.85, "damage": 120.0,
		"range": 4.4, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 75.0,
		"heat_per_shot": 0.0, "cool_rate": 1.0, "scope": false,
		"recoil": 1.6, "cam_recoil": 0.05, "melee": true,
		"blade_core": Color(0.55, 0.42, 0.30), "blade_glow": Color(0.95, 0.55, 0.15),
		"blade_len": 0.22, "blade_width": 0.17, "hilt_len": 0.55, "blade_energy": 0.0,
	},

	# =========================================================================
	# WARHAMMER 40,000 — Adeptus Astartes
	# =========================================================================
	# A bolt is a rocket-propelled shell that detonates inside the target, so
	# these hit far harder per round than a blaster and fire far slower. The
	# plasma weapons keep the setting's actual joke: they overheat, and the heat
	# pool this game already has is exactly the right place to say so.
	Class.BOLTER: {
		"name": "Godwyn Bolter", "fire_interval": 0.16, "damage": 24.0,
		"range": 110.0, "hip_spread": 2.6, "ads_spread": 0.5, "zoom_fov": 50.0,
		"heat_per_shot": 0.075, "cool_rate": 0.26, "scope": false,
		"recoil": 0.85, "cam_recoil": 0.062,
	},
	Class.HEAVY_BOLTER: {
		"name": "Heavy Bolter", "fire_interval": 0.115, "damage": 21.0,
		"range": 125.0, "hip_spread": 4.8, "ads_spread": 2.4, "zoom_fov": 60.0,
		"heat_per_shot": 0.055, "cool_rate": 0.32, "scope": false,
		"recoil": 0.9, "cam_recoil": 0.070, "kick_back": 0.8,
	},
	Class.STALKER_BOLT: {
		"name": "Stalker Bolt Rifle", "fire_interval": 0.42, "damage": 58.0,
		"range": 240.0, "hip_spread": 2.2, "ads_spread": 0.0, "zoom_fov": 30.0,
		"heat_per_shot": 0.26, "cool_rate": 0.30, "scope": true,
		"recoil": 1.15, "cam_recoil": 0.150, "kick_back": 1.4,
		"mode": FireMode.SEMI,
	},
	# Three shots and it is locked out: the plasma gun is a weapon you spend
	# rather than carry, which is the whole of its reputation.
	Class.PLASMA_GUN: {
		"flash": Color(0.55, 0.80, 1.0),
		"name": "Plasma Gun", "fire_interval": 0.70, "damage": 72.0,
		"range": 150.0, "hip_spread": 1.4, "ads_spread": 0.1, "zoom_fov": 44.0,
		"heat_per_shot": 0.36, "cool_rate": 0.18, "scope": false,
		"recoil": 1.3, "cam_recoil": 0.175, "kick_back": 1.2,
		"mode": FireMode.SEMI,
	},
	Class.MELTAGUN: {
		"flash": Color(1.0, 0.55, 0.15),
		"name": "Meltagun", "fire_interval": 1.2, "damage": 145.0,
		"range": 18.0, "hip_spread": 0.8, "ads_spread": 0.0, "zoom_fov": 56.0,
		"heat_per_shot": 0.48, "cool_rate": 0.26, "scope": false,
		"recoil": 1.5, "cam_recoil": 0.20, "kick_back": 1.8,
		"mode": FireMode.SEMI,
	},
	Class.FLAMER: {
		"flash": Color(1.0, 0.50, 0.12),
		"name": "Flamer", "fire_interval": 0.05, "damage": 7.0,
		"range": 14.0, "hip_spread": 7.0, "ads_spread": 6.0, "zoom_fov": 70.0,
		"heat_per_shot": 0.022, "cool_rate": 0.22, "scope": false,
		"recoil": 0.2, "cam_recoil": 0.010, "pellets": 3,
	},
	Class.BOLT_PISTOL: {
		"name": "Bolt Pistol", "fire_interval": 0.32, "damage": 33.0,
		"range": 70.0, "hip_spread": 2.0, "ads_spread": 0.4, "zoom_fov": 54.0,
		"heat_per_shot": 0.16, "cool_rate": 0.32, "scope": false,
		"recoil": 1.0, "cam_recoil": 0.130, "mode": FireMode.SEMI,
	},
	# Named for the chapter rather than the weapon, because Halo has a plasma
	# pistol too and two rows sharing a display name is how a leak between
	# universes hides from the isolation check in tests/kit_rules.gd.
	Class.PLASMA_PISTOL_40K: {
		"flash": Color(0.55, 0.80, 1.0),
		"name": "Astartes Plasma Pistol", "fire_interval": 0.60, "damage": 52.0,
		"range": 85.0, "hip_spread": 1.5, "ads_spread": 0.2, "zoom_fov": 50.0,
		"heat_per_shot": 0.32, "cool_rate": 0.22, "scope": false,
		"recoil": 1.25, "cam_recoil": 0.170, "kick_back": 1.0,
		"mode": FireMode.SEMI,
	},
	Class.GRENADE_LAUNCHER: {
		"name": "Auxiliary Launcher", "fire_interval": 1.3, "damage": 0.0,
		"range": 180.0, "hip_spread": 1.4, "ads_spread": 0.5, "zoom_fov": 58.0,
		"heat_per_shot": 0.40, "cool_rate": 0.28, "scope": false,
		"recoil": 1.4, "cam_recoil": 0.22, "kick_back": 2.0,
		"mode": FireMode.SEMI,
		"projectile": true, "splash": 4.0, "splash_damage": 78.0,
	},
	# Three melee weapons that are deliberately NOT the same weapon. The
	# chainsword is fast and cheap, the power sword trades rate for reach and
	# damage, and the thunder hammer is one swing that ends anybody it touches
	# and leaves you standing still for most of a second if it does not.
	Class.CHAINSWORD: {
		"name": "Chainsword", "fire_interval": 0.34, "damage": 60.0,
		"range": 3.6, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 75.0,
		"heat_per_shot": 0.0, "cool_rate": 1.0, "scope": false,
		"recoil": 1.0, "cam_recoil": 0.024, "melee": true,
		# Steel, not energy: zero emission is what tells the viewmodel to build a
		# dull blade instead of a lit one.
		"blade_core": Color(0.62, 0.63, 0.68), "blade_glow": Color(0.35, 0.30, 0.28),
		"blade_len": 0.72, "blade_width": 0.070, "blade_energy": 0.0,
	},
	Class.POWER_SWORD: {
		"name": "Power Sword", "fire_interval": 0.45, "damage": 88.0,
		"range": 3.9, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 75.0,
		"heat_per_shot": 0.0, "cool_rate": 1.0, "scope": false,
		"recoil": 1.15, "cam_recoil": 0.026, "melee": true,
		"blade_core": Color(0.85, 0.90, 1.0), "blade_glow": Color(0.35, 0.45, 1.0),
		"blade_len": 0.80, "blade_width": 0.052,
	},
	Class.THUNDER_HAMMER: {
		"name": "Thunder Hammer", "fire_interval": 0.95, "damage": 135.0,
		"range": 4.1, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 75.0,
		"heat_per_shot": 0.0, "cool_rate": 1.0, "scope": false,
		"recoil": 1.7, "cam_recoil": 0.055, "melee": true,
		"blade_core": Color(0.48, 0.52, 0.60), "blade_glow": Color(0.40, 0.70, 1.0),
		"blade_len": 0.24, "blade_width": 0.19, "hilt_len": 0.60, "blade_energy": 0.0,
	},

	# =========================================================================
	# WARHAMMER 40,000 — Necrons
	# =========================================================================
	# Gauss strips a target a layer at a time: steady, unhurried, and it never
	# stops. The whole armoury is built low-recoil and long-cooling — a Necron
	# does not flinch, but it also does not hurry.
	Class.GAUSS_FLAYER: {
		"flash": Color(0.45, 1.0, 0.55),
		"name": "Gauss Flayer", "fire_interval": 0.13, "damage": 18.0,
		"range": 95.0, "hip_spread": 2.4, "ads_spread": 0.6, "zoom_fov": 54.0,
		"heat_per_shot": 0.065, "cool_rate": 0.24, "scope": false,
		"recoil": 0.4, "cam_recoil": 0.028,
	},
	Class.GAUSS_BLASTER: {
		"flash": Color(0.45, 1.0, 0.55),
		"name": "Gauss Blaster", "fire_interval": 0.20, "damage": 27.0,
		"range": 135.0, "hip_spread": 1.8, "ads_spread": 0.3, "zoom_fov": 46.0,
		"heat_per_shot": 0.10, "cool_rate": 0.24, "scope": false,
		"recoil": 0.6, "cam_recoil": 0.048,
	},
	Class.TESLA_CARBINE: {
		"flash": Color(0.55, 0.95, 1.0),
		"name": "Tesla Carbine", "fire_interval": 0.12, "damage": 16.0,
		"range": 80.0, "hip_spread": 3.0, "ads_spread": 1.1, "zoom_fov": 58.0,
		"heat_per_shot": 0.055, "cool_rate": 0.30, "scope": false,
		"recoil": 0.35, "cam_recoil": 0.026,
	},
	Class.SYNAPTIC_DISINTEGRATOR: {
		"flash": Color(0.50, 1.0, 0.60),
		"name": "Synaptic Disintegrator", "fire_interval": 1.0, "damage": 88.0,
		"range": 380.0, "hip_spread": 5.5, "ads_spread": 0.0, "zoom_fov": 20.0,
		"heat_per_shot": 0.42, "cool_rate": 0.26, "scope": true,
		"recoil": 1.0, "cam_recoil": 0.10, "mode": FireMode.SEMI,
	},
	Class.HEAT_RAY: {
		"flash": Color(1.0, 0.60, 0.25),
		"name": "Heat Ray", "fire_interval": 0.09, "damage": 22.0,
		"range": 30.0, "hip_spread": 1.6, "ads_spread": 0.8, "zoom_fov": 64.0,
		"heat_per_shot": 0.075, "cool_rate": 0.22, "scope": false,
		"recoil": 0.3, "cam_recoil": 0.020,
	},
	Class.TRANSDIMENSIONAL_BEAMER: {
		"name": "Transdimensional Beamer", "fire_interval": 1.7, "damage": 0.0,
		"range": 300.0, "hip_spread": 0.4, "ads_spread": 0.0, "zoom_fov": 44.0,
		"heat_per_shot": 0.60, "cool_rate": 0.26, "scope": false,
		"recoil": 1.4, "cam_recoil": 0.20, "kick_back": 2.0,
		"mode": FireMode.SEMI,
		"projectile": true, "splash": 4.2, "splash_damage": 88.0,
	},
	Class.GAUSS_PISTOL: {
		"flash": Color(0.45, 1.0, 0.55),
		"name": "Gauss Pistol", "fire_interval": 0.30, "damage": 34.0,
		"range": 80.0, "hip_spread": 1.7, "ads_spread": 0.35, "zoom_fov": 54.0,
		"heat_per_shot": 0.15, "cool_rate": 0.30, "scope": false,
		"recoil": 0.7, "cam_recoil": 0.080, "mode": FireMode.SEMI,
	},
	# A polearm, so it uses the electrostaff's silhouette rather than the saber's.
	Class.WARSCYTHE: {
		"name": "Warscythe", "fire_interval": 0.55, "damage": 98.0,
		"range": 4.5, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 75.0,
		"heat_per_shot": 0.0, "cool_rate": 1.0, "scope": false,
		"recoil": 1.2, "cam_recoil": 0.028, "melee": true, "staff": true,
		"blade_core": Color(0.70, 1.0, 0.72), "blade_glow": Color(0.20, 0.95, 0.35),
	},
	Class.STAFF_OF_LIGHT: {
		"name": "Staff of Light", "fire_interval": 0.42, "damage": 74.0,
		"range": 4.2, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 75.0,
		"heat_per_shot": 0.0, "cool_rate": 1.0, "scope": false,
		"recoil": 1.0, "cam_recoil": 0.022, "melee": true, "staff": true,
		"blade_core": Color(0.75, 1.0, 0.80), "blade_glow": Color(0.30, 1.0, 0.50),
	},

	# =========================================================================
	# WARHAMMER 40,000 — Orks
	# =========================================================================
	# The Orks pay for everything in accuracy. Every one of these throws more
	# metal than its counterpart elsewhere and lands less of it, which makes the
	# faction's answer to any problem "get closer" — and that is the point.
	Class.SHOOTA: {
		"name": "Shoota", "fire_interval": 0.085, "damage": 16.0,
		"range": 55.0, "hip_spread": 5.2, "ads_spread": 2.4, "zoom_fov": 66.0,
		"heat_per_shot": 0.05, "cool_rate": 0.30, "scope": false,
		"recoil": 0.55, "cam_recoil": 0.044,
	},
	Class.BIG_SHOOTA: {
		"name": "Big Shoota", "fire_interval": 0.055, "damage": 15.0,
		"range": 75.0, "hip_spread": 6.4, "ads_spread": 3.4, "zoom_fov": 66.0,
		"heat_per_shot": 0.040, "cool_rate": 0.34, "scope": false,
		"recoil": 0.6, "cam_recoil": 0.050, "kick_back": 0.6,
	},
	Class.SLUGGA: {
		"name": "Slugga", "fire_interval": 0.26, "damage": 30.0,
		"range": 45.0, "hip_spread": 3.2, "ads_spread": 1.2, "zoom_fov": 62.0,
		"heat_per_shot": 0.14, "cool_rate": 0.34, "scope": false,
		"recoil": 1.0, "cam_recoil": 0.115, "mode": FireMode.SEMI,
	},
	Class.ROKKIT_LAUNCHA: {
		"name": "Rokkit Launcha", "fire_interval": 1.8, "damage": 0.0,
		"range": 260.0, "hip_spread": 2.5, "ads_spread": 1.4, "zoom_fov": 62.0,
		"heat_per_shot": 0.62, "cool_rate": 0.30, "scope": false,
		"recoil": 2.0, "cam_recoil": 0.34, "kick_back": 6.0,
		"mode": FireMode.SEMI,
		"projectile": true, "splash": 5.0, "splash_damage": 100.0,
	},
	Class.MEGA_BLASTA: {
		"flash": Color(0.60, 0.90, 1.0),
		"name": "Kustom Mega-Blasta", "fire_interval": 0.9, "damage": 78.0,
		"range": 120.0, "hip_spread": 2.6, "ads_spread": 0.9, "zoom_fov": 52.0,
		"heat_per_shot": 0.44, "cool_rate": 0.18, "scope": false,
		"recoil": 1.5, "cam_recoil": 0.21, "kick_back": 1.6,
		"mode": FireMode.SEMI,
	},
	Class.BURNA: {
		"flash": Color(1.0, 0.50, 0.12),
		"name": "Burna", "fire_interval": 0.055, "damage": 8.0,
		"range": 15.0, "hip_spread": 7.5, "ads_spread": 6.5, "zoom_fov": 70.0,
		"heat_per_shot": 0.024, "cool_rate": 0.22, "scope": false,
		"recoil": 0.22, "cam_recoil": 0.012, "pellets": 3,
	},
	Class.CHOPPA: {
		"name": "Choppa", "fire_interval": 0.36, "damage": 68.0,
		"range": 3.6, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 75.0,
		"heat_per_shot": 0.0, "cool_rate": 1.0, "scope": false,
		"recoil": 1.05, "cam_recoil": 0.026, "melee": true,
		"blade_core": Color(0.58, 0.56, 0.52), "blade_glow": Color(0.30, 0.26, 0.22),
		"blade_len": 0.66, "blade_width": 0.085, "blade_energy": 0.0,
	},
	Class.POWER_KLAW: {
		"name": "Power Klaw", "fire_interval": 0.80, "damage": 118.0,
		"range": 3.5, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 75.0,
		"heat_per_shot": 0.0, "cool_rate": 1.0, "scope": false,
		"recoil": 1.5, "cam_recoil": 0.048, "melee": true,
		"blade_core": Color(0.55, 0.50, 0.42), "blade_glow": Color(0.20, 0.85, 0.95),
		"blade_len": 0.30, "blade_width": 0.15, "hilt_len": 0.28, "blade_energy": 0.0,
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
const IMPACT := preload("res://scripts/impact.gd")
## How many impact bursts one trigger pull may spawn. A scattergun throws eight
## pellets and eight simultaneous bursts on one wall is both a waste and a
## visual mess — the first few read as the shot, the rest are noise.
const IMPACTS_PER_SHOT := 3
## ...and nothing is spawned for a hit no human could possibly see. In a 4v4 most
## rounds fired in a match are bots shooting at bots somewhere else on a 220 m
## map, and every one of those was building a burst, running it for a quarter of
## a second and freeing it with nobody watching. Generous enough that a sniper
## still sees where their round landed.
const IMPACT_VIEW_RANGE := 120.0
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

## --- muzzle flash -------------------------------------------------------------
##
## A REAL LIGHT at the muzzle, not just a bright quad on the viewmodel. This is
## the best realism-per-line in the game: a shot that lights the wall beside you,
## the floor under you and the man you are shooting at reads as an explosion in a
## barrel, where an emissive sprite reads as a sticker. It is also the only
## dynamic light most of these maps ever get.
##
## Built ONCE and toggled, never allocated per shot — the project's per-frame
## allocation rule, and a repeater fires thirteen times a second. Shadows off:
## a shadow-casting light per bullet would be four shadow passes a shot.
const FLASH_TIME := 0.055     # seconds; about one frame at 60, plus a little
const FLASH_ENERGY := 2.2
const FLASH_RANGE := 6.5
const FLASH_DEFAULT := Color(1.0, 0.72, 0.35)   # burnt orange, the usual muzzle

var _muzzle_light: OmniLight3D
var _flash_left := 0.0
var _impacts_left := 0     # impact bursts still allowed on this trigger pull


func _ready() -> void:
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.omni_range = FLASH_RANGE
	_muzzle_light.shadow_enabled = false
	_muzzle_light.light_specular = 0.6
	# Ahead of the receiver so it lights what is in front of the shooter rather
	# than the inside of their own chest.
	_muzzle_light.position = Vector3(0.0, 0.0, -0.45)
	_muzzle_light.visible = false
	add_child(_muzzle_light)


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


## A staff rather than the saber: the viewmodel and the third-person model draw a
## two-ended electro-pole and a shield-on-guard instead of a single blade. Purely
## which melee LOOK to build — the block mechanic is the same for both.
func is_staff() -> bool:
	return _profile.get("staff", false)


## What a melee weapon LOOKS like, for whoever is drawing it — the first-person
## viewmodel and the third-person model both build their blade from this, so a
## lightsaber, an energy sword, a chainsword and a thunder hammer are one code
## path and four table rows.
##
## `energy` 0 means a DULL edge: steel that does not glow, which is the whole
## difference between a chainsword and a power sword. Defaults are the
## lightsaber's, so an existing melee profile that says nothing is unchanged.
const BLADE_LOOK_KEYS := ["blade_core", "blade_glow", "blade_len", "blade_width",
	"blade_energy", "hilt_len"]


func melee_look() -> Dictionary:
	var out := {}
	for key in BLADE_LOOK_KEYS:
		if _profile.has(key):
			out[key] = _profile[key]
	return out


## How far this weapon can actually reach. Bots read it so they never sit at
## their preferred stand-off range holding a weapon that cannot get there.
func max_range() -> float:
	return _profile["range"]


## The cone (deg) a shot leaves with in each stance, with no live bloom or
## stance penalty in it — what this gun is CAPABLE of, rather than what it would
## do this frame. A bot works its engagement range out of these: how far away it
## can still hit is its own aim wobble plus the cone it will shoot through, and
## nothing else. `current_spread_deg` is the live number and stays the one the
## HUD and the shot itself read.
func aimed_spread_deg() -> float:
	# A scope is pinpoint, the same absolute rule current_spread_deg keeps.
	return 0.0 if has_scope() else _profile["ads_spread"]


func hip_spread_deg() -> float:
	return _profile["hip_spread"]


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
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_muzzle_light.visible = false
		else:
			# Decay rather than a hard cut: a flash that switches off looks like a
			# dropped frame, and the falloff is most of what reads as a flash.
			_muzzle_light.light_energy = FLASH_ENERGY * (_flash_left / FLASH_TIME)
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


## Light the muzzle for a moment. A blade has no muzzle, and neither does a
## weapon whose shot never leaves the barrel, so melee is skipped outright.
func _flash_muzzle() -> void:
	if _muzzle_light == null or is_melee():
		return
	_muzzle_light.light_color = _profile.get("flash", FLASH_DEFAULT)
	_muzzle_light.light_energy = FLASH_ENERGY
	_muzzle_light.visible = true
	_flash_left = FLASH_TIME


## Stow the first-person weapon across the chest while sprinting, or bring it
## back up. Forwarded rather than reached for, the same as parry(): the viewmodel
## is this node's private child and Player is what knows it is running.
##
## A blade ignores it — the saber and staff have their own pose path, and a
## melee weapon carried "not ready" is a distinction without a difference.
func set_sprinting(on: bool) -> void:
	if _viewmodel and "sprinting" in _viewmodel:
		_viewmodel.sprinting = on and not is_melee()


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
	_flash_muzzle()
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
	var pooled := {}   # target -> [damage, any_headshot]
	if is_melee():
		# A swing connects on a forward ARC, not a pinpoint ray — see _melee_strike.
		_melee_strike(pooled)
	else:
		var from := global_position
		var muzzle := from - global_transform.basis.y * 0.12
		var pellets: int = _profile.get("pellets", 1)
		var damage: float = _profile["damage"]
		_impacts_left = IMPACTS_PER_SHOT
		for i in pellets:
			var end := _trace_pellet(from, pooled, damage)
			var bolt := BOLT_SCENE.instantiate()
			get_tree().current_scene.add_child(bolt)
			bolt.launch(muzzle, end)
	for target in pooled:
		var entry: Array = pooled[target]
		target.take_damage(entry[0], shooter, entry[1])


## The half-angle (deg) a melee swing covers. Wide on purpose: a blade or staff
## fights at point-blank where a single centre ray whiffs the moment the target
## drifts off the crosshair, so "within reach and roughly in front" is a hit.
const MELEE_ARC := 50.0


## Resolve a melee swing. Hits the NEAREST enemy inside reach and inside the
## forward arc that a wall is not between — reliable at the close range melee has
## to earn, without the pixel-perfect aim a hitscan ray demanded. No headshots:
## a sweep does not care where on the body it lands.
func _melee_strike(pooled: Dictionary) -> void:
	if shooter == null or not is_instance_valid(shooter):
		return
	var origin := global_position
	var forward := -global_transform.basis.z
	var reach: float = _profile["range"]
	var cos_arc := cos(deg_to_rad(MELEE_ARC))
	var my_team = shooter.team if "team" in shooter else -99
	var space := get_world_3d().direct_space_state
	var best: Node = null
	var best_gap := INF
	for c in GameState.combatants:
		if c == shooter or not is_instance_valid(c) or not c.is_alive() or c.team == my_team:
			continue
		var chest: Vector3 = c.global_position + Vector3.UP * 1.0
		var to := chest - origin
		var gap := to.length()
		if gap > reach or gap < 0.05:
			continue
		if forward.dot(to / gap) < cos_arc:
			continue
		# A swing does not reach THROUGH a wall. World layer (1) only — bodies don't
		# block it, so a target pressed against you still gets hit.
		var q := PhysicsRayQueryParameters3D.create(origin, chest)
		q.collision_mask = 1
		q.exclude = [shooter.get_rid()]
		if not space.intersect_ray(q).is_empty():
			continue
		if gap < best_gap:
			best = c
			best_gap = gap
	if best != null:
		pooled[best] = [_profile["damage"], false]


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
	# Mark the WALL, not the man. A body already reports a hit three ways (the
	# marker, the tick and the damage), and sparking off a chest as well as off
	# stone reads as armour rather than as flesh.
	if col != null and not col.has_method("take_damage") and _impacts_left > 0 \
			and _worth_showing(end):
		_impacts_left -= 1
		var burst: Node3D = IMPACT.new()
		get_tree().current_scene.add_child(burst)
		burst.burst(end, hit.get("normal", Vector3.UP),
			_profile.get("flash", FLASH_DEFAULT))
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


## Is this point close enough to a HUMAN for the effect to be worth building?
## Humans only: bots have no camera, so a burst next to one is seen by nobody.
## Walks GameState.combatants rather than the viewports because that list is
## already there and is at most a dozen entries.
func _worth_showing(at: Vector3) -> bool:
	for c in GameState.combatants:
		if c is Player and is_instance_valid(c) \
				and c.global_position.distance_to(at) <= IMPACT_VIEW_RANGE:
			return true
	return false


func _fire_rocket() -> void:
	var rocket := ROCKET_SCENE.instantiate()
	get_tree().current_scene.add_child(rocket)
	rocket.launch(global_position, -global_transform.basis.z, shooter,
		_profile["splash"], _profile["splash_damage"], _profile["range"])
