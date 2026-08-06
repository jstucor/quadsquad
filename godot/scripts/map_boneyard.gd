extends "res://scripts/arena.gd"
## "BONEYARD" — 260 m of ship graveyard, the biggest map in the rotation.
##
## The third shape of big map: not open ground (Aridis), not a forest
## (Silva), not a grid (Senate) — a scatter of ENORMOUS objects with narrow
## ways between them. A downed cruiser hull is 60 m long and 12 m tall, so it is
## not cover you peek around, it is terrain: it blocks a third of the map from
## a third of the map, and where two hulls nearly touch is a choke point that
## the whole round will end up fighting over.
##
## That is the design bet. On a map this size the risk is that nobody ever finds
## anybody; hulls this large solve it by force, because the walkable space
## between them is a handful of wide corridors rather than 67,000 square metres
## of anywhere. The map screen reads it beautifully for the same reason.
##
## Hulls are `cover_boxes` — real colliders, stamped into the nav grid, drawn on
## the map screen. Anything decorative (plating, spars) is batched and never
## collides, so it can never quietly become a wall.

const HULL := Color(0.19, 0.19, 0.21)
const RUST := Color(0.42, 0.26, 0.17)
const SAND := Color(0.46, 0.42, 0.34)
const GROUND_SHADER := preload("res://shaders/jungle_ground.gdshader")
const GROUND_TILE_M := 5.0
const SEED := 20260726

## The wrecks: centre, size, and the yaw they came down at. Hand-placed, not
## scattered — the gaps BETWEEN them are the map, and a random layout gives you
## either a wall or a field, never a route.
const WRECKS: Array[Dictionary] = [
	{"at": Vector2(-56.0, -44.0), "size": Vector3(62.0, 13.0, 20.0), "yaw": 0.32},
	{"at": Vector2(58.0, 46.0), "size": Vector3(62.0, 13.0, 20.0), "yaw": 0.32},
	{"at": Vector2(52.0, -58.0), "size": Vector3(20.0, 15.0, 54.0), "yaw": -0.22},
	{"at": Vector2(-54.0, 60.0), "size": Vector3(20.0, 15.0, 54.0), "yaw": -0.22},
	{"at": Vector2(-104.0, 24.0), "size": Vector3(18.0, 11.0, 44.0), "yaw": 0.10},
	{"at": Vector2(104.0, -22.0), "size": Vector3(18.0, 11.0, 44.0), "yaw": 0.10},
	{"at": Vector2(6.0, -104.0), "size": Vector3(48.0, 10.0, 16.0), "yaw": -0.14},
	{"at": Vector2(-8.0, 106.0), "size": Vector3(48.0, 10.0, 16.0), "yaw": -0.14},
]
## The centre: a broken engine block, the one landmark visible from everywhere
## and the only high ground.
const CORE_R := 14.0
const CORE_H := 9.0


func _configure() -> void:
	size = 260.0
	floor_color = SAND
	wall_color = Color(0.26, 0.24, 0.21)
	cover_color = HULL
	republic_spawns = [Vector3(-110, 0, -108), Vector3(-112, 0, -88), Vector3(-90, 0, -112)]
	cis_spawns = [Vector3(110, 0, 108), Vector3(112, 0, 88), Vector3(90, 0, 112)]
	cover_boxes = _layout()


## A wreck is built from three boxes rather than one: a hull, a raised spine and
## a snapped-off section lying beside it. One box reads as a shipping container
## the size of a building; three read as something that CRASHED, and the offset
## section makes the gap alongside each wreck an actual place rather than a
## straight corridor.
func _layout() -> Array:
	var out: Array = []
	for w in WRECKS:
		var at: Vector2 = w["at"]
		var s: Vector3 = w["size"]
		var yaw: float = w["yaw"]
		var along := Vector3(cos(yaw), 0.0, sin(yaw))
		var across := Vector3(-sin(yaw), 0.0, cos(yaw))
		var base := Vector3(at.x, 0.0, at.y)
		out.append({"pos": base, "size": s})
		# The spine, sitting on top and shorter, so the silhouette steps down.
		out.append({"pos": base + Vector3(0.0, s.y, 0.0),
			"size": Vector3(s.x * 0.55, 4.0, s.z * 0.55)})
		# The broken-off section, thrown clear along the crash line.
		var throw := along * (maxf(s.x, s.z) * 0.75) + across * 9.0
		out.append({"pos": base + throw,
			"size": Vector3(maxf(s.x * 0.3, 8.0), 6.0, maxf(s.z * 0.3, 8.0))})
	# The engine core at the centre, and a skirt of debris to fight from.
	out.append({"pos": Vector3.ZERO, "size": Vector3(CORE_R, CORE_H, CORE_R)})
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.5
		out.append({"pos": Vector3(cos(a) * 24.0, 0.0, sin(a) * 24.0),
			"size": Vector3(7.0, 2.2, 7.0)})
	# Mid-field debris on the two long diagonals, so crossing between wrecks is
	# not a naked sprint.
	for spec in [[-34.0, 30.0], [36.0, -28.0], [-30.0, -76.0], [32.0, 78.0],
			[76.0, 8.0], [-78.0, -6.0], [-70.0, 74.0], [72.0, -72.0]]:
		out.append({"pos": Vector3(spec[0], 0.0, spec[1]),
			"size": Vector3(9.0, 3.0, 5.0)})
	return out


## Dust and low sun: a scrapyard at the end of the day. Warm key, cold fill, and
## the ground pale — so every hull is painted genuinely DARK against it. That is
## not a preference: at a mid grey the hulls rendered the same value as the sand
## under this much warm light, and a map made entirely of silhouettes had no
## silhouettes in it.
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.36, 0.42)
	sky_mat.sky_horizon_color = Color(0.72, 0.60, 0.44)
	sky_mat.ground_bottom_color = Color(0.30, 0.26, 0.20)
	sky_mat.ground_horizon_color = Color(0.66, 0.56, 0.42)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.38, 0.38, 0.42)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.32
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.54, 0.42)
	env.fog_density = 0.0022   # dust haze; at 0.0065 the far wrecks went with it
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.86, 0.66)
	sun.light_energy = 1.05
	# Not as low as it wants to be. At -24 degrees over 260 m the shadow map ran
	# out of depth precision and the entire foreground rendered black — a low sun
	# is the most expensive thing you can ask a directional shadow for.
	sun.rotation_degrees = Vector3(-42.0, 46.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 85.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.48, 0.56, 0.70)
	fill.light_energy = 0.40
	fill.rotation_degrees = Vector3(-20.0, -136.0, 0.0)
	fill.shadow_enabled = false
	fill.light_specular = 0.0
	add_child(fill)


func _floor_material() -> Material:
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	# The jungle shader again, recoloured to scorched sand — it is a three-tone
	# noise blend, so it does dust as readily as moss and saves a second shader.
	mat.set_shader_parameter("moss_col", SAND)
	mat.set_shader_parameter("dirt_col", Color(0.40, 0.34, 0.26))
	mat.set_shader_parameter("deep_col", Color(0.28, 0.23, 0.18))
	mat.set_shader_parameter("tiles", (Vector2(size, depth) / GROUND_TILE_M).round())
	return mat


## Scattered plating and snapped spars. Purely decorative: shin-high litter that
## must never become cover, or the choke points this map is built around would
## quietly fill in.
func _decorate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var plates: Array = []
	var spars: Array = []
	for i in 200:
		var p := Vector3(rng.randf_range(-1.0, 1.0) * size * 0.46, 0.05,
			rng.randf_range(-1.0, 1.0) * size * 0.46)
		var t := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, rng.randf() * TAU)
			.scaled(Vector3(rng.randf_range(0.6, 2.0), 1.0, rng.randf_range(0.6, 2.0))), p)
		plates.append(t)
	for i in 70:
		var p := Vector3(rng.randf_range(-1.0, 1.0) * size * 0.44, 1.2,
			rng.randf_range(-1.0, 1.0) * size * 0.44)
		var t := Transform3D(Basis.IDENTITY
			.rotated(Vector3.UP, rng.randf() * TAU)
			.rotated(Vector3.RIGHT, rng.randf_range(-0.5, 0.5)), p)
		spars.append(t)
	Props.batch(self, Props.box(Vector3(3.0, 0.25, 2.2)), plates,
		Props.material(RUST, 0.12, 0.8), false)
	Props.batch(self, Props.box(Vector3(0.5, 2.6, 0.5)), spars,
		Props.material(HULL.darkened(0.3), 0.12, 0.6), false)
