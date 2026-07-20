extends "res://scripts/character.gd"
## Decorative squad NPC: a procedural CharacterModel that loops an animation
## (random phase so squads don't march in lockstep) and optionally patrols
## between waypoints. No collision — Battlefront AI replaces this _process
## movement with a CharacterBody3D state machine later.

@export var anim := "idle"
@export var patrol_path: Array[NodePath] = []
@export var walk_speed := 1.4

var _points: Array[Node3D] = []
var _target := 0


func _ready() -> void:
	super()  # CharacterModel builds the box rig + AnimationPlayer
	for path in patrol_path:
		var node := get_node_or_null(path)
		if node is Node3D:
			_points.append(node)
	if not _points.is_empty():
		anim = "walk"
	if anim_player.has_animation(anim):
		anim_player.play(anim)
		anim_player.seek(randf() * anim_player.current_animation_length, true)


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
