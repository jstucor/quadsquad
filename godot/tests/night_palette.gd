extends Node
## THE NIGHT MAPS MUST STILL BE PLAYABLE, and that is arithmetic rather than
## taste — which is why it can be checked without a renderer.
##
##   godot --headless --path godot tests/night_palette.tscn
##
## A SCENE and not a `--script` test, unlike kit_rules.gd, for a reason worth
## writing down: `map_planet.gd` names GameState, so it cannot be compiled with
## the autoloads absent. The palette itself is all const tables and static
## functions and would happily run either way — it is the file they live in that
## decides, which is the same constraint that keeps Loadout from ever naming
## GameState.
##
## The failure this exists to catch has already happened twice while the mode was
## being written, both times by making something a little darker than the last
## thing that looked good: the ground under your feet went to pure black and the
## map kept its skyline, so it still PHOTOGRAPHED well and could not be walked
## on. A screenshot is a bad detector for that and a number is a good one, so:
##
##   * every night world keeps a floor under its terrain albedo, so there is
##     always a surface there to be lit;
##   * every night world has SOME key light — a night with a dead directional is
##     a flat ambient wash with no form in it at all;
##   * every night world has enough ambient to hold the shadow side up, because
##     ambient is the only thing lighting anything the moon cannot reach (which
##     on Kashyyyk is the entire forest floor);
##   * and night is genuinely DARKER than day, or the mode does nothing. That
##     one is measured on the KEY LIGHT and not on the ground albedo, which was
##     the first version and was measuring the wrong thing: a world whose
##     daytime ground is already near-black (a city deck, an obsidian flat)
##     cannot lose much of it, so the check fired on the two worlds that have
##     the most convincing nights in the game. What night actually takes away is
##     the light, and every world has plenty of that to lose.
##
## The bounds are deliberately loose. This is not trying to pin the look down —
## it is a floor and a ceiling either side of a wide range that all five worlds
## currently sit inside, and it only fires when something has gone properly
## wrong.
##
## It then DEPLOYS ONE, for the same reason universe_match exists next to
## kit_rules: a table that agrees with itself is not the same thing as a match
## you can play out of it. The setting has to travel from the menu, through
## GameState, into the map the generator actually built and into the weapon a
## body actually spawned holding — and each of those is a separate place to have
## forgotten it.

const MIN_GROUND_V := 0.10      # darkest a terrain colour may be at night
const MAX_GROUND_V := 0.42      # ...and light enough that it is still night
const MIN_MOON := 0.20          # directional energy: below this there is no form
const MIN_AMBIENT := 0.055      # mean channel; the floor under the shadow side
const MAX_AMBIENT := 0.30
const MAX_KEY_FRACTION := 0.55  # night key light vs the same world's day sun

var _fails := 0


const MAIN := preload("res://scenes/main.tscn")


func _ready() -> void:
	for id in PlanetMap.PLANETS:
		var name := str(PlanetMap.PLANET_NAMES[id])
		var day: Dictionary = PlanetMap.world(id, false)
		var night: Dictionary = PlanetMap.world(id, true)
		_check_has_night(name, id)
		_check_ground(name, day, night)
		_check_light(name, night)
		_check_darker(name, day, night)
	await _check_deploys()
	if _fails == 0:
		print("night_palette: OK — %d worlds, and a night match deploys"
			% PlanetMap.PLANETS.size())
	else:
		print("night_palette: %d FAILURES" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


## Boot a real night match and follow the setting all the way down.
func _check_deploys() -> void:
	GameState.reset_match()
	GameState.map_index = GameState.procedural_map_index()
	GameState.time_of_day = GameState.TimeOfDay.NIGHT
	GameState.planet = PlanetMap.Planet.GEONOSIS
	GameState.human_players = 1
	GameState.team_size = 2
	if not GameState.is_night():
		_fail("GameState says it is not night on the generated map at NIGHT")
		return
	var main: Node = MAIN.instantiate()
	add_child(main)
	for _i in 30:
		await get_tree().physics_frame

	# The MAP: the generator has to have resolved the night palette, not the day
	# one. The key light's energy is the cheapest thing to read that could only
	# have come from the night block.
	var lights := main.find_children("*", "DirectionalLight3D", true, false)
	var key := 0.0
	for l in lights:
		key = maxf(key, l.light_energy)
	var want: float = PlanetMap.world(PlanetMap.Planet.GEONOSIS, true)["sun"]["energy"]
	if not is_equal_approx(key, want):
		_fail("the deployed map's key light is %.2f, not the night table's %.2f"
			% [key, want])

	# The WEAPON: a gun resolves its flash reach at spawn, so this is the check
	# that the setting reached the things that ACT differently at night rather
	# than only the things that are drawn.
	var guns := main.find_children("*", "Weapon", true, false)
	if guns.is_empty():
		_fail("no weapon deployed, so the flash reach cannot be checked")
	else:
		var lit := 0
		for g in guns:
			for c in g.get_children():
				if c is OmniLight3D and is_equal_approx(c.omni_range,
						Weapon.FLASH_RANGE * Weapon.NIGHT_FLASH_RANGE):
					lit += 1
		if lit == 0:
			_fail("no deployed weapon carries the night muzzle flash reach")
	main.queue_free()
	await get_tree().process_frame


## Every world has a night. A generated world with no night block still BUILDS
## at night — it just builds its daytime self, which is worse than an error
## because the menu says NIGHT and the map does not.
func _check_has_night(name: String, id: int) -> void:
	if not PlanetMap.PLANETS[id].has("night"):
		_fail("%s has no night palette — a world without one still BUILDS at "
			% name + "night, it just builds its daytime self, so the menu says "
			+ "NIGHT and the map disagrees")


func _check_ground(name: String, day: Dictionary, night: Dictionary) -> void:
	for key in night["ground"]:
		if not (night["ground"][key] is Color):
			continue
		# Lava and city light are the exception the whole design turns on: they
		# are the map's own illumination and are meant to be brighter at night,
		# not darker.
		if key in PlanetMap.NIGHT_EMISSIVE:
			continue
		var v: float = night["ground"][key].v
		# `under_col` is the underside of the heightfield, which is a cave roof
		# and is supposed to be black.
		if key == "under_col":
			continue
		if v < MIN_GROUND_V:
			_fail("%s night ground '%s' is %.3f — below the %.2f floor; the "
				% [name, key, v, MIN_GROUND_V]
				+ "surface underfoot goes black and the map cannot be walked")
		if v > MAX_GROUND_V:
			_fail("%s night ground '%s' is %.3f — above %.2f, which is not night"
				% [name, key, v, MAX_GROUND_V])
	if _mean_ground(night) > _mean_ground(day):
		_fail("%s night ground is lighter than its day ground" % name)


func _check_light(name: String, night: Dictionary) -> void:
	var energy: float = night["sun"]["energy"]
	if energy < MIN_MOON:
		_fail("%s night key light is %.2f — under %.2f there is no directional "
			% [name, energy, MIN_MOON]
			+ "shading left and every surface is a flat ambient value")
	var a: Color = night["ambient"]
	var mean := (a.r + a.g + a.b) / 3.0
	if mean < MIN_AMBIENT:
		_fail("%s night ambient is %.3f — under %.3f the shadow side of "
			% [name, mean, MIN_AMBIENT]
			+ "everything, and anything the moon cannot reach, is unreadable")
	if mean > MAX_AMBIENT:
		_fail("%s night ambient is %.3f — over %.3f it is a grey wash with no "
			% [name, mean, MAX_AMBIENT] + "dark in it")


func _check_darker(name: String, day: Dictionary, night: Dictionary) -> void:
	var d: Color = day["sky"]["zenith_col"]
	var n: Color = night["sky"]["zenith_col"]
	if n.v >= d.v:
		_fail("%s night sky (%.3f) is not darker than its day sky (%.3f)"
			% [name, n.v, d.v])
	var dk: float = day["sun"]["energy"]
	var nk: float = night["sun"]["energy"]
	if nk > dk * MAX_KEY_FRACTION:
		_fail("%s night key light is %.0f%% of its day sun — over %.0f%% it is "
			% [name, nk / maxf(dk, 0.001) * 100.0, MAX_KEY_FRACTION * 100.0]
			+ "an overcast afternoon with the colours changed")


func _mean_ground(w: Dictionary) -> float:
	var total := 0.0
	var count := 0
	for key in ["low_col", "mid_col", "high_col", "rock_col"]:
		total += (w["ground"][key] as Color).v
		count += 1
	return total / maxf(float(count), 1.0)


func _fail(msg: String) -> void:
	_fails += 1
	print("  FAIL: %s" % msg)
