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
enum Mode { DEATHMATCH, ZONES }
const MODE_NAMES := {Mode.DEATHMATCH: "DEATHMATCH", Mode.ZONES: "ZONES"}
const MODE_BLURBS := {
	Mode.DEATHMATCH: "First to %d kills",
	Mode.ZONES: "Hold the area. A point a second, new area every %ds, first to %d",
}

# What each mode plays to: kills, or seconds of control.
const SCORE_LIMITS := {Mode.DEATHMATCH: 25, Mode.ZONES: 60}

# A respawn must never land on a living body: two overlapping capsules push each
# other apart every physics frame and ride that ejection out of the map, which
# drags the innocent player along with the one who died.
const SPAWN_CLEARANCE := 2.5  # a marker this close (m) to a live player is taken
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
]
const TEAM_NAMES := {Team.REPUBLIC: "REPUBLIC", Team.CIS: "SEPARATIST"}
const TEAM_COLORS := {
	Team.REPUBLIC: Color(0.35, 0.55, 1.0),
	Team.CIS: Color(1.0, 0.4, 0.32),
}

var scores := {Team.REPUBLIC: 0, Team.CIS: 0}
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

var human_players := 4
var team_size := 2
var ai_skill := 1

const MIN_HUMANS := 1
const MAX_HUMANS := 4
const MIN_TEAM_SIZE := 1
const MAX_TEAM_SIZE := 6


## Which team a given human player lands on: the first half of them hold the
## Republic side, the rest are Separatists, so 4 humans is 2v2 and 2 is 1v1.
func team_for_player(index: int) -> int:
	return Team.REPUBLIC if index < ceili(human_players / 2.0) else Team.CIS


func humans_on_team(team: int) -> int:
	var count := 0
	for i in human_players:
		if team_for_player(i) == team:
			count += 1
	return count


## How many AI are needed to bring a team up to the chosen size.
func ai_needed(team: int) -> int:
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


func _init() -> void:
	# Bindings (the kb_* InputMap actions and every pad profile) live in Controls
	# and are read back from user://controls.cfg here, before anything can ask.
	Controls.ensure_loaded()


func score_limit() -> int:
	return SCORE_LIMITS[mode]


func reset_match() -> void:
	scores = {Team.REPUBLIC: 0, Team.CIS: 0}
	match_over = false
	match_live = false
	zone_active = false
	_spawns.clear()
	combatants.clear()


func register_combatant(body: Node3D) -> void:
	if not combatants.has(body):
		combatants.append(body)


func unregister_combatant(body: Node3D) -> void:
	combatants.erase(body)


func register_spawn_point(team: int, marker: Node3D) -> void:
	_spawns.get_or_add(team, []).append(marker)


## Deterministic when index is given (initial spawns), otherwise random among
## the markers no living player is standing on (respawns), so players never
## stack on one marker.
func get_spawn_point(team: int, index: int = -1) -> Node3D:
	var list: Array = _spawns.get(team, [])
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
## an end, not the end itself.
func add_frag(team: int) -> void:
	if mode == Mode.DEATHMATCH:
		_award(team)


## A second of holding the capture area.
func add_zone_tick(team: int) -> void:
	if mode == Mode.ZONES:
		_award(team)


func _award(team: int) -> void:
	if match_over:
		return
	scores[team] += 1
	score_changed.emit(team, scores[team])
	if scores[team] >= score_limit():
		match_over = true
		match_won.emit(team)
