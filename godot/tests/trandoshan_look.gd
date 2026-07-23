extends Node3D
## Renders the Trandoshan in third person cloaked vs solid, and the thermal
## overlay over an enemy through smoke. Appearance is the thing a headless test
## cannot see.
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/trandoshan_look.tscn

const MAIN := preload("res://scenes/main.tscn")
const BOT := preload("res://scenes/actors/bot.tscn")

func _ready() -> void:
	GameState.human_players = 1
	GameState.debug_kbm = true
	GameState.mode = GameState.Mode.DEATHMATCH
	GameState.map_index = 0
	var main: Node = MAIN.instantiate()
	add_child(main)
	await _frames(20)
	var p: Player = _find(main, "Player") as Player
	if p == null:
		print("no player"); get_tree().quit(1); return
	# Force a Trandoshan build with the thermal sight, deploy it.
	var l := Loadout.new()
	l.adopt_kit(Loadout.Kit.TRANDOSHAN)
	l.weapon = Loadout.weapon_index(Weapon.Class.SOLDIER)
	l.sight = Loadout.Sight.THERMAL
	l.gadget = Loadout.Gadget.CLOAK
	p.pending = l
	p._respawn()          # actually deploy, past the buy screen
	await _frames(4)
	# An enemy in front.
	var bot: Bot = BOT.instantiate()
	p.get_parent().add_child(bot)
	bot.setup(null, 1, 2)
	bot.global_position = p.global_position - p.global_transform.basis.z * 12.0
	await _frames(6)
	# Aim (raise the thermal), draw.
	Input.action_press("kb_ads")
	await _frames(10)
	await _grab("thermal")
	Input.action_release("kb_ads")
	get_tree().quit()

func _find(n: Node, cls: String) -> Node:
	for c in n.get_children():
		if c.get_class() == cls or (c.get_script() and str(c.get_script().resource_path).ends_with(cls.to_lower()+".gd")):
			return c
		var f := _find(c, cls)
		if f: return f
	return null

func _grab(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://%s.png" % tag)
	print("wrote %s" % ProjectSettings.globalize_path("user://%s.png" % tag))

func _frames(n: int) -> void:
	for _i in n: await get_tree().process_frame
