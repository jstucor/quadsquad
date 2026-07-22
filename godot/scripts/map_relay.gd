extends "res://scripts/arena.gd"
## "Relay" — a frozen listening post on an ice plain, 64 m across, teams
## spawning at opposite corners. Cover is deliberately sparse and LOW: sight
## lines are long, there is almost nothing tall to hide behind, and crossing the
## open is a decision rather than a walk. This is the map where a scope earns
## its price.
##
## The two relay masts are the only tall things out here, so they are what you
## navigate by. Everything built is painted dark against the ice: on a white map
## anything mid-toned vanishes into the ground, players included.

const SNOW := Color(0.68, 0.74, 0.82)
const ICE := Color(0.58, 0.68, 0.80)
const RIG := Color(0.17, 0.19, 0.23)
const GROUND_SHADER := preload("res://shaders/jungle_ground.gdshader")
const GROUND_TILE_M := 3.0
const DRIFT_SEED := 20260722


func _configure() -> void:
	size = 64.0
	floor_color = SNOW
	wall_color = Color(0.26, 0.31, 0.38)    # dark rock ringing the basin
	cover_color = Color(0.19, 0.22, 0.27)   # dark outpost equipment
	republic_spawns = [Vector3(-26, 0, -22), Vector3(-22, 0, -26), Vector3(-28, 0, -14)]
	cis_spawns = [Vector3(26, 0, 22), Vector3(22, 0, 26), Vector3(28, 0, 14)]
	cover_boxes = [
		# The two relay masts' housings: the only tall cover on the map, and the
		# only ground worth holding.
		{"pos": Vector3(-9, 0, 9), "size": Vector3(3.0, 5.0, 3.0)},
		{"pos": Vector3(9, 0, -9), "size": Vector3(3.0, 5.0, 3.0)},
		# Everything else is waist-high: it breaks a sight line, it does not end one.
		{"pos": Vector3(0, 0, 0), "size": Vector3(8.0, 1.3, 1.6)},
		{"pos": Vector3(-16, 0, 2), "size": Vector3(1.6, 1.3, 7.0)},
		{"pos": Vector3(16, 0, -2), "size": Vector3(1.6, 1.3, 7.0)},
		{"pos": Vector3(-4, 0, -17), "size": Vector3(6.0, 1.3, 1.6)},
		{"pos": Vector3(4, 0, 17), "size": Vector3(6.0, 1.3, 1.6)},
		{"pos": Vector3(-20, 0, 20), "size": Vector3(2.2, 1.8, 2.2)},
		{"pos": Vector3(20, 0, -20), "size": Vector3(2.2, 1.8, 2.2)},
		{"pos": Vector3(-14, 0, -12), "size": Vector3(1.8, 1.5, 1.8)},
		{"pos": Vector3(14, 0, 12), "size": Vector3(1.8, 1.5, 1.8)},
		{"pos": Vector3(24, 0, 24), "size": Vector3(2.0, 1.6, 2.0)},
		{"pos": Vector3(-24, 0, -24), "size": Vector3(2.0, 1.6, 2.0)},
	]


## A clear, bitter cold day rather than a whiteout. That is a deliberate walk
## back: this is the map whose whole purpose is long sight lines and a scope,
## and heavy white fog cancelled exactly that — it also flattened every crate,
## mast and player into the same white as the snow. So the haze is thin, and the
## contrast comes from painting the outpost dark against the ice instead.
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.52, 0.62, 0.76)
	sky_mat.sky_horizon_color = Color(0.80, 0.85, 0.90)
	sky_mat.ground_bottom_color = Color(0.70, 0.76, 0.84)
	sky_mat.ground_horizon_color = Color(0.80, 0.85, 0.90)
	sky_mat.sun_angle_max = 30.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Snow bounces a lot of light, and that is exactly the danger: on a white
	# map, anything that is not itself dark washes to the same value as the
	# ground. At 1.15 ambient over pale cover the crates, the masts and the
	# PLAYERS all disappeared into the snow, on the map with the longest sight
	# lines in the rotation. So the ambient is held down AND every structure is
	# painted dark — the outpost reads as black machinery on white, which is
	# both legible and what an arctic station actually looks like.
	env.ambient_light_color = Color(0.52, 0.60, 0.72)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.80, 0.90)
	env.fog_density = 0.005   # depth cue only; the far corner stays a target
	env.fog_sky_affect = 0.35
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_lights() -> void:
	# Diffuse overcast light: high, weak and almost shadowless, because a
	# whiteout has no direction to it.
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-62), deg_to_rad(-30), 0)
	key.light_color = Color(0.90, 0.94, 1.0)
	key.light_energy = 1.0
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-30), deg_to_rad(140), 0)
	fill.light_color = ICE
	fill.light_energy = 0.28
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	add_child(fill)


func _floor_material() -> Material:
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("moss_col", SNOW)
	mat.set_shader_parameter("dirt_col", Color(0.66, 0.72, 0.82))  # wind-scoured ice
	mat.set_shader_parameter("deep_col", ICE)                      # blue hollows
	mat.set_shader_parameter("tiles", (Vector2(size, depth) / GROUND_TILE_M).round())
	return mat


func _decorate() -> void:
	_raise_masts()
	_scatter_drifts()


## The two relay masts, on top of their housings: a lattice tower, a dish angled
## at the sky, and a hazard lamp. Tall enough to see from anywhere, which is the
## only navigation this map offers once the blizzard closes in.
func _raise_masts() -> void:
	var sites := [Vector3(-9, 5.0, 9), Vector3(9, 5.0, -9)]
	var towers := []
	var dishes := []
	var lamps := []
	var stays := []
	for i in sites.size():
		var p: Vector3 = sites[i]
		var yaw := atan2(-p.x, -p.z)
		towers.append(Transform3D(Basis(), p + Vector3(0, 5.0, 0)))
		dishes.append(Transform3D(
			Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(-40)),
			p + Vector3(0, 9.4, 0)))
		lamps.append(Transform3D(Basis(), p + Vector3(0, 10.4, 0)))
		# Guy wires from up the tower out to three ground anchors. Each is one
		# unit-length box aimed down the run and stretched to fit it: looking_at
		# puts local -Z on the target, so scaling Z by the span is the whole
		# trick.
		var top := p + Vector3(0, 8.0, 0)
		for k in 3:
			var a := TAU * float(k) / 3.0 + yaw
			var anchor := p + Vector3(cos(a), 0.0, sin(a)) * 5.0 - Vector3(0, 5.0, 0)
			var run := top - anchor
			stays.append(Transform3D(
				Basis.looking_at(run, Vector3.UP).scaled(Vector3(1.0, 1.0, run.length())),
				(top + anchor) * 0.5))
	Props.batch(self, Props.cyl(0.30, 10.0, 4), towers, Props.material(RIG, 0.2, 0.55))
	Props.batch(self, Props.cyl(2.2, 0.3, 12), dishes,
		Props.material(Color(0.46, 0.50, 0.56), 0.1, 0.45))
	Props.batch(self, Props.ball(0.3, 6), lamps,
		Props.glow(Color(1.0, 0.35, 0.25), 3.0), false)
	Props.batch(self, Props.box(Vector3(0.07, 0.07, 1.0)), stays,
		Props.material(RIG.darkened(0.3), 0.1, 0.7), false)


## Wind-blown drifts banked against the cover. Flattened spheres, no collision,
## seeded so the plain looks the same every match.
func _scatter_drifts() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = DRIFT_SEED
	var drifts := []
	for c in cover_boxes:
		var p: Vector3 = c["pos"]
		var s: Vector3 = c["size"]
		# Two drifts per block, on the downwind (+X) side.
		for k in 2:
			var off := Vector3(s.x * 0.5 + rng.randf_range(0.3, 1.1), 0.0,
				rng.randf_range(-s.z * 0.5, s.z * 0.5))
			var scale := rng.randf_range(0.8, 1.6)
			drifts.append(Transform3D(
				Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
					Vector3(scale * 1.8, scale * 0.35, scale)),
				p + off))
	Props.batch(self, Props.ball(1.0, 8), drifts,
		Props.material(SNOW.lightened(0.05), 0.0, 0.95), false)
