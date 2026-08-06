extends Node3D

## THE PLACED HARDWARE, from the distances it is actually seen at.
##
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/deployable_look.tscn
##
## Windowed, because appearance is the whole subject. Shots land in user://.
##
## A turret and a mortar are the only two things a player BUILDS, and they are
## bought from the same screen, cost about the same and stand about the same
## height — so the first thing these shots have to answer is whether the two of
## them are telling themselves apart at twelve metres, which is the range you
## decide whether to walk around one. They are put side by side for exactly that,
## with a trooper standing next to them for scale: hardware that reads as small
## when it is chest-high is hardware nobody takes cover behind.
##
## Both are shot in TWO team colours, because the sensor slit and the shell noses
## are the only parts that carry the team and a colour that works on red usually
## needs checking on blue.

const TURRET := preload("res://scenes/actors/turret.tscn")
const MORTAR := preload("res://scenes/actors/mortar.tscn")

var _built: Array[Node3D] = []


func _ready() -> void:
	GameState.match_live = true
	_build_floor()
	_light()
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true

	for team in [0, 1]:
		_lay_out(team)
		# The DECISION distance: far enough that both fit, close enough that this
		# is the read a player actually gets before choosing to push or go round.
		cam.global_transform = Transform3D(Basis(), Vector3(0.6, 1.55, -4.2))
		cam.look_at(Vector3(0.0, 0.75, 0.0), Vector3.UP)
		await _frames(6)
		await _grab("pair_team%d" % team)
		# ...and from a walking eye height, three-quarters on, which is where the
		# tripod and the bipod either read as legs or read as clutter.
		cam.global_transform = Transform3D(Basis(), Vector3(-2.3, 1.70, -2.3))
		cam.look_at(Vector3(-0.2, 0.70, 0.0), Vector3.UP)
		await _frames(4)
		await _grab("pair_team%d_walk" % team)
	_clear()

	# Each on its own, close, from the front and from behind — the two angles
	# that show the sensor slit and the ammo rack respectively.
	for spec in [["turret", TURRET], ["mortar", MORTAR]]:
		for shot in [["front", 0.0], ["quarter", 0.85], ["rear", PI]]:
			_clear()
			_place(spec[1], Vector3.ZERO, 0)
			var a: float = shot[1]
			cam.global_transform = Transform3D(Basis(),
				Vector3(sin(a) * 2.0, 1.15, -cos(a) * 2.0))
			cam.look_at(Vector3(0.0, 0.62, 0.0), Vector3.UP)
			await _frames(5)
			await _grab("%s_%s" % [spec[0], shot[0]])
	_clear()
	get_tree().quit()


## A turret, a mortar and a body to measure them against.
func _lay_out(team: int) -> void:
	_clear()
	_place(TURRET, Vector3(-1.15, 0.0, 0.0), team)
	_place(MORTAR, Vector3(1.15, 0.0, 0.0), team)
	var m := CharacterModel.new()
	add_child(m)
	m.set_style(CharacterModel.Style.LEGION)
	m.set_team_color(GameState.team_colors[team])
	m.position = Vector3(0.0, 0.0, 1.1)
	if m.anim_player != null:
		m.anim_player.play("idle")
		m.anim_player.seek(0.0, true)
	_built.append(m)


func _place(scene: PackedScene, at: Vector3, team: int) -> void:
	var node: Node3D = scene.instantiate()
	add_child(node)
	node.position = at
	# setup() is what a player's gadget calls; it only re-tints, so the model is
	# already there either way — but calling it is what this is meant to shoot.
	node.setup(null, team)
	if node.has_method("fire_at"):
		# A mortar with no mark has its tube pointing wherever it was dropped.
		# Give it one, so the shot shows the traverse doing its job.
		node.fire_at(at + Vector3(0.0, 0.0, -20.0))
	_built.append(node)


func _clear() -> void:
	for n in _built:
		if is_instance_valid(n):
			remove_child(n)
			n.queue_free()
	_built.clear()


func _grab(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "user://deployable_%s.png" % tag
	img.save_png(path)
	print("wrote %s" % ProjectSettings.globalize_path(path))


func _light() -> void:
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(35.0), 0.0)
	key.light_energy = 1.1
	add_child(key)
	var fill := DirectionalLight3D.new()
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
	# Graded exactly as a real map is, or this photographs a lighting model the
	# game does not ship.
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
	mat.albedo_color = Color(0.26, 0.27, 0.30)
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
