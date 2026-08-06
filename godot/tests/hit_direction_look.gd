extends Node3D
## WINDOWED. The hit-direction wedges, over a real match.
##
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/hit_direction_look.tscn
##
## The bearing maths has its own headless test; what a picture answers is whether
## the thing is READABLE at the moment it matters — over a bright sky and dark
## ground at once, next to a crosshair it must not touch, at a radius that is
## outside the reticle and inside the corners where the minimap and the health
## bar already live. None of that has a number.
##
## Shot with fire coming from four directions at once, which is the busiest the
## widget is allowed to get (`MAX_MARKS`) and therefore the only interesting case.

const MAIN := preload("res://scenes/main.tscn")
const MARKS := preload("res://scripts/hit_direction.gd")


func _ready() -> void:
	GameState.reset_match()
	Quality.governor_enabled = false
	GameState.human_players = 1
	GameState.team_size = 3
	GameState.map_index = 0
	GameState.mode = GameState.Mode.DEATHMATCH
	var main: Node = MAIN.instantiate()
	add_child(main)
	await get_tree().create_timer(1.5).timeout
	for p in _players(main):
		if not p.is_alive():
			p._respawn()
	while not GameState.match_live:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout

	var player := _players(main)[0] as Player
	var marks := _find_marks(main)
	if marks == null:
		print("no hit-direction overlay found")
		get_tree().quit(1)
		return

	# ONE, first: the ordinary case, and the one a player sees most.
	marks._on_hit_from(player.global_position
		+ Vector3(9, 0, -4).rotated(Vector3.UP, player.rotation.y))
	await _grab("hitdir_one")

	# ...then a crossfire, which is the busiest it may get.
	for a: float in [2.2, 3.9, 5.4]:
		marks._on_hit_from(player.global_position
			+ Vector3(sin(a), 0, cos(a)) * 12.0)
	await _grab("hitdir_many")
	print("done")
	get_tree().quit()


func _grab(tag: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://%s.png" % tag)
	print("  user://%s.png" % tag)


func _players(n: Node) -> Array:
	var out: Array = []
	for c in n.find_children("*", "CharacterBody3D", true, false):
		if c is Player:
			out.append(c)
	return out


func _find_marks(n: Node) -> Node:
	for c in n.find_children("*", "Control", true, false):
		if c.get_script() == MARKS:
			return c
	return null
