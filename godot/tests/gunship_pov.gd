extends Node
## WINDOWED. WHAT THE GUNNER ACTUALLY SEES.
##
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/gunship_pov.tscn
##
## The LAAT was reported as "ninety per cent of the time you cannot see anything
## but the model", and neither of the two causes could be found by looking at the
## gunship from outside — which is the only way `warmachine_look` ever saw it.
## The ball hung on the OUTSIDE of the turn, so aiming at the battle meant aiming
## back through the fuselage; and the seat sits inside an opaque sphere with a
## cradle band across its eyeline, which is invisible from any other viewpoint.
##
## So this shoots down the barrels, through the player's OWN camera — which is
## the only camera with the right cull mask, and therefore the only one that can
## show whether `_hide_shell_from` worked.

const MAIN := preload("res://scenes/main.tscn")


func _ready() -> void:
	GameState.human_players = 1
	GameState.debug_kbm = true
	GameState.mode = GameState.Mode.DEATHMATCH
	GameState.map_index = 0
	var main: Node = MAIN.instantiate()
	add_child(main)
	await _frames(24)
	GameState.match_live = true
	await _frames(10)
	var p: Player = _find(main)
	if p == null:
		push_error("no player")
		get_tree().quit(1)
		return

	# DEPLOY FIRST. Nothing spawns directly (see Player.begin_deploy) — the buy
	# screen is up until the deploy button is pressed, and an earlier version of
	# this photographed that screen instead of the turret.
	# ...and the deploy button does not ARM for `DEPLOY_FLOOR` seconds, so this
	# waits for the state rather than guessing a frame count.
	var guard := 0
	while not p.deploy_armed() and guard < 900:
		await get_tree().process_frame
		guard += 1
	Input.action_press("kb_jump")
	await _frames(8)
	Input.action_release("kb_jump")
	await _frames(30)
	if not p.is_alive():
		push_error("player never deployed")
		get_tree().quit(1)
		return

	var ship: Node3D = preload("res://scripts/gunship.gd").new()
	get_tree().current_scene.add_child(ship)
	ship.begin(p, p.team, 40.0)
	# Let it fly a little way round so the shot is not the one frame it was
	# spawned on — the fault being checked is one that lasted most of a lap.
	await _frames(40)
	await _grab("gunship_pov_early")
	await _frames(150)
	await _grab("gunship_pov_mid")
	await _frames(150)
	await _grab("gunship_pov_late")
	get_tree().quit()


func _find(n: Node) -> Player:
	if n is Player:
		return n
	for c in n.get_children():
		var f := _find(c)
		if f != null:
			return f
	return null


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _grab(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://shots")
	img.save_png("user://shots/%s.png" % name)
	print("wrote %s" % name)
