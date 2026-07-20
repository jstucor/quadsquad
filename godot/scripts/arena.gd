class_name Arena
extends Node3D
## Procedural arena base for team-deathmatch maps. A map is a Node3D whose
## script `extends "res://scripts/arena.gd"` and overrides _configure() to set
## the size, floor colour, cover layout, and the two teams' spawn points. This
## base then builds the sky/environment, floor, boundary walls, key+fill
## lights, cover boxes, and registers the spawns with GameState — so a new map
## is just a layout table, no hand-authored scene geometry.

const SKY_SHADER := preload("res://shaders/starfield_sky.gdshader")
const FLOOR_SHADER := preload("res://shaders/floor_panels.gdshader")

# Overridden by each map in _configure().
var size := 50.0
var floor_color := Color(0.17, 0.18, 0.21)
var republic_spawns: Array[Vector3] = []
var cis_spawns: Array[Vector3] = []
var cover_boxes: Array = []  # [{pos = Vector3 (base at y=0), size = Vector3}, ...]


func _ready() -> void:
	_configure()
	_build_environment()
	_build_lights()
	_build_floor()
	_build_walls()
	_build_cover()
	_register_spawns()


## Override in the map script to fill in the layout.
func _configure() -> void:
	pass


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.22, 0.3)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.02, 0.03, 0.05)
	env.fog_density = 0.008
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_lights() -> void:
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-52), deg_to_rad(38), 0)
	key.light_energy = 1.0
	key.shadow_enabled = true
	add_child(key)
	# Dim shadowless opposing fill so shadow sides aren't pitch black under the
	# near-black sky (GL Compatibility gotcha).
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-25), deg_to_rad(-150), 0)
	fill.light_energy = 0.28
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	add_child(fill)


func _build_floor() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	mesh.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = FLOOR_SHADER
	mat.set_shader_parameter("base_col", floor_color)
	mat.set_shader_parameter("seam_col", floor_color.darkened(0.7))
	mat.set_shader_parameter("panels", roundf(size / 2.0))
	mesh.material_override = mat
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 1.0, size)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)


func _build_walls() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.19, 0.21, 0.25)
	mat.metallic = 0.12
	mat.roughness = 0.55
	var h := 6.0
	var half := size / 2.0
	# N, S run along X; E, W run along Z.
	_wall(Vector3(0, h * 0.5, -half), Vector3(size, h, 0.6), mat)
	_wall(Vector3(0, h * 0.5, half), Vector3(size, h, 0.6), mat)
	_wall(Vector3(-half, h * 0.5, 0), Vector3(0.6, h, size), mat)
	_wall(Vector3(half, h * 0.5, 0), Vector3(0.6, h, size), mat)


func _wall(center: Vector3, box_size: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = center
	add_child(body)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box_size
	mesh.mesh = bm
	mesh.material_override = mat
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var cb := BoxShape3D.new()
	cb.size = box_size
	shape.shape = cb
	body.add_child(shape)


func _build_cover() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.23, 0.24, 0.27)
	mat.metallic = 0.1
	mat.roughness = 0.5
	for c in cover_boxes:
		var bsize: Vector3 = c["size"]
		var pos: Vector3 = c["pos"]
		_wall(pos + Vector3(0, bsize.y * 0.5, 0), bsize, mat)


func _register_spawns() -> void:
	for p in republic_spawns:
		_spawn_marker(p, GameState.Team.REPUBLIC)
	for p in cis_spawns:
		_spawn_marker(p, GameState.Team.CIS)


func _spawn_marker(pos: Vector3, team: int) -> void:
	var m := Marker3D.new()
	m.position = pos
	add_child(m)
	# Face toward the arena centre (same height, so no pitch) so players spawn
	# looking inward. -Z is the player's forward.
	if Vector2(pos.x, pos.z).length() > 0.1:
		m.look_at(Vector3(0, pos.y, 0), Vector3.UP)
	GameState.register_spawn_point(team, m)
