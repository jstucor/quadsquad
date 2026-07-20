extends Node3D
## Team-deathmatch bootstrap: loads the current map from the rotation, builds
## the 2x2 SubViewport grid, spawns two players per team at their team's spawn
## points, wires each viewport's camera + HUD, and rotates to the next map when
## a team hits the score limit. The map itself (scenes/levels/*) registers its
## per-team spawn points with GameState before players spawn.

const PLAYER_COUNT := 4
const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")

# Map rotation. GameState.map_index selects the current one and advances on a win.
const MAPS: Array[PackedScene] = [
	preload("res://scenes/levels/crossfire.tscn"),
	preload("res://scenes/levels/foundry.tscn"),
	preload("res://scenes/levels/hangar.tscn"),
]

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
# A spread across the weapon roster (Weapon.Class enum order).
const START_CLASSES: Array[int] = [0, 1, 4, 7]  # Soldier, Sniper, HMG, RPG

const MATCH_END_DELAY := 4.5  # seconds of victory banner before the next map

var level: Node3D


func _ready() -> void:
	GameState.reset_match()
	level = MAPS[GameState.map_index].instantiate()
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
		player.weapon_class = START_CLASSES[i]
		level.add_child(player)
		var spawn := GameState.get_spawn_point(player.team, _team_slot(i))
		if spawn:
			player.global_transform = spawn.global_transform
		player.bind_camera(camera)
		player.model.set_team_color(GameState.TEAM_COLORS[player.team])

		viewport.add_child(_build_hud(player))

	GameState.match_won.connect(_on_match_won)


## How many earlier players share this player's team (its spawn index).
func _team_slot(index: int) -> int:
	var slot := 0
	for j in index:
		if TEAMS[j] == TEAMS[index]:
			slot += 1
	return slot


func _on_match_won(_team: int) -> void:
	get_tree().create_timer(MATCH_END_DELAY).timeout.connect(_next_map)


func _next_map() -> void:
	GameState.map_index = (GameState.map_index + 1) % MAPS.size()
	get_tree().reload_current_scene()


func _build_hud(player: Player) -> Control:
	var hud := Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var color: Color = PLAYER_COLORS[player.player_index]

	var tag := Label.new()
	tag.text = "P%d" % (player.player_index + 1)
	tag.add_theme_font_size_override("font_size", 28)
	tag.add_theme_color_override("font_color", color)
	tag.position = Vector2(14, 8)
	hud.add_child(tag)

	var crosshair := _full_rect_label("+", 24, Color(1, 1, 1, 0.8))
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud.add_child(crosshair)

	# Scope overlay (scoped weapons only, while aiming).
	var scope := Control.new()
	scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope.visible = false
	scope.draw.connect(_draw_scope.bind(scope))
	scope.resized.connect(scope.queue_redraw)
	hud.add_child(scope)
	var update_scope := func() -> void:
		scope.visible = player.weapon.aiming and player.weapon.has_scope()
		crosshair.visible = not scope.visible
	player.aim_changed.connect(func(_a: bool) -> void: update_scope.call())
	player.weapon_changed.connect(func(_n: String) -> void: update_scope.call())

	# Team-deathmatch scoreboard, top-centre.
	var score := _full_rect_label("", 20, Color(1, 1, 1, 0.95))
	score.offset_top = 8.0
	var refresh_score := func() -> void:
		score.text = "%s  %d   :   %d  %s" % [
			GameState.TEAM_NAMES[GameState.Team.REPUBLIC],
			GameState.scores[GameState.Team.REPUBLIC],
			GameState.scores[GameState.Team.CIS],
			GameState.TEAM_NAMES[GameState.Team.CIS]]
	refresh_score.call()
	GameState.score_changed.connect(func(_t: int, _s: int) -> void: refresh_score.call())
	hud.add_child(score)

	var health := Label.new()
	health.text = "HP 100"
	health.add_theme_font_size_override("font_size", 22)
	health.add_theme_color_override("font_color", color)
	health.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	health.offset_left = 14.0
	health.offset_top = -40.0
	hud.add_child(health)
	player.health_changed.connect(func(hp: float) -> void:
		health.text = "HP %d" % maxi(roundi(hp), 0))

	var weapon_label := Label.new()
	weapon_label.text = player.weapon.display_name()
	weapon_label.add_theme_font_size_override("font_size", 18)
	weapon_label.add_theme_color_override("font_color", color)
	weapon_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weapon_label.offset_left = -220.0
	weapon_label.offset_top = -44.0
	weapon_label.offset_right = -14.0
	weapon_label.offset_bottom = -22.0
	hud.add_child(weapon_label)
	player.weapon_changed.connect(func(n: String) -> void:
		weapon_label.text = n)

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
	heat_fill.color = Color(0.4, 0.8, 1.0, 0.9)
	heat_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heat_fill.anchor_left = 0.0
	heat_fill.anchor_top = 0.0
	heat_fill.anchor_right = 0.0
	heat_fill.anchor_bottom = 1.0
	heat_bg.add_child(heat_fill)
	player.weapon.heat_changed.connect(func(h: float, over: bool) -> void:
		heat_fill.anchor_right = h
		heat_fill.color = Color(1.0, 0.3, 0.2, 0.95) if over else Color(0.4, 0.8, 1.0, 0.9))

	# Victory banner (hidden until a team wins).
	var banner := _full_rect_label("", 40, Color(1, 1, 1, 1))
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.visible = false
	hud.add_child(banner)
	GameState.match_won.connect(func(team: int) -> void:
		banner.text = "%s WINS" % GameState.TEAM_NAMES[team]
		banner.add_theme_color_override("font_color", GameState.TEAM_COLORS[team])
		banner.visible = true)

	return hud


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
