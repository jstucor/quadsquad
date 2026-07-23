extends Control
## Front screen. Two big picker BOXES side by side — the map on the left, the
## game mode on the right — over a row of match settings and a START button.
##
## The old screen listed every map as its own row, which stopped scaling the
## moment the roster grew: at nine maps the column ran off both ends of the
## viewport. A picker box shows one choice at a time and cycles on click, so the
## screen stays a fixed size however many maps exist.
##
## Driven by the built-in ui_* actions, so any of the four joypads works it (and
## the keyboard still does) without per-device polling: those actions are bound
## to device -1, all devices, unlike the in-match kb_*/joypad input which has to
## stay per-player. Godot ships joypad events on the four DIRECTIONS only, so
## Controls.apply_ui_pad puts A and B on accept/cancel — without it a pad can
## move the focus around this screen and never press anything. Focus neighbours
## are wired explicitly by _wire_focus; the geometric search gets this layout
## wrong.

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

	# The match settings, as labelled DROPDOWNS. They used to be chips you
	# pressed to cycle: to see the choices you had to walk through them, and to
	# go back one you went all the way round. A dropdown shows the whole range at
	# once and lets you land on any of it in one press, which matters most for
	# TEAMS and TEAM SIZE — the two settings people actually shop between.
	var settings := GridContainer.new()
	settings.columns = 3
	settings.add_theme_constant_override("h_separation", 10)
	settings.add_theme_constant_override("v_separation", 8)
	column.add_child(settings)
	var players_dd := _dropdown(settings, "PLAYERS")
	var teams_dd := _dropdown(settings, "TEAMS")
	var size_dd := _dropdown(settings, "TEAM SIZE")
	var skill_dd := _dropdown(settings, "AI SKILL")
	var assist_dd := _dropdown(settings, "AIM ASSIST")

	_summary = _label("", 17, Color(0.68, 0.72, 0.78))
	column.add_child(_summary)

	var start := _wide_button("START MATCH", 28)
	start.pressed.connect(_start.bind(false))
	column.add_child(start)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	var rotate_btn := _chip(row, "MAP ROTATION")
	rotate_btn.pressed.connect(_start.bind(true))
	var controls_btn := _chip(row, "CONTROLS")
	controls_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file(SETTINGS_SCENE))
	var quit_btn := _chip(row, "QUIT")
	quit_btn.pressed.connect(func() -> void: get_tree().quit())

	_wire_focus([
		[map_box, mode_box],
		[players_dd, teams_dd, size_dd],
		[skill_dd, assist_dd],
		[start],
		[rotate_btn, controls_btn, quit_btn],
	])

	column.add_child(_label(
		"Left stick / d-pad to move    A to select or change    P1..P4 are pads 1..4",
		15, FAINT))

	# One refresh closure that everything calls, so no control has to know what
	# any other one displays.
	_refresh_all = func() -> void:
		var map: Dictionary = GameState.MAPS[GameState.map_index]
		_set_picker(map_box, map["name"], map["blurb"],
			"%d of %d" % [GameState.map_index + 1, GameState.MAPS.size()])
		_set_picker(mode_box, GameState.MODE_NAMES[GameState.mode],
			GameState.mode_blurb(),
			"%d of %d" % [GameState.mode + 1, GameState.MODE_NAMES.size()])
		# Every dropdown is REBUILT here rather than just re-selected, because
		# what is legal changes as you go: team size cannot drop below the humans
		# already standing in a team, and free-for-all needs a second player.
		# Rebuilding is a few items and happens on a press, never per frame.
		_fill(players_dd, _player_items(), GameState.human_players - GameState.MIN_HUMANS)
		_fill(teams_dd, _team_items(), _team_choice())
		teams_dd.set_item_disabled(_FREE_FOR_ALL_ITEM, GameState.human_players < 2)
		var sizes := _size_items()
		_fill(size_dd, sizes, sizes.find(_size_label(GameState.team_size)))
		size_dd.disabled = GameState.free_for_all   # every side is one player
		_fill(skill_dd, _skill_items(), GameState.ai_skill)
		_fill(assist_dd, _assist_items(), GameState.aim_assist)
		_summary.text = _describe()

	map_box.pressed.connect(func() -> void:
		GameState.map_index = wrapi(GameState.map_index + 1, 0, GameState.MAPS.size())
		_refresh_all.call())
	mode_box.pressed.connect(func() -> void:
		GameState.mode = wrapi(GameState.mode + 1, 0, GameState.MODE_NAMES.size())
		_refresh_all.call())
	players_dd.item_selected.connect(func(i: int) -> void:
		GameState.human_players = GameState.MIN_HUMANS + i
		_fix_setup()
		_refresh_all.call())
	teams_dd.item_selected.connect(func(i: int) -> void:
		# The last item is FREE FOR ALL; the rest are literal team counts.
		GameState.free_for_all = i == _FREE_FOR_ALL_ITEM
		if not GameState.free_for_all:
			GameState.team_count = 2 + i
		_fix_setup()
		_refresh_all.call())
	size_dd.item_selected.connect(func(i: int) -> void:
		GameState.team_size = _smallest_team_size() + i
		_refresh_all.call())
	skill_dd.item_selected.connect(func(i: int) -> void:
		GameState.ai_skill = i
		_refresh_all.call())
	assist_dd.item_selected.connect(func(i: int) -> void:
		GameState.aim_assist = i
		_refresh_all.call())

	_fix_setup()
	_refresh_all.call()
	map_box.grab_focus()


## Wire every control's four focus neighbours from the row layout.
##
## Godot's geometric search is NOT good enough here and this screen is the proof:
## from the 400x200 MAP box, RIGHT landed on TEAM SIZE two rows down, and the
## MODE box sitting directly beside it took four presses to reach. A pad is now
## the only way in, so the neighbours are stated rather than guessed.
##
## Every direction wraps, so there is no dead end anywhere on the screen — with
## a pad as the only way in, a press that appears to do nothing reads as a hung
## menu. Up and down cross to the nearest control in the next row by POSITION IN
## THE ROW, which is layout-free (nothing has been sized yet when this runs) and
## lands where the eye expects across rows of different lengths — the fifth of
## five chips drops onto the third of three.
func _wire_focus(rows: Array) -> void:
	for r in rows.size():
		var current: Array = rows[r]
		for i in current.size():
			var b: Button = current[i]
			b.focus_neighbor_left = current[wrapi(i - 1, 0, current.size())].get_path()
			b.focus_neighbor_right = current[wrapi(i + 1, 0, current.size())].get_path()
			b.focus_neighbor_top = _across(rows, wrapi(r - 1, 0, rows.size()),
				i, current.size())
			b.focus_neighbor_bottom = _across(rows, wrapi(r + 1, 0, rows.size()),
				i, current.size())
			# Tab/shoulder order stays the reading order rather than the ring.
			b.focus_next = b.focus_neighbor_right
			b.focus_previous = b.focus_neighbor_left


func _across(rows: Array, r: int, i: int, width: int) -> NodePath:
	var target: Array = rows[r]
	# A row of one (START) has no position to carry across, so it aims at the
	# middle of the row it lands on.
	var at := (target.size() - 1) / 2 if width <= 1 \
		else roundi(float(i) / float(width - 1) * (target.size() - 1))
	return target[at].get_path()


## --- what each dropdown offers ------------------------------------------------
##
## TEAMS lists 2, 3, 4 and then FREE FOR ALL, which is always the last item.
##
## The count is NOT limited by how many people are at the couch: AI fill every
## side up to TEAM SIZE, so one player against three AI teams is a perfectly good
## match and is probably the main way somebody plays alone. FREE FOR ALL is the
## only option that needs a second human, because it is defined as every player
## being their own side with no AI at all — on your own it would be a match
## against nobody, so it is DISABLED rather than hidden: an option that vanishes
## is one nobody learns exists.
const _FREE_FOR_ALL_ITEM := 3   # index of FREE FOR ALL in the TEAMS list


func _team_items() -> PackedStringArray:
	var out := PackedStringArray()
	for n in range(2, GameState.MAX_TEAMS + 1):
		out.append("%d TEAMS" % n)
	out.append("FREE FOR ALL")
	return out


func _team_choice() -> int:
	return _FREE_FOR_ALL_ITEM if GameState.free_for_all else GameState.team_count - 2


func _player_items() -> PackedStringArray:
	var out := PackedStringArray()
	for n in range(GameState.MIN_HUMANS, GameState.MAX_HUMANS + 1):
		out.append("%d PLAYER%s" % [n, "" if n == 1 else "S"])
	return out


## Team size starts at the biggest team's human headcount: a team can never be
## smaller than the people already standing in it.
func _size_items() -> PackedStringArray:
	var out := PackedStringArray()
	for n in range(_smallest_team_size(), GameState.MAX_TEAM_SIZE + 1):
		out.append(_size_label(n))
	return out


func _size_label(n: int) -> String:
	return "1 (SOLO)" if GameState.free_for_all else "%d PER TEAM" % n


func _skill_items() -> PackedStringArray:
	var out := PackedStringArray()
	for s in Loadout.SQUAD_SKILLS:
		out.append(str(s["name"]))
	return out


func _assist_items() -> PackedStringArray:
	var out := PackedStringArray()
	for i in GameState.AIM_ASSIST_NAMES.size():
		out.append(str(GameState.AIM_ASSIST_NAMES[i]))
	return out


## The smallest team size this setup allows: a team can never be smaller than
## the humans already standing in it.
func _smallest_team_size() -> int:
	var biggest := 1
	for t in GameState.active_teams():
		biggest = maxi(biggest, GameState.humans_on_team(t))
	return biggest


## Keep the setup self-consistent after any change.
func _fix_setup() -> void:
	# Free-for-all is the one setting that genuinely needs a second human.
	if GameState.human_players < 2:
		GameState.free_for_all = false
	GameState.team_count = clampi(GameState.team_count, 2, GameState.MAX_TEAMS)
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


## One labelled setting dropdown: a caption above the control so the value
## itself does not have to carry its own name ("TEAMS  3" in a button caption
## reads as one string and is unreadable at a glance across a room).
func _dropdown(parent: GridContainer, caption: String) -> OptionButton:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 2)
	parent.add_child(cell)
	cell.add_child(_label(caption, 13, FAINT))
	var b := OptionButton.new()
	b.custom_minimum_size = Vector2(196, 38)
	b.add_theme_font_size_override("font_size", 16)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.fit_to_longest_item = false   # a fixed width, so the row never reflows
	_framed(b)
	cell.add_child(b)
	return b


## Refill a dropdown and re-select, without firing item_selected — `select()` is
## silent, which is what stops a refresh from looping back into its own handler.
func _fill(b: OptionButton, items: PackedStringArray, choose: int) -> void:
	b.clear()
	for item in items:
		b.add_item(item)
	if b.item_count > 0:
		b.select(clampi(choose, 0, b.item_count - 1))


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
