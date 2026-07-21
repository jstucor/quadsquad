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

# PRIMARY guns, cheapest first (the menu walks them in this order). "None" is a
# real option: your sidearm is free, so an all-gadget build can skip the rifle
# entirely and still deploy armed.
const WEAPONS: Array[Dictionary] = [
	{"class": -1, "cost": 0},  # -1 = no primary, sidearm only
	{"class": Weapon.Class.SOLDIER, "cost": 45},
	{"class": Weapon.Class.BURST, "cost": 50},
	{"class": Weapon.Class.SEMI, "cost": 55},
	{"class": Weapon.Class.HEAVY, "cost": 70},
	{"class": Weapon.Class.HMG, "cost": 80},
	{"class": Weapon.Class.SNIPER, "cost": 85},
	{"class": Weapon.Class.RPG, "cost": 110},
]
const NO_PRIMARY := 0  # index of the "none" row above

# SECONDARY: sidearms. Everyone carries one, and the cheapest is free, so you
# are never left without a gun. Q / Y swaps between primary and secondary.
const SECONDARIES: Array[Dictionary] = [
	{"class": Weapon.Class.PISTOL, "cost": 0},
	{"class": Weapon.Class.HOLDOUT, "cost": 20},
	{"class": Weapon.Class.REVOLVER, "cost": 35},
]

# Bolt-ons that modify the gun's profile (see Weapon.set_class). Each is owned
# or not; `key` is the field on this object that stores that.
const UPGRADES: Array[Dictionary] = [
	{"key": "scope", "name": "SCOPE", "cost": 25, "blurb": "Zoom optics + scope overlay"},
	{"key": "cooling", "name": "COOLING VANES", "cost": 20, "blurb": "-25% heat per shot, cools faster"},
	{"key": "grip", "name": "IMPROVED GRIP", "cost": 20, "blurb": "-35% hip spread, less bloom"},
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

# GADGETS: one slot, fired with F / pad X. Each is a different verb rather than
# more damage — see Player._use_gadget and the gadget scenes.
enum Gadget { NONE, JETPACK, CABLE, SHIELD, ROTARY, TURRET }
const GADGETS: Array[Dictionary] = [
	{"name": "NONE", "cost": 0, "blurb": "No gadget"},
	{"name": "JETPACK", "cost": 45,
		"blurb": "Hold F / X to fly. Fuel burns fast, refills on the ground"},
	{"name": "WRIST CABLE", "cost": 30,
		"blurb": "Grapple within 34 m, reel in and vault on top. 5s between uses"},
	{"name": "FRONT SHIELD", "cost": 50,
		"blurb": "Toggle a barrier that stops incoming fire. You can shoot through it"},
	{"name": "ROTARY CANNON", "cost": 75,
		"blurb": "Toggle a spin-up rotary gun. Huge output, but you walk"},
	{"name": "TURRET", "cost": 65,
		"blurb": "Drop an auto-turret that fights for you until it's destroyed"},
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

# Consumables, bought by the unit.
const GRENADE_COST := 25
const GRENADE_MAX := 3
const MEDKIT_COST := 30
const MEDKIT_MAX := 2
const MEDKIT_HEAL := 60.0

## The buy screen is one row per line, in this order.
enum Row { WEAPON, SECONDARY, SCOPE, COOLING, GRIP, GADGET, ARMOR, GRENADES, MEDKITS, SQUAD, SQUAD_SKILL }

var weapon := 0        # index into WEAPONS (NO_PRIMARY = sidearm only)
var secondary := 0     # index into SECONDARIES
var gadget := 0        # index into GADGETS
var scope := false
var cooling := false
var grip := false
var armor := DEFAULT_ARMOR  # index into ARMOR
var grenades := 0
var medkits := 0
var squad := 0        # how many AI squadmates
var squad_skill := 1  # index into SQUAD_SKILLS, paid per squadmate


## A starter build that spends part of the budget: standard armour, basic rifle.
static func starter() -> Loadout:
	var l := Loadout.new()
	l.weapon = 1  # DC-15 Rifle
	return l


## Delegates to _copy_from so there's exactly one list of fields to keep in
## step with — step() trials changes on a duplicate, so a field missed here
## would be silently reset by any edit to another row.
func duplicate_loadout() -> Loadout:
	var copy := Loadout.new()
	copy._copy_from(self)
	return copy


func cost() -> int:
	var total: int = WEAPONS[weapon]["cost"]
	total += SECONDARIES[secondary]["cost"]
	total += GADGETS[gadget]["cost"]
	total += ARMOR[armor]["cost"]
	for up in UPGRADES:
		if get(up["key"]):
			total += int(up["cost"])
	total += grenades * GRENADE_COST
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


func armor_stats() -> Dictionary:
	return ARMOR[armor]


func squad_skill_stats() -> Dictionary:
	return SQUAD_SKILLS[squad_skill]


## The upgrade flags in the shape Weapon.set_class wants.
func weapon_mods() -> Dictionary:
	return {"scope": scope, "cooling": cooling, "grip": grip}


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


func _step_unchecked(row: int, dir: int) -> void:
	match row:
		Row.WEAPON:
			weapon = clampi(weapon + dir, 0, WEAPONS.size() - 1)
		Row.SECONDARY:
			secondary = clampi(secondary + dir, 0, SECONDARIES.size() - 1)
		Row.GADGET:
			gadget = clampi(gadget + dir, 0, GADGETS.size() - 1)
		Row.SCOPE:
			scope = not scope
		Row.COOLING:
			cooling = not cooling
		Row.GRIP:
			grip = not grip
		Row.ARMOR:
			armor = clampi(armor + dir, 0, ARMOR.size() - 1)
		Row.GRENADES:
			grenades = clampi(grenades + dir, 0, GRENADE_MAX)
		Row.MEDKITS:
			medkits = clampi(medkits + dir, 0, MEDKIT_MAX)
		Row.SQUAD:
			squad = clampi(squad + dir, 0, SQUAD_MAX)
		Row.SQUAD_SKILL:
			squad_skill = clampi(squad_skill + dir, 0, SQUAD_SKILLS.size() - 1)


func _same_as(other: Loadout) -> bool:
	return weapon == other.weapon and secondary == other.secondary \
		and gadget == other.gadget and scope == other.scope \
		and cooling == other.cooling and grip == other.grip \
		and armor == other.armor and grenades == other.grenades \
		and medkits == other.medkits and squad == other.squad \
		and squad_skill == other.squad_skill


func _copy_from(other: Loadout) -> void:
	weapon = other.weapon
	secondary = other.secondary
	gadget = other.gadget
	scope = other.scope
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
		Row.WEAPON: return "PRIMARY"
		Row.SECONDARY: return "SIDEARM"
		Row.GADGET: return "GADGET"
		Row.ARMOR: return "ARMOR"
		Row.GRENADES: return "GRENADES"
		Row.MEDKITS: return "HEALTH KIT"
		Row.SQUAD: return "AI SQUAD"
		Row.SQUAD_SKILL: return "SQUAD SKILL"
		_: return UPGRADES[_upgrade_index(row)]["name"]


func row_value(row: int) -> String:
	match row:
		Row.WEAPON: return weapon_name()
		Row.SECONDARY: return secondary_name()
		Row.GADGET: return GADGETS[gadget]["name"]
		Row.ARMOR: return ARMOR[armor]["name"]
		Row.GRENADES: return "x%d" % grenades if grenades > 0 else "none"
		Row.MEDKITS: return "x%d" % medkits if medkits > 0 else "none"
		Row.SQUAD: return "x%d" % squad if squad > 0 else "none"
		Row.SQUAD_SKILL: return SQUAD_SKILLS[squad_skill]["name"]
		_: return "fitted" if get(UPGRADES[_upgrade_index(row)]["key"]) else "none"


func row_cost(row: int) -> int:
	match row:
		Row.WEAPON: return WEAPONS[weapon]["cost"]
		Row.SECONDARY: return SECONDARIES[secondary]["cost"]
		Row.GADGET: return GADGETS[gadget]["cost"]
		Row.ARMOR: return ARMOR[armor]["cost"]
		Row.GRENADES: return grenades * GRENADE_COST
		Row.MEDKITS: return medkits * MEDKIT_COST
		Row.SQUAD, Row.SQUAD_SKILL: return squad_cost()
		_:
			var up: Dictionary = UPGRADES[_upgrade_index(row)]
			return int(up["cost"]) if get(up["key"]) else 0


func row_blurb(row: int) -> String:
	match row:
		Row.WEAPON:
			if not has_primary():
				return "No primary — you deploy with your sidearm"
			var p: Dictionary = Weapon.PROFILES[weapon_class()]
			return "%d dmg   %.0fm range" % [p["damage"], p["range"]]
		Row.SECONDARY:
			var sp: Dictionary = Weapon.PROFILES[secondary_class()]
			return "%d dmg   swap with Q / Y" % sp["damage"]
		Row.GADGET:
			return GADGETS[gadget]["blurb"]
		Row.ARMOR:
			var a := armor_stats()
			return "%s   %d HP" % [a["blurb"], roundi(a["health"])]
		Row.GRENADES:
			return "%d each, thrown with G / d-pad up" % GRENADE_COST
		Row.MEDKITS:
			return "%d each, heals %d with H / d-pad down" % [MEDKIT_COST, roundi(MEDKIT_HEAL)]
		Row.SQUAD:
			var each: int = SQUAD_SKILLS[squad_skill]["cost"]
			return "%d each at %s   (max %d, they fight for your team)" % [
				each, SQUAD_SKILLS[squad_skill]["name"], SQUAD_MAX]
		Row.SQUAD_SKILL:
			var skill: Dictionary = SQUAD_SKILLS[squad_skill]
			return "%s   (%d each)" % [skill["blurb"], skill["cost"]]
		_:
			var up: Dictionary = UPGRADES[_upgrade_index(row)]
			return "%s   (%d)" % [up["blurb"], up["cost"]]


func _upgrade_index(row: int) -> int:
	return row - Row.SCOPE  # SCOPE/COOLING/GRIP are contiguous, in UPGRADES order
