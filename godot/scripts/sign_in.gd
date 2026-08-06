extends Control
## SIGN IN — the screen between "how many of you" and setting the match up.
##
## WHAT IT IS FOR. The front screen asks the only question that is a fact about
## the room: how many people are here. This one asks the other one — WHICH
## controller is each of them holding, and WHO ARE THEY — and until it existed
## the game answered both by arithmetic. Player 2 was the top-right quadrant and
## was assumed to be on pad 1; their sensitivity belonged to that pad rather than
## to them; and their kills were thrown away with the match.
##
## SO A SEAT IS CLAIMED, NOT DEALT. Press START on whatever controller you picked
## up and it becomes yours — which is the same gesture every console game has
## used for twenty years, and is the only one that works when four pads have been
## charging in a drawer and nobody knows which is which. The pad that pressed is
## the pad that steers, wherever it sits in `Input.get_connected_joypads()`.
##
## THEN YOU PICK AN ACCOUNT, which is where your controller configuration and
## your record live (see `Accounts`). Signing in APPLIES that configuration to
## the device you just claimed, so a player who rebound crouch last week has it
## rebound tonight on a different pad.
##
## TWO PEOPLE CANNOT BE ONE ACCOUNT. A taken row is shown and refused rather than
## hidden: on a couch the interesting case is two brothers arguing about whose
## account it is, and a row that vanishes reads as the game having lost it.
##
## IT IS POLLED PER DEVICE, not driven by focus and the ui_* actions, for the
## reason the buy screen and team select are: four people are doing this AT ONCE,
## and Godot's focus is one cursor shared by the whole screen.

const PLAYLIST_SCENE := "res://scenes/playlist.tscn"
const FRONT_SCENE := "res://scenes/front.tscn"

const BG_COLOR := Color(0.05, 0.06, 0.08)
const ACCENT := Color(0.45, 0.72, 1.0)
const DIM := Color(0.62, 0.66, 0.72)
const FAINT := Color(0.42, 0.46, 0.52)
const PANEL := Color(0.09, 0.11, 0.14, 0.92)
const PANEL_EDGE := Color(0.24, 0.30, 0.38)
const TAKEN := Color(0.50, 0.42, 0.42)

## A seat is drawn in its OWN player colour and not in the side's, which is the
## opposite of the in-match HUD's rule and deliberately so: nothing here knows
## what side anybody is on yet, and the entire question this screen asks is
## "which of these four is me".
const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.3, 0.3), Color(0.3, 0.6, 0.9),
	Color(0.4, 0.85, 0.4), Color(0.95, 0.8, 0.3),
]

const DEADZONE := 0.6          # stick push that counts as one step
const REPEAT_DELAY := 0.35     # ...and how long a held stick waits before repeating
const REPEAT_RATE := 0.09
const KEYBOARD := -1           # the keyboard/mouse "device", as everywhere else

enum State { EMPTY, PICKING, NAMING, READY }

## The row that makes a new account, always last in the list.
const NEW_ROW := "+ NEW ACCOUNT"

var _seats: Array[Dictionary] = []
var _cards: Array[Dictionary] = []
var _footer: Label
var _waiting := -1        # how many seats were still empty at the last repaint
var _leaving := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Quality.active_views = 1
	Quality.apply_global()
	Engine.max_fps = 60
	Audio.play_music("menu")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Accounts.ensure_loaded()
	for i in GameState.human_players:
		_seats.append({
			"device": 0, "claimed": false, "state": State.EMPTY,
			"row": 0, "name": "", "cursor": 0,
			# Edge latches, one per control this screen reads. Held TRUE at build
			# so a button still down from the last screen cannot act here — the
			# same guard the buy screen keeps for a stick held on the death frame.
			"accept": true, "back": true, "start": true, "move": 0.0, "move_dir": 0,
		})
	_build()
	_refresh()


func _exit_tree() -> void:
	Engine.max_fps = 0


func _process(delta: float) -> void:
	if _leaving:
		return
	_claim_seats()
	for i in _seats.size():
		_poll(i, delta)
	_refresh()


# --- claiming -----------------------------------------------------------------

## A device that is not already somebody's, pressing START, takes the first
## empty seat. Every connected pad is polled plus the keyboard, so it genuinely
## does not matter which controller anybody picked up.
func _claim_seats() -> void:
	for device in _devices():
		# A device that already has a seat is that SEAT's to poll. Tracking its
		# START here as well would overwrite the latch a frame before `_poll`
		# reads it, so player 1's continue press would never be an edge and the
		# screen could not be left — the whole reason one owner per input.
		if _seat_of(device) >= 0:
			continue
		var pressed := _start_held(device)
		if pressed and not _latch(device):
			_take_seat(device)
		_set_free_latch(device, pressed)


## START latches for devices that have no seat yet. Kept off the seat rows for
## the obvious reason — the seat does not exist at the moment the button that
## creates it goes down.
var _free_latch := {}


func _latch(device: int) -> bool:
	return bool(_free_latch.get(device, true))


func _set_free_latch(device: int, value: bool) -> void:
	_free_latch[device] = value


func _take_seat(device: int) -> void:
	for i in _seats.size():
		var seat: Dictionary = _seats[i]
		if seat["claimed"]:
			continue
		seat["claimed"] = true
		seat["device"] = device
		seat["state"] = State.PICKING
		seat["row"] = 0
		# Every latch is armed HELD, so the press that claimed the seat cannot
		# also pick whatever row the list happens to open on.
		seat["accept"] = true
		seat["back"] = true
		seat["start"] = true
		Audio.play("ui_accept")
		_rebuild_rows(i)
		return


## Every device that could claim a seat: the keyboard, and every pad the machine
## can see. ASKED EVERY FRAME rather than cached, because the case this screen
## exists for is somebody plugging a controller in while looking at it.
func _devices() -> Array:
	var out: Array = [KEYBOARD]
	for pad in Input.get_connected_joypads():
		out.append(int(pad))
	return out


func _seat_of(device: int) -> int:
	for i in _seats.size():
		if _seats[i]["claimed"] and int(_seats[i]["device"]) == device:
			return i
	return -1


func _start_held(device: int) -> bool:
	if device < 0:
		return Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER)
	return Input.is_joy_button_pressed(device, JOY_BUTTON_START)


# --- one seat's input ---------------------------------------------------------

func _poll(index: int, delta: float) -> void:
	var seat: Dictionary = _seats[index]
	if not seat["claimed"]:
		return
	var device: int = seat["device"]
	var step := _step(seat, device, delta)
	var accept := _accept_held(device)
	var back := _back_held(device)
	var accept_edge: bool = accept and not seat["accept"]
	var back_edge: bool = back and not seat["back"]
	seat["accept"] = accept
	seat["back"] = back

	match int(seat["state"]):
		State.PICKING:
			var rows: Array = _rows(index)
			if step.y != 0:
				seat["row"] = wrapi(int(seat["row"]) + step.y, 0, rows.size())
				Audio.play("ui_move")
			if accept_edge:
				_choose(index, rows[clampi(int(seat["row"]), 0, rows.size() - 1)])
			elif back_edge:
				_release(index)
		State.NAMING:
			_type(index, step, accept_edge, back_edge)
		State.READY:
			# BACK from a finished seat goes to the account list, not out of the
			# seat: changing your mind about which account is far commoner than
			# changing your mind about which controller you are holding.
			if back_edge:
				seat["state"] = State.PICKING
				seat["name"] = ""
				Audio.play("ui_move")
				_rebuild_rows(index)
			elif _start_edge(seat, device) and index == 0 and _all_ready():
				_continue()
		_:
			pass
	# START is tracked for every state so player 1's continue press is an edge
	# and not a level — without it, holding START through the last sign-in walks
	# straight past this screen.
	if int(seat["state"]) != State.READY:
		seat["start"] = _start_held(device)


func _start_edge(seat: Dictionary, device: int) -> bool:
	var held := _start_held(device)
	var edge: bool = held and not seat["start"]
	seat["start"] = held
	return edge


## Repeat-stepped stick / d-pad / keys. A held direction steps once, waits, then
## repeats — a list of accounts is a list you scroll, and a strict one-press-one-
## step rule makes a long one unusable.
func _step(seat: Dictionary, device: int, delta: float) -> Vector2i:
	var dir := Vector2i.ZERO
	var x := 0.0
	var y := 0.0
	if device < 0:
		x = Input.get_axis("kb_left", "kb_right")
		y = Input.get_axis("kb_forward", "kb_back")
	else:
		x = Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
		y = Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT):
			x = -1.0
		elif Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT):
			x = 1.0
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP):
			y = -1.0
		elif Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN):
			y = 1.0
	if absf(x) > absf(y):
		dir.x = signi(int(signf(x))) if absf(x) > DEADZONE else 0
	else:
		dir.y = signi(int(signf(y))) if absf(y) > DEADZONE else 0
	if dir == Vector2i.ZERO:
		seat["move"] = 0.0
		seat["move_dir"] = 0
		return dir
	var key := dir.x * 2 + dir.y
	if int(seat["move_dir"]) != key:
		seat["move_dir"] = key
		seat["move"] = REPEAT_DELAY
		return dir
	seat["move"] = float(seat["move"]) - delta
	if float(seat["move"]) <= 0.0:
		seat["move"] = REPEAT_RATE
		return dir
	return Vector2i.ZERO


func _accept_held(device: int) -> bool:
	if device < 0:
		return Input.is_key_pressed(KEY_SPACE)
	return Input.is_joy_button_pressed(device, JOY_BUTTON_A)


## B, and it is FIXED and unbindable — the same rule the buy screen's exit keeps.
## A screen you can get stuck inside needs a way out that no rebind can remove.
func _back_held(device: int) -> bool:
	if device < 0:
		return Input.is_key_pressed(KEY_ESCAPE) or Input.is_key_pressed(KEY_BACKSPACE)
	return Input.is_joy_button_pressed(device, JOY_BUTTON_B)


# --- choosing and naming ------------------------------------------------------

func _choose(index: int, row: String) -> void:
	var seat: Dictionary = _seats[index]
	if row == NEW_ROW:
		seat["state"] = State.NAMING
		seat["name"] = ""
		seat["cursor"] = 0
		Audio.play("ui_accept")
		return
	if _taken_by(row) >= 0:
		# Somebody else is already signed in as them. Refused out loud rather
		# than silently: a press that does nothing reads as a broken pad.
		Audio.play("ui_deny")
		return
	seat["name"] = row
	seat["state"] = State.READY
	Accounts.sign_in(row, int(seat["device"]))
	Audio.play("ui_accept")


func _release(index: int) -> void:
	var seat: Dictionary = _seats[index]
	seat["claimed"] = false
	seat["state"] = State.EMPTY
	seat["name"] = ""
	_set_free_latch(int(seat["device"]), true)
	Audio.play("ui_move")
	# NOBODY LEFT means this screen has nothing on it, and the only thing a
	# player can want then is to go back — so B out of the last seat is the way
	# off the screen. Otherwise the sign-in is a room with no door.
	for s in _seats:
		if s["claimed"]:
			return
	_leaving = true
	get_tree().change_scene_to_file(FRONT_SCENE)


## The letter carousel: up/down changes the character under the cursor, left and
## right move it, A confirms, B rubs one out (and cancels once there is nothing
## left to rub out).
##
## A PAD HAS TO BE ABLE TO DO THIS. An on-screen QWERTY driven by a stick is
## twelve presses per letter; a carousel is one push per letter from where you
## already are, which is what arcade initials entry has always been and is still
## the right answer for a controller.
func _type(index: int, step: Vector2i, accept: bool, back: bool) -> void:
	var seat: Dictionary = _seats[index]
	var typed: String = seat["name"]
	if accept:
		var made := Accounts.create(typed)
		if made.is_empty():
			Audio.play("ui_deny")
			return
		seat["name"] = made
		seat["state"] = State.READY
		Accounts.sign_in(made, int(seat["device"]))
		Audio.play("ui_accept")
		_rebuild_all_rows()
		return
	if back:
		if typed.is_empty():
			seat["state"] = State.PICKING
			Audio.play("ui_move")
			return
		seat["name"] = typed.substr(0, typed.length() - 1)
		seat["cursor"] = mini(int(seat["cursor"]), maxi(typed.length() - 1, 0))
		Audio.play("ui_move")
		return
	if step.x != 0:
		seat["cursor"] = clampi(int(seat["cursor"]) + step.x, 0,
			mini(typed.length(), Accounts.MAX_NAME - 1))
		Audio.play("ui_move")
	if step.y != 0:
		var at: int = clampi(int(seat["cursor"]), 0, Accounts.MAX_NAME - 1)
		var chars := Accounts.NAME_CHARS
		if at >= typed.length():
			# Stepping off the end of the name adds a letter, so writing one is
			# push-up, right, push-up — never a separate "add a character" press.
			if typed.length() >= Accounts.MAX_NAME:
				return
			typed += "A" if step.y < 0 else chars[chars.length() - 1]
		else:
			# A String is not mutable in place, so the character is REPLACED by
			# rebuilding around it — `s[i] = c` parses and does nothing.
			var pos := chars.find(typed[at])
			var next := chars[wrapi(pos - step.y, 0, chars.length())]
			typed = typed.substr(0, at) + next + typed.substr(at + 1)
		seat["name"] = typed
		Audio.play("ui_move")


## Typed names for the KEYBOARD seat. Routed by DEVICE and not by "whoever is
## naming": with two people naming at once, anything else would put one player's
## typing into the other's box.
func _input(event: InputEvent) -> void:
	if _leaving or not (event is InputEventKey) or not event.pressed:
		return
	for i in _seats.size():
		var seat: Dictionary = _seats[i]
		if int(seat["device"]) >= 0 or int(seat["state"]) != State.NAMING:
			continue
		var key := event as InputEventKey
		if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
			_type(i, Vector2i.ZERO, true, false)
			return
		if key.keycode == KEY_BACKSPACE or key.keycode == KEY_ESCAPE:
			_type(i, Vector2i.ZERO, false, true)
			return
		var typed := char(key.unicode).to_upper()
		if typed.length() == 1 and Accounts.NAME_CHARS.contains(typed) \
				and str(seat["name"]).length() < Accounts.MAX_NAME:
			seat["name"] = str(seat["name"]) + typed
			seat["cursor"] = str(seat["name"]).length()
			Audio.play("ui_move")
		return


func _taken_by(name: String) -> int:
	for i in _seats.size():
		if int(_seats[i]["state"]) == State.READY and str(_seats[i]["name"]) == name:
			return i
	return -1


func _all_ready() -> bool:
	for s in _seats:
		if int(s["state"]) != State.READY:
			return false
	return not _seats.is_empty()


## Everyone is in. Hand the seating to GameState and go and build the playlist.
func _continue() -> void:
	_leaving = true
	commit_seats()
	Audio.play("ui_accept")
	get_tree().change_scene_to_file(PLAYLIST_SCENE)


## WHAT THIS SCREEN PRODUCES, split from the act of leaving it — for the reason
## `SettingsOverlay.exit_scene` is split the same way: a test that really changes
## scene frees itself mid-run, so the thing worth asserting (that the seating
## reaches GameState in seat order, devices and names together) has to be
## performable without the navigation that follows it.
func commit_seats() -> void:
	var devices: Array[int] = []
	var names: Array[String] = []
	for s in _seats:
		devices.append(int(s["device"]))
		names.append(str(s["name"]))
	GameState.player_devices = devices
	GameState.player_accounts = names


# --- the picture --------------------------------------------------------------

func _rows(index: int) -> Array:
	return _cards[index]["rows"]


func _rebuild_all_rows() -> void:
	for i in _cards.size():
		_rebuild_rows(i)


## An account list is REBUILT rather than repainted only when the roster itself
## changes (somebody made an account), because building Labels is the expensive
## half and the hover is just a colour.
func _rebuild_rows(index: int) -> void:
	var card: Dictionary = _cards[index]
	var list: VBoxContainer = card["list"]
	for c in list.get_children():
		c.queue_free()
		list.remove_child(c)
	var rows: Array = Accounts.names()
	rows.append(NEW_ROW)
	card["rows"] = rows
	var labels: Array = []
	for row in rows:
		var l := Label.new()
		l.text = str(row)
		l.add_theme_font_size_override("font_size", 18)
		list.add_child(l)
		labels.append(l)
	card["row_labels"] = labels


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
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	column.add_child(_text("SIGN IN", 46, ACCENT))
	column.add_child(_text(
		"Press START on the controller you are holding, then choose your account",
		15, DIM))
	column.add_child(_spacer(10))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	for i in _seats.size():
		row.add_child(_build_card(i))

	column.add_child(_spacer(12))
	_footer = _text("", 17, DIM)
	column.add_child(_footer)
	column.add_child(_text(
		"A choose    ·    B back    ·    stick up and down to pick a name",
		13, FAINT))


func _build_card(index: int) -> Control:
	var panel := PanelContainer.new()
	# WIDE ENOUGH FOR A NAME AND TALL ENOUGH FOR THE LIST, and the same size in
	# every state: a card that resizes as its owner signs in makes the other three
	# cards jump sideways while their owners are reading them.
	panel.custom_minimum_size = Vector2(268, 380)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var tag := _text("P%d" % (index + 1), 26, PLAYER_COLORS[index % PLAYER_COLORS.size()])
	box.add_child(tag)
	var device := _text("", 13, FAINT)
	box.add_child(device)
	box.add_child(_spacer(4))
	var state := _text("", 20, Color(0.92, 0.94, 0.98))
	box.add_child(state)
	var detail := _text("", 13, DIM)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size = Vector2(236, 34)
	box.add_child(detail)
	box.add_child(_spacer(2))
	# THE LIST SCROLLS, because the number of accounts on a machine only ever
	# goes up. A card sized to the four names it has today is a card that quietly
	# prints the fifth one through its own border, and the row a player cannot
	# see is the one they are about to sign in as.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(236, 210)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	list.custom_minimum_size = Vector2(224, 0)
	list.alignment = BoxContainer.ALIGNMENT_BEGIN
	scroll.add_child(list)

	# WHAT A FINISHED CARD SAYS. Signed in, the list goes away and leaves two
	# thirds of the card empty — and an empty card is exactly as informative as
	# an unclaimed one from across a room, which is the distance this screen is
	# read from. So it fills with the two things worth knowing: that this seat is
	# DONE, in the player's own colour, and the record they are bringing to the
	# match.
	var ready := _text("", 22, PLAYER_COLORS[index % PLAYER_COLORS.size()])
	box.add_child(_spacer(6))
	box.add_child(ready)
	var career := _text("", 13, DIM)
	box.add_child(career)

	var card := {
		"panel": panel, "tag": tag, "device": device, "state": state,
		"detail": detail, "list": list, "scroll": scroll, "rows": [],
		"row_labels": [], "shown_row": -1, "ready": ready, "career": career,
	}
	_cards.append(card)
	_paint_card(card, false, PLAYER_COLORS[index % PLAYER_COLORS.size()])
	return panel


func _paint_card(card: Dictionary, on: bool, colour: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = colour if on else PANEL_EDGE
	sb.set_border_width_all(3 if on else 2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(14)
	(card["panel"] as PanelContainer).add_theme_stylebox_override("panel", sb)


## Repaint every card from its seat — and DO NOTHING for a card that has not
## changed, which is most of them most of the time.
##
## THIS RUNS EVERY FRAME, so it is under house rule 1 and house rule 5. Painting
## a card builds a `StyleBoxFlat`, so an unconditional repaint is four material
## allocations a frame for a screen where nothing is happening between presses;
## writing `Label.text` re-shapes its glyphs whether or not the string changed;
## and building the career line allocates the string before anything can compare
## it. A per-seat SIGNATURE of everything drawn is one comparison against all
## three — the same trick the Conquest deploy screen already uses.
func _refresh() -> void:
	for i in _seats.size():
		var seat: Dictionary = _seats[i]
		var card: Dictionary = _cards[i]
		var sig := [seat["claimed"], seat["state"], seat["device"], seat["row"],
			seat["name"], seat["cursor"], _rows(i).size()]
		if card.get("sig") == sig:
			continue
		card["sig"] = sig
		var colour: Color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
		var claimed: bool = seat["claimed"]
		_paint_card(card, claimed, colour)
		var done := int(seat["state"]) == State.READY
		(card["ready"] as Label).visible = done
		(card["career"] as Label).visible = done
		_set_text(card["device"], Controls.device_label(int(seat["device"]))
			if claimed else "")
		var rows_visible := int(seat["state"]) == State.PICKING
		(card["scroll"] as ScrollContainer).visible = rows_visible
		match int(seat["state"]):
			State.EMPTY:
				_set_text(card["state"], "PRESS START")
				_set_text(card["detail"], "Any controller. The one you press with is the one you play with")
			State.PICKING:
				_set_text(card["state"], "CHOOSE ACCOUNT")
				# THE CAREER LINE GOES ABOVE THE LIST, not on the row. On the row
				# it is name-plus-three-figures on one line inside a 240 px card,
				# which ran out through the card's own border — and it could not
				# be shortened either, because the numbers are the reason anybody
				# looks at it. Up here it is the one line describing whatever the
				# cursor is on, and it wraps.
				_set_text(card["detail"], _hover_blurb(i))
				_paint_rows(i)
			State.NAMING:
				_set_text(card["state"], _name_display(seat))
				_set_text(card["detail"],
					"Up and down to change a letter, left and right to move.  A to confirm")
			State.READY:
				_set_text(card["state"], str(seat["name"]))
				_set_text(card["detail"], Accounts.summary(str(seat["name"])))
				_set_text(card["ready"], "READY")
				_set_text(card["career"], _career_lines(str(seat["name"])))
	# The footer counts who is left, so it only changes when somebody finishes —
	# and it is one string built per frame otherwise.
	var waiting := 0
	for s in _seats:
		if int(s["state"]) != State.READY:
			waiting += 1
	if waiting != _waiting:
		_waiting = waiting
		_set_text(_footer, _footer_text(waiting))


## The name being typed, with the cursor shown UNDER the letter it will change —
## a caret drawn in the middle of a word is the letter you are on, and a caret at
## the end is the letter you are about to add.
func _name_display(seat: Dictionary) -> String:
	var name: String = seat["name"]
	var at: int = clampi(int(seat["cursor"]), 0, name.length())
	if at >= name.length():
		return name + "_"
	return name.substr(0, at) + "[" + name[at] + "]" + name.substr(at + 1)


func _paint_rows(index: int) -> void:
	var seat: Dictionary = _seats[index]
	var card: Dictionary = _cards[index]
	var labels: Array = card["row_labels"]
	var rows: Array = card["rows"]
	var colour: Color = PLAYER_COLORS[index % PLAYER_COLORS.size()]
	for r in labels.size():
		var l: Label = labels[r]
		var row_name := str(rows[r])
		var taken := row_name != NEW_ROW and _taken_by(row_name) >= 0
		var here: bool = r == int(seat["row"])
		l.add_theme_color_override("font_color",
			colour if here else (TAKEN if taken else DIM))
		_set_text(l, row_name + ("   (in use)" if taken else ""))
	# ...and keep the cursor's row on screen. Only when it MOVES: a
	# ScrollContainer does not follow anything on its own, and asking it to every
	# frame is work for a picture that has not changed.
	var at: int = clampi(int(seat["row"]), 0, maxi(labels.size() - 1, 0))
	if at != int(card["shown_row"]) and at < labels.size():
		card["shown_row"] = at
		(card["scroll"] as ScrollContainer).ensure_control_visible(labels[at])


## The record a signed-in player is bringing with them, as two short lines. Not
## the same thing as `Accounts.summary` above it: that is the one-line answer to
## "is this me", and this is the bit worth reading while you wait for the others.
func _career_lines(name: String) -> String:
	var row := Accounts.stats(name)
	if int(row["matches"]) <= 0:
		return "First match"
	return "%d kills   ·   %d deaths\nbest streak %d   ·   %d headshots" % [
		int(row["kills"]), int(row["deaths"]),
		int(row["best_streak"]), int(row["headshots"])]


## What the row under this seat's cursor is worth: a career, or what making a new
## account will do.
func _hover_blurb(index: int) -> String:
	var card: Dictionary = _cards[index]
	var rows: Array = card["rows"]
	if rows.is_empty():
		return ""
	var at: int = clampi(int(_seats[index]["row"]), 0, rows.size() - 1)
	var row_name := str(rows[at])
	if row_name == NEW_ROW:
		return "Type a name. It keeps your controls and your record from here on"
	if _taken_by(row_name) >= 0:
		return "Already signed in on another controller"
	return Accounts.summary(row_name)


func _footer_text(waiting: int) -> String:
	if waiting > 0:
		return "Waiting for %d of %d" % [waiting, _seats.size()]
	return "PLAYER 1 — PRESS START TO CONTINUE"


func _set_text(l: Label, text: String) -> void:
	if l.text != text:
		l.text = text


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
