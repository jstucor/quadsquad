extends Node3D
## Renders the red dot and 4x scope reticles in-game.
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/sight_look.tscn
const MAIN := preload("res://scenes/main.tscn")

func _ready() -> void:
	GameState.human_players = 1
	GameState.debug_kbm = true
	GameState.mode = GameState.Mode.DEATHMATCH
	GameState.map_index = 0
	var main: Node = MAIN.instantiate()
	add_child(main)
	await _frames(20)
	var p: Player = _find(main)
	for shot in [["reddot", Loadout.Sight.RED_DOT], ["scope4x", Loadout.Sight.SCOPE_4X]]:
		var l := Loadout.new()
		l.adopt_kit(Loadout.Kit.LEGION)
		l.weapon = Loadout.weapon_index(Weapon.Class.SOLDIER)
		l.sight = shot[1]
		p.pending = l
		p._respawn()
		await _frames(6)
		Input.action_press("kb_ads")
		await _frames(12)
		await _grab(shot[0])
		Input.action_release("kb_ads")
		await _frames(4)
	get_tree().quit()

func _find(n: Node) -> Player:
	for c in n.get_children():
		if c is Player: return c
		var f := _find(c)
		if f: return f
	return null

func _grab(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://sight_%s.png" % tag)
	print("wrote %s" % tag)

func _frames(n: int) -> void:
	for _i in n: await get_tree().process_frame
