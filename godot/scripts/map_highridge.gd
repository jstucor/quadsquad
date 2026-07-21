extends "res://scripts/arena.gd"
## "Highridge" — a jungle basin built around a climbable mountain with a tunnel
## bored straight through it, the first map in the rotation that isn't flat.
##
## Terrain is a generated heightfield laid over the flat base plane (the base is
## still there, and is what you stand on inside the tunnel). The hill profile is
## a smoothstep falloff whose gradient peaks at 1.5 * HILL_HEIGHT / (HILL_RADIUS
## - PLATEAU_RADIUS) — those three numbers are chosen to keep the steepest face
## near 27 degrees, well inside the 45-degree limit a CharacterBody3D will walk
## up, so the whole mountain is climbable on foot.
##
## The tunnel is a hollow, not a carve: a heightfield is only a skin, so the
## space under it is already empty. All that's needed is to drop the skin cells
## where the ground would rise INTO the corridor (that opens the two mouths) and
## wall the corridor's sides, so you walk a passage instead of the whole hollow
## interior.

const GROUND_SHADER := preload("res://shaders/jungle_ground.gdshader")

const SEED := 20260722
const HILL_CENTRE := Vector2(0.0, 0.0)
const HILL_RADIUS := 26.0
const PLATEAU_RADIUS := 7.5   # flat top: the objective, and a sniper's perch
const HILL_HEIGHT := 6.2
const ROLL := 0.15            # gentle noise on the flanks, too small to trip on
const CELL := 1.8             # heightfield resolution in metres

# The tunnel runs along X, through the middle of the hill.
const TUNNEL_Z := 0.0
const TUNNEL_HALF_WIDTH := 2.4
const TUNNEL_CEILING := 3.4   # skin below this inside the corridor is cut away

const GROUND_TILE_M := 1.6
const TREE_COUNT := 46
const TREE_SPACING := 3.4
const CONTAINER_COUNT := 14


func _configure() -> void:
	size = 96.0
	depth = 78.0
	floor_color = Color(0.15, 0.23, 0.12)
	wall_color = Color(0.19, 0.24, 0.15)
	cover_color = Color(0.42, 0.44, 0.36)
	# Spawns sit out on the flat, clear of the hill and facing it.
	republic_spawns = [Vector3(-40, 0, -12), Vector3(-40, 0, 12)]
	cis_spawns = [Vector3(40, 0, -12), Vector3(40, 0, 12)]
	# Only low rubble here — the mountain and the containers are the real cover.
	cover_boxes = [
		{"pos": Vector3(-30, 0, -11), "size": Vector3(1.4, 1.3, 5.0)},
		{"pos": Vector3(30, 0, 11), "size": Vector3(1.4, 1.3, 5.0)},
		{"pos": Vector3(-33, 0, -20), "size": Vector3(4.0, 1.2, 1.2)},
		{"pos": Vector3(33, 0, 20), "size": Vector3(4.0, 1.2, 1.2)},
	]


## Ground height at a world XZ. The single source of truth for the terrain: the
## mesh, the collision, and every prop that has to sit on the ground all read it.
func height_at(x: float, z: float) -> float:
	var r := Vector2(x, z).distance_to(HILL_CENTRE)
	if r >= HILL_RADIUS:
		return 0.0
	if r <= PLATEAU_RADIUS:
		return HILL_HEIGHT  # dead flat on top, so the peak is holdable
	var t := (r - PLATEAU_RADIUS) / (HILL_RADIUS - PLATEAU_RADIUS)
	var h := HILL_HEIGHT * (1.0 - smoothstep(0.0, 1.0, t))
	# A little roll so the flanks aren't a perfect cone; kept tiny on purpose,
	# since steep noise would break the walkable-slope guarantee.
	h += sin(x * 0.19) * cos(z * 0.17) * ROLL * (1.0 - t)
	return maxf(h, 0.0)


## True where the corridor needs the skin removed: inside the tunnel's width and
## on ground that would rise into the passage. Away from the mouths the skin is
## above the ceiling and stays put, and that is what roofs the tunnel.
func _is_tunnel_mouth(x: float, z: float) -> bool:
	if absf(z - TUNNEL_Z) > TUNNEL_HALF_WIDTH:
		return false
	var h := height_at(x, z)
	return h > 0.05 and h < TUNNEL_CEILING


func _build_floor() -> void:
	_build_base_plane()
	_build_terrain()
	_build_tunnel_walls()


## The flat base the whole map sits on. It stays under the mountain, and is the
## floor you walk on through the tunnel.
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


## The mountain skin: one mesh, one trimesh collider, cells inside the tunnel
## mouths omitted so you can walk in.
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
			# Flat ground is left to the base plane, or the two would z-fight.
			var tallest := 0.0
			for c: Vector3 in corners:
				tallest = maxf(tallest, c.y)
			if tallest <= 0.05:
				continue
			if _is_tunnel_mouth(x0, z0) or _is_tunnel_mouth(x1, z1):
				continue
			_quad(st, corners[0], corners[1], corners[2], corners[3])
	st.generate_normals()
	var mesh := st.commit()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _floor_material()
	add_child(mi)

	var body := StaticBody3D.new()
	add_child(body)
	var shape := CollisionShape3D.new()
	var tri := mesh.create_trimesh_shape()
	# Without this the terrain is walked straight through with no error of any
	# kind: a ConcavePolygonShape3D only collides on one side by default, and it
	# is not the side the surface normals face. Terrain wants both sides anyway —
	# it also stops anything launched under the map drifting up through the hill.
	tri.backface_collision = true
	shape.shape = tri
	body.add_child(shape)


## Close the corridor's sides so the tunnel is a passage rather than a way into
## the whole hollow hill. Each wall segment only rises as high as the ground
## above it, so nothing pokes out through the mountain.
func _build_tunnel_walls() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.29, 0.26)
	mat.metallic = 0.05  # a dark sky reflects into metal (Gotchas)
	mat.roughness = 0.8
	var half := half_extents()
	var steps := int(size / CELL)
	for side: float in [-1.0, 1.0]:
		var wall_z: float = TUNNEL_Z + side * TUNNEL_HALF_WIDTH
		for i in steps:
			var x := -half.x + i * CELL + CELL * 0.5
			var h := height_at(x, wall_z)
			if h <= 0.1:
				continue
			var wall_h: float = minf(h, TUNNEL_CEILING)
			_wall(Vector3(x, wall_h * 0.5, wall_z), Vector3(CELL, wall_h, 0.3), mat)
	_build_portals(mat)


## A frame at each mouth, so the opening reads as an engineered tunnel rather
## than a hole in the hillside.
func _build_portals(mat: Material) -> void:
	for side: float in [-1.0, 1.0]:
		var mouth_x := _mouth_x(side)
		var post := Vector3(0.6, TUNNEL_CEILING, 0.7)
		_wall(Vector3(mouth_x, TUNNEL_CEILING * 0.5, TUNNEL_Z - TUNNEL_HALF_WIDTH - 0.3),
			post, mat)
		_wall(Vector3(mouth_x, TUNNEL_CEILING * 0.5, TUNNEL_Z + TUNNEL_HALF_WIDTH + 0.3),
			post, mat)
		_wall(Vector3(mouth_x, TUNNEL_CEILING + 0.35, TUNNEL_Z),
			Vector3(0.6, 0.7, TUNNEL_HALF_WIDTH * 2.0 + 2.0), mat)


## Where the ground first rises past the tunnel ceiling on a given side: the
## point the passage stops being open sky and becomes a tunnel.
func _mouth_x(side: float) -> float:
	var x := side * HILL_RADIUS
	while absf(x) > 1.0:
		if height_at(x, TUNNEL_Z) >= TUNNEL_CEILING:
			return x
		x -= side * 0.5
	return side * PLATEAU_RADIUS


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	# Wound counter-clockwise seen from above, so the surface faces up.
	for v: Vector3 in [a, d, c, a, c, b]:
		st.set_uv(Vector2(v.x, v.z) / GROUND_TILE_M)
		st.add_vertex(v)


func _floor_material() -> Material:
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("moss_col", floor_color)
	mat.set_shader_parameter("dirt_col", Color(0.24, 0.18, 0.12))
	mat.set_shader_parameter("deep_col", Color(0.06, 0.12, 0.06))
	# UVs are already in tile units, so the shader shouldn't scale them again.
	mat.set_shader_parameter("tiles", Vector2.ONE)
	return mat


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.27, 0.47, 0.76)
	sky_mat.sky_horizon_color = Color(0.7, 0.77, 0.72)
	sky_mat.ground_bottom_color = Color(0.13, 0.16, 0.1)
	sky_mat.ground_horizon_color = Color(0.53, 0.6, 0.48)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.44, 0.53, 0.4)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.fog_enabled = true
	env.fog_light_color = Color(0.55, 0.66, 0.52)
	env.fog_density = 0.008
	env.fog_sky_affect = 0.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(35), 0)
	sun.light_color = Color(1.0, 0.95, 0.83)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	# Shadowless green fill opposite the sun, so the shaded flank of the
	# mountain stays readable (GL Compatibility).
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-22), deg_to_rad(-145), 0)
	fill.light_color = Color(0.62, 0.82, 0.58)
	fill.light_energy = 0.35
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	add_child(fill)


func _decorate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	Foliage.grow(self, _tree_spots(rng), rng)
	_build_containers(rng)
	_build_flag()


## Trees on the flat and the lower flanks, kept off the plateau, the tunnel line
## and the spawns. Each one sits on the ground, whatever height that is.
func _tree_spots(rng: RandomNumberGenerator) -> Array:
	var spots: Array = []
	var limit := half_extents() - Vector2.ONE * 4.0
	var attempts := 0
	while spots.size() < TREE_COUNT and attempts < TREE_COUNT * 60:
		attempts += 1
		var x := rng.randf_range(-limit.x, limit.x)
		var z := rng.randf_range(-limit.y, limit.y)
		if Vector2(x, z).distance_to(HILL_CENTRE) < PLATEAU_RADIUS + 3.0:
			continue  # the peak stays clear
		if absf(z - TUNNEL_Z) < TUNNEL_HALF_WIDTH + 2.5:
			continue  # don't block the tunnel approach
		var p := Vector3(x, height_at(x, z), z)
		if _too_close(p, spots, TREE_SPACING) or _blocks_play(p):
			continue
		spots.append(p)
	return spots


## Shipping containers scattered around the basin and up the slopes. They're
## proper solid cover you can also stand on, and they sit level on the ground
## they land on rather than floating over the hill.
func _build_containers(rng: RandomNumberGenerator) -> void:
	var placed: Array = []
	var limit := half_extents() - Vector2.ONE * 6.0
	var attempts := 0
	while placed.size() < CONTAINER_COUNT and attempts < CONTAINER_COUNT * 60:
		attempts += 1
		var x := rng.randf_range(-limit.x, limit.x)
		var z := rng.randf_range(-limit.y, limit.y)
		if absf(z - TUNNEL_Z) < TUNNEL_HALF_WIDTH + 3.0:
			continue
		if Vector2(x, z).distance_to(HILL_CENTRE) < PLATEAU_RADIUS + 2.0:
			continue
		var pos := Vector3(x, height_at(x, z), z)
		if _too_close(pos, placed, 9.0) or _blocks_play(pos):
			continue
		placed.append(pos)
		_container(pos, rng)


func _container(pos: Vector3, rng: RandomNumberGenerator) -> void:
	const PALETTE := [
		Color(0.45, 0.26, 0.2), Color(0.2, 0.34, 0.42),
		Color(0.44, 0.42, 0.24), Color(0.28, 0.36, 0.28),
	]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PALETTE[rng.randi() % PALETTE.size()]
	mat.metallic = 0.12  # keep low: a dark sky reflects into metal (Gotchas)
	mat.roughness = 0.65
	var body := StaticBody3D.new()
	body.position = pos + Vector3.UP * 1.3
	body.rotation.y = rng.randf_range(0.0, TAU)
	add_child(body)
	var box_size := Vector3(6.1, 2.6, 2.44)  # roughly a 20ft container
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


## The flag on the plateau: the landmark that says "this is the high ground".
func _build_flag() -> void:
	var top := Vector3(HILL_CENTRE.x, height_at(HILL_CENTRE.x, HILL_CENTRE.y), HILL_CENTRE.y)
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.72, 0.74, 0.78)
	pole_mat.metallic = 0.15
	pole_mat.roughness = 0.4
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09
	cyl.bottom_radius = 0.12
	cyl.height = 7.0
	cyl.radial_segments = 6
	pole.mesh = cyl
	pole.material_override = pole_mat
	pole.position = top + Vector3.UP * 3.5
	add_child(pole)

	var flag_mat := StandardMaterial3D.new()
	flag_mat.albedo_color = Color(0.85, 0.75, 0.3)
	flag_mat.metallic = 0.0
	flag_mat.roughness = 0.85
	flag_mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # a banner has two sides
	var flag := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.6, 1.5, 0.06)
	flag.mesh = bm
	flag.material_override = flag_mat
	flag.position = top + Vector3(1.35, 6.1, 0.0)
	add_child(flag)

	# A collider on the pole, so it's something to hide behind up there.
	var body := StaticBody3D.new()
	body.position = top + Vector3.UP * 3.5
	add_child(body)
	var shape := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = 0.14
	cs.height = 7.0
	shape.shape = cs
	body.add_child(shape)


func _too_close(p: Vector3, placed: Array, gap: float) -> bool:
	for other in placed:
		if Vector2(p.x - other.x, p.z - other.z).length() < gap:
			return true
	return false


func _blocks_play(p: Vector3) -> bool:
	for s in republic_spawns + cis_spawns:
		if p.distance_to(s) < 7.0:
			return true
	for c in cover_boxes:
		var bpos: Vector3 = c["pos"]
		var bsize: Vector3 = c["size"]
		var dx := absf(p.x - bpos.x) - bsize.x * 0.5
		var dz := absf(p.z - bpos.z) - bsize.z * 0.5
		if maxf(dx, 0.0) < 3.0 and maxf(dz, 0.0) < 3.0:
			return true
	return false
