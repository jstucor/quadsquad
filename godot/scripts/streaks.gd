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
const REWARDS: Array[Dictionary] = [
	# ---- every side, every setting -------------------------------------------
	{
		"name": "RECON SWEEP", "kills": 4, "kind": Kind.RECON,
		"blurb": "Your side sees every enemy for a while",
		"duration": 14.0,
	},
	{
		"name": "ORBITAL STRIKE", "kills": 8, "kind": Kind.BOMBARDMENT,
		"blurb": "A battery walks fire across the enemy's densest ground",
		"duration": 7.0,
	},
	# ---- the heavy ------------------------------------------------------------
	# In Star Wars this is the CIS's and the Rebels' — the two sides with neither
	# a walker nor a gunship — so all four factions end up with four rewards each.
	# Everywhere else it is the only BECOME on offer, so everybody gets it.
	{
		"name": "JUGGERNAUT", "kills": 6, "kind": Kind.BECOME,
		"blurb": "Heavy plate, a heavier gun, and a shield that soaks the first burst",
		"factions": {
			Loadout.Universe.STAR_WARS: [1, 3],
			Loadout.Universe.HALO: [0, 1],
			Loadout.Universe.WARHAMMER: [0, 1, 2, 3],
		},
		"overshield": 260.0,
		"preset": {
			"name": "JUGGERNAUT", "kit": Loadout.Kit.WOOKIEE,
			"primary": Weapon.Class.HMG, "sidearm": Weapon.Class.BOWCASTER,
			"armor": 3, "style": CharacterModel.Style.WOOKIEE,
			"unit_health": 2.2, "unit_speed": 0.82, "unit_stature": 1.14,
		},
	},
	# ---- the Force ------------------------------------------------------------
	# ALL FOUR STAR WARS SIDES, because which one you get is a matter of ALLEGIANCE
	# and not of class: the Republic and the Rebel Alliance draw a Jedi, the
	# Separatists and the Empire draw a Sith. One row and one mechanism — a saber,
	# a guard and lightning — with the name and the body chosen by side.
	{
		"name": "FORCE MASTER", "kills": 12, "kind": Kind.BECOME,
		"blurb": "A master of the Force takes the field",
		"factions": {Loadout.Universe.STAR_WARS: [0, 1, 2, 3]},
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
	# ---- the war machines -----------------------------------------------------
	# THE GUNSHIP IS NOT A VEHICLE YOU DRIVE. It flies itself in a circuit and you
	# ride the BALL TURRET, which is what a LAAT is actually remembered for — see
	# `gunship.gd`. The walker is delivered and you climb in, which keeps the whole
	# Vehicle story untouched.
	{
		"name": "LAAT GUNSHIP", "kills": 10, "kind": Kind.GUNSHIP,
		"blurb": "Ride the ball turret while it circles the field",
		"factions": {Loadout.Universe.STAR_WARS: [0]},
		"duration": 22.0,
	},
	{
		"name": "AT-ST WALKER", "kills": 10, "kind": Kind.VEHICLE,
		"blurb": "A walker is dropped in beside you",
		"factions": {Loadout.Universe.STAR_WARS: [2]},
		"vehicle": "atst",
	},
]


## Every reward a body could earn, in threshold order. Asked once when a player
## deploys rather than on every kill — a life's class and side cannot change
## under it, and walking the table on each of thirteen rounds a second is the
## kind of question house rule 5 exists about.
##
## `team` is the side. Nothing else is asked, which is the whole point — see the
## note on `factions`.
static func available(team: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in REWARDS:
		if not _allows(row, team):
			continue
		out.append(row)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["kills"]) < int(b["kills"]))
	return out


static func _allows(row: Dictionary, team: int) -> bool:
	if not row.has("factions"):
		return true      # everybody, everywhere
	var by_universe: Dictionary = row["factions"]
	# THE UNIVERSE IS LOOKED UP FIRST and an absent one is a refusal, not a
	# fallthrough — a team index means a different side in every setting, so a
	# Spartan on team 0 must never inherit the Republic's gunship.
	if not by_universe.has(Loadout.active_universe):
		return false
	return (by_universe[Loadout.active_universe] as Array).has(team)


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
