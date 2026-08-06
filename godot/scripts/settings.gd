extends Control
## Controls settings screen, reached from the menu. One profile at a time —
## the keyboard, the shared pad layout, or one specific pad — with a row per
## rebindable control. Pressing a row listens for the next input and binds it.
##
## Built in code in the menu's style, and driven by the built-in ui_* actions so
## it can be operated from the keyboard or from any pad (which matters: you have
## to be able to reach this screen with the controller you're trying to fix).
##
## All the binding logic lives in Controls; this file is the screen.


const BG_COLOR := Color(0.06, 0.07, 0.09)
const ACCENT := Color(0.45, 0.72, 1.0)
const DIM := Color(0.62, 0.66, 0.72)
const FAINT := Color(0.42, 0.46, 0.52)
const LISTEN_COLOR := Color(1.0, 0.78, 0.35)

## Profiles in the order the picker cycles them, which is also the order it opens
## in: the shared pad layout first, because everybody plays on a pad and the
## keyboard is the odd one out now rather than the default. The rest are pad
## device indices, with Controls.ALL_PADS as the shared one.
const KEYBOARD := -2
const PROFILES: Array[int] = [Controls.ALL_PADS, 0, 1, 2, 3, KEYBOARD]

var _profile := 0            # index into PROFILES
var _listening := ""         # control id being rebound, "" when idle
var _listen_armed := false   # ...and whether the press that started it has passed
var _rows_box: VBoxContainer
var _profile_button: Button
var _hint: Label
var _rows := {}              # control id -> the button showing it
var _death_button: Button    # the DEATH STYLE toggle (a game option, not a binding)
var _quality_button: Button  # GRAPHICS quality tier — see `Quality`
var _fps_button: Button      # the FRAME CAP, which is a smoothness setting


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Controls.ensure_loaded()
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
	column.add_theme_constant_override("separation", 6)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(column)

	column.add_child(_label("CONTROLS", 38, ACCENT))
	column.add_child(_spacer(8))

	_profile_button = _button("")
	_profile_button.pressed.connect(_cycle_profile)
	column.add_child(_profile_button)
	column.add_child(_spacer(8))

	# Seventeen rows plus the chrome has to fit a 1080-tall viewport with no
	# scrolling, so the list is deliberately tight.
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 1)
	column.add_child(_rows_box)

	column.add_child(_spacer(8))
	_hint = _label("", 15, FAINT)
	column.add_child(_hint)
	column.add_child(_spacer(6))

	# GAME OPTIONS. Not bindings, and they know it — this screen is the only
	# options screen the game has, so they are parked at the bottom of it rather
	# than not existing. When there are more than a couple of these they want a
	# SETTINGS screen of their own off the menu; Controls._options is already
	# separate from the bindings so moving them is a screen, not a migration.
	column.add_child(_spacer(6))
	_death_button = _button("")
	_death_button.pressed.connect(func() -> void:
		Controls.next_death_style()
		_refresh())
	column.add_child(_death_button)

	# GRAPHICS QUALITY and the FRAME CAP. Both cycle rather than opening a
	# dropdown, because this screen is a column of buttons driven by a pad and a
	# two-or-three-value setting is not worth a list.
	_quality_button = _button("")
	_quality_button.pressed.connect(func() -> void:
		var choices: Array = Controls.QUALITY_CHOICES
		var i := choices.find(Controls.graphics_quality())
		Controls.set_graphics_quality(choices[(i + 1) % choices.size()])
		# Take effect immediately: the menu behind this screen is already rendering
		# and the next match reads the same numbers on the way up.
		Quality.apply_global()
		_refresh())
	column.add_child(_quality_button)

	_fps_button = _button("")
	_fps_button.pressed.connect(func() -> void:
		var choices: Array = Controls.FPS_CHOICES
		var i := choices.find(Controls.fps_cap())
		Controls.set_fps_cap(choices[(i + 1) % choices.size()])
		Quality.apply_fps_cap()
		_refresh())
	column.add_child(_fps_button)

	var reset := _button("RESET TO DEFAULTS")
	reset.pressed.connect(func() -> void:
		Controls.reset_defaults()
		_refresh())
	column.add_child(reset)

	var back := _button("BACK")
	back.pressed.connect(_go_back)
	column.add_child(back)

	_rebuild_rows()


## The rows change with the profile: a pad steers with its stick, so the four
## movement controls only exist on the keyboard.
func _rebuild_rows() -> void:
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	_rows.clear()
	var first: Button = null
	for entry in Controls.ACTIONS:
		if not _is_keyboard() and not entry["pad"]:
			continue
		var id: String = entry["id"]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 16)
		var name_label := _label(entry["name"], 17, DIM)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.custom_minimum_size = Vector2(260, 0)
		line.add_child(name_label)
		var value := _button("")
		value.custom_minimum_size = Vector2(240, 32)
		value.add_theme_font_size_override("font_size", 17)
		value.pressed.connect(_begin_listen.bind(id))
		line.add_child(value)
		_rows_box.add_child(line)
		_rows[id] = value
		if first == null:
			first = value
	_refresh()
	if first:
		first.grab_focus()


func _refresh() -> void:
	_profile_button.text = "DEVICE  %s" % _profile_name()
	if _death_button:
		_death_button.text = "DEATH STYLE  %s" % Controls.DEATH_NAMES.get(
			Controls.death_style(), "?")
	if _quality_button:
		_quality_button.text = "GRAPHICS  %s" % Quality.tier_label()
	if _fps_button:
		var cap := Controls.fps_cap()
		# A cap is not a target: on a machine that cannot hold 60, capping at 30
		# is the SMOOTHEST setting rather than a worse one, because every frame
		# then arrives on time. Worth saying on the button.
		_fps_button.text = "FRAME CAP  %s" % ("DISPLAY" if cap == 0 else str(cap))
	for id in _rows:
		var button: Button = _rows[id]
		if id == _listening:
			button.text = "PRESS AN INPUT"
			button.add_theme_color_override("font_color", LISTEN_COLOR)
			button.add_theme_color_override("font_focus_color", LISTEN_COLOR)
			continue
		var text := Controls.key_label(id) if _is_keyboard() \
			else Controls.pad_label(_device(), id)
		# A pad with its own binding is marked, so it's obvious which rows this
		# pad has taken off the shared layout.
		if Controls.has_override(_device(), id) and not _is_keyboard():
			text += " *"
		button.text = text
		button.add_theme_color_override("font_color", Color(0.88, 0.91, 0.95))
		button.add_theme_color_override("font_focus_color", ACCENT)
	_refresh_hint()


func _refresh_hint() -> void:
	if not _listening.is_empty():
		if _is_keyboard():
			_hint.text = "Press the key to use.    START / ESC cancels."
		elif _device() == Controls.ALL_PADS:
			_hint.text = "Press the button or trigger to use.    START / ESC cancels."
		else:
			_hint.text = "Press the button or trigger to use.    START / ESC cancels." \
				+ "    BACK clears this pad's override."
		return
	if _is_keyboard():
		_hint.text = "A / Enter on a row rebinds it.    Movement is only on the keyboard."
	elif _device() == Controls.ALL_PADS:
		_hint.text = "A on a row rebinds it. Every pad uses this unless it has its own" \
			+ " — or player 1 has rebound it."
	elif _device() == Controls.P1_PAD:
		_hint.text = "A rebinds. Player 1's layout is what pads 2-4 use unless they" \
			+ " have their own."
	else:
		_hint.text = "A rebinds. * = pad %d's own; unmarked rows follow player 1." \
			% (_device() + 1)


func _cycle_profile() -> void:
	_listening = ""
	_profile = wrapi(_profile + 1, 0, PROFILES.size())
	_rebuild_rows()


func _is_keyboard() -> bool:
	return PROFILES[_profile] == KEYBOARD


## The pad device this profile edits. Meaningless while _is_keyboard().
func _device() -> int:
	return PROFILES[_profile]


func _profile_name() -> String:
	return "KEYBOARD + MOUSE" if _is_keyboard() else Controls.device_label(_device())


## Start listening for the input to bind. The press that got us here is still
## being dispatched, so nothing is captured until the next frame — otherwise the
## Enter (or A) that opened the row would immediately bind itself.
func _begin_listen(id: String) -> void:
	_listening = id
	_listen_armed = false
	_refresh()
	await get_tree().process_frame
	if not is_inside_tree():
		return  # left the screen inside that frame; there is nothing to arm
	_listen_armed = true


## While listening, every input belongs to us: swallow it all so it can't also
## press the focused button or walk the list.
func _input(event: InputEvent) -> void:
	if _listening.is_empty():
		return
	get_viewport().set_input_as_handled()
	if not _listen_armed:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_end_listen()
			return
		# Backspace on a specific pad hands the row back to the shared layout.
		if event.keycode == KEY_BACKSPACE and not _is_keyboard():
			Controls.clear_override(_device(), _listening)
			_end_listen()
			return
	# The pad's own way out. A listen swallows everything so it can capture any
	# button, which leaves a player with no keyboard trapped in the row they
	# opened — so START always cancels and BACK always clears, and neither can be
	# bound from a pad. Nothing is lost: START is on no control, and the only way
	# you would want BACK on this row is the binding clearing already gives you.
	# START cancels on the KEYBOARD profile too, where a pad can't bind anything
	# and so could otherwise open a row it has no way to close.
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_START:
			_end_listen()
			return
		if not _is_keyboard() and event.button_index == JOY_BUTTON_BACK \
				and _device() != Controls.ALL_PADS:
			Controls.clear_override(_device(), _listening)
			_end_listen()
			return
	if _is_keyboard():
		if Controls.bind_key(_listening, event):
			_end_listen()
		return
	# A pad profile: only accept pad input, and for one specific pad, only from
	# that pad — otherwise player 1 rebinds player 3's controller by accident.
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	if _device() != Controls.ALL_PADS and event.device != _device():
		return
	if Controls.bind_pad(_device(), _listening, event):
		_end_listen()


func _end_listen() -> void:
	_listening = ""
	_listen_armed = false
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if _listening.is_empty() and event.is_action_pressed("ui_cancel"):
		_go_back()


## BACK GOES WHERE YOU CAME FROM (`GameState.settings_return`), not always to the
## match-setup menu — three screens can reach this one now.
##
## AND WHATEVER WAS CHANGED HERE IS THEIRS. A player signed in on a device owns
## that device's configuration (see `Accounts`), so leaving this screen writes it
## back to their account. Without it, a rebind made before the match is kept only
## if they then go on to finish a match, which is a rule nobody could guess.
func _go_back() -> void:
	for i in GameState.player_accounts.size():
		var who := GameState.account_for(i)
		if not who.is_empty():
			Accounts.capture(who, GameState.device_for_player(i))
	get_tree().change_scene_to_file(GameState.settings_return)


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 38)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", Color(0.88, 0.91, 0.95))
	b.add_theme_color_override("font_focus_color", ACCENT)
	b.add_theme_color_override("font_hover_color", ACCENT)
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
