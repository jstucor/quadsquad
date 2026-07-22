extends "res://scripts/arena.gd"
## "Spillway" — a drainage works cut into rock, 30 m across and 76 m end to end,
## teams at opposite ends. The length is the point: sight lines run the whole
## map, so the staggered mid-channel weirs are the only way to cross, and the
## side outfalls are what a flanker uses to get past them.
##
## Wet concrete under a permanent overcast, lit cold and green from the standing
## water in the side channels. The water is set-dressing only — it is drawn in
## the dead strips along both walls, so it frames the fighting ground without
## ever being ground you fight over.

const CONCRETE := Color(0.34, 0.36, 0.35)
const WATER := Color(0.16, 0.34, 0.33)
const PIPE := Color(0.28, 0.31, 0.30)
const GROUND_SHADER := preload("res://shaders/jungle_ground.gdshader")
const GROUND_TILE_M := 2.0
const CHANNEL_INSET := 3.4   # how far the water strips sit off each wall


func _configure() -> void:
	size = 30.0
	depth = 76.0
	floor_color = CONCRETE
	wall_color = Color(0.27, 0.29, 0.28)    # streaked retaining wall
	cover_color = Color(0.40, 0.42, 0.40)   # poured weirs and pillars
	republic_spawns = [Vector3(-8, 0, -32), Vector3(0, 0, -34), Vector3(8, 0, -32)]
	cis_spawns = [Vector3(-8, 0, 32), Vector3(0, 0, 34), Vector3(8, 0, 32)]
	cover_boxes = [
		# Staggered weirs: no single line runs the full length of the channel.
		{"pos": Vector3(-6, 0, -8), "size": Vector3(6.0, 3.0, 2.2)},
		{"pos": Vector3(6, 0, 0), "size": Vector3(6.0, 3.0, 2.2)},
		{"pos": Vector3(-6, 0, 8), "size": Vector3(6.0, 3.0, 2.2)},
		# Side outfalls, the flanking route past those weirs.
		{"pos": Vector3(-12, 0, -18), "size": Vector3(3.0, 2.4, 5.0)},
		{"pos": Vector3(12, 0, -18), "size": Vector3(3.0, 2.4, 5.0)},
		{"pos": Vector3(-12, 0, 18), "size": Vector3(3.0, 2.4, 5.0)},
		{"pos": Vector3(12, 0, 18), "size": Vector3(3.0, 2.4, 5.0)},
		# Low sills to break the run out of each end.
		{"pos": Vector3(0, 0, -24), "size": Vector3(7.0, 1.2, 1.4)},
		{"pos": Vector3(0, 0, 24), "size": Vector3(7.0, 1.2, 1.4)},
		{"pos": Vector3(-10, 0, -28), "size": Vector3(1.6, 1.8, 1.6)},
		{"pos": Vector3(10, 0, 28), "size": Vector3(1.6, 1.8, 1.6)},
	]


## Permanent overcast down in the cut: flat grey light, damp haze, and no sun to
## speak of. The haze is thin — this map's cover is geometry, not weather.
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.36, 0.38)
	sky_mat.sky_horizon_color = Color(0.46, 0.52, 0.52)
	sky_mat.ground_bottom_color = Color(0.16, 0.19, 0.19)
	sky_mat.ground_horizon_color = Color(0.36, 0.41, 0.41)
	sky_mat.sun_angle_max = 40.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.34, 0.42, 0.44)
	env.ambient_light_energy = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.34, 0.42, 0.42)
	env.fog_density = 0.013
	env.fog_sky_affect = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_lights() -> void:
	# Grey daylight straight down the cut, so the weirs cast across the channel
	# rather than along it.
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-64), deg_to_rad(88), 0)
	key.light_color = Color(0.86, 0.90, 0.92)
	key.light_energy = 0.95
	key.shadow_enabled = true
	add_child(key)
	# Green bounce off the standing water, from below the horizon.
	var damp := DirectionalLight3D.new()
	damp.rotation = Vector3(deg_to_rad(8), deg_to_rad(-90), 0)
	damp.light_color = Color(0.35, 0.72, 0.62)
	damp.light_energy = 0.40
	damp.light_specular = 0.0
	damp.shadow_enabled = false
	add_child(damp)


func _floor_material() -> Material:
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("moss_col", CONCRETE)
	mat.set_shader_parameter("dirt_col", Color(0.28, 0.31, 0.29))  # wet patches
	mat.set_shader_parameter("deep_col", Color(0.20, 0.26, 0.23))  # algae streaks
	mat.set_shader_parameter("tiles", (Vector2(size, depth) / GROUND_TILE_M).round())
	return mat


func _decorate() -> void:
	_flood_side_channels()
	_run_pipes()
	_raise_sluices()


## Standing water down both walls, unshaded so it reads as water rather than a
## painted stripe — and placed in the strips nobody fights in, so it never
## becomes cover you expected to be solid.
##
## It sits just ABOVE the deck. The floor is a solid plane at y=0, so sinking
## the water to look recessed simply buried it under the floor and nothing was
## drawn at all.
func _flood_side_channels() -> void:
	var half := half_extents()
	var x := half.x - CHANNEL_INSET
	var runs := [
		Transform3D(Basis(), Vector3(-x, 0.03, 0)),
		Transform3D(Basis(), Vector3(x, 0.03, 0)),
	]
	Props.batch(self, Props.box(Vector3(4.4, 0.12, depth - 2.0)), runs,
		Props.glow(WATER, 0.9), false)


## Pipe runs along both retaining walls, with outfall mouths spilling into the
## side channels. This is what tells you the cut is drainage and not a trench.
func _run_pipes() -> void:
	var half := half_extents()
	var x := half.x - 0.9
	var pipes := []
	var mouths := []
	for side in [-1.0, 1.0]:
		pipes.append(Transform3D(
			Basis(Vector3.RIGHT, PI * 0.5), Vector3(side * x, 4.2, 0)))
		# Four outfalls a side, angled down into the water.
		for i in 4:
			var z := -half.y + (depth / 5.0) * float(i + 1)
			mouths.append(Transform3D(
				Basis(Vector3.FORWARD, side * deg_to_rad(58)),
				Vector3(side * (x - 0.5), 3.1, z)))
	Props.batch(self, Props.cyl(0.55, depth - 1.0, 8), pipes,
		Props.material(PIPE, 0.15, 0.6))
	Props.batch(self, Props.cyl(0.34, 2.4, 6), mouths,
		Props.material(PIPE.darkened(0.15), 0.15, 0.6))


## Sluice gate frames across both ends, above the spawns. They cap the channel
## visually so it reads as a works with two ends, not a corridor that stops.
func _raise_sluices() -> void:
	var half := half_extents()
	var lintels := []
	var posts := []
	for z in [-half.y + 4.0, half.y - 4.0]:
		lintels.append(Transform3D(Basis(), Vector3(0, 6.4, z)))
		for side in [-1.0, 1.0]:
			posts.append(Transform3D(Basis(), Vector3(side * (half.x - 1.6), 3.2, z)))
	Props.batch(self, Props.box(Vector3(size - 2.0, 1.2, 1.0)), lintels,
		Props.material(PIPE.darkened(0.2), 0.15, 0.6))
	Props.batch(self, Props.box(Vector3(1.2, 6.4, 1.2)), posts,
		Props.material(CONCRETE.darkened(0.2), 0.05, 0.8))
