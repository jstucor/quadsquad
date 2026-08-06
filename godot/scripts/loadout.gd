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
		# FOUR ERAS ON ONE FIELD, which is the point of a setting rather than a
		# campaign: the Clone Wars pair and the Galactic Civil War pair, and any
		# of the four can be fielded against any other.
		"teams": ["REPUBLIC", "SEPARATIST", "EMPIRE", "REBEL ALLIANCE"],
		"colors": [Color(0.35, 0.55, 1.0), Color(1.0, 0.40, 0.32),
			Color(0.62, 0.66, 0.72), Color(0.95, 0.62, 0.22)],
		# Clone blue against droid red is the Clone Wars, and Imperial green
		# against Alliance orange is every space battle in the trilogy. The one
		# universe where the SIDE really does decide the colour of a bolt.
		"bolts": [Color(0.35, 0.65, 1.0), Color(1.0, 0.24, 0.14),
			Color(0.38, 1.0, 0.40), Color(1.0, 0.52, 0.14)],
	},
	{
		"name": "HALO",
		"blurb": "UNSC ballistics against Covenant plasma",
		"kit": Kit.SPARTAN,
		"teams": ["UNSC", "COVENANT", "BANISHED", "FORERUNNER"],
		"colors": [Color(0.38, 0.78, 0.42), Color(0.70, 0.45, 1.0),
			Color(1.0, 0.45, 0.22), Color(0.45, 0.85, 0.95)],
		# Brass tracer against plasma. Most Covenant guns state their own colour
		# and never reach this, which is the ordering working as intended.
		"bolts": [Color(1.0, 0.86, 0.48), Color(0.45, 0.75, 1.0),
			Color(1.0, 0.42, 0.18), Color(0.60, 0.92, 1.0)],
	},
	{
		"name": "WARHAMMER 40,000",
		"blurb": "Two Astartes chapters, the Necrons and the Orks",
		"kit": Kit.ULTRAMARINE,
		"teams": ["ULTRAMARINES", "BLOOD ANGELS", "NECRONS", "ORKS"],
		"colors": [Color(0.30, 0.50, 1.0), Color(1.0, 0.26, 0.24),
			Color(0.40, 0.95, 0.50), Color(0.86, 0.74, 0.22)],
		# The two chapters are near-identical on purpose: they fire the same
		# mass-reactive shell, and a bolter's tracer is not a chapter badge.
		"bolts": [Color(1.0, 0.80, 0.42), Color(1.0, 0.70, 0.32),
			Color(0.45, 1.0, 0.55), Color(1.0, 0.62, 0.22)],
	},
]

## --- FACTIONS, FLAT --------------------------------------------------------
##
## A SIDE IS NOW PICKED INDEPENDENTLY OF THE SETTING, so UNSC can fight the
## Republic. `UNIVERSES` still groups the catalogue — which classes and guns a
## faction can reach is its universe's answer, and that has not changed — but a
## MATCH no longer has one universe. It has up to four sides, each of which
## names a universe and a slot inside it.
##
## Stated as a DERIVED flat list rather than a second hand-written table, because
## a faction's name, colour and bolt already live in `UNIVERSES` and a copy would
## be one edit away from a side whose chip and whose tracer disagree with the
## roster it fields.
##
## Halo lists four team names but authors only two rosters, so `faction_count`
## asks FACTION_ROSTERS rather than the name list — a side with no classes is a
## side you can select and cannot play.
static var _factions: Array[Dictionary] = []


static func factions() -> Array[Dictionary]:
	if not _factions.is_empty():
		return _factions
	for u in UNIVERSES.size():
		var rosters: Array = FACTION_ROSTERS.get(u, [])
		var names: Array = UNIVERSES[u]["teams"]
		for side in rosters.size():
			_factions.append({
				"universe": u,
				"side": side,
				"name": str(names[side]) if side < names.size() else "SIDE %d" % side,
				"color": (UNIVERSES[u]["colors"] as Array)[side],
				"bolt": (UNIVERSES[u]["bolts"] as Array)[side],
				# What it is called when two settings are on the field at once and
				# "NECRONS" alone does not say which game you are looking at.
				"universe_name": str(UNIVERSES[u]["name"]),
			})
	return _factions


static func faction(index: int) -> Dictionary:
	var all := factions()
	return all[clampi(index, 0, all.size() - 1)]


## The first faction of a universe, so the menu can offer "all Star Wars" as a
## one-press default without knowing how the flat list is ordered.
static func first_faction_of(universe: int) -> int:
	var all := factions()
	for i in all.size():
		if int(all[i]["universe"]) == universe:
			return i
	return 0


## --- TEAM COLOURS YOU CAN CHOOSE ---------------------------------------------
##
## PURPLE CLONES AND YELLOW DROIDS. The faction's own colour is the default and
## always the first entry, so "leave it alone" is what you get by not touching
## the row.
##
## THE CHOICE DRIVES THE TRACER AS WELL AS THE ARMOUR, which is the whole reason
## it is one setting and not two. The bolt is DERIVED from the chip rather than
## picked separately: a saturated, brightened version of it, because the two
## exist for different jobs — a chip is read against a HUD and a tracer against a
## map, and the note on `bolts` is that the Empire's grey plate would make a grey
## tracer no tracer at all. Deriving keeps them recognisably the same colour
## while letting the tracer stay legible.
const TEAM_TINTS: Array[Dictionary] = [
	{"name": "FACTION", "color": Color(0, 0, 0, 0)},   # 0 = leave it alone
	{"name": "BLUE", "color": Color(0.35, 0.55, 1.00)},
	{"name": "RED", "color": Color(1.00, 0.34, 0.28)},
	{"name": "GREEN", "color": Color(0.36, 0.86, 0.42)},
	{"name": "PURPLE", "color": Color(0.66, 0.42, 1.00)},
	{"name": "YELLOW", "color": Color(0.98, 0.82, 0.22)},
	{"name": "ORANGE", "color": Color(1.00, 0.56, 0.18)},
	{"name": "CYAN", "color": Color(0.32, 0.86, 0.95)},
	{"name": "PINK", "color": Color(1.00, 0.45, 0.75)},
	{"name": "WHITE", "color": Color(0.90, 0.92, 0.96)},
	{"name": "BLACK", "color": Color(0.24, 0.25, 0.28)},
]


## The tracer a chosen chip fires. Pushed to full saturation and lifted in value,
## because a tracer is a thin bright line against terrain and the chip value that
## reads on a HUD is too dark to carry — BLACK especially, which as a bolt would
## be nothing at all, and which is why this has a value FLOOR rather than a
## multiplier.
static func tint_bolt(chip: Color) -> Color:
	var h := chip.h
	var sat: float = maxf(chip.s, 0.55)
	var val: float = maxf(chip.v, 0.85)
	return Color.from_hsv(h, sat, val)


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

## CUSTOM OPENS THE WHOLE ARMOURY; FACTION HANDS YOU A CLASS AS AUTHORED.
##
## Mirrored from `GameState.class_mode` exactly as the two above are mirrored,
## and DEFAULT FALSE so `kit_rules` — which runs under `--script` with no
## autoloads — keeps asking about the authored, restricted catalogue.
##
## The per-kit `primaries`/`secondaries` lists exist to make a CLASS mean
## something, and they did that job when the CLASS row offered five archetypes.
## Now that it offers all thirty-two of a universe's characters, the character IS
## the meaning — its body, its physique and the guns it walks in with — and the
## restriction was only stopping a player from building the thing they had
## already been handed. Measured before this: Star Wars reached 30 of 76
## primaries and Halo 17, with the Wookiee able to hold TWO and the Unggoy three.
##
## What it does NOT relax is `"kit"` exclusivity. A saber, a bowcaster, a thermal
## holo belong to their owner in every mode, because those are MECHANISM — a
## saber needs the guard and a Force power needs the button — where a per-kit
## list is only balance. That is the same line `royale_items` already draws.
static var custom_pool := false


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
	# --- THE FACTION GUNS -----------------------------------------------------
	# Added to the SHOP as well as to the rosters: a weapon that only a faction
	# class can hold is a weapon most players never see, and every one of these
	# is a gun a custom build would want. Costs sit against the existing ladder
	# rather than being invented — a carbine is carbine money.
	{"class": Weapon.Class.DC15S, "cost": 45},
	{"class": Weapon.Class.DC17M, "cost": 60},
	{"class": Weapon.Class.DC15X, "cost": 90},
	{"class": Weapon.Class.E5, "cost": 35},
	{"class": Weapon.Class.E5S, "cost": 85},
	{"class": Weapon.Class.DROIDEKA_TWIN, "cost": 85},
	{"class": Weapon.Class.SONIC_BLASTER, "cost": 70},
	{"class": Weapon.Class.E11, "cost": 45},
	{"class": Weapon.Class.DLT19, "cost": 75},
	{"class": Weapon.Class.DLT20A, "cost": 80},
	{"class": Weapon.Class.FLAMETHROWER, "cost": 65},
	{"class": Weapon.Class.A280C, "cost": 55},
	{"class": Weapon.Class.CR2, "cost": 45},
	{"class": Weapon.Class.DH447, "cost": 90},
	{"class": Weapon.Class.M319, "cost": 75, "universe": Universe.HALO},
	# APPENDED, so no index below moved. Both of these are here because a
	# faction preset already NAMED them as a primary while they were sold only
	# as sidearms (or not at all): weapon_index answers NO_PRIMARY for a gun it
	# cannot find, so the Death Trooper and the Brute Stalker were both
	# deploying with the free starter pistol and no error anywhere.
	{"class": Weapon.Class.E11D, "cost": 60},
	{"class": Weapon.Class.SPIKER, "cost": 50, "universe": Universe.HALO},
	# THE LIGHT MACHINE GUNS, appended like everything else (house rule 8).
	#
	# Sold to ANYBODY, and deliberately not kit-locked the way the T-21 and the
	# rocket tube are. Those two are the Wookiee's because they are the heaviest
	# things a body can carry; an LMG is an ordinary primary with an ordinary
	# trade — it is the most controllable gun in the game while braced and the
	# worst one on the move — and a category only one class can reach is a
	# category most players never meet.
	#
	# Priced above the rifles they out-shoot and below the sniper, because what
	# they buy is SUSTAIN and not reach.
	{"class": Weapon.Class.M739_SAW, "cost": 70, "universe": Universe.HALO},
	{"class": Weapon.Class.DLT19D, "cost": 75},
	{"class": Weapon.Class.RT97C, "cost": 85},
	{"class": Weapon.Class.GAUSS_CANNON, "cost": 85, "universe": Universe.WARHAMMER},
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
	# The ARC trooper's pistol and the death trooper's machine pistol, both of
	# which are sidearms that a build might genuinely prefer to a primary.
	{"class": Weapon.Class.DC17, "cost": 30},
	{"class": Weapon.Class.SE14R, "cost": 35},
	{"class": Weapon.Class.SPIKER, "cost": 35, "universe": Universe.HALO},
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
	SMOKE_LAUNCHER,
	# --- SUSTAINED (slot 3) ---------------------------------------------------
	# Two new MECHANISMS, appended so no existing index moves. Everything else
	# that belongs in slot 3 already existed as a deployable or a toggle (the
	# cloak, the barrier) and simply moved house.
	OVERSHIELD, FURY,
	# --- THE ROSTER REBUILD ---------------------------------------------------
	# Aliases, mostly: a rally is a fury, a deployable cover is a barrier, a set
	# of Geonosian wings is a jetpack. Two are genuinely new mechanisms —
	# BIOFOAM, the game's only instant heal since the medkits went, and the
	# DEFLECTOR, which is the Droideka's and the Jackal's shield: an overshield
	# you cannot shoot out of.
	BIOFOAM, DEFLECTOR, RALLY, SHOCK_TRAP, DEPLOY_COVER, WINGS, VISR,
	THERMAL_DET, PULSE_SCAN }
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
	{"name": "RED THIRST", "cost": 25, "universe": Universe.WARHAMMER, "like": Gadget.FURY,
		"blurb": "The thirst takes you: faster, tougher, and a heavier swing. 8s"},
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
	{"name": "WAAAGH!", "cost": 25, "universe": Universe.WARHAMMER, "like": Gadget.FURY,
		"blurb": "Roar. Faster, harder to put down, and a heavier swing. 8s"},
	{"name": "GROT GUNNER", "cost": 65, "universe": Universe.WARHAMMER, "like": Gadget.TURRET,
		"blurb": "Drop a grot on a gun that fights for you until it's destroyed"},
	{"name": "KUSTOM FORCE FIELD", "cost": 50, "universe": Universe.WARHAMMER, "like": Gadget.SHIELD,
		"blurb": "Toggle a barrier that stops incoming fire. Shoot through it, but no aiming"},
	{"name": "ROKKIT PACK", "cost": 45, "universe": Universe.WARHAMMER, "like": Gadget.JETPACK,
		"blurb": "Hold the gadget button to fly. Fuel burns fast, refills on the ground"},
	{"name": "STIKKBOMB", "cost": 25, "universe": Universe.WARHAMMER, "like": Gadget.GRENADE_FRAG,
		"blurb": "Lob a stikkbomb: bounces, 2s fuse, heavy splash. 6s between throws"},
	# THIS ROW HAS TO SIT HERE, because SMOKE_LAUNCHER sits here in the enum.
	# GADGETS is indexed BY the Gadget enum — gadget_action does GADGETS[id] —
	# so a row added to the end while its enum entry went in the middle silently
	# shifts every row below it by one. That is exactly what had happened: twelve
	# gadgets, OVERSHIELD through PULSE_SCAN, each resolved to the NEXT one's
	# behaviour, cooldown, price and HUD name. A thermal detonator was a scan
	# pulse, deployable cover was a set of Geonosian wings, and BATTLE FURY was
	# a medkit. Nothing errored, because every one of them is a valid gadget.
	{"name": "SMOKE LAUNCHER", "cost": 20, "universe": Universe.WARHAMMER, "like": Gadget.GRENADE_SMOKE,
		"blurb": "Lob smoke: blinds the area, nothing sees through it. 7s"},
	{"name": "OVERSHIELD", "cost": 55, "universe": ANY_UNIVERSE,
		"blurb": "Raise a shell that eats damage before your health does. 8s"},
	{"name": "BATTLE FURY", "cost": 45, "universe": ANY_UNIVERSE,
		"blurb": "Faster, tougher and a heavier swing while it lasts. 8s"},
	# --- THE FACTION GADGETS --------------------------------------------------
	{"name": "BIOFOAM", "cost": 35, "universe": ANY_UNIVERSE,
		"blurb": "Slam a canister of foam into yourself. Instant heal, then a long wait"},
	{"name": "DEFLECTOR SHIELD", "cost": 60, "universe": ANY_UNIVERSE,
		"blurb": "Raise a bubble that eats everything. You cannot fire out of it. 6s"},
	{"name": "RALLY", "cost": 40, "universe": ANY_UNIVERSE, "like": Gadget.FURY,
		"blurb": "Call the advance: faster, tougher, and a heavier swing. 8s"},
	{"name": "SHOCK TRAP", "cost": 35, "universe": Universe.STAR_WARS,
		"like": Gadget.SCAN_DART,
		"blurb": "A dart that marks everyone near where it sticks, through walls"},
	{"name": "DEPLOYABLE COVER", "cost": 50, "universe": ANY_UNIVERSE,
		"like": Gadget.SHIELD,
		"blurb": "Toggle a barrier that stops incoming fire. Shoot through it, but no aiming"},
	{"name": "GEONOSIAN WINGS", "cost": 40, "universe": Universe.STAR_WARS,
		"like": Gadget.JETPACK,
		"blurb": "Hold the gadget button to fly. Wingbeats burn fast, refill on the ground"},
	{"name": "VISR", "cost": 30, "universe": Universe.HALO, "like": Gadget.SCAN_DART,
		"blurb": "Light everyone up for your fireteam, through walls"},
	{"name": "THERMAL DETONATOR", "cost": 30, "universe": Universe.STAR_WARS,
		"like": Gadget.GRENADE_FRAG,
		"blurb": "The classic. Bounces, sticks to nothing, and levels a doorway"},
	{"name": "PULSE SCAN", "cost": 30, "universe": ANY_UNIVERSE, "like": Gadget.SCAN_DART,
		"blurb": "A sweep off your own position that marks everyone near you"},
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
	# THE SUSTAINED PAIR. Long cooldowns on purpose: what you are buying is a
	# WINDOW, and a window you can open every few seconds is just a passive.
	Gadget.OVERSHIELD: 22.0,
	Gadget.FURY: 20.0,
	# BIOFOAM is a long wait on purpose: health already regenerates on its own
	# (see Player._update_regen), so what this buys is the ONE moment mid-fight
	# where waiting is not an option, and it must never be a way to out-sustain
	# somebody shooting you.
	Gadget.BIOFOAM: 26.0,
	Gadget.DEFLECTOR: 24.0,
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
		"gadgets": [
			Gadget.NONE, Gadget.ROTARY, Gadget.TURRET, Gadget.MORTAR,
			Gadget.GRENADE_FRAG, Gadget.GRENADE_STICKY],
		"gadget_slots": 3,
		# The THIRD slot: what this class puts UP and keeps.
		"sustain": [Gadget.NONE, Gadget.OVERSHIELD, Gadget.FURY],
		"secondary_mods": [SecondaryMod.NONE, SecondaryMod.SCOPE, SecondaryMod.COOLING],
		"armor": [0, 1, 2, 3],
		"default_armor": 1,
		"starter": Weapon.Class.SOLDIER,
		"style": CharacterModel.Style.CLONE,
	},
	{
		"name": "MANDALORIAN",
		"blurb": "Flies, grapples, fires wrist rockets, and the only one who dual-wields",
		"gadgets": [
			Gadget.NONE, Gadget.JETPACK, Gadget.CABLE, Gadget.WRIST_ROCKET,
			Gadget.GRENADE_FRAG, Gadget.GRENADE_STICKY],
		"gadget_slots": 3,
		# The THIRD slot: what this class puts UP and keeps.
		"sustain": [Gadget.NONE, Gadget.CLOAK, Gadget.OVERSHIELD],
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
		"gadgets": [
			Gadget.NONE, Gadget.FORCE_PUSH, Gadget.FORCE_PULL, Gadget.FORCE_LEAP,
			Gadget.FORCE_LIGHTNING, Gadget.DASH, Gadget.GRENADE_FRAG,
			Gadget.GRENADE_STICKY],
		"gadget_slots": 3,
		# The THIRD slot: what this class puts UP and keeps.
		"sustain": [Gadget.NONE, Gadget.FURY, Gadget.CLOAK],
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
		"gadgets": [
			Gadget.NONE, Gadget.GRENADE_FRAG, Gadget.GRENADE_STICKY],
		"gadget_slots": 3,
		# The THIRD slot: what this class puts UP and keeps.
		"sustain": [Gadget.NONE, Gadget.FURY, Gadget.SHIELD],
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
		"gadgets": [
			Gadget.NONE, Gadget.DASH, Gadget.GRENADE_FRAG, Gadget.GRENADE_STICKY,
			Gadget.GRENADE_SMOKE],
		"gadget_slots": 3,
		# The THIRD slot: what this class puts UP and keeps.
		"sustain": [Gadget.NONE, Gadget.CLOAK, Gadget.FURY],
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
		"gadgets": [
			Gadget.NONE, Gadget.SENTRY_TURRET, Gadget.JET_PACK, Gadget.THRUSTER_PACK,
			Gadget.FRAG_GRENADE_UNSC, Gadget.PLASMA_GRENADE],
		"gadget_slots": 3,
		# The THIRD slot: what this class puts UP and keeps.
		"sustain": [Gadget.NONE, Gadget.OVERSHIELD, Gadget.BUBBLE_SHIELD],
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
		"gadgets": [
			Gadget.NONE, Gadget.THRUSTER_PACK, Gadget.TRACKER_DART,
			Gadget.TARGET_DESIGNATOR, Gadget.FRAG_GRENADE_UNSC],
		"gadget_slots": 3,
		# The THIRD slot: what this class puts UP and keeps.
		"sustain": [Gadget.NONE, Gadget.ACTIVE_CAMO, Gadget.OVERSHIELD],
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
		"gadgets": [
			Gadget.NONE, Gadget.THRUSTER_PACK, Gadget.GRAV_LIFT,
			Gadget.PLASMA_CANNON, Gadget.PLASMA_GRENADE],
		"gadget_slots": 3,
		# The THIRD slot: what this class puts UP and keeps.
		"sustain": [Gadget.NONE, Gadget.ACTIVE_CAMO, Gadget.OVERSHIELD],
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
		"gadgets": [
			Gadget.NONE, Gadget.PLASMA_GRENADE, Gadget.GRAV_LIFT,
			Gadget.THRUSTER_PACK],
		"gadget_slots": 3,
		# The THIRD slot: what this class puts UP and keeps.
		"sustain": [Gadget.NONE, Gadget.OVERSHIELD, Gadget.FURY],
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
		"gadgets": [
			Gadget.NONE, Gadget.PLASMA_CANNON, Gadget.PLASMA_GRENADE],
		"gadget_slots": 3,
		# The THIRD slot: what this class puts UP and keeps.
		"sustain": [Gadget.NONE, Gadget.FURY, Gadget.OVERSHIELD],
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
		"gadgets": [
			Gadget.NONE, Gadget.AUSPEX_SCAN, Gadget.ORBITAL_BOMBARDMENT,
			Gadget.ASSAULT_CANNON, Gadget.KRAK_GRENADE, Gadget.MELTA_BOMB],
		"gadget_slots": 3,
		# The THIRD slot: what this class puts UP and keeps.
		"sustain": [Gadget.NONE, Gadget.IRON_HALO, Gadget.OVERSHIELD],
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
		"gadgets": [
			Gadget.NONE, Gadget.JUMP_PACK, Gadget.KRAK_GRENADE, Gadget.MELTA_BOMB],
		"gadget_slots": 3,
		# The THIRD slot: what this class puts UP and keeps.
		"sustain": [Gadget.NONE, Gadget.RED_THIRST, Gadget.IRON_HALO],
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
		"gadgets": [
			Gadget.NONE, Gadget.TESLA_ARC, Gadget.TRANSLOCATION,
			Gadget.CANOPTEK_SPYDER],
		"gadget_slots": 3,
		# The THIRD slot: what this class puts UP and keeps.
		"sustain": [Gadget.NONE, Gadget.PHASE_SHIFT, Gadget.OVERSHIELD],
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
		"gadgets": [
			Gadget.NONE, Gadget.GROT_GUNNER, Gadget.ROKKIT_PACK, Gadget.STIKKBOMB,
			Gadget.SMOKE_LAUNCHER],
		"gadget_slots": 3,
		# The THIRD slot: what this class puts UP and keeps.
		"sustain": [Gadget.NONE, Gadget.WAAAGH, Gadget.KUSTOM_FORCE_FIELD],
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
	GADGET, GADGET2, GADGET3, ARMOR, SQUAD, SQUAD_SKILL,
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
	{"name": "GADGETS", "rows": [Row.GADGET, Row.GADGET2, Row.GADGET3]},
	{"name": "ARMOUR", "rows": [Row.ARMOR]},
	{"name": "AI SQUAD", "rows": [Row.SQUAD, Row.SQUAD_SKILL]},
]


var kit := Kit.CLONE   # index into KITS; picks what the rest of this may be
## What the preset this was built from was CALLED, or "" for a shopped build.
## Set by `_build_from` off the row's own `name`, which it used to throw away —
## so a Bot can say what it deployed as without holding an index into a table
## that gets appended to. A shopped loadout has no name because it is not one of
## anything: it is whatever that player bought this life.
var build_name := ""
var weapon := 0        # index into WEAPONS (NO_PRIMARY = sidearm only)
## An explicit primary Weapon.Class that overrides the WEAPONS[weapon] lookup,
## or -1 to use that lookup. This is how a FIXED faction preset (Conquest) can
## deploy a gun the ORDINARY shop does not sell — the wrist cannon — without
## adding it to WEAPONS and shifting every index the buy screen and BOT_BUILDS
## rely on. Only faction builds set it; the buy screen never touches it.
var primary_override := -1
## WHICH AUTHORED CHARACTER THIS BUILD STARTED FROM — an index into
## `custom_classes()`, or -1 for a build that was never given one (a royale drop,
## a bot's shop roll, anything built before a class was chosen).
##
## It is what the CLASS row on the buy screen now walks. `kit` is still the thing
## the allow-lists are keyed to and is DERIVED from this: a character states its
## own kit, so choosing one sets both.
var character := -1
var secondary := 0     # index into SECONDARIES
var secondary_mod := SecondaryMod.NONE
var gadget := 0        # index into GADGETS, slot 0, on the GADGET 1 control
## The second gadget slot, every class has one now: it is driven by the GADGET 2
## control (keyboard G, pad LB by default), an ordinary rebindable binding like
## slot 0. Grenades are gadgets, so this is also where a grenade goes.
var gadget2 := 0
var gadget3 := 0
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

## THE UNIT'S PHYSIQUE. How fast it moves, how much it can take, how high it
## jumps and HOW BIG IT IS. Until these existed, speed and health were per-KIT
## only — so every faction class on the default kit was mechanically the same
## body, and a Droideka moved exactly like a Scout Trooper. Worse, the model's
## `bulk` varied from 0.62 to 1.62 while the CAPSULE never did, so an Ewok
## floated inside an invisible trooper-sized cylinder and a Wookiee was 45%
## wider than the thing you actually had to hit.
##
## An authored faction class states its physique OUTRIGHT and that REPLACES the
## kit's multiplier rather than stacking on it. A Royal Guard is not "a Force
## adept, but slower" — it is a wall, and a table you have to multiply out in
## your head is a table nobody can balance from. 0.0 means "not stated", which
## is what every SHOPPED build leaves them at, so the buy screen is unchanged.
var unit_speed := 0.0
var unit_health := 0.0
var unit_jump := 0.0
var unit_stature := 0.0


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
		"sight": Sight.THERMAL, "armor": 0, "gadget3": Gadget.CLOAK},    # 85+30+20+45
	{"name": "SLAVER", "kit": Kit.TRANDOSHAN, "weapon": 1, "secondary": 2,
		"sight": Sight.THERMAL, "armor": 1, "gadget": Gadget.DASH,
		"gadget2": Gadget.GRENADE_SMOKE},                              # 40+20+30+20
	# The Wookiee fields both of its guns, because they play nothing alike: one
	# holds a lane behind the barrier, the other deletes whatever is behind cover.
	# `secondary` 5 is the bowcaster, which is the only sidearm either may hold —
	# get that index wrong and the kit_rules test says so.
	{"name": "BULWARK", "kit": Kit.WOOKIEE, "weapon": 9, "secondary": 5,
		"sight": Sight.NONE, "armor": 2, "gadget3": Gadget.SHIELD},     # 80+25+50
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
		"gadget3": Gadget.BUBBLE_SHIELD},                               # 60+25+50
	{"name": "ODST SCOUT", "kit": Kit.ODST, "primary": Weapon.Class.M7_SMG,
		"sidearm": Weapon.Class.M6D, "sight": Sight.HOLO, "armor": 0,
		"gadget3": Gadget.ACTIVE_CAMO},                                 # 40+20+20+45
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
		"gadget3": Gadget.ACTIVE_CAMO, "gadget2": Gadget.PLASMA_GRENADE},  # 60+25+45+35
	{"name": "GRUNT HEAVY", "kit": Kit.UNGGOY, "primary": Weapon.Class.FUEL_ROD,
		"sidearm": Weapon.Class.PLASMA_PISTOL, "sight": Sight.NONE, "armor": 0,
		"gadget2": Gadget.PLASMA_GRENADE},                             # 105+20+35
	{"name": "BRUTE CHIEFTAIN", "kit": Kit.JIRALHANAE, "primary": Weapon.Class.GRAV_HAMMER,
		"sidearm": Weapon.Class.MAULER, "sight": Sight.NONE, "armor": 2,
		"gadget3": Gadget.BUBBLE_SHIELD},                               # 70+30+25+50
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
		"gadget3": Gadget.RED_THIRST},                                  # 75+60+25
	# --- WARHAMMER: Necrons ---------------------------------------------------
	{"name": "NECRON WARRIOR", "kit": Kit.NECRON, "primary": Weapon.Class.GAUSS_FLAYER,
		"sidearm": Weapon.Class.GAUSS_PISTOL, "sight": Sight.RED_DOT, "armor": 2,
		"cooling": true},                                              # 45+15+25+20
	{"name": "IMMORTAL", "kit": Kit.NECRON, "primary": Weapon.Class.GAUSS_BLASTER,
		"sidearm": Weapon.Class.GAUSS_PISTOL, "sight": Sight.HOLO, "armor": 3,
		"grip": true},                                                 # 60+20+60+20
	{"name": "DEATHMARK", "kit": Kit.NECRON, "primary": Weapon.Class.SYNAPTIC_DISINTEGRATOR,
		"sidearm": Weapon.Class.GAUSS_PISTOL, "sight": Sight.SCOPE, "armor": 1,
		"gadget3": Gadget.PHASE_SHIFT},                                 # 85+25+45
	{"name": "LYCHGUARD", "kit": Kit.NECRON, "primary": Weapon.Class.WARSCYTHE,
		"sidearm": Weapon.Class.GAUSS_PISTOL, "sight": Sight.NONE, "armor": 2,
		"gadget": Gadget.TRANSLOCATION, "gadget2": Gadget.TESLA_ARC},  # 65+25+35+50
	# --- WARHAMMER: Orks ------------------------------------------------------
	{"name": "SHOOTA BOY", "kit": Kit.ORK, "primary": Weapon.Class.SHOOTA,
		"sidearm": Weapon.Class.SLUGGA, "sight": Sight.NONE, "armor": 2,
		"gadget3": Gadget.WAAAGH, "gadget2": Gadget.STIKKBOMB},         # 45+25+25+25
	{"name": "BURNA BOY", "kit": Kit.ORK, "primary": Weapon.Class.BURNA,
		"sidearm": Weapon.Class.SLUGGA, "sight": Sight.NONE, "armor": 2,
		"gadget3": Gadget.KUSTOM_FORCE_FIELD},                          # 55+25+50
	{"name": "TANKBUSTA", "kit": Kit.ORK, "primary": Weapon.Class.ROKKIT_LAUNCHA,
		"sidearm": Weapon.Class.SLUGGA, "sight": Sight.NONE, "armor": 2,
		"gadget2": Gadget.STIKKBOMB},                                  # 105+25+25
	{"name": "ORK NOB", "kit": Kit.ORK, "primary": Weapon.Class.POWER_KLAW,
		"sidearm": Weapon.Class.SLUGGA, "sight": Sight.NONE, "armor": 3,
		"gadget3": Gadget.WAAAGH, "style": CharacterModel.Style.ORK_NOB},  # 70+60+25
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
	# These eight were authored before the Empire and Rebel rosters, and it
	# showed: several carried ONE ability where every later class carries three,
	# so the Clone Wars sides were quietly the weakest thing to play. They also
	# threw a "FRAG GRENADE" — Star Wars has a noun for that, and it is the same
	# gadget at the same price (THERMAL_DET is an alias of GRENADE_FRAG), so
	# this costs nothing and is what the HUD should have said all along.
	#
	# EVERY CLASS BELOW ALSO STATES A PHYSIQUE (unit_speed / unit_health /
	# unit_jump / unit_stature — see the vars, near `style`). Before it existed,
	# those numbers were per-KIT only, so all sixteen Clone Wars classes on the
	# default kit were the SAME BODY: a Droideka moved at exactly a Scout
	# Trooper's pace, and a B1 took exactly as much killing as a Clone Commando.
	# The armour frame was the only thing separating any of them, and it is a
	# purchase, not a character. The CLONE TROOPER is the yardstick and states
	# nothing — it is 1.0 everywhere by definition, and every other number in
	# the roster is read against it.
	#
	# EVERY CLASS BELOW ALSO NAMES ITS SIDEARM. `secondary: 0` is the DL-44, and
	# it was on all thirty-two Star Wars classes: a B1 battle droid, a Geonosian
	# and an Imperial Royal Guard all drew Han Solo's pistol. Halo and Warhammer
	# each hand every faction its own free sidearm (M6D, plasma pistol, bolt
	# pistol, gauss pistol, slugga) and Star Wars simply never did, because it
	# had one faction when index 0 was chosen and now has four. Republic clones
	# carry the DC-17 hand blaster, the Separatists the SE-14, the Empire the
	# SE-14r and the Rebels the DH-17 — and the DL-44 stays where it belongs,
	# with the Rebel Pathfinder. Faction presets are authored classes rather
	# than shop builds, so the prices on those rows do not apply to them.
	{"name": "CLONE TROOPER", "weapon": 2, "sight": Sight.RED_DOT, "cooling": true,
		"sidearm": Weapon.Class.DC17, "armor": 1, "gadget2": Gadget.THERMAL_DET,
		"gadget3": Gadget.OVERSHIELD, "style": CharacterModel.Style.CLONE},
	{"name": "CLONE ENGINEER", "weapon": 6, "grip": true,
		"sidearm": Weapon.Class.DC17,
		"armor": 2, "gadget": Gadget.TURRET, "gadget2": Gadget.GRENADE_SMOKE,
		"gadget3": Gadget.DEPLOY_COVER, "unit_speed": 1.03, "unit_health": 0.95,
		"style": CharacterModel.Style.CLONE_ENGINEER},
	{"name": "CLONE HEAVY", "weapon": 9, "foregrip": true, "sight": Sight.RED_DOT,
		"sidearm": Weapon.Class.DC17, "armor": 3, "gadget": Gadget.MORTAR,
		"gadget2": Gadget.THERMAL_DET, "gadget3": Gadget.SHIELD,
		"unit_speed": 0.88, "unit_health": 1.25, "unit_jump": 0.90,
		"unit_stature": 1.06, "style": CharacterModel.Style.CLONE_HEAVY},
	# TWO DC-17s, which is the ARC trooper's own silhouette and what the DUAL mod
	# was always for. Paired DL-44s were somebody else's character entirely.
	{"name": "CLONE SPECIALIST", "weapon": 2, "sight": Sight.RED_DOT, "grip": true,
		"sidearm": Weapon.Class.DC17, "secondary_mod": SecondaryMod.DUAL, "armor": 1,
		"gadget": Gadget.SCAN_DART, "gadget2": Gadget.THERMAL_DET,
		"gadget3": Gadget.CLOAK, "unit_speed": 1.10, "unit_health": 0.90,
		"unit_jump": 1.06, "style": CharacterModel.Style.CLONE_ARC},
	# SEPARATIST -------------------------------------------------------------
	# A B1 IS SUPPOSED TO DIE. It is the only unit in the game built around
	# being outclassed: thin, a little slow, and softer than anything else that
	# carries a rifle. That is the joke and it is also the fantasy — the side
	# that wins with a B1 wins because there were more of them.
	{"name": "BATTLE DROID", "weapon": 2, "sight": Sight.HOLO, "foregrip": true,
		"sidearm": Weapon.Class.REVOLVER, "armor": 0, "gadget2": Gadget.THERMAL_DET,
		"gadget3": Gadget.OVERSHIELD, "unit_speed": 0.96, "unit_health": 0.84,
		"unit_stature": 0.94, "style": CharacterModel.Style.B1},
	# No grenade, on purpose: a B2 has no hands free for one. Everything it
	# fights with is bolted to its arms — and it walks like it. Slowest thing
	# on the Separatist roster that is not a Droideka, and the hardest to drop.
	{"name": "SUPER BATTLE DROID", "primary_override": Weapon.Class.WRIST_CANNON,
		"sidearm": Weapon.Class.REVOLVER, "armor": 3,
		"gadget": Gadget.WRIST_ROCKET, "gadget3": Gadget.SHIELD,
		"unit_speed": 0.80, "unit_health": 1.60, "unit_jump": 0.75,
		"unit_stature": 1.15, "style": CharacterModel.Style.B2},
	# A FORCE kit for the guard, the double-jump and the intrinsic dash; the
	# electrostaff (primary_override, a melee weapon the shop does not sell) raises
	# that same guard, drawn as a shield in the off hand.
	{"name": "MAGNA GUARD", "kit": Kit.FORCE, "primary_override": Weapon.Class.STAFF,
		"sidearm": Weapon.Class.REVOLVER, "armor": 2,
		"gadget": Gadget.DASH, "gadget2": Gadget.GRENADE_SMOKE,
		"gadget3": Gadget.FURY, "unit_speed": 1.15, "unit_health": 1.05,
		"unit_stature": 1.04, "style": CharacterModel.Style.MAGNAGUARD},
	{"name": "TACTICAL DROID", "weapon": NO_PRIMARY,
		"sidearm": Weapon.Class.REVOLVER,
		"secondary_mod": SecondaryMod.SCOPE, "armor": 1,
		"gadget": Gadget.MORTAR, "gadget2": Gadget.THERMAL_DET,
		"gadget3": Gadget.RALLY, "unit_speed": 0.95, "unit_health": 0.85,
		"unit_stature": 1.02, "style": CharacterModel.Style.TACTICAL},

	# HALO — UNSC (8-11) ------------------------------------------------------
	# THE PHYSIQUE CEILING IS 1.16 (about 2.1 m) AND IT IS NOT A TASTE
	# DECISION. Stature scales the collision capsule, and every map in the game
	# was laid out around a 1.8 m body — a unit tall enough to be a real Spartan
	# is also a unit that cannot get under things the level says are passable,
	# and "the Mega Nob is stuck in the doorway" is a worse bug than "the Mega
	# Nob is a little short". Crouch still gets anybody under anything.
	{"name": "SPARTAN-II", "kit": Kit.SPARTAN, "primary": Weapon.Class.MA5B,
		"sidearm": Weapon.Class.M6D, "sight": Sight.RED_DOT, "armor": 2,
		"gadget3": Gadget.BUBBLE_SHIELD, "gadget2": Gadget.FRAG_GRENADE_UNSC,
		"unit_speed": 1.05, "unit_health": 1.40, "unit_stature": 1.12,
		"style": CharacterModel.Style.SPARTAN},
	{"name": "SPARTAN HEAVY", "kit": Kit.SPARTAN, "primary": Weapon.Class.M247_HMG,
		"sidearm": Weapon.Class.M6D, "cooling": true, "armor": 3,
		"gadget": Gadget.SENTRY_TURRET, "gadget2": Gadget.FRAG_GRENADE_UNSC,
		# 1.55 put this on 271 HP behind a gun that empties a trooper in 0.39 s —
		# more health than an Elite Ultra and the hardest trade in the game, on a
		# LINE class. A Spartan Heavy should be the tough one on its own side, not
		# tougher than the Covenant's heavies as well.
		"unit_speed": 0.94, "unit_health": 1.28, "unit_jump": 0.90,
		"unit_stature": 1.14, "style": CharacterModel.Style.SPARTAN},
	{"name": "ODST", "kit": Kit.ODST, "primary": Weapon.Class.M7_SMG,
		"sidearm": Weapon.Class.M6D, "sight": Sight.HOLO, "armor": 0,
		"gadget3": Gadget.ACTIVE_CAMO, "gadget2": Gadget.FRAG_GRENADE_UNSC,
		"unit_speed": 1.12, "unit_health": 0.95, "unit_jump": 1.08,
		"style": CharacterModel.Style.ODST},
	{"name": "MARINE MARKSMAN", "kit": Kit.ODST, "primary": Weapon.Class.M392_DMR,
		"sidearm": Weapon.Class.M6D, "grip": true, "armor": 1,
		"gadget": Gadget.TRACKER_DART, "gadget2": Gadget.FRAG_GRENADE_UNSC,
		"unit_speed": 1.00, "unit_health": 0.90, "unit_stature": 0.98,
		"style": CharacterModel.Style.MARINE},
	# HALO — Covenant (12-15) -------------------------------------------------
	{"name": "ELITE MINOR", "kit": Kit.SANGHEILI, "primary": Weapon.Class.PLASMA_RIFLE,
		"sidearm": Weapon.Class.PLASMA_PISTOL, "sight": Sight.HOLO, "armor": 1,
		"gadget": Gadget.THRUSTER_PACK, "gadget2": Gadget.PLASMA_GRENADE,
		"unit_speed": 1.08, "unit_health": 1.25, "unit_stature": 1.10,
		"style": CharacterModel.Style.ELITE},
	{"name": "ELITE ZEALOT", "kit": Kit.SANGHEILI, "primary": Weapon.Class.ENERGY_SWORD,
		"sidearm": Weapon.Class.PLASMA_PISTOL, "armor": 2,
		"gadget3": Gadget.ACTIVE_CAMO, "gadget2": Gadget.PLASMA_GRENADE,
		"unit_speed": 1.14, "unit_health": 1.35, "unit_stature": 1.12,
		"style": CharacterModel.Style.ELITE},
	# A GRUNT IS KNEE-HIGH AND EVERYONE KNOWS IT. It was standing eye to eye
	# with a Spartan, which took the joke out of the only comedy unit in Halo
	# and, more to the point, meant the thing carrying the fuel rod was as easy
	# to hit as the thing carrying an assault rifle.
	{"name": "GRUNT HEAVY", "kit": Kit.UNGGOY, "primary": Weapon.Class.FUEL_ROD,
		"sidearm": Weapon.Class.PLASMA_PISTOL, "armor": 0,
		"gadget": Gadget.GRAV_LIFT, "gadget2": Gadget.PLASMA_GRENADE,
		"unit_speed": 1.02, "unit_health": 0.72, "unit_stature": 0.70,
		"style": CharacterModel.Style.GRUNT},
	# The LEAP is not decoration: a Chieftain carries a hammer with four metres
	# of reach and walks at x0.78, so without something that closes ground it
	# could be kited by literally every rifle in the game forever. The
	# leap-and-slam is also the thing everyone remembers a Chieftain doing.
	{"name": "BRUTE CHIEFTAIN", "kit": Kit.JIRALHANAE, "primary": Weapon.Class.GRAV_HAMMER,
		"sidearm": Weapon.Class.MAULER, "armor": 3, "gadget": Gadget.GRAV_LIFT,
		"gadget3": Gadget.BUBBLE_SHIELD, "gadget2": Gadget.PLASMA_GRENADE,
		"unit_speed": 0.88, "unit_health": 1.70, "unit_jump": 0.85,
		"unit_stature": 1.16, "style": CharacterModel.Style.BRUTE},

	# WARHAMMER — Ultramarines (16-19) ----------------------------------------
	# AN ASTARTES IS NOT A MAN IN ARMOUR. Every one of these is taller, heavier
	# and harder to stop than anything either other universe fields at the same
	# job, and the jump-pack classes are the only ones that also move well — a
	# Space Marine's speed is supposed to come out of a rocket, not out of legs.
	{"name": "TACTICAL MARINE", "kit": Kit.ULTRAMARINE, "primary": Weapon.Class.BOLTER,
		"sidearm": Weapon.Class.BOLT_PISTOL, "sight": Sight.RED_DOT, "armor": 2,
		"gadget3": Gadget.IRON_HALO, "gadget2": Gadget.KRAK_GRENADE,
		"unit_speed": 0.92, "unit_health": 1.35, "unit_jump": 0.95,
		"unit_stature": 1.14, "style": CharacterModel.Style.ULTRAMARINE},
	{"name": "DEVASTATOR", "kit": Kit.ULTRAMARINE, "primary": Weapon.Class.HEAVY_BOLTER,
		"sidearm": Weapon.Class.BOLT_PISTOL, "cooling": true, "armor": 3,
		"gadget": Gadget.ORBITAL_BOMBARDMENT, "gadget2": Gadget.KRAK_GRENADE,
		"unit_speed": 0.82, "unit_health": 1.60, "unit_jump": 0.85,
		"unit_stature": 1.16, "style": CharacterModel.Style.ULTRAMARINE},
	{"name": "STERNGUARD", "kit": Kit.ULTRAMARINE, "primary": Weapon.Class.PLASMA_GUN,
		"sidearm": Weapon.Class.PLASMA_PISTOL_40K, "sight": Sight.HOLO, "armor": 2,
		"gadget": Gadget.AUSPEX_SCAN, "gadget2": Gadget.MELTA_BOMB,
		"unit_speed": 0.92, "unit_health": 1.40, "unit_stature": 1.14,
		"style": CharacterModel.Style.ULTRAMARINE},
	{"name": "VANGUARD VETERAN", "kit": Kit.ULTRAMARINE, "primary": Weapon.Class.POWER_SWORD,
		"sidearm": Weapon.Class.BOLT_PISTOL, "armor": 2,
		"gadget": Gadget.ASSAULT_CANNON, "gadget2": Gadget.KRAK_GRENADE,
		"gadget3": Gadget.RALLY, "unit_speed": 1.05, "unit_health": 1.25,
		"unit_jump": 1.10, "unit_stature": 1.12,
		"style": CharacterModel.Style.ULTRAMARINE},
	# WARHAMMER — Blood Angels (20-23) ----------------------------------------
	{"name": "ASSAULT MARINE", "kit": Kit.BLOOD_ANGEL, "primary": Weapon.Class.CHAINSWORD,
		"sidearm": Weapon.Class.BOLT_PISTOL, "armor": 2,
		"gadget": Gadget.JUMP_PACK, "gadget2": Gadget.KRAK_GRENADE,
		"unit_speed": 1.08, "unit_health": 1.20, "unit_jump": 1.15,
		"unit_stature": 1.12, "style": CharacterModel.Style.BLOOD_ANGEL},
	{"name": "SANGUINARY GUARD", "kit": Kit.BLOOD_ANGEL, "primary": Weapon.Class.POWER_SWORD,
		"sidearm": Weapon.Class.PLASMA_PISTOL_40K, "armor": 3,
		"gadget": Gadget.JUMP_PACK, "gadget3": Gadget.RED_THIRST,
		"unit_speed": 1.10, "unit_health": 1.35, "unit_jump": 1.20,
		"unit_stature": 1.14, "style": CharacterModel.Style.BLOOD_ANGEL},
	{"name": "DEATH COMPANY", "kit": Kit.BLOOD_ANGEL, "primary": Weapon.Class.THUNDER_HAMMER,
		"sidearm": Weapon.Class.BOLT_PISTOL, "armor": 3,
		"gadget3": Gadget.RED_THIRST, "gadget2": Gadget.MELTA_BOMB,
		"unit_speed": 1.06, "unit_health": 1.45, "unit_stature": 1.14,
		"style": CharacterModel.Style.BLOOD_ANGEL},
	{"name": "BA TACTICAL", "kit": Kit.BLOOD_ANGEL, "primary": Weapon.Class.BOLTER,
		"sidearm": Weapon.Class.BOLT_PISTOL, "sight": Sight.HOLO, "armor": 2,
		"gadget3": Gadget.IRON_HALO, "gadget2": Gadget.KRAK_GRENADE,
		"unit_speed": 0.94, "unit_health": 1.30, "unit_stature": 1.14,
		"style": CharacterModel.Style.BLOOD_ANGEL},
	# WARHAMMER — Necrons (24-27) ---------------------------------------------
	# The Necrons were the last roster authored and the thinnest: four of their
	# eight classes deployed with ONE ability where everybody else's carry three.
	# Nothing new was needed to fix it — a Necron already owns a teleport, a
	# phase-out and an arc weapon, and they are what the faction is.
	{"name": "NECRON WARRIOR", "kit": Kit.NECRON, "primary": Weapon.Class.GAUSS_FLAYER,
		"sidearm": Weapon.Class.GAUSS_PISTOL, "sight": Sight.RED_DOT, "armor": 2,
		"gadget": Gadget.TRANSLOCATION, "gadget3": Gadget.PHASE_SHIFT,
		"unit_speed": 0.86, "unit_health": 1.30, "unit_jump": 0.85,
		"unit_stature": 1.08, "style": CharacterModel.Style.NECRON},
	{"name": "IMMORTAL", "kit": Kit.NECRON, "primary": Weapon.Class.GAUSS_BLASTER,
		"sidearm": Weapon.Class.GAUSS_PISTOL, "sight": Sight.HOLO, "armor": 3,
		"gadget": Gadget.CANOPTEK_SPYDER, "gadget3": Gadget.OVERSHIELD,
		"unit_speed": 0.82, "unit_health": 1.55, "unit_jump": 0.80,
		"unit_stature": 1.12, "style": CharacterModel.Style.NECRON},
	{"name": "DEATHMARK", "kit": Kit.NECRON, "primary": Weapon.Class.SYNAPTIC_DISINTEGRATOR,
		"sidearm": Weapon.Class.GAUSS_PISTOL, "sight": Sight.SCOPE_4X, "armor": 1,
		"gadget": Gadget.TRANSLOCATION, "gadget3": Gadget.PHASE_SHIFT,
		"unit_speed": 0.95, "unit_health": 1.05, "unit_stature": 1.10,
		"style": CharacterModel.Style.NECRON},
	{"name": "LYCHGUARD", "kit": Kit.NECRON, "primary": Weapon.Class.WARSCYTHE,
		"sidearm": Weapon.Class.GAUSS_PISTOL, "armor": 3,
		"gadget": Gadget.TESLA_ARC, "gadget2": Gadget.TRANSLOCATION,
		"unit_speed": 0.84, "unit_health": 1.65, "unit_jump": 0.80,
		"unit_stature": 1.14, "style": CharacterModel.Style.NECRON_LORD},
	# WARHAMMER — Orks (28-31) ------------------------------------------------
	# An ork is a big thick body that is nonetheless quick when it is coming at
	# you: the boyz sit near the trooper's pace and take a lot of stopping, and
	# the two Nobs trade almost all of that pace for being nearly unkillable.
	{"name": "SHOOTA BOY", "kit": Kit.ORK, "primary": Weapon.Class.SHOOTA,
		"sidearm": Weapon.Class.SLUGGA, "armor": 2,
		"gadget3": Gadget.WAAAGH, "gadget2": Gadget.STIKKBOMB,
		"unit_speed": 1.02, "unit_health": 1.20, "unit_stature": 1.08,
		"style": CharacterModel.Style.ORK},
	{"name": "BURNA BOY", "kit": Kit.ORK, "primary": Weapon.Class.BURNA,
		"sidearm": Weapon.Class.SLUGGA, "armor": 2,
		"gadget3": Gadget.KUSTOM_FORCE_FIELD, "gadget2": Gadget.SMOKE_LAUNCHER,
		"unit_speed": 0.98, "unit_health": 1.20, "unit_stature": 1.08,
		"style": CharacterModel.Style.ORK},
	{"name": "TANKBUSTA", "kit": Kit.ORK, "primary": Weapon.Class.ROKKIT_LAUNCHA,
		"sidearm": Weapon.Class.SLUGGA, "armor": 2,
		"gadget": Gadget.ROKKIT_PACK, "gadget2": Gadget.STIKKBOMB,
		"unit_speed": 0.96, "unit_health": 1.20, "unit_stature": 1.08,
		"style": CharacterModel.Style.ORK},
	{"name": "ORK NOB", "kit": Kit.ORK, "primary": Weapon.Class.POWER_KLAW,
		"sidearm": Weapon.Class.SLUGGA, "armor": 3,
		"gadget": Gadget.GROT_GUNNER, "gadget3": Gadget.WAAAGH,
		"unit_speed": 0.92, "unit_health": 1.60, "unit_jump": 0.90,
		"unit_stature": 1.16, "style": CharacterModel.Style.ORK_NOB},
	# =========================================================================
	# THE SECOND HALF OF EVERY ROSTER (32+), plus two new Star Wars sides.
	#
	# APPENDED, never interleaved. FACTION_ROSTERS names classes by INDEX, so
	# inserting a Republic class next to the other Republic ones would silently
	# re-deal every roster below it — the same trap the WEAPONS table has and the
	# same answer: add at the end and list the index.
	# =========================================================================

	# =========================================================================
	# THE STAR WARS ROSTERS, REBUILT. Battlefront's own vocabulary: every side is
	# four line classes (assault, heavy, officer, specialist) and four
	# REINFORCEMENTS — the units people actually queue for. A class earns its
	# place by playing differently, not by carrying a different-coloured rifle,
	# so almost every one of these names a weapon or a gadget that did not exist
	# before this pass.
	# =========================================================================

	# REPUBLIC, second four (32-35) ------------------------------------------
	{"name": "CLONE OFFICER", "primary": Weapon.Class.DC15S,
		"sight": Sight.RED_DOT, "sidearm": Weapon.Class.DC17, "armor": 1, "squad": 2,
		"gadget": Gadget.TURRET, "gadget2": Gadget.THERMAL_DET,
		"gadget3": Gadget.RALLY, "unit_speed": 1.02,
		"style": CharacterModel.Style.CLONE_ENGINEER},
	{"name": "CLONE SHARPSHOOTER", "primary": Weapon.Class.DC15X,
		"sidearm": Weapon.Class.DC17, "armor": 0, "gadget": Gadget.PULSE_SCAN,
		"gadget2": Gadget.GRENADE_SMOKE, "gadget3": Gadget.CLOAK,
		"unit_speed": 1.08, "unit_health": 0.85, "unit_stature": 0.98,
		"style": CharacterModel.Style.CLONE_ARC},
	# THE REINFORCEMENTS. The ARC trooper carries a PAIR of DC-17s (the dual mod
	# is the class, not an upgrade) and the commando the burst-fire DC-17m.
	# They differ in the BODY too, which is what a reinforcement is for: the ARC
	# is the fastest thing the Republic fields and the Commando the toughest.
	{"name": "ARC TROOPER", "weapon": NO_PRIMARY,
		"sidearm": Weapon.Class.DC17,
		"secondary_mod": SecondaryMod.DUAL, "armor": 1,
		"gadget": Gadget.SHOCK_TRAP, "gadget2": Gadget.DASH,
		"gadget3": Gadget.OVERSHIELD, "unit_speed": 1.16, "unit_health": 0.95,
		"unit_jump": 1.10, "style": CharacterModel.Style.CLONE_ARC},
	{"name": "CLONE COMMANDO", "primary": Weapon.Class.DC17M,
		"sight": Sight.RED_DOT, "sidearm": Weapon.Class.DC17, "armor": 3,
		"gadget": Gadget.SCAN_DART, "gadget2": Gadget.THERMAL_DET,
		"gadget3": Gadget.OVERSHIELD, "unit_speed": 0.95, "unit_health": 1.35,
		"unit_stature": 1.05, "style": CharacterModel.Style.CLONE_COMMANDO},

	# SEPARATIST, second four (36-39) ----------------------------------------
	{"name": "B1 SNIPER DROID", "primary": Weapon.Class.E5S,
		"sidearm": Weapon.Class.REVOLVER, "armor": 0, "gadget": Gadget.PULSE_SCAN,
		"gadget2": Gadget.GRENADE_SMOKE, "gadget3": Gadget.CLOAK,
		"unit_speed": 0.96, "unit_health": 0.84, "unit_stature": 0.94,
		"style": CharacterModel.Style.B1},
	# DROIDEKA: the twin repeaters and the deflector bubble, which is the unit —
	# you do not out-shoot a destroyer, you flank it while the shield is down.
	# SLOW IS THE WHOLE POINT. It rolls into position and then it is a turret:
	# if you could also run from it, or it could chase you, the flank it is
	# built to be punished by would never be worth taking. The lowest jump in
	# the game as well — a thing on three legs does not hop.
	# ...and the ROLL is the other half of it. A destroyer that could only ever
	# trudge was one long walk to the fight and then a turret, which is the unit
	# with its best trick missing: the whole reason it is a ball is that it
	# ARRIVES. The dash is a gadget, so this costs no new mechanism — it just
	# needed someone to notice that "rolls in fast, then cannot leave" is a far
	# better character than "slow" on its own.
	{"name": "DROIDEKA", "primary": Weapon.Class.DROIDEKA_TWIN,
		"sidearm": Weapon.Class.REVOLVER, "armor": 2, "gadget": Gadget.DASH,
		"gadget3": Gadget.DEFLECTOR,
		"unit_speed": 0.62, "unit_health": 1.55, "unit_jump": 0.66,
		"unit_stature": 0.88, "style": CharacterModel.Style.DROIDEKA},
	{"name": "BX COMMANDO DROID", "kit": Kit.FORCE, "weapon": NO_PRIMARY,
		"primary_override": Weapon.Class.VIBROSWORD,
		"sidearm": Weapon.Class.REVOLVER, "armor": 1,
		"gadget": Gadget.DASH, "gadget2": Gadget.GRENADE_SMOKE,
		"gadget3": Gadget.CLOAK, "unit_speed": 1.25, "unit_health": 0.85,
		"unit_jump": 1.15, "style": CharacterModel.Style.COMMANDO_DROID},
	# Light enough to fly and light enough to swat: the highest jump on the
	# roster over the second-thinnest body.
	{"name": "GEONOSIAN WARRIOR", "primary": Weapon.Class.SONIC_BLASTER,
		"sidearm": Weapon.Class.REVOLVER, "armor": 0, "gadget": Gadget.WINGS,
		"gadget2": Gadget.THERMAL_DET, "gadget3": Gadget.FURY,
		"unit_speed": 1.10, "unit_health": 0.82, "unit_jump": 1.35,
		"unit_stature": 0.94, "style": CharacterModel.Style.GEONOSIAN},

	# EMPIRE (40-47) ----------------------------------------------------------
	{"name": "STORMTROOPER", "primary": Weapon.Class.E11,
		"sight": Sight.RED_DOT, "sidearm": Weapon.Class.SE14R, "armor": 1,
		"gadget2": Gadget.THERMAL_DET, "gadget3": Gadget.OVERSHIELD,
		"style": CharacterModel.Style.STORMTROOPER},
	{"name": "HEAVY TROOPER", "primary": Weapon.Class.DLT19,
		"foregrip": true, "sidearm": Weapon.Class.SE14R, "armor": 3,
		"gadget2": Gadget.THERMAL_DET, "gadget3": Gadget.DEPLOY_COVER,
		"unit_speed": 0.88, "unit_health": 1.28, "unit_jump": 0.90,
		"unit_stature": 1.06, "style": CharacterModel.Style.STORMTROOPER_HEAVY},
	# The officers each carry their OWN side's rifle. All three used to be
	# listed with the DC-15S — a Republic clone carbine in the hands of an
	# Imperial and a Rebel officer, twenty years and one war on the wrong side.
	{"name": "IMPERIAL OFFICER", "primary": Weapon.Class.E11,
		"sidearm": Weapon.Class.SE14R, "armor": 1, "squad": 2, "gadget": Gadget.TURRET,
		"gadget2": Gadget.GRENADE_SMOKE, "gadget3": Gadget.RALLY,
		"unit_speed": 1.02, "unit_health": 0.92,
		"style": CharacterModel.Style.IMPERIAL_OFFICER},
	# The fastest line class either Imperial or Rebel fields, and the softest.
	# A scout is a flanker or it is nothing, and it has to be genuinely
	# punishing to get caught in the open as one.
	{"name": "SCOUT TROOPER", "primary": Weapon.Class.DLT20A,
		"sidearm": Weapon.Class.SE14R, "armor": 0, "gadget": Gadget.PULSE_SCAN,
		"gadget2": Gadget.GRENADE_SMOKE, "gadget3": Gadget.CLOAK,
		"unit_speed": 1.18, "unit_health": 0.82, "unit_jump": 1.18,
		"unit_stature": 0.97, "style": CharacterModel.Style.SCOUT_TROOPER},
	# The reinforcements: the two units the Empire is actually feared for, plus
	# the flamer and the guard. The DEATH TROOPER is the only class in the game
	# that is faster AND tougher than the line trooper at once — that is exactly
	# what makes the black armour frightening, and the reason it is a
	# reinforcement rather than something you can field eight of.
	{"name": "DEATH TROOPER", "kit": Kit.TRANDOSHAN,
		"primary": Weapon.Class.E11D, "sight": Sight.THERMAL,
		"sidearm": Weapon.Class.SE14R, "armor": 2, "gadget": Gadget.SCAN_DART,
		"gadget2": Gadget.GRENADE_SMOKE, "gadget3": Gadget.CLOAK,
		"unit_speed": 1.06, "unit_health": 1.20, "unit_stature": 1.03,
		"style": CharacterModel.Style.DEATH_TROOPER},
	# The flamer has no reach at all, so the whole class is the WALK IN. It is
	# paid for in health, not speed: arriving quickly is not the fantasy,
	# arriving at all is.
	{"name": "FLAMETROOPER", "primary": Weapon.Class.FLAMETHROWER,
		"sidearm": Weapon.Class.SE14R, "armor": 2, "gadget2": Gadget.THERMAL_DET,
		"gadget3": Gadget.OVERSHIELD, "unit_speed": 0.94, "unit_health": 1.30,
		"unit_stature": 1.04, "style": CharacterModel.Style.FLAMETROOPER},
	{"name": "SHORETROOPER", "primary": Weapon.Class.E11,
		"grip": true, "sidearm": Weapon.Class.SE14R, "armor": 2, "gadget": Gadget.MORTAR,
		"gadget2": Gadget.THERMAL_DET, "gadget3": Gadget.DEPLOY_COVER,
		"unit_speed": 0.96, "unit_health": 1.15, "unit_stature": 1.02,
		"style": CharacterModel.Style.SHORETROOPER},
	# THE WALL. On the FORCE kit the Royal Guard was inheriting speed 1.2 and
	# came out the fastest thing on the field, which is precisely backwards for
	# the Emperor's bodyguard — an authored physique REPLACES the kit's, so
	# these numbers are what it actually gets: slow, enormous, and the single
	# hardest body in Star Wars to put down.
	{"name": "ROYAL GUARD", "kit": Kit.FORCE, "weapon": NO_PRIMARY,
		"primary_override": Weapon.Class.STAFF,
		"sidearm": Weapon.Class.SE14R, "armor": 3,
		"gadget": Gadget.DASH, "gadget3": Gadget.FURY,
		"unit_speed": 0.84, "unit_health": 1.70, "unit_jump": 0.85,
		"unit_stature": 1.08, "style": CharacterModel.Style.IMPERIAL_ROYAL},

	# REBEL ALLIANCE (48-55) --------------------------------------------------
	{"name": "REBEL TROOPER", "primary": Weapon.Class.A280C,
		"sight": Sight.RED_DOT, "sidearm": Weapon.Class.DH17, "armor": 1,
		"gadget2": Gadget.THERMAL_DET, "gadget3": Gadget.OVERSHIELD,
		"style": CharacterModel.Style.REBEL_TROOPER},
	{"name": "REBEL VANGUARD", "primary": Weapon.Class.CR2,
		"sidearm": Weapon.Class.DH17, "armor": 2, "gadget": Gadget.DASH,
		"gadget2": Gadget.THERMAL_DET, "gadget3": Gadget.FURY,
		"unit_speed": 1.05, "unit_health": 1.15, "unit_stature": 1.05,
		"style": CharacterModel.Style.REBEL_VANGUARD},
	{"name": "REBEL OFFICER", "primary": Weapon.Class.A280C,
		"sidearm": Weapon.Class.DH17, "armor": 1, "squad": 2, "gadget": Gadget.TURRET,
		"gadget2": Gadget.GRENADE_SMOKE, "gadget3": Gadget.RALLY,
		"unit_speed": 1.02, "unit_health": 0.92,
		"style": CharacterModel.Style.REBEL_OFFICER},
	{"name": "REBEL MARKSMAN", "primary": Weapon.Class.DH447,
		"sidearm": Weapon.Class.DH17, "armor": 0, "gadget": Gadget.PULSE_SCAN,
		"gadget2": Gadget.GRENADE_SMOKE, "gadget3": Gadget.CLOAK,
		"unit_speed": 1.08, "unit_health": 0.85, "unit_stature": 0.98,
		"style": CharacterModel.Style.REBEL_PILOT},
	# Reinforcements: the Wookiee and the Ewok are the two the fanbase asks for
	# by name, and the Pathfinder is the one it plays. These two are also the
	# extremes of the whole physique table, in opposite directions — the tallest
	# and hardest body in Star Wars against the smallest and softest.
	# THE BOWCASTER, named rather than left to index 0. `secondary: 0` is the
	# DL-44, so the most recognisable weapon this unit has ever carried was being
	# replaced at deploy by Han Solo's pistol — legal, playable and the wrong
	# character. It is a `sidearm` and not a `primary` because that is where the
	# Wookiee kit actually sells it; what a player sees is the gun in its hands.
	{"name": "WOOKIEE WARRIOR", "kit": Kit.WOOKIEE, "weapon": NO_PRIMARY,
		"sidearm": Weapon.Class.BOWCASTER,
		"armor": 3, "gadget2": Gadget.THERMAL_DET, "gadget3": Gadget.FURY,
		"unit_speed": 0.86, "unit_health": 1.55, "unit_jump": 0.85,
		"unit_stature": 1.16, "style": CharacterModel.Style.WOOKIEE},
	# KNEE-HIGH AND LETHAL. The stature is not decoration: at 0.62 the capsule
	# is about 1.1 m, so an Ewok is genuinely hard to hit, genuinely fast, and
	# dies to about two rifle rounds. The model has been built at this bulk
	# since it was added — it was the HITBOX that was still trooper-sized, so
	# until now the joke was purely visual and it fought like a stormtrooper.
	{"name": "EWOK HUNTER", "kit": Kit.FORCE, "weapon": NO_PRIMARY,
		# The holdout: an Ewok's blaster is a thing it took off somebody.
		"primary_override": Weapon.Class.EWOK_SPEAR,
		"sidearm": Weapon.Class.HOLDOUT, "armor": 0,
		"gadget": Gadget.DASH, "gadget2": Gadget.GRENADE_SMOKE,
		"gadget3": Gadget.CLOAK, "unit_speed": 1.30, "unit_health": 0.60,
		"unit_jump": 1.25, "unit_stature": 0.62,
		"style": CharacterModel.Style.EWOK},
	{"name": "REBEL PATHFINDER", "kit": Kit.TRANDOSHAN,
		# The one class that keeps the DL-44 — a Pathfinder is the Alliance's
		# scoundrel, and it is his pistol.
		"primary": Weapon.Class.A280C, "sight": Sight.THERMAL,
		"sidearm": Weapon.Class.PISTOL, "armor": 1, "gadget": Gadget.SCAN_DART,
		"gadget2": Gadget.GRENADE_SMOKE, "gadget3": Gadget.CLOAK,
		"unit_speed": 1.10, "unit_health": 0.90, "unit_jump": 1.08,
		"style": CharacterModel.Style.REBEL_COMMANDO},
	{"name": "REBEL JEDI", "kit": Kit.FORCE, "weapon": NO_PRIMARY,
		"primary_override": Weapon.Class.SABER,
		"sidearm": Weapon.Class.BRYAR, "armor": 1,
		"gadget": Gadget.FORCE_PUSH, "gadget2": Gadget.FORCE_LEAP,
		"gadget3": Gadget.FURY, "unit_speed": 1.22, "unit_health": 1.30,
		"unit_jump": 1.20, "style": CharacterModel.Style.JEDI},

	# =========================================================================
	# HALO, REBUILT. The sandbox IS the roster here — a Halo class is defined by
	# which of the iconic guns it walks in with, so every one of these names a
	# different weapon and no two share a primary.
	# =========================================================================

	# HALO — UNSC, second four (56-59) ----------------------------------------
	{"name": "SPARTAN CQC", "kit": Kit.SPARTAN, "primary": Weapon.Class.M90_SHOTGUN,
		"sidearm": Weapon.Class.M6D, "armor": 2, "gadget": Gadget.THRUSTER_PACK,
		"gadget2": Gadget.FRAG_GRENADE_UNSC, "gadget3": Gadget.OVERSHIELD,
		"unit_speed": 1.10, "unit_health": 1.30, "unit_stature": 1.12,
		"style": CharacterModel.Style.SPARTAN},
	{"name": "ODST SNIPER", "kit": Kit.ODST, "primary": Weapon.Class.SRS99,
		"sidearm": Weapon.Class.M6D, "armor": 0, "gadget": Gadget.VISR,
		"gadget2": Gadget.FRAG_GRENADE_UNSC, "gadget3": Gadget.ACTIVE_CAMO,
		"unit_speed": 1.06, "unit_health": 0.90, "unit_stature": 0.98,
		"style": CharacterModel.Style.ODST},
	{"name": "MARINE ROCKETEER", "kit": Kit.ODST, "primary": Weapon.Class.SPNKR,
		"sidearm": Weapon.Class.M6D, "armor": 1, "gadget2": Gadget.FRAG_GRENADE_UNSC,
		"gadget3": Gadget.DEPLOY_COVER, "unit_speed": 0.94, "unit_health": 1.05,
		"style": CharacterModel.Style.MARINE},
	{"name": "MARINE GRENADIER", "kit": Kit.ODST, "primary": Weapon.Class.M319,
		"sidearm": Weapon.Class.M6D, "armor": 1, "gadget": Gadget.SENTRY_TURRET,
		"gadget2": Gadget.FRAG_GRENADE_UNSC, "gadget3": Gadget.BIOFOAM,
		"unit_speed": 0.98, "unit_health": 0.95,
		"style": CharacterModel.Style.MARINE},

	# HALO — Covenant, second four (60-63) ------------------------------------
	{"name": "ELITE ULTRA", "kit": Kit.SANGHEILI, "primary": Weapon.Class.COV_CARBINE,
		"sidearm": Weapon.Class.PLASMA_PISTOL, "sight": Sight.SCOPE, "armor": 3,
		"gadget2": Gadget.PLASMA_GRENADE, "gadget3": Gadget.OVERSHIELD,
		"unit_speed": 1.02, "unit_health": 1.45, "unit_stature": 1.14,
		"style": CharacterModel.Style.ELITE_ULTRA},
	{"name": "ELITE RANGER", "kit": Kit.SANGHEILI, "primary": Weapon.Class.BEAM_RIFLE,
		"sidearm": Weapon.Class.PLASMA_PISTOL, "armor": 1,
		"gadget": Gadget.THRUSTER_PACK, "gadget2": Gadget.PLASMA_GRENADE,
		"gadget3": Gadget.ACTIVE_CAMO, "unit_speed": 1.12, "unit_health": 1.15,
		"unit_jump": 1.15, "unit_stature": 1.10,
		"style": CharacterModel.Style.ELITE},
	# THE JACKAL: a beam rifle behind a gauntlet you cannot shoot through. The
	# deflector is the unit, exactly as it is for the Droideka — and like the
	# Grunt it is a small, light body, which is most of why a Kig-Yar behind
	# that shield is so annoying to dig out.
	{"name": "JACKAL SNIPER", "kit": Kit.UNGGOY, "primary": Weapon.Class.BEAM_RIFLE,
		"sidearm": Weapon.Class.PLASMA_PISTOL, "armor": 1,
		"gadget2": Gadget.PLASMA_GRENADE, "gadget3": Gadget.DEFLECTOR,
		"unit_speed": 1.12, "unit_health": 0.78, "unit_stature": 0.88,
		"style": CharacterModel.Style.JACKAL},
	# The Chieftain already holds the hammer in the first four, so this is the
	# other half of the Jiralhanae fantasy: a stalker with the spiker and camo.
	{"name": "BRUTE STALKER", "kit": Kit.JIRALHANAE, "primary": Weapon.Class.SPIKER,
		"sidearm": Weapon.Class.MAULER, "armor": 2,
		"gadget2": Gadget.PLASMA_GRENADE, "gadget3": Gadget.ACTIVE_CAMO,
		"unit_speed": 1.02, "unit_health": 1.35, "unit_stature": 1.14,
		"style": CharacterModel.Style.BRUTE},

	# 40K — Ultramarines, second four (64-67) ---------------------------------
	{"name": "ASSAULT INTERCESSOR", "kit": Kit.ULTRAMARINE, "primary": Weapon.Class.CHAINSWORD,
		"sidearm": Weapon.Class.BOLT_PISTOL, "armor": 2,
		"gadget": Gadget.JUMP_PACK, "gadget2": Gadget.KRAK_GRENADE,
		"gadget3": Gadget.IRON_HALO, "unit_speed": 1.02, "unit_health": 1.30,
		"unit_stature": 1.12, "style": CharacterModel.Style.ULTRAMARINE},
	{"name": "HELLBLASTER", "kit": Kit.ULTRAMARINE, "primary": Weapon.Class.PLASMA_GUN,
		"sidearm": Weapon.Class.BOLT_PISTOL, "cooling": true, "armor": 3,
		"gadget2": Gadget.KRAK_GRENADE, "gadget3": Gadget.OVERSHIELD,
		"unit_speed": 0.86, "unit_health": 1.50, "unit_stature": 1.14,
		"style": CharacterModel.Style.ULTRAMARINE},
	{"name": "APOTHECARY", "kit": Kit.ULTRAMARINE, "primary": Weapon.Class.BOLTER,
		"sidearm": Weapon.Class.BOLT_PISTOL, "armor": 2, "squad": 2,
		"gadget": Gadget.AUSPEX_SCAN, "gadget2": Gadget.KRAK_GRENADE,
		"gadget3": Gadget.IRON_HALO, "unit_speed": 0.94, "unit_health": 1.35,
		"unit_stature": 1.14, "style": CharacterModel.Style.ULTRAMARINE},
	{"name": "ERADICATOR", "kit": Kit.ULTRAMARINE, "primary": Weapon.Class.MELTAGUN,
		"sidearm": Weapon.Class.BOLT_PISTOL, "armor": 3,
		"gadget2": Gadget.MELTA_BOMB, "gadget3": Gadget.OVERSHIELD,
		"unit_speed": 0.84, "unit_health": 1.55, "unit_stature": 1.16,
		"style": CharacterModel.Style.ULTRAMARINE},

	# 40K — Blood Angels, second four (68-71) ---------------------------------
	{"name": "SANGUINARY PRIEST", "kit": Kit.BLOOD_ANGEL, "primary": Weapon.Class.BOLTER,
		"sidearm": Weapon.Class.BOLT_PISTOL, "armor": 2, "squad": 2,
		"gadget2": Gadget.KRAK_GRENADE, "gadget3": Gadget.RED_THIRST,
		"unit_speed": 0.96, "unit_health": 1.30, "unit_stature": 1.14,
		"style": CharacterModel.Style.BLOOD_ANGEL},
	{"name": "BA DEVASTATOR", "kit": Kit.BLOOD_ANGEL, "primary": Weapon.Class.HEAVY_BOLTER,
		"sidearm": Weapon.Class.BOLT_PISTOL, "cooling": true, "armor": 3,
		"gadget2": Gadget.KRAK_GRENADE, "gadget3": Gadget.IRON_HALO,
		"unit_speed": 0.84, "unit_health": 1.55, "unit_stature": 1.16,
		"style": CharacterModel.Style.BLOOD_ANGEL},
	{"name": "BA VANGUARD", "kit": Kit.BLOOD_ANGEL, "primary": Weapon.Class.POWER_SWORD,
		"sidearm": Weapon.Class.PLASMA_PISTOL_40K, "armor": 2,
		"gadget": Gadget.JUMP_PACK, "gadget2": Gadget.KRAK_GRENADE,
		"gadget3": Gadget.RED_THIRST, "unit_speed": 1.08, "unit_health": 1.25,
		"unit_jump": 1.15, "unit_stature": 1.12,
		"style": CharacterModel.Style.BLOOD_ANGEL},
	{"name": "BA FLAMER", "kit": Kit.BLOOD_ANGEL, "primary": Weapon.Class.FLAMER,
		"sidearm": Weapon.Class.BOLT_PISTOL, "armor": 2,
		"gadget2": Gadget.MELTA_BOMB, "gadget3": Gadget.IRON_HALO,
		"unit_speed": 0.92, "unit_health": 1.35, "unit_stature": 1.14,
		"style": CharacterModel.Style.BLOOD_ANGEL},

	# 40K — Necrons, second four (72-75) --------------------------------------
	{"name": "FLAYED ONE", "kit": Kit.NECRON, "primary": Weapon.Class.WARSCYTHE,
		"sidearm": Weapon.Class.GAUSS_PISTOL, "armor": 1,
		"gadget": Gadget.TRANSLOCATION, "gadget3": Gadget.PHASE_SHIFT,
		"unit_speed": 1.05, "unit_health": 0.95, "unit_stature": 1.06,
		"style": CharacterModel.Style.NECRON},
	{"name": "TESLA IMMORTAL", "kit": Kit.NECRON, "primary": Weapon.Class.TESLA_CARBINE,
		"sidearm": Weapon.Class.GAUSS_PISTOL, "armor": 2,
		"gadget": Gadget.TESLA_ARC, "gadget3": Gadget.OVERSHIELD,
		"unit_speed": 0.84, "unit_health": 1.45, "unit_stature": 1.12,
		"style": CharacterModel.Style.NECRON},
	{"name": "HEAT RAY DESTROYER", "kit": Kit.NECRON, "primary": Weapon.Class.HEAT_RAY,
		"sidearm": Weapon.Class.GAUSS_PISTOL, "cooling": true, "armor": 3,
		"gadget": Gadget.TESLA_ARC, "gadget3": Gadget.OVERSHIELD,
		# A Destroyer is a hovering GUN, and the heat ray is one of the biggest
		# bursts in the game (0.41 s, then a long cool). It does not also get to be
		# the toughest thing the Necrons field — the Lychguard and the Lord are
		# what stands in front of it, and at 1.60 it out-tanked both.
		"unit_speed": 0.78, "unit_health": 1.36, "unit_jump": 0.75,
		"unit_stature": 1.16, "style": CharacterModel.Style.NECRON},
	# The Lord swings a staff and walked at x0.78 with nothing that closes
	# ground: against anything holding a rifle it could never arrive, which is
	# not a hard matchup, it is an impossible one.
	{"name": "NECRON LORD", "kit": Kit.NECRON, "primary": Weapon.Class.STAFF_OF_LIGHT,
		"sidearm": Weapon.Class.GAUSS_PISTOL, "armor": 3, "squad": 2,
		"gadget": Gadget.CANOPTEK_SPYDER, "gadget2": Gadget.TRANSLOCATION,
		"gadget3": Gadget.PHASE_SHIFT, "unit_speed": 0.88, "unit_health": 1.70,
		"unit_stature": 1.16, "style": CharacterModel.Style.NECRON_LORD},

	# 40K — Orks, second four (76-79) -----------------------------------------
	{"name": "STORMBOY", "kit": Kit.ORK, "primary": Weapon.Class.SHOOTA,
		"sidearm": Weapon.Class.SLUGGA, "armor": 1,
		"gadget": Gadget.ROKKIT_PACK, "gadget2": Gadget.STIKKBOMB,
		"gadget3": Gadget.WAAAGH, "unit_speed": 1.20, "unit_health": 1.00,
		"unit_jump": 1.20, "unit_stature": 1.06,
		"style": CharacterModel.Style.ORK},
	# The single hardest body in the game to put down, and it pays the single
	# highest price for it: a Mega Nob is slower than a Droideka.
	{"name": "MEGA NOB", "kit": Kit.ORK, "primary": Weapon.Class.MEGA_BLASTA,
		"sidearm": Weapon.Class.SLUGGA, "armor": 3,
		"gadget2": Gadget.STIKKBOMB, "gadget3": Gadget.KUSTOM_FORCE_FIELD,
		"unit_speed": 0.74, "unit_health": 1.85, "unit_jump": 0.60,
		"unit_stature": 1.16, "style": CharacterModel.Style.ORK_NOB},
	{"name": "KOMMANDO", "kit": Kit.ORK, "primary": Weapon.Class.CHOPPA,
		"sidearm": Weapon.Class.SLUGGA, "armor": 1,
		"gadget2": Gadget.SMOKE_LAUNCHER, "gadget3": Gadget.WAAAGH,
		"unit_speed": 1.12, "unit_health": 1.05, "unit_stature": 1.04,
		"style": CharacterModel.Style.ORK},
	{"name": "MEK", "kit": Kit.ORK, "primary": Weapon.Class.BIG_SHOOTA,
		"sidearm": Weapon.Class.SLUGGA, "armor": 2, "squad": 2,
		"gadget": Gadget.GROT_GUNNER, "gadget2": Gadget.STIKKBOMB,
		"gadget3": Gadget.KUSTOM_FORCE_FIELD, "unit_speed": 1.00,
		"unit_health": 1.25, "unit_stature": 1.10,
		"style": CharacterModel.Style.ORK_NOB},
]## Which FACTION_BUILDS indices each team may pick from, PER UNIVERSE. Team 0 is
## the first side listed in UNIVERSES, team 1 the second, and so on. Faction
## classes are playable in every mode, so a three- or four-way match can ask for
## a roster nobody has authored: those sides WRAP onto the ones that exist rather
## than crashing or being locked out of the setting. Warhammer is the first
## universe to fill all four slots — two chapters, the Necrons and the Orks —
## which is what a wrap is there to make optional rather than required.
const FACTION_ROSTERS := {
	# EIGHT A SIDE. The second four of each roster live at the end of
	# FACTION_BUILDS (32+) rather than beside the first four, so adding them
	# moved no existing index — see the note there.
	Universe.STAR_WARS: [
		[0, 1, 2, 3, 32, 33, 34, 35],       # REPUBLIC
		[4, 5, 6, 7, 36, 37, 38, 39],       # SEPARATIST
		[40, 41, 42, 43, 44, 45, 46, 47],   # EMPIRE
		[48, 49, 50, 51, 52, 53, 54, 55]],  # REBEL ALLIANCE
	Universe.HALO: [
		[8, 9, 10, 11, 56, 57, 58, 59],     # UNSC
		[12, 13, 14, 15, 60, 61, 62, 63]],  # COVENANT
	Universe.WARHAMMER: [
		[16, 17, 18, 19, 64, 65, 66, 67],   # ULTRAMARINES
		[20, 21, 22, 23, 68, 69, 70, 71],   # BLOOD ANGELS
		[24, 25, 26, 27, 72, 73, 74, 75],   # NECRONS
		[28, 29, 30, 31, 76, 77, 78, 79]],  # ORKS
}


## The four class indices a team chooses between, in the universe being played.
## `universe` -1 means "the one currently being played". IT IS A PARAMETER
## BECAUSE A MATCH NO LONGER HAS ONE: with UNSC against the Republic, the roster
## a side fields is ITS OWN setting's, and `active_universe` cannot answer that
## for both of them. Callers that know a team pass `GameState.team_universe(t)`;
## `Loadout` may never ask GameState itself (kit_rules runs with no autoloads).
## EVERY AUTHORED CHARACTER THIS UNIVERSE FIELDS, as global indices into
## FACTION_BUILDS, in roster order.
##
## THE BUY SCREEN'S CLASS ROW USED TO OFFER THE KIT ARCHETYPES, AND THERE ARE
## ONLY FOURTEEN OF THEM. Measured: Star Wars put FIVE classes on that row and
## Warhammer four, while the game has thirty-two authored characters in each of
## them — so a player building a custom loadout could choose between "CLONE
## TROOPER" and "WOOKIEE" while the roster next door fielded a Clone Commando, an
## ARC Trooper, a Death Trooper, a Flametrooper and an Ewok Hunter. The classes
## existed, were balanced, were tested, and the mode most people play could not
## reach them.
##
## They are the same rows FACTION mode deploys (`faction_classes`), so this adds
## no catalogue and nothing to keep in step — a class authored for a roster turns
## up here for free, which is the same trick the nav grid plays on map colliders.
## Deduplicated because a build may appear on more than one side's roster.
static func custom_classes(universe := -1) -> Array:
	var u: int = universe if universe >= 0 else active_universe
	var rosters: Array = FACTION_ROSTERS.get(u, FACTION_ROSTERS[Universe.STAR_WARS])
	var out: Array = []
	var seen := {}
	for side in rosters:
		for i in side:
			if seen.has(i):
				continue
			seen[i] = true
			out.append(i)
	return out


static func faction_classes(team: int, universe := -1) -> Array:
	var u: int = universe if universe >= 0 else active_universe
	var rosters: Array = FACTION_ROSTERS.get(u, FACTION_ROSTERS[Universe.STAR_WARS])
	# THE SIDE INDEX IS THE FACTION'S OWN SLOT, not the team number. In a mixed
	# match team 1 might be UNSC, which is slot 0 of Halo — wrapping the team
	# number into Halo's two rosters would field the Covenant instead.
	return rosters[wrapi(maxi(team, 0), 0, rosters.size())]


## Build a loadout from a preset dictionary that is not in any of the tables.
##
## The public door onto `_build_from`, and it exists so a KILL STREAK REWARD can
## be an ordinary preset row (see `Streaks.REWARDS`) rather than a second way of
## describing a build. It goes through exactly the same translation every AI
## preset and authored class does — `primary`/`sidearm` looked up by CLASS, the
## name kept — so a reward that names a gun the catalogue does not sell in that
## slot is silently disarmed in exactly the same way, and `kit_rules` can ask the
## same strict question about it.
static func preset_build(preset: Dictionary) -> Loadout:
	return _build_from(preset)


## Build a faction class by its GLOBAL index into FACTION_BUILDS.
static func faction_build(index: int) -> Loadout:
	return _build_from(FACTION_BUILDS[wrapi(index, 0, FACTION_BUILDS.size())])


## A team's Nth class (0..3), built and ready to deploy.
static func team_build(team: int, class_slot: int, universe := -1) -> Loadout:
	var roster := faction_classes(team, universe)
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
				built.build_name = str(preset[key])
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
## THE LINE TROOPER'S KIT: a rifle, a scope, a frame, and nothing else at all.
##
## It is not a preset row in BOT_BUILDS because it is not a build somebody chose
## between — it is what ninety-odd of the hundred bodies in a MASSIVE battle
## carry, and the whole point of it is what it does NOT have. No gadget (a
## hundred jetpacks, turrets and mortars is not a battle, it is a fireworks
## display, and every one of them is a per-frame "should I use this" check on a
## body that should be thinking as little as possible), no grenades, no squad,
## and a sidearm nobody will ever swap to.
##
## The SCOPE is deliberate and is the one piece of kit they do get: it is what
## makes a line trooper shoot at a sensible range instead of walking into the
## enemy's faces (a bot's stand-off is derived from its cone — see
## `Bot._hold_range`), and it costs the AI nothing to carry.
##
## The gun comes from the universe's own default kit, so a massive battle in
## Halo is fought with MA5Bs and one in 40k with bolters, with no table here.
static func line_build() -> Loadout:
	var l := starter()
	l.sight = Sight.SCOPE
	l.gadget = Gadget.NONE
	l.gadget2 = Gadget.NONE
	l.squad = 0
	l.cooling = false
	l.grip = false
	l.foregrip = false
	l.secondary_mod = SecondaryMod.NONE
	return l


## WHAT YOU OPEN THE BUY SCREEN HOLDING: the first of this universe's authored
## characters, so the CLASS row starts ON the row it now walks rather than on a
## kit name that is not in the list. Falls back to the old kit starter when there
## is no roster to draw from (a bare `Loadout` in a unit test, royale).
static func starter() -> Loadout:
	var l := Loadout.new()
	if not custom_classes().is_empty():
		l.adopt_character(0)
		return l
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


## WHAT THE CLASS ROW SAYS. The character's own name when one has been chosen,
## which is the whole point of the row now — "ARC TROOPER" rather than the
## archetype "CLONE TROOPER" that five of them share.
func class_name_shown() -> String:
	if character >= 0 and build_name != "":
		return build_name
	return kit_name()


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
	return float(armor_stats()["health"]) * _physique(unit_health, kit_health()) * ttk_health


## The three other halves of max_health(). Player and Bot used to compute the
## speed inline (`armor["speed"] * kit_speed()`) in two places that had to agree;
## they go through here now for the same reason health always has.
func move_speed() -> float:
	return float(armor_stats()["speed"]) * _physique(unit_speed, kit_speed())


func jump_power() -> float:
	return float(armor_stats()["jump"]) * _physique(unit_jump, 1.0)


## How TALL this unit is, as a multiple of the standard trooper. It scales the
## model, the collision capsule, the eye height and the headshot line together —
## they are one number or they disagree, and a headshot box that does not match
## the head on screen is the worst kind of disagreement.
func stature() -> float:
	return _physique(unit_stature, 1.0)


## An authored value if the build stated one, else the shopped default.
static func _physique(stated: float, fallback: float) -> float:
	return stated if stated > 0.0 else fallback


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
			# THE CLASS ROW OFFERS THIS UNIVERSE'S AUTHORED CHARACTERS. It used to
			# offer the KIT archetypes, of which a universe has four or five
			# against its thirty-two classes — see `custom_classes`. Every entry
			# in that list is already this universe's, so unlike the kit enum
			# (which is shared by three settings and had to be WALKED) this one
			# can simply be bounded.
			var pool := custom_classes()
			if pool.is_empty():
				return kit_universe(index) == active_universe
			return index >= 0 and index < pool.size()
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
		# THE THIRD SLOT HAS ITS OWN CATALOGUE, not a filtered view of the other
		# two. A sustained ability is a different kind of thing (see gadget3_id),
		# so a kit states which ones it may put up in a list of its own — and
		# nothing in `gadgets` can reach this slot, nor anything here those.
		Row.GADGET3:
			if not in_universe(GADGETS[index], kit_universe(kit)):
				return false
			# A "kit"-marked entry still belongs to its owner alone — the same
			# rule the other four catalogue rows keep. The barrier is the
			# Wookiee's whichever slot it is fitted in.
			var owner: Variant = GADGETS[index].get("kit", null)
			if owner != null and owner != kit:
				return false
			return index in k.get("sustain", [Gadget.NONE])
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
	# list means anything ordinary goes — except in CUSTOM, where the whole
	# ordinary catalogue is open (see `custom_pool`).
	if custom_pool:
		return true
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
		Row.GADGET3:
			return gadget_slots() >= 3
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
## TAKE ONE OF THE UNIVERSE'S AUTHORED CHARACTERS as the starting point for a
## custom build — the CLASS row's job now.
##
## It is `adopt_kit` plus the BODY: the class's own style, physique, armour and
## the two guns it walks in with. That is the whole difference between the two
## screens now — FACTION deploys the character as authored, CUSTOM hands you the
## same character and lets you rebuild everything above the neck of it. The reset
## is `adopt_kit`'s and for `adopt_kit`'s reason: half the old selections would
## be illegal on the new class and this guarantees the result is inside BUDGET in
## one pass.
##
## A character's authored build is a legal player loadout — `kit_rules` asserts
## exactly that for all eighty of them — so what lands here always fits.
func adopt_character(index: int) -> void:
	var pool := custom_classes()
	if pool.is_empty():
		return
	index = clampi(index, 0, pool.size() - 1)
	var build: Dictionary = FACTION_BUILDS[pool[index]]
	var made := _build_from(build)
	# `adopt_kit` FIRST, because it is the reset — then the character's own
	# choices are laid over the fresh build rather than under it.
	adopt_kit(int(build.get("kit", default_kit())))
	character = index
	build_name = made.build_name
	style = made.style
	primary_override = made.primary_override
	weapon = made.weapon
	secondary = made.secondary
	armor = made.armor
	unit_speed = made.unit_speed
	unit_health = made.unit_health
	unit_jump = made.unit_jump
	unit_stature = made.unit_stature


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
	# The sustained slot resets with the other two. Kept explicit rather than
	# leaning on `Loadout.new()`'s default, so all three slots are visibly
	# cleared in one place — a class change RESETS the build, and an ability the
	# new class may not fit is exactly what this reset exists to prevent.
	fresh.gadget3 = Gadget.NONE
	_copy_from(fresh)


func cost() -> int:
	var total: int = WEAPONS[weapon]["cost"]
	total += SECONDARIES[secondary]["cost"]
	total += SECONDARY_MODS[secondary_mod]["cost"]
	total += SIGHTS[sight]["cost"]
	total += GADGETS[gadget]["cost"]
	total += GADGETS[gadget2]["cost"]
	# The third slot was free until this line: unpriced, the most expensive
	# ability in the game cost nothing and every budget check in the file was
	# wrong by however much it was worth.
	total += GADGETS[gadget3]["cost"]
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


## THE THIRD SLOT, which holds a different KIND of gadget from the other two.
##
## Slots 1 and 2 are things you THROW or DROP: a grenade, a turret, a dart, a
## shove. They are a press, an effect, and a cooldown. The third slot is what you
## PUT UP AND KEEP — a cloak, a barrier, an overshield, a battle fury — where the
## decision is not *when to press it* but *when to be under it*, and the cost is
## that it runs on a clock whether or not it is doing you any good.
##
## They were never a comfortable fit in the other two: a Trandoshan spending its
## one deployable slot on the cloak was really choosing between an ability and a
## grenade, which is not the choice either of them is interesting for.
func gadget3_id() -> int:
	return gadget3 if gadget_slots() >= 3 else Gadget.NONE


## Does this build carry a gadget that DOES `action` — in ANY slot, under any
## universe's name for it? Bot asks this rather than comparing raw ids, so "does
## this AI have a turret" is one question whether the turret is an autosentry, a
## canoptek spyder or a grot on a gun.
##
## ALL THREE SLOTS, which `Player.has_gadget` beside it has always asked and this
## did not. Nothing changes today — every action a caller currently names is a
## deployable or a one-shot, and the sustain catalogue is disjoint from the other
## two (`kit_rules` asserts both directions), so no live question could reach the
## third slot to be answered wrongly. It is fixed anyway because the failure mode
## is silent: the first caller to ask `uses(OVERSHIELD)` would simply be told no.
func uses(action: int) -> bool:
	return gadget_action(gadget_id()) == action \
		or gadget_action(gadget2_id()) == action \
		or gadget_action(gadget3_id()) == action


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
			# CLAMPED, not walked, and that is a simplification the character pool
			# buys: `custom_classes()` is already filtered to this universe, so
			# every entry on the row is legal and there is nothing to skip. The
			# kit enum needed a walk because three settings share it and a clamp
			# would step off the last Star Wars class straight onto a Spartan.
			var pool := custom_classes()
			if pool.is_empty():
				adopt_kit(_walk(row, kit, dir, KITS.size()))
			else:
				adopt_character(clampi(character + dir, 0, pool.size() - 1))
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
		Row.GADGET3:
			gadget3 = _walk(row, gadget3, dir, GADGETS.size())
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


## ...and every editable field HERE too, for a different reason with the same
## symptom: `step()` refuses a change this reports as no change, so a row missing
## from this comparison is a row the buy cursor cannot move. `gadget3` and
## `foregrip` were both absent — the ABILITY row and the FRONT GRIP row could be
## pressed all day and would never change, and neither said anything about why.
func _same_as(other: Loadout) -> bool:
	return kit == other.kit and character == other.character \
		and weapon == other.weapon and secondary == other.secondary \
		and secondary_mod == other.secondary_mod \
		and gadget == other.gadget and gadget2 == other.gadget2 \
		and gadget3 == other.gadget3 \
		and sight == other.sight \
		and cooling == other.cooling and grip == other.grip \
		and foregrip == other.foregrip \
		and armor == other.armor and squad == other.squad \
		and squad_skill == other.squad_skill


## EVERY EDITABLE FIELD, and the third gadget is the proof of why that matters.
## `gadget3` was missing here, which is not "the ability is sometimes lost" — it
## is the ability never existing at all, because NOTHING reads a Loadout without
## copying it first. `step()` duplicates into a trial and copies the result back,
## so the buy screen's ABILITY row wrote into a field that was then thrown away;
## `_apply_loadout` deploys `pending.duplicate_loadout()`, so even a faction class
## whose preset names one lost it on the way into the body. A field added to this
## class and not added here is a field that silently does not exist.
func _copy_from(other: Loadout) -> void:
	kit = other.kit
	character = other.character
	build_name = other.build_name
	gadget2 = other.gadget2
	gadget3 = other.gadget3
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
	unit_speed = other.unit_speed
	unit_health = other.unit_health
	unit_jump = other.unit_jump
	unit_stature = other.unit_stature


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
		Row.GADGET3: return "ABILITY"
		Row.SIGHT: return "SIGHT"
		Row.ARMOR: return "ARMOR"
		Row.SQUAD: return "AI SQUAD"
		Row.SQUAD_SKILL: return "SQUAD SKILL"
		_: return UPGRADES[_upgrade_index(row)]["name"]


func row_value(row: int) -> String:
	match row:
		Row.KIT: return class_name_shown()
		Row.WEAPON: return weapon_name()
		Row.SECONDARY: return secondary_name()
		Row.SECONDARY_MOD: return SECONDARY_MODS[secondary_mod]["name"]
		Row.GADGET: return GADGETS[gadget]["name"]
		Row.GADGET2: return GADGETS[gadget2]["name"]
		Row.GADGET3: return GADGETS[gadget3]["name"]
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
		Row.GADGET3: return GADGETS[gadget3]["cost"]
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
			# A CHARACTER'S OWN BLURB IF IT HAS ONE. Falling through to the kit's
			# is right for a build with no character on it, and wrong for one that
			# has: "Standard trooper" under the name DEATH TROOPER is a line that
			# says nothing about what you just picked.
			if character >= 0:
				var pool := custom_classes()
				if character < pool.size():
					var b: Dictionary = FACTION_BUILDS[pool[character]]
					if b.has("blurb"):
						return str(b["blurb"])
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
		Row.GADGET3:
			return "%s   (on slot 3: %s)" % [GADGETS[gadget3]["blurb"],
				Controls.slot3_label(device)]
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
