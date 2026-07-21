extends Node
## Autoload: match state — teams, team-deathmatch score, spawn points, and the
## map rotation. Levels register spawn markers per team; actors credit frags
## here on a kill, so the mode rules live in one place. Also bootstraps the
## keyboard/mouse InputMap (registered in code, no project.godot serialization).

signal score_changed(team: int, score: int)
signal match_won(team: int)

enum Team { REPUBLIC, CIS }

const SCORE_LIMIT := 25  # frags for a team to win

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
	_register_kb_actions()


func reset_match() -> void:
	scores = {Team.REPUBLIC: 0, Team.CIS: 0}
	match_over = false
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


## Credit a kill to the attacker's team; ends the match at SCORE_LIMIT.
func add_frag(team: int) -> void:
	if match_over:
		return
	scores[team] += 1
	score_changed.emit(team, scores[team])
	if scores[team] >= SCORE_LIMIT:
		match_over = true
		match_won.emit(team)


func _register_kb_actions() -> void:
	var keys := {
		"kb_forward": KEY_W,
		"kb_back": KEY_S,
		"kb_left": KEY_A,
		"kb_right": KEY_D,
		"kb_jump": KEY_SPACE,
		"kb_sprint": KEY_SHIFT,
		"kb_crouch": KEY_CTRL,
		"kb_grenade": KEY_G,
		"kb_medkit": KEY_H,
		"kb_gadget": KEY_F,
		"kb_switch": KEY_Q,  # swap primary <-> sidearm
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = keys[action]
		InputMap.action_add_event(action, ev)
	# Mouse-button actions: left = fire, right = aim down sights.
	var mouse_actions := {
		"kb_fire": MOUSE_BUTTON_LEFT,
		"kb_ads": MOUSE_BUTTON_RIGHT,
	}
	for action in mouse_actions:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = mouse_actions[action]
		InputMap.action_add_event(action, mb)
