extends Node3D
## WHERE THAT CAME FROM — the bearing maths, and the one property that makes the
## indicator worth having.
##
##   godot --headless --path godot tests/hit_direction.tscn
##
## THE PROPERTY IS THAT THE BEARING TRACKS. A marker that froze the angle it was
## created at would point somewhere meaningless the moment the player turned —
## and turning is precisely what a player DOES with this, so a frozen marker is
## not a weaker version of the feature, it is an actively misleading one. Every
## check below is a variation on "turn, and does it still point at the shooter".
##
## It is worth a test rather than a look because the failure is silent and the
## sign conventions are the part that goes wrong: a left/right flip draws a
## perfectly convincing indicator that sends the player the wrong way every time,
## and it looks correct in a screenshot.

const PLAYER := preload("res://scenes/actors/player.tscn")
const MARKS := preload("res://scripts/hit_direction.gd")

var _fails: Array[String] = []
var _done := {}


func _ready() -> void:
	GameState.reset_match()
	GameState.match_live = true
	await get_tree().process_frame

	_check_bearings()
	_check_tracking()
	_check_merge_and_cap()
	await _check_life()

	for name in ["bearings", "tracking", "merge", "life"]:
		if not _done.has(name):
			_fails.append("the `%s` checks did not run to the end" % name)
	print("")
	if _fails.is_empty():
		print("==== YOU KNOW WHERE IT CAME FROM ====")
	else:
		for f in _fails:
			print("  FAIL: ", f)
		print("==== %d FAILURES ====" % _fails.size())
	get_tree().quit(0 if _fails.is_empty() else 1)


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


func _rig() -> Array:
	var p: Player = PLAYER.instantiate()
	p.input_device = -1
	add_child(p)
	p.global_position = Vector3.ZERO
	p.rotation.y = 0.0
	var m: Control = MARKS.new()
	m.setup(p)
	add_child(m)
	return [p, m]


## A body faces -Z at yaw 0. So a shooter at -Z is dead ahead, +X is to the
## RIGHT, and the bearing is signed accordingly. These four are the sign
## conventions, which is the half that goes wrong silently.
func _check_bearings() -> void:
	print("== bearings, from a body facing -Z ==")
	var rig := _rig()
	var p: Player = rig[0]
	var m: Control = rig[1]
	for probe: Array in [
		["dead ahead", Vector3(0, 0, -10), 0.0],
		["behind",     Vector3(0, 0, 10), 180.0],
		["right",      Vector3(10, 0, 0), 90.0],
		["left",       Vector3(-10, 0, 0), -90.0],
	]:
		var got := rad_to_deg(m._bearing_to(probe[1]))
		print("  %-11s %7.1f deg (want %.0f)" % [probe[0], got, probe[2]])
		var diff: float = absf(wrapf(got - float(probe[2]), -180.0, 180.0))
		_ok(diff < 1.0,
			"a shooter %s reads as %.1f deg rather than %.0f — the sign convention is wrong, which draws a convincing marker that sends the player the wrong way"
				% [probe[0], got, probe[2]])
	# HEIGHT MUST NOT MATTER. A sniper on a tower is still to your left.
	var flat := rad_to_deg(m._bearing_to(Vector3(10, 0, 0)))
	var high := rad_to_deg(m._bearing_to(Vector3(10, 40, 0)))
	_ok(absf(flat - high) < 1.0,
		"a shooter 40 m above reads %.1f deg against %.1f on the flat — the bearing is not being flattened"
			% [high, flat])
	print("  height ignored: %.1f deg from 40 m up" % high)
	p.queue_free()
	m.queue_free()
	_done["bearings"] = true


## THE ONE THAT MATTERS. Turn toward the shooter and the marker must come round
## to twelve o'clock; the position it was created at is not stored as an angle.
func _check_tracking() -> void:
	print("\n== turning toward it brings it to the top ==")
	var rig := _rig()
	var p: Player = rig[0]
	var m: Control = rig[1]
	var shooter := Vector3(10, 0, 0)      # 90 deg to the right
	m._on_hit_from(shooter)
	_ok(m._marks.size() == 1, "being shot produced no marker")
	var before := rad_to_deg(m._bearing_to(m._marks[0]["from"]))

	# Turn 90 degrees to the right. A body faces -Z at yaw 0, so turning to face
	# +X is a yaw of -90 degrees.
	p.rotation.y = deg_to_rad(-90.0)
	var after := rad_to_deg(m._bearing_to(m._marks[0]["from"]))
	print("  before turning %.1f deg, after turning to face it %.1f deg"
		% [before, after])
	_ok(absf(after) < 1.0,
		"after turning to face the shooter the marker still reads %.1f deg — the bearing was frozen at creation and is now pointing at nothing"
			% after)

	# ...and WALKING changes it too, which a stored angle would also miss.
	p.rotation.y = 0.0
	p.global_position = Vector3(10, 0, -10)   # now the shooter is behind us
	var walked := rad_to_deg(m._bearing_to(m._marks[0]["from"]))
	print("  after walking past it %.1f deg" % walked)
	_ok(absf(absf(walked) - 180.0) < 1.0,
		"after walking past the shooter the marker reads %.1f deg rather than behind — it is not tracking position either"
			% walked)
	p.queue_free()
	m.queue_free()
	_done["tracking"] = true


## A burst is one threat, not six markers; a crossfire may not ring the screen.
func _check_merge_and_cap() -> void:
	print("\n== a burst is one threat ==")
	var rig := _rig()
	var p: Player = rig[0]
	var m: Control = rig[1]
	for i in 6:
		m._on_hit_from(Vector3(10, 0, 0.2 * i))
	print("  six rounds from one place -> %d marker(s)" % m._marks.size())
	_ok(m._marks.size() == 1,
		"a six-round burst from one direction drew %d markers — stacked wedges say nothing more than one does and hide the second shooter"
			% m._marks.size())

	# Genuinely different directions DO get their own.
	m._on_hit_from(Vector3(-10, 0, 0))
	_ok(m._marks.size() == 2,
		"a shooter on the other side did not get a marker of its own")
	# ...up to the cap.
	for i in 12:
		m._on_hit_from(Vector3(sin(i * 0.9) * 10.0, 0, cos(i * 0.9) * 10.0))
	print("  a crossfire from every angle -> %d markers (cap %d)"
		% [m._marks.size(), MARKS.MAX_MARKS])
	_ok(m._marks.size() <= MARKS.MAX_MARKS,
		"markers are not capped: %d on screen" % m._marks.size())
	p.queue_free()
	m.queue_free()
	_done["merge"] = true


## They expire, and a fresh body carries none.
func _check_life() -> void:
	print("\n== it fades, and a fresh body carries none ==")
	var rig := _rig()
	var p: Player = rig[0]
	var m: Control = rig[1]
	m._on_hit_from(Vector3(10, 0, 0))
	_ok(m._marks.size() == 1, "no marker to expire")
	# Ticked with a delta rather than waited out, so the test does not take a
	# second and a half of real time to assert one number.
	m.tick(MARKS.LIFE * 0.5)
	_ok(m._marks.size() == 1, "the marker expired at half its life")
	m.tick(MARKS.LIFE * 0.6)
	_ok(m._marks.is_empty(), "the marker outlived its own LIFE")
	print("  gone after %.2f s" % MARKS.LIFE)

	m._on_hit_from(Vector3(10, 0, 0))
	p.respawned.emit()
	await get_tree().process_frame
	_ok(m._marks.is_empty(),
		"a respawned body is still wearing the last life's incoming fire")
	print("  cleared on respawn")
	p.queue_free()
	m.queue_free()
	_done["life"] = true
