extends Control
## The always-on minimap, top left of every player's viewport.
##
## THIS IS NOT A SMALL COPY OF THE MAP SCREEN. The map screen (`map_view.gd`) is
## the whole level at once, opened deliberately, and opening it STOPS you moving
## — reading it is a commitment. The minimap is the opposite bargain: it is up
## the whole time, it costs you nothing, and so it must only ever answer the two
## questions you can afford to ask mid-fight — WHERE AM I FACING and WHO IS NEAR
## ME. Everything the map screen shows and this does not (the mortar cursor, the
## grid, player labels, the level end to end) was left out for that reason, not
## for room.
##
## So it is a WINDOW, not the level: `RADIUS_M` metres around you, you at the
## centre. On a 260 m map the whole level squeezed into 130 pixels is a smear
## with four dots in it — true, and useless. A fixed metres-per-pixel window
## instead means the minimap reads the same on Boneyard as in a hangar, and it
## means a dot's distance from the middle is a real distance you can act on.
##
## NORTH-UP, not rotating with you. A rotating minimap is easier to steer by and
## it would then disagree with the map screen, which is north-up because a level
## laid out north-up is how everyone has already learned it. Two pictures of the
## same map that turn different ways is worse than either.
##
## WHO IT SHOWS is the same discipline the map screen and the thermal read both
## keep: TEAMMATES always, and enemies ONLY while your side has them scanned. A
## permanent enemy tracker on a shared screen ends the game — but a SCAN is a
## thing somebody spent a gadget on, it expires, and it is exactly the payoff the
## dart is bought for. The scan set is team-wide (`GameState.scanned`), so one
## player's dart lights the enemy up on all four of their side's minimaps.

## Metres from the centre to the edge of the window, measured on the SHORT axis
## (the corners reach about 1.4x this). It is a SQUARE and not the disc it was
## first drawn as, for one reason that is not taste: a Control clips to its RECT
## and there is nothing that clips to a circle, so the level's footprints ran
## straight out past the rim and the widget read as broken. A square also spends
## its corners on map instead of on nothing.
const RADIUS_M := 45.0
## Corner reach, for culling: nothing outside this can touch the window.
const CORNER_M := RADIUS_M * 1.45
## Widget size, keyed off how many players share the screen — the same rule the
## buy screen follows. A full-size widget runs over a quarter-screen viewport.
const SIZES := {1: 168.0, 2: 132.0, 3: 116.0, 4: 116.0}
const INSET := Vector2(12.0, 10.0)

const BG := Color(0.04, 0.05, 0.07, 0.8)
const SHAPE_COLOR := Color(0.32, 0.36, 0.44, 0.9)
const RING := Color(1, 1, 1, 0.10)
const SCAN_MARK := Color(0.55, 0.9, 1.0)      # matches Main.SCAN_MARK
const ZONE_COLOR := Color(1.0, 0.85, 0.35, 0.55)
const POST_NEUTRAL := Color(0.7, 0.72, 0.78)
const MORTAR_COLOR := Color(1.0, 0.68, 0.25)
const DOT_R := 3.6
const SELF_R := 4.6

## How far the player has to move, or turn, before the picture is worth
## re-recording. Everything on here is drawn relative to the player, so standing
## still means an identical canvas item sixty times a second, four viewports
## deep — the same discipline as the ability gauge's 64 quantised steps.
const MOVE_EPSILON := 0.35        # metres
const TURN_EPSILON := 0.04        # radians (~2.3 degrees)

var player: Player
## Passed in rather than reached for: `main.gd` has no `class_name` (deliberately
## — see the hit marker), so `Main.PLAYER_COLORS` does not resolve from here, and
## a widget asking the scene root for its own colour is the wrong direction anyway.
var color := Color.WHITE

var _radius := 62.0               # pixels
var _centre := Vector2.ZERO
var _scale := 1.0                 # pixels per metre
## Culling cache, in PACKED ARRAYS rather than the array of dictionaries
## `GameState.map_shapes` is. A big map is several hundred footprints, this walks
## all of them, and it runs four times over on every frame any player moves — so
## the four dictionary lookups per shape were the cost, not the geometry. Same
## trick and the same reason as `GameState.sample_combatants`: no hashing in the
## inner loop. Measured on Kashyyyk at 4 viewports, this took the HUD's share of
## the frame from ~0.9 ms back down into the noise.
var _sx := PackedFloat32Array()      # footprint centre, world X
var _sz := PackedFloat32Array()      # footprint centre, world Z
var _sbound := PackedFloat32Array()  # corner-to-centre, for the cull
var _shalf := PackedVector2Array()   # half extents
var _sangle := PackedFloat32Array()
var _was_at := Vector3(INF, INF, INF)
var _was_yaw := INF
var _was_scans := -1
var _was_posts := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Clips this control's own draw commands, which is the whole reason the
	# window is rectangular — see RADIUS_M.
	clip_contents = true
	var side: float = SIZES.get(GameState.human_players, 124.0)
	size = Vector2(side, side)
	position = INSET
	_radius = side * 0.5
	_centre = Vector2(_radius, _radius)
	_scale = _radius / RADIUS_M
	_cache_shapes()


func setup(p: Player, player_color: Color) -> void:
	player = p
	color = player_color
	# The full map screen is this same picture with no window on it, so having
	# both up is one of them drawing over the other for no gain. A METHOD, not a
	# lambda: the same rule the map screen follows.
	p.map_toggled.connect(_on_map_toggled)


func _on_map_toggled(open: bool) -> void:
	visible = not open


## The level's footprints, pre-reduced to a centre and a radius. `map_shapes` is
## scanned once at match start and never changes, so this is done once too.
func _cache_shapes() -> void:
	var n := GameState.map_shapes.size()
	_sx.resize(n)
	_sz.resize(n)
	_sbound.resize(n)
	_shalf.resize(n)
	_sangle.resize(n)
	for i in n:
		var s: Dictionary = GameState.map_shapes[i]
		var pos: Vector2 = s["pos"]
		var half: Vector2 = s["size"] * 0.5
		_sx[i] = pos.x
		_sz[i] = pos.y
		_shalf[i] = half
		_sangle[i] = s["angle"]
		# Corner-to-centre, so the cull never rejects a box whose corner is
		# inside the window while its centre is outside.
		_sbound[i] = half.length()


## Called from Main._tick_overlays. Returns true when the picture has actually
## moved — see MOVE_EPSILON.
##
## The gate is on the PLAYER because the whole picture is drawn relative to them,
## so their own movement is what redraws everything at once. But the DOTS move
## too, and gating on the player alone freezes your squad and every scanned
## contact on screen the moment you stand still — which is exactly when you are
## reading the thing. Rather than testing every contact's position (that walk is
## the cost this gate exists to avoid), a slow HEARTBEAT catches them: standing
## still the map ticks at BEAT_HZ, moving it is smooth because you are the one
## moving. Twelve is well under the rate at which a dot crossing a 116-pixel
## widget looks stepped.
const BEAT := 5                   # frames between heartbeat redraws — 12 Hz at 60


func should_redraw() -> bool:
	if player == null or not visible:
		return false
	var at := player.global_position
	var yaw := player.global_rotation.y
	var scans := GameState.scanned.size()
	if Engine.get_process_frames() % BEAT != 0 \
			and at.distance_to(_was_at) < MOVE_EPSILON \
			and absf(angle_difference(yaw, _was_yaw)) < TURN_EPSILON \
			and scans == _was_scans and GameState.posts_revision == _was_posts:
		return false
	_was_at = at
	_was_yaw = yaw
	_was_scans = scans
	_was_posts = GameState.posts_revision
	return true


## World XZ to widget pixels, with the player at the centre. World -Z draws UP,
## the same orientation as the map screen.
func _to_map(world: Vector3) -> Vector2:
	var at := player.global_position
	return _centre + Vector2(world.x - at.x, world.z - at.z) * _scale


func _draw() -> void:
	if player == null:
		return
	var frame := Rect2(Vector2.ZERO, size)
	draw_rect(frame, BG, true)
	_draw_shapes()
	_draw_zone()
	_draw_posts()
	_draw_mortar()
	_draw_contacts()
	# A range ring at half the window, which is the only distance scale on here:
	# a contact outside it is past twenty-odd metres and not your problem yet.
	# Under the markers, so it never cuts through one.
	draw_arc(_centre, _radius * 0.5, 0.0, TAU, 32, RING, 1.0)
	_draw_self()
	# The border last, over everything, in the player's own colour — on a
	# four-way split every player already finds their quadrant by that colour, so
	# the minimap belonging to them should be said the same way.
	draw_rect(frame, color, false, 2.0)


## Cover and walls. Culled by the cached bounding radius first — a big map is
## several hundred footprints and this is drawn four times over.
func _draw_shapes() -> void:
	var at := player.global_position
	var ax := at.x
	var az := at.z
	# Squared distance, so the cull costs no square roots: this is the loop that
	# runs over every footprint on the map, four viewports deep.
	for i in _sx.size():
		var dx := _sx[i] - ax
		var dz := _sz[i] - az
		var reach := CORNER_M + _sbound[i]
		if dx * dx + dz * dz > reach * reach:
			continue
		var half: Vector2 = _shalf[i] * _scale
		var a := _sangle[i]
		var centre := _centre + Vector2(dx, dz) * _scale
		var ux := Vector2(cos(a), -sin(a)) * half.x
		var uz := Vector2(sin(a), cos(a)) * half.y
		draw_colored_polygon(PackedVector2Array([
			centre - ux - uz, centre + ux - uz, centre + ux + uz, centre - ux + uz,
		]), SHAPE_COLOR)


func _draw_zone() -> void:
	if not GameState.zone_active:
		return
	draw_arc(_to_map(GameState.zone_point), Zone.RADIUS * _scale, 0.0, TAU, 28,
		ZONE_COLOR, 1.5)


## Capture posts, in whoever's colour holds them. The one piece of objective
## information worth carrying at this size, because in Conquest where the posts
## are IS the map.
func _draw_posts() -> void:
	for p in GameState.conquest_posts:
		if not is_instance_valid(p):
			continue
		var at := _to_map(p.global_position)
		var team: int = p.owner_team
		var col: Color = GameState.team_colors[team] if team >= 0 else POST_NEUTRAL
		draw_rect(Rect2(at - Vector2(3.5, 3.5), Vector2(7, 7)), col, true)
		draw_rect(Rect2(at - Vector2(3.5, 3.5), Vector2(7, 7)),
			Color(0, 0, 0, 0.55), false, 1.0)


func _draw_mortar() -> void:
	var m := player.mortar()
	if m == null:
		return
	var at := _to_map(m.global_position)
	draw_line(at - Vector2(4, 0), at + Vector2(4, 0), MORTAR_COLOR, 1.5)
	draw_line(at - Vector2(0, 4), at + Vector2(0, 4), MORTAR_COLOR, 1.5)


## Everyone worth drawing: your side always, the enemy only while your team has
## them SCANNED. A scanned contact is deliberately a different SHAPE as well as a
## different colour — on a 124-pixel widget a five-pixel dot's colour is the
## first thing to go, and "is that one of mine" must survive a glance.
func _draw_contacts() -> void:
	var at := player.global_position
	for c in GameState.combatants:
		if not is_instance_valid(c) or c == player or not c.is_alive():
			continue
		var d := Vector2(c.global_position.x - at.x, c.global_position.z - at.z)
		# A BOX test, not a radius: the window is square, and culling to a circle
		# inside it would drop contacts standing in the corners you can see.
		if absf(d.x) > RADIUS_M or absf(d.y) > RADIUS_M:
			continue
		var mate: bool = c.team == player.team
		if not mate and not GameState.is_scanned_for(c, player.team):
			continue
		var to := _centre + d * _scale
		if mate:
			var col: Color = GameState.team_colors[c.team]
			var human := c is Player
			draw_circle(to, DOT_R if human else DOT_R * 0.78,
				col if human else col.darkened(0.2))
		else:
			# A hollow diamond: hostile, and known only because somebody's dart
			# is still lit. It goes away on its own.
			var r := DOT_R + 1.6
			draw_polyline(PackedVector2Array([
				to + Vector2(0, -r), to + Vector2(r, 0),
				to + Vector2(0, r), to + Vector2(-r, 0), to + Vector2(0, -r),
			]), SCAN_MARK, 1.6)


## You, at the middle, as an arrow pointing where you are looking. It is an arrow
## and not a dot because on a north-up map your HEADING is the whole reason to
## glance down: the dots tell you where they are, this tells you which way to
## turn to be looking at them.
func _draw_self() -> void:
	var yaw := player.global_rotation.y
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-fwd.y, fwd.x)
	draw_colored_polygon(PackedVector2Array([
		_centre + fwd * (SELF_R + 2.0),
		_centre - fwd * 2.0 + side * SELF_R,
		_centre - fwd * 2.0 - side * SELF_R,
	]), color)
