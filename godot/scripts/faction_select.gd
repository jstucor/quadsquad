extends Control
## WHO IS FIGHTING THIS ONE — asked ONCE, immediately before every round.
##
## IT USED TO BE PART OF QUEUING A ROUND, and that was the wrong place for it.
## Every other thing in a playlist entry is a rule you set and forget: the map,
## the mode, how long a body lasts. Who everybody IS is not that — it is the
## decision people at a couch argue about, swap over, and want to make with the
## last round still in mind ("right, I'm the droids this time"). Deciding it on a
## Tuesday for round three of a queue built on Tuesday is deciding it too early,
## and it made a saved playlist quietly brittle: a queue assembled last week
## fielded last week's armies however anybody felt about it tonight.
##
## So it is a screen, and every round passes through it — the first one out of
## the playlist and every one after (`Main._next_map`). One press per side if you
## are keeping what you had, which is the common case, and the START button is
## focused when it opens so "same as before" is a single button.
##
## Driven by the ui_* actions with explicit focus neighbours, exactly as the
## setup screens are: Godot ships joypad events on the directions only, and
## `Controls.apply_ui_pad` is what makes A and B work on any pad.

const GAME_SCENE := "res://scenes/main.tscn"
const TEAM_SELECT_SCENE := "res://scenes/team_select.tscn"
const PLAYLIST_SCENE := "res://scenes/playlist.tscn"

const BG_COLOR := Color(0.05, 0.06, 0.08)
const ACCENT := Color(0.45, 0.72, 1.0)
const DIM := Color(0.62, 0.66, 0.72)
const FAINT := Color(0.42, 0.46, 0.52)
const PANEL := Color(0.09, 0.11, 0.14, 0.92)
const PANEL_EDGE := Color(0.24, 0.30, 0.38)
const ROW_W := 620

## Set by whoever sends the player here: true while a PLAYLIST is running, so
## the screen knows that BACK means "give up on the queue" rather than "go back
## to building it". Static because the scene is loaded by path and there is
## nowhere else to hand it over.
static var from_playlist := false

var _rows: Array[OptionButton] = []
var _tints: Array[OptionButton] = []
var _summary: Label
var _start: Button
var _refresh: Callable


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Quality.active_views = 1
	Quality.apply_global()
	Engine.max_fps = 60
	Audio.play_music("menu")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# The sides may have been set by a playlist entry or read off disk without
	# anything re-deriving the names, chips and tracers from them. This screen is
	# about to show all three, so it re-derives them first.
	GameState.refresh_sides()
	_build()


func _exit_tree() -> void:
	Engine.max_fps = 0


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
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	column.add_child(_text("CHOOSE THE SIDES", 40, ACCENT))
	# WHAT IS ABOUT TO BE PLAYED, said out loud. This screen is the last thing
	# between the queue and the match, so it is also the last chance to notice
	# that the round coming up is not the one you thought.
	column.add_child(_text("%s   ·   %s" % [
		str(GameState.MAPS[GameState.map_index]["name"]), GameState.mode_blurb()],
		15, DIM))
	column.add_child(_spacer(14))

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = PANEL_EDGE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	column.add_child(panel)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	panel.add_child(list)

	var focus_rows: Array = []
	for t in GameState.MAX_TEAMS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		list.add_child(row)
		var tag := _text("SIDE %d" % (t + 1), 16, DIM)
		tag.custom_minimum_size = Vector2(90, 0)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(tag)
		var faction := _dropdown(row, ROW_W - 320)
		var tint := _dropdown(row, 180)
		_rows.append(faction)
		_tints.append(tint)
		focus_rows.append([faction, tint])
		faction.item_selected.connect(_pick_faction.bind(t))
		tint.item_selected.connect(_pick_tint.bind(t))

	column.add_child(_spacer(6))
	_summary = _text("", 14, FAINT)
	column.add_child(_summary)
	column.add_child(_spacer(6))

	_start = Button.new()
	_start.text = "FIGHT"
	_start.custom_minimum_size = Vector2(ROW_W, 54)
	_start.add_theme_font_size_override("font_size", 26)
	_primary(_start)
	_start.pressed.connect(_go)
	column.add_child(_start)
	var back := _framed(Button.new())
	back.text = "BACK"
	back.custom_minimum_size = Vector2(ROW_W, 34)
	back.pressed.connect(_back)
	column.add_child(back)
	column.add_child(_spacer(6))
	column.add_child(_text(
		"Left stick to move    ·    A to change a side    ·    B to go back",
		13, FAINT))

	_refresh = func() -> void:
		for t in GameState.MAX_TEAMS:
			var live: bool = t < GameState.active_teams() and not GameState.free_for_all
			_fill(_rows[t], _faction_items(),
				GameState.team_faction[t] if t < GameState.team_faction.size() else 0)
			_fill(_tints[t], _tint_items(),
				GameState.team_tint[t] if t < GameState.team_tint.size() else 0)
			# A side this match does not field is DISABLED rather than hidden —
			# the same rule the setup screens keep, and here it also stops the
			# panel changing height between a two-side round and a four-side one.
			_rows[t].disabled = not live
			_tints[t].disabled = not live
		_summary.text = _describe()

	_wire(focus_rows + [[_start], [back]])
	_refresh.call()
	# FOCUSED ON FIGHT. Keeping the sides you already had is the common case and
	# it should cost one press, not a walk down the panel.
	_start.grab_focus()


## Every faction in the game, labelled with its setting — "NECRONS" alone does
## not say which game you are looking at once two settings can be on the field.
func _faction_items() -> PackedStringArray:
	var out := PackedStringArray()
	for f in Loadout.factions():
		out.append("%s  ·  %s" % [f["universe_name"], f["name"]])
	return out


func _tint_items() -> PackedStringArray:
	var out := PackedStringArray()
	for t in Loadout.TEAM_TINTS:
		out.append(str(t["name"]))
	return out


func _pick_faction(index: int, team: int) -> void:
	if team < GameState.team_faction.size():
		GameState.team_faction[team] = index
		GameState.refresh_sides()
		GameState.save_setup()
	_refresh.call()


func _pick_tint(index: int, team: int) -> void:
	if team < GameState.team_tint.size():
		GameState.team_tint[team] = index
		GameState.refresh_sides()
		GameState.save_setup()
	_refresh.call()


## DERIVED FROM THE ROWS ABOVE IT, never from the cached `team_names`. Those are
## refreshed by `GameState.refresh_sides`, so a caller that sets a faction without
## refreshing leaves this line naming last round's armies — directly under a
## dropdown showing the right ones, which is the one place a stale read is
## guaranteed to be noticed and disbelieved. Same rule as the flat faction list
## itself: derive it, do not keep a second copy.
func _describe() -> String:
	if GameState.free_for_all:
		return "Free for all — every player their own side"
	var names := PackedStringArray()
	for t in GameState.active_teams():
		if t < GameState.team_faction.size():
			names.append(str(Loadout.faction(GameState.team_faction[t])["name"]))
	return " vs ".join(names)


## THE SIDES ARE SET; GO AND PLAY. Team select still follows, because which side
## you personally stand on is a different question from who the sides ARE — and
## it is skipped in a free-for-all, where there is nothing to stand on.
func _go() -> void:
	Audio.play("ui_accept")
	if GameState.free_for_all or not GameState.chosen_teams.is_empty():
		get_tree().change_scene_to_file(GAME_SCENE)
	else:
		get_tree().change_scene_to_file(TEAM_SELECT_SCENE)


func _back() -> void:
	Audio.play("ui_back")
	# Backing out of the sides is backing out of the ROUND, so a running queue is
	# abandoned rather than resumed from the middle — the same answer leaving a
	# match mid-playlist gives.
	GameState.playlist_index = -1
	get_tree().change_scene_to_file(PLAYLIST_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()


# --- furniture ----------------------------------------------------------------

func _wire(rows: Array) -> void:
	for r in rows.size():
		var here: Array = rows[r]
		for i in here.size():
			var b: Control = here[i]
			b.focus_neighbor_left = (here[wrapi(i - 1, 0, here.size())] as Control).get_path()
			b.focus_neighbor_right = (here[wrapi(i + 1, 0, here.size())] as Control).get_path()
			var up: Array = rows[wrapi(r - 1, 0, rows.size())]
			var down: Array = rows[wrapi(r + 1, 0, rows.size())]
			b.focus_neighbor_top = (up[mini(i, up.size() - 1)] as Control).get_path()
			b.focus_neighbor_bottom = (down[mini(i, down.size() - 1)] as Control).get_path()
			b.focus_next = b.focus_neighbor_bottom
			b.focus_previous = b.focus_neighbor_top


func _dropdown(into: Control, width: int) -> OptionButton:
	var b := OptionButton.new()
	b.custom_minimum_size = Vector2(width, 34)
	b.add_theme_font_size_override("font_size", 15)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.fit_to_longest_item = false
	_framed(b)
	into.add_child(b)
	return b


func _fill(b: OptionButton, items: PackedStringArray, choose: int) -> void:
	b.clear()
	for item in items:
		b.add_item(item)
	if b.item_count > 0:
		b.select(clampi(choose, 0, b.item_count - 1))


func _primary(b: Button) -> void:
	b.add_theme_color_override("font_color", Color(0.05, 0.07, 0.10))
	b.add_theme_color_override("font_focus_color", Color(0.03, 0.05, 0.08))
	b.add_theme_color_override("font_hover_color", Color(0.03, 0.05, 0.08))
	for state in ["normal", "hover", "focus", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = ACCENT if state == "normal" else ACCENT.lightened(0.18)
		sb.set_corner_radius_all(5)
		sb.set_content_margin_all(8)
		if state != "normal":
			sb.border_color = Color(1, 1, 1, 0.85)
			sb.set_border_width_all(2)
		b.add_theme_stylebox_override(state, sb)
	b.mouse_entered.connect(b.grab_focus)
	b.focus_entered.connect(func() -> void: Audio.play("ui_move"))


func _framed(b: Button) -> Button:
	b.add_theme_color_override("font_color", Color(0.90, 0.93, 0.97))
	b.add_theme_color_override("font_focus_color", ACCENT)
	b.add_theme_color_override("font_hover_color", ACCENT)
	for state in ["normal", "hover", "focus", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.14, 0.18, 0.9)
		sb.border_color = PANEL_EDGE if state == "normal" else ACCENT
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(5)
		sb.set_content_margin_all(6)
		b.add_theme_stylebox_override(state, sb)
	b.mouse_entered.connect(b.grab_focus)
	b.focus_entered.connect(func() -> void: Audio.play("ui_move"))
	return b


func _text(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
