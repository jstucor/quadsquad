extends Node3D
## The cloud a smoke grenade leaves behind: a growing translucent ball that
## really does block sight, not just decorate the area.
##
## It has NO collider. Giving it one would stop bullets and bodies too, which is
## not what smoke does — instead it registers itself with GameState, and every
## line-of-sight check in the game (Bot, Turret) asks whether the segment passes
## through an active cloud. That keeps smoke a vision tool for humans AND the
## one thing that reliably breaks an AI's lock.

const RADIUS := 5.2
const LIFETIME := 9.0
const GROW_TIME := 0.6    # seconds to billow out to full size
const FADE_TIME := 1.6    # ...and to thin out again at the end

var _left := LIFETIME
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D


func _ready() -> void:
	GameState.register_smoke(self)
	_build()


func _exit_tree() -> void:
	GameState.unregister_smoke(self)


## How far the cloud currently reaches. Sight checks use this rather than
## RADIUS, so a cloud that is still billowing does not blind anyone early.
func radius() -> float:
	return RADIUS * _fill()


func _fill() -> float:
	var age := LIFETIME - _left
	if age < GROW_TIME:
		return clampf(age / GROW_TIME, 0.05, 1.0)
	return clampf(_left / FADE_TIME, 0.0, 1.0)


func _build() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(0.72, 0.74, 0.78, 0.86)
	# Drawn from the inside as well, so standing in the smoke is blinding rather
	# than a clear bubble with a shell around it.
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ball := SphereMesh.new()
	ball.radius = RADIUS
	ball.height = RADIUS * 2.0
	ball.radial_segments = 12
	ball.rings = 8
	_mesh = MeshInstance3D.new()
	_mesh.mesh = ball
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		queue_free()
		return
	var fill := _fill()
	_mesh.scale = Vector3.ONE * fill
	_mat.albedo_color.a = 0.86 * clampf(fill * 1.4, 0.0, 1.0)
