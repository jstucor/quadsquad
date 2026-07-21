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

# Guns, cheapest first (the menu walks them in this order). The pistol costs
# nothing so an all-in armour/gear build still deploys with something.
const WEAPONS: Array[Dictionary] = [
	{"class": Weapon.Class.PISTOL, "cost": 0},
	{"class": Weapon.Class.REVOLVER, "cost": 35},
	{"class": Weapon.Class.SOLDIER, "cost": 45},
	{"class": Weapon.Class.BURST, "cost": 50},
	{"class": Weapon.Class.SEMI, "cost": 55},
	{"class": Weapon.Class.HEAVY, "cost": 70},
	{"class": Weapon.Class.HMG, "cost": 80},
	{"class": Weapon.Class.SNIPER, "cost": 85},
	{"class": Weapon.Class.RPG, "cost": 110},
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

# Consumables, bought by the unit.
const GRENADE_COST := 25
const GRENADE_MAX := 3
const MEDKIT_COST := 30
const MEDKIT_MAX := 2
const MEDKIT_HEAL := 60.0

## The buy screen is one row per line, in this order.
enum Row { WEAPON, SCOPE, COOLING, GRIP, ARMOR, GRENADES, MEDKITS }

var weapon := 0        # index into WEAPONS
var scope := false
var cooling := false
var grip := false
var armor := DEFAULT_ARMOR  # index into ARMOR
var grenades := 0
var medkits := 0


## A starter build that spends part of the budget: standard armour, basic rifle.
static func starter() -> Loadout:
	var l := Loadout.new()
	l.weapon = 2  # DC-15 Rifle
	return l


func duplicate_loadout() -> Loadout:
	var l := Loadout.new()
	l.weapon = weapon
	l.scope = scope
	l.cooling = cooling
	l.grip = grip
	l.armor = armor
	l.grenades = grenades
	l.medkits = medkits
	return l


func cost() -> int:
	var total: int = WEAPONS[weapon]["cost"]
	total += ARMOR[armor]["cost"]
	for up in UPGRADES:
		if get(up["key"]):
			total += int(up["cost"])
	total += grenades * GRENADE_COST
	total += medkits * MEDKIT_COST
	return total


func remaining() -> int:
	return BUDGET - cost()


func weapon_class() -> Weapon.Class:
	return WEAPONS[weapon]["class"] as Weapon.Class


func weapon_name() -> String:
	return Weapon.PROFILES[weapon_class()]["name"]


func armor_stats() -> Dictionary:
	return ARMOR[armor]


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


func _same_as(other: Loadout) -> bool:
	return weapon == other.weapon and scope == other.scope \
		and cooling == other.cooling and grip == other.grip \
		and armor == other.armor and grenades == other.grenades \
		and medkits == other.medkits


func _copy_from(other: Loadout) -> void:
	weapon = other.weapon
	scope = other.scope
	cooling = other.cooling
	grip = other.grip
	armor = other.armor
	grenades = other.grenades
	medkits = other.medkits


## Display: the fixed name of a row, what's currently selected on it, what that
## selection costs, and a one-line explanation. Drives the whole buy screen.
func row_label(row: int) -> String:
	match row:
		Row.WEAPON: return "WEAPON"
		Row.ARMOR: return "ARMOR"
		Row.GRENADES: return "GRENADES"
		Row.MEDKITS: return "HEALTH KIT"
		_: return UPGRADES[_upgrade_index(row)]["name"]


func row_value(row: int) -> String:
	match row:
		Row.WEAPON: return weapon_name()
		Row.ARMOR: return ARMOR[armor]["name"]
		Row.GRENADES: return "x%d" % grenades if grenades > 0 else "none"
		Row.MEDKITS: return "x%d" % medkits if medkits > 0 else "none"
		_: return "fitted" if get(UPGRADES[_upgrade_index(row)]["key"]) else "none"


func row_cost(row: int) -> int:
	match row:
		Row.WEAPON: return WEAPONS[weapon]["cost"]
		Row.ARMOR: return ARMOR[armor]["cost"]
		Row.GRENADES: return grenades * GRENADE_COST
		Row.MEDKITS: return medkits * MEDKIT_COST
		_:
			var up: Dictionary = UPGRADES[_upgrade_index(row)]
			return int(up["cost"]) if get(up["key"]) else 0


func row_blurb(row: int) -> String:
	match row:
		Row.WEAPON:
			var p: Dictionary = Weapon.PROFILES[weapon_class()]
			return "%d dmg   %.0fm range" % [p["damage"], p["range"]]
		Row.ARMOR:
			var a := armor_stats()
			return "%s   %d HP" % [a["blurb"], roundi(a["health"])]
		Row.GRENADES:
			return "%d each, thrown with G / d-pad up" % GRENADE_COST
		Row.MEDKITS:
			return "%d each, heals %d with H / d-pad down" % [MEDKIT_COST, roundi(MEDKIT_HEAL)]
		_:
			var up: Dictionary = UPGRADES[_upgrade_index(row)]
			return "%s   (%d)" % [up["blurb"], up["cost"]]


func _upgrade_index(row: int) -> int:
	return row - Row.SCOPE  # SCOPE/COOLING/GRIP are contiguous, in UPGRADES order
