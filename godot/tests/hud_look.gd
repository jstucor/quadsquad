extends Node
## THE HUD, PHOTOGRAPHED. The health gauge and the ability gauges are drawn in
## code (`HealthGauge`, `AbilityGauge`), which means every one of their states —
## full, half, spent, refilling, active, flashing — is a branch nothing else in
## the test suite can see. This renders a real match's HUD and then walks a
## player through those states so they can be judged by eye.
##
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/hud_look.tscn
##
## WINDOWED, like every other look test: --headless draws nothing.

const MAIN := preload("res://scenes/main.tscn")

var _main: Node
var _me: Player


func _ready() -> void:
	GameState.human_players = 1
	GameState.team_size = 2
	GameState.team_count = 2
	GameState.mode = GameState.Mode.DEATHMATCH
	GameState.class_mode = GameState.ClassMode.CUSTOM
	GameState.map_index = 0
	_main = MAIN.instantiate()
	add_child(_main)
	await _frames(50)
	_me = _find_player(_main)
	if _me == null:
		print("no player spawned")
		get_tree().quit()
		return
	# A build with two gadgets on it, so both slots draw: the Mandalorian carries
	# a jetpack and a cable, which are the two gauges with the most states.
	_me.pending.adopt_kit(Loadout.Kit.MANDALORIAN)
	_me.pending.gadget = Loadout.Gadget.JETPACK
	_me.pending.gadget2 = Loadout.Gadget.CABLE
	_me._respawn()
	GameState.match_live = true
	await _frames(12)
	await _grab("1_full")

	# Hurt, so the bar shows a chip falling and then the low-health warning.
	# Sized to leave the player ALIVE: kill them and every shot after this is a
	# photograph of the buy screen.
	_me.health = _me.max_health
	_me.take_damage(_me.max_health * 0.35, null)
	await _frames(4)
	await _grab("2_hit")
	_me.take_damage(_me.max_health * 0.45, null)
	await _frames(30)
	await _grab("3_low")

	# Spend both gadgets: the gauges should flip to the player colour and start
	# refilling from the bottom.
	_me.jet_fuel = 0.35
	_me._start_gadget_cd(1, Player.CABLE_COOLDOWN * 0.8)
	_me.gear_changed.emit()
	await _frames(10)
	await _grab("4_spent")

	# ...and a blade in hand, which adds the guard gauge.
	_me.pending.adopt_kit(Loadout.Kit.FORCE)
	_me._respawn()
	await _frames(20)
	await _grab("5_saber")

	# THE CONTACT SHEET. Every icon is drawn blind, in code, and in the match it
	# is 46 pixels in one corner of one viewport — laying the whole set out side
	# by side at three charge levels is the only way to see whether they are
	# telling each other apart, which is their entire job.
	_main.queue_free()
	await _frames(4)
	await _icon_sheet()
	print("HUD states rendered")
	get_tree().quit()


const SHEET := [
	Loadout.Gadget.JETPACK, Loadout.Gadget.CABLE, Loadout.Gadget.CLOAK,
	Loadout.Gadget.SHIELD, Loadout.Gadget.TURRET, Loadout.Gadget.MORTAR,
	Loadout.Gadget.SCAN_DART, Loadout.Gadget.WRIST_ROCKET,
	Loadout.Gadget.FORCE_PUSH, Loadout.Gadget.FORCE_PULL,
	Loadout.Gadget.FORCE_LEAP, Loadout.Gadget.FORCE_LIGHTNING,
	Loadout.Gadget.DASH, Loadout.Gadget.GRENADE_FRAG,
	Loadout.Gadget.GRENADE_STICKY, Loadout.Gadget.GRENADE_SMOKE,
]


func _icon_sheet() -> void:
	var back := ColorRect.new()
	back.color = Color(0.10, 0.11, 0.14)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var grid := GridContainer.new()
	grid.columns = SHEET.size()
	grid.position = Vector2(40, 60)
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	add_child(grid)
	# Three rows: ready, half charged, and spent — the three states that have to
	# be distinguishable at a glance.
	for fill: float in [1.0, 0.45, 0.0]:
		for icon: int in SHEET:
			var g := AbilityGauge.new()
			grid.add_child(g)
			g.preview(icon, fill, Color(0.92, 0.26, 0.24))
	await _frames(6)
	await _grab("6_icons")


func _grab(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://hud_%s.png" % tag)
	print("wrote hud_%s" % tag)


func _find_player(n: Node) -> Player:
	if n is Player:
		return n
	for c in n.get_children():
		var found := _find_player(c)
		if found != null:
			return found
	return null


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
