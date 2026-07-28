extends Node3D
## Renders every generated world from a few vantage points, which is the only way
## to judge one: a procedural map is different every run, so the question is not
## "is this layout right" but "does this WORLD read".
##
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/planet_look.tscn
##
## Three shots each: a high wide, an eye-level from a real spawn (the view that
## decides whether a map is playable), and a mid-height three-quarter.
const LEVEL := preload("res://scenes/levels/planet.tscn")

func _ready() -> void:
	var cam := Camera3D.new(); cam.fov = 72.0; cam.far = 2000.0
	add_child(cam); cam.current = true
	for planet in PlanetMap.PLANET_NAMES.size():
		GameState.planet = planet
		GameState.planet_seed = 1234 + planet * 77
		var level: Node3D = LEVEL.instantiate()
		add_child(level)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var tag := str(PlanetMap.PLANET_NAMES[planet]).to_lower()
		var half: float = level.size * 0.5
		# High wide, looking across the whole map into the backdrop.
		cam.global_position = Vector3(-half * 0.62, half * 0.62, -half * 0.62)
		cam.look_at(Vector3(half * 0.10, 12, half * 0.10), Vector3.UP)
		await _frames(6); await _grab(tag + "_wide")
		# Eye level on a real spawn: what a player actually sees on the drop.
		var spawn: Vector3 = level.republic_spawns[1]
		cam.global_position = spawn + Vector3(0, 1.7, 0)
		cam.look_at(Vector3(0, 14, 0), Vector3.UP)
		await _frames(4); await _grab(tag + "_eye")
		# Mid-height three-quarter through the structures.
		cam.global_position = Vector3(half * 0.30, 26.0, half * 0.34)
		cam.look_at(Vector3(-half * 0.15, 8.0, -half * 0.15), Vector3.UP)
		await _frames(4); await _grab(tag + "_mid")
		remove_child(level); level.queue_free()
		await _frames(2)
	get_tree().quit()

func _grab(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://planet_%s.png" % tag)
	print("wrote %s" % tag)

func _frames(n: int) -> void:
	for _i in n: await get_tree().process_frame
