extends Node3D
## GRENADES, THROWN FOR REAL. Three complaints, three measurements — and every
## one of them is a number, because all three are the kind of thing that looks
## fine in one throw and is obviously wrong over twenty.
##
##   THROUGH THE FLOOR   the worst of the three, because a grenade under the map
##                       detonates where nobody is and the player who threw it
##                       sees their gadget do nothing and go on cooldown.
##   RANGE               a throw that cannot reach the cover you are shooting at
##                       is a gadget nobody fits.
##   ROLL                a grenade that trickles away down a slope lands
##                       somewhere you did not aim, which is worse than short.
##
## Thrown over a real floor with a slope on it, because flat ground is the case
## that already worked — rolling and tunnelling both need a gradient to show.
##
## Run:  godot --headless --path godot tests/grenade_throw.tscn

const GRENADE := preload("res://scenes/fx/grenade.tscn")

const THROWS := 24
const SETTLE := 1.6          # seconds to watch each throw for (under the fuse)
## The throw has to clear this to be worth fitting. It was 13 m/s before, which
## landed around fourteen metres — inside the range a rifle already owns.
const MIN_RANGE := 18.0
## How far it may travel AFTER first touching down. A grenade is aimed; a bowling
## ball is not.
const MAX_ROLL := 4.5
## Anything below this is through the world. The floor here is at y = 0.
const FLOOR := -0.6


var _failures := 0


func _ready() -> void:
	print("\n=== GRENADE THROW ===\n")
	_build_ground()
	await get_tree().physics_frame
	await _measure()
	print("")
	if _failures == 0:
		print("==== GRENADES LAND WHERE THEY ARE THROWN ====")
	else:
		print("==== %d FAILURE%s ====" % [_failures, "" if _failures == 1 else "S"])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["OK  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


## A TRIMESH HEIGHTFIELD, NOT A BOX, and this is the whole reason the test works.
##
## The first version laid down thick `BoxShape3D` slabs with a ramp — and it
## passed with BOTH tunnelling defences removed, which is a test proving nothing.
## A 0.11 m sphere moving 0.37 m in a tick cannot get through a one-metre-thick
## box; it can very easily get through a SURFACE. The real maps' floor is exactly
## that: `PlanetMap._build_terrain` commits one `ConcavePolygonShape3D` with
## `backface_collision` on, an infinitely thin skin over nothing at all.
##
## So this builds the same thing at the same cell size, with a gradient across it
## — a surface, at an angle, which is the only shape the bug lives in.
##
## MEASURED, three ways, once it was built out of the right thing:
##   neither defence      lowest point -0.05 m — sinking into the surface
##   CCD only             sits on it, never goes under
##   CCD + the floor guard   identical, because the guard never has to fire
##
## Which says two useful things. CCD is the fix and the guard is a backstop that
## earns its keep by costing nothing. And this slope is gentle enough that it
## only ever reproduced PENETRATION, not the full drop-through-the-world — so the
## guard is still doing a job this test cannot photograph.
const CELL := 2.2         # the same heightfield resolution PlanetMap uses
const GROUND_SPAN := 90.0


func _build_ground() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := GROUND_SPAN * 0.5
	var cols := int(GROUND_SPAN / CELL)
	for i in cols:
		for j in cols:
			var x0 := -half + i * CELL
			var z0 := -half + j * CELL
			var x1 := x0 + CELL
			var z1 := z0 + CELL
			_quad(st,
				Vector3(x0, _height(x0, z0), z0), Vector3(x1, _height(x1, z0), z0),
				Vector3(x1, _height(x1, z1), z1), Vector3(x0, _height(x0, z1), z1))
	st.generate_normals()
	var mesh := st.commit()
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	var shape := CollisionShape3D.new()
	var tri := ConcavePolygonShape3D.new()
	tri.set_faces(mesh.get_faces())
	tri.backface_collision = true   # as the real terrain does, and for the same reason
	shape.shape = tri
	body.add_child(shape)


## A slope to land on. Gentle enough to be walkable terrain (this project keeps
## every generated surface under 26 degrees) and quite steep enough to roll on.
func _height(x: float, z: float) -> float:
	return maxf(0.0, (-z - 6.0) * 0.20) + sin(x * 0.08) * 0.35


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v: Vector3 in [a, b, c, a, c, d]:
		st.add_vertex(v)


func _measure() -> void:
	var worst_low := 99.0
	var shortest := 999.0
	var longest_roll := 0.0
	var reached := 0.0
	for i in THROWS:
		# Fanned across a spread of angles, so this is not one lucky trajectory
		# repeated. Elevation matters most: a flat throw is the one that skips off
		# a ramp, a lobbed one is the one that lands hardest.
		var yaw := deg_to_rad(-24.0 + 48.0 * float(i) / float(THROWS - 1))
		var from := Vector3(0.0, 1.5, 6.0)
		var aim := Vector3(sin(yaw), 0.0, -cos(yaw)).normalized()
		var toss := (aim + Vector3.UP * Player.GRENADE_LOB).normalized() \
			* Player.GRENADE_THROW_SPEED

		var nade: RigidBody3D = GRENADE.instantiate()
		add_child(nade)
		nade.launch(from, toss, null, Loadout.GrenadeType.FRAG)

		var low := 99.0
		var touched := Vector3.ZERO
		var has_touched := false
		var frames := int(SETTLE * 60.0)
		for f in frames:
			await get_tree().physics_frame
			if not is_instance_valid(nade):
				break
			var p: Vector3 = nade.global_position
			low = minf(low, p.y)
			# First touchdown: where the roll is measured FROM. Read off the
			# grenade's own landed flag rather than guessed from height, so the
			# test and the code agree about what landing means.
			if not has_touched and bool(nade.get("_landed")):
				has_touched = true
				touched = p
		if not is_instance_valid(nade):
			continue
		var rest: Vector3 = nade.global_position
		var range_m := Vector2(rest.x - from.x, rest.z - from.z).length()
		var roll := Vector2(rest.x - touched.x, rest.z - touched.z).length() \
			if has_touched else 0.0
		worst_low = minf(worst_low, low)
		shortest = minf(shortest, range_m)
		longest_roll = maxf(longest_roll, roll)
		reached += range_m
		nade.queue_free()

	print("  throws              %d" % THROWS)
	print("  range               %.1f m average, %.1f m shortest"
		% [reached / float(THROWS), shortest])
	print("  roll after landing  %.2f m worst" % longest_roll)
	print("  lowest point        %.2f m  (floor is 0)" % worst_low)
	print("")
	_check(worst_low > FLOOR, "no grenade went through the floor")
	_check(shortest >= MIN_RANGE,
		"every throw carried at least %.0f m" % MIN_RANGE)
	_check(longest_roll <= MAX_ROLL,
		"none rolled more than %.1f m past where it landed" % MAX_ROLL)
