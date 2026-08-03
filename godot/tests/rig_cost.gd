extends Node
## WHAT THE RIG COSTS, because house rule 17 says measure and the wrists and
## ankles were added on the argument that they are cheap.
##
## TWO TRAPS THIS TEST WALKED INTO FIRST, both recorded because the wrong version
## of each looks perfectly reasonable:
##
##   1. "Time the frames while everything animates" measures the WHOLE FRAME, not
##      the animation. It came back at 6.8 ms for 24 bodies and that number is
##      true and says nothing — it is the engine doing everything. The cost of
##      the animation system is the DIFFERENCE between playing and paused, so
##      that is what is reported: an A/B, the same discipline the render harness
##      uses for anything GPU-side.
##
##   2. Building 24 bodies of 24 DIFFERENT styles prices the worst case in the
##      game, not the normal one. `Meshes.chamfer_box` caches per SIZE, so the
##      first body of a style pays for every mesh it invents and the rest of that
##      style pay for none. A squad of clones and a line-up of one of everything
##      are different questions and both are asked below.
##
## Headless, so the renderer does nothing and what is left is the script and the
## animation system — which is exactly what more joints costs. The meshes did not
## change when the joints were added (the new ones sit where the hand and boot
## boxes already were), so nothing here is about drawing.
##
## Run:  godot --headless --path godot tests/rig_cost.tscn

## Overridable, because "is it free at 24" and "is it free at a hundred" are
## different questions and MASSIVE only asks the second one.
##   QS_RIG_BODIES=100 godot --headless --path godot tests/rig_cost.tscn
static var BODIES := int(OS.get_environment("QS_RIG_BODIES")) \
	if OS.get_environment("QS_RIG_BODIES") != "" else 24
const FRAMES := 90
const CLIPS := ["idle", "walk", "run", "crouch_walk", "guard_idle"]

var _models: Array[CharacterModel] = []


func _ready() -> void:
	print("\n=== RIG COST ===\n")
	print("  %d rotation tracks + 2 position tracks per body"
		% CharacterModel.PATHS.size())
	print("  (11 of those tracks predate the wrists and ankles)\n")

	# BUILD, the normal case: a squad wearing the same unit, so the mesh cache is
	# warm after the first. This is what a team fill actually does.
	# NOT COMPARABLE TO `perf.tscn`'S SPAWN FIGURE, and it would be easy to read
	# it as a regression against that. A body here is built TWICE: `_ready` builds
	# the default style and `set_style` then frees the whole Hips subtree and
	# builds the real one. The game does the same thing on every deploy, so the
	# number is honest — it is just answering a different question.
	var warm := await _build_cost(false)
	print("  build, one style     %6.2f ms each   (a squad of the same unit)" % warm)
	# ...and the worst case: every body a different unit, every mesh size new.
	var cold := await _build_cost(true)
	print("  build, all different %6.2f ms each   (first of each style pays for"
		% cold)
	print("                                       its own mesh sizes)")

	# TICK, as an A/B. Everything else about the frame is identical between the
	# two passes, so the difference is the animation and nothing else.
	for i in _models.size():
		var p: AnimationPlayer = _models[i].anim_player
		if p != null:
			p.play(CLIPS[i % CLIPS.size()])
	var playing := await _frame_cost()
	for m in _models:
		if m.anim_player != null:
			m.anim_player.pause()
	var paused := await _frame_cost()
	var cost := playing - paused
	print("\n  frame, animating     %6.3f ms" % playing)
	print("  frame, paused        %6.3f ms" % paused)
	print("  ANIMATION            %6.3f ms for %d bodies  (%.4f ms each)"
		% [cost, BODIES, cost / float(BODIES)])

	# The death clips, built ON DEMAND — this number is why.
	var t := Time.get_ticks_usec()
	for m in _models:
		m.build_death_clips()
	var death := (Time.get_ticks_usec() - t) / 1000.0 / float(BODIES)
	print("\n  death clips          %6.2f ms each, built only by a corpse" % death)
	print("  ...a living body would otherwise pay that on every single deploy,")
	print("  to use one of them once.")
	print("\n==== MEASURED ====")
	get_tree().quit(0)


func _build_cost(mixed: bool) -> float:
	for m in _models:
		m.queue_free()
	_models.clear()
	await get_tree().process_frame
	var t := Time.get_ticks_usec()
	for i in BODIES:
		var m := CharacterModel.new()
		add_child(m)
		m.set_style(i % CharacterModel.Style.size() if mixed
			else CharacterModel.Style.CLONE)
		_models.append(m)
	var ms := (Time.get_ticks_usec() - t) / 1000.0 / float(BODIES)
	await get_tree().process_frame
	return ms


func _frame_cost() -> float:
	# A few frames thrown away first: the one right after a state change carries
	# whatever that change deferred, and it is not what a steady match costs.
	for i in 5:
		await get_tree().process_frame
	var t := Time.get_ticks_usec()
	for f in FRAMES:
		await get_tree().process_frame
	return (Time.get_ticks_usec() - t) / 1000.0 / float(FRAMES)
