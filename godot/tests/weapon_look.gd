extends Node3D

## Renders a weapon in the owner's hands to a PNG, for judging a SILHOUETTE —
## the one thing no headless test can check. Written for the quarrel caster, whose
## crossbow limbs are hand-placed geometry, but it takes any class.
##
## Windowed, because a renderer is the point:
##
##   godot --path godot --display-driver x11 --resolution 960x540 tests/weapon_look.tscn
##
## Shots land in user:// (~/.local/share/godot/app_userdata/QuadSquad/).

const PLAYER := preload("res://scenes/actors/player.tscn")

## Each entry: the label for the file, and the loadout that puts it in hand.
var _shots := [
	["quarrel caster", Weapon.Class.QUARREL_CASTER, true],
	["hmg", Weapon.Class.HMG, false],
	["rpg", Weapon.Class.RPG, false],
]


func _ready() -> void:
	GameState.match_live = true
	_build_floor()
	_light()

	var me := await _spawn()
	var cam := Camera3D.new()
	add_child(cam)
	me.bind_camera(cam)
	cam.current = true
	await _frames(4)

	for shot in _shots:
		var build := Loadout.new()
		build.adopt_kit(Loadout.Kit.URSAN)
		if not shot[2]:
			build.weapon = Loadout.weapon_index(shot[1])
		me.pending = build
		me._apply_loadout()
		if shot[2]:            # the sidearm: swap to it the way the player would
			me._swap_weapon()
		await _frames(8)
		print("  in hand: %s" % me.weapon.display_name())
		await _grab(shot[0])

	get_tree().quit()


func _grab(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "user://weapon_%s.png" % tag
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
