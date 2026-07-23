extends Node3D

## Renders each map from a high vantage point to a PNG. Procedural maps fail in
## ways no headless check can see — fog that buries the layout, a palette that
## washes cover into the ground, props left floating — and this is the cheapest
## way to look at all of them at once.
##
## Windowed, because a renderer is the point:
##
##   godot --path godot --display-driver x11 --resolution 960x540 tests/map_look.tscn
##
## Edit ONLY to change which maps it shoots. Shots land in user://.

## Which entries of GameState.MAPS to render, by name. Empty means all of them.
const WANTED := ["KASHYYYK", "SENATE DISTRICT", "BONEYARD"]


func _ready() -> void:
	var cam := Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	cam.current = true

	for i in GameState.MAPS.size():
		var entry: Dictionary = GameState.MAPS[i]
		if not WANTED.is_empty() and not (entry["name"] in WANTED):
			continue
		var level: Node3D = entry["scene"].instantiate()
		add_child(level)
		# Two physics frames: the zone and anything else that places itself off a
		# raycast needs the colliders in the physics world first.
		await get_tree().physics_frame
		await get_tree().physics_frame
		var half: Vector2 = level.half_extents() if level.has_method("half_extents") \
			else Vector2(60, 60)
		var reach := maxf(half.x, half.y)
		# Looking in from a corner at a shallow angle: a straight top-down shot
		# hides every height, and height is what these maps are made of.
		cam.global_position = Vector3(-reach * 0.95, reach * 0.62, -reach * 0.95)
		cam.look_at(Vector3(0.0, reach * 0.05, 0.0), Vector3.UP)
		await _frames(6)
		await _grab(str(entry["name"]).to_lower().replace(" ", "_") + "_wide")
		# ...and one from the deck, at eye height on a REAL spawn — which is the
		# view that decides whether a map is playable, and the only point on the
		# map guaranteed not to be inside a building. Picking a spot by fraction
		# of the extents put the camera inside a wreck and rendered a black
		# screen that read exactly like a lighting fault.
		var spawn := Vector3(-reach * 0.42, 1.6, -reach * 0.40)
		if "republic_spawns" in level and not level.republic_spawns.is_empty():
			spawn = level.republic_spawns[0] + Vector3(0.0, 1.6, 0.0)
		cam.global_position = spawn
		cam.look_at(Vector3(0.0, 3.0, 0.0), Vector3.UP)
		await _frames(6)
		await _grab(str(entry["name"]).to_lower().replace(" ", "_") + "_eye")
		level.queue_free()
		await _frames(2)

	get_tree().quit()


func _grab(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "user://map_%s.png" % tag
	img.save_png(path)
	print("wrote %s" % ProjectSettings.globalize_path(path))


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
