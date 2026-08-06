extends Node

## Renders the CHARACTER SELECT screen in its three states — cursor on SPAWN,
## cursor on the CLASS box, and that box OPEN — which is the thing a screenshot
## can judge and a headless test cannot: whether it reads as the same screen as
## the buy screen (tests/buy_look.tscn renders the other one to compare against).
##
## Run it in CONQUEST so the deploy-post box is on screen too, which is the one
## box the buy screen does not have.
##
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/select_look.tscn

const MAIN := preload("res://scenes/main.tscn")


func _ready() -> void:
	# SHOOT THE SPLIT TOO. The metrics are picked off the player count
	# (BoxScreen.metrics) precisely because the full-size layout runs off both
	# edges of a quarter-screen viewport — so a screen judged only at one player
	# is a screen judged in the case that cannot fail.
	#   QS_VIEWS=4 godot --path godot ... tests/select_look.tscn
	GameState.human_players = maxi(1, int(OS.get_environment("QS_VIEWS")))
	GameState.mode = GameState.Mode.CONQUEST
	GameState.class_mode = GameState.ClassMode.FACTION
	GameState.map_index = 0
	# ONE SIDE ON ITS FACTION COLOUR AND ONE ON A CHOSEN ONE, because those are
	# two different code paths into `team_colors` (`refresh_sides` folds the
	# faction's own chip and the menu's tint into the same array) and only a
	# picture proves the SCREEN reads the folded answer rather than the seat.
	GameState.team_tint = [0, _purple_tint(), 0, 0]
	GameState.refresh_sides()
	var main: Node = MAIN.instantiate()
	add_child(main)
	# The map lays its command posts on the first physics frame, and the spawn
	# screen has nothing to say until they exist.
	await _frames(30)

	var player: Player = _find_player(main)
	if player == null:
		print("no player found")
		get_tree().quit(1)
		return

	player.buy_cursor = Vector2(0.5, 0.98)
	player.buy_inside = false
	await _frames(4)
	await _grab("select_spawn")

	player.buy_cursor = Vector2(0.2, 0.2)
	await _frames(4)
	await _grab("select_class")

	player.buy_inside = true
	player.buy_changed.emit(player.buy_row)
	await _frames(4)
	await _grab("select_open")
	get_tree().quit()


func _find_player(n: Node) -> Player:
	for c in n.get_children():
		if c is Player:
			return c
		var found := _find_player(c)
		if found != null:
			return found
	return null


func _grab(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://%s.png" % tag)
	print("wrote %s" % ProjectSettings.globalize_path("user://%s.png" % tag))


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


## The first tint that is not a side's own colour, so the shot is unambiguous.
func _purple_tint() -> int:
	for i in range(1, Loadout.TEAM_TINTS.size()):
		if str(Loadout.TEAM_TINTS[i]["name"]) == "PURPLE":
			return i
	return 1
