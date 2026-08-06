extends Node3D
## The visible bolt for FORCE LIGHTNING: a jagged line from the caster's hand
## through everyone the arc struck, flickering for a moment and then gone.
##
## Purely cosmetic, exactly like the cable's wire — Kinesis has already dealt
## the damage and decided the chain by the time this exists. It only has to agree
## with it, which is why it is handed the same ordered list of victims.
##
## It is built from a FIXED pool of segments, allocated once in strike() and only
## ever repositioned afterwards. The obvious implementation — rebuilding an
## ImmediateMesh every frame — allocates on every frame of every bolt in a
## four-viewport match, which is the one thing the Pi budget will not take.
##
## Like the wire it is unshaded: a lit bolt goes black on its shadow side and
## disappears on the night maps, and lightning that only reads on half the
## roster is not a tell at all.

const LIFE := 0.34            # seconds on screen
const SEGMENTS := 10          # jagged pieces per link of the chain
const MAX_LINKS := 5          # caster + every victim Kinesis can chain
const THICKNESS := 0.035
const JITTER := 0.20          # how far a joint kicks off the straight line, in m
const HAND_FORWARD := 0.75    # the bolt leaves the hand, not the camera origin
const HAND_DOWN := 0.12
const CHEST_UP := 1.0         # aim at the body, not at the feet
const CORE := Color(0.85, 0.93, 1.0)
const GLOW := Color(0.35, 0.6, 1.0)

var _source: Node3D           # the caster's weapon node; the bolt starts here
var _victims: Array = []
## Where each victim was last seen. A body that dies to the bolt is freed while
## it is still on screen, so the arc has to be able to finish drawing to a
## remembered position rather than snapping back to the caster.
var _last_pos: Array = []
var _left := 0.0
var _core: Array[MeshInstance3D] = []
var _glow: Array[MeshInstance3D] = []
var _core_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
## Reused every frame: the polyline the segments are laid along. Preallocated for
## the same reason the segments are.
var _points: Array[Vector3] = []


## `source` is the caster's weapon node (the bolt's origin), `chain` the victims
## in the order Kinesis struck them.
func strike(source: Node3D, chain: Array) -> void:
	_source = source
	_victims = chain.slice(0, MAX_LINKS - 1)
	_last_pos.resize(_victims.size())
	for i in _victims.size():
		_last_pos[i] = (_victims[i] as Node3D).global_position + Vector3.UP * CHEST_UP
	_points.resize(_victims.size() * SEGMENTS + 1)
	_left = LIFE
	_build()


func _build() -> void:
	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.albedo_color = CORE
	_core_mat.emission_enabled = true
	_core_mat.emission = CORE
	_core_mat.emission_energy_multiplier = 4.0

	# The halo is additive and translucent, so overlapping segments pile up into a
	# brighter joint instead of drawing a seam over each other.
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_mat.albedo_color = Color(GLOW.r, GLOW.g, GLOW.b, 0.45)
	_glow_mat.emission_enabled = true
	_glow_mat.emission = GLOW
	_glow_mat.emission_energy_multiplier = 2.5

	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE   # scaled to each segment's length every frame
	for _i in _victims.size() * SEGMENTS:
		_core.append(_segment(mesh, _core_mat, 1.0))
		_glow.append(_segment(mesh, _glow_mat, 2.2))


func _segment(mesh: Mesh, mat: Material, width: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("width", width)
	add_child(mi)
	return mi


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0 or _victims.is_empty() or not is_instance_valid(_source):
		queue_free()
		return
	# Fades out rather than blinking off: a bolt that vanishes mid-frame reads as
	# a dropped effect, not as one that finished.
	var fade := clampf(_left / LIFE, 0.0, 1.0)
	_core_mat.albedo_color = Color(CORE.r, CORE.g, CORE.b, fade)
	_core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.albedo_color = Color(GLOW.r, GLOW.g, GLOW.b, 0.45 * fade)

	_lay_out()


## Rebuild the polyline through the chain and drop the segments onto it.
func _lay_out() -> void:
	global_position = Vector3.ZERO
	var from: Vector3 = _source.global_position \
		- _source.global_transform.basis.z * HAND_FORWARD \
		- _source.global_transform.basis.y * HAND_DOWN
	_points[0] = from
	var index := 0
	for v in _victims.size():
		var body: Node3D = _victims[v]
		if is_instance_valid(body):
			_last_pos[v] = body.global_position + Vector3.UP * CHEST_UP
		var to: Vector3 = _last_pos[v]
		var span := to - from
		# Two axes across the run, so the jag is three-dimensional rather than a
		# flat zigzag that disappears when you look at it edge-on.
		var side := span.cross(Vector3.UP)
		if side.length() < 0.01:
			side = Vector3.RIGHT
		side = side.normalized()
		var up := side.cross(span.normalized()).normalized()
		for s in SEGMENTS:
			index += 1
			var t := float(s + 1) / float(SEGMENTS)
			var point := from + span * t
			if s < SEGMENTS - 1:   # the last point is the victim: land on them
				point += side * randf_range(-JITTER, JITTER) \
					+ up * randf_range(-JITTER, JITTER)
			_points[index] = point
		from = to

	for i in _core.size():
		_place(_core[i], _points[i], _points[i + 1])
		_place(_glow[i], _points[i], _points[i + 1])


## One segment, stretched between two points. The box is a unit cube, so it is
## scaled to the gap and pushed to the midpoint; looking down the run means the
## length is on -Z like every other stretched mesh here.
func _place(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var span := b - a
	var length := span.length()
	if length < 0.001:
		mi.visible = false
		return
	mi.visible = true
	# A segment that runs straight up is parallel to the default up vector, which
	# makes look_at error and leave the piece unrotated. It happens the moment
	# somebody is directly above or below you, so it has to be handled here.
	var up := Vector3.UP
	if absf(span.normalized().dot(up)) > 0.99:
		up = Vector3.FORWARD
	mi.look_at_from_position(a.lerp(b, 0.5), b, up)
	var width: float = THICKNESS * float(mi.get_meta("width"))
	mi.scale = Vector3(width, width, length)
