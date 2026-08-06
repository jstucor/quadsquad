extends Node
## WINDOWED. WHAT THE DRIVER ACTUALLY SEES, from inside each machine.
##
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/vehicle_pov.tscn
##
## The same argument `gunship_pov` makes and for the same reason: a vehicle
## photographed from OUTSIDE (which is all `warmachine_look` ever does) cannot
## show whether the seat is in a usable place. The AT-ST was reported as an
## unusable point of view, and every question in that report — is the camera
## inside the pod or floating over it, does the hull fill the frame, can you see
## the ground you are walking onto, does the sight agree with the gun — is only
## answerable through the driver's OWN camera.

const MAIN := preload("res://scenes/main.tscn")
const VEHICLE := preload("res://scenes/actors/vehicle.tscn")


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

	await _ride("atst", "walker")
	await _ride("", "speeder")
	get_tree().quit()


## Put the player in a machine parked in front of them and photograph the view.
func _ride(row_id: String, tag: String) -> void:
	var p: Player = _find(get_tree().current_scene)
	var v: Node3D = VEHICLE.instantiate()
	get_tree().current_scene.add_child(v)
	if row_id == "":
		v.setup(p.team)
	else:
		v.setup_as(row_id, p.team)
	# Beside the player, on the ground it hovers over.
	v.global_position = p.global_position + Vector3(6.0, 0.0, 0.0)
	await _frames(20)
	v._mount_player(p)
	await _frames(40)
	await _grab("pov_%s_forward" % tag)
	# ...and looking DOWN, which is the view that decides whether you can drive
	# it: the ground immediately in front is what you steer by and what a walker
	# is most likely to have hidden behind its own pod.
	p.set_view_angles(p.rotation.y, deg_to_rad(-28.0))
	await _frames(20)
	await _grab("pov_%s_down" % tag)
	v._eject(true)
	await _frames(20)
	v.queue_free()
	await _frames(4)


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
