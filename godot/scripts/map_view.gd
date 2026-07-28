extends Control
## The map screen for ONE player's viewport: a top-down sketch of the whole
## level with your squad on it, and the aiming surface for the mortar strike.
##
## It shows TEAMMATES only — the enemy is what you are trying to find, and
## handing four split-screen players a live enemy tracker would end the game.
## What it draws of the level comes from GameState.map_shapes, scanned from the
## world's box colliders at match start, so a new map needs no map artwork.
##
## Everything is read straight off the player each frame rather than pushed in
## by signals: it only redraws while it is open, so polling costs nothing the
## rest of the time.

const PAD := 0.05          # share of the viewport left as margin
# Strip reserved above the panel for the status line. It has to clear the
# scoreboard that sits along the top of every viewport, or the two overlap.
const HEADER := 44.0
const BG := Color(0.04, 0.05, 0.07, 0.94)
const BORDER := Color(0.45, 0.72, 1.0, 0.75)
const SHAPE_COLOR := Color(0.30, 0.34, 0.41, 0.95)
const GRID := Color(1, 1, 1, 0.055)
const GRID_STEP := 10.0    # metres between grid lines
const ZONE_COLOR := Color(1.0, 0.85, 0.35, 0.5)
const CURSOR_COLOR := Color(1.0, 0.45, 0.3)
const MORTAR_COLOR := Color(1.0, 0.68, 0.25)
const SELF_RING := Color(1, 1, 1, 0.9)
const DOT_R := 5.0
const SELF_R := 6.5
const FACING_LEN := 13.0
const LABEL_COLOR := Color(0.75, 0.80, 0.88)

var player: Player

var _area := Rect2()     # where the map is drawn, in control space
var _scale := 1.0        # pixels per metre
var _font: Font
var _font_size := 13


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)
	_font = ThemeDB.fallback_font


## Main calls this once with the player whose quadrant we live in.
func setup(p: Player) -> void:
	player = p
	p.map_toggled.connect(_on_map_toggled)


func _on_map_toggled(open: bool) -> void:
	visible = open
	set_process(open)  # idle again the moment it closes
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()  # the squad and the cursor both move while it is up


## Map the world's XZ onto the panel. World -Z is drawn UP, so the map is
## oriented the way the level is laid out rather than mirrored.
func _to_map(world: Vector3) -> Vector2:
	var c := GameState.map_center
	return _area.get_center() + Vector2(world.x - c.x, world.z - c.z) * _scale


func _draw() -> void:
	if player == null or size.x <= 0.0 or size.y <= 0.0:
		return
	_layout()
	draw_rect(_area.grow(6.0), BG, true)
	draw_rect(_area.grow(6.0), BORDER, false, 2.0)
	_draw_grid()
	_draw_shapes()
	_draw_zone()
	_draw_mortar()
	_draw_squad()
	_draw_cursor()
	_draw_legend()


## Fit the level's aspect ratio inside the viewport, so a long map stays long.
## A header strip is reserved INSIDE the control for the status line — drawing
## it above the panel put it off the top of the viewport.
func _layout() -> void:
	var margin := size * PAD
	var avail := Rect2(margin.x, margin.y + HEADER,
		size.x - margin.x * 2.0, size.y - margin.y * 2.0 - HEADER)
	var extents := GameState.map_extents
	var span := Vector2(maxf(extents.x, 1.0), maxf(extents.y, 1.0)) * 2.0
	_scale = minf(avail.size.x / span.x, avail.size.y / span.y)
	var drawn := span * _scale
	_area = Rect2(avail.position + (avail.size - drawn) * 0.5, drawn)


func _draw_grid() -> void:
	var c := GameState.map_center
	var e := GameState.map_extents
	var step := GRID_STEP * _scale
	if step < 12.0:
		return  # too dense to read on a quarter-screen viewport
	var x := c.x - e.x
	while x <= c.x + e.x:
		var px := _to_map(Vector3(x, 0, 0)).x
		draw_line(Vector2(px, _area.position.y), Vector2(px, _area.end.y), GRID, 1.0)
		x += GRID_STEP
	var z := c.z - e.y
	while z <= c.z + e.y:
		var py := _to_map(Vector3(0, 0, z)).y
		draw_line(Vector2(_area.position.x, py), Vector2(_area.end.x, py), GRID, 1.0)
		z += GRID_STEP


## Cover and walls, as filled quads. Rotation is honoured (the hand-authored
## hangar has angled geometry), so these are polygons rather than rects.
func _draw_shapes() -> void:
	for s in GameState.map_shapes:
		var at: Vector2 = s["pos"]
		var half: Vector2 = s["size"] * 0.5 * _scale
		var a: float = s["angle"]
		var centre := _to_map(Vector3(at.x, 0.0, at.y))
		var ux := Vector2(cos(a), -sin(a)) * half.x
		var uz := Vector2(sin(a), cos(a)) * half.y
		draw_colored_polygon(PackedVector2Array([
			centre - ux - uz, centre + ux - uz, centre + ux + uz, centre - ux + uz,
		]), SHAPE_COLOR)


func _draw_zone() -> void:
	if not GameState.zone_active:
		return
	var at := _to_map(GameState.zone_point)
	draw_circle(at, Zone.RADIUS * _scale, Color(ZONE_COLOR.r, ZONE_COLOR.g, ZONE_COLOR.b, 0.16))
	draw_arc(at, Zone.RADIUS * _scale, 0.0, TAU, 40, ZONE_COLOR, 2.0)


func _draw_mortar() -> void:
	var m := player.mortar()
	if m == null:
		return
	var at := _to_map(m.global_position)
	draw_arc(at, 7.0, 0.0, TAU, 16, MORTAR_COLOR, 2.0)
	draw_line(at - Vector2(0, 10), at + Vector2(0, 10), MORTAR_COLOR, 1.5)
	draw_line(at - Vector2(10, 0), at + Vector2(10, 0), MORTAR_COLOR, 1.5)


## Your squad: everyone on your team, you included. Bots are drawn smaller and
## unlabelled so the humans stand out at a glance.
func _draw_squad() -> void:
	for c in GameState.combatants:
		if c.team != player.team or not c.is_alive():
			continue
		var mine := c == player
		var at := _to_map(c.global_position)
		var col: Color = GameState.team_colors[c.team]
		var is_human := c is Player
		var r := SELF_R if mine else (DOT_R if is_human else DOT_R * 0.7)
		draw_circle(at, r, col if is_human else col.darkened(0.35))
		if mine:
			draw_arc(at, r + 3.0, 0.0, TAU, 20, SELF_RING, 1.5)
		# Which way they are facing: -Z is forward, and -Z is up on the map.
		var yaw: float = c.global_rotation.y
		var face := Vector2(-sin(yaw), -cos(yaw)) * FACING_LEN
		draw_line(at, at + face, col.lightened(0.3), 2.0)
		if is_human and not mine:
			draw_string(_font, at + Vector2(r + 4.0, -r), "P%d" % (c.player_index + 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, LABEL_COLOR)


## The strike cursor. It is always drawn — steering it is how you read the map —
## but it only turns hot when a mortar is up and off cooldown.
func _draw_cursor() -> void:
	var at := _to_map(Vector3(player.map_cursor.x, 0.0, player.map_cursor.y))
	var live := player.mortar_ready()
	var col := CURSOR_COLOR if live else Color(0.6, 0.63, 0.68, 0.8)
	var arm := 11.0
	draw_line(at - Vector2(arm, 0), at + Vector2(arm, 0), col, 1.5)
	draw_line(at - Vector2(0, arm), at + Vector2(0, arm), col, 1.5)
	if live:
		# Show the footprint the barrage will actually cover, so calling one in
		# is aiming rather than guessing.
		draw_arc(at, Mortar.SPREAD * _scale, 0.0, TAU, 28, col, 1.5)


func _draw_legend() -> void:
	var line := player.map_status()
	if line.is_empty():
		return
	# Wrapped to the VIEWPORT's remaining width, not the panel's: on a map whose
	# aspect ratio leaves the panel narrow, the panel width clips the line.
	draw_string(_font, Vector2(_area.position.x, _area.position.y - 11.0), line,
		HORIZONTAL_ALIGNMENT_LEFT, size.x - _area.position.x, _font_size + 1,
		LABEL_COLOR)
