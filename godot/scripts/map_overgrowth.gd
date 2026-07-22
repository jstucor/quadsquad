extends "res://scripts/arena.gd"
## "Overgrowth" — an outdoor jungle basin, 86 m wide x 68 m deep (the biggest
## map, and the only rectangular one), Republic spawns South and CIS North
## across a ruined stone temple at mid-field. Unlike the interior
## maps this one is lit as daylight: a warm sun, a green canopy-bounce fill and
## a humid haze, over a procedural moss/dirt floor instead of the metal deck.
##
## The trees are the map's real cover. They are drawn as two MultiMeshes
## (trunks + canopies) so the whole forest costs two draw calls per viewport
## rather than one per tree, with a single StaticBody3D holding one capsule per
## trunk for collision. Layout is generated from a fixed seed, so every match
## on this map plays the same forest.

const GROUND_SHADER := preload("res://shaders/jungle_ground.gdshader")

const TREE_SEED := 20260721
const TREE_DENSITY := 0.011  # trunks per m2 of floor; the count follows the size
const TREE_SPACING := 3.2   # minimum gap between two trunks
const GROUND_TILE_M := 1.6  # metres per tile of the ground shader's noise
const EDGE_MARGIN := 3.5    # keep trunks off the boundary wall
const SPAWN_CLEAR := 6.0    # no trunk this close to a spawn point
const COVER_CLEAR := 2.6    # ...or crowding a ruin block
const CENTRE_CLEAR := 8.0   # the temple plaza stays open for the mid fight


func _configure() -> void:
	# Wide and shallow: the widest map in the rotation, so the flanks are a real
	# route rather than a lane, and both teams cross the treeline head-on.
	size = 86.0
	depth = 68.0
	floor_color = Color(0.15, 0.23, 0.12)
	wall_color = Color(0.19, 0.24, 0.15)   # dense treeline / mossy cliff
	cover_color = Color(0.42, 0.44, 0.36)  # weathered temple stone
	republic_spawns = [Vector3(-11, 0, -28), Vector3(11, 0, -28)]
	cis_spawns = [Vector3(-11, 0, 28), Vector3(11, 0, 28)]
	cover_boxes = [
		# Ruined temple at mid-field: a broken core with two flanking walls.
		{"pos": Vector3(0, 0, 0), "size": Vector3(7.0, 3.4, 7.0)},
		{"pos": Vector3(-7.5, 0, 0), "size": Vector3(1.2, 2.0, 8.0)},
		{"pos": Vector3(7.5, 0, 0), "size": Vector3(1.2, 2.0, 8.0)},
		# Toppled pillars, low enough to crouch behind and shoot over.
		{"pos": Vector3(-4, 0, -10), "size": Vector3(6.0, 1.1, 1.1)},
		{"pos": Vector3(4, 0, 10), "size": Vector3(6.0, 1.1, 1.1)},
		# Outer shrines: the wide flanks get their own hard cover to fight over.
		{"pos": Vector3(-26, 0, -4), "size": Vector3(4.5, 2.8, 4.5)},
		{"pos": Vector3(26, 0, 4), "size": Vector3(4.5, 2.8, 4.5)},
		{"pos": Vector3(-33, 0, 12), "size": Vector3(3.0, 2.0, 6.0)},
		{"pos": Vector3(33, 0, -12), "size": Vector3(3.0, 2.0, 6.0)},
		# Mid-flank boulders bridging the centre to the outer shrines.
		{"pos": Vector3(-17, 0, -8), "size": Vector3(2.6, 2.2, 2.6)},
		{"pos": Vector3(17, 0, 8), "size": Vector3(2.6, 2.2, 2.6)},
		{"pos": Vector3(-17, 0, 10), "size": Vector3(2.2, 1.6, 3.0)},
		{"pos": Vector3(17, 0, -10), "size": Vector3(2.2, 1.6, 3.0)},
		# Forward cover so a spawn isn't a shooting gallery.
		{"pos": Vector3(-11, 0, -21), "size": Vector3(4.5, 1.4, 1.4)},
		{"pos": Vector3(11, 0, -21), "size": Vector3(4.5, 1.4, 1.4)},
		{"pos": Vector3(-11, 0, 21), "size": Vector3(4.5, 1.4, 1.4)},
		{"pos": Vector3(11, 0, 21), "size": Vector3(4.5, 1.4, 1.4)},
	]


## Daylight instead of the starfield: blue sky, warm sun, humid green haze.
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.29, 0.50, 0.78)
	sky_mat.sky_horizon_color = Color(0.68, 0.76, 0.72)
	sky_mat.ground_bottom_color = Color(0.14, 0.17, 0.11)
	sky_mat.ground_horizon_color = Color(0.55, 0.62, 0.50)
	sky_mat.sun_angle_max = 12.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.52, 0.38)  # green canopy bounce
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.55, 0.66, 0.52)
	env.fog_density = 0.011
	env.fog_sky_affect = 0.25
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-58), deg_to_rad(24), 0)
	sun.light_color = Color(1.0, 0.95, 0.82)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	# Shadowless green fill from the opposite side: leaf-filtered light, and it
	# keeps shadow sides readable without touching ambient (GL Compatibility).
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-20), deg_to_rad(-140), 0)
	fill.light_color = Color(0.62, 0.82, 0.58)
	fill.light_energy = 0.35
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	add_child(fill)


func _floor_material() -> Material:
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("moss_col", floor_color)
	mat.set_shader_parameter("dirt_col", Color(0.24, 0.18, 0.12))
	mat.set_shader_parameter("deep_col", Color(0.06, 0.12, 0.06))
	mat.set_shader_parameter("tiles", (Vector2(size, depth) / GROUND_TILE_M).round())
	return mat


func _decorate() -> void:
	_build_trees()


func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = TREE_SEED
	Foliage.grow(self, _tree_spots(rng, roundi(size * depth * TREE_DENSITY)), rng)


## Trunk positions by rejection sampling: keep drawing points until `count` of
## them clear the spawns, the temple plaza, the ruin blocks, the boundary wall
## and each other. Bounded by an attempt cap so a too-dense map can't spin.
func _tree_spots(rng: RandomNumberGenerator, count: int) -> Array[Vector3]:
	var spots: Array[Vector3] = []
	var limit := half_extents() - Vector2.ONE * EDGE_MARGIN
	var attempts := 0
	while spots.size() < count and attempts < count * 40:
		attempts += 1
		var p := Vector3(rng.randf_range(-limit.x, limit.x), 0.0,
			rng.randf_range(-limit.y, limit.y))
		if Vector2(p.x, p.z).length() < CENTRE_CLEAR:
			continue
		if _too_close(p, spots, TREE_SPACING) or _blocks_play(p):
			continue
		spots.append(p)
	return spots


func _too_close(p: Vector3, spots: Array[Vector3], gap: float) -> bool:
	for s in spots:
		if p.distance_to(s) < gap:
			return true
	return false


func _blocks_play(p: Vector3) -> bool:
	for s in republic_spawns + cis_spawns:
		if p.distance_to(s) < SPAWN_CLEAR:
			return true
	for c in cover_boxes:
		var bpos: Vector3 = c["pos"]
		var bsize: Vector3 = c["size"]
		# Distance to the block's footprint rectangle, in the XZ plane.
		var dx := absf(p.x - bpos.x) - bsize.x * 0.5
		var dz := absf(p.z - bpos.z) - bsize.z * 0.5
		if maxf(dx, 0.0) < COVER_CLEAR and maxf(dz, 0.0) < COVER_CLEAR:
			return true
	return false


