extends "res://scripts/arena.gd"
## "Spillway" — a long, narrow channel: 30 m across and 76 m end to end, teams
## spawning at opposite ends. The length is the point. Sight lines run the whole
## map, so the staggered mid-channel blocks are the only way to cross, and the
## side alcoves are what a flanker uses to get past them.

func _configure() -> void:
	size = 30.0
	depth = 76.0
	floor_color = Color(0.15, 0.19, 0.21)
	cover_color = Color(0.21, 0.24, 0.26)
	republic_spawns = [Vector3(-8, 0, -32), Vector3(0, 0, -34), Vector3(8, 0, -32)]
	cis_spawns = [Vector3(-8, 0, 32), Vector3(0, 0, 34), Vector3(8, 0, 32)]
	cover_boxes = [
		# Staggered mid-channel blocks: no single line runs the full length.
		{"pos": Vector3(-6, 0, -8), "size": Vector3(6.0, 3.0, 2.2)},
		{"pos": Vector3(6, 0, 0), "size": Vector3(6.0, 3.0, 2.2)},
		{"pos": Vector3(-6, 0, 8), "size": Vector3(6.0, 3.0, 2.2)},
		# Side alcoves, the flanking route past those blocks.
		{"pos": Vector3(-12, 0, -18), "size": Vector3(3.0, 2.4, 5.0)},
		{"pos": Vector3(12, 0, -18), "size": Vector3(3.0, 2.4, 5.0)},
		{"pos": Vector3(-12, 0, 18), "size": Vector3(3.0, 2.4, 5.0)},
		{"pos": Vector3(12, 0, 18), "size": Vector3(3.0, 2.4, 5.0)},
		# Low cover to break the run out of each spawn.
		{"pos": Vector3(0, 0, -24), "size": Vector3(7.0, 1.2, 1.4)},
		{"pos": Vector3(0, 0, 24), "size": Vector3(7.0, 1.2, 1.4)},
		{"pos": Vector3(-10, 0, -28), "size": Vector3(1.6, 1.8, 1.6)},
		{"pos": Vector3(10, 0, 28), "size": Vector3(1.6, 1.8, 1.6)},
	]
