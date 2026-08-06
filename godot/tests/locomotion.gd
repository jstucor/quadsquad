extends Node
## WHICH CLIP A DIRECTION ASKS FOR.
##
## The clips themselves are covered by `guard_pose` (hands on the grip, feet out
## of the floor). What this covers is the SELECTION, which is nothing but sign
## conventions — and sign conventions are the part that is wrong silently. A
## backpedal that plays `strafe_l` looks like an animation bug and is actually an
## axis bug, and nothing anywhere errors.
##
## Player and Bot answer this separately, on purpose: they are duck-typed against
## each other and share no base class (house rule 15). So both are asked the same
## questions here, and the answers have to match — a bot that strafes the other
## way from a player is exactly the drift a shared test exists to catch.

const PLAYER := preload("res://scenes/actors/player.tscn")
const BOT := preload("res://scenes/actors/bot.tscn")

var _fails: Array[String] = []
var _done: Array[String] = []


func _ready() -> void:
	print("\n==== locomotion clips ====")
	_check_clips_exist()
	_check_selection()
	_check_priority()
	await _check_shared()
	await _check_lean()
	print("")
	# EVERY SECTION SIGNS OFF AT ITS OWN END. A GDScript error aborts the
	# enclosing function silently (house rule 6) — this very test printed
	# "LOCOMOTION HOLDS" while `_check_selection` was dying on a call that no
	# longer existed, having verified nothing at all.
	for want in ["clips", "direction", "priority", "shared", "lean"]:
		_ok(want in _done, "the `%s` section did not finish — it aborted part way"
			% want)
	if _fails.is_empty():
		print("==== LOCOMOTION HOLDS ====")
	else:
		for f in _fails:
			print("  FAIL: ", f)
		print("==== %d FAILURES ====" % _fails.size())
	get_tree().quit(0 if _fails.is_empty() else 1)


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


## A clip the state machine can name but the library does not have is a body that
## silently keeps playing whatever it was playing — `_update_anim` guards on
## `has_animation`, so the failure is invisible rather than loud.
func _check_clips_exist() -> void:
	print("\n-- the library has what the state machine asks for --")
	var model := CharacterModel.new()
	add_child(model)
	var anim: AnimationPlayer = model.anim_player
	for name in ["idle", "walk", "run", "jump", "walk_back", "strafe_l",
			"strafe_r", "crouch_idle", "crouch_walk", "guard_idle", "guard_walk"]:
		_ok(anim.has_animation(name), "the library has no `%s` clip" % name)
	print("  %d clips: %s" % [anim.get_animation_list().size(),
		str(anim.get_animation_list())])
	# A LOOPING CLIP THAT DOES NOT LOOP is a body that walks once and freezes.
	for name in ["walk_back", "strafe_l", "strafe_r"]:
		if anim.has_animation(name):
			_ok(anim.get_animation(name).loop_mode != Animation.LOOP_NONE,
				"`%s` does not loop — it would play once and hold" % name)
	model.queue_free()


## The table is stated in terms a person can check: forward is -y (the input
## convention `Input.get_vector` produces and the one body-local -Z matches),
## +x is the body's right.
	_done.append("clips")


func _check_selection() -> void:
	print("\n-- the hips swivel, and past a right angle the body backs up --")
	# travel (local: -y forward, +x right), clip, swivel in DEGREES, what it is
	var cases := [
		[Vector2(0.0, -1.0), "walk", 0.0, "straight forward"],
		[Vector2(1.0, -1.0), "walk", 45.0, "forward and right"],
		[Vector2(-1.0, -1.0), "walk", -45.0, "forward and left"],
		# THE RIGHT ANGLE IS THE LIMIT OF THE HIP, and everything up to it is an
		# ordinary forward stride with the legs turned.
		[Vector2(1.0, 0.0), "walk", 90.0, "straight right"],
		[Vector2(-1.0, 0.0), "walk", -90.0, "straight left"],
		# ...and past it the legs cannot follow, so the body backpedals with the
		# hips turned to the MIRROR of where it is going. Backing away to your
		# right is hips a little LEFT and a backpedal.
		[Vector2(1.0, 1.0), "walk_back", -45.0, "backing away to the right"],
		[Vector2(-1.0, 1.0), "walk_back", 45.0, "backing away to the left"],
		[Vector2(0.0, 1.0), "walk_back", 0.0, "straight back"],
	]
	print("  %-30s %-11s %s" % ["travel", "clip", "hips"])
	for c in cases:
		var local: Vector2 = c[0]
		var clip := Locomotion.ground_clip(local)
		var swivel := rad_to_deg(Locomotion.swivel_for(local))
		print("  %-30s %-11s %+.0f deg" % [c[3], clip, swivel])
		_ok(clip == c[1], "%s: should play `%s`, played `%s`" % [c[3], c[1], clip])
		_ok(absf(swivel - float(c[2])) < 0.5,
			"%s: hips should be %+.0f deg, were %+.0f" % [c[3], c[2], swivel])

	# THE HIPS NEVER GO PAST A RIGHT ANGLE, whichever branch resolved them —
	# that is the whole claim, and it is one sweep to check rather than a
	# reading of the two cases above.
	var worst := 0.0
	for step in 720:
		var a := deg_to_rad(float(step) * 0.5)
		var v := Vector2(sin(a), -cos(a))
		worst = maxf(worst, absf(Locomotion.swivel_for(v)))
	print("  worst swivel over a full circle of travel: %.1f deg" % rad_to_deg(worst))
	_ok(rad_to_deg(worst) <= 90.5,
		"the hips swivelled %.1f degrees — past the right angle they cannot"
			% rad_to_deg(worst))

	# THE BOUNDARY IS STICKY. At exactly sideways both answers are valid and they
	# are 180 degrees apart, so without hysteresis a body strafing along that
	# line flips its legs end over end on stick noise.
	var edge := Vector2(1.0, 0.02)
	_ok(Locomotion.ground_clip(edge, false) == "walk",
		"a body already walking flipped to a backpedal at the boundary")
	_ok(Locomotion.ground_clip(edge, true) == "walk_back",
		"a body already backing flipped to a walk at the boundary")
	print("  at the boundary it keeps doing what it was doing")
	_done.append("direction")


## THE PRIORITY ORDER IS THE DESIGN, so it is stated here rather than left to be
## inferred from whichever branch happens to run first.
func _check_priority() -> void:
	print("\n-- what beats what --")
	var fwd := Vector2(0.0, -3.0)
	var cases := [
		["airborne beats everything", Locomotion.clip_for(fwd, true, true, true, true), "jump"],
		["crouch beats the guard", Locomotion.clip_for(fwd, false, true, true, false), "crouch_walk"],
		["the guard beats a stride", Locomotion.clip_for(fwd, false, false, true, false), "guard_walk"],
		["sprint beats the direction rule", Locomotion.clip_for(Vector2(3.0, 0.0), false, false, false, true), "run"],
		["still and upright is idle", Locomotion.clip_for(Vector2.ZERO, false, false, false, false), "idle"],
		["still and crouched", Locomotion.clip_for(Vector2.ZERO, false, true, false, false), "crouch_idle"],
	]
	for c in cases:
		print("  %-34s %s" % [c[0], c[1]])
		_ok(c[1] == c[2], "%s: got `%s`, wanted `%s`" % [c[0], c[1], c[2]])
	_done.append("priority")


## ...AND BOTH BODIES ACTUALLY GO THROUGH IT.
##
## This is the assertion that replaced "the player and the bot agree". They used
## to answer separately and the test compared them, which is a check whose whole
## job was to catch a divergence between two copies of one rule. There is one
## copy now, so the thing worth asserting is that neither body has quietly grown
## its own again.
func _check_shared() -> void:
	print("\n-- one module, both bodies --")
	var player: Player = PLAYER.instantiate()
	add_child(player)
	var bot: Bot = BOT.instantiate()
	add_child(bot)
	await get_tree().process_frame

	_ok(player.get("_loco") is Locomotion, "the player holds a Locomotion")
	_ok(not player.has_method("_ground_clip"),
		"the player has grown its own copy of the direction rule again")
	_ok(not bot.has_method("_ground_clip"),
		"the bot has grown its own copy of the direction rule again")
	print("  player holds one: %s   neither declares its own rule: %s" % [
		player.get("_loco") is Locomotion,
		not player.has_method("_ground_clip") and not bot.has_method("_ground_clip")])
	player.queue_free()
	bot.queue_free()
	await get_tree().process_frame
	_done.append("shared")


## THE LEAN, which is the realism this had none of. Driven straight, because it
## is the one part of the module that carries state between frames and so is the
## one part a single call cannot judge.
func _check_lean() -> void:
	print("\n-- the body leans into a change of speed --")
	var probe := CharacterModel.new()
	add_child(probe)
	await get_tree().process_frame
	var loco := Locomotion.new()
	loco.setup(probe.anim_player, probe)

	# Accelerate hard forward for a few frames (local -y is forward).
	for i in 12:
		loco.tick(1.0 / 60.0, Vector3(0, 0, -float(i) * 0.9), 0.0,
			false, false, false, false)
	var fwd: float = probe.get("_twist_joint").rotation.x
	print("  accelerating forward: pitch %.3f rad" % fwd)
	_ok(fwd < -0.01, "accelerating forward did not lean the body forward (%.3f)" % fwd)

	# ...then hold a constant speed. A body at a steady pace stands up again —
	# that is the whole reason this is driven by acceleration and not velocity.
	for _i in 40:
		loco.tick(1.0 / 60.0, Vector3(0, 0, -10.0), 0.0, false, false, false, false)
	var steady: float = probe.get("_twist_joint").rotation.x
	print("  holding that speed:   pitch %.3f rad" % steady)
	_ok(absf(steady) < absf(fwd) * 0.5,
		"the lean did not settle at a constant speed (%.3f vs %.3f)" % [steady, fwd])

	# Sideways acceleration rolls rather than pitches.
	for i in 12:
		loco.tick(1.0 / 60.0, Vector3(float(i) * 0.9, 0, -10.0), 0.0,
			false, false, false, false)
	var roll: float = probe.get("_twist_joint").rotation.z
	print("  accelerating right:   roll  %.3f rad" % roll)
	_ok(absf(roll) > 0.01, "accelerating sideways did not roll the body (%.3f)" % roll)

	# THE LEAN AND THE TWIST SHARE ONE JOINT AND MUST COMPOSE. The lean owns its
	# X and Z; the swivel owns its Y. Drive the body sideways so the hips turn,
	# and check both are live at once rather than one having clobbered the other.
	for i in 20:
		loco.tick(1.0 / 60.0, Vector3(float(i) * 0.4, 0, 0), 0.0,
			false, false, false, false)
	var j: Node3D = probe.get("_twist_joint")
	print("  strafing: twist y %+.3f   lean x %+.3f  z %+.3f"
		% [j.rotation.y, j.rotation.x, j.rotation.z])
	_ok(absf(j.rotation.y) > 0.1,
		"the hips did not swivel while travelling sideways (y %.3f)" % j.rotation.y)
	_ok(absf(j.rotation.z) > 0.001,
		"the lean was clobbered by the swivel — they share a joint and must not")
	probe.queue_free()
	_done.append("lean")
