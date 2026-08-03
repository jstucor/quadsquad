extends Control
## The CHARACTER SELECT screen for one viewport: pick one of your side's four
## fixed classes, the command post you come back in on (Conquest), and deploy.
## Shown whenever the match is on FACTION classes (GameState.class_mode), in any
## game mode — it was Conquest's screen, but the class source is a setting now.
##
## It is built out of BoxScreen, which is the buy screen's own mechanic and its
## own look: a grid of bordered boxes with a free cursor over them, the box under
## the cursor in the player's colour, accept to open one, a caret on the line
## inside, back to close. A player who has learned the buy screen has already
## learned this one, which is the whole reason it is not its own layout.
##
## Player owns the selection and the input (spawn_class / spawn_post, driven by
## that player's own device in _update_pick_input); this draws it, resolves which
## box the cursor is over, and shows on death / hides on spawn.
##
## Its own script — not a per-frame lambda on the tree — so its refresh dies with
## the HUD instead of leaking a closure onto process_frame across a map change.

var player: Player
var color := Color.WHITE

var _panel: Control
var _dim: ColorRect
var _title: Label
var _held: Label
var _class_names: Array[Label] = []
var _class_blurb: Label
var _post_lines: Label
var _spawn: Label
var _blurb: Label
var _prompt: Label
var _cursor: Control
var _boxes: Array[PanelContainer] = []
var _m: Dictionary


func setup(p: Player, c: Color) -> void:
	player = p
	color = c
	_m = BoxScreen.metrics()
	_build()
	visible = false
	player.died.connect(_on_died)
	player.respawned.connect(func() -> void: visible = false)
	player.buy_changed.connect(func(_row: int) -> void: _dirty = true)
	player.deploy_ready.connect(func() -> void: _dirty = true)


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = BoxScreen.DEATH_DIM
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 4)
	add_child(column)

	_title = BoxScreen.label("DEPLOY", _m["title"], color)
	column.add_child(_title)
	# The front line in one line: what your side holds, and what it costs to die.
	# Conquest only — nothing else has posts or reinforcements to report.
	_held = BoxScreen.label("", _m["head"], BoxScreen.HEAD)
	column.add_child(_held)
	column.add_child(BoxScreen.spacer(4))

	# CLASS and DEPLOY POST side by side, exactly as the buy screen lays its
	# categories out, so the two screens read as the same furniture.
	var grid := GridContainer.new()
	grid.columns = Player.BUY_GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	column.add_child(grid)

	_boxes.resize(Player.PICK_BOXES)
	var classes := GameState.classes_for(player.team)
	var class_box := _box(grid, "CLASS", Player.PICK_CLASS_BOX)
	for i in classes.size():
		var row := BoxScreen.label("", _m["text"], Color(1, 1, 1, 0.85))
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size = Vector2(_m["name"] + _m["value"] * 0.5, 0)
		class_box.add_child(row)
		_class_names.append(row)

	var post_box := _box(grid, "DEPLOY POST", Player.PICK_POST_BOX)
	_post_lines = BoxScreen.label("", _m["text"], Color(1, 1, 1, 0.85))
	_post_lines.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_post_lines.custom_minimum_size = Vector2(_m["name"] + _m["value"] * 0.5, 0)
	post_box.add_child(_post_lines)

	# What the selected class actually is, under the grid — the one thing the
	# buy screen gets from prices and this screen has to say out loud.
	column.add_child(BoxScreen.spacer(4))
	_class_blurb = BoxScreen.label("", _m["head"], BoxScreen.BLURB)
	column.add_child(_class_blurb)

	# THE SPAWN BOX: as wide as the grid and under it, the same target the buy
	# screen deploys from, and where the cursor opens.
	column.add_child(BoxScreen.spacer(4))
	var spawn_frame := PanelContainer.new()
	spawn_frame.add_theme_stylebox_override("panel", BoxScreen.panel(BoxScreen.EDGE))
	column.add_child(spawn_frame)
	_boxes[Player.PICK_SPAWN_BOX] = spawn_frame
	_spawn = BoxScreen.label("", _m["head"] + 4, BoxScreen.SPAWN_READY)
	spawn_frame.add_child(_spawn)

	column.add_child(BoxScreen.spacer(4))
	_blurb = BoxScreen.label("", _m["head"] + 1, BoxScreen.BLURB)
	column.add_child(_blurb)
	_prompt = BoxScreen.label("", _m["head"] + 2, BoxScreen.PROMPT)
	column.add_child(_prompt)

	# The cursor reticle, drawn over the boxes.
	_cursor = Control.new()
	_cursor.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.draw.connect(func() -> void:
		BoxScreen.draw_cursor(_cursor, player, _boxes, color))
	add_child(_cursor)


## One titled category box, registered at its Player box index.
func _box(grid: GridContainer, title: String, at: int) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", BoxScreen.panel(BoxScreen.EDGE))
	grid.add_child(frame)
	_boxes[at] = frame
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 1)
	frame.add_child(inner)
	inner.add_child(BoxScreen.label(title, _m["head"], BoxScreen.HEAD))
	return inner


func _on_died(eliminated: bool) -> void:
	_title.text = "ELIMINATED" if eliminated else "DEPLOY"
	_title.add_theme_color_override("font_color",
		BoxScreen.ELIMINATED if eliminated else color)
	_dim.color = BoxScreen.DEATH_DIM if eliminated else BoxScreen.DEPLOY_DIM
	visible = true
	_dirty = true
	_refresh()


# What the screen is currently showing. Assigning a Label's text re-shapes its
# glyphs whether or not the string changed, and this screen is up for whichever
# players are dead — so it rebuilds only when one of the things it displays has
# actually moved, rather than every frame for every dead player. The countdown
# is compared in WHOLE SECONDS, which is all it ever prints.
var _dirty := true
var _seen_revision := -1
var _seen_mine := -1
var _seen_tickets := -1
var _seen_post := -1
var _seen_class := -1
var _seen_wait := -1
var _seen_box := -1
var _seen_inside := false


func _process(_delta: float) -> void:
	if not visible:
		return
	# The cursor is live every frame — resolving it is one has_point sweep, and
	# it is the only thing on this screen that moves continuously.
	_cursor.queue_redraw()
	if BoxScreen.resolve(player, _boxes):
		_dirty = true
	var conquest := GameState.mode == GameState.Mode.CONQUEST
	var mine := GameState.posts_held(player.team) if conquest else 0
	var tickets := int(GameState.tickets.get(player.team, 0)) if conquest else 0
	var wait := -1 if player.deploy_armed() else maxi(ceili(player.deploy_wait()), 0)
	if not _dirty \
			and GameState.posts_revision == _seen_revision \
			and mine == _seen_mine and tickets == _seen_tickets \
			and player.spawn_post == _seen_post \
			and player.spawn_class == _seen_class and wait == _seen_wait \
			and player.buy_box == _seen_box and player.buy_inside == _seen_inside:
		return
	_dirty = false
	_seen_revision = GameState.posts_revision
	_seen_mine = mine
	_seen_tickets = tickets
	_seen_post = player.spawn_post
	_seen_class = player.spawn_class
	_seen_wait = wait
	_seen_box = player.buy_box
	_seen_inside = player.buy_inside
	_refresh()


func _refresh() -> void:
	var conquest := GameState.mode == GameState.Mode.CONQUEST
	var open := player.buy_inside

	# The tally of who holds what — the front line, at a glance. Conquest only.
	_held.visible = conquest
	if conquest:
		_held.text = "COMMAND POSTS   your side %d / %d   ·   reinforcements %d" % [
			GameState.posts_held(player.team), GameState.conquest_posts.size(),
			int(GameState.tickets.get(player.team, 0))]

	# The class list. The caret only exists while the box is OPEN, the same rule
	# the buy screen keeps: a caret on a line you cannot currently change is a lie.
	var classes := GameState.classes_for(player.team)
	var picked := clampi(player.spawn_class, 0, classes.size() - 1)
	var on_class := open and player.buy_box == Player.PICK_CLASS_BOX
	for i in _class_names.size():
		var here := i == picked
		var caret := "▸ " if (here and on_class) else ("· " if here else "  ")
		_class_names[i].text = "%s%s" % [caret, Loadout.FACTION_BUILDS[classes[i]]["name"]]
		_class_names[i].add_theme_color_override("font_color",
			color if (here and on_class) else Color(1, 1, 1, 0.72 if here else 0.5))
	_class_blurb.text = _class_summary(classes[picked])

	# The posts your side holds. Outside Conquest there are none, so the box goes
	# — hidden boxes reflow the grid and the cursor skips them for free.
	_boxes[Player.PICK_POST_BOX].visible = conquest
	if conquest:
		var owned := GameState.owned_posts(player.team)
		var on_post := open and player.buy_box == Player.PICK_POST_BOX
		var lines := PackedStringArray()
		if owned.is_empty():
			lines.append("  — none held —")
			lines.append("  deploying at base")
		else:
			var sel := clampi(player.spawn_post, 0, owned.size() - 1)
			for i in owned.size():
				var here := i == sel
				var caret := "▸ " if (here and on_post) else ("· " if here else "  ")
				lines.append("%s%s" % [caret, owned[i].post_name])
		_post_lines.text = "\n".join(lines)
		_post_lines.add_theme_color_override("font_color",
			color if on_post else Color(1, 1, 1, 0.72))

	BoxScreen.paint(_boxes, player.buy_box, open, color)

	# Count the lock-down out loud: a silent wait reads exactly like a match that
	# has failed to start.
	var a := player.buy_accept_name()
	if player.deploy_armed():
		_spawn.text = "SPAWN     %s" % a
		_spawn.add_theme_color_override("font_color", BoxScreen.SPAWN_READY)
	else:
		_spawn.text = "ready in %d..." % maxi(ceili(player.deploy_wait()), 0)
		_spawn.add_theme_color_override("font_color", BoxScreen.SPAWN_WAIT)

	# The blurb explains whatever the selector is pointing at, and the prompt says
	# what the buttons do RIGHT NOW — the same two buttons do different things in
	# the open and closed states.
	if open:
		_blurb.text = "up / down to choose"
		_prompt.text = "%s back" % player.buy_back_name()
	else:
		match player.buy_box:
			Player.PICK_SPAWN_BOX:
				_blurb.text = "Deploy as the class above"
			Player.PICK_POST_BOX:
				_blurb.text = "Where you come back in"
			_:
				_blurb.text = "Your side's four classes"
		_prompt.text = "move the cursor     %s to choose" % a


## One line describing a faction class. Built from the loadout itself (see
## Loadout.gear_summary), and CACHED: the four classes are fixed for the whole
## match, so re-deriving one every time the caret moves is four Loadout
## allocations a keypress for a string that cannot have changed.
var _summaries := {}


func _class_summary(index: int) -> String:
	if not _summaries.has(index):
		_summaries[index] = Loadout.faction_build(index).gear_summary()
	return _summaries[index]
