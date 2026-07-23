extends Node

## Renders the buy screen in its three states — selector on SPAWN, selector on a
## category, and a category OPEN — which is the whole thing a screenshot can
## judge and a headless test cannot: whether the three read differently.
##
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/buy_look.tscn

const MAIN := preload("res://scenes/main.tscn")


func _ready() -> void:
	GameState.human_players = 1
	GameState.mode = GameState.Mode.DEATHMATCH
	GameState.map_index = 0
	var main: Node = MAIN.instantiate()
	add_child(main)
	# The map, the viewport and the HUD all have to exist before the buy screen
	# is worth looking at.
	await _frames(20)

	var player: Player = _find_player(main)
	if player == null:
		print("no player found")
		get_tree().quit(1)
		return

	# Cursor over the spawn box (its start): reticle bottom, spawn highlighted.
	player.buy_cursor = Vector2(0.5, 0.98)
	player.buy_inside = false
	await _frames(4)
	await _grab("buy_spawn")

	# Sweep the cursor up over a category box: reticle on it, box highlighted.
	player.buy_cursor = Vector2(0.75, 0.18)
	await _frames(4)
	await _grab("buy_selected")

	# Open whatever the cursor resolved to.
	player.buy_inside = true
	player.buy_row = player.pending.first_row_in(player.buy_box)
	player.buy_changed.emit(player.buy_row)
	await _frames(4)
	await _grab("buy_open")
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
