extends Node
## DO ZONES, CONQUEST AND ROYALE ACTUALLY WORK ON THE MAPS WE SHIP?
##
##   godot --headless --path godot tests/modes_on_maps.tscn
##
## Every one of these modes puts something on the ground and then waits for
## people to go to it — a capture area, a command post, a crate. Nothing checks
## that the thing landed anywhere reachable, and each mode used to cast its OWN
## ray straight down from 80 or 120 m to decide. That is right on open ground and
## wrong the moment a map has a ROOF: the ray stops on the ceiling, and the round
## is played underneath a capture point sitting on the roof, with the clock
## waiting for somebody who cannot get there.
##
## IT FAILS SILENTLY IN THE WORST WAY. Nothing errors. Zones runs, scores nobody
## and never ends; Conquest lays every post out of reach so no side ever bleeds;
## royale scatters loot inside walls. All three look like balance problems.
##
## So: boot each mode on the roofed map AND on an outdoor one, and ask the two
## questions that matter — is it ON THE FLOOR, and can a body STAND there.

const MAIN := preload("res://scenes/main.tscn")

var _fails: Array[String] = []
var _done: Array[String] = []


func _ready() -> void:
	# The Outpost first, because it is the map with a lid — every fault here was
	# invisible until a roofed map existed.
	await _check_zones("OUTPOST")
	await _check_conquest("OUTPOST")
	await _check_royale("OUTPOST")
	# ...and one outdoor map, because a fix for a ceiling that broke open ground
	# would be a worse trade than the bug.
	await _check_zones("CROSSFIRE")
	await _check_conquest("GEONOSIS (GENERATED)")

	for want in ["zones OUTPOST", "conquest OUTPOST", "royale OUTPOST",
			"zones CROSSFIRE", "conquest GEONOSIS (GENERATED)"]:
		if not _done.has(want):
			_fails.append("the `%s` section never finished — it aborted part way" % want)
	print("\n==== %s ====" % ("EVERY MODE PLAYS ON EVERY MAP" if _fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [_fails.size(), "\n  ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)


## THE CAPTURE AREA, over several relocations — it moves every 30 s, so checking
## where it opened says nothing about where it goes.
func _check_zones(map_name: String) -> void:
	var main := await _boot(map_name, GameState.Mode.ZONES)
	var zone: Node3D = main.zone
	if zone == null:
		_fail("zones %s: no capture area was built at all" % map_name)
		await _drop(main)
		return
	var worst := 0.0
	var unstandable := 0
	for i in 6:
		var at: Vector3 = zone.global_position
		var floor_y := _floor_under(main, at)
		worst = maxf(worst, absf(at.y - floor_y))
		if not GameState.standable(at):
			unstandable += 1
		zone._relocate()
		await get_tree().physics_frame
	print("  zones %-22s worst %.2f m off the floor, %d of 6 spots unstandable"
		% [map_name, worst, unstandable])
	# A metre of tolerance: the area is placed on the surface and the surface is
	# a collision mesh that sits a little above its own analytic curve.
	_ok(worst < 1.2, "zones %s: the capture area is ON THE FLOOR (worst %.2f m off)"
		% [map_name, worst])
	_ok(unstandable == 0,
		"zones %s: every spot it moves to is somewhere a body can stand" % map_name)
	_done.append("zones %s" % map_name)
	await _drop(main)


## THE COMMAND POSTS, which are laid along a line and therefore the placement
## most likely to end up inside a wall.
func _check_conquest(map_name: String) -> void:
	var main := await _boot(map_name, GameState.Mode.CONQUEST)
	var posts := GameState.conquest_posts
	_ok(posts.size() >= 3, "conquest %s: the posts were laid (%d)" % [map_name, posts.size()])
	var worst := 0.0
	var unstandable := 0
	for p in posts:
		if not is_instance_valid(p):
			continue
		var floor_y := _floor_under(main, p.global_position)
		worst = maxf(worst, absf(p.global_position.y - floor_y))
		if not GameState.standable(p.global_position):
			unstandable += 1
	print("  conquest %-19s worst %.2f m off the floor, %d of %d posts unstandable"
		% [map_name, worst, unstandable, posts.size()])
	_ok(worst < 1.2, "conquest %s: every post is ON THE FLOOR (worst %.2f m off)"
		% [map_name, worst])
	_ok(unstandable == 0,
		"conquest %s: every post is somewhere a body can stand" % map_name)
	_done.append("conquest %s" % map_name)
	await _drop(main)


## THE LOOT. A crate in a wall is a crate nobody can have, and in royale the gear
## on the ground is the whole mode.
func _check_royale(map_name: String) -> void:
	var main := await _boot(map_name, GameState.Mode.ROYALE)
	var crates: Array = main.level.find_children("*", "Pickup", true, false) \
		if main.level != null else []
	_ok(crates.size() > 10, "royale %s: gear was scattered (%d crates)"
		% [map_name, crates.size()])
	var worst := 0.0
	var unstandable := 0
	for c in crates:
		var floor_y := _floor_under(main, c.global_position)
		worst = maxf(worst, absf(c.global_position.y - 0.6 - floor_y))
		if not GameState.standable(c.global_position):
			unstandable += 1
	var bad := 100.0 * float(unstandable) / float(maxi(crates.size(), 1))
	print("  royale %-21s worst %.2f m off the floor, %.0f%% of crates unreachable"
		% [map_name, worst, bad])
	_ok(worst < 1.5, "royale %s: the crates sit on the floor (worst %.2f m off)"
		% [map_name, worst])
	# A few per cent is a crate against a wall the grid pads out; a fifth of them
	# is loot scattered into the walls.
	_ok(bad < 8.0, "royale %s: the gear is reachable (%.0f%% is not)" % [map_name, bad])
	# ...and the storm has to be able to close on this map at all.
	var storm: Node3D = main.find_children("*", "Storm", true, false)[0] \
		if not main.find_children("*", "Storm", true, false).is_empty() else null
	_ok(storm != null, "royale %s: the storm exists" % map_name)
	_done.append("royale %s" % map_name)
	await _drop(main)


## The floor under a point, asked the way the game asks it — which is the whole
## fix under test, so a failure here is the thing itself and not the harness.
func _floor_under(main: Node, at: Vector3) -> float:
	var hit: Variant = GameState.ground_at(main.level, at.x, at.z)
	return (hit as Vector3).y if hit != null else -999.0


func _boot(map_name: String, mode: int) -> Node:
	GameState.human_players = 1
	GameState.team_count = 2
	GameState.free_for_all = false
	GameState.mode = mode
	GameState.chosen_teams = []
	GameState.planet_seed = 90210
	for i in GameState.MAPS.size():
		if str(GameState.MAPS[i]["name"]) == map_name:
			GameState.map_index = i
	var main: Node = MAIN.instantiate()
	add_child(main)
	# The zone and the posts place themselves on their first PHYSICS frame, not
	# in `_ready` — their placement rays need colliders that are not in the
	# physics world yet. Waiting on process frames alone photographs them at the
	# origin.
	for i in 30:
		await get_tree().physics_frame
	return main


## GET THE LAST MAP OUT OF THE WORLD BEFORE BOOTING THE NEXT ONE, and give it
## PHYSICS frames to happen in.
##
## `queue_free` takes effect at the end of the frame and the bodies leave the
## physics world after that — so one process frame is not enough, and this test
## spent a run reporting the OUTPOST's roof at 7.5 m under a capture area on
## CROSSFIRE, which has no roof at all. Every placement ray in the next map was
## hitting the previous map's ceiling. The give-away was the number: the same
## 7.50 on two maps that share no geometry is never a map's own fault.
func _drop(main: Node) -> void:
	main.queue_free()
	for i in 6:
		await get_tree().physics_frame


func _ok(cond: bool, what: String) -> void:
	if not cond:
		_fail(what)


func _fail(what: String) -> void:
	print("  FAIL %s" % what)
	_fails.append(what)
