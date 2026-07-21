extends Node3D
## Team-deathmatch bootstrap: loads the current map from the rotation, builds a
## SubViewport per human player, fills both teams up to the chosen size with AI,
## spawns everyone at their team's spawn points, wires each viewport's camera +
## HUD, and rotates to the next map when a team hits the score limit. The map
## itself (scenes/levels/*) registers its per-team spawn points before anyone
## spawns. Player count, team size and AI skill all come from the menu.

const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")
const BOT_SCENE := preload("res://scenes/actors/bot.tscn")
const MENU_SCENE := "res://scenes/menu.tscn"
const AI_RESPAWN_DELAY := 4.0  # team AI come back, unlike a player's bought squad
const MATCH_START_COUNTDOWN := 3  # seconds of GET READY once everyone has deployed
const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.3, 0.3),
	Color(0.3, 0.6, 0.9),
	Color(0.4, 0.85, 0.4),
	Color(0.95, 0.8, 0.3),
]
const MATCH_END_DELAY := 4.5  # seconds of victory banner before the next map

# HUD palette.
const HEAT_COOL_COLOR := Color(0.4, 0.8, 1.0, 0.9)
const HEAT_OVER_COLOR := Color(1.0, 0.3, 0.2, 0.95)
const ELIMINATED_COLOR := Color(1.0, 0.4, 0.35)
const DEATH_DIM := Color(0.16, 0.0, 0.0, 0.5)
const DEPLOY_DIM := Color(0.0, 0.0, 0.0, 0.55)

var level: Node3D

# The four viewports' copies of the shared readouts. GameState is an autoload
# that outlives the map, so its signals are wired ONCE to a method of this node
# and fan out to these — never to per-HUD lambdas. Godot only drops a connection
# when its target object is freed, and a lambda that doesn't touch `self` has no
# target, so the old map's HUD would keep firing into freed labels after a
# rotation. Player/weapon signals are exempt: they die with the same scene.
var _score_labels: Array[Label] = []
var _victory_banners: Array[Label] = []
var _countdown_labels: Array[Label] = []
var _deployed := {}          # players who have finished their loadout at least once
var _countdown_running := false


func _ready() -> void:
	GameState.reset_match()
	level = GameState.MAPS[GameState.map_index]["scene"].instantiate()
	add_child(level)  # its _ready registers the team spawn points

	var grid := GridContainer.new()
	# One human is full-screen, two split left/right, three or four go 2x2.
	grid.columns = 1 if GameState.human_players == 1 else 2
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(grid)

	for i in GameState.human_players:
		var container := SubViewportContainer.new()
		container.stretch = true
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_child(container)

		# own_world_3d stays false: all four viewports render the root
		# viewport's world, where the level lives.
		var viewport := SubViewport.new()
		container.add_child(viewport)

		var camera := Camera3D.new()
		viewport.add_child(camera)

		var player: Player = PLAYER_SCENE.instantiate()
		player.player_index = i
		player.input_device = i - 1  # P1 keyboard/mouse; P2..P4 joypads 0..2
		player.team = GameState.team_for_player(i)
		level.add_child(player)
		var spawn := GameState.get_spawn_point(player.team, _team_slot(i))
		if spawn:
			player.global_transform = spawn.global_transform
		player.bind_camera(camera)
		player.model.set_team_color(GameState.TEAM_COLORS[player.team])

		viewport.add_child(_build_hud(player))
		# The match waits for everyone's first deploy, so watch for it.
		player.respawned.connect(_on_player_deployed.bind(player))
		player.begin_deploy()  # after the HUD exists, so it sees the select screen

	_fill_teams_with_ai()
	GameState.match_countdown.connect(_show_countdown)
	GameState.score_changed.connect(_refresh_scores)
	GameState.match_won.connect(_show_victory)
	GameState.match_won.connect(_on_match_won)
	_refresh_scores()


## Nobody fights until every human has bought a loadout and deployed. The last
## one in starts a short countdown, and only then does GameState.match_live go
## true — which is what unfreezes players, bots and turrets alike.
func _on_player_deployed(player: Player) -> void:
	if GameState.match_live or _countdown_running:
		return
	_deployed[player] = true
	if _deployed.size() < GameState.human_players:
		return
	_countdown_running = true
	_tick_countdown(MATCH_START_COUNTDOWN)


func _tick_countdown(seconds: int) -> void:
	GameState.match_countdown.emit(seconds)
	if seconds <= 0:
		GameState.match_live = true
		GameState.match_began.emit()
		return
	get_tree().create_timer(1.0).timeout.connect(_tick_countdown.bind(seconds - 1))


## How many earlier players share this player's team (its spawn index).
func _team_slot(index: int) -> int:
	var slot := 0
	for j in index:
		if GameState.team_for_player(j) == GameState.team_for_player(index):
			slot += 1
	return slot


## Bring both teams up to the chosen size with AI. These are the match's own
## bots, not a player's bought squad: they have no owner and they respawn, so a
## 1v1 with a team size of 4 stays a 4v4 all match.
func _fill_teams_with_ai() -> void:
	for team in [GameState.Team.REPUBLIC, GameState.Team.CIS]:
		for n in GameState.ai_needed(team):
			_spawn_team_bot(team)


func _spawn_team_bot(team: int) -> void:
	if level == null or not is_instance_valid(level):
		return
	var bot: Bot = BOT_SCENE.instantiate()
	level.add_child(bot)
	bot.setup(null, team, GameState.ai_skill)  # no owner: it fights for the team
	var spawn := GameState.get_spawn_point(team)
	if spawn:
		bot.global_transform = GameState.clear_of_bodies(spawn.global_transform)
	bot.tree_exited.connect(_on_team_bot_lost.bind(team))


func _on_team_bot_lost(team: int) -> void:
	# Also fires while the scene is being torn down, when there's no tree to
	# schedule against and nothing left to reinforce.
	if not is_inside_tree() or GameState.match_over:
		return
	get_tree().create_timer(AI_RESPAWN_DELAY).timeout.connect(_spawn_team_bot.bind(team))


func _on_match_won(_team: int) -> void:
	get_tree().create_timer(MATCH_END_DELAY).timeout.connect(_next_map)


## After the victory banner: rotation mode moves to the next map on the roster,
## a single-map pick drops back to the menu so someone can choose again.
func _next_map() -> void:
	if not GameState.rotate_maps:
		get_tree().change_scene_to_file(MENU_SCENE)
		return
	GameState.map_index = (GameState.map_index + 1) % GameState.MAPS.size()
	get_tree().reload_current_scene()


## Per-viewport HUD. Each piece is built by its own function and wires itself
## to the player's signals, so nothing here has to be kept in sync by hand.
func _build_hud(player: Player) -> Control:
	var hud := Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var color: Color = PLAYER_COLORS[player.player_index]

	_add_player_tag(hud, player, color)
	_add_reticle(hud, player)
	_add_scoreboard(hud)
	_add_health(hud, player, color)
	_add_weapon_readout(hud, player, color)
	_add_gear_readout(hud, player, color)
	hud.add_child(_build_buy_screen(player, color))
	_add_victory_banner(hud)
	_add_countdown(hud)
	return hud


func _add_player_tag(hud: Control, player: Player, color: Color) -> void:
	var tag := Label.new()
	tag.text = "P%d" % (player.player_index + 1)
	tag.add_theme_font_size_override("font_size", 28)
	tag.add_theme_color_override("font_color", color)
	tag.position = Vector2(14, 8)
	hud.add_child(tag)


## Crosshair and scope overlay, built together because they are mutually
## exclusive: the bloom crosshair is the hip-fire reticle, the scope replaces it
## on scoped weapons, and neither belongs on screen while you're dead.
func _add_reticle(hud: Control, player: Player) -> void:
	# Four ticks whose gap tracks the live spread cone (grows as you spray,
	# recovers when you stop, tight when aimed).
	var crosshair := Control.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_bloom.bind(crosshair, player))
	get_tree().process_frame.connect(crosshair.queue_redraw)
	hud.add_child(crosshair)

	var scope := Control.new()
	scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope.draw.connect(_draw_scope.bind(scope))
	scope.resized.connect(scope.queue_redraw)
	hud.add_child(scope)

	var refresh := func() -> void:
		var scoped: bool = player.weapon.aiming and player.weapon.has_scope()
		var live := player.is_alive()
		scope.visible = scoped and live
		crosshair.visible = not scoped and live
	player.aim_changed.connect(func(_aiming: bool) -> void: refresh.call())
	player.weapon_changed.connect(func(_name: String) -> void: refresh.call())
	player.died.connect(func(_eliminated: bool) -> void: refresh.call())
	player.respawned.connect(func() -> void: refresh.call())
	refresh.call()


## Team-deathmatch score, top-centre. Filled in by _refresh_scores.
func _add_scoreboard(hud: Control) -> void:
	var score := _full_rect_label("", 20, Color(1, 1, 1, 0.95))
	score.offset_top = 8.0
	hud.add_child(score)
	_score_labels.append(score)


func _refresh_scores(_team := 0, _score := 0) -> void:
	var text := "%s  %d   :   %d  %s" % [
		GameState.TEAM_NAMES[GameState.Team.REPUBLIC],
		GameState.scores[GameState.Team.REPUBLIC],
		GameState.scores[GameState.Team.CIS],
		GameState.TEAM_NAMES[GameState.Team.CIS]]
	for label in _score_labels:
		label.text = text


func _add_health(hud: Control, player: Player, color: Color) -> void:
	var health := Label.new()
	health.add_theme_font_size_override("font_size", 22)
	health.add_theme_color_override("font_color", color)
	health.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	health.offset_left = 14.0
	health.offset_top = -40.0
	hud.add_child(health)
	var refresh := func(hp: float) -> void:
		health.text = "HP %d" % maxi(roundi(hp), 0)
	player.health_changed.connect(refresh)
	refresh.call(player.health)


## Weapon name plus the heat bar that stands in for ammo.
func _add_weapon_readout(hud: Control, player: Player, color: Color) -> void:
	var name_label := Label.new()
	name_label.text = player.weapon.display_name()
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", color)
	name_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	name_label.offset_left = -220.0
	name_label.offset_top = -44.0
	name_label.offset_right = -14.0
	name_label.offset_bottom = -22.0
	hud.add_child(name_label)
	player.weapon_changed.connect(func(n: String) -> void: name_label.text = n)

	var heat_bg := ColorRect.new()
	heat_bg.color = Color(1, 1, 1, 0.15)
	heat_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heat_bg.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	heat_bg.offset_left = -140.0
	heat_bg.offset_top = -20.0
	heat_bg.offset_right = -14.0
	heat_bg.offset_bottom = -12.0
	hud.add_child(heat_bg)

	var heat_fill := ColorRect.new()
	heat_fill.color = HEAT_COOL_COLOR
	heat_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heat_fill.anchor_right = 0.0
	heat_fill.anchor_bottom = 1.0
	heat_bg.add_child(heat_fill)
	player.weapon.heat_changed.connect(func(heat: float, over: bool) -> void:
		heat_fill.anchor_right = heat
		heat_fill.color = HEAT_OVER_COLOR if over else HEAT_COOL_COLOR)


## The GET READY / FIGHT call at the start of a match. Like the scoreboard, it
## is fed by ONE connection to the autoload rather than a lambda per viewport.
func _add_countdown(hud: Control) -> void:
	var label := _full_rect_label("", 44, Color(1, 0.93, 0.6))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.offset_top = -60.0
	label.visible = false
	hud.add_child(label)
	_countdown_labels.append(label)


func _show_countdown(seconds: int) -> void:
	for label in _countdown_labels:
		label.visible = true
		label.text = "GET READY   %d" % seconds if seconds > 0 else "FIGHT!"
	if seconds <= 0:
		# Let FIGHT! sit for a beat, then clear it.
		get_tree().create_timer(0.9).timeout.connect(_hide_countdown)


func _hide_countdown() -> void:
	for label in _countdown_labels:
		label.visible = false


## Hidden until a team wins, then shown in every viewport by _show_victory.
## Consumables you're carrying, above the weapon name. Hidden when you bought
## none, so a gun-only build has no dead HUD text.
func _add_gear_readout(hud: Control, player: Player, color: Color) -> void:
	var gear := Label.new()
	gear.add_theme_font_size_override("font_size", 15)
	gear.add_theme_color_override("font_color", Color(color, 0.85))
	gear.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	gear.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gear.offset_left = -220.0
	gear.offset_top = -64.0
	gear.offset_right = -14.0
	gear.offset_bottom = -46.0
	hud.add_child(gear)
	var refresh := func() -> void:
		var parts: Array[String] = []
		if player.gadget == Loadout.Gadget.JETPACK:
			parts.append("JET %d%%" % roundi(player.jet_fuel * 100.0))
		elif player.gadget == Loadout.Gadget.CABLE:
			var cd := player.cable_cooldown()
			parts.append("CABLE READY" if cd <= 0.0 else "CABLE %ds" % ceili(cd))
		elif player.gadget != Loadout.Gadget.NONE:
			parts.append(Loadout.GADGETS[player.gadget]["name"])
		if player.grenades_left > 0:
			parts.append("GRENADE x%d" % player.grenades_left)
		if player.medkits_left > 0:
			parts.append("MEDKIT x%d" % player.medkits_left)
		if player.squad.size() > 0:
			parts.append("SQUAD x%d" % player.squad.size())
		gear.text = "   ".join(parts)
	player.gear_changed.connect(func(_g: int, _m: int) -> void: refresh.call())
	player.squad_changed.connect(func(_alive: int) -> void: refresh.call())
	refresh.call()


func _add_victory_banner(hud: Control) -> void:
	var banner := _full_rect_label("", 40, Color(1, 1, 1, 1))
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.visible = false
	hud.add_child(banner)
	_victory_banners.append(banner)


func _show_victory(team: int) -> void:
	for banner in _victory_banners:
		banner.text = "%s WINS" % GameState.TEAM_NAMES[team]
		banner.add_theme_color_override("font_color", GameState.TEAM_COLORS[team])
		banner.visible = true


## The buy screen for one viewport: a dimmed backdrop, the budget, one row per
## purchasable thing with the cursor on the active row, a blurb for whatever the
## cursor is on, and the deploy prompt. Shown at match start (DEPLOY) and after
## every death (ELIMINATED). Each player drives their own quadrant, so all four
## shop at once; nobody spawns until they press deploy.
func _build_buy_screen(player: Player, color: Color) -> Control:
	var panel := Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = DEATH_DIM
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(dim)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)

	var title := _centred_label("ELIMINATED", 26, ELIMINATED_COLOR)
	column.add_child(title)
	var budget := _centred_label("", 17, Color(1, 1, 1, 0.9))
	column.add_child(budget)
	column.add_child(_spacer(8))

	# Two labels per row — name left, selection right, both fixed width — so the
	# list reads as aligned columns instead of ragged centred lines.
	# _refresh_buy_screen rewrites the text in place, so scrolling churns no nodes.
	var rows: Array[Label] = []
	var values: Array[Label] = []
	for i in Loadout.Row.size():
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		var name_label := _centred_label("", 16, Color(1, 1, 1, 0.85))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.custom_minimum_size = Vector2(190, 0)
		line.add_child(name_label)
		var value_label := _centred_label("", 16, Color(1, 1, 1, 0.85))
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.custom_minimum_size = Vector2(170, 0)
		line.add_child(value_label)
		column.add_child(line)
		rows.append(name_label)
		values.append(value_label)

	column.add_child(_spacer(8))
	var blurb := _centred_label("", 14, Color(0.7, 0.74, 0.8))
	column.add_child(blurb)
	var prompt := _centred_label("", 16, Color(0.62, 0.66, 0.72))
	column.add_child(prompt)
	column.add_child(_centred_label(
		"up / down pick a line     left / right change it", 13, Color(0.5, 0.54, 0.6)))

	var refresh := func() -> void:
		_refresh_buy_screen(player, color, rows, values, budget, blurb, prompt)
	player.buy_changed.connect(func(_row: int) -> void: refresh.call())
	player.deploy_ready.connect(func() -> void: refresh.call())
	player.died.connect(func(eliminated: bool) -> void:
		title.text = "ELIMINATED" if eliminated else "DEPLOY"
		title.add_theme_color_override("font_color",
			ELIMINATED_COLOR if eliminated else color)
		dim.color = DEATH_DIM if eliminated else DEPLOY_DIM
		panel.visible = true
		refresh.call())
	player.respawned.connect(func() -> void: panel.visible = false)
	refresh.call()
	return panel


## Rewrite the buy screen's text for the player's current pending build. The
## cursor row is bracketed and tinted; rows you can't currently afford to step
## up are still shown, they just refuse to change.
func _refresh_buy_screen(player: Player, color: Color, rows: Array[Label],
		values: Array[Label], budget: Label, blurb: Label, prompt: Label) -> void:
	var build := player.pending
	budget.text = "TOKENS  %d spent   %d left of %d" % [
		build.cost(), build.remaining(), Loadout.BUDGET]
	for i in rows.size():
		var selected := i == player.buy_row
		var tint := color if selected else Color(1, 1, 1, 0.72)
		rows[i].text = "%s %s" % ["\u25b8" if selected else " ", build.row_label(i)]
		var cost := build.row_cost(i)
		values[i].text = build.row_value(i)
		if cost > 0:
			values[i].text += "   %d" % cost
		rows[i].add_theme_color_override("font_color", tint)
		values[i].add_theme_color_override("font_color", tint)
	blurb.text = build.row_blurb(player.buy_row)
	# Count the lock down out loud: a silent "standby" for five seconds reads
	# exactly like a match that has failed to start.
	prompt.text = "%s  to deploy" % player.deploy_button_name() \
		if player.deploy_armed() else "ready in %d..." % ceili(player.deploy_wait())
	prompt.add_theme_color_override("font_color",
		Color(0.85, 0.95, 0.8) if player.deploy_armed() else Color(0.55, 0.58, 0.62))


## Bloom crosshair: four ticks at a radius that maps the weapon's current
## spread cone (half-angle) to screen pixels through the camera FOV.
func _draw_bloom(c: Control, player: Player) -> void:
	if not c.visible or c.size.y <= 0.0:
		return
	var spread := deg_to_rad(player.weapon.current_spread_deg())
	var fov := deg_to_rad(player.view_fov())
	var half_h := c.size.y * 0.5
	var radius := half_h * tan(spread) / maxf(tan(fov * 0.5), 0.001)
	radius = clampf(radius, 4.0, half_h * 0.92)
	var center := c.size * 0.5
	var col := Color(1, 1, 1, 0.85)
	var tick := 7.0
	c.draw_line(center + Vector2(0, -radius), center + Vector2(0, -radius - tick), col, 2.0)
	c.draw_line(center + Vector2(0, radius), center + Vector2(0, radius + tick), col, 2.0)
	c.draw_line(center + Vector2(-radius, 0), center + Vector2(-radius - tick, 0), col, 2.0)
	c.draw_line(center + Vector2(radius, 0), center + Vector2(radius + tick, 0), col, 2.0)
	c.draw_circle(center, 1.5, col)


func _draw_scope(c: Control) -> void:
	var s := c.size
	var center := s * 0.5
	var r: float = minf(s.x, s.y) * 0.42
	var diag := s.length()
	c.draw_arc(center, r + diag * 0.5, 0.0, TAU, 96, Color(0, 0, 0, 1.0), diag, false)
	c.draw_arc(center, r, 0.0, TAU, 96, Color(0, 0, 0, 0.9), 2.0, true)
	c.draw_line(Vector2(center.x, center.y - r), Vector2(center.x, center.y + r), Color(0, 0, 0, 0.5), 1.0)
	c.draw_line(Vector2(center.x - r, center.y), Vector2(center.x + r, center.y), Color(0, 0, 0, 0.5), 1.0)
	c.draw_circle(center, 2.0, Color(1, 0.25, 0.18))


## A row inside a VBox, as opposed to _full_rect_label which positions itself
## across the whole viewport.
func _centred_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return label


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


func _full_rect_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
