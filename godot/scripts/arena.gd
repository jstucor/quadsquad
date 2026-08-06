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
var size := 50.0   # width along X
var depth := 0.0   # length along Z; left at 0 the arena is square (size x size)
var floor_color := Color(0.17, 0.18, 0.21)
var wall_color := Color(0.19, 0.21, 0.25)
var cover_color := Color(0.23, 0.24, 0.27)
var republic_spawns: Array[Vector3] = []
var cis_spawns: Array[Vector3] = []
var cover_boxes: Array = []  # [{pos = Vector3 (base at y=0), size = Vector3}, ...]
## Exposure for THIS map, if it should not sit where the rest of the game sits.
## The grade is shared (see _grade) but how bright a place is meant to be is a
## map's own business — a foundry lit by molten metal and a snowfield at noon
## are not the same photograph.
var grade_exposure := Grade.EXPOSURE


func _ready() -> void:
	_configure()
	if depth <= 0.0:
		depth = size
	_build_environment()
	_build_lights()
	_grade()
	_build_floor()
	_build_walls()
	_build_cover()
	_decorate()
	_register_spawns()
	# The map screen would otherwise have to infer the playable area from the
	# geometry; a procedural map already knows it exactly.
	GameState.register_map_bounds(global_position, half_extents())


## Override in the map script to fill in the layout.
func _configure() -> void:
	pass


## Override to add map-specific props (trees, crates) after the base geometry.
func _decorate() -> void:
	pass


## The floor surface. Override for a map that isn't a metal deck.
func _floor_material() -> Material:
	var mat := ShaderMaterial.new()
	mat.shader = FLOOR_SHADER
	mat.set_shader_parameter("base_col", floor_color)
	mat.set_shader_parameter("seam_col", floor_color.darkened(0.7))
	mat.set_shader_parameter("panels", roundf(size / 2.0))
	return mat


## Half-extents of the playable floor, XZ.
func half_extents() -> Vector2:
	return Vector2(size, depth) * 0.5


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


## Apply THE GRADE (scripts/grade.gd) over whatever the map just built — the
## response curve, the ambient model, the glow threshold, aerial perspective and
## the shadow settings. The map keeps every colour it chose; how those colours
## are rendered is one file for the whole game.
func _grade() -> void:
	Grade.apply_to(self, grade_exposure)


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
	plane.size = Vector2(size, depth)
	mesh.mesh = plane
	mesh.material_override = _floor_material()
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 1.0, depth)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)


## Walls and cover get the same treatment the character plate does: a real
## metallic value (the sky is graded now, so there is something to reflect) and a
## RIM term, which on a box lands as a bright line down every silhouette edge.
##
## That edge is what makes a cover box read as a solid object rather than a flat
## colour, and it matters more here than on a body: cover is what a player reads
## the map through, and at range a boxy silhouette with a lit edge separates from
## the ground where a matte one merges into it.
func _surface(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.25
	mat.roughness = roughness
	mat.rim_enabled = true
	mat.rim = 0.3
	mat.rim_tint = 0.4
	return mat


func _build_walls() -> void:
	var mat := _surface(wall_color, 0.55)
	var h := 6.0
	var half := half_extents()
	# N, S run along X; E, W run along Z.
	_wall(Vector3(0, h * 0.5, -half.y), Vector3(size, h, 0.6), mat)
	_wall(Vector3(0, h * 0.5, half.y), Vector3(size, h, 0.6), mat)
	_wall(Vector3(-half.x, h * 0.5, 0), Vector3(0.6, h, depth), mat)
	_wall(Vector3(half.x, h * 0.5, 0), Vector3(0.6, h, depth), mat)


## `nav` false marks this as geometry the nav grid and the map screen must
## IGNORE while it goes on colliding — a ceiling, an overhead gantry. See
## `GameState.MAP_NAV_IGNORE` for why it is stated rather than inferred from how
## high the box is.
func _wall(center: Vector3, box_size: Vector3, mat: Material, nav := true) -> void:
	var body := StaticBody3D.new()
	body.position = center
	if not nav:
		body.set_meta(GameState.MAP_NAV_IGNORE, true)
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
	var mat := _surface(cover_color, 0.5)
	for c in cover_boxes:
		var bsize: Vector3 = c["size"]
		var pos: Vector3 = c["pos"]
		_wall(pos + Vector3(0, bsize.y * 0.5, 0), bsize, mat)


func _register_spawns() -> void:
	for p in republic_spawns:
		_spawn_marker(p, GameState.Team.CONCORD)
	for p in cis_spawns:
		_spawn_marker(p, GameState.Team.AUTOMATA)


func _spawn_marker(pos: Vector3, team: int) -> void:
	var m := Marker3D.new()
	m.position = pos
	add_child(m)
	# Face toward the arena centre (same height, so no pitch) so players spawn
	# looking inward. -Z is the player's forward.
	if Vector2(pos.x, pos.z).length() > 0.1:
		m.look_at(Vector3(0, pos.y, 0), Vector3.UP)
	GameState.register_spawn_point(team, m)
