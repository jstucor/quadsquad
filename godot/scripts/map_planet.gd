class_name PlanetMap
extends Arena
## PROCEDURAL WORLDS — one generator, five planets, a new layout every match.
##
## `GameState.planet` picks which world to build (or rolls one); the seed comes
## off the clock, so the same planet is a different map every time you drop into
## it. A planet is a TABLE ROW (see PLANETS): a palette, a sky, a sun, a terrain
## profile, and which structure generator lays out its landmarks. Adding a sixth
## world is a row and a `_lay_*` function, not a new map script.
##
## ---------------------------------------------------------------------------
## THE ONE RULE THAT SHAPES EVERYTHING ELSE: TERRAIN IS ALWAYS WALKABLE.
##
## The AI's nav grid is stamped from BOX COLLIDERS only (GameState.map_shapes —
## the same scan the map screen draws from). Terrain is a trimesh and is invisible
## to it. So if the heightfield were allowed to make cliffs, bots would path
## straight into them and stand there for the rest of the match.
##
## Therefore the split, and every planet obeys it:
##   TERRAIN   gentle, rolling, walkable everywhere. It carries the LOOK.
##   STRUCTURES  box colliders. Mesas, towers, trunks, ice walls. They carry the
##               scale, the cover and the routing — and because they are boxes,
##               the nav grid, the map screen and `cover_boxes` all understand
##               them for free.
##
## That is not a compromise: it is why a generated map is playable at all without
## a navmesh bake, and it is the same reason the hand-authored maps put their
## real cover in `cover_boxes` and their decoration in `Props.batch`.
## ---------------------------------------------------------------------------
##
## Slope budget: the height function is a sum of sines, so its gradient is exact
## and bounded — every octave contributes at most `amp * freq`, and the sum of
## those is held under MAX_GRADIENT. That is an arithmetic guarantee, not a
## tuning exercise (the same argument map_highridge makes for its hill).

## Named apart from Arena's own GROUND_SHADER/SKY_SHADER, which this inherits.
const PLANET_GROUND := preload("res://shaders/planet_ground.gdshader")
const PLANET_SKY := preload("res://shaders/planet_sky.gdshader")

enum Planet { GEONOSIS, KASHYYYK, CORUSCANT, MUSTAFAR, HOTH }
const PLANET_NAMES := {
	Planet.GEONOSIS: "GEONOSIS", Planet.KASHYYYK: "KASHYYYK",
	Planet.CORUSCANT: "CORUSCANT", Planet.MUSTAFAR: "MUSTAFAR",
	Planet.HOTH: "HOTH",
}

## Walkable slope ceiling as a gradient (rise over run). 0.50 is 26.6 degrees,
## comfortably inside what a CharacterBody3D climbs, and the terrain octaves are
## normalised so their summed gradient cannot exceed it.
const MAX_GRADIENT := 0.50
const CELL := 2.2              # heightfield resolution, metres
const GROUND_LIFT := 0.9       # props sit this far above the analytic surface
## The narrowest a solid may be and still be seen by the nav grid, which stamps a
## cell when an obstacle reaches its CENTRE. On a ~290 m map the cell spacing is
## at the coarse end of NavGrid's range.
const NAV_MIN_WIDTH := 4.0
## `height_at` is the ANALYTIC surface; the collider is a MESH sampled on CELL,
## and across a hollow its flat triangles sit ABOVE the curve. Anything placed at
## exactly height_at can start inside the ground. Same trap, same fix, as
## GameState.SPAWN_LIFT — and it scales with CELL, not with the body.

## Each planet: what it looks like, what the sun does, and how it is built.
##
## `octaves` are [wavelength_m, amplitude_m] pairs. Long wavelengths make the
## broad landform, short ones the detail; the generator normalises them against
## MAX_GRADIENT so any combination stays walkable.
const PLANETS := {
	Planet.GEONOSIS: {
		"blurb": "Red rock and wind-cut spires over a baked hardpan",
		"size": 300.0,
		"octaves": [[110.0, 7.0], [46.0, 2.6], [17.0, 0.8]],
		"ground": {
			"low_col": Color(0.52, 0.28, 0.17), "mid_col": Color(0.74, 0.45, 0.26),
			"high_col": Color(0.90, 0.66, 0.42), "rock_col": Color(0.56, 0.31, 0.20),
			"under_col": Color(0.14, 0.07, 0.05), "height_hi": 16.0,
			"rock_bias": 0.10, "world_scale": 0.05, "rough_flat": 0.95,
		},
		"sky": {
			"zenith_col": Color(0.30, 0.20, 0.22), "horizon_col": Color(0.86, 0.55, 0.34),
			"sun_col": Color(1.0, 0.82, 0.55), "cloud_col": Color(0.72, 0.46, 0.32),
			"cloud_amount": 0.30, "horizon_falloff": 2.2,
		},
		"sun": {"angle": Vector2(-46.0, 40.0), "color": Color(1.0, 0.86, 0.66),
			"energy": 1.35},
		"fog": {"color": Color(0.62, 0.36, 0.22), "density": 0.0030},
		"ambient": Color(0.42, 0.26, 0.20),
		"volumetric": 0.0018,
		"exposure": 1.45,
		"lay": "spires",
	},
	Planet.KASHYYYK: {
		"blurb": "Wroshyr giants over a shaded forest floor",
		"size": 280.0,
		"octaves": [[120.0, 5.0], [52.0, 2.2], [19.0, 0.7]],
		"ground": {
			"low_col": Color(0.76, 0.68, 0.48), "mid_col": Color(0.30, 0.46, 0.19),
			"high_col": Color(0.52, 0.58, 0.28), "rock_col": Color(0.40, 0.37, 0.30),
			"under_col": Color(0.06, 0.09, 0.06), "height_hi": 12.0,
			"world_scale": 0.06, "rough_flat": 0.96,
		},
		"sky": {
			"zenith_col": Color(0.20, 0.36, 0.44), "horizon_col": Color(0.68, 0.78, 0.66),
			"sun_col": Color(1.0, 0.97, 0.82), "cloud_col": Color(0.80, 0.86, 0.78),
			"cloud_amount": 0.45, "horizon_falloff": 3.0,
		},
		"sun": {"angle": Vector2(-58.0, 25.0), "color": Color(1.0, 0.96, 0.82),
			"energy": 1.30},
		"fog": {"color": Color(0.30, 0.45, 0.32), "density": 0.0042},
		"ambient": Color(0.24, 0.34, 0.26),
		"volumetric": 0.0030,
		"exposure": 1.55,
		"lay": "forest",
	},
	Planet.CORUSCANT: {
		"blurb": "Rooftops and canyons of an endless city, at dusk",
		"size": 290.0,
		# Almost flat: this is a rooftop plain, and its relief comes entirely
		# from the towers standing on it.
		"octaves": [[140.0, 1.6], [58.0, 0.7]],
		"ground": {
			"low_col": Color(0.13, 0.14, 0.18), "mid_col": Color(0.19, 0.20, 0.25),
			"high_col": Color(0.27, 0.29, 0.35), "rock_col": Color(0.17, 0.18, 0.23),
			"under_col": Color(0.07, 0.07, 0.09), "height_hi": 6.0,
			"world_scale": 0.09, "rough_flat": 0.6, "rough_rock": 0.45,
			"vein_col": Color(1.0, 0.72, 0.30), "vein_amount": 0.22, "vein_sharp": 34.0,
		},
		"sky": {
			"zenith_col": Color(0.06, 0.08, 0.20), "horizon_col": Color(0.60, 0.42, 0.52),
			"sun_col": Color(1.0, 0.66, 0.42), "cloud_col": Color(0.32, 0.28, 0.42),
			"glow_col": Color(1.0, 0.70, 0.35), "glow_amount": 0.85,
			"cloud_amount": 0.40, "horizon_falloff": 2.6, "stars": 0.55,
		},
		"sun": {"angle": Vector2(-34.0, 62.0), "color": Color(1.0, 0.74, 0.52),
			"energy": 1.15},
		"fog": {"color": Color(0.34, 0.28, 0.40), "density": 0.0038},
		"ambient": Color(0.26, 0.24, 0.36),
		"volumetric": 0.0026,
		"exposure": 1.60,
		"lay": "city",
	},
	Planet.MUSTAFAR: {
		"blurb": "Obsidian flats split by molten rivers, under an ash sky",
		"size": 270.0,
		"octaves": [[100.0, 6.0], [42.0, 2.4], [16.0, 0.9]],
		"ground": {
			"low_col": Color(0.17, 0.14, 0.13), "mid_col": Color(0.27, 0.22, 0.20),
			"high_col": Color(0.41, 0.33, 0.29), "rock_col": Color(0.22, 0.18, 0.17),
			"under_col": Color(0.05, 0.04, 0.04), "height_hi": 14.0,
			"rock_bias": 0.16, "world_scale": 0.055, "rough_flat": 0.78,
			"vein_col": Color(1.0, 0.34, 0.06), "vein_amount": 0.60, "vein_sharp": 16.0,
		},
		"sky": {
			"zenith_col": Color(0.10, 0.05, 0.05), "horizon_col": Color(0.48, 0.16, 0.07),
			"sun_col": Color(1.0, 0.45, 0.20), "cloud_col": Color(0.26, 0.14, 0.12),
			"glow_col": Color(1.0, 0.32, 0.06), "glow_amount": 1.25,
			"cloud_amount": 0.70, "horizon_falloff": 2.0,
		},
		"sun": {"angle": Vector2(-40.0, -35.0), "color": Color(1.0, 0.60, 0.34),
			"energy": 1.05},
		"fog": {"color": Color(0.38, 0.14, 0.07), "density": 0.0052},
		"ambient": Color(0.34, 0.16, 0.11),
		"volumetric": 0.0052,
		"exposure": 1.55,
		"lay": "foundry",
	},
	Planet.HOTH: {
		"blurb": "Drifts and ice ridges under a thin white sun",
		"size": 285.0,
		"octaves": [[125.0, 11.0], [50.0, 4.2], [18.0, 0.9]],
		"ground": {
			"low_col": Color(0.55, 0.62, 0.72), "mid_col": Color(0.74, 0.80, 0.88),
			"high_col": Color(0.90, 0.94, 1.0), "rock_col": Color(0.30, 0.33, 0.40),
			"under_col": Color(0.20, 0.26, 0.34), "height_hi": 15.0,
			"rock_bias": -0.10, "world_scale": 0.04, "rough_flat": 0.72,
			"sparkle": 0.55,
		},
		"sky": {
			"zenith_col": Color(0.34, 0.46, 0.64), "horizon_col": Color(0.86, 0.90, 0.96),
			"sun_col": Color(0.92, 0.96, 1.0), "cloud_col": Color(0.90, 0.93, 0.98),
			"cloud_amount": 0.62, "horizon_falloff": 3.4, "sun_halo": 4.0,
		},
		"sun": {"angle": Vector2(-44.0, 130.0), "color": Color(0.92, 0.96, 1.0),
			"energy": 1.45},
		"fog": {"color": Color(0.72, 0.79, 0.88), "density": 0.0034},
		"ambient": Color(0.46, 0.54, 0.66),
		"volumetric": 0.0060,
		# SNOW IS ALREADY THE BRIGHTEST ALBEDO in the game — lighting it at the
		# exposure the other worlds want puts the whole map at the top of the
		# curve, where every value collapses into white and the map stops having
		# a picture in it. This is the one planet that wants LESS.
		"exposure": 1.02,
		"lay": "glacier",
	},
}

var planet := Planet.GEONOSIS
var _rng := RandomNumberGenerator.new()
## The terrain octaves, resolved to [freq_rad_per_m, amplitude, phase_x, phase_z]
## and normalised against the slope budget. Built once in _configure.
var _octaves: Array = []
## Every structure footprint laid down so far, as {c: Vector2, r: float}. Used to
## keep towers off each other and off the spawns.
var _claims: Array = []
## Cached shade set for this planet's rock, built on first use.
var _rock_shades: Array = []
## SURFACE DETAIL, collected during layout and emitted as two MultiMeshes at the
## end. `_detail` is structural (mullions, ribs, machinery, drifts), `_lit` is
## emissive (windows, embrasures, warning lamps).
##
## Greebling is THE thing that makes box architecture read as built rather than
## blocked out, and it is what the ILM model shop did for exactly this reason: a
## flat face has no scale, and the moment you put small repeated shapes on it the
## eye reads the whole object as large. None of it collides — it is surface, and
## the project rule is that decoration never quietly becomes a wall.
var _detail: Array = []
var _lit: Array = []
## ...and a PALE batch, for snow drifted against structures. Its own list rather
## than a flag on the others because it needs a different material: drift snow is
## the brightest thing on Hoth and the structural greebles are the darkest.
var _pale: Array = []


func _configure() -> void:
	planet = GameState.chosen_planet()
	var p: Dictionary = PLANETS[planet]
	_rng.seed = GameState.planet_seed
	size = p["size"]
	depth = p["size"]
	grade_exposure = p.get("exposure", Grade.EXPOSURE)
	floor_color = p["ground"]["mid_col"]
	wall_color = p["ground"]["rock_col"]
	cover_color = p["ground"]["rock_col"]
	_build_octaves(p["octaves"])

	var half := size * 0.5
	# Opposite edges, inset, and clear of the middle where the landmarks go.
	republic_spawns = _spawn_line(-half * 0.82)
	cis_spawns = _spawn_line(half * 0.82)
	for s in republic_spawns + cis_spawns:
		_claims.append({"c": Vector2(s.x, s.z), "r": 26.0})


## Three markers across one end, sat on the terrain.
func _spawn_line(x: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for k in 3:
		var z := (k - 1) * size * 0.16
		out.append(Vector3(x, height_at(x, z) + GameState.SPAWN_LIFT, z))
	return out


## Resolve the octave table into something height_at can sum fast, and scale it
## so the WORST-CASE combined gradient is inside MAX_GRADIENT.
##
## Each octave contributes at most `amp * freq` to the slope (the derivative of
## a sine is bounded by its amplitude times its frequency), so the worst case is
## just the sum of those. Scaling all amplitudes by one factor keeps the shape
## and guarantees the budget — which is why this is arithmetic rather than
## something to tune by walking around and finding out.
func _build_octaves(table: Array) -> void:
	_octaves.clear()
	var worst := 0.0
	for row in table:
		var freq: float = TAU / float(row[0])
		var amp: float = float(row[1])
		_octaves.append([freq, amp, _rng.randf() * TAU, _rng.randf() * TAU])
		worst += amp * freq
	if worst > MAX_GRADIENT:
		var k := MAX_GRADIENT / worst
		for o in _octaves:
			o[1] *= k


## Ground height at a world XZ. The single source of truth: the mesh, its
## collider, every structure's footing and every prop read this.
## LIFTED so the lowest ground sits at y = 0, never below it.
##
## Not cosmetic. `GameState.scan_map_geometry` skips any box whose TOP is at or
## below MAP_FLOOR_TOP (0.05) — that is how it throws away a map's floor slab.
## With terrain running to -5 m, every structure standing in a hollow had its top
## below zero and was silently dropped from the scan: invisible to the nav grid
## and to the map screen, while physics still collided with it. That is exactly
## "routes pass through real geometry", and it depended on where the generator
## happened to drop things, which is why it failed by SEED.
##
## Everything else — the sea, every footing, every prop — is derived from this
## function, so lifting it here moves all of them together.
func height_at(x: float, z: float) -> float:
	var h := 0.0
	for o in _octaves:
		h += o[1] * sin(x * o[0] + o[2]) * cos(z * o[0] + o[3])
	return h + terrain_amplitude()


## The exact gradient magnitude, from the analytic derivative. Handed to the
## ground shader as vertex colour so it can put rock on the steep faces without
## reconstructing anything from an interpolated normal.
func steepness_at(x: float, z: float) -> float:
	var dx := 0.0
	var dz := 0.0
	for o in _octaves:
		dx += o[1] * o[0] * cos(x * o[0] + o[2]) * cos(z * o[0] + o[3])
		dz += -o[1] * o[0] * sin(x * o[0] + o[2]) * sin(z * o[0] + o[3])
	return clampf(Vector2(dx, dz).length() / MAX_GRADIENT, 0.0, 1.0)


# --- build order --------------------------------------------------------------

func _build_floor() -> void:
	_build_terrain()


func _build_walls() -> void:
	# No boundary box. These worlds are meant to read as open ground running to
	# a horizon, and a six-metre wall around a 300 m plain is the one thing that
	# would say "arena" loudest. The playable area is fenced by structures and by
	# the storm/score rules instead.
	pass


func _decorate() -> void:
	var p: Dictionary = PLANETS[planet]
	match p["lay"]:
		"spires": _lay_spires()
		"forest": _lay_forest()
		"city": _lay_city()
		"foundry": _lay_foundry()
		"glacier": _lay_glacier()
	_scatter_rubble()
	_build_backdrop()
	_flush_detail(p["ground"]["rock_col"].lerp(Color.BLACK, 0.35),
		p.get("lit", Color(1.0, 0.78, 0.42)))


# --- terrain ------------------------------------------------------------------

## One heightfield mesh plus its trimesh collider. Vertex colour carries the
## exact slope; UV carries world XZ so the shader's noise is world-locked and
## does not swim when the map size changes.
func _build_terrain() -> void:
	var half := size * 0.5
	var cols := int(size / CELL)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in cols:
		for j in cols:
			var x0 := -half + i * CELL
			var z0 := -half + j * CELL
			var x1 := x0 + CELL
			var z1 := z0 + CELL
			_quad(st,
				Vector3(x0, height_at(x0, z0), z0),
				Vector3(x1, height_at(x1, z0), z0),
				Vector3(x1, height_at(x1, z1), z1),
				Vector3(x0, height_at(x0, z1), z1))
	st.generate_normals()
	st.generate_tangents()
	var mesh := st.commit()

	var body := StaticBody3D.new()
	body.name = "Terrain"
	# Layer 1 (world) so shots, feet and the map scan all see it. It is a
	# trimesh, so the map screen's box-only scan skips it — which is correct:
	# the screen should draw the structures, not a contour map.
	body.collision_layer = 1
	add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _ground_material()
	body.add_child(mi)

	var shape := CollisionShape3D.new()
	var tri := ConcavePolygonShape3D.new()
	tri.set_faces(mesh.get_faces())
	# A ConcavePolygonShape3D only collides on ONE side by default, and it is
	# not the side the normals face — terrain silently lets everything through.
	# It also stops anything launched under the map drifting up through it.
	tri.backface_collision = true
	shape.shape = tri
	body.add_child(shape)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	# WINDING: a, b, c / a, c, d. Getting this backwards is why the ground was
	# dark through several rounds of "the palette must be wrong" — with the
	# normals pointing DOWN the sun never touched the terrain at all and it was
	# lit by ambient alone. A white test surface still rendering at 0.30 is what
	# finally isolated it: no albedo change can fix a surface facing away from
	# the light. Flipping the order took the same ground from 0.27 to 0.76.
	for v: Vector3 in [a, b, c, a, c, d]:
		st.set_color(Color(steepness_at(v.x, v.z), 0.0, 0.0))
		st.set_uv(Vector2(v.x, v.z))
		st.add_vertex(v)


func _ground_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PLANET_GROUND
	for key in PLANETS[planet]["ground"]:
		mat.set_shader_parameter(key, PLANETS[planet]["ground"][key])
	# THE HEIGHT BANDS MUST COME FROM THE TERRAIN, not from the table.
	#
	# They were authored independently (height_hi 16 m) while the generator
	# normalises its octaves against the slope budget and actually produces about
	# +/-5 m. So the whole map sat in the bottom third of the first band, half of
	# it clamped flat at the lowest colour, and every world rendered as one dark
	# muddy tone with none of its palette visible. Ask the terrain what range it
	# spans and hand the shader that.
	# 0 .. 2*amp, matching the lift in height_at.
	var amp := terrain_amplitude()
	mat.set_shader_parameter("height_lo", 0.0)
	mat.set_shader_parameter("height_hi", amp * 2.0)
	return mat


## The half-range the height function can actually reach: the sum of the octave
## amplitudes, after the slope normalisation has scaled them.
func terrain_amplitude() -> float:
	var a := 0.0
	for o in _octaves:
		a += o[1]
	return maxf(a, 0.5)


func _floor_material() -> Material:
	return _ground_material()


# --- environment --------------------------------------------------------------

func _build_environment() -> void:
	var p: Dictionary = PLANETS[planet]
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = PLANET_SKY
	for key in p["sky"]:
		sky_mat.set_shader_parameter(key, p["sky"][key])
	sky_mat.set_shader_parameter("sun_dir", _sun_dir())
	sky.sky_material = sky_mat
	env.sky = sky
	# The grade blends this with the sky (Grade.SKY_AMBIENT); the authored colour
	# is the floor under it, and on these worlds it is doing most of the work in
	# the shadows.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = p["ambient"]
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.fog_enabled = true
	env.fog_light_color = p["fog"]["color"]
	env.fog_density = p["fog"]["density"]
	env.fog_sky_affect = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


## The sun's direction as a unit vector, from the planet's authored angles. The
## sky shader needs it to put the disc in the right place, and the disc has to
## agree with where the shadows say the sun is.
func _sun_dir() -> Vector3:
	var a: Vector2 = PLANETS[planet]["sun"]["angle"]
	var basis := Basis.from_euler(Vector3(deg_to_rad(a.x), deg_to_rad(a.y), 0.0))
	return -(basis * Vector3.FORWARD).normalized() * -1.0


## Weather is a per-planet number: Mustafar's ash and Hoth's blizzard are thick,
## Geonosis's dust is thin, and volumetric density is sensitive enough that one
## value for all five is one value wrong for four of them.
func _grade() -> void:
	Grade.apply_to(self, grade_exposure,
		PLANETS[planet].get("volumetric", Grade.VOLUMETRIC_DENSITY))


func _build_lights() -> void:
	var p: Dictionary = PLANETS[planet]["sun"]
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(p["angle"].x), deg_to_rad(p["angle"].y), 0.0)
	key.light_color = p["color"]
	key.light_energy = p["energy"]
	key.shadow_enabled = true
	add_child(key)
	# A dim shadowless fill from the opposite side. Without it the shadow faces
	# of a 90 m tower go to a flat silhouette, which is the one thing that makes
	# big geometry read as a cardboard cut-out.
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-18.0), deg_to_rad(p["angle"].y + 165.0), 0.0)
	fill.light_color = PLANETS[planet]["ambient"]
	fill.light_energy = 0.45
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	add_child(fill)


# --- placement ----------------------------------------------------------------

## A solid box: mesh + collider on the WORLD layer.
##
## Everything impassable on these maps goes through here, and that is the whole
## trick. A box collider on layer 1 is understood by the nav grid, by the map
## screen's geometry scan and by every sight check in the game — none of which
## read the terrain trimesh. Generated cover is therefore exactly as legible to
## the AI as a hand-authored map's.
## WHAT A STRUCTURE LOOKS LIKE is independent of what it collides as.
##
## The collider has to stay a BOX — the nav grid, the map screen and the cover
## logic all read boxes, and that is the whole reason a generated map is
## navigable without a bake. But nothing requires the MESH to be the same shape,
## and a world built only from cubes and rectangles reads as a blockout however
## well it is lit. So the shape is a free choice on top of a box footprint.
enum Shape { BOX, COLUMN, CONE, WEDGE, CRAG }


func _solid(centre: Vector3, box: Vector3, mat: Material, yaw := 0.0,
		shape := Shape.BOX, sides := 6) -> void:
	# THE MINIMUM IS ENFORCED HERE, not at the call sites.
	#
	# The nav grid stamps a cell solid when an obstacle reaches its CENTRE, so
	# anything thinner than the cell spacing falls between two centres and A*
	# routes bots straight through it. Clamping in the callers was not enough and
	# was not even wrong in an obvious way — `_stack` clamped its width but let
	# depth vary down to 0.82 of it, and low cover never clamped at all. The
	# result was a nav test that passed or failed depending on the seed, which is
	# luck rather than a fix. One clamp, on the way in, cannot be forgotten.
	box = Vector3(maxf(box.x, NAV_MIN_WIDTH), box.y, maxf(box.z, NAV_MIN_WIDTH))
	var body := StaticBody3D.new()
	body.position = centre
	body.rotation.y = yaw
	body.collision_layer = 1
	add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = _shape_mesh(shape, box, sides)
	mi.material_override = mat
	body.add_child(mi)
	# The COLLIDER is always a box, whatever the mesh is: the nav grid, the map
	# screen and the cover logic all read boxes.
	var cs := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = box
	cs.shape = hull
	body.add_child(cs)


## Decoration only — no collider, drawn as part of a MultiMesh batch by the
## caller. Used for anything beyond the play area and anything too small to
## matter, per the project rule that decoration must never quietly become a wall.
## The mesh for a shape, sized to the box it stands in. Cylinders with unequal
## radii give cones and tapered columns; a low `sides` count gives the faceted,
## fractured look rock and ice actually have, and costs fewer triangles than the
## smooth version rather than more.
func _shape_mesh(shape: int, box: Vector3, sides: int) -> Mesh:
	match shape:
		Shape.COLUMN:
			var c := CylinderMesh.new()
			c.top_radius = box.x * 0.5
			c.bottom_radius = box.x * 0.52
			c.height = box.y
			c.radial_segments = sides
			c.rings = 1
			return c
		Shape.CONE:
			var c := CylinderMesh.new()
			# A spire, not a party hat: it narrows hard but never to a point,
			# because a true apex reads as a cone dropped on the map where a
			# broken-off tip reads as rock.
			c.top_radius = box.x * 0.16
			c.bottom_radius = box.x * 0.5
			c.height = box.y
			c.radial_segments = sides
			c.rings = 1
			return c
		Shape.WEDGE:
			var pm := PrismMesh.new()
			pm.size = box
			pm.left_to_right = 0.32   # off-centre ridge: a slab, not a tent
			return pm
		Shape.CRAG:
			var sp := SphereMesh.new()
			sp.radius = box.x * 0.5
			sp.height = box.y
			sp.radial_segments = 6    # faceted on purpose — this is a boulder
			sp.rings = 3
			return sp
	var bm := BoxMesh.new()
	bm.size = box
	return bm


## Add a non-colliding surface box. Batched, so a tower can carry ninety of them.
func _greeble(centre: Vector3, box: Vector3, yaw := 0.0) -> void:
	_detail.append(_ghost(centre, box, yaw))


## ...and one that emits light of its own.
func _lamp(centre: Vector3, box: Vector3, yaw := 0.0) -> void:
	_lit.append(_ghost(centre, box, yaw))


## Emit everything collected. Two draw calls for the whole map's surface detail.
func _flush_detail(detail: Color, lit: Color) -> void:
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	if not _detail.is_empty():
		Props.batch(self, unit, _detail, _mat(detail, 0.7, 0.2), true)
	if not _lit.is_empty():
		Props.batch(self, unit, _lit, Props.glow(lit, 2.2), false)
	if not _pale.is_empty():
		# A wedge, not a box: drifted snow has a windward slope, and that slope is
		# the whole reason a drift reads as snow rather than as a white crate.
		var wedge := PrismMesh.new()
		wedge.size = Vector3.ONE
		wedge.left_to_right = 0.25
		Props.batch(self, wedge, _pale, _mat(PLANETS[planet]["ground"]["high_col"],
			0.75), true)
	_detail.clear()
	_lit.clear()
	_pale.clear()


## Snow (or dust, or ash) piled against something.
func _drift(centre: Vector3, box: Vector3, yaw := 0.0) -> void:
	_pale.append(_ghost(centre, box, yaw))


func _ghost(centre: Vector3, box: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(box), centre)


## Is this spot clear of everything claimed so far? Keeps towers off each other,
## off the spawns and out of the middle lane.
func _free(at: Vector2, radius: float) -> bool:
	for c in _claims:
		if at.distance_to(c["c"]) < radius + c["r"]:
			return false
	return true


func _claim(at: Vector2, radius: float) -> void:
	_claims.append({"c": at, "r": radius})


## Find a spot for something of `radius`, inside `reach` of the middle. Gives up
## rather than looping forever — a full map is a fine reason to place fewer
## towers, and a generator that can hang is worse than a sparse one.
func _find_spot(radius: float, reach: float) -> Vector2:
	for _try in 40:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * reach
		var at := Vector2(cos(a), sin(a)) * r
		if _free(at, radius):
			_claim(at, radius)
			return at
	return Vector2.INF


func _mat(colour: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := Props.material(colour, metal, rough)
	m.rim_enabled = true
	m.rim = 0.3
	m.rim_tint = 0.4
	return m


## A SPREAD of materials around one colour, light to dark.
##
## Everything on a planet sharing a single albedo is what made the first pass
## read as one moulded lump: hue alone does not separate objects, VALUE does, and
## a field of identical mid-tone boxes has none of it. Four steps is enough to
## break a skyline up and is still four materials, not four hundred.
func _shades(colour: Color, rough := 0.85, metal := 0.0) -> Array:
	var out := []
	for k in 4:
		var f := 0.62 + k * 0.20              # 0.62 .. 1.22 of the base value
		out.append(_mat(Color(colour.r * f, colour.g * f, colour.b * f).clamp(),
			rough, metal))
	return out


## One of a shade set, picked at random. Called per STRUCTURE, not per box, so a
## single spire is one colour and the FIELD of them is varied.
func _shade(set: Array) -> Material:
	return set[_rng.randi() % set.size()]


## A TAPERED STACK — the difference between a landmark and a crate.
##
## One box scaled to 80 m is a slab; the eye reads it as a texture-less wall and
## the scale goes with it. The same volume built as four boxes, each a little
## narrower and rotated a few degrees off the last, reads as a structure: it has
## a silhouette that changes with height, it catches the light differently at
## each step, and it throws a broken shadow instead of a rectangle.
func _stack(at: Vector2, base_w: float, total_h: float, steps: int,
		mat: Material, taper := 0.72, jitter := 0.12, shape := Shape.BOX,
		sides := 6) -> void:
	var ground := height_at(at.x, at.y)
	var y := ground - 2.0          # bury the foot so it never floats on a slope
	var w := base_w
	for i in steps:
		var h := total_h / float(steps) * _rng.randf_range(0.85, 1.2)
		var off := Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) \
			* base_w * jitter
		_solid(Vector3(at.x + off.x, y + h * 0.5, at.y + off.y),
			Vector3(w, h, w * _rng.randf_range(0.82, 1.18)),
			mat, _rng.randf() * TAU, shape, sides)
		y += h
		# Never narrower than the nav grid can see. A five-step taper at 0.62
		# leaves the top step at 15% of the base — under two metres — and a box
		# thinner than the cell spacing falls between two cell centres, so A*
		# routes straight through it. tests/nav_grid catches exactly that.
		w = maxf(w * taper, NAV_MIN_WIDTH)


# --- the five layouts ----------------------------------------------------------

## GEONOSIS: wind-cut spires. Tall, thin, heavily tapered — the silhouette is
## the map, and the gaps between them are the lanes.
func _lay_spires() -> void:
	var stone := _shades(Color(0.60, 0.31, 0.19), 0.95)
	var reach := size * 0.40
	for i in 26:
		var at := _find_spot(11.0, reach)
		if at == Vector2.INF:
			continue
		var tall := _rng.randf() < 0.45
		# Low jitter: at 0.16 each step slid far enough off the last that a spire
		# read as a drunk stack of crates. A wind-cut spire is near-vertical; the
		# TAPER is what makes it a spire, not the wobble.
		_stack(at, _rng.randf_range(9.0, 15.0),
			_rng.randf_range(38.0, 82.0) if tall else _rng.randf_range(12.0, 24.0),
			5 if tall else 3, _shade(stone), 0.62, 0.05,
			Shape.CONE if tall else Shape.COLUMN, _rng.randi_range(5, 7))
	# Massifs between the spires, so the skyline has weight as well as height.
	for i in 5:
		var at := _find_spot(30.0, size * 0.36)
		if at != Vector2.INF:
			_mountain(at, _rng.randf_range(38.0, 58.0), _rng.randf_range(26.0, 44.0))
	# ...and caves bored through their feet, which is what makes a massif
	# something to fight THROUGH rather than an obstacle to walk around.
	for i in 4:
		var at := _find_spot(15.0, size * 0.34)
		if at != Vector2.INF:
			_cave(at, _rng.randf() * TAU, _rng.randf_range(18.0, 30.0))
	_low_cover(_shade(stone), 22)


## KASHYYYK: wroshyr trunks. Enormous, near-vertical, and close enough together
## that the trunks themselves are the cover — the same idea the hand-authored
## Kashyyyk uses, generated.
func _lay_forest() -> void:
	var barks := _shades(Color(0.30, 0.21, 0.13), 0.96)
	var bark: Material = _shade(barks)
	var reach := size * 0.42
	for i in 22:
		var at := _find_spot(19.0, reach)
		if at == Vector2.INF:
			continue
		bark = _shade(barks)
		# THICK. A wroshyr is a building, not a tree: at 6-10 m across these read
		# as telegraph poles from any distance, and the canopy above them had
		# nothing plausible holding it up.
		_stack(at, _rng.randf_range(11.0, 18.0), _rng.randf_range(52.0, 94.0), 4,
			bark, 0.88, 0.03, Shape.COLUMN, 8)
		# Root buttresses: three slabs leaning out of the base, which is what
		# makes a trunk sit IN the ground rather than on it.
		for k in 3:
			var a := _rng.randf() * TAU
			var o := Vector2(cos(a), sin(a)) * 4.4
			_solid(Vector3(at.x + o.x, height_at(at.x, at.y) + 1.6, at.y + o.y),
				Vector3(3.4, 5.0, 2.2), bark, a, Shape.WEDGE)
	_canopy()
	_underbrush()
	# The sea, low enough that it fills the hollows as lakes and channels rather
	# than drowning the map. The beaches come free: the ground shader's lowest
	# band is sand, and the lowest ground is exactly the waterline.
	# Rivers and lakes: the lowest sixth of the ground, and no more. See
	# _sea_level — the level is measured off the terrain, because two guesses at
	# "some fraction of the amplitude" both produced an open ocean.
	_build_sea(_sea_level(0.16), Color(0.16, 0.42, 0.46), false)
	_low_cover(_shade(barks), 18)


## UNDERBRUSH. Dense low fronds you walk and shoot straight through, plus taller
## clumps that break a sight line without stopping a round.
##
## NOTHING here collides, and that is the point on both counts: the project rule
## is that decoration must never quietly become a wall, and a forest floor you
## cannot cross is a worse map than a bare one. So this changes what a fight
## LOOKS like and what you can SEE through it, and changes nothing about where
## anyone can walk or what a bullet does — which also means the nav grid and the
## AI need to know nothing about it.
##
## Two layers, because one does not read as undergrowth: a dense low mat at
## ankle-to-knee that covers the ground everywhere, and sparse tall clumps you
## can lose a body behind.
func _underbrush() -> void:
	# A squashed low-poly SPHERE, not a prism. A triangular prism at this size
	# reads as a tent or a traffic cone from every angle; a five-sided blob reads
	# as a bush, which is the entire job.
	var frond := SphereMesh.new()
	frond.radius = 0.5
	frond.height = 1.0
	frond.radial_segments = 5
	frond.rings = 2
	var low := []
	var tall := []
	var reach := size * 0.47
	for i in 1500:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * reach
		var at := Vector2(cos(a), sin(a)) * r
		var g := height_at(at.x, at.y)
		# Nothing grows in the water; the sea level is where the beaches start.
		if g < _sea_level(0.16) + 0.6:
			continue
		var w := _rng.randf_range(1.8, 4.0)
		low.append(_ghost(Vector3(at.x, g + 0.30, at.y),
			Vector3(w, _rng.randf_range(0.7, 1.5), w * 0.85), _rng.randf() * TAU))
	for i in 150:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * reach
		var at := Vector2(cos(a), sin(a)) * r
		var g := height_at(at.x, at.y)
		if g < _sea_level(0.16) + 0.8:
			continue
		# A clump, not a single blade: three or four fronds on one spot at
		# different headings is what reads as a bush.
		for k in _rng.randi_range(3, 5):
			var o := Vector2(_rng.randf_range(-1.0, 1.0),
				_rng.randf_range(-1.0, 1.0)) * 1.6
			var h := _rng.randf_range(2.2, 3.6)   # head height: breaks a sight line
			tall.append(_ghost(Vector3(at.x + o.x, g + h * 0.42, at.y + o.y),
				Vector3(_rng.randf_range(1.8, 3.0), h, _rng.randf_range(1.6, 2.6)),
				_rng.randf() * TAU))
	Props.batch(self, frond, low, _mat(Color(0.16, 0.30, 0.12), 0.97), false)
	Props.batch(self, frond, tall, _mat(Color(0.11, 0.24, 0.09), 0.97), true)


## The canopy: a scattered ceiling of huge leaf slabs, well above head height.
## Non-colliding and drawn as one batch. It is what turns a field of columns into
## a FOREST — the light comes down in shafts and the sky is broken up.
func _canopy() -> void:
	var leaf := BoxMesh.new()
	leaf.size = Vector3(1.0, 1.0, 1.0)
	var xf := []
	for i in 46:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * size * 0.46
		var at := Vector2(cos(a), sin(a)) * r
		var w := _rng.randf_range(14.0, 26.0)
		xf.append(_ghost(Vector3(at.x, _rng.randf_range(74.0, 104.0), at.y),
			Vector3(w, _rng.randf_range(1.5, 3.0), w * _rng.randf_range(0.7, 1.3)),
			_rng.randf() * TAU))
	Props.batch(self, leaf, xf, _mat(Color(0.10, 0.20, 0.08), 0.98), true)


## CORUSCANT: a real skyline. Towers are built from a GRAMMAR rather than a
## stack of equal boxes, because that grammar is what the eye recognises as
## architecture: a wide PODIUM at the foot, a SHAFT that steps in at setbacks, a
## narrower CROWN, and a MAST. Get those four in the right proportions and a box
## reads as a building; get them wrong and no amount of detail rescues it.
##
## On top of that, surface detail at three scales — vertical mullions running the
## height of each segment, horizontal floor bands every few metres, and lit
## window rows. That is what gives a 90 m tower a SIZE: without something small
## and repeated on it, a tall box is just a tall box and could be any height.
func _lay_city() -> void:
	var plates := _shades(Color(0.30, 0.32, 0.40), 0.55, 0.25)
	var reach := size * 0.42
	var placed: Array = []
	for i in 20:
		var at := _find_spot(15.0, reach)
		if at == Vector2.INF:
			continue
		placed.append(at)
		_tower(at, _rng.randf_range(14.0, 24.0), _rng.randf_range(34.0, 96.0),
			_shade(plates))
	# SKYBRIDGES between neighbours. Coruscant is a city you cross above the
	# ground, and a span between two towers is the one element that says these
	# are inhabited rather than extruded.
	for a: Vector2 in placed:
		for b: Vector2 in placed:
			var gap := a.distance_to(b)
			if a == b or gap < 34.0 or gap > 62.0 or _rng.randf() > 0.16:
				continue
			var mid := (a + b) * 0.5
			var yaw := atan2(b.y - a.y, b.x - a.x)
			var y := height_at(mid.x, mid.y) + _rng.randf_range(22.0, 46.0)
			_greeble(Vector3(mid.x, y, mid.y), Vector3(gap, 1.6, 3.4), -yaw)
			_lamp(Vector3(mid.x, y + 1.1, mid.y), Vector3(gap * 0.9, 0.3, 0.8), -yaw)
	_low_cover(_shade(plates), 26)


## One tower.
func _tower(at: Vector2, w: float, h: float, mat: Material) -> void:
	var ground := height_at(at.x, at.y)
	var yaw := _rng.randf() * TAU
	# PODIUM: wider than the shaft and short. It is what stops a tower looking
	# like a pole pushed into the ground.
	var pod_h := h * 0.10
	_solid(Vector3(at.x, ground + pod_h * 0.5 - 1.0, at.y),
		Vector3(w * 1.34, pod_h + 2.0, w * 1.34), mat, yaw)
	var y := ground + pod_h
	var seg_w := w
	var segments := _rng.randi_range(2, 4)
	for seg in segments:
		# Each segment shorter than the last: real towers taper their FLOOR
		# COUNT as well as their plan, and equal segments read as a stack.
		var seg_h := (h - pod_h) / float(segments) * _rng.randf_range(0.8, 1.2)
		_solid(Vector3(at.x, y + seg_h * 0.5, at.y),
			Vector3(seg_w, seg_h, seg_w * _rng.randf_range(0.9, 1.1)), mat, yaw)
		_clad(at, y, seg_h, seg_w, yaw)
		y += seg_h
		seg_w *= _rng.randf_range(0.80, 0.90)
	# CROWN and MAST. A flat top is the loudest thing that says "primitive": every
	# tower on a skyline ends in something.
	_solid(Vector3(at.x, y + 2.0, at.y), Vector3(seg_w * 1.15, 4.0, seg_w * 1.15),
		mat, yaw)
	_greeble(Vector3(at.x, y + 8.0, at.y), Vector3(seg_w * 0.5, 10.0, seg_w * 0.5), yaw)
	_greeble(Vector3(at.x, y + 16.0, at.y), Vector3(0.9, 12.0, 0.9), yaw)
	_lamp(Vector3(at.x, y + 22.5, at.y), Vector3(1.6, 1.6, 1.6), yaw)
	# Roof machinery, scattered on the podium roof.
	for k in _rng.randi_range(2, 4):
		var o := Vector2(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.5, 0.5)) * w
		_greeble(Vector3(at.x + o.x, ground + pod_h + 1.2, at.y + o.y),
			Vector3(_rng.randf_range(2.0, 5.0), _rng.randf_range(1.5, 3.5),
				_rng.randf_range(2.0, 5.0)), _rng.randf() * TAU)


## The skin of one shaft segment: vertical mullions, horizontal floor bands and
## lit window rows on all four faces.
func _clad(at: Vector2, base_y: float, seg_h: float, w: float, yaw: float) -> void:
	var half := w * 0.5
	var ribs := maxi(int(w / 3.2), 3)
	for face in 4:
		var a := yaw + face * PI * 0.5
		var out := Vector2(cos(a), sin(a))         # outward normal of this face
		var side := Vector2(-out.y, out.x)         # along the face
		# The yaw that puts a greeble's LOCAL +Z along `out`, so its thin axis
		# goes INTO the facade. Basis(UP, t) sends +Z to (sin t, 0, cos t), so
		# t = PI/2 - a. Using -a instead turns every piece ninety degrees and the
		# window bands stick out of the tower as glowing shelves — which is
		# exactly what they did.
		var face_yaw := PI * 0.5 - a
		for r in ribs:
			var t := (float(r) / float(ribs - 1) - 0.5) * (w * 0.86)
			var p := at + out * (half + 0.25) + side * t
			_greeble(Vector3(p.x, base_y + seg_h * 0.5, p.y),
				Vector3(0.55, seg_h * 0.94, 0.5), face_yaw)
		# Floor bands every few metres, and lit rows between some of them. Not
		# every floor: a fully lit tower reads as a lamp, and the gaps are what
		# make it read as a building with people in some of it.
		var floors := maxi(int(seg_h / 4.5), 2)
		for f in floors:
			var fy := base_y + (float(f) + 0.5) / float(floors) * seg_h
			var p2 := at + out * (half + 0.15)
			_greeble(Vector3(p2.x, fy, p2.y), Vector3(w * 0.94, 0.35, 0.3), face_yaw)
			if _rng.randf() < 0.45:
				# Set INTO the face, not proud of it: 0.9 deep with its centre on
				# the wall leaves it flush, which is what a window is.
				_lamp(Vector3(p2.x, fy + 1.2, p2.y),
					Vector3(w * 0.80, 1.0, 0.9), face_yaw)


## MUSTAFAR: a refinery on a lava plain. Blocky, industrial, and the only planet
## whose ground lights the buildings rather than the other way round.
func _lay_foundry() -> void:
	var irons := _shades(Color(0.28, 0.24, 0.23), 0.75, 0.35)
	var iron: Material = _shade(irons)
	var rust := _mat(Color(0.36, 0.20, 0.12), 0.9, 0.15)
	var molten := Props.glow(Color(1.0, 0.42, 0.10), 3.2)
	var reach := size * 0.40
	for i in 20:
		var at := _find_spot(12.0, reach)
		if at == Vector2.INF:
			continue
		if _rng.randf() < 0.45:
			# A chimney stack.
			_stack(at, _rng.randf_range(6.0, 9.0), _rng.randf_range(30.0, 62.0), 3,
				_shade(irons), 0.90, 0.02, Shape.COLUMN, 10)
			_solid(Vector3(at.x, height_at(at.x, at.y) + 2.0, at.y),
				Vector3(14.0, 4.0, 14.0), rust)
		else:
			# A refinery block, wide and low, with a molten seam at its foot.
			var w := _rng.randf_range(16.0, 26.0)
			_stack(at, w, _rng.randf_range(10.0, 20.0), 2, _shade(irons), 0.85, 0.04)
			_solid(Vector3(at.x, height_at(at.x, at.y) + 0.4, at.y),
				Vector3(w * 1.25, 0.8, w * 1.25), molten)
	# Volcanic massifs, and the lava itself: the same sea Kashyyyk floods its
	# hollows with, lit instead of transparent, so the molten rivers follow the
	# real low ground and pool where the terrain actually dips.
	for i in 5:
		var at := _find_spot(30.0, size * 0.36)
		if at != Vector2.INF:
			_mountain(at, _rng.randf_range(34.0, 54.0), _rng.randf_range(30.0, 50.0))
	for i in 3:
		var at := _find_spot(12.0, size * 0.34)
		if at != Vector2.INF:
			_bunker(at, _rng.randf() * TAU)
	_build_sea(_sea_level(0.11), Color(1.0, 0.36, 0.06), true)
	_low_cover(rust, 22)


## HOTH: a snowfield people have DUG INTO. The relief is all in the terrain (its
## octaves are the tallest here); what stands on it is low, built, and half
## buried — bunkers, revetments, trenches, and the rock the wind has stripped
## bare. No ice spires: they read as stalagmites and fight the horizon, which on
## a snowfield is the whole picture.
func _lay_glacier() -> void:
	var ices := _shades(Color(0.72, 0.82, 0.94), 0.5, 0.1)
	# Genuinely DARK. On an all-white map the exposed rock is the only value
	# contrast there is, and at anything lighter it disappears into the snow.
	var rock := _shades(Color(0.17, 0.18, 0.23), 0.95)
	var reach := size * 0.42
	# ROCK OUTCROPS: dark, angular, poking through the snow. On an all-white map
	# these are the only value contrast there is, and without them the whole
	# planet is one tone with a horizon drawn on it.
	for i in 9:
		var at := _find_spot(14.0, reach)
		if at == Vector2.INF:
			continue
		var n := _rng.randi_range(2, 4)
		for k in n:
			var o := Vector2(_rng.randf_range(-1.0, 1.0),
				_rng.randf_range(-1.0, 1.0)) * 7.0
			var p := at + o
			var h := _rng.randf_range(3.5, 9.0)
			_solid(Vector3(p.x, height_at(p.x, p.y) + h * 0.4 - 1.2, p.y),
				Vector3(_rng.randf_range(5.0, 11.0), h, _rng.randf_range(5.0, 10.0)),
				_shade(rock), _rng.randf() * TAU, Shape.WEDGE)
			_snow_against(p, 7.0)
	# Low ice revetments: chest-to-head walls, the thing you actually fight from.
	for i in 12:
		var at := _find_spot(15.0, reach)
		if at == Vector2.INF:
			continue
		var yaw := _rng.randf() * TAU
		var dir := Vector2(cos(yaw), sin(yaw))
		var n := _rng.randi_range(3, 5)
		for k in n:
			var o := dir * (k - n * 0.5) * 10.0
			var p := at + o
			var h := _rng.randf_range(2.2, 4.0)
			_solid(Vector3(p.x, height_at(p.x, p.y) + h * 0.5 - 0.6, p.y),
				Vector3(_rng.randf_range(8.0, 13.0), h, NAV_MIN_WIDTH),
				_shade(ices), yaw + _rng.randf_range(-0.15, 0.15))
			_snow_against(p, 5.5)
	for i in 5:
		var at := _find_spot(24.0, size * 0.34)
		if at != Vector2.INF:
			_trench(at, _rng.randf() * TAU, _rng.randf_range(34.0, 56.0))
	for i in 6:
		var at := _find_spot(14.0, size * 0.36)
		if at != Vector2.INF:
			_bunker(at, _rng.randf() * TAU, _rng.randf_range(11.0, 16.0))
	for i in 3:
		var at := _find_spot(15.0, size * 0.34)
		if at != Vector2.INF:
			_cave(at, _rng.randf() * TAU, _rng.randf_range(16.0, 26.0))
	_low_cover(_shade(ices), 16)


## Snow drifted against whatever is at `at`. Three low wedges on random headings,
## overlapping the base — snow does not stop neatly at a wall, it piles against
## it, and that pile is what makes a structure look like it has been standing
## there through weather rather than dropped in this morning.
func _snow_against(at: Vector2, radius: float) -> void:
	for k in 3:
		var a := _rng.randf() * TAU
		var o := Vector2(cos(a), sin(a)) * radius * _rng.randf_range(0.5, 1.0)
		var p := at + o
		_drift(Vector3(p.x, height_at(p.x, p.y) + 0.6, p.y),
			Vector3(_rng.randf_range(5.0, 11.0), _rng.randf_range(1.4, 3.0),
				_rng.randf_range(4.0, 8.0)), a)


## Waist-high cover, spread across the middle where the fighting is. Every map
## needs it and none of the landmark generators produce it — a field of 60 m
## towers is dramatic and completely unplayable.
func _low_cover(mat: Material, count: int) -> void:
	for i in count:
		var at := _find_spot(4.0, size * 0.44)
		if at == Vector2.INF:
			continue
		var w := _rng.randf_range(2.5, 6.0)
		var h := _rng.randf_range(1.2, 2.4)
		# A crag half the time: a field of identical boxes is what makes cover
		# read as crates dropped on a planet rather than as part of it.
		_solid(Vector3(at.x, height_at(at.x, at.y) + h * 0.5 - 0.3, at.y),
			Vector3(w, h, _rng.randf_range(2.0, 5.0)), mat, _rng.randf() * TAU,
			Shape.CRAG if _rng.randf() < 0.5 else Shape.WEDGE)


## Loose rock and debris. Non-colliding, one batch, purely to break up the ground
## plane between the structures.
func _scatter_rubble() -> void:
	var p: Dictionary = PLANETS[planet]
	var rock := SphereMesh.new()   # faceted pebble, not a die
	rock.radius = 0.5
	rock.height = 1.0
	rock.radial_segments = 5
	rock.rings = 2
	var xf := []
	for i in 150:
		var at := Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) \
			* size * 0.47
		# A wide size range, weighted small: uniform pebbles read as litter
		# scattered on a floor, which is exactly what the first pass looked like.
		var s := _rng.randf_range(0.4, 1.0)
		if _rng.randf() < 0.22:
			s = _rng.randf_range(2.0, 5.5)
		xf.append(_ghost(Vector3(at.x, height_at(at.x, at.y) + s * 0.25, at.y),
			Vector3(s, s * _rng.randf_range(0.4, 0.9), s * _rng.randf_range(0.7, 1.4)),
			_rng.randf() * TAU))
	Props.batch(self, rock, xf, _mat(p["ground"]["rock_col"], 0.95), true)


## THE BACKDROP — a ring of enormous shapes standing WELL OUTSIDE the playable
## area, three to five times the height of anything you can walk to.
##
## This is the single cheapest thing on the list and it does more for scale than
## everything else put together. A 300 m arena with nothing past its edge reads
## as 300 metres; the same arena with a skyline behind it reads as a corner of
## somewhere much larger, because the eye judges size by what it can compare
## against and the fog gives it the distance for free (aerial perspective is
## already on — see Grade).
##
## Non-colliding, one MultiMesh, and placed on a ring at 1.1x to 2.4x the map's
## own half-width so nothing in it is ever reachable. It has no gameplay meaning
## at all and must not acquire any.
func _build_backdrop() -> void:
	var p: Dictionary = PLANETS[planet]
	var shape := BoxMesh.new()
	shape.size = Vector3.ONE
	var xf := []
	var half := size * 0.5
	var rings := 3
	for ring in rings:
		# Further rings are taller and sparser, which is how a real skyline
		# recedes: you only see the big ones from a long way off.
		#
		# The first ring starts at 1.7x the half-width, not 1.15x. Closer in, the
		# ring is a PALISADE: at 26 shapes on a circle that size the gaps close
		# up, the horizon becomes a solid wall of the same colour, and instead of
		# reading as distance it reads as being at the bottom of a bucket.
		var dist := half * (1.7 + ring * 0.75)
		var count := 14 - ring * 3
		var tall := 1.0 + ring * 0.9
		for i in count:
			var a := TAU * (float(i) + _rng.randf_range(-0.4, 0.4)) / float(count)
			var at := Vector2(cos(a), sin(a)) * dist * _rng.randf_range(0.88, 1.18)
			var h := _rng.randf_range(70.0, 150.0) * tall
			var w := _rng.randf_range(24.0, 60.0) * (1.0 + ring * 0.4)
			# Built as a short stack even out here: a single slab on the horizon
			# reads as a wall, and the whole point of the ring is that it reads
			# as things.
			var steps := 3
			var y := -8.0
			var ww := w
			for k in steps:
				var sh := h / float(steps)
				xf.append(_ghost(Vector3(at.x, y + sh * 0.5, at.y),
					Vector3(ww, sh, ww * _rng.randf_range(0.8, 1.25)),
					_rng.randf() * TAU))
				y += sh
				ww *= _backdrop_taper()
	# Tinted toward the FOG colour, not the rock colour. At this distance the
	# atmosphere has taken most of the object's own colour anyway, and matching
	# the fog is what lets the ring sit behind the haze instead of punching
	# through it.
	var far: Color = p["fog"]["color"].lerp(p["ground"]["rock_col"], 0.35)
	Props.batch(self, shape, xf, _mat(far, 0.98), false)


## How sharply the backdrop shapes narrow with height — the profile is the only
## thing distinguishing a city skyline from a mountain range at this distance.
func _backdrop_taper() -> float:
	match PLANETS[planet]["lay"]:
		"city": return 0.86      # towers: near-vertical
		"forest": return 0.90    # trunks: near-vertical
		"glacier": return 0.68   # peaks
		_: return 0.62           # mesas and volcanoes: heavily tapered


# --- terrain features ----------------------------------------------------------

## A SEA: one plane at a fixed height, flooding whatever the terrain leaves below
## it. Kashyyyk's water and Mustafar's lava are the same object with a different
## material — and because the height function is a sum of sines, its hollows are
## already a connected network of basins and channels, so a plane through them
## comes out as LAKES AND RIVERS rather than as a bathtub. Nothing has to be
## carved and nothing has to be routed.
##
## No collider. You wade; the terrain under it is still the floor, and it is
## still walkable, so nothing the AI does has to know the sea exists.
## The height that floods exactly `fraction` of the map, MEASURED rather than
## guessed. Samples the height function on a coarse grid and takes the
## percentile.
##
## This exists because guessing does not work: the height function is a sum of
## products of sinusoids, so its distribution is bunched hard around zero and
## nothing about the octave amplitudes tells you where the 15th percentile is.
## Two hand-picked fractions of the amplitude both came out as an open ocean with
## the map poking through it. Asking the terrain is one loop and is right by
## construction, whatever anyone does to the octaves later.
func _sea_level(fraction: float) -> float:
	var samples := PackedFloat32Array()
	var half := size * 0.5
	var step := size / 48.0
	for i in 48:
		for j in 48:
			samples.append(height_at(-half + i * step, -half + j * step))
	var sorted := Array(samples)
	sorted.sort()
	return sorted[clampi(int(sorted.size() * fraction), 0, sorted.size() - 1)]


func _build_sea(level: float, colour: Color, emissive: bool) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	# EXACTLY the map, not past it. At three times the size the plane covered
	# everything outside the terrain too, so the hollows-flooded-with-rivers came
	# out as an open ocean with the map poking out of it.
	plane.size = Vector2(size, size)
	mi.mesh = plane
	mi.position.y = level
	var m := StandardMaterial3D.new()
	if emissive:
		m.albedo_color = colour
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.emission = colour
		m.emission_energy_multiplier = 2.6
	else:
		m.albedo_color = Color(colour.r, colour.g, colour.b, 0.72)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.metallic = 0.35
		m.roughness = 0.08
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## A MOUNTAIN: a wide, heavily tapered mass. The same stack a spire uses with a
## much broader base and a shallower taper, which is genuinely the difference —
## a mountain is a spire that ran out of height before it ran out of width.
func _mountain(at: Vector2, base: float, height: float) -> void:
	_stack(at, base, height, 5, _shade(_terrain_shades()), 0.74, 0.10,
		Shape.CONE, _rng.randi_range(5, 7))


func _terrain_shades() -> Array:
	if _rock_shades.is_empty():
		_rock_shades = _shades(PLANETS[planet]["ground"]["rock_col"] * 1.5, 0.95)
	return _rock_shades


## A CAVE: a walk-through passage, built as a roof slab on two side walls with
## both ends open.
##
## Not carved out of the terrain, and that is deliberate. The heightfield is a
## skin whose slope budget is what keeps it walkable, and cutting a mouth into it
## means cutting a hole the AI cannot see (the nav grid reads boxes, not
## trimeshes) with walls too steep to climb out of. A box passage sitting ON the
## ground is a cave you can fight through, and the nav grid understands its walls
## and its opening for free.
func _cave(at: Vector2, yaw: float, length := 20.0, width := 7.0) -> void:
	var mats := _terrain_shades()
	var mat := _shade(mats)
	var g := height_at(at.x, at.y)
	var head := 4.2
	var dir := Vector2(cos(yaw), sin(yaw))
	var side := Vector2(-dir.y, dir.x)
	for s in [-1.0, 1.0]:
		var o: Vector2 = side * (width * 0.5 + 1.5) * s
		_solid(Vector3(at.x + o.x, g + head * 0.5 - 0.6, at.y + o.y),
			Vector3(NAV_MIN_WIDTH, head + 1.2, length), mat, yaw)
	# The roof, thick enough that it reads as rock overhead rather than a lid.
	_solid(Vector3(at.x, g + head + 1.6, at.y), Vector3(width + 6.0, 3.4, length),
		mat, yaw)
	# A shoulder of rock over the mouth at each end, so it looks bored INTO
	# something instead of being a free-standing carport.
	for e in [-1.0, 1.0]:
		var o: Vector2 = dir * (length * 0.5) * e
		_solid(Vector3(at.x + o.x, g + head + 4.0, at.y + o.y),
			Vector3(width + 10.0, 6.0, 7.0), mat, yaw)


## A BUNKER: four walls with a door gap, a roof, and a firing slit facing out.
## Boxes throughout, so the doorway is a real gap in the nav grid and the AI
## walks in and out of it without being told anything.
func _bunker(at: Vector2, yaw: float, w := 11.0) -> void:
	var mat := _shade(_terrain_shades())
	var g := height_at(at.x, at.y)
	var h := 3.6
	var t := NAV_MIN_WIDTH   # never thinner than the nav grid can see
	var half := w * 0.5
	var door := 3.2
	# Back and two sides solid; the front is split either side of a doorway.
	var walls := [
		[Vector3(0, 0, -half), Vector3(w, h, t)],
		[Vector3(-half, 0, 0), Vector3(t, h, w)],
		[Vector3(half, 0, 0), Vector3(t, h, w)],
		[Vector3(-(half + door * 0.5) * 0.5, 0, half),
			Vector3(w - door, h, t) * Vector3(0.5, 1, 1)],
		[Vector3((half + door * 0.5) * 0.5, 0, half),
			Vector3(w - door, h, t) * Vector3(0.5, 1, 1)],
	]
	for wall in walls:
		var local: Vector3 = wall[0]
		var rot := local.rotated(Vector3.UP, yaw)
		_solid(Vector3(at.x + rot.x, g + h * 0.5 - 0.4, at.y + rot.z), wall[1],
			mat, yaw)
	_solid(Vector3(at.x, g + h + 0.4, at.y), Vector3(w + 2.0, 1.2, w + 2.0), mat, yaw)
	# A SLOPED GLACIS across the front and an EMBRASURE above it. A bunker is not
	# a shoebox with a hole: it is a sloped mass with a slit, and those two
	# features are the whole silhouette. Both are surface detail — the box below
	# is still what the AI and the bullets see.
	var face := Vector3(0, 0, half + 1.0).rotated(Vector3.UP, yaw)
	_greeble(Vector3(at.x + face.x, g + h * 0.45, at.y + face.z),
		Vector3(w * 1.05, h * 0.9, 3.0), yaw)
	_lamp(Vector3(at.x + face.x * 1.02, g + h * 0.78, at.y + face.z * 1.02),
		Vector3(w * 0.62, 0.55, 0.6), yaw)
	# ...and a revetment of piled snow/spoil around the base.
	_snow_against(at, w * 0.8)


## A TRENCH: two parallel berms with gaps in them, rather than a cut in the
## ground. Same reasoning as the cave — a carved channel is a slope the AI cannot
## see and cannot climb, where a berm is a wall it routes around and fights from.
func _trench(at: Vector2, yaw: float, length := 44.0) -> void:
	var mat := _shade(_terrain_shades())
	var dir := Vector2(cos(yaw), sin(yaw))
	var side := Vector2(-dir.y, dir.x)
	var seg := 7.0
	var n := int(length / seg)
	for i in n:
		# Gaps: a continuous wall is a fence, and a fence with no way through is
		# the one thing that turns a trench into an obstacle instead of a route.
		if _rng.randf() < 0.18:
			continue
		var along := dir * (i - n * 0.5) * seg
		for s in [-1.0, 1.0]:
			var o: Vector2 = along + side * 3.2 * s
			var p := at + o
			var h := _rng.randf_range(1.6, 2.6)
			# 3.6 m thick, not 2. The nav grid stamps a cell solid when an
			# obstacle reaches its CENTRE, and on a 285 m map the cell spacing is
			# at the coarse end — a berm thinner than that falls between two
			# centres and A* routes bots straight through it. tests/nav_grid
			# caught exactly that: 2 of 24 routes passing through real geometry.
			_solid(Vector3(p.x, height_at(p.x, p.y) + h * 0.5 - 0.5, p.y),
				Vector3(seg * 0.95, h, NAV_MIN_WIDTH), mat, yaw)
