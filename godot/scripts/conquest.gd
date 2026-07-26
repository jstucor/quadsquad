class_name Conquest
extends Node3D
## Runs the CONQUEST match: lays out the command posts, and bleeds the
## reinforcements of whichever side holds fewer of them. Deaths spend tickets on
## their own (GameState.report_death from each die path); this adds the passive
## drain that makes CAPTURING posts — not just fragging — the way you win.
##
## Placed in the level by Main (like Storm/Zone) so it is torn down with the map.
## Posts are laid along the map's long axis: a home post at each end owned by its
## side, neutral posts down the middle to fight over.

const POST_SCENE := preload("res://scripts/command_post.gd")
const BLEED_INTERVAL := 2.0    # seconds between reinforcement drains
const BLEED_PER_POST := 1      # tickets lost per interval, per post of deficit
const HOME_FRAC := 0.8         # home posts sit this far out along the axis
const NEUTRAL_FRACS := [-0.36, 0.0, 0.36]   # neutral posts down the middle
const NAMES := ["ALPHA", "BRAVO", "CHARLIE", "DELTA", "ECHO"]

var _level: Node3D
var _placed := false
var _bleed_left := BLEED_INTERVAL


func setup(level: Node3D) -> void:
	_level = level


## Placement waits for the first physics frame: the ground raycast needs the
## level's colliders, which are not in the physics world yet during _ready.
func _physics_process(delta: float) -> void:
	if not _placed:
		_placed = true
		_place_posts()
		return
	if not GameState.match_live or GameState.match_over:
		return
	_bleed_left -= delta
	if _bleed_left <= 0.0:
		_bleed_left += BLEED_INTERVAL
		_bleed()


func _place_posts() -> void:
	var c := GameState.map_center
	var ext := GameState.map_extents
	# Lay the line along the longer axis, which on the two-team maps runs between
	# the two ends the sides spawn at.
	var along_x: bool = ext.x >= ext.y
	var half: float = ext.x if along_x else ext.y
	var name_i := 0
	# Two home posts, one per side, pre-owned.
	_spawn_post(c, along_x, -HOME_FRAC * half, GameState.Team.REPUBLIC, "REPUBLIC HQ")
	_spawn_post(c, along_x, HOME_FRAC * half, GameState.Team.CIS, "SEPARATIST HQ")
	# Neutral posts down the middle. Small maps get fewer, so they do not overlap.
	var fracs: Array = NEUTRAL_FRACS if half >= 45.0 else [0.0]
	for f in fracs:
		_spawn_post(c, along_x, float(f) * half, -1, NAMES[name_i % NAMES.size()])
		name_i += 1


func _spawn_post(center: Vector3, along_x: bool, offset: float, owner: int, label: String) -> void:
	var x := center.x + (offset if along_x else 0.0)
	var z := center.z + (0.0 if along_x else offset)
	var y := _ground(x, z)
	var post := POST_SCENE.new()
	_level.add_child(post)
	post.setup(Vector3(x, y, z), owner, label)


## Ground height at a point: the level's own analytic surface when it has one
## (the terrain maps), else a downward ray, else zero.
func _ground(x: float, z: float) -> float:
	if _level != null and _level.has_method("height_at"):
		return _level.height_at(x, z)
	var from := Vector3(x, 120.0, z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 200.0)
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return (hit["position"] as Vector3).y if not hit.is_empty() else 0.0


## Drain the reinforcements of every side that holds fewer posts than the leader,
## in proportion to the deficit — hold them all and the enemy bleeds fast, hold a
## bare majority and it is a trickle.
func _bleed() -> void:
	var most := 0
	for t in GameState.active_teams():
		most = maxi(most, GameState.posts_held(t))
	for t in GameState.active_teams():
		var deficit := most - GameState.posts_held(t)
		if deficit > 0:
			GameState.conquest_bleed(t, deficit * BLEED_PER_POST)
