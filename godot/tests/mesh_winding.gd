extends Node3D
## IS ANY GENERATED MESH INSIDE OUT?
##
##   godot --headless --path godot tests/mesh_winding.tscn
##
## `chamfer.gd` asks this of ONE mesh — the chamfered box — because that is the
## one every body part and every gun part is made of. This asks it of everything
## ELSE the game generates: characters in every style, every weapon's viewmodel,
## the vehicles, the deployables, and a whole generated world with its terrain,
## its structures and its props.
##
## WHY IT IS WORTH ITS OWN TEST. Inverted winding is the most expensive class of
## bug this project has had and it does not look like itself: with back faces
## culled, a solid whose triangles are wound the wrong way shows you its INSIDE,
## which reads as the model being transparent, or as a hole in it, or (when the
## normals disagree with the winding) as a lighting fault that sends you off
## tuning materials and sun angles. There is no error anywhere. The terrain cost
## a session to exactly this.
##
## TWO INDEPENDENT CHECKS, because each catches what the other cannot:
##
##   1. WINDING vs the stored NORMALS, per triangle. Godot's front face is the
##      CLOCKWISE one, so for correct geometry `cross(b - a, c - a)` points the
##      OPPOSITE way to the outward vertex normal. When those two agree instead,
##      the lit side and the visible side are opposite faces — which is the
##      "transparent" symptom exactly. It works on open surfaces (a terrain skin,
##      a quad, a decal) as well as on solids.
##   2. SIGNED VOLUME (the divergence theorem), which for a correctly wound closed
##      solid comes out NEGATIVE in this convention. Meaningless for an open
##      surface, so it is only asserted alongside a majority of bad triangles.
##
## THE CONVENTION IS TAKEN FROM THE ENGINE AT RUN TIME, not written down here.
## That is the whole lesson of the bug this test was written for: `chamfer.gd`
## stated the sign from memory, stated it backwards, and every model in the game
## was inside out behind a passing test.

const CHARACTER := preload("res://scripts/character.gd")
const VIEWMODEL := preload("res://scripts/viewmodel.gd")
const VEHICLE := preload("res://scenes/actors/vehicle.tscn")
const TURRET := preload("res://scenes/actors/turret.tscn")
const MORTAR := preload("res://scenes/actors/mortar.tscn")
## THE GUNSHIP IS NOT A `Vehicle` (it flies its own circuit and you ride the ball
## turret), so it is not in `STREAK_VEHICLES` and would be the one war machine
## nothing here ever looked at.
const GUNSHIP := preload("res://scripts/gunship.gd")

## How many triangles may disagree with their own normals before it is a fault
## rather than a rounding artefact. Zero would be right for a box; a swept or
## welded surface can have a degenerate sliver whose geometric normal is noise,
## so the bar is a FRACTION and it is deliberately tight.
const BAD_FRACTION := 0.02

var _fails: Array[String] = []
var _checked := 0
var _worst := {}
## Which way round the ENGINE does it, measured from its own BoxMesh rather than
## stated. See the header.
var _want := 1.0            # sign of dot(face normal, vertex normal)
var _want_volume := 1.0     # ...and of a closed solid's signed volume


func _ready() -> void:
	_calibrate()
	await _characters()
	await _viewmodels()
	await _vehicles()
	await _deployables()
	await _generated_world()

	print("\n%d meshes checked" % _checked)
	if not _worst.is_empty():
		print("worst offenders:")
		for name in _worst:
			print("  %-42s %s" % [name, _worst[name]])
	print("\n==== %s ====" % ("EVERY GENERATED MESH FACES OUTWARD" if _fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [_fails.size(), "\n  ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)


## Ask Godot's own box which way round a correct mesh is.
func _calibrate() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var arrays: Array = box.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var a := verts[idx[0]]
	var b := verts[idx[1]]
	var c := verts[idx[2]]
	_want = signf((b - a).cross(c - a).normalized().dot(
		(norms[idx[0]] + norms[idx[1]] + norms[idx[2]]).normalized()))
	var vol := 0.0
	var t := 0
	while t + 2 < idx.size():
		vol += verts[idx[t]].dot(verts[idx[t + 1]].cross(verts[idx[t + 2]])) / 6.0
		t += 3
	_want_volume = signf(vol)
	print("calibrated against the engine's BoxMesh: winding-vs-normal %+.0f, volume %+.0f"
		% [_want, _want_volume])


func _characters() -> void:
	print("== characters ==")
	for style in CharacterModel.STYLES:
		var body: CharacterModel = CHARACTER.new()
		add_child(body)
		body.set_style(style)
		await get_tree().process_frame
		_walk(body, "character %s" % CharacterModel.Style.keys()[style])
		body.queue_free()
		await get_tree().process_frame


func _viewmodels() -> void:
	print("\n== viewmodels ==")
	for c in Weapon.PROFILES.size():
		# Under a plain Node3D stand-in for the Weapon anchor, with its own
		# processing OFF: the gun is BUILT by `configure` and everything `_process`
		# does after that is bob, recoil and the ADS slide, which need an owner
		# this test has no reason to build and which move nothing about the
		# geometry being measured.
		var anchor := Node3D.new()
		add_child(anchor)
		var vm: Node3D = VIEWMODEL.new()
		anchor.add_child(vm)
		vm.set_process(false)
		vm.configure(c)
		await get_tree().process_frame
		_walk(vm, "viewmodel %s" % Weapon.Class.keys()[c])
		anchor.queue_free()
		await get_tree().process_frame


func _vehicles() -> void:
	print("\n== vehicles ==")
	# One speeder per faction, then the two earned war machines — the AT-ST and
	# the LAAT are where the vehicle builders stop being boxes (cylinders for the
	# hubs, swept struts for the legs), so they are the ones with something to get
	# wrong.
	for team in Vehicle.VEHICLES:
		var v: Node3D = VEHICLE.instantiate()
		add_child(v)
		v.setup(int(team))
		await get_tree().process_frame
		_walk(v, "speeder %s" % str(Vehicle.VEHICLES[team]["name"]))
		v.queue_free()
		await get_tree().process_frame
	for id in Vehicle.STREAK_VEHICLES:
		var v: Node3D = VEHICLE.instantiate()
		add_child(v)
		v.setup_as(str(id), 0)
		await get_tree().process_frame
		_walk(v, "war machine %s" % str(Vehicle.STREAK_VEHICLES[id]["name"]))
		v.queue_free()
		await get_tree().process_frame
	# ...and the LAAT, built without `begin()` so it does not fly off on a circuit
	# while it is being measured — the same way `warmachine_look` photographs it.
	var laat: Node3D = GUNSHIP.new()
	add_child(laat)
	laat.team = 0
	laat._build()          # the airframe only; `begin()` would seat a player
	await get_tree().process_frame
	_walk(laat, "war machine LAAT GUNSHIP")
	laat.queue_free()
	await get_tree().process_frame


func _deployables() -> void:
	print("\n== deployables ==")
	for spec: Array in [[TURRET, "turret"], [MORTAR, "mortar"]]:
		var node: Node3D = (spec[0] as PackedScene).instantiate()
		add_child(node)
		await get_tree().process_frame
		_walk(node, str(spec[1]))
		node.queue_free()
		await get_tree().process_frame


## The generated world: terrain chunks, structures, greebles, foliage — the ones
## with the history. Every planet, because each lays out its own landmarks and a
## builder used by one world only would otherwise never be looked at.
func _generated_world() -> void:
	print("\n== generated worlds ==")
	for planet in PlanetMap.PLANET_NAMES:
		GameState.map_index = GameState.procedural_map_index()
		GameState.planet = planet
		GameState.planet_seed = 12345 + planet
		var level: Node3D = GameState.MAPS[GameState.map_index]["scene"].instantiate()
		add_child(level)
		await get_tree().process_frame
		await get_tree().physics_frame
		_walk(level, "world %s" % PlanetMap.PLANET_NAMES[planet])
		level.queue_free()
		await get_tree().process_frame
	GameState.planet = GameState.RANDOM_PLANET
	GameState.map_index = 0


# --- the check ----------------------------------------------------------------

func _walk(root: Node, label: String) -> void:
	var meshes: Array[Mesh] = []
	var names: Array[String] = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).mesh != null:
			meshes.append((mi as MeshInstance3D).mesh)
			names.append(mi.name)
	for mm in root.find_children("*", "MultiMeshInstance3D", true, false):
		var multi: MultiMesh = (mm as MultiMeshInstance3D).multimesh
		if multi != null and multi.mesh != null:
			meshes.append(multi.mesh)
			names.append(mm.name)
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		meshes.append((root as MeshInstance3D).mesh)
		names.append(root.name)

	var flipped := 0
	var worst := 0.0
	var worst_name := ""
	for i in meshes.size():
		var report := _inspect(meshes[i])
		if report.is_empty():
			continue
		_checked += 1
		var bad: float = report["bad_fraction"]
		if bad > worst:
			worst = bad
			worst_name = names[i]
		if bad > BAD_FRACTION or bool(report["inside_out"]):
			flipped += 1
			_fails.append("%s: `%s` is inside out (%.0f%% of triangles disagree with their normals%s)"
				% [label, names[i], bad * 100.0,
				", signed volume negative" if report["inside_out"] else ""])
	print("  %-34s %3d meshes   worst %5.1f%% (%s)   %s" % [
		label, meshes.size(), worst * 100.0, worst_name,
		"ok" if flipped == 0 else "%d INSIDE OUT" % flipped])
	if worst > 0.0:
		_worst[label] = "%.1f%% on `%s`" % [worst * 100.0, worst_name]


## One mesh, surface by surface. Returns {} for anything with no triangles to
## judge (a point cloud, an empty surface).
func _inspect(mesh: Mesh) -> Dictionary:
	var tris := 0
	var bad := 0
	var volume := 0.0
	var closed := true
	# `surface_get_primitive_type` is an ArrayMesh method — a PrimitiveMesh (Box,
	# Sphere, Prism, Cylinder, the engine's own generators) does not have it, and
	# calling it there aborts this whole function silently (house rule 6), which
	# would skip exactly the meshes the question is about while still printing a
	# pass. They are triangles by definition.
	var array_mesh := mesh as ArrayMesh
	for s in mesh.get_surface_count():
		if array_mesh != null and array_mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays: Array = mesh.surface_get_arrays(s)
		if arrays.is_empty():
			continue
		# UNTYPED ON PURPOSE, then converted. A surface with no index buffer hands
		# back Nil here, and assigning Nil to a typed PackedInt32Array aborts this
		# whole function (house rule 6) — which is not a failure, it is 205 meshes
		# quietly never checked behind a run that said everything was fine.
		var raw_verts = arrays[Mesh.ARRAY_VERTEX]
		var raw_norms = arrays[Mesh.ARRAY_NORMAL]
		var raw_idx = arrays[Mesh.ARRAY_INDEX]
		if raw_verts == null:
			continue
		var verts: PackedVector3Array = raw_verts
		var norms: PackedVector3Array = raw_norms if raw_norms != null else PackedVector3Array()
		var idx: PackedInt32Array = raw_idx if raw_idx != null else PackedInt32Array()
		if verts.is_empty():
			continue
		if norms.is_empty():
			closed = false       # nothing to compare a winding against
		var count := idx.size() if not idx.is_empty() else verts.size()
		var t := 0
		while t + 2 < count:
			var ia := idx[t] if not idx.is_empty() else t
			var ib := idx[t + 1] if not idx.is_empty() else t + 1
			var ic := idx[t + 2] if not idx.is_empty() else t + 2
			var a := verts[ia]
			var b := verts[ib]
			var c := verts[ic]
			# The same convention `chamfer.gd` asserts: positive total volume is
			# an outward-facing solid.
			volume += a.dot(b.cross(c)) / 6.0
			if not norms.is_empty():
				var face := (b - a).cross(c - a)
				if face.length_squared() > 1e-12:
					var given := (norms[ia] + norms[ib] + norms[ic])
					if given.length_squared() > 1e-12 \
							and signf(face.normalized().dot(given.normalized())) != _want:
						bad += 1
			tris += 1
			t += 3
	if tris == 0:
		return {}
	# A NEGATIVE VOLUME ONLY MEANS ANYTHING FOR A CLOSED SOLID. An open surface —
	# a terrain skin, a quad, a decal — has no inside, so its "volume" is an
	# artefact of where the origin happens to sit and must not be asserted on.
	# The winding-vs-normals check above is the one that covers those.
	return {
		"bad_fraction": float(bad) / float(tris),
		"inside_out": closed and signf(volume) != _want_volume \
			and float(bad) / float(tris) > BAD_FRACTION,
		"triangles": tris,
	}
