extends Node3D
## WINDOWED. THE GENERATED BASE, from the three places that differ.
##
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/outpost_look.tscn
##
## A generated map cannot be judged from one screenshot — that is on record for
## the planets and it is worse here, because this one is ROOFED: the wide shot
## every other map gets is a grey lid, and `map_look` can only ever photograph a
## corridor. What has to be looked at is the three things the generator makes
## that are not corridors, and it finds them by ASKING THE LEVEL where they came
## out this run rather than by guessing at coordinates:
##
##   the HALL     — is a massive crate stack cover you fight through, or a wall?
##   the TUNNEL   — standing in it, is the floor above actually blocking sight?
##   the RAMP     — can you see, from the deck, that there is a way down?
##
## Seeded so the same run is repeatable; change the seed to look at another base.

const OUTPOST := preload("res://scenes/levels/outpost.tscn")
const SEED := 4242
## The room pitch, for placing the camera relative to a cell. Read off the level
## rather than restated where it can be; this is only the fallback.
const CELL_GUESS := 12.0


func _ready() -> void:
	GameState.planet_seed = SEED
	GameState.reset_match()
	var level: Node3D = OUTPOST.instantiate()
	add_child(level)
	await _frames(8)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 75

	# THE HALL. From a doorway rather than the middle: what is being judged is
	# whether the stacks break the room up, and standing among them cannot show
	# that.
	var halls: Array = level._halls
	print("halls %s | sunk %d cells | cover boxes %d"
		% [str(halls), level._sunk.size(), level.cover_boxes.size()])
	if not halls.is_empty():
		var h: Rect2i = halls[0]
		# INSIDE it, standing in the first cell and looking at the last. The first
		# version stepped 11 m back from the hall's middle to get the whole room
		# in — which, for a hall against the outer wall, is a camera standing
		# outside the base photographing the roof.
		var near: Vector3 = level._cell_centre(h.position.x, h.position.y)
		var far: Vector3 = level._cell_centre(h.end.x - 1, h.end.y - 1)
		# Backed off along the hall's own axis and raised, so the stacks are in
		# front of the camera rather than around it — standing in the middle of a
		# freight stack photographs the inside of a crate.
		# FROM A CORNER OF THE HALL, looking across it. Down the long axis the
		# stacks line up behind each other and the shot is a corridor; from the
		# middle the camera is inside a crate. A corner is the only place in a
		# room this full that is reliably clear.
		var mid := (near + far) * 0.5
		var corner := mid + Vector3(-1.0, 0.0, -1.0) * (CELL_GUESS * 0.42)
		cam.global_position = corner + Vector3(0.0, 2.0, 0.0)
		cam.look_at(mid + Vector3(0.0, 1.2, 0.0), Vector3.UP)
		await _frames(6)
		await _grab("outpost_hall")

	# THE TUNNEL, from inside it, looking along the run.
	var sunk: Array = level._sunk.values()
	if not sunk.is_empty():
		var at: Vector2i = sunk[0]
		var last: Vector2i = sunk[sunk.size() - 1]
		var here: Vector3 = level._cell_centre(at.x, at.y) - Vector3(0, level.SUNK, 0)
		var there: Vector3 = level._cell_centre(last.x, last.y) - Vector3(0, level.SUNK, 0)
		cam.global_position = here + Vector3(0.0, 1.7, 0.0)
		if here.distance_to(there) > 1.0:
			cam.look_at(there + Vector3(0.0, 1.6, 0.0), Vector3.UP)
		await _frames(6)
		await _grab("outpost_tunnel")

		# ...and the mouth of it from up on the deck, which is the only view that
		# says a hole in the floor is a way down rather than a hazard.
		cam.global_position = here + Vector3(0.0, level.SUNK + 6.0, 12.0)
		cam.look_at(here + Vector3(0.0, 1.0, 0.0), Vector3.UP)
		await _frames(6)
		await _grab("outpost_ramp")
	print("outpost rendered: user://shots/outpost_*.png")
	get_tree().quit()


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _grab(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://shots")
	img.save_png("user://shots/%s.png" % name)
	print("wrote %s" % name)
