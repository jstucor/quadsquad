extends Control
## THE PLAYLIST SCREEN — three columns, and it is where a night's play is built.
##
## WHAT IT REPLACED. `menu.gd` is a good MATCH SETUP screen and a bad FRONT END:
## fourteen dropdowns on one grid, every one a real decision, all of them at the
## same weight, and the result is ONE match. Four people at a couch do not want
## one match — they want three rounds, chosen once, played back to back without
## anybody having to walk to the machine between them. That is what Battlefront's
## front end is shaped around, and it is why this screen is TWO columns and a
## button:
##
##   LEFT    BUILD A ROUND. A guided pick — MAP, then MODE, then the SIDES — and
##           at the end of it a round is added to the queue. It is a sequence and
##           not a grid because it is a story: which planet, what are we playing,
##           who are we. Each step names what it is choosing between.
##   RIGHT   THE PLAYLIST. The rounds you have queued, in order, and the button
##           that plays them. It is a COLUMN and not a line at the bottom, because
##           its whole job is to be readable while you are still building.
##   BEHIND  MATCH SETTINGS, on a button. They were the middle column and should
##           not have been: a dozen dropdowns touched once an evening stood
##           permanently between the two things this screen is for. See
##           `_build_settings_panel` — including why the summary line under the
##           columns has to name every setting that moved behind it.
##
## THE SETTINGS ARE CAPTURED WHEN A ROUND IS ADDED, not shared by every round in
## the queue (see `GameState.capture_match`). That is the difference between a
## playlist and a rotation: round one can be a 20-a-side Conquest at REALISTIC
## time-to-kill and round two a four-player deathmatch, and neither has to be set
## up again.
##
## Driven by the built-in ui_* actions with explicit focus neighbours, exactly as
## `menu.gd` is and for the same reason: Godot's geometric focus search cannot
## read a three-column layout, and a pad that can move the highlight but not
## reach the next column is a pad that cannot use the screen.

const GAME_SCENE := "res://scenes/main.tscn"
const TEAM_SELECT_SCENE := "res://scenes/team_select.tscn"
## WHO IS FIGHTING IS ASKED ONCE, IMMEDIATELY BEFORE EACH ROUND, on its own
## screen — see `faction_select.gd` for why it is not queued with the round.
const FACTION_SCENE := "res://scenes/faction_select.tscn"
const SIGN_IN_SCENE := "res://scenes/sign_in.tscn"
const FRONT_SCENE := "res://scenes/front.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"
## This screen's own path, for the SETTINGS screen to come back to.
const PLAYLIST_SCENE := "res://scenes/playlist.tscn"

const BG_COLOR := Color(0.05, 0.06, 0.08)
const ACCENT := Color(0.45, 0.72, 1.0)
const DIM := Color(0.62, 0.66, 0.72)
const FAINT := Color(0.42, 0.46, 0.52)
const PANEL := Color(0.09, 0.11, 0.14, 0.92)
const PANEL_EDGE := Color(0.24, 0.30, 0.38)

## The three columns, in pixels. The left one is widest because it is the one
## being read — a map list at the width of a settings row is a list of
## abbreviations.
const BUILD_W := 500
const SETTINGS_W := 360
const QUEUE_W := 440
const COLUMN_H := 470

## How many rounds may be queued. A ceiling rather than an unbounded list because
## the column has to stay readable without scrolling, and nobody at a sofa is
## planning a twelfth round before the first one is played.
const MAX_ROUNDS := 8

## The build column's two steps.
##
## THERE WAS A THIRD — CHOOSE THE SIDES — AND IT IS NOW A SCREEN OF ITS OWN, ONCE
## BEFORE EVERY ROUND (`faction_select.tscn`). Queuing the sides with the round
## meant deciding, on a Tuesday, who everybody would be in round three; and it is
## the one decision at a couch that people actually argue about and change their
## minds on. It also made the queue brittle in a way nothing reported: a round
## carried the factions it was built with, so a playlist assembled last week
## fielded last week's armies no matter what anybody wanted tonight.
enum Step { MAP, MODE }
const STEP_NAMES := {
	Step.MAP: "1  ·  CHOOSE A MAP",
	Step.MODE: "2  ·  CHOOSE A GAME MODE",
}
const STEP_BLURBS := {
	Step.MAP: "Where the round is fought",
	Step.MODE: "What the round is — and it adds the round to your playlist",
}

var _step := Step.MAP
var _build_list: VBoxContainer
var _build_heading: Label
var _build_blurb: Label
var _build_scroll: ScrollContainer
var _queue_list: VBoxContainer
var _queue_heading: Label
var _summary: Label
var _settings_line: Label   # what is behind the SETTINGS button, said out loud
var _start: Button
var _back: Button
var _controls: Button
var _settings_rows: Array[OptionButton] = []
var _settings_scroll: ScrollContainer
var _overlay: Control
var _settings_btn: Button
var _close_btn: Button
## The top bar of the settings panel: which mode's settings are being edited.
## It starts on the mode the round being built is in, and it does NOT change the
## round — you can set Conquest up while queuing a deathmatch, which is the point
## of the settings being per mode at all.
var _mode_btn: Button
var _editing_mode := 0
var _tint_dd: Array[OptionButton] = []
var _refresh_settings: Callable
## The two focus columns, rebuilt whenever either changes, plus the settings
## panel's own ring. The panel's ring is SEPARATE and closed on itself: focus
## only ever moves through the neighbours stated here, so while the panel is up
## the stick cannot walk out of it into the screen behind.
var _left_focus: Array = []
var _mid_focus: Array = []
var _right_focus: Array = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Quality.active_views = 1
	Quality.apply_global()
	Engine.max_fps = 60
	Audio.play_music("menu")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Coming BACK here after a playlist has been played: the queue is spent and
	# leaving it up would make START replay it with no sign that anything had
	# happened. Cleared on arrival rather than on the way out, so the round that
	# is running can still ask what is next.
	if not GameState.playlist_active():
		GameState.playlist_index = -1
	# LAST NIGHT'S SETUP, read back before anything is drawn. This screen and the
	# single-match menu are the only two that load it — see `GameState.load_setup`
	# for why an autoload's `_init` deliberately does not.
	GameState.load_setup()
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

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(head)
	head.add_child(_text("QUADSQUAD", 40, ACCENT))
	head.add_child(_text(_signed_in(), 14, FAINT))
	column.add_child(_spacer(6))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	row.add_child(_build_column())
	row.add_child(_queue_column())
	# Built LAST and as siblings of the columns, so they draw over them — and the
	# mode panel after the settings panel, so it draws over that in turn.
	_build_settings_panel()

	column.add_child(_spacer(6))
	_summary = _text("", 14, DIM)
	column.add_child(_summary)
	_settings_line = _text("", 12, FAINT)
	column.add_child(_settings_line)
	column.add_child(_text(
		"Left stick to move    ·    A to choose    ·    B to step back",
		13, FAINT))

	_refresh_settings.call()
	_show_step(Step.MAP)
	_refresh_queue()


## Who is playing tonight, named. It is the one thing on this screen that is not
## a setting, and it is here because the sign-in is the step before: a player who
## chose the wrong account has exactly one screen in which to notice.
func _signed_in() -> String:
	var names := PackedStringArray()
	for i in GameState.human_players:
		var who := GameState.account_for(i)
		names.append(who if not who.is_empty() else "PLAYER %d" % (i + 1))
	return "   ·   ".join(names)


# --- the left column: BUILD A MATCH -------------------------------------------

func _build_column() -> Control:
	var panel := _panel_box(BUILD_W)
	var box: VBoxContainer = panel.get_child(0)
	_build_heading = _left_text("", 15, ACCENT)
	box.add_child(_build_heading)
	_build_blurb = _left_text("", 12, FAINT)
	box.add_child(_build_blurb)
	box.add_child(_rule(BUILD_W - 28))
	_build_scroll = ScrollContainer.new()
	_build_scroll.custom_minimum_size = Vector2(BUILD_W - 28, COLUMN_H - 76)
	_build_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_build_scroll)
	_build_list = VBoxContainer.new()
	_build_list.add_theme_constant_override("separation", 4)
	_build_list.custom_minimum_size = Vector2(BUILD_W - 44, 0)
	_build_scroll.add_child(_build_list)
	return panel


## Rebuild the left column for a step. The list is genuinely different at each
## one — fourteen maps, five modes, a dozen faction sets — so it is rebuilt
## rather than refilled, and the focus wiring is rebuilt with it (a neighbour
## pointing at a freed button is a direction that silently does nothing).
func _show_step(step: int) -> void:
	_step = step
	_build_heading.text = str(STEP_NAMES[step])
	_build_blurb.text = str(STEP_BLURBS[step])
	for c in _build_list.get_children():
		_build_list.remove_child(c)
		c.queue_free()
	_left_focus.clear()
	match step:
		Step.MAP:
			for i in GameState.MAPS.size():
				var m: Dictionary = GameState.MAPS[i]
				# MASSIVE is procedural-ground only, so a map that cannot hold the
				# chosen mode is DISABLED rather than missing — the same rule every
				# row on the old menu followed.
				var b := _list_row(str(m["name"]), str(m["blurb"]))
				b.pressed.connect(_pick_map.bind(i))
		Step.MODE:
			for i in GameState.MODE_NAMES.size():
				var b := _list_row(str(GameState.MODE_NAMES[i]), _mode_blurb(i))
				b.pressed.connect(_pick_mode.bind(i))
	_wire_columns()
	if not _left_focus.is_empty():
		(_left_focus[0] as Button).grab_focus()
	_refresh_summary()


func _pick_map(index: int) -> void:
	GameState.map_index = index
	Audio.play("ui_accept")
	_changed()
	_show_step(Step.MODE)


func _pick_mode(mode: int) -> void:
	GameState.mode = mode
	# A mode SEEDS where the gear comes from — and only if nobody has said
	# otherwise. Writing it straight in put a player's FACTION ROSTERS choice
	# back to CUSTOM every time they built a round, invisibly, because the
	# setting lives behind a button now. See `GameState.seed_class_mode`.
	GameState.seed_class_mode(mode)
	if mode == GameState.Mode.CONQUEST or GameState.massive():
		GameState.free_for_all = false
		GameState.team_count = 2
	if GameState.massive():
		GameState.map_index = GameState.procedural_map_index()
		if not GameState.MASSIVE_SIZES.has(GameState.team_size):
			GameState.team_size = GameState.MASSIVE_DEFAULT
	elif not GameState.TEAM_SIZES.has(GameState.team_size):
		GameState.team_size = 4
	# CHOOSING THE MODE IS WHAT QUEUES THE ROUND now that the sides have moved out
	# to their own screen: map, mode, done — two presses a round.
	_add_round()
	Audio.play("ui_accept")
	_changed()
	_show_step(Step.MAP)


func _mode_blurb(mode: int) -> String:
	# ASKED OF GameState with the mode set, because how many arguments a blurb
	# takes is part of the blurb and only that file knows it (house rule 6). The
	# setting is put back immediately — this is a description, not a choice.
	var was := GameState.mode
	GameState.mode = mode
	var line := GameState.mode_blurb()
	GameState.mode = was
	return line


# --- the faction sets ---------------------------------------------------------
#
# WHO FIGHTS WHOM, AS A SET AND NOT AS FOUR DROPDOWNS. The old menu had a row per
# side, which is the right control for building an odd match and the wrong one
# for the commonest question in the game: "Clones or Empire?". Every set below is
# DERIVED from `Loadout.factions()` rather than written out, so a faction added to
# a universe turns up here for free and no list can name a side that does not
# exist.
#
# The per-side rows have not been lost — the settings column still carries each
# side's COLOUR, and a cross-setting curiosity (UNSC against the Republic) is a
# set of its own here rather than something you have to assemble.

func _faction_sets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var all := Loadout.factions()
	var by_universe := {}
	for i in all.size():
		(by_universe.get_or_add(int(all[i]["universe"]), []) as Array).append(i)
	for u in by_universe:
		var list: Array = by_universe[u]
		var setting := str(all[int(list[0])]["universe_name"])
		# The classic pairings, in the order the roster states them: 0 against 1,
		# then 2 against 3. In Star Wars that is exactly Clone Wars and then Galactic
		# Civil War, which is what anybody picking a side is actually choosing.
		for base in range(0, list.size() - 1, 2):
			out.append(_set_of(setting, [list[base], list[base + 1]]))
		if list.size() >= 3:
			out.append(_set_of(setting, list.slice(0, mini(list.size(), 4))))
	# ...and the reason a match no longer HAS a universe: one setting's army
	# against another's. Built from the first faction of each, which is the one
	# everybody names when they name the setting.
	var firsts: Array = []
	for u in by_universe:
		firsts.append(int((by_universe[u] as Array)[0]))
	for a in firsts.size():
		for b in range(a + 1, firsts.size()):
			out.append(_set_of("CROSSOVER", [firsts[a], firsts[b]]))
	# FREE FOR ALL is a side per player and so is not a faction set at all — it is
	# here because this is the step that decides who is fighting whom, and "nobody
	# is on anybody's side" is an answer to that question.
	out.append({
		"name": "FREE FOR ALL", "blurb": "Every player their own side, no AI",
		"factions": [], "free_for_all": true,
	})
	return out


## A set's TITLE has to fit the row, and two sides always do while four never
## can: "ULTRAMARINES vs BLOOD ANGELS vs NECRONS vs ORKS" is 46 characters and ran
## off the panel. Past a pair the title becomes the COUNT and the names drop to
## the blurb, where they are smaller and are allowed to be long — which also
## reads better, since what a four-way set is offering is the free-for-all
## between armies rather than any particular matchup.
func _set_of(setting: String, factions: Array) -> Dictionary:
	var names := PackedStringArray()
	for f in factions:
		names.append(str(Loadout.faction(int(f))["name"]))
	if factions.size() > 2:
		return {
			"name": "ALL %d SIDES" % factions.size(),
			"blurb": ", ".join(names),
			"factions": factions,
		}
	return {
		"name": " vs ".join(names),
		"blurb": setting,
		"factions": factions,
	}


# --- THE SETTINGS, BEHIND A BUTTON --------------------------------------------
#
# THEY USED TO BE THE MIDDLE COLUMN and they should not be. A dozen dropdowns
# standing permanently between the two things this screen is FOR — building a
# round and reading the queue — is a third of the screen spent on controls that
# are touched once an evening and then never again, and it pushed both of the
# columns that matter into a narrower shape than they wanted.
#
# WHAT REPLACES THEM IS NOT NOTHING. Hiding a setting only works if the screen
# still SAYS what it is set to, or a player who cannot remember whether friendly
# fire is on has to go looking — so the summary line under the columns names
# every one of them (see `_refresh_summary`). The panel is where you CHANGE
# them; the line is where you READ them.
#
# It is a MODAL PANEL rather than another screen: it is edited in the middle of
# building a round, and a screen change would lose which step the builder was on.

func _build_settings_panel() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)
	# A DIM OVER THE WHOLE SCREEN, and it eats the mouse. Without it the columns
	# behind stay clickable, and a click that lands on a control you cannot see
	# is the worst kind of modal.
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.04, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)

	var centre := VBoxContainer.new()
	centre.set_anchors_preset(Control.PRESET_CENTER)
	centre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	centre.grow_vertical = Control.GROW_DIRECTION_BOTH
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay.add_child(centre)

	var panel := _panel_box(SETTINGS_W)
	centre.add_child(panel)
	var box: VBoxContainer = panel.get_child(0)
	box.add_child(_left_text("MATCH SETTINGS", 15, ACCENT))
	box.add_child(_left_text("How the round is played. Saved between sessions", 12, FAINT))
	box.add_child(_rule(SETTINGS_W - 28))
	_settings_scroll = ScrollContainer.new()
	_settings_scroll.custom_minimum_size = Vector2(SETTINGS_W - 28, COLUMN_H - 110)
	_settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_settings_scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 5)
	list.custom_minimum_size = Vector2(SETTINGS_W - 44, 0)
	_settings_scroll.add_child(list)

	# THE TOP BAR PICKS WHICH MODE YOU ARE EDITING, and everything under it is
	# that mode's settings followed by the ones every mode shares. It used to open
	# a second panel — settings within settings — which is one press too many for
	# a row you change more often than any other, and it hid the very thing the
	# panel is for behind a door.
	#
	# LEFT AND RIGHT SCROLL IT, A cycles it. Its left/right focus neighbours are
	# itself (see `_wire_ring`), so the stick cannot walk out of the row sideways
	# and the arrows on it are the truth rather than decoration.
	_mode_btn = _framed(Button.new())
	_mode_btn.custom_minimum_size = Vector2(SETTINGS_W - 44, 36)
	_mode_btn.add_theme_font_size_override("font_size", 15)
	_mode_btn.pressed.connect(_step_editing_mode.bind(1))
	list.add_child(_mode_btn)
	_mid_focus.append(_mode_btn)
	list.add_child(_spacer(2))
	# ...and the mode's OWN settings, directly beneath the bar that chose it.
	var size_dd := _setting(list, "PLAYERS A SIDE", _mid_focus)
	var victory_dd := _setting(list, "VICTORY", _mid_focus)
	list.add_child(_spacer(6))

	var skill_dd := _setting(list, "AI SKILL", _mid_focus)
	var assist_dd := _setting(list, "AIM ASSIST", _mid_focus)
	var ttk_dd := _setting(list, "TIME TO KILL", _mid_focus)
	var classes_dd := _setting(list, "CHARACTERS", _mid_focus)
	var ff_dd := _setting(list, "FRIENDLY FIRE", _mid_focus)
	# PLANET IS GONE FROM HERE. Every generated world is its own row in the MAP
	# step now, so a second control deciding which one gets built would be a
	# setting that silently contradicts the map you chose.
	var time_dd := _setting(list, "TIME OF DAY", _mid_focus)
	for t in GameState.MAX_TEAMS:
		_tint_dd.append(_setting(list, "SIDE %d COLOUR" % (t + 1), _mid_focus))

	box.add_child(_spacer(6))
	_close_btn = _framed(Button.new())
	_close_btn.text = "DONE"
	_close_btn.custom_minimum_size = Vector2(SETTINGS_W - 28, 34)
	_close_btn.pressed.connect(_close_settings)
	box.add_child(_close_btn)

	_refresh_settings = func() -> void:
		_mode_btn.text = "<   %s   >" % str(GameState.MODE_NAMES[_editing_mode])
		var sizes := _size_values(_editing_mode)
		_fill(size_dd, _labels(sizes, "%d PER SIDE"),
			maxi(sizes.find(GameState.mode_size(_editing_mode)), 0))
		size_dd.disabled = GameState.free_for_all
		var vics := _victory_values(_editing_mode)
		_fill(victory_dd, _labels(vics, "%d " + _victory_unit(_editing_mode)),
			maxi(vics.find(int(GameState.score_targets[_editing_mode])), 0))
		victory_dd.disabled = _editing_mode == GameState.Mode.ROYALE
		_fill(skill_dd, _names_of(Loadout.SQUAD_SKILLS), GameState.ai_skill)
		_fill(assist_dd, _dict_names(GameState.AIM_ASSIST_NAMES), GameState.aim_assist)
		_fill(ttk_dd, _dict_names(GameState.TTK_NAMES), GameState.ttk)
		_fill(classes_dd, _dict_names(GameState.CLASS_MODE_NAMES), GameState.class_mode)
		classes_dd.disabled = GameState.mode == GameState.Mode.ROYALE
		_fill(ff_dd, PackedStringArray(["OFF", "ON"]), 1 if GameState.friendly_fire else 0)
		# Only a generated world has a night to fight it in. DISABLED rather than
		# hidden: a row that vanishes is one nobody learns exists, and here it
		# would reflow the whole panel every time the map changed.
		_fill(time_dd, _dict_names(GameState.TIME_NAMES), GameState.time_of_day)
		time_dd.disabled = not GameState.map_is_procedural()
		for t in GameState.MAX_TEAMS:
			_fill(_tint_dd[t], _names_of(Loadout.TEAM_TINTS),
				GameState.team_tint[t] if t < GameState.team_tint.size() else 0)
			_tint_dd[t].disabled = t >= GameState.active_teams() or GameState.free_for_all
		_refresh_summary()

	size_dd.item_selected.connect(func(i: int) -> void:
		var values := _size_values(_editing_mode)
		GameState.set_mode_size(_editing_mode,
			int(values[clampi(i, 0, values.size() - 1)]))
		_changed())
	victory_dd.item_selected.connect(func(i: int) -> void:
		var values := _victory_values(_editing_mode)
		GameState.score_targets[_editing_mode] = int(values[clampi(i, 0, values.size() - 1)])
		_changed())
	skill_dd.item_selected.connect(func(i: int) -> void:
		GameState.ai_skill = i
		_changed())
	assist_dd.item_selected.connect(func(i: int) -> void:
		GameState.aim_assist = i
		_changed())
	ttk_dd.item_selected.connect(func(i: int) -> void:
		GameState.ttk = i
		_changed())
	classes_dd.item_selected.connect(func(i: int) -> void:
		# CHOSEN, not merely set: from here on no mode may seed over it.
		GameState.choose_class_mode(i)
		_changed())
	ff_dd.item_selected.connect(func(i: int) -> void:
		GameState.friendly_fire = i == 1
		_changed())
	time_dd.item_selected.connect(func(i: int) -> void:
		GameState.time_of_day = i
		_changed())
	for t in GameState.MAX_TEAMS:
		# `bind` the side, so four rows share one handler rather than four
		# closures that each capture the same loop variable.
		_tint_dd[t].item_selected.connect(_pick_tint.bind(t))


func _pick_tint(index: int, team: int) -> void:
	if team < GameState.team_tint.size():
		GameState.team_tint[team] = index
		GameState.refresh_sides()
	_changed()


## Repaint the settings and WRITE THEM DOWN. Every change goes through here for
## the reason `Controls` saves on every mutating call: a setup that is only
## written on the way out of a screen is a setup lost by anybody who closes the
## game from the match, which is how this game is normally left.
func _changed() -> void:
	_refresh_settings.call()
	GameState.save_setup()


## The sizes this match may legally pick. A team can never be smaller than the
## humans already standing in it, and MASSIVE has its own ladder entirely.
func _size_values(mode: int) -> Array:
	if mode == GameState.Mode.MASSIVE:
		return GameState.MASSIVE_SIZES
	var floor_size := 1
	for t in GameState.active_teams():
		floor_size = maxi(floor_size, GameState.humans_on_team(t))
	var out: Array = []
	for n: int in GameState.TEAM_SIZES:
		if n >= floor_size:
			out.append(n)
	return out if not out.is_empty() else [floor_size]


## What the current mode may be played to, in its own unit.
const SCORE_CHOICES := {
	GameState.Mode.DEATHMATCH: [10, 25, 50, 75, 100],
	GameState.Mode.ZONES: [60, 120, 200, 300],
	GameState.Mode.CONQUEST: [75, 150, 250, 400],
	GameState.Mode.MASSIVE: [100, 200, 350, 500],
}


func _victory_values(mode: int) -> Array:
	return SCORE_CHOICES.get(mode, [int(GameState.score_targets.get(mode, 1))])


func _victory_unit(mode: int) -> String:
	match mode:
		GameState.Mode.ZONES: return "SECONDS"
		GameState.Mode.CONQUEST: return "REINFORCEMENTS"
		_: return "KILLS"


# --- the right column: THE PLAYLIST -------------------------------------------

func _queue_column() -> Control:
	var panel := _panel_box(QUEUE_W)
	var box: VBoxContainer = panel.get_child(0)
	_queue_heading = _left_text("", 15, ACCENT)
	box.add_child(_queue_heading)
	box.add_child(_left_text("Played in order, no menus in between", 12, FAINT))
	box.add_child(_rule(QUEUE_W - 28))
	_queue_list = VBoxContainer.new()
	_queue_list.add_theme_constant_override("separation", 4)
	_queue_list.custom_minimum_size = Vector2(QUEUE_W - 44, COLUMN_H - 226)
	box.add_child(_queue_list)
	box.add_child(_spacer(4))

	# THE SETTINGS, ONE PRESS AWAY. Above PLAY rather than below it, because it is
	# the thing you might do BEFORE playing; framed rather than filled, because it
	# is not the action this screen exists to perform.
	_settings_btn = _framed(Button.new())
	_settings_btn.text = "MATCH SETTINGS"
	_settings_btn.custom_minimum_size = Vector2(QUEUE_W - 28, 38)
	_settings_btn.pressed.connect(_open_settings)
	box.add_child(_settings_btn)
	box.add_child(_spacer(2))

	# THE ONE ACTION THIS SCREEN EXISTS TO PERFORM, so it is the one control that
	# does not look like a setting: filled in the accent rather than framed in it.
	_start = Button.new()
	_start.text = "PLAY PLAYLIST"
	_start.custom_minimum_size = Vector2(QUEUE_W - 28, 52)
	_start.add_theme_font_size_override("font_size", 24)
	_primary(_start)
	_start.pressed.connect(_play)
	box.add_child(_start)
	# CONTROLS BELONGS HERE, one press from playing, because this is the screen
	# everybody is sitting in front of AFTER signing in — and a rebind made here
	# is written back onto the account that made it (see `settings.gd`), where the
	# same rebind made before signing in would be overwritten by the account.
	_controls = _framed(Button.new())
	_controls.text = "CONTROLS"
	_controls.custom_minimum_size = Vector2(QUEUE_W - 28, 34)
	_controls.pressed.connect(func() -> void:
		Audio.play("ui_accept")
		GameState.settings_return = PLAYLIST_SCENE
		get_tree().change_scene_to_file(SETTINGS_SCENE))
	box.add_child(_controls)
	_back = _framed(Button.new())
	_back.text = "BACK"
	_back.custom_minimum_size = Vector2(QUEUE_W - 28, 34)
	_back.pressed.connect(func() -> void:
		Audio.play("ui_back")
		get_tree().change_scene_to_file(SIGN_IN_SCENE))
	box.add_child(_back)
	return panel


func _add_round() -> void:
	if GameState.playlist.size() >= MAX_ROUNDS:
		Audio.play("ui_deny")
		return
	GameState.playlist.append(GameState.capture_match())
	GameState.save_setup()
	_refresh_queue()


## Rebuilt from the queue every time it changes. Each row is a BUTTON that
## removes itself: a queue you can add to and not take from is one wrong press
## away from being started over.
func _refresh_queue() -> void:
	for c in _queue_list.get_children():
		_queue_list.remove_child(c)
		c.queue_free()
	_right_focus.clear()
	_queue_heading.text = "PLAYLIST  ·  %d ROUND%s" % [
		GameState.playlist.size(), "" if GameState.playlist.size() == 1 else "S"]
	if GameState.playlist.is_empty():
		_queue_list.add_child(_left_text(
			"Nothing queued yet.\n\nPick a map, a mode and the sides on the left and the round lands here.",
			13, FAINT, true))
	for i in GameState.playlist.size():
		var entry: Dictionary = GameState.playlist[i]
		var b := _row_button(_queue_list, QUEUE_W - 44,
			"%d.  %s" % [i + 1, GameState.match_label(entry)],
			GameState.match_sides(entry) + "   ·   A to remove")
		b.pressed.connect(_remove_round.bind(i))
		_right_focus.append(b)
	if _settings_btn != null:
		_right_focus.append(_settings_btn)
	if _start != null:
		_start.disabled = GameState.playlist.is_empty()
		_right_focus.append(_start)
	# CONTROLS and BACK are the last rows of the right column, so both are always
	# reachable and neither is what a stick lands on by accident.
	if _controls != null:
		_right_focus.append(_controls)
	if _back != null:
		_right_focus.append(_back)
	_wire_columns()
	_refresh_summary()


func _remove_round(index: int) -> void:
	if index >= 0 and index < GameState.playlist.size():
		GameState.playlist.remove_at(index)
		GameState.save_setup()
		Audio.play("ui_back")
		_refresh_queue()
		if not _right_focus.is_empty():
			(_right_focus[0] as Button).grab_focus()


## TWO LINES UNDER THE COLUMNS, AND THEY ARE WHAT PAYS FOR HIDING THE SETTINGS.
##
## The moment a setting lives behind a button, "is friendly fire on?" costs a
## press, a read and a press back — so the settings say themselves out here
## instead, and the panel is only where they are CHANGED. The first line is the
## round being built; the second is every setting behind the button, in the order
## the panel lists them.
func _refresh_summary() -> void:
	if _summary == null:
		return
	var ai := 0
	for t in GameState.active_teams():
		ai += GameState.ai_needed(t)
	var queued := "%d round%s queued" % [GameState.playlist.size(),
		"" if GameState.playlist.size() == 1 else "s"]
	_summary.text = "%s   ·   %s   ·   %s" % [
		str(GameState.MAPS[GameState.map_index]["name"]), GameState.mode_blurb(), queued]
	if _settings_line == null:
		return
	var parts := PackedStringArray()
	parts.append("%d human%s + %d AI" % [GameState.human_players,
		"" if GameState.human_players == 1 else "s", ai])
	if not GameState.free_for_all:
		parts.append("%d a side" % GameState.team_size)
	parts.append("%s AI" % str(Loadout.SQUAD_SKILLS[GameState.ai_skill]["name"]))
	parts.append("ASSIST %s" % str(GameState.AIM_ASSIST_NAMES[GameState.aim_assist]))
	parts.append("TTK %s" % str(GameState.TTK_NAMES[GameState.ttk]))
	parts.append(str(GameState.CLASS_MODE_NAMES[GameState.class_mode]).split(" ")[0])
	parts.append("FF %s" % ("ON" if GameState.friendly_fire else "OFF"))
	if GameState.map_is_procedural():
		parts.append(str(GameState.TIME_NAMES[GameState.time_of_day]))
	_settings_line.text = "   ·   ".join(parts)


## Play the queue. The first round's settings are applied HERE rather than left
## to Main, so team select and the match are looking at the same match the
## playlist column described.
func _play() -> void:
	if not GameState.playlist_begin():
		Audio.play("ui_deny")
		return
	Audio.play("ui_accept")
	Net.leave()             # a local playlist is local, whatever was open before
	GameState.rotate_maps = false   # the queue is the rotation now
	GameState.chosen_teams = []     # team select fills it; free-for-all leaves it
	get_tree().change_scene_to_file(play_destination())


## WHERE PLAYING GOES, asked without going there (see `SettingsOverlay`). Always
## the faction screen: it is asked once before EVERY round, and it is what sends
## the round on to team select or straight into the match.
func play_destination() -> String:
	return FACTION_SCENE



## Step the top bar to another mode's settings. Wraps, because a bar you can
## walk off the end of is one that looks broken at both ends.
func _step_editing_mode(by: int) -> void:
	_editing_mode = wrapi(_editing_mode + by, 0, GameState.MODE_NAMES.size())
	Audio.play("ui_move")
	_refresh_settings.call()


## LEFT AND RIGHT SCROLL THE TOP BAR. Handled here rather than by focus
## neighbours because those MOVE the highlight, and the whole point of the bar is
## that it changes under a highlight that stays where it is.
func _mode_bar_input(event: InputEvent) -> bool:
	if _mode_btn == null or not _mode_btn.has_focus():
		return false
	if event.is_action_pressed("ui_right"):
		_step_editing_mode(1)
		return true
	if event.is_action_pressed("ui_left"):
		_step_editing_mode(-1)
		return true
	return false


## Open the settings. Focus moves INTO the panel — a modal whose controls cannot
## be reached is a modal that has trapped the player, and on a pad the highlight
## is the only cursor there is.
func _open_settings() -> void:
	if _overlay == null:
		return
	Audio.play("ui_accept")
	_overlay.visible = true
	# It opens on the mode the round being built is in, which is the one somebody
	# opening this panel is nearly always here to change.
	_editing_mode = GameState.mode
	_refresh_settings.call()
	_wire_ring(_mid_focus + [_close_btn])
	if not _mid_focus.is_empty():
		(_mid_focus[0] as Control).grab_focus()


func _close_settings() -> void:
	if _overlay == null or not _overlay.visible:
		return
	Audio.play("ui_back")
	_overlay.visible = false
	GameState.save_setup()
	# Back onto the button that opened it, or the highlight is left on a control
	# nobody can see any more.
	if _settings_btn != null:
		_settings_btn.grab_focus()


## B CLOSES IT, wherever the highlight is inside. `_unhandled_input` and not
## `_input`: an OptionButton's own popup is up on top of this and answers
## ui_cancel first, so closing the popup must not also close the panel.
func _unhandled_input(event: InputEvent) -> void:
	if _overlay != null and _overlay.visible and _mode_bar_input(event):
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if _overlay != null and _overlay.visible:
		_close_settings()
		get_viewport().set_input_as_handled()


# --- focus --------------------------------------------------------------------

## Three columns of controls, wired by hand.
##
## Up and down walk a column and WRAP; left and right cross to the neighbouring
## column at the nearest row. Godot's geometric search cannot do this — `menu.gd`
## records what it does to a two-box row — and here the left column is rebuilt on
## every step, so the wiring is redone with it rather than stated once.
func _wire_columns() -> void:
	var columns: Array = [_left_focus, _right_focus]
	for c in columns.size():
		var here: Array = columns[c]
		if here.is_empty():
			continue
		var left: Array = _nearest_column(columns, c, -1)
		var right: Array = _nearest_column(columns, c, 1)
		for i in here.size():
			var b: Control = here[i]
			b.focus_neighbor_top = (here[wrapi(i - 1, 0, here.size())] as Control).get_path()
			b.focus_neighbor_bottom = (here[wrapi(i + 1, 0, here.size())] as Control).get_path()
			b.focus_neighbor_left = _across(left, i, here.size())
			b.focus_neighbor_right = _across(right, i, here.size())
			b.focus_next = b.focus_neighbor_bottom
			b.focus_previous = b.focus_neighbor_top


## A self-contained ring: up and down walk it, wrapping, and left and right do
## the same rather than pointing at the screen underneath. Used for the settings
## panel, which is modal — every direction has to land back inside it.
func _wire_ring(items: Array) -> void:
	for i in items.size():
		var b: Control = items[i]
		if b == null:
			continue
		var up: NodePath = (items[wrapi(i - 1, 0, items.size())] as Control).get_path()
		var down: NodePath = (items[wrapi(i + 1, 0, items.size())] as Control).get_path()
		b.focus_neighbor_top = up
		b.focus_neighbor_bottom = down
		b.focus_neighbor_left = up
		b.focus_neighbor_right = down
		b.focus_next = down
		b.focus_previous = up


## The next non-empty column in a direction, wrapping — so a screen with an empty
## queue still lets left and right move somewhere rather than doing nothing.
func _nearest_column(columns: Array, from: int, dir: int) -> Array:
	for step in range(1, columns.size() + 1):
		var at: int = wrapi(from + dir * step, 0, columns.size())
		if not (columns[at] as Array).is_empty():
			return columns[at]
	return columns[from]


func _across(target: Array, i: int, height: int) -> NodePath:
	if target.is_empty():
		return NodePath()
	var at := 0 if height <= 1 else roundi(float(i) / float(height - 1) * (target.size() - 1))
	return (target[clampi(at, 0, target.size() - 1)] as Control).get_path()


# --- widgets ------------------------------------------------------------------

func _panel_box(width: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, COLUMN_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = PANEL_EDGE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	return panel


## A row in the build column: a title and a line saying what it is. The blurb is
## the half that matters — "SPILLWAY" is a word until something tells you it is a
## long narrow channel.
func _list_row(title: String, blurb: String) -> Button:
	var b := _row_button(_build_list, BUILD_W - 44, title, blurb)
	_left_focus.append(b)
	return b


func _row_button(into: Control, width: int, title: String, blurb: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(width, 44 if blurb != "" else 32)
	b.focus_mode = Control.FOCUS_ALL
	b.text = ""
	_paint_row(b, false)
	into.add_child(b)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	box.offset_left = 10
	box.offset_top = 4
	# BOUNDED ON THE RIGHT AS WELL AS THE LEFT, or a Label inside it simply grows
	# past the button and out through the panel behind it — which is what a long
	# faction set and a long map name each did, and it does not look like an
	# overflow, it looks like the panel having the wrong edge.
	box.offset_right = -10
	b.add_child(box)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 16)
	t.add_theme_color_override("font_color", Color(0.93, 0.95, 1.0))
	t.clip_text = true
	box.add_child(t)
	if blurb != "":
		var s := Label.new()
		s.text = blurb
		s.add_theme_font_size_override("font_size", 11)
		s.add_theme_color_override("font_color", FAINT)
		s.clip_text = true
		box.add_child(s)
	b.focus_entered.connect(func() -> void:
		_paint_row(b, true)
		Audio.play("ui_move")
		_reveal(b))
	b.focus_exited.connect(func() -> void: _paint_row(b, false))
	b.mouse_entered.connect(b.grab_focus)
	return b


## Scroll a focused row into view. A ScrollContainer does NOT follow focus on its
## own, so without this the list walks off the bottom of the panel and a pad
## player is moving a highlight they cannot see.
func _reveal(b: Control) -> void:
	for scroll in [_build_scroll, _settings_scroll]:
		if scroll != null and scroll.is_ancestor_of(b):
			scroll.ensure_control_visible(b)


func _paint_row(b: Button, on: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.20) if on \
		else Color(0.12, 0.14, 0.18, 0.85)
	sb.border_color = ACCENT if on else Color(0.20, 0.24, 0.30)
	sb.set_border_width_all(0)
	sb.border_width_left = 4 if on else 2
	sb.set_corner_radius_all(4)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, sb)


## One settings row: a caption on the left, the value on the right. Compact
## because the column is narrow and there are a dozen of them — a caption ABOVE
## each control (the old menu's shape) would make this column twice as tall as
## the two beside it.
## `focus` is which ring the row joins — the settings panel's, or the mode
## panel's when it is building its own. STATED rather than defaulted: an empty
## array is a perfectly ordinary ring that has not been filled yet, so using
## emptiness as "use the other one" silently put the mode panel's first rows into
## the settings panel's ring and left the mode panel with nothing to focus.
func _setting(into: Control, caption: String, focus: Array) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	into.add_child(row)
	var l := Label.new()
	l.text = caption
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", FAINT)
	l.custom_minimum_size = Vector2(108, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	var b := OptionButton.new()
	b.custom_minimum_size = Vector2(SETTINGS_W - 168, 30)
	b.add_theme_font_size_override("font_size", 13)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.fit_to_longest_item = false
	_framed(b)
	b.focus_entered.connect(_reveal.bind(b))
	row.add_child(b)
	_settings_rows.append(b)
	focus.append(b)
	return b


## Refill a dropdown and re-select without firing item_selected — `select()` is
## silent, which is what stops a refresh looping back into its own handler.
func _fill(b: OptionButton, items: PackedStringArray, choose: int) -> void:
	b.clear()
	for item in items:
		b.add_item(item)
	if b.item_count > 0:
		b.select(clampi(choose, 0, b.item_count - 1))


func _labels(values: Array, format: String) -> PackedStringArray:
	var out := PackedStringArray()
	for v in values:
		out.append(format % v)
	return out


func _names_of(rows: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for r in rows:
		out.append(str(r["name"]))
	return out


func _dict_names(table: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for i in table.size():
		out.append(str(table[i]))
	return out


func _primary(b: Button) -> void:
	b.add_theme_color_override("font_color", Color(0.05, 0.07, 0.10))
	b.add_theme_color_override("font_focus_color", Color(0.03, 0.05, 0.08))
	b.add_theme_color_override("font_hover_color", Color(0.03, 0.05, 0.08))
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.48, 0.54))
	for state in ["normal", "hover", "focus", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = ACCENT if state == "normal" else ACCENT.lightened(0.18)
		if state == "disabled":
			sb.bg_color = Color(0.18, 0.20, 0.24)
		sb.set_corner_radius_all(5)
		sb.set_content_margin_all(8)
		if state == "hover" or state == "focus":
			sb.border_color = Color(1, 1, 1, 0.85)
			sb.set_border_width_all(2)
		b.add_theme_stylebox_override(state, sb)
	b.focus_entered.connect(func() -> void: Audio.play("ui_move"))
	b.mouse_entered.connect(b.grab_focus)


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


func _left_text(text: String, size: int, colour: Color, wrap := false) -> Label:
	var l := _text(text, size, colour)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(QUEUE_W - 44, 0)
	return l


func _rule(width: int) -> Control:
	var line := ColorRect.new()
	line.color = Color(ACCENT, 0.22)
	line.custom_minimum_size = Vector2(width, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
