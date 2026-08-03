extends Node3D

## THE MINIMAP, INCLUDING THE THING IT EXISTS FOR.
##
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/minimap_look.tscn
##
## Windowed. Shots land in user://.
##
## It renders the REAL widget against real map geometry, at both widget sizes
## (full screen and split screen), and it shoots the scan BEFORE and AFTER — a
## minimap that shows your own side is a nice-to-have, and the whole argument for
## it is what happens the moment somebody's dart lands. Judging the after shot
## without the before one tells you nothing: the question is not "can I see the
## diamonds", it is "did anything change enough to notice mid-fight".
##
## Enemies are placed both INSIDE and OUTSIDE the window on purpose, because the
## failure this catches is a contact drawn at the rim rather than culled, which
## reads as an enemy right on top of you.

const MINIMAP := preload("res://scripts/minimap.gd")
const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")

var _map: Control
var _fake: Array[Node3D] = []


func _ready() -> void:
	GameState.reset_match()
	GameState.match_live = true
	GameState.human_players = 1
	_build_level()
	GameState.scan_map_geometry(self)

	var layer := CanvasLayer.new()
	add_child(layer)
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.16, 0.17, 0.20)
	layer.add_child(backdrop)

	var me := _combatant(Vector3(0, 0, 0), 0, true)
	me.rotation.y = deg_to_rad(35.0)
	# Two of mine near me, four of theirs — two well inside the window and two
	# outside it, which is what proves the cull.
	_combatant(Vector3(-9, 0, -6), 0)
	_combatant(Vector3(7, 0, 11), 0)
	var seen := [
		_combatant(Vector3(14, 0, -18), 1),
		_combatant(Vector3(-22, 0, 9), 1),
		_combatant(Vector3(3, 0, -33), 1),
		_combatant(Vector3(70, 0, 40), 1),   # far outside: must not be drawn
	]

	for spec in [["full", 1], ["split", 4]]:
		GameState.human_players = spec[1]
		GameState.scanned.clear()
		await _shoot(layer, me, "%s_dark" % spec[0])
		# What a dart does: marks every enemy in its radius for the THROWER'S
		# TEAM, which is what puts them on all four of that side's minimaps.
		for e in seen:
			if e.global_position.length() < 45.0:
				GameState.mark_scanned(e, 0, 8.0)
		await _shoot(layer, me, "%s_scanned" % spec[0])
	get_tree().quit()


func _shoot(layer: CanvasLayer, me: Node3D, tag: String) -> void:
	if _map != null:
		layer.remove_child(_map)
		_map.queue_free()
	_map = MINIMAP.new()
	layer.add_child(_map)
	_map.setup(me, Color(0.95, 0.30, 0.30))
	# The widget sits in a 12x10 corner; shift it into the middle of the shot so
	# the screenshot is of the map and not of a mostly empty backdrop.
	_map.position = Vector2(440, 210)
	_map.queue_redraw()
	await _frames(4)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "user://minimap_%s.png" % tag
	img.save_png(path)
	print("wrote %s  (%d scanned)" % [ProjectSettings.globalize_path(path),
		GameState.scanned.size()])


## A stand-in combatant: the minimap only ever asks for `team`, `is_alive()` and
## a position, which is the same duck-typed contract everything that shoots uses.
func _combatant(at: Vector3, team: int, real := false) -> Node3D:
	var node: Node3D
	if real:
		node = PLAYER_SCENE.instantiate()
		node.player_index = 0
		add_child(node)
		node.team = team
		node.global_position = at
	else:
		node = Stand.new()
		node.team = team
		add_child(node)
		node.global_position = at
	GameState.register_combatant(node)
	_fake.append(node)
	return node


class Stand extends Node3D:
	var team := 0
	func is_alive() -> bool:
		return true


## Enough boxes for the minimap to have something to draw. Real colliders, so
## `scan_map_geometry` picks them up exactly as it does on a shipped map.
func _build_level() -> void:
	var slab := StaticBody3D.new()
	slab.collision_layer = 1
	var cs := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(200, 2, 200)
	cs.shape = floor_box
	cs.position = Vector3(0, -1, 0)
	slab.add_child(cs)
	add_child(slab)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260731
	for i in 26:
		var b := StaticBody3D.new()
		b.collision_layer = 1
		var c := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(rng.randf_range(2.0, 9.0), 3.0, rng.randf_range(2.0, 9.0))
		c.shape = box
		b.add_child(c)
		add_child(b)
		b.global_position = Vector3(rng.randf_range(-46, 46), 1.5, rng.randf_range(-46, 46))
		b.rotation.y = rng.randf_range(0.0, TAU)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
