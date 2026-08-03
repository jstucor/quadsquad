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

	# Found by CAPTION, never by position in the row. This test used to index the
	# list — [3] was TIME TO KILL, [7] was VICTORY — and then PLANET and TIME OF
	# DAY were added to the top row, which silently shifted every index past two:
	# it drove the TEAMS dropdown believing it was VICTORY and asked for item 4 of
	# four. Same trap, and the same answer, as the AI presets naming their gun by
	# class rather than by catalogue index.
	var mode_dd := _dropdown_named(menu, "GAME MODE")
	var universe_dd := _dropdown_named(menu, "UNIVERSE")
	var ttk_dd := _dropdown_named(menu, "TIME TO KILL")
	var teams_dd := _dropdown_named(menu, "TEAMS")
	var victory_dd := _dropdown_named(menu, "VICTORY")

	# UNIVERSE and TIME TO KILL: both rewrite what the match is made of, so both
	# get picked here rather than only rendered.
	universe_dd.select(1)
	universe_dd.item_selected.emit(1)
	await _frames(2)
	print("picked 'HALO' -> universe %d, sides %s" % [
		GameState.universe, str(GameState.team_names)])
	ttk_dd.select(GameState.Ttk.REALISTIC)
	ttk_dd.item_selected.emit(GameState.Ttk.REALISTIC)
	await _frames(2)
	print("picked 'REALISTIC' -> health x%.2f" % Loadout.ttk_health)
	await _grab("menu_halo")
	universe_dd.select(0)
	universe_dd.item_selected.emit(0)
	ttk_dd.select(GameState.Ttk.MEDIUM)
	ttk_dd.item_selected.emit(GameState.Ttk.MEDIUM)
	await _frames(2)

	teams_dd.select(1)
	teams_dd.item_selected.emit(1)
	await _frames(2)
	print("picked '3 TEAMS' -> team_count %d, free_for_all %s" % [
		GameState.team_count, GameState.free_for_all])

	# VICTORY writes the mode's threshold: 100 KILLS in deathmatch. The mode is
	# picked through its own dropdown rather than written onto GameState, because
	# VICTORY's choices and unit come FROM the mode — poking the field leaves the
	# previous mode's items sitting in the list.
	mode_dd.select(GameState.Mode.DEATHMATCH)
	mode_dd.item_selected.emit(GameState.Mode.DEATHMATCH)
	await _frames(2)
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


## A dropdown is an OptionButton under a VBoxContainer whose first child is the
## caption Label (`Menu._dropdown` builds exactly that), so the caption is the
## stable name for one and its position in the grid is not.
func _dropdown_named(n: Node, caption: String) -> OptionButton:
	for d in _find_dropdowns(n):
		var cell := d.get_parent()
		if cell == null:
			continue
		for c in cell.get_children():
			if c is Label and (c as Label).text == caption:
				return d
	assert(false, "no dropdown captioned '%s'" % caption)
	return null


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
