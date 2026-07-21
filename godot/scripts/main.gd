extends Node3D
## Team-deathmatch bootstrap: loads the current map from the rotation, builds
## the 2x2 SubViewport grid, spawns two players per team at their team's spawn
## points, wires each viewport's camera + HUD, and rotates to the next map when
## a team hits the score limit. The map itself (scenes/levels/*) registers its
## per-team spawn points with GameState before players spawn.

const PLAYER_COUNT := 4
const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")
const MENU_SCENE := "res://scenes/menu.tscn"

# 2v2 team assignment and per-player accent colour (for the corner tag).
const TEAMS: Array[int] = [
	GameState.Team.REPUBLIC, GameState.Team.REPUBLIC,
	GameState.Team.CIS, GameState.Team.CIS,
]
const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.3, 0.3),
	Color(0.3, 0.6, 0.9),
	Color(0.4, 0.85, 0.4),
	Color(0.95, 0.8, 0.3),
]
# Which class each viewport starts highlighted on — a spread across the roster,
# so the default four are all different. Everyone still picks for themselves.
const START_KITS: Array[int] = [0, 1, 2, 3]

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


func _ready() -> void:
	GameState.reset_match()
	level = GameState.MAPS[GameState.map_index]["scene"].instantiate()
	add_child(level)  # its _ready registers the team spawn points

	var grid := GridContainer.new()
	grid.columns = 2
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(grid)

	for i in PLAYER_COUNT:
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
		player.team = TEAMS[i]
		player.kit_index = START_KITS[i]
		level.add_child(player)
		var spawn := GameState.get_spawn_point(player.team, _team_slot(i))
		if spawn:
			player.global_transform = spawn.global_transform
		player.bind_camera(camera)
		player.model.set_team_color(GameState.TEAM_COLORS[player.team])

		viewport.add_child(_build_hud(player))
		player.begin_deploy()  # after the HUD exists, so it sees the select screen

	GameState.score_changed.connect(_refresh_scores)
	GameState.match_won.connect(_show_victory)
	GameState.match_won.connect(_on_match_won)
	_refresh_scores()


## How many earlier players share this player's team (its spawn index).
func _team_slot(index: int) -> int:
	var slot := 0
	for j in index:
		if TEAMS[j] == TEAMS[index]:
			slot += 1
	return slot


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
	hud.add_child(_build_class_select(player, color))
	_add_victory_banner(hud)
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
	player.died.connect(func(_secs: int, _killed: bool) -> void: refresh.call())
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


## Hidden until a team wins, then shown in every viewport by _show_victory.
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


## The class-select / death screen for one viewport: dimmed backdrop, the four
## class names in a row with the highlighted one lit, that class's loadout and
## stat blurb, and the countdown to deploying with it. Shown at match start
## (DEPLOY) and after every death (ELIMINATED) — the player's own device steps
## the highlight, so all four choose at once in their own quadrant.
func _build_class_select(player: Player, color: Color) -> Control:
	var panel := Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = DEATH_DIM
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(dim)

	var title := _full_rect_label("ELIMINATED", 30, ELIMINATED_COLOR)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.offset_bottom = -96.0
	panel.add_child(title)

	# The four class names side by side; the picked one is tinted + bracketed.
	var names := _full_rect_label("", 20, Color(1, 1, 1, 0.9))
	names.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	names.offset_bottom = -20.0
	panel.add_child(names)

	var loadout := _full_rect_label("", 17, Color(1, 1, 1, 0.85))
	loadout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loadout.offset_top = 24.0
	panel.add_child(loadout)

	var stats := _full_rect_label("", 15, Color(0.72, 0.76, 0.82))
	stats.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stats.offset_top = 62.0
	panel.add_child(stats)

	var countdown := _full_rect_label("", 20, Color(1, 1, 1, 0.9))
	countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown.offset_top = 104.0
	panel.add_child(countdown)

	var hint := _full_rect_label("move left / right to choose class", 14,
		Color(0.62, 0.66, 0.72))
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.offset_top = 140.0
	panel.add_child(hint)

	# The verb lives on the panel, not in a captured local: GDScript lambdas
	# capture by value, so `died` writing a local would never reach the
	# countdown lambda's copy of it.
	panel.set_meta("verb", "Respawning")
	var show_kit := func(index: int) -> void:
		var parts: Array[String] = []
		for k in Kit.count():
			var n: String = Kit.get_kit(k)["name"]
			parts.append("[ %s ]" % n if k == index else "  %s  " % n)
		names.text = " ".join(parts)
		names.add_theme_color_override("font_color", color)
		var kit := Kit.get_kit(index)
		loadout.text = Kit.weapon_line(index)
		stats.text = "%s   HP %d" % [kit["blurb"], roundi(kit["health"])]
	var set_countdown := func(secs: int) -> void:
		var verb: String = panel.get_meta("verb")
		countdown.text = "%s in %d" % [verb, secs] if secs > 0 else "%s..." % verb

	player.kit_previewed.connect(func(index: int) -> void: show_kit.call(index))
	player.died.connect(func(secs: int, was_killed: bool) -> void:
		panel.set_meta("verb", "Respawning" if was_killed else "Deploying")
		title.text = "ELIMINATED" if was_killed else "DEPLOY"
		title.add_theme_color_override("font_color",
			ELIMINATED_COLOR if was_killed else color)
		dim.color = DEATH_DIM if was_killed else DEPLOY_DIM
		panel.visible = true
		set_countdown.call(secs))
	player.respawn_countdown.connect(func(secs: int) -> void: set_countdown.call(secs))
	player.respawned.connect(func() -> void: panel.visible = false)
	show_kit.call(player.kit_index)
	return panel


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


func _full_rect_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
