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
enum Mode { DEATHMATCH, ZONES, ROYALE, CONQUEST }
const MODE_NAMES := {
	Mode.DEATHMATCH: "DEATHMATCH", Mode.ZONES: "ZONES", Mode.ROYALE: "BATTLE ROYALE",
	Mode.CONQUEST: "CONQUEST",
}
const MODE_BLURBS := {
	Mode.DEATHMATCH: "First to %d kills",
	Mode.ZONES: "Hold the area. A point a second, new area every %ds, first to %d",
	Mode.ROYALE: "No respawns. Scavenge your gear, outlast the storm, last side wins",
	Mode.CONQUEST: "Capture command posts to spawn on. Hold more to bleed the enemy's %d reinforcements to zero",
}

# DEFAULT victory threshold per mode: kills, seconds of control, being the last
# side left (one "point", awarded once), or the reinforcement pool each side
# starts Conquest with. The menu lets you raise or lower all but royale's —
# score_targets holds the chosen values, seeded from here.
const SCORE_LIMITS := {Mode.DEATHMATCH: 25, Mode.ZONES: 60, Mode.ROYALE: 1, Mode.CONQUEST: 150}
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
const MAX_TEAM_SIZE := 6


## How many sides are actually in this match. Free-for-all is one team per
## human, so it needs no separate branch anywhere else in the game.
func active_teams() -> int:
	return human_players if free_for_all else mini(team_count, MAX_TEAMS)


## Teams the players PICKED on the team-select screen, one per human player.
## Empty means nobody chose — every path that skips team-select (free-for-all)
## leaves it empty and falls back to the round-robin below.
var chosen_teams: Array[int] = []


## Which team a given human player lands on. Their own pick from the team-select
## screen when there is a valid one, else dealt round-robin — so 4 humans across
## 2 teams is 2v2, across 3 is 2/1/1, and free-for-all is one each.
func team_for_player(index: int) -> int:
	if index < chosen_teams.size():
		var pick := chosen_teams[index]
		if pick >= 0 and pick < active_teams():
			return pick
	return index % active_teams()


func humans_on_team(team: int) -> int:
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
