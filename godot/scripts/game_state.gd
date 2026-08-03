extends Node
## Autoload: match state — teams, team-deathmatch score, spawn points, and the
## map rotation. Levels register spawn markers per team; actors credit frags
## here on a kill, so the mode rules live in one place. Also bootstraps the
## control bindings (Controls, registered in code — no project.godot
## serialization) before anything can ask what a button does.

signal score_changed(team: int, score: int)
signal match_won(team: int)
## The match proper hasn't begun until everyone has picked a loadout and the
## start countdown has run. `match_countdown` ticks whole seconds (0 = FIGHT),
## and nobody can move or shoot until `match_live` is true.
signal match_countdown(seconds: int)
signal match_began()
signal zone_moved(point: Vector3)     # the capture area relocated
signal zone_state(holder: int, contested: bool, seconds_left: int)
## A body went down and something killed it. Carries the whole entry rather than
## the two bodies, because by the time a HUD draws it the loser is usually freed
## — a killfeed that holds node references is a killfeed full of nulls.
signal kill_logged(entry: Dictionary)

enum Team { REPUBLIC, CIS }
## DEATHMATCH scores on kills; ZONES scores a point per second for whichever
## team has the most bodies inside the roaming capture area.
## ROYALE is the odd one out: it is not scored at all. Nobody respawns, you
## start with a sidearm and scavenge the rest off the ground, a shrinking storm
## herds everyone together, and the last side still standing wins.
## CONQUEST is the Battlefront mode: two sides fight over CAPTURE POSTS spread
## across the map. Holding more posts than the enemy bleeds their shared
## REINFORCEMENT tickets, and each death spends one; the side that runs its
## tickets to zero loses. You deploy AT a post your side holds, chosen on the
## spawn screen — so losing your posts is losing your footholds on the map.
##
## MASSIVE is the scale mode: two sides of fifty, almost all of them LINE
## TROOPERS — AI with no gadgets, one weapon and a scope, a weaker eye and a much
## cheaper think loop (see Bot.line). It plays by deathmatch rules because at
## that body count the rules are not the point: what a player is there for is
## being one rifle in a hundred, and any objective would just be a place the
## crowd stands. It is PROCEDURAL-MAP ONLY — the hand-laid arenas are built for
## eight bodies and a hundred of them in Catwalk's corridors is a traffic jam,
## where a generated world is 220 m of open ground with cover scattered over it.
enum Mode { DEATHMATCH, ZONES, ROYALE, CONQUEST, MASSIVE }
const MODE_NAMES := {
	Mode.DEATHMATCH: "DEATHMATCH", Mode.ZONES: "ZONES", Mode.ROYALE: "BATTLE ROYALE",
	Mode.CONQUEST: "CONQUEST", Mode.MASSIVE: "MASSIVE BATTLE",
}
const MODE_BLURBS := {
	Mode.DEATHMATCH: "First to %d kills",
	Mode.ZONES: "Hold the area. A point a second, new area every %ds, first to %d",
	Mode.ROYALE: "No respawns. Scavenge your gear, outlast the storm, last side wins",
	Mode.CONQUEST: "Capture command posts to spawn on. Hold more to bleed the enemy's %d reinforcements to zero",
	Mode.MASSIVE: "%d a side on generated ground. Line troopers carry a rifle and nothing else — first to %d kills",
}
## How many bodies a side fields in MASSIVE, and the sizes the menu offers. Fifty
## is the headline and the reason the mode exists; the smaller ones are here
## because the frame cost is real and measured (see the perf notes in CLAUDE.md)
## and a couch that cannot hold fifty should be able to play thirty.
const MASSIVE_SIZES := [15, 25, 35, 50]
const MASSIVE_DEFAULT := 50

# DEFAULT victory threshold per mode: kills, seconds of control, being the last
# side left (one "point", awarded once), or the reinforcement pool each side
# starts Conquest with. The menu lets you raise or lower all but royale's —
# score_targets holds the chosen values, seeded from here.
const SCORE_LIMITS := {Mode.DEATHMATCH: 25, Mode.ZONES: 60, Mode.ROYALE: 1,
	Mode.CONQUEST: 150, Mode.MASSIVE: 200}
## The victory thresholds actually in force, chosen on the menu. Seeded from the
## defaults; ROYALE's is fixed (last side standing is not a number you tune).
## The offered choices live on the menu (SCORE_CHOICES there), not here.
var score_targets := SCORE_LIMITS.duplicate()

# A respawn must never land on a living body: two overlapping capsules push each
# other apart every physics frame and ride that ejection out of the map, which
# drags the innocent player along with the one who died.
const SPAWN_CLEARANCE := 2.5  # a marker this close (m) to a live player is taken
## Metres above the computed ground to place anything, so it falls the last step
## rather than starting buried. See place_corner_spawns.
const SPAWN_LIFT := 1.2
const MIN_BODY_GAP := 1.0     # capsules are 0.7 wide, so this always separates them

# The map roster: the menu lists it, Main loads MAPS[map_index].scene, and the
# rotation walks it in order. Adding a map means adding one row here.
const MAPS: Array[Dictionary] = [
	{"name": "CROSSFIRE", "blurb": "Symmetric arena, bunker centre",
		"scene": preload("res://scenes/levels/crossfire.tscn")},
	{"name": "FOUNDRY", "blurb": "Tight lanes across a divider wall",
		"scene": preload("res://scenes/levels/foundry.tscn")},
	{"name": "OVERGROWTH", "blurb": "Wide outdoor jungle, temple ruins",
		"scene": preload("res://scenes/levels/overgrowth.tscn")},
	{"name": "HIGHRIDGE", "blurb": "Jungle mountain, tunnel and a flag on the peak",
		"scene": preload("res://scenes/levels/highridge.tscn")},
	{"name": "HANGAR", "blurb": "Imperial deck, close quarters",
		"scene": preload("res://scenes/levels/hangar.tscn")},
	{"name": "SPILLWAY", "blurb": "Long narrow channel, staggered blocks",
		"scene": preload("res://scenes/levels/spillway.tscn")},
	{"name": "CITADEL", "blurb": "Central keep and corner towers, fought in a rotation",
		"scene": preload("res://scenes/levels/citadel.tscn")},
	{"name": "RELAY", "blurb": "Wide open plain, low cover, long sight lines",
		"scene": preload("res://scenes/levels/relay.tscn")},
	{"name": "CATWALK", "blurb": "Cramped corridors, every fight is a corner",
		"scene": preload("res://scenes/levels/catwalk.tscn")},
	{"name": "GEONOSIS", "blurb": "Vast red basin: five mesas around an arena. 300m across",
		"scene": preload("res://scenes/levels/geonosis.tscn")},
	{"name": "KASHYYYK", "blurb": "Wroshyr forest: groves, clearings and a village. 220m",
		"scene": preload("res://scenes/levels/kashyyyk.tscn")},
	{"name": "SENATE DISTRICT", "blurb": "City grid at night: long avenues, a central plaza. 240m",
		"scene": preload("res://scenes/levels/senate.tscn")},
	{"name": "BONEYARD", "blurb": "Ship graveyard: vast hulls and the chokes between them. 260m",
		"scene": preload("res://scenes/levels/boneyard.tscn")},
	# The generated one. Its blurb is the PLANET's, filled in by map_blurb(),
	# because "what map is this" is answered by the planet and the roll — not by
	# a fixed line that would be wrong four times out of five.
	{"name": "PROCEDURAL WORLD", "blurb": "", "procedural": true,
		"scene": preload("res://scenes/levels/planet.tscn")},
]
## A team is just an index now, 0 .. active_teams()-1. Two is the classic
## two-faction match; three or four makes it a free-for-all between squads;
## FREE FOR ALL gives every player a team of one. Team.REPUBLIC and Team.CIS are
## still 0 and 1, so maps that name them keep working.
##
## Arrays, not dictionaries keyed by the enum: every `team_colors[team]` lookup
## in the game indexes by int and carries on working unchanged.
##
## WHO those sides ARE comes from the UNIVERSE (see Loadout.UNIVERSES) — UNSC and
## Covenant, or four Warhammer factions — so these are vars refreshed by
## apply_universe() rather than constants. Everything that reads them indexes an
## array of four either way.
const MAX_TEAMS := 4
var team_names: Array[String] = ["REPUBLIC", "SEPARATIST", "MANDALORE", "HUTT CARTEL"]
var team_colors: Array[Color] = [
	Color(0.35, 0.55, 1.0),   # blue
	Color(1.0, 0.40, 0.32),   # red
	Color(0.45, 0.85, 0.45),  # green
	Color(0.95, 0.78, 0.30),  # gold
]

## WHAT A SIDE'S GUNFIRE LOOKS LIKE, which is not the same question as what its
## scoreboard chip looks like — hence a second array rather than reusing
## team_colors. The Empire's chip is grey plate and its bolts are green; a grey
## tracer would be no tracer at all.
##
## It is a fall-through, not an override: a weapon that states its own `flash`
## colour keeps it (see Weapon.bolt_color), so plasma stays plasma and gauss
## stays green in anybody's hands. What this decides is the colour of the
## ORDINARY blaster rows, which every side shares — and for those the issuing
## army is exactly what picks the colour.
var bolt_colors: Array[Color] = [
	Color(0.35, 0.65, 1.0),
	Color(1.0, 0.24, 0.14),
	Color(0.38, 1.0, 0.40),
	Color(1.0, 0.52, 0.14),
]


## The bolt colour for a side, safe against a team index that is out of range
## (nothing should ask, but a stray team would otherwise take the whole shot
## down with it — an out-of-bounds index aborts the enclosing function).
func bolt_color(team: int) -> Color:
	if team < 0 or team >= bolt_colors.size():
		return bolt_colors[0]
	return bolt_colors[team]

## --- UNIVERSE ----------------------------------------------------------------
##
## Which SETTING the match is played in: which classes exist, which sides they
## fight for, and which of the catalogue they can reach. The tables themselves
## live in Loadout (a class_name, so it works with no autoloads — see the note
## there); this holds the choice and pushes it where it is needed.
## Both this and the TTK setting below are MIRRORED into Loadout, which may not
## name an autoload (its rules are exercised by a --script test that has none).
## Setters rather than a call at match start, so the buy screen's HP figures are
## right the moment the menu changes and can never disagree with what deploys.
## An initialiser does not run a setter, so _init seeds both as well.
var universe := Loadout.Universe.STAR_WARS:
	set(value):
		universe = clampi(value, 0, Loadout.UNIVERSES.size() - 1)
		Loadout.active_universe = universe
		var u: Dictionary = Loadout.UNIVERSES[universe]
		# assign(), not `=`: the table's rows are untyped arrays and these are
		# typed, so every `team_colors[t]` call site keeps its Color.
		team_names.assign(u["teams"])
		team_colors.assign(u["colors"])
		bolt_colors.assign(u["bolts"])

## --- TIME TO KILL -------------------------------------------------------------
##
## How fast somebody dies, chosen on the menu. It is a MULTIPLIER ON HEALTH and
## nothing else: every weapon in the game keeps its damage, and halving the
## health under it halves the time to kill for all of them at once. Doing it the
## other way — scaling damage — would need every gun, every splash, every melee
## swing and the guard's block pool touched, and any one of them missed would
## quietly become the best weapon in the game.
##
## REALISTIC is a body that goes down to a burst; HIGH is the arena-shooter
## sponge. MEDIUM is exactly the game as it was, which is why it is the default.
enum Ttk { REALISTIC, LOW, MEDIUM, HIGH }
const TTK_NAMES := {
	Ttk.REALISTIC: "REALISTIC", Ttk.LOW: "LOW", Ttk.MEDIUM: "MEDIUM", Ttk.HIGH: "HIGH",
}
const TTK_HEALTH := {
	Ttk.REALISTIC: 0.35, Ttk.LOW: 0.65, Ttk.MEDIUM: 1.0, Ttk.HIGH: 1.6,
}
const TTK_BLURBS := {
	Ttk.REALISTIC: "A burst kills. Cover is everything",
	Ttk.LOW: "Short fights, first shot matters",
	Ttk.MEDIUM: "The standard fight",
	Ttk.HIGH: "Long duels, room to react and reposition",
}
## --- PROCEDURAL WORLDS ---------------------------------------------------------
##
## The generated map (MAPS' `procedural` row) reads these. `planet` is the menu
## choice, RANDOM_PLANET rolls one per match, and `planet_seed` is what makes the
## same planet a different layout every time you drop into it.
##
## The seed is re-rolled in reset_match, so it is stable for the whole of one
## match — the terrain, the structures and every prop are generated from it, and
## anything that re-derived a position mid-match would tear the map apart.
const RANDOM_PLANET := -1
var planet := RANDOM_PLANET
var planet_seed := 0

## TIME OF DAY, which is a property of the WORLD and not of the map roster — so
## it lives here beside the planet and applies to the generated world only. The
## hand-laid arenas each author their own lighting as part of being that map; a
## generated world is a table row, and night is another row.
##
## It is not a darkness filter over the day palette. Turning the sun down takes
## the whole picture to mud and puts the cover boxes into unreadable black, which
## this project has already recorded as a *gameplay* bug once (see the sky
## ambient note in THE GRADE). Night is a second palette per planet — see
## `PlanetMap.PLANETS`' `"night"` block — lit cold and low so that the things
## which are genuinely bright, the muzzle flashes and the blasts, are the
## brightest things on the map instead of competing with a sun.
enum TimeOfDay {DAY, NIGHT}
const TIME_NAMES := {TimeOfDay.DAY: "DAY", TimeOfDay.NIGHT: "NIGHT"}
const TIME_BLURBS := {
	TimeOfDay.DAY: "The world under its own sun",
	TimeOfDay.NIGHT: "Fought by muzzle flash — the guns light the ground",
}
var time_of_day := TimeOfDay.DAY


## Is the match being fought in the dark? Asked by anything that behaves
## differently at night — the flash reach, the impact sparks — so none of them
## has to know that only the generated world has a night in the first place.
func is_night() -> bool:
	return time_of_day == TimeOfDay.NIGHT and map_is_procedural()


## Which world the generator should actually build this match: the menu choice,
## or a roll if it is set to RANDOM.
func chosen_planet() -> int:
	var count: int = PlanetMap.PLANET_NAMES.size()
	if planet >= 0 and planet < count:
		return planet
	return abs(planet_seed) % count


## True if the selected map generates itself. The menu shows the PLANET row only
## for this one, and the map blurb comes from the planet rather than the row.
func map_is_procedural() -> bool:
	return MAPS[map_index].get("procedural", false)


func map_blurb() -> String:
	if not map_is_procedural():
		return str(MAPS[map_index]["blurb"])
	var night := is_night()
	if planet == RANDOM_PLANET:
		if night:
			return "A world rolled at the drop, fought in the dark"
		return "A world rolled at the drop. Every match is a new one"
	var line := str(PlanetMap.PLANETS[chosen_planet()]["blurb"])
	if night:
		line += ", after dark"
	return line


var ttk := Ttk.MEDIUM:
	set(value):
		ttk = clampi(value, 0, TTK_NAMES.size() - 1)
		Loadout.ttk_health = float(TTK_HEALTH[ttk])

var scores := {}
var match_over := false
var map_index := 0  # index into MAPS; the menu sets it
## Menu choice: true = play the whole roster in order (rotating on each win),
## false = replay the chosen map, then back to the menu.
var rotate_maps := false

## Match setup, all chosen on the menu.
## `human_players` is how many split-screen humans are at the couch, and decides
## the viewport layout. `team_size` is the headcount PER TEAM: humans fill the
## slots first and AI makes up the difference, so 2 humans at a team size of 3
## is a 3v3 with four bots in it. `ai_skill` indexes Loadout.SQUAD_SKILLS.
## False from map load until the start countdown finishes. Everything that can
## act checks it, so the opening seconds are a real hold rather than a free hit
## for whoever loads fastest.
var match_live := false

var mode := Mode.DEATHMATCH
## Where the capture area currently is, and whether there is one at all. Bots
## read these to decide where to push in ZONES.
var zone_point := Vector3.ZERO
var zone_active := false

## CONQUEST: the shared reinforcement pool per team (seeded to score_limit()),
## the live command posts (each a CommandPost that reports its own owner), and
## the manager that runs the bleed. `scores` mirrors `tickets` in this mode so
## the scoreboard and victory banner show the count with no special-casing.
var tickets := {}
var conquest_posts: Array[Node3D] = []
var conquest: Node = null

## What the map screen draws. `map_extents` is the playable half-size on XZ;
## `map_shapes` are top-down footprints of the solid geometry, scanned once at
## match start (see scan_map_geometry).
var map_center := Vector3.ZERO
var map_extents := Vector2(40.0, 40.0)
var map_shapes: Array = []  # [{pos: Vector2, size: Vector2, angle: float}, ...]
## Where the AI may walk. Built from map_shapes once the level exists (see
## Main), and shared by every bot — the grid is the same for all of them, and
## one per bot would be the same work sixteen times over.
var nav := NavGrid.new()
var map_bounds_known := false

# A box whose top is at or below this is the floor slab, not an obstacle.
const MAP_FLOOR_TOP := 0.05
const MAP_MAX_SHAPES := 500  # the map is a sketch, not a second render of the level

## Aim assist. PADS by default, because that is the fairness problem it exists
## to fix: a thumbstick is at a real disadvantage against the mouse player
## sitting on the same couch. It only ever slows your look down and nudges it —
## it never bends a shot, so where a round goes is still entirely yours.
enum AimAssist { OFF, PADS, EVERYONE }
const AIM_ASSIST_NAMES := {
	AimAssist.OFF: "OFF", AimAssist.PADS: "PADS", AimAssist.EVERYONE: "EVERYONE",
}
var aim_assist := AimAssist.PADS

## HOW A PLAYER GETS THE GEAR THEY DEPLOY WITH, chosen on the menu and
## deliberately INDEPENDENT of the mode.
##
##   CUSTOM   the buy screen: spend the budget across the catalogue.
##   FACTION  your side's fixed roster: pick one of four authored classes off
##            the character-select screen. No budget, nothing to spend.
##
## Conquest was written as "the mode with no buy screen" and deathmatch as "the
## mode with one", which meant the two were welded to the rules they shipped
## with. They are not the same choice: a Battlefront-style roster is just as
## playable in deathmatch, and shopping is just as playable while fighting over
## command posts. So this is its own setting, `default_class_mode` only seeds it
## from the mode, and both screens work in every mode.
##
## ROYALE is the one exception and always ignores it: there is nothing to pick
## because everything you fight with is scavenged off the ground.
enum ClassMode { CUSTOM, FACTION }
const CLASS_MODE_NAMES := {
	ClassMode.CUSTOM: "CUSTOM (BUY SCREEN)", ClassMode.FACTION: "FACTION ROSTERS",
}
var class_mode := ClassMode.CUSTOM

var human_players := 4
var team_size := 2
var ai_skill := 1
## How many sides when it is not a free-for-all, and whether it is one.
var team_count := 2
var free_for_all := false

const MIN_HUMANS := 1
const MAX_HUMANS := 4
const MIN_TEAM_SIZE := 1
## TWENTY A SIDE IN THE ORDINARY MODES. It was six, which is not a Battlefront
## match — a 6v6 on 260 m of Boneyard is four people who never find each other.
## MASSIVE already proved a hundred bodies runs (see `crowded` for the four
## measures that made it possible); what stopped deathmatch, zones and conquest
## fielding forty was this constant and nothing else.
##
## Twenty rather than fifty because these modes have RULES that scale with the
## roster — conquest posts to contest, a zone with a headcount in it — and fifty
## a side turns every one of them into a scrum. Fifty is what MASSIVE is for.
const MAX_TEAM_SIZE := 20

## Past this many bodies on the field, AI switch to the CHEAP SIMULATION — the
## four measures MASSIVE is built on (see `Bot.thrifty`). Below it they collide,
## step and draw exactly as they always have.
##
## THE THRESHOLD IS BODIES, NOT MODE. Deathmatch at 20v20 has the same problem
## MASSIVE has and it is the same fix; the mode was never what made a crowd
## expensive. 24 is a little over the old ceiling of 4 teams x 6, so nothing that
## used to run at full fidelity has quietly been demoted.
const CROWD_AT := 24

## The team sizes the menu OFFERS. A ladder rather than every integer to 20:
## small sizes are where humans actually fill the slots, so those have to be
## exact, and past eight nobody is choosing between 13 and 14 a side — they are
## choosing "a squad", "a platoon" or "a battle". Twenty items on a dropdown a
## stick has to walk is a menu nobody reaches the end of.
const TEAM_SIZES := [1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 16, 20]


## Does this match field enough bodies to be worth simulating cheaply? Asked once
## by each Bot as it deploys, so the answer cannot change under a body mid-match.
func crowded() -> bool:
	return massive() or active_teams() * team_size >= CROWD_AT


## How many sides are actually in this match. Free-for-all is one team per
## human, so it needs no separate branch anywhere else in the game.
func active_teams() -> int:
	if free_for_all:
		# NETWORKED, a free-for-all is one side per human IN THE SESSION, not one
		# per viewport on this machine — `human_players` is the split-screen count
		# and always was. Reading it here would give a two-machine free-for-all
		# two sides on each machine and put half of everybody on somebody else's.
		return session_humans() if Net.online() else human_players
	return mini(team_count, MAX_TEAMS)


## HOW MANY HUMANS ARE IN THE MATCH, across every machine. Offline that is the
## split-screen count and nothing changes; online it is the session roster.
##
## The distinction this draws is the one the whole networked design rests on:
## `human_players` means VIEWPORTS ON THIS MACHINE and is per-machine forever
## (it sizes the grid, it prices the frame in `Quality`, it picks the minimap
## size). Anything about the MATCH — how many sides there are, how many AI fill
## a team, who is on it — has to ask this instead.
func session_humans() -> int:
	return Net.player_count() if Net.online() else human_players


## Teams the players PICKED on the team-select screen, one per human player.
## Empty means nobody chose — every path that skips team-select (free-for-all)
## leaves it empty and falls back to the round-robin below.
var chosen_teams: Array[int] = []


## Which team a given human player lands on. Their own pick from the team-select
## screen when there is a valid one, else dealt round-robin — so 4 humans across
## 2 teams is 2v2, across 3 is 2/1/1, and free-for-all is one each.
func team_for_player(index: int) -> int:
	# NETWORKED, sides are the HOST'S to deal — the team-select screen is a local
	# arrangement between people who can see each other, and four machines cannot
	# negotiate one. `index` is still this machine's own viewport index, so it is
	# looked up through this machine's share of the roster.
	if Net.online():
		var mine := Net.local_ids()
		return Net.team_of(mine[index]) if index < mine.size() else 0
	if index < chosen_teams.size():
		var pick := chosen_teams[index]
		if pick >= 0 and pick < active_teams():
			return pick
	return index % active_teams()


## How many humans are on a side. NETWORKED this walks the session roster, which
## is what stops every machine filling the same side with its own AI: with two
## machines of two, each counting only its own couch, both would see "two short
## of a four" and the host would field eight bodies a side.
func humans_on_team(team: int) -> int:
	if Net.online():
		return Net.humans_on_team(team)
	var count := 0
	for i in human_players:
		if team_for_player(i) == team:
			count += 1
	return count


## How many AI are needed to bring a team up to the chosen size. Free-for-all
## fills nothing: it is a fight between the people at the couch.
func ai_needed(team: int) -> int:
	if free_for_all:
		return 0
	return maxi(team_size - humans_on_team(team), 0)
## Every body that can be shot, shove or be shoved, and block a spawn marker:
## players and their bought AI squads alike. They register in _ready and drop
## out in _exit_tree; spawn picking and the anti-stacking push both walk this
## instead of a group query, which would allocate every frame.
##
## Duck-typed on purpose so bots don't need to inherit Player: a combatant must
## expose is_alive(), team, take_damage() and global_position.
var combatants: Array[Node3D] = []

var _spawns: Dictionary = {}  # Team -> Array[Node3D]


## DEBUG MODE: put player 1 on the keyboard and mouse instead of a joypad.
##
##   godot --path godot -- --debug
##
## The game is pad-first — Main hands every player a joypad, P1..P4 = pads 0..3 —
## which makes it impossible to try anything at a desk without a controller
## plugged in. This flag is the desk answer: one player, keyboard and mouse, no
## other behaviour changed, so what you are testing is still the real game.
##
## The flag is read from the USER args (everything after the bare `--`), because
## `--debug` on its own is Godot's own engine switch and never reaches us.
## `--kbm` is accepted in either position for the same reason.
var debug_kbm := false


func _init() -> void:
	# Bindings (the kb_* InputMap actions and every pad profile) live in Controls
	# and are read back from user://controls.cfg here, before anything can ask.
	Controls.ensure_loaded()
	# Push the starting universe and TTK into Loadout's mirrors. A `var x := v`
	# initialiser does not run its own setter, so without this the statics would
	# be right only from the first time somebody changed the setting.
	universe = universe
	ttk = ttk
	_read_cmdline()


func _read_cmdline() -> void:
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	for a in args:
		if a == "--debug" or a == "--kbm" or a == "--debug-kbm":
			debug_kbm = true
	if debug_kbm:
		# A sensible desk default, and still overridable on the menu: four
		# viewports with three idle pad players is not what anyone testing alone
		# wants to look at.
		human_players = 1
		print("[debug] keyboard + mouse: player 1 is on the keyboard, solo split")


func score_limit() -> int:
	return int(score_targets[mode])


## Does this match deploy off the faction rosters rather than the buy screen?
## Every screen and every AI asks THIS rather than testing the mode, which is
## what lets faction classes turn up in deathmatch and the buy screen turn up in
## Conquest. Royale is not a shop and not a roster — it is scavenging — so it
## answers false whatever the setting says.
func faction_classes() -> bool:
	return mode != Mode.ROYALE and class_mode == ClassMode.FACTION


## What a mode expects when you first select it. Only a seed: the menu writes it
## into class_mode on a mode change and the player is free to change it after.
func default_class_mode(for_mode: int) -> int:
	return ClassMode.FACTION if for_mode == Mode.CONQUEST else ClassMode.CUSTOM


## Is this the massive mode? Asked by everything that has to behave differently
## at a hundred bodies — the map roster, the AI fill, the bot's own think loop —
## rather than each of them testing the enum, which is the same discipline
## `faction_classes()` keeps.
func massive() -> bool:
	return mode == Mode.MASSIVE


## The generated map's index in MAPS. MASSIVE is locked to it, so this is the one
## place that has to know which row it is.
func procedural_map_index() -> int:
	for i in MAPS.size():
		if MAPS[i].get("procedural", false):
			return i
	return 0


## The current mode's blurb with its own numbers already in it.
##
## How many arguments a blurb takes is part of the blurb, and only this file
## knows it — ROYALE's line takes none where the others take one and two. A
## caller that guesses gets "not all arguments converted", which in GDScript
## aborts the whole function it happens in: the menu's one refresh closure
## updates every chip, so a mismatch here silently froze the entire screen the
## moment you selected the mode. Format the blurb HERE, never at the caller.
func mode_blurb() -> String:
	match mode:
		Mode.DEATHMATCH:
			return MODE_BLURBS[mode] % score_limit()
		Mode.ZONES:
			return MODE_BLURBS[mode] % [int(Zone.RELOCATE_EVERY), score_limit()]
		Mode.CONQUEST:
			return MODE_BLURBS[mode] % score_limit()
		Mode.MASSIVE:
			return MODE_BLURBS[mode] % [team_size, score_limit()]
		_:
			return MODE_BLURBS[mode]


func reset_match() -> void:
	scores = {}
	for t in active_teams():
		scores[t] = 0
	match_over = false
	match_live = false
	zone_active = false
	map_shapes.clear()
	# The record is per MATCH, so the post-match table shows this map's fighting
	# and not the accumulated rotation.
	kill_feed.clear()
	player_stats.clear()
	# A fresh world for a fresh match. Rolled here rather than at generation
	# time so it is fixed for the whole match: every structure and prop is placed
	# from it, and a seed that moved would tear the map apart mid-round.
	#
	# NOT WHEN THERE IS A SESSION — on EITHER side. The seed IS the map: every
	# structure, every prop and every piece of cover is placed from it, so two
	# machines with two seeds are two different worlds, and every symptom after
	# that (walking into invisible buildings, taking cover behind nothing, being
	# shot through a wall only one of you has) reads as a replication bug rather
	# than as the map it actually is.
	#
	# The guard was `Net.authority()` first, which is wrong in the direction
	# nobody looks: `Net.start_match` rolls the seed and SENDS it, and then the
	# host changes scene and lands here — so the host, not the client, threw away
	# the world it had just told everybody to build. Online, the seed belongs to
	# the session and this function only ever leaves it alone.
	if not Net.online():
		planet_seed = int(Time.get_unix_time_from_system()) ^ (randi() & 0xffff)
	nav = NavGrid.new()
	map_bounds_known = false
	smokes.clear()
	scanned.clear()
	_spawns.clear()
	combatants.clear()
	# CONQUEST: seed each side's reinforcements and mirror them into the score.
	tickets.clear()
	conquest_posts.clear()
	conquest = null
	if mode == Mode.CONQUEST:
		for t in active_teams():
			tickets[t] = score_limit()
			scores[t] = tickets[t]


## A map declares its playable area. Arena does this for every procedural map;
## anything hand-authored falls back to the scanned geometry's own extents.
func register_map_bounds(center: Vector3, extents: Vector2) -> void:
	map_center = center
	map_extents = extents
	map_bounds_known = true


## Build the map screen's picture of the level: every world-layer box collider,
## flattened to a top-down footprint. Scanned rather than declared per map, so a
## new map draws on the map screen without doing anything — including the
## hand-authored hangar, which has no layout table to read.
##
## Only layer-1 (world) bodies count, which is what keeps turrets, shields and
## players out of it; and only box shapes, so the terrain map's trimesh hill is
## skipped and Highridge shows its props rather than its contours.
func scan_map_geometry(level: Node) -> void:
	map_shapes.clear()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for body in level.find_children("*", "StaticBody3D", true, false):
		if (body.collision_layer & 1) == 0:
			continue
		for node in body.find_children("*", "CollisionShape3D", true, false):
			if map_shapes.size() >= MAP_MAX_SHAPES:
				break
			var box := node.shape as BoxShape3D
			if box == null:
				continue
			var xform: Transform3D = node.global_transform
			var scale: Vector3 = xform.basis.get_scale()
			if xform.origin.y + box.size.y * 0.5 * scale.y <= MAP_FLOOR_TOP:
				continue  # the floor slab; drawing it would black out the whole map
			var half := Vector2(box.size.x * scale.x, box.size.z * scale.z) * 0.5
			var at := Vector2(xform.origin.x, xform.origin.z)
			map_shapes.append({
				"pos": at,
				"size": half * 2.0,
				"angle": atan2(-xform.basis.z.x, -xform.basis.z.z),
			})
			var reach := half.length()  # rotation-proof outer bound
			lo = lo.min(at - Vector2(reach, reach))
			hi = hi.max(at + Vector2(reach, reach))
	if not map_bounds_known and lo.x < INF:
		map_center = Vector3((lo.x + hi.x) * 0.5, 0.0, (lo.y + hi.y) * 0.5)
		map_extents = (hi - lo) * 0.5
		map_bounds_known = true


func register_combatant(body: Node3D) -> void:
	if not combatants.has(body):
		combatants.append(body)


func unregister_combatant(body: Node3D) -> void:
	combatants.erase(body)
	cloaked.erase(body)
	scanned.erase(body)


## --- per-frame combatant snapshot --------------------------------------------
##
## The four reads a head count needs — validity, is_alive(), global_position and
## team — taken ONCE per physics frame and shared by everything that counts
## bodies in an area that frame. Read `live_n` and index `live_points`/
## `live_teams` together; do not hold the arrays across frames.
##
## This exists because Conquest asks for a capture read on EVERY command post on
## EVERY physics frame, where Zones asks once a second for one area. Each post
## re-walked `combatants` and re-took all four reads per body, so the scan was
## multiplied by the number of posts on the map — five posts against a full
## lobby measured 0.4 ms a frame doing the identical work five times. Sampling
## once is not an approximation: within a single physics frame every post saw
## the same unmoved bodies anyway.
var live_points := PackedVector3Array()
var live_teams := PackedInt32Array()
## The bodies behind live_points/live_teams, same indices. See sample_combatants.
var live_bodies: Array[Node3D] = []
var live_n := 0
var _live_frame := -1
## Grown in blocks and never shrunk, so a settled match stops reallocating.
const _LIVE_GROW := 8


func sample_combatants() -> void:
	var frame := Engine.get_physics_frames()
	if frame == _live_frame:
		return
	_live_frame = frame
	var n := 0
	for c in combatants:
		if not is_instance_valid(c) or not c.is_alive():
			continue
		if live_points.size() <= n:
			live_points.resize(n + _LIVE_GROW)
			live_teams.resize(n + _LIVE_GROW)
		live_points[n] = c.global_position
		live_teams[n] = c.team
		# The BODY as well as its position, so a reader can act on what it finds
		# without a second validity pass. `live_bodies` is a plain Array (it holds
		# references, so it cannot be packed) and is never shrunk, exactly like
		# the other two — at a hundred bodies this is the difference between one
		# validated walk a frame and one per bot.
		if live_bodies.size() <= n:
			live_bodies.resize(n + _LIVE_GROW)
		live_bodies[n] = c
		n += 1
	live_n = n


## Combatants currently invisible to AI (the Trandoshan's cloak). A set kept
## here rather than a flag on the body so every AI vision check can consult it
## the same way it consults `smokes`, without duck-typing a method onto Player,
## Bot and Turret. Only Player ever adds to it today.
var cloaked: Array[Node3D] = []


func set_cloaked(body: Node3D, on: bool) -> void:
	if on:
		if not cloaked.has(body):
			cloaked.append(body)
	else:
		cloaked.erase(body)


func is_cloaked(body: Node3D) -> bool:
	return not cloaked.is_empty() and cloaked.has(body)


## Enemies currently REVEALED by a scan dart, body -> {"team", "until" (msec)}.
## The reveal is team-wide (whoever threw the dart shows it to their whole side)
## and time-limited, and it draws THROUGH walls — that is the recon value. Read by
## the per-viewport scan overlay in Main.
var scanned := {}


func mark_scanned(body: Node3D, team: int, duration: float) -> void:
	scanned[body] = {"team": team, "until": Time.get_ticks_msec() + int(duration * 1000.0)}


func is_scanned_for(body: Node3D, team: int) -> bool:
	var e = scanned.get(body)
	if e == null:
		return false
	if e["until"] < Time.get_ticks_msec():
		scanned.erase(body)
		return false
	return e["team"] == team


## Smoke clouds currently on the field. They have no collider on purpose (that
## would stop bullets and bodies), so sight checks consult this list instead.
var smokes: Array[Node3D] = []


func register_smoke(cloud: Node3D) -> void:
	if not smokes.has(cloud):
		smokes.append(cloud)


func unregister_smoke(cloud: Node3D) -> void:
	smokes.erase(cloud)


## The standing height of an ordinary trooper, and where its chest is as a
## fraction of that. Every shooter in the game used to aim at a flat 1.0 m,
## which was exactly right while every body in the game was the same body.
const TROOPER_HEIGHT := 1.8
const CHEST_FRACTION := 0.56


## HOW HIGH TO AIM AT A BODY, above its feet. Units have a stature now — an Ewok
## stands about 1.1 m and a Super Battle Droid over 2.1 — so a fixed chest height
## puts an AI's rounds over the small ones and into the belt of the big ones,
## and does the same to the sight checks that decide whether they are seen at
## all. Duck-typed like is_alive(): anything not answering body_height() is
## assumed trooper-sized, which is what a turret or a prop should be.
static func aim_height(body: Node) -> float:
	var h := TROOPER_HEIGHT
	if body != null and body.has_method("body_height"):
		h = body.body_height()
	return h * CHEST_FRACTION


## Does a sight line pass through smoke? Segment-vs-sphere, closest approach
## clamped to the segment, so a cloud behind the viewer or past the target does
## not count. Every AI vision check runs this, so it stays allocation-free and
## returns immediately in the normal case of no smoke on the field.
func sight_blocked(from: Vector3, to: Vector3) -> bool:
	if smokes.is_empty():
		return false
	var seg := to - from
	var len_sq := seg.length_squared()
	for cloud in smokes:
		if not is_instance_valid(cloud):
			continue
		var centre: Vector3 = cloud.global_position
		var t := 0.0 if len_sq < 0.0001 else clampf((centre - from).dot(seg) / len_sq, 0.0, 1.0)
		var nearest := from + seg * t
		var r: float = cloud.radius()
		if nearest.distance_squared_to(centre) <= r * r:
			return true
	return false


func register_spawn_point(team: int, marker: Node3D) -> void:
	_spawns.get_or_add(team, []).append(marker)


## Deterministic when index is given (initial spawns), otherwise random among
## the markers no living player is standing on (respawns), so players never
## stack on one marker.
func get_spawn_point(team: int, index: int = -1) -> Node3D:
	var list: Array = _spawn_list(team)
	if list.is_empty():
		return null
	if index >= 0:
		return list[index % list.size()]
	var free: Array = []
	var roomiest: Node3D = list[0]
	var roomiest_gap := -1.0
	for m in list:
		var gap := _nearest_body_gap(m.global_position)
		if gap >= SPAWN_CLEARANCE:
			free.append(m)
		elif gap > roomiest_gap:
			roomiest_gap = gap
			roomiest = m
	# Every marker crowded (small map, everyone bunched): take the roomiest one.
	return free.pick_random() if not free.is_empty() else roomiest


## Markers a team may start on.
func _spawn_list(team: int) -> Array:
	return _spawns.get(team, [])


## Put each side in its own corner of the map.
##
## Maps only ever author TWO sets of markers, at two ends. With three or four
## teams that leaves the extra sides sharing somebody else's start, which in a
## free-for-all means spawning on top of an enemy. So for a 3+ team match the
## authored layout is replaced wholesale: every side gets a corner of its own,
## as far from the others as the map allows.
##
## Two-team matches are left completely alone — those layouts are hand-placed
## and tuned, and a corner is not automatically better than the spot a map
## author chose.
##
## Ground height comes from the level's own `height_at` when it has one (the
## terrain maps), because colliders are not in the physics world yet when this
## runs and a downward raycast would find nothing.
##
## And it is lifted by SPAWN_LIFT. `height_at` is the ANALYTIC surface, but what
## you collide with is a heightfield MESH sampled on a coarse grid, and across a
## hollow the mesh's flat triangles sit ABOVE the curve they approximate — so a
## body placed at the analytic height starts inside the ground and is stuck
## there. Dropping the last metre costs nothing and is always safe.
func place_corner_spawns(level: Node) -> void:
	if active_teams() <= 2:
		return
	_spawns.clear()
	var inset: Vector2 = map_extents * 0.72
	var corners := [
		Vector2(-inset.x, -inset.y), Vector2(inset.x, inset.y),
		Vector2(inset.x, -inset.y), Vector2(-inset.x, inset.y),
	]
	for team in active_teams():
		var at: Vector2 = corners[team % corners.size()]
		# Three markers spread around the corner, so a side of several bodies
		# does not have to funnel through one point.
		for k in 3:
			var a := TAU * float(k) / 3.0
			var spot := at + Vector2(cos(a), sin(a)) * 5.0
			var y := 0.0
			if level.has_method("height_at"):
				y = level.height_at(spot.x, spot.y)
			var m := Marker3D.new()
			m.position = Vector3(map_center.x + spot.x, y + SPAWN_LIFT,
				map_center.z + spot.y)
			level.add_child(m)
			# Face the middle, so a side spawns looking into the map.
			if Vector2(spot.x, spot.y).length() > 0.1:
				m.look_at(Vector3(map_center.x, y, map_center.z), Vector3.UP)
			register_spawn_point(team, m)


## Last line of defence for the crowded case: shove a spawn transform sideways
## until it clears the body nearest to it, so a respawn never starts inside
## another capsule even when every marker was occupied.
func clear_of_bodies(xform: Transform3D) -> Transform3D:
	var body := _nearest_body(xform.origin)
	if body == null or xform.origin.distance_to(body.global_position) >= MIN_BODY_GAP:
		return xform
	var away := xform.origin - body.global_position
	away.y = 0.0
	if away.length() < 0.01:  # exactly on top of them: any direction will do
		away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	xform.origin += away.normalized() * MIN_BODY_GAP
	return xform


## Distance from a candidate spawn to the closest living player.
func _nearest_body_gap(pos: Vector3) -> float:
	var body := _nearest_body(pos)
	return INF if body == null else pos.distance_to(body.global_position)


## The living player closest to a point. Dead players have their collision
## disabled, so they don't block a marker.
func _nearest_body(pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_gap := INF
	for p in combatants:
		if not p.is_alive():
			continue
		var gap := pos.distance_to(p.global_position)
		if gap < best_gap:
			best_gap = gap
			best = p
	return best


## Credit a kill. Only DEATHMATCH scores for it — in ZONES a kill is a means to
## an end, and in ROYALE the only thing that counts is who is left.
func add_frag(team: int) -> void:
	if mode == Mode.DEATHMATCH:
		_award(team)


## --- The record: who killed whom, and what each human did with their match ---
##
## SCORING AND RECORDING ARE DIFFERENT QUESTIONS, which is why this sits beside
## `add_frag` rather than inside it. What a kill is WORTH is a mode rule and
## changes per mode (Zones pays nothing for one); that a kill HAPPENED is true in
## every mode and is what the feed and the post-match screen read. Folding the
## record into `add_frag` would have lost every kill in four modes out of five.

## The last few kills, newest last. A ring rather than a growing log: the feed
## draws a handful and a long match is thousands of deaths.
var kill_feed: Array[Dictionary] = []
const KILL_FEED_MAX := 6

## Per-HUMAN stats for the match, keyed by `player_index`.
##
## HUMANS ONLY, and that is a limit of identity rather than a decision about who
## is interesting: a Bot is freed on death and replaced by a different instance,
## so there is nothing stable to accumulate into. A player_index outlives every
## death its owner has. Team totals are already in `scores`.
var player_stats: Dictionary = {}


## The stat row for a human, created on demand so nothing has to know the roster
## up front (players deploy at different times, and Royale never respawns them).
func stats_for(player_index: int) -> Dictionary:
	if not player_stats.has(player_index):
		player_stats[player_index] = {
			"kills": 0, "deaths": 0, "headshots": 0, "streak": 0, "best_streak": 0,
			"team": 0, "name": "PLAYER %d" % (player_index + 1),
		}
	return player_stats[player_index]


## What to call a body in the feed. ASKED, NOT REQUIRED: a combatant that never
## grew a `combatant_name` gets its class back instead of aborting the whole
## kill record (house rule 6 — a missing method would take the feed, the stats
## and everything after them out with it).
## DELIBERATELY UNTYPED. A `body: Node` parameter cannot even be CALLED with a
## freed object — GDScript refuses the bind before the function runs, and a
## refused call aborts whatever was recording the kill (house rule 6). The feed
## exists precisely to describe bodies that are on their way out, so the one
## argument it must survive is the one a type annotation makes impossible.
func combatant_name(body) -> String:
	if body == null or not is_instance_valid(body):
		return "?"
	if body.has_method("combatant_name"):
		return str(body.combatant_name())
	return body.get_class().to_upper()


## A body went down. `killer` may be null (a fall, the storm), may be the victim
## itself (own splash) and may be a teammate — the feed states all three, because
## "who killed me" is exactly the question a death cam exists to answer and the
## honest answer is sometimes "you did".
##
## Called from every `_die`, ALONGSIDE `add_frag`/`report_death` and never
## instead of them.
func record_kill(killer, victim, headshot := false) -> void:
	# Typed explicitly: `killer` is untyped (see combatant_name) so the comparison
	# has no inferable type and `:=` will not compile.
	var suicide: bool = killer == null or killer == victim
	var entry := {
		"killer": "" if suicide else combatant_name(killer),
		"killer_team": -1 if suicide else int(killer.get("team")),
		"victim": combatant_name(victim),
		"victim_team": int(victim.get("team")) if victim != null else -1,
		"headshot": headshot,
		"suicide": suicide,
	}
	# Only a HUMAN carries a stat row, and `stat_index` is how a body says it is
	# one. Duck-typed rather than `is Player` so a NetPlayer proxy can answer for
	# a human on another machine — online, the host scores kills by bodies it does
	# not own, and those are all proxies.
	_note_stat_index(entry, "killer_index", killer if not suicide else null)
	_note_stat_index(entry, "victim_index", victim)
	log_kill(entry)


func _note_stat_index(entry: Dictionary, key: String, body) -> void:
	if body != null and is_instance_valid(body) and body.has_method("stat_index"):
		var idx: int = body.stat_index()
		if idx >= 0:
			entry[key] = idx


## The record proper, split from `record_kill` so the wire can hand over an entry
## it was given rather than two bodies it does not have (a client has no node for
## a bot that died on the host).
## `mirror` is false for an entry that ARRIVED over the wire, which is the only
## thing stopping the host echoing back what it was just sent.
func log_kill(entry: Dictionary, mirror := true) -> void:
	kill_feed.append(entry)
	while kill_feed.size() > KILL_FEED_MAX:
		kill_feed.pop_front()
	var friendly: bool = not bool(entry["suicide"]) \
		and int(entry["killer_team"]) == int(entry["victim_team"])
	# A human's own row. Teamkills and suicides cost a death and pay no kill —
	# otherwise the quickest route up the scoreboard is a grenade at your feet.
	if entry.has("killer_index") and not bool(entry["suicide"]) and not friendly:
		var k: Dictionary = stats_for(int(entry["killer_index"]))
		k["kills"] = int(k["kills"]) + 1
		k["streak"] = int(k["streak"]) + 1
		k["best_streak"] = maxi(int(k["best_streak"]), int(k["streak"]))
		k["team"] = int(entry["killer_team"])
		if bool(entry["headshot"]):
			k["headshots"] = int(k["headshots"]) + 1
	if entry.has("victim_index"):
		var v: Dictionary = stats_for(int(entry["victim_index"]))
		v["deaths"] = int(v["deaths"]) + 1
		v["streak"] = 0        # the streak is per LIFE, so dying ends it
		v["team"] = int(entry["victim_team"])
	kill_logged.emit(entry)
	# ONLINE THE FEED IS THE HOST'S, and it is mirrored out from this ONE place
	# rather than from each `_die`. A bot dies on the host and a player dies on
	# whichever machine owns them, so the alternative is every death path knowing
	# how to replicate itself — which is how two machines end up with feeds that
	# disagree about what just happened.
	if mirror and Net.is_host() and NetSync.current != null:
		NetSync.current.mirror_kill(entry)


## The post-match table: every human that saw play, best first. Sorted on kills,
## then on FEWER deaths, so two players on three kills are separated by what it
## cost them rather than by dictionary order.
func score_table() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for idx in player_stats:
		var row: Dictionary = (player_stats[idx] as Dictionary).duplicate()
		row["index"] = idx
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["kills"]) != int(b["kills"]):
			return int(a["kills"]) > int(b["kills"])
		return int(a["deaths"]) < int(b["deaths"]))
	return rows


## Royale has no score, so the match ends the moment one side is the only one
## with anybody left alive. Called whenever a combatant dies.
##
## Deliberately counts COMBATANTS, not players: a squad of bought AI keeps their
## owner's side alive after they personally go down, which is what makes buying
## a squad matter in a mode with no respawns.
func check_last_standing() -> void:
	if mode != Mode.ROYALE or match_over or not match_live:
		return
	var alive := {}
	for c in combatants:
		if is_instance_valid(c) and c.is_alive():
			alive[c.team] = true
	if alive.size() == 1:
		_award(alive.keys()[0])
	elif alive.is_empty():
		match_over = true   # everyone went down together; nobody wins


## A second of holding the capture area.
func add_zone_tick(team: int) -> void:
	if mode == Mode.ZONES:
		_award(team)


## --- Conquest ----------------------------------------------------------------

func register_conquest_post(post: Node3D) -> void:
	if not conquest_posts.has(post):
		conquest_posts.append(post)


## The posts a team currently holds — the spots it may deploy on. `owner_team`
## rather than the built-in Node.owner, which is the scene owner and unrelated.
func owned_posts(team: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for p in conquest_posts:
		if is_instance_valid(p) and p.owner_team == team:
			out.append(p)
	return out


## Counts in place. `owned_posts().size()` allocated an array to throw it away,
## which the reinforcement bleed and every deploy screen ask for repeatedly.
func posts_held(team: int) -> int:
	var n := 0
	for p in conquest_posts:
		if is_instance_valid(p) and p.owner_team == team:
			n += 1
	return n


## Bumped every time a post changes hands. A screen showing the front line can
## compare this in O(1) to tell whether anything it drew has moved, instead of
## rebuilding the whole read every frame to find out it has not.
var posts_revision := 0


## A body on `team` went down. In Conquest that is a reinforcement spent.
func report_death(team: int) -> void:
	if mode == Mode.CONQUEST:
		_spend_ticket(team, 1)


## Passive reinforcement bleed from holding fewer posts than the enemy (the
## Conquest manager drives this on its own clock).
func conquest_bleed(team: int, amount: int) -> void:
	if mode == Mode.CONQUEST:
		_spend_ticket(team, amount)


func _spend_ticket(team: int, amount: int) -> void:
	if match_over or not tickets.has(team):
		return
	tickets[team] = maxi(int(tickets[team]) - amount, 0)
	scores[team] = tickets[team]           # the scoreboard reads scores
	score_changed.emit(team, scores[team])
	if tickets[team] <= 0:
		_conquest_defeat(team)


## A side ran out of reinforcements: whoever still has some wins.
func _conquest_defeat(loser: int) -> void:
	if match_over:
		return
	var winner := -1
	var best := -1
	for t in active_teams():
		if t == loser:
			continue
		var left := int(tickets.get(t, 0))
		if left > best:
			best = left
			winner = t
	if winner == -1:
		winner = 0 if loser != 0 else 1
	match_over = true
	match_won.emit(winner)


func _award(team: int) -> void:
	if match_over:
		return
	# A team can score before reset_match has seen it (a bot spawned early, a
	# team added by the menu), so never assume the key is there.
	scores[team] = int(scores.get(team, 0)) + 1
	score_changed.emit(team, scores[team])
	if scores[team] >= score_limit():
		match_over = true
		match_won.emit(team)
