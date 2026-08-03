extends Node3D
## First-person weapon viewmodel: a procedural blaster the OWNING player sees
## (rendered on a per-player viewmodel layer set by Player). Purely cosmetic —
## it hangs under the fixed Weapon aim anchor and animates independently, so
## recoil/bob/ADS never move the actual fire ray (that stays on Weapon's -Z).
##
## Animation is procedural, in the Minecraft/Krunker spirit of the rest of the
## game: a spring-back recoil kick + muzzle flash on fire, a gentle walk bob,
## and an aim-down-sights slide to center. The parent Weapon drives it by
## calling configure() on class change and kick() on each shot; it reads
## aiming/scope straight off the parent.

const HIP_POS := Vector3.ZERO
# How far the gun is biased while aimed. The left/up part of the ADS slide
# is NOT a constant: it's solved per gun in _aim_offset() so whichever sight is
# fitted ends up on the camera axis. Hard-coding it lined the old shared body up
# by hand, but every receiver here is a different height and the sight drifted
# off centre as soon as the guns stopped being identical.
# Slightly forward, not back: rear furniture and stocks crossing the near plane
# read as hollow/see-through exactly when the player raises the gun.
const ADS_PULL_BACK := -0.025
const SIGHT_CHANNEL_X := 0.018
const IRON_REAR_Z := -0.02
const HOLO_Z := -0.08

## THE SPRINT CARRY, from the inside. The third-person model already drops the
## weapon and swings it across the chest while running (CharacterModel's
## RUN_GUN_POS) — so everyone ELSE could see a sprinting player stow their gun,
## and the only person who could not was the one doing it.
##
## Same idea, different scale: a first-person camera sits 30 cm from the receiver,
## so where the body model swings the weapon 62 degrees across, this drops it out
## of the sight line and tips the muzzle down and inboard. It reads as "I am not
## in a position to shoot", which is exactly true — sprinting already denies the
## sights (Player._is_running).
const SPRINT_AT := Vector3(0.06, -0.17, 0.07)
const SPRINT_ROT := Vector3(-0.60, 0.95, -0.42)
## Out fast, back in faster. Coming OUT of the sprint is the one that matters:
## the gun has to be back in the aim by the time the player can shoot, or the
## first shot of every engagement is fired from a stowed weapon.
const SPRINT_IN := 0.18    # seconds to stow
const SPRINT_OUT := 0.10   # ...and to bring it back up
const AIM_TIME := 0.12       # seconds to fully raise/lower sights
const RECOIL_DECAY := 6.0    # how fast the kick springs back
const KICK_CEILING := 1.8    # a burst stacks up to here before it stops growing
# How the accumulated kick reads on screen: shoved back toward the player,
# muzzle climbing, with a small lateral lean.
#
# Kept DELIBERATELY restrained. The gun is braced against a shoulder — it is the
# steadiest thing in the frame, and a viewmodel that whips around reads as jumpy
# rather than powerful. The force of a shot belongs on the CAMERA (Player's
# cam_recoil), which is the thing a real shooter feels move. Pushed to 0.42
# radians of flip this looked like the gun was being thrown, while the view
# behind it sat flat.
const KICK_PUSH := 0.12      # metres back per unit of kick
const KICK_PITCH := 0.20     # radians of muzzle climb per unit of kick
const KICK_LEAN := 0.06
# The pushback still needs a ceiling: the Weapon anchor sits only 0.3 m in front
# of the camera (0.25 m aimed), and past that the receiver crosses the near
# plane and the gun turns inside out.
const MAX_PUSH := 0.12
# ...and the gun settles further still once the sights are up. Aimed, the weapon
# is braced and your eye is ON the sight: the same flip that reads as weight
# from the hip throws the sight picture off the camera axis when you are looking
# through it. Scaled by _aim_t, so it eases in with the sights rather than
# snapping between two amounts.
const ADS_KICK_MULT := 0.4
const FLASH_TIME := 0.045

var aiming_source: Node3D    # the parent Weapon (aiming / has_scope live here)
## The render layer these meshes belong on: the owner's private viewmodel bit,
## so only their own camera sees the gun in their hands. 0 leaves them on the
## default layer, which is what a bot wants (its weapon IS a world object).
##
## Applied on every REBUILD, not once at spawn. Player used to set it on the
## meshes that existed when it became ready — and there are none, because the
## gun is built by the set_class on the very next line, and rebuilt again on
## every weapon swap and every respawn. All of those parts landed on layer 1, so
## every OTHER player saw this one's first-person weapon floating at their face.
## Unmissable once it was a metre of lit blade; a small dark rifle overlapping
## the third-person one is why it went unnoticed.
var view_layer := 0

var _player: CharacterBody3D
var _scope: MeshInstance3D
var _holo: Node3D
var _flash: MeshInstance3D
var _saber: Node3D           # the saber's own pivot, when a blade or staff is in hand
var _shield: Node3D          # the staff's off-hand guard shield, raised on the block
var _shield_mats: Array[StandardMaterial3D] = []  # every shield part, faded together
var _shield_alpha: Array[float] = []              # each part's full alpha
var _staff_cores: Array[StandardMaterial3D] = []  # the electrostaff's charged tips...
var _staff_glows: Array[StandardMaterial3D] = []  # ...and their auras, for the crackle
var _staff_bolts: Array = []  # small electric arcs at each tip: [{base, reach, segs}]
var _staff_arc_mat: StandardMaterial3D            # the shared bolt material
var _arc_box: BoxMesh        # one unit box, scaled per arc segment (no per-frame alloc)
var _crackle_t := 0.0        # phase of the electro flicker
var _swing := 0.0            # 1 at the start of a swing, decaying to 0
var _swing_side := 1.0       # alternates, so consecutive strikes cross over
var _parry := 0.0            # 1 the frame a hit is stopped, decaying to 0
var _parry_side := 1.0       # which way the blade is knocked, alternating
var _blade_core: StandardMaterial3D  # kept so a parry can flare them
var _blade_glow: StandardMaterial3D
## What the melee weapon currently in hand LOOKS like, read off its own profile
## in _build (see Weapon.melee_look). One saber builder and one staff builder
## serve every blade in every universe — a lightsaber, an energy sword, a
## chainsword and a thunder hammer differ by these six numbers and nothing else.
var _blade_col := BLADE_CORE
var _glow_col := BLADE_GLOW
var _blade_len := BLADE_LENGTH
var _blade_rad := BLADE_RADIUS
var _blade_energy := BLADE_ENERGY
var _hilt_len := 0.24
var _brace_t := 0.0          # phase of the guard's slow sway

var _kick := 0.0             # current recoil amount (0..KICK_CEILING), springs to 0
var _kick_yaw := 0.0         # random left/right lean per shot
var _aim_t := 0.0            # 0 hip .. 1 aimed
## 0 in the aim .. 1 fully stowed across the chest. Set by the owner every frame
## (see Weapon.set_sprinting); eased here.
var sprinting := false
var _sprint_t := 0.0
var _ads_pos := Vector3(-0.165, 0.055, ADS_PULL_BACK)  # solved in _build
var _bob_t := 0.0
var _flash_t := 0.0


func _ready() -> void:
	aiming_source = get_parent()
	# Walk up to the owning body for the bob (velocity/on-floor).
	var n: Node = get_parent()
	while n != null and not (n is CharacterBody3D):
		n = n.get_parent()
	_player = n as CharacterBody3D
	_build(Weapon.Class.SOLDIER, false, false)


## Every gun's silhouette, in parts. One shared body with a few toggles made the
## whole roster read as the same weapon, so each class gets its own proportions:
## receiver block, barrel length/bore, and which of stock / fore grip / drum /
## magazine / muzzle device it carries. Values are metres, in viewmodel space.
const SHAPES := {
	Weapon.Class.SOLDIER: {  # DC-15: standard-issue rifle
		"receiver": Vector3(0.05, 0.07, 0.26), "barrel": Vector3(0.028, 0.028, 0.34),
		"stock": true, "grip": true, "mag": Vector3(0.03, 0.11, 0.05), "muzzle": 0.05,
	},
	Weapon.Class.SNIPER: {  # NT-242: long, thin, all barrel
		"receiver": Vector3(0.045, 0.062, 0.3), "barrel": Vector3(0.022, 0.022, 0.62),
		"stock": true, "grip": false, "mag": Vector3(0.026, 0.07, 0.04), "muzzle": 0.07,
		"bipod": true,
	},
	Weapon.Class.HEAVY: {  # Z-6: squat repeater slung under a drum
		"receiver": Vector3(0.075, 0.085, 0.24), "barrel": Vector3(0.042, 0.042, 0.26),
		"stock": false, "grip": true, "drum": 0.055, "muzzle": 0.06,
	},
	Weapon.Class.HMG: {  # T-21: heavy, long, bipod
		"receiver": Vector3(0.07, 0.08, 0.34), "barrel": Vector3(0.05, 0.05, 0.44),
		"stock": true, "grip": true, "drum": 0.042, "muzzle": 0.08, "bipod": true,
	},
	Weapon.Class.BURST: {  # EL-16: boxy carbine
		"receiver": Vector3(0.055, 0.08, 0.24), "barrel": Vector3(0.026, 0.026, 0.28),
		"stock": true, "grip": true, "mag": Vector3(0.032, 0.13, 0.045), "muzzle": 0.04,
	},
	Weapon.Class.SEMI: {  # A280: long marksman rifle
		"receiver": Vector3(0.048, 0.07, 0.3), "barrel": Vector3(0.024, 0.024, 0.46),
		"stock": true, "grip": true, "mag": Vector3(0.028, 0.1, 0.045), "muzzle": 0.05,
	},
	Weapon.Class.RPG: {  # PLX-1: a tube, and not much else
		"receiver": Vector3(0.1, 0.1, 0.5), "barrel": Vector3(0.088, 0.088, 0.22),
		"stock": false, "grip": true, "muzzle": 0.13, "tube": true,
	},
	Weapon.Class.REVOLVER: {  # SE-14: heavy sidearm with a cylinder
		"receiver": Vector3(0.038, 0.06, 0.13), "barrel": Vector3(0.026, 0.026, 0.17),
		"stock": false, "grip": false, "cylinder": 0.045, "muzzle": 0.03,
	},
	Weapon.Class.PISTOL: {  # DL-44
		"receiver": Vector3(0.036, 0.058, 0.14), "barrel": Vector3(0.022, 0.022, 0.15),
		"stock": false, "grip": false, "mag": Vector3(0.026, 0.085, 0.035), "muzzle": 0.035,
	},
	Weapon.Class.HOLDOUT: {  # RK-3: stubby little thing
		"receiver": Vector3(0.034, 0.05, 0.1), "barrel": Vector3(0.018, 0.018, 0.08),
		"stock": false, "grip": false, "mag": Vector3(0.024, 0.07, 0.03), "muzzle": 0.025,
	},
	Weapon.Class.ROTARY: {  # R-90: barrel cluster on a huge drum
		"receiver": Vector3(0.09, 0.09, 0.26), "barrel": Vector3(0.03, 0.03, 0.42),
		"stock": false, "grip": true, "drum": 0.075, "muzzle": 0.05, "barrels": 4,
	},
	Weapon.Class.TURRET: {  # only ever seen as a world object, never in hand
		"receiver": Vector3(0.09, 0.09, 0.3), "barrel": Vector3(0.04, 0.04, 0.4),
		"stock": false, "grip": false, "muzzle": 0.07,
	},
	Weapon.Class.SMG: {  # Westar M5: small, stockless, tall magazine
		"receiver": Vector3(0.045, 0.07, 0.18), "barrel": Vector3(0.022, 0.022, 0.16),
		"stock": false, "grip": true, "mag": Vector3(0.03, 0.14, 0.04), "muzzle": 0.035,
	},
	Weapon.Class.CARBINE: {  # DC-15S: the rifle, cut down
		"receiver": Vector3(0.05, 0.07, 0.21), "barrel": Vector3(0.026, 0.026, 0.22),
		"stock": true, "grip": true, "mag": Vector3(0.03, 0.1, 0.045), "muzzle": 0.045,
	},
	Weapon.Class.SCATTERGUN: {  # FWMB-10: fat, short, no magazine
		"receiver": Vector3(0.07, 0.085, 0.28), "barrel": Vector3(0.055, 0.055, 0.24),
		"stock": true, "grip": true, "muzzle": 0.085,
	},
	Weapon.Class.DMR: {  # A280-CFE: long barrel, ships with optics
		"receiver": Vector3(0.046, 0.068, 0.3), "barrel": Vector3(0.023, 0.023, 0.52),
		"stock": true, "grip": true, "mag": Vector3(0.027, 0.095, 0.045), "muzzle": 0.055,
	},
	Weapon.Class.DH17: {  # DH-17: boxy service pistol
		"receiver": Vector3(0.038, 0.06, 0.15), "barrel": Vector3(0.024, 0.024, 0.13),
		"stock": false, "grip": false, "mag": Vector3(0.028, 0.09, 0.035), "muzzle": 0.03,
	},
	Weapon.Class.BRYAR: {  # Bryar: long-barrelled, cylinder under the receiver
		"receiver": Vector3(0.04, 0.062, 0.16), "barrel": Vector3(0.024, 0.024, 0.24),
		"stock": false, "grip": false, "cylinder": 0.04, "muzzle": 0.04,
	},
	Weapon.Class.BOWCASTER: {  # Wookiee crossbow: fat body, short bore, limbs
		"receiver": Vector3(0.072, 0.09, 0.22), "barrel": Vector3(0.03, 0.03, 0.18),
		"stock": true, "grip": true, "drum": 0.05, "muzzle": 0.04, "limbs": 0.15,
	},
	# The lightsaber is built by _build_saber, not from these fields: a hilt and
	# a blade share nothing with a receiver and a barrel. The entry exists so
	# the class is present in the table and `saber` can flag the branch.
	Weapon.Class.SABER: {
		"receiver": Vector3(0.042, 0.042, 0.24), "barrel": Vector3(0.03, 0.03, 0.0),
		"stock": false, "grip": false, "saber": true,
	},
	Weapon.Class.WRIST_CANNON: {  # SBD arm gun: chunky forearm block, stubby bore, no stock/grip
		"receiver": Vector3(0.062, 0.078, 0.22), "barrel": Vector3(0.046, 0.046, 0.26),
		"stock": false, "grip": false, "drum": 0.04, "muzzle": 0.075,
	},
	# Built by _build_staff, not from these fields (like the saber): a pole and two
	# electro-tips share nothing with a receiver. The entry exists so the class is
	# present and `staff` flags the branch.
	Weapon.Class.STAFF: {
		"receiver": Vector3(0.03, 0.03, 0.4), "barrel": Vector3(0.02, 0.02, 0.0),
		"stock": false, "grip": false, "staff": true,
	},

	# --- HALO: UNSC -----------------------------------------------------------
	# Boxy, top-heavy, magazine-fed. The MA5B's counter housing and the SPNKr's
	# twin tubes are the two silhouettes people actually recognise.
	Weapon.Class.MA5B: {  # MA5B: fat carry handle over a short barrel
		"receiver": Vector3(0.062, 0.09, 0.26), "barrel": Vector3(0.03, 0.03, 0.20),
		"stock": true, "grip": true, "mag": Vector3(0.036, 0.13, 0.055), "muzzle": 0.045,
	},
	Weapon.Class.BR55: {  # BR55: slim rifle, long barrel, ships with optics
		"receiver": Vector3(0.05, 0.075, 0.28), "barrel": Vector3(0.024, 0.024, 0.36),
		"stock": true, "grip": true, "mag": Vector3(0.03, 0.10, 0.05), "muzzle": 0.04,
	},
	Weapon.Class.M7_SMG: {  # M7: stockless, tall magazine, stubby bore
		"receiver": Vector3(0.048, 0.072, 0.17), "barrel": Vector3(0.022, 0.022, 0.14),
		"stock": false, "grip": true, "mag": Vector3(0.032, 0.15, 0.042), "muzzle": 0.032,
	},
	Weapon.Class.M90_SHOTGUN: {  # M90: fat tube under a fat barrel
		"receiver": Vector3(0.072, 0.09, 0.30), "barrel": Vector3(0.05, 0.05, 0.30),
		"stock": true, "grip": true, "muzzle": 0.08, "tube": true,
	},
	Weapon.Class.SRS99: {  # SRS99: enormous barrel, bipod, heavy optics
		"receiver": Vector3(0.05, 0.07, 0.34), "barrel": Vector3(0.026, 0.026, 0.66),
		"stock": true, "grip": true, "mag": Vector3(0.028, 0.08, 0.05), "muzzle": 0.08,
		"bipod": true,
	},
	Weapon.Class.SPNKR: {  # SPNKr: twin tubes, no stock
		"receiver": Vector3(0.115, 0.115, 0.54), "barrel": Vector3(0.09, 0.09, 0.20),
		"stock": false, "grip": true, "muzzle": 0.14, "tube": true, "barrels": 2,
	},
	Weapon.Class.M6D: {  # M6D: heavy sidearm with a scope block
		"receiver": Vector3(0.042, 0.065, 0.16), "barrel": Vector3(0.026, 0.026, 0.14),
		"stock": false, "grip": false, "mag": Vector3(0.028, 0.09, 0.038), "muzzle": 0.035,
	},
	Weapon.Class.M247_HMG: {  # M247: belt-fed, drum, bipod
		"receiver": Vector3(0.075, 0.085, 0.34), "barrel": Vector3(0.048, 0.048, 0.46),
		"stock": true, "grip": true, "drum": 0.05, "muzzle": 0.08, "bipod": true,
	},
	Weapon.Class.M392_DMR: {  # M392: long, thin, scoped
		"receiver": Vector3(0.046, 0.07, 0.30), "barrel": Vector3(0.023, 0.023, 0.50),
		"stock": true, "grip": true, "mag": Vector3(0.028, 0.10, 0.045), "muzzle": 0.05,
	},
	Weapon.Class.SPARTAN_LASER: {  # laser: a squared-off block with a lens
		"receiver": Vector3(0.10, 0.12, 0.42), "barrel": Vector3(0.055, 0.055, 0.12),
		"stock": false, "grip": true, "drum": 0.055, "muzzle": 0.11,
	},

	# --- HALO: Covenant -------------------------------------------------------
	# Rounded, vented, no magazines anywhere — plasma weapons carry a drum where
	# a UNSC gun carries a mag, and the needler wears its crystals as limbs.
	Weapon.Class.PLASMA_RIFLE: {
		"receiver": Vector3(0.075, 0.095, 0.26), "barrel": Vector3(0.034, 0.034, 0.14),
		"stock": false, "grip": true, "drum": 0.05, "muzzle": 0.055,
	},
	Weapon.Class.PLASMA_PISTOL: {
		"receiver": Vector3(0.05, 0.075, 0.15), "barrel": Vector3(0.026, 0.026, 0.09),
		"stock": false, "grip": false, "cylinder": 0.042, "muzzle": 0.045,
	},
	Weapon.Class.NEEDLER: {  # the crystals: the bowcaster's limbs, stood on end
		"receiver": Vector3(0.062, 0.085, 0.22), "barrel": Vector3(0.028, 0.028, 0.13),
		"stock": false, "grip": true, "muzzle": 0.04, "limbs": 0.11,
	},
	Weapon.Class.COV_CARBINE: {
		"receiver": Vector3(0.052, 0.08, 0.28), "barrel": Vector3(0.026, 0.026, 0.34),
		"stock": false, "grip": true, "drum": 0.038, "muzzle": 0.042,
	},
	Weapon.Class.BEAM_RIFLE: {  # long, forked, and mostly emitter
		"receiver": Vector3(0.05, 0.075, 0.34), "barrel": Vector3(0.024, 0.024, 0.60),
		"stock": false, "grip": true, "drum": 0.04, "muzzle": 0.07, "limbs": 0.09,
	},
	Weapon.Class.FUEL_ROD: {  # a fat green tube with a drum feed
		"receiver": Vector3(0.10, 0.105, 0.44), "barrel": Vector3(0.07, 0.07, 0.20),
		"stock": false, "grip": true, "drum": 0.07, "muzzle": 0.12, "tube": true,
	},
	Weapon.Class.BRUTE_SHOT: {  # drum-fed grenade thrower with a blade under it
		"receiver": Vector3(0.085, 0.10, 0.30), "barrel": Vector3(0.05, 0.05, 0.22),
		"stock": true, "grip": true, "drum": 0.075, "muzzle": 0.09,
	},
	Weapon.Class.MAULER: {  # a shotgun the size of a pistol
		"receiver": Vector3(0.058, 0.08, 0.16), "barrel": Vector3(0.045, 0.045, 0.12),
		"stock": false, "grip": false, "muzzle": 0.07,
	},
	# The two Covenant melee weapons build from the blade path, not these fields.
	Weapon.Class.ENERGY_SWORD: {
		"receiver": Vector3(0.05, 0.05, 0.22), "barrel": Vector3(0.03, 0.03, 0.0),
		"stock": false, "grip": false, "saber": true,
	},
	Weapon.Class.GRAV_HAMMER: {
		"receiver": Vector3(0.06, 0.06, 0.5), "barrel": Vector3(0.03, 0.03, 0.0),
		"stock": false, "grip": false, "saber": true,
	},

	# --- WARHAMMER: Adeptus Astartes -----------------------------------------
	# Everything is oversized, boxed and ribbed: a bolter is a hand-held cannon,
	# so the receiver is deeper than any blaster's and the magazine is huge.
	Weapon.Class.BOLTER: {
		"receiver": Vector3(0.085, 0.105, 0.28), "barrel": Vector3(0.042, 0.042, 0.20),
		"stock": true, "grip": true, "mag": Vector3(0.05, 0.14, 0.07), "muzzle": 0.065,
	},
	Weapon.Class.HEAVY_BOLTER: {
		"receiver": Vector3(0.10, 0.115, 0.36), "barrel": Vector3(0.06, 0.06, 0.40),
		"stock": true, "grip": true, "drum": 0.075, "muzzle": 0.10, "bipod": true,
	},
	Weapon.Class.STALKER_BOLT: {
		"receiver": Vector3(0.062, 0.085, 0.32), "barrel": Vector3(0.03, 0.03, 0.56),
		"stock": true, "grip": true, "mag": Vector3(0.034, 0.11, 0.06), "muzzle": 0.055,
	},
	Weapon.Class.PLASMA_GUN: {  # coil flask over the receiver, wide emitter
		"receiver": Vector3(0.08, 0.10, 0.30), "barrel": Vector3(0.05, 0.05, 0.18),
		"stock": true, "grip": true, "drum": 0.062, "muzzle": 0.10,
	},
	Weapon.Class.MELTAGUN: {  # a bell, a flask, and nothing else
		"receiver": Vector3(0.09, 0.10, 0.24), "barrel": Vector3(0.075, 0.075, 0.16),
		"stock": false, "grip": true, "drum": 0.07, "muzzle": 0.15, "tube": true,
	},
	Weapon.Class.FLAMER: {  # a nozzle on a promethium canister
		"receiver": Vector3(0.075, 0.09, 0.26), "barrel": Vector3(0.038, 0.038, 0.24),
		"stock": false, "grip": true, "drum": 0.08, "muzzle": 0.09,
	},
	Weapon.Class.BOLT_PISTOL: {
		"receiver": Vector3(0.052, 0.075, 0.17), "barrel": Vector3(0.034, 0.034, 0.11),
		"stock": false, "grip": false, "mag": Vector3(0.038, 0.10, 0.05), "muzzle": 0.05,
	},
	Weapon.Class.PLASMA_PISTOL_40K: {
		"receiver": Vector3(0.052, 0.08, 0.16), "barrel": Vector3(0.034, 0.034, 0.10),
		"stock": false, "grip": false, "cylinder": 0.05, "muzzle": 0.075,
	},
	Weapon.Class.GRENADE_LAUNCHER: {
		"receiver": Vector3(0.09, 0.10, 0.28), "barrel": Vector3(0.062, 0.062, 0.22),
		"stock": true, "grip": true, "muzzle": 0.11, "tube": true,
	},
	Weapon.Class.CHAINSWORD: {
		"receiver": Vector3(0.06, 0.06, 0.24), "barrel": Vector3(0.03, 0.03, 0.0),
		"stock": false, "grip": false, "saber": true,
	},
	Weapon.Class.POWER_SWORD: {
		"receiver": Vector3(0.05, 0.05, 0.24), "barrel": Vector3(0.03, 0.03, 0.0),
		"stock": false, "grip": false, "saber": true,
	},
	Weapon.Class.THUNDER_HAMMER: {
		"receiver": Vector3(0.07, 0.07, 0.55), "barrel": Vector3(0.03, 0.03, 0.0),
		"stock": false, "grip": false, "saber": true,
	},

	# --- WARHAMMER: Necrons ---------------------------------------------------
	# Gauss weapons are skeletal: a thin spine, ribbed housings, and a tubular
	# emitter cage rather than a bore. The limbs field does the cage.
	Weapon.Class.GAUSS_FLAYER: {
		"receiver": Vector3(0.05, 0.075, 0.30), "barrel": Vector3(0.024, 0.024, 0.30),
		"stock": true, "grip": false, "muzzle": 0.05, "limbs": 0.08,
	},
	Weapon.Class.GAUSS_BLASTER: {
		"receiver": Vector3(0.058, 0.085, 0.32), "barrel": Vector3(0.028, 0.028, 0.36),
		"stock": true, "grip": true, "muzzle": 0.06, "limbs": 0.10,
	},
	Weapon.Class.TESLA_CARBINE: {
		"receiver": Vector3(0.055, 0.08, 0.26), "barrel": Vector3(0.026, 0.026, 0.26),
		"stock": false, "grip": true, "drum": 0.045, "muzzle": 0.055, "limbs": 0.09,
	},
	Weapon.Class.SYNAPTIC_DISINTEGRATOR: {
		"receiver": Vector3(0.045, 0.065, 0.34), "barrel": Vector3(0.02, 0.02, 0.64),
		"stock": true, "grip": false, "muzzle": 0.05, "limbs": 0.07,
	},
	Weapon.Class.HEAT_RAY: {
		"receiver": Vector3(0.078, 0.09, 0.26), "barrel": Vector3(0.05, 0.05, 0.18),
		"stock": false, "grip": true, "drum": 0.06, "muzzle": 0.11,
	},
	Weapon.Class.TRANSDIMENSIONAL_BEAMER: {
		"receiver": Vector3(0.085, 0.095, 0.42), "barrel": Vector3(0.045, 0.045, 0.22),
		"stock": false, "grip": true, "muzzle": 0.10, "tube": true, "limbs": 0.10,
	},
	Weapon.Class.GAUSS_PISTOL: {
		"receiver": Vector3(0.042, 0.065, 0.16), "barrel": Vector3(0.022, 0.022, 0.16),
		"stock": false, "grip": false, "muzzle": 0.04, "limbs": 0.06,
	},
	Weapon.Class.WARSCYTHE: {
		"receiver": Vector3(0.03, 0.03, 0.4), "barrel": Vector3(0.02, 0.02, 0.0),
		"stock": false, "grip": false, "staff": true,
	},
	Weapon.Class.STAFF_OF_LIGHT: {
		"receiver": Vector3(0.03, 0.03, 0.4), "barrel": Vector3(0.02, 0.02, 0.0),
		"stock": false, "grip": false, "staff": true,
	},

	# --- WARHAMMER: Orks ------------------------------------------------------
	# Welded, over-magazined and bolted together: every ork gun is a bigger drum
	# than it needs on a barrel that is too short for it.
	Weapon.Class.SHOOTA: {
		"receiver": Vector3(0.085, 0.10, 0.26), "barrel": Vector3(0.04, 0.04, 0.18),
		"stock": true, "grip": true, "mag": Vector3(0.048, 0.16, 0.06), "muzzle": 0.07,
	},
	Weapon.Class.BIG_SHOOTA: {
		"receiver": Vector3(0.105, 0.115, 0.30), "barrel": Vector3(0.055, 0.055, 0.34),
		"stock": false, "grip": true, "drum": 0.085, "muzzle": 0.09, "barrels": 2,
	},
	Weapon.Class.SLUGGA: {
		"receiver": Vector3(0.058, 0.08, 0.16), "barrel": Vector3(0.036, 0.036, 0.10),
		"stock": false, "grip": false, "drum": 0.05, "muzzle": 0.06,
	},
	Weapon.Class.ROKKIT_LAUNCHA: {
		"receiver": Vector3(0.12, 0.12, 0.50), "barrel": Vector3(0.10, 0.10, 0.18),
		"stock": false, "grip": true, "muzzle": 0.16, "tube": true,
	},
	Weapon.Class.MEGA_BLASTA: {
		"receiver": Vector3(0.095, 0.105, 0.30), "barrel": Vector3(0.058, 0.058, 0.22),
		"stock": true, "grip": true, "drum": 0.08, "muzzle": 0.12, "limbs": 0.10,
	},
	Weapon.Class.BURNA: {
		"receiver": Vector3(0.08, 0.095, 0.24), "barrel": Vector3(0.042, 0.042, 0.26),
		"stock": false, "grip": true, "drum": 0.085, "muzzle": 0.10,
	},
	Weapon.Class.CHOPPA: {
		"receiver": Vector3(0.06, 0.06, 0.22), "barrel": Vector3(0.03, 0.03, 0.0),
		"stock": false, "grip": false, "saber": true,
	},
	Weapon.Class.POWER_KLAW: {
		"receiver": Vector3(0.07, 0.07, 0.26), "barrel": Vector3(0.03, 0.03, 0.0),
		"stock": false, "grip": false, "saber": true,
	},
	# --- THE FACTION GUNS -----------------------------------------------------
	# A class is recognised by what it is HOLDING before anything else, so each of
	# these is proportioned to its owner: the B1's rifle is thin and cheap, the
	# Droideka's is a paired pod, the incinerator is a tank with a nozzle.
	Weapon.Class.DC15S: {  # clone carbine: the DC-15A cut down
		"receiver": Vector3(0.05, 0.07, 0.20), "barrel": Vector3(0.026, 0.026, 0.22),
		"stock": true, "grip": true, "mag": Vector3(0.03, 0.10, 0.05), "muzzle": 0.045,
	},
	Weapon.Class.DC17: {  # ARC pistol, carried in pairs
		"receiver": Vector3(0.036, 0.058, 0.13), "barrel": Vector3(0.022, 0.022, 0.13),
		"stock": false, "grip": false, "mag": Vector3(0.026, 0.08, 0.034), "muzzle": 0.032,
	},
	Weapon.Class.DC17M: {  # commando rifle: boxy, optics, underslung block
		"receiver": Vector3(0.058, 0.085, 0.28), "barrel": Vector3(0.026, 0.026, 0.26),
		"stock": true, "grip": true, "mag": Vector3(0.034, 0.12, 0.05), "muzzle": 0.04,
	},
	Weapon.Class.DC15X: {  # sharpshooter: all barrel, bipod
		"receiver": Vector3(0.045, 0.062, 0.30), "barrel": Vector3(0.022, 0.022, 0.66),
		"stock": true, "grip": false, "mag": Vector3(0.026, 0.07, 0.04), "muzzle": 0.07,
		"bipod": true,
	},
	Weapon.Class.E5: {  # B1: thin, cheap, unloved
		"receiver": Vector3(0.042, 0.06, 0.24), "barrel": Vector3(0.022, 0.022, 0.30),
		"stock": false, "grip": true, "mag": Vector3(0.026, 0.09, 0.04), "muzzle": 0.035,
	},
	Weapon.Class.E5S: {
		"receiver": Vector3(0.042, 0.06, 0.30), "barrel": Vector3(0.02, 0.02, 0.60),
		"stock": true, "grip": false, "mag": Vector3(0.024, 0.07, 0.038), "muzzle": 0.06,
		"bipod": true,
	},
	Weapon.Class.DROIDEKA_TWIN: {  # a paired pod, not a rifle
		"receiver": Vector3(0.10, 0.075, 0.22), "barrel": Vector3(0.026, 0.026, 0.30),
		"barrels": 2, "stock": false, "grip": false, "muzzle": 0.04,
	},
	Weapon.Class.SONIC_BLASTER: {  # Geonosian: a drum on a short tube
		"receiver": Vector3(0.075, 0.085, 0.20), "barrel": Vector3(0.05, 0.05, 0.18),
		"stock": false, "grip": true, "drum": 0.06, "muzzle": 0.09,
	},
	Weapon.Class.VIBROSWORD: {"saber": true},
	Weapon.Class.E11: {  # stormtrooper: the shape everybody knows
		"receiver": Vector3(0.05, 0.075, 0.22), "barrel": Vector3(0.026, 0.026, 0.24),
		"stock": true, "grip": true, "mag": Vector3(0.03, 0.10, 0.048), "muzzle": 0.042,
	},
	Weapon.Class.DLT19: {  # heavy: long, fat, drum-fed
		"receiver": Vector3(0.07, 0.08, 0.30), "barrel": Vector3(0.042, 0.042, 0.42),
		"stock": true, "grip": true, "drum": 0.05, "muzzle": 0.07, "bipod": true,
	},
	Weapon.Class.DLT20A: {  # scout: long barrel, scope, no bulk
		"receiver": Vector3(0.046, 0.066, 0.28), "barrel": Vector3(0.022, 0.022, 0.52),
		"stock": true, "grip": false, "mag": Vector3(0.026, 0.08, 0.04), "muzzle": 0.05,
	},
	Weapon.Class.SE14R: {  # death trooper machine pistol
		"receiver": Vector3(0.04, 0.062, 0.15), "barrel": Vector3(0.022, 0.022, 0.14),
		"stock": false, "grip": false, "mag": Vector3(0.028, 0.10, 0.036), "muzzle": 0.03,
	},
	Weapon.Class.E11D: {  # death trooper rifle: an E-11 under a fat suppressor
		"receiver": Vector3(0.05, 0.075, 0.24), "barrel": Vector3(0.038, 0.038, 0.30),
		"stock": true, "grip": true, "mag": Vector3(0.03, 0.11, 0.048), "muzzle": 0.05,
	},
	Weapon.Class.FLAMETHROWER: {  # a tank with a nozzle: no barrel to speak of
		"receiver": Vector3(0.085, 0.10, 0.26), "barrel": Vector3(0.034, 0.034, 0.16),
		"stock": false, "grip": true, "drum": 0.065, "muzzle": 0.10, "tube": true,
	},
	Weapon.Class.A280C: {
		"receiver": Vector3(0.05, 0.072, 0.26), "barrel": Vector3(0.024, 0.024, 0.34),
		"stock": true, "grip": true, "mag": Vector3(0.03, 0.11, 0.048), "muzzle": 0.045,
	},
	Weapon.Class.CR2: {  # SMG: stubby, high mag, no stock
		"receiver": Vector3(0.048, 0.07, 0.17), "barrel": Vector3(0.022, 0.022, 0.12),
		"stock": false, "grip": true, "mag": Vector3(0.032, 0.13, 0.042), "muzzle": 0.034,
	},
	Weapon.Class.DH447: {
		"receiver": Vector3(0.044, 0.062, 0.30), "barrel": Vector3(0.02, 0.02, 0.62),
		"stock": true, "grip": false, "mag": Vector3(0.026, 0.075, 0.04), "muzzle": 0.055,
		"bipod": true,
	},
	Weapon.Class.EWOK_SPEAR: {"staff": true},
	Weapon.Class.M319: {  # grenadier: a fat tube on a frame
		"receiver": Vector3(0.075, 0.09, 0.28), "barrel": Vector3(0.062, 0.062, 0.24),
		"stock": true, "grip": true, "muzzle": 0.085, "tube": true,
	},
	Weapon.Class.SPIKER: {  # Brute: spikes standing off the barrel
		"receiver": Vector3(0.06, 0.08, 0.20), "barrel": Vector3(0.03, 0.03, 0.22),
		"stock": false, "grip": true, "mag": Vector3(0.032, 0.11, 0.045), "muzzle": 0.05,
	},
}
## Blade dimensions and colour. The blade is drawn a good deal SHORTER than the
## weapon's 3.4 m reach on purpose: a true-length blade fills the whole screen
## from a first-person camera and you cannot see what you are swinging at.
const BLADE_LENGTH := 0.78
const BLADE_RADIUS := 0.019
## The ready stance: hilt held low and to the right, blade standing UP and
## tilted slightly across the body. A blade pointing down the barrel line is
## what every other weapon here does and it reads as a glowing rifle — worse,
## from a first-person camera it lies along the view axis and you cannot see
## past it. Upright puts the blade beside the crosshair instead of over it.
## Pitch, yaw, roll in radians. The blade is modelled along -Z like every barrel
## here, so a POSITIVE pitch is what stands it up: rotating -Z about +X by t
## sends it to (0, sin t, -cos t), and it was pointing at the floor until that
## sign was fixed.
const SABER_REST := Vector3(1.28, 0.18, -0.28)
const SABER_AT := Vector3(0.17, -0.26, -0.30)     # hilt low and to the right
## One swing, in seconds, and how far it travels. The arc is deliberately big:
## a sword that twitches like recoil does not read as a swing at all.
const SWING_TIME := 0.32
# NEGATIVE pitch, because rest already has the blade up: the swing brings it
# DOWN through horizontal, which is the chop. Positive would throw it backwards
# over the shoulder.
const SWING_PITCH := -1.55
const SWING_YAW := 1.05     # ...carried across the body
const SWING_ROLL := 0.55
const BLADE_CORE := Color(0.75, 0.92, 1.0)
const BLADE_GLOW := Color(0.25, 0.65, 1.0)
const BLADE_ENERGY := 5.0   # core emission at rest; a parry flares off this

## THE GUARD. It has to be unmistakable, because everything else about blocking
## is invisible: the arc it covers, the pool it spends and the break are all
## numbers. If the pose is a small tilt, a player holding the button has no idea
## whether anything is happening — so the blade comes right up across the view,
## the hilt is drawn in to the centre of the chest, and the whole weapon rides a
## slow brace instead of sitting frozen.
## ...while still leaving the player able to SEE. The blade is a metre of solid
## white: brought fully across the centre it blinds you exactly when you are
## being shot at, so it rises through the right of the frame with the hilt held
## out at chest height, and the crosshair stays clear.
const GUARD_ROT := Vector3(1.16, -0.34, 0.62)
const GUARD_AT := Vector3(0.13, -0.20, -0.40)      # out, up, and further away
const GUARD_DRAW_IN := Vector3(-0.05, 0.03, 0.0)   # ...the whole model leans in
const GUARD_BRACE := 0.035   # radians of sway, so a held guard is visibly HELD
const GUARD_BRACE_RATE := 3.4

## The parry: what a stopped hit looks like. The blade is knocked back and flares
## for a moment, which is the only confirmation that the guard just paid for
## something — the pool draining is a number on the HUD and nobody reading it is
## looking at the fight.
const PARRY_TIME := 0.26
const PARRY_ROT := Vector3(-0.30, 0.30, -0.34)
const PARRY_PUSH := Vector3(0.05, -0.03, 0.07)  # driven back toward the camera
const PARRY_FLARE := 9.0     # added to BLADE_ENERGY at the moment of the block


## WHO MADE THIS GUN. Six manufacturers, and every one of them builds out of the
## same boxes — what separates them is COLOUR, PROPORTION and one or two parts
## nobody else has. That is the same argument the character styles make: a
## faction reads by silhouette and palette, not by polygon count.
##
## Listed for the exceptions only; anything unlisted is Star Wars, which is what
## the catalogue was before the other universes existed.
enum Make { STARWARS, UNSC, COVENANT, ASTARTES, NECRON, ORK }
const FAMILY := {
	Weapon.Class.MA5B: Make.UNSC, Weapon.Class.BR55: Make.UNSC,
	Weapon.Class.M7_SMG: Make.UNSC, Weapon.Class.M90_SHOTGUN: Make.UNSC,
	Weapon.Class.SRS99: Make.UNSC, Weapon.Class.SPNKR: Make.UNSC,
	Weapon.Class.M6D: Make.UNSC, Weapon.Class.M247_HMG: Make.UNSC,
	Weapon.Class.M392_DMR: Make.UNSC, Weapon.Class.SPARTAN_LASER: Make.UNSC,
	Weapon.Class.PLASMA_RIFLE: Make.COVENANT, Weapon.Class.PLASMA_PISTOL: Make.COVENANT,
	Weapon.Class.NEEDLER: Make.COVENANT, Weapon.Class.COV_CARBINE: Make.COVENANT,
	Weapon.Class.BEAM_RIFLE: Make.COVENANT, Weapon.Class.FUEL_ROD: Make.COVENANT,
	Weapon.Class.BRUTE_SHOT: Make.COVENANT, Weapon.Class.MAULER: Make.COVENANT,
	Weapon.Class.SPIKER: Make.COVENANT, Weapon.Class.M319: Make.UNSC,
	Weapon.Class.BOLTER: Make.ASTARTES, Weapon.Class.HEAVY_BOLTER: Make.ASTARTES,
	Weapon.Class.STALKER_BOLT: Make.ASTARTES, Weapon.Class.PLASMA_GUN: Make.ASTARTES,
	Weapon.Class.MELTAGUN: Make.ASTARTES, Weapon.Class.FLAMER: Make.ASTARTES,
	Weapon.Class.BOLT_PISTOL: Make.ASTARTES,
	Weapon.Class.PLASMA_PISTOL_40K: Make.ASTARTES,
	Weapon.Class.GRENADE_LAUNCHER: Make.ASTARTES,
	Weapon.Class.GAUSS_FLAYER: Make.NECRON, Weapon.Class.GAUSS_BLASTER: Make.NECRON,
	Weapon.Class.TESLA_CARBINE: Make.NECRON,
	Weapon.Class.SYNAPTIC_DISINTEGRATOR: Make.NECRON,
	Weapon.Class.HEAT_RAY: Make.NECRON,
	Weapon.Class.TRANSDIMENSIONAL_BEAMER: Make.NECRON,
	Weapon.Class.GAUSS_PISTOL: Make.NECRON,
	Weapon.Class.SHOOTA: Make.ORK, Weapon.Class.BIG_SHOOTA: Make.ORK,
	Weapon.Class.SLUGGA: Make.ORK, Weapon.Class.ROKKIT_LAUNCHA: Make.ORK,
	Weapon.Class.MEGA_BLASTA: Make.ORK, Weapon.Class.BURNA: Make.ORK,
}


func _family(class_id: int) -> int:
	return FAMILY.get(class_id, Make.STARWARS)


## FOUR MATERIALS PER MAKE, and `metallic` is 0.0 in every one of them — see the
## note in `_build`. What tells a steel receiver from a polymer grip here is
## ALBEDO and ROUGHNESS: the frame is lighter and smooth so it catches a hard
## specular off the direct lights, the furniture is dark and rough so it does
## not, and the small parts are brighter and smoother still so detail reads at
## arm's length. The accent is the only emissive one — a power cell, which is
## light rather than metal and so is allowed to glow.
##
## Rebuilt per gun rather than shared, because a weapon swap rebuilds the whole
## viewmodel anyway and four materials is nothing next to the thirty meshes it
## is about to make.
const PALETTES := {
	# Imperial/Republic: gunmetal and black polymer, a red heat cell.
	Make.STARWARS: {"gun": Color(0.28, 0.285, 0.31), "dark": Color(0.075, 0.075, 0.085),
		"bright": Color(0.46, 0.465, 0.49), "cell": Color(1.0, 0.25, 0.15)},
	# UNSC: olive drab over black, with a white-blue readout. Utility kit.
	Make.UNSC: {"gun": Color(0.20, 0.22, 0.17), "dark": Color(0.06, 0.065, 0.06),
		"bright": Color(0.42, 0.44, 0.40), "cell": Color(0.45, 0.85, 1.0)},
	# Covenant: violet shell, darker violet grip, hot cyan plasma.
	Make.COVENANT: {"gun": Color(0.36, 0.28, 0.50), "dark": Color(0.16, 0.12, 0.24),
		"bright": Color(0.62, 0.54, 0.78), "cell": Color(0.25, 0.85, 1.0)},
	# Astartes: bone and dark red over black, brass-toned furniture.
	Make.ASTARTES: {"gun": Color(0.34, 0.10, 0.09), "dark": Color(0.07, 0.06, 0.06),
		"bright": Color(0.62, 0.55, 0.32), "cell": Color(1.0, 0.55, 0.15)},
	# Necron: near-black with a green core. The only palette with no warm tone.
	Make.NECRON: {"gun": Color(0.13, 0.14, 0.15), "dark": Color(0.05, 0.06, 0.06),
		"bright": Color(0.38, 0.42, 0.40), "cell": Color(0.35, 1.0, 0.45)},
	# Ork: scrap. Rust-brown frame, black rubber, and a red bit because red ones
	# go faster.
	Make.ORK: {"gun": Color(0.30, 0.20, 0.13), "dark": Color(0.09, 0.08, 0.07),
		"bright": Color(0.44, 0.34, 0.22), "cell": Color(1.0, 0.30, 0.10)},
}


func _palette(make: int) -> Dictionary:
	var c: Dictionary = PALETTES.get(make, PALETTES[Make.STARWARS])
	var gun := StandardMaterial3D.new()
	gun.albedo_color = c["gun"]
	gun.metallic = 0.0
	gun.roughness = 0.46
	gun.metallic_specular = 0.42
	var dark := StandardMaterial3D.new()
	dark.albedo_color = c["dark"]
	dark.metallic = 0.0
	dark.roughness = 0.80
	dark.metallic_specular = 0.22
	var bright := StandardMaterial3D.new()
	bright.albedo_color = c["bright"]
	bright.metallic = 0.0
	bright.roughness = 0.34
	bright.metallic_specular = 0.50
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(c["cell"], 1.0).darkened(0.85)
	accent.emission_enabled = true
	accent.emission = c["cell"]
	accent.emission_energy_multiplier = 2.0
	return {"gun": gun, "dark": dark, "bright": bright, "accent": accent}


func _build(class_id: int, scoped: bool, holo: bool) -> void:
	# remove_child before queue_free: freeing is deferred to the end of the
	# frame, so a rebuild in the same frame (deploy then weapon swap) would
	# stack the new gun on top of the old one's parts.
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_scope = null
	_holo = null
	_flash = null
	_flash_mat = null   # freed with the mesh above; _flash_col survives the rebuild
	_saber = null
	_shield = null
	_shield_mats.clear()
	_shield_alpha.clear()
	_staff_cores.clear()
	_staff_glows.clear()
	_staff_bolts.clear()
	_staff_arc_mat = null
	_arc_box = null
	_blade_core = null
	_blade_glow = null

	var shape: Dictionary = SHAPES.get(class_id, SHAPES[Weapon.Class.SOLDIER])
	if shape.get("saber", false) or shape.get("staff", false):
		_read_blade_look(class_id, shape.get("staff", false))
	if shape.get("staff", false):
		_build_staff()
		return
	if shape.get("saber", false):
		_build_saber()
		return
	# THE PALETTE. A real weapon reads as two materials that respond to light in
	# completely different ways — MACHINED METAL and MOULDED POLYMER — and the
	# old set had everything at metallic 0.1 / roughness ~0.6 in three shades of
	# near-black, so a steel barrel and a plastic grip shaded identically and the
	# whole gun collapsed into one dark slab (which is exactly what the render
	# showed). Splitting them is the single biggest realism win available here,
	# and it costs nothing: same part count, different material.
	#
	# HOW the split is made matters, and the first attempt got it wrong: pushing
	# the steel to metallic 0.8 made the gun DARKER, not richer. The GL
	# Compatibility gotcha still holds — metal is lit almost entirely by what it
	# REFLECTS, and against this project's near-black skies that is nothing.
	# `Grade`'s sky-sourced ambient softens it but does not repeal it, and the
	# renderer is currently Compatibility (see project.godot).
	#
	# So the separation is carried by ALBEDO and ROUGHNESS, and by NOTHING ELSE.
	# `metallic` is 0 on every part of every gun, deliberately.
	#
	# The reason is what metallic actually does: it takes the albedo out of the
	# diffuse and puts that energy into the reflection. Under GL Compatibility the
	# only thing there is to reflect is the sky — no SSR, no probes — so a
	# metallic receiver stops being its own colour and becomes a picture of the
	# sky gradient hanging in front of the camera, which reads as smoked glass.
	# Even at 0.30 the gun was see-through-looking rather than solid, and that is
	# not a value that wants tuning down: any amount of it trades the gun's own
	# colour for the sky's.
	#
	# A dielectric still SHINES — `metallic_specular` and a low roughness give a
	# hot highlight off the DIRECT lights every map has, which is the shine you
	# actually want on a receiver — and it stays opaque while doing it.
	var pal := _palette(_family(class_id))
	var gun: StandardMaterial3D = pal["gun"]        # receiver, barrel: the frame
	var dark: StandardMaterial3D = pal["dark"]      # furniture: grip, stock, mag
	var bright: StandardMaterial3D = pal["bright"]  # the small hard parts
	var accent: StandardMaterial3D = pal["accent"]  # the power cell

	var receiver: Vector3 = shape["receiver"]
	var barrel: Vector3 = shape["barrel"]
	var barrel_z := -receiver.z * 0.5 - barrel.z * 0.5
	_box(receiver, Vector3(0, 0, -0.03), gun)

	# Barrels: one, or a cluster for the rotary cannon.
	var barrel_count: int = shape.get("barrels", 1)
	for i in barrel_count:
		var offset := Vector3.ZERO
		if barrel_count > 1:
			var angle := TAU * i / float(barrel_count)
			offset = Vector3(cos(angle), sin(angle), 0.0) * 0.032
		_box(barrel, Vector3(offset.x, 0.012 + offset.y, barrel_z - 0.03), gun)

	var muzzle_size: float = shape.get("muzzle", 0.0)
	if muzzle_size > 0.0:
		# Muzzle device in STEEL, not polymer — it is the hottest part of the gun
		# and reading as plastic was wrong. Given a pair of ports as well.
		_box(Vector3(muzzle_size, muzzle_size, 0.06),
			Vector3(0, 0.012, barrel_z - barrel.z * 0.5 - 0.06), bright)
		for side: float in [-1.0, 1.0]:
			_box(Vector3(muzzle_size * 0.35, muzzle_size * 1.15, 0.012),
				Vector3(muzzle_size * 0.32 * side, 0.012,
					barrel_z - barrel.z * 0.5 - 0.052), dark)

	# Heat shroud along the barrel of anything with a long one. A bare extruded
	# box IS the "slab" look; a run of cooling slots breaks the length up and
	# says the barrel gets hot, which is the whole conceit of a blaster.
	if barrel_count == 1 and barrel.z > 0.14:
		var vents := clampi(int(barrel.z / 0.045), 2, 6)
		for i in vents:
			var vz := barrel_z + barrel.z * 0.5 - 0.03 - i * (barrel.z - 0.06) \
				/ maxf(vents - 1, 1)
			for side: float in [-1.0, 1.0]:
				_box(Vector3(0.006, barrel.y * 0.85, 0.016),
					Vector3(barrel.x * 0.5 * side, 0.012, vz), dark)
		# Front sight ears, with the middle left open. A single centred block was
		# exactly on the ADS line and covered the notch it was meant to frame.
		for side: float in [-1.0, 1.0]:
			_box(Vector3(0.007, 0.024, 0.016),
				Vector3(side * SIGHT_CHANNEL_X, barrel.y * 0.5 + 0.014,
					barrel_z - barrel.z * 0.34), bright)

	# Pistol grip, always: it's what you're holding. Polymer, not steel — it is
	# the part closest to the camera and the one that most needs to not be metal.
	var hand := _box(Vector3(0.035, 0.11, 0.05), Vector3(0, -0.07, 0.03), dark)
	hand.rotation.x = -0.25

	# --- Universal furniture -------------------------------------------------
	# Every gun gets these, because every gun has them and their absence is what
	# made the receivers read as extruded blocks. They are small and cheap, and
	# at viewmodel range (the weapon fills a quarter of the frame) they are the
	# difference between a prop and a machine. Sized off the receiver so they
	# land correctly on all twelve silhouettes rather than being tuned to one.
	var rz: float = receiver.z
	var ry: float = receiver.y
	# Trigger guard: a loop under the receiver, made of three thin bars.
	_box(Vector3(0.014, 0.008, 0.052), Vector3(0, -ry * 0.5 - 0.034, 0.006), bright)
	_box(Vector3(0.014, 0.030, 0.008), Vector3(0, -ry * 0.5 - 0.019, 0.030), bright)
	# Trigger itself, inside the guard.
	_box(Vector3(0.009, 0.024, 0.008), Vector3(0, -ry * 0.5 - 0.014, 0.012), bright)
	# Ejection port: a recessed panel on the right of the receiver with a lip.
	_box(Vector3(0.006, 0.030, 0.062), Vector3(receiver.x * 0.5, 0.004, -0.03), dark)
	_box(Vector3(0.008, 0.008, 0.070), Vector3(receiver.x * 0.5, 0.021, -0.03), bright)
	# Charging handle, standing proud on the left where the eye catches it.
	_box(Vector3(0.028, 0.012, 0.014), Vector3(-receiver.x * 0.5 - 0.010, 0.016, 0.01), bright)
	# Top rail: a run of side slots along the receiver. A repeated small feature is
	# what gives a surface SCALE — the same trick as the tower mullions on
	# Coruscant, and the reason a plain box could be any size. Keep the centre
	# empty, because that is the sight channel.
	var slots := clampi(int(rz / 0.028), 3, 9)
	for i in slots:
		var t := -rz * 0.5 + 0.02 + i * (rz - 0.04) / maxf(slots - 1, 1)
		for side: float in [-1.0, 1.0]:
			_box(Vector3(0.010, 0.006, 0.008),
				Vector3(side * SIGHT_CHANNEL_X, ry * 0.5 + 0.003, t), dark)
	# Sling loop at the rear.
	_box(Vector3(0.008, 0.018, 0.008), Vector3(-receiver.x * 0.4, -ry * 0.5 - 0.006,
		rz * 0.42), bright)

	if shape.get("stock", false):
		# Polymer, and given a cheek riser: a stock is the one part with a shape
		# that comes from a human face rather than from the mechanism.
		_box(Vector3(0.04, 0.055, 0.12), Vector3(0, -0.008, receiver.z * 0.5 + 0.05), dark)
		_box(Vector3(0.030, 0.018, 0.075), Vector3(0, 0.026, receiver.z * 0.5 + 0.04), dark)
		_box(Vector3(0.044, 0.050, 0.012), Vector3(0, -0.012, receiver.z * 0.5 + 0.108), bright)
	if shape.get("grip", false):
		_box(Vector3(0.02, 0.035, 0.05), Vector3(0, -0.055, -0.1), dark)
	if shape.has("mag"):
		var mag: Vector3 = shape["mag"]
		_box(mag, Vector3(0, -receiver.y * 0.5 - mag.y * 0.4, -0.02), dark)
	if shape.has("drum"):
		var drum: float = shape["drum"]
		var d := _cyl(drum, 0.05, Vector3(0, -0.07, -0.02), dark)
		d.rotation.z = PI / 2.0  # drum face sideways
	if shape.has("cylinder"):
		var cyl_r: float = shape["cylinder"]
		var c := _cyl(cyl_r, 0.055, Vector3(0, -0.004, -0.03), gun)
		c.rotation.z = PI / 2.0
	if shape.get("tube", false):
		# The RPG reads as a launcher: a fat ring near the muzzle.
		var ring := _cyl(0.075, 0.05, Vector3(0, 0.0, barrel_z), dark)
		ring.rotation.x = PI / 2.0
	if shape.get("bipod", false):
		for side in [-1.0, 1.0]:
			var leg := _box(Vector3(0.012, 0.09, 0.012),
				Vector3(0.03 * side, -0.06, barrel_z + 0.04), dark)
			leg.rotation.z = 0.35 * side
	if shape.get("limbs", false):
		# The bowcaster's crossbow limbs, out at the MUZZLE end and swept back,
		# with a string strung between the tips. It is the whole reason the
		# weapon is recognisable — built from the same boxes as everything else,
		# because a silhouette is what a viewmodel is for and this one is a
		# CROSSBOW. Sitting them mid-barrel and short read as a rifle with a bar
		# stuck through it.
		var span: float = shape["limbs"]
		var limb_z := -receiver.z * 0.5 - barrel.z * 0.9
		for side in [-1.0, 1.0]:
			var limb := _box(Vector3(span, 0.018, 0.038),
				Vector3(span * 0.5 * side, 0.0, limb_z), gun)
			# Only a slight sweep. At 0.5 rad the limbs lay along the view axis and
			# vanished into the receiver from the owner's own camera — which is the
			# only camera that ever sees a viewmodel.
			limb.rotation.y = -0.16 * side
		# The string runs BEHIND the tips, and in gunmetal: the accent material
		# is the emissive power cell, and a glowing orange bowstring reads as a
		# fault light rather than a weapon.
		_box(Vector3(span * 1.95, 0.008, 0.008),
			Vector3(0.0, 0.0, limb_z + span * 0.16), dark)
	_box(Vector3(0.02, 0.018, 0.04), Vector3(0, receiver.y * 0.5 - 0.005, -0.02), accent)
	_dress(_family(class_id), receiver, barrel, barrel_z, pal)

	# Sights. The scope is a tube on a mount; the holo is a hollow ring you can
	# see the world through, which is the point of buying it.
	_scope = _cyl(0.02, 0.15, Vector3(0, receiver.y * 0.5 + 0.03, -0.06), gun)
	_scope.name = "ScopeTube"
	_box(Vector3(0.012, 0.03, 0.02), Vector3(0, receiver.y * 0.5 + 0.01, -0.06), gun) \
		.reparent(_scope, false)
	_scope.visible = scoped

	_holo = Node3D.new()
	_holo.name = "HoloSight"
	add_child(_holo)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.1, 0.1, 0.11)
	ring_mat.metallic = 0.0   # solid: metallic here is a mirror of the sky
	ring_mat.roughness = 0.5
	var hoop := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.022
	torus.outer_radius = 0.03
	torus.rings = 10
	torus.ring_segments = 6
	hoop.mesh = torus
	hoop.material_override = ring_mat
	hoop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# TorusMesh's hole runs along +Y, i.e. it lies flat like a donut on a table.
	# Stand it up so the hole runs down the barrel and you sight THROUGH it —
	# the same -Z convention _cyl() uses.
	hoop.rotation.x = PI / 2.0
	hoop.position = Vector3(0, receiver.y * 0.5 + 0.028, -0.08)
	_holo.add_child(hoop)
	for side: float in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.006, 0.028, 0.014)
		post.mesh = pm
		post.material_override = ring_mat
		post.position = Vector3(side * 0.020, receiver.y * 0.5 + 0.003, HOLO_Z)
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_holo.add_child(post)
	_holo.visible = holo

	# Whichever sight is fitted has to sit on the camera axis when aimed. The
	# camera is at the Head origin and this gun hangs off the Weapon anchor, so
	# the slide is simply "cancel the anchor offset, then cancel the sight's own
	# offset". Iron sights line up on the receiver's top rib.
	var sight_at := Vector3(0.0, receiver.y * 0.5 + 0.012, IRON_REAR_Z)
	if holo:
		sight_at = Vector3(0.0, receiver.y * 0.5 + 0.028, HOLO_Z)
	elif scoped:
		sight_at = _scope.position
	var anchor: Vector3 = get_parent().position  # Weapon's offset under Head
	_ads_pos = Vector3(-(anchor.x + sight_at.x), -(anchor.y + sight_at.y), ADS_PULL_BACK)

	_build_flash(barrel_z - barrel.z * 0.5 - 0.06)


## WHAT MAKES A GUN LOOK LIKE ITS FACTION'S GUN. The frame, the barrel and the
## universal furniture above are the same machine for everybody; this is the
## handful of parts that are not, and it is deliberately a handful — at
## viewmodel range a weapon is read in about a second, and one or two shapes
## nobody else has do more than a dozen that everybody has.
##
## Every part here goes through the same `_box`/`_cyl` builders and the same
## four dielectric materials as the rest of the gun. No new mechanism, no new
## material model: a faction is a table row and a dozen lines, exactly like a
## character style.
func _dress(make: int, receiver: Vector3, barrel: Vector3, barrel_z: float,
		pal: Dictionary) -> void:
	var gun: StandardMaterial3D = pal["gun"]
	var dark: StandardMaterial3D = pal["dark"]
	var bright: StandardMaterial3D = pal["bright"]
	var accent: StandardMaterial3D = pal["accent"]
	var rx := receiver.x
	var ry := receiver.y
	var rz := receiver.z
	match make:
		Make.UNSC:
			# THE CARRY HANDLE. It is the one silhouette everybody recognises: a
			# raised bridge over the receiver with the sight tucked under it. Build
			# it as side rails so the sight picture has a clear centre channel.
			for xside: float in [-1.0, 1.0]:
				for zside: float in [-1.0, 1.0]:
					_box(Vector3(0.008, 0.030, 0.010),
						Vector3(xside * SIGHT_CHANNEL_X, ry * 0.5 + 0.016,
							zside * rz * 0.28), gun)
				_box(Vector3(0.008, 0.010, rz * 0.62),
					Vector3(xside * SIGHT_CHANNEL_X, ry * 0.5 + 0.031, 0), gun)
			# ...and the AMMO COUNTER, a lit panel on the left of the receiver.
			_box(Vector3(0.004, 0.020, 0.040),
				Vector3(-rx * 0.5 - 0.003, ry * 0.18, rz * 0.16), accent)
			# Ribbed polymer handguard over the chamber end of the barrel.
			for i in 4:
				_box(Vector3(barrel.x + 0.016, barrel.y + 0.014, 0.010),
					Vector3(0, 0.012, barrel_z + barrel.z * 0.34 - i * 0.020), dark)
		Make.COVENANT:
			# NO STRAIGHT LINES AND NO CORNERS: a Covenant weapon is a shell with
			# a glowing core down the middle. Two tapered halves clamped round a
			# plasma channel, which is a cylinder rather than a box — the only
			# family here built out of round parts, and that alone reads as alien
			# from the corner of the eye.
			for side: float in [-1.0, 1.0]:
				var fin := _box(Vector3(0.012, ry * 1.15, rz * 0.7),
					Vector3(side * (rx * 0.5 + 0.004), 0.004, -0.02), gun)
				fin.rotation.z = 0.22 * side
			var core := _cyl(0.012, rz * 0.9, Vector3(0, ry * 0.22, -0.02), accent)
			core.rotation.x = PI / 2.0
			# A pair of prongs at the muzzle, where a barrel would be.
			for side: float in [-1.0, 1.0]:
				var prong := _box(Vector3(0.014, 0.030, 0.075),
					Vector3(side * 0.026, 0.012, barrel_z - barrel.z * 0.4), gun)
				prong.rotation.y = -0.18 * side
		Make.ASTARTES:
			# HEAVY, AND DECORATED. A bolter is a ritual object as much as a gun:
			# a fat shell casing box under the receiver, a purity seal hanging off
			# the side, and a wide muzzle collar.
			_box(Vector3(rx * 1.25, 0.045, rz * 0.5),
				Vector3(0, -ry * 0.5 - 0.020, -0.04), gun)
			_box(Vector3(0.006, 0.052, 0.030),
				Vector3(rx * 0.5 + 0.004, -0.012, rz * 0.22), bright)   # seal
			var collar := _cyl(barrel.x * 1.5, 0.030,
				Vector3(0, 0.012, barrel_z - barrel.z * 0.34), bright)
			collar.rotation.x = PI / 2.0
			# Chunky top rail cheeks, because an Astartes optic is a slab — but
			# not a slab across the player's notch.
			for side: float in [-1.0, 1.0]:
				_box(Vector3(rx * 0.22, 0.018, rz * 0.34),
					Vector3(side * SIGHT_CHANNEL_X, ry * 0.5 + 0.012, -rz * 0.1), gun)
		Make.NECRON:
			# A BLADE, NOT A GUN. Necron weapons are flat, angular and lit from
			# inside: a spine down the top with a green channel in it, and two
			# swept vanes at the muzzle instead of a barrel shroud.
			for side: float in [-1.0, 1.0]:
				_box(Vector3(0.006, 0.026, rz * 1.1),
					Vector3(side * SIGHT_CHANNEL_X, ry * 0.5 + 0.012, -0.02), gun)
				_box(Vector3(0.004, 0.010, rz * 0.95),
					Vector3(side * SIGHT_CHANNEL_X, ry * 0.5 + 0.024, -0.02), accent)
			for side: float in [-1.0, 1.0]:
				var vane := _box(Vector3(0.010, 0.055, 0.14),
					Vector3(side * 0.020, 0.012, barrel_z - barrel.z * 0.2), gun)
				vane.rotation.z = 0.30 * side
				vane.rotation.y = -0.10 * side
			var tube := _cyl(0.008, barrel.z * 0.8,
				Vector3(0, 0.012, barrel_z), accent)
			tube.rotation.x = PI / 2.0
		Make.ORK:
			# BOLTED-ON SCRAP, and deliberately ASYMMETRIC — a matched pair reads
			# as issued kit, which orks do not have. Plates at angles, rivets, and
			# an oversized ammo drum hanging off one side.
			_box(Vector3(rx * 0.5, ry * 0.9, rz * 0.4),
				Vector3(-rx * 0.45, 0.010, -rz * 0.1), gun).rotation.z = 0.12
			_box(Vector3(rx * 0.8, ry * 0.5, rz * 0.3),
				Vector3(rx * 0.30, -ry * 0.3, rz * 0.2), bright).rotation.x = -0.10
			for i in 5:
				_box(Vector3(0.010, 0.010, 0.010),
					Vector3(rx * 0.5, ry * 0.1 - i * 0.012, -rz * 0.3 + i * 0.016),
					bright)   # rivets, crookedly spaced
			var drum := _cyl(0.055, 0.038,
				Vector3(-rx * 0.7, -ry * 0.35, 0.02), dark)
			drum.rotation.z = PI / 2.0
			# A crude flame-cut muzzle: three teeth of different lengths.
			for i in 3:
				_box(Vector3(0.012, 0.012, 0.030 + i * 0.012),
					Vector3(-0.014 + i * 0.014, 0.012,
						barrel_z - barrel.z * 0.5 - 0.02), gun)
		_:
			# STAR WARS: a cooling shroud with a lit seam, which is the look the
			# whole catalogue started from.
			_box(Vector3(0.006, 0.010, rz * 0.55),
				Vector3(-rx * 0.5 - 0.002, ry * 0.28, -0.02), accent)


## The lightsaber: a machined hilt with a blade standing out of it. Built on its
## own path because it shares no part with a gun.
##
## The blade is TWO nested cylinders — a near-white core inside a wider, softer
## coloured shell — because a single emissive cylinder reads as a flat plastic
## rod under GL Compatibility. Both are unshaded, so the blade keeps its colour
## on the night maps where a lit surface would go black on its shadow side (the
## same reason the cable's wire is unshaded).
##
## It leaves `_flash` null: a blade has no muzzle. kick() already null-checks it.
## Read the melee look off the weapon's own profile, falling back to the
## lightsaber's numbers. Done here rather than in SHAPES so the first-person
## blade and the third-person one (CharacterModel.set_melee) read ONE source and
## cannot disagree about what the player is holding.
func _read_blade_look(class_id: int, staff := false) -> void:
	var p: Dictionary = Weapon.PROFILES.get(class_id, {})
	# A pole weapon defaults to the electrostaff's violet, a blade to the
	# lightsaber's blue — so the two weapons that shipped before any of this
	# still build exactly as they did without carrying colour keys of their own.
	_blade_col = p.get("blade_core", STAFF_CORE if staff else BLADE_CORE)
	_glow_col = p.get("blade_glow", STAFF_GLOW if staff else BLADE_GLOW)
	_blade_len = p.get("blade_len", BLADE_LENGTH)
	_blade_rad = float(p.get("blade_width", BLADE_RADIUS * 2.0)) * 0.5
	_blade_energy = p.get("blade_energy", BLADE_ENERGY)
	_hilt_len = p.get("hilt_len", 0.24)


## A blade material. `energy` 0 means the weapon's body is STEEL rather than
## plasma — a chainsword, a thunder hammer, a choppa, a klaw — and steel is a LIT
## surface, not an emitting one.
##
## That distinction was missed the first time and the result was the loudest
## wrong thing in the game: everything came back UNSHADED, which bypasses
## lighting but NOT the tonemap, so a mid-grey albedo went through AgX at
## exposure 1.6 and came out a flat near-white slab with no shading on it
## anywhere. A hammer head lit from no direction, at one value across every face,
## reads as frosted glass — and the additive aura wrapped round it (below) let
## the horizon show straight through. "Shiny, transparent and glowing" was three
## symptoms of one cause.
##
## Unshaded is still right for PLASMA: a lit blade goes black on its shadow side,
## and a glowing sword is most of the point on the night maps.
func _blade_mat(color: Color, energy: float, aura: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if energy <= 0.0 and not aura:
		# STEEL. Lit like the rest of the weapon, by the same albedo/roughness
		# split the receiver uses (see the palette in `_build`): metallic kept
		# moderate because these skies are near-black and a mirror reflects
		# nothing, with the shine coming off the DIRECT lights instead.
		m.albedo_color = color
		m.metallic = 0.0            # solid: see the palette note in `_build`
		m.metallic_specular = 0.6
		m.roughness = 0.32
		return m
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r, color.g, color.b, 0.5) if aura else color
	if aura:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
	return m


## A slim blade is a cylinder; a HEAD (a thunder hammer, a power klaw) is a box.
## The threshold lives on Weapon, next to the profiles it classifies, because the
## third-person blade splits on it too and the two viewpoints must not disagree.
const BLADE_HEAD_WIDTH := Weapon.BLADE_HEAD_WIDTH


func _build_saber() -> void:
	# Everything hangs off one pivot so the whole weapon swings as a piece. The
	# viewmodel root cannot be used for that: its transform is already driven by
	# recoil, bob and the ADS slide every frame.
	_saber = Node3D.new()
	_saber.name = "Saber"
	add_child(_saber)
	_saber.position = SABER_AT
	_saber.rotation = SABER_REST

	var hilt_mat := StandardMaterial3D.new()
	hilt_mat.albedo_color = Color(0.16, 0.17, 0.19)
	hilt_mat.metallic = 0.0   # solid: metallic is a mirror of the sky, not a shine
	hilt_mat.roughness = 0.35
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.42, 0.36, 0.20)
	ring_mat.metallic = 0.0
	ring_mat.roughness = 0.4

	# The hilt sits in the hand, angled like the pistol grip every gun carries.
	# A hammer's haft is long, a sword's grip is short — one number, from the
	# profile, and the emitter/blade slide down the shaft to follow it.
	var hilt := _cyl(0.021, _hilt_len, Vector3(0, -0.015, 0.0), hilt_mat, _saber)
	var mouth := -_hilt_len * 0.42
	_cyl(0.025, 0.02, Vector3(0, -0.015, mouth), ring_mat, _saber)    # emitter shroud
	_cyl(0.024, 0.015, Vector3(0, -0.015, _hilt_len * 0.25), ring_mat, _saber)  # pommel
	_box(Vector3(0.012, 0.014, 0.03), Vector3(0.02, -0.015, 0.02), ring_mat, _saber)

	var core_mat := _blade_mat(_blade_col, _blade_energy, false)
	# THE AURA IS ADDITIVE, AND ADDITIVE MEANS SEE-THROUGH. That is the right
	# trade for plasma — a blade IS light, and what shows through it is part of
	# the effect — and the wrong one everywhere else: an additive shell drawn over
	# a solid object makes the object translucent, because the shell is in front
	# and the shell is transparent. So it is only ever built where the thing
	# underneath is meant to be light.
	var glow_mat := _blade_mat(_glow_col, 3.0, true)

	# Blade runs down -Z out of the emitter, the same axis every barrel uses.
	var blade_z := mouth - 0.01 - _blade_len * 0.5
	if _blade_rad > BLADE_HEAD_WIDTH:
		# A HEAD, not a blade — and the split doubles as the rule for who carries
		# a field, which is why no new key is needed: every boxed head in the
		# game (grav hammer, thunder hammer, power klaw) is a power weapon, and
		# every steel cylinder (chainsword, choppa) is a plain length of metal.
		#
		# Steel, and it stays steel: the power field is a
		# CAP on the striking face, sitting proud of it and INSIDE the head's own
		# width, not a shell wrapped round the head. A shell drawn wider than what
		# it covers is transparent over the sky on the outside and transparent
		# over the metal on the inside, which is what turned a hammer into a
		# frosted brick.
		_box(Vector3(_blade_rad * 2.0, _blade_rad * 1.5, _blade_len),
			Vector3(0, -0.015, blade_z), core_mat, _saber)
		_box(Vector3(_blade_rad * 1.7, _blade_rad * 1.2, _blade_len * 0.10),
			Vector3(0, -0.015, blade_z - _blade_len * 0.52), glow_mat, _saber)
	else:
		_cyl(_blade_rad, _blade_len, Vector3(0, -0.015, blade_z), core_mat, _saber)
		# Plasma only. A chainsword and a choppa are lengths of steel with no
		# field on them at all, and a sleeve at 1.9x the radius over one is a
		# translucent paddle with a sword somewhere inside it.
		if _blade_energy > 0.0:
			_cyl(_blade_rad * 1.9, _blade_len * 0.99, Vector3(0, -0.015, blade_z),
				glow_mat, _saber)
	hilt.name = "SaberHilt"
	# Held so a parry can flare them. They belong to this blade alone (built here,
	# not shared out of a table), so writing to them cannot leak onto anyone else.
	_blade_core = core_mat
	_blade_glow = glow_mat

	# No sights on a sword. Aiming blocks instead, so the ADS slide is a small
	# guard-raise rather than bringing anything onto the camera axis.
	_ads_pos = Vector3(-0.05, 0.02, 0.02)


## Where the off-hand shield sits, stowed low-left at rest and raised across the
## LEFT of the view when the guard is up — never over the crosshair (same rule the
## saber blade follows), so you can still see to fight.
const SHIELD_STOW := Vector3(-0.34, -0.46, 0.04)
const SHIELD_GUARD := Vector3(-0.26, -0.05, -0.34)
# The BX commando-droid shield: an elongated, pointed hexagon — yellow panels in a
# grey frame with radiating ribs and a small central emitter hub.
const SHIELD_W := 0.13   # half-width
const SHIELD_H := 0.25   # half-height (taller than wide: the pointed lozenge shape)
const SHIELD_YELLOW := Color(0.93, 0.75, 0.16)
const SHIELD_FRAME := Color(0.30, 0.31, 0.34)
const SHIELD_RIB := Color(0.20, 0.21, 0.24)
const SHIELD_HUB := Color(0.14, 0.15, 0.17)
const SHIELD_HUB_BAR := Color(0.62, 0.64, 0.68)
# The electrostaff's charge is VIOLET, not the saber's blue — the IG-100 look.
const STAFF_CORE := Color(0.86, 0.62, 1.0)   # violet-white charged core
const STAFF_GLOW := Color(0.58, 0.16, 0.98)  # purple aura around it
# The crackling lightning at the tips is DERIVED (halfway between the core and
# its aura) rather than stated, so a pole weapon that picks its own colours — a
# Necron warscythe's green — crackles in them without a third colour key.
const STAFF_ARC_BOLTS := 3       # little bolts spitting off each emitter
const STAFF_ARC_SEGS := 4        # jagged pieces per bolt
const STAFF_ARC_JITTER := 0.02   # how far a joint kicks off line, in m
const STAFF_ARC_WIDTH := 0.006


## The electrostaff: a metal pole through the hand with an electro-tip at each
## end, built under the same pivot the saber uses so the swing/guard/parry
## animation drives it unchanged. The off-hand SHIELD is a separate node on the
## viewmodel root (it is the other hand, not part of the swinging weapon) that
## _animate_saber raises with the guard.
func _build_staff() -> void:
	_saber = Node3D.new()
	_saber.name = "Staff"
	add_child(_saber)
	_saber.position = SABER_AT
	_saber.rotation = SABER_REST

	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.11, 0.12, 0.14)
	pole_mat.metallic = 0.0    # solid, like every other weapon part
	pole_mat.roughness = 0.3
	var band_mat := StandardMaterial3D.new()   # brushed-metal segment rings
	band_mat.albedo_color = Color(0.34, 0.35, 0.38)
	band_mat.metallic = 0.0
	band_mat.roughness = 0.35

	# A long dark pole down -Z through the grip, more of it forward than back so it
	# reads as a reaching weapon; a few segment rings break up its length.
	_cyl(0.015, 1.02, Vector3(0, -0.015, -0.14), pole_mat, _saber)
	for z in [-0.02, 0.12, -0.30, 0.24]:
		_cyl(0.019, 0.022, Vector3(0, -0.015, z), band_mat, _saber)

	# One shared material and unit box for every tip's crackling arcs, allocated
	# once here and only repositioned each frame (the lightning_arc rule).
	_arc_box = BoxMesh.new()
	_arc_box.size = Vector3.ONE
	_staff_arc_mat = StandardMaterial3D.new()
	_staff_arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_staff_arc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_staff_arc_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	# The arc colour sits between the core and its aura, so a green warscythe
	# crackles green without a fourth colour key on every pole weapon.
	var arc_col := _blade_col.lerp(_glow_col, 0.5)
	_staff_arc_mat.albedo_color = arc_col
	_staff_arc_mat.emission_enabled = true
	_staff_arc_mat.emission = arc_col
	_staff_arc_mat.emission_energy_multiplier = 4.0

	# The two charged emitter heads. The FRONT one is the business end a parry
	# flares, so it owns _blade_core/_blade_glow; both crackle (see _animate_saber).
	var front_end := -0.14 - 0.51
	var back_end := -0.14 + 0.51
	_blade_core = _staff_emitter(front_end, -1.0, pole_mat, band_mat)
	_blade_glow = _staff_glows[0]
	_staff_emitter(back_end, 1.0, pole_mat, band_mat)

	# The off-hand BX shield, hidden at rest and faded up with the guard.
	_build_shield()

	_ads_pos = Vector3(-0.05, 0.02, 0.02)


## One charged emitter head at the end of the staff, IG-100 style: a metal collar,
## a splayed fork of METAL prongs, a slim violet core between them and a TIGHT halo
## (not a fat glow bulb), and a set of small purple arcs crackling across the fork
## (laid out each frame in _crackle_staff). `outward` is -1 for the front end
## (extends -Z) or +1 for the back (+Z). Returns the core material; registers the
## core, halo and arcs for the crackle.
func _staff_emitter(base_z: float, outward: float,
		collar_mat: StandardMaterial3D, prong_mat: StandardMaterial3D) -> StandardMaterial3D:
	var y := -0.015
	var core_mat := _blade_mat(_blade_col, _blade_energy, false)
	var glow_mat := _blade_mat(_glow_col, 2.4, true)
	# A metal collar where the pole meets the head, and a slightly flared cap.
	_cyl(0.024, 0.06, Vector3(0, y, base_z), collar_mat, _saber)
	_cyl(0.03, 0.02, Vector3(0, y, base_z + outward * 0.04), collar_mat, _saber)
	# A fork of three METAL prongs splaying outward past the core, so the head reads
	# as an emitter rather than a glowing blob.
	var prong_end := base_z + outward * 0.15
	for k in 3:
		var a := TAU * float(k) / 3.0
		var off := Vector2(cos(a), sin(a))
		var p := _cyl(0.007, 0.17, Vector3(off.x * 0.03, y + off.y * 0.03, prong_end),
			prong_mat, _saber)
		# Splay the prong so it opens away from the axis toward its tip.
		p.rotation = Vector3(off.y * 0.28, -off.x * 0.28, 0.0)
	# The slim charged core and a TIGHT halo — the crackle, not the bulb, is the tell.
	var mid := base_z + outward * 0.09
	_cyl(0.008, 0.20, Vector3(0, y, mid), core_mat, _saber)
	_cyl(0.022, 0.16, Vector3(0, y, mid), glow_mat, _saber)
	# The crackling arcs: bolts from just inside the head out past the fork.
	for _b in STAFF_ARC_BOLTS:
		var segs: Array[MeshInstance3D] = []
		for _s in STAFF_ARC_SEGS:
			var mi := MeshInstance3D.new()
			mi.mesh = _arc_box
			mi.material_override = _staff_arc_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_saber.add_child(mi)
			segs.append(mi)
		_staff_bolts.append({
			"base": Vector3(0, y, base_z + outward * 0.06),
			"reach": outward * 0.16, "segs": segs})
	_staff_cores.append(core_mat)
	_staff_glows.append(glow_mat)
	return core_mat


## The BX commando-droid shield the Magna Guard blocks with: an elongated pointed
## hexagon of yellow panels in a grey frame, ribs radiating to the corners, and a
## small emitter hub. Every part is an unshaded, cull-disabled flat mesh (so it
## reads on the dark maps and winding never matters) faded together with the guard
## via _shield_mats / _shield_alpha.
func _build_shield() -> void:
	_shield = Node3D.new()
	_shield.name = "GuardShield"
	add_child(_shield)
	_shield.position = SHIELD_STOW
	var w := SHIELD_W
	var h := SHIELD_H
	# Layered front-to-back by local z (higher z = nearer the camera) AND by
	# render_priority, so the transparent panels sort deterministically: grey frame
	# at the back showing as a border, the yellow fill over it, then the ribs and
	# the hub on top.
	_shield_hex(w + 0.024, h + 0.028, 0.0, _shield_mat(SHIELD_FRAME, 1.0))
	_shield_hex(w, h, 0.006, _shield_mat(SHIELD_YELLOW, 0.95))
	# Ribs: a vertical spine top-to-bottom and four spokes out to the side corners,
	# splitting the yellow into panels the way the reference does.
	var rib := _shield_mat(SHIELD_RIB, 1.0)
	_shield_rib(Vector2(0, h), Vector2(0, -h), 0.012, rib)
	for v in [Vector2(w, 0.42 * h), Vector2(w, -0.42 * h),
			Vector2(-w, -0.42 * h), Vector2(-w, 0.42 * h)]:
		_shield_rib(Vector2.ZERO, v, 0.010, rib)
	# The central emitter hub: a small dark hexagon with three light bars across.
	_shield_hex(0.05, 0.062, 0.014, _shield_mat(SHIELD_HUB, 1.0))
	var bar := _shield_mat(SHIELD_HUB_BAR, 1.0)
	for oy in [-0.022, 0.0, 0.022]:
		_box(Vector3(0.062, 0.006, 0.006), Vector3(0, oy, 0.018), bar, _shield)
	_shield.visible = false


## A tracked shield material: unshaded and cull-disabled, starting fully
## transparent (the guard fades it in). Registered so _animate_saber fades and
## flares every part of the shield as one.
func _shield_mat(color: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color, 0.0)
	# Draw order = build order (frame, fill, ribs, hub, bars), so the layers never
	# fight over which transparent quad is in front.
	m.render_priority = _shield_mats.size()
	_shield_mats.append(m)
	_shield_alpha.append(alpha)
	return m


## A flat elongated hexagon in the XY plane (pointed top and bottom), triangle-fan
## from the centre. Winding is irrelevant — the material is cull-disabled.
func _shield_hex(w: float, h: float, z: float, mat: StandardMaterial3D) -> void:
	var pts := [Vector2(0, h), Vector2(w, 0.42 * h), Vector2(w, -0.42 * h),
		Vector2(0, -h), Vector2(-w, -0.42 * h), Vector2(-w, 0.42 * h)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3(0, 0, 1))
	for i in 6:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % 6]
		st.add_vertex(Vector3(0, 0, z))
		st.add_vertex(Vector3(a.x, a.y, z))
		st.add_vertex(Vector3(b.x, b.y, z))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shield.add_child(mi)


## A thin rib from `a` to `b` in the panel plane, drawn just in front of the fill.
func _shield_rib(a: Vector2, b: Vector2, thick: float, mat: StandardMaterial3D) -> void:
	var d := b - a
	var mid := (a + b) * 0.5
	var mi := _box(Vector3(thick, d.length(), 0.006),
		Vector3(mid.x, mid.y, 0.011), mat, _shield)
	mi.rotation.z = atan2(d.y, d.x) - PI / 2.0


## The colour of the glow at the barrel tip. Owned rather than hardcoded because
## it is the SHOOTER's own view of their gun's fire, and it has to be the colour
## their rounds actually are — Weapon pushes it (see Weapon.bolt_color), so an
## Imperial rifle flashes green in the hands holding it as well as on the wall.
var _flash_col := Color(1.0, 0.72, 0.35)
var _flash_mat: StandardMaterial3D


## Compare then write, and never build a second material: this is reached from
## the firing path, so it runs as often as the trigger does.
func set_flash_color(col: Color) -> void:
	if col == _flash_col:
		return
	_flash_col = col
	if _flash_mat != null:
		_flash_mat.albedo_color = col
		_flash_mat.emission = col


func _build_flash(tip_z: float) -> void:
	# Muzzle flash: a small additive glow at the barrel tip, flicked on for a
	# couple of frames per shot (additive so it reads as light, not a solid
	# orange shape, under the GL Compatibility renderer).
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fmat.albedo_color = _flash_col
	fmat.emission_enabled = true
	fmat.emission = _flash_col
	fmat.emission_energy_multiplier = 4.0
	_flash_mat = fmat
	_flash = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.045
	sph.height = 0.09
	sph.radial_segments = 8
	sph.rings = 4
	_flash.mesh = sph
	_flash.material_override = fmat
	_flash.position = Vector3(0, 0.012, tip_z)
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	add_child(_flash)


## `into` lets a caller build under its own pivot instead of straight onto the
## viewmodel root — the saber needs that, because the whole weapon swings as one
## piece and the root's transform is already spoken for by recoil and bob.
func _box(size: Vector3, pos: Vector3, mat: Material,
		into: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	# Chamfered, like the body parts — and it matters MORE here than anywhere
	# else, because a first-person weapon sits half a metre from the camera and
	# fills a quarter of the frame. A hard edge at that distance is unmissable.
	mi.mesh = Meshes.chamfer_box(size)
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(into if into != null else self).add_child(mi)
	return mi


func _cyl(radius: float, height: float, pos: Vector3, mat: Material,
		into: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	mi.mesh = m
	mi.position = pos
	mi.rotation.x = PI / 2.0  # CylinderMesh is Y-up; lay it along -Z (barrel/scope)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(into if into != null else self).add_child(mi)
	return mi


## Rebuild the gun for this class and sight. Called on every class change, so
## each weapon genuinely has its own silhouette rather than a shared body with
## a couple of parts hidden. The sniper ships with optics; anything else grows
## a scope or a holo ring only when one is bought.
func configure(class_id: int, scoped := false, holo := false) -> void:
	# The sniper ships with optics, but a bought holo ring replaces them rather
	# than sitting alongside — two sights on one rail is nobody's intent.
	_build(class_id, (scoped or class_id == Weapon.Class.SNIPER) and not holo, holo)
	# Every part in there is new, so the owner's layer has to go on again. Done
	# here rather than inside _build because _build returns early for a blade.
	_apply_view_layer()


## Put the freshly built parts on the owner's private viewmodel layer.
func _apply_view_layer() -> void:
	if view_layer == 0:
		return
	for mi in find_children("*", "MeshInstance3D", true, false):
		mi.layers = view_layer


## The saber's own animation. Two states and one action:
##
## AT REST it sits in the ready stance, riding the same walk bob as every other
## weapon so it does not float independently of the body.
##
## AIMING is the GUARD, so the blade comes up ACROSS the body — the pose has to
## read as "I am blocking with this", because the exhaustion pool it spends is
## invisible otherwise.
##
## SWINGING is a single arc traced by sin(): the blade accelerates through the
## strike and settles back, and consecutive swings alternate sides so holding
## the trigger looks like a sequence of cuts rather than one chop on repeat.
## `_aim_t` is stepped by the caller, once, for every weapon: stepping it again
## here fought the caller's own step and left the raise crawling.
func _animate_saber(delta: float, bob: Vector3) -> void:
	_swing = maxf(_swing - delta / SWING_TIME, 0.0)
	_parry = maxf(_parry - delta / PARRY_TIME, 0.0)
	_brace_t += delta * GUARD_BRACE_RATE

	# The viewmodel root only carries the bob and the guard's draw-in; the swing
	# and the parry belong to the saber pivot.
	position = HIP_POS.lerp(GUARD_DRAW_IN, _aim_t) + bob + PARRY_PUSH * _parry
	rotation = Vector3.ZERO

	# Guard: blade brought up across the view, hilt drawn in to the chest.
	var pose := SABER_REST.lerp(GUARD_ROT, _aim_t)
	var at := SABER_AT.lerp(GUARD_AT, _aim_t)
	# ...and BRACED there. A pose that holds perfectly still reads as a frozen
	# animation, which is the one thing a defensive stance must not look like.
	pose += Vector3(sin(_brace_t) * GUARD_BRACE,
		sin(_brace_t * 0.63) * GUARD_BRACE * 0.7, 0.0) * _aim_t

	# 0 at the start of the swing, 1 at the end; sin() gives the arc a fast
	# middle and a soft finish at both ends.
	var t := 1.0 - _swing
	var arc := sin(t * PI)
	pose += Vector3(
		arc * SWING_PITCH,
		arc * SWING_YAW * _swing_side,
		arc * SWING_ROLL * -_swing_side)

	# The parry rocks the blade back off the impact and springs it home. Same sin
	# arc as the swing, so a block reads as a deliberate motion rather than a
	# twitch, and it alternates sides so a burst stopped by the guard looks like
	# the blade working rather than one shudder repeated.
	if _parry > 0.0:
		var knock := sin((1.0 - _parry) * PI)
		pose += Vector3(PARRY_ROT.x, PARRY_ROT.y * _parry_side,
			PARRY_ROT.z * _parry_side) * knock

	_saber.rotation = pose
	_saber.position = at
	# The off-hand shield rides up into the block with the guard and fades away
	# again as it drops — the visible half of "shield as blocker in the other
	# hand", where the pool and the arc are just numbers.
	if _shield != null:
		_shield.visible = _aim_t > 0.02
		_shield.position = SHIELD_STOW.lerp(SHIELD_GUARD, _aim_t) + bob * 0.5
		var flare := _parry * 0.25   # a bright flash across the whole shield on a block
		for i in _shield_mats.size():
			_shield_mats[i].albedo_color.a = clampf(_shield_alpha[i] * _aim_t + flare, 0.0, 1.0)
	# The saber flares its single blade on a parry; the staff crackles both tips.
	if _staff_glows.is_empty():
		_flare_blade()
	else:
		_crackle_staff(delta)
	visible = true


## The electrostaff's tips crackle: a fast irregular flicker on the core/halo
## emission, and the little arcs re-jag every frame — laid down a jagged line from
## just inside each head out past the fork. A parry surges all of it.
func _crackle_staff(delta: float) -> void:
	_crackle_t += delta * 20.0
	var crk := 0.65 + 0.45 * absf(sin(_crackle_t)) + 0.3 * absf(sin(_crackle_t * 2.7))
	var flare := PARRY_FLARE * _parry
	for m in _staff_cores:
		m.emission_energy_multiplier = (BLADE_ENERGY + flare) * crk
	for m in _staff_glows:
		m.emission_energy_multiplier = (2.4 + flare * 0.6) * crk
	_staff_arc_mat.emission_energy_multiplier = (3.5 + flare) * crk
	var j := STAFF_ARC_JITTER
	for bolt in _staff_bolts:
		var a: Vector3 = bolt["base"]
		# The bolt's far end dances past the fork each frame.
		var b: Vector3 = a + Vector3(randf_range(-j, j), randf_range(-j, j),
			bolt["reach"] + randf_range(-j, j))
		var segs: Array = bolt["segs"]
		var n := segs.size()
		var prev := a
		for i in n:
			var t := float(i + 1) / float(n)
			var pt := a.lerp(b, t)
			if i < n - 1:   # the last joint lands on the end; the rest jag
				pt += Vector3(randf_range(-j, j), randf_range(-j, j), randf_range(-j, j))
			_place_seg(segs[i], prev, pt)
			prev = pt


## Stretch one arc segment between two points in the STAFF's local space (the
## segments are children of the swing pivot, so they ride the swing). The unit box
## is scaled to the gap and its -Z aimed down the run.
func _place_seg(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var span := b - a
	var length := span.length()
	if length < 0.0005:
		mi.visible = false
		return
	mi.visible = true
	var up := Vector3.UP
	if absf(span.normalized().dot(up)) > 0.99:
		up = Vector3.RIGHT
	mi.transform = Transform3D(Basis.looking_at(span, up), (a + b) * 0.5)
	mi.scale = Vector3(STAFF_ARC_WIDTH, STAFF_ARC_WIDTH, length)


## Push the parry's brightness onto the blade. The flare is on the EMISSION
## rather than on a separate flash mesh so it lights the whole length of the
## blade at once, which is what sells contact somewhere along it.
func _flare_blade() -> void:
	if _blade_core == null:
		return
	var flare := PARRY_FLARE * _parry
	_blade_core.emission_energy_multiplier = BLADE_ENERGY + flare
	_blade_glow.emission_energy_multiplier = 3.0 + flare * 0.6


## The guard just stopped a hit. Cosmetic only — Player has already decided what
## the block cost and whether it broke.
func parry() -> void:
	if _saber == null:
		return
	_parry = 1.0
	_parry_side = -_parry_side


## Called on each shot; strength scales the kick per weapon class.
func kick(strength: float) -> void:
	# A blade swings; it does not recoil. Alternating the side means a held
	# attack reads as a sequence of strikes crossing the body rather than the
	# same chop played over and over.
	if _saber != null:
		_swing = 1.0
		_swing_side = -_swing_side
		return
	_kick = minf(_kick + strength, KICK_CEILING)
	_kick_yaw = randf_range(-1.0, 1.0)
	_flash_t = FLASH_TIME
	if _flash:
		_flash.rotation.z = randf() * TAU
		_flash.scale = Vector3.ONE * randf_range(0.8, 1.3)


func _process(delta: float) -> void:
	var aiming := false
	var scoped := false
	if aiming_source:
		aiming = aiming_source.aiming
		scoped = aiming_source.has_scope()

	# The guard is NOT `weapon.aiming`. Player forces that flag false for a melee
	# weapon — a blade has no sights — so reading it here left _aim_t pinned at 0
	# and the guard pose below never played at all. Ask the OWNER instead, which
	# is also the only thing that knows about the exhaustion pool, so the blade
	# drops back to rest the moment the guard breaks. Bots have no guard_up.
	var guarding: bool = _player != null and _player.has_method("guard_up") \
		and _player.guard_up()

	_aim_t = move_toward(_aim_t, 1.0 if (aiming or guarding) else 0.0, delta / AIM_TIME)
	_sprint_t = move_toward(_sprint_t, 1.0 if sprinting else 0.0,
		delta / (SPRINT_IN if sprinting else SPRINT_OUT))
	_kick = move_toward(_kick, 0.0, delta * RECOIL_DECAY)

	# Walk bob, damped while aiming and only on the ground.
	var speed := 0.0
	if _player and _player.is_on_floor():
		speed = Vector2(_player.velocity.x, _player.velocity.z).length()
	_bob_t += delta * (4.0 + speed * 1.6)
	var bob_amp := 0.011 * clampf(speed / 5.0, 0.0, 1.0) * (1.0 - 0.75 * _aim_t)
	var bob := Vector3(cos(_bob_t) * bob_amp, absf(sin(_bob_t)) * bob_amp, 0.0)

	# A blade has its own motion: it swings on its pivot instead of kicking the
	# whole viewmodel, and raising the guard is a pose rather than a sight slide.
	if _saber != null:
		_animate_saber(delta, bob)
		return

	var pos := HIP_POS.lerp(_ads_pos, _aim_t) + bob
	# How much of the kick actually SHOWS. Raising the sights damps it, so the
	# gun steadies as your eye comes onto the glass.
	var shown := _kick * lerpf(1.0, ADS_KICK_MULT, _aim_t)
	# Recoil shoves the gun back toward the player, capped so a stacked burst
	# can't drive it through the camera.
	pos.z += minf(shown * KICK_PUSH, MAX_PUSH)
	# ...and the sprint carry rides on top of all of it, so a stowed gun still
	# bobs with the stride and still kicks if something makes it fire.
	pos += SPRINT_AT * _sprint_t
	position = pos
	# Muzzle climbs (rotate about +X) with a small random lateral lean.
	rotation = Vector3(shown * KICK_PITCH, shown * _kick_yaw * KICK_LEAN, 0.0) \
		+ SPRINT_ROT * _sprint_t

	if _flash:
		_flash_t = maxf(_flash_t - delta, 0.0)
		_flash.visible = _flash_t > 0.0

	# A scoped weapon replaces the gun with the scope overlay when aimed. Hide it
	# as the overlay takes over so receiver furniture never flashes through the
	# black scope view during the raise.
	visible = not (aiming and scoped and _aim_t > 0.35)
