extends "res://scripts/arena.gd"
## "Citadel" — a 54 m square built around one tall central keep with four corner
## towers. Nothing shoots across the middle, so the fight is a rotation: the keep
## splits the map into four quadrants and the towers are the corners you fight
## for on the way round it.

func _configure() -> void:
	size = 54.0
	floor_color = Color(0.19, 0.17, 0.20)
	cover_color = Color(0.26, 0.24, 0.28)
	wall_color = Color(0.22, 0.20, 0.24)
	republic_spawns = [Vector3(-20, 0, -20), Vector3(-20, 0, -12), Vector3(-12, 0, -20)]
	cis_spawns = [Vector3(20, 0, 20), Vector3(20, 0, 12), Vector3(12, 0, 20)]
	cover_boxes = [
		# The keep: tall enough that nothing shoots over it.
		{"pos": Vector3(0, 0, 0), "size": Vector3(11.0, 6.0, 11.0)},
		# Buttresses off each face, so the rotation around it is not a clean circle.
		{"pos": Vector3(0, 0, -8.5), "size": Vector3(4.0, 2.6, 3.0)},
		{"pos": Vector3(0, 0, 8.5), "size": Vector3(4.0, 2.6, 3.0)},
		{"pos": Vector3(-8.5, 0, 0), "size": Vector3(3.0, 2.6, 4.0)},
		{"pos": Vector3(8.5, 0, 0), "size": Vector3(3.0, 2.6, 4.0)},
		# Corner towers.
		{"pos": Vector3(-18, 0, 18), "size": Vector3(4.5, 4.5, 4.5)},
		{"pos": Vector3(18, 0, -18), "size": Vector3(4.5, 4.5, 4.5)},
		{"pos": Vector3(-18, 0, -18), "size": Vector3(3.5, 3.5, 3.5)},
		{"pos": Vector3(18, 0, 18), "size": Vector3(3.5, 3.5, 3.5)},
		# Low cover on the approaches between keep and towers.
		{"pos": Vector3(-11, 0, 11), "size": Vector3(1.6, 1.4, 1.6)},
		{"pos": Vector3(11, 0, -11), "size": Vector3(1.6, 1.4, 1.6)},
		{"pos": Vector3(-11, 0, -11), "size": Vector3(1.6, 1.4, 1.6)},
		{"pos": Vector3(11, 0, 11), "size": Vector3(1.6, 1.4, 1.6)},
	]
