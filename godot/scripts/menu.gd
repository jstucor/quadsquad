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
const MENU_SCENE := "res://scenes/menu.tscn"
const TEAM_SELECT_SCENE := "res://scenes/team_select.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const FRONT_SCENE := "res://scenes/front.tscn"

const BG_COLOR := Color(0.06, 0.07, 0.09)
const ACCENT := Color(0.45, 0.72, 1.0)
const DIM := Color(0.62, 0.66, 0.72)
const FAINT := Color(0.42, 0.46, 0.52)
const PANEL := Color(0.10, 0.12, 0.15, 0.9)
const PANEL_EDGE := Color(0.24, 0.30, 0.38)

## THE GRID. Every settings row on this screen sits on the SAME four columns.
##
## It used to be three grids of two, three and four columns, each auto-sized to
## its own contents and each centred — so the three blocks were 420, 640 and 880
## wide stacked on top of each other, and the whole screen zig-zagged with none
## of the labels lining up. Nothing was WRONG with any one row, which is why it
## survived: the fault only exists between them.
##
## One column width and one column count is the whole fix, and it is also what
## lets a block be read as a block rather than as six loose controls.
const COLS := 4
const CELL_W := 208
const CELL_GAP := 12
const GRID_W := COLS * CELL_W + (COLS - 1) * CELL_GAP

var _summary: Label
var _refresh_all: Callable
var _faction_dd: Array[OptionButton] = []
var _tint_dd: Array[OptionButton] = []


func _ready() -> void:
	# A match captures the pointer; coming back here it has to be free again.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# The menu is one camera-less screen and will happily render at three hundred
	# frames a second, which on integrated graphics heats the chip up before the
	# match that needs it has started. Re-applied here as well as in Main so a
	# quality change made on the settings screen takes hold without a restart.
	Quality.active_views = 1
	Quality.apply_global()
	# The menu owns the menu track. Said every time this screen loads rather than
	# once at startup, because the match changes it and coming back has to change
	# it back — `Audio.play_music` ignores a request for what is already playing,
	# so this is safe to repeat.
	Audio.play_music("menu")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# The setup this machine last used, read back — the same file the playlist
	# screen keeps, because they are two ways of editing one match configuration.
	GameState.load_setup()
	GameState.chosen_teams = []   # a fresh visit re-picks teams from scratch
	# `-- --host` / `-- --join` walk straight into the lobby, already in a
	# session. Checked here rather than in an autoload's _ready because it CHANGES
	# SCENE, and doing that before the first scene has finished loading is how you
	# get a tree with two current scenes in it.
	#
	# DEFERRED, because the tree is still mid-way through adding THIS scene: a
	# scene change from inside `_ready` tries to detach a parent that is busy
	# attaching, which errors and leaves the menu up.
	if not Net.online() and Net.boot_from_cmdline():
		get_tree().change_scene_to_file.call_deferred(LOBBY_SCENE)
		return
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

	# THE MASTHEAD. A wordmark, a rule under it and a line saying what this is —
	# the rule is doing the work, because a title floating over a stack of
	# dropdowns reads as the first row of the stack rather than as a header.
	column.add_child(_label("QUADSQUAD", 60, ACCENT))
	column.add_child(_rule())
	column.add_child(_label("FOUR-PLAYER SPLIT SCREEN", 14, FAINT))
	column.add_child(_spacer(6))

	# MAP and MODE are DROPDOWNS now too, matching the settings below — one press
	# lands on any map instead of clicking through the whole roster.
	column.add_child(_heading("BATTLEFIELD"))
	var top := _grid()
	column.add_child(top)
	var map_dd := _dropdown(top, "MAP")
	var mode_dd := _dropdown(top, "GAME MODE")
	# UNIVERSE sits with MAP and MODE rather than down among the match settings,
	# because it is the same size of decision: it decides which classes, weapons
	# and factions the whole match is made of.
	var universe_dd := _dropdown(top, "UNIVERSE")
	# PLANET only means anything for the generated map, so it is DISABLED rather
	# than hidden on the others — the same rule VICTORY and CLASSES follow: an
	# option that vanishes is one nobody learns exists.
	var planet_dd := _dropdown(top, "PLANET")
	# ...and TIME OF DAY beside it, for the same reason and with the same rule:
	# it is the other half of choosing which world you are dropping into, and it
	# is only the generated one that has a night to drop into.
	var time_dd := _dropdown(top, "TIME OF DAY")
	# TIME TO KILL is next to it because the two answer the same question — what
	# kind of fight is this — and both change how every gun in the game feels.
	var ttk_dd := _dropdown(top, "TIME TO KILL")
	# The block is six controls on a four-wide grid, so the second row is padded
	# rather than left to centre itself under the first — a half row that centres
	# is the raggedness this grid exists to remove.
	_pad(top, 2)

	# The selected map + mode described in one line, since a dropdown shows only
	# the name.
	# ALIGNED TO THE GRID, not centred on the screen. It is a caption for the
	# block above it, and a centred line under a left-aligned block reads as
	# belonging to neither.
	var blurb := _caption()
	column.add_child(blurb)

	# The match settings, as labelled DROPDOWNS. They used to be chips you
	# pressed to cycle: to see the choices you had to walk through them, and to
	# go back one you went all the way round. A dropdown shows the whole range at
	# once and lets you land on any of it in one press, which matters most for
	# TEAMS and TEAM SIZE — the two settings people actually shop between.
	column.add_child(_heading("MATCH"))
	var settings := _grid()
	column.add_child(settings)
	var players_dd := _dropdown(settings, "PLAYERS")
	var teams_dd := _dropdown(settings, "TEAMS")
	var size_dd := _dropdown(settings, "TEAM SIZE")
	# CLASSES is where the gear comes from, and it is deliberately independent of
	# the mode: faction rosters in deathmatch and the buy screen in Conquest are
	# both perfectly good matches. Selecting a mode SEEDS it (Conquest opens on
	# faction, everything else on custom) and you are free to change it after.
	var victory_dd := _dropdown(settings, "VICTORY")
	var skill_dd := _dropdown(settings, "AI SKILL")
	var assist_dd := _dropdown(settings, "AIM ASSIST")
	var classes_dd := _dropdown(settings, "CLASSES")
	_pad(settings, 1)

	# --- WHO EACH SIDE IS, AND WHAT COLOUR THEY WEAR ------------------------
	#
	# A row per side, because a side is now picked INDEPENDENTLY of the setting:
	# the UNIVERSE dropdown above deals its own factions out in order, and these
	# let you change any of them, which is how UNSC ends up fighting the Republic.
	#
	# Four rows are always BUILT and the unused ones DISABLED rather than hidden,
	# the same rule every other row on this screen follows — an option that
	# vanishes is one nobody learns exists, and here it would also make the whole
	# grid reflow every time TEAMS changed.
	column.add_child(_heading("SIDES"))
	var sides := _grid()
	column.add_child(sides)
	for t in GameState.MAX_TEAMS:
		_faction_dd.append(_dropdown(sides, "SIDE %d" % (t + 1)))
		_tint_dd.append(_dropdown(sides, "SIDE %d COLOUR" % (t + 1)))

	_summary = _caption(16)
	column.add_child(_summary)
	column.add_child(_spacer(4))

	# THE ONE THING ON THE SCREEN THAT IS NOT A SETTING, so it is the one thing
	# that does not look like one: filled in the accent rather than framed in it.
	# It was a dark box the same weight as MAP ROTATION and QUIT beneath it,
	# which is a primary action a player has to go looking for.
	var start := _wide_button("START MATCH", 30)
	_make_primary(start)
	start.pressed.connect(_start.bind(false))
	column.add_child(start)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	var rotate_btn := _chip(row, "MAP ROTATION")
	rotate_btn.pressed.connect(_start.bind(true))
	# MULTIPLAYER sits beside MAP ROTATION rather than above START, because it is
	# the same size of decision as the settings around it: everything on this
	# screen still applies, and the lobby only adds who else is playing.
	var net_btn := _chip(row, "MULTIPLAYER")
	net_btn.pressed.connect(_open_lobby)
	var controls_btn := _chip(row, "CONTROLS")
	controls_btn.pressed.connect(func() -> void:
		GameState.settings_return = MENU_SCENE
		get_tree().change_scene_to_file(SETTINGS_SCENE))
	# BACK, not QUIT-only. This screen is one press in from the front screen now
	# (see `front.gd`), and a setup screen whose only way out is closing the game
	# is a dead end — the commonest thing a player does here is realise they
	# picked LOCAL when they meant ONLINE.
	var back_btn := _chip(row, "BACK")
	back_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file(FRONT_SCENE))
	var quit_btn := _chip(row, "QUIT")
	quit_btn.pressed.connect(func() -> void: get_tree().quit())

	# Each side's two dropdowns share a focus row, so left/right walks FACTION
	# then COLOUR for that side and up/down walks the sides.
	var side_rows: Array = []
	for t in GameState.MAX_TEAMS:
		side_rows.append([_faction_dd[t], _tint_dd[t]])

	_wire_focus([
		[map_dd, mode_dd],
		[universe_dd, planet_dd, time_dd, ttk_dd],
		[players_dd, teams_dd, size_dd],
		[victory_dd, skill_dd, assist_dd],
		[classes_dd],
	] + side_rows + [
		[start],
		[rotate_btn, net_btn, controls_btn, back_btn, quit_btn],
	])

	column.add_child(_label(
		"Left stick / d-pad to move    A to select or change    P1..P4 are pads 1..4",
		15, FAINT))

	# One refresh closure that everything calls, so no control has to know what
	# any other one displays.
	_refresh_all = func() -> void:
		_fill(map_dd, _map_items(), GameState.map_index)
		map_dd.disabled = GameState.massive()
		_fill(mode_dd, _mode_items(), GameState.mode)
		_fill(universe_dd, _universe_items(), GameState.universe)
		# The PLANET row now only means anything for the ROLLED generated map:
		# every world is its own map row, so on one of those this control would be
		# a second opinion about which world gets built. It shows the map's own
		# answer and goes dead, rather than lying.
		var stated := GameState.map_planet()
		_fill(planet_dd, _planet_items(),
			stated + 1 if stated >= 0 else GameState.planet + 1)   # RANDOM is item 0
		planet_dd.disabled = not GameState.map_is_procedural() or stated >= 0
		_fill(time_dd, _time_items(), GameState.time_of_day)
		time_dd.disabled = not GameState.map_is_procedural()
		_fill(ttk_dd, _ttk_items(), GameState.ttk)
		blurb.text = "%s   —   %s" % [GameState.map_blurb(), GameState.mode_blurb()]
		# CONQUEST is Republic vs Separatist: exactly two sides, never a free-for-all.
		var conquest: bool = GameState.mode == GameState.Mode.CONQUEST
		if conquest:
			GameState.free_for_all = false
			GameState.team_count = 2
		# MASSIVE is two sides on generated ground and nothing else: the map row
		# is pinned to the procedural world (the hand-laid arenas are eight-body
		# maps) and the sides are fixed at two, because fifty a side across four
		# teams is two hundred bodies and no machine here is having that.
		var massive: bool = GameState.massive()
		if massive:
			GameState.free_for_all = false
			GameState.team_count = 2
			GameState.map_index = GameState.procedural_map_index()
			if not GameState.MASSIVE_SIZES.has(GameState.team_size):
				GameState.team_size = GameState.MASSIVE_DEFAULT
		# Every dropdown is REBUILT here rather than just re-selected, because
		# what is legal changes as you go: team size cannot drop below the humans
		# already standing in a team, and free-for-all needs a second player.
		# Rebuilding is a few items and happens on a press, never per frame.
		_fill(players_dd, _player_items(), GameState.human_players - GameState.MIN_HUMANS)
		_fill(teams_dd, _team_items(), _team_choice())
		teams_dd.set_item_disabled(_FREE_FOR_ALL_ITEM, GameState.human_players < 2)
		teams_dd.disabled = conquest or massive   # both are two-sided
		var sizes := _size_items()
		_fill(size_dd, sizes, sizes.find(_size_label(GameState.team_size)))
		size_dd.disabled = GameState.free_for_all   # every side is one player
		# VICTORY: the threshold to win, in the mode's own unit. ROYALE is last
		# side standing — there is no number to tune, so the row is disabled.
		var vics := _victory_values()
		_fill(victory_dd, _victory_items(), maxi(vics.find(GameState.score_limit()), 0))
		victory_dd.disabled = GameState.mode == GameState.Mode.ROYALE
		for t in GameState.MAX_TEAMS:
			var live: bool = t < GameState.active_teams()
			_fill(_faction_dd[t], _faction_items(),
				GameState.team_faction[t] if t < GameState.team_faction.size() else 0)
			_fill(_tint_dd[t], _tint_items(),
				GameState.team_tint[t] if t < GameState.team_tint.size() else 0)
			# FREE FOR ALL is one side per player and they are not factions you
			# choose between, so the rows go dead rather than lying about it.
			_faction_dd[t].disabled = not live or GameState.free_for_all
			_tint_dd[t].disabled = not live
		_fill(skill_dd, _skill_items(), GameState.ai_skill)
		_fill(assist_dd, _assist_items(), GameState.aim_assist)
		# ROYALE is neither a shop nor a roster — everything you fight with is
		# scavenged — so the row is disabled rather than hidden, the same rule
		# VICTORY follows: an option that vanishes is one nobody learns exists.
		_fill(classes_dd, _classes_items(), GameState.class_mode)
		classes_dd.disabled = GameState.mode == GameState.Mode.ROYALE
		_summary.text = _describe()

	map_dd.item_selected.connect(func(i: int) -> void:
		GameState.map_index = i
		_refresh_all.call())
	mode_dd.item_selected.connect(func(i: int) -> void:
		GameState.mode = i
		# A mode SEEDS the class source rather than owning it: Conquest opens on
		# its faction rosters, everything else on the buy screen, and the CLASSES
		# row below is free to say otherwise.
		GameState.class_mode = GameState.default_class_mode(i)
		_refresh_all.call())
	planet_dd.item_selected.connect(func(i: int) -> void:
		# Item 0 is RANDOM, which is GameState.RANDOM_PLANET (-1).
		GameState.planet = i - 1
		_refresh_all.call())
	time_dd.item_selected.connect(func(i: int) -> void:
		GameState.time_of_day = i
		_refresh_all.call())
	universe_dd.item_selected.connect(func(i: int) -> void:
		# Changing universe changes who the sides ARE, so a team picked on the
		# old roster means nothing — team-select is re-run from scratch anyway,
		# but clearing here keeps the summary line honest in the meantime.
		GameState.universe = i
		GameState.chosen_teams = []
		_refresh_all.call())
	ttk_dd.item_selected.connect(func(i: int) -> void:
		GameState.ttk = i
		_refresh_all.call())
	classes_dd.item_selected.connect(func(i: int) -> void:
		GameState.class_mode = i
		_refresh_all.call())
	victory_dd.item_selected.connect(func(i: int) -> void:
		GameState.score_targets[GameState.mode] = _victory_values()[i]
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
		# Indexed into the SAME list the dropdown was filled from. It used to add
		# the index to the floor, which only works while the sizes are contiguous
		# integers — the moment the ladder skips (8 to 10 to 12) that arithmetic
		# picks a different number than the one that was clicked.
		var values := _size_values()
		GameState.team_size = int(values[clampi(i, 0, values.size() - 1)])
		_refresh_all.call())
	for t in GameState.MAX_TEAMS:
		# `bind` the side, so four dropdowns share one handler rather than four
		# closures that each capture a different loop variable — the classic way
		# to end up with every row editing side 3.
		_faction_dd[t].item_selected.connect(_pick_faction.bind(t))
		_tint_dd[t].item_selected.connect(_pick_tint.bind(t))
	skill_dd.item_selected.connect(func(i: int) -> void:
		GameState.ai_skill = i
		_refresh_all.call())
	assist_dd.item_selected.connect(func(i: int) -> void:
		GameState.aim_assist = i
		_refresh_all.call())

	_fix_setup()
	_refresh_all.call()
	map_dd.grab_focus()


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


func _map_items() -> PackedStringArray:
	var out := PackedStringArray()
	for m in GameState.MAPS:
		out.append(str(m["name"]))
	return out


func _mode_items() -> PackedStringArray:
	var out := PackedStringArray()
	for i in GameState.MODE_NAMES.size():
		out.append(str(GameState.MODE_NAMES[i]))
	return out


# What the current mode may play to, in its own unit — kills for deathmatch,
# seconds of control for zones. ROYALE is not tunable (last side standing), so
# its dropdown is disabled and never reads this.
const SCORE_CHOICES := {
	GameState.Mode.DEATHMATCH: [10, 25, 50, 75, 100],
	GameState.Mode.ZONES: [60, 120, 200, 300],
	GameState.Mode.CONQUEST: [75, 150, 250, 400],   # starting reinforcements per side
	# MASSIVE counts kills like deathmatch, but a hundred bodies trade them far
	# faster: twenty-five would be over before the crowd had finished walking
	# into each other.
	GameState.Mode.MASSIVE: [100, 200, 350, 500],
}


func _victory_values() -> Array:
	return SCORE_CHOICES.get(GameState.mode, [GameState.score_limit()])


func _victory_items() -> PackedStringArray:
	var out := PackedStringArray()
	var unit := "KILLS"
	if GameState.mode == GameState.Mode.ZONES:
		unit = "SECONDS"
	elif GameState.mode == GameState.Mode.CONQUEST:
		unit = "REINFORCEMENTS"
	for v in _victory_values():
		out.append("%d %s" % [v, unit])
	return out


## Team size starts at the biggest team's human headcount: a team can never be
## smaller than the people already standing in it.
##
## MASSIVE has its own ladder entirely (`GameState.MASSIVE_SIZES`): the ordinary
## one runs to six, and the whole point of that mode is the numbers. The smaller
## rungs are offered because the frame cost of a hundred bodies is real and
## measured — a couch that cannot hold fifty a side should be able to play
## twenty-five.
func _size_items() -> PackedStringArray:
	var out := PackedStringArray()
	if GameState.massive():
		for n: int in GameState.MASSIVE_SIZES:
			out.append(_size_label(n))
		return out
	for n: int in _size_values():
		out.append(_size_label(n))
	return out


## The sizes this match may legally pick, in order — the offered ladder, minus
## anything below the humans already standing in a team. Everything that fills or
## reads the dropdown indexes THIS, so the list and the value cannot disagree.
func _size_values() -> Array:
	if GameState.massive():
		return GameState.MASSIVE_SIZES
	var floor_size := _smallest_team_size()
	var out: Array = []
	for n: int in GameState.TEAM_SIZES:
		if n >= floor_size:
			out.append(n)
	# Never offer nothing: if the humans outnumber every rung, the floor itself is
	# the only legal size and has to be on the list.
	if out.is_empty():
		out.append(floor_size)
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


## Every faction in the game, labelled with its SETTING as well as its name —
## "NECRONS" alone does not say which game you are looking at once two settings
## can be on the field at once.
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
	_refresh_all.call()


func _pick_tint(index: int, team: int) -> void:
	if team < GameState.team_tint.size():
		GameState.team_tint[team] = index
		GameState.refresh_sides()
	_refresh_all.call()


func _universe_items() -> PackedStringArray:
	var out := PackedStringArray()
	for u in Loadout.UNIVERSES:
		out.append(str(u["name"]))
	return out


## RANDOM first, then every world. Random is the default because a generated
## map that is a different world each time is the whole point of having one.
func _planet_items() -> PackedStringArray:
	var out := PackedStringArray(["RANDOM"])
	for i in PlanetMap.PLANET_NAMES.size():
		out.append(str(PlanetMap.PLANET_NAMES[i]))
	return out


func _time_items() -> PackedStringArray:
	var out := PackedStringArray()
	for i in GameState.TIME_NAMES.size():
		out.append(str(GameState.TIME_NAMES[i]))
	return out


func _ttk_items() -> PackedStringArray:
	var out := PackedStringArray()
	for i in GameState.TTK_NAMES.size():
		out.append(str(GameState.TTK_NAMES[i]))
	return out


func _classes_items() -> PackedStringArray:
	var out := PackedStringArray()
	for i in GameState.CLASS_MODE_NAMES.size():
		out.append(str(GameState.CLASS_MODE_NAMES[i]))
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
	if GameState.massive():
		return   # its own ladder, and its own two-sided shape
	if not GameState.free_for_all:
		GameState.team_size = maxi(GameState.team_size, _smallest_team_size())
	# COMING BACK OUT OF MASSIVE, the size is still 50 — its ladder is not this
	# one. Without this the ordinary modes silently run at fifty a side, over
	# their own MAX_TEAM_SIZE, and the dropdown shows no selection at all because
	# nothing in its list matches.
	if not GameState.TEAM_SIZES.has(GameState.team_size):
		var values := _size_values()
		var best: int = int(values[0])
		for n: int in values:
			if n <= GameState.team_size:
				best = n
		GameState.team_size = best


## Spell out what you'll actually get, since "3 humans across 2 teams at team
## size 3" is not obviously a 3v3 with three bots in it.
func _describe() -> String:
	var gear := "   ·   %s" % ("faction classes" if GameState.faction_classes()
		else "custom loadouts")
	if GameState.mode == GameState.Mode.ROYALE:
		gear = "   ·   everything scavenged"
	# The two settings that change what the match is MADE of, spelled out: which
	# armoury is on the buy screen and how long a body lasts under it.
	gear += "   ·   %s   ·   %s" % [
		Loadout.UNIVERSES[GameState.universe]["blurb"],
		GameState.TTK_BLURBS[GameState.ttk]]
	if GameState.free_for_all:
		return "%d players, every one for themselves — no AI%s" % [
			GameState.human_players, gear]
	var ai := 0
	var sides := PackedStringArray()
	for t in GameState.active_teams():
		ai += GameState.ai_needed(t)
		sides.append(str(GameState.team_size))
	return "%d human%s + %d AI     %s%s" % [
		GameState.human_players, "" if GameState.human_players == 1 else "s",
		ai, " v ".join(sides), gear]


## START goes to the TEAM-SELECT screen first, where each player picks a side —
## unless it is free-for-all, where every player is already their own team and
## there is nothing to pick, so it drops straight into the match.
## Leaving for the lobby drops any session that is still open. Coming back here
## is the one unambiguous "I am done being online" in the game, and a socket left
## up would keep answering discovery for a machine sitting on the front screen.
func _open_lobby() -> void:
	Audio.play("ui_accept")
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _start(rotate: bool) -> void:
	Audio.play("ui_accept")
	GameState.save_setup()   # what was set up here is what this machine opens on next
	Net.leave()   # a local match is a local match, whatever was open before
	GameState.rotate_maps = rotate
	GameState.chosen_teams = []   # cleared; team-select fills it, FFA leaves it
	if GameState.free_for_all:
		get_tree().change_scene_to_file(GAME_SCENE)
	else:
		get_tree().change_scene_to_file(TEAM_SELECT_SCENE)


# --- widgets -----------------------------------------------------------------

## One labelled setting dropdown: a caption above the control so the value
## itself does not have to carry its own name ("TEAMS  3" in a button caption
## reads as one string and is unreadable at a glance across a room).
## One settings block's grid. Every block uses the SAME four columns and the
## same cell width, which is the whole of why the screen lines up (see COLS).
## A caption line under a block, on the grid's own left edge and width.
func _caption(size := 15) -> Label:
	var l := _label("", size, Color(0.64, 0.68, 0.75))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.custom_minimum_size = Vector2(GRID_W, 0)
	return l


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = COLS
	g.add_theme_constant_override("h_separation", CELL_GAP)
	g.add_theme_constant_override("v_separation", 10)
	return g


## Fill out the tail of a block's last row so it does not centre itself under
## the row above.
func _pad(grid: GridContainer, cells: int) -> void:
	for _i in cells:
		var blank := Control.new()
		blank.custom_minimum_size = Vector2(CELL_W, 0)
		blank.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(blank)


## A block heading. Left-aligned to the grid rather than centred, because it
## labels the block under it — a centred caption over a left-aligned grid reads
## as a title for the whole screen.
func _heading(text: String) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(GRID_W, 0)
	box.add_theme_constant_override("separation", 3)
	var l := _label(text, 13, ACCENT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(l)
	var line := ColorRect.new()
	line.color = Color(ACCENT, 0.22)
	line.custom_minimum_size = Vector2(GRID_W, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	return box


## The rule under the wordmark.
func _rule() -> Control:
	var line := ColorRect.new()
	line.color = Color(ACCENT, 0.45)
	line.custom_minimum_size = Vector2(GRID_W * 0.42, 2)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _dropdown(parent: GridContainer, caption: String) -> OptionButton:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 2)
	parent.add_child(cell)
	cell.add_child(_label(caption, 13, FAINT))
	var b := OptionButton.new()
	b.custom_minimum_size = Vector2(CELL_W, 38)
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


## Fill a button in the accent instead of framing it. Reserved for the ONE
## action a screen exists to perform — two primaries is no primary.
func _make_primary(b: Button) -> void:
	b.add_theme_color_override("font_color", Color(0.05, 0.07, 0.10))
	b.add_theme_color_override("font_focus_color", Color(0.03, 0.05, 0.08))
	b.add_theme_color_override("font_hover_color", Color(0.03, 0.05, 0.08))
	for state in ["normal", "hover", "focus", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = ACCENT if state == "normal" else ACCENT.lightened(0.18)
		sb.set_corner_radius_all(5)
		sb.set_content_margin_all(10)
		# Focus is carried by a BRIGHTER fill and a light edge rather than by the
		# frame colour every other control uses — on a filled button an accent
		# border against an accent fill is invisible.
		if state != "normal":
			sb.border_color = Color(1, 1, 1, 0.85)
			sb.set_border_width_all(2)
		b.add_theme_stylebox_override(state, sb)


func _wide_button(text: String, size: int) -> Button:
	var b := _framed(Button.new())
	b.text = text
	b.custom_minimum_size = Vector2(GRID_W, 56)   # exactly the settings grid
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
	# EVERY framed control on this screen is built here, so this one line gives
	# the whole menu a voice: a blip as the selection moves, whichever pad or
	# key moved it. `focus_entered` rather than an input handler, because focus
	# is the thing that actually changed and it fires for mouse, key and pad
	# alike — the same reason `_wire_focus` states neighbours rather than
	# trusting Godot's geometric search.
	b.focus_entered.connect(_focus_blip)
	return b


func _focus_blip() -> void:
	Audio.play("ui_move")


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
