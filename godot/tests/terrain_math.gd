extends Node
## THE TERRAIN'S TWO GUARANTEES, CHECKED AS ARITHMETIC.
##
## `height_at` and `steepness_at` are the pair in this project most able to
## disagree without anything erroring. One is the surface; the other claims to be
## its exact analytic gradient, and the shader paints rock wherever the second one
## says it is steep. If they drift apart the result is rock on the flats and grass
## on the cliffs — which reads as a palette mistake and sends you into the shader,
## where the fault is not.
##
## So the derivative is checked against a CENTRAL DIFFERENCE of the height
## function itself. Nothing is taken on trust: if the two agree everywhere on a
## dense sample of every planet, at every seed, the chain rule was done right.
##
## The second guarantee is walkability. The whole octave design exists so that
## "whatever anyone puts in the table stays walkable" is arithmetic rather than
## a tuning exercise — so it is measured, not asserted.
##
## Run:  godot --headless --path godot tests/terrain_math.tscn

const PLANET_MAP := preload("res://scenes/levels/planet.tscn")

const SEEDS := 4
const SAMPLES := 900
const PROBE := 0.05          # metres either side, for the central difference
## The gradient from finite differences and the analytic one will never be bit
## identical — the surface has curvature and the probe has width. This is well
## inside "the same function" and far outside "somebody dropped a term".
const GRADIENT_TOLERANCE := 0.012

var _failures := 0


func _ready() -> void:
	print("\n=== TERRAIN MATH ===\n")
	print("  %-12s %-6s %10s %10s %10s" % [
		"planet", "seed", "max slope", "worst d-err", "lowest"])
	for planet in PlanetMap.PLANET_NAMES.keys():
		for s in SEEDS:
			await _check_world(planet, s)
	print("")
	if _failures == 0:
		print("==== THE SURFACE AND ITS GRADIENT AGREE ====")
	else:
		print("==== %d FAILURE%s ====" % [_failures, "" if _failures == 1 else "S"])
	get_tree().quit(1 if _failures > 0 else 0)


func _check_world(planet: int, seed_index: int) -> void:
	GameState.planet = planet
	GameState.planet_seed = 1000 + seed_index * 7919
	var map: PlanetMap = PLANET_MAP.instantiate()
	add_child(map)
	await get_tree().process_frame

	var half: float = map.size * 0.45
	var worst_slope := 0.0
	var worst_err := 0.0
	var lowest := 1e9
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in SAMPLES:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var h: float = map.height_at(x, z)
		lowest = minf(lowest, h)
		# The gradient the shader is told about, back in world units.
		var claimed: float = map.steepness_at(x, z) * map.MAX_GRADIENT
		# ...and the one the surface actually has, measured off it.
		var dx: float = (map.height_at(x + PROBE, z) - map.height_at(x - PROBE, z)) \
			/ (2.0 * PROBE)
		var dz: float = (map.height_at(x, z + PROBE) - map.height_at(x, z - PROBE)) \
			/ (2.0 * PROBE)
		var actual := Vector2(dx, dz).length()
		worst_slope = maxf(worst_slope, actual)
		# Only compared where the claim is not clamped — `steepness_at` saturates
		# at 1.0 by design, so past MAX_GRADIENT the two legitimately differ.
		if claimed < map.MAX_GRADIENT * 0.98:
			worst_err = maxf(worst_err, absf(actual - claimed))

	print("  %-12s %-6d %9.3f %10.5f %10.3f" % [
		str(PlanetMap.PLANET_NAMES.get(planet, planet)), GameState.planet_seed,
		worst_slope, worst_err, lowest])
	if worst_err > GRADIENT_TOLERANCE:
		_check(false, "the claimed gradient does not match the surface (%.5f)"
			% worst_err)
	# WALKABLE BY CONSTRUCTION. This is the promise the octave normalisation
	# makes, and it is the reason a new planet can be a table row.
	if worst_slope > map.MAX_GRADIENT * 1.02:
		_check(false, "slope %.3f exceeds the %.2f budget"
			% [worst_slope, map.MAX_GRADIENT])
	# ...and TERRAIN MUST NOT GO BELOW y = 0, or `scan_map_geometry` throws away
	# every structure standing in a hollow and the nav grid routes through them.
	if lowest < -0.001:
		_check(false, "ground reaches %.3f, below zero" % lowest)
	map.queue_free()
	await get_tree().process_frame


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("        FAIL  %s" % what)
		_failures += 1
