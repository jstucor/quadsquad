extends Node3D
## WINDOWED. FEET ON THE GROUND, ON GROUND THAT IS NOT FLAT.
##
##   godot --path godot --display-driver x11 --resolution 1500x620 tests/plant_look.tscn
##
## A flat floor cannot judge this — every foot is at y=0 whether it was solved or
## not, which is the same failure `grenade_throw` records about box floors. So the
## bodies stand on a SLOPE and on a STEP, which is exactly where a clip that
## plays joint angles without asking the ground puts one boot in the air and
## buries the other.
##
## Left pair: planting OFF, which is what shipped. Right pair: planting ON.
## Side by side, because a single body reads as fine on either.
const GAP := 1.5

func _ready() -> void:
	_ground(); _light(); Grade.apply_to(self, 1.6)
	await get_tree().physics_frame
	# label, x, plant?
	var cases := [["SLOPE off", -2.2, false], ["SLOPE on", -0.7, true],
		["STEP off", 0.9, false], ["STEP on", 2.4, true]]
	var locos: Array[Locomotion] = []
	var models: Array[CharacterModel] = []
	for c in cases:
		var m := CharacterModel.new()
		add_child(m)
		# SEAT IT ON WHATEVER IS ACTUALLY UNDER IT. A CharacterModel is a Node3D
		# and does not fall, so an earlier version of this left all four floating
		# at a fixed height — where the probe finds ground far below, nothing is
		# ever within PLANT_BAND, and the sheet compared planting-off against
		# planting-that-never-engaged.
		m.position = Vector3(c[1], _ground_at(c[1]), 0.0)
		m.set_style(0); m.set_render_layers(1)
		await get_tree().process_frame
		var l := Locomotion.new()
		l.setup(m.anim_player, m)
		l.plant_feet = c[2]
		locos.append(l); models.append(m)
	# Settle: run the tick so the probes fire and the feet find the ground.
	# BOTH KINDS OF FRAME. The probe is physics and the solve is idle (see
	# CharacterModel's note on process_priority), so a settle loop that only
	# awaits physics starves the half that actually moves the feet — an earlier
	# version ran 40 probes and 5 solves and reported the solve as broken.
	for _f in 40:
		for i in locos.size():
			locos[i].tick(1.0 / 60.0, Vector3.ZERO, 0.0, false, false, false, false)
		await get_tree().physics_frame
		await get_tree().process_frame
	# MEASURE THE ERROR, NOT THE HEIGHT. Two bodies side by side on a slope stand
	# at different heights, so comparing their ankle heights compares their
	# POSITIONS — which is what an earlier version of this did, and it made
	# planting look like it lifted the feet 28 cm. What matters is each foot
	# against the ground beneath THAT foot.
	for i in models.size():
		var worst := 0.0
		var each := PackedStringArray()
		for sn in ["L", "R"]:
			var a := models[i].get_node(NodePath(CharacterModel.PATHS["a" + sn])) as Node3D
			var want := _ground_under(a.global_position) + CharacterModel.FOOT_LIFT
			var err := a.global_position.y - want
			each.append("%s %+.0f" % [sn, err * 1000.0])
			worst = maxf(worst, absf(err))
		# ...AND WHETHER THE STANCE SURVIVED. The splay lives in the hip's
		# rotation, which is exactly what a solve is tempted to overwrite, so a
		# body whose feet are correct and whose legs are together has traded one
		# artefact for a worse one. Measured as the gap between the ankles.
		var aL := models[i].get_node(NodePath(CharacterModel.PATHS["aL"])) as Node3D
		var aR := models[i].get_node(NodePath(CharacterModel.PATHS["aR"])) as Node3D
		var stance := Vector2(aL.global_position.x - aR.global_position.x,
			aL.global_position.z - aR.global_position.z).length()
		print("  %-10s worst %3.0f mm   stance %.0f mm   per foot [%s]"
			% [cases[i][0], worst * 1000.0, stance * 1000.0, " ".join(each)])
	await get_tree().process_frame
	var cam := Camera3D.new(); add_child(cam); cam.current = true
	cam.position = Vector3(0.1, 0.95, 3.6)
	cam.look_at(Vector3(0.1, 0.55, 0.0), Vector3.UP)
	await _grab("plant_feet")
	get_tree().quit()

## A ramp under the left pair and a step under the right, both real colliders.
func _ground_under(at: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5, at + Vector3.DOWN * 2.0)
	q.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(q)
	return float((hit["position"] as Vector3).y) if not hit.is_empty() else 0.0


func _ground_at(x: float) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, 6.0, 0.0), Vector3(x, -4.0, 0.0))
	q.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(q)
	return float((hit["position"] as Vector3).y) if not hit.is_empty() else 0.0


func _ground() -> void:
	_slab(Vector3(20, 1, 20), Vector3(0, -0.5, 0), 0.0)
	_slab(Vector3(3.2, 0.6, 3.0), Vector3(-1.45, 0.0, 0.0), deg_to_rad(14.0))
	_slab(Vector3(1.5, 0.5, 3.0), Vector3(2.4, 0.25, 0.0), 0.0)

func _slab(size: Vector3, at: Vector3, tilt: float) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = size; cs.shape = bs
	body.add_child(cs); body.position = at; body.rotation.z = tilt
	body.collision_layer = 1
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size; mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.26, 0.30); mat.metallic = 0.0; mat.roughness = 0.9
	mi.material_override = mat; body.add_child(mi)
	add_child(body)

func _light() -> void:
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-38), deg_to_rad(28), 0); key.light_energy = 1.6
	add_child(key)
	var we := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.09, 0.10, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.50, 0.58); e.ambient_light_energy = 0.8
	we.environment = e; add_child(we)

func _grab(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://shots")
	img.save_png("user://shots/%s.png" % name)
	print("wrote user://shots/%s.png" % name)
