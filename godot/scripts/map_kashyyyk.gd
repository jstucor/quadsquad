extends "res://scripts/arena.gd"
## "KASHYYYK" — 220 m of wroshyr forest, and the second of the big maps after
## Geonosis. Where Geonosis is an open basin you navigate by looking across it,
## this one you navigate by what is BLOCKING the view: the trunks are the map.
##
## The design problem with a forest at this size is that evenly scattered trees
## are visual noise and tactical mush — every angle is half-blocked, nothing is
## a landmark, and a firefight is decided by whose tree happened to be nearer.
## So the trunks come in GROVES with real clearings between them, and the
## clearings are where the cover and the fighting are. A grove reads as a wall
## you go around; a clearing reads as a room.
##
## Trunks are `cover_boxes`, not decoration. Anything a player will try to hide
## behind has to be a collider — `Props.batch` geometry never collides, and a
## tree you can shoot through is worse than no tree at all. The decorative
## canopy overhead is batched, because nobody takes cover in a canopy.

const BARK := Color(0.30, 0.22, 0.15)
const MOSS := Color(0.24, 0.33, 0.17)
const LEAF := Color(0.16, 0.28, 0.14)
const GROUND_SHADER := preload("res://shaders/jungle_ground.gdshader")
const GROUND_TILE_M := 4.0
const SEED := 20260724

## Groves: centre, radius, how many trunks. Placed so the middle of the map has
## a ring of them — the centre is a clearing you can be seen crossing, which is
## what stops the whole match collapsing onto it.
const GROVES: Array[Dictionary] = [
	{"at": Vector2(-62.0, -58.0), "r": 26.0, "n": 9},
	{"at": Vector2(64.0, 60.0), "r": 26.0, "n": 9},
	{"at": Vector2(-70.0, 54.0), "r": 24.0, "n": 8},
	{"at": Vector2(66.0, -62.0), "r": 24.0, "n": 8},
	{"at": Vector2(0.0, -84.0), "r": 22.0, "n": 7},
	{"at": Vector2(0.0, 86.0), "r": 22.0, "n": 7},
	{"at": Vector2(-88.0, 0.0), "r": 22.0, "n": 7},
	{"at": Vector2(88.0, 4.0), "r": 22.0, "n": 7},
	{"at": Vector2(-30.0, 24.0), "r": 16.0, "n": 5},
	{"at": Vector2(32.0, -26.0), "r": 16.0, "n": 5},
]
const TRUNK_MIN := 2.4     # a wroshyr is wide enough to be real cover
const TRUNK_MAX := 4.2
const TRUNK_HEIGHT := 22.0  # tall enough that the canopy reads as a ceiling

## The one piece of built structure: a Wookiee village platform over the centre
## clearing, on legs you can fight between.
const VILLAGE_R := 18.0
const VILLAGE_LEGS := 6


func _configure() -> void:
	size = 220.0
	floor_color = MOSS
	wall_color = Color(0.16, 0.20, 0.13)   # the forest just gets darker outward
	cover_color = BARK
	republic_spawns = [Vector3(-88, 0, -84), Vector3(-96, 0, -72), Vector3(-76, 0, -92)]
	cis_spawns = [Vector3(88, 0, 84), Vector3(96, 0, 72), Vector3(76, 0, 92)]
	cover_boxes = _layout()


func _layout() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var out: Array = []
	for grove in GROVES:
		var at: Vector2 = grove["at"]
		for i in int(grove["n"]):
			# Spread over the grove's disc rather than its rim, so a grove has
			# depth to it and cannot be cleared from one angle.
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * float(grove["r"])
			var w := rng.randf_range(TRUNK_MIN, TRUNK_MAX)
			out.append({
				"pos": Vector3(at.x + cos(a) * d, 0.0, at.y + sin(a) * d),
				"size": Vector3(w, TRUNK_HEIGHT, w),
			})
	# The village legs: thick, evenly spaced, and the only cover in the middle.
	for i in VILLAGE_LEGS:
		var a := TAU * float(i) / float(VILLAGE_LEGS)
		out.append({
			"pos": Vector3(cos(a) * VILLAGE_R, 0.0, sin(a) * VILLAGE_R),
			"size": Vector3(3.0, 12.0, 3.0),
		})
	# Fallen trunks around the clearing — low cover you shoot over, which is what
	# makes the middle survivable at all.
	for spec in [[-24.0, -8.0, 14.0, 2.0], [26.0, 10.0, 14.0, 2.0],
			[8.0, -26.0, 2.0, 13.0], [-10.0, 27.0, 2.0, 13.0],
			[-44.0, 40.0, 11.0, 2.2], [46.0, -38.0, 11.0, 2.2],
			[40.0, 44.0, 2.2, 11.0], [-42.0, -46.0, 2.2, 11.0]]:
		out.append({"pos": Vector3(spec[0], 0.0, spec[1]),
			"size": Vector3(spec[2], 1.6, spec[3])})
	return out


## Daylight under a canopy: bright above, deep green shade below. The fog is
## kept thin — at 220 m a dense haze hides the groves that the whole map is for.
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.48, 0.62)
	sky_mat.sky_horizon_color = Color(0.62, 0.70, 0.58)
	sky_mat.ground_bottom_color = Color(0.12, 0.16, 0.10)
	sky_mat.ground_horizon_color = Color(0.44, 0.52, 0.40)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.34, 0.44, 0.34)
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.30
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.20, 0.30, 0.22)
	# 0.006 looked atmospheric and buried the map: over 220 m it washed every
	# grove, trunk and clearing into one flat green. Same lesson as Foundry's
	# 0.026 — a big map needs a FRACTION of a small map's fog.
	env.fog_density = 0.0022
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_lights() -> void:
	# Sun raked low through the trunks, so the groves cast long shadows and the
	# clearings read as bright.
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.96, 0.82)
	sun.light_energy = 1.0
	sun.rotation_degrees = Vector3(-44.0, 34.0, 0.0)
	sun.shadow_enabled = true
	# Pull the shadow range IN. The atlas is capped project-wide, and spreading
	# it over 220 m costs all its depth precision: the whole near ground came
	# back solid black. Sharp where the players are, unshadowed far away, which
	# nobody notices.
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)
	# The shadowless opposing fill every map here needs: without it the shaded
	# side of a trunk is black, and a player standing against one vanishes.
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.55, 0.68, 0.60)
	fill.light_energy = 0.42
	fill.rotation_degrees = Vector3(-16.0, -142.0, 0.0)
	fill.shadow_enabled = false
	fill.light_specular = 0.0
	add_child(fill)


func _floor_material() -> Material:
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("moss_col", MOSS)
	mat.set_shader_parameter("dirt_col", Color(0.24, 0.20, 0.13))
	mat.set_shader_parameter("deep_col", Color(0.07, 0.13, 0.06))
	mat.set_shader_parameter("tiles", (Vector2(size, depth) / GROUND_TILE_M).round())
	return mat


## Canopy and undergrowth, all batched and none of it colliding. The canopy sits
## ABOVE the trunks' tops so it never blocks a shot — it is a ceiling for the
## eye, not for the bullets.
func _decorate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 1
	var canopy: Array = []
	var ferns: Array = []
	for grove in GROVES:
		var at: Vector2 = grove["at"]
		for i in int(grove["n"]) * 2:
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * float(grove["r"]) * 1.15
			var p := Vector3(at.x + cos(a) * d, TRUNK_HEIGHT + 3.0, at.y + sin(a) * d)
			var t := Transform3D(Basis.IDENTITY.scaled(
				Vector3.ONE * rng.randf_range(0.9, 1.6)), p)
			canopy.append(t)
	for i in 260:
		var p := Vector3(rng.randf_range(-1.0, 1.0) * size * 0.48, 0.0,
			rng.randf_range(-1.0, 1.0) * size * 0.48)
		ferns.append(Transform3D(Basis.IDENTITY.rotated(
			Vector3.UP, rng.randf() * TAU), p))
	Props.batch(self, Props.ball(7.0, 6), canopy, Props.material(LEAF, 0.0, 0.9), false)
	Props.batch(self, Props.box(Vector3(1.6, 0.9, 1.6)), ferns,
		Props.material(Color(0.22, 0.32, 0.16), 0.0, 0.9), false)
