extends "res://scripts/arena.gd"
## "Crossfire" — a symmetric 50 m arena, teams spawn North (Republic) and South
## (CIS), with a central bunker cluster, mid-field flank cover, and low forward
## cover near each base.

func _configure() -> void:
	size = 50.0
	floor_color = Color(0.16, 0.18, 0.22)
	republic_spawns = [Vector3(-7, 0, -20), Vector3(7, 0, -20)]
	cis_spawns = [Vector3(-7, 0, 20), Vector3(7, 0, 20)]
	cover_boxes = [
		{"pos": Vector3(0, 0, 0), "size": Vector3(3.0, 2.2, 3.0)},
		{"pos": Vector3(-5, 0, 3), "size": Vector3(1.6, 1.6, 1.6)},
		{"pos": Vector3(5, 0, -3), "size": Vector3(1.6, 1.6, 1.6)},
		{"pos": Vector3(-14, 0, 0), "size": Vector3(2.0, 2.4, 6.0)},
		{"pos": Vector3(14, 0, 0), "size": Vector3(2.0, 2.4, 6.0)},
		{"pos": Vector3(-6, 0, -10), "size": Vector3(1.4, 1.4, 1.4)},
		{"pos": Vector3(6, 0, -10), "size": Vector3(1.4, 1.4, 1.4)},
		{"pos": Vector3(-6, 0, 10), "size": Vector3(1.4, 1.4, 1.4)},
		{"pos": Vector3(6, 0, 10), "size": Vector3(1.4, 1.4, 1.4)},
		{"pos": Vector3(0, 0, -14), "size": Vector3(4.0, 1.2, 1.2)},
		{"pos": Vector3(0, 0, 14), "size": Vector3(4.0, 1.2, 1.2)},
	]
