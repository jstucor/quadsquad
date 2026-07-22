extends Control
## Front screen. Two big picker BOXES side by side — the map on the left, the
## game mode on the right — over a row of match settings and a START button.
##
## The old screen listed every map as its own row, which stopped scaling the
## moment the roster grew: at nine maps the column ran off both ends of the
## viewport. A picker box shows one choice at a time and cycles on click, so the
## screen stays a fixed size however many maps exist.
##
## Driven by the built-in ui_* actions, so it works from the keyboard AND from
## any of the four joypads without per-device polling: those actions are bound
## to device -1 (all pads), unlike the in-match kb_*/joypad input which has to
## stay per-player. Buttons find their neighbours geometrically, so no explicit
## focus wiring.

const GAME_SCENE := "res://scenes/main.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"

const BG_COLOR := Color(0.06, 0.07, 0.09)
const ACCENT := Color(0.45, 0.72, 1.0)
const DIM := Color(0.62, 0.66, 0.72)
const FAINT := Color(0.42, 0.46, 0.52)
const PANEL := Color(0.10, 0.12, 0.15, 0.9)
const PANEL_EDGE := Color(0.24, 0.30, 0.38)
const BOX := Vector2(400, 200)

var _summary: Label
var _refresh_all: Callable


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
	column.add_theme_constant_override("separation", 12)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(column)

	column.add_child(_label("QUADSQUAD", 52, ACCENT))

	# The two picker boxes, side by side.
	var boxes := HBoxContainer.new()
	boxes.add_theme_constant_override("separation", 24)
	boxes.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(boxes)
	var map_box := _picker(boxes, "MAP")
	var mode_box := _picker(boxes, "GAME MODE")

	var settings := HBoxContainer.new()
	settings.add_theme_constant_override("separation", 10)
	settings.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(settings)
	var players_btn := _chip(settings, "")
	var teams_btn := _chip(settings, "")
	var size_btn := _chip(settings, "")
	var skill_btn := _chip(settings, "")
	var assist_btn := _chip(settings, "")

	_summary = _label("", 17, Color(0.68, 0.72, 0.78))
	column.add_child(_summary)

	var start := _wide_button("START MATCH", 28)
	start.pressed.connect(_start.bind(false))
	column.add_child(start)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	_chip(row, "MAP ROTATION").pressed.connect(_start.bind(true))
	_chip(row, "CONTROLS").pressed.connect(func() -> void:
		get_tree().change_scene_to_file(SETTINGS_SCENE))
	_chip(row, "QUIT").pressed.connect(func() -> void: get_tree().quit())

	column.add_child(_label(
		"Arrows / left stick to move    Enter / A to select or change    P1 is keyboard + mouse",
		15, FAINT))

	# One refresh closure that everything calls, so no control has to know what
	# any other one displays.
	_refresh_all = func() -> void:
		var map: Dictionary = GameState.MAPS[GameState.map_index]
		_set_picker(map_box, map["name"], map["blurb"],
			"%d of %d" % [GameState.map_index + 1, GameState.MAPS.size()])
		_set_picker(mode_box, GameState.MODE_NAMES[GameState.mode],
			GameState.MODE_BLURBS[GameState.mode] % (
				[GameState.score_limit()] if GameState.mode == GameState.Mode.DEATHMATCH
				else [30, GameState.score_limit()]),
			"%d of %d" % [GameState.mode + 1, GameState.MODE_NAMES.size()])
		players_btn.text = "PLAYERS  %d" % GameState.human_players
		teams_btn.text = "TEAMS  %s" % ("FREE FOR ALL" if GameState.free_for_all
			else str(GameState.team_count))
		size_btn.text = "TEAM SIZE  %s" % ("1" if GameState.free_for_all
			else str(GameState.team_size))
		skill_btn.text = "AI SKILL  %s" % Loadout.SQUAD_SKILLS[GameState.ai_skill]["name"]
		assist_btn.text = "AIM ASSIST  %s" % GameState.AIM_ASSIST_NAMES[GameState.aim_assist]
		_summary.text = _describe()

	map_box.pressed.connect(func() -> void:
		GameState.map_index = wrapi(GameState.map_index + 1, 0, GameState.MAPS.size())
		_refresh_all.call())
	mode_box.pressed.connect(func() -> void:
		GameState.mode = wrapi(GameState.mode + 1, 0, GameState.MODE_NAMES.size())
		_refresh_all.call())
	players_btn.pressed.connect(func() -> void:
		GameState.human_players = wrapi(GameState.human_players + 1,
			GameState.MIN_HUMANS, GameState.MAX_HUMANS + 1)
		_fix_setup()
		_refresh_all.call())
	teams_btn.pressed.connect(_cycle_teams)
	size_btn.pressed.connect(func() -> void:
		if GameState.free_for_all:
			return  # every side is one player; there is no size to set
		GameState.team_size = wrapi(GameState.team_size + 1,
			_smallest_team_size(), GameState.MAX_TEAM_SIZE + 1)
		_refresh_all.call())
	skill_btn.pressed.connect(func() -> void:
		GameState.ai_skill = wrapi(GameState.ai_skill + 1, 0, Loadout.SQUAD_SKILLS.size())
		_refresh_all.call())
	assist_btn.pressed.connect(func() -> void:
		GameState.aim_assist = wrapi(GameState.aim_assist + 1, 0,
			GameState.AIM_ASSIST_NAMES.size())
		_refresh_all.call())

	_fix_setup()
	_refresh_all.call()
	map_box.grab_focus()


## TEAMS walks 2, 3, 4 and then FREE FOR ALL. The count is capped by how many
## humans are at the couch — three sides with two people would leave one empty —
## and free-for-all needs at least two of you to fight over.
func _cycle_teams() -> void:
	var ceiling := mini(GameState.MAX_TEAMS, maxi(GameState.human_players, 2))
	if GameState.free_for_all:
		GameState.free_for_all = false
		GameState.team_count = 2
	elif GameState.team_count >= ceiling:
		if GameState.human_players >= 2:
			GameState.free_for_all = true
		else:
			GameState.team_count = 2
	else:
		GameState.team_count += 1
	_fix_setup()
	_refresh_all.call()


## The smallest team size this setup allows: a team can never be smaller than
## the humans already standing in it.
func _smallest_team_size() -> int:
	var biggest := 1
	for t in GameState.active_teams():
		biggest = maxi(biggest, GameState.humans_on_team(t))
	return biggest


## Keep the setup self-consistent after any change.
func _fix_setup() -> void:
	if GameState.human_players < 2:
		GameState.free_for_all = false
	GameState.team_count = clampi(GameState.team_count, 2,
		mini(GameState.MAX_TEAMS, maxi(GameState.human_players, 2)))
	if not GameState.free_for_all:
		GameState.team_size = maxi(GameState.team_size, _smallest_team_size())


## Spell out what you'll actually get, since "3 humans across 2 teams at team
## size 3" is not obviously a 3v3 with three bots in it.
func _describe() -> String:
	if GameState.free_for_all:
		return "%d players, every one for themselves — no AI" % GameState.human_players
	var ai := 0
	var sides := PackedStringArray()
	for t in GameState.active_teams():
		ai += GameState.ai_needed(t)
		sides.append(str(GameState.team_size))
	return "%d human%s + %d AI     %s" % [
		GameState.human_players, "" if GameState.human_players == 1 else "s",
		ai, " v ".join(sides)]


func _start(rotate: bool) -> void:
	GameState.rotate_maps = rotate
	get_tree().change_scene_to_file(GAME_SCENE)


# --- widgets -----------------------------------------------------------------

## One big picker box: a heading, the current choice, a blurb and a position
## counter. It is a Button so the whole panel is clickable AND focusable, which
## is what makes it work from a pad as readily as from the mouse.
func _picker(parent: HBoxContainer, heading: String) -> Button:
	var b := _framed(Button.new())
	b.custom_minimum_size = BOX
	parent.add_child(b)
	# The text lives in child labels rather than the Button's own caption, so the
	# four lines can each have their own size and colour.
	var lines := VBoxContainer.new()
	lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.add_theme_constant_override("separation", 6)
	b.add_child(lines)
	lines.add_child(_label(heading, 16, FAINT))
	lines.add_child(_label("", 32, Color(0.92, 0.95, 1.0)))  # value
	lines.add_child(_label("", 15, DIM))                     # blurb
	lines.add_child(_label("", 13, FAINT))                   # counter
	return b


func _set_picker(box: Button, value: String, blurb: String, counter: String) -> void:
	var lines: VBoxContainer = box.get_child(0)
	lines.get_child(1).text = value
	lines.get_child(2).text = blurb
	lines.get_child(3).text = counter


## A small setting button. Cycles on press, same as every row on the old screen.
func _chip(parent: HBoxContainer, text: String) -> Button:
	var b := _framed(Button.new())
	b.text = text
	b.custom_minimum_size = Vector2(0, 38)
	b.add_theme_font_size_override("font_size", 16)
	parent.add_child(b)
	return b


func _wide_button(text: String, size: int) -> Button:
	var b := _framed(Button.new())
	b.text = text
	b.custom_minimum_size = Vector2(824, 52)   # both picker boxes plus the gap
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", size)
	return b


## Shared panel look, and the focus wiring every control here needs: hovering
## takes focus too, so the highlighted control is always the one Enter/A acts on.
func _framed(b: Button) -> Button:
	b.add_theme_color_override("font_color", Color(0.90, 0.93, 0.97))
	b.add_theme_color_override("font_focus_color", ACCENT)
	b.add_theme_color_override("font_hover_color", ACCENT)
	for state in ["normal", "hover", "focus", "pressed"]:
		b.add_theme_stylebox_override(state,
			_panel(PANEL_EDGE if state == "normal" else ACCENT))
	b.mouse_entered.connect(b.grab_focus)
	return b


func _panel(edge: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = edge
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	return sb


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
