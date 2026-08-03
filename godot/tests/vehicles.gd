extends Node3D
## THE SPEEDERS: the Star-Wars-only rule, the four table rows, the repulsor, and
## the mount/dismount round trip.
##
## Most of what this protects is an ABSENCE or a RESTORE, which is exactly the
## kind of thing a later edit undoes silently: that Halo and Warhammer get NO
## vehicles, that a dismounted player gets its collision and its model back, that
## a driver who dies at the controls does NOT get them back (the death cam owns
## the body by then), and that a speeder never spawns on top of its own team's
## deploy marker.
##
##   godot --headless --path godot tests/vehicles.tscn

const VEHICLE := preload("res://scenes/actors/vehicle.tscn")
const PLAYER := preload("res://scenes/actors/player.tscn")
const MAIN := preload("res://scenes/main.tscn")

var _fails: Array[String] = []


func _ready() -> void:
	GameState.mode = GameState.Mode.DEATHMATCH
	GameState.team_count = 4
	GameState.free_for_all = false
	GameState.reset_match()
	GameState.match_live = true
	_build_floor()

	_test_universe_rule()
	_test_table()
	await _test_hover()
	await _test_mount_round_trip()
	await _test_damage_and_wreck()
	await _test_real_matches()
	await _test_war_machines()

	print("\n==== %s ====" % ("VEHICLES WORK" if _fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [_fails.size(), "\n  ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)


## ONLY STAR WARS HAS VEHICLES. This is the whole scope line and it is one
## function, so this is the test that catches somebody "generalising" it later.
func _test_universe_rule() -> void:
	print("== the Star Wars rule ==")
	var sw: Array = Vehicle.spawns_for(Loadout.Universe.STAR_WARS)
	_expect(sw.size() == 4, "Star Wars fields 4 vehicles, got %d" % sw.size())
	for u: int in [Loadout.Universe.HALO, Loadout.Universe.WARHAMMER]:
		var got: Array = Vehicle.spawns_for(u)
		_expect(got.is_empty(),
			"universe %d fields NO vehicles, got %d" % [u, got.size()])
	# One per SIDE, and the sides are the ones the universe actually names — a
	# fifth row here would be a vehicle belonging to a faction that cannot be
	# fielded, which nothing else would report.
	var teams: Array = Loadout.UNIVERSES[Loadout.Universe.STAR_WARS]["teams"]
	_expect(sw.size() == teams.size(),
		"one vehicle per Star Wars side (%d vehicles, %d sides)"
			% [sw.size(), teams.size()])
	for t: int in sw:
		_expect(t >= 0 and t < teams.size(),
			"vehicle team %d is a real Star Wars side" % t)


## Every row states everything the mechanism reads. A missing key is a default
## somewhere downstream, which is a legal, playable, completely wrong vehicle —
## the same failure mode as a preset naming a gun the catalogue does not sell.
func _test_table() -> void:
	print("\n== the four rows ==")
	var required := ["name", "build", "health", "top_speed", "accel", "turn",
		"hover", "gun", "hull"]
	var names := {}
	var builds := {}
	for t: int in Vehicle.VEHICLES:
		var row: Dictionary = Vehicle.VEHICLES[t]
		for key: String in required:
			_expect(row.has(key), "%s states \"%s\"" % [row.get("name", t), key])
		_expect(Weapon.PROFILES.has(row["gun"]),
			"%s carries a real weapon class" % row["name"])
		# Distinct NAMES and distinct BUILDERS. Two rows sharing a builder is four
		# factions flying three vehicles, which is precisely the "one speeder in
		# four colours" outcome the table exists to avoid.
		_expect(not names.has(row["name"]), "%s is a unique name" % row["name"])
		_expect(not builds.has(row["build"]),
			"%s has a silhouette of its own (\"%s\")" % [row["name"], row["build"]])
		names[row["name"]] = true
		builds[row["build"]] = true
		print("  %-20s hp %4.0f  top %4.1f m/s  turn %.1f  hover %.2f m"
			% [row["name"], row["health"], row["top_speed"], row["turn"], row["hover"]])
	# THE HANDLING ENVELOPE HAS TO BE SPREAD, or taking one is never a decision.
	# Guard rails only — which speeder is fastest is a balance call, that there is
	# a real spread between fastest and slowest is the contract.
	var speeds: Array[float] = []
	var healths: Array[float] = []
	for t: int in Vehicle.VEHICLES:
		speeds.append(float(Vehicle.VEHICLES[t]["top_speed"]))
		healths.append(float(Vehicle.VEHICLES[t]["health"]))
	speeds.sort()
	healths.sort()
	_expect(speeds[-1] / speeds[0] >= 1.25,
		"fastest is meaningfully faster than slowest (%.2fx)" % (speeds[-1] / speeds[0]))
	_expect(healths[-1] / healths[0] >= 2.0,
		"toughest is meaningfully tougher than flimsiest (%.2fx)"
			% (healths[-1] / healths[0]))
	# ...and every one of them has to be faster than running, or it is a prop.
	for t: int in Vehicle.VEHICLES:
		_expect(float(Vehicle.VEHICLES[t]["top_speed"]) > Player.SPRINT_SPEED * 1.5,
			"%s is worth taking over sprinting" % Vehicle.VEHICLES[t]["name"])


## THE REPULSOR. Dropped from well above the floor, every speeder has to settle
## at its OWN row's clearance and stay there — the number that makes an
## airspeeder fly over cover a bike has to go round.
func _test_hover() -> void:
	print("\n== the repulsor ==")
	for t: int in Vehicle.VEHICLES:
		var row: Dictionary = Vehicle.VEHICLES[t]
		var v: Vehicle = VEHICLE_SCENE_new()
		add_child(v)
		v.setup(t)
		v.global_position = Vector3(t * 12.0, 6.0, 0.0)
		v.reset_physics_interpolation()
		for i in 180:
			await get_tree().physics_frame
		var got := v.global_position.y
		var want := float(row["hover"])
		_expect(absf(got - want) < 0.22,
			"%s settles at its own %.2f m clearance (got %.2f)"
				% [row["name"], want, got])
		# A speeder is a combatant, or nothing shoots at it and it does not block
		# a spawn marker.
		_expect(GameState.combatants.has(v), "%s registers as a combatant" % row["name"])
		_expect(v.body_height() > 0.0, "%s reports an aim height" % row["name"])
		v.queue_free()
		await get_tree().physics_frame


## MOUNTING AND — the half that actually breaks — GETTING BACK OFF.
func _test_mount_round_trip() -> void:
	print("\n== mount / dismount ==")
	var v: Vehicle = VEHICLE_SCENE_new()
	add_child(v)
	v.setup(Vehicle.REPUBLIC)
	v.global_position = Vector3(0, 2.0, 40.0)
	var p: Player = PLAYER.instantiate()
	p.player_index = 0
	p.input_device = -1
	p.team = Vehicle.REPUBLIC
	add_child(p)
	p.global_position = Vector3(1.5, 0.2, 40.0)
	for i in 30:
		await get_tree().physics_frame

	# The mount rides the EXISTING interact edge, so this is exactly what a real
	# press produces: the area advertises, the player publishes the press.
	p.pickup_in_reach = v
	p.pickup_pressed = true
	for i in 6:
		await get_tree().physics_frame
	_expect(v.driver == p, "the player mounts")
	_expect(p.in_vehicle(), "the player knows it is flying")
	_expect(not p.model.visible, "the body is hidden while flying")
	_expect(p.get_node("CollisionShape3D").disabled,
		"the body's collision is off while flying")
	_expect(not p.pickup_pressed, "the press was consumed — one press, one action")

	# ...and the driver rides the seat, not wherever it was standing.
	var gap := p.global_position.distance_to(v.get_node("Seat").global_position)
	_expect(gap < 0.05, "the driver is carried on the seat (%.3f m off)" % gap)

	p.pickup_pressed = true
	for i in 6:
		await get_tree().physics_frame
	_expect(v.driver == null, "the player dismounts")
	_expect(not p.in_vehicle(), "the player knows it is back on foot")
	_expect(p.model.visible, "the body comes back")
	_expect(not p.get_node("CollisionShape3D").disabled, "the collision comes back")
	# CLEAR OF THE HULL. Dropping the driver at the vehicle's own origin puts two
	# capsules inside each other, which is the documented ejection bug.
	var out := Vector2(p.global_position.x - v.global_position.x,
		p.global_position.z - v.global_position.z).length()
	_expect(out > 1.0, "the driver is put down clear of the hull (%.2f m)" % out)

	# AN ENEMY'S SPEEDER IS NOT YOURS. The mount area refuses it outright, so
	# there is no way to steal one even standing in it with the button held.
	p.team = Vehicle.EMPIRE
	p.pickup_in_reach = v
	p.pickup_pressed = true
	for i in 6:
		await get_tree().physics_frame
	_expect(v.driver == null, "an enemy cannot take your speeder")
	p.queue_free()
	v.queue_free()
	await get_tree().physics_frame


## SHOOTING ONE DOWN, and what that does to whoever is flying it.
func _test_damage_and_wreck() -> void:
	print("\n== damage ==")
	var v: Vehicle = VEHICLE_SCENE_new()
	add_child(v)
	v.setup(Vehicle.REPUBLIC)
	v.global_position = Vector3(0, 2.0, 80.0)
	await get_tree().physics_frame

	# Friendly fire is off here exactly as it is everywhere else.
	# Both attackers go IN THE TREE. A real shooter always is, and the corpse path
	# reads `attacker.global_position` — a bare Node3D standing outside the scene
	# is a test artifact that reports as a product error.
	var friend := Dummy.new()
	friend.team = Vehicle.REPUBLIC
	add_child(friend)
	var before := v.health
	v.take_damage(100.0, friend)
	_expect(is_equal_approx(v.health, before), "a teammate cannot shoot it")

	var foe := Dummy.new()
	foe.team = Vehicle.EMPIRE
	add_child(foe)
	foe.global_position = Vector3(0, 1.0, 70.0)
	v.take_damage(100.0, foe)
	_expect(v.health < before, "an enemy can")

	# THE HULL DOES NOT SHIELD THE DRIVER. Without the bleed, sitting in a speeder
	# is strictly better than standing anywhere, and the vehicle becomes a bunker.
	var p: Player = PLAYER.instantiate()
	p.player_index = 0
	p.input_device = -1
	p.team = Vehicle.REPUBLIC
	add_child(p)
	p.global_position = Vector3(1.5, 0.2, 80.0)
	for i in 20:
		await get_tree().physics_frame
	p.pickup_in_reach = v
	p.pickup_pressed = true
	for i in 6:
		await get_tree().physics_frame
	_expect(v.driver == p, "mounted for the damage test")
	var hp_before: float = p.health
	v.take_damage(50.0, foe)
	_expect(p.health < hp_before,
		"a round through the hull reaches the driver (%.0f -> %.0f)"
			% [hp_before, p.health])

	# ...and destroying it puts the driver back on their feet rather than freeing
	# them with the wreck.
	v.take_damage(10000.0, foe)
	for i in 6:
		await get_tree().physics_frame
	_expect(not v.is_alive(), "it can be destroyed")
	_expect(not p.in_vehicle(), "the wreck ejects its driver")
	_expect(not GameState.combatants.has(v),
		"a wreck stops being a target")
	p.queue_free()
	await get_tree().physics_frame


## A REAL MATCH IS THE ONLY THING THAT PROVES THE RULE SHIPS. Everything above
## tests `Vehicle` directly; this boots `main.tscn` and counts what actually got
## placed, which is the half that catches `_place_vehicles` never being called,
## being called before the spawn points exist, or quietly running in a universe
## that is supposed to have none.
func _test_real_matches() -> void:
	print("\n== in a real match ==")
	# (universe, mode, teams, how many speeders should be on the field)
	var cases := [
		[Loadout.Universe.STAR_WARS, GameState.Mode.DEATHMATCH, 2, 2],
		[Loadout.Universe.STAR_WARS, GameState.Mode.DEATHMATCH, 4, 4],
		[Loadout.Universe.STAR_WARS, GameState.Mode.CONQUEST, 2, 2],
		# Royale is scavenging, not a motor pool.
		[Loadout.Universe.STAR_WARS, GameState.Mode.ROYALE, 2, 0],
		[Loadout.Universe.HALO, GameState.Mode.DEATHMATCH, 2, 0],
		[Loadout.Universe.WARHAMMER, GameState.Mode.DEATHMATCH, 4, 0],
	]
	for c: Array in cases:
		GameState.universe = c[0]
		GameState.mode = c[1]
		GameState.team_count = c[2]
		GameState.free_for_all = false
		GameState.human_players = 1
		GameState.team_size = 2
		GameState.map_index = 0
		GameState.chosen_teams = []
		var main: Node = MAIN.instantiate()
		add_child(main)
		await _frames(40)
		var found := main.find_children("*", "Vehicle", true, false)
		var label := "%s / %s / %d teams" % [Loadout.UNIVERSES[c[0]]["name"],
			GameState.Mode.keys()[c[1]], c[2]]
		_expect(found.size() == c[3], "%s places %d speeder(s), got %d"
			% [label, c[3], found.size()])
		# ...and no speeder may be sitting on the marker it was parked beside, or
		# it body-blocks that side's respawn for the whole match.
		for v: Node3D in found:
			var clear := true
			for t in GameState.active_teams():
				var sp := GameState.get_spawn_point(t)
				if sp != null and sp.global_position.distance_to(v.global_position) < 2.0:
					clear = false
			_expect(clear, "%s: %s is clear of every spawn marker" % [label, v.label()])
		main.queue_free()
		await _frames(6)
	# Leave the autoload as we found it for anything running after this.
	GameState.universe = Loadout.Universe.STAR_WARS
	GameState.mode = GameState.Mode.DEATHMATCH


## THE EARNED WAR MACHINES (see `Streaks`), and mostly ONE question: does the
## thing stand on the ground it is standing on?
##
## A WALKER'S LEGS ARE DRAWN, NOT SIMULATED — the hull hovers off a ray and the
## legs are geometry hung off it — so the leg length and the row's `hover` are
## two numbers that have to agree and NOTHING enforces it. The first AT-ST's feet
## finished three metres in the air, and a screenshot does not reliably show that
## (the shadow lands under it either way, and there is no other body in frame at
## walker scale). A number does.
func _test_war_machines() -> void:
	print("\n== the war machines ==")
	for id: String in Vehicle.STREAK_VEHICLES:
		var row: Dictionary = Vehicle.STREAK_VEHICLES[id]
		var v: Vehicle = VEHICLE_SCENE_new()
		add_child(v)               # ...or it has no global transform to measure
		v.setup_as(id, 0)
		v.global_position = Vector3(0, float(row["hover"]) + 6.0, 0)
		v.reset_physics_interpolation()
		for i in 180:
			await get_tree().physics_frame
		var clearance := v.global_position.y
		_expect(absf(clearance - float(row["hover"])) < 0.6,
			"%s settles at its own clearance (%.2f m, wants %.2f)"
				% [row["name"], clearance, float(row["hover"])])

		# THE LOWEST DRAWN POINT against the ground it is standing on. Measured off
		# the real meshes rather than off the table, because the table is exactly
		# what would be wrong.
		var lowest := INF
		for mi in v.find_children("*", "MeshInstance3D", true, false):
			var aabb: AABB = (mi as MeshInstance3D).get_aabb()
			for c in 8:
				var corner: Vector3 = (mi as MeshInstance3D).global_transform \
					* aabb.get_endpoint(c)
				lowest = minf(lowest, corner.y)
		# A WALKER stands on its feet; a GUNSHIP is meant to be off the ground.
		var walks: bool = float(row["hover"]) < 5.0
		if walks:
			_expect(absf(lowest) < 0.45,
				"%s stands ON the ground (lowest drawn point %.2f m)"
					% [row["name"], lowest])
		else:
			_expect(lowest > 1.5,
				"%s hangs clear of the ground (lowest drawn point %.2f m)"
					% [row["name"], lowest])
		print("    %-14s clearance %.2f m, lowest geometry %.2f m"
			% [row["name"], clearance, lowest])
		v.queue_free()
		await get_tree().physics_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## --- harness ------------------------------------------------------------------

class Dummy extends Node3D:
	var team := 0
	func is_alive() -> bool: return true


## A floor for the repulsor to find. The hover ray masks WORLD ONLY (layer 1), so
## this has to be on it — a floor on the players layer would be invisible to it,
## which is the mistake the mask exists to prevent.
func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	add_child(body)


func VEHICLE_SCENE_new() -> Vehicle:
	return VEHICLE.instantiate()


func _expect(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)
