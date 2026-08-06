extends "res://scripts/arena.gd"
## "Crossfire" — a planetside landing zone at night, 50 m square, Concord
## holding the South pads and Automata the North across a central comms bunker.
##
## The lighting is the map's character: it is genuinely dark out here, and what
## you can see is what the floodlight pylons and the pad markings light. The
## four pylons stand in the corners, so the middle of the map is the dimmest
## part of it — pushing the bunker means giving up the light you can see by.

const PAD_COLOR := Color(0.35, 0.72, 1.0)
const LAMP_COLOR := Color(1.0, 0.86, 0.62)
const STEEL := Color(0.22, 0.24, 0.28)


func _configure() -> void:
	size = 50.0
	floor_color = Color(0.15, 0.16, 0.19)   # ferrocrete apron
	wall_color = Color(0.17, 0.19, 0.23)    # blast berm
	cover_color = Color(0.24, 0.26, 0.30)   # bunker plate and cargo
	republic_spawns = [Vector3(-7, 0, -20), Vector3(7, 0, -20)]
	cis_spawns = [Vector3(-7, 0, 20), Vector3(7, 0, 20)]
	cover_boxes = [
		# The comms bunker at mid-field, with two hardpoints beside it.
		{"pos": Vector3(0, 0, 0), "size": Vector3(3.0, 2.2, 3.0)},
		{"pos": Vector3(-5, 0, 3), "size": Vector3(1.6, 1.6, 1.6)},
		{"pos": Vector3(5, 0, -3), "size": Vector3(1.6, 1.6, 1.6)},
		# Revetment walls down the flanks: the two long routes past the bunker.
		{"pos": Vector3(-14, 0, 0), "size": Vector3(2.0, 2.4, 6.0)},
		{"pos": Vector3(14, 0, 0), "size": Vector3(2.0, 2.4, 6.0)},
		# Cargo stacks between the pads and the middle.
		{"pos": Vector3(-6, 0, -10), "size": Vector3(1.4, 1.4, 1.4)},
		{"pos": Vector3(6, 0, -10), "size": Vector3(1.4, 1.4, 1.4)},
		{"pos": Vector3(-6, 0, 10), "size": Vector3(1.4, 1.4, 1.4)},
		{"pos": Vector3(6, 0, 10), "size": Vector3(1.4, 1.4, 1.4)},
		# Blast walls in front of each pad, so a spawn isn't a shooting gallery.
		{"pos": Vector3(0, 0, -14), "size": Vector3(4.0, 1.2, 1.2)},
		{"pos": Vector3(0, 0, 14), "size": Vector3(4.0, 1.2, 1.2)},
	]


## Night, and the starfield is the point of being outdoors — kept, with a thin
## ground haze so the floodlights have something to throw beams through.
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.19, 0.28)  # cold starlight
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.55   # the pad markings and lamps should bloom
	env.glow_bloom = 0.08
	env.fog_enabled = true
	env.fog_light_color = Color(0.10, 0.13, 0.20)
	env.fog_density = 0.012
	env.fog_sky_affect = 0.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_lights() -> void:
	# Moonlight: cold, low and weak. It shapes the geometry without lighting it.
	var moon := DirectionalLight3D.new()
	moon.rotation = Vector3(deg_to_rad(-40), deg_to_rad(35), 0)
	moon.light_color = Color(0.70, 0.78, 1.0)
	moon.light_energy = 0.5
	moon.shadow_enabled = true
	add_child(moon)
	# Warm shadowless fill standing in for the floodlights, from the opposite
	# side so the shadow sides stay readable (GL Compatibility gotcha).
	var flood := DirectionalLight3D.new()
	flood.rotation = Vector3(deg_to_rad(-16), deg_to_rad(-145), 0)
	flood.light_color = LAMP_COLOR
	flood.light_energy = 0.42
	flood.light_specular = 0.0
	flood.shadow_enabled = false
	add_child(flood)


func _decorate() -> void:
	_build_pylons()
	_build_pads()
	_build_mast()


## Floodlight pylons in the four corners: a mast, a head box and a lamp panel.
## Three batches, twelve objects, three draw calls.
func _build_pylons() -> void:
	var spots := Props.corners(half_extents(), 4.0)
	var masts := []
	var heads := []
	var lamps := []
	for s in spots:
		var p: Vector3 = s
		# Heads face the middle, so the map reads as lit inward.
		var yaw := atan2(-p.x, -p.z)
		masts.append(Transform3D(Basis(), Vector3(p.x, 4.0, p.z)))
		heads.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 8.1, p.z)))
		lamps.append(Transform3D(Basis(Vector3.UP, yaw),
			Vector3(p.x, 8.1, p.z) + Vector3(-sin(yaw), -0.25, -cos(yaw)) * 0.62))
	Props.batch(self, Props.cyl(0.22, 8.0, 6), masts, Props.material(STEEL, 0.2, 0.55))
	Props.batch(self, Props.box(Vector3(1.5, 0.9, 1.1)), heads,
		Props.material(STEEL.darkened(0.2), 0.15, 0.6))
	Props.batch(self, Props.box(Vector3(1.25, 0.62, 0.1)), lamps,
		Props.glow(LAMP_COLOR, 3.2), false)


## Landing pad markings painted on the apron behind each team, plus the pad edge
## lights. Flat on the deck, so they light the spawns without blocking them.
func _build_pads() -> void:
	var rings := []
	var lights := []
	for z in [-20.0, 20.0]:
		rings.append(Transform3D(Basis(), Vector3(0, 0.02, z)))
		# Eight edge lights around each pad.
		for i in 8:
			var a := TAU * float(i) / 8.0
			lights.append(Transform3D(Basis(),
				Vector3(cos(a) * 8.5, 0.06, z + sin(a) * 8.5)))
	var ring := TorusMesh.new()
	ring.inner_radius = 7.6
	ring.outer_radius = 8.4
	ring.rings = 24
	ring.ring_segments = 6
	Props.batch(self, ring, rings, Props.glow(PAD_COLOR, 1.0), false)
	Props.batch(self, Props.box(Vector3(0.5, 0.12, 0.5)), lights,
		Props.glow(PAD_COLOR.lightened(0.3), 2.2), false)


## The comms mast the bunker exists to protect: the tallest thing on the map and
## the landmark you orient by from anywhere on it.
func _build_mast() -> void:
	Props.batch(self, Props.cyl(0.28, 13.0, 6),
		[Transform3D(Basis(), Vector3(0, 8.7, 0))], Props.material(STEEL, 0.2, 0.55))
	# Dish and a hazard beacon on top.
	Props.batch(self, Props.cyl(1.7, 0.35, 10),
		[Transform3D(Basis(Vector3.RIGHT, deg_to_rad(35)), Vector3(0, 13.4, 0))],
		Props.material(Color(0.62, 0.64, 0.68), 0.1, 0.5))
	Props.batch(self, Props.ball(0.36, 8),
		[Transform3D(Basis(), Vector3(0, 15.4, 0))],
		Props.glow(Color(1.0, 0.25, 0.2), 3.0), false)
