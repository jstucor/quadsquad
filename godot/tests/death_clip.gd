extends Node
## THE DEATH CLIPS, MEASURED. A canned fall has exactly two ways to be wrong and
## neither of them raises anything: the body can pivot about the wrong point (it
## spins about its hips and drives its head through the floor), or it can end up
## somewhere that is not lying down. Both look like "the animation is a bit off"
## and both are arithmetic, so they get numbers rather than a screenshot.
##
## `death_look.tscn` is the picture; this is the proof.
##
## Run:  godot --headless --path godot tests/death_clip.tscn

## Where a joint is allowed to get to. The model's feet rest at y = 0, so anything
## below this is through the floor — the failure the feet-pivot exists to prevent.
const FLOOR_TOLERANCE := -0.06
## A body that has fallen over has its head DOWN. Standing it is ~1.7 m; this is
## the line between "lying" and "leaning".
const LYING_HEAD_MAX := 0.85
## ...and it should not have travelled halfway across the room to get there.
##
## MEASURED AT THE HIPS, not at the furthest joint. The first version of this
## check walked every joint and failed at 1.64 m — which was not a bug, it was a
## body lying down being 1.8 m long. A corpse's HIPS are what "where it died"
## means; a hand two metres away is an arm.
const MAX_DRIFT := 1.3

var _failures := 0


func _ready() -> void:
	print("\n=== DEATH CLIPS ===\n")
	_test_fall_direction()
	await _test_falls()
	print("")
	if _failures == 0:
		print("==== EVERY BODY LIES DOWN ====")
	else:
		print("==== %d FAILURE%s ====" % [_failures, "" if _failures == 1 else "S"])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["OK  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


## A shove decides which way you go down, and it is read in the BODY's space —
## so a round in the back drops you forward whatever direction you happened to be
## facing. Getting this wrong is subtle: it still falls over, just not away from
## whoever shot it.
func _test_fall_direction() -> void:
	print("-- which way it goes down --")
	# Model faces -Z. A shove with +Z (pushed backwards) must fall BACK.
	_check(CharacterModel.fall_from_push(Vector3(0, 0, 1), 0.0)
		== CharacterModel.Fall.BACK, "shot from the front -> falls backward")
	_check(CharacterModel.fall_from_push(Vector3(0, 0, -1), 0.0)
		== CharacterModel.Fall.FRONT, "shot from behind -> falls forward")
	_check(CharacterModel.fall_from_push(Vector3(1, 0, 0), 0.0)
		== CharacterModel.Fall.RIGHT, "shoved from its left -> falls right")
	_check(CharacterModel.fall_from_push(Vector3(-1, 0, 0), 0.0)
		== CharacterModel.Fall.LEFT, "shoved from its right -> falls left")
	_check(CharacterModel.fall_from_push(Vector3.ZERO, 0.0)
		== CharacterModel.Fall.CRUMPLE, "no shove at all -> crumples where it stood")
	# Facing matters: the same world-space shove on a body turned 180 degrees is
	# now a shot in the BACK, so it must fall the other way.
	_check(CharacterModel.fall_from_push(Vector3(0, 0, 1), PI)
		== CharacterModel.Fall.FRONT,
		"...and the same shove on a body facing the other way falls forward")


func _test_falls() -> void:
	print("\n-- the fall itself --")
	var model := CharacterModel.new()
	add_child(model)
	model.set_style(CharacterModel.Style.GENERIC)
	await get_tree().process_frame
	model.build_death_clips()
	var player: AnimationPlayer = model.anim_player
	_check(player != null, "the model has an AnimationPlayer to play them on")
	if player == null:
		return

	for fall: int in CharacterModel.DEATH_CLIPS:
		var clip: String = CharacterModel.DEATH_CLIPS[fall]
		if not player.has_animation(clip):
			_check(false, "%s exists" % clip)
			continue
		var lowest := 99.0
		var culprit := ""
		var drift := 0.0
		var head_end := 99.0
		player.play(clip)
		# Walked in steps rather than played out, so the whole fall is measured
		# and not just where it stopped — a body that dips through the floor
		# halfway down and comes back up would pass an end-state check.
		for i in 25:
			var t := CharacterModel.DEATH_LEN * float(i) / 24.0
			player.seek(t, true)
			await get_tree().process_frame
			# Every MESH, not every node: a joint is a bare Node3D and some of them
			# sit inside the body by design (the twist, the held-gun anchor). What
			# must stay out of the floor is what can be SEEN in it.
			for mesh in model.find_children("*", "MeshInstance3D", true, false):
				var mi := mesh as MeshInstance3D
				var box := mi.get_aabb()
				# The mesh's own lowest corner in world space, so a thick boot is
				# measured at its sole and not at its centre.
				for corner in 8:
					var y: float = (mi.global_transform * box.get_endpoint(corner)).y
					if y < lowest:
						lowest = y
						# WHICH PART, not just how far. A number alone sends you
						# tuning the wrong limb — the first fix here went into the
						# arms when the offender was somewhere else entirely.
						culprit = str(mi.get_parent().name)
			var hips := model.get_node_or_null("Hips") as Node3D
			if hips != null:
				drift = maxf(drift, Vector2(hips.global_position.x,
					hips.global_position.z).length())
			var head := model.get_node_or_null(
				NodePath(CharacterModel.PATHS["head"])) as Node3D
			if head != null:
				head_end = head.global_position.y
		print("    %-14s lowest %6.3f m (%s)   head ends %5.3f m   drift %5.2f m"
			% [clip, lowest, culprit, head_end, drift])
		_check(lowest >= FLOOR_TOLERANCE,
			"%s never goes through the floor" % clip)
		_check(head_end <= LYING_HEAD_MAX, "%s ends with the head down" % clip)
		_check(drift <= MAX_DRIFT, "%s stays where it died" % clip)
	model.queue_free()
