extends Node3D
## Split-screen bootstrap: builds the 2x2 SubViewport grid, spawns one player
## per quadrant at a level spawn point, and wires each viewport's camera and
## HUD to its player. The level itself lives in scenes/levels/ and registers
## its spawn points with GameState before this runs (child _ready first).

const PLAYER_COUNT := 4
const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")

const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.3, 0.3),
	Color(0.3, 0.6, 0.9),
	Color(0.4, 0.85, 0.4),
	Color(0.95, 0.8, 0.3),
]

@onready var level: Node3D = $Level


func _ready() -> void:
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
		level.add_child(player)
		var spawn := GameState.get_spawn_point(player.team, i)
		if spawn:
			player.global_transform = spawn.global_transform
		player.bind_camera(camera)

		viewport.add_child(_build_hud(player))


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

	var tickets := _full_rect_label("", 18, Color(1, 1, 1, 0.9))
	tickets.text = "Tickets %d" % GameState.tickets[player.team]
	tickets.offset_top = 10.0
	hud.add_child(tickets)
	GameState.tickets_changed.connect(func(team: int, count: int) -> void:
		if team == player.team:
			tickets.text = "Tickets %d" % count)

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

	return hud


func _full_rect_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
