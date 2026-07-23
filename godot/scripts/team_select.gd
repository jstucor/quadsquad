extends Control
## Team select, between the menu and the match. Every human picks a side: move
## your token onto a team box, press A to lock in, B to change your mind. Once
## all of them are locked, it loads the map, the AI and the buy screen.
##
## It draws itself and polls each player's own device every frame — P1..P4 are
## pads 0..3, and the debug flag puts P1 on the keyboard — the same pad-first,
## per-device model the in-match input uses. Free-for-all never reaches here (the
## menu drops it straight into the match), so there are always at least two teams
## to choose between.

const GAME_SCENE := "res://scenes/main.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"
const DEADZONE := 0.6   # stick push that counts as one step, like the buy screen

# Match Main's player colours, so a token here is the same colour as that
# player's HUD in the match.
const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.3, 0.3), Color(0.3, 0.6, 0.9),
	Color(0.4, 0.85, 0.4), Color(0.95, 0.8, 0.3),
]

## One entry per human player, in player order.
var _players: Array[Dictionary] = []
var _teams := 2
var _started := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_teams = GameState.active_teams()
	for i in GameState.human_players:
		_players.append({
			# device: keyboard for P1 under the debug flag, else this player's pad.
			"device": -1 if (GameState.debug_kbm and i == 0) else i,
			"hover": GameState.team_for_player(i),   # start on the round-robin pick
			"locked": false,
			# One-shot latches so a held stick/button steps once, not every frame.
			"move_latch": 0.0, "accept_latch": true, "back_latch": true,
		})


func _process(_delta: float) -> void:
	if _started:
		return
	for p in _players:
		_poll(p)
	if _all_locked():
		_begin_match()
	queue_redraw()


## One player's input this frame: move the hover while unlocked, A to lock, B to
## release. All of it edge-latched so a held control acts once.
func _poll(p: Dictionary) -> void:
	var device: int = p["device"]
	if not p["locked"]:
		var step := _move_step(p)
		if step != 0:
			p["hover"] = wrapi(int(p["hover"]) + step, 0, _teams)
	var accept := Controls.held(device, "jump")
	if accept and not p["accept_latch"]:
		p["locked"] = true
	p["accept_latch"] = accept
	var back := _back_held(device)
	if back and not p["back_latch"]:
		p["locked"] = false
	p["back_latch"] = back


## Horizontal step from the movement stick / d-pad, one per push.
func _move_step(p: Dictionary) -> int:
	var device: int = p["device"]
	var x := 0.0
	if device < 0:
		x = Input.get_axis("kb_left", "kb_right")
	else:
		x = Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT):
			x = -1.0
		elif Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT):
			x = 1.0
	var step := 0
	if absf(x) >= DEADZONE:
		if p["move_latch"] == 0.0:
			step = signi(x)
		p["move_latch"] = signf(x)
	else:
		p["move_latch"] = 0.0
	return step


## B: the pad's B button, or ESC/Backspace on the keyboard — the fixed "back"
## the buy screen uses too, never bound to anything else.
func _back_held(device: int) -> bool:
	if device < 0:
		return Input.is_key_pressed(KEY_ESCAPE) or Input.is_key_pressed(KEY_BACKSPACE)
	return Input.is_joy_button_pressed(device, JOY_BUTTON_B)


func _all_locked() -> bool:
	for p in _players:
		if not p["locked"]:
			return false
	return true


## Everyone has chosen: record the picks and drop into the match.
func _begin_match() -> void:
	_started = true
	var picks: Array[int] = []
	for p in _players:
		picks.append(int(p["hover"]))
	GameState.chosen_teams = picks
	get_tree().change_scene_to_file(GAME_SCENE)


func _input(event: InputEvent) -> void:
	# A keyboardless bail-out back to the menu, so a mis-started match is not a
	# trap. START on any pad, or ESC before anyone has locked in.
	if event is InputEventJoypadButton and event.pressed \
			and event.button_index == JOY_BUTTON_START:
		get_tree().change_scene_to_file(MENU_SCENE)


func _draw() -> void:
	var s := size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.06, 0.07, 0.09))
	var font := get_theme_default_font()
	var fs := 22
	_centre(font, 34, Vector2(s.x * 0.5, 60.0), "CHOOSE YOUR TEAM", Color(0.45, 0.72, 1.0))

	# A row of team boxes across the middle.
	var gap := 24.0
	var box_w: float = minf(300.0, (s.x - gap * (_teams + 1)) / _teams)
	var box_h := s.y * 0.42
	var total := box_w * _teams + gap * (_teams - 1)
	var y := s.y * 0.24
	var box_rects: Array[Rect2] = []
	for t in _teams:
		var x := (s.x - total) * 0.5 + t * (box_w + gap)
		var r := Rect2(x, y, box_w, box_h)
		box_rects.append(r)
		var col: Color = GameState.TEAM_COLORS[t]
		draw_rect(r, Color(col, 0.14))
		draw_rect(r, col, false, 3.0)
		_centre(font, fs, r.position + Vector2(box_w * 0.5, 34.0),
			GameState.TEAM_NAMES[t], col)

	# Each player's token, sitting in the team it is hovering / locked on. Locked
	# tokens are filled and lettered; a still-choosing token is a hollow ring.
	var counts := {}
	for i in _players.size():
		var p := _players[i]
		var t: int = p["hover"]
		var slot: int = counts.get(t, 0)
		counts[t] = slot + 1
		var r := box_rects[t]
		var pos := r.position + Vector2(
			box_w * 0.5 + (slot - 1) * 46.0, box_h * 0.6)
		var col := PLAYER_COLORS[i % PLAYER_COLORS.size()]
		if p["locked"]:
			draw_circle(pos, 18.0, col)
			_centre(font, 18, pos + Vector2(0, 1), "P%d" % (i + 1), Color.BLACK)
		else:
			draw_arc(pos, 18.0, 0.0, TAU, 28, Color(col, 0.9), 3.0, true)
			_centre(font, 16, pos + Vector2(0, 1), "P%d" % (i + 1), col)

	# Status line: who is still choosing, or that the match is loading.
	var waiting := 0
	for p in _players:
		if not p["locked"]:
			waiting += 1
	var msg := "loading…" if waiting == 0 \
		else "waiting for %d player%s" % [waiting, "" if waiting == 1 else "s"]
	_centre(font, 20, Vector2(s.x * 0.5, s.y - 92.0), msg, Color(0.7, 0.74, 0.8))
	_centre(font, 15, Vector2(s.x * 0.5, s.y - 58.0),
		"move to a team    A to lock in    B to change    START returns to menu",
		Color(0.5, 0.54, 0.6))


func _centre(font: Font, fs: int, at: Vector2, text: String, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, at - Vector2(w * 0.5, 0.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
