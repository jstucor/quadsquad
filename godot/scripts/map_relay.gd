extends "res://scripts/arena.gd"
## "Relay" — a wide 64 m plain with deliberately sparse, LOW cover. Sight lines
## are long and there is nothing tall to hide behind, so this is the map where a
## scope earns its price and crossing open ground is a decision rather than a
## walk. Teams spawn diagonally opposite.

func _configure() -> void:
	size = 64.0
	floor_color = Color(0.21, 0.20, 0.17)
	cover_color = Color(0.27, 0.26, 0.22)
	republic_spawns = [Vector3(-26, 0, -22), Vector3(-22, 0, -26), Vector3(-28, 0, -14)]
	cis_spawns = [Vector3(26, 0, 22), Vector3(22, 0, 26), Vector3(28, 0, 14)]
	cover_boxes = [
		# Two relay masts: the only tall things on the map, and the only places
		# worth holding.
		{"pos": Vector3(-9, 0, 9), "size": Vector3(3.0, 5.0, 3.0)},
		{"pos": Vector3(9, 0, -9), "size": Vector3(3.0, 5.0, 3.0)},
		# Everything else is waist-high: it breaks a sight line, it does not end one.
		{"pos": Vector3(0, 0, 0), "size": Vector3(8.0, 1.3, 1.6)},
		{"pos": Vector3(-16, 0, 2), "size": Vector3(1.6, 1.3, 7.0)},
		{"pos": Vector3(16, 0, -2), "size": Vector3(1.6, 1.3, 7.0)},
		{"pos": Vector3(-4, 0, -17), "size": Vector3(6.0, 1.3, 1.6)},
		{"pos": Vector3(4, 0, 17), "size": Vector3(6.0, 1.3, 1.6)},
		{"pos": Vector3(-20, 0, 20), "size": Vector3(2.2, 1.8, 2.2)},
		{"pos": Vector3(20, 0, -20), "size": Vector3(2.2, 1.8, 2.2)},
		{"pos": Vector3(-14, 0, -12), "size": Vector3(1.8, 1.5, 1.8)},
		{"pos": Vector3(14, 0, 12), "size": Vector3(1.8, 1.5, 1.8)},
		{"pos": Vector3(24, 0, 24), "size": Vector3(2.0, 1.6, 2.0)},
		{"pos": Vector3(-24, 0, -24), "size": Vector3(2.0, 1.6, 2.0)},
	]
