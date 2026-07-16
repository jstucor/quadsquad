extends Node3D
## Hangar level: registers its spawn markers with GameState so the game
## bootstrap (and future conquest logic) never hardcodes positions.

func _ready() -> void:
	for marker in $SpawnPoints.get_children():
		if marker is Node3D:
			GameState.register_spawn_point(GameState.Team.REPUBLIC, marker)
