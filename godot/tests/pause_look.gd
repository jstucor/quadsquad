extends Node3D
## WINDOWED. The in-match pause screen, and the confirm in front of leaving.
##
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/pause_look.tscn
##
## Both states, because the second is entirely new text and the first has just
## grown a row. What a picture answers here and a headless test cannot: whether
## QUIT TO MENU reads as the bottom of a list rather than as another setting,
## and whether the confirm says enough to be answered without being a wall.
##
## Shot over a REAL match rather than a backdrop — this screen is transparent
## over the game and the whole question is whether it stays readable there.

const MAIN := preload("res://scenes/main.tscn")
const OVERLAY := preload("res://scripts/settings_overlay.gd")


func _ready() -> void:
	GameState.reset_match()
	Quality.governor_enabled = false
	GameState.human_players = 1
	GameState.team_size = 3
	GameState.map_index = 0
	GameState.mode = GameState.Mode.DEATHMATCH
	var main: Node = MAIN.instantiate()
	add_child(main)
	await get_tree().create_timer(1.5).timeout
	for p in _players(main):
		if not p.is_alive():
			p._respawn()
	# WAIT FOR THE MATCH TO BE LIVE. The overlay closes itself while it is not
	# (`_process` — dying, the map, or a match that has not been called on), which
	# is correct behaviour and meant an earlier version of this test photographed
	# an empty screen during the GET READY countdown and looked like a broken
	# overlay.
	while not GameState.match_live:
		await get_tree().process_frame

	var overlay := _find_overlay(main)
	if overlay == null:
		print("no overlay found")
		get_tree().quit(1)
		return
	overlay._show()
	# ON THE QUIT ROW, because a screenshot of a list is a screenshot of whatever
	# the caret is on and this is the row that is new.
	for i in overlay._rows.size():
		if overlay._rows[i]["kind"] == OVERLAY.Kind.QUIT:
			overlay._row = i
	overlay._render()
	await _grab("pause_menu")

	overlay._activate()          # into the confirm
	await _grab("pause_confirm")
	print("done")
	get_tree().quit()


func _grab(tag: String) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://%s.png" % tag)
	print("  user://%s.png" % tag)


func _players(n: Node) -> Array:
	var out: Array = []
	for c in n.find_children("*", "CharacterBody3D", true, false):
		if c is Player:
			out.append(c)
	return out


func _find_overlay(n: Node) -> Node:
	for c in n.find_children("*", "Control", true, false):
		if c.get_script() == OVERLAY:
			return c
	return null
