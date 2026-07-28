extends Node3D

## What the new universes LOOK like — the one thing no headless test can judge.
## Lines up every unit of a universe side by side, third person, and then puts a
## representative weapon from each armoury in first-person hands.
##
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/universe_look.tscn
##
## Windowed, because a renderer is the point (the same rule guard_look and
## death_look follow). Shots land in user://
## (~/.local/share/godot/app_userdata/QuadSquad/).
##
## The body line-ups are what to check first: every one of these shares ONE
## skeleton and one set of animations, so if a Spartan reads as a Spartan and an
## ork reads as an ork, the head/bulk/accessory table is carrying the whole job.

const PLAYER := preload("res://scenes/actors/player.tscn")

## Each row: the file tag, and the styles standing in it.
const LINEUPS := [
	["halo_unsc", [CharacterModel.Style.SPARTAN, CharacterModel.Style.ODST,
		CharacterModel.Style.MARINE]],
	["halo_covenant", [CharacterModel.Style.ELITE, CharacterModel.Style.GRUNT,
		CharacterModel.Style.BRUTE]],
	["wh_astartes", [CharacterModel.Style.ULTRAMARINE,
		CharacterModel.Style.BLOOD_ANGEL]],
	["wh_xenos", [CharacterModel.Style.NECRON, CharacterModel.Style.NECRON_LORD,
		CharacterModel.Style.ORK, CharacterModel.Style.ORK_NOB]],
]

## First-person shots: one gun from each armoury plus every kind of melee, since
## the blade builder is the part that is newly parameterised.
const GUNS := [
	["ma5b", Weapon.Class.MA5B],
	["needler", Weapon.Class.NEEDLER],
	["energy_sword", Weapon.Class.ENERGY_SWORD],
	["grav_hammer", Weapon.Class.GRAV_HAMMER],
	["bolter", Weapon.Class.BOLTER],
	["chainsword", Weapon.Class.CHAINSWORD],
	["thunder_hammer", Weapon.Class.THUNDER_HAMMER],
	["warscythe", Weapon.Class.WARSCYTHE],
	["gauss_flayer", Weapon.Class.GAUSS_FLAYER],
	["big_shoota", Weapon.Class.BIG_SHOOTA],
	["power_klaw", Weapon.Class.POWER_KLAW],
]

var _models: Array[CharacterModel] = []


func _ready() -> void:
	GameState.match_live = true
	_build_floor()
	_light()

	# --- the bodies, from outside ---------------------------------------------
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	for row in LINEUPS:
		_lay_out(row[1])
		# Frame the row: back off in proportion to how many are standing in it,
		# and stand on the NEGATIVE z side — the model faces -Z (that is where its
		# barrel points), so a camera at +z photographs the backs of everybody.
		var span: float = float(row[1].size())
		cam.global_transform = Transform3D(Basis(),
			Vector3(0.0, 1.0, -(1.4 + span * 0.85)))
		cam.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)
		await _frames(6)
		await _grab(row[0])
		# ...and again from close up. The HEAD is the loudest part of a
		# silhouette and the only part of these that is genuinely new geometry,
		# so it gets a shot where you can actually see it: a Sangheili's split
		# mandibles and an ork's jaw are four boxes each and either read or don't.
		cam.global_transform = Transform3D(Basis(),
			Vector3(0.0, 1.62, -(0.55 + span * 0.42)))
		cam.look_at(Vector3(0.0, 1.58, 0.0), Vector3.UP)
		await _frames(4)
		await _grab("%s_heads" % row[0])
	_clear_models()

	# --- the CARRY, which is a three-quarter shot or it is nothing -------------
	# A rifle held on the right shoulder is an ASYMMETRIC pose, so it cannot be
	# judged head-on: from directly in front the weapon foreshortens to a bar and
	# both arms hide behind the torso. These are the shots that say whether the
	# hands are actually on the grips.
	for style in [CharacterModel.Style.SPARTAN, CharacterModel.Style.ULTRAMARINE,
			CharacterModel.Style.B1]:
		_lay_out([style])
		for shot in [["front", 0.0], ["quarter", 0.9], ["side", 1.55], ["run", 0.9]]:
			if shot[0] == "run":
				# The SPRINT CARRY: the run clip stows the weapon across the chest,
				# and that is judged in three-quarters like the standing hold.
				for m in _models:
					if m.anim_player != null:
						m.anim_player.play("run")
						m.anim_player.seek(CharacterModel.RUN_LEN * 0.25, true)
			var a: float = shot[1]
			cam.global_transform = Transform3D(Basis(),
				Vector3(sin(a) * 2.1, 1.35, -cos(a) * 2.1))
			cam.look_at(Vector3(0.0, 1.15, 0.0), Vector3.UP)
			await _frames(4)
			await _grab("carry_%d_%s" % [style, shot[0]])
	_clear_models()

	# --- and the weapons, from the inside -------------------------------------
	var me := await _spawn()
	me.bind_camera(cam)
	await _frames(4)
	for shot in GUNS:
		var build := Loadout.new()
		build.primary_override = shot[1]   # bypasses the kit rules; this is a photo
		me.pending = build
		me._apply_loadout()
		await _frames(8)
		print("  in hand: %s" % me.weapon.display_name())
		await _grab("gun_%s" % shot[0])
	# ...and the FIRST-PERSON SPRINT CARRY, which is the same idea as the run
	# clip's and the only one the player themselves can see. Shot on a rifle,
	# because a blade ignores it (see Weapon.set_sprinting).
	var rifle := Loadout.new()
	rifle.weapon = Loadout.weapon_index(Weapon.Class.SOLDIER)
	me.pending = rifle
	me._apply_loadout()
	await _frames(8)
	await _grab("sprint_ready")
	me.weapon.set_sprinting(true)
	await _frames(30)
	await _grab("sprint_stowed")

	get_tree().quit()


## One model per style, evenly spaced and facing the camera, holding a rifle so
## the solved carry pose is in the shot too.
func _lay_out(styles: Array) -> void:
	_clear_models()
	var span := 1.15
	var start := -span * (styles.size() - 1) * 0.5
	for i in styles.size():
		var m := CharacterModel.new()
		add_child(m)
		m.set_style(styles[i])
		m.set_team_color(GameState.team_colors[i % GameState.team_colors.size()])
		m.position = Vector3(start + span * i, 0.0, 0.0)
		# PLAY something. A bare model sits in its rest pose with both arms hanging
		# — which is not a pose the game ever shows, and photographing it hid the
		# fact that the carry was being judged from geometry alone.
		if m.anim_player != null:
			m.anim_player.play("idle")
			m.anim_player.seek(0.0, true)
		_models.append(m)


func _clear_models() -> void:
	for m in _models:
		if is_instance_valid(m):
			remove_child(m)
			m.queue_free()
	_models.clear()


func _grab(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "user://universe_%s.png" % tag
	img.save_png(path)
	print("wrote %s" % ProjectSettings.globalize_path(path))


func _light() -> void:
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(35.0), 0.0)
	key.light_energy = 1.1
	add_child(key)
	var fill := DirectionalLight3D.new()   # shadowless opposing fill (see Gotchas)
	fill.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(-150.0), 0.0)
	fill.light_energy = 0.4
	fill.shadow_enabled = false
	add_child(fill)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.48, 0.55)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	# Grade it exactly as a real map is graded, or this test photographs a
	# lighting model the game does not ship — which is the whole failure mode a
	# look test exists to catch.
	Grade.apply_to(self)


func _build_floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 2.0, 60.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(shape)
	body.collision_layer = 1
	var mi := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(60.0, 2.0, 60.0)
	mi.mesh = plane
	mi.position = Vector3(0.0, -1.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.25, 0.28)
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)


func _spawn() -> Player:
	var p: Player = PLAYER.instantiate()
	p.input_device = -1
	p.player_index = 0
	add_child(p)
	await get_tree().physics_frame
	p.pending = Loadout.new()
	p._apply_loadout()
	await get_tree().physics_frame
	return p


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
