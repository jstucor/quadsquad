class_name Kit
extends RefCounted
## The four playable classes. A kit is the loadout you pick when you deploy and
## on every death: which weapons you may cycle through (Q / Y in-match) and the
## body stats that go with them. All per-class numbers live here, the way all
## per-weapon numbers live in Weapon.PROFILES.
##
## `health` is absolute; `speed` and `jump` are multipliers on the Player's base
## walk/sprint speed and jump velocity, so tuning the baseline still moves
## everyone together.

const KITS: Array[Dictionary] = [
	{
		"name": "ASSAULT",
		"blurb": "All-rounder. Standard armour and pace.",
		"weapons": [Weapon.Class.SOLDIER, Weapon.Class.BURST],
		"health": 100.0, "speed": 1.0, "jump": 1.0,
	},
	{
		"name": "SPECIALIST",
		"blurb": "Fast and high-jumping, but thin armour.",
		"weapons": [Weapon.Class.SNIPER, Weapon.Class.SEMI],
		"health": 80.0, "speed": 1.12, "jump": 1.12,
	},
	{
		"name": "OFFICER",
		"blurb": "Sidearms only. Standard armour and pace.",
		"weapons": [Weapon.Class.REVOLVER, Weapon.Class.PISTOL],
		"health": 100.0, "speed": 1.0, "jump": 1.0,
	},
	{
		"name": "HEAVY",
		"blurb": "Heavy armour, heavy guns. Slow, low jump.",
		"weapons": [Weapon.Class.HEAVY, Weapon.Class.HMG, Weapon.Class.RPG],
		"health": 140.0, "speed": 0.88, "jump": 0.9,
	},
]


static func count() -> int:
	return KITS.size()


static func get_kit(index: int) -> Dictionary:
	return KITS[wrapi(index, 0, KITS.size())]


## "DC-15 Rifle / EL-16 Burst" — the loadout line shown on the class screen.
static func weapon_line(index: int) -> String:
	var names: Array[String] = []
	for c in get_kit(index)["weapons"]:
		names.append(Weapon.PROFILES[c]["name"])
	return " / ".join(names)
