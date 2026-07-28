class_name Loadout
extends RefCounted
## What a player buys before deploying: a gun, upgrades bolted to it, an armour
## frame, and consumables. Replaces the old fixed classes — every build is spent
## out of the same BUDGET, so "class" is now whatever you can afford.
##
## Every life gets a fresh BUDGET (nothing is earned or banked), and a player's
## build persists across deaths: the buy screen opens pre-filled with it, so
## respawning is one button press unless you want to re-spec.
##
## The catalogue tables below are the whole balance surface — costs and stats
## live here, nowhere else. An instance holds one player's current selections.

const BUDGET := 200

## The CHARACTER CLASSES of every universe, in one enum for the same reason
## Weapon.Class is: KITS is indexed by it, and which universe a class plays in is
## stated on its own row rather than split across three parallel enums. The
## Star Wars five come first, so nothing that already names Kit.CLONE moved.
enum Kit {
	CLONE, MANDALORIAN, FORCE, WOOKIEE, TRANDOSHAN,
	SPARTAN, ODST, SANGHEILI, UNGGOY, JIRALHANAE,          # Halo
	ULTRAMARINE, BLOOD_ANGEL, NECRON, ORK,                 # Warhammer 40,000
}

## --- UNIVERSES ---------------------------------------------------------------
##
## The game plays in one of several SETTINGS, chosen on the menu, and a universe
## is exactly three things: which CLASSES you may pick, which SIDES they fight
## for, and (through those classes' allow-lists) which of the catalogue they can
## reach. Nothing else in the game knows a universe exists — the weapons all live
## in one Weapon.Class enum, the bodies in one CharacterModel.Style enum, and the
## rules, maps and modes are untouched.
##
## Every catalogue row states the universe it belongs to. NO KEY MEANS STAR WARS,
## because that is what the whole catalogue was before this existed and marking
## two hundred existing rows to say "unchanged" is how a table stops being
## readable. ANY is for the handful of rows that belong to nobody in particular.
##
## Why the enum lives HERE and not on GameState, which is where a match setting
## belongs: `--script` test runs have no autoloads, so Loadout may never name
## GameState. GameState mirrors its choice into `active_universe` below instead,
## which is the same trick the TTK multiplier uses.
enum Universe { STAR_WARS, HALO, WARHAMMER }
const ANY_UNIVERSE := -1

const UNIVERSES: Array[Dictionary] = [
	{
		"name": "STAR WARS",
		"blurb": "Clones, droids, Jedi and bounty hunters",
		"kit": Kit.CLONE,          # what a class-free build (royale, starter) wears
		"teams": ["REPUBLIC", "SEPARATIST", "MANDALORE", "HUTT CARTEL"],
		"colors": [Color(0.35, 0.55, 1.0), Color(1.0, 0.40, 0.32),
			Color(0.45, 0.85, 0.45), Color(0.95, 0.78, 0.30)],
	},
	{
		"name": "HALO",
		"blurb": "UNSC ballistics against Covenant plasma",
		"kit": Kit.SPARTAN,
		"teams": ["UNSC", "COVENANT", "BANISHED", "FORERUNNER"],
		"colors": [Color(0.38, 0.78, 0.42), Color(0.70, 0.45, 1.0),
			Color(1.0, 0.45, 0.22), Color(0.45, 0.85, 0.95)],
	},
	{
		"name": "WARHAMMER 40,000",
		"blurb": "Two Astartes chapters, the Necrons and the Orks",
		"kit": Kit.ULTRAMARINE,
		"teams": ["ULTRAMARINES", "BLOOD ANGELS", "NECRONS", "ORKS"],
		"colors": [Color(0.30, 0.50, 1.0), Color(1.0, 0.26, 0.24),
			Color(0.40, 0.95, 0.50), Color(0.86, 0.74, 0.22)],
	},
]

## The universe currently being played, MIRRORED here from GameState.universe so
## that nothing in this file has to reach for an autoload (see above). GameState
## writes it in its own setter, and in _init, so it is right before anything can
## ask.
static var active_universe := Universe.STAR_WARS

## The TIME-TO-KILL multiplier on every body's health, mirrored from
## GameState.ttk for the same reason. It is applied in ONE place — max_health(),
## which every player, bot and heal ceiling already goes through — so a match set
## to REALISTIC is one number and no special cases.
static var ttk_health := 1.0


## Which universe a catalogue row belongs to. Missing means Star Wars: the whole
## original catalogue predates the setting and says so by saying nothing.
static func entry_universe(entry: Dictionary) -> int:
	return int(entry.get("universe", Universe.STAR_WARS))


static func in_universe(entry: Dictionary, universe: int) -> bool:
	var u := entry_universe(entry)
	return u == ANY_UNIVERSE or u == universe


## The universe a CLASS is played in — and, through it, the universe of every
## build wearing that class. This is what lets the allow-lists stay autoload-free:
## a weapon is legal for a kit only if it is from the kit's own universe, and the
## kit is right there on the build being checked.
static func kit_universe(of_kit: int) -> int:
	return int(KITS[clampi(of_kit, 0, KITS.size() - 1)].get("universe", Universe.STAR_WARS))


## The class a build starts on when nobody has picked one: the royale drop-in and
## the free starter loadout both need a body to wear, and it has to be one that
## belongs to the universe being played.
static func default_kit() -> int:
	return int(UNIVERSES[clampi(active_universe, 0, UNIVERSES.size() - 1)]["kit"])


## The class indices this universe offers on the CLASS row.
static func universe_kits() -> Array[int]:
	var out: Array[int] = []
	for i in KITS.size():
		if kit_universe(i) == active_universe:
			out.append(i)
	return out

## CHARACTER CLASSES. A kit is a set of ALLOW-LISTS over the catalogue below,
## not a separate catalogue of its own: every kit shops from the same tables and
## pays out of the same BUDGET, and what separates them is what they are allowed
## to reach and how many gadget slots they carry. That way a new gun or gadget
## is one table entry plus a decision about who may take it, rather than three
## parallel shops that drift apart.
##
## The rules a kit can state:
##   gadgets        which Gadget ids it may buy (also gates the second slot)
##   gadget_slots   how many gadget slots — 2 for every class now
##   secondary_mods which SecondaryMod ids it may buy — DUAL is Mandalorian-only
##   armor          which ARMOR indices it may wear
##   default_armor  what it starts on, which is how "lighter by default" is said
##   sights         if present, the ONLY Sight ids it may fit (else all but the
##                  Trandoshan's thermal)
##   primaries      if present, the ONLY non-kit primary classes it may hold;
##                  a kit's own "kit"-marked weapon is always reachable on top
##   secondaries    the same, for sidearms
##   default_primary the class it opens holding (else `primaries[0]`, else none)
##   starter        the class the FREE starter build hands it (else no primary)
##   speed          multiplier on foot speed, on TOP of the armour frame's
##   health         multiplier on the armour frame's health, same idea as speed
##   dash           true if the class can dash (see Player._dash)
##   universe       which setting the class plays in (absent = Star Wars)
##   style          the CharacterModel.Style its body is built from
##
## A gun marked with a "kit" key in WEAPONS is that kit's alone, so a class
## without an explicit `primaries` list still cannot pick up a lightsaber. A gun
## from ANOTHER UNIVERSE is refused the same way and needs no key at all — see
## _allows_entry, which checks the universe before anything else.
## The table itself is further down, under the gadget and armour catalogues it
## has to name; the enum is at the top of the file, where WEAPONS needs it.

# PRIMARY guns, cheapest first (the menu walks them in this order). "None" is a
# real option: your sidearm is free, so an all-gadget build can skip the rifle
# entirely and still deploy armed.
const WEAPONS: Array[Dictionary] = [
	{"class": -1, "cost": 0},  # -1 = no primary, sidearm only
	{"class": Weapon.Class.SMG, "cost": 40},
	{"class": Weapon.Class.SOLDIER, "cost": 45},
	{"class": Weapon.Class.BURST, "cost": 50},
	{"class": Weapon.Class.CARBINE, "cost": 50},
	{"class": Weapon.Class.SEMI, "cost": 55},
	{"class": Weapon.Class.SCATTERGUN, "cost": 60},
	{"class": Weapon.Class.HEAVY, "cost": 70},
	{"class": Weapon.Class.DMR, "cost": 75},
	# The two heaviest things a body can carry are the WOOKIEE's alone. They keep
	# a `royale` flag because that mode has no classes at all: a rocket tube on
	# the ground works perfectly well for a plain trooper, unlike a lightsaber
	# with no guard behind it, so kit-locking them in the shop must not quietly
	# empty two of the best finds out of the crates.
	{"class": Weapon.Class.HMG, "cost": 80, "kit": Kit.WOOKIEE, "royale": true},
	{"class": Weapon.Class.SNIPER, "cost": 85},
	{"class": Weapon.Class.RPG, "cost": 110, "kit": Kit.WOOKIEE, "royale": true},
	# Appended rather than slotted in by price, because WEAPONS is indexed by
	# POSITION and inserting here would shift every BOT_BUILDS preset below it.
	# The order only exists to walk the menu, and the one kit that can take the
	# saber sees nothing else on the row, so its place in the list is moot.
	{"class": Weapon.Class.SABER, "cost": 55, "kit": Kit.FORCE},

	# --- HALO ----------------------------------------------------------------
	# Priced against the Star Wars column above rather than against each other,
	# so a 200-token budget buys the same SHAPE of build in any universe: a rifle
	# and a gadget, or a heavy gun and nothing else.
	{"class": Weapon.Class.M7_SMG, "cost": 40, "universe": Universe.HALO},
	{"class": Weapon.Class.MA5B, "cost": 45, "universe": Universe.HALO},
	{"class": Weapon.Class.PLASMA_RIFLE, "cost": 45, "universe": Universe.HALO},
	{"class": Weapon.Class.BR55, "cost": 55, "universe": Universe.HALO},
	{"class": Weapon.Class.COV_CARBINE, "cost": 55, "universe": Universe.HALO},
	{"class": Weapon.Class.NEEDLER, "cost": 55, "universe": Universe.HALO},
	{"class": Weapon.Class.M90_SHOTGUN, "cost": 60, "universe": Universe.HALO},
	{"class": Weapon.Class.ENERGY_SWORD, "cost": 60, "universe": Universe.HALO},
	{"class": Weapon.Class.GRAV_HAMMER, "cost": 70, "universe": Universe.HALO},
	{"class": Weapon.Class.BRUTE_SHOT, "cost": 70, "universe": Universe.HALO},
	{"class": Weapon.Class.M392_DMR, "cost": 75, "universe": Universe.HALO},
	{"class": Weapon.Class.M247_HMG, "cost": 80, "universe": Universe.HALO},
	{"class": Weapon.Class.SRS99, "cost": 85, "universe": Universe.HALO},
	{"class": Weapon.Class.BEAM_RIFLE, "cost": 85, "universe": Universe.HALO},
	{"class": Weapon.Class.FUEL_ROD, "cost": 105, "universe": Universe.HALO},
	{"class": Weapon.Class.SPNKR, "cost": 110, "universe": Universe.HALO},
	{"class": Weapon.Class.SPARTAN_LASER, "cost": 115, "universe": Universe.HALO},

	# --- WARHAMMER 40,000 ----------------------------------------------------
	{"class": Weapon.Class.CHOPPA, "cost": 40, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.SHOOTA, "cost": 45, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.GAUSS_FLAYER, "cost": 45, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.CHAINSWORD, "cost": 45, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.BOLTER, "cost": 50, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.TESLA_CARBINE, "cost": 50, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.STAFF_OF_LIGHT, "cost": 55, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.BURNA, "cost": 55, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.FLAMER, "cost": 60, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.GAUSS_BLASTER, "cost": 60, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.POWER_SWORD, "cost": 60, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.HEAT_RAY, "cost": 65, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.WARSCYTHE, "cost": 65, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.POWER_KLAW, "cost": 70, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.BIG_SHOOTA, "cost": 70, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.THUNDER_HAMMER, "cost": 75, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.HEAVY_BOLTER, "cost": 80, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.STALKER_BOLT, "cost": 80, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.MEGA_BLASTA, "cost": 80, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.MELTAGUN, "cost": 85, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.SYNAPTIC_DISINTEGRATOR, "cost": 85, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.PLASMA_GUN, "cost": 90, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.GRENADE_LAUNCHER, "cost": 95, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.ROKKIT_LAUNCHA, "cost": 105, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.TRANSDIMENSIONAL_BEAMER, "cost": 110, "universe": Universe.WARHAMMER},
]
const NO_PRIMARY := 0  # index of the "none" row above

# SECONDARY: sidearms. Everyone carries one, and the cheapest is free, so you
# are never left without a gun. The swap control moves between primary and
# secondary; the secondary has its own modification slot (SECONDARY_MODS).
const SECONDARIES: Array[Dictionary] = [
	{"class": Weapon.Class.PISTOL, "cost": 0},
	{"class": Weapon.Class.DH17, "cost": 15},
	{"class": Weapon.Class.HOLDOUT, "cost": 20},
	{"class": Weapon.Class.REVOLVER, "cost": 35},
	{"class": Weapon.Class.BRYAR, "cost": 40},
	# The Wookiee's, and the only sidearm it may carry. Free for the same reason
	# the pistol is: it is not a choice, it is what the class has in its hands,
	# and charging for the one option is just a smaller budget.
	{"class": Weapon.Class.BOWCASTER, "cost": 0, "kit": Kit.WOOKIEE},

	# Every universe needs its own FREE sidearm, for the reason the DL-44 is free
	# here: the cheapest sidearm is not a choice, it is what is in your other
	# hand, and charging for the only option a faction has is just a smaller
	# budget. Which of them a class may actually hold is its `secondaries` list.
	{"class": Weapon.Class.M6D, "cost": 0, "universe": Universe.HALO},
	{"class": Weapon.Class.PLASMA_PISTOL, "cost": 0, "universe": Universe.HALO},
	{"class": Weapon.Class.MAULER, "cost": 30, "universe": Universe.HALO},
	{"class": Weapon.Class.BOLT_PISTOL, "cost": 0, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.GAUSS_PISTOL, "cost": 0, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.SLUGGA, "cost": 0, "universe": Universe.WARHAMMER},
	{"class": Weapon.Class.PLASMA_PISTOL_40K, "cost": 30, "universe": Universe.WARHAMMER},
]

# The sidearm's own slot. Deliberately NOT the primary's three upgrades: a
# sidearm gets one pick, and dual wield is the one that changes how it plays
# rather than how it shoots.
enum SecondaryMod { NONE, SCOPE, COOLING, DUAL }
const SECONDARY_MODS: Array[Dictionary] = [
	{"name": "NONE", "cost": 0, "blurb": "Sidearm as issued"},
	{"name": "SCOPE", "cost": 20,
		"blurb": "Pinpoint while aimed, at the cost of the scope blackout"},
	{"name": "COOLING", "cost": 15, "blurb": "-25% heat per shot, cools faster"},
	{"name": "DUAL WIELD", "cost": 35,
		"blurb": "Carry two. Fire is the right gun, aim is the left, both to fire together"},
]

# Sights are one slot with several options rather than stackable toggles: a
# reflex dot, a holo ring and the two magnified scopes are ALTERNATIVES, and you
# fit one. Walked left-to-right in this order (roughly increasing magnification),
# which is also the SIGHTS array order — the array is indexed by the enum value,
# so the two must stay in step.
enum Sight { NONE, RED_DOT, HOLO, SCOPE, SCOPE_4X, THERMAL }
const SIGHTS: Array[Dictionary] = [
	{"name": "IRON", "cost": 0, "blurb": "Open sights"},
	# The cheap close-combat optic: clear view, a crisp dot, barely any zoom, a
	# small steadying of the aim. The reflex sight to the holo's ring.
	{"name": "RED DOT", "cost": 15,
		"blurb": "Reflex dot: clear view, minimal zoom, a little tighter aim"},
	{"name": "HOLO RING", "cost": 20,
		"blurb": "Hollow ring sight: clear view, mild zoom, tighter aim"},
	{"name": "SCOPE", "cost": 25,
		"blurb": "Pinpoint accurate while aimed, but it blacks out everything around it"},
	# The long-range option: 4x magnification for reaching across the big maps,
	# same pinpoint-and-blackout trade as the scope but zoomed much further in.
	{"name": "4X SCOPE", "cost": 35,
		"blurb": "4x sniper scope: pinpoint at range, but a heavy blackout around it"},
	# The Trandoshan's, and only theirs: a holo ring that paints enemy HEAT while
	# aimed, so it reads bodies straight through smoke — which is the whole combo
	# with the class's smoke grenades. Aims like the holo (clear view, mild
	# zoom); the heat read is drawn on the player's own HUD, see Main.
	{"name": "THERMAL HOLO", "cost": 30, "kit": Kit.TRANDOSHAN,
		"blurb": "Holo ring that marks enemy heat through smoke while aimed"},
]

# Bolt-ons that modify the gun's profile (see Weapon.set_class). Each is owned
# or not; `key` is the field on this object that stores that.
## One per COOLING/GRIP/FOREGRIP row. Their ORDER must match those
## rows (see _upgrade_index, which maps `row - Row.COOLING` into this array), so
## a new bolt-on is a new row directly after GRIP and a new entry appended here.
const UPGRADES: Array[Dictionary] = [
	{"key": "cooling", "name": "COOLING VANES", "cost": 20, "blurb": "-25% heat per shot, cools faster"},
	# GRIP is now ACCURACY only — the kick reduction moved to the front grip, so
	# steadying your hip fire and taming your recoil are two separate buys.
	{"key": "grip", "name": "IMPROVED GRIP", "cost": 20, "blurb": "-35% hip-fire spread"},
	{"key": "foregrip", "name": "FRONT GRIP", "cost": 20, "blurb": "-20% kick and recoil climb"},
]

# Armour frames: health against speed/jump. Index 1 (NONE) is the default.
const ARMOR: Array[Dictionary] = [
	{"name": "LIGHT FRAME", "cost": 20, "health": 80.0, "speed": 1.12, "jump": 1.12,
		"blurb": "Fast and high-jumping, thin"},
	{"name": "NONE", "cost": 0, "health": 100.0, "speed": 1.0, "jump": 1.0,
		"blurb": "Standard trooper"},
	{"name": "PLATED", "cost": 25, "health": 130.0, "speed": 0.95, "jump": 0.97,
		"blurb": "Tougher, marginally slower"},
	{"name": "HEAVY PLATE", "cost": 60, "health": 175.0, "speed": 0.85, "jump": 0.88,
		"blurb": "Very tough, heavy and low-jumping"},
]
const DEFAULT_ARMOR := 1

# What a thrown grenade DOES. Grenades are gadgets now (see GRENADE_GADGETS), but
# the projectile (grenade.gd) and smoke still speak in these three verbs.
enum GrenadeType { FRAG, SMOKE, STICKY }

# GADGETS: fitted to a gadget slot (every class has two now). Each is a different
# verb rather than more damage — see Player._use_gadget and the gadget scenes.
## NOTE: GADGETS is indexed by this enum, and the buy row IS the gadget id, so a
## new gadget goes on the END. Inserting one in the middle would renumber every
## saved and preset gadget underneath it.
## A gadget from another universe is usually not a new MECHANISM, it is the same
## verb wearing different words — a bubble shield and a kustom force field are
## both "a barrier that stops incoming fire", and writing three of those would be
## three chances for them to drift apart. So an entry may carry a `"like"` key
## naming the gadget whose behaviour it uses (see gadget_action): the CATALOGUE
## grows, the code that acts on a gadget does not. An entry with no `"like"` is
## its own behaviour, and every one of those has a case in Player._use_gadget.
enum Gadget { NONE, JETPACK, CABLE, SHIELD, ROTARY, TURRET, MORTAR,
	FORCE_PUSH, FORCE_PULL, FORCE_LEAP, FORCE_LIGHTNING, WRIST_ROCKET,
	CLOAK, DASH, GRENADE_FRAG, GRENADE_STICKY, GRENADE_SMOKE, SCAN_DART,
	# Halo
	BUBBLE_SHIELD, ACTIVE_CAMO, THRUSTER_PACK, SENTRY_TURRET, GRAV_LIFT,
	JET_PACK, PLASMA_CANNON, TARGET_DESIGNATOR, TRACKER_DART,
	FRAG_GRENADE_UNSC, PLASMA_GRENADE,
	# Warhammer 40,000 — Astartes
	JUMP_PACK, IRON_HALO, AUSPEX_SCAN, ORBITAL_BOMBARDMENT, ASSAULT_CANNON,
	RED_THIRST, KRAK_GRENADE, MELTA_BOMB,
	# ...Necrons
	TESLA_ARC, PHASE_SHIFT, TRANSLOCATION, CANOPTEK_SPYDER,
	# ...Orks
	WAAAGH, GROT_GUNNER, KUSTOM_FORCE_FIELD, ROKKIT_PACK, STIKKBOMB,
	SMOKE_LAUNCHER }
const GADGETS: Array[Dictionary] = [
	# NONE belongs to every universe: an empty slot is an empty slot.
	{"name": "NONE", "cost": 0, "blurb": "No gadget", "universe": ANY_UNIVERSE},
	{"name": "JETPACK", "cost": 45,
		"blurb": "Hold the gadget button to fly. Fuel burns fast, refills on the ground"},
	{"name": "WRIST CABLE", "cost": 30,
		"blurb": "Grapple within 34 m, reel in and vault on top. 5s between uses"},
	# The barrier is the WOOKIEE's now. Same `royale` opt-in as the heavy guns:
	# class-locked in the shop, still findable on the ground in a mode that has
	# no classes to lock it to.
	{"name": "FRONT SHIELD", "cost": 50, "kit": Kit.WOOKIEE, "royale": true,
		"blurb": "Toggle a barrier that stops incoming fire. Shoot through it, but no aiming"},
	{"name": "ROTARY CANNON", "cost": 75,
		"blurb": "Toggle a spin-up rotary gun. Huge output, but you walk"},
	{"name": "TURRET", "cost": 65,
		"blurb": "Drop an auto-turret that fights for you until it's destroyed"},
	{"name": "MORTAR", "cost": 60,
		"blurb": "Drop a tube, then call salvos from the map screen. 14s between them"},
	# Force powers. They move people rather than damaging them, which is what
	# makes a melee class playable: the saber does the killing, these decide who
	# is standing close enough for it.
	# Marked with "kit" for the same reason the lightsaber is: these belong to a
	# class, so a mode with no classes must never hand one out. See royale_items.
	{"name": "FORCE PUSH", "cost": 45, "kit": Kit.FORCE,
		"blurb": "Throw everyone in front of you back off their feet. 6s"},
	{"name": "FORCE PULL", "cost": 40, "kit": Kit.FORCE,
		"blurb": "Drag the one you are looking at to you, from 34 m. 7s"},
	{"name": "FORCE LEAP", "cost": 35, "kit": Kit.FORCE,
		"blurb": "A Force-assisted bound: high, long, and it closes ground fast. 4s"},
	# The exception to "these move people rather than damaging them", and the only
	# ranged damage the class can buy — which is what it is for: a saber that
	# cannot reach past 3.4 m has no answer at all to someone holding a doorway.
	# It is still not a gun: short of a rifle's range, on a long cooldown, and it
	# arcs to the crowd behind the target rather than rewarding precision.
	{"name": "FORCE LIGHTNING", "cost": 50, "kit": Kit.FORCE,
		"blurb": "HOLD to pour lightning at the nearest enemy in front, chaining to 3 more. 18 m, 4s"},
	# The Mandalorian's third gadget, and the only DAMAGE one it can buy. No
	# "kit" key, exactly like the jetpack and the cable: the kit allow-list is
	# what keeps it out of other classes' hands, and a rocket off the ground
	# works perfectly well for a class-free royale trooper.
	{"name": "WRIST ROCKET", "cost": 55,
		"blurb": "A rocket straight off your wrist: splash, no reload, 7s between shots"},
	# The Trandoshan's two. No "kit" key — the allow-list keeps them theirs, and
	# a cloak or a dash off the ground is fine for a class-free royale trooper.
	{"name": "CLOAK", "cost": 45,
		"blurb": "Vanish for a few seconds. Firing drops it. AI cannot see you cloaked. 9s"},
	{"name": "SPRINT DASH", "cost": 25,
		"blurb": "A quick burst in the way you are moving. 4s"},
	# Grenades are GADGETS now, not a counted consumable — you fit one in a slot
	# and it recharges on a cooldown instead of running out. Each throws its own
	# grenade type (see Player._use_gadget). SMOKE is the Trandoshan's alone, so
	# it carries the "kit" key exactly as the smoke consumable used to.
	{"name": "FRAG GRENADE", "cost": 30,
		"blurb": "Lob a frag: bounces, 2s fuse, heavy splash. 6s between throws"},
	{"name": "STICKY GRENADE", "cost": 35,
		"blurb": "Lob a sticky: clings where it lands, people included, then blows. 6s"},
	{"name": "SMOKE GRENADE", "cost": 20, "kit": Kit.TRANDOSHAN,
		"blurb": "Lob smoke: blinds the area, nothing sees through it (you do, thermal). 7s"},
	# The Clone ARC's recon tool: fire a dart that sticks and PINGS nearby enemies
	# to your whole team for a few seconds, walls or no walls. No "kit" key — a
	# scanner off the ground works for a plain trooper, and the allow-list keeps it
	# ARC-only in the factions.
	{"name": "SCAN DART", "cost": 30,
		"blurb": "A dart that sticks and reveals enemies near it to your team through walls. 12s"},

	# --- HALO ----------------------------------------------------------------
	{"name": "BUBBLE SHIELD", "cost": 50, "universe": Universe.HALO, "like": Gadget.SHIELD,
		"blurb": "Toggle a barrier that stops incoming fire. Shoot through it, but no aiming"},
	{"name": "ACTIVE CAMO", "cost": 45, "universe": Universe.HALO, "like": Gadget.CLOAK,
		"blurb": "Vanish for a few seconds. Firing drops it. AI cannot see you cloaked. 9s"},
	{"name": "THRUSTER PACK", "cost": 25, "universe": Universe.HALO, "like": Gadget.DASH,
		"blurb": "A quick burst in the way you are moving. 4s"},
	{"name": "AUTOSENTRY", "cost": 65, "universe": Universe.HALO, "like": Gadget.TURRET,
		"blurb": "Drop an auto-turret that fights for you until it's destroyed"},
	{"name": "GRAV LIFT", "cost": 35, "universe": Universe.HALO, "like": Gadget.FORCE_LEAP,
		"blurb": "A hard shove upward and forward: high, long, and it closes ground fast. 4s"},
	{"name": "JET PACK", "cost": 45, "universe": Universe.HALO, "like": Gadget.JETPACK,
		"blurb": "Hold the gadget button to fly. Fuel burns fast, refills on the ground"},
	{"name": "PLASMA CANNON", "cost": 75, "universe": Universe.HALO, "like": Gadget.ROTARY,
		"blurb": "Tear a plasma cannon off its mount and carry it. Huge output, but you walk"},
	{"name": "TARGET DESIGNATOR", "cost": 60, "universe": Universe.HALO, "like": Gadget.MORTAR,
		"blurb": "Drop a tube, then call salvos from the map screen. 14s between them"},
	{"name": "TRACKER DART", "cost": 30, "universe": Universe.HALO, "like": Gadget.SCAN_DART,
		"blurb": "A dart that sticks and reveals enemies near it to your team through walls. 12s"},
	{"name": "M9 FRAG GRENADE", "cost": 30, "universe": Universe.HALO, "like": Gadget.GRENADE_FRAG,
		"blurb": "Lob a frag: bounces, 2s fuse, heavy splash. 6s between throws"},
	# The one alias that is genuinely the right mechanic and not just the right
	# word: a plasma grenade sticks to whoever it lands on, which is exactly what
	# the sticky already does.
	{"name": "PLASMA GRENADE", "cost": 35, "universe": Universe.HALO, "like": Gadget.GRENADE_STICKY,
		"blurb": "Lob a plasma stick: clings where it lands, people included, then blows. 6s"},

	# --- WARHAMMER 40,000: Adeptus Astartes ----------------------------------
	{"name": "JUMP PACK", "cost": 45, "universe": Universe.WARHAMMER, "like": Gadget.JETPACK,
		"blurb": "Hold the gadget button to fly. Fuel burns fast, refills on the ground"},
	{"name": "IRON HALO", "cost": 50, "universe": Universe.WARHAMMER, "like": Gadget.SHIELD,
		"blurb": "Toggle a barrier that stops incoming fire. Shoot through it, but no aiming"},
	{"name": "AUSPEX SCAN", "cost": 30, "universe": Universe.WARHAMMER, "like": Gadget.SCAN_DART,
		"blurb": "A scanner that sticks and reveals enemies near it to your squad through walls. 12s"},
	{"name": "ORBITAL BOMBARDMENT", "cost": 60, "universe": Universe.WARHAMMER, "like": Gadget.MORTAR,
		"blurb": "Plant a beacon, then call salvos from the map screen. 14s between them"},
	{"name": "ASSAULT CANNON", "cost": 75, "universe": Universe.WARHAMMER, "like": Gadget.ROTARY,
		"blurb": "Toggle a spin-up rotary cannon. Huge output, but you walk"},
	{"name": "RED THIRST", "cost": 25, "universe": Universe.WARHAMMER, "like": Gadget.DASH,
		"blurb": "A quick burst in the way you are moving. 4s"},
	{"name": "KRAK GRENADE", "cost": 30, "universe": Universe.WARHAMMER, "like": Gadget.GRENADE_FRAG,
		"blurb": "Lob a krak: bounces, 2s fuse, heavy splash. 6s between throws"},
	{"name": "MELTA BOMB", "cost": 35, "universe": Universe.WARHAMMER, "like": Gadget.GRENADE_STICKY,
		"blurb": "Lob a melta bomb: clings where it lands, people included, then blows. 6s"},
	# --- ...Necrons -----------------------------------------------------------
	{"name": "TESLA ARC", "cost": 50, "universe": Universe.WARHAMMER, "like": Gadget.FORCE_LIGHTNING,
		"blurb": "HOLD to pour arc lightning at the nearest enemy in front, chaining to 3 more. 18 m, 4s"},
	{"name": "PHASE SHIFT", "cost": 45, "universe": Universe.WARHAMMER, "like": Gadget.CLOAK,
		"blurb": "Phase out for a few seconds. Firing drops it. AI cannot see you phased. 9s"},
	{"name": "TRANSLOCATION", "cost": 35, "universe": Universe.WARHAMMER, "like": Gadget.FORCE_LEAP,
		"blurb": "A dimensional bound: high, long, and it closes ground fast. 4s"},
	{"name": "CANOPTEK SPYDER", "cost": 65, "universe": Universe.WARHAMMER, "like": Gadget.TURRET,
		"blurb": "Drop a construct that fights for you until it's destroyed"},
	# --- ...Orks --------------------------------------------------------------
	{"name": "WAAAGH!", "cost": 25, "universe": Universe.WARHAMMER, "like": Gadget.DASH,
		"blurb": "A roaring charge in the way you are moving. 4s"},
	{"name": "GROT GUNNER", "cost": 65, "universe": Universe.WARHAMMER, "like": Gadget.TURRET,
		"blurb": "Drop a grot on a gun that fights for you until it's destroyed"},
	{"name": "KUSTOM FORCE FIELD", "cost": 50, "universe": Universe.WARHAMMER, "like": Gadget.SHIELD,
		"blurb": "Toggle a barrier that stops incoming fire. Shoot through it, but no aiming"},
	{"name": "ROKKIT PACK", "cost": 45, "universe": Universe.WARHAMMER, "like": Gadget.JETPACK,
		"blurb": "Hold the gadget button to fly. Fuel burns fast, refills on the ground"},
	{"name": "STIKKBOMB", "cost": 25, "universe": Universe.WARHAMMER, "like": Gadget.GRENADE_FRAG,
		"blurb": "Lob a stikkbomb: bounces, 2s fuse, heavy splash. 6s between throws"},
	{"name": "SMOKE LAUNCHER", "cost": 20, "universe": Universe.WARHAMMER, "like": Gadget.GRENADE_SMOKE,
		"blurb": "Lob smoke: blinds the area, nothing sees through it. 7s"},
]


## What a gadget actually DOES: its own id, or the base gadget it is an alias of.
## Everything that acts on a gadget — Player._use_gadget, Bot's "do I own a
## turret", the HUD readout — asks this rather than the raw id, which is what
## lets a bubble shield and a kustom force field be one mechanism and two rows.
static func gadget_action(id: int) -> int:
	if id < 0 or id >= GADGETS.size():
		return Gadget.NONE
	return int(GADGETS[id].get("like", id))


## The cooldown of whatever a gadget id resolves to. Aliases never state their
## own — a plasma grenade recharges exactly as fast as the sticky it is.
static func cooldown_of(id: int) -> float:
	return float(GADGET_COOLDOWNS.get(gadget_action(id), 0.0))

## What a gadget costs to use again, in seconds. Only the force powers are on a
## cooldown of their own — everything else is a toggle, a placement, or (the
## cable) times itself.
const GADGET_COOLDOWNS := {
	Gadget.FORCE_PUSH: 6.0, Gadget.FORCE_PULL: 7.0, Gadget.FORCE_LEAP: 4.0,
	# Short, because the channel itself is now the limit on how often it lands:
	# two seconds of holding still is the cost, and a nine-second lock-out on top
	# of that made the class's only ranged answer something you had once a fight.
	Gadget.FORCE_LIGHTNING: 4.0,
	# The wrist rocket is on a cooldown for the same reason the force powers are:
	# it is a gadget, not a gun, and the whole balance of it is how often it
	# arrives rather than what it does when it lands.
	Gadget.WRIST_ROCKET: 7.0,
	Gadget.CLOAK: 9.0,
	Gadget.DASH: 4.0,
	# Grenades recharge instead of running out — the cooldown IS the ammo now.
	Gadget.GRENADE_FRAG: 6.0,
	Gadget.GRENADE_STICKY: 6.0,
	Gadget.GRENADE_SMOKE: 7.0,
	Gadget.SCAN_DART: 12.0,
}

## The GrenadeType a grenade gadget throws, or -1 if the gadget is not a grenade.
## One place both Player and Bot read, so the mapping never drifts.
const GRENADE_GADGETS := {
	Gadget.GRENADE_FRAG: GrenadeType.FRAG,
	Gadget.GRENADE_STICKY: GrenadeType.STICKY,
	Gadget.GRENADE_SMOKE: GrenadeType.SMOKE,
}


const KITS: Array[Dictionary] = [
	{
		"name": "CLONE TROOPER",
		"blurb": "Republic line trooper. Every rifle worth carrying and every deployable",
		"gadgets": [Gadget.NONE, Gadget.ROTARY, Gadget.TURRET, Gadget.MORTAR,
			Gadget.GRENADE_FRAG, Gadget.GRENADE_STICKY],
		"gadget_slots": 2,
		"secondary_mods": [SecondaryMod.NONE, SecondaryMod.SCOPE, SecondaryMod.COOLING],
		"armor": [0, 1, 2, 3],
		"default_armor": 1,
		"starter": Weapon.Class.SOLDIER,
		"style": CharacterModel.Style.CLONE,
	},
	{
		"name": "MANDALORIAN",
		"blurb": "Flies, grapples, fires wrist rockets, and the only one who dual-wields",
		"gadgets": [Gadget.NONE, Gadget.JETPACK, Gadget.CABLE, Gadget.WRIST_ROCKET,
			Gadget.GRENADE_FRAG, Gadget.GRENADE_STICKY],
		"gadget_slots": 2,
		"secondary_mods": [SecondaryMod.NONE, SecondaryMod.SCOPE, SecondaryMod.COOLING,
			SecondaryMod.DUAL],
		# No heavy plate: the kit's whole identity is moving, and the jetpack
		# already pays for its lift in fuel rather than in weight.
		"armor": [0, 1, 2],
		"default_armor": 0,   # LIGHT FRAME — "lighter armour by default"
		"style": CharacterModel.Style.MANDALORIAN,
	},
	{
		"name": "FORCE ADEPT",
		"blurb": "Lightsaber or any gun, plus a Force power. Tough, fast, dashes and double jumps",
		# DASH is offered as an explicit gadget as well as the intrinsic empty-slot
		# dash: fitting it lets the adept keep the dash in one slot while spending
		# the other on a Force power, rather than choosing between a power and the
		# dash that only appears when a slot is left empty.
		"gadgets": [Gadget.NONE, Gadget.FORCE_PUSH, Gadget.FORCE_PULL, Gadget.FORCE_LEAP,
			Gadget.FORCE_LIGHTNING, Gadget.DASH, Gadget.GRENADE_FRAG, Gadget.GRENADE_STICKY],
		"gadget_slots": 2,
		"secondary_mods": [SecondaryMod.NONE, SecondaryMod.SCOPE, SecondaryMod.COOLING],
		"armor": [0, 1],
		"default_armor": 0,
		# No `primaries` list, so the adept may carry ANY ordinary gun — the saber
		# is reached through its own "kit" key (see allows). The Force gadget on
		# the gadget button and the dash/double-jump are the class, not the blade,
		# so a gun-toting Jedi keeps all of them; only the GUARD needs the saber
		# in hand (guard_up checks is_melee). It still opens on the saber, which is
		# the class fantasy.
		"default_primary": Weapon.Class.SABER,
		# A melee class has to be able to reach the fight, so it is quick on foot
		# and can dash. Light frame on top of this puts it at 1.12 * 1.2.
		"speed": 1.2,
		# ...and it has to SURVIVE the crossing. Everyone else shoots on the way in
		# while the adept can only close, and the guard is not cover: it pays a pool
		# per point stopped and breaks. The frame is multiplied rather than replaced
		# for the same reason speed is, so the two armours it may wear still differ.
		"health": 1.25,
		"dash": true,
		"style": CharacterModel.Style.JEDI,
	},
	{
		"name": "WOOKIEE",
		"blurb": "Heavy weapons and a bowcaster. Slow, enormously tough, and the only one with a barrier",
		# One gadget, and it is the barrier — taken off the clone, because a
		# shield in front of a rifleman is cover for a fire team, while a shield
		# in front of a slow heavy is the only way that heavy crosses open ground.
		"gadgets": [Gadget.NONE, Gadget.SHIELD, Gadget.GRENADE_FRAG, Gadget.GRENADE_STICKY],
		"gadget_slots": 2,
		# NO SCOPE on the sidearm. A scope means zero spread while aimed
		# (Weapon.current_spread_deg), which on a PELLET weapon collapses all
		# three quarrels onto one point — 78 damage at any range, for 20 tokens.
		"secondary_mods": [SecondaryMod.NONE, SecondaryMod.COOLING],
		# Plate or nothing: there is no light-framed Wookiee.
		"armor": [2, 3],
		"default_armor": 2,
		# The heavy weapons are the class, and nothing else may carry them. Note
		# there is no "none" option here: a Wookiee that has not bought a heavy
		# gun is just a slow trooper, so the cheaper of the two is the floor.
		"primaries": [Weapon.Class.HMG, Weapon.Class.RPG],
		"secondaries": [Weapon.Class.BOWCASTER],
		# Carrying a squad weapon costs you the legs, and being built like this
		# pays for it: 130-175 of frame becomes 169-227. The slowest thing on the
		# map and the hardest to shift off a doorway.
		"speed": 0.9,
		"health": 1.3,
		"style": CharacterModel.Style.WOOKIEE,
	},
	{
		"name": "TRANDOSHAN",
		"blurb": "Reptilian hunter. Thermal sight, smoke, and can vanish or dash. Quick and lightly armoured",
		# CLOAK to break contact and DASH to reposition — no deployables, no
		# barrier: the class is about being where the enemy is not.
		"gadgets": [Gadget.NONE, Gadget.CLOAK, Gadget.DASH,
			Gadget.GRENADE_FRAG, Gadget.GRENADE_STICKY, Gadget.GRENADE_SMOKE],
		"gadget_slots": 2,
		"secondary_mods": [SecondaryMod.NONE, SecondaryMod.SCOPE, SecondaryMod.COOLING],
		"armor": [0, 1, 2],
		"default_armor": 0,
		# SMOKE and the THERMAL HOLO carry their own "kit" key, so the Trandoshan
		# reaches them (and every ordinary grenade and sight) with no list of its
		# own — the thermal sight and the smoke are one kit on purpose.
		# A focused armoury: a rifle, a marksman semi, a bullet-hose SMG, and a
		# sniper. Precise and mobile rather than broad.
		"primaries": [Weapon.Class.SOLDIER, Weapon.Class.SEMI, Weapon.Class.SMG,
			Weapon.Class.SNIPER],
		# Fast and thin: it fights by not being shot at, so it moves.
		"speed": 1.15,
		"health": 0.95,
		"style": CharacterModel.Style.TRANDOSHAN,
	},

	# =========================================================================
	# HALO
	# =========================================================================
	# The UNSC/Covenant split is done with `primaries`/`secondaries` lists rather
	# than with "kit" keys, because a faction is not one class's private weapon:
	# every UNSC class may reach every UNSC gun, and none of them may touch
	# plasma. That is what an allow-list is for.
	{
		"name": "SPARTAN",
		"blurb": "MJOLNIR armour: every UNSC weapon, a shield bubble, and the health to walk in",
		"universe": Universe.HALO,
		"gadgets": [Gadget.NONE, Gadget.BUBBLE_SHIELD, Gadget.SENTRY_TURRET,
			Gadget.JET_PACK, Gadget.THRUSTER_PACK, Gadget.FRAG_GRENADE_UNSC,
			Gadget.PLASMA_GRENADE],
		"gadget_slots": 2,
		"secondary_mods": [SecondaryMod.NONE, SecondaryMod.SCOPE, SecondaryMod.COOLING],
		"armor": [1, 2, 3],
		"default_armor": 2,
		"primaries": [Weapon.Class.MA5B, Weapon.Class.BR55, Weapon.Class.M7_SMG,
			Weapon.Class.M90_SHOTGUN, Weapon.Class.M392_DMR, Weapon.Class.SRS99,
			Weapon.Class.M247_HMG, Weapon.Class.SPNKR, Weapon.Class.SPARTAN_LASER],
		"secondaries": [Weapon.Class.M6D],
		"starter": Weapon.Class.MA5B,
		"health": 1.20,
		"style": CharacterModel.Style.SPARTAN,
	},
	{
		"name": "ODST",
		"blurb": "Orbital drop trooper. Quiet, quick, camouflaged — and thin where the Spartan is not",
		"universe": Universe.HALO,
		"gadgets": [Gadget.NONE, Gadget.ACTIVE_CAMO, Gadget.THRUSTER_PACK,
			Gadget.TRACKER_DART, Gadget.TARGET_DESIGNATOR, Gadget.FRAG_GRENADE_UNSC],
		"gadget_slots": 2,
		"secondary_mods": [SecondaryMod.NONE, SecondaryMod.SCOPE, SecondaryMod.COOLING],
		"armor": [0, 1, 2],
		"default_armor": 0,
		"primaries": [Weapon.Class.M7_SMG, Weapon.Class.BR55, Weapon.Class.MA5B,
			Weapon.Class.M392_DMR, Weapon.Class.SRS99],
		"secondaries": [Weapon.Class.M6D],
		"starter": Weapon.Class.M7_SMG,
		"speed": 1.12,
		"health": 0.95,
		"style": CharacterModel.Style.ODST,
	},
	{
		"name": "SANGHEILI",
		"blurb": "Covenant Elite. Plasma, camouflage, and the sword you close the distance with",
		"universe": Universe.HALO,
		"gadgets": [Gadget.NONE, Gadget.ACTIVE_CAMO, Gadget.THRUSTER_PACK,
			Gadget.GRAV_LIFT, Gadget.PLASMA_CANNON, Gadget.PLASMA_GRENADE],
		"gadget_slots": 2,
		"secondary_mods": [SecondaryMod.NONE, SecondaryMod.SCOPE, SecondaryMod.COOLING],
		"armor": [0, 1, 2],
		"default_armor": 1,
		"primaries": [Weapon.Class.PLASMA_RIFLE, Weapon.Class.COV_CARBINE,
			Weapon.Class.NEEDLER, Weapon.Class.BEAM_RIFLE, Weapon.Class.ENERGY_SWORD,
			Weapon.Class.FUEL_ROD],
		"secondaries": [Weapon.Class.PLASMA_PISTOL, Weapon.Class.MAULER],
		"starter": Weapon.Class.PLASMA_RIFLE,
		# The energy sword is a real option for this class, so it needs to be able
		# to cross open ground under fire — the same argument the Force adept won.
		"speed": 1.08,
		"health": 1.15,
		"dash": true,
		"style": CharacterModel.Style.ELITE,
	},
	{
		"name": "UNGGOY",
		"blurb": "A Grunt. Small, fast, barely armoured, and carrying something far too big for it",
		"universe": Universe.HALO,
		"gadgets": [Gadget.NONE, Gadget.PLASMA_GRENADE, Gadget.GRAV_LIFT,
			Gadget.THRUSTER_PACK],
		"gadget_slots": 2,
		"secondary_mods": [SecondaryMod.NONE, SecondaryMod.COOLING],
		"armor": [0, 1],
		"default_armor": 0,
		"primaries": [Weapon.Class.NEEDLER, Weapon.Class.PLASMA_RIFLE,
			Weapon.Class.FUEL_ROD],
		"secondaries": [Weapon.Class.PLASMA_PISTOL],
		"starter": Weapon.Class.NEEDLER,
		# The trade the whole class is: it dies to almost anything, and it is the
		# only Covenant body that can carry a fuel rod and still outrun a Spartan.
		"speed": 1.18,
		"health": 0.70,
		"style": CharacterModel.Style.GRUNT,
	},
	{
		"name": "JIRALHANAE",
		"blurb": "A Brute. The widest thing on the field, a gravity hammer, and no interest in cover",
		"universe": Universe.HALO,
		"gadgets": [Gadget.NONE, Gadget.BUBBLE_SHIELD, Gadget.PLASMA_CANNON,
			Gadget.PLASMA_GRENADE],
		"gadget_slots": 2,
		"secondary_mods": [SecondaryMod.NONE, SecondaryMod.COOLING],
		"armor": [2, 3],
		"default_armor": 2,
		"primaries": [Weapon.Class.BRUTE_SHOT, Weapon.Class.GRAV_HAMMER,
			Weapon.Class.PLASMA_RIFLE, Weapon.Class.FUEL_ROD],
		"secondaries": [Weapon.Class.MAULER],
		"starter": Weapon.Class.BRUTE_SHOT,
		"speed": 0.92,
		"health": 1.35,
		"style": CharacterModel.Style.BRUTE,
	},

	# =========================================================================
	# WARHAMMER 40,000
	# =========================================================================
	# Four sides, not two, which is why this universe fills all four team slots
	# where the other two wrap. The two chapters share an armoury and differ in
	# what they do with it: the Ultramarine holds a line, the Blood Angel closes.
	{
		"name": "ULTRAMARINE",
		"blurb": "Codex Astartes: bolters, plasma, and the discipline to hold a firing line",
		"universe": Universe.WARHAMMER,
		"gadgets": [Gadget.NONE, Gadget.IRON_HALO, Gadget.AUSPEX_SCAN,
			Gadget.ORBITAL_BOMBARDMENT, Gadget.ASSAULT_CANNON, Gadget.KRAK_GRENADE,
			Gadget.MELTA_BOMB],
		"gadget_slots": 2,
		"secondary_mods": [SecondaryMod.NONE, SecondaryMod.SCOPE, SecondaryMod.COOLING],
		# Power armour or terminator plate. There is no lightly-armoured Astartes.
		"armor": [2, 3],
		"default_armor": 2,
		"primaries": [Weapon.Class.BOLTER, Weapon.Class.HEAVY_BOLTER,
			Weapon.Class.STALKER_BOLT, Weapon.Class.PLASMA_GUN, Weapon.Class.MELTAGUN,
			Weapon.Class.FLAMER, Weapon.Class.GRENADE_LAUNCHER,
			Weapon.Class.CHAINSWORD, Weapon.Class.POWER_SWORD],
		"secondaries": [Weapon.Class.BOLT_PISTOL, Weapon.Class.PLASMA_PISTOL_40K],
		"starter": Weapon.Class.BOLTER,
		"speed": 0.95,
		"health": 1.45,
		"style": CharacterModel.Style.ULTRAMARINE,
	},
	{
		"name": "BLOOD ANGEL",
		"blurb": "Jump pack and chainsword. It is built to arrive, not to shoot at you from over there",
		"universe": Universe.WARHAMMER,
		"gadgets": [Gadget.NONE, Gadget.JUMP_PACK, Gadget.RED_THIRST,
			Gadget.IRON_HALO, Gadget.KRAK_GRENADE, Gadget.MELTA_BOMB],
		"gadget_slots": 2,
		"secondary_mods": [SecondaryMod.NONE, SecondaryMod.SCOPE, SecondaryMod.COOLING],
		"armor": [1, 2, 3],
		"default_armor": 2,
		"primaries": [Weapon.Class.CHAINSWORD, Weapon.Class.POWER_SWORD,
			Weapon.Class.THUNDER_HAMMER, Weapon.Class.BOLTER, Weapon.Class.FLAMER,
			Weapon.Class.MELTAGUN],
		"secondaries": [Weapon.Class.BOLT_PISTOL, Weapon.Class.PLASMA_PISTOL_40K],
		"default_primary": Weapon.Class.CHAINSWORD,
		"starter": Weapon.Class.CHAINSWORD,
		"speed": 1.05,
		"health": 1.40,
		"dash": true,
		"style": CharacterModel.Style.BLOOD_ANGEL,
	},
	{
		"name": "NECRON",
		"blurb": "Gauss, tesla and a warscythe. Slow, relentless, and it does not flinch",
		"universe": Universe.WARHAMMER,
		"gadgets": [Gadget.NONE, Gadget.PHASE_SHIFT, Gadget.TESLA_ARC,
			Gadget.TRANSLOCATION, Gadget.CANOPTEK_SPYDER],
		"gadget_slots": 2,
		"secondary_mods": [SecondaryMod.NONE, SecondaryMod.SCOPE, SecondaryMod.COOLING],
		"armor": [1, 2, 3],
		"default_armor": 2,
		"primaries": [Weapon.Class.GAUSS_FLAYER, Weapon.Class.GAUSS_BLASTER,
			Weapon.Class.TESLA_CARBINE, Weapon.Class.SYNAPTIC_DISINTEGRATOR,
			Weapon.Class.HEAT_RAY, Weapon.Class.TRANSDIMENSIONAL_BEAMER,
			Weapon.Class.WARSCYTHE, Weapon.Class.STAFF_OF_LIGHT],
		"secondaries": [Weapon.Class.GAUSS_PISTOL],
		"starter": Weapon.Class.GAUSS_FLAYER,
		# No grenades at all: a Necron reaches out with tesla or it walks at you.
		"speed": 0.92,
		"health": 1.30,
		"style": CharacterModel.Style.NECRON,
	},
	{
		"name": "ORK",
		"blurb": "Dakka. None of it lands, all of it hurts, and the choppa always does",
		"universe": Universe.WARHAMMER,
		"gadgets": [Gadget.NONE, Gadget.WAAAGH, Gadget.GROT_GUNNER,
			Gadget.KUSTOM_FORCE_FIELD, Gadget.ROKKIT_PACK, Gadget.STIKKBOMB,
			Gadget.SMOKE_LAUNCHER],
		"gadget_slots": 2,
		"secondary_mods": [SecondaryMod.NONE, SecondaryMod.COOLING],
		"armor": [1, 2, 3],
		"default_armor": 2,
		"primaries": [Weapon.Class.SHOOTA, Weapon.Class.BIG_SHOOTA,
			Weapon.Class.BURNA, Weapon.Class.MEGA_BLASTA, Weapon.Class.ROKKIT_LAUNCHA,
			Weapon.Class.CHOPPA, Weapon.Class.POWER_KLAW],
		"secondaries": [Weapon.Class.SLUGGA],
		"starter": Weapon.Class.SHOOTA,
		"speed": 1.05,
		"health": 1.25,
		"style": CharacterModel.Style.ORK,
	},
]


# AI squadmates: you buy a headcount and a skill tier, and pay the tier's price
# for every one of them (4 veterans cost 4 x VETERAN). Skill is what actually
# separates them — aim, reaction, engagement range and the gun they carry —
# see Bot.SKILLS.
const SQUAD_MAX := 4
const SQUAD_SKILLS: Array[Dictionary] = [
	{"name": "RECRUIT", "cost": 20, "blurb": "Poor aim, slow to react, short sight"},
	{"name": "REGULAR", "cost": 35, "blurb": "Steady aim, average reactions"},
	{"name": "VETERAN", "cost": 55, "blurb": "Sharp aim, quick, pushes further out"},
	{"name": "ELITE", "cost": 80, "blurb": "Deadly aim, near-instant, long sight"},
]


## The buy screen is one row per line, in this order. SIGHT/COOLING/GRIP sit
## directly under WEAPON because they now fit the PRIMARY only; the sidearm's
## single slot sits under SECONDARY for the same reason.
## COOLING, GRIP, FOREGRIP are the primary bolt-ons and MUST stay contiguous and
## in the same order as UPGRADES — _upgrade_index maps them by `row - Row.COOLING`.
enum Row {
	KIT,
	WEAPON, SIGHT, COOLING, GRIP, FOREGRIP,
	SECONDARY, SECONDARY_MOD,
	GADGET, GADGET2, ARMOR, SQUAD, SQUAD_SKILL,
}

## HOW THE BUY SCREEN IS GROUPED, and — since the rework — how it is DRIVEN.
##
## The old screen walked one flat list of rows: up/down moved a cursor through
## every line on the screen and left/right changed whatever it was sitting on.
## That is why a stray nudge of the stick on the frame you died could silently
## re-roll your class, which is the worst possible thing for it to change: the
## kit resets the whole build.
##
## Now the selector moves between BOXES, and a box has to be OPENED before any
## line inside it can be touched. Two consequences worth stating: the grouping
## is input, not decoration, so it lives here with the catalogue rather than in
## the screen that draws it; and SPAWN is a box of its own (added by the screen,
## not listed here) so that deploying is a deliberate press on a target rather
## than a button that works from anywhere.
const BUY_BOXES: Array[Dictionary] = [
	# CLASS comes first because it decides what every box under it may hold.
	{"name": "CLASS", "rows": [Row.KIT]},
	{"name": "PRIMARY", "rows": [Row.WEAPON, Row.SIGHT, Row.COOLING, Row.GRIP, Row.FOREGRIP]},
	{"name": "SIDEARM", "rows": [Row.SECONDARY, Row.SECONDARY_MOD]},
	# Two gadget slots for every class now — grenades live here too, as gadgets.
	{"name": "GADGETS", "rows": [Row.GADGET, Row.GADGET2]},
	{"name": "ARMOUR", "rows": [Row.ARMOR]},
	{"name": "AI SQUAD", "rows": [Row.SQUAD, Row.SQUAD_SKILL]},
]


var kit := Kit.CLONE   # index into KITS; picks what the rest of this may be
var weapon := 0        # index into WEAPONS (NO_PRIMARY = sidearm only)
## An explicit primary Weapon.Class that overrides the WEAPONS[weapon] lookup,
## or -1 to use that lookup. This is how a FIXED faction preset (Conquest) can
## deploy a gun the ORDINARY shop does not sell — the wrist cannon — without
## adding it to WEAPONS and shifting every index the buy screen and BOT_BUILDS
## rely on. Only faction builds set it; the buy screen never touches it.
var primary_override := -1
var secondary := 0     # index into SECONDARIES
var secondary_mod := SecondaryMod.NONE
var gadget := 0        # index into GADGETS, slot 0, on the GADGET 1 control
## The second gadget slot, every class has one now: it is driven by the GADGET 2
## control (keyboard G, pad LB by default), an ordinary rebindable binding like
## slot 0. Grenades are gadgets, so this is also where a grenade goes.
var gadget2 := 0
## Primary-only upgrades. The sidearm has its own slot and ignores these.
var sight := Sight.NONE
var cooling := false
var grip := false
var foregrip := false
var armor := DEFAULT_ARMOR  # index into ARMOR
var squad := 0        # how many AI squadmates
var squad_skill := 1  # index into SQUAD_SKILLS, paid per squadmate
## Which procedural body the character wears (a CharacterModel.Style), or -1 to
## derive it from the kit. Faction (Conquest) builds set it explicitly, because a
## Magna Guard is a FORCE kit but must look like a droid, not a Jedi.
var style := -1


# Ready-made builds the AI deploy with, so a firefight has snipers, gunners and
# engineers in it rather than a dozen identical riflemen. Each one is spent out
# of the same BUDGET a player gets — they are legal loadouts, not cheats — and
# each is checked against it by the bot_builds_are_legal test.
## NOTE: `weapon` / `secondary` are indices into WEAPONS / SECONDARIES, so
## inserting a gun into either table shifts every preset below it. Adding guns
## means re-checking these numbers, which the bot_builds_are_legal test only
## catches when the shift also breaks the budget.
## A preset with no `kit` is a CLONE TROOPER, which is what all the originals
## are — the kit only has to be named when it is not the default.
const BOT_BUILDS: Array[Dictionary] = [
	{"name": "RIFLEMAN", "weapon": 2, "secondary": 0, "sight": Sight.HOLO,
		"armor": 2, "gadget2": Gadget.GRENADE_FRAG},                   # 45+20+25+30
	{"name": "MARKSMAN", "weapon": 10, "secondary": 0, "sight": Sight.SCOPE,
		"armor": 0, "grip": true},                                     # 85+25+20+20
	# Was the T-21 HMG, which is a Wookiee weapon now. The Z-6 is what a clone
	# suppresses with, and the heavy plate and vanes are what the role actually
	# was — a body that stands still and keeps firing.
	{"name": "GUNNER", "weapon": 7, "secondary": 0, "sight": Sight.NONE,
		"armor": 3, "cooling": true},                                  # 70+60+20
	{"name": "ENGINEER", "weapon": 2, "secondary": 3, "sight": Sight.HOLO,
		"gadget": Gadget.TURRET, "armor": 1},                          # 45+35+20+65
	# SCOUT and SKIRMISHER carry the wrist cable, which is the Mandalorian's, so
	# they ARE Mandalorians — the kit_rules test caught them the moment the
	# gadget moved and they would otherwise have deployed illegal builds.
	{"name": "SCOUT", "kit": Kit.MANDALORIAN, "weapon": 5, "secondary": 2,
		"sight": Sight.HOLO,
		"gadget": Gadget.CABLE, "armor": 0},                           # 55+20+20+30
	{"name": "GRENADIER", "weapon": 3, "secondary": 0, "sight": Sight.HOLO,
		"armor": 2, "gadget2": Gadget.GRENADE_FRAG},                   # 50+20+25+30
	# SHOCK used to carry the front shield. That is the Wookiee's now, so it
	# leans on the rotary instead — same job (walk at you behind something that
	# does not care), different tool.
	{"name": "SHOCK", "weapon": 7, "secondary": 0, "sight": Sight.NONE,
		"gadget": Gadget.ROTARY, "armor": 2},                          # 70+75+25
	# New guns get presets of their own, so the AI actually field them.
	{"name": "BREACHER", "weapon": 6, "secondary": 1, "sight": Sight.NONE,
		"armor": 2, "gadget2": Gadget.GRENADE_STICKY},                 # 60+15+25+35
	{"name": "SKIRMISHER", "kit": Kit.MANDALORIAN, "weapon": 1, "secondary": 2,
		"sight": Sight.HOLO,
		"armor": 0, "gadget": Gadget.CABLE},                           # 40+20+20+30
	{"name": "DESIGNATOR", "weapon": 8, "secondary": 0, "sight": Sight.NONE,
		"armor": 1, "gadget": Gadget.MORTAR},                          # 75+60
	# The other two classes field presets of their own, so a match actually has
	# Mandalorians and Force adepts in it rather than three flavours of trooper.
	# Both are legal for their kit: check `allows` before changing either.
	{"name": "BOUNTY HUNTER", "kit": Kit.MANDALORIAN, "weapon": 4, "secondary": 1,
		"sight": Sight.HOLO, "armor": 0, "gadget": Gadget.CABLE,
		"gadget2": Gadget.JETPACK},                                    # 50+15+20+20+30+45
	# Fields the wrist rocket, so the AI actually throw one at you.
	{"name": "DEATH WATCH", "kit": Kit.MANDALORIAN, "weapon": 1, "secondary": 0,
		"sight": Sight.HOLO, "armor": 1, "gadget": Gadget.WRIST_ROCKET,
		"gadget2": Gadget.JETPACK},                                    # 40+20+55+45
	{"name": "DUELLIST", "kit": Kit.FORCE, "weapon": 12, "secondary": 0,
		"sight": Sight.NONE, "armor": 0, "gadget": Gadget.FORCE_PUSH,
		"gadget2": Gadget.GRENADE_FRAG},                               # 55+20+45+30
	{"name": "ACOLYTE", "kit": Kit.FORCE, "weapon": 12, "secondary": 0,
		"sight": Sight.NONE, "armor": 0, "gadget": Gadget.FORCE_LIGHTNING},  # 55+20+50
	# A Force adept who shoots: a rifle instead of the saber, keeping the pull to
	# drag someone into the open. Fields the new "guns AND powers" build.
	{"name": "WARDEN", "kit": Kit.FORCE, "weapon": 2, "secondary": 0,
		"sight": Sight.HOLO, "armor": 0, "gadget": Gadget.FORCE_PULL,
		"gadget2": Gadget.GRENADE_FRAG},                               # 45+20+20+40+30
	# The Trandoshan fields both of its ideas: a cloaking sniper and a
	# smoke-and-dash rusher. Both legal for the kit; the kit_rules test checks it.
	{"name": "STALKER", "kit": Kit.TRANDOSHAN, "weapon": 10, "secondary": 0,
		"sight": Sight.THERMAL, "armor": 0, "gadget": Gadget.CLOAK},    # 85+30+20+45
	{"name": "SLAVER", "kit": Kit.TRANDOSHAN, "weapon": 1, "secondary": 2,
		"sight": Sight.THERMAL, "armor": 1, "gadget": Gadget.DASH,
		"gadget2": Gadget.GRENADE_SMOKE},                              # 40+20+30+20
	# The Wookiee fields both of its guns, because they play nothing alike: one
	# holds a lane behind the barrier, the other deletes whatever is behind cover.
	# `secondary` 5 is the bowcaster, which is the only sidearm either may hold —
	# get that index wrong and the kit_rules test says so.
	{"name": "BULWARK", "kit": Kit.WOOKIEE, "weapon": 9, "secondary": 5,
		"sight": Sight.NONE, "armor": 2, "gadget": Gadget.SHIELD},     # 80+25+50
	{"name": "DEMOLISHER", "kit": Kit.WOOKIEE, "weapon": 11, "secondary": 5,
		"sight": Sight.NONE, "armor": 3, "gadget2": Gadget.GRENADE_FRAG},  # 110+60+30

	# =========================================================================
	# The other universes' AI. Which universe a preset belongs to is derived from
	# its KIT (see universe_builds), so there is no separate list to keep in step
	# — a preset naming an Ork class is an Ork preset by construction.
	#
	# These name their gun by CLASS (`primary`/`sidearm`), not by index. The Star
	# Wars presets above predate that and still use raw indices, which is exactly
	# the fragility the named form exists to stop: WEAPONS is forty rows longer
	# than it was and every one of those numbers had to be re-counted by hand.
	# =========================================================================

	# --- HALO: UNSC ----------------------------------------------------------
	{"name": "SPARTAN RIFLEMAN", "kit": Kit.SPARTAN, "primary": Weapon.Class.MA5B,
		"sidearm": Weapon.Class.M6D, "sight": Sight.RED_DOT, "armor": 2,
		"gadget2": Gadget.FRAG_GRENADE_UNSC},                          # 45+25+30
	{"name": "BR MARKSMAN", "kit": Kit.SPARTAN, "primary": Weapon.Class.BR55,
		"sidearm": Weapon.Class.M6D, "sight": Sight.HOLO, "armor": 2,
		"grip": true},                                                 # 55+20+25+20
	{"name": "HEAVY GUNNER", "kit": Kit.SPARTAN, "primary": Weapon.Class.M247_HMG,
		"sidearm": Weapon.Class.M6D, "sight": Sight.NONE, "armor": 3,
		"cooling": true},                                              # 80+60+20
	{"name": "SPARTAN BREACHER", "kit": Kit.SPARTAN, "primary": Weapon.Class.M90_SHOTGUN,
		"sidearm": Weapon.Class.M6D, "sight": Sight.NONE, "armor": 2,
		"gadget": Gadget.BUBBLE_SHIELD},                               # 60+25+50
	{"name": "ODST SCOUT", "kit": Kit.ODST, "primary": Weapon.Class.M7_SMG,
		"sidearm": Weapon.Class.M6D, "sight": Sight.HOLO, "armor": 0,
		"gadget": Gadget.ACTIVE_CAMO},                                 # 40+20+20+45
	{"name": "ODST SNIPER", "kit": Kit.ODST, "primary": Weapon.Class.SRS99,
		"sidearm": Weapon.Class.M6D, "sight": Sight.SCOPE, "armor": 0,
		"grip": true},                                                 # 85+25+20+20
	# --- HALO: Covenant -------------------------------------------------------
	{"name": "ELITE MINOR", "kit": Kit.SANGHEILI, "primary": Weapon.Class.PLASMA_RIFLE,
		"sidearm": Weapon.Class.PLASMA_PISTOL, "sight": Sight.HOLO, "armor": 1,
		"gadget2": Gadget.PLASMA_GRENADE},                             # 45+20+35
	{"name": "ELITE RANGER", "kit": Kit.SANGHEILI, "primary": Weapon.Class.COV_CARBINE,
		"sidearm": Weapon.Class.PLASMA_PISTOL, "sight": Sight.SCOPE, "armor": 2,
		"gadget": Gadget.THRUSTER_PACK},                               # 55+25+25+25
	{"name": "ELITE ZEALOT", "kit": Kit.SANGHEILI, "primary": Weapon.Class.ENERGY_SWORD,
		"sidearm": Weapon.Class.PLASMA_PISTOL, "sight": Sight.NONE, "armor": 2,
		"gadget": Gadget.ACTIVE_CAMO, "gadget2": Gadget.PLASMA_GRENADE},  # 60+25+45+35
	{"name": "GRUNT HEAVY", "kit": Kit.UNGGOY, "primary": Weapon.Class.FUEL_ROD,
		"sidearm": Weapon.Class.PLASMA_PISTOL, "sight": Sight.NONE, "armor": 0,
		"gadget2": Gadget.PLASMA_GRENADE},                             # 105+20+35
	{"name": "BRUTE CHIEFTAIN", "kit": Kit.JIRALHANAE, "primary": Weapon.Class.GRAV_HAMMER,
		"sidearm": Weapon.Class.MAULER, "sight": Sight.NONE, "armor": 2,
		"gadget": Gadget.BUBBLE_SHIELD},                               # 70+30+25+50
	{"name": "BRUTE GRENADIER", "kit": Kit.JIRALHANAE, "primary": Weapon.Class.BRUTE_SHOT,
		"sidearm": Weapon.Class.MAULER, "sight": Sight.NONE, "armor": 3,
		"gadget2": Gadget.PLASMA_GRENADE},                             # 70+30+60+35

	# --- WARHAMMER: Astartes --------------------------------------------------
	{"name": "TACTICAL MARINE", "kit": Kit.ULTRAMARINE, "primary": Weapon.Class.BOLTER,
		"sidearm": Weapon.Class.BOLT_PISTOL, "sight": Sight.RED_DOT, "armor": 2,
		"gadget2": Gadget.KRAK_GRENADE},                               # 50+15+25+30
	{"name": "DEVASTATOR", "kit": Kit.ULTRAMARINE, "primary": Weapon.Class.HEAVY_BOLTER,
		"sidearm": Weapon.Class.BOLT_PISTOL, "sight": Sight.NONE, "armor": 3,
		"cooling": true},                                              # 80+60+20
	{"name": "STERNGUARD", "kit": Kit.ULTRAMARINE, "primary": Weapon.Class.PLASMA_GUN,
		"sidearm": Weapon.Class.BOLT_PISTOL, "sight": Sight.HOLO, "armor": 2,
		"gadget": Gadget.AUSPEX_SCAN},                                 # 90+20+25+30
	{"name": "SCOUT SNIPER", "kit": Kit.ULTRAMARINE, "primary": Weapon.Class.STALKER_BOLT,
		"sidearm": Weapon.Class.BOLT_PISTOL, "sight": Sight.SCOPE_4X, "armor": 2,
		"grip": true},                                                 # 80+35+25+20
	{"name": "ASSAULT MARINE", "kit": Kit.BLOOD_ANGEL, "primary": Weapon.Class.CHAINSWORD,
		"sidearm": Weapon.Class.BOLT_PISTOL, "sight": Sight.NONE, "armor": 2,
		"gadget": Gadget.JUMP_PACK, "gadget2": Gadget.KRAK_GRENADE},   # 45+25+45+30
	{"name": "DEATH COMPANY", "kit": Kit.BLOOD_ANGEL, "primary": Weapon.Class.THUNDER_HAMMER,
		"sidearm": Weapon.Class.BOLT_PISTOL, "sight": Sight.NONE, "armor": 3,
		"gadget": Gadget.RED_THIRST},                                  # 75+60+25
	# --- WARHAMMER: Necrons ---------------------------------------------------
	{"name": "NECRON WARRIOR", "kit": Kit.NECRON, "primary": Weapon.Class.GAUSS_FLAYER,
		"sidearm": Weapon.Class.GAUSS_PISTOL, "sight": Sight.RED_DOT, "armor": 2,
		"cooling": true},                                              # 45+15+25+20
	{"name": "IMMORTAL", "kit": Kit.NECRON, "primary": Weapon.Class.GAUSS_BLASTER,
		"sidearm": Weapon.Class.GAUSS_PISTOL, "sight": Sight.HOLO, "armor": 3,
		"grip": true},                                                 # 60+20+60+20
	{"name": "DEATHMARK", "kit": Kit.NECRON, "primary": Weapon.Class.SYNAPTIC_DISINTEGRATOR,
		"sidearm": Weapon.Class.GAUSS_PISTOL, "sight": Sight.SCOPE, "armor": 1,
		"gadget": Gadget.PHASE_SHIFT},                                 # 85+25+45
	{"name": "LYCHGUARD", "kit": Kit.NECRON, "primary": Weapon.Class.WARSCYTHE,
		"sidearm": Weapon.Class.GAUSS_PISTOL, "sight": Sight.NONE, "armor": 2,
		"gadget": Gadget.TRANSLOCATION, "gadget2": Gadget.TESLA_ARC},  # 65+25+35+50
	# --- WARHAMMER: Orks ------------------------------------------------------
	{"name": "SHOOTA BOY", "kit": Kit.ORK, "primary": Weapon.Class.SHOOTA,
		"sidearm": Weapon.Class.SLUGGA, "sight": Sight.NONE, "armor": 2,
		"gadget": Gadget.WAAAGH, "gadget2": Gadget.STIKKBOMB},         # 45+25+25+25
	{"name": "BURNA BOY", "kit": Kit.ORK, "primary": Weapon.Class.BURNA,
		"sidearm": Weapon.Class.SLUGGA, "sight": Sight.NONE, "armor": 2,
		"gadget": Gadget.KUSTOM_FORCE_FIELD},                          # 55+25+50
	{"name": "TANKBUSTA", "kit": Kit.ORK, "primary": Weapon.Class.ROKKIT_LAUNCHA,
		"sidearm": Weapon.Class.SLUGGA, "sight": Sight.NONE, "armor": 2,
		"gadget2": Gadget.STIKKBOMB},                                  # 105+25+25
	{"name": "ORK NOB", "kit": Kit.ORK, "primary": Weapon.Class.POWER_KLAW,
		"sidearm": Weapon.Class.SLUGGA, "sight": Sight.NONE, "armor": 3,
		"gadget": Gadget.WAAAGH, "style": CharacterModel.Style.ORK_NOB},  # 70+60+25
	{"name": "MEK GUNNER", "kit": Kit.ORK, "primary": Weapon.Class.BIG_SHOOTA,
		"sidearm": Weapon.Class.SLUGGA, "sight": Sight.NONE, "armor": 3,
		"gadget": Gadget.GROT_GUNNER},                                 # 70+60+65
]


## The AI presets belonging to the universe being played. Derived from each
## preset's KIT rather than listed separately: a preset naming an Ork class is an
## Ork preset, and there is no second table to fall out of step.
static func universe_builds() -> Array[int]:
	var out: Array[int] = []
	for i in BOT_BUILDS.size():
		if kit_universe(int(BOT_BUILDS[i].get("kit", Kit.CLONE))) == active_universe:
			out.append(i)
	return out


## Build one of the AI presets. Anything the preset leaves out keeps its default.
static func bot_build(index: int) -> Loadout:
	var list := universe_builds()
	if list.is_empty():   # a universe with no AI authored yet: never crash a match
		return starter()
	return _build_from(BOT_BUILDS[list[wrapi(index, 0, list.size())]])


## --- faction rosters ---------------------------------------------------------
##
## The FACTION class mode (GameState.class_mode, any game mode — it was
## Conquest's, but it is a setting now) has no buy screen: you pick your side and
## then one of its four FIXED classes on the character-select screen. These are
## those classes — authored loadouts, not shopped, so they ignore BUDGET and the
## kit allow-lists (which only ever gate the buy screen). They reuse the ordinary
## catalogue by index, plus the Super Battle Droid's `primary_override` for the
## wrist cannon, which the shop does not sell.
##
## Order matters: the first four are REPUBLIC, the last four SEPARATIST;
## FACTION_ROSTERS maps a team to its slice. `name` is shown on the select
## screen. Some fields (smoke, the HMG, the shield) belong to another kit in the
## SHOP — here they are just gear on a fixed build, which is exactly what a
## preset is for.
const FACTION_BUILDS: Array[Dictionary] = [
	# REPUBLIC ---------------------------------------------------------------
	{"name": "CLONE TROOPER", "weapon": 2, "sight": Sight.RED_DOT, "cooling": true,
		"secondary": 0, "armor": 1, "gadget2": Gadget.GRENADE_FRAG,
		"style": CharacterModel.Style.CLONE},
	{"name": "CLONE ENGINEER", "weapon": 6, "grip": true, "secondary": 0,
		"armor": 2, "gadget": Gadget.TURRET, "gadget2": Gadget.GRENADE_SMOKE,
		"style": CharacterModel.Style.CLONE_ENGINEER},
	{"name": "CLONE HEAVY", "weapon": 9, "foregrip": true, "sight": Sight.RED_DOT,
		"secondary": 0, "armor": 3, "gadget": Gadget.SHIELD, "gadget2": Gadget.GRENADE_FRAG,
		"style": CharacterModel.Style.CLONE_HEAVY},
	{"name": "CLONE ARC", "weapon": 2, "sight": Sight.RED_DOT, "grip": true,
		"secondary": 0, "secondary_mod": SecondaryMod.DUAL, "armor": 1,
		"gadget": Gadget.SCAN_DART, "gadget2": Gadget.GRENADE_FRAG,
		"style": CharacterModel.Style.CLONE_ARC},
	# SEPARATIST -------------------------------------------------------------
	{"name": "BATTLE DROID", "weapon": 2, "sight": Sight.HOLO, "foregrip": true,
		"secondary": 0, "armor": 0, "gadget2": Gadget.GRENADE_FRAG,
		"style": CharacterModel.Style.B1},
	{"name": "SUPER BATTLE DROID", "primary_override": Weapon.Class.WRIST_CANNON,
		"secondary": 0, "armor": 3, "gadget": Gadget.WRIST_ROCKET, "gadget2": Gadget.SHIELD,
		"style": CharacterModel.Style.B2},
	# A FORCE kit for the guard, the double-jump and the intrinsic dash; the
	# electrostaff (primary_override, a melee weapon the shop does not sell) raises
	# that same guard, drawn as a shield in the off hand.
	{"name": "MAGNA GUARD", "kit": Kit.FORCE, "primary_override": Weapon.Class.STAFF,
		"secondary": 0, "armor": 2, "gadget": Gadget.DASH, "gadget2": Gadget.GRENADE_SMOKE,
		"style": CharacterModel.Style.MAGNAGUARD},
	{"name": "TACTICAL DROID", "weapon": NO_PRIMARY, "secondary": 3,
		"secondary_mod": SecondaryMod.SCOPE, "armor": 1,
		"gadget": Gadget.MORTAR, "gadget2": Gadget.GRENADE_FRAG,
		"style": CharacterModel.Style.TACTICAL},

	# HALO — UNSC (8-11) ------------------------------------------------------
	{"name": "SPARTAN-II", "kit": Kit.SPARTAN, "primary": Weapon.Class.MA5B,
		"sidearm": Weapon.Class.M6D, "sight": Sight.RED_DOT, "armor": 2,
		"gadget": Gadget.BUBBLE_SHIELD, "gadget2": Gadget.FRAG_GRENADE_UNSC,
		"style": CharacterModel.Style.SPARTAN},
	{"name": "SPARTAN HEAVY", "kit": Kit.SPARTAN, "primary": Weapon.Class.M247_HMG,
		"sidearm": Weapon.Class.M6D, "cooling": true, "armor": 3,
		"gadget": Gadget.SENTRY_TURRET, "gadget2": Gadget.FRAG_GRENADE_UNSC,
		"style": CharacterModel.Style.SPARTAN},
	{"name": "ODST", "kit": Kit.ODST, "primary": Weapon.Class.M7_SMG,
		"sidearm": Weapon.Class.M6D, "sight": Sight.HOLO, "armor": 0,
		"gadget": Gadget.ACTIVE_CAMO, "gadget2": Gadget.FRAG_GRENADE_UNSC,
		"style": CharacterModel.Style.ODST},
	{"name": "MARINE MARKSMAN", "kit": Kit.ODST, "primary": Weapon.Class.M392_DMR,
		"sidearm": Weapon.Class.M6D, "grip": true, "armor": 1,
		"gadget": Gadget.TRACKER_DART, "gadget2": Gadget.FRAG_GRENADE_UNSC,
		"style": CharacterModel.Style.MARINE},
	# HALO — Covenant (12-15) -------------------------------------------------
	{"name": "ELITE MINOR", "kit": Kit.SANGHEILI, "primary": Weapon.Class.PLASMA_RIFLE,
		"sidearm": Weapon.Class.PLASMA_PISTOL, "sight": Sight.HOLO, "armor": 1,
		"gadget": Gadget.THRUSTER_PACK, "gadget2": Gadget.PLASMA_GRENADE,
		"style": CharacterModel.Style.ELITE},
	{"name": "ELITE ZEALOT", "kit": Kit.SANGHEILI, "primary": Weapon.Class.ENERGY_SWORD,
		"sidearm": Weapon.Class.PLASMA_PISTOL, "armor": 2,
		"gadget": Gadget.ACTIVE_CAMO, "gadget2": Gadget.PLASMA_GRENADE,
		"style": CharacterModel.Style.ELITE},
	{"name": "GRUNT HEAVY", "kit": Kit.UNGGOY, "primary": Weapon.Class.FUEL_ROD,
		"sidearm": Weapon.Class.PLASMA_PISTOL, "armor": 0,
		"gadget": Gadget.GRAV_LIFT, "gadget2": Gadget.PLASMA_GRENADE,
		"style": CharacterModel.Style.GRUNT},
	{"name": "BRUTE CHIEFTAIN", "kit": Kit.JIRALHANAE, "primary": Weapon.Class.GRAV_HAMMER,
		"sidearm": Weapon.Class.MAULER, "armor": 3,
		"gadget": Gadget.BUBBLE_SHIELD, "gadget2": Gadget.PLASMA_GRENADE,
		"style": CharacterModel.Style.BRUTE},

	# WARHAMMER — Ultramarines (16-19) ----------------------------------------
	{"name": "TACTICAL MARINE", "kit": Kit.ULTRAMARINE, "primary": Weapon.Class.BOLTER,
		"sidearm": Weapon.Class.BOLT_PISTOL, "sight": Sight.RED_DOT, "armor": 2,
		"gadget": Gadget.IRON_HALO, "gadget2": Gadget.KRAK_GRENADE,
		"style": CharacterModel.Style.ULTRAMARINE},
	{"name": "DEVASTATOR", "kit": Kit.ULTRAMARINE, "primary": Weapon.Class.HEAVY_BOLTER,
		"sidearm": Weapon.Class.BOLT_PISTOL, "cooling": true, "armor": 3,
		"gadget": Gadget.ORBITAL_BOMBARDMENT, "gadget2": Gadget.KRAK_GRENADE,
		"style": CharacterModel.Style.ULTRAMARINE},
	{"name": "STERNGUARD", "kit": Kit.ULTRAMARINE, "primary": Weapon.Class.PLASMA_GUN,
		"sidearm": Weapon.Class.PLASMA_PISTOL_40K, "sight": Sight.HOLO, "armor": 2,
		"gadget": Gadget.AUSPEX_SCAN, "gadget2": Gadget.MELTA_BOMB,
		"style": CharacterModel.Style.ULTRAMARINE},
	{"name": "VANGUARD VETERAN", "kit": Kit.ULTRAMARINE, "primary": Weapon.Class.POWER_SWORD,
		"sidearm": Weapon.Class.BOLT_PISTOL, "armor": 2,
		"gadget": Gadget.ASSAULT_CANNON, "gadget2": Gadget.KRAK_GRENADE,
		"style": CharacterModel.Style.ULTRAMARINE},
	# WARHAMMER — Blood Angels (20-23) ----------------------------------------
	{"name": "ASSAULT MARINE", "kit": Kit.BLOOD_ANGEL, "primary": Weapon.Class.CHAINSWORD,
		"sidearm": Weapon.Class.BOLT_PISTOL, "armor": 2,
		"gadget": Gadget.JUMP_PACK, "gadget2": Gadget.KRAK_GRENADE,
		"style": CharacterModel.Style.BLOOD_ANGEL},
	{"name": "SANGUINARY GUARD", "kit": Kit.BLOOD_ANGEL, "primary": Weapon.Class.POWER_SWORD,
		"sidearm": Weapon.Class.PLASMA_PISTOL_40K, "armor": 3,
		"gadget": Gadget.JUMP_PACK, "gadget2": Gadget.RED_THIRST,
		"style": CharacterModel.Style.BLOOD_ANGEL},
	{"name": "DEATH COMPANY", "kit": Kit.BLOOD_ANGEL, "primary": Weapon.Class.THUNDER_HAMMER,
		"sidearm": Weapon.Class.BOLT_PISTOL, "armor": 3,
		"gadget": Gadget.RED_THIRST, "gadget2": Gadget.MELTA_BOMB,
		"style": CharacterModel.Style.BLOOD_ANGEL},
	{"name": "BA TACTICAL", "kit": Kit.BLOOD_ANGEL, "primary": Weapon.Class.BOLTER,
		"sidearm": Weapon.Class.BOLT_PISTOL, "sight": Sight.HOLO, "armor": 2,
		"gadget": Gadget.IRON_HALO, "gadget2": Gadget.KRAK_GRENADE,
		"style": CharacterModel.Style.BLOOD_ANGEL},
	# WARHAMMER — Necrons (24-27) ---------------------------------------------
	{"name": "NECRON WARRIOR", "kit": Kit.NECRON, "primary": Weapon.Class.GAUSS_FLAYER,
		"sidearm": Weapon.Class.GAUSS_PISTOL, "sight": Sight.RED_DOT, "armor": 2,
		"gadget": Gadget.PHASE_SHIFT, "style": CharacterModel.Style.NECRON},
	{"name": "IMMORTAL", "kit": Kit.NECRON, "primary": Weapon.Class.GAUSS_BLASTER,
		"sidearm": Weapon.Class.GAUSS_PISTOL, "sight": Sight.HOLO, "armor": 3,
		"gadget": Gadget.CANOPTEK_SPYDER, "style": CharacterModel.Style.NECRON},
	{"name": "DEATHMARK", "kit": Kit.NECRON, "primary": Weapon.Class.SYNAPTIC_DISINTEGRATOR,
		"sidearm": Weapon.Class.GAUSS_PISTOL, "sight": Sight.SCOPE_4X, "armor": 1,
		"gadget": Gadget.TRANSLOCATION, "style": CharacterModel.Style.NECRON},
	{"name": "LYCHGUARD", "kit": Kit.NECRON, "primary": Weapon.Class.WARSCYTHE,
		"sidearm": Weapon.Class.GAUSS_PISTOL, "armor": 3,
		"gadget": Gadget.TESLA_ARC, "gadget2": Gadget.TRANSLOCATION,
		"style": CharacterModel.Style.NECRON_LORD},
	# WARHAMMER — Orks (28-31) ------------------------------------------------
	{"name": "SHOOTA BOY", "kit": Kit.ORK, "primary": Weapon.Class.SHOOTA,
		"sidearm": Weapon.Class.SLUGGA, "armor": 2,
		"gadget": Gadget.WAAAGH, "gadget2": Gadget.STIKKBOMB,
		"style": CharacterModel.Style.ORK},
	{"name": "BURNA BOY", "kit": Kit.ORK, "primary": Weapon.Class.BURNA,
		"sidearm": Weapon.Class.SLUGGA, "armor": 2,
		"gadget": Gadget.KUSTOM_FORCE_FIELD, "gadget2": Gadget.SMOKE_LAUNCHER,
		"style": CharacterModel.Style.ORK},
	{"name": "TANKBUSTA", "kit": Kit.ORK, "primary": Weapon.Class.ROKKIT_LAUNCHA,
		"sidearm": Weapon.Class.SLUGGA, "armor": 2,
		"gadget": Gadget.ROKKIT_PACK, "gadget2": Gadget.STIKKBOMB,
		"style": CharacterModel.Style.ORK},
	{"name": "ORK NOB", "kit": Kit.ORK, "primary": Weapon.Class.POWER_KLAW,
		"sidearm": Weapon.Class.SLUGGA, "armor": 3,
		"gadget": Gadget.GROT_GUNNER, "gadget2": Gadget.WAAAGH,
		"style": CharacterModel.Style.ORK_NOB},
]

## Which FACTION_BUILDS indices each team may pick from, PER UNIVERSE. Team 0 is
## the first side listed in UNIVERSES, team 1 the second, and so on. Faction
## classes are playable in every mode, so a three- or four-way match can ask for
## a roster nobody has authored: those sides WRAP onto the ones that exist rather
## than crashing or being locked out of the setting. Warhammer is the first
## universe to fill all four slots — two chapters, the Necrons and the Orks —
## which is what a wrap is there to make optional rather than required.
const FACTION_ROSTERS := {
	Universe.STAR_WARS: [[0, 1, 2, 3], [4, 5, 6, 7]],
	Universe.HALO: [[8, 9, 10, 11], [12, 13, 14, 15]],
	Universe.WARHAMMER: [[16, 17, 18, 19], [20, 21, 22, 23],
		[24, 25, 26, 27], [28, 29, 30, 31]],
}


## The four class indices a team chooses between, in the universe being played.
static func faction_classes(team: int) -> Array:
	var rosters: Array = FACTION_ROSTERS.get(active_universe,
		FACTION_ROSTERS[Universe.STAR_WARS])
	return rosters[wrapi(maxi(team, 0), 0, rosters.size())]


## Build a faction class by its GLOBAL index into FACTION_BUILDS.
static func faction_build(index: int) -> Loadout:
	return _build_from(FACTION_BUILDS[wrapi(index, 0, FACTION_BUILDS.size())])


## A team's Nth class (0..3), built and ready to deploy.
static func team_build(team: int, class_slot: int) -> Loadout:
	var roster := faction_classes(team)
	return faction_build(roster[wrapi(class_slot, 0, roster.size())])


## Build a preset row. Two keys are TRANSLATED rather than assigned: `primary`
## and `sidearm` name a Weapon.Class and are looked up into the WEAPONS /
## SECONDARIES index the build actually stores. Presets used to state those
## indices as literals, which silently re-armed every preset below any gun
## inserted into either table — with forty new weapons in the catalogue that
## stopped being a theoretical risk. `weapon`/`secondary` still work for the
## original rows, so nothing had to be re-counted to add this.
static func _build_from(preset: Dictionary) -> Loadout:
	var built := Loadout.new()
	for key in preset:
		match key:
			"name":
				pass
			"primary":
				built.weapon = weapon_index(preset[key])
			"sidearm":
				built.secondary = secondary_index(preset[key])
			_:
				built.set(key, preset[key])
	return built


## What you drop in with in battle royale: the free sidearm and nothing else.
## Everything better is on the ground, which is the entire mode.
## Which entries of a catalogue battle royale may generate. ROYALE HAS NO
## CLASSES: everyone drops in as a plain trooper, so anything carrying a "kit"
## key is a class's signature — a lightsaber, a Force power — and there is no
## class for it to belong to. Handing one out would give a scavenger a weapon
## with no guard to go with it, or a power on a button that class-free builds do
## not have. `from` skips the leading "none" row where a table has one.
##
## An entry may opt back IN with `"royale": true`. That is for gear which is a
## class's by BALANCE rather than by mechanism — the heavy guns and the barrier
## work exactly as well in the hands of a plain trooper, and dropping them from
## the crates would quietly gut the loot table. The test is: does the item need
## something only a class has? A saber needs the guard, a Force power needs the
## button. A rocket tube needs neither.
## ...and it filters by UNIVERSE for the same reason it filters by kit: a crate
## on a Halo map has no business containing a bowcaster. The universe is not a
## balance question, it is what the match IS.
static func royale_items(table: Array[Dictionary], from := 0) -> Array[int]:
	var out: Array[int] = []
	for i in range(from, table.size()):
		if not in_universe(table[i], active_universe):
			continue
		if not table[i].has("kit") or table[i].get("royale", false):
			out.append(i)
	return out


static func royale_start() -> Loadout:
	var l := Loadout.new()
	# The class-free baseline for this universe: no saber, no powers, no guard.
	l.kit = default_kit()
	l.weapon = NO_PRIMARY
	l.secondary = l._first_allowed(Row.SECONDARY, SECONDARIES.size())
	l.gadget = Gadget.NONE
	l.armor = DEFAULT_ARMOR
	l.squad = 0
	return l


## A starter build that spends part of the budget: standard armour, basic rifle.
## The gun is looked up by CLASS, not by a literal index — inserting a cheaper
## primary into WEAPONS silently changed what every player deployed with — and
## WHICH class comes from the universe's baseline kit, so a first deploy in Halo
## hands you an MA5B rather than a DC-15 the kit could not legally hold.
static func starter() -> Loadout:
	var l := Loadout.new()
	l.adopt_kit(default_kit())
	var k: Dictionary = KITS[l.kit]
	if k.has("starter"):
		l.weapon = weapon_index(k["starter"])
	return l


## Where a gun sits in WEAPONS, or NO_PRIMARY if it isn't sold as a primary.
static func weapon_index(gun: Weapon.Class) -> int:
	for i in WEAPONS.size():
		if WEAPONS[i]["class"] == gun:
			return i
	return NO_PRIMARY


## Where a sidearm sits in SECONDARIES, or 0 (the free pistol) if it is not sold
## as one. Named-weapon presets go through this the way primaries go through
## weapon_index.
static func secondary_index(gun: Weapon.Class) -> int:
	for i in SECONDARIES.size():
		if SECONDARIES[i]["class"] == gun:
			return i
	return 0


## Delegates to _copy_from so there's exactly one list of fields to keep in
## step with — step() trials changes on a duplicate, so a field missed here
## would be silently reset by any edit to another row.
func duplicate_loadout() -> Loadout:
	var copy := Loadout.new()
	copy._copy_from(self)
	return copy


## --- character class ---------------------------------------------------------

func kit_stats() -> Dictionary:
	return KITS[kit]


func kit_name() -> String:
	return KITS[kit]["name"]


func gadget_slots() -> int:
	return int(KITS[kit]["gadget_slots"])


## Foot-speed multiplier for the class, on top of the armour frame's. Defaults
## to 1.0, so a kit only has to say anything when it is not ordinary.
func kit_speed() -> float:
	return float(KITS[kit].get("speed", 1.0))


## Health multiplier for the class, on top of the armour frame's. Same shape as
## kit_speed for the same reason: the frames stay meaningfully different inside a
## class instead of one flat number replacing everything the player bought.
func kit_health() -> float:
	return float(KITS[kit].get("health", 1.0))


## What the armour frame is actually worth to THIS build, class included. Every
## place that sets a body's health goes through here, so the number on the buy
## screen and the number you deploy with cannot drift apart.
## ...and the TIME-TO-KILL setting scales the lot. It is applied HERE, in the one
## function every body's health already goes through (Player, Bot.setup and the
## bot heal ceiling), which is why "how fast someone dies" is a single number and
## not a rule threaded through the damage code: halve everyone's health and every
## gun in the game kills twice as fast, with no weapon rebalanced.
func max_health() -> float:
	return float(armor_stats()["health"]) * kit_health() * ttk_health


func can_dash() -> bool:
	return bool(KITS[kit].get("dash", false))


## True if this kit may hold that entry on that row. Rows with no restriction
## answer true for everything, so a new row costs nothing here.
func allows(row: int, index: int) -> bool:
	var k := KITS[kit]
	match row:
		# The CLASS row offers the universe being played and nothing else. This
		# is the ONE allow-list that reads the active universe rather than
		# deriving it from the build, because it is the row that CHOOSES which
		# universe's class you are on.
		Row.KIT:
			return kit_universe(index) == active_universe
		# The four catalogue rows share ONE rule (see _allows_entry): a
		# "kit"-marked entry belongs to its owner alone; otherwise an optional
		# per-kit allow-list restricts to those, else anything goes. The identity
		# a restrictive list matches on is the weapon CLASS for guns and the plain
		# INDEX for sights and grenades — which is the only thing that differs.
		Row.WEAPON:
			return _allows_entry(WEAPONS[index], WEAPONS[index]["class"], "primaries")
		Row.SECONDARY:
			return _allows_entry(SECONDARIES[index], SECONDARIES[index]["class"], "secondaries")
		Row.SIGHT:
			return _allows_entry(SIGHTS[index], index, "sights")
		Row.GADGET, Row.GADGET2:
			if not in_universe(GADGETS[index], kit_universe(kit)):
				return false
			if not index in k["gadgets"]:
				return false
			# Two slots, two different gadgets. Carrying the same one twice buys
			# nothing and would put a jetpack on both buttons.
			var other: int = gadget2 if row == Row.GADGET else gadget
			return index == Gadget.NONE or index != other
		Row.SECONDARY_MOD:
			return index in k["secondary_mods"]
		Row.ARMOR:
			return index in k["armor"]
	return true


## The shared allow-list rule for the catalogue rows. `entry` is the table row,
## `identity` is what a restrictive list matches on (a Weapon.Class for guns, an
## index for sights/grenades), and `list_name` is the kit key that restricts it.
func _allows_entry(entry: Dictionary, identity, list_name: String) -> bool:
	# THE UNIVERSE COMES FIRST, and it is the one rule with no exceptions: a
	# bolter is not a thing a clone trooper is allowed to want. Derived from the
	# kit rather than read off GameState, so this stays callable with no
	# autoloads (the kit_rules test runs under --script).
	if not in_universe(entry, kit_universe(kit)):
		return false
	# A "kit"-marked entry (the saber, the bowcaster, smoke, the thermal holo) is
	# its owner's alone and always reachable by them — which is what lets a class
	# keep its signature gear while still shopping the ordinary catalogue.
	if entry.has("kit"):
		return entry["kit"] == kit
	# Otherwise: a per-kit list means ONLY those (the Wookiee's heavies), and no
	# list means anything ordinary goes.
	var only: Array = KITS[kit].get(list_name, [])
	return only.is_empty() or identity in only


## True if the row exists at all for this kit. A row that is unavailable is
## hidden on the buy screen and skipped by the cursor, rather than shown as a
## line you can sit on and not change — four players shop at once and a dead
## line reads as a broken screen.
func row_available(row: int) -> bool:
	match row:
		Row.GADGET2:
			return gadget_slots() >= 2
		Row.SIGHT, Row.COOLING, Row.GRIP, Row.FOREGRIP:
			# Sights and cooling vanes on a sword are nothing. They are also the
			# rows that would otherwise let a Force adept spend 65 tokens on
			# absolutely no effect.
			return has_primary() and not primary_is_melee()
	return true


## --- buy-screen boxes ---------------------------------------------------------

## True if this kit has anything at all inside that box. A box with nothing left
## in it is hidden AND skipped by the selector, exactly as an unavailable row is
## — a Mandalorian's screen has no GRENADES panel to land on.
func box_available(box: int) -> bool:
	if box < 0 or box >= BUY_BOXES.size():
		return false
	for row in BUY_BOXES[box]["rows"]:
		if row_available(row):
			return true
	return false


## The first row inside a box that this kit actually has, or -1.
func first_row_in(box: int) -> int:
	if box < 0 or box >= BUY_BOXES.size():
		return -1
	for row in BUY_BOXES[box]["rows"]:
		if row_available(row):
			return row
	return -1


## Step to another row INSIDE one box, without escaping it. Returns the row it
## lands on; walking off either end stops rather than wrapping into the next box,
## because a box you opened is the only thing you should be able to change.
func step_row_in(box: int, from: int, dir: int) -> int:
	var rows: Array = BUY_BOXES[box]["rows"]
	var at := rows.find(from)
	if at < 0:
		return first_row_in(box)
	var i := at + dir
	while i >= 0 and i < rows.size():
		if row_available(rows[i]):
			return rows[i]
		i += dir
	return from


func primary_is_melee() -> bool:
	return has_primary() and Weapon.PROFILES[weapon_class()].get("melee", false)


## The first available row at or after `from`, walking in `dir`. The buy cursor
## uses this so it never lands on a row this kit does not have.
func next_row(from: int, dir: int) -> int:
	var row := wrapi(from, 0, Row.size())
	for _i in Row.size():
		if row_available(row):
			return row
		row = wrapi(row + dir, 0, Row.size())
	return from


## Rebuild as this kit's default. Switching class RESETS the build rather than
## converting it: half the selections would be illegal, and quietly rewriting
## six rows under a player who nudged one is worse than starting clean. It also
## means the result is always inside BUDGET without a second pass.
func adopt_kit(new_kit: int) -> void:
	var fresh := Loadout.new()
	fresh.kit = clampi(new_kit, 0, KITS.size() - 1)
	var k: Dictionary = KITS[fresh.kit]
	fresh.armor = int(k["default_armor"])
	# What the kit opens holding: an explicit `default_primary` (the Force adept's
	# saber, which it may swap OFF), else the sole entry of a restrictive
	# `primaries` list (the Wookiee is holding a heavy, not choosing one), else no
	# primary at all — the sidearm is free, so a build can deploy on it alone.
	var only: Array = k.get("primaries", [])
	if k.has("default_primary"):
		fresh.weapon = weapon_index(k["default_primary"])
	elif not only.is_empty():
		fresh.weapon = weapon_index(only[0])
	else:
		fresh.weapon = NO_PRIMARY
	# ...and the same for the sidearm, or a Wookiee would adopt its kit still
	# holding the pistol on row 0 — an illegal build that the buy screen would
	# then refuse to step off, because every direction from it is disallowed.
	fresh.secondary = fresh._first_allowed(Row.SECONDARY, SECONDARIES.size())
	fresh.gadget = Gadget.NONE
	fresh.gadget2 = Gadget.NONE
	_copy_from(fresh)


func cost() -> int:
	var total: int = WEAPONS[weapon]["cost"]
	total += SECONDARIES[secondary]["cost"]
	total += SECONDARY_MODS[secondary_mod]["cost"]
	total += SIGHTS[sight]["cost"]
	total += GADGETS[gadget]["cost"]
	total += GADGETS[gadget2]["cost"]
	total += ARMOR[armor]["cost"]
	for up in UPGRADES:
		if get(up["key"]):
			total += int(up["cost"])
	total += squad_cost()
	return total


## The squad is priced per head, so raising skill raises the whole bill.
func squad_cost() -> int:
	return squad * int(SQUAD_SKILLS[squad_skill]["cost"])


func remaining() -> int:
	return BUDGET - cost()


## The primary gun, or -1 when you bought none. A faction preset's explicit
## override wins over the WEAPONS lookup (see primary_override).
## Which procedural body to build: the explicit faction style if one was set,
## otherwise mapped from the kit (a plain Clone, a Mandalorian, a Force adept in
## robes, a Wookiee, a Trandoshan).
## ...which is a KIT TABLE LOOKUP rather than a match on the enum: with fourteen
## classes across three universes, a match statement is a list of every class
## written a second time somewhere the class itself cannot see.
func character_style() -> int:
	if style >= 0:
		return style
	return int(KITS[kit].get("style", CharacterModel.Style.GENERIC))


func weapon_class() -> int:
	return primary_override if primary_override >= 0 else WEAPONS[weapon]["class"]


func has_primary() -> bool:
	return primary_override >= 0 or weapon != NO_PRIMARY


func weapon_name() -> String:
	return "none" if not has_primary() else Weapon.PROFILES[weapon_class()]["name"]


func secondary_class() -> Weapon.Class:
	return SECONDARIES[secondary]["class"] as Weapon.Class


func secondary_name() -> String:
	return Weapon.PROFILES[secondary_class()]["name"]


## The class you actually deploy holding: your primary if you bought one.
func deploy_class() -> Weapon.Class:
	return weapon_class() as Weapon.Class if has_primary() else secondary_class()


## GADGETS is listed in Gadget enum order, so the row index IS the gadget id.
func gadget_id() -> int:
	return gadget


## The second slot, or NONE for every kit that only has one.
func gadget2_id() -> int:
	return gadget2 if gadget_slots() >= 2 else Gadget.NONE


## Does this build carry a gadget that DOES `action` — in either slot, under any
## universe's name for it? Bot asks this rather than comparing raw ids, so "does
## this AI have a turret" is one question whether the turret is an autosentry, a
## canoptek spyder or a grot on a gun.
func uses(action: int) -> bool:
	return gadget_action(gadget_id()) == action or gadget_action(gadget2_id()) == action


## One line naming what this build actually deploys with — gun, sidearm, gadgets
## and the health the frame gives it.
##
## Derived from the build rather than written per preset, because a faction
## class IS a table row: a hand-written blurb sitting next to it goes stale the
## first time somebody swaps the gadget and does not notice the description.
## The character-select screen shows this under the class list.
func gear_summary() -> String:
	var parts := PackedStringArray()
	parts.append(weapon_name() if has_primary() else secondary_name())
	if has_primary():
		parts.append(secondary_name())
	for id in [gadget_id(), gadget2_id()]:
		if id != Gadget.NONE:
			parts.append(str(GADGETS[id]["name"]))
	parts.append("%d HP" % roundi(max_health()))
	return "   ·   ".join(parts)


func armor_stats() -> Dictionary:
	return ARMOR[armor]


func squad_skill_stats() -> Dictionary:
	return SQUAD_SKILLS[squad_skill]


## The PRIMARY's upgrade flags, in the shape Weapon.set_class wants.
func primary_mods() -> Dictionary:
	return {"sight": sight, "cooling": cooling, "grip": grip, "foregrip": foregrip}


## The SIDEARM's, from its own one-pick slot. Dual wield changes how the gun is
## carried rather than how it shoots, so it contributes no flags here.
func secondary_mods() -> Dictionary:
	return {
		"sight": Sight.SCOPE if secondary_mod == SecondaryMod.SCOPE else Sight.NONE,
		"cooling": secondary_mod == SecondaryMod.COOLING,
		"grip": false,
	}


## Whichever set applies to the gun currently in hand.
func mods_for(on_secondary: bool) -> Dictionary:
	return secondary_mods() if on_secondary else primary_mods()


func dual_wield() -> bool:
	return secondary_mod == SecondaryMod.DUAL


## Move one option along `row` by `dir` (-1/+1). Anything the budget can't cover
## is refused, so a build on screen is always one you can actually deploy with.
## Returns true if the build changed.
func step(row: int, dir: int) -> bool:
	var trial := duplicate_loadout()
	trial._step_unchecked(row, dir)
	if trial.cost() > BUDGET or trial._same_as(self):
		return false
	_copy_from(trial)
	return true


## Walk `current` one step in `dir`, skipping anything this kit may not take, and
## stopping where it started if there is nothing further along. Stepping ONE at a
## time and refusing would strand the cursor on the first disallowed entry, so
## the skip has to happen here rather than in step().
## The lowest entry on a row this kit may hold, or 0 if it may hold none — the
## starting point adopt_kit drops a fresh build on.
func _first_allowed(row: int, size: int) -> int:
	for i in size:
		if allows(row, i):
			return i
	return 0


func _walk(row: int, current: int, dir: int, size: int) -> int:
	var i := current + dir
	while i >= 0 and i < size:
		if allows(row, i):
			return i
		i += dir
	return current


func _step_unchecked(row: int, dir: int) -> void:
	match row:
		Row.KIT:
			# Walked, not clamped: the classes of three universes share one enum
			# and only this universe's are legal, so a clamp would step straight
			# from the last Star Wars class onto a Spartan.
			adopt_kit(_walk(row, kit, dir, KITS.size()))
		Row.WEAPON:
			weapon = _walk(row, weapon, dir, WEAPONS.size())
		Row.SECONDARY:
			# Walked, not clamped: the row has kit-locked entries in it now, and
			# a clamp would have let anyone step onto the bowcaster.
			secondary = _walk(row, secondary, dir, SECONDARIES.size())
		Row.SECONDARY_MOD:
			secondary_mod = _walk(row, secondary_mod, dir, SECONDARY_MODS.size())
		Row.GADGET:
			gadget = _walk(row, gadget, dir, GADGETS.size())
		Row.GADGET2:
			gadget2 = _walk(row, gadget2, dir, GADGETS.size())
		Row.SIGHT:
			# Walked, not clamped: THERMAL is kit-locked, so a clamp would let
			# anyone step onto it.
			sight = _walk(row, sight, dir, SIGHTS.size())
		Row.COOLING:
			cooling = not cooling
		Row.GRIP:
			grip = not grip
		Row.FOREGRIP:
			foregrip = not foregrip
		Row.ARMOR:
			armor = _walk(row, armor, dir, ARMOR.size())
		Row.SQUAD:
			squad = clampi(squad + dir, 0, SQUAD_MAX)
		Row.SQUAD_SKILL:
			squad_skill = clampi(squad_skill + dir, 0, SQUAD_SKILLS.size() - 1)


func _same_as(other: Loadout) -> bool:
	return kit == other.kit \
		and weapon == other.weapon and secondary == other.secondary \
		and secondary_mod == other.secondary_mod \
		and gadget == other.gadget and gadget2 == other.gadget2 \
		and sight == other.sight \
		and cooling == other.cooling and grip == other.grip \
		and armor == other.armor and squad == other.squad \
		and squad_skill == other.squad_skill


func _copy_from(other: Loadout) -> void:
	kit = other.kit
	gadget2 = other.gadget2
	weapon = other.weapon
	primary_override = other.primary_override
	style = other.style
	secondary = other.secondary
	secondary_mod = other.secondary_mod
	gadget = other.gadget
	sight = other.sight
	cooling = other.cooling
	grip = other.grip
	foregrip = other.foregrip
	armor = other.armor
	squad = other.squad
	squad_skill = other.squad_skill


## Display: the fixed name of a row, what's currently selected on it, what that
## selection costs, and a one-line explanation. Drives the whole buy screen.
func row_label(row: int) -> String:
	match row:
		Row.KIT: return "CLASS"
		Row.WEAPON: return "PRIMARY"
		Row.SECONDARY: return "SIDEARM"
		Row.SECONDARY_MOD: return "SIDEARM MOD"
		Row.GADGET: return "GADGET"
		Row.GADGET2: return "GADGET 2"
		Row.SIGHT: return "SIGHT"
		Row.ARMOR: return "ARMOR"
		Row.SQUAD: return "AI SQUAD"
		Row.SQUAD_SKILL: return "SQUAD SKILL"
		_: return UPGRADES[_upgrade_index(row)]["name"]


func row_value(row: int) -> String:
	match row:
		Row.KIT: return kit_name()
		Row.WEAPON: return weapon_name()
		Row.SECONDARY: return secondary_name()
		Row.SECONDARY_MOD: return SECONDARY_MODS[secondary_mod]["name"]
		Row.GADGET: return GADGETS[gadget]["name"]
		Row.GADGET2: return GADGETS[gadget2]["name"]
		Row.SIGHT: return SIGHTS[sight]["name"]
		Row.ARMOR: return ARMOR[armor]["name"]
		Row.SQUAD: return "x%d" % squad if squad > 0 else "none"
		Row.SQUAD_SKILL: return SQUAD_SKILLS[squad_skill]["name"]
		_: return "fitted" if get(UPGRADES[_upgrade_index(row)]["key"]) else "none"


func row_cost(row: int) -> int:
	match row:
		Row.KIT: return 0  # the class is free; what it lets you buy is not
		Row.WEAPON: return WEAPONS[weapon]["cost"]
		Row.SECONDARY: return SECONDARIES[secondary]["cost"]
		Row.SECONDARY_MOD: return SECONDARY_MODS[secondary_mod]["cost"]
		Row.GADGET: return GADGETS[gadget]["cost"]
		Row.GADGET2: return GADGETS[gadget2]["cost"]
		Row.SIGHT: return SIGHTS[sight]["cost"]
		Row.ARMOR: return ARMOR[armor]["cost"]
		Row.SQUAD, Row.SQUAD_SKILL: return squad_cost()
		_:
			var up: Dictionary = UPGRADES[_upgrade_index(row)]
			return int(up["cost"]) if get(up["key"]) else 0


## The line under the cursor. `device` is the shopping player's input_device, so
## the rows that name a control name the one THAT player would actually press
## (and keep naming the right one after a rebind).
func row_blurb(row: int, device: int = -1) -> String:
	match row:
		Row.KIT:
			return KITS[kit]["blurb"]
		Row.WEAPON:
			if not has_primary():
				return "No primary — you deploy with your sidearm"
			var p: Dictionary = Weapon.PROFILES[weapon_class()]
			return "%d dmg   %.0fm range" % [p["damage"], p["range"]]
		Row.SECONDARY:
			var sp: Dictionary = Weapon.PROFILES[secondary_class()]
			return "%d dmg   swap with %s" % [
				sp["damage"], Controls.label(device, "switch")]
		Row.SECONDARY_MOD:
			return SECONDARY_MODS[secondary_mod]["blurb"]
		Row.GADGET:
			return GADGETS[gadget]["blurb"]
		Row.GADGET2:
			return "%s   (on slot 2: %s)" % [GADGETS[gadget2]["blurb"],
				Controls.slot2_label(device)]
		Row.SIGHT:
			return "%s   (primary only)" % SIGHTS[sight]["blurb"]
		Row.ARMOR:
			# The kit's multiplier is folded in, so the line reads what you will
			# actually deploy with rather than the frame's paper number.
			return "%s   %d HP" % [armor_stats()["blurb"], roundi(max_health())]
		Row.SQUAD:
			var each: int = SQUAD_SKILLS[squad_skill]["cost"]
			return "%d each at %s   (max %d, they fight for your team)" % [
				each, SQUAD_SKILLS[squad_skill]["name"], SQUAD_MAX]
		Row.SQUAD_SKILL:
			var skill: Dictionary = SQUAD_SKILLS[squad_skill]
			return "%s   (%d each)" % [skill["blurb"], skill["cost"]]
		_:
			var up: Dictionary = UPGRADES[_upgrade_index(row)]
			return "%s   (%d, primary only)" % [up["blurb"], up["cost"]]


## COOLING/GRIP are contiguous and in UPGRADES order, so an upgrade row is just
## its offset from the first one. The four row_* functions fall through to this
## for anything they do not name, which means a row added ABOVE COOLING and not
## given a case computes a negative index instead of failing where the mistake
## is — exactly what adding the CLASS row at position 0 did. Assert rather than
## let it index backwards into the array.
func _upgrade_index(row: int) -> int:
	var i := row - Row.COOLING
	assert(i >= 0 and i < UPGRADES.size(),
		"row %d has no case in the row_* functions" % row)
	return i
