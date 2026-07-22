extends "res://scripts/arena.gd"
## "Citadel" — a desert fortress at dusk, 54 m square, built around one tall
## sandstone keep with four corner towers. Nothing shoots across the middle, so
## the fight is a rotation: the keep splits the map into four quadrants and the
## towers are the corners you contest on the way round it.
##
## Lit as low evening sun: long shadows raking off the keep, a cold sky fill,
## and braziers on the buttresses that mark the four approaches after dark.

const SAND := Color(0.55, 0.45, 0.30)
const STONE := Color(0.48, 0.41, 0.31)
const FIRE := Color(1.0, 0.55, 0.18)
const GROUND_SHADER := preload("res://shaders/jungle_ground.gdshader")
const GROUND_TILE_M := 2.4


func _configure() -> void:
	size = 54.0
	floor_color = SAND
	wall_color = Color(0.42, 0.35, 0.26)    # rampart wall
	cover_color = STONE
	republic_spawns = [Vector3(-20, 0, -20), Vector3(-20, 0, -12), Vector3(-12, 0, -20)]
	cis_spawns = [Vector3(20, 0, 20), Vector3(20, 0, 12), Vector3(12, 0, 20)]
	cover_boxes = [
		# The keep: tall enough that nothing shoots over it.
		{"pos": Vector3(0, 0, 0), "size": Vector3(11.0, 6.0, 11.0)},
		# Buttresses off each face, so the rotation around it is not a clean circle.
		{"pos": Vector3(0, 0, -8.5), "size": Vector3(4.0, 2.6, 3.0)},
		{"pos": Vector3(0, 0, 8.5), "size": Vector3(4.0, 2.6, 3.0)},
		{"pos": Vector3(-8.5, 0, 0), "size": Vector3(3.0, 2.6, 4.0)},
		{"pos": Vector3(8.5, 0, 0), "size": Vector3(3.0, 2.6, 4.0)},
		# Corner towers.
		{"pos": Vector3(-18, 0, 18), "size": Vector3(4.5, 4.5, 4.5)},
		{"pos": Vector3(18, 0, -18), "size": Vector3(4.5, 4.5, 4.5)},
		{"pos": Vector3(-18, 0, -18), "size": Vector3(3.5, 3.5, 3.5)},
		{"pos": Vector3(18, 0, 18), "size": Vector3(3.5, 3.5, 3.5)},
		# Low walls on the approaches between keep and towers.
		{"pos": Vector3(-11, 0, 11), "size": Vector3(1.6, 1.4, 1.6)},
		{"pos": Vector3(11, 0, -11), "size": Vector3(1.6, 1.4, 1.6)},
		{"pos": Vector3(-11, 0, -11), "size": Vector3(1.6, 1.4, 1.6)},
		{"pos": Vector3(11, 0, 11), "size": Vector3(1.6, 1.4, 1.6)},
	]


## Dusk: a burnt orange horizon under a deepening sky, with dust haze thick
## enough to soften the far towers without hiding them.
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.20, 0.24, 0.42)
	sky_mat.sky_horizon_color = Color(0.86, 0.55, 0.30)
	sky_mat.ground_bottom_color = Color(0.26, 0.20, 0.14)
	sky_mat.ground_horizon_color = Color(0.66, 0.48, 0.30)
	sky_mat.sun_angle_max = 18.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.44, 0.38, 0.42)
	env.ambient_light_energy = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.06
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.55, 0.38)  # blown dust
	env.fog_density = 0.010
	env.fog_sky_affect = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_lights() -> void:
	# Low sun, raking almost horizontally: the keep throws a shadow most of the
	# way across a quadrant, which is what makes the rotation read.
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-16), deg_to_rad(52), 0)
	sun.light_color = Color(1.0, 0.76, 0.50)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)
	# Cold sky bounce from the opposite side, so the shaded faces go blue rather
	# than black — the counterweight that keeps a low sun readable.
	var sky_fill := DirectionalLight3D.new()
	sky_fill.rotation = Vector3(deg_to_rad(-55), deg_to_rad(-130), 0)
	sky_fill.light_color = Color(0.48, 0.58, 0.85)
	sky_fill.light_energy = 0.42
	sky_fill.light_specular = 0.0
	sky_fill.shadow_enabled = false
	add_child(sky_fill)


## Sand rather than deck plate: the jungle noise shader recoloured, since it is
## already a three-tone blend of a base, a patch tone and a dark drift.
func _floor_material() -> Material:
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("moss_col", SAND)
	mat.set_shader_parameter("dirt_col", Color(0.44, 0.35, 0.23))  # scoured rock
	mat.set_shader_parameter("deep_col", Color(0.34, 0.26, 0.17))  # wind shadow
	mat.set_shader_parameter("tiles", (Vector2(size, depth) / GROUND_TILE_M).round())
	return mat


func _decorate() -> void:
	_crown_towers()
	_light_braziers()
	_hang_banners()


## Crenellations along the tops of the keep and the four towers. They sit above
## the collider, so they change the silhouette without changing the cover.
func _crown_towers() -> void:
	var merlons := []
	_crenellate(merlons, Vector3(0, 6.0, 0), 11.0, 1.4)
	for c in cover_boxes:
		var s: Vector3 = c["size"]
		var p: Vector3 = c["pos"]
		if s.x < 3.0 or s.y < 3.0 or p.length() < 1.0:
			continue  # towers only; the keep is done above
		_crenellate(merlons, Vector3(p.x, s.y, p.z), s.x, 0.9)
	Props.batch(self, Props.box(Vector3(1.0, 1.0, 1.0)), merlons,
		Props.material(STONE.lightened(0.06), 0.0, 0.85))


## Lay merlons around the rim of a square top, leaving the gaps between them as
## embrasures.
func _crenellate(out: Array, top: Vector3, width: float, block: float) -> void:
	var half := width * 0.5 - block * 0.5
	var steps := maxi(int(width / (block * 2.0)), 2)
	var scale := Basis().scaled(Vector3(block, block, block))
	for i in steps + 1:
		var t := -half + (half * 2.0) * float(i) / float(steps)
		out.append(Transform3D(scale, top + Vector3(t, block * 0.5, -half)))
		out.append(Transform3D(scale, top + Vector3(t, block * 0.5, half)))
		if i > 0 and i < steps:
			out.append(Transform3D(scale, top + Vector3(-half, block * 0.5, t)))
			out.append(Transform3D(scale, top + Vector3(half, block * 0.5, t)))


## A brazier on each of the keep's four buttresses. They mark the approaches,
## and at dusk they are the only warm thing left once the sun drops.
func _light_braziers() -> void:
	var bowls := []
	var flames := []
	for c in cover_boxes:
		var p: Vector3 = c["pos"]
		var s: Vector3 = c["size"]
		if p.length() < 6.0 or p.length() > 10.0:
			continue  # the four buttresses only
		bowls.append(Transform3D(Basis(), Vector3(p.x, s.y + 0.25, p.z)))
		flames.append(Transform3D(Basis(), Vector3(p.x, s.y + 0.75, p.z)))
	Props.batch(self, Props.cyl(0.55, 0.5, 8, 0.75), bowls,
		Props.material(Color(0.24, 0.20, 0.16), 0.2, 0.6))
	Props.batch(self, Props.ball(0.45, 8), flames, Props.glow(FIRE, 3.4), false)


## Team banners down the keep's faces, so which side of it you are on is
## readable at a glance from across the map.
func _hang_banners() -> void:
	var faces := [
		[Vector3(0, 3.6, -5.6), 0.0, GameState.Team.REPUBLIC],
		[Vector3(0, 3.6, 5.6), 0.0, GameState.Team.CIS],
		[Vector3(-5.6, 3.6, 0), PI * 0.5, GameState.Team.REPUBLIC],
		[Vector3(5.6, 3.6, 0), PI * 0.5, GameState.Team.CIS],
	]
	for team in [GameState.Team.REPUBLIC, GameState.Team.CIS]:
		var xforms := []
		for f in faces:
			if f[2] != team:
				continue
			xforms.append(Transform3D(Basis(Vector3.UP, f[1]), f[0]))
		Props.batch(self, Props.box(Vector3(1.6, 4.0, 0.08)), xforms,
			Props.material(GameState.TEAM_COLORS[team].darkened(0.25), 0.0, 0.9))
