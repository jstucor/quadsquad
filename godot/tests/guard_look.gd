extends Node3D

## What the guard LOOKS like, from both ends: our own blade in first person and
## somebody else's stance from four metres away. Saves PNGs rather than needing
## an editor, because the thing being judged here is appearance and nothing else
## in the test suite can see.
##
## Run it windowed — a renderer is the whole point, so --headless produces
## nothing:
##
##   godot --path godot --display-driver x11 --resolution 960x540 tests/guard_look.tscn
##
## Shots land in user:// (~/.local/share/godot/app_userdata/QuadSquad/).

const PLAYER := preload("res://scenes/actors/player.tscn")

var _mate: Player
var _outside: Camera3D   # the over-the-shoulder view of the other trooper


func _ready() -> void:
	GameState.match_live = true
	_build_floor()
	_light()

	var me := await _spawn(0, Vector3.ZERO)
	_mate = await _spawn(1, Vector3(0.0, 0.0, -4.2))
	_mate.rotation.y = PI          # face us, so the stance reads front-on

	var cam := Camera3D.new()
	add_child(cam)
	me.bind_camera(cam)
	cam.current = true
	# ...and a second, ordinary camera off to the side, because the first-person
	# view is exactly the one that cannot see the stance being judged.
	_outside = Camera3D.new()
	add_child(_outside)
	_outside.global_position = Vector3(1.9, 1.0, -6.6)
	_outside.look_at(Vector3(0.0, 0.9, -4.2), Vector3.UP)
	await _frames(4)

	await _shot("1_rest", 20)
	Input.action_press("kb_ads")
	await _shot("2_guard", 30)
	# A hit from the front, which the guard pays for: the blade should be flaring
	# and knocked off line in this one.
	var attacker := Node3D.new()
	add_child(attacker)
	attacker.global_position = Vector3(0.0, 1.0, -8.0)
	me.take_damage(30.0, attacker)
	_mate.take_damage(30.0, attacker)
	await _shot("3_parry", 4)
	Input.action_release("kb_ads")
	await _shot("4_lowered", 30)

	# The new power, mid-bolt: it lasts a third of a second, so the frame has to
	# be grabbed right after it is thrown.
	me._force_cd = [0.0, 0.0, 0.0]   # one per gadget slot, and there are three
	me._use_gadget(0)
	await _shot("5_lightning", 3)

	print("guard_up (me) %s, blade in hand %s" % [me.guard_up(), me.weapon.is_melee()])
	get_tree().quit()


## Two frames per moment: what the player holding the blade sees, and what the
## player being charged BY it sees.
func _shot(tag: String, wait: int) -> void:
	await _frames(wait)
	await _grab("%s_fp" % tag)
	_outside.current = true
	await _frames(2)
	await _grab("%s_tp" % tag)
	_outside.current = false
	await _frames(2)


func _grab(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "user://guard_%s.png" % tag
	img.save_png(path)
	print("wrote %s" % ProjectSettings.globalize_path(path))


func _light() -> void:
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(35.0), 0.0)
	key.light_energy = 1.1
	add_child(key)
	var fill := DirectionalLight3D.new()   # shadowless opposing fill (see Gotchas)
	fill.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(-150.0), 0.0)
	fill.light_energy = 0.35
	fill.shadow_enabled = false
	add_child(fill)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.10, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.44, 0.5)
	e.ambient_light_energy = 0.5
	env.environment = e
	add_child(env)


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
	mat.albedo_color = Color(0.22, 0.23, 0.26)
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)


func _spawn(index: int, at: Vector3) -> Player:
	var p: Player = PLAYER.instantiate()
	p.input_device = -1
	p.player_index = index
	p.team = index
	p.position = at
	add_child(p)
	await get_tree().physics_frame
	var l := Loadout.new()
	l.adopt_kit(Loadout.Kit.FORCE)
	l.weapon = Loadout.weapon_index(Weapon.Class.SABER)
	l.gadget = Loadout.Gadget.FORCE_LIGHTNING
	p.pending = l
	p._apply_loadout()
	await get_tree().physics_frame
	return p


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
