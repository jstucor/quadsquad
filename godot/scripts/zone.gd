extends Node3D
## The capture area for the ZONES mode: a marked circle somewhere on the map.
## Every second, whichever team has more bodies standing in it takes a point,
## and every RELOCATE_EVERY seconds it picks a new spot. First team to
## GameState.score_limit() seconds of control wins.
##
## "Bodies" means combatants, so bought squads, team AI and placed turrets all
## count toward holding it — a lone player with three squadmates really can take
## an area off two opponents.
##
## Placement works on every map, including the hand-authored hangar: candidate
## points come from the arena's own extents when it has them and from the spread
## of the spawn markers when it doesn't, and the ground height is found by
## raycasting down, so it sits on terrain and hangar decking alike.

const RADIUS := 7.5
const RELOCATE_EVERY := 30.0
const TICK := 1.0
const HEIGHT := 9.0        # a tall column, so a hill or a crate doesn't drop you out
const MIN_MOVE := 18.0     # a new area has to be a real walk from the old one
const EDGE_INSET := 10.0   # keep the area off the boundary walls

var _level: Node3D
var _tick_left := TICK
var _move_left := RELOCATE_EVERY
var _placed := false
var _holder := -1
var _contested := false
var _ring: MeshInstance3D
var _column: MeshInstance3D


func setup(level: Node3D) -> void:
	_level = level


func _ready() -> void:
	_build_marker()


## Everything runs on the physics tick because placement depends on a raycast:
## during _ready the level's colliders are not in the physics world yet, so the
## ground ray finds nothing and every area lands on the fallback spot.
func _physics_process(delta: float) -> void:
	if not _placed:
		_placed = true
		_relocate()
	if not GameState.match_live or GameState.match_over:
		return
	_move_left -= delta
	if _move_left <= 0.0:
		_relocate()
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left += TICK
		_score_tick()


## Count who's inside and award the second. A tie (including nobody there) pays
## nobody, so an area only earns while a team actually holds it.
func _score_tick() -> void:
	var inside := {GameState.Team.REPUBLIC: 0, GameState.Team.CIS: 0}
	for c in GameState.combatants:
		if not is_instance_valid(c) or not c.is_alive():
			continue
		if _contains(c.global_position):
			inside[c.team] += 1
	var republic: int = inside[GameState.Team.REPUBLIC]
	var cis: int = inside[GameState.Team.CIS]
	_contested = republic > 0 and cis > 0
	if republic > cis:
		_holder = GameState.Team.REPUBLIC
		GameState.add_zone_tick(GameState.Team.REPUBLIC)
	elif cis > republic:
		_holder = GameState.Team.CIS
		GameState.add_zone_tick(GameState.Team.CIS)
	else:
		_holder = -1
	_paint()
	GameState.zone_state.emit(_holder, _contested, ceili(_move_left))


func _contains(point: Vector3) -> bool:
	var flat := Vector2(point.x - global_position.x, point.z - global_position.z)
	return flat.length() <= RADIUS \
		and absf(point.y - global_position.y) <= HEIGHT


func _relocate() -> void:
	_move_left = RELOCATE_EVERY
	var spot := _pick_spot()
	global_position = spot
	_holder = -1
	_contested = false
	_paint()
	GameState.zone_point = spot
	GameState.zone_active = true
	GameState.zone_moved.emit(spot)


## A random point that is actually standable, a fair walk from where the area
## just was. Falls back to the map centre if the map is too small to satisfy it.
func _pick_spot() -> Vector3:
	var bounds := _bounds()
	for attempt in 40:
		var x := randf_range(-bounds.x, bounds.x)
		var z := randf_range(-bounds.y, bounds.y)
		var ground: Variant = _ground_at(x, z)
		if ground == null:
			continue
		var candidate: Vector3 = ground
		if GameState.zone_active and Vector2(candidate.x - global_position.x,
				candidate.z - global_position.z).length() < MIN_MOVE:
			continue
		return candidate
	var centre: Variant = _ground_at(0.0, 0.0)
	return centre if centre != null else Vector3.ZERO


## Straight down from high up: whatever floor, deck or hillside is there.
## Vector3 where there's ground, null where the ray finds nothing.
func _ground_at(x: float, z: float) -> Variant:
	var from := Vector3(x, 80.0, z)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 140.0)
	query.collision_mask = 1  # world geometry
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit["position"] as Vector3


## Half-extents to sample within: the arena's own size when it has one, or the
## spread of the spawn markers for hand-authored maps like the hangar.
func _bounds() -> Vector2:
	if _level != null and "size" in _level and "depth" in _level:
		var half := Vector2(_level.size, _level.depth) * 0.5
		return (half - Vector2.ONE * EDGE_INSET).maxf(6.0)
	var spread := Vector2(12.0, 12.0)
	for team in [GameState.Team.REPUBLIC, GameState.Team.CIS]:
		var index := 0
		while true:
			var marker := GameState.get_spawn_point(team, index)
			if marker == null or index > 8:
				break
			spread.x = maxf(spread.x, absf(marker.global_position.x))
			spread.y = maxf(spread.y, absf(marker.global_position.z))
			index += 1
	return (spread - Vector2.ONE * 4.0).maxf(6.0)


func _build_marker() -> void:
	# A translucent column you can see across the map, plus a ring on the deck
	# so you can tell exactly where the edge is when you're standing in it.
	_column = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = RADIUS
	cyl.bottom_radius = RADIUS
	cyl.height = 6.0
	cyl.radial_segments = 20
	cyl.rings = 1
	_column.mesh = cyl
	_column.position.y = 3.0
	_column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_column)

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS - 0.35
	torus.outer_radius = RADIUS
	torus.rings = 28
	torus.ring_segments = 5
	_ring.mesh = torus
	_ring.position.y = 0.12
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_paint()


## Neutral while nobody holds it, the holder's colour while they do, and white
## while both teams are standing in it.
func _paint() -> void:
	var tint := Color(0.85, 0.85, 0.9)
	if _contested:
		tint = Color(1.0, 0.95, 0.6)
	elif _holder != -1:
		tint = GameState.TEAM_COLORS[_holder]
	_column.material_override = _marker_material(Color(tint, 0.13))
	_ring.material_override = _marker_material(Color(tint, 0.75))


func _marker_material(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = tint
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # visible from inside the column
	return mat
