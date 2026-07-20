extends Node
## Autoload: match state — teams, team-deathmatch score, spawn points, and the
## map rotation. Levels register spawn markers per team; actors credit frags
## here on a kill, so the mode rules live in one place. Also bootstraps the
## keyboard/mouse InputMap (registered in code, no project.godot serialization).

signal score_changed(team: int, score: int)
signal match_won(team: int)

enum Team { REPUBLIC, CIS }

const SCORE_LIMIT := 25  # frags for a team to win
const TEAM_NAMES := {Team.REPUBLIC: "REPUBLIC", Team.CIS: "SEPARATIST"}
const TEAM_COLORS := {
	Team.REPUBLIC: Color(0.35, 0.55, 1.0),
	Team.CIS: Color(1.0, 0.4, 0.32),
}

var scores := {Team.REPUBLIC: 0, Team.CIS: 0}
var match_over := false
var map_index := 0  # index into Main.MAPS; advanced on match end

var _spawns: Dictionary = {}  # Team -> Array[Node3D]


func _init() -> void:
	_register_kb_actions()


func reset_match() -> void:
	scores = {Team.REPUBLIC: 0, Team.CIS: 0}
	match_over = false
	_spawns.clear()


func register_spawn_point(team: int, marker: Node3D) -> void:
	_spawns.get_or_add(team, []).append(marker)


## Deterministic when index is given (initial spawns), random otherwise
## (respawns), so players never stack on one marker at match start.
func get_spawn_point(team: int, index: int = -1) -> Node3D:
	var list: Array = _spawns.get(team, [])
	if list.is_empty():
		return null
	if index >= 0:
		return list[index % list.size()]
	return list.pick_random()


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
		"kb_switch": KEY_Q,  # cycle weapon class
		"kb_crouch": KEY_CTRL,
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
