extends Node3D
## WINDOWED. The two earned war machines, with a trooper beside them for scale.
##
##   godot --path godot --display-driver x11 --resolution 1280x620 tests/warmachine_look.tscn
##
## THE TROOPER IS THE POINT OF THE SHOT. These are rewards for a ten-kill streak
## and the whole feeling of one is that it is BIGGER than what you were — a
## walker photographed alone is just a shape, and every shape looks imposing with
## nothing next to it. The speeder is in frame for the same reason: what the
## reward has to beat is the thing already parked on the map.
##
## Shots land in user:// (~/.local/share/godot/app_userdata/QuadSquad/).

const VEHICLE := preload("res://scenes/actors/vehicle.tscn")


func _ready() -> void:
	_floor()
	_light()
	Grade.apply_to(self, 1.6)

	# A trooper at the origin as the yardstick.
	var man := CharacterModel.new()
	add_child(man)
	man.set_style(CharacterModel.Style.CLONE)
	man.set_render_layers(1)
	man.position = Vector3(-1.0, 0, 6.4)

	var laat := await _spawn("laat", 0, Vector3(2.0, 0, -1.0))
	var atst := await _spawn("atst", 2, Vector3(-1.5, 0, 2.5))
	var barc := await _spawn("", 0, Vector3(-4.0, 0, -2.0))
	print("  LAAT %.1f m long, AT-ST %.1f m tall, BARC %.1f m long" % [
		laat._row["hull"].z, atst._row["hull"].y + atst._row["hover"],
		barc._row["hull"].z])

	var cam := Camera3D.new()
	add_child(cam)
	# Low and off to one side: an emplacement or a vehicle is judged from where a
	# player meets it, which is on foot at about twelve metres.
	cam.position = Vector3(11.0, 3.4, 15.5)
	cam.look_at(Vector3(-0.5, 2.6, 1.0), Vector3.UP)
	cam.current = true
	await _frames(30)
	_shoot("warmachine_group")

	# ...and each alone, front three-quarter, because a group shot cannot show
	# whether one of them reads from its own front.
	for pair in [[laat, "laat"], [atst, "atst"]]:
		var v: Vehicle = pair[0]
		cam.position = v.global_position + Vector3(6.0, -4.2, 9.0)
		cam.look_at(v.global_position + Vector3.UP * 0.6, Vector3.UP)
		await _frames(10)
		_shoot("warmachine_%s" % pair[1])
	print("done")
	get_tree().quit()


func _spawn(row_id: String, team: int, at: Vector3) -> Vehicle:
	var v: Vehicle = VEHICLE.instantiate()
	add_child(v)
	await _frames(1)
	if row_id == "":
		v.setup(team)
	else:
		v.setup_as(row_id, team)
	v.global_position = at
	return v


func _shoot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://%s.png" % name)
	print("  user://%s.png" % name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _floor() -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(90, 90)
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.31, 0.32, 0.34)
	mat.metallic = 0.0
	mat.roughness = 0.9
	mi.material_override = mat
	add_child(mi)
	# A COLLIDER, not just a plane. Every one of these holds itself up off a
	# downward ray masked to layer 1 (see Vehicle) — with nothing to hit, they
	# rest on the deck and a gunship photographed lying on its skids is a pile of
	# boxes. The first version of this test did exactly that.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(90, 2, 90)
	shape.shape = box
	shape.position = Vector3(0, -1, 0)
	body.add_child(shape)


func _light() -> void:
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.rotation_degrees = Vector3(-40, 137, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.38, 0.46)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.46, 0.51, 0.58)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)
