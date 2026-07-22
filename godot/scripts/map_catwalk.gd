extends "res://scripts/arena.gd"
## "Catwalk" — a cramped 34 m box cut into corridors by full-height slabs. Every
## engagement is a corner at close range, which makes it the scattergun and
## dual-wield map: there is nowhere far enough away to want a scope.

func _configure() -> void:
	size = 34.0
	floor_color = Color(0.16, 0.16, 0.19)
	cover_color = Color(0.23, 0.23, 0.27)
	republic_spawns = [Vector3(-13, 0, -13), Vector3(-13, 0, 0), Vector3(-13, 0, 13)]
	cis_spawns = [Vector3(13, 0, 13), Vector3(13, 0, 0), Vector3(13, 0, -13)]
	cover_boxes = [
		# Full-height slabs, laid out so no corridor runs straight through.
		{"pos": Vector3(-6, 0, -10), "size": Vector3(1.4, 4.0, 9.0)},
		{"pos": Vector3(6, 0, 10), "size": Vector3(1.4, 4.0, 9.0)},
		{"pos": Vector3(-6, 0, 9), "size": Vector3(1.4, 4.0, 5.0)},
		{"pos": Vector3(6, 0, -9), "size": Vector3(1.4, 4.0, 5.0)},
		{"pos": Vector3(0, 0, -4), "size": Vector3(7.0, 4.0, 1.4)},
		{"pos": Vector3(0, 0, 4), "size": Vector3(7.0, 4.0, 1.4)},
		# Waist-high boxes in the pockets, for the fights that happen in them.
		{"pos": Vector3(0, 0, 0), "size": Vector3(1.6, 1.3, 1.6)},
		{"pos": Vector3(-11, 0, 6), "size": Vector3(1.5, 1.4, 1.5)},
		{"pos": Vector3(11, 0, -6), "size": Vector3(1.5, 1.4, 1.5)},
		{"pos": Vector3(-11, 0, -6), "size": Vector3(1.5, 1.4, 1.5)},
		{"pos": Vector3(11, 0, 6), "size": Vector3(1.5, 1.4, 1.5)},
	]
