extends "res://scripts/arena.gd"
## "ARIDIS" — a 300 x 300 m red rock basin, by a wide margin the biggest map
## in the rotation: about thirty-five times the floor area of Crossfire.
##
## Being this big changes what the map IS. You cannot hold all of it, and you
## will not stumble into a fight by walking forward — the whole thing is built
## around LANDMARKS you navigate between: five climbable mesas ringing an open
## middle, and the Vespid arena wall at the centre of it. Every one of them
## is tall enough to see from anywhere in the basin, so the map reads as a place
## with directions in it rather than a field.
##
## Terrain is a heightfield like Highridge's, but at a much coarser CELL: at
## Highridge's 1.8 m this map would be 28,000 quads, and it renders four times
## over plus a shadow pass. Dunes are smooth, so 5 m cells cost nothing to look
## at and bring it down to a tenth of that.
##
## Mesa slopes use the same arithmetic Highridge does — a smoothstep falloff's
## gradient peaks at 1.5 * height / (radius - plateau), so those three numbers
## decide whether a mesa can be climbed. Measured across every face of all five:
## the steepest is 36.9 degrees, inside the 45 a CharacterBody3D will walk up, so
## all of them are climbable on foot.

const GROUND_SHADER := preload("res://shaders/terrain_ground.gdshader")

const SEED := 20260723
const CELL := 5.0             # heightfield resolution; see the note above
const DUNE_HEIGHT := 1.6      # rolling ground everywhere, too low to trip on
const GROUND_TILE_M := 3.0

# The mesas: centre, foot radius, flat-top radius, height. Kept to a shallow
# gradient so all of them can be walked up rather than admired from below.
const MESAS: Array[Dictionary] = [
	{"at": Vector2(-92.0, -78.0), "r": 46.0, "top": 15.0, "h": 15.0},
	{"at": Vector2(96.0, -70.0), "r": 40.0, "top": 12.0, "h": 12.5},
	{"at": Vector2(-104.0, 84.0), "r": 44.0, "top": 14.0, "h": 13.5},
	{"at": Vector2(88.0, 92.0), "r": 38.0, "top": 11.0, "h": 11.0},
	{"at": Vector2(6.0, -118.0), "r": 34.0, "top": 10.0, "h": 9.0},
]
# The arena ring at the centre: the one piece of built structure, and the
# obvious place to fight over.
const ARENA_RADIUS := 30.0
const ARENA_WALL_H := 7.0
const ARENA_SEGMENTS := 16    # gaps between them are the ways in

const SPIRE_COUNT := 34
const BOULDER_COUNT := 120
const PROP_CLEAR := 12.0      # keep spires and boulders off the spawns


func _configure() -> void:
	size = 300.0
	floor_color = Color(0.52, 0.29, 0.18)   # red Vespid dust
	wall_color = Color(0.38, 0.22, 0.15)    # the canyon wall ringing the basin
	cover_color = Color(0.46, 0.30, 0.21)   # weathered rock and ruin
	# Spawns sit between the mesas and the arena, not out at the corners: on a
	# map this size a corner spawn is a minute's walk from anything.
	republic_spawns = [Vector3(-58, 0, -46), Vector3(-70, 0, -30), Vector3(-46, 0, -58)]
	cis_spawns = [Vector3(58, 0, 46), Vector3(70, 0, 30), Vector3(46, 0, 58)]
	cover_boxes = _cover_layout()


## Cover is placed in CLUSTERS rather than spread evenly. Scattered cover over
## 90,000 square metres is just noise; clumps give the basin somewhere to fight
## and somewhere to cross, which is what makes the space readable.
func _cover_layout() -> Array:
	var out: Array = []
	# Ruined pylons around the arena, the fight everyone is drawn to.
	for i in 8:
		var a := TAU * float(i) / 8.0 + 0.4
		out.append({"pos": Vector3(cos(a) * 42.0, 0, sin(a) * 42.0),
			"size": Vector3(4.0, 5.0, 4.0)})
	# Staging clumps: four of them, ringing the middle at mid-distance.
	for c in [Vector2(-52.0, 34.0), Vector2(52.0, -34.0),
			Vector2(30.0, 62.0), Vector2(-30.0, -62.0)]:
		out.append({"pos": Vector3(c.x, 0, c.y), "size": Vector3(9.0, 3.4, 9.0)})
		out.append({"pos": Vector3(c.x + 11.0, 0, c.y + 4.0), "size": Vector3(3.0, 1.6, 7.0)})
		out.append({"pos": Vector3(c.x - 4.0, 0, c.y - 11.0), "size": Vector3(7.0, 1.6, 3.0)})
	# Hard cover on each spawn's approach, so nobody is shot walking out.
	for p in [Vector3(-58, 0, -46), Vector3(58, 0, 46)]:
		out.append({"pos": p + Vector3(10, 0, 10) * signf(p.x),
			"size": Vector3(8.0, 2.4, 2.4)})
		out.append({"pos": p + Vector3(-8, 0, 12) * signf(p.x),
			"size": Vector3(2.4, 2.4, 8.0)})
	return out


## Rolling dunes everywhere, plus whichever mesas reach this point. Single
## source of truth for the mesh, its collider and every prop that sits on it.
func height_at(x: float, z: float) -> float:
	var h := DUNE_HEIGHT * (
		sin(x * 0.031) * cos(z * 0.027) * 0.6
		+ sin((x + z) * 0.017) * 0.4)
	for m in MESAS:
		h += _mesa(Vector2(x, z), m)
	return maxf(h, 0.0)


## One mesa: flat on top, smoothstep down to nothing at its foot.
func _mesa(p: Vector2, m: Dictionary) -> float:
	var at: Vector2 = m["at"]
	var gap := p.distance_to(at)
	var foot: float = m["r"]
	var top: float = m["top"]
	if gap >= foot:
		return 0.0
	if gap <= top:
		return m["h"]
	return m["h"] * smoothstep(1.0, 0.0, (gap - top) / (foot - top))


func _build_floor() -> void:
	_build_base_plane()
	_build_terrain()


## The flat base under everything. The heightfield is only a skin, so this is
## what stops anything falling through where the skin is flat.
func _build_base_plane() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, depth)
	mesh.mesh = plane
	mesh.material_override = _floor_material()
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 1.0, depth)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)


## The dune-and-mesa skin: one mesh, one trimesh collider.
func _build_terrain() -> void:
	var half := half_extents()
	var cols := int(size / CELL)
	var rows := int(depth / CELL)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in cols:
		for j in rows:
			var x0 := -half.x + i * CELL
			var z0 := -half.y + j * CELL
			var x1 := x0 + CELL
			var z1 := z0 + CELL
			var corners := [
				Vector3(x0, height_at(x0, z0), z0),
				Vector3(x1, height_at(x1, z0), z0),
				Vector3(x1, height_at(x1, z1), z1),
				Vector3(x0, height_at(x0, z1), z1),
			]
			# Emit from the first RAISED corner, never from a height cutoff: a
			# cutoff leaves the skin's leading edge hanging above the base plane
			# and players walk under the terrain instead of up it.
			var tallest := 0.0
			for c: Vector3 in corners:
				tallest = maxf(tallest, c.y)
			if tallest <= 0.0:
				continue
			_quad(st, corners[0], corners[1], corners[2], corners[3])
	st.generate_normals()
	var mesh := st.commit()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _terrain_material()
	add_child(mi)

	var body := StaticBody3D.new()
	add_child(body)
	var shape := CollisionShape3D.new()
	var tri := mesh.create_trimesh_shape()
	# A ConcavePolygonShape3D only collides on ONE side by default, and it is not
	# the side the normals face — without this everything walks straight through
	# the terrain with no error anywhere.
	tri.backface_collision = true
	shape.shape = tri
	body.add_child(shape)


## One terrain cell. Three things here are load-bearing and all three were wrong
## first time round, with no error to show for it:
##   - the winding is counter-clockwise seen from ABOVE, or the normals face
##     down and the whole basin renders unlit;
##   - steepness goes in the vertex colour's red channel, which is how the
##     shader knows to paint slopes as rock — left at white, every face is rock
##     and the mesas stop reading as landforms;
##   - UVs must be set in tile units. A mesh with no UVs samples one noise cell
##     for all 300 m and comes out as a single flat wash of colour.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v: Vector3 in [a, d, c, a, c, b]:
		st.set_color(Color(steepness_at(v.x, v.z), 0.0, 0.0))
		st.set_uv(Vector2(v.x, v.z) / GROUND_TILE_M)
		st.add_vertex(v)


## Analytic gradient, sampled either side of the point. The map generates the
## heightfield so it knows this exactly, which is cheaper and cleaner than
## recovering it from the mesh normals afterwards.
func steepness_at(x: float, z: float) -> float:
	const E := 2.0   # scaled to CELL: a 0.9 m step reads as flat on 5 m cells
	var dx := (height_at(x + E, z) - height_at(x - E, z)) / (2.0 * E)
	var dz := (height_at(x, z + E) - height_at(x, z - E)) / (2.0 * E)
	return clampf(Vector2(dx, dz).length() / 0.45, 0.0, 1.0)


## Canyon walls rather than the base arena's 6 m fence: at this scale a low wall
## reads as a kerb, and the basin needs to feel enclosed by something.
func _build_walls() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = wall_color
	mat.metallic = 0.0
	mat.roughness = 0.9
	var h := 26.0
	var half := half_extents()
	_wall(Vector3(0, h * 0.5, -half.y), Vector3(size, h, 2.0), mat)
	_wall(Vector3(0, h * 0.5, half.y), Vector3(size, h, 2.0), mat)
	_wall(Vector3(-half.x, h * 0.5, 0), Vector3(2.0, h, depth), mat)
	_wall(Vector3(half.x, h * 0.5, 0), Vector3(2.0, h, depth), mat)


## Harsh desert daylight: a high white sun, an orange sky, and enough dust that
## the far wall of the basin is a haze rather than a hard edge. The haze is also
## what stops a 300 m sight line being a free shot from one side to the other.
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.44, 0.38, 0.46)
	sky_mat.sky_horizon_color = Color(0.86, 0.60, 0.38)
	sky_mat.ground_bottom_color = Color(0.34, 0.20, 0.13)
	sky_mat.ground_horizon_color = Color(0.72, 0.48, 0.30)
	sky_mat.sun_angle_max = 14.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.46, 0.40)
	env.ambient_light_energy = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.06
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.54, 0.36)
	env.fog_density = 0.0045   # tuned to the map: it must not hide the mesas
	env.fog_sky_affect = 0.35
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-54), deg_to_rad(36), 0)
	sun.light_color = Color(1.0, 0.92, 0.80)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	# The shadow atlas is capped project-wide, and spreading it over 300 m makes
	# every shadow a smear. Pulling the range in keeps them sharp where players
	# actually are and lets the far basin go unshadowed, which nobody notices.
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)
	var bounce := DirectionalLight3D.new()
	bounce.rotation = Vector3(deg_to_rad(-18), deg_to_rad(-140), 0)
	bounce.light_color = Color(0.90, 0.52, 0.34)   # light coming back off the dust
	bounce.light_energy = 0.42
	bounce.light_specular = 0.0
	bounce.shadow_enabled = false
	add_child(bounce)


func _floor_material() -> Material:
	var mat := _ground_material()
	mat.set_shader_parameter("uv_tiles", Vector2(size, depth) / GROUND_TILE_M)
	mat.set_shader_parameter("slope_mix", 0.0)
	return mat


func _terrain_material() -> Material:
	var mat := _ground_material()
	mat.set_shader_parameter("uv_tiles", Vector2.ONE)
	mat.set_shader_parameter("slope_mix", 1.0)
	return mat


func _ground_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("moss_col", floor_color)
	mat.set_shader_parameter("dirt_col", Color(0.60, 0.36, 0.22))
	mat.set_shader_parameter("rock_col", Color(0.44, 0.31, 0.25))
	mat.set_shader_parameter("deep_col", Color(0.34, 0.18, 0.12))
	mat.set_shader_parameter("cave_col", Color(0.18, 0.10, 0.08))
	return mat


func _decorate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	_build_arena()
	_build_spires(rng)
	_build_boulders(rng)


## The Vespid arena: a ring of wall segments with gaps between them, sitting
## on the flat middle of the basin. Real cover, so these are colliders rather
## than set dressing — it is the one structure people will fight inside.
func _build_arena() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.50, 0.33, 0.23)
	mat.metallic = 0.0
	mat.roughness = 0.85
	for i in ARENA_SEGMENTS:
		if i % 4 == 3:
			continue  # every fourth panel missing: the ways in
		var a := TAU * float(i) / float(ARENA_SEGMENTS)
		var at := Vector3(cos(a) * ARENA_RADIUS, 0.0, sin(a) * ARENA_RADIUS)
		var body := StaticBody3D.new()
		body.position = at + Vector3(0, ARENA_WALL_H * 0.5, 0)
		body.rotation.y = -a
		add_child(body)
		var span := TAU * ARENA_RADIUS / float(ARENA_SEGMENTS) * 1.05
		var box_size := Vector3(1.8, ARENA_WALL_H, span)
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = box_size
		mesh.mesh = bm
		mesh.material_override = mat
		body.add_child(mesh)
		var shape := CollisionShape3D.new()
		var cb := BoxShape3D.new()
		cb.size = box_size
		shape.shape = cb
		body.add_child(shape)


## Rock spires: tall, thin and scattered across the open ground. They are the
## mid-range navigation — something to steer by between the mesas — and they
## break the very longest sight lines without blocking movement.
func _build_spires(rng: RandomNumberGenerator) -> void:
	var tall := []
	var caps := []
	for i in SPIRE_COUNT:
		var p := _open_spot(rng, 26.0)
		if p == Vector3.INF:
			continue
		var height := rng.randf_range(9.0, 22.0)
		var lean := Basis(Vector3.FORWARD, rng.randf_range(-0.06, 0.06)) \
			* Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		tall.append(Transform3D(lean.scaled(Vector3(1.0, height / 14.0, 1.0)),
			p + Vector3(0, height * 0.5, 0)))
		caps.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)),
			p + Vector3(0, height, 0)))
	Props.batch(self, Props.cyl(2.6, 14.0, 6, 0.9), tall,
		Props.material(Color(0.46, 0.30, 0.22), 0.0, 0.9))
	Props.batch(self, Props.ball(1.1, 6), caps,
		Props.material(Color(0.40, 0.26, 0.19), 0.0, 0.9), false)


## Boulder fields. No collision — the cover layout is what the map plays like,
## and 120 loose colliders would both cost physics and quietly change it.
func _build_boulders(rng: RandomNumberGenerator) -> void:
	var rocks := []
	for i in BOULDER_COUNT:
		var p := _open_spot(rng, 6.0)
		if p == Vector3.INF:
			continue
		var s := rng.randf_range(0.8, 2.6)
		rocks.append(Transform3D(
			Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
				Vector3(s * 1.3, s * 0.8, s)),
			p + Vector3(0, s * 0.3, 0)))
	Props.batch(self, Props.ball(1.0, 6), rocks,
		Props.material(Color(0.48, 0.32, 0.23), 0.0, 0.92), false)


## A point on the ground clear of the spawns, the arena and the cover, with its
## height taken from the terrain so props sit ON the dunes rather than in them.
## Returns Vector3.INF when it cannot find one, which the caller skips.
func _open_spot(rng: RandomNumberGenerator, clear: float) -> Vector3:
	var half := half_extents() - Vector2.ONE * 8.0
	for attempt in 24:
		var x := rng.randf_range(-half.x, half.x)
		var z := rng.randf_range(-half.y, half.y)
		var flat := Vector2(x, z)
		if flat.length() < ARENA_RADIUS + 8.0:
			continue  # keep the arena floor clear
		var blocked := false
		for s in republic_spawns + cis_spawns:
			if flat.distance_to(Vector2(s.x, s.z)) < PROP_CLEAR:
				blocked = true
				break
		if not blocked:
			for c in cover_boxes:
				var cp: Vector3 = c["pos"]
				if flat.distance_to(Vector2(cp.x, cp.z)) < clear:
					blocked = true
					break
		if blocked:
			continue
		return Vector3(x, height_at(x, z), z)
	return Vector3.INF
