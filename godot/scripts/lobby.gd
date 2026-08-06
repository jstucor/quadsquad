extends Control
## THE LOBBY — host a session, find one, or join one by address, then sit in it
## until the host says go.
##
## It is deliberately built out of the MENU'S OWN furniture (the same panels,
## dropdowns and focus wiring) rather than a screen of its own style: this is the
## front screen with one more decision on it, and a lobby that looks like a
## different game is a lobby that reads as a different game.
##
## THREE PAGES, ONE SCREEN. Choosing (host or join), browsing (what is on this
## network), and the session itself. They are pages and not scenes because
## `Net` is an autoload holding a live socket — changing scene between them would
## work, and it would also mean every connection callback has to survive a scene
## change to land somewhere useful.
##
## WHO DRIVES IT: the machine, on the `ui_*` actions, exactly like the main menu.
## Every pad and the keyboard work it (see `Controls.apply_ui_pad`), because in a
## lobby there is one decision per MACHINE — how many of us are sitting here and
## which side we are on — and that is not a thing four people press separately.
## Per-seat choices happen on the deploy screen, in the match, where they belong.

const FRONT_SCENE := "res://scenes/front.tscn"
const GAME_SCENE := "res://scenes/main.tscn"

const BG_COLOR := Color(0.06, 0.07, 0.09)
const ACCENT := Color(0.45, 0.72, 1.0)
const DIM := Color(0.62, 0.66, 0.72)
const FAINT := Color(0.42, 0.46, 0.52)
const PANEL := Color(0.10, 0.12, 0.15, 0.9)
const PANEL_EDGE := Color(0.24, 0.30, 0.38)
const WARN := Color(1.0, 0.62, 0.4)

## ONLY THE MODES THAT ARE ACTUALLY REPLICATED. Deathmatch needs bodies and a
## score, and both are synced; Zones adds one circle whose position and holder
## the host decides. Conquest, Royale and Massive each need a whole system of
## their own carried over the wire — capture posts, crates on the ground, a
## hundred bodies — and offering a mode that half works is worse than not
## offering it, because the failure looks like a bug in the game rather than a
## feature that is not finished. See NETWORKING in README.md for what each needs.
const ONLINE_MODES: Array[int] = [GameState.Mode.DEATHMATCH, GameState.Mode.ZONES]

enum Page { CHOOSE, BROWSE, SESSION }

var _page := Page.CHOOSE
var _body: VBoxContainer
var _status: Label
var _locals := 1
var _team := Net.TEAM_AUTO
var _address := "127.0.0.1"
var _servers: Array = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Quality.active_views = 1
	Quality.apply_global()
	Audio.play_music("menu")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Methods of this node, never lambdas: `Net` is an autoload that outlives
	# every screen, and a lambda with no target object would go on firing into
	# this freed lobby for the rest of the session (house rule 11).
	Net.roster_changed.connect(_on_roster_changed)
	Net.session_joined.connect(_on_session_joined)
	Net.session_failed.connect(_on_session_failed)
	Net.browse_result.connect(_on_browse_result)
	Net.launching.connect(_on_launching)
	# Coming back from a finished match: the session is still up and this screen
	# should open on it rather than asking whether to host again.
	_page = Page.SESSION if Net.online() else Page.CHOOSE
	_build()


func _exit_tree() -> void:
	# Leaving to the MENU drops the session; leaving to the MATCH must not. The
	# scene being changed is what tells them apart, so the disconnect is done by
	# whoever changes it (`_back`), not here.
	pass


# --- layout ------------------------------------------------------------------

func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

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
	column.add_child(_label("MULTIPLAYER", 46, ACCENT))

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	_body.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_body)

	_status = _label("", 17, DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status)

	match _page:
		Page.CHOOSE: _build_choose()
		Page.BROWSE: _build_browse()
		Page.SESSION: _build_session()


## Page one: how many of us are at this machine, which side we want, and whether
## we are opening a session or looking for one.
func _build_choose() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	_body.add_child(grid)

	var seats := _dropdown(grid, "PLAYERS AT THIS MACHINE")
	_fill(seats, _seat_items(), _locals - 1)
	seats.item_selected.connect(_on_seats_chosen)

	var side := _dropdown(grid, "SIDE")
	_fill(side, _team_items(), 0 if _team == Net.TEAM_AUTO else _team + 1)
	side.item_selected.connect(_on_side_chosen)

	_body.add_child(_spacer(6))
	var host_btn := _wide_button("HOST A SESSION", 26)
	host_btn.pressed.connect(_on_host)
	_body.add_child(host_btn)

	var find_btn := _wide_button("FIND A SESSION", 26)
	find_btn.pressed.connect(_on_find)
	_body.add_child(find_btn)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(row)
	var back := _chip(row, "BACK")
	back.pressed.connect(_back)

	_status.text = "Everyone must be on the same network"
	_wire_focus([[seats, side], [host_btn], [find_btn], [back]])


## Page two: what is on this network. The address box is kept alongside rather
## than behind another press — broadcast discovery does not cross a subnet or a
## router, and when it fails the answer is always "type the IP", so that has to
## be visible at the moment it is needed and not one page further in.
func _build_browse() -> void:
	var found := VBoxContainer.new()
	found.add_theme_constant_override("separation", 4)
	_body.add_child(found)

	var rows: Array = []
	if _servers.is_empty():
		found.add_child(_label("No sessions found on this network", 18, FAINT))
	for server: Dictionary in _servers:
		var text := "%s   —   %s / %s   —   %d of %d" % [
			str(server.get("name", "?")), str(server.get("map", "?")),
			str(server.get("mode", "?")), int(server.get("players", 0)),
			int(server.get("max", 0))]
		var btn := _wide_button(text, 20)
		btn.pressed.connect(_on_join_found.bind(str(server["address"])))
		found.add_child(btn)
		rows.append([btn])

	_body.add_child(_spacer(6))
	var addr_row := HBoxContainer.new()
	addr_row.add_theme_constant_override("separation", 8)
	addr_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(addr_row)
	addr_row.add_child(_label("ADDRESS", 15, FAINT))
	var field := LineEdit.new()
	field.text = _address
	field.custom_minimum_size = Vector2(220, 0)
	field.text_changed.connect(_on_address_typed)
	addr_row.add_child(field)
	var go := _chip(addr_row, "JOIN")
	go.pressed.connect(_on_join_typed)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(row)
	var again := _chip(row, "SEARCH AGAIN")
	again.pressed.connect(_on_find)
	var back := _chip(row, "BACK")
	back.pressed.connect(_to_choose)

	rows.append([field, go])
	rows.append([again, back])
	_wire_focus(rows)


## Page three: who is in, what we are about to play, and (host only) the button.
func _build_session() -> void:
	if not Net.online():
		_page = Page.CHOOSE
		_build_choose()
		return

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _panel(PANEL_EDGE))
	_body.add_child(frame)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 2)
	frame.add_child(inner)
	inner.add_child(_label("IN THE SESSION", 14, FAINT))
	for id: int in Net.roster():
		var team := Net.team_of(id)
		var line := _label("%s   —   %s%s" % [
			Net.name_of(id),
			GameState.team_names[team % GameState.team_names.size()],
			"   (you)" if Net.owns(id) else ""], 18,
			GameState.team_colors[team % GameState.team_colors.size()])
		inner.add_child(line)

	_body.add_child(_spacer(4))
	var rows: Array = []
	if Net.is_host():
		# The host owns the match settings, because there is only one match. A
		# client showing editable dropdowns it cannot apply is a screen that lies.
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 8)
		_body.add_child(grid)
		var map_dd := _dropdown(grid, "MAP")
		_fill(map_dd, _map_items(), GameState.map_index)
		map_dd.item_selected.connect(_on_map_chosen)
		var mode_dd := _dropdown(grid, "GAME MODE")
		_fill(mode_dd, _mode_items(), maxi(ONLINE_MODES.find(GameState.mode), 0))
		mode_dd.item_selected.connect(_on_mode_chosen)
		var size_dd := _dropdown(grid, "TEAM SIZE")
		_fill(size_dd, _size_items(), GameState.team_size - GameState.MIN_TEAM_SIZE)
		size_dd.item_selected.connect(_on_size_chosen)
		rows.append([map_dd, mode_dd, size_dd])

		var start := _wide_button("START MATCH", 28)
		start.pressed.connect(_on_start)
		_body.add_child(start)
		rows.append([start])
		_status.text = "%d player%s in.  AI will fill each side to %d." % [
			Net.player_count(), "" if Net.player_count() == 1 else "s",
			GameState.team_size]
	else:
		_body.add_child(_label("Waiting for the host to start…", 20, DIM))
		_status.text = "%s / %s" % [
			str(GameState.MAPS[GameState.map_index]["name"]),
			str(GameState.MODE_NAMES.get(GameState.mode, "?"))]

	var side := _dropdown_row("SIDE", _team_items(),
		0 if _team == Net.TEAM_AUTO else _team + 1)
	side.item_selected.connect(_on_side_chosen)
	rows.append([side])

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(row)
	var leave := _chip(row, "LEAVE SESSION")
	leave.pressed.connect(_back)
	rows.append([leave])
	_wire_focus(rows)


# --- actions -----------------------------------------------------------------

func _on_seats_chosen(index: int) -> void:
	_locals = index + 1
	Audio.play("ui_move")


func _on_side_chosen(index: int) -> void:
	_team = Net.TEAM_AUTO if index == 0 else index - 1
	Audio.play("ui_move")
	if Net.online():
		Net.choose_team(_team)


func _on_address_typed(text: String) -> void:
	_address = text


func _on_host() -> void:
	Audio.play("ui_accept")
	# THIS MACHINE'S SPLIT-SCREEN COUNT IS SET HERE AND NOWHERE ELSE. It is the
	# one match setting that is genuinely per-machine (it sizes the viewport grid
	# and prices the frame), so it is deliberately not in the host's config.
	GameState.human_players = _locals
	if GameState.mode not in ONLINE_MODES:
		GameState.mode = GameState.Mode.DEATHMATCH
	GameState.free_for_all = false
	if Net.host(_locals, _machine_name(), _team):
		_page = Page.SESSION
		_build()


func _on_find() -> void:
	Audio.play("ui_accept")
	_servers = []
	_page = Page.BROWSE
	_build()
	_status.text = "Searching…"
	Net.browse()


func _on_join_found(address: String) -> void:
	_address = address
	_on_join_typed()


func _on_join_typed() -> void:
	Audio.play("ui_accept")
	GameState.human_players = _locals
	_status.text = "Connecting to %s…" % _address
	Net.join(_address, _locals, _machine_name(), _team)


func _on_start() -> void:
	Audio.play("ui_accept")
	Net.start_match()


func _to_choose() -> void:
	_page = Page.CHOOSE
	_build()


func _back() -> void:
	Audio.play("ui_back")
	if _page == Page.SESSION:
		Net.leave()
		_page = Page.CHOOSE
		_build()
		return
	# OUT TO THE FRONT SCREEN, which is where ONLINE PLAY is entered from. It
	# used to go to the match-setup menu, which is a screen an online player has
	# never seen — a BACK that lands somewhere new reads as the game having got
	# lost rather than as having gone back.
	get_tree().change_scene_to_file(FRONT_SCENE)


# --- Net callbacks -----------------------------------------------------------

func _on_roster_changed() -> void:
	if _page == Page.SESSION:
		_build()


func _on_session_joined() -> void:
	_page = Page.SESSION
	_build()


func _on_session_failed(reason: String) -> void:
	_page = Page.CHOOSE
	_build()
	_status.text = reason
	_status.add_theme_color_override("font_color", WARN)
	Audio.play("ui_back")


func _on_browse_result(servers: Array) -> void:
	_servers = servers
	if _page == Page.BROWSE:
		_build()


## The host said go. Every machine changes scene off this one signal, host
## included — `Net.start_match` emits it locally as well as sending it, so there
## is exactly one code path into a networked match.
func _on_launching() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _machine_name() -> String:
	var n := OS.get_environment("USER")
	if n.is_empty():
		n = OS.get_environment("USERNAME")
	return n.to_upper() if not n.is_empty() else "PLAYER"


func _on_map_chosen(index: int) -> void:
	GameState.map_index = index
	Audio.play("ui_move")
	_build()


func _on_mode_chosen(index: int) -> void:
	GameState.mode = ONLINE_MODES[index]
	GameState.seed_class_mode(GameState.mode)
	Audio.play("ui_move")
	_build()


func _on_size_chosen(index: int) -> void:
	GameState.team_size = GameState.MIN_TEAM_SIZE + index
	Audio.play("ui_move")
	_build()


# --- items -------------------------------------------------------------------

func _seat_items() -> PackedStringArray:
	var items := PackedStringArray()
	for n in range(1, Net.MAX_LOCAL + 1):
		items.append("%d" % n if n > 1 else "1  (just me)")
	return items


func _team_items() -> PackedStringArray:
	var items := PackedStringArray(["AUTO"])
	for t in mini(GameState.team_count, GameState.MAX_TEAMS):
		items.append(GameState.team_names[t])
	return items


func _map_items() -> PackedStringArray:
	var items := PackedStringArray()
	for m in GameState.MAPS:
		items.append(str(m["name"]))
	return items


func _mode_items() -> PackedStringArray:
	var items := PackedStringArray()
	for m: int in ONLINE_MODES:
		items.append(str(GameState.MODE_NAMES.get(m, "?")))
	return items


func _size_items() -> PackedStringArray:
	var items := PackedStringArray()
	for n in range(GameState.MIN_TEAM_SIZE, GameState.MAX_TEAM_SIZE + 1):
		items.append("%d a side" % n)
	return items


# --- widgets -----------------------------------------------------------------
#
# Same shapes as menu.gd's, deliberately: this screen is the front screen with
# one more decision on it.

func _dropdown(parent: GridContainer, caption: String) -> OptionButton:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 2)
	parent.add_child(cell)
	cell.add_child(_label(caption, 13, FAINT))
	var b := OptionButton.new()
	b.add_theme_font_size_override("font_size", 19)
	b.fit_to_longest_item = true
	cell.add_child(b)
	return b


func _dropdown_row(caption: String, items: PackedStringArray,
		choose: int) -> OptionButton:
	var grid := GridContainer.new()
	grid.columns = 1
	_body.add_child(grid)
	var b := _dropdown(grid, caption)
	_fill(b, items, choose)
	return b


func _fill(b: OptionButton, items: PackedStringArray, choose: int) -> void:
	b.clear()
	for item in items:
		b.add_item(item)
	if b.item_count > 0:
		b.select(clampi(choose, 0, b.item_count - 1))


func _chip(parent: HBoxContainer, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 17)
	parent.add_child(b)
	return b


func _wide_button(text: String, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(460, 0)
	return b


func _spacer(h: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s


func _panel(edge: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PANEL
	box.border_color = edge
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## Godot's geometric focus search gets a laid-out menu wrong — see the note in
## menu.gd, which is where this rule was learned. Neighbours are stated, and every
## direction wraps: a press that appears to do nothing reads as a hung screen.
func _wire_focus(rows: Array) -> void:
	if rows.is_empty():
		return
	for r in rows.size():
		var row: Array = rows[r]
		for i in row.size():
			var c: Control = row[i]
			c.focus_neighbor_left = c.get_path_to(row[(i - 1 + row.size()) % row.size()])
			c.focus_neighbor_right = c.get_path_to(row[(i + 1) % row.size()])
			c.focus_neighbor_top = c.get_path_to(_across(rows, r - 1, i))
			c.focus_neighbor_bottom = c.get_path_to(_across(rows, r + 1, i))
	var first: Control = (rows[0] as Array)[0]
	first.call_deferred("grab_focus")


func _across(rows: Array, r: int, i: int) -> Control:
	var row: Array = rows[(r + rows.size()) % rows.size()]
	return row[mini(i, row.size() - 1)]
