extends "res://scripts/arena.gd"
## "Catwalk" — the maintenance decks of a station, a cramped 34 m box cut into
## corridors by full-height bulkheads. Every engagement is a corner at close
## range, which makes it the scattergun and dual-wield map: there is nowhere far
## enough away to want a scope.
##
## Lit as an interior with the main lighting off. What you actually see by is the
## strip lighting along the bulkheads and the red emergency domes overhead, so
## the corridors read as lit lanes between dark corners.

const DECK := Color(0.14, 0.15, 0.17)
const STRIP := Color(0.45, 0.80, 1.0)
const ALARM := Color(1.0, 0.20, 0.16)
const PIPE := Color(0.24, 0.26, 0.29)


func _configure() -> void:
	size = 34.0
	floor_color = DECK
	wall_color = Color(0.17, 0.18, 0.21)    # hull plate
	cover_color = Color(0.21, 0.22, 0.26)   # bulkheads
	republic_spawns = [Vector3(-13, 0, -13), Vector3(-13, 0, 0), Vector3(-13, 0, 13)]
	cis_spawns = [Vector3(13, 0, 13), Vector3(13, 0, 0), Vector3(13, 0, -13)]
	cover_boxes = [
		# Full-height bulkheads, laid out so no corridor runs straight through.
		{"pos": Vector3(-6, 0, -10), "size": Vector3(1.4, 4.0, 9.0)},
		{"pos": Vector3(6, 0, 10), "size": Vector3(1.4, 4.0, 9.0)},
		{"pos": Vector3(-6, 0, 9), "size": Vector3(1.4, 4.0, 5.0)},
		{"pos": Vector3(6, 0, -9), "size": Vector3(1.4, 4.0, 5.0)},
		{"pos": Vector3(0, 0, -4), "size": Vector3(7.0, 4.0, 1.4)},
		{"pos": Vector3(0, 0, 4), "size": Vector3(7.0, 4.0, 1.4)},
		# Waist-high crates in the pockets, for the fights that happen in them.
		{"pos": Vector3(0, 0, 0), "size": Vector3(1.6, 1.3, 1.6)},
		{"pos": Vector3(-11, 0, 6), "size": Vector3(1.5, 1.4, 1.5)},
		{"pos": Vector3(11, 0, -6), "size": Vector3(1.5, 1.4, 1.5)},
		{"pos": Vector3(-11, 0, -6), "size": Vector3(1.5, 1.4, 1.5)},
		{"pos": Vector3(11, 0, 6), "size": Vector3(1.5, 1.4, 1.5)},
	]


## Interior, so there is no sky to speak of — near black, with the glow budget
## spent on the strip lighting instead.
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.02, 0.02, 0.03)
	sky_mat.sky_horizon_color = Color(0.05, 0.06, 0.08)
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.03)
	sky_mat.ground_horizon_color = Color(0.05, 0.06, 0.08)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.18, 0.22, 0.30)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.75   # the strips are the light source; let them bleed
	env.glow_bloom = 0.14
	env.fog_enabled = true
	env.fog_light_color = Color(0.10, 0.14, 0.20)
	env.fog_density = 0.020
	env.fog_sky_affect = 0.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_lights() -> void:
	# Weak overhead service lighting, steep so the corridors stay dark and the
	# tops of the bulkheads catch it.
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-76), deg_to_rad(15), 0)
	key.light_color = Color(0.78, 0.86, 1.0)
	key.light_energy = 0.6
	key.shadow_enabled = true
	add_child(key)
	# Cold shadowless fill standing in for the strips, so the corners are dim
	# rather than solid black (GL Compatibility gotcha).
	var strips := DirectionalLight3D.new()
	strips.rotation = Vector3(deg_to_rad(-8), deg_to_rad(-160), 0)
	strips.light_color = STRIP
	strips.light_energy = 0.34
	strips.light_specular = 0.0
	strips.shadow_enabled = false
	add_child(strips)


func _decorate() -> void:
	_light_strips()
	_hang_conduits()
	_emergency_domes()


## A lit strip down both long faces of every full-height bulkhead, at chest
## height. These ARE the map's lighting, and because they follow the cover they
## also trace the corridors for you.
func _light_strips() -> void:
	var xforms := []
	for c in cover_boxes:
		var s: Vector3 = c["size"]
		if s.y < 3.0:
			continue  # bulkheads only, not the crates
		var p: Vector3 = c["pos"]
		var along_z: bool = s.z > s.x
		var length := (s.z if along_z else s.x) - 0.6
		var mesh_size := Vector3(0.06, 0.16, length) if along_z \
			else Vector3(length, 0.16, 0.06)
		var off := (s.x if along_z else s.z) * 0.5 + 0.04
		for side in [-1.0, 1.0]:
			var at := p + Vector3(0, 1.5, 0) \
				+ (Vector3(side * off, 0, 0) if along_z else Vector3(0, 0, side * off))
			xforms.append(Transform3D(Basis().scaled(mesh_size), at))
	# One unit box scaled per instance, so every strip length is one batch.
	Props.batch(self, Props.box(Vector3.ONE), xforms, Props.glow(STRIP, 2.4), false)


## Conduit runs across the ceiling. They tie the bulkheads together overhead and
## give the ceiling something for the key light to break up.
func _hang_conduits() -> void:
	var runs := []
	for x in [-10.0, -3.0, 3.0, 10.0]:
		runs.append(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, 4.6, 0)))
	Props.batch(self, Props.cyl(0.22, size - 1.0, 6), runs,
		Props.material(PIPE, 0.15, 0.6))
	# Cross-ties, so the ceiling reads as a grid rather than four loose pipes.
	var ties := []
	for z in [-11.0, 0.0, 11.0]:
		ties.append(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 5.0, z)))
	Props.batch(self, Props.cyl(0.16, size - 1.0, 6), ties,
		Props.material(PIPE.darkened(0.2), 0.15, 0.6))


## Red emergency domes over the two team ends. They are the only warm light in
## here, and they tell you which end of the station you are looking down.
func _emergency_domes() -> void:
	var domes := []
	for z in [-14.0, 14.0]:
		for x in [-8.0, 0.0, 8.0]:
			domes.append(Transform3D(Basis().scaled(Vector3(1, 0.5, 1)),
				Vector3(x, 4.3, z)))
	Props.batch(self, Props.ball(0.34, 8), domes, Props.glow(ALARM, 2.6), false)
