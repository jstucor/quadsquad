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
## DOORWAY WIDTH, AND IT IS SIZED AGAINST THE NAV GRID RATHER THAN AGAINST A
## BODY. Two men abreast is 4.6 m and that is what this was — but the grid on an
## 84 m map runs at 1.8 m cells, and `NavGrid._stamp` grows every obstacle by
## CLEARANCE plus half a cell, which is 1.4 m on EACH side. A 4.6 m door comes out
## as 1.8 m of open grid: one cell, and none at all once it lands off centre.
##
## The base was then in pieces and it did not look like it — `nav_grid` reported
## anywhere between 6 and 24 of 24 journeys routable depending on the seed, which
## reads as noise. At 7.0 the same padding leaves about 4 m of grid: a doorway the
## AI can plan through, and still a door rather than a missing wall.
const DOOR := 7.0
## The hangars: a 2x2 block of cells at each end with its internal walls left
## out, which is the only open volume in the base and the only place a fight is
## decided at more than a room's length.
const HANGAR := Vector2i(2, 2)
## How many of the walls that are NOT needed for connectivity get a doorway
## anyway. A spanning tree alone is a base with dead ends, and a dead end in a
## close-quarters map is a place you die in rather than a place you fight in —
## loops are what let you break contact and come back round.
## RAISED FROM 0.34, and the second reason is the one that made it necessary. A
## spanning tree gives most rooms exactly ONE doorway — which is a base of dead
## ends to play, and structurally fragile: one crate near that door, or one
## doorway landing badly on the nav grid, and the room is cut off from the base
## entirely. Flooding the walkable cells caught pockets of 10-25% of the floor
## stranded that way. More loops is both the better map and the sturdier one.
const LOOP_CHANCE := 0.55

## HOW MUCH OF THE BASE IS NOT A PLAIN ROOM. Both are COUNTS rather than chances,
## so a base always has some of each — a generator that can roll "none of the
## interesting thing" produces a map somebody plays once and calls broken.
const HALLS := 2               # 2x1 or 2x2 blocks merged into one big room
const SUNKEN_RUN := 3          # cells of lowered tunnel, in an L
## How far the tunnel floor sits below the deck. Deep enough that standing in it
## you cannot see across the floor above (a body is 1.8 m), shallow enough that
## dropping in costs nothing — you climb out at the ramp, but you are never stuck.
const SUNK := 3.4
## The kerb round an opening in the deck. LOW on purpose, and the asymmetry is the
## design: a player vaults it and drops in, and it is a WALL to the nav grid, so
## bots route to the ramp instead of stepping off the edge on their way past.
const KERB := 0.62

var _rng := RandomNumberGenerator.new()
## Which cells are floor: every cell is, in this layout. What varies is the WALLS
## between them — see `_open`, keyed "x,z,dir".
var _open := {}
## The two hangar rectangles, in cell coordinates.
var _hangars: Array[Rect2i] = []
## The big interior rooms — a 2x1 or 2x2 block with its inside walls left out.
var _halls: Array[Rect2i] = []
## Cells whose floor is DOWN a level: the tunnel. Keyed "x,z".
var _sunk := {}
## ...and the cells where a ramp runs from the deck down into it. TWO of them,
## one at each end — see `_ramp_cells`.
var _ramp := Vector2i(-1, -1)
var _ramp_out := Vector2i(-1, -1)


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
	_plan_halls()
	_plan_sunken()
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

## BIG ROOMS, because a base of identical 12 m boxes is one room repeated
## forty-nine times. A hall is a 2x1 or 2x2 block with its internal walls left
## out — the same trick the hangars use — and what goes in it is not the same
## furniture at a larger size: it gets MASSIVE crates, stacked, taller than a
## body (see `_place_cover`). That changes what the room is FOR rather than how
## big it is: cover you cannot shoot over, cannot see past, and can climb.
func _plan_halls() -> void:
	_halls.clear()
	var tries := 0
	while _halls.size() < HALLS and tries < 40:
		tries += 1
		var wide := _rng.randi_range(1, 2)
		var tall := 2 if wide == 1 else _rng.randi_range(1, 2)
		var at := Vector2i(_rng.randi_range(0, GRID - wide), _rng.randi_range(0, GRID - tall))
		var rect := Rect2i(at, Vector2i(wide, tall))
		var clash := false
		# Never overlapping a hangar or another hall: two merged blocks sharing a
		# cell is one enormous room, which is the opposite of what this map is.
		for other in _hangars + _halls:
			if other.intersects(rect):
				clash = true
		if not clash:
			_halls.append(rect)


## THE TUNNEL. A short run of cells whose floor is a level DOWN, reached by one
## ramp, roofed by the deck above it — so it plays as a basement while being, to
## everything that reads this map, the same single walkable surface.
##
## THAT IS NOT A COMPROMISE, IT IS THE CONSTRAINT. `NavGrid` is a 2D occupancy
## grid: it has one height per cell and no idea that two floors can share an XZ.
## A genuine second storey would give every bot in the base a plan of a level it
## is not standing on. So the tunnel is DUG rather than stacked — same plan, same
## walls, one surface — and the only thing the grid has to be told about is the
## EDGE, which is what the kerbs are for.
func _plan_sunken() -> void:
	_sunk.clear()
	# TRIED UNTIL IT LANDS, which is the same discipline `_plan_halls` keeps and
	# for a reason this generator proved on its second run: the start is rolled in
	# the middle third and the run stops at anything already spoken for, so a
	# first cell inside a hall left `_sunk` EMPTY and the base simply had no
	# tunnel — the exact "rolled none of the interesting thing" outcome the
	# constants at the top are counts rather than chances to avoid. A one-cell
	# tunnel is the same failure in a smaller size: it is a pit, not a tunnel.
	var ways: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]
	for attempt in 30:
		_sunk.clear()
		var at := Vector2i(_rng.randi_range(2, GRID - 3), _rng.randi_range(2, GRID - 3))
		var dir: Vector2i = ways[_rng.randi_range(0, ways.size() - 1)]
		for i in SUNKEN_RUN:
			if at.x < 0 or at.y < 0 or at.x >= GRID or at.y >= GRID:
				break
			var blocked := false
			for h in _hangars + _halls:
				if h.has_point(at):
					blocked = true
			if blocked:
				break
			_sunk[_key_cell(at)] = at
			# One turn part way along, so it is an L and not a trench you can see
			# the whole of from either end — the same reason the rooms are not a
			# grid of open squares.
			if i == 1:
				dir = Vector2i(dir.y, dir.x)
			at += dir
		if _sunk.size() >= 2:
			break
	# A RAMP AT EACH END, and the second one is not decoration.
	#
	# With one way in, the tunnel is a cul-de-sac — and worse, its KERBS are walls
	# to the nav grid, so the cells it took stop being a route. Where the run
	# happened to lie across the only corridor joining two halves of the base, the
	# base came apart: `nav_grid` measured 24 of 24 journeys routable on one seed
	# and 6 of 24 on another, which is a map that is fine on Tuesday and
	# unplayable on Wednesday. Two ramps make the tunnel a PASSAGE — it carries
	# the route it replaced, and it is a flanking way round rather than a hole to
	# be cornered in.
	var cells: Array = _sunk.values()
	_ramp = cells[0] if not cells.is_empty() else Vector2i(-1, -1)
	_ramp_out = cells[cells.size() - 1] if cells.size() > 1 else Vector2i(-1, -1)


func _key_cell(at: Vector2i) -> String:
	return "%d,%d" % [at.x, at.y]


func _is_sunk(x: int, z: int) -> bool:
	return _sunk.has("%d,%d" % [x, z])


func _plan() -> void:
	_open.clear()
	# A HALL IS ONE ROOM: its internal walls come out, exactly as a hangar's do.
	for h in _halls:
		for x in range(h.position.x, h.end.x):
			for z in range(h.position.y, h.end.y):
				if x + 1 < h.end.x:
					_set_open(x, z, Vector2i.RIGHT)
				if z + 1 < h.end.y:
					_set_open(x, z, Vector2i.DOWN)
	# ...and the tunnel is a run, so its cells are open to each other and to the
	# cell the ramp climbs to. A sealed tunnel is a hole nobody can use.
	for key in _sunk:
		var at: Vector2i = _sunk[key]
		for dir: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var to := at + dir
			if _is_sunk(to.x, to.y):
				_set_open(at.x, at.y, dir)
	# ...AND THE DECK WALL AT EACH RAMP MOUTH, which is the edge the ramp climbs
	# THROUGH. Opening only the edges BETWEEN tunnel cells left both ramps running
	# straight into a solid wall: the tunnel was a sealed box, and where the run
	# had taken over a corridor it took that route away with it. Measured by
	# flooding the walkable cells — around 90% of the floor joined up with the
	# tunnel cut off, and barely half where it had been a through route.
	for spec: Array in [[_ramp, _ramp_dir_for(_ramp)], [_ramp_out, _ramp_dir_out()]]:
		var cell: Vector2i = spec[0]
		if cell.x < 0:
			continue
		_open_between(cell, cell + (spec[1] as Vector2i))
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


## Open the wall between two neighbouring cells, whichever way round they are
## given. Every edge is stored against its LEFT/UPPER cell as RIGHT or DOWN, so
## an edge opened the other way round is silently a different edge — and the wall
## stays up.
func _open_between(a: Vector2i, b: Vector2i) -> void:
	var step := b - a
	if step == Vector2i.RIGHT or step == Vector2i.DOWN:
		_set_open(a.x, a.y, step)
	elif step == Vector2i.LEFT:
		_set_open(b.x, b.y, Vector2i.RIGHT)
	elif step == Vector2i.UP:
		_set_open(b.x, b.y, Vector2i.DOWN)


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
	_build_sunken(mat)
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


## THE FLOOR IS GENERATED TOO, ONE SLAB PER CELL, and it has to be: `Arena`
## builds a single plane with one solid box under it, and a tunnel dug into that
## is a room under a slab — unreachable, and open to the void at the sides. The
## first version of this looked exactly like that: standing in the tunnel you saw
## the STARFIELD through the walls, because below y=0 there was nothing at all.
##
## Per cell, the floor is at the deck or a level down; the tunnel gets retaining
## walls round the drop, so the base has an inside everywhere you can stand.
##
## These slabs are NOT nav obstacles and need no marking to say so: their tops
## are at or below `MAP_FLOOR_TOP`, which is the rule the scanner already applies
## to a map's floor. The tunnel's own slab is far below that and skipped for the
## same reason.
func _build_floor() -> void:
	var deck := _surface(floor_color, 0.85)
	var sunk_mat := _surface(floor_color.darkened(0.22), 0.8)
	var wall_mat := _surface(wall_color.darkened(0.12), 0.7)
	for x in GRID:
		for z in GRID:
			var centre := _cell_centre(x, z)
			var down := _is_sunk(x, z)
			var top := -SUNK if down else 0.0
			_wall(centre + Vector3(0.0, top - 0.4, 0.0),
				Vector3(CELL, 0.8, CELL), sunk_mat if down else deck)
			if not down:
				continue
			# RETAINING WALLS round the hole, from the tunnel floor up to the deck,
			# on every side that is not more tunnel. Without them the dug cells are
			# open to whatever is under the map, which is nothing.
			for dir: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
				var to := Vector2i(x, z) + dir
				if _is_sunk(to.x, to.y):
					continue
				var along := Vector3(float(dir.y), 0.0, float(dir.x))
				var across := Vector3(float(dir.x), 0.0, float(dir.y))
				var at := centre + across * (CELL * 0.5) \
					+ Vector3(0.0, -SUNK * 0.5, 0.0)
				# THE RAMP SIDE IS STILL WALLED, with a gap the ramp runs through —
				# two stubs, exactly as a doorway upstairs is built. Left fully open
				# it was a window under the neighbouring floor slab and out of the
				# map: standing in the tunnel you could see the STARFIELD past the
				# ramp, which is the second time this map has shown the void and
				# both times it was a hole nobody thought of as a surface.
				var span := CELL
				var gap := 0.0
				if _is_ramp_mouth(Vector2i(x, z), dir):
					gap = CELL * 0.55
					span = (CELL - gap) * 0.5
				for side: float in ([-1.0, 1.0] if gap > 0.0 else [0.0]):
					var offset := along * side * (gap + span) * 0.5
					var box := Vector3(
						absf(along.x) * span + absf(across.x) * WALL, SUNK,
						absf(along.z) * span + absf(across.z) * WALL)
					# NOT a nav obstacle: it is below the deck, and the KERB
					# directly above is what the grid is meant to see. Two stamps
					# on one edge would be the same wall counted twice.
					_wall(at + offset, box, wall_mat, false)


## THE TUNNEL, dug out of the deck: a floor a level down, a kerb round the drop,
## and one ramp in.
##
## The floor is a slab marked `nav := false` — it is FLOOR, and the nav grid
## reads footprints, so an unmarked slab down here would stamp the tunnel solid
## and route every bot round the outside of it (the roof taught this lesson once
## already, see `GameState.MAP_NAV_IGNORE`). The RAMP is marked the same way for
## the same reason: a bot has to be able to path straight up it.
##
## The KERBS are the opposite: they are the only part of this the grid SHOULD see.
## Without them a route that happens to cross the opening walks a bot off a 3.4 m
## drop on its way somewhere else, over and over, because the grid has one height
## per cell and cannot know the floor moved. With them the bots go round to the
## ramp and the players — who can see the hole — vault in.
func _build_sunken(mat: Material) -> void:
	if _sunk.is_empty():
		return
	var kerb_mat := _surface(cover_color.lightened(0.05), 0.55)
	for key in _sunk:
		var at: Vector2i = _sunk[key]
		var centre := _cell_centre(at.x, at.y)
		# The floor and the retaining walls are `_build_floor`'s; what is left here
		# is the EDGE the grid has to see and the way down.
		# A kerb on every side that is NOT another tunnel cell and NOT the ramp:
		# those are the edges you can fall off.
		for dir: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var to := at + dir
			if _is_sunk(to.x, to.y):
				continue
			if _is_ramp_mouth(at, dir):
				continue
			var along := Vector3(float(dir.y), 0.0, float(dir.x))
			var across := Vector3(float(dir.x), 0.0, float(dir.y))
			_wall(centre + across * CELL * 0.5 + Vector3(0.0, KERB * 0.5, 0.0),
				_box_size(along, across, CELL, 0.5) * Vector3(1.0, 0.0, 1.0)
					+ Vector3(0.0, KERB, 0.0), kerb_mat)
	# THE RAMP, cut into the cell the tunnel starts at and climbing back to the
	# deck. A rotated box: the slope is what a body walks up, and `move_and_slide`
	# needs no help with it below the floor angle.
	for spec: Array in [[_ramp, _ramp_dir_for(_ramp)], [_ramp_out, _ramp_dir_out()]]:
		var cell: Vector2i = spec[0]
		if cell.x < 0:
			continue
		var centre := _cell_centre(cell.x, cell.y)
		var dir: Vector2i = spec[1]
		var run := CELL * 0.9
		var slope := atan2(SUNK, run)
		var body := StaticBody3D.new()
		body.set_meta(GameState.MAP_NAV_IGNORE, true)
		body.position = centre + Vector3(float(dir.x), 0.0, float(dir.y)) * CELL * 0.32 \
			+ Vector3(0.0, -SUNK * 0.5, 0.0)
		body.rotation.y = atan2(float(dir.x), float(dir.y))
		add_child(body)
		var mi := MeshInstance3D.new()
		var box := Vector3(CELL * 0.45, 0.6, sqrt(run * run + SUNK * SUNK))
		mi.mesh = Meshes.chamfer_box(box)
		mi.material_override = mat
		mi.rotation.x = -slope
		body.add_child(mi)
		var shape := CollisionShape3D.new()
		var cb := BoxShape3D.new()
		cb.size = box
		shape.shape = cb
		shape.rotation.x = -slope
		body.add_child(shape)


## Which way a ramp climbs out of a given cell: toward a neighbour that is NOT
## part of the tunnel, so it always arrives somewhere you can walk.
func _ramp_dir_for(cell: Vector2i) -> Vector2i:
	for dir: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		var to := cell + dir
		if to.x < 0 or to.y < 0 or to.x >= GRID or to.y >= GRID:
			continue
		if not _is_sunk(to.x, to.y):
			return dir
	return Vector2i.RIGHT


## Is this edge the mouth of a ramp? Both ends of the run have one, and the two
## look for different ways out so a two-cell tunnel does not put both on the same
## wall.
func _is_ramp_mouth(cell: Vector2i, dir: Vector2i) -> bool:
	if cell == _ramp and dir == _ramp_dir_for(_ramp):
		return true
	if _ramp_out.x >= 0 and cell == _ramp_out and dir == _ramp_dir_out():
		return true
	return false


## The far ramp climbs out the OTHER way where it can, so the tunnel runs through
## rather than doubling back on itself.
func _ramp_dir_out() -> Vector2i:
	var back := _ramp_dir_for(_ramp)
	for dir: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		if dir == back:
			continue
		var to := _ramp_out + dir
		if to.x < 0 or to.y < 0 or to.x >= GRID or to.y >= GRID:
			continue
		if not _is_sunk(to.x, to.y):
			return dir
	return _ramp_dir_for(_ramp_out)


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
			# THE TUNNEL IS FURNISHED BY BEING A TUNNEL. A crate in a 3.4 m slot
			# under the floor is a plug, not cover.
			if _is_sunk(x, z):
				continue
			var in_hall := false
			for h in _halls:
				if h.has_point(Vector2i(x, z)):
					in_hall = true
			if in_hall:
				_stack_massive(centre)
				continue
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


## MASSIVE CRATES, and they are a different KIND of cover rather than a bigger
## one. Everywhere else in this base the crates are chest height on purpose — a
## crate you cannot see over is a second wall and the map already has all the
## walls it needs. A big hall is where that rule is deliberately broken: a
## freight stack you cannot see past, cannot shoot over and CAN climb, so the
## room has an inside to fight through and a top to fight from.
##
## Stacked with the smaller box on top and set back, so the silhouette is a
## staircase from one side and a cliff from the other — that asymmetry is what
## makes a stack somewhere to go rather than an obstacle to walk round.
const MASSIVE_BASE := Vector3(4.4, 2.6, 3.4)


## A RANDOM OFFSET INSIDE THE CELL THAT CANNOT PLUG A DOORWAY.
##
## A doorway is `DOOR` metres of gap centred on a cell edge, and a crate is up to
## 4.4 m across: dropped anywhere in the cell, one lands in the gap and shuts the
## room. Two rooms shut that way is a base in pieces, and the failure is by SEED
## — `nav_grid` reported 24 of 24 journeys routable on one roll and **6 of 24** on
## another, which is the same map being fine on Tuesday and unplayable on
## Wednesday. That is worse than a map that never works, because nothing looks
## wrong until somebody is in it.
##
## So the offset is bounded by the crate's OWN half-extent plus a body's width of
## clearance, which keeps every box inside the room and every doorway open.
## Cover keeps its distance from the walls for the same reason the doors are
## wide: the grid grows a crate by 1.4 m as well, so a box that merely LOOKS
## clear of a doorway can still close it.
const COVER_CLEAR := 2.4


func _clear_of_walls(box: Vector3) -> Vector3:
	var room_x: float = maxf(CELL * 0.5 - box.x * 0.5 - COVER_CLEAR, 0.0)
	var room_z: float = maxf(CELL * 0.5 - box.z * 0.5 - COVER_CLEAR, 0.0)
	return Vector3(_rng.randf_range(-room_x, room_x), 0.0,
		_rng.randf_range(-room_z, room_z))


func _stack_massive(centre: Vector3) -> void:
	# ONE OR TWO PER CELL, not three. At three, a 12 m room held 4.4 m stacks with
	# no line through it — measured on the nav grid as routable journeys falling
	# from 24 of 24 to 10, which is the room becoming a wall. Cover you cannot get
	# past is not cover.
	for i in _rng.randi_range(1, 2):
		var base := MASSIVE_BASE * Vector3(
			_rng.randf_range(0.8, 1.15), _rng.randf_range(0.85, 1.2),
			_rng.randf_range(0.8, 1.15))
		var at := centre + _clear_of_walls(base)
		cover_boxes.append({"pos": at, "size": base})
		if _rng.randf() < 0.7:
			# The one on top, set back over an edge so there is a step up onto it.
			var top := base * Vector3(0.62, 0.55, 0.62)
			cover_boxes.append({
				"pos": at + Vector3(base.x * 0.18, base.y, -base.z * 0.14),
				"size": top,
			})


func _cell_centre(x: int, z: int) -> Vector3:
	var half := size * 0.5
	return Vector3((x + 0.5) * CELL - half, 0.0, (z + 0.5) * CELL - half)
