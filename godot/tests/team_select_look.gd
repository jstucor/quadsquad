extends Node
## Renders the team-select screen with a few players in mid-selection.
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/team_select_look.tscn
const TS := preload("res://scenes/team_select.tscn")

func _ready() -> void:
	GameState.free_for_all = false
	GameState.team_count = 3
	GameState.human_players = 4
	var ts: Control = TS.instantiate()
	add_child(ts)
	await _frames(4)
	# Force a mid-selection state: P1 locked on team 0, P2 locked on team 1,
	# P3 hovering team 2, P4 still hovering team 0.
	ts._players[0]["hover"] = 0; ts._players[0]["locked"] = true
	ts._players[1]["hover"] = 1; ts._players[1]["locked"] = true
	ts._players[2]["hover"] = 2; ts._players[2]["locked"] = false
	ts._players[3]["hover"] = 0; ts._players[3]["locked"] = false
	ts._started = true    # freeze polling so the forced state stays put
	ts.queue_redraw()
	await _frames(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://team_select.png")
	print("wrote team_select")
	get_tree().quit()

func _frames(n: int) -> void:
	for _i in n: await get_tree().process_frame
