extends Node
## Autoload: Battlefront-style match state — teams, reinforcement tickets,
## and spawn points. Levels register spawn markers; actors query and spend
## tickets here, so conquest rules can grow without touching actor code.
## Also bootstraps the keyboard/mouse InputMap (registered in code so there
## is no hand-maintained serialization in project.godot).

signal tickets_changed(team: int, count: int)

enum Team { REPUBLIC, CIS }

const START_TICKETS := 200

var tickets := {Team.REPUBLIC: START_TICKETS, Team.CIS: START_TICKETS}

var _spawns: Dictionary = {}  # Team -> Array[Node3D]


func _init() -> void:
	_register_kb_actions()


func reset_match() -> void:
	tickets = {Team.REPUBLIC: START_TICKETS, Team.CIS: START_TICKETS}
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


func take_ticket(team: int) -> void:
	tickets[team] = maxi(tickets[team] - 1, 0)
	tickets_changed.emit(team, tickets[team])


func _register_kb_actions() -> void:
	var keys := {
		"kb_forward": KEY_W,
		"kb_back": KEY_S,
		"kb_left": KEY_A,
		"kb_right": KEY_D,
		"kb_jump": KEY_SPACE,
		"kb_sprint": KEY_SHIFT,
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = keys[action]
		InputMap.action_add_event(action, ev)
	if not InputMap.has_action("kb_fire"):
		InputMap.add_action("kb_fire")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("kb_fire", mb)
