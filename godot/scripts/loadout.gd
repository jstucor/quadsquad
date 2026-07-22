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

## CHARACTER CLASSES. A kit is a set of ALLOW-LISTS over the catalogue below,
## not a separate catalogue of its own: every kit shops from the same tables and
## pays out of the same BUDGET, and what separates them is what they are allowed
## to reach and how many gadget slots they carry. That way a new gun or gadget
## is one table entry plus a decision about who may take it, rather than three
## parallel shops that drift apart.
##
## The rules a kit can state:
##   gadgets        which Gadget ids it may buy (also gates the second slot)
##   gadget_slots   1, or 2 for the Mandalorian
##   secondary_mods which SecondaryMod ids it may buy — DUAL is Mandalorian-only
##   armor          which ARMOR indices it may wear
##   default_armor  what it starts on, which is how "lighter by default" is said
##   grenades       false removes the grenade rows entirely
##   primaries      if present, the ONLY primary classes it may hold
##
## A gun marked with a "kit" key in WEAPONS is that kit's alone, so a class
## without an explicit `primaries` list still cannot pick up a lightsaber.
## The table itself is further down, under the gadget and armour catalogues it
## has to name; only the enum can live up here, where WEAPONS needs it.
enum Kit { CLONE, MANDALORIAN, FORCE }

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
	{"class": Weapon.Class.HMG, "cost": 80},
	{"class": Weapon.Class.SNIPER, "cost": 85},
	{"class": Weapon.Class.RPG, "cost": 110},
	# Appended rather than slotted in by price, because WEAPONS is indexed by
	# POSITION and inserting here would shift every BOT_BUILDS preset below it.
	# The order only exists to walk the menu, and the one kit that can take the
	# saber sees nothing else on the row, so its place in the list is moot.
	{"class": Weapon.Class.SABER, "cost": 55, "kit": Kit.FORCE},
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

# Sights are one slot with three options rather than a toggle, because a holo
# ring and a magnified scope are alternatives, not stackable extras.
enum Sight { NONE, HOLO, SCOPE }
const SIGHTS: Array[Dictionary] = [
	{"name": "IRON", "cost": 0, "blurb": "Open sights"},
	{"name": "HOLO RING", "cost": 20,
		"blurb": "Hollow ring sight: clear view, mild zoom, tighter aim"},
	{"name": "SCOPE", "cost": 25,
		"blurb": "Pinpoint accurate while aimed, but it blacks out everything around it"},
]

# Bolt-ons that modify the gun's profile (see Weapon.set_class). Each is owned
# or not; `key` is the field on this object that stores that.
const UPGRADES: Array[Dictionary] = [
	{"key": "cooling", "name": "COOLING VANES", "cost": 20, "blurb": "-25% heat per shot, cools faster"},
	{"key": "grip", "name": "IMPROVED GRIP", "cost": 20, "blurb": "-35% hip spread, -30% kick"},
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

# GADGETS: one slot, on the rebindable "gadget" control. Each is a different
# verb rather than more damage — see Player._use_gadget and the gadget scenes.
enum Gadget { NONE, JETPACK, CABLE, SHIELD, ROTARY, TURRET, MORTAR,
	FORCE_PUSH, FORCE_PULL, FORCE_LEAP }
const GADGETS: Array[Dictionary] = [
	{"name": "NONE", "cost": 0, "blurb": "No gadget"},
	{"name": "JETPACK", "cost": 45,
		"blurb": "Hold the gadget button to fly. Fuel burns fast, refills on the ground"},
	{"name": "WRIST CABLE", "cost": 30,
		"blurb": "Grapple within 34 m, reel in and vault on top. 5s between uses"},
	{"name": "FRONT SHIELD", "cost": 50,
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
	{"name": "FORCE PUSH", "cost": 45,
		"blurb": "Throw everyone in front of you back off their feet. 6s"},
	{"name": "FORCE PULL", "cost": 40,
		"blurb": "Drag the one you are looking at to you, from 34 m. 7s"},
	{"name": "FORCE LEAP", "cost": 35,
		"blurb": "A Force-assisted bound: high, long, and it closes ground fast. 4s"},
]

## What a gadget costs to use again, in seconds. Only the force powers are on a
## cooldown of their own — everything else is a toggle, a placement, or (the
## cable) times itself.
const GADGET_COOLDOWNS := {
	Gadget.FORCE_PUSH: 6.0, Gadget.FORCE_PULL: 7.0, Gadget.FORCE_LEAP: 4.0,
}


const KITS: Array[Dictionary] = [
	{
		"name": "CLONE TROOPER",
		"blurb": "Republic line trooper. The full armoury and every deployable",
		"gadgets": [Gadget.NONE, Gadget.SHIELD, Gadget.ROTARY, Gadget.TURRET,
			Gadget.MORTAR],
		"gadget_slots": 1,
		"secondary_mods": [SecondaryMod.NONE, SecondaryMod.SCOPE, SecondaryMod.COOLING],
		"armor": [0, 1, 2, 3],
		"default_armor": 1,
		"grenades": true,
	},
	{
		"name": "MANDALORIAN",
		"blurb": "Two gadgets and no grenades. Flies, grapples, and the only one who dual-wields",
		"gadgets": [Gadget.NONE, Gadget.JETPACK, Gadget.CABLE],
		"gadget_slots": 2,
		"secondary_mods": [SecondaryMod.NONE, SecondaryMod.SCOPE, SecondaryMod.COOLING,
			SecondaryMod.DUAL],
		# No heavy plate: the kit's whole identity is moving, and the jetpack
		# already pays for its lift in fuel rather than in weight.
		"armor": [0, 1, 2],
		"default_armor": 0,   # LIGHT FRAME — "lighter armour by default"
		"grenades": false,
	},
	{
		"name": "FORCE ADEPT",
		"blurb": "Lightsaber only. Double jump, aim to block until you tire, and bend the fight with the Force",
		"gadgets": [Gadget.NONE, Gadget.FORCE_PUSH, Gadget.FORCE_PULL, Gadget.FORCE_LEAP],
		"gadget_slots": 1,
		"secondary_mods": [SecondaryMod.NONE, SecondaryMod.SCOPE, SecondaryMod.COOLING],
		"armor": [0, 1],
		"default_armor": 0,
		"grenades": false,
		"primaries": [Weapon.Class.SABER],
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

# Consumables, bought by the unit. You carry ONE type of grenade, chosen on its
# own row: they are different verbs, not different damage numbers, so mixing
# them would just mean carrying a worse version of each.
enum GrenadeType { FRAG, SMOKE, STICKY }
const GRENADE_TYPES: Array[Dictionary] = [
	{"name": "FRAG", "cost": 25, "blurb": "Bounces, 2s fuse, heavy splash"},
	{"name": "SMOKE", "cost": 15,
		"blurb": "Blinds the area for 9s — nothing sees through it, AI included"},
	{"name": "STICKY", "cost": 35,
		"blurb": "Sticks where it lands, people included, then detonates"},
]
const GRENADE_MAX := 3
const MEDKIT_COST := 30
const MEDKIT_MAX := 2
const MEDKIT_HEAL := 60.0

## The buy screen is one row per line, in this order. SIGHT/COOLING/GRIP sit
## directly under WEAPON because they now fit the PRIMARY only; the sidearm's
## single slot sits under SECONDARY for the same reason.
enum Row {
	KIT,
	WEAPON, SIGHT, COOLING, GRIP,
	SECONDARY, SECONDARY_MOD,
	GADGET, GADGET2, ARMOR, GRENADE_TYPE, GRENADES, MEDKITS, SQUAD, SQUAD_SKILL,
}

var kit := Kit.CLONE   # index into KITS; picks what the rest of this may be
var weapon := 0        # index into WEAPONS (NO_PRIMARY = sidearm only)
var secondary := 0     # index into SECONDARIES
var secondary_mod := SecondaryMod.NONE
var grenade_type := GrenadeType.FRAG
var gadget := 0        # index into GADGETS, on the gadget control
## The Mandalorian's second gadget, on the GRENADE control. That button is free
## for exactly the class that carries two gadgets, because the same class is the
## one that carries no grenades — which is why a second binding was not added.
var gadget2 := 0
## Primary-only upgrades. The sidearm has its own slot and ignores these.
var sight := Sight.NONE
var cooling := false
var grip := false
var armor := DEFAULT_ARMOR  # index into ARMOR
var grenades := 0
var medkits := 0
var squad := 0        # how many AI squadmates
var squad_skill := 1  # index into SQUAD_SKILLS, paid per squadmate


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
		"armor": 2, "grenades": 1},                                    # 45+20+25+25
	{"name": "MARKSMAN", "weapon": 10, "secondary": 0, "sight": Sight.SCOPE,
		"armor": 0, "grip": true},                                     # 85+25+20+20
	{"name": "GUNNER", "weapon": 9, "secondary": 0, "sight": Sight.NONE,
		"armor": 3, "cooling": true},                                  # 80+60+20
	{"name": "ENGINEER", "weapon": 2, "secondary": 3, "sight": Sight.HOLO,
		"gadget": Gadget.TURRET, "armor": 1},                          # 45+35+20+65
	# SCOUT and SKIRMISHER carry the wrist cable, which is the Mandalorian's, so
	# they ARE Mandalorians — the kit_rules test caught them the moment the
	# gadget moved and they would otherwise have deployed illegal builds.
	{"name": "SCOUT", "kit": Kit.MANDALORIAN, "weapon": 5, "secondary": 2,
		"sight": Sight.HOLO,
		"gadget": Gadget.CABLE, "armor": 0, "medkits": 1},             # 55+20+20+30+20+30
	{"name": "GRENADIER", "weapon": 3, "secondary": 0, "sight": Sight.HOLO,
		"armor": 2, "grenades": 3},                                    # 50+20+25+75
	{"name": "SHOCK", "weapon": 7, "secondary": 0, "sight": Sight.NONE,
		"gadget": Gadget.SHIELD, "armor": 2, "medkits": 1},            # 70+50+25+30
	# New guns get presets of their own, so the AI actually field them.
	{"name": "BREACHER", "weapon": 6, "secondary": 1, "sight": Sight.NONE,
		"armor": 2, "grenades": 1},                                    # 60+15+25+25
	{"name": "SKIRMISHER", "kit": Kit.MANDALORIAN, "weapon": 1, "secondary": 2,
		"sight": Sight.HOLO,
		"armor": 0, "gadget": Gadget.CABLE, "medkits": 1},             # 40+20+20+20+30+30
	{"name": "DESIGNATOR", "weapon": 8, "secondary": 0, "sight": Sight.NONE,
		"armor": 1, "gadget": Gadget.MORTAR, "grenades": 1},           # 75+60+25
	# The other two classes field presets of their own, so a match actually has
	# Mandalorians and Force adepts in it rather than three flavours of trooper.
	# Both are legal for their kit: check `allows` before changing either.
	{"name": "BOUNTY HUNTER", "kit": Kit.MANDALORIAN, "weapon": 4, "secondary": 1,
		"sight": Sight.HOLO, "armor": 0, "gadget": Gadget.CABLE,
		"gadget2": Gadget.JETPACK},                                    # 50+15+20+20+30+45
	{"name": "DUELLIST", "kit": Kit.FORCE, "weapon": 12, "secondary": 0,
		"sight": Sight.NONE, "armor": 0, "gadget": Gadget.FORCE_PUSH,
		"medkits": 1},                                                 # 55+20+45+30
]


## Build one of the AI presets. Anything the preset leaves out keeps its default.
static func bot_build(index: int) -> Loadout:
	var preset: Dictionary = BOT_BUILDS[wrapi(index, 0, BOT_BUILDS.size())]
	var built := Loadout.new()
	for key in preset:
		if key != "name":
			built.set(key, preset[key])
	return built


## What you drop in with in battle royale: the free sidearm and nothing else.
## Everything better is on the ground, which is the entire mode.
static func royale_start() -> Loadout:
	var l := Loadout.new()
	l.weapon = NO_PRIMARY
	l.secondary = 0
	l.gadget = Gadget.NONE
	l.armor = DEFAULT_ARMOR
	l.grenades = 0
	l.medkits = 0
	l.squad = 0
	return l


## A starter build that spends part of the budget: standard armour, basic rifle.
## The gun is looked up by CLASS, not by a literal index — inserting a cheaper
## primary into WEAPONS silently changed what every player deployed with.
static func starter() -> Loadout:
	var l := Loadout.new()
	l.weapon = weapon_index(Weapon.Class.SOLDIER)
	return l


## Where a gun sits in WEAPONS, or NO_PRIMARY if it isn't sold as a primary.
static func weapon_index(gun: Weapon.Class) -> int:
	for i in WEAPONS.size():
		if WEAPONS[i]["class"] == gun:
			return i
	return NO_PRIMARY


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


func has_grenades() -> bool:
	return bool(KITS[kit]["grenades"])


## True if this kit may hold that entry on that row. Rows with no restriction
## answer true for everything, so a new row costs nothing here.
func allows(row: int, index: int) -> bool:
	var k := KITS[kit]
	match row:
		Row.WEAPON:
			var entry: Dictionary = WEAPONS[index]
			var only: Array = k.get("primaries", [])
			if not only.is_empty():
				return entry["class"] in only
			# No explicit list: everything except another kit's signature weapon.
			return not entry.has("kit")
		Row.GADGET, Row.GADGET2:
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


## True if the row exists at all for this kit. A row that is unavailable is
## hidden on the buy screen and skipped by the cursor, rather than shown as a
## line you can sit on and not change — four players shop at once and a dead
## line reads as a broken screen.
func row_available(row: int) -> bool:
	match row:
		Row.GADGET2:
			return gadget_slots() >= 2
		Row.GRENADE_TYPE, Row.GRENADES:
			return has_grenades()
		Row.SIGHT, Row.COOLING, Row.GRIP:
			# Sights and cooling vanes on a sword are nothing. They are also the
			# rows that would otherwise let a Force adept spend 65 tokens on
			# absolutely no effect.
			return has_primary() and not primary_is_melee()
	return true


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
	# A kit with exactly one legal primary is holding it, not choosing it.
	var only: Array = k.get("primaries", [])
	fresh.weapon = weapon_index(only[0]) if not only.is_empty() else NO_PRIMARY
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
	total += grenades * int(GRENADE_TYPES[grenade_type]["cost"])
	total += medkits * MEDKIT_COST
	total += squad_cost()
	return total


## The squad is priced per head, so raising skill raises the whole bill.
func squad_cost() -> int:
	return squad * int(SQUAD_SKILLS[squad_skill]["cost"])


func remaining() -> int:
	return BUDGET - cost()


## The primary gun, or -1 when you bought none.
func weapon_class() -> int:
	return WEAPONS[weapon]["class"]


func has_primary() -> bool:
	return weapon != NO_PRIMARY


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


func armor_stats() -> Dictionary:
	return ARMOR[armor]


func squad_skill_stats() -> Dictionary:
	return SQUAD_SKILLS[squad_skill]


## The PRIMARY's upgrade flags, in the shape Weapon.set_class wants.
func primary_mods() -> Dictionary:
	return {"sight": sight, "cooling": cooling, "grip": grip}


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


func grenade_type_stats() -> Dictionary:
	return GRENADE_TYPES[grenade_type]


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
			adopt_kit(clampi(kit + dir, 0, KITS.size() - 1))
		Row.WEAPON:
			weapon = _walk(row, weapon, dir, WEAPONS.size())
		Row.SECONDARY:
			secondary = clampi(secondary + dir, 0, SECONDARIES.size() - 1)
		Row.SECONDARY_MOD:
			secondary_mod = _walk(row, secondary_mod, dir, SECONDARY_MODS.size())
		Row.GRENADE_TYPE:
			grenade_type = clampi(grenade_type + dir, 0, GRENADE_TYPES.size() - 1)
		Row.GADGET:
			gadget = _walk(row, gadget, dir, GADGETS.size())
		Row.GADGET2:
			gadget2 = _walk(row, gadget2, dir, GADGETS.size())
		Row.SIGHT:
			sight = clampi(sight + dir, 0, SIGHTS.size() - 1)
		Row.COOLING:
			cooling = not cooling
		Row.GRIP:
			grip = not grip
		Row.ARMOR:
			armor = _walk(row, armor, dir, ARMOR.size())
		Row.GRENADES:
			grenades = clampi(grenades + dir, 0, GRENADE_MAX)
		Row.MEDKITS:
			medkits = clampi(medkits + dir, 0, MEDKIT_MAX)
		Row.SQUAD:
			squad = clampi(squad + dir, 0, SQUAD_MAX)
		Row.SQUAD_SKILL:
			squad_skill = clampi(squad_skill + dir, 0, SQUAD_SKILLS.size() - 1)


func _same_as(other: Loadout) -> bool:
	return kit == other.kit \
		and weapon == other.weapon and secondary == other.secondary \
		and secondary_mod == other.secondary_mod \
		and grenade_type == other.grenade_type \
		and gadget == other.gadget and gadget2 == other.gadget2 \
		and sight == other.sight \
		and cooling == other.cooling and grip == other.grip \
		and armor == other.armor and grenades == other.grenades \
		and medkits == other.medkits and squad == other.squad \
		and squad_skill == other.squad_skill


func _copy_from(other: Loadout) -> void:
	kit = other.kit
	gadget2 = other.gadget2
	weapon = other.weapon
	secondary = other.secondary
	secondary_mod = other.secondary_mod
	grenade_type = other.grenade_type
	gadget = other.gadget
	sight = other.sight
	cooling = other.cooling
	grip = other.grip
	armor = other.armor
	grenades = other.grenades
	medkits = other.medkits
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
		Row.GRENADE_TYPE: return "GRENADE"
		Row.GADGET: return "GADGET"
		Row.GADGET2: return "GADGET 2"
		Row.SIGHT: return "SIGHT"
		Row.ARMOR: return "ARMOR"
		Row.GRENADES: return "GRENADES"
		Row.MEDKITS: return "HEALTH KIT"
		Row.SQUAD: return "AI SQUAD"
		Row.SQUAD_SKILL: return "SQUAD SKILL"
		_: return UPGRADES[_upgrade_index(row)]["name"]


func row_value(row: int) -> String:
	match row:
		Row.KIT: return kit_name()
		Row.WEAPON: return weapon_name()
		Row.SECONDARY: return secondary_name()
		Row.SECONDARY_MOD: return SECONDARY_MODS[secondary_mod]["name"]
		Row.GRENADE_TYPE: return GRENADE_TYPES[grenade_type]["name"]
		Row.GADGET: return GADGETS[gadget]["name"]
		Row.GADGET2: return GADGETS[gadget2]["name"]
		Row.SIGHT: return SIGHTS[sight]["name"]
		Row.ARMOR: return ARMOR[armor]["name"]
		Row.GRENADES: return "x%d" % grenades if grenades > 0 else "none"
		Row.MEDKITS: return "x%d" % medkits if medkits > 0 else "none"
		Row.SQUAD: return "x%d" % squad if squad > 0 else "none"
		Row.SQUAD_SKILL: return SQUAD_SKILLS[squad_skill]["name"]
		_: return "fitted" if get(UPGRADES[_upgrade_index(row)]["key"]) else "none"


func row_cost(row: int) -> int:
	match row:
		Row.KIT: return 0  # the class is free; what it lets you buy is not
		Row.WEAPON: return WEAPONS[weapon]["cost"]
		Row.SECONDARY: return SECONDARIES[secondary]["cost"]
		Row.SECONDARY_MOD: return SECONDARY_MODS[secondary_mod]["cost"]
		Row.GRENADE_TYPE: return 0  # the type is free; the rounds are what cost
		Row.GADGET: return GADGETS[gadget]["cost"]
		Row.GADGET2: return GADGETS[gadget2]["cost"]
		Row.SIGHT: return SIGHTS[sight]["cost"]
		Row.ARMOR: return ARMOR[armor]["cost"]
		Row.GRENADES: return grenades * int(GRENADE_TYPES[grenade_type]["cost"])
		Row.MEDKITS: return medkits * MEDKIT_COST
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
		Row.GRENADE_TYPE:
			return GRENADE_TYPES[grenade_type]["blurb"]
		Row.GADGET:
			return GADGETS[gadget]["blurb"]
		Row.GADGET2:
			return "%s   (on %s)" % [GADGETS[gadget2]["blurb"],
				Controls.label(device, "grenade")]
		Row.SIGHT:
			return "%s   (primary only)" % SIGHTS[sight]["blurb"]
		Row.ARMOR:
			var a := armor_stats()
			return "%s   %d HP" % [a["blurb"], roundi(a["health"])]
		Row.GRENADES:
			return "%s, %d each, thrown with %s" % [
				GRENADE_TYPES[grenade_type]["name"],
				GRENADE_TYPES[grenade_type]["cost"], Controls.label(device, "grenade")]
		Row.MEDKITS:
			return "%d each, heals %d with %s" % [
				MEDKIT_COST, roundi(MEDKIT_HEAL), Controls.label(device, "medkit")]
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
