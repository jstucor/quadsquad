extends Node3D

## What a body looks like once it is down, in ALL THREE death styles.
##
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/death_look.tscn
##
## Appearance is the thing being judged here, so it runs WINDOWED — the same
## rule guard_look follows. It lines up one corpse per unit type, freezes them
## upright (physics off, so the shot is the POSE rather than wherever they
## happened to have tumbled to) and renders the RAGDOLL, then the ANIMATED fall
## at rest, then the CLASSIC T-pose flop the option brings back.
##
## The ANIMATED shot is the one to look at hardest: the ragdoll settles onto
## whatever it lands on and this one does not, so this line-up on flat ground is
## its BEST case, not its typical one.
##
## It writes Controls.set_option, which SAVES, so it snapshots the real
## user://controls.cfg first and puts it back — the same discipline
## controls_inherit keeps, and for the same reason.

const CORPSE := preload("res://scenes/fx/corpse.tscn")
const CONFIG := "user://controls.cfg"

const LINEUP := [
	CharacterModel.Style.LEGION,
	CharacterModel.Style.AUTOMATON,
	CharacterModel.Style.AUTOMATON_HEAVY,
	CharacterModel.Style.GLAIVE_DRONE,
	CharacterModel.Style.URSAN,
]

var _backup := ""


func _ready() -> void:
	if FileAccess.file_exists(CONFIG):
		_backup = FileAccess.get_file_as_string(CONFIG)
	_build_scene()

	# THROUGH `set_death_style`, not by writing the old boolean. That key is now
	# a fallback the style migrates FROM — setting it while a real style is stored
	# changes nothing, so this test would have gone on photographing whichever
	# style happened to be saved and reported it as both.
	Controls.set_death_style(Controls.Death.RAGDOLL)
	_lay_out()
	await _frames(6)
	await _grab("death_ragdoll")

	Controls.set_death_style(Controls.Death.ANIMATED)
	# NOT frozen on arrival. `freeze_all` stops a ragdoll's rigid bodies, and on an
	# animated corpse it PAUSES the clip — so freezing at lay-out time photographed
	# five bodies standing to attention, which is frame zero of a fall. It has to
	# play out first and be stopped at the end.
	_lay_out(false)
	await _frames(int(CharacterModel.DEATH_LEN * 64.0))
	_freeze_all()
	await _frames(2)
	await _grab("death_animated")

	Controls.set_death_style(Controls.Death.CLASSIC)
	_lay_out()
	await _frames(6)
	await _grab("death_classic")

	_restore()
	get_tree().quit()


## One corpse per style, evenly spaced and facing the camera. Physics is frozen
## so what is on screen is the pose, not the tumble.
func _lay_out(freeze_now := true) -> void:
	for c in get_children():
		if c.has_method("freeze_all"):
			c.queue_free()
	for i in LINEUP.size():
		var corpse: Node3D = CORPSE.instantiate()
		add_child(corpse)
		var at := Vector3((i - (LINEUP.size() - 1) * 0.5) * 1.15, 0.0, 0.0)
		# Turned a little off square, so the pose reads in three quarters rather
		# than as a flat front-on silhouette.
		var facing := Basis(Vector3.UP, deg_to_rad(35.0))
		# FORCED: this scene has no Player in it, and a corpse with no human
		# within VIEW_RANGE now frees itself rather than being built for nobody.
		corpse.launch(Transform3D(facing, at), GameState.team_colors[i % 2],
			Vector3.ZERO, LINEUP[i], true)
		# A corpse is a ragdoll now, so freezing it is six bodies, not one.
		if freeze_now:
			corpse.freeze_all()


## Stop whatever is still moving, whichever style is up.
func _freeze_all() -> void:
	for c in get_children():
		if c.has_method("freeze_all"):
			c.freeze_all()


func _build_scene() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.15, 2.9)
	cam.rotation_degrees = Vector3(-14.0, 0.0, 0.0)
	cam.current = true
	add_child(cam)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	key.light_energy = 1.1
	add_child(key)
	# A dim opposing fill, the project's standard answer to black shadow sides.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, -150.0, 0.0)
	fill.light_energy = 0.35
	fill.shadow_enabled = false
	fill.light_specular = 0.0
	add_child(fill)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.30, 0.32, 0.38)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 2.0, 40.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	floor_body.add_child(shape)
	floor_body.collision_layer = 1
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.23, 0.26)
	mat.metallic = 0.0
	mesh.material_override = mat
	floor_body.add_child(mesh)
	add_child(floor_body)


func _restore() -> void:
	if _backup == "":
		return
	var f := FileAccess.open(CONFIG, FileAccess.WRITE)
	f.store_string(_backup)
	f.close()


func _grab(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://%s.png" % tag)
	print("wrote %s" % ProjectSettings.globalize_path("user://%s.png" % tag))


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
