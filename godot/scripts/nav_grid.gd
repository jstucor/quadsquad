class_name NavGrid
extends RefCounted
## Where the AI may walk, and how to get from one place to another without
## walking through a wall.
##
## It is an occupancy grid plus A*, built from `GameState.map_shapes` — the
## top-down footprints of every world-layer box collider, which the map screen
## already scans at match start. Reusing that scan is the whole reason this is
## cheap: no navmesh to bake, no per-map authoring, and a new procedural map
## becomes navigable for free, exactly as it becomes drawable for free.
##
## A* itself is Godot's `AStarGrid2D` rather than a hand-rolled one: it is
## implemented in C++, it already does octile heuristics, and its
## ONLY_IF_NO_OBSTACLES diagonal mode is what stops a path cutting the corner of
## a crate diagonally through the solid part.
##
## What this deliberately is NOT: a 3D solution. The grid is flat, so it routes
## around obstacles but knows nothing about height — it cannot plan a jump onto
## a ledge or off one, and on the terrain maps it treats a hillside as walkable
## because a hillside IS walkable. Slopes are the level's problem; walls are
## this one's.

## Cell size is chosen per map between these two. A small arena gets fine cells
## because its corridors are narrow; a 300 m map coarsens so the grid stays a
## few tens of thousands of cells rather than a million.
##
## Resolution is not a cosmetic choice here. A cell is stamped solid when the
## obstacle reaches its CENTRE, so a wall thinner than the cell spacing can fall
## between two centres and leave a hole A* will happily route through — and the
## bot then walks into the wall, which is the whole problem this exists to fix.
## CELL_MIN is therefore the thinnest wall the game builds, and _stamp adds half
## a cell to close the gap for anything thinner still.
const CELL_MIN := 0.9
const CELL_MAX := 2.0
## Obstacles are grown by this before being stamped in, so a path that hugs a
## wall still leaves room for a body (capsule radius 0.35) to walk it. Without
## the inflation, A* happily returns a route straight along a wall face and the
## bot grinds down it. Kept close to the body: every extra centimetre here
## narrows the real corridors, and on the tight maps that seals them.
const CLEARANCE := 0.5
## Cap per axis, so an enormous map coarsens instead of allocating unboundedly.
const MAX_SIDE := 220
## How far out to look for a walkable cell when a start or goal lands inside
## geometry — which happens constantly, because a bot standing against a crate
## is inside the crate's inflated footprint.
const OPEN_SEARCH := 6

## HOW MANY A* SEARCHES MAY RUN IN ONE PHYSICS FRAME, across every bot on the
## map.
##
## What one search costs, timed directly (tests/perf.tscn): 2.0 ms on Kashyyyk,
## 1.7 ms on Geonosis, 0.10 ms on a small arena. What a loaded match asks for:
## about 16 searches a second across the whole AI. On AVERAGE that is half a
## millisecond a frame and perfectly affordable — the problem was never the
## average.
##
## The problem is that bots re-plan on their own timers, so nothing stopped
## several landing on the SAME frame: at eight bots the worst frame was eight
## searches, ~16 ms of A* on a 16.7 ms budget, for a stutter with no cause
## visible anywhere in the game. It is not hypothetical — with the budget at 2,
## a 1.4 s sample deferred 12 requests, meaning a dozen frames genuinely had
## three or more bots wanting a route at once.
##
## Bots that are refused simply keep following the path they already have (or
## walk straight at the goal, which is the no-path fallback) and ask again next
## frame. That is invisible: a plan is a few seconds of walking, and one frame
## late is nothing.
const PLANS_PER_FRAME := 2

var ready := false

## Running totals, for the perf harness. A* is the AI's expensive answer, so how
## OFTEN it is asked for is the number worth watching — frame-time averages on a
## capped loop are far too noisy to see a routing change in.
var plans_run := 0
var plans_refused := 0

var _plan_frame := -1
var _plans_this_frame := 0

var _grid: AStarGrid2D
var _origin := Vector2.ZERO   # world XZ of the grid's lower corner
var _cell := CELL_MAX
var _cols := 0
var _rows := 0


## Stamp the level into a grid. Call once per match, after the map's geometry
## has been scanned.
func build(center: Vector3, extents: Vector2, shapes: Array) -> void:
	ready = false
	var size := extents * 2.0
	if size.x <= 0.0 or size.y <= 0.0:
		return
	# Coarsen rather than explode on a huge map: Geonosis is 300 m across.
	_cell = clampf(maxf(size.x, size.y) / float(MAX_SIDE), CELL_MIN, CELL_MAX)
	_cols = maxi(1, ceili(size.x / _cell))
	_rows = maxi(1, ceili(size.y / _cell))
	_origin = Vector2(center.x, center.z) - extents

	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(0, 0, _cols, _rows)
	_grid.cell_size = Vector2(_cell, _cell)
	# `offset` is the world position of cell (0,0), and a cell's position is its
	# CENTRE — so the grid origin is half a cell in from the corner.
	_grid.offset = _origin + Vector2(_cell, _cell) * 0.5
	# Without this a diagonal step may pass between two solid cells that touch at
	# a corner, which is how a path ends up going through the join of two crates.
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.update()

	for s in shapes:
		_stamp(s)
	ready = true


## Mark every cell covered by one footprint, grown by CLEARANCE.
##
## The footprint may be rotated (the hand-authored hangar has angled geometry),
## so cells are tested against the ROTATED rectangle — an axis-aligned bound of
## a 45-degree box is 1.4x too big and would seal gaps that are really there.
## The local axes are the same ones map_view draws these footprints with.
func _stamp(shape: Dictionary) -> void:
	var at: Vector2 = shape["pos"]
	var half: Vector2 = shape["size"] * 0.5
	var a: float = shape["angle"]
	var ex := Vector2(cos(a), -sin(a))   # the box's local X axis, in world XZ
	var ez := Vector2(sin(a), cos(a))    # ...and its local Z axis
	# CLEARANCE keeps a body off the wall; the half-cell closes the gap that
	# centre-sampling leaves, so a wall thinner than one cell still stamps a
	# continuous line of solid cells instead of a dotted one.
	var pad := CLEARANCE + _cell * 0.5
	var grown := half + Vector2(pad, pad)

	# Sweep the cells inside the rotated rect's own bounding box, then test each
	# one properly. `reach` is rotation-proof.
	var reach := grown.length()
	var lo := _cell_of_xz(at - Vector2(reach, reach))
	var hi := _cell_of_xz(at + Vector2(reach, reach))
	for cx in range(maxi(lo.x, 0), mini(hi.x + 1, _cols)):
		for cy in range(maxi(lo.y, 0), mini(hi.y + 1, _rows)):
			var p := _origin + Vector2(cx + 0.5, cy + 0.5) * _cell
			var d := p - at
			if absf(d.dot(ex)) <= grown.x and absf(d.dot(ez)) <= grown.y:
				_grid.set_point_solid(Vector2i(cx, cy), true)


## May a search run this physics frame? Ask BEFORE calling `path`, and if the
## answer is no, keep whatever route you already had and ask again next frame.
## See PLANS_PER_FRAME for why the budget exists.
func may_plan() -> bool:
	var frame := Engine.get_physics_frames()
	if frame != _plan_frame:
		_plan_frame = frame
		_plans_this_frame = 0
	if _plans_this_frame >= PLANS_PER_FRAME:
		plans_refused += 1
		return false
	_plans_this_frame += 1
	plans_run += 1
	return true


## A route from one world point to another, as world XZ waypoints. Empty when
## there is no grid or no way through, which callers treat as "walk straight at
## it" — a bot with no path must still move.
func path(from: Vector3, to: Vector3) -> PackedVector2Array:
	if not ready:
		return PackedVector2Array()
	var a := _nearest_open(_cell_of(from))
	var b := _nearest_open(_cell_of(to))
	if a.x < 0 or b.x < 0:
		return PackedVector2Array()
	return _grid.get_point_path(a, b)


## Is there solid geometry at this world point? Used by the string-pulling in
## Bot to decide whether it can cut a corner off its own path.
func blocked_at(p: Vector3) -> bool:
	if not ready:
		return false
	var c := _cell_of(p)
	if not _inside(c):
		return false   # off the grid is not a wall; it is off the map
	return _grid.is_point_solid(c)


## Is the straight line between two world points clear of stamped geometry?
## Sampled along the segment at half-cell steps, which is the finest answer the
## grid can give. Cheaper than a physics ray and, more usefully, it agrees with
## the grid the path was planned on — a smoother that disagreed with the planner
## would cut corners the planner had deliberately routed around.
func line_clear(from: Vector3, to: Vector3) -> bool:
	if not ready:
		return true
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var span := a.distance_to(b)
	var steps := ceili(span / (_cell * 0.5))
	for i in range(1, steps + 1):
		var p := a.lerp(b, float(i) / float(steps))
		var c := _cell_of_xz(p)
		if _inside(c) and _grid.is_point_solid(c):
			return false
	return true


func cell_size() -> float:
	return _cell


func _cell_of(p: Vector3) -> Vector2i:
	return _cell_of_xz(Vector2(p.x, p.z))


func _cell_of_xz(p: Vector2) -> Vector2i:
	var rel := (p - _origin) / _cell
	return Vector2i(floori(rel.x), floori(rel.y))


func _inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _cols and c.y < _rows


## The nearest walkable cell to `c`, searched outward in rings. A bot pressed
## against a crate is INSIDE that crate's inflated footprint, so its own cell is
## solid far more often than not — without this, pathing would simply fail
## whenever it mattered most.
func _nearest_open(c: Vector2i) -> Vector2i:
	var start := Vector2i(clampi(c.x, 0, _cols - 1), clampi(c.y, 0, _rows - 1))
	if not _grid.is_point_solid(start):
		return start
	for r in range(1, OPEN_SEARCH + 1):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				# Ring only: the inside was covered by a smaller r.
				if absi(dx) != r and absi(dy) != r:
					continue
				var t := Vector2i(start.x + dx, start.y + dy)
				if _inside(t) and not _grid.is_point_solid(t):
					return t
	return Vector2i(-1, -1)
