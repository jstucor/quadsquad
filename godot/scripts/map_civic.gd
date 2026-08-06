extends "res://scripts/arena.gd"
## "CIVIC DISTRICT" — 240 m of city block, and the third of the big maps.
##
## Aridis is open ground with landmarks; Silva is a forest you feel your
## way through. This one is the opposite of both: a REGULAR GRID. Every avenue
## is a straight sight line the length of the map, every junction is four ways
## at once, and the whole thing is legible from the first second because it is a
## grid — which is exactly what makes it tense rather than confusing. You always
## know where you could be shot from; you just cannot watch all of it.
##
## The blocks are deliberately UNEQUAL in size. A perfectly uniform grid plays
## like graph paper: every fight identical, no reason to be anywhere. Mixing
## tower footprints breaks the symmetry and gives the district corners worth
## holding, without touching the readability of the street plan.
##
## Everything tall here is a `cover_box`, so the towers are real geometry: they
## stop bullets, they stamp into the nav grid, and they draw on the map screen.
## The map screen is the point of a grid map — it is the one layout where a
## top-down read genuinely tells you what to do next.

const CONCRETE := Color(0.30, 0.32, 0.38)
const DEEP := Color(0.13, 0.14, 0.18)
const NEON := Color(0.35, 0.72, 1.0)
const SEED := 20260725

## Street plan: block centres on a 4x4 lattice with the middle two removed for a
## plaza. Spacing is the avenue width plus the block width.
const SPACING := 52.0
const AVENUE := 16.0        # clear width of a street
const BLOCK_MIN := 22.0
const BLOCK_MAX := 34.0
const TOWER_MIN := 14.0
const TOWER_MAX := 30.0
const PLAZA_R := 26.0       # the open middle, where the grid is interrupted


func _configure() -> void:
	size = 240.0
	floor_color = Color(0.22, 0.23, 0.27)
	wall_color = Color(0.15, 0.16, 0.20)
	cover_color = CONCRETE
	# Spawns sit on the outer ring road, diagonally opposite, so neither side
	# starts with a straight avenue to the other.
	republic_spawns = [Vector3(-100, 0, -100), Vector3(-100, 0, -78), Vector3(-78, 0, -100)]
	cis_spawns = [Vector3(100, 0, 100), Vector3(100, 0, 78), Vector3(78, 0, 100)]
	cover_boxes = _layout()


func _layout() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var out: Array = []
	for gx in 5:
		for gz in 5:
			var at := Vector2((gx - 2) * SPACING, (gz - 2) * SPACING)
			# The plaza: no tower in the middle, so the centre is a place to
			# fight over rather than a building to walk around.
			if at.length() < PLAZA_R:
				continue
			var w := rng.randf_range(BLOCK_MIN, BLOCK_MAX)
			var d := rng.randf_range(BLOCK_MIN, BLOCK_MAX)
			var h := rng.randf_range(TOWER_MIN, TOWER_MAX)
			out.append({"pos": Vector3(at.x, 0.0, at.y), "size": Vector3(w, h, d)})
			# A low annex against one face: cover in the street itself, so an
			# avenue is not a pure shooting gallery.
			var side := rng.randi_range(0, 3)
			var off := Vector3(
				(w * 0.5 + 3.0) * (1.0 if side == 0 else (-1.0 if side == 1 else 0.0)),
				0.0,
				(d * 0.5 + 3.0) * (1.0 if side == 2 else (-1.0 if side == 3 else 0.0)))
			out.append({"pos": Vector3(at.x, 0.0, at.y) + off,
				"size": Vector3(6.0, 2.6, 6.0)})
	# The plaza's own cover: a ring of low barriers, so crossing it is possible.
	for i in 8:
		var a := TAU * float(i) / 8.0 + 0.3
		out.append({"pos": Vector3(cos(a) * 15.0, 0.0, sin(a) * 15.0),
			"size": Vector3(5.0, 1.5, 1.6) if i % 2 == 0 else Vector3(1.6, 1.5, 5.0)})
	# ...and a raised speaker's dais at the very centre: high ground worth ten
	# metres of exposure to reach.
	out.append({"pos": Vector3(0, 0, 0), "size": Vector3(9.0, 3.2, 9.0)})
	return out


## Night, lit by the city itself. Dark on purpose: on a pale map every player
## washes into the ground (see the Relay note), and a district of grey concrete
## is exactly that map unless the ambient is held right down and the light
## comes from coloured sources.
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.20, 0.26, 0.38)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.55      # the neon is the look; let it bloom
	env.glow_bloom = 0.10
	env.fog_enabled = true
	env.fog_light_color = Color(0.10, 0.14, 0.22)
	# Thin. A 240 m map with real fog loses its far towers, and the towers are
	# how you navigate a grid (Foundry's 0.026 wash is the warning here).
	env.fog_density = 0.0075
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_lights() -> void:
	var key := DirectionalLight3D.new()
	key.light_color = Color(0.62, 0.72, 1.0)   # cold moonlight down the avenues
	key.light_energy = 0.85
	key.rotation_degrees = Vector3(-58.0, 28.0, 0.0)
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 80.0   # see the Silva note
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.9, 0.55, 0.35)  # warm bounce off the city
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-12.0, -150.0, 0.0)
	fill.shadow_enabled = false
	fill.light_specular = 0.0
	add_child(fill)


## Neon banding on the towers and lamp posts down the streets, all batched and
## none of it colliding. Emissive strips do the navigation work that a landmark
## does on the other big maps: from anywhere you can see which block is which.
func _decorate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 1
	var strips: Array = []
	var lamps: Array = []
	for spec in cover_boxes:
		var s: Vector3 = spec["size"]
		if s.y < TOWER_MIN:
			continue   # annexes and plaza barriers get none
		var p: Vector3 = spec["pos"]
		# Two bands per tower, at heights that vary so the skyline is not striped.
		for band in 2:
			var y := rng.randf_range(6.0, s.y - 3.0)
			strips.append(Transform3D(Basis.IDENTITY.scaled(
				Vector3(s.x * 1.01, 0.6, s.z * 1.01)), Vector3(p.x, y, p.z)))
	for gx in 6:
		for gz in 6:
			var at := Vector3((gx - 2.5) * SPACING * 0.86, 0.0, (gz - 2.5) * SPACING * 0.86)
			if Vector2(at.x, at.z).length() < PLAZA_R * 0.6:
				continue
			lamps.append(Transform3D(Basis.IDENTITY, at + Vector3(0.0, 3.0, 0.0)))
	Props.batch(self, Props.box(Vector3.ONE), strips, Props.glow(NEON, 2.2), false)
	Props.batch(self, Props.box(Vector3(0.4, 6.0, 0.4)), lamps,
		Props.material(DEEP, 0.1, 0.5), false)
