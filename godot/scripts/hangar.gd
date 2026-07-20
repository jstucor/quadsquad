extends Node3D
## Hangar level: registers its spawn markers with GameState so the game
## bootstrap (and future conquest logic) never hardcodes positions.

func _ready() -> void:
	# Existing markers (near +Z) are the Republic side.
	for marker in $SpawnPoints.get_children():
		if marker is Node3D:
			GameState.register_spawn_point(GameState.Team.REPUBLIC, marker)
	# Mirror a CIS side near -Z so the hangar works for team deathmatch.
	for x in [-6, -2, 2, 6]:
		var m := Marker3D.new()
		m.position = Vector3(x, 0, -14)
		m.rotation.y = PI  # face +Z, back toward the Republic side
		add_child(m)
		GameState.register_spawn_point(GameState.Team.CIS, m)
