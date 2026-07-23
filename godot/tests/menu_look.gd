extends Node

## Renders the front menu to a PNG, and drives the settings dropdowns from code
## to prove they actually write GameState — the half a screenshot cannot show.
##
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/menu_look.tscn

const MENU := preload("res://scenes/menu.tscn")


func _ready() -> void:
	# The menu anchors itself FULL_RECT, which is zero if its parent is zero —
	# the first run of this test rendered the whole screen jammed into the top
	# left corner, which looked exactly like a broken layout.
	var root := get_node(".") as Control
	if root != null:
		root.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.size = get_viewport().get_visible_rect().size
	var menu: Control = MENU.instantiate()
	add_child(menu)
	await _frames(6)
	await _grab("menu")

	# The dropdowns, exercised: pick 3 TEAMS, then FREE FOR ALL, and check what
	# lands in GameState. `item_selected` is emitted by select() only when it is
	# emitted manually, so this drives the signal the way the popup does.
	var dropdowns := _find_dropdowns(menu)
	print("dropdowns found: %d" % dropdowns.size())
	for d in dropdowns:
		var items := PackedStringArray()
		for i in d.item_count:
			items.append(d.get_item_text(i))
		print("  %-14s -> %s" % [d.get_item_text(d.selected), str(items)])

	# Dropdown order matches the build: MAP, MODE, PLAYERS, TEAMS, TEAM SIZE,
	# VICTORY, AI SKILL, AIM ASSIST.
	var mode_dd: OptionButton = dropdowns[1]
	var teams_dd: OptionButton = dropdowns[3]
	var victory_dd: OptionButton = dropdowns[5]

	teams_dd.select(1)
	teams_dd.item_selected.emit(1)
	await _frames(2)
	print("picked '3 TEAMS' -> team_count %d, free_for_all %s" % [
		GameState.team_count, GameState.free_for_all])

	# VICTORY writes the mode's threshold: 100 KILLS in deathmatch.
	GameState.mode = GameState.Mode.DEATHMATCH
	victory_dd.select(4)             # [10, 25, 50, 75, 100] -> 100
	victory_dd.item_selected.emit(4)
	await _frames(2)
	print("picked '100 KILLS' -> score_limit %d" % GameState.score_limit())

	GameState.human_players = 4
	teams_dd.select(3)
	teams_dd.item_selected.emit(3)
	await _frames(2)
	print("picked 'FREE FOR ALL' -> free_for_all %s, teams %d" % [
		GameState.free_for_all, GameState.active_teams()])
	await _grab("menu_ffa")
	get_tree().quit()


func _find_dropdowns(n: Node) -> Array[OptionButton]:
	var out: Array[OptionButton] = []
	for c in n.get_children():
		if c is OptionButton:
			out.append(c)
		out.append_array(_find_dropdowns(c))
	return out


func _grab(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://%s.png" % tag)
	print("wrote %s" % ProjectSettings.globalize_path("user://%s.png" % tag))


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
