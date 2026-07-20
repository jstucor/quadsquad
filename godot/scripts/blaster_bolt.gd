extends Node3D
## Visual-only blaster bolt tracer. The weapon's hitscan already decided the
## outcome; this just flies the path and frees itself at the end point.

const SPEED := 400.0  # bolts read as fast energy blasts, not lobbed pellets

var _dir := Vector3.ZERO
var _remaining := 0.0


func launch(from: Vector3, to: Vector3) -> void:
	global_position = from
	_remaining = from.distance_to(to)
	if _remaining < 0.01:
		queue_free()
		return
	_dir = (to - from) / _remaining
	if absf(_dir.dot(Vector3.UP)) < 0.99:
		look_at(to)  # bolt mesh lies along -Z


func _process(delta: float) -> void:
	var step := SPEED * delta
	global_position += _dir * step
	_remaining -= step
	if _remaining <= 0.0:
		queue_free()
