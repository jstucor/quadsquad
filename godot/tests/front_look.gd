extends Node

## Renders the FRONT SCREEN, in both of its states, to PNGs.
##
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/front_look.tscn
##
## It has to be a LOOK test and not a headless one. Everything this screen is for
## is appearance: whether the live 3D background reads as a body standing in a
## lit room rather than as a grey smear, whether the entry list stays legible
## over it, and whether the wordmark and the figure are fighting each other for
## the same third of the frame. None of that has a number.
##
## The second shot is the LOCAL PLAY step, because a panel that is built once and
## then shown (rather than rebuilt) is exactly the kind of thing that lays out
## correctly the first time and never again — and it is the state a player is in
## when they are answering the only question this screen asks.

const FRONT := preload("res://scenes/front.tscn")


func _ready() -> void:
	# The screen anchors itself FULL_RECT, which is zero if its parent is zero.
	# `menu_look` records the first run of that mistake: the whole layout
	# rendered jammed into the top-left corner, which looks exactly like a broken
	# screen rather than like a broken test.
	var root := get_node(".") as Control
	if root != null:
		root.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.size = get_viewport().get_visible_rect().size
	var front: Control = FRONT.instantiate()
	add_child(front)
	# The body is built and posed on the first frames, and the SubViewport needs
	# a couple more to have rendered anything at all — grabbing too early
	# photographs an empty stage and reads as "the background does not work".
	await _frames(20)
	await _grab("front")

	# Walk into the LOCAL PLAY step the way a player does, through the button's
	# own signal rather than by calling the private handler — a test that reaches
	# past the control is one that keeps passing after the control stops being
	# wired to anything.
	var local := _first_entry(front)
	if local == null:
		print("FAIL: no entry buttons on the front screen")
		get_tree().quit(1)
		return
	local.emit_signal("pressed")
	await _frames(8)
	await _grab("front_local")

	print("front screen rendered: user://front.png, user://front_local.png")
	get_tree().quit()


## The first entry button, depth first. Found by WALKING rather than by index
## into a container, for the reason `menu_look` records about indexing its
## dropdown list: a row that gains an item silently re-points every index past it.
func _first_entry(n: Node) -> Button:
	for c in n.get_children():
		if c is Button:
			return c
		var deeper := _first_entry(c)
		if deeper != null:
			return deeper
	return null


func _grab(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://%s.png" % tag)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
