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
## which universe is being played — a shellgun is a hitscan with a heavy round.
enum Class {
	SOLDIER, SNIPER, HEAVY, REVOLVER, HMG, BURST, SEMI, RPG, PISTOL, HOLDOUT,
	ROTARY, TURRET,
	SMG, CARBINE, SCATTERGUN, DMR,   # primaries
	DH7, BR9,                     # sidearms
	SABER,                           # Kinesis adept's melee primary
	QUARREL_CASTER,                       # the Ursan's sidearm, and only theirs
	WRIST_CANNON,                    # the Super Battle Droid's arm gun (Conquest)
	STAFF,                           # the Magna Guard's electrostaff (Conquest)

	# --- DEEP_RANGE ----------------------------------------------------------------
	# COALITION: ballistic, loud, and accurate in short controlled bursts.
	AR7, BR3, S9_SMG, CQ12, LR99, RL8, S6, HM40, DM3,
	LANCE_LASER,
	# Hierophany: plasma — hotter, softer, and it melts shields rather than plate.
	PLASMA_RIFLE, PLASMA_PISTOL, NEEDLER, HIER_CARBINE, BEAM_RIFLE, FUEL_ROD,
	CLEAVER_GUN, MAULER, ENERGY_SWORD, GRAV_HAMMER,

	# --- IRONHYMN 40,000 -----------------------------------------------------
	# Adeptus Order: mass-reactive bolts, plasma that cooks its own operator,
	# and chain teeth for whatever survives the walk in.
	SHELLGUN, HEAVY_BOLTER, STALKER_BOLT, PLASMA_GUN, FUSION_GUN, FLAMER,
	BOLT_PISTOL, ORDER_PLASMA_PISTOL, GRENADE_LAUNCHER,
	CHAINSWORD, POWER_SWORD, THUNDER_HAMMER,
	# Necrons: gauss flays, tesla arcs, and none of it ever jams.
	GAUSS_RIFLE, GAUSS_BLASTER, TESLA_CARBINE, SYNAPTIC_DISINTEGRATOR,
	HEAT_RAY, TRANSDIMENSIONAL_BEAMER, GAUSS_PISTOL, WARSCYTHE, STAFF_OF_LIGHT,
	# Orks: more dakka, less accuracy, and a very large choppy thing.
	SLUGTHROWER, BIG_SHOOTA, SLUG_PISTOL, SCRAP_ROCKET, JUNK_BLASTER, TORCH,
	CLEAVER, CRUSHER_CLAW,

	# =========================================================================
	# THE ROSTER REBUILD. Sixteen guns the faction classes could not be built
	# without — a Aegis Drone firing a DC-15 is not a Aegis Drone, and an DROPTROOPER with an
	# unsilenced SMG is just a marine. Appended, so no index moved.
	# =========================================================================
	# The Compact Wars — Concord
	VL15S,          # legionary carbine: the officer/engineer gun
	VL17,           # ARC trooper's pistol, carried in pairs
	VL17M,          # legionary commando rifle
	VL15X,          # legionary sharpshooter's rifle
	# The Compact Wars — Automata
	X5,             # AUTOMATON's rifle
	X5S,            # ...and the sniper variant
	AEGIS_TWIN,  # the destroyer's paired repeating blasters
	SONIC_BLASTER,  # Vespid
	VIBROSWORD,     # BX commando droid
	# The Compact Wars — Dominion
	DK11,            # dominion trooper
	DK19,          # heavy trooper
	DK20A,         # scout/sniper
	SR14R,          # death trooper's machine pistol
	FLAMETHROWER,   # incinerator trooper: the incinerator
	# The Compact Wars — the Pact
	A28C,          # rebel trooper
	CR9,            # vanguard SMG
	DH44,          # rebel marksman
	KOBB_SPEAR,     # ...and the one nobody expects
	# Deep Range
	GL19,           # COALITION grenade launcher
	SPIKER,         # Brute spiker
	DK11D,           # death trooper's rifle — see below

	# =========================================================================
	# THE LIGHT MACHINE GUNS. Appended, so no index moved (house rule 8).
	#
	# There were three sustained-fire guns in the whole catalogue and all three
	# were the same idea at three rates: a lot of small rounds through a wide
	# cone. That is ONE weapon, and it left the whole slow-and-heavy half of the
	# category empty — the gun you brace, fire in fours, and kill in three hits
	# with. These four spread the class across the rate/damage axis instead of
	# stacking on one end of it, and every setting gets one so an LMG player is
	# not forced into The Compact Wars.
	#
	# What they SHARE is the LMG contract, and it is what makes them different
	# from rifles rather than better ones: very stable while braced (low
	# `cam_recoil` — see the note on machine-gun stability), a deep heat pool,
	# and a hip-fire cone bad enough that they are useless on the move.
	RT9,          # The Compact Wars: the slow one. Fewest rounds, hardest hit.
	DK19D,         # The Compact Wars: the middle. A suppressor you walk fire with.
	SAW7,       # Deep Range: the fast one. Least damage a round, most of them.
	GAUSS_CANNON,   # ironhymn Unsleeping: slow, heavy, and it does not miss.
}
enum FireMode { AUTO, SEMI, BURST }

# THE GUN KICKS AS MUCH AS THE SCREEN KICKS, AND THAT IS ONE NUMBER, NOT TWO.
#
# There used to be a `recoil` key for the viewmodel beside `cam_recoil` for the
# camera, and being separate they disagreed: the ratio between them ran from 5.9
# on the sniper to 12.0 on the rifle, so some guns flipped hard while the view
# behind them barely moved and others did the opposite. That is the single most
# common reason a shooter feels "off" — the weapon in your hands is telling you
# one thing about the shot and the sight picture is telling you another, and the
# eye believes the sight picture.
#
# So the viewmodel's climb is DERIVED from the camera's (`VIEW_KICK_PER_RAD`).
# One number per gun decides what a shot does, and the two can never drift.
const VIEW_KICK_PER_RAD := 8.0

## HOW HEAVY THE GUN IS IN THE HANDS — one number, and it is the whole of a
## weapon's HANDLING.
##
## Everything about these guns was a statement about what a round DOES: damage,
## reach, cone, heat, kick. Nothing said what the weapon is like to CARRY, so a
## Gauss Cannon came up to the eye exactly as fast as a holdout pistol and left a
## sprint exactly as fast — which is why the catalogue could be spread across
## every ballistic axis and still have all sixty guns feel like one gun.
##
## `handling` multiplies every TIME the weapon costs you: raising the sights
## (`Player.ads_time`) and recovering from a sprint (`SPRINT_RAISE_TIME`). Above
## 1.0 is slower. 1.0 is the DC-15, which is the rifle everything else in this
## file is already read against, and **no key means 1.0** — the same rule as
## `VOICES` and the universe keys, so only the exceptions are stated and an
## ordinary rifle says nothing.
##
## It is deliberately NOT derived from damage or weight-by-proxy. A derivation
## that is right for forty guns and wrong for twenty is worse than a column,
## because the twenty are invisible.
const HANDLING_DEFAULT := 1.0


func handling() -> float:
	return maxf(0.05, float(_profile.get("handling", HANDLING_DEFAULT)))

# spread = fire-cone half-angle (deg); zoom_fov = FOV while aiming; heat_per_shot
# / cool_rate are fractions of the 0..1 heat pool;
# cam_recoil = camera pitch kick (radians), and the gun's own visible kick is
# derived from it. Optional keys default via .get():
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
		"name": "VL-15 Rifle", "fire_interval": 0.14, "damage": 20.0,
		"range": 120.0, "hip_spread": 2.5, "ads_spread": 0.4, "zoom_fov": 48.0,
		"heat_per_shot": 0.085, "cool_rate": 0.26, "scope": false,
		"cam_recoil": 0.046,
	},
	Class.SNIPER: {
		"name": "NX-24 Sniper", "fire_interval": 1.1, "damage": 95.0,
		"range": 400.0, "hip_spread": 7.0, "ads_spread": 0.0, "zoom_fov": 20.0,
		"heat_per_shot": 0.45, "cool_rate": 0.28, "scope": true,
		"handling": 1.60, "cam_recoil": 0.20, "kick_back": 3.0,
		"mode": FireMode.SEMI,
	},
	Class.HEAVY: {
		"name": "RP-6 Repeater", "fire_interval": 0.075, "damage": 11.0,
		"range": 85.0, "hip_spread": 4.5, "ads_spread": 2.0, "zoom_fov": 62.0,
		"heat_per_shot": 0.06, "cool_rate": 0.22, "scope": false,
		"handling": 1.45, "cam_recoil": 0.018,
	},
	Class.REVOLVER: {
		"name": "SR-14 Revolver", "fire_interval": 0.42, "damage": 55.0,
		"range": 100.0, "hip_spread": 1.5, "ads_spread": 0.3, "zoom_fov": 55.0,
		"heat_per_shot": 0.22, "cool_rate": 0.3, "scope": false,
		"handling": 0.78, "cam_recoil": 0.22, "kick_back": 1.6,
		"mode": FireMode.SEMI,
	},
	# A MACHINE GUN IS THE STEADIEST THING YOU CAN CARRY, AND IT WAS THE WORST.
	#
	# Steady climb is `cam_recoil / (fire_interval * Player.RECOIL_RECOVER)`, and
	# on that measure the T-21 was running at 7.6 degrees a second against the
	# DC-15's 3.1 — the belt-fed weapon braced on a bipod climbed two and a half
	# times as fast as a rifle held in two hands. Every one of these guns was
	# therefore a three-round weapon with a very long tail of wasted rounds, and
	# the whole reason to carry one is the twentieth round.
	#
	# They are the most CONTROLLABLE guns in the game now (T-21 3.6 deg/s, Z-6
	# 2.3, R-90 3.6, all under the rifle) and they still pay for it everywhere
	# else — the widest cones in the catalogue, the worst hip fire, and the
	# weight. Range and rate buy nothing if the sight leaves the target.
	#
	# The HMG's cooling is double every other gun's relative to its output: it is
	# the one weapon meant to keep firing, so the lockout it earns is short.
	Class.HMG: {
		"name": "T-90 HMG", "fire_interval": 0.05, "damage": 13.0,
		"range": 110.0, "hip_spread": 5.5, "ads_spread": 2.5, "zoom_fov": 60.0,
		"heat_per_shot": 0.042, "cool_rate": 0.36, "scope": false,
		"handling": 1.70, "cam_recoil": 0.019,
	},
	Class.BURST: {
		"name": "BL-16 Burst", "fire_interval": 0.42, "damage": 24.0,
		"range": 140.0, "hip_spread": 1.6, "ads_spread": 0.15, "zoom_fov": 50.0,
		"heat_per_shot": 0.09, "cool_rate": 0.3, "scope": false,
		"handling": 1.05, "cam_recoil": 0.055,
		"mode": FireMode.BURST, "burst_count": 3, "burst_interval": 0.06,
	},
	Class.SEMI: {
		"name": "A-28 Semi", "fire_interval": 0.2, "damage": 42.0,
		"range": 200.0, "hip_spread": 1.0, "ads_spread": 0.0, "zoom_fov": 45.0,
		"heat_per_shot": 0.11, "cool_rate": 0.3, "scope": false,
		"handling": 1.10, "cam_recoil": 0.105, "kick_back": 1.0,
		"mode": FireMode.SEMI,
	},
	Class.PISTOL: {
		"name": "BR-44 Pistol", "fire_interval": 0.26, "damage": 32.0,
		"range": 90.0, "hip_spread": 1.8, "ads_spread": 0.35, "zoom_fov": 56.0,
		"heat_per_shot": 0.13, "cool_rate": 0.34, "scope": false,
		"handling": 0.70, "cam_recoil": 0.118, "mode": FireMode.SEMI,
	},
	Class.HOLDOUT: {
		"name": "RK-9 Holdout", "fire_interval": 0.16, "damage": 19.0,
		"range": 70.0, "hip_spread": 2.4, "ads_spread": 0.7, "zoom_fov": 58.0,
		"heat_per_shot": 0.075, "cool_rate": 0.4, "scope": false,
		"handling": 0.68, "cam_recoil": 0.061,
	},
	# The rotary gadget's gun: enormous sustained output, but it has to spin up
	# first and it sprays, and carrying it slows you to a walk.
	Class.ROTARY: {
		"name": "R-99 Rotary", "fire_interval": 0.04, "damage": 12.0,
		"range": 95.0, "hip_spread": 4.0, "ads_spread": 2.2, "zoom_fov": 64.0,
		"heat_per_shot": 0.022, "cool_rate": 0.20, "scope": false,
		"handling": 1.85, "cam_recoil": 0.015, "spinup": 0.7,
	},
	# What a placed turret shoots with. It's bolted to the floor, so it has a
	# viewmodel kick nobody sees and no camera kick or shove at all.
	Class.TURRET: {
		"name": "EW-5 Turret", "fire_interval": 0.18, "damage": 18.0,
		"range": 60.0, "hip_spread": 1.2, "ads_spread": 1.2, "zoom_fov": 70.0,
		"heat_per_shot": 0.05, "cool_rate": 0.28, "scope": false,
		"cam_recoil": 0.0,
	},
	Class.RPG: {
		"name": "PX-1 RPG", "fire_interval": 1.6, "damage": 0.0,
		"range": 300.0, "hip_spread": 0.5, "ads_spread": 0.0, "zoom_fov": 60.0,
		"heat_per_shot": 0.6, "cool_rate": 0.3, "scope": false,
		"handling": 1.60, "cam_recoil": 0.30, "kick_back": 5.5,
		"mode": FireMode.SEMI,
		"projectile": true, "splash": 4.5, "splash_damage": 95.0,
	},
	# The cheap primary: it spits, but every round is a pinprick and the cone
	# opens up fast, so it is a room-clearer rather than a rifle.
	Class.SMG: {
		"name": "WS-5 SMG", "fire_interval": 0.07, "damage": 12.0,
		"range": 55.0, "hip_spread": 3.6, "ads_spread": 1.4, "zoom_fov": 64.0,
		"heat_per_shot": 0.05, "cool_rate": 0.30, "scope": false,
		"handling": 0.74, "cam_recoil": 0.030,
	},
	# Between the SMG and the DC-15: a shorter, faster rifle that gives up range.
	Class.CARBINE: {
		"name": "VL-15S Carbine", "fire_interval": 0.11, "damage": 16.0,
		"range": 90.0, "hip_spread": 2.2, "ads_spread": 0.35, "zoom_fov": 52.0,
		"heat_per_shot": 0.07, "cool_rate": 0.28, "scope": false,
		"handling": 0.88, "cam_recoil": 0.038,
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
		"name": "FB-10 Scatter", "fire_interval": 0.85, "damage": 12.0,
		"range": 26.0, "hip_spread": 3.2, "ads_spread": 2.0, "zoom_fov": 66.0,
		"heat_per_shot": 0.30, "cool_rate": 0.34, "scope": false,
		"handling": 1.15, "cam_recoil": 0.175, "kick_back": 2.2,
		"mode": FireMode.SEMI, "pellets": 7,
	},
	# Scoped as issued, so it is pinpoint on the glass without buying a sight —
	# the cheaper, faster-firing alternative to the bolt-action sniper.
	Class.DMR: {
		"name": "A-28M Marksman", "fire_interval": 0.55, "damage": 62.0,
		"range": 250.0, "hip_spread": 2.4, "ads_spread": 0.0, "zoom_fov": 32.0,
		"heat_per_shot": 0.30, "cool_rate": 0.30, "scope": true,
		"handling": 1.30, "cam_recoil": 0.140, "kick_back": 1.4,
		"mode": FireMode.SEMI,
	},
	# Sidearms. The DH-17 is the only automatic one, which is what makes it the
	# sidearm worth dual-wielding.
	Class.DH7: {
		"name": "DH-7 Sidearm", "fire_interval": 0.17, "damage": 17.0,
		"range": 60.0, "hip_spread": 2.6, "ads_spread": 0.8, "zoom_fov": 58.0,
		"heat_per_shot": 0.075, "cool_rate": 0.36, "scope": false,
		"handling": 0.72, "cam_recoil": 0.049,
	},
	Class.BR9: {
		"name": "BR-9 Pistol", "fire_interval": 0.5, "damage": 58.0,
		"range": 120.0, "hip_spread": 1.2, "ads_spread": 0.1, "zoom_fov": 50.0,
		"heat_per_shot": 0.28, "cool_rate": 0.32, "scope": false,
		"handling": 0.80, "cam_recoil": 0.160, "kick_back": 1.2,
		"mode": FireMode.SEMI,
	},
	# The arc blade: Kinesis adept's only primary, and the only MELEE weapon.
	# It is still a hitscan — a ray three metres long — so it needs no new code
	# path anywhere, it just cannot reach. That range is the entire balance of
	# the class: it hits harder than any rifle and kills a standard trooper in
	# two swings, but every one of them is a decision to close.
	#
	# No heat: a blade does not overheat, and the exhaustion that limits the
	# class is the BLOCK pool on Player, not the trigger.
	Class.SABER: {
		"name": "Arc Blade", "fire_interval": 0.40, "damage": 55.0,
		"range": 3.4, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 75.0,
		"heat_per_shot": 0.0, "cool_rate": 1.0, "scope": false,
		"cam_recoil": 0.022, "melee": true,
	},
	# The Ursan's sidearm: a crossbow that throws a spread of energy quarrels.
	# Three pellets through one cone, which is the scattergun's mechanism and
	# needs no new code — the damage is already pooled per target, so one trigger
	# pull is one hit marker and one tick however many quarrels land.
	#
	# It is a SIDEARM that hits like a primary (78 on a clean hit, more than a
	# rifle's four rounds) and pays for it in everything else: under a shot a
	# second, half a rifle's reach, and a third of the heat pool per pull, so
	# three pulls lock it out. That is deliberate — the class it belongs to is
	# carrying an HMG or a rocket tube in the other hand, and the quarrel caster is
	# what it fights with while those are hot or empty of targets.
	#
	# The cone is TIGHT (2.2 hip against the scattergun's 3.2, and remember two
	# independent rotations make the effective corner ~1.4x that) so it stays a
	# weapon at mid range rather than a second shotgun.
	Class.QUARREL_CASTER: {
		"name": "Quarrel Caster", "fire_interval": 0.9, "damage": 26.0,
		"range": 60.0, "hip_spread": 2.2, "ads_spread": 0.9, "zoom_fov": 58.0,
		"heat_per_shot": 0.34, "cool_rate": 0.30, "scope": false,
		"handling": 1.10, "cam_recoil": 0.19, "kick_back": 2.6,
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
		"handling": 0.90, "cam_recoil": 0.03,
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
		"cam_recoil": 0.02, "melee": true, "staff": true,
	},

	# =========================================================================
	# HALO — COALITION
	# =========================================================================
	# The reason these are here and not a re-skin of the DC-15: a universe's guns
	# are how it FEELS. COALITION weapons are ballistic — they bloom fast, they kick,
	# and they reward the three-round burst; Hierophany plasma barely kicks at all
	# and pays for it in heat, which is a mechanic this game already has.
	Class.AR7: {
		"name": "AR-7 Assault Rifle", "fire_interval": 0.085, "damage": 14.0,
		"range": 70.0, "hip_spread": 3.4, "ads_spread": 1.2, "zoom_fov": 62.0,
		"heat_per_shot": 0.048, "cool_rate": 0.30, "scope": false,
		"handling": 0.95, "cam_recoil": 0.034,
	},
	Class.BR3: {
		"name": "BR-3 Battle Rifle", "fire_interval": 0.36, "damage": 22.0,
		"range": 150.0, "hip_spread": 1.5, "ads_spread": 0.12, "zoom_fov": 44.0,
		"heat_per_shot": 0.085, "cool_rate": 0.30, "scope": false,
		"handling": 1.05, "cam_recoil": 0.050,
		"mode": FireMode.BURST, "burst_count": 3, "burst_interval": 0.055,
	},
	Class.S9_SMG: {
		"name": "S-9 SMG", "fire_interval": 0.06, "damage": 10.0,
		"range": 45.0, "hip_spread": 4.2, "ads_spread": 1.7, "zoom_fov": 66.0,
		"heat_per_shot": 0.042, "cool_rate": 0.32, "scope": false,
		"handling": 0.74, "cam_recoil": 0.028,
	},
	Class.CQ12: {
		"name": "CQ-12 Shotgun", "fire_interval": 0.82, "damage": 13.0,
		"range": 22.0, "hip_spread": 3.4, "ads_spread": 2.2, "zoom_fov": 68.0,
		"heat_per_shot": 0.30, "cool_rate": 0.34, "scope": false,
		"handling": 1.15, "cam_recoil": 0.185, "kick_back": 2.4,
		"mode": FireMode.SEMI, "pellets": 8,
	},
	Class.LR99: {
		"name": "LR-99 Sniper", "fire_interval": 1.15, "damage": 100.0,
		"range": 400.0, "hip_spread": 7.5, "ads_spread": 0.0, "zoom_fov": 19.0,
		"heat_per_shot": 0.46, "cool_rate": 0.28, "scope": true,
		"handling": 1.60, "cam_recoil": 0.22, "kick_back": 3.2,
		"mode": FireMode.SEMI,
	},
	Class.RL8: {
		"name": "RL-8 Rocket", "fire_interval": 1.5, "damage": 0.0,
		"range": 300.0, "hip_spread": 0.6, "ads_spread": 0.0, "zoom_fov": 60.0,
		"heat_per_shot": 0.58, "cool_rate": 0.30, "scope": false,
		"handling": 1.60, "cam_recoil": 0.30, "kick_back": 5.2,
		"mode": FireMode.SEMI,
		"projectile": true, "splash": 4.6, "splash_damage": 95.0,
	},
	Class.S6: {
		"name": "S-6 Magnum", "fire_interval": 0.30, "damage": 36.0,
		"range": 95.0, "hip_spread": 1.6, "ads_spread": 0.25, "zoom_fov": 46.0,
		"heat_per_shot": 0.16, "cool_rate": 0.34, "scope": false,
		"handling": 0.74, "cam_recoil": 0.135, "mode": FireMode.SEMI,
	},
	Class.HM40: {
		"name": "HM-40 Machine Gun", "fire_interval": 0.055, "damage": 14.0,
		"range": 105.0, "hip_spread": 5.6, "ads_spread": 2.6, "zoom_fov": 60.0,
		"heat_per_shot": 0.044, "cool_rate": 0.34, "scope": false,
		"handling": 1.70, "cam_recoil": 0.042,
	},
	Class.DM3: {
		"name": "DM-3 Marksman", "fire_interval": 0.35, "damage": 40.0,
		"range": 190.0, "hip_spread": 2.0, "ads_spread": 0.0, "zoom_fov": 36.0,
		"heat_per_shot": 0.18, "cool_rate": 0.30, "scope": true,
		"handling": 1.25, "cam_recoil": 0.118, "mode": FireMode.SEMI,
	},
	# The one gun in the game that has to be CHARGED. `spinup` already exists for
	# the rotary's barrels, and a charge is the same thing said backwards: hold
	# the trigger, nothing happens, then the whole magazine's worth arrives at
	# once. AUTO rather than SEMI because the spin-up gate eats the press edge —
	# a semi-automatic charge weapon would never fire at all.
	Class.LANCE_LASER: {
		"flash": Color(1.0, 0.35, 0.30),
		"name": "Lance Laser", "fire_interval": 1.6, "damage": 180.0,
		"range": 320.0, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 34.0,
		"heat_per_shot": 0.85, "cool_rate": 0.22, "scope": true,
		"handling": 1.70, "cam_recoil": 0.24, "kick_back": 2.0, "spinup": 1.2,
	},

	# =========================================================================
	# HALO — Hierophany
	# =========================================================================
	Class.PLASMA_RIFLE: {
		"flash": Color(0.45, 0.75, 1.0),
		"name": "Plasma Rifle", "fire_interval": 0.10, "damage": 15.0,
		"range": 60.0, "hip_spread": 2.8, "ads_spread": 1.0, "zoom_fov": 62.0,
		"heat_per_shot": 0.075, "cool_rate": 0.26, "scope": false,
		"handling": 0.95, "cam_recoil": 0.020,
	},
	Class.PLASMA_PISTOL: {
		"flash": Color(0.45, 0.85, 0.7),
		"name": "Plasma Pistol", "fire_interval": 0.22, "damage": 21.0,
		"range": 50.0, "hip_spread": 2.0, "ads_spread": 0.55, "zoom_fov": 58.0,
		"heat_per_shot": 0.11, "cool_rate": 0.30, "scope": false,
		"handling": 0.72, "cam_recoil": 0.030, "mode": FireMode.SEMI,
	},
	# The needler's crystals track, which this engine has no room for — so what
	# makes it a needler here is VOLUME on a very tight cone: it is the only
	# automatic weapon that stays accurate while you hold it down, and it hurts
	# in proportion to how long you can keep it on somebody.
	Class.NEEDLER: {
		"flash": Color(0.95, 0.45, 1.0),
		"name": "Shard Pistol", "fire_interval": 0.075, "damage": 11.0,
		"range": 50.0, "hip_spread": 1.3, "ads_spread": 0.5, "zoom_fov": 64.0,
		"heat_per_shot": 0.05, "cool_rate": 0.28, "scope": false,
		"handling": 0.92, "cam_recoil": 0.016,
	},
	Class.HIER_CARBINE: {
		"flash": Color(0.65, 1.0, 0.55),
		"name": "Hierophant Carbine", "fire_interval": 0.24, "damage": 30.0,
		"range": 165.0, "hip_spread": 1.4, "ads_spread": 0.1, "zoom_fov": 40.0,
		"heat_per_shot": 0.13, "cool_rate": 0.28, "scope": false,
		"handling": 1.00, "cam_recoil": 0.090, "mode": FireMode.SEMI,
	},
	Class.BEAM_RIFLE: {
		"flash": Color(0.55, 0.75, 1.0),
		"name": "Particle Beam Rifle", "fire_interval": 1.0, "damage": 92.0,
		"range": 400.0, "hip_spread": 6.5, "ads_spread": 0.0, "zoom_fov": 18.0,
		"heat_per_shot": 0.50, "cool_rate": 0.24, "scope": true,
		"handling": 1.50, "cam_recoil": 0.14, "mode": FireMode.SEMI,
	},
	Class.FUEL_ROD: {
		"flash": Color(0.55, 1.0, 0.35),
		"name": "Rod Cannon", "fire_interval": 1.1, "damage": 0.0,
		"range": 220.0, "hip_spread": 1.2, "ads_spread": 0.4, "zoom_fov": 60.0,
		"heat_per_shot": 0.34, "cool_rate": 0.26, "scope": false,
		"handling": 1.55, "cam_recoil": 0.24, "kick_back": 3.4,
		"mode": FireMode.SEMI,
		"projectile": true, "splash": 3.8, "splash_damage": 72.0,
	},
	Class.CLEAVER_GUN: {
		"name": "Cleaver Launcher", "fire_interval": 0.75, "damage": 0.0,
		"range": 150.0, "hip_spread": 1.8, "ads_spread": 0.8, "zoom_fov": 62.0,
		"heat_per_shot": 0.26, "cool_rate": 0.30, "scope": false,
		"handling": 1.35, "cam_recoil": 0.19, "kick_back": 2.2,
		"mode": FireMode.SEMI,
		"projectile": true, "splash": 3.0, "splash_damage": 55.0,
	},
	Class.MAULER: {
		"name": "Mauler", "fire_interval": 0.55, "damage": 11.0,
		"range": 18.0, "hip_spread": 3.0, "ads_spread": 2.0, "zoom_fov": 66.0,
		"heat_per_shot": 0.26, "cool_rate": 0.34, "scope": false,
		"handling": 0.80, "cam_recoil": 0.16, "kick_back": 1.6,
		"mode": FireMode.SEMI, "pellets": 5,
	},
	# The energy sword is the saber's mechanism with a different blade: a melee
	# hitscan that lands on the forward arc. Longer reach than the arc blade and
	# it kills a standard body outright, which is the lunge everybody remembers.
	Class.ENERGY_SWORD: {
		"name": "Energy Sword", "fire_interval": 0.55, "damage": 95.0,
		"range": 4.0, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 75.0,
		"heat_per_shot": 0.0, "cool_rate": 1.0, "scope": false,
		"cam_recoil": 0.026, "melee": true,
		"blade_core": Color(0.72, 0.94, 1.0), "blade_glow": Color(0.20, 0.75, 1.0),
		"blade_len": 0.62, "blade_width": 0.055,
	},
	Class.GRAV_HAMMER: {
		"name": "Gravity Hammer", "fire_interval": 0.85, "damage": 120.0,
		"range": 4.4, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 75.0,
		"heat_per_shot": 0.0, "cool_rate": 1.0, "scope": false,
		"cam_recoil": 0.05, "melee": true,
		"blade_core": Color(0.55, 0.42, 0.30), "blade_glow": Color(0.95, 0.55, 0.15),
		"blade_len": 0.22, "blade_width": 0.17, "hilt_len": 0.55, "blade_energy": 0.0,
	},

	# =========================================================================
	# IRONHYMN — Adeptus Order
	# =========================================================================
	# A bolt is a rocket-propelled shell that detonates inside the target, so
	# these hit far harder per round than a blaster and fire far slower. The
	# plasma weapons keep the setting's actual joke: they overheat, and the heat
	# pool this game already has is exactly the right place to say so.
	Class.SHELLGUN: {
		"name": "MK VII Shellgun", "fire_interval": 0.16, "damage": 24.0,
		"range": 110.0, "hip_spread": 2.6, "ads_spread": 0.5, "zoom_fov": 50.0,
		"heat_per_shot": 0.075, "cool_rate": 0.26, "scope": false,
		"handling": 1.10, "cam_recoil": 0.062,
	},
	Class.HEAVY_BOLTER: {
		"name": "Heavy Shellgun", "fire_interval": 0.115, "damage": 21.0,
		"range": 125.0, "hip_spread": 4.8, "ads_spread": 2.4, "zoom_fov": 60.0,
		"heat_per_shot": 0.055, "cool_rate": 0.32, "scope": false,
		"handling": 1.75, "cam_recoil": 0.070, "kick_back": 0.8,
	},
	Class.STALKER_BOLT: {
		"name": "Stalker Shellgun", "fire_interval": 0.42, "damage": 58.0,
		"range": 240.0, "hip_spread": 2.2, "ads_spread": 0.0, "zoom_fov": 30.0,
		"heat_per_shot": 0.26, "cool_rate": 0.30, "scope": true,
		"handling": 1.20, "cam_recoil": 0.150, "kick_back": 1.4,
		"mode": FireMode.SEMI,
	},
	# Three shots and it is locked out: the plasma gun is a weapon you spend
	# rather than carry, which is the whole of its reputation.
	Class.PLASMA_GUN: {
		"flash": Color(0.55, 0.80, 1.0),
		"name": "Plasma Gun", "fire_interval": 0.70, "damage": 72.0,
		"range": 150.0, "hip_spread": 1.4, "ads_spread": 0.1, "zoom_fov": 44.0,
		"heat_per_shot": 0.36, "cool_rate": 0.18, "scope": false,
		"handling": 1.25, "cam_recoil": 0.175, "kick_back": 1.2,
		"mode": FireMode.SEMI,
	},
	Class.FUSION_GUN: {
		"flash": Color(1.0, 0.55, 0.15),
		"name": "Fusion Gun", "fire_interval": 1.2, "damage": 145.0,
		"range": 18.0, "hip_spread": 0.8, "ads_spread": 0.0, "zoom_fov": 56.0,
		"heat_per_shot": 0.48, "cool_rate": 0.26, "scope": false,
		"handling": 1.30, "cam_recoil": 0.20, "kick_back": 1.8,
		"mode": FireMode.SEMI,
	},
	# THE FLAME FAMILY — this one, the Incinerator and the Burna — is three rows
	# in three universes with one shared job, so it is tuned as a family. All
	# three used to kill a standard trooper in 0.23-0.27 s, which made them the
	# three highest-trading classes in the whole game AND put them under human
	# reaction time: being burned down was not a fight you lost, it was a frame
	# in which you stopped existing. They now kill in ~0.44 s, which is still
	# comfortably the fastest kill anywhere and is still delivered by the only
	# weapon in the game you cannot miss with.
	#
	# The damage came off in FEWER, BIGGER ticks rather than smaller ones (the
	# interval went up as well as the damage down): a flamer at sixteen hits a
	# second is a stream of two-point numbers that reads as being nibbled, and it
	# is also sixteen hitscans and sixteen impact bursts a second per shooter
	# across four viewports. Heat is set so the trigger holds for about three
	# seconds and then wants a break, which is what a fuel tank should feel like.
	Class.FLAMER: {
		"flash": Color(1.0, 0.50, 0.12),
		"name": "Flamer", "fire_interval": 0.085, "damage": 6.5,
		"range": 14.0, "hip_spread": 7.0, "ads_spread": 6.0, "zoom_fov": 70.0,
		"heat_per_shot": 0.030, "cool_rate": 0.28, "scope": false,
		"handling": 1.30, "cam_recoil": 0.010, "pellets": 3,
	},
	Class.BOLT_PISTOL: {
		"name": "Shell Pistol", "fire_interval": 0.32, "damage": 33.0,
		"range": 70.0, "hip_spread": 2.0, "ads_spread": 0.4, "zoom_fov": 54.0,
		"heat_per_shot": 0.16, "cool_rate": 0.32, "scope": false,
		"handling": 0.80, "cam_recoil": 0.130, "mode": FireMode.SEMI,
	},
	# Named for the chapter rather than the weapon, because Deep Range has a plasma
	# pistol too and two rows sharing a display name is how a leak between
	# universes hides from the isolation check in tests/kit_rules.gd.
	Class.ORDER_PLASMA_PISTOL: {
		"flash": Color(0.55, 0.80, 1.0),
		"name": "Order Plasma Pistol", "fire_interval": 0.60, "damage": 52.0,
		"range": 85.0, "hip_spread": 1.5, "ads_spread": 0.2, "zoom_fov": 50.0,
		"heat_per_shot": 0.32, "cool_rate": 0.22, "scope": false,
		"handling": 0.82, "cam_recoil": 0.170, "kick_back": 1.0,
		"mode": FireMode.SEMI,
	},
	Class.GRENADE_LAUNCHER: {
		"name": "Auxiliary Launcher", "fire_interval": 1.3, "damage": 0.0,
		"range": 180.0, "hip_spread": 1.4, "ads_spread": 0.5, "zoom_fov": 58.0,
		"heat_per_shot": 0.40, "cool_rate": 0.28, "scope": false,
		"handling": 1.30, "cam_recoil": 0.22, "kick_back": 2.0,
		"mode": FireMode.SEMI,
		"projectile": true, "splash": 4.0, "splash_damage": 78.0,
	},
	# Three melee weapons that are deliberately NOT the same weapon. The
	# chain blade is fast and cheap, the power sword trades rate for reach and
	# damage, and the thunder hammer is one swing that ends anybody it touches
	# and leaves you standing still for most of a second if it does not.
	Class.CHAINSWORD: {
		"name": "Chain Blade", "fire_interval": 0.34, "damage": 60.0,
		"range": 3.6, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 75.0,
		"heat_per_shot": 0.0, "cool_rate": 1.0, "scope": false,
		"cam_recoil": 0.024, "melee": true,
		# Steel, not energy: zero emission is what tells the viewmodel to build a
		# dull blade instead of a lit one.
		"blade_core": Color(0.62, 0.63, 0.68), "blade_glow": Color(0.35, 0.30, 0.28),
		"blade_len": 0.72, "blade_width": 0.070, "blade_energy": 0.0,
	},
	Class.POWER_SWORD: {
		"name": "Power Blade", "fire_interval": 0.45, "damage": 88.0,
		"range": 3.9, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 75.0,
		"heat_per_shot": 0.0, "cool_rate": 1.0, "scope": false,
		"cam_recoil": 0.026, "melee": true,
		"blade_core": Color(0.85, 0.90, 1.0), "blade_glow": Color(0.35, 0.45, 1.0),
		"blade_len": 0.80, "blade_width": 0.052,
	},
	Class.THUNDER_HAMMER: {
		"name": "Storm Hammer", "fire_interval": 0.95, "damage": 135.0,
		"range": 4.1, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 75.0,
		"heat_per_shot": 0.0, "cool_rate": 1.0, "scope": false,
		"cam_recoil": 0.055, "melee": true,
		"blade_core": Color(0.48, 0.52, 0.60), "blade_glow": Color(0.40, 0.70, 1.0),
		"blade_len": 0.24, "blade_width": 0.19, "hilt_len": 0.60, "blade_energy": 0.0,
	},

	# =========================================================================
	# IRONHYMN — Necrons
	# =========================================================================
	# Gauss strips a target a layer at a time: steady, unhurried, and it never
	# stops. The whole armoury is built low-recoil and long-cooling — a Unsleeping
	# does not flinch, but it also does not hurry.
	Class.GAUSS_RIFLE: {
		"flash": Color(0.45, 1.0, 0.55),
		"name": "Gauss Rifle", "fire_interval": 0.13, "damage": 18.0,
		"range": 95.0, "hip_spread": 2.4, "ads_spread": 0.6, "zoom_fov": 54.0,
		"heat_per_shot": 0.065, "cool_rate": 0.24, "scope": false,
		"handling": 1.00, "cam_recoil": 0.028,
	},
	Class.GAUSS_BLASTER: {
		"flash": Color(0.45, 1.0, 0.55),
		"name": "Gauss Blaster", "fire_interval": 0.20, "damage": 27.0,
		"range": 135.0, "hip_spread": 1.8, "ads_spread": 0.3, "zoom_fov": 46.0,
		"heat_per_shot": 0.10, "cool_rate": 0.24, "scope": false,
		"handling": 1.40, "cam_recoil": 0.048,
	},
	Class.TESLA_CARBINE: {
		"flash": Color(0.55, 0.95, 1.0),
		"name": "Tesla Carbine", "fire_interval": 0.12, "damage": 16.0,
		"range": 80.0, "hip_spread": 3.0, "ads_spread": 1.1, "zoom_fov": 58.0,
		"heat_per_shot": 0.055, "cool_rate": 0.30, "scope": false,
		"handling": 1.00, "cam_recoil": 0.026,
	},
	Class.SYNAPTIC_DISINTEGRATOR: {
		"flash": Color(0.50, 1.0, 0.60),
		"name": "Synaptic Rifle", "fire_interval": 1.0, "damage": 88.0,
		"range": 380.0, "hip_spread": 5.5, "ads_spread": 0.0, "zoom_fov": 20.0,
		"heat_per_shot": 0.42, "cool_rate": 0.26, "scope": true,
		"handling": 1.45, "cam_recoil": 0.10, "mode": FireMode.SEMI,
	},
	Class.HEAT_RAY: {
		"flash": Color(1.0, 0.60, 0.25),
		"name": "Heat Ray", "fire_interval": 0.09, "damage": 22.0,
		"range": 30.0, "hip_spread": 1.6, "ads_spread": 0.8, "zoom_fov": 64.0,
		"heat_per_shot": 0.075, "cool_rate": 0.22, "scope": false,
		"handling": 1.60, "cam_recoil": 0.020,
	},
	Class.TRANSDIMENSIONAL_BEAMER: {
		"name": "Phase Beamer", "fire_interval": 1.7, "damage": 0.0,
		"range": 300.0, "hip_spread": 0.4, "ads_spread": 0.0, "zoom_fov": 44.0,
		"heat_per_shot": 0.60, "cool_rate": 0.26, "scope": false,
		"handling": 1.40, "cam_recoil": 0.20, "kick_back": 2.0,
		"mode": FireMode.SEMI,
		"projectile": true, "splash": 4.2, "splash_damage": 88.0,
	},
	Class.GAUSS_PISTOL: {
		"flash": Color(0.45, 1.0, 0.55),
		"name": "Gauss Pistol", "fire_interval": 0.30, "damage": 34.0,
		"range": 80.0, "hip_spread": 1.7, "ads_spread": 0.35, "zoom_fov": 54.0,
		"heat_per_shot": 0.15, "cool_rate": 0.30, "scope": false,
		"handling": 0.76, "cam_recoil": 0.080, "mode": FireMode.SEMI,
	},
	# A polearm, so it uses the electrostaff's silhouette rather than the saber's.
	Class.WARSCYTHE: {
		"name": "War Scythe", "fire_interval": 0.55, "damage": 98.0,
		"range": 4.5, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 75.0,
		"heat_per_shot": 0.0, "cool_rate": 1.0, "scope": false,
		"cam_recoil": 0.028, "melee": true, "staff": true,
		"blade_core": Color(0.70, 1.0, 0.72), "blade_glow": Color(0.20, 0.95, 0.35),
	},
	Class.STAFF_OF_LIGHT: {
		"name": "Lumen Staff", "fire_interval": 0.42, "damage": 74.0,
		"range": 4.2, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 75.0,
		"heat_per_shot": 0.0, "cool_rate": 1.0, "scope": false,
		"cam_recoil": 0.022, "melee": true, "staff": true,
		"blade_core": Color(0.75, 1.0, 0.80), "blade_glow": Color(0.30, 1.0, 0.50),
	},

	# =========================================================================
	# IRONHYMN — Orks
	# =========================================================================
	# The Orks pay for everything in accuracy. Every one of these throws more
	# metal than its counterpart elsewhere and lands less of it, which makes the
	# faction's answer to any problem "get closer" — and that is the point.
	Class.SLUGTHROWER: {
		"name": "Slugthrower", "fire_interval": 0.085, "damage": 16.0,
		"range": 55.0, "hip_spread": 5.2, "ads_spread": 2.4, "zoom_fov": 66.0,
		"heat_per_shot": 0.05, "cool_rate": 0.30, "scope": false,
		"handling": 1.00, "cam_recoil": 0.044,
	},
	Class.BIG_SHOOTA: {
		"name": "Heavy Slugthrower", "fire_interval": 0.055, "damage": 15.0,
		"range": 75.0, "hip_spread": 6.4, "ads_spread": 3.4, "zoom_fov": 66.0,
		"heat_per_shot": 0.040, "cool_rate": 0.34, "scope": false,
		"handling": 1.70, "cam_recoil": 0.050, "kick_back": 0.6,
	},
	Class.SLUG_PISTOL: {
		"name": "Slug Pistol", "fire_interval": 0.26, "damage": 30.0,
		"range": 45.0, "hip_spread": 3.2, "ads_spread": 1.2, "zoom_fov": 62.0,
		"heat_per_shot": 0.14, "cool_rate": 0.34, "scope": false,
		"handling": 0.74, "cam_recoil": 0.115, "mode": FireMode.SEMI,
	},
	Class.SCRAP_ROCKET: {
		"name": "Scrap Rocket", "fire_interval": 1.8, "damage": 0.0,
		"range": 260.0, "hip_spread": 2.5, "ads_spread": 1.4, "zoom_fov": 62.0,
		"heat_per_shot": 0.62, "cool_rate": 0.30, "scope": false,
		"handling": 1.55, "cam_recoil": 0.34, "kick_back": 6.0,
		"mode": FireMode.SEMI,
		"projectile": true, "splash": 5.0, "splash_damage": 100.0,
	},
	Class.JUNK_BLASTER: {
		"flash": Color(0.60, 0.90, 1.0),
		"name": "Junk Blaster", "fire_interval": 0.9, "damage": 78.0,
		"range": 120.0, "hip_spread": 2.6, "ads_spread": 0.9, "zoom_fov": 52.0,
		"heat_per_shot": 0.44, "cool_rate": 0.18, "scope": false,
		"handling": 1.55, "cam_recoil": 0.21, "kick_back": 1.6,
		"mode": FireMode.SEMI,
	},
	# Tuned with the rest of the flame family — see the note on Class.FLAMER.
	Class.TORCH: {
		"flash": Color(1.0, 0.50, 0.12),
		"name": "Torch", "fire_interval": 0.09, "damage": 6.9,
		"range": 15.0, "hip_spread": 7.5, "ads_spread": 6.5, "zoom_fov": 70.0,
		"heat_per_shot": 0.030, "cool_rate": 0.28, "scope": false,
		"handling": 1.30, "cam_recoil": 0.012, "pellets": 3,
	},
	Class.CLEAVER: {
		"name": "Cleaver", "fire_interval": 0.36, "damage": 68.0,
		"range": 3.6, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 75.0,
		"heat_per_shot": 0.0, "cool_rate": 1.0, "scope": false,
		"cam_recoil": 0.026, "melee": true,
		"blade_core": Color(0.58, 0.56, 0.52), "blade_glow": Color(0.30, 0.26, 0.22),
		"blade_len": 0.66, "blade_width": 0.085, "blade_energy": 0.0,
	},
	Class.CRUSHER_CLAW: {
		"name": "Crusher Claw", "fire_interval": 0.80, "damage": 118.0,
		"range": 3.5, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 75.0,
		"heat_per_shot": 0.0, "cool_rate": 1.0, "scope": false,
		"cam_recoil": 0.048, "melee": true,
		"blade_core": Color(0.55, 0.50, 0.42), "blade_glow": Color(0.20, 0.85, 0.95),
		"blade_len": 0.30, "blade_width": 0.15, "hilt_len": 0.28, "blade_energy": 0.0,
	},
	# =========================================================================
	# THE FACTION GUNS. Each one exists because a class could not be itself
	# without it, and each is tuned to the ROLE rather than to a spreadsheet: a
	# carbine is a rifle you can move with, a machine pistol is a shotgun that
	# reaches, and the flamethrower is the only weapon in the game with no reach
	# at all and no way to miss.
	# =========================================================================

	# --- CONCORD -------------------------------------------------------------
	# Faster and looser than the DC-15A, and the officer's gun: you are meant to
	# be moving and pointing at things, not holding a lane.
	Class.VL15S: {
		"name": "VL-15S Carbine", "fire_interval": 0.11, "damage": 17.0,
		"range": 62.0, "hip_spread": 2.6, "ads_spread": 0.85, "zoom_fov": 62.0,
		"heat_per_shot": 0.055, "cool_rate": 0.52, "scope": false,
		"handling": 0.88, "cam_recoil": 0.011,
	},
	# The ARC's pistol. Alone it is a fast sidearm; the class carries TWO (the
	# dual-wield mod), which is the whole reason it is a separate gun.
	Class.VL17: {
		"name": "VL-17 Blaster", "fire_interval": 0.14, "damage": 22.0,
		"range": 48.0, "hip_spread": 2.2, "ads_spread": 0.9, "zoom_fov": 66.0,
		"heat_per_shot": 0.09, "cool_rate": 0.55, "scope": false,
		"handling": 0.70, "cam_recoil": 0.016,
	},
	# The commando rifle: three-round burst, and the most accurate automatic in
	# the Concord's hands. Bursts reward the trigger discipline the unit is
	# supposed to have.
	Class.VL17M: {
		"name": "VL-17M Rifle", "fire_interval": 0.075, "damage": 21.0,
		"range": 86.0, "hip_spread": 1.5, "ads_spread": 0.24, "zoom_fov": 55.0,
		"heat_per_shot": 0.075, "cool_rate": 0.40, "scope": false,
		"handling": 0.95, "cam_recoil": 0.013,
		"mode": FireMode.BURST, "burst_count": 3, "burst_interval": 0.34,
	},
	Class.VL15X: {
		"name": "VL-15X Sniper", "fire_interval": 1.25, "damage": 118.0,
		"range": 260.0, "hip_spread": 5.0, "ads_spread": 0.0, "zoom_fov": 22.0,
		"heat_per_shot": 0.42, "cool_rate": 0.30, "scope": true,
		"handling": 1.45, "cam_recoil": 0.26, "kick_back": 1.6,
	},

	# --- AUTOMATA -----------------------------------------------------------
	# The light automaton's rifle is deliberately the WORST automatic in the game. That is the
	# joke and the balance both: droids come in numbers.
	Class.X5: {
		"name": "X-5 Blaster", "fire_interval": 0.135, "damage": 15.0,
		"range": 58.0, "hip_spread": 3.4, "ads_spread": 1.15, "zoom_fov": 64.0,
		"heat_per_shot": 0.06, "cool_rate": 0.46, "scope": false,
		"handling": 0.86, "cam_recoil": 0.013,
	},
	Class.X5S: {
		"name": "X-5S Sniper", "fire_interval": 1.35, "damage": 110.0,
		"range": 240.0, "hip_spread": 5.5, "ads_spread": 0.0, "zoom_fov": 24.0,
		"heat_per_shot": 0.45, "cool_rate": 0.28, "scope": true,
		"handling": 1.45, "cam_recoil": 0.25, "kick_back": 1.4,
	},
	# THE DESTROYER'S TWIN REPEATERS: the highest sustained output in the game
	# and a heat pool that punishes holding the trigger. Paired with the personal
	# shield, this is a unit you have to flank rather than out-shoot.
	Class.AEGIS_TWIN: {
		"name": "Twin Repeaters", "fire_interval": 0.055, "damage": 13.0,
		"range": 70.0, "hip_spread": 2.4, "ads_spread": 1.0, "zoom_fov": 68.0,
		"heat_per_shot": 0.042, "cool_rate": 0.34, "scope": false,
		"handling": 1.60, "cam_recoil": 0.007,
		"alternate_muzzles": true, "muzzle_x": 0.24, "muzzle_y": -0.14, "muzzle_z": -0.34,
	},
	# Vespid sonic: a slow projectile-feeling blast with real splash, which is
	# the only Automata answer to somebody in cover.
	# THE VESPID'S GUN, and at 0.85 s a cycle it was the worst trade in the
	# game by a wide margin: three rounds over 1.85 s from a body with 66 health.
	# A Vespid is a flying skirmisher — it is SUPPOSED to be fragile, but a
	# unit that is fragile AND cannot shoot is not a glass cannon, it is glass.
	# The rate is what moved; the damage and the blast are its character and were
	# already right.
	Class.SONIC_BLASTER: {
		"name": "Sonic Blaster", "fire_interval": 0.60, "damage": 46.0,
		"range": 55.0, "hip_spread": 1.4, "ads_spread": 0.5, "zoom_fov": 62.0,
		"heat_per_shot": 0.26, "cool_rate": 0.32, "scope": false,
		"handling": 1.05, "cam_recoil": 0.06,
		"splash": 3.2, "splash_damage": 34.0,
	},
	# The BX's blade. Shorter reach than a arc blade and no guard behind it —
	# a commando droid that closes has committed.
	Class.VIBROSWORD: {
		"name": "Vibrosword", "fire_interval": 0.34, "damage": 74.0,
		"range": 3.5, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 75.0,
		"heat_per_shot": 0.0, "cool_rate": 1.0, "scope": false,
		"cam_recoil": 0.024, "melee": true,
		"blade_core": Color(0.72, 0.74, 0.80), "blade_glow": Color(0.30, 0.34, 0.40),
		"blade_len": 0.62, "blade_width": 0.048, "blade_energy": 0.0,
	},

	# --- DOMINION ---------------------------------------------------------------
	Class.DK11: {
		"name": "DK-11 Blaster", "fire_interval": 0.12, "damage": 18.0,
		"range": 66.0, "hip_spread": 2.5, "ads_spread": 0.7, "zoom_fov": 60.0,
		"heat_per_shot": 0.06, "cool_rate": 0.50, "scope": false,
		"handling": 0.92, "cam_recoil": 0.012,
	},
	Class.DK19: {
		"name": "DK-19 Heavy", "fire_interval": 0.095, "damage": 24.0,
		"range": 92.0, "hip_spread": 3.6, "ads_spread": 0.9, "zoom_fov": 58.0,
		"heat_per_shot": 0.055, "cool_rate": 0.34, "scope": false,
		"handling": 1.55, "cam_recoil": 0.022, "kick_back": 0.6,
	},
	Class.DK20A: {
		"name": "DK-20A", "fire_interval": 0.62, "damage": 62.0,
		"range": 150.0, "hip_spread": 2.4, "ads_spread": 0.0, "zoom_fov": 34.0,
		"heat_per_shot": 0.24, "cool_rate": 0.38, "scope": true,
		"handling": 1.40, "cam_recoil": 0.10,
	},
	# THE DEATH TROOPER'S RIFLE. The unit used to be listed as carrying the
	# SE-14r, which is sold as a SIDEARM — so weapon_index returned NO_PRIMARY
	# and the Dominion's most feared reinforcement deployed holding the free
	# starter pistol. It needed its own gun rather than a dominion trooper's E-11:
	# a suppressed rifle that trades the E-11's range for a much tighter cone
	# and a heavier round, which is how that unit is supposed to fight.
	Class.DK11D: {
		"name": "DK-11D Rifle", "fire_interval": 0.105, "damage": 21.0,
		"range": 74.0, "hip_spread": 2.0, "ads_spread": 0.42, "zoom_fov": 56.0,
		"heat_per_shot": 0.062, "cool_rate": 0.46, "scope": false,
		"handling": 0.90, "cam_recoil": 0.010,
	},
	# The death trooper's machine pistol: a shotgun's damage profile at a
	# carbine's range, and the reason that unit is feared at any distance.
	Class.SR14R: {
		"name": "SR-14R", "fire_interval": 0.07, "damage": 14.0,
		"range": 44.0, "hip_spread": 2.0, "ads_spread": 0.8, "zoom_fov": 66.0,
		"heat_per_shot": 0.055, "cool_rate": 0.50, "scope": false,
		"handling": 0.72, "cam_recoil": 0.009,
	},
	# THE INCINERATOR: no reach, no aim, no miss. A cone of pellets at ten metres
	# with a fast tick — the only gun in the game that cannot headshot and does
	# not care where the crosshair is.
	# Tuned with the rest of the flame family — see the note on Class.FLAMER. The
	# shortest reach of the three, because the Incinerator is the one that is
	# supposed to have none at all.
	Class.FLAMETHROWER: {
		"name": "Incinerator", "fire_interval": 0.09, "damage": 6.9,
		"range": 11.0, "hip_spread": 7.0, "ads_spread": 6.0, "zoom_fov": 70.0,
		"heat_per_shot": 0.030, "cool_rate": 0.30, "scope": false,
		"handling": 1.30, "cam_recoil": 0.003, "pellets": 3,
	},

	# --- PACT ALLIANCE -------------------------------------------------------
	Class.A28C: {
		"name": "A-28C", "fire_interval": 0.125, "damage": 20.0,
		"range": 78.0, "hip_spread": 2.3, "ads_spread": 0.6, "zoom_fov": 58.0,
		"heat_per_shot": 0.065, "cool_rate": 0.46, "scope": false,
		"handling": 0.95, "cam_recoil": 0.015,
	},
	Class.CR9: {
		"name": "CR-9 SMG", "fire_interval": 0.06, "damage": 13.0,
		"range": 38.0, "hip_spread": 3.0, "ads_spread": 1.4, "zoom_fov": 68.0,
		"heat_per_shot": 0.045, "cool_rate": 0.52, "scope": false,
		"handling": 0.76, "cam_recoil": 0.008,
	},
	Class.DH44: {
		"name": "DH-44 Sniper", "fire_interval": 1.15, "damage": 112.0,
		"range": 250.0, "hip_spread": 5.0, "ads_spread": 0.0, "zoom_fov": 22.0,
		"heat_per_shot": 0.40, "cool_rate": 0.32, "scope": true,
		"handling": 1.45, "cam_recoil": 0.25, "kick_back": 1.5,
	},
	# The Kobb's spear. The shortest reach and the highest melee damage in the
	# game: it is a joke unit that genuinely kills people, which is exactly what
	# the fanbase wants from it.
	Class.KOBB_SPEAR: {
		"name": "Kobb Spear", "fire_interval": 0.42, "damage": 92.0,
		"range": 4.0, "hip_spread": 0.0, "ads_spread": 0.0, "zoom_fov": 75.0,
		"heat_per_shot": 0.0, "cool_rate": 1.0, "scope": false,
		"cam_recoil": 0.028, "melee": true, "staff": true,
		"blade_core": Color(0.62, 0.48, 0.30), "blade_glow": Color(0.40, 0.30, 0.18),
		"blade_len": 0.34, "blade_width": 0.05, "hilt_len": 0.75,
		"blade_energy": 0.0,
	},

	# --- HALO -----------------------------------------------------------------
	# The COALITION's answer to a doorway: an arcing grenade that detonates on impact.
	Class.GL19: {
		"name": "GL-19 Grenadier", "fire_interval": 1.1, "damage": 58.0,
		"range": 90.0, "hip_spread": 1.2, "ads_spread": 0.4, "zoom_fov": 58.0,
		"heat_per_shot": 0.34, "cool_rate": 0.30, "scope": false,
		"handling": 1.30, "cam_recoil": 0.10, "projectile": true,
		"splash": 4.4, "splash_damage": 62.0,
	},
	# Brute spiker: fast, brutal up close and wildly inaccurate past it.
	Class.SPIKER: {
		"name": "Spiker", "fire_interval": 0.08, "damage": 16.0,
		"range": 42.0, "hip_spread": 3.8, "ads_spread": 1.8, "zoom_fov": 68.0,
		"heat_per_shot": 0.05, "cool_rate": 0.48, "scope": false,
		"handling": 0.86, "cam_recoil": 0.012,
	},

	# =========================================================================
	# THE LIGHT MACHINE GUNS.
	#
	# WHAT AN LMG IS, AS A CONTRACT, and it is a shape no other row in this table
	# has: it is the most CONTROLLABLE gun in the game while it is braced, and
	# the worst one in every other situation. Low `cam_recoil` for the damage it
	# puts out — a machine gun that climbs is a machine gun nobody fires past the
	# third round, and the whole reason to carry the weight is that the twentieth
	# round goes where the first one did. It pays for that in `hip_spread` (the
	# widest cones here), in `ads_spread` that never quite reaches zero, and in a
	# heat pool it is always somewhere inside.
	#
	# They are spread ALONG THE RATE/DAMAGE AXIS rather than clustered, because
	# four guns that differ only in name is the failure this category already
	# had. Rounds-to-kill on a 100 hp trooper, and seconds to get there:
	#
	#   RT-97C        3 rounds, 0.52 s   the slow one: 38 a round, rifle reach
	#   Gauss Cannon  3 rounds, 0.56 s   ...and it ignores the cone entirely
	#   DLT-19D       4 rounds, 0.45 s   the middle, and the one you walk fire with
	#   M739 SAW      7 rounds, 0.36 s   the fast one: a hose with a deep pool
	# =========================================================================

	# THE SLOW ONE. Fires at a rifle's rate and hits like a marksman weapon, and
	# it is the LMG for somebody who wants to fight at range: the tightest ADS
	# cone of the four and the only one that reaches past 120 m.
	Class.RT9: {
		"name": "RT-9 Heavy Blaster", "fire_interval": 0.175, "damage": 38.0,
		"range": 145.0, "hip_spread": 4.8, "ads_spread": 0.34, "zoom_fov": 46.0,
		"heat_per_shot": 0.058, "cool_rate": 0.30, "scope": false,
		"handling": 1.65, "cam_recoil": 0.030,
	},
	# THE MIDDLE ONE, and the one that behaves most like the category's
	# reputation: a suppressor you hold on a doorway and walk across a squad.
	Class.DK19D: {
		"name": "DK-19D Suppressor", "fire_interval": 0.115, "damage": 26.0,
		"range": 120.0, "hip_spread": 5.2, "ads_spread": 0.85, "zoom_fov": 52.0,
		"heat_per_shot": 0.040, "cool_rate": 0.32, "scope": false,
		"handling": 1.60, "cam_recoil": 0.019,
	},
	# THE FAST ONE. Least damage a round of anything in the category and the
	# deepest pool to spend, so it is the one that answers a rush rather than a
	# rifleman. Its cone is the price.
	Class.SAW7: {
		"name": "SAW-7", "fire_interval": 0.052, "damage": 15.0,
		"range": 85.0, "hip_spread": 5.6, "ads_spread": 1.5, "zoom_fov": 60.0,
		"heat_per_shot": 0.028, "cool_rate": 0.34, "scope": false,
		"handling": 1.55, "cam_recoil": 0.014,
	},
	# THE UNSLEEPING ONE: slow, enormous per round, and it does not climb at all,
	# because nothing about a gauss weapon is being held back by a man's
	# shoulder. The trade is the slowest cooling of the four.
	Class.GAUSS_CANNON: {
		"name": "Gauss Cannon", "fire_interval": 0.19, "damage": 40.0,
		"range": 135.0, "hip_spread": 4.4, "ads_spread": 0.30, "zoom_fov": 48.0,
		"heat_per_shot": 0.068, "cool_rate": 0.26, "scope": false,
		"handling": 1.75, "cam_recoil": 0.024,
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
## What a shot costs the heat pool, as a MULTIPLIER on the profile's own figure.
## Written from outside (the COOLANT sustained ability) rather than folded into
## `_upgraded_profile` like a fitted mod, because it is a WINDOW and not a
## purchase — a mod is true for the life, this is true for seven seconds.
var heat_mult := 1.0
var _cooldown := 0.0
var _heat := 0.0
var _overheated := false
var _burst_left := 0
var _bloom := 0.0  # extra hip-fire spread (deg) built up by sustained fire
var _spin := 0.0   # seconds the trigger has been held, for spin-up weapons
var _muzzle_side := -1.0
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

## AT NIGHT THE MUZZLE FLASH IS NOT A DETAIL, IT IS THE LIGHTING. By day it is a
## flicker on the wall beside you competing with a sun; in the dark it is the
## only thing illuminating the ground for twenty metres, and a 6.5 m flash that
## is gone in 55 ms simply does not read as that. All three of its dials go up
## together, and the RANGE by the most — reach is what turns a flash on your own
## hands into a flash that shows you the man you are shooting at.
##
## It costs nothing extra: the light already exists and is already toggled, so
## this is three numbers resolved once at spawn, not a second light.
const NIGHT_FLASH_RANGE := 3.1
const NIGHT_FLASH_ENERGY := 1.6
const NIGHT_FLASH_TIME := 1.7

var _muzzle_light: OmniLight3D
var _flash_left := 0.0
## The flash's dials for this match — the constants above, times the night
## multipliers if this is a night match. Resolved at spawn rather than asked per
## shot: a repeater fires thirteen times a second and the answer cannot change
## inside a match.
var _flash_time := FLASH_TIME
var _flash_energy := FLASH_ENERGY
var _impacts_left := 0     # impact bursts still allowed on this trigger pull

## --- THE BLADE'S VOICE -------------------------------------------------------
##
## How far the hum bends on a swing, and how fast that settles. The hum's pitch
## rising as the blade moves is the same doppler `_saber_swing` carries, and it is
## what stops a lit blade sounding like a held note with whooshes played over it.
##
## Driven off the SWING rather than off the weapon's measured motion, because a
## bot has no viewmodel and no camera: a swing is a shot, both of them fire one,
## and this way both sound the same.
const HUM_SWING_BEND := 0.22
const HUM_SWING_SETTLE := 3.2
## A refused hum asks again on this timer and not every tick — a claim walks the
## combatant list, and a fourth blade with a three-slot pool would otherwise ask
## sixty times a second for the whole match.
const HUM_RETRY := 0.75

var _hum_token := 0
var _hum_lit := false      # was a lit blade in hand last tick
var _hum_retry := 0.0
var _swing_t := 0.0        # 1 on the frame of a swing, settling to 0


func _ready() -> void:
	var night: bool = GameState.is_night()
	_flash_time = FLASH_TIME * (NIGHT_FLASH_TIME if night else 1.0)
	_flash_energy = FLASH_ENERGY * (NIGHT_FLASH_ENERGY if night else 1.0)
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.omni_range = FLASH_RANGE * (NIGHT_FLASH_RANGE if night else 1.0)
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
	# ...and drops the COOLANT discount, because a rebuilt weapon knows nothing
	# about a window somebody else is counting down. The owner re-pushes it every
	# tick while it is up (`Player._update_sustained`), so a swap mid-window
	# keeps working and this line only ever clears a stale one. The window
	# belongs to the BODY, not to the gun that was in its hands when it opened —
	# the alternative is an ability the HUD shows running while a weapon swap has
	# silently switched it off.
	heat_mult = 1.0
	_burst_left = 0
	_bloom = 0.0
	_spin = 0.0
	heat_changed.emit(_heat, _overheated)
	if _viewmodel:
		_viewmodel.configure(c, has_scope(), has_holo())
		# THE GUN IS LIT IN THE TEAM'S COLOUR FROM THE MOMENT IT IS DRAWN, not
		# from the first shot. `configure` rebuilds the weapon from scratch, so
		# this is the one place that always runs after the materials exist — on
		# deploy, on every swap, and on a class change.
		_viewmodel.set_light_color(bolt_color())


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
	# FRONT GRIP tames the kick — the camera climb, the gun's own visible climb
	# (derived from it) and the body shove of the heavy guns — and touches nothing
	# about accuracy.
	if upgrades.get("foregrip", false):
		p["cam_recoil"] = float(p["cam_recoil"]) * FOREGRIP_RECOIL_MULT
		p["kick_back"] = float(p.get("kick_back", 0.0)) * FOREGRIP_RECOIL_MULT
	return p


## Dump the whole heat pool and clear a lockout, right now. The COOLANT ability's
## other half — and it is the half you feel, because a lockout is the one state
## in this game where a gun stops being a gun and there was nothing anywhere in
## the catalogue that could answer one.
func vent() -> void:
	_heat = 0.0
	_overheated = false
	heat_changed.emit(_heat, _overheated)


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


## The Saurian's thermal ring: aims like a holo, but the HUD paints enemy
## heat through smoke while it is raised. Load-bearing for the heat overlay in
## Main, nothing else.
func has_thermal() -> bool:
	return _profile.get("thermal", false)


## A blade rather than a gun: same hitscan, no tracer, no muzzle flash, and no
## sights to raise — the aim control blocks with it instead (see Player).
## WHICH VOICE THIS GUN HAS. A family, not a per-gun sample: sixty rows would
## mean sixty sounds nobody could tell apart, and the families genuinely do sound
## different from each other — a bolt-propelled shell is a bang, plasma is a
## fizz, gauss is a rising whine, a blaster is a falling zap.
##
## Stated only for the EXCEPTIONS. Everything unlisted falls through the rule
## below, so a new The Compact Wars gun needs no entry at all and a new Unsleeping one needs
## a single line. Note it is keyed on the class rather than on a "sound" key in
## PROFILES for exactly the reason the melee look is not: sixty rows would have
## to be edited to add one family.
const VOICES := {
	Class.PLASMA_RIFLE: "plasma", Class.PLASMA_PISTOL: "plasma",
	Class.NEEDLER: "plasma", Class.HIER_CARBINE: "plasma",
	Class.BEAM_RIFLE: "plasma", Class.FUEL_ROD: "plasma",
	Class.CLEAVER_GUN: "shellgun", Class.MAULER: "shellgun",
	Class.PLASMA_GUN: "plasma", Class.ORDER_PLASMA_PISTOL: "plasma",
	Class.FUSION_GUN: "plasma", Class.FLAMER: "plasma", Class.TORCH: "plasma",
	Class.HEAT_RAY: "plasma", Class.LANCE_LASER: "plasma",
	Class.SHELLGUN: "shellgun", Class.HEAVY_BOLTER: "shellgun",
	Class.STALKER_BOLT: "shellgun", Class.BOLT_PISTOL: "shellgun",
	Class.GRENADE_LAUNCHER: "shellgun", Class.SCRAP_ROCKET: "shellgun",
	Class.SLUGTHROWER: "shellgun", Class.BIG_SHOOTA: "shellgun", Class.SLUG_PISTOL: "shellgun",
	Class.JUNK_BLASTER: "shellgun",
	Class.AR7: "shellgun", Class.BR3: "shellgun", Class.S9_SMG: "shellgun",
	Class.CQ12: "shellgun", Class.LR99: "shellgun", Class.RL8: "shellgun",
	Class.S6: "shellgun", Class.HM40: "shellgun", Class.DM3: "shellgun",
	Class.GAUSS_RIFLE: "gauss", Class.GAUSS_BLASTER: "gauss",
	Class.TESLA_CARBINE: "gauss", Class.SYNAPTIC_DISINTEGRATOR: "gauss",
	Class.TRANSDIMENSIONAL_BEAMER: "gauss", Class.GAUSS_PISTOL: "gauss",
	# The faction guns. The Deep Range pair take their side's voice; the incinerator and
	# the sonic blaster are the two weapons here that are neither a crack nor a
	# zap, so they borrow the plasma family's fizz.
	Class.GL19: "shellgun", Class.SPIKER: "shellgun",
	Class.FLAMETHROWER: "plasma", Class.SONIC_BLASTER: "plasma",
}
## Above this, a blaster gets the heavier voice. Damage rather than a per-gun
## flag because it is already the number that says how big a gun is.
const HEAVY_VOICE_DAMAGE := 44.0


func _voice() -> String:
	if is_melee():
		# A lit blade has its own swing — pitched, because what you hear is the
		# hum being moved, where a steel edge is just air.
		return "saber_swing" if blade_is_energy() else "melee_swing"
	if VOICES.has(weapon_class):
		return VOICES[weapon_class]
	if float(_profile["damage"]) >= HEAVY_VOICE_DAMAGE \
			or _profile.get("projectile", false):
		return "blaster_heavy"
	return "blaster"


## WHAT COLOUR THIS GUN'S FIRE IS — the tracer, the muzzle light and the impact
## scorch all ask this one question now. They used to disagree: the light and the
## scorch took the profile's `flash` while every bolt in the game, in all three
## universes, was one shared burnt-orange material. A gun that lights the wall
## green and then puts an orange round into it is two guns.
##
## Stated only for the EXCEPTIONS, exactly like VOICES. A weapon with a colour of
## its own keeps it, so plasma stays plasma and gauss stays green in whoever's
## hands. Everything unlisted — which is every ordinary blaster row, and those
## rows are shared by all four The Compact Wars sides — takes the colour its own ARMY
## issues, which is what makes legionary fire blue and droid fire red without either
## needing a weapon the other cannot hold.
##
## Resolved per trigger pull rather than once at spawn, unlike the flash's other
## three dials: this depends on the profile AND on the shooter, and those are
## assigned in either order by Player, Bot and Turret. It costs one dictionary
## get, against a scene instantiation happening on the same line.
func bolt_color() -> Color:
	if _profile.has("flash"):
		return _profile["flash"]
	if shooter != null and is_instance_valid(shooter) and "team" in shooter:
		return GameState.bolt_color(shooter.team)
	return FLASH_DEFAULT


## A LIT BLADE, as opposed to a length of steel — a arc blade, an energy sword,
## a power sword, the electrostaff. Asked of `blade_energy`, the key that already
## tells the viewmodel to build a glowing blade instead of a dull one, so the
## thing that HUMS and the thing that GLOWS can never disagree and no new table
## row was needed to say which is which.
func blade_is_energy() -> bool:
	return is_melee() and float(_profile.get("blade_energy", 1.0)) > 0.0


func is_melee() -> bool:
	return _profile.get("melee", false)


## A staff rather than the saber: the viewmodel and the third-person model draw a
## two-ended electro-pole and a shield-on-guard instead of a single blade. Purely
## which melee LOOK to build — the block mechanic is the same for both.
func is_staff() -> bool:
	return _profile.get("staff", false)


## What a melee weapon LOOKS like, for whoever is drawing it — the first-person
## viewmodel and the third-person model both build their blade from this, so a
## arc blade, an energy sword, a chain blade and a thunder hammer are one code
## path and four table rows.
##
## `energy` 0 means a DULL edge: steel that does not glow, which is the whole
## difference between a chain blade and a power sword. Defaults are the
## arc blade's, so an existing melee profile that says nothing is unchanged.
const BLADE_LOOK_KEYS := ["blade_core", "blade_glow", "blade_len", "blade_width",
	"blade_energy", "hilt_len"]

## A slim blade builds as a cylinder; anything fatter than this (per RADIUS, so
## half the stated `blade_width`) builds as a boxed HEAD. The threshold is what
## separates "a sword" from "a lump on a stick" — a fat cylinder reads as a
## rolling pin and a boxed sword reads as a plank.
##
## It lives here, with the profiles it classifies, because BOTH viewpoints need
## it and they must never disagree about what the player is holding: it also
## decides who carries a POWER FIELD. Every boxed head in the game is a power
## weapon (grav hammer, thunder hammer, power klaw) and every steel cylinder is
## a plain length of metal (chain blade, choppa), so the shape split IS the field
## rule and no profile needs a key for it.
const BLADE_HEAD_WIDTH := 0.045


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
## WHAT THIS GUN IS LIKE WHEN AIMED, WHICH IS THE AI'S MODEL AND NOT THE SHOT.
##
## It is deliberately NOT zero, even though `current_spread_deg` is pinpoint down
## the sights now. A Bot derives its whole stand-off from this (`_hit_reach`:
## a shot lands while the tier's wobble plus the gun's cone keeps it inside a
## body at that range), so zeroing it here would silently move every ADS-capable
## bot's fighting range outward and collapse the difference between a scoped
## rifle and an iron-sighted one — `tests/bot_range.tscn` caught exactly that.
##
## Pinpoint aiming is a rule about what a PLAYER is promised by a sight picture.
## Turning it into an AI rebalance as a side effect would be a second, unasked-for
## change hiding inside the first, so the column still describes how tight each
## gun is when aimed and the AI still tunes against it, unchanged.
func aimed_spread_deg() -> float:
	return 0.0 if has_scope() else _profile["ads_spread"]


func hip_spread_deg() -> float:
	return _profile["hip_spread"]


## The spread cone half-angle (deg) a shot would use right now — hip fire adds
## the accumulated bloom, aiming stays tight. Used by the bloom crosshair.
##
## AIMING IS PINPOINT. On every gun, with every sight, in every stance: while the
## sights are up the shot goes exactly where the reticle is and nowhere else.
##
## It used to be the SCOPE's promise alone, and everything else kept a small
## `ads_spread` cone — so aiming an iron-sighted rifle still threw rounds inside
## a cone you could see the reticle drawing, which is the one thing a sight
## picture is supposed to rule out. What a player is told by looking down the
## sights is "the round goes there"; a gun that then answers "roughly there"
## reads as the game cheating, and no amount of tuning the number fixes the
## disagreement — the eye believes the sight picture (the same argument the
## viewmodel kick is derived rather than authored for).
##
## WHAT AIMING STILL COSTS, so this is a trade and not a free upgrade: you move
## slower (`ADS_SPEED_MULT`), you cannot do it at a run, coming out of a sprint
## takes the weapon's own handling time, and RECOIL is untouched — the cone is
## gone, the climb is not, so a held trigger still walks off the target. Hip fire
## keeps its bloom, its stance multipliers and the grip mods that tighten it.
##
## The rule lives HERE rather than as a zeroed `ads_spread` column, so it covers
## every profile including future ones and cannot be quietly undone by a table
## entry — the same reason the scope's version of it lived here.
func current_spread_deg() -> float:
	# Zero while aimed no matter the stance, so the multiplier below never has
	# anything to widen.
	var base: float = 0.0 if aiming else _profile["hip_spread"] + _bloom
	# Stance widens the cone on the move and tightens it crouched. The HUD bloom
	# crosshair reads this same value, so the reticle blooms as you run and
	# settles as you stand — the accuracy penalty is legible, not hidden.
	return base * stance_spread_mult


# Fixed-timestep so heat/cooldown/burst behave identically regardless of render
# framerate (important on the Pi) and on the same clock as firing.
func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_update_blade_voice(delta)
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_muzzle_light.visible = false
		else:
			# Decay rather than a hard cut: a flash that switches off looks like a
			# dropped frame, and the falloff is most of what reads as a flash.
			_muzzle_light.light_energy = _flash_energy * (_flash_left / _flash_time)
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


## `cam_recoil` IS WHAT A TRIGGER PULL COSTS, NOT WHAT ONE ROUND COSTS, and for a
## burst weapon those are three different things.
##
## A burst puts its rounds out 55-60 ms apart. Recoil settles at
## `Player.RECOIL_RECOVER` (6/s), so across a whole burst barely 7% of the first
## round's kick has decayed before the third lands — they stack almost perfectly.
## Charging the full number three times meant the EL-16 threw the camera up 13.7
## degrees on ONE PULL, and the learn-pattern's first-shot weighting pushed that
## past 18. That is not a hard gun, it is a gun that cannot be fired twice at the
## same target, and it is exactly what "the burst gun is unusable" was.
##
## So the number in the table is the cost of the PULL and the rounds share it.
## That also makes the column comparable across fire modes for the first time:
## the EL-16's 0.055 and the A280's semi-automatic 0.105 now mean the same thing.
func _shot_recoil() -> float:
	var kick := float(_profile["cam_recoil"])
	if _profile.get("mode", FireMode.AUTO) == FireMode.BURST:
		kick /= maxf(1.0, float(_profile.get("burst_count", 1)))
	return kick


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
func _flash_muzzle(local_pos := Vector3(0.0, 0.0, -0.45)) -> void:
	if _muzzle_light == null or is_melee():
		return
	_muzzle_light.position = local_pos
	var col := bolt_color()
	_muzzle_light.light_color = col
	# The glow at the barrel tip is the shooter's own view of the same shot.
	if _viewmodel:
		_viewmodel.set_flash_color(col)
		_viewmodel.set_light_color(col)
	_muzzle_light.light_energy = _flash_energy
	_muzzle_light.visible = true
	_flash_left = _flash_time


## Stow the first-person weapon across the chest while sprinting, or bring it
## back up. Forwarded rather than reached for, the same as parry(): the viewmodel
## is this node's private child and Player is what knows it is running.
##
## A blade ignores it — the saber and staff have their own pose path, and a
## melee weapon carried "not ready" is a distinction without a difference.
## THE STOW AMOUNT, 0 up and 1 fully carried across the chest. Player owns the
## timer because it decides whether the TRIGGER works (`Player.weapon_ready`),
## and the viewmodel is handed the answer rather than running a second clock —
## two timers is how the gun on screen and the gun in the rules come to disagree
## about whether you can shoot.
func set_sprint_amount(v: float) -> void:
	if _viewmodel and "sprint_amount" in _viewmodel:
		_viewmodel.sprint_amount = clampf(v, 0.0, 1.0)
		_viewmodel.sprinting = v > 0.5


func set_sprinting(on: bool) -> void:
	if _viewmodel and "sprinting" in _viewmodel:
		_viewmodel.sprinting = on and not is_melee()


## IGNITE, HUM, RETRACT — driven off what is in hand rather than pushed by the
## swap that put it there.
##
## Two reasons it is a poll and not an event. `set_class` runs before the weapon is
## in the tree (Player._ready assigns the shooter and calls it on the next line),
## and neither the ignition nor the hum can be positioned until it is; and a blade
## should fall silent when its owner dies, which is not a swap at all. Asking "is
## a lit blade in a living hand" every tick answers all of it in one place.
func _update_blade_voice(delta: float) -> void:
	_swing_t = maxf(_swing_t - HUM_SWING_SETTLE * delta, 0.0)
	if not is_inside_tree():
		return
	var lit := blade_is_energy() and _owner_alive()
	if lit != _hum_lit:
		_hum_lit = lit
		Audio.play_at("saber_on" if lit else "saber_off", global_position)
		if not lit:
			Audio.release_loop(_hum_token)
			_hum_token = 0
			_hum_retry = 0.0
	if not lit:
		return
	if _hum_token != 0:
		Audio.move_loop(_hum_token, global_position,
			1.0 + HUM_SWING_BEND * _swing_t)
		return
	# No voice: the bank may still be rendering, or three nearer blades may hold
	# the whole pool. Either way this weapon works fine without one.
	_hum_retry -= delta
	if _hum_retry <= 0.0:
		_hum_retry = HUM_RETRY
		_hum_token = Audio.claim_loop("saber_hum", global_position)


## A blade in a dead hand is not lit. Duck-typed on `is_alive()` like everything
## else that asks a combatant anything; a turret has no melee and never gets here,
## and a weapon on a test bench with no shooter counts as live.
func _owner_alive() -> bool:
	if shooter == null or not is_instance_valid(shooter):
		return true
	return not shooter.has_method("is_alive") or shooter.is_alive()


## Release the pool slot on the way out. An autoload outlives the scene, so a hum
## not released here is a hum that plays for the rest of the session.
func _exit_tree() -> void:
	Audio.release_loop(_hum_token)
	_hum_token = 0


## The owner's guard just stopped a hit; show it on the blade. Forwarded rather
## than reached for, because the viewmodel is this node's private child — Player
## knows about the block, and Weapon is the one thing that knows where the model
## holding it lives.
func parry() -> void:
	if _viewmodel and _viewmodel.has_method("parry"):
		_viewmodel.parry()
	# Heard as well as seen. This is raised from Player._absorb_with_guard, the one
	# place that knows the block was actually paid for — the same rule as the hit
	# marker, so a clash can never sound for a shot that was not stopped.
	if is_inside_tree():
		Audio.play_at("saber_clash" if blade_is_energy() else "melee_hit",
			global_position)


func _fire_shot() -> void:
	var tracer_muzzle := global_position - global_transform.basis.y * 0.12
	var flash_local := Vector3(0.0, 0.0, -0.45)
	if _profile.get("alternate_muzzles", false):
		_muzzle_side = -_muzzle_side
		flash_local = Vector3(
			float(_profile.get("muzzle_x", 0.0)) * _muzzle_side,
			float(_profile.get("muzzle_y", -0.12)),
			float(_profile.get("muzzle_z", -0.45)))
		tracer_muzzle = global_transform * flash_local
	_heat = minf(_heat + _profile["heat_per_shot"] * heat_mult, 1.0)
	if _heat >= 1.0:
		_overheated = true
	heat_changed.emit(_heat, _overheated)
	var kick := _shot_recoil()
	if _viewmodel:
		_viewmodel.kick(kick * VIEW_KICK_PER_RAD)
	_flash_muzzle(flash_local)
	Audio.play_at(_voice(), global_position)
	if is_melee():
		_swing_t = 1.0   # bends the hum for as long as the swing lasts
	fired.emit(kick, _profile.get("kick_back", 0.0))
	# Hip fire blooms the cone; aiming down sights stays precise.
	if not aiming:
		_bloom = minf(_bloom + _profile["hip_spread"] * 0.4, _profile["hip_spread"] * 2.2)
	if _profile.get("projectile", false):
		_fire_rocket()
	else:
		_fire_hitscan(tracer_muzzle)


## One trigger pull. Most guns fire a single ray; a scattergun fires `pellets`
## of them through the same cone.
##
## Damage is POOLED per target rather than applied per pellet: seven separate
## take_damage calls would fire seven hit-ticks and seven markers for one shot,
## and would also let a single pellet's headshot flag decide the whole shot. A
## pellet that lands on a head still counts double, but the target is told once.
func _fire_hitscan(muzzle: Vector3) -> void:
	var pooled := {}   # target -> [damage, any_headshot]
	if is_melee():
		# A swing connects on a forward ARC, not a pinpoint ray — see _melee_strike.
		_melee_strike(pooled)
	else:
		var from := global_position
		var pellets: int = _profile.get("pellets", 1)
		var damage: float = _profile["damage"]
		_impacts_left = IMPACTS_PER_SHOT
		# Resolved once for the whole pull: a scattergun throws eight of these and
		# every pellet is the same gun in the same hands.
		var col := bolt_color()
		for i in pellets:
			var end := _trace_pellet(from, pooled, damage)
			var bolt := BOLT_SCENE.instantiate()
			get_tree().current_scene.add_child(bolt)
			bolt.launch(muzzle, end, col)
	for target in pooled:
		var entry: Array = pooled[target]
		target.take_damage(entry[0], shooter, entry[1])


## SOMEBODY ELSE'S SHOT, DRAWN HERE. A remote body's gunfire has to be visible —
## the muzzle flash is the best realism-per-line in the game and at night it is
## most of the lighting — but the shot itself was resolved on the machine that
## fired it, and resolving it a second time here would double every hit.
##
## So this is deliberately the cosmetic HALF of `_fire_shot` and nothing else: no
## ray, no damage, no heat, no recoil signal, no bloom. It is the whole reason a
## proxy carries a real `Weapon` rather than a mesh — the flash colour, the voice,
## the tracer and the bolt colour all fall out of the gun's own profile, so a
## remote Hierophany rifle sounds and lights like one with no second table.
##
## The tracer's far end is guessed from the barrel rather than sent: at 13 rounds
## a second the endpoint is four bytes a shot to place a line that exists for a
## tenth of a second, and its DIRECTION — which is what a player reads off a
## tracer — is already exact.
func fire_cosmetic() -> void:
	var muzzle := global_position - global_transform.basis.y * 0.12
	_flash_muzzle()
	Audio.play_at(_voice(), global_position)
	if is_melee():
		_swing_t = 1.0
		return
	var col := bolt_color()
	var to := muzzle - global_transform.basis.z * float(_profile["range"])
	var query := PhysicsRayQueryParameters3D.create(muzzle, to)
	query.collision_mask = 1   # WORLD only: a tracer stops at a wall, not at a body
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var bolt := BOLT_SCENE.instantiate()
	get_tree().current_scene.add_child(bolt)
	bolt.launch(muzzle, hit.get("position", to), col)


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
		# BATTLE FURY makes the swing heavier. Asked of the shooter rather than
		# stored on the weapon, because the buff belongs to the body and the
		# weapon is rebuilt on every swap.
		var swing: float = _profile["damage"]
		if shooter != null and shooter.has_method("fury_up") and shooter.fury_up():
			swing *= Player.FURY_MELEE
		pooled[best] = [swing, false]
		# The swing already played when the trigger went; this is the CONTACT,
		# and a swing that lands has to sound different from one that does not —
		# that is the only feedback a melee fighter gets that they connected.
		Audio.play_at("melee_hit", best.global_position)


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
		burst.burst(end, hit.get("normal", Vector3.UP), bolt_color())
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
