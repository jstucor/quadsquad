extends Node3D
## Builds the AI's navigation grid on every map and checks it is actually
## usable: not so inflated that it seals the tight maps, and not so coarse that
## a planned path crosses a wall.
##
## The wall check is the important one. The grid stamps a cell solid when an
## obstacle reaches its CENTRE, so a wall thinner than the cell spacing can fall
## between two centres, leave a hole, and let A* route a bot straight into it —
## which is exactly the "running into walls" this whole system exists to stop.
## Every planned path is therefore re-tested against PHYSICS: a ray along each
## leg at chest height must not hit world geometry.
##
## Run as a SCENE, not with --script: it needs the GameState autoload and a real
## physics world, and --script mode has neither.
##
##   godot --headless --path godot tests/nav_grid.tscn

const SAMPLES := 24     # random start/goal pairs per map
const CHEST := 1.0
const MIN_JOURNEY := 8.0


func _ready() -> void:
	await get_tree().physics_frame
	var fails: Array[String] = []
	print("map             cells  solid   routed  thru-wall  straight-hits-wall  detour")
	for i in GameState.MAPS.size():
		print(await _check_map(i, fails))
	print("\n==== %s ====" % ("NAV GRID IS SOUND" if fails.is_empty()
		else "%d PROBLEM(S):\n  %s" % [fails.size(), "\n  ".join(fails)]))
	get_tree().quit()


func _check_map(index: int, fails: Array[String]) -> String:
	GameState.reset_match()
	var level: Node = GameState.MAPS[index]["scene"].instantiate()
	add_child(level)
	# Two physics frames: colliders are not in the physics world during _ready,
	# and the raycasts below are the whole point of this test.
	await get_tree().physics_frame
	await get_tree().physics_frame
	GameState.scan_map_geometry(level)
	var nav: NavGrid = GameState.nav
	nav.build(GameState.map_center, GameState.map_extents, GameState.map_shapes)

	var solid := 0
	var total := 0
	for x in nav._cols:
		for y in nav._rows:
			total += 1
			if nav._grid.is_point_solid(Vector2i(x, y)):
				solid += 1

	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var routed := 0
	var through := 0
	var naive_blocked := 0   # journeys where walking STRAIGHT at the goal hits a wall
	var detour_sum := 0.0
	var space := get_world_3d().direct_space_state
	for s in SAMPLES:
		var a := _open_spot(nav, rng)
		var b := _open_spot(nav, rng)
		if a == Vector3.INF or b == Vector3.INF or a.distance_to(b) < MIN_JOURNEY:
			continue
		var route: PackedVector2Array = nav.path(a, b)
		if route.size() < 2:
			continue
		routed += 1
		# What the AI used to do: point at the goal and walk. Counting these is
		# the measure of what the planner is for — every one is a journey that
		# would have ended against a wall.
		var sa := _chest(level, Vector2(a.x, a.z))
		var sb := _chest(level, Vector2(b.x, b.z))
		var sq := PhysicsRayQueryParameters3D.create(sa, sb)
		sq.collision_mask = 1
		var straight_hit := space.intersect_ray(sq)
		if not straight_hit.is_empty() and _is_box(straight_hit.get("collider")):
			naive_blocked += 1
		var walked := 0.0
		var hit := false
		for i in range(1, route.size()):
			# Chest height above the GROUND, not above y=0. On the terrain maps a
			# flat ray at a fixed height drives straight into the hillside and
			# reports every route as blocked — the hill is walkable, and the grid
			# is deliberately flat (see NavGrid's header).
			var p0 := _chest(level, route[i - 1])
			var p1 := _chest(level, route[i])
			walked += route[i - 1].distance_to(route[i])
			var q := PhysicsRayQueryParameters3D.create(p0, p1)
			q.collision_mask = 1
			var got := space.intersect_ray(q)
			# Only a BOX collider counts as a planner failure. The grid is built
			# from box footprints and is deliberately flat, so a trimesh hit is
			# the hillside the bot is supposed to walk up — and, on the terrain
			# maps, is usually just the collision mesh sitting above the analytic
			# height this test sampled (see the height_at note in CLAUDE.md).
			if not got.is_empty() and _is_box(got.get("collider")):
				hit = true
		if hit:
			through += 1
		detour_sum += walked / maxf(a.distance_to(b), 0.001)

	var map_name: String = GameState.MAPS[index]["name"]
	var blocked := 100.0 * float(solid) / float(maxi(total, 1))
	if routed < SAMPLES / 3:
		fails.append("%s: only %d of %d journeys found a route — the grid seals the map"
			% [map_name, routed, SAMPLES])
	if through > 0:
		fails.append("%s: %d of %d routes pass through real geometry"
			% [map_name, through, routed])
	if blocked > 70.0:
		fails.append("%s: %.0f%% of the map is marked solid" % [map_name, blocked])
	# ...AND A MAP WITH NOTHING SOLID IN IT AT ALL DID NOT BUILD. Every map in the
	# roster has walls or cover; zero means the level script errored out (a parse
	# error leaves an empty Node3D) or its layout table is empty — and to every
	# other measure here that map looks PERFECT: nothing to route around, every
	# journey found, a detour of 1.00. This test read exactly that for a whole run
	# while the Outpost's script was failing to parse.
	if blocked < 1.0:
		fails.append("%s: nothing is solid — the level built no geometry at all"
			% map_name)
	level.queue_free()
	return "%-14s %6d  %4.0f%%  %4d/%-3d %7d %8d      x%.2f" % [
		map_name, total, blocked, routed, SAMPLES, through, naive_blocked,
		detour_sum / float(maxi(routed, 1))]


## Did we hit something the navigation grid should have known about? The grid is
## stamped from box colliders, so only a box is its responsibility.
func _is_box(body: Object) -> bool:
	if body == null or not (body is Node):
		return false
	for node in (body as Node).find_children("*", "CollisionShape3D", true, false):
		if node.shape is BoxShape3D:
			return true
	return false


## A waypoint lifted to chest height over whatever the ground is doing there.
func _chest(level: Node, at: Vector2) -> Vector3:
	var y := 0.0
	if level.has_method("height_at"):
		y = level.height_at(at.x, at.y)
	return Vector3(at.x, y + CHEST, at.y)


## A random point on open ground, or INF if every roll landed inside geometry.
func _open_spot(nav: NavGrid, rng: RandomNumberGenerator) -> Vector3:
	for attempt in 40:
		var c := Vector2i(rng.randi_range(0, nav._cols - 1),
			rng.randi_range(0, nav._rows - 1))
		if nav._grid.is_point_solid(c):
			continue
		var p: Vector2 = nav._grid.get_point_position(c)
		return Vector3(p.x, 0.0, p.y)
	return Vector3.INF
