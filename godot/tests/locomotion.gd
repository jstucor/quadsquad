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


func _ready() -> void:
	print("\n==== locomotion clips ====")
	_check_clips_exist()
	_check_selection()
	print("")
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
func _check_selection() -> void:
	print("\n-- direction picks the clip, on both bodies --")
	var player: Player = PLAYER.instantiate()
	add_child(player)
	var bot: Bot = BOT.instantiate()
	add_child(bot)

	var cases := [
		[Vector2(0.0, -1.0), "walk", "straight forward"],
		[Vector2(0.0, 1.0), "walk_back", "straight back"],
		[Vector2(1.0, 0.0), "strafe_r", "hard right"],
		[Vector2(-1.0, 0.0), "strafe_l", "hard left"],
		# THE WIDE FORWARD BAND. Walking forward at an angle is the commonest
		# input in the game and must not flicker into a sidestep.
		[Vector2(0.5, -1.0), "walk", "forward, drifting right"],
		[Vector2(-0.5, -1.0), "walk", "forward, drifting left"],
		[Vector2(0.6, 1.0), "walk_back", "backing off, drifting right"],
		# ...and past the ratio it does commit, or the sidestep never plays.
		[Vector2(1.0, -0.3), "strafe_r", "mostly right, a little forward"],
	]
	print("  %-30s %-11s %-11s" % ["input", "player", "bot"])
	for c in cases:
		var move: Vector2 = c[0]
		var want: String = c[1]
		var got_p: String = player._ground_clip(move)
		var got_b: String = bot._ground_clip(move)
		print("  %-30s %-11s %-11s" % [c[2], got_p, got_b])
		_ok(got_p == want,
			"%s: the player should play `%s`, played `%s`" % [c[2], want, got_p])
		_ok(got_b == want,
			"%s: the bot should play `%s`, played `%s`" % [c[2], want, got_b])
		_ok(got_p == got_b,
			"%s: player plays `%s` and bot plays `%s` — they must agree"
				% [c[2], got_p, got_b])
	player.queue_free()
	bot.queue_free()
