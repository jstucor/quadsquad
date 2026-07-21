extends Node3D
## The visible line for the wrist cable: a claw that shoots out of the muzzle,
## the wire trailing behind it, and a retract when the grapple lets go.
##
## It follows its owner every frame rather than being parented to them, because
## the anchor is a world position — parenting would drag the far end around as
## the player turns. Built on layer 1 so every viewport sees it, including the
## owner's (their camera only culls their own body and other players'
## viewmodels).
##
## Purely cosmetic: Player owns the timing and decides whether the shot
## connected. This just has to agree with it, so it takes the same flight time.

const WIRE_RADIUS := 0.03
# The wire leaves the barrel tip, not the gun's origin. The origin sits about
# where the owner's camera is, so a line starting there is blown up by
# perspective into a white wedge across their own view.
const MUZZLE_FORWARD := 0.75
const CLAW_SIZE := Vector3(0.16, 0.16, 0.3)
const RETRACT_TIME := 0.16

var _owner_body: Node3D
var _muzzle_node: Node3D   # read every frame: the player keeps moving
var _target := Vector3.ZERO
var _flight := 0.0
var _elapsed := 0.0
var _retracting := false
var _retract_left := 0.0

@onready var _wire: MeshInstance3D = $Wire
@onready var _claw: MeshInstance3D = $Claw


## `flight` should match the delay the player waits before it starts reeling, so
## the yank lands on the same frame the claw visually bites.
func launch(body: Node3D, muzzle: Node3D, target: Vector3, flight: float) -> void:
	_owner_body = body
	_muzzle_node = muzzle
	_target = target
	_flight = maxf(flight, 0.01)
	_elapsed = 0.0
	_build()


## Let go: the claw snaps back to the muzzle and the node frees itself.
func release() -> void:
	if _retracting:
		return
	_retracting = true
	_retract_left = RETRACT_TIME


func _build() -> void:
	# Unshaded and pale on purpose: a thin dark line vanishes against the dark
	# maps, and a lit one goes black on its shadow side. This has to read at a
	# glance on every map, so it ignores lighting entirely.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.82, 0.85, 0.9)
	var claw_mat := StandardMaterial3D.new()
	claw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	claw_mat.albedo_color = Color(0.95, 0.72, 0.35)  # warm tip, easy to track

	var wire_mesh := CylinderMesh.new()
	wire_mesh.top_radius = WIRE_RADIUS
	wire_mesh.bottom_radius = WIRE_RADIUS
	wire_mesh.height = 1.0        # scaled to the live length each frame
	wire_mesh.radial_segments = 5
	wire_mesh.rings = 0
	_wire.mesh = wire_mesh
	_wire.material_override = mat
	_wire.rotation.x = PI / 2.0   # CylinderMesh is Y-up; lay it along -Z

	var claw_mesh := BoxMesh.new()
	claw_mesh.size = CLAW_SIZE
	_claw.mesh = claw_mesh
	_claw.material_override = claw_mat


func _process(delta: float) -> void:
	if not is_instance_valid(_muzzle_node):
		queue_free()
		return
	var muzzle: Vector3 = _muzzle_node.global_position \
		- _muzzle_node.global_transform.basis.z * MUZZLE_FORWARD
	var tip := muzzle
	if _retracting:
		_retract_left -= delta
		if _retract_left <= 0.0:
			queue_free()
			return
		tip = muzzle.lerp(_target, _retract_left / RETRACT_TIME)
	else:
		_elapsed += delta
		tip = muzzle.lerp(_target, clampf(_elapsed / _flight, 0.0, 1.0))

	global_position = muzzle
	var span := tip - muzzle
	var length := span.length()
	if length < 0.05:
		_wire.visible = false
		_claw.visible = false
		return
	_wire.visible = true
	_claw.visible = true
	look_at(tip, Vector3.UP)  # -Z runs down the wire
	# The cylinder is a unit length centred on its own origin, so push it half a
	# span forward and stretch it to reach.
	_wire.position = Vector3(0.0, 0.0, -length * 0.5)
	_wire.scale = Vector3(1.0, length, 1.0)
	_claw.position = Vector3(0.0, 0.0, -length)
