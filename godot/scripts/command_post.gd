class_name CommandPost
extends Node3D
## A Conquest capture post: a fixed point on the map a side can OWN and deploy
## on. Whichever team has the most bodies standing in its radius captures it over
## CAPTURE_TIME — neutral or enemy alike — and once owned it is a spawn point for
## that side (see spawn_transform / GameState.owned_posts). Home posts start owned
## by their side; the rest start neutral and are what the match is fought over.
##
## Modelled on Zone's capture read (a per-team head count of combatants, so bots
## and turrets hold ground too), but stationary and stateful: it remembers who
## owns it and how far the current contest has progressed.

const RADIUS := 6.5
const HEIGHT := 9.0           # tall column, so a crate or slope doesn't drop you out
const CAPTURE_TIME := 5.0     # seconds of uncontested presence to flip it
const NEUTRAL := Color(0.72, 0.74, 0.78)

## Read by GameState.owned_posts — NOT the built-in Node.owner (the scene owner),
## which is unrelated. -1 is neutral.
var owner_team := -1
var post_name := "POST"

var _cap_team := -1           # who is currently making capture progress
var _cap_progress := 0.0      # 0..1 toward _cap_team taking it
var _column: MeshInstance3D
var _ring: MeshInstance3D
var _beam: MeshInstance3D
## The markers' materials, built ONCE. _paint runs every physics frame on every
## post, so it may only ever write a colour into these — building three fresh
## StandardMaterial3Ds a frame (which it used to) is three RenderingServer
## materials per post per frame, and with five posts that measured 1.7 ms of the
## frame on its own. See the note on _paint.
var _column_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _beam_mat: StandardMaterial3D
## Per-team head count for the capture read, reused across frames so the read
## allocates nothing. Teams are dense indices 0..active_teams()-1.
var _counts := PackedInt32Array()


func setup(at: Vector3, initial_owner: int, label: String) -> void:
	global_position = at
	owner_team = initial_owner
	post_name = label


func _ready() -> void:
	GameState.register_conquest_post(self)
	GameState.posts_revision += 1   # the home posts start owned
	_build_marker()
	_paint()


func _physics_process(delta: float) -> void:
	if not GameState.match_live or GameState.match_over:
		return
	var leader := _leader_inside()
	if leader != -1 and leader != owner_team:
		# Someone the post does not belong to is holding it: build toward their
		# capture, restarting the meter if the contender changed.
		if _cap_team != leader:
			_cap_team = leader
			_cap_progress = 0.0
		_cap_progress += delta / CAPTURE_TIME
		if _cap_progress >= 1.0:
			owner_team = leader
			_cap_team = -1
			_cap_progress = 0.0
			GameState.posts_revision += 1
	else:
		# Owner present, empty, or contested: the meter secures back toward safe.
		if _cap_progress > 0.0:
			_cap_progress = maxf(_cap_progress - delta / CAPTURE_TIME, 0.0)
			if _cap_progress == 0.0:
				_cap_team = -1
	_paint()


## The single team with the most living bodies inside; -1 when empty or tied.
##
## Counts into a reused PackedInt32Array rather than building a Dictionary: this
## runs on every post every physics frame, so a fresh dictionary (plus the
## variant boxing of `inside.get(team, 0)`) per post per frame was pure garbage.
## A team is a dense index, so an array indexes as directly as a hash did.
func _leader_inside() -> int:
	var teams := GameState.active_teams()
	if _counts.size() < teams:
		_counts.resize(teams)
	for i in teams:
		_counts[i] = 0
	# One shared scan of the living bodies for the whole frame, however many posts
	# ask for it — see GameState.sample_combatants.
	GameState.sample_combatants()
	var points := GameState.live_points
	var sides := GameState.live_teams
	# Squared radius, so the inner loop never takes a square root.
	var r2 := RADIUS * RADIUS
	var here := global_position
	for i in GameState.live_n:
		var p := points[i]
		var dx := p.x - here.x
		var dz := p.z - here.z
		if dx * dx + dz * dz > r2 or absf(p.y - here.y) > HEIGHT:
			continue
		var t := sides[i]
		if t >= 0 and t < teams:
			_counts[t] += 1
	# Unchanged reading of the tally: the single highest count wins, a tie freezes
	# it. Teams with nobody inside sit at 0 and can only ever tie the empty case,
	# which already returned -1.
	var best := 0
	var leader := -1
	var tied := false
	for t in teams:
		var n := _counts[t]
		if n > best:
			best = n
			leader = t
			tied = false
		elif n == best:
			tied = true
	return -1 if tied else leader


## Where a player deploying here lands: on the post, lifted the usual spawn nudge
## (the collision mesh sits above the analytic ground on the terrain maps), and
## facing the middle of the map so you spawn looking into it.
func spawn_transform() -> Transform3D:
	var origin := global_position + Vector3.UP * GameState.SPAWN_LIFT
	var to_centre := GameState.map_center - global_position
	to_centre.y = 0.0
	var basis := Basis.IDENTITY
	if to_centre.length() > 0.1:
		basis = Transform3D().looking_at(to_centre, Vector3.UP).basis
	return Transform3D(basis, origin)


func _build_marker() -> void:
	_column = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = RADIUS
	cyl.bottom_radius = RADIUS
	cyl.height = 5.0
	cyl.radial_segments = 20
	cyl.rings = 1
	_column.mesh = cyl
	_column.position.y = 2.5
	_column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_column_mat = _marker_material()
	_column.material_override = _column_mat
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
	_ring_mat = _marker_material()
	_ring.material_override = _ring_mat
	add_child(_ring)

	# A tall thin beam of the owner's colour, visible clear across the map, so the
	# front line reads at a glance — the Battlefront command-post pillar.
	_beam = MeshInstance3D.new()
	var beam := CylinderMesh.new()
	beam.top_radius = 0.5
	beam.bottom_radius = 0.9
	beam.height = 26.0
	beam.radial_segments = 8
	_beam.mesh = beam
	_beam.position.y = 13.0
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam_mat = _marker_material()
	_beam.material_override = _beam_mat
	add_child(_beam)


## Owner's colour when held, neutral grey when not; the ring flashes the
## contender's colour, brightening as their capture fills.
##
## Called every physics frame, so it only ever writes a COLOUR into materials
## that already exist, and only when that colour actually moved — a post nobody
## is contesting costs nothing at all, and a post being captured costs one
## albedo write on the one marker that is animating. It used to build three
## whole materials a frame whether anything had changed or not.
func _paint() -> void:
	var base := NEUTRAL if owner_team == -1 else GameState.TEAM_COLORS[owner_team]
	var ring_tint := base
	var ring_alpha := 0.7
	if _cap_team != -1:
		ring_tint = GameState.TEAM_COLORS[_cap_team]
		ring_alpha = lerpf(0.35, 1.0, _cap_progress)
	_tint(_column_mat, Color(base, 0.12))
	_tint(_ring_mat, Color(ring_tint, ring_alpha))
	_tint(_beam_mat, Color(base, 0.10 if owner_team == -1 else 0.22))


func _tint(mat: StandardMaterial3D, c: Color) -> void:
	if mat.albedo_color != c:
		mat.albedo_color = c


## One marker material, built at construction. _paint owns the colour from here.
func _marker_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
