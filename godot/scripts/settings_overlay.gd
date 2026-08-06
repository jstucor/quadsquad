extends Control
## The in-game settings bar, one per player viewport. START (pad) or ESC
## (keyboard) opens it over that player's own screen while the other three keep
## playing — so it is driven by THIS player's device alone, polled per frame the
## way the buy screen is, never by the device-wide ui_* actions four players
## would fight over.
##
## It edits the three things a player wants to change without leaving the match:
## LOOK SENSITIVITY and AIM ASSIST strength (per-device, in Controls), and any
## button binding (rebound in place, exactly like the menu's controls screen).
## Whole configs can be stored under a custom name and loaded onto whatever
## device a player ends up on next match — that is the PRESET rows. All of the
## storage lives in Controls; this file is only the screen and its navigation.
##
## While it is open the player stands still (Player.settings_open), like the map.

const FRONT_SCENE := "res://scenes/front.tscn"
const PLAYLIST_SCENE := "res://scenes/playlist.tscn"
const LOBBY_SCENE := "res://scenes/lobby.tscn"

const ACCENT := Color(0.45, 0.72, 1.0)
const WARN := Color(1.0, 0.55, 0.45)
const DIM := Color(0.70, 0.74, 0.80)
const FAINT := Color(0.48, 0.52, 0.58)
const LISTEN_COLOR := Color(1.0, 0.78, 0.35)
const OK_COLOR := Color(0.55, 0.88, 0.55)

const SENS_STEP := 0.1
const ASSIST_STEP := 0.1

# The on-screen keyboard for naming a preset: a flat strip the player scrolls
# with left/right (up/down jumps a row's worth for speed), plus two action cells.
const NAME_CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -"
const CELL_DEL := "DEL"
const CELL_OK := "OK"
const NAME_MAX := 14

## CONFIRM is its own mode rather than a second row, because the thing it guards
## is the only irreversible action on this screen: everything else here can be
## undone by doing it again, and ending the match cannot.
enum Mode { NAV, LISTEN, NAME, CONFIRM }

# One row per line of the NAV screen. `kind` drives what accept/left/right do.
enum Kind { SENS, ASSIST, BIND, PROFILE, LOAD, SAVE, DELETE, RESET, RESUME, QUIT }

var player: Player
var device := -1

var _open := false
var _mode := Mode.NAV
var _row := 0
var _rows: Array[Dictionary] = []
var _profile_idx := 0        # which saved profile the PROFILE/LOAD/DELETE rows act on

var _listen_id := ""
var _listen_armed := false

var _name_buf := ""
var _name_cell := 0          # index into NAME_CHARS, then DEL, then OK

var _prev := {}              # virtual-button -> down last frame, for edge detection
## _input runs BEFORE _process in a frame, so a mode change made there (a rebind
## completing on a key that is also a nav key, or ESC leaving the name entry)
## would otherwise let _process act on that same press in the new mode. This eats
## one frame of edges after any such transition.
var _swallow_edges := false

var _bg: ColorRect
var _panel: PanelContainer
var _body: VBoxContainer
var _title: Label
var _hint: Label


## Main calls this right after it builds the player, so the device is known and
## the row list (which differs for a pad and the keyboard) can be built once.
func setup(p: Player) -> void:
	player = p
	device = p.input_device
	# THIS SCREEN OUTRANKS THE PAUSE IT TAKES. Solo, opening it stops the tree —
	# so if this node were pausable it would stop with everything else and there
	# would be no way to close it, no way to resume, and no way to quit: the game
	# would be frozen by the one control that exists to unfreeze it. It has to
	# run unpaused as well (that is how it sees the START press in the first
	# place), which is ALWAYS rather than WHEN_PAUSED.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# THE CACHED DEVICE HAS TO FOLLOW THE BODY. This screen is per-device by
	# design — its bindings, its sensitivity and its presets are all that device's
	# — so it keeps a copy, and a copy is a thing that goes stale. A player who
	# picks up a spare controller mid-match would otherwise be editing the
	# settings of the pad whose batteries just died.
	p.device_changed.connect(_on_device_changed)
	_build_ui()
	visible = false


func _on_device_changed(new_device: int) -> void:
	device = new_device
	_prev.clear()          # the old pad's held buttons are not this one's edges
	if _open:
		_rebuild_rows()    # a pad and a keyboard do not offer the same rows
		_render()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_bg = ColorRect.new()
	_bg.color = Color(0.04, 0.05, 0.07, 0.86)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)

	_title = _label("SETTINGS", 22, ACCENT)
	column.add_child(_title)
	column.add_child(_spacer(6))

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 1)
	column.add_child(_body)

	column.add_child(_spacer(6))
	_hint = _label("", 12, FAINT)
	column.add_child(_hint)


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	# Something ended the match state the overlay lives in — dying, opening the
	# map, the match not being live: get out of the way and let it play.
	if _open and (not player.is_alive() or player.map_open \
			or not GameState.match_live):
		_close()
		return

	var edges := _read_edges()
	if not _open:
		if edges["toggle"] and player.is_alive() and GameState.match_live \
				and not player.map_open:
			_show()
		return

	match _mode:
		Mode.NAV:
			_nav_input(edges)
		Mode.NAME:
			# The keyboard player types (handled in _input); a pad drives the
			# on-screen character strip. Reading edges above still refreshed _prev.
			if device >= 0:
				_name_input(edges)
		Mode.CONFIRM:
			_confirm_input(edges)
		Mode.LISTEN:
			# Nothing here: the binding — and its START-cancel / BACK-clear — is
			# captured in _input, so a pad can still bind its B or BACK button. The
			# _read_edges() call above only keeps _prev fresh for the return to NAV.
			pass


# --- open / close -------------------------------------------------------------

func _show() -> void:
	_open = true
	_mode = Mode.NAV
	_row = 0
	# SOLO, THIS IS A REAL PAUSE. At more than one human it never has been and
	# must not become one — the whole point of this screen is that it opens over
	# ONE viewport while everybody else keeps playing. `GameState.may_pause()`
	# owns that rule so it is not restated here (see the note there).
	if GameState.may_pause():
		GameState.hold(_hold_id(), true)
	player.settings_open = true
	player.weapon.aiming = false
	if device < 0:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	visible = true
	_rebuild_rows()
	_render()


func _close() -> void:
	_open = false
	_mode = Mode.NAV
	_listen_id = ""
	visible = false
	# ALWAYS released, whether or not it was ever taken — `hold(x, false)` on a
	# reason that was never held is a no-op, and the alternative is remembering
	# across a code path that can also be reached by dying, by a map change and
	# by leaving the match.
	GameState.hold(_hold_id(), false)
	if is_instance_valid(player):
		player.settings_open = false
		if device < 0:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- NAV mode -----------------------------------------------------------------

## This screen's own hold, keyed per player so two of them (which cannot both be
## solo, but can both exist) can never clear each other's.
func _hold_id() -> String:
	return "settings:%d" % (player.player_index if is_instance_valid(player) else 0)


func _rebuild_rows() -> void:
	_rows.clear()
	_rows.append({"kind": Kind.SENS})
	_rows.append({"kind": Kind.ASSIST})
	for entry in Controls.ACTIONS:
		# A pad steers with its stick, so the four movement rows are keyboard-only —
		# same rule the menu's controls screen uses.
		if device >= 0 and not entry["pad"]:
			continue
		_rows.append({"kind": Kind.BIND, "id": entry["id"], "name": entry["name"]})
	_rows.append({"kind": Kind.PROFILE})
	_rows.append({"kind": Kind.LOAD})
	_rows.append({"kind": Kind.SAVE})
	_rows.append({"kind": Kind.DELETE})
	_rows.append({"kind": Kind.RESET})
	_rows.append({"kind": Kind.RESUME})
	# LAST, and behind a confirm. It is last because RESUME is what a player
	# reaching for this screen actually wants and should be the easiest thing to
	# land on; it is behind a confirm because the row list WRAPS, so "up from the
	# top row" is one press away from it.
	_rows.append({"kind": Kind.QUIT})
	_row = clampi(_row, 0, _rows.size() - 1)
	_profile_idx = clampi(_profile_idx, 0, maxi(Controls.profile_names().size() - 1, 0))


func _nav_input(edges: Dictionary) -> void:
	if edges["back"] or edges["toggle"]:
		_close()
		return
	if edges["down"]:
		_row = wrapi(_row + 1, 0, _rows.size())
		_render()
	elif edges["up"]:
		_row = wrapi(_row - 1, 0, _rows.size())
		_render()
	var dir := (1 if edges["right"] else 0) - (1 if edges["left"] else 0)
	if dir != 0:
		_adjust(dir)
	if edges["accept"]:
		_activate()


func _adjust(dir: int) -> void:
	match _rows[_row]["kind"]:
		Kind.SENS:
			Controls.set_sensitivity(device, Controls.sensitivity(device) + dir * SENS_STEP)
			player.refresh_settings()
		Kind.ASSIST:
			Controls.set_aim_assist(device, Controls.aim_assist_strength(device) + dir * ASSIST_STEP)
			player.refresh_settings()
		Kind.PROFILE:
			var n := Controls.profile_names().size()
			if n > 0:
				_profile_idx = wrapi(_profile_idx + dir, 0, n)
		_:
			return
	_render()


func _activate() -> void:
	match _rows[_row]["kind"]:
		Kind.BIND:
			_begin_listen(_rows[_row]["id"])
		Kind.LOAD:
			var names := Controls.profile_names()
			if _profile_idx < names.size():
				Controls.load_profile(names[_profile_idx], device)
				player.refresh_settings()
				_render()
		Kind.SAVE:
			_name_buf = ""
			_name_cell = 0
			_mode = Mode.NAME
			_render()
		Kind.DELETE:
			var dnames := Controls.profile_names()
			if _profile_idx < dnames.size():
				Controls.delete_profile(dnames[_profile_idx])
				_profile_idx = maxi(_profile_idx - 1, 0)
				_render()
		Kind.RESET:
			Controls.reset_defaults()
			player.refresh_settings()
			_render()
		Kind.RESUME:
			_close()
		Kind.QUIT:
			_mode = Mode.CONFIRM
			_render()
		_:
			return


## THE CONFIRM. Accept leaves, anything else comes back — and BACK is not the
## only way out on purpose: START (`toggle`) has closed this screen from every
## other mode since it was written, and a mode where the button that has always
## meant "put this away" instead does nothing is how a player ends up pressing
## accept to make something happen.
func _confirm_input(edges: Dictionary) -> void:
	if edges["back"] or edges["toggle"]:
		_mode = Mode.NAV
		_render()
		return
	if edges["accept"]:
		_leave_match()


## OUT OF THE MATCH ENTIRELY. Until this existed the only ways out of a match
## were winning it, losing it, or killing the process — which for a 200-ticket
## Conquest is several minutes of a game somebody has already decided to stop
## playing.
##
## ONLINE IT LEAVES THE SESSION FIRST. Changing scene without `Net.leave()`
## abandons a live peer connection: the host goes on believing this machine is
## still in the match and holding bodies for it, and the next attempt to join
## anything reuses a socket that was never closed.
func _leave_match() -> void:
	_close()
	var to := exit_scene()
	# Walked out of, not paused: a queue you left in the middle of is one you are
	# no longer playing, and `playlist_begin` starts it from the top next time.
	GameState.playlist_index = -1
	# EVERY hold, not just this screen's: a pad may have fallen out while the menu
	# was up, and a scene loaded into a paused tree never runs its first frame.
	GameState.release_all_holds()
	if Net.online():
		Net.leave()
	get_tree().change_scene_to_file(to)


## WHERE LEAVING GOES, split out from the act of going there so it can be checked
## without being done. A test that performs the real navigation frees itself
## mid-run — the scene it is part of is the scene being replaced — so the choice
## and the jump have to be separable or the choice cannot be tested at all.
## LEAVING A PLAYLIST GOES BACK TO THE PLAYLIST, not out to the front screen.
## The queue is a night's play that somebody built, everyone is still signed in,
## and the commonest reason to walk out of round two of three is to change
## something about round three — so the screen that can do that is where leaving
## belongs. The playlist itself is ABANDONED (`playlist_index` goes back to -1,
## done by the caller) rather than resumed: quitting is quitting.
func exit_scene() -> String:
	if Net.online():
		return LOBBY_SCENE
	return PLAYLIST_SCENE if GameState.playlist_active() else FRONT_SCENE


# --- rebinding (LISTEN mode) --------------------------------------------------

func _begin_listen(id: String) -> void:
	_listen_id = id
	_listen_armed = false
	_mode = Mode.LISTEN
	_render()
	await get_tree().process_frame
	if is_inside_tree() and _mode == Mode.LISTEN:
		_listen_armed = true


func _end_listen() -> void:
	_listen_id = ""
	_listen_armed = false
	_mode = Mode.NAV
	_swallow_edges = true  # the input that ended the listen must not also drive NAV
	_render()


## Every input belongs to the listen while it is up, so it is captured here rather
## than polled — a poll only sees the buttons we already named, and the point of a
## rebind is to catch any of them. Filtered to THIS player's device so one player
## rebinding cannot capture another's controller.
func _input(event: InputEvent) -> void:
	if _mode == Mode.NAME and device < 0:
		_name_key(event)
		return
	if _mode != Mode.LISTEN:
		return
	get_viewport().set_input_as_handled()
	if not _listen_armed:
		return
	if device < 0:
		# Keyboard profile: ESC cancels, anything else binds.
		if event is InputEventKey and event.pressed and not event.echo \
				and event.keycode == KEY_ESCAPE:
			_end_listen()
			return
		if Controls.bind_key(_listen_id, event):
			_end_listen()
		return
	# A pad profile. START cancels and BACK clears the override (neither is
	# bindable), exactly like the menu's controls screen, so a player with no
	# keyboard is never trapped in a row they opened.
	if event is InputEventJoypadButton and event.pressed and event.device == device:
		if event.button_index == JOY_BUTTON_START:
			_end_listen()
			return
		if event.button_index == JOY_BUTTON_BACK:
			Controls.clear_override(device, _listen_id)
			_end_listen()
			return
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	if event.device != device:
		return
	if Controls.bind_pad(device, _listen_id, event):
		_end_listen()


# --- naming a preset (NAME mode) ----------------------------------------------

func _name_input(edges: Dictionary) -> void:
	if edges["back"] or edges["toggle"]:
		_mode = Mode.NAV
		_render()
		return
	var cells := NAME_CHARS.length() + 2  # + DEL + OK
	if edges["right"]:
		_name_cell = wrapi(_name_cell + 1, 0, cells)
		_render()
	elif edges["left"]:
		_name_cell = wrapi(_name_cell - 1, 0, cells)
		_render()
	elif edges["down"]:
		_name_cell = wrapi(_name_cell + 10, 0, cells)
		_render()
	elif edges["up"]:
		_name_cell = wrapi(_name_cell - 10, 0, cells)
		_render()
	if edges["accept"]:
		_name_commit_cell()


func _name_commit_cell() -> void:
	var n := NAME_CHARS.length()
	if _name_cell == n:            # DEL
		if _name_buf.length() > 0:
			_name_buf = _name_buf.substr(0, _name_buf.length() - 1)
	elif _name_cell == n + 1:      # OK
		_finish_name()
		return
	elif _name_buf.length() < NAME_MAX:
		_name_buf += NAME_CHARS[_name_cell]
	_render()


## Physical keyboard typing while naming (the keyboard player's fast path).
func _name_key(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	get_viewport().set_input_as_handled()
	_swallow_edges = true  # this keypress is the name entry's, not the NAV list's
	match event.keycode:
		KEY_ESCAPE:
			_mode = Mode.NAV
		KEY_ENTER, KEY_KP_ENTER:
			_finish_name()
			return
		KEY_BACKSPACE:
			if _name_buf.length() > 0:
				_name_buf = _name_buf.substr(0, _name_buf.length() - 1)
		_:
			var ch := char(event.unicode).to_upper()
			if ch.length() == 1 and NAME_CHARS.contains(ch) and _name_buf.length() < NAME_MAX:
				_name_buf += ch
	_render()


func _finish_name() -> void:
	if Controls.save_profile(_name_buf, device):
		# Land the selector on the profile just saved.
		var names := Controls.profile_names()
		_profile_idx = maxi(names.find(_name_buf.strip_edges()), 0)
	_mode = Mode.NAV
	_render()


# --- rendering ----------------------------------------------------------------

func _render() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	if _mode == Mode.NAME:
		_title.text = "NAME THIS PRESET"
		_render_name()
		_hint.text = "MOVE to pick a letter  ·  ACCEPT adds  ·  BACK cancels" \
			if device >= 0 else "TYPE a name  ·  ENTER saves  ·  ESC cancels"
		return
	if _mode == Mode.CONFIRM:
		_title.text = "LEAVE THE MATCH?"
		_render_confirm()
		_hint.text = "ACCEPT to leave  ·  BACK / START to stay"
		return
	_title.text = "SETTINGS  —  %s" % Controls.device_label(device) if device >= 0 \
		else "SETTINGS  —  KEYBOARD + MOUSE"
	for i in _rows.size():
		_body.add_child(_render_row(i))
	_hint.text = _hint_text()


func _render_row(i: int) -> Control:
	var selected := i == _row and _mode == Mode.NAV
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	var name_l := _label(_row_name(i), 15, ACCENT if selected else DIM)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_l.custom_minimum_size = Vector2(230, 0)
	line.add_child(name_l)
	var value_l := _label(_row_value(i), 15, _row_value_color(i, selected))
	value_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	value_l.custom_minimum_size = Vector2(210, 0)
	line.add_child(value_l)
	return line


func _row_name(i: int) -> String:
	var caret := "▶ " if (i == _row and _mode == Mode.NAV) else "   "
	match _rows[i]["kind"]:
		Kind.SENS: return caret + "LOOK SENSITIVITY"
		Kind.ASSIST: return caret + "AIM ASSIST"
		Kind.BIND: return caret + str(_rows[i]["name"])
		Kind.PROFILE: return caret + "PRESET"
		Kind.LOAD: return caret + "LOAD PRESET"
		Kind.SAVE: return caret + "SAVE AS NEW…"
		Kind.DELETE: return caret + "DELETE PRESET"
		Kind.RESET: return caret + "RESET TO DEFAULTS"
		Kind.RESUME: return caret + "RESUME"
		Kind.QUIT: return caret + "QUIT TO MENU"
	return caret


func _row_value(i: int) -> String:
	match _rows[i]["kind"]:
		Kind.SENS:
			return "◂ %.1fx ▸" % Controls.sensitivity(device)
		Kind.ASSIST:
			return "◂ %d%% ▸" % roundi(Controls.aim_assist_strength(device) * 100.0)
		Kind.BIND:
			var id: String = _rows[i]["id"]
			if _mode == Mode.LISTEN and id == _listen_id:
				return "PRESS AN INPUT…"
			var text: String = Controls.key_label(id) if device < 0 \
				else Controls.pad_label(device, id)
			if device >= 0 and Controls.has_override(device, id):
				text += " *"
			return text
		Kind.PROFILE:
			var names := Controls.profile_names()
			if names.is_empty():
				return "(none saved)"
			return "◂ %s ▸" % names[clampi(_profile_idx, 0, names.size() - 1)]
	return ""


func _row_value_color(i: int, selected: bool) -> Color:
	if _rows[i]["kind"] == Kind.BIND and _mode == Mode.LISTEN \
			and _rows[i]["id"] == _listen_id:
		return LISTEN_COLOR
	return Color(0.90, 0.93, 0.97) if selected else DIM


## WHAT LEAVING ACTUALLY COSTS, said out loud and said DIFFERENTLY depending on
## who else is playing. On a couch this is not one player's decision: there is
## one match on one machine and no way for player three to walk out while the
## other three carry on, so the honest thing is to tell whoever is about to press
## it that they are ending everybody's game. A confirm that says only "are you
## sure?" is a confirm that answers the wrong question.
func _render_confirm() -> void:
	var lines := PackedStringArray()
	var humans: int = GameState.human_players
	if Net.online():
		lines.append("This machine leaves the session and returns to the lobby.")
		if humans > 1:
			lines.append("All %d players on this machine leave with it." % humans)
	elif humans > 1:
		lines.append("This ends the match for all %d players." % humans)
		lines.append("There is one match on this machine — nobody carries on without you.")
	else:
		lines.append("The match ends and you go back to the menu.")
	lines.append("")
	lines.append("Nothing about this round is kept.")
	for i in lines.size():
		var l := _label(lines[i], 15 if i == 0 else 14,
			WARN if i == 0 else DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_body.add_child(l)


func _render_name() -> void:
	var shown := _name_buf if not _name_buf.is_empty() else "…"
	_body.add_child(_label(shown, 24, Color(0.95, 0.97, 1.0)))
	_body.add_child(_spacer(8))
	# The character strip, wrapped ten to a line so up/down step a visible row.
	var n := NAME_CHARS.length()
	var grid := GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 2)
	_body.add_child(grid)
	for k in n:
		grid.add_child(_cell(NAME_CHARS[k] if NAME_CHARS[k] != " " else "␣", k == _name_cell, DIM))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 20)
	_body.add_child(_spacer(6))
	_body.add_child(actions)
	actions.add_child(_cell(CELL_DEL, _name_cell == n, LISTEN_COLOR))
	actions.add_child(_cell(CELL_OK, _name_cell == n + 1, OK_COLOR))


func _cell(text: String, on: bool, on_color: Color) -> Label:
	var l := _label(text, 18, on_color if on else FAINT)
	if on:
		l.text = "[%s]" % text
	return l


func _hint_text() -> String:
	if _rows.is_empty():
		return ""
	match _rows[_row]["kind"]:
		Kind.SENS, Kind.ASSIST:
			return "◂ ▸ adjust  ·  BACK / START closes"
		Kind.BIND:
			return "ACCEPT to rebind  ·  (in a rebind: START cancels, BACK clears)" \
				if device >= 0 else "ACCEPT to rebind  ·  ESC cancels a rebind"
		Kind.PROFILE:
			return "◂ ▸ pick a saved preset"
		Kind.LOAD:
			return "ACCEPT loads the picked preset onto this device"
		Kind.SAVE:
			return "ACCEPT names and saves the current settings as a preset"
		Kind.DELETE:
			return "ACCEPT deletes the picked preset"
		Kind.RESET:
			return "ACCEPT restores default bindings and feel"
		Kind.RESUME:
			return "ACCEPT (or BACK / START) returns to the match"
		Kind.QUIT:
			return "ACCEPT to leave this match"
	return ""


# --- input polling ------------------------------------------------------------
#
# Six virtual buttons plus the open/close toggle, read from THIS player's device
# and edge-detected against last frame. Pads poll dpad + left stick + face
# buttons; the keyboard reads arrows/WASD + Enter + Esc.

func _read_edges() -> Dictionary:
	var now := {
		"up": _down("up"), "down": _down("down"),
		"left": _down("left"), "right": _down("right"),
		"accept": _down("accept"), "back": _down("back"),
		"toggle": _down("toggle"),
	}
	var edges := {}
	for k in now:
		edges[k] = (not _swallow_edges) and now[k] and not _prev.get(k, false)
	_prev = now
	_swallow_edges = false
	return edges


## THE KEYBOARD IS A SAFETY VALVE WHEN THIS PLAYER'S PAD IS GONE, and it exists
## to close a dead end rather than as a feature.
##
## Solo, a pad falling out stops the match (`Main._on_pad_changed`) and the only
## thing that can start it again is this screen — which is driven by the pad that
## just died. Reconnecting is the ordinary fix and usually works, but a controller
## that has genuinely broken would otherwise leave the game frozen with no exit
## but killing the process, which is precisely the failure this whole pass is
## about. So while a pad player is disconnected, the keyboard drives their screen
## too: it is the one input that is always present.
##
## It is deliberately gated on being DISCONNECTED and never on merely being a pad
## player — otherwise at a couch one keyboard would silently drive four overlays
## at once.
func _pad_lost() -> bool:
	return device >= 0 and not Input.get_connected_joypads().has(device)


func _down(which: String) -> bool:
	if device >= 0:
		return _pad_down(which) or (_pad_lost() and _key_down(which))
	return _key_down(which)


func _pad_down(which: String) -> bool:
	match which:
		"up":
			return Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP) \
				or Input.get_joy_axis(device, JOY_AXIS_LEFT_Y) < -0.5
		"down":
			return Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN) \
				or Input.get_joy_axis(device, JOY_AXIS_LEFT_Y) > 0.5
		"left":
			return Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT) \
				or Input.get_joy_axis(device, JOY_AXIS_LEFT_X) < -0.5
		"right":
			return Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT) \
				or Input.get_joy_axis(device, JOY_AXIS_LEFT_X) > 0.5
		"accept":
			return Input.is_joy_button_pressed(device, JOY_BUTTON_A)
		"back":
			return Input.is_joy_button_pressed(device, JOY_BUTTON_B)
		"toggle":
			return Input.is_joy_button_pressed(device, JOY_BUTTON_START)
	return false


func _key_down(which: String) -> bool:
	match which:
		"up":
			return Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W)
		"down":
			return Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S)
		"left":
			return Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A)
		"right":
			return Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D)
		"accept":
			return Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER)
		"back", "toggle":
			return Input.is_key_pressed(KEY_ESCAPE)
	return false


# --- little builders ----------------------------------------------------------

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
