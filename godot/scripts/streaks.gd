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

enum Kind { RECON, BOMBARDMENT, VEHICLE, BECOME }

## Class and faction gating uses the SAME KEYS the catalogue already uses, so it
## reads the same way as everything else:
##
##   `kits`   — only these `Loadout.Kit`s may earn it. Absent means anybody.
##   `teams`  — only these team indices. Absent means any side.
##   `universe` — only this `Loadout.Universe`. Absent means any setting.
##
## **A gated reward is not a bonus for that class, it is that class's OWN reward**
## — the Force adept has no orbital uplink and a Wookiee does not fly a gunship.
## Everybody can reach RECON and ORBITAL; the rest are somebody's in particular.
const REWARDS: Array[Dictionary] = [
	# ---- everybody -----------------------------------------------------------
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
	# ---- the heavy bruisers --------------------------------------------------
	# JUGGERNAUT is a BECOME and it is deliberately the CHEAPEST of them, because
	# what it turns you into is still a trooper: bigger, tougher, slower, holding
	# something belt-fed. The Force master at 12 is a different thing entirely.
	{
		"name": "JUGGERNAUT", "kills": 6, "kind": Kind.BECOME,
		"blurb": "Heavy plate, a heavier gun, and a shield that soaks the first burst",
		"kits": [Loadout.Kit.WOOKIEE, Loadout.Kit.JIRALHANAE, Loadout.Kit.ORK,
			Loadout.Kit.UNGGOY],
		"overshield": 260.0,
		"preset": {
			"name": "JUGGERNAUT", "kit": Loadout.Kit.WOOKIEE,
			"primary": Weapon.Class.HMG, "sidearm": Weapon.Class.BOWCASTER,
			"armor": 3, "style": CharacterModel.Style.WOOKIEE,
			"unit_health": 2.2, "unit_speed": 0.82, "unit_stature": 1.14,
		},
	},
	# ---- the Force -----------------------------------------------------------
	# JEDI MASTER and SITH MASTER are ONE reward whose preset is chosen by SIDE
	# (`preset_by_team`), not two rows. They are the same mechanism — a saber, a
	# guard and lightning — and stating them twice is how the two would drift.
	{
		"name": "FORCE MASTER", "kills": 12, "kind": Kind.BECOME,
		"blurb": "A master of the Force takes the field",
		"kits": [Loadout.Kit.FORCE],
		"universe": Loadout.Universe.STAR_WARS,
		"preset_by_team": {
			# Republic and Rebel draw a Jedi; CIS and Empire draw a Sith. Same
			# build, different name and blade — which is exactly the difference.
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
	# ---- the war machines ----------------------------------------------------
	# DELIVERED, NOT BECOME. It is parked beside you and you climb in, which keeps
	# the whole vehicle story — mounting, the team gate, the driver bleed, dying
	# at the controls — exactly as it already is (see Vehicle). A vehicle that
	# materialised around you would need every one of those answered again.
	#
	# ONLY TWO SIDES HAVE ONE. The Republic's LAAT and the Empire's AT-ST are the
	# two that were asked for; the CIS and the Rebel Alliance fall through to the
	# universal rewards and adding theirs is one row here plus one in
	# `Vehicle.STREAK_VEHICLES`. That is a real gap, not a design.
	{
		"name": "LAAT GUNSHIP", "kills": 10, "kind": Kind.VEHICLE,
		"blurb": "A gunship sets down beside you",
		"universe": Loadout.Universe.STAR_WARS,
		"teams": [0],
		"vehicle": "laat",
	},
	{
		"name": "AT-ST WALKER", "kills": 10, "kind": Kind.VEHICLE,
		"blurb": "A walker is dropped in beside you",
		"universe": Loadout.Universe.STAR_WARS,
		"teams": [2],
		"vehicle": "atst",
	},
]


## Every reward a body could earn, in threshold order. Asked once when a player
## deploys rather than on every kill — a life's class and side cannot change
## under it, and walking the table on each of thirteen rounds a second is the
## kind of question house rule 5 exists about.
##
## `kit` is the Loadout.Kit being played, `team` the side.
static func available(kit: int, team: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in REWARDS:
		if not _allows(row, kit, team):
			continue
		out.append(row)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["kills"]) < int(b["kills"]))
	return out


static func _allows(row: Dictionary, kit: int, team: int) -> bool:
	# THE UNIVERSE IS CHECKED FIRST, exactly as `Loadout._allows_entry` does it:
	# a Star Wars gunship must not be reachable by a Spartan who happens to be on
	# team 0, and team indices mean different sides in different settings.
	if row.has("universe") and int(row["universe"]) != Loadout.active_universe:
		return false
	if row.has("kits") and not (row["kits"] as Array).has(kit):
		return false
	if row.has("teams") and not (row["teams"] as Array).has(team):
		return false
	return true


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
