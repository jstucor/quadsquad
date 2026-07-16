extends Node3D
## Squad trooper NPC. Plays looping animations with a random phase offset so
## squads don't move in lockstep; optionally patrols between waypoints.
## Decorative for now (no collision) — Battlefront AI replaces _process
## movement with a CharacterBody3D + state machine later.

@export var anim := "idle"
@export var patrol_path: Array[NodePath] = []
@export var walk_speed := 1.4

var _points: Array[Node3D] = []
var _target := 0
var _anim_player: AnimationPlayer


func _ready() -> void:
	_anim_player = find_child("AnimationPlayer", true, false)
	if _anim_player == null:
		push_warning("Trooper '%s': model has no AnimationPlayer" % name)
	for path in patrol_path:
		var node := get_node_or_null(path)
		if node is Node3D:
			_points.append(node)
	if not _points.is_empty():
		anim = "walk"
	_play(anim)


func _process(delta: float) -> void:
	if _points.is_empty():
		return
	var target := _points[_target].global_position
	target.y = global_position.y
	var offset := target - global_position
	if offset.length() < 0.25:
		_target = (_target + 1) % _points.size()
		return
	look_at(target)  # model faces -Z, same as look_at
	global_position += offset.normalized() * walk_speed * delta


func _play(anim_name: String) -> void:
	if _anim_player == null or not _anim_player.has_animation(anim_name):
		return
	_anim_player.play(anim_name)
	_anim_player.seek(randf() * _anim_player.current_animation_length, true)
