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
##   BECOME    something happens to YOU. Ork Warboss, Warden Master. You stop being
##             a trooper and the rest of the life is played as something else.
##
## **A REWARD IS OFFERED, NOT APPLIED.** D-UP takes it, D-DOWN turns it down (see
## `Player.accept_reward` / `decline_reward`). DECLINE is a real answer and not a
## politeness, because some of these COST you something: a BECOME replaces the
## build you chose and are in the middle of using, and the gunship takes you off
## the ground for twenty seconds while your side is holding a post. Forcing that
## on somebody at the moment they are doing best is the opposite of a reward.
## **The offer is spent when it is MADE, not when it is taken**, or every further
## kill re-offers the thing you just refused.
##
## A REWARD IS A TABLE ROW, and a BECOME reward's row is an ORDINARY PRESET in
## the same format as every AI build and authored class in the game (see
## `Loadout.preset_build`). A new reward is a row here plus, at most, one case in
## `Player._grant_streak`.

enum Kind { RECON, BOMBARDMENT, VEHICLE, BECOME, GUNSHIP }

## A REWARD BELONGS TO A FACTION, AND TO NOTHING ELSE.
##
## It was gated on KIT as well, which meant the reward you could earn depended on
## what you had bought that life — so a Concord player in a legionary kit and one in
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
## belong to different sides in different settings, and the pair cannot express
## that without two rows that would then drift apart. It is also what makes an
## absent universe a REFUSAL rather than a fallthrough: team 0 is the Concord in
## The Compact Wars and the COALITION in Deep Range, and neither may inherit the other's prize.
## THE LADDER IS THE SAME SHAPE FOR EVERY FACTION: two rewards anybody can earn,
## then that side's OWN signature, and for The Compact Wars a fourth at the top.
const KILLS_RECON := 4
const KILLS_ORBITAL := 7
const KILLS_SIGNATURE := 10
const KILLS_FORCE := 14

## The signature presets are all the same shape, so the shared parts are stated
## once here and merged in by `_signature`. What each faction actually states is
## the three things that make it itself: a NAME, a BODY and a WEAPON.
const SIGNATURE_BLURB := "Your side's finest takes the field"

## WHAT A SIGNATURE PRESET MUST STATE, and why leaving a field out is not neutral.
##
## `Loadout._build_from` builds a FRESH Loadout and writes only the keys the row
## names — everything else is the class default. So a row that states a body and
## two guns and stops does not inherit the build the player spent two hundred
## tokens and ten kills assembling: it REPLACES it with iron sights, no cooling,
## no grip and three empty gadget slots. The first pass did exactly that, which
## made the best reward in the game a downgrade in everything except health, and
## is most of why they did not feel like rewards. Every row below therefore names:
##
##   unit_health / overshield  the pool, and it is the only pool this life gets
##                             (`Player._no_regen`) — a signature does not heal.
##   gadget / gadget2 / gadget3  all three, always. Slot 3 is an OVERSHIELD-class
##                             ability on purpose: with regeneration gone it is
##                             the one thing that gives ground back.
##   sight / cooling / grip / foregrip   on a RANGED primary. A melee signature
##                             hides those rows, so it states `secondary_mod`
##                             instead and walks in with two sidearms.
##
## A gadget here is NOT checked against the kit's allow-list, exactly as an
## authored faction class's is not — `_build_from` writes the field. That is
## deliberate: a Aegis Drone Prime carries the Ursan's front shield because a
## aegis drone IS a shield, and the allow-lists are a SHOP rule, not a physics one.
##
## ---------------------------------------------------------------------------
## A SIGNATURE IS SUPPOSED TO BE TOO STRONG. That is the design, not a tuning
## slip, and the numbers below were raised deliberately to make it true.
##
## The argument is what a ten-kill streak COSTS. It is ten kills without dying
## once, in a mode where everybody respawns and nobody else has to string
## anything together — most players will earn one a handful of times and many
## will never see one. A reward that rare has to change the shape of the fight
## when it lands, or the correct play on earning it is to carry on exactly as
## before, which is the same as not having earned it. The previous pass stood a
## signature up at roughly 7-11x a trooper's effective health, which is a very
## good trooper; these stand at closer to 12-16x, which is a problem the other
## side has to organise against. Being able to say "somebody is a Warboss, deal
## with it" out loud is the whole point of the rung.
##
## WHAT KEEPS IT FROM BEING A ROUND-ENDER IS UNCHANGED, and it is three things,
## none of which is a smaller pool:
##
##   NO REGENERATION (`Player._no_regen`). Every point spent is a point gone.
##       You can win five fights on one shield and not fifty, and this is the
##       only counterweight that SCALES with how big the pool gets — which is
##       exactly why the pool is the right dial to turn up.
##   THE SLOT 3 EXCEPTION. An OVERSHIELD or an IRON HALO re-issues the second
##       pool, so there is one deliberate way to give ground back, and it is a
##       cooldown the enemy can play around.
##   IT DIES WITH YOU. A signature is per LIFE. Focus it down once and it is
##       gone for good, along with the streak that earned it.
##
## And it is ANNOUNCED (`Player._signature_entry`): the transformation is loud,
## bright and visible to everyone nearby, so nobody is surprised by it. A body
## this strong arriving quietly would be the unfair version.


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
	# rung that keeps the ladder the same height for a Runt and a Sentinel.
	{
		"name": "ORBITAL STRIKE", "kills": KILLS_ORBITAL, "kind": Kind.BOMBARDMENT,
		"blurb": "Take fire control aboard the ship and call the rounds down yourself",
		# EIGHTEEN AND NOT SEVEN. Seven seconds was the right length for a barrage
		# that aimed itself and needed no player in it; this one has to be flown
		# to, read, and aimed, and a window you spend arriving in is not a reward.
		"duration": 18.0,
	},

	# =========================================================================
	# ONE SIGNATURE PER FACTION, AND NO TWO SIDES SHARE ONE.
	#
	# This is the rule `tests/streaks.gd` enforces, and it is here because the
	# first version had SIX factions sharing a generic "Juggernaut" — which is
	# the same failure as the first roster pass (LEGION PILOT and PACT HEAVY
	# carrying recycled rifles): a reward generated from an adjective rather than
	# designed from the fanbase's own vocabulary. A Unsleeping Lord and an Ork
	# Warboss are not two skins on one Juggernaut, and if they were, there would
	# be no reason to care which side you were on.
	#
	# Every one is a BECOME except the Concord's and the Dominion's, which were
	# asked for as machines. The body and the gun are the whole of each row: the
	# mechanism underneath is identical and stated once.
	# =========================================================================

	# ---- THE COMPACT WARS -----------------------------------------------------------
	{
		"name": "HAMMERHEAD GUNSHIP", "kills": KILLS_SIGNATURE, "kind": Kind.GUNSHIP,
		"blurb": "Ride the ball turret while it circles the field",
		"factions": {Loadout.Universe.COMPACT: [0]},
		"duration": 22.0,
	},
	{
		"name": "AEGIS PRIME", "kills": KILLS_SIGNATURE, "kind": Kind.BECOME,
		"blurb": "Paired repeaters behind a shield, and no way to run",
		"factions": {Loadout.Universe.COMPACT: [1]},
		"overshield": 759.0,
		"preset": {
			"name": "AEGIS PRIME", "kit": Loadout.Kit.LEGION,
			"primary": Weapon.Class.AEGIS_TWIN, "sidearm": Weapon.Class.PISTOL,
			"armor": 3, "style": CharacterModel.Style.AEGIS_DRONE,
			"unit_health": 3.07, "unit_speed": 0.72, "unit_stature": 0.95,
			# COOLING matters more here than on anything else in the game: the twin
			# is the highest sustained output in the catalogue behind the SHORTEST
			# heat pool, so the mod that lengthens the burst is the whole unit.
			"sight": Loadout.Sight.RED_DOT, "cooling": true,
			"grip": true, "foregrip": true,
			"gadget": Loadout.Gadget.SHIELD,
			"gadget2": Loadout.Gadget.SCAN_DART,
			"gadget3": Loadout.Gadget.OVERSHIELD,
		},
	},
	{
		"name": "MARAUDER WALKER", "kills": KILLS_SIGNATURE, "kind": Kind.VEHICLE,
		"blurb": "A walker is dropped in beside you",
		"factions": {Loadout.Universe.COMPACT: [2]},
		"vehicle": "atst",
	},
	{
		"name": "URSAN CHIEFTAIN", "kills": KILLS_SIGNATURE, "kind": Kind.BECOME,
		"blurb": "Two metres of fur, plate and quarrel caster",
		"factions": {Loadout.Universe.COMPACT: [3]},
		"overshield": 594.0,
		"preset": {
			"name": "URSAN CHIEFTAIN", "kit": Loadout.Kit.URSAN,
			"primary": Weapon.Class.HMG, "sidearm": Weapon.Class.QUARREL_CASTER,
			"armor": 3, "style": CharacterModel.Style.URSAN,
			"unit_health": 3.42, "unit_speed": 0.88, "unit_stature": 1.14,
			# NO SCOPE ON THE QUARREL CASTER, deliberately, and for the reason the
			# URSAN kit already forbids it: zero spread collapses all three
			# quarrels onto one point and the pellet gun stops being one.
			"sight": Loadout.Sight.RED_DOT, "cooling": true,
			"grip": true, "foregrip": true,
			"gadget": Loadout.Gadget.SHIELD,
			"gadget2": Loadout.Gadget.GRENADE_FRAG,
			"gadget3": Loadout.Gadget.FURY,
		},
	},

	# ---- HALO ----------------------------------------------------------------
	{
		"name": "PALADIN HEADHUNTER", "kills": KILLS_SIGNATURE, "kind": Kind.BECOME,
		"blurb": "Mjolnir plate and a shield that comes back",
		"factions": {Loadout.Universe.DEEP_RANGE: [0]},
		"overshield": 726.0,
		"preset": {
			"name": "PALADIN HEADHUNTER", "kit": Loadout.Kit.PALADIN,
			"primary": Weapon.Class.HM40, "sidearm": Weapon.Class.S6,
			"armor": 3, "style": CharacterModel.Style.PALADIN,
			"unit_health": 3.19, "unit_speed": 1.05, "unit_stature": 1.10,
			"sight": Loadout.Sight.RED_DOT, "cooling": true,
			"grip": true, "foregrip": true,
			"gadget": Loadout.Gadget.SENTRY_TURRET,
			"gadget2": Loadout.Gadget.FRAG_GRENADE_UNSC,
			"gadget3": Loadout.Gadget.OVERSHIELD,
		},
	},
	{
		"name": "ZHAAL BLADEMASTER", "kills": KILLS_SIGNATURE, "kind": Kind.BECOME,
		"blurb": "An energy sword and the speed to reach you with it",
		"factions": {Loadout.Universe.DEEP_RANGE: [1]},
		"overshield": 660.0,
		"preset": {
			"name": "ZHAAL BLADEMASTER", "kit": Loadout.Kit.ZHAAL,
			"primary": Weapon.Class.ENERGY_SWORD,
			"sidearm": Weapon.Class.PLASMA_PISTOL,
			"armor": 2, "style": CharacterModel.Style.ZHAAL_ULTRA,
			"unit_health": 2.95, "unit_speed": 1.22, "unit_stature": 1.14,
			# A MELEE SIGNATURE HIDES THE SIGHT/COOLING/GRIP ROWS, so its weapon
			# buff goes on the SIDEARM instead: DUAL is two plasma pistols the
			# moment it swaps off the blade, which is also the answer to the one
			# thing a sword-only body cannot do — reach anybody.
			"secondary_mod": Loadout.SecondaryMod.DUAL,
			"gadget": Loadout.Gadget.PLASMA_CANNON,
			"gadget2": Loadout.Gadget.PLASMA_GRENADE,
			"gadget3": Loadout.Gadget.ACTIVE_CAMO,
		},
	},

	# ---- IRONHYMN ----------------------------------------------------
	{
		"name": "IRONCLAD", "kills": KILLS_SIGNATURE, "kind": Kind.BECOME,
		"blurb": "Tactical Dreadnought armour and a heavy shellgun",
		"factions": {Loadout.Universe.IRONHYMN: [0]},
		"overshield": 825.0,
		"preset": {
			"name": "IRONCLAD", "kit": Loadout.Kit.SENTINEL,
			"primary": Weapon.Class.HEAVY_BOLTER,
			"sidearm": Weapon.Class.BOLT_PISTOL,
			"armor": 3, "style": CharacterModel.Style.SENTINEL,
			"unit_health": 4.01, "unit_speed": 0.70, "unit_stature": 1.16,
			"sight": Loadout.Sight.RED_DOT, "cooling": true,
			"grip": true, "foregrip": true,
			"gadget": Loadout.Gadget.ASSAULT_CANNON,
			"gadget2": Loadout.Gadget.BREACH_CHARGE,
			"gadget3": Loadout.Gadget.IRON_HALO,
		},
	},
	{
		"name": "CRIMSON EXEMPLAR", "kills": KILLS_SIGNATURE, "kind": Kind.BECOME,
		"blurb": "Gold plate, a power sword and wings to arrive on",
		"factions": {Loadout.Universe.IRONHYMN: [1]},
		"overshield": 660.0,
		"preset": {
			"name": "CRIMSON EXEMPLAR", "kit": Loadout.Kit.CHORISTER,
			"primary": Weapon.Class.POWER_SWORD,
			"sidearm": Weapon.Class.ORDER_PLASMA_PISTOL,
			"armor": 2, "style": CharacterModel.Style.CHORISTER,
			"unit_health": 3.19, "unit_speed": 1.18, "unit_jump": 1.45,
			"unit_stature": 1.12,
			"secondary_mod": Loadout.SecondaryMod.DUAL,
			# The wings are the whole read on this one, so they are the gadget on
			# the button rather than a line in the blurb.
			"gadget": Loadout.Gadget.JUMP_PACK,
			"gadget2": Loadout.Gadget.FUSION_CHARGE,
			"gadget3": Loadout.Gadget.CRIMSON_RAGE,
		},
	},
	{
		"name": "UNSLEEPING OVERLORD", "kills": KILLS_SIGNATURE, "kind": Kind.BECOME,
		"blurb": "A warscythe, and it gets back up",
		"factions": {Loadout.Universe.IRONHYMN: [2]},
		"overshield": 693.0,
		"preset": {
			"name": "UNSLEEPING OVERLORD", "kit": Loadout.Kit.UNSLEEPING,
			"primary": Weapon.Class.WARSCYTHE,
			"sidearm": Weapon.Class.GAUSS_PISTOL,
			"armor": 3, "style": CharacterModel.Style.UNSLEEPING_LORD,
			"unit_health": 3.66, "unit_speed": 0.92, "unit_stature": 1.15,
			"secondary_mod": Loadout.SecondaryMod.DUAL,
			"gadget": Loadout.Gadget.TESLA_ARC,
			"gadget2": Loadout.Gadget.TRANSLOCATION,
			"gadget3": Loadout.Gadget.PHASE_SHIFT,
		},
	},
	{
		"name": "SCRAP WARLORD", "kills": KILLS_SIGNATURE, "kind": Kind.BECOME,
		"blurb": "A power klaw and the size to swing it",
		"factions": {Loadout.Universe.IRONHYMN: [3]},
		"overshield": 759.0,
		"preset": {
			"name": "SCRAP WARLORD", "kit": Loadout.Kit.SCRAPKIN,
			"primary": Weapon.Class.CRUSHER_CLAW, "sidearm": Weapon.Class.SLUG_PISTOL,
			"armor": 3, "style": CharacterModel.Style.SCRAPKIN_BOSS,
			"unit_health": 4.13, "unit_speed": 0.95, "unit_stature": 1.20,
			"secondary_mod": Loadout.SecondaryMod.DUAL,
			"gadget": Loadout.Gadget.SCRAP_JETS,
			"gadget2": Loadout.Gadget.SCRAP_BOMB,
			"gadget3": Loadout.Gadget.WARCRY,
		},
	},

	# =========================================================================
	# ...and one at the top of the The Compact Wars ladder that ALL FOUR sides reach,
	# because Kinesis is allegiance and not faction hardware. It is the one
	# reward deliberately shared, and it still resolves to two different bodies.
	# =========================================================================
	{
		"name": "KINESIS MASTER", "kills": KILLS_FORCE, "kind": Kind.BECOME,
		"blurb": "A master of Kinesis takes the field",
		"factions": {Loadout.Universe.COMPACT: [0, 1, 2, 3]},
		"shared": true,
		# WATCHED, NOT LOOKED THROUGH. Everything a Force Master does happens to
		# the BODY — a two-metre blade on an arc, a guard across the chest, a
		# shove, a leap — and a camera 30 cm from the hilt is aimed at the one
		# part of that which cannot be seen. It is safe HERE specifically because
		# this body's weapons are an arc, a cone and a sidearm rather than a
		# precision ray; see `Player.third_person` for why that is the deciding
		# question and not a matter of taste.
		"third_person": true,
		# THE TOP RUNG MUST NOT BE THE SQUISHIEST THING ON THE LADDER, and it was:
		# on a LIGHT FRAME with no second pool it stood up at 208 effective health
		# against the ten-kill Terminator's 795, so the four-kill climb from the
		# signature to the master was a downgrade in everything but flair. It keeps
		# the light frame — a Kinesis adept is fast because it has to close — and
		# takes the pool as a SHIELD instead, which is the one that gets spent.
		"overshield": 858.0,
		"preset_by_team": {
			0: {"name": "GRAND WARDEN", "style": CharacterModel.Style.WARDEN},
			3: {"name": "GRAND WARDEN", "style": CharacterModel.Style.WARDEN},
			1: {"name": "DREAD REAVER", "style": CharacterModel.Style.DOMINION_GUARD},
			2: {"name": "DREAD REAVER", "style": CharacterModel.Style.DOMINION_GUARD},
		},
		"preset": {
			"name": "KINESIS MASTER", "kit": Loadout.Kit.ADEPT,
			"primary": Weapon.Class.SABER, "sidearm": Weapon.Class.PISTOL,
			"armor": 0, "style": CharacterModel.Style.WARDEN,
			"gadget": Loadout.Gadget.ARC_STORM,
			"gadget2": Loadout.Gadget.KINETIC_PUSH,
			"gadget3": Loadout.Gadget.FURY,
			"unit_health": 4.01, "unit_speed": 1.18, "unit_jump": 1.35,
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
## `universe` and `side` are the TEAM'S OWN, because a match may have COALITION on one
## side and the Concord on the other and there is no single setting to ask.
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
	# Paladin on team 0 must never inherit the Concord's gunship.
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
## `preset_by_team` to override parts of its base `preset` — that is how WARDEN and
## REAVER are one reward and one mechanism with two names and two bodies.
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


## The line under the name on the OFFER prompt.
##
## A BECOME states the cost as well as the prize, because DECLINE is only a real
## answer if you are told what you are agreeing to — and the cost here is the one
## thing no amount of looking at the body would tell you. It is appended in ONE
## place rather than written into nine blurbs, so the rule and the sentence
## describing it cannot drift apart: `Player._no_regen` is set for every BECOME
## and for nothing else, and so is this.
const NO_REGEN_NOTE := "No health regeneration"


static func offer_blurb(row: Dictionary) -> String:
	var text := str(row.get("blurb", ""))
	if int(row.get("kind", -1)) != Kind.BECOME:
		return text
	if text == "":
		return NO_REGEN_NOTE
	return "%s — %s" % [text, NO_REGEN_NOTE]
