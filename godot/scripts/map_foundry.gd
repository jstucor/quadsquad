extends "res://scripts/arena.gd"
## "Foundry" — a working smelting floor, 46 m across, Concord West and Automata East
## across a line of casting moulds with lane gaps between them.
##
## The map is lit by its own furnaces: a dim overhead key and a strong warm
## bounce coming back off the molten channels, with heavy smoke haze that eats
## the long sight lines. The channels themselves are the landmark — they run in
## the gaps BETWEEN the mould blocks, so the routes through the middle are the
## bright ones and crossing the map means crossing the light.

const CHANNEL_COLOR := Color(1.0, 0.42, 0.08)
const IRON := Color(0.20, 0.17, 0.16)


func _configure() -> void:
	size = 46.0
	floor_color = Color(0.16, 0.13, 0.12)   # soot-blackened deck
	wall_color = Color(0.21, 0.16, 0.13)    # rusted plate
	cover_color = Color(0.27, 0.22, 0.19)   # scorched casting moulds
	republic_spawns = [Vector3(-19, 0, -5), Vector3(-19, 0, 5)]
	cis_spawns = [Vector3(19, 0, -5), Vector3(19, 0, 5)]
	cover_boxes = [
		# The casting moulds: a broken line down the middle with two lane gaps.
		{"pos": Vector3(0, 0, -14), "size": Vector3(2.5, 3.0, 8.0)},
		{"pos": Vector3(0, 0, 14), "size": Vector3(2.5, 3.0, 8.0)},
		{"pos": Vector3(0, 0, 0), "size": Vector3(2.5, 2.4, 4.0)},
		# Slag heaps on the flanks.
		{"pos": Vector3(-9, 0, -8), "size": Vector3(1.6, 1.6, 1.6)},
		{"pos": Vector3(9, 0, 8), "size": Vector3(1.6, 1.6, 1.6)},
		{"pos": Vector3(-9, 0, 8), "size": Vector3(1.6, 1.6, 1.6)},
		{"pos": Vector3(9, 0, -8), "size": Vector3(1.6, 1.6, 1.6)},
		# Ladle stands either side of the centre mould.
		{"pos": Vector3(-10, 0, 0), "size": Vector3(1.4, 2.0, 1.4)},
		{"pos": Vector3(10, 0, 0), "size": Vector3(1.4, 2.0, 1.4)},
	]


## No sky worth seeing — this is an interior. The starfield is left in place but
## drowned by smoke, so what you actually see overhead is haze lit from below.
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.05, 0.03, 0.03)
	sky_mat.sky_horizon_color = Color(0.22, 0.10, 0.05)
	sky_mat.ground_bottom_color = Color(0.04, 0.02, 0.02)
	sky_mat.ground_horizon_color = Color(0.20, 0.09, 0.04)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.34, 0.16, 0.08)  # furnace bounce
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7   # the channels should bloom
	env.glow_bloom = 0.12
	env.fog_enabled = true
	env.fog_light_color = Color(0.30, 0.14, 0.07)
	# Smoke, but you still have to be able to FIGHT in it: measured at 0.026 the
	# whole map was a flat orange wash with the cover invisible from spawn.
	env.fog_density = 0.010
	env.fog_sky_affect = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_lights() -> void:
	# Weak, cold overhead work lighting — the furnaces do the real lighting.
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-70), deg_to_rad(20), 0)
	key.light_color = Color(0.72, 0.76, 0.88)
	key.light_energy = 0.55
	key.shadow_enabled = true
	add_child(key)
	# The molten bounce, aimed UP from a shallow angle so it catches the
	# undersides and shadow sides the way a floor full of hot metal would.
	var glow := DirectionalLight3D.new()
	glow.rotation = Vector3(deg_to_rad(12), deg_to_rad(-120), 0)
	glow.light_color = Color(1.0, 0.48, 0.16)
	glow.light_energy = 0.75
	glow.light_specular = 0.0
	glow.shadow_enabled = false
	add_child(glow)


func _floor_material() -> Material:
	var mat := ShaderMaterial.new()
	mat.shader = FLOOR_SHADER
	mat.set_shader_parameter("base_col", floor_color)
	mat.set_shader_parameter("seam_col", Color(0.30, 0.13, 0.05))  # heat in the seams
	mat.set_shader_parameter("panels", roundf(size / 2.0))
	return mat


func _decorate() -> void:
	_pour_channels()
	_build_stacks()
	_build_gantry()


## The molten runs, laid in the LANE GAPS rather than under the moulds: the
## quickest ways through the middle are the lit ones, so pushing the centre
## means being visible while you do it. Flat on the deck and unshaded, so they
## read as the brightest thing on the map from any angle.
func _pour_channels() -> void:
	var half := half_extents()
	var runs := [
		# Two long pours down the lane gaps either side of the centre mould.
		Transform3D(Basis(), Vector3(0, 0.02, -7.0)),
		Transform3D(Basis(), Vector3(0, 0.02, 7.0)),
		# A cross-run feeding them from the north wall.
		Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 0.02, 0)),
	]
	Props.batch(self, Props.box(Vector3(3.2, 0.04, 6.0)), runs,
		Props.glow(CHANNEL_COLOR, 2.6), false)
	# Tap-holes at the wall ends of each run, where the metal comes from.
	var taps := []
	for z in [-half.y + 1.2, half.y - 1.2]:
		taps.append(Transform3D(Basis(), Vector3(0, 0.8, z)))
	Props.batch(self, Props.box(Vector3(2.4, 1.6, 0.5)), taps,
		Props.glow(Color(1.0, 0.62, 0.2), 2.0), false)


## Smelting stacks in the four corners: tall, dark, and the thing that tells you
## which end of the map you are looking at. Purely visual — the corners are
## already dead space, so nothing is lost by filling them.
func _build_stacks() -> void:
	var half := half_extents()
	var spots := Props.corners(half, 3.0)
	var bases := []
	var caps := []
	for s in spots:
		var p: Vector3 = s
		bases.append(Transform3D(Basis(), Vector3(p.x, 5.0, p.z)))
		caps.append(Transform3D(Basis(), Vector3(p.x, 10.3, p.z)))
	Props.batch(self, Props.cyl(1.5, 10.0, 8, 1.1), bases, Props.material(IRON, 0.15, 0.6))
	# Hot mouths at the top, so the stacks read as lit from inside.
	Props.batch(self, Props.cyl(1.15, 0.5, 8), caps,
		Props.glow(Color(1.0, 0.35, 0.1), 1.6), false)


## Overhead crane rails spanning the hall. They sit well above head height, so
## they frame the space and cast long shadows across the deck without ever being
## something you bump into.
func _build_gantry() -> void:
	var half := half_extents()
	var beams := []
	for x in [-13.0, 0.0, 13.0]:
		beams.append(Transform3D(Basis(), Vector3(x, 7.5, 0)))
	Props.batch(self, Props.box(Vector3(0.6, 0.5, size)), beams,
		Props.material(IRON, 0.2, 0.55))
	# The rails those beams hang from, running the other way down both walls.
	var rails := []
	for z in [-half.y + 1.0, half.y - 1.0]:
		rails.append(Transform3D(Basis(), Vector3(0, 7.9, z)))
	Props.batch(self, Props.box(Vector3(size, 0.7, 0.8)), rails,
		Props.material(IRON.darkened(0.2), 0.2, 0.55))
