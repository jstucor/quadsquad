extends "res://scripts/arena.gd"
## "Foundry" — a tighter 46 m arena, teams spawn West (Republic) and East (CIS)
## across a central line of tall divider blocks with lane gaps, plus scattered
## crate cover on the flanks.

func _configure() -> void:
	size = 46.0
	floor_color = Color(0.2, 0.17, 0.16)
	republic_spawns = [Vector3(-19, 0, -5), Vector3(-19, 0, 5)]
	cis_spawns = [Vector3(19, 0, -5), Vector3(19, 0, 5)]
	cover_boxes = [
		{"pos": Vector3(0, 0, -14), "size": Vector3(2.5, 3.0, 8.0)},
		{"pos": Vector3(0, 0, 14), "size": Vector3(2.5, 3.0, 8.0)},
		{"pos": Vector3(0, 0, 0), "size": Vector3(2.5, 2.4, 4.0)},
		{"pos": Vector3(-9, 0, -8), "size": Vector3(1.6, 1.6, 1.6)},
		{"pos": Vector3(9, 0, 8), "size": Vector3(1.6, 1.6, 1.6)},
		{"pos": Vector3(-9, 0, 8), "size": Vector3(1.6, 1.6, 1.6)},
		{"pos": Vector3(9, 0, -8), "size": Vector3(1.6, 1.6, 1.6)},
		{"pos": Vector3(-10, 0, 0), "size": Vector3(1.4, 2.0, 1.4)},
		{"pos": Vector3(10, 0, 0), "size": Vector3(1.4, 2.0, 1.4)},
	]
