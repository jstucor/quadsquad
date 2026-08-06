extends Node3D
## WINDOWED. THE HIP SWIVEL THAT REPLACED THE SIDESTEP.
##
##   godot --path godot --display-driver x11 --resolution 1500x560 tests/swivel_look.tscn
##
## Five bodies, all AIMING AT THE CAMERA and each travelling a different way, so
## the only thing that differs between them is what the legs did about it. That
## is the comparison the old sidestep sheet was making too — a body photographed
## alone reads as fine whatever its legs are doing.
const SPACING := 1.25
const WIND_UP := 40

func _ready() -> void:
	_floor(); _light(); Grade.apply_to(self, 1.6)
	# label, travel in the body's own frame (-z forward, +x right)
	var cases := [
		["FORWARD", Vector3(0, 0, -3.0)],
		["FWD-RIGHT", Vector3(2.1, 0, -2.1)],
		["RIGHT", Vector3(3.0, 0, 0)],
		["BACK-RIGHT", Vector3(2.1, 0, 2.1)],
		["BACK", Vector3(0, 0, 3.0)],
	]
	var models: Array[CharacterModel] = []
	for i in cases.size():
		var m := CharacterModel.new()
		add_child(m)
		m.position = Vector3((i - (cases.size() - 1) * 0.5) * SPACING, 0.0, 0.0)
		m.set_style(0)
		m.set_render_layers(1)
		await get_tree().process_frame
		var loco := Locomotion.new()
		loco.setup(m.anim_player, m)
		for _f in WIND_UP:
			loco.tick(1.0 / 60.0, cases[i][1], 0.0, false, false, false, false)
		models.append(m)
		print("  %-11s clip %-10s hips %+.0f deg" % [cases[i][0],
			m.anim_player.assigned_animation,
			rad_to_deg(Locomotion.swivel_for(Vector2(cases[i][1].x, cases[i][1].z)))])
	# Freeze them all on the same frame, so the legs' HEADING is the only
	# difference and not the phase of the stride.
	for m in models:
		m.anim_player.seek(0.35, true)
		m.anim_player.pause()
	await get_tree().process_frame
	var cam := Camera3D.new(); add_child(cam); cam.current = true
	cam.position = Vector3(0.0, 2.6, 3.9)
	cam.look_at(Vector3(0.0, 0.9, 0.0), Vector3.UP)
	await _grab("swivel_hips")
	get_tree().quit()

func _floor() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(24, 24); mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.22, 0.26); mat.metallic = 0.0; mat.roughness = 0.9
	mi.material_override = mat; add_child(mi)

func _light() -> void:
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-55), deg_to_rad(25), 0)
	key.light_energy = 1.6; add_child(key)
	var we := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.10, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.50, 0.58); e.ambient_light_energy = 0.8
	we.environment = e; add_child(we)

func _grab(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://shots")
	img.save_png("user://shots/%s.png" % name)
	print("wrote user://shots/%s.png" % name)
