class_name Streaks
extends Object
## KILL STREAK REWARDS: what a life that is going well earns you.
##
## A streak is `Player.kills_this_life`, which the HUD has counted since long
## before this existed and which resets on death. That is the whole economy —
## nothing is banked, nothing is bought, and dying costs you everything you were
## working toward. **It is per LIFE and not per match on purpose**: a reward you
## keep across deaths is a reward the best player accumulates and the worst
## player watches, where a streak that dies with you is a thing anybody can start
## on their next spawn.
##
## THERE ARE TWO KINDS OF REWARD AND THE SPLIT IS THE DESIGN. It is the same
## distinction the third gadget slot already makes (see CLAUDE.md, gadget slots):
##
##   CALL-IN   something happens somewhere else. Recon, orbital strike, a walker
##             delivered to you. You carry on being what you were.
##   BECOME    something happens to YOU. Juggernaut, Jedi Master. You stop being
##             a trooper and the rest of the life is played as something else.
##
## **EVERY REWARD FIRES THE MOMENT IT IS EARNED, and takes no button.** Not for
## want of a design — CoD hands you a key — but because this game has no free
## one: A jump, B swap, X gadget, Y sustain, LB gadget 2, R3 crouch, and the
## project's own rule is that every prompt names a rebindable control rather than
## a key. A reward that had to be triggered would need a seventh face button, a
## chord, or a screen, and all three cost more than the tactical choice is worth
## at a couch where three other people are still playing.
##
## A REWARD IS A TABLE ROW, and a BECOME reward's row is an ORDINARY PRESET in
## the same format as every AI build and authored class in the game (see
## `Loadout.preset_build`). A new reward is a row here plus, at most, one case in
## `Player._grant_streak`.

enum Kind { RECON, BOMBARDMENT, VEHICLE, BECOME, GUNSHIP }

## A REWARD BELONGS TO A FACTION, AND TO NOTHING ELSE.
##
## It was gated on KIT as well, which meant the reward you could earn depended on
## what you had bought that life — so a Republic player in a clone kit and one in
## a Force kit were fighting for different prizes on the same side, and switching
## class mid-match silently changed the ladder under you. A faction is the thing a
## player picks once and identifies with, and it is the same answer for every one
## of that side's eight classes.
##
##   `factions` — {universe: [team indices]}. A universe absent from the map does
##                not get the reward at all. NO `factions` key means everybody,
##                in every setting.
##
## Stated as a MAP rather than as a `universe` + `teams` pair because a reward can
## belong to different sides in different settings — the Juggernaut is the CIS's
## and the Rebels' in Star Wars and everybody's in Halo — and the pair cannot
## express that without two rows that would then drift apart.
## THE LADDER IS THE SAME SHAPE FOR EVERY FACTION: two rewards anybody can earn,
## then that side's OWN signature, and for Star Wars a fourth at the top.
const KILLS_RECON := 4
const KILLS_ORBITAL := 7
const KILLS_SIGNATURE := 10
const KILLS_FORCE := 14

## The signature presets are all the same shape, so the shared parts are stated
## once here and merged in by `_signature`. What each faction actually states is
## the three things that make it itself: a NAME, a BODY and a WEAPON.
const SIGNATURE_BLURB := "Your side's finest takes the field"


const REWARDS: Array[Dictionary] = [
	# =========================================================================
	# EVERY FACTION, EVERY SETTING. These two carry no `factions` key at all,
	# which is what makes them universal — the ladder every side shares before it
	# gets to its own.
	# =========================================================================
	{
		"name": "RECON SWEEP", "kills": KILLS_RECON, "kind": Kind.RECON,
		"blurb": "Your side sees every enemy for a while",
		"duration": 14.0,
	},
	# THE ORBITAL STRIKE IS DELIBERATELY UNIVERSAL. Every side has somebody
	# overhead, and it is the one reward that asks nothing of what you are — no
	# body to become, no machine to climb into, no faction hardware. It is the
	# rung that keeps the ladder the same height for a Grot and a Space Marine.
	{
		"name": "ORBITAL STRIKE", "kills": KILLS_ORBITAL, "kind": Kind.BOMBARDMENT,
		"blurb": "A battery walks fire across the enemy's densest ground",
		"duration": 7.0,
	},

	# =========================================================================
	# ONE SIGNATURE PER FACTION, AND NO TWO SIDES SHARE ONE.
	#
	# This is the rule `tests/streaks.gd` enforces, and it is here because the
	# first version had SIX factions sharing a generic "Juggernaut" — which is
	# the same failure as the first roster pass (CLONE PILOT and REBEL HEAVY
	# carrying recycled rifles): a reward generated from an adjective rather than
	# designed from the fanbase's own vocabulary. A Necron Lord and an Ork
	# Warboss are not two skins on one Juggernaut, and if they were, there would
	# be no reason to care which side you were on.
	#
	# Every one is a BECOME except the Republic's and the Empire's, which were
	# asked for as machines. The body and the gun are the whole of each row: the
	# mechanism underneath is identical and stated once.
	# =========================================================================

	# ---- STAR WARS -----------------------------------------------------------
	{
		"name": "LAAT GUNSHIP", "kills": KILLS_SIGNATURE, "kind": Kind.GUNSHIP,
		"blurb": "Ride the ball turret while it circles the field",
		"factions": {Loadout.Universe.STAR_WARS: [0]},
		"duration": 22.0,
	},
	{
		"name": "DROIDEKA PRIME", "kills": KILLS_SIGNATURE, "kind": Kind.BECOME,
		"blurb": "Paired repeaters behind a shield, and no way to run",
		"factions": {Loadout.Universe.STAR_WARS: [1]},
		"overshield": 320.0,
		"preset": {
			"name": "DROIDEKA PRIME", "kit": Loadout.Kit.CLONE,
			"primary": Weapon.Class.DROIDEKA_TWIN, "sidearm": Weapon.Class.PISTOL,
			"armor": 3, "style": CharacterModel.Style.DROIDEKA,
			"unit_health": 2.0, "unit_speed": 0.72, "unit_stature": 0.95,
		},
	},
	{
		"name": "AT-ST WALKER", "kills": KILLS_SIGNATURE, "kind": Kind.VEHICLE,
		"blurb": "A walker is dropped in beside you",
		"factions": {Loadout.Universe.STAR_WARS: [2]},
		"vehicle": "atst",
	},
	{
		"name": "WOOKIEE CHIEFTAIN", "kills": KILLS_SIGNATURE, "kind": Kind.BECOME,
		"blurb": "Two metres of fur, plate and bowcaster",
		"factions": {Loadout.Universe.STAR_WARS: [3]},
		"overshield": 220.0,
		"preset": {
			"name": "WOOKIEE CHIEFTAIN", "kit": Loadout.Kit.WOOKIEE,
			"primary": Weapon.Class.HMG, "sidearm": Weapon.Class.BOWCASTER,
			"armor": 3, "style": CharacterModel.Style.WOOKIEE,
			"unit_health": 2.2, "unit_speed": 0.88, "unit_stature": 1.14,
		},
	},

	# ---- HALO ----------------------------------------------------------------
	{
		"name": "SPARTAN HEADHUNTER", "kills": KILLS_SIGNATURE, "kind": Kind.BECOME,
		"blurb": "Mjolnir plate and a shield that comes back",
		"factions": {Loadout.Universe.HALO: [0]},
		"overshield": 300.0,
		"preset": {
			"name": "SPARTAN HEADHUNTER", "kit": Loadout.Kit.SPARTAN,
			"primary": Weapon.Class.M247_HMG, "sidearm": Weapon.Class.M6D,
			"armor": 3, "style": CharacterModel.Style.SPARTAN,
			"unit_health": 2.1, "unit_speed": 1.05, "unit_stature": 1.10,
		},
	},
	{
		"name": "SANGHEILI ZEALOT", "kills": KILLS_SIGNATURE, "kind": Kind.BECOME,
		"blurb": "An energy sword and the speed to reach you with it",
		"factions": {Loadout.Universe.HALO: [1]},
		"overshield": 280.0,
		"preset": {
			"name": "SANGHEILI ZEALOT", "kit": Loadout.Kit.SANGHEILI,
			"primary": Weapon.Class.ENERGY_SWORD,
			"sidearm": Weapon.Class.PLASMA_PISTOL,
			"armor": 2, "style": CharacterModel.Style.ELITE_ULTRA,
			"unit_health": 1.9, "unit_speed": 1.22, "unit_stature": 1.14,
		},
	},

	# ---- WARHAMMER 40,000 ----------------------------------------------------
	{
		"name": "TERMINATOR", "kills": KILLS_SIGNATURE, "kind": Kind.BECOME,
		"blurb": "Tactical Dreadnought armour and a heavy bolter",
		"factions": {Loadout.Universe.WARHAMMER: [0]},
		"overshield": 340.0,
		"preset": {
			"name": "TERMINATOR", "kit": Loadout.Kit.ULTRAMARINE,
			"primary": Weapon.Class.HEAVY_BOLTER,
			"sidearm": Weapon.Class.BOLT_PISTOL,
			"armor": 3, "style": CharacterModel.Style.ULTRAMARINE,
			"unit_health": 2.6, "unit_speed": 0.70, "unit_stature": 1.16,
		},
	},
	{
		"name": "SANGUINARY EXEMPLAR", "kills": KILLS_SIGNATURE, "kind": Kind.BECOME,
		"blurb": "Gold plate, a power sword and wings to arrive on",
		"factions": {Loadout.Universe.WARHAMMER: [1]},
		"overshield": 240.0,
		"preset": {
			"name": "SANGUINARY EXEMPLAR", "kit": Loadout.Kit.BLOOD_ANGEL,
			"primary": Weapon.Class.POWER_SWORD,
			"sidearm": Weapon.Class.PLASMA_PISTOL_40K,
			"armor": 2, "style": CharacterModel.Style.BLOOD_ANGEL,
			"unit_health": 2.0, "unit_speed": 1.18, "unit_jump": 1.45,
			"unit_stature": 1.12,
		},
	},
	{
		"name": "NECRON OVERLORD", "kills": KILLS_SIGNATURE, "kind": Kind.BECOME,
		"blurb": "A warscythe, and it gets back up",
		"factions": {Loadout.Universe.WARHAMMER: [2]},
		"overshield": 260.0,
		"preset": {
			"name": "NECRON OVERLORD", "kit": Loadout.Kit.NECRON,
			"primary": Weapon.Class.WARSCYTHE,
			"sidearm": Weapon.Class.GAUSS_PISTOL,
			"armor": 3, "style": CharacterModel.Style.NECRON_LORD,
			"unit_health": 2.4, "unit_speed": 0.92, "unit_stature": 1.15,
		},
	},
	{
		"name": "ORK WARBOSS", "kills": KILLS_SIGNATURE, "kind": Kind.BECOME,
		"blurb": "A power klaw and the size to swing it",
		"factions": {Loadout.Universe.WARHAMMER: [3]},
		"overshield": 300.0,
		"preset": {
			"name": "ORK WARBOSS", "kit": Loadout.Kit.ORK,
			"primary": Weapon.Class.POWER_KLAW, "sidearm": Weapon.Class.SLUGGA,
			"armor": 3, "style": CharacterModel.Style.ORK_NOB,
			"unit_health": 2.7, "unit_speed": 0.95, "unit_stature": 1.20,
		},
	},

	# =========================================================================
	# ...and one at the top of the Star Wars ladder that ALL FOUR sides reach,
	# because the Force is allegiance and not faction hardware. It is the one
	# reward deliberately shared, and it still resolves to two different bodies.
	# =========================================================================
	{
		"name": "FORCE MASTER", "kills": KILLS_FORCE, "kind": Kind.BECOME,
		"blurb": "A master of the Force takes the field",
		"factions": {Loadout.Universe.STAR_WARS: [0, 1, 2, 3]},
		"shared": true,
		"preset_by_team": {
			0: {"name": "JEDI MASTER", "style": CharacterModel.Style.JEDI},
			3: {"name": "JEDI MASTER", "style": CharacterModel.Style.JEDI},
			1: {"name": "SITH MASTER", "style": CharacterModel.Style.IMPERIAL_ROYAL},
			2: {"name": "SITH MASTER", "style": CharacterModel.Style.IMPERIAL_ROYAL},
		},
		"preset": {
			"name": "FORCE MASTER", "kit": Loadout.Kit.FORCE,
			"primary": Weapon.Class.SABER, "sidearm": Weapon.Class.PISTOL,
			"armor": 0, "style": CharacterModel.Style.JEDI,
			"gadget": Loadout.Gadget.FORCE_LIGHTNING,
			"gadget2": Loadout.Gadget.FORCE_PUSH,
			"gadget3": Loadout.Gadget.FURY,
			"unit_health": 2.6, "unit_speed": 1.18, "unit_jump": 1.35,
		},
	},
]


## Every reward a body could earn, in threshold order. Asked once when a player
## deploys rather than on every kill — a life's class and side cannot change
## under it, and walking the table on each of thirteen rounds a second is the
## kind of question house rule 5 exists about.
##
## `team` is the side. Nothing else is asked, which is the whole point — see the
## note on `factions`.
## `universe` and `side` are the TEAM'S OWN, because a match may have UNSC on one
## side and the Republic on the other and there is no single setting to ask.
## Passed in for the same reason `faction_classes` takes one: this file may not
## name an autoload either.
static func available(side: int, universe := -1) -> Array[Dictionary]:
	var u: int = universe if universe >= 0 else Loadout.active_universe
	var out: Array[Dictionary] = []
	for row in REWARDS:
		if not _allows(row, side, u):
			continue
		out.append(row)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["kills"]) < int(b["kills"]))
	return out


static func _allows(row: Dictionary, side: int, universe: int) -> bool:
	if not row.has("factions"):
		return true      # everybody, everywhere
	var by_universe: Dictionary = row["factions"]
	# THE UNIVERSE IS LOOKED UP FIRST and an absent one is a refusal, not a
	# fallthrough — a team index means a different side in every setting, so a
	# Spartan on team 0 must never inherit the Republic's gunship.
	if not by_universe.has(universe):
		return false
	return (by_universe[universe] as Array).has(side)


## The reward crossed by going from `before` kills to `after`, or an empty
## dictionary. **At most one per kill**, and the LOWEST crossed — a player who
## somehow jumps two thresholds with one grenade collects them one kill apart
## rather than both at once, which keeps the announcements legible.
static func earned(rewards: Array[Dictionary], before: int, after: int) -> Dictionary:
	for row in rewards:
		var need := int(row["kills"])
		if before < need and after >= need:
			return row
	return {}


## The preset a BECOME reward deploys, resolved for a side. A row may state
## `preset_by_team` to override parts of its base `preset` — that is how JEDI and
## SITH are one reward and one mechanism with two names and two bodies.
static func become_preset(row: Dictionary, team: int) -> Dictionary:
	var preset: Dictionary = (row.get("preset", {}) as Dictionary).duplicate(true)
	var by_team: Dictionary = row.get("preset_by_team", {})
	if by_team.has(team):
		for key in by_team[team]:
			preset[key] = by_team[team][key]
	return preset


## What the HUD says when one lands. The NAME is what a player repeats to the
## room; the blurb is for the announcement line under it.
static func announce(row: Dictionary) -> String:
	return str(row.get("name", "REWARD"))
