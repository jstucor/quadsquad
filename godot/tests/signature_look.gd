extends Node3D
## WINDOWED. Every faction's signature reward, side by side.
##
##   godot --path godot --display-driver x11 --resolution 1400x520 tests/signature_look.tscn
##
## THE POINT IS THE LINE-UP AND NOT THE INDIVIDUALS. A signature is supposed to
## be the one thing its side has that nobody else does, so the only way to judge
## the set is to stand them next to each other and see whether ten of them are
## ten different things — which is exactly the check the roster line-ups exist
## for, and exactly the failure the first version had when six factions shared a
## generic Juggernaut.
##
## It also catches the silent one: **a head kind with no `match` case falls
## through to the BARE FACE and says nothing** (three units shipped that way
## once). There is no error for it, so a picture is the detector.

const YARDSTICK := 1.80


func _ready() -> void:
	_floor()
	_light()
	Grade.apply_to(self, 1.6)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true

	for u: int in [Loadout.Universe.STAR_WARS, Loadout.Universe.HALO,
			Loadout.Universe.WARHAMMER]:
		GameState.universe = u
		var sides: int = (Loadout.UNIVERSES[u]["teams"] as Array).size()
		var rows: Array[Dictionary] = []
		for t in mini(sides, 4):
			for row in Streaks.available(t):
				if int(row["kind"]) == Streaks.Kind.BECOME \
						and not row.get("shared", false):
					rows.append(Streaks.become_preset(row, t))
		if rows.is_empty():
			continue
		var built: Array[Node3D] = []
		for i in rows.size():
			var m := CharacterModel.new()
			add_child(m)
			m.position = Vector3((i - (rows.size() - 1) * 0.5) * 1.9, 0, 0)
			# TURNED TO FACE THE CAMERA. A model faces -Z by default and the camera
			# sits at +Z, so without this the whole line-up is photographed from
			# BEHIND — which hides every faceplate, weapon and chest accessory,
			# i.e. everything a signature is supposed to be recognised by.
			m.rotation.y = PI
			var build := Loadout.preset_build(rows[i])
			m.set_style(build.character_style())
			m.set_render_layers(1)
			m.scale = Vector3.ONE * build.stature()
			m.anim_player.play("idle")
			built.append(m)
			print("  %-18s style %d, %.2f m"
				% [rows[i]["name"], build.character_style(), YARDSTICK * build.stature()])
		# A POST AT A KNOWN HEIGHT, because "is this one bigger" is the whole
		# question a signature line-up answers and the eye cannot do it unaided.
		_post(Vector3((rows.size() * 0.5 + 0.6) * 1.9, 0, 0))
		await _frames(6)
		cam.position = Vector3(0, 1.15, 1.6 + rows.size() * 0.92)
		cam.look_at(Vector3(0, 1.05, 0), Vector3.UP)
		await _frames(4)
		var name := str(Loadout.UNIVERSES[u]["name"]).to_lower().replace(" ", "_")
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://signatures_%s.png" % name)
		print("  user://signatures_%s.png" % name)
		for m in built:
			m.queue_free()
		await _frames(2)
	print("done")
	get_tree().quit()


func _post(at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.chamfer_box(Vector3(0.12, YARDSTICK, 0.12))
	mi.position = at + Vector3(0, YARDSTICK * 0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.78, 0.30)
	mat.metallic = 0.0
	mat.roughness = 0.7
	mi.material_override = mat
	add_child(mi)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _floor() -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.31, 0.33)
	mat.metallic = 0.0
	mat.roughness = 0.9
	mi.material_override = mat
	add_child(mi)


func _light() -> void:
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.rotation_degrees = Vector3(-42, 150, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.30, 0.36, 0.44)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.46, 0.51, 0.58)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)
