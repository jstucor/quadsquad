extends Node3D
## WHAT YOU CAN SHOOT OVER IS WHAT YOU CAN SEE.
##
## A generated map's structures are boxes to the nav grid and shapes to the eye
## (`PlanetMap._solid`), and for a long time they were boxes to PHYSICS too — so
## a spire was solid out to the full width of its base all the way to its tip and
## a round fired over the slope of a ridge stopped in mid-air on nothing.
##
## They now carry the shape's own convex hull, with the footprint box left in the
## tree DISABLED so `GameState.scan_map_geometry` still reads it. That is a
## subtle arrangement — re-enabling the box, or dropping it, breaks a different
## half of the game each way — so this checks both halves at once:
##
##   1. every shaped prop has a disabled box footprint AND a live convex hull,
##      and the footprint is still visible to the geometry scan;
##   2. a ray through the corner the SHAPE does not occupy passes, where the
##      bounding box would have stopped it.
##
##   godot --headless --path godot tests/prop_shapes.tscn
const LEVEL := preload("res://scenes/levels/planet.tscn")


func _ready() -> void:
	var fails: Array[String] = []
	var props := 0
	var freed := 0
	for planet in PlanetMap.PLANET_NAMES.size():
		GameState.planet = planet
		GameState.planet_seed = 4400 + planet * 31
		var t0 := Time.get_ticks_usec()
		var level: Node3D = LEVEL.instantiate()
		add_child(level)
		var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
		await get_tree().physics_frame
		await get_tree().physics_frame
		GameState.scan_map_geometry(level)
		var scanned := GameState.map_shapes.size()
		var pname: String = str(PlanetMap.PLANET_NAMES[planet])
		var shaped := 0
		var opened := 0
		var probed := 0
		for body in level.find_children("*", "StaticBody3D", true, false):
			if (body.collision_layer & 1) == 0:
				continue
			var mi: MeshInstance3D = null
			for child in body.get_children():
				if child is MeshInstance3D:
					mi = child
			# Boxes are exempt (their mesh IS their footprint) and so is the
			# terrain, which is an ArrayMesh on a trimesh collider and was never a
			# `_solid` at all.
			if mi == null or mi.mesh is BoxMesh or mi.mesh is ArrayMesh:
				continue
			shaped += 1
			props += 1
			var box: CollisionShape3D = null
			var hull: CollisionShape3D = null
			for cs in body.find_children("*", "CollisionShape3D", true, false):
				if cs.shape is BoxShape3D:
					box = cs
				elif cs.shape is ConvexPolygonShape3D:
					hull = cs
			if box == null:
				fails.append("%s: a %s prop has no box footprint — invisible to the nav grid" % [pname, mi.mesh.get_class()])
				continue
			if not box.disabled:
				fails.append("%s: a %s prop still COLLIDES as its bounding box"
					% [pname, mi.mesh.get_class()])
				continue
			if hull == null or hull.disabled:
				fails.append("%s: a %s prop has no live convex hull — it is a ghost" % [pname, mi.mesh.get_class()])
				continue
			# The probe. A ray through the part of the bounding box the shape does
			# not fill: the box would stop it, the shape must not.
			var res := _corner_ray(body, mi)
			if res.is_empty():
				continue
			probed += 1
			if res["hit"]:
				fails.append("%s: a %s prop still blocks a shot through its empty corner" % [pname, mi.mesh.get_class()])
			else:
				opened += 1
		print("%-11s %5.0f ms build  %4d shaped props  %4d/%-4d corners open  %5d scanned"
			% [pname, build_ms, shaped, opened, probed, scanned])
		if scanned == 0:
			fails.append("%s: the geometry scan found nothing" % pname)
		remove_child(level)
		level.queue_free()
		freed += 1
		await get_tree().process_frame

	print("")
	if fails.is_empty():
		print("==== %d SHAPED PROPS COLLIDE AS THEIR SHAPE ====" % props)
	else:
		for f in fails:
			print("FAIL  %s" % f)
		print("==== %d FAILURES ====" % fails.size())
	get_tree().quit()


## Fire the one ray whose answer differs between a box and the shape, picked per
## shape because they are empty in different places: a cylinder, cone or boulder
## leaves the box's vertical CORNERS empty, and a wedge tapers with HEIGHT, so
## its gap is up the sloped side rather than at a corner.
func _corner_ray(body: StaticBody3D, mi: MeshInstance3D) -> Dictionary:
	var aabb := mi.mesh.get_aabb()
	var from := Vector3.ZERO
	var to := Vector3.ZERO
	if mi.mesh is PrismMesh:
		# Along the ridge-facing side, above half height: the slab has narrowed.
		var y := aabb.position.y + aabb.size.y * 0.86
		var x := aabb.size.x * 0.42
		from = Vector3(x, y, -aabb.size.z)
		to = Vector3(x, y, aabb.size.z)
	else:
		# Straight down the box's XZ corner, which no round section reaches.
		var x := aabb.size.x * 0.45
		var z := aabb.size.z * 0.45
		from = Vector3(x, aabb.position.y + aabb.size.y + 1.0, z)
		to = Vector3(x, aabb.position.y - 1.0, z)
	var space := body.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		body.to_global(from), body.to_global(to))
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	# Only this body's answer matters — the terrain or a neighbour standing in the
	# way says nothing about whether THIS prop is a box.
	return {"hit": not hit.is_empty() and hit.get("collider") == body}
