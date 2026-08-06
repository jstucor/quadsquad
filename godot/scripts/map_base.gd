extends "res://scripts/arena.gd"
## THE OUTPOST — a generated INTERIOR base, and the game's close-quarters map.
##
## WHY IT EXISTS. Every generated world so far is 270-300 m of open ground: you
## navigate by landmark, you cross it at a run, and the fights are decided at the
## range your gun is comfortable at. There was nothing at the other end of that
## scale except the hand-laid Catwalk, and one authored corridor map is a map
## everybody learns in an evening. This is 84 m — a bit over a QUARTER of a
## planet's span — enclosed, roofed, and generated fresh from the match seed.
##
## WHAT MAKES IT A CLOSE-COMBAT MAP IS THE SIGHT LINES, NOT THE SIZE. A small map
## with long diagonals is a sniper's map that happens to be small. So the layout
## is a GRID OF ROOMS separated by solid walls, connected by doorways: the longest
## line anywhere is a corridor's length, most engagements start inside twelve
## metres, and there is no vantage point that sees more than one room.
##
## THE RULES IT IS BUILT UNDER, all of them the project's own:
##
##  * STRUCTURES ARE BOXES (see PROCEDURAL WORLDS). The nav grid is stamped from
##    box colliders and cannot see anything else, so every wall here is a box and
##    the AI understands the whole base for free — no bake, no authored volumes.
##  * BUILT UP, NEVER CARVED. A room is four walls with gaps in them, not a hole
##    cut in a solid block. The same reason the caves and bunkers on the planets
##    are built that way: a carved passage is a hole the nav grid cannot see.
##  * A WALL MUST BE THICKER THAN A NAV CELL. `NavGrid` stamps a cell solid when
##    an obstacle reaches its CENTRE, so a wall thinner than the cell spacing
##    falls between two centres and A* routes bots straight through it. At this
##    size the grid runs near `CELL_MIN` (0.9 m), and the walls are 1.0 m.
##  * THE PERIMETER RING IS ALWAYS OPEN, which is a layout decision doing a
##    mechanical job: `GameState.place_corner_spawns` drops three- and four-way
##    matches into the corners of the map, and a corner that happened to be a
##    sealed room would spawn a whole side inside the geometry.

const CELL := 12.0            # room pitch — a room is one cell across
const GRID := 7               # 7 x 7 cells
const WALL := 1.0             # thicker than a nav cell (see the header)
const WALL_H := 6.5           # ceiling height, and the height of every wall
const DOOR := 4.6             # doorway width — two men abreast, not a lane
## The hangars: a 2x2 block of cells at each end with its internal walls left
## out, which is the only open volume in the base and the only place a fight is
## decided at more than a room's length.
const HANGAR := Vector2i(2, 2)
## How many of the walls that are NOT needed for connectivity get a doorway
## anyway. A spanning tree alone is a base with dead ends, and a dead end in a
## close-quarters map is a place you die in rather than a place you fight in —
## loops are what let you break contact and come back round.
const LOOP_CHANCE := 0.34

var _rng := RandomNumberGenerator.new()
## Which cells are floor: every cell is, in this layout. What varies is the WALLS
## between them — see `_open`, keyed "x,z,dir".
var _open := {}
## The two hangar rectangles, in cell coordinates.
var _hangars: Array[Rect2i] = []


func _configure() -> void:
	# THE SEED IS THE MATCH'S. Rolled once per match in `GameState.reset_match`,
	# so the base is the same base for everybody in it and a different one next
	# time — the same contract the planets have.
	_rng.seed = GameState.planet_seed if GameState.planet_seed != 0 else 20260806
	size = CELL * GRID
	depth = size
	# LIGHTER THAN AN OUTDOOR MAP'S, and that is the documented lesson from the
	# night palettes rather than a taste: an interior has no sun and no sky, so
	# every surface is lit by ambient alone — and a dark albedo under ambient
	# light is black. What makes a place read as INDOORS is the absence of a key
	# light and a hard shadow, not dark paint.
	floor_color = Color(0.26, 0.27, 0.31)
	wall_color = Color(0.38, 0.39, 0.44)
	cover_color = Color(0.45, 0.46, 0.50)
	# An interior is lit by its own strips, and they are dimmer than a sun. The
	# grade is shared; how bright this place is meant to be is the map's own
	# business (see `Arena.grade_exposure`).
	grade_exposure = 1.75

	_hangars = [
		Rect2i(Vector2i(0, 0), HANGAR),
		Rect2i(Vector2i(GRID - HANGAR.x, GRID - HANGAR.y), HANGAR),
	]
	_plan()
	_place_spawns()
	_place_cover()


# --- the plan -----------------------------------------------------------------
#
# Cells are nodes; the wall between two adjacent cells is an edge. Every edge
# starts SOLID and is opened by one of three rules, in this order:
#
#   1. inside a hangar          — a hangar is one room, not four
#   2. the perimeter ring       — the outermost lane is always walkable
#   3. connectivity, then loops — a spanning tree over what is left, plus
#                                 LOOP_CHANCE of the rest
#
## Order matters: the first two are structural and the third only has to connect
## what they left, which is why a hangar never ends up sealed off by a random
## edge order.

func _plan() -> void:
	_open.clear()
	for h in _hangars:
		for x in range(h.position.x, h.end.x):
			for z in range(h.position.y, h.end.y):
				if x + 1 < h.end.x:
					_set_open(x, z, Vector2i.RIGHT)
				if z + 1 < h.end.y:
					_set_open(x, z, Vector2i.DOWN)
	# The ring: every edge along the outer lane, both axes.
	for i in GRID - 1:
		_set_open(i, 0, Vector2i.RIGHT)
		_set_open(i, GRID - 1, Vector2i.RIGHT)
		_set_open(0, i, Vector2i.DOWN)
		_set_open(GRID - 1, i, Vector2i.DOWN)

	# ...then join everything else up. Union-find over cells: an edge that joins
	# two separate parts of the base is opened because it must be, and the rest
	# are opened by the dice.
	var parent := {}
	for x in GRID:
		for z in GRID:
			parent[Vector2i(x, z)] = Vector2i(x, z)
	# The structural openings above are already part of the base, so they are
	# unioned first or the tree below would open a second door beside every one.
	var edges: Array = []
	for x in GRID:
		for z in GRID:
			for dir: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var to := Vector2i(x, z) + dir
				if to.x >= GRID or to.y >= GRID:
					continue
				if _is_open(x, z, dir):
					_union(parent, Vector2i(x, z), to)
				else:
					edges.append([Vector2i(x, z), dir])
	edges.shuffle()
	for e: Array in edges:
		var from: Vector2i = e[0]
		var dir: Vector2i = e[1]
		var to: Vector2i = from + dir
		if _find(parent, from) != _find(parent, to):
			_set_open(from.x, from.y, dir)
			_union(parent, from, to)
		elif _rng.randf() < LOOP_CHANCE:
			_set_open(from.x, from.y, dir)


func _key(x: int, z: int, dir: Vector2i) -> String:
	return "%d,%d,%d,%d" % [x, z, dir.x, dir.y]


func _set_open(x: int, z: int, dir: Vector2i) -> void:
	_open[_key(x, z, dir)] = true


func _is_open(x: int, z: int, dir: Vector2i) -> bool:
	return _open.has(_key(x, z, dir))


func _find(parent: Dictionary, at: Vector2i) -> Vector2i:
	while parent[at] != at:
		parent[at] = parent[parent[at]]
		at = parent[at]
	return at


func _union(parent: Dictionary, a: Vector2i, b: Vector2i) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[ra] = rb


# --- building it --------------------------------------------------------------
#
# Every wall is built as SEGMENTS: a solid edge is one box the width of a cell,
# and an edge with a doorway is two boxes with `DOOR` metres of nothing between
# them. That is the whole difference between a room and a corridor here, and it
# is why nothing is ever carved.

func _decorate() -> void:
	var mat := _surface(wall_color, 0.62)
	var half := size * 0.5
	for x in GRID:
		for z in GRID:
			# Each cell builds its own RIGHT and DOWN walls, so no edge is built
			# twice; the outer two sides of the map are the arena's own boundary
			# walls and are left to it.
			for dir: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var to := Vector2i(x, z) + dir
				if to.x >= GRID or to.y >= GRID:
					continue
				_build_edge(x, z, dir, _is_open(x, z, dir), mat, half)
	_build_ceiling()
	_build_lights_inside()


## One edge of the lattice: a full wall, or two stubs with a doorway between.
func _build_edge(x: int, z: int, dir: Vector2i, open: bool, mat: Material,
		half: float) -> void:
	var centre := Vector3(
		(x + 0.5 + dir.x * 0.5) * CELL - half, WALL_H * 0.5,
		(z + 0.5 + dir.y * 0.5) * CELL - half)
	var along := Vector3(float(dir.y), 0.0, float(dir.x))   # perpendicular to dir
	var across := Vector3(float(dir.x), 0.0, float(dir.y))
	if not open:
		_wall(centre, _box_size(along, across, CELL, WALL), mat)
		return
	# Two stubs. The doorway is centred on the edge, so a corridor runs straight
	# through a line of open cells instead of zig-zagging between offset gaps —
	# a base you can actually run down.
	var stub := (CELL - DOOR) * 0.5
	if stub <= 0.05:
		return
	for s: float in [-1.0, 1.0]:
		var at := centre + along * s * (DOOR + stub) * 0.5
		_wall(at, _box_size(along, across, stub, WALL), mat)


## A wall's box, laid out along one axis and thick across the other.
func _box_size(along: Vector3, across: Vector3, length: float, thick: float) -> Vector3:
	return Vector3(
		absf(along.x) * length + absf(across.x) * thick,
		WALL_H,
		absf(along.z) * length + absf(across.z) * thick)


## THE ROOF, and it is what makes this an interior rather than a walled maze.
##
## ONE BOX for the whole base. A ceiling per room would be dozens of draws for a
## surface nobody looks at, and an object is culled as a whole anyway — this one
## spans the map, so it is drawn every frame whatever happens, exactly like the
## prop MultiMeshes (see PERFORMANCE). One is affordable; forty-nine is not.
##
## It COLLIDES, deliberately: a jetpack, a Force jump and a grenade all reach
## 6.5 m, and a base you can hop out of the top of is a base with no roof.
func _build_ceiling() -> void:
	var mat := _surface(wall_color.darkened(0.35), 0.8)
	# ...and it is NOT an obstacle, which it has to say out loud: the nav grid and
	# the map screen both read footprints, and this one covers the entire level.
	_wall(Vector3(0.0, WALL_H + 0.5, 0.0), Vector3(size, 1.0, depth), mat, false)


## THE LIGHT COMES FROM THE CEILING, and almost none of it is a real light.
##
## A dynamic light is the most expensive thing this game can put in a room and
## the frame is already fill-bound; forty-nine lit rooms would be forty-nine
## shadow-casting omnis. So the strips are EMISSIVE geometry — they read as the
## source, they cost a material — and the actual illumination is the ambient
## plus two shadowless fills. That is the same trade the night palettes make:
## what sells a lit space is that the thing which should be bright IS bright,
## not that it is casting a real shadow.
func _build_lights_inside() -> void:
	var strip := StandardMaterial3D.new()
	strip.albedo_color = Color(0.62, 0.72, 0.85)
	strip.metallic = 0.0
	strip.roughness = 0.4
	strip.emission_enabled = true
	strip.emission = Color(0.55, 0.72, 1.0)
	# Kept under unity for the reason on record for the turret's sensor slit and
	# the gun's heat cell: past it, AgX takes emission to white and a white strip
	# is no colour at all.
	strip.emission_energy_multiplier = 0.85
	# ...and each HANGAR END gets its side's colour on the strips. A generated base
	# of identical grey rooms is a maze, and the first thing a maze takes away is
	# knowing which way you are facing — this is the cheapest possible landmark and
	# it is the one piece of information a player in here actually wants.
	var ends: Array[StandardMaterial3D] = []
	for i in _hangars.size():
		var tint: StandardMaterial3D = strip.duplicate()
		var col: Color = GameState.team_color(i)
		tint.albedo_color = col.lightened(0.35)
		tint.emission = col
		ends.append(tint)
	var half := size * 0.5
	for x in GRID:
		for z in GRID:
			var at := Vector3((x + 0.5) * CELL - half, WALL_H - 0.16,
				(z + 0.5) * CELL - half)
			var use := strip
			for i in _hangars.size():
				if _hangars[i].has_point(Vector2i(x, z)):
					use = ends[i]
			var mi := MeshInstance3D.new()
			mi.mesh = Meshes.chamfer_box(Vector3(0.5, 0.12, CELL * 0.55))
			mi.material_override = use
			mi.position = at
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)


## The interior's own light. Overridden wholesale rather than added to: the
## arena's key light is a SUN at 52 degrees, and a sun inside a roofed base lights
## nothing at all — every ray of it stops on the ceiling.
func _build_lights() -> void:
	# Straight down and one off to the side: the first gives the floor, the crates
	# and the tops of walls a value of their own (pure ambient is flat, and a flat
	# room has no depth at all), the second puts a slightly different value on the
	# two wall directions so a corner reads as a corner.
	for spec: Array in [[-88.0, 0.0, 0.95], [-52.0, -130.0, 0.55]]:
		var l := DirectionalLight3D.new()
		l.rotation = Vector3(deg_to_rad(spec[0]), deg_to_rad(spec[1]), 0.0)
		l.light_energy = spec[2]
		# NO SHADOWS from either. A shadow map cast through a ceiling is a black
		# base, and these two exist to lift the walls rather than to describe
		# where anything is.
		l.shadow_enabled = false
		l.light_specular = 0.15
		add_child(l)


func _build_environment() -> void:
	super()
	# An interior has no sky to speak of and no distance to fog: the far wall is
	# eighty metres away at the very most. What the ambient has to do instead is
	# most of the lighting, so it is well up on an outdoor map's.
	for child in get_children():
		if child is WorldEnvironment:
			var env: Environment = (child as WorldEnvironment).environment
			env.ambient_light_color = Color(0.52, 0.57, 0.68)
			env.ambient_light_energy = 1.75
			env.fog_enabled = true
			env.fog_light_color = Color(0.05, 0.06, 0.08)
			env.fog_density = 0.012
			env.fog_sky_affect = 0.0


# --- where people start, and what they fight around ---------------------------

## A HANGAR EACH, which is what the two 2x2 blocks are for: an open volume to
## deploy into, at opposite corners of the base, with the whole layout between
## them. Four markers apiece so a side of twenty is not funnelling through one.
func _place_spawns() -> void:
	var into: Array[Array] = [republic_spawns, cis_spawns]
	for i in _hangars.size():
		var h: Rect2i = _hangars[i]
		var mid := _cell_centre(h.position.x, h.position.y) \
			+ Vector3((h.size.x - 1) * CELL * 0.5, 0.0, (h.size.y - 1) * CELL * 0.5)
		for k in 4:
			var a := TAU * float(k) / 4.0
			(into[i % into.size()] as Array).append(
				mid + Vector3(cos(a) * CELL * 0.45, 0.6, sin(a) * CELL * 0.45))


## COVER IS WHAT MAKES A ROOM A FIGHT. An empty box room is a duel at the door;
## a crate in the middle of it is two people working round the same object.
##
## Deliberately LOW — chest height, not head height. In a room this size a crate
## you cannot see over is a second wall, and the map already has all the walls it
## needs.
func _place_cover() -> void:
	for x in GRID:
		for z in GRID:
			var centre := _cell_centre(x, z)
			var in_hangar := false
			for h in _hangars:
				if h.has_point(Vector2i(x, z)):
					in_hangar = true
			# A hangar gets a couple of big containers to fight around, a room
			# gets one or two crates, and roughly a third of rooms get nothing —
			# an interior where every room is furnished identically reads as a
			# generated one.
			var count := 2 if in_hangar else _rng.randi_range(0, 2)
			for i in count:
				var spread := CELL * (0.34 if in_hangar else 0.24)
				var at := centre + Vector3(
					_rng.randf_range(-spread, spread), 0.0,
					_rng.randf_range(-spread, spread))
				var box := Vector3(
					_rng.randf_range(1.6, 3.0), _rng.randf_range(1.0, 1.5),
					_rng.randf_range(1.6, 3.0)) if in_hangar else Vector3(
					_rng.randf_range(1.0, 1.8), _rng.randf_range(0.9, 1.3),
					_rng.randf_range(1.0, 1.8))
				cover_boxes.append({"pos": at, "size": box})


func _cell_centre(x: int, z: int) -> Vector3:
	var half := size * 0.5
	return Vector3((x + 0.5) * CELL - half, 0.0, (z + 0.5) * CELL - half)
