extends Control
## Map-select menu — the game's main scene. Lists GameState.MAPS, plus a
## rotation entry that plays the whole roster in order (what the game used to do
## unconditionally) and a quit entry.
##
## Driven by the built-in ui_* actions, so it works from the keyboard AND from
## any of the four joypads without per-device polling: those actions are bound
## to device -1 (all pads), unlike the in-match kb_*/joypad input which has to
## stay per-player. Buttons find their up/down neighbours geometrically, so no
## explicit focus wiring.

const GAME_SCENE := "res://scenes/main.tscn"

const BG_COLOR := Color(0.06, 0.07, 0.09)
const ACCENT := Color(0.45, 0.72, 1.0)
const DIM := Color(0.62, 0.66, 0.72)


func _ready() -> void:
	# A match captures the pointer; coming back here it has to be free again.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.add_theme_constant_override("separation", 10)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(column)

	column.add_child(_label("QUADSQUAD", 52, ACCENT))
	column.add_child(_label("SELECT MAP", 22, DIM))
	column.add_child(_spacer(14))
	_build_setup_rows(column)
	column.add_child(_spacer(14))

	var first: Button = null
	for i in GameState.MAPS.size():
		var map: Dictionary = GameState.MAPS[i]
		var button := _row(column, map["name"], map["blurb"])
		button.pressed.connect(_start.bind(i, false))
		if first == null:
			first = button

	column.add_child(_spacer(14))
	_row(column, "MAP ROTATION", "Play every map in order").pressed.connect(
		_start.bind(0, true))
	_row(column, "QUIT", "").pressed.connect(func() -> void: get_tree().quit())

	column.add_child(_spacer(20))
	column.add_child(_label(
		"Arrows / left stick to move    Enter / A to select or change    P1 is keyboard + mouse",
		15, Color(0.42, 0.46, 0.52)))

	if first:
		first.grab_focus()


## Match setup: how many humans are on the couch, how big each team is, and how
## good the AI filling the empty slots are. Each row cycles on press, and the
## summary underneath spells out what you'll actually get, since "2 humans at
## team size 3" is not obviously a 3v3.
func _build_setup_rows(column: VBoxContainer) -> void:
	var summary := _label("", 16, Color(0.68, 0.72, 0.78))

	var players_button := _row(column, "", "Humans at the couch")
	var size_button := _row(column, "", "Headcount per team, AI fill the rest")
	var skill_button := _row(column, "", "How good the AI teammates are")

	var refresh := func() -> void:
		players_button.text = "PLAYERS  %d" % GameState.human_players
		size_button.text = "TEAM SIZE  %d" % GameState.team_size
		skill_button.text = "AI SKILL  %s" % Loadout.SQUAD_SKILLS[GameState.ai_skill]["name"]
		var ai_total: int = GameState.ai_needed(GameState.Team.REPUBLIC) \
			+ GameState.ai_needed(GameState.Team.CIS)
		summary.text = "%d human%s + %d AI     %d v %d" % [
			GameState.human_players, "" if GameState.human_players == 1 else "s",
			ai_total, GameState.team_size, GameState.team_size]

	players_button.pressed.connect(func() -> void:
		GameState.human_players = wrapi(GameState.human_players + 1,
			GameState.MIN_HUMANS, GameState.MAX_HUMANS + 1)
		# A team can never be smaller than the humans standing in it.
		GameState.team_size = maxi(GameState.team_size,
			GameState.humans_on_team(GameState.Team.REPUBLIC))
		refresh.call())
	size_button.pressed.connect(func() -> void:
		var floor_size: int = maxi(GameState.humans_on_team(GameState.Team.REPUBLIC), 1)
		GameState.team_size = wrapi(GameState.team_size + 1,
			floor_size, GameState.MAX_TEAM_SIZE + 1)
		refresh.call())
	skill_button.pressed.connect(func() -> void:
		GameState.ai_skill = wrapi(GameState.ai_skill + 1, 0, Loadout.SQUAD_SKILLS.size())
		refresh.call())

	column.add_child(summary)
	refresh.call()


func _start(index: int, rotate: bool) -> void:
	GameState.map_index = index
	GameState.rotate_maps = rotate
	get_tree().change_scene_to_file(GAME_SCENE)


## One entry: a fixed-width button with its blurb in a fixed-width column beside
## it, so every row is the same width and the whole list centres as one block.
func _row(column: VBoxContainer, text: String, blurb: String) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var button := _button(text)
	row.add_child(button)
	var label := _label(blurb, 17, DIM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.custom_minimum_size = Vector2(280, 0)
	row.add_child(label)
	column.add_child(row)
	return button


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 46)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", Color(0.88, 0.91, 0.95))
	b.add_theme_color_override("font_focus_color", ACCENT)
	b.add_theme_color_override("font_hover_color", ACCENT)
	# Hovering moves the focus too, so the highlighted entry is always the one
	# Enter/A will start — no split between "hovered" and "selected".
	b.mouse_entered.connect(b.grab_focus)
	return b


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c
